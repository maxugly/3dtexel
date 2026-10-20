@tool
extends Node
## Generic source imports. Archives remain intact; no unsafe automatic extraction.
const Credits = preload("res://addons/3dtexel/credits.gd")
func prepare(provider: Node,folder: String,asset: Dictionary,plan: Dictionary) -> Dictionary:
	var files: Array=plan.get("files",[])
	if files.is_empty():return {"error":"Provider returned no files."}
	var names := {};var supported := ["glb","gltf","obj","fbx","blend","png","jpg","jpeg","webp","tga","exr","hdr","wav","ogg","mp3","zip","7z","tar","gz","txt","md","pdf"]
	for entry: Dictionary in files:
		var name := str(entry.get("filename",""))
		if name.is_empty() or name!=name.get_file() or name.begins_with(".") or ":" in name or "\\" in name or ".." in name or name.get_extension().to_lower() not in supported or names.has(name.to_lower()):return {"error":"Unsafe, unsupported or duplicate source filename."}
		if not str(entry.get("url","")).begins_with("https://"):return {"error":"Only HTTPS source downloads are supported."}
		names[name.to_lower()]=true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var hashes := {};var record := Credits.asset_record(asset)
	for entry: Dictionary in files:
		var path := folder.path_join(str(entry.filename))
		if FileAccess.file_exists(path):return {"error":"Partial import exists; preserved for review instead of overwritten."}
		var result: Dictionary=await provider.get_bytes(str(entry.url),ProjectSettings.globalize_path(path+".pending"),256*1024*1024)
		if result.has("error"):return result
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".pending"),ProjectSettings.globalize_path(path))!=OK:return {"error":"Cannot finish source file."}
		hashes[str(entry.filename)]=FileAccess.get_sha256(path)
		if Credits.write_json(path+".credits.json",record)!=OK:return {"error":"Cannot preserve file credits."}
	record.sha256=hashes;record.returned_resolution=plan.get("variant","original");record.imported_utc=Time.get_datetime_string_from_system(true)
	for entry: Dictionary in files:
		if Credits.write_json(folder.path_join(str(entry.filename))+".credits.json",record)!=OK:return {"error":"Cannot preserve final file credits."}
	for name in ["asset.credits.json","provenance.json","import_receipt.json"]:
		if Credits.write_json(folder.path_join(name),record)!=OK:return {"error":"Cannot save import metadata."}
	return {"note":"Source files imported with credits. Archives are preserved intact; extract through a reviewed importer."}
