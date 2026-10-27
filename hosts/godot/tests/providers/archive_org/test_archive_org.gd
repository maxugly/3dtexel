extends SceneTree
## Comprehensive offline contract and regression tests for Internet Archive provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/archive_org/provider.gd")
const Client = preload("res://addons/3dtexel/providers/archive_org/client.gd")

class MockArchiveOrgClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/archive_org/fixtures/search_page_1.json"))
		fixtures["meta"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/archive_org/fixtures/item_metadata.json"))

	func search(_query: String, _mediatype := "image", _collection := "flickrcommons", _page := 1, _rows := 30) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func fetch_metadata(identifier: String) -> Dictionary:
		calls += 1
		if identifier == "flickr-commons-steam-locomotive-1905":
			return fixtures["meta"]
		return {"files": [{"name": "%s.jpg" % identifier, "source": "original"}]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Internet Archive photograph content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.GRAY)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Internet Archive offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "archive_org", "Descriptor ID is archive_org")
	check(desc.name == "Internet Archive", "Descriptor name is Internet Archive")
	check(desc.website.begins_with("https://archive.org/"), "Website points to archive.org")
	check(desc.key_env.is_empty(), "Internet Archive requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockArchiveOrgClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://archive_org_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Material category returns empty
	var mat_res: Dictionary = await provider.refresh_page("", "material", "")
	check(mat_res.items.is_empty(), "Material category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("locomotive", "image", "")
	check(search_res.items.size() == 2, "Search yields 2 assets from fixture")

	var loco_item: Dictionary = search_res.items[0]
	check(loco_item.id == "flickr-commons-steam-locomotive-1905", "Identifier matches")
	check(loco_item.type == "image", "Type is image")
	check(loco_item.authors[0].name == "Library of Congress", "Creator is Library of Congress")
	check(loco_item.license.id == "public-domain", "License is public-domain")
	check(loco_item.price.free == true, "Asset is free")

	# 5. Details and Variants
	var detailed_loco: Dictionary = await provider.refresh_asset(loco_item)
	var vars := provider.variants(detailed_loco)
	check(vars.size() >= 1, "Variants resolved from item metadata")
	check(vars[0].id == "original_jpg", "First variant is original_jpg")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(detailed_loco)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Flickr Commons public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(detailed_loco, "original_jpg")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan has 1 file")
	check(plan.files[0].url.contains("archive.org/download/"), "Download URL uses official archive.org/download endpoint")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://archive_org_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "archive_org":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["archive_org"]
	hub_provider.enabled=true
	var hub_mock := MockArchiveOrgClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://archive_org_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/archive_org_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(detailed_loco, "original_jpg")
	check(not prep_res.has("error"), "Internet Archive preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Internet Archive offline tests complete; failures=%d" % failures)
	quit(failures)
