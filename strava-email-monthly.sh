#!/bin/sh
# strava-email-monthly / strava-email-weekly / strava-email-yearly — leaderboard emailer.
#
# The same binary is installed under three names; behavior is selected by name:
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
#   strava-email-yearly   — emails a full year-in-review on 1 January.
#     Cron (added by install.sh):
#       0 9 1 1 *  /usr/bin/strava-email-yearly >> /var/log/strava-email-yearly.log 2>&1
#     Recipients: STRAVA_EMAIL_YEARLY_TO (fallback: STRAVA_EMAIL_TO)
#     Test override: STRAVA_EMAIL_TEST_YEAR=2025 /usr/bin/strava-email-yearly
#     Content: club totals (km / acts / elevation / athletes / avg km/h),
#              top-5 athletes ranked by distance, single-activity highlights.
#
# SMTP settings come from /etc/strava-leaderboard.conf (shared by all modes).
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
case "$(basename "$0")" in *weekly*) _mode="weekly" ;; *yearly*) _mode="yearly" ;; esac

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
elif [ "$_mode" = "yearly" ]; then
    _recipients="${STRAVA_EMAIL_YEARLY_TO:-${STRAVA_EMAIL_WEEKLY_TO:-}}"
    if [ -z "$STRAVA_EMAIL_SMTP" ] || [ -z "$STRAVA_EMAIL_USER" ] || [ -z "$_recipients" ]; then
        log "STRAVA_EMAIL_SMTP / STRAVA_EMAIL_USER / STRAVA_EMAIL_YEARLY_TO not set in $CONFIG — skipping yearly email"
        exit 0
    fi
    if [ -n "${STRAVA_EMAIL_TEST_YEAR:-}" ]; then
        TARGET_YEAR="$STRAVA_EMAIL_TEST_YEAR"
    else
        TARGET_YEAR="$(($(date +%Y) - 1))"
    fi
    YEAR_LABEL="$TARGET_YEAR"
    _subject_suffix=" — Year in Review"
    _subheader_suffix=""
    _no_data_msg_suffix=" recorded for"
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

# Test-only recipient override: STRAVA_EMAIL_TEST_TO=you@example.com /usr/bin/strava-email-weekly
# Survives config sourcing because the conf never defines STRAVA_EMAIL_TEST_TO.
[ -n "${STRAVA_EMAIL_TEST_TO:-}" ] && _recipients="$STRAVA_EMAIL_TEST_TO"

# --- Month label (monthly/weekly) or year label (yearly) --------------------
if [ "$_mode" = "yearly" ]; then
    MONTH_LABEL="$YEAR_LABEL"
    log "building yearly year-in-review email for $TARGET_YEAR"
else
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
fi
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
EXCLUDE_ATHLETES="${STRAVA_EXCLUDE_ATHLETES:-}"
# jq preamble: builds $excl list and defines notExcluded filter (requires --arg exclude).
_JQ_EXCL_DEF='($exclude | if . == "" then [] else split(",") | map(ascii_downcase | ltrimstr(" ") | rtrimstr(" ")) | map(select(. != "")) end) as $excl | def notExcluded: ((.firstname // "" | ascii_downcase) + " " + (.lastname // "" | ascii_downcase)) as $name | (($excl | length) == 0 or ([$excl[] | select(. == $name)] | length == 0));'

TMP="$(mktemp -d /tmp/strava-email.XXXXXX)"
trap '_rc=$?; rm -rf "$TMP"; [ $_rc -ne 0 ] && log "FATAL: strava-email exited with code $_rc"' EXIT

BODY="$TMP/body.html"

# HTML shell: header + embedded CSS (inline-compatible for Gmail / Outlook web).
{
    printf '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    if [ "$_mode" = "yearly" ]; then
        printf '<title>Strava Year in Review - %s</title>' "$YEAR_LABEL"
    else
        printf '<title>Strava Leaderboard - %s%s</title>' "$MONTH_LABEL" "$_subject_suffix"
    fi
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
    printf '.yt{background:#1a1a1a;border-radius:4px;padding:4px 0;margin-bottom:12px}'
    printf '.ytc{display:inline-block;padding:10px 12px;text-align:center;min-width:80px}'
    printf '.ytv{font-size:20px;font-weight:700;color:#fc4c02;font-variant-numeric:tabular-nums}'
    printf '.ytl{font-size:10px;color:#aaa;margin-top:2px}'
    printf '.hl{background:#f9f9f9;border-radius:4px;margin-top:10px}'
    printf '.hlc{display:inline-block;padding:10px 12px;vertical-align:top;width:30%%;box-sizing:border-box}'
    printf '.hli{font-size:18px}'
    printf '.hlt{font-size:11px;font-weight:700;color:#555;margin:2px 0}'
    printf '.hln{font-size:11px;color:#222;font-weight:600}'
    printf '.hls{font-size:10px;color:#888}'
    printf '</style></head><body>\n<div class="w">\n'
    if [ "$_mode" = "yearly" ]; then
        printf '<div class="hd"><h1>&#127942; Year in Review %s</h1><p>Strava Club Annual Summary</p></div>\n' \
            "$YEAR_LABEL"
    else
        printf '<div class="hd"><h1>&#127942; Strava Leaderboard</h1><p>%s%s</p></div>\n' \
            "$MONTH_LABEL" "$_subheader_suffix"
    fi
    printf '<div class="cb">\n'
} > "$BODY"

# Inline styles — Outlook's Word renderer ignores <style> blocks; these must be on every element.
_TH='nowrap style="background:#fc4c02;color:#fff;padding:5px 6px;font-size:11px;white-space:nowrap;text-align:left"'
_THR='nowrap style="background:#fc4c02;color:#fff;padding:5px 6px;font-size:11px;white-space:nowrap;text-align:right"'
_TD='nowrap style="padding:5px 6px;font-size:11px;border-bottom:1px solid #eee;vertical-align:middle;white-space:nowrap"'
_TDR='nowrap style="padding:5px 6px;font-size:11px;border-bottom:1px solid #eee;vertical-align:middle;text-align:right;white-space:nowrap"'

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

    # ---- Yearly rendering (totals + top-5 + highlights) ---------------------
    if [ "$_mode" = "yearly" ]; then
        YTOTALS="$TMP/ytotals_${club_id}.tsv"
        YTOP5="$TMP/ytop5_${club_id}.tsv"
        YHL="$TMP/yhl_${club_id}.tsv"

        # Totals: km / acts / elev / athletes / avg_kmh / first-in-year / new-club(1=yes)
        jq -rn \
            --arg year "$TARGET_YEAR" \
            --arg merge "$MERGE_ATHLETES" \
            --arg exclude "$EXCLUDE_ATHLETES" \
            "$JQ_MERGE_FUNC$_JQ_EXCL_DEF"'
            [inputs | applyMerge | select(notExcluded)] | normArr as $store |
            ($store | map(select(.firstSeen | startswith($year)))) as $all |
            ($all | length) as $acts |
            ($all | map(.distance // 0) | add // 0) as $dist_m |
            ($all | map(.total_elevation_gain // 0) | add // 0) as $elev |
            ($all | map(.moving_time // 0) | add // 0) as $time_s |
            ($all | group_by("\(.firstname)|\(.lastname)") | length) as $ath |
            ($all | map(.firstSeen // "") | map(select(. != "")) | sort | .[0] // "") as $first_in_year |
            ($store | map(.firstSeen // "") | map(select(. != "")) | min // "") as $alltime_first |
            [
              (($dist_m / 1000 * 10 | round) / 10 | tostring),
              ($acts | tostring),
              ($elev | round | tostring),
              ($ath | tostring),
              (if $time_s > 0 then ($dist_m / $time_s * 3.6 * 10 | round) / 10 else 0 end | tostring),
              $first_in_year,
              (if $alltime_first < $year then "0" else "1" end)
            ] | @tsv' \
            "$NDJSON" > "$YTOTALS" \
            || log "WARNING: jq failed building yearly totals for club $club_id"

        # Top 5: rank / name / km / time_h / time_m / elev / acts / km/h
        jq -rn \
            --arg year "$TARGET_YEAR" \
            --arg merge "$MERGE_ATHLETES" \
            --arg exclude "$EXCLUDE_ATHLETES" \
            "$JQ_MERGE_FUNC$_JQ_EXCL_DEF"'
            [inputs | applyMerge | select(notExcluded) | select(.firstSeen | startswith($year))]
            | normArr | group_by("\(.firstname)|\(.lastname)")
            | map({
                name: "\(.[0].firstname) \(.[0].lastname)",
                dist: (([.[].distance // 0] | add) / 1000),
                time_s: ([.[].moving_time // 0] | add),
                elev: (([.[].total_elevation_gain // 0] | add) | round),
                cnt: length
              })
            | sort_by(-.dist)
            | .[0:5]
            | to_entries[]
            | [
                (.key + 1 | tostring),
                (.value.name | @html),
                ((.value.dist * 10 | round) / 10 | tostring),
                (.value.time_s / 3600 | floor | tostring),
                (.value.time_s % 3600 / 60 | floor | tostring),
                (.value.elev | tostring),
                (.value.cnt | tostring),
                (if .value.time_s > 0 then
                   (.value.dist / (.value.time_s / 3600) * 10 | round) / 10
                 else 0 end | tostring)
              ]
            | @tsv' \
            "$NDJSON" > "$YTOP5" \
            || log "WARNING: jq failed building yearly top-5 for club $club_id"

        # Highlights: type / name / value / unit / sport
        jq -rn \
            --arg year "$TARGET_YEAR" \
            --arg merge "$MERGE_ATHLETES" \
            --arg exclude "$EXCLUDE_ATHLETES" \
            "$JQ_MERGE_FUNC$_JQ_EXCL_DEF"'
            ([inputs | applyMerge | select(notExcluded) | select(.firstSeen | startswith($year))] | normArr) as $yr_all |
            ($yr_all | map(select((.distance // 0) > 1000))) as $all |
            ($yr_all | group_by("\(.firstname)|\(.lastname)") | sort_by(-length) | .[0]) as $mact |
            ($yr_all | group_by("\(.firstname)|\(.lastname)") | map({name: "\(.[0].firstname // "") \(.[0].lastname // "")", elev: ([.[].total_elevation_gain // 0] | add)}) | sort_by(-.elev) | .[0]) as $tclimb |
            ($all | sort_by(if (.moving_time // 0) > 0 then -(.distance / .moving_time) else 0 end) | .[0]) as $fast |
            ($all | sort_by(-(.distance // 0)) | .[0]) as $long |
            ($all | sort_by(-(.total_elevation_gain // 0)) | .[0]) as $elev |
            (
              if $mact != null then
                "mostactive",
                (("\($mact[0].firstname // "") \($mact[0].lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
                ($mact | length | tostring),
                "activities",
                ""
              else empty end
            ),
            (
              if $tclimb != null and ($tclimb.elev // 0) > 0 then
                "topclimber",
                ($tclimb.name | @html),
                ($tclimb.elev | round | tostring),
                "m total",
                ""
              else empty end
            ),
            (
              if $fast != null then
                "fastest",
                (("\($fast.firstname // "") \($fast.lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
                (if ($fast.moving_time // 0) > 0 then ($fast.distance / $fast.moving_time * 3.6 * 10 | round) / 10 else 0 end | tostring),
                "km/h",
                (($fast.sport_type // "") | @html)
              else empty end
            ),
            (
              if $long != null then
                "longest",
                (("\($long.firstname // "") \($long.lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
                ((($long.distance // 0) / 1000 * 10 | round) / 10 | tostring),
                "km",
                (($long.sport_type // "") | @html)
              else empty end
            ),
            (
              if $elev != null then
                "mostelev",
                (("\($elev.firstname // "") \($elev.lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
                (($elev.total_elevation_gain // 0) | round | tostring),
                "m",
                (($elev.sport_type // "") | @html)
              else empty end
            )' \
            "$NDJSON" > "$YHL" \
            || log "WARNING: jq failed building yearly highlights for club $club_id"

        if [ ! -s "$YTOP5" ]; then
            printf '<p class="nd">No activities recorded for %s.</p>' "$TARGET_YEAR" >> "$BODY"
            continue
        fi

        # Year in Numbers block
        if [ -s "$YTOTALS" ]; then
            IFS="$(printf '\t')" read -r _ykm _yacts _yelev _yath _yavg _yfirst _ynewclub < "$YTOTALS" || true
            {
                printf '<div style="padding:12px 16px 4px">'
                printf '<div style="font-size:10px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px">Year in Numbers</div>'
                printf '<table style="width:100%%;border-collapse:collapse;background:#f5f5f5;border-radius:4px"><tr>'
                _yn_cell() { printf '<td style="text-align:center;padding:10px 6px;border-right:1px solid #e0e0e0"><div style="font-size:18px;font-weight:700;color:#fc4c02">%s</div><div style="font-size:10px;color:#888;margin-top:2px">%s</div></td>' "$1" "$2"; }
                _yn_cell "$_ykm"   "km"
                _yn_cell "$_yacts" "activities"
                _yn_cell "$_yelev" "m elev"
                _yn_cell "$_yath"  "athletes"
                _yn_cell "$_yavg"  "avg km/h"
                printf '</tr></table></div>\n'
            } >> "$BODY"
        fi

        # Top 5 table
        {
            printf '<div style="padding:4px 16px 10px">'
            printf '<div style="font-size:10px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.06em;margin:8px 0 6px">Top 5 &middot; %s%s</div>' \
                "$TARGET_YEAR" \
                "$([ "${_ynewclub:-0}" = "1" ] && [ -n "${_yfirst:-}" ] && printf ' <span style="font-weight:400;text-transform:none;letter-spacing:0">since %s</span>' "$_yfirst")"
            printf '<table style="width:100%%;border-collapse:collapse;font-size:11px">\n<thead><tr>\n'
            printf '<th %s width="26">#</th><th %s>Athlete</th>' "$_TH" "$_TH"
            printf '<th %s width="60">km</th><th %s width="68">Time</th>' "$_THR" "$_THR"
            printf '<th %s width="52">m&#8593;</th><th %s width="38">Acts</th><th %s width="48">km/h</th>' "$_THR" "$_THR" "$_THR"
            printf '</tr></thead><tbody>\n'
        } >> "$BODY"

        while IFS="$(printf '\t')" read -r _yr _yn _yd _yth _ytm _yel _yc _ya; do
            _ytm_pad="$(printf '%02d' "$_ytm")"
            case "$_yr" in
                1) _ym="&#129351;" ;; 2) _ym="&#129352;" ;; 3) _ym="&#129353;" ;;
                *) _ym="$_yr" ;;
            esac
            _yr_style="$_TD"
            [ "$_yr" = "1" ] && _yr_style='nowrap style="padding:5px 6px;font-size:11px;border-bottom:1px solid #eee;vertical-align:middle;white-space:nowrap;color:#fc4c02;font-weight:700"'
            printf '<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%sh&thinsp;%sm</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>\n' \
                "$_yr_style" "$_ym" "$_TD" "$_yn" "$_TDR" "$_yd" \
                "$_TDR" "$_yth" "$_ytm_pad" "$_TDR" "$_yel" "$_TDR" "$_yc" "$_TDR" "$_ya" >> "$BODY"
        done < "$YTOP5"

        printf '</tbody></table></div>\n' >> "$BODY"

        # Single-activity highlights
        if [ -s "$YHL" ]; then
            {
                printf '<div style="padding:0 16px 14px">'
                printf '<div style="font-size:10px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px">Highlights</div>'
                printf '<table style="width:100%%;border-collapse:collapse"><tr>'
            } >> "$BODY"

            while IFS= read -r _htype && \
                  IFS= read -r _hname && \
                  IFS= read -r _hval  && \
                  IFS= read -r _hunit && \
                  IFS= read -r _hsport; do
                case "$_htype" in
                    mostactive) _hicon="&#128293;"; _hlabel="Most Active"      ;;
                    topclimber) _hicon="&#128304;"; _hlabel="Top Climber"      ;;
                    fastest)    _hicon="&#9889;" ; _hlabel="Fastest Single"    ;;
                    longest)    _hicon="&#128207;"; _hlabel="Longest Single"   ;;
                    mostelev)   _hicon="&#127956;"; _hlabel="Best Elev. Single" ;;
                    *)          _hicon="&#9679;"  ; _hlabel="$_htype"           ;;
                esac
                printf '<td style="padding:10px 10px;vertical-align:top;border:1px solid #eee;border-radius:4px"><div style="font-size:18px;line-height:1.2">%s</div><div style="font-size:9px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.06em;margin:3px 0 2px">%s</div><div style="font-size:15px;font-weight:700;color:#fc4c02;line-height:1.1">%s %s</div><div style="font-size:10px;color:#444;margin-top:2px">%s</div>%s</td>' \
                    "$_hicon" "$_hlabel" "$_hval" "$_hunit" "$_hname" \
                    "$([ -n "$_hsport" ] && printf '<div style="font-size:9px;color:#aaa">%s</div>' "$_hsport")" >> "$BODY"
            done < "$YHL"

            printf '</tr></table></div>\n' >> "$BODY"
        fi

        continue
    fi
    # ---- End yearly rendering ------------------------------------------------

    TABLE="$TMP/table_${club_id}.tsv"
    MHL="$TMP/mhl_${club_id}.txt"
    if [ "$_mode" = "weekly" ]; then
        jq -rn \
            --arg month "$TARGET_MONTH" \
            --arg wfrom "$LAST_WEEK_FROM" \
            --arg wto   "$LAST_WEEK_TO" \
            --arg merge "$MERGE_ATHLETES" \
            --arg exclude "$EXCLUDE_ATHLETES" \
            "$JQ_MERGE_FUNC$_JQ_EXCL_DEF"'[ inputs | applyMerge | select(notExcluded) ] | normArr as $all
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
            "$NDJSON" > "$TABLE" || log "WARNING: jq failed building weekly email table for club $club_id — table may be empty"
    else
        jq -rn \
            --arg month "$TARGET_MONTH" \
            --arg merge "$MERGE_ATHLETES" \
            --arg exclude "$EXCLUDE_ATHLETES" \
            "$JQ_MERGE_FUNC$_JQ_EXCL_DEF"'[inputs | applyMerge | select(notExcluded) | select(.firstSeen | startswith($month))]
             | normArr | group_by("\(.firstname)|\(.lastname)")
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
            "$NDJSON" > "$TABLE" || log "WARNING: jq failed building monthly email table for club $club_id — table may be empty"
    fi
    log "club $club_id: $(wc -l < "$TABLE" 2>/dev/null | tr -d ' ') athletes in table"

    # Monthly/weekly highlights: most-active / top-climber / fastest / longest / most-elevation
    jq -rn \
        --arg month "$TARGET_MONTH" \
        --arg merge "$MERGE_ATHLETES" \
        --arg exclude "$EXCLUDE_ATHLETES" \
        "$JQ_MERGE_FUNC$_JQ_EXCL_DEF"'
        ([inputs | applyMerge | select(notExcluded) | select(.firstSeen | startswith($month))] | normArr) as $all |
        ($all | group_by("\(.firstname)|\(.lastname)") | sort_by(-length) | .[0]) as $mact |
        ($all | group_by("\(.firstname)|\(.lastname)") | map({name: "\(.[0].firstname // "") \(.[0].lastname // "")", elev: ([.[].total_elevation_gain // 0] | add)}) | sort_by(-.elev) | .[0]) as $tclimb |
        ($all | map(select((.moving_time // 0) > 0 and (.distance // 0) > 1000)) | sort_by(-(.distance / .moving_time)) | .[0]) as $fast |
        ($all | sort_by(-(.distance // 0)) | .[0]) as $long |
        ($all | sort_by(-(.total_elevation_gain // 0)) | .[0]) as $elev |
        (
          if $mact != null then
            "mostactive",
            (("\($mact[0].firstname // "") \($mact[0].lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
            ($mact | length | tostring),
            "activities",
            ""
          else empty end
        ),
        (
          if $tclimb != null and ($tclimb.elev // 0) > 0 then
            "topclimber",
            ($tclimb.name | @html),
            ($tclimb.elev | round | tostring),
            "m total",
            ""
          else empty end
        ),
        (
          if $fast != null then
            "fastest",
            (("\($fast.firstname // "") \($fast.lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
            (($fast.distance / $fast.moving_time * 3.6 * 10 | round) / 10 | tostring),
            "km/h",
            (($fast.sport_type // "") | @html)
          else empty end
        ),
        (
          if $long != null then
            "longest",
            (("\($long.firstname // "") \($long.lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
            ((($long.distance // 0) / 1000 * 10 | round) / 10 | tostring),
            "km",
            (($long.sport_type // "") | @html)
          else empty end
        ),
        (
          if $elev != null then
            "mostelev",
            (("\($elev.firstname // "") \($elev.lastname // "")") | ltrimstr(" ") | rtrimstr(" ") | @html),
            (($elev.total_elevation_gain // 0) | round | tostring),
            "m",
            (($elev.sport_type // "") | @html)
          else empty end
        )' \
        "$NDJSON" > "$MHL" || log "WARNING: jq failed building monthly highlights for club $club_id"

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

    # Highlights block
    if [ -s "$MHL" ]; then
        {
            printf '<div style="padding:0 16px 14px">'
            printf '<div style="font-size:10px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px">Highlights</div>'
            printf '<table style="width:100%%;border-collapse:collapse"><tr>'
        } >> "$BODY"
        while IFS= read -r _htype && \
              IFS= read -r _hname && \
              IFS= read -r _hval  && \
              IFS= read -r _hunit && \
              IFS= read -r _hsport; do
            case "$_htype" in
                mostactive) _hicon="&#128293;"; _hlabel="Most Active"       ;;
                topclimber) _hicon="&#128304;"; _hlabel="Top Climber"       ;;
                fastest)    _hicon="&#9889;" ; _hlabel="Fastest Single"     ;;
                longest)    _hicon="&#128207;"; _hlabel="Longest Single"    ;;
                mostelev)   _hicon="&#127956;"; _hlabel="Best Elev. Single" ;;
                *)          _hicon="&#9679;"  ; _hlabel="$_htype"           ;;
            esac
            printf '<td style="padding:10px 10px;vertical-align:top;border:1px solid #eee;border-radius:4px"><div style="font-size:18px;line-height:1.2">%s</div><div style="font-size:9px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.06em;margin:3px 0 2px">%s</div><div style="font-size:15px;font-weight:700;color:#fc4c02;line-height:1.1">%s %s</div><div style="font-size:10px;color:#444;margin-top:2px">%s</div>%s</td>' \
                "$_hicon" "$_hlabel" "$_hval" "$_hunit" "$_hname" \
                "$([ -n "$_hsport" ] && printf '<div style="font-size:9px;color:#aaa">%s</div>' "$_hsport")" >> "$BODY"
        done < "$MHL"
        printf '</tr></table></div>\n' >> "$BODY"
    fi
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
