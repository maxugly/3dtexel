@tool
extends "res://addons/3dtexel/core/provider_cache.gd"
## Blend Swap response and metadata cache.

const CATALOG_PATH = "user://3dtexel_cache_blendswap.json"
const ASSETS_PATH = "user://3dtexel_assets_blendswap.json"

func _init() -> void:
	root = "user://asset_browser/previews/blendswap"
	catalog_path = CATALOG_PATH
	assets_path = ASSETS_PATH

func put_asset(asset_dict: Dictionary, do_save := true) -> void:
	ensure_loaded()
	var clean_id := str(asset_dict.get("id", ""))
	if clean_id.is_empty():
		return
	catalog[clean_id] = public_asset(asset_dict)
	if do_save:
		save()

func save_catalog() -> void:
	save()
