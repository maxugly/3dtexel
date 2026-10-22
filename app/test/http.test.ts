import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { createLibrary } from "../src/index.js";
import { startHttpServer } from "../src/http-server.js";
import { FakeHttp, fixtureJsonSync, tempHome } from "./support.js";

function polyhavenHttp(): FakeHttp {
  return new FakeHttp({
    json: [
      { match: "https://api.polyhaven.com/assets", value: fixtureJsonSync("polyhaven/assets.json") },
      { match: "https://api.polyhaven.com/info/brick_wall_001", value: fixtureJsonSync("polyhaven/info_brick_wall.json") },
      { match: "https://api.polyhaven.com/files/brick_wall_001", value: fixtureJsonSync("polyhaven/files_brick_wall.json") }
    ]
  });
}

test("HTTP API enforces bearer auth and serves offline provider contracts", async () => {
  const temporary = await tempHome();
  const http = polyhavenHttp();
  const library = await createLibrary({
    home: temporary.home,
    output: path.join(temporary.home, "library"),
    env: { ASSET_LIBRARY_TOKEN: "test-token" },
    http
  });
  const server = await startHttpServer(library, { host: "127.0.0.1", port: 0 });
  const auth = { Authorization: "Bearer test-token" };
  try {
    const health = await fetch(`${server.url}/health`, { headers: auth });
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { ok: true, version: "0.1.0" });

    const unauthorized = await fetch(`${server.url}/v1/providers`);
    assert.equal(unauthorized.status, 401);
    assert.equal(unauthorized.headers.get("www-authenticate"), "Bearer");
    assert.doesNotMatch(await unauthorized.text(), /test-token/);

    const providers = await fetch(`${server.url}/v1/providers`, { headers: auth });
    assert.equal(providers.status, 200);
    const providerBody = await providers.json() as { providers: Array<{ id: string }> };
    assert.equal(providerBody.providers.length, 9);
    assert.ok(providerBody.providers.some((entry) => entry.id === "polyhaven"));

    const search = await fetch(`${server.url}/v1/search?q=brick&category=material&providers=polyhaven`, { headers: auth });
    assert.equal(search.status, 200);
    const searchBody = await search.json() as { assets: Array<{ id: string }> };
    assert.equal(searchBody.assets[0]!.id, "brick_wall_001");

    const planned = await fetch(`${server.url}/v1/assets/polyhaven/brick_wall_001/plan`, {
      method: "POST",
      headers: { ...auth, "Content-Type": "application/json" },
      body: JSON.stringify({ variant: "1k" })
    });
    assert.equal(planned.status, 200);
    const planBody = await planned.json() as { plan: { kind: string; maps: Record<string, unknown> } };
    assert.equal(planBody.plan.kind, "material");
    assert.ok(planBody.plan.maps.albedo);

    const invalid = await fetch(`${server.url}/v1/search?category=bogus`, { headers: auth });
    assert.equal(invalid.status, 400);

    const missing = await fetch(`${server.url}/v1/nope`, { headers: auth });
    assert.equal(missing.status, 404);
  } finally {
    await server.close();
    await library.close();
    await temporary.cleanup();
  }
});

test("HTTP API refuses non-loopback binds without a token", async () => {
  const temporary = await tempHome();
  const library = await createLibrary({
    home: temporary.home,
    output: path.join(temporary.home, "library"),
    env: {},
    http: polyhavenHttp()
  });
  try {
    await assert.rejects(
      () => startHttpServer(library, { host: "0.0.0.0", port: 0 }),
      /non-loopback.*ASSET_LIBRARY_TOKEN/i
    );
  } finally {
    await library.close();
    await temporary.cleanup();
  }
});
