@tool
extends "res://addons/3dtexel/core/provider.gd"
## ambientCG provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/ambientcg/client.gd")
const Cache = preload("res://addons/3dtexel/providers/ambientcg/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "ambientcg",
		"name": "ambientCG",
		"website": "https://ambientcg.com/",
		"key_env": [],
		"capabilities": ["files", "variants", "material", "model", "image"]
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
	var id := str(raw.get("assetId", raw.get("id", "")))
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "ambientcg"
	asset.provider = "ambientCG"
	asset.id = id

	var raw_type := str(raw.get("dataType", raw.get("type", asset.get("type", "Material"))))
	match raw_type.to_lower():
		"material", "atlas", "decal", "substance", "terrain", "plaintexture":
			asset.type = "material"
		"3dmodel":
			asset.type = "model"
		"hdri":
			asset.type = "image"
		_:
			asset.type = "material"

	var display_name := str(raw.get("languageIndependentName", raw.get("name", raw.get("title", id))))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://ambientcg.com/a/" + id))
	asset.thumbnail = str(raw.get("previewImage", raw.get("thumbnail", "https://ambientcg.com/get?preview=" + id)))
	asset.description = str(raw.get("description", asset.get("description", "%s by ambientCG" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	asset.authors = [{"name": "Lennart Demes", "url": "https://ambientcg.com"}]

	var lic_val: Variant = raw.get("license", {
		"id": "cc0",
		"name": "CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	})
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Created by Lennart Demes for ambientCG (CC0)"
	asset.metadata_source_url = "https://ambientcg.com/a/" + id
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var dl_data: Dictionary = {}
	if asset.has("downloadData") and asset.downloadData is Dictionary:
		dl_data = asset.downloadData
	elif asset.has("download_data") and asset.download_data is Dictionary:
		dl_data = asset.download_data
	elif asset.get("source_metadata") is Dictionary and asset.source_metadata.get("downloadData") is Dictionary:
		dl_data = asset.source_metadata.get("downloadData")

	if dl_data.is_empty():
		return asset.get("variants", [])

	var result := []
	var keys := dl_data.keys()
	keys.sort()
	for k: String in keys:
		var vid := Importer.slug(k)
		result.append({
			"id": vid,
			"label": k,
			"confirmed": true,
			"kind": "files",
			"resolution": vid
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	var type_param := ""
	match category:
		"material": type_param = "Material"
		"model": type_param = "3DModel"
		"image": type_param = "HDRI"
		"audio":
			return {"items": [], "next_cursor": ""}
		_:
			type_param = ""

	var offset := int(cursor) if not cursor.is_empty() else 0
	var page_size := 30

	var resp: Dictionary = await client.fetch_assets(query, type_param, page_size, offset)
	if resp.has("error"):
		return resp

	var raw_assets: Array = []
	if resp.has("assets") and resp.assets is Array:
		raw_assets = resp.assets
	elif resp.has("items") and resp.items is Array:
		raw_assets = resp.items

	var items: Array[Dictionary] = []
	for raw in raw_assets:
		if raw is Dictionary:
			var normalized := normalize(raw, true)
			client.cache.put_asset(normalized)
			items.append(normalized)

	var total_found := int(resp.get("foundAssets", raw_assets.size()))
	var next_cur := str(offset + page_size) if (offset + page_size < total_found) else ""
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	var id := str(asset.get("id", ""))
	if id.is_empty():
		return {"error": "Missing asset ID."}

	var resp: Dictionary = await client.fetch_assets(id, "", 1, 0)
	if resp.has("error"):
		return resp

	var raw_assets: Array = resp.get("assets", [])
	if raw_assets.is_empty():
		return normalize(asset, false)

	var fresh_raw: Dictionary = raw_assets[0]
	var normalized := normalize(fresh_raw, true)
	client.cache.put_asset(normalized)
	return normalized

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var dl_data: Dictionary = {}
	if detailed.has("downloadData") and detailed.downloadData is Dictionary:
		dl_data = detailed.downloadData
	elif detailed.has("download_data") and detailed.download_data is Dictionary:
		dl_data = detailed.download_data
	elif detailed.get("source_metadata") is Dictionary and detailed.source_metadata.get("downloadData") is Dictionary:
		dl_data = detailed.source_metadata.get("downloadData")

	var matched_entry: Dictionary = {}
	var matched_key := ""
	var target_slug := Importer.slug(variant)

	for k in dl_data:
		if Importer.slug(k) == target_slug:
			matched_key = k
			if dl_data[k] is Dictionary:
				matched_entry = dl_data[k]
			break

	if matched_entry.is_empty():
		if not dl_data.is_empty():
			matched_key = str(dl_data.keys()[0])
			if dl_data[matched_key] is Dictionary:
				matched_entry = dl_data[matched_key]

	if matched_entry.is_empty():
		return {"error": "No download entry found for variant %s." % variant}

	var dl_url := str(matched_entry.get("downloadLink", matched_entry.get("rawLink", "")))
	if dl_url.is_empty():
		return {"error": "Missing download URL for variant %s." % variant}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var id := str(detailed.id)
	var ext := dl_url.get_file().get_extension().to_lower()
	if ext.is_empty():
		ext = "zip"
	var filename := "%s_%s.%s" % [id, Importer.slug(matched_key), ext]

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
	return await client.fetch_assets("", "Material", 1, 0)

func cancel_all() -> void:
	client.cancel_all()
