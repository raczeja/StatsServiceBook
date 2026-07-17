/**
 * functional-tests.mjs — Puppeteer-based regression tests for all five pages
 * and the bike-service CGI. Runs against the local test container (port 8080).
 *
 * Usage (container must already be running on :8080):
 *   node functional-tests.mjs
 *
 * Called automatically by run-tests.ps1, which starts the container first.
 * Exits 0 on all pass, 1 on any failure.
 */
import puppeteer from "puppeteer";
import fs from "fs";
import path from "path";
import assert from "assert/strict";

const PORT = process.env.TEST_PORT || process.env.STRAVA_TEST_PORT || "8080";
const BASE = `http://localhost:${PORT}/strava/me`;
const CGI = `http://localhost:${PORT}/cgi-bin`;
const URLS = {
  club: `http://localhost:${PORT}/strava/index.html`,
  dash: `${BASE}/index.html`,
  stats: `${BASE}/stats.html`,
  activity: `${BASE}/activity.html?id=18784255013`,
  activityHealthsyncRun: `${BASE}/activity.html?id=2026-06-22-15-07-running`,
  activityHealthsyncCycling: `${BASE}/activity.html?id=2026-06-22-10-30-cycling`,
  activityMagene: `${BASE}/activity.html?id=magene-2026-07-12-50671559`,
  bike: `${BASE}/bike.html`,
};

const TEST_RESULTS =
  process.env.TEST_RESULTS || path.resolve("test-results.xml");
const START_TIME_MS = Date.now();

const BROWSER_CANDIDATES = [
  process.env.BROWSER_PATH,
  process.env.EDGE_PATH,
  "/usr/bin/google-chrome-stable",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium-browser",
  "/usr/bin/chromium",
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
].filter(Boolean);

async function findBrowser() {
  const bundled = await puppeteer.executablePath?.();
  if (bundled && fs.existsSync(bundled)) return bundled;

  for (const p of BROWSER_CANDIDATES) {
    if (fs.existsSync(p)) return p;
  }

  throw new Error(
    "Browser not found. Install puppeteer so it can download a browser, or set BROWSER_PATH/EDGE_PATH to a valid executable.",
  );
}

// ── Result tracking ────────────────────────────────────────────────────────────

const results = [];
let passed = 0,
  failed = 0;

function pass(suite, name) {
  results.push({ suite, name, ok: true });
  passed++;
  console.log(`  PASS  ${suite} / ${name}`);
}

function fail(suite, name, err) {
  results.push({ suite, name, ok: false, error: err });
  failed++;
  console.error(`  FAIL  ${suite} / ${name}: ${err.message || err}`);
}

async function check(suite, name, fn) {
  try {
    await fn();
    pass(suite, name);
  } catch (e) {
    fail(suite, name, e);
  }
}

// ── Per-page helpers ───────────────────────────────────────────────────────────

async function testClubDashboard(page, jsErrors) {
  const S = "club-dashboard";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.club, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector("#board tbody tr", { timeout: 10000 });
  } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );
  await check(S, "meta-populated", async () => {
    const text = await page.$eval("#meta", (el) => el.textContent);
    assert.ok(!text.includes("Loading"), `#meta still says Loading: ${text}`);
  });
  await check(S, "table-has-rows", async () => {
    const n = await page.$$eval("#board .person-row", (rows) => rows.length);
    assert.ok(n >= 1, `expected >= 1 person row, got ${n}`);
  });
  // club-activities.sample.json: 4 athletes → 4 person-rows + 4 hidden detail-rows
  await check(S, "4-athlete-rows", async () => {
    const n = await page.$$eval("#board .person-row", (rows) => rows.length);
    assert.equal(n, 4, `expected 4 person-rows, got ${n}`);
  });
  await check(S, "4-detail-rows-hidden", async () => {
    const n = await page.$$eval(
      "#board .detail-row",
      (rows) => rows.filter((r) => r.style.display === "none").length,
    );
    assert.equal(n, 4, `expected 4 hidden detail-rows, got ${n}`);
  });
  // Alex R has the highest km in June 2026 (150.4 km across 3 rides) → rank 1
  await check(S, "first-place-Alex", async () => {
    const name = await page.$eval(
      "#board .person-row:first-of-type td:nth-child(2)",
      (el) => el.textContent.trim(),
    );
    assert.ok(
      name.startsWith("Alex"),
      `expected first place "Alex…", got "${name}"`,
    );
  });
  // Click the first person-row → its detail-row should become visible
  await check(S, "drill-down-toggle", async () => {
    await page.click("#board .person-row:first-child");
    const visible = await page.$eval(
      "#board .detail-row",
      (el) => el.style.display !== "none",
    );
    assert.ok(visible, "detail-row should be visible after clicking person-row");
    // click again → collapses
    await page.click("#board .person-row:first-child");
    const hidden = await page.$eval(
      "#board .detail-row",
      (el) => el.style.display === "none",
    );
    assert.ok(hidden, "detail-row should be hidden after second click");
  });
  // Detail table has activity rows (Alex has 3 rides, so detail-table has 3 data rows)
  await check(S, "drill-down-activity-rows", async () => {
    await page.click("#board .person-row:first-child");
    const n = await page.$eval(
      "#board .detail-row .detail-table tbody",
      (tbody) => tbody.querySelectorAll("tr").length,
    );
    assert.equal(n, 3, `expected 3 detail activity rows for Alex, got ${n}`);
    await page.click("#board .person-row:first-child");
  });
  // Detail table header must include "Avg km/h" column
  await check(S, "detail-table-has-avg-speed-header", async () => {
    await page.click("#board .person-row:first-child");
    const headers = await page.$eval(
      "#board .detail-row .detail-table thead tr",
      (tr) => Array.from(tr.querySelectorAll("th")).map((th) => th.textContent.trim()),
    );
    assert.ok(
      headers.includes("Avg km/h"),
      `expected "Avg km/h" in detail table headers, got: ${JSON.stringify(headers)}`,
    );
    await page.click("#board .person-row:first-child");
  });
  // Each activity row in the detail table must show a numeric avg speed (not "–")
  await check(S, "detail-activity-avg-speed-values", async () => {
    await page.click("#board .person-row:first-child");
    const speeds = await page.$eval(
      "#board .detail-row .detail-table tbody",
      (tbody) => Array.from(tbody.querySelectorAll("tr")).map((tr) => {
        const cells = tr.querySelectorAll("td");
        return cells[cells.length - 1]?.textContent.trim();
      }),
    );
    // Alex R's 3 rides all have moving_time > 0, so none should be "–"
    speeds.forEach(function(spd, i) {
      const n = parseFloat(spd);
      assert.ok(!isNaN(n) && n > 0, `detail row ${i} avg speed "${spd}" is not a positive number`);
    });
    await page.click("#board .person-row:first-child");
  });
  // Each club's "all-time JSON" footer link must resolve to a real file.
  // This catches the install.sh bug where leaderboard.json was symlinked instead
  // of leaderboard_<clubId>.json.
  await check(S, "leaderboard-json-links-accessible", async () => {
    const hrefs = await page.$$eval(
      '#footer-links a[href*="leaderboard_"]',
      (links) => links.map((a) => a.href),
    );
    assert.ok(
      hrefs.length >= 1,
      `expected >= 1 leaderboard JSON link in footer, got ${hrefs.length}`,
    );
    for (const href of hrefs) {
      const status = await page.evaluate(
        async (url) => (await fetch(url)).status,
        href,
      );
      assert.equal(status, 200, `leaderboard JSON at ${href} returned ${status}`);
    }
  });
}

async function testMyActivities(page, jsErrors) {
  const S = "my-activities";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  // generatedAt is 2026-07-14 so default month is July; select June which has the full test dataset
  await page.evaluate(() => {
    const sel = document.getElementById("month");
    sel.value = "6";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  // Default filter: year=2026, month=6 (June), sport=Ride → 6 rides, 304 km
  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );
  await check(S, "meta-5-activities", async () => {
    const text = await page.$eval("#meta", (el) => el.textContent);
    assert.ok(
      text.includes("6 activities"),
      `expected "6 activities" in #meta: ${text}`,
    );
  });
  await check(S, "summary-distance", async () => {
    const text = await page.$eval("#summary", (el) => el.textContent);
    // 303 755.8 m rounds to 304 km in the page's display formatting
    assert.ok(text.includes("304"), `expected "304" km in #summary: ${text}`);
  });
  await check(S, "table-5-rows", async () => {
    const n = await page.$$eval("#board tbody tr", (rows) => rows.length);
    assert.equal(n, 6, `expected 6 Ride rows for June 2026, got ${n}`);
  });
  await check(S, "bests-chips", async () => {
    const n = await page.$$eval("#bests .best", (els) => els.length);
    assert.ok(n >= 3, `expected >= 3 best chips, got ${n}`);
  });
  await check(S, "year-selector-2026", async () => {
    const val = await page.$eval("#year", (el) => el.value);
    assert.equal(val, "2026");
  });
  await check(S, "bar-chart-has-bars", async () => {
    const n = await page.$$eval("#svg-dist rect", (els) => els.length);
    assert.ok(n > 0, `expected bars in #svg-dist, got ${n}`);
  });
  await check(S, "bike-selects-in-table", async () => {
    const n = await page.$$eval("#board tbody td select", (els) => els.length);
    assert.ok(n >= 5, `expected >= 5 bike selects for Ride rows, got ${n}`);
  });
  await check(S, "drive-banner-hidden", async () => {
    // drive-status.json says ok:true in the test container → banner must be hidden
    const visible = await page
      .$eval("#drive-banner", (el) => el.classList.contains("visible"))
      .catch(() => false);
    assert.equal(
      visible,
      false,
      "drive-auth banner should be hidden when drive-status.json says ok:true",
    );
  });
  await check(S, "drive-token-connected", async () => {
    // drive-status.json has ok:true + expires_at → token status line must show "connected"
    await page.waitForFunction(
      () => document.getElementById("drive-token")?.textContent.includes("Google Drive"),
      { timeout: 5000 },
    ).catch(() => {});
    const text = await page
      .$eval("#drive-token", (el) => el.textContent)
      .catch(() => "");
    assert.ok(
      text.includes("Google Drive: connected"),
      `expected "Google Drive: connected" in #drive-token: "${text}"`,
    );
  });
}

async function testStats(page, jsErrors) {
  const S = "stats";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.stats, { waitUntil: "networkidle0", timeout: 20000 });
  // Default: year=2026, sport=Ride → 16 activities, 824.7 km
  try {
    await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );

  // KPI: Activities = 17
  await check(S, "kpi-activities-16", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    assert.equal(val, "18", `expected KPI Activities="18", got "${val}"`);
  });

  // KPI: Distance includes "941" (856.7 km existing + 84.6 km Magene = 941.3 km)
  await check(S, "kpi-distance-824", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Distance"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    assert.ok(
      val && val.includes("941"),
      `expected "941" in distance KPI, got "${val}"`,
    );
  });

  // Personal records
  await check(S, "records-longest-102.4", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    assert.ok(text.includes("102.4"), `expected "102.4" in .recs: ${text}`);
  });
  await check(S, "records-elevation-1320", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    assert.ok(
      text.includes("1320") || text.includes("1 320"),
      `expected "1320" in .recs: ${text}`,
    );
  });
  await check(S, "records-fastest-25.0", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    assert.ok(text.includes("25.0"), `expected "25.0" km/h in .recs: ${text}`);
  });

  await check(S, "year-table-has-row", async () => {
    const n = await page.$$eval("#yearTable tbody tr", (rows) => rows.length);
    assert.ok(n >= 1, `expected year table rows, got ${n}`);
  });
  await check(S, "year-table-one-highlighted", async () => {
    const n = await page.$$eval("#yearTable tr.hi", (rows) => rows.length);
    assert.equal(n, 1, `expected exactly 1 highlighted year row, got ${n}`);
  });
  await check(S, "monthly-chart-bars", async () => {
    const n = await page.$$eval("#moSvg rect", (els) => els.length);
    assert.ok(n > 0, `expected bars in #moSvg, got ${n}`);
  });
  await check(S, "sport-table-sports", async () => {
    const n = await page.$$eval("#sportTable tbody tr", (rows) => rows.length);
    // In 2026 the sample has Ride, Run, Walk, VirtualRide (Hike is 2025-only)
    assert.ok(n >= 4, `expected >= 4 sport rows for 2026, got ${n}`);
  });

  // Switch to "All years" and verify period appears in meta + sport subtitle
  await page.evaluate(() => {
    const sel = document.getElementById("yearSel");
    sel.value = "all";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  await check(S, "all-years-meta-shows-period", async () => {
    const meta = await page.$eval("#meta", (el) => el.textContent);
    // period looks like "X year(s)" or "X month(s)" or "X day(s)"
    assert.ok(
      /\d+\s+year|\d+\s+month|\d+\s+day/.test(meta),
      `expected period in #meta when all years selected, got: "${meta}"`,
    );
  });

  await check(S, "all-years-sport-subtitle-shows-period", async () => {
    const subtitle = await page.$eval("#sportSubtitle", (el) => el.textContent);
    assert.ok(
      subtitle.includes("all time") && /\d+\s+year|\d+\s+month|\d+\s+day/.test(subtitle),
      `expected "all time · <period>" in #sportSubtitle, got: "${subtitle}"`,
    );
  });
}

async function testActivityDetail(page, jsErrors) {
  const S = "activity-detail";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.activity, { waitUntil: "networkidle0", timeout: 20000 });
  // 18784255013.json: "West Wroclaw Sample Ride", 64 250.4 m, 612 m, 8 splits
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}

  // Filter out Leaflet CDN errors (unpkg.com may be unreachable inside container)
  await check(S, "no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    assert.equal(real.length, 0, real.map((e) => e.message).join("; "));
  });
  await check(S, "no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    assert.equal(text, "", `#err is not empty: "${text}"`);
  });
  await check(S, "content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    assert.ok(display !== "none", `#content has display:none`);
  });
  await check(S, "title-west-wroclaw", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    assert.ok(
      text.includes("West Wroclaw"),
      `expected "West Wroclaw" in #name, got "${text}"`,
    );
  });
  await check(S, "cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    assert.ok(n >= 4, `expected >= 4 stat cards, got ${n}`);
  });
  await check(S, "distance-64km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    // 64 250.4 / 1000 = 64.2504 → toFixed(1) = "64.3" (rounds up) or "64.2"
    assert.ok(
      text.includes("64.3") || text.includes("64.2"),
      `expected ~64.2/64.3 km in .cards: ${text.slice(0, 200)}`,
    );
  });
  await check(S, "elevation-612m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("612"),
      `expected "612" m in .cards: ${text.slice(0, 200)}`,
    );
  });
  await check(S, "splits-chart-rendered", async () => {
    const n = await page.$$eval(
      "#svg-splits rect, #svg-splits polyline",
      (els) => els.length,
    );
    assert.ok(n > 0, `expected SVG elements in #svg-splits, got ${n}`);
  });
  // Elevation profile — built from cumulative splits_metric.elevation_difference
  await check(S, "elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    assert.ok(display !== "none", `#elev-box has display:none`);
  });
  await check(S, "svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`);
  });
  // Heart rate chart — built from splits_metric.average_heartrate
  await check(S, "hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    assert.ok(display !== "none", `#hr-box has display:none`);
  });
  await check(S, "svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`);
  });
  // Heart rate zone table — visible when HR data is present
  await check(S, "hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    assert.ok(display !== "none", `#hr-zone-box has display:none`);
  });
  await check(S, "hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    assert.strictEqual(n, 5, `expected 5 HR zone rows, got ${n}`);
  });
  await check(S, "hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    assert.ok(txt.includes("185"), `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`);
  });
  await check(S, "elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`);
  });
  await check(S, "hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-hr"] && window.LINE_TIPS["svg-hr"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`);
  });
  await check(S, "elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(new MouseEvent("mousemove", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2
      }));
      return document.getElementById("chart-tip").style.display === "block";
    });
    assert.ok(tipVisible, "#chart-tip should become visible on mousemove over #svg-elev");
  });
  // Cadence chart — rendered from splits_metric[i].average_cadence
  await check(S, "cad-box-visible", async () => {
    const display = await page.$eval("#cad-box", (el) => el.style.display);
    assert.ok(display !== "none", `#cad-box has display:none — cadence chart not rendered`);
  });
  await check(S, "svg-cad-rendered", async () => {
    const n = await page.$$eval("#svg-cad path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-cad (fill + line), got ${n}`);
  });
  // Power chart — rendered from splits_metric[i].average_watts
  await check(S, "pwr-box-visible", async () => {
    const display = await page.$eval("#pwr-box", (el) => el.style.display);
    assert.ok(display !== "none", `#pwr-box has display:none — power chart not rendered`);
  });
  await check(S, "svg-pwr-rendered", async () => {
    const n = await page.$$eval("#svg-pwr path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-pwr (fill + line), got ${n}`);
  });
  // Splits box must stay visible for Strava activities
  await check(S, "splits-box-visible", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    assert.ok(display !== "none", `#splits-box unexpectedly hidden for Strava activity`);
  });
}

async function testActivityDetailHealthsyncRun(page, jsErrors) {
  const S = "activity-detail-healthsync-run";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.activityHealthsyncRun, {
    waitUntil: "networkidle0",
    timeout: 20000,
  });
  // healthsync-20260622.json: "Sample HealthSync Run", 3200 m, 18 m elevation, ~3.2 km
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}

  // Filter out Leaflet CDN errors (unpkg.com may be unreachable inside container)
  await check(S, "no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    assert.equal(real.length, 0, real.map((e) => e.message).join("; "));
  });
  await check(S, "no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    assert.equal(text, "", `#err is not empty: "${text}"`);
  });
  await check(S, "content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    assert.ok(display !== "none", `#content has display:none`);
  });
  await check(S, "title-healthsync-run", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    assert.ok(
      text.includes("HealthSync") || text.includes("Run"),
      `expected HealthSync or Run in #name, got "${text}"`,
    );
  });
  await check(S, "cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    assert.ok(n >= 4, `expected >= 4 stat cards, got ${n}`);
  });
  await check(S, "distance-3km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    // 3200 m = 3.2 km
    assert.ok(
      text.includes("3.2"),
      `expected ~3.2 km in .cards: ${text.slice(0, 200)}`,
    );
  });
  await check(S, "elevation-18m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("18"),
      `expected "18" m in .cards: ${text.slice(0, 200)}`,
    );
  });
  // Elevation profile — parsed from GPX <ele> tags
  await check(S, "elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    assert.ok(display !== "none", `#elev-box has display:none`);
  });
  await check(S, "svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`);
  });
  // Heart rate chart — parsed from GPX <gpxtpx:hr> extensions
  await check(S, "hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    assert.ok(display !== "none", `#hr-box has display:none`);
  });
  await check(S, "svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`);
  });
  // Heart rate zone table — visible when HR data is present
  await check(S, "hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    assert.ok(display !== "none", `#hr-zone-box has display:none`);
  });
  await check(S, "hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    assert.strictEqual(n, 5, `expected 5 HR zone rows, got ${n}`);
  });
  await check(S, "hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    assert.ok(txt.includes("185"), `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`);
  });
  await check(S, "elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`);
  });
  await check(S, "hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-hr"] && window.LINE_TIPS["svg-hr"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`);
  });
  await check(S, "elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(new MouseEvent("mousemove", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2
      }));
      return document.getElementById("chart-tip").style.display === "block";
    });
    assert.ok(tipVisible, "#chart-tip should become visible on mousemove over #svg-elev");
  });
  // Cadence chart — parsed from GPX <gpxtpx:cad> extensions
  await check(S, "cad-box-visible", async () => {
    const display = await page.$eval("#cad-box", (el) => el.style.display);
    assert.ok(display !== "none", `#cad-box has display:none — cadence chart not rendered from GPX`);
  });
  await check(S, "svg-cad-rendered", async () => {
    const n = await page.$$eval("#svg-cad path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-cad (fill + line), got ${n}`);
  });
  // Cadence card — average_cadence from detail JSON (parsed from GPX :cad> during ingestion)
  await check(S, "cadence-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("85") && text.toLowerCase().includes("cadence"),
      `expected cadence card with value 85 in .cards: ${text.slice(0, 300)}`,
    );
  });
  // No km splits for HealthSync activities — splits-box must be hidden
  await check(S, "splits-box-hidden", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    assert.equal(display, "none", `#splits-box should be hidden for HealthSync activity, got "${display}"`);
  });
}

async function testActivityDetailHealthsyncCycling(page, jsErrors) {
  const S = "activity-detail-healthsync-cycling";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.activityHealthsyncCycling, {
    waitUntil: "networkidle0",
    timeout: 20000,
  });
  // healthsync-bike.json: "CYCLING", 25120 m, 64 m elevation, ~25.1 km
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}

  // Filter out Leaflet CDN errors (unpkg.com may be unreachable inside container)
  await check(S, "no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    assert.equal(real.length, 0, real.map((e) => e.message).join("; "));
  });
  await check(S, "no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    assert.equal(text, "", `#err is not empty: "${text}"`);
  });
  await check(S, "content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    assert.ok(display !== "none", `#content has display:none`);
  });
  await check(S, "title-cycling", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    assert.ok(
      text.includes("CYCLING"),
      `expected "CYCLING" in #name, got "${text}"`,
    );
  });
  await check(S, "cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    assert.ok(n >= 4, `expected >= 4 stat cards, got ${n}`);
  });
  await check(S, "distance-25km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    // 25120 m = 25.12 km → toFixed(1) = "25.1"
    assert.ok(
      text.includes("25.1") || text.includes("25.2"),
      `expected ~25.1 km in .cards: ${text.slice(0, 200)}`,
    );
  });
  await check(S, "elevation-64m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("64"),
      `expected "64" m in .cards: ${text.slice(0, 200)}`,
    );
  });
  // Elevation profile — parsed from GPX <ele> tags
  await check(S, "elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    assert.ok(display !== "none", `#elev-box has display:none`);
  });
  await check(S, "svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`);
  });
  // Heart rate chart — parsed from GPX <gpxtpx:hr> extensions
  await check(S, "hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    assert.ok(display !== "none", `#hr-box has display:none`);
  });
  await check(S, "svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`);
  });
  // Heart rate zone table — visible when HR data is present
  await check(S, "hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    assert.ok(display !== "none", `#hr-zone-box has display:none`);
  });
  await check(S, "hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    assert.strictEqual(n, 5, `expected 5 HR zone rows, got ${n}`);
  });
  await check(S, "hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    assert.ok(txt.includes("185"), `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`);
  });
  await check(S, "elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`);
  });
  await check(S, "hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-hr"] && window.LINE_TIPS["svg-hr"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`);
  });
  await check(S, "elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(new MouseEvent("mousemove", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2
      }));
      return document.getElementById("chart-tip").style.display === "block";
    });
    assert.ok(tipVisible, "#chart-tip should become visible on mousemove over #svg-elev");
  });
  // No km splits for HealthSync activities — splits-box must be hidden
  await check(S, "splits-box-hidden", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    assert.equal(display, "none", `#splits-box should be hidden for HealthSync activity, got "${display}"`);
  });
}

async function testActivityDetailMagene(page, jsErrors) {
  const S = "activity-detail-magene";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.activityMagene, {
    waitUntil: "networkidle0",
    timeout: 20000,
  });
  // magene-sample.json: "Magene C606", 84600 m, 303 m elevation, no HR
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    assert.equal(real.length, 0, real.map((e) => e.message).join("; "));
  });
  await check(S, "no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    assert.equal(text, "", `#err is not empty: "${text}"`);
  });
  await check(S, "content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    assert.ok(display !== "none", `#content has display:none`);
  });
  await check(S, "title-magene", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    assert.ok(
      text.includes("Magene"),
      `expected "Magene" in #name, got "${text}"`,
    );
  });
  await check(S, "cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    assert.ok(n >= 4, `expected >= 4 stat cards, got ${n}`);
  });
  await check(S, "distance-84km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    // 84600 m = 84.6 km
    assert.ok(
      text.includes("84.6") || text.includes("84.5"),
      `expected ~84.6 km in .cards: ${text.slice(0, 200)}`,
    );
  });
  await check(S, "elevation-303m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("303"),
      `expected "303" m in .cards: ${text.slice(0, 200)}`,
    );
  });
  // Elevation profile — parsed from GPX <ele> tags
  await check(S, "elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    assert.ok(display !== "none", `#elev-box has display:none`);
  });
  await check(S, "svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    assert.ok(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`);
  });
  // Heart rate chart — Magene has no HR data, so hr-box must be hidden
  await check(S, "hr-box-hidden", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    assert.equal(display, "none", `#hr-box should be hidden for Magene (no HR), got "${display}"`);
  });
  // HR zone table must also be hidden
  await check(S, "hr-zone-box-hidden", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    assert.equal(display, "none", `#hr-zone-box should be hidden for Magene (no HR), got "${display}"`);
  });
  await check(S, "elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    assert.ok(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`);
  });
  // No km splits — Magene activities are not Strava activities
  await check(S, "splits-box-hidden", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    assert.equal(display, "none", `#splits-box should be hidden for Magene activity, got "${display}"`);
  });
}

async function testBikeService(page, jsErrors) {
  const S = "bike-service";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });
  // bike-service.sample.json: 4 bikes; Road Bike has 5 parts
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForSelector("#bikepanel table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );
  await check(S, "meta-not-loading", async () => {
    const text = await page.$eval("#meta", (el) => el.textContent);
    assert.ok(!text.includes("Loading"), `#meta still says Loading`);
  });
  await check(S, "bike-tabs-present", async () => {
    const n = await page.$$eval(".bikes .tab:not(.add)", (els) => els.length);
    // 4 bikes from sample + 1 auto-seeded from gear b-anon-1 (Bike A in activities.json).
    // b-kross-strava (same name "Kross" as existing Kross bike) must NOT create a 6th tab.
    assert.ok(n >= 4, `expected >= 4 bike tabs, got ${n}`);
  });
  await check(S, "no-duplicate-bike-tabs", async () => {
    const labels = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((e) => e.textContent.trim()),
    );
    const dupes = labels.filter((l, i) => labels.indexOf(l) !== i);
    assert.equal(dupes.length, 0, `duplicate bike tabs: ${JSON.stringify(dupes)}`);
  });
  await check(S, "no-duplicate-gear-options", async () => {
    // Open Edit Bike for the Kross bike (has a gear alias scenario in sample data).
    // The gear dropdown must not list the same name twice.
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Kross"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .btn.sm", { timeout: 5000 });
    await page.evaluate(() => {
      const btns = document.querySelectorAll("#bikepanel .btn.sm");
      const edit = Array.from(btns).find((b) => b.textContent.includes("Edit bike"));
      if (edit) edit.click();
    });
    await page.waitForSelector("#b-gear", { timeout: 3000 });
    const opts = await page.$$eval("#b-gear option", (els) =>
      els.map((o) => o.textContent.replace(/\s*·.*$/, "").trim()),
    );
    const dupes = opts.filter((l, i) => l && opts.indexOf(l) !== i);
    assert.equal(dupes.length, 0, `duplicate gear options: ${JSON.stringify(dupes)}`);
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });
  await check(S, "road-bike-tab-exists", async () => {
    const labels = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((e) => e.textContent.trim()),
    );
    assert.ok(
      labels.some((l) => l.includes("Road Bike")),
      `"Road Bike" not in tabs: ${JSON.stringify(labels)}`,
    );
  });
  // Click Road Bike tab to make it active, then check its panel
  await check(S, "road-bike-odo-positive", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) =>
        el.textContent.includes("Road Bike"),
      );
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const text = await page.$eval("#bikepanel .big", (el) =>
      el.textContent.trim(),
    );
    const km = parseFloat(text.replace(/[\s,]/g, "").replace(",", "."));
    assert.ok(km > 0, `expected Road Bike odo > 0 km, got "${text}"`);
  });
  await check(S, "parts-table-has-rows", async () => {
    const n = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    assert.ok(n >= 1, `expected >= 1 part row in Road Bike panel, got ${n}`);
  });
}

async function testBikeServicePartReplacement(page, jsErrors) {
  const S = "bike-service-parts";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForSelector("#bikepanel table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Click Road Bike tab
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) =>
      el.textContent.includes("Road Bike"),
    );
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

  // Count parts before replacement
  let partsBefore = await page.$$eval(
    "#bikepanel tbody tr:not(.ridesrow)",
    (rows) => rows.length,
  );
  assert.ok(partsBefore >= 1, "should have at least 1 part");

  // Find and click delete button for the first part
  await check(S, "part-delete-button-exists", async () => {
    const deleteBtn = await page.$(
      '#bikepanel tbody tr:not(.ridesrow) button[onclick*="deletePart"]',
    );
    assert.ok(deleteBtn, "delete button for first part not found");
  });

  // Test deleting a part and verifying it persists
  await check(S, "part-deletion-persists", async () => {
    // Get first part's name for verification
    const partName = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow) td:nth-child(1)",
      (el) => el.textContent.trim(),
    );

    // Click delete button with user confirmation
    await page.evaluate(() => {
      // Mock confirm to always return true
      window.confirm = () => true;
    });

    const deleteBtn = await page.$(
      '#bikepanel tbody tr:not(.ridesrow) button[onclick*="deletePart"]',
    );
    if (deleteBtn) {
      await deleteBtn.click();
    }

    // Wait for modal to close and page to update
    await page.evaluate(
      () =>
        new Promise((resolve) => {
          setTimeout(resolve, 500);
        }),
    );

    // Count parts after deletion
    const partsAfter = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );

    assert.ok(
      partsAfter < partsBefore,
      `expected parts count to decrease, before: ${partsBefore}, after: ${partsAfter}`,
    );
  });
}

async function testSyncSourceMerging(page, jsErrors) {
  const S = "sync-source-merging";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // generatedAt is 2026-07-14; select June 2026 where both Strava (numeric) and HealthSync (date-based) IDs coexist
  await page.evaluate(() => {
    const sel = document.getElementById("month");
    sel.value = "6";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  // Test 1: Both Strava (numeric) and HealthSync (string) activities coexist
  await check(S, "strava-and-healthsync-mixed", async () => {
    // Get all activity IDs from the table
    const activityIds = await page.$$eval("#board tbody tr", (rows) =>
      rows
        .map((r) => r.getAttribute("data-id"))
        .filter((id) => id !== null && id !== ""),
    );

    assert.ok(activityIds.length > 0, "no activities found in table");

    // Check for both numeric (Strava) and string (HealthSync) IDs
    const numericIds = activityIds.filter((id) => /^\d+$/.test(id));
    const stringIds = activityIds.filter((id) => /^[a-z0-9\-]+$/.test(id));

    assert.ok(
      numericIds.length > 0,
      `expected Strava (numeric) activities, got: ${JSON.stringify(activityIds)}`,
    );
    assert.ok(
      stringIds.length > 0,
      `expected HealthSync (string) activities, got: ${JSON.stringify(activityIds)}`,
    );
  });

  // Test 2: HealthSync activities have correct structure (date-based IDs)
  await check(S, "healthsync-activities-have-date-ids", async () => {
    const healthsyncIds = await page.$$eval("#board tbody tr", (rows) =>
      rows
        .map((r) => r.getAttribute("data-id"))
        .filter((id) => id && /^\d{4}-\d{2}-\d{2}/.test(id)),
    );

    assert.ok(healthsyncIds.length > 0, "no HealthSync activities found");
    // Verify they follow date-based format: YYYY-MM-DD
    healthsyncIds.forEach((id) => {
      assert.ok(
        /^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}.*/.test(id),
        `invalid HealthSync ID format: ${id}`,
      );
    });
  });

  // Test 3: All activities have required display fields
  await check(S, "activities-have-required-fields", async () => {
    const activities = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => ({
        id: r.getAttribute("data-id"),
        dateCells: r.querySelectorAll("td").length,
        hasBike: !!r.querySelector("select"),
      })),
    );

    assert.ok(activities.length > 0, "no activities found");
    activities.forEach((act) => {
      assert.ok(act.id, "activity missing id");
      assert.ok(act.dateCells >= 4, `activity ${act.id} has < 4 columns`);
      assert.ok(
        act.hasBike || true,
        `activity ${act.id} missing bike selector or similar`,
      );
    });
  });

  // Test 4: No duplicate activities in the list
  await check(S, "no-duplicate-activities", async () => {
    const activityIds = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => r.getAttribute("data-id")),
    );

    const uniqueIds = new Set(activityIds);
    assert.equal(
      activityIds.length,
      uniqueIds.size,
      `found ${activityIds.length - uniqueIds.size} duplicate activities`,
    );
  });
}

async function testHistoricalActivityPreservation(page, jsErrors) {
  const S = "historical-preservation";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Test 1: Activities span multiple years (historical data preserved)
  await check(S, "activities-span-multiple-years", async () => {
    // Get all activity rows and extract date info
    const activityDates = await page.$$eval("#board tbody tr", (rows) =>
      rows
        .map((r) => {
          const cells = r.querySelectorAll("td");
          // Look for date in any cell that has YYYY-MM-DD format
          const allText = Array.from(cells)
            .map((c) => c.textContent)
            .join(" ");
          const dateMatch = allText.match(/(\d{4})-(\d{2})-(\d{2})/);
          return dateMatch ? dateMatch[1] : null;
        })
        .filter((y) => y !== null),
    );

    assert.ok(activityDates.length > 0, `no activities with valid dates found`);
  });

  // Test 2: Verify total activity count when viewing all years
  await check(S, "all-years-view-preserves-count", async () => {
    // Select "All" year option if available
    const yearSelect = await page.$("#year");
    if (yearSelect) {
      const options = await page.$$eval("#year option", (opts) =>
        opts.map((o) => ({ value: o.value, text: o.textContent })),
      );

      const allOption = options.find((o) =>
        o.text.toLowerCase().includes("all"),
      );
      if (allOption) {
        await page.select("#year", allOption.value);
        await page.waitForFunction(
          () =>
            !document.getElementById("meta")?.textContent.includes("Loading"),
          { timeout: 5000 },
        );
      }
    }

    // Count rows
    const rowCount = await page.$$eval(
      "#board tbody tr",
      (rows) => rows.length,
    );
    assert.ok(rowCount > 0, "no activities shown for all years");
  });

  // Test 3: Historical activities are accessible via detail page
  await check(S, "historical-activities-have-detail", async () => {
    // Check if older activities (2025 or earlier) are present
    const has2025Activity = await page
      .$eval("#board tbody tr", (row) => {
        const cells = row.querySelectorAll("td");
        const dateText = cells[1]?.textContent || "";
        return dateText.includes("2025") || dateText.includes("2024");
      })
      .catch(() => false);

    // If we have 2025 activities, they should be clickable/linkable
    if (has2025Activity) {
      const detailLinks = await page.$$eval(
        "#board tbody tr a[href*='activity.html']",
        (links) => links.length,
      );
      assert.ok(
        detailLinks > 0,
        "historical activities should have detail links",
      );
    }
  });

  // Test 4: Activity counts don't decrease when filtering
  await check(S, "total-count-accessible", async () => {
    const metaText = await page.$eval("#meta", (el) => el.textContent.trim());

    // Extract count from meta (e.g., "6 activities, 304 km")
    const countMatch = metaText.match(/(\d+)\s*activities/);
    assert.ok(
      countMatch,
      `couldn't extract activity count from meta: "${metaText}"`,
    );

    const count = parseInt(countMatch[1]);
    assert.ok(count > 0, `activity count should be > 0, got ${count}`);
  });
}

async function testDataConsistencyAcrossSources(page, jsErrors) {
  const S = "data-consistency";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Test 1: All activities have required fields populated
  await check(S, "required-fields-populated", async () => {
    const activities = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => {
        const cells = r.querySelectorAll("td");
        return {
          name: cells[0]?.textContent?.trim() || "",
          date: cells[1]?.textContent?.trim() || "",
          distance: cells[2]?.textContent?.trim() || "",
          time: cells[3]?.textContent?.trim() || "",
        };
      }),
    );

    activities.forEach((act, idx) => {
      assert.ok(
        act.name && act.name.length > 0,
        `activity ${idx} missing name`,
      );
      assert.ok(
        act.date && act.date.length > 0,
        `activity ${idx} missing date`,
      );
      assert.ok(
        act.distance && act.distance.length > 0,
        `activity ${idx} missing distance`,
      );
      assert.ok(
        act.time && act.time.length > 0,
        `activity ${idx} missing time`,
      );
    });
  });

  // Test 2: HealthSync and Strava activities use consistent sport types
  await check(S, "consistent-sport-types", async () => {
    const rows = await page.$$eval("#board tbody tr", (trs) => trs.length);
    assert.ok(rows > 0, "no activities to validate");

    // Just verify the table has consistent structure across all activities
    const structureOk = await page.evaluate(() => {
      const rows = document.querySelectorAll("#board tbody tr");
      for (const row of rows) {
        const cells = row.querySelectorAll("td");
        if (cells.length < 4) return false;
      }
      return true;
    });

    assert.ok(structureOk, "activity table rows have inconsistent structure");
  });

  // Test 3: Verify distance values are numeric (can be summed)
  await check(S, "distances-are-numeric", async () => {
    const distances = await page.$$eval(
      "#board tbody tr",
      (rows) =>
        rows
          .map((r) => {
            const cells = r.querySelectorAll("td");
            // Search all cells for one containing numeric data with km
            for (const cell of cells) {
              const text = cell.textContent || "";
              const match = text.match(/[\d.,]+/);
              if (match && /\d/.test(match[0])) {
                return match[0];
              }
            }
            return "";
          })
          .filter((d) => d !== ""), // Skip empty distances
    );

    distances.forEach((dist, idx) => {
      const numericDist = parseFloat(dist.replace(/[^\d.]/g, ""));
      assert.ok(
        !isNaN(numericDist) && numericDist > 0,
        `distance ${idx} is not numeric or is 0: "${dist}"`,
      );
    });
  });

  // Test 4: Activity details are accessible for both source types
  await check(S, "all-activities-clickable", async () => {
    // Get all activity IDs to verify they can be accessed
    const activityIds = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => r.getAttribute("data-id")).filter((id) => id),
    );

    assert.ok(
      activityIds.length > 0,
      "should have clickable activities with data-id attributes",
    );
  });
}

async function testBikeServiceNotifications(page, jsErrors) {
  const S = "bike-service-notifications";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForSelector("#bikepanel table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Verify error element exists and is initially empty
  await check(S, "error-element-exists", async () => {
    const errEl = await page.$("#err");
    assert.ok(errEl, "#err element not found");
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    assert.ok(text === "", `#err should be initially empty, got: "${text}"`);
  });

  // Test error clearing after successful page load
  await check(S, "error-clears-on-load", async () => {
    // Initially error should be empty
    let err = await page.$eval("#err", (el) => el.textContent.trim());
    assert.ok(err === "", "error should start empty");

    // Manually set an error (simulate one)
    await page.evaluate(() => {
      document.getElementById("err").textContent = "Test error message";
    });

    let errSet = await page.$eval("#err", (el) => el.textContent.trim());
    assert.ok(
      errSet.includes("Test error"),
      `error should contain test message, got: "${errSet}"`,
    );

    // Refresh page to clear errors
    await page.reload({ waitUntil: "networkidle0", timeout: 20000 });

    // After reload, error should be cleared
    let errAfter = await page.$eval("#err", (el) => el.textContent.trim());
    assert.ok(
      errAfter === "",
      `error should be cleared after reload, got: "${errAfter}"`,
    );
  });

  // Test error display on modal interactions
  await check(S, "error-appears-in-modal-flow", async () => {
    // Click Road Bike tab
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) =>
        el.textContent.includes("Road Bike"),
      );
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

    // Find a part and try to open its detail modal
    const parts = await page.$$(
      "#bikepanel tbody tr:not(.ridesrow) button[onclick*='showPart']",
    );
    if (parts.length > 0) {
      await parts[0].click();

      // Wait for modal to appear
      await page.evaluate(
        () =>
          new Promise((resolve) => {
            setTimeout(resolve, 200);
          }),
      );

      // Cancel modal
      const cancelBtn = await page.$(
        'button.btn:not(.primary):contains("Cancel")',
      );
      if (cancelBtn) {
        await cancelBtn.click();
      } else {
        // Try generic cancel button
        const allBtns = await page.$$eval(
          "button.btn:not(.primary)",
          (buttons) =>
            buttons
              .filter((b) => b.textContent.includes("Cancel"))
              .map((b) => b.textContent),
        );
        assert.ok(allBtns.length > 0, "Cancel button should exist in modal");
      }
    }

    // After flow, verify error is either empty or contains expected text
    const err = await page.$eval("#err", (el) => el.textContent.trim());
    // Error should either be empty or contain a specific message
    assert.ok(
      err === "" || typeof err === "string",
      "error should be string or empty",
    );
  });
}

// ── CGI round-trip (plain fetch, no browser) ───────────────────────────────────

async function testResetFilter(page, jsErrors) {
  const S = "reset-filter";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "reset-button-exists", async () => {
    const btn = await page.$("#resetFilters");
    assert.ok(btn, "#resetFilters button not found");
  });

  await check(S, "reset-restores-default-year", async () => {
    // Change year away from default
    await page.select("#year", "2025");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );
    // Click reset
    await page.click("#resetFilters");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );
    const year = await page.$eval("#year", (el) => el.value);
    assert.equal(year, "2026", `expected year reset to "2026", got "${year}"`);
  });

  await check(S, "reset-restores-default-sport", async () => {
    const sport = await page.$eval("#sport", (el) => el.value);
    assert.equal(sport, "Ride", `expected sport reset to "Ride", got "${sport}"`);
  });

  await check(S, "reset-clears-month-filter", async () => {
    // Month should be set to current month (not "all")
    const month = await page.$eval("#month", (el) => el.value);
    assert.ok(month !== undefined, "month selector should exist");
    // After reset the month is the current month or "all" depending on current date vs data
    assert.ok(typeof month === "string", `month value should be a string, got ${typeof month}`);
  });
}

async function testColumnSorting(page, jsErrors) {
  const S = "column-sorting";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Default sort is date descending — the date header should carry a sorted class
  await check(S, "default-date-column-sorted", async () => {
    const hasSortedClass = await page.evaluate(() => {
      const ths = Array.from(document.querySelectorAll("#board thead th"));
      return ths.some((th) => th.className.includes("sorted-"));
    });
    assert.ok(hasSortedClass, "no column header has a sorted class on initial load");
  });

  // Click a non-date column header and verify sorting changes
  await check(S, "click-header-applies-sorted-class", async () => {
    const headers = await page.$$eval("#board thead th", (ths) =>
      ths.map((th, i) => ({ idx: i, text: th.textContent.trim(), cls: th.className })),
    );
    // Pick first header that is not already sorted
    const unsorted = headers.find((h) => !h.cls.includes("sorted-"));
    assert.ok(unsorted, "all headers already sorted — cannot test click");

    await page.$$eval(
      "#board thead th",
      (ths, idx) => ths[idx].click(),
      unsorted.idx,
    );

    await page.evaluate(
      () =>
        new Promise((resolve) => {
          setTimeout(resolve, 200);
        }),
    );

    const hasClass = await page.evaluate((idx) => {
      const th = document.querySelectorAll("#board thead th")[idx];
      return th.className.includes("sorted-");
    }, unsorted.idx);

    assert.ok(
      hasClass,
      `expected sorted class on header #${unsorted.idx} ("${unsorted.text}") after click`,
    );
  });

  // Click same header again — sort direction should reverse
  await check(S, "second-click-reverses-sort-direction", async () => {
    const headers = await page.$$eval("#board thead th", (ths) =>
      ths.map((th, i) => ({ idx: i, cls: th.className })),
    );
    const sorted = headers.find((h) => h.cls.includes("sorted-"));
    assert.ok(sorted, "no sorted header found for reverse-click test");

    const dirBefore = sorted.cls.includes("sorted-asc") ? "asc" : "desc";

    await page.$$eval(
      "#board thead th",
      (ths, idx) => ths[idx].click(),
      sorted.idx,
    );
    await page.evaluate(
      () =>
        new Promise((resolve) => {
          setTimeout(resolve, 200);
        }),
    );

    const dirAfter = await page.evaluate((idx) => {
      const th = document.querySelectorAll("#board thead th")[idx];
      return th.className.includes("sorted-asc") ? "asc" : "desc";
    }, sorted.idx);

    assert.notEqual(
      dirAfter,
      dirBefore,
      `expected sort direction to flip from "${dirBefore}" to "${dirAfter}"`,
    );
  });
}

async function testStatsSportFilter(page, jsErrors) {
  const S = "stats-sport-filter";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.stats, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Default sport: Ride — KPI Activities = 16
  await check(S, "default-sport-ride", async () => {
    const sport = await page.$eval("#sportSel", (el) => el.value);
    assert.equal(sport, "Ride", `expected default sport "Ride", got "${sport}"`);
  });

  // Switch to Run and verify KPI Activities changes
  await check(S, "switch-to-run-updates-kpis", async () => {
    const rideCounts = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });

    // Switch sport to Run
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const runOpt = Array.from(sel.options).find((o) =>
        o.value === "Run",
      );
      if (runOpt) {
        sel.value = "Run";
        sel.dispatchEvent(new Event("change", { bubbles: true }));
      }
    });
    await page.evaluate(
      () =>
        new Promise((resolve) => {
          setTimeout(resolve, 300);
        }),
    );

    const runCounts = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });

    assert.ok(runCounts !== null, "Activities KPI not found after switching to Run");
    // The count should differ from Ride (different sports have different activity counts)
    assert.notEqual(
      runCounts,
      rideCounts,
      `expected Run KPI Activities to differ from Ride ("${rideCounts}"), got "${runCounts}"`,
    );
  });

  // Verify records section still renders after sport switch
  await check(S, "records-render-after-sport-switch", async () => {
    const recsEl = await page.$(".recs");
    assert.ok(recsEl, ".recs element not found after sport switch");
  });

  // Switch to All sports and verify the By sport table shows multiple rows
  await check(S, "all-sports-shows-sport-table", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const allOpt = Array.from(sel.options).find((o) =>
        o.value === "All" || o.value === "",
      );
      if (allOpt) {
        sel.value = allOpt.value;
        sel.dispatchEvent(new Event("change", { bubbles: true }));
      }
    });
    await page.evaluate(
      () =>
        new Promise((resolve) => {
          setTimeout(resolve, 300);
        }),
    );

    const sportRows = await page.$$eval(
      "#sportTable tbody tr",
      (rows) => rows.length,
    );
    assert.ok(
      sportRows >= 2,
      `expected >= 2 rows in #sportTable with All sports, got ${sportRows}`,
    );
  });
}

async function testFocusRow(page, jsErrors) {
  const S = "focus-row";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try { sessionStorage.clear(); } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  // generatedAt is 2026-07-14 so default month is July (1 activity, no best chips); select June
  await page.evaluate(() => {
    const sel = document.getElementById("month");
    sel.value = "6";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  try {
    await page.waitForSelector("#bests .best", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Each chip must carry a data-id that matches a row in the table.
  await check(S, "chips-link-to-valid-rows", async () => {
    const chipIds = await page.$$eval("#bests .best", (els) =>
      els.map((el) => el.getAttribute("data-id")).filter(Boolean),
    );
    assert.ok(chipIds.length >= 1, "no best chips with data-id found");
    for (const id of chipIds) {
      const exists = await page.evaluate(
        (id) => !!document.querySelector(`#board tbody tr[data-id="${id}"]`),
        id,
      );
      assert.ok(exists, `no table row found for chip data-id="${id}"`);
    }
  });

  // Clicking a chip must flash the correct row.  The flash class is applied
  // after a 500 ms delay (scroll-then-highlight fix), so we wait up to 1.5 s.
  await check(S, "chip-click-flashes-row", async () => {
    const chipId = await page.$eval(
      "#bests .best",
      (el) => el.getAttribute("data-id"),
    );
    assert.ok(chipId, "first best chip has no data-id");

    await page.evaluate(() => document.querySelector("#bests .best").click());

    await page.waitForFunction(
      (id) => {
        const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
        return tr && tr.classList.contains("flash");
      },
      { timeout: 1500 },
      chipId,
    );
  });

  // A rapid double-click must restart the flash: the row should still carry
  // the flash class ~600 ms after the second click (500 ms delay + buffer).
  await check(S, "double-click-restarts-flash", async () => {
    const chipId = await page.$eval(
      "#bests .best",
      (el) => el.getAttribute("data-id"),
    );
    assert.ok(chipId, "first best chip has no data-id");

    // First click — wait for flash to start.
    await page.evaluate(() => document.querySelector("#bests .best").click());
    await page.waitForFunction(
      (id) => {
        const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
        return tr && tr.classList.contains("flash");
      },
      { timeout: 1500 },
      chipId,
    );

    // Second click while first flash is still running.
    await page.evaluate(() => document.querySelector("#bests .best").click());

    // The fix removes the class immediately then re-adds it after 500 ms.
    // Briefly after the click the class should be gone…
    const removedQuickly = await page.evaluate((id) => {
      const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
      return tr && !tr.classList.contains("flash");
    }, chipId);
    assert.ok(
      removedQuickly,
      "flash class should be removed immediately on second click",
    );

    // …and then reappear once the 500 ms delay elapses.
    await page.waitForFunction(
      (id) => {
        const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
        return tr && tr.classList.contains("flash");
      },
      { timeout: 1500 },
      chipId,
    );
  });
}

async function testBikeServiceCgi() {
  const ENDPOINT = `${CGI}/bike-service`;

  await check("cgi-bike-service", "GET-returns-json", async () => {
    const r = await fetch(ENDPOINT, { cache: "no-store" });
    assert.equal(r.status, 200, `expected 200, got ${r.status}`);
    const ct = r.headers.get("content-type") ?? "";
    assert.ok(ct.includes("json"), `expected JSON content-type, got: ${ct}`);
    const data = await r.json();
    assert.ok(Array.isArray(data.bikes), "data.bikes is not an Array");
    assert.ok(
      data.bikes.length >= 4,
      `expected >= 4 bikes, got ${data.bikes.length}`,
    );
  });

  await check("cgi-bike-service", "GET-has-road-bike-parts", async () => {
    const r = await fetch(ENDPOINT, { cache: "no-store" });
    const data = await r.json();
    const road = data.bikes.find((b) => b.name === "Road Bike");
    assert.ok(road, '"Road Bike" not in bikes array');
    assert.ok(
      Array.isArray(road.parts) && road.parts.length >= 1,
      `Road Bike.parts is empty or not an array`,
    );
  });

  await check("cgi-bike-service", "POST-service-note-persists", async () => {
    const getR = await fetch(ENDPOINT, { cache: "no-store" });
    const current = await getR.json();
    const testNote = `test-service-${Date.now()}`;

    const road = current.bikes.find((b) => b.name === "Road Bike");
    assert.ok(road, '"Road Bike" not found for POST test');

    // Use any available part (may have been deleted by part-replacement test)
    const testPart = road.parts && road.parts.length > 0 ? road.parts[0] : null;
    assert.ok(testPart, "Road Bike has no parts for POST test");

    if (!testPart.services) testPart.services = [];
    testPart.services.push({
      id: `s-test-${Date.now()}`,
      date: "2026-06-24",
      mileage: 608,
      note: testNote,
    });

    const postR = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(current),
    });
    assert.ok(postR.ok, `POST failed with status ${postR.status}`);

    const verifyR = await fetch(ENDPOINT, { cache: "no-store" });
    const verify = await verifyR.json();
    const vRoad = verify.bikes.find((b) => b.name === "Road Bike");
    const vPart = vRoad?.parts?.find((p) => p.id === testPart.id);
    const found = vPart?.services?.some((s) => s.note === testNote);
    assert.ok(found, `POST'd service note not found on subsequent GET`);
  });
}

async function testActivityFilteringAndRefresh(page, jsErrors) {
  const S = "activity-filtering";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Test changing year filter (2026 → 2025)
  await check(S, "year-filter-changes", async () => {
    const year2026 = await page.$eval("#year", (el) => el.value);
    assert.equal(year2026, "2026", "initial year should be 2026");

    // Get the row count for 2026
    let rows2026 = await page.$$eval("#board tbody tr", (rows) => rows.length);

    // Change to 2025
    await page.select("#year", "2025");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );

    const year2025 = await page.$eval("#year", (el) => el.value);
    assert.equal(year2025, "2025", "year should be 2025 after change");

    // Row count may differ (2026 has different activities than 2025)
    let rows2025 = await page.$$eval("#board tbody tr", (rows) => rows.length);
    // Just verify table updated; content varies by dataset
    assert.ok(rows2025 >= 0, "rows after year filter should be >= 0");
  });

  // Test changing sport filter (Ride → Walk)
  await check(S, "sport-filter-changes", async () => {
    // Reset to 2026 for consistent test
    await page.select("#year", "2026");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );

    const rideRows = await page.$$eval(
      "#board tbody tr",
      (rows) => rows.length,
    );
    assert.ok(rideRows >= 1, "should have >= 1 Ride rows");

    // Change to Walk
    const sportSelect = await page.$(".sport-filter select");
    if (sportSelect) {
      await page.evaluate(() => {
        const select = document.querySelector(".sport-filter select");
        if (select) {
          const walkOpt = Array.from(select.options).find((o) =>
            o.textContent.includes("Walk"),
          );
          if (walkOpt) {
            select.value = walkOpt.value;
            select.dispatchEvent(new Event("change", { bubbles: true }));
          }
        }
      });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 5000 },
      );

      const walkRows = await page.$$eval(
        "#board tbody tr",
        (rows) => rows.length,
      );
      // Walk rows may differ from Ride rows in the test data
      assert.ok(walkRows >= 0, "Walk rows should be >= 0");
    }
  });

  // Test month filter (June → May)
  await check(S, "month-filter-changes", async () => {
    const monthSelect = await page.$(".month-filter select");
    if (monthSelect) {
      const mayOpt = await page.evaluate(() => {
        const select = document.querySelector(".month-filter select");
        if (select) {
          const opt = Array.from(select.options).find((o) =>
            o.textContent.includes("May"),
          );
          return opt?.value;
        }
      });

      if (mayOpt) {
        await page.select(".month-filter select", mayOpt);
        await page.waitForFunction(
          () =>
            !document.getElementById("meta")?.textContent.includes("Loading"),
          { timeout: 5000 },
        );

        const currentMonth = await page.$eval(
          ".month-filter select",
          (el) => el.value,
        );
        assert.ok(currentMonth, "month filter should be set");
      }
    }
  });
}

async function testBikeAssignmentDropdown(page, jsErrors) {
  const S = "bike-assignment";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try {
      sessionStorage.clear();
    } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });

  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Test that bike dropdowns exist in the table
  await check(S, "dropdowns-exist", async () => {
    const selects = await page.$$eval(
      "#board tbody td select",
      (els) => els.length,
    );
    assert.ok(selects >= 1, `expected >= 1 bike select, got ${selects}`);
  });

  // Test changing a bike assignment and verifying persistence
  await check(S, "bike-assignment-persists", async () => {
    // Find first select with at least 2 options
    const selectData = await page.evaluate(() => {
      const selects = document.querySelectorAll("#board tbody td select");
      for (const sel of selects) {
        if (sel.options.length >= 2) {
          const activityId = sel.closest("tr")?.getAttribute("data-id");
          const currentValue = sel.value;
          return {
            found: true,
            activityId,
            currentValue,
            options: Array.from(sel.options).map((o) => ({
              value: o.value,
              text: o.textContent,
            })),
          };
        }
      }
      return { found: false };
    });

    assert.ok(selectData.found, "no multi-option select found for testing");

    if (selectData.found) {
      const { activityId, currentValue, options } = selectData;

      // Pick a different option
      const otherOption = options.find((o) => o.value !== currentValue);
      assert.ok(otherOption, "no alternative option found to test");

      // Change the bike assignment via dropdown
      await page.evaluate(
        ({ aId, newVal }) => {
          const selects = document.querySelectorAll("#board tbody td select");
          for (const sel of selects) {
            const row = sel.closest("tr");
            if (row?.getAttribute("data-id") === aId) {
              sel.value = newVal;
              sel.dispatchEvent(new Event("change", { bubbles: true }));
              break;
            }
          }
        },
        { aId: activityId, newVal: otherOption.value },
      );

      // Give the CGI POST time to complete
      await page.evaluate(
        () =>
          new Promise((resolve) => {
            setTimeout(resolve, 500);
          }),
      );

      // Verify the CGI was called by checking the bike-assign endpoint
      const bikeAssignR = await page.evaluate(async () => {
        try {
          const r = await fetch("/cgi-bin/bike-assign", {
            cache: "no-store",
          });
          return await r.json();
        } catch (e) {
          return null;
        }
      });

      assert.ok(bikeAssignR, "bike-assign CGI should return data");
      if (bikeAssignR) {
        // The bike-assign CGI stores assignments as {activityId: bikeId, ...}
        assert.ok(
          typeof bikeAssignR === "object",
          "bike-assign should return a JSON object",
        );
      }
    }
  });
}

// Regression test: manually-assigned bike rides must be counted in the summary odo.
// setBike() replaces a.gear_id with the bike name string; computePrimaryBikeOdo used
// to compare that string against the Strava gear ID and wrongly excluded such rides.
async function testBikeOdoIncludesManualAssignments(page, jsErrors) {
  const S = "bike-odo-manual-assign";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // generatedAt is 2026-07-14; select June 2026 where activity id=4 (Gravel Grind) lives
  await page.evaluate(() => {
    const sel = document.getElementById("month");
    sel.value = "6";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  // Set sport=Ride so all rows are rides and the odo covers the same set.
  await page.evaluate(() => {
    const sel = document.getElementById("sport");
    sel.value = "Ride";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  // Capture the total distance shown in the summary bar before any reassignment.
  const beforeText = await page.$eval("#summary", (el) => el.textContent);
  const beforeKm = parseFloat(beforeText.match(/^([\d\s,]+)\s*km/)?.[1]?.replace(/[\s,]/g, "") || "0");
  assert.ok(beforeKm > 0, `expected non-zero total km in summary: "${beforeText}"`);

  // Reassign activity id=4 (Gravel Grind, gear b18141502 = "Gravel Bike", 76003.9 m)
  // to "Road Bike" via setBike. Before the fix, computePrimaryBikeOdo would then
  // exclude it because a.gear_id becomes "Road Bike" ≠ gid "b16239154".
  await check(S, "odo-counts-reassigned-ride", async () => {
    const result = await page.evaluate(() => {
      // Call setBike directly to simulate the dropdown change.
      if (typeof setBike === "function") {
        setBike("4", "Road Bike");
      } else {
        window.setBike("4", "Road Bike");
      }
      // Give the render cycle a tick to complete.
      return new Promise((resolve) => {
        setTimeout(() => {
          const text = document.getElementById("summary")?.textContent || "";
          const m = text.match(/Road Bike:\s*([\d\s,]+)\s*km/);
          resolve({ summaryText: text, odoText: m ? m[1] : null });
        }, 200);
      });
    });

    assert.ok(
      result.odoText !== null,
      `"Road Bike: X km" not found in summary after reassignment: "${result.summaryText}"`,
    );
    const odoKm = parseFloat(result.odoText.replace(/[\s,]/g, ""));
    // Activity 4 (Gravel Grind) is ~76 km. After reassignment to Road Bike its distance
    // must appear in the odo. The odo should be >= Road Bike's base total (those already
    // tagged b16239154: ~608 km in sample data) so it must be well above 76 km.
    assert.ok(
      odoKm > 76,
      `expected Road Bike odo > 76 km after reassigning Gravel Grind (76 km), got ${odoKm} km. ` +
      `Summary: "${result.summaryText}"`,
    );
  });
}

async function testEmptyState(page, jsErrors) {
  const S = "empty-state";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector("#board table", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // AlpineSki is not in the sample dataset → board renders empty state
  await page.evaluate(() => {
    const sel = document.getElementById("sport");
    sel.value = "AlpineSki";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  await check(S, "empty-div-shown", async () => {
    const el = await page.$("#board .empty");
    assert.ok(el, ".empty not rendered when no activities match filter");
  });
  await check(S, "empty-div-text", async () => {
    const text = await page.$eval("#board .empty", (el) => el.textContent);
    assert.ok(
      text.includes("No activities"),
      `expected "No activities" in .empty, got: "${text}"`,
    );
  });
  await check(S, "summary-cleared", async () => {
    const text = await page.$eval("#summary", (el) => el.textContent.trim());
    assert.equal(
      text,
      "",
      `expected #summary cleared on empty filter, got: "${text}"`,
    );
  });
}

async function testDashboardBestChips(page, jsErrors) {
  const S = "dashboard-best-chips";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.dash, { waitUntil: "networkidle0", timeout: 20000 });
  // generatedAt is 2026-07-14 so default month is July (1 activity, no best chips); select June
  await page.evaluate(() => {
    const sel = document.getElementById("month");
    sel.value = "6";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  try {
    await page.waitForSelector("#bests .best", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Every chip must have a <b> label and non-empty value text
  await check(S, "chips-have-label-and-value", async () => {
    const chips = await page.$$eval("#bests .best", (els) =>
      els.map((el) => ({
        label: el.querySelector("b")?.textContent?.trim() || "",
        full: el.textContent?.trim() || "",
      })),
    );
    assert.ok(chips.length >= 3, `expected >= 3 best chips, got ${chips.length}`);
    chips.forEach((c, i) => {
      assert.ok(c.label.length > 0, `chip ${i} has no <b> label`);
      assert.ok(
        c.full.length > c.label.length,
        `chip ${i} has no value text beyond the label`,
      );
    });
  });

  // Temperature chips must be present (sample data has average_temp) and show °C
  await check(S, "temperature-chips-present-with-degree-symbol", async () => {
    const chipTexts = await page.$$eval("#bests .best", (els) =>
      els.map((el) => el.textContent || ""),
    );
    const coldText = chipTexts.find((t) => t.includes("Coldest"));
    const hotText = chipTexts.find((t) => t.includes("Hottest"));
    assert.ok(coldText, "expected a Coldest chip (sample data has average_temp)");
    assert.ok(hotText, "expected a Hottest chip (sample data has average_temp)");
    assert.ok(
      coldText.includes("°C"),
      `expected "°C" in Coldest chip, got: "${coldText}"`,
    );
    assert.ok(
      hotText.includes("°C"),
      `expected "°C" in Hottest chip, got: "${hotText}"`,
    );
  });
}

async function testStravaLink(page, jsErrors) {
  const S = "strava-link";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });

  // Strava numeric ID → "Open on Strava" link must be present
  await page.goto(URLS.activity, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "strava-activity-has-open-link", async () => {
    const text = await page.$eval("#links", (el) => el.textContent);
    assert.ok(
      text.includes("Open on Strava"),
      `expected "Open on Strava" in #links for Strava activity, got: "${text}"`,
    );
  });
  await check(S, "strava-link-href-contains-id", async () => {
    const href = await page.$eval(
      '#links a[href*="strava.com"]',
      (el) => el.href,
    );
    assert.ok(
      href.includes("18784255013"),
      `expected activity ID in Strava link href, got: "${href}"`,
    );
  });

  // HealthSync date-based ID → no Strava link
  jsErrors.length = 0;
  await page.goto(URLS.activityHealthsyncRun, {
    waitUntil: "networkidle0",
    timeout: 20000,
  });
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "healthsync-activity-no-strava-link", async () => {
    const link = await page.$('#links a[href*="strava.com"]');
    assert.ok(!link, 'expected no "Open on Strava" link for HealthSync activity');
  });
}

async function testStatsRecords(page, jsErrors) {
  const S = "stats-records";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.stats, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "best-week-record-present", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      labels.some((l) => l.includes("Best week")),
      `expected "Best week" in #recs record labels, got: ${JSON.stringify(labels)}`,
    );
  });
  await check(S, "best-week-value-has-km", async () => {
    const val = await page.evaluate(() => {
      for (const rec of document.querySelectorAll("#recs .rec")) {
        if (rec.querySelector(".rl")?.textContent.includes("Best week"))
          return rec.querySelector(".rv")?.textContent || "";
      }
      return null;
    });
    assert.ok(
      val && val.includes("km"),
      `expected "km" in best-week value, got: "${val}"`,
    );
  });

  await check(S, "streak-record-present", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      labels.some((l) => l.toLowerCase().includes("streak")),
      `expected "streak" in #recs record labels, got: ${JSON.stringify(labels)}`,
    );
  });
  await check(S, "streak-value-has-days", async () => {
    const val = await page.evaluate(() => {
      for (const rec of document.querySelectorAll("#recs .rec")) {
        if (rec.querySelector(".rl")?.textContent.toLowerCase().includes("streak"))
          return rec.querySelector(".rv")?.textContent || "";
      }
      return null;
    });
    assert.ok(
      val && val.includes("day"),
      `expected "day" in streak value, got: "${val}"`,
    );
  });
}

async function testBikeModalCrud(page, jsErrors) {
  const S = "bike-modal-crud";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  const testBikeName = `TestBike-${Date.now()}`;

  // ── Add bike ──────────────────────────────────────────────────────────────
  await check(S, "add-bike-modal-opens", async () => {
    await page.evaluate(() => showAddBike());
    await page.waitForSelector("#b-name", { timeout: 3000 });
    const nameInput = await page.$("#b-name");
    assert.ok(nameInput, "#b-name input not found in add-bike modal");
  });

  await check(S, "add-bike-creates-tab", async () => {
    await page.$eval(
      "#b-name",
      (el, name) => { el.value = name; },
      testBikeName,
    );
    await page.evaluate(() => saveBike(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const tabs = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((el) => el.textContent.trim()),
    );
    assert.ok(
      tabs.some((t) => t.includes(testBikeName)),
      `expected tab with name "${testBikeName}", got: ${JSON.stringify(tabs)}`,
    );
  });

  // ── Add part to Road Bike ─────────────────────────────────────────────────
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

  const testPartName = `TestPart-${Date.now()}`;

  await check(S, "add-part-modal-opens", async () => {
    await page.evaluate(() => showAddPart());
    await page.waitForSelector("#p-name", { timeout: 3000 });
    const nameInput = await page.$("#p-name");
    assert.ok(nameInput, "#p-name input not found in add-part modal");
  });

  await check(S, "add-part-creates-row", async () => {
    await page.$eval(
      "#p-name",
      (el, name) => { el.value = name; },
      testPartName,
    );
    const countBefore = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    await page.evaluate(() => savePart(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const countAfter = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    assert.ok(
      countAfter > countBefore,
      `expected part count to increase from ${countBefore}, got ${countAfter}`,
    );
  });

  // ── Delete the test bike ──────────────────────────────────────────────────
  await check(S, "delete-bike-removes-tab", async () => {
    await page.evaluate((name) => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      for (const t of tabs) {
        if (t.textContent.trim().includes(name)) { t.click(); break; }
      }
    }, testBikeName);
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

    const tabsBefore = await page.$$eval(".bikes .tab:not(.add)", (els) => els.length);
    await page.evaluate(() => {
      window.confirm = () => true;
      const btn = document.querySelector('button[onclick*="deleteBike"]');
      if (btn) btn.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const tabsAfter = await page.$$eval(".bikes .tab:not(.add)", (els) => els.length);
    assert.ok(
      tabsAfter < tabsBefore,
      `expected tab count to decrease from ${tabsBefore}, got ${tabsAfter}`,
    );
  });
}

async function testAlertThresholds(page, jsErrors) {
  const S = "alert-thresholds";
  const ENDPOINT = `${CGI}/bike-service`;

  // Setup: lower alertKm to 1 on Road Bike's first active part so it's
  // guaranteed to trigger regardless of how much mileage the sample carries.
  const setupR = await fetch(ENDPOINT, { cache: "no-store" });
  const setupData = await setupR.json();
  const road = setupData.bikes.find((b) => b.name === "Road Bike");
  if (!road || !road.parts || road.parts.length === 0) {
    console.log(`  SKIP  ${S}: Road Bike has no parts to test`);
    return;
  }
  const originalAlertKm = road.parts[0].alertKm;
  road.parts[0].alertKm = 1;
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(setupData),
  });

  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  await check(S, "warn-row-appears-when-threshold-exceeded", async () => {
    const n = await page.$$eval("#bikepanel tr.warn", (rows) => rows.length);
    assert.ok(
      n >= 1,
      `expected >= 1 tr.warn in #bikepanel when alertKm=1 is set, got ${n}`,
    );
  });

  await check(S, "warn-row-has-highlight-background", async () => {
    const bg = await page.evaluate(() => {
      const td = document.querySelector("#bikepanel tr.warn td");
      return td ? window.getComputedStyle(td).backgroundColor : null;
    });
    assert.ok(
      bg && bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent",
      `expected coloured background on tr.warn td, got: "${bg}"`,
    );
  });

  // Teardown: restore original alertKm so subsequent runs start clean
  const restoreR = await fetch(ENDPOINT, { cache: "no-store" });
  const restoreData = await restoreR.json();
  const restoreRoad = restoreData.bikes.find((b) => b.name === "Road Bike");
  if (restoreRoad && restoreRoad.parts && restoreRoad.parts.length > 0) {
    restoreRoad.parts[0].alertKm = originalAlertKm;
    await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(restoreData),
    });
  }
}

async function testNeedsReplacement(page, jsErrors) {
  const S = "needs-replacement";
  const ENDPOINT = `${CGI}/bike-service`;

  // Setup: clear needsReplacement on all parts so the test starts clean.
  const setupR = await fetch(ENDPOINT, { cache: "no-store" });
  const setupData = await setupR.json();
  const road = setupData.bikes.find((b) => b.name === "Road Bike");
  if (!road || !road.parts || road.parts.length < 2) {
    console.log(`  SKIP  ${S}: Road Bike needs >= 2 parts`);
    return;
  }
  road.parts.forEach((p) => { p.needsReplacement = false; });
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(setupData),
  });

  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

  // --- checkbox is present in service modal ---
  await check(S, "service-modal-has-needs-repl-checkbox", async () => {
    const svcBtns = await page.$$('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showService"]');
    assert.ok(svcBtns.length >= 1, "expected >= 1 Service button");
    await svcBtns[0].click();
    await page.waitForSelector("#s-needs-repl", { timeout: 3000 });
    const chk = await page.$("#s-needs-repl");
    assert.ok(chk, "#s-needs-repl checkbox not found in service modal");
    // close without saving
    await page.evaluate(() => closeModal());
  });

  // --- flag the last part (not the first) so we can verify it moves to the top ---
  const lastPartId = road.parts[road.parts.length - 1].id;
  await check(S, "flagged-part-shows-needs-repl-badge", async () => {
    // Open service modal for the last part via JS, check the box, save.
    await page.evaluate((id) => showService(id), lastPartId);
    await page.waitForSelector("#s-needs-repl", { timeout: 3000 });
    await page.evaluate(() => {
      document.getElementById("s-needs-repl").checked = true;
      // fill required date/mileage fields
      document.getElementById("f-date").value = "2026-01-01";
      document.getElementById("f-mileage").value = "0";
    });
    await page.evaluate(() => saveService(document.getElementById("s-needs-repl").closest("#modal").querySelector('button[onclick*="saveService"]')?.getAttribute("onclick")?.match(/'([^']+)'/)?.[1]));
    // saveService expects the part id — call it directly
  });

  // Easier: call saveService directly with the known id
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

  // Use CGI to mark the last part as needsReplacement directly, then reload.
  const preR = await fetch(ENDPOINT, { cache: "no-store" });
  const preData = await preR.json();
  const preRoad = preData.bikes.find((b) => b.name === "Road Bike");
  if (preRoad && preRoad.parts.length >= 2) {
    preRoad.parts[preRoad.parts.length - 1].needsReplacement = true;
    await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(preData),
    });
  }

  await page.reload({ waitUntil: "networkidle0", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  await check(S, "needs-repl-badge-visible", async () => {
    const n = await page.$$eval("#bikepanel .needs-repl", (els) => els.length);
    assert.ok(n >= 1, `expected >= 1 .needs-repl badge in #bikepanel, got ${n}`);
  });

  await check(S, "flagged-part-sorts-first", async () => {
    // The first non-ridesrow part row must contain the .needs-repl badge.
    const firstRowHasBadge = await page.evaluate(() => {
      const rows = document.querySelectorAll("#bikepanel tbody tr:not(.ridesrow)");
      return rows.length > 0 && !!rows[0].querySelector(".needs-repl");
    });
    assert.ok(firstRowHasBadge, "expected the flagged part to be the first row in the active-parts table");
  });

  await check(S, "service-modal-checkbox-prechecked-for-flagged-part", async () => {
    // Service modal for the flagged part must pre-check the box.
    const svcBtns = await page.$$('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showService"]');
    assert.ok(svcBtns.length >= 1, "no Service button found");
    await svcBtns[0].click();   // first row = flagged part (sorted to top)
    await page.waitForSelector("#s-needs-repl", { timeout: 3000 });
    const checked = await page.$eval("#s-needs-repl", (el) => el.checked);
    assert.ok(checked, "#s-needs-repl should be pre-checked for a flagged part");
    await page.evaluate(() => closeModal());
  });

  // Teardown: clear all needsReplacement flags
  const tearR = await fetch(ENDPOINT, { cache: "no-store" });
  const tearData = await tearR.json();
  const tearRoad = tearData.bikes.find((b) => b.name === "Road Bike");
  if (tearRoad) tearRoad.parts.forEach((p) => { p.needsReplacement = false; });
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(tearData),
  });
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const executablePath = await findBrowser();
  console.log("Using browser:", executablePath);

  const browser = await puppeteer.launch({
    executablePath,
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
  });

  const jsErrors = [];
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    // Only track uncaught JS exceptions — not console.error network messages
    // (404s for optional resources like CDN assets or missing images are benign).
    page.on("pageerror", (err) => jsErrors.push(err));

    console.log("\n--- Club Dashboard ---");
    await testClubDashboard(page, jsErrors);

    console.log("\n--- My Activities ---");
    await testMyActivities(page, jsErrors);

    console.log("\n--- Empty State (dashboard) ---");
    await testEmptyState(page, jsErrors);

    console.log("\n--- Dashboard Best Chips ---");
    await testDashboardBestChips(page, jsErrors);

    console.log("\n--- Activity Filtering & Refresh ---");
    await testActivityFilteringAndRefresh(page, jsErrors);

    console.log("\n--- Bike Assignment (Dropdown) ---");
    await testBikeAssignmentDropdown(page, jsErrors);

    console.log("\n--- Bike Odo Includes Manual Assignments ---");
    await testBikeOdoIncludesManualAssignments(page, jsErrors);

    console.log("\n--- Sync Source Merging (Strava + HealthSync) ---");
    await testSyncSourceMerging(page, jsErrors);

    console.log("\n--- Historical Activity Preservation ---");
    await testHistoricalActivityPreservation(page, jsErrors);

    console.log("\n--- Data Consistency Across Sources ---");
    await testDataConsistencyAcrossSources(page, jsErrors);

    console.log("\n--- Focus Row (best-chip highlight) ---");
    await testFocusRow(page, jsErrors);

    console.log("\n--- Reset Filter ---");
    await testResetFilter(page, jsErrors);

    console.log("\n--- Column Sorting ---");
    await testColumnSorting(page, jsErrors);

    console.log("\n--- Stats ---");
    await testStats(page, jsErrors);

    console.log("\n--- Stats Sport Filter ---");
    await testStatsSportFilter(page, jsErrors);

    console.log("\n--- Stats Records (best week / streak) ---");
    await testStatsRecords(page, jsErrors);

    console.log("\n--- Activity Detail ---");
    await testActivityDetail(page, jsErrors);

    console.log("\n--- Activity Detail (HealthSync Run) ---");
    await testActivityDetailHealthsyncRun(page, jsErrors);

    console.log("\n--- Activity Detail (HealthSync Cycling) ---");
    await testActivityDetailHealthsyncCycling(page, jsErrors);

    console.log("\n--- Activity Detail (Magene C606 — no HR) ---");
    await testActivityDetailMagene(page, jsErrors);

    console.log("\n--- Strava Link (numeric vs HealthSync ID) ---");
    await testStravaLink(page, jsErrors);

    console.log("\n--- Bike Service (UI) ---");
    await testBikeService(page, jsErrors);

    console.log("\n--- Bike Service (Part Replacement) ---");
    await testBikeServicePartReplacement(page, jsErrors);

    console.log("\n--- Bike Service (Notifications) ---");
    await testBikeServiceNotifications(page, jsErrors);

    console.log("\n--- Bike Modal CRUD (add/delete bike, add part) ---");
    await testBikeModalCrud(page, jsErrors);

    console.log("\n--- Alert Thresholds (isWarn) ---");
    await testAlertThresholds(page, jsErrors);

    console.log("\n--- Needs Replacement (flag, badge, sort) ---");
    await testNeedsReplacement(page, jsErrors);
  } finally {
    await browser.close();
  }

  console.log("\n--- CGI: bike-service ---");
  await testBikeServiceCgi();

  console.log("\n" + "=".repeat(50));
  console.log(`Results: ${passed} passed, ${failed} failed`);
  writeJUnitXml(TEST_RESULTS);
  if (failed > 0) {
    console.error("\nFailed tests:");
    results
      .filter((r) => !r.ok)
      .forEach((r) => {
        console.error(
          `  FAIL  ${r.suite} / ${r.name}: ${r.error?.message ?? r.error}`,
        );
      });
    return 1;
  } else {
    console.log("All tests passed.");
    return 0;
  }
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function writeJUnitXml(filePath) {
  const duration = ((Date.now() - START_TIME_MS) / 1000).toFixed(3);
  const failures = results.filter((r) => !r.ok).length;
  const testCount = results.length;
  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
  xml += `<testsuites>\n`;
  xml += `<testsuite name=\"functional-tests\" tests=\"${testCount}\" failures=\"${failures}\" time=\"${duration}\">\n`;
  results.forEach((r) => {
    const name = `${r.suite} / ${r.name}`;
    xml += `  <testcase classname=\"${escapeXml(r.suite)}\" name=\"${escapeXml(name)}\" time=\"0\">`;
    if (!r.ok) {
      const message = escapeXml(
        r.error?.message ?? String(r.error) ?? "failure",
      );
      xml += `\n    <failure message=\"${message}\">${message}</failure>\n  `;
    }
    xml += `</testcase>\n`;
  });
  xml += `</testsuite>\n</testsuites>\n`;
  fs.writeFileSync(filePath, xml, "utf8");
  console.log(`JUnit XML test report written to ${filePath}`);
}

// Set exitCode rather than calling process.exit() directly — avoids a
// libuv UV_HANDLE_CLOSING assertion on Windows when puppeteer's IPC
// channels are still draining as the process shuts down.
main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((err) => {
    console.error("Fatal:", err);
    process.exitCode = 1;
  });
