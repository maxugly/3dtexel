@tool
extends "res://addons/3dtexel/core/provider_cache.gd"
## Retain existing metadata paths for compatibility.
const CATALOG_PATH = "user://3dtexel_cache_yale_british_art.json"
const ASSETS_PATH = "user://3dtexel_assets_yale_british_art.json"

func _init() -> void:
	root="user://asset_browser/previews/yale_british_art"
	catalog_path=CATALOG_PATH;assets_path=ASSETS_PATH
