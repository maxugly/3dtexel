extends SceneTree
## Comprehensive offline contract and regression tests for Poly Haven provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/polyhaven/provider.gd")
const Client = preload("res://addons/3dtexel/providers/polyhaven/client.gd")

class MockPolyHavenClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["assets"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/polyhaven/fixtures/assets.json"))
		fixtures["info_brick"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/polyhaven/fixtures/info_brick_wall.json"))
		fixtures["files_brick"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/polyhaven/fixtures/files_brick_wall.json"))
		fixtures["files_cannon"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/polyhaven/fixtures/files_cannon.json"))

	func fetch_assets(_type_filter := "") -> Dictionary:
		calls += 1
		return fixtures["assets"]

	func fetch_info(asset_id: String) -> Dictionary:
		calls += 1
		if asset_id == "brick_wall_001":
			return fixtures["info_brick"]
		return {"name": asset_id.capitalize(), "type": 2, "authors": {"Rico Cilliers": "https://polyhaven.com"}}

	func fetch_files(asset_id: String) -> Dictionary:
		calls += 1
		if asset_id == "brick_wall_001":
			return fixtures["files_brick"]
		elif asset_id == "cannon_01":
			return fixtures["files_cannon"]
		return {}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock texture/model bytes for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.GREEN)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Poly Haven offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "polyhaven", "Descriptor ID is polyhaven")
	check(desc.name == "Poly Haven", "Descriptor name is Poly Haven")
	check(desc.website.begins_with("https://polyhaven.com/"), "Website points to Poly Haven")
	check(desc.key_env.is_empty(), "Poly Haven requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockPolyHavenClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://polyhaven_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Query category "audio" returns empty immediately
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("brick", "all", "")
	check(search_res.items.size() == 1, "Search for 'brick' yields 1 asset")
	var brick_item: Dictionary = search_res.items[0]
	check(brick_item.id == "brick_wall_001", "Brick Wall ID matches")
	check(brick_item.type == "material", "Type mapped to material")
	check(brick_item.license.id == "cc0", "License is CC0")
	check(brick_item.price.free == true, "Asset is free")

	# 5. Asset details
	var detailed_brick: Dictionary = await provider.refresh_asset(brick_item)
	check(detailed_brick.description.contains("Weathered red brick wall"), "Description parsed")
	check(detailed_brick.dimensions.x == 2.0, "Dimensions parsed")
	var vars := provider.variants(detailed_brick)
	check(vars.size() >= 2, "Variants include 1k and 2k")
	check(vars[0].id == "1k", "First variant is 1k")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(detailed_brick)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Poly Haven CC0 evaluates to PERMISSIVE")

	# 7. Material download plan resolution
	var mat_plan: Dictionary = await provider.resolve_download(detailed_brick, "1k")
	check(mat_plan.kind == "material", "Material download plan kind is material")
	check(mat_plan.maps.has("albedo"), "Plan includes albedo map")
	check(mat_plan.maps.has("normal"), "Plan includes normal map")
	check(mat_plan.maps.has("roughness"), "Plan includes roughness map")
	check(mat_plan.maps.has("height"), "Plan includes height/displacement map")
	check(mat_plan.normal_format == "opengl", "Normal format is opengl")

	# 8. Model download plan resolution
	var cannon_item := provider.normalize({
		"id": "cannon_01",
		"name": "Cannon 01",
		"type": 2
	})
	var model_plan: Dictionary = await provider.resolve_download(cannon_item, "gltf")
	check(model_plan.kind == "files", "Model download plan kind is files")
	check(model_plan.files.size() == 1, "Model download plan has 1 file")
	check(model_plan.files[0].filename == "cannon_01.gltf", "glTF filename resolved")

	# 9. Preparation engine execution (files)
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://polyhaven_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "polyhaven":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["polyhaven"]
	var hub_mock := MockPolyHavenClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://polyhaven_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/polyhaven_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(cannon_item, "gltf")
	check(not prep_res.has("error"), "Model preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Poly Haven offline tests complete; failures=%d" % failures)
	quit(failures)
