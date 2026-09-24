# strava-my-feed-scrape.sh — sourced by strava-my-activities.sh (§2, scrape branch).
# Pages /athlete/training_activities; normalizes web format to API field shape;
# appends NDJSON to $TMP/all.ndjson.
# Variables read from caller: TMP, MAX_PAGES, STATE_DIR, log, curl_retry.
# Variables written back: reached_end (set to 1 on natural end), _sc_norm_fail (incremented).

# The training_activities web endpoint returns 20 activities/page (fixed).
# MAX_PAGES * 20 = effective history cap; raise STRAVA_MY_MAX_PAGES if you
# have more than MAX_PAGES*20 activities.
_sc_per_page=20
_sc_csrf="$(cat "$STATE_DIR/strava_csrf.txt" 2>/dev/null || echo "")"
# Generate a search session UUID (reused across pages of the same run).
_sc_session_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null \
  || printf '%08x-%04x-4%03x-%04x-%012x' \
     "$(date +%s)" "$(( $$ & 0xFFFF ))" "$(( $$ & 0xFFF ))" \
     "$(( ($$ >> 4 & 0x3FFF) | 0x8000 ))" "$(date +%s)$$" 2>/dev/null \
  || printf 'scrape-session-%s-%s' "$(date +%s)" "$$")"
log "fetching athlete activities via scrape (up to $MAX_PAGES pages of $_sc_per_page)..."
while [ "$page" -le "$MAX_PAGES" ]; do
  log "page $page: GET /athlete/training_activities?page=$page"
  curl_retry -fsS \
    -b "$STATE_DIR/strava_cookies.txt" \
    -H "x-csrf-token: $_sc_csrf" \
    -H "x-requested-with: XMLHttpRequest" \
    -H "accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
    "https://www.strava.com/athlete/training_activities?keywords=&sport_type=&tags=&commute=&private_activities=&trainer=&gear=&search_session_id=${_sc_session_id}&new_activity_only=false&page=${page}" \
    -o "$TMP/sc_page.raw" || die "activities scrape failed (page $page)"

  # Parse the response. Modern Strava returns JSON; older versions may return
  # a JS/HTML fragment. Try JSON array, JSON wrapper, then HTML ID extraction.
  : > "$TMP/sc_acts.ndjson"
  if jq -e 'type == "array" and length > 0' "$TMP/sc_page.raw" >/dev/null 2>&1; then
    jq -c '.[]' "$TMP/sc_page.raw" > "$TMP/sc_acts.ndjson"
  elif jq -e '(.activities // .models) | type == "array"' "$TMP/sc_page.raw" >/dev/null 2>&1; then
    jq -c '(.activities // .models)[]' "$TMP/sc_page.raw" > "$TMP/sc_acts.ndjson"
  else
    # Before trying HTML extraction, detect if Strava redirected to login page.
    if grep -qiE 'Log In to Strava|id="login-form"|action="/session"' "$TMP/sc_page.raw" 2>/dev/null; then
      die "activities scrape: page $page — Strava returned the login page; STRAVA_SESSION_COOKIE has expired; copy a fresh _strava4_session value from browser DevTools (Application → Cookies → strava.com)"
    fi
    # HTML/JS fallback: extract activity IDs from href or data attributes.
    # These produce minimal records; detail backfill enriches them later.
    grep -oE '"/activities/[0-9]+"' "$TMP/sc_page.raw" 2>/dev/null \
      | grep -oE '[0-9]+' | sort -u \
      | while IFS= read -r _sc_aid; do printf '{"id":%s}\n' "$_sc_aid"; done \
      > "$TMP/sc_acts.ndjson"
    if [ ! -s "$TMP/sc_acts.ndjson" ]; then
      grep -oE '"id"\s*:\s*[0-9]{6,}' "$TMP/sc_page.raw" 2>/dev/null \
        | grep -oE '[0-9]{6,}' | sort -u \
        | while IFS= read -r _sc_aid; do printf '{"id":%s}\n' "$_sc_aid"; done \
        > "$TMP/sc_acts.ndjson"
    fi
    if [ ! -s "$TMP/sc_acts.ndjson" ]; then
      _sc_raw_sample="$(head -c 300 "$TMP/sc_page.raw" | tr '\n\r' '  ')"
      log "  LAYOUT CHANGE DETECTED: page $page — not JSON and no activity IDs found in HTML; response starts: ${_sc_raw_sample}; Strava may have changed the /athlete/training_activities endpoint"
      reached_end=1; break
    fi
    log "  page $page: note — response was HTML/JS, only IDs extracted; detail backfill will enrich"
  fi

  count="$(wc -l < "$TMP/sc_acts.ndjson" | tr -d ' ')"
  [ "$count" -gt 0 ] || { log "  page $page empty, stopping"; reached_end=1; break; }

  # Normalize to the same field shape as the API feed so section 3 merge works.
  # The Strava web endpoint differs from the API in three ways:
  #   1. Dates are locale-formatted ("Wed, 9/2/2026"), not ISO-8601
  #   2. Distance is in km (possibly with comma decimal), not metres
  #   3. Times are formatted strings ("1:12:34"), not integer seconds
  # Detection: if moving_time is a string the record is in web format.
  jq -c '
    def parse_time(v):
      if   (v | type) == "number" then v
      elif (v | type) == "string" and (v | split(":") | length) == 3 then
           (v | split(":") | (.[0]|tonumber)*3600 + (.[1]|tonumber)*60 + (.[2]|tonumber))
      elif (v | type) == "string" and (v | split(":") | length) == 2 then
           (v | split(":") | (.[0]|tonumber)*60 + (.[1]|tonumber))
      else 0 end;
    (.moving_time // .movingTime // null) as $mt_raw
    | (($mt_raw | type) == "string") as $web
    | (.start_date_local // .start_date // .startDateLocal // "") as $sd
    | (if   ($sd | startswith("20")) then $sd[0:10]
       elif ($sd | contains(",")) then
         ($sd | split(", ")[-1] | split("/") |
           (.[2]) + "-" +
           (.[0]|tonumber|tostring | if length==1 then "0"+. else . end) + "-" +
           (.[1]|tonumber|tostring | if length==1 then "0"+. else . end))
       else $sd[0:10]
       end) as $date
    | ((.distance // 0)
       | if   type == "string" then (split(",") | join(".") | try tonumber catch 0)
         else . end
       | if $web then . * 1000 else . end) as $dist
    | {
        id:                   (.id // null),
        start_date_local:     $date,
        name:                 (.name // .title // ""),
        sport_type:           (.sport_type // .type // .sportType // ""),
        gear_id:              (.gear_id // .gearId // null),
        distance:             $dist,
        moving_time:          (parse_time($mt_raw)),
        elapsed_time:         (parse_time(.elapsed_time // .elapsedTime // null)),
        total_elevation_gain: (.total_elevation_gain // .totalElevationGain // .elevation_gain_raw // 0),
        average_speed:        (.average_speed // .averageSpeed // 0),
        max_speed:            (.max_speed // .maxSpeed // 0),
        average_heartrate:    (.average_heartrate // .averageHeartrate // null),
        max_heartrate:        (.max_heartrate // .maxHeartrate // null),
        average_cadence:      (.average_cadence // .averageCadence // null),
        average_watts:        (.average_watts // .averageWatts // null),
        weighted_average_watts: (.weighted_average_watts // .weightedAverageWatts // null),
        max_watts:            (.max_watts // .maxWatts // null),
        kilojoules:           (.kilojoules // null),
        average_temp:         (.average_temp // .averageTemp // null),
        suffer_score:         (.suffer_score // .sufferScore // null),
        elev_high:            (.elev_high // .elevHigh // null),
        elev_low:             (.elev_low // .elevLow // null)
      }
    | select(.id != null)
  ' "$TMP/sc_acts.ndjson" >> "$TMP/all.ndjson" || { log "WARNING: jq scrape normalization failed (page $page) — activities may be missing"; _sc_norm_fail=$((_sc_norm_fail+1)); }

  log "  page $page: $count activities (scrape)"
  [ "$count" -lt "$_sc_per_page" ] && { log "  short page, stopping"; reached_end=1; break; }
  page=$((page + 1))
done
