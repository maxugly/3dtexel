extends Control
## Manual UI probe: hosts the real browser panel in a real window, runs a real
## search against the real providers, screenshots the result and prints UI state.
## Usage: godot --path hosts/godot res://tools/ui_probe.tscn

const Browser = preload("res://addons/3dtexel/browser.gd")
## Screenshots land in TEXEL_UI_OUT (default: the user data folder) so the tool
## stays usable on any machine.
var out_dir := ""

var browser: Control
var shots := 0

func _ready() -> void:
	out_dir = OS.get_environment("TEXEL_UI_OUT")
	if out_dir.is_empty():out_dir = OS.get_user_data_dir().path_join("ui_probe")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser = Browser.new()
	add_child(browser)
	await get_tree().process_frame
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var query := OS.get_environment("TEXEL_UI_QUERY")
	if query.is_empty():query = "wood"
	var only := OS.get_environment("TEXEL_UI_ONLY")
	print("[ui-probe] query=", query, " only=", only)
	browser.search.text = query
	if not only.is_empty():
		for id in browser.client.providers:browser.client.providers[id].enabled = false
		for id in only.split(",", false):browser.client.providers[id].enabled = true
	await get_tree().process_frame
	browser.start_search()
	_watch()

func _watch() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if browser.busy and browser.searching and shots < 1 and Time.get_ticks_msec() % 3 == 0:
			await _shot("searching")
		if not browser.busy and browser.searching == false and shots >= 1:
			break
	await _shot("final")
	_report()
	get_tree().quit(0)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/ui_%s_%s.png" % [out_dir, tag, Time.get_ticks_msec()]
	image.save_png(path)
	shots += 1
	print("[ui-probe] screenshot ", path)

func _report() -> void:
	print("[ui-probe] status: ", browser.status.text)
	print("[ui-probe] page:   ", browser.page_label.text)
	print("[ui-probe] cards:  ", browser.grid.get_child_count(), " visible_assets=", browser.visible_assets.size())
	print("[ui-probe] search field enabled: ", browser.search.editable, " search button disabled: ", browser.search_button.disabled)
	var titles := []
	for asset: Dictionary in browser.visible_assets.slice(0, 12):titles.append("%s/%s" % [asset.get("provider_id", "?"), asset.get("title", "?")])
	print("[ui-probe] titles: ", titles)
	print("[ui-probe] filters: licenses=", browser.license_filter.item_count, " versions=", browser.version_filter.item_count)
