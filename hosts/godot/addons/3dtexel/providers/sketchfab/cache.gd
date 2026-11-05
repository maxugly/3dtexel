@tool
extends RefCounted
## Sketchfab cache management.

const CATALOG_PATH = "user://3dtexel_cache_sketchfab.json"
const ASSETS_PATH = "user://3dtexel_assets_sketchfab.json"

var root := "user://asset_browser/previews/sketchfab"
var catalog := {}
var assets := {}
var loaded := false

func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	if FileAccess.file_exists(CATALOG_PATH):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if raw is Dictionary:
			catalog = raw
	if FileAccess.file_exists(ASSETS_PATH):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(ASSETS_PATH))
		if raw is Dictionary:
			assets = raw

func save() -> void:
	var f1 := FileAccess.open(CATALOG_PATH, FileAccess.WRITE)
	if f1:
		f1.store_string(JSON.stringify(catalog, "\t"))
		f1.close()
	var f2 := FileAccess.open(ASSETS_PATH, FileAccess.WRITE)
	if f2:
		f2.store_string(JSON.stringify(assets, "\t"))
		f2.close()

func asset(id: String) -> Dictionary:
	ensure_loaded()
	if not assets.has(id):
		assets[id] = {}
	return assets[id]
