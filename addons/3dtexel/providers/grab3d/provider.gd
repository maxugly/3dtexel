@tool
extends "res://addons/3dtexel/core/provider.gd"
## Grab3D provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/grab3d/client.gd")
const Cache = preload("res://addons/3dtexel/providers/grab3d/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "grab3d",
		"name": "Grab3D",
		"website": "https://grab3d.com/",
		"key_env": [],
		"capabilities": ["files", "variants", "model"]
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
	var id := str(raw.get("slug", raw.get("id", "")))
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "grab3d"
	asset.provider = "Grab3D"
	asset.id = id
	asset.type = "model"

	var display_name := ""
	var name_val: Variant = raw.get("name", asset.get("name", id))
	if name_val is Dictionary:
		display_name = str(name_val.get("en", id))
	else:
		display_name = str(name_val)
	if display_name.is_empty():
		display_name = id.capitalize()

	asset.title = display_name
	asset.url = str(raw.get("url", "https://grab3d.com/models/" + id))

	var thumb := ""
	var media_val: Variant = raw.get("media", asset.get("media", {}))
	if media_val is Dictionary:
		thumb = str(media_val.get("thumbnail", ""))
	if thumb.is_empty():
		thumb = str(raw.get("thumbnail", "https://grab3d.com/media/thumbs/%s.webp" % id))
	asset.thumbnail = thumb

	asset.description = str(raw.get("summary", asset.get("description", "%s - CC0 3D model" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	asset.authors = [{"name": "Grab3D Community", "url": "https://grab3d.com"}]

	var lic_val: Variant = raw.get("license", {
		"id": "cc0",
		"name": "CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	})
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Model '%s' from Grab3D (CC0)" % display_name
	asset.metadata_source_url = "https://grab3d.com/models/" + id
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

	var tris := 0
	var specs: Variant = asset.get("specs", {})
	if specs is Dictionary:
		tris = int(specs.get("triangleCount", 0))

	var result := []
	for f: Dictionary in files:
		var fmt := str(f.get("format", f.get("filename", "")).get_extension()).to_lower()
		if fmt.is_empty():
			fmt = str(f.get("format", "glb")).to_lower()
		var vid := Importer.slug(fmt)
		var label := fmt.to_upper()
		if tris > 0:
			label += " (%d tris)" % tris

		result.append({
			"id": vid,
			"label": label,
			"triangles": tris,
			"confirmed": true,
			"kind": "files"
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["material", "image", "audio"]:
		return {"items": [], "next_cursor": ""}

	var resp: Dictionary = await client.fetch_models()
	if resp.has("error"):
		return resp

	var all_models: Array = []
	if resp.has("items") and resp.items is Array:
		all_models = resp.items
	elif resp.get("data") is Array:
		all_models = resp.data

	var q := query.strip_edges().to_lower()
	var matched := []

	for raw in all_models:
		if not (raw is Dictionary):
			continue
		var raw_dict: Dictionary = raw
		if not q.is_empty():
			var slug := str(raw_dict.get("slug", "")).to_lower()
			var name := ""
			var name_val: Variant = raw_dict.get("name")
			if name_val is Dictionary:
				name = str(name_val.get("en", "")).to_lower()
			elif name_val is String:
				name = name_val.to_lower()
			var summary := str(raw_dict.get("summary", "")).to_lower()
			var tags: Array = raw_dict.get("tags", [])

			var is_match := slug.contains(q) or name.contains(q) or summary.contains(q)
			if not is_match:
				for t in tags:
					if str(t).to_lower().contains(q):
						is_match = true
						break
			if not is_match:
				continue
		matched.append(raw_dict)

	var offset := int(cursor) if not cursor.is_empty() else 0
	var page_size := 30
	var items: Array[Dictionary] = []

	var upper := mini(offset + page_size, matched.size())
	for i in range(offset, upper):
		var normalized := normalize(matched[i], true)
		client.cache.put_asset(normalized)
		items.append(normalized)

	var next_cur := str(offset + page_size) if (offset + page_size < matched.size()) else ""
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	var id := str(asset.get("id", ""))
	if id.is_empty():
		return {"error": "Missing asset ID."}

	var raw_detail: Dictionary = await client.fetch_model(id)
	if raw_detail.has("error"):
		return normalize(asset, false)

	var normalized := normalize(raw_detail, true)
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

	var target_slug := Importer.slug(variant)
	var matched_file: Dictionary = {}

	for f: Dictionary in files:
		var fmt := str(f.get("format", "")).to_lower()
		if Importer.slug(fmt) == target_slug:
			matched_file = f
			break

	if matched_file.is_empty() and not files.is_empty():
		matched_file = files[0]

	if matched_file.is_empty():
		return {"error": "No file available for variant %s." % variant}

	var dl_url := str(matched_file.get("url", ""))
	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var ext := dl_url.get_file().get_extension()
	if ext.is_empty():
		ext = str(matched_file.get("format", "glb"))
	var filename := "%s.%s" % [Importer.slug(str(detailed.id)), ext]

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
	return await client.fetch_models()

func cancel_all() -> void:
	client.cancel_all()
