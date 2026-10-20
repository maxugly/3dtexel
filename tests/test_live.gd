extends SceneTree
## Explicit opt-in integration smoke: downloads ONLY a zero-credit CC0 material.
const Browser = preload("res://addons/3dtexel/browser.gd")
func _initialize():call_deferred("run")
func run():
	var browser := Browser.new();root.add_child(browser)
	await process_frame
	if browser.client.api_key().is_empty():push_error("Environment key required.");quit(1);return
	browser.search.text="grass"
	await browser.run_search()
	if browser.grid.get_child_count()==0:push_error("Live search failed.");quit(1);return
	var asset: Dictionary = await browser.client.json_request("/assets/24509")
	if asset.has("error"):push_error("Live asset details failed.");quit(1);return
	browser.selected=asset
	browser.output.text="res://3DTexel/live_smoke"
	browser.handoff.button_pressed=true
	browser.inbox.text="res://3DTexel/inbox"
	browser.resolution.select(1)
	await browser.download_selected()
	print(browser.status.text)
	if not browser.status.text.begins_with("Ready:"):quit(1);return
	browser.queue_free();await process_frame
	quit()
