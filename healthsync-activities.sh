#!/bin/sh
# HealthSync / Google Drive → My Activities Dashboard
# ---------------------------------------------------
# Downloads activity exports from Google Drive (placed by healthsync.app on
# Android), accumulates them in a persistent NDJSON store, and renders the
# same static HTML dashboard as strava-my-activities.sh. Switch cron to this
# script when Strava API access ends; both scripts produce the same page set.
#
# Data formats used: CSV (summary), TCX (HR + calories via grep), GPX (map +
# elevation — cached locally, parsed in-browser via leaflet-gpx).
#
# Requires: curl, jq. No xmllint needed — TCX fields extracted with grep -o.
# Run by cron once a day. See README.md for setup.

set -eu

LIBDIR="$(dirname "$0")"
# shellcheck disable=SC1090
. "$LIBDIR/strava-lib.sh"

CONFIG="${HEALTHSYNC_CONFIG:-/etc/healthsync-activities.conf}"
[ -f "$CONFIG" ] || die "config not found: $CONFIG (copy config-healthsync.example)"
# shellcheck disable=SC1090
. "$CONFIG"

: "${GOOGLE_CLIENT_ID:?set GOOGLE_CLIENT_ID in $CONFIG}"
: "${GOOGLE_CLIENT_SECRET:?set GOOGLE_CLIENT_SECRET in $CONFIG}"
: "${GOOGLE_REFRESH_TOKEN:?set GOOGLE_REFRESH_TOKEN in $CONFIG}"
: "${DRIVE_FOLDER_ID:?set DRIVE_FOLDER_ID in $CONFIG}"

TOKEN_REFRESH_MARGIN="${HEALTHSYNC_TOKEN_REFRESH_MARGIN:-300}"
STATE_DIR="${HEALTHSYNC_STATE_DIR:-/usr/lib/healthsync}"
WEB_DIR="${HEALTHSYNC_WEB_DIR:-/www/strava/me}"
BIKE_DATA="${HEALTHSYNC_BIKE_DATA:-$STATE_DIR/bike-service.json}"
BIKE_ASSIGN="${HEALTHSYNC_BIKE_ASSIGN:-$STATE_DIR/bike-assignments.json}"
DEFAULT_BIKE_NAME="${HEALTHSYNC_DEFAULT_BIKE:-Kross}"
CGI_DIR="${HEALTHSYNC_CGI_DIR:-/www/cgi-bin}"
IMPORT_ENABLED="${HEALTHSYNC_IMPORT_ENABLED:-1}"
IMPORT_STRAVA="${HEALTHSYNC_IMPORT_STRAVA_STORE:-}"
BIRTH_YEAR="${HEALTHSYNC_BIRTH_YEAR:-}"
ATHLETE_AGE=""
[ -n "$BIRTH_YEAR" ] && ATHLETE_AGE="$(( $(date '+%Y') - BIRTH_YEAR ))"

command -v curl >/dev/null 2>&1 || die "curl not installed (opkg install curl ca-bundle)"
command -v jq   >/dev/null 2>&1 || die "jq not installed (opkg install jq)"

GPX_DIR="$WEB_DIR/gpx"
DETAIL_DIR="$WEB_DIR/details"
STORE="$STATE_DIR/activities.ndjson"
TOKEN_STATE="$STATE_DIR/gdrive-token.json"
GEARS_CACHE="$STATE_DIR/gears-strava-cache.json"

mkdir -p "$STATE_DIR" "$WEB_DIR" "$GPX_DIR" "$DETAIL_DIR"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/healthsync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- 0. One-time migration: import historical activities from a Strava store --
# Set HEALTHSYNC_IMPORT_STRAVA_STORE=/path/to/strava-my-activities/activities.ndjson
# in the config to carry over Strava history. On each run, any record whose .id
# is not yet in the HealthSync store is appended. Idempotent and safe to leave
# in place permanently — the 30-day Drive window means HealthSync will only ever
# produce new records, so the Strava history sits untouched in the merged store.
# Strava IDs are numeric (18784255013); HealthSync IDs are strings (2026-06-22-…)
# — they never collide, so no deduplication between sources is needed.
if [ -n "$IMPORT_STRAVA" ] && [ -f "$IMPORT_STRAVA" ]; then
    [ -f "$STORE" ] && jq -r '.id | tostring' "$STORE" > "$TMP/hs-ids.txt" 2>/dev/null \
        || : > "$TMP/hs-ids.txt"
    imported=0
    while IFS= read -r line; do
        aid="$(printf '%s' "$line" | jq -r '.id | tostring' 2>/dev/null)" || continue
        [ -z "$aid" ] && continue
        grep -qxF "$aid" "$TMP/hs-ids.txt" && continue
        printf '%s\n' "$line" >> "$STORE"
        printf '%s\n' "$aid" >> "$TMP/hs-ids.txt"
        imported=$((imported + 1))
    done < "$IMPORT_STRAVA"
    log "Strava history: $imported activities merged from $IMPORT_STRAVA (store now $(wc -l < "$STORE" | tr -d ' ') total)"

    # One-time migration: copy bike-service.json and bike-assignments.json from
    # the Strava state dir (same directory as IMPORT_STRAVA) if the HealthSync
    # files do not exist yet. Idempotent — skipped on every subsequent run.
    _sd="$(dirname "$IMPORT_STRAVA")"
    if [ ! -f "$BIKE_DATA" ] && [ -f "$_sd/bike-service.json" ]; then
        cp "$_sd/bike-service.json" "$BIKE_DATA"
        log "migrated bike-service.json from $_sd"
    fi
    if [ ! -f "$BIKE_ASSIGN" ] && [ -f "$_sd/bike-assignments.json" ]; then
        cp "$_sd/bike-assignments.json" "$BIKE_ASSIGN"
        log "migrated bike-assignments.json from $_sd"
    fi
    unset _sd
fi

ADDED=0
if [ "$IMPORT_ENABLED" != "0" ]; then

# --- 1. Google Drive access token -------------------------------------------
# Same pattern as strava-lib.sh: cache the token, refresh when near expiry.
# Google does not rotate refresh tokens on access-token refresh.
ensure_drive_token() {
    now="$(date +%s)"
    if [ -f "$TOKEN_STATE" ]; then
        cached="$(jq -r '.access_token // empty' "$TOKEN_STATE" 2>/dev/null || true)"
        exp="$(jq -r '.expires_at // 0' "$TOKEN_STATE" 2>/dev/null || echo 0)"
        case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
        if [ -n "$cached" ] && [ "$exp" -gt "$((now + TOKEN_REFRESH_MARGIN))" ]; then
            ACCESS_TOKEN="$cached"
            log "reusing cached Drive token (valid for $((exp - now))s more)"
            return 0
        fi
    fi
    log "refreshing Google Drive token..."
    curl_retry -fsS https://oauth2.googleapis.com/token \
        -d "client_id=$GOOGLE_CLIENT_ID" \
        -d "client_secret=$GOOGLE_CLIENT_SECRET" \
        -d "refresh_token=$GOOGLE_REFRESH_TOKEN" \
        -d "grant_type=refresh_token" \
        -o "$TMP/token.json" || die "Drive token refresh failed"
    ACCESS_TOKEN="$(jq -r '.access_token // empty' "$TMP/token.json")"
    [ -n "$ACCESS_TOKEN" ] || die "no access_token in Drive response: $(cat "$TMP/token.json")"
    expires_in="$(jq -r '.expires_in // 3600' "$TMP/token.json")"
    jq --argjson exp "$((now + expires_in))" '. + {expires_at: $exp}' \
        "$TMP/token.json" > "$TOKEN_STATE"
    chmod 600 "$TOKEN_STATE"
    log "Drive token refreshed (valid ~${expires_in}s)"
}

ensure_drive_token

# --- 2. List Drive folder ----------------------------------------------------
log "listing Drive folder $DRIVE_FOLDER_ID..."
QUERY="'${DRIVE_FOLDER_ID}'+in+parents+and+trashed=false"
curl_retry -fsS \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://www.googleapis.com/drive/v3/files?q=${QUERY}&fields=files(id,name,modifiedTime)&pageSize=1000" \
    -o "$TMP/filelist.json" || die "Drive file listing failed"
file_count="$(jq '.files | length' "$TMP/filelist.json")"
log "found $file_count files in Drive folder"

# keepalive mode: token refresh + folder check only
case "${HEALTHSYNC_MODE:-full}" in keepalive) log "keepalive done."; exit 0 ;; esac

# Build name→id lookup (tab-separated, sorted for grep -F)
jq -r '.files[] | "\(.name)\t\(.id)"' "$TMP/filelist.json" | sort > "$TMP/name_to_id.tsv"

drive_file_id() {
    # Returns the Drive file id for a given filename, or empty string.
    grep -F "$1	" "$TMP/name_to_id.tsv" | cut -f2 | head -1 || true
}

drive_download() {
    fid="$1"; dest="$2"
    curl_retry -fsS -L \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://www.googleapis.com/drive/v3/files/${fid}?alt=media" \
        -o "$dest"
}

# --- 3. Process new activity files ------------------------------------------
# Enumerate unique activity base names from all file extensions (CSV, TCX, GPX,
# KML, FIT). CSV has precise summary data and is used when present; cycling
# activities may export only TCX+GPX, so TCX is the fallback for distance/time.
[ -f "$STORE" ] || : > "$STORE"
jq -r '.id' "$STORE" 2>/dev/null | sort > "$TMP/known_ids.txt" || : > "$TMP/known_ids.txt"

ADDED=0

# Strip any known extension, then keep names matching either HealthSync format:
#   Old (type-first):  "WALKING 2026.06.22 20.01"
#   New (date-first):  "2026.06.22 15.07-WALKING"
jq -r '.files[].name |
    gsub("[.](csv|gpx|tcx|kml|fit)$"; "") |
    select(
        test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2} [0-9]{2}\\.[0-9]{2}-[A-Z_]+$") or
        test("^[A-Z_]+ [0-9]{4}\\.[0-9]{2}\\.[0-9]{2} [0-9]{2}\\.[0-9]{2}$")
    )
' "$TMP/filelist.json" | sort -u > "$TMP/activity_bases.txt"
log "unique activities found: $(wc -l < "$TMP/activity_bases.txt" | tr -d ' ')"

while IFS= read -r base; do
    [ -n "$base" ] || continue

    # Detect format from base name:
    #   Old (type-first):  "WALKING 2026.06.22 20.01"
    #   New (date-first):  "2026.06.22 15.07-WALKING"
    case "$base" in
        [0-9]*)
            # New format: date-first
            date_part="$(printf '%s' "$base" | cut -d' ' -f1)"   # 2026.06.22
            rest="$(printf '%s' "$base" | cut -d' ' -f2)"         # 15.07-WALKING
            time_part="$(printf '%s' "$rest" | cut -d'-' -f1)"    # 15.07
            activity_type="$(printf '%s' "$rest" | cut -d'-' -f2-)" # WALKING
            ;;
        *)
            # Old format: type-first
            activity_type="$(printf '%s' "$base" | cut -d' ' -f1)"
            date_part="$(printf '%s' "$base" | cut -d' ' -f2)"   # 2026.06.22
            time_part="$(printf '%s' "$base" | cut -d' ' -f3)"   # 20.01
            ;;
    esac

    # Stable ID: "2026-06-22-20-01-walking"
    type_lower="$(printf '%s' "$activity_type" | tr '[:upper:]' '[:lower:]')"
    act_id="$(printf '%s-%s-%s' "$date_part" "$time_part" "$type_lower" | tr '.' '-')"

    if grep -qxF "$act_id" "$TMP/known_ids.txt" 2>/dev/null; then
        log "skipping known: $act_id"
        continue
    fi

    log "new activity: $act_id"

    # Date/time from filename (CSV may override with the exact recorded value)
    act_date="$(printf '%s' "$date_part" | tr '.' '-')"
    act_time="$(printf '%s' "$time_part" | tr '.' ':'):00"
    act_start="${act_date}T${act_time}Z"
    distance_m=0; csv_active=0; csv_elapsed=0

    # --- Summary data: CSV preferred (exact start time + distance + active time) ---
    csv_id="$(drive_file_id "${base}.csv")"
    # Also check extensionless variant (some HealthSync versions omit .csv)
    [ -z "$csv_id" ] && csv_id="$(drive_file_id "$base")"

    if [ -n "$csv_id" ] && drive_download "$csv_id" "$TMP/activity.csv" 2>/dev/null; then
        # Skip header row; columns: source_app,type,name,date,time,elapsed_s,active_s,dist_km
        # Strip \r so CRLF exports from the Android app don't leave a trailing \r on the
        # last field, which would break jq's tonumber on csv_dist_km.
        csv_data="$(tail -n +2 "$TMP/activity.csv" | head -1 | tr -d '\r')"
        if [ -n "$csv_data" ]; then
            csv_datetime="$(printf '%s' "$csv_data" | cut -d, -f4)"  # 2026.06.22 20:01:42
            csv_elapsed="$(printf '%s' "$csv_data" | cut -d, -f6)"   # elapsed seconds
            csv_active="$(printf '%s' "$csv_data" | cut -d, -f7)"    # active seconds
            csv_dist_km="$(printf '%s' "$csv_data" | cut -d, -f8)"   # distance in km
            act_date="$(printf '%s' "$csv_datetime" | cut -d' ' -f1 | tr '.' '-')"
            act_time="$(printf '%s' "$csv_datetime" | cut -d' ' -f2)"
            act_start="${act_date}T${act_time}Z"
            distance_m="$(printf '%s' "$csv_dist_km" | jq -Rr 'tonumber * 1000 | round')"
        fi
    fi

    avg_speed="$(jq -n --argjson d "$distance_m" --argjson t "$csv_active" \
        'if $t>0 then $d/$t else 0 end')"

    case "$activity_type" in
        WALKING|NORDIC_WALKING) sport_type="Walk" ;;
        RUNNING)                sport_type="Run" ;;
        CYCLING|BIKING|INDOOR_CYCLING|E_BIKING) sport_type="Ride" ;;
        SWIMMING)               sport_type="Swim" ;;
        HIKING)                 sport_type="Hike" ;;
        *)                      sport_type="$activity_type" ;;
    esac

    # TCX: HR + calories; also distance/time when no CSV was available.
    # Use "${base}.tcx" so both old-format and new-format names resolve correctly.
    tcx_name="${base}.tcx"
    avg_hr="null"; max_hr="null"; calories="null"; avg_watts_v="null"; kj_v="null"
    tcx_id="$(drive_file_id "$tcx_name")"
    if [ -n "$tcx_id" ] && drive_download "$tcx_id" "$TMP/activity.tcx" 2>/dev/null; then
        _v="$(grep -o 'AverageHeartRateBpm><Value>[0-9]*</Value>' \
            "$TMP/activity.tcx" | head -1 | grep -o 'Value>[0-9]*' | grep -o '[0-9]*$' || true)"
        [ -n "$_v" ] && avg_hr="$_v"
        _v="$(grep -o 'MaximumHeartRateBpm><Value>[0-9]*</Value>' \
            "$TMP/activity.tcx" | head -1 | grep -o 'Value>[0-9]*' | grep -o '[0-9]*$' || true)"
        [ -n "$_v" ] && max_hr="$_v"
        _v="$(grep -o '<Calories>[0-9]*</Calories>' \
            "$TMP/activity.tcx" | head -1 | grep -o '[0-9]*</Calories>' | grep -o '^[0-9]*' || true)"
        [ -n "$_v" ] && calories="$_v"
        # No CSV: extract distance and total time from TCX lap summaries.
        # Last cumulative <DistanceMeters> trackpoint = total activity distance.
        # Sum all <TotalTimeSeconds> entries to handle multi-lap activities.
        if [ "$distance_m" = "0" ] && [ "$csv_active" = "0" ]; then
            _dist="$(grep -o '<DistanceMeters>[0-9.]*</DistanceMeters>' "$TMP/activity.tcx" \
                | tail -1 | grep -o '<DistanceMeters>[0-9.]*' | grep -o '[0-9.]*$' || true)"
            [ -n "$_dist" ] && distance_m="$(printf '%s' "$_dist" | jq -Rr 'tonumber | round')"
            _time="$(grep -o '<TotalTimeSeconds>[0-9.]*</TotalTimeSeconds>' "$TMP/activity.tcx" \
                | grep -o '<TotalTimeSeconds>[0-9.]*' | grep -o '[0-9.]*$' \
                | jq -Rn '[inputs | tonumber] | add // 0 | round' || echo 0)"
            csv_elapsed="$_time"; csv_active="$_time"
            avg_speed="$(jq -n --argjson d "$distance_m" --argjson t "$csv_active" \
                'if $t>0 then $d/$t else 0 end')"
        fi
        # Watts: average trackpoint power (power meter only)
        avg_watts_v="$(grep -o '<Watts>[0-9]*</Watts>' "$TMP/activity.tcx" \
            | grep -o '[0-9]*</Watts>' | grep -o '^[0-9]*' \
            | jq -Rn '[inputs | tonumber] | if length>0 then (add/length | round) else null end' \
            2>/dev/null || echo null)"
        if [ "$avg_watts_v" != "null" ] && [ "$csv_active" -gt 0 ]; then
            kj_v="$(jq -n --argjson w "$avg_watts_v" --argjson t "$csv_active" \
                '$w * $t / 1000 | round')"
        fi
    fi
    # kJ ≈ kcal (Strava convention; ~25% cycling efficiency makes them numerically equal)
    if [ "$kj_v" = "null" ] && [ "$calories" != "null" ]; then
        kj_v="$calories"
        if [ "$avg_watts_v" = "null" ] && [ "$csv_active" -gt 0 ]; then
            avg_watts_v="$(jq -n --argjson kj "$kj_v" --argjson t "$csv_active" \
                '$kj * 1000 / $t | round')"
        fi
    fi

    # GPX: cache locally + compute elevation gain
    # Elevation chars removed by tr: <, e, l, > and / — none appear in numeric values.
    gpx_name="${base}.gpx"
    gpx_safe="$(printf '%s' "$gpx_name" | tr ' ' '_')"
    gpx_local="$GPX_DIR/$gpx_safe"
    gpx_ref="null"; elevation_gain=0; max_speed_v=0

    gpx_id="$(drive_file_id "$gpx_name")"
    if [ -n "$gpx_id" ] && drive_download "$gpx_id" "$gpx_local" 2>/dev/null; then
        gpx_ref="\"gpx/$gpx_safe\""
        elevation_gain="$(grep -o '<ele>[0-9.]*</ele>' "$gpx_local" \
            | tr -d '<el>/' \
            | jq -Rn '[inputs | tonumber] as $e |
                reduce range(1; $e|length) as $i (
                    0; . + (if $e[$i] > $e[$i-1] then $e[$i] - $e[$i-1] else 0 end)
                ) | round' 2>/dev/null || echo 0)"
        # Max speed from GPX speed extension (m/s); Garmin/Wahoo export gpxtpx:speed
        _mspd="$(grep -o ':speed>[0-9.]*' "$gpx_local" \
            | grep -o '[0-9.]*$' \
            | jq -Rn '[inputs | tonumber] | if length>0 then max else 0 end' \
            2>/dev/null || echo 0)"
        max_speed_v="${_mspd:-0}"
    fi

    case "$sport_type" in
        Ride|EBikeRide|VirtualRide|Handcycle|MountainBikeRide|GravelRide)
            gear_id="\"$DEFAULT_BIKE_NAME\"" ;;
        *) gear_id="null" ;;
    esac

    # Weather temp: extract start lat/lon from GPX first trackpoint, fall back to config
    _w_lat="" _w_lon="" _w_temp="null" _w_temp_src="null"
    if [ -n "$gpx_local" ] && [ -f "$gpx_local" ]; then
        _w_lat=$(grep '<trkpt' "$gpx_local" | head -n1 | grep -o 'lat="[^"]*"' | cut -d'"' -f2 | head -n1 || true)
        _w_lon=$(grep '<trkpt' "$gpx_local" | head -n1 | grep -o 'lon="[^"]*"' | cut -d'"' -f2 | head -n1 || true)
    fi
    [ -z "$_w_lat" ] && _w_lat="${WEATHER_LAT:-}"
    [ -z "$_w_lon" ] && _w_lon="${WEATHER_LON:-}"
    if [ -n "$_w_lat" ] && [ -n "$_w_lon" ]; then
        _fw_temp_source=""
        _t=$(fetch_weather_temp "$_w_lat" "$_w_lon" "$act_date" || true)
        if [ -n "$_t" ]; then
            _w_temp="$_t"
            _w_temp_src="\"$_fw_temp_source\""
        fi
    fi

    jq -nc \
        --arg id         "$act_id" \
        --arg date       "$act_date" \
        --arg start_date "$act_start" \
        --arg name       "$activity_type" \
        --arg sport_type "$sport_type" \
        --argjson distance     "$distance_m" \
        --argjson moving_time  "$csv_active" \
        --argjson elapsed_time "$csv_elapsed" \
        --argjson elevation    "$elevation_gain" \
        --argjson avg_speed    "$avg_speed" \
        --argjson avg_hr       "$avg_hr" \
        --argjson max_hr       "$max_hr" \
        --argjson calories     "$calories" \
        --argjson gpx_file     "$gpx_ref" \
        --argjson gear_id      "$gear_id" \
        --argjson max_speed    "$max_speed_v" \
        --argjson avg_watts    "$avg_watts_v" \
        --argjson avg_temp     "$_w_temp" \
        --argjson temp_src     "$_w_temp_src" \
        --argjson kj           "$kj_v" \
        '{id:$id, date:$date, start_date:$start_date, start_date_local:$start_date,
          name:$name, sport_type:$sport_type, gear_id:$gear_id,
          distance:$distance,
          moving_time:($moving_time|tonumber), elapsed_time:($elapsed_time|tonumber),
          total_elevation_gain:$elevation, average_speed:$avg_speed, max_speed:$max_speed,
          average_heartrate:$avg_hr, max_heartrate:$max_hr,
          average_cadence:null, average_watts:$avg_watts, kilojoules:$kj,
          average_temp:$avg_temp, temp_source:$temp_src, suffer_score:null,
          calories:$calories, gpx_file:$gpx_file}' >> "$STORE"

    printf '%s\n' "$act_id" >> "$TMP/known_ids.txt"
    ADDED=$((ADDED + 1))
done < "$TMP/activity_bases.txt"

TOTAL="$(wc -l < "$STORE" | tr -d ' ')"
log "store: +$ADDED new, $TOTAL total"

# Backfill average_temp for records with null temp (archive + forecast fallback),
# and upgrade forecast temps to archive once archive data becomes available
# (~7 days after the activity date). Only null-temp and forecast-sourced records
# are touched; archive temps and pre-existing records without temp_source are left.
_bf_count=0
: > "$TMP/store_patched.ndjson"
while IFS= read -r _line; do
    _bf_case=$(printf '%s' "$_line" | jq -r \
        'if .average_temp == null then "null"
         elif (.temp_source == "forecast" and .date <= (now - 604800 | strftime("%Y-%m-%d"))) then "upgrade"
         else "" end' 2>/dev/null || true)
    if [ -n "$_bf_case" ]; then
        _d=$(printf '%s' "$_line" | jq -r '.date')
        _gf=$(printf '%s' "$_line" | jq -r '.gpx_file // ""')
        _bl="" _blon=""
        if [ -n "$_gf" ] && [ -f "$WEB_DIR/$_gf" ]; then
            _bl=$(grep '<trkpt' "$WEB_DIR/$_gf" | head -n1 | grep -o 'lat="[^"]*"' | cut -d'"' -f2 | head -n1 || true)
            _blon=$(grep '<trkpt' "$WEB_DIR/$_gf" | head -n1 | grep -o 'lon="[^"]*"' | cut -d'"' -f2 | head -n1 || true)
        fi
        [ -z "$_bl" ] && _bl="${WEATHER_LAT:-}"
        [ -z "$_blon" ] && _blon="${WEATHER_LON:-}"
        if [ -n "$_bl" ] && [ -n "$_blon" ]; then
            _fw_temp_source=""
            [ "$_bf_case" = "upgrade" ] && _fw_archive_only=1
            _t2=$(fetch_weather_temp "$_bl" "$_blon" "$_d" || true)
            _fw_archive_only=0
            if [ -n "$_t2" ]; then
                _line=$(printf '%s' "$_line" | jq --argjson t "$_t2" --arg src "$_fw_temp_source" \
                    '.average_temp = $t | .temp_source = $src')
                _bf_count=$((_bf_count + 1))
            fi
        fi
    fi
    printf '%s\n' "$_line"
done < "$STORE" > "$TMP/store_patched.ndjson"
mv "$TMP/store_patched.ndjson" "$STORE"
if [ "$_bf_count" -gt 0 ]; then
    log "weather: backfilled/upgraded temp for $_bf_count activities"
    ADDED=$((ADDED + _bf_count))
fi

# --- 4. Write per-activity detail files -------------------------------------
# activity.html fetches details/{id}.json — for healthsync activities this is
# the store record (with gpx_file), not a Strava API response.
# One jq pass emits "id<TAB>json" per line — avoids one subprocess per record.
_sep="$(printf '\t')"
jq -r '(.id | tostring) + "\t" + tojson' "$STORE" | \
while IFS="$_sep" read -r aid content; do
    detail_file="$DETAIL_DIR/${aid}.json"
    printf '%s\n' "$content" > "$detail_file"
done
unset _sep
log "detail files: $(ls -1 "$DETAIL_DIR" 2>/dev/null | grep -c '\.json$' || echo 0) activities"

else
  log "import disabled (HEALTHSYNC_IMPORT_ENABLED=0) — re-rendering from existing store"
fi
TOTAL="$(wc -l < "$STORE" 2>/dev/null | tr -d ' ' || echo 0)"

# --- 5. Emit activities.json + 6. Render HTML --------------------------------
# Skip when nothing changed: no new activities and bike-assign unchanged
# (no CGI writes since last emit). After deploying new scripts, run manually.
# Also force re-emit when the computed athlete age differs from the stored one
# (changing HEALTHSYNC_BIRTH_YEAR in the config, or on new-year rollover, triggers this).
if [ "$ADDED" -eq 0 ] && [ -f "$WEB_DIR/activities.json" ]; then
    _stored_age="$(jq -r '.athleteAge // "null"' "$WEB_DIR/activities.json" 2>/dev/null || printf 'null')"
    _want_age="${ATHLETE_AGE:-null}"
    [ "$_stored_age" != "$_want_age" ] && ADDED=1
fi
if [ "$ADDED" -eq 0 ] && [ -f "$WEB_DIR/activities.json" ] && \
   [ -f "$WEB_DIR/index.html" ] && \
   [ -f "$BIKE_ASSIGN" ] && [ "$WEB_DIR/activities.json" -nt "$BIKE_ASSIGN" ]; then
    log "no new activities, outputs up-to-date — skipping re-emit"
else
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

[ -f "$BIKE_ASSIGN" ] || printf '{}' > "$BIKE_ASSIGN"
cp "$BIKE_ASSIGN" "$TMP/bike-assign.json"

# gears map: gear_id → {name}.
# Source 1 (store): HealthSync activities — gear_id IS the human bike name.
# Source 2 (Strava detail files): opaque gear_id needs .gear.name lookup.
# Cache source 2 permanently — Strava history is static once imported.
jq -s 'map(select(.gear_id != null) | {(.gear_id): {name:.gear_id}}) | add // {}' \
    "$STORE" > "$TMP/gears.json"
if [ ! -f "$GEARS_CACHE" ] && ls "$DETAIL_DIR"/[0-9]*.json >/dev/null 2>&1; then
    jq -s 'map(.gear | select(. != null and .id != null) | {(.id): {name:(.name // .id)}}) | add // {}' \
        "$DETAIL_DIR"/[0-9]*.json > "$GEARS_CACHE"
    log "built Strava gear name cache"
fi
if [ -f "$GEARS_CACHE" ]; then
    jq -s '.[0] * .[1]' "$TMP/gears.json" "$GEARS_CACHE" > "$TMP/gears-merged.json"
    mv "$TMP/gears-merged.json" "$TMP/gears.json"
fi

jq -s \
    --arg gen "$GENERATED_AT" \
    --arg athleteAge "$ATHLETE_AGE" \
    --slurpfile assigns "$TMP/bike-assign.json" \
    --slurpfile gears "$TMP/gears.json" '
  ($assigns[0] // {}) as $A |
  ($gears[0] // {}) as $G |
  # When Strava history is migrated, the gear cache may contain opaque Strava IDs
  # (e.g. "b12345") whose name equals a HealthSync gear_id key (the human bike
  # name).  Build an alias map and drop the opaque IDs so the bike dropdown does
  # not show the same bike twice.
  ($G | to_entries
      | map(select(.key != .value.name and (.value.name as $n | $G | has($n))))
      | map({(.key): .value.name}) | add // {}) as $ALIAS |
  ($G | with_entries(select($ALIAS[.key] | not))) as $GCLEAN |
  {
    generatedAt: $gen,
    athleteAge: (if $athleteAge == "" then null else ($athleteAge | tonumber) end),
    gears: $GCLEAN,
    activities: [
      .[] |
      ($A[.id | tostring] // .gear_id) as $raw |
      (if $raw != null then ($ALIAS[$raw] // $raw) else null end) as $bike |
      {
        id:                   .id,
        date:                 .date,
        name:                 .name,
        sport_type:           .sport_type,
        gear_id:              $bike,
        distance:             .distance,
        moving_time:          .moving_time,
        elapsed_time:         .elapsed_time,
        total_elevation_gain: .total_elevation_gain,
        average_speed:        .average_speed,
        max_speed:            (.max_speed // 0),
        average_heartrate:    .average_heartrate,
        max_heartrate:        .max_heartrate,
        average_cadence:      null,
        average_watts:        .average_watts,
        kilojoules:           .kilojoules,
        average_temp:         .average_temp,
        suffer_score:         null,
        calories:             .calories,
        gpx_file:             .gpx_file,
        detail:               true
      }
    ] | sort_by(.date) | reverse
  }
' "$STORE" > "$WEB_DIR/activities.json"

log "wrote $WEB_DIR/activities.json ($TOTAL activities)"

# --- 6. Render HTML pages (same helpers as strava-my-activities.sh) ---------
# shellcheck disable=SC1090
. "$LIBDIR/strava-my-html-dashboard.sh"
# shellcheck disable=SC1090
. "$LIBDIR/strava-my-html-detail.sh"
# shellcheck disable=SC1090
. "$LIBDIR/strava-my-html-bike.sh"
# shellcheck disable=SC1090
. "$LIBDIR/strava-my-html-stats.sh"

log "wrote $WEB_DIR/index.html, $WEB_DIR/activity.html, $WEB_DIR/bike.html, $WEB_DIR/stats.html"
fi
log "done."
