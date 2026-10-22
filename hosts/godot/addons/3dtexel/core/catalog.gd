@tool
extends RefCounted
## Public, portable metadata only. Provider namespaces prevent ID collisions.
const Credits = preload("res://addons/3dtexel/credits.gd")
const Sanitizer = preload("res://addons/3dtexel/core/public_metadata.gd")
var root := "user://asset_browser/catalog"
var records := {}
var loaded := false
func load_catalog() -> void:
	if loaded:return
	loaded=true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if FileAccess.file_exists(root.path_join("assets.json")):
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("assets.json")))
		if value is Dictionary:records=value
func upsert(asset: Dictionary) -> void:
	load_catalog()
	var identity := str(asset.get("provider_id",""))+":"+str(asset.get("id",""))
	if identity.begins_with(":") or identity.ends_with(":"):return
	var clean := {}
	for key in ["provider_id","provider","id","title","description","url","thumbnail","type","price","license","licenses","authors","attribution_text","metadata_source_url","resolutions","variants","download","tags","license_status","license_reason","selected_license","source_metadata","retrieved_utc"]:
		if asset.has(key):clean[key]=Sanitizer.sanitize(asset[key])
	var prior: Dictionary=records.get(identity,{})
	prior.merge(clean,true);records[identity]=prior
func save() -> Error:
	load_catalog();return Credits.write_json(root.path_join("assets.json"),records)
func search(provider_ids: Array, query: String, category: String, free_only: bool, license_name: String) -> Array:
	load_catalog();var found := []
	for asset: Dictionary in records.values():
		if asset.get("provider_id","") not in provider_ids:continue
		if category!="all" and asset.get("type","material")!=category:continue
		if free_only and not asset.get("price",{}).get("free",false):continue
		if license_name!="Any license" and Credits.license_record(asset.get("license","")).name!=license_name:continue
		var text := (str(asset.get("title",""))+" "+str(asset.get("description",""))+" "+JSON.stringify(asset.get("tags",[]))).to_lower()
		var matches := true
		for word in query.to_lower().split(" ",false):
			if word not in text:matches=false;break
		if matches:found.append(asset.duplicate(true))
	found.sort_custom(func(a,b):return (str(a.title)+str(a.provider_id)+str(a.id)).naturalnocasecmp_to(str(b.title)+str(b.provider_id)+str(b.id))<0)
	return found
