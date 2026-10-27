@tool
extends "res://addons/3dtexel/core/provider.gd"
## Publisher-owned KayKit repositories, with reported files and per-pack terms.
const Client = preload("res://addons/3dtexel/providers/kaykit/client.gd")
const Cache = preload("res://addons/3dtexel/providers/kaykit/cache.gd")
const Metadata = preload("res://addons/3dtexel/providers/kaykit/metadata.gd")
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
var client: Node
func _init() -> void:client=Client.new();add_child(client)
func descriptor() -> Dictionary:
	return {"id":"kaykit","name":"KayKit","website":"https://kaylousberg.com/game-assets","key_env":[],"capabilities":["model","files","variants"]}
func sync_network() -> void:client.network_allowed=network_allowed;client.refreshing=refreshing
func api_key() -> String:return ""
func set_session_key(_value: String) -> void:pass
func credential_status() -> String:return "No key required."
func can_download(asset: Dictionary) -> bool:
	return Importer.free_asset(asset) and int(Policy.evaluate(asset).status) in [Policy.Status.PERMISSIVE,Policy.Status.ATTRIBUTION] and not variants(asset).is_empty()
func source_record(raw: Dictionary) -> Dictionary:
	var source: Dictionary=raw.get("source_metadata",{}).duplicate(true) if raw.get("source_metadata") is Dictionary else {}
	for field in ["id","title","url","thumbnail","description","tags","price","authors","license","files","repository","license_text","license_source_url"]:
		if raw.has(field):source[field]=raw[field]
	return source
func normalize(raw: Dictionary,fetched := false) -> Dictionary:
	var source := source_record(raw)
	var id := Importer.slug(str(source.get("id",raw.get("slug",""))))
	var asset: Dictionary=client.cache.asset(id)
	asset.merge(raw,true)
	asset.provider_id="kaykit";asset.provider="KayKit";asset.id=id;asset.type="model"
	asset.title=str(source.get("title",id.capitalize()));asset.url=str(source.get("url",""));asset.thumbnail=str(source.get("thumbnail",""))
	asset.description=str(source.get("description",""));asset.tags=source.get("tags",[]) if source.get("tags") is Array else []
	asset.price=source.get("price",{}) if source.get("price") is Dictionary else {}
	asset.authors=source.get("authors",[]) if source.get("authors") is Array else []
	asset.license=SourceLicense.record(source.get("license",""));asset.licenses=[asset.license];asset.selected_license=asset.license
	asset.attribution_text="Assets by Kay Lousberg — KayKit (%s)" % str(asset.license.name) if not asset.authors.is_empty() else "KayKit — "+str(asset.license.name)
	asset.metadata_source_url=str(source.get("license_source_url",asset.url))
	asset.source_metadata=Cache.public_asset(source)
	asset.files=source.get("files",[]) if source.get("files") is Array else []
	asset.retrieved_utc=Time.get_datetime_string_from_system(true) if fetched else str(raw.get("retrieved_utc",""))
	asset.variants=variants(asset)
	return asset
func variants(asset: Dictionary) -> Array:
	var source := source_record(asset)
	var files: Variant=source.get("files",[])
	if not files is Array:return []
	var result := [];var seen := {}
	for file in files:
		if not file is Dictionary:continue
		var filename := str(file.get("filename",""))
		if filename.is_empty() or filename!=filename.get_file() or not str(file.get("url","")).begins_with("https://") or filename.get_extension().to_lower()!="zip":continue
		var id := "zip" if files.size()==1 else Importer.slug(filename.get_basename())
		if seen.has(id):continue
		seen[id]=true;result.append({"id":id,"label":"Pack archive (ZIP)" if id=="zip" else filename,"kind":"files","confirmed":true})
	return result
func local_assets() -> Array:
	client.cache.ensure_loaded()
	var result := []
	for raw in client.cache.catalog.values():
		if raw is Dictionary:result.append(normalize(raw))
	return result
func refresh_page(query: String,category: String,cursor: String) -> Dictionary:
	if category not in ["all","model"]:return {"items":[],"next_cursor":""}
	if not network_allowed:return {"error":"Search requires explicit action."}
	if not cursor.is_empty() and (not cursor.is_valid_int() or int(cursor)<1 or int(cursor)>167):return {"error":"Invalid KayKit page cursor."}
	sync_network()
	var response: Dictionary=await client.fetch_packs(query,1 if cursor.is_empty() else int(cursor))
	if response.has("error"):return response
	var items := []
	for raw in response.get("items",[]):
		if raw is Dictionary:
			var asset := normalize(raw,true);client.cache.put_asset(asset);items.append(asset)
	return {"items":items,"next_cursor":str(response.get("next_cursor",""))}
func asset_details(asset: Dictionary) -> Dictionary:
	return normalize(asset)
func refresh_asset(asset: Dictionary) -> Dictionary:
	if not network_allowed:return {"error":"Pack details require explicit action."}
	sync_network()
	var source := source_record(asset)
	if not source.get("repository") is Dictionary:return {"error":"Search KayKit again to replace obsolete catalog metadata."}
	var result: Dictionary=await client.fetch_pack(source.repository)
	if result.has("error"):return result
	var updated := normalize(result,true)
	if updated.id!=asset.id:return {"error":"Pack identity changed; search again."}
	client.cache.put_asset(updated);return updated
func resolve_download(asset: Dictionary,variant: String) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	sync_network()
	var detailed := await refresh_asset(asset)
	if detailed.has("error"):return detailed
	if not can_download(detailed):return {"error":"This pack's license or free download availability needs review."}
	var options := variants(detailed)
	if not options.any(func(option):return option.id==variant):return {"error":"Requested KayKit variant is not reported by this pack."}
	var files: Array=source_record(detailed).get("files",[])
	for file: Dictionary in files:
		var id := "zip" if files.size()==1 else Importer.slug(str(file.filename).get_basename())
		if id==variant:return {"kind":"files","asset":detailed,"variant":variant,"files":[{"filename":str(file.filename),"url":str(file.url)}]}
	return {"error":"Requested KayKit file is missing."}
func thumbnail(url: String) -> Texture2D:
	sync_network();return await client.thumbnail(url)
func get_bytes(url: String,destination: String,limit: int) -> Dictionary:
	if not network_allowed:return {"error":"Download requires explicit action."}
	sync_network();return await client.get_bytes(url,destination,limit)
func check_connection() -> Dictionary:
	if not network_allowed:return {"error":"Connection checks require explicit action."}
	sync_network();return await client.fetch_packs("",1)
func cancel_all() -> void:client.cancel_all()
