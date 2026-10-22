@tool
extends "res://addons/3dtexel/core/provider.gd"
## USDA Pomological Watercolors provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/usda_watercolors/client.gd")
const Cache = preload("res://addons/3dtexel/providers/usda_watercolors/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "usda_watercolors",
		"name": "USDA Pomological Watercolors",
		"website": "https://usdawatercolors.nal.usda.gov/",
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
	var raw_id: Variant = raw.get("id", "")
	var id_str := str(int(raw_id)) if (raw_id is float or raw_id is int) else str(raw_id)
	var clean_id := Importer.slug(id_str)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "usda_watercolors"
	asset.provider = "USDA Pomological Watercolors"
	asset.id = clean_id
	asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "USDA Pomological Watercolor %s" % id_str
	asset.title = display_title

	asset.url = "https://usdawatercolors.nal.usda.gov/pom/download.xhtml?id=%s" % id_str

	var thumb_url := str(raw.get("thumbnail_url", raw.get("thumbnail", "")))
	asset.thumbnail = thumb_url

	var desc := str(raw.get("specimen_notes", raw.get("description", "")))
	if desc.is_empty():
		var sci := str(raw.get("scientific_name", ""))
		var com := str(raw.get("common_name", ""))
		desc = "%s (%s) - Watercolor illustration from USDA Pomological Watercolor Collection." % [display_title, sci if not sci.is_empty() else com]
	asset.description = desc

	var artist_name := str(raw.get("artist", "USDA Pomological Watercolor Artists"))
	asset.authors = [{"name": artist_name, "url": "https://usdawatercolors.nal.usda.gov/"}]

	var tags := []
	for k in ["common_name", "scientific_name", "geographic_origin"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain (US Government Work)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (USDA National Agricultural Library / Public Domain)" % [display_title, artist_name]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	return [
		{
			"id": "full",
			"label": "Original Maximum Resolution",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "2048",
			"label": "2048px Resolution",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "1024",
			"label": "1024px Resolution",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "thumb",
			"label": "512px Thumbnail",
			"kind": "files",
			"confirmed": true
		}
	]

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
	return asset

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var target_variant := variant if not variant.is_empty() else "full"
	var src: Dictionary = detailed.get("source_metadata", {})
	if src.is_empty():
		src = detailed

	var download_url := ""
	if src.has("iiif_base") and not str(src.iiif_base).is_empty():
		var iiif_base := str(src.iiif_base)
		var size_spec := "full/max/0/default.jpg"
		match target_variant:
			"2048":
				size_spec = "full/2048,/0/default.jpg"
			"1024":
				size_spec = "full/1024,/0/default.jpg"
			"thumb":
				size_spec = "full/512,/0/default.jpg"
			_:
				size_spec = "full/max/0/default.jpg"
		download_url = "%s/%s" % [iiif_base, size_spec]
	elif src.has("image_url") and not str(src.image_url).is_empty():
		download_url = str(src.image_url)
	else:
		download_url = str(detailed.get("thumbnail", ""))

	if download_url.is_empty():
		return {"error": "No download URL available for USDA Pomological Watercolor."}

	var ext := download_url.get_file().get_extension()
	if ext.is_empty() or ext.contains("?"):
		ext = "jpg"

	var clean_id: String = str(detailed.get("id", "watercolor"))
	var filename := "%s_%s.%s" % [clean_id, target_variant, ext]

	return {
		"kind": "files",
		"asset": detailed,
		"variant": target_variant,
		"files": [
			{
				"filename": filename,
				"url": download_url
			}
		]
	}

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	return await client.get_bytes(url, destination, limit)

func thumbnail(url: String) -> Texture2D:
	return null

func cancel_all() -> void:
	client.cancel_all()
