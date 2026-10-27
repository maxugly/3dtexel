@tool
extends "res://addons/3dtexel/core/provider.gd"
## Los Angeles County Museum of Art provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/lacma/client.gd")
const Cache = preload("res://addons/3dtexel/providers/lacma/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Files = preload("res://addons/3dtexel/core/reported_files.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "lacma",
		"name": "Los Angeles County Museum of Art",
		"website": "https://collections.lacma.org/",
		"key_env": [],
		"capabilities": ["image", "material", "files", "variants"]
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
	var raw_id: Variant = raw.get("id", raw.get("nid", ""))
	var id_str := str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id_str)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "lacma"
	asset.provider = "Los Angeles County Museum of Art"
	asset.id = clean_id
	asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "LACMA Artwork %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", "https://collections.lacma.org/node/%s" % id_str))
	asset.thumbnail = str(raw.get("thumbnail", raw.get("primary_image_thumb", "")))

	var artist := str(raw.get("artist", raw.get("maker", "Unknown Artist")))
	var date_str := str(raw.get("date", raw.get("dated", "")))
	var medium := str(raw.get("medium", ""))
	var department := str(raw.get("department", "Art Collection"))

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var parts := [display_title]
		if not artist.is_empty() and artist != "Unknown Artist":
			parts.append("by %s" % artist)
		if not date_str.is_empty():
			parts.append("(%s)" % date_str)
		if not medium.is_empty():
			parts.append("- %s" % medium)
		parts.append("[LACMA - %s]" % department)
		desc = " ".join(parts)
	asset.description = desc

	asset.authors = [{"name": artist, "url": "https://collections.lacma.org/"}]

	var tags := []
	for k in ["department", "medium", "culture", "classification"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	if raw.has("tags") and raw.tags is Array:
		tags.append_array(raw.tags)
	asset.tags = tags

	asset.price = raw.get("price",{"free":true,"credits":0})

	var lic_val := {
		"id": "cc0-1.0",
		"name": "Creative Commons Zero (CC0 1.0)",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	if raw.has("license"):lic_val=SourceLicense.record(raw.license,str(raw.get("license_version","")))
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (Los Angeles County Museum of Art, CC0 1.0 Universal)" % [display_title, artist]
	if raw.has("license"):
		var supplied := str(raw.get("attribution_text",""))
		var names: Array[String]=[]
		for person in asset.authors:
			if person is Dictionary and not str(person.get("name","")).is_empty():names.append(str(person.name))
		asset.attribution_text=supplied if not supplied.is_empty() else "%s — %s (%s)" % [asset.title,", ".join(names),asset.license.name]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw.get("source_metadata",raw))
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func file_offers(asset: Dictionary) -> Array:
	return Files.offers(asset,[["high_res_url","orig","Original Image"],["image_url","orig","Source Image"],["primary_image","orig","Source Image"],["image_uri","orig","Source Image"],["medium_res_url","2048","Medium Image"],["low_res_url","1024","Low Resolution Image"],["thumbnail","512","Image Preview"]])
func variants(asset: Dictionary) -> Array:
	return Files.variants(file_offers(asset))

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var page_size := 24
	var resp: Dictionary = await client.search(query, page, page_size)
	if resp.has("error"):
		return resp

	var results: Array = resp.get("data", resp.get("artworks", resp.get("results", [])))
	var all_items: Array = []
	for r in results:
		if r is Dictionary:
			var norm: Dictionary = normalize(r, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total: int = int(resp.get("total", 0))
	var next_cur := ""
	if page * page_size < total:
		next_cur = str(page + 1)

	return {
		"items": all_items,
		"next_cursor": next_cur
	}

func asset_details(asset: Dictionary) -> Dictionary:
	var cached: Dictionary=client.cache.asset(str(asset.id))
	if cached.is_empty():return asset
	return Cache.merge_asset(cached,asset)

func resolve_download(asset: Dictionary,variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	var detailed := await asset_details(asset)
	if detailed.has("error"):return detailed
	return Files.plan(detailed,variant,file_offers(detailed))

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	return await client.get_bytes(url, destination, limit)

func thumbnail(url: String) -> Texture2D:
	sync_network()
	return await client.thumbnail(url)

func cancel_all() -> void:
	client.cancel_all()

func check_connection() -> Dictionary:
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.search("",1,1)
