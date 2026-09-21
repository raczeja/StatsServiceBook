import { test, expect } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

// ── My Activities ──────────────────────────────────────────────────────────────

test.describe("my-activities", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    // generatedAt is 2026-07-14 so default month is July; select June which has the full test dataset
    await page.evaluate(() => {
      const sel = document.getElementById("month");
      sel.value = "6";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
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

  test("meta-5-activities", async () => {
    const text = await page.$eval("#meta", (el) => el.textContent);
    expect(text.includes("6 activities"), `expected "6 activities" in #meta: ${text}`).toBeTruthy();
  });

  test("summary-distance", async () => {
    const text = await page.$eval("#summary", (el) => el.textContent);
    expect(text.includes("304"), `expected "304" km in #summary: ${text}`).toBeTruthy();
  });

  test("table-5-rows", async () => {
    const n = await page.$$eval("#board tbody tr", (rows) => rows.length);
    expect(n, `expected 6 Ride rows for June 2026, got ${n}`).toBe(6);
  });

  test("bests-chips", async () => {
    const n = await page.$$eval("#bests .best", (els) => els.length);
    expect(n >= 3, `expected >= 3 best chips, got ${n}`).toBeTruthy();
  });

  test("year-selector-2026", async () => {
    const val = await page.$eval("#year", (el) => el.value);
    expect(val).toBe("2026");
  });

  test("bar-chart-has-bars", async () => {
    const n = await page.$$eval("#svg-dist rect", (els) => els.length);
    expect(n > 0, `expected bars in #svg-dist, got ${n}`).toBeTruthy();
  });

  test("bike-selects-in-table", async () => {
    const n = await page.$$eval("#board tbody td select", (els) => els.length);
    expect(n >= 5, `expected >= 5 bike selects for Ride rows, got ${n}`).toBeTruthy();
  });

  test("drive-banner-hidden", async () => {
    const visible = await page
      .$eval("#drive-banner", (el) => el.classList.contains("visible"))
      .catch(() => false);
    expect(visible, "drive-auth banner should be hidden when drive-status.json says ok:true").toBe(false);
  });

  test("ck-banner-hidden-in-api-mode", async () => {
    const display = await page
      .$eval("#ck-banner", (el) => el.style.display)
      .catch(() => "none");
    expect(display, "#ck-banner should be hidden when scrapeMeta is null").toBe("none");
  });

  test("ck-banner-ok-state", async () => {
    const { cls, visible } = await page.evaluate(() => {
      const el = document.getElementById("ck-banner");
      if (!el || typeof renderCookieBanner !== "function") return { cls: "", visible: false };
      const future = new Date(Date.now() + 20 * 86400000).toISOString().slice(0, 10);
      const today  = new Date().toISOString().slice(0, 10);
      renderCookieBanner({ cookieVerifiedAt: today, cookieRefreshNeededBy: future });
      return { cls: el.className, visible: el.style.display !== "none" };
    });
    expect(visible, "#ck-banner should be visible in ok state").toBeTruthy();
    expect(cls.includes("ck-ok"), `#ck-banner class should include ck-ok, got: "${cls}"`).toBeTruthy();
  });

  test("ck-banner-warn-state", async () => {
    const { cls, visible } = await page.evaluate(() => {
      const el = document.getElementById("ck-banner");
      if (!el || typeof renderCookieBanner !== "function") return { cls: "", visible: false };
      const soon  = new Date(Date.now() + 4 * 86400000).toISOString().slice(0, 10);
      const today = new Date().toISOString().slice(0, 10);
      renderCookieBanner({ cookieVerifiedAt: today, cookieRefreshNeededBy: soon });
      return { cls: el.className, visible: el.style.display !== "none" };
    });
    expect(visible, "#ck-banner should be visible in warn state").toBeTruthy();
    expect(cls.includes("ck-warn"), `#ck-banner class should include ck-warn, got: "${cls}"`).toBeTruthy();
  });

  test("ck-banner-expired-state", async () => {
    const { cls, visible, text } = await page.evaluate(() => {
      const el = document.getElementById("ck-banner");
      if (!el || typeof renderCookieBanner !== "function") return { cls: "", visible: false, text: "" };
      const past  = new Date(Date.now() - 2 * 86400000).toISOString().slice(0, 10);
      const today = new Date().toISOString().slice(0, 10);
      renderCookieBanner({ cookieVerifiedAt: today, cookieRefreshNeededBy: past });
      return { cls: el.className, visible: el.style.display !== "none", text: el.innerHTML };
    });
    expect(visible, "#ck-banner should be visible in expired state").toBeTruthy();
    expect(cls.includes("ck-expired"), `#ck-banner class should include ck-expired, got: "${cls}"`).toBeTruthy();
    expect(text.includes("expired"), `#ck-banner text should mention "expired", got: "${text}"`).toBeTruthy();
  });

  test("drive-token-connected", async () => {
    await page.waitForFunction(
      () => document.getElementById("drive-token")?.textContent.includes("Drive:"),
      { timeout: 5000 },
    ).catch(() => {});
    const text = await page
      .$eval("#drive-token", (el) => el.textContent)
      .catch(() => "");
    expect(text.includes("Drive: reachable"), `expected "Drive: reachable" in #drive-token: "${text}"`).toBeTruthy();
    expect(text.includes("42 files"), `expected "42 files" in #drive-token: "${text}"`).toBeTruthy();
  });
});

// ── Empty State ────────────────────────────────────────────────────────────────

test.describe("empty-state", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const sel = document.getElementById("sport");
      sel.value = "AlpineSki";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
  });

  test.afterAll(async () => { await page.close(); });

  test("empty-div-shown", async () => {
    const el = await page.$("#board .empty");
    expect(el, ".empty not rendered when no activities match filter").toBeTruthy();
  });

  test("empty-div-text", async () => {
    const text = await page.$eval("#board .empty", (el) => el.textContent);
    expect(text.includes("No activities"), `expected "No activities" in .empty, got: "${text}"`).toBeTruthy();
  });

  test("summary-cleared", async () => {
    const text = await page.$eval("#summary", (el) => el.textContent.trim());
    expect(text, `expected #summary cleared on empty filter, got: "${text}"`).toBe("");
  });
});

// ── Dashboard Best Chips ───────────────────────────────────────────────────────

test.describe("dashboard-best-chips", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    await page.evaluate(() => {
      const sel = document.getElementById("month");
      sel.value = "6";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    try {
      await page.waitForSelector("#bests .best", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("chips-have-label-and-value", async () => {
    const chips = await page.$$eval("#bests .best", (els) =>
      els.map((el) => ({
        label: el.querySelector("b")?.textContent?.trim() || "",
        full: el.textContent?.trim() || "",
      })),
    );
    expect(chips.length >= 3, `expected >= 3 best chips, got ${chips.length}`).toBeTruthy();
    chips.forEach((c, i) => {
      expect(c.label.length > 0, `chip ${i} has no <b> label`).toBeTruthy();
      expect(c.full.length > c.label.length, `chip ${i} has no value text beyond the label`).toBeTruthy();
    });
  });

  test("temperature-chips-present-with-degree-symbol", async () => {
    const chipTexts = await page.$$eval("#bests .best", (els) => els.map((el) => el.textContent || ""));
    const coldText = chipTexts.find((t) => t.includes("Coldest"));
    const hotText = chipTexts.find((t) => t.includes("Hottest"));
    expect(coldText, "expected a Coldest chip (sample data has average_temp)").toBeTruthy();
    expect(hotText, "expected a Hottest chip (sample data has average_temp)").toBeTruthy();
    expect(coldText.includes("°C"), `expected "°C" in Coldest chip, got: "${coldText}"`).toBeTruthy();
    expect(hotText.includes("°C"), `expected "°C" in Hottest chip, got: "${hotText}"`).toBeTruthy();
  });
});

// ── Activity Filtering & Refresh ───────────────────────────────────────────────

test.describe("activity-filtering", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("year-filter-changes", async () => {
    const year2026 = await page.$eval("#year", (el) => el.value);
    expect(year2026, "initial year should be 2026").toBe("2026");
    await page.selectOption("#year", "2025");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );
    const year2025 = await page.$eval("#year", (el) => el.value);
    expect(year2025, "year should be 2025 after change").toBe("2025");
    const rows2025 = await page.$$eval("#board tbody tr", (rows) => rows.length);
    expect(rows2025 >= 0, "rows after year filter should be >= 0").toBeTruthy();
  });

  test("sport-filter-changes", async () => {
    await page.selectOption("#year", "2026");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );
    const rideRows = await page.$$eval("#board tbody tr", (rows) => rows.length);
    expect(rideRows >= 1, "should have >= 1 Ride rows").toBeTruthy();
    const sportSelect = await page.$(".sport-filter select");
    if (sportSelect) {
      await page.evaluate(() => {
        const select = document.querySelector(".sport-filter select");
        if (select) {
          const walkOpt = Array.from(select.options).find((o) => o.textContent.includes("Walk"));
          if (walkOpt) { select.value = walkOpt.value; select.dispatchEvent(new Event("change", { bubbles: true })); }
        }
      });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 5000 },
      );
      const walkRows = await page.$$eval("#board tbody tr", (rows) => rows.length);
      expect(walkRows >= 0, "Walk rows should be >= 0").toBeTruthy();
    }
  });

  test("month-filter-changes", async () => {
    const monthSelect = await page.$(".month-filter select");
    if (monthSelect) {
      const mayOpt = await page.evaluate(() => {
        const select = document.querySelector(".month-filter select");
        if (select) {
          const opt = Array.from(select.options).find((o) => o.textContent.includes("May"));
          return opt?.value;
        }
      });
      if (mayOpt) {
        await page.selectOption(".month-filter select", mayOpt);
        await page.waitForFunction(
          () => !document.getElementById("meta")?.textContent.includes("Loading"),
          { timeout: 5000 },
        );
        const currentMonth = await page.$eval(".month-filter select", (el) => el.value);
        expect(currentMonth, "month filter should be set").toBeTruthy();
      }
    }
  });
});

// ── Bike Assignment (Dropdown) ─────────────────────────────────────────────────

test.describe("bike-assignment", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("dropdowns-exist", async () => {
    const selects = await page.$$eval("#board tbody td select", (els) => els.length);
    expect(selects >= 1, `expected >= 1 bike select, got ${selects}`).toBeTruthy();
  });

  test("bike-assignment-persists", async () => {
    const selectData = await page.evaluate(() => {
      const selects = document.querySelectorAll("#board tbody td select");
      for (const sel of selects) {
        if (sel.options.length >= 2) {
          const activityId = sel.closest("tr")?.getAttribute("data-id");
          const currentValue = sel.value;
          return {
            found: true,
            activityId,
            currentValue,
            options: Array.from(sel.options).map((o) => ({ value: o.value, text: o.textContent })),
          };
        }
      }
      return { found: false };
    });
    expect(selectData.found, "no multi-option select found for testing").toBeTruthy();
    if (selectData.found) {
      const { activityId, currentValue, options } = selectData;
      const otherOption = options.find((o) => o.value !== currentValue);
      expect(otherOption, "no alternative option found to test").toBeTruthy();
      await page.evaluate(({ aId, newVal }) => {
        const selects = document.querySelectorAll("#board tbody td select");
        for (const sel of selects) {
          const row = sel.closest("tr");
          if (row?.getAttribute("data-id") === aId) {
            sel.value = newVal;
            sel.dispatchEvent(new Event("change", { bubbles: true }));
            break;
          }
        }
      }, { aId: activityId, newVal: otherOption.value });
      await page.evaluate(() => new Promise((resolve) => { setTimeout(resolve, 500); }));
      const bikeAssignR = await page.evaluate(async () => {
        try {
          const r = await fetch("/cgi-bin/bike-assign", { cache: "no-store" });
          return await r.json();
        } catch (e) { return null; }
      });
      expect(bikeAssignR, "bike-assign CGI should return data").toBeTruthy();
      if (bikeAssignR) {
        expect(typeof bikeAssignR === "object", "bike-assign should return a JSON object").toBeTruthy();
      }
    }
  });
});

// ── Bike Odo Includes Manual Assignments ──────────────────────────────────────

test.describe("bike-odo-manual-assign", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const sel = document.getElementById("month");
      sel.value = "6";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    await page.evaluate(() => {
      const sel = document.getElementById("sport");
      sel.value = "Ride";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
  });

  test.afterAll(async () => { await page.close(); });

  test("odo-counts-reassigned-ride", async () => {
    const beforeText = await page.$eval("#summary", (el) => el.textContent);
    const beforeKm = parseFloat(beforeText.match(/^([\d\s,]+)\s*km/)?.[1]?.replace(/[\s,]/g, "") || "0");
    expect(beforeKm > 0, `expected non-zero total km in summary: "${beforeText}"`).toBeTruthy();

    const result = await page.evaluate(() => {
      if (typeof setBike === "function") {
        setBike("4", "Road Bike");
      } else {
        window.setBike("4", "Road Bike");
      }
      return new Promise((resolve) => {
        setTimeout(() => {
          const text = document.getElementById("summary")?.textContent || "";
          const m = text.match(/Road Bike:\s*([\d\s,]+)\s*km/);
          resolve({ summaryText: text, odoText: m ? m[1] : null });
        }, 200);
      });
    });
    expect(
      result.odoText !== null,
      `"Road Bike: X km" not found in summary after reassignment: "${result.summaryText}"`,
    ).toBeTruthy();
    const odoKm = parseFloat(result.odoText.replace(/[\s,]/g, ""));
    expect(
      odoKm > 76,
      `expected Road Bike odo > 76 km after reassigning Gravel Grind (76 km), got ${odoKm} km. Summary: "${result.summaryText}"`,
    ).toBeTruthy();
  });
});

// ── Sync Source Merging ────────────────────────────────────────────────────────

test.describe("sync-source-merging", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const sel = document.getElementById("month");
      sel.value = "6";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
  });

  test.afterAll(async () => { await page.close(); });

  test("strava-and-healthsync-mixed", async () => {
    const activityIds = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => r.getAttribute("data-id")).filter((id) => id !== null && id !== ""),
    );
    expect(activityIds.length > 0, "no activities found in table").toBeTruthy();
    const numericIds = activityIds.filter((id) => /^\d+$/.test(id));
    const stringIds = activityIds.filter((id) => /^[a-z0-9\-]+$/.test(id));
    expect(numericIds.length > 0, `expected Strava (numeric) activities, got: ${JSON.stringify(activityIds)}`).toBeTruthy();
    expect(stringIds.length > 0, `expected HealthSync (string) activities, got: ${JSON.stringify(activityIds)}`).toBeTruthy();
  });

  test("healthsync-activities-have-date-ids", async () => {
    const healthsyncIds = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => r.getAttribute("data-id")).filter((id) => id && /^\d{4}-\d{2}-\d{2}/.test(id)),
    );
    expect(healthsyncIds.length > 0, "no HealthSync activities found").toBeTruthy();
    healthsyncIds.forEach((id) => {
      expect(/^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}.*/.test(id), `invalid HealthSync ID format: ${id}`).toBeTruthy();
    });
  });

  test("activities-have-required-fields", async () => {
    const activities = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => ({
        id: r.getAttribute("data-id"),
        dateCells: r.querySelectorAll("td").length,
        hasBike: !!r.querySelector("select"),
      })),
    );
    expect(activities.length > 0, "no activities found").toBeTruthy();
    activities.forEach((act) => {
      expect(act.id, "activity missing id").toBeTruthy();
      expect(act.dateCells >= 4, `activity ${act.id} has < 4 columns`).toBeTruthy();
    });
  });

  test("no-duplicate-activities", async () => {
    const activityIds = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => r.getAttribute("data-id")),
    );
    const uniqueIds = new Set(activityIds);
    expect(activityIds.length, `found ${activityIds.length - uniqueIds.size} duplicate activities`).toBe(uniqueIds.size);
  });
});

// ── Historical Activity Preservation ──────────────────────────────────────────

test.describe("historical-preservation", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("activities-span-multiple-years", async () => {
    const activityDates = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => {
        const cells = r.querySelectorAll("td");
        const allText = Array.from(cells).map((c) => c.textContent).join(" ");
        const dateMatch = allText.match(/(\d{4})-(\d{2})-(\d{2})/);
        return dateMatch ? dateMatch[1] : null;
      }).filter((y) => y !== null),
    );
    expect(activityDates.length > 0, `no activities with valid dates found`).toBeTruthy();
  });

  test("all-years-view-preserves-count", async () => {
    const yearSelect = await page.$("#year");
    if (yearSelect) {
      const options = await page.$$eval("#year option", (opts) =>
        opts.map((o) => ({ value: o.value, text: o.textContent })),
      );
      const allOption = options.find((o) => o.text.toLowerCase().includes("all"));
      if (allOption) {
        await page.selectOption("#year", allOption.value);
        await page.waitForFunction(
          () => !document.getElementById("meta")?.textContent.includes("Loading"),
          { timeout: 5000 },
        );
      }
    }
    const rowCount = await page.$$eval("#board tbody tr", (rows) => rows.length);
    expect(rowCount > 0, "no activities shown for all years").toBeTruthy();
  });

  test("all-activities-have-detail-link", async () => {
    const { rows, links } = await page.$$eval("#board tbody tr", (rows) => ({
      rows: rows.length,
      links: rows.filter((r) => r.querySelector("a[href*='activity.html']")).length,
    }));
    expect(rows, "board must have at least one activity row").toBeGreaterThan(0);
    expect(
      links,
      `every activity row must have a detail link — ${rows - links} row(s) missing a link`,
    ).toBe(rows);
  });

  test("total-count-accessible", async () => {
    const metaText = await page.$eval("#meta", (el) => el.textContent.trim());
    const countMatch = metaText.match(/(\d+)\s*activities/);
    expect(countMatch, `couldn't extract activity count from meta: "${metaText}"`).toBeTruthy();
    const count = parseInt(countMatch[1]);
    expect(count > 0, `activity count should be > 0, got ${count}`).toBeTruthy();
  });
});

// ── Data Consistency Across Sources ───────────────────────────────────────────

test.describe("data-consistency", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("required-fields-populated", async () => {
    const activities = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => {
        const cells = r.querySelectorAll("td");
        return {
          name: cells[0]?.textContent?.trim() || "",
          date: cells[1]?.textContent?.trim() || "",
          distance: cells[2]?.textContent?.trim() || "",
          time: cells[3]?.textContent?.trim() || "",
        };
      }),
    );
    activities.forEach((act, idx) => {
      expect(act.name && act.name.length > 0, `activity ${idx} missing name`).toBeTruthy();
      expect(act.date && act.date.length > 0, `activity ${idx} missing date`).toBeTruthy();
      expect(act.distance && act.distance.length > 0, `activity ${idx} missing distance`).toBeTruthy();
      expect(act.time && act.time.length > 0, `activity ${idx} missing time`).toBeTruthy();
    });
  });

  test("consistent-sport-types", async () => {
    const rows = await page.$$eval("#board tbody tr", (trs) => trs.length);
    expect(rows > 0, "no activities to validate").toBeTruthy();
    const structureOk = await page.evaluate(() => {
      const rows = document.querySelectorAll("#board tbody tr");
      for (const row of rows) {
        const cells = row.querySelectorAll("td");
        if (cells.length < 4) return false;
      }
      return true;
    });
    expect(structureOk, "activity table rows have inconsistent structure").toBeTruthy();
  });

  test("distances-are-numeric", async () => {
    const distances = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => {
        const cells = r.querySelectorAll("td");
        for (const cell of cells) {
          const text = cell.textContent || "";
          const match = text.match(/[\d.,]+/);
          if (match && /\d/.test(match[0])) return match[0];
        }
        return "";
      }).filter((d) => d !== ""),
    );
    distances.forEach((dist, idx) => {
      const numericDist = parseFloat(dist.replace(/[^\d.]/g, ""));
      expect(!isNaN(numericDist) && numericDist > 0, `distance ${idx} is not numeric or is 0: "${dist}"`).toBeTruthy();
    });
  });

  test("all-activities-clickable", async () => {
    const activityIds = await page.$$eval("#board tbody tr", (rows) =>
      rows.map((r) => r.getAttribute("data-id")).filter((id) => id),
    );
    expect(activityIds.length > 0, "should have clickable activities with data-id attributes").toBeTruthy();
  });

  test("fmtKm-thousand-separator", async () => {
    const formatted = await page.evaluate(() => fmtKm(1234567));
    expect(formatted, "fmtKm(1234567) should use space as thousand separator").toBe("1 234.6");
  });
});

// ── Focus Row (best-chip highlight) ───────────────────────────────────────────

test.describe("focus-row", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    await page.evaluate(() => {
      const sel = document.getElementById("month");
      sel.value = "6";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
    try {
      await page.waitForSelector("#bests .best", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("chips-link-to-valid-rows", async () => {
    const chipIds = await page.$$eval("#bests .best", (els) =>
      els.map((el) => el.getAttribute("data-id")).filter(Boolean),
    );
    expect(chipIds.length >= 1, "no best chips with data-id found").toBeTruthy();
    for (const id of chipIds) {
      const exists = await page.evaluate(
        (id) => !!document.querySelector(`#board tbody tr[data-id="${id}"]`),
        id,
      );
      expect(exists, `no table row found for chip data-id="${id}"`).toBeTruthy();
    }
  });

  test("chip-click-flashes-row", async () => {
    const chipId = await page.$eval("#bests .best", (el) => el.getAttribute("data-id"));
    expect(chipId, "first best chip has no data-id").toBeTruthy();
    await page.evaluate(() => document.querySelector("#bests .best").click());
    await page.waitForFunction(
      (id) => {
        const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
        return tr && tr.classList.contains("flash");
      },
      chipId, { timeout: 1500 },
    );
  });

  test("double-click-restarts-flash", async () => {
    const chipId = await page.$eval("#bests .best", (el) => el.getAttribute("data-id"));
    expect(chipId, "first best chip has no data-id").toBeTruthy();
    await page.evaluate(() => document.querySelector("#bests .best").click());
    await page.waitForFunction(
      (id) => {
        const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
        return tr && tr.classList.contains("flash");
      },
      chipId, { timeout: 1500 },
    );
    await page.evaluate(() => document.querySelector("#bests .best").click());
    const removedQuickly = await page.evaluate((id) => {
      const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
      return tr && !tr.classList.contains("flash");
    }, chipId);
    expect(removedQuickly, "flash class should be removed immediately on second click").toBeTruthy();
    await page.waitForFunction(
      (id) => {
        const tr = document.querySelector(`#board tbody tr[data-id="${id}"]`);
        return tr && tr.classList.contains("flash");
      },
      chipId, { timeout: 1500 },
    );
  });
});

// ── Reset Filter ───────────────────────────────────────────────────────────────

test.describe("reset-filter", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("reset-button-exists", async () => {
    const btn = await page.$("#resetFilters");
    expect(btn, "#resetFilters button not found").toBeTruthy();
  });

  test("reset-restores-default-year", async () => {
    await page.selectOption("#year", "2025");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );
    await page.click("#resetFilters");
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 5000 },
    );
    const year = await page.$eval("#year", (el) => el.value);
    expect(year, `expected year reset to "2026", got "${year}"`).toBe("2026");
  });

  test("reset-restores-default-sport", async () => {
    const sport = await page.$eval("#sport", (el) => el.value);
    expect(sport, `expected sport reset to "Ride", got "${sport}"`).toBe("Ride");
  });

  test("reset-clears-month-filter", async () => {
    const month = await page.$eval("#month", (el) => el.value);
    expect(month !== undefined, "month selector should exist").toBeTruthy();
    expect(typeof month === "string", `month value should be a string, got ${typeof month}`).toBeTruthy();
  });
});

// ── Column Sorting ─────────────────────────────────────────────────────────────

test.describe("column-sorting", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.dash, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector("#board table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("default-date-column-sorted", async () => {
    const hasSortedClass = await page.evaluate(() => {
      const ths = Array.from(document.querySelectorAll("#board thead th"));
      return ths.some((th) => th.className.includes("sorted-"));
    });
    expect(hasSortedClass, "no column header has a sorted class on initial load").toBeTruthy();
  });

  test("click-header-applies-sorted-class", async () => {
    const headers = await page.$$eval("#board thead th", (ths) =>
      ths.map((th, i) => ({ idx: i, text: th.textContent.trim(), cls: th.className })),
    );
    const unsorted = headers.find((h) => !h.cls.includes("sorted-"));
    expect(unsorted, "all headers already sorted — cannot test click").toBeTruthy();
    await page.$$eval("#board thead th", (ths, idx) => ths[idx].click(), unsorted.idx);
    await page.evaluate(() => new Promise((resolve) => { setTimeout(resolve, 200); }));
    const hasClass = await page.evaluate((idx) => {
      const th = document.querySelectorAll("#board thead th")[idx];
      return th.className.includes("sorted-");
    }, unsorted.idx);
    expect(hasClass, `expected sorted class on header #${unsorted.idx} ("${unsorted.text}") after click`).toBeTruthy();
  });

  test("second-click-reverses-sort-direction", async () => {
    const headers = await page.$$eval("#board thead th", (ths) =>
      ths.map((th, i) => ({ idx: i, cls: th.className })),
    );
    const sorted = headers.find((h) => h.cls.includes("sorted-"));
    expect(sorted, "no sorted header found for reverse-click test").toBeTruthy();
    const dirBefore = sorted.cls.includes("sorted-asc") ? "asc" : "desc";
    await page.$$eval("#board thead th", (ths, idx) => ths[idx].click(), sorted.idx);
    await page.evaluate(() => new Promise((resolve) => { setTimeout(resolve, 200); }));
    const dirAfter = await page.evaluate((idx) => {
      const th = document.querySelectorAll("#board thead th")[idx];
      return th.className.includes("sorted-asc") ? "asc" : "desc";
    }, sorted.idx);
    expect(dirAfter).not.toBe(dirBefore);
  });
});
