extends SceneTree
## Comprehensive offline contract and regression tests for Yale Center for British Art provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/yale_british_art/provider.gd")
const Client = preload("res://addons/3dtexel/providers/yale_british_art/client.gd")

class MockYalClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["artworks"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/yale_british_art/fixtures/artworks.json"))

	func search(_query := "", _page := 1, _page_size := 24) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["artworks"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.NAVY_BLUE)
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
	print("Starting Yale Center for British Art offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "yale_british_art", "Descriptor ID is yale_british_art")
	check(desc.name == "Yale Center for British Art", "Descriptor name matches")
	check(desc.website.contains("britishart.yale.edu"), "Website points to britishart.yale.edu")
	check(desc.capabilities.has("image") and desc.capabilities.has("material"), "Capabilities include image and material")
	check(desc.key_env.is_empty(), "Yale requires no API key")

	# 2. Attach mock transport
	var mock := MockYalClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (model category returns empty)
	provider.network_allowed = true
	var mod_resp: Dictionary = await provider.refresh_page("", "model", "")
	check(mod_resp.get("items", []).is_empty(), "Model category returns empty for 2D museum collection")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("turner", "image", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")

	# 6. Item normalization & license policy
	var item: Dictionary = items[0]
	check(item.id == "ycba_dort_packet_boat_turner", "Item ID normalized correctly")
	check(item.provider_id == "yale_british_art", "Provider ID preserved")
	check(item.title.contains("Dort"), "Title matches fixture")
	check(item.authors[0].name.to_lower().contains("turner"), "Artist matches fixture")

	# License evaluation (CC0 evaluates to PERMISSIVE)
	var lic: Dictionary = item.license
	check(lic.id == "cc0-1.0", "License ID is cc0-1.0")
	var eval_res: Dictionary = Policy.evaluate(item)
	check(eval_res.status == Policy.Status.PERMISSIVE, "CC0 evaluates to PERMISSIVE")

	# Variants
	var vars: Array = item.variants
	check(vars.size() >= 2, "At least 2 resolution variants available")
	check(vars[0].id == "orig", "First variant is orig")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://yale_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "yale_british_art":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["yale_british_art"]
	var hub_mock := MockYalClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/yale_%s" % Time.get_ticks_usec()
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

	print("Yale Center for British Art offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
