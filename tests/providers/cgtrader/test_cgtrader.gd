extends SceneTree
## Comprehensive offline contract and regression tests for CGTrader provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/cgtrader/provider.gd")
const Client = preload("res://addons/3dtexel/providers/cgtrader/client.gd")

class MockCGTraderClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/cgtrader/fixtures/models_characters.json"))
		fixtures["warrior"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/cgtrader/fixtures/model_warrior.json"))

	func search_models(_query := "", _category := "character-people", _page := 1, _free_only := true) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func fetch_model(id: String) -> Dictionary:
		calls += 1
		if id == "cgt-99120":
			return fixtures["warrior"]
		return {"id": id, "title": id.capitalize(), "files": [{"format": "obj", "download_url": "https://api.cgtrader.com/v1/models/%s/download" % id}]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock CGTrader FBX character content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.PURPLE)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting CGTrader offline provider tests...")

	# 1. Descriptor and credentials
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "cgtrader", "Descriptor ID is cgtrader")
	check(desc.name == "CGTrader", "Descriptor name is CGTrader")
	check(desc.website.contains("cgtrader.com"), "Website points to CGTrader")
	check("CGTRADER_API_TOKEN" in desc.key_env, "key_env includes CGTRADER_API_TOKEN")

	check("No key" in provider.credential_status(), "Explains key is needed initially")
	provider.set_session_key("test_secret_token_123")
	check("configured" in provider.credential_status(), "Reports token configured after setting")
	check(not "test_secret_token_123" in provider.credential_status(), "Token value is not leaked in status string")

	# 2. Attach mock transport
	var mock_client := MockCGTraderClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://cgtrader_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-model categories return empty
	var mat_res: Dictionary = await provider.refresh_page("", "material", "")
	check(mat_res.items.is_empty(), "Material category returns empty without errors")

	# 4. Search and pagination (characters)
	var search_res: Dictionary = await provider.refresh_page("warrior", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 character models from fixture")

	var warrior_item: Dictionary = search_res.items[0]
	check(warrior_item.id == "cgt-99120", "ID matches warrior girl")
	check(warrior_item.type == "model", "Type is model")
	check(warrior_item.authors[0].name == "PolygonHero", "Artist is PolygonHero")
	check(warrior_item.price.free == true, "Price is free")

	# 5. Variants & specs
	var vars := provider.variants(warrior_item)
	check(vars.size() >= 2, "Variants include fbx and blend")
	check(vars[0].id == "fbx", "First variant is fbx")
	check(vars[0].polygons == 18450, "Polygon count of 18450 exposed on variant")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(warrior_item)
	check(policy_eval.status == Policy.Status.UNKNOWN, "Marketplace royalty-free license evaluates to UNKNOWN (needs review)")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(warrior_item, "fbx")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan has 1 file")
	check(plan.files[0].filename == "cgt_99120.fbx", "Filename is cgt_99120.fbx")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://cgtrader_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "cgtrader":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["cgtrader"]
	var hub_mock := MockCGTraderClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://cgtrader_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/cgtrader_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(warrior_item, "fbx")
	check(not prep_res.has("error"), "CGTrader preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("CGTrader offline tests complete; failures=%d" % failures)
	quit(failures)
