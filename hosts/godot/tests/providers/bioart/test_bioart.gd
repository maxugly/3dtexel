extends SceneTree
## Comprehensive offline contract and regression tests for NIAID BioArt provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/bioart/provider.gd")
const Client = preload("res://addons/3dtexel/providers/bioart/client.gd")

class MockBioArtClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["graphics"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/bioart/fixtures/graphics.json"))

	func fetch_graphics(_query := "") -> Dictionary:
		calls += 1
		return {"items": fixtures["graphics"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.MEDIUM_AQUAMARINE)
		if not destination.is_empty():
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
	print("Starting NIAID BioArt offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "bioart", "Descriptor ID is bioart")
	check(desc.name == "NIAID BioArt", "Descriptor name is NIAID BioArt")
	check(desc.website.contains("bioart.niaid.nih.gov"), "Website points to bioart.niaid.nih.gov")
	check(desc.capabilities.has("image"), "Capabilities include image")
	check(desc.key_env.is_empty(), "NIAID BioArt requires no API key")

	# 2. Attach mock transport
	var mock_client := MockBioArtClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://bioart_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Audio category returns empty
	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.is_empty(), "Audio category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("coronavirus", "all", "")
	check(search_res.items.size() == 1, "Search yields 1 coronavirus graphic from fixture")

	var virus_item: Dictionary = search_res.items[0]
	check(virus_item.id == "bio_00123", "ID matches bio_00123")
	check(virus_item.type == "image", "Type is image")
	check(virus_item.license.id == "public-domain", "License is public domain")
	check(virus_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(virus_item)
	check(vars.size() >= 1, "Variants include hires PNG")
	check(vars[0].id == "coronavirus_virion_hires", "First variant is hires")

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(virus_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "BioArt public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(virus_item, "coronavirus_virion_hires")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("coronavirus_virion_hires.png"), "Plan targets hires PNG")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://bioart_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "bioart":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["bioart"]
	var hub_mock := MockBioArtClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://bioart_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/bioart_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(virus_item, "coronavirus_virion_hires")
	check(not prep_res.has("error"), "BioArt preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("NIAID BioArt offline tests complete; failures=%d" % failures)
	quit(failures)
