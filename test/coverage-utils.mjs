import { createHash } from "node:crypto";
import v8ToIstanbul from "v8-to-istanbul";
import { URLS } from "./test-urls.mjs";

const PAGE_INFO = [
  ["club", URLS.club],
  ["dashboard", URLS.dash],
  ["stats", URLS.stats],
  ["heatmap", URLS.heatmap],
  ["data-quality", URLS.dataQuality],
  ["activity-detail", URLS.activity],
  ["bike-service", URLS.bike],
].map(([label, value]) => {
  const url = new URL(value);
  return { label, origin: url.origin, pathname: url.pathname, url: `${url.origin}${url.pathname}` };
});

export function getPageInfo(value) {
  try {
    const url = new URL(value);
    return PAGE_INFO.find(
      (page) => page.origin === url.origin && page.pathname === url.pathname,
    ) ?? null;
  } catch {
    return null;
  }
}

export async function getStatementCoverage(entry) {
  const converter = v8ToIstanbul(entry.url, 0, { source: entry.source });
  await converter.load();
  converter.applyCoverage(entry.functions);

  const statements = [];
  for (const fileCoverage of Object.values(converter.toIstanbul())) {
    for (const [id, count] of Object.entries(fileCoverage.s)) {
      const location = fileCoverage.statementMap[id];
      statements.push({
        key: [
          location.start.line,
          location.start.column,
          location.end.line,
          location.end.column,
        ].join(":"),
        covered: count > 0,
      });
    }
  }

  return statements;
}

export async function getStatementCounts(entry) {
  const statements = await getStatementCoverage(entry);
  return {
    covered: statements.filter((statement) => statement.covered).length,
    total: statements.length,
  };
}

export async function summarizeCoverage(entries) {
  const pageStatements = new Map(
    PAGE_INFO.map((page) => [page.label, { ...page, statements: new Map() }]),
  );

  for (const entry of entries) {
    const page = pageStatements.get(entry.pageInfo?.label);
    if (!page || typeof entry.source !== "string" || !Array.isArray(entry.functions)) {
      continue;
    }

    const sourceHash = createHash("sha256").update(entry.source).digest("hex");
    const statements = await getStatementCoverage(entry);
    for (const statement of statements) {
      const key = `${entry.scriptStart ?? ""}:${sourceHash}:${statement.key}`;
      page.statements.set(
        key,
        Boolean(page.statements.get(key)) || statement.covered,
      );
    }
  }

  const pages = [...pageStatements.values()].map((page) => {
    const totalStatements = page.statements.size;
    const coveredStatements = [...page.statements.values()].filter(Boolean).length;
    const percent =
      totalStatements > 0 ? (coveredStatements / totalStatements) * 100 : 0;
    return {
      label: page.label,
      url: page.url,
      percent: Number(percent.toFixed(2)),
      coveredStatements,
      totalStatements,
    };
  });
  const totalStatements = pages.reduce((sum, page) => sum + page.totalStatements, 0);
  const coveredStatements = pages.reduce((sum, page) => sum + page.coveredStatements, 0);

  return {
    metric: "statement coverage across Playwright functional tests",
    overallPercent:
      totalStatements > 0
        ? Number(((coveredStatements / totalStatements) * 100).toFixed(2))
        : 0,
    coveredStatements,
    totalStatements,
    pages,
  };
}
