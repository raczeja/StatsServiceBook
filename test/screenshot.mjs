/**
 * screenshot.mjs — takes screenshots of the club and My Activities pages.
 * Called by make-screenshots.ps1 after the Podman test container is running.
 *
 * Usage:
 *   node screenshot.mjs <outputDir>
 *
 * Requires puppeteer-core (installed by make-screenshots.ps1 into a temp dir).
 * Points at the system Edge executable — no browser download needed.
 */
import puppeteer from "puppeteer-core";
import fs from "fs";
import path from "path";

const outDir = process.argv[2];
if (!outDir) {
  console.error("Usage: node screenshot.mjs <outputDir>");
  process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });

const BASE = "http://localhost:8080/strava/me";

const PAGES = [
  { name: "club-dashboard", url: "http://localhost:8080/strava/index.html" },
  { name: "my-activities", url: `${BASE}/index.html` },
  { name: "stats", url: `${BASE}/stats.html` },
  { name: "activity-detail", url: `${BASE}/activity.html?id=18784255013` },
  { name: "bike-service", url: `${BASE}/bike.html` },
];

const EDGE_CANDIDATES = [
  process.env.EDGE_PATH,
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
].filter(Boolean);

function findEdge() {
  for (const p of EDGE_CANDIDATES) {
    if (fs.existsSync(p)) return p;
  }
  throw new Error(
    "Edge not found. Set EDGE_PATH env var to the msedge.exe path.",
  );
}

const executablePath = findEdge();
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
