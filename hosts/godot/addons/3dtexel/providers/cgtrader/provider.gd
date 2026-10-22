@tool
extends "res://addons/3dtexel/core/provider.gd"
## CGTrader provider adapter with character focus and credential management.

const Client = preload("res://addons/3dtexel/providers/cgtrader/client.gd")
const Cache = preload("res://addons/3dtexel/providers/cgtrader/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "cgtrader",
		"name": "CGTrader",
		"website": "https://www.cgtrader.com/3d-models/character",
		"key_env": ["CGTRADER_API_TOKEN", "CGTRADER_CLIENT_ID"],
		"capabilities": ["files", "variants", "model"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

## The API only answers requests that carry a key, so the site stays out of
## the default sweep until a key is present.
func default_enabled() -> bool:return not api_key().is_empty()
func disabled_reason() -> String:return "The API needs a key: set CGTRADER_API_TOKEN or paste a session key."

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	return OS.get_environment("CGTRADER_API_TOKEN")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API token configured."
	return "No key configured. Set CGTRADER_API_TOKEN to download models."

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
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "cgtrader"
	asset.provider = "CGTrader"
	asset.id = id
	asset.type = "model"

	var display_name := str(raw.get("title", raw.get("name", id)))
	asset.title = display_name

	var slug := str(raw.get("slug", Importer.slug(display_name)))
	asset.url = str(raw.get("url", "https://www.cgtrader.com/3d-models/character/%s" % slug))
	asset.thumbnail = str(raw.get("thumbnail", asset.get("thumbnail", "")))
	asset.description = str(raw.get("description", asset.get("description", "")))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var username := "CGTrader Artist"
	var profile_url := "https://www.cgtrader.com"
	var user_val: Variant = raw.get("user", asset.get("user", {}))
	if user_val is Dictionary:
		username = str(user_val.get("username", username))
		profile_url = str(user_val.get("profile_url", profile_url))
	asset.authors = [{"name": username, "url": profile_url}]

	var lic_val := {
		"id": "royalty-free",
		"name": "CGTrader Royalty Free",
		"url": "https://www.cgtrader.com/pages/terms-and-conditions#royalty-free-license",
		"attribution_required": true
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "3D Model '%s' by %s via CGTrader" % [display_name, username]
	asset.metadata_source_url = "https://api.cgtrader.com/v1/models/" + id
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	if files.is_empty():
		return asset.get("variants", [])

	var poly_count := int(asset.get("polygons", 0))
	var result := []

	for f: Dictionary in files:
		var fmt := str(f.get("format", "")).to_lower()
		if fmt.is_empty():
			fmt = str(f.get("filename", "")).get_extension().to_lower()
		if fmt.is_empty():
			fmt = "obj"

		var vid := Importer.slug(fmt)
		var label := fmt.to_upper()
		if poly_count > 0:
			label += " (%d polys)" % poly_count

		result.append({
			"id": vid,
			"label": label,
			"format": fmt,
			"polygons": poly_count,
			"confirmed": true,
			"kind": "files"
		})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["material", "image", "audio"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() else 1
	if page < 1:
		page = 1

	# Category: Focus on character-people as prioritized
	var cat_param := "character-people"
	var resp: Dictionary = await client.search_models(query, cat_param, page, true)
	if resp.has("error"):
		return resp

	var raw_models: Array = []
	if resp.has("data") and resp.data is Array:
		raw_models = resp.data
	elif resp.has("items") and resp.items is Array:
		raw_models = resp.items

	var items: Array[Dictionary] = []
	for raw in raw_models:
		if raw is Dictionary:
			var normalized := normalize(raw, true)
			client.cache.put_asset(normalized)
			items.append(normalized)

	var total_found := int(resp.get("total", raw_models.size()))
	var per_page := int(resp.get("per_page", 30))
	var next_cur := str(page + 1) if (page * per_page < total_found) else ""
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	var id := str(asset.get("id", ""))
	if id.is_empty():
		return {"error": "Missing asset ID."}

	var detail: Dictionary = await client.fetch_model(id)
	if detail.has("error"):
		return normalize(asset, false)

	var normalized := normalize(detail, true)
	client.cache.put_asset(normalized)
	return normalized

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var target_slug := Importer.slug(variant)
	var matched_file: Dictionary = {}

	for f: Dictionary in files:
		var fmt := str(f.get("format", "")).to_lower()
		if Importer.slug(fmt) == target_slug:
			matched_file = f
			break

	if matched_file.is_empty() and not files.is_empty():
		matched_file = files[0]

	if matched_file.is_empty():
		return {"error": "No file found for variant %s." % variant}

	var dl_url := str(matched_file.get("download_url", matched_file.get("url", "")))
	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var ext := str(matched_file.get("format", "obj")).to_lower()
	var filename := "%s.%s" % [Importer.slug(str(detailed.id)), ext]

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
	return await client.search_models("", "character-people", 1, true)

func cancel_all() -> void:
	client.cancel_all()
