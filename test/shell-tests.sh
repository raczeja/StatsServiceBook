#!/bin/sh
# shell-tests.sh — unit tests for shell script logic
#
# Tests the core algorithms from healthsync-activities.sh and strava-lib.sh
# without needing network access, OAuth credentials, or a real router.
# Run inside the Alpine container (needs jq):
#   docker exec <container> sh /opt/shell-tests.sh
#   docker exec <container> sh /opt/shell-tests.sh --junit /tmp/shell-tests.xml
# Exits 0 on all pass, 1 on any failure.

set -eu

JUNIT_OUT=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --junit) JUNIT_OUT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

PASS=0; FAIL=0
TMP="$(mktemp -d)"
RESULTS="$TMP/results.tsv"   # suite TAB name TAB ok|fail TAB message
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

_xml_escape() {
    printf '%s' "$1" \
        | sed -e 's/&/\&amp;/g' \
              -e 's/</\&lt;/g' \
              -e 's/>/\&gt;/g' \
              -e 's/"/\&quot;/g'
}

ok() {
    PASS=$((PASS + 1))
    printf '%s\t%s\tok\t\n' "$1" "$2" >> "$RESULTS"
    printf '  PASS  %s / %s\n' "$1" "$2"
}

err() {
    FAIL=$((FAIL + 1))
    printf '%s\t%s\tfail\t%s\n' "$1" "$2" "$3" >> "$RESULTS"
    printf '  FAIL  %s / %s: %s\n' "$1" "$2" "$3"
}

assert_eq() {
    if [ "$3" = "$4" ]; then
        ok "$1" "$2"
    else
        err "$1" "$2" "expected \"$4\", got \"$3\""
    fi
}

# ── activity-id-generation ────────────────────────────────────────────────────
# Same logic as the `while IFS= read -r base` loop in healthsync-activities.sh.
S="activity-id-generation"

_make_id() {
    base="$1"
    case "$base" in
        [0-9]*)
            date_part="$(printf '%s' "$base" | cut -d' ' -f1)"
            rest="$(printf '%s' "$base" | cut -d' ' -f2)"
            time_part="$(printf '%s' "$rest" | cut -d'-' -f1)"
            activity_type="$(printf '%s' "$rest" | cut -d'-' -f2-)"
            ;;
        *)
            activity_type="$(printf '%s' "$base" | cut -d' ' -f1)"
            date_part="$(printf '%s' "$base" | cut -d' ' -f2)"
            time_part="$(printf '%s' "$base" | cut -d' ' -f3)"
            ;;
    esac
    type_lower="$(printf '%s' "$activity_type" | tr '[:upper:]' '[:lower:]')"
    printf '%s-%s-%s' "$date_part" "$time_part" "$type_lower" | tr '.' '-'
}

assert_eq "$S" "new-format-walking"  "$(_make_id '2026.06.22 15.07-WALKING')"        "2026-06-22-15-07-walking"
assert_eq "$S" "new-format-cycling"  "$(_make_id '2026.06.22 10.30-CYCLING')"        "2026-06-22-10-30-cycling"
assert_eq "$S" "new-format-running"  "$(_make_id '2026.05.01 08.00-RUNNING')"        "2026-05-01-08-00-running"
assert_eq "$S" "old-format-walking"  "$(_make_id 'WALKING 2026.06.22 20.01')"        "2026-06-22-20-01-walking"
assert_eq "$S" "old-format-running"  "$(_make_id 'RUNNING 2025.11.03 08.15')"        "2025-11-03-08-15-running"
assert_eq "$S" "old-format-cycling"  "$(_make_id 'CYCLING 2025.08.14 07.45')"        "2025-08-14-07-45-cycling"
assert_eq "$S" "old-format-nordic"   "$(_make_id 'NORDIC_WALKING 2026.05.10 09.30')" "2026-05-10-09-30-nordic_walking"
assert_eq "$S" "new-format-ebike"    "$(_make_id '2026.04.03 12.00-E_BIKING')"       "2026-04-03-12-00-e_biking"

# ── sport-type-mapping ────────────────────────────────────────────────────────
# Mirrors the case block in healthsync-activities.sh.
S="sport-type-mapping"

_sport() {
    activity_type="$1"
    case "$activity_type" in
        WALKING|NORDIC_WALKING) printf 'Walk' ;;
        RUNNING)                printf 'Run' ;;
        CYCLING|BIKING|INDOOR_CYCLING|E_BIKING) printf 'Ride' ;;
        SWIMMING)               printf 'Swim' ;;
        HIKING)                 printf 'Hike' ;;
        *)                      printf '%s' "$activity_type" ;;
    esac
}

assert_eq "$S" "WALKING"             "$(_sport WALKING)"         "Walk"
assert_eq "$S" "NORDIC_WALKING"      "$(_sport NORDIC_WALKING)"  "Walk"
assert_eq "$S" "RUNNING"             "$(_sport RUNNING)"         "Run"
assert_eq "$S" "CYCLING"             "$(_sport CYCLING)"         "Ride"
assert_eq "$S" "BIKING"              "$(_sport BIKING)"          "Ride"
assert_eq "$S" "INDOOR_CYCLING"      "$(_sport INDOOR_CYCLING)"  "Ride"
assert_eq "$S" "E_BIKING"            "$(_sport E_BIKING)"        "Ride"
assert_eq "$S" "SWIMMING"            "$(_sport SWIMMING)"        "Swim"
assert_eq "$S" "HIKING"              "$(_sport HIKING)"          "Hike"
assert_eq "$S" "unknown-passthrough" "$(_sport YOGA)"            "YOGA"

# ── ndjson-deduplication ──────────────────────────────────────────────────────
# Mirrors the known-ID check and Strava import loop in healthsync-activities.sh.
S="ndjson-deduplication"

printf '%s\n' \
    '{"id":"2026-06-22-15-07-walking","sport_type":"Walk"}' \
    '{"id":"2026-06-22-10-30-cycling","sport_type":"Ride"}' \
    > "$TMP/store.ndjson"
jq -r '.id' "$TMP/store.ndjson" | sort > "$TMP/known_ids.txt"

if grep -qxF "2026-06-22-15-07-walking" "$TMP/known_ids.txt"; then
    ok "$S" "known-id-detected"
else
    err "$S" "known-id-detected" "existing ID not found in known_ids"
fi

if grep -qxF "2026-07-01-08-00-running" "$TMP/known_ids.txt"; then
    err "$S" "new-id-not-in-known" "new ID was incorrectly found in known_ids"
else
    ok "$S" "new-id-not-in-known"
fi

printf '%s\n' \
    '{"id":"18784255013","sport_type":"Ride","distance":64000}' \
    '{"id":"99999999999","sport_type":"Run","distance":5000}' \
    > "$TMP/strava-store.ndjson"

printf '%s\n' '{"id":"18784255013","sport_type":"Ride"}' > "$TMP/hs-store.ndjson"
jq -r '.id | tostring' "$TMP/hs-store.ndjson" > "$TMP/hs-ids.txt"

imported=0
while IFS= read -r line; do
    aid="$(printf '%s' "$line" | jq -r '.id | tostring' 2>/dev/null)" || continue
    [ -z "$aid" ] && continue
    grep -qxF "$aid" "$TMP/hs-ids.txt" && continue
    printf '%s\n' "$line" >> "$TMP/hs-store.ndjson"
    printf '%s\n' "$aid" >> "$TMP/hs-ids.txt"
    imported=$((imported + 1))
done < "$TMP/strava-store.ndjson"

assert_eq "$S" "strava-import-count" "$imported" "1"

if grep -qF '"id":"99999999999"' "$TMP/hs-store.ndjson"; then
    ok "$S" "strava-import-new-in-store"
else
    err "$S" "strava-import-new-in-store" "new ID not written to store"
fi

dupe_count="$(grep -c '"id":"18784255013"' "$TMP/hs-store.ndjson" || true)"
assert_eq "$S" "strava-no-duplicate" "$dupe_count" "1"

# Cross-format deduplication within a single run: old-format (TYPE YYYY.MM.DD
# HH.MM) and new-format (YYYY.MM.DD HH.MM-TYPE) filenames for the same activity
# produce identical IDs. The fix appends each new ID to known_ids.txt so the
# second base name is skipped in the same pass.
_process_base() {
    base="$1"; store="$2"; known="$3"
    case "$base" in
        [0-9]*)
            date_part="$(printf '%s' "$base" | cut -d' ' -f1)"
            rest="$(printf '%s' "$base" | cut -d' ' -f2)"
            time_part="$(printf '%s' "$rest" | cut -d'-' -f1)"
            activity_type="$(printf '%s' "$rest" | cut -d'-' -f2-)"
            ;;
        *)
            activity_type="$(printf '%s' "$base" | cut -d' ' -f1)"
            date_part="$(printf '%s' "$base" | cut -d' ' -f2)"
            time_part="$(printf '%s' "$base" | cut -d' ' -f3)"
            ;;
    esac
    type_lower="$(printf '%s' "$activity_type" | tr '[:upper:]' '[:lower:]')"
    act_id="$(printf '%s-%s-%s' "$date_part" "$time_part" "$type_lower" | tr '.' '-')"
    if grep -qxF "$act_id" "$known" 2>/dev/null; then
        return 0
    fi
    printf '{"id":"%s","sport_type":"Ride"}\n' "$act_id" >> "$store"
    printf '%s\n' "$act_id" >> "$known"
}

S="cross-format-deduplication"

: > "$TMP/xf_store.ndjson"
: > "$TMP/xf_known.txt"
_process_base "CYCLING 2026.06.28 15.30" "$TMP/xf_store.ndjson" "$TMP/xf_known.txt"
_process_base "2026.06.28 15.30-CYCLING" "$TMP/xf_store.ndjson" "$TMP/xf_known.txt"
assert_eq "$S" "old-then-new-no-dupe" \
    "$(wc -l < "$TMP/xf_store.ndjson" | tr -d ' ')" "1"

: > "$TMP/xf_store.ndjson"
: > "$TMP/xf_known.txt"
_process_base "2026.06.28 15.30-CYCLING" "$TMP/xf_store.ndjson" "$TMP/xf_known.txt"
_process_base "CYCLING 2026.06.28 15.30" "$TMP/xf_store.ndjson" "$TMP/xf_known.txt"
assert_eq "$S" "new-then-old-no-dupe" \
    "$(wc -l < "$TMP/xf_store.ndjson" | tr -d ' ')" "1"

: > "$TMP/xf_store.ndjson"
: > "$TMP/xf_known.txt"
_process_base "2026.06.28 15.30-CYCLING" "$TMP/xf_store.ndjson" "$TMP/xf_known.txt"
_process_base "2026.06.29 08.00-RUNNING" "$TMP/xf_store.ndjson" "$TMP/xf_known.txt"
assert_eq "$S" "distinct-activities-both-stored" \
    "$(wc -l < "$TMP/xf_store.ndjson" | tr -d ' ')" "2"

# ── tcx-parsing ───────────────────────────────────────────────────────────────
# Mirrors the grep -o patterns from healthsync-activities.sh TCX block.
S="tcx-parsing"

cat > "$TMP/activity.tcx" <<'TCX'
<TrainingCenterDatabase>
  <Activities>
    <Activity Sport="Biking">
      <Lap>
        <TotalTimeSeconds>3600</TotalTimeSeconds>
        <DistanceMeters>25120.5</DistanceMeters>
        <Calories>450</Calories>
        <AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>
        <MaximumHeartRateBpm><Value>172</Value></MaximumHeartRateBpm>
        <Watts>220</Watts><Watts>230</Watts>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>
TCX

avg_hr="$(grep -o 'AverageHeartRateBpm><Value>[0-9]*</Value>' "$TMP/activity.tcx" \
    | head -1 | grep -o 'Value>[0-9]*' | grep -o '[0-9]*$' || true)"
assert_eq "$S" "avg-hr"     "$avg_hr"    "145"

max_hr="$(grep -o 'MaximumHeartRateBpm><Value>[0-9]*</Value>' "$TMP/activity.tcx" \
    | head -1 | grep -o 'Value>[0-9]*' | grep -o '[0-9]*$' || true)"
assert_eq "$S" "max-hr"     "$max_hr"    "172"

calories="$(grep -o '<Calories>[0-9]*</Calories>' "$TMP/activity.tcx" \
    | head -1 | grep -o '[0-9]*</Calories>' | grep -o '^[0-9]*' || true)"
assert_eq "$S" "calories"   "$calories"  "450"

_dist="$(grep -o '<DistanceMeters>[0-9.]*</DistanceMeters>' "$TMP/activity.tcx" \
    | tail -1 | grep -o '<DistanceMeters>[0-9.]*' | grep -o '[0-9.]*$' || true)"
dist_m="$(printf '%s' "$_dist" | jq -Rr 'tonumber | round')"
assert_eq "$S" "distance-m" "$dist_m"   "25121"

_time="$(grep -o '<TotalTimeSeconds>[0-9.]*</TotalTimeSeconds>' "$TMP/activity.tcx" \
    | grep -o '<TotalTimeSeconds>[0-9.]*' | grep -o '[0-9.]*$' \
    | jq -Rn '[inputs | tonumber] | add // 0 | round' || echo 0)"
assert_eq "$S" "total-time" "$_time"    "3600"

avg_watts="$(grep -o '<Watts>[0-9]*</Watts>' "$TMP/activity.tcx" \
    | grep -o '[0-9]*</Watts>' | grep -o '^[0-9]*' \
    | jq -Rn '[inputs | tonumber] | if length>0 then (add/length | round) else null end' \
    2>/dev/null || echo null)"
assert_eq "$S" "avg-watts"  "$avg_watts" "225"

# ── csv-parsing ───────────────────────────────────────────────────────────────
# Mirrors the CSV extraction logic in healthsync-activities.sh.
S="csv-parsing"

cat > "$TMP/activity.csv" <<'CSV'
source_app,type,name,date,time,elapsed_s,active_s,dist_km
HealthSync,CYCLING,CYCLING,2026.06.22,10:30:15,3840,3780,25.120
CSV

csv_data="$(tail -n +2 "$TMP/activity.csv" | head -1 | tr -d '\r')"
csv_date_raw="$(printf '%s' "$csv_data" | cut -d, -f4)"
csv_elapsed="$(printf '%s' "$csv_data" | cut -d, -f6)"
csv_active="$(printf '%s' "$csv_data" | cut -d, -f7)"
csv_dist_km="$(printf '%s' "$csv_data" | cut -d, -f8)"
act_date="$(printf '%s' "$csv_date_raw" | tr '.' '-')"

assert_eq "$S" "date"        "$act_date"    "2026-06-22"
assert_eq "$S" "elapsed"     "$csv_elapsed" "3840"
assert_eq "$S" "active"      "$csv_active"  "3780"

dist_m="$(printf '%s' "$csv_dist_km" | jq -Rr 'tonumber * 1000 | round')"
assert_eq "$S" "distance-m"  "$dist_m"      "25120"

avg_speed="$(jq -n --argjson d "$dist_m" --argjson t "$csv_active" \
    'if $t>0 then ($d/$t * 100 | round) / 100 else 0 end')"
assert_eq "$S" "avg-speed-nonzero" \
    "$([ "$avg_speed" != "0" ] && printf true || printf false)" "true"

# CRLF resilience: trailing \r must not break jq tonumber on last field
printf 'HealthSync,WALKING,WALKING,2026.06.22,20:01:42,1800,1750,3.200\r\n' \
    > "$TMP/crlf.csv"
csv_data_cr="$(tail -n +1 "$TMP/crlf.csv" | head -1 | tr -d '\r')"
csv_dist_cr="$(printf '%s' "$csv_data_cr" | cut -d, -f8)"
dist_m_cr="$(printf '%s' "$csv_dist_cr" | jq -Rr 'tonumber * 1000 | round')"
assert_eq "$S" "crlf-distance-m" "$dist_m_cr" "3200"

# ── avg-speed-edge-cases ──────────────────────────────────────────────────────
# Mirrors the avg_speed formula in healthsync-activities.sh (lines 235-236, 273-274).
S="avg-speed-edge-cases"

result="$(jq -n --argjson d 30000 --argjson t 0 'if $t>0 then $d/$t else 0 end')"
assert_eq "$S" "zero-time-returns-0" "$result" "0"

result="$(jq -n --argjson d 0 --argjson t 3600 'if $t>0 then $d/$t else 0 end')"
assert_eq "$S" "zero-distance-returns-0" "$result" "0"

result="$(jq -n --argjson d 36000 --argjson t 3600 'if $t>0 then $d/$t else 0 end')"
assert_eq "$S" "normal-speed-10ms" "$result" "10"

# ── elevation-gain ────────────────────────────────────────────────────────────
# Mirrors the GPX elevation jq pipeline in healthsync-activities.sh (lines 305-310).
S="elevation-gain"

_elev_from_pts() {
    printf '%s' "$1" | tr ' ' '\n' | \
        jq -Rn '[inputs | tonumber] as $e |
            reduce range(1; $e|length) as $i (
                0; . + (if $e[$i] > $e[$i-1] then $e[$i] - $e[$i-1] else 0 end)
            ) | round'
}

elev="$(printf '' | jq -Rn '[inputs | tonumber] as $e |
    reduce range(1; $e|length) as $i (
        0; . + (if $e[$i] > $e[$i-1] then $e[$i] - $e[$i-1] else 0 end)
    ) | round' 2>/dev/null || echo 0)"
assert_eq "$S" "zero-points"      "$elev" "0"
assert_eq "$S" "one-point"        "$(_elev_from_pts '100')"             "0"
assert_eq "$S" "descending-only"  "$(_elev_from_pts '100 90 80 70')"    "0"
assert_eq "$S" "typical-route"    "$(_elev_from_pts '100 150 140 190')" "100"

# ── max-speed-no-extension ────────────────────────────────────────────────────
# GPX without a :speed extension must produce 0, not null or an error.
S="max-speed-no-extension"

cat > "$TMP/no_speed.gpx" << 'GPX'
<?xml version="1.0"?>
<gpx version="1.1">
  <trk><trkseg>
    <trkpt lat="51.1" lon="17.0"><ele>100</ele></trkpt>
    <trkpt lat="51.2" lon="17.1"><ele>110</ele></trkpt>
  </trkseg></trk>
</gpx>
GPX

_mspd="$(grep -o ':speed>[0-9.]*' "$TMP/no_speed.gpx" \
    | grep -o '[0-9.]*$' \
    | jq -Rn '[inputs | tonumber] | if length>0 then max else 0 end' \
    2>/dev/null || echo 0)"
assert_eq "$S" "no-speed-tags-returns-0" "${_mspd:-0}" "0"

# ── tcx-fallback-condition ────────────────────────────────────────────────────
# The TCX-no-CSV branch checks [ "$distance_m" = "0" ] && [ "$csv_active" = "0" ].
# jq `round` must return the bare integer string "0" even for "0.000" input so
# the string comparison holds.
S="tcx-fallback-condition"

dist="$(printf '0.000' | jq -Rr 'tonumber * 1000 | round')"
assert_eq "$S" "zero-km-rounds-to-0-string"  "$dist" "0"
dist="$(printf '0' | jq -Rr 'tonumber * 1000 | round')"
assert_eq "$S" "zero-int-stays-0-string"     "$dist" "0"

# ── activity-filter-regex ─────────────────────────────────────────────────────
# Mirrors the jq select block that builds activity_bases.txt (lines 165-171).
S="activity-filter-regex"

cat > "$TMP/filelist.json" << 'JSON'
{"files":[
  {"name":"CYCLING 2026.06.28 15.30.csv"},
  {"name":"2026.06.28 15.30-CYCLING.gpx"},
  {"name":"CYCLING 2026.06.28 15.30"},
  {"name":"some-random-file.csv"},
  {"name":"walking 2026.06.28 15.30.csv"},
  {"name":"CYCLING 2026.06.28 15.30.bak"},
  {"name":"NORDIC_WALKING 2026.05.10 09.30.tcx"},
  {"name":"2026.04.03 12.00-E_BIKING.fit"}
]}
JSON

bases="$(jq -r '.files[].name |
    gsub("[.](csv|gpx|tcx|kml|fit)$"; "") |
    select(
        test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2} [0-9]{2}\\.[0-9]{2}-[A-Z_]+$") or
        test("^[A-Z_]+ [0-9]{4}\\.[0-9]{2}\\.[0-9]{2} [0-9]{2}\\.[0-9]{2}$")
    )
' "$TMP/filelist.json" | sort -u)"

assert_eq "$S" "valid-base-count" \
    "$(printf '%s\n' "$bases" | grep -c '.' || true)" "4"

if printf '%s\n' "$bases" | grep -qxF "CYCLING 2026.06.28 15.30"; then
    ok "$S" "old-format-accepted"
else
    err "$S" "old-format-accepted" "old-format base missing"
fi
if printf '%s\n' "$bases" | grep -qxF "NORDIC_WALKING 2026.05.10 09.30"; then
    ok "$S" "underscore-type-accepted"
else
    err "$S" "underscore-type-accepted" "underscore type base missing"
fi
if printf '%s\n' "$bases" | grep -q "walking "; then
    err "$S" "lowercase-type-rejected" "lowercase type incorrectly accepted"
else
    ok "$S" "lowercase-type-rejected"
fi
if printf '%s\n' "$bases" | grep -q "\.bak"; then
    err "$S" "unknown-extension-rejected" "unknown extension incorrectly accepted"
else
    ok "$S" "unknown-extension-rejected"
fi

# ── multi-lap-tcx ─────────────────────────────────────────────────────────────
# Multi-lap TCX: TotalTimeSeconds must be summed; DistanceMeters must use the
# last value (cumulative per-lap total, not per-lap increment).
S="multi-lap-tcx"

cat > "$TMP/multilap.tcx" << 'TCX'
<TrainingCenterDatabase>
  <Activities><Activity Sport="Biking">
    <Lap>
      <TotalTimeSeconds>1800</TotalTimeSeconds>
      <DistanceMeters>5000</DistanceMeters>
    </Lap>
    <Lap>
      <TotalTimeSeconds>1800</TotalTimeSeconds>
      <DistanceMeters>10000</DistanceMeters>
    </Lap>
  </Activity></Activities>
</TrainingCenterDatabase>
TCX

_time="$(grep -o '<TotalTimeSeconds>[0-9.]*</TotalTimeSeconds>' "$TMP/multilap.tcx" \
    | grep -o '<TotalTimeSeconds>[0-9.]*' | grep -o '[0-9.]*$' \
    | jq -Rn '[inputs | tonumber] | add // 0 | round' || echo 0)"
assert_eq "$S" "time-sum-both-laps" "$_time" "3600"

_dist="$(grep -o '<DistanceMeters>[0-9.]*</DistanceMeters>' "$TMP/multilap.tcx" \
    | tail -1 | grep -o '<DistanceMeters>[0-9.]*' | grep -o '[0-9.]*$' || true)"
dist_m="$(printf '%s' "$_dist" | jq -Rr 'tonumber | round')"
assert_eq "$S" "distance-uses-last-lap" "$dist_m" "10000"

# ── token-caching ─────────────────────────────────────────────────────────────
# Mirrors the cached-token-reuse branch in strava-lib.sh / ensure_drive_token.
S="token-caching"

TOKEN_FILE="$TMP/token.json"
now="$(date +%s)"
margin=300

printf '{"access_token":"test-token","expires_at":%d}\n' "$((now + 3600))" \
    > "$TOKEN_FILE"
cached_token="$(jq -r '.access_token // empty' "$TOKEN_FILE")"
cached_exp="$(jq -r '.expires_at // 0' "$TOKEN_FILE")"
if [ -n "$cached_token" ] && [ "$cached_exp" -gt "$((now + margin))" ]; then
    ok "$S" "fresh-token-reused"
else
    err "$S" "fresh-token-reused" "fresh token should be reused, was not"
fi

printf '{"access_token":"old-token","expires_at":%d}\n' "$((now - 100))" \
    > "$TOKEN_FILE"
cached_token="$(jq -r '.access_token // empty' "$TOKEN_FILE")"
cached_exp="$(jq -r '.expires_at // 0' "$TOKEN_FILE")"
if [ -n "$cached_token" ] && [ "$cached_exp" -gt "$((now + margin))" ]; then
    err "$S" "expired-token-not-reused" "expired token was incorrectly reused"
else
    ok "$S" "expired-token-not-reused"
fi

printf '{"access_token":"near-exp","expires_at":%d}\n' "$((now + 100))" \
    > "$TOKEN_FILE"
cached_token="$(jq -r '.access_token // empty' "$TOKEN_FILE")"
cached_exp="$(jq -r '.expires_at // 0' "$TOKEN_FILE")"
if [ -n "$cached_token" ] && [ "$cached_exp" -gt "$((now + margin))" ]; then
    err "$S" "near-expiry-not-reused" "near-expiry token was incorrectly reused"
else
    ok "$S" "near-expiry-not-reused"
fi

rm -f "$TOKEN_FILE"
cached_token="$(jq -r '.access_token // empty' "$TOKEN_FILE" 2>/dev/null || true)"
if [ -n "$cached_token" ]; then
    err "$S" "missing-file-not-reused" "token read from nonexistent file"
else
    ok "$S" "missing-file-not-reused"
fi

# ── cgi-validation ────────────────────────────────────────────────────────────
# Mirrors the jq -e guards in the bike-service and bike-assign CGI bodies.
S="cgi-validation"

_bike_service_valid() {
    printf '%s' "$1" | jq -e 'type=="object" and (.bikes|type=="array")' \
        >/dev/null 2>&1 && printf true || printf false
}

_bike_assign_valid() {
    printf '%s' "$1" | jq -e 'type == "object"' \
        >/dev/null 2>&1 && printf true || printf false
}

assert_eq "$S" "bike-service-valid-payload" \
    "$(_bike_service_valid '{"bikes":[{"id":"b1","name":"Road Bike","parts":[]}]}')" "true"
assert_eq "$S" "bike-service-bikes-not-array" \
    "$(_bike_service_valid '{"bikes":"not-an-array"}')" "false"
assert_eq "$S" "bike-service-missing-bikes" \
    "$(_bike_service_valid '{"data":[]}')" "false"
assert_eq "$S" "bike-service-array-rejected" \
    "$(_bike_service_valid '[]')" "false"
assert_eq "$S" "bike-service-malformed-rejected" \
    "$(_bike_service_valid 'not json')" "false"
assert_eq "$S" "bike-assign-valid-object" \
    "$(_bike_assign_valid '{"18784255013":"b-kross"}')" "true"
assert_eq "$S" "bike-assign-array-rejected" \
    "$(_bike_assign_valid '["b-kross"]')" "false"
assert_eq "$S" "bike-assign-malformed-rejected" \
    "$(_bike_assign_valid '{bad}')" "false"

# ── keepalive-mode ────────────────────────────────────────────────────────────
# Mirrors the HEALTHSYNC_MODE case check in healthsync-activities.sh that exits
# after the Drive folder listing when mode is "keepalive".
S="keepalive-mode"

HEALTHSYNC_MODE=keepalive
_kp=""; case "${HEALTHSYNC_MODE:-full}" in keepalive) _kp=keepalive ;; *) _kp=full ;; esac
assert_eq "$S" "keepalive-matches"   "$_kp" "keepalive"

HEALTHSYNC_MODE=full
_kp=""; case "${HEALTHSYNC_MODE:-full}" in keepalive) _kp=keepalive ;; *) _kp=full ;; esac
assert_eq "$S" "full-continues"      "$_kp" "full"

HEALTHSYNC_MODE=""
_kp=""; case "${HEALTHSYNC_MODE:-full}" in keepalive) _kp=keepalive ;; *) _kp=full ;; esac
assert_eq "$S" "empty-defaults-full" "$_kp" "full"

unset HEALTHSYNC_MODE
_kp=""; case "${HEALTHSYNC_MODE:-full}" in keepalive) _kp=keepalive ;; *) _kp=full ;; esac
assert_eq "$S" "unset-defaults-full" "$_kp" "full"
HEALTHSYNC_MODE=""

# ── scrape-html-parsing ───────────────────────────────────────────────────────
# Mirrors the jq helpers in the STRAVA_SOURCE=scrape branch of strava-leaderboard.sh
# that decode HTML-encoded stat strings from the Strava club feed JSON.
S="scrape-html-parsing"

_parse_km() {
    jq -rn --arg s "$1" '
        def strip_html: gsub("<[^>]*>"; "");
        def parse_km:
          strip_html | gsub("[^0-9.]"; "") |
          if . == "" or . == "." then 0 else tonumber end * 1000;
        $s | parse_km'
}

assert_eq "$S" "km-with-html-tags" \
    "$(_parse_km '34.30<abbr class="unit"> km</abbr>')" "34300"
assert_eq "$S" "km-plain-number"   "$(_parse_km '10.00')"            "10000"
assert_eq "$S" "km-empty-string"   "$(_parse_km '')"                 "0"
assert_eq "$S" "km-html-only"      "$(_parse_km '<abbr>km</abbr>')"  "0"

_parse_elev() {
    jq -rn --arg s "$1" '
        def strip_html: gsub("<[^>]*>"; "");
        def parse_elev:
          strip_html | gsub("[^0-9.]"; "") |
          if . == "" or . == "." then 0 else tonumber end;
        $s | parse_elev'
}

assert_eq "$S" "elev-with-html" \
    "$(_parse_elev '108<abbr class="unit"> m</abbr>')" "108"
assert_eq "$S" "elev-plain"     "$(_parse_elev '450')" "450"
assert_eq "$S" "elev-empty"     "$(_parse_elev '')"    "0"

_parse_time() {
    jq -rn --arg s "$1" '
        def strip_html: gsub("<[^>]*>"; "");
        def _n: if (. == null or . == "") then 0 else tonumber end;
        def parse_time:
          strip_html |
          capture("(?:(?<h>[0-9]+)\\s*h)?\\s*(?:(?<m>[0-9]+)\\s*m)?\\s*(?:(?<s>[0-9]+)\\s*s)?") |
          ((.h | _n) * 3600) + ((.m | _n) * 60) + (.s | _n);
        $s | parse_time'
}

assert_eq "$S" "time-h-m"     "$(_parse_time '1<abbr>h</abbr> 27<abbr>m</abbr>')"                              "5220"
assert_eq "$S" "time-m-only"  "$(_parse_time '45<abbr>m</abbr>')"                                              "2700"
assert_eq "$S" "time-s-only"  "$(_parse_time '30<abbr>s</abbr>')"                                              "30"
assert_eq "$S" "time-h-m-s"   "$(_parse_time '2<abbr>h</abbr> 3<abbr>m</abbr> 15<abbr>s</abbr>')"             "7395"
assert_eq "$S" "time-empty"   "$(_parse_time '')"                                                              "0"
assert_eq "$S" "time-plain-m" "$(_parse_time '45m')"                                                           "2700"

# ── scrape-activity-dedup ─────────────────────────────────────────────────────
# Mirrors the scrape dedup pipeline: entity filter → unique_by(id) → drop known.
S="scrape-activity-dedup"

# Seed the known store with one already-seen activity.
printf '%s\n' \
    '{"signature":"act-111","firstname":"Alice","name":"Old Ride","distance":10000}' \
    > "$TMP/sc_store.ndjson"
jq -s '[ .[].signature ]' "$TMP/sc_store.ndjson" > "$TMP/sc_known.json"

# Feed: act-111 (known→skip), act-222 (new), GroupActivity (skip), act-222 again (dedup).
cat > "$TMP/sc_feed.json" << 'FEED'
[
  {"entity":"Activity","activity":{"id":"act-111","activityName":"Old Ride","elapsedTime":3600,"type":"Ride","startDate":"2026-06-01T08:00:00Z","athlete":{"firstName":"Alice","athleteName":"Alice Smith","avatarUrl":""},"stats":[{"key":"stat_one","value":"10.00"},{"key":"stat_two","value":"100"},{"key":"stat_three","value":"1h"}]}},
  {"entity":"Activity","activity":{"id":"act-222","activityName":"New Ride","elapsedTime":5400,"type":"Ride","startDate":"2026-06-10T09:00:00Z","athlete":{"firstName":"Bob","athleteName":"Bob Jones","avatarUrl":""},"stats":[{"key":"stat_one","value":"25.50"},{"key":"stat_two","value":"300"},{"key":"stat_three","value":"1h 30m"}]}},
  {"entity":"GroupActivity","activity":{"id":"act-333","activityName":"Filtered Out"}},
  {"entity":"Activity","activity":{"id":"act-222","activityName":"Duplicate","elapsedTime":5400,"type":"Ride","startDate":"2026-06-10T09:00:00Z","athlete":{"firstName":"Bob","athleteName":"Bob Jones","avatarUrl":""},"stats":[{"key":"stat_one","value":"25.50"},{"key":"stat_two","value":"300"},{"key":"stat_three","value":"1h 30m"}]}}
]
FEED

_scrape_dedup() {
    # optional $1: cutoff date YYYY-MM-DD (empty = no cutoff)
    jq -n \
        --slurpfile known "$TMP/sc_known.json" \
        --slurpfile fetched "$TMP/sc_feed.json" \
        --arg cutoff "${1:-}" '
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
        | map(select(($seen[.s] | not) and ($cutoff == "" or .firstSeen >= $cutoff)))'
}

_sc_new="$(_scrape_dedup)"

assert_eq "$S" "only-new-added"        "$(printf '%s' "$_sc_new" | jq 'length')"         "1"
assert_eq "$S" "new-id-is-act-222"     "$(printf '%s' "$_sc_new" | jq -r '.[0].s')"      "act-222"
assert_eq "$S" "known-id-excluded"     "$(printf '%s' "$_sc_new" | jq '[.[].s=="act-111"]|any')" "false"
assert_eq "$S" "group-entity-excluded" "$(printf '%s' "$_sc_new" | jq '[.[].s=="act-333"]|any')" "false"
assert_eq "$S" "distance-parsed-km"    "$(printf '%s' "$_sc_new" | jq '.[0].distance')"  "25500"
assert_eq "$S" "moving-time-parsed"    "$(printf '%s' "$_sc_new" | jq '.[0].moving_time')" "5400"
assert_eq "$S" "elev-parsed"           "$(printf '%s' "$_sc_new" | jq '.[0].total_elevation_gain')" "300"
assert_eq "$S" "first-seen-from-date"  "$(printf '%s' "$_sc_new" | jq -r '.[0].firstSeen')" "2026-06-10"
assert_eq "$S" "lastname-trimmed"      "$(printf '%s' "$_sc_new" | jq -r '.[0].lastname')" "Jones"

# ── scrape-start-date ─────────────────────────────────────────────────────────
# Mirrors the STRAVA_SCRAPE_START_DATE cutoff: activities before the date are
# silently dropped even if they are otherwise new (not in the known store).
S="scrape-start-date"

# Empty known store (both acts below are "new").
printf '[]\n' > "$TMP/sc_known.json"

# Feed: act-old (2026-06-01) and act-recent (2026-06-20), both unknown.
cat > "$TMP/sc_feed.json" << 'FEED'
[
  {"entity":"Activity","activity":{"id":"act-old","activityName":"Old Ride","elapsedTime":3600,"type":"Ride","startDate":"2026-06-01T08:00:00Z","athlete":{"firstName":"Alice","athleteName":"Alice Smith","avatarUrl":""},"stats":[{"key":"stat_one","value":"10.00"},{"key":"stat_two","value":"100"},{"key":"stat_three","value":"1h"}]}},
  {"entity":"Activity","activity":{"id":"act-recent","activityName":"Recent Ride","elapsedTime":5400,"type":"Ride","startDate":"2026-06-20T09:00:00Z","athlete":{"firstName":"Bob","athleteName":"Bob Jones","avatarUrl":""},"stats":[{"key":"stat_one","value":"25.50"},{"key":"stat_two","value":"300"},{"key":"stat_three","value":"1h 30m"}]}}
]
FEED

# No cutoff → both activities included.
_sd_none="$(_scrape_dedup "")"
assert_eq "$S" "no-cutoff-both-included"   "$(printf '%s' "$_sd_none" | jq 'length')" "2"

# Cutoff 2026-06-10 → only act-recent (2026-06-20) passes; act-old (2026-06-01) dropped.
_sd_cut="$(_scrape_dedup "2026-06-10")"
assert_eq "$S" "cutoff-drops-old"          "$(printf '%s' "$_sd_cut" | jq 'length')"          "1"
assert_eq "$S" "cutoff-keeps-recent"       "$(printf '%s' "$_sd_cut" | jq -r '.[0].s')"        "act-recent"
assert_eq "$S" "cutoff-old-excluded"       "$(printf '%s' "$_sd_cut" | jq '[.[].s=="act-old"]|any')" "false"

# Cutoff on exact date → inclusive (>= not >).
_sd_exact="$(_scrape_dedup "2026-06-20")"
assert_eq "$S" "cutoff-exact-date-included" "$(printf '%s' "$_sd_exact" | jq -r '.[0].s')" "act-recent"

# Cutoff after both dates → nothing passes.
_sd_all="$(_scrape_dedup "2026-07-01")"
assert_eq "$S" "cutoff-excludes-all"       "$(printf '%s' "$_sd_all" | jq 'length')" "0"

# Restore the known store for the cursor / meta tests that follow.
jq -s '[ .[].signature ]' "$TMP/sc_store.ndjson" > "$TMP/sc_known.json" 2>/dev/null || printf '[]\n' > "$TMP/sc_known.json"

# ── scrape-cursor ─────────────────────────────────────────────────────────────
# Mirrors: _scrape_cursor=$(jq -r '(.entries[-1].cursorData.updated_at|floor|tostring)')
S="scrape-cursor"

cat > "$TMP/sc_page.json" << 'PAGE'
{"entries":[
  {"entity":"Activity","cursorData":{"updated_at":1717200000.5}},
  {"entity":"Activity","cursorData":{"updated_at":1717100000.9}}
]}
PAGE

_cursor="$(jq -r '(.entries[-1].cursorData.updated_at | floor | tostring)' "$TMP/sc_page.json")"
assert_eq "$S" "cursor-is-last-entry"   "$_cursor" "1717100000"
assert_eq "$S" "cursor-floored"         "$(printf '%s' "$_cursor" | grep -c '\.'  || true)" "0"

# Single-entry page: cursor equals that entry.
printf '{"entries":[{"entity":"Activity","cursorData":{"updated_at":1720000001.7}}]}\n' \
    > "$TMP/sc_page1.json"
_c1="$(jq -r '(.entries[-1].cursorData.updated_at | floor | tostring)' "$TMP/sc_page1.json")"
assert_eq "$S" "cursor-single-entry"    "$_c1" "1720000001"

# ── scrape-meta ───────────────────────────────────────────────────────────────
# Mirrors: jq -n --argjson ts "$_sc_age" '{ cookieVerifiedAt: ..., cookieRefreshNeededBy: ... }'
S="scrape-meta"

# Use a fixed timestamp: 2026-06-01T00:00:00Z = 1780272000
_ts=1780272000
_meta="$(jq -n --argjson ts "$_ts" '{
    cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
    cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0])
}')"

assert_eq "$S" "verified-at-date"        "$(printf '%s' "$_meta" | jq -r '.cookieVerifiedAt')"      "2026-06-01"
assert_eq "$S" "refresh-needed-30-days"  "$(printf '%s' "$_meta" | jq -r '.cookieRefreshNeededBy')" "2026-07-01"

# Zero timestamp → meta not emitted (validated by the shell guard in the script).
_sc_age=0
if [ "$_sc_age" -gt 0 ]; then
    err "$S" "zero-age-not-emitted" "zero age should suppress scrapeMeta"
else
    ok "$S" "zero-age-not-emitted"
fi

# ── scrape-csrf-extraction ────────────────────────────────────────────────────
# Mirrors the awk pattern in ensure_session_cookie that reads the CSRF token
# from the Strava dashboard HTML.
S="scrape-csrf-extraction"

_csrf_from_html() {
    printf '%s' "$1" | awk -F'"' '/name="csrf-token"/{
        for(i=1;i<=NF;i++){if($i==" content=" || $i=="content="){print $(i+1);exit}}
    }'
}

# Standard attribute order: name then content.
assert_eq "$S" "name-then-content" \
    "$(_csrf_from_html '<meta name="csrf-token" content="abc123XYZ"/>')" \
    "abc123XYZ"

# content before name: the awk pattern checks for " content=" as a quoted-field
# prefix, so when content= merges with the tag opener (<meta content=) it is not
# matched. Strava always emits the standard Rails order (name first), so this
# limitation is acceptable — document it as "returns empty".
assert_eq "$S" "content-before-name-unsupported" \
    "$(_csrf_from_html '<meta content="tok456" name="csrf-token"/>')" \
    ""

# No csrf-token tag → empty output.
_no_token="$(_csrf_from_html '<meta name="viewport" content="width=device-width"/>')"
if [ -z "$_no_token" ]; then
    ok "$S" "no-token-empty-output"
else
    err "$S" "no-token-empty-output" "expected empty, got: $_no_token"
fi

# ── scrape-session-age ────────────────────────────────────────────────────────
# Mirrors the CSRF-cache reuse guard in ensure_session_cookie:
#   [ "$(( $(date +%s) - _sc_ts ))" -lt 2160000 ]  (25 days = 2160000 s)
S="scrape-session-age"

_now="$(date +%s)"
_24h_ago=$(( _now - 86400 ))
_26d_ago=$(( _now - 2246400 ))
_bad_val=""

# Recent timestamp (24 h old) → cache is valid.
case "$_24h_ago" in ''|*[!0-9]*) _age_recent=expired ;; *)
    if [ "$(( _now - _24h_ago ))" -lt 2160000 ]; then _age_recent=valid
    else _age_recent=expired; fi ;;
esac
assert_eq "$S" "recent-ts-valid" "$_age_recent" "valid"

# Old timestamp (26 days) → cache expired.
case "$_26d_ago" in ''|*[!0-9]*) _age_old=expired ;; *)
    if [ "$(( _now - _26d_ago ))" -lt 2160000 ]; then _age_old=valid
    else _age_old=expired; fi ;;
esac
assert_eq "$S" "old-ts-expired" "$_age_old" "expired"

# Empty/invalid value → treated as 0 → expired (mirrors: case "$_sc_ts" in ''|*[!0-9]*) _sc_ts=0 ;; esac).
case "$_bad_val" in ''|*[!0-9]*) _age_bad=expired ;; *)
    if [ "$(( _now - _bad_val ))" -lt 2160000 ]; then _age_bad=valid
    else _age_bad=expired; fi ;;
esac
assert_eq "$S" "empty-val-expired" "$_age_bad" "expired"

# ── scrape-dry-run-meta ───────────────────────────────────────────────────────
# Mirrors the _sc_dry_run_meta building logic in strava-leaderboard.sh:
#   jq -n --argjson ts "$_sc_ts" '{ dryRun: true, cookieValid: true, ... }'
S="scrape-dry-run-meta"

_ts=1780272000  # 2026-06-01T00:00:00Z

# Valid cookie + feed OK: all fields present.
_dry_valid="$(jq -n --argjson ts "$_ts" --argjson feedOk 1 '{
    cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
    cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0]),
    dryRun:                true,
    cookieValid:           true,
    feedTestOk:            ($feedOk == 1)
}')"

assert_eq "$S" "dry-run-flag"           "$(printf '%s' "$_dry_valid" | jq '.dryRun')"                   "true"
assert_eq "$S" "cookie-valid-flag"      "$(printf '%s' "$_dry_valid" | jq '.cookieValid')"              "true"
assert_eq "$S" "feed-test-ok"           "$(printf '%s' "$_dry_valid" | jq '.feedTestOk')"               "true"
assert_eq "$S" "verified-at"            "$(printf '%s' "$_dry_valid" | jq -r '.cookieVerifiedAt')"      "2026-06-01"
assert_eq "$S" "refresh-needed-by"      "$(printf '%s' "$_dry_valid" | jq -r '.cookieRefreshNeededBy')" "2026-07-01"

# Valid cookie + feed FAILED.
_dry_feed_fail="$(jq -n --argjson ts "$_ts" --argjson feedOk 0 '{
    cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
    cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0]),
    dryRun:                true,
    cookieValid:           true,
    feedTestOk:            ($feedOk == 1)
}')"
assert_eq "$S" "feed-test-failed"       "$(printf '%s' "$_dry_feed_fail" | jq '.feedTestOk')"  "false"
assert_eq "$S" "feed-fail-cookie-valid" "$(printf '%s' "$_dry_feed_fail" | jq '.cookieValid')" "true"

# Expired cookie: dryRun=true, cookieValid=false, feedTestOk=false, no dates.
_dry_expired='{"dryRun":true,"cookieValid":false,"feedTestOk":false}'
assert_eq "$S" "expired-dry-run-flag"   "$(printf '%s' "$_dry_expired" | jq '.dryRun')"        "true"
assert_eq "$S" "expired-valid-false"    "$(printf '%s' "$_dry_expired" | jq '.cookieValid')"   "false"
assert_eq "$S" "expired-feed-false"     "$(printf '%s' "$_dry_expired" | jq '.feedTestOk')"    "false"
assert_eq "$S" "expired-no-dates"       "$(printf '%s' "$_dry_expired" | jq 'has("cookieVerifiedAt")')" "false"

# scrape mode (no dryRun field): dryRun and feedTestOk should be absent.
_scrape_meta="$(jq -n --argjson ts "$_ts" '{
    cookieVerifiedAt:      ($ts            | todate | split("T")[0]),
    cookieRefreshNeededBy: (($ts + 2592000) | todate | split("T")[0])
}')"
assert_eq "$S" "scrape-mode-no-dryrun"     "$(printf '%s' "$_scrape_meta" | jq 'has("dryRun")')"     "false"
assert_eq "$S" "scrape-mode-no-feedtestok" "$(printf '%s' "$_scrape_meta" | jq 'has("feedTestOk")')" "false"

# ── JUnit XML output ──────────────────────────────────────────────────────────

if [ -n "$JUNIT_OUT" ]; then
    total=$((PASS + FAIL))
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<testsuites>\n'
        printf '<testsuite name="shell-tests" tests="%d" failures="%d" time="0">\n' \
            "$total" "$FAIL"
        TAB="$(printf '\t')"
        while IFS="$TAB" read -r suite name status msg; do
            safe_suite="$(_xml_escape "$suite")"
            safe_name="$(_xml_escape "$name")"
            safe_msg="$(_xml_escape "$msg")"
            printf '  <testcase classname="%s" name="%s / %s" time="0">' \
                "$safe_suite" "$safe_suite" "$safe_name"
            if [ "$status" = "fail" ]; then
                printf '\n    <failure message="%s">%s</failure>\n  ' \
                    "$safe_msg" "$safe_msg"
            fi
            printf '</testcase>\n'
        done < "$RESULTS"
        printf '</testsuite>\n'
        printf '</testsuites>\n'
    } > "$JUNIT_OUT"
    printf 'JUnit XML written to %s\n' "$JUNIT_OUT"
fi

# ── summary ───────────────────────────────────────────────────────────────────

printf '\n==> Shell tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
