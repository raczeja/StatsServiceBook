import { test, expect } from "./coverage-fixture.mjs";
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
      /^OK/,
      /^OK/,
      /^OK/,
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

  test("filters missing data and handles unknown and optional GPS", async ({
    page,
  }) => {
    await page.route("**/me/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          generatedAt: new Date().toISOString(),
          activities: [
            {
              id: "missing-all",
              name: "Missing everything",
              date: "2026-01-01",
              sport_type: "Ride",
              detail: false,
              has_gps: false,
              average_heartrate: 0,
            },
            {
              id: "unknown-gps",
              name: "Unknown GPS",
              date: "2026-01-02",
              sport_type: "Ride",
              detail: true,
              has_gps: null,
              average_heartrate: null,
            },
            {
              id: "yoga-no-gps",
              name: "GPS optional",
              date: "2026-01-03",
              sport_type: "Yoga",
              detail: true,
              has_gps: false,
              average_heartrate: 100,
            },
            {
              id: "complete",
              name: "Complete activity",
              date: "2026-01-04",
              sport_type: "Ride",
              detail: true,
              has_gps: true,
              average_heartrate: 120,
            },
          ],
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    await expect(page.locator("#count-total")).toHaveText("4");
    await expect(page.locator("#count-gps")).toHaveText("1");
    await expect(page.locator("#state")).toContainText("1 activity has unknown GPS status");
    const rows = page.locator("#activity-list tbody tr");
    await expect(rows).toHaveCount(1);
    await expect(rows.first()).toContainText("Missing everything");
    await expect(rows.first().locator("td").nth(3)).toHaveText("Details, GPS");
    await expect(page.locator("#activity-list")).not.toContainText("GPS optional");
    await expect(page.locator("#activity-list")).not.toContainText("Unknown GPS");

    await page.locator("#filter-gps").uncheck();
    await expect(rows.first().locator("td").nth(3)).toHaveText("Details");
    await page.locator("#filter-details").uncheck();
    await expect(page.locator("#activity-list .empty")).toContainText(
      "No activities match",
    );
    await page.locator("#filter-heart-rate").check();
    await expect(page.locator("#activity-list tbody tr")).toHaveCount(2);
    await expect(page.locator("#activity-list")).toContainText("Heart rate");
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

  test("shows disabled, keepalive, and never-successful import states", async ({
    page,
  }) => {
    const now = Math.floor(Date.now() / 1000);
    await page.route("**/strava-sync-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ lastAttempt: now, lastSuccess: 0 }),
      }),
    );
    await page.route("**/healthsync-sync-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          mode: "keepalive",
          importEnabled: false,
          ok: true,
          lastAttempt: now,
          lastSuccess: now,
          error: "<config unavailable>",
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
    await expect(strava.locator(".badge")).toHaveText("No successful import");
    await expect(healthsync.locator(".badge")).toHaveText("Disabled");
    await expect(healthsync).toContainText(
      "Latest run checked Drive access only; no activities were imported.",
    );
    await expect(healthsync).toContainText("Activity import is disabled");
    await expect(healthsync.locator(".issues")).toHaveText(
      "<config unavailable>",
    );
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

  test("renders-a-run-log-from-refreshed-status", async ({ page }) => {
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.evaluate(() =>
      updateLogSection("strava", { log: ["stored run log entry"] }),
    );

    const log = page.locator("#log-section-strava");
    await expect(log.locator("details")).toHaveAttribute("open", "");
    await expect(log.locator("summary")).toContainText("Run log (1 lines)");
    await expect(log.locator("pre.run-log")).toContainText(
      "stored run log entry",
    );
  });

  test("live-log-preserves-scroll-position-unless-already-at-bottom", async ({ page }) => {
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const logText = (count) =>
      Array.from({ length: count }, (_, i) => `line ${i + 1}`).join("\n");
    await page.evaluate((text) => updateLogSectionRaw("strava", text), logText(40));

    const pre = page.locator("#log-section-strava pre.run-log");
    await expect(pre).toBeVisible();
    await pre.evaluate((el) => { el.scrollTop = 0; });
    await page.evaluate(
      (text) => updateLogSectionRaw("strava", text),
      logText(41),
    );
    await expect.poll(() => pre.evaluate((el) => el.scrollTop)).toBe(0);

    await pre.evaluate((el) => { el.scrollTop = el.scrollHeight; });
    await page.evaluate(
      (text) => updateLogSectionRaw("strava", text),
      logText(42),
    );
    await expect.poll(() =>
      pre.evaluate((el) => el.scrollHeight - el.clientHeight - el.scrollTop),
    ).toBeLessThanOrEqual(1);
  });

  test("sync-trigger-opens-log-details", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    await page.route("**/strava-sync-status.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          ok: true,
          lastAttempt: now,
          lastSuccess: now,
          log: ["line 1", "line 2"],
        }),
      }),
    );
    await page.route("**/cgi-bin/trigger-sync", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      }),
    );
    await page.route("**/strava-sync-live.log", (route) =>
      route.fulfill({ status: 404, body: "" }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const strava = page.locator("#sources .source").filter({ has: page.locator("h2", { hasText: /^Strava/ }) });
    const details = strava.locator("details").first();
    // starts collapsed
    await expect(strava.locator("pre.run-log"), "log pre hidden before sync").toBeHidden();
    // trigger sync
    await strava.locator("button.sync-btn[data-src]").click();
    // details should open immediately when startLivePolling runs
    await expect(details, "log <details> opens when sync is triggered").toHaveAttribute("open", "");
  });

  test("detects-a-sync-started-outside-the-page", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    let statusReads = 0;
    await page.route("**/strava-sync-status.json", (route) => {
      statusReads += 1;
      return route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          ok: true,
          lastAttempt: statusReads === 1 ? now : now + 1,
          lastSuccess: now + 1,
        }),
      });
    });
    await page.route("**/strava-sync-running", (route) =>
      route.fulfill({ status: 200, body: "running" }),
    );
    await page.route("**/strava-sync-live.log", (route) =>
      route.fulfill({ contentType: "text/plain", body: "cron sync started" }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.evaluate(() => {
      window.__sawCronSyncState = false;
      const observer = new MutationObserver(() => {
        const button = document.querySelector(
          '#sources .sync-btn[data-src="strava"]',
        );
        if (button?.disabled && button.textContent.includes("Running")) {
          window.__sawCronSyncState = true;
        }
      });
      observer.observe(document.getElementById("sources"), {
        attributes: true,
        childList: true,
        subtree: true,
        characterData: true,
      });
    });
    await expect
      .poll(() => page.evaluate(() => window.__sawCronSyncState), {
        timeout: 8000,
      })
      .toBeTruthy();
  });

  test("sync-completion-renders-live-log-and-refreshes-source-card", async ({
    page,
  }) => {
    const now = Math.floor(Date.now() / 1000);
    let statusReads = 0;
    await page.route("**/strava-sync-status.json", (route) => {
      statusReads += 1;
      return route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          ok: true,
          lastAttempt: statusReads <= 2 ? now : now + 1,
          lastSuccess: now + 1,
          log: ["final status log"],
        }),
      });
    });
    await page.route("**/cgi-bin/trigger-sync", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      }),
    );
    await page.route("**/strava-sync-live.log", (route) =>
      route.fulfill({ contentType: "text/plain", body: "sync started\n<unsafe> line\n\n" }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    const strava = page
      .locator("#sources .source")
      .filter({ has: page.locator("h2", { hasText: /^Strava/ }) });
    const button = strava.locator("button.sync-btn[data-src]");
    await button.click();
    await expect(button).toHaveText("✓ Done", { timeout: 7000 });
    await expect(strava.locator("pre.run-log")).toContainText("<unsafe> line");
    await expect(strava.locator("pre.run-log")).not.toContainText("<unsafe><");
    await expect(strava.locator("details summary")).toContainText("Show run log");
    await expect(strava.locator(".badge")).toContainText("OK");
  });

  test("sync-all-refreshes-cards-when-attempt-timestamps-do-not-change", async ({
    page,
  }) => {
    const now = Math.floor(Date.now() / 1000);
    const sources = ["strava", "healthsync", "leaderboard"];
    const triggered = Object.fromEntries(sources.map((src) => [src, false]));
    for (const src of sources) {
      await page.route(`**/${src}-sync-status.json`, (route) => {
        const isComplete = triggered[src];
        return route.fulfill({
          contentType: "application/json",
          body: JSON.stringify({
            ok: true,
            runId: isComplete ? `${src}-run-2` : `${src}-run-1`,
            lastAttempt: now,
            lastSuccess: now,
            log: [isComplete ? `${src} final status log` : "previous status log"],
          }),
        });
      });
      await page.route(`**/${src}-sync-running`, (route) =>
        route.fulfill({ status: 404, body: "" }),
      );
    }
    await page.route("**/cgi-bin/trigger-sync", async (route) => {
      const src = new URLSearchParams(route.request().postData()).get("source");
      triggered[src] = true;
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    await page.locator("#sync-all-btn").click();
    await expect.poll(() => Object.values(triggered).every(Boolean)).toBeTruthy();
    for (const src of sources) {
      const card = page.locator(`#sources .source:has([data-src="${src}"])`);
      await expect(card.locator("pre.run-log")).toContainText(
        `${src} final status log`,
        { timeout: 12000 },
      );
    }
  });

  test("sync-trigger-reports-server-error-and-recovers-button", async ({
    page,
  }) => {
    await page.route("**/cgi-bin/trigger-sync", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: false, error: "sync queue is full" }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    const button = page.locator(
      '#sources .source h2:has-text("Strava")',
    ).locator("..").locator("button.sync-btn[data-src]");
    await button.click();
    await expect(button).toHaveText("Error: sync queue is full");
    await expect(button).toBeEnabled();
  });

  test("sync-all-triggers-only-enabled-source-buttons", async ({ page }) => {
    const triggered = [];
    await page.route("**/cgi-bin/trigger-sync", async (route) => {
      triggered.push(new URLSearchParams(route.request().postData()).get("source"));
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: false, error: "test response" }),
      });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const healthsyncButton = page.locator(
      '#sources .source h2:has-text("HealthSync")',
    ).locator("..").locator("button.sync-btn[data-src]");
    await healthsyncButton.evaluate((button) => { button.disabled = true; });

    await page.locator("#sync-all-btn").click();
    await expect.poll(() => triggered.length).toBe(2);
    expect(triggered).toHaveLength(2);
    expect(triggered).toEqual(expect.arrayContaining(["strava", "leaderboard"]));
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

  test("cookie-section-omits-card-without-expiry-or-dry-run-expiry", async ({
    page,
  }) => {
    await page.route("**/me/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ activities: [], scrapeMeta: {} }),
      }),
    );
    await page.route("**/strava/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ activities: [] }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    await expect(page.locator("#cookie-status")).toBeVisible();
    await expect(page.locator("#cookie-cards .source")).toHaveCount(0);
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

  test("cookie-save-posts-the-value-and-clears-the-input", async ({ page }) => {
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
    let postedCookie;
    await page.route("**/cgi-bin/update-cookie", async (route) => {
      postedCookie = route.request().postDataJSON();
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true, updated: 2 }),
      });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    const input = page.locator("#cookie-input");
    await input.fill("new-session-cookie");
    await page.getByRole("button", { name: "Save cookie" }).click();
    await expect(page.locator("#cookie-save-status")).toContainText(
      "Cookie saved to 2 config file(s)",
    );
    await expect(input).toHaveValue("");
    expect(postedCookie).toEqual({ cookie: "new-session-cookie" });
  });

  test("cookie-save-requires-a-value", async ({ page }) => {
    await page.route("**/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          generatedAt: new Date().toISOString(),
          scrapeMeta: { cookieRefreshNeededBy: "2099-01-01" },
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    await page.getByRole("button", { name: "Save cookie" }).click();
    await expect(page.locator("#cookie-save-status")).toHaveText(
      "Please paste a cookie value.",
    );
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

  test("cookie-section-shows-expired-dry-run-and-feed-test-states", async ({
    page,
  }) => {
    const expired = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    await page.route("**/me/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          scrapeMeta: {
            cookieVerifiedAt: "2026-01-01",
            cookieRefreshNeededBy: expired,
          },
        }),
      }),
    );
    await page.route("**/strava/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          scrapeMeta: {
            dryRun: true,
            cookieValid: false,
            feedTestOk: false,
          },
        }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    const cards = page.locator("#cookie-cards .source");
    await expect(cards).toHaveCount(2);
    await expect(cards.nth(0)).toContainText("Expired");
    await expect(cards.nth(0)).toContainText("Cookie has expired");
    await expect(cards.nth(1)).toContainText("(api+dry-run)");
    await expect(cards.nth(1).locator(".badge")).toHaveText("Expired");
    await expect(cards.nth(1)).toContainText("Feed test failed");
  });

  test("cookie-save-shows-server-error", async ({ page }) => {
    await page.route("**/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          scrapeMeta: { cookieRefreshNeededBy: "2099-01-01" },
        }),
      }),
    );
    await page.route("**/cgi-bin/update-cookie", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: false, error: "config is read-only" }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.locator("#cookie-input").fill("session-value");
    await page.getByRole("button", { name: "Save cookie" }).click();

    await expect(page.locator("#cookie-save-status")).toHaveText(
      "Error: config is read-only",
    );
    await expect(page.locator("#cookie-input")).toHaveValue("session-value");
  });

  test("cookie-save-shows-network-failure", async ({ page }) => {
    await page.route("**/activities.json", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          activities: [],
          scrapeMeta: { cookieRefreshNeededBy: "2099-01-01" },
        }),
      }),
    );
    await page.route("**/cgi-bin/update-cookie", (route) =>
      route.abort("failed"),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.locator("#cookie-input").fill("session-value");
    await page.getByRole("button", { name: "Save cookie" }).click();

    await expect(page.locator("#cookie-save-status")).toContainText(
      "Request failed:",
    );
  });

  test("email-cards-show-failed-stale-and-partial-send-statuses", async ({
    page,
  }) => {
    const now = Math.floor(Date.now() / 1000);
    const statusByType = {
      monthly: {
        mode: "monthly",
        ok: false,
        lastAttempt: now,
        lastSuccess: 0,
        subject: "<Monthly report>",
        recipientCount: 4,
        sentCount: 2,
        log: ["<smtp> rejected two recipients"],
      },
      weekly: {
        mode: "weekly",
        ok: true,
        lastAttempt: now,
        lastSuccess: now - 9 * 86400,
        recipientCount: 2,
        sentCount: 2,
      },
      yearly: {
        mode: "yearly",
        ok: true,
        lastAttempt: now,
        lastSuccess: now - 371 * 86400,
      },
    };
    for (const [type, status] of Object.entries(statusByType)) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({
          contentType: "application/json",
          body: JSON.stringify(status),
        }),
      );
    }
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });

    const cards = page.locator("#email-cards .email-status-card");
    await expect(cards).toHaveCount(3);
    await expect(cards).toHaveAttribute("data-sid", "weekly");
    const monthly = cards.filter({ hasText: "Monthly email" });
    await expect(monthly.locator(".badge")).toHaveText("Failed");
    await expect(monthly).toContainText("<Monthly report>");
    await expect(monthly).toContainText("2 sent OK");
    await expect(monthly.locator("pre.run-log")).toContainText(
      "<smtp> rejected two recipients",
    );
    await expect(cards.filter({ hasText: "Weekly email" }).locator(".badge"))
      .toHaveText("Stale");
    await expect(cards.filter({ hasText: "Yearly email" }).locator(".badge"))
      .toHaveText("Stale");
    expect(
      await page.$$eval("#email-cards .email-sec", (els) =>
        els.map((el) => el.getAttribute("data-sid")),
      ),
    ).toEqual(["send", "weekly", "monthly", "yearly"]);
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
    await expect(sec.locator("h2").first()).toContainText("Email");
    const card = sec.locator(".source").filter({ hasText: "Monthly email" });
    await expect(card.locator(".badge")).toHaveText(/^OK/);
    await expect(card).toContainText("Strava Leaderboard - August 2026");
    await expect(card).toContainText("Recipients: 3");
  });

  test("email-cards-can-be-reordered-and-reset", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    for (const type of ["monthly", "weekly", "yearly"]) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({
          contentType: "application/json",
          body: JSON.stringify({
            mode: type, ok: true, lastAttempt: now, lastSuccess: now,
          }),
        }),
      );
    }
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    const ids = () =>
      page.$$eval("#email-cards .email-sec", (els) =>
        els.map((el) => el.getAttribute("data-sid")),
      );
    expect(await ids()).toEqual(["send", "weekly", "monthly", "yearly"]);

    await page.evaluate(() => {
      const wrap = document.getElementById("email-cards");
      const source = wrap.querySelector('.email-sec[data-sid="monthly"]');
      const target = wrap.querySelector('.email-sec[data-sid="send"]');
      const handle = source.querySelector(".sec-handle");
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = target.getBoundingClientRect();
      target.dispatchEvent(
        new MouseEvent("drop", {
          bubbles: true, cancelable: true, clientY: rect.top + 1,
        }),
      );
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    expect(await ids()).toEqual(["monthly", "send", "weekly", "yearly"]);
    expect(
      await page.evaluate(() => JSON.parse(localStorage.getItem("ssb-email-sec"))),
    ).toEqual(["monthly", "send", "weekly", "yearly"]);

    await page.reload({ waitUntil: "networkidle" });
    expect(await ids()).toEqual(["monthly", "send", "weekly", "yearly"]);
    await page.locator("#email-status .sec-order-reset").click();
    expect(await ids()).toEqual(["send", "weekly", "monthly", "yearly"]);
  });

  test("email-section-visible-with-send-form-when-no-status-files", async ({ page }) => {
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
    const sec = page.locator("#email-status");
    await expect(sec, "#email-status should be visible (contains send form)").toBeVisible();
    await expect(sec.locator("#send-email-card"), "send form should be present").toBeVisible();
    await expect(sec.locator("#email-type-sel"), "type dropdown should be present").toBeVisible();
    await expect(sec.locator("#email-to-override"), "override field should be present").toBeVisible();
    await expect(sec.locator("#email-cards .email-status-card"), "no status cards when no files").toHaveCount(0);
  });

  test("send-email-reports-a-rejected-request", async ({ page }) => {
    for (const type of ["monthly", "weekly", "yearly"]) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({ status: 404, body: "" }),
      );
    }
    let postedEmail;
    await page.route("**/cgi-bin/send-email", async (route) => {
      postedEmail = route.request().postDataJSON();
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: false, error: "SMTP unavailable" }),
      });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.locator("#email-type-sel").selectOption("yearly");
    await page.locator("#email-to-override").fill("rider@example.com");
    await page.locator("#send-email-card .sync-btn").click();

    await expect(page.locator("#send-email-status")).toHaveText(
      "Error: SMTP unavailable",
    );
    await expect(page.locator("#send-email-card .sync-btn")).toBeEnabled();
    expect(postedEmail).toEqual({
      type: "yearly",
      email_to: "rider@example.com",
    });
  });

  test("send-email-reports-an-asynchronous-send-failure", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    for (const type of ["monthly", "yearly"]) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({ status: 404, body: "" }),
      );
    }
    let sendQueued = false;
    await page.route("**/email-weekly-status.json", (route) => {
      return route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          mode: "weekly",
          ok: !sendQueued,
          lastAttempt: now + (sendQueued ? 1 : 0),
          lastSuccess: now,
        }),
      });
    });
    await page.route("**/cgi-bin/send-email", (route) => {
      sendQueued = true;
      return route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.locator("#email-type-sel").selectOption("weekly");
    await page.locator("#send-email-card .sync-btn").click();

    await expect(page.locator("#send-email-status")).toHaveText(
      "✗ Send failed — see status card for details.",
      { timeout: 10000 },
    );
    await expect(page.locator("#send-email-card .sync-btn")).toBeEnabled();
  });

  test("send-email-poll-timeout-restores-send-button", async ({ page }) => {
    for (const type of ["monthly", "weekly", "yearly"]) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({ status: 404, body: "" }),
      );
    }
    await page.route("**/cgi-bin/send-email", (route) =>
      route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      }),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.clock.install();
    await page.locator("#send-email-card .sync-btn").click();
    await expect(page.locator("#send-email-status")).toContainText(
      "Queued — waiting for completion",
    );

    await page.clock.fastForward(181000);

    await expect(page.locator("#send-email-status")).toHaveText(
      "✓ Sent (monthly). Refreshing…",
    );
    await expect(page.locator("#send-email-card .sync-btn")).toBeEnabled();
  });

  test("send-email-shows-request-failure-and-omits-empty-override", async ({
    page,
  }) => {
    for (const type of ["monthly", "weekly", "yearly"]) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({ status: 404, body: "" }),
      );
    }
    await page.route("**/cgi-bin/send-email", (route) =>
      route.abort("failed"),
    );
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.locator("#send-email-card .sync-btn").click();

    await expect(page.locator("#send-email-status")).toContainText(
      "Request failed:",
    );
    await expect(page.locator("#send-email-card .sync-btn")).toBeEnabled();
  });

  test("send-email-polls-until-the-send-completes", async ({ page }) => {
    const now = Math.floor(Date.now() / 1000);
    for (const type of ["monthly", "yearly"]) {
      await page.route(`**/email-${type}-status.json`, (route) =>
        route.fulfill({ status: 404, body: "" }),
      );
    }
    let weeklyStatusReads = 0;
    await page.route("**/email-weekly-status.json", async (route) => {
      weeklyStatusReads += 1;
      const complete = weeklyStatusReads >= 3;
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          mode: "weekly",
          ok: true,
          lastAttempt: complete ? now + 1 : now,
          lastSuccess: complete ? now + 1 : now,
          sentCount: complete ? 2 : 0,
        }),
      });
    });
    let postedEmail;
    await page.route("**/cgi-bin/send-email", async (route) => {
      postedEmail = route.request().postDataJSON();
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      });
    });
    await page.goto(URLS.dataQuality, { waitUntil: "networkidle" });
    await page.locator("#email-type-sel").selectOption("weekly");
    await page.locator("#send-email-card .sync-btn").click();

    await expect(page.locator("#send-email-status")).toHaveText(
      "✓ Sent (weekly) to 2 recipient(s).",
      { timeout: 10000 },
    );
    await expect(page.locator("#send-email-card .sync-btn")).toBeEnabled();
    expect(postedEmail).toEqual({ type: "weekly" });
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
