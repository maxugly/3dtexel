import assert from "node:assert/strict";
import test from "node:test";
import type { Asset } from "../../src/types.js";
import { AmbientCgProvider } from "../../src/providers/ambientcg.js";
import { KenneyProvider } from "../../src/providers/kenney.js";
import { MetMuseumProvider } from "../../src/providers/met-museum.js";
import { NasaProvider } from "../../src/providers/nasa.js";
import { OpenGameArtProvider } from "../../src/providers/opengameart.js";
import { OpenverseProvider } from "../../src/providers/openverse.js";
import { PolyHavenProvider } from "../../src/providers/polyhaven.js";
import { TexelProvider } from "../../src/providers/texel.js";
import { WikimediaProvider } from "../../src/providers/wikimedia.js";
import { context, FakeHttp, fixtureJson, fixtureJsonSync, fixtureText } from "../support.js";

const params = (query: string, category: "all" | "material" | "model" | "audio" | "image" = "all") => ({
  query,
  category,
  limit: 24
});

function first(assets: Asset[]): Asset {
  assert.ok(assets[0], "expected at least one asset");
  return assets[0];
}

async function resolved(provider: { details(asset: Asset): Promise<Asset> }, asset: Asset): Promise<Asset> {
  return provider.details(asset);
}

test("polyhaven search, details, and material plan contract", async () => {
  const http = new FakeHttp({
    json: [
      { match: "https://api.polyhaven.com/assets", value: fixtureJsonSync("polyhaven/assets.json") },
      { match: "https://api.polyhaven.com/info/brick_wall_001", value: fixtureJsonSync("polyhaven/info_brick_wall.json") },
      { match: "https://api.polyhaven.com/files/brick_wall_001", value: fixtureJsonSync("polyhaven/files_brick_wall.json") }
    ]
  });
  const provider = new PolyHavenProvider(context(http));
  const page = await provider.search(params("brick", "material"));
  assert.equal(page.items.length, 1);
  const asset = first(page.items);
  assert.equal(asset.id, "brick_wall_001");
  assert.equal(asset.license.id, "cc0");
  assert.equal(provider.isDetailed(asset), false);

  const detailed = await resolved(provider, asset);
  assert.deepEqual(detailed.variants.map((entry) => entry.id), ["jpg_1k", "jpg_2k"]);
  const plan = await provider.resolveDownload(detailed, "jpg_1k");
  assert.equal(plan.kind, "material");
  if (plan.kind === "material") {
    assert.equal(plan.normal_format, "opengl");
    assert.ok(plan.maps.albedo?.url.startsWith("https://"));
    assert.ok(plan.maps.normal?.url.startsWith("https://"));
    assert.ok(plan.maps.roughness?.url.startsWith("https://"));
    assert.ok(plan.maps.ao?.url.startsWith("https://"));
    assert.ok(plan.maps.height?.url.startsWith("https://"));
  }
});

test("ambientcg search, details, and archive plan contract", async () => {
  const http = new FakeHttp({
    json: [{ match: "https://ambientcg.com/api/v3/assets", value: fixtureJsonSync("ambientcg/search_page_0.json") }]
  });
  const provider = new AmbientCgProvider(context(http));
  const page = await provider.search(params("paving", "material"));
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0]!.id, "PavingStones036");
  const detailed = await resolved(provider, page.items[0]!);
  assert.ok(detailed.variants.some((entry) => entry.id === "1k_jpg"));
  const plan = await provider.resolveDownload(detailed, "1k_jpg");
  assert.equal(plan.kind, "files");
  if (plan.kind === "files") {
    assert.match(plan.files[0]!.url, /^https:\/\/ambientcg\.com\//);
  }
});

test("opengameart embedded search and detail pages stay offline", async () => {
  const searchHtml = await fixtureText("opengameart/search_page_0.html");
  const detailHtml = await fixtureText("opengameart/detail_texture.html");
  const http = new FakeHttp({
    text: [
      { match: "https://opengameart.org/art-search", value: searchHtml },
      { match: "https://opengameart.org/content/stone-wall-texture", value: detailHtml }
    ]
  });
  const provider = new OpenGameArtProvider(context(http));
  const page = await provider.search(params("stone"));
  const asset = page.items.find((entry) => entry.id === "stone-wall-texture");
  assert.ok(asset);
  assert.equal(asset.type, "material");
  const detailed = await resolved(provider, asset);
  assert.ok(detailed.variants.length > 0);
  assert.ok(detailed.authors.some((author) => author.name === "TextureArtist"));
  const plan = await provider.resolveDownload(detailed, detailed.variants[0]!.id);
  assert.equal(plan.kind, "files");
  if (plan.kind === "files") {
    assert.match(plan.files[0]!.url, /^https:\/\/opengameart\.org\//);
  }
});

test("openverse image and audio results resolve to bounded files", async () => {
  const all = fixtureJsonSync<{ results: Array<Record<string, unknown>> }>("openverse/items.json");
  const imageOnly = { ...all, results: all.results.filter((item) => item.media_type !== "audio") };
  const audioOnly = { ...all, results: all.results.filter((item) => item.media_type === "audio") };
  const http = new FakeHttp({
    json: [
      { match: "https://api.openverse.org/v1/images/", value: imageOnly },
      { match: "https://api.openverse.org/v1/audios/", value: audioOnly }
    ]
  });
  const provider = new OpenverseProvider(context(http));
  const images = await provider.search(params("olive", "image"));
  assert.equal(images.items.length, 1);
  assert.equal(images.items[0]!.type, "image");
  assert.deepEqual(images.items[0]!.variants.map((entry) => entry.id), ["orig", "preview"]);
  const audio = await provider.search(params("canyon", "audio"));
  assert.equal(audio.items.length, 1);
  assert.equal(audio.items[0]!.type, "audio");
  assert.ok(audio.items[0]!.variants.some((entry) => entry.id === "audio"));
  const plan = await provider.resolveDownload(audio.items[0]!, "audio");
  assert.equal(plan.kind, "files");
});

test("met museum public-domain assets resolve an original file", async () => {
  const http = new FakeHttp({
    json: [{ match: "https://collectionapi.metmuseum.org/public/collection/v1/search", value: fixtureJsonSync("met_museum/search.json") }]
  });
  const provider = new MetMuseumProvider(context(http));
  const page = await provider.search(params("wheat", "image"));
  assert.equal(page.items.length, 1);
  const asset = first(page.items);
  assert.equal(asset.price.free, true);
  assert.ok(asset.variants.some((entry) => entry.id === "orig"));
  const plan = await provider.resolveDownload(asset, "orig");
  assert.equal(plan.kind, "files");
});

test("wikimedia pages normalize variants and resolve downloads", async () => {
  const http = new FakeHttp({
    json: [{ match: "https://commons.wikimedia.org/w/api.php", value: fixtureJsonSync("wikimedia/query.json") }]
  });
  const provider = new WikimediaProvider(context(http));
  const page = await provider.search(params("mona", "image"));
  assert.equal(page.items.length, 1);
  const asset = first(page.items);
  assert.equal(asset.id, "12345");
  assert.deepEqual(asset.variants.map((entry) => entry.id), ["orig", "2048", "1024"]);
  const plan = await provider.resolveDownload(asset, "orig");
  assert.equal(plan.kind, "files");
});

test("nasa manifests expose image and audio variants", async () => {
  const http = new FakeHttp({
    json: [
      { match: "https://images-api.nasa.gov/search", value: fixtureJsonSync("nasa/search_page_0.json") },
      { match: "https://images-api.nasa.gov/asset/as17-148-22727", value: fixtureJsonSync("nasa/asset_manifest.json") },
      { match: "https://images-api.nasa.gov/asset/apollo11_eagle", value: fixtureJsonSync("nasa/manifest_audio.json") }
    ]
  });
  const provider = new NasaProvider(context(http));
  const images = await provider.search(params("earth", "image"));
  assert.equal(images.items.length, 1);
  const detailedImage = await resolved(provider, images.items[0]!);
  assert.deepEqual(detailedImage.variants.map((entry) => entry.id), ["orig", "large", "medium", "small"]);
  const imagePlan = await provider.resolveDownload(detailedImage, "orig");
  assert.equal(imagePlan.kind, "files");

  const audio = await provider.search(params("apollo", "audio"));
  assert.equal(audio.items.length, 1);
  const detailedAudio = await resolved(provider, audio.items[0]!);
  assert.ok(detailedAudio.variants.some((entry) => entry.id === "wav"));
  const audioPlan = await provider.resolveDownload(detailedAudio, "wav");
  assert.equal(audioPlan.kind, "files");
});

test("kenney packs resolve archive downloads", async () => {
  const http = new FakeHttp({
    json: [{ match: "https://kenney.nl/assets.json", value: fixtureJsonSync("kenney/packs.json") }]
  });
  const provider = new KenneyProvider(context(http));
  const page = await provider.search(params("prototype", "material"));
  assert.equal(page.items.length, 1);
  const asset = first(page.items);
  assert.equal(asset.license.id, "cc0");
  const plan = await provider.resolveDownload(asset, "prototype_textures");
  assert.equal(plan.kind, "files");
  if (plan.kind === "files") {
    assert.match(plan.files[0]!.url, /^https:\/\/kenney\.nl\//);
  }
});

test("texel preview does not call the download endpoint and actual plans use zero credits", async () => {
  const http = new FakeHttp({
    json: [
      { match: "https://3dtexel.com/wp-json/3dtexel-api/v1/assets/search", value: fixtureJsonSync("texel/search.json") },
      { match: "https://3dtexel.com/wp-json/3dtexel-api/v1/assets/oak_floor_01/download", method: "POST", value: fixtureJsonSync("texel/download.json") },
      { match: "https://3dtexel.com/wp-json/3dtexel-api/v1/assets/oak_floor_01", value: fixtureJsonSync("texel/detail.json") }
    ]
  });
  const provider = new TexelProvider(context(http, { TEXEL_API_KEY: "test-key" }));
  const page = await provider.search(params("oak", "material"));
  const asset = first(page.items);
  assert.equal(provider.isDetailed(asset), false);
  const preview = await provider.resolveDownload(asset, "2k", { preview: true });
  assert.equal(preview.kind, "material");
  if (preview.kind === "material") {
    assert.deepEqual(preview.maps, {});
  }
  assert.equal(http.calls.filter((call) => call.method === "POST").length, 0);

  const plan = await provider.resolveDownload(asset, "2k");
  assert.equal(plan.kind, "material");
  if (plan.kind === "material") {
    assert.equal(plan.variant, "2k");
    assert.ok(plan.maps.albedo?.url.startsWith("https://cdn.3dtexel.com/"));
  }
  const post = http.calls.find((call) => call.method === "POST");
  assert.ok(post);
  assert.deepEqual((post.body as Record<string, unknown>).max_credits, 0);
  assert.equal((post.body as Record<string, unknown>).resolution, "2k");
});
