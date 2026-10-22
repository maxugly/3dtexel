extends SceneTree
## Offline contract tests for the Kenney provider. Kenney publishes HTML, so the
## fixtures are trimmed copies of a real listing page and a real pack page.

const Provider = preload("res://addons/3dtexel/providers/kenney/provider.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")

class FixtureClient:
	extends "res://addons/3dtexel/providers/kenney/client.gd"
	var requested: Array[String] = []
	func text_request(path_or_url: String) -> Dictionary:
		requested.append(path_or_url)
		if path_or_url.contains("page:2"):
			return {"raw_text": "<html><body>no more</body></html>"}
		if path_or_url.contains("platformer-art-buildings"):
			return {"raw_text": FileAccess.get_file_as_string("res://tests/providers/kenney/fixtures/pack.html")}
		return {"raw_text": FileAccess.get_file_as_string("res://tests/providers/kenney/fixtures/listing.html")}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var provider := Provider.new()
	root.add_child(provider)
	provider.network_allowed = true

	var fixture := FixtureClient.new()
	provider.client.queue_free()
	provider.remove_child(provider.client)
	provider.client = fixture
	provider.add_child(fixture)
	fixture.cache.root = "user://kenney_test_cache_%s" % Time.get_ticks_usec()

	var desc := provider.descriptor()
	check(desc.id == "kenney", "Descriptor ID is kenney")
	check(desc.name == "Kenney", "Descriptor name is Kenney")
	check(desc.key_env.is_empty(), "Kenney requires no API key")

	var page: Dictionary = await provider.refresh_page("platformer", "all", "")
	check(page.get("items", []).size() == 2, "Listing yields two packs from the fixture")
	check(page.get("next_cursor", "") == "2", "A following page is advertised")
	check(fixture.requested[0].contains("search=platformer"), "The query is sent as a bounded site search")

	var first: Dictionary = page.get("items", [])[0]
	check(first.get("title", "") == "Platformer Art Buildings", "Title is read from the card heading")
	check(str(first.get("url", "")).ends_with("/assets/platformer-art-buildings"), "Card link is kept as the page address")
	check(str(first.get("thumbnail", "")).ends_with("sample-400x.png"), "Cover image is kept as the thumbnail")
	check(first.get("license", {}).get("id", "") == "cc0", "Kenney packs are CC0")
	check(first.get("price", {}).get("free", false), "Kenney packs are free")
	check(Policy.evaluate(first).status == Policy.Status.PERMISSIVE, "CC0 pack evaluates to PERMISSIVE")

	# The pack page carries the real archive link, so downloads resolve.
	var plan: Dictionary = await provider.resolve_download(first, "zip")
	check(not plan.has("error"), "Download plan resolves: " + str(plan.get("error", "")))
	check(plan.get("files", []).size() == 1, "Plan carries one archive")
	check(str(plan.get("files", [{}])[0].get("url", "")).ends_with(".zip"), "Archive points at a zip")

	provider.queue_free()
	await process_frame
	print("Kenney offline tests complete; failures=%d" % failures)
	quit(failures)
