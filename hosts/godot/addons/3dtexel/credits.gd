@tool
extends RefCounted
## Public attribution records, reusable by importers and saved-scene manifests.
static func authors(asset: Dictionary) -> Array:
	var result := []
	for key in ["authors","author","creators","creator"]:
		var value: Variant=asset.get(key,[])
		var values: Array=value if value is Array else [value]
		for person in values:
			var entry := {}
			if person is String and not person.strip_edges().is_empty():entry={"name":person.strip_edges(),"url":""}
			elif person is Dictionary:entry={"name":str(person.get("name",person.get("display_name",""))),"url":str(person.get("url",""))}
			if not entry.is_empty() and not entry.name.is_empty() and entry not in result:result.append(entry)
	return result
static func license_record(value: Variant) -> Dictionary:
	var result: Dictionary=value.duplicate(true) if value is Dictionary else {"name":str(value)}
	if not result.has("name"):result.name=str(result.get("id","Unknown"))
	if str(result.name).strip_edges().is_empty():result.name="Unknown"
	if not result.has("attribution_required"):
		var name := str(result.name).to_lower()
		result.attribution_required=false if "cc0" in name else (true if "cc-by" in name or "cc by" in name else null)
	return result
static var _res_regex: RegEx
static func available_resolutions(asset: Dictionary) -> Array[String]:
	var result: Array[String]=[]
	var values := []
	for key in ["resolutions","available_resolutions","formats"]:
		if asset.has(key):values.append(asset[key])
		if asset.get("download") is Dictionary and asset.download.has(key):values.append(asset.download[key])
	if values.is_empty():return result
	if _res_regex==null:_res_regex=RegEx.create_from_string("(?i)(?<![0-9])(1|2|4|8|16)\\s*k\\b")
	for value in values:
		for match in _res_regex.search_all(JSON.stringify(value)):
			var size := match.get_string(1)+"k"
			if size not in result:result.append(size)
	result.sort_custom(func(a,b):return int(a)<int(b))
	return result
static func asset_record(asset: Dictionary) -> Dictionary:
	var people := authors(asset)
	var license := license_record(asset.get("license",""))
	var record := {"schema_version":1,"provider":str(asset.get("provider","Unknown")),"asset_id":asset.get("asset_id",asset.get("id",null)),"title":str(asset.get("title",asset.get("name","Untitled"))),"source_url":str(asset.get("source_url",asset.get("url",""))),"authors":people,"author_status":"reported" if not people.is_empty() else "not_supplied","license":license,"metadata_source_url":str(asset.get("metadata_source_url",asset.get("url",asset.get("source_url","")))),"attribution_text":str(asset.get("attribution",asset.get("attribution_text",""))),"review_required":people.is_empty() or license.name=="Unknown" or license.get("attribution_required")==null or (license.get("attribution_required")==true and str(license.get("url","")).is_empty())}
	var policy := preload("res://addons/3dtexel/core/license_policy.gd").evaluate(asset)
	record.license_status=policy.status;record.license_reason=policy.reason
	for key in ["provider_id","licenses","selected_license","license_status","license_reason","source_metadata","retrieved_utc"]:
		if asset.has(key):record[key]=asset[key]
	return record
static func write_json(path: String, value: Dictionary) -> Error:
	var file := FileAccess.open(path+".pending",FileAccess.WRITE)
	if not file:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(preload("res://addons/3dtexel/core/public_metadata.gd").sanitize(value),"\t"));file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".pending"),ProjectSettings.globalize_path(path))
static func write_asset_sidecars(folder: String, record: Dictionary) -> Error:
	var paths := ["asset.credits.json","material.res.credits.json"]
	var directory := DirAccess.open(folder)
	if directory:
		for name in directory.get_files():
			if name.ends_with("_texture.res") or name.get_extension().to_lower() in ["glb","gltf","obj","fbx","blend","png","jpg","jpeg","webp","tga","exr","hdr","wav","ogg","mp3","zip","7z","tar","gz","txt","md","pdf"]:paths.append(name+".credits.json")
	var sources := DirAccess.open(folder.path_join("_source"))
	if sources:
		for name in sources.get_files():
			if not name.begins_with(".") and not name.ends_with(".credits.json") and not name.ends_with(".pending"):paths.append("_source/"+name+".credits.json")
	for name in paths:
		var error := write_json(folder.path_join(name),record)
		if error!=OK:return error
	return OK
static func collect_scene(scene_path: String) -> Dictionary:
	var todo: Array[String]=[scene_path]
	var seen := {};var assets := {};var missing := []
	while not todo.is_empty():
		var path: String=todo.pop_back()
		if seen.has(path):continue
		seen[path]=true
		var sidecar := path+".credits.json"
		var record: Variant=null
		if path!=scene_path and FileAccess.file_exists(sidecar):record=JSON.parse_string(FileAccess.get_file_as_string(sidecar))
		elif FileAccess.file_exists(path.get_base_dir().path_join("asset.credits.json")):record=JSON.parse_string(FileAccess.get_file_as_string(path.get_base_dir().path_join("asset.credits.json")))
		if record is Dictionary:
			var normalized := asset_record(record)
			var people: Array=normalized.authors
			var license: Dictionary=normalized.license
			var needs_review: bool=normalized.review_required or bool(record.get("review_required",false))
			normalized.merge(record,true)
			normalized.authors=people;normalized.license=license;normalized.review_required=needs_review
			record=normalized
			var asset_identity: Variant=record.get("asset_id")
			if asset_identity==null:asset_identity=record.get("source_url",sidecar)
			if str(asset_identity).is_empty():asset_identity=sidecar
			var identity := str(record.get("provider",""))+":"+str(asset_identity)
			if not assets.has(identity):assets[identity]=record.duplicate(true);assets[identity].used_by=[]
			assets[identity].used_by.append(path)
		elif path.get_extension() in ["res","png","jpg","jpeg","webp","dds","glb","gltf","fbx","obj","hdr","exr"]:missing.append(path)
		for dependency: String in ResourceLoader.get_dependencies(path):
			var candidate: String=dependency.get_slice("::",dependency.get_slice_count("::")-1)
			if candidate.begins_with("uid://"):
				var id := ResourceUID.text_to_id(candidate)
				candidate=ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
			if candidate.begins_with("res://"):todo.append(candidate)
	return {"schema_version":1,"scene":scene_path,"saved_dependencies_only":true,"generated_utc":Time.get_datetime_string_from_system(true),"assets":assets.values(),"missing_sidecars":missing,"note":"Runtime-loaded assets require separate inclusion. Missing metadata remains marked for review."}
static func write_scene(scene_path: String) -> Dictionary:
	if not FileAccess.file_exists(scene_path):return {"error":"Save the scene first."}
	var result := collect_scene(scene_path)
	var path := scene_path+".credits.json"
	if write_json(path,result)!=OK:return {"error":"Cannot save scene credits."}
	var text := "# Scene credits\n\nSource: "+scene_path+"\n\n"
	for asset in result.assets:
		var names := []
		for person in asset.get("authors",[]):names.append(str(person.get("name","")))
		text+="- "+str(asset.get("title","Asset"))+" — "+(", ".join(names) if not names.is_empty() else "AUTHOR NOT SUPPLIED")+" — "+str(license_record(asset.get("license","")).name)+" — "+str(asset.get("source_url",""))+"\n"
		var license := license_record(asset.get("license",""))
		if not str(license.get("url","")).is_empty():text+="  License: "+str(license.url)+"\n"
		if not str(asset.get("attribution_text","")).is_empty():text+="  "+str(asset.attribution_text)+"\n"
		if asset.get("review_required",false):text+="  REVIEW: attribution metadata incomplete.\n"
	text+="\nMissing sidecars: %s. Check JSON for review flags and dynamic-asset limitations.\n" % result.missing_sidecars.size()
	var file := FileAccess.open(scene_path+".credits.md",FileAccess.WRITE)
	if file:file.store_string(text);file.close()
	return {"path":path,"asset_count":result.assets.size(),"missing_count":result.missing_sidecars.size()}

static func collect_game(main_scene_path := "") -> Dictionary:
	return preload("res://addons/3dtexel/core/credits_collector.gd").collect_game(main_scene_path)

static func collect_project(res_root := "res://", ignore_dirs := []) -> Dictionary:
	return preload("res://addons/3dtexel/core/credits_collector.gd").collect_project(res_root, ignore_dirs)

static func format_markdown(collected: Dictionary, options := {}) -> String:
	return preload("res://addons/3dtexel/core/credits_collector.gd").format_markdown(collected, options)

static func export_credits(collected: Dictionary, target_path := "res://CREDITS.md", options := {}) -> Dictionary:
	return preload("res://addons/3dtexel/core/credits_collector.gd").export_credits(collected, target_path, options)

