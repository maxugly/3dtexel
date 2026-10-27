extends SceneTree
## Every network path is mocked; archive content is synthetic and decodable.
const Provider = preload("res://addons/3dtexel/providers/kaykit/provider.gd")
const Client = preload("res://addons/3dtexel/providers/kaykit/client.gd")
const Metadata = preload("res://addons/3dtexel/providers/kaykit/metadata.gd")
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
class MockClient:
	extends Client
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/kaykit/fixtures/packs.json"))
	var requests: Array[String]=[]
	var downloaded_files := 0
	var license_text := FileAccess.get_file_as_string("res://tests/providers/kaykit/fixtures/LICENSE.txt")
	var broken_listing := false
	var invalid_license := false
	var cancel_during_listing := false
	func _init() -> void:cache.root="user://kaykit_fixture_"+str(Time.get_ticks_usec())
	func json_request(url: String) -> Dictionary:
		if not network_allowed:return {"error":"Offline mock needs explicit permission."}
		requests.append(url)
		if url.contains("/search/repositories?"):
			var result := fixture.duplicate(true)
			if url.contains("dungeon"):result.items=[result.items[0]];result.total_count=1
			return result
		for repository in fixture.items:
			if url.contains("/repos/"+str(repository.full_name)+"/contents/"):
				if cancel_during_listing:transport_generation+=1;return {"error":"Request cancelled."}
				if broken_listing:return {"error":"Listing unavailable."}
				var prefix := "https://raw.githubusercontent.com/"+str(repository.full_name)+"/main/"
				var listing := {"items":[{"name":"icon.png","type":"file","source_file_url":prefix+"icon.png"},{"name":"LICENSE.txt","type":"file","source_file_url":prefix+"LICENSE.txt"}]}
				cache.put_response(url,listing);return cache.get_response(url)
		return {"error":"Unexpected mock metadata endpoint."}
	func get_bytes(url: String,destination := "",_max_bytes := 67108864,_redirects_left := 5) -> Dictionary:
		if not network_allowed and not allowed_thumbnails.has(url):return {"error":"No explicit download grant."}
		if url.ends_with("LICENSE.txt"):return {"bytes":("License: unknown" if invalid_license else license_text).to_utf8_buffer()}
		if url.ends_with("icon.png"):
			var image := Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color.FOREST_GREEN)
			return {"bytes":image.save_png_to_buffer()}
		if not url.contains("/zipball/") or destination.is_empty():return {"error":"Unexpected mock download endpoint."}
		downloaded_files+=1
		var zip := ZIPPacker.new()
		if zip.open(destination)!=OK:return {"error":"Cannot write fixture archive."}
		zip.start_file("synthetic/model.gltf")
		zip.write_file('{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"SyntheticNode"}]}'.to_utf8_buffer());zip.close_file()
		zip.start_file("synthetic/LICENSE.txt");zip.write_file(license_text.to_utf8_buffer());zip.close_file();zip.close()
		return {"path":destination}
var failures := 0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func attach(provider: Node,mock: Node) -> void:
	provider.client.free();provider.client=mock;provider.add_child(mock)
func run() -> void:
	var provider := Provider.new();root.add_child(provider)
	var mock := MockClient.new();attach(provider,mock)
	check(provider.descriptor().id=="kaykit" and provider.descriptor().key_env.is_empty(),"Provider identity and no-key access preserved")
	check((await provider.refresh_page("dungeon","model","")).has("error"),"Search requires explicit action")
	provider.network_allowed=true
	check((await provider.refresh_page("dungeon","audio","")).items.is_empty() and mock.requests.is_empty(),"Unsupported category never requests metadata")
	check((await provider.refresh_page("dungeon","model","-1")).has("error") and mock.requests.is_empty(),"Invalid cursor makes no request")
	var response: Dictionary=await provider.refresh_page("dungeon","model","")
	check(not response.has("error") and response.items.size()==1,"Real search construction and source parsing return the matching pack")
	if response.get("items",[]).is_empty():quit(1);return
	var asset: Dictionary=response.items[0]
	check(mock.requests[0].contains("per_page=6&page=1") and mock.requests[0].contains("user%3AKayKit-Game-Assets"),"Search is bounded and publisher-scoped")
	check(asset.id=="dungeon_pack" and asset.provider_id=="kaykit","Existing Dungeon Remastered identity preserved")
	check(asset.thumbnail.ends_with("icon.png") and not asset.authors.is_empty(),"Reported image and creator retained")
	check(asset.license.id=="cc0-1.0" and Policy.evaluate(asset).status==Policy.Status.PERMISSIVE,"License comes from the per-pack declaration")
	check(provider.variants(asset).size()==1 and provider.variants(asset)[0].id=="zip","Only the reported archive is offered")
	var cached: Dictionary=provider.normalize(asset)
	check(cached.thumbnail==asset.thumbnail and cached.title==asset.title and cached.source_metadata==asset.source_metadata,"Cache normalization preserves stable source evidence without nesting")
	var count := mock.requests.size()
	await provider.asset_details(asset);provider.variants(asset)
	check(mock.requests.size()==count,"Selection and variant rendering reuse fetched metadata")
	var missing := {"id":"legacy","title":"Old cached pack"}
	check(provider.variants(missing).is_empty() and not provider.can_download(provider.normalize(missing)),"Missing metadata never invents free status, CC0 or versions")
	check((await provider.resolve_download(missing,"zip")).has("error"),"Obsolete endpoint metadata needs a fresh search")
	check((await provider.resolve_download(asset,"glb")).has("error"),"A GLB choice cannot silently download a ZIP")
	var plan: Dictionary=await provider.resolve_download(asset,"zip")
	check(not plan.has("error") and plan.variant=="zip" and plan.files[0].url.ends_with("/zipball/main"),"Exact published archive template is resolved")
	mock.invalid_license=true
	check((await provider.resolve_download(asset,"zip")).has("error"),"Changed license is rechecked and blocks download")
	mock.invalid_license=false
	mock.broken_listing=true
	check((await provider.resolve_download(asset,"zip")).has("error"),"Failed metadata refresh cannot fall back to stale invented URLs")
	mock.broken_listing=false
	var listing_url := "https://api.github.com/repos/KayKit-Game-Assets/Example/contents/?ref=main"
	mock.cache.put_response(listing_url,{"items":[{"type":"file","name":"icon.png"}]},{"etag":"offline-old"})
	check(mock.cache.get_response(listing_url).is_empty() and mock.cache.conditional_headers(listing_url).is_empty(),"Incomplete old cached listings refetch without a stale conditional validator")
	mock.fixture.total_count=7
	var page: Dictionary=await mock.fetch_packs("",1)
	check(page.next_cursor=="2","Server total supplies the next bounded page")
	page=await mock.fetch_packs("",2)
	check(page.next_cursor=="" and mock.requests.filter(func(url):return url.contains("page=2")).size()==1,"Next page is explicit and terminates at the server total")
	mock.fixture.total_count=2
	var spoof: Dictionary=mock.fixture.items[0].duplicate(true);spoof.owner.login="another-publisher"
	check(not Metadata.official(spoof),"Foreign publisher rejected")
	spoof=mock.fixture.items[0].duplicate(true);spoof.fork=true
	check(not Metadata.official(spoof),"Forks never inherit KayKit authorship")
	var repo: Dictionary=mock.fixture.items[0]
	check(not Metadata.source_url("https://raw.githubusercontent.com.attacker.test/"+str(repo.full_name)+"/main/icon.png",repo),"Lookalike file hosts rejected")
	check(Metadata.license_record("CC0 appears in a suggestion, not a declaration").id=="unknown","License is not inferred from a keyword")
	check(Metadata.license_record("License: https://creativecommons.org/licenses/by-nc/4.0/").id=="cc-by-nc-4.0","Restrictive license remains exact")
	var forged := repo.duplicate(true);forged.archive_url="https://example.invalid/guess.zip"
	check(Metadata.pack(forged,[],mock.license_text,"https://raw.githubusercontent.com/"+str(repo.full_name)+"/main/LICENSE.txt").files.is_empty(),"Missing archive template never creates a speculative version")
	var before_cancel := mock.requests.size()
	mock.cancel_during_listing=true
	check((await mock.fetch_packs("",1)).has("error") and mock.requests.size()==before_cancel+2,"Cancellation stops remaining pack metadata work")
	mock.cancel_during_listing=false
	var hub := Registry.new();root.add_child(hub)
	hub.catalog.root="user://kaykit_contract_"+str(Time.get_ticks_usec());hub.inventory.root=hub.catalog.root.path_join("imports")
	for id in hub.providers:hub.providers[id].enabled=id=="kaykit"
	var hub_provider: Node=hub.providers.kaykit
	var hub_mock := MockClient.new();attach(hub_provider,hub_mock)
	hub.network_allowed=true
	var prep := Preparation.new();prep.registry=hub;prep.output_directory="res://AssetLibrary/kaykit_fixture_"+str(Time.get_ticks_usec());root.add_child(prep)
	# Reproduce metadata/image completion switching client permission off before import.
	hub_mock.network_allowed=false
	var prepared: Dictionary=await prep.prepare(asset,"zip")
	check(not prepared.has("error"),"Actual preparation succeeds after permission handoff: "+str(prepared.get("error","")))
	var versions: Dictionary=hub.inventory.versions(asset)
	check(versions.has("zip") and hub_mock.downloaded_files==1,"Import receipt records exact version")
	if versions.has("zip"):
		var folder: String=versions.zip.folder
		var path := folder.path_join(str(plan.files[0].filename))
		var reader := ZIPReader.new();check(reader.open(path)==OK,"Imported ZIP opens")
		var model_path := folder.path_join("fixture.gltf")
		var file := FileAccess.open(model_path,FileAccess.WRITE);file.store_buffer(reader.read_file("synthetic/model.gltf"));file.close();reader.close()
		var doc := GLTFDocument.new();var state := GLTFState.new()
		check(doc.append_from_file(ProjectSettings.globalize_path(model_path),state)==OK,"Synthetic model inside downloaded ZIP parses")
		var provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))
		check(provenance.sha256.get(path.get_file(),"")==FileAccess.get_sha256(path),"Archive hash is preserved")
		check(FileAccess.file_exists(path+".credits.json") and provenance.authors[0].name=="Kay Lousberg" and provenance.license.id=="cc0-1.0","Creator, exact license, and sidecars are preserved")
		await prep.prepare(asset,"zip")
		check(hub_mock.downloaded_files==1,"A completed import is reused locally")
	remove_tree(prep.output_directory)
	provider.queue_free();hub.queue_free();prep.queue_free();await process_frame
	print("KayKit offline tests complete; failures=",failures)
	quit(1 if failures else 0)
func remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if not directory:return
	for child in directory.get_directories():remove_tree(path.path_join(child))
	for file in directory.get_files():directory.remove(file)
	DirAccess.remove_absolute(path)
