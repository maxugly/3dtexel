@tool
extends "res://addons/3dtexel/core/provider.gd"
## Wellcome Collection provider adapter implementing Provider Contract v1.

const Client = preload("res://addons/3dtexel/providers/wellcome_collection/client.gd")
const Cache = preload("res://addons/3dtexel/providers/wellcome_collection/cache.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")

var client: Node

func _init() -> void:
	client = Client.new()
	add_child(client)

func descriptor() -> Dictionary:
	return {
		"id": "wellcome_collection",
		"name": "Wellcome Collection",
		"website": "https://wellcomecollection.org/",
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

	asset.provider_id = "wellcome_collection"
	asset.provider = "Wellcome Collection"
	asset.id = clean_id
	asset.type = "image"

	var display_title := str(raw.get("title", ""))
	if display_title.is_empty():
		display_title = "Wellcome Work %s" % id_str
	asset.title = display_title

	asset.url = "https://wellcomecollection.org/works/%s" % id_str

	# Extract thumbnail URL
	var thumb_url := ""
	if raw.has("thumbnail") and raw.thumbnail is Dictionary:
		thumb_url = str(raw.thumbnail.get("url", ""))
	asset.thumbnail = thumb_url

	# Extract description
	var desc := str(raw.get("description", ""))
	if desc.contains("<"):
		# Strip basic html tags
		var regex := RegEx.new()
		regex.compile("<[^>]*>")
		desc = regex.sub(desc, "", true)
	if desc.is_empty():
		desc = "%s - Digitized collection work at Wellcome Collection." % display_title
	asset.description = desc

	# Authors / Contributors
	var authors := []
	if raw.has("contributors") and raw.contributors is Array:
		for c in raw.contributors:
			if c is Dictionary and c.has("agent") and c.agent is Dictionary:
				var name: String = str(c.agent.get("label", ""))
				if not name.is_empty():
					authors.append({"name": name, "url": asset.url})
	if authors.is_empty():
		authors.append({"name": "Wellcome Collection", "url": "https://wellcomecollection.org/"})
	asset.authors = authors

	asset.price = raw.get("price",{"free":true,"credits":0})

	# License determination
	var lic_id := "cc-by-4.0"
	var lic_name := "Creative Commons Attribution 4.0 International (CC BY 4.0)"
	var lic_url := "https://creativecommons.org/licenses/by/4.0/"
	var req_attrib := true

	# Inspect items for specific license info
	if raw.has("items") and raw.items is Array:
		for it in raw.items:
			if it is Dictionary and it.has("locations") and it.locations is Array:
				for loc in it.locations:
					if loc is Dictionary and loc.has("license") and loc.license is Dictionary:
						var l_id := str(loc.license.get("id", "")).to_lower()
						if l_id.contains("cc0") or l_id.contains("pdm") or l_id.contains("public"):
							lic_id = "public-domain"
							lic_name = "Public Domain Mark"
							lic_url = "https://creativecommons.org/publicdomain/mark/1.0/"
							req_attrib = false
							break

	var lic_val := {
		"id": lic_id,
		"name": lic_name,
		"url": lic_url,
		"attribution_required": req_attrib
	}
	if raw.has("license"):lic_val=SourceLicense.record(raw.license,str(raw.get("license_version","")))
	asset.license = Credits.license_record(lic_val)
	asset.licenses = [asset.license]
	asset.selected_license = asset.license

	var creator_name: String = str(authors[0].name)
	asset.attribution_text = "%s - %s (Wellcome Collection / %s)" % [display_title, creator_name, lic_name]
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

func _extract_iiif_base(asset: Dictionary) -> String:
	var src: Dictionary = asset.get("source_metadata", {})
	if src.is_empty():
		src = asset

	if src.has("items") and src.items is Array:
		for it in src.items:
			if it is Dictionary and it.has("locations") and it.locations is Array:
				for loc in it.locations:
					if loc is Dictionary:
						var u := str(loc.get("url", ""))
						if u.contains("/image/") or u.contains("/thumbs/"):
							if u.ends_with("/info.json"):
								return u.trim_suffix("/info.json").replace("/thumbs/", "/image/")
							elif u.contains("/full/"):
								var parts := u.split("/full/", true, 1)
								return parts[0].replace("/thumbs/", "/image/")

	var thumb := str(asset.get("thumbnail", ""))
	if (thumb.contains("/image/") or thumb.contains("/thumbs/")) and thumb.contains("/full/"):
		var parts := thumb.split("/full/", true, 1)
		return parts[0].replace("/thumbs/", "/image/")

	return ""

func variants(asset: Dictionary) -> Array:
	if _extract_iiif_base(asset).is_empty():return []
	var result := [
		{
			"id": "max",
			"label": "Full Resolution (Max)",
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
	return result

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
			if category == "material":
				norm.type = "material"
			client.cache.catalog[norm.id] = norm
			all_items.append(norm)

	client.cache.save()

	var total_pages: int = int(resp.get("totalPages", 1))
	var next_cur := ""
	if page < total_pages:
		next_cur = str(page + 1)

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
	var iiif_base := _extract_iiif_base(detailed)
	var download_url := ""

	if not iiif_base.is_empty():
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
	else:
		download_url = str(detailed.get("thumbnail", ""))

	if download_url.is_empty():
		return {"error": "No download URL available for Wellcome Collection work."}

	var clean_id: String = str(detailed.get("id", "work"))
	var filename := "%s_%s.jpg" % [clean_id, target_variant]

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
	return await client.search("",1,1)
