import { test, expect } from "./coverage-fixture.mjs";
import { URLS } from "./test-urls.mjs";

// All tests in this file run at a narrow touch viewport so @media(pointer:coarse)
// and @media(max-width:640px) rules apply — exercising mobile-specific layout
// that the desktop chromium project does not cover.
test.use({ viewport: { width: 375, height: 812 }, hasTouch: true });

// ── Stats – touch hides drag controls ─────────────────────────────────────────
//
// @media(pointer:coarse){.sec-handle,.sec-order-reset{display:none}}
// The elements are injected by JS after load; CSS then hides them on touch.
// The desktop tests (stats-section-order) confirm they ARE visible — these
// confirm they are NOT visible on touch, so both sides of the rule are covered.

test.describe("mobile-stats-touch-controls", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".sec[data-sid]", { timeout: 10000 });
    } catch (_) {}
  });

  test.afterAll(async () => {
    await page.close();
  });

  test("no-js-errors", async () => {
    expect(
      jsErrors.map((e) => e.message).join("; "),
      "JS errors on mobile stats",
    ).toBe("");
  });

  test("sec-handle-hidden-on-touch", async () => {
    // Elements exist in the DOM (JS injects them) but must be CSS-invisible.
    const hidden = await page.evaluate(() => {
      const handles = document.querySelectorAll(".sec-handle");
      if (handles.length === 0) return true; // not yet injected → no drag UI, also fine
      return Array.from(handles).every(
        (el) => window.getComputedStyle(el).display === "none",
      );
    });
    expect(
      hidden,
      "expected all .sec-handle elements hidden on touch (pointer:coarse)",
    ).toBe(true);
  });

  test("sec-order-reset-hidden-on-touch", async () => {
    const hidden = await page.evaluate(() => {
      const btns = document.querySelectorAll(".sec-order-reset");
      if (btns.length === 0) return true;
      return Array.from(btns).every(
        (el) => window.getComputedStyle(el).display === "none",
      );
    });
    expect(
      hidden,
      "expected .sec-order-reset button hidden on touch (pointer:coarse)",
    ).toBe(true);
  });

  test("all-sections-still-render", async () => {
    const n = await page.$$eval(".sec[data-sid]", (els) => els.length);
    expect(n, `expected 12 stat sections on mobile, got ${n}`).toBe(12);
  });
});

// ── Stats – narrow layout ──────────────────────────────────────────────────────

test.describe("mobile-stats-layout", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
    } catch (_) {}
  });

  test.afterAll(async () => {
    await page.close();
  });

  test("kpi-cards-fit-within-viewport", async () => {
    // At 375px, @media(max-width:640px) applies: kpi minmax drops to 120px.
    // Verify no kpi card overflows the viewport width.
    const overflow = await page.evaluate(() => {
      const vpw = window.innerWidth;
      return Array.from(document.querySelectorAll(".kpis .kpi")).some(
        (el) => el.getBoundingClientRect().right > vpw + 1,
      );
    });
    expect(overflow, "a .kpi card overflows the mobile viewport").toBe(false);
  });

  test("h1-does-not-overflow-viewport", async () => {
    const overflow = await page.evaluate(() => {
      const h1 = document.querySelector("h1");
      if (!h1) return false;
      return h1.getBoundingClientRect().right > window.innerWidth + 1;
    });
    expect(overflow, "h1 overflows mobile viewport on stats page").toBe(false);
  });
});

// ── Dashboard – chart tooltip on touch ────────────────────────────────────────
//
// Bar rects are wired with ontouchstart="showTip(...)" + ontouchend="setTimeout(hideTip,3000)".
// Verify the tooltip appears on a touch event — behaviour not covered by desktop tests.

test.describe("mobile-dashboard-chart-tooltip", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("svg rect[ontouchstart]", { timeout: 10000 });
    } catch (_) {}
  });

  test.afterAll(async () => {
    await page.close();
  });

  test("no-js-errors", async () => {
    expect(
      jsErrors.map((e) => e.message).join("; "),
      "JS errors on mobile dashboard chart",
    ).toBe("");
  });

  test("chart-tip-shown-on-touchstart", async () => {
    // Fire the ontouchstart handler on the first bar rect that has one.
    const shown = await page.evaluate(() => {
      const rect = document.querySelector("svg rect[ontouchstart]");
      if (!rect) return null;
      const bounds = rect.getBoundingClientRect();
      const cx = bounds.left + bounds.width / 2;
      const cy = bounds.top + bounds.height / 2;
      // Simulate a touch at the bar's centre — ontouchstart reads touches[0].clientX/Y.
      const touch = new Touch({
        identifier: 1,
        target: rect,
        clientX: cx,
        clientY: cy,
      });
      rect.dispatchEvent(
        new TouchEvent("touchstart", { bubbles: true, touches: [touch] }),
      );
      const tip = document.getElementById("chart-tip");
      return tip ? tip.style.display : null;
    });
    expect(shown, `#chart-tip display after touchstart, got "${shown}"`).toBe(
      "block",
    );
  });

  test("chart-tip-has-content-after-touchstart", async () => {
    const text = await page.evaluate(() => {
      const tip = document.getElementById("chart-tip");
      return tip ? tip.textContent.trim() : "";
    });
    expect(
      text.length,
      `#chart-tip should have non-empty text after touchstart, got "${text}"`,
    ).toBeGreaterThan(0);
  });
});

// ── Dashboard – narrow layout ──────────────────────────────────────────────────

test.describe("mobile-dashboard-layout", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board tr", { timeout: 10000 });
    } catch (_) {}
  });

  test.afterAll(async () => {
    await page.close();
  });

  test("no-js-errors", async () => {
    expect(
      jsErrors.map((e) => e.message).join("; "),
      "JS errors on mobile dashboard",
    ).toBe("");
  });

  test("activity-rows-present", async () => {
    const n = await page.$$eval("#board tr", (rows) => rows.length);
    expect(
      n,
      `expected at least 1 activity row on mobile dashboard, got ${n}`,
    ).toBeGreaterThanOrEqual(1);
  });

  test("h1-does-not-overflow-viewport", async () => {
    const overflow = await page.evaluate(() => {
      const h1 = document.querySelector("h1");
      if (!h1) return false;
      return h1.getBoundingClientRect().right > window.innerWidth + 1;
    });
    expect(overflow, "h1 overflows mobile viewport on dashboard").toBe(false);
  });
});

// ── Activity detail – cooperative two-finger map gestures ──────────────────────
//
// enableCoopGestures() makes the detail route map require two fingers to pan on a
// touch device: map.dragging is disabled on load, a one-finger swipe scrolls the
// page and shows a "Use two fingers to move the map" hint instead, and dragging is
// re-enabled only while two touches are down. Desktop projects have no touch, so
// this behaviour can only be exercised here. leafletMap is a top-level global in
// the detail page, so it is reachable as window.leafletMap.

test.describe("mobile-activity-map-gestures", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.activityMultiClimb, {
      waitUntil: "load",
      timeout: 20000,
    });
    try {
      await page.waitForFunction(
        () => window.leafletMap && window.leafletMap.getContainer(),
        { timeout: 15000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
    await page.close();
  });

  test("no-js-errors", async () => {
    expect(
      jsErrors.map((e) => e.message).join("; "),
      "JS errors on mobile activity map",
    ).toBe("");
  });

  test("dragging-disabled-on-load", async () => {
    // enableCoopGestures() calls map.dragging.disable() immediately on touch.
    const enabled = await page.evaluate(() =>
      window.leafletMap.dragging.enabled(),
    );
    expect(
      enabled,
      "map dragging should be disabled on touch until two fingers are down",
    ).toBe(false);
  });

  test("hint-shown-after-one-finger-touchmove", async () => {
    // A one-finger touchmove over the map should surface the instruction overlay.
    const opacity = await page.evaluate(() => {
      const c = window.leafletMap.getContainer();
      const b = c.getBoundingClientRect();
      const t = new Touch({
        identifier: 1,
        target: c,
        clientX: b.left + b.width / 2,
        clientY: b.top + b.height / 2,
      });
      c.dispatchEvent(
        new TouchEvent("touchmove", { bubbles: true, touches: [t] }),
      );
      const overlay = Array.from(c.querySelectorAll("div")).find((d) =>
        /two fingers/i.test(d.textContent || ""),
      );
      return overlay ? overlay.style.opacity : null;
    });
    expect(
      opacity,
      'one-finger touchmove should show the "two fingers" hint overlay',
    ).toBe("1");
  });

  test("dragging-enabled-with-two-fingers", async () => {
    // Two touches down → map.dragging.enable().
    const enabled = await page.evaluate(() => {
      const c = window.leafletMap.getContainer();
      const b = c.getBoundingClientRect();
      const mk = (id, dx) =>
        new Touch({
          identifier: id,
          target: c,
          clientX: b.left + b.width / 2 + dx,
          clientY: b.top + b.height / 2,
        });
      c.dispatchEvent(
        new TouchEvent("touchstart", {
          bubbles: true,
          touches: [mk(1, -20), mk(2, 20)],
        }),
      );
      return window.leafletMap.dragging.enabled();
    });
    expect(
      enabled,
      "two-finger touchstart should re-enable map dragging",
    ).toBe(true);
  });

  test("dragging-disabled-again-after-lifting-to-one-finger", async () => {
    // Lifting back to a single remaining touch should disable dragging again.
    const enabled = await page.evaluate(() => {
      const c = window.leafletMap.getContainer();
      const b = c.getBoundingClientRect();
      const t = new Touch({
        identifier: 1,
        target: c,
        clientX: b.left + b.width / 2,
        clientY: b.top + b.height / 2,
      });
      c.dispatchEvent(
        new TouchEvent("touchend", { bubbles: true, touches: [t] }),
      );
      return window.leafletMap.dragging.enabled();
    });
    expect(
      enabled,
      "dragging should be disabled again once only one finger remains",
    ).toBe(false);
  });
});
