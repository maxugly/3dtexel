@tool
extends "res://addons/3dtexel/core/provider.gd"
const Client = preload("res://addons/3dtexel/providers/texel/client.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
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
	return "Key available (environment/session)." if not api_key().is_empty() else "Browsing needs no key. Downloads need TEXEL_API_KEY or a session key."
func can_download(asset: Dictionary) -> bool:
	return Importer.free_asset(asset) and not api_key().is_empty() and asset.get("download",{}).get("via_api",true)
func normalize(raw: Dictionary, fetched := false) -> Dictionary:
	var asset: Dictionary=client.cache.asset(int(raw.get("id",raw.get("asset_id",0))))
	asset.merge(raw,true)
	asset.provider_id="texel";asset.provider="3DTexel";asset.id=str(raw.get("id",raw.get("asset_id","")))
	asset.type="material";asset.authors=Credits.authors(asset)
	asset.source_metadata=preload("res://addons/3dtexel/providers/texel/cache.gd").public_asset(raw)
	asset.retrieved_utc=Time.get_datetime_string_from_system(true) if fetched else raw.get("retrieved_utc","")
	asset.license=Credits.license_record(asset.get("license",""))
	asset.variants=variants(asset)
	return asset
func variants(asset: Dictionary) -> Array:
	var sizes := Credits.available_resolutions(asset);var result := []
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
	var parts := cursor.split(":");var source := parts[0] if parts.size()>1 else "pbr";var page := int(parts[1]) if parts.size()>1 else 1
	var data: Dictionary=await client.json_request("/assets/search?q=%s&type=%s&page=%s&per_page=50" % [query.uri_encode(),source,page])
	if data.has("error"):return data
	var items := []
	for raw: Dictionary in data.get("items",[]):
		items.append(normalize(raw,true))
		var url := str(raw.get("thumbnail",""))
		if not url.is_empty():client.allowed_thumbnails[url]=true
	var next_cursor := "%s:%s" % [source,page+1] if page*50<int(data.get("total",0)) and page<50 else ("ai-pbr:1" if source=="pbr" else "")
	return {"items":items,"next_cursor":next_cursor}
func refresh_asset(asset: Dictionary) -> Dictionary:
	if not network_allowed:return {"error":"Metadata refresh requires explicit action."}
	sync_network();var data: Dictionary=await client.json_request("/assets/%s" % int(asset.id))
	if data.has("error"):return data
	return normalize(await client.enrich_asset(data,true),true)
func resolve_download(asset: Dictionary,variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	sync_network();var fresh: Dictionary=await client.json_request("/assets/%s" % int(asset.id))
	if fresh.has("error"):return fresh
	fresh=await client.enrich_asset(fresh)
	if not Importer.free_asset(fresh):return {"error":"Current price is not free; no download requested."}
	var response: Dictionary=await client.json_request("/assets/%s/download" % int(asset.id),HTTPClient.METHOD_POST,{"max_credits":0,"resolution":variant})
	if response.has("error"):return response
	if int(response.get("charged_credits",0))!=0:return {"error":"Unexpected charged response."}
	var files: Dictionary=response.get("files",{})
	fresh.license=response.get("license",fresh.get("license",{}))
	var maps := {}
	for role in Importer.MAPS:
		var url := Importer.file_url(files.get(role,""))
		if not url.is_empty():maps[role]=url
	return {"kind":"material","asset":normalize(fresh,true),"variant":str(files.get("resolution",variant)),"maps":maps,"normal_format":files.get("normal_format","opengl"),"material_props":files.get("material_props",{})}
func thumbnail(url: String) -> Texture2D:
	sync_network();return await client.thumbnail(url)
func get_bytes(url: String,destination: String,limit: int) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	return await client.get_bytes(url,destination,limit)
func check_connection() -> Dictionary:return await client.json_request("/me")
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
