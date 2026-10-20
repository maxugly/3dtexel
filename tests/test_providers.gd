extends SceneTree
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Provider = preload("res://addons/3dtexel/core/provider.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
class FakeProvider:
	extends Provider
	var id := "mock_site"
	var calls := 0
	var key := ""
	func descriptor() -> Dictionary:return {"id":id,"name":"Offline fixture","website":"https://example.invalid","key_env":["FAKE_KEY"],"capabilities":["files"]}
	func api_key() -> String:return key
	func set_session_key(value: String) -> void:key=value
	func can_download(_asset: Dictionary) -> bool:return true
	func variants(_asset: Dictionary) -> Array:return [{"id":"original","label":"Original","confirmed":true}]
	func resolve_download(asset: Dictionary,_variant: String) -> Dictionary:
		calls+=1
		return {"kind":"files","asset":asset,"variant":"original","files":[{"filename":"fixture.txt","url":"https://example.invalid/file"}]}
	func get_bytes(_url: String,destination: String,_limit: int) -> Dictionary:
		calls+=1
		var file := FileAccess.open(destination,FileAccess.WRITE);file.store_string("Offline original fixture");file.close()
		return {}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var hub := Registry.new();root.add_child(hub)
	check(hub.providers.has("texel"),"Texel discovered through provider directory")
	for provider in hub.providers.values():provider.enabled=false
	hub.catalog.root="user://provider_contract_%s" % Time.get_ticks_usec()
	var first := FakeProvider.new();var second := FakeProvider.new();second.id="other_site"
	check(hub.register_provider(first)==OK and hub.register_provider(second)==OK,"Independent sites register without browser changes")
	first.enabled=true;second.enabled=true
	var asset := {"provider_id":"mock_site","provider":"Offline fixture","id":"same/non-numeric:id","title":"Same title","type":"model","price":{"free":true},"license":{"name":"CC-BY-4.0","url":"https://creativecommons.org/licenses/by/4.0/","attribution_required":true},"authors":[{"name":"Fixture artist","url":"https://example.invalid/artist"}],"url":"https://example.invalid/asset","api_key":"SECRET_FIXTURE","token":"SECRET_FIXTURE","source_metadata":{"author":"Fixture artist","authorization":"SECRET_FIXTURE"}}
	var other := asset.duplicate(true);other.provider_id="other_site"
	hub.index_assets([asset,other]);check(hub.search("Same","model",true,"Any license").size()==2,"Provider-qualified IDs never collide")
	check(first.calls==0 and second.calls==0,"Index and local browsing are offline")
	second.enabled=false
	check(hub.search("","all",true,"Any license").size()==1,"Disabled sites are excluded")
	check(not hub.can_download(other),"Disabled site cannot download")
	var catalog_text := FileAccess.get_file_as_string(hub.catalog.root.path_join("assets.json"))
	check("SECRET_FIXTURE" not in catalog_text,"Secrets excluded even in nested metadata")
	first.set_session_key("SESSION_ONLY_SECRET");hub.catalog.save()
	check("SESSION_ONLY_SECRET" not in FileAccess.get_file_as_string(hub.catalog.root.path_join("assets.json")),"Session key never persisted")
	var fresh := preload("res://addons/3dtexel/core/catalog.gd").new();fresh.root=hub.catalog.root
	check(fresh.search(["mock_site"],"Same","model",true,"Any license").size()==1,"Catalog survives another instance")
	var prep := Preparation.new();root.add_child(prep);prep.registry=hub;prep.output_directory="res://AssetLibrary/fixture_%s" % Time.get_ticks_usec()
	hub.network_allowed=true
	var prepared: Dictionary=await prep.prepare(asset,"original")
	check(not prepared.has("error"),"Non-material file preparation works")
	var path := prep.output_directory.path_join("mock_site").path_join("same_title_same_non_numeric_id_"+str(asset.id).sha256_text().left(12)).path_join("original")
	check(FileAccess.file_exists(path.path_join("fixture.txt.credits.json")),"Credits travel beside downloaded file")
	var record: Variant=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("fixture.txt.credits.json")))
	check(record is Dictionary and record.authors[0].name=="Fixture artist" and record.license.name=="CC-BY-4.0","Author and exact license preserved")
	check("SECRET_FIXTURE" not in FileAccess.get_file_as_string(path.path_join("asset.credits.json")),"Sidecar does not retain secrets")
	var calls := first.calls
	var reused: Dictionary=await prep.prepare(asset,"original")
	check(not reused.has("error") and first.calls==calls,"Completed source import reused offline")
	var bad: Dictionary=await prep.prepare(asset,"../outside")
	check(bad.has("error") and first.calls==calls,"Unsafe variant rejected before download")
	var cc0 := asset.duplicate(true);cc0.license="CC0"
	check(Policy.evaluate(cc0).status==Policy.Status.PERMISSIVE,"CC0 category")
	check(Policy.evaluate(asset).status==Policy.Status.ATTRIBUTION,"Attribution category")
	cc0.license="CC-BY-SA-4.0";check(Policy.evaluate(cc0).status==Policy.Status.UNKNOWN,"Share-alike needs review, not blanket rejection")
	cc0.license="CC-BY-NC-4.0";check(Policy.evaluate(cc0).status==Policy.Status.BLOCKED,"Noncommercial terms blocked for commercial project")
	prep.queue_free();hub.queue_free();await process_frame
	print("Provider contract tests complete; failures=",failures)
	quit(1 if failures else 0)
