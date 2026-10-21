@tool
extends "res://addons/3dtexel/core/provider.gd"
## NYPL Digital Collections provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/nypl/client.gd")
const Cache = preload("res://addons/3dtexel/providers/nypl/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "nypl",
		"name": "NYPL Digital Collections",
		"website": "https://digitalcollections.nypl.org/",
		"key_env": ["NYPL_API_TOKEN"],
		"capabilities": ["image", "material", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	return OS.get_environment("NYPL_API_TOKEN")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API token configured."
	return "Free token available from NYPL. Set NYPL_API_TOKEN to search live API."

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
	var id := str(raw.get("imageID", raw.get("id", "")))
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "nypl"
	asset.provider = "NYPL Digital Collections"
	asset.id = clean_id
	asset.type = "image"

	var display_name := str(raw.get("title", clean_id.capitalize()))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://digitalcollections.nypl.org/items/" + str(raw.get("digitalUUID", id))))
	asset.thumbnail = str(raw.get("thumbnail", "https://images.nypl.org/index.php?id=" + id + "&t=b"))
	asset.description = str(raw.get("description", asset.get("description", "%s at New York Public Library" % display_name)))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var creator := str(raw.get("creator", "The New York Public Library"))
	asset.authors = [{"name": creator, "url": "https://digitalcollections.nypl.org"}]

	var lic_val := {
		"id": "public-domain",
		"name": "No Copyright - United States (Public Domain)",
		"url": "http://rightsstatements.org/vocab/NoC-US/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s by %s - The New York Public Library (Public Domain)" % [display_name, creator]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	return [
		{
			"id": "highres",
			"label": "High-Resolution Image",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "thumbnail",
			"label": "Preview Thumbnail",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var resp: Dictionary = await client.search(query, page)
	if resp.has("error"):
		return resp

	var api_obj: Dictionary = resp.get("nyplAPI", {})
	var resp_obj: Dictionary = api_obj.get("response", {})
	var results: Array = resp_obj.get("result", [])
	if results.is_empty() and resp.has("items") and resp.items is Array:
		results = resp.items

	var items: Array[Dictionary] = []
	for raw in results:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if category == "material":
			normalized.type = "material"
		client.cache.put_asset(normalized)
		items.append(normalized)

	var next_cur := str(page + 1) if results.size() >= 30 else ""
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
	var raw_id := str(meta.get("imageID", detailed.id))

	var dl_url := ""
	if variant == "thumbnail":
		dl_url = str(meta.get("thumbnail", "https://images.nypl.org/index.php?id=" + raw_id + "&t=b"))
	else:
		dl_url = str(meta.get("highResLink", "https://images.nypl.org/index.php?id=" + raw_id + "&t=w"))

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
	return await client.search("", 1)

func cancel_all() -> void:
	client.cancel_all()
