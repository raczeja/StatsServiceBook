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

command -v curl >/dev/null 2>&1 || die "curl not installed (opkg install curl ca-bundle)"
command -v jq   >/dev/null 2>&1 || die "jq not installed (opkg install jq)"

GPX_DIR="$WEB_DIR/gpx"
DETAIL_DIR="$WEB_DIR/details"
STORE="$STATE_DIR/activities.ndjson"
TOKEN_STATE="$STATE_DIR/gdrive-token.json"

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
fi

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
    curl -fsS https://oauth2.googleapis.com/token \
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
curl -fsS \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://www.googleapis.com/drive/v3/files?q=${QUERY}&fields=files(id,name,modifiedTime)&pageSize=1000" \
    -o "$TMP/filelist.json" || die "Drive file listing failed"
file_count="$(jq '.files | length' "$TMP/filelist.json")"
log "found $file_count files in Drive folder"

# Build name→id lookup (tab-separated, sorted for grep -F)
jq -r '.files[] | "\(.name)\t\(.id)"' "$TMP/filelist.json" | sort > "$TMP/name_to_id.tsv"

drive_file_id() {
    # Returns the Drive file id for a given filename, or empty string.
    grep -F "$1	" "$TMP/name_to_id.tsv" | cut -f2 | head -1 || true
}

drive_download() {
    fid="$1"; dest="$2"
    curl -fsS -L \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://www.googleapis.com/drive/v3/files/${fid}?alt=media" \
        -o "$dest"
}

# --- 3. Process new activity files ------------------------------------------
# One CSV per activity; matching TCX (HR/calories) and GPX (map/elevation) are
# downloaded and cached alongside. Activity IDs are derived from the filename
# since healthsync exports carry no Strava-style numeric ID.
[ -f "$STORE" ] || : > "$STORE"
jq -r '.id' "$STORE" 2>/dev/null | sort > "$TMP/known_ids.txt" || : > "$TMP/known_ids.txt"

ADDED=0


# Match both filename formats HealthSync uses:
#   Old: "{TYPE} {YYYY.MM.DD} {HH.MM}.csv"   e.g. "WALKING 2026.06.22 20.01.csv"
#   New: "{YYYY.MM.DD} {HH.MM}-{TYPE}.csv"   e.g. "2026.06.22 15.07-WALKING.csv"
#        (new format without extension:       e.g. "2026.06.22 15.07-WALKING")
# The date-first regex requires end-of-string ($) so it does not match .kml/.gpx/.tcx
# files that share the same naming pattern but carry no summary data.
jq -r '.files[] | select(
    (.name | endswith(".csv")) or
    (.name | test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2} [0-9]{2}\\.[0-9]{2}-[A-Z_]+$"))
) | "\(.id)\t\(.name)"' \
    "$TMP/filelist.json" > "$TMP/csv_files.tsv"
log "CSV files found: $(wc -l < "$TMP/csv_files.tsv" | tr -d ' ')"

while IFS='	' read -r file_id filename; do
    [ -n "$file_id" ] || continue

    # Strip .csv suffix if present, then detect which format:
    #   Old (type-first):  "WALKING 2026.06.22 20.01"
    #   New (date-first):  "2026.06.22 15.07-WALKING"
    base="$(basename "$filename" .csv)"
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

    drive_download "$file_id" "$TMP/activity.csv" \
        || { log "WARN: failed to download CSV for $act_id"; continue; }

    # Skip header row; columns: source_app,type,name,date,time,elapsed_s,active_s,dist_km
    # Strip \r so CRLF exports from the Android app don't leave a trailing \r on the
    # last field, which would break jq's tonumber on csv_dist_km.
    csv_data="$(tail -n +2 "$TMP/activity.csv" | head -1 | tr -d '\r')"
    [ -n "$csv_data" ] || { log "WARN: empty CSV for $act_id"; continue; }

    csv_datetime="$(printf '%s' "$csv_data" | cut -d, -f4)"  # 2026.06.22 20:01:42
    csv_elapsed="$(printf '%s' "$csv_data" | cut -d, -f6)"   # elapsed seconds
    csv_active="$(printf '%s' "$csv_data" | cut -d, -f7)"    # active seconds
    csv_dist_km="$(printf '%s' "$csv_data" | cut -d, -f8)"   # distance in km

    act_date="$(printf '%s' "$csv_datetime" | cut -d' ' -f1 | tr '.' '-')"
    act_time="$(printf '%s' "$csv_datetime" | cut -d' ' -f2)"
    act_start="${act_date}T${act_time}Z"

    distance_m="$(printf '%s' "$csv_dist_km" | jq -Rr 'tonumber * 1000 | round')"
    avg_speed="$(jq -n --arg d "$distance_m" --arg t "$csv_active" \
        'if ($t|tonumber)>0 then ($d|tonumber)/($t|tonumber) else 0 end')"

    case "$activity_type" in
        WALKING|NORDIC_WALKING) sport_type="Walk" ;;
        RUNNING)                sport_type="Run" ;;
        CYCLING|BIKING|INDOOR_CYCLING|E_BIKING) sport_type="Ride" ;;
        SWIMMING)               sport_type="Swim" ;;
        HIKING)                 sport_type="Hike" ;;
        *)                      sport_type="$activity_type" ;;
    esac

    # TCX: extract HR + calories using grep -o (compact XML, no xmllint needed)
    tcx_name="${date_part} ${time_part}-${activity_type}.tcx"
    avg_hr="null"; max_hr="null"; calories="null"
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
    fi

    # GPX: cache locally + compute elevation gain
    # Elevation chars removed by tr: <, e, l, > and / — none appear in numeric values.
    gpx_name="${date_part} ${time_part}-${activity_type}.gpx"
    gpx_safe="$(printf '%s' "$gpx_name" | tr ' ' '_')"
    gpx_local="$GPX_DIR/$gpx_safe"
    gpx_ref="null"; elevation_gain=0

    gpx_id="$(drive_file_id "$gpx_name")"
    if [ -n "$gpx_id" ] && drive_download "$gpx_id" "$gpx_local" 2>/dev/null; then
        gpx_ref="\"gpx/$gpx_safe\""
        elevation_gain="$(grep -o '<ele>[0-9.]*</ele>' "$gpx_local" \
            | tr -d '<el>/' \
            | jq -Rn '[inputs | tonumber] as $e |
                reduce range(1; $e|length) as $i (
                    0; . + (if $e[$i] > $e[$i-1] then $e[$i] - $e[$i-1] else 0 end)
                ) | round' 2>/dev/null || echo 0)"
    fi

    case "$sport_type" in
        Ride|EBikeRide|VirtualRide|Handcycle|MountainBikeRide|GravelRide)
            gear_id="\"$DEFAULT_BIKE_NAME\"" ;;
        *) gear_id="null" ;;
    esac

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
        '{id:$id, date:$date, start_date:$start_date, start_date_local:$start_date,
          name:$name, sport_type:$sport_type, gear_id:$gear_id,
          distance:$distance,
          moving_time:($moving_time|tonumber), elapsed_time:($elapsed_time|tonumber),
          total_elevation_gain:$elevation, average_speed:$avg_speed, max_speed:0,
          average_heartrate:$avg_hr, max_heartrate:$max_hr,
          average_cadence:null, average_watts:null, kilojoules:null,
          average_temp:null, suffer_score:null,
          calories:$calories, gpx_file:$gpx_file}' >> "$STORE"

    ADDED=$((ADDED + 1))
done < "$TMP/csv_files.tsv"

TOTAL="$(wc -l < "$STORE" | tr -d ' ')"
log "store: +$ADDED new, $TOTAL total"

# --- 4. Write per-activity detail files -------------------------------------
# activity.html fetches details/{id}.json — for healthsync activities this is
# the store record (with gpx_file), not a Strava API response.
while IFS= read -r line; do
    aid="$(printf '%s' "$line" | jq -r '.id | tostring')"
    detail_file="$DETAIL_DIR/${aid}.json"
    [ -f "$detail_file" ] || printf '%s\n' "$line" > "$detail_file"
done < "$STORE"
log "detail files: $(ls -1 "$DETAIL_DIR" 2>/dev/null | grep -c '\.json$' || echo 0) activities"

else
  log "import disabled (HEALTHSYNC_IMPORT_ENABLED=0) — re-rendering from existing store"
fi
TOTAL="$(wc -l < "$STORE" 2>/dev/null | tr -d ' ' || echo 0)"

# --- 5. Emit activities.json ------------------------------------------------
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

[ -f "$BIKE_ASSIGN" ] || printf '{}' > "$BIKE_ASSIGN"
cp "$BIKE_ASSIGN" "$TMP/bike-assign.json"

# gears map: gear_id → {name}.
# Source 1 (store): HealthSync native activities — gear_id IS the human bike name.
# Source 2 (detail files): Strava activities — gear_id is opaque (b16239154);
# detail JSON carries .gear.id + .gear.name. Source 2 overrides source 1.
jq -s 'map(select(.gear_id != null) | {(.gear_id): {name:.gear_id}}) | add // {}' \
    "$STORE" > "$TMP/gears.json"
if ls "$DETAIL_DIR"/*.json >/dev/null 2>&1; then
    jq -s 'map(.gear | select(. != null and .id != null) | {(.id): {name:(.name // .id)}}) | add // {}' \
        "$DETAIL_DIR"/*.json > "$TMP/gears-detail.json"
    jq -s '.[0] * .[1]' "$TMP/gears.json" "$TMP/gears-detail.json" > "$TMP/gears-merged.json"
    mv "$TMP/gears-merged.json" "$TMP/gears.json"
fi

jq -s \
    --arg gen "$GENERATED_AT" \
    --slurpfile assigns "$TMP/bike-assign.json" \
    --slurpfile gears "$TMP/gears.json" '
  ($assigns[0] // {}) as $A |
  ($gears[0] // {}) as $G |
  {
    generatedAt: $gen,
    gears: $G,
    activities: [
      .[] |
      ($A[.id | tostring] // .gear_id) as $bike |
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
        max_speed:            0,
        average_heartrate:    .average_heartrate,
        max_heartrate:        .max_heartrate,
        average_cadence:      null,
        average_watts:        null,
        kilojoules:           null,
        average_temp:         null,
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
log "done."
