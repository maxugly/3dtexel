@tool
extends "res://addons/3dtexel/core/provider.gd"
## Kenney game assets provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/kenney/client.gd")
const Scan = preload("res://addons/3dtexel/core/html_scan.gd")
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

	var wanted := ""
	match category:
		"model": wanted = "3D"
		"material": wanted = "Textures"
		"audio": wanted = "Audio"
		"image": wanted = "2D"

	var page := int(cursor) if not cursor.is_empty() else 1
	var response: Dictionary = await client.fetch_packs(query, page) if wanted.is_empty() else await client.fetch_packs(query, page, wanted)
	if response.has("error"):
		return response

	var html := str(response.get("raw_text", ""))
	if html.is_empty():
		return {"error": "Kenney returned an empty listing."}

	var packs := parse_listing(html)
	if packs.is_empty():
		return {"items": [], "next_cursor": ""}

	var items: Array[Dictionary] = []
	for raw in packs:
		var categories: Array = raw.get("categories", [])
		if not wanted.is_empty():
			if not categories.has(wanted):
				continue
			raw["type"] = category
		var normalized := normalize(raw, true)
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_cursor := ""
	if Scan.match(html, "page:%d\\b" % (page + 1)) != "":
		next_cursor = str(page + 1)
	client.cache.save_catalog()
	return {"items": items, "next_cursor": next_cursor}

## Reads the pack cards from a Kenney listing page.
func parse_listing(html: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for block in Scan.blocks(html, "<div class='asset'>"):
		var url := Scan.match(block, "href='(https://kenney\\.nl/assets/[^']+)'")
		if url.is_empty():
			continue
		var title := Scan.text(Scan.match(block, "<h2>.*?</h2>"))
		var cover := Scan.match(block, "background-image:url\\(\\\"([^\\\"]+)\\\"\\)")
		var categories := Scan.matches(block, "category:([^'?]+)")
		var series := Scan.matches(block, "series:([^'?]+)")
		var id := url.get_file().trim_prefix("/assets/")
		result.append({
			"id": id,
			"title": title,
			"url": url,
			"thumbnail": cover,
			"categories": categories,
			"tags": series,
			"type": "model" if categories.has("3D") else ("material" if categories.has("Textures") else ("audio" if categories.has("Audio") else "image"))
		})
	return result

## Reads the direct download link and license from a pack page.
func parse_detail(html: String) -> Dictionary:
	var archive := Scan.match(html, "href='([^']+\\.zip)'")
	var license_url := Scan.match(html, "creativecommons\\.org/publicdomain/zero/1\\.0")
	var preview := Scan.match(html, "src='(https://kenney\\.nl/media[^']+preview\\.png)'")
	var files: Array[Dictionary] = []
	if not archive.is_empty():
		files.append({"filename": archive.get_file(), "url": archive})
	return {
		"download_url": archive,
		"files": files,
		"license_cc0": not license_url.is_empty(),
		"preview": preview
	}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	## The pack page is addressed by its own address, not by the normalized id.
	var page_url := str(asset.get("url", ""))
	if page_url.is_empty():
		var id := str(asset.get("id", ""))
		if id.is_empty():
			return normalize(asset, false)
		page_url = "https://kenney.nl/assets/" + id.replace("_", "-")
	var response: Dictionary = await client.text_request(page_url)
	if response.has("error"):
		return response
	var detail := parse_detail(str(response.get("raw_text", "")))
	var merged := asset.duplicate(true)
	merged.merge(detail, true)
	merged.source_metadata = detail
	return normalize(merged, false)

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
		return {"error": "Kenney does not publish a direct archive for this pack."}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var filename := dl_url.get_file()

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
	return await client.fetch_packs()

func cancel_all() -> void:
	client.cancel_all()
