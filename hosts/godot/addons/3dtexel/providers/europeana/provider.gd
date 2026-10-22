@tool
extends "res://addons/3dtexel/core/provider.gd"
## Europeana Collections provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/europeana/client.gd")
const Cache = preload("res://addons/3dtexel/providers/europeana/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "europeana",
		"name": "Europeana Collections",
		"website": "https://www.europeana.eu/",
		"key_env": ["EUROPEANA_API_KEY"],
		"capabilities": ["image", "material", "files", "variants"]
	}

## The public demo key keeps Europeana usable without an account. It carries a
## lower rate limit, so a personal key from the environment is preferred.
const DEMO_KEY := "api2demo"

var session_key := ""

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_key = request_key()

func api_key() -> String:
	if not session_key.is_empty():
		return session_key
	return OS.get_environment("EUROPEANA_API_KEY").strip_edges()

## The key actually sent with a request. The demo key is only a fallback and
## is never shown as a credential.
func request_key() -> String:
	var key := api_key()
	return key if not key.is_empty() else DEMO_KEY

func set_session_key(value: String) -> void:
	session_key = value.strip_edges()
	sync_network()

func credential_status() -> String:
	if not OS.get_environment("EUROPEANA_API_KEY").strip_edges().is_empty():
		return "Using EUROPEANA_API_KEY from the environment."
	if not session_key.is_empty():
		return "Using the session key for this editor session."
	return "Using the public Europeana demo key (lower rate limit)."

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
	var id: String = str(raw_id)
	var clean_id := Importer.slug(id)
	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "europeana"
	asset.provider = "Europeana Collections"
	asset.id = clean_id
	asset.type = "image"

	var display_name := clean_id.capitalize()
	var titles: Variant = raw.get("title", [])
	if titles is Array and not titles.is_empty():
		display_name = str(titles[0])
	elif titles is String and not titles.is_empty():
		display_name = titles
	asset.title = display_name

	asset.url = str(raw.get("guid", "https://www.europeana.eu/item" + id))

	var edm_img: Variant = raw.get("edmPreview", [])
	if edm_img is Array and not edm_img.is_empty():
		asset.thumbnail = str(edm_img[0])
	else:
		asset.thumbnail = str(raw.get("thumbnail", ""))

	asset.description = str(raw.get("description", "%s in Europeana Collections" % display_name))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.price = {"free": true, "credits": 0}

	var creator := "Europeana Collections"
	var dc_creator: Variant = raw.get("dcCreator", [])
	if dc_creator is Array and not dc_creator.is_empty():
		creator = str(dc_creator[0])
	elif raw.has("dataProvider"):
		var dp: Variant = raw.get("dataProvider")
		if dp is Array and not dp.is_empty():
			creator = str(dp[0])
		elif dp is String:
			creator = dp
	asset.authors = [{"name": creator, "url": asset.url}]

	var rights_arr: Variant = raw.get("rights", [])
	var rights_str := ""
	if rights_arr is Array and not rights_arr.is_empty():
		rights_str = str(rights_arr[0]).to_lower()
	elif rights_arr is String:
		rights_str = rights_arr.to_lower()

	var is_cc0 := "cc0" in rights_str or "publicdomain" in rights_str or "zero" in rights_str
	var lic_val := {
		"id": "cc0" if is_cc0 else "public-domain",
		"name": "Creative Commons CC0 1.0 Universal" if is_cc0 else "Public Domain / Open Access",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	}
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	asset.attribution_text = "%s - %s (Europeana / Open Access)" % [display_name, creator]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	var result := []
	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		var fname := str(f_dict.get("filename", ""))
		var res := str(f_dict.get("resolution", fname.get_basename()))
		var vid := Importer.slug(res)
		result.append({
			"id": vid,
			"label": "%s Resolution" % vid.to_upper(),
			"kind": "files",
			"confirmed": true,
			"resolution": vid
		})

	if result.is_empty():
		result.append({
			"id": "orig",
			"label": "Original Maximum Resolution",
			"kind": "files",
			"confirmed": true
		})
		result.append({
			"id": "2048",
			"label": "2048px Resolution",
			"kind": "files",
			"confirmed": true
		})
		result.append({
			"id": "1024",
			"label": "1024px Preview",
			"kind": "files",
			"confirmed": true
		})

	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	if category in ["audio", "model"]:
		return {"items": [], "next_cursor": ""}

	var offset := int(cursor) if not cursor.is_empty() and cursor.is_valid_int() else 0
	var rows := 24
	var resp: Dictionary = await client.search(query, offset, rows)
	if resp.has("error"):
		return resp

	var all_items: Array = []
	if resp.has("items") and resp.items is Array:
		all_items = resp.items

	var items: Array[Dictionary] = []
	for raw in all_items:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		if category == "material":
			normalized.type = "material"
		client.cache.put_asset(normalized)
		items.append(normalized)

	var next_cur := str(offset + rows) if all_items.size() >= rows else ""
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

	var files: Array = detailed.get("files", [])
	if files.is_empty() and detailed.get("source_metadata") is Dictionary:
		files = detailed.source_metadata.get("files", [])

	var target_slug := Importer.slug(variant)
	var chosen_file: Dictionary = {}

	for f in files:
		if not (f is Dictionary):
			continue
		var f_dict: Dictionary = f
		if Importer.slug(str(f_dict.get("resolution", ""))) == target_slug or Importer.slug(str(f_dict.get("filename", "")).get_basename()) == target_slug:
			chosen_file = f_dict
			break

	if chosen_file.is_empty() and not files.is_empty() and files[0] is Dictionary:
		chosen_file = files[0]

	var dl_url := str(chosen_file.get("url", ""))
	if dl_url.is_empty():
		var edm_arr: Variant = detailed.get("edmIsShownBy", detailed.get("source_metadata", {}).get("edmIsShownBy", []))
		if edm_arr is Array and not edm_arr.is_empty():
			dl_url = str(edm_arr[0])
		elif edm_arr is String:
			dl_url = edm_arr

	if dl_url.is_empty():
		dl_url = str(detailed.get("thumbnail", detailed.get("source_metadata", {}).get("thumbnail", "")))

	if dl_url.is_empty():
		return {"error": "No download URL available for Europeana item."}

	if not dl_url.begins_with("https://"):
		return {"error": "Insecure download URL: %s" % dl_url}

	var filename := str(chosen_file.get("filename", "%s.jpg" % Importer.slug(str(detailed.id))))

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
	return await client.search()

func cancel_all() -> void:
	client.cancel_all()
