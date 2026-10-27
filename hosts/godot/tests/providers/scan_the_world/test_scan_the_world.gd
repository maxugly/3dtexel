extends SceneTree
## Comprehensive offline contract and regression tests for Scan The World provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/scan_the_world/provider.gd")
const Client = preload("res://addons/3dtexel/providers/scan_the_world/client.gd")

class MockSTWClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["sculptures"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/scan_the_world/fixtures/sculptures.json"))

	func search(_query := "", _page := 1, _per_page := 24) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["sculptures"]

	func get_bytes(_url: String, destination := "", _max_bytes := 268435456, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var mock_glb := PackedByteArray([0x67, 0x6c, 0x54, 0x46, 2, 0, 0, 0, 20, 0, 0, 0, 0, 0, 0, 0])
		if not destination.is_empty():
			var f := FileAccess.open(destination, FileAccess.WRITE)
			if f:
				f.store_buffer(mock_glb)
				f.close()
			return {}
		return {"bytes": mock_glb}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Scan The World offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "scan_the_world", "Descriptor ID is scan_the_world")
	check(desc.name == "Scan The World", "Descriptor name is Scan The World")
	check(desc.website.contains("myminifactory.com"), "Website points to myminifactory.com")
	check(desc.capabilities.has("model") and desc.capabilities.has("files"), "Capabilities include model and files")
	check(desc.key_env.is_empty(), "Scan The World requires no API key")

	# 2. Attach mock transport
	var mock := MockSTWClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (material category returns empty)
	provider.network_allowed = true
	var mat_resp: Dictionary = await provider.refresh_page("", "material", "")
	check(mat_resp.get("items", []).is_empty(), "Material category returns empty for 3D model provider")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "model", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("victory", "model", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")
	check(search_res.get("next_cursor") == "2", "Next cursor is page 2")

	# 6. Item normalization & license policy
	var item: Dictionary = items[0]
	check(item.id == "104820", "Item ID normalized correctly")
	check(item.provider_id == "scan_the_world", "Provider ID preserved")
	check(item.type == "model", "Asset type is model")
	check(item.title.contains("Winged Victory"), "Title matches fixture")
	check(item.authors[0].name.contains("Louvre"), "Museum matches fixture")

	# License evaluation (CC0 evaluates to PERMISSIVE)
	var lic: Dictionary = item.license
	check(lic.id == "cc0-1.0", "License ID is cc0-1.0")
	var eval_res: Dictionary = Policy.evaluate(item)
	check(eval_res.status == Policy.Status.PERMISSIVE, "CC0 evaluates to PERMISSIVE")

	# Variants
	var vars: Array = item.variants
	check(vars.size() >= 2, "At least 2 mesh format variants available (glb, obj)")
	check(vars[0].id == "glb", "First variant is glb")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://scan_the_world_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "scan_the_world":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["scan_the_world"]
	hub_provider.enabled=true
	var hub_mock := MockSTWClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/scan_the_world_%s" % Time.get_ticks_usec()
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

	print("Scan The World offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
