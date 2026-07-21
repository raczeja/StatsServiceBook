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
WEATHER_CACHE="$STATE_DIR/weather-cache.json"
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
    [ -n "${LOCAL_DRIVE_DIR:-}" ] && { ACCESS_TOKEN="local"; return 0; }
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
    if ! curl_retry -fsS https://oauth2.googleapis.com/token \
        -d "client_id=$GOOGLE_CLIENT_ID" \
        -d "client_secret=$GOOGLE_CLIENT_SECRET" \
        -d "refresh_token=$GOOGLE_REFRESH_TOKEN" \
        -d "grant_type=refresh_token" \
        -o "$TMP/token.json"; then
        printf '{"ok":false,"error":"Drive token refresh failed","ts":%s}\n' "$(date +%s)" \
            > "$WEB_DIR/drive-status.json" 2>/dev/null || true
        die "Drive token refresh failed"
    fi
    ACCESS_TOKEN="$(jq -r '.access_token // empty' "$TMP/token.json")"
    [ -n "$ACCESS_TOKEN" ] || die "no access_token in Drive response: $(cat "$TMP/token.json")"
    expires_in="$(jq -r '.expires_in // 3600' "$TMP/token.json")"
    jq --argjson exp "$((now + expires_in))" '. + {expires_at: $exp}' \
        "$TMP/token.json" > "$TOKEN_STATE"
    chmod 600 "$TOKEN_STATE"
    log "Drive token refreshed (valid ~${expires_in}s)"
}

ensure_drive_token

# --- 2. List Drive folder (or local test dir when LOCAL_DRIVE_DIR is set) -----
if [ -n "${LOCAL_DRIVE_DIR:-}" ]; then
    log "local mode: reading files from $LOCAL_DRIVE_DIR ..."
    find "$LOCAL_DRIVE_DIR" -maxdepth 1 -type f -exec basename {} \; 2>/dev/null \
        | jq -Rsc '[split("\n")[] | select(length>0) |
                    {id:.,name:.,modifiedTime:"2026-01-01T00:00:00Z"}] | {files:.}' \
        > "$TMP/filelist.json"
    file_count="$(jq '.files | length' "$TMP/filelist.json")"
    log "found $file_count local files"
else
    log "listing Drive folder $DRIVE_FOLDER_ID..."
    QUERY="'${DRIVE_FOLDER_ID}'+in+parents+and+trashed=false"
    curl_retry -fsS \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://www.googleapis.com/drive/v3/files?q=${QUERY}&fields=files(id,name,modifiedTime)&pageSize=1000" \
        -o "$TMP/filelist.json" || die "Drive file listing failed"
    file_count="$(jq '.files | length' "$TMP/filelist.json")"
    log "found $file_count files in Drive folder"
fi

# keepalive mode: token refresh + folder check only; write token status for dashboard
case "${HEALTHSYNC_MODE:-full}" in keepalive)
    _exp="$(jq -r '.expires_at // 0' "$TOKEN_STATE" 2>/dev/null || echo 0)"
    _tok="$(jq -r '.token_type // "Bearer"' "$TOKEN_STATE" 2>/dev/null || echo Bearer)"
    printf '{"ok":true,"expires_at":%s,"token_type":"%s","lastSync":%s,"mode":"keepalive"}\n' \
        "$_exp" "$_tok" "$(date +%s)" > "$WEB_DIR/drive-status.json" 2>/dev/null || true
    log "keepalive done."; exit 0
    ;;
esac

# Build name→id lookup (tab-separated, sorted for grep -F)
jq -r '.files[] | "\(.name)\t\(.id)"' "$TMP/filelist.json" | sort > "$TMP/name_to_id.tsv"

drive_file_id() {
    # Returns the Drive file id for a given filename, or empty string.
    grep -F "$1	" "$TMP/name_to_id.tsv" | cut -f2 | head -1 || true
}

drive_download() {
    fid="$1"; dest="$2"
    if [ -n "${LOCAL_DRIVE_DIR:-}" ]; then
        cp "$LOCAL_DRIVE_DIR/$fid" "$dest" 2>/dev/null || return 1
        return 0
    fi
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
jq -r '.magene_id // empty' "$STORE" 2>/dev/null \
    | grep -v '^$' | sort -u > "$TMP/merged_magene_ids.txt" \
    || : > "$TMP/merged_magene_ids.txt"

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
    avg_hr="null"; max_hr="null"; calories="null"; avg_watts_v="null"; kj_v="null"; avg_cad_v="null"
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
        # Cadence from TCX: lap-level summary first, then average of trackpoints.
        # Cycling uses <AverageCadence>; running uses namespace-prefixed AvgRunCadence/RunCadence.
        _cad="$(grep -o '<AverageCadence>[0-9]*</AverageCadence>' "$TMP/activity.tcx" \
            | head -1 | grep -o '[0-9]*</AverageCadence>' | grep -o '^[0-9]*' || true)"
        if [ -z "$_cad" ]; then
            _cad="$(grep -o 'AvgRunCadence>[0-9]*' "$TMP/activity.tcx" \
                | head -1 | grep -o '[0-9]*$' || true)"
        fi
        if [ -z "$_cad" ]; then
            _cad="$(grep -o '<Cadence>[0-9]*</Cadence>' "$TMP/activity.tcx" \
                | grep -o '[0-9]*</Cadence>' | grep -o '^[0-9]*' \
                | jq -Rn '[inputs | tonumber] | if length>0 then (add/length | round) else empty end' \
                2>/dev/null || true)"
        fi
        if [ -z "$_cad" ]; then
            _cad="$(grep -o 'RunCadence>[0-9]*' "$TMP/activity.tcx" \
                | grep -o '[0-9]*$' \
                | jq -Rn '[inputs | tonumber] | if length>0 then (add/length | round) else empty end' \
                2>/dev/null || true)"
        fi
        [ -n "$_cad" ] && avg_cad_v="$_cad"
        _tt1="$(grep -o '<Time>[0-9T:Z.-]*</Time>' "$TMP/activity.tcx" | head -1 \
            | cut -d'>' -f2 | cut -d'<' -f1 || true)"
        [ -n "$_tt1" ] && _tt1="$(printf '%s' "$_tt1" | cut -d'.' -f1 | tr -d 'Z')Z"
        [ -n "$_tt1" ] && act_start="$_tt1"
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
        # Cadence from GPX trackpoint extensions (<gpxtpx:cad>) — fallback when TCX absent.
        if [ "$avg_cad_v" = "null" ]; then
            _cad="$(grep -o ':cad>[0-9]*' "$gpx_local" \
                | grep -o '[0-9]*$' \
                | jq -Rn '[inputs | tonumber] | if length>0 then (add/length | round) else null end' \
                2>/dev/null || echo null)"
            [ "$_cad" != "null" ] && avg_cad_v="$_cad"
        fi
        _gt1="$(grep -o '<time>[0-9T:Z.-]*</time>' "$gpx_local" | head -1 \
            | cut -d'>' -f2 | cut -d'<' -f1 || true)"
        [ -n "$_gt1" ] && _gt1="$(printf '%s' "$_gt1" | cut -d'.' -f1 | tr -d 'Z')Z"
        [ -n "$_gt1" ] && act_start="$_gt1"
    fi

    case "$sport_type" in
        Ride|EBikeRide|VirtualRide|Handcycle|MountainBikeRide|GravelRide)
            gear_id="\"$DEFAULT_BIKE_NAME\"" ;;
        *) gear_id="null" ;;
    esac

    # Weather: extract start lat/lon from GPX first trackpoint, fall back to config
    _w_lat="" _w_lon="" _w_temp="null" _w_temp_src="null"
    _w_apparent_temp="null" _w_wind_speed="null" _w_wind_dir="null" _w_weathercode="null" _w_precipitation="null"
    if [ -n "$gpx_local" ] && [ -f "$gpx_local" ]; then
        _w_lat=$(grep '<trkpt' "$gpx_local" | head -n1 | grep -o 'lat="[^"]*"' | cut -d'"' -f2 | head -n1 || true)
        _w_lon=$(grep '<trkpt' "$gpx_local" | head -n1 | grep -o 'lon="[^"]*"' | cut -d'"' -f2 | head -n1 || true)
    fi
    [ -z "$_w_lat" ] && _w_lat="${WEATHER_LAT:-}"
    [ -z "$_w_lon" ] && _w_lon="${WEATHER_LON:-}"
    if [ -n "$_w_lat" ] && [ -n "$_w_lon" ]; then
        _fw_temp_source="" _fw_apparent_temp="" _fw_wind_speed="" _fw_wind_dir="" _fw_weathercode="" _fw_precipitation=""
        _t=$(fetch_weather_temp "$_w_lat" "$_w_lon" "$act_date" || true)
        if [ -n "$_t" ]; then
            _w_temp="$_t"
            _w_temp_src="\"$_fw_temp_source\""
            [ -n "$_fw_apparent_temp" ] && _w_apparent_temp="$_fw_apparent_temp"
            [ -n "$_fw_wind_speed"    ] && _w_wind_speed="$_fw_wind_speed"
            [ -n "$_fw_wind_dir"      ] && _w_wind_dir="$_fw_wind_dir"
            [ -n "$_fw_weathercode"   ] && _w_weathercode="$_fw_weathercode"
            [ -n "$_fw_precipitation" ] && _w_precipitation="$_fw_precipitation"
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
        --argjson apparent_temp "$_w_apparent_temp" \
        --argjson wind_speed   "$_w_wind_speed" \
        --argjson wind_dir     "$_w_wind_dir" \
        --argjson weathercode  "$_w_weathercode" \
        --argjson precipitation "$_w_precipitation" \
        --argjson kj           "$kj_v" \
        --argjson avg_cad      "$avg_cad_v" \
        '{id:$id, date:$date, start_date:$start_date, start_date_local:$start_date,
          name:$name, sport_type:$sport_type, gear_id:$gear_id,
          distance:$distance,
          moving_time:($moving_time|tonumber), elapsed_time:($elapsed_time|tonumber),
          total_elevation_gain:$elevation, average_speed:$avg_speed, max_speed:$max_speed,
          average_heartrate:$avg_hr, max_heartrate:$max_hr,
          average_cadence:$avg_cad, average_watts:$avg_watts, kilojoules:$kj,
          average_temp:$avg_temp, temp_source:$temp_src,
          apparent_temp:$apparent_temp, wind_speed:$wind_speed, wind_dir:$wind_dir,
          weathercode:$weathercode, precipitation:$precipitation,
          suffer_score:null, calories:$calories, gpx_file:$gpx_file, dual_source:false}' >> "$STORE"

    printf '%s\n' "$act_id" >> "$TMP/known_ids.txt"
    ADDED=$((ADDED + 1))
done < "$TMP/activity_bases.txt"

# --- 3a. Cycling watch index for Magene dual-source detection ----------------
# One TSV row per non-merged cycling watch activity: id TAB start_epoch TAB end_epoch.
: > "$TMP/cycling_watch_index.tsv"
if [ "${HEALTHSYNC_MODE:-full}" = "full" ] && [ -f "$STORE" ]; then
    jq -r 'select(
        (.sport_type == "Ride" or .sport_type == "MountainBikeRide" or
         .sport_type == "GravelRide" or .sport_type == "EBikeRide") and
        (.dual_source | not) and (.start_date != null)
    ) | [.id,
          (.start_date | .[0:19] + "Z" | fromdateiso8601 | floor | tostring),
          ((.start_date | .[0:19] + "Z" | fromdateiso8601) + (.elapsed_time // .moving_time // 0) | floor | tostring)
         ] | join("\t")' \
        "$STORE" 2>/dev/null >> "$TMP/cycling_watch_index.tsv" || true
    log "cycling index: $(wc -l < "$TMP/cycling_watch_index.tsv" | tr -d ' ') ride(s) indexed"
fi

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
                drive_download "$_mfid" "$TMP/magene.fit" \
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

TOTAL="$(wc -l < "$STORE" | tr -d ' ')"
log "store: +$ADDED new, $TOTAL total"

# Seed weather cache from store records that already have full weather data,
# then run the shared backfill (null-temp, enrichment, forecast→archive upgrade),
# then apply any cache changes back to store records.
log "weather: seeding cache from store..."
[ -f "$WEATHER_CACHE" ] || printf '{}' > "$WEATHER_CACHE"
jq -sc 'map(select(.average_temp != null and .wind_speed != null) |
    {(.id|tostring): {t:.average_temp, s:(.temp_source // "device"),
                      at:.apparent_temp, ws:.wind_speed, wd:.wind_dir,
                      wc:.weathercode,  pr:.precipitation}}) |
    add // {}' "$STORE" > "$TMP/wc_from_store.json"
jq -s '.[0] + .[1]' "$TMP/wc_from_store.json" "$WEATHER_CACHE" > "$WEATHER_CACHE.tmp" \
    && mv "$WEATHER_CACHE.tmp" "$WEATHER_CACHE"

run_weather_backfill "$STORE" "$WEATHER_CACHE" "$TMP" "$DETAIL_DIR" "$WEB_DIR"

jq -c --slurpfile wc "$WEATHER_CACHE" '
  . as $r |
  ($wc[0][.id|tostring]) as $c |
  if ($c | type) != "object" then .
  elif $r.average_temp == null and ($c.t != null) then
    . + {average_temp:$c.t, temp_source:$c.s,
         apparent_temp:($c.at//null), wind_speed:($c.ws//null),
         wind_dir:($c.wd//null), weathercode:($c.wc//null), precipitation:($c.pr//null)}
  elif $r.temp_source == "forecast" and $c.s == "archive" and ($c.t != null) then
    . + {average_temp:$c.t, temp_source:"archive",
         apparent_temp:($c.at//null), wind_speed:($c.ws//null),
         wind_dir:($c.wd//null), weathercode:($c.wc//null), precipitation:($c.pr//null)}
  elif $r.wind_speed == null and ($c.ws != null) then
    . + {apparent_temp:($c.at//null), wind_speed:$c.ws,
         wind_dir:($c.wd//null), weathercode:($c.wc//null), precipitation:($c.pr//null)}
  else . end
' "$STORE" > "$TMP/store_weather.ndjson" \
    && mv "$TMP/store_weather.ndjson" "$STORE"
if [ "${_rw_changed:-0}" -gt 0 ]; then
    log "weather: backfilled/upgraded ${_rw_changed} activities"
    ADDED=$((ADDED + _rw_changed))
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
        temp_source:          .temp_source,
        apparent_temp:        .apparent_temp,
        wind_speed:           .wind_speed,
        wind_dir:             .wind_dir,
        weathercode:          .weathercode,
        precipitation:        .precipitation,
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

# --- 7. Drive auth status + re-authorization CGI ----------------------------
# Write success status (with token expiry + sync time) so the dashboard can show Drive info.
if [ "$IMPORT_ENABLED" != "0" ]; then
    _exp="$(jq -r '.expires_at // 0' "$TOKEN_STATE" 2>/dev/null || echo 0)"
    _tok="$(jq -r '.token_type // "Bearer"' "$TOKEN_STATE" 2>/dev/null || echo Bearer)"
    printf '{"ok":true,"expires_at":%s,"token_type":"%s","lastSync":%s,"mode":"full"}\n' \
        "$_exp" "$_tok" "$(date +%s)" > "$WEB_DIR/drive-status.json" 2>/dev/null || true
fi

# Generate the drive-auth CGI (device authorization flow). Idempotent.
# Users visit /cgi-bin/drive-auth to get a new refresh token when the old one
# expires (apps in Google "Testing" status expire after 7 days of inactivity).
{
    printf '#!/bin/sh\n'
    printf 'CONFIG="%s"\n' "$CONFIG"
    printf 'STATE_DIR="%s"\n' "$STATE_DIR"
    printf 'WEB_DIR="%s"\n' "$WEB_DIR"
    cat <<'CGI'
# shellcheck disable=SC1090
. "$CONFIG" 2>/dev/null || {
    printf 'Content-Type: text/html\r\n\r\n'
    printf '<!doctype html><html><body><p>Cannot read config: %s</p></body></html>\n' "$CONFIG"
    exit 0
}

DC_FILE="$STATE_DIR/drive-device-code.json"

if [ "${QUERY_STRING:-}" = "poll" ]; then
    printf 'Content-Type: application/json\r\nCache-Control: no-cache\r\n\r\n'
    if [ ! -f "$DC_FILE" ]; then
        printf '{"status":"error","msg":"no_pending_auth"}\n'; exit 0
    fi
    dc="$(jq -r '.device_code // empty' "$DC_FILE" 2>/dev/null || true)"
    if [ -z "$dc" ]; then
        rm -f "$DC_FILE"; printf '{"status":"error","msg":"bad_state"}\n'; exit 0
    fi
    r="$(curl -fsS --max-time 15 https://oauth2.googleapis.com/token \
        -d "client_id=$GOOGLE_CLIENT_ID" -d "client_secret=$GOOGLE_CLIENT_SECRET" \
        -d "device_code=$dc" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" 2>/dev/null || true)"
    err="$(printf '%s' "$r" | jq -r '.error // empty' 2>/dev/null || true)"
    rt="$(printf '%s' "$r" | jq -r '.refresh_token // empty' 2>/dev/null || true)"
    if [ -n "$rt" ]; then
        tmp="$(mktemp)"
        sed "s|^GOOGLE_REFRESH_TOKEN=.*|GOOGLE_REFRESH_TOKEN=\"$rt\"|" "$CONFIG" > "$tmp" \
            && mv "$tmp" "$CONFIG" && chmod 600 "$CONFIG"
        printf '{"ok":true}\n' > "$WEB_DIR/drive-status.json"
        rm -f "$DC_FILE"
        printf '{"status":"ok"}\n'
    elif [ "$err" = "authorization_pending" ] || [ "$err" = "slow_down" ]; then
        printf '{"status":"pending"}\n'
    elif [ "$err" = "expired_token" ]; then
        rm -f "$DC_FILE"; printf '{"status":"expired"}\n'
    else
        e="$(printf '%s' "$err" | sed 's/["\]/\\&/g')"
        printf '{"status":"error","msg":"%s"}\n' "$e"
    fi
    exit 0
fi

# Start device authorization flow
mkdir -p "$STATE_DIR" 2>/dev/null || true
dc_resp="$(curl -fsS --max-time 15 https://accounts.google.com/o/oauth2/device/code \
    -d "client_id=$GOOGLE_CLIENT_ID" \
    -d "scope=https://www.googleapis.com/auth/drive.readonly" 2>/dev/null || true)"
user_code="$(printf '%s' "$dc_resp" | jq -r '.user_code // empty' 2>/dev/null || true)"
verify_url="$(printf '%s' "$dc_resp" | jq -r '.verification_url // empty' 2>/dev/null || true)"
expires_in="$(printf '%s' "$dc_resp" | jq -r '.expires_in // 300' 2>/dev/null || echo 300)"

printf 'Content-Type: text/html\r\nCache-Control: no-cache\r\n\r\n'

if [ -z "$user_code" ]; then
    printf '<!doctype html><html lang="en"><body><h2>Authorization Error</h2>'
    printf '<p>Could not request a device code from Google. Check GOOGLE_CLIENT_ID in config.</p>'
    printf '</body></html>\n'
    exit 0
fi

printf '%s\n' "$dc_resp" > "$DC_FILE"

cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Authorize Google Drive</title>
<style>
body{font-family:system-ui,Arial,sans-serif;max-width:520px;margin:3rem auto;padding:0 1.5rem;color:#222}
h1{font-size:1.35rem;margin:0 0 .75rem}
.code{display:block;font-size:2.2rem;font-weight:700;letter-spacing:.25em;background:#f5f5f5;border:2px solid #ddd;border-radius:.5rem;padding:.6rem 1rem;margin:.5rem 0 1rem;font-family:monospace;text-align:center}
.openBtn{display:inline-block;background:#4285f4;color:#fff;padding:.5rem 1.2rem;border-radius:.4rem;text-decoration:none;font-weight:600;font-size:.95rem}
.openBtn:hover{background:#3367d6}
.note{color:#666;font-size:.88rem;margin:1rem 0}
#status{font-size:.9rem;margin:1rem 0;min-height:1.2em;color:#555}
.ok{color:#2a7d2e;font-weight:600;font-size:1rem}
</style>
</head>
<body>
<h1>Re-authorize Google Drive</h1>
HTML
printf '<p>1. Open <a href="%s" target="_blank" class="openBtn">Google Device Auth</a></p>\n' "$verify_url"
printf '<p>2. Enter this code when prompted:</p>\n<code class="code">%s</code>\n' "$user_code"
printf '<p class="note">Code expires in <span id="timer">%s</span>s &mdash; this page polls automatically.</p>\n' "$expires_in"
printf '<div id="status">Waiting for authorization...</div>\n'
cat <<'HTML'
<script>
var exp=parseInt(document.getElementById("timer").textContent,10)||300;
var tiv=setInterval(function(){
  exp--;document.getElementById("timer").textContent=exp;
  if(exp<=0){clearInterval(tiv);clearInterval(piv);document.getElementById("status").textContent="Code expired. Reload to start over.";}
},1000);
function poll(){
  fetch("drive-auth?poll",{cache:"no-store"})
    .then(function(r){return r.ok?r.json():{status:"error"};})
    .then(function(d){
      if(d.status==="ok"){
        clearInterval(tiv);clearInterval(piv);
        document.getElementById("status").innerHTML='<span class="ok">&#10003; Authorized! Redirecting to dashboard...</span>';
        setTimeout(function(){window.location="/strava/me/";},1500);
      }else if(d.status==="expired"){
        clearInterval(tiv);clearInterval(piv);
        document.getElementById("status").textContent="Code expired. Reload to start over.";
      }
    })
    .catch(function(){});
}
var piv=setInterval(poll,5000);
</script>
</body>
</html>
HTML
CGI
} > "$CGI_DIR/drive-auth"
chmod 0755 "$CGI_DIR/drive-auth"
log "wrote $CGI_DIR/drive-auth"
log "done."
