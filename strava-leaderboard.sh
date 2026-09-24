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
MAX_PAGES="${STRAVA_MAX_PAGES:-20}"
PER_PAGE="${STRAVA_PER_PAGE:-200}"
WEB_DIR="${STRAVA_WEB_DIR:-/www/strava}"
STATE_DIR="${STRAVA_STATE_DIR:-/usr/lib/strava-leaderboard}"  # must survive reboot (NOT /tmp or /var on OpenWrt)
SNAPSHOT_DIR="$STATE_DIR/snapshots"
KEEP_SNAPSHOTS="${STRAVA_KEEP_SNAPSHOTS:-90}"
EXCLUDE_ATHLETES="${STRAVA_EXCLUDE_ATHLETES:-}"   # comma-separated "Firstname Lastname" to hide
MERGE_ATHLETES="${STRAVA_MERGE_ATHLETES:-}"     # comma-separated "Canonical=Alias" pairs to merge
ELEV_FETCH_MAX="${STRAVA_ELEV_FETCH_MAX:-20}"   # max Run elevation page-fetches per club per run (scrape mode)

command -v curl >/dev/null 2>&1 || die "curl not installed (apk add curl ca-bundle  /  opkg install curl ca-bundle)"
command -v jq   >/dev/null 2>&1 || die "jq not installed (apk add jq  /  opkg install jq)"

mkdir -p "$WEB_DIR" "$SNAPSHOT_DIR"

TOKEN_STATE="$STATE_DIR/token.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/strava.XXXXXX")"
LOCKFILE="${TMPDIR:-/tmp}/strava-leaderboard.lock"
if ! mkdir "$LOCKFILE" 2>/dev/null; then
  _lock_pid="$(cat "$LOCKFILE/pid" 2>/dev/null || true)"
  if [ -n "$_lock_pid" ] && kill -0 "$_lock_pid" 2>/dev/null; then
    log "another instance is already running (PID $_lock_pid, $LOCKFILE); exiting"
    rm -rf "$TMP"; exit 0
  else
    log "stale lock found (PID ${_lock_pid:-unknown} not running); removing and continuing"
    rm -rf "$LOCKFILE"
    mkdir "$LOCKFILE"
  fi
fi
printf '%s\n' "$$" > "$LOCKFILE/pid"
trap '_rc=$?; rm -rf "$TMP" "$LOCKFILE"; [ $_rc -ne 0 ] && log "FATAL: strava-leaderboard exited with code $_rc"' EXIT

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
SCRAPE_START_DATE="${STRAVA_SCRAPE_START_DATE:-}"
if [ -n "$SCRAPE_START_DATE" ]; then
  case "$SCRAPE_START_DATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "STRAVA_SCRAPE_START_DATE must be YYYY-MM-DD, got: $SCRAPE_START_DATE" ;;
  esac
fi
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
      log "club $club_id: GET /api/v3/clubs/$club_id"
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
      else
        log "club $club_id: fetching club page via scrape..."
        if curl_retry -fsS \
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
        log "  page $page: GET /api/v3/clubs/$club_id/activities?per_page=$PER_PAGE&page=$page"
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
        log "  page $page: GET $_sc_url"
        curl_retry -fsS \
          -b "$STATE_DIR/strava_cookies.txt" \
          -H "accept: application/json, text/plain, */*" \
          -H "x-requested-with: XMLHttpRequest" \
          -H "x-csrf-token: $_sc_csrf" \
          -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
          "$_sc_url" \
          -o "$TMP/page.json" || die "feed fetch failed (club $club_id page $page)"
        if ! jq -e '.entries' "$TMP/page.json" >/dev/null 2>&1; then
          if grep -qiE 'Log In to Strava|id="login-form"|action="/session"' "$TMP/page.json" 2>/dev/null; then
            die "club $club_id feed: Strava returned the login page — STRAVA_SESSION_COOKIE has expired; copy a fresh _strava4_session value from browser DevTools (Application → Cookies → strava.com) and delete $STATE_DIR/strava_session_age.txt"
          fi
          _feed_sample="$(head -c 300 "$TMP/page.json" | tr '\n\r' '  ')"
          _feed_keys="$(jq -r 'if type == "object" then keys[] else "not-an-object" end' "$TMP/page.json" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
          die "LAYOUT CHANGE DETECTED: club $club_id feed page $page — .entries field missing from response (Strava may have changed the club feed JSON structure); top-level keys: [${_feed_keys}]; response starts: ${_feed_sample}; expected field: .entries[]"
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

  # Pre-filter: grep removes lines that are not complete JSON objects (e.g.
  # truncated by an interrupted write) before jq ever opens the file.  grep reads
  # bytes without JSON-parsing, so it cannot trigger jq's assertion-crash.
  grep '^{.*}$' "$CLUB_STORE" > "$TMP/store_pre_${club_id}.ndjson" 2>/dev/null \
    || : > "$TMP/store_pre_${club_id}.ndjson"

  if [ -s "$TMP/store_pre_${club_id}.ndjson" ]; then
    jq -sc '[ .[].signature ]' "$TMP/store_pre_${club_id}.ndjson" > "$TMP/known.json" \
      || printf '[]\n' > "$TMP/known.json"
  else
    printf '[]\n' > "$TMP/known.json"
  fi
  [ -s "$TMP/fetched.json" ] || printf '[]\n' > "$TMP/fetched.json"

  # Combine known+fetched into one object to avoid --slurpfile, which triggers
  # a jq assertion crash (cb == jq_util_input_next_input_cb) on OpenWrt jq when
  # jq tries to report an error position for a slurpfile input.
  { printf '{"known":'; cat "$TMP/known.json"; \
    printf ',"fetched":'; cat "$TMP/fetched.json"; printf '}'; } \
    > "$TMP/merge_input.json"
  case "$STRAVA_SOURCE" in
    api)
      jq -c \
        --arg today "$FIRST_SEEN" '
        def sig:
          [ ((.athlete.firstname // "") | ascii_downcase),
            ((.athlete.lastname  // "") | ascii_downcase),
            (.distance             // 0 | tostring),
            (.moving_time          // 0 | tostring),
            (.elapsed_time         // 0 | tostring),
            ((.sport_type // .type // "") | ascii_downcase)
          ] | join("|");
        ( (.known // []) | map({ (.): true }) | add // {} ) as $seen
        | [ .fetched[] | { s: sig, a: . } ]
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
      ' "$TMP/merge_input.json" > "$TMP/new.ndjson"
      ;;
    scrape)
      # Stats arrive as HTML strings: strip tags, parse numbers.
      # distance: "34.30<abbr...> km</abbr>" → 34300 m
      # elev:     "108<abbr...> m</abbr>"    → 108 m
      # time:     "1<abbr>h</abbr> 27<abbr>m</abbr>" → seconds
      jq -c \
        --arg cutoff "$SCRAPE_START_DATE" '
        def _n: if (. == null or . == "") then 0 else tonumber end;
        # strip_html and digits avoid gsub/capture (both crash on this jq build:
        # the regex engine calls jq_util_input_get_position on any error, which
        # asserts because the error-callback state is uninitialised in this build).
        def strip_html:
          [split("<")[0]] + [split("<")[1:][] | split(">")[1:] | join(">")] | join("");
        def digits:
          [explode[] | select(. == 46 or (. >= 48 and . <= 57))] | implode;
        def parse_km:   strip_html | digits | if . == "" or . == "." then 0 else tonumber end * 1000;
        def parse_elev: strip_html | digits | if . == "" or . == "." then 0 else tonumber end;
        def parse_time:
          strip_html | . as $t |
          (if ($t|contains("h")) then ($t|split("h")[0]|digits|_n) else 0 end) * 3600 +
          (if ($t|contains("m"))
           then ((if ($t|contains("h")) then $t|split("h")[1] else $t end)|split("m")[0]|digits|_n)
           else 0 end) * 60 +
          (if ($t|contains("s"))
           then ((if ($t|contains("m")) then $t|split("m")[1] else
                  if ($t|contains("h")) then $t|split("h")[1] else $t end end)|split("s")[0]|digits|_n)
           else 0 end);
        ( (.known // []) | map({ (.): true }) | add // {} ) as $seen
        | [ .fetched[]
            | select(.entity == "Activity" or .entity == "GroupActivity")
            | (if .entity == "GroupActivity"
               then (.rowData.activities // [])[]
                    | {id: (.entity_id_str // ""),
                       stats: (.stats // []),
                       athlete: {firstName: (.athlete_firstname // ""),
                                 athleteName: (.athlete_name // ""),
                                 avatarUrl: (.athlete_avatar_url // "")},
                       activityName: (.name // ""),
                       type: (.type // ""),
                       startDate: (.start_date // ""),
                       elapsedTime: (.elapsed_time // 0)}
               else .activity
                    | . + {athlete: ((.athlete // {}) + {
                                      athleteName: (((.athlete.firstName // "") + " " + (.athlete.lastName // "")) | ltrimstr(" ") | rtrimstr(" "))}),
                           elapsedTime: (.elapsed_time // 0)}
               end)
            | select(. != null and (.id // "") != "")
            | ((.stats // []) | map(select(.key == "stat_one"))   | .[0].value // "") as $s1
            | ((.stats // []) | map(select(.key == "stat_two"))   | .[0].value // "") as $s2
            | ((.stats // []) | map(select(.key == "stat_three")) | .[0].value // "") as $s3
            | ($s3 | parse_time) as $pt3
            | ($s2 | parse_time) as $pt2
            | (.athlete.firstName // "") as $fn
            | (.athlete.athleteName // "") as $an
            | {
                s:         .id,
                firstname: $fn,
                lastname:  ($an | ltrimstr($fn) | ltrimstr(" ")),
                profile_medium: (.athlete.avatarUrl // ""),
                name:      (.activityName // ""),
                distance:  ($s1 | parse_km),
                moving_time: (if $pt3 > 0 then $pt3
                              elif $pt2 > 0 then $pt2
                              else (.elapsedTime // 0) end),
                elapsed_time: (.elapsedTime // 0),
                total_elevation_gain: (if (($pt3 == 0) and ($pt2 > 0)) or ($s2 | strip_html | contains("/")) then 0
                                       else ($s2 | parse_elev) end),
                type:      (.type // ""),
                sport_type: (.type // ""),
                firstSeen: (.startDate // "" | split("T")[0])
              }
          ]
        | unique_by(.s)
        | map(select(($seen[.s] | not) and ($cutoff == "" or .firstSeen >= $cutoff) and (.distance <= 2000000)))
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
      ' "$TMP/merge_input.json" > "$TMP/new.ndjson"
      ;;
  esac

  ADDED="$(wc -l < "$TMP/new.ndjson" | tr -d ' ')"
  cat "$TMP/new.ndjson" >> "$CLUB_STORE"
  case "$STRAVA_SOURCE" in
    api)    log "club $club_id: +$ADDED new (firstSeen $FIRST_SEEN), $(wc -l < "$CLUB_STORE" | tr -d ' ') total" ;;
    scrape) log "club $club_id: +$ADDED new (actual dates), $(wc -l < "$CLUB_STORE" | tr -d ' ') total" ;;
  esac

  # Backfill: for scrape mode, patch any existing store entries that have a blank
  # lastname or missing profile_medium, using name/avatar data from the current
  # feed.  This self-heals entries stored before the Activity-entity lastName fix.
  # Only entries whose activity ID appears in this run's feed can be patched;
  # older entries no longer in the feed remain unchanged.
  case "$STRAVA_SOURCE" in
    scrape)
      _bf_any="$(grep -c '"lastname":""' "$CLUB_STORE" 2>/dev/null || printf '0')"
      if [ "${_bf_any:-0}" -gt 0 ]; then
        jq -c '
          def strip_html:
            [split("<")[0]] + [split("<")[1:][] | split(">")[1:] | join(">")] | join("");
          def digits:
            [explode[] | select(. == 46 or (. >= 48 and . <= 57))] | implode;
          [ .fetched[]
            | select(.entity == "Activity" or .entity == "GroupActivity")
            | (if .entity == "GroupActivity"
               then (.rowData.activities // [])[]
                    | {id: (.entity_id_str // ""),
                       athlete: {firstName: (.athlete_firstname // ""),
                                 athleteName: (.athlete_name // ""),
                                 avatarUrl: (.athlete_avatar_url // "")}}
               else .activity
                    | . + {athlete: ((.athlete // {}) + {
                                      athleteName: (((.athlete.firstName // "") + " " + (.athlete.lastName // "")) | ltrimstr(" ") | rtrimstr(" "))})}
                    | {id: .id, athlete: .athlete}
               end)
            | select((.id // "") != "")
            | (.athlete.firstName // "") as $fn
            | (.athlete.athleteName // "") as $an
            | {id: .id, fn: $fn, ln: ($an | ltrimstr($fn) | ltrimstr(" ")),
               pm: (.athlete.avatarUrl // "")}
            | select(.ln != "" or .pm != "")
          ] as $ents
          | {
              nm: ($ents | map({(.id): .}) | add // {}),
              fn_map: (
                $ents | map(select(.ln != "")) | group_by(.fn)
                | map(select((map(.ln) | unique | length) == 1))
                | map({(.[0].fn): {
                    ln: .[0].ln,
                    pm: ([.[].pm] | map(select(. != "")) | if length > 0 then .[0] else "" end)
                  }})
                | add // {}
              )
            }
        ' "$TMP/merge_input.json" > "$TMP/name_map.json"
        _nm_count="$(jq '(.nm | length) + (.fn_map | length)' "$TMP/name_map.json")"
        if [ "${_nm_count:-0}" -gt 0 ]; then
          jq -sc --argjson maps "$(cat "$TMP/name_map.json")" '
            ($maps.nm // {}) as $nm | ($maps.fn_map // {}) as $fn_map |
            [ .[]
              | ($nm[.signature]) as $m
              | if $m != null then
                  (if (.lastname == "" or .lastname == null) and ($m.ln // "") != ""
                   then {lastname: $m.ln} else {} end) as $ln |
                  (if (.profile_medium == "" or .profile_medium == null) and ($m.pm // "") != ""
                   then {profile_medium: $m.pm} else {} end) as $pm |
                  . + $ln + $pm
                elif (.lastname == "" or .lastname == null) and ($fn_map[.firstname] != null) then
                  ($fn_map[.firstname]) as $f |
                  (if ($f.ln // "") != "" then {lastname: $f.ln} else {} end) as $ln |
                  (if (.profile_medium == "" or .profile_medium == null) and ($f.pm // "") != ""
                   then {profile_medium: $f.pm} else {} end) as $pm |
                  . + $ln + $pm
                else .
                end
            ] | .[]
          ' "$TMP/store_pre_${club_id}.ndjson" > "$TMP/store_backfilled.ndjson"
          cat "$TMP/new.ndjson" >> "$TMP/store_backfilled.ndjson"
          mv "$TMP/store_backfilled.ndjson" "$CLUB_STORE"
          log "club $club_id: backfilled names/avatars for existing entries (${_bf_any} blank)"
        fi
      fi
      ;;
  esac

  # Backfill: for scrape mode, fetch elevation from individual activity pages
  # for Run activities where the club feed only shows pace as stat_two.
  # Results are cached in run_elev_cache.json so each activity is fetched once.
  case "$STRAVA_SOURCE" in
    scrape)
      ELEV_CACHE="$STATE_DIR/run_elev_cache.json"
      [ -f "$ELEV_CACHE" ] || printf '{}' > "$ELEV_CACHE"
      jq -r --argjson cache "$(cat "$ELEV_CACHE")" '
        select(.sport_type == "Run" and (.total_elevation_gain // 0) == 0)
        | .signature
        | select($cache[.] == null)
      ' "$CLUB_STORE" | sort -u | head -"$ELEV_FETCH_MAX" > "$TMP/needs_elev.txt" 2>/dev/null || :
      _ef_count="$(wc -l < "$TMP/needs_elev.txt" | tr -d ' ')"
      if [ "${_ef_count:-0}" -gt 0 ]; then
        log "club $club_id: fetching elevation for $_ef_count Run activities (max $ELEV_FETCH_MAX)..."
        ensure_session_cookie
        _ef_ok=0
        while IFS= read -r _ef_sig; do
          _ef_page="$TMP/act_${_ef_sig}.html"
          if curl_retry -s -L -b "$STATE_DIR/strava_cookies.txt" \
            "https://www.strava.com/activities/${_ef_sig}" \
            -o "$_ef_page" 2>/dev/null; then
            _ef_elev="$(sed -n 's/^[[:space:]]*elev_gain: \([0-9][0-9]*\).*/\1/p' \
              "$_ef_page" 2>/dev/null | head -1)"
            if [ -n "$_ef_elev" ]; then
              jq -c --arg s "$_ef_sig" --argjson e "$_ef_elev" \
                '. + {($s): $e}' "$ELEV_CACHE" > "$ELEV_CACHE.tmp" \
                && mv "$ELEV_CACHE.tmp" "$ELEV_CACHE"
              _ef_ok=$(( _ef_ok + 1 ))
            else
              jq -c --arg s "$_ef_sig" '. + {($s): -1}' \
                "$ELEV_CACHE" > "$ELEV_CACHE.tmp" \
                && mv "$ELEV_CACHE.tmp" "$ELEV_CACHE"
            fi
            rm -f "$_ef_page"
          fi
          sleep 2
        done < "$TMP/needs_elev.txt"
        log "club $club_id: elevation fetched for $_ef_ok/$_ef_count Run activities"
        jq -c --argjson cache "$(cat "$ELEV_CACHE")" '
          if .sport_type == "Run" and (.total_elevation_gain // 0) == 0
             and ($cache[.signature] != null) and ($cache[.signature] > 0)
          then .total_elevation_gain = $cache[.signature]
          else .
          end
        ' "$CLUB_STORE" > "$TMP/store_elev.ndjson" \
          && mv "$TMP/store_elev.ndjson" "$CLUB_STORE"
      fi
      ;;
  esac

  # Rebuild the grep-filtered view of the store after merge (new entries are valid
  # jq output so they pass the filter; the check prevents any pre-existing bad
  # lines from reaching jq's NDJSON parser in 5a/5b).
  grep '^{.*}$' "$CLUB_STORE" > "$TMP/store_${club_id}.json" 2>/dev/null \
    || : > "$TMP/store_${club_id}.json"

  # 5a. Emit per-club activities temp file (assembled into activities.json below).
  jq -s --arg clubId "$club_id" --arg sport "$SPORT_LC" \
    --argjson info "$(cat "$TMP/club_info_${club_id}.json")" \
    --arg exclude "$EXCLUDE_ATHLETES" \
    --arg merge "$MERGE_ATHLETES" \
    "$JQ_MERGE_FUNC"'
    ($exclude | if . == "" then []
                else split(",") | map(ascii_downcase | ltrimstr(" ") | rtrimstr(" ")) | map(select(. != ""))
                end) as $excl |
    {
      clubId: $clubId,
      club: {
        name:           ($info.name           // null),
        city:           ($info.city           // null),
        state:          ($info.state          // null),
        country:        ($info.country        // null),
        member_count:   ($info.member_count   // null),
        description:    ($info.description    // null),
        url:            ($info.url            // null),
        profile_medium: ($info.profile_medium // null),
        sport_type:     ($info.sport_type     // null)
      },
      activities: ([ .[]
        | select( ($sport == "") or (((.sport_type // .type) // "") | ascii_downcase) == $sport )
        | applyMerge
        | ( (.firstname // "" | ascii_downcase) + " " + (.lastname // "" | ascii_downcase) ) as $fn
        | select( ($excl | length) == 0 or ([$excl[] | select(. == $fn)] | length == 0) )
      ] | normArr | [.[]
        | {
            date:                 .firstSeen,
            firstname:            .firstname,
            lastname:             .lastname,
            profile_medium:       .profile_medium,
            distance:             (.distance // 0),
            moving_time:          (.moving_time // 0),
            total_elevation_gain: (.total_elevation_gain // 0),
            sport_type:           .sport_type,
            signature:            .signature
          }
      ])
    }
  ' "$TMP/store_${club_id}.json" > "$TMP/clubdata_${club_id}.json"

  # 5b. Emit per-club all-time leaderboard JSON and dated snapshot.
  jq -s --arg sport "$SPORT_LC" --arg generatedAt "$GENERATED_AT" \
    --arg exclude "$EXCLUDE_ATHLETES" \
    --arg merge "$MERGE_ATHLETES" \
    "$JQ_MERGE_FUNC"'
    ($exclude | if . == "" then []
                else split(",") | map(ascii_downcase | ltrimstr(" ") | rtrimstr(" ")) | map(select(. != ""))
                end) as $excl |
    def athleteKey: "\(.firstname)|\(.lastname)";
    ( [ .[]
        | select( ($sport == "") or (((.sport_type // .type) // "") | ascii_downcase) == $sport )
        | applyMerge
        | ( (.firstname // "" | ascii_downcase) + " " + (.lastname // "" | ascii_downcase) ) as $fn
        | select( ($excl | length) == 0 or ([$excl[] | select(. == $fn)] | length == 0) )
      ]
      | normArr
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
  ' "$TMP/store_${club_id}.json" > "$TMP/leaderboard_${club_id}.json"

  cp "$TMP/leaderboard_${club_id}.json" "$SNAPSHOT_DIR/${STAMP}_${club_id}.json"
  cp "$TMP/leaderboard_${club_id}.json" "$WEB_DIR/leaderboard_${club_id}.json.tmp" \
  && mv "$WEB_DIR/leaderboard_${club_id}.json.tmp" "$WEB_DIR/leaderboard_${club_id}.json"

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
  # Always probe the feed regardless of cookie validity — report both results.
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
        if grep -qiE 'Log In to Strava|id="login-form"|action="/session"' "$TMP/dr_feed_${_dr_club}.json" 2>/dev/null; then
          log "cookie dry-run: club $_dr_club page $_dr_page — Strava returned login page; STRAVA_SESSION_COOKIE has expired"
        else
          _dr_sample="$(head -c 200 "$TMP/dr_feed_${_dr_club}.json" | tr '\n\r' '  ')"
          _dr_keys="$(jq -r 'if type == "object" then keys[] else "not-an-object" end' "$TMP/dr_feed_${_dr_club}.json" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
          log "cookie dry-run: LAYOUT CHANGE DETECTED — club $_dr_club page $_dr_page — .entries missing from feed response; top-level keys: [${_dr_keys}]; response starts: ${_dr_sample}"
        fi
        _sc_dry_run_feed_ok=0; break
      fi
      _dr_count="$(jq '.entries | length' "$TMP/dr_feed_${_dr_club}.json")"
      _dr_acts="$(jq '[.entries[] | if .entity == "Activity" then . elif .entity == "GroupActivity" then (.rowData.activities // [])[] else empty end] | length' "$TMP/dr_feed_${_dr_club}.json")"
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

  # Build _sc_dry_run_meta reflecting both the cookie check and feed probe results.
  _sc_ts="$(cat "$STATE_DIR/strava_session_age.txt" 2>/dev/null || printf '0')"
  case "$_sc_ts" in ''|*[!0-9]*) _sc_ts=0 ;; esac
  if [ "$_sc_ts" -gt 0 ]; then
    _sc_dry_run_meta="$(jq -n --argjson ts "$_sc_ts" --argjson cookieOk "$_sc_check_valid" --argjson feedOk "$_sc_dry_run_feed_ok" '{
      cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
      cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0]),
      dryRun:                true,
      cookieValid:           ($cookieOk == 1),
      feedTestOk:            ($feedOk == 1)
    }')"
  else
    _sc_dry_run_meta="$(jq -n --argjson cookieOk "$_sc_check_valid" --argjson feedOk "$_sc_dry_run_feed_ok" '{
      dryRun:      true,
      cookieValid: ($cookieOk == 1),
      feedTestOk:  ($feedOk == 1)
    }')"
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

log "aggregating leaderboard JSON..."
# shellcheck disable=SC2086
jq -s --arg generatedAt "$GENERATED_AT" --arg sport "$SPORT_LC" \
  --arg source "$STRAVA_SOURCE" --argjson scrapeMeta "$_sc_meta" \
  '{ generatedAt: $generatedAt,
     sport: (if $sport == "" then "all" else $sport end),
     source: $source,
     scrapeMeta: $scrapeMeta,
     clubs: . }' \
  $clubdata_files > "$WEB_DIR/activities.json.tmp" \
  && mv "$WEB_DIR/activities.json.tmp" "$WEB_DIR/activities.json"

log "wrote $WEB_DIR/activities.json and per-club leaderboard JSON (snapshot $STAMP)"


# --- 6. Render the static HTML dashboard (see strava-leaderboard-html.sh) ---
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-leaderboard-html.sh"

log "done."
