@tool
extends "res://addons/3dtexel/core/provider.gd"
## Library of Congress provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/library_of_congress/client.gd")
const Cache = preload("res://addons/3dtexel/providers/library_of_congress/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "library_of_congress",
		"name": "Library of Congress",
		"website": "https://www.loc.gov/",
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
	var raw_id: Variant = raw.get("pk", raw.get("id", ""))
	var id: String = str(raw_id)
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "library_of_congress"
	asset.provider = "Library of Congress"
	asset.id = clean_id
	asset.type = "image"

	var display_name := clean_id.capitalize()
	if raw.has("title") and not str(raw.title).is_empty():
		display_name = str(raw.title)
	asset.title = display_name

	asset.url = str(raw.get("links", {}).get("item", raw.get("url", "https://www.loc.gov/pictures/item/" + id)))

	var image_dict: Variant = raw.get("image", null)
	if image_dict is Dictionary:
		asset.thumbnail = str(image_dict.get("thumb", image_dict.get("square", "")))
	else:
		asset.thumbnail = str(raw.get("thumbnail", ""))

	asset.description = str(raw.get("summary", raw.get("description", "%s in Library of Congress" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var creator := str(raw.get("creator", "Library of Congress"))
	asset.authors = [{"name": creator, "url": "https://www.loc.gov/"}]

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain (No Known Copyright Restrictions)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (Library of Congress / Public Domain)" % [display_name, creator]
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
	if resp.has("results") and resp.results is Array:
		all_items = resp.results
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
		var img_dict: Variant = detailed.get("image", detailed.get("source_metadata", {}).get("image", null))
		if img_dict is Dictionary:
			if variant in ["1024", "small"]:
				dl_url = str(img_dict.get("alt", img_dict.get("full", "")))
			else:
				dl_url = str(img_dict.get("full", img_dict.get("alt", "")))

	if dl_url.is_empty():
		return {"error": "No download URL available for Library of Congress item."}

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
