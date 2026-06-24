/**
 * screenshot.mjs — takes screenshots of the club and My Activities pages.
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

const executablePath = await findBrowser();
console.log("Using Edge:", executablePath);

const browser = await puppeteer.launch({
  executablePath,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
});

try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  for (const { name, url } of PAGES) {
    console.log(`→ ${name}: ${url}`);
    await page.goto(url, { waitUntil: "networkidle0", timeout: 20000 });
    const file = path.join(outDir, `${name}.png`);
    await page.screenshot({ path: file, fullPage: false });
    console.log(`  saved ${file}`);
  }
} finally {
  await browser.close();
}
