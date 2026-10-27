@tool
extends RefCounted
## Disk cache and catalog persistence for NASA Images provider. Sanitizes public metadata.

const Credits = preload("res://addons/3dtexel/credits.gd")
const PublicMetadata = preload("res://addons/3dtexel/core/public_metadata.gd")

var root := "user://nasa_cache"
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
	return clean.contains("/search") or clean.contains("/asset/") or clean.contains("/metadata/") or clean.contains("/git/trees/")

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
		clean[k] = sanitize(data[k])
	var prior := response_validators(path)
	prior.merge(validators, true)
	Credits.write_json(response_path(path), {
		"fetched_utc": Time.get_datetime_string_from_system(true),
		"data": clean,
		"validators": prior
	})
	Credits.write_json(root.path_join("catalog.json"), catalog)

static func public_asset(asset: Dictionary) -> Dictionary:
	var clean := {}
	for key in [
		"id", "provider", "provider_id", "title", "name", "type", "url",
		"thumbnail", "description", "license", "licenses", "selected_license",
		"price", "tags", "authors", "author", "attribution", "attribution_text",
		"metadata_source_url", "variants", "files", "preview_images"
	]:
		if asset.has(key):
			clean[key] = sanitize(asset[key])
	if asset.has("source_metadata") and asset.source_metadata is Dictionary:
		clean.source_metadata = sanitize(asset.source_metadata)
	return clean

static func sanitize(value: Variant) -> Variant:
	return PublicMetadata.sanitize(value)

func upsert(asset: Dictionary) -> void:
	ensure_loaded()
	var id := str(asset.get("id", ""))
	if id.is_empty():
		return
	var previous: Dictionary = catalog.get(id, {})
	var incoming := public_asset(asset)
	previous.merge(incoming, true)
	catalog[id] = previous

func save_catalog() -> void:
	ensure_loaded()
	Credits.write_json(root.path_join("catalog.json"), catalog)

func asset(id: String) -> Dictionary:
	ensure_loaded()
	return catalog.get(id, {}).duplicate(true)

func search(query: String, type: String, free_only: bool, license: String) -> Array:
	ensure_loaded()
	var result := []
	var words := query.to_lower().split(" ", false)
	for value: Dictionary in catalog.values():
		if type != "all" and value.get("type", "") != type:
			continue
		var price: Dictionary = value.get("price", {})
		if free_only and not (price.get("free", false) and int(price.get("credits", 0)) == 0):
			continue
		if license != "Any license":
			var lic_name := str(Credits.license_record(value.get("license", "")).name)
			if lic_name != license:
				continue
		var haystack := (str(value.get("title", "")) + " " + str(value.get("description", "")) + " " + JSON.stringify(value.get("tags", []))).to_lower()
		var matches := true
		for word in words:
			if word not in haystack:
				matches = false
				break
		if matches:
			result.append(value.duplicate(true))
	result.sort_custom(func(a, b):
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
	)
	return result

func licenses() -> Array[String]:
	ensure_loaded()
	var result: Array[String] = []
	for value: Dictionary in catalog.values():
		var name := str(Credits.license_record(value.get("license", "")).name)
		if not name.is_empty() and name not in result:
			result.append(name)
	result.sort()
	return result

func thumbnail_path(url: String) -> String:
	ensure_loaded()
	return root.path_join("thumb_" + url.sha256_text() + ".png")
