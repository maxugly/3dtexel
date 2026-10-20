extends SceneTree
const Client = preload("res://addons/3dtexel/client.gd")
class OfflineClient:
	extends Client
	func transport_json(_path: String,_method:=HTTPClient.METHOD_GET,_body:={})->Dictionary:return {"error":"Preview is offline."}
	func get_bytes(_url: String,_destination:="",_max_bytes:=67108864,_redirects_left:=5)->Dictionary:return {"error":"Preview is offline."}
const Browser = preload("res://addons/3dtexel/browser.gd")
func _initialize():call_deferred("run")
func run():
	var args := OS.get_cmdline_user_args()
	root.size=Vector2i(int(args[0]),int(args[1])) if args.size()>=2 else Vector2i(1280,900)
	var destination := args[2] if args.size()>=3 else "res://docs/browser.png"
	var background := ColorRect.new();background.color=Color("25282e");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(background)
	var margin := MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:margin.add_theme_constant_override(side,16)
	root.add_child(margin)
	var browser := Browser.new();margin.add_child(browser)
	await process_frame
	browser.client.queue_free();browser.client=OfflineClient.new();browser.add_child(browser.client)
	browser.output.text="res://3DTexel/Materials"
	browser.inbox.text="res://assets/terrain/inbox"
	browser.search.text="grass"
	await browser.run_search()
	var asset: Dictionary = await browser.client.json_request("/assets/24509")
	if not asset.has("error"):
		var thumbnail: Texture2D = await browser.client.thumbnail(str(asset.get("thumbnail","")))
		await browser.select_asset(asset,thumbnail)
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(destination)
	print("Saved ",destination)
	quit()
