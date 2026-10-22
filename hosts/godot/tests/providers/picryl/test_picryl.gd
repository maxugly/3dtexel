extends SceneTree
## Comprehensive offline contract and regression tests for Picryl provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/picryl/provider.gd")
const Client = preload("res://addons/3dtexel/providers/picryl/client.gd")

class MockPicrylClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["items"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/picryl/fixtures/items.json"))

	func search(_query := "", _page := 1, _page_size := 24) -> Dictionary:
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
	print("Starting Picryl offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "picryl", "Descriptor ID is picryl")
	check(desc.name == "Picryl", "Descriptor name matches")
	check(desc.website.contains("picryl.com"), "Website points to picryl.com")
	check(desc.capabilities.has("image") and desc.capabilities.has("material"), "Capabilities include image and material")
	check(desc.key_env.is_empty(), "Picryl requires no API key")

	# 2. Attach mock transport
	var mock := MockPicrylClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (audio category returns empty)
	provider.network_allowed = true
	var aud_resp: Dictionary = await provider.refresh_page("", "audio", "")
	check(aud_resp.get("items", []).is_empty(), "Audio category returns empty for visual historical provider")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("wright", "image", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")

	# 6. Item normalization & license policy
	var item: Dictionary = items[0]
	check(item.id == "picryl_wright_flyer_flight", "Item ID normalized correctly")
	check(item.provider_id == "picryl", "Provider ID preserved")
	check(item.type == "image", "Item is image")
	check(item.title.contains("Wright Flyer"), "Title matches fixture")
	check(item.authors[0].name.contains("John T. Daniels"), "Author matches fixture")

	# License evaluation (Public Domain evaluates to PERMISSIVE)
	var lic: Dictionary = item.license
	check(lic.id == "public-domain", "License is public-domain")
	var eval_res: Dictionary = Policy.evaluate(item)
	check(eval_res.status == Policy.Status.PERMISSIVE, "Public Domain evaluates to PERMISSIVE")

	# Variants
	var vars: Array = item.variants
	check(vars.size() >= 2, "At least 2 variants available")
	check(vars[0].id == "orig", "First variant is orig")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://picryl_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "picryl":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["picryl"]
	# The site is off by default here, so the test turns it on like a user would.
	hub_provider.enabled = true
	hub_provider.network_allowed = true
	var hub_mock := MockPicrylClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/picryl_%s" % Time.get_ticks_usec()
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

	print("Picryl offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
