@tool
extends "res://addons/3dtexel/core/provider.gd"
## NASA Multimedia provider adapter (Images, Audio, 3D Models) implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/nasa/client.gd")
const Cache = preload("res://addons/3dtexel/providers/nasa/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "nasa",
		"name": "NASA Multimedia",
		"website": "https://www.nasa.gov/multimedia/",
		"key_env": [],
		"capabilities": ["files", "variants", "image", "audio", "model", "material"]
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

func normalize(raw: Dictionary, fetched := false) -> Dictionary:
	var id := str(raw.get("id", raw.get("nasa_id", "")))
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "nasa"
	asset.provider = "NASA Multimedia"
	asset.id = id
	asset.type = str(raw.get("type", asset.get("type", "image")))
	asset.title = str(raw.get("title", asset.get("title", "NASA Asset " + id)))
	asset.url = str(raw.get("url", "https://images.nasa.gov/details/" + id))
	asset.thumbnail = str(raw.get("thumbnail", asset.get("thumbnail", "")))
	asset.description = str(raw.get("description", asset.get("description", "")))
	asset.price = {"free": true, "credits": 0}

	asset.authors = Credits.authors(asset)
	if asset.authors.is_empty() and raw.has("author") and not str(raw.author).is_empty():
		asset.authors = [{"name": str(raw.author), "url": "https://www.nasa.gov"}]

	var lic_val: Variant = raw.get("license", {
		"id": "public-domain",
		"name": "Public Domain (NASA Media Guidelines)",
		"url": "https://www.nasa.gov/multimedia/guidelines/index.html",
		"attribution_required": true
	})
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	var default_attr := "Image Credit: NASA"
	if asset.type == "audio":
		default_attr = "Audio Credit: NASA"
	elif asset.type == "model":
		default_attr = "3D Model Credit: NASA"
	asset.attribution_text = str(raw.get("attribution_text", default_attr))

	asset.metadata_source_url = str(raw.get("metadata_source_url", "https://images-api.nasa.gov/asset/" + id))
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

	if files.is_empty():
		return []

	var result := []
	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		var fname := str(f_dict.get("filename", ""))
		var vid := str(f_dict.get("variant_id", ""))
		if vid.is_empty():
			vid = Importer.slug(fname.get_basename())
		var ext := fname.get_extension().to_lower()
		var lbl := str(f_dict.get("label", vid.capitalize()))
		result.append({
			"id": vid,
			"label": lbl,
			"kind": "files",
			"confirmed": true,
			"filter_key": "format:" + ext if not ext.is_empty() else "",
			"filter_label": ext.to_upper() if not ext.is_empty() else ""
		})
	return result

func local_assets() -> Array:
	client.cache.ensure_loaded()
	var result := []
	for raw: Dictionary in client.cache.catalog.values():
		result.append(normalize(raw))
	return result

func local_import_roots() -> Array:
	return []

func legacy_folder(_output: String, _asset: Dictionary, _variant: String) -> String:
	return ""

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	if category not in ["all", "image", "audio", "model", "material"]:
		return {"items": [], "next_cursor": ""}
	if not network_allowed:
		return {"error": "Refresh requires explicit action."}

	sync_network()

	var page_num := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var media_param := "image,audio,3d"
	if category == "image" or category == "material":
		media_param = "image"
	elif category == "audio":
		media_param = "audio"
	elif category == "model":
		media_param = "3d"

	var url := "/search?page=%d&media_type=%s" % [page_num, media_param]

	var trimmed := query.strip_edges()
	if trimmed.is_empty() and category == "material":
		trimmed = "surface texture"
	elif trimmed.is_empty() and category == "audio":
		trimmed = "apollo"
	elif trimmed.is_empty() and category == "model":
		trimmed = "rover"
	elif trimmed.is_empty():
		trimmed = "earth"

	url += "&q=" + trimmed.uri_encode()

	var data: Dictionary = await client.json_request(url)
	if data.has("error"):
		return data

	var collection: Dictionary = data.get("collection", {})
	var raw_items: Array = collection.get("items", [])
	var items := []

	for item: Dictionary in raw_items:
		var data_arr: Array = item.get("data", [])
		if data_arr.is_empty():
			continue
		var meta: Dictionary = data_arr[0]
		var nasa_id := str(meta.get("nasa_id", ""))
		if nasa_id.is_empty():
			continue

		var title := str(meta.get("title", "NASA Asset " + nasa_id))
		var desc := str(meta.get("description", ""))
		var center := str(meta.get("center", "NASA"))
		var photog := str(meta.get("photographer", meta.get("secondary_creator", ""))).strip_edges()

		var authors := []
		if not photog.is_empty():
			authors.append({"name": photog, "url": ""})
		authors.append({"name": "NASA / " + center, "url": "https://www.nasa.gov"})

		var thumb := ""
		for link: Dictionary in item.get("links", []):
			if link.get("rel", "") == "preview" or str(link.get("href", "")).contains("~thumb"):
				thumb = str(link.get("href", ""))
				break

		var raw_media := str(meta.get("media_type", "image")).to_lower()
		var asset_type := "image"
		var attr_prefix := "Image Credit: "
		if raw_media == "audio":
			asset_type = "audio"
			attr_prefix = "Audio Credit: "
		elif raw_media in ["3d", "model"]:
			asset_type = "model"
			attr_prefix = "3D Model Credit: "
		elif category == "material":
			asset_type = "material"

		var raw_asset := {
			"id": nasa_id,
			"title": title,
			"type": asset_type,
			"url": "https://images.nasa.gov/details/" + nasa_id,
			"thumbnail": thumb,
			"description": desc,
			"tags": meta.get("keywords", []),
			"authors": authors,
			"author": authors[0].name,
			"attribution_text": attr_prefix + (photog if not photog.is_empty() else "NASA / " + center),
			"source_metadata": meta
		}

		var normalized := normalize(raw_asset, true)
		items.append(normalized)
		if not thumb.is_empty():
			client.allowed_thumbnails[thumb] = true
		client.cache.upsert(normalized)

	var next_cursor := ""
	for link: Dictionary in collection.get("links", []):
		if link.get("rel", "") == "next":
			next_cursor = str(page_num + 1)
			break

	return {
		"items": items,
		"next_cursor": next_cursor
	}

func asset_details(asset: Dictionary) -> Dictionary:
	var id := str(asset.get("id", ""))
	var cached: Dictionary = client.cache.asset(id)
	var cached_files: Array = cached.get("files", cached.get("source_metadata", {}).get("files", []))
	if not cached_files.is_empty() and not refreshing:
		return normalize(cached, false)

	if not network_allowed:
		return {"error": "Choose an asset first."}

	sync_network()
	var url := "/asset/" + id
	var data: Dictionary = await client.json_request(url)
	if data.has("error"):
		return data

	var items: Array = data.get("collection", {}).get("items", [])
	var files: Array[Dictionary] = []
	var seen_variants := {}

	# 1. Image resolutions check
	var size_priority := ["orig", "large", "medium", "small"]
	for target_size in size_priority:
		for it: Dictionary in items:
			var href := str(it.get("href", ""))
			if href.contains("~" + target_size + ".") and (href.ends_with(".jpg") or href.ends_with(".png") or href.ends_with(".tif")):
				var fname := href.get_file().get_slice("?", 0)
				files.append({
					"filename": fname,
					"variant_id": target_size,
					"label": target_size.capitalize(),
					"url": href
				})
				seen_variants[target_size] = true
				break

	# 2. Audio, 3D models, and direct formats
	for it: Dictionary in items:
		var href := str(it.get("href", ""))
		var lower := href.to_lower()
		if lower.contains("~thumb") or lower.contains("metadata.json"):
			continue
		var is_media := lower.ends_with(".wav") or lower.ends_with(".mp3") or lower.ends_with(".m4a") or lower.ends_with(".ogg") \
			or lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".obj") or lower.ends_with(".stl") or lower.ends_with(".zip") \
			or ((lower.ends_with(".jpg") or lower.ends_with(".png")) and files.is_empty())
		if is_media:
			var fname := href.get_file().get_slice("?", 0)
			var base := fname.get_basename()
			var vid := Importer.slug(base)
			if not seen_variants.has(vid):
				seen_variants[vid] = true
				var ext := fname.get_extension().to_upper()
				files.append({
					"filename": fname,
					"variant_id": vid,
					"label": "%s (%s)" % [base.capitalize(), ext],
					"url": href
				})

	var updated := asset.duplicate(true)
	updated["files"] = files
	if updated.has("source_metadata") and updated.source_metadata is Dictionary:
		updated.source_metadata["files"] = files

	var normalized := normalize(updated, true)
	client.cache.upsert(normalized)
	return normalized

func refresh_asset(asset: Dictionary) -> Dictionary:
	if not network_allowed:
		return {"error": "Metadata refresh requires explicit action."}
	sync_network()
	client.refreshing = true
	var res := await asset_details(asset)
	client.refreshing = false
	return res

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}

	sync_network()

	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	if files.is_empty():
		var details: Dictionary = await asset_details(asset)
		if details.has("error"):
			return details
		files = details.get("files", details.get("source_metadata", {}).get("files", []))
		asset = details

	if files.is_empty():
		return {"error": "No downloadable variants available for NASA asset."}

	var matched_file: Dictionary = {}
	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		if str(f_dict.get("variant_id", "")) == variant or str(f_dict.get("filename", "")) == variant or Importer.slug(str(f_dict.get("filename", "")).get_basename()) == Importer.slug(variant):
			matched_file = f_dict
			break

	if matched_file.is_empty() and not files.is_empty() and files[0] is Dictionary:
		matched_file = files[0]

	if matched_file.is_empty():
		return {"error": "Variant '%s' not found." % variant}

	var dl_url := str(matched_file.get("url", ""))
	if not dl_url.begins_with("https://"):
		return {"error": "Download URL is not HTTPS: %s" % dl_url}

	return {
		"kind": "files",
		"asset": normalize(asset, false),
		"variant": variant,
		"files": [
			{
				"filename": str(matched_file.get("filename", "nasa_media")),
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
	return await client.json_request("/search?q=earth&page=1")

func cancel_all() -> void:
	client.cancel_all()
