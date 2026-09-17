import { test, expect } from "@playwright/test";
import { CGI } from "./test-urls.mjs";

// ── CGI: Bike Service ─────────────────────────────────────────────────────────

test.describe.serial("cgi-bike-service", () => {
  const ENDPOINT = `${CGI}/bike-service`;

  test("GET-returns-json", async () => {
    const r = await fetch(ENDPOINT, { cache: "no-store" });
    expect(r.status, `expected 200, got ${r.status}`).toBe(200);
    const ct = r.headers.get("content-type") ?? "";
    expect(ct.includes("json"), `expected JSON content-type, got: ${ct}`).toBeTruthy();
    const data = await r.json();
    expect(Array.isArray(data.bikes), "data.bikes is not an Array").toBeTruthy();
    expect(
      data.bikes.length >= 4,
      `expected >= 4 bikes, got ${data.bikes.length}`,
    ).toBeTruthy();
  });

  test("GET-has-road-bike-parts", async () => {
    const r = await fetch(ENDPOINT, { cache: "no-store" });
    const data = await r.json();
    const road = data.bikes.find((b) => b.name === "Road Bike");
    expect(road, '"Road Bike" not in bikes array').toBeTruthy();
    expect(
      Array.isArray(road.parts) && road.parts.length >= 1,
      `Road Bike.parts is empty or not an array`,
    ).toBeTruthy();
  });

  test("POST-service-note-persists", async () => {
    const getR = await fetch(ENDPOINT, { cache: "no-store" });
    const current = await getR.json();
    const testNote = `test-service-${Date.now()}`;

    const road = current.bikes.find((b) => b.name === "Road Bike");
    expect(road, '"Road Bike" not found for POST test').toBeTruthy();

    const testPart = road.parts && road.parts.length > 0 ? road.parts[0] : null;
    expect(testPart, "Road Bike has no parts for POST test").toBeTruthy();

    if (!testPart.services) testPart.services = [];
    testPart.services.push({
      id: `s-test-${Date.now()}`,
      date: "2026-06-24",
      mileage: 608,
      note: testNote,
    });

    const postR = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(current),
    });
    expect(postR.ok, `POST failed with status ${postR.status}`).toBeTruthy();

    const verifyR = await fetch(ENDPOINT, { cache: "no-store" });
    const verify = await verifyR.json();
    const vRoad = verify.bikes.find((b) => b.name === "Road Bike");
    const vPart = vRoad?.parts?.find((p) => p.id === testPart.id);
    const found = vPart?.services?.some((s) => s.note === testNote);
    expect(found, `POST'd service note not found on subsequent GET`).toBeTruthy();
  });
});

// ── CGI: Ride Goals ───────────────────────────────────────────────────────────

test.describe.serial("cgi-ride-goals", () => {
  const ENDPOINT = `${CGI}/ride-goals`;

  test.beforeAll(async () => {
    // Reset state
    await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ goals: {} }),
    });
  });

  test("GET-returns-json-with-goals-object", async () => {
    const r = await fetch(ENDPOINT, { cache: "no-store" });
    expect(r.status, `expected 200, got ${r.status}`).toBe(200);
    const ct = r.headers.get("content-type") ?? "";
    expect(ct.includes("json"), `expected JSON content-type, got: ${ct}`).toBeTruthy();
    const data = await r.json();
    expect(
      data.goals !== undefined && typeof data.goals === "object" && !Array.isArray(data.goals),
      `data.goals must be a plain object, got: ${JSON.stringify(data.goals)}`,
    ).toBeTruthy();
  });

  test("POST-goal-persists", async () => {
    const testKm = 7000 + Math.floor(Math.random() * 2000);
    const postR = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ goals: { "2026": testKm } }),
    });
    expect(postR.ok, `POST failed with status ${postR.status}`).toBeTruthy();
    const posted = await postR.json();
    expect(
      posted.goals?.["2026"],
      `POST response does not echo back goal: ${JSON.stringify(posted)}`,
    ).toBe(testKm);
    expect(posted.updatedAt, "POST response missing updatedAt").toBeTruthy();

    const getR = await fetch(ENDPOINT, { cache: "no-store" });
    const got = await getR.json();
    expect(
      got.goals?.["2026"],
      `subsequent GET missing posted goal: ${JSON.stringify(got)}`,
    ).toBe(testKm);
  });

  test("POST-missing-goals-key-400", async () => {
    const r = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ data: {} }),
    });
    expect(r.status, `expected 400 for missing goals key, got ${r.status}`).toBe(400);
  });

  test("POST-goals-as-array-400", async () => {
    const r = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ goals: [8000] }),
    });
    expect(r.status, `expected 400 for goals array, got ${r.status}`).toBe(400);
  });
});
