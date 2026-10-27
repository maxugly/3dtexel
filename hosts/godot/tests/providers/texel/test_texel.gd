extends SceneTree
## Offline provider regression: public metadata, exact choices, zero-credit materials.
const Provider = preload("res://addons/3dtexel/providers/texel/provider.gd")
const Client = preload("res://addons/3dtexel/providers/texel/client.gd")
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
class MockClient:
	extends Client
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/texel/fixtures/asset.json"))
	var calls: Array=[]
	var file_calls := 0
	var page_calls := 0
	var key_available := true
	var charge := 0
	var actual := "2k"
	var missing_albedo := false
	var returned_license := "CC0"
	func _init() -> void:cache.root="user://texel_fixture_"+str(Time.get_ticks_usec())
	func api_key() -> String:return "offline-fixture-key" if key_available else ""
	func transport_json(path: String,method := HTTPClient.METHOD_GET,body := {}) -> Dictionary:
		if not network_allowed:return {"error":"Explicit action required."}
		calls.append({"path":path,"method":method,"body":body.duplicate(true)})
		if path.begins_with("/assets/search?"):return {"items":[fixture.duplicate(true)],"total":1}
		if path=="/assets/101":return fixture.duplicate(true)
		if path=="/assets/101/download" and method==HTTPClient.METHOD_POST:
			return {"charged_credits":charge,"license":returned_license,"files":{"albedo":"" if missing_albedo else "https://example.invalid/albedo.png?signature=offline-only","normal":"https://example.invalid/normal.png?signature=offline-only","resolution":actual,"normal_format":"opengl"}}
		return {"error":"Unexpected offline endpoint."}
	func get_bytes(url: String,destination := "",_limit := 67108864,_redirects := 5) -> Dictionary:
		if not network_allowed and not allowed_thumbnails.has(url):return {"error":"Explicit permission required."}
		if url.contains("/product/"):
			page_calls+=1;return {"bytes":FileAccess.get_file_as_bytes("res://tests/providers/texel/fixtures/product.html")}
		file_calls+=1
		var image := Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.5,.7,1))
		var bytes := image.save_png_to_buffer()
		if not destination.is_empty():
			var file := FileAccess.open(destination,FileAccess.WRITE)
			if not file:return {"error":"Cannot write offline map."}
			file.store_buffer(bytes);file.close();return {"path":destination}
		return {"bytes":bytes}
var failures := 0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func attach(provider: Node,mock: Node) -> void:provider.client.free();provider.client=mock;provider.add_child(mock)
func run() -> void:
	check(Client.KEY_NAMES.has("3D_TEXEL_API_KEY") and Client.KEY_NAMES.has("3DTEXEL_API_KEY") and Client.KEY_NAMES.has("TEXEL_API_KEY"),"New credential name and legacy aliases are supported")
	var actual_client := Client.new();root.add_child(actual_client)
	check((await actual_client.json_request("/me")).has("error"),"Account endpoint never requests network implicitly")
	check((await actual_client.get_bytes("https://example.invalid/map.png")).has("error"),"Map bytes never request network implicitly")
	actual_client.free()
	var provider := Provider.new();root.add_child(provider)
	var mock := MockClient.new();attach(provider,mock)
	check((await provider.refresh_page("wood","material","")).has("error") and mock.calls.is_empty(),"Search requires explicit action")
	provider.network_allowed=true
	check((await provider.refresh_page("wood","model","")).items.is_empty() and mock.calls.is_empty(),"Unsupported category remains offline")
	check((await provider.refresh_page("wood","material","pbr:invalid")).has("error") and mock.calls.is_empty(),"Invalid cursor remains offline")
	var result: Dictionary=await provider.refresh_page("wood & moss","material","")
	check(not result.has("error") and result.items.size()==1,"Bounded search works")
	check(mock.calls[0].path.contains("per_page=24") and mock.calls[0].path.contains("wood%20%26%20moss"),"Query encoding and page bound are explicit")
	var asset: Dictionary=result.items[0]
	check(asset.id=="101" and asset.provider_id=="texel" and asset.license.id=="cc0-1.0","Qualified numeric ID and exact documented CC0 declaration normalize correctly")
	check(Policy.evaluate(asset).status==Policy.Status.PERMISSIVE,"Canonical CC0 metadata clears policy")
	var detailed: Dictionary=await provider.asset_details(asset)
	check(detailed.authors[0].name=="Offline Artist" and provider.variants(detailed).size()==2,"Explicit detail action discovers actual author and sizes")
	var count := mock.calls.size();var pages := mock.page_calls
	await provider.asset_details(asset)
	check(mock.calls.size()==count and mock.page_calls==pages,"Repeated details reuse API metadata and page evidence")
	var hub := Registry.new();root.add_child(hub);hub.catalog.root="user://texel_contract_"+str(Time.get_ticks_usec());hub.inventory.root=hub.catalog.root.path_join("imports")
	for id in hub.providers:hub.providers[id].enabled=id=="texel"
	hub.index_assets([detailed])
	var cached: Dictionary=hub.cached_asset(detailed)
	check(provider.variants(cached).size()==2,"Reported sizes survive shared catalog persistence")
	check((await provider.resolve_download(asset,"8k")).has("error"),"Unreported resolution never requests download links")
	check(not mock.calls.any(func(call):return call.method==HTTPClient.METHOD_POST),"Invalid choices perform no download POST")
	var plan: Dictionary=await provider.resolve_download(asset,"2k")
	check(not plan.has("error") and plan.variant=="2k" and plan.maps.has("albedo"),"Only reported map roles and actual resolution form the material plan")
	check(mock.calls.back().body.max_credits==0 and mock.calls.back().body.resolution=="2k","Download is explicitly capped at zero credits")
	mock.charge=1
	check((await provider.resolve_download(asset,"2k")).has("error"),"Unexpected nonzero charge fails closed")
	mock.charge=0;mock.missing_albedo=true
	check((await provider.resolve_download(asset,"2k")).has("error"),"Missing albedo is not a successful material")
	mock.missing_albedo=false;mock.returned_license="https://creativecommons.org/licenses/by-nd/4.0/"
	check((await provider.resolve_download(asset,"2k")).has("error"),"Returned restricted license blocks import")
	mock.returned_license="CC0"
	for denied in ["https://creativecommons.org/licenses/by-nc/4.0/","unknown"]:
		mock.fixture.license=denied;count=mock.calls.size()
		check((await provider.resolve_download(asset,"2k")).has("error"),"Changed license blocks download: "+denied)
		check(not mock.calls.slice(count).any(func(call):return call.method==HTTPClient.METHOD_POST),"Changed license is rejected before download POST")
	mock.fixture.license="CC0 1.0 (public domain)";mock.fixture.price={"free":false,"credits":5};count=mock.calls.size()
	check((await provider.resolve_download(asset,"2k")).has("error") and not mock.calls.slice(count).any(func(call):return call.method==HTTPClient.METHOD_POST),"Fresh paid metadata overrides a cached free record without spending")
	mock.fixture.price={"free":true,"credits":0};mock.key_available=false;count=mock.calls.size()
	check((await provider.resolve_download(asset,"2k")).has("error") and mock.calls.size()==count,"Missing key rejects download before requests")
	mock.key_available=true
	var hub_provider: Node=hub.providers.texel;var hub_mock := MockClient.new();attach(hub_provider,hub_mock);hub.network_allowed=true
	var prep := Preparation.new();prep.registry=hub;prep.output_directory="res://AssetLibrary/texel_fixture_"+str(Time.get_ticks_usec());root.add_child(prep)
	hub_mock.network_allowed=false
	var prepared: Dictionary=await prep.prepare(detailed,"1k")
	check(not prepared.has("error"),"Native material preparation succeeds after permission handoff: "+str(prepared.get("error","")))
	var versions: Dictionary=hub.inventory.versions(detailed)
	check(versions.has("2k"),"Imported receipt records the actual returned 2K version")
	if versions.has("2k"):
		var folder: String=versions["2k"].folder
		var material := ResourceLoader.load(folder.path_join("material.res"),"",ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
		check(material!=null and material.albedo_texture!=null and material.albedo_texture.get_width()==16,"Prepared material reloads with decoded albedo")
		var provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))
		check(provenance.requested_resolution=="1k" and provenance.returned_resolution=="2k","Requested and returned sizes remain distinct")
		check(provenance.charged_credits==0 and provenance.authors[0].name=="Offline Artist" and provenance.license.id=="cc0-1.0","Zero charge, creator and license preserved")
		check(provenance.sha256.albedo==FileAccess.get_sha256(folder.path_join(provenance.maps.albedo)),"Source map hash verified")
		check(FileAccess.file_exists(folder.path_join(provenance.maps.albedo)+".credits.json"),"Source-map credits preserved")
		check(not FileAccess.get_file_as_string(folder.path_join("provenance.json")).contains("signature=offline-only"),"Signed links never reach sidecars")
	remove_tree(prep.output_directory)
	provider.queue_free();hub.queue_free();prep.queue_free();await process_frame
	print("3D Texel offline tests complete; failures=",failures)
	quit(1 if failures else 0)
func remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if not directory:return
	for child in directory.get_directories():remove_tree(path.path_join(child))
	for file in directory.get_files():directory.remove(file)
	DirAccess.remove_absolute(path)
