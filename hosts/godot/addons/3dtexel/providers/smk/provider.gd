@tool
extends "res://addons/3dtexel/core/provider.gd"
## SMK Open (National Gallery of Denmark) provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/smk/client.gd")
const Cache = preload("res://addons/3dtexel/providers/smk/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "smk",
		"name": "SMK Open",
		"website": "https://open.smk.dk/art/",
		"key_env": [],
		"capabilities": ["image", "material", "model", "files", "variants"]
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
	var id := str(raw.get("id", ""))
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "smk"
	asset.provider = "SMK Open"
	asset.id = clean_id
	asset.type = "image"

	var display_name := clean_id.capitalize()
	var titles: Array = raw.get("titles", [])
	if not titles.is_empty() and titles[0] is Dictionary:
		display_name = str(titles[0].get("title", display_name))
	asset.title = display_name

	asset.url = str(raw.get("frontend_url", "https://open.smk.dk/art/?id=" + id))
	asset.thumbnail = str(raw.get("image_thumbnail", ""))
	asset.description = str(raw.get("description", "%s at Statens Museum for Kunst" % display_name))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var creator := "Statens Museum for Kunst"
	var prod: Array = raw.get("production", [])
	if not prod.is_empty() and prod[0] is Dictionary:
		creator = str(prod[0].get("creator", creator))
	asset.authors = [{"name": creator, "url": "https://www.smk.dk"}]

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s - Statens Museum for Kunst (CC0)" % [display_name, creator]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	var result := []
	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		var fname := str(f_dict.get("filename", ""))
		var res := str(f_dict.get("resolution", fname.get_basename()))
		var vid := Importer.slug(res)
		result.append({
			"id": vid,
			"label": "%s Resolution" % vid.to_upper(),
			"kind": "files",
			"confirmed": true,
			"resolution": vid
		})

	if not result.is_empty():
		return result

	var existing: Array = asset.get("variants", [])
	if not existing.is_empty():
		return existing

	if str(asset.get("type", "")) == "model":
		var f3d: Array = asset.get("files", [])
		if f3d.is_empty() and asset.get("source_metadata") is Dictionary:
			f3d = asset.source_metadata.get("files", [])
		if not f3d.is_empty():
			var v := []
			for f in f3d:
				if f is Dictionary:
					var res_id := str(f.get("resolution", "stl"))
					var label := "STL (Optimized)" if res_id.contains("small") else "STL (Full)"
					v.append({
						"id": res_id,
						"label": label,
						"kind": "files",
						"confirmed": true
					})
			return v
		return [
			{
				"id": "stl_small",
				"label": "STL (Optimized)",
				"kind": "files",
				"confirmed": true
			},
			{
				"id": "stl",
				"label": "STL (Full)",
				"kind": "files",
				"confirmed": true
			}
		]

	return [
		{
			"id": "2k",
			"label": "2K Resolution",
			"kind": "files",
			"confirmed": true,
			"resolution": "2k"
		},
		{
			"id": "1k",
			"label": "1K Resolution",
			"kind": "files",
			"confirmed": true,
			"resolution": "1k"
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category == "audio":
		return {"items": [], "next_cursor": ""}

	var offset := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
	var rows := 30
	var resp: Dictionary = {}
	if category == "model":
		if client.get_script() != Client:
			return {"items": [], "next_cursor": ""}
		resp = await client.search_3d(query, offset, rows)
	else:
		resp = await client.search(query, offset, rows)

	if resp.has("error"):
		return resp

	var all_items: Array = []
	if resp.has("items") and resp.items is Array:
		all_items = resp.items

	var items: Array[Dictionary] = []
	for raw in all_items:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if category == "model":
			normalized.type = "model"
			var f3d: Array = raw.get("files_3D", [])
			var model_files: Array = []
			for f in f3d:
				if f is Dictionary:
					var stl_url := str(f.get("url", ""))
					var fsz := int(f.get("file_size", 0))
					var is_small := stl_url.to_lower().contains("small")
					var res_id := "stl_small" if is_small else "stl"
					model_files.append({
						"filename": "%s_%s.stl" % [normalized.id, res_id],
						"url": stl_url,
						"resolution": res_id,
						"size": fsz
					})
			if not model_files.is_empty():
				model_files.sort_custom(func(a, b): return int(a.get("size", 0)) < int(b.get("size", 0)))
				normalized["files"] = model_files
				normalized.source_metadata["files"] = model_files
				normalized.variants = variants(normalized)
		elif category == "material":
			normalized.type = "material"
		if normalized.thumbnail.is_empty():
			var thumb_candidate := str(raw.get("image_thumbnail", ""))
			if thumb_candidate.is_empty() and not str(raw.get("image_iiif_id", "")).is_empty():
				thumb_candidate = str(raw.image_iiif_id) + "/full/!512,/0/default.jpg"
			normalized.thumbnail = thumb_candidate
		if not normalized.thumbnail.is_empty():
			client.allowed_thumbnails[normalized.thumbnail] = true
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_cur := str(offset + rows) if all_items.size() >= rows else ""
	client.cache.save_catalog()
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	return normalize(asset, false)

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var target_slug := Importer.slug(variant)
	var chosen_file: Dictionary = {}

	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		if Importer.slug(str(f_dict.get("resolution", ""))) == target_slug or Importer.slug(str(f_dict.get("filename", "")).get_basename()) == target_slug:
			chosen_file = f_dict
			break

	if chosen_file.is_empty() and not files.is_empty() and files[0] is Dictionary:
		chosen_file = files[0]

	var dl_url := str(chosen_file.get("url", ""))
	var filename := str(chosen_file.get("filename", "%s.jpg" % Importer.slug(str(detailed.id))))

	if dl_url.is_empty():
		var iiif := str(detailed.get("image_iiif_id", detailed.get("source_metadata", {}).get("image_iiif_id", "")))
		if iiif.is_empty() and str(detailed.get("thumbnail", "")).contains("/full/"):
			iiif = str(detailed.thumbnail).split("/full/")[0]
		if not iiif.is_empty():
			var sz := "!1024,1024" if variant == "1k" else "!2048,2048"
			dl_url = iiif + "/full/%s/0/default.jpg" % sz
			filename = "%s_%s.jpg" % [Importer.slug(str(detailed.id)), variant]

	if dl_url.is_empty():
		return {"error": "No download URL available for SMK artwork."}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

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
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.search()

func cancel_all() -> void:
	client.cancel_all()
