extends SceneTree
## Comprehensive offline contract and regression tests for KayKit provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/kaykit/provider.gd")
const Client = preload("res://addons/3dtexel/providers/kaykit/client.gd")

class MockKayKitClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["packs"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/kaykit/fixtures/packs.json"))

	func fetch_packs() -> Dictionary:
		calls += 1
		return {"items": fixtures["packs"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock KayKit package content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.FOREST_GREEN)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting KayKit offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "kaykit", "Descriptor ID is kaykit")
	check(desc.name == "KayKit", "Descriptor name is KayKit")
	check(desc.website.contains("kaylousberg.com"), "Website points to kaylousberg.com")
	check(desc.key_env.is_empty(), "KayKit requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockKayKitClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://kaykit_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-model categories return empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("dungeon", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 dungeon pack from fixture")

	var dungeon_item: Dictionary = search_res.items[0]
	check(dungeon_item.id == "dungeon_pack", "ID matches dungeon_pack")
	check(dungeon_item.type == "model", "Type is model")
	check(dungeon_item.license.id == "cc0", "License is CC0")
	check(dungeon_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(dungeon_item)
	check(vars.size() >= 2, "Variants include GLB and FBX")
	check(vars[0].id == "kaykit_dungeon_glb", "First variant is GLB")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(dungeon_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "KayKit CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(dungeon_item, "kaykit_dungeon_glb")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].filename.contains("GLB"), "Plan selects GLB zip")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://kaykit_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "kaykit":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["kaykit"]
	var hub_mock := MockKayKitClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://kaykit_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/kaykit_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(dungeon_item, "kaykit_dungeon_glb")
	check(not prep_res.has("error"), "KayKit preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("KayKit offline tests complete; failures=%d" % failures)
	quit(failures)
