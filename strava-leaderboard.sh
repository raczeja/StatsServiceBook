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
  $clubdata_files > "$WEB_DIR/activities.json"

log "wrote $WEB_DIR/activities.json and per-club leaderboard JSON (snapshot $STAMP)"

# --- 6. Render the static HTML dashboard -----------------------------------
# The page fetches activities.json and does all filtering and leaderboard
# aggregation in the browser, showing one section per club. Single-quoted
# heredoc — nothing below is shell-expanded; all runtime data flows through
# activities.json.
log "rendering HTML..."
cat > "$WEB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t;</script>
<title>Club Leaderboard</title>
<style>
  :root{--bg:#fafafa;--surface:#fff;--surface-2:#f5f5f5;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--border:#eee;--border-2:#ccc;--row-alt:#fafafa;--accent:#fc4c02;--detail-th:#e8e8e8;--hover-row:#fff0eb}
  @media(prefers-color-scheme:dark){:root{--bg:#121212;--surface:#1e1e1e;--surface-2:#252525;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--border:#2a2a2a;--border-2:#3a3a3a;--row-alt:#1a1a1a;--detail-th:#2a2a2a;--hover-row:#2a1200}}
  [data-theme=light]{--bg:#fafafa;--surface:#fff;--surface-2:#f5f5f5;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--border:#eee;--border-2:#ccc;--row-alt:#fafafa;--accent:#fc4c02;--detail-th:#e8e8e8;--hover-row:#fff0eb}
  [data-theme=dark]{--bg:#121212;--surface:#1e1e1e;--surface-2:#252525;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--border:#2a2a2a;--border-2:#3a3a3a;--row-alt:#1a1a1a;--detail-th:#2a2a2a;--hover-row:#2a1200}
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:900px;padding:0 1rem;background:var(--bg);color:var(--text)}
  h1{margin:0 0 .25rem}
  .meta{color:var(--text-3);font-size:.85rem;margin:.75rem 0 1rem}
  .filters{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;margin:.5rem 0 1rem}
  select{font:inherit;padding:.35rem .5rem;border:1px solid var(--border-2);border-radius:.4rem;background:var(--surface);color:var(--text)}
  table{border-collapse:collapse;width:100%;background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08)}
  th,td{padding:.5rem .75rem;text-align:left;border-bottom:1px solid var(--border)}
  th{background:#fc4c02;color:#fff}
  tr:nth-child(even) td{background:var(--row-alt)}
  td.num{text-align:right;font-variant-numeric:tabular-nums}
  .empty{color:var(--text-3);padding:1rem 0}
  .nav{margin:.25rem 0 1rem}
  .nav a{display:inline-block;padding:.4rem .75rem;background:#fc4c02;color:#fff;text-decoration:none;border-radius:.4rem;font-size:.85rem;font-weight:600}
  .nav a:hover{background:#e34402}
  .club-section{margin-bottom:2rem}
  .club-heading{color:#fc4c02;margin:1.25rem 0 .25rem;font-size:1.1rem;border-bottom:2px solid #fc4c02;padding-bottom:.25rem;display:flex;align-items:center;gap:.5rem}
  .club-heading img{width:1.6rem;height:1.6rem;border-radius:50%;object-fit:cover;flex-shrink:0}
  .club-heading a{font-size:.7em;font-weight:normal;color:#fc4c02;margin-left:auto}
  .club-sub{color:var(--text-3);font-size:.82rem;margin:0 0 .5rem}
  .club-desc{color:var(--text-2);font-size:.82rem;margin:0 0 .75rem;font-style:italic}
  .ck-banner{padding:.55rem 1rem;border-radius:.4rem;margin:.5rem 0 1rem;font-size:.88rem}
  .ck-ok{background:#e8f5e9;color:#2e7d32;border:1px solid #a5d6a7}
  .ck-warn{background:#fff8e1;color:#e65100;border:1px solid #ffe082;font-weight:600}
  .ck-expired{background:#ffebee;color:#b71c1c;border:1px solid #ef9a9a;font-weight:600}
  @media(prefers-color-scheme:dark){.ck-ok{background:#14391a;color:#86efac;border-color:#166534}.ck-warn{background:#3d2200;color:#fdba74;border-color:#92400e}.ck-expired{background:#3d0a0a;color:#fca5a5;border-color:#991b1b}}
  [data-theme=dark] .ck-ok{background:#14391a;color:#86efac;border-color:#166534}
  [data-theme=dark] .ck-warn{background:#3d2200;color:#fdba74;border-color:#92400e}
  [data-theme=dark] .ck-expired{background:#3d0a0a;color:#fca5a5;border-color:#991b1b}
  [data-theme=light] .ck-ok{background:#e8f5e9;color:#2e7d32;border-color:#a5d6a7}
  [data-theme=light] .ck-warn{background:#fff8e1;color:#e65100;border-color:#ffe082}
  [data-theme=light] .ck-expired{background:#ffebee;color:#b71c1c;border-color:#ef9a9a}
  .bar{height:5px;background:#fc4c02;border-radius:3px;margin-top:4px;min-width:3px}
  .person-row{cursor:pointer}
  .person-row:hover td{background:var(--hover-row)}
  .expand-btn{float:right;font-size:.8rem;opacity:.6}
  .detail-row td{padding:0;background:var(--surface-2)}
  .detail-table{border-collapse:collapse;width:100%;font-size:.83rem}
  .detail-table th{background:var(--detail-th);color:var(--text-2);font-weight:600;padding:.3rem .6rem}
  .detail-table td{padding:.3rem .6rem;border-bottom:1px solid var(--detail-th)}
  .detail-table td.num{text-align:right}
  .club-alltime{margin:.5rem 0 .75rem}
  .club-alltime-label{font-size:.75rem;font-weight:600;color:var(--text-3);text-transform:uppercase;letter-spacing:.04em;margin-bottom:.35rem}
  .stat-tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(7.5rem,1fr));gap:.4rem;margin:.35rem 0 .75rem}
  .stat-tile{background:var(--surface-2);border:1px solid var(--border);border-radius:.5rem;padding:.5rem .7rem;text-align:center}
  .stat-tile .stv{font-size:1.2rem;font-weight:700;color:#fc4c02}
  .stat-tile .stl{font-size:.72rem;color:var(--text-3);margin-top:.1rem}
  .achieve-section{margin:.25rem 0 .75rem}
  .achieve-section-label{font-size:.75rem;font-weight:600;color:var(--text-3);text-transform:uppercase;letter-spacing:.04em;margin-bottom:.35rem}
  .achieve-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(13rem,1fr));gap:.4rem}
  .achieve-item{background:var(--surface-2);border:1px solid var(--border);border-radius:.5rem;padding:.5rem .75rem;display:flex;align-items:flex-start;gap:.45rem}
  .achieve-icon{font-size:1.2rem;flex-shrink:0;line-height:1.3}
  .achieve-body .abl{font-size:.78rem;color:var(--text-3)}
  .achieve-body .abv{font-weight:600;font-size:.88rem}
  .top5-section{margin:.5rem 0 .75rem}
  .top5-label{font-size:.75rem;font-weight:600;color:var(--text-3);text-transform:uppercase;letter-spacing:.04em;margin-bottom:.35rem}
  .top5-since{font-weight:400;text-transform:none;letter-spacing:0;font-size:.7rem}
  .top5-list{display:flex;flex-direction:column;gap:.3rem}
  .top5-item{display:flex;align-items:center;gap:.6rem;background:var(--surface-2);border:1px solid var(--border);border-radius:.4rem;padding:.4rem .7rem}
  .top5-rank{font-weight:700;font-size:.9rem;color:var(--text-3);min-width:1.4rem;text-align:right;flex-shrink:0}
  .top5-rank.r1{color:#fc4c02}
  .top5-avatar{width:1.8rem;height:1.8rem;border-radius:50%;object-fit:cover;flex-shrink:0}
  .top5-avatar-ph{width:1.8rem;height:1.8rem;border-radius:50%;background:var(--border-2);flex-shrink:0}
  .top5-name{font-size:.9rem;font-weight:500}
  .top5-dist{font-weight:700;color:#fc4c02;font-size:.9rem;font-variant-numeric:tabular-nums}
  .top5-sub{font-size:.75rem;color:var(--text-3)}
  .top5-bar{height:3px;background:#fc4c02;border-radius:2px;margin-top:2px;opacity:.6}
  #theme-tog{margin-left:auto;flex-shrink:0;background:none;border:none;font-size:1.2rem;cursor:pointer;line-height:1;padding:.2rem .4rem;border-radius:.3rem;color:var(--text-3)}
  .sec-handle{display:inline-block;cursor:grab;padding:.1rem .25rem;color:var(--text-3);font-size:.9rem;vertical-align:middle;user-select:none;margin-right:.25rem;opacity:.6;border-radius:.2rem}
  .sec-handle:hover{opacity:1;color:var(--accent)}
  .sec-handle:active{cursor:grabbing}
  .sec.sec-dragging{opacity:.4}
  .sec.sec-drag-over{outline:2px dashed var(--accent);outline-offset:2px}
  .sec-order-reset{font-size:.72rem;color:var(--text-3);background:none;border:1px solid var(--border-2);border-radius:.25rem;padding:.15rem .5rem;cursor:pointer;display:block;margin-left:auto;margin-bottom:.4rem}
  .sec-order-reset:hover{color:var(--accent);border-color:var(--accent)}
@media(pointer:coarse){.sec-handle,.sec-order-reset{display:none}}
</style>
</head>
<body>
<div style="display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem"><h1 style="margin:0">🏆 Club Leaderboard</h1><button id="theme-tog">🌙</button></div>
<div class="nav"><a href="me/">→ My Activities</a></div>
<div class="filters">
  <label>Year <select id="year"></select></label>
  <label>Month <select id="month"></select></label>
</div>
<div class="meta" id="meta">Loading…</div>
<div id="board"></div>
<div id="ck-banner" style="display:none"></div>
<div class="meta" id="footer-meta">
  StravaStats for OpenWrt · <span id="footer-source"></span> · <a href="activities.json">activities.json</a><span id="footer-links"></span> · <a href="https://github.com/raczeja/StatsServiceBook" target="_blank" rel="noopener">GitHub</a>
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

function fmtKm(m){ var s=(m/1000).toFixed(1); return s.replace(/\B(?=(\d{3})+(?!\d))/g,' '); }
function fmtNum(n){ return String(Math.floor(n)).replace(/\B(?=(\d{3})+(?!\d))/g,' '); }
function fmtTime(s){ return Math.floor(s/3600)+"h "+Math.floor((s%3600)/60)+"m"; }
function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }
function getLastWeekRange(){
  var n=new Date(), dow=n.getDay(), dsm=dow===0?6:dow-1;
  var mon=new Date(n.getTime()-dsm*86400000); mon.setHours(0,0,0,0);
  var lm=new Date(mon.getTime()-7*86400000), ls=new Date(mon.getTime()-86400000);
  function fmt(d){ return d.getFullYear()+'-'+('0'+(d.getMonth()+1)).slice(-2)+'-'+('0'+d.getDate()).slice(-2); }
  return {from:fmt(lm),to:fmt(ls)};
}

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

function toggleDetail(id){
  var el = document.getElementById(id);
  if(el) el.style.display = el.style.display==='none' ? '' : 'none';
}

function hasLetter(s){return !!(s&&s.replace(/[\s.,\-]/g,'').length>0);}
function pickLastname(ln1,ln2){
  if(hasLetter(ln1)) return ln1;
  if(hasLetter(ln2)) return ln2;
  return ln1;
}
function buildAthReg(allActs){
  var n2p={};
  (allActs||[]).forEach(function(a){
    var pm=a.profile_medium||'', fn=a.firstname||'', ln=a.lastname||'';
    if(!pm||!fn) return;
    if(hasLetter(ln)&&!n2p[fn+'|'+ln]) n2p[fn+'|'+ln]=pm;
    if(!n2p[fn+'|']) n2p[fn+'|']=pm;
  });
  return n2p;
}
function athKey(a,n2p){
  var pm=a.profile_medium||'';
  if(pm) return pm;
  var fn=a.firstname||'', ln=a.lastname||'';
  if(n2p){
    var rp=n2p[hasLetter(ln)?fn+'|'+ln:fn+'|'];
    if(rp) return rp;
  }
  return fn+'|'+ln;
}

function renderClubTable(acts, tablePrefix, allActs, lastWeek, n2p){
  var map = {};
  acts.forEach(function(a){
    var k = athKey(a,n2p);
    var e = map[k];
    if(!e){ e=map[k]={_key:k,firstname:a.firstname,lastname:a.lastname,distance:0,moving_time:0,elev:0,count:0,items:[]}; }
    else { e.lastname=pickLastname(e.lastname,a.lastname); }
    e.distance+=a.distance||0;
    e.moving_time+=a.moving_time||0;
    e.elev+=a.total_elevation_gain||0;
    e.count++;
    e.items.push(a);
  });
  var lwMap = {};
  (allActs||[]).forEach(function(a){
    if(a.date && lastWeek && a.date>=lastWeek.from && a.date<=lastWeek.to){
      var k=athKey(a,n2p);
      lwMap[k]=(lwMap[k]||0)+(a.distance||0);
    }
  });
  var members = Object.keys(map).map(function(k){ return map[k]; })
    .sort(function(x,y){ return y.distance-x.distance; });
  if(members.length===0) return '<p class="empty">No activities for this period.</p>';
  var maxDist = members[0].distance || 1;
  var html = '<table><thead><tr><th>#</th><th>Athlete</th><th>Distance</th>'+
    '<th>Time</th><th>Elev (m)</th><th>Activities</th><th>Avg km/h</th>'+(lastWeek?'<th>Last week</th>':'')+
    '</tr></thead><tbody>';
  members.forEach(function(m,i){
    var avg = m.moving_time>0 ? (m.distance/m.moving_time*3.6) : 0;
    var pct = maxDist>0 ? Math.max(3, Math.round(m.distance/maxDist*100)) : 3;
    var did = tablePrefix+'-d'+i;
    var lw = lwMap[m._key]||0;
    html += '<tr class="person-row" onclick="toggleDetail(\''+did+'\')" title="Click to show activities">'+
      '<td class="num">'+(i+1)+'</td>'+
      '<td>'+esc(m.firstname)+' '+esc(m.lastname)+'<span class="expand-btn">▾</span></td>'+
      '<td class="num">'+fmtKm(m.distance)+' km<div class="bar" style="width:'+pct+'%"></div></td>'+
      '<td class="num">'+fmtTime(m.moving_time)+'</td>'+
      '<td class="num">'+fmtNum(m.elev)+'</td>'+
      '<td class="num">'+m.count+'</td>'+
      '<td class="num">'+avg.toFixed(1)+'</td>'+
      (lastWeek?'<td class="num">'+fmtKm(lw)+' km</td>':'')+
      '</tr>';
    html += '<tr id="'+did+'" class="detail-row" style="display:none"><td colspan="'+(lastWeek?8:7)+'">';
    html += '<table class="detail-table"><thead><tr>'+
      '<th>Date</th><th>Sport</th><th>Distance</th><th>Time</th><th>Elev (m)</th><th>Avg km/h</th><th>Strava</th>'+
      '</tr></thead><tbody>';
    m.items.slice().sort(function(a,b){ return (b.date||'').localeCompare(a.date||''); })
      .forEach(function(a){
        var aspd = (a.moving_time||0)>0 ? ((a.distance||0)/(a.moving_time)*3.6).toFixed(1) : '–';
        var sid = (a.signature && /^\d+$/.test(a.signature))
          ? '<a href="https://www.strava.com/activities/'+esc(a.signature)+'" target="_blank" rel="noopener">'+esc(a.signature)+'</a>'
          : '';
        html += '<tr>'+
          '<td>'+esc(a.date||'')+'</td>'+
          '<td>'+esc(a.sport_type||'')+'</td>'+
          '<td class="num">'+fmtKm(a.distance||0)+' km</td>'+
          '<td class="num">'+fmtTime(a.moving_time||0)+'</td>'+
          '<td class="num">'+fmtNum(a.total_elevation_gain||0)+'</td>'+
          '<td class="num">'+aspd+'</td>'+
          '<td>'+sid+'</td></tr>';
      });
    html += '</tbody></table></td></tr>';
  });
  html += '</tbody></table>';
  return html;
}

function renderThisYearTiles(allActs,n2p){
  var curYear=new Date().getFullYear();
  var allTimeFirst=allActs.reduce(function(mn,a){ return a.date&&(!mn||a.date<mn)?a.date:mn; },'');
  var clubStartedThisYear=allTimeFirst && allTimeFirst.slice(0,4)===String(curYear);
  var acts=allActs.filter(function(a){ return a.date && +a.date.slice(0,4)===curYear; });
  if(acts.length===0) return '';
  var dist=0,time=0,elev=0,ath={},firstDate='';
  acts.forEach(function(a){
    dist+=a.distance||0; time+=a.moving_time||0; elev+=a.total_elevation_gain||0;
    ath[athKey(a,n2p)]=true;
    if(a.date && (!firstDate || a.date<firstDate)) firstDate=a.date;
  });
  var avg=time>0?(dist/time*3.6):0;
  var sinceStr=(clubStartedThisYear && firstDate)
    ? ' <span class="top5-since">since '+esc(firstDate)+'</span>' : '';
  return '<div class="club-alltime">'+
    '<div class="club-alltime-label">This year ('+curYear+')'+sinceStr+'</div>'+
    '<div class="stat-tiles">'+
    '<div class="stat-tile"><div class="stv">'+fmtKm(dist)+'</div><div class="stl">km</div></div>'+
    '<div class="stat-tile"><div class="stv">'+acts.length+'</div><div class="stl">activities</div></div>'+
    '<div class="stat-tile"><div class="stv">'+fmtNum(elev)+'</div><div class="stl">m elevation</div></div>'+
    '<div class="stat-tile"><div class="stv">'+Object.keys(ath).length+'</div><div class="stl">athletes</div></div>'+
    '<div class="stat-tile"><div class="stv">'+avg.toFixed(1)+'</div><div class="stl">avg km/h</div></div>'+
    '</div></div>';
}

function renderClubAlltimeTiles(allActs,n2p){
  if(!allActs || allActs.length===0) return '';
  var dist=0,time=0,elev=0,ath={},firstDate=null;
  allActs.forEach(function(a){
    dist+=a.distance||0; time+=a.moving_time||0; elev+=a.total_elevation_gain||0;
    ath[athKey(a,n2p)]=true;
    if(a.date && (!firstDate || a.date<firstDate)) firstDate=a.date;
  });
  var sinceAlltime=firstDate?' <span class="top5-since">since '+esc(firstDate)+'</span>':'';
  return '<div class="club-alltime">'+
    '<div class="club-alltime-label">Club all-time'+sinceAlltime+'</div>'+
    '<div class="stat-tiles">'+
    '<div class="stat-tile"><div class="stv">'+fmtKm(dist)+'</div><div class="stl">km total</div></div>'+
    '<div class="stat-tile"><div class="stv">'+allActs.length+'</div><div class="stl">activities</div></div>'+
    '<div class="stat-tile"><div class="stv">'+fmtNum(elev)+'</div><div class="stl">m elevation</div></div>'+
    '<div class="stat-tile"><div class="stv">'+Object.keys(ath).length+'</div><div class="stl">athletes</div></div>'+
    '</div></div>';
}

function renderTop5Year(allActs,year,n2p){
  var acts=allActs.filter(function(a){ return a.date && +a.date.slice(0,4)===year; });
  if(acts.length===0) return '';
  // Earliest date across all history (not just this year)
  var allTimeFirst=allActs.reduce(function(mn,a){ return a.date&&(!mn||a.date<mn)?a.date:mn; },'');
  var clubStartedThisYear=allTimeFirst && allTimeFirst.slice(0,4)===String(year);
  var map={},firstDate='';
  acts.forEach(function(a){
    var k=athKey(a,n2p);
    if(!map[k]) map[k]={fn:a.firstname,ln:a.lastname,dist:0,cnt:0,pm:a.profile_medium||''};
    else { map[k].ln=pickLastname(map[k].ln,a.lastname); }
    map[k].dist+=a.distance||0; map[k].cnt++;
    if(a.profile_medium && !map[k].pm) map[k].pm=a.profile_medium;
    if(a.date && (!firstDate || a.date<firstDate)) firstDate=a.date;
  });
  var top=Object.keys(map).map(function(k){return map[k];})
    .sort(function(a,b){return b.dist-a.dist;}).slice(0,5);
  if(top.length===0) return '';
  var maxDist=top[0].dist||1;
  var sinceStr=(clubStartedThisYear && firstDate)
    ? ' <span class="top5-since">since '+esc(firstDate)+'</span>' : '';
  var h='<div class="top5-section"><div class="top5-label">Top 5 &middot; '+year+sinceStr+'</div><div class="top5-list">';
  top.forEach(function(m,i){
    var rank=i+1;
    var av=m.pm
      ? '<img class="top5-avatar" src="'+esc(m.pm)+'" alt="">'
      : '<div class="top5-avatar-ph"></div>';
    var pct=Math.max(5,Math.round(m.dist/maxDist*100));
    h+='<div class="top5-item">'+
      '<span class="top5-rank'+(rank===1?' r1':'')+'">#'+rank+'</span>'+
      av+
      '<div style="flex:1;min-width:0"><div class="top5-name">'+esc(m.fn)+' '+esc(m.ln)+'</div>'+
      '<div class="top5-bar" style="width:'+pct+'%"></div></div>'+
      '<div style="text-align:right;flex-shrink:0"><div class="top5-dist">'+fmtKm(m.dist)+' km</div>'+
      '<div class="top5-sub">'+m.cnt+' activities</div></div>'+
      '</div>';
  });
  h+='</div></div>';
  return h;
}

function renderPeriodTiles(acts,label,n2p){
  if(acts.length===0) return '';
  var dist=0,time=0,elev=0,ath={};
  acts.forEach(function(a){
    dist+=a.distance||0; time+=a.moving_time||0; elev+=a.total_elevation_gain||0;
    ath[athKey(a,n2p)]=true;
  });
  var avg=time>0?(dist/time*3.6):0;
  return '<div class="club-alltime"><div class="club-alltime-label">'+esc(label)+'</div><div class="stat-tiles">'+
    '<div class="stat-tile"><div class="stv">'+fmtKm(dist)+'</div><div class="stl">km</div></div>'+
    '<div class="stat-tile"><div class="stv">'+acts.length+'</div><div class="stl">activities</div></div>'+
    '<div class="stat-tile"><div class="stv">'+fmtNum(elev)+'</div><div class="stl">m elevation</div></div>'+
    '<div class="stat-tile"><div class="stv">'+Object.keys(ath).length+'</div><div class="stl">athletes</div></div>'+
    '<div class="stat-tile"><div class="stv">'+avg.toFixed(1)+'</div><div class="stl">avg km/h</div></div>'+
    '</div></div>';
}

function renderAchievements(acts,label,n2p){
  if(acts.length<1) return '';
  var fastest=null,fastSpd=0,longest=null,longestD=0,topElev=null,topElevD=0;
  var athCount={},athElev={},athDname={};
  acts.forEach(function(a){
    if((a.moving_time||0)>0&&(a.distance||0)>1000){
      var spd=a.distance/a.moving_time*3.6;
      if(spd>fastSpd){fastSpd=spd;fastest=a;}
    }
    if((a.distance||0)>longestD){longestD=a.distance;longest=a;}
    if((a.total_elevation_gain||0)>topElevD){topElevD=a.total_elevation_gain;topElev=a;}
    var key=athKey(a,n2p);
    athCount[key]=(athCount[key]||0)+1;
    athElev[key]=(athElev[key]||0)+(a.total_elevation_gain||0);
    if(!athDname[key]){athDname[key]={fn:a.firstname||'',ln:a.lastname||''};}
    else{athDname[key].ln=pickLastname(athDname[key].ln,a.lastname||'');}
  });
  var mostActiveKey=null,mostActiveN=0;
  Object.keys(athCount).forEach(function(k){if(athCount[k]>mostActiveN){mostActiveN=athCount[k];mostActiveKey=k;}});
  var topClimberKey=null,topClimberM=0;
  Object.keys(athElev).forEach(function(k){if(athElev[k]>topClimberM){topClimberM=athElev[k];topClimberKey=k;}});
  if(!fastest&&!longest&&!topElev&&!mostActiveKey) return '';
  function ai(icon,lbl,val,sub){
    return '<div class="achieve-item"><div class="achieve-icon">'+icon+'</div>'+
      '<div class="achieve-body"><div class="abl">'+esc(lbl)+'</div>'+
      '<div class="abv">'+val+'</div>'+(sub?'<div class="abl">'+esc(sub)+'</div>':'')+
      '</div></div>';
  }
  function keyName(k){var d=athDname[k]||{fn:'',ln:''};return esc(d.fn)+' '+esc(d.ln);}
  var h='<div class="achieve-section"><div class="achieve-section-label">Highlights &middot; '+esc(label)+'</div><div class="achieve-grid">';
  if(mostActiveKey) h+=ai('&#128293;','Most active',keyName(mostActiveKey)+' &mdash; '+mostActiveN+' '+(mostActiveN===1?'activity':'activities'),'');
  if(topClimberKey&&topClimberM>0) h+=ai('&#128304;','Top climber',keyName(topClimberKey)+' &mdash; '+fmtNum(topClimberM)+' m total','');
  if(fastest) h+=ai('&#9889;','Fastest single',esc(fastest.firstname)+' '+esc(fastest.lastname)+' &mdash; '+fastSpd.toFixed(1)+' km/h',fastest.sport_type||'');
  if(longest) h+=ai('&#128207;','Longest single',esc(longest.firstname)+' '+esc(longest.lastname)+' &mdash; '+fmtKm(longestD)+' km',longest.sport_type||'');
  if(topElev) h+=ai('&#127956;','Best elevation single',esc(topElev.firstname)+' '+esc(topElev.lastname)+' &mdash; '+fmtNum(topElevD)+' m',topElev.sport_type||'');
  h+='</div></div>';
  return h;
}

function render(){
  var year = +yearSel.value;
  var month = monthSel.value;
  var label = month==="all" ? String(year) : MONTHS[+month-1]+" "+year;
  var clubs = DATA.clubs || [];
  var sport = DATA.sport || "all";
  var _now = new Date(), _cy = _now.getFullYear(), _cm = _now.getMonth()+1;
  var isCurrentPeriod = (year === _cy) && (month === "all" || +month === _cm);
  var lastWeek = isCurrentPeriod ? getLastWeekRange() : null;

  var totalDist = 0, totalActs = 0;
  var html = "";

  clubs.forEach(function(club, i){
    var clubAllActs = club.activities||[];
    var n2p = buildAthReg(clubAllActs);
    var acts = clubAllActs.filter(function(a){
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
    var _tbl=renderClubTable(acts, esc(club.clubId||String(i)), clubAllActs, lastWeek, n2p);
    var _top5=renderTop5Year(clubAllActs,year,n2p);
    var _period=renderPeriodTiles(acts,label,n2p);
    var _achieve=renderAchievements(acts,label,n2p);
    var _thisyr=renderThisYearTiles(clubAllActs,n2p);
    var _alltime=renderClubAlltimeTiles(clubAllActs,n2p);
    html += '<div class="sec" data-sid="table">'+_tbl+'</div>';
    if(_top5) html += '<div class="sec" data-sid="top5">'+_top5+'</div>';
    if(_period) html += '<div class="sec" data-sid="period">'+_period+'</div>';
    if(_achieve) html += '<div class="sec" data-sid="achievements">'+_achieve+'</div>';
    if(_thisyr) html += '<div class="sec" data-sid="thisyear">'+_thisyr+'</div>';
    if(_alltime) html += '<div class="sec" data-sid="alltime">'+_alltime+'</div>';
    html += '</section>';
  });

  meta.innerHTML = "Sport: "+esc(sport)+" · "+clubs.length+" club(s) · "+
    totalActs+" activities · "+fmtKm(totalDist)+" km total · "+esc(label)+
    " · generated "+esc(DATA.generatedAt||"");
  board.innerHTML = html;
  if(typeof window._lbSecAfterRender==='function')window._lbSecAfterRender();
}

fetch("activities.json",{cache:"no-store"})
  .then(function(r){ if(!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
  .then(function(d){ DATA=d; init(); })
  .catch(function(err){
    meta.textContent="Failed to load activities.json ("+err.message+
      "). Open this page via the router's web server, not from a file.";
  });

(function(){
  var root=document.documentElement;
  var btn=document.getElementById('theme-tog');
  var saved=localStorage.getItem('theme');
  if(saved) root.dataset.theme=saved;
  function isDark(){return root.dataset.theme==='dark'||(!root.dataset.theme&&matchMedia('(prefers-color-scheme:dark)').matches);}
  function syncBtn(){btn.textContent=isDark()?'☀️':'🌙';}
  syncBtn();
  btn.onclick=function(){root.dataset.theme=isDark()?'light':'dark';localStorage.setItem('theme',root.dataset.theme);syncBtn();};
  matchMedia('(prefers-color-scheme:dark)').addEventListener('change',syncBtn);
})();
(function(){
  var LB_SEC_KEY='ssb-lb-sec';
  var LB_SEC_DEFAULT=['table','top5','period','achievements','thisyear','alltime'];
  var board=document.getElementById('board');
  if(!board)return;
  var dragSrc=null;
  function getSecs(wrap){return Array.prototype.filter.call(wrap.children,function(el){return el.classList&&el.classList.contains('sec');});}
  function saveOrder(wrap){try{localStorage.setItem(LB_SEC_KEY,JSON.stringify(getSecs(wrap).map(function(s){return s.getAttribute('data-sid');})));}catch(e){}}
  function getOrder(allSids){
    var saved=null;try{saved=JSON.parse(localStorage.getItem(LB_SEC_KEY));}catch(e){}
    var order=[];
    if(saved){saved.forEach(function(sid){if(allSids.indexOf(sid)>=0)order.push(sid);});allSids.forEach(function(sid){if(order.indexOf(sid)<0)order.push(sid);});}
    else{LB_SEC_DEFAULT.forEach(function(sid){if(allSids.indexOf(sid)>=0)order.push(sid);});allSids.forEach(function(sid){if(order.indexOf(sid)<0)order.push(sid);});}
    return order;
  }
  function doReset(){
    try{localStorage.removeItem(LB_SEC_KEY);}catch(e){}
    var clubSecs=board.querySelectorAll('.club-section');
    for(var i=0;i<clubSecs.length;i++){
      var wrap=clubSecs[i];
      var allSids=getSecs(wrap).map(function(s){return s.getAttribute('data-sid');});
      var secMap={};getSecs(wrap).forEach(function(s){secMap[s.getAttribute('data-sid')]=s;});
      LB_SEC_DEFAULT.forEach(function(sid){if(secMap[sid])wrap.appendChild(secMap[sid]);});
      allSids.forEach(function(sid){if(secMap[sid]&&LB_SEC_DEFAULT.indexOf(sid)<0)wrap.appendChild(secMap[sid]);});
    }
  }
  function applyOrderAndInject(wrap){
    var allSids=getSecs(wrap).map(function(s){return s.getAttribute('data-sid');});
    var order=getOrder(allSids);
    var secMap={};getSecs(wrap).forEach(function(s){secMap[s.getAttribute('data-sid')]=s;});
    order.forEach(function(sid){if(secMap[sid])wrap.appendChild(secMap[sid]);});
    getSecs(wrap).forEach(function(s){
      var old=s.querySelector('.sec-handle');if(old)old.parentNode.removeChild(old);
      var sid=s.getAttribute('data-sid');
      var handle=document.createElement('span');handle.className='sec-handle';handle.title='Drag to reorder';handle.textContent='⠿';
      handle.setAttribute('draggable','true');
      handle.addEventListener('dragstart',function(e){dragSrc={wrap:wrap,sid:sid};s.classList.add('sec-dragging');if(e.dataTransfer){e.dataTransfer.effectAllowed='move';try{e.dataTransfer.setDragImage(s,0,0);}catch(_){}}e.stopPropagation();});
      handle.addEventListener('dragend',function(){s.classList.remove('sec-dragging');dragSrc=null;getSecs(wrap).forEach(function(x){x.classList.remove('sec-drag-over');});});
      s.ondragover=function(e){if(dragSrc&&dragSrc.wrap===wrap&&dragSrc.sid!==sid){e.preventDefault();s.classList.add('sec-drag-over');}};
      s.ondragleave=function(e){if(!s.contains(e.relatedTarget))s.classList.remove('sec-drag-over');};
      s.ondrop=function(e){
        e.preventDefault();
        if(!dragSrc||dragSrc.wrap!==wrap||dragSrc.sid===sid)return;
        var secs=getSecs(wrap);var srcEl=null,tgtEl=null;
        for(var i=0;i<secs.length;i++){if(secs[i].getAttribute('data-sid')===dragSrc.sid)srcEl=secs[i];if(secs[i].getAttribute('data-sid')===sid)tgtEl=secs[i];}
        if(!srcEl||!tgtEl)return;
        var rect=tgtEl.getBoundingClientRect();
        if((e.clientY||0)<rect.top+rect.height/2)wrap.insertBefore(srcEl,tgtEl);else wrap.insertBefore(srcEl,tgtEl.nextSibling);
        getSecs(wrap).forEach(function(x){x.classList.remove('sec-drag-over');});
        saveOrder(wrap);
      };
      s.insertBefore(handle,s.firstChild);
    });
  }
  function ensureResetBtn(){
    if(board.previousElementSibling&&board.previousElementSibling.classList.contains('sec-order-reset'))return;
    var rb=document.createElement('button');rb.className='sec-order-reset';rb.textContent='↺ Reset section order';
    rb.onclick=function(){doReset();injectAll();};
    board.parentNode.insertBefore(rb,board);
  }
  function injectAll(){
    ensureResetBtn();
    var clubSecs=board.querySelectorAll('.club-section');
    for(var i=0;i<clubSecs.length;i++)applyOrderAndInject(clubSecs[i]);
  }
  window._lbSecAfterRender=injectAll;
})();
</script>
</body>
</html>
HTML

log "wrote $WEB_DIR/index.html"
log "done."
