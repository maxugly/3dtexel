@tool
extends "res://addons/3dtexel/core/provider.gd"
## LibriVox provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/librivox/client.gd")
const Cache = preload("res://addons/3dtexel/providers/librivox/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "librivox",
		"name": "LibriVox",
		"website": "https://librivox.org/",
		"key_env": [],
		"capabilities": ["audio", "files", "variants"]
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

	asset.provider_id = "librivox"
	asset.provider = "LibriVox"
	asset.id = clean_id
	asset.type = "audio"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "LibriVox Audio %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url_librivox", raw.get("url", "https://librivox.org/search?q=%s" % clean_id)))
	asset.thumbnail = str(raw.get("thumbnail", raw.get("coverart_thumbnail", "")))

	# Authors and readers
	var authors_list: Array = raw.get("authors", [])
	var author_names := []
	if not authors_list.is_empty() and authors_list[0] is Dictionary:
		for a in authors_list:
			if a is Dictionary:
				var fn := str(a.get("first_name", "")).strip_edges()
				var ln := str(a.get("last_name", "")).strip_edges()
				var full := ("%s %s" % [fn, ln]).strip_edges()
				if not full.is_empty():
					author_names.append(full)
	var author_str := ", ".join(author_names) if not author_names.is_empty() else str(raw.get("author", "LibriVox Volunteer Readers"))
	asset.authors = [{"name": author_str, "url": asset.url}]

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var total_time := str(raw.get("totaltime", ""))
		desc = "%s by %s - Public domain spoken recording from LibriVox (%s)." % [display_title, author_str, total_time]
	asset.description = desc

	var tags := []
	if raw.has("genres") and raw.genres is Array:
		for g in raw.genres:
			if g is Dictionary:
				tags.append(str(g.get("name", "")))
	if raw.has("language") and not str(raw.language).is_empty():
		tags.append(str(raw.language))
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain Mark 1.0",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "\"%s\" by %s - LibriVox (Public Domain)" % [display_title, author_str]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	return [
		{
			"id": "mp3_128",
			"label": "128kbps MP3 Audio Stream",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "mp3_64",
			"label": "64kbps MP3 Audio Stream",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "ogg",
			"label": "OGG Audio Stream",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["image", "model", "material"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var page_size := 24
	var resp: Dictionary = await client.search(query, page, page_size)
	if resp.has("error"):
		return resp

	var results: Array = resp.get("books", resp.get("audiobooks", resp.get("results", [])))
	var all_items: Array = []
	for r in results:
		if r is Dictionary:
			var norm: Dictionary = normalize(r, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total: int = int(resp.get("total", results.size()))
	var next_cur := ""
	if page * page_size < total:
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

	var target_variant := variant if not variant.is_empty() else "mp3_128"
	var download_url := ""
	var filename := ""

	var files: Dictionary = detailed.get("files", {})
	if files.has(target_variant):
		download_url = str(files[target_variant])
	elif target_variant == "mp3_128":
		download_url = str(detailed.get("url_zip_file", detailed.get("url_audio_file", detailed.get("audio_url", ""))))
	elif target_variant == "ogg":
		download_url = str(detailed.get("url_ogg_file", detailed.get("audio_url", "")))
	else:
		download_url = str(detailed.get("url_audio_file", detailed.get("audio_url", "")))

	if download_url.is_empty():
		return {"error": "No download URL available for LibriVox recording."}

	var ext := download_url.get_file().get_extension()
	if ext.is_empty() or ext.contains("?"):
		ext = "mp3"
	filename = "%s_%s.%s" % [str(detailed.get("id", "librivox")), target_variant, ext]

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
