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
		"audio": asset.type = "audio"
		"3d": asset.type = "model"
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

func variants(asset: Dictionary) -> Array:
	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	if files.is_empty():
		return asset.get("variants", [])

	var result := []
	var supported := ["jpg", "jpeg", "png", "webp", "tif", "tiff", "mp3", "ogg", "wav", "flac", "glb", "gltf", "obj"]

	for f: Dictionary in files:
		var fname := str(f.get("name", ""))
		var ext := fname.get_extension().to_lower()
		if ext not in supported:
			continue

		var source_type := str(f.get("source", "original")).to_lower()
		var vid := Importer.slug(fname.get_basename())
		var label := fname
		if source_type == "original":
			label = "Original (" + ext.to_upper() + ")"
			vid = "original_" + ext
		elif source_type == "derivative":
			label = "Derivative (" + ext.to_upper() + ")"

		result.append({
			"id": vid,
			"label": label,
			"filename": fname,
			"format": ext,
			"confirmed": true,
			"kind": "files"
		})
	return result

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
			collection = ""
		"model":
			mediatype = "3d"
			collection = ""
		_:
			mediatype = ""
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
			client.cache.put_asset(normalized)
			items.append(normalized)

	var next_cur := str(page + 1) if (page * rows < total_found) else ""
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
	var matched_file: Dictionary = {}
	var target_slug := Importer.slug(variant)

	for f: Dictionary in files:
		var fname := str(f.get("name", ""))
		var ext := fname.get_extension().to_lower()
		var vid := Importer.slug(fname.get_basename())
		var source_type := str(f.get("source", "")).to_lower()
		if source_type == "original" and target_slug.begins_with("original"):
			matched_file = f
			break
		if vid == target_slug:
			matched_file = f
			break

	if matched_file.is_empty() and not files.is_empty():
		matched_file = files[0]

	if matched_file.is_empty():
		return {"error": "No downloadable file found for variant %s." % variant}

	var filename := str(matched_file.get("name", "archive_file.bin"))
	var dl_url := "https://archive.org/download/%s/%s" % [id, filename.uri_encode()]

	return {
		"kind": "files",
		"asset": detailed,
		"variant": variant,
		"files": [
			{
				"filename": filename,
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
	return await client.search("locomotive", "image", "flickrcommons", 1, 1)

func cancel_all() -> void:
	client.cancel_all()
