# strava-my-html-bike.sh — sourced by strava-my-activities.sh.
# Writes $WEB_DIR/bike.html (the bike-service tracker page) and installs
# $CGI_DIR/bike-service (the read/write CGI that persists bike-service.json).
# Quoted heredocs: nothing shell-expanded; $BIKE_DATA is injected only into
# the CGI preamble before its quoted body.

# --- 6b. Render the bike-service tracker page ------------------------------
# Unlike every other page here, this one is read/WRITE: it loads its data from
# the CGI (section 6c) and POSTs the whole document back on every change. Bike
# mileage is computed in the browser from activities.json (sport_type "Ride",
# cumulative distance up to a chosen date) and the computed value is stored into
# bike-service.json so each part keeps an accurate historical snapshot even if
# the underlying Strava data later changes. Config is injected before the quoted
# heredoc (same pattern as the CGI preamble); the rest is shell-unexpanded.
{
  printf '%s\n' '<!doctype html><html lang="en"><head>'
  printf '<script>var _CFG={defaultBikeName:"%s",currency:"%s",emailConfigured:%s};</script>\n' \
    "$DEFAULT_BIKE_NAME" "${CURRENCY:-PLN}" "$([ -n "${BIKE_EMAIL:-}" ] && printf 'true' || printf 'false')"
} > "$WEB_DIR/bike.html"
cat >> "$WEB_DIR/bike.html" <<'HTML'
<script>var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t;</script>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bike Service</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN0YXRzU2VydmljZUJvb2siPgogIDxkZWZzPgogICAgPGNsaXBQYXRoIGlkPSJjbGlwIj4KICAgICAgPGNpcmNsZSBjeD0iMzIiIGN5PSIzMiIgcj0iMzAiLz4KICAgIDwvY2xpcFBhdGg+CiAgICA8bGluZWFyR3JhZGllbnQgaWQ9ImJnIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMyYTJhMmEiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMTExMTExIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KCiAgPCEtLSBCYWNrZ3JvdW5kIGNpcmNsZSAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMiIgZmlsbD0idXJsKCNiZykiLz4KCiAgPGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXApIj4KCiAgICA8IS0tIEFyZWEgZmlsbCB1bmRlciB0aGUgcm91dGUgbGluZSAtLT4KICAgIDxwb2x5Z29uCiAgICAgIHBvaW50cz0iNCw0NiAxMyw0NiAxOSwzMiAyNSw0MCAzMiwxOCAzOSwzMiA0NSwyNSA1MSwzMiA2MCwzMiA2MCw1NiA0LDU2IgogICAgICBmaWxsPSIjZmM0YzAyIiBmaWxsLW9wYWNpdHk9IjAuMTUiLz4KCiAgICA8IS0tIFJvdXRlIC8gZWxldmF0aW9uIHByb2ZpbGUg4oCUIHRoZSBjb3JlIGZlYXR1cmUgLS0+CiAgICA8cG9seWxpbmUKICAgICAgcG9pbnRzPSI0LDQ2IDEzLDQ2IDE5LDMyIDI1LDQwIDMyLDE4IDM5LDMyIDQ1LDI1IDUxLDMyIDYwLDMyIgogICAgICBmaWxsPSJub25lIgogICAgICBzdHJva2U9IiNmYzRjMDIiCiAgICAgIHN0cm9rZS13aWR0aD0iMy4yIgogICAgICBzdHJva2UtbGluZWNhcD0icm91bmQiCiAgICAgIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KCiAgICA8IS0tIEdQUyAvIHN0YXJ0IGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjQiIGN5PSI0NiIgcj0iMi41IiBmaWxsPSIjZmM0YzAyIi8+CgogICAgPCEtLSBGaW5pc2ggLyBjdXJyZW50LXBvc2l0aW9uIGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjYwIiBjeT0iMzIiIHI9IjIuNSIgZmlsbD0iI2ZjNGMwMiIvPgoKICA8L2c+CgogIDwhLS0gV2lGaSBzaWduYWwgYXJjcyDigJQgdG9wLXJpZ2h0LCByZXByZXNlbnRzIHRoZSByb3V0ZXIgLS0+CiAgPHBhdGggZD0iTTQzLDEzIFE1MCw3ICA1NywxMyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjQ1Ii8+CiAgPHBhdGggZD0iTTQ2LDE3IFE1MCwxMyA1NCwxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjc1Ii8+CiAgPGNpcmNsZSBjeD0iNTAiIGN5PSIyMSIgcj0iMi4yIiBmaWxsPSIjZmM0YzAyIi8+CgogIDwhLS0gT3V0ZXIgcmluZyAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLW9wYWNpdHk9IjAuMzUiLz4KPC9zdmc+Cg==" type="image/svg+xml">
<style>
:root{--bg:#fafafa;--surface:#fff;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--text-7:#777;--border:#eee;--border-2:#ccc;--border-3:#ddd;--row-alt:#fafafa;--accent:#fc4c02;--btn-bg:#fff;--select-bg:#fff;--input-bg:#fff;--warn-row:#fffde6;--hi-row:#fff5f0;--green:#4caf50;--red:#b00;--svc-bar-bg:#eee}
@media(prefers-color-scheme:dark){:root{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--text-7:#707070;--border:#2a2a2a;--border-2:#3a3a3a;--border-3:#333;--row-alt:#1a1a1a;--btn-bg:#2a2a2a;--select-bg:#1e1e1e;--input-bg:#252525;--warn-row:#2a2700;--hi-row:#1f1108;--red:#e05050;--svc-bar-bg:#2a2a2a}}
[data-theme=light]{--bg:#fafafa;--surface:#fff;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--text-7:#777;--border:#eee;--border-2:#ccc;--border-3:#ddd;--row-alt:#fafafa;--btn-bg:#fff;--select-bg:#fff;--input-bg:#fff;--warn-row:#fffde6;--hi-row:#fff5f0;--red:#b00;--svc-bar-bg:#eee}
[data-theme=dark]{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--text-7:#707070;--border:#2a2a2a;--border-2:#3a3a3a;--border-3:#333;--row-alt:#1a1a1a;--btn-bg:#2a2a2a;--select-bg:#1e1e1e;--input-bg:#252525;--warn-row:#2a2700;--hi-row:#1f1108;--red:#e05050;--svc-bar-bg:#2a2a2a}
body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1000px;padding:0 1rem;background:var(--bg);color:var(--text)}
h1{margin:0 0 .25rem;font-size:1.6rem}
h2{font-size:1.05rem;margin:1.25rem 0 .4rem}
a{color:var(--accent)}
.crumbs{font-size:.85rem;margin:0 0 .75rem}
.meta{color:var(--text-3);font-size:.85rem;margin:.6rem 0}
.bikes{display:flex;flex-wrap:wrap;gap:.4rem;align-items:center;margin:.5rem 0}
.tab{background:var(--surface);border:1px solid var(--border-3);border-radius:.4rem;padding:.35rem .7rem;cursor:pointer;font:inherit;color:var(--text-2)}
.tab.active{background:#fc4c02;border-color:#fc4c02;color:#fff;font-weight:600}
.tab.add{border-style:dashed;color:var(--accent)}
.panel{background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.5rem;padding:.85rem 1rem;margin:.5rem 0}
.odo{display:flex;flex-wrap:wrap;gap:1.25rem;align-items:baseline;margin:.2rem 0 .6rem}
.odo .big{font-size:1.8rem;font-weight:700;font-variant-numeric:tabular-nums;color:var(--accent)}
.odo .k{color:var(--text-4);font-size:.72rem;text-transform:uppercase;letter-spacing:.03em}
.odo-sub{color:var(--text-3);font-size:.85rem;margin-top:.1rem}
.btn{font:inherit;border:1px solid var(--border-2);background:var(--btn-bg);border-radius:.4rem;padding:.3rem .65rem;cursor:pointer;color:var(--text-2)}
.btn:hover{border-color:var(--accent);color:var(--accent)}
.btn.primary{background:#fc4c02;border-color:#fc4c02;color:#fff}
.btn.primary:hover{opacity:.9;color:#fff}
.btn.sm{padding:.18rem .45rem;font-size:.8rem}
.btn.danger:hover{border-color:var(--red);color:var(--red)}
table{border-collapse:collapse;width:100%;background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);margin:.3rem 0}
th,td{padding:.45rem .6rem;text-align:left;border-bottom:1px solid var(--border);vertical-align:top}
th{background:#fc4c02;color:#fff;white-space:nowrap}
td.num{text-align:right;font-variant-numeric:tabular-nums}
tr:nth-child(even) td{background:var(--row-alt)}
.muted{color:var(--text-4);font-size:.85rem}
.svc{color:var(--text-3);font-size:.82rem;margin:.1rem 0 0}
.empty{color:var(--text-3);padding:.6rem 0}
.archived td{color:var(--text-7)}
.ridesrow td{padding:0 .6rem .5rem;border-bottom:1px solid var(--border)}
details.rides summary{cursor:pointer;color:var(--text-3);font-size:.82rem;padding:.25rem 0;list-style:none}
details.rides summary::-webkit-details-marker{display:none}
details.rides summary::before{content:"▸ ";color:var(--accent)}
details.rides[open] summary::before{content:"▾ "}
table.ridetbl{box-shadow:none;margin:.15rem 0 .35rem;background:transparent}
table.ridetbl td{padding:.2rem .5rem;border-bottom:1px solid var(--border);font-size:.85rem}
table.ridetbl tr:nth-child(even) td{background:var(--row-alt)}
#err{color:var(--red);padding:.5rem 0}
tr.warn td{background:var(--warn-row)}
.svc-bar{height:4px;border-radius:2px;background:var(--svc-bar-bg);margin:.35rem 0 .1rem;overflow:hidden}
.svc-bar-fill{height:100%;border-radius:2px;transition:width .2s}
.svc-bar-fill.good{background:var(--green)}
.svc-bar-fill.warn{background:var(--accent)}
.svc-bar-fill.due{background:var(--red)}
.svc-pct{font-size:.7rem;color:var(--text-4)}
.svc-type-row{margin:.2rem 0}
.svc-type-label{font-size:.72rem;color:var(--text-4);font-weight:600;margin-bottom:.1rem}
.st-block{border:1px solid var(--border);border-radius:.35rem;padding:.45rem .55rem;margin:.3rem 0;background:var(--bg)}
.needs-repl{display:inline-block;background:var(--red);color:#fff;font-size:.68rem;font-weight:700;padding:.05rem .35rem;border-radius:.3rem;margin-left:.4rem;vertical-align:middle;white-space:nowrap}
#ovl{display:none;position:fixed;inset:0;background:rgba(0,0,0,.4);z-index:50}
#modal{background:var(--surface);max-width:460px;margin:6vh auto;border-radius:.6rem;padding:1.1rem 1.25rem;box-shadow:0 8px 30px rgba(0,0,0,.3);max-height:85vh;overflow-y:auto}
#modal h3{margin:0 0 .6rem}
#modal label{display:block;font-size:.82rem;color:var(--text-3);margin:.55rem 0 .15rem}
#modal input,#modal select,#modal textarea{font:inherit;width:100%;box-sizing:border-box;padding:.4rem .5rem;border:1px solid var(--border-2);border-radius:.4rem;background:var(--input-bg);color:var(--text)}
#modal textarea{resize:vertical;min-height:2.4rem}
#modal .row{display:flex;gap:.6rem}
#modal .row>div{flex:1}
#modal .actions{display:flex;justify-content:flex-end;gap:.5rem;margin-top:1rem;position:sticky;bottom:0;background:var(--surface);padding:.45rem 0 .1rem}
#modal .hint{font-size:.75rem;color:var(--text-4);margin-top:.15rem}
.chk{display:flex;align-items:center;gap:.45rem;margin-top:.7rem}
#modal .chk input{width:auto}
.chk label{display:inline;margin:0}
tr[draggable]{cursor:grab}
tr[draggable]:active{cursor:grabbing}
tr.dragging{opacity:.35}
tr.dragover td{background:var(--hi-row)!important;border-top:2px solid var(--accent)}
#pbar{position:fixed;top:0;left:0;width:0;height:3px;background:var(--accent);z-index:9999;pointer-events:none}
#theme-tog{margin-left:auto;flex-shrink:0;background:none;border:none;font-size:1.2rem;cursor:pointer;line-height:1;padding:.2rem .4rem;border-radius:.3rem;color:var(--text-3)}
.cost-block{margin:.5rem 0;background:var(--surface);border:1px solid var(--border);border-radius:.45rem;padding:.55rem .8rem}
.cost-total{font-size:1.1rem;font-weight:700;font-variant-numeric:tabular-nums;color:var(--text-2)}
.cost-yr-tbl{border-collapse:collapse;width:100%;margin:.35rem 0 0}
.cost-yr-tbl td{padding:.15rem .4rem;font-size:.83rem;border-bottom:1px solid var(--border);vertical-align:baseline}
.cost-yr-tbl td:last-child{text-align:right;font-variant-numeric:tabular-nums;font-weight:600}
details.cost-yr summary{cursor:pointer;font-size:.82rem;color:var(--text-4);list-style:none;padding:.2rem 0}
details.cost-yr summary::-webkit-details-marker{display:none}
details.cost-yr summary::before{content:"▸ ";color:var(--accent)}
details.cost-yr[open] summary::before{content:"▾ "}
@media(prefers-color-scheme:dark){#modal input,#modal select,#modal textarea,.st-block input,.st-block select{background:var(--input-bg)!important;color:var(--text)!important;border-color:var(--border-2)!important}}
[data-theme=dark] #modal input,[data-theme=dark] #modal select,[data-theme=dark] #modal textarea,[data-theme=dark] .st-block input,[data-theme=dark] .st-block select{background:#252525!important;color:#e0e0e0!important;border-color:#3a3a3a!important}
[data-theme=light] #modal input,[data-theme=light] #modal select,[data-theme=light] #modal textarea,[data-theme=light] .st-block input,[data-theme=light] .st-block select{background:#fff!important;color:#222!important;border-color:#ccc!important}
@media(max-width:640px){body{margin:.75rem auto}#hdr{flex-wrap:wrap}h1{font-size:1.1rem}#bikepanel table{display:block;overflow-x:auto;-webkit-overflow-scrolling:touch}}
</style>
</head>
<body>
<div id="pbar"></div>
<div class="crumbs"><a href="index.html">&larr; My Activities</a> &middot; <a href="stats.html">📊 My Stats</a> &middot; <a id="leaderboard-link" href="../" style="display:none">🏆 Club leaderboard</a></div>
<div id="hdr" style="display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="36" height="36" aria-hidden="true"><defs><clipPath id="clip"><circle cx="32" cy="32" r="30"/></clipPath><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs><circle cx="32" cy="32" r="32" fill="url(#bg)"/><g clip-path="url(#clip)"><polygon points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32 60,56 4,56" fill="#fc4c02" fill-opacity="0.15"/><polyline points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32" fill="none" stroke="#fc4c02" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="46" r="2.5" fill="#fc4c02"/><circle cx="60" cy="32" r="2.5" fill="#fc4c02"/></g><path d="M43,13 Q50,7 57,13" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.45"/><path d="M46,17 Q50,13 54,17" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/><circle cx="50" cy="21" r="2.2" fill="#fc4c02"/><circle cx="32" cy="32" r="31" fill="none" stroke="#fc4c02" stroke-width="0.8" stroke-opacity="0.35"/></svg><h1 style="margin:0">🔧 Bike Service</h1><button id="theme-tog">🌙</button></div>
<div class="meta" id="meta">Loading…</div>
<div id="err"></div>
<div class="bikes" id="bikes"></div>
<div id="bikepanel"></div>

<div id="ovl"><div id="modal"></div></div>

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

// ---- state ----------------------------------------------------------------
var ACT   = null;   // activities.json (rides + gear names)
var RIDES = [];     // [{date, km, gear}] sorted ascending by date
var GEARS = {};     // gear_id -> { name }
var DEFGEAR = "";   // default gear for untagged rides (most recently used bike)
var MODEL = { version: 1, bikes: [] };
var selBike = null; // selected bike id
var SAVING  = false;

// ---- helpers --------------------------------------------------------------
function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g, function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }
function todayStr(){
  var d = new Date();
  function p(n){ return (n<10?"0":"")+n; }
  return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate());
}
function uid(pfx){ return pfx + Date.now().toString(36) + Math.random().toString(36).slice(2,6); }
// km with a space as thousands separator and one decimal: 1234.5 -> "1 234.5".
function fmtKm(km){
  var s = (Math.round((km||0)*10)/10).toFixed(1);
  return s.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}
function fmtTime(s){
  var d=Math.floor(s/86400),h=Math.floor((s%86400)/3600),m=Math.floor((s%3600)/60);
  if(d>0) return d+"d "+h+"h "+m+"m";
  return h>0?h+"h "+m+"m":m+"m";
}
function fmtInt(n){ return Math.round(n||0).toString().replace(/\B(?=(\d{3})+(?!\d))/g," "); }
function fmtCost(c){ if(c==null||c===''||isNaN(+c)||+c===0) return ''; return (Math.round((+c)*100)/100).toFixed(2)+' '+((_CFG&&_CFG.currency)||'PLN'); }
function fmtSpan(first,last){
  if(!first||!last) return "";
  var ay=+first.slice(0,4),am=+first.slice(5,7);
  var by=+last.slice(0,4), bm=+last.slice(5,7);
  var months=(by-ay)*12+(bm-am)+1;
  if(months<1) months=1;
  var y=Math.floor(months/12),m=months%12,parts=[];
  if(y) parts.push(y+" year"+(y>1?"s":""));
  if(m) parts.push(m+" month"+(m>1?"s":""));
  return parts.join(" ");
}
// Exact calendar duration between two YYYY-MM-DD strings → "1 year 2 months 3 weeks 4 days".
function fmtDuration(from, to){
  if(!from||!to) return "";
  var a=new Date(from), b=new Date(to);
  if(isNaN(a.getTime())||isNaN(b.getTime())||b<a) return "";
  var totalDays=Math.round((b-a)/86400000);
  var years=Math.floor(totalDays/365);
  var rem=totalDays-years*365;
  var months=Math.floor(rem/30);
  rem=rem-months*30;
  var weeks=Math.floor(rem/7);
  var days=rem%7;
  var parts=[];
  if(years)  parts.push(years+" year"+(years>1?"s":""));
  if(months) parts.push(months+" month"+(months>1?"s":""));
  if(weeks)  parts.push(weeks+" week"+(weeks>1?"s":""));
  if(days||(parts.length===0)) parts.push(days+" day"+(days!==1?"s":""));
  return parts.join(" ");
}
function calendarDaysSince(fromDate){
  if(!fromDate) return 0;
  var a=new Date(fromDate),b=new Date(todayStr());
  if(isNaN(a.getTime())||isNaN(b.getTime())) return 0;
  return Math.max(0,Math.round((b-a)/86400000));
}
function alertTimeDays(st){
  var n=+st.alertTimeN||0; if(!n) return 0;
  var unit=st.alertTimeUnit||"months";
  if(unit==="weeks") return n*7;
  if(unit==="years") return n*365;
  return n*30;
}
function err(msg){ document.getElementById("err").textContent = msg || ""; }

// ---- mileage math (client-side, from activities.json) ---------------------
// True when ride r should count toward a bike. Three match paths:
//   • no gearId ("all rides") → every ride counts
//   • ride gear matches Strava gear ID or the bike's display name (bike-assign
//     overrides on the dashboard store the bike name, not the gear ID)
//   • bike is the default AND ride has no gear tag → untagged rides fall here
function rideMatchesBike(r, bike){
  var gearId = bike.gearId || "";
  if (!gearId) return true;
  if (r.gear === gearId) return true;
  if (r.gear && r.gear === bike.name) return true;
  if (bike.isDefault && !r.gear) return true;
  return false;
}
// Cumulative distance of outdoor rides up to (and including) a date.
function rideMileage(bike, dateStr){
  var sum = 0;
  for (var i=0;i<RIDES.length;i++){
    var r = RIDES[i];
    if (r.date > dateStr) continue;           // dates are "YYYY-MM-DD", lexical compare works
    if (!rideMatchesBike(r, bike)) continue;
    sum += r.km;
  }
  return sum;
}
function rideTimeSince(bike, fromDate){
  var t = 0;
  for (var i=0;i<RIDES.length;i++){
    var r = RIDES[i];
    if (fromDate && r.date < fromDate) continue;
    if (!rideMatchesBike(r, bike)) continue;
    t += r.time;
  }
  return t;  // seconds
}
function rideMileageSince(bike, fromDate){
  var sum = 0;
  for (var i=0;i<RIDES.length;i++){
    var r = RIDES[i];
    if (fromDate && r.date < fromDate) continue;
    if (!rideMatchesBike(r, bike)) continue;
    sum += r.km;
  }
  return sum;
}
function bikeMileage(bike, dateStr){
  return (+bike.baseMileage || 0) + rideMileage(bike, dateStr || todayStr());
}
function bikeTotals(bike, dateStr){
  var dt = dateStr || todayStr();
  var km = +bike.baseMileage || 0, time = 0, elev = 0, first = null, last = null;
  for (var i=0;i<RIDES.length;i++){
    var r = RIDES[i];
    if (r.date > dt) continue;
    if (!rideMatchesBike(r, bike)) continue;
    km += r.km; time += r.time; elev += r.elev;
    if (!first || r.date < first) first = r.date;
    if (!last  || r.date > last)  last  = r.date;
  }
  return { km:km, time:time, elev:elev, first:first, last:last };
}
// All costs on a bike as [{year, amount, label}].
function bikeAllCosts(bike){
  var costs=[];
  (bike.parts||[]).forEach(function(p){
    if(p.cost&&+p.cost>0){
      var yr=(p.installedDate||todayStr()).slice(0,4);
      costs.push({year:yr,amount:+p.cost,label:esc(p.name)+' <span class="muted">(part)</span>'});
    }
    (p.serviceTypes||[]).forEach(function(st){
      (st.services||[]).forEach(function(s){
        if(s.cost&&+s.cost>0){
          var yr=(s.date||todayStr()).slice(0,4);
          costs.push({year:yr,amount:+s.cost,label:esc(p.name)+' – '+esc(st.name)+' <span class="muted">(service)</span>'});
        }
      });
    });
  });
  return costs;
}
function bikeTotalCost(bike){
  var t=0; bikeAllCosts(bike).forEach(function(c){t+=c.amount;}); return t;
}
function bikePartsCostOnly(bike){
  var t=0;
  (bike.parts||[]).forEach(function(p){ if(p.cost&&+p.cost>0) t+=+p.cost; });
  return t;
}
function bikeServiceCostOnly(bike){
  var t=0;
  (bike.parts||[]).forEach(function(p){
    (p.serviceTypes||[]).forEach(function(st){
      (st.services||[]).forEach(function(s){ if(s.cost&&+s.cost>0) t+=+s.cost; });
    });
  });
  return t;
}
function bikeCostByYear(bike){
  var yr={};
  bikeAllCosts(bike).forEach(function(c){yr[c.year]=(yr[c.year]||0)+c.amount;});
  return yr;
}
// Sum of part purchase cost + all service costs for one part.
function partTotalCost(p){
  var t=p.cost&&+p.cost>0?+p.cost:0;
  (p.serviceTypes||[]).forEach(function(st){
    (st.services||[]).forEach(function(s){if(s.cost&&+s.cost>0)t+=+s.cost;});
  });
  return t;
}
// The activities counted toward a part, newest first: rides on the bike's gear
// (or every ride when the bike has no gear) ridden on/after the part was fitted,
// bounded by its archived date if it has one.
function partRides(bike, part){
  var lo = part.installedDate || "";
  var hi = part.archivedDate || "9999-12-31";
  var out = [];
  for (var i=0;i<RIDES.length;i++){
    var r = RIDES[i];
    if (lo && r.date < lo) continue;
    if (r.date > hi) continue;
    if (!rideMatchesBike(r, bike)) continue;
    out.push(r);
  }
  return out.sort(function(a,c){ return a.date < c.date ? 1 : -1; });   // newest → oldest
}
// Collapsible list of those rides, with a summary line (count + total km).
function ridesBlock(list){
  var sumKm = 0, sumTime = 0;
  list.forEach(function(r){ sumKm += r.km; sumTime += r.time; });
  if (!list.length) return '<div class="muted" style="margin:.2rem 0 .4rem">No rides recorded in this window.</div>';
  var rows = list.map(function(r){
    return '<tr><td>'+esc(r.date)+'</td><td>'+esc(r.name||"(untitled)")+'</td>'+
      '<td class="num">'+fmtKm(r.km)+' km</td>'+
      '<td class="num">'+fmtTime(r.time)+'</td></tr>';
  }).join("");
  return '<details class="rides"><summary>'+list.length+' ride'+(list.length===1?'':'s')+
    ' · '+fmtKm(sumKm)+' km · '+fmtTime(sumTime)+'</summary>'+
    '<table class="ridetbl"><tbody>'+rows+'</tbody></table></details>';
}
// The "Last service" cell: the most recent service shown as a summary line, plus
// a collapsible list of the full service history (same ▸ arrow as the rides
// lists) when there is more than one. Pass the part's services in any order.
function servicesBlock(services){
  var asc = (services||[]).slice().sort(function(a,c){ return a.date<c.date?-1:1; });
  if (!asc.length) return '<span class="muted">never</span>';
  var last = asc[asc.length-1];
  var lastCostStr = last.cost&&+last.cost>0?' · '+fmtCost(last.cost):'';
  var lastTxt = esc(last.date)+' @ '+fmtKm(last.mileage)+' km'+lastCostStr+
    (last.note?'<div class="muted">'+esc(last.note)+'</div>':'');
  if (asc.length === 1) return lastTxt;
  var rows = asc.slice().reverse().map(function(s){            // newest → oldest
    var costStr=s.cost&&+s.cost>0?' · '+fmtCost(s.cost):'';
    return '<tr><td>'+esc(s.date)+'</td><td class="num">'+fmtKm(s.mileage)+
      ' km</td><td>'+esc(s.note||"")+costStr+'</td></tr>';
  }).join("");
  return lastTxt +
    '<details class="rides"><summary>'+asc.length+' services</summary>'+
    '<table class="ridetbl"><tbody>'+rows+'</tbody></table></details>';
}
// Per-service-type % of alert threshold used since last service of that type (or install).
function stPct(bike,p,st){
  var svc=(st.services||[]).slice().sort(function(a,c){ return a.date<c.date?-1:1; });
  var last=svc.length?svc[svc.length-1]:null;
  var fromDate=last?last.date:(p.installedDate||"");
  var refMileage=last?(+last.mileage||0):(+p.installedMileage||0);
  var refKm=Math.max(0,bikeMileage(bike)-refMileage);
  var refH=rideTimeSince(bike,fromDate)/3600;
  var refDays=calendarDaysSince(fromDate);
  var pctKm=(st.alertKm&&+st.alertKm>0)?(refKm/+st.alertKm*100):0;
  var pctH=(st.alertH&&+st.alertH>0)?(refH/+st.alertH*100):0;
  var adv=alertTimeDays(st);
  var pctDays=(adv>0)?(refDays/adv*100):0;
  return Math.max(pctKm,pctH,pctDays);
}
// Worst % across all service types; 0 when no thresholds configured (used for sorting).
function partPct(bike,p){
  var types=p.serviceTypes||[];
  var max=0;
  types.forEach(function(st){ max=Math.max(max,stPct(bike,p,st)); });
  return max;
}
// One-time migration: old flat services/alertKm/alertH → serviceTypes array.
function migratePart(p){
  if(p.serviceTypes) return;
  p.serviceTypes=[{id:uid("st-"),name:"Service",services:p.services||[],alertKm:p.alertKm!=null?p.alertKm:null,alertH:p.alertH!=null?p.alertH:null}];
  delete p.services; delete p.alertKm; delete p.alertH;
}
function curBike(){
  for (var i=0;i<MODEL.bikes.length;i++) if (MODEL.bikes[i].id === selBike) return MODEL.bikes[i];
  return null;
}
// Distinct gears seen across rides, with km + count, for the bike form dropdown.
// Collapses aliases by pre-computing name→canonical-key from GEARS: when a Strava
// opaque ID ("b12345") and a HealthSync name-as-ID ("Road Bike") both resolve to
// the same display name, they land in the same bucket. Name-as-id wins as canonical
// key when both styles exist (so the Kross HealthSync scenario stays stable).
function gearOptions(){
  var agg = {};
  var nameKey = {};
  Object.keys(GEARS).forEach(function(gid){
    var nm = (GEARS[gid] && GEARS[gid].name) ? GEARS[gid].name : gid;
    if (!nameKey[nm] || gid === nm) nameKey[nm] = gid;
  });
  RIDES.forEach(function(r){
    var g = r.gear || "";
    if (!g) return;
    var name = (GEARS[g] && GEARS[g].name) ? GEARS[g].name : g;
    var key = nameKey[name] || g;
    if (!agg[key]) agg[key] = { km:0, n:0, name:name };
    agg[key].km += r.km; agg[key].n += 1;
  });
  return Object.keys(agg).map(function(k){
    var e = agg[k];
    return { id:k, label: e.name + " · " + fmtKm(e.km) + " km · " + e.n + " rides" };
  }).sort(function(a,b){ return a.label < b.label ? -1 : 1; });
}

// ---- load / save ----------------------------------------------------------
function loadAll(){
  err("");
  progressStart();
  // Fetch activities and live bike assignments in parallel. activities.json bakes
  // in assignments from the last cron run; the CGI has the current state, so we
  // apply it on top to pick up changes made since the last script execution.
  Promise.all([
    fetch("activities.json", { cache:"no-store" })
      .then(function(r){ if(!r.ok) throw new Error("activities.json HTTP "+r.status); return r.json(); }),
    fetch("/cgi-bin/bike-assign", { cache:"no-store" })
      .then(function(r){ return r.ok ? r.json() : {}; }).catch(function(){ return {}; })
  ])
    .then(function(results){
      var d = results[0], assigns = results[1] || {};
      ACT = d; GEARS = d.gears || {};
      var rides = (d.activities || [])
        .filter(function(a){ return a.sport_type === "Ride" && a.date; });
      var gearDist = {};
      for (var i=0;i<rides.length;i++){
        var g = assigns[String(rides[i].id)] || rides[i].gear_id;
        if(g) gearDist[g]=(gearDist[g]||0)+(rides[i].distance||0);
      }
      DEFGEAR = "";
      var maxDist = 0;
      Object.keys(gearDist).forEach(function(g){ if(gearDist[g]>maxDist){ maxDist=gearDist[g]; DEFGEAR=g; } });
      RIDES = rides
        .map(function(a){
          var gear = assigns[String(a.id)] || a.gear_id || "";
          return { date:a.date, km:(a.distance||0)/1000, time:(a.moving_time||0), elev:(a.total_elevation_gain||0), gear:gear, name:(a.name||"") };
        })
        .sort(function(a,b){ return a.date < b.date ? -1 : 1; });
      return fetch("/cgi-bin/bike-service", { cache:"no-store" });
    })
    .then(function(r){ if(!r.ok) throw new Error("bike-service CGI HTTP "+r.status); return r.json(); })
    .then(function(m){
      MODEL = (m && Array.isArray(m.bikes)) ? m : { version:1, bikes:[] };
      // The CGI accepts any {bikes:[...]} shape; guard against a stored/edited
      // bike that lacks a parts array so render()'s b.parts.filter never throws.
      MODEL.bikes.forEach(function(b){ if (!Array.isArray(b.parts)) b.parts = []; });
      MODEL.bikes.forEach(function(b){ b.parts.forEach(migratePart); });
      // Auto-seed a bike for every Strava gear discovered in activities that isn't
      // already mapped to a bike, so your bikes show up without manual "Add bike".
      // Once seeded the bike (and its parts/service history) is persisted, so it
      // survives even if the gear later drops out of the activity window.
      var mapped = {};
      var mappedNames = {};
      MODEL.bikes.forEach(function(b){ if (b.gearId) mapped[b.gearId] = true; if (b.name) mappedNames[b.name] = true; });
      var seeded = false;
      Object.keys(GEARS)
        .sort(function(a,b){ var na=GEARS[a].name||a, nb=GEARS[b].name||b; return na<nb?-1:1; })
        .forEach(function(gid){
          var bname = GEARS[gid].name || gid;
          // Skip if this gear_id is already assigned, or if a bike with the same
          // name already exists (avoids duplicate tabs after Strava→HealthSync migration).
          if (mapped[gid] || mappedNames[bname]) return;
          MODEL.bikes.push({ id:uid("b-"), name:bname, gearId:gid, baseMileage:0, parts:[] });
          mappedNames[bname] = true;
          seeded = true;
        });
      // No Strava gears discovered yet (detail backfill still pending) and nothing
      // stored — seed the known default bike so the page is useful immediately.
      if (MODEL.bikes.length === 0) {
        MODEL.bikes.push({ id:uid("b-"), name:(_CFG&&_CFG.defaultBikeName)||"My Bike", gearId:"", baseMileage:0, isDefault:true, parts:[] });
        seeded = true;
      }
      // Ensure exactly one bike is marked as the default (absorbs untagged rides).
      // On first open after this update, auto-set the DEFGEAR bike (highest-distance).
      var hasDefault = false;
      MODEL.bikes.forEach(function(b){ if (b.isDefault) hasDefault = true; });
      if (!hasDefault && MODEL.bikes.length) {
        var autoDefault = null;
        if (DEFGEAR) MODEL.bikes.forEach(function(b){ if (!autoDefault && b.gearId === DEFGEAR) autoDefault = b; });
        if (!autoDefault) autoDefault = MODEL.bikes[0];
        autoDefault.isDefault = true;
        seeded = true;
      }
      if (!curBike() && MODEL.bikes.length) {
        // Prefer the bike marked isDefault; fall back to DEFGEAR match, then first.
        var defBike = null;
        MODEL.bikes.forEach(function(b){ if (!defBike && b.isDefault) defBike = b; });
        if (!defBike && DEFGEAR) MODEL.bikes.forEach(function(b){ if (!defBike && b.gearId === DEFGEAR) defBike = b; });
        selBike = defBike ? defBike.id : MODEL.bikes[0].id;
      }
      progressDone();
      render();
      if (seeded) persist();   // store the freshly seeded bikes
    })
    .catch(function(e){
      progressDone();
      err("Failed to load: " + e.message + ". Open this page via the router's web server, and make sure the bike-service CGI is installed (/cgi-bin/bike-service).");
      document.getElementById("meta").textContent = "";
    });
}

// Persist the whole document. Optimistic: we keep the in-memory change and only
// surface an error banner if the write fails (the user can retry the action).
function persist(){
  if (SAVING) return Promise.resolve();
  SAVING = true;
  return fetch("/cgi-bin/bike-service", {
      method:"POST",
      headers:{ "Content-Type":"application/json" },
      body: JSON.stringify(MODEL)
    })
    .then(function(r){ if(!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
    .then(function(saved){ if (saved && Array.isArray(saved.bikes)) MODEL = saved; err(""); })
    .catch(function(e){ err("Save failed: " + e.message + " — your last change is not stored. Try again."); })
    .then(function(){ SAVING = false; render(); });
}

// ---- modal ----------------------------------------------------------------
function openModal(html){
  document.getElementById("modal").innerHTML = html;
  document.getElementById("ovl").style.display = "block";
}
function closeModal(){ document.getElementById("ovl").style.display = "none"; }
window.closeModal = closeModal;

// Recompute the mileage input from the date input for the current bike. Used as
// an onchange on every date picker — changing the date auto-fills the mileage.
function recalc(){
  var b = curBike(); if (!b) return;
  var dt = document.getElementById("f-date");
  var mi = document.getElementById("f-mileage");
  if (dt && mi) mi.value = (Math.round(bikeMileage(b, dt.value)*10)/10);
}
window.recalc = recalc;

// ---- bike CRUD ------------------------------------------------------------
function bikeForm(bike){
  var opts = '<option value="">All rides (no specific gear)</option>';
  gearOptions().forEach(function(g){
    opts += '<option value="'+esc(g.id)+'"'+((bike&&bike.gearId===g.id)?' selected':'')+'>'+esc(g.label)+'</option>';
  });
  openModal(
    '<h3>'+(bike?'Edit bike':'Add bike')+'</h3>'+
    '<label>Name</label><input id="b-name" value="'+esc(bike?bike.name:"")+'" placeholder="e.g. Road bike">'+
    '<label>Strava gear (which rides count toward this bike’s mileage)</label><select id="b-gear">'+opts+'</select>'+
    '<label>Base mileage (km already ridden before Strava tracking)</label>'+
    '<input id="b-base" type="number" step="1" value="'+(bike?(+bike.baseMileage||0):0)+'">'+
    '<div class="chk"><input type="checkbox" id="b-default"'+((bike&&bike.isDefault)?' checked':'')+'>'+
    '<label style="margin:0">Default bike — untagged rides are counted here</label></div>'+
    '<div class="actions"><button class="btn" onclick="closeModal()">Cancel</button>'+
    '<button class="btn primary" onclick="saveBike('+(bike?'\''+bike.id+'\'':'null')+')">Save</button></div>'
  );
}
window.showAddBike = function(){ bikeForm(null); };
window.editBike = function(id){ var b; MODEL.bikes.forEach(function(x){ if(x.id===id) b=x; }); if(b) bikeForm(b); };
window.saveBike = function(id){
  var name = document.getElementById("b-name").value.trim();
  if (!name){ document.getElementById("b-name").focus(); return; }
  var gear = document.getElementById("b-gear").value;
  var base = +document.getElementById("b-base").value || 0;
  var isDefault = document.getElementById("b-default").checked;
  if (isDefault) MODEL.bikes.forEach(function(b){ b.isDefault = false; });
  if (id){
    MODEL.bikes.forEach(function(b){ if(b.id===id){ b.name=name; b.gearId=gear; b.baseMileage=base; b.isDefault=isDefault; } });
  } else {
    var nb = { id:uid("b-"), name:name, gearId:gear, baseMileage:base, isDefault:isDefault, parts:[] };
    MODEL.bikes.push(nb); selBike = nb.id;
  }
  closeModal(); persist();
};
window.deleteBike = function(id){
  var b; MODEL.bikes.forEach(function(x){ if(x.id===id) b=x; });
  if (!b) return;
  if (!confirm('Delete bike "'+b.name+'" and all its parts? This cannot be undone.')) return;
  MODEL.bikes = MODEL.bikes.filter(function(x){ return x.id!==id; });
  if (selBike===id) selBike = MODEL.bikes.length ? MODEL.bikes[0].id : null;
  closeModal(); persist();
};
window.selectBike = function(id){ selBike = id; render(); };

// ---- part: add / edit -----------------------------------------------------
function stBlockHtml(i,stId,name,km,h,desc,timeN,timeUnit){
  return '<input type="hidden" class="st-id" value="'+esc(stId||'')+'">'+
    '<div style="display:flex;align-items:center;gap:.4rem">'+
    '<input class="st-name" style="flex:1;font:inherit;border:1px solid #ccc;border-radius:.4rem;padding:.35rem .5rem;background:#fff;color:#222" placeholder="e.g. Clean &amp; Lube" value="'+esc(name||'')+'">'+
    '<button class="btn sm danger" onclick="removeSvcType('+i+')" title="Remove">✕</button></div>'+
    '<input class="st-desc" style="width:100%;box-sizing:border-box;font:inherit;font-size:.82rem;border:1px solid #ccc;border-radius:.4rem;padding:.28rem .5rem;margin-top:.3rem;background:#fff;color:#222" placeholder="Description / tooltip (optional)" value="'+esc(desc||'')+'">'+
    '<div class="row" style="margin-top:.35rem">'+
    '<div><label>Alert after km (optional)</label><input class="st-km" type="number" step="1" min="0" placeholder="e.g. 500" value="'+(km!=null&&km!==''?km:'')+'"></div>'+
    '<div><label>Alert after hours (optional)</label><input class="st-h" type="number" step="1" min="0" placeholder="e.g. 20" value="'+(h!=null&&h!==''?h:'')+'"></div></div>'+
    '<div style="margin-top:.25rem"><label>Alert after time (optional)</label>'+
    '<div style="display:flex;gap:.4rem;align-items:center">'+
    '<input class="st-timen" type="number" step="1" min="1" placeholder="e.g. 1" style="width:5rem" value="'+(timeN!=null&&+timeN>=1?timeN:'')+'">'+
    '<select class="st-timeunit" style="font:inherit;padding:.35rem .5rem;border:1px solid #ccc;border-radius:.4rem;background:#fff;color:#222">'+
    '<option value="weeks"'+(timeUnit==="weeks"?' selected':'')+'>weeks</option>'+
    '<option value="months"'+((!timeUnit||timeUnit==="months")?' selected':'')+'>months</option>'+
    '<option value="years"'+(timeUnit==="years"?' selected':'')+'>years</option>'+
    '</select></div></div>';
}
window.addSvcType = function(){
  var list=document.getElementById("st-list"); if(!list) return;
  var i=list.children.length;
  var div=document.createElement("div");
  div.className="st-block"; div.id="st-"+i;
  div.innerHTML=stBlockHtml(i,uid("st-"),"",null,null,"",null,"months");
  list.appendChild(div);
};
window.removeSvcType = function(i){
  var list=document.getElementById("st-list"); if(!list) return;
  if(list.querySelectorAll(".st-block").length<=1){ alert("A part must have at least one service type."); return; }
  var el=document.getElementById("st-"+i); if(el) el.remove();
};
function partForm(part){
  var b = curBike(); if (!b) return;
  var date = part ? part.installedDate : todayStr();
  var mi   = part ? part.installedMileage : Math.round(bikeMileage(b, date)*10)/10;
  var types=(part&&part.serviceTypes&&part.serviceTypes.length)?part.serviceTypes:[{id:uid("st-"),name:"Service",alertKm:null,alertH:null}];
  var stHtml=types.map(function(st,i){
    return '<div class="st-block" id="st-'+i+'">'+stBlockHtml(i,st.id,st.name,st.alertKm,st.alertH,st.desc,st.alertTimeN,st.alertTimeUnit)+'</div>';
  }).join("");
  openModal(
    '<h3>'+(part?'Edit part':'Add part')+'</h3>'+
    '<label>Name</label><input id="p-name" value="'+esc(part?part.name:"")+'" placeholder="e.g. Chain, Rear tyre, Brake pads">'+
    '<label>Note (optional)</label><textarea id="p-note" placeholder="free text">'+esc(part?part.note:"")+'</textarea>'+
    '<div class="row"><div><label>Installed date</label>'+
      '<input id="f-date" type="date" value="'+esc(date)+'" onchange="recalc()"></div>'+
    '<div><label>Mileage at install (km)</label>'+
      '<input id="f-mileage" type="number" step="1" value="'+mi+'">'+
      '<div class="hint">auto-filled from the date; editable</div></div></div>'+
    '<label>Purchase cost (optional, '+((_CFG&&_CFG.currency)||'PLN')+')</label>'+
    '<input id="p-cost" type="number" step="0.01" min="0" placeholder="e.g. 25.00" value="'+(part&&part.cost!=null?+part.cost:'')+'">'+
    '<div style="font-size:.82rem;font-weight:600;color:#555;margin:.7rem 0 .2rem">Service types</div>'+
    '<div id="st-list">'+stHtml+'</div>'+
    '<button class="btn sm" onclick="addSvcType()" style="margin:.3rem 0">＋ Add service type</button>'+
    '<div class="chk"><input type="checkbox" id="p-email-alert"'+(part&&part.emailAlert?' checked':'')+'>'+
    '<label style="margin:0">Email alert when service threshold is reached'+
    (_CFG&&_CFG.emailConfigured?'':' <span class="muted" style="font-weight:400;font-size:.8rem">(set STRAVA_MY_BIKE_EMAIL to enable)</span>')+
    '</label></div>'+
    '<div class="actions"><button class="btn" onclick="closeModal()">Cancel</button>'+
    '<button class="btn primary" onclick="savePart('+(part?'\''+part.id+'\'':'null')+')">Save</button></div>'
  );
}
window.showAddPart = function(){ partForm(null); };
window.editPart = function(id){ var p=findPart(id); if(p) partForm(p); };
window.savePart = function(id){
  var b = curBike(); if(!b) return;
  var name = document.getElementById("p-name").value.trim();
  if (!name){ document.getElementById("p-name").focus(); return; }
  var note = document.getElementById("p-note").value;
  var date = document.getElementById("f-date").value || todayStr();
  var mi   = +document.getElementById("f-mileage").value || 0;
  var costEl = document.getElementById("p-cost");
  var cost = costEl && costEl.value !== "" ? +costEl.value : null;
  var existingPart = id ? findPart(id) : null;
  var emailAlertEl = document.getElementById("p-email-alert");
  var emailAlert = emailAlertEl ? emailAlertEl.checked : (existingPart ? (existingPart.emailAlert || false) : false);
  var stBlocks = document.getElementById("st-list").querySelectorAll(".st-block");
  var serviceTypes = [];
  stBlocks.forEach(function(el){
    var stid=(el.querySelector(".st-id")||{value:""}).value||uid("st-");
    var sname=el.querySelector(".st-name").value.trim()||"Service";
    var sdesc=(el.querySelector(".st-desc")||{value:""}).value.trim()||"";
    var skm=el.querySelector(".st-km").value;
    var sh=el.querySelector(".st-h").value;
    var stimen=(el.querySelector(".st-timen")||{value:""}).value;
    var stimeu=(el.querySelector(".st-timeunit")||{value:"months"}).value||"months";
    var existing=null;
    if(existingPart) existingPart.serviceTypes.forEach(function(st){ if(st.id===stid) existing=st; });
    serviceTypes.push({id:stid,name:sname,desc:sdesc||undefined,
      alertKm:skm!==""?(+skm||null):null,
      alertH:sh!==""?(+sh||null):null,
      alertTimeN:stimen!==""&&+stimen>=1?(+stimen):null,
      alertTimeUnit:stimen!==""&&+stimen>=1?stimeu:undefined,
      services:existing?existing.services:[]});
  });
  if(!serviceTypes.length) serviceTypes=[{id:uid("st-"),name:"Service",alertKm:null,alertH:null,services:[]}];
  if (id){
    var p = findPart(id);
    if (p){ p.name=name; p.note=note; p.installedDate=date; p.installedMileage=mi; p.serviceTypes=serviceTypes;
      p.emailAlert=emailAlert;
      if(cost!=null) p.cost=cost; else delete p.cost; }
  } else {
    var np2 = { id:uid("p-"), name:name, note:note, installedDate:date,
      installedMileage:mi, status:"new", needsReplacement:false, emailAlert:emailAlert, serviceTypes:serviceTypes };
    if(cost!=null) np2.cost=cost;
    b.parts.push(np2);
  }
  closeModal(); persist();
};
window.deletePart = function(id){
  var p = findPart(id); if(!p) return;
  if (!confirm('Delete part "'+p.name+'" and its service history?')) return;
  var b = curBike(); b.parts = b.parts.filter(function(x){ return x.id!==id; });
  closeModal(); persist();
};
function findPart(id){
  var b = curBike(); if(!b) return null;
  for (var i=0;i<b.parts.length;i++) if (b.parts[i].id===id) return b.parts[i];
  return null;
}

// ---- part: service --------------------------------------------------------
window.updateSvcDesc = function(sel){
  var opt=sel&&sel.options[sel.selectedIndex];
  var desc=opt?opt.getAttribute('data-desc')||'':'';
  var el=document.getElementById('s-type-desc');
  if(el){ el.textContent=desc; el.style.display=desc?'':'none'; }
};
window.showService = function(id){
  var b = curBike(), p = findPart(id); if(!b||!p) return;
  var date = todayStr();
  var types=p.serviceTypes||[];
  var firstDesc=types.length?types[0].desc||'':'';
  var typeHtml;
  if(types.length>1){
    typeHtml='<label>Service type</label>'+
      '<select id="s-type" onchange="updateSvcDesc(this)">'+
      types.map(function(st){return '<option value="'+esc(st.id)+'" data-desc="'+esc(st.desc||'')+'">'+esc(st.name)+'</option>';}).join('')+
      '</select>'+
      '<div id="s-type-desc" class="hint" style="margin:.15rem 0 .35rem'+(firstDesc?'':';display:none')+'">'+esc(firstDesc)+'</div>';
  } else if(types.length===1){
    typeHtml='<input type="hidden" id="s-type" value="'+esc(types[0].id)+'">'+
      (firstDesc?'<div id="s-type-desc" class="hint" style="margin:.15rem 0 .35rem">'+esc(firstDesc)+'</div>':'');
  } else {
    typeHtml='';
  }
  openModal(
    '<h3>Service: '+esc(p.name)+'</h3>'+
    typeHtml+
    '<div class="row"><div><label>Date</label>'+
      '<input id="f-date" type="date" value="'+esc(date)+'" onchange="recalc()"></div>'+
    '<div><label>Mileage (km)</label>'+
      '<input id="f-mileage" type="number" step="1" value="'+Math.round(bikeMileage(b,date)*10)/10+'">'+
      '<div class="hint">auto-filled from the date</div></div></div>'+
    '<label>Note (optional)</label><textarea id="s-note" placeholder="e.g. cleaned &amp; lubed, checked wear"></textarea>'+
    '<label>Service cost (optional, '+((_CFG&&_CFG.currency)||'PLN')+')</label>'+
    '<input id="s-cost" type="number" step="0.01" min="0" placeholder="e.g. 5.00">'+
    '<div class="chk"><input type="checkbox" id="s-needs-repl"'+(p.needsReplacement?' checked':'')+'>'+
      '<label style="margin:0">Needs replacement</label></div>'+
    '<div class="actions"><button class="btn" onclick="closeModal()">Cancel</button>'+
    '<button class="btn primary" onclick="saveService(\''+id+'\')">Save service</button></div>'
  );
};
window.saveService = function(id){
  var p = findPart(id); if(!p) return;
  var stidEl=document.getElementById("s-type");
  var stid=stidEl?stidEl.value:"";
  var st=null;
  if(p.serviceTypes) p.serviceTypes.forEach(function(x){ if(x.id===stid) st=x; });
  if(!st&&p.serviceTypes&&p.serviceTypes.length) st=p.serviceTypes[0];
  if(!st) return;
  if(!st.services) st.services=[];
  var svcCostEl=document.getElementById("s-cost");
  var svcRec={
    id: uid("s-"),
    date: document.getElementById("f-date").value || todayStr(),
    mileage: +document.getElementById("f-mileage").value || 0,
    note: document.getElementById("s-note").value
  };
  if(svcCostEl&&svcCostEl.value!=="") svcRec.cost=+svcCostEl.value;
  st.services.push(svcRec);
  st.services.sort(function(a,b){ return a.date < b.date ? -1 : 1; });
  p.needsReplacement = document.getElementById("s-needs-repl").checked;
  closeModal(); persist();
};

// ---- part: drag-and-drop reorder ------------------------------------------
var _dragId = null;
window.dragStart = function(e, id, el){
  _dragId = id;
  e.dataTransfer.effectAllowed = "move";
  setTimeout(function(){ el.classList.add("dragging"); }, 0);
};
window.dragEnd = function(el){
  el.classList.remove("dragging");
  document.querySelectorAll("tr.dragover").forEach(function(r){ r.classList.remove("dragover"); });
};
window.dragEnter = function(e, el){ e.preventDefault(); el.classList.add("dragover"); };
window.dragLeave = function(el){ el.classList.remove("dragover"); };
window.dragOver  = function(e){ e.preventDefault(); e.dataTransfer.dropEffect = "move"; };
window.drop = function(e, targetId, el){
  e.preventDefault();
  if (el) el.classList.remove("dragover");
  if (!_dragId || _dragId === targetId) return;
  var b = curBike(); if (!b) return;
  var active = [];
  b.parts.forEach(function(p, i){ if (p.status !== "archived") active.push({p:p, i:i}); });
  var srcPos = -1, tgtPos = -1;
  active.forEach(function(x, j){ if (x.p.id === _dragId) srcPos=j; if (x.p.id === targetId) tgtPos=j; });
  if (srcPos < 0 || tgtPos < 0) return;
  var moved = active.splice(srcPos, 1)[0];
  active.splice(tgtPos, 0, moved);
  var ai = 0;
  b.parts = b.parts.map(function(p){ return p.status !== "archived" ? active[ai++].p : p; });
  _dragId = null;
  persist();
};

// ---- part: replace (archive + optional successor) -------------------------
window.showReplace = function(id){
  var b = curBike(), p = findPart(id); if(!b||!p) return;
  var date = todayStr();
  openModal(
    '<h3>Replace: '+esc(p.name)+'</h3>'+
    '<p class="muted">The old part moves to <b>Archived</b>, recording its final mileage.</p>'+
    '<div class="row"><div><label>Replaced on</label>'+
      '<input id="f-date" type="date" value="'+esc(date)+'" onchange="recalc()"></div>'+
    '<div><label>Mileage (km)</label>'+
      '<input id="f-mileage" type="number" step="1" value="'+Math.round(bikeMileage(b,date)*10)/10+'">'+
      '<div class="hint">auto-filled from the date</div></div></div>'+
    '<label>Reason / note (optional)</label><textarea id="r-note" placeholder="e.g. worn out at 0.75 on the chain checker"></textarea>'+
    '<div class="chk"><input type="checkbox" id="r-new" checked onchange="document.getElementById(\'r-newname\').disabled=!this.checked;document.getElementById(\'r-cost\').disabled=!this.checked">'+
      '<label style="margin:0">Install a replacement now</label></div>'+
    '<label>New part name</label><input id="r-newname" value="'+esc(p.name)+'">'+
    '<label>New part cost (optional, '+((_CFG&&_CFG.currency)||'PLN')+')</label>'+
    '<input id="r-cost" type="number" step="0.01" min="0" placeholder="e.g. 25.00">'+
    '<div class="actions"><button class="btn" onclick="closeModal()">Cancel</button>'+
    '<button class="btn primary" onclick="saveReplace(\''+id+'\')">Replace</button></div>'
  );
};
window.saveReplace = function(id){
  var b = curBike(), p = findPart(id); if(!b||!p) return;
  var date = document.getElementById("f-date").value || todayStr();
  var mi   = +document.getElementById("f-mileage").value || 0;
  var note = document.getElementById("r-note").value;
  p.status = "archived";
  p.archivedDate = date;
  p.archivedMileage = mi;
  p.needsReplacement = false;
  if (note) p.archiveNote = note;
  if (document.getElementById("r-new").checked){
    var nm = document.getElementById("r-newname").value.trim() || p.name;
    var rCostEl = document.getElementById("r-cost");
    var rCost = rCostEl && rCostEl.value !== "" ? +rCostEl.value : null;
    var np = { id:uid("p-"), name:nm, note:"", installedDate:date,
      installedMileage:mi, status:"new", services:[] };
    if(rCost!=null) np.cost=rCost;
    b.parts.push(np);
    p.replacedById = np.id;
  }
  closeModal(); persist();
};

// ---- render ---------------------------------------------------------------
function render(){
  // bike tabs
  var bt = MODEL.bikes.map(function(b){
    return '<button class="tab'+(b.id===selBike?' active':'')+'" onclick="selectBike(\''+b.id+'\')">'+esc(b.name)+'</button>';
  }).join("");
  bt += '<button class="tab add" onclick="showAddBike()">＋ Add bike</button>';
  document.getElementById("bikes").innerHTML = bt;

  var gen = (ACT && ACT.generatedAt) ? (" · rides as of " + esc(ACT.generatedAt.slice(0,10))) : "";
  document.getElementById("meta").innerHTML =
    RIDES.length + " outdoor rides found in activities.json" + gen +
    (MODEL.updatedAt ? " · saved " + esc(String(MODEL.updatedAt).slice(0,10)) : "");

  var b = curBike();
  var panel = document.getElementById("bikepanel");
  if (!b){
    panel.innerHTML = '<div class="panel empty">No bikes yet. Click <b>＋ Add bike</b> to start tracking parts and service.</div>';
    return;
  }

  var now = todayStr();
  var tot = bikeTotals(b, now);
  var gearName = b.gearId ? ((GEARS[b.gearId] && GEARS[b.gearId].name) ? GEARS[b.gearId].name : b.gearId) : "all rides";
  if (b.gearId && b.isDefault) gearName += " + untagged rides";
  var span = fmtSpan(tot.first, tot.last);
  var subStats = tot.time > 0
    ? fmtTime(tot.time) + ' · ' + fmtInt(tot.elev) + ' m elev' + (span ? ' · ' + span : '')
    : (span ? span : '');

  var html = '<div class="panel">'+
    '<div class="odo"><div><div class="k">Current mileage</div><div class="big">'+fmtKm(tot.km)+' km</div>'+
      (subStats?'<div class="odo-sub">'+esc(subStats)+'</div>':'')+
    '</div>'+
    '<div><div class="k">Mileage source</div><div>'+esc(gearName)+(b.baseMileage?(' + '+fmtKm(b.baseMileage)+' km base'):'')+'</div></div></div>'+
    '<div><button class="btn primary" onclick="showAddPart()">＋ Add part</button> '+
    '<button class="btn sm" onclick="editBike(\''+b.id+'\')">Edit bike</button> '+
    '<button class="btn sm danger" onclick="deleteBike(\''+b.id+'\')">Delete bike</button></div></div>';

  // cost summary block
  var totalCost = bikeTotalCost(b);
  if(totalCost>0){
    var partsCost   = bikePartsCostOnly(b);
    var serviceCost = bikeServiceCostOnly(b);
    var costByYr = bikeCostByYear(b);
    var yrKeys = Object.keys(costByYr).sort(function(a,c){return c<a?-1:1;});
    var yrRows = yrKeys.map(function(yr){
      return '<tr><td>'+esc(yr)+'</td><td>'+fmtCost(costByYr[yr])+'</td></tr>';
    }).join('');
    var splitHtml = (partsCost>0&&serviceCost>0)
      ?'<div style="font-size:.8rem;color:#888;margin-top:.15rem">'+
         fmtCost(partsCost)+' parts · '+fmtCost(serviceCost)+' service</div>'
      :'';
    html += '<div class="cost-block">'+
      '<div style="font-size:.72rem;text-transform:uppercase;letter-spacing:.04em;color:#888;margin-bottom:.15rem">Total cost</div>'+
      '<div class="cost-total">'+fmtCost(totalCost)+'</div>'+
      splitHtml+
      (yrKeys.length>1
        ?'<details class="cost-yr"><summary>By year</summary>'+
          '<table class="cost-yr-tbl"><tbody>'+yrRows+'</tbody></table></details>'
        :(yrKeys.length===1
          ?'<div style="font-size:.83rem;color:#888;margin-top:.1rem">'+esc(yrKeys[0])+'</div>'
          :''))+
    '</div>';
  }

  var active   = b.parts.filter(function(p){ return p.status !== "archived"; });
  // Parts with an alert threshold: sort by % used descending (soonest service due first).
  // Parts without any threshold: sort by install date descending (newest install first).
  // The two groups are kept separate — alerted parts always precede unalerted ones.
  active = active.slice().sort(function(x,y){
    var rx=!!x.needsReplacement, ry=!!y.needsReplacement;
    if(rx!==ry) return rx?-1:1;
    var ha=(x.serviceTypes||[]).some(function(st){return (st.alertKm&&+st.alertKm>0)||(st.alertH&&+st.alertH>0);});
    var hb=(y.serviceTypes||[]).some(function(st){return (st.alertKm&&+st.alertKm>0)||(st.alertH&&+st.alertH>0);});
    if(ha!==hb) return ha?-1:1;
    if(ha){ var pa=partPct(b,x),pb=partPct(b,y); return pb-pa; }
    var da=x.installedDate||"",db=y.installedDate||"";
    return da<db?1:da>db?-1:0;
  });
  var archived = b.parts.filter(function(p){ return p.status === "archived"; });

  // active parts
  html += '<h2>Parts in use</h2>';
  if (!active.length){
    html += '<div class="panel empty">No active parts. Add a chain, tyres, brake pads… each tracks the km ridden since you fitted it.</div>';
  } else {
    html += '<table><thead><tr><th>Part</th><th>Installed</th><th>Ridden since install</th><th>Last service</th><th>Since service</th><th>Cost</th><th></th></tr></thead><tbody>';
    active.forEach(function(p){
      var ridden = Math.max(0, bikeMileage(b) - (+p.installedMileage || 0));
      var riddenSec = rideTimeSince(b, p.installedDate);
      var noteLine = p.note ? '<div class="muted">'+esc(p.note)+'</div>' : '';
      var replBadge = p.needsReplacement ? '<span class="needs-repl">Needs replacement</span>' : '';
      var types = p.serviceTypes || [];
      var multiType = types.length > 1;
      var isWarn = Boolean(p.needsReplacement);
      var lastCell = "", sinceCell = "";
      types.forEach(function(st){
        var svc=(st.services||[]).slice().sort(function(a,c){return a.date<c.date?-1:1;});
        var last=svc.length?svc[svc.length-1]:null;
        var fromDate=last?last.date:(p.installedDate||"");
        var sinceMileage=last?(+last.mileage||0):(+p.installedMileage||0);
        var sinceKm=Math.max(0,bikeMileage(b)-sinceMileage);
        var sinceH=Math.max(0,rideTimeSince(b,fromDate)/3600);
        var sinceDays=calendarDaysSince(fromDate);
        var adv=alertTimeDays(st);
        var pctKm=(st.alertKm&&+st.alertKm>0)?(sinceKm/+st.alertKm*100):0;
        var pctH=(st.alertH&&+st.alertH>0)?(sinceH/+st.alertH*100):0;
        var pctDays=(adv>0)?(sinceDays/adv*100):0;
        var pct=Math.max(pctKm,pctH,pctDays);
        var hasThresh=(st.alertKm&&+st.alertKm>0)||(st.alertH&&+st.alertH>0)||(adv>0);
        if(pct>=100) isWarn=true;
        var barCls=pct>=100?'due':pct>=80?'warn':'good';
        var label=(multiType||st.desc)?'<div class="svc-type-label"'+(st.desc?' title="'+esc(st.desc)+'"':'')+'>'+esc(st.name)+'</div>':'';
        lastCell+='<div class="svc-type-row">'+label+servicesBlock(svc)+'</div>';
        var tipParts=[];
        if(st.alertKm&&+st.alertKm>0) tipParts.push(fmtKm(sinceKm)+' km / '+st.alertKm+' km');
        if(st.alertH&&+st.alertH>0) tipParts.push(sinceH.toFixed(1)+' h / '+st.alertH+' h');
        if(adv>0) tipParts.push(sinceDays+' d / '+adv+' d');
        var barTip=(last?'Since last service: ':'Since install: ')+tipParts.join('; ');
        var bar=hasThresh
          ?'<div class="svc-bar" title="'+esc(barTip)+'"><div class="svc-bar-fill '+barCls+'" style="width:'+Math.min(100,pct).toFixed(1)+'%"></div></div>'+
           '<span class="svc-pct" title="'+esc(barTip)+'">'+Math.round(pct)+'%</span>'
          :'';
        sinceCell+='<div class="svc-type-row">'+label+
          (last?'<b>'+fmtKm(sinceKm)+'</b> km<div class="muted">'+sinceH.toFixed(1)+' h'+(adv>0?' · '+sinceDays+' d':'')+'</div>'
               :(adv>0?'<span class="muted">'+sinceDays+' d</span>':'<span class="muted">—</span>'))+
          bar+'</div>';
      });
      if(!types.length){lastCell='<span class="muted">never</span>';sinceCell='<span class="muted">—</span>';}
      var dnd = ' draggable="true"'+
        ' ondragstart="dragStart(event,\''+p.id+'\',this)"'+
        ' ondragend="dragEnd(this)"'+
        ' ondragenter="dragEnter(event,this)"'+
        ' ondragleave="dragLeave(this)"'+
        ' ondragover="dragOver(event)"'+
        ' ondrop="drop(event,\''+p.id+'\',this)"';
      var pCostTotal = partTotalCost(p);
      var costCell = pCostTotal>0
        ? '<span style="font-variant-numeric:tabular-nums">'+fmtCost(pCostTotal)+'</span>'+
          (p.cost&&+p.cost>0?'<div class="muted" style="font-size:.78rem">part: '+fmtCost(p.cost)+'</div>':'')
        : '<span class="muted">—</span>';
      html += '<tr'+dnd+(isWarn?' class="warn"':'')+'><td><b>'+esc(p.name)+'</b>'+replBadge+noteLine+'</td>'+
        '<td style="white-space:nowrap">'+esc(p.installedDate||"?")+'<div class="muted">@ '+fmtKm(p.installedMileage)+' km</div></td>'+
        '<td class="num"><b>'+fmtKm(ridden<0?0:ridden)+'</b> km<div class="muted">'+(riddenSec/3600).toFixed(1)+' h</div></td>'+
        '<td>'+lastCell+'</td>'+
        '<td>'+sinceCell+'</td>'+
        '<td class="num">'+costCell+'</td>'+
        '<td style="white-space:nowrap">'+
          '<button class="btn sm" onclick="showService(\''+p.id+'\')">Service</button> '+
          '<button class="btn sm" onclick="showReplace(\''+p.id+'\')">Replace</button> '+
          '<button class="btn sm" onclick="editPart(\''+p.id+'\')">Edit</button> '+
          '<button class="btn sm danger" onclick="deletePart(\''+p.id+'\')">✕</button>'+
        '</td></tr>';
      html += '<tr class="ridesrow'+(isWarn?' warn':'')+'"'+
        ' ondragover="dragOver(event)" ondrop="drop(event,\''+p.id+'\',this)">'+
        '<td colspan="7">'+ridesBlock(partRides(b, p))+'</td></tr>';
    });
    html += '</tbody></table>';
  }

  // archived parts
  if (archived.length){
    html += '<h2>Archived (replaced)</h2>';
    html += '<table><thead><tr><th>Part</th><th>Lifespan</th><th>Distance on part</th><th>Services</th><th>Cost</th></tr></thead><tbody>';
    archived.sort(function(a,c){ return (c.archivedDate||"") < (a.archivedDate||"") ? -1 : 1; });
    archived.forEach(function(p){
      var life = (+p.archivedMileage||0) - (+p.installedMileage||0);
      var allSvc=[];
      (p.serviceTypes||[]).forEach(function(st){ allSvc=allSvc.concat(st.services||[]); });
      allSvc.sort(function(a,c){return a.date<c.date?-1:1;});
      var svcTxt = allSvc.length
        ? allSvc.map(function(s){ return esc(s.date)+' ('+fmtKm(s.mileage)+' km'+(s.note?': '+esc(s.note):'')+')'; }).join('<br>')
        : '<span class="muted">none</span>';
      var noteLine = p.note ? '<div class="muted">'+esc(p.note)+'</div>' : '';
      var arcNote = p.archiveNote ? '<div class="muted">'+esc(p.archiveNote)+'</div>' : '';
      var dur = fmtDuration(p.installedDate, p.archivedDate);
      var aCostTotal = partTotalCost(p);
      var aCostCell = aCostTotal>0 ? fmtCost(aCostTotal) : '<span class="muted">—</span>';
      html += '<tr class="archived"><td><b>'+esc(p.name)+'</b>'+noteLine+'</td>'+
        '<td>'+esc(p.installedDate||"?")+' → '+esc(p.archivedDate||"?")+(dur?'<div class="muted">'+esc(dur)+'</div>':'')+arcNote+'</td>'+
        '<td class="num"><b>'+fmtKm(life<0?0:life)+'</b> km<div class="muted">'+fmtKm(p.installedMileage)+' → '+fmtKm(p.archivedMileage)+'</div></td>'+
        '<td class="svc">'+svcTxt+'</td>'+
        '<td class="num">'+aCostCell+'</td></tr>';
      html += '<tr class="ridesrow archived"><td colspan="5">'+ridesBlock(partRides(b, p))+'</td></tr>';
    });
    html += '</tbody></table>';
  }

  panel.innerHTML = html;
}

document.getElementById("ovl").addEventListener("click", function(e){ if (e.target === this) closeModal(); });
loadAll();
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

log "wrote $WEB_DIR/bike.html"

# --- 6c. Install the bike-service CGI (read/write JSON store) ---------------
# uhttpd executes files under its cgi_prefix (default /cgi-bin). This tiny CGI is
# the only writer of $BIKE_DATA: GET returns the stored document, POST validates
# the body as JSON, stamps updatedAt, and writes it atomically. The one runtime
# value (the data-file path) is injected here; the body below is a quoted heredoc
# so nothing else is shell-expanded. Trust model matches the rest of these pages:
# no auth — intended for a private LAN router only.
mkdir -p "$CGI_DIR"
BIKE_DATA_DIR="$(dirname "$BIKE_DATA")"
mkdir -p "$BIKE_DATA_DIR"

{
  printf '%s\n' '#!/bin/sh'
  printf 'DATA_FILE=%s\n' "\"$BIKE_DATA\""
} > "$CGI_DIR/bike-service"

cat >> "$CGI_DIR/bike-service" <<'CGI'
# StravaStats for OpenWrt — bike-service data CGI (generated by strava-my-activities).
# GET  -> the stored bike-service document (or an empty one).
# POST -> validate JSON body, stamp updatedAt, write atomically, echo it back.
set -eu

emit_json() { printf 'Content-Type: application/json\r\n\r\n'; }
fail() { # <status line> <message>
  printf 'Status: %s\r\nContent-Type: application/json\r\n\r\n' "$1"
  printf '{"error":"%s"}\n' "$2"
  exit 0
}

DATA_DIR="$(dirname "$DATA_FILE")"
mkdir -p "$DATA_DIR" 2>/dev/null || true

method="${REQUEST_METHOD:-GET}"

if [ "$method" = "GET" ]; then
  emit_json
  if [ -f "$DATA_FILE" ]; then
    cat "$DATA_FILE"
  else
    printf '{"version":1,"bikes":[]}\n'
  fi
  exit 0
fi

if [ "$method" = "POST" ]; then
  len="${CONTENT_LENGTH:-0}"
  case "$len" in ''|*[!0-9]*) fail '411 Length Required' 'missing or invalid Content-Length' ;; esac
  [ "$len" -gt 0 ]       || fail '400 Bad Request' 'empty body'
  [ "$len" -le 1048576 ] || fail '413 Payload Too Large' 'body exceeds 1 MB'

  tmpbody="$DATA_FILE.body.$$"
  cat > "$tmpbody"
  [ -s "$tmpbody" ] \
    || { rm -f "$tmpbody"; fail '400 Bad Request' 'empty body'; }
  # Validate it parses as JSON and looks like our document (has a bikes array).
  jq -e 'type=="object" and (.bikes|type=="array")' "$tmpbody" >/dev/null 2>&1 \
    || { rm -f "$tmpbody"; fail '400 Bad Request' 'body is not a valid bike-service document'; }

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

chmod 0755 "$CGI_DIR/bike-service"
log "installed bike-service CGI -> $CGI_DIR/bike-service (data: $BIKE_DATA)"

# --- 6d. Install the bike-assign CGI (per-activity bike override) ------------
# Simple GET/POST CGI for the flat {actId: bikeName} JSON assignments file.
# Shared between strava-my-activities and healthsync-activities; idempotent.
[ -f "$BIKE_ASSIGN" ] || printf '{}' > "$BIKE_ASSIGN"
{
  printf '%s\n' '#!/bin/sh'
  printf 'DATA_FILE=%s\n' "\"$BIKE_ASSIGN\""
} > "$CGI_DIR/bike-assign"

cat >> "$CGI_DIR/bike-assign" <<'CGI'
set -eu
emit_json() { printf 'Content-Type: application/json\r\n\r\n'; }
fail() {
    printf 'Status: %s\r\nContent-Type: application/json\r\n\r\n{"error":"%s"}\n' "$1" "$2"
    exit 0
}
method="${REQUEST_METHOD:-GET}"
if [ "$method" = "GET" ]; then
    emit_json
    if [ -f "$DATA_FILE" ]; then cat "$DATA_FILE"; else printf '{}'; fi
    exit 0
fi
if [ "$method" = "POST" ]; then
    len="${CONTENT_LENGTH:-0}"
    case "$len" in ''|*[!0-9]*) fail '411 Length Required' 'bad Content-Length' ;; esac
    [ "$len" -le 524288 ] || fail '413 Payload Too Large' 'body exceeds 512 KB'
    tmpbody="${DATA_FILE}.body.$$"
    cat > "$tmpbody"
    [ -s "$tmpbody" ] \
        || { rm -f "$tmpbody"; fail '400 Bad Request' 'empty body'; }
    jq -e 'type == "object"' "$tmpbody" >/dev/null 2>&1 \
        || { rm -f "$tmpbody"; fail '400 Bad Request' 'body must be a JSON object'; }
    tmp="${DATA_FILE}.tmp.$$"
    if jq '.' "$tmpbody" > "$tmp" 2>/dev/null; then
        rm -f "$tmpbody"
        mv "$tmp" "$DATA_FILE"
    else
        rm -f "$tmp" "$tmpbody"
        fail '500 Internal Server Error' 'write failed'
    fi
    emit_json
    cat "$DATA_FILE"
    exit 0
fi
fail '405 Method Not Allowed' 'use GET or POST'
CGI

chmod 0755 "$CGI_DIR/bike-assign"
log "installed bike-assign CGI -> $CGI_DIR/bike-assign"
