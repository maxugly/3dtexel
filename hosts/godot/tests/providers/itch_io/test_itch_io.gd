extends SceneTree
## Comprehensive offline contract and regression tests for itch.io provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/itch_io/provider.gd")
const Client = preload("res://addons/3dtexel/providers/itch_io/client.gd")

class MockItchIOClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["feed"] = FileAccess.get_file_as_string("res://tests/providers/itch_io/fixtures/feed_game_assets.xml")

	func fetch_feed(_path := "/game-assets/free.xml") -> Dictionary:
		calls += 1
		return {"text": fixtures["feed"]}

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock itch.io ZIP content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.CRIMSON)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting itch.io offline provider tests...")

	# 1. Descriptor and credentials
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "itch_io", "Descriptor ID is itch_io")
	check(desc.name == "itch.io", "Descriptor name is itch.io")
	check(desc.website.contains("itch.io"), "Website points to itch.io")
	check("ITCHIO_API_KEY" in desc.key_env, "key_env includes ITCHIO_API_KEY")

	check("Public browse enabled" in provider.credential_status(), "Explains public browse is active without key")
	provider.set_session_key("secret_itch_key_999")
	check("configured" in provider.credential_status(), "Reports key configured after setting")
	check(not "secret_itch_key_999" in provider.credential_status(), "API key is not leaked in status string")

	# 2. Attach mock transport
	var mock_client := MockItchIOClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://itch_io_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Search and pagination via XML feed
	var search_res: Dictionary = await provider.refresh_page("", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 assets from feed fixture")

	var dungeon_item: Dictionary = search_res.items[0]
	check(dungeon_item.id == "kay_kit_dungeon_remastered", "Dungeon ID extracted")
	check(dungeon_item.type == "model", "Dungeon pack detected as model")
	check(dungeon_item.authors[0].name == "Kay Lousberg", "Creator is Kay Lousberg")
	check(dungeon_item.price.free == true, "Asset is free")

	var sfx_item: Dictionary = search_res.items[1]
	check(sfx_item.id == "retro_sci_fi_sfx", "SFX ID extracted")
	check(sfx_item.type == "audio", "SFX detected as audio")
	check(sfx_item.authors[0].name == "SubSpaceAudio", "Creator is SubSpaceAudio")

	# 4. Variants
	var vars := provider.variants(dungeon_item)
	check(vars.size() >= 1, "Variants include zip archive")
	check(vars[0].id == "zip", "Variant id is zip")

	# 5. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(dungeon_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "CC0 declared asset evaluates to PERMISSIVE")

	# 6. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(dungeon_item, "zip")
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() == 1, "Plan has 1 file")
	check(plan.files[0].filename.contains("kay_kit_dungeon_remastered.zip"), "Filename matches asset ID")

	# 7. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://itch_io_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "itch_io":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["itch_io"]
	var hub_mock := MockItchIOClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://itch_io_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/itch_io_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(dungeon_item, "zip")
	check(not prep_res.has("error"), "itch.io preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("itch.io offline tests complete; failures=%d" % failures)
	quit(failures)
