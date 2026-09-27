import { test, expect } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

test.describe("data-quality", () => {
  test("shows activity completeness and all source statuses", async ({
    page,
  }) => {
    await page.route("**/activities.json", async (route) => {
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
      .filter({ hasText: "Strava" });
    const healthsync = page
      .locator("#sources .source")
      .filter({ hasText: "HealthSync" });
    await expect(strava.locator(".badge")).toHaveText("Failed");
    await expect(strava).toContainText("token refresh failed");
    await expect(healthsync.locator(".badge")).toHaveText("Stale");
    await expect(healthsync).toContainText("last 48 hours");
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
          page.locator('#hdr h1 a[href="data-quality.html"]'),
        ).toBeVisible();
      }
    }
  });
});
