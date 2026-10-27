@tool
extends "res://addons/3dtexel/core/provider.gd"
## Freesound provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/freesound/client.gd")
const Cache = preload("res://addons/3dtexel/providers/freesound/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "freesound",
		"name": "Freesound",
		"website": "https://freesound.org/",
		"key_env": ["FREESOUND_API_KEY","FREESOUND_OAUTH_ACCESS_TOKEN"],
		"capabilities": ["audio", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing

## Credential fallback for standalone adapter consumers. The registry applies
## the bundled live-verification policy when deciding default checkboxes.
func default_enabled() -> bool:return not api_key().is_empty()
func disabled_reason() -> String:return "Configure FREESOUND_API_KEY for previews, or FREESOUND_OAUTH_ACCESS_TOKEN for originals."

func api_key() -> String:
	return client.api_key() if not client.api_key().is_empty() else client.oauth_token()

func set_session_key(value: String) -> void:
	client.custom_key = value.strip_edges()

func credential_status() -> String:
	if not client.oauth_token().is_empty():return "OAuth token configured; reported WAV/MP3/OGG originals available."
	if not api_key().is_empty():return "API key configured; audio previews available."
	return "API key required for search; original audio requires an OAuth access token."

func can_download(asset: Dictionary) -> bool:
	if int(Policy.evaluate(asset).status) not in [Policy.Status.PERMISSIVE,Policy.Status.ATTRIBUTION]:return false
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

## Flatten stored source evidence before normalization, preserving cache reloads.
func source_record(raw: Dictionary) -> Dictionary:
	var evidence: Variant=raw.get("source_metadata",{})
	var source: Dictionary=evidence.duplicate(true) if evidence is Dictionary else {}
	for field in ["id","name","url","description","username","license","images","previews","duration","samplerate","channels","filesize","tags","download","price"]:
		if raw.has(field):source[field]=raw[field]
	if raw.has("type") and str(raw.get("provider_id",""))!="freesound":source.type=raw.type
	return source
func preview_urls(asset: Dictionary) -> Dictionary:
	var source: Variant=asset.get("source_metadata",{})
	var value: Variant=asset.get("previews",source.get("previews",{}) if source is Dictionary else {})
	return value if value is Dictionary else {}
func normalize(raw: Dictionary, fetched := false) -> Dictionary:
	var source := source_record(raw)
	var raw_id: Variant=source.get("id",raw.get("id",""))
	var id := str(int(raw_id)) if raw_id is float or raw_id is int else str(raw_id)
	var asset: Dictionary=client.cache.asset(id)
	asset.merge(raw,true)
	asset.provider_id="freesound";asset.provider="Freesound";asset.id=id;asset.type="audio"
	asset.title=str(source.get("name",raw.get("title",asset.get("title","Freesound "+id))))
	asset.url=str(source.get("url","https://freesound.org/s/"+id+"/"))
	var images: Variant=source.get("images",{})
	asset.thumbnail=""
	if images is Dictionary:
		for field in ["waveform_m","spectral_m","waveform_l","spectral_l"]:
			var value: Variant=images.get(field,"")
			if value is String and value.begins_with("https://"):
				asset.thumbnail=value;break
	var username := str(source.get("username","")).strip_edges() if source.get("username")!=null else ""
	asset.authors=[]
	if not username.is_empty():asset.authors=[{"name":username,"url":"https://freesound.org/people/"+username.uri_encode()+"/"}]
	asset.description=str(source.get("description","")) if source.get("description")!=null else ""
	if asset.description.is_empty():asset.description=asset.title
	asset.tags=source.tags.duplicate() if source.get("tags") is Array else []
	for field in ["type","channels"]:
		if source.get(field)!=null and str(source[field]) not in asset.tags:asset.tags.append(str(source[field]))
	var price: Variant=source.get("price",{"free":true,"credits":0})
	asset.price=price if price is Dictionary else {}
	asset.license=SourceLicense.record(source.get("license",""))
	asset.licenses=[asset.license];asset.selected_license=asset.license
	var by := " by "+username if not username.is_empty() else ""
	asset.attribution_text="\"%s\"%s — Freesound (%s)" % [asset.title,by,str(asset.license.name)]
	asset.metadata_source_url=Client.BASE_URL+"/apiv2/sounds/"+id+"/"
	asset.source_metadata=Cache.public_asset(source)
	# Use sanitized source evidence for both current and restored preview choices.
	asset.previews=asset.source_metadata.get("previews",{})
	asset.retrieved_utc=Time.get_datetime_string_from_system(true) if fetched else str(raw.get("retrieved_utc",""))
	asset.variants=variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var previews := preview_urls(asset)
	var result := []
	for spec in [["mp3_hq","preview-hq-mp3","MP3 High Quality Preview"],["ogg_hq","preview-hq-ogg","OGG High Quality Preview"],["mp3_lq","preview-lq-mp3","MP3 Low Quality Preview"],["ogg_lq","preview-lq-ogg","OGG Low Quality Preview"]]:
		if str(previews.get(spec[1],"")).begins_with("https://"):
			result.append({"id":spec[0],"label":spec[2],"kind":"files","confirmed":true})
	var source: Dictionary=asset.get("source_metadata",{})
	var original_url := str(source.get("download",""))
	if not client.oauth_token().is_empty() and Client.original_download_url(original_url,str(asset.get("id",""))) and str(source.get("type","")).to_lower() in ["wav","mp3","ogg"]:
		result.append({"id":"original","label":"Original "+str(source.type).to_upper(),"kind":"files","confirmed":true})
	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	if category not in ["all","audio"]:
		return {"items": [], "next_cursor": ""}

	if not network_allowed:return {"error":"Search requires explicit action."}
	if not cursor.is_empty() and (not cursor.is_valid_int() or int(cursor)<1):return {"error":"Invalid Freesound page cursor."}
	sync_network()
	var page := int(cursor) if not cursor.is_empty() else 1
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

	var next_cur := ""
	if not str(resp.get("next","")).is_empty() and resp.get("next")!=null:
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
	var response: Dictionary=await client.fetch_sound(str(asset.id))
	if response.has("error"):return response
	var normalized := normalize(response,true)
	client.cache.set_asset(str(normalized.id),normalized);client.cache.save()
	return normalized

func resolve_download(asset: Dictionary,variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	if int(Policy.evaluate(asset).status)==Policy.Status.BLOCKED:return {"error":"The sound's price or license blocks downloading."}
	if variant=="original" and client.oauth_token().is_empty():return {"error":"Original Freesound downloads require FREESOUND_OAUTH_ACCESS_TOKEN; preview files are separate choices."}
	var detailed := await asset_details(asset)
	if detailed.has("error"):return detailed
	if not can_download(detailed):return {"error":"Updated sound metadata blocks downloading."}
	var options := variants(detailed)
	var target := variant if not variant.is_empty() else str(options[0].id)
	if not options.any(func(option):return option.id==target):return {"error":"The requested Freesound preview is not reported by this sound."}
	if target=="original":
		var source: Dictionary=detailed.get("source_metadata",{})
		return {"kind":"files","asset":detailed,"variant":target,"files":[{"filename":str(detailed.id)+"_original."+str(source.type).to_lower(),"url":str(source.download)}]}
	var parts := target.split("_");var extension := str(parts[0]);var quality := str(parts[1])
	var previews := preview_urls(detailed)
	var url := str(previews.get("preview-"+quality+"-"+extension,""))
	return {"kind":"files","asset":detailed,"variant":target,"files":[{"filename":str(detailed.id)+"_"+target+"."+extension,"url":url}]}

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	sync_network()
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
