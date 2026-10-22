extends SceneTree
## Comprehensive offline contract and regression tests for Openverse provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/openverse/provider.gd")
const Client = preload("res://addons/3dtexel/providers/openverse/client.gd")

class MockOpenverseClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["items"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/openverse/fixtures/items.json"))

	func search(_query := "", _category := "image", _page := 1, _page_size := 24) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["items"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var fake_data := PackedByteArray([
			0xFF, 0xD8, 0xFF, 0xE0, # JPEG header
			0x00, 0x10, 0x4A, 0x46
		])
		if not destination.is_empty():
			var f := FileAccess.open(destination, FileAccess.WRITE)
			if f:
				f.store_buffer(fake_data)
				f.close()
			return {}
		return {"bytes": fake_data}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Openverse offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "openverse", "Descriptor ID is openverse")
	check(desc.name == "Openverse", "Descriptor name matches")
	check(desc.website.contains("openverse.org"), "Website points to openverse.org")
	check(desc.capabilities.has("image") and desc.capabilities.has("audio"), "Capabilities include image and audio")
	check(desc.key_env.is_empty(), "Openverse requires no API key")

	# 2. Attach mock transport
	var mock := MockOpenverseClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (model category returns empty)
	provider.network_allowed = true
	var mod_resp: Dictionary = await provider.refresh_page("", "model", "")
	check(mod_resp.get("items", []).is_empty(), "Model category returns empty for 2D/audio aggregator")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("tree", "image", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")

	# 6. Item normalization & license policy
	var item0: Dictionary = items[0]
	check(item0.id.contains("e302ba7c"), "Item 0 ID normalized correctly")
	check(item0.provider_id == "openverse", "Provider ID preserved")
	check(item0.type == "image", "Item 0 is image")
	check(item0.title.contains("Olive Tree"), "Title matches fixture")

	# License evaluation: item 0 is CC0 -> PERMISSIVE
	var lic0: Dictionary = item0.license
	check(lic0.id == "cc0-1.0", "License 0 is cc0-1.0")
	var eval_res0: Dictionary = Policy.evaluate(item0)
	check(eval_res0.status == Policy.Status.PERMISSIVE, "CC0 evaluates to PERMISSIVE")

	# License evaluation: item 1 is CC-BY -> ATTRIBUTION
	var item1: Dictionary = items[1]
	check(item1.id.contains("a904bc12"), "Item 1 ID normalized correctly")
	check(item1.type == "audio", "Item 1 is audio")
	var lic1: Dictionary = item1.license
	check(lic1.id == "cc-by-4.0", "License 1 is cc-by-4.0")
	var eval_res1: Dictionary = Policy.evaluate(item1)
	check(eval_res1.status == Policy.Status.ATTRIBUTION, "CC-BY evaluates to ATTRIBUTION")

	# Variants
	var vars: Array = item0.variants
	check(vars.size() >= 2, "At least 2 variants available")
	check(vars[0].id == "orig", "First variant is orig")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://openverse_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "openverse":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["openverse"]
	var hub_mock := MockOpenverseClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/openverse_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(item0, vars[0].id)
	check(not prep_res.is_empty(), "Preparation result is non-empty")
	check(hub_mock.downloaded_files > 0, "Mock transport performed download")

	# Cleanup test output directory
	if DirAccess.dir_exists_absolute(prep.output_directory):
		var d := DirAccess.open(prep.output_directory)
		if d:
			for f in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(prep.output_directory)

	print("Openverse offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
