# strava-my-html-heatmap.sh — sourced by strava-my-activities.sh and healthsync-activities.sh.
# Generates $WEB_DIR/heatmap.json (array of {d,s,p} per GPS activity) and writes
# $WEB_DIR/heatmap.html (full-viewport Leaflet.heat heatmap with period + sport filter).
# Uses awk for GPX coordinate extraction — jq cannot parse XML.
# Quoted heredoc: nothing shell-expanded.

# --- 7. Generate heatmap.json -----------------------------------------------
# Incremental: sampled points per GPX file are cached in $STATE_DIR/heatmap-cache.ndjson
# ({"k":"gpx/<id>.gpx","p":[[lat,lng],...]}). Only GPX files missing from the cache are
# read (grep+awk, ~0.4 s each on the router); heatmap.json is then assembled from the
# cache with a single jq pass. Bump _hm_ver when the sampling logic changes.
_hm_ver=1
_hm_cache="${STATE_DIR:-$WEB_DIR}/heatmap-cache.ndjson"
_hm_verfile="${STATE_DIR:-$WEB_DIR}/heatmap-cache.ver"
_hm_sigfile="${STATE_DIR:-$WEB_DIR}/heatmap-cache.sig"
log "html: writing heatmap.json..."
# heatmap.json: [{d:"YYYY-MM-DD", s:"Ride", p:[[lat,lng],...]}]
# Source: activities.json for GPX paths, dates and sport types; every 10th trkpt.
if [ -f "$WEB_DIR/activities.json" ]; then
  _hm_tab="$(printf '\t')"
  if [ "$(cat "$_hm_verfile" 2>/dev/null)" != "$_hm_ver" ]; then
    : > "$_hm_cache"
    printf '%s' "$_hm_ver" > "$_hm_verfile"
  fi
  [ -f "$_hm_cache" ] || : > "$_hm_cache"
  # Strava: no gpx_file field → derive from numeric id.
  # HealthSync: gpx_file field present (original filename stored in activities.json).
  # Candidate GPX paths come from activities.json (small); cached keys are read with grep
  # (no JSON parse of the multi-MB cache on the router). Only GPX files that EXIST and
  # have no cache entry are sampled — activities without a GPX file (indoor etc.) are
  # skipped silently and cost nothing. Progress logs MUST go to stderr (log() writes to
  # stdout) — the loop body's stdout is appended to the cache.
  jq -r '.activities[]? | select(.id != null and (.date // "") != "")
    | (if .gpx_file != null then .gpx_file else "gpx/" + (.id | tostring) + ".gpx" end)' \
    "$WEB_DIR/activities.json" 2>/dev/null | sort -u > "$TMP/hm_all.txt" || true
  grep -o '^{"k":"[^"]*"' "$_hm_cache" 2>/dev/null | awk -F'"' '{print $4}' > "$TMP/hm_have.txt" || true
  : > "$TMP/hm_missing.txt"
  # BusyBox `grep -vxF -f <empty file>` prints nothing, so special-case a cold cache.
  { if [ -s "$TMP/hm_have.txt" ]; then grep -vxF -f "$TMP/hm_have.txt" "$TMP/hm_all.txt" 2>/dev/null || true
    else cat "$TMP/hm_all.txt"; fi; } | while IFS= read -r _hm_gpx; do
    [ -f "$WEB_DIR/$_hm_gpx" ] && printf '%s\n' "$_hm_gpx"
  done > "$TMP/hm_missing.txt" || true
  _hm_total="$(grep -c . "$TMP/hm_missing.txt" 2>/dev/null || true)"
  [ "${_hm_total:-0}" -gt 0 ] && log "html: heatmap.json — sampling $_hm_total new GPX files"
  _hm_n=0
  while IFS= read -r _hm_gpx; do
    [ -n "$_hm_gpx" ] || continue
    _hm_path="$WEB_DIR/$_hm_gpx"
    # Extract every 10th trkpt; split 'trkpt lat="LL" lon="NN"' on " to get a[2]=lat a[4]=lon
    _hm_pts="$(grep -o 'trkpt lat="[0-9.-]*" lon="[0-9.-]*"' "$_hm_path" | \
      awk 'NR%10==1{split($0,a,"\""); printf "%s[%.4f,%.4f]",(f++ ? "," : ""),a[2]+0,a[4]+0}')" || _hm_pts=""
    # Cache empty results too (p:[]) so no-GPS files aren't re-read every run.
    printf '{"k":"%s","p":[%s]}\n' "$_hm_gpx" "$_hm_pts" >> "$_hm_cache"
    _hm_n=$((_hm_n + 1))
    [ $((_hm_n % 50)) -eq 0 ] && log "html: heatmap.json — $_hm_n/$_hm_total sampled" >&2
  done < "$TMP/hm_missing.txt"
  # Skip the (slow) assembly when nothing was sampled and the activity list is unchanged.
  _hm_sig="$_hm_ver $(jq -c '[.activities[]? | [.id, .date, .sport_type, .gpx_file]]' "$WEB_DIR/activities.json" 2>/dev/null | md5sum)"
  if [ "$_hm_n" -eq 0 ] && [ -f "$WEB_DIR/heatmap.json" ] && [ "$(cat "$_hm_sigfile" 2>/dev/null)" = "$_hm_sig" ]; then
    log "html: heatmap.json up-to-date (no new GPX files, activity list unchanged) — skipping"
  else
  jq -c --slurpfile c "$_hm_cache" '
    ($c | map({(.k): .p}) | add // {}) as $m
    | [ .activities[]? | select(.id != null and (.date // "") != "")
        | (if .gpx_file != null then .gpx_file else "gpx/" + (.id | tostring) + ".gpx" end) as $g
        | select(($m[$g] // []) | length > 0)
        | {d: .date, s: (.sport_type // ""), p: $m[$g]} ]' \
    "$WEB_DIR/activities.json" > "$WEB_DIR/heatmap.json.tmp" 2>/dev/null \
        && mv "$WEB_DIR/heatmap.json.tmp" "$WEB_DIR/heatmap.json" \
        && printf '%s' "$_hm_sig" > "$_hm_sigfile" \
        || { rm -f "$WEB_DIR/heatmap.json.tmp"; [ -f "$WEB_DIR/heatmap.json" ] || printf '[]' > "$WEB_DIR/heatmap.json"; }
  fi
  unset _hm_tab _hm_gpx _hm_path _hm_pts _hm_n _hm_total _hm_sig
else
  printf '[]' > "$WEB_DIR/heatmap.json.tmp" && mv "$WEB_DIR/heatmap.json.tmp" "$WEB_DIR/heatmap.json"
fi
unset _hm_ver _hm_cache _hm_verfile _hm_sigfile

# --- 7b. Write heatmap.html -------------------------------------------------
log "html: writing heatmap.html..."
cat > "$WEB_DIR/heatmap.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Activity Heatmap</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN0YXRzU2VydmljZUJvb2siPgogIDxkZWZzPgogICAgPGNsaXBQYXRoIGlkPSJjbGlwIj4KICAgICAgPGNpcmNsZSBjeD0iMzIiIGN5PSIzMiIgcj0iMzAiLz4KICAgIDwvY2xpcFBhdGg+CiAgICA8bGluZWFyR3JhZGllbnQgaWQ9ImJnIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMyYTJhMmEiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMTExMTExIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KCiAgPCEtLSBCYWNrZ3JvdW5kIGNpcmNsZSAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMiIgZmlsbD0idXJsKCNiZykiLz4KCiAgPGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXApIj4KCiAgICA8IS0tIEFyZWEgZmlsbCB1bmRlciB0aGUgcm91dGUgbGluZSAtLT4KICAgIDxwb2x5Z29uCiAgICAgIHBvaW50cz0iNCw0NiAxMyw0NiAxOSwzMiAyNSw0MCAzMiwxOCAzOSwzMiA0NSwyNSA1MSwzMiA2MCwzMiA2MCw1NiA0LDU2IgogICAgICBmaWxsPSIjZmM0YzAyIiBmaWxsLW9wYWNpdHk9IjAuMTUiLz4KCiAgICA8IS0tIFJvdXRlIC8gZWxldmF0aW9uIHByb2ZpbGUg4oCUIHRoZSBjb3JlIGZlYXR1cmUgLS0+CiAgICA8cG9seWxpbmUKICAgICAgcG9pbnRzPSI0LDQ2IDEzLDQ2IDE5LDMyIDI1LDQwIDMyLDE4IDM5LDMyIDQ1LDI1IDUxLDMyIDYwLDMyIgogICAgICBmaWxsPSJub25lIgogICAgICBzdHJva2U9IiNmYzRjMDIiCiAgICAgIHN0cm9rZS13aWR0aD0iMy4yIgogICAgICBzdHJva2UtbGluZWNhcD0icm91bmQiCiAgICAgIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KCiAgICA8IS0tIEdQUyAvIHN0YXJ0IGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjQiIGN5PSI0NiIgcj0iMi41IiBmaWxsPSIjZmM0YzAyIi8+CgogICAgPCEtLSBGaW5pc2ggLyBjdXJyZW50LXBvc2l0aW9uIGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjYwIiBjeT0iMzIiIHI9IjIuNSIgZmlsbD0iI2ZjNGMwMiIvPgoKICA8L2c+CgogIDwhLS0gV2lGaSBzaWduYWwgYXJjcyDigJQgdG9wLXJpZ2h0LCByZXByZXNlbnRzIHRoZSByb3V0ZXIgLS0+CiAgPHBhdGggZD0iTTQzLDEzIFE1MCw3ICA1NywxMyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjQ1Ii8+CiAgPHBhdGggZD0iTTQ2LDE3IFE1MCwxMyA1NCwxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjc1Ii8+CiAgPGNpcmNsZSBjeD0iNTAiIGN5PSIyMSIgcj0iMi4yIiBmaWxsPSIjZmM0YzAyIi8+CgogIDwhLS0gT3V0ZXIgcmluZyAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLW9wYWNpdHk9IjAuMzUiLz4KPC9zdmc+Cg==" type="image/svg+xml">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,Arial,sans-serif;background:#111;color:#ddd;
     display:flex;flex-direction:column;height:100vh;overflow:hidden}
.hm-nav{display:flex;flex-wrap:wrap;gap:.4rem;padding:.4rem .9rem;
        background:#1a1a1a;border-bottom:1px solid #2a2a2a;flex-shrink:0}
.hm-nav a{padding:.25rem .5rem;background:#fc4c02;color:#fff;text-decoration:none;
          border-radius:.4rem;font-size:.8rem;font-weight:600;flex:0 0 auto}
.hm-nav a:hover{background:#e34402}
#bar{display:flex;align-items:center;gap:.75rem;padding:.55rem .9rem;
     background:#1a1a1a;border-bottom:1px solid #2a2a2a;flex-shrink:0;flex-wrap:wrap}
#bar h1{font-size:1rem;font-weight:700;color:#fc4c02;white-space:nowrap}
#bar label{font-size:.85rem;color:#bbb}
select{background:#222;color:#eee;border:1px solid #444;border-radius:.3rem;
       padding:.25rem .5rem;cursor:pointer;font-size:.85rem}
#count{margin-left:auto;font-size:.8rem;color:#888;white-space:nowrap}
#map{flex:1;min-height:0;opacity:0;transition:opacity .3s ease}
#map.ready{opacity:1}
#msg{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
     color:#888;font-size:.9rem;text-align:center;pointer-events:none;
     background:rgba(0,0,0,.5);padding:.6rem 1.2rem;border-radius:.4rem}
#pbar{position:fixed;top:0;left:0;width:0;height:3px;background:#fc4c02;z-index:9999;pointer-events:none}
.city-lbl{font-size:.7rem;font-weight:600;color:#eee;text-shadow:0 0 3px #000,0 0 3px #000;
          white-space:nowrap;pointer-events:none;padding-left:6px}
</style>
<script src="offline.js"></script>
</head>
<body>
<div id="pbar"></div>
<div class="hm-nav">
  <a href="index.html">&#8592; My Activities</a>
  <a href="bike.html">🔧 Bike service</a>
  <a href="stats.html">📊 My Stats</a>
  <a href="data-quality.html">&#128203; Data completeness</a>
  <a id="leaderboard-link" href="../" style="display:none">🏆 Club leaderboard</a>
</div>
<div id="bar">
  <h1>&#128506; Heatmap</h1>
  <label>Period:&nbsp;<select id="period"></select></label>
  <label>Sport:&nbsp;<select id="sport"></select></label>
  <span id="count"></span>
</div>
<div id="map"><div id="msg">Loading&hellip;</div></div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script src="https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js"></script>
<script>
"use strict";
// leaflet.heat's simpleheat calls getImageData on every redraw; hint the browser
// to keep the bitmap readable so it doesn't log a willReadFrequently perf warning.
// Scoped: the heat canvas is the only 2d canvas on this page.
(function(){
  var _gc = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function(type, attrs){
    if(type === '2d'){ attrs = attrs || {}; if(attrs.willReadFrequently === undefined) attrs.willReadFrequently = true; }
    return _gc.call(this, type, attrs);
  };
})();
fetch('../',{method:'HEAD'}).then(function(r){if(r.ok){var el=document.getElementById('leaderboard-link');if(el)el.style.display='';}}).catch(function(){});
var _pbar=null,_pbarTick=null,_pbarPct=0,_pbarT0=0;
function progressStart(){
  if(!_pbar)_pbar=document.getElementById("pbar");
  clearInterval(_pbarTick);_pbarPct=0;_pbarT0=Date.now();
  _pbar.style.cssText="width:0%;opacity:1;transition:none";
  _pbarTick=setInterval(function(){
    _pbarPct+=(_pbarPct<70?3:_pbarPct<85?1:0.2);
    if(_pbarPct>90)_pbarPct=90;
    _pbar.style.transition="width .3s ease";
    _pbar.style.width=_pbarPct+"%";
  },300);
}
function _progressFinish(){
  if(!_pbar)_pbar=document.getElementById("pbar");
  clearInterval(_pbarTick);
  _pbar.style.transition="width .15s ease";
  _pbar.style.width="100%";
  setTimeout(function(){_pbar.style.transition="opacity .4s ease";_pbar.style.opacity="0";},200);
}
function progressDone(){
  var wait=350-Math.min(350,Date.now()-_pbarT0);
  if(wait>0){setTimeout(_progressFinish,wait);}else{_progressFinish();}
}
var map = L.map('map',{zoomControl:true}).setView([48,15],4);

// Esri World Dark Gray Base — free, no API key. maxZoom 16 is fine for a heatmap.
// Falls back to OSM (light, but labels built-in) on tile error.
var _heatTileProviders = [
  { url:'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
    attr:'Tiles &copy; <a href="https://www.esri.com/">Esri</a>', maxZoom:16 },
  { url:'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    attr:'&copy; <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> contributors', maxZoom:19 }
];
var _heatTileIdx = 0, _heatTileSwitching = false;
var _tp = _heatTileProviders[0];
var _baseTile = L.tileLayer(_tp.url,{maxZoom:_tp.maxZoom,attribution:_tp.attr}).addTo(map);

// City/road label overlay — Esri Reference layer is a transparent tile set with just labels.
// Placed in a custom pane (z-index 450) above the heatmap canvas (overlayPane, z-index 400)
// so city names remain readable on top of the heat layer.
// Removed automatically if the base falls back to OSM (OSM tiles include built-in labels).
map.createPane('labels');
map.getPane('labels').style.zIndex = 450;
map.getPane('labels').style.pointerEvents = 'none';
var _labelTile = L.tileLayer(
  'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
  {maxZoom:16, attribution:'', pane:'labels'}
).addTo(map);

_baseTile.on('tileerror',function(){
  if(_heatTileSwitching||_heatTileIdx+1>=_heatTileProviders.length) return;
  _heatTileSwitching=true;
  _heatTileIdx++;
  var _np=_heatTileProviders[_heatTileIdx];
  map.removeLayer(_baseTile);
  // OSM has built-in labels; remove the separate Esri reference overlay.
  if(_labelTile){map.removeLayer(_labelTile);_labelTile=null;}
  _baseTile=L.tileLayer(_np.url,{maxZoom:_np.maxZoom,attribution:_np.attr}).addTo(map);
  _heatTileSwitching=false;
});

var heatLayer = null;
var allData = [];

function daysAgo(n){
  var d = new Date(); d.setDate(d.getDate()-n);
  return d.toISOString().slice(0,10);
}

function applyFilter(periodVal){
  var sportVal = document.getElementById('sport').value;
  var acts, from;
  if(periodVal === 'all'){
    acts = allData;
  } else if(periodVal === 'w7'){
    from = daysAgo(7);
    acts = allData.filter(function(a){ return a.d >= from; });
  } else if(periodVal === 'w30'){
    from = daysAgo(30);
    acts = allData.filter(function(a){ return a.d >= from; });
  } else if(periodVal === 'w90'){
    from = daysAgo(90);
    acts = allData.filter(function(a){ return a.d >= from; });
  } else {
    acts = allData.filter(function(a){ return a.d && a.d.slice(0,4) === periodVal; });
  }

  // Sport filter — '' means "All sports"
  if(sportVal){
    acts = acts.filter(function(a){ return a.s === sportVal; });
  }

  var pts = [];
  for(var i=0;i<acts.length;i++){
    var p = acts[i].p;
    for(var j=0;j<p.length;j++) pts.push(p[j]);
  }

  if(heatLayer){ map.removeLayer(heatLayer); heatLayer=null; }
  if(pts.length){
    heatLayer = L.heatLayer(pts,{
      radius:5, blur:8, minOpacity:0.4, max:5,
      gradient:{0.3:'#0055ff',0.55:'#fc4c02',0.8:'#ff8c00',1:'#ffff00'}
    }).addTo(map);
    map.fitBounds(L.latLngBounds(pts),{padding:[30,30],animate:false});
  }

  var n = acts.length;
  document.getElementById('count').textContent =
    n + ' activit' + (n===1?'y':'ies') +
    (pts.length ? ' · ' + pts.length.toLocaleString() + ' pts' : '');
}

progressStart();
fetch('heatmap.json',{cache:'no-cache'})
  .then(function(r){ return r.json(); })
  .then(function(data){
    allData = data;
    progressDone();
    var el = document.getElementById('msg');
    if(el) el.style.display = 'none';

    // --- Period dropdown ---
    var ymap = {};
    for(var i=0;i<data.length;i++){
      if(data[i].d && data[i].d.length >= 4) ymap[data[i].d.slice(0,4)] = 1;
    }
    var ys = Object.keys(ymap).sort().reverse();
    var psel = document.getElementById('period');
    var popts = [
      {v:'w90', l:'Last 3 months'},
      {v:'all', l:'All time'},
      {v:'w30', l:'Last 30 days'},
      {v:'w7',  l:'Last 7 days'}
    ];
    for(var i=0;i<ys.length;i++) popts.push({v:ys[i], l:ys[i]});
    for(var i=0;i<popts.length;i++){
      var o = document.createElement('option');
      o.value = popts[i].v; o.textContent = popts[i].l;
      psel.appendChild(o);
    }
    psel.value = 'w90';

    // --- Sport dropdown ---
    var smap = {};
    for(var i=0;i<data.length;i++){
      if(data[i].s) smap[data[i].s] = 1;
    }
    var sports = Object.keys(smap).sort();
    var ssel = document.getElementById('sport');
    // "All sports" first (empty value), then each sport alphabetically
    var so = document.createElement('option');
    so.value = ''; so.textContent = 'All sports';
    ssel.appendChild(so);
    for(var i=0;i<sports.length;i++){
      var o = document.createElement('option');
      o.value = sports[i]; o.textContent = sports[i];
      ssel.appendChild(o);
    }
    // Default to Ride if present, otherwise first sport, otherwise All sports
    if(smap['Ride']) ssel.value = 'Ride';
    else if(sports.length) ssel.value = sports[0];

    psel.addEventListener('change', function(){ applyFilter(psel.value); });
    ssel.addEventListener('change', function(){ applyFilter(psel.value); });
    applyFilter('w90');
    // Reveal the map only after the first fitBounds has positioned it, so the
    // initial world-view render + tile reload doesn't flash ("blink") on open.
    document.getElementById('map').classList.add('ready');
  })
  .catch(function(){
    progressDone();
    document.getElementById('map').classList.add('ready');
    var el = document.getElementById('msg');
    if(el) el.textContent = 'Failed to load heatmap.json';
  });
</script>
<div class="meta" style="text-align:center;padding:.5rem 0 1rem"><a href="https://github.com/raczeja/StatsServiceBook" target="_blank" rel="noopener">StatsServiceBook on GitHub</a></div>
</body>
</html>
HTML
