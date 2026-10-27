extends SceneTree
## Comprehensive offline contract and regression tests for NASA Visible Earth provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/nasa_visible_earth/provider.gd")
const Client = preload("res://addons/3dtexel/providers/nasa_visible_earth/client.gd")

class MockVisibleEarthClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["earth"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/nasa_visible_earth/fixtures/earth.json"))

	func search(_query := "", _page := 1, _page_size := 24) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["earth"]

	func get_bytes(url: String, destination := "", _max_bytes := 134217728, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.ROYAL_BLUE)
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
	print("Starting NASA Visible Earth offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "nasa_visible_earth", "Descriptor ID is nasa_visible_earth")
	check(desc.name == "NASA Visible Earth", "Descriptor name is NASA Visible Earth")
	check(desc.website.contains("visibleearth.nasa.gov"), "Website points to visibleearth.nasa.gov")
	check(desc.capabilities.has("image") and desc.capabilities.has("material"), "Capabilities include image and material")
	check(desc.key_env.is_empty(), "NASA Visible Earth requires no API key")

	# 2. Attach mock transport
	var mock := MockVisibleEarthClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 4. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("marble", "image", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")
	check(search_res.get("next_cursor") == "2", "Next cursor is page 2")

	# 5. Item normalization & license policy
	var item: Dictionary = items[0]
	check(item.id == "blue_marble_next_generation_july", "Item ID normalized correctly")
	check(item.provider_id == "nasa_visible_earth", "Provider ID preserved")
	check(item.title.contains("Blue Marble"), "Title matches fixture")
	check(item.authors[0].name.contains("NASA Earth Observatory"), "Author matches fixture")

	# License evaluation (Public Domain evaluates to PERMISSIVE)
	var lic: Dictionary = item.license
	check(lic.id == "public-domain", "License ID is public-domain")
	var eval_res: Dictionary = Policy.evaluate(item)
	check(eval_res.status == Policy.Status.PERMISSIVE, "Public Domain evaluates to PERMISSIVE")

	# Variants
	var vars: Array = item.variants
	check(vars.size() >= 3, "At least 3 resolution variants available")

	# 6. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://nasa_visible_earth_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "nasa_visible_earth":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["nasa_visible_earth"]
	hub_provider.enabled=true
	var hub_mock := MockVisibleEarthClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/nasa_visible_earth_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(item, vars[1].id)
	check(not prep_res.is_empty(), "Preparation result is non-empty")
	check(hub_mock.downloaded_files > 0, "Mock transport performed download")

	# Cleanup test output directory
	if DirAccess.dir_exists_absolute(prep.output_directory):
		var d := DirAccess.open(prep.output_directory)
		if d:
			for f in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(prep.output_directory)

	print("NASA Visible Earth offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
