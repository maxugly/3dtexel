extends SceneTree
## Comprehensive offline contract and regression tests for USFWS provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/usfws/provider.gd")
const Client = preload("res://addons/3dtexel/providers/usfws/client.gd")

class MockUSFWSClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["wildlife"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/usfws/fixtures/wildlife.json"))

	func fetch_wildlife(_query := "") -> Dictionary:
		calls += 1
		return {"items": fixtures["wildlife"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock USFWS binary photo data for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.FOREST_GREEN)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting USFWS offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "usfws", "Descriptor ID is usfws")
	check(desc.name == "US Fish & Wildlife Service", "Descriptor name is US Fish & Wildlife Service")
	check(desc.website.contains("fws.gov"), "Website points to fws.gov")
	check(desc.capabilities.has("image"), "Capabilities include image")
	check(desc.key_env.is_empty(), "USFWS requires no API key")

	# 2. Attach mock transport
	var mock_client := MockUSFWSClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://usfws_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("eagle", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 eagle item from fixture")

	var eagle_item: Dictionary = search_res.items[0]
	check(eagle_item.id == "fws_bald_eagle_flight", "ID matches fws_bald_eagle_flight")
	check(eagle_item.type == "image", "Type is image")
	check(eagle_item.license.id == "public-domain", "License is public domain")
	check(eagle_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(eagle_item)
	check(vars.size() >= 1, "Variants include orig photo")
	check(vars[0].id == "bald_eagle_flight_orig", "First variant is orig")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(eagle_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "USFWS public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(eagle_item, "bald_eagle_flight_orig")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("download/collection/natdiglib"), "Plan targets photo download")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://usfws_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "usfws":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["usfws"]
	var hub_mock := MockUSFWSClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://usfws_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/usfws_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(eagle_item, "bald_eagle_flight_orig")
	check(not prep_res.has("error"), "USFWS preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("USFWS offline tests complete; failures=%d" % failures)
	quit(failures)
