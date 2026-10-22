@tool
extends "res://addons/3dtexel/core/provider.gd"
## itch.io provider adapter with public asset feeds and API key management.

const Client = preload("res://addons/3dtexel/providers/itch_io/client.gd")
const Cache = preload("res://addons/3dtexel/providers/itch_io/cache.gd")
const Parser = preload("res://addons/3dtexel/providers/itch_io/parser.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_key := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "itch_io",
		"name": "itch.io",
		"website": "https://itch.io/game-assets",
		"key_env": ["ITCHIO_API_KEY"],
		"capabilities": ["files", "variants", "model", "image", "audio", "material"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_key = api_key()

func api_key() -> String:
	if not session_key.is_empty():
		return session_key
	return OS.get_environment("ITCHIO_API_KEY")

func set_session_key(value: String) -> void:
	session_key = value.strip_edges()
	client.api_key = session_key

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "No key set. Public browse enabled; set ITCHIO_API_KEY for library downloads."

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
	var link := str(raw.get("link", raw.get("url", "")))
	var id := str(raw.get("id", ""))
	if id.is_empty() and not link.is_empty():
		var clean_link := link.trim_suffix("/")
		id = clean_link.get_slice("/", clean_link.get_slice_count("/") - 1)
	if id.is_empty():
		id = str(raw.get("guid", "itch_asset_" + str(Time.get_ticks_usec())))
	id = Importer.slug(id)

	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "itch_io"
	asset.provider = "itch.io"
	asset.id = id

	var title_str := str(raw.get("title", id.capitalize()))
	asset.title = title_str

	# Type inference
	var desc_lower := str(raw.get("description", "")).to_lower()
	var title_lower := title_str.to_lower()
	var combined := title_lower + " " + desc_lower

	var detected_type := str(raw.get("type", ""))
	if detected_type.is_empty():
		if "3d" in combined or "model" in combined or "mesh" in combined or "character" in combined:
			detected_type = "model"
		elif "sound" in combined or "sfx" in combined or "audio" in combined or "music" in combined or "wav" in combined:
			detected_type = "audio"
		elif "texture" in combined or "material" in combined or "shader" in combined:
			detected_type = "material"
		else:
			detected_type = "image"
	asset.type = detected_type

	asset.url = link if not link.is_empty() else str(raw.get("url", "https://itch.io"))
	asset.thumbnail = str(raw.get("thumbnail", asset.get("thumbnail", "")))
	asset.description = str(raw.get("description", asset.get("description", "")))
	asset.price = {"free": true, "credits": 0}

	var creator := str(raw.get("creator", raw.get("author", "itch.io Creator")))
	if creator.is_empty():
		creator = "itch.io Creator"
	var author_url := str(raw.get("author_url", ""))
	if author_url.is_empty() and link.contains(".itch.io"):
		author_url = link.substr(0, link.find(".itch.io") + 8)
	if author_url.is_empty():
		author_url = "https://itch.io"
	asset.authors = [{"name": creator, "url": author_url}]

	var lic_val: Variant = raw.get("license", {
		"id": "cc0",
		"name": "Creative Commons / Free Game Asset",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	})
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Asset '%s' by %s via itch.io" % [title_str, creator]
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
			var fname := str(f.get("filename", f.get("name", "archive.zip")))
			var vid := Importer.slug(fname.get_basename())
			result.append({
				"id": vid,
				"label": fname,
				"confirmed": true,
				"kind": "files"
			})
	else:
		# Standard downloadable archive from itch.io project
		result.append({
			"id": "zip",
			"label": "Download Archive (ZIP)",
			"confirmed": true,
			"kind": "files"
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	var feed_path := "/game-assets/free.xml"
	if category == "audio":
		feed_path = "/game-assets/free/tag-audio.xml"
	elif category == "model":
		feed_path = "/game-assets/free/tag-3d.xml"
	elif category == "material":
		feed_path = "/game-assets/free/tag-textures.xml"

	var resp: Dictionary = await client.fetch_feed(feed_path)
	if resp.has("error"):
		return resp

	var xml_text := str(resp.get("text", ""))
	var parsed_items: Array[Dictionary] = Parser.parse_feed(xml_text)

	var q := query.strip_edges().to_lower()
	var matched: Array[Dictionary] = []

	for raw in parsed_items:
		if not q.is_empty():
			var title_str := str(raw.get("title", "")).to_lower()
			var desc_str := str(raw.get("description", "")).to_lower()
			var creator_str := str(raw.get("creator", "")).to_lower()
			if not (title_str.contains(q) or desc_str.contains(q) or creator_str.contains(q)):
				continue

		if not category.is_empty() and category != "all":
			var normalized_pre := normalize(raw, false)
			if normalized_pre.type != category:
				continue

		matched.append(raw)

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
		if Importer.slug(str(f.get("filename", f.get("name", ""))).get_basename()) == Importer.slug(variant):
			dl_url = str(f.get("url", f.get("download_url", "")))
			break

	if dl_url.is_empty():
		dl_url = str(detailed.get("download_url", ""))
	if dl_url.is_empty() and detailed.get("source_metadata") is Dictionary:
		dl_url = str(detailed.source_metadata.get("download_url", ""))
	if dl_url.is_empty():
		var page_url := str(detailed.get("url", ""))
		if not page_url.is_empty():
			dl_url = page_url.trim_suffix("/") + "/download"

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
	return await client.fetch_feed("/game-assets/free.xml")

func cancel_all() -> void:
	client.cancel_all()
