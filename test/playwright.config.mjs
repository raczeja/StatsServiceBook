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
    { title: "Playwright results", useDetails: true, showError: true },
  ]);
}

export default defineConfig({
  testDir: ".",
  testMatch: "**/*.spec.mjs",
  timeout: 30000,
  expect: { timeout: 10000 },
  // workers: 1 — bike-service tests POST data to the shared CGI server; running
  // spec files in parallel would interleave those writes and corrupt state.
  workers: 1,
  reporter: reporters,
  use: {
    baseURL: `http://${HOST}:${PORT}`,
    viewport: { width: 1440, height: 900 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: {
        browserName: "chromium",
        // Allow overriding with a system Chrome when bundled Chromium can't be downloaded
        // (e.g. network-restricted WSL). Set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome.
        ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
          ? { launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } }
          : {}),
      },
    },
  ],
});
