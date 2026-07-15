#!/bin/sh
# Local test harness for club + My Activities pages + bike-service CGI.
# Extracts each page from its dedicated helper script (the single source of
# truth — no copy/paste drift), lays them out like the router does, and
# serves them with lighttpd (CGI/1.1 compliant POST handling).
# Used inside the container built by Containerfile; not shipped to the router.
set -eu

DASHBOARD=/opt/strava-my-html-dashboard.sh
DETAIL=/opt/strava-my-html-detail.sh
BIKE=/opt/strava-my-html-bike.sh
STATS=/opt/strava-my-html-stats.sh
CLUB=/opt/strava-leaderboard.sh

WEB=/www/strava/me
DATA=/data/bike-service.json
CLUB_WEB=/www/strava

mkdir -p "$WEB/details" "$WEB/gpx" "$CLUB_WEB" /www/cgi-bin /data

# Extract each page from its helper script's <<'HTML' heredoc.
awk '/^cat > "\$WEB_DIR\/index\.html" <<.HTML.$/{f=1;next}    /^HTML$/{f=0} f' "$DASHBOARD" > "$WEB/index.html"
awk '/^cat > "\$WEB_DIR\/index\.html" <<.HTML.$/{f=1;next}    /^HTML$/{f=0} f' "$CLUB"      > "$CLUB_WEB/index.html"
awk '/^cat > "\$WEB_DIR\/activity\.html" <<.HTML.$/{f=1;next} /^HTML$/{f=0} f' "$DETAIL"    > "$WEB/activity.html"
awk '/^cat > "\$WEB_DIR\/stats\.html" <<.HTML.$/{f=1;next}    /^HTML$/{f=0} f' "$STATS"     > "$WEB/stats.html"
{
  printf '%s\n' '<!doctype html><html lang="en"><head>'
  printf '<script>var _CFG={defaultBikeName:""};</script>\n'
  awk '/^cat >> "\$WEB_DIR\/bike\.html" <<.HTML.$/{f=1;next} /^HTML$/{f=0} f' "$BIKE"
} > "$WEB/bike.html"

# CGI: prepend the two lines the main script injects (shebang + data path),
# then the body of the <<'CGI' heredoc in strava-my-html-bike.sh.
{
  echo '#!/bin/sh'
  echo "DATA_FILE=\"$DATA\""
  awk '/^cat >> "\$CGI_DIR\/bike-service" <<.CGI.$/{f=1;next} /^CGI$/{f=0} f' "$BIKE"
} > /www/cgi-bin/bike-service
chmod 0755 /www/cgi-bin/bike-service

BIKE_ASSIGN=/data/bike-assignments.json
[ -f "$BIKE_ASSIGN" ] || printf '{}' > "$BIKE_ASSIGN"
{
  echo '#!/bin/sh'
  echo "DATA_FILE=\"$BIKE_ASSIGN\""
  awk '/^cat >> "\$CGI_DIR\/bike-assign" <<.CGI.$/{f=1;next} /^CGI$/{f=0} f' "$BIKE"
} > /www/cgi-bin/bike-assign
chmod 0755 /www/cgi-bin/bike-assign

# drive-auth CGI stub (no real Google credentials in the test container).
{
  echo '#!/bin/sh'
  echo 'printf "Content-Type: text/html\r\nCache-Control: no-cache\r\n\r\n"'
  echo 'printf "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Authorize Google Drive</title></head><body><h1>Re-authorize Google Drive</h1><p>Test stub.</p></body></html>\n"'
} > /www/cgi-bin/drive-auth
chmod 0755 /www/cgi-bin/drive-auth

cp /opt/activities.sample.json "$WEB/activities.json"
# Drive auth status: ok=true with token info so the dashboard can render the status line.
printf '{"ok":true,"expires_at":%s,"token_type":"Bearer","lastSync":%s,"mode":"full"}\n' \
    "$(($(date +%s) + 7200))" "$(date +%s)" > "$WEB/drive-status.json"
cp /opt/club-activities.sample.json "$CLUB_WEB/activities.json"

# Minimal per-club leaderboard JSON — mirrors what strava-leaderboard writes to
# $WEB_DIR/leaderboard_<clubId>.json; install.sh symlinks that into /www/strava/.
# Without this file the footer link returns 404, which install.sh's symlink bug
# (leaderboard.json vs leaderboard_<id>.json) previously masked.
printf '{"generatedAt":"2026-01-01T00:00:00Z","sportType":null,"totals":{"member_count":0,"distance":0,"moving_time":0,"elevation_gain":0,"activity_count":0},"members":[]}\n' \
  > "$CLUB_WEB/leaderboard_123456.json"

# Sample per-activity detail JSON (served at details/<id>.json, linked from the dashboard).
cp /opt/18784255013.json "$WEB/details/18784255013.json"

# HealthSync sample: detail JSON + GPX file for testing the GPX map path.
cp /opt/healthsync-20260622.json "$WEB/details/2026-06-22-15-07-running.json"
cp /opt/healthsync-sample.gpx "$WEB/gpx/healthsync-sample.gpx"

# HealthSync bike/cycling sample: detail JSON + GPX for testing gear_id assignment.
cp /opt/healthsync-bike.json "$WEB/details/2026-06-22-10-30-cycling.json"
cp /opt/healthsync-bike.gpx "$WEB/gpx/2026.06.22_10.30-CYCLING.gpx"

# Magene C606 sample: detail JSON + GPX (GPS Visualizer-converted, no HR).
cp /opt/magene-sample.json "$WEB/details/magene-2026-07-12-50671559.json"
cp /opt/magene-sample.gpx  "$WEB/gpx/magene_2026-07-12_50671559.gpx"

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
echo "  GPX activity   ->  http://localhost:8080/strava/me/activity.html?id=2026-06-22-15-07-running"
echo "  Bike activity  ->  http://localhost:8080/strava/me/activity.html?id=2026-06-22-10-30-cycling"
echo "  Bike service   ->  http://localhost:8080/strava/me/bike.html"
cat > /tmp/lighttpd.conf <<'CONF'
server.document-root = "/www"
server.port          = 8080
server.bind          = "0.0.0.0"
server.modules       = ("mod_cgi", "mod_indexfile", "mod_staticfile", "mod_dirlisting")
server.errorlog      = "/dev/stderr"
server.pid-file      = "/tmp/lighttpd.pid"
index-file.names     = ("index.html")
$HTTP["url"] =~ "^/cgi-bin/" {
  cgi.assign = ("" => "/bin/sh")
}
CONF
exec lighttpd -D -f /tmp/lighttpd.conf
