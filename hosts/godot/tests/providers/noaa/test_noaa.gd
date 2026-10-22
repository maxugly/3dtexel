extends SceneTree
## Comprehensive offline contract and regression tests for NOAA provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/noaa/provider.gd")
const Client = preload("res://addons/3dtexel/providers/noaa/client.gd")

class MockNOAAClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["gallery"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/noaa/fixtures/gallery.json"))

	func fetch_gallery(_query := "") -> Dictionary:
		calls += 1
		return {"items": fixtures["gallery"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock NOAA binary content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.TEAL)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting NOAA offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "noaa", "Descriptor ID is noaa")
	check(desc.name == "NOAA Coastal & Marine", "Descriptor name is NOAA Coastal & Marine")
	check(desc.website.contains("noaa.gov"), "Website points to noaa.gov")
	check(desc.capabilities.has("image") and desc.capabilities.has("model"), "Capabilities include image and model")
	check(desc.key_env.is_empty(), "NOAA requires no API key")

	# 2. Attach mock transport
	var mock_client := MockNOAAClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://noaa_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("coral", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 coral reef item from fixture")

	var reef_item: Dictionary = search_res.items[0]
	check(reef_item.id == "noaa_coral_reef_01", "ID matches noaa_coral_reef_01")
	check(reef_item.type == "image", "Type is image")
	check(reef_item.license.id == "public-domain", "License is public domain")
	check(reef_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(reef_item)
	check(vars.size() >= 1, "Variants include hires image")
	check(vars[0].id == "coral_reef_hawaii_hires", "First variant is hires")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(reef_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "NOAA public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(reef_item, "coral_reef_hawaii_hires")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("coral_reef_hawaii_hires.jpg"), "Plan selects hires image")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://noaa_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "noaa":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["noaa"]
	var hub_mock := MockNOAAClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://noaa_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/noaa_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(reef_item, "coral_reef_hawaii_hires")
	check(not prep_res.has("error"), "NOAA preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("NOAA offline tests complete; failures=%d" % failures)
	quit(failures)
