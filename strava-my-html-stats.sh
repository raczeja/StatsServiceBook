# strava-my-html-stats.sh — sourced by strava-my-activities.sh.
# Writes $WEB_DIR/stats.html (personal activity stats summary).
# Quoted heredoc: nothing shell-expanded; all data flows through activities.json.

cat > "$WEB_DIR/stats.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t;</script>
<title>My Stats</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN0YXRzU2VydmljZUJvb2siPgogIDxkZWZzPgogICAgPGNsaXBQYXRoIGlkPSJjbGlwIj4KICAgICAgPGNpcmNsZSBjeD0iMzIiIGN5PSIzMiIgcj0iMzAiLz4KICAgIDwvY2xpcFBhdGg+CiAgICA8bGluZWFyR3JhZGllbnQgaWQ9ImJnIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMyYTJhMmEiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMTExMTExIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KCiAgPCEtLSBCYWNrZ3JvdW5kIGNpcmNsZSAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMiIgZmlsbD0idXJsKCNiZykiLz4KCiAgPGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXApIj4KCiAgICA8IS0tIEFyZWEgZmlsbCB1bmRlciB0aGUgcm91dGUgbGluZSAtLT4KICAgIDxwb2x5Z29uCiAgICAgIHBvaW50cz0iNCw0NiAxMyw0NiAxOSwzMiAyNSw0MCAzMiwxOCAzOSwzMiA0NSwyNSA1MSwzMiA2MCwzMiA2MCw1NiA0LDU2IgogICAgICBmaWxsPSIjZmM0YzAyIiBmaWxsLW9wYWNpdHk9IjAuMTUiLz4KCiAgICA8IS0tIFJvdXRlIC8gZWxldmF0aW9uIHByb2ZpbGUg4oCUIHRoZSBjb3JlIGZlYXR1cmUgLS0+CiAgICA8cG9seWxpbmUKICAgICAgcG9pbnRzPSI0LDQ2IDEzLDQ2IDE5LDMyIDI1LDQwIDMyLDE4IDM5LDMyIDQ1LDI1IDUxLDMyIDYwLDMyIgogICAgICBmaWxsPSJub25lIgogICAgICBzdHJva2U9IiNmYzRjMDIiCiAgICAgIHN0cm9rZS13aWR0aD0iMy4yIgogICAgICBzdHJva2UtbGluZWNhcD0icm91bmQiCiAgICAgIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KCiAgICA8IS0tIEdQUyAvIHN0YXJ0IGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjQiIGN5PSI0NiIgcj0iMi41IiBmaWxsPSIjZmM0YzAyIi8+CgogICAgPCEtLSBGaW5pc2ggLyBjdXJyZW50LXBvc2l0aW9uIGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjYwIiBjeT0iMzIiIHI9IjIuNSIgZmlsbD0iI2ZjNGMwMiIvPgoKICA8L2c+CgogIDwhLS0gV2lGaSBzaWduYWwgYXJjcyDigJQgdG9wLXJpZ2h0LCByZXByZXNlbnRzIHRoZSByb3V0ZXIgLS0+CiAgPHBhdGggZD0iTTQzLDEzIFE1MCw3ICA1NywxMyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjQ1Ii8+CiAgPHBhdGggZD0iTTQ2LDE3IFE1MCwxMyA1NCwxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjc1Ii8+CiAgPGNpcmNsZSBjeD0iNTAiIGN5PSIyMSIgcj0iMi4yIiBmaWxsPSIjZmM0YzAyIi8+CgogIDwhLS0gT3V0ZXIgcmluZyAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLW9wYWNpdHk9IjAuMzUiLz4KPC9zdmc+Cg==" type="image/svg+xml">
<style>
:root{--bg:#fafafa;--surface:#fff;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--text-5:#999;--text-7:#777;--border:#eee;--border-2:#ccc;--row-alt:#fafafa;--accent:#fc4c02;--accent-light:#fc9172;--select-bg:#fff;--tooltip-bg:rgba(20,20,20,.92);--hi-row:#fff5f0;--avg-line:#f5c400;--text-6:#555}
@media(prefers-color-scheme:dark){:root{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--text-5:#606060;--text-7:#707070;--border:#2a2a2a;--border-2:#3a3a3a;--row-alt:#1a1a1a;--select-bg:#1e1e1e;--tooltip-bg:rgba(10,10,10,.95);--hi-row:#1f1108;--text-6:#a0a0a0}}
[data-theme=light]{--bg:#fafafa;--surface:#fff;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--text-5:#999;--text-7:#777;--border:#eee;--border-2:#ccc;--row-alt:#fafafa;--select-bg:#fff;--tooltip-bg:rgba(20,20,20,.92);--hi-row:#fff5f0;--text-6:#555}
[data-theme=dark]{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--text-5:#606060;--text-7:#707070;--border:#2a2a2a;--border-2:#3a3a3a;--row-alt:#1a1a1a;--select-bg:#1e1e1e;--tooltip-bg:rgba(10,10,10,.95);--hi-row:#1f1108;--text-6:#a0a0a0}
body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1100px;padding:0 1rem;background:var(--bg);color:var(--text)}
h1{margin:0 0 .25rem;font-size:1.6rem}
h2{font-size:.78rem;font-weight:700;margin:1.6rem 0 .5rem;color:var(--text-4);text-transform:uppercase;letter-spacing:.06em}
a{color:var(--accent)}
.crumbs{font-size:.85rem;margin:0 0 .75rem}
.meta{color:var(--text-3);font-size:.85rem;margin:.4rem 0 .75rem}
.filters{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin:.5rem 0 .85rem}
select{font:inherit;padding:.35rem .5rem;border:1px solid var(--border-2);border-radius:.4rem;background:var(--select-bg);color:var(--text);cursor:pointer}
.kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(145px,1fr));gap:.5rem;margin:.25rem 0 .5rem}
.kpi{background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.65rem .85rem}
.kpi .k{font-size:.68rem;text-transform:uppercase;letter-spacing:.05em;color:var(--text-5);font-weight:600}
.kpi .v{font-size:1.5rem;font-weight:700;font-variant-numeric:tabular-nums;color:var(--accent);line-height:1.2;margin:.05rem 0}
.kpi .s{font-size:.75rem;color:var(--text-7)}
table{border-collapse:collapse;width:100%;background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);margin:.25rem 0}
th,td{padding:.42rem .65rem;text-align:left;border-bottom:1px solid var(--border);white-space:nowrap}
th{background:#fc4c02;color:#fff}
td.num{text-align:right;font-variant-numeric:tabular-nums}
tr:nth-child(even) td{background:var(--row-alt)}
tr.hi td{background:var(--hi-row)!important;font-weight:600}
.muted{color:var(--text-4);font-size:.85rem}
.cmp td.c0{background:var(--surface);color:var(--text-4)}
.cmp td.c1{background:#ffeee6;color:#222}
.cmp td.c2{background:#ffcaab;color:#222}
.cmp td.c3{background:#ff9a6c;color:#222}
.cmp td.c4{background:#fc4c02;color:#fff;font-weight:600}
@media(prefers-color-scheme:dark){.cmp td.c1{background:#2d1200;color:#c07450}.cmp td.c2{background:#3d1a00;color:#d4896a}.cmp td.c3{background:#572500;color:#e8a07a}}
[data-theme=dark] .cmp td.c1{background:#2d1200;color:#c07450}
[data-theme=dark] .cmp td.c2{background:#3d1a00;color:#d4896a}
[data-theme=dark] .cmp td.c3{background:#572500;color:#e8a07a}
[data-theme=light] .cmp td.c1{background:#ffeee6;color:#222}
[data-theme=light] .cmp td.c2{background:#ffcaab;color:#222}
[data-theme=light] .cmp td.c3{background:#ff9a6c;color:#222}
.cmp td.yoy-pos{color:#1a7a3a;font-weight:600}
.cmp td.yoy-neg{color:#c62828;font-weight:600}
@media(prefers-color-scheme:dark){.cmp td.yoy-pos{color:#4caf72}.cmp td.yoy-neg{color:#ef9a9a}}
[data-theme=dark] .cmp td.yoy-pos{color:#4caf72}
[data-theme=dark] .cmp td.yoy-neg{color:#ef9a9a}
.chart-box{background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.65rem .9rem;margin:.25rem 0}
.chart-box h3{margin:0 0 .4rem;font-size:.75rem;color:var(--text-4);font-weight:700;text-transform:uppercase;letter-spacing:.05em}
svg.bar{width:100%;display:block}
.recs{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:.5rem;margin:.25rem 0}
.rec{background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.6rem .85rem}
.rec .rl{font-size:.68rem;text-transform:uppercase;letter-spacing:.05em;color:var(--text-5);font-weight:600}
.rec .rv{font-size:1.2rem;font-weight:700;color:var(--accent);font-variant-numeric:tabular-nums;margin:.1rem 0}
.rec .rs{font-size:.78rem;color:var(--text-3);white-space:pre-line}
#tip{display:none;position:fixed;background:var(--tooltip-bg);color:#fff;padding:.42rem .7rem;
     border-radius:.4rem;font-size:.8rem;pointer-events:none;z-index:100;
     white-space:pre;line-height:1.65;box-shadow:0 2px 8px rgba(0,0,0,.3)}
.empty{color:var(--text-4);padding:.4rem 0;font-size:.9rem}
#pbar{position:fixed;top:0;left:0;width:0;height:3px;background:var(--accent);z-index:9999;pointer-events:none}
#theme-tog{margin-left:auto;flex-shrink:0;background:none;border:none;font-size:1.2rem;cursor:pointer;line-height:1;padding:.2rem .4rem;border-radius:.3rem;color:var(--text-3)}
#yearTable,#moTable,#cmpTable,#sportTable{overflow-x:auto;-webkit-overflow-scrolling:touch}
@media(max-width:640px){body{margin:.75rem auto}#hdr{flex-wrap:wrap}h1{font-size:1.1rem}.kpis{grid-template-columns:repeat(auto-fill,minmax(120px,1fr))}.recs{grid-template-columns:repeat(2,1fr)}}
.goal-wrap{background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.8rem 1rem;margin:.25rem 0}
.goal-input-row{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap;margin-bottom:.5rem}
.goal-input-row input{font:inherit;padding:.3rem .45rem;border:1px solid var(--border-2);border-radius:.35rem;background:var(--select-bg);color:var(--text);width:90px}
.goal-btn{font:inherit;padding:.3rem .75rem;border-radius:.35rem;background:var(--accent);color:#fff;cursor:pointer;border:none;font-size:.85rem}
.goal-stats{font-size:.88rem;color:var(--text-2);margin:.35rem 0}
.goal-done{font-weight:700;color:var(--accent)}
.goal-bar-outer{height:11px;background:var(--border);border-radius:6px;overflow:hidden}
.goal-bar-inner{height:100%;background:var(--accent);border-radius:6px;transition:width .4s}
.goal-note{font-size:.75rem;color:var(--text-4);margin:.25rem 0 0}
.goal-months{display:grid;grid-template-columns:repeat(6,1fr);gap:.3rem .5rem;margin-top:.75rem}
@media(max-width:580px){.goal-months{grid-template-columns:repeat(4,1fr)}}
@media(max-width:400px){.goal-months{grid-template-columns:repeat(3,1fr)}}
.goal-mo{font-size:.72rem}
.goal-mo-lbl{font-weight:600;color:var(--text-4);text-transform:uppercase;letter-spacing:.03em}
.goal-mo-bar{height:5px;background:var(--border);border-radius:3px;margin:.15rem 0;overflow:hidden}
.goal-mo-fill{height:100%;border-radius:3px}
.mo-hit  .goal-mo-fill{background:#22c55e}
.mo-cur  .goal-mo-fill{background:#fb923c}
.mo-past .goal-mo-fill{background:#60a5fa}
.mo-fut  .goal-mo-fill{background:var(--border-2)}
.goal-mo-num{color:var(--text-5);font-size:.67rem;white-space:nowrap}
.sec-handle{display:inline-block;cursor:grab;padding:.1rem .25rem;color:var(--text-3);font-size:.9rem;vertical-align:middle;user-select:none;margin-right:.25rem;opacity:.6;border-radius:.2rem}
.sec-handle:hover{opacity:1;color:var(--accent)}
.sec-handle:active{cursor:grabbing}
.sec.sec-dragging{opacity:.4}
.sec.sec-drag-over{outline:2px dashed var(--accent);outline-offset:2px}
.sec-order-reset{font-size:.72rem;color:var(--text-3);background:none;border:1px solid var(--border-2);border-radius:.25rem;padding:.15rem .5rem;cursor:pointer;display:block;margin-left:auto;margin-bottom:.4rem}
.sec-order-reset:hover{color:var(--accent);border-color:var(--accent)}
@media(pointer:coarse){.sec-handle,.sec-order-reset{display:none}}
</style>
</head>
<body>
<div id="pbar"></div>
<div id="tip"></div>
<div class="crumbs"><a href="index.html">&larr; My Activities</a> &middot; <a href="bike.html">🔧 Bike service</a></div>
<div id="hdr" style="display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="36" height="36" aria-hidden="true"><defs><clipPath id="clip"><circle cx="32" cy="32" r="30"/></clipPath><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs><circle cx="32" cy="32" r="32" fill="url(#bg)"/><g clip-path="url(#clip)"><polygon points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32 60,56 4,56" fill="#fc4c02" fill-opacity="0.15"/><polyline points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32" fill="none" stroke="#fc4c02" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="46" r="2.5" fill="#fc4c02"/><circle cx="60" cy="32" r="2.5" fill="#fc4c02"/></g><path d="M43,13 Q50,7 57,13" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.45"/><path d="M46,17 Q50,13 54,17" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/><circle cx="50" cy="21" r="2.2" fill="#fc4c02"/><circle cx="32" cy="32" r="31" fill="none" stroke="#fc4c02" stroke-width="0.8" stroke-opacity="0.35"/></svg><h1 style="margin:0">My Stats</h1><button id="theme-tog">🌙</button></div>
<div class="meta" id="meta">Loading…</div>

<div class="filters">
  <label>Sport&nbsp;<select id="sportSel"></select></label>
  <label>Year&nbsp;<select id="yearSel"></select></label>
</div>

<div id="sec-wrap">
<div class="sec" data-sid="kpis">
<div class="kpis" id="kpis"></div>
</div>
<div class="sec" data-sid="goals">
<div id="goalsSection"></div>
</div>

<div class="sec" data-sid="records">
<h2>Personal records <span id="recsSubtitle" class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; all time &middot; all sports</span></h2>
<div class="recs" id="recs"></div>
</div>

<div class="sec" data-sid="year">
<h2>Year overview</h2>
<div id="yearTable"></div>
</div>

<div class="sec" data-sid="monthly-chart">
<h2 id="moTitle">Monthly breakdown</h2>
<div class="meta" id="moDesc" style="margin:.1rem 0 .5rem"></div>
<div class="chart-box"><h3 id="moChartTitle">Distance per month (km)</h3><svg class="bar" id="moSvg" viewBox="0 0 480 130" preserveAspectRatio="none"></svg></div>
</div>
<div class="sec" data-sid="monthly-table">
<div id="moTable"></div>
</div>

<div class="sec" data-sid="comparison">
<h2>Year comparison <span class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; km per month</span></h2>
<div id="cmpTable"></div>
</div>

<div class="sec" data-sid="sport">
<h2>By sport <span id="sportSubtitle" class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; all time</span></h2>
<div id="sportTable"></div>
</div>

<div class="sec" data-sid="dow">
<h2>Average per day of week <span id="dowSubtitle" class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; selected sport &middot; all years</span></h2>
<div class="chart-box"><h3>Avg distance per weekday (km)</h3><svg class="bar" id="dowSvg" viewBox="0 0 280 120" preserveAspectRatio="none"></svg></div>
</div>
</div>

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
  var longest=null, longest_t=null, most_e=null, fastest=null, max_spd=null;
  var most_pow=null, most_kj=null, most_vam=null, most_steps=null;
  var weeks={}, months={}, months_count={}, dates={};
  var _stepSports={Walk:1,Hike:1};
  acts.forEach(function(a){
    var km=(a.distance||0)/1000, s=a.moving_time||0, e=a.total_elevation_gain||0;
    var pow=a.weighted_average_watts||a.average_watts||0;
    var kj=a.kilojoules||0;
    var vam=(s>0&&e>=100)?(e/(s/3600)):0;
    if(!longest   ||km>longest.km)   longest  ={km:km,s:s,e:e,date:a.date,name:a.name,id:a.id};
    if(!longest_t ||s>longest_t.s)   longest_t={km:km,s:s,  date:a.date,name:a.name,id:a.id};
    if(!most_e    ||e>most_e.e)      most_e   ={km:km,s:s,e:e,date:a.date,name:a.name,id:a.id};
    if(km>=20){
      var spd=s>0?(km/s)*3600:0;
      if(!fastest||spd>fastest.spd)  fastest  ={spd:spd,km:km,date:a.date,name:a.name,id:a.id};
    }
    var mspd=(a.max_speed||0)*3.6;
    if(mspd>0&&(!max_spd||mspd>max_spd.spd))
      max_spd={spd:mspd,km:km,date:a.date,name:a.name,id:a.id};
    if(pow>0&&(!most_pow||pow>most_pow.pow))
      most_pow={pow:pow,km:km,s:s,date:a.date,name:a.name,id:a.id};
    if(kj>0&&(!most_kj||kj>most_kj.kj))
      most_kj={kj:kj,km:km,s:s,date:a.date,name:a.name,id:a.id};
    if(vam>0&&(!most_vam||vam>most_vam.vam))
      most_vam={vam:vam,e:e,km:km,s:s,date:a.date,name:a.name,id:a.id};
    if(_stepSports[a.sport_type]&&a.average_cadence&&s>0){
      var st=Math.round(a.average_cadence*2*s/60);
      if(!most_steps||st>most_steps.steps)
        most_steps={steps:st,km:km,s:s,date:a.date,name:a.name,id:a.id};
    }
    if(a.date){
      weeks[weekOf(a.date)]=(weeks[weekOf(a.date)]||0)+km;
      var ym=a.date.slice(0,7);
      months[ym]=(months[ym]||0)+km;
      months_count[ym]=(months_count[ym]||0)+1;
      dates[a.date]=1;
    }
  });
  var bwk=null,bwkKm=0;
  Object.keys(weeks).forEach(function(w){ if(weeks[w]>bwkKm){bwkKm=weeks[w];bwk=w;} });
  var bmo=null,bmoKm=0;
  Object.keys(months).forEach(function(m){ if(months[m]>bmoKm){bmoKm=months[m];bmo=m;} });
  var bmoCount=null,bmoCountN=0;
  Object.keys(months_count).forEach(function(m){ if(months_count[m]>bmoCountN){bmoCountN=months_count[m];bmoCount=m;} });

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
    longest:longest, longest_t:longest_t, most_e:most_e, fastest:fastest, max_spd:max_spd,
    most_pow:most_pow, most_kj:most_kj, most_vam:most_vam, most_steps:most_steps,
    bwk:bwk?{week:bwk,km:bwkKm}:null,
    bmo:bmo?{month:bmo,km:bmoKm}:null,
    bmoCount:bmoCount?{month:bmoCount,n:bmoCountN}:null,
    streak:sorted.length?{n:maxStr,from:sFrom,to:sTo}:null
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
// Sets the dashboard filter in sessionStorage so index.html restores it on load.
window._gf=function(y,m,s){
  try{sessionStorage.setItem('activityFilter',JSON.stringify({year:y,month:m,sport:s}));}catch(e){}
};

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
    var fill = b.hi?"var(--accent)":"var(--accent-light)";
    var tipTxt = b.tip || b.label;
    return '<rect x="'+x+'" y="'+y+'" width="'+bw+'" height="'+bh+'"'+
           ' fill="'+fill+'" rx="1"'+
           ' onmouseenter="showTip(event,'+esc(JSON.stringify(tipTxt))+')"'+
           ' onmousemove="moveTip(event)" onmouseleave="hideTip()"'+
           ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+esc(JSON.stringify(tipTxt))+')"'+
           ' ontouchend="setTimeout(hideTip,3000)" style="cursor:default"/>'+
      (bh>14?'<text x="'+(x+bw/2)+'" y="'+(y-2)+'"'+
             ' text-anchor="middle" font-size="8.5" fill="var(--text-6)">'+fmtKmD(b.val||0)+'</text>':'')+
      '<text x="'+(x+bw/2)+'" y="'+(viewH-3)+'"'+
            ' text-anchor="middle" font-size="9" fill="var(--text-4)">'+esc(b.label)+'</text>';
  });
  svg.innerHTML = parts.join("");
}

// ---- Annual Goals & Progress ------------------------------------------------
// Stored in /cgi-bin/ride-goals (GET/POST, same pattern as bike-service).
// Goals JSON: { "goals": { "2025": 7500, "2026": 8000 }, "updatedAt": "…" }

var _goalsCache = null; // in-memory after first load

function _goalUrl(){ return "/cgi-bin/ride-goals"; }

function _loadGoals(cb){
  if(_goalsCache){ cb(_goalsCache); return; }
  fetch(_goalUrl(),{cache:"no-store"})
    .then(function(r){ return r.ok?r.json():Promise.reject(r.status); })
    .then(function(d){ _goalsCache=d; cb(d); })
    .catch(function(){ _goalsCache={goals:{}}; cb(_goalsCache); });
}

function _saveGoals(data, cb){
  _goalsCache=data;
  fetch(_goalUrl(),{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify(data)
  }).then(function(r){ return r.ok?r.json():Promise.reject(r.status); })
    .then(function(d){ _goalsCache=d; if(cb) cb(null,d); })
    .catch(function(e){ if(cb) cb(e); });
}

// Distribute yearGoal across 12 months based on prev-year ride proportions.
// Months with no prev-year data each get the equal base (yearGoal/12);
// months with data proportionally share the remaining budget.
// Fallback to equal split when no prev-year data at all.
function _moTargets(yearGoal, allActs, yearStr){
  var prevY=String(+yearStr-1);
  var prevRides=allActs.filter(function(a){
    return a.sport_type==="Ride"&&a.date&&a.date.slice(0,4)===prevY;
  });
  var byMo=[0,0,0,0,0,0,0,0,0,0,0,0], tot=0;
  prevRides.forEach(function(a){
    var m=+a.date.slice(5,7)-1;
    byMo[m]+=(a.distance||0)/1000; tot+=(a.distance||0)/1000;
  });
  if(tot===0) return byMo.map(function(){ return yearGoal/12; });
  var nZero=byMo.filter(function(v){return v===0;}).length;
  if(nZero===0) return byMo.map(function(v){return v/tot*yearGoal;});
  var base=yearGoal/12;
  var remaining=yearGoal-base*nZero;
  return byMo.map(function(v){ return v===0?base:(v/tot)*remaining; });
}

function renderGoals(goalsData){
  var el=document.getElementById("goalsSection");
  if(!el) return;
  var yr=selYear&&selYear!=="all"?selYear:null;
  var isRideSport=(selSport==="Ride"||selSport==="All"||!selSport);
  if(!yr||!isRideSport){ el.innerHTML=""; return; }

  var gmap=goalsData.goals||{};
  var goal=gmap[yr]!=null?gmap[yr]:null;
  // auto-copy from previous year when no goal set yet
  if(goal==null){
    var prev=String(+yr-1);
    if(gmap[prev]!=null) goal=gmap[prev];
  }

  var allRides=ALL_ACTS.filter(function(a){return a.sport_type==="Ride";});
  var yrRides=allRides.filter(function(a){return a.date&&a.date.slice(0,4)===yr;});
  var doneKm=0;
  yrRides.forEach(function(a){doneKm+=(a.distance||0)/1000;});

  var now=new Date(), nowYr=now.getFullYear(), isCurrentYear=(+yr===nowYr);
  var daysInYear=(+yr%4===0&&(+yr%100!==0||+yr%400===0))?366:365;
  var dayOfYear=isCurrentYear
    ?Math.floor((now-new Date(yr+"-01-01T00:00:00"))/86400000)+1
    :daysInYear;
  var projected=isCurrentYear&&dayOfYear>0
    ?Math.round(doneKm/dayOfYear*daysInYear*10)/10
    :doneKm;

  var inputVal=goal!=null?Math.round(goal):"";
  var prevY=String(+yr-1);
  var prevHint=goal==null&&gmap[prevY]!=null
    ?" (copied from "+prevY+")"
    :"";

  var h='<h2>Annual Goals &amp; Progress <span class="muted" style="font-size:.78rem;font-weight:400;text-transform:none">&mdash; '+esc(yr)+' &middot; Ride</span></h2>';
  h+='<div class="goal-wrap">';
  h+='<div class="goal-input-row">';
  h+='<label>Yearly target&nbsp;<input id="goalKmInput" type="number" min="0" step="100" value="'+inputVal+'" placeholder="e.g. 8000"> km</label>';
  h+='<button class="goal-btn" id="goalKmSave">Save</button>';
  if(prevHint) h+='<span class="muted" style="font-size:.8rem">'+esc(prevHint)+'</span>';
  h+='</div>';

  if(goal!=null&&goal>0){
    var pct=Math.min(100,Math.round(doneKm/goal*100));
    var projPct=Math.round(projected/goal*100);
    var moTgts=_moTargets(goal,ALL_ACTS,yr);
    var curMoIdx=isCurrentYear?now.getMonth():11;
    // prev-year monthly km for tooltip
    var prevByMo=[0,0,0,0,0,0,0,0,0,0,0,0];
    ALL_ACTS.forEach(function(a){
      if(a.sport_type==="Ride"&&a.date&&a.date.slice(0,4)===prevY){
        prevByMo[+a.date.slice(5,7)-1]+=(a.distance||0)/1000;
      }
    });

    // Distribution source note + per-month breakdown for tooltip
    var _prevTot=0, _nPrevZero=0;
    prevByMo.forEach(function(v){_prevTot+=v; if(v===0) _nPrevZero++;});
    var _distNote=_prevTot===0
      ?"Equal split (no "+prevY+" data)"
      :_nPrevZero>0
        ?"Based on "+prevY+" · equal base for "+_nPrevZero+" month"+(_nPrevZero===1?"":"s")+" with no data"
        :"Based on "+prevY+" proportions";
    var _distRows=["Monthly distribution — "+_distNote+":"];
    for(var _di=0;_di<12;_di+=4){
      var _row="";
      for(var _dj=_di;_dj<_di+4;_dj++){
        var _pct=goal>0?(moTgts[_dj]/goal*100):0;
        _row+=MONTHS_S[_dj]+" "+fmtKmD(moTgts[_dj])+" ("+_pct.toFixed(1)+"%)  ";
      }
      _distRows.push(_row.trimRight?_row.trimRight():_row.replace(/\s+$/,""));
    }
    var _distTip=_distRows.join("\n");
    var _dtJ=esc(JSON.stringify(_distTip));
    var _dta=' onmouseenter="showTip(event,'+_dtJ+')"'+
             ' onmousemove="moveTip(event)" onmouseleave="hideTip()"'+
             ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+_dtJ+')"'+
             ' ontouchend="setTimeout(hideTip,3000)"'+
             ' style="cursor:help"';
    h+='<div class="goal-stats"'+_dta+'><span class="goal-done">'+fmtKmD(doneKm)+' km</span> of '+fmtKmD(goal)+' km &mdash; <strong>'+pct+'%</strong>';
    if(isCurrentYear) h+=' &middot; projected <strong>'+fmtKmD(projected)+' km</strong> ('+projPct+'%)';
    h+='</div>';
    h+='<div class="goal-bar-outer"><div class="goal-bar-inner" style="width:'+pct+'%"></div></div>';

    if(isCurrentYear){
      var remaining=Math.max(0,goal-doneKm);
      var daysLeft=daysInYear-dayOfYear;
      h+='<div class="goal-note">';
      if(projPct>=100){
        h+=fmtKmD(projected-goal)+' km surplus projected';
      } else {
        h+=fmtKmD(remaining)+' km remaining';
        if(daysLeft>0) h+=' &middot; need '+fmtKmD(remaining/daysLeft)+' km/day to finish';
      }
      h+='</div>';
    }

    h+='<div class="goal-months">';
    MONTHS_S.forEach(function(moName,mi){
      var moDone=0;
      yrRides.forEach(function(a){
        if(+a.date.slice(5,7)-1===mi) moDone+=(a.distance||0)/1000;
      });
      var moTgt=moTgts[mi];
      var moPct=moTgt>0?Math.min(100,Math.round(moDone/moTgt*100)):0;
      var isPast=isCurrentYear?mi<curMoIdx:mi<=11;
      var isCur=isCurrentYear&&mi===curMoIdx;
      var cls=moDone>=moTgt&&moTgt>0?"mo-hit":(isCur?"mo-cur":(isPast?"mo-past":"mo-fut"));
      var tip=MONTHS_F[mi]+"\n"+
        yr+":    "+fmtKmD(moDone)+" km\n"+
        prevY+": "+fmtKmD(prevByMo[mi])+" km\n"+
        "Target:  "+fmtKmD(moTgt)+" km";
      var tipJ=esc(JSON.stringify(tip));
      var ta=' onmouseenter="showTip(event,'+tipJ+')"'+
             ' onmousemove="moveTip(event)" onmouseleave="hideTip()"'+
             ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+tipJ+')"'+
             ' ontouchend="setTimeout(hideTip,3000)"';
      h+='<div class="goal-mo '+cls+'" style="cursor:default"'+ta+'>';
      h+='<div class="goal-mo-lbl">'+moName+'</div>';
      h+='<div class="goal-mo-bar"><div class="goal-mo-fill" style="width:'+moPct+'%"></div></div>';
      h+='<div class="goal-mo-num">'+fmtKmD(moDone)+'&thinsp;/&thinsp;'+fmtKmD(moTgt)+'</div>';
      h+='</div>';
    });
    h+='</div>';
  } else {
    h+='<div class="muted" style="font-size:.85rem;padding:.15rem 0">Enter a yearly distance target to track your progress.</div>';
  }
  h+='</div>';
  el.innerHTML=h;

  var saveBtn=document.getElementById("goalKmSave");
  var inp=document.getElementById("goalKmInput");
  if(saveBtn&&inp){
    saveBtn.onclick=function(){
      var v=parseFloat(inp.value);
      if(isNaN(v)||v<0) return;
      var updated={goals:{},updatedAt:""};
      var g=_goalsCache?(_goalsCache.goals||{}):{};
      Object.keys(g).forEach(function(k){updated.goals[k]=g[k];});
      updated.goals[yr]=v;
      saveBtn.disabled=true; saveBtn.textContent="Saving…";
      _saveGoals(updated,function(err){
        saveBtn.disabled=false; saveBtn.textContent="Save";
        if(err){ alert("Failed to save goal — is the CGI installed?"); return; }
        renderGoals(_goalsCache);
      });
    };
    inp.addEventListener("keydown",function(e){ if(e.key==="Enter") saveBtn.click(); });
  }
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
  document.getElementById("recsSubtitle").innerHTML = "— all time · " + (selSport && selSport!=="All" ? esc(selSport) : "all sports");
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
  // Steps — estimated from cadence for Walk/Hike activities (cadence in strides/min × 2)
  var _walkSports = {Walk:1, Hike:1};
  var _totalSteps = 0;
  fyAll.forEach(function(a){
    if(_walkSports[a.sport_type] && a.average_cadence && a.moving_time)
      _totalSteps += Math.round(a.average_cadence * 2 * a.moving_time / 60);
  });
  var _showSteps = (_totalSteps > 0) &&
    (!selSport || selSport==="All" || _walkSports[selSport]);

  var _kpis = [
    {k:"Distance",        v:fmtKm(a.distM)+" km"},
    {k:"Moving time",     v:fmtH(a.secs)},
    {k:"Elevation",       v:fmtInt(Math.round(a.elev))+" m"},
    {k:"Activities",      v:fmtInt(a.n), s:nDays+" / "+_pDays+" days",
     tip:nDays+" active days out of "+_pDays+" calendar days in period"},
    {k:"Avg km / week",   v:fmtKmD(apw)+" km"},
    {k:"Avg km / activity",v:a.n?fmtKmD(a.distM/1000/a.n)+" km":"—"},
    {k:"Avg speed",       v:fmtSpd(a.distM,a.secs)}
  ];
  if(_showSteps)
    _kpis.push({k:"Steps (walk)", v:fmtInt(_totalSteps),
      tip:"Estimated steps from Walk & Hike activities that have cadence data (cadence × 2 × time). Activities without cadence are not counted."});
  document.getElementById("kpis").innerHTML = _kpis.map(function(kp){
    var ta = kp.tip
      ? ' onmouseenter="showTip(event,'+esc(JSON.stringify(kp.tip))+')"'+
        ' onmousemove="moveTip(event)" onmouseleave="hideTip()"'+
        ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+esc(JSON.stringify(kp.tip))+')"'+
        ' ontouchend="setTimeout(hideTip,3000)"'
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
    var cmpCurY=cmpYears[0], cmpPrevY=cmpYears[1];
    var cmpHead='<tr><th>Month</th><th>YoY</th>'+cmpYears.map(function(y){return '<th>'+y+'</th>';}).join("")+'</tr>';
    var cmpRows=MONTHS_S.map(function(mo,i){
      var cells=cmpYears.map(function(y){
        var v=cmpData[y][i];
        return '<td class="num '+heatCls(v)+'">'+(v?fmtKmD(v):'—')+'</td>';
      }).join("");
      var vCur=cmpData[cmpCurY][i], vPrev=cmpData[cmpPrevY][i];
      var isFuture=cmpCurY===curY&&i>curMo;
      var yoyCell;
      if(isFuture||(!vCur&&!vPrev)){
        yoyCell='<td class="num" style="color:var(--text-4)">—</td>';
      } else {
        var d=vCur-vPrev, sign=d>=0?'+':'', cls=d>0?'yoy-pos':d<0?'yoy-neg':'';
        var pct=vPrev>0?(d/vPrev*100):0;
        yoyCell='<td class="num '+cls+'" style="line-height:1.5">'+sign+fmtKmD(d)+' km<br>'+sign+pct.toFixed(1)+'%</td>';
      }
      return '<tr><td>'+mo+'</td>'+yoyCell+cells+'</tr>';
    }).join("");
    var cmpTots=cmpYears.map(function(y){return cmpData[y].reduce(function(s,v){return s+(v||0);},0);});
    var cmpTotCells=cmpYears.map(function(y,i){return '<td class="num"><strong>'+fmtKmD(cmpTots[i])+'</strong></td>';}).join("");
    var tD=cmpTots[0]-cmpTots[1], tSign=tD>=0?'+':'', tCls=tD>0?'yoy-pos':tD<0?'yoy-neg':'';
    var tPct=cmpTots[1]>0?(tD/cmpTots[1]*100):0;
    var cmpTotYoy='<td class="num '+tCls+'" style="line-height:1.5"><strong>'+tSign+fmtKmD(tD)+' km</strong><br>'+tSign+tPct.toFixed(1)+'%</td>';
    var cmpTotRow='<tr style="border-top:2px solid var(--border-2)"><td><strong>Total</strong></td>'+cmpTotYoy+cmpTotCells+'</tr>';
    document.getElementById("cmpTable").innerHTML=
      '<table class="cmp"><thead>'+cmpHead+'</thead><tbody>'+cmpRows+cmpTotRow+'</tbody></table>';
  } else {
    document.getElementById("cmpTable").innerHTML=
      '<div class="empty">Need at least 2 years of data for comparison.</div>';
  }

  // --- Personal records (all time, selected sport) ---
  var rec = computeRecords(fyAll);
  var ri  = [];
  function mkRec(l,v,s,lnk){
    return '<div class="rec"><div class="rl">'+esc(l)+'</div><div class="rv">'+esc(v)+'</div>'+
           '<div class="rs">'+esc(s)+'</div>'+(lnk||'')+'</div>';
  }
  function _aLink(id){
    return id?'<div style="font-size:.73rem;margin-top:.3rem"><a href="activity.html?id='+esc(String(id))+'">View activity →</a></div>':'';
  }
  function _fLink(year,month){
    var sp=(selSport&&selSport!=='All')?selSport:'all';
    var oc='_gf('+JSON.stringify(String(year))+','+JSON.stringify(String(month))+','+JSON.stringify(sp)+')';
    return '<div style="font-size:.73rem;margin-top:.3rem"><a href="index.html" onclick="'+esc(oc)+'">View activities →</a></div>';
  }
  if(rec.longest)
    ri.push(mkRec("Longest distance", fmtKmD(rec.longest.km)+" km",
                  rec.longest.date+"  "+fmtH(rec.longest.s)+"\n"+rec.longest.name, _aLink(rec.longest.id)));
  if(rec.longest_t)
    ri.push(mkRec("Longest "+(selSport&&selSport!=="All"?selSport.toLowerCase():"activity"), fmtH(rec.longest_t.s),
                  rec.longest_t.date+"  "+fmtKmD(rec.longest_t.km)+" km\n"+rec.longest_t.name, _aLink(rec.longest_t.id)));
  if(rec.most_e)
    ri.push(mkRec("Most elevation", fmtInt(Math.round(rec.most_e.e))+" m",
                  rec.most_e.date+"  "+fmtKmD(rec.most_e.km)+" km\n"+rec.most_e.name, _aLink(rec.most_e.id)));
  if(rec.fastest)
    ri.push(mkRec("Fastest avg speed", rec.fastest.spd.toFixed(1)+" km/h",
                  rec.fastest.date+"  "+fmtKmD(rec.fastest.km)+" km\n"+rec.fastest.name, _aLink(rec.fastest.id)));
  if(rec.max_spd)
    ri.push(mkRec("Max speed", rec.max_spd.spd.toFixed(1)+" km/h",
                  rec.max_spd.date+"  "+fmtKmD(rec.max_spd.km)+" km\n"+rec.max_spd.name, _aLink(rec.max_spd.id)));
  if(rec.most_pow)
    ri.push(mkRec("Most power", Math.round(rec.most_pow.pow)+" W",
                  rec.most_pow.date+"  "+fmtKmD(rec.most_pow.km)+" km\n"+rec.most_pow.name, _aLink(rec.most_pow.id)));
  if(rec.most_kj)
    ri.push(mkRec("Most work", fmtInt(Math.round(rec.most_kj.kj))+" kJ",
                  rec.most_kj.date+"  "+fmtKmD(rec.most_kj.km)+" km\n"+rec.most_kj.name, _aLink(rec.most_kj.id)));
  if(rec.most_vam)
    ri.push(mkRec("Best VAM", fmtInt(Math.round(rec.most_vam.vam))+" m/h",
                  rec.most_vam.date+"  "+fmtInt(Math.round(rec.most_vam.e))+" m elev\n"+rec.most_vam.name, _aLink(rec.most_vam.id)));
  if(rec.most_steps)
    ri.push(mkRec("Most steps", fmtInt(rec.most_steps.steps),
                  rec.most_steps.date+"  "+fmtKmD(rec.most_steps.km)+" km\n"+rec.most_steps.name, _aLink(rec.most_steps.id)));
  if(rec.bwk){
    var bwDate=rec.bwk.week;
    ri.push(mkRec("Best week (km)", fmtKmD(rec.bwk.km)+" km",
                  "week of "+bwDate, _fLink(bwDate.slice(0,4),+bwDate.slice(5,7))));
  }
  if(rec.bmo){
    var bm=rec.bmo.month;
    ri.push(mkRec("Best month (km)", fmtKmD(rec.bmo.km)+" km",
                  MONTHS_F[+bm.slice(5,7)-1]+" "+bm.slice(0,4), _fLink(bm.slice(0,4),+bm.slice(5,7))));
  }
  if(rec.bmoCount){
    var bmc=rec.bmoCount.month;
    ri.push(mkRec("Most activities", rec.bmoCount.n+" activit"+(rec.bmoCount.n===1?"y":"ies"),
                  MONTHS_F[+bmc.slice(5,7)-1]+" "+bmc.slice(0,4), _fLink(bmc.slice(0,4),+bmc.slice(5,7))));
  }
  if(rec.streak)
    ri.push(mkRec("Longest streak", rec.streak.n+" day"+(rec.streak.n===1?"":"s"),
                  rec.streak.from+" → "+rec.streak.to,
                  _fLink(rec.streak.from.slice(0,4),+rec.streak.from.slice(5,7))));
  document.getElementById("recs").innerHTML = ri.join("") || '<div class="empty">No data yet.</div>';

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

  // goals section renders from cached data (loaded once in load())
  if(_goalsCache) renderGoals(_goalsCache);
  if(typeof window._statsSecAfterRender==='function')window._statsSecAfterRender();
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
      // load goals in parallel; render immediately, then re-render with goal data
      render();
      _loadGoals(function(gd){ renderGoals(gd); });
    })
    .catch(function(e){
      progressDone();
      document.getElementById("meta").textContent="Error loading activities.json: "+e.message;
    });
}

document.getElementById("sportSel").addEventListener("change",function(){ selSport=this.value; render(); });
document.getElementById("yearSel").addEventListener("change",function(){ selYear=this.value; render(); });
load();
(function(){
  var STATS_SEC_KEY='ssb-stats-sec';
  var STATS_SEC_DEFAULT=['kpis','goals','records','year','monthly-chart','monthly-table','comparison','sport','dow'];
  var wrap=document.getElementById('sec-wrap');
  if(!wrap)return;
  var dragSrc=null;
  function getSecs(){return Array.prototype.filter.call(wrap.children,function(el){return el.classList.contains('sec');});}
  function saveOrder(){try{localStorage.setItem(STATS_SEC_KEY,JSON.stringify(getSecs().map(function(s){return s.getAttribute('data-sid');})));}catch(e){}}
  function applyOrder(){
    var saved=null;try{saved=JSON.parse(localStorage.getItem(STATS_SEC_KEY));}catch(e){}
    var order=(saved&&saved.length===STATS_SEC_DEFAULT.length)?saved:STATS_SEC_DEFAULT.slice();
    var secMap={};getSecs().forEach(function(s){secMap[s.getAttribute('data-sid')]=s;});
    order.forEach(function(sid){if(secMap[sid])wrap.appendChild(secMap[sid]);});
  }
  function doReset(){
    try{localStorage.removeItem(STATS_SEC_KEY);}catch(e){}
    var secMap={};getSecs().forEach(function(s){secMap[s.getAttribute('data-sid')]=s;});
    STATS_SEC_DEFAULT.forEach(function(sid){if(secMap[sid])wrap.appendChild(secMap[sid]);});
  }
  function dropInto(sid,e){
    if(!dragSrc||dragSrc===sid)return;
    var secs=getSecs();var srcEl=null,tgtEl=null;
    for(var i=0;i<secs.length;i++){if(secs[i].getAttribute('data-sid')===dragSrc)srcEl=secs[i];if(secs[i].getAttribute('data-sid')===sid)tgtEl=secs[i];}
    if(!srcEl||!tgtEl)return;
    var rect=tgtEl.getBoundingClientRect();
    if((e.clientY||0)<rect.top+rect.height/2)wrap.insertBefore(srcEl,tgtEl);else wrap.insertBefore(srcEl,tgtEl.nextSibling);
    getSecs().forEach(function(x){x.classList.remove('sec-drag-over');});
    saveOrder();
  }
  function ensureResetBtn(){
    if(wrap.querySelector('.sec-order-reset'))return;
    var rb=document.createElement('button');rb.className='sec-order-reset';rb.textContent='↺ Reset order';
    rb.onclick=function(){doReset();injectHandles();};
    wrap.insertBefore(rb,wrap.firstChild);
  }
  function injectHandles(){
    ensureResetBtn();
    getSecs().forEach(function(s){
      var old=s.querySelector('.sec-handle');if(old)old.parentNode.removeChild(old);
      var sid=s.getAttribute('data-sid');
      var handle=document.createElement('span');handle.className='sec-handle';handle.title='Drag to reorder';handle.textContent='⠿';
      handle.setAttribute('draggable','true');
      handle.addEventListener('dragstart',function(e){dragSrc=sid;s.classList.add('sec-dragging');if(e.dataTransfer){e.dataTransfer.effectAllowed='move';try{e.dataTransfer.setDragImage(s,0,0);}catch(_){}}e.stopPropagation();});
      handle.addEventListener('dragend',function(){s.classList.remove('sec-dragging');dragSrc=null;getSecs().forEach(function(x){x.classList.remove('sec-drag-over');});});
      s.ondragover=function(e){if(dragSrc&&dragSrc!==sid){e.preventDefault();s.classList.add('sec-drag-over');}};
      s.ondragleave=function(e){if(!s.contains(e.relatedTarget))s.classList.remove('sec-drag-over');};
      s.ondrop=function(e){e.preventDefault();dropInto(sid,e);};
      var h=s.querySelector('h2');
      if(h)h.insertBefore(handle,h.firstChild);else s.insertBefore(handle,s.firstChild);
    });
  }
  applyOrder();
  injectHandles();
  window._statsSecAfterRender=injectHandles;
})();
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

log "wrote $WEB_DIR/stats.html"

# --- Install the ride-goals CGI (read/write JSON store) ----------------------
# GET  -> stored goals document (or empty default).
# POST -> validate JSON (must be object with "goals" object), stamp updatedAt,
#         write atomically. Same trust model as bike-service: LAN-only, no auth.
mkdir -p "$CGI_DIR"
GOALS_DATA_DIR="$(dirname "$GOALS_DATA")"
mkdir -p "$GOALS_DATA_DIR"

{
  printf '%s\n' '#!/bin/sh'
  printf 'DATA_FILE=%s\n' "\"$GOALS_DATA\""
} > "$CGI_DIR/ride-goals"

cat >> "$CGI_DIR/ride-goals" <<'CGI'
# StravaStats for OpenWrt — ride-goals CGI (generated by strava-my-html-stats).
set -eu

emit_json() { printf 'Content-Type: application/json\r\n\r\n'; }
fail() {
  printf 'Status: %s\r\nContent-Type: application/json\r\n\r\n{"error":"%s"}\n' "$1" "$2"
  exit 0
}

DATA_DIR="$(dirname "$DATA_FILE")"
mkdir -p "$DATA_DIR" 2>/dev/null || true

method="${REQUEST_METHOD:-GET}"

if [ "$method" = "GET" ]; then
  emit_json
  if [ -f "$DATA_FILE" ]; then cat "$DATA_FILE"; else printf '{"goals":{}}\n'; fi
  exit 0
fi

if [ "$method" = "POST" ]; then
  len="${CONTENT_LENGTH:-0}"
  case "$len" in ''|*[!0-9]*) fail '411 Length Required' 'missing or invalid Content-Length' ;; esac
  [ "$len" -gt 0 ]      || fail '400 Bad Request' 'empty body'
  [ "$len" -le 65536 ]  || fail '413 Payload Too Large' 'body exceeds 64 kB'

  tmpbody="$DATA_FILE.body.$$"
  cat > "$tmpbody"
  [ -s "$tmpbody" ] || { rm -f "$tmpbody"; fail '400 Bad Request' 'empty body'; }
  jq -e 'type=="object" and (.goals|type=="object")' "$tmpbody" >/dev/null 2>&1 \
    || { rm -f "$tmpbody"; fail '400 Bad Request' 'body must be an object with a goals object'; }

  tmp="$DATA_FILE.tmp.$$"
  if jq --arg t "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '.updatedAt=$t' "$tmpbody" > "$tmp" 2>/dev/null; then
    rm -f "$tmpbody"
    mv "$tmp" "$DATA_FILE"
  else
    rm -f "$tmp" "$tmpbody"
    fail '500 Internal Server Error' 'failed to write store'
  fi

  emit_json
  cat "$DATA_FILE"
  exit 0
fi

fail '405 Method Not Allowed' 'use GET or POST'
CGI

chmod 0755 "$CGI_DIR/ride-goals"
log "installed ride-goals CGI -> $CGI_DIR/ride-goals (data: $GOALS_DATA)"
