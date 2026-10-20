# strava-my-html-detail.sh — sourced by strava-my-activities.sh.
# Writes $WEB_DIR/activity.html (the per-activity detail page).
# A single page reused for every activity: reads ?id=<n> from the URL, fetches
# details/<id>.json, and renders cards, a Leaflet/OSM map, and per-km splits.
# Quoted heredoc: nothing shell-expanded.

# --- 6a. Render the per-activity detail page -------------------------------
log "html: writing activity.html..."
: "${STRAVA_MY_CLIMB_MIN_GAIN_RIDE:=25}"
: "${STRAVA_MY_CLIMB_MIN_GAIN_RUN:=5}"
: "${STRAVA_MY_CLIMB_MIN_GAIN_HIKE:=10}"
: "${STRAVA_MY_CLIMB_MIN_GAIN_WALK:=3}"
: "${STRAVA_MY_CLIMB_MIN_GAIN_OTHER:=10}"
: "${STRAVA_MY_CLIMB_MIN_DISTANCE:=100}"
: "${STRAVA_MY_CLIMB_MIN_GRADE_RIDE:=2}"
: "${STRAVA_MY_CLIMB_MIN_GRADE_RUN:=2}"
: "${STRAVA_MY_CLIMB_MIN_GRADE_HIKE:=2}"
: "${STRAVA_MY_CLIMB_MIN_GRADE_WALK:=1}"
: "${STRAVA_MY_CLIMB_MIN_GRADE_OTHER:=2}"
: "${STRAVA_MY_CLIMB_DESCENT_RESET:=30}"
for _climb_cfg in \
  STRAVA_MY_CLIMB_MIN_GAIN_RIDE STRAVA_MY_CLIMB_MIN_GAIN_RUN \
  STRAVA_MY_CLIMB_MIN_GAIN_HIKE STRAVA_MY_CLIMB_MIN_GAIN_WALK \
  STRAVA_MY_CLIMB_MIN_GAIN_OTHER STRAVA_MY_CLIMB_MIN_DISTANCE \
  STRAVA_MY_CLIMB_MIN_GRADE_RIDE STRAVA_MY_CLIMB_MIN_GRADE_RUN \
  STRAVA_MY_CLIMB_MIN_GRADE_HIKE STRAVA_MY_CLIMB_MIN_GRADE_WALK \
  STRAVA_MY_CLIMB_MIN_GRADE_OTHER STRAVA_MY_CLIMB_DESCENT_RESET; do
  eval "_climb_value=\${$_climb_cfg}"
  case "$_climb_value" in ''|*[!0-9]*) eval "$_climb_cfg=0" ;; esac
done
cat > "$WEB_DIR/activity.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t;</script>
<title>Activity detail</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN0YXRzU2VydmljZUJvb2siPgogIDxkZWZzPgogICAgPGNsaXBQYXRoIGlkPSJjbGlwIj4KICAgICAgPGNpcmNsZSBjeD0iMzIiIGN5PSIzMiIgcj0iMzAiLz4KICAgIDwvY2xpcFBhdGg+CiAgICA8bGluZWFyR3JhZGllbnQgaWQ9ImJnIiB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iMSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMyYTJhMmEiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMTExMTExIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KCiAgPCEtLSBCYWNrZ3JvdW5kIGNpcmNsZSAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMiIgZmlsbD0idXJsKCNiZykiLz4KCiAgPGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXApIj4KCiAgICA8IS0tIEFyZWEgZmlsbCB1bmRlciB0aGUgcm91dGUgbGluZSAtLT4KICAgIDxwb2x5Z29uCiAgICAgIHBvaW50cz0iNCw0NiAxMyw0NiAxOSwzMiAyNSw0MCAzMiwxOCAzOSwzMiA0NSwyNSA1MSwzMiA2MCwzMiA2MCw1NiA0LDU2IgogICAgICBmaWxsPSIjZmM0YzAyIiBmaWxsLW9wYWNpdHk9IjAuMTUiLz4KCiAgICA8IS0tIFJvdXRlIC8gZWxldmF0aW9uIHByb2ZpbGUg4oCUIHRoZSBjb3JlIGZlYXR1cmUgLS0+CiAgICA8cG9seWxpbmUKICAgICAgcG9pbnRzPSI0LDQ2IDEzLDQ2IDE5LDMyIDI1LDQwIDMyLDE4IDM5LDMyIDQ1LDI1IDUxLDMyIDYwLDMyIgogICAgICBmaWxsPSJub25lIgogICAgICBzdHJva2U9IiNmYzRjMDIiCiAgICAgIHN0cm9rZS13aWR0aD0iMy4yIgogICAgICBzdHJva2UtbGluZWNhcD0icm91bmQiCiAgICAgIHN0cm9rZS1saW5lam9pbj0icm91bmQiLz4KCiAgICA8IS0tIEdQUyAvIHN0YXJ0IGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjQiIGN5PSI0NiIgcj0iMi41IiBmaWxsPSIjZmM0YzAyIi8+CgogICAgPCEtLSBGaW5pc2ggLyBjdXJyZW50LXBvc2l0aW9uIGRvdCAtLT4KICAgIDxjaXJjbGUgY3g9IjYwIiBjeT0iMzIiIHI9IjIuNSIgZmlsbD0iI2ZjNGMwMiIvPgoKICA8L2c+CgogIDwhLS0gV2lGaSBzaWduYWwgYXJjcyDigJQgdG9wLXJpZ2h0LCByZXByZXNlbnRzIHRoZSByb3V0ZXIgLS0+CiAgPHBhdGggZD0iTTQzLDEzIFE1MCw3ICA1NywxMyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjQ1Ii8+CiAgPHBhdGggZD0iTTQ2LDE3IFE1MCwxMyA1NCwxNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjEuOCIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBvcGFjaXR5PSIwLjc1Ii8+CiAgPGNpcmNsZSBjeD0iNTAiIGN5PSIyMSIgcj0iMi4yIiBmaWxsPSIjZmM0YzAyIi8+CgogIDwhLS0gT3V0ZXIgcmluZyAtLT4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmM0YzAyIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLW9wYWNpdHk9IjAuMzUiLz4KPC9zdmc+Cg==" type="image/svg+xml">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
<style>
  :root{--bg:#fafafa;--surface:#fff;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--border:#eee;--border-2:#ccc;--row-alt:#f7f7f7;--accent:#fc4c02;--tooltip-bg:rgba(30,30,30,.93);--chart-grid:#e0e0e0;--map-spin-bg:#e8e8e8;--btn-bg:rgba(255,255,255,.9)}
  @media(prefers-color-scheme:dark){:root{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--border:#2a2a2a;--border-2:#3a3a3a;--row-alt:#1a1a1a;--tooltip-bg:rgba(10,10,10,.95);--chart-grid:#2e2e2e;--map-spin-bg:#252525;--btn-bg:rgba(42,42,42,.9)}}
  [data-theme=light]{--bg:#fafafa;--surface:#fff;--text:#222;--text-2:#444;--text-3:#666;--text-4:#888;--border:#eee;--border-2:#ccc;--row-alt:#f7f7f7;--accent:#fc4c02;--tooltip-bg:rgba(30,30,30,.93);--chart-grid:#e0e0e0;--map-spin-bg:#e8e8e8;--btn-bg:rgba(255,255,255,.9)}
  [data-theme=dark]{--bg:#121212;--surface:#1e1e1e;--text:#e0e0e0;--text-2:#b0b0b0;--text-3:#909090;--text-4:#6a6a6a;--border:#2a2a2a;--border-2:#3a3a3a;--row-alt:#1a1a1a;--tooltip-bg:rgba(10,10,10,.95);--chart-grid:#2e2e2e;--map-spin-bg:#252525;--btn-bg:rgba(42,42,42,.9)}
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1000px;padding:0 1rem;background:var(--bg);color:var(--text)}
  h1{margin:0 0 .25rem;font-size:1.5rem}
  a{color:var(--accent)}
  .crumbs{font-size:.85rem;margin:0 0 .75rem}
  .nav{margin:.25rem 0 1rem;display:flex;flex-wrap:wrap;gap:.4rem}.nav a{padding:.4rem .75rem;background:#fc4c02;color:#fff;text-decoration:none;border-radius:.4rem;font-size:.85rem;font-weight:600;flex:0 0 auto;text-align:center}.nav a:hover{background:#e34402}
  .sub{color:var(--text-3);font-size:.9rem;margin:.1rem 0 .5rem}
  .desc{white-space:pre-wrap;background:var(--surface);border:1px solid var(--border);padding:.5rem .75rem;border-radius:.4rem;margin:.5rem 0;font-size:.9rem;color:var(--text-2)}
  .links{font-size:.85rem;margin:.25rem 0 1rem}
  .links a{margin-right:1rem}
  .cards{display:flex;flex-wrap:wrap;gap:.6rem;margin:.5rem 0 1rem}
  .card{flex:1;min-width:120px;background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);padding:.5rem .75rem;border-radius:.4rem}
  .card .k{color:var(--text-4);font-size:.72rem;text-transform:uppercase;letter-spacing:.03em}
  .card .v{font-size:1.15rem;font-weight:600;font-variant-numeric:tabular-nums;margin-top:.15rem}
  .wx-src{display:inline-block;font-size:.6rem;font-weight:600;letter-spacing:.04em;padding:.1em .4em;border-radius:.25rem;vertical-align:middle;margin-left:.3em;text-transform:uppercase}
  .wx-arch{background:#dbeafe;color:#1d4ed8}
  .wx-fcst{background:#fef9c3;color:#854d0e}
  .wx-dev{background:#dcfce7;color:#166534}
  @media(prefers-color-scheme:dark){.wx-arch{background:#1e3a5f;color:#93c5fd}.wx-fcst{background:#3d2e00;color:#fde68a}.wx-dev{background:#14391a;color:#86efac}}
  [data-theme=dark] .wx-arch{background:#1e3a5f;color:#93c5fd}
  [data-theme=dark] .wx-fcst{background:#3d2e00;color:#fde68a}
  [data-theme=dark] .wx-dev{background:#14391a;color:#86efac}
  [data-theme=light] .wx-arch{background:#dbeafe;color:#1d4ed8}
  [data-theme=light] .wx-fcst{background:#fef9c3;color:#854d0e}
  [data-theme=light] .wx-dev{background:#dcfce7;color:#166534}
  #map{height:340px;border-radius:.4rem;box-shadow:0 1px 3px rgba(0,0,0,.08);margin:.5rem 0 1rem;background:var(--map-spin-bg)}
  .box{background:var(--surface);box-shadow:0 1px 3px rgba(0,0,0,.08);padding:.5rem .75rem;border-radius:.4rem;margin:.5rem 0 1rem}
  .box h3{margin:0 0 .35rem;font-size:.85rem;color:var(--text-2);font-weight:600}
  svg.splits{height:200px;display:block}
  .chart-scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
  .note{color:var(--text-3);font-size:.85rem;padding:.25rem 0}
  #err{color:#b00;padding:1rem 0}
  #chart-tip{display:none;position:fixed;background:var(--tooltip-bg);color:#fff;padding:.45rem .7rem;border-radius:.4rem;font-size:.8rem;pointer-events:none;z-index:1000;line-height:1.7;box-shadow:0 2px 8px rgba(0,0,0,.3)}
  #chart-tip strong{display:block;margin-bottom:.15rem;font-size:.85rem}
  #pbar{position:fixed;top:0;left:0;width:0;height:3px;background:var(--accent);z-index:9999;pointer-events:none}
  #map-box{position:relative}
  #map-spin{position:absolute;left:0;top:.5rem;right:0;bottom:1rem;display:flex;flex-direction:column;
    align-items:center;justify-content:center;background:var(--map-spin-bg);border-radius:.4rem;
    color:var(--text-3);font-size:.9rem;gap:.5rem;z-index:500;pointer-events:none}
  #map-spin-bar{width:120px;height:3px;background:var(--border-2);border-radius:2px;overflow:hidden}
  #map-spin-bar::after{content:'';display:block;height:100%;width:40%;background:var(--accent);
    animation:map-shimmer 1.2s ease-in-out infinite}
  @keyframes map-shimmer{0%{transform:translateX(-150%)}100%{transform:translateX(400%)}}
  #map-expand-btn{position:absolute;top:.4rem;right:.4rem;z-index:600;background:var(--btn-bg);border:1px solid var(--border-2);border-radius:.3rem;padding:.2rem .5rem;font-size:.78rem;cursor:pointer;line-height:1.5;box-shadow:0 1px 3px rgba(0,0,0,.15)}
  #map-expand-btn:hover{background:var(--surface);border-color:var(--text-4)}
  .climb-swatch{display:inline-block;width:1.2rem;height:.22rem;background:#1565c0;vertical-align:middle;margin-right:.2rem}
  .climb-nav{display:inline-flex;align-items:center;gap:.25rem;margin-left:.4rem;vertical-align:middle}
  .climb-nav button{cursor:pointer;border:1px solid var(--border-2,#ccc);background:var(--surface);color:inherit;border-radius:.25rem;line-height:1;padding:.05rem .35rem;font-size:.9rem;font-weight:700}
  .climb-nav button:hover{background:var(--border-2,#e5e5e5)}
  .climb-nav .climb-count{font-size:.7rem;font-variant-numeric:tabular-nums;color:var(--text-4)}
  #climb-prof-head{display:flex;align-items:center}
  #climb-prof-title{display:inline-flex;align-items:center;gap:.4rem}
  .climb-prof-stats{display:flex;flex-wrap:wrap;gap:.5rem .9rem;margin:.1rem 0 .55rem}
  .climb-prof-stats .cp-stat{flex:1 1 auto;min-width:72px;text-align:center}
  .climb-prof-stats .cp-v{font-size:1.1rem;font-weight:600;font-variant-numeric:tabular-nums}
  .climb-prof-stats .cp-k{color:var(--text-4);font-size:.62rem;text-transform:uppercase;letter-spacing:.03em;margin-top:.1rem}
  #svg-climbprof{display:block;width:100%;height:auto}
  .climb-prof-legend{display:flex;flex-wrap:wrap;gap:.35rem .9rem;margin-top:.5rem;font-size:.72rem;color:var(--text-3)}
  .climb-prof-legend span{display:inline-flex;align-items:center;gap:.3rem}
  .climb-prof-legend i{width:.85rem;height:.85rem;border-radius:2px;display:inline-block;flex-shrink:0}
  /* Climbing analysis + gradient distribution sit side-by-side on desktop, stack on mobile. */
  .climb-grade-row{display:flex;flex-wrap:wrap;gap:.5rem 1rem;align-items:flex-start}
  .climb-grade-row>.box{margin:.5rem 0 1rem}
  .climb-grade-row #climb-profile-box{flex:4 1 420px;min-width:0}
  .climb-grade-row #grade-dist-box{flex:1 1 200px;min-width:0}
  /* Cap the donut+legend cluster so it stays compact: side-by-side when the box is
     wide (gradient section shown alone), legend wrapping below the donut when the box
     is narrow (shown next to the climbing-analysis chart). */
  .grade-dist-wrap{display:flex;align-items:center;gap:.5rem .9rem;flex-wrap:wrap;max-width:430px}
  #svg-gradedist{width:150px;height:150px;flex:0 0 auto}
  .grade-dist-legend{display:flex;flex-direction:column;gap:.3rem;font-size:.76rem;color:var(--text-2);flex:1 1 150px;min-width:150px;max-width:230px}
  .grade-dist-legend .gd-row{display:flex;align-items:center;gap:.4rem}
  .grade-dist-legend i{width:.8rem;height:.8rem;border-radius:2px;flex-shrink:0}
  .grade-dist-legend .gd-lbl{flex:1 1 auto}
  .grade-dist-legend .gd-val{color:var(--text-3);font-variant-numeric:tabular-nums;white-space:nowrap}
  .route-endpoint-tip{background:rgba(255,255,255,.92);color:#111;border:1px solid rgba(0,0,0,.25);border-radius:.25rem;font-size:.65rem;font-weight:700;letter-spacing:.03em;text-transform:uppercase;padding:.05rem .3rem;box-shadow:0 1px 2px rgba(0,0,0,.2)}
  .route-endpoint-tip.leaflet-tooltip-top:before{border-top-color:rgba(0,0,0,.25)}
  #map-box.fs-map{position:fixed;inset:0;z-index:9000;margin:0;padding:0;background:#000;border-radius:0}
  #map-box.fs-map #map{height:100%;border-radius:0;margin:0;box-shadow:none}
  #map-box.fs-map #map-expand-btn{top:.6rem;right:.6rem}
  .hr-zone-table{width:100%;border-collapse:collapse;font-size:.85rem}
  .hr-zone-table td{padding:.25rem .4rem;vertical-align:middle}
  .hr-zone-table tr:nth-child(odd){background:var(--row-alt)}
  .hr-zone-bar{display:inline-block;height:8px;border-radius:3px;vertical-align:middle}
  #theme-tog{margin-left:auto;flex-shrink:0;background:none;border:none;font-size:1.2rem;cursor:pointer;line-height:1;padding:.2rem .4rem;border-radius:.3rem;color:var(--text-3)}
  #bike-row label{color:var(--text-3)!important}
  #bike-row select{border-color:var(--border-2)!important;background:var(--surface)!important;color:var(--text)!important}
  #bike-status{color:var(--text-4)!important}
  #hr-zone-box{overflow-x:auto;-webkit-overflow-scrolling:touch}
  @media(max-width:640px){body{margin:.75rem auto}#hdr{flex-wrap:wrap}h1{font-size:1.1rem}}
  .sec-handle{display:inline-block;cursor:grab;padding:.1rem .25rem;color:var(--text-3);font-size:.9rem;vertical-align:middle;user-select:none;margin-right:.25rem;opacity:.6;border-radius:.2rem}
  .sec-handle:hover{opacity:1;color:var(--accent)}
  .sec-handle:active{cursor:grabbing}
  .sec.sec-dragging{opacity:.4}
  .sec.sec-drag-over{outline:2px dashed var(--accent);outline-offset:2px}
  .sec-order-reset{font-size:.72rem;color:var(--text-3);background:none;border:1px solid var(--border-2);border-radius:.25rem;padding:.15rem .5rem;cursor:pointer;display:block;margin-left:auto;margin-bottom:.4rem}
  .sec-order-reset:hover{color:var(--accent);border-color:var(--accent)}
@media(pointer:coarse){.sec-handle,.sec-order-reset{display:none}}
</style>
<script>window.OFFLINE_CFG={rw:"#bike-sel"};</script>
<script src="offline.js"></script>
</head>
<body>
<div id="pbar"></div>
<div id="chart-tip"></div>
<div class="nav"><a href="index.html">&#8592; All activities</a> <a href="bike.html">🔧 Bike service</a> <a href="stats.html">📊 My Stats</a> <a href="heatmap.html">&#128506; Heatmap</a> <a href="data-quality.html">&#128203; Data completeness</a> <a id="leaderboard-link" href="../" style="display:none">🏆 Club leaderboard</a></div>
<div id="err"></div>
<div id="content" style="display:none">
  <div id="hdr" style="display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="36" height="36" aria-hidden="true"><defs><clipPath id="clip"><circle cx="32" cy="32" r="30"/></clipPath><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs><circle cx="32" cy="32" r="32" fill="url(#bg)"/><g clip-path="url(#clip)"><polygon points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32 60,56 4,56" fill="#fc4c02" fill-opacity="0.15"/><polyline points="4,46 13,46 19,32 25,40 32,18 39,32 45,25 51,32 60,32" fill="none" stroke="#fc4c02" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="46" r="2.5" fill="#fc4c02"/><circle cx="60" cy="32" r="2.5" fill="#fc4c02"/></g><path d="M43,13 Q50,7 57,13" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.45"/><path d="M46,17 Q50,13 54,17" fill="none" stroke="#fc4c02" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/><circle cx="50" cy="21" r="2.2" fill="#fc4c02"/><circle cx="32" cy="32" r="31" fill="none" stroke="#fc4c02" stroke-width="0.8" stroke-opacity="0.35"/></svg><h1 id="name" style="margin:0"></h1><button id="theme-tog">🌙</button></div>
  <div class="sub" id="sub"></div>
  <div class="desc" id="desc" style="display:none"></div>
  <div class="links" id="links"></div>
  <div id="bike-row" style="display:none;margin:.25rem 0 .75rem;font-size:.9rem"></div>
  <div id="sec-wrap">
  <div class="sec cards" data-sid="cards" id="cards"></div>
  <div class="sec" data-sid="map" id="map-box">
    <div id="map"></div>
    <div id="map-spin">Loading map…<div id="map-spin-bar"></div></div>
    <button id="map-expand-btn" onclick="toggleMapFullscreen()" title="Expand map">&#x26F6; Expand</button>
  </div>
  <div class="sec box" data-sid="elev" id="elev-box" style="display:none">
    <h3>Elevation profile</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-elev-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-elev" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="sec climb-grade-row" data-sid="climbprof">
    <div class="box" id="climb-profile-box" style="display:none">
      <h3 id="climb-prof-head"><span id="climb-prof-title">Climbing analysis</span></h3>
      <div class="climb-prof-stats" id="climb-prof-stats"></div>
      <svg id="svg-climbprof" preserveAspectRatio="xMidYMid meet"></svg>
      <div class="climb-prof-legend" id="climb-prof-legend"></div>
    </div>
    <div class="box" id="grade-dist-box" style="display:none">
      <h3>Gradient distribution</h3>
      <div class="grade-dist-wrap">
        <svg id="svg-gradedist" viewBox="0 0 150 150" preserveAspectRatio="xMidYMid meet"></svg>
        <div class="grade-dist-legend" id="grade-dist-legend"></div>
      </div>
    </div>
  </div>
  <div class="sec box" data-sid="hr" id="hr-box" style="display:none">
    <h3>Heart rate</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-hr-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-hr" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="sec box" data-sid="cad" id="cad-box" style="display:none">
    <h3>Cadence</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-cad-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-cad" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="sec box" data-sid="pwr" id="pwr-box" style="display:none">
    <h3>Power</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-pwr-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-pwr" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="sec box" data-sid="spd" id="spd-box" style="display:none">
    <h3>Speed</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-spd-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-spd" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="sec box" data-sid="temp" id="temp-box" style="display:none">
    <h3>Temperature</h3>
    <div class="note" id="temp-summary" style="margin-bottom:.4rem"></div>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-temp-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll" style="flex:1;min-width:0"><svg class="splits" id="svg-temp" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
  </div>
  <div class="sec box" data-sid="hrzone" id="hr-zone-box" style="display:none">
    <h3 id="hr-zone-title">Heart rate zones</h3>
    <div id="hr-zone-content"></div>
  </div>
  <div class="sec box" data-sid="hrmax" id="hr-maxavg-box" style="display:none">
    <h3>Maximum average heart rate</h3>
    <div style="display:flex;align-items:flex-start">
      <svg id="svg-hrmaxavg-yaxis" style="flex-shrink:0"></svg>
      <div class="chart-scroll chart-scroll-indep" style="flex:1;min-width:0"><svg id="svg-hrmaxavg" preserveAspectRatio="xMidYMid meet"></svg></div>
    </div>
    <div class="note" style="margin-top:.4rem">Best average heart rate sustained over each window, across the whole activity.</div>
  </div>
  <div class="sec box" data-sid="splits" id="splits-box">
    <h3 id="splits-title">Splits</h3>
    <div class="chart-scroll"><svg class="splits" id="svg-splits" preserveAspectRatio="xMidYMid meet"></svg></div>
  </div>
  </div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
"use strict";
fetch('../',{method:'HEAD'}).then(function(r){if(r.ok){var el=document.getElementById('leaderboard-link');if(el)el.style.display='';}}).catch(function(){});
var _pbar=null,_pbarTick=null,_pbarPct=0,_pbarT0=0;
var leafletMap=null,leafletLine=null;
// Climb switcher state: _climbs is track-ordered; _climbIdx is the one shown in the
// card; _climbMap/_climbLines (idx → polyline) let the ‹ › arrows focus the map.
var _climbs=[],_climbIdx=0,_climbBiggestIdx=0,_climbMap=null,_climbLines=null;
// Full track (one entry per GPX point) + cumulative metres, kept so the ‹ › switcher
// can re-slice and re-draw the per-climb profile chart. climb.start/end index into these.
var _climbTrackPts=[],_climbCumDist=[];
// Leaflet layer holding the gradient-coloured overlay for the currently-selected
// climb (rebuilt by the ‹ › switcher). Other climbs stay plain blue.
var _climbGradLayer=null;
// Gradient colour bands for the per-climb profile (steepest first). Each segment of the
// climb is filled with the colour of its local gradient — HC steepest, Cat4 shallowest.
var CLIMB_GRADE_BANDS=[
  {min:12,color:"#e53935",label:"HC (>12%)"},
  {min:9, color:"#fb8c00",label:"Cat1 (9–12%)"},
  {min:6, color:"#fdd835",label:"Cat2 (6–9%)"},
  {min:3, color:"#43a047",label:"Cat3 (3–6%)"},
  {min:-1e9,color:"#29b6f6",label:"Cat4 (0–3%)"}
];
function climbGradeColor(pct){
  for(var i=0;i<CLIMB_GRADE_BANDS.length;i++) if(pct>=CLIMB_GRADE_BANDS[i].min) return CLIMB_GRADE_BANDS[i].color;
  return CLIMB_GRADE_BANDS[CLIMB_GRADE_BANDS.length-1].color;
}
// Whole-activity gradient-distribution bands (steepest first) for the donut chart.
// Same colours/thresholds as the per-climb bands but with flat/descending terrain
// split out as its own "Other" slice (the climb chart lumps it into Cat4).
var GRADE_DIST_BANDS=[
  {min:12, color:"#e53935", label:"HC (>12%)"},
  {min:9,  color:"#fb8c00", label:"Cat1 (9–12%)"},
  {min:6,  color:"#fdd835", label:"Cat2 (6–9%)"},
  {min:3,  color:"#43a047", label:"Cat3 (3–6%)"},
  {min:0,  color:"#29b6f6", label:"Cat4 (0–3%)"},
  {min:-1e9,color:"#9e9e9e",label:"Other (<0%)"}
];
function gradeBandIndex(pct){
  for(var i=0;i<GRADE_DIST_BANDS.length;i++) if(pct>=GRADE_DIST_BANDS[i].min) return i;
  return GRADE_DIST_BANDS.length-1;
}
// Per-segment gradient (%) using coarse fixed-distance blocks (~CLIMB_GRAD_BLOCK_M
// metres each), so the colour bands come out as a few solid contiguous blocks like a
// bike-computer climb view — not a thin per-point barcode. distKm/ele are the climb's
// own arrays; returns an array of length ele.length-1 (one gradient per segment).
var CLIMB_GRAD_BLOCK_M=200;
function climbBandGrads(distKm, ele){
  var out=[], n=ele.length, i;
  if(n<2) return out;
  var d0=distKm[0]*1000, totalM=distKm[n-1]*1000-d0;
  var blockM=Math.max(120, totalM/12);
  if(CLIMB_GRAD_BLOCK_M>0 && totalM/CLIMB_GRAD_BLOCK_M>=2) blockM=CLIMB_GRAD_BLOCK_M;
  var first={}, last={}, blk=[];
  for(i=0;i<n;i++){
    var b=Math.floor((distKm[i]*1000-d0)/blockM);
    blk.push(b);
    if(first[b]===undefined) first[b]=i;
    last[b]=i;
  }
  var g={};
  for(var k in first){ if(!first.hasOwnProperty(k)) continue;
    var a=first[k], z=last[k], sp=distKm[z]*1000-distKm[a]*1000;
    g[k]= sp>0 ? (ele[z]-ele[a])/sp*100 : 0;
  }
  for(i=0;i<n-1;i++) out.push(g[blk[i]]);
  return out;
}
var CLIMB_THRESHOLDS = {"gain":{"Ride":25,"Run":5,"Hike":10,"Walk":3,"Other":10},"minDistance":100};
var CLIMB_MIN_GRADE = {"gRide":3,"gRun":2,"gHike":2,"gWalk":1,"gOther":2};
var CLIMB_DESCENT_RESET = 30;
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
function hideMapSpin(){
  var s=document.getElementById("map-spin");
  if(s) s.style.display="none";
}

function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g, function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }
function fmtKm(m){ var s=(m/1000).toFixed(2); return s.replace(/\B(?=(\d{3})+(?!\d))/g," "); }
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

// --- Synchronized scrolling across all .chart-scroll containers ------------
// Scroll events do not bubble, so use capture phase to intercept them all.
// Containers also marked .chart-scroll-indep (e.g. the max-average-HR curve,
// which uses a duration x-axis) are excluded — they share no common scale with
// the distance-based charts, so syncing them would be meaningless.
var _scrollSyncing = false;
document.addEventListener("scroll", function(e) {
  if (_scrollSyncing) return;
  var src = e.target;
  if (!src || !src.classList || !src.classList.contains("chart-scroll")) return;
  if (src.classList.contains("chart-scroll-indep")) return;
  var all = document.querySelectorAll(".chart-scroll");
  var maxScroll = src.scrollWidth - src.clientWidth;
  if (maxScroll <= 0) return;
  var ratio = src.scrollLeft / maxScroll;
  _scrollSyncing = true;
  for (var _i = 0; _i < all.length; _i++) {
    if (all[_i] === src) continue;
    if (all[_i].classList.contains("chart-scroll-indep")) continue;
    var t = all[_i], tm = t.scrollWidth - t.clientWidth;
    if (tm > 0) t.scrollLeft = Math.round(ratio * tm);
  }
  _scrollSyncing = false;
}, true);

// --- Google encoded-polyline decoder ---------------------------------------
// Returns an array of [lat, lng] pairs. Standard precision-5 algorithm.
// Direction chevrons along the route (like Strava). Placed at a fixed on-screen
// spacing and rebuilt on zoom, so density stays constant at every zoom level.
function addDirectionArrows(map, pts){
  if (!pts || pts.length < 2) return;
  var group = L.layerGroup().addTo(map);
  var SPACING = 90;
  function rebuild(){
    group.clearLayers();
    var z = map.getZoom(), prev = map.project(pts[0], z), acc = SPACING / 2, i;
    for (i = 1; i < pts.length; i++) {
      var cur = map.project(pts[i], z), dx = cur.x - prev.x, dy = cur.y - prev.y;
      var seg = Math.sqrt(dx*dx + dy*dy);
      if (seg < 0.5) continue;
      var ang = Math.atan2(dy, dx) * 180 / Math.PI, pos = 0;
      while (acc + (seg - pos) >= SPACING) {
        pos += SPACING - acc; acc = 0;
        var f = pos / seg;
        var ll = map.unproject(L.point(prev.x + dx * f, prev.y + dy * f), z);
        L.marker(ll, { interactive: false, keyboard: false, icon: L.divIcon({
          className: "", iconSize: [20, 20], iconAnchor: [10, 10],
          html: '<svg width="20" height="20" viewBox="0 0 20 20" style="transform:rotate(' + ang.toFixed(1) + 'deg);display:block;pointer-events:none">'
              + '<path d="M4 3 L16 10 L4 17 L8 10 Z" fill="#fc4c02" stroke="#fff" stroke-width="2" stroke-linejoin="round"/></svg>'
        }) }).addTo(group);
      }
      acc += seg - pos;
      prev = cur;
    }
  }
  map.on("zoomend", rebuild);
  rebuild();
}

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

function fillDetailFromActivity(d, act){
  if (!act) return d;
  var fields = [
    "suffer_score", "average_heartrate", "max_heartrate",
    "average_temp", "temp_source", "apparent_temp", "wind_speed",
    "wind_dir", "weathercode", "precipitation", "max_single_climb"
  ];
  fields.forEach(function(key){
    if (d[key] == null && act[key] != null) d[key] = act[key];
  });
  return d;
}

function card(k, v){ return '<div class="card"><div class="k">'+esc(k)+'</div><div class="v">'+v+'</div></div>'; }
// Same card, with a hover explanation (native tooltip) for cryptic metrics.
function cardTip(k, v, tip){ return '<div class="card" title="'+esc(tip)+'"><div class="k">'+esc(k)+'</div><div class="v">'+v+'</div></div>'; }

// gain · avg-grade · distance for one climb.
function fmtClimbText(c){
  var t = c.gain + " m";
  if (c.distance != null && c.distance > 0) {
    var distance = c.distance < 1000
      ? Math.round(c.distance) + " m"
      : (c.distance / 1000).toFixed(2) + " km";
    t += " · " + (c.gain / c.distance * 100).toFixed(1) + "% avg · " + distance;
  }
  return t;
}

// Draw the climb card for the currently-selected climb (_climbs[_climbIdx]). With
// more than one climb the title carries ‹ N/M › arrows to flip through them; a
// single climb keeps the plain "Longest climb" title (and no arrows).
function renderClimbCardFace(){
  var cardEl = document.getElementById("longest-climb-card");
  if (!cardEl || !_climbs.length) return;
  var kEl = cardEl.querySelector(".k");
  var vEl = cardEl.querySelector(".v");
  var c = _climbs[_climbIdx];
  var multi = _climbs.length > 1;
  if (kEl) {
    var isLongest = multi && c.idx === _climbBiggestIdx;
    var title = multi ? ("Climb " + c.idx + (isLongest ? " · longest" : "")) : "Longest climb";
    var k = '<span class="climb-swatch" aria-hidden="true"></span>' + title;
    if (multi) {
      k += '<span class="climb-nav">'
        + '<button type="button" class="climb-prev" aria-label="Previous climb" title="Previous climb">‹</button>'
        + '<span class="climb-count">' + (_climbIdx + 1) + '/' + _climbs.length + '</span>'
        + '<button type="button" class="climb-next" aria-label="Next climb" title="Next climb">›</button>'
        + '</span>';
    }
    kEl.innerHTML = k;
    if (multi) {
      kEl.querySelector(".climb-prev").onclick = function(){ showClimb(_climbIdx - 1); };
      kEl.querySelector(".climb-next").onclick = function(){ showClimb(_climbIdx + 1); };
    }
  }
  if (vEl) vEl.textContent = fmtClimbText(c);
  cardEl.style.display = "";
}

// Switch the card to climb index i (wraps around) and, when the map is present,
// zoom to that climb and thicken its line so card and map stay in sync.
function showClimb(i){
  if (!_climbs.length) return;
  var n = _climbs.length;
  _climbIdx = ((i % n) + n) % n;
  renderClimbCardFace();
  renderClimbProfile(_climbs[_climbIdx]);
  renderClimbGradientOnMap(_climbs[_climbIdx]);
  if (_climbMap && _climbLines) {
    var sel = _climbLines[_climbs[_climbIdx].idx];
    for (var key in _climbLines) {
      if (_climbLines.hasOwnProperty(key))
        _climbLines[key].setStyle({ weight: _climbLines[key] === sel ? 8 : 5 });
    }
    if (sel) { try { _climbMap.fitBounds(sel.getBounds(), { padding: [40, 40] }); } catch(_){} }
  }
}

// Entry point from the GPX consumers. `climbs` is findClimbs() output (sorted by
// gain desc) or a single-element max_single_climb fallback. `trackPts` (optional)
// is the full {lat,lon,ele} track that climb.start/end index into — stored so the
// per-climb profile chart can re-slice it. Stores climbs in track order for the
// switcher, defaulting the view to the biggest ("longest") climb.
function updateLongestClimbCard(climbs, trackPts){
  var cardEl = document.getElementById("longest-climb-card");
  if (!cardEl) return;
  // Stash the track + cumulative-distance array for the climb-profile chart.
  _climbTrackPts = (trackPts && trackPts.length) ? trackPts : [];
  _climbCumDist = [];
  if (_climbTrackPts.length) {
    _climbCumDist.push(0);
    for (var q = 1; q < _climbTrackPts.length; q++)
      _climbCumDist.push(_climbCumDist[q - 1] + haversineM(
        _climbTrackPts[q - 1].lat, _climbTrackPts[q - 1].lon,
        _climbTrackPts[q].lat, _climbTrackPts[q].lon));
  }
  // Whole-activity gradient distribution from the track (independent of climbs).
  renderGradeDist(gradeBucketsFromTrack(_climbTrackPts, _climbCumDist));
  if (!climbs || !climbs.length) {
    _climbs = [];
    cardEl.style.display = "none";
    renderClimbProfile(null);
    return;
  }
  var biggest = climbs[0];
  for (var b = 1; b < climbs.length; b++) if (climbs[b].gain > biggest.gain) biggest = climbs[b];
  _climbBiggestIdx = biggest.idx;
  _climbs = climbs.slice().sort(function(a, bb){ return (a.idx || 0) - (bb.idx || 0); });
  _climbIdx = 0;
  for (var p = 0; p < _climbs.length; p++) if (_climbs[p] === biggest) { _climbIdx = p; break; }
  renderClimbCardFace();
  renderClimbProfile(_climbs[_climbIdx]);
}

// Whole-activity gradient distribution: how much distance was spent in each
// gradient band (HC…Cat4 + flat/descending "Other"). Fed from the GPX track
// (updateLongestClimbCard) or, for Strava-API activities, from the per-km splits
// (renderSplits). `buckets` is metres-per-band (GRADE_DIST_BANDS order) or null.
function renderGradeDist(buckets){
  var box = document.getElementById("grade-dist-box");
  var svg = document.getElementById("svg-gradedist");
  var leg = document.getElementById("grade-dist-legend");
  if (!box || !svg || !leg) return;
  var total = 0, i;
  if (buckets) for (i = 0; i < buckets.length; i++) total += buckets[i] || 0;
  if (!buckets || total <= 0) { box.style.display = "none"; return; }
  // Donut via stroke-dasharray on concentric arcs, starting at 12 o'clock.
  var cx = 75, cy = 75, r = 52, sw = 22, C = 2 * Math.PI * r, off = 0, parts = "";
  for (i = 0; i < GRADE_DIST_BANDS.length; i++) {
    var frac = (buckets[i] || 0) / total;
    if (frac <= 0) continue;
    var dash = frac * C, gap = C - dash;
    parts += '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" fill="none" stroke="'
      + GRADE_DIST_BANDS[i].color + '" stroke-width="' + sw + '" stroke-dasharray="'
      + dash.toFixed(2) + ' ' + gap.toFixed(2) + '" stroke-dashoffset="' + (-off * C).toFixed(2)
      + '" transform="rotate(-90 ' + cx + ' ' + cy + ')"><title>' + GRADE_DIST_BANDS[i].label
      + ': ' + (buckets[i] / 1000).toFixed(1) + ' km</title></circle>';
    off += frac;
  }
  parts += '<text x="' + cx + '" y="' + (cy - 2) + '" text-anchor="middle" font-size="17" font-weight="600" fill="currentColor">'
    + (total / 1000).toFixed(1) + '</text>';
  parts += '<text x="' + cx + '" y="' + (cy + 13) + '" text-anchor="middle" font-size="9" fill="var(--text-4)">km total</text>';
  svg.innerHTML = parts;
  var lh = "";
  for (i = 0; i < GRADE_DIST_BANDS.length; i++) {
    if ((buckets[i] || 0) <= 0) continue;
    lh += '<div class="gd-row"><i style="background:' + GRADE_DIST_BANDS[i].color + '"></i>'
      + '<span class="gd-lbl">' + GRADE_DIST_BANDS[i].label + '</span>'
      + '<span class="gd-val">' + (buckets[i] / 1000).toFixed(1) + ' km</span></div>';
  }
  leg.innerHTML = lh;
  box.style.display = "";
}

// Bucket distance by gradient from the full GPX track. Elevation is smoothed over
// ~100 m blocks so the bands reflect real terrain, not per-point GPS noise.
function gradeBucketsFromTrack(pts, cum){
  if (!pts || !cum || pts.length !== cum.length) return null;
  var E = [], D = [], i;
  for (i = 0; i < pts.length; i++) {
    if (pts[i].ele != null && isFinite(pts[i].ele)) { E.push(pts[i].ele); D.push(cum[i]); }
  }
  if (E.length < 2 || (D[D.length - 1] - D[0]) <= 0) return null;
  var buckets = [], BLOCK = 100, segStart = 0, total = 0;
  for (i = 0; i < GRADE_DIST_BANDS.length; i++) buckets.push(0);
  for (i = 1; i < E.length; i++) {
    if ((D[i] - D[segStart]) >= BLOCK || i === E.length - 1) {
      var d = D[i] - D[segStart];
      if (d > 0) { buckets[gradeBandIndex((E[i] - E[segStart]) / d * 100)] += d; total += d; }
      segStart = i;
    }
  }
  return total > 0 ? buckets : null;
}

// Bucket distance by gradient from per-km Strava splits (distance + elevation_difference).
function gradeBucketsFromSplits(splits){
  if (!splits || !splits.length) return null;
  var buckets = [], total = 0, hasElev = false, i;
  for (i = 0; i < GRADE_DIST_BANDS.length; i++) buckets.push(0);
  for (i = 0; i < splits.length; i++) {
    var d = splits[i].distance || 0, ed = splits[i].elevation_difference;
    if (d <= 0 || ed == null) continue;
    hasElev = true;
    buckets[gradeBandIndex(ed / d * 100)] += d; total += d;
  }
  return (hasElev && total > 0) ? buckets : null;
}

// Per-climb elevation profile, coloured by gradient (the Magene-style "Climbing
// analysis" chart). X-axis runs 0 → the climb's own distance in km; the fill of
// each segment is its local gradient band. Driven by the same ‹ › switcher as the
// climb card, so flipping climbs redraws this chart too. Hidden when the selected
// climb has no track indices (e.g. the max_single_climb fallback with no GPX).
function renderClimbProfile(climb){
  var box = document.getElementById("climb-profile-box");
  if (!box) return;
  if (!climb || climb.start == null || climb.end == null || climb.end <= climb.start
      || !_climbTrackPts.length || _climbCumDist.length !== _climbTrackPts.length) {
    box.style.display = "none";
    return;
  }
  // Slice the climb; carry elevation forward across the occasional null sample.
  var i, j, s = climb.start, e = climb.end, startCum = _climbCumDist[s];
  var dist = [], ele = [], lastE = null;
  for (i = s; i <= e; i++) {
    var ev = _climbTrackPts[i].ele;
    if (ev == null || !isFinite(ev)) ev = lastE; else lastE = ev;
    if (ev == null) continue;                 // skip leading nulls
    dist.push((_climbCumDist[i] - startCum) / 1000);   // km from climb start
    ele.push(ev);
  }
  if (ele.length < 2) { box.style.display = "none"; return; }
  // Smooth elevation (±2 points) to tame GPS jitter before computing gradients.
  var sm = [], WIN = 2, a2, b2, sum, cnt;
  for (i = 0; i < ele.length; i++) {
    a2 = Math.max(0, i - WIN); b2 = Math.min(ele.length - 1, i + WIN); sum = 0; cnt = 0;
    for (j = a2; j <= b2; j++) { sum += ele[j]; cnt++; }
    sm.push(sum / cnt);
  }
  ele = sm;

  var totalKm = dist[dist.length - 1] || 0, totalM = totalKm * 1000;
  var gain = climb.gain || Math.max(0, ele[ele.length - 1] - ele[0]);
  var avgGrade = totalM > 0 ? (gain / totalM * 100) : 0;
  // Coarse per-block gradients drive both the band colours and the Max-gradient stat,
  // so the number matches the steepest band actually shown (not a jittery point spike).
  var grads = climbBandGrads(dist, ele);
  function segGrad(k) { return grads[k < grads.length ? k : grads.length - 1] || 0; }
  var maxGrade = 0;
  for (i = 0; i < grads.length; i++) if (grads[i] > maxGrade) maxGrade = grads[i];

  // --- stat tiles -----------------------------------------------------------
  var startKm = startCum / 1000;
  function stat(v, k) { return '<div class="cp-stat"><div class="cp-v">' + v + '</div><div class="cp-k">' + esc(k) + '</div></div>'; }
  var distTxt = totalKm < 1 ? Math.round(totalM) + " m" : totalKm.toFixed(2) + " km";
  var statsHtml = stat(avgGrade.toFixed(1) + "%", "Avg gradient")
    + stat(maxGrade.toFixed(1) + "%", "Max gradient")
    + stat(distTxt, "Climb distance")
    + stat(Math.round(gain) + " m", "Accumulated climb")
    + stat(startKm.toFixed(2) + " km", "Route position");
  document.getElementById("climb-prof-stats").innerHTML = statsHtml;

  // --- SVG geometry ---------------------------------------------------------
  var H = 220, YAX_W = 48, padR = 12, padT = 14, labelH = 20;
  var cw = box.clientWidth || 900;
  var W = Math.max(320, Math.round(cw) - 24);
  var plotL = YAX_W, plotR = W - padR, plotW = plotR - plotL;
  var chTop = padT, chBot = H - labelH, chH = chBot - chTop;
  var minE = ele[0], maxE = ele[0];
  for (i = 0; i < ele.length; i++) { if (ele[i] < minE) minE = ele[i]; if (ele[i] > maxE) maxE = ele[i]; }
  var eRange = (maxE - minE) || 1;
  var yBase = minE, ySpan = eRange * 1.08;      // 8% headroom above the summit
  function xOf(km) { return plotL + (totalKm > 0 ? km / totalKm : 0) * plotW; }
  function yOf(m)  { return chBot - ((m - yBase) / ySpan) * chH; }

  // Gradient-coloured area: one filled quad per segment.
  var segs = "", chBotF = chBot.toFixed(1);
  for (i = 0; i < ele.length - 1; i++) {
    var x1 = xOf(dist[i]).toFixed(1), x2 = xOf(dist[i + 1]).toFixed(1);
    var y1 = yOf(ele[i]).toFixed(1),  y2 = yOf(ele[i + 1]).toFixed(1);
    var col = climbGradeColor(segGrad(i));
    segs += '<polygon points="' + x1 + ',' + chBotF + ' ' + x1 + ',' + y1 + ' '
      + x2 + ',' + y2 + ' ' + x2 + ',' + chBotF + '" fill="' + col + '" stroke="' + col + '" stroke-width="0.6"/>';
  }
  // Crisp top line over the coloured area.
  var line = "";
  for (i = 0; i < ele.length; i++) line += (i ? "L" : "M") + xOf(dist[i]).toFixed(1) + "," + yOf(ele[i]).toFixed(1);
  var top = '<path d="' + line + '" fill="none" stroke="var(--text-2)" stroke-width="1.3" stroke-linejoin="round" opacity="0.7"/>';

  // Y grid + altitude labels (min / mid / max).
  var grid = "", yax = "", ticks = [minE, (minE + maxE) / 2, maxE];
  for (i = 0; i < ticks.length; i++) {
    var gy = yOf(ticks[i]).toFixed(1);
    grid += '<line x1="' + plotL + '" y1="' + gy + '" x2="' + plotR + '" y2="' + gy + '" stroke="var(--chart-grid)" stroke-width="1"/>';
    yax += '<text x="' + (YAX_W - 6) + '" y="' + (parseFloat(gy) + 4) + '" text-anchor="end" font-size="11" fill="var(--text-3)">' + Math.round(ticks[i]) + ' m</text>';
  }
  // X ticks: 0 … climb distance (km).
  var xt = "", NT = totalKm < 0.6 ? 2 : (totalKm < 2 ? 4 : 5), dec = totalKm < 2 ? 2 : 1;
  for (i = 0; i <= NT; i++) {
    var km = totalKm * i / NT, lx = xOf(km).toFixed(1);
    xt += '<text x="' + lx + '" y="' + (H - 4) + '" text-anchor="' + (i === 0 ? "start" : i === NT ? "end" : "middle") + '" font-size="11" fill="var(--text-3)">' + km.toFixed(dec) + ' km</text>';
  }

  // Hover tooltips (reuse the shared line-chart hover machinery).
  var tips = [];
  for (i = 0; i < ele.length; i++) {
    tips.push({ x: parseFloat(xOf(dist[i]).toFixed(1)),
      html: '<strong>' + dist[i].toFixed(2) + ' km</strong>' + Math.round(ele[i]) + ' m · ' + segGrad(i).toFixed(1) + '%' });
  }
  LINE_TIPS["svg-climbprof"] = tips;
  var overlay = '<rect x="' + plotL + '" y="0" width="' + plotW + '" height="' + H + '"'
    + ' fill="transparent" style="cursor:crosshair"'
    + ' onmousemove="lineChartHover(event,\'svg-climbprof\')"'
    + ' onmouseout="hideTip()"'
    + ' ontouchmove="lineChartHover({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},\'svg-climbprof\')"'
    + ' ontouchend="hideTip()"/>';

  var svg = document.getElementById("svg-climbprof");
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);
  svg.innerHTML = grid + segs + top + yax + xt + overlay;

  // Legend (only the bands that appear would be nice, but showing all keeps it stable).
  var leg = "";
  for (i = 0; i < CLIMB_GRADE_BANDS.length; i++)
    leg += '<span><i style="background:' + CLIMB_GRADE_BANDS[i].color + '"></i>' + esc(CLIMB_GRADE_BANDS[i].label) + '</span>';
  document.getElementById("climb-prof-legend").innerHTML = leg;

  // Header title + ‹ N/M › switcher (mirrors the climb card).
  var titleEl = document.getElementById("climb-prof-title");
  if (titleEl) {
    var multi = _climbs.length > 1;
    var isLongest = multi && climb.idx === _climbBiggestIdx;
    var t = multi ? ("Climbing analysis · climb " + climb.idx + (isLongest ? " (longest)" : "")) : "Climbing analysis";
    var html = '<span>' + esc(t) + '</span>';
    if (multi) {
      html += '<span class="climb-nav">'
        + '<button type="button" class="cp-prev" aria-label="Previous climb" title="Previous climb">‹</button>'
        + '<span class="climb-count">' + (_climbIdx + 1) + '/' + _climbs.length + '</span>'
        + '<button type="button" class="cp-next" aria-label="Next climb" title="Next climb">›</button>'
        + '</span>';
    }
    titleEl.innerHTML = html;
    if (multi) {
      titleEl.querySelector(".cp-prev").onclick = function(){ showClimb(_climbIdx - 1); };
      titleEl.querySelector(".cp-next").onclick = function(){ showClimb(_climbIdx + 1); };
    }
  }
  box.style.display = "";
}

// Overlay the currently-selected climb on the map, coloured by gradient band (same
// palette as the Climbing-analysis chart). A continuous dark casing underneath keeps
// the thin colour bands legible over map tiles. Other climbs stay plain blue, so the
// resting "blue = climb" convention holds and only the active climb lights up.
// Rebuilt by showClimb() so the ‹ › switcher drives it in step with the chart.
function renderClimbGradientOnMap(climb){
  if (!_climbMap || typeof L === "undefined") return;
  if (_climbGradLayer) { try { _climbMap.removeLayer(_climbGradLayer); } catch(_){} _climbGradLayer = null; }
  if (!climb || climb.start == null || climb.end == null || climb.end <= climb.start) return;
  if (!_climbTrackPts.length || _climbCumDist.length !== _climbTrackPts.length) return;
  // Build the climb slice: lat/lon + cumulative metres + elevation (carried across nulls).
  var i, j, s = climb.start, e = climb.end;
  var lat = [], lon = [], cum = [], ele = [], lastE = null;
  for (i = s; i <= e; i++) {
    var p = _climbTrackPts[i];
    if (p.lat == null || !isFinite(p.lat)) continue;
    var ev = p.ele;
    if (ev == null || !isFinite(ev)) ev = lastE; else lastE = ev;
    if (ev == null) continue;
    lat.push(p.lat); lon.push(p.lon); cum.push(_climbCumDist[i]); ele.push(ev);
  }
  if (lat.length < 2) return;
  // Smooth elevation (±2) so the gradient bands match the chart and resist jitter.
  var sm = [], WIN = 2, a2, b2, sum, cnt;
  for (i = 0; i < ele.length; i++) {
    a2 = Math.max(0, i - WIN); b2 = Math.min(ele.length - 1, i + WIN); sum = 0; cnt = 0;
    for (j = a2; j <= b2; j++) { sum += ele[j]; cnt++; }
    sm.push(sum / cnt);
  }
  ele = sm;
  // Same coarse block gradients as the chart, so map and chart colours agree.
  var distKm = [];
  for (i = 0; i < cum.length; i++) distKm.push(cum[i] / 1000);
  var grads = climbBandGrads(distKm, ele);
  var segCols = [];
  for (i = 0; i < lat.length - 1; i++)
    segCols.push(climbGradeColor(grads[i < grads.length ? i : grads.length - 1] || 0));

  var layers = [], all = [];
  for (i = 0; i < lat.length; i++) all.push([lat[i], lon[i]]);
  // One continuous dark casing for the whole climb, then one coloured polyline per
  // contiguous same-colour run (keeps the layer count low and the bands solid).
  var gp = _climbMap.getPane("climbPane") ? "climbPane" : "overlayPane";
  layers.push(L.polyline(all, { pane: gp, color: "#1a1a1a", weight: 9, opacity: 0.9, lineJoin: "round", lineCap: "round" }));
  var r = 0;
  while (r < segCols.length) {
    var rc = segCols[r], rEnd = r;
    while (rEnd + 1 < segCols.length && segCols[rEnd + 1] === rc) rEnd++;
    var runPts = [];
    for (j = r; j <= rEnd + 1; j++) runPts.push([lat[j], lon[j]]);
    layers.push(L.polyline(runPts, { pane: gp, color: rc, weight: 5, opacity: 1, lineJoin: "round", lineCap: "round" }));
    r = rEnd + 1;
  }
  _climbGradLayer = L.layerGroup(layers).addTo(_climbMap);
}

function renderCards(d){
  var sport = d.sport_type || d.type || "";
  var html = "";
  html += card("Distance", fmtKm(d.distance || 0) + " km");
  // Moving time as the headline, with total (elapsed) time, stopped time and the
  // moving-% folded into a small sub-line underneath. This card plus "Longest climb"
  // are the two full-width cards, so both are appended at the very end of the grid.
  var _mtMain = fmtTime(d.moving_time || 0);
  var movingCard;
  if (d.elapsed_time && d.elapsed_time !== d.moving_time) {
    var movePct = d.elapsed_time > 0 ? Math.round(100 * d.moving_time / d.elapsed_time) : null;
    var stopped = (d.elapsed_time || 0) - (d.moving_time || 0);
    var _mtSub = fmtTime(d.elapsed_time) + ' total'
      + (stopped >= 60 ? ' · ' + fmtTime(stopped) + ' stopped' : '')
      + (movePct != null ? ' · ' + movePct + '% moving' : '');
    movingCard = card("Moving time", _mtMain +
      '<div style="color:var(--text-4);font-size:.8rem;font-weight:400;margin-top:3px">' + _mtSub + '</div>');
  } else {
    // No elapsed time in the record (e.g. HealthSync) — the GPX fill below derives
    // total/stopped/% from the track's first→last timestamps and shows it here.
    movingCard = '<div class="card"><div class="k">Moving time</div><div class="v">' + _mtMain
      + '<div id="gpx-elapsed-sub" style="display:none;color:var(--text-4);font-size:.8rem;font-weight:400;margin-top:3px"></div></div></div>';
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
  } else {
    // No max speed in the record (e.g. HealthSync) — derive it from the GPX track below.
    html += '<div class="card" id="gpx-maxspeed-card" style="display:none"><div class="k">'
      + (isFoot(sport) ? 'Best pace' : 'Max speed') + '</div><div class="v"></div></div>';
  }
  if (d.total_elevation_gain) html += card("Elevation", Math.round(d.total_elevation_gain) + " m");
  // Total descent — downhill metres lost. Not carried in the record, so always
  // derived from the GPX track (filled by renderGpxCharts below).
  html += '<div class="card" id="gpx-descent-card" style="display:none" title="Total elevation lost, from the GPX track."><div class="k">Descent</div><div class="v"></div></div>';
  // Altitude range (lowest → highest point) when both bounds are known.
  if (d.elev_high != null && d.elev_low != null && d.elev_high > d.elev_low)
    html += cardTip("Altitude", Math.round(d.elev_low) + '–' + Math.round(d.elev_high) + ' m',
      "Lowest and highest point of the activity (span: " + Math.round(d.elev_high - d.elev_low) + " m).");
  else
    // No elevation bounds in the record (e.g. HealthSync) — derive from the GPX track below.
    html += '<div class="card" id="gpx-altitude-card" style="display:none"><div class="k">Altitude</div><div class="v"></div></div>';
  // Start clock time — derived from the first GPX timestamp (filled below).
  html += '<div class="card" id="gpx-start-card" style="display:none" title="Clock time the activity started, from the GPX track."><div class="k">Started</div><div class="v"></div></div>';
  var climbCard = '<div class="card" id="longest-climb-card" style="display:none" title="Blue lines on the map mark the climbs; use the ‹ › arrows to switch between them">'
    + '<div class="k"><span class="climb-swatch" aria-hidden="true"></span>Longest climb</div><div class="v"></div></div>';
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
  if (d.step_count) {
    html += card("Steps", Math.round(d.step_count).toLocaleString());
  } else if (d.average_cadence && isFoot(sport)) {
    html += cardTip("Steps", Math.round(d.average_cadence * 2 * d.moving_time / 60).toLocaleString(),
      "Estimated total steps: avg cadence (strides/min) × 2 × moving time.");
  } else if (d.distance > 0 && (sport === "Walk" || sport === "Hike")) {
    html += cardTip("Steps", Math.round(d.distance / 0.75).toLocaleString(),
      "Estimated total steps: distance ÷ 0.75 m average walking stride (no step or cadence data from Strava).");
  }
  if (d.average_watts)     html += card("Avg power", Math.round(d.average_watts) + " W");
  // Normalized power (weighted average) + Variability Index = NP / avg.
  if (d.weighted_average_watts) {
    var vi = d.average_watts > 0 ? (d.weighted_average_watts / d.average_watts).toFixed(2) : null;
    html += card("Norm. power", Math.round(d.weighted_average_watts) + " W" +
      (vi ? ' <span style="color:var(--text-4);font-size:.8rem">VI ' + vi + '</span>' : ''));
  }
  if (d.max_watts)         html += card("Max power", Math.round(d.max_watts) + " W");
  if (d.kilojoules)        html += card("Work", Math.round(d.kilojoules) + " kJ");
  if (d.calories)          html += card("Calories", Math.round(d.calories));
  if (d.suffer_score != null) html += cardTip("Strava Relative Effort", Math.round(d.suffer_score), "Official score supplied by Strava’s activity data.");
  if (d.average_temp != null || d.wind_speed != null) {
    var _ts = d.temp_source;
    var _srcLabel = _ts === "archive"   ? '<span class="wx-src wx-arch" title="Weather archive — historical data from Open-Meteo for the activity location and time.">hist</span>'
                  : _ts === "forecast"  ? '<span class="wx-src wx-fcst" title="Weather forecast — near-future estimate, upgraded to archive after ~7 days.">fcst</span>'
                  : d.average_temp != null ? '<span class="wx-src wx-dev" title="Temperature from your Garmin/device sensor or Strava\'s weather estimate.">device</span>'
                  : '';
    var _wIcon = '';
    if (d.weathercode != null) {
      var wc = d.weathercode;
      _wIcon = wc === 0                          ? '☀️'
             : wc <= 2                           ? '🌤️'
             : wc === 3                          ? '☁️'
             : (wc === 45 || wc === 48)          ? '🌫️'
             : (wc >= 51 && wc <= 57)            ? '🌦️'
             : (wc >= 61 && wc <= 67)            ? '🌧️'
             : (wc >= 71 && wc <= 77)            ? '🌨️'
             : (wc >= 80 && wc <= 82)            ? '🌦️'
             : (wc >= 85 && wc <= 86)            ? '🌨️'
             : (wc >= 95 && wc <= 99)            ? '⛈️'
             : '🌡️';
    }
    var _windArrow = '';
    if (d.wind_dir != null) {
      var dirs = ['↑','↗','→','↘','↓','↙','←','↖'];
      _windArrow = dirs[Math.round(((d.wind_dir % 360) + 360) % 360 / 45) % 8];
    }
    var _tempVal = d.average_temp != null ? (_wIcon ? _wIcon + ' ' : '') + Math.round(d.average_temp) + ' °C' + (d.apparent_temp != null && Math.round(d.apparent_temp) !== Math.round(d.average_temp) ? ' <span style="color:var(--text-4);font-size:.8rem">feels ' + Math.round(d.apparent_temp) + '°</span>' : '') + ' ' + _srcLabel : '';
    var _windVal = d.wind_speed != null ? _windArrow + ' ' + Math.round(d.wind_speed) + ' km/h' + (d.precipitation != null && d.precipitation > 0 ? ' <span style="color:var(--text-4);font-size:.8rem">💧' + (+d.precipitation).toFixed(1) + ' mm</span>' : '') : '';
    if (_tempVal) html += '<div class="card"><div class="k">Temp</div><div class="v">' + _tempVal + '</div></div>';
    if (_windVal) html += '<div class="card"><div class="k">Wind</div><div class="v">' + _windVal + '</div></div>';
  }
  if (d.gear && d.gear.name) html += card("Gear", esc(d.gear.name));
  if (d.device_name)       html += card("Device", esc(d.device_name));
  // Append the two full-width cards (Moving time, Longest climb) last so they sit
  // at the end of the grid instead of breaking the row flow earlier.
  html += movingCard + climbCard;
  document.getElementById("cards").innerHTML = html;
  if (d.average_heartrate > 0)
    renderHrEffort([{bpm:d.average_heartrate, secs:d.moving_time || 0}], d.max_heartrate || 0, d, "activity average HR only");
}

// --- Generic area line chart (elevation profile / heart rate) ----------------
// points: numeric array; color: stroke/fill hex; unit: label suffix (e.g. "m", "bpm")
// xLabels: optional string array (same length as points) — when provided the chart
// renders x-axis ticks. compactLabels=true keeps compact chart width and shows only
// whole-km boundary labels (for GPX charts with hundreds of points).
// Without xLabels the chart stays compact.
// xDomStart/xDomEnd (compactLabels only): force the km x-domain instead of deriving it
// from the first/last label. Lets a series that starts partway (e.g. temperature with the
// first 3 km dropped) stay pixel-aligned with the full-distance elev/hr/cad/spd charts.
function drawLineSvg(svgId, points, color, unit, xLabels, compactLabels, xDomStart, xDomEnd) {
  var n = points.length;
  if (!n) return;
  var minV = points[0], maxV = points[0], i;
  for (i = 1; i < n; i++) {
    if (points[i] < minV) minV = points[i];
    if (points[i] > maxV) maxV = points[i];
  }
  var base = (unit === "bpm") ? Math.max(40, minV - Math.max(10, Math.round((maxV - minV) * 0.15))) : minV;
  var range = (maxV - base) || 1;
  var YAX_W = 52, barW = 30, PX_PER_KM = 30;
  var yaxisSvg = document.getElementById(svgId + "-yaxis");
  var px = yaxisSvg ? 0 : YAX_W;  // no left margin when y-axis lives in a separate fixed SVG
  var labelH = xLabels ? 20 : 0;
  var W;
  // Effective km domain: honour explicit xDomStart/xDomEnd when given, else derive from labels.
  var _domStart = (compactLabels && isFinite(xDomStart)) ? xDomStart
                : (xLabels ? parseFloat(xLabels[0]) : 0);
  var _domEnd   = (compactLabels && isFinite(xDomEnd)) ? xDomEnd
                : (xLabels ? parseFloat(xLabels[n - 1]) : 0);
  if (xLabels && compactLabels) {
    // GPX distance chart: width scales linearly with total distance at a fixed
    // PX_PER_KM, so km N always lands at the same x. This keeps the elevation,
    // speed, HR, cadence and per-km charts on one shared x-axis (the per-km bar
    // chart in renderSplitsFromArray uses the same PX_PER_KM and left gutter).
    var _tk = _domEnd - _domStart;
    if (!(_tk > 0)) _tk = 0;
    W = Math.max(px + 16 + Math.round(_tk * PX_PER_KM), 900);
  } else if (xLabels) {
    W = px + n * barW + 16;
  } else {
    W = Math.max(n * 3, 900);
  }
  var H = 200, ch = H - 18 - labelH;
  // X positioning. For GPX charts (compactLabels) xLabels hold cumulative km, so place
  // points by distance to make the km axis linear and evenly spaced. Otherwise (per-split
  // charts) space points evenly by index. Falls back to index if the distance span is
  // zero/invalid.
  var useDist = !!(compactLabels && xLabels), d0 = 0, dSpan = 1;
  if (useDist) {
    d0 = _domStart;
    if (!isFinite(d0)) d0 = 0;
    dSpan = (isFinite(_domEnd) ? _domEnd : 0) - d0;
    if (!(dSpan > 0)) useDist = false;
  }
  function xPos(i) {
    var frac;
    if (useDist) {
      var dv = parseFloat(xLabels[i]);
      frac = isFinite(dv) ? (dv - d0) / dSpan : 0;
    } else {
      frac = i / (n > 1 ? n - 1 : 1);
    }
    return px + frac * (W - px - 16);
  }
  var path = "", x, y;
  for (i = 0; i < n; i++) {
    x = xPos(i).toFixed(1);
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
      '" stroke="var(--chart-grid)" stroke-width="1"/>';
    if (yaxisSvg) {
      yaxisHtml +=
        '<text x="' + (YAX_W - 6) + '" y="' + (parseFloat(gy) + 4) + '" text-anchor="end" font-size="11" fill="var(--text-3)">' + lbl + '</text>' +
        '<line x1="' + (YAX_W - 3) + '" y1="' + gy + '" x2="' + YAX_W + '" y2="' + gy + '" stroke="var(--border-2)" stroke-width="1"/>';
    } else {
      gridLines +=
        '<text x="' + (px - 6) + '" y="' + (parseFloat(gy) + 4) + '" text-anchor="end" font-size="11" fill="var(--text-3)">' + lbl + '</text>';
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
    if (compactLabels) {
      // Points are positioned by distance (see xPos), so km boundaries are evenly spaced.
      // Still enforce a minimum pixel gap so very long rides thin to every N km instead of
      // overlapping.
      var lastKm = -1, lastLabelX = -1e9, MIN_LABEL_GAP = 34;
      for (i = 0; i < n; i++) {
        var kmVal = Math.floor(parseFloat(xLabels[i]));
        if (isNaN(kmVal) || kmVal === lastKm) continue;
        lastKm = kmVal;
        var lx = xPos(i);
        if (lx - lastLabelX < MIN_LABEL_GAP) continue;
        lastLabelX = lx;
        html += '<text x="' + lx.toFixed(1) + '" y="' + (H - 4) + '" text-anchor="middle" font-size="11" fill="var(--text-3)">' + kmVal + ' km</text>';
      }
    } else {
      var stride = n > 120 ? 5 : n > 60 ? 2 : 1;
      for (i = 0; i < n; i += stride) {
        x = xPos(i).toFixed(1);
        var labelText = String(xLabels[i]);
        if (i === 0 && labelText === "0") labelText = "0 km";
        html += '<text x="' + x + '" y="' + (H - 4) + '" text-anchor="middle" font-size="11" fill="var(--text-3)">' + labelText + '</text>';
      }
    }
  }
  // Build per-point tooltip data and add a transparent hit overlay.
  var tipEntries = [];
  for (i = 0; i < n; i++) {
    var tx = parseFloat(xPos(i).toFixed(1));
    var tipLabel = xLabels
      ? ('<strong>Km ' + esc(xLabels[i]) + '</strong>')
      : ('<strong>' + (unit === 'bpm' ? 'Heart rate' : 'Elevation') + '</strong>');
    tipEntries.push({x: tx, html: tipLabel + Math.round(points[i]) + ' ' + unit});
  }
  LINE_TIPS[svgId] = tipEntries;
  html += '<rect x="' + px + '" y="0" width="' + (W - px - 16) + '" height="' + H + '"'
        + ' fill="transparent" style="cursor:crosshair"'
        + ' onmousemove="lineChartHover(event,\'' + svgId + '\')"'
        + ' onmouseout="hideTip()"'
        + ' ontouchmove="lineChartHover({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},\'' + svgId + '\')"'
        + ' ontouchend="hideTip()"/>';

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

function renderPowerFromSplits(splits) {
  var watts = [], labels = [], i, w;
  for (i = 0; i < splits.length; i++) {
    w = splits[i].average_watts;
    if (w > 0) { watts.push(w); labels.push(String(i + 1)); }
  }
  if (!watts.length) return;
  document.getElementById("pwr-box").style.display = "";
  drawLineSvg("svg-pwr", watts, "#f57c00", "W", labels);
}

// h:mm:ss / m:ss for zone time display; "0 s" for zero.
function fmtHMS(s) {
  s = Math.round(s);
  if (!s) return "0 s";
  var h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
  if (h > 0) return h + ":" + (m<10?"0":"") + m + ":" + (sec<10?"0":"") + sec;
  return m + ":" + (sec<10?"0":"") + sec;
}

function resolveHrMax(hrPoints, maxHR) {
  var hrMax = ATHLETE_AGE > 0 ? 220 - ATHLETE_AGE : (maxHR || 0);
  if (!hrMax) {
    for (var i = 0; i < hrPoints.length; i++)
      if (hrPoints[i].bpm > hrMax) hrMax = hrPoints[i].bpm;
  }
  return hrMax;
}

// Six-zone model (% of HRmax): Relaxed <50, Healthy 50-60, Fat Burn 60-70,
// Aerobic 70-80, Strength Training 80-90, Red-line ≥90.
function hrZoneIndex(bpm, hrMax) {
  if (bpm < Math.round(0.50 * hrMax)) return 0;
  if (bpm < Math.round(0.60 * hrMax)) return 1;
  if (bpm < Math.round(0.70 * hrMax)) return 2;
  if (bpm < Math.round(0.80 * hrMax)) return 3;
  if (bpm < Math.round(0.90 * hrMax)) return 4;
  return 5;
}

function renderHrEffort(hrPoints, maxHR, activity, source) {
  if (!hrPoints.length) return;
  var hrMax = resolveHrMax(hrPoints, maxHR);
  if (!hrMax) return;
  var weightedSecs = 0, totalSecs = 0;
  for (var i = 0; i < hrPoints.length; i++) {
    var bpm = Number(hrPoints[i].bpm), secs = Number(hrPoints[i].secs);
    if (!isFinite(bpm) || bpm <= 0 || !isFinite(secs) || secs <= 0) continue;
    var zone = bpm < Math.round(.60*hrMax) ? 0
      : bpm < Math.round(.80*hrMax) ? 1
      : bpm < Math.round(.90*hrMax) ? 2
      : bpm < Math.round(hrMax) ? 3 : 4;
    weightedSecs += secs * (zone + 1);
    totalSecs += secs;
  }
  if (!totalSecs) return;
  var estimate = Math.round(weightedSecs / 60 / 7);
  var method = source === "activity average HR only"
    ? "Only the activity average HR is available, so it is treated as constant throughout moving time."
    : "Calculated from " + source + " and their durations.";
  var tip = "Estimated HR effort: time in Strava-like zones (<60%, 60–80%, 80–90%, 90–100%, >100% of HRmax), weighted 1–5 and divided by 7. "
    + method + " This is an estimate, not Strava’s official Relative Effort score.";
  var html = '<div class="card" id="hr-effort-card" title="' + esc(tip) + '">'
    + '<div class="k">HR effort (est.)</div><div class="v">' + estimate + '</div></div>';
  var existing = document.getElementById("hr-effort-card");
  if (existing) existing.outerHTML = html;
  else document.getElementById("cards").insertAdjacentHTML("beforeend", html);
}

// hrPoints: [{bpm, secs}] — secs is actual time (splits) or equal weight (GPX).
// maxHR: activity max_heartrate; if 0/null, derived from data.
// Six zones: <50%, 50-60%, 60-70%, 70-80%, 80-90%, ≥90% of HRmax.
// HRmax preference: ATHLETE_AGE > 0 → 220 − age; else activity maxHR; else peak from data.
function renderHrZones(hrPoints, maxHR) {
  if (!hrPoints.length) return;
  var i, bpm;
  var hrMax = resolveHrMax(hrPoints, maxHR), sourceLabel;
  if (ATHLETE_AGE > 0) {
    sourceLabel = "HRmax " + hrMax + " bpm";
  } else {
    sourceLabel = hrMax ? "HRmax " + hrMax + " bpm (activity max)" : "";
  }
  if (!hrMax) return;
  var pcts = [0.50, 0.60, 0.70, 0.80, 0.90];
  var t = [];
  for (i = 0; i < pcts.length; i++) t.push(Math.round(pcts[i] * hrMax));
  var labels = [
    "< " + t[0] + " bpm",
    t[0] + " – " + (t[1]-1) + " bpm",
    t[1] + " – " + (t[2]-1) + " bpm",
    t[2] + " – " + (t[3]-1) + " bpm",
    t[3] + " – " + (t[4]-1) + " bpm",
    "≥ " + t[4] + " bpm"
  ];
  var colors = ["#cfd8dc","#9e9e9e","#29b6f6","#8bc34a","#ffca28","#f4511e"];
  var names  = ["Relaxed","Healthy","Fat Burn","Aerobic","Strength Training","Red-line"];
  var descs  = [
    "Recovery — very light effort (below 50% max HR)",
    "Healthy — light activity, builds endurance base (50–60% max HR)",
    "Fat Burn — comfortable aerobic effort (60–70% max HR)",
    "Aerobic — moderate endurance effort (70–80% max HR)",
    "Strength Training — hard effort near anaerobic threshold (80–90% max HR)",
    "Red-line — maximum effort, peak performance (above 90% max HR)"
  ];
  var zoneSecs = [0,0,0,0,0,0], totalSecs = 0, zone, secs;
  for (i = 0; i < hrPoints.length; i++) {
    bpm = hrPoints[i].bpm; secs = hrPoints[i].secs;
    if (bpm <= 0) continue;
    zone = hrZoneIndex(bpm, hrMax);
    zoneSecs[zone] += secs; totalSecs += secs;
  }
  if (!totalSecs) return;
  var html = '<table class="hr-zone-table">';
  for (i = 5; i >= 0; i--) {
    var pct = zoneSecs[i] / totalSecs * 100;
    var barW = Math.min(100, Math.round(pct));
    html += '<tr title="' + descs[i] + '">'
      + '<td style="font-weight:600;white-space:nowrap;cursor:help">'
        + '<span style="display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:6px;background:' + colors[i] + ';vertical-align:middle"></span>'
        + names[i] + '</td>'
      + '<td style="color:var(--text-3);white-space:nowrap">' + labels[i] + '</td>'
      + '<td style="font-variant-numeric:tabular-nums;white-space:nowrap">' + fmtHMS(zoneSecs[i]) + '</td>'
      + '<td style="font-variant-numeric:tabular-nums;color:var(--text-4);white-space:nowrap">' + pct.toFixed(1) + '%</td>'
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

// Duration label: "5 s", "30 s", "2 min", "180 min".
function fmtDurShort(s) {
  return s < 60 ? s + " s" : Math.round(s / 60) + " min";
}

// Maximum-average heart-rate curve: for each window length, the best average HR
// sustained over any continuous window of that length during the activity.
// hrSamples: ordered HR values; movingTime: seconds (samples assumed evenly spaced).
// Rendered on its own log-scaled duration x-axis, independent of the other charts.
function renderHrMaxAvg(hrSamples, movingTime) {
  var n = hrSamples.length;
  if (n < 2 || !(movingTime > 0)) return;
  var secsPerPt = movingTime / n;
  // Prefix sums for O(1) window averages.
  var pre = new Array(n + 1); pre[0] = 0;
  for (var i = 0; i < n; i++) pre[i + 1] = pre[i] + Number(hrSamples[i] || 0);
  var DURS = [5, 10, 20, 30, 60, 120, 300, 720, 1200, 2400, 3600, 5400, 10800];
  var pts = [];   // {d: seconds, v: bpm}
  for (var di = 0; di < DURS.length; di++) {
    var D = DURS[di];
    var w = Math.round(D / secsPerPt);
    if (w < 1) w = 1;
    if (w > n) break;   // window longer than the activity
    var best = 0;
    for (var s = 0; s + w <= n; s++) {
      var avg = (pre[s + w] - pre[s]) / w;
      if (avg > best) best = avg;
    }
    if (best > 0) pts.push({ d: D, v: best });
  }
  if (pts.length < 2) return;
  drawHrMaxAvgSvg(pts);
  document.getElementById("hr-maxavg-box").style.display = "";
  if (window._detailSecAfterRender) window._detailSecAfterRender();
}

function drawHrMaxAvgSvg(pts) {
  var n = pts.length, i, color = "#e91e63";
  var minV = pts[0].v, maxV = pts[0].v;
  for (i = 1; i < n; i++) { if (pts[i].v < minV) minV = pts[i].v; if (pts[i].v > maxV) maxV = pts[i].v; }
  var base = Math.max(40, Math.floor(minV - Math.max(10, (maxV - minV) * 0.15)));
  var range = (maxV - base) || 1;
  var YAX_W = 52, PLOT_W = Math.max(560, (n - 1) * 90), px = 0;
  var labelH = 20, H = 200, ch = H - 18 - labelH, W = YAX_W + PLOT_W + 16;
  px = YAX_W;
  var lx0 = Math.log(pts[0].d), lxSpan = Math.log(pts[n - 1].d) - lx0;
  if (!(lxSpan > 0)) lxSpan = 1;
  function xPos(idx) { return px + ((Math.log(pts[idx].d) - lx0) / lxSpan) * (W - px - 16); }
  function yPos(v) { return ch - ((v - base) / range) * (ch - 24); }
  var path = "";
  for (i = 0; i < n; i++) path += (i ? "L" : "M") + xPos(i).toFixed(1) + "," + yPos(pts[i].v).toFixed(1);
  var fill = path + "L" + (W - 16) + "," + ch + "L" + px + "," + ch + "Z";

  // Grid lines + y-axis labels (separate fixed y-axis SVG, like drawLineSvg).
  // Aim for ~5 evenly spaced ticks at round bpm values (step of 5/10/20/25…).
  var gridLines = "", yaxisHtml = "";
  var top = base + range, raw = range / 5;
  var step = raw <= 5 ? 5 : raw <= 10 ? 10 : raw <= 20 ? 20 : raw <= 25 ? 25 : Math.ceil(raw / 50) * 50;
  var gridVals = [base];
  for (var gv = Math.ceil((base + 1) / step) * step; gv < top - step * 0.3; gv += step) gridVals.push(gv);
  gridVals.push(top);
  for (i = 0; i < gridVals.length; i++) {
    var gy = yPos(gridVals[i]).toFixed(1);
    gridLines += '<line x1="' + px + '" y1="' + gy + '" x2="' + (W - 16) + '" y2="' + gy + '" stroke="var(--chart-grid)" stroke-width="1"/>';
    yaxisHtml += '<text x="' + (YAX_W - 6) + '" y="' + (parseFloat(gy) + 4) + '" text-anchor="end" font-size="11" fill="var(--text-3)">' + Math.round(gridVals[i]) + ' bpm</text>'
      + '<line x1="' + (YAX_W - 3) + '" y1="' + gy + '" x2="' + YAX_W + '" y2="' + gy + '" stroke="var(--border-2)" stroke-width="1"/>';
  }
  var yaxisSvg = document.getElementById("svg-hrmaxavg-yaxis");
  if (yaxisSvg) {
    yaxisSvg.setAttribute("viewBox", "0 0 " + YAX_W + " " + H);
    yaxisSvg.setAttribute("width", YAX_W);
    yaxisSvg.setAttribute("height", H);
    yaxisSvg.innerHTML = yaxisHtml;
  }

  var html = gridLines
    + '<path d="' + fill + '" fill="' + color + '" opacity=".18"/>'
    + '<path d="' + path + '" fill="none" stroke="' + color + '" stroke-width="2" stroke-linejoin="round"/>';
  var lastLabelX = -1e9, MIN_GAP = 40;
  for (i = 0; i < n; i++) {
    var lxp = xPos(i);
    html += '<circle cx="' + lxp.toFixed(1) + '" cy="' + yPos(pts[i].v).toFixed(1) + '" r="3" fill="' + color + '"/>';
    if (lxp - lastLabelX < MIN_GAP && i !== n - 1) continue;
    lastLabelX = lxp;
    html += '<text x="' + lxp.toFixed(1) + '" y="' + (H - 4) + '" text-anchor="middle" font-size="11" fill="var(--text-3)">' + fmtDurShort(pts[i].d) + '</text>';
  }
  var tipEntries = [];
  for (i = 0; i < n; i++) {
    tipEntries.push({ x: parseFloat(xPos(i).toFixed(1)),
      html: '<strong>' + fmtDurShort(pts[i].d) + '</strong>' + Math.round(pts[i].v) + ' bpm' });
  }
  LINE_TIPS["svg-hrmaxavg"] = tipEntries;
  html += '<rect x="' + px + '" y="0" width="' + (W - px - 16) + '" height="' + H + '"'
        + ' fill="transparent" style="cursor:crosshair"'
        + ' onmousemove="lineChartHover(event,\'svg-hrmaxavg\')"'
        + ' onmouseout="hideTip()"'
        + ' ontouchmove="lineChartHover({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},\'svg-hrmaxavg\')"'
        + ' ontouchend="hideTip()"/>';

  var svg = document.getElementById("svg-hrmaxavg");
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);
  svg.style.width = W + "px";
  svg.innerHTML = html;
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

// Cooperative touch gestures. On a touch device Leaflet's default one-finger
// drag pans the map and swallows the page scroll, so a swipe that starts on the
// map never reaches the sections below — especially painful in landscape where
// the map fills the viewport. Require two fingers to pan: a one-finger swipe
// then scrolls the page as normal, two fingers pan/zoom the map. A brief hint
// overlay tells the user how to move the map when they try one finger.
function enableCoopGestures(map) {
  if (!L.Browser.touch && !("ontouchstart" in window)) return;
  map.dragging.disable();
  var c = map.getContainer();
  var hint, hintTimer;
  function showHint() {
    if (!hint) {
      hint = document.createElement("div");
      hint.textContent = "Use two fingers to move the map";
      hint.style.cssText = "position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.45);color:#fff;font-size:15px;font-weight:600;text-align:center;padding:0 20px;z-index:1200;pointer-events:none;opacity:0;transition:opacity .15s";
      c.appendChild(hint);
    }
    hint.style.opacity = "1";
    clearTimeout(hintTimer);
    hintTimer = setTimeout(function(){ if (hint) hint.style.opacity = "0"; }, 1400);
  }
  c.addEventListener("touchstart", function(e) {
    if (e.touches.length >= 2) { map.dragging.enable(); }
    else { map.dragging.disable(); }
  }, { passive: true });
  c.addEventListener("touchmove", function(e) {
    if (e.touches.length < 2) showHint();
  }, { passive: true });
  c.addEventListener("touchend", function(e) {
    if (e.touches.length < 2) map.dragging.disable();
  }, { passive: true });
}

// Detect every qualifying climb in the track (not just the biggest). A major
// descent (> CLIMB_DESCENT_RESET below the running peak) closes the current climb
// segment and starts a new one, so each "run" between big descents contributes at
// most one climb (its biggest valley→peak gain that clears the gain/distance/grade
// thresholds). Returns an array sorted by gain descending; each entry carries
// `idx`, a 1-based number in track order so the map and card can label climbs
// consistently. Empty array when no segment qualifies.
function findClimbs(trackPts, sport){
  var raw = [], i, j, from, to, sum, cnt;
  for (i = 0; i < trackPts.length; i++) {
    if (trackPts[i].ele != null && isFinite(trackPts[i].ele)) raw.push(trackPts[i].ele);
    else raw.push(null);
  }
  if (raw.length < 2) return [];
  var smooth = [];
  for (i = 0; i < raw.length; i++) {
    if (raw[i] == null) { smooth.push(null); continue; }
    from = Math.max(0, i - 2); to = Math.min(raw.length - 1, i + 2); sum = 0; cnt = 0;
    for (j = from; j <= to; j++) if (raw[j] != null) { sum += raw[j]; cnt++; }
    smooth.push(cnt ? sum / cnt : null);
  }
  var cumDist = [0];
  for (i = 1; i < trackPts.length; i++)
    cumDist.push(cumDist[i - 1] + haversineM(trackPts[i - 1].lat, trackPts[i - 1].lon, trackPts[i].lat, trackPts[i].lon));
  var sportKey = sport === "Ride" || sport === "Run" || sport === "Hike" || sport === "Walk" ? sport : "Other";
  var minGain = CLIMB_THRESHOLDS.gain[sportKey] || CLIMB_THRESHOLDS.gain.Other;
  var minGrade = (CLIMB_MIN_GRADE["g" + sportKey] || 2) / 100;
  var descentReset = CLIMB_DESCENT_RESET;
  var climbs = [];
  var best = 0, bestStart = -1, bestEnd = -1;
  var segValIdx = -1, segValEle = 0, segPeakEle = 0;
  function flush() {
    if (bestStart >= 0 && bestEnd > bestStart)
      climbs.push({start: bestStart, end: bestEnd, gain: Math.round(best), distance: cumDist[bestEnd] - cumDist[bestStart]});
    best = 0; bestStart = -1; bestEnd = -1;
  }
  for (i = 0; i < smooth.length; i++) {
    if (smooth[i] == null) continue;
    if (segValIdx < 0) { segValIdx = i; segValEle = smooth[i]; segPeakEle = smooth[i]; continue; }
    var e = smooth[i];
    if (e < segPeakEle - descentReset) {
      flush();
      segValIdx = i; segValEle = e; segPeakEle = e; continue;
    }
    if (e > segPeakEle) segPeakEle = e;
    if (e < segValEle) { segValIdx = i; segValEle = e; }
    var gain = e - segValEle;
    var dist = cumDist[i] - cumDist[segValIdx];
    if (gain >= minGain && dist >= CLIMB_THRESHOLDS.minDistance && dist > 0 && gain / dist >= minGrade && gain > best) {
      best = gain; bestStart = segValIdx; bestEnd = i;
    }
  }
  flush();
  // Number in track order (start index), then sort by gain so the biggest is first.
  climbs.sort(function(a, b){ return a.start - b.start; });
  for (i = 0; i < climbs.length; i++) climbs[i].idx = i + 1;
  climbs.sort(function(a, b){ return b.gain - a.gain; });
  return climbs;
}

// Fetch each GPX once and share the text between the map and the charts — both
// consumers (renderGpxMap, renderGpxCharts) would otherwise re-download the same
// multi-MB file. Memoize the fetch promise keyed by URL; reject with a .status on HTTP errors.
var _gpxTextCache = {};
function fetchGpxText(url){
  if (!_gpxTextCache[url]) {
    _gpxTextCache[url] = fetch(url, { cache: "no-cache" }).then(function(r){
      if (!r.ok) { var err = new Error("HTTP " + r.status); err.status = r.status; throw err; }
      return r.text();
    });
  }
  return _gpxTextCache[url];
}

// Fetch + parse ourselves to avoid leaflet-gpx's responseXML=null crash when
// uhttpd serves .gpx without an XML Content-Type header.
function renderGpxMap(gpxUrl, sport, maxSingleClimb){
  var box = document.getElementById("map-box");
  if (typeof L === "undefined") {
    hideMapSpin();
    box.innerHTML = '<div class="note">Map library unavailable (needs internet).</div>';
    return;
  }
  fetchGpxText(gpxUrl)
    .then(function(txt){
      if (!txt.trim()) { hideMapSpin(); box.innerHTML = '<div class="note">GPX file is empty.</div>'; return; }
      var doc = (new DOMParser()).parseFromString(txt, "application/xml");
      var perr = doc.documentElement && doc.documentElement.nodeName === "parsererror";
      if (perr) { hideMapSpin(); box.innerHTML = '<div class="note">GPX not valid XML — first bytes: <code>' + txt.slice(0,120).replace(/</g,"&lt;") + '</code></div>'; return; }
      var els = doc.getElementsByTagNameNS("*", "trkpt");
      if (!els.length) els = doc.getElementsByTagNameNS("*", "rtept");
      var trackPts = [], pts = [], i, el;
      for (i = 0; i < els.length; i++) {
        el = els[i];
        var eleEl = el.getElementsByTagNameNS("*", "ele")[0];
        var ele = eleEl ? parseFloat(eleEl.textContent) : null;
        trackPts.push({lat:parseFloat(el.getAttribute("lat")), lon:parseFloat(el.getAttribute("lon")), ele:ele});
        pts.push([trackPts[i].lat, trackPts[i].lon]);
      }
      if (!pts.length) { hideMapSpin(); box.innerHTML = '<div class="note">GPX has no track points.</div>'; return; }
      try {
        var map = L.map("map");
        leafletMap = map;
        var tileLayer = makeTileLayer(map);
        enableCoopGestures(map);
        var line = L.polyline(pts, { color: "#fc4c02", weight: 4, opacity: 0.9 }).addTo(map);
        leafletLine = line;
        map.fitBounds(line.getBounds());
        addDirectionArrows(map, pts);
        // Draw every qualifying climb (blue). The biggest gets a heavier line and
        // drives the initial zoom; when more than one is found the climb markers are
        // numbered ("Climb 2 …") to match the card's ‹ › switcher. Line layers are
        // kept keyed by idx so the switcher can focus/highlight each one.
        var climbs = findClimbs(trackPts, sport);
        var climbLines = [];
        _climbMap = map; _climbLines = {};
        // All climb overlays live in their own pane so the "Hide climbs" button can
        // toggle them with one style change.
        map.createPane("climbPane").style.zIndex = 450;
        if (climbs.length) {
          for (var ci = 0; ci < climbs.length; ci++) {
            var c = climbs[ci];
            var isBiggest = (ci === 0);
            var label = climbs.length > 1 ? "Climb " + c.idx : "Climb";
            var cl = L.polyline(pts.slice(c.start, c.end + 1), { color: "#1565c0", weight: isBiggest ? 7 : 5, opacity: 0.9, pane: "climbPane" }).addTo(map);
            climbLines.push(cl);
            _climbLines[c.idx] = cl;
            L.circleMarker(pts[c.start], { pane: "climbPane", radius: 6, color: "#2e7d32", fillColor: "#66bb6a", fillOpacity: 1 })
              .bindTooltip(label + " start", {permanent:false}).addTo(map);
            L.circleMarker(pts[c.end], { pane: "climbPane", radius: 6, color: "#b71c1c", fillColor: "#ef5350", fillOpacity: 1 })
              .bindTooltip(label + " summit", {permanent:false}).addTo(map);
          }
          updateLongestClimbCard(climbs, trackPts);
          renderClimbGradientOnMap(_climbs[_climbIdx]);
        } else if (maxSingleClimb > 0) {
          updateLongestClimbCard([{gain: maxSingleClimb, distance: null}], trackPts);
        }
        // Open zoomed to the shown (longest/default) climb so the map matches the
        // card + chart; the "Full route" button zooms out to the whole ride.
        var climbGroup = climbLines.length ? L.featureGroup(climbLines) : null;
        var selClimbLine = (_climbs.length && _climbLines) ? _climbLines[_climbs[_climbIdx].idx] : null;
        var fitTarget = selClimbLine ? selClimbLine
                      : (climbGroup && climbGroup.getBounds().isValid()) ? climbGroup : line;
        var fitPad = (selClimbLine || climbGroup) ? [40, 40] : [20, 20];
        map.fitBounds(fitTarget.getBounds(), { padding: fitPad });
        // Whole-activity start (green "Start") and finish (black "Finish") markers,
        // with always-on labels and white rings so they read clearly apart from the
        // green/red climb start/summit dots.
        L.circleMarker(pts[0], { radius: 8, color: "#ffffff", weight: 2, fillColor: "#2e7d32", fillOpacity: 1 })
          .bindTooltip("Start", { permanent: true, direction: "top", className: "route-endpoint-tip" }).addTo(map);
        L.circleMarker(pts[pts.length-1], { radius: 8, color: "#ffffff", weight: 2, fillColor: "#111111", fillOpacity: 1 })
          .bindTooltip("Finish", { permanent: true, direction: "top", className: "route-endpoint-tip" }).addTo(map);
        // "Full route" + "Hide climbs" buttons — only when the route has climbs
        if (climbGroup) {
          var fullBtn = L.control({ position: "bottomleft" });
          fullBtn.onAdd = function() {
            var wrap = L.DomUtil.create("div", "");
            var bs = "background:var(--btn-bg,rgba(255,255,255,.9));border:1px solid var(--border-2,#ccc);border-radius:.3rem;padding:.2rem .5rem;font-size:.78rem;cursor:pointer;line-height:1.5;box-shadow:0 1px 3px rgba(0,0,0,.15);margin-right:.3rem";
            var d = L.DomUtil.create("button", "", wrap);
            d.innerHTML = "Full route";
            d.style.cssText = bs;
            L.DomEvent.on(d, "click", function(e) {
              L.DomEvent.stop(e);
              map.fitBounds(line.getBounds(), { padding: [20, 20] });
            });
            var hb = L.DomUtil.create("button", "climb-toggle-btn", wrap);
            hb.innerHTML = "Hide climbs";
            hb.style.cssText = bs;
            var hidden = false;
            L.DomEvent.on(hb, "click", function(e) {
              L.DomEvent.stop(e);
              hidden = !hidden;
              map.getPane("climbPane").style.display = hidden ? "none" : "";
              hb.innerHTML = hidden ? "Show climbs" : "Hide climbs";
            });
            L.DomEvent.disableClickPropagation(wrap);
            return wrap;
          };
          fullBtn.addTo(map);
        }
        setTimeout(function(){ map.invalidateSize(); map.fitBounds(fitTarget.getBounds(), { padding: fitPad }); }, 0);
        tileLayer.once("load", hideMapSpin);
        setTimeout(hideMapSpin, 10000);
      } catch(e) {
        hideMapSpin();
        box.innerHTML = '<div class="note">Map render failed: ' + e.message + '</div>';
      }
    })
    .catch(function(e){
      hideMapSpin();
      if (e && e.status) { box.innerHTML = '<div class="note">GPX not found (' + e.status + '): ' + gpxUrl + '</div>'; return; }
      box.innerHTML = '<div class="note">GPX fetch error: ' + (e && e.message || String(e)) + '</div>';
    });
}

function haversineM(lat1, lon1, lat2, lon2) {
  var R = 6371000, dLat = (lat2-lat1)*Math.PI/180, dLon = (lon2-lon1)*Math.PI/180;
  var a = Math.sin(dLat/2)*Math.sin(dLat/2)+Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
  return R*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));
}

// --- GPX elevation + heart rate + cadence charts (healthsync / scrape activities) -----
// Fetches the GPX once, populates elev-box, hr-box, hr-zone-box, cad-box, and splits-box.
function renderGpxCharts(gpxUrl, maxHR, movingTime, sport, maxSingleClimb, detail) {
  fetchGpxText(gpxUrl)
    .then(function(txt){
      var doc = (new DOMParser()).parseFromString(txt, "application/xml");
      var i, step;

      // One pass over all track points: collect elevation, HR, cadence, and cumulative distance.
      var trkpts = doc.getElementsByTagNameNS("*", "trkpt");
      if (!trkpts.length) trkpts = doc.getElementsByTagNameNS("*", "rtept");
      var climbTrackPts = [];
      var allE = [], allEDist = [];
      var allH = [], allHDist = [];
      var allC = [], allCDist = [];
      var allT = [], allTDist = [];               // device/air temperature (°C) + cumulative km
      var spDist = [], spTime = [], spKm = [];   // cumulative m, epoch s, km — for speed (needs time)
      var cumDist = 0, prevLat = null, prevLon = null;
      for (i = 0; i < trkpts.length; i++) {
        var pt = trkpts[i];
        var lat = parseFloat(pt.getAttribute("lat")), lon = parseFloat(pt.getAttribute("lon"));
        if (prevLat !== null) cumDist += haversineM(prevLat, prevLon, lat, lon);
        prevLat = lat; prevLon = lon;
        var km = cumDist / 1000;
        var eleEl = pt.getElementsByTagNameNS("*", "ele")[0];
        var eleV = eleEl ? parseFloat(eleEl.textContent) : null;
        climbTrackPts.push({lat: lat, lon: lon, ele: eleV});
        if (eleV !== null) { allE.push(eleV); allEDist.push(km); }
        var hrEls = pt.getElementsByTagNameNS("*", "hr");
        if (!hrEls.length) hrEls = pt.getElementsByTagNameNS("*", "heartrate");
        var bpm = hrEls.length ? (parseFloat(hrEls[0].textContent) || 0) : 0;
        if (bpm > 0) { allH.push(bpm); allHDist.push(km); }
        var cadEls = pt.getElementsByTagNameNS("*", "cad");
        if (!cadEls.length) cadEls = pt.getElementsByTagNameNS("*", "cadence");
        var rpm = cadEls.length ? (parseFloat(cadEls[0].textContent) || 0) : 0;
        if (rpm > 0) { allC.push(rpm); allCDist.push(km); }
        // Air/device temperature: Garmin exports <gpxtpx:atemp>; some tools use <temp>.
        var tmpEls = pt.getElementsByTagNameNS("*", "atemp");
        if (!tmpEls.length) tmpEls = pt.getElementsByTagNameNS("*", "temp");
        if (tmpEls.length) {
          var degC = parseFloat(tmpEls[0].textContent);
          if (isFinite(degC)) { allT.push(degC); allTDist.push(km); }
        }
        var tEl = pt.getElementsByTagNameNS("*", "time")[0];
        var tS = tEl ? new Date(tEl.textContent).getTime() / 1000 : null;
        if (tS !== null && isFinite(tS)) { spDist.push(cumDist); spTime.push(tS); spKm.push(km); }
      }

      var gpxClimbs = findClimbs(climbTrackPts, sport);
      updateLongestClimbCard(gpxClimbs.length ? gpxClimbs : (maxSingleClimb > 0 ? [{gain: maxSingleClimb, distance: null}] : null), climbTrackPts);

      // GPX-derived cards for records that lack them (e.g. HealthSync): altitude
      // range (min/max elevation) and total/stopped/% from the first→last timestamps.
      var altCard = document.getElementById("gpx-altitude-card");
      if (altCard && allE.length) {
        var loE = allE[0], hiE = allE[0];
        for (i = 1; i < allE.length; i++) { if (allE[i] < loE) loE = allE[i]; if (allE[i] > hiE) hiE = allE[i]; }
        if (hiE > loE) {
          altCard.querySelector(".v").textContent = Math.round(loE) + "–" + Math.round(hiE) + " m";
          altCard.title = "Lowest and highest point, from the GPX track (span: " + Math.round(hiE - loE) + " m).";
          altCard.style.display = "";
        }
      }
      var subEl = document.getElementById("gpx-elapsed-sub");
      if (subEl && spTime.length > 1) {
        var gElapsed = spTime[spTime.length - 1] - spTime[0];
        if (gElapsed > (movingTime || 0)) {
          var gStopped = gElapsed - (movingTime || 0);
          var gPct = gElapsed > 0 ? Math.round(100 * (movingTime || 0) / gElapsed) : null;
          subEl.textContent = fmtTime(gElapsed) + " total"
            + (gStopped >= 60 ? " · " + fmtTime(gStopped) + " stopped" : "")
            + (gPct != null ? " · " + gPct + "% moving" : "");
          subEl.title = "Total time and stops derived from the GPX track timestamps.";
          subEl.style.display = "";
        }
      }
      // Total descent: sum of downhill deltas over lightly smoothed elevation
      // (a ±2-point moving average) to suppress GPS jitter.
      var descCard = document.getElementById("gpx-descent-card");
      if (descCard && allE.length > 2) {
        var sm = [], W = 2, a2, b2, s2, n2, j2;
        for (i = 0; i < allE.length; i++) {
          a2 = Math.max(0, i - W); b2 = Math.min(allE.length - 1, i + W); s2 = 0; n2 = 0;
          for (j2 = a2; j2 <= b2; j2++) { s2 += allE[j2]; n2++; }
          sm.push(s2 / n2);
        }
        var desc = 0;
        for (i = 1; i < sm.length; i++) { var dd2 = sm[i] - sm[i - 1]; if (dd2 < 0) desc += -dd2; }
        if (desc >= 1) {
          descCard.querySelector(".v").textContent = Math.round(desc) + " m";
          descCard.style.display = "";
        }
      }
      // Start clock time from the first GPX timestamp.
      var startCard = document.getElementById("gpx-start-card");
      if (startCard && spTime.length) {
        var sd = new Date(spTime[0] * 1000);
        if (isFinite(sd.getTime())) {
          var hh = sd.getHours(), mm = sd.getMinutes();
          startCard.querySelector(".v").textContent = (hh < 10 ? "0" + hh : hh) + ":" + (mm < 10 ? "0" + mm : mm);
          startCard.style.display = "";
        }
      }

      function dsWithKmLabels(arr, distArr) {
        var s = Math.max(1, Math.floor(arr.length / 600));
        var vals = [], labels = [];
        for (var j = 0; j < arr.length; j += s) { vals.push(arr[j]); labels.push(distArr[j].toFixed(2)); }
        return {vals: vals, labels: labels};
      }

      if (allE.length) {
        var dsE = dsWithKmLabels(allE, allEDist);
        document.getElementById("elev-box").style.display = "";
        drawLineSvg("svg-elev", dsE.vals, "#fc4c02", "m", dsE.labels, true);
      }

      if (allH.length) {
        var dsH = dsWithKmLabels(allH, allHDist);
        document.getElementById("hr-box").style.display = "";
        drawLineSvg("svg-hr", dsH.vals, "#e91e63", "bpm", dsH.labels, true);
        // Distribute movingTime equally across all HR track points for zone estimation.
        var secsPerPt = allH.length > 0 ? (movingTime || allH.length) / allH.length : 1;
        var gpxZonePts = [];
        for (i = 0; i < allH.length; i++) gpxZonePts.push({bpm: allH[i], secs: secsPerPt});
        renderHrEffort(gpxZonePts, maxHR, detail, "recorded HR samples");
        renderHrZones(gpxZonePts, maxHR);
        // Maximum-average HR curve needs the per-sample series (splits are too coarse).
        renderHrMaxAvg(allH, movingTime || allH.length);
      }

      if (allC.length) {
        var dsC = dsWithKmLabels(allC, allCDist);
        document.getElementById("cad-box").style.display = "";
        drawLineSvg("svg-cad", dsC.vals, "#8e24aa", "rpm", dsC.labels, true);
      }

      if (allT.length) {
        // Drop the first few km: device temperature sensors start at the storage/garage
        // temperature and only settle to ambient once riding — those early readings skew
        // the range. Keep everything on short rides that never pass the skip distance.
        var TEMP_SKIP_KM = 3;
        var tVals = [], tLabels = [];
        for (i = 0; i < allT.length; i++) {
          if (allTDist[i] >= TEMP_SKIP_KM) { tVals.push(allT[i]); tLabels.push(allTDist[i]); }
        }
        if (!tVals.length) { tVals = allT.slice(); tLabels = allTDist.slice(); }
        var loT = tVals[0], hiT = tVals[0], sumT = 0;
        for (i = 0; i < tVals.length; i++) { if (tVals[i] < loT) loT = tVals[i]; if (tVals[i] > hiT) hiT = tVals[i]; sumT += tVals[i]; }
        var dsT = dsWithKmLabels(tVals, tLabels);
        document.getElementById("temp-box").style.display = "";
        document.getElementById("temp-summary").textContent =
          "Min " + Math.round(loT) + " °C · Avg " + Math.round(sumT / tVals.length) + " °C · Max " + Math.round(hiT) + " °C";
        // Span the whole ride (0 … total km) so the temperature chart lines up with the others
        // even though its data starts after the skipped section.
        drawLineSvg("svg-temp", dsT.vals, "#f4511e", "°C", dsT.labels, true, 0, cumDist / 1000);
      }

      // Speed (km/h): instantaneous speed from consecutive points is too noisy to plot,
      // so smooth over a ~6 s centered window (distance ÷ time across the window).
      if (spTime.length > 1) {
        var allS = [], allSDist = [], SMOOTH_SEC = 6, m = spTime.length;
        for (i = 0; i < m; i++) {
          var a = i, b = i;
          while ((spTime[b] - spTime[a]) < SMOOTH_SEC && (a > 0 || b < m - 1)) {
            if (a > 0) a--;
            if (b < m - 1) b++;
          }
          var dt = spTime[b] - spTime[a], dd = spDist[b] - spDist[a];
          var mps = dt > 0 ? dd / dt : 0;
          if (!(mps > 0)) mps = 0;
          allS.push(mps * 3.6);
          allSDist.push(spKm[i]);
        }
        var dsS = dsWithKmLabels(allS, allSDist);
        document.getElementById("spd-box").style.display = "";
        drawLineSvg("svg-spd", dsS.vals, "#0288d1", "km/h", dsS.labels, true);
        // Fill the GPX-derived max-speed card (when the record carried no max_speed).
        var spCard = document.getElementById("gpx-maxspeed-card");
        if (spCard) {
          var maxS = 0;
          for (i = 0; i < allS.length; i++) { if (allS[i] > maxS) maxS = allS[i]; }
          if (maxS > 0) {
            spCard.querySelector(".v").textContent = isFoot(sport) ? fmtPace(maxS / 3.6) : maxS.toFixed(1) + " km/h";
            spCard.title = "Fastest speed from the GPX track (smoothed over 6 s).";
            spCard.style.display = "";
          }
        }
      }

      // Per-km splits computed from trkpts (lat/lon + time + ele + HR + cad)
      if (trkpts.length > 1) {
        var gpxSplits = [], KM = 1000;
        var segDist = 0, segTime = 0, segEle0 = null, segEleEnd = null;
        var segHrSum = 0, segHrN = 0, segCadSum = 0, segCadN = 0;
        var prevLat = null, prevLon = null, prevT = null;
        function ptEle(pt) { var el = pt.getElementsByTagNameNS("*","ele")[0]; return el ? parseFloat(el.textContent) : null; }
        function ptTime(pt) { var el = pt.getElementsByTagNameNS("*","time")[0]; return el ? new Date(el.textContent).getTime()/1000 : null; }
        function ptHr(pt) { var el = pt.getElementsByTagNameNS("*","hr")[0]||pt.getElementsByTagNameNS("*","heartrate")[0]; return el ? parseFloat(el.textContent)||0 : 0; }
        function ptCad(pt) { var el = pt.getElementsByTagNameNS("*","cad")[0]||pt.getElementsByTagNameNS("*","cadence")[0]; return el ? parseFloat(el.textContent)||0 : 0; }
        function flushSeg() {
          if (segDist < 50) return;
          gpxSplits.push({
            distance: segDist, moving_time: Math.round(segTime),
            elevation_difference: (segEle0 !== null && segEleEnd !== null) ? segEleEnd - segEle0 : null,
            average_heartrate: segHrN > 0 ? segHrSum / segHrN : null,
            average_cadence: segCadN > 0 ? segCadSum / segCadN : null
          });
        }
        for (i = 0; i < trkpts.length; i++) {
          var pt = trkpts[i];
          var lat = parseFloat(pt.getAttribute("lat")), lon = parseFloat(pt.getAttribute("lon"));
          var t = ptTime(pt), ele = ptEle(pt), hr = ptHr(pt), cad = ptCad(pt);
          if (segEle0 === null && ele !== null) segEle0 = ele;
          if (ele !== null) segEleEnd = ele;
          if (hr > 0) { segHrSum += hr; segHrN++; }
          if (cad > 0) { segCadSum += cad; segCadN++; }
          if (prevLat !== null) {
            var d2 = haversineM(prevLat, prevLon, lat, lon);
            var dt = (t !== null && prevT !== null) ? Math.max(0, t - prevT) : 0;
            segDist += d2; segTime += dt;
            if (segDist >= KM) {
              flushSeg();
              segDist = 0; segTime = 0; segEle0 = ele; segEleEnd = ele;
              segHrSum = 0; segHrN = 0; segCadSum = 0; segCadN = 0;
            }
          }
          prevLat = lat; prevLon = lon; prevT = t;
        }
        flushSeg(); // last partial km
        if (gpxSplits.length) {
          var splitsBox = document.getElementById("splits-box");
          splitsBox.style.display = "";
          var splitsNote = document.getElementById("gpx-splits-note");
          if (splitsNote) splitsNote.remove();
          renderSplitsFromArray(gpxSplits, sport || "", detailLineChartWidth(), true);
          if (typeof window._detailSecAfterRender === "function")
            window._detailSecAfterRender();
        } else {
          var splitsNote2 = document.getElementById("gpx-splits-note");
          if (splitsNote2) splitsNote2.textContent = "No GPS track points available for splits.";
        }
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
  if (d.gpx_file) { renderGpxMap(d.gpx_file, d.sport_type || d.type || "", d.max_single_climb || 0); return; }
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
    enableCoopGestures(map);
    var line = L.polyline(pts, { color: "#fc4c02", weight: 4, opacity: .9 }).addTo(map);
    leafletLine = line;
    map.fitBounds(line.getBounds(), { padding: [20, 20] });
    addDirectionArrows(map, pts);
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

function detailLineChartWidth() {
  var ids = ["svg-elev", "svg-hr", "svg-cad", "svg-pwr", "svg-spd", "svg-temp"];
  var width = 0;
  for (var i = 0; i < ids.length; i++) {
    var svg = document.getElementById(ids[i]);
    if (svg) width = Math.max(width, parseFloat(svg.style.width) || 0);
  }
  return width;
}

// distMode (GPX): position bars by cumulative distance on the same linear km axis
// as the elevation/speed line charts (shared PX_PER_KM + left gutter) so every
// chart's x-axis lines up. Otherwise bars are spaced evenly by split index.
function renderSplitsFromArray(splits, sport, chartWidth, distMode) {
  if (!splits.length) return;
  var foot = isFoot(sport);
  document.getElementById("splits-title").innerHTML = foot ? "Per-km pace" : "Per-km speed";

  var speeds = splits.map(function(s){
    return (s.moving_time > 0) ? (s.distance / s.moving_time) : (s.average_speed || 0);
  });
  var max = Math.max.apply(null, speeds) || 1;

  var n = splits.length, pad = 16, labelH = 16, PX_PER_KM = 30, YAX_W = 52;
  // Cumulative km at each split boundary (used by the distance axis).
  var cumKm = [0], di;
  for (di = 0; di < n; di++) cumKm.push(cumKm[di] + (splits[di].distance || 0) / 1000);
  var totalKm = cumKm[n] || 1;
  var xStart = distMode ? YAX_W : pad;  // match the line charts' y-axis gutter in distMode
  var W, evenBarW;
  if (distMode) {
    W = Math.max(xStart + Math.round(totalKm * PX_PER_KM) + pad, chartWidth || 0);
  } else {
    W = Math.max(pad*2 + n*30, chartWidth || 0);
    evenBarW = (W - pad*2) / n;
  }
  function barLeft(i){ return distMode ? (xStart + cumKm[i] * PX_PER_KM) : (xStart + i*evenBarW); }
  function barRight(i){ return distMode ? (xStart + cumKm[i+1] * PX_PER_KM) : (xStart + (i+1)*evenBarW); }
  var H = 200, chartH = H - labelH;
  var svg = document.getElementById("svg-splits");
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);
  svg.style.width = W + "px";

  TIP_DATA = [];
  var html = "";
  for (var i = 0; i < n; i++) {
    var s = splits[i], spd = speeds[i];
    var barH = Math.round((spd / max) * (chartH - 20));
    if (barH < 1) barH = 1;
    var xL = barLeft(i), xR = barRight(i), bw = xR - xL, xc = (xL + xR) / 2;
    var label = foot ? fmtPace(spd) : (spd*3.6).toFixed(1);
    var km = (s.distance/1000);

    var tip = '<strong>Km ' + (i+1) + '</strong>'
      + (km < 0.97 ? 'Distance: ' + km.toFixed(2) + ' km<br>' : '')
      + (foot ? 'Pace: ' + fmtPace(spd) : 'Speed: ' + (spd*3.6).toFixed(1) + ' km/h') + '<br>'
      + 'Time: ' + fmtTime(s.moving_time || s.elapsed_time || 0);
    if (s.elevation_difference != null) tip += '<br>Elev: ' + (s.elevation_difference>=0?'+':'') + Math.round(s.elevation_difference) + ' m';
    if (s.average_heartrate) tip += '<br>HR: ' + Math.round(s.average_heartrate) + ' bpm';
    if (s.average_cadence) tip += '<br>Cadence: ' + Math.round(s.average_cadence) + ' rpm';
    if (s.average_watts) tip += '<br>Power: ' + Math.round(s.average_watts) + ' W';
    TIP_DATA.push(tip);

    html += '<rect x="'+(xL+1)+'" y="'+(chartH-barH)+'" width="'+Math.max(1,(bw-2))+'" height="'+barH+'" fill="var(--accent)" rx="2"'
      + ' onmouseover="showTip(event,'+i+')" onmousemove="moveTip(event)" onmouseout="hideTip()"'
      + ' ontouchstart="showTip({clientX:event.touches[0].clientX,clientY:event.touches[0].clientY},'+i+')" ontouchend="setTimeout(hideTip,1500)"'
      + ' style="cursor:pointer"/>';
    html += '<text x="'+xc+'" y="'+(chartH-barH-4)+'" text-anchor="middle" font-size="8.5" fill="var(--text-2)">'+label+'</text>';
    html += '<text x="'+xc+'" y="'+(H-3)+'" text-anchor="middle" font-size="9" fill="var(--text-4)">'+(i+1)+'</text>';
  }
  svg.innerHTML = html;
}

function renderSplits(d){
  var sport = d.sport_type || d.type || "";
  // GPX activities: renderGpxCharts computes per-km splits from the track and fills splits-box.
  if (d.gpx_file) {
    var splitsBox = document.getElementById("splits-box");
    splitsBox.innerHTML = '<h3 id="splits-title">Per-km splits</h3>'
      + '<div class="chart-scroll"><svg class="splits" id="svg-splits" preserveAspectRatio="xMidYMid meet"></svg></div>'
      + '<div id="gpx-splits-note" class="note">Computing from GPS track…</div>';
    renderGpxCharts(d.gpx_file, d.max_heartrate || 0, d.moving_time || 0, sport, d.max_single_climb || 0, d);
    return;
  }
  var box = document.getElementById("splits-box");
  var splits = d.splits_metric || [];
  if (!splits.length) { box.innerHTML = '<h3>Splits</h3><div class="note">No splits recorded for this activity.</div>'; return; }

  // Whole-activity gradient distribution from per-km splits (no GPX track here).
  renderGradeDist(gradeBucketsFromSplits(splits));
  // Elevation, heart rate, cadence, and power charts from splits data (when available).
  renderElevFromSplits(splits);
  renderHrFromSplits(splits);
  renderCadFromSplits(splits);
  renderPowerFromSplits(splits);
  // Heart rate zones estimated from per-km split averages.
  var hrZonePts = [], zi;
  for (zi = 0; zi < splits.length; zi++) {
    if (splits[zi].average_heartrate > 0)
      hrZonePts.push({bpm: splits[zi].average_heartrate, secs: splits[zi].moving_time || 0});
  }
  renderHrEffort(hrZonePts, d.max_heartrate || 0, d, "per-km average HR");
  renderHrZones(hrZonePts, d.max_heartrate || 0);
  renderSplitsFromArray(splits, sport, detailLineChartWidth());
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
    if (current && !bikes.some(function(b){ return b.name === current; }))
      opts = '<option value="' + esc(current) + '" selected>' + esc(current) + '</option>' + opts;
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
  if(typeof window._detailSecAfterRender==='function')window._detailSecAfterRender();
}

function fail(msg){ progressDone(); hideMapSpin(); document.getElementById("err").textContent = msg; }

(function(){
  var root=document.documentElement,btn=document.getElementById('theme-tog');
  var saved=localStorage.getItem('theme');
  if(saved)root.dataset.theme=saved;
  function isDark(){return root.dataset.theme==='dark'||(!root.dataset.theme&&matchMedia('(prefers-color-scheme:dark)').matches);}
  function syncBtn(){btn.textContent=isDark()?'☀️':'🌙';}
  syncBtn();
  btn.onclick=function(){root.dataset.theme=isDark()?'light':'dark';localStorage.setItem('theme',root.dataset.theme);syncBtn();};
  matchMedia('(prefers-color-scheme:dark)').addEventListener('change',syncBtn);
})();

(function(){
  var DETAIL_SEC_KEY='ssb-detail-sec';
  var DETAIL_SEC_DEFAULT=['cards','map','climbprof','elev','cad','pwr','spd','temp','splits','hr','hrzone','hrmax'];
  var wrap=document.getElementById('sec-wrap');
  if(!wrap)return;
  var dragSrc=null;
  function getSecs(){return Array.prototype.filter.call(wrap.children,function(el){return el.classList.contains('sec');});}
  function saveOrder(){try{localStorage.setItem(DETAIL_SEC_KEY,JSON.stringify(getSecs().map(function(s){return s.getAttribute('data-sid');})));}catch(e){}}
  function applyOrder(){
    var saved=null;try{saved=JSON.parse(localStorage.getItem(DETAIL_SEC_KEY));}catch(e){}
    var order=(saved&&saved.length===DETAIL_SEC_DEFAULT.length)?saved:DETAIL_SEC_DEFAULT.slice();
    var secMap={};getSecs().forEach(function(s){secMap[s.getAttribute('data-sid')]=s;});
    order.forEach(function(sid){if(secMap[sid])wrap.appendChild(secMap[sid]);});
  }
  function doReset(){
    try{localStorage.removeItem(DETAIL_SEC_KEY);}catch(e){}
    var secMap={};getSecs().forEach(function(s){secMap[s.getAttribute('data-sid')]=s;});
    DETAIL_SEC_DEFAULT.forEach(function(sid){if(secMap[sid])wrap.appendChild(secMap[sid]);});
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
      var h=s.querySelector('h3');
      if(h)h.insertBefore(handle,h.firstChild);else s.insertBefore(handle,s.firstChild);
    });
  }
  applyOrder();
  injectHandles();
  window._detailSecAfterRender=injectHandles;
})();

(function(){
  var id = getId();
  if (!id) { fail("No activity id in the URL. Go back and click an activity."); return; }
  progressStart();
  Promise.all([
    fetch("details/" + id + ".json", { cache: "no-cache" })
      .then(function(r){
        if (r.status === 404) throw new Error("Detail for this activity hasn't been downloaded yet — it backfills over the next daily runs. Try again later.");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      }),
    fetch("activities.json", { cache: "no-cache" })
      .then(function(r){ return r.ok ? r.json() : {}; })
      .catch(function(){ return {}; })
  ]).then(function(res){
    progressDone();
    var d = res[0], meta = res[1];
    if (meta && meta.athleteAge) ATHLETE_AGE = meta.athleteAge;
    if (meta && meta.activities) {
      var act = meta.activities.find(function(a){ return String(a.id) === String(id); });
      if (act) {
        fillDetailFromActivity(d, act);
      }
    }
    render(d, id);
  }).catch(function(err){ fail(err.message); });
})();
</script>
<div class="meta" style="text-align:center;padding:.5rem 0 1rem"><a href="https://github.com/raczeja/StatsServiceBook" target="_blank" rel="noopener">StatsServiceBook on GitHub</a></div>
</body>
</html>
HTML

sed -i \
  -e "s/\\\"Ride\\\":[0-9]*/\\\"Ride\\\":$STRAVA_MY_CLIMB_MIN_GAIN_RIDE/" \
  -e "s/\\\"Run\\\":[0-9]*/\\\"Run\\\":$STRAVA_MY_CLIMB_MIN_GAIN_RUN/" \
  -e "s/\\\"Hike\\\":[0-9]*/\\\"Hike\\\":$STRAVA_MY_CLIMB_MIN_GAIN_HIKE/" \
  -e "s/\\\"Walk\\\":[0-9]*/\\\"Walk\\\":$STRAVA_MY_CLIMB_MIN_GAIN_WALK/" \
  -e "s/\\\"Other\\\":[0-9]*/\\\"Other\\\":$STRAVA_MY_CLIMB_MIN_GAIN_OTHER/" \
  -e "s/\\\"minDistance\\\":[0-9]*/\\\"minDistance\\\":$STRAVA_MY_CLIMB_MIN_DISTANCE/" \
  "$WEB_DIR/activity.html"
sed -i \
  -e "s/\\\"gRide\\\":[0-9]*/\\\"gRide\\\":$STRAVA_MY_CLIMB_MIN_GRADE_RIDE/" \
  -e "s/\\\"gRun\\\":[0-9]*/\\\"gRun\\\":$STRAVA_MY_CLIMB_MIN_GRADE_RUN/" \
  -e "s/\\\"gHike\\\":[0-9]*/\\\"gHike\\\":$STRAVA_MY_CLIMB_MIN_GRADE_HIKE/" \
  -e "s/\\\"gWalk\\\":[0-9]*/\\\"gWalk\\\":$STRAVA_MY_CLIMB_MIN_GRADE_WALK/" \
  -e "s/\\\"gOther\\\":[0-9]*/\\\"gOther\\\":$STRAVA_MY_CLIMB_MIN_GRADE_OTHER/" \
  -e "s/CLIMB_DESCENT_RESET = [0-9]*/CLIMB_DESCENT_RESET = $STRAVA_MY_CLIMB_DESCENT_RESET/" \
  "$WEB_DIR/activity.html"
