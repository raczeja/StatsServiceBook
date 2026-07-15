# strava-my-html-detail.sh — sourced by strava-my-activities.sh.
# Writes $WEB_DIR/activity.html (the per-activity detail page).
# A single page reused for every activity: reads ?id=<n> from the URL, fetches
# details/<id>.json, and renders cards, a Leaflet/OSM map, and per-km splits.
# Quoted heredoc: nothing shell-expanded.

# --- 6a. Render the per-activity detail page -------------------------------
cat > "$WEB_DIR/activity.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Activity detail</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN0YXRzU2VydmljZUJvb2siPgogIDxkZWZzPgogICAgPGNsaXBQYXRoIGlkPSJjbGlwIj4KICAgICAgPGNpcmNsZSBjeD0iMzIiIGN5PSIzMiIgcj0iMzAiLz4KICAgIDwvY2xpcFBhdGg+CiAgICA8bGluZWFyR3JhZGllbnQgaWQ9ImJnIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMyYTJhMmEiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMTExMTExIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KCiAgPCEtLSBCYWNrZ3JvdW5kIGNpcmNsZSAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMiIgZmlsbD0idXJsKCNiZykiLz4KCiAgPGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXApIj4KCiAgICA8IS0tIEFyZWEgZmlsbCB1bmRlciB0aGUgcm91dGUgbGluZSAtLT4KICAgIDxwb2x5Z29uCiAgICAgIHBvaW50cz0iNCw0NiAxMyw0NiAxOSwzMiAyNSw0MCAzMiwxOCAzOSwzMiA0NSwyNSA1MSwzMiA2MCwzMiA2MCw1NiA0LDU2IgogICAgICBmaWxsPSIjZmM0YzAyIiBmaWxsLW9wYWNpdHk9IjAuMTUiLz4KCiAgICA8IS0tIFJvdXRlIC8gZWxldmF0aW9uIHByb2ZpbGUg4oCUIHRoZSBjb3JlIGZlYXR1cmUgLS0+CiAgICA8cG9seWxpbmUKICAgICAgcG9pbnRzPSI0LDQ2IDEzLDQ2IDE5LDMyIDI1LDQwIDMyLDE4IDM5LDMyIDQ1LDI1IDUxLDMyIDYwLDMyIgogICAgICBmaWxsPSJub25lIgogICAgICBzdHJva2U9IiNmYzRjMDIiCiAgICAgIHN0cm9rZS13aWR0aD0iMy4yIgogICAgICBzdHJva2UtbGluZWNhcD0icm91bmQiCiAgICAgIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KCiAgICA8IS0tIEdQUyAvIHN0YXJ0IGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjQiIGN5PSI0NiIgcj0iMi41IiBmaWxsPSIjZmM0YzAyIi8+CgogICAgPCEtLSBGaW5pc2ggLyBjdXJyZW50LXBvc2l0aW9uIGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjYwIiBjeT0iMzIiIHI9IjIuNSIgZmlsbD0iI2ZjNGMwMiIvPgoKICA8L2c+CgogIDwhLS0gV2lGaSBzaWduYWwgYXJjcyDigJQgdG9wLXJpZ2h0LCByZXByZXNlbnRzIHRoZSByb3V0ZXIgLS0+CiAgPHBhdGggZD0iTTQzLDEzIFE1MCw3ICA1NywxMyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjQ1Ii8+CiAgPHBhdGggZD0iTTQ2LDE3IFE1MCwxMyA1NCwxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjc1Ii8+CiAgPGNpcmNsZSBjeD0iNTAiIGN5PSIyMSIgcj0iMi4yIiBmaWxsPSIjZmM0YzAyIi8+CgogIDwhLS0gT3V0ZXIgcmluZyAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLW9wYWNpdHk9IjAuMzUiLz4KPC9zdmc+Cg==" type="image/svg+xml">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
<style>
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1000px;padding:0 1rem;background:#fafafa;color:#222}
  h1{margin:0 0 .25rem;font-size:1.5rem}
  a{color:#fc4c02}
  .crumbs{font-size:.85rem;margin:0 0 .75rem}
  .sub{color:#666;font-size:.9rem;margin:.1rem 0 .5rem}
  .desc{white-space:pre-wrap;background:#fff;border:1px solid #eee;padding:.5rem .75rem;border-radius:.4rem;margin:.5rem 0;font-size:.9rem;color:#444}
  .links{font-size:.85rem;margin:.25rem 0 1rem}
  .links a{margin-right:1rem}
  .cards{display:flex;flex-wrap:wrap;gap:.6rem;margin:.5rem 0 1rem}
  .card{flex:1;min-width:120px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:.5rem .75rem;border-radius:.4rem}
  .card .k{color:#888;font-size:.72rem;text-transform:uppercase;letter-spacing:.03em}
  .card .v{font-size:1.15rem;font-weight:600;font-variant-numeric:tabular-nums;margin-top:.15rem}
  #map{height:340px;border-radius:.4rem;box-shadow:0 1px 3px rgba(0,0,0,.08);margin:.5rem 0 1rem;background:#e8e8e8}
  .box{background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:.5rem .75rem;border-radius:.4rem;margin:.5rem 0 1rem}
  .box h3{margin:0 0 .35rem;font-size:.85rem;color:#444;font-weight:600}
  svg.splits{height:200px;display:block}
  .chart-scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
  .note{color:#666;font-size:.85rem;padding:.25rem 0}
  #err{color:#b00;padding:1rem 0}
  #chart-tip{display:none;position:fixed;background:rgba(30,30,30,.93);color:#fff;padding:.45rem .7rem;border-radius:.4rem;font-size:.8rem;pointer-events:none;z-index:1000;line-height:1.7;box-shadow:0 2px 8px rgba(0,0,0,.3)}
  #chart-tip strong{display:block;margin-bottom:.15rem;font-size:.85rem}
  #pbar{position:fixed;top:0;left:0;width:0;height:3px;background:#fc4c02;z-index:9999;pointer-events:none}
  #map-box{position:relative}
  #map-spin{position:absolute;left:0;top:.5rem;right:0;bottom:1rem;display:flex;flex-direction:column;
    align-items:center;justify-content:center;background:#e8e8e8;border-radius:.4rem;
    color:#666;font-size:.9rem;gap:.5rem;z-index:500;pointer-events:none}
  #map-spin-bar{width:120px;height:3px;background:#ccc;border-radius:2px;overflow:hidden}
  #map-spin-bar::after{content:'';display:block;height:100%;width:40%;background:#fc4c02;
    animation:map-shimmer 1.2s ease-in-out infinite}
  @keyframes map-shimmer{0%{transform:translateX(-150%)}100%{transform:translateX(400%)}}
  #map-expand-btn{position:absolute;top:.4rem;right:.4rem;z-index:600;background:rgba(255,255,255,.9);border:1px solid #ccc;border-radius:.3rem;padding:.2rem .5rem;font-size:.78rem;cursor:pointer;line-height:1.5;box-shadow:0 1px 3px rgba(0,0,0,.15)}
  #map-expand-btn:hover{background:#fff;border-color:#999}
  #map-box.fs-map{position:fixed;inset:0;z-index:9000;margin:0;padding:0;background:#000;border-radius:0}
  #map-box.fs-map #map{height:100%;border-radius:0;margin:0;box-shadow:none}
  #map-box.fs-map #map-expand-btn{top:.6rem;right:.6rem}
  .hr-zone-table{width:100%;border-collapse:collapse;font-size:.85rem}
  .hr-zone-table td{padding:.25rem .4rem;vertical-align:middle}
  .hr-zone-table tr:nth-child(odd){background:#f7f7f7}
  .hr-zone-bar{display:inline-block;height:8px;border-radius:3px;vertical-align:middle}
</style>
</head>
<body>
<div id="pbar"></div>
<div id="chart-tip"></div>
<div class="crumbs"><a href="index.html">&larr; All activities</a> &middot; <a id="leaderboard-link" href="../" style="display:none">🏆 Club leaderboard</a></div>
<div id="err"></div>
<div id="content" style="display:none">
  <div style="display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="36" height="36" aria-hidden="true"><defs><clipPath id="clip"><circle cx="32" cy="32" r="30"/></clipPath><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs><circle cx="32" cy="32" r="32" fill="url(#bg)"/><g clip-path="url(#clip)"><polygon points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32 60,56 4,56" fill="#fc4c02" fill-opacity="0.15"/><polyline points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32" fill="none" stroke="#fc4c02" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="46" r="2.5" fill="#fc4c02"/><circle cx="60" cy="32" r="2.5" fill="#fc4c02"/></g><path d="M43,13 Q50,7 57,13" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.45"/><path d="M46,17 Q50,13 54,17" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/><circle cx="50" cy="21" r="2.2" fill="#fc4c02"/><circle cx="32" cy="32" r="31" fill="none" stroke="#fc4c02" stroke-width="0.8" stroke-opacity="0.35"/></svg><h1 id="name" style="margin:0"></h1></div>
  <div class="sub" id="sub"></div>
  <div class="desc" id="desc" style="display:none"></div>
  <div class="links" id="links"></div>
  <div id="bike-row" style="display:none;margin:.25rem 0 .75rem;font-size:.9rem"></div>
  <div class="cards" id="cards"></div>
  <div id="map-box">
    <div id="map"></div>
    <div id="map-spin">Loading map…<div id="map-spin-bar"></div></div>
    <button id="map-expand-btn" onclick="toggleMapFullscreen()" title="Expand map">&#x26F6; Expand</button>
  </div>
  <div class="box" id="elev-box" style="display:none">
    <h3>Elevation profile</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-elev-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-elev" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="box" id="hr-box" style="display:none">
    <h3>Heart rate</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-hr-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-hr" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="box" id="cad-box" style="display:none">
    <h3>Cadence</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-cad-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-cad" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="box" id="hr-zone-box" style="display:none">
    <h3 id="hr-zone-title">Heart rate zones</h3>
    <div id="hr-zone-content"></div>
  </div>
  <div class="box" id="splits-box">
    <h3 id="splits-title">Splits</h3>
    <div class="chart-scroll"><svg class="splits" id="svg-splits" preserveAspectRatio="xMidYMid meet"></svg></div>
  </div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
"use strict";
fetch('../',{method:'HEAD'}).then(function(r){if(r.ok){var el=document.getElementById('leaderboard-link');if(el)el.style.display='';}}).catch(function(){});
var _pbar=null,_pbarTick=null,_pbarPct=0;
var leafletMap=null,leafletLine=null;
function toggleMapFullscreen(){
  var box=document.getElementById("map-box");
  var btn=document.getElementById("map-expand-btn");
  var fs=box.classList.toggle("fs-map");
  btn.innerHTML=fs?"&#x2715; Close":"&#x26F6; Expand";
  if(leafletMap){
    setTimeout(function(){
      leafletMap.invalidateSize();
      if(leafletLine) leafletMap.fitBounds(leafletLine.getBounds(),{padding:[20,20]});
    },50);
  }
}
document.addEventListener("keydown",function(e){
  if(e.key==="Escape"){var box=document.getElementById("map-box");if(box.classList.contains("fs-map"))toggleMapFullscreen();}
});
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
function hideMapSpin(){
  var s=document.getElementById("map-spin");
  if(s) s.style.display="none";
}

function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g, function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }
function fmtKm(m){ return (m/1000).toFixed(2); }
function fmtTime(s){
  s = Math.round(s);
  var h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
  if (h > 0) return h + "h " + (m<10?"0":"") + m + "m";
  return m + "m " + (sec<10?"0":"") + sec + "s";
}
// Pace from speed (m/s) -> "m:ss /km".
function fmtPace(mps){
  if (!mps || mps <= 0) return "—";
  var sec = 1000 / mps, m = Math.floor(sec/60), s = Math.round(sec%60);
  if (s === 60) { m += 1; s = 0; }
  return m + ":" + (s<10?"0":"") + s + " /km";
}

// Foot sports get pace (min/km); everything else gets speed (km/h).
var FOOT = { Run:1, TrailRun:1, Walk:1, Hike:1, VirtualRun:1 };
function isFoot(sport){ return !!FOOT[sport]; }

// --- Tooltip (shared with splits chart and line charts) --------------------
var TIP_DATA = [], tipEl = null;
var LINE_TIPS = {};   // svgId -> [{x, html}] — populated by drawLineSvg
var ATHLETE_AGE = 0;  // set from activities.json metadata; 0 = not configured
function lineChartHover(e, svgId) {
  var data = LINE_TIPS[svgId];
  if (!data || !data.length) return;
  var svg = document.getElementById(svgId);
  var rect = svg.getBoundingClientRect();
  var vb = svg.viewBox.baseVal;
  if (!rect.width || !vb) return;
  var mx = (e.clientX - rect.left) * vb.width / rect.width;
  var best = 0, bestDist = Infinity, i, d;
  for (i = 0; i < data.length; i++) {
    d = Math.abs(data[i].x - mx);
    if (d < bestDist) { bestDist = d; best = i; }
  }
  if (!tipEl) tipEl = document.getElementById("chart-tip");
  tipEl.innerHTML = data[best].html;
  tipEl.style.display = "block";
  moveTip(e);
}
function showTip(e, idx){
  if (!tipEl) tipEl = document.getElementById("chart-tip");
  if (!TIP_DATA[idx]) return;
  tipEl.innerHTML = TIP_DATA[idx];
  tipEl.style.display = "block";
  moveTip(e);
}
function moveTip(e){
  if (!tipEl) return;
  tipEl.style.left = (e.clientX + 16) + "px";
  tipEl.style.top  = (e.clientY - 10) + "px";
}
function hideTip(){
  if (!tipEl) tipEl = document.getElementById("chart-tip");
  tipEl.style.display = "none";
}

// --- Google encoded-polyline decoder ---------------------------------------
// Returns an array of [lat, lng] pairs. Standard precision-5 algorithm.
function decodePolyline(str){
  var pts = [], i = 0, lat = 0, lng = 0;
  while (i < str.length) {
    var shift = 0, result = 0, b;
    do { b = str.charCodeAt(i++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    lat += (result & 1) ? ~(result >> 1) : (result >> 1);
    shift = 0; result = 0;
    do { b = str.charCodeAt(i++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    lng += (result & 1) ? ~(result >> 1) : (result >> 1);
    pts.push([lat / 1e5, lng / 1e5]);
  }
  return pts;
}

function getId(){
  var m = /[?&]id=([^&]*)/.exec(location.search);
  if (!m) return "";
  return decodeURIComponent(m[1]).replace(/[^a-zA-Z0-9-]/g, "");
}

function card(k, v){ return '<div class="card"><div class="k">'+esc(k)+'</div><div class="v">'+v+'</div></div>'; }
// Same card, with a hover explanation (native tooltip) for cryptic metrics.
function cardTip(k, v, tip){ return '<div class="card" title="'+esc(tip)+'"><div class="k">'+esc(k)+'</div><div class="v">'+v+'</div></div>'; }

function renderCards(d){
  var sport = d.sport_type || d.type || "";
  var html = "";
  html += card("Distance", fmtKm(d.distance || 0) + " km");
  html += card("Moving time", fmtTime(d.moving_time || 0));
  if (d.elapsed_time && d.elapsed_time !== d.moving_time)
    html += card("Elapsed", fmtTime(d.elapsed_time));
  // Stopped time (café / traffic stops) — elapsed minus moving, when meaningful.
  var stopped = (d.elapsed_time || 0) - (d.moving_time || 0);
  if (stopped >= 60) {
    var movePct = d.elapsed_time > 0 ? Math.round(100 * d.moving_time / d.elapsed_time) : null;
    html += card("Stopped", fmtTime(stopped) +
      (movePct != null ? ' <span style="color:#888;font-size:.8rem">' + movePct + '% moving</span>' : ''));
  }
  if (d.average_speed) {
    html += isFoot(sport)
      ? card("Avg pace", fmtPace(d.average_speed))
      : card("Avg speed", (d.average_speed*3.6).toFixed(1) + " km/h");
  }
  if (d.max_speed) {
    html += isFoot(sport)
      ? card("Best pace", fmtPace(d.max_speed))
      : card("Max speed", (d.max_speed*3.6).toFixed(1) + " km/h");
  }
  if (d.total_elevation_gain) html += card("Elevation", Math.round(d.total_elevation_gain) + " m");
  // VAM (vertical ascent m/h) and climb intensity (m/km) — key cycling climb metrics.
  if (d.total_elevation_gain > 0 && d.moving_time > 0)
    html += cardTip("Climb rate", Math.round(d.total_elevation_gain * 3600 / d.moving_time) + " m/h",
      "VAM — average climbing speed in vertical metres per hour (elevation gain ÷ moving time). Higher means you climbed faster.");
  if (d.total_elevation_gain > 0 && d.distance > 0)
    html += card("Climb/km", (d.total_elevation_gain / (d.distance / 1000)).toFixed(1) + " m/km");
  if (d.average_heartrate) {
    var hrTip = ATHLETE_AGE > 0
      ? "HRmax = 220 − " + ATHLETE_AGE + " = " + (220 - ATHLETE_AGE) + " bpm · used for zone thresholds"
      : "Zone thresholds use " + (d.max_heartrate ? d.max_heartrate + " bpm (activity max HR)" : "peak HR from data")
        + ". Set BIRTH_YEAR in config for age-based zones.";
    html += cardTip("Avg HR", Math.round(d.average_heartrate) + " bpm", hrTip);
  }
  if (d.max_heartrate) {
    var mhrTip = ATHLETE_AGE > 0
      ? "HRmax = 220 − " + ATHLETE_AGE + " = " + (220 - ATHLETE_AGE) + " bpm · used for zone thresholds"
      : "This value is used as HRmax for zone thresholds."
        + " Set BIRTH_YEAR in config for age-based zones.";
    html += cardTip("Max HR", Math.round(d.max_heartrate) + " bpm", mhrTip);
  }
  if (d.average_cadence)   html += card("Avg cadence", Math.round(d.average_cadence));
  if (d.average_watts)     html += card("Avg power", Math.round(d.average_watts) + " W");
  // Normalized power (weighted average) + Variability Index = NP / avg.
  if (d.weighted_average_watts) {
    var vi = d.average_watts > 0 ? (d.weighted_average_watts / d.average_watts).toFixed(2) : null;
    html += card("Norm. power", Math.round(d.weighted_average_watts) + " W" +
      (vi ? ' <span style="color:#888;font-size:.8rem">VI ' + vi + '</span>' : ''));
  }
  if (d.max_watts)         html += card("Max power", Math.round(d.max_watts) + " W");
  if (d.kilojoules)        html += card("Work", Math.round(d.kilojoules) + " kJ");
  if (d.calories)          html += card("Calories", Math.round(d.calories));
  if (d.suffer_score != null) html += card("Relative effort", Math.round(d.suffer_score));
  if (d.average_temp != null) html += card("Temp", Math.round(d.average_temp) + " °C");
  if (d.gear && d.gear.name) html += card("Gear", esc(d.gear.name));
  if (d.device_name)       html += card("Device", esc(d.device_name));
  document.getElementById("cards").innerHTML = html;
}

// --- Generic area line chart (elevation profile / heart rate) ----------------
// points: numeric array; color: stroke/fill hex; unit: label suffix (e.g. "m", "bpm")
// xLabels: optional string array (same length as points) — when provided the chart
// uses 30 px/point spacing (matching the splits bar chart) and renders x-axis ticks.
// Without xLabels (GPX charts with hundreds of points) the chart stays compact.
function drawLineSvg(svgId, points, color, unit, xLabels) {
  var n = points.length;
  if (!n) return;
  var minV = points[0], maxV = points[0], i;
  for (i = 1; i < n; i++) {
    if (points[i] < minV) minV = points[i];
    if (points[i] > maxV) maxV = points[i];
  }
  var base = (unit === "bpm") ? Math.max(40, minV - Math.max(10, Math.round((maxV - minV) * 0.15))) : minV;
  var range = (maxV - base) || 1;
  var YAX_W = 52, barW = 30;
  var yaxisSvg = document.getElementById(svgId + "-yaxis");
  var px = yaxisSvg ? 0 : YAX_W;  // no left margin when y-axis lives in a separate fixed SVG
  var labelH = xLabels ? 20 : 0;
  var W = xLabels ? (px + n * barW + 16) : Math.max(n * 2, 360);
  var H = 200, ch = H - 18 - labelH;
  var path = "", x, y;
  for (i = 0; i < n; i++) {
    x = (px + i * (W - px - 16) / (n > 1 ? n - 1 : 1)).toFixed(1);
    y = (ch - ((points[i] - base) / range) * (ch - 24)).toFixed(1);
    path += (i ? "L" : "M") + x + "," + y;
  }
  var fill = path + "L" + (W - 16) + "," + ch + "L" + px + "," + ch + "Z";

  // Three horizontal grid lines: at base, mid, and max.
  // When a separate y-axis SVG exists, labels go there; grid lines remain in the main SVG.
  var gridLines = "";
  var yaxisHtml = "";
  var gridVals = [base, base + range * 0.5, base + range];
  for (i = 0; i < gridVals.length; i++) {
    var gy = (ch - ((gridVals[i] - base) / range) * (ch - 24)).toFixed(1);
    var lbl = Math.round(gridVals[i]) + " " + unit;
    gridLines +=
      '<line x1="' + px + '" y1="' + gy + '" x2="' + (W - 16) + '" y2="' + gy +
      '" stroke="#e0e0e0" stroke-width="1"/>';
    if (yaxisSvg) {
      yaxisHtml +=
        '<text x="' + (YAX_W - 6) + '" y="' + (parseFloat(gy) + 4) + '" text-anchor="end" font-size="11" fill="#666">' + lbl + '</text>' +
        '<line x1="' + (YAX_W - 3) + '" y1="' + gy + '" x2="' + YAX_W + '" y2="' + gy + '" stroke="#ccc" stroke-width="1"/>';
    } else {
      gridLines +=
        '<text x="' + (px - 6) + '" y="' + (parseFloat(gy) + 4) + '" text-anchor="end" font-size="11" fill="#666">' + lbl + '</text>';
    }
  }
  if (yaxisSvg) {
    yaxisSvg.setAttribute("viewBox", "0 0 " + YAX_W + " " + H);
    yaxisSvg.setAttribute("width", YAX_W);
    yaxisSvg.setAttribute("height", H);
    yaxisSvg.innerHTML = yaxisHtml;
  }

  var html = gridLines +
    '<path d="' + fill + '" fill="' + color + '" opacity=".18"/>' +
    '<path d="' + path + '" fill="none" stroke="' + color + '" stroke-width="2" stroke-linejoin="round"/>';
  if (xLabels) {
    var stride = n > 120 ? 5 : n > 60 ? 2 : 1;
    for (i = 0; i < n; i += stride) {
      x = (px + i * (W - px - 16) / (n > 1 ? n - 1 : 1)).toFixed(1);
      html += '<text x="' + x + '" y="' + (H - 4) + '" text-anchor="middle" font-size="11" fill="#666">' + xLabels[i] + '</text>';
    }
  }
  // Build per-point tooltip data and add a transparent hit overlay.
  var tipEntries = [];
  for (i = 0; i < n; i++) {
    var tx = parseFloat((px + i * (W - px - 16) / (n > 1 ? n - 1 : 1)).toFixed(1));
    var tipLabel = xLabels
      ? ('<strong>Km ' + esc(xLabels[i]) + '</strong>')
      : ('<strong>' + (unit === 'bpm' ? 'Heart rate' : 'Elevation') + '</strong>');
    tipEntries.push({x: tx, html: tipLabel + Math.round(points[i]) + ' ' + unit});
  }
  LINE_TIPS[svgId] = tipEntries;
  html += '<rect x="' + px + '" y="0" width="' + (W - px - 16) + '" height="' + H + '"'
        + ' fill="transparent" style="cursor:crosshair"'
        + ' onmousemove="lineChartHover(event,\'' + svgId + '\')"'
        + ' onmouseout="hideTip()"/>';

  var svg = document.getElementById(svgId);
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);
  svg.style.width = W + "px";
  svg.innerHTML = html;
}

function renderElevFromSplits(splits) {
  var hasElev = false, i;
  for (i = 0; i < splits.length; i++) {
    if (splits[i].elevation_difference != null) { hasElev = true; break; }
  }
  if (!hasElev) return;
  var cum = [0], labels = ["0"];
  for (i = 0; i < splits.length; i++) {
    cum.push(cum[cum.length - 1] + (splits[i].elevation_difference || 0));
    labels.push(String(i + 1));
  }
  document.getElementById("elev-box").style.display = "";
  drawLineSvg("svg-elev", cum, "#fc4c02", "m", labels);
}

function renderHrFromSplits(splits) {
  var hrs = [], labels = [], i, hr;
  for (i = 0; i < splits.length; i++) {
    hr = splits[i].average_heartrate;
    if (hr > 0) { hrs.push(hr); labels.push(String(i + 1)); }
  }
  if (!hrs.length) return;
  document.getElementById("hr-box").style.display = "";
  drawLineSvg("svg-hr", hrs, "#e91e63", "bpm", labels);
}

function renderCadFromSplits(splits) {
  var cads = [], labels = [], i, cad;
  for (i = 0; i < splits.length; i++) {
    cad = splits[i].average_cadence;
    if (cad > 0) { cads.push(cad); labels.push(String(i + 1)); }
  }
  if (!cads.length) return;
  document.getElementById("cad-box").style.display = "";
  drawLineSvg("svg-cad", cads, "#8e24aa", "rpm", labels);
}

// h:mm:ss / m:ss for zone time display; "0 s" for zero.
function fmtHMS(s) {
  s = Math.round(s);
  if (!s) return "0 s";
  var h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
  if (h > 0) return h + ":" + (m<10?"0":"") + m + ":" + (sec<10?"0":"") + sec;
  return m + ":" + (sec<10?"0":"") + sec;
}

// hrPoints: [{bpm, secs}] — secs is actual time (splits) or equal weight (GPX).
// maxHR: activity max_heartrate; if 0/null, derived from data.
// Zones S1–S5: <60%, 60-70%, 70-80%, 80-90%, ≥90% of HRmax.
// HRmax preference: ATHLETE_AGE > 0 → 220 − age; else activity maxHR; else peak from data.
function renderHrZones(hrPoints, maxHR) {
  if (!hrPoints.length) return;
  var i, bpm;
  var hrMax, sourceLabel;
  if (ATHLETE_AGE > 0) {
    hrMax = 220 - ATHLETE_AGE;
    sourceLabel = "HRmax " + hrMax + " bpm";
  } else {
    hrMax = maxHR || 0;
    if (!hrMax) {
      for (i = 0; i < hrPoints.length; i++)
        if (hrPoints[i].bpm > hrMax) hrMax = hrPoints[i].bpm;
    }
    sourceLabel = hrMax ? "HRmax " + hrMax + " bpm (activity max)" : "";
  }
  if (!hrMax) return;
  var pcts = [0.60, 0.70, 0.80, 0.90];
  var t = [];
  for (i = 0; i < pcts.length; i++) t.push(Math.round(pcts[i] * hrMax));
  var labels = [
    "< " + t[0] + " bpm",
    t[0] + " – " + (t[1]-1) + " bpm",
    t[1] + " – " + (t[2]-1) + " bpm",
    t[2] + " – " + (t[3]-1) + " bpm",
    "≥ " + t[3] + " bpm"
  ];
  var colors = ["#5c9bd4","#4caf50","#ffc107","#ff7043","#ef5350"];
  var names  = ["Z1","Z2","Z3","Z4","Z5"];
  var descs  = [
    "Very light effort — warm-up and recovery (below 60% max HR)",
    "Easy effort — aerobic base building (60–70% max HR)",
    "Moderate effort — aerobic tempo (70–80% max HR)",
    "Intense effort — anaerobic threshold (80–90% max HR)",
    "Maximum effort — peak performance (above 90% max HR)"
  ];
  var zoneSecs = [0,0,0,0,0], totalSecs = 0, zone, secs;
  for (i = 0; i < hrPoints.length; i++) {
    bpm = hrPoints[i].bpm; secs = hrPoints[i].secs;
    if (bpm <= 0) continue;
    if      (bpm < t[0]) zone = 0;
    else if (bpm < t[1]) zone = 1;
    else if (bpm < t[2]) zone = 2;
    else if (bpm < t[3]) zone = 3;
    else                 zone = 4;
    zoneSecs[zone] += secs; totalSecs += secs;
  }
  if (!totalSecs) return;
  var html = '<table class="hr-zone-table">';
  for (i = 4; i >= 0; i--) {
    var pct = zoneSecs[i] / totalSecs * 100;
    var barW = Math.min(100, Math.round(pct));
    html += '<tr title="' + descs[i] + '">'
      + '<td style="font-weight:600;color:' + colors[i] + ';white-space:nowrap;cursor:help">' + names[i] + '</td>'
      + '<td style="color:#666;white-space:nowrap">' + labels[i] + '</td>'
      + '<td style="font-variant-numeric:tabular-nums;white-space:nowrap">' + fmtHMS(zoneSecs[i]) + '</td>'
      + '<td style="font-variant-numeric:tabular-nums;color:#888;white-space:nowrap">' + pct.toFixed(1) + '%</td>'
      + '<td style="width:100px"><div class="hr-zone-bar" style="width:' + barW + 'px;background:' + colors[i] + '"></div></td>'
      + '</tr>';
  }
  html += '</table>';
  document.getElementById("hr-zone-content").innerHTML = html;
  var titleEl = document.getElementById("hr-zone-title");
  titleEl.textContent = "Heart rate zones · " + sourceLabel;
  titleEl.title = ATHLETE_AGE > 0
    ? "Max HR = 220 − " + ATHLETE_AGE + " = " + hrMax + " bpm (Haskell-Fox formula)"
    : "Zone thresholds based on this activity's peak recorded HR (" + hrMax + " bpm)."
      + " Set BIRTH_YEAR in config for age-based zones.";
  titleEl.style.cursor = "help";
  document.getElementById("hr-zone-box").style.display = "";
}

// --- GPX map (healthsync activities) ----------------------------------------
// Try tile providers in order; switch on first error.
// OSM → CartoDB Voyager → Esri (different CDNs; one usually clears SSL proxies).
var TILE_PROVIDERS = [
  { url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    attr: "&copy; OpenStreetMap contributors" },
  { url: "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
    attr: "&copy; OpenStreetMap &copy; CartoDB" },
  { url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}",
    attr: "Tiles &copy; Esri" }
];
function makeTileLayer(map) {
  var idx = 0, switching = false;
  var p = TILE_PROVIDERS[0];
  var layer = L.tileLayer(p.url, { maxZoom: 19, attribution: p.attr }).addTo(map);
  layer.on("tileerror", function() {
    if (switching) return;
    if (idx + 1 < TILE_PROVIDERS.length) {
      switching = true;
      idx++;
      var np = TILE_PROVIDERS[idx];
      layer.options.attribution = np.attr;
      layer.setUrl(np.url);
      setTimeout(function() { switching = false; }, 3000);
    } else {
      if (!map.getContainer().querySelector(".tile-unavail")) {
        var n = document.createElement("div");
        n.className = "tile-unavail";
        n.style.cssText = "position:absolute;bottom:30px;left:50%;transform:translateX(-50%);background:rgba(255,255,255,.85);padding:4px 10px;font-size:12px;border-radius:3px;pointer-events:none;z-index:1000;white-space:nowrap";
        n.textContent = "Map tiles unavailable — route still shown";
        map.getContainer().appendChild(n);
      }
    }
  });
  return layer;
}

// Fetch + parse ourselves to avoid leaflet-gpx's responseXML=null crash when
// uhttpd serves .gpx without an XML Content-Type header.
function renderGpxMap(gpxUrl){
  var box = document.getElementById("map-box");
  if (typeof L === "undefined") {
    hideMapSpin();
    box.innerHTML = '<div class="note">Map library unavailable (needs internet).</div>';
    return;
  }
  fetch(gpxUrl)
    .then(function(r){
      if (!r.ok) { hideMapSpin(); box.innerHTML = '<div class="note">GPX not found (' + r.status + '): ' + gpxUrl + '</div>'; throw null; }
      return r.text();
    })
    .then(function(txt){
      if (txt === null) return;
      if (!txt.trim()) { hideMapSpin(); box.innerHTML = '<div class="note">GPX file is empty.</div>'; return; }
      var doc = (new DOMParser()).parseFromString(txt, "application/xml");
      var perr = doc.documentElement && doc.documentElement.nodeName === "parsererror";
      if (perr) { hideMapSpin(); box.innerHTML = '<div class="note">GPX not valid XML — first bytes: <code>' + txt.slice(0,120).replace(/</g,"&lt;") + '</code></div>'; return; }
      var els = doc.getElementsByTagNameNS("*", "trkpt");
      if (!els.length) els = doc.getElementsByTagNameNS("*", "rtept");
      var pts = [], i, el;
      for (i = 0; i < els.length; i++) {
        el = els[i];
        pts.push([parseFloat(el.getAttribute("lat")), parseFloat(el.getAttribute("lon"))]);
      }
      if (!pts.length) { hideMapSpin(); box.innerHTML = '<div class="note">GPX has no track points.</div>'; return; }
      try {
        var map = L.map("map");
        leafletMap = map;
        var tileLayer = makeTileLayer(map);
        var line = L.polyline(pts, { color: "#fc4c02", weight: 4, opacity: 0.9 }).addTo(map);
        leafletLine = line;
        map.fitBounds(line.getBounds(), { padding: [20, 20] });
        L.circleMarker(pts[0], { radius: 5, color: "#2e7d32", fillColor: "#2e7d32", fillOpacity: 1 }).addTo(map);
        L.circleMarker(pts[pts.length-1], { radius: 5, color: "#c62828", fillColor: "#c62828", fillOpacity: 1 }).addTo(map);
        setTimeout(function(){ map.invalidateSize(); map.fitBounds(line.getBounds(), { padding: [20, 20] }); }, 0);
        tileLayer.once("load", hideMapSpin);
        setTimeout(hideMapSpin, 10000);
      } catch(e) {
        hideMapSpin();
        box.innerHTML = '<div class="note">Map render failed: ' + e.message + '</div>';
      }
    })
    .catch(function(e){
      if (e === null) return;
      hideMapSpin();
      box.innerHTML = '<div class="note">GPX fetch error: ' + (e && e.message || String(e)) + '</div>';
    });
}

// --- GPX elevation + heart rate + cadence charts (healthsync activities) -----
// Fetches the GPX once and populates elev-box, hr-box, hr-zone-box, and cad-box when data is present.
function renderGpxCharts(gpxUrl, maxHR, movingTime) {
  fetch(gpxUrl)
    .then(function(r){ if (!r.ok) throw new Error("HTTP " + r.status); return r.text(); })
    .then(function(txt){
      var doc = (new DOMParser()).parseFromString(txt, "application/xml");
      var i, step;

      // Elevation from <ele> elements
      var eles = doc.getElementsByTagNameNS("*", "ele");
      if (eles.length) {
        var allE = [];
        for (i = 0; i < eles.length; i++) allE.push(parseFloat(eles[i].textContent) || 0);
        step = Math.max(1, Math.floor(allE.length / 300));
        var se = [];
        for (i = 0; i < allE.length; i += step) se.push(allE[i]);
        document.getElementById("elev-box").style.display = "";
        drawLineSvg("svg-elev", se, "#fc4c02", "m");
      }

      // Heart rate from track-point extensions (<gpxtpx:hr>, <hr>, <heartrate>)
      var trkpts = doc.getElementsByTagNameNS("*", "trkpt");
      if (!trkpts.length) trkpts = doc.getElementsByTagNameNS("*", "rtept");
      var allH = [], hrEls, bpm;
      for (i = 0; i < trkpts.length; i++) {
        hrEls = trkpts[i].getElementsByTagNameNS("*", "hr");
        if (!hrEls.length) hrEls = trkpts[i].getElementsByTagNameNS("*", "heartrate");
        bpm = hrEls.length ? (parseFloat(hrEls[0].textContent) || 0) : 0;
        if (bpm > 0) allH.push(bpm);
      }
      if (allH.length) {
        step = Math.max(1, Math.floor(allH.length / 300));
        var sh = [];
        for (i = 0; i < allH.length; i += step) sh.push(allH[i]);
        document.getElementById("hr-box").style.display = "";
        drawLineSvg("svg-hr", sh, "#e91e63", "bpm");
        // Distribute movingTime equally across all HR track points for zone estimation.
        var secsPerPt = allH.length > 0 ? (movingTime || allH.length) / allH.length : 1;
        var gpxZonePts = [];
        for (i = 0; i < allH.length; i++) gpxZonePts.push({bpm: allH[i], secs: secsPerPt});
        renderHrZones(gpxZonePts, maxHR);
      }

      // Cadence from track-point extensions (<gpxtpx:cad>, <cad>, <cadence>)
      var allC = [], cadEls, rpm;
      for (i = 0; i < trkpts.length; i++) {
        cadEls = trkpts[i].getElementsByTagNameNS("*", "cad");
        if (!cadEls.length) cadEls = trkpts[i].getElementsByTagNameNS("*", "cadence");
        rpm = cadEls.length ? (parseFloat(cadEls[0].textContent) || 0) : 0;
        if (rpm > 0) allC.push(rpm);
      }
      if (allC.length) {
        step = Math.max(1, Math.floor(allC.length / 300));
        var sc = [];
        for (i = 0; i < allC.length; i += step) sc.push(allC[i]);
        document.getElementById("cad-box").style.display = "";
        drawLineSvg("svg-cad", sc, "#8e24aa", "rpm");
      }
    })
    .catch(function(e){
      var box = document.getElementById("elev-box");
      box.style.display = "";
      box.querySelector("svg").insertAdjacentHTML("beforebegin",
        '<div class="note">GPX charts unavailable: ' + esc(e.message) + '</div>');
    });
}

function renderMap(d){
  // GPX path: healthsync activities — the GPX file is cached locally on the router.
  if (d.gpx_file) { renderGpxMap(d.gpx_file); return; }
  var box = document.getElementById("map-box");
  var enc = d.map && (d.map.polyline || d.map.summary_polyline);
  if (!enc || typeof L === "undefined") {
    box.innerHTML = '<div class="note">'
      + (enc ? "Map library unavailable (needs internet)." : "No GPS route for this activity.")
      + '</div>';
    return;
  }
  var pts;
  try { pts = decodePolyline(enc); } catch (e) { pts = []; }
  if (!pts.length) { box.innerHTML = '<div class="note">Route could not be decoded.</div>'; return; }
  try {
    var map = L.map("map");
    leafletMap = map;
    var tileLayer = makeTileLayer(map);
    var line = L.polyline(pts, { color: "#fc4c02", weight: 4, opacity: .9 }).addTo(map);
    leafletLine = line;
    map.fitBounds(line.getBounds(), { padding: [20, 20] });
    L.circleMarker(pts[0], { radius: 5, color: "#2e7d32", fillColor: "#2e7d32", fillOpacity: 1 }).addTo(map);
    L.circleMarker(pts[pts.length-1], { radius: 5, color: "#c62828", fillColor: "#c62828", fillOpacity: 1 }).addTo(map);
    // The container may have just become visible; re-measure so tiles fill it.
    setTimeout(function(){ map.invalidateSize(); map.fitBounds(line.getBounds(), { padding: [20, 20] }); }, 0);
    // Hide the map spinner once tiles have loaded; fall back after 10s.
    tileLayer.once("load", hideMapSpin);
    setTimeout(hideMapSpin, 10000);
  } catch (e) {
    box.innerHTML = '<div class="note">Map failed to load (needs internet).</div>';
  }
}

function renderSplits(d){
  // GPX activities: elevation + HR charts are rendered from renderGpxCharts (called below);
  // there are no km splits to show, so hide that box.
  if (d.gpx_file) { renderGpxCharts(d.gpx_file, d.max_heartrate || 0, d.moving_time || 0); document.getElementById("splits-box").style.display = "none"; return; }
  var box = document.getElementById("splits-box");
  var splits = d.splits_metric || [];
  if (!splits.length) { box.innerHTML = '<h3>Splits</h3><div class="note">No splits recorded for this activity.</div>'; return; }

  var sport = d.sport_type || d.type || "";
  var foot = isFoot(sport);
  document.getElementById("splits-title").innerHTML = foot ? "Per-km pace" : "Per-km speed";

  // Bar height is always proportional to speed, so taller = faster regardless
  // of sport; the label/tooltip shows pace for foot sports, km/h otherwise.
  var speeds = splits.map(function(s){
    return (s.moving_time > 0) ? (s.distance / s.moving_time) : (s.average_speed || 0);
  });
  var max = Math.max.apply(null, speeds) || 1;

  var n = splits.length, barW = 30, pad = 16, labelH = 16;
  var W = pad*2 + n*barW, H = 200, chartH = H - labelH;
  var svg = document.getElementById("svg-splits");
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);
  svg.style.width = W + "px";

  TIP_DATA = [];
  var html = "";
  for (var i = 0; i < n; i++) {
    var s = splits[i], spd = speeds[i];
    var barH = Math.round((spd / max) * (chartH - 20));
    if (barH < 1) barH = 1;
    var x = pad + i*barW;
    var label = foot ? fmtPace(spd) : (spd*3.6).toFixed(1);
    var km = (s.distance/1000);

    var tip = '<strong>Km ' + (i+1) + '</strong>'
      + (km < 0.97 ? 'Distance: ' + km.toFixed(2) + ' km<br>' : '')
      + (foot ? 'Pace: ' + fmtPace(spd) : 'Speed: ' + (spd*3.6).toFixed(1) + ' km/h') + '<br>'
      + 'Time: ' + fmtTime(s.moving_time || s.elapsed_time || 0);
    if (s.elevation_difference != null) tip += '<br>Elev: ' + (s.elevation_difference>=0?'+':'') + Math.round(s.elevation_difference) + ' m';
    if (s.average_heartrate) tip += '<br>HR: ' + Math.round(s.average_heartrate) + ' bpm';
    if (s.average_cadence) tip += '<br>Cadence: ' + Math.round(s.average_cadence) + ' rpm';
    TIP_DATA.push(tip);

    html += '<rect x="'+(x+1)+'" y="'+(chartH-barH)+'" width="'+(barW-2)+'" height="'+barH+'" fill="#fc4c02" rx="2"'
      + ' onmouseover="showTip(event,'+i+')" onmousemove="moveTip(event)" onmouseout="hideTip()" style="cursor:pointer"/>';
    html += '<text x="'+(x+barW/2)+'" y="'+(chartH-barH-4)+'" text-anchor="middle" font-size="8.5" fill="#444">'+label+'</text>';
    html += '<text x="'+(x+barW/2)+'" y="'+(H-3)+'" text-anchor="middle" font-size="9" fill="#888">'+(i+1)+'</text>';
  }
  svg.innerHTML = html;

  // Elevation, heart rate, and cadence charts from splits data (when available).
  renderElevFromSplits(splits);
  renderHrFromSplits(splits);
  renderCadFromSplits(splits);
  // Heart rate zones estimated from per-km split averages.
  var hrZonePts = [], zi;
  for (zi = 0; zi < splits.length; zi++) {
    if (splits[zi].average_heartrate > 0)
      hrZonePts.push({bpm: splits[zi].average_heartrate, secs: splits[zi].moving_time || 0});
  }
  renderHrZones(hrZonePts, d.max_heartrate || 0);
}

// --- Bike assignment picker (cycling activities only) -------------------------
var BIKE_SPORTS = { Ride:1, EBikeRide:1, VirtualRide:1, MountainBikeRide:1, GravelRide:1, Handcycle:1 };
function isBike(sport){ return !!BIKE_SPORTS[sport]; }

function loadBikePicker(d, actId) {
  Promise.all([
    fetch("/cgi-bin/bike-service")
      .then(function(r){ return r.ok ? r.json() : null; }).catch(function(){ return null; }),
    fetch("/cgi-bin/bike-assign")
      .then(function(r){ return r.ok ? r.json() : {}; }).catch(function(){ return {}; })
  ]).then(function(res) {
    var svc = res[0], assigns = res[1] || {};
    var bikes = (svc && svc.bikes) || [];
    if (!bikes.length) return;
    // Current value: explicit override, then Strava gear name, then HealthSync gear_id string,
    // then the default bike for untagged activities.
    var current = assigns[actId];
    if (current === undefined) {
      current = (d.gear && d.gear.name) ||
                (d.gear_id && !/^b[0-9]+$/.test(String(d.gear_id)) ? d.gear_id : "") || "";
    }
    if (!current && isBike(d.sport_type)) {
      for (var i = 0; i < bikes.length; i++) {
        if (bikes[i].isDefault) { current = bikes[i].name || ""; break; }
      }
    }
    var opts = '<option value="">— unassigned —</option>';
    for (var i = 0; i < bikes.length; i++) {
      var n = bikes[i].name || "";
      opts += '<option value="' + esc(n) + '"' + (current === n ? ' selected' : '') + '>' + esc(n) + '</option>';
    }
    var row = document.getElementById("bike-row");
    row.innerHTML = '<label style="color:#666">Bike: '
      + '<select id="bike-sel" style="font:inherit;font-size:.9rem;border:1px solid #ccc;'
      + 'border-radius:.3rem;padding:.1rem .4rem;margin-left:.2rem">'
      + opts + '</select></label>'
      + ' <span id="bike-status" style="font-size:.8rem;color:#888"></span>';
    row.style.display = "block";
    document.getElementById("bike-sel").onchange = function() {
      saveBike(actId, this.value, assigns);
    };
  }).catch(function(){});
}

function saveBike(actId, value, assigns) {
  var status = document.getElementById("bike-status");
  if (status) status.textContent = "Saving…";
  if (value) { assigns[actId] = value; } else { delete assigns[actId]; }
  fetch("/cgi-bin/bike-assign", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(assigns)
  }).then(function(r) {
    if (!r.ok) throw new Error("HTTP " + r.status);
    if (status) { status.textContent = "Saved"; setTimeout(function(){ status.textContent = ""; }, 2000); }
  }).catch(function(e) {
    if (status) status.textContent = "Error: " + (e && e.message || String(e));
  });
}

function render(d, id){
  // Reveal the container first so the map measures a real size at init time —
  // a Leaflet map created inside a display:none box renders grey, tile-less.
  document.getElementById("content").style.display = "block";
  document.getElementById("name").textContent = d.name || "Activity";
  var when = (d.start_date_local || d.start_date || "");
  var sub = [];
  if (when) sub.push(esc(when.slice(0,10) + (when.length > 10 ? " " + when.slice(11,16) : "")));
  if (d.sport_type || d.type) sub.push(esc(d.sport_type || d.type));
  document.getElementById("sub").innerHTML = sub.join(" · ");

  if (d.description) {
    var de = document.getElementById("desc");
    de.textContent = d.description; de.style.display = "block";
  }
  var stravaLink = /^[0-9]+$/.test(id)
    ? '<a href="https://www.strava.com/activities/'+encodeURIComponent(id)+'" target="_blank" rel="noopener">Open on Strava</a>'
    : '';
  document.getElementById("links").innerHTML = stravaLink
    + '<a href="details/'+encodeURIComponent(id)+'.json">Raw JSON</a>';

  renderCards(d);
  if (isBike(d.sport_type || d.type || "")) loadBikePicker(d, id);
  renderMap(d);
  renderSplits(d);
}

function fail(msg){ progressDone(); hideMapSpin(); document.getElementById("err").textContent = msg; }

(function(){
  var id = getId();
  if (!id) { fail("No activity id in the URL. Go back and click an activity."); return; }
  progressStart();
  Promise.all([
    fetch("details/" + id + ".json", { cache: "no-store" })
      .then(function(r){
        if (r.status === 404) throw new Error("Detail for this activity hasn't been downloaded yet — it backfills over the next daily runs. Try again later.");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      }),
    fetch("activities.json")
      .then(function(r){ return r.ok ? r.json() : {}; })
      .catch(function(){ return {}; })
  ]).then(function(res){
    progressDone();
    var d = res[0], meta = res[1];
    if (meta && meta.athleteAge) ATHLETE_AGE = meta.athleteAge;
    if (d.average_temp == null && meta && meta.activities) {
      var act = meta.activities.find(function(a){ return String(a.id) === String(id); });
      if (act && act.average_temp != null) d.average_temp = act.average_temp;
    }
    render(d, id);
  }).catch(function(err){ fail(err.message); });
})();
</script>
</body>
</html>
HTML
