extends SceneTree
## Comprehensive offline contract and regression tests for ShareTextures provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/sharetextures/provider.gd")
const Client = preload("res://addons/3dtexel/providers/sharetextures/client.gd")

class MockShareTexturesClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["textures"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/sharetextures/fixtures/textures.json"))

	func fetch_textures() -> Dictionary:
		calls += 1
		return {"items": fixtures["textures"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.DARK_GRAY)
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
	print("Starting ShareTextures offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "sharetextures", "Descriptor ID is sharetextures")
	check(desc.name == "ShareTextures", "Descriptor name is ShareTextures")
	check(desc.website.contains("sharetextures.com"), "Website points to sharetextures.com")
	check(desc.key_env.is_empty(), "ShareTextures requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockShareTexturesClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://sharetextures_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-material categories return empty
	var model_res: Dictionary = await provider.refresh_page("", "model", "")
	check(model_res.items.is_empty(), "Model category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("concrete", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 concrete texture from fixture")

	var concrete_item: Dictionary = search_res.items[0]
	check(concrete_item.id == "concrete_wall_01", "ID matches concrete_wall_01")
	check(concrete_item.type == "material", "Type is material")
	check(concrete_item.license.id == "cc0", "License is CC0")
	check(concrete_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(concrete_item)
	check(vars.size() >= 2, "Variants include 1k and 2k")
	check(vars[0].id == "1k", "First variant is 1k")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(concrete_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "ShareTextures CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(concrete_item, "1k")
	check(plan.kind == "material", "Download plan kind is material")
	check(plan.maps.has("albedo"), "Plan maps include albedo")
	check(plan.maps.has("normal"), "Plan maps include normal")
	check(plan.maps.has("roughness"), "Plan maps include roughness")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://sharetextures_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "sharetextures":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["sharetextures"]
	hub_provider.enabled=true
	var hub_mock := MockShareTexturesClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://sharetextures_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/sharetextures_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(concrete_item, "1k")
	check(not prep_res.has("error"), "ShareTextures preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("ShareTextures offline tests complete; failures=%d" % failures)
	quit(failures)
