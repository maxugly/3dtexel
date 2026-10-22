import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { createLibrary } from "../src/index.js";
import type { Asset } from "../src/types.js";
import { ensureAllowedFilename } from "../src/util/fs.js";
import { assertHttpsUrl } from "../src/util/sanitize.js";
import {
  FakeHttp,
  fixtureJsonSync,
  readJsonFile,
  tempHome
} from "./support.js";

function polyhavenHttp(): FakeHttp {
  return new FakeHttp({
    json: [
      { match: "https://api.polyhaven.com/assets", value: fixtureJsonSync("polyhaven/assets.json") },
      { match: "https://api.polyhaven.com/info/brick_wall_001", value: fixtureJsonSync("polyhaven/info_brick_wall.json") },
      { match: "https://api.polyhaven.com/files/brick_wall_001", value: fixtureJsonSync("polyhaven/files_brick_wall.json") }
    ]
  });
}

test("library search, plan, download, credits, reuse, and policy refusal", async () => {
  const temporary = await tempHome();
  const http = polyhavenHttp();
  const library = await createLibrary({
    home: temporary.home,
    output: path.join(temporary.home, "library"),
    env: {},
    http
  });
  try {
    const found = await library.search({
      query: "brick",
      category: "material",
      providers: ["polyhaven"],
      limit: 24
    });
    assert.equal(found.errors.length, 0);
    assert.equal(found.assets.length, 1);
    const asset = found.assets[0]!;
    assert.equal(asset.provider_id, "polyhaven");
    assert.equal(asset.id, "brick_wall_001");

    const catalog = await library.search({ mode: "catalog", query: "brick", providers: ["polyhaven"] });
    assert.equal(catalog.assets.length, 1);

    const planned = await library.planDownload("polyhaven", "brick_wall_001", "1k");
    assert.equal(planned.plan.kind, "material");
    if (planned.plan.kind === "material") {
      assert.ok(planned.plan.maps.albedo);
    }
    assert.equal(http.downloads.length, 0);

    const imported = await library.download("polyhaven", "brick_wall_001", "1k");
    assert.equal(imported.reused, false);
    assert.equal(imported.returned_variant, "jpg_1k");
    assert.equal(imported.files.length, 5);
    assert.equal(http.downloads.length, 5);
    assert.ok(imported.folder.startsWith(path.join(temporary.home, "library", "polyhaven")));

    const material = await readJsonFile<{ maps: Record<string, string>; normal_format: string }>(
      path.join(imported.folder, "material.json")
    );
    assert.equal(material.normal_format, "opengl");
    assert.equal(material.maps.albedo, "_source/albedo.jpg");
    assert.equal(material.maps.normal, "_source/normal.jpg");

    const receipt = await readJsonFile<Record<string, unknown>>(path.join(imported.folder, "import_receipt.json"));
    assert.equal(receipt.status, "complete");
    assert.equal(receipt.requested_variant, "1k");
    assert.equal(receipt.returned_variant, "jpg_1k");
    assert.equal(receipt.charged_credits, 0);

    const provenanceText = await readFile(path.join(imported.folder, "provenance.json"), "utf8");
    assert.doesNotMatch(provenanceText, /Authorization|api[_-]?key|X-Amz|token=/i);
    const provenance = JSON.parse(provenanceText) as Record<string, unknown>;
    assert.equal(provenance.provider_id, "polyhaven");

    const credits = await library.credits("polyhaven", "brick_wall_001", "JPG_1K");
    assert.equal((credits.author_status as string), "reported");
    assert.equal((credits.license as Record<string, unknown>).id, "cc0");

    const imports = await library.imports({ provider_id: "polyhaven" });
    assert.equal(imports.length, 1);
    assert.equal(imports[0]!.exists, true);

    const reused = await library.download("polyhaven", "brick_wall_001", "1k");
    assert.equal(reused.reused, true);
    assert.equal(http.downloads.length, 5);

    const blocked: Asset = {
      ...asset,
      license: { id: "cc-by-nc-4.0", name: "CC BY-NC 4.0", attribution_required: false },
      licenses: [{ id: "cc-by-nc-4.0", name: "CC BY-NC 4.0", attribution_required: false }],
      selected_license: { id: "cc-by-nc-4.0", name: "CC BY-NC 4.0", attribution_required: false }
    };
    library.catalog.upsert(blocked);
    await library.catalog.flush(true);
    await assert.rejects(
      () => library.planDownload("polyhaven", "brick_wall_001", "1k"),
      /blocked/i
    );
    await assert.rejects(
      () => library.download("polyhaven", "brick_wall_001", "1k"),
      /blocked/i
    );
  } finally {
    await library.close();
    await temporary.cleanup();
  }
});

test("provider filenames cannot overwrite sidecars and userinfo URLs are refused", () => {
  assert.throws(() => ensureAllowedFilename("import_receipt.json"), /Reserved sidecar/);
  assert.throws(() => ensureAllowedFilename("photo.credits.json"), /Reserved sidecar/);
  assert.throws(() => assertHttpsUrl("https://user:pass@example.com/file.zip"), /user information/);
  assert.equal(assertHttpsUrl("https://example.com/file.zip?download=1"), "https://example.com/file.zip?download=1");
});

test("downloadMany reports independent failures and keeps zero-credit policy", async () => {
  const temporary = await tempHome();
  const http = polyhavenHttp();
  const library = await createLibrary({
    home: temporary.home,
    output: path.join(temporary.home, "library"),
    env: {},
    http
  });
  try {
    await library.search({ query: "brick", category: "material", providers: ["polyhaven"] });
    const batch = await library.downloadMany([
      { provider_id: "polyhaven", asset_id: "brick_wall_001", variant: "1k" },
      { provider_id: "polyhaven", asset_id: "missing", variant: "1k" }
    ]);
    assert.equal(batch.results.length, 2);
    assert.ok(batch.results[0]!.result);
    assert.match(batch.results[1]!.error ?? "", /not in the local catalog/i);
  } finally {
    await library.close();
    await temporary.cleanup();
  }
});
