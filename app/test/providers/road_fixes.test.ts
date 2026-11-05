import assert from "node:assert/strict";
import test from "node:test";
import path from "node:path";
import { writeFile, access } from "node:fs/promises";
import { createLibrary } from "../../src/index.js";
import { ensureAllowedRelativeFile } from "../../src/util/fs.js";
import { FakeHttp, fixtureJsonSync, tempHome } from "../support.js";

test("glTF imports include referenced assets and reject old incomplete receipts", async () => {
  const temp = await tempHome();
  const files = { gltf: { "1k": { gltf: {
    url:"https://dl.polyhaven.org/cannon_01.gltf", include: {
      "cannon_01.bin": {url:"https://dl.polyhaven.org/cannon_01.bin"},
      "textures/color.jpg": {url:"https://dl.polyhaven.org/color.jpg"}
    }
  } } } };
  const http = new FakeHttp({json:[
    {match:"https://api.polyhaven.com/assets",value:fixtureJsonSync("polyhaven/assets.json")},
    {match:"https://api.polyhaven.com/info/cannon_01",value:{name:"Cannon 01",type:2}},
    {match:"https://api.polyhaven.com/files/cannon_01",value:files}
  ]});
  const library = await createLibrary({home:temp.home,output:path.join(temp.home,"library"),env:{},http});
  try {
    await library.search({query:"cannon",category:"model",providers:["polyhaven"]});
    const result = await library.download("polyhaven","cannon_01","gltf_1k");
    assert.deepEqual(result.files.map(f=>f.path).sort(),["cannon_01.bin","cannon_01.gltf","textures/color.jpg"]);
    await access(path.join(result.folder,"textures/color.jpg"));
    await writeFile(path.join(result.folder,"cannon_01.gltf"), JSON.stringify({buffers:[{uri:"missing.bin"}]}));
    await assert.rejects(library.download("polyhaven","cannon_01","gltf_1k"),/incomplete.*missing.bin/);
    assert.throws(()=>ensureAllowedRelativeFile("../outside.bin"),/Unsafe/);
  } finally { await library.close(); await temp.cleanup(); }
});

test("Kenney signed download links are requested only for download and never cached", async () => {
  const { KenneyProvider } = await import("../../src/providers/kenney.js");
  const { context } = await import("../support.js");
  let transientOptions: any;
  const http = new FakeHttp({
    text:[{match:"https://kenney.nl/assets/road-kit",value:"<a href='https://creativecommons.org/publicdomain/zero/1.0/'>CC0</a><a data-download-id='abcdef'>Download</a>"}],
    json:[{match:"https://kenney.nl/download-link/abcdef",value:(_url: string,options: unknown)=>{transientOptions=options;return {url:"https://example.org/road.zip?signature=secret"};}}]
  });
  const provider = new KenneyProvider(context(http));
  const {createAsset} = await import("../../src/asset.js");
  const asset = createAsset({provider_id:"kenney",provider_name:"Kenney",id:"road_kit",title:"Road Kit",type:"model",url:"https://kenney.nl/assets/road-kit",price:{free:true,credits:0},license:{id:"cc0",name:"CC0",url:"https://creativecommons.org/publicdomain/zero/1.0/",attribution_required:false}});
  const detail = await provider.details(asset);
  const preview = await provider.resolveDownload(detail,"zip",{preview:true});
  assert.equal(preview.kind,"files");
  if (preview.kind === "files") assert.equal(preview.files.length,0);
  assert.equal(http.calls.filter(call=>call.url.includes("download-link")).length,0);
  const download = await provider.resolveDownload(detail,"zip");
  assert.equal(download.kind,"files");
  assert.equal(transientOptions.cache,false);
  assert.doesNotMatch(JSON.stringify(detail),/signature=secret/);
});

test("Poly Haven current map-first texture metadata yields a complete material", async () => {
  const temp = await tempHome();
  const http = new FakeHttp({json:[
    {match:"https://api.polyhaven.com/assets",value:{gravel_road:{name:"Gravel Road",type:1,tags:["gravel"]}}},
    {match:"https://api.polyhaven.com/info/gravel_road",value:{name:"Gravel Road",type:1}},
    {match:"https://api.polyhaven.com/files/gravel_road",value:fixtureJsonSync("polyhaven/files_gravel_current.json")}
  ]});
  const library = await createLibrary({home:temp.home,output:path.join(temp.home,"library"),env:{},http});
  try {
    await library.search({query:"gravel",category:"material",providers:["polyhaven"]});
    const result = await library.planDownload("polyhaven","gravel_road","1k");
    assert.equal(result.plan.kind,"material");
    if(result.plan.kind === "material") {
      assert.ok(result.plan.maps.albedo); assert.ok(result.plan.maps.roughness);
      assert.match(result.plan.maps.normal!.url,/nor_gl/); assert.equal(result.plan.normal_format,"opengl");
    }
  } finally {await library.close(); await temp.cleanup();}
});

test("BlenderKit previews do not request or cache signed URLs", async () => {
  const { BlenderKitProvider } = await import("../../src/providers/blenderkit.js");
  const { context } = await import("../support.js");
  let transientOptions: any;
  const http = new FakeHttp({json:[
    {match:"https://www.blendkit.com/api/v1/search",value:fixtureJsonSync("blenderkit/search.json")},
    {match:"https://www.blendkit.com/api/v1/downloads",value:(_url: string, options: unknown)=>{transientOptions=options;return fixtureJsonSync("blenderkit/download.json");}}
  ]});
  const provider=new BlenderKitProvider(context(http));
  const page=await provider.search({query:"assassin",category:"model",limit:1});
  const asset=page.items[0]!;
  const preview=await provider.resolveDownload(asset,"gltf_godot",{preview:true});
  if(preview.kind === "files") assert.equal(preview.files.length,0); else assert.fail("Expected file plan");
  assert.equal(http.calls.filter(call=>call.url.includes("/downloads/")).length,0);
  await provider.resolveDownload(asset,"gltf_godot");
  assert.equal(transientOptions.cache,false);
});
