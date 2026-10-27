@tool
extends "res://addons/3dtexel/core/provider.gd"
## Rawpixel Public Domain provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/rawpixel/client.gd")
const Cache = preload("res://addons/3dtexel/providers/rawpixel/cache.gd")
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
		"id": "rawpixel",
		"name": "Rawpixel Public Domain",
		"website": "https://www.rawpixel.com/public-domain",
		"key_env": [],
		"capabilities": ["image", "material", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing

## This site cannot be queried from here, so it stays out of the default sweep
## and says why. A user can still turn it on from the site list.
func default_enabled() -> bool:return false
func disabled_reason() -> String:return "The host rejects automated requests from this network (HTTP 403)."

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
	var raw_id: Variant = raw.get("id", raw.get("image_id", raw.get("nid", "")))
	var id_str := str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id_str)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "rawpixel"
	asset.provider = "Rawpixel Public Domain"
	asset.id = clean_id
	asset.type = "image"

	var display_title := str(raw.get("image_title", raw.get("title", "")))
	if display_title.is_empty():
		display_title = "Rawpixel CC0 Artwork %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", raw.get("web_url", "https://www.rawpixel.com/image/%s" % id_str)))

	# Thumbnail
	var thumb_url := str(raw.get("image_thumbnail", raw.get("thumbnail", "")))
	if thumb_url.is_empty() and raw.has("image_opengraph"):
		thumb_url = str(raw.image_opengraph)
	if thumb_url.is_empty() and raw.has("image_uri"):
		thumb_url = str(raw.image_uri)
	asset.thumbnail = thumb_url

	var desc := str(raw.get("image_alt", raw.get("description", "")))
	if desc.is_empty():
		var artist := str(raw.get("artist", raw.get("creator", "")))
		desc = "%s%s - Public domain digital restoration from Rawpixel." % [
			display_title,
			" by %s" % artist if not artist.is_empty() else ""
		]
	asset.description = desc

	var author_name := str(raw.get("artist", raw.get("creator", raw.get("source_institution", "Rawpixel Public Domain Archive"))))
	if author_name.is_empty():
		author_name = "Rawpixel Public Domain Archive"
	asset.authors = [{"name": author_name, "url": "https://www.rawpixel.com/public-domain"}]

	var tags := []
	if raw.has("keywords_raw"):
		var kw: Variant = raw.keywords_raw
		if kw is String:
			for t in kw.split(",", false):
				tags.append(t.strip_edges())
		elif kw is Array:
			tags = kw
	elif raw.has("tags") and raw.tags is Array:
		tags = raw.tags
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

	asset.attribution_text = "%s - %s (Rawpixel / CC0)" % [display_title, author_name]
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

	var results: Array = resp.get("results", [])
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
