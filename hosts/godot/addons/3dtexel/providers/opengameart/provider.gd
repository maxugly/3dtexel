@tool
extends "res://addons/3dtexel/core/provider.gd"
## OpenGameArt site provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/opengameart/client.gd")
const Parser = preload("res://addons/3dtexel/providers/opengameart/parser.gd")
const Cache = preload("res://addons/3dtexel/providers/opengameart/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "opengameart",
		"name": "OpenGameArt",
		"website": "https://opengameart.org/content/",
		"key_env": [],
		"capabilities": ["files", "variants", "model", "material", "audio", "image"]
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
	var id := str(raw.get("id", raw.get("slug", "")))
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "opengameart"
	asset.provider = "OpenGameArt"
	asset.id = id
	asset.type = str(raw.get("type", asset.get("type", "image")))
	asset.title = str(raw.get("title", asset.get("title", "Untitled")))
	asset.url = str(raw.get("url", asset.get("url", "https://opengameart.org/content/" + id)))
	asset.thumbnail = str(raw.get("thumbnail", asset.get("thumbnail", "")))
	asset.description = str(raw.get("description", asset.get("description", "")))
	asset.price = {"free": true, "credits": 0}

	asset.authors = Credits.authors(asset)
	if asset.authors.is_empty() and raw.has("author") and not str(raw.author).is_empty():
		asset.authors = [{"name": str(raw.author), "url": ""}]

	var lic_val: Variant = raw.get("license", asset.get("license", {}))
	asset.license = Credits.license_record(lic_val)
	if raw.has("licenses") and raw.licenses is Array:
		asset.licenses = raw.licenses
	elif not asset.has("licenses"):
		asset.licenses = [asset.license]

	if raw.has("selected_license"):
		asset.selected_license = raw.selected_license
	elif not asset.has("selected_license"):
		asset.selected_license = asset.license

	asset.attribution_text = str(raw.get("attribution_text", asset.get("attribution_text", "")))
	asset.metadata_source_url = str(raw.get("metadata_source_url", asset.url))
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
	if files.size() == 1:
		var f: Dictionary = files[0]
		var fname := str(f.get("filename", ""))
		var ext := fname.get_extension().to_lower()
		result.append({
			"id": "original",
			"label": "Original · " + (ext.to_upper() if not ext.is_empty() else "FILE"),
			"kind": "files",
			"confirmed": true,
			"filter_key": "format:" + ext if not ext.is_empty() else "",
			"filter_label": ext.to_upper() if not ext.is_empty() else ""
		})
	else:
		result.append({
			"id": "all-files",
			"label": "All Files (%d)" % files.size(),
			"kind": "files",
			"confirmed": true
		})
		var seen := {"all-files": true}
		for f: Dictionary in files:
			var fname := str(f.get("filename", ""))
			var ext := fname.get_extension().to_lower()
			var base_slug := Importer.slug(fname)
			if base_slug.is_empty():
				base_slug = "file"
			var vid := base_slug
			var counter := 1
			while seen.has(vid):
				vid = "%s_%d" % [base_slug, counter]
				counter += 1
			seen[vid] = true
			result.append({
				"id": vid,
				"label": fname,
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
	if category not in ["all", "material", "model", "audio", "image"]:
		return {"items": [], "next_cursor": ""}
	if not network_allowed:
		return {"error": "Refresh requires explicit action."}

	sync_network()

	var page_num := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
	var url := "https://opengameart.org/art-search?page=%d" % page_num

	var trimmed_query := query.strip_edges()
	if not trimmed_query.is_empty():
		url += "&keys=" + trimmed_query.uri_encode()

	match category:
		"material":
			url += "&field_art_type_tid[]=14"
		"model":
			url += "&field_art_type_tid[]=10"
		"audio":
			url += "&field_art_type_tid[]=12&field_art_type_tid[]=13"
		"image":
			url += "&field_art_type_tid[]=9&field_art_type_tid[]=11"

	var resp: Dictionary = await client.http_get_string(url)
	if resp.has("error"):
		return resp

	var parsed: Dictionary = Parser.parse_search_page(str(resp.get("body", "")), url)
	var items := []
	for raw: Dictionary in parsed.get("items", []):
		var normalized := normalize(raw, true)
		items.append(normalized)
		var thumb_url := str(normalized.get("thumbnail", ""))
		if not thumb_url.is_empty():
			client.allowed_thumbnails[thumb_url] = true
		client.cache.upsert(normalized)

	return {
		"items": items,
		"next_cursor": parsed.get("next_cursor", "")
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
	var url := str(asset.get("url", "https://opengameart.org/content/" + id))
	if not url.begins_with("https://"):
		url = Parser.clean_url(url)

	var resp: Dictionary = await client.http_get_string(url)
	if resp.has("error"):
		return resp

	var parsed: Dictionary = Parser.parse_asset_page(str(resp.get("body", "")), url)
	var updated := asset.duplicate(true)
	updated.merge(parsed, true)
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

	var id := str(asset.get("id", ""))
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
		return {"error": "No downloadable files found on source page."}

	if not Importer.free_asset(asset):
		return {"error": "Asset is not declared free."}

	var matched_files: Array[Dictionary] = []
	if variant == "all-files" or (variant == "original" and files.size() == 1):
		for f: Dictionary in files:
			matched_files.append({
				"filename": str(f.get("filename", "")),
				"url": str(f.get("url", ""))
			})
	else:
		# Match specific file by slug or filename
		for f: Dictionary in files:
			var fname := str(f.get("filename", ""))
			if Importer.slug(fname) == variant or fname == variant:
				matched_files.append({
					"filename": fname,
					"url": str(f.get("url", ""))
				})
				break
		if matched_files.is_empty() and files.size() == 1:
			matched_files.append({
				"filename": str(files[0].get("filename", "")),
				"url": str(files[0].get("url", ""))
			})

	if matched_files.is_empty():
		return {"error": "Requested variant '%s' not found among source files." % variant}

	for mf in matched_files:
		if not str(mf.url).begins_with("https://"):
			return {"error": "Download URL is not HTTPS: %s" % mf.url}

	return {
		"kind": "files",
		"asset": normalize(asset, false),
		"variant": variant,
		"files": matched_files
	}

func thumbnail(url: String) -> Texture2D:
	sync_network()
	return await client.thumbnail(url)

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	return await client.get_bytes(url, destination, limit)

func check_connection() -> Dictionary:
	return await client.http_get_string("https://opengameart.org/art-search")

func cancel_all() -> void:
	client.cancel_all()
