@tool
extends "res://addons/3dtexel/core/provider_cache.gd"
## Retain existing metadata paths for compatibility.
const CATALOG_PATH = "user://3dtexel_cache_freesound.json"
const ASSETS_PATH = "user://3dtexel_assets_freesound.json"

func _init() -> void:
	root="user://asset_browser/previews/freesound"
	catalog_path=CATALOG_PATH;assets_path=ASSETS_PATH
