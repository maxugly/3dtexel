extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Registry = preload("res://addons/3dtexel/core/registry.gd")
class FakeClient:
	extends "res://addons/3dtexel/core/registry.gd"
	var started := 0
	var active := 0
	var peak := 0
	func thumbnail(_url: String,_asset: Dictionary) -> Texture2D:
		started+=1;active+=1;peak=maxi(peak,active)
		await get_tree().create_timer(.02).timeout
		active-=1
		return null
## Mirrors the provider client gate: a thumbnail is only fetched when the exact
## URL was allow-listed, so grid tiles stay blank without an explicit grant.
class GatedClient:
	extends Node
	var allowed_thumbnails := {}
	var network_allowed := false
	func thumbnail(url: String) -> Texture2D:
		if not network_allowed and not allowed_thumbnails.has(url):return null
		return GradientTexture1D.new()
class FakeProvider:
	extends Node
	var enabled := true
	var network_allowed := false
	var client: GatedClient
	func descriptor() -> Dictionary:return {"id":"fake_registry"}
	func thumbnail(url: String) -> Texture2D:return client.thumbnail(url)
	func cancel_all() -> void:pass
var failures := 0
func check(value: bool, message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1200,900)
	var browser := Browser.new();root.add_child(browser);await process_frame
	browser.set_process(false)
	browser.client.queue_free()
	var fake := FakeClient.new();browser.add_child(fake);browser.client=fake;browser.selection.registry=fake;browser.session.registry=fake
	for i in 100:
		browser.grid.add_child(browser.make_asset_tile({"id":i,"title":"Test","thumbnail":"https://example.invalid/thumbnail","price":{"free":true,"credits":0}},browser.serial))
	for i in 8:await process_frame
	browser.pump_thumbnails()
	check(fake.started==4 and fake.peak==4,"At most four thumbnail requests start together")
	for i in 8:
		await create_timer(.03).timeout
		browser.pump_thumbnails()
	check(fake.peak==4,"Concurrency remains bounded")
	check(fake.started<100 and not browser.thumbnail_queue.is_empty(),"Offscreen thumbnails are deferred")
	var first_count := fake.started
	browser.results_scroll.scroll_vertical=browser.results_scroll.get_v_scroll_bar().max_value
	for i in 4:await process_frame
	browser.pump_thumbnails()
	check(fake.started>first_count,"Scrolling loads newly visible thumbnails")
	await create_timer(.03).timeout
	browser.serial+=1;browser.pump_thumbnails()
	check(browser.thumbnail_queue.is_empty(),"Stale generation jobs discarded")
	await test_thumbnail_allow_list()
	browser.queue_free();await process_frame
	print("Thumbnail queue tests complete; failures=",failures)
	quit(1 if failures else 0)
## The registry must grant the provider client permission for the exact
## thumbnail URL it was asked to render, otherwise finished searches show a
## grid of blank tiles because the global network flag is already off.
func test_thumbnail_allow_list() -> void:
	var registry := Registry.new();root.add_child(registry);await process_frame
	var provider := FakeProvider.new()
	provider.client = GatedClient.new()
	registry.register_provider(provider)
	var url := "https://example.invalid/thumbnail.png"
	var texture: Texture2D = await registry.thumbnail(url,{"provider_id":"fake_registry"})
	check(texture!=null,"Registry allow-lists the thumbnail URL so grid tiles render")
	check(provider.client.allowed_thumbnails.has(url),"Requested thumbnail URL is recorded in the provider allow list")
	var other := "https://example.invalid/other.png"
	var blocked: Texture2D = await provider.thumbnail(other)
	check(blocked==null,"Unrequested URLs stay blocked")
	provider.client.queue_free()
	registry.queue_free();await process_frame
