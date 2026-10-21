@tool
extends "res://addons/3dtexel/core/provider.gd"
## Art Institute of Chicago provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/aic/client.gd")
const Cache = preload("res://addons/3dtexel/providers/aic/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "aic",
		"name": "Art Institute of Chicago",
		"website": "https://www.artic.edu/",
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
	var id: String = str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "aic"
	asset.provider = "Art Institute of Chicago"
	asset.id = clean_id
	asset.type = "image"

	var display_name := clean_id.capitalize()
	if raw.has("title") and not str(raw.title).is_empty():
		display_name = str(raw.title)
	asset.title = display_name

	asset.url = str(raw.get("url", "https://www.artic.edu/artworks/" + id))

	var img_id: String = str(raw.get("image_id", ""))
	var thumb_dict: Variant = raw.get("thumbnail", null)
	if thumb_dict is Dictionary and thumb_dict.has("lqip"):
		asset.thumbnail = str(thumb_dict.lqip)
	elif not img_id.is_empty():
		asset.thumbnail = "https://www.artic.edu/iiif/2/%s/full/400,/0/default.jpg" % img_id
	else:
		asset.thumbnail = str(raw.get("thumbnail", ""))

	asset.description = str(raw.get("medium_display", "%s at Art Institute of Chicago" % display_name))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var creator := str(raw.get("artist_display", "Art Institute of Chicago"))
	asset.authors = [{"name": creator, "url": "https://www.artic.edu/"}]

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s - Art Institute of Chicago (CC0)" % [display_name, creator]
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
			"label": "Full Resolution Image",
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
			"id": "843",
			"label": "843px Standard",
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
	if resp.has("data") and resp.data is Array:
		all_items = resp.data
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
		var img_id := str(detailed.get("image_id", detailed.get("source_metadata", {}).get("image_id", "")))
		if not img_id.is_empty():
			if variant in ["843", "small"]:
				dl_url = "https://www.artic.edu/iiif/2/%s/full/843,/0/default.jpg" % img_id
			elif variant in ["2048", "large"]:
				dl_url = "https://www.artic.edu/iiif/2/%s/full/2048,/0/default.jpg" % img_id
			else:
				dl_url = "https://www.artic.edu/iiif/2/%s/full/max/0/default.jpg" % img_id

	if dl_url.is_empty():
		return {"error": "No download URL available for Art Institute of Chicago artwork."}

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
