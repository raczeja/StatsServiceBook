# strava-my-bike-alert.sh — sourced by strava-my-activities.sh.
# Bike-service email threshold alerts (§6f).
# Variables read from caller scope: BIKE_EMAIL, BIKE_DATA, BIKE_EMAIL_STATE,
# WEB_DIR, STRAVA_EMAIL_SMTP, STRAVA_EMAIL_USER, STRAVA_EMAIL_FROM, WEB_URL.
# No variables are set back into caller scope.

if [ -n "$BIKE_EMAIL" ] && [ -f "$BIKE_DATA" ] && [ -f "$WEB_DIR/activities.json" ]; then
  if [ -z "${STRAVA_EMAIL_SMTP:-}" ] || [ -z "${STRAVA_EMAIL_USER:-}" ]; then
    log "bike alerts: STRAVA_EMAIL_SMTP / STRAVA_EMAIL_USER not set — skipping"
  else
    log "bike alerts: checking service thresholds..."
    [ -f "$BIKE_EMAIL_STATE" ] || printf '{}' > "$BIKE_EMAIL_STATE"
    TODAY=$(date +%Y-%m-%d)

    # jq computes the threshold % for every active part with emailAlert:true that
    # has at least one threshold configured. Outputs one line per service type:
    #   tier|bike_id|part_id|stype_id|bike_name|part_name|stype_name|pct|km|h|days
    # tier: 0=ok(<90%), 1=warn(90-99%), 2=alert(>=100%)
    _PARTS=$(jq -r --arg today "$TODAY" \
      --slurpfile acts "$WEB_DIR/activities.json" '
      def tonum: if type=="string" then tonumber else . end;
      def days_since(d):
        if (d==null or d=="") then 0
        else (($today|strptime("%Y-%m-%d")|mktime)-(d|strptime("%Y-%m-%d")|mktime))
             /86400|floor|if .<0 then 0 else . end
        end;
      def atd(st):
        ((st.alertTimeN//0)|tonum) as $n |
        if $n<=0 then 0
        else $n*((st.alertTimeUnit//"months")|
          if .=="weeks" then 7 elif .=="years" then 365 else 30 end)
        end;
      $acts[0].activities as $acts |
      .bikes[] |
      . as $bike |
      ($bike.gearId//"") as $gid |
      ($bike.isDefault//false) as $isd |
      (.parts//[])[] |
      select((.status//"new")!="archived" and (.emailAlert//false)) |
      . as $part |
      (.serviceTypes//[])[] |
      . as $st |
      select(($st.alertKm//0|tonum)>0 or ($st.alertH//0|tonum)>0 or ($st.alertTimeN//0|tonum)>0) |
      (($st.services//[])|sort_by(.date)|if length>0 then .[-1].date else null end) as $ld |
      ($ld//($part.installedDate//"")) as $from |
      [$acts[]|
        select(.sport_type=="Ride")|
        select($from=="" or .date>=$from)|
        select($gid=="" or .gear_id==$gid or ($isd and (.gear_id==null or .gear_id=="")))] as $rides |
      ($rides|map((.distance//0)|tonum)|add//0)/1000 as $km |
      ($rides|map((.moving_time//0)|tonum)|add//0)/3600 as $h |
      days_since($from) as $d |
      (($st.alertKm//0|tonum)|if .>0 then $km/.*100 else 0 end) as $pkm |
      (($st.alertH//0|tonum)|if .>0 then $h/.*100 else 0 end) as $ph |
      (atd($st)) as $ad |
      (if $ad>0 then $d/$ad*100 else 0 end) as $pd |
      [$pkm,$ph,$pd]|max as $pct |
      [
        (if $pct>=100 then 2 elif $pct>=90 then 1 else 0 end|tostring),
        ($bike.id//""),($part.id//""),($st.id//""),
        ($bike.name//""),($part.name//""),($st.name//""),
        ($pct|floor|tostring),
        ($km*10+.5|floor/10|tostring),
        ($h*10+.5|floor/10|tostring),
        ($d|tostring)
      ]|join("|")
    ' "$BIKE_DATA") || { log "bike alerts: jq failed — skipping"; _PARTS=""; }

    SEND_BODY=""
    NEW_STATE=$(cat "$BIKE_EMAIL_STATE")

    while IFS='|' read -r _tier _bid _pid _sid _bname _pname _sname _pct _km _h _days; do
      [ -z "$_tier" ] && continue
      _key="${_bid}|${_pid}|${_sid}"

      # Read stored tier/date for this key
      _stier=$(printf '%s' "$NEW_STATE" | jq -r --arg k "$_key" '(.[$k].tier//0)|tostring')
      _sdate=$(printf '%s' "$NEW_STATE" | jq -r --arg k "$_key" '.[$k].date//"" ')

      _send=0
      if [ "$_tier" -gt 0 ]; then
        if [ "$_tier" -gt "$_stier" ]; then
          _send=1  # threshold crossed or escalated
        elif [ "$_tier" -eq 2 ] && [ -n "$_sdate" ] && [ "$_sdate" != "" ]; then
          # re-alert weekly while still overdue
          _age=$(jq -n --arg t "$TODAY" --arg s "$_sdate" \
            '(($t|strptime("%Y-%m-%d")|mktime)-($s|strptime("%Y-%m-%d")|mktime))/86400|floor' \
            2>/dev/null || printf '0')
          [ "${_age:-0}" -ge 7 ] && _send=1
        fi
      fi

      if [ "$_send" -eq 1 ]; then
        case "$_tier" in
          2) _lvl="ALERT" ;;
          *) _lvl="WARN" ;;
        esac
        _line="[${_lvl}] ${_bname} / ${_pname} — ${_sname}: ${_pct}% of limit"
        [ "$_km" != "0" ] && [ "$_km" != "0.0" ] && _line="${_line} | ridden ${_km} km"
        [ "$_h"  != "0" ] && [ "$_h"  != "0.0" ] && _line="${_line} | time ${_h}h"
        [ "$_days" != "0" ] && _line="${_line} | ${_days} days elapsed"
        SEND_BODY="${SEND_BODY}${_line}
"
        NEW_STATE=$(printf '%s' "$NEW_STATE" | jq -c \
          --arg k "$_key" --argjson t "$_tier" --arg d "$TODAY" \
          '.[$k]={tier:$t,date:$d}')
      elif [ "$_tier" -eq 0 ] && [ "$_stier" -gt 0 ]; then
        # part was serviced — reset tier so it will warn again next time
        NEW_STATE=$(printf '%s' "$NEW_STATE" | jq -c --arg k "$_key" 'del(.[$k])')
      fi
    done << _PARTS_EOF
$_PARTS
_PARTS_EOF

    if [ -n "$SEND_BODY" ]; then
      _alert_ct=$(printf '%s' "$SEND_BODY" | grep -c '^\[ALERT\]' 2>/dev/null || printf '0')
      _warn_ct=$(printf '%s' "$SEND_BODY"  | grep -c '^\[WARN\]'  2>/dev/null || printf '0')
      if [ "${_alert_ct:-0}" -gt 0 ]; then
        _subj="[ALERT] Bike service overdue — ${_alert_ct} part(s) need attention"
      else
        _subj="[WARNING] Bike service due soon — ${_warn_ct} part(s) approaching limit"
      fi

      _smtp="${STRAVA_EMAIL_SMTP}"
      _smtp_auth="${_smtp#*://}"
      _smtp_host="${_smtp_auth%%:*}"
      _smtp_port="${_smtp_auth##*:}"
      [ "$_smtp_port" = "$_smtp_auth" ] && _smtp_port="465"
      _starttls="off"
      case "$_smtp" in smtp://*) _starttls="on" ;; esac
      _user="${STRAVA_EMAIL_USER%%:*}"
      _pass="${STRAVA_EMAIL_USER#*:}"
      _from="${STRAVA_EMAIL_FROM:-$_user}"

      _send_failed=0
      old_IFS="$IFS"; IFS=","
      for _addr in $BIKE_EMAIL; do
        _addr=$(printf '%s' "$_addr" | tr -d ' \t')
        [ -n "$_addr" ] || continue
        {
          printf 'From: %s\r\n' "$_from"
          printf 'To: %s\r\n' "$_addr"
          printf 'Subject: %s\r\n' "$_subj"
          printf 'Date: %s\r\n' "$(date '+%a, %d %b %Y %H:%M:%S %z')"
          printf 'MIME-Version: 1.0\r\n'
          printf 'Content-Type: text/plain; charset=utf-8\r\n'
          printf '\r\n'
          printf 'Bike Service Alert — %s\r\n\r\n' "$TODAY"
          printf '%s' "$SEND_BODY" | while IFS= read -r _l; do printf '%s\r\n' "$_l"; done
          printf '\r\nManage your bike: %s/bike.html\r\n' "${WEB_URL:-http://192.168.1.1/strava/me}"
        } | msmtp \
            --host="$_smtp_host" \
            --port="$_smtp_port" \
            --tls \
            --tls-starttls="$_starttls" \
            --auth=plain \
            --user="$_user" \
            --passwordeval="printf '%s' '$_pass'" \
            --from="$_from" \
            "$_addr" \
          && log "bike alerts: sent to $_addr" \
          || { log "bike alerts: failed to send to $_addr"; _send_failed=1; }
      done
      IFS="$old_IFS"
      [ "$_send_failed" -eq 0 ] || log "bike alerts: some sends failed"
    else
      log "bike alerts: no new threshold crossings"
    fi

    # Persist updated state (tier resets + new sends)
    printf '%s\n' "$NEW_STATE" > "$BIKE_EMAIL_STATE"
  fi
fi
