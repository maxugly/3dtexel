extends SceneTree
## Comprehensive offline contract and regression tests for DigitaltMuseum provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/digitaltmuseum/provider.gd")
const Client = preload("res://addons/3dtexel/providers/digitaltmuseum/client.gd")

class MockDigitaltMuseumClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/digitaltmuseum/fixtures/search.json"))

	func search(_query := "", _offset := 0, _limit := 24, _category := "all") -> Dictionary:
		calls += 1
		return fixtures["search"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var bytes := PackedByteArray()
		if url.to_lower().ends_with(".glb"):
			bytes.resize(64)
			bytes.fill(0)
		else:
			var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color.FIREBRICK)
			bytes = img.save_png_to_buffer()

		if not destination.is_empty():
			var f := FileAccess.open(destination, FileAccess.WRITE)
			if f:
				f.store_buffer(bytes)
				f.close()
			return {}
		return {"bytes": bytes}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting DigitaltMuseum offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "digitaltmuseum", "Descriptor ID is digitaltmuseum")
	check(desc.name == "DigitaltMuseum", "Descriptor name is DigitaltMuseum")
	check(desc.website.contains("digitaltmuseum.se"), "Website points to digitaltmuseum.se")
	check(desc.capabilities.has("image") and desc.capabilities.has("model") and desc.capabilities.has("material"), "Capabilities include image, model, and material")
	check(desc.key_env.is_empty(), "DigitaltMuseum requires no API key")

	# 2. Attach mock transport
	var mock_client := MockDigitaltMuseumClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://digitaltmuseum_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("sword", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 items from fixture")

	# Item 0 is 3D model
	var model_item: Dictionary = search_res.items[0]
	check(model_item.id == "021016499312", "Model ID matches 021016499312")
	check(model_item.type == "model", "Type is model")
	check(model_item.license.id == "cc0", "License is CC0")
	check(model_item.price.free == true, "Asset is free")

	# Item 1 is image
	var image_item: Dictionary = search_res.items[1]
	check(image_item.id == "011014298114", "Image ID matches 011014298114")
	check(image_item.type == "image", "Type is image")

	# 5. Variants
	var model_vars := provider.variants(model_item)
	check(model_vars.size() >= 1, "Model has at least 1 variant")
	check(model_vars[0].id == "glb", "Model variant is glb")

	var image_vars := provider.variants(image_item)
	check(image_vars.size() >= 2, "Image has orig and 1200 variants")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(model_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "DigitaltMuseum CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(model_item, "glb")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.ends_with(".glb"), "Plan targets GLB file")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://digitaltmuseum_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "digitaltmuseum":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["digitaltmuseum"]
	var hub_mock := MockDigitaltMuseumClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://digitaltmuseum_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/digitaltmuseum_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(model_item, "glb")
	check(not prep_res.has("error"), "DigitaltMuseum model preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("DigitaltMuseum offline tests complete; failures=%d" % failures)
	quit(failures)
