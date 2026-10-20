#!/bin/sh
# Self-heal after an OpenWrt sysupgrade. Installed to /etc/strava-restore.sh
# (preserved across sysupgrade) and started from /etc/rc.local at boot.
#
# sysupgrade keeps /etc but wipes /usr/bin and installed packages. install.sh
# stages a copy of the repo on persistent storage ($STRAVA_BUNDLE_DIR, recorded
# in /etc/strava-restore.conf). When the scripts are gone, this re-runs that
# bundle's install.sh (which reinstalls packages, scripts, cron) and then
# regenerates the web pages. A no-op on a normal boot.
set -u

CONF="/etc/strava-restore.conf"
[ -f "$CONF" ] && . "$CONF"
BUNDLE_DIR="${STRAVA_BUNDLE_DIR:-}"
[ -n "$BUNDLE_DIR" ] || exit 0

# Nothing to do when the install is intact.
[ -f /usr/bin/strava-lib.sh ] && [ -x /usr/bin/strava-my-activities ] && exit 0

LOG="$(dirname "$BUNDLE_DIR")/strava-restore.log"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG" 2>/dev/null; }

# The bundle lives on persistent storage that may mount late (USB).
i=0
while [ ! -f "$BUNDLE_DIR/install.sh" ] && [ "$i" -lt 60 ]; do
  sleep 5; i=$((i + 1))
done
if [ ! -f "$BUNDLE_DIR/install.sh" ]; then
  log "restore: $BUNDLE_DIR/install.sh not found — giving up"
  exit 1
fi

log "restore: scripts missing (sysupgrade?) — reinstalling from $BUNDLE_DIR"

# Package install needs the network; retry install.sh while it is not up yet.
attempt=1
while [ "$attempt" -le 10 ]; do
  if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && sh "$BUNDLE_DIR/install.sh" >>"$LOG" 2>&1; then
    log "restore: install.sh succeeded (attempt $attempt)"
    break
  fi
  log "restore: attempt $attempt failed — retrying in 60s"
  attempt=$((attempt + 1))
  sleep 60
done
if [ ! -f /usr/bin/strava-lib.sh ]; then
  log "restore: reinstall failed after $((attempt - 1)) attempts"
  exit 1
fi

# Rebuild /www/strava from the persisted state. Unconfigured sources just fail.
for b in strava-my-activities strava-leaderboard healthsync-activities; do
  [ -x "/usr/bin/$b" ] || continue
  # HealthSync is optional: skip it while its config is missing or still the template.
  if [ "$b" = healthsync-activities ] && \
     { [ ! -f /etc/healthsync-activities.conf ] || grep -q 'YOUR_GOOGLE_REFRESH_TOKEN\|YOUR_DRIVE_FOLDER_ID' /etc/healthsync-activities.conf; }; then
    log "restore: skipping $b (not configured)"
    continue
  fi
  log "restore: running $b"
  "/usr/bin/$b" >>"$LOG" 2>&1 || log "restore: $b exited non-zero"
done
log "restore: done."
