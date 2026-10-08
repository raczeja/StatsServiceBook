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

STRAVA_SOURCE="${STRAVA_MY_SOURCE:-api}"
case "$STRAVA_SOURCE" in
  api)
    : "${STRAVA_CLIENT_ID:?set STRAVA_CLIENT_ID in $CONFIG}"
    : "${STRAVA_CLIENT_SECRET:?set STRAVA_CLIENT_SECRET in $CONFIG}"
    : "${STRAVA_REFRESH_TOKEN:?set STRAVA_REFRESH_TOKEN in $CONFIG}"
    ;;
  scrape)
    : "${STRAVA_SESSION_COOKIE:?set STRAVA_SESSION_COOKIE in $CONFIG (required for STRAVA_MY_SOURCE=scrape — copy _strava4_session from browser DevTools → Application → Cookies → strava.com)}"
    ;;
  *)
    die "STRAVA_MY_SOURCE must be 'api' or 'scrape', got: $STRAVA_SOURCE"
    ;;
esac

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
GOALS_DATA="${RIDE_GOALS_DATA:-${STRAVA_MY_GOALS_DATA:-$STATE_DIR/ride-goals.json}}"
CGI_DIR="${STRAVA_MY_CGI_DIR:-/www/cgi-bin}"
DEFAULT_BIKE_NAME="${STRAVA_MY_DEFAULT_BIKE_NAME:-My Bike}"
CURRENCY="${STRAVA_MY_CURRENCY:-PLN}"
BIKE_EMAIL="${STRAVA_MY_BIKE_EMAIL:-}"
BIKE_EMAIL_STATE="${STRAVA_MY_BIKE_EMAIL_STATE:-$STATE_DIR/bike-email-state.json}"

# Per-activity detail backfill (rate-limit aware — see section 3b).
DETAIL_DIR="${STRAVA_MY_DETAIL_DIR:-$WEB_DIR/details}"        # one <id>.json per activity
DETAIL_MAX_PER_RUN="${STRAVA_MY_DETAIL_MAX_PER_RUN:-40}"      # cap detail fetches per run; 0 disables
DETAIL_SLEEP="${STRAVA_MY_DETAIL_SLEEP:-1}"                   # seconds between detail fetches (be gentle)
GPX_MAX_PER_RUN="${STRAVA_MY_GPX_MAX_PER_RUN:-5}"            # cap GPX-only retries per run (spread over days)
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
_RUN_LOG="$TMP/run-log.txt"
_LIVE_LOG="$WEB_DIR/strava-sync-live.log"
_LIVE_LOG_ACTIVE=""
log() { logger -t strava "$*"; printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(basename "$0")" "$*" | tee -a "$_RUN_LOG" ${_LIVE_LOG_ACTIVE:+"$_LIVE_LOG"}; }
LOCKFILE="${TMPDIR:-/tmp}/strava-my-activities.lock"
if ! mkdir "$LOCKFILE" 2>/dev/null; then
  _lock_pid="$(cat "$LOCKFILE/pid" 2>/dev/null || true)"
  if [ -n "$_lock_pid" ] && kill -0 "$_lock_pid" 2>/dev/null; then
    log "another instance is already running (PID $_lock_pid, $LOCKFILE); exiting"
    exit 0
  else
    log "stale lock found (PID ${_lock_pid:-unknown} not running); removing and continuing"
    rm -rf "$LOCKFILE"
    mkdir "$LOCKFILE"
  fi
fi
printf '%s\n' "$$" > "$LOCKFILE/pid"
> "$_LIVE_LOG" 2>/dev/null || true
_LIVE_LOG_ACTIVE=1
_RUNNING_FLAG="$WEB_DIR/strava-sync-running"
_SYNC_RUN_ID="$(date +%s)-$$"
printf '1' > "$_RUNNING_FLAG" 2>/dev/null || true
write_sync_status() {
  _rc=$?
  [ "$_rc" -eq 0 ] || log "FATAL: strava-my-activities exited with code $_rc"
  _now="$(date +%s)"
  _status_tmp="$WEB_DIR/.strava-sync-status.$$"
  _log_json="$(jq -Rsc 'split("\n")|map(select(length>0))|.[-50:]' "$_RUN_LOG" 2>/dev/null || printf '[]')"
  if [ "$_rc" -eq 0 ]; then
    _last_success="$(jq -r '.lastSuccess // empty' "$WEB_DIR/strava-sync-status.json" 2>/dev/null || true)"
    case "$_last_success" in ''|*[!0-9]*) _last_success=0 ;; esac
    [ "$IMPORT_ENABLED" = "0" ] || _last_success="$_now"
    jq -n --arg source "$STRAVA_SOURCE" --arg runId "$_SYNC_RUN_ID" --argjson now "$_now" \
      --argjson lastSuccess "$_last_success" \
      --argjson importEnabled "$([ "$IMPORT_ENABLED" = "0" ] && printf false || printf true)" \
      --argjson logs "$_log_json" \
      '{source:$source,runId:$runId,ok:true,importEnabled:$importEnabled,lastAttempt:$now,lastSuccess:(if $lastSuccess > 0 then $lastSuccess else null end),log:$logs}' > "$_status_tmp"
  else
    _last_success="$(jq -r '.lastSuccess // empty' "$WEB_DIR/strava-sync-status.json" 2>/dev/null || true)"
    case "$_last_success" in ''|*[!0-9]*) _last_success=0 ;; esac
    jq -n --arg source "$STRAVA_SOURCE" --arg runId "$_SYNC_RUN_ID" --argjson now "$_now" \
      --argjson lastSuccess "$_last_success" --arg error "Sync exited with status $_rc" \
      --argjson importEnabled "$([ "$IMPORT_ENABLED" = "0" ] && printf false || printf true)" \
      --argjson logs "$_log_json" \
      '{source:$source,runId:$runId,ok:false,importEnabled:$importEnabled,lastAttempt:$now,lastSuccess:(if $lastSuccess > 0 then $lastSuccess else null end),error:$error,log:$logs}' > "$_status_tmp"
  fi
  mv "$_status_tmp" "$WEB_DIR/strava-sync-status.json"
  printf '0' > "$_RUNNING_FLAG" 2>/dev/null || true
  rm -rf "$TMP" "$LOCKFILE"
}
trap 'write_sync_status' EXIT

# Scrape-health counters — incremented in §2 and §3b; emailed at end of run.
_sc_norm_fail=0       # jq normalization failures on list pages (activities missing)
_sc_cookie_expired=0  # session cookie expired mid detail-backfill
_sc_layout_fail=0     # detail page layout change (parse produced no data)

if [ "$IMPORT_ENABLED" != "0" ]; then

# --- 1. Authenticate -------------------------------------------------------
# api:    OAuth token refresh (see strava-lib.sh ensure_access_token)
# scrape: web session cookie + CSRF (see strava-lib.sh ensure_session_cookie)
case "$STRAVA_SOURCE" in
  api)    ensure_access_token ;;
  scrape) ensure_session_cookie ;;
esac

# --- 2. Page through the athlete's own activities feed ---------------------
# api:    GET /api/v3/athlete/activities — full JSON objects, real IDs + dates.
# scrape: GET /athlete/training_activities — web endpoint used by the browser;
#         returns 20 activities/page (fixed). The response may be JSON or a
#         JS/HTML fragment depending on the Strava version; the parser below
#         tries JSON first then falls back to ID extraction from HTML attributes.
: > "$TMP/all.ndjson"
page=1
# Whether pagination reached the natural end of the feed (an empty or short page)
# rather than stopping at MAX_PAGES. Only a full traversal lets section 3 treat a
# stored activity that is missing from the feed as deleted.
reached_end=0

case "$STRAVA_SOURCE" in
  api)
    # shellcheck disable=SC1090
    . "$STRAVA_LIBDIR/strava-my-feed-api.sh"
    ;;
  scrape)
    # shellcheck disable=SC1090
    . "$STRAVA_LIBDIR/strava-my-feed-scrape.sh"
    ;;
esac

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
log "merging $TOTAL fetched with $(wc -l < "$STORE" | tr -d ' ') stored activities..."

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

run_weather_backfill "$STORE" "$WEATHER_CACHE" "$TMP" "$DETAIL_DIR" "$WEB_DIR"
[ "${_rw_changed:-0}" -gt 0 ] && { log "weather: backfilled/upgraded ${_rw_changed} activities"; ADDED=$((ADDED + _rw_changed)); }

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
if [ -s "$TMP/deleted_ids.txt" ] || [ -s "$TMP/changed_ids.txt" ]; then
  printf '{}' > "$STATE_DIR/hr-summary.json"
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

# --- 3b. Backfill per-activity detail JSON (see strava-my-detail-backfill.sh) ----
# _sc_norm_fail/_sc_cookie_expired/_sc_layout_fail are initialized above and
# flow back via shared scope; §3c reads them immediately after this source call.
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-detail-backfill.sh"


else
  log "import disabled (STRAVA_MY_IMPORT_ENABLED=0) — re-rendering from existing store"
fi

# --- 3c. Scrape health alert --------------------------------------------------
# Three conditions that individually don't abort the run (exit 0) but need admin
# attention: layout change, cookie expiry mid-backfill, and list normalization
# failures. Sends one consolidated email per day; rate-limited by
# $STATE_DIR/scrape-alert.txt. Reuses STRAVA_EMAIL_SMTP/USER and BIKE_EMAIL
# (STRAVA_MY_BIKE_EMAIL) from the config — no new config keys required.
if [ "$STRAVA_SOURCE" = "scrape" ]; then
  _sc_any=$((_sc_norm_fail + _sc_layout_fail + _sc_cookie_expired))
  if [ "$_sc_any" -gt 0 ]; then
    if [ -z "${STRAVA_EMAIL_SMTP:-}" ] || [ -z "${STRAVA_EMAIL_USER:-}" ] || [ -z "${BIKE_EMAIL:-}" ]; then
      log "scrape alert: $_sc_any issue(s) detected — STRAVA_EMAIL_SMTP/USER/STRAVA_MY_BIKE_EMAIL not fully configured, skipping email"
    else
      _sc_today="$(date +%Y-%m-%d)"
      _sc_state="$STATE_DIR/scrape-alert.txt"
      _sc_last="$(cat "$_sc_state" 2>/dev/null || printf '')"
      if [ "$_sc_last" = "$_sc_today" ]; then
        log "scrape alert: $_sc_any issue(s) but already alerted today — skipping email"
      else
        _sc_body=""
        if [ "$_sc_layout_fail" -gt 0 ]; then
          _sc_body="${_sc_body}[LAYOUT CHANGE] $_sc_layout_fail activit$([ "$_sc_layout_fail" -eq 1 ] && printf 'y' || printf 'ies') could not be parsed.
Strava's page structure may have changed. Update the scrape parser in strava-my-activities.sh.
"
        fi
        if [ "$_sc_cookie_expired" -gt 0 ]; then
          _sc_body="${_sc_body}[COOKIE EXPIRED] Session cookie expired during detail backfill.
Copy a fresh _strava4_session value from browser DevTools (Application > Cookies > strava.com).
"
        fi
        if [ "$_sc_norm_fail" -gt 0 ]; then
          _sc_body="${_sc_body}[PARSE FAILURE] $_sc_norm_fail activit$([ "$_sc_norm_fail" -eq 1 ] && printf 'y page' || printf 'y pages') failed jq normalization.
Some activities may be missing from the dashboard.
"
        fi
        _sc_smtp="${STRAVA_EMAIL_SMTP}"
        _sc_auth="${_sc_smtp#*://}"
        _sc_host="${_sc_auth%%:*}"
        _sc_port="${_sc_auth##*:}"
        [ "$_sc_port" = "$_sc_auth" ] && _sc_port="465"
        _sc_starttls="off"
        case "$_sc_smtp" in smtp://*) _sc_starttls="on" ;; esac
        _sc_user="${STRAVA_EMAIL_USER%%:*}"
        _sc_pass="${STRAVA_EMAIL_USER#*:}"
        _sc_from="${STRAVA_EMAIL_FROM:-$_sc_user}"
        _sc_subj="[ALERT] Strava scrape issue(s) detected — $_sc_today"
        _sc_sent=0
        old_IFS="$IFS"; IFS=","
        for _sc_addr in $BIKE_EMAIL; do
          _sc_addr="$(printf '%s' "$_sc_addr" | tr -d ' \t')"
          [ -n "$_sc_addr" ] || continue
          {
            printf 'From: %s\r\n' "$_sc_from"
            printf 'To: %s\r\n' "$_sc_addr"
            printf 'Subject: %s\r\n' "$_sc_subj"
            printf 'Date: %s\r\n' "$(date '+%a, %d %b %Y %H:%M:%S %z')"
            printf 'MIME-Version: 1.0\r\n'
            printf 'Content-Type: text/plain; charset=utf-8\r\n'
            printf '\r\n'
            printf 'StatsServiceBook — Strava scrape alert — %s\r\n\r\n' "$_sc_today"
            printf '%s' "$_sc_body" | while IFS= read -r _sc_l; do printf '%s\r\n' "$_sc_l"; done
            printf '\r\nCheck the router log for lines starting with LAYOUT CHANGE DETECTED / cookie expired / WARNING for details.\r\n'
          } | msmtp \
              --host="$_sc_host" \
              --port="$_sc_port" \
              --tls \
              --tls-starttls="$_sc_starttls" \
              --auth=plain \
              --user="$_sc_user" \
              --passwordeval="printf '%s' '$_sc_pass'" \
              --from="$_sc_from" \
              "$_sc_addr" \
            && { log "scrape alert: sent to $_sc_addr"; _sc_sent=1; } \
            || log "scrape alert: failed to send to $_sc_addr"
        done
        IFS="$old_IFS"
        [ "$_sc_sent" -gt 0 ] && printf '%s\n' "$_sc_today" > "$_sc_state"
      fi
    fi
  fi
fi

TOTAL_STORED="$(wc -l < "$STORE" 2>/dev/null | tr -d ' ' || echo 0)"

# Write a minimal detail file (from store record) for any activity without one.
# Skip list is NOT respected here: skipped activities still get a minimal file so
# the dashboard can always link to activity.html (showing basic store stats even
# when the full Strava detail is unavailable).  Section 3b will not overwrite
# skip-listed activities; others get the full response on subsequent runs.
mkdir -p "$DETAIL_DIR"
_pre_minimal="$(ls -1 "$DETAIL_DIR" 2>/dev/null | grep -c '\.minimal$' || echo 0)"
log "detail: checking minimal files from $TOTAL_STORED store records"
jq -r 'select(.id != null) | [(.id | tostring), tojson] | @tsv' "$STORE" > "$TMP/minimal-records.tsv"
while IFS="$(printf '\t')" read -r _mdid _mdrec; do
  [ -n "$_mdid" ] || continue
  [ -f "$DETAIL_DIR/$_mdid.json" ] && continue
  printf '%s\n' "$_mdrec" > "$DETAIL_DIR/$_mdid.json"
  touch "$DETAIL_DIR/$_mdid.minimal"
done < "$TMP/minimal-records.tsv"
_post_minimal="$(ls -1 "$DETAIL_DIR" 2>/dev/null | grep -c '\.minimal$' || echo 0)"
[ "$_post_minimal" -gt "$_pre_minimal" ] && log "detail: minimal files now $_post_minimal"
# If new minimal files were created, bump ADDED so the skip-render guard
# triggers a re-emit of activities.json (pipe runs in subshell; use file counts).
[ "$_post_minimal" -gt "$_pre_minimal" ] && \
  ADDED=$((ADDED + _post_minimal - _pre_minimal))

# Skip re-render when nothing changed and no scripts were updated since last render.
# Re-renders when: new/changed/deleted activities, new detail files, weather backfill,
# bike-assign written via CGI (bike-assign newer than activities.json), or scripts updated.
_skip_render=0
# Include the entrypoint because it controls the activities.json projection.
_scripts_md5=""
for _hs in "$0" \
            "$STRAVA_LIBDIR/strava-my-html-dashboard.sh" \
            "$STRAVA_LIBDIR/strava-my-html-detail.sh" \
            "$STRAVA_LIBDIR/strava-my-html-bike.sh" \
            "$STRAVA_LIBDIR/strava-my-html-stats.sh" \
            "$STRAVA_LIBDIR/strava-my-html-heatmap.sh" \
            "$STRAVA_LIBDIR/strava-my-html-data-quality.sh" \
            "$STRAVA_LIBDIR/strava-render-pages.sh" \
            "$STRAVA_LIBDIR/strava-lib.sh"; do
    [ -f "$_hs" ] && _scripts_md5="$_scripts_md5$(md5sum "$_hs")"
done
_scripts_md5=$(printf '%s' "$_scripts_md5" | md5sum | cut -d' ' -f1)
if [ "$ADDED" -eq 0 ] && [ -f "$WEB_DIR/activities.json" ] && \
   [ -f "$WEB_DIR/index.html" ] && \
   [ -f "$BIKE_ASSIGN" ] && [ "$WEB_DIR/activities.json" -nt "$BIKE_ASSIGN" ]; then
    _stored_md5=""
    [ -f "$STATE_DIR/scripts.md5" ] && _stored_md5=$(cat "$STATE_DIR/scripts.md5")
    if [ "$_scripts_md5" = "$_stored_md5" ]; then
        _skip_render=1
        log "no new activities and scripts up-to-date — skipping re-render"
    fi
fi
if [ "$_skip_render" -eq 0 ]; then

# --- 4. Emit activities.json for the dashboard ----------------------------
# Flat list of all stored activities, sorted newest-first. The browser handles
# all year/month/sport-type filtering; no server-side aggregation needed.
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Cookie health metadata (scrape mode only) — mirrors leaderboard's scrapeMeta
# so the dashboard can show the same expiry banner.
_sc_meta='null'
if [ "$STRAVA_SOURCE" = "scrape" ]; then
  _sc_age="$(cat "$STATE_DIR/strava_session_age.txt" 2>/dev/null || printf '0')"
  case "$_sc_age" in ''|*[!0-9]*) _sc_age=0 ;; esac
  if [ "$_sc_age" -gt 0 ]; then
    _sc_meta="$(jq -n --argjson ts "$_sc_age" '{
      cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
      cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0])
    }')"
  fi
fi

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
  _detail_json_count="$(ls -1 "$DETAIL_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
  log "render: aggregating $_detail_json_count detail JSON files"
  cat "$DETAIL_DIR"/*.json > "$TMP/details-all.json"
  if ! jq -e -s 'length >= 0' "$TMP/details-all.json" >/dev/null 2>"$TMP/details-parse-error"; then
    log "warning: invalid detail JSON detected; validating files individually"
    : > "$TMP/details-valid.ndjson"
    _detail_invalid=0
    for _detail_file in "$DETAIL_DIR"/*.json; do
      if jq -c . "$_detail_file" > "$TMP/detail-one.json" 2>/dev/null; then
        cat "$TMP/detail-one.json" >> "$TMP/details-valid.ndjson"
      else
        _detail_invalid=$((_detail_invalid + 1))
        log "warning: skipping invalid detail JSON: $_detail_file"
        mv "$_detail_file" "$_detail_file.invalid"
      fi
    done
    mv "$TMP/details-valid.ndjson" "$TMP/details-all.json"
    log "warning: skipped $_detail_invalid invalid detail JSON file(s)"
  fi
  log "render: building scalar detail enrichment"
  : > "$TMP/enrich-parts.ndjson"
  for _detail_file in "$DETAIL_DIR"/*.json; do
    [ -f "$_detail_file" ] || continue
    _detail_id="${_detail_file##*/}"
    _detail_id="${_detail_id%.json}"
    jq -c --arg fileid "$_detail_id" '
      select(.id != null) as $d
      | ($d | {
          moving_time:           (.moving_time // null),
          elapsed_time:           (.elapsed_time // null),
          total_elevation_gain:   (.total_elevation_gain // null),
          average_speed:          (.average_speed // null),
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
          calories:               (.calories // null),
          gear_id:                (.gear.id // null),
          gpx_file:               (.gpx_file // null)
        }) as $v
      | {($fileid): $v, ($d.id | tostring): $v}
    ' "$_detail_file" >> "$TMP/enrich-parts.ndjson"
  done
  jq -s 'add // {}' "$TMP/enrich-parts.ndjson" > "$TMP/enrich.json"
  # Max single climb per activity: compute once server-side from GPX files so the
  # browser never has to load hundreds of GPX files just for the dashboard chip.
  _climb_cache="$STATE_DIR/max-climbs.json"
  [ -f "$_climb_cache" ] || printf '{}' > "$_climb_cache"
  jq -r 'to_entries[] | select(.value.gpx_file != null) | [(.value.date // "0000-00-00"), .key, .value.gpx_file] | join(" ")' \
    "$TMP/enrich.json" 2>/dev/null | sort -ru | awk '{print $2, $3}' > "$TMP/gpx-paths.txt" || : > "$TMP/gpx-paths.txt"
  : > "$TMP/max-climbs-new.ndjson"
  jq -c 'to_entries[] | {(.key): .value}' "$_climb_cache" >> "$TMP/max-climbs-new.ndjson" 2>/dev/null
  jq -r 'keys | .[]' "$_climb_cache" > "$TMP/cached-climb-ids.txt" 2>/dev/null || : > "$TMP/cached-climb-ids.txt"
  _climbs_total="$(wc -l < "$TMP/gpx-paths.txt" | tr -d ' ')"
  _climbs_cached="$(wc -l < "$TMP/cached-climb-ids.txt" | tr -d ' ')"
  _climbs_todo=$((_climbs_total - _climbs_cached))
  [ "$_climbs_todo" -lt 0 ] && _climbs_todo=0
  [ "$_climbs_todo" -gt 0 ] \
    && log "render: computing max_single_climb for $_climbs_todo GPX activities (cached: $_climbs_cached)"
  _climbs_computed=0
  _climb_batch="${STRAVA_CLIMB_BATCH:-50}"
  # Use same defaults as strava-my-html-detail.sh so server and client thresholds match.
  : "${STRAVA_MY_CLIMB_MIN_GAIN_RIDE:=25}"
  : "${STRAVA_MY_CLIMB_MIN_DISTANCE:=100}"
  : "${STRAVA_MY_CLIMB_MIN_GRADE_RIDE:=2}"
  : "${STRAVA_MY_CLIMB_DESCENT_RESET:=30}"
  _awk_min_gain="$STRAVA_MY_CLIMB_MIN_GAIN_RIDE"
  _awk_min_dist="$STRAVA_MY_CLIMB_MIN_DISTANCE"
  _awk_min_grade="$(printf '%s %s' "$STRAVA_MY_CLIMB_MIN_GRADE_RIDE" "100" | awk '{printf "%.6f", $1/$2}')"
  _awk_descent_reset="$STRAVA_MY_CLIMB_DESCENT_RESET"
  while read -r _cid _cgpx; do
    grep -qx "$_cid" "$TMP/cached-climb-ids.txt" && continue
    [ "$_climbs_computed" -ge "$_climb_batch" ] && break
    _cgpx_path="$WEB_DIR/$_cgpx"
    [ -f "$_cgpx_path" ] || continue
    _cval="$(awk -v ming="$_awk_min_gain" -v mind="$_awk_min_dist" -v minr="$_awk_min_grade" -v dreset="$_awk_descent_reset" '
      BEGIN{pi=3.14159265358979;cv=0;cp=0;cd=0;best=0;tot=0;f=1;clat=0;clon=0;plat="";plon=""}
      function hav(la1,lo1,la2,lo2,  R,dl,dn,a,c){
        R=6371000;dl=(la2-la1)*pi/180;dn=(lo2-lo1)*pi/180
        a=sin(dl/2)*sin(dl/2)+cos(la1*pi/180)*cos(la2*pi/180)*sin(dn/2)*sin(dn/2)
        c=2*atan2(sqrt(a),sqrt(1-a));return R*c}
      /lat=/{s=$0;gsub(/.*lat="/,"",s);gsub(/".*$/,"",s);clat=s+0
             s=$0;gsub(/.*lon="/,"",s);gsub(/".*$/,"",s);clon=s+0}
      /<ele>/{s=$0;gsub(/.*<ele>/,"",s);gsub(/<\/ele>.*/,"",s);e=s+0
              if(plat!="")tot+=hav(plat+0,plon+0,clat,clon)
              plat=clat;plon=clon
              if(f){cv=e;cp=e;cd=tot;f=0;next}
              if(e<cp-dreset){cv=e;cp=e;cd=tot;next}
              if(e>cp)cp=e
              if(e<cv){cv=e;cd=tot}
              g=e-cv;d=tot-cd
              if(g>=ming&&d>=mind&&d>0&&g/d>=minr&&g>best)best=g}
      END{printf"%d",int(best+0.5)}' "$_cgpx_path" 2>/dev/null)"
    [ -n "$_cval" ] || _cval=0
    printf '{"%s":%s}\n' "$_cid" "$_cval" >> "$TMP/max-climbs-new.ndjson"
    printf '%s\n' "$_cid" >> "$TMP/cached-climb-ids.txt"
    _climbs_computed=$((_climbs_computed + 1))
    [ $((_climbs_computed % 10)) -eq 0 ] \
      && log "render: max_single_climb $_climbs_computed/$_climbs_todo done"
  done < "$TMP/gpx-paths.txt"
  [ -s "$TMP/max-climbs-new.ndjson" ] \
    && jq -s 'add // {}' "$TMP/max-climbs-new.ndjson" > "$TMP/max-climbs.json" 2>/dev/null \
    || printf '{}' > "$TMP/max-climbs.json"
  [ "$_climbs_computed" -gt 0 ] \
    && cp "$TMP/max-climbs.json" "$_climb_cache" \
    && log "render: computed max_single_climb for $_climbs_computed new GPX activities"
  _climbs_remaining=$((_climbs_todo - _climbs_computed))
  [ "$_climbs_remaining" -gt 0 ] \
    && log "render: climb batch limit $_climb_batch reached; $_climbs_remaining activities queued for next run"
  _hr_cache="$STATE_DIR/hr-summary.json"
  [ -f "$_hr_cache" ] || printf '{}' > "$_hr_cache"
  jq -c 'to_entries[] | {(.key): .value}' "$_hr_cache" > "$TMP/hr-summary-parts.ndjson"
  jq -s 'map({(.id | tostring): {moving_time: (.moving_time // null), max_heartrate: (.max_heartrate // null)}}) | add // {}' \
    "$STORE" > "$TMP/hr-feed-fields.json"
  jq -r --slurpfile fields "$TMP/hr-feed-fields.json" '
    ($fields[0] // {}) as $feed
    | to_entries[]
    | select(.value.gpx_file != null and .value.average_heartrate == null)
    | [.key, .value.gpx_file,
       ($feed[.key].moving_time // .value.moving_time // 0),
       ($feed[.key].max_heartrate // .value.max_heartrate // 0)]
    | @tsv
  ' "$TMP/enrich.json" 2>/dev/null \
    | sort -r > "$TMP/hr-gpx-paths.txt" || : > "$TMP/hr-gpx-paths.txt"
  jq -r 'keys[]' "$_hr_cache" > "$TMP/hr-cached-ids.txt" 2>/dev/null || : > "$TMP/hr-cached-ids.txt"
  : > "$TMP/hr-gpx-pending.txt"
  _tab="$(printf '\t')"
  while IFS="$_tab" read -r _hr_id _hr_gpx _hr_time _hr_rawmax; do
    if ! grep -qx "$_hr_id" "$TMP/hr-cached-ids.txt"; then
      printf '%s\t%s\t%s\t%s\n' "$_hr_id" "$_hr_gpx" "$_hr_time" "$_hr_rawmax" >> "$TMP/hr-gpx-pending.txt"
    fi
  done < "$TMP/hr-gpx-paths.txt"
  mv "$TMP/hr-gpx-pending.txt" "$TMP/hr-gpx-paths.txt"
  _hr_todo="$(wc -l < "$TMP/hr-gpx-paths.txt" | tr -d ' ')"
  _hr_computed=0
  _hr_batch=100
  while IFS="$_tab" read -r _hr_id _hr_gpx _hr_time _hr_rawmax; do
    [ "$_hr_computed" -ge "$_hr_batch" ] && break
    _hr_gpx_path="$WEB_DIR/$_hr_gpx"
    [ -f "$_hr_gpx_path" ] || continue
    _hr_values="$(gpx_hr_summary "$_hr_gpx_path" "$_hr_time" "$_hr_rawmax" "$ATHLETE_AGE" 2>/dev/null)" || _hr_values=""
    case "$_hr_values" in
      *"$_tab"*) ;;
      *) _hr_values="null${_tab}null${_tab}null" ;;
    esac
    _hr_avg="${_hr_values%%"$_tab"*}"
    _hr_values="${_hr_values#*"$_tab"}"
    _hr_max="${_hr_values%%"$_tab"*}"
    _hr_effort="${_hr_values#*"$_tab"}"
    printf '{"%s":{"average_heartrate":%s,"max_heartrate":%s,"estimated_hr_effort":%s}}\n' \
      "$_hr_id" "$_hr_avg" "$_hr_max" "$_hr_effort" >> "$TMP/hr-summary-parts.ndjson"
    printf '%s\n' "$_hr_id" >> "$TMP/hr-cached-ids.txt"
    _hr_computed=$((_hr_computed + 1))
  done < "$TMP/hr-gpx-paths.txt"
  jq -s 'add // {}' "$TMP/hr-summary-parts.ndjson" > "$TMP/hr-summary.json"
  cp "$TMP/hr-summary.json" "$_hr_cache"
  [ "$_hr_computed" -gt 0 ] && log "render: cached GPX heart-rate summaries for $_hr_computed activities"
  _hr_remaining=$((_hr_todo - _hr_computed))
  [ "$_hr_remaining" -gt 0 ] \
    && log "render: HR summary batch limit $_hr_batch reached; $_hr_remaining activities queued for next run"
  # GPS is keyed by the detail filename: scraped detail JSON may carry a stale
  # or mismatched .id while the file name and its GPX route match the activity.
  # Build one small record per file instead of combining input_filename with
  # inputs; that combination aborts in some router jq builds on large globs.
  : > "$TMP/gps-parts.ndjson"
  _gps_detail_count=0
  for _detail_file in "$DETAIL_DIR"/*.json; do
    [ -f "$_detail_file" ] || continue
    _detail_id="${_detail_file##*/}"
    _detail_id="${_detail_id%.json}"
    _gps_detail_count=$((_gps_detail_count + 1))
    [ $((_gps_detail_count % 50)) -eq 0 ] && log "render: GPS detail $_gps_detail_count/$_detail_json_count"
    if ! jq -c --arg id "$_detail_id" '{
      ($id): (
        (((.map.polyline // "") | length) > 0)
        or (((.map.summary_polyline // "") | length) > 0)
        or (((.start_latlng // []) | length) >= 2)
        or (((.gpx_file // "") | length) > 0)
      )
    }' "$_detail_file" >> "$TMP/gps-parts.ndjson"; then
      log "warning: invalid detail JSON skipped while building GPS map: $_detail_file"
    fi
  done
  if [ -s "$TMP/gps-parts.ndjson" ]; then
    log "render: combining GPS flags ($_gps_detail_count/$_detail_json_count)"
    jq -s 'add // {}' "$TMP/gps-parts.ndjson" > "$TMP/gps.json"
  else
    echo '{}' > "$TMP/gps.json"
  fi
else
  echo '{}' > "$TMP/enrich.json"
  echo '{}' > "$TMP/gps.json"
  printf '{}' > "$TMP/max-climbs.json"
  printf '{}' > "$TMP/hr-summary.json"
fi

# Gear (bike) names: detailed activities carry a .gear object with the gear's id
# and human name. Build a gear_id -> { name } map so the bike-service page can
# label a bike by its Strava gear instead of the opaque "b1234567" id. Best
# effort — gear names only appear once the relevant detail files have backfilled.
if ls "$DETAIL_DIR"/*.json >/dev/null 2>&1; then
  log "render: building gear cache from $_detail_json_count detail files"
  jq -s '
    map(.gear | select(. != null and .id != null) | { (.id): { name: (.name // .id) } })
    | add // {}
  ' "$TMP/details-all.json" > "$TMP/gears.json"
else
  echo '{}' > "$TMP/gears.json"
fi

log "building activities.json..."
jq -s --arg generatedAt "$GENERATED_AT" \
  --arg athleteAge "$ATHLETE_AGE" \
  --argjson scrapeMeta "$_sc_meta" \
  --slurpfile det "$TMP/detail_ids.json" \
  --slurpfile enr "$TMP/enrich.json" \
  --slurpfile hr "$TMP/hr-summary.json" \
  --slurpfile gps "$TMP/gps.json" \
  --slurpfile gears "$TMP/gears.json" \
  --slurpfile climbs "$TMP/max-climbs.json" \
  --slurpfile assigns "$TMP/bike-assign.json" \
  --slurpfile wcache "$WEATHER_CACHE" '
  ( ($det[0] // []) | map({ (.): true }) | add // {} ) as $have
  | ($enr[0] // {}) as $enrich
  | ($hr[0] // {}) as $hr_by_id
  | ($gps[0] // {}) as $gps_by_id
  | ($assigns[0] // {}) as $A
  | ($wcache[0] // {}) as $W
  | {
    generatedAt: $generatedAt,
    athleteAge: (if $athleteAge == "" then null else ($athleteAge | tonumber) end),
    scrapeMeta: $scrapeMeta,
    gears: ($gears[0] // {}),
    activities: [
      .[]
      | ($enrich[(.id | tostring)] // {}) as $e
      | ($A[(.id | tostring)] // .gear_id // $e.gear_id) as $bike
      | ($W[(.id | tostring)]) as $wc
      | (($climbs[0] // {})[(.id | tostring)]) as $climbVal
      | (if ($wc | type) == "number" then $wc
         elif ($wc | type) == "object" then ($wc.t // null)
         else null end) as $wctemp
      | {
          id:                     .id,
          date:                   .date,
          name:                   .name,
          sport_type:             .sport_type,
          gear_id:                $bike,
          distance:               (.distance // 0),
          moving_time:            (.moving_time // 0),
          elapsed_time:           (if (.elapsed_time // 0) > 0 then .elapsed_time else ($e.elapsed_time // 0) end),
          total_elevation_gain:   (if (.total_elevation_gain // 0) > 0 then .total_elevation_gain else ($e.total_elevation_gain // 0) end),
          average_speed:          (if (.average_speed // 0) > 0 then .average_speed else ($e.average_speed // 0) end),
          max_speed:              (if (.max_speed // 0) > 0 then .max_speed else ($e.max_speed // 0) end),
          average_heartrate:      (.average_heartrate // $e.average_heartrate // $hr_by_id[(.id | tostring)].average_heartrate),
          max_heartrate:          (.max_heartrate // $e.max_heartrate // $hr_by_id[(.id | tostring)].max_heartrate),
          estimated_hr_effort:   ($hr_by_id[(.id | tostring)].estimated_hr_effort // null),
          average_cadence:        (.average_cadence // $e.average_cadence),
          average_watts:          (.average_watts // $e.average_watts),
          weighted_average_watts: (.weighted_average_watts // $e.weighted_average_watts),
          max_watts:              (.max_watts // $e.max_watts),
          kilojoules:             (.kilojoules // $e.kilojoules),
          average_temp:           (.average_temp // $e.average_temp // $wctemp),
          temp_source:            (if ($wc | type) == "object" and ($wc.t != null) then $wc.s else null end),
          apparent_temp:          (if ($wc | type) == "object" then $wc.at else null end),
          wind_speed:             (if ($wc | type) == "object" then $wc.ws else null end),
          wind_dir:               (if ($wc | type) == "object" then $wc.wd else null end),
          weathercode:            (if ($wc | type) == "object" then $wc.wc else null end),
          precipitation:          (if ($wc | type) == "object" then $wc.pr else null end),
          suffer_score:           (.suffer_score // $e.suffer_score),
          calories:               (.calories // $e.calories),
          gpx_file:               ($e.gpx_file // null),
          max_single_climb:       (if ($climbVal | type) == "number" and $climbVal > 0 then $climbVal else null end),
          has_gps:                (if ($have[(.id | tostring)] // false) then ($gps_by_id[(.id | tostring)] // false) else null end),
          detail:                 (($have[(.id | tostring)]) // false)
        }
    ] | sort_by(.date) | reverse
  }
' "$STORE" > "$WEB_DIR/activities.json.tmp" \
  && mv "$WEB_DIR/activities.json.tmp" "$WEB_DIR/activities.json"

log "wrote $WEB_DIR/activities.json ($TOTAL_STORED activities)"

log "html: rendering pages..."
# --- 5/6a/6b/6c/6d. Render dashboard, detail, bike, stats pages --------------
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-render-pages.sh"

# --- 6f. Bike-service email alerts (see strava-my-bike-alert.sh) -------------
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-bike-alert.sh"

log "wrote $WEB_DIR/index.html, $WEB_DIR/activity.html, $WEB_DIR/stats.html and $WEB_DIR/activities.json"

# --- Render all-activities heatmap (last — GPX scan is slow on flash storage) -
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-my-html-heatmap.sh"

printf '%s\n' "$_scripts_md5" > "$STATE_DIR/scripts.md5"

fi  # _skip_render

log "done."
