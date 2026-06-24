#!/bin/sh
# Entrypoint for the live HealthSync test container.
# Runs healthsync-activities.sh (fetches from Google Drive, generates HTML),
# then starts lighttpd to serve the result.
set -eu

STATE=/usr/lib/healthsync
WEB=/www/strava/me
CGI=/www/cgi-bin

mkdir -p "$STATE" "$WEB/details" "$WEB/gpx" "$CGI"

# Override paths to container layout (config stays at its standard location).
export HEALTHSYNC_STATE_DIR="$STATE"
export HEALTHSYNC_WEB_DIR="$WEB"
export HEALTHSYNC_CGI_DIR="$CGI"
export HEALTHSYNC_BIKE_DATA="$STATE/bike-service.json"
export HEALTHSYNC_BIKE_ASSIGN="$STATE/bike-assignments.json"

echo "==> running healthsync-activities.sh ..."
/opt/healthsync-activities.sh

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

echo "serving on :8080 — open http://localhost:8080/strava/me/"
exec lighttpd -D -f /tmp/lighttpd.conf
