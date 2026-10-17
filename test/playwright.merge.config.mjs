// Used only by CI: `playwright merge-reports --config playwright.merge.config.mjs blob-reports`
// combines the parallel + serial blob reports into the usual html/json/junit outputs.
export default {
  testDir: ".",
  reporter: [
    ["html", { outputFolder: "playwright-report", open: "never" }],
    ["list"],
    ["json", { outputFile: "test-results/results.json" }],
    ["junit", { outputFile: "test-results/junit.xml" }],
    [
      "@estruyf/github-actions-reporter",
      { title: "Playwright results", useDetails: true, showError: true, summary: false },
    ],
  ],
};
