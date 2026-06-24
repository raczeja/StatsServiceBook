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
import assert from "assert/strict";

const BASE = "http://localhost:8080/strava/me";
const CGI = "http://localhost:8080/cgi-bin";
const URLS = {
  club: "http://localhost:8080/strava/index.html",
  dash: `${BASE}/index.html`,
  stats: `${BASE}/stats.html`,
  activity: `${BASE}/activity.html?id=18784255013`,
  bike: `${BASE}/bike.html`,
};

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

function findBrowser() {
  for (const p of BROWSER_CANDIDATES) {
    if (fs.existsSync(p)) return p;
  }

  const bundled = puppeteer.executablePath?.();
  if (bundled && fs.existsSync(bundled)) return bundled;

  throw new Error(
    "Browser not found. Set BROWSER_PATH or EDGE_PATH to a Chrome/Chromium executable path, or install puppeteer with its bundled browser.",
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
    const n = await page.$$eval("#board tbody tr", (rows) => rows.length);
    assert.ok(n >= 1, `expected >= 1 row, got ${n}`);
  });
  // club-activities.sample.json: 4 athletes, each gets one leaderboard row
  await check(S, "4-athlete-rows", async () => {
    const n = await page.$$eval("#board tbody tr", (rows) => rows.length);
    assert.equal(n, 4, `expected 4 athlete rows, got ${n}`);
  });
  // Alex R has the highest km in June 2026 (150.4 km across 3 rides) → rank 1
  await check(S, "first-place-Alex", async () => {
    const name = await page.$eval(
      "#board tbody tr:first-child td:nth-child(2)",
      (el) => el.textContent.trim(),
    );
    assert.ok(
      name.startsWith("Alex"),
      `expected first place "Alex…", got "${name}"`,
    );
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
  // Default filter: year=2026, month=6 (June), sport=Ride → 5 rides, 271.8 km
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
      text.includes("5 activities"),
      `expected "5 activities" in #meta: ${text}`,
    );
  });
  await check(S, "summary-distance", async () => {
    const text = await page.$eval("#summary", (el) => el.textContent);
    // 271 755.8 m rounds to 272 km in the page's display formatting
    assert.ok(text.includes("272"), `expected "272" km in #summary: ${text}`);
  });
  await check(S, "table-5-rows", async () => {
    const n = await page.$$eval("#board tbody tr", (rows) => rows.length);
    assert.equal(n, 5, `expected 5 Ride rows for June 2026, got ${n}`);
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

  // KPI: Activities = 16
  await check(S, "kpi-activities-16", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    assert.equal(val, "16", `expected KPI Activities="16", got "${val}"`);
  });

  // KPI: Distance includes "824"
  await check(S, "kpi-distance-824", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Distance"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    assert.ok(
      val && val.includes("824"),
      `expected "824" in distance KPI, got "${val}"`,
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
    // 4 bikes from sample + 1 auto-seeded from gear b-anon-1 (Bike A in activities.json)
    assert.ok(n >= 4, `expected >= 4 bike tabs, got ${n}`);
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

// ── CGI round-trip (plain fetch, no browser) ───────────────────────────────────

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
    const chain = road.parts.find((p) => p.name === "Chain");
    assert.ok(chain, '"Chain" part not found for POST test');

    chain.services.push({
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
    const vChain = vRoad?.parts.find((p) => p.name === "Chain");
    const found = vChain?.services.some((s) => s.note === testNote);
    assert.ok(found, `POST'd service note not found on subsequent GET`);
  });
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const executablePath = findBrowser();
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

    console.log("\n--- Stats ---");
    await testStats(page, jsErrors);

    console.log("\n--- Activity Detail ---");
    await testActivityDetail(page, jsErrors);

    console.log("\n--- Bike Service (UI) ---");
    await testBikeService(page, jsErrors);
  } finally {
    await browser.close();
  }

  console.log("\n--- CGI: bike-service ---");
  await testBikeServiceCgi();

  console.log("\n" + "=".repeat(50));
  console.log(`Results: ${passed} passed, ${failed} failed`);
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
