@tool
extends "res://addons/3dtexel/core/provider.gd"
## Kenney game assets provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/kenney/client.gd")
const Cache = preload("res://addons/3dtexel/providers/kenney/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "kenney",
		"name": "Kenney",
		"website": "https://kenney.nl/assets",
		"key_env": [],
		"capabilities": ["files", "variants", "model", "audio", "material", "image"]
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
	var id := str(raw.get("id", raw.get("slug", "")))
	id = Importer.slug(id)
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "kenney"
	asset.provider = "Kenney"
	asset.id = id

	var raw_type := str(raw.get("type", asset.get("type", "model"))).to_lower()
	if raw_type.is_empty() or raw_type == "3d":
		raw_type = "model"
	elif raw_type == "2d":
		raw_type = "image"
	asset.type = raw_type

	var display_name := str(raw.get("title", id.capitalize()))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://kenney.nl/assets/" + id))
	asset.thumbnail = str(raw.get("thumbnail", "https://kenney.nl/media/pages/assets/%s/thumbnail.png" % id))
	asset.description = str(raw.get("description", asset.get("description", "%s by Kenney" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	asset.authors = [{"name": "Kenney", "url": "https://kenney.nl"}]

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons Zero (CC0)",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Assets by Kenney (https://kenney.nl) - CC0"
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var existing: Array = asset.get("variants", [])
	if not existing.is_empty():
		return existing

	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	var result := []
	if not files.is_empty():
		for f: Dictionary in files:
			var fname := str(f.get("filename", "pack.zip"))
			var vid := Importer.slug(fname.get_basename())
			result.append({
				"id": vid,
				"label": fname,
				"confirmed": true,
				"kind": "files"
			})
	else:
		result.append({
			"id": "zip",
			"label": "Full Asset Pack (ZIP)",
			"confirmed": true,
			"kind": "files"
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	var resp: Dictionary = await client.fetch_packs()
	if resp.has("error"):
		return resp

	var all_packs: Array = []
	if resp.has("items") and resp.items is Array:
		all_packs = resp.items
	elif resp.get("data") is Array:
		all_packs = resp.data

	var q := query.strip_edges().to_lower()
	var matched: Array[Dictionary] = []

	for raw in all_packs:
		if not (raw is Dictionary):
			continue
		var raw_dict: Dictionary = raw
		if not q.is_empty():
			var title_str := str(raw_dict.get("title", "")).to_lower()
			var desc_str := str(raw_dict.get("description", "")).to_lower()
			var id_str := str(raw_dict.get("id", "")).to_lower()
			var is_match := title_str.contains(q) or desc_str.contains(q) or id_str.contains(q)
			if not is_match:
				for t in raw_dict.get("tags", []):
					if str(t).to_lower().contains(q):
						is_match = true
						break
			if not is_match:
				continue

		if not category.is_empty() and category != "all":
			var cat_type := str(raw_dict.get("type", "")).to_lower()
			if cat_type != category:
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
	return normalize(asset, false)

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var dl_url := ""
	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	for f: Dictionary in files:
		if Importer.slug(str(f.get("filename", "")).get_basename()) == Importer.slug(variant):
			dl_url = str(f.get("url", ""))
			break

	if dl_url.is_empty():
		dl_url = str(detailed.get("download_url", ""))
	if dl_url.is_empty():
		var id := str(detailed.id)
		dl_url = "https://kenney.nl/media/pages/assets/%s/download/%s.zip" % [id, id]

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var filename := "%s.zip" % Importer.slug(str(detailed.id))

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
	return await client.fetch_packs()

func cancel_all() -> void:
	client.cancel_all()
