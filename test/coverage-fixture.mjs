import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { expect, test as base } from "@playwright/test";
import { getPageInfo } from "./coverage-utils.mjs";

const outputDir = path.resolve(process.env.COVERAGE_OUTPUT_DIR || "coverage-data");
const trackers = new WeakMap();

function getFirstPartyScriptUrl(rawUrl, documentUrl) {
  const document = getPageInfo(documentUrl);
  // Do not attribute anonymous scripts, including Playwright's injected helpers, to the app.
  if (!document || !rawUrl) return null;

  let scriptUrl;
  try {
    scriptUrl = new URL(rawUrl);
  } catch {
    return null;
  }

  if (scriptUrl.origin !== new URL(document.url).origin) return null;
  return `${scriptUrl.origin}${scriptUrl.pathname}`;
}

function createCoverageTracker() {
  const sessions = new Set();
  const pages = new WeakMap();

  async function track(page) {
    const existing = pages.get(page);
    if (existing) return existing.proxy;

    const client = await page.context().newCDPSession(page);
    const scripts = new Map();
    const record = {
      page,
      client,
      scripts,
      proxy: null,
      finished: null,
    };

    client.on("Debugger.scriptParsed", (script) => {
      const documentUrl = page.url();
      const pageInfo = getPageInfo(documentUrl);
      const scriptUrl = getFirstPartyScriptUrl(script.url, documentUrl);
      if (!pageInfo || !scriptUrl) return;

      const source = client
        .send("Debugger.getScriptSource", { scriptId: script.scriptId })
        .then(({ scriptSource }) => {
          if (typeof scriptSource !== "string") {
            throw new Error(`No source returned for ${scriptUrl}`);
          }
          return {
            source: scriptSource,
            url: scriptUrl,
            pageInfo,
            scriptStart: `${script.startLine}:${script.startColumn}`,
          };
        });
      source.catch(() => {});
      scripts.set(script.scriptId, source);
    });

    try {
      await client.send("Debugger.enable");
      await client.send("Profiler.enable");
      await client.send("Profiler.startPreciseCoverage", {
        callCount: true,
        detailed: true,
      });
    } catch (error) {
      await client.detach();
      throw error;
    }

    record.finish = async () => {
      if (record.finished) return record.finished;
      record.finished = (async () => {
        try {
          const { result } = await client.send("Profiler.takePreciseCoverage");
          await client.send("Profiler.stopPreciseCoverage");

          const entries = [];
          for (const coverage of result) {
            const source = scripts.get(coverage.scriptId);
            if (!source) continue;

            const metadata = await source;
            entries.push({
              ...metadata,
              functions: coverage.functions,
            });
          }

          if (entries.length > 0) {
            await fs.mkdir(outputDir, { recursive: true });
            await fs.writeFile(
              path.join(outputDir, `${randomUUID()}.json`),
              `${JSON.stringify(entries)}\n`,
              "utf8",
            );
          }
        } finally {
          await client.detach();
        }
      })();
      return record.finished;
    };

    record.proxy = new Proxy(page, {
      get(target, property) {
        if (property === "close") {
          return async (...args) => {
            await record.finish();
            return target.close(...args);
          };
        }
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });

    pages.set(page, record);
    pages.set(record.proxy, record);
    sessions.add(record);
    return record.proxy;
  }

  async function finish(page) {
    const record = pages.get(page);
    if (record) await record.finish();
  }

  async function finishContext(context) {
    await Promise.all(
      [...sessions]
        .filter((record) => record.page.context() === context)
        .map((record) => record.finish()),
    );
  }

  async function finishAll() {
    const results = await Promise.allSettled(
      [...sessions].map((record) => record.finish()),
    );
    const errors = results
      .filter((result) => result.status === "rejected")
      .map((result) => result.reason);
    if (errors.length > 0) {
      throw new AggregateError(errors, "Failed to collect Playwright JavaScript coverage");
    }
  }

  return { finish, finishAll, finishContext, track };
}

export const test = base.extend({
  browser: [
    async ({ browser }, use) => {
      const tracker = createCoverageTracker();
      const trackedBrowser = new Proxy(browser, {
        get(target, property) {
          if (property === "newPage") {
            return async (...args) => tracker.track(await target.newPage(...args));
          }
          if (property === "newContext") {
            return async (...args) => {
              const context = await target.newContext(...args);
              return new Proxy(context, {
                get(contextTarget, contextProperty) {
                  if (contextProperty === "newPage") {
                    return async (...pageArgs) =>
                      tracker.track(await contextTarget.newPage(...pageArgs));
                  }
                  if (contextProperty === "close") {
                    return async (...closeArgs) => {
                      await tracker.finishContext(contextTarget);
                      return contextTarget.close(...closeArgs);
                    };
                  }
                  const value = Reflect.get(contextTarget, contextProperty, contextTarget);
                  return typeof value === "function"
                    ? value.bind(contextTarget)
                    : value;
                },
              });
            };
          }
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });

      trackers.set(browser, tracker);
      trackers.set(trackedBrowser, tracker);
      await fs.mkdir(outputDir, { recursive: true });
      try {
        await use(trackedBrowser);
      } finally {
        await tracker.finishAll();
      }
    },
    { scope: "worker" },
  ],
  page: async ({ browser, page }, use) => {
    const tracker = trackers.get(browser);
    if (!tracker) throw new Error("Playwright coverage tracker was not initialized");

    const trackedPage = await tracker.track(page);
    try {
      await use(trackedPage);
    } finally {
      await tracker.finish(page);
    }
  },
});

export { expect };
