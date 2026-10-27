@tool
extends "res://addons/3dtexel/core/provider.gd"
## British Library Flickr Commons provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/british_library_flickr/client.gd")
const Cache = preload("res://addons/3dtexel/providers/british_library_flickr/cache.gd")
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
		"id": "british_library_flickr",
		"name": "British Library",
		"website": "https://www.flickr.com/photos/britishlibrary/",
		"key_env": ["FLICKR_API_KEY"],
		"capabilities": ["image", "material", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing

func api_key() -> String:
	return client.api_key()

func set_session_key(value: String) -> void:
	client.custom_key=value

func credential_status() -> String:
	return "API key configured." if not api_key().is_empty() else "Flickr API key required."
func default_enabled() -> bool:return not api_key().is_empty()
func disabled_reason() -> String:return "Set FLICKR_API_KEY or enter a session API key."

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

	asset.provider_id = "british_library_flickr"
	asset.provider = "British Library"
	asset.id = clean_id
	asset.type = "image"

	var display_title := ""
	if raw.has("title"):
		var t: Variant = raw.title
		if t is Dictionary:
			display_title = str(t.get("_content", ""))
		else:
			display_title = str(t)
	if display_title.is_empty():
		display_title = "British Library Item %s" % id_str
	asset.title = display_title

	asset.url = "https://www.flickr.com/photos/britishlibrary/%s/" % id_str

	# Thumbnails
	var thumb_url := ""
	for k in ["url_m", "url_z", "url_q", "url_s", "url_b"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			thumb_url = str(raw[k])
			break
	asset.thumbnail = thumb_url

	var desc_text := ""
	if raw.has("description"):
		var d: Variant = raw.description
		if d is Dictionary:
			desc_text = str(d.get("_content", ""))
		else:
			desc_text = str(d)
	if desc_text.is_empty():
		desc_text = "%s - Public domain historical illustration from the British Library." % display_title
	asset.description = desc_text

	var tag_list := []
	if raw.has("tags"):
		var t_val: Variant = raw.tags
		if t_val is String:
			for tag in t_val.split(" ", false):
				tag_list.append(tag)
		elif t_val is Array:
			tag_list = t_val
	asset.tags = tag_list

	asset.price = raw.get("price",{"free":true,"credits":0})

	var author_name := "The British Library"
	if raw.has("ownername") and not str(raw.ownername).is_empty():
		author_name = str(raw.ownername)
	asset.authors = [{"name": author_name, "url": "https://www.flickr.com/photos/britishlibrary/"}]

	var lic_val := {
		"id": "public-domain",
		"name": "Public Domain Mark 1.0 (No Known Copyright Restrictions)",
		"url": "https://creativecommons.org/publicdomain/mark/1.0/",
		"attribution_required": false
	}
	lic_val=flickr_license(raw.get("license",""))
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - British Library (Flickr Commons / Public Domain)" % display_title
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
	return Files.offers(asset,[["url_o","orig","Original Image"],["url_b","1024","Large Image"],["url_z","640","Medium Image"],["url_m","preview","Image Preview"]])
func variants(asset: Dictionary) -> Array:
	return Files.variants(file_offers(asset))

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var per_page := 24
	var resp: Dictionary = await client.search(query, page, per_page)
	if resp.has("error"):
		return resp

	var photos_container: Dictionary = resp.get("photos", {})
	var photo_list: Array = photos_container.get("photo", [])

	var all_items: Array = []
	for p in photo_list:
		if p is Dictionary:
			var norm: Dictionary = normalize(p, true)
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total_pages: int = int(photos_container.get("pages", 1))
	var next_cur := ""
	if page < total_pages:
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

static func flickr_license(value: Variant) -> Dictionary:
	var code := str(value)
	if code=="7":return {"id":"flickr-no-known-restrictions","name":"No known copyright restrictions","url":"https://www.flickr.com/commons/usage/","attribution_required":false}
	if code=="8":return {"id":"public-domain","name":"United States Government Work","url":"https://www.usa.gov/government-copyright","attribution_required":false}
	if code=="9":return SourceLicense.record("cc0")
	if code=="10":return SourceLicense.record("pdm")
	if code=="0":return {"id":"all-rights-reserved","name":"All Rights Reserved","url":"","attribution_required":false}
	var cc := {"1":"by-nc-sa","2":"by-nc","3":"by-nc-nd","4":"by","5":"by-sa","6":"by-nd","11":"by","12":"by-sa","13":"by-nd","14":"by-nc","15":"by-nc-sa","16":"by-nc-nd"}
	if cc.has(code):return SourceLicense.record(cc[code],"2.0" if int(code)<7 else "4.0")
	return SourceLicense.record(value)
