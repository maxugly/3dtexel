@tool
extends "res://addons/3dtexel/core/provider.gd"
## Rijksmuseum Amsterdam provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/rijksmuseum/client.gd")
const Cache = preload("res://addons/3dtexel/providers/rijksmuseum/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "rijksmuseum",
		"name": "Rijksmuseum",
		"website": "https://www.rijksmuseum.nl/en/collection",
		"key_env": ["RIJKSMUSEUM_API_KEY"],
		"capabilities": ["image", "material", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	return OS.get_environment("RIJKSMUSEUM_API_KEY")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "No key required (using public demo access). Set RIJKSMUSEUM_API_KEY for personal key."

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
	var id := str(raw.get("objectNumber", raw.get("id", "")))
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "rijksmuseum"
	asset.provider = "Rijksmuseum"
	asset.id = clean_id
	asset.type = "image"

	var display_name := str(raw.get("title", clean_id.capitalize()))
	asset.title = display_name

	var links: Dictionary = raw.get("links", {})
	asset.url = str(links.get("web", "https://www.rijksmuseum.nl/en/collection/" + id))

	var web_img: Dictionary = raw.get("webImage", {})
	var header_img: Dictionary = raw.get("headerImage", {})
	var thumb := str(header_img.get("url", web_img.get("url", "")))
	asset.thumbnail = thumb

	var long_title := str(raw.get("longTitle", "%s at Rijksmuseum" % display_name))
	asset.description = long_title

	var maker := str(raw.get("principalOrFirstMaker", "Rijksmuseum"))
	asset.authors = [{"name": maker, "url": "https://www.rijksmuseum.nl"}]
	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "cc0",
		"name": "Creative Commons CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s - Rijksmuseum Amsterdam (CC0)" % [display_name, maker]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var meta: Dictionary = asset.get("source_metadata", {})
	var web_img: Dictionary = meta.get("webImage", asset.get("webImage", {}))
	var result := []

	if not web_img.is_empty():
		var w := int(web_img.get("width", 0))
		var h := int(web_img.get("height", 0))
		var label := "Full Resolution"
		if w > 0 and h > 0:
			label = "Full Resolution (%dx%d)" % [w, h]
		result.append({
			"id": "full",
			"label": label,
			"kind": "files",
			"confirmed": true
		})

	result.append({
		"id": "preview",
		"label": "Web Preview",
		"kind": "files",
		"confirmed": true
	})

	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var page_size := 30
	var resp: Dictionary = await client.search(query, page, page_size)
	if resp.has("error"):
		return resp

	var all_artworks: Array = []
	if resp.has("artObjects") and resp.artObjects is Array:
		all_artworks = resp.artObjects
	elif resp.has("items") and resp.items is Array:
		all_artworks = resp.items

	var items: Array[Dictionary] = []
	for raw in all_artworks:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if category == "material":
			normalized.type = "material"
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_cur := str(page + 1) if all_artworks.size() >= page_size else ""
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

	var meta: Dictionary = detailed.get("source_metadata", {})
	var web_img: Dictionary = meta.get("webImage", detailed.get("webImage", {}))
	var header_img: Dictionary = meta.get("headerImage", detailed.get("headerImage", {}))

	var dl_url := ""
	if variant == "preview" and not header_img.is_empty():
		dl_url = str(header_img.get("url", ""))
	elif not web_img.is_empty():
		dl_url = str(web_img.get("url", ""))

	if dl_url.is_empty() and not header_img.is_empty():
		dl_url = str(header_img.get("url", ""))

	if dl_url.is_empty():
		return {"error": "No image URL found for Rijksmuseum artwork %s." % detailed.id}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var filename := "%s.jpg" % Importer.slug(str(detailed.id))

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
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.search("", 1, 1)

func cancel_all() -> void:
	client.cancel_all()
