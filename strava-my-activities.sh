#!/bin/sh
# StravaStats for OpenWrt — My Activities Dashboard
# -------------------------------------------------
# Fetches the authenticated athlete's own activities from Strava, accumulates
# them in a persistent store (deduped by Strava activity ID), and renders a
# static HTML dashboard with year/month/sport-type filters into uhttpd's web
# root. Unlike the club leaderboard, individual activities carry real dates
# (start_date_local) so no "first-seen" approximation is needed.
# Designed for low-RAM MIPS routers. Pure POSIX sh / BusyBox; deps: curl + jq.
#
# Run by cron once a day. See README.md for setup.

set -eu

STRAVA_LIBDIR="$(dirname "$0")"
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-lib.sh"

CONFIG="${STRAVA_MY_CONFIG:-/etc/strava-my-activities.conf}"

[ -f "$CONFIG" ] || die "config not found: $CONFIG (copy config-my.example and edit it)"
# shellcheck disable=SC1090
. "$CONFIG"

: "${STRAVA_CLIENT_ID:?set STRAVA_CLIENT_ID in $CONFIG}"
: "${STRAVA_CLIENT_SECRET:?set STRAVA_CLIENT_SECRET in $CONFIG}"
: "${STRAVA_REFRESH_TOKEN:?set STRAVA_REFRESH_TOKEN in $CONFIG}"

TOKEN_REFRESH_MARGIN="${STRAVA_TOKEN_REFRESH_MARGIN:-600}"
MAX_PAGES="${STRAVA_MY_MAX_PAGES:-20}"
PER_PAGE="${STRAVA_MY_PER_PAGE:-200}"
WEB_DIR="${STRAVA_MY_WEB_DIR:-/www/strava/me}"
STATE_DIR="${STRAVA_MY_STATE_DIR:-/usr/lib/strava-my-activities}"

# Bike service tracker (see sections 6b/6c). The dashboard is a static page, but
# unlike everything else here it WRITES data back — through a tiny CGI that reads
# and writes a single JSON file. BIKE_DATA must live on persistent storage (off
# the RAM-backed /tmp,/var); CGI_DIR is uhttpd's default CGI prefix, /www/cgi-bin.
BIKE_DATA="${STRAVA_MY_BIKE_DATA:-$STATE_DIR/bike-service.json}"
BIKE_ASSIGN="${STRAVA_MY_BIKE_ASSIGN:-$STATE_DIR/bike-assignments.json}"
CGI_DIR="${STRAVA_MY_CGI_DIR:-/www/cgi-bin}"
DEFAULT_BIKE_NAME="${STRAVA_MY_DEFAULT_BIKE_NAME:-My Bike}"

# Per-activity detail backfill (rate-limit aware — see section 3b).
DETAIL_DIR="${STRAVA_MY_DETAIL_DIR:-$WEB_DIR/details}"        # one <id>.json per activity
DETAIL_MAX_PER_RUN="${STRAVA_MY_DETAIL_MAX_PER_RUN:-40}"      # cap detail fetches per run; 0 disables
DETAIL_SLEEP="${STRAVA_MY_DETAIL_SLEEP:-1}"                   # seconds between detail fetches (be gentle)
DETAIL_SKIP="$STATE_DIR/detail-skip.txt"                     # ids Strava said are gone; never retried

# Historical sync (see section 3): each run rebuilds the store from the feed so
# edits propagate and deleted activities are pruned. Set to 0 to disable only the
# (destructive) deletion of activities missing from the feed; additions and
# in-place updates of still-present activities always happen regardless.
PRUNE_DELETED="${STRAVA_MY_PRUNE_DELETED:-1}"
IMPORT_ENABLED="${STRAVA_MY_IMPORT_ENABLED:-1}"
BIRTH_YEAR="${STRAVA_MY_BIRTH_YEAR:-}"
ATHLETE_AGE=""
[ -n "$BIRTH_YEAR" ] && ATHLETE_AGE="$(( $(date '+%Y') - BIRTH_YEAR ))"

command -v curl >/dev/null 2>&1 || die "curl not installed (apk add curl ca-bundle  /  opkg install curl ca-bundle)"
command -v jq   >/dev/null 2>&1 || die "jq not installed (apk add jq  /  opkg install jq)"

mkdir -p "$WEB_DIR" "$STATE_DIR"

TOKEN_STATE="$STATE_DIR/token.json"
STORE="$STATE_DIR/activities.ndjson"
WEATHER_CACHE="$STATE_DIR/weather-cache.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/strava-me.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if [ "$IMPORT_ENABLED" != "0" ]; then

# --- 1. Ensure a valid access token (see strava-lib.sh) -------------------
ensure_access_token

# --- 2. Page through the athlete's own activities feed ---------------------
# The /athlete/activities endpoint returns full activity objects with real IDs
# and real dates (start_date_local) — no "first-seen" approximation needed.
log "fetching athlete activities (up to $MAX_PAGES pages of $PER_PAGE)..."
: > "$TMP/all.ndjson"
page=1
# Whether pagination reached the natural end of the feed (an empty or short page)
# rather than stopping at MAX_PAGES. Only a full traversal lets section 3 treat a
# stored activity that is missing from the feed as deleted; a capped run can only
# prune within the date window it actually saw.
reached_end=0
while [ "$page" -le "$MAX_PAGES" ]; do
  curl -fsS "https://www.strava.com/api/v3/athlete/activities?per_page=$PER_PAGE&page=$page" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -o "$TMP/page.json" || die "activities fetch failed (page $page)"

  count="$(jq 'length' "$TMP/page.json" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || { log "page $page empty, stopping"; reached_end=1; break; }

  jq -c '.[]' "$TMP/page.json" >> "$TMP/all.ndjson"
  log "page $page: $count activities"

  [ "$count" -lt "$PER_PAGE" ] && { log "short page, stopping"; reached_end=1; break; }
  page=$((page + 1))
done

jq -s '.' "$TMP/all.ndjson" > "$TMP/fetched.json"
TOTAL="$(jq 'length' "$TMP/fetched.json")"
log "fetched $TOTAL activities total"

# --- 3. Sync the persistent store with the feed ----------------------------
# The store is keyed by Strava activity ID (individual activities always have a
# numeric id, unlike the club feed). Each run REBUILDS the store from the feed so
# the dashboard reflects edits and removals, not just additions:
#   * new activities are added;
#   * activities still present are refreshed from the feed (a rename, a corrected
#     sport type, a recalculated distance/time all propagate);
#   * activities missing from the feed are pruned as deleted — but only when it is
#     safe to conclude they were really removed: we reached the end of the feed
#     (full history seen), or, on a capped run, they fall inside the date window we
#     actually fetched. Older-than-window activities on a capped run are kept.
# Pruning is skipped entirely when the feed came back empty (likely a transient
# error, not a mass deletion) or when STRAVA_MY_PRUNE_DELETED=0 (append-only mode).
[ -f "$STORE" ] || : > "$STORE"

# Project each fetched activity to the compact store record.
jq '[ .[] | {
      id:                     .id,
      date:                   ((.start_date_local // .start_date // "") | .[0:10]),
      name:                   (.name // ""),
      sport_type:             (.sport_type // .type // ""),
      gear_id:                (.gear_id // null),
      distance:               (.distance // 0),
      moving_time:            (.moving_time // 0),
      elapsed_time:           (.elapsed_time // 0),
      total_elevation_gain:   (.total_elevation_gain // 0),
      average_speed:          (.average_speed // 0),
      max_speed:              (.max_speed // 0),
      average_heartrate:      (.average_heartrate // null),
      max_heartrate:          (.max_heartrate // null),
      average_cadence:        (.average_cadence // null),
      average_watts:          (.average_watts // null),
      weighted_average_watts: (.weighted_average_watts // null),
      max_watts:              (.max_watts // null),
      kilojoules:             (.kilojoules // null),
      average_temp:           (.average_temp // null),
      suffer_score:           (.suffer_score // null),
      elev_high:              (.elev_high // null),
      elev_low:               (.elev_low // null)
    } ]' "$TMP/fetched.json" > "$TMP/fetched_proj.json"

# Only trust deletion-pruning when the feed actually returned activities; an empty
# feed is treated as "no information", never "everything was deleted".
do_prune=0
if [ "$PRUNE_DELETED" != "0" ] && [ "$TOTAL" -gt 0 ]; then do_prune=1; fi

jq -n \
  --slurpfile stored "$STORE" \
  --slurpfile fetched "$TMP/fetched_proj.json" \
  --argjson reachedEnd "$reached_end" \
  --argjson doPrune "$do_prune" '
  # Fields that represent a real change to the activity (ignoring schema drift in
  # the optional metric fields) — used to decide whether to refresh detail cache.
  def cmpkeys: { name, distance, moving_time, elapsed_time, total_elevation_gain, sport_type, date, gear_id };
  ($fetched[0] // [])                                  as $F
  | $stored                                            as $S
  | ($F | map({ (.id|tostring): . }) | add // {})      as $fById
  | ($S | map({ (.id|tostring): . }) | add // {})      as $sById
  | ([ $F[] | .date | select(. != null and . != "") ] | min) as $minDate
  | ( $S | map(
        . as $s
        | ($fById[($s.id|tostring)]) as $f
        | if $f == null then
            # Stored but absent from this feed fetch.
            { rec: $s, status: "absent",
              keep: ( if $doPrune == 0 then true
                      elif $reachedEnd == 1 then false
                      else (($s.date // "") == "" or $minDate == null or ($s.date < $minDate)) end ) }
          else
            # Still present: take the fresh feed version (propagates edits).
            { rec: $f, keep: true,
              status: (if ($f|cmpkeys) != ($s|cmpkeys) then "changed" else "same" end) }
          end
    ) ) as $eval
  | {
      store:   ( [ $F[] | select($sById[(.id|tostring)] == null) ]   # brand-new from the feed
                 + [ $eval[] | select(.keep) | .rec ] ),             # refreshed + kept-out-of-window
      added:   [ $F[] | select($sById[(.id|tostring)] == null) | .id ],
      changed: [ $eval[] | select(.status == "changed") | .rec.id ],
      deleted: [ $eval[] | select(.keep | not)          | .rec.id ]
    }
' > "$TMP/merge.json"

jq -c '.store[]'               "$TMP/merge.json" > "$TMP/store.new"
jq -r '.deleted[]? | tostring' "$TMP/merge.json" > "$TMP/deleted_ids.txt"
jq -r '.changed[]? | tostring' "$TMP/merge.json" > "$TMP/changed_ids.txt"
ADDED="$(jq '.added   | length' "$TMP/merge.json")"
CHANGED="$(jq '.changed | length' "$TMP/merge.json")"
DELETED="$(jq '.deleted | length' "$TMP/merge.json")"

mv "$TMP/store.new" "$STORE"
TOTAL_STORED="$(wc -l < "$STORE" | tr -d ' ')"
if [ "$do_prune" -eq 0 ] && [ "$PRUNE_DELETED" != "0" ]; then
  log "store: +$ADDED new, ~$CHANGED updated, pruning skipped (empty feed), $TOTAL_STORED total"
else
  log "store: +$ADDED new, ~$CHANGED updated, -$DELETED removed, $TOTAL_STORED total"
fi

# Weather backfill: for null-temp activities not yet in the cache, look up
# Open-Meteo. The cache ($WEATHER_CACHE) persists across runs so each activity
# is only queried once even though the Strava store is rebuilt every run.
# Coordinates come from the cached detail JSON's start_latlng, with WEATHER_LAT/
# WEATHER_LON as a fallback for activities whose detail hasn't downloaded yet.
[ -f "$WEATHER_CACHE" ] || printf '{}' > "$WEATHER_CACHE"
jq -c 'select(.average_temp == null) | {id: (.id|tostring), date}' "$STORE" \
| while IFS= read -r _entry; do
    _wid=$(printf '%s' "$_entry" | jq -r '.id')
    _wd=$(printf '%s' "$_entry" | jq -r '.date')
    jq -e --arg id "$_wid" '.[$id] != null' "$WEATHER_CACHE" >/dev/null 2>&1 && continue
    _wlat="" _wlon=""
    if [ -f "$DETAIL_DIR/$_wid.json" ]; then
        _wlat=$(jq -r '.start_latlng[0] // ""' "$DETAIL_DIR/$_wid.json" 2>/dev/null || true)
        _wlon=$(jq -r '.start_latlng[1] // ""' "$DETAIL_DIR/$_wid.json" 2>/dev/null || true)
    fi
    [ -z "$_wlat" ] && _wlat="${WEATHER_LAT:-}"
    [ -z "$_wlon" ] && _wlon="${WEATHER_LON:-}"
    [ -n "$_wlat" ] && [ -n "$_wlon" ] || continue
    _wt=$(fetch_weather_temp "$_wlat" "$_wlon" "$_wd" || true)
    [ -n "$_wt" ] || continue
    jq --arg id "$_wid" --argjson t "$_wt" '.[$id] = $t' "$WEATHER_CACHE" \
        > "$WEATHER_CACHE.tmp" && mv "$WEATHER_CACHE.tmp" "$WEATHER_CACHE"
done
log "weather: cache has $(jq 'length' "$WEATHER_CACHE") entries"

# --- 3a. Reconcile detail files with the synced store ----------------------
# Deleted activities: drop their cached detail JSON (it is web-served) and any
# skip-list entry. Changed activities: invalidate the cached detail so section 3b
# re-fetches a fresh copy (newest-first, so recent edits refresh soonest).
if [ -s "$TMP/deleted_ids.txt" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    rm -f "$DETAIL_DIR/$id.json"
  done < "$TMP/deleted_ids.txt"
  if [ -f "$DETAIL_SKIP" ]; then
    grep -vxF -f "$TMP/deleted_ids.txt" "$DETAIL_SKIP" > "$TMP/skip.new" || true
    mv "$TMP/skip.new" "$DETAIL_SKIP"
  fi
  log "detail: removed cached files for $DELETED deleted activities"
fi
if [ -s "$TMP/changed_ids.txt" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    rm -f "$DETAIL_DIR/$id.json"
  done < "$TMP/changed_ids.txt"
  log "detail: invalidated $CHANGED changed activities for re-fetch"
fi

# Cross-check every stored gear_id against the cached detail file's .gear.id.
# Catches gear changes that silently propagated to the feed (and thus to the store)
# without triggering a cmpkeys diff — detail file stays stale until we notice here.
if [ -d "$DETAIL_DIR" ] && [ -f "$STORE" ]; then
  jq -r 'select(.gear_id != null) | "\(.id)\t\(.gear_id)"' "$STORE" > "$TMP/store_gears.tsv"
  if [ -s "$TMP/store_gears.tsv" ]; then
    gear_stale=0
    while IFS='	' read -r gid store_gear; do
      detail="$DETAIL_DIR/$gid.json"
      [ -f "$detail" ] || continue
      detail_gear="$(jq -r '.gear.id // ""' "$detail" 2>/dev/null || true)"
      if [ "$store_gear" != "$detail_gear" ]; then
        rm -f "$detail"
        gear_stale=$((gear_stale + 1))
      fi
    done < "$TMP/store_gears.tsv"
    [ "$gear_stale" -gt 0 ] && log "detail: invalidated $gear_stale activities with stale gear (re-fetch next)"
  fi
fi

# --- 3b. Backfill per-activity detail JSON (rate-limit aware) --------------
# For every activity in the store we fetch the full object from
# GET /activities/{id} and save it as $DETAIL_DIR/<id>.json. This covers all
# historical activities and any new ones, but Strava's read API is rate limited
# (default 100 requests / 15 min, 1000 / day for a non-premium app), so we never
# fetch them all at once: each run fetches at most DETAIL_MAX_PER_RUN that don't
# yet have a file, newest first, sleeping DETAIL_SLEEP between calls. Over enough
# daily cron runs the whole history backfills; new activities are picked up the
# day after they first appear. State is the presence of the per-id file plus a
# skip list of ids Strava reported gone (404/410) so we don't retry them forever.
[ -f "$DETAIL_SKIP" ] || : > "$DETAIL_SKIP"   # ids Strava said are gone; never retried

if [ "$DETAIL_MAX_PER_RUN" -gt 0 ]; then
  mkdir -p "$DETAIL_DIR"
  # Stored ids, newest first, so recent activities get their detail soonest.
  jq -s -r 'sort_by(.date) | reverse | .[] | select(.id != null) | .id' "$STORE" > "$TMP/ids.txt"

  saved=0      # detail files written this run
  tried=0      # API requests spent this run (caps against the rate limit)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ -f "$DETAIL_DIR/$id.json" ] && continue                 # already have it
    grep -qxF "$id" "$DETAIL_SKIP" && continue                # known gone, skip
    if [ "$tried" -ge "$DETAIL_MAX_PER_RUN" ]; then
      log "detail backfill: hit cap ($DETAIL_MAX_PER_RUN requests); remaining will continue next run"
      break
    fi

    tried=$((tried + 1))
    code="$(curl -sS -o "$TMP/detail.json" -w '%{http_code}' \
      "https://www.strava.com/api/v3/activities/$id?include_all_efforts=false" \
      -H "Authorization: Bearer $ACCESS_TOKEN" || echo 000)"
    case "$code" in
      200)
        # Validate it parses before committing it to the (web-served) detail dir.
        if jq -e . "$TMP/detail.json" >/dev/null 2>&1; then
          mv "$TMP/detail.json" "$DETAIL_DIR/$id.json"
          saved=$((saved + 1))
        else
          log "detail backfill: activity $id returned unparseable body; will retry next run"
        fi
        ;;
      404|410)
        log "detail backfill: activity $id gone (HTTP $code); adding to skip list"
        echo "$id" >> "$DETAIL_SKIP"
        ;;
      429)
        log "detail backfill: rate limited (HTTP 429) on activity $id; stopping for this run"
        break
        ;;
      401)
        log "detail backfill: unauthorized (HTTP 401) — token/scope issue; stopping"
        break
        ;;
      *)
        log "detail backfill: activity $id returned HTTP $code; stopping to be safe"
        break
        ;;
    esac

    [ "$DETAIL_SLEEP" -gt 0 ] && sleep "$DETAIL_SLEEP"
  done < "$TMP/ids.txt"

  DETAIL_HAVE="$(ls -1 "$DETAIL_DIR" 2>/dev/null | grep -c '\.json$' || true)"
  log "detail backfill: +$saved saved ($tried requests) this run, $DETAIL_HAVE/$TOTAL_STORED activities have detail"
else
  log "detail backfill: disabled (STRAVA_MY_DETAIL_MAX_PER_RUN=0)"
fi

else
  log "import disabled (STRAVA_MY_IMPORT_ENABLED=0) — re-rendering from existing store"
fi
TOTAL_STORED="$(wc -l < "$STORE" 2>/dev/null | tr -d ' ' || echo 0)"

# --- 4. Emit activities.json for the dashboard ----------------------------
# Flat list of all stored activities, sorted newest-first. The browser handles
# all year/month/sport-type filtering; no server-side aggregation needed.
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ids that currently have a detail file, so the dashboard can link to them.
ls -1 "$DETAIL_DIR" 2>/dev/null | grep -E '^[0-9]+\.json$' | cut -d. -f1 \
  | jq -Rn '[inputs]' > "$TMP/detail_ids.json"

[ -f "$BIKE_ASSIGN" ] || printf '{}' > "$BIKE_ASSIGN"
cp "$BIKE_ASSIGN" "$TMP/bike-assign.json"

# Historical backfill: the store is append-only, so activities saved before the
# richer fields were added lack them. Build an id -> scalars map from the detail
# files (which backfill the full history over daily runs) and overlay it onto
# each store record below. Project to scalars immediately so memory stays modest
# even with a few hundred small detail files.
if ls "$DETAIL_DIR"/*.json >/dev/null 2>&1; then
  jq -s '
    map(select(.id != null) | {
      (.id|tostring): {
        elapsed_time:           (.elapsed_time // null),
        max_speed:              (.max_speed // null),
        average_heartrate:      (.average_heartrate // null),
        max_heartrate:          (.max_heartrate // null),
        average_cadence:        (.average_cadence // null),
        average_watts:          (.average_watts // null),
        weighted_average_watts: (.weighted_average_watts // null),
        max_watts:              (.max_watts // null),
        kilojoules:             (.kilojoules // null),
        average_temp:           (.average_temp // null),
        suffer_score:           (.suffer_score // null),
        calories:               (.calories // null)
      }
    }) | add // {}
  ' "$DETAIL_DIR"/*.json > "$TMP/enrich.json"
else
  echo '{}' > "$TMP/enrich.json"
fi

# Gear (bike) names: detailed activities carry a .gear object with the gear's id
# and human name. Build a gear_id -> { name } map so the bike-service page can
# label a bike by its Strava gear instead of the opaque "b1234567" id. Best
# effort — gear names only appear once the relevant detail files have backfilled.
if ls "$DETAIL_DIR"/*.json >/dev/null 2>&1; then
  jq -s '
    map(.gear | select(. != null and .id != null) | { (.id): { name: (.name // .id) } })
    | add // {}
  ' "$DETAIL_DIR"/*.json > "$TMP/gears.json"
else
  echo '{}' > "$TMP/gears.json"
fi

jq -s --arg generatedAt "$GENERATED_AT" \
  --arg athleteAge "$ATHLETE_AGE" \
  --slurpfile det "$TMP/detail_ids.json" \
  --slurpfile enr "$TMP/enrich.json" \
  --slurpfile gears "$TMP/gears.json" \
  --slurpfile assigns "$TMP/bike-assign.json" \
  --slurpfile wcache "$WEATHER_CACHE" '
  ( ($det[0] // []) | map({ (.): true }) | add // {} ) as $have
  | ($enr[0] // {}) as $enrich
  | ($assigns[0] // {}) as $A
  | ($wcache[0] // {}) as $W
  | {
    generatedAt: $generatedAt,
    athleteAge: (if $athleteAge == "" then null else ($athleteAge | tonumber) end),
    gears: ($gears[0] // {}),
    activities: [
      .[]
      | ($enrich[(.id | tostring)] // {}) as $e
      | ($A[(.id | tostring)] // .gear_id) as $bike
      | {
          id:                     .id,
          date:                   .date,
          name:                   .name,
          sport_type:             .sport_type,
          gear_id:                $bike,
          distance:               (.distance // 0),
          moving_time:            (.moving_time // 0),
          elapsed_time:           ((.elapsed_time // $e.elapsed_time) // 0),
          total_elevation_gain:   (.total_elevation_gain // 0),
          average_speed:          (.average_speed // 0),
          max_speed:              ((.max_speed // $e.max_speed) // 0),
          average_heartrate:      (.average_heartrate // $e.average_heartrate),
          max_heartrate:          (.max_heartrate // $e.max_heartrate),
          average_cadence:        (.average_cadence // $e.average_cadence),
          average_watts:          (.average_watts // $e.average_watts),
          weighted_average_watts: (.weighted_average_watts // $e.weighted_average_watts),
          max_watts:              (.max_watts // $e.max_watts),
          kilojoules:             (.kilojoules // $e.kilojoules),
          average_temp:           (.average_temp // $e.average_temp // $W[(.id|tostring)]),
          suffer_score:           (.suffer_score // $e.suffer_score),
          calories:               (.calories // $e.calories),
          detail:                 (($have[(.id | tostring)]) // false)
        }
    ] | sort_by(.date) | reverse
  }
' "$STORE" > "$WEB_DIR/activities.json"

log "wrote $WEB_DIR/activities.json ($TOTAL_STORED activities)"

# --- 5. Render the static HTML dashboard (see strava-my-html-dashboard.sh) -
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-html-dashboard.sh"

# --- 6a. Render the per-activity detail page (see strava-my-html-detail.sh) -
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-html-detail.sh"

# --- 6b+c. Render bike-service page + install CGI (see strava-my-html-bike.sh) -
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-html-bike.sh"

# --- 6d. Render personal stats summary (see strava-my-html-stats.sh) ---------
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-html-stats.sh"

log "wrote $WEB_DIR/index.html, $WEB_DIR/activity.html, $WEB_DIR/stats.html and $WEB_DIR/activities.json"
log "done."
