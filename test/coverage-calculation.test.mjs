import assert from "node:assert/strict";
import test from "node:test";
import { getStatementCounts, summarizeCoverage } from "./coverage-utils.mjs";
import { URLS } from "./test-urls.mjs";

function createEntry(secondFunctionCount, scriptStart = "0:0") {
  const source = [
    "function called() {",
    "  const value = 1;",
    "  return value;",
    "}",
    "called();",
    "function notCalled() {",
    "  const value = 2;",
    "  return value;",
    "}",
  ].join("\n");
  const calledStart = source.indexOf("function called");
  const calledEnd = source.indexOf("\n}", calledStart) + 2;
  const notCalledStart = source.indexOf("function notCalled");
  return {
    url: URLS.dash,
    pageInfo: { label: "dashboard", url: URLS.dash },
    scriptStart,
    source,
    functions: [
      {
        functionName: "",
        isBlockCoverage: false,
        ranges: [{ startOffset: 0, endOffset: source.length, count: 1 }],
      },
      {
        functionName: "called",
        isBlockCoverage: true,
        ranges: [{ startOffset: calledStart, endOffset: calledEnd, count: 1 }],
      },
      {
        functionName: "notCalled",
        isBlockCoverage: true,
        ranges: [
          {
            startOffset: notCalledStart,
            endOffset: source.length,
            count: secondFunctionCount,
          },
        ],
      },
    ],
  };
}

test("does not count an uncalled function body as covered by the script range", async () => {
  const counts = await getStatementCounts(createEntry(0));

  assert.ok(counts.covered > 0, "expected executed statements to be covered");
  assert.ok(counts.total > counts.covered, "expected the uncalled function statements to remain uncovered");
});

test("merges repeated visits without double-counting statements", async () => {
  const firstRun = createEntry(0);
  const secondRun = createEntry(1);
  const firstRunCounts = await getStatementCounts(firstRun);
  const summary = await summarizeCoverage([firstRun, secondRun]);
  const dashboard = summary.pages.find((page) => page.label === "dashboard");

  assert.equal(dashboard.totalStatements, firstRunCounts.total);
  assert.equal(dashboard.coveredStatements, dashboard.totalStatements);
});

test("counts separate inline scripts even when their source is identical", async () => {
  const firstScript = createEntry(0, "1:0");
  const secondScript = createEntry(0, "20:0");
  const firstScriptCounts = await getStatementCounts(firstScript);
  const summary = await summarizeCoverage([firstScript, secondScript]);
  const dashboard = summary.pages.find((page) => page.label === "dashboard");

  assert.equal(dashboard.totalStatements, firstScriptCounts.total * 2);
});
