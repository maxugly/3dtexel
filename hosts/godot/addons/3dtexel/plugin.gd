@tool
extends EditorPlugin
const Credits = preload("res://addons/3dtexel/credits.gd")
const Browser = preload("res://addons/3dtexel/browser.gd")
var browser: Control
var _credits_paths := {}
var _credits_queued := false
func _enter_tree() -> void:
	browser = Browser.new()
	browser.editor_plugin = self
	EditorInterface.get_editor_main_screen().add_child(browser)
	browser.hide()
	scene_saved.connect(_scene_saved)
func _exit_tree() -> void:
	if is_instance_valid(browser): browser.queue_free()
func _has_main_screen() -> bool: return true
func _get_plugin_name() -> String: return "Asset Library"
func _get_plugin_icon() -> Texture2D: return EditorInterface.get_base_control().get_theme_icon("Material","EditorIcons")
func _make_visible(value: bool) -> void:
	if is_instance_valid(browser): browser.visible = value

func _scene_saved(path: String) -> void:
	if not ProjectSettings.get_setting("asset_browser/automatic_scene_credits",ProjectSettings.get_setting("3dtexel/automatic_scene_credits",true)):return
	_credits_paths[path]=true
	if _credits_queued:return
	_credits_queued=true
	_flush_scene_credits.call_deferred()
func _flush_scene_credits() -> void:
	_credits_queued=false
	if _credits_paths.is_empty():return
	var paths := _credits_paths.keys()
	_credits_paths.clear()
	if not is_inside_tree():return
	for path in paths:Credits.write_scene(str(path))
