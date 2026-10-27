extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
class SlowCache:
	extends RefCounted
	var root := ""
	var loaded := false
	func ensure_loaded() -> void:
		OS.delay_msec(150) # Simulates slow local disk work, never provider traffic.
		loaded=true
class FixtureClient:
	extends Node
	var cache := SlowCache.new()
class FixtureProvider:
	extends "res://addons/3dtexel/core/provider.gd"
	var client := FixtureClient.new()
	var local_calls := 0
	func _init():add_child(client)
	func descriptor() -> Dictionary:return {"id":"responsive_fixture","name":"Fixture","website":"https://example.invalid"}
	func local_assets() -> Array:local_calls+=1;return []
	func refresh_page(_query: String,_category: String,_cursor: String) -> Dictionary:return {"items":[],"next_cursor":""}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var browser := Browser.new();root.add_child(browser);await process_frame
	for provider in browser.client.providers.values():provider.enabled=false
	var fixture := FixtureProvider.new();browser.client.register_provider(fixture);fixture.enabled=true
	browser.client.catalog.root="user://responsive_catalog_%s" % Time.get_ticks_usec()
	browser.client.inventory.root=browser.client.catalog.root+"_imports"
	browser.start_search()
	check(browser.busy and browser.status.text=="Preparing search…","Search acknowledges the click immediately")
	await create_timer(.025).timeout
	check(browser.busy and not fixture.client.cache.loaded,"The UI processes timers while disk preparation runs")
	var frames := 0;var deadline := Time.get_ticks_msec()+5000
	while browser.busy and Time.get_ticks_msec()<deadline:await process_frame;frames+=1
	check(not browser.busy and fixture.client.cache.loaded,"Background preparation and search finish")
	check(frames>2,"Search preparation yields to UI frames")
	check(fixture.local_calls==0,"Search does not rebuild every provider's cached catalog")
	browser.queue_free();await process_frame
	print("Search responsiveness tests complete; failures=",failures)
	quit(1 if failures else 0)
