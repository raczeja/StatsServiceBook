import { test, expect } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

// ── Heatmap ────────────────────────────────────────────────────────────────────

test.describe("heatmap", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.heatmap, { waitUntil: "networkidle", timeout: 20000 });
    // Wait for the Leaflet map container and the activity count to populate.
    try {
      await page.waitForSelector(".leaflet-container", { timeout: 10000 });
      await page.waitForFunction(
        () => (document.getElementById("count")?.textContent || "").includes("activit"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("map-container-exists", async () => {
    const el = await page.$(".leaflet-container");
    expect(el, "leaflet-container not found").toBeTruthy();
  });

  test("period-dropdown-populated", async () => {
    const n = await page.$$eval("#period option", (opts) => opts.length);
    expect(n > 0, `expected options in #period, got ${n}`).toBeTruthy();
  });

  test("period-dropdown-has-all-time", async () => {
    const opts = await page.$$eval("#period option", (opts) => opts.map((o) => o.value));
    expect(opts.includes("all"), `expected "all" option in #period, got: ${JSON.stringify(opts)}`).toBeTruthy();
  });

  test("sport-dropdown-populated", async () => {
    const n = await page.$$eval("#sport option", (opts) => opts.length);
    expect(n > 0, `expected options in #sport, got ${n}`).toBeTruthy();
  });

  test("sport-dropdown-has-ride-and-run", async () => {
    const vals = await page.$$eval("#sport option", (opts) => opts.map((o) => o.value));
    expect(vals.includes("Ride"), `expected "Ride" in #sport options, got: ${JSON.stringify(vals)}`).toBeTruthy();
    expect(vals.includes("Run"), `expected "Run" in #sport options, got: ${JSON.stringify(vals)}`).toBeTruthy();
  });

  test("activity-count-shows-number", async () => {
    const text = await page.$eval("#count", (el) => el.textContent);
    expect(/\d+\s+activit/.test(text), `expected "N activit..." in #count, got: "${text}"`).toBeTruthy();
  });

  test("activity-count-shows-pts", async () => {
    const text = await page.$eval("#count", (el) => el.textContent);
    expect(text.includes("pts"), `expected "pts" in #count, got: "${text}"`).toBeTruthy();
  });

  test("city-labels-rendered", async () => {
    // cities.json is served from the test container; markers should appear after fetch.
    await page.waitForFunction(
      () => document.querySelectorAll(".city-lbl").length > 0,
      { timeout: 5000 },
    ).catch(() => {});
    const n = await page.$$eval(".city-lbl", (els) => els.length);
    expect(n > 0, `expected at least 1 .city-lbl marker, got ${n}`).toBeTruthy();
  });

  test("city-label-has-text", async () => {
    const texts = await page.$$eval(".city-lbl", (els) => els.map((el) => el.textContent.trim()));
    expect(
      texts.some((t) => t.length > 0),
      `expected non-empty text in .city-lbl elements, got: ${JSON.stringify(texts)}`,
    ).toBeTruthy();
  });

  test("sport-filter-all-more-than-ride", async () => {
    // Switch to All sports — count should be >= Ride-only count.
    const rideCount = await page.evaluate(() => {
      const t = document.getElementById("count")?.textContent || "";
      const m = t.match(/(\d+)\s+activit/);
      return m ? parseInt(m[1], 10) : 0;
    });

    await page.evaluate(() => {
      const sel = document.getElementById("sport");
      sel.value = "";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

    const allCount = await page.evaluate(() => {
      const t = document.getElementById("count")?.textContent || "";
      const m = t.match(/(\d+)\s+activit/);
      return m ? parseInt(m[1], 10) : 0;
    });
    expect(allCount >= rideCount, `all-sports count (${allCount}) should be >= ride count (${rideCount})`).toBeTruthy();
  });

  test("period-filter-w7-lte-all", async () => {
    // Switch to all-time first to get the total.
    await page.evaluate(() => {
      document.getElementById("sport").value = "";
      document.getElementById("sport").dispatchEvent(new Event("change", { bubbles: true }));
      document.getElementById("period").value = "all";
      document.getElementById("period").dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const allCount = await page.evaluate(() => {
      const t = document.getElementById("count")?.textContent || "";
      const m = t.match(/(\d+)\s+activit/);
      return m ? parseInt(m[1], 10) : 0;
    });

    await page.evaluate(() => {
      document.getElementById("period").value = "w7";
      document.getElementById("period").dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const w7Count = await page.evaluate(() => {
      const t = document.getElementById("count")?.textContent || "";
      const m = t.match(/(\d+)\s+activit/);
      return m ? parseInt(m[1], 10) : 0;
    });

    expect(w7Count <= allCount, `w7 count (${w7Count}) should be <= all-time count (${allCount})`).toBeTruthy();
  });

  test("leaflet-canvas-painted", async () => {
    // The heat layer renders into a <canvas> inside .leaflet-overlay-pane.
    // Switch to all-time + all sports so heat points are present.
    await page.evaluate(() => {
      document.getElementById("period").value = "all";
      document.getElementById("period").dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 500)));
    const canvasCount = await page.$$eval(
      ".leaflet-overlay-pane canvas",
      (els) => els.length,
    );
    expect(canvasCount > 0, `expected canvas in .leaflet-overlay-pane, got ${canvasCount}`).toBeTruthy();
  });
});
