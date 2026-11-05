import assert from "node:assert/strict";
import test from "node:test";
import { BlenderKitProvider } from "../../src/providers/blenderkit.js";
import { context, FakeHttp } from "../support.js";
import searchFixture from "../fixtures/blenderkit/search.json" with { type: "json" };
import detailFixture from "../fixtures/blenderkit/detail.json" with { type: "json" };
import downloadFixture from "../fixtures/blenderkit/download.json" with { type: "json" };

test("blenderkit search, details, and model plan contract", async () => {
  const http = new FakeHttp({
    json: [
      { match: "https://www.blendkit.com/api/v1/search", value: searchFixture },
      { match: "https://www.blendkit.com/api/v1/assets/f7e86d85-9199-4426-b89a-aad9f8734eb6", value: detailFixture },
      { match: "https://www.blendkit.com/api/v1/downloads", value: downloadFixture }
    ]
  });

  const ctx = context(http, {
    BLENDERKIT_API_KEY: "mock_bk_token"
  });

  const provider = new BlenderKitProvider(ctx);
  assert.equal(provider.descriptor().id, "blenderkit");
  assert.equal(provider.descriptor().name, "BlenderKit");
  assert.equal(provider.credentialStatus(), "API token configured.");

  const search = await provider.search({ query: "assassin", category: "model", limit: 24 });
  assert.ok(search.items.length > 0);
  const asset = search.items[0]!;
  assert.equal(asset.id, "f7e86d85-9199-4426-b89a-aad9f8734eb6");
  assert.ok(asset.title.includes("Assassin"));
  assert.equal(asset.price.free, true);
  assert.equal(asset.price.credits, 0);
  assert.equal(asset.authors[0]!.name, "Silent Wolf");

  const plan = await provider.resolveDownload(asset, "gltf_godot");
  assert.equal(plan.kind, "files");
  if (plan.kind === "files") {
    assert.equal(plan.files.length, 1);
    assert.ok(plan.files[0]!.filename.endsWith(".glb"));
    assert.ok(plan.files[0]!.url.startsWith("https://"));
  }
});
