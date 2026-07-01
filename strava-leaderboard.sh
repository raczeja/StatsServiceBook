#!/bin/sh
# StravaStats for OpenWrt
# ------------------------
# Fetches a Strava club's recent-activities feed, accumulates the activities
# into a persistent store (dating each one by the day it was first seen, since
# the feed carries no dates), aggregates a leaderboard (mirroring
# server/src/services/stats.service.ts + activityStore.ts), and renders a static
# HTML dashboard plus JSON into uhttpd's web root. The dashboard lets you pick a
# year and month (defaulting to the current ones) and filters in the browser.
# Designed for low-RAM MIPS home routers running OpenWrt. Pure POSIX sh /
# BusyBox; deps: curl + jq.
#
# Run by cron once a day. See README.md for setup.

set -eu

STRAVA_LIBDIR="$(dirname "$0")"
# shellcheck disable=SC1090
. "$STRAVA_LIBDIR/strava-lib.sh"

CONFIG="${STRAVA_CONFIG:-/etc/strava-leaderboard.conf}"

[ -f "$CONFIG" ] || die "config not found: $CONFIG (copy config.example and edit it)"
# shellcheck disable=SC1090
. "$CONFIG"

: "${STRAVA_CLIENT_ID:?set STRAVA_CLIENT_ID in $CONFIG}"
: "${STRAVA_CLIENT_SECRET:?set STRAVA_CLIENT_SECRET in $CONFIG}"
: "${STRAVA_REFRESH_TOKEN:?set STRAVA_REFRESH_TOKEN in $CONFIG}"
: "${STRAVA_CLUB_ID:?set STRAVA_CLUB_ID in $CONFIG}"

SPORT_TYPE="${STRAVA_SPORT_TYPE:-}"                 # e.g. Run, Ride; "" = all sports
TOKEN_REFRESH_MARGIN="${STRAVA_TOKEN_REFRESH_MARGIN:-600}"  # refresh if the access token expires within this many seconds
MAX_PAGES="${STRAVA_MAX_PAGES:-5}"
PER_PAGE="${STRAVA_PER_PAGE:-200}"
WEB_DIR="${STRAVA_WEB_DIR:-/www/strava}"
STATE_DIR="${STRAVA_STATE_DIR:-/usr/lib/strava-leaderboard}"  # must survive reboot (NOT /tmp or /var on OpenWrt)
SNAPSHOT_DIR="$STATE_DIR/snapshots"
KEEP_SNAPSHOTS="${STRAVA_KEEP_SNAPSHOTS:-90}"

command -v curl >/dev/null 2>&1 || die "curl not installed (apk add curl ca-bundle  /  opkg install curl ca-bundle)"
command -v jq   >/dev/null 2>&1 || die "jq not installed (apk add jq  /  opkg install jq)"

mkdir -p "$WEB_DIR" "$SNAPSHOT_DIR"

TOKEN_STATE="$STATE_DIR/token.json"
STORE="$STATE_DIR/activities.ndjson"   # persistent accumulated activity store (append-only NDJSON)
TMP="$(mktemp -d "${TMPDIR:-/tmp}/strava.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- 1. Ensure a valid access token (see strava-lib.sh) -------------------
ensure_access_token

# --- 2. Page through the club activities feed ------------------------------
log "fetching club $STRAVA_CLUB_ID activities (up to $MAX_PAGES pages)..."
: > "$TMP/all.ndjson"
page=1
while [ "$page" -le "$MAX_PAGES" ]; do
  curl -fsS "https://www.strava.com/api/v3/clubs/$STRAVA_CLUB_ID/activities?per_page=$PER_PAGE&page=$page" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -o "$TMP/page.json" || die "activities fetch failed (page $page)"

  count="$(jq 'length' "$TMP/page.json" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || { log "page $page empty, stopping"; break; }

  jq -c '.[]' "$TMP/page.json" >> "$TMP/all.ndjson"
  log "page $page: $count activities"

  [ "$count" -lt "$PER_PAGE" ] && { log "short page, stopping"; break; }
  page=$((page + 1))
done

jq -s '.' "$TMP/all.ndjson" > "$TMP/fetched.json"
TOTAL="$(jq 'length' "$TMP/fetched.json")"
log "fetched $TOTAL activities total"

# --- 3. Merge the feed into the persistent activity store ------------------
# The club feed has no ids and no dates, so we dedupe by a content signature
# (athlete name + activity shape, mirroring activityStore.ts buildSignature)
# and stamp each newly seen activity with today's *local* date — its "first
# seen" day. With a daily cron and a feed that spans ~2 weeks, that date is the
# performed day to within the polling interval. The store is append-only NDJSON
# so writes stay cheap on flash; existing activities keep their original date.
#
# STRAVA_FIRST_SEEN_DATE (YYYY-MM-DD) overrides the stamp for this run — useful
# when first bootstrapping the store, to attribute the activities the feed
# currently shows to the month they were really performed (e.g. 2026-05-15)
# instead of install day. It only affects activities newly added this run.
FIRST_SEEN="${STRAVA_FIRST_SEEN_DATE:-$(date '+%Y-%m-%d')}"
case "$FIRST_SEEN" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) die "STRAVA_FIRST_SEEN_DATE must be YYYY-MM-DD, got: $FIRST_SEEN" ;;
esac
[ -f "$STORE" ] || : > "$STORE"

# Existing signatures, as a JSON array, for dedupe against what we already have.
jq -s '[ .[].signature ]' "$STORE" > "$TMP/known.json"

jq -c -n \
  --slurpfile known "$TMP/known.json" \
  --slurpfile fetched "$TMP/fetched.json" \
  --arg today "$FIRST_SEEN" '
  def sig:
    [ ((.athlete.firstname // "") | ascii_downcase),
      ((.athlete.lastname  // "") | ascii_downcase),
      ((.name // "")              | ascii_downcase),
      (.distance             // 0 | tostring),
      (.elapsed_time         // 0 | tostring),
      ((.sport_type // .type // "") | ascii_downcase)
    ] | join("|");
  ( ($known[0] // []) | map({ (.): true }) | add // {} ) as $seen
  | [ $fetched[0][] | { s: sig, a: . } ]
  | unique_by(.s)                       # collapse duplicates within this fetch
  | map(select($seen[.s] | not))        # drop activities already in the store
  | .[]
  | {
      signature:      .s,
      firstSeen:      $today,
      firstname:      (.a.athlete.firstname // ""),
      lastname:       (.a.athlete.lastname  // ""),
      profile_medium: (.a.athlete.profile_medium // ""),
      name:           (.a.name // ""),
      distance:       (.a.distance // 0),
      moving_time:    (.a.moving_time // 0),
      elapsed_time:   (.a.elapsed_time // 0),
      total_elevation_gain: (.a.total_elevation_gain // 0),
      type:           (.a.type // ""),
      sport_type:     (.a.sport_type // .a.type // "")
    }
' > "$TMP/new.ndjson"

ADDED="$(wc -l < "$TMP/new.ndjson" | tr -d ' ')"
cat "$TMP/new.ndjson" >> "$STORE"
TOTAL_STORED="$(wc -l < "$STORE" | tr -d ' ')"
log "store: +$ADDED new (firstSeen $FIRST_SEEN), $TOTAL_STORED activities total"

# --- 4. Emit dashboard JSON from the full store ----------------------------
# activities.json drives the interactive dashboard: a flat, sport-filtered list
# of per-activity records, each carrying its first-seen date so the browser can
# group/filter by year and month. leaderboard.json is the all-time aggregate,
# kept for the JSON link and the dated snapshots.
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
SPORT_LC="$(printf '%s' "$SPORT_TYPE" | tr '[:upper:]' '[:lower:]')"

jq -s --arg sport "$SPORT_LC" --arg generatedAt "$GENERATED_AT" '
  {
    generatedAt: $generatedAt,
    sport: (if $sport == "" then "all" else $sport end),
    activities: [
      .[]
      | select( ($sport == "") or (((.sport_type // .type) // "") | ascii_downcase) == $sport )
      | {
          date:           .firstSeen,
          firstname:      .firstname,
          lastname:       .lastname,
          profile_medium: .profile_medium,
          distance:       (.distance // 0),
          moving_time:    (.moving_time // 0),
          total_elevation_gain: (.total_elevation_gain // 0),
          sport_type:     .sport_type
        }
    ]
  }
' "$STORE" > "$WEB_DIR/activities.json"

# All-time leaderboard aggregate (mirrors stats.service.ts: group by
# firstname|lastname|profile_medium, sum distance/time/elevation, rank by
# distance, avg speed in km/h).
jq -s --arg sport "$SPORT_LC" --arg generatedAt "$GENERATED_AT" '
  def athleteKey: "\(.firstname)|\(.lastname)|\(.profile_medium // "")";
  ( [ .[]
      | select( ($sport == "") or (((.sport_type // .type) // "") | ascii_downcase) == $sport )
    ]
    | group_by(athleteKey)
    | map({
        firstname: .[0].firstname,
        lastname:  .[0].lastname,
        distance:        (map(.distance // 0)             | add),
        moving_time:     (map(.moving_time // 0)          | add),
        elevation_gain:  (map(.total_elevation_gain // 0) | add),
        activity_count:  length
      }
      | . + { average_speed: (if .moving_time > 0 then (.distance / .moving_time * 3.6) else 0 end) })
    | sort_by(-.distance)
    | to_entries | map(.value + { rank: (.key + 1) })
  ) as $members
  | {
      generatedAt: $generatedAt,
      sportType:  (if $sport == "" then null else $sport end),
      totals: {
        member_count:   ($members | length),
        distance:       ($members | map(.distance)       | add // 0),
        moving_time:    ($members | map(.moving_time)    | add // 0),
        elevation_gain: ($members | map(.elevation_gain) | add // 0),
        activity_count: ($members | map(.activity_count) | add // 0)
      },
      members: $members
    }
' "$STORE" > "$TMP/leaderboard.json"

STAMP="$(date '+%Y%m%d')"
cp "$TMP/leaderboard.json" "$SNAPSHOT_DIR/$STAMP.json"
cp "$TMP/leaderboard.json" "$WEB_DIR/leaderboard.json"

# prune old snapshots so daily runs don't fill the flash
ls -1t "$SNAPSHOT_DIR"/*.json 2>/dev/null | tail -n +"$((KEEP_SNAPSHOTS + 1))" | while read -r f; do
  rm -f "$f"
done

# --- 5. Render the static HTML dashboard -----------------------------------
# The page is a fixed template: it fetches activities.json and does all the
# year/month filtering and leaderboard aggregation in the browser, so changing
# the period needs no server. Written with a quoted heredoc so nothing here is
# shell-expanded — all the runtime values live in activities.json.
cat > "$WEB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Club Leaderboard</title>
<style>
  body{font-family:system-ui,Arial,sans-serif;margin:2rem auto;max-width:900px;padding:0 1rem;background:#fafafa;color:#222}
  h1{margin:0 0 .25rem}
  .meta{color:#666;font-size:.85rem;margin:.75rem 0 1rem}
  .filters{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;margin:.5rem 0 1rem}
  select{font:inherit;padding:.35rem .5rem;border:1px solid #ccc;border-radius:.4rem;background:#fff;color:#222}
  table{border-collapse:collapse;width:100%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08)}
  th,td{padding:.5rem .75rem;text-align:left;border-bottom:1px solid #eee}
  th{background:#fc4c02;color:#fff}
  tr:nth-child(even) td{background:#fafafa}
  td.num{text-align:right;font-variant-numeric:tabular-nums}
  .empty{color:#666;padding:1rem 0}
  .nav{margin:.25rem 0 1rem}
  .nav a{display:inline-block;padding:.4rem .75rem;background:#fc4c02;color:#fff;text-decoration:none;border-radius:.4rem;font-size:.85rem;font-weight:600}
  .nav a:hover{background:#e34402}
</style>
</head>
<body>
<h1>🏆 Club Leaderboard</h1>
<div class="nav"><a href="me/">→ My Activities</a></div>
<div class="filters">
  <label>Year <select id="year"></select></label>
  <label>Month <select id="month"></select></label>
</div>
<div class="meta" id="meta">Loading…</div>
<div id="board"></div>
<div class="meta">
  StravaStats for OpenWrt · history accumulated daily by cron, dated by when each
  activity was first seen · <a href="activities.json">activities.json</a> ·
  <a href="leaderboard.json">all-time JSON</a>
</div>
<script>
"use strict";
var MONTHS = ["January","February","March","April","May","June","July",
              "August","September","October","November","December"];
var yearSel = document.getElementById("year");
var monthSel = document.getElementById("month");
var meta = document.getElementById("meta");
var board = document.getElementById("board");
var DATA = null;

function fmtKm(m){ return (m/1000).toFixed(1); }
function fmtTime(s){ return Math.floor(s/3600) + "h " + Math.floor((s%3600)/60) + "m"; }
function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g, function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]; }); }

function fallbackToLatestMonth(acts, year, month) {
  var y = year, m = month;
  for (var i = 0; i < 24; i++) {
    var yy = y, mm = m;
    if (acts.some(function(a){ return a.date && +a.date.slice(0,4) === yy && +a.date.slice(5,7) === mm; }))
      return { year: yy, month: mm };
    m--; if (m === 0) { m = 12; y--; }
    if (y < 2000) break;
  }
  return null;
}

function init(){
  var acts = DATA.activities || [];
  var now = new Date();
  var curYear = now.getFullYear();
  var curMonth = now.getMonth() + 1; // 1-12

  // Years present in the data, plus the current year, newest first.
  var yset = {};
  acts.forEach(function(a){ yset[+a.date.slice(0,4)] = true; });
  yset[curYear] = true;
  var years = Object.keys(yset).map(Number).sort(function(a,b){ return b - a; });

  yearSel.innerHTML = years.map(function(y){
    return '<option value="' + y + '">' + y + '</option>';
  }).join("");
  yearSel.value = years.indexOf(curYear) >= 0 ? curYear : years[0];

  var opts = ['<option value="all">Whole year</option>'];
  for (var i = 0; i < 12; i++) opts.push('<option value="' + (i+1) + '">' + MONTHS[i] + '</option>');
  monthSel.innerHTML = opts.join("");
  monthSel.value = String(curMonth);

  // Step back to the most recent month with data when default period is empty.
  var _fb = fallbackToLatestMonth(acts, +yearSel.value, +monthSel.value);
  if (_fb) { yearSel.value = String(_fb.year); monthSel.value = String(_fb.month); }

  yearSel.onchange = render;
  monthSel.onchange = render;
  render();
}

function render(){
  var year = +yearSel.value;
  var month = monthSel.value; // "all" or "1".."12"
  var label = month === "all" ? String(year) : MONTHS[+month - 1] + " " + year;

  var rows = (DATA.activities || []).filter(function(a){
    if (+a.date.slice(0,4) !== year) return false;
    if (month !== "all" && +a.date.slice(5,7) !== +month) return false;
    return true;
  });

  // Aggregate by athlete (firstname|lastname|profile_medium).
  var map = {};
  rows.forEach(function(a){
    var k = a.firstname + "|" + a.lastname + "|" + (a.profile_medium || "");
    var e = map[k];
    if (!e) { e = map[k] = { firstname:a.firstname, lastname:a.lastname,
      distance:0, moving_time:0, elev:0, count:0 }; }
    e.distance += a.distance || 0;
    e.moving_time += a.moving_time || 0;
    e.elev += a.total_elevation_gain || 0;
    e.count += 1;
  });

  var members = Object.keys(map).map(function(k){ return map[k]; })
    .sort(function(x,y){ return y.distance - x.distance; });

  var totalDist = members.reduce(function(s,m){ return s + m.distance; }, 0);
  var totalActs = members.reduce(function(s,m){ return s + m.count; }, 0);
  var sport = DATA.sport || "all";

  meta.innerHTML = "Sport: " + esc(sport) + " · " + members.length + " athletes · " +
    totalActs + " activities · " + fmtKm(totalDist) + " km total · " + esc(label) +
    " · generated " + esc(DATA.generatedAt || "");

  if (members.length === 0) {
    board.innerHTML = '<div class="empty">No activities for ' + esc(label) + '.</div>';
    return;
  }

  var html = '<table><thead><tr><th>#</th><th>Athlete</th><th>Distance</th>' +
    '<th>Time</th><th>Elev (m)</th><th>Activities</th><th>Avg km/h</th></tr></thead><tbody>';
  members.forEach(function(m, i){
    var avg = m.moving_time > 0 ? (m.distance / m.moving_time * 3.6) : 0;
    html += '<tr><td class="num">' + (i+1) + '</td>' +
      '<td>' + esc(m.firstname) + ' ' + esc(m.lastname) + '</td>' +
      '<td class="num">' + fmtKm(m.distance) + ' km</td>' +
      '<td class="num">' + fmtTime(m.moving_time) + '</td>' +
      '<td class="num">' + Math.floor(m.elev) + '</td>' +
      '<td class="num">' + m.count + '</td>' +
      '<td class="num">' + avg.toFixed(1) + '</td></tr>';
  });
  html += '</tbody></table>';
  board.innerHTML = html;
}

fetch("activities.json", { cache: "no-store" })
  .then(function(r){ if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
  .then(function(d){ DATA = d; init(); })
  .catch(function(err){
    meta.textContent = "Failed to load activities.json (" + err.message +
      "). Open this page via the router's web server, not from a file.";
  });
</script>
</body>
</html>
HTML

log "wrote $WEB_DIR/index.html, $WEB_DIR/activities.json and $WEB_DIR/leaderboard.json (snapshot $STAMP)"
log "done."
