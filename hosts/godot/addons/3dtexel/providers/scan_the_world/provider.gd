@tool
extends "res://addons/3dtexel/core/provider.gd"
## Scan The World 3D sculpture and cultural artifact provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/scan_the_world/client.gd")
const Cache = preload("res://addons/3dtexel/providers/scan_the_world/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "scan_the_world",
		"name": "Scan The World",
		"website": "https://www.myminifactory.com/scantheworld/",
		"key_env": [],
		"capabilities": ["model", "files", "variants"]
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
	var raw_id: Variant = raw.get("id", "")
	var id_str := str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id_str)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "scan_the_world"
	asset.provider = "Scan The World"
	asset.id = clean_id
	asset.type = "model"

	var display_title := str(raw.get("name", raw.get("title", "")))
	if display_title.is_empty():
		display_title = "Scan The World 3D Sculpture %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", "https://www.myminifactory.com/object/3d-print-%s" % id_str))

	# Thumbnail
	var thumb_url := str(raw.get("thumbnail", ""))
	if thumb_url.is_empty() and raw.has("images") and raw.images is Array and not raw.images.is_empty():
		var first_img: Dictionary = raw.images[0]
		if first_img.has("thumbnail") and first_img.thumbnail is Dictionary:
			thumb_url = str(first_img.thumbnail.get("url", ""))
		elif first_img.has("original") and first_img.original is Dictionary:
			thumb_url = str(first_img.original.get("url", ""))
	asset.thumbnail = thumb_url

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var origin := str(raw.get("origin_museum", "World Cultural Institution"))
		desc = "%s (%s) - Free cultural 3D sculpture scan from Scan The World." % [display_title, origin]
	asset.description = desc

	var museum_name := str(raw.get("origin_museum", raw.get("artist", "Scan The World")))
	asset.authors = [{"name": museum_name, "url": "https://www.myminifactory.com/scantheworld/"}]

	var tags := []
	for k in ["origin_museum", "artist", "category"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "cc0-1.0",
		"name": "Creative Commons Zero (CC0 1.0)",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (Scan The World / CC0)" % [display_title, museum_name]
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
	if not files.is_empty():
		for f in files:
			if not (f is Dictionary):
				continue
			var f_dict: Dictionary = f
			var fmt := str(f_dict.get("format", str(f_dict.get("filename", "")).get_extension()))
			if fmt.is_empty():
				fmt = "glb"
			var vid := Importer.slug(fmt)
			result.append({
				"id": vid,
				"label": "%s 3D Mesh" % vid.to_upper(),
				"kind": "files",
				"confirmed": true,
				"format": vid
			})
		return result

	return [
		{
			"id": "glb",
			"label": "GLB 3D Model",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "obj",
			"label": "OBJ 3D Mesh",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "stl",
			"label": "STL 3D Print Mesh",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "image", "material"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var per_page := 24
	var resp: Dictionary = await client.search(query, page, per_page)
	if resp.has("error"):
		return resp

	var items_list: Array = resp.get("items", [])
	var all_items: Array = []
	for it in items_list:
		if it is Dictionary:
			var norm: Dictionary = normalize(it, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total: int = int(resp.get("total", 0))
	var next_cur := ""
	if page * per_page < total:
		next_cur = str(page + 1)

	return {
		"items": all_items,
		"next_cursor": next_cur
	}

func asset_details(asset: Dictionary) -> Dictionary:
	return asset

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var target_variant := variant if not variant.is_empty() else "glb"
	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var download_url := ""
	var filename := ""

	for f in files:
		if f is Dictionary:
			var f_dict: Dictionary = f
			var fmt := str(f_dict.get("format", str(f_dict.get("filename", "")).get_extension())).to_lower()
			if fmt == target_variant or target_variant in fmt:
				download_url = str(f_dict.get("url", ""))
				filename = str(f_dict.get("filename", ""))
				break

	if download_url.is_empty() and not files.is_empty() and files[0] is Dictionary:
		download_url = str(files[0].get("url", ""))
		filename = str(files[0].get("filename", ""))

	if download_url.is_empty():
		return {"error": "No download URL available for Scan The World 3D sculpture."}

	if filename.is_empty():
		filename = "%s_%s.%s" % [str(detailed.get("id", "sculpture")), target_variant, target_variant]

	return {
		"kind": "files",
		"asset": detailed,
		"variant": target_variant,
		"files": [
			{
				"filename": filename,
				"url": download_url
			}
		]
	}

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	return await client.get_bytes(url, destination, limit)

func thumbnail(url: String) -> Texture2D:
	return null

func cancel_all() -> void:
	client.cancel_all()
