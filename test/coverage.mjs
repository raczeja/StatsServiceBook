import fs from "node:fs";
import path from "node:path";
import { chromium } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

const pages = [
  { name: "club", url: URLS.club },
  { name: "dashboard", url: URLS.dash },
  { name: "stats", url: URLS.stats },
  { name: "heatmap", url: URLS.heatmap },
  { name: "data-quality", url: URLS.dataQuality },
  { name: "activity-detail", url: URLS.activity },
  { name: "bike-service", url: URLS.bike },
];

function mergedLength(ranges) {
  const sorted = ranges
    .map((range) => ({
      start: Math.max(0, Number(range.startOffset ?? 0)),
      end: Math.max(0, Number(range.endOffset ?? 0)),
    }))
    .filter((range) => range.end > range.start)
    .sort((a, b) => a.start - b.start);

  let length = 0;
  let current = null;
  for (const range of sorted) {
    if (!current || range.start > current.end) {
      if (current) {
        length += current.end - current.start;
      }
      current = { ...range };
    } else {
      current.end = Math.max(current.end, range.end);
    }
  }
  if (current) {
    length += current.end - current.start;
  }
  return length;
}

async function collectPageCoverage(url, label) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });
  const page = await context.newPage();

  await page.coverage.startJSCoverage({
    resetOnNavigation: false,
    reportAnonymousScripts: true,
  });
  await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
  const coverage = await page.coverage.stopJSCoverage();
  const pageOrigin = new URL(url).origin;

  let usedBytes = 0;
  let totalBytes = 0;

  for (const entry of coverage) {
    if (!entry.url) {
      continue;
    }
    let scriptOrigin;
    try {
      scriptOrigin = new URL(entry.url).origin;
    } catch {
      continue;
    }
    if (scriptOrigin !== pageOrigin) {
      continue;
    }

    const functions = Array.isArray(entry.functions) ? entry.functions : [];
    const ranges = functions.flatMap((fn) =>
      (Array.isArray(fn.ranges) ? fn.ranges : []).filter((range) => Number(range.count ?? 0) > 0),
    );
    const used = mergedLength(ranges);
    const total = typeof entry.source === "string" ? entry.source.length : 0;

    if (total > 0) {
      usedBytes += Math.min(used, total);
      totalBytes += total;
    }
  }

  await context.close();
  await browser.close();

  const percent = totalBytes > 0 ? (usedBytes / totalBytes) * 100 : 0;

  return {
    label,
    url,
    percent: Number(percent.toFixed(2)),
    usedBytes,
    totalBytes,
  };
}

const results = [];
for (const page of pages) {
  const result = await collectPageCoverage(page.url, page.name);
  results.push(result);
}

const overall = results.reduce(
  (sum, item) => {
    sum.usedBytes += item.usedBytes;
    sum.totalBytes += item.totalBytes;
    return sum;
  },
  { usedBytes: 0, totalBytes: 0 },
);

const overallPercent = overall.totalBytes > 0 ? (overall.usedBytes / overall.totalBytes) * 100 : 0;
const outDir = path.resolve(process.cwd(), "coverage");
fs.mkdirSync(outDir, { recursive: true });

const summary = {
  generatedAt: new Date().toISOString(),
  overallPercent: Number(overallPercent.toFixed(2)),
  pages: results,
};

const summaryPath = path.join(outDir, "coverage-summary.json");
fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");

console.log("Playwright coverage summary");
console.log(`Overall: ${summary.overallPercent.toFixed(2)}% (${overall.usedBytes}/${overall.totalBytes} bytes)\n`);
for (const page of results) {
  console.log(`${page.label}: ${page.percent.toFixed(2)}% (${page.usedBytes}/${page.totalBytes} bytes) - ${page.url}`);
}
console.log(`\nSaved to ${summaryPath}`);
