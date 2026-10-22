extends SceneTree
## Comprehensive offline contract and regression tests for Kenney provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/kenney/provider.gd")
const Client = preload("res://addons/3dtexel/providers/kenney/client.gd")

class MockKenneyClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["packs"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/kenney/fixtures/packs.json"))

	func fetch_packs() -> Dictionary:
		calls += 1
		return {"items": fixtures["packs"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Kenney ZIP package content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.DODGER_BLUE)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Kenney offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "kenney", "Descriptor ID is kenney")
	check(desc.name == "Kenney", "Descriptor name is Kenney")
	check(desc.website.contains("kenney.nl"), "Website points to kenney.nl")
	check(desc.key_env.is_empty(), "Kenney requires no API key")
	check(provider.credential_status() == "No key required.", "Credential status explains no key needed")
	check(provider.api_key().is_empty(), "No API key stored")

	# 2. Attach mock transport
	var mock_client := MockKenneyClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://kenney_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Search and category filtering
	var search_res: Dictionary = await provider.refresh_page("blaster", "all", "")
	check(search_res.items.size() == 1, "Search for 'blaster' yields 1 asset")

	var blaster_item: Dictionary = search_res.items[0]
	check(blaster_item.id == "blaster_kit", "Blaster Kit ID matches")
	check(blaster_item.type == "model", "Type is model")
	check(blaster_item.license.id == "cc0", "License is CC0")
	check(blaster_item.price.free == true, "Asset is free")

	var audio_res: Dictionary = await provider.refresh_page("", "audio", "")
	check(audio_res.items.size() == 1, "Audio category returns interface-sounds")
	check(audio_res.items[0].id == "interface_sounds", "Interface sounds ID matches")

	var mat_res: Dictionary = await provider.refresh_page("", "material", "")
	check(mat_res.items.size() == 1, "Material category returns prototype-textures")

	# 4. Variants
	var vars := provider.variants(blaster_item)
	check(vars.size() >= 1, "Variants include zip package")
	check(vars[0].id == "blaster_kit", "First variant is blaster_kit")

	# 5. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(blaster_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Kenney CC0 evaluates to PERMISSIVE")

	# 6. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(blaster_item, "blaster_kit")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan has 1 file")
	check(plan.files[0].filename == "blaster_kit.zip", "Filename is blaster_kit.zip")

	# 7. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://kenney_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "kenney":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["kenney"]
	var hub_mock := MockKenneyClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://kenney_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/kenney_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(blaster_item, "blaster_kit")
	check(not prep_res.has("error"), "Kenney preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Kenney offline tests complete; failures=%d" % failures)
	quit(failures)
