extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
class FixtureProvider:
	extends "res://addons/3dtexel/core/provider.gd"
	func descriptor() -> Dictionary:return {"id":"restart_fixture","name":"Fixture","website":"https://example.invalid"}
	func refresh_page(query: String,_category: String,_cursor: String) -> Dictionary:
		await get_tree().create_timer(0.4 if query=="old" else 0.02).timeout
		return {"items":[{"provider_id":"restart_fixture","id":query,"title":query,"type":"model","price":{"free":true}}],"next_cursor":""}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var browser := Browser.new();root.add_child(browser);await process_frame
	for provider in browser.client.providers.values():provider.enabled=false
	var fixture := FixtureProvider.new();browser.client.register_provider(fixture);fixture.enabled=true
	browser.client.scope="restart_fixture";browser.seeded=true
	browser.client.catalog=load("res://addons/3dtexel/core/catalog.gd").new()
	browser.client.catalog.root="user://texel_restart_fixture_%s" % Time.get_ticks_usec()
	browser.search.text="old";browser.start_search()
	await create_timer(.04).timeout
	browser.search.text="new";browser.start_search()
	await create_timer(.15).timeout
	var ok := browser.session.query=="new" and browser.session.identities.has("restart_fixture:new")
	await create_timer(.4).timeout
	ok = ok and not browser.client.catalog.records.has("restart_fixture:old") and browser.session.query=="new"
	print("Search replacement and stale result isolation: ","PASS" if ok else "FAIL")
	browser.queue_free();await process_frame
	quit(0 if ok else 1)
