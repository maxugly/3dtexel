@tool
extends RefCounted
## Local import receipts, separate from provider metadata. Never contacts a site.
const Credits = preload("res://addons/3dtexel/credits.gd")
var root := "user://asset_browser/imports"
var records := {}
var loaded := false
static func identity(asset: Dictionary) -> String:
	return str(asset.get("provider_id",""))+":"+str(asset.get("id",asset.get("asset_id","")))
func load_index() -> void:
	if loaded:return
	loaded=true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if FileAccess.file_exists(root.path_join("imports.json")):
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("imports.json")))
		if value is Dictionary:records=value
func save() -> Error:
	load_index();return Credits.write_json(root.path_join("imports.json"),records)
func record_import(asset: Dictionary, actual: String, folder: String, requested := "") -> Error:
	load_index()
	if actual.is_empty() or not FileAccess.file_exists(folder.path_join("provenance.json")):return ERR_INVALID_DATA
	var entries: Dictionary=records.get(identity(asset),{})
	entries[actual]={"folder":folder,"requested":requested,"imported_utc":Time.get_datetime_string_from_system(true)}
	records[identity(asset)]=entries
	return save()
func versions(asset: Dictionary) -> Dictionary:
	load_index();var found := {}
	for version in records.get(identity(asset),{}):
		var entry: Dictionary=records[identity(asset)][version]
		var folder := str(entry.get("folder",""))
		if FileAccess.file_exists(folder.path_join("provenance.json")) and (FileAccess.file_exists(folder.path_join("material.res")) or FileAccess.file_exists(folder.path_join("import_receipt.json"))):found[version]=entry.duplicate(true)
	return found
func has_version(asset: Dictionary, version: String) -> bool:return versions(asset).has(version)
func scan(folder: String, depth := 6) -> void:
	load_index()
	if depth<0:return
	var directory := DirAccess.open(folder)
	if not directory:return
	var provenance := folder.path_join("provenance.json")
	if FileAccess.file_exists(provenance):
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(provenance))
		if value is Dictionary:
			var provider_id := str(value.get("provider_id",""))
			if provider_id.is_empty() and value.get("provider")=="3DTexel":provider_id="texel"
			var id: Variant=value.get("asset_id")
			if not provider_id.is_empty() and id!=null:
				var asset := {"provider_id":provider_id,"id":str(id)}
				var version := str(value.get("returned_resolution",value.get("variant",folder.get_file())))
				if not version.is_empty():
					var entries: Dictionary=records.get(identity(asset),{})
					entries[version]={"folder":folder,"requested":value.get("requested_resolution",""),"imported_utc":value.get("imported_utc","")};records[identity(asset)]=entries
	for name in directory.get_directories():
		if not name.begins_with(".") and name!="_source" and name!="live-verification":scan(folder.path_join(name),depth-1)
