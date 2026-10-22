@tool
extends "res://addons/3dtexel/core/provider.gd"
## Freesound provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/freesound/client.gd")
const Cache = preload("res://addons/3dtexel/providers/freesound/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
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
		"key_env": ["FREESOUND_API_KEY"],
		"capabilities": ["audio", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing

## The API only answers requests that carry a key, so the site stays out of
## the default sweep until a key is present.
func default_enabled() -> bool:return not api_key().is_empty()
func disabled_reason() -> String:return "The API needs a key: set FREESOUND_API_KEY or paste a session key."

func api_key() -> String:
	return client.api_key()

func set_session_key(value: String) -> void:
	client.custom_key = value

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "Free API key optional for extended search/downloads."

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

	asset.provider_id = "freesound"
	asset.provider = "Freesound"
	asset.id = clean_id
	asset.type = "audio"

	var display_title := str(raw.get("name", ""))
	if display_title.is_empty():
		display_title = "Freesound %s" % id_str
	asset.title = display_title

	asset.url = str(raw.get("url", "https://freesound.org/s/%s/" % id_str))

	# Previews and waveform thumbnails
	var images: Dictionary = raw.get("images", {})
	var thumb := str(images.get("waveform_m", images.get("spectral_m", "")))
	asset.thumbnail = thumb

	var author_name := str(raw.get("username", "Unknown Artist"))
	asset.authors = [{"name": author_name, "url": "https://freesound.org/people/%s/" % author_name}]

	var desc := str(raw.get("description", ""))
	if desc.is_empty():
		var dur := float(raw.get("duration", 0.0))
		var srate := int(raw.get("samplerate", 44100))
		var ch := int(raw.get("channels", 2))
		desc = "%s - Sound recording by %s (%0.1fs, %dHz, %s channels)" % [
			display_title, author_name, dur, srate, "stereo" if ch == 2 else "mono"
		]
	asset.description = desc

	var tags := []
	if raw.has("tags") and raw.tags is Array:
		tags.append_array(raw.tags)
	for k in ["type", "channels"]:
		if raw.has(k) and not str(raw[k]).is_empty():
			tags.append(str(raw[k]))
	asset.tags = tags

	asset.price = {"free": true, "credits": 0}

	# Freesound license parsing
	var raw_lic := str(raw.get("license", "")).to_lower()
	var lic_id := "cc0-1.0"
	var lic_name := "Creative Commons Zero (CC0 1.0)"
	var lic_url := "https://creativecommons.org/publicdomain/zero/1.0/"
	var attr_req := false

	if "by-nc" in raw_lic or "noncommercial" in raw_lic:
		lic_id = "cc-by-nc-4.0"
		lic_name = "Creative Commons Attribution NonCommercial (CC-BY-NC 4.0)"
		lic_url = "https://creativecommons.org/licenses/by-nc/4.0/"
		attr_req = true
	elif "by" in raw_lic or "attribution" in raw_lic:
		lic_id = "cc-by-4.0"
		lic_name = "Creative Commons Attribution 4.0 International (CC-BY 4.0)"
		lic_url = "https://creativecommons.org/licenses/by/4.0/"
		attr_req = true

	var lic_val := {
		"id": lic_id,
		"name": lic_name,
		"url": lic_url,
		"attribution_required": attr_req
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	if attr_req:
		asset.attribution_text = "\"%s\" by %s (https://freesound.org/s/%s/) licensed under %s" % [
			display_title, author_name, id_str, lic_name
		]
	else:
		asset.attribution_text = "\"%s\" by %s - Freesound (CC0 1.0 Universal)" % [display_title, author_name]

	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	return [
		{
			"id": "mp3_hq",
			"label": "MP3 High Quality Preview",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "ogg_hq",
			"label": "OGG High Quality Preview",
			"kind": "files",
			"confirmed": true
		},
		{
			"id": "original",
			"label": "Original Sound File",
			"kind": "files",
			"confirmed": true
		}
	]

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["image", "model", "material"]:
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

	var total: int = int(resp.get("count", 0))
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

	var target_variant := variant if not variant.is_empty() else "mp3_hq"
	var previews: Dictionary = detailed.get("previews", {})
	if previews.is_empty() and detailed.get("source_metadata") is Dictionary:
		previews = detailed.source_metadata.get("previews", {})

	var download_url := ""
	var filename := ""

	if target_variant == "mp3_hq":
		download_url = str(previews.get("preview-hq-mp3", previews.get("preview-lq-mp3", "")))
		filename = "%s.mp3" % str(detailed.get("id", "sound"))
	elif target_variant == "ogg_hq":
		download_url = str(previews.get("preview-hq-ogg", previews.get("preview-lq-ogg", "")))
		filename = "%s.ogg" % str(detailed.get("id", "sound"))
	elif target_variant == "original":
		download_url = str(detailed.get("download_url", detailed.get("download", "")))
		if download_url.is_empty():
			# Fallback to high quality audio preview
			download_url = str(previews.get("preview-hq-ogg", previews.get("preview-hq-mp3", "")))
		var orig_type := str(detailed.get("type", "wav")).to_lower()
		filename = "%s.%s" % [str(detailed.get("id", "sound")), orig_type]

	if download_url.is_empty():
		return {"error": "No download URL available for Freesound audio."}

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
