#!/bin/sh
# strava-cron-guard — cron wrapper that sends an alert email when a script fails.
#
# Usage (in crontab):
#   50 23 * * *  /usr/bin/strava-cron-guard strava-leaderboard >> /var/log/strava-leaderboard.log 2>&1
#
# The guard runs /usr/bin/<script-name>, captures its output, and forwards it to
# stdout (so the cron log redirect still works). On non-zero exit it sends an
# alert email to STRAVA_EMAIL_ALERTS_TO from /etc/strava-leaderboard.conf.

set -eu

SCRIPT_NAME="${1:?Usage: strava-cron-guard <script-name>}"
SCRIPT="/usr/bin/$SCRIPT_NAME"
CONFIG="${STRAVA_CONFIG:-/etc/strava-leaderboard.conf}"

[ -x "$SCRIPT" ] || { printf 'strava-cron-guard: not found or not executable: %s\n' "$SCRIPT" >&2; exit 1; }

CAPTURE="$(mktemp /tmp/strava-guard.XXXXXX)"

# Run the script, capture all output; print it after so the cron log redirect works.
set +e
"$SCRIPT" >"$CAPTURE" 2>&1
EXIT_CODE=$?
set -e

cat "$CAPTURE"

if [ "$EXIT_CODE" -eq 0 ]; then
    rm -f "$CAPTURE"
    exit 0
fi

logger -t strava "ERROR: $SCRIPT_NAME failed (exit $EXIT_CODE) — checking for alert config"
# Non-zero exit — send alert email if SMTP is configured.
STRAVA_EMAIL_SMTP=""
STRAVA_EMAIL_USER=""
STRAVA_EMAIL_FROM=""
STRAVA_EMAIL_ALERTS_TO=""

if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG"
fi

if [ -z "$STRAVA_EMAIL_SMTP" ] || [ -z "$STRAVA_EMAIL_USER" ] || [ -z "$STRAVA_EMAIL_ALERTS_TO" ]; then
    printf 'strava-cron-guard: alert email not configured (STRAVA_EMAIL_SMTP/USER/ALERTS_TO); skipping notification\n'
    logger -t strava "WARNING: $SCRIPT_NAME failed (exit $EXIT_CODE) — no alert email configured"
    rm -f "$CAPTURE"
    exit "$EXIT_CODE"
fi

EMAIL_FROM="${STRAVA_EMAIL_FROM:-${STRAVA_EMAIL_USER%%:*}}"
SUBJECT="[strava-cron] $SCRIPT_NAME failed (exit $EXIT_CODE)"

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
    printf '%s exited with code %s on %s.\n\n' "$SCRIPT" "$EXIT_CODE" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Last 50 lines of output:\n'
    printf -- '---\n'
    tail -n 50 "$CAPTURE"
} > "$MSG_BODY"

old_IFS="$IFS"; IFS=","
for addr in $STRAVA_EMAIL_ALERTS_TO; do
    addr="$(printf '%s' "$addr" | tr -d ' \t')"
    [ -n "$addr" ] || continue
    printf 'strava-cron-guard: sending alert to %s\n' "$addr"
    logger -t strava "ERROR: $SCRIPT_NAME failed (exit $EXIT_CODE) — sending alert to $addr"
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
        || { printf 'strava-cron-guard: failed to send alert to %s\n' "$addr"; logger -t strava "ERROR: failed to send failure alert for $SCRIPT_NAME to $addr"; }
done
IFS="$old_IFS"

rm -f "$CAPTURE" "$MSG_BODY"
exit "$EXIT_CODE"
