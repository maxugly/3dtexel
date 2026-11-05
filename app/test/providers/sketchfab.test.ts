import assert from "node:assert/strict";
import test from "node:test";
import { SketchfabProvider } from "../../src/providers/sketchfab.js";
import { context, FakeHttp } from "../support.js";

const SAMPLE_SEARCH = {
  results: [
    {
      uid: "52772448c62348e0a4951b51758d5587",
      name: "Autumn House",
      description: "Low poly autumn house",
      viewerUrl: "https://sketchfab.com/3d-models/autumn-house-52772448c62348e0a4951b51758d5587",
      isDownloadable: true,
      license: {
        slug: "by",
        label: "CC Attribution",
        url: "http://creativecommons.org/licenses/by/4.0/"
      },
      user: {
        username: "zhenyarech",
        displayName: "Zhenya",
        profileUrl: "https://sketchfab.com/zhenyarech"
      },
      thumbnails: {
        images: [
          { url: "https://media.sketchfab.com/models/thumb.jpeg", width: 720, height: 405 }
        ]
      }
    }
  ],
  next: "https://api.sketchfab.com/v3/search?cursor=page2"
};

const SAMPLE_DOWNLOAD = {
  glb: {
    url: "https://sketchfab-prod-media.s3.amazonaws.com/archives/autumn_house.glb",
    size: 5821508,
    expires: 300
  },
  gltf: {
    url: "https://sketchfab-prod-media.s3.amazonaws.com/archives/autumn_house.zip",
    size: 12191822,
    expires: 300
  }
};

test("sketchfab search, details, and model plan contract", async () => {
  const http = new FakeHttp({
    json: [
      { match: "https://api.sketchfab.com/v3/search", value: SAMPLE_SEARCH },
      { match: "https://api.sketchfab.com/v3/models/52772448c62348e0a4951b51758d5587/download", value: SAMPLE_DOWNLOAD },
      { match: "https://api.sketchfab.com/v3/models/52772448c62348e0a4951b51758d5587", value: SAMPLE_SEARCH.results[0] }
    ]
  });

  const ctx = context(http, {
    SKETCHFAB_API_KEY: "mock_test_key"
  });

  const provider = new SketchfabProvider(ctx);
  assert.equal(provider.descriptor().id, "sketchfab");
  assert.equal(provider.credentialStatus(), "API key configured.");

  const search = await provider.search({ query: "house", category: "model", limit: 24 });
  assert.equal(search.items.length, 1);
  const asset = search.items[0]!;
  assert.equal(asset.id, "52772448c62348e0a4951b51758d5587");
  assert.equal(asset.title, "Autumn House");
  assert.equal(asset.license.id, "cc-by-4.0");
  assert.equal(asset.authors[0]!.name, "Zhenya");

  const plan = await provider.resolveDownload(asset, "glb");
  assert.equal(plan.kind, "files");
  if (plan.kind === "files") {
    assert.equal(plan.files.length, 1);
    assert.ok(plan.files[0]!.filename.endsWith(".glb"));
    assert.equal(plan.files[0]!.size, 5821508);
  }
});
