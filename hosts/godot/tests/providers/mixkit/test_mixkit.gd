extends SceneTree
## Comprehensive offline contract and regression tests for Mixkit Audio provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/mixkit/provider.gd")
const Client = preload("res://addons/3dtexel/providers/mixkit/client.gd")

class MockMixkitClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["sounds"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/mixkit/fixtures/sounds.json"))

	func search(_query := "", _page := 1, _page_size := 24) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["sounds"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var fake_audio := PackedByteArray([
			0x49, 0x44, 0x33, # "ID3" tag
			0x03, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x20
		])
		if not destination.is_empty():
			var f := FileAccess.open(destination, FileAccess.WRITE)
			if f:
				f.store_buffer(fake_audio)
				f.close()
			return {}
		return {"bytes": fake_audio}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Mixkit Audio offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "mixkit", "Descriptor ID is mixkit")
	check(desc.name == "Mixkit Audio", "Descriptor name matches")
	check(desc.website.contains("mixkit.co"), "Website points to mixkit.co")
	check(desc.capabilities.has("audio") and desc.capabilities.has("files"), "Capabilities include audio and files")
	check(desc.key_env.is_empty(), "Mixkit requires no API key")

	# 2. Attach mock transport
	var mock := MockMixkitClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (image category returns empty)
	provider.network_allowed = true
	var img_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(img_resp.get("items", []).is_empty(), "Image category returns empty for audio provider")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "audio", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("arcade", "audio", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")

	# 6. Item normalization & license policy
	var item: Dictionary = items[0]
	check(item.id == "mixkit_game_level_music", "Item ID normalized correctly")
	check(item.provider_id == "mixkit", "Provider ID preserved")
	check(item.type == "audio", "Item type is audio")
	check(item.title.contains("Arcade"), "Title matches fixture")
	check(item.authors[0].name.contains("Mixkit"), "Author matches fixture")

	# License evaluation (Royalty-free evaluates to PERMISSIVE)
	var lic: Dictionary = item.license
	check(lic.id == "cc0-1.0", "License ID is cc0-1.0")
	var eval_res: Dictionary = Policy.evaluate(item)
	check(eval_res.status == Policy.Status.PERMISSIVE, "Mixkit license evaluates to PERMISSIVE")

	# Variants
	var vars: Array = item.variants
	check(vars.size() >= 2, "At least 2 audio variants available")
	check(vars[0].id == "mp3", "First variant is mp3")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://mixkit_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "mixkit":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["mixkit"]
	hub_provider.enabled=true
	# The site is off by default here, so the test turns it on like a user would.
	hub_provider.enabled = true
	hub_provider.network_allowed = true
	var hub_mock := MockMixkitClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/mixkit_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(item, vars[0].id)
	check(not prep_res.is_empty(), "Preparation result is non-empty")
	check(hub_mock.downloaded_files > 0, "Mock transport performed download")

	# Cleanup test output directory
	if DirAccess.dir_exists_absolute(prep.output_directory):
		var d := DirAccess.open(prep.output_directory)
		if d:
			for f in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(prep.output_directory)

	print("Mixkit Audio offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
