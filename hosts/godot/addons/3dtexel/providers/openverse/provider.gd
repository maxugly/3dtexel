@tool
extends "res://addons/3dtexel/core/provider.gd"
## Openverse provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/openverse/client.gd")
const Cache = preload("res://addons/3dtexel/providers/openverse/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "openverse",
		"name": "Openverse",
		"website": "https://openverse.org/",
		"key_env": [],
		"capabilities": ["image", "audio", "material", "files", "variants"]
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
	if int(preload("res://addons/3dtexel/core/license_policy.gd").evaluate(asset).status) not in [0,2]:return false
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

	asset.provider_id = "openverse"
	asset.provider = "Openverse"
	asset.id = clean_id

	var mediatype := str(raw.get("media_type",raw.get("type", raw.get("category", "")))).to_lower()
	if mediatype == "audio" or raw.has("audio_set") or raw.has("waveform"):
		asset.type = "audio"
	else:
		asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "Openverse Item %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("foreign_landing_url", raw.get("url", "https://openverse.org/%s/%s" % [asset.type, id_str])))
	asset.thumbnail = str(raw.get("thumbnail", raw.get("url", "")))

	var creator := str(raw.get("creator", "Unknown Creator"))
	var creator_url := str(raw.get("creator_url", asset.url))
	asset.authors = [{"name": creator, "url": creator_url}] if raw.has("creator") and not str(raw.creator).is_empty() else []

	var source_name := str(raw.get("source", raw.get("provider", "Openverse Collection")))
	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		desc = "%s by %s [Source: %s]" % [display_title, creator, source_name]
	asset.description = desc

	var tags := []
	if raw.has("tags") and raw.tags is Array:
		for t in raw.tags:
			if t is Dictionary:
				tags.append(str(t.get("name", "")))
			elif t is String:
				tags.append(t)
	tags.append(source_name)
	asset.tags = tags

	asset.price = raw.get("price",{"free":true,"credits":0})

	var lic_val := SourceLicense.record(raw.get("license",""),str(raw.get("license_version","")))
	var lic_name := str(lic_val.name);var attr_req := bool(lic_val.attribution_required)
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	if attr_req:
		asset.attribution_text = "\"%s\" by %s (%s) licensed under %s via Openverse" % [
			display_title, creator, asset.url, lic_name
		]
	else:
		asset.attribution_text = "\"%s\" by %s - Openverse (%s)" % [display_title, creator, lic_name]

	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw.get("source_metadata",raw))
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var source: Dictionary=asset.get("source_metadata",{})
	var result := []
	var audio: bool=asset.get("type")=="audio"
	if str(source.get("url","")).begins_with("https://"):
		result.append({"id":"audio" if audio else "orig","label":"Source Audio File" if audio else "Original Full Resolution","kind":"files","confirmed":true})
	if not audio and str(asset.get("thumbnail","")).begins_with("https://"):
		result.append({"id":"preview","label":"Image Preview","kind":"files","confirmed":true})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category == "model":
		return {"items": [], "next_cursor": ""}

	var page := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 1
	var page_size := 20
	var search_cat := "audio" if category == "audio" else "image"
	var resp: Dictionary = await client.search(query, search_cat, page, page_size)
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

	var total: int = int(resp.get("result_count", 0))
	var next_cur := ""
	if page<int(resp.get("page_count",ceili(float(total)/page_size))):
		next_cur = str(page + 1)

	return {
		"items": all_items,
		"next_cursor": next_cur
	}

func asset_details(asset: Dictionary) -> Dictionary:
	var cached: Dictionary=client.cache.asset(str(asset.id))
	var detailed := Cache.merge_asset(cached,asset)
	if not variants(detailed).is_empty():return detailed
	return await refresh_asset(detailed)
func refresh_asset(asset: Dictionary) -> Dictionary:
	if not network_allowed:return {"error":"Asset details require explicit action."}
	sync_network()
	var source: Dictionary=asset.get("source_metadata",{})
	var response: Dictionary=await client.fetch_detail(str(source.get("id",asset.id)),str(asset.get("type","image")))
	if response.has("error"):return response
	if asset.get("type")=="audio":response.media_type="audio"
	var normalized := normalize(response,true)
	client.cache.set_asset(str(normalized.id),normalized);client.cache.save()
	return normalized

func resolve_download(asset: Dictionary,variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	var detailed := await asset_details(asset)
	if detailed.has("error"):return detailed
	var target := variant if not variant.is_empty() else ("audio" if detailed.get("type")=="audio" else "orig")
	if not variants(detailed).any(func(option):return option.id==target):return {"error":"The requested Openverse version is not reported by this asset."}
	var source: Dictionary=detailed.get("source_metadata",{})
	var url := str(detailed.get("thumbnail","")) if target=="preview" else str(source.get("url",""))
	var extension := url.get_slice("?",0).get_slice("#",0).get_extension().to_lower()
	if extension.is_empty():extension=str(source.get("filetype","" )).trim_prefix(".")
	if extension not in ["jpg","jpeg","png","webp","gif","tif","tiff","svg","mp3","ogg","wav","flac","m4a"]:
		return {"error":"The source did not report a supported file format."}
	return {"kind":"files","asset":detailed,"variant":target,"files":[{"filename":str(detailed.id)+"_"+target+"."+extension,"url":url}]}

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
	return await client.search("","image",1,1)
