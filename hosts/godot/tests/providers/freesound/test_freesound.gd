extends SceneTree
## Comprehensive offline contract and regression tests for Freesound provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/freesound/provider.gd")
const Client = preload("res://addons/3dtexel/providers/freesound/client.gd")

class MockFreesoundClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["sounds"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/freesound/fixtures/sounds.json"))

	func search(_query := "", _page := 1, _page_size := 24) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["sounds"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var fake_audio := PackedByteArray([
			0x52, 0x49, 0x46, 0x46, # "RIFF"
			0x24, 0x00, 0x00, 0x00, # size
			0x57, 0x41, 0x56, 0x45, # "WAVE"
			0x66, 0x6d, 0x74, 0x20  # "fmt "
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
	print("Starting Freesound offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "freesound", "Descriptor ID is freesound")
	check(desc.name == "Freesound", "Descriptor name matches")
	check(desc.website.contains("freesound.org"), "Website points to freesound.org")
	check(desc.capabilities.has("audio") and desc.capabilities.has("files"), "Capabilities include audio and files")
	check(desc.key_env.has("FREESOUND_API_KEY"), "Key env lists FREESOUND_API_KEY")

	# 2. Attach mock transport
	var mock := MockFreesoundClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (image/model/material category returns empty)
	provider.network_allowed = true
	var img_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(img_resp.get("items", []).is_empty(), "Image category returns empty for audio provider")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "audio", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("laser", "audio", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")

	# 6. Item normalization & license policy
	var item0: Dictionary = items[0]
	check(item0.id == "12345", "Item 0 ID normalized correctly")
	check(item0.provider_id == "freesound", "Provider ID preserved")
	check(item0.type == "audio", "Item type is audio")
	check(item0.title.contains("Laser"), "Title matches fixture")
	check(item0.authors[0].name == "sound_wizard", "Author matches fixture")

	# License evaluation: item 0 is CC0 -> PERMISSIVE
	var lic0: Dictionary = item0.license
	check(lic0.id == "cc0-1.0", "License 0 is cc0-1.0")
	var eval_res0: Dictionary = Policy.evaluate(item0)
	check(eval_res0.status == Policy.Status.PERMISSIVE, "CC0 evaluates to PERMISSIVE")

	# License evaluation: item 1 is CC-BY -> ATTRIBUTION
	var item1: Dictionary = items[1]
	check(item1.id == "67890", "Item 1 ID normalized correctly")
	check(item1.type == "audio", "Item 1 type is audio")
	var lic1: Dictionary = item1.license
	check(lic1.id == "cc-by-4.0", "License 1 is cc-by-4.0")
	var eval_res1: Dictionary = Policy.evaluate(item1)
	check(eval_res1.status == Policy.Status.ATTRIBUTION, "CC-BY evaluates to ATTRIBUTION")

	# Variants
	var vars: Array = item0.variants
	check(vars.size() >= 3, "At least 3 audio variants available")
	check(vars[0].id == "mp3_hq", "First variant is mp3_hq")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://freesound_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "freesound":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["freesound"]
	# The site is off by default here, so the test turns it on like a user would.
	hub_provider.enabled = true
	hub_provider.network_allowed = true
	var hub_mock := MockFreesoundClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/freesound_%s" % Time.get_ticks_usec()
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

	print("Freesound offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
