extends SceneTree
## Offline contract and regression tests for BlenderKit provider.

const Provider = preload("res://addons/3dtexel/providers/blenderkit/provider.gd")
const Client = preload("res://addons/3dtexel/providers/blenderkit/client.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")

class MockBlenderKitClient:
	extends Client
	var calls := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/blenderkit/fixtures/search.json"))
		fixtures["detail"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/blenderkit/fixtures/detail.json"))
		fixtures["download"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/blenderkit/fixtures/download.json"))

	func search(_query := "", _page := 1, _limit := 25) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["search"]

	func get_asset(_asset_id: String) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network requests require explicit action."}
		return fixtures["detail"]

	func get_download_url(_endpoint: String) -> Dictionary:
		calls += 1
		if not network_allowed:
			return {"error": "Network downloads require explicit authorization."}
		return fixtures["download"]

	func get_bytes(_url: String, destination := "", _max_bytes := 134217728, _redirects := 5) -> Dictionary:
		calls += 1
		var fake_data := PackedByteArray([0x67, 0x6c, 0x54, 0x46]) # "glTF"
		if not destination.is_empty():
			var f := FileAccess.open(destination, FileAccess.WRITE)
			if f:
				f.store_buffer(fake_data)
				f.close()
				return {}
			return {"error": "Cannot write destination file."}
		return {"bytes": fake_data}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILURE: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting BlenderKit offline provider tests...")

	# 1. Descriptor
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "blenderkit", "Descriptor ID is blenderkit")
	check(desc.name == "BlenderKit", "Descriptor name is BlenderKit")
	check(desc.website.contains("blendkit.com"), "Website points to blendkit.com")
	check(desc.capabilities.has("model") and desc.capabilities.has("files") and desc.capabilities.has("variants"), "Capabilities include model, files, variants")
	check(desc.key_env.has("BLENDERKIT_API_KEY"), "Key env includes BLENDERKIT_API_KEY")

	# 2. Credentials
	provider.set_session_key("bk_test_token_12345")
	check(provider.api_key() == "bk_test_token_12345", "Session key sets api_key")
	check(provider.credential_status() == "API token configured.", "Status reflects configured key")

	# 3. Attach Mock Transport
	var mock := MockBlenderKitClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)
	mock.cache.root = "user://blenderkit_test_cache_%s" % Time.get_ticks_usec()

	# 4. Category filtering
	provider.network_allowed = true
	var aud_resp: Dictionary = await provider.refresh_page("", "audio", "")
	check(aud_resp.get("items", []).is_empty(), "Audio category returns empty for 3D model repository")

	# 5. Search results
	var res: Dictionary = await provider.refresh_page("assassin", "model", "")
	check(not res.has("error"), "Search does not error")
	var items: Array = res.get("items", [])
	check(items.size() > 0, "Returns search results")

	var first: Dictionary = items[0]
	check(first.provider_id == "blenderkit", "Provider ID normalized")
	check(first.type == "model", "Asset type is model")
	check(first.title.contains("Assassin"), "Title parsed from fixture: " + str(first.title))
	check(first.price.free == true and first.price.credits == 0, "Zero-credit confirmed free")
	check(first.authors.size() > 0, "Author preserved")
	check(first.variants.size() > 0, "Variants populated")

	# 6. Resolve download
	var plan: Dictionary = await provider.resolve_download(first, "gltf_godot")
	check(not plan.has("error"), "Download plan resolved successfully")
	check(plan.kind == "files", "Plan kind is files")
	check(plan.files.size() > 0, "Plan files present")
	check(str(plan.files[0].url).begins_with("https://"), "Signed URL returned")

	# 7. Policy
	check(int(first.policy.status) != Policy.Status.BLOCKED, "Free asset is not blocked by license policy")

	provider.queue_free()
	print("BlenderKit offline provider tests complete; failures=%d" % failures)
	quit(1 if failures > 0 else 0)
