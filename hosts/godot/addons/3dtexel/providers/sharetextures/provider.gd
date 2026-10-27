@tool
extends "res://addons/3dtexel/core/provider.gd"
## ShareTextures PBR materials provider adapter.

const Client = preload("res://addons/3dtexel/providers/sharetextures/client.gd")
const Cache = preload("res://addons/3dtexel/providers/sharetextures/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "sharetextures",
		"name": "ShareTextures",
		"website": "https://www.sharetextures.com/",
		"key_env": [],
		"capabilities": ["materials", "files", "variants", "material"]
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

	asset.provider_id = "sharetextures"
	asset.provider = "ShareTextures"
	asset.id = id
	asset.type = "material"

	var display_name := str(raw.get("name", raw.get("title", id.capitalize())))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://www.sharetextures.com/textures/" + id))
	asset.thumbnail = str(raw.get("thumbnail", ""))
	asset.description = str(raw.get("description", asset.get("description", "%s by ShareTextures" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	asset.authors = [{"name": "ShareTextures", "url": "https://www.sharetextures.com"}]

	var lic_val := {
		"id": "cc0",
		"name": "Custom CC0 (Commercial game use OK, no library redistribution)",
		"url": "https://www.sharetextures.com/license",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Texture '%s' from ShareTextures.com (Custom CC0)" % display_name
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var files: Dictionary = asset.get("files", {})
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", {})

	if files.is_empty():
		return [
			{"id": "1k", "label": "1K PBR Maps", "confirmed": true, "kind": "material", "resolution": "1k"},
			{"id": "2k", "label": "2K PBR Maps", "confirmed": true, "kind": "material", "resolution": "2k"}
		]

	var result := []
	var res_keys := files.keys()
	res_keys.sort()
	for r: String in res_keys:
		var vid := Importer.slug(r)
		result.append({
			"id": vid,
			"label": r.to_upper() + " PBR Maps",
			"confirmed": true,
			"kind": "material",
			"resolution": vid
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["model", "audio", "image"]:
		return {"items": [], "next_cursor": ""}

	var resp: Dictionary = await client.fetch_textures()
	if resp.has("error"):
		return resp

	var all_textures: Array = []
	if resp.has("items") and resp.items is Array:
		all_textures = resp.items
	elif resp.get("data") is Array:
		all_textures = resp.data

	var q := query.strip_edges().to_lower()
	var matched: Array[Dictionary] = []

	for raw in all_textures:
		if not (raw is Dictionary):
			continue
		var raw_dict: Dictionary = raw
		if not q.is_empty():
			var name_str := str(raw_dict.get("name", "")).to_lower()
			var desc_str := str(raw_dict.get("description", "")).to_lower()
			var id_str := str(raw_dict.get("id", "")).to_lower()
			var is_match := name_str.contains(q) or desc_str.contains(q) or id_str.contains(q)
			if not is_match:
				for t in raw_dict.get("tags", []):
					if str(t).to_lower().contains(q):
						is_match = true
						break
			if not is_match:
				continue
		matched.append(raw_dict)

	var offset := int(cursor) if not cursor.is_empty() else 0
	var page_size := 30
	var items: Array[Dictionary] = []

	var upper := mini(offset + page_size, matched.size())
	for i in range(offset, upper):
		var normalized := normalize(matched[i], true)
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_cur := str(offset + page_size) if (offset + page_size < matched.size()) else ""
	client.cache.save_catalog()
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

	var files: Dictionary = detailed.get("files", {})
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", {})

	var target_res := Importer.slug(variant)
	var chosen_files: Dictionary = files.get(target_res, {})
	if chosen_files.is_empty():
		for k in files:
			if Importer.slug(k) == target_res:
				chosen_files = files[k]
				break

	if chosen_files.is_empty() and not files.is_empty():
		chosen_files = files[files.keys()[0]]

	if chosen_files.is_empty():
		return {"error": "No textures found for variant %s." % variant}

	var maps := {}
	if chosen_files.has("diffuse"): maps["albedo"] = str(chosen_files.diffuse)
	elif chosen_files.has("basecolor"): maps["albedo"] = str(chosen_files.basecolor)

	if chosen_files.has("normal"): maps["normal"] = str(chosen_files.normal)
	if chosen_files.has("roughness"): maps["roughness"] = str(chosen_files.roughness)
	if chosen_files.has("displacement"): maps["height"] = str(chosen_files.displacement)
	if chosen_files.has("ao"): maps["ao"] = str(chosen_files.ao)
	if chosen_files.has("metallic"): maps["metallic"] = str(chosen_files.metallic)

	if maps.is_empty():
		return {"error": "Could not extract map URLs for variant %s." % variant}

	return {
		"kind": "material",
		"asset": detailed,
		"variant": variant,
		"maps": maps,
		"normal_format": "opengl",
		"material_props": {}
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
	return await client.fetch_textures()

func cancel_all() -> void:
	client.cancel_all()
