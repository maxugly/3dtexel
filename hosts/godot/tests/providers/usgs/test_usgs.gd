extends SceneTree
## Comprehensive offline contract and regression tests for USGS provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/usgs/provider.gd")
const Client = preload("res://addons/3dtexel/providers/usgs/client.gd")

class MockUSGSClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["gallery"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/usgs/fixtures/gallery.json"))

	func fetch_gallery(_query := "") -> Dictionary:
		calls += 1
		return {"items": fixtures["gallery"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock USGS binary data for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.SIENNA)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting USGS offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "usgs", "Descriptor ID is usgs")
	check(desc.name == "USGS Multimedia & 3DEP", "Descriptor name is USGS Multimedia & 3DEP")
	check(desc.website.contains("usgs.gov"), "Website points to usgs.gov")
	check(desc.capabilities.has("image") and desc.capabilities.has("model"), "Capabilities include image and model")
	check(desc.key_env.is_empty(), "USGS requires no API key")

	# 2. Attach mock transport
	var mock_client := MockUSGSClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://usgs_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("canyon", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 Grand Canyon item from fixture")

	var canyon_item: Dictionary = search_res.items[0]
	check(canyon_item.id == "usgs_grand_canyon_3dep", "ID matches usgs_grand_canyon_3dep")
	check(canyon_item.type == "model", "Type is model")
	check(canyon_item.license.id == "public-domain", "License is public domain")
	check(canyon_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(canyon_item)
	check(vars.size() >= 2, "Variants include GLB and TIF")
	check(vars[0].id == "grand_canyon_mesh", "First variant is grand_canyon_mesh")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(canyon_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "USGS public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(canyon_item, "grand_canyon_mesh")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("grand_canyon_mesh.glb"), "Plan selects GLB terrain mesh")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://usgs_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "usgs":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["usgs"]
	hub_provider.enabled=true
	var hub_mock := MockUSGSClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://usgs_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/usgs_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(canyon_item, "grand_canyon_mesh")
	check(not prep_res.has("error"), "USGS preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("USGS offline tests complete; failures=%d" % failures)
	quit(failures)
