# healthsync-fit-import.sh — sourced by healthsync-activities.sh (§3b).
# Detects Magene_MODEL_YYYY-MM-DD_ID_*.fit files in Drive, converts FIT→GPX
# via GPS Visualizer, and either merges the Magene record into a matching watch
# activity (dual-source) or adds a standalone Magene record to the store.
# Variables read from caller: HEALTHSYNC_MODE, TMP, STORE, GPX_DIR, STATE_DIR,
#   LIBDIR, LOCAL_DRIVE_DIR, DEFAULT_BIKE_NAME, WEATHER_LAT, WEATHER_LON,
#   log, curl_retry, fetch_weather_temp, drive_file_id, drive_download.
# Variables written back (shared scope):
#   ADDED — incremented per new/merged record; read by §5 skip-render guard.

# --- 3b. Magene FIT files (HEALTHSYNC_MODE=full only) -------------------------
# Detect Magene_MODEL_YYYY-MM-DD_ID_*.fit files placed manually in Drive.
# Convert FIT → GPX via GPS Visualizer (two-step curl), cache the GPX.
# If a matching watch activity is found by timing (Δstart<600s, Δend<300s),
# Magene distance/speed/cadence/elevation patch the watch record; watch keeps HR.
if [ "${HEALTHSYNC_MODE:-full}" = "full" ]; then
    jq -r '.files[].name | select(test("^Magene_[^_]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]+"))' \
        "$TMP/filelist.json" 2>/dev/null | sort -u > "$TMP/magene_files.txt" \
        || : > "$TMP/magene_files.txt"
    : > "$TMP/retro_absorbed.txt"

    while IFS= read -r _mf; do
        [ -n "$_mf" ] || continue
        _mmodel="$(printf '%s' "$_mf" | cut -d'_' -f2)"
        _mdate="$(printf '%s' "$_mf" | cut -d'_' -f3)"
        _muid="$(printf '%s' "$_mf" | cut -d'_' -f4)"
        _mact_id="magene-${_mdate}-${_muid}"
        _mgpx_safe="magene_${_mdate}_${_muid}.gpx"
        _mgpx_local="$GPX_DIR/$_mgpx_safe"
        _mretro=0

        if grep -qxF "$_mact_id" "$TMP/merged_magene_ids.txt" 2>/dev/null; then
            log "skipping merged Magene: $_mact_id"; continue
        fi
        if grep -qxF "$_mact_id" "$TMP/known_ids.txt" 2>/dev/null; then
            if [ -s "$TMP/cycling_watch_index.tsv" ] && [ -f "$_mgpx_local" ]; then
                log "retrying dual-source for standalone Magene: $_mact_id"
                _mretro=1
            else
                log "skipping known Magene: $_mact_id"; continue
            fi
        fi

        # Retro case: GPX already cached; grab FIT for wheel-sensor distance if available.
        if [ "$_mretro" = "1" ] && [ -n "${LOCAL_DRIVE_DIR:-}" ] && [ -f "$LOCAL_DRIVE_DIR/$_mf" ]; then
            cp "$LOCAL_DRIVE_DIR/$_mf" "$TMP/magene.fit" 2>/dev/null || true
        fi

        if [ "$_mretro" = "0" ]; then
            if [ -n "${LOCAL_DRIVE_DIR:-}" ] && [ -f "$LOCAL_DRIVE_DIR/$_mgpx_safe" ]; then
                log "Magene: using pre-converted local GPX: $_mgpx_safe"
                cp "$LOCAL_DRIVE_DIR/$_mgpx_safe" "$_mgpx_local"
                # Also grab FIT for accurate wheel-sensor distance
                [ -f "$LOCAL_DRIVE_DIR/$_mf" ] && cp "$LOCAL_DRIVE_DIR/$_mf" "$TMP/magene.fit" 2>/dev/null || true
            else
                log "new Magene FIT: $_mf → $_mact_id"

                _mfid="$(drive_file_id "$_mf")"
                [ -n "$_mfid" ] || { log "Magene: not found in Drive listing: $_mf"; continue; }
                drive_download "$_mfid" "$TMP/magene.fit" "$_mf" \
                    || { log "Magene: download failed: $_mf"; continue; }

                log "Magene: converting FIT to GPX via GPS Visualizer..."
                curl -s --max-time 120 \
                    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36" \
                    -H "Referer: https://www.gpsvisualizer.com/convert_input" \
                    -F "convert_format=gpx" \
                    -F "uploaded_file_1=@${TMP}/magene.fit" \
                    -F "submitted=Convert" \
                    "https://www.gpsvisualizer.com/convert?output" \
                    -o "$TMP/gv_resp.html" 2>/dev/null \
                    || { log "Magene: GPS Visualizer POST failed"; continue; }

                _mgpxpath="$(grep -o 'href="/[a-z_-]*/convert/[^"]*\.gpx"' "$TMP/gv_resp.html" \
                    | head -1 | cut -d'"' -f2 || true)"
                [ -n "$_mgpxpath" ] \
                    || { log "Magene: no GPX link in GPS Visualizer response"; continue; }

                log "Magene: downloading converted GPX from GPS Visualizer..."
                curl -s --max-time 60 \
                    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36" \
                    "https://www.gpsvisualizer.com${_mgpxpath}" \
                    -o "$TMP/magene.gpx" 2>/dev/null \
                    || { log "Magene: GPX download from GPS Visualizer failed"; continue; }

                cp "$TMP/magene.gpx" "$_mgpx_local"
            fi
        fi

        _melev="$(grep -o '<ele>[0-9.]*</ele>' "$_mgpx_local" \
            | tr -d '<el>/' \
            | jq -Rn '[inputs | tonumber] as $e |
                reduce range(1; $e|length) as $i (
                    0; . + (if $e[$i] > $e[$i-1] then $e[$i] - $e[$i-1] else 0 end)
                ) | round' 2>/dev/null || echo 0)"

        _mmspd="$(grep -o ':speed>[0-9.]*' "$_mgpx_local" \
            | grep -o '[0-9.]*' \
            | jq -Rn '[inputs | tonumber] | if length > 0 then max else 0 end' \
            2>/dev/null || echo 0)"

        _mcad="$(grep -o ':cad>[0-9]*' "$_mgpx_local" \
            | grep -o '[0-9]*' \
            | jq -Rn '[inputs | tonumber] | if length > 0 then (add / length | round) else null end' \
            2>/dev/null || echo null)"

        _mt1="$(grep -o '<time>[0-9T:Z.-]*</time>' "$_mgpx_local" | head -1 \
            | cut -d'>' -f2 | cut -d'<' -f1 || true)"
        _mt2="$(grep -o '<time>[0-9T:Z.-]*</time>' "$_mgpx_local" | tail -1 \
            | cut -d'>' -f2 | cut -d'<' -f1 || true)"
        _melapsed=0
        _mstart="${_mdate}T00:00:00Z"
        if [ -n "$_mt1" ] && [ -n "$_mt2" ]; then
            _mstart="$(printf '%s' "$_mt1" | cut -d'.' -f1 | tr -d 'Z')Z"
            _mh1="$(printf '%s' "$_mt1" | cut -dT -f2 | cut -d: -f1 | tr -dc '0-9')"
            _mm1="$(printf '%s' "$_mt1" | cut -dT -f2 | cut -d: -f2 | tr -dc '0-9')"
            _ms1="$(printf '%s' "$_mt1" | cut -dT -f2 | cut -d: -f3 | cut -d. -f1 | tr -dc '0-9')"
            _mh2="$(printf '%s' "$_mt2" | cut -dT -f2 | cut -d: -f1 | tr -dc '0-9')"
            _mm2="$(printf '%s' "$_mt2" | cut -dT -f2 | cut -d: -f2 | tr -dc '0-9')"
            _ms2="$(printf '%s' "$_mt2" | cut -dT -f2 | cut -d: -f3 | cut -d. -f1 | tr -dc '0-9')"
            _mh1="${_mh1#0}"; _mh1="${_mh1:-0}"
            _mm1="${_mm1#0}"; _mm1="${_mm1:-0}"
            _ms1="${_ms1#0}"; _ms1="${_ms1:-0}"
            _mh2="${_mh2#0}"; _mh2="${_mh2:-0}"
            _mm2="${_mm2#0}"; _mm2="${_mm2:-0}"
            _ms2="${_ms2#0}"; _ms2="${_ms2:-0}"
            _melapsed="$(( _mh2*3600 + _mm2*60 + _ms2 - (_mh1*3600 + _mm1*60 + _ms1) ))"
        fi

        _mstart_epoch="$(TZ=UTC date -D '%Y-%m-%dT%H:%M:%S' \
            -d "$(printf '%s' "$_mstart" | tr -d 'Z')" '+%s' 2>/dev/null || echo 0)"
        _mend_epoch=$(( _mstart_epoch + _melapsed ))

        # Prefer FIT odometer (wheel-sensor accuracy) over GPS Haversine.
        # FIT cumulative-distance records: uint32 LE, scale=100, unit=1/100 m.
        # Strategy: track the last value in a monotonically-increasing run (max step
        # 100000 raw = 1 km). Per-second records step by ~500-1000; spurious cross-field
        # patterns jump by millions or drop suddenly, so they break the run and are skipped.
        _mdist=0
        if [ -f "$TMP/magene.fit" ]; then
            _mfsize="$(wc -c < "$TMP/magene.fit" 2>/dev/null || echo 0)"
            _mskip=$(( _mfsize > 5000 ? _mfsize - 5000 : 0 ))
            _mdist="$(od -An -tu1 -j "$_mskip" "$TMP/magene.fit" 2>/dev/null \
                | awk 'BEGIN{b0=0;b1=0;b2=0;b3=0;n=0;prev=0;last=0}
                       {for(i=1;i<=NF;i++){
                           v=$i+0; b0=b1; b1=b2; b2=b3; b3=v; n++
                           if(n>=4){
                               u=b0+(b1*256)+(b2*65536)+(b3*16777216)
                               if(u>=50000 && u<=20000000){
                                   if(prev==0 || (u>=prev-5000 && u<=prev+100000)){
                                       last=u; prev=u
                                   }
                               }
                           }
                       }}
                       END{print (last>0 ? int(last/100) : 0)}' 2>/dev/null || echo 0)"
        fi
        if [ "${_mdist:-0}" -le 0 ]; then
            log "Magene: FIT distance unavailable, falling back to GPS Haversine"
            _mdist="$(grep '<trkpt' "$_mgpx_local" \
                | grep -o 'lat="[^"]*" lon="[^"]*"' \
                | tr -d 'laton="' \
                | jq -Rn '
                    [inputs | split(" ") | {lat:(.[0]|tonumber), lon:(.[1]|tonumber)}] as $p |
                    def deg: . * 3.14159265358979 / 180;
                    reduce range(1; $p|length) as $i (0;
                        ($p[$i-1].lat | deg) as $a1 |
                        ($p[$i].lat   | deg) as $a2 |
                        ($p[$i].lon - $p[$i-1].lon | deg) as $dl |
                        (($a1|sin)*($a2|sin) + ($a1|cos)*($a2|cos)*($dl|cos)) as $c |
                        . + (6371000 * (if $c >= 1 then 0
                                       elif $c <= -1 then 3.14159265
                                       else ($c|acos) end))
                    ) | round' 2>/dev/null || echo 0)"
        fi

        _mavg="$(jq -n \
            --argjson d "${_mdist:-0}" \
            --argjson t "$_melapsed" \
            'if $t > 0 then $d / $t else 0 end')"

        _mgearf="\"${DEFAULT_BIKE_NAME:-}\""
        _mgpxref="\"gpx/$_mgpx_safe\""

        # Dual-source detection: compare Magene start/end epochs with cycling watch index
        _mwatch_id=""
        if [ -s "$TMP/cycling_watch_index.tsv" ] && [ "$_mstart_epoch" -gt 0 ]; then
            while IFS= read -r _wi_line; do
                _wi_id="$(printf '%s' "$_wi_line" | cut -f1)"
                _wi_start="$(printf '%s' "$_wi_line" | cut -f2)"
                _wi_end="$(printf '%s' "$_wi_line" | cut -f3)"
                _ds=$(( _mstart_epoch - _wi_start ))
                [ "$_ds" -lt 0 ] && _ds=$(( 0 - _ds ))
                [ "$_ds" -gt 600 ] && continue
                _de=$(( _mend_epoch - _wi_end ))
                [ "$_de" -lt 0 ] && _de=$(( 0 - _de ))
                [ "$_de" -gt 300 ] && continue
                _mwatch_id="$_wi_id"
                log "Magene: dual-source match: $_mf ↔ $_wi_id (Δstart=${_ds}s Δend=${_de}s)"
                break
            done < "$TMP/cycling_watch_index.tsv"
        fi

        if [ -n "$_mwatch_id" ]; then
            # MERGE PATH: write a patch file; §3c applies it to the watch record
            jq -nc \
                --argjson distance  "${_mdist:-0}" \
                --argjson max_speed "${_mmspd:-0}" \
                --argjson avg_cad   "$_mcad" \
                --argjson elevation "${_melev:-0}" \
                --arg     magene_id "$_mact_id" \
                --arg     magene_gpx "gpx/$_mgpx_safe" \
                '{distance:$distance, max_speed:$max_speed, average_cadence:$avg_cad,
                  total_elevation_gain:$elevation, magene_id:$magene_id,
                  magene_gpx_file:$magene_gpx, dual_source:true}' \
                > "$TMP/magene_patch_${_mwatch_id}.json"
            printf '%s\n' "$_mact_id" >> "$TMP/known_ids.txt"
            printf '%s\n' "$_mact_id" >> "$TMP/merged_magene_ids.txt"
            if [ "$_mretro" = "1" ]; then
                printf '%s\n' "$_mact_id" >> "$TMP/retro_absorbed.txt"
                log "Magene: retroactive merge of $_mact_id into watch record $_mwatch_id"
            else
                ADDED=$((ADDED + 1))
                log "Magene: merged $_mact_id into watch record $_mwatch_id"
            fi
        else
            if [ "$_mretro" = "1" ]; then
                log "Magene: no watch match on retry for $_mact_id"; continue
            fi
            # STANDALONE PATH: fetch weather and write a full standalone record
            _mwtemp="null" _mwsrc="null"
            _mw_apparent_temp="null" _mw_wind_speed="null" _mw_wind_dir="null" _mw_weathercode="null" _mw_precipitation="null"
            _mwlat="$(grep '<trkpt' "$_mgpx_local" | head -1 \
                | grep -o 'lat="[^"]*"' | cut -d'"' -f2 | head -1 || true)"
            _mwlon="$(grep '<trkpt' "$_mgpx_local" | head -1 \
                | grep -o 'lon="[^"]*"' | cut -d'"' -f2 | head -1 || true)"
            [ -z "$_mwlat" ] && _mwlat="${WEATHER_LAT:-}"
            [ -z "$_mwlon" ] && _mwlon="${WEATHER_LON:-}"
            if [ -n "$_mwlat" ] && [ -n "$_mwlon" ]; then
                _fw_temp_source="" _fw_apparent_temp="" _fw_wind_speed="" _fw_wind_dir="" _fw_weathercode="" _fw_precipitation=""
                _mwt="$(fetch_weather_temp "$_mwlat" "$_mwlon" "$_mdate" || true)"
                if [ -n "$_mwt" ]; then
                    _mwtemp="$_mwt"
                    _mwsrc="\"$_fw_temp_source\""
                    [ -n "$_fw_apparent_temp" ] && _mw_apparent_temp="$_fw_apparent_temp"
                    [ -n "$_fw_wind_speed"    ] && _mw_wind_speed="$_fw_wind_speed"
                    [ -n "$_fw_wind_dir"      ] && _mw_wind_dir="$_fw_wind_dir"
                    [ -n "$_fw_weathercode"   ] && _mw_weathercode="$_fw_weathercode"
                    [ -n "$_fw_precipitation" ] && _mw_precipitation="$_fw_precipitation"
                fi
            fi
            jq -nc \
                --arg     id           "$_mact_id" \
                --arg     date         "$_mdate" \
                --arg     start_date   "$_mstart" \
                --arg     name         "Magene ${_mmodel}" \
                --argjson distance     "${_mdist:-0}" \
                --argjson moving_time  "$_melapsed" \
                --argjson elapsed_time "$_melapsed" \
                --argjson elevation    "${_melev:-0}" \
                --argjson avg_speed    "$_mavg" \
                --argjson max_speed    "${_mmspd:-0}" \
                --argjson avg_cad      "$_mcad" \
                --argjson avg_temp     "$_mwtemp" \
                --argjson temp_src     "$_mwsrc" \
                --argjson apparent_temp "$_mw_apparent_temp" \
                --argjson wind_speed   "$_mw_wind_speed" \
                --argjson wind_dir     "$_mw_wind_dir" \
                --argjson weathercode  "$_mw_weathercode" \
                --argjson precipitation "$_mw_precipitation" \
                --argjson gear_id      "$_mgearf" \
                --argjson gpx_file     "$_mgpxref" \
                '{id:$id, date:$date, start_date:$start_date, start_date_local:$start_date,
                  name:$name, sport_type:"Ride", gear_id:$gear_id,
                  distance:$distance,
                  moving_time:($moving_time|tonumber), elapsed_time:($elapsed_time|tonumber),
                  total_elevation_gain:$elevation, average_speed:$avg_speed, max_speed:$max_speed,
                  average_heartrate:null, max_heartrate:null,
                  average_cadence:$avg_cad, average_watts:null, kilojoules:null,
                  average_temp:$avg_temp, temp_source:$temp_src,
                  apparent_temp:$apparent_temp, wind_speed:$wind_speed, wind_dir:$wind_dir,
                  weathercode:$weathercode, precipitation:$precipitation,
                  suffer_score:null, calories:null, gpx_file:$gpx_file, dual_source:false}' >> "$STORE"
            printf '%s\n' "$_mact_id" >> "$TMP/known_ids.txt"
            ADDED=$((ADDED + 1))
            log "added Magene: $_mact_id (${_mdist:-0}m, ${_melapsed}s)"
        fi
    done < "$TMP/magene_files.txt"

    # --- 3c. Apply dual-source merge patches to store --------------------------
    # awk removes retro-absorbed standalone records (one pass, no jq).
    # The while loop applies patch files: jq is spawned only for matched watch
    # records (typically 1-2 per run), not for every line in the store.
    if [ -s "$TMP/retro_absorbed.txt" ]; then
        awk -v af="$TMP/retro_absorbed.txt" 'BEGIN{
            while((getline id < af) > 0) drop[id]=1
        } /^\{/{
            n=split($0,a,"\""); id=a[4]
            if(!drop[id]) print
        }' "$STORE" > "$TMP/store_absorbed.ndjson" \
            && mv "$TMP/store_absorbed.ndjson" "$STORE"
    fi
    if ls "$TMP"/magene_patch_*.json >/dev/null 2>&1; then
        _merged_count=0
        while IFS= read -r _mpl; do
            _mpl_id="$(printf '%s' "$_mpl" | cut -d'"' -f4)"
            _pf="$TMP/magene_patch_${_mpl_id}.json"
            if [ -f "$_pf" ]; then
                _mpl="$(printf '%s' "$_mpl" | jq -c --argjson _p "$(cat "$_pf")" \
                    '. * $_p' 2>/dev/null || printf '%s' "$_mpl")"
                _merged_count=$(( _merged_count + 1 ))
            fi
            printf '%s\n' "$_mpl"
        done < "$STORE" > "$TMP/store_merged.ndjson" \
            && mv "$TMP/store_merged.ndjson" "$STORE"
        [ "$_merged_count" -gt 0 ] && \
            log "Magene: merged $_merged_count dual-source ride(s) into store"
    fi
fi
