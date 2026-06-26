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
