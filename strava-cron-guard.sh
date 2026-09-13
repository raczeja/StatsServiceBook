#!/bin/sh
# strava-cron-guard — cron wrapper with network pre-flight check, automatic
# retry on transient failure, and alert email when all retries are exhausted.
#
# Usage (in crontab):
#   50 23 * * *  /usr/bin/strava-cron-guard strava-leaderboard >> /var/log/strava-leaderboard.log 2>&1
#
# Self-healing behaviour:
#   1. Pre-flight: pings STRAVA_NET_CHECK_HOST (default: 1.1.1.1) before running
#      the script. If unreachable, waits STRAVA_NET_CHECK_INTERVAL seconds and
#      retries the ping, up to STRAVA_NET_CHECK_WAIT total seconds. Aborts with a
#      syslog error if the network never comes up within that window.
#   2. Retry: on non-zero exit the script is re-run after STRAVA_CRON_RETRY_DELAY
#      seconds, up to STRAVA_CRON_RETRIES additional attempts. The alert email is
#      only sent once all attempts have failed.
#
# All knobs live in /etc/strava-leaderboard.conf (or $STRAVA_CONFIG):
#   STRAVA_CRON_RETRIES=2          retries after the first attempt (0 = no retry)
#   STRAVA_CRON_RETRY_DELAY=300    seconds between retries
#   STRAVA_NET_CHECK_HOST=1.1.1.1  host to ping for the pre-flight check
#   STRAVA_NET_CHECK_WAIT=120      max seconds to wait for network to come up
#   STRAVA_NET_CHECK_INTERVAL=15   seconds between connectivity polls

set -eu

SCRIPT_NAME="${1:?Usage: strava-cron-guard <script-name>}"
SCRIPT="/usr/bin/$SCRIPT_NAME"
CONFIG="${STRAVA_CONFIG:-/etc/strava-leaderboard.conf}"

[ -x "$SCRIPT" ] || { printf 'strava-cron-guard: not found or not executable: %s\n' "$SCRIPT" >&2; exit 1; }

# Defaults — overridden by values in the config file.
STRAVA_CRON_RETRIES=2
STRAVA_CRON_RETRY_DELAY=300
STRAVA_NET_CHECK_HOST="1.1.1.1"
STRAVA_NET_CHECK_WAIT=120
STRAVA_NET_CHECK_INTERVAL=15
STRAVA_EMAIL_SMTP=""
STRAVA_EMAIL_USER=""
STRAVA_EMAIL_FROM=""
STRAVA_EMAIL_ALERTS_TO=""

if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG"
fi

# ── 1. Network pre-flight ─────────────────────────────────────────────────────
# OpenWrt's dnsmasq restarts briefly on WAN reconnect / DHCP renewal. Ping a
# well-known IP (not hostname) so DNS is not required for the check itself.
_net_waited=0
while ! ping -c 1 -W 3 "$STRAVA_NET_CHECK_HOST" >/dev/null 2>&1; do
    if [ "$_net_waited" -ge "$STRAVA_NET_CHECK_WAIT" ]; then
        printf 'strava-cron-guard: network still offline after %ds — aborting %s\n' \
            "$STRAVA_NET_CHECK_WAIT" "$SCRIPT_NAME"
        logger -t strava "ERROR: $SCRIPT_NAME skipped — no network after ${STRAVA_NET_CHECK_WAIT}s"
        exit 1
    fi
    printf 'strava-cron-guard: network offline, waiting %ds (%d/%ds)…\n' \
        "$STRAVA_NET_CHECK_INTERVAL" "$_net_waited" "$STRAVA_NET_CHECK_WAIT"
    logger -t strava "WARNING: $SCRIPT_NAME — network offline (waited ${_net_waited}/${STRAVA_NET_CHECK_WAIT}s)"
    sleep "$STRAVA_NET_CHECK_INTERVAL"
    _net_waited=$((_net_waited + STRAVA_NET_CHECK_INTERVAL))
done
if [ "$_net_waited" -gt 0 ]; then
    printf 'strava-cron-guard: network up after %ds — proceeding with %s\n' \
        "$_net_waited" "$SCRIPT_NAME"
    logger -t strava "INFO: $SCRIPT_NAME — network recovered after ${_net_waited}s"
fi

# ── 2. Run with retries ───────────────────────────────────────────────────────
CAPTURE="$(mktemp /tmp/strava-guard.XXXXXX)"
_attempt=0
EXIT_CODE=1

while true; do
    _attempt=$((_attempt + 1))
    : > "$CAPTURE"
    set +e
    "$SCRIPT" >"$CAPTURE" 2>&1
    EXIT_CODE=$?
    set -e

    cat "$CAPTURE"

    if [ "$EXIT_CODE" -eq 0 ]; then
        rm -f "$CAPTURE"
        exit 0
    fi

    if [ "$_attempt" -le "$STRAVA_CRON_RETRIES" ]; then
        printf 'strava-cron-guard: %s failed (exit %d), retry %d/%d in %ds…\n' \
            "$SCRIPT_NAME" "$EXIT_CODE" "$_attempt" "$STRAVA_CRON_RETRIES" "$STRAVA_CRON_RETRY_DELAY"
        logger -t strava \
            "WARNING: $SCRIPT_NAME failed (exit $EXIT_CODE) — retry ${_attempt}/${STRAVA_CRON_RETRIES} in ${STRAVA_CRON_RETRY_DELAY}s"
        sleep "$STRAVA_CRON_RETRY_DELAY"
    else
        break
    fi
done

logger -t strava "ERROR: $SCRIPT_NAME failed (exit $EXIT_CODE) after ${_attempt} attempt(s)"

# ── 3. Send alert email ───────────────────────────────────────────────────────
if [ -z "$STRAVA_EMAIL_SMTP" ] || [ -z "$STRAVA_EMAIL_USER" ] || [ -z "$STRAVA_EMAIL_ALERTS_TO" ]; then
    printf 'strava-cron-guard: alert email not configured (STRAVA_EMAIL_SMTP/USER/ALERTS_TO); skipping notification\n'
    logger -t strava "WARNING: $SCRIPT_NAME failed — no alert email configured"
    rm -f "$CAPTURE"
    exit "$EXIT_CODE"
fi

EMAIL_FROM="${STRAVA_EMAIL_FROM:-${STRAVA_EMAIL_USER%%:*}}"
SUBJECT="[strava-cron] $SCRIPT_NAME failed after ${_attempt} attempt(s) (exit $EXIT_CODE)"

# Parse STRAVA_EMAIL_SMTP URL (smtps://host:port or smtp://host:port) for msmtp.
_smtp_authority="${STRAVA_EMAIL_SMTP#*://}"
_smtp_host="${_smtp_authority%%:*}"
_smtp_port="${_smtp_authority##*:}"
[ "$_smtp_port" = "$_smtp_authority" ] && _smtp_port="465"
_smtp_starttls="off"
case "$STRAVA_EMAIL_SMTP" in smtp://*) _smtp_starttls="on" ;; esac
_smtp_user="${STRAVA_EMAIL_USER%%:*}"
_smtp_pass="${STRAVA_EMAIL_USER#*:}"

# Build shared body (headers per recipient; body shared).
MSG_BODY="$(mktemp /tmp/strava-guard-body.XXXXXX)"
{
    printf '%s exited with code %d on %s after %d attempt(s).\n\n' \
        "$SCRIPT" "$EXIT_CODE" "$(date '+%Y-%m-%d %H:%M:%S')" "$_attempt"
    printf 'Last 50 lines of output (final attempt):\n'
    printf -- '---\n'
    tail -n 50 "$CAPTURE"
} > "$MSG_BODY"

old_IFS="$IFS"; IFS=","
for addr in $STRAVA_EMAIL_ALERTS_TO; do
    addr="$(printf '%s' "$addr" | tr -d ' \t')"
    [ -n "$addr" ] || continue
    printf 'strava-cron-guard: sending alert to %s\n' "$addr"
    logger -t strava "ERROR: $SCRIPT_NAME failed after ${_attempt} attempt(s) — sending alert to $addr"
    {
        printf 'From: %s\r\n' "$EMAIL_FROM"
        printf 'To: %s\r\n' "$addr"
        printf 'Subject: %s\r\n' "$SUBJECT"
        printf 'Date: %s\r\n' "$(date '+%a, %d %b %Y %H:%M:%S %z')"
        printf 'MIME-Version: 1.0\r\n'
        printf 'Content-Type: text/plain; charset=utf-8\r\n'
        printf '\r\n'
        cat "$MSG_BODY"
    } | msmtp \
        --host="$_smtp_host" \
        --port="$_smtp_port" \
        --tls \
        --tls-starttls="$_smtp_starttls" \
        --auth=plain \
        --user="$_smtp_user" \
        --passwordeval="printf '%s' '$_smtp_pass'" \
        --from="$EMAIL_FROM" \
        "$addr" \
        || { printf 'strava-cron-guard: failed to send alert to %s\n' "$addr"; \
             logger -t strava "ERROR: failed to send failure alert for $SCRIPT_NAME to $addr"; }
done
IFS="$old_IFS"

rm -f "$CAPTURE" "$MSG_BODY"
exit "$EXIT_CODE"
