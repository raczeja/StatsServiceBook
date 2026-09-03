#!/bin/sh
# Installer for StravaStats-OpenWrt. Run on the router as root:
#   scp -r openwrt root@<router-ip>:/tmp/strava && ssh root@<router-ip>
#   sh /tmp/strava/install.sh
set -eu

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="/usr/bin/strava-leaderboard"
CONF="/etc/strava-leaderboard.conf"
BIN_ME="/usr/bin/strava-my-activities"
CONF_ME="/etc/strava-my-activities.conf"
BIN_HS="/usr/bin/healthsync-activities"
CONF_HS="/etc/healthsync-activities.conf"
BIN_GUARD="/usr/bin/strava-cron-guard"
BIN_EMAIL="/usr/bin/strava-email-monthly"
BIN_EMAIL_WEEKLY="/usr/bin/strava-email-weekly"
CRON_TIME="${CRON_TIME:-50 23 * * *}"               # leaderboard:  daily at 23:50 local time
CRON_TIME_ME="${CRON_TIME_ME:-55 23 * * *}"         # my-activities: daily at 23:55 local time
CRON_TIME_HS="${CRON_TIME_HS:-55 23 * * *}"         # healthsync:    daily at 23:55 (replaces my-activities when Strava API ends)
CRON_TIME_EMAIL="${CRON_TIME_EMAIL:-0 8 1 * *}"     # monthly email: 1st of each month at 08:00
CRON_TIME_EMAIL_WEEKLY="${CRON_TIME_EMAIL_WEEKLY:-0 8 * * 1}" # weekly email:  every Monday at 08:00
# POSIX TZ for Europe/Warsaw incl. DST (CET/CEST). Override with TZ_POSIX="" to skip.
TZ_POSIX="${TZ_POSIX:-CET-1CEST,M3.5.0,M10.5.0/3}"

echo "==> setting router timezone so cron times are Warsaw local"
if [ -n "$TZ_POSIX" ]; then
  uci set system.@system[0].timezone="$TZ_POSIX"
  uci set system.@system[0].zonename='Europe/Warsaw'
  uci commit system
  /etc/init.d/system reload
fi

echo "==> installing dependencies (curl, jq, ca-bundle, msmtp)"
# OpenWrt 24.10+/snapshots use apk; older releases use opkg.
if command -v apk >/dev/null 2>&1; then
  apk update
  apk add curl jq ca-bundle msmtp
elif command -v opkg >/dev/null 2>&1; then
  opkg update
  opkg install curl jq ca-bundle msmtp
else
  echo "ERROR: neither apk nor opkg found — install curl, jq, ca-bundle manually" >&2
  exit 1
fi

echo "==> installing $BIN"
cp "$SRC_DIR/strava-leaderboard.sh" "$BIN"
chmod 0755 "$BIN"

if [ ! -f "$CONF" ]; then
  echo "==> installing config template to $CONF (edit it before running!)"
  cp "$SRC_DIR/config.example" "$CONF"
  chmod 0600 "$CONF"
else
  echo "==> $CONF already exists — leaving it untouched"
fi

echo "==> installing $BIN_GUARD, $BIN_EMAIL, and $BIN_EMAIL_WEEKLY"
cp "$SRC_DIR/strava-cron-guard.sh"    "$BIN_GUARD"
chmod 0755 "$BIN_GUARD"
cp "$SRC_DIR/strava-email-monthly.sh" "$BIN_EMAIL"
chmod 0755 "$BIN_EMAIL"
cp "$SRC_DIR/strava-email-monthly.sh" "$BIN_EMAIL_WEEKLY"
chmod 0755 "$BIN_EMAIL_WEEKLY"

echo "==> installing shared library and HTML helpers"
cp "$SRC_DIR/strava-lib.sh"               /usr/bin/strava-lib.sh
chmod 0644 /usr/bin/strava-lib.sh
cp "$SRC_DIR/strava-my-html-dashboard.sh" /usr/bin/strava-my-html-dashboard.sh
chmod 0644 /usr/bin/strava-my-html-dashboard.sh
cp "$SRC_DIR/strava-my-html-detail.sh"   /usr/bin/strava-my-html-detail.sh
chmod 0644 /usr/bin/strava-my-html-detail.sh
cp "$SRC_DIR/strava-my-html-bike.sh"     /usr/bin/strava-my-html-bike.sh
chmod 0644 /usr/bin/strava-my-html-bike.sh
cp "$SRC_DIR/strava-my-html-stats.sh"   /usr/bin/strava-my-html-stats.sh
chmod 0644 /usr/bin/strava-my-html-stats.sh

echo "==> installing $BIN_ME"
cp "$SRC_DIR/strava-my-activities.sh" "$BIN_ME"
chmod 0755 "$BIN_ME"

if [ ! -f "$CONF_ME" ]; then
  echo "==> installing config template to $CONF_ME (edit it before running!)"
  cp "$SRC_DIR/config-my.example" "$CONF_ME"
  chmod 0600 "$CONF_ME"
else
  echo "==> $CONF_ME already exists — leaving it untouched"
fi

echo "==> installing $BIN_HS"
cp "$SRC_DIR/healthsync-activities.sh" "$BIN_HS"
chmod 0755 "$BIN_HS"

if [ ! -f "$CONF_HS" ]; then
  echo "==> installing config template to $CONF_HS (edit it before running!)"
  cp "$SRC_DIR/config-healthsync.example" "$CONF_HS"
  chmod 0600 "$CONF_HS"
else
  echo "==> $CONF_HS already exists — leaving it untouched"
fi

# --- Reconcile web symlinks when output dirs are relocated off flash ----------
# By default each dashboard is written straight into uhttpd's web root
# (/www/strava and /www/strava/me). If a config points STRAVA_WEB_DIR /
# STRAVA_MY_WEB_DIR elsewhere (e.g. a USB disk, to spare the 16 MB flash
# overlay), uhttpd still only serves /www — so recreate the symlinks that bridge
# the served path to the relocated output. Idempotent: a no-op when the dirs are
# the defaults, and safe to re-run.

# Read one KEY="value" from a config without pulling its secrets into our env.
conf_val() { # <conf-file> <key> <default>
  ( set +eu; [ -f "$1" ] && . "$1"; eval "printf '%s' \"\${$2:-$3}\"" )
}

ME_WEB="$(conf_val "$CONF_ME" STRAVA_MY_WEB_DIR /www/strava/me)"
LB_WEB="$(conf_val "$CONF" STRAVA_WEB_DIR /www/strava)"
HS_STATE="$(conf_val "$CONF_HS" HEALTHSYNC_STATE_DIR /usr/lib/healthsync)"
HS_WEB="$(conf_val "$CONF_HS" HEALTHSYNC_WEB_DIR /www/strava/me)"

# My activities is served at a leaf path -> a single directory symlink.
if [ "$ME_WEB" != "/www/strava/me" ]; then
  echo "==> linking /www/strava/me -> $ME_WEB (relocated web dir)"
  mkdir -p /www/strava "$ME_WEB"
  [ -e /www/strava/me ] && [ ! -L /www/strava/me ] && rm -rf /www/strava/me
  ln -sfn "$ME_WEB" /www/strava/me
fi

# /www/strava also holds the 'me' entry, so keep it a real dir and symlink only
# the files the leaderboard generates into the relocated web dir.
if [ "$LB_WEB" != "/www/strava" ]; then
  LB_CLUB_IDS="$(conf_val "$CONF" STRAVA_CLUB_IDS "$(conf_val "$CONF" STRAVA_CLUB_ID "")")"
  echo "==> linking /www/strava/{activities.json,index.html,leaderboard_<club>.json} -> $LB_WEB"
  mkdir -p /www/strava "$LB_WEB"
  for f in activities.json index.html; do
    [ -e "/www/strava/$f" ] && [ ! -L "/www/strava/$f" ] && rm -f "/www/strava/$f"
    ln -sfn "$LB_WEB/$f" "/www/strava/$f"
  done
  old_IFS="$IFS"; IFS=","
  for club_id in $LB_CLUB_IDS; do
    club_id="$(printf '%s' "$club_id" | tr -d ' \t')"
    [ -n "$club_id" ] || continue
    f="leaderboard_${club_id}.json"
    [ -e "/www/strava/$f" ] && [ ! -L "/www/strava/$f" ] && rm -f "/www/strava/$f"
    ln -sfn "$LB_WEB/$f" "/www/strava/$f"
  done
  IFS="$old_IFS"
fi

# HealthSync state dir — must exist before the first run (may be on a USB mount).
echo "==> ensuring HealthSync state dir: $HS_STATE"
mkdir -p "$HS_STATE"

# HealthSync shares the served path /www/strava/me with My Activities.
# Two cases when HS_WEB is relocated:
#   Coexistence (ME_WEB is still the default real dir): Strava owns /www/strava/me,
#   so only symlink drive-status.json there so the Strava dashboard can show the
#   Google Drive token status without clobbering Strava's files.
#   HealthSync-primary (ME_WEB also relocated): safe to create the full directory
#   symlink /www/strava/me → HS_WEB so uhttpd serves HealthSync's output.
if [ "$HS_WEB" != "/www/strava/me" ]; then
  mkdir -p /www/strava "$HS_WEB"
  if [ "$ME_WEB" = "/www/strava/me" ]; then
    echo "==> coexistence: linking /www/strava/me/drive-status.json -> $HS_WEB/drive-status.json"
    ln -sf "$HS_WEB/drive-status.json" /www/strava/me/drive-status.json
  else
    echo "==> linking /www/strava/me -> $HS_WEB (relocated HealthSync web dir)"
    [ -e /www/strava/me ] && [ ! -L /www/strava/me ] && rm -rf /www/strava/me
    ln -sfn "$HS_WEB" /www/strava/me
  fi
fi

# --- Ensure uhttpd serves the bike-service CGI --------------------------------
# The My Activities "Bike service" page (http://<router>/strava/me/bike.html)
# saves its data through a CGI that strava-my-activities writes to /www/cgi-bin.
# uhttpd serves that prefix as CGI by default; set it idempotently in case a
# custom config dropped it. Only commits + reloads when a change was needed.
if command -v uci >/dev/null 2>&1 && uci -q get uhttpd.main >/dev/null 2>&1; then
  CUR_CGI="$(uci -q get uhttpd.main.cgi_prefix || true)"
  if [ "$CUR_CGI" != "/cgi-bin" ]; then
    echo "==> enabling uhttpd CGI (cgi_prefix=/cgi-bin) for the bike-service page"
    uci set uhttpd.main.cgi_prefix='/cgi-bin'
    uci commit uhttpd
    /etc/init.d/uhttpd reload
  else
    echo "==> uhttpd CGI already enabled (cgi_prefix=/cgi-bin)"
  fi
fi

echo "==> scheduling daily runs: leaderboard '$CRON_TIME', my-activities '$CRON_TIME_ME', healthsync '$CRON_TIME_HS', monthly-email '$CRON_TIME_EMAIL', weekly-email '$CRON_TIME_EMAIL_WEEKLY'"
CRON_LINE="$CRON_TIME $BIN_GUARD strava-leaderboard >> /var/log/strava-leaderboard.log 2>&1"
CRON_LINE_ME="$CRON_TIME_ME $BIN_GUARD strava-my-activities >> /var/log/strava-my-activities.log 2>&1"
CRON_LINE_HS="$CRON_TIME_HS $BIN_GUARD healthsync-activities >> /var/log/healthsync-activities.log 2>&1"
CRON_LINE_EMAIL="$CRON_TIME_EMAIL $BIN_GUARD strava-email-monthly >> /var/log/strava-email-monthly.log 2>&1"
CRON_LINE_EMAIL_WEEKLY="$CRON_TIME_EMAIL_WEEKLY $BIN_GUARD strava-email-weekly >> /var/log/strava-email-weekly.log 2>&1"
{
  crontab -l 2>/dev/null \
    | grep -v 'strava-leaderboard' \
    | grep -v 'strava-my-activities' \
    | grep -v 'healthsync-activities' \
    | grep -v 'strava-email-monthly' \
    | grep -v 'strava-email-weekly' \
    || true
  echo "$CRON_LINE"
  echo "$CRON_LINE_ME"
  echo "$CRON_LINE_HS"
  echo "$CRON_LINE_EMAIL"
  echo "$CRON_LINE_EMAIL_WEEKLY"
} | crontab -
/etc/init.d/cron enable
/etc/init.d/cron restart

cat <<EOF

==> Done. Next steps:

    Club leaderboard:
    1) Edit your secrets:        vi $CONF
    2) Run once to verify:       $BIN          (output should end with 'done.')
    3) Open the dashboard:       http://<router-ip>/strava/

    My activities (Strava API — active until subscription lapses):
    1) Edit your secrets:        vi $CONF_ME
    2) Run once to verify:       $BIN_ME       (output should end with 'done.')
    3) Open the dashboard:       http://<router-ip>/strava/me/
    4) Track bike maintenance:   http://<router-ip>/strava/me/bike.html

    My activities (HealthSync / Google Drive — Strava-API-free):
    1) Edit your secrets:        vi $CONF_HS
    2) Run once to verify:       $BIN_HS       (output should end with 'done.')
    3) When Strava API access ends, remove the my-activities cron line:
         crontab -l | grep -v 'strava-my-activities' | crontab -

    Email (optional — configure in $CONF):
      STRAVA_EMAIL_SMTP / STRAVA_EMAIL_USER / STRAVA_EMAIL_FROM
      STRAVA_EMAIL_TO         — monthly leaderboard recipients (comma-separated, sent 1st of month)
      STRAVA_EMAIL_WEEKLY_TO  — weekly leaderboard recipients  (comma-separated, sent every Monday)
      STRAVA_EMAIL_ALERTS_TO  — cron error alert recipients    (comma-separated)
      Test monthly email:  STRAVA_EMAIL_TEST_MONTH=YYYY-MM $BIN_EMAIL
      Test weekly email:   STRAVA_WEEKLY_TEST_MONTH=YYYY-MM $BIN_EMAIL_WEEKLY

    Logs:
      /var/log/strava-leaderboard.log    (in RAM; cleared on reboot)
      /var/log/strava-my-activities.log  (in RAM; cleared on reboot)
      /var/log/healthsync-activities.log (in RAM; cleared on reboot)
      /var/log/strava-email-monthly.log  (in RAM; cleared on reboot)
      /var/log/strava-email-weekly.log   (in RAM; cleared on reboot)
    Cron:    crontab -l
EOF
