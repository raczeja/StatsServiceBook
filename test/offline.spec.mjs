import { test, expect } from "./coverage-fixture.mjs";
import { URLS, BASE } from "./test-urls.mjs";

// Service workers need a secure context; http://localhost qualifies, so the same
// behaviour that needs https:// on the router can be verified here.

// Visit a page until the service worker controls it (first load installs it,
// the reload is the first controlled load).
async function primed(page, url) {
  await page.goto(url);
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await page.reload();
  await page.waitForFunction(() => !!navigator.serviceWorker.controller);
}

test.use({ serviceWorkers: "allow" });

test.describe("offline mode", () => {
  test("service worker registers for the my-activities scope", async ({ page }) => {
    await page.goto(URLS.dash);
    const scope = await page.evaluate(() =>
      navigator.serviceWorker.ready.then((r) => r.scope),
    );
    expect(scope).toBe(BASE + "/");
  });

  test("a single failed reachability probe does not show the offline banner", async ({ page }) => {
    let heads = 0;
    await page.route("**/offline.js", (route) => {
      if (route.request().method() === "HEAD" && heads++ === 0) return route.abort();
      return route.continue();
    });
    await page.goto(URLS.dash);
    await expect.poll(() => heads, { timeout: 15000 }).toBeGreaterThanOrEqual(2);
    await expect(page.locator("#offline-bar")).toHaveCount(0);
  });

  test("two consecutive failed probes show the offline banner", async ({ page }) => {
    await page.route("**/offline.js", (route) =>
      route.request().method() === "HEAD" ? route.abort() : route.continue(),
    );
    await page.goto(URLS.dash);
    await expect(page.locator("#offline-bar")).toBeVisible({ timeout: 15000 });
  });

  test("dashboard still renders activities when the router is unreachable", async ({ page, context }) => {
    await primed(page, URLS.dash);
    await expect(page.locator("#board tbody tr").first()).toBeVisible();
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator("#board tbody tr").first()).toBeVisible();
    await expect(page.locator("#offline-bar")).toBeVisible();
    await context.setOffline(false);
  });

  test("bike-assign dropdowns are disabled offline and re-enabled online", async ({ page, context }) => {
    await primed(page, URLS.dash);
    await context.setOffline(true);
    await page.reload();
    const sel = page.locator("select.bike-sel").first();
    await expect(sel).toBeDisabled();
    await context.setOffline(false);
    await page.evaluate(() => window.dispatchEvent(new Event("online")));
    await expect(page.locator("#offline-bar")).toHaveCount(0);
    await expect(sel).toBeEnabled();
  });

  test("bike page is readable offline but write buttons are disabled", async ({ page, context }) => {
    await primed(page, URLS.bike);
    await expect(page.locator(".tab").first()).toBeVisible();
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator(".tab").first()).toBeVisible();
    await expect(page.locator("#offline-bar")).toBeVisible();
    await expect(page.locator(".tab.add")).toBeDisabled();
    // selecting a bike tab is read-only and must stay usable
    await expect(page.locator(".tab:not(.add)").first()).toBeEnabled();
    await context.setOffline(false);
  });

  test("writes are rejected client-side while offline", async ({ page, context }) => {
    await primed(page, URLS.bike);
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator("#offline-bar")).toBeVisible();
    const msg = await page.evaluate(() =>
      fetch("/cgi-bin/bike-service", { method: "POST", body: "{}" }).then(
        () => "sent",
        (e) => e.message,
      ),
    );
    expect(msg).toMatch(/Offline/);
    await context.setOffline(false);
  });

  test("an already opened activity detail stays available offline", async ({ page, context }) => {
    await primed(page, URLS.activity);
    await expect(page.locator("#content")).toBeVisible();
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator("#content")).toBeVisible();
    await expect(page.locator("#name")).not.toHaveText("");
    await context.setOffline(false);
  });

  test("offline banner reserves space so it does not cover page content on a phone", async ({ page, context }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await primed(page, URLS.dash);
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator("#offline-bar")).toBeVisible();
    const { barH, pad } = await page.evaluate(() => ({
      barH: document.getElementById("offline-bar").offsetHeight,
      pad: parseFloat(getComputedStyle(document.body).paddingBottom) || 0,
    }));
    expect(barH).toBeGreaterThan(0);
    expect(pad).toBeGreaterThanOrEqual(barH);
    // Back online: the reserved space is released together with the banner.
    await context.setOffline(false);
    await page.evaluate(() => window.dispatchEvent(new Event("online")));
    await expect(page.locator("#offline-bar")).toHaveCount(0);
    expect(await page.evaluate(() => document.body.style.paddingBottom)).toBe("");
  });

  test("club leaderboard link stays visible on My Activities pages offline", async ({ page, context }) => {
    await primed(page, URLS.club); // caches the club page
    await primed(page, URLS.dash);
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator("#offline-bar")).toBeVisible();
    await expect(page.locator("#leaderboard-link")).toBeVisible();
    await page.locator("#leaderboard-link").click();
    await expect(page).toHaveURL(URLS.club.replace(/index\.html$/, ""));
    await context.setOffline(false);
  });

  test("club leaderboard is available offline", async ({ page, context }) => {
    await primed(page, URLS.club);
    await context.setOffline(true);
    await page.reload();
    await expect(page.locator("body")).not.toBeEmpty();
    await expect(page.locator("#offline-bar")).toBeVisible();
    await context.setOffline(false);
  });
});
