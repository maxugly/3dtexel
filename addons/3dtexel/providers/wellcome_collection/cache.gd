@tool
extends RefCounted
## Disk and session cache for Wellcome Collection provider.

const CATALOG_PATH = "user://3dtexel_cache_wellcome_collection.json"
const ASSETS_PATH = "user://3dtexel_assets_wellcome_collection.json"

var catalog: Dictionary = {}
var assets: Dictionary = {}
var loaded := false

static func public_asset(raw: Dictionary) -> Dictionary:
	var c := raw.duplicate(true)
	strip_sensitive(c)
	return c

static func strip_sensitive(dict: Dictionary) -> void:
	for key in ["api_key", "token", "secret", "authorization"]:
		dict.erase(key)

func ensure_loaded() -> void:
	if loaded:
		return
	catalog = _read_json(CATALOG_PATH)
	assets = _read_json(ASSETS_PATH)
	loaded = true

func save() -> void:
	_write_json(CATALOG_PATH, catalog)
	_write_json(ASSETS_PATH, assets)

func asset(id: String) -> Dictionary:
	ensure_loaded()
	if assets.has(id) and assets[id] is Dictionary:
		return assets[id].duplicate(true)
	return {}

func set_asset(id: String, data: Dictionary) -> void:
	ensure_loaded()
	assets[id] = data.duplicate(true)

func clear() -> void:
	catalog.clear()
	assets.clear()
	loaded = false

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text := file.get_as_text()
	var test_json_conv := JSON.new()
	if test_json_conv.parse(text) == OK and test_json_conv.data is Dictionary:
		return test_json_conv.data
	return {}

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
