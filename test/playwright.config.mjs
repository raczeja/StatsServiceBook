import { defineConfig } from "@playwright/test";

const PORT = process.env.TEST_PORT || process.env.STRAVA_TEST_PORT || "8080";
const HOST = process.env.TEST_HOST || "localhost";

const reporters = [
  ["html", { outputFolder: "playwright-report", open: "never" }],
  ["list"],
  ["json", { outputFile: "test-results/results.json" }],
  ["junit", { outputFile: "test-results/junit.xml" }],
];

if (process.env.CI) {
  reporters.push([
    "@estruyf/github-actions-reporter",
    { title: "Playwright results", useDetails: true, showError: true, summary: false },
  ]);
}

// Specs that only read static pages or mock every CGI via page.route() — safe to
// run concurrently. Everything else touches shared CGI state and must run serially.
const PARALLEL_SPECS = [
  "**/club-dashboard.spec.mjs",
  "**/data-quality.spec.mjs",
  "**/heatmap.spec.mjs",
  "**/mobile.spec.mjs",
  "**/offline.spec.mjs",
];

// Allow overriding with a system Chrome when bundled Chromium can't be downloaded
// (e.g. network-restricted WSL). Set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome.
const browserUse = {
  browserName: "chromium",
  ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
    ? { launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } }
    : {}),
};

export default defineConfig({
  testDir: ".",
  testMatch: "**/*.spec.mjs",
  timeout: 30000,
  expect: { timeout: 10000 },
  // workers: 1 â€” bike-service tests POST data to the shared CGI server; running
  // spec files in parallel would interleave those writes and corrupt state.
  workers: 1,
  reporter: reporters,
  use: {
    baseURL: `http://${HOST}:${PORT}`,
    // The offline service worker would bypass page.route() mocks after the first
    // load; only offline.spec.mjs opts back in (test.use({ serviceWorkers: "allow" })).
    serviceWorkers: "block",
    viewport: { width: 1440, height: 900 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "parallel",
      testMatch: PARALLEL_SPECS,
      use: browserUse,
    },
    {
      name: "serial",
      testMatch: "**/*.spec.mjs",
      testIgnore: PARALLEL_SPECS,
      use: browserUse,
    },
  ],
});
