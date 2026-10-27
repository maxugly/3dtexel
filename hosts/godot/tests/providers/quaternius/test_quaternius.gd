extends SceneTree
## Comprehensive offline contract and regression tests for Quaternius provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/quaternius/provider.gd")
const Client = preload("res://addons/3dtexel/providers/quaternius/client.gd")

class MockQuaterniusClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["packs"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/quaternius/fixtures/packs.json"))

	func fetch_packs() -> Dictionary:
		calls += 1
		return {"items": fixtures["packs"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Quaternius package content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.MEDIUM_PURPLE)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Quaternius offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "quaternius", "Descriptor ID is quaternius")
	check(desc.name == "Quaternius", "Descriptor name is Quaternius")
	check(desc.website.contains("quaternius.com"), "Website points to quaternius.com")
	check(desc.key_env.is_empty(), "Quaternius requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockQuaterniusClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://quaternius_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-model categories return empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("cyberpunk", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 cyberpunk pack from fixture")

	var cp_item: Dictionary = search_res.items[0]
	check(cp_item.id == "cyberpunk_characters", "ID matches cyberpunk_characters")
	check(cp_item.type == "model", "Type is model")
	check(cp_item.license.id == "cc0", "License is CC0")
	check(cp_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(cp_item)
	check(vars.size() >= 2, "Variants include GLTF and FBX")
	check(vars[0].id == "cyberpunk_characters_gltf", "First variant is GLTF")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(cp_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Quaternius CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(cp_item, "cyberpunk_characters_gltf")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].filename.contains("GLTF"), "Plan selects GLTF zip")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://quaternius_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "quaternius":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["quaternius"]
	hub_provider.enabled=true
	var hub_mock := MockQuaterniusClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://quaternius_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/quaternius_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(cp_item, "cyberpunk_characters_gltf")
	check(not prep_res.has("error"), "Quaternius preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Quaternius offline tests complete; failures=%d" % failures)
	quit(failures)
