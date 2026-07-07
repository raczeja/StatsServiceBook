#!/bin/sh
# StravaStats for OpenWrt
# ------------------------
# Fetches one or more Strava clubs' recent-activities feeds, accumulates the
# activities into per-club persistent stores (dating each one by the day it was
# first seen, since the feed carries no dates), aggregates per-club leaderboards,
# and renders a static HTML dashboard plus JSON into uhttpd's web root. The
# dashboard shows each club in its own section and lets you pick a year and month
# (defaulting to the current ones) to filter in the browser.
# Designed for low-RAM MIPS home routers running OpenWrt. Pure POSIX sh /
# BusyBox; deps: curl + jq.
#
# Run by cron once a day. See README.md for setup.

set -eu

STRAVA_LIBDIR="$(dirname "$0")"
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-lib.sh"

CONFIG="${STRAVA_CONFIG:-/etc/strava-leaderboard.conf}"

[ -f "$CONFIG" ] || die "config not found: $CONFIG (copy config.example and edit it)"
# shellcheck disable=SC1090
. "$CONFIG"

STRAVA_SOURCE="${STRAVA_SOURCE:-api}"
case "$STRAVA_SOURCE" in
  api)
    : "${STRAVA_CLIENT_ID:?set STRAVA_CLIENT_ID in $CONFIG}"
    : "${STRAVA_CLIENT_SECRET:?set STRAVA_CLIENT_SECRET in $CONFIG}"
    : "${STRAVA_REFRESH_TOKEN:?set STRAVA_REFRESH_TOKEN in $CONFIG}"
    ;;
  scrape)
    : "${STRAVA_SESSION_COOKIE:?set STRAVA_SESSION_COOKIE in $CONFIG (required for STRAVA_SOURCE=scrape — copy _strava4_session from browser DevTools)}"
    ;;
  *)
    die "STRAVA_SOURCE must be 'api' or 'scrape', got: $STRAVA_SOURCE"
    ;;
esac
# Accept STRAVA_CLUB_IDS (new, comma-separated) or STRAVA_CLUB_ID (old, single).
STRAVA_CLUB_IDS="${STRAVA_CLUB_IDS:-${STRAVA_CLUB_ID:-}}"
: "${STRAVA_CLUB_IDS:?set STRAVA_CLUB_IDS in $CONFIG}"

SPORT_TYPE="${STRAVA_SPORT_TYPE:-}"                 # e.g. Run, Ride; "" = all sports
TOKEN_REFRESH_MARGIN="${STRAVA_TOKEN_REFRESH_MARGIN:-600}"  # refresh if the access token expires within this many seconds
MAX_PAGES="${STRAVA_MAX_PAGES:-5}"
PER_PAGE="${STRAVA_PER_PAGE:-200}"
WEB_DIR="${STRAVA_WEB_DIR:-/www/strava}"
STATE_DIR="${STRAVA_STATE_DIR:-/usr/lib/strava-leaderboard}"  # must survive reboot (NOT /tmp or /var on OpenWrt)
SNAPSHOT_DIR="$STATE_DIR/snapshots"
KEEP_SNAPSHOTS="${STRAVA_KEEP_SNAPSHOTS:-90}"

command -v curl >/dev/null 2>&1 || die "curl not installed (apk add curl ca-bundle  /  opkg install curl ca-bundle)"
command -v jq   >/dev/null 2>&1 || die "jq not installed (apk add jq  /  opkg install jq)"

mkdir -p "$WEB_DIR" "$SNAPSHOT_DIR"

TOKEN_STATE="$STATE_DIR/token.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/strava.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- 1. Authenticate (api: OAuth token refresh; scrape: web session login) --
# Cookie dry-run: when STRAVA_SOURCE=api but STRAVA_SESSION_COOKIE is also set,
# probe the cookie on every run without saving any scraped data. The result
# appears in scrapeMeta so the dashboard shows cookie health alongside API data —
# useful to confirm the session is ready before switching to STRAVA_SOURCE=scrape.
_scrape_dry_run=0
_sc_check_valid=0
case "$STRAVA_SOURCE" in
  api)
    ensure_access_token
    if [ -n "${STRAVA_SESSION_COOKIE:-}" ]; then
      _scrape_dry_run=1
      check_session_cookie_status || true
    fi
    ;;
  scrape) ensure_session_cookie ;;
esac

FIRST_SEEN="${STRAVA_FIRST_SEEN_DATE:-$(date '+%Y-%m-%d')}"
case "$FIRST_SEEN" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) die "STRAVA_FIRST_SEEN_DATE must be YYYY-MM-DD, got: $FIRST_SEEN" ;;
esac
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
SPORT_LC="$(printf '%s' "$SPORT_TYPE" | tr '[:upper:]' '[:lower:]')"
STAMP="$(date '+%Y%m%d')"

# --- 2+3+4. For each club: fetch, merge into per-club store, emit JSON ----
# Write club IDs one-per-line so iteration avoids a pipe subshell.
printf '%s\n' "$STRAVA_CLUB_IDS" | tr ',' '\n' > "$TMP/club_ids.txt"
: > "$TMP/clubs_manifest.txt"

while IFS= read -r club_id; do
  club_id="$(printf '%s' "$club_id" | tr -d ' \t')"
  [ -n "$club_id" ] || continue

  CLUB_STORE="$STATE_DIR/activities_${club_id}.ndjson"

  # One-time migration: carry history forward from the old single-club store name.
  # Guard with the manifest so we copy to at most one club per run — the old
  # activities.ndjson belonged to one specific club; copying it to every new club
  # would seed all clubs with the same history and show duplicate data.
  if [ ! -f "$CLUB_STORE" ] && [ -f "$STATE_DIR/activities.ndjson" ] && [ ! -s "$TMP/clubs_manifest.txt" ]; then
    cp "$STATE_DIR/activities.ndjson" "$CLUB_STORE"
    log "migrated activities.ndjson -> activities_${club_id}.ndjson"
  fi

  # 2. Fetch club details for the dashboard (api only; scrape has no OAuth token).
  case "$STRAVA_SOURCE" in
    api)
      if curl_retry -fsS "https://www.strava.com/api/v3/clubs/$club_id" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -o "$TMP/club_info_${club_id}.json" 2>/dev/null; then
        # Persist full club details so scrape mode can reuse them after the API is retired.
        cp "$TMP/club_info_${club_id}.json" "$STATE_DIR/club_info_${club_id}.json"
        log "club $club_id: $(jq -r '.name // "(unnamed)"' "$TMP/club_info_${club_id}.json")"
      else
        log "club $club_id: details fetch failed (will show ID only)"
        printf '{}' > "$TMP/club_info_${club_id}.json"
      fi
      ;;
    scrape)
      # Prefer club details saved by API mode (full: name, city, member_count, profile image).
      # Fall back to parsing the club name from the public club page HTML.
      if [ -f "$STATE_DIR/club_info_${club_id}.json" ]; then
        cp "$STATE_DIR/club_info_${club_id}.json" "$TMP/club_info_${club_id}.json"
        log "club $club_id: $(jq -r '.name // "(unnamed)"' "$TMP/club_info_${club_id}.json") (scrape mode, cached details)"
      elif curl_retry -fsS \
        -b "$STATE_DIR/strava_cookies.txt" \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
        "https://www.strava.com/clubs/$club_id" \
        -o "$TMP/club_page_${club_id}.html" 2>/dev/null; then
        _scn=$(awk '/<title>/{
          gsub(/.*<title>/, ""); gsub(/<\/title>.*/, "")
          gsub(/ *[|].*$/, ""); gsub(/^[ \t]+|[ \t]+$/, "")
          if ($0 != "") { print; exit }
        }' "$TMP/club_page_${club_id}.html")
        if [ -n "$_scn" ]; then
          printf '%s\n' "$_scn" | jq -R '{name: .}' > "$TMP/club_info_${club_id}.json"
        else
          printf '{}' > "$TMP/club_info_${club_id}.json"
        fi
        log "club $club_id: ${_scn:-(unnamed)} (scrape mode, name from page)"
      else
        printf '{}' > "$TMP/club_info_${club_id}.json"
        log "club $club_id (scrape mode, club details unavailable)"
      fi
      ;;
  esac

  # 3. Page through the club activities feed
  log "fetching club $club_id activities (up to $MAX_PAGES pages, source: $STRAVA_SOURCE)..."
  : > "$TMP/all.ndjson"
  _scrape_cursor=""
  page=1
  while [ "$page" -le "$MAX_PAGES" ]; do
    case "$STRAVA_SOURCE" in
      api)
        curl_retry -fsS \
          "https://www.strava.com/api/v3/clubs/$club_id/activities?per_page=$PER_PAGE&page=$page" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -o "$TMP/page.json" || die "activities fetch failed (club $club_id page $page)"
        count="$(jq 'length' "$TMP/page.json" 2>/dev/null || echo 0)"
        [ "$count" -gt 0 ] || { log "  page $page empty, stopping"; break; }
        jq -c '.[]' "$TMP/page.json" >> "$TMP/all.ndjson"
        log "  page $page: $count activities"
        [ "$count" -lt "$PER_PAGE" ] && { log "  short page, stopping"; break; }
        ;;
      scrape)
        _sc_url="https://www.strava.com/clubs/$club_id/feed?feed_type=club&club_id=$club_id"
        [ -n "$_scrape_cursor" ] && _sc_url="$_sc_url&before=$_scrape_cursor&cursor=$_scrape_cursor"
        _sc_csrf="$(cat "$STATE_DIR/strava_csrf.txt" 2>/dev/null || echo "")"
        curl_retry -fsS \
          -b "$STATE_DIR/strava_cookies.txt" \
          -H "accept: application/json, text/plain, */*" \
          -H "x-requested-with: XMLHttpRequest" \
          -H "x-csrf-token: $_sc_csrf" \
          -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
          "$_sc_url" \
          -o "$TMP/page.json" || die "feed fetch failed (club $club_id page $page)"
        if ! jq -e '.entries' "$TMP/page.json" >/dev/null 2>&1; then
          die "feed response not JSON (club $club_id) — session may have expired; delete $STATE_DIR/strava_session_age.txt and retry"
        fi
        count="$(jq '.entries | length' "$TMP/page.json")"
        [ "$count" -gt 0 ] || { log "  page $page empty, stopping"; break; }
        jq -c '.entries[]' "$TMP/page.json" >> "$TMP/all.ndjson"
        log "  page $page: $count entries"
        _scrape_cursor="$(jq -r '(.entries[-1].cursorData.updated_at | floor | tostring)' "$TMP/page.json")"
        ;;
    esac
    page=$((page + 1))
  done

  jq -s '.' "$TMP/all.ndjson" > "$TMP/fetched.json"
  log "fetched $(jq 'length' "$TMP/fetched.json") entries from club $club_id"

  # 3. Merge fetched activities into the per-club persistent store.
  # api:    dedup by content signature (feed has no ids/dates); stamp with today.
  # scrape: dedup by activity id; firstSeen = actual startDate from Strava.
  [ -f "$CLUB_STORE" ] || : > "$CLUB_STORE"

  if [ -s "$CLUB_STORE" ]; then
    jq -s '[ .[].signature ]' "$CLUB_STORE" > "$TMP/known.json" \
      || printf '[]\n' > "$TMP/known.json"
  else
    printf '[]\n' > "$TMP/known.json"
  fi
  [ -s "$TMP/fetched.json" ] || printf '[]\n' > "$TMP/fetched.json"

  case "$STRAVA_SOURCE" in
    api)
      jq -c -n \
        --slurpfile known "$TMP/known.json" \
        --slurpfile fetched "$TMP/fetched.json" \
        --arg today "$FIRST_SEEN" '
        def sig:
          [ ((.athlete.firstname // "") | ascii_downcase),
            ((.athlete.lastname  // "") | ascii_downcase),
            ((.name // "")              | ascii_downcase),
            (.distance             // 0 | tostring),
            (.elapsed_time         // 0 | tostring),
            ((.sport_type // .type // "") | ascii_downcase)
          ] | join("|");
        ( ($known[0] // []) | map({ (.): true }) | add // {} ) as $seen
        | [ $fetched[0][] | { s: sig, a: . } ]
        | unique_by(.s)
        | map(select($seen[.s] | not))
        | .[]
        | {
            signature:      .s,
            firstSeen:      $today,
            firstname:      (.a.athlete.firstname // ""),
            lastname:       (.a.athlete.lastname  // ""),
            profile_medium: (.a.athlete.profile_medium // ""),
            name:           (.a.name // ""),
            distance:       (.a.distance // 0),
            moving_time:    (.a.moving_time // 0),
            elapsed_time:   (.a.elapsed_time // 0),
            total_elevation_gain: (.a.total_elevation_gain // 0),
            type:           (.a.type // ""),
            sport_type:     (.a.sport_type // .a.type // "")
          }
      ' > "$TMP/new.ndjson"
      ;;
    scrape)
      # Stats arrive as HTML strings: strip tags, parse numbers.
      # distance: "34.30<abbr...> km</abbr>" → 34300 m
      # elev:     "108<abbr...> m</abbr>"    → 108 m
      # time:     "1<abbr>h</abbr> 27<abbr>m</abbr>" → seconds
      jq -c -n \
        --slurpfile known "$TMP/known.json" \
        --slurpfile fetched "$TMP/fetched.json" '
        def strip_html: gsub("<[^>]*>"; "");
        def parse_km:
          strip_html | gsub("[^0-9.]"; "") |
          if . == "" or . == "." then 0 else tonumber end * 1000;
        def parse_elev:
          strip_html | gsub("[^0-9.]"; "") |
          if . == "" or . == "." then 0 else tonumber end;
        def _n: if (. == null or . == "") then 0 else tonumber end;
        def parse_time:
          strip_html |
          capture("(?:(?<h>[0-9]+)\\s*h)?\\s*(?:(?<m>[0-9]+)\\s*m)?\\s*(?:(?<s>[0-9]+)\\s*s)?") |
          ((.h | _n) * 3600) + ((.m | _n) * 60) + (.s | _n);
        ( ($known[0] // []) | map({ (.): true }) | add // {} ) as $seen
        | [ $fetched[0][]
            | select(.entity == "Activity")
            | .activity
            | (.stats | map(select(.key == "stat_one"))   | .[0].value // "") as $s1
            | (.stats | map(select(.key == "stat_two"))   | .[0].value // "") as $s2
            | (.stats | map(select(.key == "stat_three")) | .[0].value // "") as $s3
            | (.athlete.firstName // "") as $fn
            | (.athlete.athleteName // "") as $an
            | {
                s:         .id,
                firstname: $fn,
                lastname:  ($an | ltrimstr($fn) | ltrimstr(" ")),
                profile_medium: (.athlete.avatarUrl // ""),
                name:      (.activityName // ""),
                distance:  ($s1 | parse_km),
                moving_time: ($s3 | parse_time),
                elapsed_time: (.elapsedTime // 0),
                total_elevation_gain: ($s2 | parse_elev),
                type:      (.type // ""),
                sport_type: (.type // ""),
                firstSeen: (.startDate // "" | split("T")[0])
              }
          ]
        | unique_by(.s)
        | map(select($seen[.s] | not))
        | .[]
        | {
            signature:    .s,
            firstSeen:    .firstSeen,
            firstname:    .firstname,
            lastname:     .lastname,
            profile_medium: .profile_medium,
            name:         .name,
            distance:     .distance,
            moving_time:  .moving_time,
            elapsed_time: .elapsed_time,
            total_elevation_gain: .total_elevation_gain,
            type:         .type,
            sport_type:   .sport_type
          }
      ' > "$TMP/new.ndjson"
      ;;
  esac

  ADDED="$(wc -l < "$TMP/new.ndjson" | tr -d ' ')"
  cat "$TMP/new.ndjson" >> "$CLUB_STORE"
  case "$STRAVA_SOURCE" in
    api)    log "club $club_id: +$ADDED new (firstSeen $FIRST_SEEN), $(wc -l < "$CLUB_STORE" | tr -d ' ') total" ;;
    scrape) log "club $club_id: +$ADDED new (actual dates), $(wc -l < "$CLUB_STORE" | tr -d ' ') total" ;;
  esac

  # 5a. Emit per-club activities temp file (assembled into activities.json below).
  jq -s --arg clubId "$club_id" --arg sport "$SPORT_LC" \
    --slurpfile info "$TMP/club_info_${club_id}.json" '
    {
      clubId: $clubId,
      club: {
        name:           ($info[0].name           // null),
        city:           ($info[0].city           // null),
        state:          ($info[0].state          // null),
        country:        ($info[0].country        // null),
        member_count:   ($info[0].member_count   // null),
        description:    ($info[0].description    // null),
        url:            ($info[0].url            // null),
        profile_medium: ($info[0].profile_medium // null),
        sport_type:     ($info[0].sport_type     // null)
      },
      activities: [
        .[]
        | select( ($sport == "") or (((.sport_type // .type) // "") | ascii_downcase) == $sport )
        | {
            date:                 .firstSeen,
            firstname:            .firstname,
            lastname:             .lastname,
            profile_medium:       .profile_medium,
            distance:             (.distance // 0),
            moving_time:          (.moving_time // 0),
            total_elevation_gain: (.total_elevation_gain // 0),
            sport_type:           .sport_type
          }
      ]
    }
  ' "$CLUB_STORE" > "$TMP/clubdata_${club_id}.json"

  # 5b. Emit per-club all-time leaderboard JSON and dated snapshot.
  jq -s --arg sport "$SPORT_LC" --arg generatedAt "$GENERATED_AT" '
    def athleteKey: "\(.firstname)|\(.lastname)|\(.profile_medium // "")";
    ( [ .[]
        | select( ($sport == "") or (((.sport_type // .type) // "") | ascii_downcase) == $sport )
      ]
      | group_by(athleteKey)
      | map({
          firstname: .[0].firstname,
          lastname:  .[0].lastname,
          distance:        (map(.distance // 0)             | add),
          moving_time:     (map(.moving_time // 0)          | add),
          elevation_gain:  (map(.total_elevation_gain // 0) | add),
          activity_count:  length
        }
        | . + { average_speed: (if .moving_time > 0 then (.distance / .moving_time * 3.6) else 0 end) })
      | sort_by(-.distance)
      | to_entries | map(.value + { rank: (.key + 1) })
    ) as $members
    | {
        generatedAt: $generatedAt,
        sportType:  (if $sport == "" then null else $sport end),
        totals: {
          member_count:   ($members | length),
          distance:       ($members | map(.distance)       | add // 0),
          moving_time:    ($members | map(.moving_time)    | add // 0),
          elevation_gain: ($members | map(.elevation_gain) | add // 0),
          activity_count: ($members | map(.activity_count) | add // 0)
        },
        members: $members
      }
  ' "$CLUB_STORE" > "$TMP/leaderboard_${club_id}.json"

  cp "$TMP/leaderboard_${club_id}.json" "$SNAPSHOT_DIR/${STAMP}_${club_id}.json"
  cp "$TMP/leaderboard_${club_id}.json" "$WEB_DIR/leaderboard_${club_id}.json"

  # Prune old snapshots for this club so daily runs don't fill flash.
  ls -1t "$SNAPSHOT_DIR"/*_${club_id}.json 2>/dev/null | tail -n +"$((KEEP_SNAPSHOTS + 1))" | while read -r f; do
    rm -f "$f"
  done

  printf '%s\n' "$club_id" >> "$TMP/clubs_manifest.txt"
done < "$TMP/club_ids.txt"

# --- 4b. Cookie dry-run: probe the club scrape feed (not saved) ---------------
# Runs when STRAVA_SOURCE=api but STRAVA_SESSION_COOKIE is also set. Exercises
# the full scrape pipeline — session cookie, CSRF header, feed JSON endpoint,
# and activity-entry parsing — without touching the persistent store. Verifies
# the migration path to STRAVA_SOURCE=scrape is working end-to-end.
_sc_dry_run_feed_ok=0
_sc_dry_run_meta='null'
if [ "$_scrape_dry_run" = "1" ]; then
  if [ "$_sc_check_valid" = "1" ]; then
    _sc_dry_run_feed_ok=1
    log "cookie dry-run: probing club scrape feed for all clubs (not saving)..."
    while IFS= read -r _dr_club; do
      _dr_club="$(printf '%s' "$_dr_club" | tr -d ' \t')"
      [ -n "$_dr_club" ] || continue
      _dr_csrf="$(cat "$STATE_DIR/strava_csrf.txt" 2>/dev/null || echo "")"
      _dr_url="https://www.strava.com/clubs/$_dr_club/feed?feed_type=club&club_id=$_dr_club"
      _dr_cursor=""
      _dr_page=1
      _dr_total_acts=0
      while [ "$_dr_page" -le "$MAX_PAGES" ]; do
        [ -n "$_dr_cursor" ] && _dr_url="${_dr_url%%\?*}?feed_type=club&club_id=$_dr_club&before=$_dr_cursor&cursor=$_dr_cursor"
        if ! curl_retry -fsS \
          -b "$STATE_DIR/strava_cookies.txt" \
          -H "accept: application/json, text/plain, */*" \
          -H "x-requested-with: XMLHttpRequest" \
          -H "x-csrf-token: $_dr_csrf" \
          -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
          "$_dr_url" \
          -o "$TMP/dr_feed_${_dr_club}.json" 2>/dev/null; then
          log "cookie dry-run: club $_dr_club page $_dr_page — network error"
          _sc_dry_run_feed_ok=0; break
        fi
        if ! jq -e '.entries' "$TMP/dr_feed_${_dr_club}.json" >/dev/null 2>&1; then
          log "cookie dry-run: club $_dr_club page $_dr_page — response not valid JSON (session may have expired)"
          _sc_dry_run_feed_ok=0; break
        fi
        _dr_count="$(jq '.entries | length' "$TMP/dr_feed_${_dr_club}.json")"
        _dr_acts="$(jq '[.entries[] | select(.entity == "Activity")] | length' "$TMP/dr_feed_${_dr_club}.json")"
        _dr_total_acts=$((_dr_total_acts + _dr_acts))
        log "cookie dry-run: club $_dr_club page $_dr_page — $_dr_count entries, $_dr_acts activities (not saved)"
        [ "$_dr_count" -gt 0 ] || break
        _dr_cursor="$(jq -r '(.entries[-1].cursorData.updated_at | floor | tostring)' "$TMP/dr_feed_${_dr_club}.json")"
        [ "$_dr_count" -lt "$PER_PAGE" ] && break
        _dr_page=$((_dr_page + 1))
      done
      [ "$_sc_dry_run_feed_ok" = "1" ] && \
        log "cookie dry-run: club $_dr_club — $_dr_total_acts activities fetched via scrape (not saved)"
    done < "$TMP/club_ids.txt"
  fi

  # Build _sc_dry_run_meta now that the probe result is known.
  if [ "$_sc_check_valid" = "1" ]; then
    _sc_ts="$(cat "$STATE_DIR/strava_session_age.txt" 2>/dev/null || printf '0')"
    case "$_sc_ts" in ''|*[!0-9]*) _sc_ts=0 ;; esac
    if [ "$_sc_ts" -gt 0 ]; then
      _sc_dry_run_meta="$(jq -n --argjson ts "$_sc_ts" --argjson feedOk "$_sc_dry_run_feed_ok" '{
        cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
        cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0]),
        dryRun:                true,
        cookieValid:           true,
        feedTestOk:            ($feedOk == 1)
      }')"
    else
      _sc_dry_run_meta='{"dryRun":true,"cookieValid":true,"feedTestOk":false}'
    fi
  else
    _sc_dry_run_meta='{"dryRun":true,"cookieValid":false,"feedTestOk":false}'
  fi
fi

# --- 5. Emit combined activities.json from per-club data ------------------
# Collect per-club temp file paths (paths are numeric IDs, no spaces, safe to split).
clubdata_files=""
while IFS= read -r club_id; do
  [ -n "$club_id" ] || continue
  clubdata_files="$clubdata_files $TMP/clubdata_${club_id}.json"
done < "$TMP/clubs_manifest.txt"

# Build scrapeMeta: cookie verification date + ~30-day expiry (used by dashboard banner).
# In scrape mode: real session data. In api+cookie dry-run: precomputed above.
_sc_meta='null'
if [ "$STRAVA_SOURCE" = "scrape" ]; then
  _sc_age="$(cat "$STATE_DIR/strava_session_age.txt" 2>/dev/null || printf '0')"
  case "$_sc_age" in ''|*[!0-9]*) _sc_age=0 ;; esac
  if [ "$_sc_age" -gt 0 ]; then
    _sc_meta="$(jq -n --argjson ts "$_sc_age" '{
      cookieVerifiedAt:     ($ts            | todate | split("T")[0]),
      cookieRefreshNeededBy:(($ts + 2592000) | todate | split("T")[0])
    }')"
  fi
elif [ "$_scrape_dry_run" = "1" ]; then
  _sc_meta="$_sc_dry_run_meta"
fi

# shellcheck disable=SC2086
jq -s --arg generatedAt "$GENERATED_AT" --arg sport "$SPORT_LC" \
  --arg source "$STRAVA_SOURCE" --argjson scrapeMeta "$_sc_meta" \
  '{ generatedAt: $generatedAt,
     sport: (if $sport == "" then "all" else $sport end),
     source: $source,
     scrapeMeta: $scrapeMeta,
     clubs: . }' \
  $clubdata_files > "$WEB_DIR/activities.json"

log "wrote $WEB_DIR/activities.json and per-club leaderboard JSON (snapshot $STAMP)"

# --- 6. Render the static HTML dashboard -----------------------------------
# The page fetches activities.json and does all filtering and leaderboard
# aggregation in the browser, showing one section per club. Single-quoted
# heredoc — nothing below is shell-expanded; all runtime data flows through
# activities.json.
cat > "$WEB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Club Leaderboard</title>
<style>
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:900px;padding:0 1rem;background:#fafafa;color:#222}
  h1{margin:0 0 .25rem}
  .meta{color:#666;font-size:.85rem;margin:.75rem 0 1rem}
  .filters{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;margin:.5rem 0 1rem}
  select{font:inherit;padding:.35rem .5rem;border:1px solid #ccc;border-radius:.4rem;background:#fff;color:#222}
  table{border-collapse:collapse;width:100%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08)}
  th,td{padding:.5rem .75rem;text-align:left;border-bottom:1px solid #eee}
  th{background:#fc4c02;color:#fff}
  tr:nth-child(even) td{background:#fafafa}
  td.num{text-align:right;font-variant-numeric:tabular-nums}
  .empty{color:#666;padding:1rem 0}
  .nav{margin:.25rem 0 1rem}
  .nav a{display:inline-block;padding:.4rem .75rem;background:#fc4c02;color:#fff;text-decoration:none;border-radius:.4rem;font-size:.85rem;font-weight:600}
  .nav a:hover{background:#e34402}
  .club-section{margin-bottom:2rem}
  .club-heading{color:#fc4c02;margin:1.25rem 0 .25rem;font-size:1.1rem;border-bottom:2px solid #fc4c02;padding-bottom:.25rem;display:flex;align-items:center;gap:.5rem}
  .club-heading img{width:1.6rem;height:1.6rem;border-radius:50%;object-fit:cover;flex-shrink:0}
  .club-heading a{font-size:.7em;font-weight:normal;color:#fc4c02;margin-left:auto}
  .club-sub{color:#666;font-size:.82rem;margin:0 0 .5rem}
  .club-desc{color:#555;font-size:.82rem;margin:0 0 .75rem;font-style:italic}
  .ck-banner{padding:.55rem 1rem;border-radius:.4rem;margin:.5rem 0 1rem;font-size:.88rem}
  .ck-ok{background:#e8f5e9;color:#2e7d32;border:1px solid #a5d6a7}
  .ck-warn{background:#fff8e1;color:#e65100;border:1px solid #ffe082;font-weight:600}
  .ck-expired{background:#ffebee;color:#b71c1c;border:1px solid #ef9a9a;font-weight:600}
  .bar{height:5px;background:#fc4c02;border-radius:3px;margin-top:4px;min-width:3px}
</style>
</head>
<body>
<h1>🏆 Club Leaderboard</h1>
<div class="nav"><a href="me/">→ My Activities</a></div>
<div class="filters">
  <label>Year <select id="year"></select></label>
  <label>Month <select id="month"></select></label>
</div>
<div class="meta" id="meta">Loading…</div>
<div id="board"></div>
<div id="ck-banner" style="display:none"></div>
<div class="meta" id="footer-meta">
  StravaStats for OpenWrt · <span id="footer-source"></span> · <a href="activities.json">activities.json</a><span id="footer-links"></span>
</div>
<script>
"use strict";
var MONTHS = ["January","February","March","April","May","June","July",
              "August","September","October","November","December"];
var yearSel = document.getElementById("year");
var monthSel = document.getElementById("month");
var meta = document.getElementById("meta");
var board = document.getElementById("board");
var footerLinks = document.getElementById("footer-links");
var DATA = null;

function fmtKm(m){ return (m/1000).toFixed(1); }
function fmtTime(s){ return Math.floor(s/3600)+"h "+Math.floor((s%3600)/60)+"m"; }
function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }

function renderCookieBanner(meta){
  var el = document.getElementById("ck-banner");
  if(!meta){ el.style.display="none"; return; }
  var dr = meta.dryRun ? true : false;
  var pfx = dr ? "Cookie dry-run — " : "";
  if(!meta.cookieRefreshNeededBy){
    if(dr && meta.cookieValid === false){
      el.className = "ck-banner ck-expired";
      el.innerHTML = "&#9888; "+pfx+"<code>STRAVA_SESSION_COOKIE</code> has <strong>expired</strong>"+
                     " &mdash; paste a fresh <code>_strava4_session</code> value into"+
                     " <code>STRAVA_SESSION_COOKIE</code> in <code>/etc/strava-leaderboard.conf</code>";
      el.style.display = "";
    } else {
      el.style.display = "none";
    }
    return;
  }
  var daysLeft = Math.ceil((new Date(meta.cookieRefreshNeededBy) - new Date()) / 86400000);
  var cls, msg;
  if(daysLeft <= 0){
    cls = "ck-expired";
    msg = "&#9888; "+pfx+"session cookie has expired &mdash; paste a fresh <code>_strava4_session</code> value"+
          " into <code>STRAVA_SESSION_COOKIE</code> in <code>/etc/strava-leaderboard.conf</code>";
  } else if(daysLeft <= 7){
    cls = "ck-warn";
    msg = "&#9888; "+pfx+"session cookie expires in "+daysLeft+" day"+(daysLeft===1?"":"s")+
          " ("+esc(meta.cookieRefreshNeededBy)+") &mdash; refresh <code>_strava4_session</code> soon";
  } else if(dr && meta.feedTestOk === false){
    cls = "ck-warn";
    msg = "&#9888; Cookie dry-run &mdash; cookie valid but feed fetch failed"+
          " (check network or club ID); valid until "+esc(meta.cookieRefreshNeededBy)+" ("+daysLeft+" days)";
  } else {
    cls = "ck-ok";
    var feedNote = dr ? (meta.feedTestOk ? " — feed test OK" : "") : "";
    msg = "&#10003; "+(dr ? "Cookie dry-run (api mode)" : "Scrape mode")+
          " &mdash; cookie verified "+esc(meta.cookieVerifiedAt)+
          ", valid until "+esc(meta.cookieRefreshNeededBy)+" ("+daysLeft+" days)"+feedNote;
  }
  el.className = "ck-banner "+cls;
  el.innerHTML = msg;
  el.style.display = "";
}

function fallbackToLatestMonth(acts, year, month) {
  var y = year, m = month;
  for (var i = 0; i < 24; i++) {
    var yy = y, mm = m;
    if (acts.some(function(a){ return a.date && +a.date.slice(0,4)===yy && +a.date.slice(5,7)===mm; }))
      return { year: yy, month: mm };
    m--; if (m===0){ m=12; y--; }
    if (y < 2000) break;
  }
  return null;
}

function init(){
  renderCookieBanner(DATA.scrapeMeta || null);
  var clubs = DATA.clubs || [];
  var allActs = [];
  clubs.forEach(function(c){ (c.activities||[]).forEach(function(a){ allActs.push(a); }); });

  var now = new Date();
  var curYear = now.getFullYear();
  var curMonth = now.getMonth()+1;

  var yset = {};
  allActs.forEach(function(a){ if(a.date) yset[+a.date.slice(0,4)]=true; });
  yset[curYear] = true;
  var years = Object.keys(yset).map(Number).sort(function(a,b){ return b-a; });

  yearSel.innerHTML = years.map(function(y){
    return '<option value="'+y+'">'+y+'</option>';
  }).join("");
  yearSel.value = years.indexOf(curYear)>=0 ? curYear : years[0];

  var opts = ['<option value="all">Whole year</option>'];
  for(var i=0;i<12;i++) opts.push('<option value="'+(i+1)+'">'+MONTHS[i]+'</option>');
  monthSel.innerHTML = opts.join("");
  monthSel.value = String(curMonth);

  var _fb = fallbackToLatestMonth(allActs, +yearSel.value, +monthSel.value);
  if(_fb){ yearSel.value=String(_fb.year); monthSel.value=String(_fb.month); }

  var lks = "";
  clubs.forEach(function(c){
    var label = (c.club && c.club.name) ? esc(c.club.name) : ('club '+esc(c.clubId));
    lks += ' · <a href="leaderboard_'+esc(c.clubId)+'.json">'+label+' all-time JSON</a>';
  });
  footerLinks.innerHTML = lks;
  var fsrc = document.getElementById("footer-source");
  if(fsrc) fsrc.textContent = DATA.source === "scrape"
    ? "scrape mode · real activity dates"
    : "api mode · dates = first-seen day";

  yearSel.onchange = render;
  monthSel.onchange = render;
  render();
}

function renderClubTable(acts){
  var map = {};
  acts.forEach(function(a){
    var k = a.firstname+"|"+a.lastname+"|"+(a.profile_medium||"");
    var e = map[k];
    if(!e){ e=map[k]={firstname:a.firstname,lastname:a.lastname,distance:0,moving_time:0,elev:0,count:0}; }
    e.distance+=a.distance||0;
    e.moving_time+=a.moving_time||0;
    e.elev+=a.total_elevation_gain||0;
    e.count++;
  });
  var members = Object.keys(map).map(function(k){ return map[k]; })
    .sort(function(x,y){ return y.distance-x.distance; });
  if(members.length===0) return '<p class="empty">No activities for this period.</p>';
  var maxDist = members[0].distance || 1;
  var html = '<table><thead><tr><th>#</th><th>Athlete</th><th>Distance</th>'+
    '<th>Time</th><th>Elev (m)</th><th>Activities</th><th>Avg km/h</th></tr></thead><tbody>';
  members.forEach(function(m,i){
    var avg = m.moving_time>0 ? (m.distance/m.moving_time*3.6) : 0;
    var pct = maxDist>0 ? Math.max(3, Math.round(m.distance/maxDist*100)) : 3;
    html += '<tr><td class="num">'+(i+1)+'</td>'+
      '<td>'+esc(m.firstname)+' '+esc(m.lastname)+'</td>'+
      '<td class="num">'+fmtKm(m.distance)+' km<div class="bar" style="width:'+pct+'%"></div></td>'+
      '<td class="num">'+fmtTime(m.moving_time)+'</td>'+
      '<td class="num">'+Math.floor(m.elev)+'</td>'+
      '<td class="num">'+m.count+'</td>'+
      '<td class="num">'+avg.toFixed(1)+'</td></tr>';
  });
  html += '</tbody></table>';
  return html;
}

function render(){
  var year = +yearSel.value;
  var month = monthSel.value;
  var label = month==="all" ? String(year) : MONTHS[+month-1]+" "+year;
  var clubs = DATA.clubs || [];
  var sport = DATA.sport || "all";

  var totalDist = 0, totalActs = 0;
  var html = "";

  clubs.forEach(function(club){
    var acts = (club.activities||[]).filter(function(a){
      if(!a.date) return false;
      if(+a.date.slice(0,4)!==year) return false;
      if(month!=="all" && +a.date.slice(5,7)!==+month) return false;
      return true;
    });
    acts.forEach(function(a){ totalDist+=a.distance||0; totalActs++; });
    var info = club.club || {};
    var title = info.name ? esc(info.name) : ('Club '+esc(club.clubId));
    html += '<section class="club-section">';
    html += '<h2 class="club-heading">';
    if(info.profile_medium)
      html += '<img src="'+esc(info.profile_medium)+'" alt="">';
    html += title;
    if(info.url)
      html += '<a href="https://www.strava.com/clubs/'+esc(info.url)+'" target="_blank" rel="noopener">strava.com/clubs/'+esc(info.url)+'</a>';
    html += '</h2>';
    var sub = [];
    if(info.city || info.country) sub.push([info.city,info.country].filter(Boolean).map(esc).join(', '));
    if(info.member_count) sub.push(info.member_count+' members');
    if(info.sport_type) sub.push(esc(info.sport_type));
    if(sub.length) html += '<p class="club-sub">'+sub.join(' · ')+'</p>';
    if(info.description) html += '<p class="club-desc">'+esc(info.description)+'</p>';
    html += renderClubTable(acts);
    html += '</section>';
  });

  meta.innerHTML = "Sport: "+esc(sport)+" · "+clubs.length+" club(s) · "+
    totalActs+" activities · "+fmtKm(totalDist)+" km total · "+esc(label)+
    " · generated "+esc(DATA.generatedAt||"");
  board.innerHTML = html;
}

fetch("activities.json",{cache:"no-store"})
  .then(function(r){ if(!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
  .then(function(d){ DATA=d; init(); })
  .catch(function(err){
    meta.textContent="Failed to load activities.json ("+err.message+
      "). Open this page via the router's web server, not from a file.";
  });
</script>
</body>
</html>
HTML

log "wrote $WEB_DIR/index.html"
log "done."
