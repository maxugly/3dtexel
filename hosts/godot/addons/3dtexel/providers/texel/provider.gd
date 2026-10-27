@tool
extends "res://addons/3dtexel/core/provider.gd"
const Client = preload("res://addons/3dtexel/providers/texel/client.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Cache = preload("res://addons/3dtexel/providers/texel/cache.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
var client: Node
func _init() -> void:
	client=Client.new();add_child(client)
func descriptor() -> Dictionary:
	return {"id":"texel","name":"3D Texel","website":"https://3dtexel.com/pbr-material/","key_env":Client.KEY_NAMES,"capabilities":["material","terrain","variants"]}
func sync_network() -> void:
	client.network_allowed=network_allowed;client.refreshing=refreshing
func api_key() -> String:return client.api_key()
func set_session_key(value: String) -> void:client.session_key=value
func credential_status() -> String:
	return "Key available (environment/session)." if not api_key().is_empty() else "Browsing needs no key. Downloads need 3D_TEXEL_API_KEY or a session key."
func can_download(asset: Dictionary) -> bool:
	return Importer.free_asset(asset) and int(Policy.evaluate(asset).status) in [Policy.Status.PERMISSIVE,Policy.Status.ATTRIBUTION] and not api_key().is_empty() and source_record(asset).get("download",{}).get("via_api",true)
func source_record(raw: Dictionary) -> Dictionary:
	var source: Dictionary=raw.get("source_metadata",{}).duplicate(true) if raw.get("source_metadata") is Dictionary else {}
	source.merge(Cache.public_asset(raw),true)
	return source
func license_record(value: Variant) -> Dictionary:
	# Preserve the API's exact CC0 declaration while supplying its canonical ID.
	if value is String and value.strip_edges().to_lower()=="cc0 1.0 (public domain)":return SourceLicense.record("cc0-1.0")
	return SourceLicense.record(value)
func normalize(raw: Dictionary, fetched := false) -> Dictionary:
	var source := source_record(raw)
	var id := str(int(source.get("id",source.get("asset_id",0))))
	var asset: Dictionary=client.cache.asset(int(id))
	asset.merge(source,true);asset.merge(raw,true)
	asset.provider_id="texel";asset.provider="3DTexel";asset.id=id
	asset.type="material";asset.authors=Credits.authors(asset)
	asset.source_metadata=Cache.public_asset(source)
	asset.retrieved_utc=Time.get_datetime_string_from_system(true) if fetched else str(raw.get("retrieved_utc",""))
	asset.license=license_record(source.get("license",""));asset.licenses=[asset.license];asset.selected_license=asset.license
	asset.variants=variants(asset)
	return asset
func variants(asset: Dictionary) -> Array:
	var sizes := Credits.available_resolutions(source_record(asset));var result := []
	for size in sizes:result.append({"id":size,"label":size.to_upper(),"confirmed":true,"kind":"material","resolution":size})
	return result
func local_assets() -> Array:
	client.cache.ensure_loaded();var result := []
	for raw: Dictionary in client.cache.catalog.values():result.append(normalize(raw))
	return result
func refresh_page(query: String,_category: String,cursor: String) -> Dictionary:
	if _category not in ["all","material"]:return {"items":[],"next_cursor":""}
	if not network_allowed:return {"error":"Refresh requires explicit action."}
	sync_network()
	var parts := cursor.split(":")
	if not cursor.is_empty() and (parts.size()!=2 or parts[0] not in ["pbr","ai-pbr"] or not parts[1].is_valid_int() or int(parts[1])<1 or int(parts[1])>50):return {"error":"Invalid 3D Texel page cursor."}
	var source := parts[0] if parts.size()>1 else "pbr";var page := int(parts[1]) if parts.size()>1 else 1
	var data: Dictionary=await client.json_request("/assets/search?q=%s&type=%s&page=%s&per_page=24" % [query.uri_encode(),source,page])
	if data.has("error"):return data
	var items := []
	for raw: Dictionary in data.get("items",[]):
		items.append(normalize(raw,true))
		var url := str(raw.get("thumbnail",""))
		if not url.is_empty():client.allowed_thumbnails[url]=true
	var next_cursor := "%s:%s" % [source,page+1] if page*24<int(data.get("total",0)) and page<50 else ("ai-pbr:1" if source=="pbr" else "")
	return {"items":items,"next_cursor":next_cursor}
func refresh_asset(asset: Dictionary) -> Dictionary:
	if not network_allowed:return {"error":"Metadata refresh requires explicit action."}
	sync_network();var data: Dictionary=await client.json_request("/assets/%s" % int(asset.id))
	if data.has("error"):return data
	return normalize(await client.enrich_asset(data,true),true)
func resolve_download(asset: Dictionary,variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	if api_key().is_empty():return {"error":"Configure 3D_TEXEL_API_KEY for downloads."}
	if not str(asset.get("id","")).is_valid_int() or int(asset.id)<1:return {"error":"Invalid 3D Texel asset ID."}
	sync_network()
	# Revalidate price and license immediately before asking for zero-credit links.
	var previous: bool=client.refreshing;client.refreshing=true
	var fresh: Dictionary=await client.json_request("/assets/%s" % int(asset.id))
	client.refreshing=previous
	if fresh.has("error"):return fresh
	if int(fresh.get("id",0))!=int(asset.id):return {"error":"The site returned a different asset."}
	fresh=normalize(await client.enrich_asset(fresh),true)
	if not can_download(fresh):return {"error":"Current price, license or API availability blocks downloading."}
	if not variants(fresh).any(func(option):return option.id==variant):return {"error":"The selected resolution is not reported by this material."}
	var response: Dictionary=await client.json_request("/assets/%s/download" % int(asset.id),HTTPClient.METHOD_POST,{"max_credits":0,"resolution":variant})
	if response.has("error"):return response
	if not response.has("charged_credits") or float(response.charged_credits)!=0:return {"error":"The response did not confirm a zero-credit download."}
	if not response.get("files") is Dictionary:return {"error":"No material files were returned."}
	var files: Dictionary=response.files
	fresh.license=response.get("license",fresh.get("license",{}));fresh=normalize(fresh,true)
	if not can_download(fresh):return {"error":"The returned license blocks importing this material."}
	var maps := {}
	for role in Importer.MAPS:
		var url := Importer.file_url(files.get(role,""))
		if url.begins_with("https://"):maps[role]=url
	if not maps.has("albedo"):return {"error":"No supported albedo map was reported."}
	var actual := str(files.get("resolution",variant)).to_lower()
	if actual not in ["1k","2k","4k","8k","16k"]:return {"error":"Invalid returned material resolution."}
	return {"kind":"material","asset":fresh,"variant":actual,"maps":maps,"normal_format":files.get("normal_format","opengl"),"material_props":files.get("material_props",{})}
func thumbnail(url: String) -> Texture2D:
	sync_network();return await client.thumbnail(url)
func get_bytes(url: String,destination: String,limit: int) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	sync_network();return await client.get_bytes(url,destination,limit)
func check_connection() -> Dictionary:
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network()
	return await client.json_request("/me")

func legacy_folder(output: String,asset: Dictionary,variant: String) -> String:
	for directory in [output,"res://3DTexel/Materials"]:
		var base: String = directory.path_join("%s_%s" % [Importer.slug(str(asset.title)),int(asset.id)])
		var actual := variant
		var alias_path: String = base.path_join("request_"+variant+".json")
		if FileAccess.file_exists(alias_path):
			var alias: Variant=JSON.parse_string(FileAccess.get_file_as_string(alias_path))
			if alias is Dictionary:actual=Importer.slug(str(alias.get("returned_resolution",variant)))
		var folder: String = base.path_join(actual)
		if FileAccess.file_exists(folder.path_join("material.res")) and FileAccess.file_exists(folder.path_join("provenance.json")):return folder
	return ""
func cancel_all() -> void:client.cancel_all()

func load_local_imports(output: String) -> void:
	client.cache.load_local_imports(output)
	if output!="res://3DTexel/Materials":client.cache.load_local_imports("res://3DTexel/Materials")

func local_import_roots() -> Array:return ["res://3DTexel/Materials"]
func asset_details(asset: Dictionary) -> Dictionary:
	if not network_allowed:return {"error":"Choose an asset first."}
	sync_network();client.refreshing=false
	var data: Dictionary=await client.json_request("/assets/%s" % int(asset.id))
	if data.has("error"):return data
	return normalize(await client.enrich_asset(data),false)
