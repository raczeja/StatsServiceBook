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
  svg.splits{max-width:100%;height:200px;display:block;margin:0 auto}
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
</style>
</head>
<body>
<div id="pbar"></div>
<div id="chart-tip"></div>
<div class="crumbs"><a href="index.html">&larr; All activities</a></div>
<div id="err"></div>
<div id="content" style="display:none">
  <h1 id="name"></h1>
  <div class="sub" id="sub"></div>
  <div class="desc" id="desc" style="display:none"></div>
  <div class="links" id="links"></div>
  <div class="cards" id="cards"></div>
  <div id="map-box">
    <div id="map"></div>
    <div id="map-spin">Loading map…<div id="map-spin-bar"></div></div>
  </div>
  <div class="box" id="splits-box">
    <h3 id="splits-title">Splits</h3>
    <svg class="splits" id="svg-splits" preserveAspectRatio="xMidYMid meet"></svg>
  </div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
"use strict";
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

// --- Tooltip (shared with the splits chart) --------------------------------
var TIP_DATA = [], tipEl = null;
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
  return decodeURIComponent(m[1]).replace(/[^0-9]/g, "");   // digits only
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
  if (d.average_heartrate) html += card("Avg HR", Math.round(d.average_heartrate) + " bpm");
  if (d.max_heartrate)     html += card("Max HR", Math.round(d.max_heartrate) + " bpm");
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

function renderMap(d){
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
    var tileLayer = L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, attribution: "&copy; OpenStreetMap contributors"
    }).addTo(map);
    var line = L.polyline(pts, { color: "#fc4c02", weight: 4, opacity: .9 }).addTo(map);
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
  // Render at natural pixel size (CSS max-width:100% scales it down uniformly
  // when there are many splits). Without this the SVG would stretch to fill the
  // card, ballooning bars and distorting labels for short, few-split activities.
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
    TIP_DATA.push(tip);

    html += '<rect x="'+(x+1)+'" y="'+(chartH-barH)+'" width="'+(barW-2)+'" height="'+barH+'" fill="#fc4c02" rx="2"'
      + ' onmouseover="showTip(event,'+i+')" onmousemove="moveTip(event)" onmouseout="hideTip()" style="cursor:pointer"/>';
    html += '<text x="'+(x+barW/2)+'" y="'+(chartH-barH-4)+'" text-anchor="middle" font-size="8.5" fill="#444">'+label+'</text>';
    html += '<text x="'+(x+barW/2)+'" y="'+(H-3)+'" text-anchor="middle" font-size="9" fill="#888">'+(i+1)+'</text>';
  }
  svg.innerHTML = html;
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
  document.getElementById("links").innerHTML =
    '<a href="https://www.strava.com/activities/'+encodeURIComponent(id)+'" target="_blank" rel="noopener">Open on Strava</a>'
    + '<a href="details/'+encodeURIComponent(id)+'.json">Raw JSON</a>';

  renderCards(d);
  renderMap(d);
  renderSplits(d);
}

function fail(msg){ progressDone(); hideMapSpin(); document.getElementById("err").textContent = msg; }

(function(){
  var id = getId();
  if (!id) { fail("No activity id in the URL. Go back and click an activity."); return; }
  progressStart();
  fetch("details/" + id + ".json", { cache: "no-store" })
    .then(function(r){
      if (r.status === 404) throw new Error("Detail for this activity hasn't been downloaded yet — it backfills over the next daily runs. Try again later.");
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(function(d){ progressDone(); render(d, id); })
    .catch(function(err){ fail(err.message); });
})();
</script>
</body>
</html>
HTML
