import v8ToIstanbul from "v8-to-istanbul";

export async function getStatementCounts(entry) {
  const converter = v8ToIstanbul(entry.url, 0, { source: entry.source });
  await converter.load();
  converter.applyCoverage(entry.functions);

  let covered = 0;
  let total = 0;
  for (const fileCoverage of Object.values(converter.toIstanbul())) {
    for (const count of Object.values(fileCoverage.s)) {
      total += 1;
      if (count > 0) {
        covered += 1;
      }
    }
  }

  return { covered, total };
}
