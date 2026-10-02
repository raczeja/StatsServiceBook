import fs from "node:fs";
import path from "node:path";
import { summarizeCoverage } from "./coverage-utils.mjs";

const inputDir = path.resolve(
  process.env.COVERAGE_INPUT_DIR || "coverage-data",
);
const inputFiles = fs
  .readdirSync(inputDir)
  .filter((file) => file.endsWith(".json"))
  .sort();
if (inputFiles.length === 0) {
  throw new Error(`No Playwright coverage data found in ${inputDir}`);
}

const entries = inputFiles.flatMap((file) => {
  const content = JSON.parse(
    fs.readFileSync(path.join(inputDir, file), "utf8"),
  );
  if (!Array.isArray(content)) {
    throw new Error(`Invalid coverage data in ${path.join(inputDir, file)}`);
  }
  return content;
});
const summary = await summarizeCoverage(entries);
if (summary.totalStatements === 0) {
  throw new Error("No first-party JavaScript statements were covered by Playwright");
}

const outDir = path.resolve(process.cwd(), "coverage");
fs.mkdirSync(outDir, { recursive: true });
summary.generatedAt = new Date().toISOString();

const summaryPath = path.join(outDir, "coverage-summary.json");
fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");

console.log("Playwright coverage summary");
console.log(
  `Overall: ${summary.overallPercent.toFixed(2)}% (${summary.coveredStatements}/${summary.totalStatements} unique statements)\n`,
);
for (const page of summary.pages) {
  console.log(
    `${page.label}: ${page.percent.toFixed(2)}% (${page.coveredStatements}/${page.totalStatements} statements) - ${page.url}`,
  );
}
console.log(`\nSaved to ${summaryPath}`);
