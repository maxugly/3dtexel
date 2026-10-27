@tool
extends "res://addons/3dtexel/core/provider.gd"
## NIH 3D Print Exchange provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/nih_3d/client.gd")
const Cache = preload("res://addons/3dtexel/providers/nih_3d/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "nih_3d",
		"name": "NIH 3D",
		"website": "https://3d.nih.gov/",
		"key_env": [],
		"capabilities": ["model", "files", "variants"]
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
	var id := str(raw.get("id", ""))
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "nih_3d"
	asset.provider = "NIH 3D"
	asset.id = clean_id
	asset.type = "model"

	var display_name := str(raw.get("title", clean_id.capitalize()))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://3d.nih.gov/entries/" + id))
	asset.thumbnail = str(raw.get("thumbnail", ""))
	asset.description = str(raw.get("description", asset.get("description", "%s from NIH 3D" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var author_name := str(raw.get("author", "National Institutes of Health (NIH)"))
	asset.authors = [{"name": author_name, "url": "https://3d.nih.gov"}]

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons Zero (CC0 / Public Domain)",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s via NIH 3D (Public Domain / CC0)" % [display_name, author_name]
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
		var vid := str(f_dict.get("variant_id", Importer.slug(fname.get_basename())))
		var fmt := str(f_dict.get("format", fname.get_extension())).to_upper()
		result.append({
			"id": vid,
			"label": "%s (%s)" % [vid.capitalize(), fmt],
			"kind": "files",
			"confirmed": true,
			"filter_key": "format:" + fmt.to_lower(),
			"filter_label": fmt
		})

	if result.is_empty():
		result.append({
			"id": "glb",
			"label": "GLB Model",
			"kind": "files",
			"confirmed": true
		})

	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "image", "material"]:
		return {"items": [], "next_cursor": ""}

	var resp: Dictionary = await client.fetch_entries(query)
	if resp.has("error"):
		return resp

	var all_entries: Array = []
	if resp.has("items") and resp.items is Array:
		all_entries = resp.items
	elif resp.get("data") is Array:
		all_entries = resp.data

	var q := query.strip_edges().to_lower()
	var matched: Array[Dictionary] = []

	for raw in all_entries:
		if not (raw is Dictionary):
			continue
		var raw_dict: Dictionary = raw
		if not q.is_empty():
			var title_str := str(raw_dict.get("title", "")).to_lower()
			var desc_str := str(raw_dict.get("description", "")).to_lower()
			var id_str := str(raw_dict.get("id", "")).to_lower()
			var is_match := title_str.contains(q) or desc_str.contains(q) or id_str.contains(q)
			if not is_match:
				for t in raw_dict.get("tags", []):
					if str(t).to_lower().contains(q):
						is_match = true
						break
			if not is_match:
				continue
		matched.append(raw_dict)

	var offset := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
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

	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var target_slug := Importer.slug(variant)
	var chosen_file: Dictionary = {}

	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		if str(f_dict.get("variant_id", "")) == target_slug or Importer.slug(str(f_dict.get("filename", "")).get_basename()) == target_slug:
			chosen_file = f_dict
			break

	if chosen_file.is_empty() and not files.is_empty() and files[0] is Dictionary:
		chosen_file = files[0]

	if chosen_file.is_empty():
		return {"error": "Variant '%s' not found for NIH 3D asset." % variant}

	var dl_url := str(chosen_file.get("url", ""))
	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	return {
		"kind": "files",
		"asset": detailed,
		"variant": variant,
		"files": [
			{
				"filename": str(chosen_file.get("filename", "nih_model.glb")),
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
	return await client.fetch_entries()

func cancel_all() -> void:
	client.cancel_all()
