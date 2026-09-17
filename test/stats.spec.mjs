import { test, expect } from "@playwright/test";
import { URLS, CGI } from "./test-urls.mjs";

// helper: find a record card by label substring and return its .rv text
async function getRecVal(page, labelFrag) {
  return page.evaluate((frag) => {
    for (const rec of document.querySelectorAll("#recs .rec")) {
      if (rec.querySelector(".rl")?.textContent.includes(frag))
        return rec.querySelector(".rv")?.textContent || "";
    }
    return null;
  }, labelFrag);
}

// helper: find a record card by label substring and return its link href (or null)
async function getRecLink(page, labelFrag) {
  return page.evaluate((frag) => {
    for (const rec of document.querySelectorAll("#recs .rec")) {
      if (rec.querySelector(".rl")?.textContent.includes(frag)) {
        const a = rec.querySelector("a[href]");
        return a ? a.getAttribute("href") : null;
      }
    }
    return null;
  }, labelFrag);
}

// helper: fire the _gf() call from a period-record link and return the parsed filter object
async function getFilterFromRecLink(page, labelFrag) {
  const json = await page.evaluate((frag) => {
    for (const rec of document.querySelectorAll("#recs .rec")) {
      if (rec.querySelector(".rl")?.textContent.includes(frag)) {
        const a = rec.querySelector("a[href='index.html']");
        if (a) {
          const oc = a.getAttribute("onclick") || "";
          const m = oc.match(/_gf\(([^)]+)\)/);
          // eslint-disable-next-line no-eval
          if (m) eval("window._gf(" + m[1] + ")");
        }
        break;
      }
    }
    return sessionStorage.getItem("activityFilter");
  }, labelFrag);
  return json ? JSON.parse(json) : null;
}

// ── Stats ──────────────────────────────────────────────────────────────────────

test.describe("stats", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("kpi-activities-16", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    expect(val, `expected KPI Activities="18", got "${val}"`).toBe("18");
  });

  test("kpi-distance-824", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Distance"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    expect(val && val.includes("941"), `expected "941" in distance KPI, got "${val}"`).toBeTruthy();
  });

  test("records-longest-102.4", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    expect(text.includes("102.4"), `expected "102.4" in .recs: ${text}`).toBeTruthy();
  });

  test("records-elevation-1320", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    expect(
      text.includes("1320") || text.includes("1 320"),
      `expected "1320" in .recs: ${text}`,
    ).toBeTruthy();
  });

  test("records-fastest-25.0", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    expect(text.includes("25.0"), `expected "25.0" km/h in .recs: ${text}`).toBeTruthy();
  });

  test("records-max-speed-70.0", async () => {
    const text = await page.$eval(".recs", (el) => el.textContent);
    expect(text.includes("70.0"), `expected "70.0" km/h in .recs (max speed): ${text}`).toBeTruthy();
  });

  test("year-table-has-row", async () => {
    const n = await page.$$eval("#yearTable tbody tr", (rows) => rows.length);
    expect(n >= 1, `expected year table rows, got ${n}`).toBeTruthy();
  });

  test("year-table-one-highlighted", async () => {
    const n = await page.$$eval("#yearTable tr.hi", (rows) => rows.length);
    expect(n, `expected exactly 1 highlighted year row, got ${n}`).toBe(1);
  });

  test("monthly-chart-bars", async () => {
    const n = await page.$$eval("#moSvg rect", (els) => els.length);
    expect(n > 0, `expected bars in #moSvg, got ${n}`).toBeTruthy();
  });

  test("sport-table-sports", async () => {
    const n = await page.$$eval("#sportTable tbody tr", (rows) => rows.length);
    expect(n >= 4, `expected >= 4 sport rows for 2026, got ${n}`).toBeTruthy();
  });

  test("all-years-meta-shows-period", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("yearSel");
      sel.value = "all";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const meta = await page.$eval("#meta", (el) => el.textContent);
    expect(
      /\d+\s+year|\d+\s+month|\d+\s+day/.test(meta),
      `expected period in #meta when all years selected, got: "${meta}"`,
    ).toBeTruthy();
  });

  test("all-years-sport-subtitle-shows-period", async () => {
    const subtitle = await page.$eval("#sportSubtitle", (el) => el.textContent);
    expect(
      subtitle.includes("all time") && /\d+\s+year|\d+\s+month|\d+\s+day/.test(subtitle),
      `expected "all time · <period>" in #sportSubtitle, got: "${subtitle}"`,
    ).toBeTruthy();
  });

  test("cmp-table-yoy-header", async () => {
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector("#cmpTable th", { timeout: 10000 }); } catch (_) {}
    const headers = await page.$$eval("#cmpTable th", (ths) => ths.map((t) => t.textContent.trim()));
    expect(headers.includes("YoY"), `expected "YoY" header in cmpTable, got: ${JSON.stringify(headers)}`).toBeTruthy();
  });

  test("cmp-table-yoy-cell-format", async () => {
    const cells = await page.$$eval("#cmpTable td", (tds) => tds.map((t) => t.textContent.trim()));
    const yoy = cells.find((c) => /^[+\-]\d/.test(c) && c.includes("km"));
    expect(yoy, `expected a YoY cell like "+N km / +N%" in cmpTable, got cells: ${JSON.stringify(cells.slice(0,10))}`).toBeTruthy();
  });

  test("cmp-table-total-row", async () => {
    const rows = await page.$$eval("#cmpTable tbody tr", (trs) => trs.map((r) => r.textContent.trim()));
    const totRow = rows.find((r) => r.startsWith("Total"));
    expect(totRow, `expected a "Total" row in cmpTable, got rows: ${JSON.stringify(rows.slice(-3))}`).toBeTruthy();
  });
});

// ── Stats Sport Filter ─────────────────────────────────────────────────────────

test.describe("stats-sport-filter", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("default-sport-ride", async () => {
    const sport = await page.$eval("#sportSel", (el) => el.value);
    expect(sport, `expected default sport "Ride", got "${sport}"`).toBe("Ride");
  });

  test("kpi-activities-days-subtitle", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".s")?.textContent.trim() || null;
      }
      return null;
    });
    expect(val && /^18 \/ \d+ days$/.test(val), `expected Activities subtitle to match "18 / N days", got "${val}"`).toBeTruthy();
  });

  test("kpi-activities-tooltip", async () => {
    const cardHandle = await page.evaluateHandle(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities")) return k;
      }
      return null;
    });
    expect(cardHandle, "Activities KPI card not found").toBeTruthy();
    await cardHandle.hover();
    await page.evaluate(() => new Promise(function(r){ setTimeout(r, 100); }));
    const tipText = await page.$eval("#tip", function(el){ return el.textContent; });
    expect(tipText && tipText.includes("active days"), `expected tooltip to mention "active days", got "${tipText}"`).toBeTruthy();
    await page.mouse.move(0, 0);
  });

  test("switch-to-run-updates-kpis", async () => {
    const rideCounts = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const runOpt = Array.from(sel.options).find((o) => o.value === "Run");
      if (runOpt) { sel.value = "Run"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((resolve) => { setTimeout(resolve, 300); }));
    const runCounts = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Activities"))
          return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    expect(runCounts !== null, "Activities KPI not found after switching to Run").toBeTruthy();
    expect(runCounts).not.toBe(rideCounts);
  });

  test("records-change-on-sport-switch", async () => {
    const val = await getRecVal(page, "Longest distance");
    expect(val, "Longest distance record not found after switching to Run").toBeTruthy();
    expect(!val.includes("102.4"), `Longest distance should show Run value, not Ride 102.4 km — got: "${val}"`).toBeTruthy();
    expect(val.includes("km"), `expected "km" in Longest distance after sport switch, got: "${val}"`).toBeTruthy();
  });

  test("records-subtitle-shows-sport", async () => {
    const subtitle = await page.$eval("#recsSubtitle", (el) => el.textContent);
    expect(subtitle.includes("Run"), `expected "Run" in records subtitle after switching to Run, got: "${subtitle}"`).toBeTruthy();
  });

  test("records-render-after-sport-switch", async () => {
    const recsEl = await page.$(".recs");
    expect(recsEl, ".recs element not found after sport switch").toBeTruthy();
  });

  test("all-sports-shows-sport-table", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const allOpt = Array.from(sel.options).find((o) => o.value === "All" || o.value === "");
      if (allOpt) { sel.value = allOpt.value; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((resolve) => { setTimeout(resolve, 300); }));
    const sportRows = await page.$$eval("#sportTable tbody tr", (rows) => rows.length);
    expect(sportRows >= 2, `expected >= 2 rows in #sportTable with All sports, got ${sportRows}`).toBeTruthy();
  });

  test("all-sports-steps-kpi-shown", async () => {
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Steps")) return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    const digits = val ? val.replace(/[,.\s]/g, "") : "";
    expect(val && digits.includes("9530"), `expected Steps KPI with ~9530 when All sports selected, got "${val}"`).toBeTruthy();
  });

  test("walk-sport-steps-kpi-shown", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find(o => o.value === "Walk");
      if (opt) { sel.value = "Walk"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise(r => setTimeout(r, 300)));
    const val = await page.evaluate(() => {
      for (const k of document.querySelectorAll(".kpi")) {
        if (k.querySelector(".k")?.textContent.includes("Steps")) return k.querySelector(".v")?.textContent.trim();
      }
      return null;
    });
    const digitsW = val ? val.replace(/[,.\s]/g, "") : "";
    expect(val && digitsW.includes("9530"), `expected Steps KPI with ~9530 when Walk selected, got "${val}"`).toBeTruthy();
  });

  test("ride-sport-no-steps-kpi", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find(o => o.value === "Ride");
      if (opt) { sel.value = "Ride"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise(r => setTimeout(r, 300)));
    const found = await page.evaluate(() => {
      return Array.from(document.querySelectorAll(".kpi"))
        .some(k => k.querySelector(".k")?.textContent.includes("Steps"));
    });
    expect(!found, "Steps KPI should not appear when Ride sport is selected").toBeTruthy();
  });
});

// ── Stats Records ──────────────────────────────────────────────────────────────

test.describe("stats-records", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("all-expected-labels-present", async () => {
    const EXPECTED_LABELS = [
      "Longest distance", "Longest ride", "Most elevation", "Fastest avg speed",
      "Best week", "Best month", "Most activities", "Longest streak",
    ];
    const labels = await page.$$eval("#recs .rec .rl", (els) => els.map((el) => el.textContent));
    for (const frag of EXPECTED_LABELS) {
      expect(
        labels.some((l) => l.includes(frag)),
        `expected "${frag}" in #recs record labels, got: ${JSON.stringify(labels)}`,
      ).toBeTruthy();
    }
  });

  test("longest-distance-is-102.4km", async () => {
    const val = await getRecVal(page, "Longest distance");
    expect(val && val.includes("102.4"), `expected "102.4" in Longest distance, got: "${val}"`).toBeTruthy();
  });

  test("most-elevation-is-1320m", async () => {
    const val = await getRecVal(page, "Most elevation");
    expect(val && val.includes("1 320"), `expected "1 320" in Most elevation, got: "${val}"`).toBeTruthy();
  });

  test("fastest-speed-has-kmh", async () => {
    const val = await getRecVal(page, "Fastest avg speed");
    expect(val && val.includes("km/h"), `expected "km/h" in Fastest avg speed, got: "${val}"`).toBeTruthy();
  });

  test("longest-ride-has-duration", async () => {
    const val = await getRecVal(page, "Longest ride");
    expect(val && val.match(/\d+h\s+\d+m/), `expected "Xh Ym" in Longest ride, got: "${val}"`).toBeTruthy();
  });

  test("link-present-for-longest-distance", async () => {
    const href = await getRecLink(page, "Longest distance");
    expect(href && href.includes("activity.html?id="), `expected activity link for "Longest distance", got: ${href}`).toBeTruthy();
  });

  test("link-present-for-longest-ride", async () => {
    const href = await getRecLink(page, "Longest ride");
    expect(href && href.includes("activity.html?id="), `expected activity link for "Longest ride", got: ${href}`).toBeTruthy();
  });

  test("link-present-for-most-elevation", async () => {
    const href = await getRecLink(page, "Most elevation");
    expect(href && href.includes("activity.html?id="), `expected activity link for "Most elevation", got: ${href}`).toBeTruthy();
  });

  test("link-present-for-fastest-avg-speed", async () => {
    const href = await getRecLink(page, "Fastest avg speed");
    expect(href && href.includes("activity.html?id="), `expected activity link for "Fastest avg speed", got: ${href}`).toBeTruthy();
  });

  test("filter-link-for-best-week", async () => {
    const href = await getRecLink(page, "Best week");
    expect(href && href === "index.html", `expected "index.html" link for "Best week", got: ${href}`).toBeTruthy();
  });

  test("filter-link-for-best-month", async () => {
    const href = await getRecLink(page, "Best month");
    expect(href && href === "index.html", `expected "index.html" link for "Best month", got: ${href}`).toBeTruthy();
  });

  test("filter-link-for-most-activities", async () => {
    const href = await getRecLink(page, "Most activities");
    expect(href && href === "index.html", `expected "index.html" link for "Most activities", got: ${href}`).toBeTruthy();
  });

  test("filter-link-for-longest-streak", async () => {
    const href = await getRecLink(page, "Longest streak");
    expect(href === "index.html", `expected "index.html" link for "Longest streak", got: ${href}`).toBeTruthy();
  });

  test("streak-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Longest streak");
    expect(f, "activityFilter not set by Longest streak link").toBeTruthy();
    expect(f.year, `expected year "2026", got "${f.year}"`).toBe("2026");
    expect(f.month, `expected month "6" (June), got "${f.month}"`).toBe("6");
    expect(f.sport, `expected sport "Ride", got "${f.sport}"`).toBe("Ride");
  });

  test("best-month-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Best month");
    expect(f, "activityFilter not set by Best month link").toBeTruthy();
    expect(f.year, `expected year "2026", got "${f.year}"`).toBe("2026");
    expect(f.month, `expected month "6" (June), got "${f.month}"`).toBe("6");
    expect(f.sport, `expected sport "Ride", got "${f.sport}"`).toBe("Ride");
  });

  test("best-week-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Best week");
    expect(f, "activityFilter not set by Best week link").toBeTruthy();
    expect(f.year, `expected year "2026", got "${f.year}"`).toBe("2026");
    expect(f.month, `expected month "6" (June), got "${f.month}"`).toBe("6");
    expect(f.sport, `expected sport "Ride", got "${f.sport}"`).toBe("Ride");
  });

  test("most-activities-filter-year-month-sport", async () => {
    const f = await getFilterFromRecLink(page, "Most activities");
    expect(f, "activityFilter not set by Most activities link").toBeTruthy();
    expect(f.year, `expected year "2026", got "${f.year}"`).toBe("2026");
    expect(f.month, `expected month "6" (June), got "${f.month}"`).toBe("6");
    expect(f.sport, `expected sport "Ride", got "${f.sport}"`).toBe("Ride");
  });

  test("best-week-value-has-km", async () => {
    const val = await getRecVal(page, "Best week");
    expect(val && val.includes("km"), `expected "km" in Best week value, got: "${val}"`).toBeTruthy();
  });

  test("best-month-value-has-km", async () => {
    const val = await getRecVal(page, "Best month");
    expect(val && val.includes("km"), `expected "km" in Best month value, got: "${val}"`).toBeTruthy();
  });

  test("most-activities-value-is-number", async () => {
    const val = await getRecVal(page, "Most activities");
    expect(val && val.match(/\d+\s+activit/), `expected "N activit..." in Most activities, got: "${val}"`).toBeTruthy();
  });

  test("streak-value-has-days", async () => {
    const val = await getRecVal(page, "Longest streak");
    expect(val && val.includes("day"), `expected "day" in Longest streak value, got: "${val}"`).toBeTruthy();
  });

  test("no-power-record-without-data", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) => els.map((el) => el.textContent));
    expect(
      !labels.some((l) => l.includes("Most power")),
      `"Most power" record should be absent when no watts data, got: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("no-work-record-without-data", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) => els.map((el) => el.textContent));
    expect(
      !labels.some((l) => l.includes("Most work")),
      `"Most work" record should be absent when no kJ data, got: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("longest-label-says-ride-for-ride-sport", async () => {
    const labels = await page.$$eval("#recs .rec .rl", (els) => els.map((el) => el.textContent));
    expect(
      labels.some((l) => l === "Longest ride"),
      `expected "Longest ride" label when sport=Ride, got: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("longest-label-says-walk-for-walk-sport", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find((o) => o.value === "Walk");
      if (opt) { sel.value = "Walk"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const labels = await page.$$eval("#recs .rec .rl", (els) => els.map((el) => el.textContent));
    expect(
      labels.some((l) => l === "Longest walk"),
      `expected "Longest walk" label when sport=Walk, got: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("most-steps-appears-for-walk", async () => {
    const val = await getRecVal(page, "Most steps");
    expect(val && /[\d\s]/.test(val), `expected a numeric steps value for Walk, got: "${val}"`).toBeTruthy();
  });

  test("most-steps-absent-for-ride", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      const opt = Array.from(sel.options).find((o) => o.value === "Ride");
      if (opt) { sel.value = "Ride"; sel.dispatchEvent(new Event("change", { bubbles: true })); }
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const labels = await page.$$eval("#recs .rec .rl", (els) => els.map((el) => el.textContent));
    expect(
      !labels.some((l) => l.includes("Most steps")),
      `"Most steps" should be absent for Ride sport, got: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });
});

// ── Stats Goals ────────────────────────────────────────────────────────────────

test.describe("stats-goals", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    // Reset goal state before the suite so results are deterministic.
    await fetch(`${CGI}/ride-goals`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ goals: {} }),
    }).catch(() => {});

    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("section-visible-ride-2026", async () => {
    const el = await page.$("#goalsSection .goal-wrap");
    expect(el, "#goalsSection .goal-wrap not found for Ride + 2026").toBeTruthy();
  });

  test("section-hidden-for-run", async () => {
    await page.evaluate(() => {
      const sel = document.getElementById("sportSel");
      sel.value = "Run";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));
    const html = await page.$eval("#goalsSection", (el) => el.innerHTML);
    expect(html, `#goalsSection should be empty for Run sport, got: "${html.slice(0, 100)}"`).toBe("");
  });

  test("section-hidden-for-all-years", async () => {
    await page.evaluate(() => {
      document.getElementById("sportSel").value = "Ride";
      document.getElementById("sportSel").dispatchEvent(new Event("change", { bubbles: true }));
      document.getElementById("yearSel").value = "all";
      document.getElementById("yearSel").dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 200)));
    const html = await page.$eval("#goalsSection", (el) => el.innerHTML);
    expect(html, `#goalsSection should be empty for all-years, got: "${html.slice(0, 100)}"`).toBe("");
  });

  test("section-reappears-ride-2026", async () => {
    await page.evaluate(() => {
      document.getElementById("yearSel").value = "2026";
      document.getElementById("yearSel").dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const el = await page.$("#goalsSection .goal-wrap");
    expect(el, "#goalsSection .goal-wrap not found after switching back to Ride + 2026").toBeTruthy();
  });

  test("progress-bar-appears", async () => {
    await page.evaluate(() => {
      const inp = document.getElementById("goalKmInput");
      if (inp) { inp.value = "2000"; }
    });
    await page.click("#goalKmSave");
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const el = await page.$(".goal-bar-inner");
    expect(el, ".goal-bar-inner not found after saving goal").toBeTruthy();
  });

  test("progress-bar-nonzero-width", async () => {
    const w = await page.$eval(".goal-bar-inner", (el) => el.style.width);
    const pct = parseFloat(w);
    expect(pct > 0 && pct <= 100, `expected 0 < progress width <= 100%, got "${w}"`).toBeTruthy();
  });

  test("stats-line-shows-percent", async () => {
    const text = await page.$eval(".goal-stats", (el) => el.textContent);
    expect(text.includes("%"), `expected "%" in .goal-stats, got: "${text}"`).toBeTruthy();
  });

  test("twelve-monthly-tiles", async () => {
    const n = await page.$$eval(".goal-mo", (els) => els.length);
    expect(n, `expected 12 .goal-mo tiles, got ${n}`).toBe(12);
  });

  test("twelve-monthly-bars", async () => {
    const n = await page.$$eval(".goal-mo-bar", (els) => els.length);
    expect(n, `expected 12 .goal-mo-bar elements, got ${n}`).toBe(12);
  });

  test("monthly-tile-hover-shows-tip", async () => {
    const visible = await page.evaluate(() => {
      const tile = document.querySelector(".goal-mo");
      if (!tile) return false;
      const r = tile.getBoundingClientRect();
      tile.dispatchEvent(new MouseEvent("mouseenter", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2,
      }));
      return document.getElementById("tip").style.display === "block";
    });
    expect(visible, "#tip should be visible after mouseenter on .goal-mo tile").toBeTruthy();
  });

  test("monthly-tile-tip-has-year-lines", async () => {
    const text = await page.evaluate(() => document.getElementById("tip").textContent);
    expect(
      text.includes("2026") && text.includes("km"),
      `#tip text should contain "2026" and "km", got: "${text}"`,
    ).toBeTruthy();
    expect(text.includes("Target"), `#tip text should contain "Target", got: "${text}"`).toBeTruthy();
  });

  test("stats-line-hover-shows-distribution-tip", async () => {
    const visible = await page.evaluate(() => {
      const el = document.querySelector(".goal-stats");
      if (!el) return false;
      const r = el.getBoundingClientRect();
      el.dispatchEvent(new MouseEvent("mouseenter", {
        bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2,
      }));
      return document.getElementById("tip").style.display === "block";
    });
    expect(visible, "#tip should be visible after mouseenter on .goal-stats").toBeTruthy();
  });

  test("stats-line-tip-has-distribution-content", async () => {
    const text = await page.evaluate(() => document.getElementById("tip").textContent);
    expect(
      text.includes("Jan") && /\d/.test(text),
      `distribution tip should contain "Jan" and a numeric value, got: "${text}"`,
    ).toBeTruthy();
    expect(
      text.toLowerCase().includes("based on") || text.toLowerCase().includes("equal split"),
      `distribution tip should name the source, got: "${text}"`,
    ).toBeTruthy();
    expect(
      /\(\d+\.\d+%\)/.test(text),
      `distribution tip should contain percentage values like "(8.3%)", got: "${text}"`,
    ).toBeTruthy();
  });

  test("goal-persists-after-reload", async () => {
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".kpis .kpi", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => new Promise((r) => setTimeout(r, 500)));
    const val = await page.evaluate(() => document.getElementById("goalKmInput")?.value);
    expect(val, `expected input value "2000" after reload, got "${val}"`).toBe("2000");
  });
});

// ── Stats Section Order ────────────────────────────────────────────────────────

test.describe("stats-section-order", () => {
  test.describe.configure({ mode: 'serial' });
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => {
      try { localStorage.removeItem("ssb-stats-sec"); } catch (_) {}
      try { sessionStorage.clear(); } catch (_) {}
    });
    await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector(".sec[data-sid]", { timeout: 10000 }); } catch (_) {}
  });

  test.afterAll(async () => {
    await page.evaluate(() => { try { localStorage.removeItem("ssb-stats-sec"); } catch (_) {} });
    await page.close();
  });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("all-sections-present", async () => {
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const expected = ["kpis", "goals", "records", "year", "monthly-chart", "monthly-table", "comparison", "sport", "dow"];
    expect(sids, `sections: ${JSON.stringify(sids)}`).toEqual(expected);
  });

  test("drag-handles-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec .sec-handle", (els) => els.length);
    expect(n, `expected 9 .sec-handle elements, got ${n}`).toBe(9);
  });

  test("reset-button-present", async () => {
    const n = await page.$$eval("#sec-wrap .sec-order-reset", (els) => els.length);
    expect(n, `expected 1 .sec-order-reset button, got ${n}`).toBe(1);
  });

  test("drag-to-reorder-works", async () => {
    await page.evaluate(() => {
      const wrap = document.getElementById("sec-wrap");
      const secs = Array.from(wrap.querySelectorAll(".sec[data-sid]"));
      const src = secs.find((s) => s.getAttribute("data-sid") === "records");
      const tgt = secs.find((s) => s.getAttribute("data-sid") === "kpis");
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
    expect(sids[0], `expected "records" first after drag, got "${sids[0]}"`).toBe("records");
    expect(sids[1], `expected "kpis" second after drag, got "${sids[1]}"`).toBe("kpis");
  });

  test("order-persisted-in-localstorage", async () => {
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-stats-sec")); } catch (_) { return null; }
    });
    expect(Array.isArray(saved) && saved.length === 9, "saved order should be 9-element array").toBeTruthy();
    expect(saved[0], `expected "records" first in saved, got "${saved[0]}"`).toBe("records");
  });

  test("order-restored-after-reload", async () => {
    await page.reload({ waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector(".sec[data-sid]", { timeout: 10000 }); } catch (_) {}
    const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    expect(sids[0], `after reload, expected "records" first, got "${sids[0]}"`).toBe("records");
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
    expect(sids[0], `after reset, expected "kpis" first, got "${sids[0]}"`).toBe("kpis");
    const saved = await page.evaluate(() => {
      try { return localStorage.getItem("ssb-stats-sec"); } catch (_) { return "x"; }
    });
    expect(saved, `expected localStorage cleared after reset, got: ${saved}`).toBe(null);
  });
});
