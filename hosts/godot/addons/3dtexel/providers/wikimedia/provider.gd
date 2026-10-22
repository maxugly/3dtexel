@tool
extends "res://addons/3dtexel/core/provider.gd"
## Wikimedia Commons provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/wikimedia/client.gd")
const Cache = preload("res://addons/3dtexel/providers/wikimedia/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "wikimedia",
		"name": "Wikimedia Commons",
		"website": "https://commons.wikimedia.org/",
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
	var raw_id: Variant = raw.get("pageid", raw.get("id", ""))
	var id: String = str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "wikimedia"
	asset.provider = "Wikimedia Commons"
	asset.id = clean_id
	asset.type = "image"

	var title_str: String = str(raw.get("title", ""))
	if title_str.begins_with("File:"):
		title_str = title_str.substr(5).get_basename()
	var display_name := title_str.replace("_", " ").strip_edges()
	if display_name.is_empty():
		display_name = clean_id.capitalize()
	asset.title = display_name

	var img_info: Dictionary = {}
	var info_arr: Variant = raw.get("imageinfo", [])
	if info_arr is Array and not info_arr.is_empty() and info_arr[0] is Dictionary:
		img_info = info_arr[0]

	asset.url = str(img_info.get("descriptionurl", "https://commons.wikimedia.org/wiki/File:" + clean_id))
	asset.thumbnail = str(img_info.get("thumburl", img_info.get("url", raw.get("thumbnail", ""))))
	asset.description = str(raw.get("description", "%s at Wikimedia Commons" % display_name))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var ext_meta: Dictionary = img_info.get("extmetadata", {})
	var artist_meta: Dictionary = ext_meta.get("Artist", {})
	var creator := str(artist_meta.get("value", raw.get("artist", "Wikimedia Commons")))
	# Strip HTML tags if any in artist
	var tag_regex := RegEx.create_from_string("<[^>]*>")
	creator = tag_regex.sub(creator, "", true).strip_edges()
	if creator.is_empty():
		creator = "Wikimedia Commons"
	asset.authors = [{"name": creator, "url": asset.url}]

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain Mark 1.0 (PD-Art)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (Wikimedia Commons / Public Domain)" % [display_name, creator]
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

	if result.is_empty():
		result.append({
			"id": "orig",
			"label": "Original Maximum Resolution",
			"kind": "files",
			"confirmed": true
		})
		result.append({
			"id": "2048",
			"label": "2048px Resolution",
			"kind": "files",
			"confirmed": true
		})
		result.append({
			"id": "1024",
			"label": "1024px Preview",
			"kind": "files",
			"confirmed": true
		})

	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var offset := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
	var rows := 24
	var resp: Dictionary = await client.search(query, offset, rows)
	if resp.has("error"):
		return resp

	var all_items: Array = []
	if resp.has("query") and resp.query is Dictionary and resp.query.has("pages"):
		var pages_dict: Dictionary = resp.query.pages
		for p in pages_dict.values():
			if p is Dictionary:
				all_items.append(p)
	elif resp.has("items") and resp.items is Array:
		all_items = resp.items

	var items: Array[Dictionary] = []
	for raw in all_items:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if category == "material":
			normalized.type = "material"
		client.cache.put_asset(normalized)
		items.append(normalized)

	var next_cur := str(offset + rows) if all_items.size() >= rows else ""
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
	if dl_url.is_empty():
		var info_arr: Variant = detailed.get("imageinfo", detailed.get("source_metadata", {}).get("imageinfo", []))
		if info_arr is Array and not info_arr.is_empty() and info_arr[0] is Dictionary:
			dl_url = str(info_arr[0].get("url", ""))

	if dl_url.is_empty():
		return {"error": "No download URL available for Wikimedia artwork."}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var filename := str(chosen_file.get("filename", "%s.jpg" % Importer.slug(str(detailed.id))))

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
	return await client.search()

func cancel_all() -> void:
	client.cancel_all()
