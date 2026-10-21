extends SceneTree
## Comprehensive offline contract and regression tests for NASA Multimedia provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/nasa/provider.gd")
const Client = preload("res://addons/3dtexel/providers/nasa/client.gd")

class MockNASAClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search_0"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nasa/fixtures/search_page_0.json"))
		fixtures["search_1"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nasa/fixtures/search_page_1.json"))
		fixtures["manifest"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nasa/fixtures/asset_manifest.json"))
		fixtures["manifest_audio"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nasa/fixtures/manifest_audio.json"))
		fixtures["manifest_model"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nasa/fixtures/manifest_model.json"))

	func json_request(path_or_url: String) -> Dictionary:
		calls += 1
		if "page=2" in path_or_url:
			return fixtures["search_1"]
		if "/search" in path_or_url:
			return fixtures["search_0"]
		if "/asset/apollo11" in path_or_url:
			return fixtures["manifest_audio"]
		if "/asset/curiosity" in path_or_url:
			return fixtures["manifest_model"]
		if "/asset/" in path_or_url:
			return fixtures["manifest"]
		return {"error": "404 Not Found in mock NASA fixture"}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock binary content for NASA multimedia " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.BLUE)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting NASA Multimedia offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "nasa", "Descriptor ID is nasa")
	check(desc.name == "NASA Multimedia", "Descriptor name is NASA Multimedia")
	check(desc.website.contains("nasa.gov/multimedia"), "Website points to NASA Multimedia")
	check(desc.capabilities.has("audio") and desc.capabilities.has("model"), "Capabilities include audio and model")
	check(desc.key_env.is_empty(), "NASA provider requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockNASAClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://nasa_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Search page 0
	var search_res: Dictionary = await provider.refresh_page("earth", "all", "")
	check(search_res.items.size() == 4, "Search page 0 returns 4 multimedia items")
	check(search_res.next_cursor == "2", "Search page 0 has next_cursor == '2'")

	var item_blue_marble: Dictionary = search_res.items[0]
	check(item_blue_marble.id == "as17-148-22727", "Blue Marble nasa_id extracted")
	check(item_blue_marble.type == "image", "Blue marble is type image")
	check(item_blue_marble.title == "The Blue Marble (Apollo 17)", "Blue Marble title extracted")
	check(item_blue_marble.thumbnail.contains("~thumb.jpg"), "Thumbnail preview URL extracted")
	check("Eugene Cernan" in item_blue_marble.author, "Photographer credited")

	var item_audio: Dictionary = search_res.items[2]
	check(item_audio.id == "apollo11_eagle", "Audio item ID extracted")
	check(item_audio.type == "audio", "Audio item has type audio")
	check(item_audio.attribution_text.begins_with("Audio Credit:"), "Audio credit prefix used: " + item_audio.attribution_text)

	var item_model: Dictionary = search_res.items[3]
	check(item_model.id == "curiosity_rover_3d", "3D model item ID extracted")
	check(item_model.type == "model", "Model item has type model")
	check(item_model.attribution_text.begins_with("3D Model Credit:"), "Model credit prefix used")

	# 4. Search page 1 (last page)
	var search_last: Dictionary = await provider.refresh_page("earth", "all", "2")
	check(search_last.items.size() == 1, "Page 2 returns 1 item")
	check(search_last.next_cursor == "", "Page 2 ends pagination with empty cursor")

	# 5. Asset details and manifest resolution for images
	var details: Dictionary = await provider.asset_details(item_blue_marble)
	check(not details.has("error"), "Asset manifest retrieved successfully")
	check(details.files.size() == 4, "Asset manifest parsed 4 resolution tiers")

	var vars := provider.variants(details)
	check(vars.size() == 4, "Four resolution variants generated")
	check(vars[0].id == "orig" and vars[0].filter_key == "format:jpg", "Orig resolution variant created")
	check(vars[1].id == "large", "Large resolution variant created")

	# 6. Asset details and manifest resolution for Audio & 3D models
	var audio_details: Dictionary = await provider.asset_details(item_audio)
	check(not audio_details.has("error"), "Audio manifest retrieved successfully")
	var audio_vars := provider.variants(audio_details)
	check(audio_vars.size() >= 2, "Audio has WAV and MP3 variants: size=%d" % audio_vars.size())

	var model_details: Dictionary = await provider.asset_details(item_model)
	check(not model_details.has("error"), "3D model manifest retrieved successfully")
	var model_vars := provider.variants(model_details)
	check(model_vars.size() >= 2, "Model has GLB and OBJ variants: size=%d" % model_vars.size())

	# 7. Download plan resolution
	var plan_orig: Dictionary = await provider.resolve_download(details, "orig")
	check(plan_orig.kind == "files", "Download kind is files")
	check(plan_orig.variant == "orig", "Variant preserved in plan")
	check(plan_orig.files.size() == 1 and plan_orig.files[0].url.contains("~orig.jpg"), "Orig image selected in plan")

	var plan_audio: Dictionary = await provider.resolve_download(audio_details, audio_vars[0].id)
	check(plan_audio.kind == "files", "Audio download plan kind is files")
	check(plan_audio.files.size() == 1, "Audio file URL resolved")

	var plan_model: Dictionary = await provider.resolve_download(model_details, model_vars[0].id)
	check(plan_model.kind == "files", "Model download plan kind is files")
	check(plan_model.files.size() == 1, "Model file URL resolved")

	# 8. Registry integration, auto-discovery & Preparation
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://nasa_registry_test_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")

	check(hub.providers.has("nasa"), "NASA Multimedia discovered automatically by Registry scan")
	for p in hub.providers.values():
		p.enabled = false

	var hub_provider: Node = hub.providers["nasa"]
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	var hub_mock := MockNASAClient.new()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.enabled = true
	hub.network_allowed = true

	# Test provider-qualified IDs
	var nasa_asset := details.duplicate(true)
	nasa_asset.provider_id = "nasa"
	nasa_asset.provider = "NASA Multimedia"
	hub.index_assets([nasa_asset])
	check(hub.search("Blue Marble", "image", true, "Any license").size() == 1, "NASA asset searchable in catalog")

	# 9. Preparation with credits sidecars and local reuse
	var prep := Preparation.new()
	root.add_child(prep)
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/nasa_fixture_%s" % Time.get_ticks_usec()

	var prep_res: Dictionary = await prep.prepare(nasa_asset, "orig")
	check(not prep_res.has("error"), "NASA image preparation succeeded: " + str(prep_res.get("error", "")))

	var dest_folder := prep.output_directory.path_join("nasa").path_join("the_blue_marble_apollo_17_as17_148_22727_" + str(nasa_asset.id).sha256_text().left(12)).path_join("orig")
	check(FileAccess.file_exists(dest_folder.path_join("as17-148-22727~orig.jpg")), "NASA file written to disk")
	check(FileAccess.file_exists(dest_folder.path_join("as17-148-22727~orig.jpg.credits.json")), "Credits sidecar accompanies file")
	check(FileAccess.file_exists(dest_folder.path_join("provenance.json")), "Provenance sidecar written")

	# 10. License policy evaluation
	var policy := Policy.evaluate(nasa_asset)
	check(policy.status == Policy.Status.PERMISSIVE, "NASA public domain media is PERMISSIVE")

	# Clean up
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()
	await process_frame

	print("NASA Multimedia offline tests complete; failures=", failures)
	quit(1 if failures else 0)
