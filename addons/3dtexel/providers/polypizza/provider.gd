@tool
extends "res://addons/3dtexel/core/provider.gd"
## Poly Pizza low-poly 3D models provider adapter with free API key authentication.

const Client = preload("res://addons/3dtexel/providers/polypizza/client.gd")
const Cache = preload("res://addons/3dtexel/providers/polypizza/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "polypizza",
		"name": "Poly Pizza",
		"website": "https://poly.pizza/",
		"key_env": ["POLYPIZZA_API_KEY"],
		"capabilities": ["model", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	return OS.get_environment("POLYPIZZA_API_KEY")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "Free API key required for live search. Set POLYPIZZA_API_KEY."

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
	var id := str(raw.get("ID", raw.get("id", "")))
	id = Importer.slug(id)
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "polypizza"
	asset.provider = "Poly Pizza"
	asset.id = id
	asset.type = "model"

	var display_name := str(raw.get("Title", raw.get("title", id.capitalize())))
	asset.title = display_name
	asset.url = str(raw.get("Url", raw.get("url", "https://poly.pizza/m/" + id)))
	asset.thumbnail = str(raw.get("Thumbnail", raw.get("thumbnail", "")))
	asset.description = str(raw.get("Description", asset.get("description", "%s on Poly Pizza" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var author_name := str(raw.get("Author", raw.get("author", "Poly Pizza")))
	asset.authors = [{"name": author_name, "url": "https://poly.pizza"}]

	var raw_lic := str(raw.get("License", raw.get("license", "CC0"))).to_upper()
	var is_cc0 := raw_lic.contains("CC0") or raw_lic.contains("ZERO")
	var lic_val := {
		"id": "cc0" if is_cc0 else "cc-by-3.0",
		"name": "Creative Commons CC0 1.0 Universal" if is_cc0 else "Creative Commons Attribution 3.0",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/" if is_cc0 else "https://creativecommons.org/licenses/by/3.0/",
		"attribution_required": not is_cc0
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s via Poly Pizza (%s)" % [display_name, author_name, lic_val.name]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var meta: Dictionary = asset.get("source_metadata", {})
	var tri_count: int = int(meta.get("Tri Count", meta.get("tri_count", asset.get("Tri Count", asset.get("tri_count", 0)))))
	var tri_label := " (%d tris)" % tri_count if tri_count > 0 else ""
	return [
		{
			"id": "glb",
			"label": "GLB Model" + tri_label,
			"confirmed": true,
			"kind": "files"
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "image", "material"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var limit := 30
	var resp: Dictionary = await client.search(query, page, limit)
	if resp.has("error"):
		return resp

	var all_models: Array = []
	if resp.has("results") and resp.results is Array:
		all_models = resp.results
	elif resp.has("items") and resp.items is Array:
		all_models = resp.items

	var items: Array[Dictionary] = []
	for raw in all_models:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		client.cache.put_asset(normalized)
		items.append(normalized)

	var next_cur := str(page + 1) if all_models.size() >= limit else ""
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
	var dl_url := str(detailed.get("Download", detailed.get("download_url", meta.get("Download", meta.get("download_url", "")))))

	if dl_url.is_empty():
		return {"error": "No download URL available for %s." % detailed.get("title", detailed.id)}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var filename := "%s.glb" % Importer.slug(str(detailed.id))

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
	return await client.search("", 1, 1)

func cancel_all() -> void:
	client.cancel_all()
