/**
 * screenshot.mjs — takes screenshots of the club and My Activities pages,
 * plus bike-service modal states (add/edit bike, add/edit/service part).
 * Called by make-screenshots.ps1 after the Podman test container is running.
 *
 * Usage:
 *   node screenshot.mjs <outputDir>
 *
 * Requires puppeteer (installed by make-screenshots.ps1 into a temp dir).
 */
import puppeteer from "puppeteer";
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
  { name: "club-dashboard",      url: `http://${HOST}:${PORT}/strava/index.html`, dark: false },
  { name: "club-dashboard-dark", url: `http://${HOST}:${PORT}/strava/index.html`, dark: true  },
  { name: "my-activities",       url: `${BASE}/index.html`,                       dark: false },
  { name: "stats",               url: `${BASE}/stats.html`,                       dark: false },
  { name: "heatmap",             url: `${BASE}/heatmap.html`,                     dark: false },
  { name: "activity-detail",     url: `${BASE}/activity.html?id=18784255013`,     dark: false },
  { name: "bike-service",        url: `${BASE}/bike.html`,                        dark: false },
  // Dark mode variants
  { name: "my-activities-dark",  url: `${BASE}/index.html`,                       dark: true },
  { name: "stats-dark",          url: `${BASE}/stats.html`,                       dark: true },
  { name: "activity-detail-dark",url: `${BASE}/activity.html?id=18784255013`,     dark: true },
  { name: "bike-service-dark",   url: `${BASE}/bike.html`,                        dark: true },
];

const BROWSER_CANDIDATES = [
  process.env.EDGE_PATH,
  process.env.BROWSER_PATH,
  "/usr/bin/google-chrome-stable",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium-browser",
  "/usr/bin/chromium",
].filter(Boolean);

async function findBrowser() {
  const bundled = await puppeteer.executablePath?.();
  if (bundled && fs.existsSync(bundled)) return bundled;

  for (const p of BROWSER_CANDIDATES) {
    if (fs.existsSync(p)) return p;
  }

  throw new Error(
    "Browser not found. Set EDGE_PATH/BROWSER_PATH to a browser executable, or install puppeteer so it can download a browser.",
  );
}

async function waitBikeReady(page) {
  await page.waitForSelector(".bikes .tab", { timeout: 10000 });
  await page.waitForFunction(
    () => !document.getElementById("meta")?.textContent.includes("Loading"),
    { timeout: 10000 },
  );
  // Select Road Bike tab
  await page.evaluate(() => {
    const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
    const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
    if (t) t.click();
  });
  await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
}

async function shot(page, name) {
  const file = path.join(outDir, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`  saved ${file}`);
}

const executablePath = await findBrowser();
console.log("Using browser:", executablePath);

const browser = await puppeteer.launch({
  executablePath,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
});

try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  // ── Standard full-page screenshots ───────────────────────────────────────────
  for (const { name, url, dark } of PAGES) {
    console.log(`→ ${name}: ${url}${dark ? " [dark]" : ""}`);
    // Set theme in localStorage before navigation so the anti-FOUC script picks it up.
    await page.evaluate((isDark) => {
      try { if (isDark) localStorage.setItem("theme", "dark"); else localStorage.removeItem("theme"); } catch (_) {}
    }, dark);
    // Heatmap uses networkidle2 (allows ≤2 in-flight requests) so tile loading
    // doesn't block indefinitely, while still letting CDN scripts finish loading.
    const waitFor = name === "heatmap" ? "networkidle2" : "networkidle0";
    await page.goto(url, { waitUntil: waitFor, timeout: 45000 });

    if (name === "heatmap") {
      // Wait for Leaflet library to be available, then for heatmap data and tiles.
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
      // Wait for all map tiles to finish loading after the filter change triggers
      // a fitBounds + tile reload.  waitForSelector finds the first already-loaded
      // tile (which may pre-date the filter change), so instead poll until there
      // are no tiles still in-flight.
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
    }

    await shot(page, name);
  }

  // ── Bike-service modal screenshots (light mode) ──────────────────────────────
  console.log("→ bike modal screenshots");
  await page.evaluate(() => { try { localStorage.removeItem("theme"); } catch (_) {} });
  await page.goto(`${BASE}/bike.html`, { waitUntil: "networkidle0", timeout: 20000 });
  await waitBikeReady(page);

  // Add bike modal
  console.log("  → bike-modal-add-bike");
  await page.evaluate(() => showAddBike());
  await page.waitForSelector("#b-name", { timeout: 3000 });
  await shot(page, "bike-modal-add-bike");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  // Edit bike modal (Road Bike)
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

  // Add part modal
  console.log("  → bike-modal-add-part");
  await page.evaluate(() => showAddPart());
  await page.waitForSelector("#p-name", { timeout: 3000 });
  await shot(page, "bike-modal-add-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  // Edit part modal (first active part = Chain, which is flagged needsReplacement)
  console.log("  → bike-modal-edit-part");
  await page.evaluate(() => {
    const btns = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow) button[onclick*="editPart"]');
    if (btns[0]) btns[0].click();
  });
  await page.waitForSelector("#p-name", { timeout: 3000 });
  await shot(page, "bike-modal-edit-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  // Service part modal (first active part = Chain — shows pre-checked "Needs replacement")
  console.log("  → bike-modal-service-part");
  await page.evaluate(() => {
    const btns = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showService"]');
    if (btns[0]) btns[0].click();
  });
  await page.waitForSelector("#f-date", { timeout: 3000 });
  await shot(page, "bike-modal-service-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  // Replace part modal (first active part = Chain)
  console.log("  → bike-modal-replace-part");
  await page.evaluate(() => {
    const btns = document.querySelectorAll('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showReplace"]');
    if (btns[0]) btns[0].click();
  });
  await page.waitForSelector("#r-note", { timeout: 3000 });
  await shot(page, "bike-modal-replace-part");
  await page.evaluate(() => closeModal());
  await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));

  // ── Multi-bike overview screenshots (all bike tabs visible) ──────────────────
  async function shotMultiBike(darkMode, shotName) {
    await page.evaluate((isDark) => {
      try { if (isDark) localStorage.setItem("theme", "dark"); else localStorage.removeItem("theme"); } catch (_) {}
    }, darkMode);
    await page.goto(`${BASE}/bike.html`, { waitUntil: "networkidle0", timeout: 20000 });
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
  // Stats page: move kpis section down one position so records appears first.
  console.log("→ stats-section-reorder");
  await page.evaluate(() => { try { localStorage.removeItem("theme"); localStorage.removeItem("ssb-stats-sec"); } catch (_) {} });
  await page.goto(`${BASE}/stats.html`, { waitUntil: "networkidle0", timeout: 30000 });
  try { await page.waitForSelector(".sec[data-sid]", { timeout: 10000 }); } catch (_) {}
  try {
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
  } catch (_) {}
  // Drag kpis (first) to after records (second)
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
  // Restore default order in localStorage
  await page.evaluate(() => { try { localStorage.removeItem("ssb-stats-sec"); } catch (_) {} });

  // Activity detail: move splits up one position
  console.log("→ detail-section-reorder");
  await page.evaluate(() => { try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {} });
  await page.goto(`${BASE}/activity.html?id=18784255013`, { waitUntil: "networkidle0", timeout: 30000 });
  try {
    await page.waitForFunction(
      () => document.getElementById("content")?.style.display !== "none",
      { timeout: 10000 },
    );
  } catch (_) {}
  // Drag splits (last) to before hrzone (second-to-last)
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
  // Restore default order
  await page.evaluate(() => { try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {} });

} finally {
  await browser.close();
}
