import fs from "node:fs";
import path from "node:path";
import { chromium } from "@playwright/test";
import { URLS } from "./test-urls.mjs";
import { getStatementCounts } from "./coverage-utils.mjs";

const pages = [
  { name: "club", url: URLS.club },
  { name: "dashboard", url: URLS.dash },
  { name: "stats", url: URLS.stats },
  { name: "heatmap", url: URLS.heatmap },
  { name: "data-quality", url: URLS.dataQuality },
  { name: "activity-detail", url: URLS.activity },
  { name: "bike-service", url: URLS.bike },
];

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

  let coveredStatements = 0;
  let totalStatements = 0;

  for (const entry of coverage) {
    if (!entry.url) {
      continue;
    }
    let scriptUrl;
    try {
      scriptUrl = new URL(entry.url);
    } catch {
      continue;
    }
    if (scriptUrl.origin !== pageOrigin || typeof entry.source !== "string") {
      continue;
    }

    if (!Array.isArray(entry.functions)) {
      continue;
    }
    const counts = await getStatementCounts(entry);
    coveredStatements += counts.covered;
    totalStatements += counts.total;
  }

  await context.close();
  await browser.close();

  const percent = totalStatements > 0 ? (coveredStatements / totalStatements) * 100 : 0;

  return {
    label,
    url,
    percent: Number(percent.toFixed(2)),
    coveredStatements,
    totalStatements,
  };
}

const results = [];
for (const page of pages) {
  const result = await collectPageCoverage(page.url, page.name);
  results.push(result);
}

const overall = results.reduce(
  (sum, item) => {
    sum.coveredStatements += item.coveredStatements;
    sum.totalStatements += item.totalStatements;
    return sum;
  },
  { coveredStatements: 0, totalStatements: 0 },
);

const overallPercent =
  overall.totalStatements > 0 ? (overall.coveredStatements / overall.totalStatements) * 100 : 0;
const outDir = path.resolve(process.cwd(), "coverage");
fs.mkdirSync(outDir, { recursive: true });

const summary = {
  generatedAt: new Date().toISOString(),
  metric: "statement coverage",
  overallPercent: Number(overallPercent.toFixed(2)),
  pages: results,
};

const summaryPath = path.join(outDir, "coverage-summary.json");
fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");

console.log("Playwright coverage summary");
console.log(
  `Overall: ${summary.overallPercent.toFixed(2)}% (${overall.coveredStatements}/${overall.totalStatements} statements)\n`,
);
for (const page of results) {
  console.log(
    `${page.label}: ${page.percent.toFixed(2)}% (${page.coveredStatements}/${page.totalStatements} statements) - ${page.url}`,
  );
}
console.log(`\nSaved to ${summaryPath}`);
