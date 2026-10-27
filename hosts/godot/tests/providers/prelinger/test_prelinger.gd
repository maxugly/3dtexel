extends SceneTree
## Comprehensive offline contract and regression tests for Prelinger Archives provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/prelinger/provider.gd")
const Client = preload("res://addons/3dtexel/providers/prelinger/client.gd")

class MockPrelingerClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		fixtures["search"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/prelinger/fixtures/search.json"))

	func search(_query := "", _page := 1, _rows := 30) -> Dictionary:
		calls += 1
		return fixtures["search"]

	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		downloaded_files += 1
		var content := "Mock Prelinger media binary content for " + url
		if not destination.is_empty():
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				return {}
			return {"error": "Cannot write destination file"}
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.DARK_KHAKI)
		return {"bytes": img.save_png_to_buffer()}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Prelinger Archives offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "prelinger", "Descriptor ID is prelinger")
	check(desc.name == "Prelinger Archives", "Descriptor name is Prelinger Archives")
	check(desc.website.contains("archive.org"), "Website points to archive.org")
	check(desc.capabilities.has("image") or desc.capabilities.has("audio"), "Capabilities include image or audio")
	check(desc.key_env.is_empty(), "Prelinger Archives requires no API key")

	# 2. Attach mock transport
	var mock_client := MockPrelingerClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = mock_client
	provider.add_child(mock_client)
	mock_client.cache.root = "user://prelinger_test_cache_%s" % Time.get_ticks_usec()
	provider.network_allowed = true

	# 3. Model category returns empty
	var model_res: Dictionary = await provider.refresh_page("", "model", "")
	check(model_res.items.is_empty(), "Model category returns empty without errors")

	# 4. Search and pagination
	var search_res: Dictionary = await provider.refresh_page("duck", "all", "")
	check(search_res.items.size() == 2, "Search yields 2 items from fixture")

	var duck_item: Dictionary = search_res.items[0]
	check(duck_item.id == "duckandc1951", "ID matches duckandc1951")
	check(duck_item.license.id == "public-domain", "License is public domain")
	check(duck_item.price.free == true, "Asset is free")

	# 5. Variants
	var vars := provider.variants(duck_item)
	check(vars.size() >= 2, "Variants include mp4 and mp3: size=%d" % vars.size())

	# 6. License policy evaluation
	var policy_eval: Dictionary = Policy.evaluate(duck_item)
	check(policy_eval.status == Policy.Status.PERMISSIVE, "Prelinger public domain evaluates to PERMISSIVE")

	# 7. Download plan resolution
	var plan: Dictionary = await provider.resolve_download(duck_item, vars[0].id)
	check(plan.kind == "files", "Download plan kind is files")
	check(plan.files.size() > 0, "Plan contains downloadable files")
	check(plan.files[0].url.contains("DuckandC1951"), "Plan targets DuckandC1951 media")

	# 8. Registry integration and Preparation engine
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://prelinger_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "prelinger":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["prelinger"]
	hub_provider.enabled=true
	var hub_mock := MockPrelingerClient.new()
	hub_provider.client.queue_free()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_mock.cache.root = "user://prelinger_hub_cache_%s" % Time.get_ticks_usec()
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/prelinger_fixture_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(duck_item, vars[0].id)
	check(not prep_res.has("error"), "Prelinger preparation succeeded: " + str(prep_res.get("error", "")))

	# Cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prep.output_directory))
	prep.queue_free()
	hub.queue_free()
	provider.queue_free()

	print("Prelinger Archives offline tests complete; failures=%d" % failures)
	quit(failures)
