@tool
extends EditorPlugin
const Browser = preload("res://addons/3dtexel/browser.gd")
var browser: Control
func _enter_tree() -> void:
	browser = Browser.new()
	browser.editor_plugin = self
	EditorInterface.get_editor_main_screen().add_child(browser)
	browser.hide()
func _exit_tree() -> void:
	if is_instance_valid(browser): browser.queue_free()
func _has_main_screen() -> bool: return true
func _get_plugin_name() -> String: return "3D Texel"
func _get_plugin_icon() -> Texture2D: return EditorInterface.get_base_control().get_theme_icon("Material","EditorIcons")
func _make_visible(value: bool) -> void:
	if is_instance_valid(browser): browser.visible = value
