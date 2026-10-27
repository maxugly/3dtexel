@tool
extends "res://addons/3dtexel/core/provider.gd"
## David Rumsey Map Collection provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/david_rumsey/client.gd")
const Cache = preload("res://addons/3dtexel/providers/david_rumsey/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "david_rumsey",
		"name": "David Rumsey Map Collection",
		"website": "https://www.davidrumsey.com/",
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

	asset.provider_id = "david_rumsey"
	asset.provider = "David Rumsey Map Collection"
	asset.id = clean_id
	asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "Historical Map %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", "https://www.davidrumsey.com/luna/servlet/detail/%s" % id_str))

	var thumb_url := str(raw.get("thumbnail", ""))
	asset.thumbnail = thumb_url

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var author := str(raw.get("author", "Historical Cartographer"))
		var date := str(raw.get("date", "Undated"))
		desc = "%s (%s) by %s - David Rumsey Historical Map Collection." % [display_title, date, author]
	asset.description = desc

	var author_name := str(raw.get("author", "David Rumsey Map Collection"))
	asset.authors = [{"name": author_name, "url": "https://www.davidrumsey.com/"}]

	var tags := []
	for k in ["date", "publisher", "category"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	asset.tags = tags

	asset.price = raw.get("price",{"free":true,"credits":0})

	var lic_str := str(raw.get("license", "CC0")).to_upper()
	var lic_val: Dictionary
	if lic_str.contains("CC0") or lic_str.contains("PUBLIC"):
		lic_val = {
			"id": "cc0-1.0",
			"name": "Creative Commons Zero (CC0 1.0)",
			"url": "https://creativecommons.org/publicdomain/zero/1.0/",
			"attribution_required": false
		}
	else:
		lic_val = {
			"id": "public-domain",
			"name": "Public Domain Mark 1.0",
			"url": "https://creativecommons.org/publicdomain/mark/1.0/",
			"attribution_required": false
		}
	if raw.has("license"):lic_val=SourceLicense.record(raw.license,str(raw.get("license_version","")))
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (David Rumsey Map Collection / Stanford University)" % [display_title, author_name]
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

func variants(asset: Dictionary) -> Array:
	if str(asset.get("source_metadata",{}).get("iiif_image",asset.get("iiif_image",""))).is_empty():return []
	return [
		{
			"id": "max",
			"label": "Original Maximum Resolution (Max)",
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
			"label": "1024px Preview",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "512",
			"label": "512px Thumbnail",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var offset := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
	var limit := 24
	var resp: Dictionary = await client.search(query, offset, limit)
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
	if offset + limit < total:
		next_cur = str(offset + limit)

	return {
		"items": all_items,
		"next_cursor": next_cur
	}

func asset_details(asset: Dictionary) -> Dictionary:
	return asset

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	if not variant.is_empty() and not variants(asset).any(func(option):return str(option.id)==variant):return {"error":"The requested image version is not reported by this asset."}
	if variants(asset).is_empty():return {"error":"The source has not reported an image service for this asset."}
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var target_variant := variant if not variant.is_empty() else "max"
	var src: Dictionary = detailed.get("source_metadata", {})
	if src.is_empty():
		src = detailed

	var download_url := ""
	var id_val := str(src.get("id", detailed.get("id", "")))

	if src.has("iiif_image") and not str(src.iiif_image).is_empty():
		var iiif_base: String = str(src.iiif_image)
		var size_spec := "full/max/0/default.jpg"
		match target_variant:
			"2048":
				size_spec = "full/2048,/0/default.jpg"
			"1024":
				size_spec = "full/1024,/0/default.jpg"
			"512":
				size_spec = "full/512,/0/default.jpg"
			_:
				size_spec = "full/max/0/default.jpg"
		download_url = "%s/%s" % [iiif_base, size_spec]
	elif not id_val.is_empty():
		var size_spec := "full/max/0/default.jpg"
		match target_variant:
			"2048":
				size_spec = "full/2048,/0/default.jpg"
			"1024":
				size_spec = "full/1024,/0/default.jpg"
			"512":
				size_spec = "full/512,/0/default.jpg"
			_:
				size_spec = "full/max/0/default.jpg"
		download_url = "https://www.davidrumsey.com/luna/servlet/iiif/%s/%s" % [id_val, size_spec]
	else:
		download_url = str(detailed.get("thumbnail", ""))

	if download_url.is_empty():
		return {"error": "No download URL available for David Rumsey map."}

	var ext := download_url.get_file().get_extension()
	if ext.is_empty() or ext.contains("?"):
		ext = "jpg"

	var clean_id: String = str(detailed.get("id", "map"))
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
	sync_network()
	return await client.thumbnail(url)

func cancel_all() -> void:
	client.cancel_all()

func check_connection() -> Dictionary:
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.search("",0,1)
