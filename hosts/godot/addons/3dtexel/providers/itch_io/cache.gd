@tool
extends RefCounted
## Disk cache and catalog persistence for itch.io provider. Sanitizes public metadata.

const Credits = preload("res://addons/3dtexel/credits.gd")
const PublicMetadata = preload("res://addons/3dtexel/core/public_metadata.gd")

var root := "user://itch_io_cache"
var catalog := {}
var loaded := false

func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if FileAccess.file_exists(root.path_join("catalog.json")):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("catalog.json")))
		if data is Dictionary:
			catalog = data

static func cacheable(path: String) -> bool:
	var clean := path.to_lower()
	if "password" in clean or "token" in clean or "session" in clean or "key" in clean:
		return false
	return clean.contains(".xml") or clean.contains("/api/") or clean.contains("itch.zone") or clean.contains("game-assets")

func thumbnail_path(url: String) -> String:
	ensure_loaded()
	return root.path_join("thumb_" + url.sha256_text() + ".png")

func response_path(path: String) -> String:
	ensure_loaded()
	return root.path_join("resp_" + path.sha256_text() + ".json")

func get_response(path: String) -> Dictionary:
	ensure_loaded()
	if not cacheable(path) or not FileAccess.file_exists(response_path(path)):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(response_path(path)))
	return data.get("data", {}) if data is Dictionary else {}

func response_validators(path: String) -> Dictionary:
	ensure_loaded()
	if not cacheable(path) or not FileAccess.file_exists(response_path(path)):
		return {}
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(response_path(path)))
	return record.get("validators", {}) if record is Dictionary else {}

func conditional_headers(path: String) -> PackedStringArray:
	var validators := response_validators(path)
	var headers := PackedStringArray()
	if validators.has("etag") and not str(validators.etag).is_empty():
		headers.append("If-None-Match: " + str(validators.etag))
	if validators.has("last_modified") and not str(validators.last_modified).is_empty():
		headers.append("If-Modified-Since: " + str(validators.last_modified))
	return headers

func put_response(path: String, data: Dictionary, validators := {}) -> void:
	ensure_loaded()
	if not cacheable(path) or data.has("error"):
		return
	var clean := {}
	for k in data:
		clean[k] = PublicMetadata.sanitize(data[k])
	var record := {
		"data": clean,
		"validators": validators,
		"cached_at": Time.get_datetime_string_from_system(true)
	}
	var file := FileAccess.open(response_path(path), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(record, "\t"))
		file.close()

func asset(id: String) -> Dictionary:
	ensure_loaded()
	return catalog.get(id, {}).duplicate(true)

func put_asset(asset: Dictionary, save := true) -> void:
	ensure_loaded()
	if asset.is_empty():
		return
	var id: String = str(asset.get("id", ""))
	if id.is_empty():
		return
	var clean := public_asset(asset)
	clean.provider_id = "itch_io"
	clean.provider = "itch.io"
	catalog[id] = clean
	if save:
		save_catalog()

func save_catalog() -> void:
	ensure_loaded()
	var file := FileAccess.open(root.path_join("catalog.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(catalog, "\t"))
		file.close()

func clear() -> void:
	ensure_loaded()
	catalog.clear()
	save_catalog()

static func public_asset(asset: Dictionary) -> Dictionary:
	var clean := PublicMetadata.sanitize(asset)
	var allowed := [
		"provider_id", "provider", "id", "title", "type", "url", "thumbnail",
		"description", "tags", "categories", "price", "authors", "license", "licenses",
		"selected_license", "attribution_text", "metadata_source_url", "source_metadata",
		"retrieved_utc", "variants", "files"
	]
	var out := {}
	for key in allowed:
		if clean.has(key):
			out[key] = clean[key]
	return out
