extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
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
	browser.queue_free();await process_frame
	print("Thumbnail queue tests complete; failures=",failures)
	quit(1 if failures else 0)
