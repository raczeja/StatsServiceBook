/**
 * screenshot.mjs — takes screenshots of all pages and bike-service modal states.
 * Called by make-screenshots.ps1 after the Podman test container is running.
 * Uses Playwright (installed in the same dir as the functional test suite).
 *
 * Usage:
 *   node screenshot.mjs <outputDir>
 */
import { chromium } from "@playwright/test";
import fs from "fs";
import path from "path";

const outDir = process.argv[2];
if (!outDir) {
  console.error("Usage: node screenshot.mjs <outputDir>");
  process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });

const PORT = process.env.TEST_PORT || process.env.STRAVA_TEST_PORT || "8080";
const HOST = process.env.TEST_HOST || "localhost";
const BASE = `http://${HOST}:${PORT}/strava/me`;

const PAGES = [
  { name: "club-dashboard",       url: `http://${HOST}:${PORT}/strava/index.html`, dark: false },
  { name: "club-dashboard-dark",  url: `http://${HOST}:${PORT}/strava/index.html`, dark: true  },
  { name: "my-activities",        url: `${BASE}/index.html`,                       dark: false },
  { name: "stats",                url: `${BASE}/stats.html`,                       dark: false },
  { name: "heatmap",              url: `${BASE}/heatmap.html`,                     dark: false },
  { name: "activity-detail",      url: `${BASE}/activity.html?id=18784255013`,     dark: false },
  { name: "bike-service",         url: `${BASE}/bike.html`,                        dark: false },
  // Dark mode variants
  { name: "my-activities-dark",   url: `${BASE}/index.html`,                       dark: true  },
  { name: "stats-dark",           url: `${BASE}/stats.html`,                       dark: true  },
  { name: "activity-detail-dark", url: `${BASE}/activity.html?id=18784255013`,     dark: true  },
  { name: "bike-service-dark",    url: `${BASE}/bike.html`,                        dark: true  },
];

// Navigate to url briefly to establish origin, then set localStorage theme.
// The caller does the full navigation separately so waits can be customised.
async function setTheme(page, url, dark) {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 });
  await page.evaluate((isDark) => {
    if (isDark) localStorage.setItem("theme", "dark"); else localStorage.removeItem("theme");
  }, dark);
}

async function shot(page, name) {
  const file = path.join(outDir, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`  saved ${file}`);
}

async function waitBikeReady(page) {
  await page.waitForSelector(".bikes .tab", { timeout: 10000 });
  await page.waitForFunction(
    () => !document.getElementById("meta")?.textContent.includes("Loading"),
    { timeout: 10000 },
  );
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
}

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1440, height: 900 });

  // ── Standard full-page screenshots ───────────────────────────────────────────
  for (const { name, url, dark } of PAGES) {
    console.log(`→ ${name}: ${url}${dark ? " [dark]" : ""}`);
    await setTheme(page, url, dark);

    if (name === "heatmap") {
      // Use 'load' — map tiles keep requests in flight so networkidle would block.
      await page.goto(url, { waitUntil: "load", timeout: 45000 });
      try {
        await page.waitForFunction(() => typeof L !== "undefined", { timeout: 15000 });
      } catch (_) { console.warn("  Leaflet did not load from CDN"); }
      try {
        await page.waitForFunction(
          () => (document.getElementById("count")?.textContent || "").length > 0,
          { timeout: 12000 },
        );
      } catch (_) {}
      await page.evaluate(() => {
        const ssel = document.getElementById("sport");
        if (ssel) { ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true })); }
        const psel = document.getElementById("period");
        if (psel) { psel.value = "all"; psel.dispatchEvent(new Event("change", { bubbles: true })); }
      });
      // Wait for all tiles to finish after fitBounds + tile reload from filter change.
      try {
        await page.waitForFunction(
          () => {
            const loaded  = document.querySelectorAll(".leaflet-tile-loaded");
            const loading = document.querySelectorAll(".leaflet-tile:not(.leaflet-tile-loaded)");
            return loaded.length > 0 && loading.length === 0;
          },
          { timeout: 20000 },
        );
      } catch (_) { console.warn("  Tiles still loading after 20 s — taking screenshot anyway"); }
      await page.evaluate(() => new Promise((r) => setTimeout(r, 1200)));
    } else {
      await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
    }

    await shot(page, name);
  }

  // ── Bike-service modal screenshots (light mode) ──────────────────────────────
  console.log("→ bike modal screenshots");
  await page.evaluate(() => { try { localStorage.removeItem("theme"); } catch (_) {} });
  await page.goto(`${BASE}/bike.html`, { waitUntil: "networkidle", timeout: 20000 });
  await waitBikeReady(page);

  console.log("  → bike-modal-add-bike");
  await page.evaluate(() => showAddBike());
  await page.waitForSelector("#b-name", { timeout: 3000 });
  await shot(page, "bike-modal-add-bike");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  console.log("  → bike-modal-edit-bike");
  await page.evaluate(() => {
    const btns = document.querySelectorAll("#bikepanel .btn.sm");
    const b = Array.from(btns).find((el) => el.textContent.includes("Edit bike"));
    if (b) b.click();
  });
  await page.waitForSelector("#b-name", { timeout: 3000 });
  await shot(page, "bike-modal-edit-bike");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  console.log("  → bike-modal-add-part");
  await page.evaluate(() => showAddPart());
  await page.waitForSelector("#p-name", { timeout: 3000 });
  await shot(page, "bike-modal-add-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  console.log("  → bike-modal-edit-part");
  await page.evaluate(() => {
    const btns = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow) button[onclick*="editPart"]');
    if (btns[0]) btns[0].click();
  });
  await page.waitForSelector("#p-name", { timeout: 3000 });
  await shot(page, "bike-modal-edit-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  console.log("  → bike-modal-service-part");
  await page.evaluate(() => {
    const btns = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showService"]');
    if (btns[0]) btns[0].click();
  });
  await page.waitForSelector("#f-date", { timeout: 3000 });
  await shot(page, "bike-modal-service-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  console.log("  → bike-modal-replace-part");
  await page.evaluate(() => {
    const btns = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showReplace"]');
    if (btns[0]) btns[0].click();
  });
  await page.waitForSelector("#r-note", { timeout: 3000 });
  await shot(page, "bike-modal-replace-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  // ── Multi-bike overview screenshots ──────────────────────────────────────────
  async function shotMultiBike(darkMode, shotName) {
    await page.evaluate((isDark) => {
      try { if (isDark) localStorage.setItem("theme", "dark"); else localStorage.removeItem("theme"); } catch (_) {}
    }, darkMode);
    await page.goto(`${BASE}/bike.html`, { waitUntil: "networkidle", timeout: 20000 });
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
    await page.evaluate(() => new Promise((r) => setTimeout(r, 400)));
    const file = path.join(outDir, `${shotName}.png`);
    await page.screenshot({ path: file, fullPage: true });
    console.log(`  saved ${file}`);
  }

  console.log("  → bike-stats-multi");
  await shotMultiBike(false, "bike-stats-multi");

  console.log("  → bike-stats-multi-dark");
  await shotMultiBike(true, "bike-stats-multi-dark");

  // ── Section-reorder screenshots ──────────────────────────────────────────────
  console.log("→ stats-section-reorder");
  await page.evaluate(() => { try { localStorage.removeItem("theme"); localStorage.removeItem("ssb-stats-sec"); } catch (_) {} });
  await page.goto(`${BASE}/stats.html`, { waitUntil: "networkidle", timeout: 30000 });
  try { await page.waitForSelector(".sec[data-sid]", { timeout: 10000 }); } catch (_) {}
  try {
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}
  await page.evaluate(() => {
    const wrap = document.getElementById("sec-wrap");
    const secs = Array.from(wrap ? wrap.querySelectorAll(".sec[data-sid]") : []);
    const src = secs.find((s) => s.getAttribute("data-sid") === "kpis");
    const tgt = secs.find((s) => s.getAttribute("data-sid") === "records");
    const handle = src ? src.querySelector(".sec-handle") : null;
    if (!handle || !tgt) return;
    handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
    const rect = tgt.getBoundingClientRect();
    tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + rect.height - 1 }));
    handle.dispatchEvent(new Event("dragend", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));
  await shot(page, "stats-section-reorder");
  await page.evaluate(() => { try { localStorage.removeItem("ssb-stats-sec"); } catch (_) {} });

  console.log("→ detail-section-reorder");
  await page.evaluate(() => { try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {} });
  await page.goto(`${BASE}/activity.html?id=18784255013`, { waitUntil: "networkidle", timeout: 30000 });
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}
  await page.evaluate(() => {
    const wrap = document.getElementById("sec-wrap");
    const secs = Array.from(wrap ? wrap.querySelectorAll(".sec[data-sid]") : []);
    const src = secs.find((s) => s.getAttribute("data-sid") === "splits");
    const tgt = secs.find((s) => s.getAttribute("data-sid") === "hrzone");
    const handle = src ? src.querySelector(".sec-handle") : null;
    if (!handle || !tgt) return;
    handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
    const rect = tgt.getBoundingClientRect();
    tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + 1 }));
    handle.dispatchEvent(new Event("dragend", { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));
  await shot(page, "detail-section-reorder");
  await page.evaluate(() => { try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {} });

} finally {
  await browser.close();
}
