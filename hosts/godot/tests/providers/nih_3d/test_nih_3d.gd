extends SceneTree
## Comprehensive offline contract and regression tests for NIH 3D provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/nih_3d/provider.gd")
const Client = preload("res://addons/3dtexel/providers/nih_3d/client.gd")

class MockNIHClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nih_3d/fixtures/search.json"))

	func fetch_entries(_query := "") -> Dictionary:
		calls += 1
		return {"items": fixtures["search"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock NIH 3D GLB content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.INDIAN_RED)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting NIH 3D offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "nih_3d", "Descriptor ID is nih_3d")
	check(desc.name == "NIH 3D", "Descriptor name is NIH 3D")
	check(desc.website.contains("3d.nih.gov"), "Website points to 3d.nih.gov")
	check(desc.capabilities.has("model"), "Capabilities include model")
	check(desc.key_env.is_empty(), "NIH 3D requires no API key")

	# 2. Attach mock transport
	var mock_client := MockNIHClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://nih_3d_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-model categories return empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("heart", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 heart model from fixture")

	var heart_item: Dictionary = search_res.items[0]
	check(heart_item.id == "3dpx_012345", "ID matches 3dpx_012345")
	check(heart_item.type == "model", "Type is model")
	check(heart_item.license.id == "cc0", "License is CC0")
	check(heart_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(heart_item)
	check(vars.size() >= 2, "Variants include GLB and STL")
	check(vars[0].id == "human_heart", "First variant is human_heart")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(heart_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "NIH 3D CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(heart_item, "human_heart")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("Human_Heart.glb"), "Plan selects GLB file")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://nih_3d_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "nih_3d":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["nih_3d"]
	hub_provider.enabled=true
	var hub_mock := MockNIHClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://nih_3d_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/nih_3d_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(heart_item, "human_heart")
	check(not prep_res.has("error"), "NIH 3D preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("NIH 3D offline tests complete; failures=%d" % failures)
	quit(failures)
