extends SceneTree
## Comprehensive offline contract and regression tests for Poly Pizza provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/polypizza/provider.gd")
const Client = preload("res://addons/3dtexel/providers/polypizza/client.gd")

class MockPolyPizzaClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/polypizza/fixtures/search.json"))

	func search(_query: String, _page := 1, _limit := 30) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Poly Pizza GLB binary content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.ORANGE_RED)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Poly Pizza offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "polypizza", "Descriptor ID is polypizza")
	check(desc.name == "Poly Pizza", "Descriptor name is Poly Pizza")
	check(desc.website.contains("poly.pizza"), "Website points to poly.pizza")
	check(desc.key_env.has("POLYPIZZA_API_KEY"), "Poly Pizza expects POLYPIZZA_API_KEY in key_env")

	# Check credential handling
	check(provider.credential_status().contains("Free API key required"), "Status shows key required when empty")
	provider.set_session_key("test_pizza_key_123")
	check(provider.api_key() == "test_pizza_key_123", "Session key sets api_key")
	check(provider.credential_status() == "API key configured.", "Status reflects configured key")

	# 2. Attach mock transport
	var mock_client := MockPolyPizzaClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://polypizza_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-model categories return empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("tree", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 items from fixture")

	var tree_item: Dictionary = search_res.items[0]
	check(tree_item.id == "tree_oak", "ID matches tree_oak")
	check(tree_item.type == "model", "Type is model")
	check(tree_item.license.id == "cc0", "Tree license is CC0")
	check(tree_item.price.free == true, "Asset is free")

	var drone_item: Dictionary = search_res.items[1]
	check(drone_item.id == "drone_scifi", "ID matches drone_scifi")
	check(drone_item.license.id == "cc-by-3.0", "Drone license is CC-BY")
	check(drone_item.license.attribution_required == true, "Drone requires attribution")

	# 5. Variants
	var vars := provider.variants(tree_item)
	check(vars.size() == 1, "Has 1 variant (glb)")
	check(vars[0].id == "glb", "Variant id is glb")
	check(vars[0].label.contains("350 tris"), "Variant label includes tri count: " + vars[0].label)

	# 6. License policy evaluation
	var cc0_eval: Dictionary = Policy.evaluate(tree_item)
	check(cc0_eval.status == Policy.Status.PERMISSIVE, "Poly Pizza CC0 evaluates to PERMISSIVE")

	var cc_by_eval: Dictionary = Policy.evaluate(drone_item)
	check(cc_by_eval.status == Policy.Status.ATTRIBUTION, "Poly Pizza CC-BY evaluates to ATTRIBUTION")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(tree_item, "glb")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan contains 1 glb file")
	check(plan.files[0].filename == "tree_oak.glb", "Plan targets tree_oak.glb")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://polypizza_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "polypizza":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["polypizza"]
	var hub_mock := MockPolyPizzaClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://polypizza_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/polypizza_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(tree_item, "glb")
	check(not prep_res.has("error"), "Poly Pizza preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Poly Pizza offline tests complete; failures=%d" % failures)
	quit(failures)
