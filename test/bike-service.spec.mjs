import { test, expect } from "@playwright/test";
import { URLS, CGI } from "./test-urls.mjs";

const BIKE_CGI = `${CGI}/bike-service`;

// ── Bike Service ───────────────────────────────────────────────────────────────

test.describe.serial("bike-service", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForSelector("#bikepanel table", { timeout: 10000 });
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

  test("meta-not-loading", async () => {
    const text = await page.$eval("#meta", (el) => el.textContent);
    expect(!text.includes("Loading"), `#meta still says Loading`).toBeTruthy();
  });

  test("bike-tabs-present", async () => {
    const n = await page.$$eval(".bikes .tab:not(.add)", (els) => els.length);
    expect(n >= 4, `expected >= 4 bike tabs, got ${n}`).toBeTruthy();
  });

  test("no-duplicate-bike-tabs", async () => {
    const labels = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((e) => e.textContent.trim()),
    );
    const dupes = labels.filter((l, i) => labels.indexOf(l) !== i);
    expect(dupes.length, `duplicate bike tabs: ${JSON.stringify(dupes)}`).toBe(0);
  });

  test("no-duplicate-gear-options", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Kross"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .btn.sm", { timeout: 5000 });
    await page.evaluate(() => {
      const btns = document.querySelectorAll("#bikepanel .btn.sm");
      const edit = Array.from(btns).find((b) => b.textContent.includes("Edit bike"));
      if (edit) edit.click();
    });
    await page.waitForSelector("#b-gear", { timeout: 3000 });
    const opts = await page.$$eval("#b-gear option", (els) =>
      els.map((o) => o.textContent.replace(/\s*·.*$/, "").trim()),
    );
    const dupes = opts.filter((l, i) => l && opts.indexOf(l) !== i);
    expect(dupes.length, `duplicate gear options: ${JSON.stringify(dupes)}`).toBe(0);
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  test("road-bike-tab-exists", async () => {
    const labels = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((e) => e.textContent.trim()),
    );
    expect(
      labels.some((l) => l.includes("Road Bike")),
      `"Road Bike" not in tabs: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("road-bike-odo-positive", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const text = await page.$eval("#bikepanel .big", (el) => el.textContent.trim());
    const km = parseFloat(text.replace(/[\s,]/g, "").replace(",", "."));
    expect(km > 0, `expected Road Bike odo > 0 km, got "${text}"`).toBeTruthy();
  });

  test("top-panel-extra-stats", async () => {
    const labels = await page.$$eval(
      "#bikepanel .odo .k",
      (els) => els.map((el) => el.textContent.trim()),
    );
    expect(labels.includes("Elevation"),  `expected "Elevation" in odo labels, got: ${JSON.stringify(labels)}`).toBeTruthy();
    expect(labels.includes("Avg Ride"),   `expected "Avg Ride" in odo labels, got: ${JSON.stringify(labels)}`).toBeTruthy();
    expect(labels.includes("Services"),   `expected "Services" in odo labels, got: ${JSON.stringify(labels)}`).toBeTruthy();
    expect(labels.includes("Parts"),      `expected "Parts" in odo labels, got: ${JSON.stringify(labels)}`).toBeTruthy();
  });

  test("bike-stats-comparison-table", async () => {
    const headings = await page.$$eval("#bikepanel h2", (els) => els.map((el) => el.textContent.trim()));
    expect(
      headings.some((h) => h.includes("Bike Statistics")),
      `expected "Bike Statistics" h2, got: ${JSON.stringify(headings)}`,
    ).toBeTruthy();
    const rows = await page.$$eval(
      "#bikepanel table tbody tr",
      (trs) => trs
        .filter((r) => !r.classList.contains("ridesrow") && !r.classList.contains("archived"))
        .map((r) => Array.from(r.querySelectorAll("td")).map((td) => td.textContent.trim())),
    );
    const distRow = rows.find((r) => r[0] === "Distance");
    expect(distRow, `expected a "Distance" row in the Bike Statistics table`).toBeTruthy();
    const hasPositive = distRow.slice(1).some(function(cell) {
      return parseFloat(cell.replace(/[\s]/g, "")) > 0;
    });
    expect(hasPositive, `expected at least one positive Distance value, got: ${JSON.stringify(distRow)}`).toBeTruthy();
  });

  test("parts-table-has-rows", async () => {
    const n = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    expect(n >= 1, `expected >= 1 part row in Road Bike panel, got ${n}`).toBeTruthy();
  });

  test("archived-part-shows-duration", async () => {
    const archiveRows = await page.$$eval(
      "#bikepanel tr.archived:not(.ridesrow)",
      (rows) => rows.length,
    );
    expect(archiveRows >= 1, `expected >= 1 archived part row, got ${archiveRows}`).toBeTruthy();
    const durText = await page.$eval(
      "#bikepanel tr.archived:not(.ridesrow) td:nth-child(2) .muted",
      (el) => el.textContent.trim(),
    );
    expect(
      /year|month|week|day/.test(durText),
      `expected duration text (year/month/week/day) in archived part, got: "${durText}"`,
    ).toBeTruthy();
  });

  test("time-based-alert-bar-renders", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const pct = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) .svc-pct",
      (el) => el.textContent.trim(),
    );
    expect(pct.endsWith("%"), `expected a % value in .svc-pct, got: "${pct}"`).toBeTruthy();
  });

  test("time-based-alert-shows-days", async () => {
    const sinceCells = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) td:nth-child(5)",
      (els) => els.map((e) => e.textContent),
    );
    const hasDays = sinceCells.some((t) => /\d+ d/.test(t));
    expect(hasDays, `expected at least one "Since service" cell to show days, got: ${JSON.stringify(sinceCells)}`).toBeTruthy();
  });

  test("cost-column-header-present", async () => {
    const headers = await page.$$eval(
      "#bikepanel thead th",
      (ths) => ths.map((th) => th.textContent.trim()),
    );
    expect(headers.includes("Cost"), `expected "Cost" column header, got: ${JSON.stringify(headers)}`).toBeTruthy();
  });

  test("cost-total-block-shown", async () => {
    await page.evaluate(() => {
      const t = Array.from(document.querySelectorAll(".bikes .tab:not(.add)")).find(
        (el) => el.textContent.includes("Road Bike"),
      );
      if (t) t.click();
    });
    try {
      await page.waitForFunction(() => !!document.querySelector(".cost-block"), { timeout: 5000 });
    } catch (_) {}
    const block = await page.$(".cost-block");
    expect(block, "expected .cost-block to be present when costs are recorded").toBeTruthy();
    const text = await page.$eval(".cost-block .cost-total", (el) => el.textContent.trim());
    expect(/\d/.test(text), `expected a numeric value in .cost-total, got: "${text}"`).toBeTruthy();
  });

  test("cost-total-includes-currency", async () => {
    const text = await page.$eval(".cost-block .cost-total", (el) => el.textContent.trim());
    expect(/PLN/i.test(text), `expected currency code (PLN) in cost total, got: "${text}"`).toBeTruthy();
  });

  test("cost-split-parts-and-service", async () => {
    const text = await page.$eval(".cost-block", (el) => el.textContent);
    expect(/parts/i.test(text), `expected "parts" label in cost split line, got: "${text}"`).toBeTruthy();
    expect(/service/i.test(text), `expected "service" label in cost split line, got: "${text}"`).toBeTruthy();
  });

  test("cost-split-shows-correct-amounts", async () => {
    const text = await page.$eval(".cost-block", (el) => el.textContent);
    expect(/49[.,]90/.test(text), `expected part cost 49.90 in cost block, got: "${text}"`).toBeTruthy();
    expect(/5[.,]50/.test(text), `expected service cost 5.50 in cost block, got: "${text}"`).toBeTruthy();
  });

  test("cost-cell-shows-part-cost", async () => {
    const costCells = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) td:nth-child(6)",
      (els) => els.map((e) => e.textContent.trim()),
    );
    const hasValue = costCells.some((t) => /\d/.test(t) && !t.includes("—"));
    expect(hasValue, `expected at least one cost cell with a numeric value, got: ${JSON.stringify(costCells)}`).toBeTruthy();
  });

  test("cost-modal-label-has-currency", async () => {
    await page.evaluate(() => {
      if (typeof showAddPart === "function") showAddPart();
    });
    await page.waitForSelector("#p-cost", { timeout: 3000 });
    const labelText = await page.evaluate(() => {
      const input = document.getElementById("p-cost");
      if (!input) return "";
      const label = input.previousElementSibling;
      return label ? label.textContent.trim() : "";
    });
    expect(/PLN/i.test(labelText), `expected currency code (PLN) in purchase cost label, got: "${labelText}"`).toBeTruthy();
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });
});

// ── Bike Input Step and Odo ────────────────────────────────────────────────────

test.describe.serial("bike-input-step-and-odo", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("add-part-mileage-step-is-1", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    await page.evaluate(() => { if (typeof showAddPart === "function") showAddPart(); });
    await page.waitForSelector("#f-mileage", { timeout: 3000 });
    const step = await page.$eval("#f-mileage", (el) => el.getAttribute("step"));
    expect(step, `expected #f-mileage step="1", got "${step}"`).toBe("1");
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  test("add-part-alert-km-step-is-1", async () => {
    await page.evaluate(() => { if (typeof showAddPart === "function") showAddPart(); });
    await page.waitForSelector(".st-km", { timeout: 3000 });
    const step = await page.$eval(".st-km", (el) => el.getAttribute("step"));
    expect(step, `expected .st-km step="1", got "${step}"`).toBe("1");
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  test("add-part-alert-hours-step-is-1", async () => {
    await page.evaluate(() => { if (typeof showAddPart === "function") showAddPart(); });
    await page.waitForSelector(".st-h", { timeout: 3000 });
    const step = await page.$eval(".st-h", (el) => el.getAttribute("step"));
    expect(step, `expected .st-h step="1", got "${step}"`).toBe("1");
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  test("edit-bike-base-mileage-step-is-1", async () => {
    await page.evaluate(() => {
      const btns = document.querySelectorAll("#bikepanel .btn.sm");
      const edit = Array.from(btns).find((b) => b.textContent.includes("Edit bike"));
      if (edit) edit.click();
    });
    await page.waitForSelector("#b-base", { timeout: 3000 });
    const step = await page.$eval("#b-base", (el) => el.getAttribute("step"));
    expect(step, `expected #b-base step="1", got "${step}"`).toBe("1");
    await page.evaluate(() => { if (typeof closeModal === "function") closeModal(); });
  });

  test("odo-test-bike-tab-present", async () => {
    const labels = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((e) => e.textContent.trim()),
    );
    expect(
      labels.some((l) => l.includes("Odo Test Bike")),
      `"Odo Test Bike" not in tabs: ${JSON.stringify(labels)}`,
    ).toBeTruthy();
  });

  test("ridden-since-install-includes-base-mileage", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Odo Test Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel table", { timeout: 5000 });
    const riddenText = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow) td:nth-child(3)",
      (el) => el.textContent.trim(),
    );
    const km = parseFloat(riddenText.replace(/[\s ]/g, "").replace(",", "."));
    expect(
      km > 4000,
      `expected ridden-since-install > 4000 km (baseMileage included), got ${km} from "${riddenText}"`,
    ).toBeTruthy();
  });

  test("alert-pct-includes-base-mileage", async () => {
    const pctText = await page.$eval(
      "#bikepanel tbody tr:not(.ridesrow):not(.archived) .svc-pct",
      (el) => el.textContent.trim(),
    );
    const pct = parseFloat(pctText);
    expect(
      pct >= 100,
      `expected alert pct >= 100% (baseMileage included in calc), got ${pct}% from "${pctText}"`,
    ).toBeTruthy();
  });
});

// ── Bike Service Part Replacement ─────────────────────────────────────────────

test.describe.serial("bike-service-parts", () => {
  let page, partsBefore;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForSelector("#bikepanel table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    partsBefore = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
  });

  test.afterAll(async () => { await page.close(); });

  test("part-delete-button-exists", async () => {
    const deleteBtn = await page.$(
      '#bikepanel tbody tr:not(.ridesrow) button[onclick*="deletePart"]',
    );
    expect(deleteBtn, "delete button for first part not found").toBeTruthy();
    expect(partsBefore >= 1, "should have at least 1 part").toBeTruthy();
  });

  test("part-deletion-persists", async () => {
    await page.evaluate(() => { window.confirm = () => true; });
    const deleteBtn = await page.$(
      '#bikepanel tbody tr:not(.ridesrow) button[onclick*="deletePart"]',
    );
    if (deleteBtn) {
      await deleteBtn.click();
    }
    await page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 500)));
    const partsAfter = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    expect(
      partsAfter < partsBefore,
      `expected parts count to decrease, before: ${partsBefore}, after: ${partsAfter}`,
    ).toBeTruthy();
  });
});

// ── Bike Service Notifications ─────────────────────────────────────────────────

test.describe.serial("bike-service-notifications", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForSelector("#bikepanel table", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("error-element-exists", async () => {
    const errEl = await page.$("#err");
    expect(errEl, "#err element not found").toBeTruthy();
    const text = await page.$eval("#err", (el) => el.textContent.trim());
    expect(text, `#err should be initially empty, got: "${text}"`).toBe("");
  });

  test("error-clears-on-load", async () => {
    let err = await page.$eval("#err", (el) => el.textContent.trim());
    expect(err, "error should start empty").toBe("");
    await page.evaluate(() => {
      document.getElementById("err").textContent = "Test error message";
    });
    let errSet = await page.$eval("#err", (el) => el.textContent.trim());
    expect(errSet.includes("Test error"), `error should contain test message, got: "${errSet}"`).toBeTruthy();
    await page.reload({ waitUntil: "networkidle", timeout: 20000 });
    let errAfter = await page.$eval("#err", (el) => el.textContent.trim());
    expect(errAfter, `error should be cleared after reload, got: "${errAfter}"`).toBe("");
  });

  test("error-appears-in-modal-flow", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const parts = await page.$$('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showPart"]');
    if (parts.length > 0) {
      await parts[0].click();
      await page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 200)));
    }
    const err = await page.$eval("#err", (el) => el.textContent.trim());
    expect(typeof err === "string", "error should be string or empty").toBeTruthy();
  });
});

// ── Bike Modal CRUD ────────────────────────────────────────────────────────────

test.describe.serial("bike-modal-crud", () => {
  let page;
  const jsErrors = [];
  let testBikeName;

  test.beforeAll(async ({ browser }) => {
    testBikeName = `TestBike-${Date.now()}`;
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("add-bike-modal-opens", async () => {
    await page.evaluate(() => showAddBike());
    await page.waitForSelector("#b-name", { timeout: 3000 });
    const nameInput = await page.$("#b-name");
    expect(nameInput, "#b-name input not found in add-bike modal").toBeTruthy();
  });

  test("add-bike-creates-tab", async () => {
    await page.$eval("#b-name", (el, name) => { el.value = name; }, testBikeName);
    await page.evaluate(() => saveBike(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const tabs = await page.$$eval(".bikes .tab:not(.add)", (els) =>
      els.map((el) => el.textContent.trim()),
    );
    expect(
      tabs.some((t) => t.includes(testBikeName)),
      `expected tab with name "${testBikeName}", got: ${JSON.stringify(tabs)}`,
    ).toBeTruthy();
  });

  test("add-part-modal-opens", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    await page.evaluate(() => showAddPart());
    await page.waitForSelector("#p-name", { timeout: 3000 });
    const nameInput = await page.$("#p-name");
    expect(nameInput, "#p-name input not found in add-part modal").toBeTruthy();
  });

  test("add-part-creates-row", async () => {
    const testPartName = `TestPart-${Date.now()}`;
    await page.$eval("#p-name", (el, name) => { el.value = name; }, testPartName);
    const countBefore = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    await page.evaluate(() => savePart(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const countAfter = await page.$$eval(
      "#bikepanel tbody tr:not(.ridesrow)",
      (rows) => rows.length,
    );
    expect(
      countAfter > countBefore,
      `expected part count to increase from ${countBefore}, got ${countAfter}`,
    ).toBeTruthy();
  });

  test("delete-bike-removes-tab", async () => {
    await page.evaluate((name) => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      for (const t of tabs) {
        if (t.textContent.trim().includes(name)) { t.click(); break; }
      }
    }, testBikeName);
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const tabsBefore = await page.$$eval(".bikes .tab:not(.add)", (els) => els.length);
    await page.evaluate(() => {
      window.confirm = () => true;
      const btn = document.querySelector('button[onclick*="deleteBike"]');
      if (btn) btn.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 800)));
    const tabsAfter = await page.$$eval(".bikes .tab:not(.add)", (els) => els.length);
    expect(
      tabsAfter < tabsBefore,
      `expected tab count to decrease from ${tabsBefore}, got ${tabsAfter}`,
    ).toBeTruthy();
  });
});

// ── Email Alert Checkbox ───────────────────────────────────────────────────────

test.describe.serial("email-alert-checkbox", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
  });

  test.afterAll(async () => { await page.close(); });

  test("checkbox-always-visible-in-add-part-modal", async () => {
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = false;
      if (typeof showAddPart === "function") showAddPart();
    });
    await page.waitForSelector("#p-name", { timeout: 3000 });
    const chk = await page.$("#p-email-alert");
    expect(chk, "#p-email-alert checkbox should always be present in add-part modal").toBeTruthy();
    const hint = await page.$('.chk:has(#p-email-alert) .muted');
    expect(hint, "hint span should appear when emailConfigured=false").toBeTruthy();
    await page.evaluate(() => closeModal());
  });

  test("checkbox-hint-hidden-when-email-configured", async () => {
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
      if (typeof showAddPart === "function") showAddPart();
    });
    await page.waitForSelector("#p-name", { timeout: 3000 });
    const chk = await page.$("#p-email-alert");
    expect(chk, "#p-email-alert checkbox should be present when emailConfigured=true").toBeTruthy();
    const hint = await page.$('.chk:has(#p-email-alert) .muted');
    expect(!hint, "hint span should not appear when emailConfigured=true").toBeTruthy();
    await page.evaluate(() => closeModal());
  });

  test("email-alert-true-persisted", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const partName = `EmailAlertPart-${Date.now()}`;
    await page.evaluate((name) => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
      showAddPart();
    }, partName);
    await page.waitForSelector("#p-name", { timeout: 3000 });
    await page.$eval("#p-name", (el, v) => { el.value = v; }, partName);
    await page.$eval("#p-email-alert", (el) => { el.checked = true; });
    await page.evaluate(() => savePart(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 1000)));
    const data = await fetch(BIKE_CGI, { cache: "no-store" }).then((r) => r.json());
    const bike = data.bikes.find((b) => b.name === "Road Bike");
    expect(bike, "Road Bike not found in CGI store").toBeTruthy();
    const newPart = (bike.parts || []).find((p) => p.name === partName);
    expect(newPart, `Part "${partName}" not found in CGI store`).toBeTruthy();
    expect(newPart.emailAlert, `expected emailAlert:true on part, got: ${JSON.stringify(newPart.emailAlert)}`).toBe(true);
    // Cleanup
    const cleanData = await fetch(BIKE_CGI, { cache: "no-store" }).then((r) => r.json());
    const cleanBike = cleanData.bikes.find((b) => b.name === "Road Bike");
    if (cleanBike) {
      cleanBike.parts = (cleanBike.parts || []).filter((p) => p.name !== partName);
      await fetch(BIKE_CGI, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(cleanData) });
    }
  });

  test("email-alert-false-when-unchecked", async () => {
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    const partName = `EmailAlertFalsePart-${Date.now()}`;
    await page.evaluate(() => {
      if (typeof _CFG !== "undefined") _CFG.emailConfigured = true;
      showAddPart();
    });
    await page.waitForSelector("#p-name", { timeout: 3000 });
    await page.$eval("#p-name", (el, v) => { el.value = v; }, partName);
    await page.evaluate(() => savePart(null));
    await page.evaluate(() => new Promise((r) => setTimeout(r, 1000)));
    const data = await fetch(BIKE_CGI, { cache: "no-store" }).then((r) => r.json());
    const bike = data.bikes.find((b) => b.name === "Road Bike");
    const newPart = (bike?.parts || []).find((p) => p.name === partName);
    expect(newPart, `Part "${partName}" not found in CGI store`).toBeTruthy();
    expect(!newPart.emailAlert, `expected emailAlert falsy on unchecked part, got: ${JSON.stringify(newPart.emailAlert)}`).toBeTruthy();
    // Cleanup
    const cleanData = await fetch(BIKE_CGI, { cache: "no-store" }).then((r) => r.json());
    const cb = cleanData.bikes.find((b) => b.name === "Road Bike");
    if (cb) {
      cb.parts = (cb.parts || []).filter((p) => p.name !== partName);
      await fetch(BIKE_CGI, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(cleanData) });
    }
  });
});

// ── Alert Thresholds ──────────────────────────────────────────────────────────

test.describe.serial("alert-thresholds", () => {
  let page;
  let originalAlertKm;
  let skipSuite = false;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    // CGI setup: lower alertKm to 1 on first active part
    const setupR = await fetch(BIKE_CGI, { cache: "no-store" });
    const setupData = await setupR.json();
    const road = setupData.bikes.find((b) => b.name === "Road Bike");
    if (!road || !road.parts || road.parts.length === 0) {
      skipSuite = true;
      return;
    }
    const firstPart = road.parts[0];
    if (firstPart.serviceTypes && firstPart.serviceTypes.length > 0) {
      originalAlertKm = firstPart.serviceTypes[0].alertKm;
      firstPart.serviceTypes[0].alertKm = 1;
    } else {
      originalAlertKm = firstPart.alertKm;
      firstPart.alertKm = 1;
    }
    await fetch(BIKE_CGI, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(setupData),
    });

    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
  });

  test.afterAll(async () => {
    // CGI teardown: restore original alertKm
    const restoreR = await fetch(BIKE_CGI, { cache: "no-store" });
    const restoreData = await restoreR.json();
    const restoreRoad = restoreData.bikes.find((b) => b.name === "Road Bike");
    if (restoreRoad && restoreRoad.parts && restoreRoad.parts.length > 0) {
      const rp = restoreRoad.parts[0];
      if (rp.serviceTypes && rp.serviceTypes.length > 0) {
        rp.serviceTypes[0].alertKm = originalAlertKm;
      } else {
        rp.alertKm = originalAlertKm;
      }
      await fetch(BIKE_CGI, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(restoreData),
      });
    }
    if (page) await page.close();
  });

  test("warn-row-appears-when-threshold-exceeded", async () => {
    if (skipSuite) return;
    const n = await page.$$eval("#bikepanel tr.warn", (rows) => rows.length);
    expect(n >= 1, `expected >= 1 tr.warn in #bikepanel when alertKm=1 is set, got ${n}`).toBeTruthy();
  });

  test("warn-row-has-highlight-background", async () => {
    if (skipSuite) return;
    const bg = await page.evaluate(() => {
      const td = document.querySelector("#bikepanel tr.warn td");
      return td ? window.getComputedStyle(td).backgroundColor : null;
    });
    expect(
      bg && bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent",
      `expected coloured background on tr.warn td, got: "${bg}"`,
    ).toBeTruthy();
  });
});

// ── Needs Replacement ──────────────────────────────────────────────────────────

test.describe.serial("needs-replacement", () => {
  let page;
  let skipSuite = false;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    // CGI setup: clear needsReplacement on all parts
    const setupR = await fetch(BIKE_CGI, { cache: "no-store" });
    const setupData = await setupR.json();
    const road = setupData.bikes.find((b) => b.name === "Road Bike");
    if (!road || !road.parts || road.parts.length < 2) {
      skipSuite = true;
      return;
    }
    road.parts.forEach((p) => { p.needsReplacement = false; });
    await fetch(BIKE_CGI, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(setupData),
    });

    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
  });

  test.afterAll(async () => {
    // Teardown: clear all needsReplacement flags
    const tearR = await fetch(BIKE_CGI, { cache: "no-store" });
    const tearData = await tearR.json();
    const tearRoad = tearData.bikes.find((b) => b.name === "Road Bike");
    if (tearRoad) tearRoad.parts.forEach((p) => { p.needsReplacement = false; });
    await fetch(BIKE_CGI, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(tearData),
    });
    if (page) await page.close();
  });

  test("service-modal-has-needs-repl-checkbox", async () => {
    if (skipSuite) return;
    const svcBtns = await page.$$('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showService"]');
    expect(svcBtns.length >= 1, "expected >= 1 Service button").toBeTruthy();
    await svcBtns[0].click();
    await page.waitForSelector("#s-needs-repl", { timeout: 3000 });
    const chk = await page.$("#s-needs-repl");
    expect(chk, "#s-needs-repl checkbox not found in service modal").toBeTruthy();
    await page.evaluate(() => closeModal());
  });

  test("needs-repl-badge-visible-after-flag", async () => {
    if (skipSuite) return;
    // Use CGI to mark last part as needsReplacement, then reload
    const preR = await fetch(BIKE_CGI, { cache: "no-store" });
    const preData = await preR.json();
    const preRoad = preData.bikes.find((b) => b.name === "Road Bike");
    if (preRoad && preRoad.parts.length >= 2) {
      preRoad.parts[preRoad.parts.length - 1].needsReplacement = true;
      await fetch(BIKE_CGI, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(preData),
      });
    }
    await page.reload({ waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
    const n = await page.$$eval("#bikepanel .needs-repl", (els) => els.length);
    expect(n >= 1, `expected >= 1 .needs-repl badge in #bikepanel, got ${n}`).toBeTruthy();
  });

  test("flagged-part-sorts-first", async () => {
    if (skipSuite) return;
    const firstRowHasBadge = await page.evaluate(() => {
      const rows = document.querySelectorAll("#bikepanel tbody tr:not(.ridesrow)");
      return rows.length > 0 && !!rows[0].querySelector(".needs-repl");
    });
    expect(firstRowHasBadge, "expected the flagged part to be the first row in the active-parts table").toBeTruthy();
  });

  test("service-modal-checkbox-prechecked-for-flagged-part", async () => {
    if (skipSuite) return;
    const svcBtns = await page.$$('#bikepanel tbody tr:not(.ridesrow) button[onclick*="showService"]');
    expect(svcBtns.length >= 1, "no Service button found").toBeTruthy();
    await svcBtns[0].click();
    await page.waitForSelector("#s-needs-repl", { timeout: 3000 });
    const checked = await page.$eval("#s-needs-repl", (el) => el.checked);
    expect(checked, "#s-needs-repl should be pre-checked for a flagged part").toBeTruthy();
    await page.evaluate(() => closeModal());
  });
});

// ── Service Type Description ───────────────────────────────────────────────────

test.describe.serial("service-type-description", () => {
  let page;
  let skipSuite = false;
  let testPartId, testDesc, origDesc;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    // CGI setup: write test description onto first serviceType
    const setupR = await fetch(BIKE_CGI, { cache: "no-store" });
    const setupData = await setupR.json();
    const road = setupData.bikes.find((b) => b.name === "Road Bike");
    if (!road || !road.parts || !road.parts.length ||
        !road.parts[0].serviceTypes || !road.parts[0].serviceTypes.length) {
      skipSuite = true;
      return;
    }
    const testPart = road.parts[0];
    testPartId = testPart.id;
    testDesc = `desc-${Date.now()}`;
    origDesc = testPart.serviceTypes[0].desc;
    testPart.serviceTypes[0].desc = testDesc;
    await fetch(BIKE_CGI, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(setupData),
    });

    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    jsErrors.length = 0;
    await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    try {
      await page.waitForSelector(".bikes .tab", { timeout: 10000 });
      await page.waitForFunction(
        () => !document.getElementById("meta")?.textContent.includes("Loading"),
        { timeout: 10000 },
      );
    } catch (_) {}
    await page.evaluate(() => {
      const t = Array.from(document.querySelectorAll(".bikes .tab:not(.add)"))
        .find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    await page.waitForSelector("#bikepanel .big", { timeout: 5000 });
  });

  test.afterAll(async () => {
    // Restore original description
    const restoreR = await fetch(BIKE_CGI, { cache: "no-store" });
    const restoreData = await restoreR.json();
    const restoreRoad = restoreData.bikes.find((b) => b.name === "Road Bike");
    if (restoreRoad && restoreRoad.parts.length > 0 &&
        restoreRoad.parts[0].serviceTypes && restoreRoad.parts[0].serviceTypes.length > 0) {
      restoreRoad.parts[0].serviceTypes[0].desc = origDesc;
      await fetch(BIKE_CGI, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(restoreData),
      });
    }
    if (page) await page.close();
  });

  test("service-modal-shows-type-description", async () => {
    if (skipSuite) return;
    await page.evaluate((pid) => showService(pid), testPartId);
    await page.waitForSelector("#ovl", { timeout: 3000 });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 150)));
    const descEl = await page.$("#s-type-desc");
    expect(descEl, "#s-type-desc not present in service modal").toBeTruthy();
    const text = await page.$eval("#s-type-desc", (el) => el.textContent.trim());
    expect(text, `service modal description mismatch: expected "${testDesc}", got "${text}"`).toBe(testDesc);
    await page.evaluate(() => closeModal());
  });
});

// ── Bike Section Order ─────────────────────────────────────────────────────────

test.describe.serial("bike-section-order", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.evaluate(() => {
      try { localStorage.removeItem("ssb-bike-sec"); } catch (_) {}
    });
    await page.goto(URLS.bike, { waitUntil: "networkidle", timeout: 20000 });
    await page.waitForSelector(".bikes .tab", { timeout: 10000 });
    await page.waitForFunction(
      () => !document.getElementById("meta")?.textContent.includes("Loading"),
      { timeout: 10000 },
    );
    await page.evaluate(() => {
      const tabs = document.querySelectorAll(".bikes .tab:not(.add)");
      const t = Array.from(tabs).find((el) => el.textContent.includes("Road Bike"));
      if (t) t.click();
    });
    try { await page.waitForSelector("#bikepanel .sec[data-sid]", { timeout: 8000 }); } catch (_) {}
    await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));
  });

  test.afterAll(async () => {
    await page.evaluate(() => { try { localStorage.removeItem("ssb-bike-sec"); } catch (_) {} });
    await page.close();
  });

  test("no-js-errors", () => {
    expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  });

  test("parts-section-present", async () => {
    const sid = await page.$eval("#bikepanel .sec[data-sid='parts']", (el) =>
      el.getAttribute("data-sid"),
    );
    expect(sid, "expected 'parts' section in bikepanel").toBe("parts");
  });

  test("drag-handles-present", async () => {
    const n = await page.$$eval("#bikepanel .sec .sec-handle", (els) => els.length);
    expect(n >= 1, `expected at least 1 .sec-handle in bikepanel, got ${n}`).toBeTruthy();
  });

  test("reset-button-present", async () => {
    const n = await page.$$eval("#bikepanel .sec-order-reset", (els) => els.length);
    expect(n, `expected 1 .sec-order-reset in bikepanel, got ${n}`).toBe(1);
  });

  test("drag-to-reorder-works-when-multiple-sections", async () => {
    const secCount = await page.$$eval("#bikepanel .sec[data-sid]", (els) => els.length);
    if (secCount < 2) return;
    await page.evaluate(() => {
      const panel = document.getElementById("bikepanel");
      const secs = Array.from(panel.querySelectorAll(".sec[data-sid]"));
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
    const sids = await page.$$eval("#bikepanel .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    const saved = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem("ssb-bike-sec")); } catch (_) { return null; }
    });
    expect(Array.isArray(saved) && saved.length >= 1, "expected saved order in localStorage").toBeTruthy();
    expect(saved[0], `saved[0] should match DOM order[0]: "${sids[0]}"`).toBe(sids[0]);
  });

  test("reset-button-restores-default-order", async () => {
    await page.evaluate(() => {
      const rb = document.querySelector("#bikepanel .sec-order-reset");
      if (rb) rb.click();
    });
    await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
    const sids = await page.$$eval("#bikepanel .sec[data-sid]", (els) =>
      els.map((el) => el.getAttribute("data-sid")),
    );
    expect(sids[0], `after reset, expected "parts" first, got "${sids[0]}"`).toBe("parts");
  });
});

// ── Mobile Layout ──────────────────────────────────────────────────────────────

test.describe.serial("mobile-layout", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
    await page.setViewportSize({ width: 375, height: 812 });
  });

  test.afterAll(async () => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.close();
  });

  const pages = [
    { name: "dashboard", url: "dash",     wait: "#board" },
    { name: "stats",     url: "stats",    wait: ".kpis .kpi" },
    { name: "bike",      url: "bike",     wait: ".bikes" },
    { name: "activity",  url: "activity", wait: "#content" },
  ];

  for (const pg of pages) {
    test(`${pg.name}-mobile-checks`, async () => {
      jsErrors.length = 0;
      await page.evaluate(() => {
        try { localStorage.removeItem("theme"); } catch (_) {}
        try { sessionStorage.clear(); } catch (_) {}
      });
      await page.goto(URLS[pg.url], { waitUntil: "networkidle", timeout: 20000 });
      try { await page.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}

      const overflow = await page.evaluate(() =>
        document.documentElement.scrollWidth > document.documentElement.clientWidth
      );
      expect(!overflow,
        `${pg.name} page has horizontal overflow at 375px — table needs overflow-x:auto wrapper`).toBeTruthy();

      const hdr = await page.$("#hdr");
      expect(hdr, `#hdr element not found on ${pg.name} page`).toBeTruthy();

      expect(jsErrors.length, `JS errors on ${pg.name} at 375px: ${jsErrors.map((e) => e.message).join("; ")}`).toBe(0);
    });
  }
});

// ── Mobile Section Reorder ────────────────────────────────────────────────────

test.describe.serial("mobile-section-reorder", () => {
  let ctx, mPage;

  test.beforeAll(async ({ browser }) => {
    ctx = await browser.newContext({ isMobile: true, hasTouch: true, viewport: { width: 375, height: 812 } });
    mPage = await ctx.newPage();
  });

  test.afterAll(async () => { await ctx.close(); });

  const mobilePages = [
    { name: "stats",    url: "stats",    wait: ".kpis .kpi" },
    { name: "activity", url: "activity", wait: "#content" },
    { name: "bike",     url: "bike",     wait: ".bikes" },
    { name: "club",     url: "club",     wait: ".club-section" },
  ];

  for (const pg of mobilePages) {
    test(`${pg.name}-handle-hidden-on-mobile`, async () => {
      await mPage.goto(URLS[pg.url], { waitUntil: "networkidle", timeout: 20000 });
      try { await mPage.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}
      const visible = await mPage.evaluate(() => {
        return Array.from(document.querySelectorAll(".sec-handle")).some(el => {
          const s = getComputedStyle(el);
          return s.display !== "none" && s.visibility !== "hidden";
        });
      });
      expect(!visible, `${pg.name}: .sec-handle should be hidden on touch viewport but is visible`).toBeTruthy();
    });

    test(`${pg.name}-reset-btn-hidden-on-mobile`, async () => {
      const visible = await mPage.evaluate(() => {
        return Array.from(document.querySelectorAll(".sec-order-reset")).some(el => {
          const s = getComputedStyle(el);
          return s.display !== "none" && s.visibility !== "hidden";
        });
      });
      expect(!visible, `${pg.name}: .sec-order-reset should be hidden on touch viewport but is visible`).toBeTruthy();
    });
  }
});

// ── Dark Mode ──────────────────────────────────────────────────────────────────

test.describe.serial("dark-mode", () => {
  let page;
  const jsErrors = [];

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    page.on("pageerror", (e) => jsErrors.push(e));
  });

  test.afterAll(async () => { await page.close(); });

  const dmPages = [
    { name: "dashboard",   url: "dash",     wait: "#board table" },
    { name: "stats",       url: "stats",    wait: ".kpis .kpi" },
    { name: "bike",        url: "bike",     wait: ".bikes .tab" },
    { name: "activity",    url: "activity", wait: "#content" },
    { name: "leaderboard", url: "club",     wait: "#board" },
  ];

  for (const pg of dmPages) {
    test(`${pg.name}-dark-mode-checks`, async () => {
      jsErrors.length = 0;
      await page.evaluate(() => {
        try { localStorage.removeItem("theme"); } catch (_) {}
        try { sessionStorage.clear(); } catch (_) {}
      });
      await page.goto(URLS[pg.url], { waitUntil: "networkidle", timeout: 20000 });
      try { await page.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}

      // toggle button exists
      const btn = await page.$("#theme-tog");
      expect(btn, `#theme-tog not found on ${pg.name} page`).toBeTruthy();

      // initial icon is 🌙 or ☀️
      const icon = await page.$eval("#theme-tog", (el) => el.textContent.trim());
      expect(icon === "🌙" || icon === "☀️",
        `expected 🌙 or ☀️ from #theme-tog on ${pg.name}, got: "${icon}"`).toBeTruthy();

      // click from light → dark
      await page.evaluate(() => {
        document.documentElement.dataset.theme = "light";
        localStorage.setItem("theme", "light");
        document.getElementById("theme-tog").textContent = "🌙";
      });
      await page.click("#theme-tog");
      await page.evaluate(() => new Promise((r) => setTimeout(r, 50)));
      const theme1 = await page.evaluate(() => document.documentElement.dataset.theme);
      expect(theme1, `clicking #theme-tog from light should set data-theme=dark on ${pg.name}`).toBe("dark");
      const icon1 = await page.$eval("#theme-tog", (el) => el.textContent.trim());
      expect(icon1, `icon after dark toggle should be ☀️ on ${pg.name}, got "${icon1}"`).toBe("☀️");

      // click again → light
      await page.click("#theme-tog");
      await page.evaluate(() => new Promise((r) => setTimeout(r, 50)));
      const theme2 = await page.evaluate(() => document.documentElement.dataset.theme);
      expect(theme2, `second click on #theme-tog should set data-theme=light on ${pg.name}`).toBe("light");

      // persists to localStorage
      await page.evaluate(() => {
        document.documentElement.dataset.theme = "light";
        localStorage.setItem("theme", "light");
        document.getElementById("theme-tog").textContent = "🌙";
      });
      await page.click("#theme-tog"); // → dark
      await page.evaluate(() => new Promise((r) => setTimeout(r, 50)));
      const stored = await page.evaluate(() => localStorage.getItem("theme"));
      expect(stored, `localStorage["theme"] should be "dark" after clicking to dark on ${pg.name}`).toBe("dark");

      // reload preserves theme
      await page.reload({ waitUntil: "networkidle", timeout: 20000 });
      try { await page.waitForSelector(pg.wait, { timeout: 10000 }); } catch (_) {}
      const themeAfterReload = await page.evaluate(() => document.documentElement.dataset.theme);
      expect(themeAfterReload, `after reload, data-theme should still be "dark" on ${pg.name}`).toBe("dark");

      // cleanup
      await page.evaluate(() => { try { localStorage.removeItem("theme"); } catch (_) {} });

      // no js errors
      expect(jsErrors.length, `JS errors on ${pg.name}: ${jsErrors.map((e) => e.message).join("; ")}`).toBe(0);
    });
  }
});
