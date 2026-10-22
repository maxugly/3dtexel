@tool
extends "res://addons/3dtexel/core/provider.gd"
## Openverse provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/openverse/client.gd")
const Cache = preload("res://addons/3dtexel/providers/openverse/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "openverse",
		"name": "Openverse",
		"website": "https://openverse.org/",
		"key_env": [],
		"capabilities": ["image", "audio", "material", "files", "variants"]
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

	asset.provider_id = "openverse"
	asset.provider = "Openverse"
	asset.id = clean_id

	var mediatype := str(raw.get("media_type", raw.get("category", ""))).to_lower()
	if mediatype == "audio" or raw.has("audio_set") or raw.has("waveform"):
		asset.type = "audio"
	else:
		asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "Openverse Item %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("foreign_landing_url", raw.get("url", "https://openverse.org/%s/%s" % [asset.type, id_str])))
	asset.thumbnail = str(raw.get("thumbnail", raw.get("url", "")))

	var creator := str(raw.get("creator", "Unknown Creator"))
	var creator_url := str(raw.get("creator_url", asset.url))
	asset.authors = [{"name": creator, "url": creator_url}]

	var source_name := str(raw.get("source", raw.get("provider", "Openverse Collection")))
	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		desc = "%s by %s [Source: %s]" % [display_title, creator, source_name]
	asset.description = desc

	var tags := []
	if raw.has("tags") and raw.tags is Array:
		for t in raw.tags:
			if t is Dictionary:
				tags.append(str(t.get("name", "")))
			elif t is String:
				tags.append(t)
	tags.append(source_name)
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	# License normalization
	var lic_str := str(raw.get("license", "")).to_lower().strip_edges()
	var lic_ver := str(raw.get("license_version", "")).strip_edges()

	var lic_id := "cc0-1.0"
	var lic_name := "Creative Commons Zero (CC0 1.0)"
	var lic_url := "https://creativecommons.org/publicdomain/zero/1.0/"
	var attr_req := false

	if lic_str in ["cc0", "pdm", "publicdomain", "public-domain"]:
		lic_id = "cc0-1.0"
		lic_name = "Creative Commons Zero (CC0 1.0)"
		lic_url = "https://creativecommons.org/publicdomain/zero/1.0/"
		attr_req = false
	elif "by-nc" in lic_str or "nc" in lic_str:
		lic_id = "cc-by-nc-4.0"
		lic_name = "Creative Commons Attribution NonCommercial %s" % lic_ver
		lic_url = "https://creativecommons.org/licenses/by-nc/%s/" % (lic_ver if not lic_ver.is_empty() else "4.0")
		attr_req = true
	elif "by" in lic_str:
		lic_id = "cc-by-4.0"
		lic_name = "Creative Commons Attribution %s" % (lic_ver if not lic_ver.is_empty() else "4.0")
		lic_url = "https://creativecommons.org/licenses/by/%s/" % (lic_ver if not lic_ver.is_empty() else "4.0")
		attr_req = true

	var lic_val := {
		"id": lic_id,
		"name": lic_name,
		"url": lic_url,
		"attribution_required": attr_req
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	if attr_req:
		asset.attribution_text = "\"%s\" by %s (%s) licensed under %s via Openverse" % [
			display_title, creator, asset.url, lic_name
		]
	else:
		asset.attribution_text = "\"%s\" by %s - Openverse (%s)" % [display_title, creator, lic_name]

	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	if asset.get("type", "image") == "audio":
		return [
			{
				"id": "audio",
				"label": "Original Audio File",
				"kind": "files",
				"confirmed": true
			},
			{
				"id": "stream",
				"label": "Audio Stream Preview",
				"kind": "files",
				"confirmed": true
			}
		]
	return [
		{
			"id": "orig",
			"label": "Original Full Resolution",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "preview",
			"label": "Image Preview",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category == "model":
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var page_size := 24
	var search_cat := "audio" if category == "audio" else "image"
	var resp: Dictionary = await client.search(query, search_cat, page, page_size)
	if resp.has("error"):
		return resp

	var results: Array = resp.get("results", [])
	var all_items: Array = []
	for r in results:
		if r is Dictionary:
			var norm: Dictionary = normalize(r, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total: int = int(resp.get("result_count", 0))
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

	var target_variant := variant if not variant.is_empty() else ("audio" if detailed.get("type") == "audio" else "orig")
	var download_url := ""
	var filename := ""

	if target_variant in ["preview", "stream"]:
		download_url = str(detailed.get("thumbnail", detailed.get("url", "")))
	else:
		download_url = str(detailed.get("url", detailed.get("thumbnail", "")))

	if download_url.is_empty():
		return {"error": "No download URL available for Openverse asset."}

	var ext := download_url.get_file().get_extension()
	if ext.is_empty() or ext.contains("?"):
		ext = "ogg" if detailed.get("type") == "audio" else "jpg"
	filename = "%s_%s.%s" % [str(detailed.get("id", "openverse")), target_variant, ext]

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
