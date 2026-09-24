# strava-my-detail-backfill.sh — sourced by strava-my-activities.sh (§3b).
# Rate-limited per-activity detail JSON backfill. Handles both API mode
# (GET /api/v3/activities/{id}) and scrape mode (HTML parse + GPX download)
# via an internal case branch — the shared loop structure prevents splitting.
# Variables read from caller: DETAIL_DIR, DETAIL_SKIP, DETAIL_MAX_PER_RUN,
#   DETAIL_SLEEP, GPX_MAX_PER_RUN, STORE, STRAVA_SOURCE, TMP, STATE_DIR,
#   WEB_DIR, ACCESS_TOKEN, TOTAL_STORED, log, curl_retry, die.
# Variables incremented in caller scope (no special wiring needed):
#   ADDED — incremented by saved count; read by §4 skip-render guard after sourcing.
#   _sc_norm_fail, _sc_cookie_expired, _sc_layout_fail — read by §3c after sourcing.

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
    [ -f "$DETAIL_DIR/$id.json" ] && [ ! -f "$DETAIL_DIR/$id.minimal" ] && continue  # have full detail
    grep -qxF "$id" "$DETAIL_SKIP" && continue                # known gone, skip
    if [ "$tried" -ge "$DETAIL_MAX_PER_RUN" ]; then
      log "detail backfill: hit cap ($DETAIL_MAX_PER_RUN requests); remaining will continue next run"
      break
    fi

    tried=$((tried + 1))
    case "$STRAVA_SOURCE" in
      api)
        log "detail backfill: GET /api/v3/activities/$id"
        code="$(curl_retry -sS -o "$TMP/detail.json" -w '%{http_code}' \
          "https://www.strava.com/api/v3/activities/$id?include_all_efforts=false" \
          -H "Authorization: Bearer $ACCESS_TOKEN" || echo 000)"
        ;;
      scrape)
        log "detail backfill: GET /activities/$id (scrape)"
        # Fetch the activity HTML page and extract data from Strava's Backbone.js
        # bootstrap. Strava does NOT use Next.js; activity data is embedded via
        # chained Backbone method calls:
        #   .similarActivitiesData({...})  — metrics + start_date_local (Unix ts)
        #   pageView.activity().set({bikes:[{id,name},...], shoes:[...]})  — gear
        # Both appear on single long lines, making grep+awk extraction reliable.
        code="$(curl_retry -sS -o "$TMP/sc_detail.html" -w '%{http_code}' \
          -b "$STATE_DIR/strava_cookies.txt" \
          -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
          "https://www.strava.com/activities/$id" || echo 000)"
        if [ "$code" = "200" ]; then
          : > "$TMP/detail.json"

          # Extract the similarActivitiesData({...}) JSON object.
          # The argument is a single long line; strip the method prefix then use
          # awk brace-counting to extract the balanced JSON object.
          grep -o '\.similarActivitiesData({.*' "$TMP/sc_detail.html" 2>/dev/null \
            | head -1 \
            | sed 's/^\.similarActivitiesData(//' \
            | awk '{
                depth=0; buf=""
                for(i=1;i<=length($0);i++){
                  c=substr($0,i,1)
                  buf=buf c
                  if(c=="{") depth++
                  else if(c=="}"){depth--; if(depth==0){print buf; exit}}
                }
              }' > "$TMP/sc_sad.json" 2>/dev/null || true

          # Extract bikes array from pageView.activity().set({bikes:[...], ...}).
          # Keys are unquoted JS; the bikes value array IS valid JSON.
          grep -o 'bikes: \[{.*}\]' "$TMP/sc_detail.html" 2>/dev/null \
            | head -1 \
            | sed 's/^bikes: //' > "$TMP/sc_bikes.json" 2>/dev/null || true
          jq -e 'type == "array"' "$TMP/sc_bikes.json" >/dev/null 2>&1 \
            || printf '[]' > "$TMP/sc_bikes.json"

          # sport_type is already normalised in the store from the list fetch.
          _sc_sport="$(jq -rs --arg i "$id" \
            '[.[] | select(.id == ($i|tonumber))] | .[0].sport_type // "Ride"' \
            "$STORE" 2>/dev/null)" || _sc_sport=""
          [ -n "$_sc_sport" ] || _sc_sport="Ride"

          # Build the detail JSON from the extracted blobs.
          if jq -e '.efforts[0].activity_id' "$TMP/sc_sad.json" >/dev/null 2>&1; then
            jq -n \
              --argjson sad   "$(cat "$TMP/sc_sad.json")" \
              --argjson bikes "$(cat "$TMP/sc_bikes.json")" \
              --arg     sport "$_sc_sport" \
              '
                $sad.efforts[0] as $e
                | $e.activity_values.values as $v
                | ($v.bike_id != null) as $has_bike
                | (if $has_bike then ($v.bike_id | floor) else null end) as $bid
                | (if $has_bike then "b\($bid | tostring)" else null end) as $gid
                | ([$bikes[] | select(.id == $bid)] | if length > 0 then .[0].name else "Unknown Bike" end) as $bname
                | {
                    id:                    $e.activity_id,
                    name:                  $e.activity_name,
                    sport_type:            $sport,
                    start_date_local:      ($e.start_date_local | strftime("%Y-%m-%dT%H:%M:%SZ")),
                    start_date:            ($e.start_date       | strftime("%Y-%m-%dT%H:%M:%SZ")),
                    distance:              ($v.distance         // 0),
                    moving_time:           ($v.moving_time      // 0 | floor),
                    elapsed_time:          ($v.elapsed_time     // 0 | floor),
                    total_elevation_gain:  ($v.elev_gain        // 0),
                    average_speed:         (($v.avg_speed // 0) as $asp |
                                           if $asp > 0 then $asp
                                           elif ($v.distance // 0) > 0 and ($v.moving_time // 0) > 0
                                           then ($v.distance / ($v.moving_time | floor))
                                           else 0 end),
                    max_speed:             ($v.max_speed        // 0),
                    average_heartrate:     ($v.avg_heartrate    // $v.average_heartrate // null),
                    max_heartrate:         ($v.max_heartrate    // null),
                    average_cadence:       ($v.avg_cadence      // null),
                    average_watts:         ($v.avg_watts        // null),
                    weighted_average_watts:($v.weighted_avg_watts // null),
                    max_watts:             ($v.max_watts        // null),
                    kilojoules:            (if ($v.avg_watts != null and $v.moving_time != null)
                                           then ($v.avg_watts * $v.moving_time / 1000 | round)
                                           else null end),
                    calories:              ($v.calories         | if . != null then floor else null end),
                    step_count:            ($v.steps            // null),
                    suffer_score:          ($v.suffer_score     // $v.relative_effort // null),
                    average_temp:          ($v.avg_temp         // null),
                    elev_high:             ($v.elev_high        // null),
                    elev_low:              ($v.elev_low         // null),
                    device_name:           ($e.device_name      // $sad.device_name // null),
                    description:           ($e.activity_description // null),
                    start_latlng:          (if ($e.start_lat // null) != null and ($e.start_lng // null) != null
                                           then [$e.start_lat, $e.start_lng] else null end),
                    map:                   (if ($e.map_polyline // $e.summary_polyline // null) != null
                                           then {summary_polyline: ($e.map_polyline // $e.summary_polyline)}
                                           else null end),
                    gear_id:               $gid,
                    gear:                  (if $has_bike then {id: $gid, name: $bname} else null end)
                  }
              ' > "$TMP/detail.json" 2>/dev/null || true
          fi

          # Fallback for similarActivitiesData(null): Strava passes null when the
          # activity has no similar-activities comparison (no subscription, certain types).
          # Extract metrics from the multi-line pageView.activity().set({distance:...}) block
          # and supplementary fields from the rendered HTML.
          if ! jq -e '.id' "$TMP/detail.json" >/dev/null 2>&1 \
            && grep -qE '\.similarActivitiesData\(null\)' "$TMP/sc_detail.html" 2>/dev/null; then
            log "detail backfill scrape: activity $id — similarActivitiesData(null); using pageView.activity fallback"
            # Capture the metrics set({distance:...}) block using awk brace-counting.
            # There are multiple set({...}) calls; we want the one that contains "distance:".
            awk '
              /pageView\.activity\(\)\.set\(\{/ { in_b=1; brace=0; buf="" }
              in_b {
                for(i=1;i<=length($0);i++){
                  c=substr($0,i,1)
                  if(c=="{") brace++
                  else if(c=="}"){ brace--
                    if(brace<=0){
                      buf=buf substr($0,1,i)
                      if(buf ~ /distance:/) print buf
                      in_b=0; buf=""; break
                    }
                  }
                }
                if(in_b) buf=buf $0 "\n"
              }
            ' "$TMP/sc_detail.html" > "$TMP/pv_block.txt" 2>/dev/null || true
            # Extract numeric fields — each appears as "key: number" in the block.
            _pv_n() { grep -oE "$1:[[:space:]]*-?[0-9]+\.?[0-9]*" "$TMP/pv_block.txt" | head -1 \
                       | sed "s/$1:[[:space:]]*//" | tr -d ' '; }
            _pv_dist="$(_pv_n distance)"
            _pv_mt="$(_pv_n moving_time)"
            _pv_spd="$(_pv_n avg_speed)"
            _pv_hr="$(_pv_n avg_hr)"
            _pv_cad="$(_pv_n avg_cadence)"
            _pv_elevg="$(_pv_n elev_gain)"
            _pv_watts="$(_pv_n avgWatts)"    # camelCase in Strava's pv_block
            _pv_kj="$(_pv_n kilojoules)"
            _pv_cals_raw="$(grep -oE "calories:[[:space:]]*[0-9]+\.?[0-9]*" "$TMP/pv_block.txt" \
                             | head -1 | sed 's/calories:[[:space:]]*//' | tr -d ' ')"
            _pv_temp_raw="$(grep -oE "avg_temp:[[:space:]]*(null|-?[0-9]+\.?[0-9]*)" "$TMP/pv_block.txt" \
                             | head -1 | sed 's/avg_temp:[[:space:]]*//')"
            # HTML fallback for stats not in the pv_block: <th>Label</th><td>value</td> table
            [ -z "$_pv_cad" ] && _pv_cad="$(awk '
              /<th[^>]*>Cadence</{found=1;next}
              found && /<td/{match($0,/[0-9]+/);if(RSTART>0){print substr($0,RSTART,RLENGTH);exit}}
              found && ++n>3{exit}
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_cad=""
            [ -z "$_pv_cals_raw" ] && _pv_cals_raw="$(awk '
              /<th[^>]*>Calories</{found=1;next}
              found && /<td/{line=$0;sub(/^[^>]*>/,"",line);gsub(",","",line);match(line,/[0-9]+/);if(RSTART>0){print substr(line,RSTART,RLENGTH);exit}}
              found && ++n>3{exit}
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_cals_raw=""
            [ -z "$_pv_temp_raw" ] && _pv_temp_raw="$(awk '
              /<th[^>]*>Temperature</{found=1;next}
              found && /<td/{line=$0;sub(/^[^>]*>/,"",line);match(line,/[-]?[0-9]+/);if(RSTART>0){print substr(line,RSTART,RLENGTH);exit}}
              found && ++n>3{exit}
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_temp_raw=""
            # Device name: <div class='device spans8'>Magene C606</div>
            _pv_device="$(awk '
              /class=.device spans8./{found=1;next}
              found && /^[^<]/{gsub(/^[[:space:]]+|[[:space:]]+$/,"");if(length($0)>0){print;exit}}
              found && /</{exit}
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_device=""
            # Gear name: <span class='gear-name'>Kross Level 6.0 SRAM</span>
            _pv_gear_name="$(awk '
              /class=.gear-name./{found=1;next}
              found && /^[^<]/{gsub(/^[[:space:]]+|[[:space:]]+$/,"");if(length($0)>0){print;exit}}
              found && /</{exit}
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_gear_name=""
            # Resolve gear_id from bikes array already captured in sc_bikes.json
            _pv_gear_id=""
            if [ -n "$_pv_gear_name" ] && jq -e 'type == "array"' "$TMP/sc_bikes.json" >/dev/null 2>&1; then
              _pv_bid="$(jq -r --arg n "$_pv_gear_name" \
                '.[] | select(.name == $n) | .id' "$TMP/sc_bikes.json" 2>/dev/null | head -1)"
              [ -n "$_pv_bid" ] && [ "$_pv_bid" != "null" ] && _pv_gear_id="b${_pv_bid}"
            fi
            # Steps: scrape from rendered HTML — "Steps</div>...<strong>6,488</strong>"
            _pv_steps="$(awk '
              /spans5.*>Steps</{found=1;next}
              found && /<strong>/{
                match($0,/[0-9,]+/)
                if(RSTART>0){s=substr($0,RSTART,RLENGTH);gsub(",","",s);print s;exit}
              }
              found && ++n>6{exit}
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_steps=""
            # Activity name: from <h1 class='...activity-name'>
            _pv_name="$(grep -oE "class='[^']*activity-name[^']*'>[^<]+" "$TMP/sc_detail.html" \
                         | head -1 | sed "s/.*'[^']*'>//" | xargs 2>/dev/null)" || _pv_name=""
            [ -n "$_pv_name" ] || _pv_name="$(sed -n 's/.*<title>\([^|]*\)|.*/\1/p' \
                         "$TMP/sc_detail.html" | head -1 | xargs 2>/dev/null)" || _pv_name="Activity $id"
            # Date: Strava renders "H:MM AM/PM on Day, Month DD, YYYY"
            _pv_date="$(awk '
              /[AP]M on /{
                match($0,/[A-Za-z]+ [0-9]+, [0-9]+/)
                if(RSTART>0){
                  s=substr($0,RSTART,RLENGTH); n=split(s,a,/[, ]+/)
                  mo=a[1]; dy=a[2]; yr=a[3]
                  mnames="JanFebMarAprMayJunJulAugSepOctNovDec"
                  m=(index(mnames,substr(mo,1,3))+2)/3
                  printf "%s-%02d-%02d\n",yr,m,dy; exit
                }
              }
            ' "$TMP/sc_detail.html" 2>/dev/null)" || _pv_date=""
            [ -n "$_pv_date" ] || _pv_date="$(date +%Y-%m-%d)"
            jq -n \
              --arg  id    "$id" \
              --arg  name  "$_pv_name" \
              --arg  sport "$_sc_sport" \
              --arg  date  "${_pv_date}T00:00:00Z" \
              --arg  dist  "${_pv_dist:-0}" \
              --arg  mt    "${_pv_mt:-0}" \
              --arg  spd   "${_pv_spd:-}" \
              --arg  hr    "${_pv_hr:-}" \
              --arg  cad   "${_pv_cad:-}" \
              --arg  elevg "${_pv_elevg:-0}" \
              --arg  cals  "${_pv_cals_raw:-}" \
              --arg  temp  "${_pv_temp_raw:-null}" \
              --arg  steps "${_pv_steps:-}" \
              --arg  watts  "${_pv_watts:-}" \
              --arg  kj     "${_pv_kj:-}" \
              --arg  device "${_pv_device:-}" \
              --arg  gid    "${_pv_gear_id:-}" \
              --arg  gname  "${_pv_gear_name:-}" \
              '{
                id:                   ($id   | tonumber),
                name:                 $name,
                sport_type:           $sport,
                start_date_local:     $date,
                start_date:           $date,
                distance:             ($dist  | if .=="" then 0 else tonumber end),
                moving_time:          ($mt    | if .=="" then 0 else tonumber|floor end),
                total_elevation_gain: ($elevg | if .=="" then 0 else tonumber end),
                average_speed:        (($spd | if .=="" then 0 else tonumber end) as $s |
                                       if $s > 0 then $s
                                       elif ($dist|tonumber) > 0 and ($mt|tonumber) > 0
                                       then ($dist|tonumber) / ($mt|tonumber|floor)
                                       else 0 end),
                average_heartrate:    ($hr    | if .=="" then null else tonumber end),
                average_cadence:      ($cad   | if .=="" then null else tonumber end),
                average_watts:        ($watts | if .=="" then null else tonumber end),
                kilojoules:           ($kj    | if .=="" then null else tonumber end),
                calories:             ($cals  | if .=="" then null else tonumber|floor end),
                average_temp:         ($temp  | if .=="null" or .=="" then null else tonumber end),
                step_count:           ($steps | if .=="" then null else tonumber end),
                device_name:          (if $device=="" then null else $device end),
                gear_id:              (if $gid==""    then null else $gid end),
                gear:                 (if $gid==""    then null else {id: $gid, name: $gname} end)
              }' > "$TMP/detail.json" 2>/dev/null || true
          fi

          if ! jq -e '.id' "$TMP/detail.json" >/dev/null 2>&1; then
            if grep -qiE 'Log In to Strava|id="login-form"|action="/session"' "$TMP/sc_detail.html" 2>/dev/null; then
              log "detail backfill scrape: activity $id — Strava returned the login page (cookie expired); stopping detail backfill"
              _sc_cookie_expired=1
              break
            fi
            _sc_detail_sample="$(head -c 300 "$TMP/sc_detail.html" | tr '\n\r' '  ')"
            log "LAYOUT CHANGE DETECTED: detail backfill scrape: activity $id — neither similarActivitiesData nor pageView fallback produced data; response starts: ${_sc_detail_sample}; skipping"
            _sc_layout_fail=$((_sc_layout_fail+1))
            continue   # page loaded but parse failed — skip this activity, don't abort the run
          fi

          # Download the GPX export for the Leaflet map track.
          # Non-GPS activities (manual, indoor) return no track; we skip them.
          mkdir -p "$WEB_DIR/gpx"
          log "detail backfill: GET /activities/$id/export_gpx"
          _gpx_tmp="$TMP/$id.gpx"
          _gpx_code="$(curl_retry -sS \
            -o "$_gpx_tmp" \
            -w '%{http_code}' \
            -b "$STATE_DIR/strava_cookies.txt" \
            -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
            "https://www.strava.com/activities/$id/export_gpx" || echo 000)"
          if [ "$_gpx_code" = "200" ] && grep -q "<trkpt" "$_gpx_tmp" 2>/dev/null; then
            log "detail backfill: GPX saved for activity $id (has track points)"
            mv "$_gpx_tmp" "$WEB_DIR/gpx/$id.gpx"
            jq --arg gpx "gpx/$id.gpx" '. + {gpx_file: $gpx}' \
              "$TMP/detail.json" > "$TMP/detail_gpx.json" 2>/dev/null \
              && mv "$TMP/detail_gpx.json" "$TMP/detail.json"
          elif [ "$_gpx_code" = "429" ]; then
            # Rate limited — don't clobber any GPX we already have for this activity.
            rm -f "$_gpx_tmp"
            if [ -f "$WEB_DIR/gpx/$id.gpx" ] && grep -q "<trkpt" "$WEB_DIR/gpx/$id.gpx" 2>/dev/null; then
              log "detail backfill: GPX rate limited for activity $id (HTTP 429); keeping existing GPX"
              jq --arg gpx "gpx/$id.gpx" '. + {gpx_file: $gpx}' \
                "$TMP/detail.json" > "$TMP/detail_gpx.json" 2>/dev/null \
                && mv "$TMP/detail_gpx.json" "$TMP/detail.json"
            else
              # No existing GPX — save detail JSON without GPX, queue for GPX retry.
              grep -qxF "$id" "$STATE_DIR/gpx-pending.txt" 2>/dev/null \
                || echo "$id" >> "$STATE_DIR/gpx-pending.txt"
              log "detail backfill: GPX rate limited for activity $id (HTTP 429); detail saved, GPX queued for retry"
              # fall through — detail JSON saved below without gpx_file
            fi
          else
            log "detail backfill: GPX discarded for activity $id (HTTP $_gpx_code, no track points)"
            rm -f "$_gpx_tmp" "$WEB_DIR/gpx/$id.gpx"
            grep -qxF "$id" "$STATE_DIR/gpx-no-gps.txt" 2>/dev/null \
              || echo "$id" >> "$STATE_DIR/gpx-no-gps.txt"
          fi
        fi
        ;;
    esac
    case "$code" in
      200)
        # Validate it parses before committing it to the (web-served) detail dir.
        if jq -e . "$TMP/detail.json" >/dev/null 2>&1; then
          mv "$TMP/detail.json" "$DETAIL_DIR/$id.json"
          rm -f "$DETAIL_DIR/$id.minimal"   # upgraded from minimal to full
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
      401|403)
        log "detail backfill: unauthorized (HTTP $code) — token/cookie issue; stopping"
        break
        ;;
      *)
        log "detail backfill: activity $id returned HTTP $code; stopping to be safe"
        break
        ;;
    esac

    [ "$DETAIL_SLEEP" -gt 0 ] && sleep "$DETAIL_SLEEP"
  done < "$TMP/ids.txt"

  # --- 3b-ii. GPX queue backfill: historical details missing their GPX --------
  # Detail JSONs saved before GPX download was implemented, or in API mode,
  # have no gpx_file field.  Queue them so the retry block below can fill them
  # in without re-fetching the detail.  Skips known-no-GPS and already-pending.
  if [ "$STRAVA_SOURCE" = "scrape" ] && [ -d "$DETAIL_DIR" ]; then
    _gpx_queued=0
    for _dj in "$DETAIL_DIR"/*.json; do
      [ -f "$_dj" ] || continue
      _did="$(basename "$_dj" .json)"
      jq -e '.gpx_file' "$_dj" >/dev/null 2>&1 && continue
      [ -f "$WEB_DIR/gpx/$_did.gpx" ] && continue
      grep -qxF "$_did" "$STATE_DIR/gpx-no-gps.txt" 2>/dev/null && continue
      grep -qxF "$_did" "$STATE_DIR/gpx-pending.txt" 2>/dev/null && continue
      echo "$_did" >> "$STATE_DIR/gpx-pending.txt"
      _gpx_queued=$((_gpx_queued + 1))
    done
    [ "$_gpx_queued" -gt 0 ] && log "detail backfill: queued $_gpx_queued historical activities for GPX download"
  fi

  # --- 3b-iii. GPX retry for activities that hit 429 on a prior run ----------
  GPX_PENDING="$STATE_DIR/gpx-pending.txt"
  if [ -f "$GPX_PENDING" ] && [ -s "$GPX_PENDING" ] && [ "$STRAVA_SOURCE" = "scrape" ]; then
    _gpx_retried=0
    _gpx_tried=0
    _gpx_rate_limited=0   # set to 1 on 429; remaining IDs kept in queue, no more downloads
    _gpx_still_pending=""
    while IFS= read -r _gpx_id; do
      [ -n "$_gpx_id" ] || continue
      if [ -f "$WEB_DIR/gpx/$_gpx_id.gpx" ] && grep -q "<trkpt" "$WEB_DIR/gpx/$_gpx_id.gpx" 2>/dev/null; then
        # GPX already present — wire up reference if detail is missing it
        if [ -f "$DETAIL_DIR/$_gpx_id.json" ] && ! jq -e '.gpx_file' "$DETAIL_DIR/$_gpx_id.json" >/dev/null 2>&1; then
          jq --arg gpx "gpx/$_gpx_id.gpx" '. + {gpx_file: $gpx}' \
            "$DETAIL_DIR/$_gpx_id.json" > "$TMP/gpx_update.json" 2>/dev/null \
            && mv "$TMP/gpx_update.json" "$DETAIL_DIR/$_gpx_id.json"
        fi
        continue   # drop from pending — no need to rewrite it
      fi
      # Cap hit or rate limited: keep in queue, skip download, continue loop to
      # preserve all remaining IDs (avoids the data loss a bare `break` would cause).
      if [ "$_gpx_rate_limited" = "1" ] || { [ "$GPX_MAX_PER_RUN" -gt 0 ] && [ "$_gpx_tried" -ge "$GPX_MAX_PER_RUN" ]; }; then
        _gpx_still_pending="${_gpx_still_pending}${_gpx_id}
"
        continue
      fi
      _gpx_tried=$((_gpx_tried + 1))
      _gpx_tmp="$TMP/$_gpx_id.gpx"
      log "detail backfill: GPX retry for activity $_gpx_id..."
      _gpx_code="$(curl_retry -sS \
        -o "$_gpx_tmp" \
        -w '%{http_code}' \
        -b "$STATE_DIR/strava_cookies.txt" \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
        "https://www.strava.com/activities/$_gpx_id/export_gpx" || echo 000)"
      if [ "$_gpx_code" = "200" ] && grep -q "<trkpt" "$_gpx_tmp" 2>/dev/null; then
        mv "$_gpx_tmp" "$WEB_DIR/gpx/$_gpx_id.gpx"
        if [ -f "$DETAIL_DIR/$_gpx_id.json" ]; then
          jq --arg gpx "gpx/$_gpx_id.gpx" '. + {gpx_file: $gpx}' \
            "$DETAIL_DIR/$_gpx_id.json" > "$TMP/gpx_update.json" 2>/dev/null \
            && mv "$TMP/gpx_update.json" "$DETAIL_DIR/$_gpx_id.json"
        fi
        _gpx_retried=$((_gpx_retried + 1))
        log "detail backfill: GPX retry succeeded for activity $_gpx_id"
      elif [ "$_gpx_code" = "429" ]; then
        rm -f "$_gpx_tmp"
        _gpx_rate_limited=1
        _gpx_still_pending="${_gpx_still_pending}${_gpx_id}
"
        log "detail backfill: GPX retry rate limited for activity $_gpx_id; keeping queue for next run"
      else
        rm -f "$_gpx_tmp"
        log "detail backfill: GPX retry for activity $_gpx_id — HTTP $_gpx_code; discarding from queue"
        grep -qxF "$_gpx_id" "$STATE_DIR/gpx-no-gps.txt" 2>/dev/null \
          || echo "$_gpx_id" >> "$STATE_DIR/gpx-no-gps.txt"
      fi
      [ "$DETAIL_SLEEP" -gt 0 ] && sleep "$DETAIL_SLEEP"
    done < "$GPX_PENDING"
    printf '%s' "$_gpx_still_pending" > "$GPX_PENDING"
    _gpx_queue_left="$(grep -c . "$GPX_PENDING" 2>/dev/null || echo 0)"
    [ "$_gpx_retried" -gt 0 ] && log "detail backfill: GPX retry: $_gpx_retried saved; $_gpx_queue_left remaining in queue"
    [ "$_gpx_retried" -eq 0 ] && [ "$_gpx_queue_left" -gt 0 ] && log "detail backfill: GPX retry: cap reached ($GPX_MAX_PER_RUN/run); $_gpx_queue_left remaining will continue on later runs"
  fi

  DETAIL_HAVE="$(ls -1 "$DETAIL_DIR" 2>/dev/null | grep -c '\.json$' || true)"
  log "detail backfill: +$saved saved ($tried requests) this run, $DETAIL_HAVE/$TOTAL_STORED activities have detail"
  ADDED=$((ADDED + saved))
else
  log "detail backfill: disabled (STRAVA_MY_DETAIL_MAX_PER_RUN=0)"
fi
