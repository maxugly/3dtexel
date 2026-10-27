@tool
extends "res://addons/3dtexel/core/provider_cache.gd"
## Retain existing metadata paths for compatibility.
const CATALOG_PATH = "user://3dtexel_cache_nasa_visible_earth.json"
const ASSETS_PATH = "user://3dtexel_assets_nasa_visible_earth.json"

func _init() -> void:
	root="user://asset_browser/previews/nasa_visible_earth"
	catalog_path=CATALOG_PATH;assets_path=ASSETS_PATH
