@tool
extends "res://addons/3dtexel/core/provider.gd"
## Sketchfab 3D models provider adapter.

const Client = preload("res://addons/3dtexel/providers/sketchfab/client.gd")
const Cache = preload("res://addons/3dtexel/providers/sketchfab/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node
var session_token := ""

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "sketchfab",
		"name": "Sketchfab",
		"website": "https://sketchfab.com/",
		"key_env": ["SKETCHFAB_API_KEY", "SKETCHFAB_API_TOKEN"],
		"capabilities": ["model", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

func default_enabled() -> bool:
	return true

func disabled_reason() -> String:
	return "Unchecked by default. Turn on to browse or download Sketchfab models."

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	var env_key := OS.get_environment("SKETCHFAB_API_KEY")
	if not env_key.is_empty():
		return env_key
	return OS.get_environment("SKETCHFAB_API_TOKEN")

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API key configured."
	return "API key required. Set SKETCHFAB_API_KEY in environment or session settings."

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
	var raw_id: String = str(raw.get("uid", raw.get("id", "asset")))
	var clean_id := raw_id

	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "sketchfab"
	asset.provider = "Sketchfab"
	asset.id = clean_id
	asset.type = "model"

	var display_title := str(raw.get("name", raw.get("title", clean_id.capitalize())))
	asset.title = display_title
	asset.url = str(raw.get("viewerUrl", "https://sketchfab.com/3d-models/" + clean_id))

	var author_data: Variant = raw.get("user", {})
	var author_name := "Sketchfab Artist"
	var author_url := "https://sketchfab.com"
	if author_data is Dictionary:
		author_name = str(author_data.get("displayName", author_data.get("username", "Sketchfab Artist")))
		author_url = str(author_data.get("profileUrl", "https://sketchfab.com"))
	asset.authors = [{"name": author_name, "url": author_url}]

	var desc := str(raw.get("description", "%s on Sketchfab" % display_title))
	asset.description = desc

	var l_raw: Variant = raw.get("license", {})
	var l_slug := ""
	var l_name := "Creative Commons"
	var l_url := "https://creativecommons.org/"
	if l_raw is Dictionary:
		l_slug = str(l_raw.get("slug", "")).to_lower()
		l_name = str(l_raw.get("label", "Creative Commons"))
		l_url = str(l_raw.get("url", "https://creativecommons.org/"))

	var spdx := "CC-BY-4.0"
	if l_slug == "by": spdx = "CC-BY-4.0"
	elif l_slug == "by-sa": spdx = "CC-BY-SA-4.0"
	elif l_slug == "cc0": spdx = "CC0-1.0"
	elif "nc" in l_slug or "nd" in l_slug: spdx = "PROPRIETARY"

	asset.license = {
		"id": spdx.to_lower(),
		"name": l_name,
		"url": l_url,
		"attribution_required": spdx.begins_with("CC-BY")
	}

	asset.price = {"free": true, "credits": 0}
	asset.policy = Policy.evaluate(asset)

	var thumbs: Variant = raw.get("thumbnails", {})
	if thumbs is Dictionary and thumbs.has("images") and thumbs.images is Array and not thumbs.images.is_empty():
		asset.thumbnail = str(thumbs.images[0].get("url", ""))

	var vars := [
		{"id": "glb", "label": "GLB Model", "confirmed": true, "kind": "files"},
		{"id": "gltf", "label": "glTF Archive", "confirmed": true, "kind": "files"},
		{"id": "source", "label": "Original Source", "confirmed": true, "kind": "files"}
	]
	asset.variants = vars
	return asset

func variants(asset: Dictionary) -> Array:
	return asset.get("variants", [])

func is_detailed(_asset: Dictionary) -> bool:
	return true

func search(query: String) -> Array:
	if not network_allowed:
		return local_assets()
	sync_network()
	var json: Dictionary = await client.search(query)
	if json.has("error"):
		return []
	var results := []
	for r in json.get("results", []):
		if r is Dictionary:
			var norm: Dictionary = normalize(r, false)
			results.append(norm)
			client.cache.catalog[norm.id] = r
	client.cache.save()
	return results

func resolve_download(asset: Dictionary, requested: String) -> Dictionary:
	sync_network()
	var uid := str(asset.id)
	var dl: Dictionary = await client.resolve_download(uid)
	if dl.has("error"):
		return dl

	var target_format := requested if requested in ["gltf", "source"] else "glb"
	var selected: Dictionary = dl.get(target_format, dl.get("glb", dl.get("gltf", dl.get("source", {}))))
	if not selected.has("url"):
		return {"error": "Format not available"}

	var ext := "zip" if target_format == "source" else target_format
	var fname := "%s_%s.%s" % [Importer.slug(str(asset.title)), uid.left(8), ext]
	var files := [
		{
			"filename": fname,
			"url": selected.url,
			"size": selected.get("size", 0)
		}
	]
	return {
		"kind": "files",
		"asset": asset,
		"variant": target_format,
		"files": files
	}
