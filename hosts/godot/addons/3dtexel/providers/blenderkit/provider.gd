@tool
extends "res://addons/3dtexel/core/provider.gd"
## BlenderKit online 3D models provider adapter.

const Client = preload("res://addons/3dtexel/providers/blenderkit/client.gd")
const Cache = preload("res://addons/3dtexel/providers/blenderkit/cache.gd")
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
		"id": "blenderkit",
		"name": "BlenderKit",
		"website": "https://www.blendkit.com/",
		"key_env": ["BLENDERKIT_API_KEY", "BLENDERKIT_TOKEN"],
		"capabilities": ["model", "files", "variants"]
	}

func sync_network() -> void:
	client.network_allowed = network_allowed
	client.refreshing = refreshing
	client.api_token = api_key()

func default_enabled() -> bool:
	return true

func disabled_reason() -> String:
	return "Unchecked by default. Turn on to browse or download BlenderKit models."

func api_key() -> String:
	if not session_token.is_empty():
		return session_token
	var env_key := OS.get_environment("BLENDERKIT_API_KEY")
	if not env_key.is_empty():
		return env_key
	var token_env := OS.get_environment("BLENDERKIT_TOKEN")
	if not token_env.is_empty():
		return token_env
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		var token_file := home.path_join(".config/blenderkit_token.json")
		if FileAccess.file_exists(token_file):
			var content := FileAccess.get_file_as_string(token_file)
			var parsed: Variant = JSON.parse_string(content)
			if parsed is Dictionary and parsed.has("access_token"):
				return str(parsed["access_token"])
	return ""

func set_session_key(value: String) -> void:
	session_token = value.strip_edges()
	client.api_token = session_token

func credential_status() -> String:
	if not api_key().is_empty():
		return "API token configured."
	return "Public free mode (no token needed for free assets)."

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
	var raw_id: String = str(raw.get("id", "asset"))
	var clean_id := raw_id

	var asset: Dictionary = client.cache.asset(clean_id)
	asset.merge(raw, true)

	asset.provider_id = "blenderkit"
	asset.provider = "BlenderKit"
	asset.id = clean_id
	asset.type = "model"

	var display_title := str(raw.get("name", raw.get("displayName", raw.get("title", clean_id))))
	asset.title = display_title

	var base_id := str(raw.get("assetBaseId", clean_id))
	asset.url = str(raw.get("url", "https://www.blendkit.com/asset-gallery-detail/%s/" % base_id))

	# Authors
	var author_data: Variant = raw.get("author", {})
	var author_name := "BlenderKit Artist"
	var author_url := "https://www.blendkit.com"
	if author_data is Dictionary:
		author_name = str(author_data.get("fullName", author_data.get("firstName", "BlenderKit Artist")))
		if author_data.has("aboutMeUrl") and not str(author_data.aboutMeUrl).is_empty():
			author_url = str(author_data.aboutMeUrl)
		elif author_data.has("id"):
			author_url = "https://www.blendkit.com/?query=author_id:%s" % str(author_data.id)
	asset.authors = [{"name": author_name, "url": author_url}]

	var desc := str(raw.get("description", "%s on BlenderKit" % display_title))
	asset.description = desc

	# Thumbnails
	asset.thumbnail = str(raw.get("thumbnailMiddleUrl", raw.get("thumbnailSmallUrl", raw.get("thumbnailLargeUrl", ""))))

	# Licensing & Pricing
	var is_free: bool = bool(raw.get("isFree", false))
	asset.price = {"free": is_free, "credits": 0}

	var lic_str := str(raw.get("license", "royalty_free")).to_lower()
	var lic_val: Dictionary = {}
	if lic_str == "cc0" or lic_str == "public_domain":
		lic_val = {
			"id": "cc0-1.0",
			"name": "Creative Commons CC0 1.0 Universal",
			"url": "https://creativecommons.org/publicdomain/zero/1.0/",
			"attribution_required": false
		}
	elif lic_str in ["cc_by", "cc-by", "cc-by-4.0"]:
		lic_val = {
			"id": "cc-by-4.0",
			"name": "Creative Commons Attribution 4.0 International",
			"url": "https://creativecommons.org/licenses/by/4.0/",
			"attribution_required": true
		}
	else:
		lic_val = {
			"id": "royalty_free",
			"name": "Royalty Free (BlenderKit Standard Free)",
			"url": "https://www.blendkit.com/license/",
			"attribution_required": false
		}

	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license
	asset.attribution_text = "%s by %s via BlenderKit (%s)" % [display_title, author_name, lic_val.name]
	asset.metadata_source_url = asset.url
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.policy = Policy.evaluate(asset)
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var files: Array = asset.get("files", [])
	if files.is_empty() and asset.get("source_metadata") is Dictionary:
		files = asset.source_metadata.get("files", [])

	var result := []
	var has_gltf_godot := false
	var has_gltf := false
	var has_blend := false

	for f in files:
		if not (f is Dictionary):
			continue
		var ftype := str(f.get("fileType", ""))
		var dl_url := str(f.get("downloadUrl", ""))
		var size_bytes := int(f.get("fileUploadSize", f.get("size", 0)))
		var tip := "%.1f MB" % (size_bytes / 1048576.0) if size_bytes > 0 else "Free model"

		if ftype == "gltf_godot":
			has_gltf_godot = true
			result.append({
				"id": "gltf_godot",
				"label": "GLTF (Godot)",
				"kind": "files",
				"confirmed": true,
				"download_url": dl_url,
				"tooltip": tip
			})
		elif ftype == "gltf":
			has_gltf = true
			result.append({
				"id": "gltf",
				"label": "GLTF",
				"kind": "files",
				"confirmed": true,
				"download_url": dl_url,
				"tooltip": tip
			})
		elif ftype == "blend":
			has_blend = true
			result.append({
				"id": "blend",
				"label": "Blender (.blend)",
				"kind": "files",
				"confirmed": true,
				"download_url": dl_url,
				"tooltip": tip
			})

	# If no discrete files found, provide default fallback variants
	if result.is_empty():
		result.append({"id": "gltf_godot", "label": "GLTF (Godot)", "kind": "files", "confirmed": true})
		result.append({"id": "blend", "label": "Blender (.blend)", "kind": "files", "confirmed": true})

	return result

func is_detailed(_asset: Dictionary) -> bool:
	return true

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()
	if not category.is_empty() and category != "all" and category != "model" and category != "models":
		return {"items": [], "next_cursor": ""}

	var page := 1
	if not cursor.is_empty() and cursor.is_valid_int():
		page = maxi(1, cursor.to_int())

	var limit := 25
	var json: Dictionary = await client.search(query, page, limit)
	if json.has("error"):
		return json

	var raw_items: Array = json.get("results", [])
	var items: Array = []
	for raw in raw_items:
		if not (raw is Dictionary):
			continue
		var normalized := normalize(raw, true)
		client.cache.put_asset(normalized, false)
		items.append(normalized)

	var next_url := str(json.get("next", ""))
	var next_cur := str(page + 1) if not next_url.is_empty() and next_url != "null" and raw_items.size() >= limit else ""
	client.cache.save_catalog()
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	var raw_id := str(asset.get("id", ""))
	if raw_id.is_empty():
		return asset
	var detail_resp: Dictionary = await client.get_asset(raw_id)
	if detail_resp.has("error") or detail_resp.is_empty():
		return normalize(asset, false)
	return normalize(detail_resp, true)

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	if int(Policy.evaluate(detailed).status) == Policy.Status.BLOCKED:
		return {"error": "Asset is blocked by project license policy."}

	var meta: Dictionary = detailed.get("source_metadata", {})
	var candidate_files: Array = detailed.get("files", meta.get("files", []))

	var chosen_file: Dictionary = {}
	# Match by fileType
	for f in candidate_files:
		if f is Dictionary and str(f.get("fileType", "")) == variant:
			chosen_file = f
			break

	# Fallbacks
	if chosen_file.is_empty():
		for f in candidate_files:
			if f is Dictionary:
				var ftype := str(f.get("fileType", ""))
				if ftype in ["gltf_godot", "gltf", "blend"]:
					chosen_file = f
					break

	if chosen_file.is_empty() and not candidate_files.is_empty() and candidate_files[0] is Dictionary:
		chosen_file = candidate_files[0]

	var dl_endpoint := str(chosen_file.get("downloadUrl", ""))
	if dl_endpoint.is_empty():
		return {"error": "Download endpoint not available for this asset."}

	var dl_resp: Dictionary = await client.get_download_url(dl_endpoint)
	if dl_resp.has("error"):
		return dl_resp

	var file_path := str(dl_resp.get("filePath", ""))
	if file_path.is_empty():
		return {"error": "Signed download URL not returned by BlenderKit."}

	var ftype := str(chosen_file.get("fileType", variant))
	var ext := "glb" if ftype.begins_with("gltf") else ("blend" if ftype == "blend" else "zip")
	var slug_name := Importer.slug(str(detailed.get("title", detailed.id)))
	var filename := "%s.%s" % [slug_name, ext]

	var files := [
		{
			"filename": filename,
			"url": file_path,
			"size": int(chosen_file.get("fileUploadSize", 0))
		}
	]

	return {
		"kind": "files",
		"asset": detailed,
		"variant": variant,
		"files": files
	}

func get_bytes(url: String, destination := "", limit := 134217728) -> Dictionary:
	return await client.get_bytes(url, destination, limit)

func cancel_all() -> void:
	client.cancel_all()
