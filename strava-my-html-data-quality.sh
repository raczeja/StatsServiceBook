# strava-my-html-data-quality.sh - sourced by strava-render-pages.sh.
# Writes $WEB_DIR/data-quality.html and the trigger-sync CGI.

mkdir -p "$CGI_DIR"
cat > "$CGI_DIR/trigger-sync" <<'CGI'
#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
[ "$REQUEST_METHOD" = "POST" ] || { printf '{"ok":false,"error":"POST required"}\n'; exit 0; }
read -r _body 2>/dev/null || true
_src="${_body#*source=}"; _src="${_src%%&*}"
case "$_src" in
  strava)      _cmd=/usr/bin/strava-my-activities ;;
  healthsync)  _cmd=/usr/bin/healthsync-activities ;;
  leaderboard) _cmd=/usr/bin/strava-leaderboard ;;
  *) printf '{"ok":false,"error":"unknown source"}\n'; exit 0 ;;
esac
[ -x "$_cmd" ] || { printf '{"ok":false,"error":"not found"}\n'; exit 0; }
setsid "$_cmd" < /dev/null > /dev/null 2>&1 &
printf '{"ok":true,"source":"%s"}\n' "$_src"
CGI
chmod 0755 "$CGI_DIR/trigger-sync"
log "wrote $CGI_DIR/trigger-sync"

{
  printf 'MY_CONF="/etc/strava-my-activities.conf"\n'
  printf 'LB_CONF="/etc/strava-leaderboard.conf"\n'
  printf 'MY_STATE_DIR="%s"\n' "$STATE_DIR"
  cat <<'CGI'
#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
[ "$REQUEST_METHOD" = "POST" ] || { printf '{"ok":false,"error":"POST required"}\n'; exit 0; }
read -r _body 2>/dev/null || true
_cookie="$(printf '%s' "$_body" | jq -r '.cookie // empty' 2>/dev/null)"
[ -n "$_cookie" ] || { printf '{"ok":false,"error":"missing cookie value"}\n'; exit 0; }
_updated=0
for _conf in "$MY_CONF" "$LB_CONF"; do
  [ -f "$_conf" ] || continue
  grep -q '^STRAVA_SESSION_COOKIE=' "$_conf" || continue
  _tmp="${_conf}.tmp.$$"
  while IFS= read -r _line; do
    case "$_line" in
      STRAVA_SESSION_COOKIE=*) printf 'STRAVA_SESSION_COOKIE="%s"\n' "$_cookie" ;;
      *) printf '%s\n' "$_line" ;;
    esac
  done < "$_conf" > "$_tmp" && mv "$_tmp" "$_conf" && _updated=$((_updated+1))
done
[ "$_updated" -gt 0 ] || { printf '{"ok":false,"error":"STRAVA_SESSION_COOKIE not found in config"}\n'; exit 0; }
_lb_state="$(grep '^STRAVA_STATE_DIR=' "$LB_CONF" 2>/dev/null | tail -1)"
_lb_state="${_lb_state#*=}"; _lb_state="${_lb_state#\"}"; _lb_state="${_lb_state%\"}"
_lb_state="${_lb_state:-/usr/lib/strava-leaderboard}"
for _sd in "$MY_STATE_DIR" "$_lb_state"; do
  [ -d "$_sd" ] || continue
  rm -f "$_sd/strava_session_age.txt" "$_sd/strava_csrf.txt"
done
printf '{"ok":true,"updated":%d}\n' "$_updated"
CGI
} > "$CGI_DIR/update-cookie"
chmod 0755 "$CGI_DIR/update-cookie"
log "wrote $CGI_DIR/update-cookie"

cat > "$CGI_DIR/send-email" <<'CGI'
#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
[ "$REQUEST_METHOD" = "POST" ] || { printf '{"ok":false,"error":"POST required"}\n'; exit 0; }
read -r _body 2>/dev/null || true
_type="$(printf '%s' "$_body" | jq -r '.type // empty' 2>/dev/null)"
_to="$(printf '%s' "$_body" | jq -r '.email_to // empty' 2>/dev/null)"
_period="$(printf '%s' "$_body" | jq -r '.period // empty' 2>/dev/null)"
case "$_type" in
  monthly) _cmd=/usr/bin/strava-email-monthly; _penv=STRAVA_EMAIL_TEST_MONTH ;;
  weekly)  _cmd=/usr/bin/strava-email-weekly;  _penv=STRAVA_WEEKLY_TEST_MONTH ;;
  yearly)  _cmd=/usr/bin/strava-email-yearly;  _penv=STRAVA_EMAIL_TEST_YEAR ;;
  *) printf '{"ok":false,"error":"unknown email type"}\n'; exit 0 ;;
esac
[ -x "$_cmd" ] || { printf '{"ok":false,"error":"script not found"}\n'; exit 0; }
set --
[ -n "$_to"     ] && set -- "$@" "STRAVA_EMAIL_TEST_TO=$_to"
[ -n "$_period" ] && set -- "$@" "$_penv=$_period"
if [ "$#" -gt 0 ]; then
  setsid env "$@" "$_cmd" < /dev/null > /dev/null 2>&1 &
else
  setsid "$_cmd" < /dev/null > /dev/null 2>&1 &
fi
printf '{"ok":true,"type":"%s"}\n' "$_type"
CGI
chmod 0755 "$CGI_DIR/send-email"
log "wrote $CGI_DIR/send-email"

log "html: writing data-quality.html..."
cat > "$WEB_DIR/data-quality.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t;</script>
<title>Data Quality - My Activities</title>
<style>
:root{--bg:#fafafa;--surface:#fff;--text:#222;--muted:#666;--border:#ddd;--accent:#fc4c02;--warn:#a65d00;--warn-bg:#fff4d6;--bad:#b42318;--bad-bg:#fde8e7;--good:#287a3e;--good-bg:#e7f4e9}
@media(prefers-color-scheme:dark){:root{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--muted:#aaa;--border:#444;--warn:#ffbd55;--warn-bg:#352600;--bad:#ff938b;--bad-bg:#3a1110;--good:#86d797;--good-bg:#102b16}}
[data-theme=light]{--bg:#fafafa;--surface:#fff;--text:#222;--muted:#666;--border:#ddd;--warn:#a65d00;--warn-bg:#fff4d6;--bad:#b42318;--bad-bg:#fde8e7;--good:#287a3e;--good-bg:#e7f4e9}
[data-theme=dark]{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--muted:#aaa;--border:#444;--warn:#ffbd55;--warn-bg:#352600;--bad:#ff938b;--bad-bg:#3a1110;--good:#86d797;--good-bg:#102b16}
body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1100px;padding:0 1rem;background:var(--bg);color:var(--text)}
a{color:var(--accent)}h1{margin:.2rem 0 .4rem;font-size:1.7rem}.meta{color:var(--muted);font-size:.88rem;margin:1rem 0}#hdr{display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem}#theme-tog{margin-left:auto;flex-shrink:0;background:none;border:none;font-size:1.2rem;cursor:pointer;line-height:1;padding:.2rem .4rem;border-radius:.3rem;color:var(--text)}
.nav{margin:.25rem 0 1rem;display:flex;flex-wrap:wrap;gap:.4rem}.nav a{padding:.4rem .75rem;background:#fc4c02;color:#fff;text-decoration:none;border-radius:.4rem;font-size:.85rem;font-weight:600;flex:0 0 auto;text-align:center}.nav a:hover{background:#e34402}
.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.65rem;margin:1rem 0 1.5rem}.metric,.source{background:var(--surface);border:1px solid var(--border);padding:.8rem 1rem;border-radius:4px}.metric strong{display:block;font-size:1.45rem;font-variant-numeric:tabular-nums}.metric span{color:var(--muted);font-size:.85rem}
.sources{display:grid;grid-template-columns:1fr;gap:.65rem;margin-bottom:1.5rem}.source h2{font-size:1rem;margin:0 0 .5rem}.source p{margin:.25rem 0;font-size:.9rem;overflow-wrap:anywhere}.badge{display:inline-block;font-size:.78rem;font-weight:650;padding:.15rem .45rem;border-radius:3px;background:var(--good-bg);color:var(--good)}.badge.warn{background:var(--warn-bg);color:var(--warn)}.badge.bad{background:var(--bad-bg);color:var(--bad)}
h2{font-size:1.1rem;margin:1rem 0 .5rem}.table-wrap{overflow-x:auto;border:1px solid var(--border);background:var(--surface)}table{border-collapse:collapse;width:100%;min-width:650px}th,td{text-align:left;padding:.55rem .7rem;border-bottom:1px solid var(--border);vertical-align:top}th{font-size:.8rem;color:var(--muted);font-weight:600}td{font-size:.88rem}.issues{color:var(--bad)}.empty{color:var(--good);padding:1rem;background:var(--good-bg)}#state{color:var(--muted);margin:.75rem 0}
.issue-filters{display:flex;flex-wrap:wrap;gap:1rem;margin:.5rem 0 1rem}.issue-filters label{display:inline-flex;align-items:center;gap:.35rem;font-size:.9rem;cursor:pointer}.issue-filters input{accent-color:var(--accent);margin:0}
@media(max-width:650px){body{margin:.8rem auto}.summary{grid-template-columns:repeat(2,minmax(0,1fr))}h1{font-size:1.35rem}}
.run-log{font-size:.75rem;white-space:pre-wrap;word-break:break-all;margin:.5rem 0 0;padding:.5rem;background:var(--bg);border:1px solid var(--border);border-radius:3px;max-height:200px;overflow-y:auto;line-height:1.4}
.sync-btn{margin-top:.7rem;padding:.35rem .8rem;background:var(--accent);color:#fff;border:none;border-radius:.3rem;font-size:.82rem;font-weight:600;cursor:pointer;display:inline-block}.sync-btn:hover{opacity:.85}.sync-btn:disabled{opacity:.5;cursor:not-allowed}
.ck-ok{background:var(--good-bg);color:var(--good);border:1px solid var(--good)}.ck-warn{background:var(--warn-bg);color:var(--warn);border:1px solid var(--warn);font-weight:600}.ck-expired{background:var(--bad-bg);color:var(--bad);border:1px solid var(--bad);font-weight:600}
#cookie-update-card textarea{width:100%;box-sizing:border-box;font-family:monospace;font-size:.8rem;padding:.4rem;border:1px solid var(--border);background:var(--bg);color:var(--text);border-radius:.3rem;resize:vertical}
#cookie-save-status.ok{color:var(--good)}#cookie-save-status.err{color:var(--bad)}
#send-email-card input[type=text],#send-email-card select{font-family:system-ui,Arial,sans-serif;font-size:.85rem;padding:.35rem .5rem;border:1px solid var(--border);background:var(--bg);color:var(--text);border-radius:.3rem}#send-email-card input[type=text]{width:100%;box-sizing:border-box}
#email-period-sel{font-family:system-ui,Arial,sans-serif;font-size:.85rem;padding:.35rem .5rem;border:1px solid var(--border);background:var(--bg);color:var(--text);border-radius:.3rem;color-scheme:light}
[data-theme=dark] #email-period-sel{color-scheme:dark}
#send-email-status.ok{color:var(--good)}#send-email-status.err{color:var(--bad)}
#email-to-override.invalid{border-color:var(--bad)!important;outline:none}
</style>
</head>
<body>
<div id="hdr"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="36" height="36" aria-hidden="true"><defs><clipPath id="clip"><circle cx="32" cy="32" r="30"/></clipPath><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs><circle cx="32" cy="32" r="32" fill="url(#bg)"/><g clip-path="url(#clip)"><polygon points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32 60,56 4,56" fill="#fc4c02" fill-opacity="0.15"/><polyline points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32" fill="none" stroke="#fc4c02" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="46" r="2.5" fill="#fc4c02"/><circle cx="60" cy="32" r="2.5" fill="#fc4c02"/></g><path d="M43,13 Q50,7 57,13" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.45"/><path d="M46,17 Q50,13 54,17" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/><circle cx="50" cy="21" r="2.2" fill="#fc4c02"/><circle cx="32" cy="32" r="31" fill="none" stroke="#fc4c02" stroke-width="0.8" stroke-opacity="0.35"/></svg><h1 style="margin:0">&#128203; Data completeness</h1><button id="theme-tog">🌙</button></div>
<div class="nav"><a href="index.html">&#8592; My Activities</a> <a href="bike.html">🔧 Bike service</a> <a href="stats.html">📊 My Stats</a> <a href="heatmap.html">&#128506; Heatmap</a> <a id="leaderboard-link" href="../" style="display:none">🏆 Club leaderboard</a></div>
<div id="state">Loading activity and synchronization data...</div>
<section class="summary" aria-label="Activity data completeness">
  <div class="metric"><strong id="count-total">-</strong><span>Activities checked</span></div>
  <div class="metric"><strong id="count-gps">-</strong><span>Without GPS</span></div>
  <div class="metric"><strong id="count-hr">-</strong><span>Without heart rate</span></div>
  <div class="metric"><strong id="count-detail">-</strong><span>Without details</span></div>
</section>
<div style="display:flex;align-items:center;gap:.75rem;margin:1rem 0 .5rem"><h2 style="margin:0">Latest synchronization</h2><button id="sync-all-btn" class="sync-btn" style="margin:0" onclick="syncAll()">&#8635; Sync all</button></div>
<section class="sources" id="sources"><div class="source">Loading source status...</div></section>
<section id="email-status" style="display:none">
<h2>Email</h2>
<div id="email-cards" class="sources"></div>
<article class="source" id="send-email-card">
<h2>Send email now</h2>
<div style="display:flex;flex-wrap:wrap;align-items:flex-end;gap:.6rem;margin:.4rem 0">
  <div><label style="font-size:.8rem;color:var(--muted);display:block;margin-bottom:.2rem">Type</label><select id="email-type-sel" onchange="updatePeriodInput()"><option value="monthly">Monthly</option><option value="weekly">Weekly</option><option value="yearly">Yearly</option></select></div>
  <div id="email-period-wrap" style="flex-shrink:0"><label style="font-size:.8rem;color:var(--muted);display:block;margin-bottom:.2rem">Period</label><input id="email-period-sel" type="month" style="width:9rem"></div>
  <div style="flex:1;min-width:160px"><label style="font-size:.8rem;color:var(--muted);display:block;margin-bottom:.2rem">Override recipients (optional)</label><input type="email" id="email-to-override" autocomplete="email" placeholder="you@example.com — leave empty for defaults" style="width:100%;box-sizing:border-box"></div>
  <button class="sync-btn" style="margin:0;flex-shrink:0" onclick="sendEmail()">&#9993; Send</button>
</div>
<div id="send-email-status" style="font-size:.88rem"></div>
</article>
</section>
<section id="cookie-status" style="display:none">
<h2>Session cookie</h2>
<div id="cookie-cards" class="sources"></div>
<article class="source" id="cookie-update-card">
<h2>Update <code>_strava4_session</code> cookie</h2>
<p style="font-size:.9rem">Paste the cookie value from browser DevTools (Application &rarr; Cookies &rarr; strava.com &rarr; <code>_strava4_session</code>). Updates both My Activities and Club Leaderboard configs.</p>
<textarea id="cookie-input" rows="3" placeholder="Paste _strava4_session value here..."></textarea>
<div style="margin:.5rem 0"><button class="sync-btn" style="margin:0" onclick="saveCookie()">Save cookie</button></div>
<div id="cookie-save-status" style="font-size:.88rem"></div>
</article>
</section>
<h2>Activities requiring attention</h2>
<div class="issue-filters" role="group" aria-label="Filter missing data">
  <label><input id="filter-gps" type="checkbox" checked> GPS</label>
  <label><input id="filter-heart-rate" type="checkbox"> Heart rate</label>
  <label><input id="filter-details" type="checkbox" checked> Details</label>
</div>
<div id="activity-list"></div>
<p class="meta" id="generated"></p>
<script>
"use strict";
var staleAfter=48*60*60;
var GPS_OPTIONAL={'Swim':1,'Badminton':1,'Squash':1,'TableTennis':1,'WeightTraining':1,'Yoga':1,'Pilates':1,'Workout':1,'Elliptical':1,'StairStepper':1,'RockClimbing':1,'Crossfit':1,'CoreTraining':1,'HighIntensityIntervalTraining':1,'MartialArts':1,'Boxing':1,'Volleyball':1,'Basketball':1,'Soccer':1,'Tennis':1};
function esc(value){return String(value==null?"":value).replace(/[&<>"']/g,function(ch){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch];});}
function stamp(value){if(!value)return "not recorded";var date=new Date(Number(value)*1000);return isNaN(date.getTime())?"not recorded":date.toLocaleString();}
function timeAgo(secs){if(!secs||secs<0)return '';if(secs<120)return 'just now';if(secs<3600)return Math.floor(secs/60)+'m ago';if(secs<86400)return Math.floor(secs/3600)+'h ago';var d=Math.floor(secs/86400);if(d<30)return d+'d ago';var mo=Math.floor(d/30);if(mo<12)return mo+'mo ago';return Math.floor(mo/12)+'y ago';}
function renderActivityList(activities){
  var showGps=document.getElementById('filter-gps').checked;
  var showHeartRate=document.getElementById('filter-heart-rate').checked;
  var showDetails=document.getElementById('filter-details').checked;
  var rows=[];
  activities.forEach(function(a){
    var problems=[];
    if(showDetails&&a.detail!==true)problems.push('Details');
    if(showGps&&a.has_gps===false&&!GPS_OPTIONAL[a.sport_type])problems.push('GPS');
    if(showHeartRate&&!(Number(a.average_heartrate)>0))problems.push('Heart rate');
    if(!problems.length)return;
    rows.push('<tr><td>'+esc(a.date||'-')+'</td><td><a href="activity.html?id='+encodeURIComponent(a.id)+'">'+esc(a.name||'Unnamed activity')+'</a></td><td>'+esc(a.sport_type||'-')+'</td><td class="issues">'+problems.join(', ')+'</td></tr>');
  });
  document.getElementById('activity-list').innerHTML=rows.length?'<div class="table-wrap"><table><thead><tr><th>Date</th><th>Activity</th><th>Sport</th><th>Missing data</th></tr></thead><tbody>'+rows.join('')+'</tbody></table></div>':'<p class="empty">No activities match the selected missing-data filters.</p>';
}
var SYNC_STATUS_URLS={strava:'strava-sync-status.json',healthsync:'healthsync-sync-status.json',leaderboard:'../leaderboard-sync-status.json'};
var SYNC_LIVE_LOG_URLS={strava:'strava-sync-live.log',healthsync:'healthsync-sync-live.log',leaderboard:'../leaderboard-sync-live.log'};
var SYNC_RUNNING_URLS={strava:'strava-sync-running',healthsync:'healthsync-sync-running',leaderboard:'../leaderboard-sync-running'};
var SRC_NAMES={strava:'Strava',healthsync:'HealthSync',leaderboard:'Club leaderboard'};
var _knownAttempt={strava:0,healthsync:0,leaderboard:0};
function _renderLogEl(el,lines,label){
  var previous=el.querySelector('pre.run-log');
  var shouldFollow=!previous||previous.scrollHeight-previous.clientHeight-previous.scrollTop<=24;
  var previousScrollTop=previous?previous.scrollTop:0;
  el.innerHTML='<details open><summary style="cursor:pointer;font-size:.85rem;color:var(--muted)">'+label+' ('+lines.length+' lines)</summary><pre class="run-log">'+lines.map(function(l){return esc(l);}).join('\n')+'</pre></details>';
  var pre=el.querySelector('pre.run-log');if(pre)pre.scrollTop=shouldFollow?pre.scrollHeight:previousScrollTop;
}
function refreshSourceCard(src,name,status){
  var logEl=document.getElementById('log-section-'+src);
  if(!logEl)return;
  var article=logEl.closest('article');
  if(!article||!article.parentNode)return;
  var tmp=document.createElement('div');
  tmp.innerHTML=sourceCard(name,status,src);
  var newEl=tmp.firstElementChild;
  if(newEl)article.parentNode.replaceChild(newEl,article);
}
function updateLogSection(srcKey,status){
  var el=document.getElementById('log-section-'+srcKey);
  if(!el||!status||!status.log||!status.log.length)return;
  _renderLogEl(el,status.log,'Run log');
}
function updateLogSectionRaw(srcKey,text){
  var el=document.getElementById('log-section-'+srcKey);
  if(!el)return;
  var lines=text.split('\n').filter(function(l){return l.length>0;});
  if(!lines.length)return;
  _renderLogEl(el,lines,'Live log');
}
function startLivePolling(src,btn,prevAttempt){
  var url=SYNC_STATUS_URLS[src],liveUrl=SYNC_LIVE_LOG_URLS[src],deadline=Date.now()+300000;
  var logEl=document.getElementById('log-section-'+src);
  if(logEl){var det=logEl.querySelector('details');if(det)det.open=true;}
  var timer=setInterval(function(){
    if(Date.now()>deadline){clearInterval(timer);btn.textContent='↻ Sync now';btn.disabled=false;return;}
    if(liveUrl){fetch(liveUrl,{cache:'no-store'}).then(function(r){return r.ok?r.text():null;}).then(function(t){if(t&&t.trim())updateLogSectionRaw(src,t);}).catch(function(){});}
    if(url){fetch(url,{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
    .then(function(st){
      if(!st||!(Number(st.lastAttempt)>prevAttempt))return;
      clearInterval(timer);
      _knownAttempt[src]=Number(st.lastAttempt);
      btn.textContent='✓ Done';
      setTimeout(function(){
        fetch(url,{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
        .then(function(freshSt){refreshSourceCard(src,SRC_NAMES[src],freshSt||st);});
      },3000);
    });}
  },2000);
}
function triggerSync(src,btn){
  btn.disabled=true;btn.textContent='↻ Running…';
  var url=SYNC_STATUS_URLS[src];
  var prevAttempt=0;
  return (url?fetch(url,{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}):Promise.resolve(null))
  .then(function(st){
    prevAttempt=st?Number(st.lastAttempt)||0:0;
    return fetch('/cgi-bin/trigger-sync',{method:'POST',body:'source='+src,headers:{'Content-Type':'application/x-www-form-urlencoded'}});
  })
  .then(function(r){return r.json();})
  .then(function(j){
    if(!j.ok){btn.textContent='Error: '+(j.error||'?');btn.disabled=false;return false;}
    if(!url){btn.textContent='✓ Triggered';return true;}
    startLivePolling(src,btn,prevAttempt);
    return true;
  })
  .catch(function(){btn.textContent='Failed';btn.disabled=false;return false;});
}
async function syncAll(){
  var allBtn=document.getElementById('sync-all-btn');
  if(allBtn)allBtn.disabled=true;
  var buttons=Array.from(document.querySelectorAll('.sync-btn[data-src]')).filter(function(b){return !b.disabled;});
  for(var i=0;i<buttons.length;i++){
    await triggerSync(buttons[i].dataset.src,buttons[i]);
  }
  if(allBtn)allBtn.disabled=false;
}
function cookieDaysLeft(meta){if(!meta||!meta.cookieRefreshNeededBy)return null;return Math.ceil((new Date(meta.cookieRefreshNeededBy)-new Date())/86400000);}
function cookieStatusCard(title,meta){
  if(!meta)return '';
  var dr=meta.dryRun?true:false;
  var days=cookieDaysLeft(meta);
  var cls,badge,detail='';
  if(days===null){
    if(dr&&meta.cookieValid===false){cls='expired';badge='Expired';}
    else return '';
  } else if(days<=0){cls='expired';badge='Expired';}
  else if(days<=7){cls='warn';badge='Expires in '+days+' day'+(days===1?'':'s');}
  else{cls='ok';badge='OK — '+days+' days left';}
  if(meta.cookieVerifiedAt)detail+='<p>Verified: '+esc(meta.cookieVerifiedAt)+'</p>';
  if(meta.cookieRefreshNeededBy)detail+='<p>Refresh by: '+esc(meta.cookieRefreshNeededBy)+'</p>';
  if(days!==null&&days<=0)detail+='<p class="issues">Cookie has expired &mdash; paste a new value below.</p>';
  if(dr&&meta.feedTestOk===false)detail+='<p class="issues">Feed test failed (check network or club ID).</p>';
  if(dr&&meta.feedTestOk===true)detail+='<p>Feed test: OK</p>';
  return '<article class="source ck-'+cls+'"><h2>'+esc(title)+(dr?' <small style="font-weight:normal;font-size:.78rem">(api+dry-run)</small>':'')+'<span class="badge '+(cls==='ok'?'':'warn')+(cls==='expired'?' bad':'')+'">'+badge+'</span></h2>'+detail+'</article>';
}
function renderCookieSection(myMeta,lbMeta){
  var hasCookie=myMeta||lbMeta;
  var sec=document.getElementById('cookie-status');
  if(!hasCookie){sec.style.display='none';return;}
  sec.style.display='';
  document.getElementById('cookie-cards').innerHTML=cookieStatusCard('My Activities',myMeta)+cookieStatusCard('Club Leaderboard',lbMeta);
}
function saveCookie(){
  var val=document.getElementById('cookie-input').value.trim();
  var statusEl=document.getElementById('cookie-save-status');
  if(!val){statusEl.className='err';statusEl.textContent='Please paste a cookie value.';return;}
  statusEl.className='';statusEl.textContent='Saving...';
  fetch('/cgi-bin/update-cookie',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({cookie:val})})
  .then(function(r){return r.json();})
  .then(function(j){
    if(j.ok){statusEl.className='ok';statusEl.textContent='✓ Cookie saved to '+(j.updated||'?')+' config file(s). Session cache cleared — next sync will use the new value.';document.getElementById('cookie-input').value='';}
    else{statusEl.className='err';statusEl.textContent='Error: '+(j.error||'unknown');}
  })
  .catch(function(e){statusEl.className='err';statusEl.textContent='Request failed: '+e.message;});
}
function emailCard(name,status){
  if(!status)return '';
  var now=Math.floor(Date.now()/1000),last=Number(status.lastSuccess)||0,age=last?now-last:null;
  var staleLimit=status.mode==='yearly'?370*86400:8*86400;
  var badge,cls;
  if(status.ok===false){badge='Failed';cls='bad';}
  else if(age!==null&&age>staleLimit){badge='Stale';cls='warn';}
  else{badge='OK'+(age!==null?' — '+timeAgo(age):'');cls='';}
  var detail='';
  if(status.subject)detail+='<p>Last subject: <em>'+esc(status.subject)+'</em></p>';
  if(status.recipientCount!=null)detail+='<p>Recipients: '+esc(status.recipientCount)+(status.sentCount!=null&&status.sentCount!==status.recipientCount?' ('+esc(status.sentCount)+' sent OK)':'')+'</p>';
  var logsHtml=status.log&&status.log.length?'<details><summary style="cursor:pointer;font-size:.85rem;color:var(--muted)">Show run log ('+status.log.length+' lines)</summary><pre class="run-log">'+status.log.map(function(l){return esc(l);}).join('\n')+'</pre></details>':'';
  return '<article class="source"><h2>'+esc(name)+' <span class="badge '+cls+'">'+badge+'</span></h2><p>Latest attempt: '+stamp(status.lastAttempt)+'</p><p>Last successful send: '+stamp(status.lastSuccess)+'</p>'+detail+logsHtml+'</article>';
}
var EMAIL_STATUS_URLS={monthly:'../email-monthly-status.json',weekly:'../email-weekly-status.json',yearly:'../email-yearly-status.json'};
function _refreshEmailCards(){
  Promise.all([
    fetch('../email-monthly-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
    fetch('../email-weekly-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
    fetch('../email-yearly-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
  ]).then(function(vs){renderEmailSection(vs[0],vs[1],vs[2]);});
}
function _pollEmailDone(type,prevAttempt,btn,statusEl){
  var url=EMAIL_STATUS_URLS[type],deadline=Date.now()+180000;
  var timer=setInterval(function(){
    if(Date.now()>deadline){
      clearInterval(timer);btn.disabled=false;btn.innerHTML='&#9993; Send';
      statusEl.className='ok';statusEl.textContent='✓ Sent ('+type+'). Refreshing…';
      _refreshEmailCards();return;
    }
    fetch(url,{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
    .then(function(st){
      if(!st||!(Number(st.lastAttempt)>prevAttempt))return;
      clearInterval(timer);btn.disabled=false;btn.innerHTML='&#9993; Send';
      var ok=st.ok===true;
      statusEl.className=ok?'ok':'err';
      statusEl.textContent=ok?'✓ Sent ('+type+') to '+(st.sentCount!=null?st.sentCount:'–')+' recipient(s).':'✗ Send failed — see status card for details.';
      _refreshEmailCards();
    });
  },3000);
}
function isoWeekStr(d){
  var day=d.getDay()||7;
  var thu=new Date(d);thu.setDate(d.getDate()-day+4);
  var y=thu.getFullYear();
  var jan4=new Date(y,0,4);var w=Math.ceil(((thu-jan4)/86400000+((jan4.getDay()||7)-1)+1)/7);
  return y+'-W'+String(w).padStart(2,'0');
}
function weekToMonth(wStr){
  var p=wStr.split('-W');if(p.length!==2)return '';
  var yr=parseInt(p[0]),wk=parseInt(p[1]);
  var jan4=new Date(yr,0,4);var dow=(jan4.getDay()||7);
  var mon=new Date(jan4);mon.setDate(jan4.getDate()-dow+1+(wk-1)*7);
  return mon.getFullYear()+'-'+String(mon.getMonth()+1).padStart(2,'0');
}
function updatePeriodInput(){
  var type=document.getElementById('email-type-sel').value;
  var inp=document.getElementById('email-period-sel');
  var now=new Date();
  if(type==='yearly'){
    inp.type='number';inp.min='2020';inp.max=now.getFullYear();inp.style.width='5rem';
    inp.value=now.getFullYear()-1;
  } else if(type==='weekly'){
    inp.type='week';inp.style.width='9rem';
    inp.value=isoWeekStr(now);
  } else {
    inp.type='month';inp.style.width='9rem';
    var mm=String(now.getMonth()+1).padStart(2,'0');
    inp.value=now.getFullYear()+'-'+mm;
  }
}
function validEmail(s){return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);}
function sendEmail(){
  var type=document.getElementById('email-type-sel').value;
  var toEl=document.getElementById('email-to-override');
  var to=(toEl.value||'').trim();
  var _praw=(document.getElementById('email-period-sel').value||'').trim();
  var period=type==='weekly'?weekToMonth(_praw):_praw;
  var statusEl=document.getElementById('send-email-status');
  var btn=document.querySelector('#send-email-card .sync-btn');
  toEl.classList.remove('invalid');
  if(to){
    var addrs=to.split(/[\s,;]+/).filter(Boolean);
    var bad=addrs.filter(function(a){return !validEmail(a);});
    if(bad.length){
      toEl.classList.add('invalid');
      statusEl.className='err';
      statusEl.textContent='Invalid address'+(bad.length>1?'es':'')+': '+bad.join(', ');
      return;
    }
  }
  if(btn){btn.disabled=true;btn.textContent='Sending…';}
  statusEl.className='';statusEl.textContent='';
  var prevAttempt=0;
  var url=EMAIL_STATUS_URLS[type];
  (url?fetch(url,{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}):Promise.resolve(null))
  .then(function(st){
    prevAttempt=st?Number(st.lastAttempt)||0:0;
    var body={type:type};if(to)body.email_to=to;if(period)body.period=period;
    return fetch('/cgi-bin/send-email',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  })
  .then(function(r){return r.json();})
  .then(function(j){
    if(!j.ok){btn.disabled=false;btn.innerHTML='&#9993; Send';statusEl.className='err';statusEl.textContent='Error: '+(j.error||'unknown');return;}
    statusEl.className='ok';statusEl.textContent='Queued — waiting for completion…';
    btn.textContent='⏳ Waiting…';
    _pollEmailDone(type,prevAttempt,btn,statusEl);
  })
  .catch(function(e){
    btn.disabled=false;btn.innerHTML='&#9993; Send';
    statusEl.className='err';statusEl.textContent='Request failed: '+e.message;
  });
}
function renderEmailSection(monthly,weekly,yearly){
  var cards=emailCard('Monthly email',monthly)+emailCard('Weekly email',weekly)+emailCard('Yearly email',yearly);
  var sec=document.getElementById('email-status');
  sec.style.display='';
  document.getElementById('email-cards').innerHTML=cards;
}
function sourceCard(name,status,srcKey){
  if(!status||(!status.lastAttempt&&status.importEnabled===false))return '';
  var now=Math.floor(Date.now()/1000),last=Number(status.lastSuccess)||0,age=last?now-last:null;
  var disabled=status.importEnabled===false;
  var warning=status.ok===false||disabled||!last||age>staleAfter;
  var badge=status.ok===false?'Failed':disabled?'Disabled':!last?'No successful import':age>staleAfter?'Stale':'OK'+(age!==null?' — '+timeAgo(age):'');
  var cls=status.ok===false?'bad':warning?'warn':'';
  var detail=status.error?'<p class="issues">'+esc(status.error)+'</p>':'';
  if(status.mode==='keepalive')detail+='<p>Latest run checked Drive access only; no activities were imported.</p>';
  if(status.importEnabled===false)detail+='<p>Activity import is disabled in configuration.</p>';
  if(age!==null&&age>staleAfter)detail+='<p>No successful import in the last 48 hours.</p>';
  var logsInner=status.log&&status.log.length?'<details><summary style="cursor:pointer;font-size:.85rem;color:var(--muted)">Show run log ('+status.log.length+' lines)</summary><pre class="run-log">'+status.log.map(function(l){return esc(l);}).join('\n')+'</pre></details>':'';
  var logsHtml=srcKey?'<div id="log-section-'+srcKey+'">'+logsInner+'</div>':logsInner;
  var syncBtn=srcKey?'<button class="sync-btn" data-src="'+srcKey+'" onclick="triggerSync(this.dataset.src,this)">↻ Sync now</button>':'';
  return '<article class="source"><h2>'+esc(name)+' <span class="badge '+cls+'">'+badge+'</span></h2><p>Latest attempt: '+stamp(status.lastAttempt)+'</p><p>Last successful import: '+stamp(status.lastSuccess)+'</p>'+detail+logsHtml+syncBtn+'</article>';
}
function render(data,statuses,lbData){
  var activities=Array.isArray(data.activities)?data.activities:[];
  var missingGps=activities.filter(function(a){return a.has_gps===false&&!GPS_OPTIONAL[a.sport_type];});
  var unknownGps=activities.filter(function(a){return a.has_gps==null;}).length;
  var missingHr=activities.filter(function(a){return !(Number(a.average_heartrate)>0);});
  var missingDetail=activities.filter(function(a){return a.detail!==true;});
  document.getElementById('count-total').textContent=activities.length;
  document.getElementById('count-gps').textContent=missingGps.length;
  document.getElementById('count-hr').textContent=missingHr.length;
  document.getElementById('count-detail').textContent=missingDetail.length;
  document.getElementById('state').textContent=unknownGps+' '+(unknownGps===1?'activity has':'activities have')+' unknown GPS status because details are unavailable.';
  document.getElementById('generated').textContent='Activity data generated: '+(data.generatedAt?new Date(data.generatedAt).toLocaleString():'not recorded');
  document.getElementById('sources').innerHTML=sourceCard('Strava',statuses.strava,'strava')+sourceCard('HealthSync',statuses.healthsync,'healthsync')+sourceCard('Club leaderboard',statuses.leaderboard,'leaderboard');
  renderCookieSection(data.scrapeMeta||null,lbData?lbData.scrapeMeta||null:null);
  renderEmailSection(statuses.emailMonthly||null,statuses.emailWeekly||null,statuses.emailYearly||null);
  renderActivityList(activities);
  document.querySelectorAll('.issue-filters input').forEach(function(input){
    input.addEventListener('change',function(){renderActivityList(activities);});
  });
  // Seed known lastAttempt for auto-detect polling
  ['strava','healthsync','leaderboard'].forEach(function(src){
    if(statuses[src])_knownAttempt[src]=Number(statuses[src].lastAttempt)||0;
  });
}
Promise.all([
  fetch('activities.json',{cache:'no-store'}).then(function(r){if(!r.ok)throw new Error('activities.json HTTP '+r.status);return r.json();}),
  fetch('strava-sync-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('healthsync-sync-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('../leaderboard-sync-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('../activities.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('../email-monthly-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('../email-weekly-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('../email-yearly-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
]).then(function(values){render(values[0],{strava:values[1],healthsync:values[2],leaderboard:values[3],emailMonthly:values[5],emailWeekly:values[6],emailYearly:values[7]},values[4]);}).catch(function(error){document.getElementById('state').textContent='Could not load activity data: '+error.message;});
updatePeriodInput();
// Continuous poll: detect syncs triggered by cron while the page is open (GET, not HEAD — uhttpd compatibility)
setInterval(function(){
  ['strava','healthsync','leaderboard'].forEach(function(src){
    var btn=document.querySelector('.sync-btn[data-src="'+src+'"]');
    if(!btn||btn.disabled)return;
    fetch(SYNC_RUNNING_URLS[src],{cache:'no-store'})
    .then(function(r){return r.ok?r.text():null;})
    .then(function(t){
      if(t!=='1')return;
      btn.textContent='↻ Running…';btn.disabled=true;
      startLivePolling(src,btn,_knownAttempt[src]||0);
    }).catch(function(){});
  });
},5000);
fetch('../',{method:'HEAD'}).then(function(r){if(r.ok){var el=document.getElementById('leaderboard-link');if(el)el.style.display='';}}).catch(function(){});
(function(){
  var root=document.documentElement;
  var btn=document.getElementById('theme-tog');
  function isDark(){return root.dataset.theme==='dark'||(!root.dataset.theme&&matchMedia('(prefers-color-scheme:dark)').matches);}
  function syncBtn(){btn.textContent=isDark()?'☀️':'🌙';}
  syncBtn();
  btn.onclick=function(){root.dataset.theme=isDark()?'light':'dark';localStorage.setItem('theme',root.dataset.theme);syncBtn();};
  matchMedia('(prefers-color-scheme:dark)').addEventListener('change',syncBtn);
})();
</script>
<div class="meta" style="text-align:center;padding:.5rem 0 1rem"><a href="https://github.com/raczeja/StatsServiceBook" target="_blank" rel="noopener">StatsServiceBook on GitHub</a></div>
</body>
</html>
HTML
log "wrote $WEB_DIR/data-quality.html"