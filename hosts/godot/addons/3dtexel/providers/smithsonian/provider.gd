@tool
extends "res://addons/3dtexel/core/provider.gd"
## Smithsonian Open Access & 3D provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/smithsonian/client.gd")
const Cache = preload("res://addons/3dtexel/providers/smithsonian/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "smithsonian",
		"name": "Smithsonian Open Access & 3D",
		"website": "https://3d.si.edu/",
		"key_env": ["SMITHSONIAN_API_KEY"],
		"capabilities": ["model", "image", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

## This site cannot be queried from here, so it stays out of the default sweep
## and says why. A user can still turn it on from the site list.
func default_enabled() -> bool:return false
func disabled_reason() -> String:return "The host rejects automated requests from this network (HTTP 403)."

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	return OS.get_environment("SMITHSONIAN_API_KEY")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "No key required for basic access. Set SMITHSONIAN_API_KEY for higher rate limits."

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
	var raw_id := str(raw.get("id", ""))
	var clean_id := Importer.slug(raw_id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "smithsonian"
	asset.provider = "Smithsonian Open Access & 3D"
	asset.id = clean_id

	var content: Dictionary = raw.get("content", {})
	var dnr: Dictionary = content.get("descriptiveNonRepeating", {})
	var title_obj = dnr.get("title", {})
	var title_str := ""
	if title_obj is Dictionary:
		title_str = str(title_obj.get("content", ""))
	if title_str.is_empty():
		title_str = str(raw.get("title", clean_id.capitalize()))
	asset.title = title_str

	asset.url = str(dnr.get("record_link", "https://3d.si.edu/object/3d/" + clean_id))

	# Media parsing
	var online_media: Dictionary = dnr.get("online_media", {})
	var media_list: Array = online_media.get("media", [])
	var thumb := ""
	var files: Array[Dictionary] = []
	var is_3d := false

	for m in media_list:
		if not (m is Dictionary):
			continue
		var m_dict: Dictionary = m
		var m_type := str(m_dict.get("type", "")).to_lower()
		var m_fmt := str(m_dict.get("format", "")).to_upper()
		var m_url := str(m_dict.get("content", ""))
		var m_thumb := str(m_dict.get("thumbnail", ""))

		if thumb.is_empty() and not m_thumb.is_empty():
			thumb = m_thumb

		if m_type.contains("3d") or m_fmt in ["GLB", "OBJ", "STL", "GLTF"]:
			is_3d = true

		if not m_url.is_empty():
			var fname := m_url.get_file().get_slice("?", 0)
			if fname.is_empty():
				fname = "%s_%s.%s" % [clean_id, m_fmt.to_lower(), m_fmt.to_lower()]
			var vid := Importer.slug(fname.get_basename())
			files.append({
				"filename": fname,
				"variant_id": vid,
				"format": m_fmt,
				"label": "%s (%s)" % [m_fmt, m_type.capitalize() if not m_type.is_empty() else "Asset"],
				"url": m_url
			})

	asset.thumbnail = thumb
	asset.files = files
	asset.type = "model" if is_3d else str(raw.get("type", "image"))

	# Description & DataSource
	var desc := ""
	var data_source := "Smithsonian Institution"
	var freetext: Dictionary = content.get("freetext", {})
	for note in freetext.get("notes", []):
		if note is Dictionary and str(note.get("label", "")) == "Description":
			desc = str(note.get("content", ""))
			break
	for ds in freetext.get("dataSource", []):
		if ds is Dictionary and str(ds.get("label", "")) == "Data Source":
			data_source = str(ds.get("content", "Smithsonian Institution"))
			break

	asset.description = desc if not desc.is_empty() else "%s by %s" % [title_str, data_source]
	asset.authors = [{"name": data_source, "url": "https://www.si.edu"}]
	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons Zero (CC0 1.0)",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (Smithsonian Open Access / CC0)" % [title_str, data_source]
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
			"label": str(f_dict.get("label", fname)),
			"kind": "files",
			"confirmed": true,
			"filter_key": "format:" + fmt.to_lower(),
			"filter_label": fmt
		})

	if result.is_empty():
		result.append({
			"id": "glb",
			"label": "GLB 3D Model",
			"kind": "files",
			"confirmed": true
		})

	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "material"]:
		return {"items": [], "next_cursor": ""}

	var start := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
	var rows := 30
	var resp: Dictionary = await client.search(query, start, rows)
	if resp.has("error"):
		return resp

	var response_obj: Dictionary = resp.get("response", {})
	var raw_rows: Array = response_obj.get("rows", [])
	if raw_rows.is_empty() and resp.has("items") and resp.items is Array:
		raw_rows = resp.items

	var items: Array[Dictionary] = []
	for raw in raw_rows:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if not category.is_empty() and category != "all" and normalized.type != category:
			continue
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_cur := str(start + rows) if raw_rows.size() >= rows else ""
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
		return {"error": "Variant '%s' not found for Smithsonian asset." % variant}

	var dl_url := str(chosen_file.get("url", ""))
	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	return {
		"kind": "files",
		"asset": detailed,
		"variant": variant,
		"files": [
			{
				"filename": str(chosen_file.get("filename", "smithsonian_asset")),
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
	return await client.search("3d", 0, 1)

func cancel_all() -> void:
	client.cancel_all()
