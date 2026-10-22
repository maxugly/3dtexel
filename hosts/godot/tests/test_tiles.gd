extends SceneTree
class TestBrowser:
	extends "res://addons/3dtexel/browser.gd"
	var clicked: Array[int] = []
	func select_asset(asset: Dictionary, _texture: Texture2D) -> void:
		clicked.append(int(asset.id))
var failures := 0
func check(value: bool, message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1200,900)
	var browser := TestBrowser.new();root.add_child(browser)
	await process_frame
	var tile := browser.make_asset_tile({"id":42,"title":"Test material","price":{"free":true,"credits":0}},0)
	browser.grid.add_child(tile)
	for i in 6:await process_frame
	var main := tile.get_node("Contents/Inspect")
	var contents := main.get_child(0).get_child(0)
	for region in [contents.get_node("Thumbnail"),contents.get_node("Title"),contents.get_node("License")]:
		var point: Vector2 = region.get_global_rect().get_center()
		for down in [true,false]:
			var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point
			root.push_input(event)
			await process_frame
	check(browser.clicked==[42,42,42],"Thumbnail, title and license clicks all select exactly once")
	check(tile.get_node("Contents/Header/Select") is CheckBox,"Card selection is separate from inspecting its image")
	print("Tile hit tests complete; failures=",failures)
	quit(1 if failures else 0)
