# strava-my-html-data-quality.sh - sourced by strava-render-pages.sh.
# Writes $WEB_DIR/data-quality.html, a read-only import and activity audit.

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
.nav{margin:.25rem 0 1rem}.nav a{display:inline-block;padding:.4rem .75rem;background:#fc4c02;color:#fff;text-decoration:none;border-radius:.4rem;font-size:.85rem;font-weight:600}.nav a:hover{background:#e34402}
.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.65rem;margin:1rem 0 1.5rem}.metric,.source{background:var(--surface);border:1px solid var(--border);padding:.8rem 1rem;border-radius:4px}.metric strong{display:block;font-size:1.45rem;font-variant-numeric:tabular-nums}.metric span{color:var(--muted);font-size:.85rem}
.sources{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:.65rem;margin-bottom:1.5rem}.source h2{font-size:1rem;margin:0 0 .5rem}.source p{margin:.25rem 0;font-size:.9rem;overflow-wrap:anywhere}.badge{display:inline-block;font-size:.78rem;font-weight:650;padding:.15rem .45rem;border-radius:3px;background:var(--good-bg);color:var(--good)}.badge.warn{background:var(--warn-bg);color:var(--warn)}.badge.bad{background:var(--bad-bg);color:var(--bad)}
h2{font-size:1.1rem;margin:1rem 0 .5rem}.table-wrap{overflow-x:auto;border:1px solid var(--border);background:var(--surface)}table{border-collapse:collapse;width:100%;min-width:650px}th,td{text-align:left;padding:.55rem .7rem;border-bottom:1px solid var(--border);vertical-align:top}th{font-size:.8rem;color:var(--muted);font-weight:600}td{font-size:.88rem}.issues{color:var(--bad)}.empty{color:var(--good);padding:1rem;background:var(--good-bg)}#state{color:var(--muted);margin:.75rem 0}
.issue-filters{display:flex;flex-wrap:wrap;gap:1rem;margin:.5rem 0 1rem}.issue-filters label{display:inline-flex;align-items:center;gap:.35rem;font-size:.9rem;cursor:pointer}.issue-filters input{accent-color:var(--accent);margin:0}
@media(max-width:650px){body{margin:.8rem auto}.summary{grid-template-columns:repeat(2,minmax(0,1fr))}.sources{grid-template-columns:1fr}h1{font-size:1.35rem}}
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
<h2>Latest synchronization</h2>
<section class="sources" id="sources"><div class="source">Loading source status...</div></section>
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
function sourceCard(name,status){
  if(!status)return '<article class="source"><h2>'+name+'</h2><span class="badge warn">No status yet</span><p>Run this importer once to start tracking synchronization.</p></article>';
  var now=Math.floor(Date.now()/1000),last=Number(status.lastSuccess)||0,age=last?now-last:null;
  var disabled=status.importEnabled===false;
  var warning=status.ok===false||disabled||!last||age>staleAfter;
  var badge=status.ok===false?'Failed':disabled?'Disabled':!last?'No successful import':age>staleAfter?'Stale':'OK';
  var cls=status.ok===false?'bad':warning?'warn':'';
  var detail=status.error?'<p class="issues">'+esc(status.error)+'</p>':'';
  if(status.mode==='keepalive')detail+='<p>Latest run checked Drive access only; no activities were imported.</p>';
  if(status.importEnabled===false)detail+='<p>Activity import is disabled in configuration.</p>';
  if(age!==null&&age>staleAfter)detail+='<p>No successful import in the last 48 hours.</p>';
  return '<article class="source"><h2>'+esc(name)+' <span class="badge '+cls+'">'+badge+'</span></h2><p>Latest attempt: '+stamp(status.lastAttempt)+'</p><p>Last successful import: '+stamp(status.lastSuccess)+'</p>'+detail+'</article>';
}
function render(data,statuses){
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
  document.getElementById('sources').innerHTML=sourceCard('Strava',statuses.strava)+sourceCard('HealthSync',statuses.healthsync)+sourceCard('Club leaderboard',statuses.leaderboard);
  renderActivityList(activities);
  document.querySelectorAll('.issue-filters input').forEach(function(input){
    input.addEventListener('change',function(){renderActivityList(activities);});
  });
}
Promise.all([
  fetch('activities.json',{cache:'no-store'}).then(function(r){if(!r.ok)throw new Error('activities.json HTTP '+r.status);return r.json();}),
  fetch('strava-sync-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('healthsync-sync-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;}),
  fetch('../leaderboard-sync-status.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
]).then(function(values){render(values[0],{strava:values[1],healthsync:values[2],leaderboard:values[3]});}).catch(function(error){document.getElementById('state').textContent='Could not load activity data: '+error.message;});
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