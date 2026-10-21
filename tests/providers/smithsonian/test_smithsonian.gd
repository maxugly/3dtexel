extends SceneTree
## Comprehensive offline contract and regression tests for Smithsonian provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/smithsonian/provider.gd")
const Client = preload("res://addons/3dtexel/providers/smithsonian/client.gd")

class MockSmithsonianClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/smithsonian/fixtures/search.json"))

	func search(_query: String, _start := 0, _rows := 30) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Smithsonian 3D / binary content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.CORNFLOWER_BLUE)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Smithsonian offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "smithsonian", "Descriptor ID is smithsonian")
	check(desc.name.contains("Smithsonian"), "Descriptor name mentions Smithsonian")
	check(desc.website.contains("si.edu"), "Website points to si.edu")
	check(desc.capabilities.has("model") and desc.capabilities.has("image"), "Capabilities include model and image")

	# Check credential handling
	check(provider.credential_status().contains("No key required"), "Default credential status explains optional key")
	provider.set_session_key("test_smithsonian_key")
	check(provider.api_key() == "test_smithsonian_key", "Session key sets api_key")
	check(provider.credential_status() == "API key configured.", "Status reflects configured key")

	# 2. Attach mock transport
	var mock_client := MockSmithsonianClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://smithsonian_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-supported category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("mammoth", "all", "")
	check(search_res.items.size() == 3, "Search returns 3 items from fixture")

	var mammoth_item: Dictionary = search_res.items[0]
	check(mammoth_item.type == "model", "Mammoth is recognized as 3D model")
	check(mammoth_item.license.id == "cc0", "License is CC0")
	check(mammoth_item.price.free == true, "Asset is free")
	check(mammoth_item.thumbnail.contains("mammoth_thumb.png"), "Thumbnail is extracted")

	var peacock_item: Dictionary = search_res.items[2]
	check(peacock_item.type == "image", "Peacock Room is recognized as image")

	# 5. Variants
	var vars := provider.variants(mammoth_item)
	check(vars.size() >= 2, "Mammoth has GLB and OBJ variants: size=%d" % vars.size())
	check(vars[0].id == "mammoth_low", "First variant is mammoth_low")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(mammoth_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Smithsonian CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(mammoth_item, "mammoth_low")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan contains 1 file")
	check(plan.files[0].url.contains("mammoth_low.glb"), "GLB download URL selected")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://smithsonian_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "smithsonian":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["smithsonian"]
	var hub_mock := MockSmithsonianClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://smithsonian_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/smithsonian_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(mammoth_item, "mammoth_low")
	check(not prep_res.has("error"), "Smithsonian preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Smithsonian offline tests complete; failures=%d" % failures)
	quit(failures)
