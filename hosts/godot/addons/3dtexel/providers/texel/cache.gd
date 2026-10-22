@tool
extends RefCounted
const Credits = preload("res://addons/3dtexel/credits.gd")
var root := "user://3dtexel_cache"
var catalog := {}
var loaded := false
func ensure_loaded() -> void:
	if loaded:return
	loaded=true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if FileAccess.file_exists(root.path_join("catalog.json")):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("catalog.json")))
		if data is Dictionary:catalog=data
static func cacheable(path: String) -> bool:
	return path.begins_with("/assets/search?") or RegEx.create_from_string("^/assets/[0-9]+$").search(path)!=null
func response_path(path: String) -> String:return root.path_join(path.sha256_text()+".json")
func get_response(path: String) -> Dictionary:
	ensure_loaded()
	if not cacheable(path) or not FileAccess.file_exists(response_path(path)):return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(response_path(path)))
	return data.get("data",{}) if data is Dictionary else {}
func put_response(path: String, data: Dictionary, validators := {}) -> void:
	ensure_loaded()
	if not cacheable(path) or data.has("error"):return
	# Only public asset metadata is persisted. No account responses, keys or download links.
	var clean := {}
	if path.begins_with("/assets/search?"):
		for key in ["query","type","page","per_page","total","match"]:
			if data.has(key):clean[key]=data[key]
		clean.items=[]
		for asset: Dictionary in data.get("items",[]):clean.items.append(public_asset(asset));upsert(asset)
	else:clean=public_asset(data);upsert(data)
	var prior := response_validators(path)
	prior.merge(validators,true)
	Credits.write_json(response_path(path),{"fetched_utc":Time.get_datetime_string_from_system(true),"data":clean,"validators":prior})
	Credits.write_json(root.path_join("catalog.json"),catalog)
static func public_asset(asset: Dictionary) -> Dictionary:
	var clean := {}
	for key in ["id","asset_id","provider","title","name","type","source","url","source_url","thumbnail","description","updated","license","price","categories","tags","authors","author","creators","creator","attribution","attribution_text","resolutions","available_resolutions","formats","metadata_source_url"]:
		if asset.has(key):clean[key]=sanitize(asset[key])
	if asset.get("download") is Dictionary:
		clean.download={}
		for key in ["via_api","how","resolutions","available_resolutions","formats"]:
			if asset.download.has(key):clean.download[key]=sanitize(asset.download[key])
	return clean
static func sanitize(value: Variant) -> Variant:
	return preload("res://addons/3dtexel/core/public_metadata.gd").sanitize(value)
func upsert(asset: Dictionary) -> void:
	ensure_loaded()
	var id := str(asset.get("id",asset.get("asset_id","")))
	if id.is_empty():return
	var previous: Dictionary=catalog.get(id,{})
	var incoming := public_asset(asset)
	if incoming.get("license") is String and previous.get("license") is Dictionary and Credits.license_record(incoming.license).name==Credits.license_record(previous.license).name:incoming.license=previous.license
	previous.merge(incoming,true)
	catalog[id]=previous
func asset(id: int) -> Dictionary:
	ensure_loaded();return catalog.get(str(id),{}).duplicate(true)
func search(query: String, type: String, free_only: bool, license: String) -> Array:
	ensure_loaded()
	var result := []
	var words := query.to_lower().split(" ",false)
	for value: Dictionary in catalog.values():
		if type!="all" and value.get("type","pbr")!=type:continue
		var price: Dictionary=value.get("price",{})
		if free_only and not (price.get("free",false) and int(price.get("credits",0))==0):continue
		if license!="Any license" and str(Credits.license_record(value.get("license","")).name)!=license:continue
		var haystack := (str(value.get("title",""))+" "+str(value.get("description",""))+" "+JSON.stringify(value.get("tags",[]))).to_lower()
		var matches := true
		for word in words:
			if word not in haystack:matches=false;break
		if matches:result.append(value.duplicate(true))
	result.sort_custom(func(a,b):return str(a.get("title","")).naturalnocasecmp_to(str(b.get("title","")))<0 if a.get("title")!=b.get("title") else int(a.id)<int(b.id))
	return result
func licenses() -> Array[String]:
	ensure_loaded();var result: Array[String]=[]
	for value: Dictionary in catalog.values():
		var name := str(Credits.license_record(value.get("license","")).name)
		if name not in result:result.append(name)
	result.sort();return result
func thumbnail_path(url: String) -> String:
	ensure_loaded();return root.path_join("thumb_"+url.sha256_text()+".png")
func load_local_imports(folder: String, depth := 3) -> void:
	ensure_loaded()
	if depth<0:return
	var directory := DirAccess.open(folder)
	if not directory:return
	if FileAccess.file_exists(folder.path_join("provenance.json")):
		var item: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))
		if item is Dictionary and item.get("provider","")=="3DTexel":
			if not FileAccess.file_exists(folder.path_join("asset.credits.json")):Credits.write_asset_sidecars(folder,Credits.asset_record(item))
			item.id=item.get("asset_id",0);item.type="pbr";item.url=item.get("source_url","");item.price={"free":int(item.get("charged_credits",-1))==0,"credits":int(item.get("charged_credits",-1))};upsert(item)
	for name in directory.get_directories():
		if not name.begins_with(".") and name!="_source":load_local_imports(folder.path_join(name),depth-1)
	Credits.write_json(root.path_join("catalog.json"),catalog)

func response_validators(path: String) -> Dictionary:
	ensure_loaded()
	if not cacheable(path) or not FileAccess.file_exists(response_path(path)):return {}
	var record: Variant=JSON.parse_string(FileAccess.get_file_as_string(response_path(path)))
	return record.get("validators",{}) if record is Dictionary else {}
func conditional_headers(path: String) -> PackedStringArray:
	var values := response_validators(path);var headers := PackedStringArray()
	for pair in [["etag","If-None-Match"],["last_modified","If-Modified-Since"]]:
		var value := str(values.get(pair[0],""))
		if not value.is_empty() and value.length()<512 and "\r" not in value and "\n" not in value:headers.append(str(pair[1])+": "+value)
	return headers
