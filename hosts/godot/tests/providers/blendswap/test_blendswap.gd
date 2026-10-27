extends SceneTree
## Comprehensive offline contract and regression tests for Blend Swap provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

const Provider = preload("res://addons/3dtexel/providers/blendswap/provider.gd")
const Client = preload("res://addons/3dtexel/providers/blendswap/client.gd")

class MockBlendSwapClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}
	var simulate_paid_download := false

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/blendswap/fixtures/search.json"))
		fixtures["download_free"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/blendswap/fixtures/download_free.json"))
		fixtures["download_paid"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/blendswap/fixtures/download_paid.json"))

	func search(_query := "", _page := 1, _limit := 25) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["search"]

	func get_download(_asset_id: int, _file_id := 0) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network downloads require explicit authorization."}
		if simulate_paid_download:
			var paid: Dictionary = fixtures["download_paid"]
			var spent: int = int(paid.get("credits_spent", 10))
			return {"error": "Download blocked: requires %d paid credits. Only zero-credit assets may be imported." % spent}
		return fixtures["download_free"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		# BLENDER header signature: "BLENDER_v420"
		var fake_blend := PackedByteArray([
			0x42, 0x4C, 0x45, 0x4E, 0x44, 0x45, 0x52, # "BLENDER"
			0x2D, 0x76, 0x34, 0x32, 0x30             # "-v420"
		])
		if not destination.is_empty():
			var f := FileAccess.open(destination, FileAccess.WRITE)
			if f:
				f.store_buffer(fake_blend)
				f.close()
				return {}
			return {"error": "Cannot write destination file."}
		return {"bytes": fake_blend}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Blend Swap offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "blendswap", "Descriptor ID is blendswap")
	check(desc.name == "Blend Swap", "Descriptor name matches")
	check(desc.website.contains("blendswap.com"), "Website points to blendswap.com")
	check(desc.capabilities.has("model") and desc.capabilities.has("files") and desc.capabilities.has("variants"), "Capabilities include model, files, and variants")
	check(desc.key_env.has("BLENDSWAP_KEY") and desc.key_env.has("BLENDSWAP_API_KEY"), "Key env includes BLENDSWAP_KEY and BLENDSWAP_API_KEY")

	# 2. Credential handling
	if provider.api_key().is_empty():
		check(provider.credential_status().contains("Public browse mode"), "Status shows public browse mode when key is absent")
	else:
		check(provider.credential_status() == "API key configured.", "Status reflects configured key from environment")
	provider.set_session_key("bsk_live_testkey12345")
	check(provider.api_key() == "bsk_live_testkey12345", "Session key sets api_key")
	check(provider.credential_status() == "API key configured.", "Status reflects configured key")

	# 3. Attach mock transport
	var mock := MockBlendSwapClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)
	mock.cache.root = "user://blendswap_test_cache_%s" % Time.get_ticks_usec()

	# 4. Category filtering
	provider.network_allowed = true
	var aud_resp: Dictionary = await provider.refresh_page("", "audio", "")
	check(aud_resp.get("items", []).is_empty(), "Audio category returns empty for 3D model repository")

	# 5. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "model", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 6. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("pumpkin", "model", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 3, "Found 3 items in search fixture")

	# 7. Item normalization & license policy
	var pumpkin_item: Dictionary = items[0]
	check(pumpkin_item.id == "26300", "Pumpkin ID is 26300")
	check(pumpkin_item.provider_id == "blendswap", "Provider ID preserved")
	check(pumpkin_item.type == "model", "Item is model")
	check(pumpkin_item.title.contains("Stylized Pumpkin"), "Title matches fixture")
	check(pumpkin_item.authors[0].name == "PumpkinArtist", "Author matches fixture")
	check(pumpkin_item.license.id == "cc0", "Pumpkin license is CC0")
	var eval_pumpkin: Dictionary = Policy.evaluate(pumpkin_item)
	check(eval_pumpkin.status == Policy.Status.PERMISSIVE, "CC0 evaluates to PERMISSIVE")

	var drone_item: Dictionary = items[1]
	check(drone_item.id == "28450", "Drone ID is 28450")
	check(drone_item.license.id == "cc-by-4.0", "Drone license is CC-BY")
	check(drone_item.license.attribution_required == true, "Drone requires attribution")
	var eval_drone: Dictionary = Policy.evaluate(drone_item)
	check(eval_drone.status == Policy.Status.ATTRIBUTION, "CC-BY evaluates to ATTRIBUTION")

	var restricted_item: Dictionary = items[2]
	check(restricted_item.id == "29999", "Restricted ID is 29999")
	check(restricted_item.license.id == "cc-by-nc-4.0", "Restricted license is CC-BY-NC")
	var eval_restricted: Dictionary = Policy.evaluate(restricted_item)
	check(eval_restricted.status == Policy.Status.BLOCKED, "CC-BY-NC evaluates to BLOCKED")

	# 8. Variants
	var pumpkin_vars: Array = provider.variants(pumpkin_item)
	check(pumpkin_vars.size() >= 1, "At least 1 variant available for pumpkin")
	check(pumpkin_vars[0].id == "blend", "Variant is blend")
	check(pumpkin_vars[0].label.contains("stylized_pumpkin.blend"), "Variant label includes blend filename")

	# 9. Zero-Credit Guardrail
	mock.simulate_paid_download = true
	provider.set_session_key("bsk_live_testkey12345")
	var paid_dl_plan: Dictionary = await provider.resolve_download(pumpkin_item, "blend")
	check(paid_dl_plan.has("error"), "Paid download is blocked by zero-credit guardrail")
	check(paid_dl_plan.error.contains("paid credits"), "Error indicates paid credit requirement")
	mock.simulate_paid_download = false

	# 10. Preparation & Mock Download via Registry and Preparation
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://blendswap_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "blendswap":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["blendswap"]
	hub_provider.enabled = true
	hub_provider.network_allowed = true
	var hub_mock := MockBlendSwapClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/blendswap_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(pumpkin_item, "blend")
	check(not prep_res.has("error"), "Preparation result succeeded without error: " + str(prep_res.get("error", "")))
	check(hub_mock.downloaded_files > 0, "Mock transport performed file download")

	# Verify sidecar provenance
	var expected_folder := prep.output_directory.path_join("blendswap").path_join(
		"%s_%s" % [Importer.slug(str(pumpkin_item.title)), Importer.slug(str(pumpkin_item.id)) + "_" + str(pumpkin_item.id).sha256_text().left(12)]
	).path_join("blend")

	var blend_path := expected_folder.path_join("stylized_pumpkin.blend")
	check(FileAccess.file_exists(blend_path), "Downloaded .blend file exists on disk")
	check(FileAccess.file_exists(blend_path + ".credits.json"), "Credits sidecar exists beside .blend file")
	check(FileAccess.file_exists(expected_folder.path_join("provenance.json")), "provenance.json exists")

	var sidecar_text := FileAccess.get_file_as_string(blend_path + ".credits.json")
	check("PumpkinArtist" in sidecar_text, "Author preserved in credits sidecar")
	check("CC0" in sidecar_text or "cc0" in sidecar_text, "License preserved in credits sidecar")
	check("bsk_live_" not in sidecar_text, "API keys never saved in sidecars")

	# Cleanup test output directory
	if DirAccess.dir_exists_absolute(prep.output_directory):
		var d := DirAccess.open(prep.output_directory)
		if d:
			for sub in d.get_directories():
				var sub_dir := DirAccess.open(prep.output_directory.path_join(sub))
				if sub_dir:
					for sub2 in sub_dir.get_directories():
						var sub2_dir := DirAccess.open(prep.output_directory.path_join(sub).path_join(sub2))
						if sub2_dir:
							for sub3 in sub2_dir.get_directories():
								var sub3_dir := DirAccess.open(prep.output_directory.path_join(sub).path_join(sub2).path_join(sub3))
								if sub3_dir:
									for f in sub3_dir.get_files():
										sub3_dir.remove(f)
									DirAccess.remove_absolute(prep.output_directory.path_join(sub).path_join(sub2).path_join(sub3))
							for f in sub2_dir.get_files():
								sub2_dir.remove(f)
							DirAccess.remove_absolute(prep.output_directory.path_join(sub).path_join(sub2))
					for f in sub_dir.get_files():
						sub_dir.remove(f)
					DirAccess.remove_absolute(prep.output_directory.path_join(sub))
			DirAccess.remove_absolute(prep.output_directory)

	provider.queue_free()
	prep.queue_free()
	hub.queue_free()
	await process_frame

	print("Blend Swap offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
