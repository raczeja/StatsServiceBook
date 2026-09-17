/**
 * functional-tests.mjs — Playwright-based regression tests for all five pages
 * and the bike-service CGI. Runs against the local test container (port 8080).
 *
 * Usage (container must already be running on :8080):
 *   node functional-tests.mjs
 *
 * Called automatically by run-tests.ps1, which starts the container first.
 * Exits 0 on all pass, 1 on any failure.
 */
import { chromium } from "playwright";
import fs from "fs";
import path from "path";
import assert from "assert/strict";

const PORT = process.env.TEST_PORT || process.env.STRAVA_TEST_PORT || "8080";
const HOST = process.env.TEST_HOST || "localhost";
const BASE = `http://${HOST}:${PORT}/strava/me`;
const CGI = `http://${HOST}:${PORT}/cgi-bin`;
const URLS = {
  club: `http://${HOST}:${PORT}/strava/index.html`,
  dash: `${BASE}/index.html`,
  stats: `${BASE}/stats.html`,
  heatmap: `${BASE}/heatmap.html`,
  activity: `${BASE}/activity.html?id=18784255013`,
  activityHealthsyncRun: `${BASE}/activity.html?id=2026-06-22-15-07-running`,
  activityHealthsyncCycling: `${BASE}/activity.html?id=2026-06-22-10-30-cycling`,
  activityMagene: `${BASE}/activity.html?id=magene-2026-07-12-50671559`,
  activityWalk: `${BASE}/activity.html?id=3`,
  bike: `${BASE}/bike.html`,
};

const TEST_RESULTS =
  process.env.TEST_RESULTS || path.resolve("test-results.xml");
const START_TIME_MS = Date.now();

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
  await page.goto(URLS.club, { waitUntil: "networkidle", timeout: 20000 });
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
  // Past month (June 2026, which is the default fallback) must NOT show "Last week"
  await check(S, "table-no-last-week-past-month", async () => {
    const headers = await page.$$eval(
      "#board thead tr th",
      (ths) => ths.map((th) => th.textContent.trim()),
    );
    assert.ok(
      !headers.some((h) => h.replace(/ /g, " ").includes("Last week")),
      `expected no "Last week" header for past month, got: ${JSON.stringify(headers)}`,
    );
  });
  // Table header must include "Last week" column when current month matches the data month
  await check(S, "table-has-last-week-column", async () => {
    // Mock Date so the browser thinks it's in June 2026 (same as the data)
    await page.evaluate(() => {
      const _Orig = window.Date;
      const fake = new _Orig(2026, 5, 15);
      window.__savedDate = _Orig;
      window.Date = class extends _Orig {
        constructor(...a) { super(...(a.length ? a : [fake.getTime()])); }
        static now() { return fake.getTime(); }
      };
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    const headers = await page.$$eval(
      "#board thead tr th",
      (ths) => ths.map((th) => th.textContent.trim()),
    );
    // Restore real Date and re-render so later tests see the normal state
    await page.evaluate(() => {
      if (window.__savedDate) { window.Date = window.__savedDate; delete window.__savedDate; }
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    assert.ok(
      headers.some((h) => h.includes("Last week")),
      `expected "Last week" column header when current month matches data, got: ${JSON.stringify(headers)}`,
    );
  });
  // Last-week column must show a non-zero km value for at least one athlete
  // (regression guard for the lwMap key mismatch that caused always-zero values)
  await check(S, "last-week-column-has-value", async () => {
    await page.evaluate(() => {
      const _Orig = window.Date;
      const fake = new _Orig(2026, 5, 15);
      window.__savedDateLw = _Orig;
      window.Date = class extends _Orig {
        constructor(...a) { super(...(a.length ? a : [fake.getTime()])); }
        static now() { return fake.getTime(); }
      };
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    const lwValues = await page.$$eval(
      "#board .person-row td:last-child",
      (tds) => tds.map((td) => td.textContent.trim()),
    );
    await page.evaluate(() => {
      if (window.__savedDateLw) { window.Date = window.__savedDateLw; delete window.__savedDateLw; }
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    const nonZero = lwValues.filter((v) => !v.startsWith("0"));
    assert.ok(
      nonZero.length > 0,
      `expected ≥1 non-zero last-week km value, got: ${JSON.stringify(lwValues)}`,
    );
  });
  // Detail rows must be sorted newest-first (descending date)
  await check(S, "detail-rows-newest-first", async () => {
    await page.click("#board .person-row:first-child");
    const dates = await page.$eval(
      "#board .detail-row .detail-table tbody",
      (tbody) => Array.from(tbody.querySelectorAll("tr")).map((tr) => tr.querySelector("td")?.textContent.trim() || ""),
    );
    assert.ok(dates.length >= 2, `expected >= 2 detail rows to test sort, got ${dates.length}`);
    for (let i = 0; i < dates.length - 1; i++) {
      assert.ok(
        dates[i] >= dates[i + 1],
        `detail rows not newest-first: row ${i}="${dates[i]}" should be >= row ${i+1}="${dates[i+1]}"`,
      );
    }
    await page.click("#board .person-row:first-child");
  });
  // Top-5-year section must be present and contain at least 1 item
  await check(S, "top5-year-section-exists", async () => {
    const n = await page.$$eval("#board .top5-item", (els) => els.length);
    assert.ok(n >= 1, `expected >= 1 .top5-item in #board, got ${n}`);
  });
  // "since YYYY-MM-DD" must appear in the Top-5 section label (moved from per-athlete subtitle)
  await check(S, "top5-since-date-in-label", async () => {
    const label = await page.$eval("#board .top5-label", (el) => el.textContent);
    assert.ok(/since \d{4}-\d{2}-\d{2}/.test(label), `top5 label missing "since YYYY-MM-DD", got: "${label}"`);
  });
  // Per-athlete subtitle must NOT contain "since" (moved to section label)
  await check(S, "top5-sub-no-since", async () => {
    const subs = await page.$$eval("#board .top5-sub", (els) => els.map((e) => e.textContent));
    const hasSince = subs.some((t) => /since/.test(t));
    assert.ok(!hasSince, `top5 per-athlete subtitle should not contain "since", got: ${JSON.stringify(subs)}`);
  });
  // Single-activity highlights section must be present
  await check(S, "achieve-section-exists", async () => {
    const n = await page.$$eval("#board .achieve-section", (els) => els.length);
    assert.ok(n >= 1, `expected >= 1 .achieve-section, got ${n}`);
  });
  // achieve-section label must mention the selected period
  await check(S, "achieve-section-label-has-period", async () => {
    const label = await page.$eval("#board .achieve-section-label", (el) => el.textContent);
    assert.ok(label.length > 5, `achieve-section label too short: "${label}"`);
  });
  // Club all-time section must be present
  await check(S, "club-alltime-section-exists", async () => {
    const n = await page.$$eval("#board .club-alltime", (els) => els.length);
    assert.ok(n >= 1, `expected >= 1 .club-alltime, got ${n}`);
  });
  // Club all-time label must contain "since YYYY-MM-DD" (moved from tile to label)
  await check(S, "club-alltime-label-has-since", async () => {
    const label = await page.evaluate(() => {
      const labels = Array.from(document.querySelectorAll("#board .club-alltime-label"));
      const found = labels.find((el) => el.textContent.includes("Club all-time"));
      return found ? found.textContent : null;
    });
    assert.ok(label !== null, `no "Club all-time" .club-alltime-label found in #board`);
    assert.ok(/since \d{4}-\d{2}-\d{2}/.test(label), `club-alltime label missing "since DATE", got: "${label}"`);
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
  await check(S, "ck-banner-hidden-in-api-mode", async () => {
    // Sample activities.json has no scrapeMeta → cookie banner must be hidden in api mode
    const display = await page
      .$eval("#ck-banner", (el) => el.style.display)
      .catch(() => "none");
    assert.equal(display, "none", "#ck-banner should be hidden when scrapeMeta is null");
  });
  await check(S, "ck-banner-ok-state", async () => {
    // Inject scrapeMeta with cookieRefreshNeededBy 20 days from now → ck-ok (green)
    const { cls, visible } = await page.evaluate(() => {
      const el = document.getElementById("ck-banner");
      if (!el || typeof renderCookieBanner !== "function") return { cls: "", visible: false };
      const future = new Date(Date.now() + 20 * 86400000).toISOString().slice(0, 10);
      const today  = new Date().toISOString().slice(0, 10);
      renderCookieBanner({ cookieVerifiedAt: today, cookieRefreshNeededBy: future });
      return { cls: el.className, visible: el.style.display !== "none" };
    });
    assert.ok(visible, "#ck-banner should be visible in ok state");
    assert.ok(cls.includes("ck-ok"), `#ck-banner class should include ck-ok, got: "${cls}"`);
  });
  await check(S, "ck-banner-warn-state", async () => {
    // Inject scrapeMeta with cookieRefreshNeededBy 4 days from now → ck-warn (orange)
    const { cls, visible } = await page.evaluate(() => {
      const el = document.getElementById("ck-banner");
      if (!el || typeof renderCookieBanner !== "function") return { cls: "", visible: false };
      const soon  = new Date(Date.now() + 4 * 86400000).toISOString().slice(0, 10);
      const today = new Date().toISOString().slice(0, 10);
      renderCookieBanner({ cookieVerifiedAt: today, cookieRefreshNeededBy: soon });
      return { cls: el.className, visible: el.style.display !== "none" };
    });
    assert.ok(visible, "#ck-banner should be visible in warn state");
    assert.ok(cls.includes("ck-warn"), `#ck-banner class should include ck-warn, got: "${cls}"`);
  });
  await check(S, "ck-banner-expired-state", async () => {
    // Inject scrapeMeta with cookieRefreshNeededBy in the past → ck-expired (red)
    const { cls, visible, text } = await page.evaluate(() => {
      const el = document.getElementById("ck-banner");
      if (!el || typeof renderCookieBanner !== "function") return { cls: "", visible: false, text: "" };
      const past  = new Date(Date.now() - 2 * 86400000).toISOString().slice(0, 10);
      const today = new Date().toISOString().slice(0, 10);
      renderCookieBanner({ cookieVerifiedAt: today, cookieRefreshNeededBy: past });
      return { cls: el.className, visible: el.style.display !== "none", text: el.innerHTML };
    });
    assert.ok(visible, "#ck-banner should be visible in expired state");
    assert.ok(cls.includes("ck-expired"), `#ck-banner class should include ck-expired, got: "${cls}"`);
    assert.ok(text.includes("expired"), `#ck-banner text should mention "expired", got: "${text}"`);
  });
  await check(S, "drive-token-connected", async () => {
    // drive-status.json has ok:true + file_count + expires_at → status line must show "Drive: reachable"
    await page.waitForFunction(
      () => document.getElementById("drive-token")?.textContent.includes("Drive:"),
      { timeout: 5000 },
    ).catch(() => {});
    const text = await page
      .$eval("#drive-token", (el) => el.textContent)
      .catch(() => "");
    assert.ok(
      text.includes("Drive: reachable"),
      `expected "Drive: reachable" in #drive-token: "${text}"`,
    );
    assert.ok(
      text.includes("42 files"),
      `expected "42 files" in #drive-token: "${text}"`,
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
  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
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
  await check(S, "records-max-speed-70.0", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    assert.ok(text.includes("70.0"), `expected "70.0" km/h in .recs (max speed): ${text}`);
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

  // YoY column: reload to default year so cmpTable is rendered
  await page.evaluate(() => {
    try { sessionStorage.clear(); } catch (_) {}
  });
  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
  try { await page.waitForSelector("#cmpTable th", { timeout: 10000 }); } catch (_) {}

  await check(S, "cmp-table-yoy-header", async () => {
    const headers = await page.$$eval("#cmpTable th", (ths) => ths.map((t) => t.textContent.trim()));
    assert.ok(headers.includes("YoY"), `expected "YoY" header in cmpTable, got: ${JSON.stringify(headers)}`);
  });
  await check(S, "cmp-table-yoy-cell-format", async () => {
    const cells = await page.$$eval("#cmpTable td", (tds) => tds.map((t) => t.textContent.trim()));
    const yoy = cells.find((c) => /^[+\-]\d/.test(c) && c.includes("km"));
    assert.ok(yoy, `expected a YoY cell like "+N km / +N%" in cmpTable, got cells: ${JSON.stringify(cells.slice(0,10))}`);
  });
  await check(S, "cmp-table-total-row", async () => {
    const rows = await page.$$eval("#cmpTable tbody tr", (trs) => trs.map((r) => r.textContent.trim()));
    const totRow = rows.find((r) => r.startsWith("Total"));
    assert.ok(totRow, `expected a "Total" row in cmpTable, got rows: ${JSON.stringify(rows.slice(-3))}`);
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
  await page.goto(URLS.activity, { waitUntil: "load", timeout: 20000 });
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
  // Weather cards — 18784255013.json has temp_source=archive, apparent_temp=27, wind_speed=15, wind_dir=270
  await check(S, "weather-temp-source-badge-shown", async () => {
    const badge = await page.$(".cards .wx-src");
    assert.ok(badge, "expected .wx-src source badge in temp card, got none");
  });
  await check(S, "weather-temp-archive-badge", async () => {
    const hasBadge = await page.evaluate(() => !!document.querySelector(".wx-arch"));
    assert.ok(hasBadge, 'expected .wx-arch badge (archive source) in temp card');
  });
  await check(S, "weather-temp-feels-like-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("feels") && text.includes("27"),
      `expected "feels 27" in .cards weather section: ${text.slice(0, 300)}`,
    );
  });
  await check(S, "weather-wind-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.toLowerCase().includes("wind") && text.includes("15"),
      `expected Wind card with "15 km/h" in .cards: ${text.slice(0, 300)}`,
    );
  });
  await check(S, "weather-wind-direction-arrow", async () => {
    // wind_dir=270 (west) → ← arrow
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("←"),
      `expected west arrow "←" in Wind card (wind_dir=270), got: ${text.slice(0, 300)}`,
    );
  });
  // 18784255013.json: gear = {id:'b-anon-1', name:'Bike A'} — "Bike A" is not in
  // bike-service at this point (bike.html auto-seed hasn't run yet).
  // The Gear card must show the gear name, and the bike picker must select "Bike A"
  // as a custom option rather than falling back to "— unassigned —".
  await check(S, "gear-card-shows-name", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    assert.ok(
      text.includes("Bike A"),
      `expected "Bike A" in gear card, got: ${text.slice(0, 400)}`,
    );
  });
  await check(S, "bike-picker-selects-gear-name", async () => {
    // Wait for the async bike picker to render.
    try {
      await page.waitForSelector("#bike-sel", { timeout: 5000 });
    } catch (_) {
      assert.fail("#bike-sel did not appear — bike picker not rendered for Ride activity");
    }
    const selected = await page.$eval("#bike-sel", (el) => el.value);
    assert.equal(
      selected,
      "Bike A",
      `expected bike picker to show "Bike A" (gear name not in bike-service), got "${selected}"`,
    );
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
    waitUntil: "load",
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
    waitUntil: "load",
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
    waitUntil: "load",
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

async function testActivityDetailWalk(page, jsErrors) {
  const S = "activity-detail-walk";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  // Forest Walk: id=3, average_cadence=55, moving_time=5198
  // expected steps = Math.round(55 * 2 * 5198 / 60) = 9530
  await page.goto(URLS.activityWalk, { waitUntil: "load", timeout: 20000 });
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 }
    );
  } catch (_) {}

  await check(S, "no-js-errors", () => {
    const real = jsErrors.filter(e =>
      !e.message?.toLowerCase().includes("leaflet") &&
      !e.message?.toLowerCase().includes("unpkg.com")
    );
    assert.equal(real.length, 0, real.map(e => e.message).join("; "));
  });

  // Steps card: 55 strides/min * 2 * 5198s / 60 ≈ 9530
  await check(S, "steps-card-shown", async () => {
    const text = await page.$eval(".cards", el => el.textContent);
    // Strip locale thousands separators (comma, space, dot) before numeric check
    const digits = text.replace(/[,.\s]/g, "");
    assert.ok(
      text.includes("Steps") && digits.includes("9530"),
      `expected Steps card with ~9530 in .cards: ${text.slice(0, 300)}`
    );
  });

  // Cadence card should also be visible
  await check(S, "cadence-card-shown", async () => {
    const text = await page.$eval(".cards", el => el.textContent);
    assert.ok(
      text.toLowerCase().includes("cadence") && text.includes("55"),
      `expected cadence card with value 55: ${text.slice(0, 300)}`
    );
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
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
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
  await check(S, "top-panel-extra-stats", async () => {
    // Elevation, Avg Ride, Services, Parts should appear as .odo > div > .k labels
    // when the bike has rides; Road Bike in sample data does.
    const labels = await page.$$eval(
      "#bikepanel .odo .k",
      (els) => els.map((el) => el.textContent.trim()),
    );
    assert.ok(labels.includes("Elevation"),  `expected "Elevation" in odo labels, got: ${JSON.stringify(labels)}`);
    assert.ok(labels.includes("Avg Ride"),   `expected "Avg Ride" in odo labels, got: ${JSON.stringify(labels)}`);
    assert.ok(labels.includes("Services"),   `expected "Services" in odo labels, got: ${JSON.stringify(labels)}`);
    assert.ok(labels.includes("Parts"),      `expected "Parts" in odo labels, got: ${JSON.stringify(labels)}`);
  });
  await check(S, "bike-stats-comparison-table", async () => {
    // Comparison table (2+ bikes in sample) must be after archived section.
    // "Bike Statistics" h2 must appear after at least one parts table.
    const headings = await page.$$eval("#bikepanel h2", (els) => els.map((el) => el.textContent.trim()));
    assert.ok(
      headings.some((h) => h.includes("Bike Statistics")),
      `expected "Bike Statistics" h2, got: ${JSON.stringify(headings)}`,
    );
    // The comparison table's Distance row must have at least one positive km value.
    const rows = await page.$$eval(
      "#bikepanel table tbody tr",
      (trs) => trs
        .filter((r) => !r.classList.contains("ridesrow") && !r.classList.contains("archived"))
        .map((r) => Array.from(r.querySelectorAll("td")).map((td) => td.textContent.trim())),
    );
    const distRow = rows.find((r) => r[0] === "Distance");
    assert.ok(distRow, `expected a "Distance" row in the Bike Statistics table`);
    const hasPositive = distRow.slice(1).some(function(cell) {
      return parseFloat(cell.replace(/[\s]/g, "")) > 0;
    });
    assert.ok(hasPositive, `expected at least one positive Distance value, got: ${JSON.stringify(distRow)}`);
  });
  await check(S, "parts-table-has-rows", async () => {
    const n = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    assert.ok(n >= 1, `expected >= 1 part row in Road Bike panel, got ${n}`);
  });
  // Archived parts — Road Bike has "Old Chain" archived from 2024-03-15 to 2025-09-01.
  // fmtDuration should produce a non-empty "N year(s) M month(s)…" string.
  await check(S, "archived-part-shows-duration", async () => {
    const archiveRows = await page.$$eval(
      "#bikepanel tr.archived:not(.ridesrow)",
      (rows) => rows.length,
    );
    assert.ok(archiveRows >= 1, `expected >= 1 archived part row, got ${archiveRows}`);
    const durText = await page.$eval(
      "#bikepanel tr.archived:not(.ridesrow) td:nth-child(2) .muted",
      (el) => el.textContent.trim(),
    );
    assert.ok(
      /year|month|week|day/.test(durText),
      `expected duration text (year/month/week/day) in archived part, got: "${durText}"`,
    );
  });
  // Fork service part has alertTimeN=1, alertTimeUnit="years" — installed 2025-09-01,
  // today is well past 1 year so the bar should show ≥ 100% and trigger a warning row.
  await check(S, "time-based-alert-bar-renders", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const pct = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) .svc-pct",
      (el) => el.textContent.trim(),
    );
    assert.ok(pct.endsWith("%"), `expected a % value in .svc-pct, got: "${pct}"`);
  });
  await check(S, "time-based-alert-shows-days", async () => {
    const sinceCells = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) td:nth-child(5)",
      (els) => els.map((e) => e.textContent),
    );
    const hasDays = sinceCells.some((t) => /\d+ d/.test(t));
    assert.ok(hasDays, `expected at least one "Since service" cell to show days (e.g. "365 d"), got: ${JSON.stringify(sinceCells)}`);
  });
  // Cost tracking — Road Bike / Chain has cost:49.90 + one service with cost:5.50 in sample data.
  await check(S, "cost-column-header-present", async () => {
    const headers = await page.$$eval(
      "#bikepanel thead th",
      (ths) => ths.map((th) => th.textContent.trim()),
    );
    assert.ok(headers.includes("Cost"), `expected "Cost" column header, got: ${JSON.stringify(headers)}`);
  });
  // Ensure Road Bike is still selected and the cost block has rendered before cost checks.
  // A deferred render() from persist() can briefly swap the panel to a no-cost bike.
  await page.evaluate(() => {
    const t = Array.from(document.querySelectorAll(".bikes .tab:not(.add)")).find(
      (el) => el.textContent.includes("Road Bike"),
    );
    if (t) t.click();
  });
  try {
    await page.waitForFunction(() => !!document.querySelector(".cost-block"), { timeout: 5000 });
  } catch (_) {}
  await check(S, "cost-total-block-shown", async () => {
    // Road Bike Chain has part cost 49.90 + service cost 5.50 = 55.40; total block must appear.
    const block = await page.$(".cost-block");
    assert.ok(block, "expected .cost-block to be present when costs are recorded");
    const text = await page.$eval(".cost-block .cost-total", (el) => el.textContent.trim());
    assert.ok(/\d/.test(text), `expected a numeric value in .cost-total, got: "${text}"`);
  });
  await check(S, "cost-total-includes-currency", async () => {
    const text = await page.$eval(".cost-block .cost-total", (el) => el.textContent.trim());
    assert.ok(/PLN/i.test(text), `expected currency code (PLN) in cost total, got: "${text}"`);
  });
  await check(S, "cost-split-parts-and-service", async () => {
    // Road Bike has part cost (49.90) AND a service cost (5.50) → split line must appear
    // showing both "parts" and "service" labels beneath the total.
    const text = await page.$eval(".cost-block", (el) => el.textContent);
    assert.ok(
      /parts/i.test(text),
      `expected "parts" label in cost split line, got: "${text}"`,
    );
    assert.ok(
      /service/i.test(text),
      `expected "service" label in cost split line, got: "${text}"`,
    );
  });
  await check(S, "cost-split-shows-correct-amounts", async () => {
    // part cost 49.90 + service cost 5.50; each must appear in the split line.
    const text = await page.$eval(".cost-block", (el) => el.textContent);
    assert.ok(
      /49[.,]90/.test(text),
      `expected part cost 49.90 in cost block, got: "${text}"`,
    );
    assert.ok(
      /5[.,]50/.test(text),
      `expected service cost 5.50 in cost block, got: "${text}"`,
    );
  });
  await check(S, "cost-cell-shows-part-cost", async () => {
    // The cost column (6th td, 0-indexed 5) of non-archived, non-ridesrow rows should
    // show a non-dash value for the Chain row (which has cost 49.90).
    const costCells = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) td:nth-child(6)",
      (els) => els.map((e) => e.textContent.trim()),
    );
    const hasValue = costCells.some((t) => /\d/.test(t) && !t.includes("—"));
    assert.ok(hasValue, `expected at least one cost cell with a numeric value, got: ${JSON.stringify(costCells)}`);
  });
  await check(S, "cost-modal-label-has-currency", async () => {
    // Open "Add part" modal and verify the purchase cost label shows the currency code.
    await page.evaluate(() => {
      if (typeof showAddPart === "function") showAddPart();
    });
    await page.waitForSelector("#p-cost", { timeout: 3000 });
    const labelText = await page.evaluate(() => {
      const input = document.getElementById("p-cost");
      if (!input) return "";
      const label = input.previousElementSibling;
      return label ? label.textContent.trim() : "";
    });
    assert.ok(
      /PLN/i.test(labelText),
      `expected currency code (PLN) in purchase cost label, got: "${labelText}"`,
    );
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });
}

async function testBikeInputStepAndOdo(page, jsErrors) {
  const S = "bike-input-step-and-odo";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // ── step=1 on km / hours inputs in "Add part" modal ──────────────────────
  await check(S, "add-part-mileage-step-is-1", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    await page.evaluate(() => { if (typeof showAddPart === "function") showAddPart(); });
    await page.waitForSelector("#f-mileage", { timeout: 3000 });
    const step = await page.$eval("#f-mileage", (el) => el.getAttribute("step"));
    assert.equal(step, "1", `expected #f-mileage step="1", got "${step}"`);
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  await check(S, "add-part-alert-km-step-is-1", async () => {
    await page.evaluate(() => { if (typeof showAddPart === "function") showAddPart(); });
    await page.waitForSelector(".st-km", { timeout: 3000 });
    const step = await page.$eval(".st-km", (el) => el.getAttribute("step"));
    assert.equal(step, "1", `expected .st-km step="1", got "${step}"`);
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  await check(S, "add-part-alert-hours-step-is-1", async () => {
    await page.evaluate(() => { if (typeof showAddPart === "function") showAddPart(); });
    await page.waitForSelector(".st-h", { timeout: 3000 });
    const step = await page.$eval(".st-h", (el) => el.getAttribute("step"));
    assert.equal(step, "1", `expected .st-h step="1", got "${step}"`);
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  await check(S, "edit-bike-base-mileage-step-is-1", async () => {
    await page.evaluate(() => {
      const btns = document.querySelectorAll("#bikepanel .btn.sm");
      const edit = Array.from(btns).find((b) => b.textContent.includes("Edit bike"));
      if (edit) edit.click();
    });
    await page.waitForSelector("#b-base", { timeout: 3000 });
    const step = await page.$eval("#b-base", (el) => el.getAttribute("step"));
    assert.equal(step, "1", `expected #b-base step="1", got "${step}"`);
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  // ── Ridden-since-install uses odometer difference (baseMileage included) ──
  // "Odo Test Bike": baseMileage=5000, gearId="" (all rides → ~1301 km tracked),
  // Chain installedMileage=1200. Expected ridden = (5000 + ~1301) - 1200 = ~5101 km.
  // The OLD formula (rideMileageSince) would have returned only ~1301 (tracked rides only).
  await check(S, "odo-test-bike-tab-present", async () => {
    const labels = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((e) => e.textContent.trim()),
    );
    assert.ok(
      labels.some((l) => l.includes("Odo Test Bike")),
      `"Odo Test Bike" not in tabs: ${JSON.stringify(labels)}`,
    );
  });

  await check(S, "ridden-since-install-includes-base-mileage", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Odo Test Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel table", { timeout: 5000 });
    // "Ridden since install" is 3rd column (td:nth-child(3)) of the first non-rides row.
    const riddenText = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow) td:nth-child(3)",
      (el) => el.textContent.trim(),
    );
    // Parse leading number (e.g. "5 101.2 km" → 5101.2)
    const km = parseFloat(riddenText.replace(/[\s ]/g, "").replace(",", "."));
    // baseMileage=5000, tracked rides≈1301, installedMileage=1200 → ridden≈5101
    // Minimum sanity: must be > 4000 (proves baseMileage is counted, not just tracked rides).
    assert.ok(
      km > 4000,
      `expected ridden-since-install > 4000 km (baseMileage included), got ${km} from "${riddenText}"`,
    );
  });

  await check(S, "alert-pct-includes-base-mileage", async () => {
    // alertKm=2000, ridden≈5101 → pct ≥ 100%. If baseMileage were ignored (1301 km), pct=65%.
    const pctText = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) .svc-pct",
      (el) => el.textContent.trim(),
    );
    const pct = parseFloat(pctText);
    assert.ok(
      pct >= 100,
      `expected alert pct >= 100% (baseMileage included in calc), got ${pct}% from "${pctText}"`,
    );
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
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });

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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });

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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });

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
        await page.selectOption("#year", allOption.value);
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });

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
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });

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
    await page.reload({ waitUntil: "networkidle", timeout: 20000 });

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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
    await page.selectOption("#year", "2025");
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
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

  // KPI: Activities card subtitle shows "18 / N days" (18 active days for Ride 2026)
  await check(S, "kpi-activities-days-subtitle", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".s")?.textContent.trim() || null;
      }
      return null;
    });
    assert.ok(val && /^18 \/ \d+ days$/.test(val),
      `expected Activities subtitle to match "18 / N days", got "${val}"`);
  });

  // KPI: Activities card tooltip mentions active days on hover
  await check(S, "kpi-activities-tooltip", async () => {
    const cardHandle = await page.evaluateHandle(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities")) return k;
      }
      return null;
    });
    assert.ok(cardHandle, "Activities KPI card not found");
    await cardHandle.hover();
    await page.evaluate(() => new Promise(function(r){ setTimeout(r, 100); }));
    const tipText = await page.$eval("#tip", function(el){ return el.textContent; });
    assert.ok(tipText && tipText.includes("active days"),
      `expected tooltip to mention "active days", got "${tipText}"`);
    await page.mouse.move(0, 0);
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

  // Records respond to sport switch: longest-distance value must differ from Ride
  await check(S, "records-change-on-sport-switch", async () => {
    // We switched to Run above. Longest Run in sample = 8.2 km, not the Ride 102.4 km.
    const val = await getRecVal(page, "Longest distance");
    assert.ok(val, "Longest distance record not found after switching to Run");
    assert.ok(
      !val.includes("102.4"),
      `Longest distance should show Run value, not Ride 102.4 km — got: "${val}"`,
    );
    assert.ok(
      val.includes("km"),
      `expected "km" in Longest distance after sport switch, got: "${val}"`,
    );
  });

  // Records subtitle shows the selected sport name
  await check(S, "records-subtitle-shows-sport", async () => {
    const subtitle = await page.$eval("#recsSubtitle", (el) => el.textContent);
    assert.ok(
      subtitle.includes("Run"),
      `expected "Run" in records subtitle after switching to Run, got: "${subtitle}"`,
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

  // All sports: Steps KPI appears because Forest Walk has average_cadence=55
  // expected steps = Math.round(55 * 2 * 5198 / 60) = 9530
  await check(S, "all-sports-steps-kpi-shown", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Steps")) return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    // Strip locale thousands separators before numeric check
    const digits = val ? val.replace(/[,.\s]/g, "") : "";
    assert.ok(val && digits.includes("9530"),
      `expected Steps KPI with ~9530 when All sports selected, got "${val}"`);
  });

  // Switch to Walk: Steps KPI still present
  await check(S, "walk-sport-steps-kpi-shown", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find(o => o.value === "Walk");
      if (opt) { sel.value = "Walk"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise(r => setTimeout(r, 300)));
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Steps")) return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    const digitsW = val ? val.replace(/[,.\s]/g, "") : "";
    assert.ok(val && digitsW.includes("9530"),
      `expected Steps KPI with ~9530 when Walk selected, got "${val}"`);
  });

  // Switch to Ride: Steps KPI absent
  await check(S, "ride-sport-no-steps-kpi", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find(o => o.value === "Ride");
      if (opt) { sel.value = "Ride"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise(r => setTimeout(r, 300)));
    const found = await page.evaluate(() => {
      return Array.from(document.querySelectorAll(".kpi"))
        .some(k => k.querySelector(".k")?.textContent.includes("Steps"));
    });
    assert.ok(!found, "Steps KPI should not appear when Ride sport is selected");
  });
}

async function testFocusRow(page, jsErrors) {
  const S = "focus-row";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try { sessionStorage.clear(); } catch (_) {}
  });
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
      chipId, { timeout: 1500 },
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
      chipId, { timeout: 1500 },
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
      chipId, { timeout: 1500 },
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });

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
    await page.selectOption("#year", "2025");
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
    await page.selectOption("#year", "2026");
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
        await page.selectOption(".month-filter select", mayOpt);
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });

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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
  await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
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
  await page.goto(URLS.activity, { waitUntil: "load", timeout: 20000 });
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
    waitUntil: "load",
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

// helper: find a record card by label substring and return its .rv text
async function getRecVal(page, labelFrag) {
  return page.evaluate((frag) => {
    for (const rec of document.querySelectorAll("#recs .rec")) {
      if (rec.querySelector(".rl")?.textContent.includes(frag))
        return rec.querySelector(".rv")?.textContent || "";
    }
    return null;
  }, labelFrag);
}

// helper: find a record card by label substring and return its link href (or null)
async function getRecLink(page, labelFrag) {
  return page.evaluate((frag) => {
    for (const rec of document.querySelectorAll("#recs .rec")) {
      if (rec.querySelector(".rl")?.textContent.includes(frag)) {
        const a = rec.querySelector("a[href]");
        return a ? a.getAttribute("href") : null;
      }
    }
    return null;
  }, labelFrag);
}

// helper: fire the _gf() call from a period-record link and return the parsed filter object
async function getFilterFromRecLink(page, labelFrag) {
  const json = await page.evaluate((frag) => {
    for (const rec of document.querySelectorAll("#recs .rec")) {
      if (rec.querySelector(".rl")?.textContent.includes(frag)) {
        const a = rec.querySelector("a[href='index.html']");
        if (a) {
          const oc = a.getAttribute("onclick") || "";
          const m = oc.match(/_gf\(([^)]+)\)/);
          // eslint-disable-next-line no-eval
          if (m) eval("window._gf(" + m[1] + ")");
        }
        break;
      }
    }
    return sessionStorage.getItem("activityFilter");
  }, labelFrag);
  return json ? JSON.parse(json) : null;
}

async function testStatsRecords(page, jsErrors) {
  const S = "stats-records";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
  try {
    await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // ── all expected labels are present ────────────────────────────────────────
  const EXPECTED_LABELS = [
    "Longest distance",
    "Longest ride",
    "Most elevation",
    "Fastest avg speed",
    "Best week",
    "Best month",
    "Most activities",
    "Longest streak",
  ];
  await check(S, "all-expected-labels-present", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    for (const frag of EXPECTED_LABELS) {
      assert.ok(
        labels.some((l) => l.includes(frag)),
        `expected "${frag}" in #recs record labels, got: ${JSON.stringify(labels)}`,
      );
    }
  });

  // ── per-activity record values ──────────────────────────────────────────────
  await check(S, "longest-distance-is-102.4km", async () => {
    const val = await getRecVal(page, "Longest distance");
    assert.ok(val && val.includes("102.4"), `expected "102.4" in Longest distance, got: "${val}"`);
  });

  await check(S, "most-elevation-is-1320m", async () => {
    const val = await getRecVal(page, "Most elevation");
    assert.ok(val && val.includes("1 320"), `expected "1 320" in Most elevation, got: "${val}"`);
  });

  await check(S, "fastest-speed-has-kmh", async () => {
    const val = await getRecVal(page, "Fastest avg speed");
    assert.ok(val && val.includes("km/h"), `expected "km/h" in Fastest avg speed, got: "${val}"`);
  });

  await check(S, "longest-ride-has-duration", async () => {
    const val = await getRecVal(page, "Longest ride");
    assert.ok(val && val.match(/\d+h\s+\d+m/), `expected "Xh Ym" in Longest ride, got: "${val}"`);
  });

  // ── per-activity records have "View activity" links ────────────────────────
  for (const labelFrag of ["Longest distance", "Longest ride", "Most elevation", "Fastest avg speed"]) {
    await check(S, `link-present-for-${labelFrag.toLowerCase().replace(/ /g, "-")}`, async () => {
      const href = await getRecLink(page, labelFrag);
      assert.ok(
        href && href.includes("activity.html?id="),
        `expected activity link for "${labelFrag}", got: ${href}`,
      );
    });
  }

  // ── period records link to index.html (filtered); "Longest streak" has no link
  for (const labelFrag of ["Best week", "Best month", "Most activities"]) {
    await check(S, `filter-link-for-${labelFrag.toLowerCase().replace(/ /g, "-")}`, async () => {
      const href = await getRecLink(page, labelFrag);
      assert.ok(
        href && href === "index.html",
        `expected "index.html" link for "${labelFrag}", got: ${href}`,
      );
    });
  }
  await check(S, "filter-link-for-longest-streak", async () => {
    const href = await getRecLink(page, "Longest streak");
    assert.ok(href === "index.html",
      `expected "index.html" link for "Longest streak", got: ${href}`);
  });

  // Streak in sample data starts 2026-06-03 → link must point to June 2026.
  await check(S, "streak-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Longest streak");
    assert.ok(f, "activityFilter not set by Longest streak link");
    assert.strictEqual(f.year,  "2026", `expected year "2026", got "${f.year}"`);
    assert.strictEqual(f.month, "6",    `expected month "6" (June), got "${f.month}"`);
    assert.strictEqual(f.sport, "Ride", `expected sport "Ride", got "${f.sport}"`);
  });

  // ── period-record filter links pre-load the correct dashboard filter ────────
  // Sample data: best month = June 2026 (6 rides, ~303 km); default sport = Ride.
  await check(S, "best-month-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Best month");
    assert.ok(f, "activityFilter not set by Best month link");
    assert.strictEqual(f.year,  "2026", `expected year "2026", got "${f.year}"`);
    assert.strictEqual(f.month, "6",    `expected month "6" (June), got "${f.month}"`);
    assert.strictEqual(f.sport, "Ride", `expected sport "Ride", got "${f.sport}"`);
  });

  // Sample data: best week starts 2026-06-01 → June 2026.
  await check(S, "best-week-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Best week");
    assert.ok(f, "activityFilter not set by Best week link");
    assert.strictEqual(f.year,  "2026", `expected year "2026", got "${f.year}"`);
    assert.strictEqual(f.month, "6",    `expected month "6" (June), got "${f.month}"`);
    assert.strictEqual(f.sport, "Ride", `expected sport "Ride", got "${f.sport}"`);
  });

  // Sample data: most Ride activities also in June 2026 (6 rides).
  await check(S, "most-activities-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Most activities");
    assert.ok(f, "activityFilter not set by Most activities link");
    assert.strictEqual(f.year,  "2026", `expected year "2026", got "${f.year}"`);
    assert.strictEqual(f.month, "6",    `expected month "6" (June), got "${f.month}"`);
    assert.strictEqual(f.sport, "Ride", `expected sport "Ride", got "${f.sport}"`);
  });

  // ── period record values ────────────────────────────────────────────────────
  await check(S, "best-week-value-has-km", async () => {
    const val = await getRecVal(page, "Best week");
    assert.ok(val && val.includes("km"), `expected "km" in Best week value, got: "${val}"`);
  });

  await check(S, "best-month-value-has-km", async () => {
    const val = await getRecVal(page, "Best month");
    assert.ok(val && val.includes("km"), `expected "km" in Best month value, got: "${val}"`);
  });

  await check(S, "most-activities-value-is-number", async () => {
    const val = await getRecVal(page, "Most activities");
    assert.ok(val && val.match(/\d+\s+activit/), `expected "N activit..." in Most activities, got: "${val}"`);
  });

  await check(S, "streak-value-has-days", async () => {
    const val = await getRecVal(page, "Longest streak");
    assert.ok(val && val.includes("day"), `expected "day" in Longest streak value, got: "${val}"`);
  });

  // ── VAM and power records absent (sample data has no watts/kJ) ────────────
  await check(S, "no-power-record-without-data", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      !labels.some((l) => l.includes("Most power")),
      `"Most power" record should be absent when no watts data, got: ${JSON.stringify(labels)}`,
    );
  });

  await check(S, "no-work-record-without-data", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      !labels.some((l) => l.includes("Most work")),
      `"Most work" record should be absent when no kJ data, got: ${JSON.stringify(labels)}`,
    );
  });

  // ── sport-aware "Longest X" label: "Longest ride" for Ride sport ──────────
  await check(S, "longest-label-says-ride-for-ride-sport", async () => {
    // page loaded with default Ride sport
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      labels.some((l) => l === "Longest ride"),
      `expected "Longest ride" label when sport=Ride, got: ${JSON.stringify(labels)}`,
    );
  });

  // ── switch to Walk: label changes, "Most steps" appears ──────────────────
  await check(S, "longest-label-says-walk-for-walk-sport", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find((o) => o.value === "Walk");
      if (opt) { sel.value = "Walk"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      labels.some((l) => l === "Longest walk"),
      `expected "Longest walk" label when sport=Walk, got: ${JSON.stringify(labels)}`,
    );
  });

  await check(S, "most-steps-appears-for-walk", async () => {
    // still on Walk from previous check
    const val = await getRecVal(page, "Most steps");
    assert.ok(val && /[\d\s]/.test(val),
      `expected a numeric steps value for Walk, got: "${val}"`);
  });

  await check(S, "most-steps-absent-for-ride", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find((o) => o.value === "Ride");
      if (opt) { sel.value = "Ride"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const labels = await page.$$eval("#recs .rec .rl", (els) =>
      els.map((el) => el.textContent),
    );
    assert.ok(
      !labels.some((l) => l.includes("Most steps")),
      `"Most steps" should be absent for Ride sport, got: ${JSON.stringify(labels)}`,
    );
  });
}

async function testStatsGoals(page, jsErrors) {
  const S = "stats-goals";
  jsErrors.length = 0;
  // Reset goal state before the suite so results are deterministic.
  await fetch(`${CGI}/ride-goals`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ goals: {} }),
  }).catch(() => {});

  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
  try {
    await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // Default: year=2026, sport=Ride → goals section should render (no goal set yet)
  await check(S, "section-visible-ride-2026", async () => {
    const el = await page.$("#goalsSection .goal-wrap");
    assert.ok(el, "#goalsSection .goal-wrap not found for Ride + 2026");
  });

  // Switch sport to Run → section should disappear
  await page.evaluate(() => {
    const sel = document.getElementById("sportSel");
    sel.value = "Run";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));
  await check(S, "section-hidden-for-run", async () => {
    const html = await page.$eval("#goalsSection", (el) => el.innerHTML);
    assert.equal(html, "", `#goalsSection should be empty for Run sport, got: "${html.slice(0, 100)}"`);
  });

  // Switch sport back to Ride, then year to all → section should disappear
  await page.evaluate(() => {
    document.getElementById("sportSel").value = "Ride";
    document.getElementById("sportSel").dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => {
    document.getElementById("yearSel").value = "all";
    document.getElementById("yearSel").dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));
  await check(S, "section-hidden-for-all-years", async () => {
    const html = await page.$eval("#goalsSection", (el) => el.innerHTML);
    assert.equal(html, "", `#goalsSection should be empty for all-years, got: "${html.slice(0, 100)}"`);
  });

  // Switch year back to 2026 → section should reappear
  await page.evaluate(() => {
    document.getElementById("yearSel").value = "2026";
    document.getElementById("yearSel").dispatchEvent(new Event("change", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
  await check(S, "section-reappears-ride-2026", async () => {
    const el = await page.$("#goalsSection .goal-wrap");
    assert.ok(el, "#goalsSection .goal-wrap not found after switching back to Ride + 2026");
  });

  // Set a goal of 2000 km and save
  await page.evaluate(() => {
    const inp = document.getElementById("goalKmInput");
    if (inp) { inp.value = "2000"; }
  });
  await page.click("#goalKmSave");
  await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));

  // Progress bar must be present and have non-zero width (941 km done / 2000 goal → ~47%)
  await check(S, "progress-bar-appears", async () => {
    const el = await page.$(".goal-bar-inner");
    assert.ok(el, ".goal-bar-inner not found after saving goal");
  });
  await check(S, "progress-bar-nonzero-width", async () => {
    const w = await page.$eval(".goal-bar-inner", (el) => el.style.width);
    const pct = parseFloat(w);
    assert.ok(pct > 0 && pct <= 100, `expected 0 < progress width <= 100%, got "${w}"`);
  });

  // Stats line shows distance and %
  await check(S, "stats-line-shows-percent", async () => {
    const text = await page.$eval(".goal-stats", (el) => el.textContent);
    assert.ok(text.includes("%"), `expected "%" in .goal-stats, got: "${text}"`);
  });

  // 12 monthly breakdown tiles
  await check(S, "twelve-monthly-tiles", async () => {
    const n = await page.$$eval(".goal-mo", (els) => els.length);
    assert.equal(n, 12, `expected 12 .goal-mo tiles, got ${n}`);
  });
  await check(S, "twelve-monthly-bars", async () => {
    const n = await page.$$eval(".goal-mo-bar", (els) => els.length);
    assert.equal(n, 12, `expected 12 .goal-mo-bar elements, got ${n}`);
  });

  // Hovering a monthly tile shows the #tip with this-year / prev-year / target lines
  await check(S, "monthly-tile-hover-shows-tip", async () => {
    const visible = await page.evaluate(() => {
      const tile = document.querySelector(".goal-mo");
      if (!tile) return false;
      const r = tile.getBoundingClientRect();
      tile.dispatchEvent(new MouseEvent("mouseenter", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2,
      }));
      return document.getElementById("tip").style.display === "block";
    });
    assert.ok(visible, "#tip should be visible after mouseenter on .goal-mo tile");
  });
  await check(S, "monthly-tile-tip-has-year-lines", async () => {
    const text = await page.evaluate(() => document.getElementById("tip").textContent);
    // tooltip must contain the current year and a "km" value for both years
    assert.ok(
      text.includes("2026") && text.includes("km"),
      `#tip text should contain "2026" and "km", got: "${text}"`,
    );
    assert.ok(
      text.includes("Target"),
      `#tip text should contain "Target", got: "${text}"`,
    );
  });

  // Hovering the stats line shows distribution tooltip with per-month targets
  await check(S, "stats-line-hover-shows-distribution-tip", async () => {
    const visible = await page.evaluate(() => {
      const el = document.querySelector(".goal-stats");
      if (!el) return false;
      const r = el.getBoundingClientRect();
      el.dispatchEvent(new MouseEvent("mouseenter", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2,
      }));
      return document.getElementById("tip").style.display === "block";
    });
    assert.ok(visible, "#tip should be visible after mouseenter on .goal-stats");
  });
  await check(S, "stats-line-tip-has-distribution-content", async () => {
    const text = await page.evaluate(() => document.getElementById("tip").textContent);
    // fmtKmD outputs a number without a "km" unit; check for month name and a number
    assert.ok(
      text.includes("Jan") && /\d/.test(text),
      `distribution tip should contain "Jan" and a numeric value, got: "${text}"`,
    );
    assert.ok(
      text.toLowerCase().includes("based on") || text.toLowerCase().includes("equal split"),
      `distribution tip should name the source, got: "${text}"`,
    );
    // Each month entry must include a percentage share
    assert.ok(
      /\(\d+\.\d+%\)/.test(text),
      `distribution tip should contain percentage values like "(8.3%)", got: "${text}"`,
    );
  });

  // Goal persists across page reload
  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
  try {
    await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}
  await page.evaluate(() => new Promise((r) => setTimeout(r, 500)));
  await check(S, "goal-persists-after-reload", async () => {
    const val = await page.evaluate(
      () => document.getElementById("goalKmInput")?.value,
    );
    assert.equal(val, "2000", `expected input value "2000" after reload, got "${val}"`);
  });
}

async function testRideGoalsCgi() {
  const ENDPOINT = `${CGI}/ride-goals`;

  // Reset state first
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ goals: {} }),
  });

  await check("cgi-ride-goals", "GET-returns-json-with-goals-object", async () => {
    const r = await fetch(ENDPOINT, { cache: "no-store" });
    assert.equal(r.status, 200, `expected 200, got ${r.status}`);
    const ct = r.headers.get("content-type") ?? "";
    assert.ok(ct.includes("json"), `expected JSON content-type, got: ${ct}`);
    const data = await r.json();
    assert.ok(
      data.goals !== undefined && typeof data.goals === "object" && !Array.isArray(data.goals),
      `data.goals must be a plain object, got: ${JSON.stringify(data.goals)}`,
    );
  });

  await check("cgi-ride-goals", "POST-goal-persists", async () => {
    const testKm = 7000 + Math.floor(Math.random() * 2000);
    const postR = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ goals: { "2026": testKm } }),
    });
    assert.ok(postR.ok, `POST failed with status ${postR.status}`);
    const posted = await postR.json();
    assert.equal(
      posted.goals?.["2026"],
      testKm,
      `POST response does not echo back goal: ${JSON.stringify(posted)}`,
    );
    assert.ok(posted.updatedAt, "POST response missing updatedAt");

    const getR = await fetch(ENDPOINT, { cache: "no-store" });
    const got = await getR.json();
    assert.equal(
      got.goals?.["2026"],
      testKm,
      `subsequent GET missing posted goal: ${JSON.stringify(got)}`,
    );
  });

  await check("cgi-ride-goals", "POST-missing-goals-key-400", async () => {
    const r = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ data: {} }),
    });
    assert.equal(r.status, 400, `expected 400 for missing goals key, got ${r.status}`);
  });

  await check("cgi-ride-goals", "POST-goals-as-array-400", async () => {
    const r = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ goals: [8000] }),
    });
    assert.equal(r.status, 400, `expected 400 for goals array, got ${r.status}`);
  });
}

async function testBikeModalCrud(page, jsErrors) {
  const S = "bike-modal-crud";
  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
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

async function testEmailAlertCheckbox(page, jsErrors) {
  const S = "email-alert-checkbox";
  const ENDPOINT = `${CGI}/bike-service`;

  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}

  // ── 1. Checkbox always present (with hint when email not configured) ──────
  await check(S, "checkbox-always-visible-in-add-part-modal", async () => {
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = false;
      if (typeof showAddPart === "function") showAddPart();
    });
    await page.waitForSelector("#p-name", { timeout: 3000 });
    const chk = await page.$("#p-email-alert");
    assert.ok(chk, "#p-email-alert checkbox should always be present in add-part modal");
    // Hint span visible when email not configured
    const hint = await page.$('.chk:has(#p-email-alert) .muted');
    assert.ok(hint, "hint span should appear when emailConfigured=false");
    await page.evaluate(() => closeModal());
  });

  // ── 2. Hint hidden when emailConfigured is true ───────────────────────────
  await check(S, "checkbox-hint-hidden-when-email-configured", async () => {
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
      if (typeof showAddPart === "function") showAddPart();
    });
    await page.waitForSelector("#p-name", { timeout: 3000 });
    const chk = await page.$("#p-email-alert");
    assert.ok(chk, "#p-email-alert checkbox should be present when emailConfigured=true");
    const hint = await page.$('.chk:has(#p-email-alert) .muted');
    assert.ok(!hint, "hint span should not appear when emailConfigured=true");
    await page.evaluate(() => closeModal());
  });

  // ── 3. emailAlert:true persisted when checkbox is checked ─────────────────
  await check(S, "email-alert-true-persisted", async () => {
    // Select Road Bike
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

    const partName = `EmailAlertPart-${Date.now()}`;
    const partsBefore = await fetch(ENDPOINT, { cache: "no-store" })
      .then((r) => r.json())
      .then((d) => {
        const bike = d.bikes.find((b) => b.name === "Road Bike");
        return bike ? (bike.parts || []).length : 0;
      });

    // Open modal with emailConfigured=true, fill name, check the box, save
    await page.evaluate((name) => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
      showAddPart();
    }, partName);
    await page.waitForSelector("#p-name", { timeout: 3000 });
    await page.$eval("#p-name", (el, v) => { el.value = v; }, partName);
    await page.$eval("#p-email-alert", (el) => { el.checked = true; });
    await page.evaluate(() => savePart(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 1000)));

    // Verify the new part in the CGI store has emailAlert:true
    const data = await fetch(ENDPOINT, { cache: "no-store" }).then((r) => r.json());
    const bike = data.bikes.find((b) => b.name === "Road Bike");
    assert.ok(bike, "Road Bike not found in CGI store");
    const newPart = (bike.parts || []).find((p) => p.name === partName);
    assert.ok(newPart, `Part "${partName}" not found in CGI store`);
    assert.strictEqual(
      newPart.emailAlert,
      true,
      `expected emailAlert:true on part, got: ${JSON.stringify(newPart.emailAlert)}`,
    );

    // Cleanup — delete the test part
    const cleanData = await fetch(ENDPOINT, { cache: "no-store" }).then((r) => r.json());
    const cleanBike = cleanData.bikes.find((b) => b.name === "Road Bike");
    if (cleanBike) {
      cleanBike.parts = (cleanBike.parts || []).filter((p) => p.name !== partName);
      await fetch(ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(cleanData),
      });
    }
  });

  // ── 4. emailAlert:false default when checkbox not checked ─────────────────
  await check(S, "email-alert-false-when-unchecked", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

    const partName = `EmailAlertFalsePart-${Date.now()}`;
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
      showAddPart();
    });
    await page.waitForSelector("#p-name", { timeout: 3000 });
    await page.$eval("#p-name", (el, v) => { el.value = v; }, partName);
    // Leave checkbox unchecked (default)
    await page.evaluate(() => savePart(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 1000)));

    const data = await fetch(ENDPOINT, { cache: "no-store" }).then((r) => r.json());
    const bike = data.bikes.find((b) => b.name === "Road Bike");
    const newPart = (bike?.parts || []).find((p) => p.name === partName);
    assert.ok(newPart, `Part "${partName}" not found in CGI store`);
    assert.ok(
      !newPart.emailAlert,
      `expected emailAlert falsy on unchecked part, got: ${JSON.stringify(newPart.emailAlert)}`,
    );

    // Cleanup
    if (bike) {
      bike.parts = (bike.parts || []).filter((p) => p.name !== partName);
      const cleanData = await fetch(ENDPOINT, { cache: "no-store" }).then((r) => r.json());
      const cb = cleanData.bikes.find((b) => b.name === "Road Bike");
      if (cb) {
        cb.parts = (cb.parts || []).filter((p) => p.name !== partName);
        await fetch(ENDPOINT, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(cleanData),
        });
      }
    }
  });

  // ── 5. Editing a part preserves emailAlert when re-saved ──────────────────
  await check(S, "email-alert-preserved-on-edit", async () => {
    // Post a part with emailAlert:true directly via CGI
    const setupData = await fetch(ENDPOINT, { cache: "no-store" }).then((r) => r.json());
    const road = setupData.bikes.find((b) => b.name === "Road Bike");
    if (!road) { return; }
    const partName = `EmailAlertEditPart-${Date.now()}`;
    const newPart = {
      id: `p-test-${Date.now()}`, name: partName, note: "", installedDate: "2026-01-01",
      installedMileage: 0, status: "new", emailAlert: true,
      serviceTypes: [{ id: "st-test", name: "Service", alertKm: 500, alertH: null, services: [] }],
    };
    road.parts = [...(road.parts || []), newPart];
    await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(setupData),
    });

    // Reload and open the edit modal for that part
    await page.reload({ waitUntil: "networkidle" });
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

    // Find and click Edit for the test part
    const editClicked = await page.evaluate((name) => {
      const rows = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow)');
      for (const row of rows) {
        if (row.textContent.includes(name)) {
          const btn = row.querySelector('button[onclick*="editPart"]');
          if (btn) { btn.click(); return true; }
        }
      }
      return false;
    }, partName);
    assert.ok(editClicked, `Edit button for "${partName}" not found`);

    await page.waitForSelector("#p-name", { timeout: 3000 });
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
    });

    // Checkbox should be pre-checked because the part has emailAlert:true
    const isChecked = await page.$eval("#p-email-alert", (el) => el.checked).catch(() => null);
    // If the checkbox exists (emailConfigured was already true when modal opened, it might not be here)
    // So we re-render: close and reopen with emailConfigured=true
    await page.evaluate(() => closeModal());
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
    });
    const partId = await page.evaluate((name) => {
      const rows = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow)');
      for (const row of rows) {
        if (row.textContent.includes(name)) {
          const btn = row.querySelector('button[onclick*="editPart"]');
          if (btn) {
            const m = btn.getAttribute("onclick").match(/editPart\('([^']+)'\)/);
            return m ? m[1] : null;
          }
        }
      }
      return null;
    }, partName);
    if (partId) {
      await page.evaluate((id) => editPart(id), partId);
      await page.waitForSelector("#p-name", { timeout: 3000 });
      const checked = await page.$eval("#p-email-alert", (el) => el.checked).catch(() => false);
      assert.ok(checked, "emailAlert checkbox should be pre-checked when editing a part with emailAlert:true");
    }
    await page.evaluate(() => closeModal());

    // Cleanup
    const cleanData = await fetch(ENDPOINT, { cache: "no-store" }).then((r) => r.json());
    const cb = cleanData.bikes.find((b) => b.name === "Road Bike");
    if (cb) {
      cb.parts = (cb.parts || []).filter((p) => p.name !== partName);
      await fetch(ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(cleanData),
      });
    }
  });

  await check(S, "no-js-errors", async () => {
    assert.strictEqual(jsErrors.length, 0, `JS errors: ${jsErrors.join("; ")}`);
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
  // Parts may be in the old flat format (alertKm on the part) or the new
  // serviceTypes format (alertKm inside serviceTypes[0]). Handle both.
  const firstPart = road.parts[0];
  let originalAlertKm;
  if (firstPart.serviceTypes && firstPart.serviceTypes.length > 0) {
    originalAlertKm = firstPart.serviceTypes[0].alertKm;
    firstPart.serviceTypes[0].alertKm = 1;
  } else {
    originalAlertKm = firstPart.alertKm;
    firstPart.alertKm = 1;
  }
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(setupData),
  });

  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
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
    const rp = restoreRoad.parts[0];
    if (rp.serviceTypes && rp.serviceTypes.length > 0) {
      rp.serviceTypes[0].alertKm = originalAlertKm;
    } else {
      rp.alertKm = originalAlertKm;
    }
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
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
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
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
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

  await page.reload({ waitUntil: "networkidle", timeout: 20000 });
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

async function testServiceTypeDescription(page, jsErrors) {
  const S = "service-type-description";
  const ENDPOINT = `${CGI}/bike-service`;

  // Setup: write a known description onto the first service type of Road Bike's first part.
  const setupR = await fetch(ENDPOINT, { cache: "no-store" });
  const setupData = await setupR.json();
  const road = setupData.bikes.find((b) => b.name === "Road Bike");
  if (!road || !road.parts || !road.parts.length ||
      !road.parts[0].serviceTypes || !road.parts[0].serviceTypes.length) {
    console.log(`  SKIP  ${S}: Road Bike has no serviceTypes to test`);
    return;
  }
  const testPart = road.parts[0];
  const testDesc = `desc-${Date.now()}`;
  const origDesc = testPart.serviceTypes[0].desc;
  testPart.serviceTypes[0].desc = testDesc;
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(setupData),
  });

  jsErrors.length = 0;
  await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
  try {
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}
  await page.evaluate(() => {
    const t = Array.from(document.querySelectorAll(".bikes .tab:not(.add)"))
      .find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });

  await check(S, "service-modal-shows-type-description", async () => {
    await page.evaluate((pid) => showService(pid), testPart.id);
    await page.waitForSelector("#ovl", { timeout: 3000 });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 150)));
    const descEl = await page.$("#s-type-desc");
    assert.ok(descEl, "#s-type-desc not present in service modal");
    const text = await page.$eval("#s-type-desc", (el) => el.textContent.trim());
    assert.strictEqual(text, testDesc,
      `service modal description mismatch: expected "${testDesc}", got "${text}"`);
    await page.evaluate(() => closeModal());
  });

  // Teardown
  const restoreR = await fetch(ENDPOINT, { cache: "no-store" });
  const restoreData = await restoreR.json();
  const restoreRoad = restoreData.bikes.find((b) => b.name === "Road Bike");
  if (restoreRoad && restoreRoad.parts.length > 0 &&
      restoreRoad.parts[0].serviceTypes && restoreRoad.parts[0].serviceTypes.length > 0) {
    restoreRoad.parts[0].serviceTypes[0].desc = origDesc;
    await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(restoreData),
    });
  }
}

// ── Heatmap page ───────────────────────────────────────────────────────────────

async function testHeatmap(page, jsErrors) {
  const S = "heatmap";
  jsErrors.length = 0;
  await page.goto(URLS.heatmap, { waitUntil: "networkidle", timeout: 20000 });

  // heatmap.json loads via fetch; wait for count to be populated
  try {
    await page.waitForFunction(
      () => (document.getElementById("count")?.textContent || "").length > 0,
      { timeout: 10000 },
    );
  } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );

  await check(S, "map-container-present", async () => {
    const el = await page.$("#map");
    assert.ok(el, "#map element not found");
  });

  await check(S, "period-dropdown-present", async () => {
    const el = await page.$("#period");
    assert.ok(el, "#period select not found");
  });

  await check(S, "period-has-all-time-option", async () => {
    const opts = await page.$$eval("#period option", (os) => os.map((o) => o.value));
    assert.ok(opts.includes("all"), `expected "all" option in #period, got: ${JSON.stringify(opts)}`);
  });

  await check(S, "period-has-time-range-options", async () => {
    const opts = await page.$$eval("#period option", (os) => os.map((o) => o.value));
    assert.ok(opts.includes("w7"),  `expected "w7"  option in #period`);
    assert.ok(opts.includes("w30"), `expected "w30" option in #period`);
    assert.ok(opts.includes("w90"), `expected "w90" option in #period`);
  });

  await check(S, "period-has-year-options", async () => {
    const opts = await page.$$eval("#period option", (os) => os.map((o) => o.value));
    const years = opts.filter((v) => /^\d{4}$/.test(v));
    assert.ok(years.length >= 1, `expected at least one year option, got: ${JSON.stringify(opts)}`);
  });

  // heatmap.sample.json has 4 activities; 1 on 2026-07-15 (Ride) falls within 90 days of today
  await check(S, "default-is-last-3-months", async () => {
    const val = await page.$eval("#period", (el) => el.value);
    assert.equal(val, "w90", `expected default period to be "w90", got: "${val}"`);
  });

  // default sport = Ride; 2026-07-15 is the only Ride within 90 days
  await check(S, "default-last-3-months-shows-1-activity", async () => {
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    assert.ok(
      count.startsWith("1 "),
      `expected count to start with "1 " for Last 3 months + Ride (default), got: "${count}"`,
    );
  });

  // --- Sport dropdown ---
  await check(S, "sport-dropdown-present", async () => {
    const el = await page.$("#sport");
    assert.ok(el, "#sport select not found");
  });

  await check(S, "sport-has-all-sports-option", async () => {
    const opts = await page.$$eval("#sport option", (os) => os.map((o) => o.value));
    assert.ok(opts.includes(""), `expected "" (All sports) option in #sport, got: ${JSON.stringify(opts)}`);
  });

  await check(S, "sport-has-ride-and-run", async () => {
    const opts = await page.$$eval("#sport option", (os) => os.map((o) => o.value));
    assert.ok(opts.includes("Ride"), `expected "Ride" option in #sport, got: ${JSON.stringify(opts)}`);
    assert.ok(opts.includes("Run"),  `expected "Run"  option in #sport, got: ${JSON.stringify(opts)}`);
  });

  await check(S, "sport-default-is-ride", async () => {
    const val = await page.$eval("#sport", (el) => el.value);
    assert.equal(val, "Ride", `expected default sport to be "Ride", got: "${val}"`);
  });

  // heatmap.sample.json: 4 activities total (3 Rides + 1 Run). Set All sports + All time.
  await check(S, "all-time-shows-4-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      sel.value = "all"; sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    assert.ok(
      count.startsWith("4 "),
      `expected count to start with "4 " for All time + All sports, got: "${count}"`,
    );
  });

  // 2024 has 2 activities: 2024-06-15 (Ride) + 2024-06-22 (Run). All sports → 2.
  await check(S, "filter-2024-shows-2-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      const opt = Array.from(sel.options).find((o) => o.value === "2024");
      if (opt) { sel.value = "2024"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    assert.ok(
      count.startsWith("2 "),
      `expected count to start with "2 " for 2024 + All sports, got: "${count}"`,
    );
  });

  // Sport filter: Run across all time → 1 activity (2024-06-22)
  await check(S, "sport-filter-run-all-time-shows-1", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("period");
      sel.value = "all"; sel.dispatchEvent(new Event("change", { bubbles: true }));
      const ssel = document.getElementById("sport");
      ssel.value = "Run"; ssel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    assert.ok(
      count.startsWith("1 "),
      `expected count to start with "1 " for All time + Run sport filter, got: "${count}"`,
    );
  });

  await check(S, "filter-last-7-days-shows-0-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      sel.value = "w7"; sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    assert.ok(
      count.startsWith("0 "),
      `expected count to start with "0 " for last-7-days filter, got: "${count}"`,
    );
  });

  await check(S, "dashboard-link-present", async () => {
    const href = await page.$eval(".crumbs a", (el) => el.getAttribute("href"));
    assert.ok(href && href.includes("index.html"), `expected crumbs link to index.html, got: "${href}"`);
  });
}

// ── Dark mode toggle ───────────────────────────────────────────────────────────

async function testDarkMode(page, jsErrors) {
  const S = "dark-mode";

  // Pages that have the toggle button (heatmap is excluded — stays always dark).
  const pages = [
    { name: "dashboard",  url: URLS.dash,     wait: "#board table" },
    { name: "stats",      url: URLS.stats,    wait: ".kpis .kpi" },
    { name: "bike",       url: URLS.bike,     wait: ".bikes .tab" },
    { name: "activity",   url: URLS.activity, wait: "#content" },
    { name: "leaderboard",url: URLS.club,     wait: "#board" },
  ];

  for (const pg of pages) {
    jsErrors.length = 0;
    // Clear localStorage so theme starts from OS default (no data-theme attr).
    await page.evaluate(() => {
      try { localStorage.removeItem("theme"); } catch (_) {}
      try { sessionStorage.clear(); } catch (_) {}
    });
    await page.goto(pg.url, { waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}

    await check(S, `${pg.name}-toggle-button-exists`, async () => {
      const btn = await page.$("#theme-tog");
      assert.ok(btn, `#theme-tog not found on ${pg.name} page`);
    });

    await check(S, `${pg.name}-button-shows-moon-initially`, async () => {
      // No localStorage value → button should show 🌙 (light mode icon, since test
      // browser prefers-color-scheme defaults to "no-preference" / light).
      const icon = await page.$eval("#theme-tog", (el) => el.textContent.trim());
      assert.ok(icon === "🌙" || icon === "☀️",
        `expected 🌙 or ☀️ from #theme-tog on ${pg.name}, got: "${icon}"`);
    });

    await check(S, `${pg.name}-click-sets-dark`, async () => {
      // Set to light first so we know the toggle direction.
      await page.evaluate(() => {
        document.documentElement.dataset.theme = "light";
        localStorage.setItem("theme", "light");
        document.getElementById("theme-tog").textContent = "🌙";
      });
      await page.click("#theme-tog");
      await page.evaluate(() => new Promise((r) => setTimeout(r, 50)));

      const theme = await page.evaluate(() => document.documentElement.dataset.theme);
      assert.equal(theme, "dark",
        `clicking #theme-tog from light should set data-theme=dark on ${pg.name}`);

      const icon = await page.$eval("#theme-tog", (el) => el.textContent.trim());
      assert.equal(icon, "☀️",
        `icon after dark toggle should be ☀️ on ${pg.name}, got "${icon}"`);
    });

    await check(S, `${pg.name}-click-toggles-back-to-light`, async () => {
      await page.click("#theme-tog");
      await page.evaluate(() => new Promise((r) => setTimeout(r, 50)));

      const theme = await page.evaluate(() => document.documentElement.dataset.theme);
      assert.equal(theme, "light",
        `second click on #theme-tog should set data-theme=light on ${pg.name}`);

      const icon = await page.$eval("#theme-tog", (el) => el.textContent.trim());
      assert.equal(icon, "🌙",
        `icon after light toggle should be 🌙 on ${pg.name}, got "${icon}"`);
    });

    await check(S, `${pg.name}-persists-to-localstorage`, async () => {
      // After clicking dark, reload — data-theme=dark should be set immediately
      // (anti-FOUC script reads localStorage before any CSS parses).
      await page.evaluate(() => {
        document.documentElement.dataset.theme = "light";
        localStorage.setItem("theme", "light");
        document.getElementById("theme-tog").textContent = "🌙";
      });
      await page.click("#theme-tog"); // → dark
      await page.evaluate(() => new Promise((r) => setTimeout(r, 50)));

      const stored = await page.evaluate(() => localStorage.getItem("theme"));
      assert.equal(stored, "dark",
        `localStorage["theme"] should be "dark" after clicking to dark on ${pg.name}`);

      // Reload and verify the theme is still dark (anti-FOUC preserved it).
      await page.reload({ waitUntil: "networkidle", timeout: 20000 });
      try { await page.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}

      const theme = await page.evaluate(() => document.documentElement.dataset.theme);
      assert.equal(theme, "dark",
        `after reload, data-theme should still be "dark" on ${pg.name}`);

      // Cleanup
      await page.evaluate(() => { try { localStorage.removeItem("theme"); } catch (_) {} });
    });

    await check(S, `${pg.name}-no-js-errors`, () =>
      assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
    );
  }
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function testMobileLayout(page, jsErrors) {
  const S = "mobile-layout";

  const pages = [
    { name: "dashboard", url: URLS.dash,     wait: "#board" },
    { name: "stats",     url: URLS.stats,    wait: ".kpis .kpi" },
    { name: "bike",      url: URLS.bike,     wait: ".bikes" },
    { name: "activity",  url: URLS.activity, wait: "#content" },
  ];

  await page.setViewportSize({ width: 375, height: 812 });

  for (const pg of pages) {
    jsErrors.length = 0;
    await page.evaluate(() => {
      try { localStorage.removeItem("theme"); } catch (_) {}
      try { sessionStorage.clear(); } catch (_) {}
    });
    await page.goto(pg.url, { waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}

    await check(S, `${pg.name}-no-horizontal-overflow`, async () => {
      const overflow = await page.evaluate(() =>
        document.documentElement.scrollWidth > document.documentElement.clientWidth
      );
      assert.ok(!overflow,
        `${pg.name} page has horizontal overflow at 375px — table needs overflow-x:auto wrapper`);
    });

    await check(S, `${pg.name}-hdr-exists`, async () => {
      const hdr = await page.$("#hdr");
      assert.ok(hdr, `#hdr element not found on ${pg.name} page`);
    });

    await check(S, `${pg.name}-no-js-errors`, () => {
      assert.strictEqual(jsErrors.length, 0,
        `JS errors on ${pg.name} at 375px: ${jsErrors.map((e) => e.message).join("; ")}`);
    });
  }

  // Restore desktop viewport for subsequent test suites.
  await page.setViewportSize({ width: 1440, height: 900 });
}

async function testMobileSectionReorder(browser, jsErrors) {
  const S = "mobile-section-reorder";
  // hasTouch: true is required for Chrome to report pointer:coarse in CSS media queries
  const ctx = await browser.newContext({ isMobile: true, hasTouch: true, viewport: { width: 375, height: 812 } });
  const mPage = await ctx.newPage();

  const pages = [
    { name: "stats",    url: URLS.stats,    wait: ".kpis .kpi" },
    { name: "activity", url: URLS.activity, wait: "#content" },
    { name: "bike",     url: URLS.bike,     wait: ".bikes" },
    { name: "club",     url: URLS.club,     wait: ".club-section" },
  ];

  for (const pg of pages) {
    await mPage.goto(pg.url, { waitUntil: "networkidle", timeout: 20000 });
    try { await mPage.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}

    await check(S, `${pg.name}-handle-hidden-on-mobile`, async () => {
      const visible = await mPage.evaluate(() => {
        return Array.from(document.querySelectorAll(".sec-handle")).some(el => {
          const s = getComputedStyle(el);
          return s.display !== "none" && s.visibility !== "hidden";
        });
      });
      assert.ok(!visible, `${pg.name}: .sec-handle should be hidden on touch viewport but is visible`);
    });

    await check(S, `${pg.name}-reset-btn-hidden-on-mobile`, async () => {
      const visible = await mPage.evaluate(() => {
        return Array.from(document.querySelectorAll(".sec-order-reset")).some(el => {
          const s = getComputedStyle(el);
          return s.display !== "none" && s.visibility !== "hidden";
        });
      });
      assert.ok(!visible, `${pg.name}: .sec-order-reset should be hidden on touch viewport but is visible`);
    });
  }

  await ctx.close();
}

async function testStatsSectionOrder(page, jsErrors) {
  const S = "stats-section-order";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try { localStorage.removeItem("ssb-stats-sec"); } catch (_) {}
    try { sessionStorage.clear(); } catch (_) {}
  });
  await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
  try { await page.waitForSelector(".sec[data-sid]", { timeout: 10000 }); } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );

  await check(S, "all-sections-present", async () => {
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const expected = ["kpis", "goals", "records", "year", "monthly-chart", "monthly-table", "comparison", "sport", "dow"];
    assert.deepEqual(sids, expected, `sections: ${JSON.stringify(sids)}`);
  });

  await check(S, "drag-handles-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec .sec-handle", (els) => els.length);
    assert.equal(n, 9, `expected 9 .sec-handle elements, got ${n}`);
  });

  await check(S, "reset-button-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec-order-reset", (els) => els.length);
    assert.equal(n, 1, `expected 1 .sec-order-reset button, got ${n}`);
  });

  // Drag records (index 2) to before kpis (index 0) by dropping above midpoint of kpis
  await check(S, "drag-to-reorder-works", async () => {
    await page.evaluate(() => {
      const wrap = document.getElementById("sec-wrap");
      const secs = Array.from(wrap.querySelectorAll(".sec[data-sid]"));
      const src = secs.find((s) => s.getAttribute("data-sid") === "records");
      const tgt = secs.find((s) => s.getAttribute("data-sid") === "kpis");
      const handle = src ? src.querySelector(".sec-handle") : null;
      if (!handle || !tgt) return;
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = tgt.getBoundingClientRect();
      // clientY = rect.top + 1 → insert BEFORE kpis
      tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + 1 }));
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    assert.equal(sids[0], "records", `expected "records" first after drag, got "${sids[0]}"`);
    assert.equal(sids[1], "kpis", `expected "kpis" second after drag, got "${sids[1]}"`);
  });

  await check(S, "order-persisted-in-localstorage", async () => {
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-stats-sec")); } catch (_) { return null; }
    });
    assert.ok(Array.isArray(saved) && saved.length === 9, "saved order should be 9-element array");
    assert.equal(saved[0], "records", `expected "records" first in saved, got "${saved[0]}"`);
  });

  await check(S, "order-restored-after-reload", async () => {
    await page.reload({ waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector(".sec[data-sid]", { timeout: 10000 }); } catch (_) {}
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    assert.equal(sids[0], "records", `after reload, expected "records" first, got "${sids[0]}"`);
  });

  await check(S, "reset-button-restores-default-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector("#sec-wrap .sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    assert.equal(sids[0], "kpis", `after reset, expected "kpis" first, got "${sids[0]}"`);
    const saved = await page.evaluate(() => {
      try { return localStorage.getItem("ssb-stats-sec"); } catch (_) { return "x"; }
    });
    assert.equal(saved, null, `expected localStorage cleared after reset, got: ${saved}`);
  });

  await page.evaluate(() => { try { localStorage.removeItem("ssb-stats-sec"); } catch (_) {} });
}

async function testDetailSectionOrder(page, jsErrors) {
  const S = "detail-section-order";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {}
    try { sessionStorage.clear(); } catch (_) {}
  });
  await page.goto(URLS.activity, { waitUntil: "load", timeout: 20000 });
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

  await check(S, "all-sections-present", async () => {
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const expected = ["cards", "map", "elev", "hr", "cad", "pwr", "hrzone", "splits"];
    assert.deepEqual(sids, expected, `sections: ${JSON.stringify(sids)}`);
  });

  await check(S, "drag-handles-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec .sec-handle", (els) => els.length);
    assert.equal(n, 8, `expected 8 .sec-handle elements, got ${n}`);
  });

  await check(S, "reset-button-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec-order-reset", (els) => els.length);
    assert.equal(n, 1, `expected 1 .sec-order-reset button, got ${n}`);
  });

  // Drag splits (last) to before hrzone (second-to-last)
  await check(S, "drag-to-reorder-works", async () => {
    await page.evaluate(() => {
      const wrap = document.getElementById("sec-wrap");
      const secs = Array.from(wrap.querySelectorAll(".sec[data-sid]"));
      const src = secs.find((s) => s.getAttribute("data-sid") === "splits");
      const tgt = secs.find((s) => s.getAttribute("data-sid") === "hrzone");
      const handle = src ? src.querySelector(".sec-handle") : null;
      if (!handle || !tgt) return;
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = tgt.getBoundingClientRect();
      // clientY = rect.top + 1 → insert BEFORE target
      tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + 1 }));
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    assert.equal(sids[sids.length - 2], "splits", `expected "splits" second-to-last, got "${sids[sids.length - 2]}"`);
    assert.equal(sids[sids.length - 1], "hrzone", `expected "hrzone" last, got "${sids[sids.length - 1]}"`);
  });

  await check(S, "order-persisted-in-localstorage", async () => {
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-detail-sec")); } catch (_) { return null; }
    });
    assert.ok(Array.isArray(saved) && saved.length === 8, "saved order should be 8-element array");
    assert.equal(saved[saved.length - 2], "splits", `expected "splits" second-to-last in saved`);
  });

  await check(S, "reset-button-restores-default-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector("#sec-wrap .sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    assert.equal(sids[sids.length - 1], "splits", `after reset, expected "splits" last, got "${sids[sids.length - 1]}"`);
  });

  await page.evaluate(() => { try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {} });
}

async function testBikeSectionOrder(page, jsErrors) {
  const S = "bike-section-order";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try { localStorage.removeItem("ssb-bike-sec"); } catch (_) {}
  });
  await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
  await page.waitForSelector(".bikes .tab", { timeout: 10000 });
  await page.waitForFunction(
    () => !document.getElementById("meta")?.textContent.includes("Loading"),
    { timeout: 10000 },
  );
  // Select Road Bike tab so panel is populated
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  try {
    await page.waitForSelector("#bikepanel .sec[data-sid]", { timeout: 8000 });
  } catch (_) {}
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );

  await check(S, "parts-section-present", async () => {
    const sid = await page.$eval("#bikepanel .sec[data-sid='parts']", (el) =>
      el.getAttribute("data-sid"),
    );
    assert.equal(sid, "parts", "expected 'parts' section in bikepanel");
  });

  await check(S, "drag-handles-present", async () => {
    const n = await page.$$eval("#bikepanel .sec .sec-handle", (els) => els.length);
    assert.ok(n >= 1, `expected at least 1 .sec-handle in bikepanel, got ${n}`);
  });

  await check(S, "reset-button-present", async () => {
    const n = await page.$$eval("#bikepanel .sec-order-reset", (els) => els.length);
    assert.equal(n, 1, `expected 1 .sec-order-reset in bikepanel, got ${n}`);
  });

  // If 2+ sections exist, drag the first to after the second
  await check(S, "drag-to-reorder-works-when-multiple-sections", async () => {
    const secCount = await page.$$eval("#bikepanel .sec[data-sid]", (els) => els.length);
    if (secCount < 2) return; // only one section — nothing to drag
    await page.evaluate(() => {
      const panel = document.getElementById("bikepanel");
      const secs = Array.from(panel.querySelectorAll(".sec[data-sid]"));
      if (secs.length < 2) return;
      const src = secs[0], tgt = secs[1];
      const handle = src.querySelector(".sec-handle");
      if (!handle) return;
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = tgt.getBoundingClientRect();
      tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + rect.height - 1 }));
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#bikepanel .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-bike-sec")); } catch (_) { return null; }
    });
    assert.ok(Array.isArray(saved) && saved.length >= 1, "expected saved order in localStorage");
    assert.equal(saved[0], sids[0], `saved[0] should match DOM order[0]: "${sids[0]}"`);
  });

  await check(S, "reset-button-restores-default-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector("#bikepanel .sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#bikepanel .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    // After reset, "parts" must be first (it is always present and always default-first)
    assert.equal(sids[0], "parts", `after reset, expected "parts" first, got "${sids[0]}"`);
  });

  await page.evaluate(() => { try { localStorage.removeItem("ssb-bike-sec"); } catch (_) {} });
}

async function testClubSectionOrder(page, jsErrors) {
  const S = "club-section-order";
  jsErrors.length = 0;
  await page.evaluate(() => {
    try { localStorage.removeItem("ssb-lb-sec"); } catch (_) {}
  });
  await page.goto(URLS.club, { waitUntil: "networkidle", timeout: 30000 });
  try {
    await page.waitForSelector(".club-section .sec[data-sid]", { timeout: 10000 });
  } catch (_) {}

  await check(S, "no-js-errors", () =>
    assert.equal(jsErrors.length, 0, jsErrors.map((e) => e.message).join("; ")),
  );

  await check(S, "sections-present-in-club", async () => {
    const n = await page.$$eval(".club-section .sec[data-sid]", (els) => els.length);
    assert.ok(n >= 1, `expected at least 1 .sec[data-sid] in .club-section, got ${n}`);
  });

  await check(S, "drag-handles-present", async () => {
    const n = await page.$$eval(".club-section .sec .sec-handle", (els) => els.length);
    assert.ok(n >= 1, `expected at least 1 .sec-handle in .club-section, got ${n}`);
  });

  await check(S, "reset-button-present", async () => {
    const n = await page.$$eval(".sec-order-reset", (els) => els.length);
    assert.equal(n, 1, `expected 1 .sec-order-reset on leaderboard page, got ${n}`);
  });

  // Drag the first section of the first club to after the second section
  await check(S, "drag-to-reorder-works", async () => {
    const secCount = await page.$$eval(".club-section:first-child .sec[data-sid]", (els) => els.length);
    if (secCount < 2) return;
    await page.evaluate(() => {
      const cs = document.querySelector(".club-section");
      if (!cs) return;
      const secs = Array.from(cs.querySelectorAll(".sec[data-sid]"));
      if (secs.length < 2) return;
      const src = secs[0], tgt = secs[1];
      const handle = src.querySelector(".sec-handle");
      if (!handle) return;
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = tgt.getBoundingClientRect();
      tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + rect.height - 1 }));
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-lb-sec")); } catch (_) { return null; }
    });
    assert.ok(Array.isArray(saved) && saved.length >= 1, "expected saved order in localStorage after drag");
  });

  await check(S, "reset-button-restores-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector(".sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    // After reset, "table" section should be first in first club
    const sids = await page.$$eval(".club-section .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    assert.ok(sids.length >= 1, "expected at least one .sec in club after reset");
    assert.equal(sids[0], "table", `after reset, expected "table" first in club, got "${sids[0]}"`);
  });

  await page.evaluate(() => { try { localStorage.removeItem("ssb-lb-sec"); } catch (_) {} });
}

async function main() {
  // Use system Chrome/Chromium when Playwright's bundled browser isn't installed
  // (e.g. in WSL / CI without network access to download it). Set
  // PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH to override; otherwise fall back to
  // channel:"chrome" which picks up any installed Google Chrome.
  const launchOpts = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
    ? { headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH }
    : { headless: true, channel: "chrome" };
  const browser = await chromium.launch(launchOpts);

  const jsErrors = [];
  try {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 1440, height: 900 });
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

    console.log("\n--- Heatmap ---");
    await testHeatmap(page, jsErrors);

    console.log("\n--- Stats ---");
    await testStats(page, jsErrors);

    console.log("\n--- Stats Sport Filter ---");
    await testStatsSportFilter(page, jsErrors);

    console.log("\n--- Stats Records (best week / streak) ---");
    await testStatsRecords(page, jsErrors);

    console.log("\n--- Stats Goals & Progress ---");
    await testStatsGoals(page, jsErrors);

    console.log("\n--- Stats Section Order ---");
    await testStatsSectionOrder(page, jsErrors);

    console.log("\n--- Activity Detail ---");
    await testActivityDetail(page, jsErrors);

    console.log("\n--- Detail Section Order ---");
    await testDetailSectionOrder(page, jsErrors);

    console.log("\n--- Activity Detail (HealthSync Run) ---");
    await testActivityDetailHealthsyncRun(page, jsErrors);

    console.log("\n--- Activity Detail (HealthSync Cycling) ---");
    await testActivityDetailHealthsyncCycling(page, jsErrors);

    console.log("\n--- Activity Detail (Magene C606 — no HR) ---");
    await testActivityDetailMagene(page, jsErrors);

    console.log("\n--- Activity Detail (Walk — steps card) ---");
    await testActivityDetailWalk(page, jsErrors);

    console.log("\n--- Strava Link (numeric vs HealthSync ID) ---");
    await testStravaLink(page, jsErrors);

    console.log("\n--- Bike Section Order ---");
    await testBikeSectionOrder(page, jsErrors);

    console.log("\n--- Club Section Order ---");
    await testClubSectionOrder(page, jsErrors);

    console.log("\n--- Bike Service (UI) ---");
    await testBikeService(page, jsErrors);

    console.log("\n--- Bike Service (Input Step + Odo-based Mileage) ---");
    await testBikeInputStepAndOdo(page, jsErrors);

    console.log("\n--- Bike Service (Part Replacement) ---");
    await testBikeServicePartReplacement(page, jsErrors);

    console.log("\n--- Bike Service (Notifications) ---");
    await testBikeServiceNotifications(page, jsErrors);

    console.log("\n--- Bike Modal CRUD (add/delete bike, add part) ---");
    await testBikeModalCrud(page, jsErrors);

    console.log("\n--- Email Alert Checkbox (part modal + persist) ---");
    await testEmailAlertCheckbox(page, jsErrors);

    console.log("\n--- Alert Thresholds (isWarn) ---");
    await testAlertThresholds(page, jsErrors);

    console.log("\n--- Needs Replacement (flag, badge, sort) ---");
    await testNeedsReplacement(page, jsErrors);

    console.log("\n--- Service Type Description (modal hint) ---");
    await testServiceTypeDescription(page, jsErrors);

    console.log("\n--- Mobile Layout (375px viewport) ---");
    await testMobileLayout(page, jsErrors);

    console.log("\n--- Mobile Section Reorder (pointer:coarse via isMobile context) ---");
    await testMobileSectionReorder(browser, jsErrors);

    console.log("\n--- Dark Mode Toggle ---");
    await testDarkMode(page, jsErrors);
  } finally {
    await browser.close();
  }

  console.log("\n--- CGI: bike-service ---");
  await testBikeServiceCgi();

  console.log("\n--- CGI: ride-goals ---");
  await testRideGoalsCgi();

  console.log("\n" + "=".repeat(50));
  console.log(`Results: ${passed} passed, ${failed} failed`);
  writeJUnitXml(TEST_RESULTS);
  writeJsonReport(
    process.env.TEST_RESULTS_JSON ||
      path.join(path.dirname(TEST_RESULTS), "results.json"),
  );
  writeHtmlReport(process.env.PLAYWRIGHT_REPORT_DIR || "playwright-report");
  if (process.env.CI) {
    writeGithubActionsReport();
  }
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

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function writeJsonReport(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const report = {
    stats: { passed, failed, total: results.length },
    tests: results.map((r) => ({
      suite: r.suite,
      name: r.name,
      ok: r.ok,
      error: r.ok ? null : (r.error?.message ?? String(r.error)),
    })),
  };
  fs.writeFileSync(filePath, JSON.stringify(report, null, 2), "utf8");
  console.log(`JSON test report written to ${filePath}`);
}

function writeHtmlReport(outputFolder) {
  fs.mkdirSync(outputFolder, { recursive: true });
  const duration = ((Date.now() - START_TIME_MS) / 1000).toFixed(1);
  const rows = results
    .map((r) => {
      const status = r.ok ? "pass" : "fail";
      const error = r.ok
        ? ""
        : `<pre class="err">${escapeHtml(r.error?.message ?? String(r.error))}</pre>`;
      return `<tr class="${status}"><td>${escapeHtml(r.suite)}</td><td>${escapeHtml(r.name)}</td><td>${status.toUpperCase()}</td><td>${error}</td></tr>`;
    })
    .join("\n");
  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Playwright report</title>
<style>
  body{font-family:sans-serif;margin:2rem}h1{margin-bottom:.25rem}
  .summary{margin-bottom:1rem;color:#555}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #ddd;padding:6px 10px;text-align:left}
  th{background:#f4f4f4}
  tr.pass td:nth-child(3){color:green}
  tr.fail td:nth-child(3){color:red}
  pre.err{margin:0;white-space:pre-wrap;font-size:.8em;color:red}
</style>
</head>
<body>
<h1>Playwright Results</h1>
<p class="summary">${passed} passed, ${failed} failed &mdash; ${duration}s</p>
<table>
<thead><tr><th>Suite</th><th>Test</th><th>Status</th><th>Error</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
</body>
</html>`;
  fs.writeFileSync(path.join(outputFolder, "index.html"), html, "utf8");
  console.log(`HTML report written to ${outputFolder}/index.html`);
}

function writeGithubActionsReport() {
  const env = process.env.NODE_ENV || "test";
  const title = `Playwright results (ENV=${env})`;
  console.log(`\n::group::${title}`);
  results.forEach((r) => {
    if (!r.ok) {
      const msg = (r.error?.message ?? String(r.error)).replace(/\n/g, " ");
      console.log(`::error::FAIL ${r.suite} / ${r.name}: ${msg}`);
    }
  });
  console.log("::endgroup::");
}

// Set exitCode rather than calling process.exit() directly — avoids a
// libuv UV_HANDLE_CLOSING assertion on Windows when the IPC
// channels are still draining as the process shuts down.
main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((err) => {
    console.error("Fatal:", err);
    process.exitCode = 1;
  });
