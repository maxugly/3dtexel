extends SceneTree
## Comprehensive offline contract and regression tests for ambientCG provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/ambientcg/provider.gd")
const Client = preload("res://addons/3dtexel/providers/ambientcg/client.gd")

class MockAmbientCGClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixture: Dictionary = {}

	func _init() -> void:
		fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/ambientcg/fixtures/search_page_0.json"))

	func fetch_assets(_query := "", _type_filter := "", _limit := 30, _offset := 0) -> Dictionary:
		calls += 1
		return fixture

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock ambientCG ZIP content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.YELLOW)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting ambientCG offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "ambientcg", "Descriptor ID is ambientcg")
	check(desc.name == "ambientCG", "Descriptor name is ambientCG")
	check(desc.website.begins_with("https://ambientcg.com/"), "Website points to ambientCG")
	check(desc.key_env.is_empty(), "ambientCG requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockAmbientCGClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://ambientcg_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 assets from fixture")

	var paving_item: Dictionary = search_res.items[0]
	check(paving_item.id == "PavingStones036", "PavingStones036 ID matches")
	check(paving_item.type == "material", "Paving stones type is material")
	check(paving_item.license.id == "cc0", "License is CC0")
	check(paving_item.price.free == true, "Asset is free")

	var stump_item: Dictionary = search_res.items[1]
	check(stump_item.id == "TreeStump001", "TreeStump001 ID matches")
	check(stump_item.type == "model", "Tree stump type is model")

	# 5. Variants
	var vars := provider.variants(paving_item)
	check(vars.size() >= 2, "Variants include 1K-JPG and 2K-JPG")
	check(vars[0].id == "1k_jpg" or vars[1].id == "1k_jpg", "1k_jpg variant present")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(paving_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "ambientCG CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(paving_item, "1k_jpg")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan has 1 file")
	check(plan.files[0].filename.contains("1k_jpg.zip"), "Filename includes 1k_jpg.zip")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://ambientcg_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "ambientcg":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["ambientcg"]
	var hub_mock := MockAmbientCGClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://ambientcg_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/ambientcg_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(paving_item, "1k_jpg")
	check(not prep_res.has("error"), "ambientCG preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("ambientCG offline tests complete; failures=%d" % failures)
	quit(failures)
