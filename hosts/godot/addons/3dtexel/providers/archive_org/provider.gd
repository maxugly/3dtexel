@tool
extends "res://addons/3dtexel/core/provider.gd"
## Internet Archive provider adapter with Flickr Commons support.

const Client = preload("res://addons/3dtexel/providers/archive_org/client.gd")
const Cache = preload("res://addons/3dtexel/providers/archive_org/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "archive_org",
		"name": "Internet Archive",
		"website": "https://archive.org/details/flickrcommons",
		"key_env": [],
		"capabilities": ["files", "variants", "image", "audio", "model"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing

func api_key() -> String:
	return ""

func set_session_key(_value: String) -> void:
	pass

func credential_status() -> String:
	return "No key required."

func can_download(asset: Dictionary) -> bool:
	if not Importer.free_asset(asset):
		return false
	var vars := variants(asset)
	return not vars.is_empty()

func local_assets() -> Array:
	client.cache.ensure_loaded()
	var result := []
	for raw in client.cache.catalog.values():
		if raw is Dictionary:
			result.append(normalize(raw, false))
	return result

func normalize(raw: Dictionary, fetched := false) -> Dictionary:
	var id := str(raw.get("identifier", raw.get("id", "")))
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "archive_org"
	asset.provider = "Internet Archive"
	asset.id = id

	var mediatype := str(raw.get("mediatype", asset.get("mediatype", "image"))).to_lower()
	match mediatype:
		"image": asset.type = "image"
		"audio", "etree": asset.type = "audio"
		"3d", "data": asset.type = "model"
		_: asset.type = "image"

	var display_name := str(raw.get("title", asset.get("title", id)))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://archive.org/details/" + id))
	asset.thumbnail = str(raw.get("thumbnail", "https://archive.org/services/img/" + id))
	asset.description = str(raw.get("description", asset.get("description", "")))
	asset.price = {"free": true, "credits": 0}

	var creator := str(raw.get("creator", asset.get("creator", "Unknown Creator")))
	if creator.is_empty():
		creator = "Internet Archive Contributor"
	asset.authors = [{"name": creator, "url": "https://archive.org/details/" + id}]

	var lic_url := str(raw.get("licenseurl", "https://creativecommons.org/publicdomain/mark/1.0/"))
	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain (No Known Copyright Restrictions)",
		"url": lic_url,
		"attribution_required": true
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Photograph/media from %s via Flickr Commons / Internet Archive" % creator
	asset.metadata_source_url = "https://archive.org/metadata/" + id
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

const IMAGE_EXTS := ["jpg", "jpeg", "png", "webp", "tif", "tiff", "zip", "7z"]
const AUDIO_EXTS := ["mp3", "ogg", "wav", "flac", "m4a", "zip", "7z"]
const MODEL_EXTS := ["glb", "gltf", "obj", "stl", "fbx", "blend", "dae", "ply", "3ds", "zip", "7z"]

static func _allowed_exts_for_type(asset_type: String) -> Array:
	match asset_type:
		"model": return MODEL_EXTS
		"audio": return AUDIO_EXTS
		_: return IMAGE_EXTS

static func _is_valid_type_file(fname: String, asset_type: String) -> bool:
	var lower := fname.to_lower()
	if lower == "__ia_thumb.jpg" or lower.ends_with("_thumb.jpg") or lower.ends_with("_thumb.png"):
		return false
	var ext := lower.get_extension()
	return ext in _allowed_exts_for_type(asset_type)

func variants(asset: Dictionary) -> Array:
	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	var asset_type := str(asset.get("type", "image"))
	var result := []

	for f in files:
		if not (f is Dictionary):
			continue
		var fname := str(f.get("name", ""))
		if not _is_valid_type_file(fname, asset_type):
			continue
		var ext := fname.get_extension().to_lower()
		var source_type := str(f.get("source", "original")).to_lower()
		var vid := Importer.slug(fname.get_file().get_basename())
		var label := fname.get_file()
		if source_type == "original":
			label = "Original (" + ext.to_upper() + ")"
			vid = "original_" + ext
		elif source_type == "derivative":
			label = "Derivative (" + ext.to_upper() + ")"

		result.append({
			"id": vid,
			"label": label,
			"filename": fname.get_file(),
			"format": ext,
			"confirmed": true,
			"kind": "files"
		})

	if not result.is_empty():
		return result

	var existing: Array = asset.get("variants", [])
	if not existing.is_empty():
		return existing

	match asset_type:
		"model":
			return [{"id": "original_zip", "label": "Model Pack (ZIP/STL)", "confirmed": true, "kind": "files"}]
		"audio":
			return [{"id": "original_mp3", "label": "Audio (MP3/WAV)", "confirmed": true, "kind": "files"}]
		_:
			return [{"id": "original_jpg", "label": "Original (JPG)", "confirmed": true, "kind": "files"}]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category == "material":
		return {"items": [], "next_cursor": ""}

	var mediatype := ""
	var collection := "flickrcommons"

	match category:
		"image":
			mediatype = "image"
			collection = "flickrcommons"
		"audio":
			mediatype = "audio"
			collection = "opensource_audio"
		"model":
			mediatype = "data"
			collection = "thingiverse"
		_:
			mediatype = "image"
			collection = "flickrcommons"

	var page := int(cursor) if not cursor.is_empty() else 1
	if page < 1:
		page = 1
	var rows := 30

	var resp: Dictionary = await client.search(query, mediatype, collection, page, rows)
	if resp.has("error"):
		return resp

	var response_obj: Dictionary = resp.get("response", {})
	var docs: Array = response_obj.get("docs", [])
	var total_found := int(response_obj.get("numFound", 0))

	var items: Array[Dictionary] = []
	for raw in docs:
		if raw is Dictionary:
			var normalized := normalize(raw, true)
			client.cache.put_asset(normalized, false)
			items.append(normalized)

	var next_cur := str(page + 1) if (page * rows < total_found) else ""
	client.cache.save_catalog()
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	var id := str(asset.get("id", ""))
	if id.is_empty():
		return {"error": "Missing asset ID."}

	var meta: Dictionary = await client.fetch_metadata(id)
	if meta.has("error"):
		return normalize(asset, false)

	var merged: Dictionary = asset.duplicate(true)
	merged["files"] = meta.get("files", [])
	merged["server"] = meta.get("server", "")
	merged["dir"] = meta.get("dir", "")
	if meta.get("metadata") is Dictionary:
		merged.merge(meta.metadata, true)

	var normalized := normalize(merged, true)
	client.cache.put_asset(normalized)
	return normalized

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var id := str(detailed.id)
	var asset_type := str(detailed.get("type", "image"))
	var valid_files: Array[Dictionary] = []
	for f in files:
		if f is Dictionary and _is_valid_type_file(str(f.get("name", "")), asset_type):
			valid_files.append(f)

	var matched_file: Dictionary = {}
	var target_slug := Importer.slug(variant)

	# 1. Exact match by slug or original_<ext>
	for f: Dictionary in valid_files:
		var fname := str(f.get("name", ""))
		var ext := fname.get_extension().to_lower()
		var vid := Importer.slug(fname.get_file().get_basename())
		if vid == target_slug or ("original_" + ext) == target_slug:
			matched_file = f
			break

	# 2. Priority for audio when original_mp3 is requested
	if matched_file.is_empty() and asset_type == "audio":
		for f: Dictionary in valid_files:
			var ext := str(f.get("name", "")).get_extension().to_lower()
			if ext in ["mp3", "ogg", "wav", "flac"]:
				matched_file = f
				break

	# 3. Match original source type
	if matched_file.is_empty():
		for f: Dictionary in valid_files:
			var source_type := str(f.get("source", "")).to_lower()
			if source_type == "original":
				matched_file = f
				break

	if matched_file.is_empty() and not valid_files.is_empty():
		matched_file = valid_files[0]

	if matched_file.is_empty():
		return {"error": "No downloadable %s file found for variant %s." % [asset_type, variant]}

	var raw_name := str(matched_file.get("name", "archive_file.bin"))
	var safe_filename := raw_name.get_file()
	var path_parts := raw_name.split("/", false)
	var encoded_parts: Array[String] = []
	for p in path_parts:
		encoded_parts.append(p.uri_encode())
	var dl_url := "https://archive.org/download/%s/%s" % [id, "/".join(encoded_parts)]

	return {
		"kind": "files",
		"asset": detailed,
		"variant": variant,
		"files": [
			{
				"filename": safe_filename,
				"url": dl_url
			}
		]
	}

func thumbnail(url: String) -> Texture2D:
	sync_network()
	return await client.thumbnail(url)

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	return await client.get_bytes(url, destination, limit)

func check_connection() -> Dictionary:
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.search("locomotive", "image", "flickrcommons", 1, 1)

func cancel_all() -> void:
	client.cancel_all()
