import { test, expect } from "@playwright/test";
import { URLS } from "./test-urls.mjs";

// ── Club Dashboard ─────────────────────────────────────────────────────────────

test.describe.serial("club-dashboard", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.club, { waitUntil: "networkidle", timeout: 20000 });
    try { await page.waitForSelector("#board tbody tr", { timeout: 10000 }); } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("meta-populated", async () => {
    const text = await page.$eval("#meta", (el) => el.textContent);
    expect(text.includes("Loading"), `#meta still says Loading: ${text}`).toBe(false);
  });

  test("table-has-rows", async () => {
    const n = await page.$$eval("#board .person-row", (rows) => rows.length);
    expect(n >= 1, `expected >= 1 person row, got ${n}`).toBeTruthy();
  });

  test("4-athlete-rows", async () => {
    const n = await page.$$eval("#board .person-row", (rows) => rows.length);
    expect(n, `expected 4 person-rows, got ${n}`).toBe(4);
  });

  test("4-detail-rows-hidden", async () => {
    const n = await page.$$eval(
      "#board .detail-row",
      (rows) => rows.filter((r) => r.style.display === "none").length,
    );
    expect(n, `expected 4 hidden detail-rows, got ${n}`).toBe(4);
  });

  test("first-place-Alex", async () => {
    const name = await page.$eval(
      "#board .person-row:first-of-type td:nth-child(2)",
      (el) => el.textContent.trim(),
    );
    expect(name.startsWith("Alex"), `expected first place "Alex…", got "${name}"`).toBeTruthy();
  });

  test("drill-down-toggle", async () => {
    await page.click("#board .person-row:first-child");
    const visible = await page.$eval(
      "#board .detail-row",
      (el) => el.style.display !== "none",
    );
    expect(visible, "detail-row should be visible after clicking person-row").toBeTruthy();
    await page.click("#board .person-row:first-child");
    const hidden = await page.$eval(
      "#board .detail-row",
      (el) => el.style.display === "none",
    );
    expect(hidden, "detail-row should be hidden after second click").toBeTruthy();
  });

  test("drill-down-activity-rows", async () => {
    await page.click("#board .person-row:first-child");
    const n = await page.$eval(
      "#board .detail-row .detail-table tbody",
      (tbody) => tbody.querySelectorAll("tr").length,
    );
    expect(n, `expected 3 detail activity rows for Alex, got ${n}`).toBe(3);
    await page.click("#board .person-row:first-child");
  });

  test("detail-table-has-avg-speed-header", async () => {
    await page.click("#board .person-row:first-child");
    const headers = await page.$eval(
      "#board .detail-row .detail-table thead tr",
      (tr) => Array.from(tr.querySelectorAll("th")).map((th) => th.textContent.trim()),
    );
    expect(
      headers.includes("Avg km/h"),
      `expected "Avg km/h" in detail table headers, got: ${JSON.stringify(headers)}`,
    ).toBeTruthy();
    await page.click("#board .person-row:first-child");
  });

  test("detail-activity-avg-speed-values", async () => {
    await page.click("#board .person-row:first-child");
    const speeds = await page.$eval(
      "#board .detail-row .detail-table tbody",
      (tbody) => Array.from(tbody.querySelectorAll("tr")).map((tr) => {
        const cells = tr.querySelectorAll("td");
        return cells[cells.length - 1]?.textContent.trim();
      }),
    );
    for (let i = 0; i < speeds.length; i++) {
      const n = parseFloat(speeds[i]);
      expect(!isNaN(n) && n > 0, `detail row ${i} avg speed "${speeds[i]}" is not a positive number`).toBeTruthy();
    }
    await page.click("#board .person-row:first-child");
  });

  test("table-no-last-week-past-month", async () => {
    const headers = await page.$$eval(
      "#board thead tr th",
      (ths) => ths.map((th) => th.textContent.trim()),
    );
    expect(
      !headers.some((h) => h.replace(/ /g, " ").includes("Last week")),
      `expected no "Last week" header for past month, got: ${JSON.stringify(headers)}`,
    ).toBeTruthy();
  });

  test("table-has-last-week-column", async () => {
    await page.evaluate(() => {
      const _Orig = window.Date;
      const fake = new _Orig(2026, 5, 15);
      window.__savedDate = _Orig;
      window.Date = class extends _Orig {
        constructor(...a) { super(...(a.length ? a : [fake.getTime()])); }
        static now() { return fake.getTime(); }
      };
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    const headers = await page.$$eval(
      "#board thead tr th",
      (ths) => ths.map((th) => th.textContent.trim()),
    );
    await page.evaluate(() => {
      if (window.__savedDate) { window.Date = window.__savedDate; delete window.__savedDate; }
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    expect(
      headers.some((h) => h.includes("Last week")),
      `expected "Last week" column header when current month matches data, got: ${JSON.stringify(headers)}`,
    ).toBeTruthy();
  });

  test("last-week-column-has-value", async () => {
    await page.evaluate(() => {
      const _Orig = window.Date;
      const fake = new _Orig(2026, 5, 15);
      window.__savedDateLw = _Orig;
      window.Date = class extends _Orig {
        constructor(...a) { super(...(a.length ? a : [fake.getTime()])); }
        static now() { return fake.getTime(); }
      };
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    const lwValues = await page.$$eval(
      "#board .person-row td:last-child",
      (tds) => tds.map((td) => td.textContent.trim()),
    );
    await page.evaluate(() => {
      if (window.__savedDateLw) { window.Date = window.__savedDateLw; delete window.__savedDateLw; }
      if (typeof render === "function") render();
    });
    await new Promise((r) => setTimeout(r, 100));
    const nonZero = lwValues.filter((v) => !v.startsWith("0"));
    expect(
      nonZero.length > 0,
      `expected ≥1 non-zero last-week km value, got: ${JSON.stringify(lwValues)}`,
    ).toBeTruthy();
  });

  test("detail-rows-newest-first", async () => {
    await page.click("#board .person-row:first-child");
    const dates = await page.$eval(
      "#board .detail-row .detail-table tbody",
      (tbody) => Array.from(tbody.querySelectorAll("tr")).map((tr) => tr.querySelector("td")?.textContent.trim() || ""),
    );
    expect(dates.length >= 2, `expected >= 2 detail rows to test sort, got ${dates.length}`).toBeTruthy();
    for (let i = 0; i < dates.length - 1; i++) {
      expect(
        dates[i] >= dates[i + 1],
        `detail rows not newest-first: row ${i}="${dates[i]}" should be >= row ${i+1}="${dates[i+1]}"`,
      ).toBeTruthy();
    }
    await page.click("#board .person-row:first-child");
  });

  test("top5-year-section-exists", async () => {
    const n = await page.$$eval("#board .top5-item", (els) => els.length);
    expect(n >= 1, `expected >= 1 .top5-item in #board, got ${n}`).toBeTruthy();
  });

  test("top5-since-date-in-label", async () => {
    const label = await page.$eval("#board .top5-label", (el) => el.textContent);
    expect(/since \d{4}-\d{2}-\d{2}/.test(label), `top5 label missing "since YYYY-MM-DD", got: "${label}"`).toBeTruthy();
  });

  test("top5-sub-no-since", async () => {
    const subs = await page.$$eval("#board .top5-sub", (els) => els.map((e) => e.textContent));
    const hasSince = subs.some((t) => /since/.test(t));
    expect(!hasSince, `top5 per-athlete subtitle should not contain "since", got: ${JSON.stringify(subs)}`).toBeTruthy();
  });

  test("achieve-section-exists", async () => {
    const n = await page.$$eval("#board .achieve-section", (els) => els.length);
    expect(n >= 1, `expected >= 1 .achieve-section, got ${n}`).toBeTruthy();
  });

  test("achieve-section-label-has-period", async () => {
    const label = await page.$eval("#board .achieve-section-label", (el) => el.textContent);
    expect(label.length > 5, `achieve-section label too short: "${label}"`).toBeTruthy();
  });

  test("club-alltime-section-exists", async () => {
    const n = await page.$$eval("#board .club-alltime", (els) => els.length);
    expect(n >= 1, `expected >= 1 .club-alltime, got ${n}`).toBeTruthy();
  });

  test("club-alltime-label-has-since", async () => {
    const label = await page.evaluate(() => {
      const labels = Array.from(document.querySelectorAll("#board .club-alltime-label"));
      const found = labels.find((el) => el.textContent.includes("Club all-time"));
      return found ? found.textContent : null;
    });
    expect(label !== null, `no "Club all-time" .club-alltime-label found in #board`).toBeTruthy();
    expect(/since \d{4}-\d{2}-\d{2}/.test(label), `club-alltime label missing "since DATE", got: "${label}"`).toBeTruthy();
  });

  test("leaderboard-json-links-accessible", async () => {
    const hrefs = await page.$$eval(
      '#footer-links a[href*="leaderboard_"]',
      (links) => links.map((a) => a.href),
    );
    expect(hrefs.length >= 1, `expected >= 1 leaderboard JSON link in footer, got ${hrefs.length}`).toBeTruthy();
    for (const href of hrefs) {
      const status = await page.evaluate(
        async (url) => (await fetch(url)).status,
        href,
      );
      expect(status, `leaderboard JSON at ${href} returned ${status}`).toBe(200);
    }
  });
});

// ── Club Section Order ─────────────────────────────────────────────────────────

test.describe.serial("club-section-order", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => {
      try { localStorage.removeItem("ssb-lb-sec"); } catch (_) {}
    });
    await page.goto(URLS.club, { waitUntil: "networkidle", timeout: 30000 });
    try { await page.waitForSelector(".club-section .sec[data-sid]", { timeout: 10000 }); } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("sections-present-in-club", async () => {
    const n = await page.$$eval(".club-section .sec[data-sid]", (els) => els.length);
    expect(n >= 1, `expected at least 1 .sec[data-sid] in .club-section, got ${n}`).toBeTruthy();
  });

  test("drag-handles-present", async () => {
    const n = await page.$$eval(".club-section .sec .sec-handle", (els) => els.length);
    expect(n >= 1, `expected at least 1 .sec-handle in .club-section, got ${n}`).toBeTruthy();
  });

  test("reset-button-present", async () => {
    const n = await page.$$eval(".sec-order-reset", (els) => els.length);
    expect(n, `expected 1 .sec-order-reset on leaderboard page, got ${n}`).toBe(1);
  });

  test("drag-to-reorder-works", async () => {
    const secCount = await page.$$eval(".club-section:first-child .sec[data-sid]", (els) => els.length);
    if (secCount < 2) return;
    await page.evaluate(() => {
      const cs = document.querySelector(".club-section");
      if (!cs) return;
      const secs = Array.from(cs.querySelectorAll(".sec[data-sid]"));
      if (secs.length < 2) return;
      const src = secs[0], tgt = secs[1];
      const handle = src.querySelector(".sec-handle");
      if (!handle) return;
      handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
      const rect = tgt.getBoundingClientRect();
      tgt.dispatchEvent(new MouseEvent("drop", { bubbles: true, cancelable: true, clientY: rect.top + rect.height - 1 }));
      handle.dispatchEvent(new Event("dragend", { bubbles: true }));
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-lb-sec")); } catch (_) { return null; }
    });
    expect(Array.isArray(saved) && saved.length >= 1, "expected saved order in localStorage after drag").toBeTruthy();
  });

  test("reset-button-restores-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector(".sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval(".club-section .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    expect(sids.length >= 1, "expected at least one .sec in club after reset").toBeTruthy();
    expect(sids[0], `after reset, expected "table" first in club, got "${sids[0]}"`).toBe("table");
    await page.evaluate(() => { try { localStorage.removeItem("ssb-lb-sec"); } catch (_) {} });
  });
});
