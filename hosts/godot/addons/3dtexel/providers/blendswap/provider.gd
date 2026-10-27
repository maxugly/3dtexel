@tool
extends "res://addons/3dtexel/core/provider.gd"
## Blend Swap community 3D models provider adapter.

const Client = preload("res://addons/3dtexel/providers/blendswap/client.gd")
const Cache = preload("res://addons/3dtexel/providers/blendswap/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "blendswap",
		"name": "Blend Swap",
		"website": "https://blendswap.com/",
		"key_env": ["BLENDSWAP_KEY", "BLENDSWAP_API_KEY"],
		"capabilities": ["model", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

func default_enabled() -> bool:
	return true

func disabled_reason() -> String:
	return "Unchecked by default. Turn on to browse or download Blend Swap models."

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	var env_key := OS.get_environment("BLENDSWAP_KEY")
	if not env_key.is_empty():
		return env_key
	return OS.get_environment("BLENDSWAP_API_KEY")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "Public browse mode. Set BLENDSWAP_KEY or BLENDSWAP_API_KEY for official API downloads."

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
	var raw_id: Variant = raw.get("id", raw.get("slug", "asset"))
	var id_str := str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id_str)
	if clean_id.is_empty():
		clean_id = "blendswap_asset"

	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "blendswap"
	asset.provider = "Blend Swap"
	asset.id = clean_id
	asset.type = "model"

	var display_title := str(raw.get("title", clean_id.capitalize()))
	asset.title = display_title
	asset.url = str(raw.get("url", "https://blendswap.com/blend/" + clean_id))
	asset.thumbnail = str(raw.get("thumbnail_url", raw.get("thumbnail", "")))

	var author_data: Variant = raw.get("author", {})
	var author_name := "Blend Swap Artist"
	var author_url := "https://blendswap.com"
	if author_data is Dictionary:
		author_name = str(author_data.get("username", author_data.get("name", "Blend Swap Artist")))
		author_url = str(author_data.get("url", "https://blendswap.com"))
	elif author_data is String and not author_data.is_empty():
		author_name = author_data
	asset.authors = [{"name": author_name, "url": author_url}]

	var desc := str(raw.get("description", "%s on Blend Swap" % display_title))
	asset.description = desc

	var tags := []
	if raw.has("tags") and raw.tags is Array:
		tags.append_array(raw.tags)
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	# License parsing
	var lic_key := ""
	if raw.get("license") is Dictionary:
		lic_key = str(raw.license.get("key", raw.license.get("id", raw.license.get("name", "")))).to_lower()
	else:
		lic_key = str(raw.get("license", "cc-by")).to_lower()

	var lic_val := {}
	if lic_key.contains("cc0") or lic_key.contains("cc-0") or lic_key.contains("zero") or lic_key.contains("public"):
		lic_val = {
			"id": "cc0",
			"name": "Creative Commons CC0 1.0 Universal",
			"url": "https://creativecommons.org/publicdomain/zero/1.0/",
			"attribution_required": false
		}
	elif lic_key.contains("nc"):
		lic_val = {
			"id": "cc-by-nc-4.0",
			"name": "Creative Commons Attribution-NonCommercial 4.0 International",
			"url": "https://creativecommons.org/licenses/by-nc/4.0/",
			"attribution_required": true
		}
	elif lic_key.contains("sa"):
		lic_val = {
			"id": "cc-by-sa-4.0",
			"name": "Creative Commons Attribution-ShareAlike 4.0 International",
			"url": "https://creativecommons.org/licenses/by-sa/4.0/",
			"attribution_required": true
		}
	else:
		lic_val = {
			"id": "cc-by-4.0",
			"name": "Creative Commons Attribution 4.0 International",
			"url": "https://creativecommons.org/licenses/by/4.0/",
			"attribution_required": true
		}

	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s via Blend Swap (%s)" % [display_title, author_name, lic_val.name]
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
	if not files.is_empty():
		for f in files:
			if not (f is Dictionary):
				continue
			var fid := str(f.get("id", ""))
			var vid := "file_" + Importer.slug(fid) if not fid.is_empty() and files.size() > 1 else "blend"
			var fname := str(f.get("filename", "model.blend"))
			var size_bytes := int(f.get("size_bytes", f.get("size", 0)))
			var size_label := " (%s)" % String.humanize_size(size_bytes) if size_bytes > 0 else ""
			var label := "%s%s" % [fname, size_label]
			result.append({
				"id": vid,
				"file_id": fid,
				"label": label,
				"confirmed": true,
				"kind": "files"
			})
	if result.is_empty():
		result.append({
			"id": "blend",
			"label": "Blender .blend Model",
			"confirmed": true,
			"kind": "files"
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "image", "material"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var limit := 25
	var resp: Dictionary = await client.search(query, page, limit)
	if resp.has("error"):
		return resp

	var raw_items: Array = []
	if resp.has("data") and resp.data is Array:
		raw_items = resp.data
	elif resp.has("results") and resp.results is Array:
		raw_items = resp.results
	elif resp.has("items") and resp.items is Array:
		raw_items = resp.items

	var items: Array[Dictionary] = []
	for raw in raw_items:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_cur := str(page + 1) if raw_items.size() >= limit else ""
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

	if int(Policy.evaluate(detailed).status) == Policy.Status.BLOCKED:
		return {"error": "Asset is blocked by project license policy."}

	var meta: Dictionary = detailed.get("source_metadata", {})
	var raw_id: int = int(detailed.get("raw_id", meta.get("id", detailed.id)))

	# Find file_id if specified in variant
	var file_id := 0
	var vars := variants(detailed)
	for v in vars:
		if v.get("id") == variant and v.has("file_id"):
			file_id = int(v.file_id)
			break

	var download_url := ""
	var filename := "%s.blend" % Importer.slug(str(detailed.id))

	var candidate_files: Array = detailed.get("files", meta.get("files", []))
	for f in candidate_files:
		if f is Dictionary:
			var fid := str(f.get("id", ""))
			var vid := "file_" + Importer.slug(fid) if not fid.is_empty() and candidate_files.size() > 1 else "blend"
			if vid == variant or candidate_files.size() == 1:
				var fname := str(f.get("filename", ""))
				if not fname.is_empty():
					filename = Importer.slug(fname.get_basename()) + "." + fname.get_extension()
					break

	# If API key configured, use the official downloads endpoint
	if not client.api_token.is_empty() and raw_id > 0:
		var dl_resp: Dictionary = await client.get_download(raw_id, file_id)
		if dl_resp.has("error"):
			return dl_resp
		download_url = str(dl_resp.get("download_url", ""))
		if dl_resp.has("file") and dl_resp.file is Dictionary:
			var fname := str(dl_resp.file.get("filename", ""))
			if not fname.is_empty():
				filename = Importer.slug(fname.get_basename()) + "." + fname.get_extension()

	# Fallback to direct download URL in asset metadata or fixture
	if download_url.is_empty():
		download_url = str(detailed.get("download_url", detailed.get("download", meta.get("download_url", meta.get("download", "")))))

	if download_url.is_empty():
		return {"error": "No download URL available for %s." % detailed.get("title", detailed.id)}

	if not download_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % download_url}

	return {
		"kind": "files",
		"asset": detailed,
		"variant": variant,
		"files": [
			{
				"filename": filename,
				"url": download_url
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
	if not network_allowed:
		return {"error": "Connection checks require explicit action."}
	sync_network()
	return await client.search("", 1, 1)

func cancel_all() -> void:
	client.cancel_all()
