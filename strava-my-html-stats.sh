# strava-my-html-stats.sh — sourced by strava-my-activities.sh.
# Writes $WEB_DIR/stats.html (personal activity stats summary).
# Quoted heredoc: nothing shell-expanded; all data flows through activities.json.

cat > "$WEB_DIR/stats.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>My Stats</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN0YXRzU2VydmljZUJvb2siPgogIDxkZWZzPgogICAgPGNsaXBQYXRoIGlkPSJjbGlwIj4KICAgICAgPGNpcmNsZSBjeD0iMzIiIGN5PSIzMiIgcj0iMzAiLz4KICAgIDwvY2xpcFBhdGg+CiAgICA8bGluZWFyR3JhZGllbnQgaWQ9ImJnIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMyYTJhMmEiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMTExMTExIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KCiAgPCEtLSBCYWNrZ3JvdW5kIGNpcmNsZSAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMiIgZmlsbD0idXJsKCNiZykiLz4KCiAgPGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXApIj4KCiAgICA8IS0tIEFyZWEgZmlsbCB1bmRlciB0aGUgcm91dGUgbGluZSAtLT4KICAgIDxwb2x5Z29uCiAgICAgIHBvaW50cz0iNCw0NiAxMyw0NiAxOSwzMiAyNSw0MCAzMiwxOCAzOSwzMiA0NSwyNSA1MSwzMiA2MCwzMiA2MCw1NiA0LDU2IgogICAgICBmaWxsPSIjZmM0YzAyIiBmaWxsLW9wYWNpdHk9IjAuMTUiLz4KCiAgICA8IS0tIFJvdXRlIC8gZWxldmF0aW9uIHByb2ZpbGUg4oCUIHRoZSBjb3JlIGZlYXR1cmUgLS0+CiAgICA8cG9seWxpbmUKICAgICAgcG9pbnRzPSI0LDQ2IDEzLDQ2IDE5LDMyIDI1LDQwIDMyLDE4IDM5LDMyIDQ1LDI1IDUxLDMyIDYwLDMyIgogICAgICBmaWxsPSJub25lIgogICAgICBzdHJva2U9IiNmYzRjMDIiCiAgICAgIHN0cm9rZS13aWR0aD0iMy4yIgogICAgICBzdHJva2UtbGluZWNhcD0icm91bmQiCiAgICAgIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KCiAgICA8IS0tIEdQUyAvIHN0YXJ0IGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjQiIGN5PSI0NiIgcj0iMi41IiBmaWxsPSIjZmM0YzAyIi8+CgogICAgPCEtLSBGaW5pc2ggLyBjdXJyZW50LXBvc2l0aW9uIGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjYwIiBjeT0iMzIiIHI9IjIuNSIgZmlsbD0iI2ZjNGMwMiIvPgoKICA8L2c+CgogIDwhLS0gV2lGaSBzaWduYWwgYXJjcyDigJQgdG9wLXJpZ2h0LCByZXByZXNlbnRzIHRoZSByb3V0ZXIgLS0+CiAgPHBhdGggZD0iTTQzLDEzIFE1MCw3ICA1NywxMyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjQ1Ii8+CiAgPHBhdGggZD0iTTQ2LDE3IFE1MCwxMyA1NCwxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjc1Ii8+CiAgPGNpcmNsZSBjeD0iNTAiIGN5PSIyMSIgcj0iMi4yIiBmaWxsPSIjZmM0YzAyIi8+CgogIDwhLS0gT3V0ZXIgcmluZyAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLW9wYWNpdHk9IjAuMzUiLz4KPC9zdmc+Cg==" type="image/svg+xml">
<style>
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1100px;padding:0 1rem;background:#fafafa;color:#222}
  h1{margin:0 0 .25rem;font-size:1.6rem}
  h2{font-size:.78rem;font-weight:700;margin:1.6rem 0 .5rem;color:#888;text-transform:uppercase;letter-spacing:.06em}
  a{color:#fc4c02}
  .crumbs{font-size:.85rem;margin:0 0 .75rem}
  .meta{color:#666;font-size:.85rem;margin:.4rem 0 .75rem}
  .filters{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin:.5rem 0 .85rem}
  select{font:inherit;padding:.35rem .5rem;border:1px solid #ccc;border-radius:.4rem;background:#fff;color:#222;cursor:pointer}
  /* KPI cards */
  .kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(145px,1fr));gap:.5rem;margin:.25rem 0 .5rem}
  .kpi{background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.65rem .85rem}
  .kpi .k{font-size:.68rem;text-transform:uppercase;letter-spacing:.05em;color:#999;font-weight:600}
  .kpi .v{font-size:1.5rem;font-weight:700;font-variant-numeric:tabular-nums;color:#fc4c02;line-height:1.2;margin:.05rem 0}
  .kpi .s{font-size:.75rem;color:#777}
  /* tables */
  table{border-collapse:collapse;width:100%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);margin:.25rem 0}
  th,td{padding:.42rem .65rem;text-align:left;border-bottom:1px solid #eee;white-space:nowrap}
  th{background:#fc4c02;color:#fff}
  td.num{text-align:right;font-variant-numeric:tabular-nums}
  tr:nth-child(even) td{background:#fafafa}
  tr.hi td{background:#fff5f0!important;font-weight:600}
  .muted{color:#888;font-size:.85rem}
  /* year comparison heatmap */
  .cmp td.c0{background:#fff;color:#bbb}
  .cmp td.c1{background:#ffeee6}
  .cmp td.c2{background:#ffcaab}
  .cmp td.c3{background:#ff9a6c}
  .cmp td.c4{background:#fc4c02;color:#fff;font-weight:600}
  /* chart */
  .chart-box{background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.65rem .9rem;margin:.25rem 0}
  .chart-box h3{margin:0 0 .4rem;font-size:.75rem;color:#888;font-weight:700;text-transform:uppercase;letter-spacing:.05em}
  svg.bar{width:100%;display:block}
  /* records grid */
  .recs{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:.5rem;margin:.25rem 0}
  .rec{background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.6rem .85rem}
  .rec .rl{font-size:.68rem;text-transform:uppercase;letter-spacing:.05em;color:#999;font-weight:600}
  .rec .rv{font-size:1.2rem;font-weight:700;color:#fc4c02;font-variant-numeric:tabular-nums;margin:.1rem 0}
  .rec .rs{font-size:.78rem;color:#666;white-space:pre-line}
  /* tooltip */
  #tip{display:none;position:fixed;background:rgba(20,20,20,.92);color:#fff;padding:.42rem .7rem;
       border-radius:.4rem;font-size:.8rem;pointer-events:none;z-index:100;
       white-space:pre;line-height:1.65;box-shadow:0 2px 8px rgba(0,0,0,.3)}
  .empty{color:#888;padding:.4rem 0;font-size:.9rem}
  #pbar{position:fixed;top:0;left:0;width:0;height:3px;background:#fc4c02;z-index:9999;pointer-events:none}
</style>
</head>
<body>
<div id="pbar"></div>
<div id="tip"></div>
<div class="crumbs"><a href="index.html">&larr; My Activities</a> &middot; <a href="bike.html">🔧 Bike service</a></div>
<div style="display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="36" height="36" aria-hidden="true"><defs><clipPath id="clip"><circle cx="32" cy="32" r="30"/></clipPath><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs><circle cx="32" cy="32" r="32" fill="url(#bg)"/><g clip-path="url(#clip)"><polygon points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32 60,56 4,56" fill="#fc4c02" fill-opacity="0.15"/><polyline points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32" fill="none" stroke="#fc4c02" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="46" r="2.5" fill="#fc4c02"/><circle cx="60" cy="32" r="2.5" fill="#fc4c02"/></g><path d="M43,13 Q50,7 57,13" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.45"/><path d="M46,17 Q50,13 54,17" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/><circle cx="50" cy="21" r="2.2" fill="#fc4c02"/><circle cx="32" cy="32" r="31" fill="none" stroke="#fc4c02" stroke-width="0.8" stroke-opacity="0.35"/></svg><h1 style="margin:0">My Stats</h1></div>
<div class="meta" id="meta">Loading…</div>

<div class="filters">
  <label>Sport&nbsp;<select id="sportSel"></select></label>
  <label>Year&nbsp;<select id="yearSel"></select></label>
</div>

<div class="kpis" id="kpis"></div>

<h2>Year overview</h2>
<div id="yearTable"></div>

<h2 id="moTitle">Monthly breakdown</h2>
<div class="meta" id="moDesc" style="margin:.1rem 0 .5rem"></div>
<div class="chart-box"><h3 id="moChartTitle">Distance per month (km)</h3><svg class="bar" id="moSvg" viewBox="0 0 480 130" preserveAspectRatio="none"></svg></div>
<div id="moTable"></div>

<h2>Year comparison <span class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; km per month</span></h2>
<div id="cmpTable"></div>

<h2>Personal records <span class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; all time &middot; selected sport</span></h2>
<div class="recs" id="recs"></div>

<h2>By sport <span id="sportSubtitle" class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; all time</span></h2>
<div id="sportTable"></div>

<h2>Average per day of week <span id="dowSubtitle" class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; selected sport &middot; all years</span></h2>
<div class="chart-box"><h3>Avg distance per weekday (km)</h3><svg class="bar" id="dowSvg" viewBox="0 0 280 120" preserveAspectRatio="none"></svg></div>

<div class="meta" style="margin-top:1.5rem">
  StravaStats for OpenWrt &middot; <a href="index.html">My Activities</a> &middot;
  <a href="bike.html">🔧 Bike service</a> &middot; <a href="activities.json">activities.json</a> &middot;
  <a id="leaderboard-link" href="../" style="display:none">🏆 Club leaderboard</a>
</div>

<script>
"use strict";
fetch('../',{method:'HEAD'}).then(function(r){if(r.ok){var el=document.getElementById('leaderboard-link');if(el)el.style.display='';}}).catch(function(){});
var _pbar=null,_pbarTick=null,_pbarPct=0;
function progressStart(){
  if(!_pbar)_pbar=document.getElementById("pbar");
  clearInterval(_pbarTick);_pbarPct=0;
  _pbar.style.cssText="width:0%;opacity:1;transition:none";
  _pbarTick=setInterval(function(){
    _pbarPct+=(_pbarPct<70?3:_pbarPct<85?1:0.2);
    if(_pbarPct>90)_pbarPct=90;
    _pbar.style.transition="width .3s ease";
    _pbar.style.width=_pbarPct+"%";
  },300);
}
function progressDone(){
  if(!_pbar)_pbar=document.getElementById("pbar");
  clearInterval(_pbarTick);
  _pbar.style.transition="width .15s ease";
  _pbar.style.width="100%";
  setTimeout(function(){_pbar.style.transition="opacity .4s ease";_pbar.style.opacity="0";},200);
}
var DATA = null, ALL_ACTS = [], genStr = "";
var selSport = "Ride", selYear = "";

var MONTHS_S = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
var MONTHS_F = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];
var DAYS_S   = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];

// ---- helpers ----------------------------------------------------------------
function esc(s){
  return String(s==null?"":s).replace(/[&<>"]/g,function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c];
  });
}
function p2(n){ return n<10?"0"+n:""+n; }

// meters → km string with 1 decimal + space thousands separator
function fmtKm(m){
  var k = Math.round((m||0)/100)/10;
  return k.toFixed(1).replace(/\B(?=(\d{3})+(?!\d))/g," ");
}
// km (already float) → same string format
function fmtKmD(km){
  return (Math.round((km||0)*10)/10).toFixed(1).replace(/\B(?=(\d{3})+(?!\d))/g," ");
}
function fmtInt(n){ return Math.round(n||0).toString().replace(/\B(?=(\d{3})+(?!\d))/g," "); }
function fmtH(s){
  var h = Math.floor((s||0)/3600), m = Math.floor(((s||0)%3600)/60);
  return h+"h "+p2(m)+"m";
}
// distance in meters + time in seconds → km/h string, or "—"
function fmtSpd(distM, secS){
  return secS>0 ? ((distM/secS)*3.6).toFixed(1)+" km/h" : "—";
}
function todayStr(){
  var d = new Date();
  return d.getFullYear()+"-"+p2(d.getMonth()+1)+"-"+p2(d.getDate());
}
// day-of-week index: 0=Mon … 6=Sun
function dowOf(dateStr){
  var d = new Date(dateStr+"T12:00:00");
  return (d.getDay()+6)%7;
}
// Monday of the week containing dateStr → "YYYY-MM-DD"
function weekOf(dateStr){
  var d = new Date(dateStr+"T12:00:00");
  d.setDate(d.getDate() - ((d.getDay()+6)%7));
  return d.getFullYear()+"-"+p2(d.getMonth()+1)+"-"+p2(d.getDate());
}

// ---- filter / aggregate ----------------------------------------------------
function filtered(){
  return ALL_ACTS.filter(function(a){
    return !selSport || selSport==="All" || a.sport_type===selSport;
  });
}
function filterYear(acts, yr){
  if(!yr||yr==="all") return acts;
  return acts.filter(function(a){ return a.date && a.date.slice(0,4)===yr; });
}
function agg(list){
  var distM=0,secs=0,elev=0;
  list.forEach(function(a){ distM+=(a.distance||0); secs+=(a.moving_time||0); elev+=(a.total_elevation_gain||0); });
  return {n:list.length, distM:distM, secs:secs, elev:elev};
}
function sortedYears(acts){
  var s={};
  acts.forEach(function(a){ if(a.date) s[a.date.slice(0,4)]=1; });
  return Object.keys(s).sort(function(a,b){return b-a;});
}
function avgPerWeek(acts, yr){
  var a = agg(acts);
  if(!a.n) return 0;
  var now = new Date(), curY = now.getFullYear();
  var weeks;
  if(yr && yr!=="all"){
    if(+yr===curY){
      var jan = new Date(curY+"-01-01T12:00:00");
      weeks = Math.max(1, Math.ceil((now-jan)/86400000/7));
    } else { weeks=52; }
  } else {
    var ds = acts.map(function(a){return a.date;}).filter(Boolean).sort();
    if(!ds.length) return 0;
    var d1=new Date(ds[0]+"T12:00:00"), d2=new Date(ds[ds.length-1]+"T12:00:00");
    weeks = Math.max(1, Math.ceil((d2-d1)/86400000/7)+1);
  }
  return (a.distM/1000)/weeks;
}

// first-to-last activity span → "X years, Y months, Z days" (or "" if < 2 dates)
function fmtPeriod(acts){
  var dates=acts.map(function(a){return a.date;}).filter(Boolean).sort();
  if(dates.length<2) return "";
  var d1=new Date(dates[0]+"T12:00:00"), d2=new Date(dates[dates.length-1]+"T12:00:00");
  if(d2<=d1) return "";
  var y1=d1.getFullYear(),m1=d1.getMonth(),day1=d1.getDate();
  var y2=d2.getFullYear(),m2=d2.getMonth(),day2=d2.getDate();
  var years=y2-y1, months=m2-m1, days=day2-day1;
  if(days<0){ months--; days+=new Date(y2,m2,0).getDate(); }
  if(months<0){ years--; months+=12; }
  var parts=[];
  if(years>0) parts.push(years+" year"+(years===1?"":"s"));
  if(months>0) parts.push(months+" month"+(months===1?"":"s"));
  if(days>0) parts.push(days+" day"+(days===1?"":"s"));
  return parts.join(", ");
}

// ---- personal records -------------------------------------------------------
function computeRecords(acts){
  var longest=null, longest_t=null, most_e=null, fastest=null;
  var weeks={}, months={}, dates={};
  acts.forEach(function(a){
    var km=(a.distance||0)/1000, s=a.moving_time||0, e=a.total_elevation_gain||0;
    if(!longest   ||km>longest.km)   longest  ={km:km,s:s,e:e,date:a.date,name:a.name};
    if(!longest_t ||s>longest_t.s)   longest_t={km:km,s:s,  date:a.date,name:a.name};
    if(!most_e    ||e>most_e.e)      most_e   ={km:km,s:s,e:e,date:a.date,name:a.name};
    if(km>=20){
      var spd=s>0?(km/s)*3600:0;
      if(!fastest||spd>fastest.spd)  fastest  ={spd:spd,km:km,date:a.date,name:a.name};
    }
    if(a.date){
      weeks[weekOf(a.date)] = (weeks[weekOf(a.date)]||0) + km;
      months[a.date.slice(0,7)] = (months[a.date.slice(0,7)]||0) + km;
      dates[a.date] = 1;
    }
  });
  var bwk=null,bwkKm=0; Object.keys(weeks ).forEach(function(w){ if(weeks[w] >bwkKm){bwkKm=weeks[w]; bwk=w;} });
  var bmo=null,bmoKm=0; Object.keys(months).forEach(function(m){ if(months[m]>bmoKm){bmoKm=months[m];bmo=m;} });

  // longest consecutive-day streak
  var sorted=Object.keys(dates).sort();
  var maxStr=sorted.length?1:0, cur=1, sFrom=sorted[0], sTo=sorted[0], cFrom=sorted[0];
  for(var i=1;i<sorted.length;i++){
    var d1=new Date(sorted[i-1]+"T12:00:00"), d2=new Date(sorted[i]+"T12:00:00");
    if((d2-d1)/86400000===1){
      cur++;
      if(cur>maxStr){ maxStr=cur; sFrom=cFrom; sTo=sorted[i]; }
    } else { cur=1; cFrom=sorted[i]; }
  }
  return {
    longest:longest, longest_t:longest_t, most_e:most_e, fastest:fastest,
    bwk: bwk?{week:bwk,km:bwkKm}:null,
    bmo: bmo?{month:bmo,km:bmoKm}:null,
    streak: sorted.length?{n:maxStr,from:sFrom,to:sTo}:null
  };
}

// ---- tooltip ----------------------------------------------------------------
var tipEl = null;
function showTip(e,txt){
  if(!tipEl) tipEl=document.getElementById("tip");
  tipEl.textContent=txt; tipEl.style.display="block"; moveTip(e);
}
function moveTip(e){
  if(!tipEl) return;
  tipEl.style.left=(e.clientX+14)+"px"; tipEl.style.top=(e.clientY-10)+"px";
}
function hideTip(){
  if(!tipEl) tipEl=document.getElementById("tip");
  tipEl.style.display="none";
}
window.showTip=showTip; window.moveTip=moveTip; window.hideTip=hideTip;

// ---- SVG bar chart ----------------------------------------------------------
// bars: [{label, val (km), tip (plain text), hi (bool)}]
// viewW/viewH must match the svg's viewBox
function drawBars(svgId, bars, viewW, viewH){
  var svg = document.getElementById(svgId);
  if(!svg) return;
  var n=bars.length, PAD=26, GAP=3;
  var bw = Math.floor((viewW-PAD*2-(n-1)*GAP)/n);
  var max=0; bars.forEach(function(b){if((b.val||0)>max) max=b.val;}); if(!max) max=1;
  var usable = viewH-36; // 18px bottom (labels) + 18px top (value text above tallest bar)
  var parts = bars.map(function(b,i){
    var bh = Math.max(0, Math.round(((b.val||0)/max)*usable));
    var x=PAD+i*(bw+GAP), y=viewH-18-bh;
    var fill = b.hi?"#fc4c02":"#fc9172";
    var tipTxt = b.tip || b.label;
    return '<rect x="'+x+'" y="'+y+'" width="'+bw+'" height="'+bh+'"'+
           ' fill="'+fill+'" rx="1"'+
           ' onmouseenter="showTip(event,'+esc(JSON.stringify(tipTxt))+')"'+
           ' onmousemove="moveTip(event)" onmouseleave="hideTip()"'+
           ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+esc(JSON.stringify(tipTxt))+')"'+
           ' ontouchend="setTimeout(hideTip,1500)" style="cursor:default"/>'+
      (bh>14?'<text x="'+(x+bw/2)+'" y="'+(y-2)+'"'+
             ' text-anchor="middle" font-size="8.5" fill="#555">'+fmtKmD(b.val||0)+'</text>':'')+
      '<text x="'+(x+bw/2)+'" y="'+(viewH-3)+'"'+
            ' text-anchor="middle" font-size="9" fill="#888">'+esc(b.label)+'</text>';
  });
  svg.innerHTML = parts.join("");
}

// ---- render -----------------------------------------------------------------
function render(){
  var curY = String(new Date().getFullYear());
  var curMo = new Date().getMonth(); // 0-indexed
  var isAll = (!selYear || selYear==="all");
  var yrStr = isAll ? curY : selYear;
  var _period = isAll ? fmtPeriod(ALL_ACTS) : "";
  if(ALL_ACTS.length){
    document.getElementById("meta").textContent =
      ALL_ACTS.length+" activities"+(_period?" · "+_period:"")+genStr;
  }
  document.getElementById("dowSubtitle").innerHTML = "— selected sport · " + (isAll ? "all years" : selYear);
  document.getElementById("sportSubtitle").innerHTML = "— " + (isAll ? "all time"+(_period?" · "+_period:"") : selYear);
  var f = filtered();
  var fyAll  = isAll ? f : filterYear(f, selYear);  // KPIs, records, DOW
  var fyYear = filterYear(f, yrStr);                // monthly breakdown

  // --- KPI cards ---
  var a = agg(fyAll), apw = avgPerWeek(fyAll, selYear||yrStr);
  var _daySet={};
  fyAll.forEach(function(x){ if(x.date) _daySet[x.date]=1; });
  var nDays = Object.keys(_daySet).length;
  var _pDays = (function(){
    var now = new Date(), curY = now.getFullYear();
    if(isAll){
      var ds = ALL_ACTS.map(function(x){return x.date;}).filter(Boolean).sort();
      if(!ds.length) return 0;
      var d1 = new Date(ds[0].slice(0,4)+"-01-01T12:00:00");
      return Math.round((now-d1)/86400000)+1;
    }
    var yr = +selYear;
    if(yr===curY){
      var jan1 = new Date(curY+"-01-01T12:00:00");
      return Math.round((now-jan1)/86400000)+1;
    }
    return (yr%4===0&&(yr%100!==0||yr%400===0))?366:365;
  })();
  document.getElementById("kpis").innerHTML = [
    {k:"Distance",        v:fmtKm(a.distM)+" km"},
    {k:"Moving time",     v:fmtH(a.secs)},
    {k:"Elevation",       v:fmtInt(Math.round(a.elev))+" m"},
    {k:"Activities",      v:fmtInt(a.n), s:nDays+" / "+_pDays+" days",
     tip:nDays+" active days out of "+_pDays+" calendar days in period"},
    {k:"Avg km / week",   v:fmtKmD(apw)+" km"},
    {k:"Avg km / activity",v:a.n?fmtKmD(a.distM/1000/a.n)+" km":"—"},
    {k:"Avg speed",       v:fmtSpd(a.distM,a.secs)}
  ].map(function(kp){
    var ta = kp.tip
      ? ' onmouseenter="showTip(event,'+esc(JSON.stringify(kp.tip))+')"'+
        ' onmousemove="moveTip(event)" onmouseleave="hideTip()"'+
        ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+esc(JSON.stringify(kp.tip))+')"'+
        ' ontouchend="setTimeout(hideTip,1500)"'
      : '';
    return '<div class="kpi"'+ta+'>'+
           '<div class="k">'+esc(kp.k)+'</div>'+
           '<div class="v">'+kp.v+'</div>'+
           (kp.s?'<div class="s">'+esc(kp.s)+'</div>':'')+
           '</div>';
  }).join("");

  // --- Year overview table ---
  var ys = sortedYears(f);
  var ytHead='<tr><th>Year</th><th>Activities</th><th>Distance</th><th>Time</th>'+
             '<th>Elevation</th><th>Avg dist</th><th>Avg speed</th></tr>';
  var ytRows = ys.map(function(y){
    var ya = agg(filterYear(f,y));
    return '<tr'+(y===yrStr?' class="hi"':'')+'>'+
      '<td>'+y+'</td>'+
      '<td class="num">'+fmtInt(ya.n)+'</td>'+
      '<td class="num">'+fmtKm(ya.distM)+' km</td>'+
      '<td class="num">'+fmtH(ya.secs)+'</td>'+
      '<td class="num">'+fmtInt(Math.round(ya.elev))+' m</td>'+
      '<td class="num">'+(ya.n?fmtKmD(ya.distM/1000/ya.n)+' km':'—')+'</td>'+
      '<td class="num">'+fmtSpd(ya.distM,ya.secs)+'</td>'+
    '</tr>';
  }).join("");
  document.getElementById("yearTable").innerHTML = ytRows
    ? '<table><thead>'+ytHead+'</thead><tbody>'+ytRows+'</tbody></table>'
    : '<div class="empty">No activities found.</div>';

  // --- Monthly breakdown ---
  // Specific year: show that year's totals.
  // All years: aggregate by month number across all years, then show the average
  // per year (total / number of distinct years that had at least one activity in
  // that month), so months are comparable regardless of how many years of data exist.
  var moSrc   = isAll ? f : fyYear;
  var moLabel = isAll ? "all years (avg / year)" : yrStr;
  document.getElementById("moTitle").textContent = "Monthly breakdown — "+moLabel;
  document.getElementById("moChartTitle").textContent = "Distance per month (km) — "+moLabel;
  document.getElementById("moDesc").textContent = isAll
    ? "Each bar shows the average km ridden in that calendar month across all years of data. "+
      "The “Years” column in the table indicates how many seasons contributed — "+
      "months with only 1 year show the raw total (avg = total). The more seasons you accumulate, the more meaningful the average becomes."
    : "";
  var byMo = [];
  for(var m=1;m<=12;m++){
    var ml = moSrc.filter(function(a){ return a.date && +a.date.slice(5,7)===m; });
    var ma = agg(ml);
    var numYrs = 1;
    if(isAll && ml.length){
      var ySet={};
      ml.forEach(function(a){ if(a.date) ySet[a.date.slice(0,4)]=1; });
      numYrs = Object.keys(ySet).length || 1;
    }
    byMo.push({ n:ma.n, distM:ma.distM, secs:ma.secs, elev:ma.elev,
                dispDistM: ma.distM/numYrs, dispSecs: ma.secs/numYrs, dispElev: ma.elev/numYrs,
                numYrs: numYrs });
  }
  drawBars("moSvg", byMo.map(function(ma,i){
    return {
      label: MONTHS_S[i],
      val:   ma.dispDistM/1000,
      hi:    (!isAll && i===curMo && yrStr===curY),
      tip:   MONTHS_F[i]+(isAll?" (avg/year)":" "+yrStr)+
             "\n"+fmtKm(ma.dispDistM)+" km"+(isAll?" avg/year":"")+
             "  "+fmtH(ma.dispSecs)+
             "  "+fmtInt(Math.round(ma.dispElev))+" m elev"+
             (isAll?"  ("+ma.numYrs+" year"+(ma.numYrs===1?"":"s")+" · total "+fmtKm(ma.distM)+" km)":""+
             "  "+ma.n+" activit"+(ma.n===1?"y":"ies"))
    };
  }), 480, 130);

  var mtHead = isAll
    ? '<tr><th>Month</th><th>Years</th><th>Avg km / year</th><th>Avg time / year</th><th>Avg elev / year</th><th>Total km</th></tr>'
    : '<tr><th>Month</th><th>Activities</th><th>Distance</th><th>Time</th><th>Elevation</th><th>Avg dist</th></tr>';
  var mtRows = byMo.map(function(ma,i){
    if(!ma.n) return "";
    if(isAll) return '<tr><td>'+MONTHS_F[i]+'</td>'+
      '<td class="num">'+ma.numYrs+'</td>'+
      '<td class="num">'+fmtKm(ma.dispDistM)+' km</td>'+
      '<td class="num">'+fmtH(ma.dispSecs)+'</td>'+
      '<td class="num">'+fmtInt(Math.round(ma.dispElev))+' m</td>'+
      '<td class="num">'+fmtKm(ma.distM)+' km</td>'+
    '</tr>';
    return '<tr><td>'+MONTHS_F[i]+'</td>'+
      '<td class="num">'+fmtInt(ma.n)+'</td>'+
      '<td class="num">'+fmtKm(ma.distM)+' km</td>'+
      '<td class="num">'+fmtH(ma.secs)+'</td>'+
      '<td class="num">'+fmtInt(Math.round(ma.elev))+' m</td>'+
      '<td class="num">'+(ma.n?fmtKmD(ma.distM/1000/ma.n)+' km':'—')+'</td>'+
    '</tr>';
  }).join("");
  document.getElementById("moTable").innerHTML = mtRows.trim()
    ? '<table><thead>'+mtHead+'</thead><tbody>'+mtRows+'</tbody></table>'
    : '<div class="empty">No activities found.</div>';

  // --- Year comparison heatmap (km/month, up to 5 most recent years) ---
  var cmpYears = ys.slice(0,5);
  if(cmpYears.length >= 2){
    var cmpData={};
    cmpYears.forEach(function(y){
      cmpData[y]=[];
      for(var m=1;m<=12;m++){
        var ml2=filterYear(f,y).filter(function(a){ return a.date&&+a.date.slice(5,7)===m; });
        cmpData[y].push(agg(ml2).distM/1000);
      }
    });
    var cmpMax=0;
    Object.keys(cmpData).forEach(function(y){
      cmpData[y].forEach(function(v){ if(v>cmpMax) cmpMax=v; });
    });
    function heatCls(v){
      if(!cmpMax||!v) return "c0";
      var r=v/cmpMax;
      if(r<0.20) return "c1";
      if(r<0.45) return "c2";
      if(r<0.70) return "c3";
      return "c4";
    }
    var cmpHead='<tr><th>Month</th>'+cmpYears.map(function(y){return '<th>'+y+'</th>';}).join("")+'</tr>';
    var cmpRows=MONTHS_S.map(function(mo,i){
      var cells=cmpYears.map(function(y){
        var v=cmpData[y][i];
        return '<td class="num '+heatCls(v)+'">'+(v?fmtKmD(v):'—')+'</td>';
      }).join("");
      return '<tr><td>'+mo+'</td>'+cells+'</tr>';
    }).join("");
    document.getElementById("cmpTable").innerHTML=
      '<table class="cmp"><thead>'+cmpHead+'</thead><tbody>'+cmpRows+'</tbody></table>';
  } else {
    document.getElementById("cmpTable").innerHTML=
      '<div class="empty">Need at least 2 years of data for comparison.</div>';
  }

  // --- Personal records (all time, selected sport) ---
  var rec = computeRecords(fyAll);
  var ri  = [];
  if(rec.longest)
    ri.push({l:"Longest (distance)", v:fmtKmD(rec.longest.km)+" km",
             s:rec.longest.date+"  "+fmtH(rec.longest.s)+"\n"+rec.longest.name});
  if(rec.longest_t)
    ri.push({l:"Longest (duration)", v:fmtH(rec.longest_t.s),
             s:rec.longest_t.date+"  "+fmtKmD(rec.longest_t.km)+" km\n"+rec.longest_t.name});
  if(rec.most_e)
    ri.push({l:"Most elevation",     v:fmtInt(Math.round(rec.most_e.e))+" m",
             s:rec.most_e.date+"  "+fmtKmD(rec.most_e.km)+" km\n"+rec.most_e.name});
  if(rec.fastest)
    ri.push({l:"Fastest avg speed",  v:rec.fastest.spd.toFixed(1)+" km/h",
             s:rec.fastest.date+"  "+fmtKmD(rec.fastest.km)+" km\n"+rec.fastest.name});
  if(rec.bmo){
    var bm=rec.bmo.month;
    ri.push({l:"Best month (km)",    v:fmtKmD(rec.bmo.km)+" km",
             s:MONTHS_F[+bm.slice(5,7)-1]+" "+bm.slice(0,4)});
  }
  if(rec.bwk)
    ri.push({l:"Best week (km)",     v:fmtKmD(rec.bwk.km)+" km",
             s:"week of "+rec.bwk.week});
  if(rec.streak)
    ri.push({l:"Longest streak",     v:rec.streak.n+" day"+(rec.streak.n===1?"":"s"),
             s:rec.streak.from+" → "+rec.streak.to});
  document.getElementById("recs").innerHTML = ri.map(function(r){
    return '<div class="rec">'+
             '<div class="rl">'+esc(r.l)+'</div>'+
             '<div class="rv">'+esc(r.v)+'</div>'+
             '<div class="rs">'+esc(r.s)+'</div>'+
           '</div>';
  }).join("") || '<div class="empty">No data yet.</div>';

  // --- By sport (all sports, year-filtered when a year is selected) ---
  var sportSrc = isAll ? ALL_ACTS : filterYear(ALL_ACTS, selYear);
  var sportAgg={};
  sportSrc.forEach(function(a){
    var st=a.sport_type||"Other";
    if(!sportAgg[st]) sportAgg[st]={n:0,distM:0,secs:0,elev:0};
    sportAgg[st].n++;
    sportAgg[st].distM+=(a.distance||0);
    sportAgg[st].secs +=(a.moving_time||0);
    sportAgg[st].elev +=(a.total_elevation_gain||0);
  });
  var totalDistM=0;
  Object.keys(sportAgg).forEach(function(st){totalDistM+=sportAgg[st].distM;});
  var stKeys=Object.keys(sportAgg).sort(function(a,b){return sportAgg[b].distM-sportAgg[a].distM;});
  var stHead='<tr><th>Sport</th><th>Activities</th><th>Distance</th>'+
             '<th>Time</th><th>Elevation</th><th>% of km</th></tr>';
  var stRows=stKeys.map(function(st){
    var sa=sportAgg[st];
    var pct=totalDistM?Math.round(sa.distM/totalDistM*100):0;
    return '<tr'+(st===selSport?' class="hi"':'')+'>'+
      '<td>'+esc(st)+'</td>'+
      '<td class="num">'+fmtInt(sa.n)+'</td>'+
      '<td class="num">'+fmtKm(sa.distM)+' km</td>'+
      '<td class="num">'+fmtH(sa.secs)+'</td>'+
      '<td class="num">'+fmtInt(Math.round(sa.elev))+' m</td>'+
      '<td class="num">'+pct+'%</td>'+
    '</tr>';
  }).join("");
  document.getElementById("sportTable").innerHTML=
    '<table><thead>'+stHead+'</thead><tbody>'+stRows+'</tbody></table>';

  // --- Day of week (all time, selected sport) ---
  var dowKm=[0,0,0,0,0,0,0], dowN=[0,0,0,0,0,0,0];
  fyAll.forEach(function(a){
    if(!a.date) return;
    var d=dowOf(a.date);
    dowKm[d]+=(a.distance||0)/1000;
    dowN[d]++;
  });
  var dowAvg=dowKm.map(function(km,i){ return dowN[i]?km/dowN[i]:0; });
  var maxDow=dowAvg.indexOf(Math.max.apply(null,dowAvg));
  drawBars("dowSvg", DAYS_S.map(function(day,i){
    return {
      label: day,
      val:   dowAvg[i],
      hi:    i===maxDow,
      tip:   day+"\navg "+fmtKmD(dowAvg[i])+" km / activity\n"+dowN[i]+" activit"+(dowN[i]===1?"y":"ies")
    };
  }), 280, 120);
}

// ---- init -------------------------------------------------------------------
function load(){
  progressStart();
  fetch("activities.json",{cache:"no-store"})
    .then(function(r){ if(!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
    .then(function(d){
      DATA=d; ALL_ACTS=(d.activities||[]);
      var curY=String(new Date().getFullYear());
      selYear=curY;

      // Sport selector: sorted by total distance, Ride first if present
      var sportDist={};
      ALL_ACTS.forEach(function(a){
        var st=a.sport_type||"Other";
        sportDist[st]=(sportDist[st]||0)+(a.distance||0);
      });
      var sports=Object.keys(sportDist).sort(function(a,b){return sportDist[b]-sportDist[a];});
      selSport=sports.indexOf("Ride")>=0?"Ride":(sports[0]||"All");
      var sOpts='<option value="All">All sports</option>';
      sports.forEach(function(st){
        sOpts+='<option value="'+esc(st)+'"'+(st===selSport?' selected':'')+'>'+esc(st)+'</option>';
      });
      document.getElementById("sportSel").innerHTML=sOpts;
      document.getElementById("sportSel").value=selSport;

      // Year selector
      var ys=sortedYears(ALL_ACTS);
      var yOpts='<option value="all">All years</option>'+
        ys.map(function(y){ return '<option value="'+y+'"'+(y===curY?' selected':'')+'>'+y+'</option>'; }).join("");
      document.getElementById("yearSel").innerHTML=yOpts;
      document.getElementById("yearSel").value=curY;

      genStr=d.generatedAt?" · updated "+d.generatedAt.slice(0,10):"";
      progressDone();
      render();
    })
    .catch(function(e){
      progressDone();
      document.getElementById("meta").textContent="Error loading activities.json: "+e.message;
    });
}

document.getElementById("sportSel").addEventListener("change",function(){ selSport=this.value; render(); });
document.getElementById("yearSel").addEventListener("change",function(){ selYear=this.value; render(); });
load();
</script>
</body>
</html>
HTML

log "wrote $WEB_DIR/stats.html"
