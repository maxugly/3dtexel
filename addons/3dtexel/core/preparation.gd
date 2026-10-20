@tool
extends Node
signal progress(message: String)
const Importer = preload("res://addons/3dtexel/importer.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Files = preload("res://addons/3dtexel/core/file_preparation.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
var registry: Node
var output_directory := "res://AssetLibrary"
var send_to_terrain := false
var terrain_inbox := "res://assets/terrain/inbox"
func prepare(asset: Dictionary, requested: String) -> Dictionary:
	if not output_directory.begins_with("res://") or ".." in output_directory:return {"error":"Output must be inside res://."}
	if requested.is_empty() or requested!=Importer.slug(requested):return {"error":"Variant ID must be a safe lowercase slug."}
	if int(Policy.evaluate(asset).status)==Policy.Status.BLOCKED:return {"error":"Asset is blocked by project license/entitlement policy."}
	var provider: Node=registry.provider_for(asset)
	if not provider or not provider.enabled:return {"error":"Provider is disabled or unavailable."}
	if registry.get("inventory")!=null:
		var imports: Dictionary=registry.inventory.versions(asset)
		if imports.has(requested):return reuse_local(str(imports[requested].folder),asset,requested)
	var base := output_directory.path_join(str(provider.descriptor().id)).path_join("%s_%s" % [Importer.slug(str(asset.title)),Importer.slug(str(asset.id))+"_"+str(asset.id).sha256_text().left(12)])
	var folder := base.path_join(requested)
	var alias_path := base.path_join("request_"+requested+".json")
	if FileAccess.file_exists(alias_path):
		var alias: Variant=JSON.parse_string(FileAccess.get_file_as_string(alias_path))
		if alias is Dictionary:folder=base.path_join(Importer.slug(str(alias.get("returned_resolution",requested))))
	if FileAccess.file_exists(folder.path_join("provenance.json")) and (FileAccess.file_exists(folder.path_join("material.res")) or FileAccess.file_exists(folder.path_join("import_receipt.json"))):
		return reuse_local(folder,asset,requested)
	var legacy: String=provider.legacy_folder(output_directory,asset,requested)
	if not legacy.is_empty() and FileAccess.file_exists(legacy.path_join("provenance.json")) and FileAccess.file_exists(legacy.path_join("material.res")):return reuse_local(legacy,asset,requested)
	progress.emit("Resolving download…")
	var plan: Dictionary=await provider.resolve_download(asset,requested)
	if plan.has("error"):return plan
	var previous_id := str(asset.id);var previous_provider := str(asset.get("provider_id",""))
	asset=plan.get("asset",asset)
	if str(asset.get("provider_id",""))!=previous_provider or str(asset.get("id",""))!=previous_id:return {"error":"Provider returned a different asset identity."}
	if int(Policy.evaluate(asset).status)==Policy.Status.BLOCKED:return {"error":"Updated metadata is blocked by project policy."}
	registry.index_assets([asset])
	var files: Dictionary=plan.get("maps",{})
	var actual := Importer.slug(str(plan.get("variant",requested)))
	if actual.is_empty():return {"error":"Missing returned variant."}
	folder=base.path_join(actual)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	Importer.write_json(alias_path,{"requested_resolution":requested,"returned_resolution":actual})
	if FileAccess.file_exists(folder.path_join("provenance.json")) and (FileAccess.file_exists(folder.path_join("material.res")) or FileAccess.file_exists(folder.path_join("import_receipt.json"))):return reuse_local(folder,asset,requested)
	if plan.get("kind","")=="files":
		var handler := Files.new();add_child(handler)
		var prepared: Dictionary=await handler.prepare(provider,folder,asset,plan)
		handler.queue_free()
		if not prepared.has("error"):remember(asset,actual,folder,requested)
		return prepared
	if plan.get("kind","")!="material":return {"error":"Unsupported preparation kind; expected material or files."}
	var source := folder.path_join("_source")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source))
	var ignore := FileAccess.open(source.path_join(".gdignore"),FileAccess.WRITE)
	if ignore:ignore.close()
	var maps := {};var hashes := {}
	for role in Importer.MAPS:
		var url := Importer.file_url(files.get(role,""))
		if url.is_empty():continue
		var relative := "_source/%s.%s" % [role,Importer.extension(url)]
		var destination := folder.path_join(relative)
		progress.emit("Downloading %s · %s…" % [asset.title,role])
		var result: Dictionary = await provider.get_bytes(url,ProjectSettings.globalize_path(destination+".pending"),256*1024*1024)
		if result.has("error"):return result
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(destination+".pending"),ProjectSettings.globalize_path(destination))!=OK:
			return {"error":"Cannot finish downloaded map."}
		maps[role]=relative;hashes[role]=FileAccess.get_sha256(destination)
	if not maps.has("albedo"):return {"error":"No supported albedo map returned."}
	progress.emit("Packing mipmaps and GPU-compressed materials…")
	await get_tree().process_frame
	var normal_format := str(plan.get("normal_format","opengl"))
	var result := Importer.make_material(folder,maps,normal_format,plan.get("material_props",{}))
	if result.has("error"):return result
	var provenance := {"provider":asset.get("provider",asset.get("provider_id","")),"provider_id":asset.get("provider_id",""),"asset_id":asset.id,"title":asset.title,"source_url":asset.get("url",""),"license":asset.get("license",{}),"requested_resolution":requested,"returned_resolution":actual,"normal_format":normal_format,"maps":maps,"sha256":hashes,"dimensions":result.dimensions,"imported_utc":Time.get_datetime_string_from_system(true),"charged_credits":0}
	var credit_asset := asset.duplicate(true)
	credit_asset.license=provenance.license
	var credits := Credits.asset_record(credit_asset)
	credits.requested_resolution=requested;credits.returned_resolution=actual;credits.sha256=hashes;credits.dimensions=result.dimensions
	provenance.merge(credits,true)
	if Importer.write_json(folder.path_join("provenance.json"),provenance)!=OK or Credits.write_asset_sidecars(folder,credits)!=OK:return {"error":"Could not save provenance or credits."}
	var note := ""
	if send_to_terrain:
		var terrain := Importer.terrain_handoff(folder,maps,asset,normal_format,terrain_inbox)
		note=" Terrain handoff failed: "+str(terrain.error) if terrain.has("error") else " Sent to Terrain imports at its current output size."
	remember(asset,actual,folder,requested)
	return {"note":"%s prepared as %s%s" % [requested.to_upper(),actual.to_upper(),note]}
func reuse_local(folder: String, asset: Dictionary, requested: String) -> Dictionary:
	var provenance: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))
	if provenance is not Dictionary:return {"error":"Existing provenance needs review."}
	var credit_source: Dictionary=provenance.duplicate(true)
	for key in asset:
		var value: Variant=asset[key]
		if value==null:continue
		if value is String and value.is_empty():continue
		if value is Array and value.is_empty():continue
		credit_source[key]=value
	credit_source.id=asset.id;credit_source.title=asset.title;credit_source.url=asset.get("url",provenance.get("source_url",""))
	var credits := Credits.asset_record(credit_source)
	if Credits.write_asset_sidecars(folder,credits)!=OK:return {"error":"Could not update local credits."}
	if send_to_terrain and not provenance.get("maps",{}).is_empty():
		var result := Importer.terrain_handoff(folder,provenance.get("maps",{}),credit_source,str(provenance.get("normal_format","opengl")),terrain_inbox)
		if result.has("error"):return result
	remember(asset,str(provenance.get("returned_resolution",folder.get_file())),folder,requested)
	return {"note":requested.to_upper()+" reused locally · "+str(provenance.get("returned_resolution",folder.get_file())).to_upper()}

func remember(asset: Dictionary,actual: String,folder: String,requested: String) -> void:
	if registry.get("inventory")!=null:registry.inventory.record_import(asset,actual,folder,requested)
