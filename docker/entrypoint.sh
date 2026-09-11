#!/bin/sh
# Docker entrypoint for StatsServiceBook.
# Detects which config files are mounted, wires up crond, then starts lighttpd.
set -eu

DATA=/data
WEB=/www
CGI=/www/cgi-bin

mkdir -p \
  "$CGI" \
  "$DATA/strava-leaderboard" \
  "$DATA/strava-my-activities" \
  "$DATA/healthsync" \
  "$WEB/strava/me/details" \
  "$WEB/strava/me/gpx" \
  /var/log

CRON_FILE=/tmp/crontab
: > "$CRON_FILE"
FOUND=0

if [ -f /etc/strava-leaderboard.conf ]; then
  FOUND=1
  SCHED="${CRON_LEADERBOARD:-50 23 * * *}"
  echo "$SCHED strava-leaderboard >> /var/log/strava-leaderboard.log 2>&1" >> "$CRON_FILE"
  echo "==> strava-leaderboard cron: $SCHED"
fi

if [ -f /etc/strava-my-activities.conf ]; then
  FOUND=1
  SCHED="${CRON_MY_ACTIVITIES:-55 23 * * *}"
  echo "$SCHED strava-my-activities >> /var/log/strava-my-activities.log 2>&1" >> "$CRON_FILE"
  echo "==> strava-my-activities cron: $SCHED"
fi

if [ -f /etc/healthsync-activities.conf ]; then
  FOUND=1
  SCHED="${CRON_HEALTHSYNC:-55 23 * * *}"
  echo "$SCHED healthsync-activities >> /var/log/healthsync-activities.log 2>&1" >> "$CRON_FILE"
  echo "==> healthsync-activities cron: $SCHED"
fi

if [ "$FOUND" = "0" ]; then
  echo "WARNING: no config mounted. Mount at least one of:"
  echo "  /etc/strava-my-activities.conf"
  echo "  /etc/strava-leaderboard.conf"
  echo "  /etc/healthsync-activities.conf"
  echo "See https://github.com/raczeja/StatsServiceBook/wiki/Docker"
fi

crontab "$CRON_FILE"
crond

# Optional first-run: execute each enabled script before handing off to lighttpd.
if [ "${RUN_ON_START:-0}" = "1" ]; then
  if [ -f /etc/strava-leaderboard.conf ]; then
    echo "==> running strava-leaderboard ..."
    strava-leaderboard 2>&1 || echo "ERROR: strava-leaderboard failed"
  fi
  if [ -f /etc/strava-my-activities.conf ]; then
    echo "==> running strava-my-activities ..."
    strava-my-activities 2>&1 || echo "ERROR: strava-my-activities failed"
  fi
  if [ -f /etc/healthsync-activities.conf ]; then
    echo "==> running healthsync-activities ..."
    healthsync-activities 2>&1 || echo "ERROR: healthsync-activities failed"
  fi
fi

echo "==> serving on :80 — open http://localhost/strava/me/"
exec lighttpd -D -f /etc/lighttpd/lighttpd.conf
