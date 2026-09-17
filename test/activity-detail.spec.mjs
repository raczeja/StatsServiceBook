import { test, expect } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

// ── Activity Detail (Strava) ───────────────────────────────────────────────────

test.describe("activity-detail", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.activity, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    expect(real.length, real.map((e) => e.message).join("; ")).toBe(0);
  });

  test("no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    expect(text, `#err is not empty: "${text}"`).toBe("");
  });

  test("content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    expect(display !== "none", `#content has display:none`).toBeTruthy();
  });

  test("title-west-wroclaw", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    expect(text.includes("West Wroclaw"), `expected "West Wroclaw" in #name, got "${text}"`).toBeTruthy();
  });

  test("cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    expect(n >= 4, `expected >= 4 stat cards, got ${n}`).toBeTruthy();
  });

  test("distance-64km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("64.3") || text.includes("64.2"),
      `expected ~64.2/64.3 km in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elevation-612m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("612"), `expected "612" m in .cards: ${text.slice(0, 200)}`).toBeTruthy();
  });

  test("splits-chart-rendered", async () => {
    const n = await page.$$eval("#svg-splits rect, #svg-splits polyline", (els) => els.length);
    expect(n > 0, `expected SVG elements in #svg-splits, got ${n}`).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`).toBeTruthy();
  });

  test("hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    expect(display !== "none", `#hr-box has display:none`).toBeTruthy();
  });

  test("svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`).toBeTruthy();
  });

  test("hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    expect(display !== "none", `#hr-zone-box has display:none`).toBeTruthy();
  });

  test("hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    expect(n, `expected 5 HR zone rows, got ${n}`).toBe(5);
  });

  test("hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    expect(txt.includes("185"), `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`).toBeTruthy();
  });

  test("elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    expect(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`).toBeTruthy();
  });

  test("hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-hr"] && window.LINE_TIPS["svg-hr"].length) || 0
    );
    expect(n > 0, `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`).toBeTruthy();
  });

  test("elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(new MouseEvent("mousemove", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2
      }));
      return document.getElementById("chart-tip").style.display === "block";
    });
    expect(tipVisible, "#chart-tip should become visible on mousemove over #svg-elev").toBeTruthy();
  });

  test("cad-box-visible", async () => {
    const display = await page.$eval("#cad-box", (el) => el.style.display);
    expect(display !== "none", `#cad-box has display:none — cadence chart not rendered`).toBeTruthy();
  });

  test("svg-cad-rendered", async () => {
    const n = await page.$$eval("#svg-cad path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-cad (fill + line), got ${n}`).toBeTruthy();
  });

  test("pwr-box-visible", async () => {
    const display = await page.$eval("#pwr-box", (el) => el.style.display);
    expect(display !== "none", `#pwr-box has display:none — power chart not rendered`).toBeTruthy();
  });

  test("svg-pwr-rendered", async () => {
    const n = await page.$$eval("#svg-pwr path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-pwr (fill + line), got ${n}`).toBeTruthy();
  });

  test("splits-box-visible", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(display !== "none", `#splits-box unexpectedly hidden for Strava activity`).toBeTruthy();
  });

  test("weather-temp-source-badge-shown", async () => {
    const badge = await page.$(".cards .wx-src");
    expect(badge, "expected .wx-src source badge in temp card, got none").toBeTruthy();
  });

  test("weather-temp-archive-badge", async () => {
    const hasBadge = await page.evaluate(() => !!document.querySelector(".wx-arch"));
    expect(hasBadge, 'expected .wx-arch badge (archive source) in temp card').toBeTruthy();
  });

  test("weather-temp-feels-like-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("feels") && text.includes("27"),
      `expected "feels 27" in .cards weather section: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("weather-wind-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.toLowerCase().includes("wind") && text.includes("15"),
      `expected Wind card with "15 km/h" in .cards: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("weather-wind-direction-arrow", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("←"), `expected west arrow "←" in Wind card (wind_dir=270), got: ${text.slice(0, 300)}`).toBeTruthy();
  });

  test("gear-card-shows-name", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("Bike A"), `expected "Bike A" in gear card, got: ${text.slice(0, 400)}`).toBeTruthy();
  });

  test("bike-picker-selects-gear-name", async () => {
    try {
      await page.waitForSelector("#bike-sel", { timeout: 5000 });
    } catch (_) {
      throw new Error("#bike-sel did not appear — bike picker not rendered for Ride activity");
    }
    const selected = await page.$eval("#bike-sel", (el) => el.value);
    expect(selected, `expected bike picker to show "Bike A" (gear name not in bike-service), got "${selected}"`).toBe("Bike A");
  });
});

// ── Detail Section Order ───────────────────────────────────────────────────────

test.describe("detail-section-order", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => {
      try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {}
      try { sessionStorage.clear(); } catch (_) {}
    });
    await page.goto(URLS.activity, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
    await page.evaluate(() => { try { localStorage.removeItem("ssb-detail-sec"); } catch (_) {} });
    await page.close();
  });

  test("no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    expect(real.length, real.map((e) => e.message).join("; ")).toBe(0);
  });

  test("all-sections-present", async () => {
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const expected = ["cards", "map", "elev", "hr", "cad", "pwr", "hrzone", "splits"];
    expect(sids, `sections: ${JSON.stringify(sids)}`).toEqual(expected);
  });

  test("drag-handles-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec .sec-handle", (els) => els.length);
    expect(n, `expected 8 .sec-handle elements, got ${n}`).toBe(8);
  });

  test("reset-button-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec-order-reset", (els) => els.length);
    expect(n, `expected 1 .sec-order-reset button, got ${n}`).toBe(1);
  });

  test("drag-to-reorder-works", async () => {
    await page.evaluate(() => {
      const wrap = document.getElementById("sec-wrap");
      const secs = Array.from(wrap.querySelectorAll(".sec[data-sid]"));
      const src = secs.find((s) => s.getAttribute("data-sid") === "splits");
      const tgt = secs.find((s) => s.getAttribute("data-sid") === "hrzone");
      const handle = src ? src.querySelector(".sec-handle") : null;
      if (!handle || !tgt) return;
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = tgt.getBoundingClientRect();
      tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + 1 }));
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    expect(sids[sids.length - 2], `expected "splits" second-to-last, got "${sids[sids.length - 2]}"`).toBe("splits");
    expect(sids[sids.length - 1], `expected "hrzone" last, got "${sids[sids.length - 1]}"`).toBe("hrzone");
  });

  test("order-persisted-in-localstorage", async () => {
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-detail-sec")); } catch (_) { return null; }
    });
    expect(Array.isArray(saved) && saved.length === 8, "saved order should be 8-element array").toBeTruthy();
    expect(saved[saved.length - 2], `expected "splits" second-to-last in saved`).toBe("splits");
  });

  test("reset-button-restores-default-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector("#sec-wrap .sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    expect(sids[sids.length - 1], `after reset, expected "splits" last, got "${sids[sids.length - 1]}"`).toBe("splits");
  });
});

// ── Activity Detail (HealthSync Run) ──────────────────────────────────────────

test.describe("activity-detail-healthsync-run", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.activityHealthsyncRun, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    expect(real.length, real.map((e) => e.message).join("; ")).toBe(0);
  });

  test("no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    expect(text, `#err is not empty: "${text}"`).toBe("");
  });

  test("content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    expect(display !== "none", `#content has display:none`).toBeTruthy();
  });

  test("title-healthsync-run", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    expect(text.includes("HealthSync") || text.includes("Run"), `expected HealthSync or Run in #name, got "${text}"`).toBeTruthy();
  });

  test("cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    expect(n >= 4, `expected >= 4 stat cards, got ${n}`).toBeTruthy();
  });

  test("distance-3km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("3.2"), `expected ~3.2 km in .cards: ${text.slice(0, 200)}`).toBeTruthy();
  });

  test("elevation-18m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("18"), `expected "18" m in .cards: ${text.slice(0, 200)}`).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`).toBeTruthy();
  });

  test("hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    expect(display !== "none", `#hr-box has display:none`).toBeTruthy();
  });

  test("svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`).toBeTruthy();
  });

  test("hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    expect(display !== "none", `#hr-zone-box has display:none`).toBeTruthy();
  });

  test("hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    expect(n, `expected 5 HR zone rows, got ${n}`).toBe(5);
  });

  test("hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    expect(txt.includes("185"), `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`).toBeTruthy();
  });

  test("elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    expect(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`).toBeTruthy();
  });

  test("hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-hr"] && window.LINE_TIPS["svg-hr"].length) || 0
    );
    expect(n > 0, `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`).toBeTruthy();
  });

  test("elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(new MouseEvent("mousemove", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2
      }));
      return document.getElementById("chart-tip").style.display === "block";
    });
    expect(tipVisible, "#chart-tip should become visible on mousemove over #svg-elev").toBeTruthy();
  });

  test("cad-box-visible", async () => {
    const display = await page.$eval("#cad-box", (el) => el.style.display);
    expect(display !== "none", `#cad-box has display:none — cadence chart not rendered from GPX`).toBeTruthy();
  });

  test("svg-cad-rendered", async () => {
    const n = await page.$$eval("#svg-cad path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-cad (fill + line), got ${n}`).toBeTruthy();
  });

  test("cadence-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("85") && text.toLowerCase().includes("cadence"),
      `expected cadence card with value 85 in .cards: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("splits-box-hidden", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(display, `#splits-box should be hidden for HealthSync activity, got "${display}"`).toBe("none");
  });
});

// ── Activity Detail (HealthSync Cycling) ──────────────────────────────────────

test.describe("activity-detail-healthsync-cycling", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.activityHealthsyncCycling, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    expect(real.length, real.map((e) => e.message).join("; ")).toBe(0);
  });

  test("no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    expect(text, `#err is not empty: "${text}"`).toBe("");
  });

  test("content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    expect(display !== "none", `#content has display:none`).toBeTruthy();
  });

  test("title-cycling", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    expect(text.includes("CYCLING"), `expected "CYCLING" in #name, got "${text}"`).toBeTruthy();
  });

  test("cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    expect(n >= 4, `expected >= 4 stat cards, got ${n}`).toBeTruthy();
  });

  test("distance-25km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("25.1") || text.includes("25.2"),
      `expected ~25.1 km in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elevation-64m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("64"), `expected "64" m in .cards: ${text.slice(0, 200)}`).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`).toBeTruthy();
  });

  test("splits-box-hidden", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(display, `#splits-box should be hidden for HealthSync activity, got "${display}"`).toBe("none");
  });
});

// ── Activity Detail (Magene) ───────────────────────────────────────────────────

test.describe("activity-detail-magene", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.activityMagene, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    expect(real.length, real.map((e) => e.message).join("; ")).toBe(0);
  });

  test("no-error-shown", async () => {
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    expect(text, `#err is not empty: "${text}"`).toBe("");
  });

  test("content-visible", async () => {
    const display = await page.$eval("#content", (el) => el.style.display);
    expect(display !== "none", `#content has display:none`).toBeTruthy();
  });

  test("title-magene", async () => {
    const text = await page.$eval("#name", (el) => el.textContent.trim());
    expect(text.includes("Magene"), `expected "Magene" in #name, got "${text}"`).toBeTruthy();
  });

  test("cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    expect(n >= 4, `expected >= 4 stat cards, got ${n}`).toBeTruthy();
  });

  test("distance-84km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("84.6") || text.includes("84.5"),
      `expected ~84.6 km in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elevation-303m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text.includes("303"), `expected "303" m in .cards: ${text.slice(0, 200)}`).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(n >= 2, `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`).toBeTruthy();
  });

  test("hr-box-hidden", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    expect(display, `#hr-box should be hidden for Magene (no HR), got "${display}"`).toBe("none");
  });

  test("hr-zone-box-hidden", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    expect(display, `#hr-zone-box should be hidden for Magene (no HR), got "${display}"`).toBe("none");
  });

  test("elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(() =>
      (window.LINE_TIPS && window.LINE_TIPS["svg-elev"] && window.LINE_TIPS["svg-elev"].length) || 0
    );
    expect(n > 0, `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`).toBeTruthy();
  });

  test("splits-box-hidden", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(display, `#splits-box should be hidden for Magene activity, got "${display}"`).toBe("none");
  });
});

// ── Activity Detail (Walk — steps card) ───────────────────────────────────────

test.describe("activity-detail-walk", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.activityWalk, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    const real = jsErrors.filter(
      (e) =>
        !e.message?.toLowerCase().includes("leaflet") &&
        !e.message?.toLowerCase().includes("unpkg.com"),
    );
    expect(real.length, real.map((e) => e.message).join("; ")).toBe(0);
  });

  test("steps-card-shown", async () => {
    const text = await page.$eval(".cards", el => el.textContent);
    const digits = text.replace(/[,.\s]/g, "");
    expect(
      text.includes("Steps") && digits.includes("9530"),
      `expected Steps card with ~9530 in .cards: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("cadence-card-shown", async () => {
    const text = await page.$eval(".cards", el => el.textContent);
    expect(
      text.toLowerCase().includes("cadence") && text.includes("55"),
      `expected cadence card with value 55: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });
});

// ── Strava Link (numeric vs HealthSync ID) ────────────────────────────────────

test.describe("strava-link", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.activity, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("strava-activity-has-open-link", async () => {
    const text = await page.$eval("#links", (el) => el.textContent);
    expect(text.includes("Open on Strava"), `expected "Open on Strava" in #links for Strava activity, got: "${text}"`).toBeTruthy();
  });

  test("strava-link-href-contains-id", async () => {
    const href = await page.$eval('#links a[href*="strava.com"]', (el) => el.href);
    expect(href.includes("18784255013"), `expected activity ID in Strava link href, got: "${href}"`).toBeTruthy();
  });

  test("healthsync-activity-no-strava-link", async () => {
    jsErrors.length = 0;
    await page.goto(URLS.activityHealthsyncRun, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
    const link = await page.$('#links a[href*="strava.com"]');
    expect(!link, 'expected no "Open on Strava" link for HealthSync activity').toBeTruthy();
  });
});

// ── Heatmap ────────────────────────────────────────────────────────────────────

test.describe("heatmap", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.heatmap, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => (document.getElementById("count")?.textContent || "").length > 0,
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("map-container-present", async () => {
    const el = await page.$("#map");
    expect(el, "#map element not found").toBeTruthy();
  });

  test("period-dropdown-present", async () => {
    const el = await page.$("#period");
    expect(el, "#period select not found").toBeTruthy();
  });

  test("period-has-all-time-option", async () => {
    const opts = await page.$$eval("#period option", (os) => os.map((o) => o.value));
    expect(opts.includes("all"), `expected "all" option in #period, got: ${JSON.stringify(opts)}`).toBeTruthy();
  });

  test("period-has-time-range-options", async () => {
    const opts = await page.$$eval("#period option", (os) => os.map((o) => o.value));
    expect(opts.includes("w7"),  `expected "w7"  option in #period`).toBeTruthy();
    expect(opts.includes("w30"), `expected "w30" option in #period`).toBeTruthy();
    expect(opts.includes("w90"), `expected "w90" option in #period`).toBeTruthy();
  });

  test("period-has-year-options", async () => {
    const opts = await page.$$eval("#period option", (os) => os.map((o) => o.value));
    const years = opts.filter((v) => /^\d{4}$/.test(v));
    expect(years.length >= 1, `expected at least one year option, got: ${JSON.stringify(opts)}`).toBeTruthy();
  });

  test("default-is-last-3-months", async () => {
    const val = await page.$eval("#period", (el) => el.value);
    expect(val, `expected default period to be "w90", got: "${val}"`).toBe("w90");
  });

  test("default-last-3-months-shows-1-activity", async () => {
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(count.startsWith("1 "), `expected count to start with "1 " for Last 3 months + Ride (default), got: "${count}"`).toBeTruthy();
  });

  test("sport-dropdown-present", async () => {
    const el = await page.$("#sport");
    expect(el, "#sport select not found").toBeTruthy();
  });

  test("sport-has-all-sports-option", async () => {
    const opts = await page.$$eval("#sport option", (os) => os.map((o) => o.value));
    expect(opts.includes(""), `expected "" (All sports) option in #sport, got: ${JSON.stringify(opts)}`).toBeTruthy();
  });

  test("sport-has-ride-and-run", async () => {
    const opts = await page.$$eval("#sport option", (os) => os.map((o) => o.value));
    expect(opts.includes("Ride"), `expected "Ride" option in #sport, got: ${JSON.stringify(opts)}`).toBeTruthy();
    expect(opts.includes("Run"),  `expected "Run"  option in #sport, got: ${JSON.stringify(opts)}`).toBeTruthy();
  });

  test("sport-default-is-ride", async () => {
    const val = await page.$eval("#sport", (el) => el.value);
    expect(val, `expected default sport to be "Ride", got: "${val}"`).toBe("Ride");
  });

  test("all-time-shows-4-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      sel.value = "all"; sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(count.startsWith("4 "), `expected count to start with "4 " for All time + All sports, got: "${count}"`).toBeTruthy();
  });

  test("filter-2024-shows-2-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      const opt = Array.from(sel.options).find((o) => o.value === "2024");
      if (opt) { sel.value = "2024"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(count.startsWith("2 "), `expected count to start with "2 " for 2024 + All sports, got: "${count}"`).toBeTruthy();
  });

  test("sport-filter-run-all-time-shows-1", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("period");
      sel.value = "all"; sel.dispatchEvent(new Event("change", { bubbles: true }));
      const ssel = document.getElementById("sport");
      ssel.value = "Run"; ssel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(count.startsWith("1 "), `expected count to start with "1 " for All time + Run sport filter, got: "${count}"`).toBeTruthy();
  });

  test("filter-last-7-days-shows-0-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = ""; ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      sel.value = "w7"; sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(count.startsWith("0 "), `expected count to start with "0 " for last-7-days filter, got: "${count}"`).toBeTruthy();
  });

  test("dashboard-link-present", async () => {
    const href = await page.$eval(".crumbs a", (el) => el.getAttribute("href"));
    expect(href && href.includes("index.html"), `expected crumbs link to index.html, got: "${href}"`).toBeTruthy();
  });
});
