@tool
extends "res://addons/3dtexel/core/provider.gd"
## 3DTextures.me PBR materials provider adapter.

const Client = preload("res://addons/3dtexel/providers/textures3d/client.gd")
const Cache = preload("res://addons/3dtexel/providers/textures3d/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "textures3d",
		"name": "3DTextures.me",
		"website": "https://3dtextures.me/",
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

func extract_text(html: String) -> String:
	var regex := RegEx.create_from_string("<[^>]*>")
	return regex.sub(html, " ", true).strip_edges()

func extract_maps(html: String) -> Dictionary:
	var maps := {}
	var regex := RegEx.create_from_string("href=[\"'](https?://[^\"']+\\.(?:jpg|png|jpeg))[\"']")
	for match_obj in regex.search_all(html):
		var url: String = match_obj.get_string(1)
		var lower := url.to_lower()
		if lower.contains("basecolor") or lower.contains("diffuse") or lower.contains("color"):
			maps["albedo"] = url
		elif lower.contains("normal"):
			maps["normal"] = url
		elif lower.contains("roughness") or lower.contains("rough"):
			maps["roughness"] = url
		elif lower.contains("height") or lower.contains("displacement") or lower.contains("disp"):
			maps["height"] = url
		elif lower.contains("ambientocclusion") or lower.contains("ao"):
			maps["ao"] = url
		elif lower.contains("metallic") or lower.contains("metal"):
			maps["metallic"] = url
	return maps

func normalize(raw: Dictionary, fetched := false) -> Dictionary:
	var id := str(raw.get("slug", raw.get("id", "")))
	id = Importer.slug(id)
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "textures3d"
	asset.provider = "3DTextures.me"
	asset.id = id
	asset.type = "material"

	var title_str := ""
	var title_val: Variant = raw.get("title", asset.get("title", id))
	if title_val is Dictionary:
		title_str = str(title_val.get("rendered", id))
	else:
		title_str = str(title_val)
	title_str = extract_text(title_str)
	asset.title = title_str

	asset.url = str(raw.get("link", raw.get("url", "https://3dtextures.me/" + id)))
	asset.thumbnail = str(raw.get("jetpack_featured_media_url", asset.get("thumbnail", "")))

	var content_html := ""
	var content_val: Variant = raw.get("content", asset.get("content", {}))
	if content_val is Dictionary:
		content_html = str(content_val.get("rendered", ""))
	elif content_val is String:
		content_html = content_val
	asset.description = extract_text(content_html)
	asset.price = {"free": true, "credits": 0}

	asset.authors = [{"name": "3DTextures.me", "url": "https://3dtextures.me"}]

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "Texture '%s' from 3DTextures.me (CC0)" % title_str
	asset.metadata_source_url = asset.url

	if not content_html.is_empty():
		asset.maps = extract_maps(content_html)

	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	return [
		{
			"id": "2k",
			"label": "2K PBR Maps",
			"confirmed": true,
			"kind": "material",
			"resolution": "2k"
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["model", "audio", "image"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() else 1
	if page < 1:
		page = 1
	var per_page := 30

	var resp: Dictionary = await client.fetch_posts(query, page, per_page)
	if resp.has("error"):
		return resp

	var all_posts: Array = []
	if resp.has("items") and resp.items is Array:
		all_posts = resp.items
	elif resp.get("data") is Array:
		all_posts = resp.data

	var items: Array[Dictionary] = []
	for raw in all_posts:
		if raw is Dictionary:
			var normalized := normalize(raw, true)
			client.cache.put_asset(normalized, false)
			items.append(normalized)

	var next_cur := str(page + 1) if (all_posts.size() >= per_page) else ""
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

	var maps: Dictionary = detailed.get("maps", {})
	if maps.is_empty():
		return {"error": "No PBR texture maps found for asset %s." % str(detailed.id)}

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
	return await client.fetch_posts("", 1, 1)

func cancel_all() -> void:
	client.cancel_all()
