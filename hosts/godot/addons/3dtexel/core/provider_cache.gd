@tool
extends RefCounted
## Public metadata and preview cache for adapters retaining legacy JSON paths.
const PublicMetadata = preload("res://addons/3dtexel/core/public_metadata.gd")
var root := ""
var catalog_path := ""
var assets_path := ""
var catalog: Dictionary={}
var assets: Dictionary={}
var loaded := false
static func public_asset(raw: Dictionary) -> Dictionary:
	return PublicMetadata.sanitize(raw)
static func strip_sensitive(record: Dictionary) -> void:
	var clean := public_asset(record);record.clear();record.merge(clean)
func ensure_loaded() -> void:
	if loaded:return
	loaded=true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	catalog=_read_json(catalog_path);assets=_read_json(assets_path)
func save() -> void:
	_write_json(catalog_path,catalog);_write_json(assets_path,assets)
func asset(id: String) -> Dictionary:
	ensure_loaded()
	var value: Variant=assets.get(id,catalog.get(id,{}))
	return value.duplicate(true) if value is Dictionary else {}
func set_asset(id: String,data: Dictionary) -> void:
	ensure_loaded();assets[id]=public_asset(data)
static func merge_asset(cached: Dictionary,current: Dictionary) -> Dictionary:
	var result := cached.duplicate(true)
	var source: Dictionary=cached.get("source_metadata",{}).duplicate(true)
	source.merge(current.get("source_metadata",{}),true)
	result.merge(current,true)
	if not source.is_empty():result.source_metadata=source
	return result
func thumbnail_path(url: String) -> String:
	ensure_loaded()
	return root.path_join("thumb_"+url.sha256_text()+".png")
func cache_paths() -> Array[String]:return [root,catalog_path,assets_path]
func clear() -> void:
	catalog.clear();assets.clear();loaded=false
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return public_asset(value) if value is Dictionary else {}
func _write_json(path: String,data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(public_asset(data)))
