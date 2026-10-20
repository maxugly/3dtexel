extends SceneTree
## Comprehensive offline contract and regression tests for OpenGameArt provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

const Provider = preload("res://addons/3dtexel/providers/opengameart/provider.gd")
const Client = preload("res://addons/3dtexel/providers/opengameart/client.gd")
const Parser = preload("res://addons/3dtexel/providers/opengameart/parser.gd")

class MockOGAClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search_0"] = FileAccess.get_file_as_string("res://tests/providers/opengameart/fixtures/search_page_0.html")
		fixtures["search_1"] = FileAccess.get_file_as_string("res://tests/providers/opengameart/fixtures/search_page_1.html")
		fixtures["detail_model"] = FileAccess.get_file_as_string("res://tests/providers/opengameart/fixtures/detail_model.html")
		fixtures["detail_texture"] = FileAccess.get_file_as_string("res://tests/providers/opengameart/fixtures/detail_texture.html")
		fixtures["detail_audio"] = FileAccess.get_file_as_string("res://tests/providers/opengameart/fixtures/detail_audio.html")
		fixtures["detail_changed"] = FileAccess.get_file_as_string("res://tests/providers/opengameart/fixtures/detail_changed_layout.html")

	func http_get_string(url: String) -> Dictionary:
		calls += 1
		if "page=1" in url:
			return {"body": fixtures["search_1"], "status": 200, "url": url}
		if "/art-search" in url:
			return {"body": fixtures["search_0"], "status": 200, "url": url}
		if "dungeon-chest-3d" in url:
			return {"body": fixtures["detail_model"], "status": 200, "url": url}
		if "stone-wall-texture" in url:
			return {"body": fixtures["detail_texture"], "status": 200, "url": url}
		if "victory-fanfare" in url:
			return {"body": fixtures["detail_audio"], "status": 200, "url": url}
		if "changed" in url or "walls" in url:
			return {"body": fixtures["detail_changed"], "status": 200, "url": url}
		return {"error": "404 Not Found in mock fixture"}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock binary content for " + url
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
	print("Starting OpenGameArt offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "opengameart", "Descriptor ID is opengameart")
	check(desc.name == "OpenGameArt", "Descriptor name is OpenGameArt")
	check(desc.website.begins_with("https://opengameart.org/"), "Website points to OpenGameArt")
	check(desc.key_env.is_empty(), "OpenGameArt requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Pure parser tests for Search Page 0
	var mock_client := MockOGAClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)

	var search_0_html: String = mock_client.fixtures["search_0"]
	var parsed_search_0: Dictionary = Parser.parse_search_page(search_0_html, "https://opengameart.org/art-search")
	var items: Array = parsed_search_0.get("items", [])
	check(items.size() == 4, "Search page 0 parses 4 items")
	check(parsed_search_0.next_cursor == "1", "Search page 0 has next_cursor == '1'")

	var item_model: Dictionary = items[0]
	check(item_model.id == "dungeon-chest-3d", "Item 0 slug extracted")
	check(item_model.title == "Dungeon Chest 3D", "Item 0 title extracted")
	check(item_model.type == "model", "Item 0 art type mapped to model")
	check(item_model.thumbnail == "https://opengameart.org/sites/default/files/styles/thumbnail/public/chest_preview.png", "Item 0 thumbnail extracted")
	check(item_model.author == "ModelMaster", "Item 0 author extracted")

	var item_texture: Dictionary = items[1]
	check(item_texture.id == "stone-wall-texture", "Item 1 slug extracted")
	check(item_texture.type == "material", "Item 1 mapped to material")
	check(item_texture.license.name == "CC0", "Item 1 license is CC0")
	check(item_texture.thumbnail == "https://opengameart.org/sites/default/files/styles/thumbnail/public/stone_preview.png", "Item 1 relative thumbnail cleaned to full HTTPS")

	var item_audio: Dictionary = items[2]
	check(item_audio.id == "victory-fanfare", "Item 2 slug extracted")
	check(item_audio.type == "audio", "Item 2 mapped to audio")
	check(item_audio.license.name == "OGA-BY 3.0", "Item 2 license is OGA-BY 3.0")

	var item_2d: Dictionary = items[3]
	check(item_2d.id == "rpg-character-sprites", "Item 3 slug extracted")
	check(item_2d.type == "image", "Item 3 mapped to image")
	check(item_2d.license.name == "CC-BY-SA 3.0", "Item 3 license is CC-BY-SA 3.0")
	check(item_2d.thumbnail == "https://opengameart.org/sites/default/files/styles/thumbnail/public/sprites_preview.png", "Item 3 protocol-relative // url cleaned to HTTPS")

	# 3. Search Page 1 (end of pagination)
	var search_1_html: String = mock_client.fixtures["search_1"]
	var parsed_search_1: Dictionary = Parser.parse_search_page(search_1_html, "https://opengameart.org/art-search?page=1")
	check(parsed_search_1.items.size() == 1, "Search page 1 has 1 item")
	check(parsed_search_1.next_cursor == "", "Search page 1 ends pagination with empty cursor")

	# 4. Detail Page parsing: Model with declared author, attribution notice, dual licenses, GLB + blend
	var model_html: String = mock_client.fixtures["detail_model"]
	var parsed_model: Dictionary = Parser.parse_asset_page(model_html, "https://opengameart.org/content/dungeon-chest-3d")
	check(parsed_model.title == "Dungeon Chest 3D", "Detail title parsed")
	check(parsed_model.author == "ModelMaster", "Declared author prioritized over uploader")
	check(parsed_model.submitter.name == "UploaderProxy", "Uploader preserved in metadata evidence")
	check(parsed_model.attribution_text == "Please attribute to ModelMaster (https://modelmaster.example.com).", "Attribution notice captured")
	check(parsed_model.licenses.size() == 2, "Both dual licenses preserved")
	check(parsed_model.selected_license.name == "CC-BY 3.0", "CC-BY selected over copyleft GPL alternative")
	check(parsed_model.files.size() == 2, "Two downloadable files extracted")
	check(parsed_model.files[0].filename == "chest.glb" and parsed_model.files[0].url.begins_with("https://"), "GLB file parsed")
	check(parsed_model.files[1].filename == "chest.blend", "Blend file parsed")
	check(parsed_model.tags.has("chest") and parsed_model.tags.has("3d"), "Tags parsed")

	# 5. Detail Page parsing: Texture (CC0, fallback to submitter, single file)
	var texture_html: String = mock_client.fixtures["detail_texture"]
	var parsed_texture: Dictionary = Parser.parse_asset_page(texture_html, "https://opengameart.org/content/stone-wall-texture")
	check(parsed_texture.author == "TextureArtist", "Submitter used when no author declared")
	check(parsed_texture.license.name == "CC0", "CC0 license parsed")
	check(parsed_texture.license.attribution_required == false, "CC0 marked attribution not required")
	check(parsed_texture.files.size() == 1 and parsed_texture.files[0].filename == "stone_wall.png", "Single texture file parsed")

	# 6. Detail Page parsing: Audio (OGA-BY, OGG + WAV)
	var audio_html: String = mock_client.fixtures["detail_audio"]
	var parsed_audio: Dictionary = Parser.parse_asset_page(audio_html, "https://opengameart.org/content/victory-fanfare")
	check(parsed_audio.license.name == "OGA-BY 3.0", "OGA-BY 3.0 license parsed")
	check(parsed_audio.files.size() == 2, "OGG and WAV files parsed")

	# 7. Changed Layout parsing (HTML entities, multiple authors, relative files)
	var changed_html: String = mock_client.fixtures["detail_changed"]
	var parsed_changed: Dictionary = Parser.parse_asset_page(changed_html, "https://opengameart.org/content/modular-dungeon-walls-gates")
	check(parsed_changed.title == "Modular Dungeon Walls & Gates", "HTML entity &amp; unescaped in title")
	check(parsed_changed.authors.size() == 2, "Multiple comma-separated authors parsed")
	check(parsed_changed.files.size() == 2, "Downloads in changed layout parsed")
	check(parsed_changed.files[0].url.begins_with("https://opengameart.org/"), "Relative download URL converted to HTTPS")

	# 8. Variants and real-only versions check
	var unconfirmed_asset := {"id": "no-files-yet", "title": "Empty"}
	check(provider.variants(unconfirmed_asset).is_empty(), "Unknown availability returns empty variants array")
	check(not provider.can_download(unconfirmed_asset), "Asset without files cannot download")

	var single_file_asset := {"id": "stone-wall-texture", "title": "Stone Wall", "files": parsed_texture.files}
	var single_vars := provider.variants(single_file_asset)
	check(single_vars.size() == 1, "Single file produces 1 variant")
	check(single_vars[0].id == "original" and single_vars[0].filter_key == "format:png", "Single file uses 'original' ID and format filter")

	var multi_file_asset := {"id": "dungeon-chest-3d", "title": "Dungeon Chest", "files": parsed_model.files}
	var multi_vars := provider.variants(multi_file_asset)
	check(multi_vars.size() == 3, "Multi-file asset produces 'all-files' + 2 format variants")
	check(multi_vars[0].id == "all-files", "First variant is all-files")
	check(multi_vars[1].id == "chest_glb" and multi_vars[1].filter_key == "format:glb", "GLB variant with safe slug")
	check(multi_vars[2].id == "chest_blend" and multi_vars[2].filter_key == "format:blend", "Blend variant with safe slug")

	# 9. Provider live flow with Mock Transport
	mock_client.cache.root = "user://oga_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("test", "all", "")
	check(search_res.items.size() == 4, "Refresh page via mock client returns 4 items")
	check(search_res.next_cursor == "1", "Cursor returned correctly")

	# Category filter check: unsupported category returns empty without network
	var prior_calls := mock_client.calls
	var empty_cat := await provider.refresh_page("test", "nonexistent_category", "")
	check(empty_cat.items.is_empty() and mock_client.calls == prior_calls, "Unsupported category returns empty without network request")

	# Asset details fetch and caching
	var asset_stub := {"id": "dungeon-chest-3d", "title": "Dungeon Chest 3D", "url": "https://opengameart.org/content/dungeon-chest-3d"}
	var details: Dictionary = await provider.asset_details(asset_stub)
	check(not details.has("error"), "Asset details fetched successfully")
	check(details.files.size() == 2, "Details include 2 files")
	var calls_after_detail := mock_client.calls

	# Repeated asset details fetch reuses cache
	var repeated: Dictionary = await provider.asset_details(asset_stub)
	check(mock_client.calls == calls_after_detail, "Repeated details request served from disk cache without network call")

	# 10. Download resolution
	var plan_single: Dictionary = await provider.resolve_download(details, "chest_glb")
	check(plan_single.kind == "files", "Download kind is files")
	check(plan_single.variant == "chest_glb", "Variant preserved in plan")
	check(plan_single.files.size() == 1 and plan_single.files[0].filename == "chest.glb", "Only GLB file in single variant plan")

	var plan_all: Dictionary = await provider.resolve_download(details, "all-files")
	check(plan_all.files.size() == 2, "All files variant returns both files")

	var plan_bad: Dictionary = await provider.resolve_download(details, "nonexistent_variant")
	check(plan_bad.has("error"), "Nonexistent variant rejected with error")

	# 11. Registry coexistence, secret stripping and preparation
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://oga_registry_test_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")

	check(hub.providers.has("opengameart"), "OpenGameArt discovered automatically by Registry directory scan")
	# Disable all auto-discovered providers first
	for p in hub.providers.values():
		p.enabled = false

	# Configure discovered provider with a fresh mock client
	var hub_provider: Node = hub.providers["opengameart"]
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	var hub_mock := MockOGAClient.new()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.enabled = true
	provider = hub_provider
	hub.network_allowed = true

	# Test provider-qualified IDs and collision safety
	var oga_asset := details.duplicate(true)
	oga_asset.provider_id = "opengameart"
	oga_asset.provider = "OpenGameArt"
	oga_asset.api_key = "SECRET_LEAK_ATTEMPT"
	oga_asset.token = "SECRET_TOKEN"
	oga_asset.source_metadata = {"authorization": "SENSITIVE_AUTH", "files": parsed_model.files}

	var duplicate_other := oga_asset.duplicate(true)
	duplicate_other.provider_id = "other_provider"

	hub.index_assets([oga_asset, duplicate_other])
	check(hub.search("Dungeon", "model", true, "Any license").size() == 1, "Only enabled provider assets returned in search")

	# Verify secret stripping in saved catalog
	var cat_content := FileAccess.get_file_as_string(hub.catalog.root.path_join("assets.json"))
	check("SECRET_LEAK_ATTEMPT" not in cat_content and "SECRET_TOKEN" not in cat_content and "SENSITIVE_AUTH" not in cat_content, "Secrets stripped from persistent catalog")

	# 12. Full end-to-end Preparation with sidecars and local reuse
	var prep := Preparation.new()
	root.add_child(prep)
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/oga_fixture_%s" % Time.get_ticks_usec()

	var prep_res: Dictionary = await prep.prepare(oga_asset, "chest_glb")
	check(not prep_res.has("error"), "Generic file preparation succeeded: " + str(prep_res.get("error", "")))

	var dest_folder := prep.output_directory.path_join("opengameart").path_join("dungeon_chest_3d_dungeon_chest_3d_" + str(oga_asset.id).sha256_text().left(12)).path_join("chest_glb")
	check(FileAccess.file_exists(dest_folder.path_join("chest.glb")), "Downloaded file written to disk")
	check(FileAccess.file_exists(dest_folder.path_join("chest.glb.credits.json")), "Credits sidecar accompanies file")
	check(FileAccess.file_exists(dest_folder.path_join("asset.credits.json")), "Asset credits written")
	check(FileAccess.file_exists(dest_folder.path_join("provenance.json")), "Provenance sidecar written")
	check(FileAccess.file_exists(dest_folder.path_join("import_receipt.json")), "Import receipt written")

	var sidecar_text := FileAccess.get_file_as_string(dest_folder.path_join("chest.glb.credits.json"))
	var sidecar_obj: Variant = JSON.parse_string(sidecar_text)
	check(sidecar_obj is Dictionary and sidecar_obj.authors[0].name == "ModelMaster", "Declared creator preserved in sidecar")
	check(sidecar_obj.license.name == "CC-BY 3.0", "Exact license preserved in sidecar")
	check("SECRET_LEAK_ATTEMPT" not in sidecar_text and "SECRET_TOKEN" not in sidecar_text and "SENSITIVE_AUTH" not in sidecar_text, "Sidecar contains no secrets")

	# Offline reuse test: second prepare call must not call transport
	var file_downloads_before := hub_mock.downloaded_files
	var reused_prep: Dictionary = await prep.prepare(oga_asset, "chest_glb")
	check(not reused_prep.has("error") and hub_mock.downloaded_files == file_downloads_before, "Existing import reused offline without network call")

	# Policy check for licenses
	var cc0_asset := oga_asset.duplicate(true)
	cc0_asset.license = "CC0"
	cc0_asset.selected_license = "CC0"
	check(Policy.evaluate(cc0_asset).status == Policy.Status.PERMISSIVE, "CC0 is PERMISSIVE")

	var by_asset := oga_asset.duplicate(true)
	by_asset.license = "CC-BY 3.0"
	by_asset.selected_license = "CC-BY 3.0"
	check(Policy.evaluate(by_asset).status == Policy.Status.ATTRIBUTION, "CC-BY 3.0 is ATTRIBUTION")

	var ogaby_asset := oga_asset.duplicate(true)
	ogaby_asset.license = "OGA-BY 3.0"
	ogaby_asset.selected_license = "OGA-BY 3.0"
	check(Policy.evaluate(ogaby_asset).status == Policy.Status.ATTRIBUTION, "OGA-BY 3.0 is ATTRIBUTION")

	var gpl_asset := oga_asset.duplicate(true)
	gpl_asset.license = "GPL 3.0"
	gpl_asset.selected_license = "GPL 3.0"
	check(Policy.evaluate(gpl_asset).status == Policy.Status.UNKNOWN, "GPL 3.0 is UNKNOWN (needs review, not auto-blocked)")

	# Disabled site behavior
	provider.enabled = false
	check(not hub.can_download(oga_asset), "Disabled site cannot download")
	check(hub.search("Dungeon", "model", true, "Any license").is_empty(), "Disabled site excluded from search")

	# Clean up nodes
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()
	await process_frame

	print("OpenGameArt offline tests complete; failures=", failures)
	quit(1 if failures else 0)
