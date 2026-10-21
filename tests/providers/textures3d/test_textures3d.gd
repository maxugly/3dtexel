extends SceneTree
## Comprehensive offline contract and regression tests for 3DTextures.me provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/textures3d/provider.gd")
const Client = preload("res://addons/3dtexel/providers/textures3d/client.gd")

class Mock3DTexturesClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["posts"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/textures3d/fixtures/posts.json"))

	func fetch_posts(_query := "", _page := 1, _per_page := 30) -> Dictionary:
		calls += 1
		return {"items": fixtures["posts"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.FIREBRICK)
		if not destination.is_empty():
			if url.to_lower().contains(".jpg") or url.to_lower().contains(".jpeg"):
				img.save_jpg(destination)
			else:
				img.save_png(destination)
			return {}
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting 3DTextures.me offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "textures3d", "Descriptor ID is textures3d")
	check(desc.name == "3DTextures.me", "Descriptor name is 3DTextures.me")
	check(desc.website.contains("3dtextures.me"), "Website points to 3dtextures.me")
	check(desc.key_env.is_empty(), "3DTextures requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := Mock3DTexturesClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://3dtextures_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-material categories return empty
	var model_res: Dictionary = await provider.refresh_page("", "model", "")
	check(model_res.items.is_empty(), "Model category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("lava", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 posts from fixture")

	var lava_item: Dictionary = search_res.items[0]
	check(lava_item.id == "lava_001", "Lava 001 slug matches")
	check(lava_item.type == "material", "Type is material")
	check(lava_item.license.id == "cc0", "License is CC0")
	check(lava_item.price.free == true, "Asset is free")

	# 5. Maps extracted from post content
	check(lava_item.maps.has("albedo"), "Albedo map link extracted")
	check(lava_item.maps.has("normal"), "Normal map link extracted")
	check(lava_item.maps.has("roughness"), "Roughness map link extracted")
	check(lava_item.maps.has("height"), "Height map link extracted")
	check(lava_item.maps.has("ao"), "AO map link extracted")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(lava_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "3DTextures CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(lava_item, "2k")
	check(plan.kind == "material", "Download plan kind is material")
	check(plan.maps.has("albedo"), "Plan maps include albedo")
	check(plan.normal_format == "opengl", "Normal format is opengl")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://3dtextures_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "textures3d":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["textures3d"]
	var hub_mock := Mock3DTexturesClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://3dtextures_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/3dtextures_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(lava_item, "2k")
	check(not prep_res.has("error"), "3DTextures preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("3DTextures.me offline tests complete; failures=%d" % failures)
	quit(failures)
