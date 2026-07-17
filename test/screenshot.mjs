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
const BASE = `http://localhost:${PORT}/strava/me`;

const PAGES = [
  { name: "club-dashboard", url: `http://localhost:${PORT}/strava/index.html` },
  { name: "my-activities", url: `${BASE}/index.html` },
  { name: "stats", url: `${BASE}/stats.html` },
  { name: "activity-detail", url: `${BASE}/activity.html?id=18784255013` },
  { name: "bike-service", url: `${BASE}/bike.html` },
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
  for (const { name, url } of PAGES) {
    console.log(`→ ${name}: ${url}`);
    await page.goto(url, { waitUntil: "networkidle0", timeout: 20000 });
    await shot(page, name);
  }

  // ── Bike-service modal screenshots ───────────────────────────────────────────
  console.log("→ bike modal screenshots");
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

} finally {
  await browser.close();
}
