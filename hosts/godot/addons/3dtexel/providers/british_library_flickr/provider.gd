@tool
extends "res://addons/3dtexel/core/provider.gd"
## British Library Flickr Commons provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/british_library_flickr/client.gd")
const Cache = preload("res://addons/3dtexel/providers/british_library_flickr/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "british_library_flickr",
		"name": "British Library",
		"website": "https://www.flickr.com/photos/britishlibrary/",
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

	asset.provider_id = "british_library_flickr"
	asset.provider = "British Library"
	asset.id = clean_id
	asset.type = "image"

	var display_title := ""
	if raw.has("title"):
		var t: Variant = raw.title
		if t is Dictionary:
			display_title = str(t.get("_content", ""))
		else:
			display_title = str(t)
	if display_title.is_empty():
		display_title = "British Library Item %s" % id_str
	asset.title = display_title

	asset.url = "https://www.flickr.com/photos/britishlibrary/%s/" % id_str

	# Thumbnails
	var thumb_url := ""
	for k in ["url_m", "url_z", "url_q", "url_s", "url_b"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			thumb_url = str(raw[k])
			break
	asset.thumbnail = thumb_url

	var desc_text := ""
	if raw.has("description"):
		var d: Variant = raw.description
		if d is Dictionary:
			desc_text = str(d.get("_content", ""))
		else:
			desc_text = str(d)
	if desc_text.is_empty():
		desc_text = "%s - Public domain historical illustration from the British Library." % display_title
	asset.description = desc_text

	var tag_list := []
	if raw.has("tags"):
		var t_val: Variant = raw.tags
		if t_val is String:
			for tag in t_val.split(" ", false):
				tag_list.append(tag)
		elif t_val is Array:
			tag_list = t_val
	asset.tags = tag_list

	asset.price = {"free": true, "credits": 0}

	var author_name := "The British Library"
	if raw.has("ownername") and not str(raw.ownername).is_empty():
		author_name = str(raw.ownername)
	asset.authors = [{"name": author_name, "url": "https://www.flickr.com/photos/britishlibrary/"}]

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain Mark 1.0 (No Known Copyright Restrictions)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - British Library (Flickr Commons / Public Domain)" % display_title
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
		return result

	var src: Dictionary = asset.get("source_metadata", {})
	if src.has("url_o") and not str(src.url_o).is_empty():
		result.append({
			"id": "orig",
			"label": "Original Maximum Resolution",
			"kind": "files",
			"confirmed": true
		})
	if src.has("url_b") or result.is_empty():
		result.append({
			"id": "1024",
			"label": "1024px Resolution",
			"kind": "files",
			"confirmed": true
		})
	if src.has("url_z"):
		result.append({
			"id": "640",
			"label": "640px Resolution",
			"kind": "files",
			"confirmed": true
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var per_page := 24
	var resp: Dictionary = await client.search(query, page, per_page)
	if resp.has("error"):
		return resp

	var photos_container: Dictionary = resp.get("photos", {})
	var photo_list: Array = photos_container.get("photo", [])

	var all_items: Array = []
	for p in photo_list:
		if p is Dictionary:
			var norm: Dictionary = normalize(p, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total_pages: int = int(photos_container.get("pages", 1))
	var next_cur := ""
	if page < total_pages:
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

	var target_variant := variant
	var all_vars := variants(detailed)
	if target_variant.is_empty() and not all_vars.is_empty():
		target_variant = str(all_vars[0].id)

	var download_url := ""
	var src: Dictionary = detailed.get("source_metadata", {})

	if target_variant == "orig" and src.has("url_o"):
		download_url = str(src.url_o)
	elif target_variant == "1024" and src.has("url_b"):
		download_url = str(src.url_b)
	elif target_variant == "640" and src.has("url_z"):
		download_url = str(src.url_z)
	else:
		for k in ["url_o", "url_b", "url_z", "url_m"]:
			if src.has(k) and not str(src[k]).is_empty():
				download_url = str(src[k])
				break

	if download_url.is_empty():
		download_url = str(detailed.get("thumbnail", ""))

	if download_url.is_empty():
		return {"error": "No download URL available for British Library item."}

	var ext := download_url.get_file().get_extension()
	if ext.is_empty() or ext.contains("?"):
		ext = "jpg"

	var clean_id: String = str(detailed.get("id", "asset"))
	var filename := "%s_%s.%s" % [clean_id, target_variant, ext]

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
