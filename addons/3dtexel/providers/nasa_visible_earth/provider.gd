@tool
extends "res://addons/3dtexel/core/provider.gd"
## NASA Visible Earth provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/nasa_visible_earth/client.gd")
const Cache = preload("res://addons/3dtexel/providers/nasa_visible_earth/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "nasa_visible_earth",
		"name": "NASA Visible Earth",
		"website": "https://visibleearth.nasa.gov/",
		"key_env": [],
		"capabilities": ["image", "material", "files", "variants"]
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

	asset.provider_id = "nasa_visible_earth"
	asset.provider = "NASA Visible Earth"
	asset.id = clean_id
	asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "Visible Earth Image %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", "https://visibleearth.nasa.gov/images/%s" % id_str))
	asset.thumbnail = str(raw.get("thumbnail", ""))

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var coll := str(raw.get("collection", "Earth Science"))
		desc = "%s (%s) - Satellite imagery of Earth produced by NASA Earth Observatory." % [display_title, coll]
	asset.description = desc

	var author_name := "NASA Earth Observatory"
	asset.authors = [{"name": author_name, "url": "https://visibleearth.nasa.gov/"}]

	var tags := []
	for k in ["collection", "date", "sensor"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain (NASA / US Government Work)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - NASA Earth Observatory / Visible Earth (Public Domain)" % display_title
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
			var res := str(f_dict.get("resolution", f_dict.get("filename", "")))
			var vid := Importer.slug(res)
			result.append({
				"id": vid,
				"label": "%s Resolution" % vid.to_upper(),
				"kind": "files",
				"confirmed": true,
				"resolution": vid
			})
		return result

	return [
		{
			"id": "orig",
			"label": "21600x10800 Ultra Resolution",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "5400x2700",
			"label": "5400x2700 High Resolution",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "2048x1024",
			"label": "2048x1024 Standard Resolution",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var page_size := 24
	var resp: Dictionary = await client.search(query, page, page_size)
	if resp.has("error"):
		return resp

	var results: Array = resp.get("results", [])
	var all_items: Array = []
	for r in results:
		if r is Dictionary:
			var norm: Dictionary = normalize(r, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total: int = int(resp.get("total", 0))
	var next_cur := ""
	if page * page_size < total:
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

	var target_variant := variant if not variant.is_empty() else "5400x2700"
	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var download_url := ""
	var filename := ""

	for f in files:
		if f is Dictionary:
			var f_dict: Dictionary = f
			var res_slug := Importer.slug(str(f_dict.get("resolution", "")))
			if res_slug == target_variant or target_variant in res_slug:
				download_url = str(f_dict.get("url", ""))
				filename = str(f_dict.get("filename", ""))
				break

	if download_url.is_empty() and not files.is_empty() and files[0] is Dictionary:
		download_url = str(files[0].get("url", ""))
		filename = str(files[0].get("filename", ""))

	if download_url.is_empty():
		download_url = str(detailed.get("thumbnail", ""))

	if download_url.is_empty():
		return {"error": "No download URL available for Visible Earth image."}

	if filename.is_empty():
		var ext := download_url.get_file().get_extension()
		if ext.is_empty() or ext.contains("?"):
			ext = "jpg"
		filename = "%s_%s.%s" % [str(detailed.get("id", "earth")), target_variant, ext]

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
