extends SceneTree
## Comprehensive offline contract and regression tests for NYPL provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/nypl/provider.gd")
const Client = preload("res://addons/3dtexel/providers/nypl/client.gd")

class MockNYPLClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nypl/fixtures/search.json"))

	func search(_query := "", _page := 1) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.DARK_GOLDENROD)
		if not destination.is_empty():
			img.save_jpg(destination)
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
	print("Starting NYPL offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "nypl", "Descriptor ID is nypl")
	check(desc.name == "NYPL Digital Collections", "Descriptor name is NYPL Digital Collections")
	check(desc.website.contains("digitalcollections.nypl.org"), "Website points to digitalcollections.nypl.org")
	check(desc.capabilities.has("image") and desc.capabilities.has("material"), "Capabilities include image and material")

	# Check credential handling
	check(provider.credential_status().contains("Free token available"), "Default credential status explains optional key")
	provider.set_session_key("test_nypl_token")
	check(provider.api_key() == "test_nypl_token", "Session key sets api_key")
	check(provider.credential_status() == "API token configured.", "Status reflects configured key")

	# 2. Attach mock transport
	var mock_client := MockNYPLClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://nypl_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("manhattan", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 items from fixture")

	var map_item: Dictionary = search_res.items[0]
	check(map_item.id == "1234567", "ID matches 1234567")
	check(map_item.type == "image", "Type is image")
	check(map_item.license.id == "public-domain", "License is public domain")
	check(map_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(map_item)
	check(vars.size() >= 2, "Variants include highres and thumbnail: size=%d" % vars.size())
	check(vars[0].id == "highres", "First variant is highres")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(map_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "NYPL public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(map_item, "highres")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("index.php?id="), "Plan targets high-res image link")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://nypl_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "nypl":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["nypl"]
	var hub_mock := MockNYPLClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://nypl_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/nypl_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(map_item, "highres")
	check(not prep_res.has("error"), "NYPL preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("NYPL offline tests complete; failures=%d" % failures)
	quit(failures)
