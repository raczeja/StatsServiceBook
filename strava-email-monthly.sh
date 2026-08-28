#!/bin/sh
# strava-email-monthly / strava-email-weekly — leaderboard emailer.
#
# The same binary is installed under two names; behavior is selected by name:
#
#   strava-email-monthly  — emails last month's leaderboard on the 1st of each month.
#     Cron (added by install.sh):
#       0 8 1 * *  /usr/bin/strava-email-monthly >> /var/log/strava-email-monthly.log 2>&1
#     Recipients: STRAVA_EMAIL_TO
#     Test override: STRAVA_EMAIL_TEST_MONTH=2026-07 /usr/bin/strava-email-monthly
#
#   strava-email-weekly   — emails the current month's leaderboard every Monday.
#     Cron (added by install.sh):
#       0 8 * * 1  /usr/bin/strava-email-weekly >> /var/log/strava-email-weekly.log 2>&1
#     Recipients: STRAVA_EMAIL_WEEKLY_TO
#     Test override: STRAVA_WEEKLY_TEST_MONTH=2026-08 /usr/bin/strava-email-weekly
#
# SMTP settings come from /etc/strava-leaderboard.conf (shared by both modes).
# The script is a no-op when the relevant email vars are not configured.

set -eu

STRAVA_LIBDIR="$(dirname "$0")"
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-lib.sh"

CONFIG="${STRAVA_CONFIG:-/etc/strava-leaderboard.conf}"
[ -f "$CONFIG" ] || die "config not found: $CONFIG (copy config.example and edit it)"
# shellcheck disable=SC1090
. "$CONFIG"

# --- Detect mode from invocation name ----------------------------------------
_mode="monthly"
case "$(basename "$0")" in *weekly*) _mode="weekly" ;; esac

# --- Resolve SMTP credentials (shared by both modes) -------------------------
STRAVA_EMAIL_SMTP="${STRAVA_EMAIL_SMTP:-}"
STRAVA_EMAIL_USER="${STRAVA_EMAIL_USER:-}"

# --- Mode-specific: recipient var and month target ---------------------------
if [ "$_mode" = "weekly" ]; then
    _recipients="${STRAVA_EMAIL_WEEKLY_TO:-}"
    if [ -z "$STRAVA_EMAIL_SMTP" ] || [ -z "$STRAVA_EMAIL_USER" ] || [ -z "$_recipients" ]; then
        log "STRAVA_EMAIL_SMTP / STRAVA_EMAIL_USER / STRAVA_EMAIL_WEEKLY_TO not set in $CONFIG — skipping weekly email"
        exit 0
    fi
    # Current month; override with STRAVA_WEEKLY_TEST_MONTH for testing.
    if [ -n "${STRAVA_WEEKLY_TEST_MONTH:-}" ]; then
        TARGET_MONTH="$STRAVA_WEEKLY_TEST_MONTH"
    else
        TARGET_MONTH="$(date +%Y-%m)"
    fi
    _subject_suffix=" (Weekly Update)"
    _subheader_suffix=" &mdash; Weekly Update"
    _no_data_msg_suffix=" so far in"
else
    _recipients="${STRAVA_EMAIL_TO:-}"
    if [ -z "$STRAVA_EMAIL_SMTP" ] || [ -z "$STRAVA_EMAIL_USER" ] || [ -z "$_recipients" ]; then
        log "STRAVA_EMAIL_SMTP / STRAVA_EMAIL_USER / STRAVA_EMAIL_TO not set in $CONFIG — skipping monthly email"
        exit 0
    fi
    # Previous month; override with STRAVA_EMAIL_TEST_MONTH for testing.
    if [ -n "${STRAVA_EMAIL_TEST_MONTH:-}" ]; then
        TARGET_MONTH="$STRAVA_EMAIL_TEST_MONTH"
    else
        year=$(date +%Y)
        month=$(date +%m)
        if [ "$month" -eq 1 ]; then
            prev_year=$((year - 1))
            prev_month=12
        else
            prev_year=$year
            prev_month=$((month - 1))
        fi
        TARGET_MONTH="$(printf '%04d-%02d' "$prev_year" "$prev_month")"
    fi
    _subject_suffix=""
    _subheader_suffix=""
    _no_data_msg_suffix=" recorded for"
fi

# --- Month label -------------------------------------------------------------
case "${TARGET_MONTH#*-}" in
    01) month_name="January"   ;; 02) month_name="February"  ;;
    03) month_name="March"     ;; 04) month_name="April"     ;;
    05) month_name="May"       ;; 06) month_name="June"      ;;
    07) month_name="July"      ;; 08) month_name="August"    ;;
    09) month_name="September" ;; 10) month_name="October"   ;;
    11) month_name="November"  ;; 12) month_name="December"  ;;
    *)  month_name="$TARGET_MONTH" ;;
esac
MONTH_LABEL="$month_name ${TARGET_MONTH%%-*}"

log "building $_mode leaderboard email for $TARGET_MONTH ($MONTH_LABEL)"

# --- Other config ------------------------------------------------------------
EMAIL_FROM="${STRAVA_EMAIL_FROM:-${STRAVA_EMAIL_USER%%:*}}"
STATE_DIR="${STRAVA_STATE_DIR:-/usr/lib/strava-leaderboard}"
WEB_DIR="${STRAVA_WEB_DIR:-/www/strava}"
CLUB_IDS="${STRAVA_CLUB_IDS:-${STRAVA_CLUB_ID:-}}"
: "${CLUB_IDS:?set STRAVA_CLUB_IDS in $CONFIG}"

TMP="$(mktemp -d /tmp/strava-email.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

BODY="$TMP/body.html"

# HTML shell: header + embedded CSS (inline-compatible for Gmail / Outlook web).
{
    printf '<!DOCTYPE html><html><head><meta charset="utf-8">'
    printf '<title>Strava Leaderboard - %s%s</title>' "$MONTH_LABEL" "$_subject_suffix"
    printf '<style>'
    printf 'body{margin:0;padding:0;background:#fafafa;font-family:Arial,Helvetica,sans-serif;color:#222}'
    printf '.w{max-width:620px;margin:0 auto;padding:20px 16px}'
    printf '.hd{background:#fc4c02;color:#fff;padding:28px 32px;border-radius:6px 6px 0 0}'
    printf '.hd h1{margin:0 0 6px;font-size:21px;font-weight:700;letter-spacing:-.3px}'
    printf '.hd p{margin:0;font-size:16px;opacity:.92}'
    printf '.cb{background:#fff;border-radius:0 0 6px 6px;box-shadow:0 1px 4px rgba(0,0,0,.1);margin-bottom:20px;overflow:hidden}'
    printf '.cn{padding:11px 16px;font-size:14px;font-weight:700;background:#2a2a2a;color:#fff}'
    printf 'table{width:100%%;border-collapse:collapse}'
    printf 'th{background:#fc4c02;color:#fff;padding:9px 12px;text-align:left;font-size:12px;white-space:nowrap}'
    printf 'th.r{text-align:right}'
    printf 'td{padding:8px 12px;font-size:13px;border-bottom:1px solid #eee;vertical-align:middle}'
    printf 'td.r{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}'
    printf 'tr:nth-child(even) td{background:#fafafa}'
    printf 'tr.t td.rk{color:#fc4c02;font-weight:700}'
    printf '.nd{color:#666;padding:14px 16px;font-size:13px}'
    printf '.ft{color:#bbb;font-size:11px;text-align:center;padding:18px 0 6px}'
    printf '</style></head><body><div class="w">'
    printf '<div class="hd"><h1>&#127942; Strava Leaderboard</h1><p>%s%s</p></div>' \
        "$MONTH_LABEL" "$_subheader_suffix"
    printf '<div class="cb">'
} > "$BODY"

# --- Per-club leaderboard blocks ---------------------------------------------
old_IFS="$IFS"; IFS=","
for club_id in $CLUB_IDS; do
    club_id="$(printf '%s' "$club_id" | tr -d ' \t')"
    [ -n "$club_id" ] || continue

    NDJSON="$STATE_DIR/activities_${club_id}.ndjson"

    club_name=""
    ACTIVITIES_JSON="$WEB_DIR/activities.json"
    if [ -f "$ACTIVITIES_JSON" ]; then
        club_name="$(jq -r --arg id "$club_id" \
            '.clubs[] | select(.clubId == $id) | .club.name // empty' \
            "$ACTIVITIES_JSON" 2>/dev/null || true)"
    fi
    club_name="${club_name:-Club $club_id}"

    printf '<div class="cn">%s</div>' "$club_name" >> "$BODY"

    if [ ! -f "$NDJSON" ]; then
        printf '<p class="nd">Activity store not found.</p>' >> "$BODY"
        continue
    fi

    TABLE="$TMP/table_${club_id}.tsv"
    jq -rn --arg month "$TARGET_MONTH" \
        '[inputs | select(.firstSeen | startswith($month))]
         | group_by("\(.firstname)|\(.lastname)")
         | map({
             name: "\(.[0].firstname) \(.[0].lastname)",
             dist: (([.[].distance] | add) / 1000),
             time_s: ([.[].moving_time] | add),
             elev: (([.[].total_elevation_gain] | add) | round),
             count: length
           })
         | sort_by(-.dist)
         | to_entries[]
         | [
             (.key + 1 | tostring),
             .value.name,
             ((.value.dist * 10 | round) / 10 | tostring),
             (.value.time_s / 3600 | floor | tostring),
             (.value.time_s % 3600 / 60 | floor | tostring),
             (.value.elev | tostring),
             (.value.count | tostring)
           ]
         | @tsv' \
        "$NDJSON" > "$TABLE" 2>/dev/null || true

    if [ ! -s "$TABLE" ]; then
        printf '<p class="nd">No activities%s %s.</p>' \
            "$_no_data_msg_suffix" "$MONTH_LABEL" >> "$BODY"
        continue
    fi

    {
        printf '<table><thead><tr>'
        printf '<th>#</th><th>Athlete</th>'
        printf '<th class="r">Distance</th><th class="r">Time</th>'
        printf '<th class="r">Elev</th><th class="r">Activities</th>'
        printf '</tr></thead><tbody>'
    } >> "$BODY"

    while IFS="$(printf '\t')" read -r rank name dist time_h time_m elev count; do
        time_m_pad="$(printf '%02d' "$time_m")"
        case "$rank" in
            1) medal="&#129351;" ;; 2) medal="&#129352;" ;; 3) medal="&#129353;" ;;
            *) medal="$rank"     ;;
        esac
        _tr_class=""
        [ "$rank" = "1" ] && _tr_class=' class="t"'
        printf '<tr%s><td class="rk">%s</td><td>%s</td><td class="r">%s&thinsp;km</td><td class="r">%sh&thinsp;%sm</td><td class="r">%s&thinsp;m</td><td class="r">%s</td></tr>' \
            "$_tr_class" "$medal" "$name" "$dist" "$time_h" "$time_m_pad" "$elev" "$count" >> "$BODY"
    done < "$TABLE"

    printf '</tbody></table>' >> "$BODY"
done
IFS="$old_IFS"

printf '</div>'                                                                          >> "$BODY"
printf '<div class="ft">Generated by StatsServiceBook &middot; %s</div>' \
    "$(date '+%Y-%m-%d %H:%M')"                                                          >> "$BODY"
printf '</div></body></html>'                                                            >> "$BODY"

# --- Send one email per recipient -------------------------------------------
SUBJECT="Strava Leaderboard - $MONTH_LABEL${_subject_suffix}"
log "sending to: $_recipients"

_smtp_authority="${STRAVA_EMAIL_SMTP#*://}"
_smtp_host="${_smtp_authority%%:*}"
_smtp_port="${_smtp_authority##*:}"
[ "$_smtp_port" = "$_smtp_authority" ] && _smtp_port="465"
_smtp_starttls="off"
case "$STRAVA_EMAIL_SMTP" in smtp://*) _smtp_starttls="on" ;; esac
_smtp_user="${STRAVA_EMAIL_USER%%:*}"
_smtp_pass="${STRAVA_EMAIL_USER#*:}"

old_IFS="$IFS"; IFS=","
for addr in $_recipients; do
    addr="$(printf '%s' "$addr" | tr -d ' \t')"
    [ -n "$addr" ] || continue
    log "sending to $addr"
    {
        printf 'From: %s\r\n' "$EMAIL_FROM"
        printf 'To: %s\r\n' "$addr"
        printf 'Subject: %s\r\n' "$SUBJECT"
        printf 'Date: %s\r\n' "$(date '+%a, %d %b %Y %H:%M:%S %z')"
        printf 'MIME-Version: 1.0\r\n'
        printf 'Content-Type: text/html; charset=utf-8\r\n'
        printf '\r\n'
        cat "$BODY"
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
        || log "WARNING: failed to send to $addr"
done
IFS="$old_IFS"

log "done."
