extends SceneTree
## Comprehensive offline contract and regression tests for Met Museum provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/met_museum/provider.gd")
const Client = preload("res://addons/3dtexel/providers/met_museum/client.gd")

class MockMetMuseumClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/met_museum/fixtures/search.json"))

	func search(_query := "", _offset := 0, _limit := 24) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.INDIAN_RED)
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
	print("Starting Met Museum offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "met_museum", "Descriptor ID is met_museum")
	check(desc.name == "The Metropolitan Museum of Art", "Descriptor name is The Metropolitan Museum of Art")
	check(desc.website.contains("metmuseum.org"), "Website points to metmuseum.org")
	check(desc.capabilities.has("image") and desc.capabilities.has("material"), "Capabilities include image and material")
	check(desc.key_env.is_empty(), "Met Museum requires no API key")

	# 1b. Endpoints: search moved to v1.1 (v1 answers 410), objects stay on v1
	check(Client.SEARCH_PATH.contains("/public/collection/v1.1/search"), "Search endpoint is the live v1.1 path")
	check(Client.OBJECT_PATH.contains("/public/collection/v1/objects/"), "Object endpoint stays on v1")

	# 2. Attach mock transport
	var mock_client := MockMetMuseumClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://met_museum_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Model category returns empty
	var model_res: Dictionary = await provider.refresh_page("", "model", "")
	check(model_res.items.is_empty(), "Model category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("van gogh", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 items from fixture")

	var item: Dictionary = search_res.items[0]
	check(item.id == "436535", "ID matches 436535")
	check(item.type == "image", "Type is image")
	check(item.license.id == "cc0", "License is CC0")
	check(item.price.free == true, "Asset is free")
	check(item.authors[0].name.contains("Vincent van Gogh"), "Author preserved")

	# 5. Variants
	var vars := provider.variants(item)
	check(vars.size() >= 2, "Variants include orig and small: size=%d" % vars.size())
	check(vars[0].id == "orig", "First variant is orig")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Met Museum CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(item, "orig")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("original"), "Plan targets original image")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://met_museum_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "met_museum":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["met_museum"]
	var hub_mock := MockMetMuseumClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://met_museum_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/met_museum_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(item, "orig")
	check(not prep_res.has("error"), "Met Museum preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Met Museum offline tests complete; failures=%d" % failures)
	quit(failures)
