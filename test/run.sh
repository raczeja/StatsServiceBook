#!/bin/sh
# Local test harness for club + My Activities pages + bike-service CGI.
# Extracts each page from its dedicated helper script (the single source of
# truth — no copy/paste drift), lays them out like the router does, and
# serves them with BusyBox httpd, which runs /cgi-bin/* as CGI exactly like
# OpenWrt's uhttpd. Used inside the container built by Containerfile; not
# shipped to the router.
set -eu

DASHBOARD=/opt/strava-my-html-dashboard.sh
DETAIL=/opt/strava-my-html-detail.sh
BIKE=/opt/strava-my-html-bike.sh
STATS=/opt/strava-my-html-stats.sh
CLUB=/opt/strava-leaderboard.sh

WEB=/www/strava/me
DATA=/data/bike-service.json
CLUB_WEB=/www/strava

mkdir -p "$WEB/details" "$CLUB_WEB" /www/cgi-bin /data

# Extract each page from its helper script's <<'HTML' heredoc.
awk '/^cat > "\$WEB_DIR\/index\.html" <<.HTML.$/{f=1;next}    /^HTML$/{f=0} f' "$DASHBOARD" > "$WEB/index.html"
awk '/^cat > "\$WEB_DIR\/index\.html" <<.HTML.$/{f=1;next}    /^HTML$/{f=0} f' "$CLUB"      > "$CLUB_WEB/index.html"
awk '/^cat > "\$WEB_DIR\/activity\.html" <<.HTML.$/{f=1;next} /^HTML$/{f=0} f' "$DETAIL"    > "$WEB/activity.html"
awk '/^cat > "\$WEB_DIR\/stats\.html" <<.HTML.$/{f=1;next}    /^HTML$/{f=0} f' "$STATS"     > "$WEB/stats.html"
awk '/^cat > "\$WEB_DIR\/bike\.html" <<.HTML.$/{f=1;next}     /^HTML$/{f=0} f' "$BIKE"      > "$WEB/bike.html"

# CGI: prepend the two lines the main script injects (shebang + data path),
# then the body of the <<'CGI' heredoc in strava-my-html-bike.sh.
{
  echo '#!/bin/sh'
  echo "DATA_FILE=\"$DATA\""
  awk '/^cat >> "\$CGI_DIR\/bike-service" <<.CGI.$/{f=1;next} /^CGI$/{f=0} f' "$BIKE"
} > /www/cgi-bin/bike-service
chmod 0755 /www/cgi-bin/bike-service

cp /opt/activities.sample.json "$WEB/activities.json"
cp /opt/club-activities.sample.json "$CLUB_WEB/activities.json"

# Sample per-activity detail JSON (served at details/<id>.json, linked from the dashboard).
cp /opt/18784255013.json "$WEB/details/18784255013.json"

# Seed the bike-service store with sample parts/services so the page has data on
# first load. Only seed if absent: once the CGI has written real edits we don't clobber them.
if [ ! -f "$DATA" ] && [ -f /opt/bike-service.sample.json ]; then
  cp /opt/bike-service.sample.json "$DATA"
  echo "seeded $DATA from bike-service.sample.json"
fi

echo "extracted pages:"
echo "  club/index.html: $(wc -l < "$CLUB_WEB/index.html") lines"
echo "  index.html:    $(wc -l < "$WEB/index.html") lines"
echo "  activity.html: $(wc -l < "$WEB/activity.html") lines"
echo "  stats.html:    $(wc -l < "$WEB/stats.html") lines"
echo "  bike.html:     $(wc -l < "$WEB/bike.html") lines"
echo "  CGI:           $(wc -l < /www/cgi-bin/bike-service) lines"
echo "serving on :8080:"
echo "  Club leaderboard ->  http://localhost:8080/strava/"
echo "  My Activities  ->  http://localhost:8080/strava/me/"
echo "  Stats          ->  http://localhost:8080/strava/me/stats.html"
echo "  Activity       ->  http://localhost:8080/strava/me/activity.html?id=18784255013"
echo "  Bike service   ->  http://localhost:8080/strava/me/bike.html"
exec httpd -f -vv -p 8080 -h /www
