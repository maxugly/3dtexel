@tool
extends "res://addons/3dtexel/core/provider.gd"
## NDL Image Bank Japan provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/ndl_imagebank/client.gd")
const Cache = preload("res://addons/3dtexel/providers/ndl_imagebank/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "ndl_imagebank",
		"name": "NDL Image Bank Japan",
		"website": "https://www.ndl.go.jp/imagebank/",
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
	var id := str(raw.get("id", ""))
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "ndl_imagebank"
	asset.provider = "NDL Image Bank Japan"
	asset.id = clean_id
	asset.type = "image"

	var display_name := clean_id.capitalize()
	if raw.has("title") and not str(raw.title).is_empty():
		display_name = str(raw.title)
	asset.title = display_name

	asset.url = str(raw.get("url", "https://www.ndl.go.jp/imagebank/item/" + id))
	asset.thumbnail = str(raw.get("thumbnail", ""))
	asset.description = str(raw.get("description", "%s from National Diet Library Image Bank" % display_name))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var creator := str(raw.get("artist", raw.get("creator", "National Diet Library")))
	asset.authors = [{"name": creator, "url": "https://www.ndl.go.jp/imagebank/"}]

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain Mark 1.0 (Out of Copyright)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s - NDL Image Bank (Public Domain)" % [display_name, creator]
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
			"id": "full",
			"label": "Full Resolution Image",
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
	if resp.has("items") and resp.items is Array:
		all_items = resp.items

	var items: Array[Dictionary] = []
	for raw in all_items:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if category == "material":
			normalized.type = "material"
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
	if dl_url.is_empty():
		dl_url = str(detailed.get("image_url", detailed.get("source_metadata", {}).get("image_url", "")))

	if dl_url.is_empty():
		return {"error": "No download URL available for NDL Image Bank artwork."}

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
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.search()

func cancel_all() -> void:
	client.cancel_all()
