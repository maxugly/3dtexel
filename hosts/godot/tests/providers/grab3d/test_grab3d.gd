extends SceneTree
## Comprehensive offline contract and regression tests for Grab3D provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/grab3d/provider.gd")
const Client = preload("res://addons/3dtexel/providers/grab3d/client.gd")

class MockGrab3DClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["models"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/grab3d/fixtures/models.json"))
		fixtures["chest"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/grab3d/fixtures/model_chest.json"))

	func fetch_models() -> Dictionary:
		calls += 1
		return {"items": fixtures["models"]}

	func fetch_model(slug: String) -> Dictionary:
		calls += 1
		if slug == "treasure-chest":
			return fixtures["chest"]
		return {"slug": slug, "name": {"en": slug.capitalize()}, "files": [{"format": "glb", "url": "https://grab3d.com/dl/%s.glb" % slug}]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Grab3D GLB content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.ORANGE)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Grab3D offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "grab3d", "Descriptor ID is grab3d")
	check(desc.name == "Grab3D", "Descriptor name is Grab3D")
	check(desc.website.begins_with("https://grab3d.com/"), "Website points to Grab3D")
	check(desc.key_env.is_empty(), "Grab3D requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockGrab3DClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://grab3d_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-model categories return empty
	var mat_res: Dictionary = await provider.refresh_page("", "material", "")
	check(mat_res.items.is_empty(), "Material category returns empty without errors")
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("chest", "all", "")
	check(search_res.items.size() == 1, "Search for 'chest' yields 1 asset")

	var chest_item: Dictionary = search_res.items[0]
	check(chest_item.id == "treasure-chest", "treasure-chest ID matches")
	check(chest_item.type == "model", "Type is model")
	check(chest_item.license.id == "cc0", "License is CC0")
	check(chest_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(chest_item)
	check(vars.size() >= 3, "Variants include glb, fbx, blend")
	check(vars[0].id == "glb", "First variant is glb")
	check(vars[0].triangles == 12400, "Triangle count of 12400 exposed on variant")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(chest_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Grab3D CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(chest_item, "glb")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan has 1 file")
	check(plan.files[0].filename == "treasure_chest.glb", "Filename is treasure_chest.glb")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://grab3d_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "grab3d":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["grab3d"]
	var hub_mock := MockGrab3DClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://grab3d_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/grab3d_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(chest_item, "glb")
	check(not prep_res.has("error"), "Grab3D preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Grab3D offline tests complete; failures=%d" % failures)
	quit(failures)
