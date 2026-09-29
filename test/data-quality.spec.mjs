import { test, expect } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

test.describe("data-quality", () => {
  test("shows activity completeness and all source statuses", async ({
    page,
  }) => {
    await page.route("**/me/activities.json", async (route) => {
      const response = await route.fetch();
      const data = await response.json();
      const activity = data.activities.find(
        (item) => item.name === "Magene C606",
      );
      activity.detail = false;
      activity.has_gps = null;
      await route.fulfill({ response, json: data });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    await expect(
      page.getByRole("heading", { name: "Data completeness" }),
    ).toBeVisible();
    await expect(page.locator("#count-total")).toHaveText("30");
    await expect(page.locator("#count-gps")).toHaveText("1");
    await expect(page.locator("#count-detail")).toHaveText("1");
    expect(
      Number(await page.locator("#count-hr").textContent()),
    ).toBeGreaterThan(0);
    await expect(page.locator("#sources .source")).toHaveCount(3);
    await expect(page.locator("#sources")).toContainText("Club leaderboard");
    await expect(page.locator("#sources .badge")).toHaveText([
      "OK",
      "OK",
      "OK",
    ]);
    await expect(page.locator("#activity-list")).toContainText("City Loop");
    await expect(page.locator("#activity-list")).toContainText("Magene C606");
    await expect(page.locator("#activity-list")).toContainText("Details");
    const mageneRow = page
      .locator("#activity-list tbody tr")
      .filter({ hasText: "Magene C606" });
    await expect(page.locator("#filter-heart-rate")).not.toBeChecked();
    await expect(mageneRow.locator("td").nth(3)).toHaveText("Details");
    await page.locator("#filter-heart-rate").check();
    await expect(mageneRow.locator("td").nth(3)).toHaveText(
      "Details, Heart rate",
    );
  });

  test("flags failed and stale imports", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    await page.route("**/strava-sync-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          source: "api",
          ok: false,
          lastAttempt: now,
          lastSuccess: now - 3 * 86400,
          error: "token refresh failed",
        }),
      }),
    );
    await page.route("**/healthsync-sync-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          source: "HealthSync",
          mode: "full",
          ok: true,
          lastAttempt: now,
          lastSuccess: now - 49 * 3600,
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    const strava = page
      .locator("#sources .source")
      .filter({ has: page.locator("h2", { hasText: /^Strava/ }) });
    const healthsync = page
      .locator("#sources .source")
      .filter({ has: page.locator("h2", { hasText: "HealthSync" }) });
    await expect(strava.locator(".badge").first()).toHaveText("Failed");
    await expect(strava).toContainText("token refresh failed");
    await expect(healthsync.locator(".badge").first()).toHaveText("Stale");
    await expect(healthsync).toContainText("last 48 hours");
  });

  test("sync-now-buttons-and-sync-all-visible", async ({ page }) => {
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    // Each visible source card should have a Sync now button
    const cards = page.locator("#sources .source");
    const count = await cards.count();
    expect(count, "expected at least one source card").toBeGreaterThan(0);
    for (let i = 0; i < count; i++) {
      await expect(
        cards.nth(i).locator("button.sync-btn[data-src]"),
        `source card ${i} should have a Sync now button`,
      ).toBeVisible();
    }
    // Sync all button next to the section heading
    await expect(
      page.locator("#sync-all-btn"),
      "Sync all button should be visible",
    ).toBeVisible();
  });

  test("run-log-collapsed-by-default", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    await page.route("**/strava-sync-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          source: "api",
          ok: true,
          lastAttempt: now,
          lastSuccess: now,
          log: ["line 1", "line 2", "line 3"],
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const strava = page.locator("#sources .source").filter({ has: page.locator("h2", { hasText: /^Strava/ }) });
    const details = strava.locator("details").first();
    await expect(details, "log <details> should be present").toBeVisible();
    // closed by default — pre content should not be visible
    await expect(strava.locator("pre.run-log"), "log pre should be hidden when collapsed").toBeHidden();
    await details.locator("summary").click();
    await expect(strava.locator("pre.run-log"), "log pre visible after expand").toBeVisible();
    await expect(strava.locator("pre.run-log")).toContainText("line 1");
  });

  test("no-status-source-cards-are-hidden", async ({ page }) => {
    await page.route("**/strava-sync-status.json", (route) =>
      route.fulfill({ status: 404, body: "" }),
    );
    await page.route("**/healthsync-sync-status.json", (route) =>
      route.fulfill({ status: 404, body: "" }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    // Only the leaderboard card (which uses the sample file) should be visible
    const cards = page.locator("#sources .source");
    const count = await cards.count();
    for (let i = 0; i < count; i++) {
      await expect(
        cards.nth(i),
        `card ${i} should not say "No status yet"`,
      ).not.toContainText("No status yet");
    }
  });

  test("cookie-section-hidden-when-no-scrapeMeta", async ({ page }) => {
    await page.route("**/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ activities: [], generatedAt: new Date().toISOString(), scrapeMeta: null }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await expect(
      page.locator("#cookie-status"),
      "#cookie-status should be hidden when scrapeMeta is null",
    ).toBeHidden();
  });

  test("cookie-section-shows-when-scrapeMeta-present", async ({ page }) => {
    const today = new Date().toISOString().slice(0, 10);
    const future = new Date(Date.now() + 20 * 86400000).toISOString().slice(0, 10);
    await page.route("**/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          generatedAt: new Date().toISOString(),
          scrapeMeta: { cookieVerifiedAt: today, cookieRefreshNeededBy: future },
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const sec = page.locator("#cookie-status");
    await expect(sec, "#cookie-status should be visible when scrapeMeta present").toBeVisible();
    await expect(sec.locator("#cookie-cards .source").first()).toContainText("My Activities");
    await expect(sec.locator(".ck-ok").first(), "ok state card present").toBeVisible();
    await expect(sec.locator("#cookie-input"), "cookie textarea present").toBeVisible();
    await expect(
      sec.locator("button", { hasText: "Save cookie" }),
      "Save cookie button present",
    ).toBeVisible();
  });

  test("cookie-section-warn-state-when-expiry-near", async ({ page }) => {
    const today = new Date().toISOString().slice(0, 10);
    const soon = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);
    await page.route("**/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          generatedAt: new Date().toISOString(),
          scrapeMeta: { cookieVerifiedAt: today, cookieRefreshNeededBy: soon },
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await expect(
      page.locator("#cookie-cards .ck-warn").first(),
      "warn-state card should appear when expiry <= 7 days",
    ).toBeVisible();
  });

  test("email-section-visible-when-status-files-present", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    await page.route("**/email-monthly-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          mode: "monthly", ok: true,
          lastAttempt: now, lastSuccess: now,
          subject: "Strava Leaderboard - August 2026",
          recipientCount: 3, sentCount: 3,
          log: ["building monthly email", "sent OK to a@example.com"],
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const sec = page.locator("#email-status");
    await expect(sec, "#email-status should be visible when status files present").toBeVisible();
    await expect(sec.locator("h2").first()).toContainText("Email sending");
    const card = sec.locator(".source").filter({ hasText: "Monthly email" });
    await expect(card.locator(".badge")).toHaveText("OK");
    await expect(card).toContainText("Strava Leaderboard - August 2026");
    await expect(card).toContainText("Recipients: 3");
  });

  test("email-section-hidden-when-no-status-files", async ({ page }) => {
    await page.route("**/email-monthly-status.json", (route) =>
      route.fulfill({ status: 404, body: "" }),
    );
    await page.route("**/email-weekly-status.json", (route) =>
      route.fulfill({ status: 404, body: "" }),
    );
    await page.route("**/email-yearly-status.json", (route) =>
      route.fulfill({ status: 404, body: "" }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await expect(
      page.locator("#email-status"),
      "#email-status should be hidden when no status files exist",
    ).toBeHidden();
  });

  test("existing pages link to data completeness", async ({ page }) => {
    for (const url of [
      URLS.dash,
      URLS.activity,
      URLS.stats,
      URLS.heatmap,
      URLS.bike,
      URLS.club,
    ]) {
      await page.goto(url, { waitUntil: "domcontentloaded" });
      await expect(page.locator('a[href$="data-quality.html"]').first()).toBeVisible();
      if (url === URLS.dash) {
        await expect(
          page.locator('.nav a[href="data-quality.html"]'),
        ).toBeVisible();
      }
    }
  });
});
