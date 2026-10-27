extends SceneTree
const Openverse = preload("res://addons/3dtexel/providers/openverse/provider.gd")
const Freesound = preload("res://addons/3dtexel/providers/freesound/provider.gd")
const Catalog = preload("res://addons/3dtexel/core/catalog.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Files = preload("res://addons/3dtexel/core/reported_files.gd")
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
class OpenverseClient:
	extends "res://addons/3dtexel/providers/openverse/client.gd"
	var details := {};var detail_calls := 0;var last_id := ""
	func fetch_detail(id: String,_category: String) -> Dictionary:
		detail_calls+=1;last_id=id;return details.duplicate(true)
	func get_bytes(_url: String,_destination := "",_max_bytes := 67108864,_redirects_left := 5) -> Dictionary:return {"error":"Offline"}
class FreesoundClient:
	extends "res://addons/3dtexel/providers/freesound/client.gd"
	var details := {};var detail_calls := 0
	func oauth_token() -> String:return ""
	func fetch_sound(_id: String) -> Dictionary:detail_calls+=1;return details.duplicate(true)
	func get_bytes(_url: String,_destination := "",_max_bytes := 67108864,_redirects_left := 5) -> Dictionary:return {"error":"Offline"}
var failures := 0
var test_root := "user://provider_downloads_"+str(Time.get_ticks_usec())
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func attach(provider: Node,client: Node,id: String) -> void:
	root.add_child(provider);provider.client.free();provider.client=client;provider.add_child(client)
	client.cache.root=test_root.path_join(id);client.cache.catalog_path=client.cache.root.path_join("catalog.json");client.cache.assets_path=client.cache.root.path_join("assets.json")
	provider.network_allowed=true
func run():
	await test_openverse()
	await test_freesound()
	test_files()
	check(SourceLicense.record("https://unrelated.invalid/publicdomain/zero/1.0/").id=="unknown","A similar URL path does not establish CC0")
	check(Policy.evaluate({"price":{"free":true},"license":SourceLicense.record("by-nd")}).status==Policy.Status.BLOCKED,"ND remains blocked even when the source omits its version")
	Registry.clear_cache_path(test_root)
	print("Reported download regression tests complete; failures=",failures)
	quit(1 if failures else 0)
func test_openverse() -> void:
	var provider := Openverse.new();var client := OpenverseClient.new();attach(provider,client,"openverse")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/openverse/fixtures/items.json"))
	var raw: Dictionary=fixture.results[0];var asset: Dictionary=provider.normalize(raw,true)
	var catalog := Catalog.new();catalog.root=test_root.path_join("core");catalog.upsert(asset);catalog.save()
	var restored := Catalog.new();restored.root=catalog.root;restored.load_catalog();asset=restored.records["openverse:"+str(asset.id)]
	var plan: Dictionary=await provider.resolve_download(asset,"orig")
	check(not plan.has("error") and plan.files[0].url==raw.url,"Openverse imports the direct media URL after catalog persistence, never its landing page")
	check(asset.url==raw.foreign_landing_url,"Openverse preserves the landing page separately for provenance")
	check((await provider.resolve_download(asset,"stream")).has("error"),"An audio stream is never substituted with a waveform image")
	var limited := raw.duplicate(true);limited.license="by-nc-nd";limited.license_version="3.0"
	var normalized := provider.normalize(limited)
	check(normalized.license.id=="cc-by-nc-nd-3.0" and Policy.evaluate(normalized).status==Policy.Status.BLOCKED,"Compound NC/ND terms retain their actual version and remain blocked")
	limited.license="by-sa";limited.license_version="2.0"
	normalized=provider.normalize(limited)
	check(normalized.license.id=="cc-by-sa-2.0" and Policy.evaluate(normalized).status==Policy.Status.UNKNOWN,"Share-alike is preserved for review instead of being rewritten to plain CC-BY")
	limited.erase("license");limited.erase("license_version")
	check(not provider.can_download(provider.normalize(limited)),"Missing license evidence is not treated as CC0")
	client.details=raw
	var incomplete := {"provider_id":"openverse","id":asset.id,"type":"image","source_metadata":{"id":raw.id}}
	var detail: Dictionary=await provider.asset_details(incomplete)
	check(not detail.has("error") and client.detail_calls==1 and client.last_id==raw.id,"Missing Openverse details use the original source UUID")
	await provider.asset_details(incomplete)
	check(client.detail_calls==1,"Openverse details are cached")
	var current := provider.normalize(raw.duplicate(true));current.license={"id":"cc-by-nc-3.0"};current.selected_license=current.license
	check((await provider.asset_details(current)).selected_license.id=="cc-by-nc-3.0","New search license changes take precedence over cached details")
	provider.queue_free();await process_frame
func test_freesound() -> void:
	var provider := Freesound.new();var client := FreesoundClient.new();attach(provider,client,"freesound")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/freesound/fixtures/sounds.json"))
	var raw: Dictionary=fixture.results[0];var asset: Dictionary=provider.normalize(raw,true)
	var plan: Dictionary=await provider.resolve_download(asset,"mp3_hq")
	check(not plan.has("error") and plan.files[0].url==raw.previews["preview-hq-mp3"] and str(plan.files[0].filename).ends_with(".mp3"),"Freesound uses the exact reported preview and matching file format")
	check((await provider.resolve_download(asset,"original")).has("error"),"OAuth-only originals never fall back to audio previews")
	var low := raw.duplicate(true);low.previews={"preview-lq-ogg":"https://example.invalid/low.ogg"}
	var low_asset: Dictionary=provider.normalize(low)
	check(provider.variants(low_asset).size()==1 and provider.variants(low_asset)[0].id=="ogg_lq","Only the reported preview quality is offered")
	check((await provider.resolve_download(low_asset,"ogg_hq")).has("error"),"A missing high-quality preview is not replaced with low quality")
	low.license="https://creativecommons.org/licenses/by-nd/3.0/"
	check(Policy.evaluate(provider.normalize(low)).status==Policy.Status.BLOCKED,"No-derivatives audio remains blocked")
	client.details=raw
	var incomplete := {"provider_id":"freesound","id":"12345","type":"audio"}
	check(not (await provider.asset_details(incomplete)).has("error") and client.detail_calls==1,"Freesound can retrieve missing sound metadata")
	await provider.asset_details(incomplete);check(client.detail_calls==1,"Repeated sound details reuse cache")
	client.custom_key="offline-fixture"
	check(client.api_headers("https://freesound.org/apiv2/sounds/12345/").size()==3,"API authentication uses headers")
	check(client.api_headers("https://freesound.org.attacker.invalid/apiv2/sounds/12345/").size()==2,"Lookalike domains cannot receive API credentials")
	check(client.api_headers("https://cdn.freesound.org/previews/12345.mp3").size()==2,"File hosts cannot receive API credentials")
	provider.queue_free();await process_frame
func test_files() -> void:
	var asset := {"id":"asset","type":"image","source_metadata":{"files":[{"resolution":"2k","filename":"actual.png","url":"https://example.invalid/actual.png"}]}}
	var offers := Files.offers(asset)
	check(offers.size()==1 and offers[0].id=="2k","Reported file choices preserve source version IDs")
	check(Files.plan(asset,"4k",offers).has("error"),"Missing versions cannot silently use the first file")
	check(Files.plan(asset,"2k",offers).files[0].filename=="actual.png","Source filenames and URLs survive exact version selection")
