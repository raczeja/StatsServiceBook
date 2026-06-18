# strava-my-html-dashboard.sh — sourced by strava-my-activities.sh.
# Writes $WEB_DIR/index.html (the main activities dashboard).
# Quoted heredoc: nothing shell-expanded; all runtime data flows through
# activities.json which the page fetches and filters in the browser.

# --- 5. Render the static HTML dashboard ----------------------------------
cat > "$WEB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>My Activities</title>
<style>
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:1000px;padding:0 1rem;background:#fafafa;color:#222}
  h1{margin:0 0 .25rem}
  .meta{color:#666;font-size:.85rem;margin:.75rem 0 .5rem}
  .filters{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;margin:.5rem 0 .75rem}
  select{font:inherit;padding:.35rem .5rem;border:1px solid #ccc;border-radius:.4rem;background:#fff;color:#222}
  #resetFilters{font:inherit;padding:.35rem .5rem;border:1px solid #ccc;border-radius:.4rem;background:#fff;color:#666;cursor:pointer}
  #resetFilters:hover{border-color:#fc4c02;color:#fc4c02}
  .summary{margin:.25rem 0 .5rem;font-size:.95rem;color:#444;font-weight:500}
  .bests{display:flex;flex-wrap:wrap;gap:.4rem;margin:0 0 .75rem}
  .bests:empty{display:none}
  .best{background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);border-radius:.4rem;padding:.25rem .55rem;font-size:.82rem;color:#444;font-variant-numeric:tabular-nums;cursor:pointer}
  .best:hover{box-shadow:0 1px 3px rgba(252,76,2,.5)}
  .best b{color:#888;font-weight:600;font-size:.72rem;text-transform:uppercase;letter-spacing:.03em;margin-right:.35rem}
  @keyframes rowflash{from{background:#ffe2c2}to{background:transparent}}
  tr.flash td{animation:rowflash 1.8s ease-out}
  table{border-collapse:collapse;width:100%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08)}
  th,td{padding:.5rem .75rem;text-align:left;border-bottom:1px solid #eee}
  th{background:#fc4c02;color:#fff;cursor:pointer;user-select:none;white-space:nowrap}
  th.sorted-asc::after{content:" \2191"}
  th.sorted-desc::after{content:" \2193"}
  tr:nth-child(even) td{background:#fafafa}
  td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
  .clamp2{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:break-word}
  .empty{color:#666;padding:1rem 0}
  .charts{display:flex;flex-wrap:wrap;gap:1rem;margin:.5rem 0 .75rem}
  .chart-box{flex:1;min-width:260px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:.5rem .75rem}
  .chart-box--full{flex:0 0 100%}
  .chart-box h3{margin:0 0 .35rem;font-size:.85rem;color:#444;font-weight:600}
  svg.bar-chart{width:100%;height:150px;display:block}
  .chart-box--full svg.bar-chart{height:220px}
  #chart-tip{display:none;position:fixed;background:rgba(30,30,30,.93);color:#fff;padding:.45rem .7rem;border-radius:.4rem;font-size:.8rem;pointer-events:none;z-index:100;line-height:1.7;box-shadow:0 2px 8px rgba(0,0,0,.3)}
  #chart-tip strong{display:block;margin-bottom:.15rem;font-size:.85rem}
  #pbar{position:fixed;top:0;left:0;width:0;height:3px;background:#fc4c02;z-index:9999;pointer-events:none}
</style>
</head>
<body>
<div id="pbar"></div>
<div id="chart-tip"></div>
<h1>My Activities <a href="bike.html" style="font-size:.85rem;font-weight:400;vertical-align:middle;color:#fc4c02;text-decoration:none">🔧 Bike service</a> <a href="stats.html" style="font-size:.85rem;font-weight:400;vertical-align:middle;color:#fc4c02;text-decoration:none">📊 My Stats</a></h1>
<div class="filters">
  <label>Year <select id="year"></select></label>
  <label>Month <select id="month"></select></label>
  <label>Sport <select id="sport"></select></label>
  <button id="resetFilters" title="Reset all filters to defaults">↺ Reset</button>
</div>
<div class="meta" id="meta">Loading...</div>
<div class="summary" id="summary"></div>
<div class="bests" id="bests"></div>
<div class="charts">
  <div class="chart-box chart-box--full"><h3 id="title-dist">Distance (km)</h3><svg class="bar-chart" id="svg-dist" viewBox="0 0 360 110" preserveAspectRatio="none"></svg></div>
  <div class="chart-box"><h3 id="title-time">Time (h)</h3><svg class="bar-chart" id="svg-time" viewBox="0 0 360 110" preserveAspectRatio="none"></svg></div>
  <div class="chart-box"><h3 id="title-elev">Elevation (m)</h3><svg class="bar-chart" id="svg-elev" viewBox="0 0 360 110" preserveAspectRatio="none"></svg></div>
</div>
<div id="board"></div>
<div class="meta">
  StravaStats for OpenWrt &middot; individual activities updated daily by cron &middot;
  <a href="bike.html">🔧 Bike service</a> &middot;
  <a href="stats.html">📊 My Stats</a> &middot;
  <a href="activities.json">activities.json</a>
</div>
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
var MONTHS = ["January","February","March","April","May","June","July",
              "August","September","October","November","December"];

var TIP_DATA = [];
var tipEl = null;
function showTip(e, idx) {
  if (!tipEl) tipEl = document.getElementById("chart-tip");
  if (!TIP_DATA[idx]) return;
  tipEl.innerHTML = TIP_DATA[idx];
  tipEl.style.display = "block";
  moveTip(e);
}
function moveTip(e) {
  if (!tipEl) return;
  tipEl.style.left = (e.clientX + 16) + "px";
  tipEl.style.top  = (e.clientY - 10) + "px";
}
function hideTip() {
  if (!tipEl) tipEl = document.getElementById("chart-tip");
  tipEl.style.display = "none";
}
var yearSel  = document.getElementById("year");
var monthSel = document.getElementById("month");
var sportSel = document.getElementById("sport");
var metaEl   = document.getElementById("meta");
var summaryEl= document.getElementById("summary");
var bestsEl  = document.getElementById("bests");
var board    = document.getElementById("board");
var DATA      = null;
var BIKE_MODEL = null;
var sortCol  = "date";
var sortAsc  = false;

function saveFilter(){
  try { sessionStorage.setItem("activityFilter",JSON.stringify({year:yearSel.value,month:monthSel.value,sport:sportSel.value,sortCol:sortCol,sortAsc:sortAsc})); } catch(e){}
}

function fmtKm(m){ return (m/1000).toFixed(1); }
function fmtTime(s){
  var d = Math.floor(s/86400), h = Math.floor((s%86400)/3600), m = Math.floor((s%3600)/60);
  if (d > 0) return d + "d " + h + "h " + m + "m";
  return h > 0 ? h + "h " + m + "m" : m + "m";
}
// Integer with a space as thousands separator: 2255 -> "2 255".
function fmtInt(n){
  return Math.round(n||0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}
// ISO/UTC timestamp -> local "YYYY-MM-DD HH:MM" (no seconds).
function fmtGenerated(iso){
  if (!iso) return "";
  var d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  function p(n){ return (n<10?"0":"")+n; }
  return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate())+
    " "+p(d.getHours())+":"+p(d.getMinutes());
}
// Inclusive calendar span between two "YYYY-MM-DD" dates -> "1 year 3 months".
function fmtSpan(first, last){
  if (!first || !last) return "";
  var ay=+first.slice(0,4), am=+first.slice(5,7);
  var by=+last.slice(0,4),  bm=+last.slice(5,7);
  var months = (by-ay)*12 + (bm-am) + 1;        // inclusive of both end months
  if (months < 1) months = 1;
  var y = Math.floor(months/12), m = months%12, parts = [];
  if (y) parts.push(y+" year"+(y>1?"s":""));
  if (m) parts.push(m+" month"+(m>1?"s":""));
  return parts.join(" ");
}
function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g, function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }

// Identify the primary gear (highest all-time distance) once; stable across filters.
var _defGear = null;
function defGear(){
  if (_defGear !== null) return _defGear;
  var rides = (DATA.activities || []).filter(function(a){ return a.sport_type === "Ride"; });
  var dist = {};
  rides.forEach(function(r){ var g = r.gear_id; if (g) dist[g] = (dist[g]||0) + (r.distance||0); });
  var best = "", max = 0;
  Object.keys(dist).forEach(function(g){ if (dist[g] > max){ max = dist[g]; best = g; } });
  _defGear = best;
  return _defGear;
}

// Compute km for the primary bike within a filtered activity set.
// Untagged rides are attributed to the primary gear, matching bike.html logic.
function computeKrossOdo(filteredActs){
  if (!DATA) return null;
  var g = defGear();
  if (!g) return null;
  var name = ((DATA.gears||{})[g]||{}).name || g;
  var km = 0;
  filteredActs.forEach(function(a){
    if (a.sport_type !== "Ride") return;
    if ((a.gear_id || g) === g) km += (a.distance||0) / 1000;
  });
  return { name: name, km: km };
}

function init(){
  var acts = DATA.activities || [];

  // Derive VAM (vertical ascent m/h) and coalesce optional metrics to numbers
  // once, so the table can render and sort them like any other numeric column.
  acts.forEach(function(a){
    a.vam = (a.total_elevation_gain > 0 && a.moving_time > 0)
      ? a.total_elevation_gain * 3600 / a.moving_time : 0;
    a.average_heartrate = a.average_heartrate || 0;
    a.average_watts     = a.average_watts || 0;
    a.kilojoules        = a.kilojoules || 0;
    a.calories          = a.calories || 0;
  });

  var now = new Date();
  var curYear = now.getFullYear();
  var curMonth = now.getMonth() + 1;

  var yset = {};
  acts.forEach(function(a){ if (a.date) yset[+a.date.slice(0,4)] = true; });
  yset[curYear] = true;
  var years = Object.keys(yset).map(Number).sort(function(a,b){ return b-a; });

  var yOpts = ['<option value="all">All years</option>'];
  years.forEach(function(y){ yOpts.push('<option value="'+y+'">'+y+'</option>'); });
  yearSel.innerHTML = yOpts.join("");
  yearSel.value = years.indexOf(curYear) >= 0 ? curYear : years[0];

  var mOpts = ['<option value="all">Whole year</option>'];
  for (var i=0;i<12;i++) mOpts.push('<option value="'+(i+1)+'">'+MONTHS[i]+'</option>');
  monthSel.innerHTML = mOpts.join("");
  monthSel.value = String(curMonth);

  // Sport types discovered from the data, sorted alphabetically.
  var sset = {};
  acts.forEach(function(a){ if (a.sport_type) sset[a.sport_type] = true; });
  var sports = Object.keys(sset).sort();
  var sOpts = ['<option value="all">All sports</option>'];
  sports.forEach(function(s){ sOpts.push('<option value="'+esc(s)+'">'+esc(s)+'</option>'); });
  sportSel.innerHTML = sOpts.join("");
  sportSel.value = sset["Ride"] ? "Ride" : "all";

  // Restore filter + sort state saved before navigating to activity detail.
  var _saved = sessionStorage.getItem("activityFilter");
  if (_saved) {
    try {
      var _st = JSON.parse(_saved);
      if (_st.year  !== undefined) yearSel.value  = _st.year;
      if (_st.month !== undefined) monthSel.value = _st.month;
      if (_st.sport !== undefined) sportSel.value = _st.sport;
      if (_st.sortCol)             sortCol        = _st.sortCol;
      if (_st.sortAsc !== undefined) sortAsc      = !!_st.sortAsc;
    } catch(e) {}
  }

  yearSel.onchange  = function(){ saveFilter(); render(); };
  monthSel.onchange = function(){ saveFilter(); render(); };
  sportSel.onchange = function(){ saveFilter(); render(); };
  document.getElementById("resetFilters").onclick = function() {
    try { sessionStorage.removeItem("activityFilter"); } catch(e) {}
    sortCol = "date";
    sortAsc = false;
    init();
  };
  render();
}

var MON_ABB = ["J","F","M","A","M","J","J","A","S","O","N","D"];

function drawBars(svgId, vals, selMonth, decimals, avg, tooltipData) {
  var svg = document.getElementById(svgId);
  if (!svg) return;
  var max = Math.max.apply(null, vals) || 1;
  var W = 360, H = 110, pad = 14, barW = (W - pad*2) / 12, labelH = 16;
  var chartH = H - labelH;
  var html = "";
  if (tooltipData) TIP_DATA = tooltipData;
  for (var i = 0; i < vals.length; i++) {
    var v = vals[i];
    var barH = Math.round((v / max) * (chartH - 6));
    var x = pad + i * barW;
    var opacity = (selMonth === "all" || +selMonth - 1 === i) ? 1 : 0.25;
    var label = v > 0 ? (decimals ? v.toFixed(1) : Math.round(v)) : "";
    var labelY = chartH - barH - 3;
    if (barH > 0) {
      var tipAttrs = tooltipData && tooltipData[i]
        ? ' onmouseover="showTip(event,'+i+')" onmousemove="moveTip(event)" onmouseout="hideTip()" style="cursor:pointer"'
        : '';
      html += '<rect x="'+(x+1)+'" y="'+(chartH-barH)+'" width="'+(barW-2)+'" height="'+barH+'" fill="#fc4c02" opacity="'+opacity+'" rx="2"'+tipAttrs+'/>';
      if (label && barH > 12) {
        html += '<text x="'+(x+barW/2)+'" y="'+(labelY < 9 ? 9 : labelY)+'" text-anchor="middle" font-size="8.5" fill="#444">'+label+'</text>';
      }
    }
    html += '<text x="'+(x+barW/2)+'" y="'+(H-2)+'" text-anchor="middle" font-size="9" fill="#888">'+MON_ABB[i]+'</text>';
  }
  if (avg != null && avg > 0) {
    var avgY = Math.round(chartH - (avg / max) * (chartH - 6));
    html += '<line x1="'+pad+'" y1="'+avgY+'" x2="'+(W-pad)+'" y2="'+avgY+'" stroke="#f5c400" stroke-width="1.5" stroke-dasharray="4,3"/>';
  }
  svg.innerHTML = html;
}

function renderCharts(rows, selMonth, year) {
  var monthly = [];
  for (var i = 0; i < 12; i++) monthly.push({dist: 0, time: 0, elev: 0});
  rows.forEach(function(a) {
    var m = a.date ? +a.date.slice(5, 7) - 1 : -1;
    if (m >= 0 && m < 12) {
      monthly[m].dist += a.distance || 0;
      monthly[m].time += a.moving_time || 0;
      monthly[m].elev += a.total_elevation_gain || 0;
    }
  });

  var distVals = monthly.map(function(m) { return m.dist / 1000; });
  var timeVals = monthly.map(function(m) { return m.time / 3600; });
  var elevVals = monthly.map(function(m) { return m.elev; });

  // Bars always show the real accumulated total — including the current,
  // partly-elapsed month. The avg line is ONE monthly average that blends
  // completed months (each counts as a whole month) with the current month
  // weighted only by how much of it has elapsed (in whole weeks). When viewing
  // the current year we work out the current month's elapsed fraction; past
  // years have no partial month, so the average is just the plain monthly mean.
  var now = new Date();
  var curMonthIdx = -1, weeksElapsed = 0, weeksInMonth = 0, avgFraction = 1;
  if (year === now.getFullYear()) {
    curMonthIdx = now.getMonth();
    var daysInMonth = new Date(now.getFullYear(), curMonthIdx + 1, 0).getDate();
    weeksInMonth = Math.ceil(daysInMonth / 7);     // whole-week buckets (4 or 5)
    weeksElapsed = Math.ceil(now.getDate() / 7);   // bucket the current day falls in
    avgFraction = Math.min(weeksElapsed / weeksInMonth, 1);
  }

  // Completion-weighted monthly average: total ÷ effective months. Each active
  // completed month adds its value to the numerator and 1 month to the
  // denominator; the current month adds its real value but only `avgFraction`
  // of a month. So a month that is on its usual pace leaves the average
  // unchanged — it is never dragged down just because only the first week has
  // elapsed, nor inflated by extrapolating a tiny early sample.
  function blendedAvg(vals) {
    var num = 0, den = 0;
    for (var i = 0; i < vals.length; i++) {
      if (vals[i] > 0) {
        num += vals[i];
        den += (i === curMonthIdx) ? avgFraction : 1;
      }
    }
    return den > 0 ? num / den : null;
  }
  var distAvg = blendedAvg(distVals);
  var timeAvg = blendedAvg(timeVals);
  var elevAvg = blendedAvg(elevVals);

  function setChartTitle(id, base, avg, decimals) {
    var el = document.getElementById(id);
    if (!el) return;
    var avgStr = avg != null && avg > 0
      ? ', <span style="color:#f5c400;font-weight:400">avg ' + (decimals ? avg.toFixed(1) : Math.round(avg)) + '</span>'
      : '';
    el.innerHTML = base + avgStr;
  }
  setChartTitle("title-dist", "Distance (km)", distAvg, 1);
  setChartTitle("title-time", "Time (h)", timeAvg, 1);
  setChartTitle("title-elev", "Elevation (m)", elevAvg, 0);

  var avgLine = distAvg != null
    ? ' &nbsp;<span style="color:#f5c400">avg ' + distAvg.toFixed(1) + ' km</span>'
    : '';
  var tooltipData = monthly.map(function(m, i) {
    if (m.dist === 0) return null;
    var tip = '<strong>' + MONTHS[i] + '</strong>' +
      'Distance: ' + (m.dist / 1000).toFixed(1) + ' km' + avgLine + '<br>' +
      'Time: ' + fmtTime(m.time) + '<br>' +
      'Elevation: ' + Math.round(m.elev) + ' m';
    if (i === curMonthIdx) {
      tip += '<br><span style="color:#aaa">in progress · week ' + weeksElapsed +
        ' of ' + weeksInMonth + '</span>';
    }
    return tip;
  });

  drawBars("svg-dist", distVals, selMonth, 1, distAvg, tooltipData);
  drawBars("svg-time", timeVals, selMonth, 1, timeAvg);
  drawBars("svg-elev", elevVals, selMonth, 0, elevAvg);
}

var COLS       = ["date","name","sport_type","distance","moving_time","total_elevation_gain","average_speed","max_speed","vam","average_heartrate","average_watts","kilojoules"];
var COL_LABELS = ["Date","Name","Sport","Distance","Time","Elev (m)","Avg km/h","Max km/h","VAM","Avg HR","Avg W","kJ"];
// Hover explanations for the less-obvious columns (shown as native tooltips).
var COL_TIPS   = {
  vam:               "VAM — average climbing speed in vertical metres per hour (elevation gain ÷ moving time). Higher means you climbed faster.",
  average_heartrate: "Average heart rate (bpm), when recorded.",
  average_watts:     "Average power output (W), when a power meter is present.",
  kilojoules:        "Work done (kJ) — mechanical energy output over the ride, when power is recorded."
};

// Scroll the table to a given activity and briefly highlight its row. Called
// from the "bests" chips; exposed on window so the inline onclick can reach it.
function focusRow(id){
  var tr = board.querySelector('tr[data-id="'+id+'"]');
  if (!tr) return;
  tr.scrollIntoView({ behavior: "smooth", block: "center" });
  tr.classList.add("flash");
  setTimeout(function(){ tr.classList.remove("flash"); }, 1800);
}
window.focusRow = focusRow;

function sortRows(rows){
  var col = sortCol, asc = sortAsc;
  rows.sort(function(a,b){
    var av = a[col], bv = b[col];
    if (av == null) av = ""; if (bv == null) bv = "";
    if (typeof av === "number" && typeof bv === "number") return asc ? av-bv : bv-av;
    av = String(av).toLowerCase(); bv = String(bv).toLowerCase();
    return av < bv ? (asc?-1:1) : av > bv ? (asc?1:-1) : 0;
  });
  return rows;
}

function render(){
  var year  = yearSel.value === "all" ? "all" : +yearSel.value;
  var month = monthSel.value;
  var sport = sportSel.value;
  var label;
  if (year === "all") label = month === "all" ? "All years" : MONTHS[+month-1]+" · all years";
  else                label = month === "all" ? String(year) : MONTHS[+month-1]+" "+year;
  if (sport !== "all") label += " · "+sport;

  var rows = (DATA.activities || []).filter(function(a){
    if (!a.date) return false;
    if (year !== "all" && +a.date.slice(0,4) !== year) return false;
    if (month !== "all" && +a.date.slice(5,7) !== +month) return false;
    if (sport !== "all" && a.sport_type !== sport) return false;
    return true;
  });

  rows = sortRows(rows);

  var totalDist = 0, totalTime = 0, totalElev = 0, first = null, last = null;
  rows.forEach(function(a){
    totalDist += a.distance||0;
    totalTime += a.moving_time||0;
    totalElev += a.total_elevation_gain||0;
    if (a.date){ if (!first || a.date < first) first = a.date; if (!last || a.date > last) last = a.date; }
  });

  metaEl.innerHTML = esc(label)+" &middot; "+rows.length+" activities &middot; generated "+esc(fmtGenerated(DATA.generatedAt||""));

  var yearRows = (DATA.activities || []).filter(function(a) {
    if (!a.date) return false;
    if (year !== "all" && +a.date.slice(0,4) !== year) return false;
    if (sport !== "all" && a.sport_type !== sport) return false;
    return true;
  });
  renderCharts(yearRows, month, year);

  if (rows.length === 0){
    summaryEl.textContent = "";
    bestsEl.innerHTML = "";
    board.innerHTML = '<div class="empty">No activities for '+esc(label)+'.</div>';
    return;
  }

  var span = fmtSpan(first, last);
  var odo = computeKrossOdo(rows);
  summaryEl.textContent = fmtInt(totalDist/1000)+" km · "+fmtTime(totalTime)+" · "+fmtInt(totalElev)+" m elev"+
    (span ? " · "+span : "") +
    (odo ? " · "+odo.name+": "+fmtInt(odo.km)+" km" : "");

  // Period "bests": the standout single activity for each metric. Only shown
  // when there is more than one activity, where a comparison is meaningful.
  bestsEl.innerHTML = "";
  if (rows.length >= 2) {
    var maxBy = function(fn){
      var best = null, bestV = 0;
      rows.forEach(function(a){ var v = fn(a) || 0; if (v > bestV){ bestV = v; best = a; } });
      return best;
    };
    // Each chip explains its metric, names the activity, and links to its row:
    // clicking scrolls the table to it and flashes the row.
    var chip = function(a, label, val, tip){
      var who = (a.name || "activity") + (a.date ? " · " + a.date : "");
      return '<span class="best" data-id="'+esc(a.id)+'" onclick="focusRow(\''+a.id+'\')" '+
        'title="'+esc(tip + " — " + who + " · click to highlight it in the table")+'">'+
        '<b>'+label+'</b>'+val+'</span>';
    };
    var chips = [];
    var bLong  = maxBy(function(a){ return a.distance; });
    var bClimb = maxBy(function(a){ return a.total_elevation_gain; });
    var bSpeed = maxBy(function(a){ return a.average_speed; });
    var bVam   = maxBy(function(a){ return a.vam; });
    var bCal   = maxBy(function(a){ return a.calories; });
    if (bLong)  chips.push(chip(bLong,  "Longest", fmtKm(bLong.distance)+" km",
      "Longest single activity by distance"));
    if (bClimb) chips.push(chip(bClimb, "Most climbing", fmtInt(bClimb.total_elevation_gain)+" m",
      "Single activity with the most total elevation gain"));
    if (bSpeed) chips.push(chip(bSpeed, "Fastest avg", (bSpeed.average_speed*3.6).toFixed(1)+" km/h",
      "Highest average speed"));
    if (bVam)   chips.push(chip(bVam,   "Best VAM", fmtInt(bVam.vam)+" m/h",
      "VAM — best average climbing speed in vertical metres per hour (elevation gain ÷ moving time)"));
    if (bCal)   chips.push(chip(bCal,   "Most calories", fmtInt(bCal.calories)+" kcal",
      "Single activity that burned the most calories"));
    // Temperature needs its own scan: it has a meaningful minimum and can be
    // zero or negative, so maxBy (which seeds at 0) can't find these.
    var bCold = null, bHot = null;
    rows.forEach(function(a){
      if (a.average_temp == null) return;
      if (!bCold || a.average_temp < bCold.average_temp) bCold = a;
      if (!bHot  || a.average_temp > bHot.average_temp)  bHot  = a;
    });
    if (bCold && bHot && bCold !== bHot) {
      chips.push(chip(bCold, "Coldest", Math.round(bCold.average_temp)+" °C",
        "Single activity with the lowest average temperature"));
      chips.push(chip(bHot,  "Hottest", Math.round(bHot.average_temp)+" °C",
        "Single activity with the highest average temperature"));
    }
    bestsEl.innerHTML = chips.join("");
  }

  var thHtml = "<tr>";
  COLS.forEach(function(c,i){
    var cls = c===sortCol ? (' class="sorted-'+(sortAsc?"asc":"desc")+'"') : "";
    var tip = COL_TIPS[c] ? ' title="'+esc(COL_TIPS[c])+'"' : "";
    thHtml += '<th data-col="'+c+'"'+cls+tip+'>'+COL_LABELS[i]+'</th>';
  });
  thHtml += "</tr>";

  var html = "<table><thead>"+thHtml+"</thead><tbody>";
  rows.forEach(function(a){
    var avg  = a.average_speed > 0 ? (a.average_speed*3.6).toFixed(1) : "&mdash;";
    var maxs = a.max_speed > 0 ? (a.max_speed*3.6).toFixed(1) : "&mdash;";
    var vam  = a.vam > 0 ? fmtInt(a.vam) : "&mdash;";
    var hr   = a.average_heartrate > 0 ? Math.round(a.average_heartrate) : "&mdash;";
    var pw   = a.average_watts > 0 ? Math.round(a.average_watts) : "&mdash;";
    var kj   = a.kilojoules > 0 ? fmtInt(a.kilojoules) : "&mdash;";
    var nameCell = a.detail
      ? '<a href="activity.html?id='+encodeURIComponent(a.id)+'" title="Activity detail" class="clamp2">'+esc(a.name||"")+'</a>'
      : '<span class="clamp2">'+esc(a.name||"")+'</span>';
    html += '<tr data-id="'+esc(a.id)+'">'+
      '<td style="white-space:nowrap">'+esc(a.date||"")+"</td>"+
      "<td>"+nameCell+"</td>"+
      "<td>"+esc(a.sport_type||"")+"</td>"+
      '<td class="num">'+fmtKm(a.distance)+" km</td>"+
      '<td class="num">'+fmtTime(a.moving_time)+"</td>"+
      '<td class="num">'+Math.floor(a.total_elevation_gain||0)+"</td>"+
      '<td class="num">'+avg+"</td>"+
      '<td class="num">'+maxs+"</td>"+
      '<td class="num">'+vam+"</td>"+
      '<td class="num">'+hr+"</td>"+
      '<td class="num">'+pw+"</td>"+
      '<td class="num">'+kj+"</td>"+
      "</tr>";
  });
  html += "</tbody></table>";
  board.innerHTML = html;

  // Attach sort handlers after innerHTML is set.
  var ths = board.querySelectorAll("th[data-col]");
  for (var i=0; i<ths.length; i++){
    ths[i].onclick = (function(th){
      return function(){
        var col = th.getAttribute("data-col");
        if (sortCol === col){ sortAsc = !sortAsc; }
        else { sortCol = col; sortAsc = (col==="name"||col==="sport_type"); }
        saveFilter();
        render();
      };
    })(ths[i]);
  }

}

progressStart();
fetch("activities.json", { cache:"no-store" })
  .then(function(r){ if (!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
  .then(function(d){
    DATA = d;
    return fetch("/cgi-bin/bike-service", { cache:"no-store" })
      .then(function(r){ return r.ok ? r.json() : null; })
      .catch(function(){ return null; });
  })
  .then(function(bm){ BIKE_MODEL = bm; progressDone(); init(); })
  .catch(function(err){
    progressDone();
    metaEl.textContent = "Failed to load activities.json ("+err.message+
      "). Open this page via the router's web server, not from a file.";
  });
</script>
</body>
</html>
HTML
