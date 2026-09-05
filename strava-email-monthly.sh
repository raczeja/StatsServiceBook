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
        month=$(expr "$(date +%m)" + 0)
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
log "merge athletes: ${MERGE_ATHLETES:-none}"

# --- Last week date range (weekly email only) ---------------------------------
LAST_WEEK_FROM="" LAST_WEEK_TO=""
if [ "$_mode" = "weekly" ]; then
    _now_ts=$(date +%s)
    _dow=$(date +%w)    # 0=Sun, 1=Mon, ..., 6=Sat
    [ "$_dow" -eq 0 ] && _dsm=6 || _dsm=$((_dow - 1))
    _this_mon=$((_now_ts - _dsm * 86400))
    LAST_WEEK_FROM=$(date -d "@$((_this_mon - 7 * 86400))" '+%Y-%m-%d')
    LAST_WEEK_TO=$(date -d "@$((_this_mon - 86400))" '+%Y-%m-%d')
    log "last week: $LAST_WEEK_FROM to $LAST_WEEK_TO"
    _wk_d1="${LAST_WEEK_FROM##*-}"
    _wk_d2="${LAST_WEEK_TO##*-}"
    _tmp="${LAST_WEEK_FROM%-*}"; _wk_m1="${_tmp##*-}"
    _tmp="${LAST_WEEK_TO%-*}";   _wk_m2="${_tmp##*-}"
    case "$_wk_m1" in 01)_wk_mn1=Jan;;02)_wk_mn1=Feb;;03)_wk_mn1=Mar;;04)_wk_mn1=Apr;;05)_wk_mn1=May;;06)_wk_mn1=Jun;;07)_wk_mn1=Jul;;08)_wk_mn1=Aug;;09)_wk_mn1=Sep;;10)_wk_mn1=Oct;;11)_wk_mn1=Nov;;12)_wk_mn1=Dec;;esac
    case "$_wk_m2" in 01)_wk_mn2=Jan;;02)_wk_mn2=Feb;;03)_wk_mn2=Mar;;04)_wk_mn2=Apr;;05)_wk_mn2=May;;06)_wk_mn2=Jun;;07)_wk_mn2=Jul;;08)_wk_mn2=Aug;;09)_wk_mn2=Sep;;10)_wk_mn2=Oct;;11)_wk_mn2=Nov;;12)_wk_mn2=Dec;;esac
    if [ "$_wk_m1" = "$_wk_m2" ]; then
        _subheader_suffix=" &mdash; Weekly Update &mdash; $_wk_mn1 ${_wk_d1#0}&#8211;${_wk_d2#0}"
    else
        _subheader_suffix=" &mdash; Weekly Update &mdash; $_wk_mn1 ${_wk_d1#0}&#8211;$_wk_mn2 ${_wk_d2#0}"
    fi
fi

# --- Other config ------------------------------------------------------------
EMAIL_FROM="${STRAVA_EMAIL_FROM:-${STRAVA_EMAIL_USER%%:*}}"
STATE_DIR="${STRAVA_STATE_DIR:-/usr/lib/strava-leaderboard}"
WEB_DIR="${STRAVA_WEB_DIR:-/www/strava}"
CLUB_IDS="${STRAVA_CLUB_IDS:-${STRAVA_CLUB_ID:-}}"
: "${CLUB_IDS:?set STRAVA_CLUB_IDS in $CONFIG}"
MERGE_ATHLETES="${STRAVA_MERGE_ATHLETES:-}"

TMP="$(mktemp -d /tmp/strava-email.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

BODY="$TMP/body.html"

# HTML shell: header + embedded CSS (inline-compatible for Gmail / Outlook web).
{
    printf '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
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
    printf 'tr:nth-child(even) td{background:#fafafa}'
    printf '.nd{color:#666;padding:14px 16px;font-size:13px}'
    printf '.ft{color:#bbb;font-size:11px;text-align:center;padding:18px 0 6px}'
    printf '</style></head><body>\n<div class="w">\n'
    printf '<div class="hd"><h1>&#127942; Strava Leaderboard</h1><p>%s%s</p></div>\n' \
        "$MONTH_LABEL" "$_subheader_suffix"
    printf '<div class="cb">\n'
} > "$BODY"

# Inline styles — Outlook's Word renderer ignores <style> blocks; these must be on every element.
_TH='nowrap style="background:#fc4c02;color:#fff;padding:5px 6px;font-size:11px;white-space:nowrap;text-align:left"'
_THR='nowrap style="background:#fc4c02;color:#fff;padding:5px 6px;font-size:11px;white-space:nowrap;text-align:right"'
_TD='nowrap style="padding:5px 6px;font-size:11px;border-bottom:1px solid #eee;vertical-align:middle;white-space:nowrap"'
_TDR='nowrap style="padding:5px 6px;font-size:11px;border-bottom:1px solid #eee;vertical-align:middle;text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums"'

# --- Per-club leaderboard blocks ---------------------------------------------
old_IFS="$IFS"; IFS=","
for club_id in $CLUB_IDS; do
    club_id="$(printf '%s' "$club_id" | tr -d ' \t')"
    [ -n "$club_id" ] || continue

    NDJSON="$STATE_DIR/activities_${club_id}.ndjson"
    if [ -f "$NDJSON" ]; then
        log "club $club_id: $(wc -l < "$NDJSON" | tr -d ' ') activities in store"
    else
        log "club $club_id: NDJSON store not found"
    fi

    club_name=""
    ACTIVITIES_JSON="$WEB_DIR/activities.json"
    if [ -f "$ACTIVITIES_JSON" ]; then
        club_name="$(jq -r --arg id "$club_id" \
            '.clubs[] | select(.clubId == $id) | .club.name // empty' \
            "$ACTIVITIES_JSON" 2>/dev/null || true)"
    fi
    club_name="${club_name:-Club $club_id}"

    printf '<div class="cn">%s</div>\n' "$club_name" >> "$BODY"

    if [ ! -f "$NDJSON" ]; then
        printf '<p class="nd">Activity store not found.</p>' >> "$BODY"
        continue
    fi

    TABLE="$TMP/table_${club_id}.tsv"
    if [ "$_mode" = "weekly" ]; then
        jq -rn \
            --arg month "$TARGET_MONTH" \
            --arg wfrom "$LAST_WEEK_FROM" \
            --arg wto   "$LAST_WEEK_TO" \
            --arg merge "$MERGE_ATHLETES" \
            "$JQ_MERGE_FUNC"'[ inputs | applyMerge ] as $all
             | ($all | map(select(.firstSeen | startswith($month)))) as $ma
             | ($all | map(select(.firstSeen >= $wfrom and .firstSeen <= $wto))) as $wa
             | ($ma | group_by("\(.firstname)|\(.lastname)")
                  | map({
                      key:    "\(.[0].firstname)|\(.[0].lastname)",
                      name:   "\(.[0].firstname) \(.[0].lastname)",
                      dist:   (([.[].distance]             | add) / 1000),
                      time_s: ([.[].moving_time]            | add),
                      elev:   (([.[].total_elevation_gain] | add) | round),
                      count:  length
                    }))
             | map(. as $a | . + {
                   week_dist: ([$wa[] | select("\(.firstname)|\(.lastname)" == $a.key) | .distance] | add // 0) / 1000
                 })
             | sort_by(-.dist)
             | to_entries[]
             | [
                 (.key + 1 | tostring),
                 (.value.name | @html),
                 ((.value.dist      * 10 | round) / 10 | tostring),
                 (.value.time_s / 3600 | floor | tostring),
                 (.value.time_s % 3600 / 60 | floor | tostring),
                 (.value.elev | tostring),
                 (if .value.time_s > 0 then ((.value.dist / (.value.time_s / 3600) * 10 | round) / 10) else 0 end | tostring),
                 ((.value.week_dist * 10 | round) / 10 | tostring)
               ]
             | @tsv' \
            "$NDJSON" > "$TABLE" 2>/dev/null || true
    else
        jq -rn \
            --arg month "$TARGET_MONTH" \
            --arg merge "$MERGE_ATHLETES" \
            "$JQ_MERGE_FUNC"'[inputs | applyMerge | select(.firstSeen | startswith($month))]
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
                 (.value.name | @html),
                 ((.value.dist * 10 | round) / 10 | tostring),
                 (.value.time_s / 3600 | floor | tostring),
                 (.value.time_s % 3600 / 60 | floor | tostring),
                 (.value.elev | tostring),
                 (if .value.time_s > 0 then ((.value.dist / (.value.time_s / 3600) * 10 | round) / 10) else 0 end | tostring)
               ]
             | @tsv' \
            "$NDJSON" > "$TABLE" 2>/dev/null || true
    fi
    log "club $club_id: $(wc -l < "$TABLE" 2>/dev/null | tr -d ' ') athletes in table"

    if [ ! -s "$TABLE" ]; then
        printf '<p class="nd">No activities%s %s.</p>' \
            "$_no_data_msg_suffix" "$MONTH_LABEL" >> "$BODY"
        continue
    fi

    {
        printf '<table style="width:100%%;border-collapse:collapse;font-size:11px">\n<thead><tr>\n'
        printf '<th %s width="26">#</th>\n<th %s width="180">Athlete</th>\n' "$_TH" "$_TH"
        printf '<th %s width="55">km</th>\n<th %s width="68">Time</th>\n' "$_THR" "$_THR"
        printf '<th %s width="54">m&#8593;</th>\n' "$_THR"
        printf '<th %s width="48">km/h</th>\n' "$_THR"
        [ "$_mode" = "weekly" ] && printf '<th %s width="54">Wk&nbsp;km</th>\n' "$_THR"
        printf '</tr>\n</thead>\n<tbody>\n'
    } >> "$BODY"

    while IFS="$(printf '\t')" read -r rank name dist time_h time_m elev avg_speed week_dist; do
        time_m_pad="$(printf '%02d' "$time_m")"
        case "$rank" in
            1) medal="&#129351;" ;; 2) medal="&#129352;" ;; 3) medal="&#129353;" ;;
            *) medal="$rank"     ;;
        esac
        _rk_style="$_TD"
        [ "$rank" = "1" ] && _rk_style='nowrap style="padding:5px 6px;font-size:11px;border-bottom:1px solid #eee;vertical-align:middle;white-space:nowrap;color:#fc4c02;font-weight:700"'
        if [ "$_mode" = "weekly" ]; then
            printf '<tr>\n<td %s>%s</td>\n<td %s>%s</td>\n<td %s>%s</td>\n<td %s>%sh&thinsp;%sm</td>\n<td %s>%s</td>\n<td %s>%s</td>\n<td %s>%s</td>\n</tr>\n' \
                "$_rk_style" "$medal" "$_TD" "$name" "$_TDR" "$dist" "$_TDR" "$time_h" "$time_m_pad" "$_TDR" "$elev" "$_TDR" "$avg_speed" "$_TDR" "$week_dist" >> "$BODY"
        else
            printf '<tr>\n<td %s>%s</td>\n<td %s>%s</td>\n<td %s>%s</td>\n<td %s>%sh&thinsp;%sm</td>\n<td %s>%s</td>\n<td %s>%s</td>\n</tr>\n' \
                "$_rk_style" "$medal" "$_TD" "$name" "$_TDR" "$dist" "$_TDR" "$time_h" "$time_m_pad" "$_TDR" "$elev" "$_TDR" "$avg_speed" >> "$BODY"
        fi
    done < "$TABLE"

    printf '</tbody>\n</table>\n' >> "$BODY"
done
IFS="$old_IFS"

printf '</div>\n' >> "$BODY"
printf '<div class="ft">Generated by StatsServiceBook &middot; %s</div>\n' \
    "$(date '+%Y-%m-%d %H:%M')" >> "$BODY"
printf '</div>\n</body>\n</html>\n' >> "$BODY"

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

_send_failed=0
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
        && log "sent OK to $addr" \
        || { log "WARNING: failed to send to $addr"; _send_failed=1; }
done
IFS="$old_IFS"

log "done."
exit "$_send_failed"
