import assert from "node:assert/strict";
import test from "node:test";
import { getStatementCounts } from "./coverage-utils.mjs";

test("does not count an uncalled function body as covered by the script range", async () => {
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
  const entry = {
    url: "http://localhost/coverage-fixture.js",
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
        ranges: [{ startOffset: notCalledStart, endOffset: source.length, count: 0 }],
      },
    ],
  };

  const counts = await getStatementCounts(entry);

  assert.ok(counts.covered > 0, "expected executed statements to be covered");
  assert.ok(counts.total > counts.covered, "expected the uncalled function statements to remain uncovered");
});
