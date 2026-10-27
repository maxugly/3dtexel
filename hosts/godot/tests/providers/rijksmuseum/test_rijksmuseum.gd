extends SceneTree
## Comprehensive offline contract and regression tests for Rijksmuseum provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/rijksmuseum/provider.gd")
const Client = preload("res://addons/3dtexel/providers/rijksmuseum/client.gd")

class MockRijksClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["collection"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/rijksmuseum/fixtures/collection.json"))

	func search(_query := "", _page := 1, _page_size := 30) -> Dictionary:
		calls += 1
		return fixtures["collection"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.GOLDENROD)
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
	print("Starting Rijksmuseum offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "rijksmuseum", "Descriptor ID is rijksmuseum")
	check(desc.name == "Rijksmuseum", "Descriptor name is Rijksmuseum")
	check(desc.website.contains("rijksmuseum.nl"), "Website points to rijksmuseum.nl")
	check(desc.capabilities.has("image") and desc.capabilities.has("material"), "Capabilities include image and material")

	# Check credential handling
	check(provider.credential_status().contains("No key required"), "Default credential status explains optional key")
	provider.set_session_key("test_rijks_key")
	check(provider.api_key() == "test_rijks_key", "Session key sets api_key")
	check(provider.credential_status() == "API key configured.", "Status reflects configured key")

	# 2. Attach mock transport
	var mock_client := MockRijksClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://rijksmuseum_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Non-image categories return empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("rembrandt", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 artworks from fixture")

	var nightwatch_item: Dictionary = search_res.items[0]
	check(nightwatch_item.id == "sk_c_5", "ID matches sk_c_5")
	check(nightwatch_item.type == "image", "Type is image")
	check(nightwatch_item.license.id == "cc0", "License is CC0")
	check(nightwatch_item.price.free == true, "Asset is free")
	check(nightwatch_item.thumbnail.contains("=s400") or nightwatch_item.thumbnail.contains("=s0"), "Thumbnail URL extracted")

	# 5. Variants
	var vars := provider.variants(nightwatch_item)
	check(vars.size() >= 2, "Variants include full and preview")
	check(vars[0].id == "full", "First variant is full")
	check(vars[0].label.contains("5656x4704"), "Label shows dimensions: " + vars[0].label)

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(nightwatch_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Rijksmuseum CC0 evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(nightwatch_item, "full")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("=s0"), "Plan selects full resolution image")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://rijksmuseum_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "rijksmuseum":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["rijksmuseum"]
	hub_provider.enabled=true
	var hub_mock := MockRijksClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://rijksmuseum_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/rijksmuseum_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(nightwatch_item, "full")
	check(not prep_res.has("error"), "Rijksmuseum preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Rijksmuseum offline tests complete; failures=%d" % failures)
	quit(failures)
