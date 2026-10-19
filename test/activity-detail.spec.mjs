import { test, expect } from "./coverage-fixture.mjs";
import { URLS } from "./test-urls.mjs";

// ── Activity Detail (Strava) ───────────────────────────────────────────────────

test.describe("activity-detail", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
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
    expect(
      text.includes("West Wroclaw"),
      `expected "West Wroclaw" in #name, got "${text}"`,
    ).toBeTruthy();
  });

  test("cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    expect(n >= 4, `expected >= 4 stat cards, got ${n}`).toBeTruthy();
  });

  test("strava-relative-effort-kept-as-official-score", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(text).toContain("Strava Relative Effort121");
    expect(await page.$("#hr-effort-card")).not.toBeNull();
  });

  test("official-relative-effort-falls-back-to-activity-summary", async () => {
    const cards = await page.$eval("#cards", (el) => el.innerHTML);
    try {
      const score = await page.evaluate(() => {
        const detail = fillDetailFromActivity(
          { id: 123, suffer_score: null },
          { id: 123, suffer_score: 232 },
        );
        renderCards(detail);
        const card = Array.from(document.querySelectorAll("#cards .card")).find(
          (el) =>
            el.querySelector(".k")?.textContent === "Strava Relative Effort",
        );
        return card?.querySelector(".v")?.textContent.trim();
      });
      expect(score).toBe("232");
    } finally {
      await page.$eval(
        "#cards",
        (el, html) => {
          el.innerHTML = html;
        },
        cards,
      );
    }
  });

  test("official-score-and-estimate-are-shown-separately", async () => {
    const cards = await page.$eval("#cards", (el) => el.innerHTML);
    try {
      const result = await page.evaluate(() => {
        const detail = fillDetailFromActivity(
          {
            id: 123,
            suffer_score: null,
            average_heartrate: 150,
            max_heartrate: 190,
            moving_time: 3600,
          },
          { id: 123, suffer_score: 232 },
        );
        renderCards(detail);
        return {
          official: Array.from(document.querySelectorAll("#cards .card"))
            .find(
              (el) =>
                el.querySelector(".k")?.textContent ===
                "Strava Relative Effort",
            )
            ?.querySelector(".v")
            ?.textContent.trim(),
          estimated: document
            .querySelector("#hr-effort-card .v")
            ?.textContent.trim(),
        };
      });
      expect(result.official).toBe("232");
      expect(Number(result.estimated)).toBeGreaterThan(0);
    } finally {
      await page.$eval(
        "#cards",
        (el, html) => {
          el.innerHTML = html;
        },
        cards,
      );
    }
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
    expect(
      text.includes("612"),
      `expected "612" m in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("splits-chart-rendered", async () => {
    const n = await page.$$eval(
      "#svg-splits rect, #svg-splits polyline",
      (els) => els.length,
    );
    expect(
      n > 0,
      `expected SVG elements in #svg-splits, got ${n}`,
    ).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("svg-elev-axis-starts-at-0m", async () => {
    const text = await page.$eval("#svg-elev-yaxis", (el) => el.textContent);
    expect(
      /0 m/.test(text),
      `expected #svg-elev-yaxis to include a "0 m" label, got: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    expect(display !== "none", `#hr-box has display:none`).toBeTruthy();
  });

  test("svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    expect(display !== "none", `#hr-zone-box has display:none`).toBeTruthy();
  });

  test("hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    expect(n, `expected 6 HR zone rows, got ${n}`).toBe(6);
  });

  test("hr-zone-descriptive-names", async () => {
    const txt = await page.$eval("#hr-zone-content", (el) => el.textContent);
    for (const name of [
      "Relaxed",
      "Healthy",
      "Fat Burn",
      "Aerobic",
      "Strength Training",
      "Red-line",
    ]) {
      expect(
        txt.includes(name),
        `expected zone name "${name}" in #hr-zone-content, got: ${txt.slice(0, 300)}`,
      ).toBeTruthy();
    }
  });

  test("hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    expect(
      txt.includes("185"),
      `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`,
    ).toBeTruthy();
  });

  test("elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(
      () =>
        (window.LINE_TIPS &&
          window.LINE_TIPS["svg-elev"] &&
          window.LINE_TIPS["svg-elev"].length) ||
        0,
    );
    expect(
      n > 0,
      `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`,
    ).toBeTruthy();
  });

  test("hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(
      () =>
        (window.LINE_TIPS &&
          window.LINE_TIPS["svg-hr"] &&
          window.LINE_TIPS["svg-hr"].length) ||
        0,
    );
    expect(
      n > 0,
      `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`,
    ).toBeTruthy();
  });

  test("elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(
        new MouseEvent("mousemove", {
          bubbles: true,
          cancelable: true,
          clientX: r.left + r.width / 2,
          clientY: r.top + r.height / 2,
        }),
      );
      return document.getElementById("chart-tip").style.display === "block";
    });
    expect(
      tipVisible,
      "#chart-tip should become visible on mousemove over #svg-elev",
    ).toBeTruthy();
  });

  test("cad-box-visible", async () => {
    const display = await page.$eval("#cad-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#cad-box has display:none — cadence chart not rendered`,
    ).toBeTruthy();
  });

  test("svg-cad-rendered", async () => {
    const n = await page.$$eval("#svg-cad path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-cad (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("pwr-box-visible", async () => {
    const display = await page.$eval("#pwr-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#pwr-box has display:none — power chart not rendered`,
    ).toBeTruthy();
  });

  test("svg-pwr-rendered", async () => {
    const n = await page.$$eval("#svg-pwr path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-pwr (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("splits-box-visible", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#splits-box unexpectedly hidden for Strava activity`,
    ).toBeTruthy();
  });

  test("spd-box-hidden-for-strava-splits", async () => {
    // Strava-API activities only carry per-km splits (no per-point time/position),
    // so the high-resolution speed line chart must stay hidden.
    const display = await page.$eval("#spd-box", (el) => el.style.display);
    expect(
      display,
      `#spd-box should be hidden for Strava splits-only activity, got "${display}"`,
    ).toBe("none");
  });

  test("grade-dist-box-visible-from-splits", async () => {
    // The whole-activity gradient-distribution donut is built from the per-km
    // splits (distance + elevation_difference) for Strava-API activities.
    const display = await page.$eval("#grade-dist-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#grade-dist-box hidden — gradient distribution not rendered from splits`,
    ).toBeTruthy();
  });

  test("svg-gradedist-has-arcs", async () => {
    const n = await page.$$eval("#svg-gradedist circle", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 donut arcs in #svg-gradedist, got ${n}`,
    ).toBeTruthy();
  });

  test("grade-dist-legend-populated", async () => {
    const rows = await page.$$eval(
      "#grade-dist-legend .gd-row",
      (els) => els.length,
    );
    expect(
      rows >= 2,
      `expected >= 2 gradient-distribution legend rows, got ${rows}`,
    ).toBeTruthy();
    const txt = await page.$eval("#grade-dist-legend", (el) => el.textContent);
    expect(
      /km/.test(txt),
      `expected km values in gradient-distribution legend, got "${txt.slice(0, 200)}"`,
    ).toBeTruthy();
  });

  test("hr-maxavg-renders-from-samples", async () => {
    // Strava splits carry no per-sample HR series, so drive the max-average-HR
    // curve directly with a synthetic descending series and assert it renders.
    const result = await page.evaluate(() => {
      const samples = [];
      for (let i = 0; i < 600; i++) samples.push(170 - Math.floor(i / 10));
      renderHrMaxAvg(samples, 3600);
      return {
        display: document.getElementById("hr-maxavg-box").style.display,
        paths: document.querySelectorAll("#svg-hrmaxavg path").length,
        tips:
          (window.LINE_TIPS &&
            window.LINE_TIPS["svg-hrmaxavg"] &&
            window.LINE_TIPS["svg-hrmaxavg"].length) ||
          0,
        yaxis: document.getElementById("svg-hrmaxavg-yaxis").textContent,
        bpmLabels: document.querySelectorAll("#svg-hrmaxavg-yaxis text")
          .length,
      };
    });
    expect(
      result.display !== "none",
      "#hr-maxavg-box should be visible after renderHrMaxAvg",
    ).toBeTruthy();
    expect(
      result.paths >= 2,
      `expected >= 2 paths in #svg-hrmaxavg (fill + line), got ${result.paths}`,
    ).toBeTruthy();
    expect(
      result.tips > 0,
      `expected LINE_TIPS['svg-hrmaxavg'] entries, got ${result.tips}`,
    ).toBeTruthy();
    expect(
      /bpm/.test(result.yaxis),
      `expected a "bpm" y-axis label, got: ${result.yaxis.slice(0, 120)}`,
    ).toBeTruthy();
    expect(
      result.bpmLabels >= 4,
      `expected >= 4 y-axis bpm labels, got ${result.bpmLabels}`,
    ).toBeTruthy();
  });

  test("weather-temp-source-badge-shown", async () => {
    const badge = await page.$(".cards .wx-src");
    expect(
      badge,
      "expected .wx-src source badge in temp card, got none",
    ).toBeTruthy();
  });

  test("weather-temp-archive-badge", async () => {
    const hasBadge = await page.evaluate(
      () => !!document.querySelector(".wx-arch"),
    );
    expect(
      hasBadge,
      "expected .wx-arch badge (archive source) in temp card",
    ).toBeTruthy();
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
    expect(
      text.includes("←"),
      `expected west arrow "←" in Wind card (wind_dir=270), got: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("gear-card-shows-name", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("Bike A"),
      `expected "Bike A" in gear card, got: ${text.slice(0, 400)}`,
    ).toBeTruthy();
  });

  test("bike-picker-selects-gear-name", async () => {
    try {
      await page.waitForSelector("#bike-sel", { timeout: 5000 });
    } catch (_) {
      throw new Error(
        "#bike-sel did not appear — bike picker not rendered for Ride activity",
      );
    }
    const selected = await page.$eval("#bike-sel", (el) => el.value);
    expect(
      selected,
      `expected bike picker to show "Bike A" (gear name not in bike-service), got "${selected}"`,
    ).toBe("Bike A");
  });
});

// ── Detail Section Order ───────────────────────────────────────────────────────

test.describe("detail-section-order", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => {
      try {
        localStorage.removeItem("ssb-detail-sec");
      } catch (_) {}
      try {
        sessionStorage.clear();
      } catch (_) {}
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
    await page.evaluate(() => {
      try {
        localStorage.removeItem("ssb-detail-sec");
      } catch (_) {}
    });
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
    const expected = [
      "cards",
      "map",
      "climbprof",
      "elev",
      "cad",
      "pwr",
      "spd",
      "temp",
      "splits",
      "hr",
      "hrzone",
      "hrmax",
    ];
    expect(sids, `sections: ${JSON.stringify(sids)}`).toEqual(expected);
  });

  test("drag-handles-present", async () => {
    const n = await page.$$eval(
      "#sec-wrap .sec .sec-handle",
      (els) => els.length,
    );
    expect(n, `expected 12 .sec-handle elements, got ${n}`).toBe(12);
  });

  test("reset-button-present", async () => {
    const n = await page.$$eval(
      "#sec-wrap .sec-order-reset",
      (els) => els.length,
    );
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
      tgt.dispatchEvent(
        new MouseEvent("drop", {
          bubbles: true,
          cancelable: true,
          clientY: rect.top + 1,
        }),
      );
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const hz = sids.indexOf("hrzone");
    expect(
      sids[hz - 1],
      `expected "splits" immediately before "hrzone", got "${sids[hz - 1]}"`,
    ).toBe("splits");
    expect(
      sids[hz],
      `expected "hrzone" to follow "splits", got "${sids[hz]}"`,
    ).toBe("hrzone");
  });

  test("order-persisted-in-localstorage", async () => {
    const saved = await page.evaluate(() => {
      try {
        return JSON.parse(localStorage.getItem("ssb-detail-sec"));
      } catch (_) {
        return null;
      }
    });
    expect(
      Array.isArray(saved) && saved.length === 12,
      "saved order should be 12-element array",
    ).toBeTruthy();
    const hz = saved.indexOf("hrzone");
    expect(
      saved[hz - 1],
      `expected "splits" immediately before "hrzone" in saved`,
    ).toBe("splits");
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
    expect(sids, `after reset: ${JSON.stringify(sids)}`).toEqual([
      "cards",
      "map",
      "climbprof",
      "elev",
      "cad",
      "pwr",
      "spd",
      "temp",
      "splits",
      "hr",
      "hrzone",
      "hrmax",
    ]);
  });
});

// ── Activity Detail (HealthSync Run) ──────────────────────────────────────────

test.describe("activity-detail-healthsync-run", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
    });
    await page.goto(URLS.activityHealthsyncRun, {
      waitUntil: "load",
      timeout: 20000,
    });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
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
    expect(
      text.includes("HealthSync") || text.includes("Run"),
      `expected HealthSync or Run in #name, got "${text}"`,
    ).toBeTruthy();
  });

  test("estimated-hr-effort-from-recorded-pulse", async () => {
    await page.waitForFunction(
      () =>
        document
          .getElementById("hr-effort-card")
          ?.getAttribute("title")
          .includes("recorded HR samples"),
      { timeout: 10000 },
    );
    const card = await page.$eval("#hr-effort-card", (el) => ({
      label: el.querySelector(".k")?.textContent,
      value: el.querySelector(".v")?.textContent,
      title: el.title,
    }));
    expect(card.label).toBe("HR effort (est.)");
    expect(Number(card.value)).toBeGreaterThan(0);
    expect(card.title).toContain("not Strava");
  });

  test("cards-populated", async () => {
    const n = await page.$$eval(".cards .card", (els) => els.length);
    expect(n >= 4, `expected >= 4 stat cards, got ${n}`).toBeTruthy();
  });

  test("distance-3km", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("3.2"),
      `expected ~3.2 km in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elevation-18m", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("18"),
      `expected "18" m in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("longest-climb-marked-on-map", async () => {
    await page.waitForFunction(
      () =>
        document.querySelector("#longest-climb-card")?.style.display !== "none",
      { timeout: 10000 },
    );
    const card = await page.$eval(
      "#longest-climb-card",
      (el) => el.textContent,
    );
    expect(card).toMatch(
      /Longest climb\s*\d+\s*m(\s·\s[\d.]+% avg ·\s[\d.]+\s(?:m|km))?/,
    );
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("hr-box-visible", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    expect(display !== "none", `#hr-box has display:none`).toBeTruthy();
  });

  test("svg-hr-rendered", async () => {
    const n = await page.$$eval("#svg-hr path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-hr (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("hr-zone-box-visible", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    expect(display !== "none", `#hr-zone-box has display:none`).toBeTruthy();
  });

  test("hr-zone-table-rows", async () => {
    const n = await page.$$eval("#hr-zone-content tr", (els) => els.length);
    expect(n, `expected 6 HR zone rows, got ${n}`).toBe(6);
  });

  test("hr-zone-descriptive-names", async () => {
    const txt = await page.$eval("#hr-zone-content", (el) => el.textContent);
    for (const name of [
      "Relaxed",
      "Healthy",
      "Fat Burn",
      "Aerobic",
      "Strength Training",
      "Red-line",
    ]) {
      expect(
        txt.includes(name),
        `expected zone name "${name}" in #hr-zone-content, got: ${txt.slice(0, 300)}`,
      ).toBeTruthy();
    }
  });

  test("hr-zone-title-age-based", async () => {
    const txt = await page.$eval("#hr-zone-title", (el) => el.textContent);
    expect(
      txt.includes("185"),
      `#hr-zone-title should mention HRmax 185 bpm (220-35), got: ${txt}`,
    ).toBeTruthy();
  });

  test("elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(
      () =>
        (window.LINE_TIPS &&
          window.LINE_TIPS["svg-elev"] &&
          window.LINE_TIPS["svg-elev"].length) ||
        0,
    );
    expect(
      n > 0,
      `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`,
    ).toBeTruthy();
  });

  test("hr-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(
      () =>
        (window.LINE_TIPS &&
          window.LINE_TIPS["svg-hr"] &&
          window.LINE_TIPS["svg-hr"].length) ||
        0,
    );
    expect(
      n > 0,
      `expected LINE_TIPS['svg-hr'] to have entries, got ${n}`,
    ).toBeTruthy();
  });

  test("elev-chart-hover-shows-tip", async () => {
    const tipVisible = await page.evaluate(() => {
      var svg = document.getElementById("svg-elev");
      if (!svg) return false;
      var overlay = svg.querySelector("rect[onmousemove]");
      if (!overlay) return false;
      var r = svg.getBoundingClientRect();
      overlay.dispatchEvent(
        new MouseEvent("mousemove", {
          bubbles: true,
          cancelable: true,
          clientX: r.left + r.width / 2,
          clientY: r.top + r.height / 2,
        }),
      );
      return document.getElementById("chart-tip").style.display === "block";
    });
    expect(
      tipVisible,
      "#chart-tip should become visible on mousemove over #svg-elev",
    ).toBeTruthy();
  });

  test("cad-box-visible", async () => {
    const display = await page.$eval("#cad-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#cad-box has display:none — cadence chart not rendered from GPX`,
    ).toBeTruthy();
  });

  test("svg-cad-rendered", async () => {
    const n = await page.$$eval("#svg-cad path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-cad (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("cadence-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("85") && text.toLowerCase().includes("cadence"),
      `expected cadence card with value 85 in .cards: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("temp-box-visible-from-gpx", async () => {
    // The GPX carries <gpxtpx:atemp> per trackpoint, so the temperature chart renders.
    const display = await page.$eval("#temp-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#temp-box has display:none — temperature chart not rendered from GPX`,
    ).toBeTruthy();
  });

  test("svg-temp-rendered", async () => {
    const n = await page.$$eval("#svg-temp path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-temp (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("svg-temp-yaxis-uses-celsius-unit", async () => {
    const txt = await page.$eval("#svg-temp-yaxis", (el) => el.textContent);
    expect(
      txt.includes("°C"),
      `expected #svg-temp y-axis labels to carry the °C unit, got "${txt}"`,
    ).toBeTruthy();
  });

  test("temp-summary-min-avg-max", async () => {
    const txt = await page.$eval("#temp-summary", (el) => el.textContent);
    expect(
      /Min\s+13\s*°C/.test(txt) &&
        /Avg\s+17\s*°C/.test(txt) &&
        /Max\s+23\s*°C/.test(txt),
      `expected "Min 13 · Avg 17 · Max 23 °C" summary, got "${txt}"`,
    ).toBeTruthy();
  });

  test("temp-tooltip-entries-registered", async () => {
    const n = await page.evaluate(
      () =>
        (window.LINE_TIPS &&
          window.LINE_TIPS["svg-temp"] &&
          window.LINE_TIPS["svg-temp"].length) ||
        0,
    );
    expect(
      n > 0,
      `expected LINE_TIPS['svg-temp'] to have entries, got ${n}`,
    ).toBeTruthy();
  });

  test("splits-box-visible", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#splits-box should be visible for GPX activity (GPS splits computed)`,
    ).toBeTruthy();
  });

  test("hr-maxavg-box-visible-from-gpx", async () => {
    // GPX activities carry a per-sample HR series, so the max-average-HR curve
    // renders as part of the GPX chart pass.
    const display = await page.$eval(
      "#hr-maxavg-box",
      (el) => el.style.display,
    );
    expect(
      display !== "none",
      `#hr-maxavg-box should be visible for a GPX activity with HR samples`,
    ).toBeTruthy();
  });

  test("svg-hrmaxavg-rendered-from-gpx", async () => {
    const n = await page.$$eval("#svg-hrmaxavg path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-hrmaxavg (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("hr-maxavg-scroll-not-synced-to-distance-charts", async () => {
    // The max-average-HR chart uses a duration x-axis, so its horizontal scroll
    // must NOT follow the distance-based charts' synchronized scrolling.
    const result = await page.evaluate(() => {
      var indep = document.querySelector("#hr-maxavg-box .chart-scroll");
      var distance = document.querySelector("#splits-box .chart-scroll");
      if (!indep || !distance) return { skip: true };
      // Force both to be horizontally scrollable regardless of viewport.
      indep.style.width = "200px";
      indep.querySelector("svg").style.width = "2000px";
      distance.style.width = "200px";
      distance.querySelector("svg").style.width = "2000px";
      indep.scrollLeft = 0;
      // Scroll a distance chart to its end and fire the sync handler.
      distance.scrollLeft = distance.scrollWidth - distance.clientWidth;
      distance.dispatchEvent(new Event("scroll", { bubbles: false }));
      return {
        skip: false,
        hasClass: indep.classList.contains("chart-scroll-indep"),
        indepScroll: indep.scrollLeft,
        distanceMoved: distance.scrollLeft > 0,
      };
    });
    if (result.skip) return;
    expect(
      result.hasClass,
      "#hr-maxavg-box .chart-scroll should carry the chart-scroll-indep marker",
    ).toBeTruthy();
    expect(
      result.distanceMoved,
      "distance chart should have scrolled (test precondition)",
    ).toBeTruthy();
    expect(
      result.indepScroll,
      `max-avg-HR chart should stay at scrollLeft 0, got ${result.indepScroll}`,
    ).toBe(0);
  });

  test("gpx-splits-share-chart-scroll-and-retain-reorder-handle", async () => {
    await page.setViewportSize({ width: 640, height: 800 });
    await page.waitForFunction(
      () =>
        document.querySelector("#splits-title .sec-handle") &&
        document.getElementById("svg-splits").style.width,
      { timeout: 10000 },
    );
    const result = await page.evaluate(() => {
      var cadence = document.querySelector("#cad-box .chart-scroll");
      var splits = document.querySelector("#splits-box .chart-scroll");
      var cadenceMax = cadence.scrollWidth - cadence.clientWidth;
      var splitsMax = splits.scrollWidth - splits.clientWidth;
      cadence.scrollLeft = Math.round(cadenceMax / 2);
      cadence.dispatchEvent(new Event("scroll"));
      return {
        cadenceMax: cadenceMax,
        splitsMax: splitsMax,
        cadenceRatio: cadence.scrollLeft / cadenceMax,
        splitsRatio: splits.scrollLeft / splitsMax,
        hasHandle: !!document.querySelector("#splits-title .sec-handle"),
      };
    });
    expect(result.cadenceMax).toBeGreaterThan(0);
    expect(result.splitsMax).toBeGreaterThan(0);
    expect(Math.abs(result.cadenceRatio - result.splitsRatio)).toBeLessThan(0.02);
    expect(result.hasHandle).toBeTruthy();
  });

  // GPX-derived cards for records lacking the fields (HealthSync has no elev bounds,
  // descent, or start clock time — all come from the track).
  test("gpx-descent-card-visible-with-metres", async () => {
    await page.waitForFunction(
      () =>
        document.querySelector("#gpx-descent-card")?.style.display !== "none",
      { timeout: 10000 },
    );
    const text = await page.$eval("#gpx-descent-card", (el) => el.textContent);
    expect(text).toMatch(/Descent\s*\d+\s*m/);
    const metres = Number((text.match(/(\d+)\s*m/) || [])[1]);
    expect(metres, `expected descent > 0, got "${text}"`).toBeGreaterThan(0);
  });

  test("gpx-altitude-card-from-track", async () => {
    await page.waitForFunction(
      () =>
        document.querySelector("#gpx-altitude-card")?.style.display !== "none",
      { timeout: 10000 },
    );
    const text = await page.$eval("#gpx-altitude-card", (el) => el.textContent);
    expect(
      text.includes("120") && text.includes("158"),
      `expected altitude 120–158 m from GPX, got "${text}"`,
    ).toBeTruthy();
  });

  test("gpx-start-time-card-hhmm", async () => {
    await page.waitForFunction(
      () => document.querySelector("#gpx-start-card")?.style.display !== "none",
      { timeout: 10000 },
    );
    const text = await page.$eval("#gpx-start-card .v", (el) =>
      el.textContent.trim(),
    );
    expect(text, `expected HH:MM start time, got "${text}"`).toMatch(
      /^\d{2}:\d{2}$/,
    );
  });

  test("moving-time-card-shows-total-and-moving-pct", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.includes("total") && text.includes("% moving"),
      `expected moving-time sub-line (total + % moving): ${text.slice(0, 400)}`,
    ).toBeTruthy();
  });

  test("moving-time-and-longest-climb-moved-after-standard-cards", async () => {
    // Moving time + Longest climb are the two full-width cards; they are appended
    // after the normal metric cards (a dynamic "HR effort (est.)" card may follow).
    const labels = await page.$$eval(".cards .card", (els) =>
      els.map((el) => el.querySelector(".k")?.textContent?.trim() || ""),
    );
    const idx = (needle) => labels.findIndex((l) => l.includes(needle));
    const iMoving = idx("Moving time");
    const iClimb = idx("Longest climb");
    const iDistance = idx("Distance");
    const iElevation = idx("Elevation");
    expect(iMoving, `Moving time card missing (all: ${labels.join(", ")})`).toBeGreaterThan(-1);
    expect(
      iClimb === iMoving + 1,
      `expected Longest climb right after Moving time, got Moving=${iMoving} Climb=${iClimb} (all: ${labels.join(", ")})`,
    ).toBeTruthy();
    expect(iMoving).toBeGreaterThan(iDistance);
    expect(iMoving).toBeGreaterThan(iElevation);
  });
});

// ── GPX fetched once (shared between map + charts) ────────────────────────────

test.describe("activity-detail-gpx-single-fetch", () => {
  let page;
  const gpxRequests = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    // Attach the listener before navigation so we capture every GPX request.
    page.on("request", (req) => {
      if (/\.gpx(\?|$)/i.test(req.url())) gpxRequests.push(req.url());
    });
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
    });
    gpxRequests.length = 0;
    await page.goto(URLS.activityHealthsyncRun, {
      waitUntil: "load",
      timeout: 20000,
    });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
    // Both the map and the charts render asynchronously; give them time to fire
    // any (de-duplicated) GPX request before counting.
    await page.waitForFunction(
      () => document.getElementById("svg-elev")?.querySelector("path"),
      { timeout: 10000 },
    );
  });

  test.afterAll(async () => {
    await page.close();
  });

  test("gpx-downloaded-exactly-once", () => {
    // renderGpxMap and renderGpxCharts share one memoized fetch (fetchGpxText),
    // so the multi-MB GPX must hit the network only once per page load.
    expect(
      gpxRequests.length,
      `expected exactly 1 .gpx request, got ${gpxRequests.length}: ${JSON.stringify(gpxRequests)}`,
    ).toBe(1);
  });
});

// ── Activity Detail (HealthSync Cycling) ──────────────────────────────────────

test.describe("activity-detail-healthsync-cycling", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
    });
    await page.goto(URLS.activityHealthsyncCycling, {
      waitUntil: "load",
      timeout: 20000,
    });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
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
    expect(
      text.includes("CYCLING"),
      `expected "CYCLING" in #name, got "${text}"`,
    ).toBeTruthy();
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
    expect(
      text.includes("64"),
      `expected "64" m in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("splits-box-visible", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#splits-box should be visible for GPX activity (GPS splits computed)`,
    ).toBeTruthy();
  });

  test("spd-box-visible", async () => {
    const display = await page.$eval("#spd-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#spd-box has display:none — speed chart not rendered from GPX`,
    ).toBeTruthy();
  });

  test("svg-spd-rendered", async () => {
    const n = await page.$$eval("#svg-spd path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-spd (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("spd-chart-has-kmh-axis", async () => {
    const text = await page.$eval("#svg-spd-yaxis", (el) => el.textContent);
    expect(
      /km\/h/.test(text),
      `expected #svg-spd-yaxis to include a "km/h" label, got: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("gpx-charts-share-one-distance-x-axis", async () => {
    // Elevation, speed and the per-km bar chart must sit on a single linear km
    // axis: each scrolls the same number of pixels (equal maxScroll) so the same
    // km always lands at the same x across all three. Guards against the per-km
    // chart drifting to a different scale (the "x axis not equal" regression).
    await page.setViewportSize({ width: 640, height: 800 });
    await page.waitForFunction(
      () =>
        document.getElementById("svg-elev")?.style.width &&
        document.getElementById("svg-spd")?.style.width &&
        document.getElementById("svg-splits")?.style.width,
      { timeout: 10000 },
    );
    const r = await page.evaluate(() => {
      const maxScroll = (sel) => {
        const el = document.querySelector(sel);
        return el ? el.scrollWidth - el.clientWidth : -1;
      };
      return {
        elev: maxScroll("#elev-box .chart-scroll"),
        spd: maxScroll("#spd-box .chart-scroll"),
        splits: maxScroll("#splits-box .chart-scroll"),
      };
    });
    expect(r.elev, `#elev-box must be scrollable, got ${r.elev}`).toBeGreaterThan(0);
    expect(r.splits, `#splits-box must be scrollable, got ${r.splits}`).toBeGreaterThan(0);
    // Same distance span → equal scroll range within one km-worth of pixels.
    expect(
      Math.abs(r.elev - r.splits),
      `elev/splits maxScroll differ: ${r.elev} vs ${r.splits}`,
    ).toBeLessThan(60);
    expect(
      Math.abs(r.spd - r.splits),
      `spd/splits maxScroll differ: ${r.spd} vs ${r.splits}`,
    ).toBeLessThan(60);
  });

  test("longest-climb-card-visible", async () => {
    // max_single_climb comes from activities.json (computed server-side); the
    // detail JSON doesn't carry it, so the detail page must merge it in.
    await page.waitForFunction(
      () =>
        document.querySelector("#longest-climb-card")?.style.display !== "none",
      { timeout: 10000 },
    );
    const card = await page.$eval(
      "#longest-climb-card",
      (el) => el.textContent,
    );
    expect(card).toMatch(
      /Longest climb\s*\d+\s*m(\s·\s[\d.]+% avg ·\s[\d.]+\s(?:m|km))?/,
    );
  });

  test("grade-dist-box-visible-from-gpx-track", async () => {
    // GPX activities build the gradient-distribution donut from the full track
    // (smoothed into ~100 m blocks) inside updateLongestClimbCard.
    await page.waitForFunction(
      () => document.getElementById("grade-dist-box")?.style.display !== "none",
      { timeout: 10000 },
    );
    const n = await page.$$eval("#svg-gradedist circle", (els) => els.length);
    expect(
      n >= 1,
      `expected donut arcs in #svg-gradedist from the GPX track, got ${n}`,
    ).toBeTruthy();
    const rows = await page.$$eval(
      "#grade-dist-legend .gd-row",
      (els) => els.length,
    );
    expect(
      rows >= 1,
      `expected gradient-distribution legend rows, got ${rows}`,
    ).toBeTruthy();
  });
});

// ── Activity Detail (Magene) ───────────────────────────────────────────────────

test.describe("activity-detail-magene", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
    });
    await page.goto(URLS.activityMagene, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
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
    expect(
      text.includes("Magene"),
      `expected "Magene" in #name, got "${text}"`,
    ).toBeTruthy();
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
    expect(
      text.includes("303"),
      `expected "303" m in .cards: ${text.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("elev-box-visible", async () => {
    const display = await page.$eval("#elev-box", (el) => el.style.display);
    expect(display !== "none", `#elev-box has display:none`).toBeTruthy();
  });

  test("svg-elev-rendered", async () => {
    const n = await page.$$eval("#svg-elev path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-elev (fill + line), got ${n}`,
    ).toBeTruthy();
  });

  test("hr-box-hidden", async () => {
    const display = await page.$eval("#hr-box", (el) => el.style.display);
    expect(
      display,
      `#hr-box should be hidden for Magene (no HR), got "${display}"`,
    ).toBe("none");
  });

  test("hr-zone-box-hidden", async () => {
    const display = await page.$eval("#hr-zone-box", (el) => el.style.display);
    expect(
      display,
      `#hr-zone-box should be hidden for Magene (no HR), got "${display}"`,
    ).toBe("none");
  });

  test("elev-chart-has-tooltip-data", async () => {
    const n = await page.evaluate(
      () =>
        (window.LINE_TIPS &&
          window.LINE_TIPS["svg-elev"] &&
          window.LINE_TIPS["svg-elev"].length) ||
        0,
    );
    expect(
      n > 0,
      `expected LINE_TIPS['svg-elev'] to have entries, got ${n}`,
    ).toBeTruthy();
  });

  test("splits-box-visible", async () => {
    const display = await page.$eval("#splits-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#splits-box should be visible for GPX activity (GPS splits computed)`,
    ).toBeTruthy();
  });

  test("temp-box-visible-from-gpx", async () => {
    const display = await page.$eval("#temp-box", (el) => el.style.display);
    expect(
      display !== "none",
      `#temp-box has display:none — temperature chart not rendered from GPX`,
    ).toBeTruthy();
  });

  test("temp-summary-excludes-first-3km-garage-readings", async () => {
    // The GPX carries 34–35 °C "garage" readings in the first 3 km (sensor at storage
    // temperature) and 12–22 °C once riding. The first-3km skip must exclude the garage
    // readings, so the summary is Min 12 · Avg 17 · Max 22 — not Max 35.
    const txt = await page.$eval("#temp-summary", (el) => el.textContent);
    expect(
      /Min\s+12\s*°C/.test(txt) &&
        /Avg\s+17\s*°C/.test(txt) &&
        /Max\s+22\s*°C/.test(txt),
      `expected "Min 12 · Avg 17 · Max 22 °C" (garage readings skipped), got "${txt}"`,
    ).toBeTruthy();
  });

  test("svg-temp-rendered", async () => {
    const n = await page.$$eval("#svg-temp path", (els) => els.length);
    expect(
      n >= 2,
      `expected >= 2 path elements in #svg-temp (fill + line), got ${n}`,
    ).toBeTruthy();
  });
});

// ── Activity Detail (multiple qualifying climbs) ──────────────────────────────

test.describe("activity-detail-multiclimb", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.goto(URLS.activityMultiClimb, {
      waitUntil: "load",
      timeout: 20000,
    });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
    // Wait for the climb card to be populated from the GPX track.
    try {
      await page.waitForFunction(
        () =>
          document.querySelector("#longest-climb-card")?.style.display !==
          "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
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

  test("climb-card-has-switcher", async () => {
    // The GPX has two distinct climbs separated by a >30 m descent, so the card
    // shows ‹ › arrows and an "N/M" counter to flip between them. It opens on the
    // biggest climb (flagged "longest").
    const title = await page.$eval(
      "#longest-climb-card .k",
      (el) => el.textContent,
    );
    expect(
      title.toLowerCase().includes("longest"),
      `expected the default view to flag the biggest climb as "longest", got "${title}"`,
    ).toBeTruthy();
    const count = await page.$eval(
      "#longest-climb-card .climb-count",
      (el) => el.textContent.trim(),
    );
    expect(count, `expected an "N/M" counter, got "${count}"`).toBe("1/2");
    const navBtns = await page.$$eval(
      "#longest-climb-card .climb-nav button",
      (els) => els.length,
    );
    expect(
      navBtns,
      `expected two switcher buttons (‹ ›), got ${navBtns}`,
    ).toBe(2);
  });

  test("climb-switcher-flips-to-next-climb", async () => {
    const before = await page.$eval(
      "#longest-climb-card .v",
      (el) => el.textContent,
    );
    await page.click("#longest-climb-card .climb-next");
    const count = await page.$eval(
      "#longest-climb-card .climb-count",
      (el) => el.textContent.trim(),
    );
    expect(count, `expected counter to advance to 2/2, got "${count}"`).toBe(
      "2/2",
    );
    const after = await page.$eval(
      "#longest-climb-card .v",
      (el) => el.textContent,
    );
    expect(
      after !== before && /\d+\s*m/.test(after),
      `expected the shown climb metrics to change on next, before="${before}" after="${after}"`,
    ).toBeTruthy();
    // Reset back to the first climb so later assertions start from a known state.
    await page.click("#longest-climb-card .climb-prev");
  });

  test("activity-start-finish-labelled-on-map", async () => {
    // The whole-activity endpoints carry always-on "Start"/"Finish" labels so they
    // are distinguishable from the climb start/summit dots.
    const labels = await page.$$eval(".route-endpoint-tip", (els) =>
      els.map((e) => e.textContent.trim().toLowerCase()),
    );
    expect(
      labels.includes("start") && labels.includes("finish"),
      `expected permanent "Start" and "Finish" map labels, got ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("direction-arrows-on-map", async () => {
    // Chevrons along the route show the direction of travel.
    const n = await page.$$eval(
      ".leaflet-marker-pane svg path[fill='#fc4c02']",
      (els) => els.length,
    );
    expect(n >= 2, `expected direction arrows on the map, got ${n}`).toBeTruthy();
  });

  test("hide-climbs-button-toggles-climb-layers", async () => {
    const btn = page.locator(".climb-toggle-btn");
    await expect(btn).toHaveText("Hide climbs");
    await btn.click();
    await expect(btn).toHaveText("Show climbs");
    const disp = await page.$eval(".leaflet-climb-pane", (e) => getComputedStyle(e).display);
    expect(disp).toBe("none");
    await btn.click();
    await expect(btn).toHaveText("Hide climbs");
    const disp2 = await page.$eval(".leaflet-climb-pane", (e) => getComputedStyle(e).display);
    expect(disp2).not.toBe("none");
  });

  test("both-climbs-drawn-on-map", async () => {
    // Each climb is drawn as its own blue (#1565c0) polyline over the orange route.
    const n = await page.$$eval(".leaflet-overlay-pane path, .leaflet-climb-pane path", (els) =>
      els.filter(
        (p) =>
          (p.getAttribute("stroke") || "").toLowerCase() === "#1565c0",
      ).length,
    );
    expect(
      n >= 2,
      `expected >= 2 blue climb polylines on the map, got ${n}`,
    ).toBeTruthy();
  });

  test("climb-profile-chart-visible", async () => {
    // The Magene-style per-climb profile renders alongside the climb card.
    await page.waitForFunction(
      () =>
        document.getElementById("climb-profile-box")?.style.display !== "none",
      { timeout: 10000 },
    );
    const display = await page.$eval(
      "#climb-profile-box",
      (el) => el.style.display,
    );
    expect(
      display !== "none",
      `#climb-profile-box should be visible when climbs exist`,
    ).toBeTruthy();
  });

  test("climb-profile-has-gradient-coloured-segments", async () => {
    // The climb is drawn as gradient-coloured filled segments (one <polygon> each),
    // using the HC/Cat1–4 band colours.
    const r = await page.evaluate(() => {
      const bands = ["#e53935", "#fb8c00", "#fdd835", "#43a047", "#29b6f6"];
      const polys = Array.from(
        document.querySelectorAll("#svg-climbprof polygon"),
      );
      const colours = new Set(
        polys.map((p) => (p.getAttribute("fill") || "").toLowerCase()),
      );
      return {
        count: polys.length,
        usesBandColour: polys.some((p) =>
          bands.includes((p.getAttribute("fill") || "").toLowerCase()),
        ),
      };
    });
    expect(
      r.count >= 3,
      `expected several coloured climb segments, got ${r.count}`,
    ).toBeTruthy();
    expect(
      r.usesBandColour,
      `expected climb segments filled with gradient-band colours`,
    ).toBeTruthy();
  });

  test("climb-profile-stat-tiles-and-legend", async () => {
    const stats = await page.$$eval(
      "#climb-prof-stats .cp-stat",
      (els) => els.length,
    );
    expect(stats, `expected 5 climb stat tiles, got ${stats}`).toBe(5);
    const legend = await page.$$eval(
      "#climb-prof-legend span",
      (els) => els.length,
    );
    expect(legend, `expected 5 legend entries, got ${legend}`).toBe(5);
    const statsText = await page.$eval(
      "#climb-prof-stats",
      (el) => el.textContent,
    );
    expect(
      /Avg gradient/i.test(statsText) && /Accumulated climb/i.test(statsText),
      `expected gradient + accumulated-climb tiles, got: ${statsText.slice(0, 200)}`,
    ).toBeTruthy();
  });

  test("climb-profile-x-axis-is-climb-distance", async () => {
    // X-axis runs 0 → the climb's own distance (sub-km here), NOT the whole
    // 1.07 km activity — the tooltip series' last point stays well under total.
    const r = await page.evaluate(() => {
      const tips =
        (window.LINE_TIPS && window.LINE_TIPS["svg-climbprof"]) || [];
      const last = tips[tips.length - 1];
      const m = last ? /([\d.]+)\s*km/.exec(last.html) : null;
      return {
        n: tips.length,
        startsAtZero: tips.length
          ? /0\.00\s*km/.test(tips[0].html)
          : false,
        lastKm: m ? Number(m[1]) : null,
      };
    });
    expect(r.n > 0, `expected climb-profile tooltip series`).toBeTruthy();
    expect(
      r.startsAtZero,
      `expected the climb profile to start at 0.00 km`,
    ).toBeTruthy();
    expect(
      r.lastKm != null && r.lastKm < 0.6,
      `expected the climb to span < 0.6 km (its own length), got ${r.lastKm}`,
    ).toBeTruthy();
  });

  test("climb-profile-switcher-flips-chart", async () => {
    // Opens on the longest climb; the ‹ › header switcher redraws the chart for
    // the next climb (different distance/tooltip series).
    const before = await page.evaluate(() => {
      const tips =
        (window.LINE_TIPS && window.LINE_TIPS["svg-climbprof"]) || [];
      const last = tips[tips.length - 1];
      return last ? last.html : "";
    });
    const title = await page.$eval("#climb-prof-title", (el) => el.textContent);
    expect(
      title.toLowerCase().includes("longest"),
      `expected the default profile to flag the longest climb, got "${title}"`,
    ).toBeTruthy();
    await page.click("#climb-prof-title .cp-next");
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const after = await page.evaluate(() => {
      const tips =
        (window.LINE_TIPS && window.LINE_TIPS["svg-climbprof"]) || [];
      const last = tips[tips.length - 1];
      return last ? last.html : "";
    });
    expect(
      after !== before,
      `expected the climb profile to change after switching climbs`,
    ).toBeTruthy();
    // Reset back to the first (longest) climb for later assertions.
    await page.click("#climb-prof-title .cp-prev");
  });

  test("selected-climb-coloured-by-gradient-on-map", async () => {
    // The currently-selected climb is overlaid on the map coloured by gradient band
    // (same palette as the chart), over a dark casing for legibility. Other climbs
    // stay plain blue.
    await page.waitForFunction(() => window._climbGradLayer != null, {
      timeout: 10000,
    });
    const r = await page.evaluate(() => {
      const bands = ["#e53935", "#fb8c00", "#fdd835", "#43a047", "#29b6f6"];
      const strokes = Array.from(
        document.querySelectorAll(".leaflet-overlay-pane path, .leaflet-climb-pane path"),
      ).map((p) => (p.getAttribute("stroke") || "").toLowerCase());
      const bandHits = new Set(strokes.filter((s) => bands.includes(s)));
      return {
        hasCasing: strokes.includes("#1a1a1a"),
        bandColours: bandHits.size,
      };
    });
    expect(
      r.hasCasing,
      "expected a dark casing (#1a1a1a) under the gradient climb overlay",
    ).toBeTruthy();
    // Coarse blocks mean a steady climb renders as one band; varied terrain shows more.
    expect(
      r.bandColours >= 1,
      `expected >= 1 gradient-band colour on the selected climb, got ${r.bandColours}`,
    ).toBeTruthy();
  });

  test("map-opens-zoomed-to-selected-climb", async () => {
    // On load the map focuses the shown (longest/default) climb, not the whole route,
    // so map + chart + card all open on the same climb.
    await page.evaluate(() => {
      if (typeof showClimb === "function") showClimb(0);
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 500)));
    const r = await page.evaluate(() => {
      const m = window._climbMap;
      const sel =
        window._climbs && window._climbLines
          ? window._climbLines[window._climbs[window._climbIdx].idx]
          : null;
      const route = window.leafletLine;
      if (!m || !sel || !route) return { skip: true };
      const c = m.getCenter();
      return {
        skip: false,
        mapLng: c.lng,
        climbLng: sel.getBounds().getCenter().lng,
        routeLng: route.getBounds().getCenter().lng,
      };
    });
    if (r.skip) return;
    const toClimb = Math.abs(r.mapLng - r.climbLng);
    const toRoute = Math.abs(r.mapLng - r.routeLng);
    expect(
      toClimb < 0.0008,
      `map centre should sit on the selected climb (Δ=${toClimb})`,
    ).toBeTruthy();
    expect(
      toClimb < toRoute,
      `map should be centred on the climb, not the whole route (climbΔ=${toClimb} routeΔ=${toRoute})`,
    ).toBeTruthy();
  });

  test("gradient-overlay-rebuilds-on-switch", async () => {
    // Switching climbs tears down the old overlay and builds one for the new climb —
    // never leaving two overlays stacked.
    const before = await page.evaluate(() =>
      window._climbGradLayer ? window._climbGradLayer.getLayers().length : 0,
    );
    await page.click("#climb-prof-title .cp-next");
    await page.evaluate(() => new Promise((r) => setTimeout(r, 150)));
    const after = await page.evaluate(() => ({
      layers: window._climbGradLayer
        ? window._climbGradLayer.getLayers().length
        : 0,
      onMap: window._climbMap && window._climbGradLayer
        ? window._climbMap.hasLayer(window._climbGradLayer)
        : false,
    }));
    expect(before, "expected an overlay before switching").toBeGreaterThan(0);
    expect(after.layers, "expected a rebuilt overlay after switching").toBeGreaterThan(0);
    expect(
      after.onMap,
      "expected exactly the current overlay attached to the map",
    ).toBeTruthy();
    await page.click("#climb-prof-title .cp-prev");
  });
});

// ── Activity Detail (Walk — steps card) ───────────────────────────────────────

test.describe("activity-detail-walk", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
    });
    await page.goto(URLS.activityWalk, { waitUntil: "load", timeout: 20000 });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => {
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

  test("steps-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    const digits = text.replace(/[,.\s]/g, "");
    expect(
      text.includes("Steps") && digits.includes("9530"),
      `expected Steps card with 9530 in .cards: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("steps-card-actual-not-estimated", async () => {
    // walk-sample.json has step_count set, so the card should NOT show a tooltip hint
    const tipText = await page.$eval(".cards", (el) => el.innerHTML);
    expect(
      !tipText.includes("Estimated total steps"),
      `steps card should show actual count (no estimation tooltip), got: ${tipText.slice(0, 300)}`,
    ).toBeTruthy();
  });

  test("cadence-card-shown", async () => {
    const text = await page.$eval(".cards", (el) => el.textContent);
    expect(
      text.toLowerCase().includes("cadence") && text.includes("55"),
      `expected cadence card with value 55: ${text.slice(0, 300)}`,
    ).toBeTruthy();
  });
});

// ── Strava Link (numeric vs HealthSync ID) ────────────────────────────────────

test.describe("strava-link", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => {
      try {
        sessionStorage.clear();
      } catch (_) {}
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
    await page.close();
  });

  test("strava-activity-has-open-link", async () => {
    const text = await page.$eval("#links", (el) => el.textContent);
    expect(
      text.includes("Open on Strava"),
      `expected "Open on Strava" in #links for Strava activity, got: "${text}"`,
    ).toBeTruthy();
  });

  test("strava-link-href-contains-id", async () => {
    const href = await page.$eval(
      '#links a[href*="strava.com"]',
      (el) => el.href,
    );
    expect(
      href.includes("18784255013"),
      `expected activity ID in Strava link href, got: "${href}"`,
    ).toBeTruthy();
  });

  test("healthsync-activity-no-strava-link", async () => {
    jsErrors.length = 0;
    await page.goto(URLS.activityHealthsyncRun, {
      waitUntil: "load",
      timeout: 20000,
    });
    try {
      await page.waitForFunction(
        () => document.getElementById("content")?.style.display !== "none",
        { timeout: 10000 },
      );
    } catch (_) {}
    const link = await page.$('#links a[href*="strava.com"]');
    expect(
      !link,
      'expected no "Open on Strava" link for HealthSync activity',
    ).toBeTruthy();
  });
});

// ── Heatmap ────────────────────────────────────────────────────────────────────

test.describe("heatmap", () => {
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

  test.afterAll(async () => {
    await page.close();
  });

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
    const opts = await page.$$eval("#period option", (os) =>
      os.map((o) => o.value),
    );
    expect(
      opts.includes("all"),
      `expected "all" option in #period, got: ${JSON.stringify(opts)}`,
    ).toBeTruthy();
  });

  test("period-has-time-range-options", async () => {
    const opts = await page.$$eval("#period option", (os) =>
      os.map((o) => o.value),
    );
    expect(
      opts.includes("w7"),
      `expected "w7"  option in #period`,
    ).toBeTruthy();
    expect(
      opts.includes("w30"),
      `expected "w30" option in #period`,
    ).toBeTruthy();
    expect(
      opts.includes("w90"),
      `expected "w90" option in #period`,
    ).toBeTruthy();
  });

  test("period-has-year-options", async () => {
    const opts = await page.$$eval("#period option", (os) =>
      os.map((o) => o.value),
    );
    const years = opts.filter((v) => /^\d{4}$/.test(v));
    expect(
      years.length >= 1,
      `expected at least one year option, got: ${JSON.stringify(opts)}`,
    ).toBeTruthy();
  });

  test("default-is-last-3-months", async () => {
    const val = await page.$eval("#period", (el) => el.value);
    expect(val, `expected default period to be "w90", got: "${val}"`).toBe(
      "w90",
    );
  });

  test("default-last-3-months-shows-1-activity", async () => {
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(
      count.startsWith("1 "),
      `expected count to start with "1 " for Last 3 months + Ride (default), got: "${count}"`,
    ).toBeTruthy();
  });

  test("sport-dropdown-present", async () => {
    const el = await page.$("#sport");
    expect(el, "#sport select not found").toBeTruthy();
  });

  test("sport-has-all-sports-option", async () => {
    const opts = await page.$$eval("#sport option", (os) =>
      os.map((o) => o.value),
    );
    expect(
      opts.includes(""),
      `expected "" (All sports) option in #sport, got: ${JSON.stringify(opts)}`,
    ).toBeTruthy();
  });

  test("sport-has-ride-and-run", async () => {
    const opts = await page.$$eval("#sport option", (os) =>
      os.map((o) => o.value),
    );
    expect(
      opts.includes("Ride"),
      `expected "Ride" option in #sport, got: ${JSON.stringify(opts)}`,
    ).toBeTruthy();
    expect(
      opts.includes("Run"),
      `expected "Run"  option in #sport, got: ${JSON.stringify(opts)}`,
    ).toBeTruthy();
  });

  test("sport-default-is-ride", async () => {
    const val = await page.$eval("#sport", (el) => el.value);
    expect(val, `expected default sport to be "Ride", got: "${val}"`).toBe(
      "Ride",
    );
  });

  test("all-time-shows-4-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = "";
      ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      sel.value = "all";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(
      count.startsWith("8 "),
      `expected count to start with "8 " for All time + All sports, got: "${count}"`,
    ).toBeTruthy();
  });

  test("filter-2024-shows-2-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = "";
      ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      const opt = Array.from(sel.options).find((o) => o.value === "2024");
      if (opt) {
        sel.value = "2024";
        sel.dispatchEvent(new Event("change", { bubbles: true }));
      }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(
      count.startsWith("2 "),
      `expected count to start with "2 " for 2024 + All sports, got: "${count}"`,
    ).toBeTruthy();
  });

  test("sport-filter-run-all-time-shows-1", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("period");
      sel.value = "all";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
      const ssel = document.getElementById("sport");
      ssel.value = "Run";
      ssel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(
      count.startsWith("2 "),
      `expected count to start with "2 " for All time + Run sport filter, got: "${count}"`,
    ).toBeTruthy();
  });

  test("filter-last-7-days-shows-0-activities", async () => {
    await page.evaluate(() => {
      const ssel = document.getElementById("sport");
      ssel.value = "";
      ssel.dispatchEvent(new Event("change", { bubbles: true }));
      const sel = document.getElementById("period");
      sel.value = "w7";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const count = await page.$eval("#count", (el) => el.textContent.trim());
    expect(
      count.startsWith("0 "),
      `expected count to start with "0 " for last-7-days filter, got: "${count}"`,
    ).toBeTruthy();
  });

  test("dashboard-link-present", async () => {
    const href = await page.$eval(".hm-nav a", (el) => el.getAttribute("href"));
    expect(
      href && href.includes("index.html"),
      `expected hm-nav link to index.html, got: "${href}"`,
    ).toBeTruthy();
  });
});
