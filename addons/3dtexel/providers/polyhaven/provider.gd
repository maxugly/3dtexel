@tool
extends "res://addons/3dtexel/core/provider.gd"
## Poly Haven provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/polyhaven/client.gd")
const Cache = preload("res://addons/3dtexel/providers/polyhaven/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "polyhaven",
		"name": "Poly Haven",
		"website": "https://polyhaven.com/",
		"key_env": [],
		"capabilities": ["materials", "files", "variants", "image", "model", "material"]
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
	var id := str(raw.get("id", ""))
	var asset: Dictionary = client.cache.asset(id)
	asset.merge(raw, true)

	asset.provider_id = "polyhaven"
	asset.provider = "Poly Haven"
	asset.id = id

	# Type mapping: 0=hdri (image), 1=texture (material), 2=model (model)
	var type_val: Variant = raw.get("type", asset.get("type", 1))
	if type_val is int or type_val is float:
		match int(type_val):
			0: asset.type = "image"
			1: asset.type = "material"
			2: asset.type = "model"
			_: asset.type = "material"
	elif str(type_val) == "0":
		asset.type = "image"
	elif str(type_val) == "1":
		asset.type = "material"
	elif str(type_val) == "2":
		asset.type = "model"
	else:
		asset.type = str(type_val)

	var display_name := str(raw.get("name", raw.get("title", asset.get("title", id.capitalize()))))
	asset.title = display_name
	asset.url = str(raw.get("url", "https://polyhaven.com/a/" + id))
	asset.thumbnail = str(raw.get("thumbnail", "https://cdn.polyhaven.com/asset_img/thumbs/%s.png?width=256&height=256" % id))
	asset.description = str(raw.get("description", asset.get("description", "")))
	asset.tags = raw.get("tags", asset.get("tags", []))
	asset.categories = raw.get("categories", asset.get("categories", []))
	asset.price = {"free": true, "credits": 0}

	# Authors
	var authors_list: Array = []
	var raw_authors: Variant = raw.get("authors", asset.get("authors", []))
	if raw_authors is Dictionary:
		for author_name in raw_authors:
			authors_list.append({"name": str(author_name), "url": str(raw_authors[author_name])})
	elif raw_authors is Array:
		for a in raw_authors:
			if a is Dictionary:
				authors_list.append(a)
			elif a is String and not a.is_empty():
				authors_list.append({"name": a, "url": "https://polyhaven.com"})
	if authors_list.is_empty():
		authors_list = [{"name": "Poly Haven Contributors", "url": "https://polyhaven.com"}]
	asset.authors = authors_list

	var lic_val: Variant = raw.get("license", {
		"id": "cc0",
		"name": "CC0 1.0 Universal",
		"url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"attribution_required": false
	})
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	var author_names: Array[String] = []
	for a in asset.authors:
		author_names.append(str(a.get("name", "")))
	var author_str := ", ".join(author_names)
	asset.attribution_text = "Asset by %s via Poly Haven (CC0)" % author_str
	asset.metadata_source_url = "https://api.polyhaven.com/info/" + id
	asset.source_metadata = Cache.public_asset(raw)
	asset.retrieved_utc = Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc", "")
	asset.variants = variants(asset)
	return asset

func variants(asset: Dictionary) -> Array:
	var files_raw: Dictionary = asset.get("files_raw", {})
	if files_raw.is_empty() and asset.get("source_metadata") is Dictionary:
		files_raw = asset.source_metadata.get("files_raw", {})

	if files_raw.is_empty():
		return asset.get("variants", [])

	var asset_type := str(asset.get("type", "material"))
	var result := []

	if asset_type == "material":
		# Format preferred: jpg then png
		var formats := ["jpg", "png"]
		for fmt in formats:
			if files_raw.has(fmt) and files_raw[fmt] is Dictionary:
				var res_dict: Dictionary = files_raw[fmt]
				var sorted_res := res_dict.keys()
				sorted_res.sort()
				for res_key: String in sorted_res:
					var vid := Importer.slug(res_key)
					result.append({
						"id": vid,
						"label": res_key.to_upper() + " " + fmt.to_upper(),
						"confirmed": true,
						"kind": "material",
						"resolution": vid
					})
				break # Use jpg resolutions primarily
	elif asset_type == "model":
		# Formats: gltf, blend, fbx, obj
		for fmt: String in files_raw:
			if files_raw[fmt] is Dictionary:
				var vid := Importer.slug(fmt)
				result.append({
					"id": vid,
					"label": fmt.to_upper(),
					"confirmed": true,
					"kind": "files"
				})
	else:
		# HDRIs (images)
		for fmt: String in ["hdr", "exr"]:
			if files_raw.has(fmt) and files_raw[fmt] is Dictionary:
				var res_dict: Dictionary = files_raw[fmt]
				for res_key: String in res_dict:
					var vid := Importer.slug(res_key + "_" + fmt)
					result.append({
						"id": vid,
						"label": res_key.to_upper() + " " + fmt.to_upper(),
						"confirmed": true,
						"kind": "files"
					})
				break

	return result

func refresh_page(query: String, category: String, cursor: String) -> Dictionary:
	sync_network()

	# Map requested category
	var type_param := ""
	match category:
		"material": type_param = "textures"
		"model": type_param = "models"
		"image": type_param = "hdris"
		"audio":
			# Poly Haven has no audio
			return {"items": [], "next_cursor": ""}
		_:
			type_param = ""

	var resp: Dictionary = await client.fetch_assets(type_param)
	if resp.has("error"):
		return resp

	var all_items: Array = []
	var q := query.strip_edges().to_lower()

	for asset_id: String in resp:
		var item_data: Variant = resp[asset_id]
		if not (item_data is Dictionary):
			continue

		var item_dict: Dictionary = item_data
		item_dict["id"] = asset_id

		# Filter by text search if provided
		if not q.is_empty():
			var name: String = str(item_dict.get("name", "")).to_lower()
			var tags: Array = item_dict.get("tags", [])
			var cats: Array = item_dict.get("categories", [])
			var matched := asset_id.to_lower().contains(q) or name.contains(q)
			if not matched:
				for tag in tags:
					if str(tag).to_lower().contains(q):
						matched = true
						break
			if not matched:
				for cat in cats:
					if str(cat).to_lower().contains(q):
						matched = true
						break
			if not matched:
				continue

		all_items.append(item_dict)

	var offset := int(cursor) if not cursor.is_empty() else 0
	var page_size := 30
	var items: Array[Dictionary] = []

	var upper := mini(offset + page_size, all_items.size())
	for i in range(offset, upper):
		var raw_item: Dictionary = all_items[i]
		var normalized := normalize(raw_item, true)
		client.cache.put_asset(normalized)
		items.append(normalized)

	var next_cur := str(offset + page_size) if (offset + page_size < all_items.size()) else ""
	return {"items": items, "next_cursor": next_cur}

func asset_details(asset: Dictionary) -> Dictionary:
	return await refresh_asset(asset)

func refresh_asset(asset: Dictionary) -> Dictionary:
	sync_network()
	var id := str(asset.get("id", ""))
	if id.is_empty():
		return {"error": "Missing asset ID."}

	var info: Dictionary = await client.fetch_info(id)
	var files: Dictionary = await client.fetch_files(id)

	if info.has("error") and not files.has("error"):
		info = {}
	elif files.has("error") and not info.has("error"):
		files = {}
	elif info.has("error") and files.has("error"):
		return {"error": "Failed to fetch asset details: %s" % info.get("error")}

	var merged: Dictionary = asset.duplicate(true)
	merged.merge(info, true)
	merged["id"] = id
	merged["files_raw"] = files

	var normalized := normalize(merged, true)
	client.cache.put_asset(normalized)
	return normalized

func resolve_download(asset: Dictionary, variant: String) -> Dictionary:
	sync_network()
	var detailed := await asset_details(asset)
	if detailed.has("error"):
		return detailed

	var files_raw: Dictionary = detailed.get("files_raw", {})
	var asset_type := str(detailed.get("type", "material"))

	if asset_type == "material":
		# Maps: albedo, normal, roughness, ao, metallic, height
		var chosen_res := variant.to_lower()
		var fmt_dict: Dictionary = {}
		if files_raw.has("jpg") and files_raw["jpg"] is Dictionary:
			fmt_dict = files_raw["jpg"]
		elif files_raw.has("png") and files_raw["png"] is Dictionary:
			fmt_dict = files_raw["png"]

		if not fmt_dict.has(chosen_res):
			# fallback to first available resolution
			var keys := fmt_dict.keys()
			if not keys.is_empty():
				chosen_res = keys[0]
			else:
				return {"error": "No textures found for variant %s." % variant}

		var res_maps: Dictionary = fmt_dict.get(chosen_res, {})
		var maps := {}

		# Diffuse / Albedo
		if res_maps.has("diffuse"):
			maps["albedo"] = str(res_maps.diffuse.get("url", ""))
		elif res_maps.has("diff"):
			maps["albedo"] = str(res_maps.diff.get("url", ""))

		# Normal
		if res_maps.has("nor_gl"):
			maps["normal"] = str(res_maps.nor_gl.get("url", ""))
		elif res_maps.has("normal"):
			maps["normal"] = str(res_maps.normal.get("url", ""))

		# Roughness
		if res_maps.has("rough"):
			maps["roughness"] = str(res_maps.rough.get("url", ""))

		# AO
		if res_maps.has("ao"):
			maps["ao"] = str(res_maps.ao.get("url", ""))

		# Metallic
		if res_maps.has("metal"):
			maps["metallic"] = str(res_maps.metal.get("url", ""))

		# Height / Displacement
		if res_maps.has("disp"):
			maps["height"] = str(res_maps.disp.get("url", ""))

		if maps.is_empty():
			return {"error": "No map URLs resolved for variant %s." % variant}

		return {
			"kind": "material",
			"asset": detailed,
			"variant": chosen_res,
			"maps": maps,
			"normal_format": "opengl",
			"material_props": {}
		}
	else:
		# Model or HDRI (image)
		var files_to_download: Array[Dictionary] = []
		var matched_fmt := variant.to_lower()

		# Check if files_raw has the format directly (e.g. gltf, blend, fbx)
		if files_raw.has(matched_fmt) and files_raw[matched_fmt] is Dictionary:
			var container: Dictionary = files_raw[matched_fmt]
			# May be nested by resolution or direct
			if container.has("url"):
				var dl_url: String = str(container.get("url", ""))
				files_to_download.append({
					"filename": dl_url.get_file(),
					"url": dl_url
				})
			else:
				for sub_k in container:
					var sub_item: Variant = container[sub_k]
					if sub_item is Dictionary and sub_item.has("url"):
						var dl_url: String = str(sub_item.get("url", ""))
						files_to_download.append({
							"filename": dl_url.get_file(),
							"url": dl_url
						})
					elif sub_item is Dictionary:
						for leaf_k in sub_item:
							var leaf_item: Variant = sub_item[leaf_k]
							if leaf_item is Dictionary and leaf_item.has("url"):
								var dl_url: String = str(leaf_item.get("url", ""))
								files_to_download.append({
									"filename": dl_url.get_file(),
									"url": dl_url
								})

		if files_to_download.is_empty():
			return {"error": "Could not resolve download files for variant %s." % variant}

		return {
			"kind": "files",
			"asset": detailed,
			"variant": variant,
			"files": files_to_download
		}

func thumbnail(url: String) -> Texture2D:
	sync_network()
	return await client.thumbnail(url)

func get_bytes(url: String, destination: String, limit: int) -> Dictionary:
	if not network_allowed:
		return {"error": "Download requires explicit action."}
	return await client.get_bytes(url, destination, limit)

func check_connection() -> Dictionary:
	return await client.fetch_assets("textures")

func cancel_all() -> void:
	client.cancel_all()
