extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
var failures := 0
func check(value: bool, message: String):
	if not value: failures+=1;push_error(message)
func _initialize():call_deferred("run")
func settle():
	for i in 8:await process_frame
func run():
	# Godot editor main screen is container-managed, unlike the original MarginContainer preview.
	var editor_host := VBoxContainer.new();editor_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(editor_host)
	var browser := Browser.new();editor_host.add_child(browser)
	await settle()
	for i in 12:
		browser.grid.add_child(browser.make_asset_tile({"id":i,"title":"A long ground material title for layout testing","price":{"free":true,"credits":0}},0))
	for viewport_size in [Vector2i(1600,900),Vector2i(850,1000),Vector2i(640,960)]:
		root.size=viewport_size
		await settle()
		check(browser.size.y>=editor_host.size.y-2,"Browser must fill editor host vertically: %s" % viewport_size)
		check(browser.size.x<=viewport_size.x+2,"No horizontal overflow: %s" % viewport_size)
		check(browser.results_scroll.size.y>viewport_size.y*.45,"Results consume available height: %s" % viewport_size)
		check(browser.grid.size.x<=browser.results_scroll.size.x+2,"Grid fits its scroll pane: %s" % viewport_size)
		print("Layout ",viewport_size,": browser=",browser.size," results=",browser.results_scroll.size," columns=",browser.grid.columns)
	browser.queue_free()
	print("Layout tests complete; failures=",failures)
	quit(1 if failures else 0)
