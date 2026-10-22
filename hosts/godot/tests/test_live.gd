extends SceneTree
## Explicit opt-in integration smoke: downloads ONLY a zero-credit CC0 material.
const Browser = preload("res://addons/3dtexel/browser.gd")
func _initialize():call_deferred("run")
func run():
	if OS.get_environment("TEXEL_ALLOW_LIVE_TESTS")!="1":push_error("Live network tests disabled. Explicit TEXEL_ALLOW_LIVE_TESTS=1 required.");quit(1);return
	var browser := Browser.new();root.add_child(browser)
	await process_frame
	if browser.client.providers.texel.api_key().is_empty():push_error("Environment key required.");quit(1);return
	browser.search.text="grass"
	await browser.refresh_search()
	if browser.grid.get_child_count()==0:push_error("Live search failed.");quit(1);return
	browser.client.network_allowed=true
	var asset: Dictionary = await browser.client.providers.texel.refresh_asset({"id":"24509"})
	if asset.has("error"):push_error("Live asset details failed.");quit(1);return
	browser.client.network_allowed=false
	browser.selected=asset
	browser.output.text="res://3DTexel/live_smoke"
	browser.handoff.button_pressed=true
	browser.inbox.text="res://3DTexel/inbox"
	if not browser.selection.options(asset,false).any(func(option):return option.id=="2k"):
		push_error("Asset does not report a 2K version; refusing a probe.");quit(1);return
	await browser.download_one(asset,"2k")
	print(browser.status.text)
	if not browser.status.text.begins_with("1 / 1 downloads complete"):quit(1);return
	browser.queue_free();await process_frame
	quit()
