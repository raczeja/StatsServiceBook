# strava-my-feed-api.sh — sourced by strava-my-activities.sh (§2, api branch).
# Pages /api/v3/athlete/activities; appends NDJSON to $TMP/all.ndjson.
# Variables read from caller: TMP, MAX_PAGES, PER_PAGE, ACCESS_TOKEN, log, curl_retry.
# Variables written back: reached_end (set to 1 on natural end of feed).

log "fetching athlete activities via API (up to $MAX_PAGES pages of $PER_PAGE)..."
while [ "$page" -le "$MAX_PAGES" ]; do
  log "page $page: GET /api/v3/athlete/activities?per_page=$PER_PAGE&page=$page"
  curl_retry -fsS "https://www.strava.com/api/v3/athlete/activities?per_page=$PER_PAGE&page=$page" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -o "$TMP/page.json" || die "activities fetch failed (page $page)"

  count="$(jq 'length' "$TMP/page.json" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || { log "page $page empty, stopping"; reached_end=1; break; }

  jq -c '.[]' "$TMP/page.json" >> "$TMP/all.ndjson"
  log "page $page: $count activities"

  [ "$count" -lt "$PER_PAGE" ] && { log "short page, stopping"; reached_end=1; break; }
  page=$((page + 1))
done
