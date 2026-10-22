@tool
extends "res://addons/3dtexel/core/provider.gd"
## Mixkit Audio provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/mixkit/client.gd")
const Cache = preload("res://addons/3dtexel/providers/mixkit/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "mixkit",
		"name": "Mixkit Audio",
		"website": "https://mixkit.co/free-sound-effects/",
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
	var raw_id: Variant = raw.get("id", raw.get("slug", ""))
	var id_str := str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id_str)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "mixkit"
	asset.provider = "Mixkit Audio"
	asset.id = clean_id
	asset.type = "audio"

	var display_title := str(raw.get("title", raw.get("name", "")))
	if display_title.is_empty():
		display_title = "Mixkit Sound %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", "https://mixkit.co/free-sound-effects/%s/" % clean_id))
	asset.thumbnail = str(raw.get("thumbnail", raw.get("cover_image", "")))

	var creator := str(raw.get("author", "Mixkit"))
	asset.authors = [{"name": creator, "url": "https://mixkit.co"}]

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var cat := str(raw.get("category", "Game Sound Effect"))
		var dur := float(raw.get("duration", 0.0))
		desc = "%s (%s) - Royalty-free sound effect from Mixkit (%0.1fs)." % [display_title, cat, dur]
	asset.description = desc

	var tags := []
	if raw.has("tags") and raw.tags is Array:
		tags.append_array(raw.tags)
	for k in ["category", "mood", "instrument"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "cc0-1.0",
		"name": "Mixkit Free Sound Effects License",
		"url": "https://mixkit.co/license/#sfxFree",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "\"%s\" - Mixkit Free Sound Effects License" % display_title
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	return [
		{
			"id": "mp3",
			"label": "MP3 Audio File",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "wav",
			"label": "WAV Audio File",
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

	var results: Array = resp.get("items", resp.get("results", []))
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

	var target_variant := variant if not variant.is_empty() else "mp3"
	var files: Dictionary = detailed.get("files", {})
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", {})

	var download_url := ""
	var filename := ""

	if files.has(target_variant):
		download_url = str(files[target_variant])
		filename = "%s.%s" % [str(detailed.get("id", "mixkit")), target_variant]
	else:
		download_url = str(detailed.get("audio_url", detailed.get("download_url", "")))
		if download_url.is_empty():
			return {"error": "No download URL available for Mixkit audio."}
		var ext := download_url.get_file().get_extension()
		if ext.is_empty() or ext.contains("?"):
			ext = target_variant
		filename = "%s.%s" % [str(detailed.get("id", "mixkit")), ext]

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
