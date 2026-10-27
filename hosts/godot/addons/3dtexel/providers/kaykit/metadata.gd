@tool
extends RefCounted
## Official repository metadata only; no guessed files, prices or licenses.
const SourceLicense = preload("res://addons/3dtexel/core/source_license.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
const OWNER := "KayKit-Game-Assets"
static func official(repository: Dictionary) -> bool:
	var name := str(repository.get("name",""))
	var owner: Variant=repository.get("owner",{})
	return owner is Dictionary and str(owner.get("login",""))==OWNER and not bool(repository.get("fork",false)) and name.is_valid_filename() and repository.get("full_name")==OWNER+"/"+name and repository.get("html_url")=="https://github.com/"+OWNER+"/"+name
static func source_url(url: String,repository: Dictionary) -> bool:
	return official(repository) and url.begins_with("https://raw.githubusercontent.com/"+str(repository.full_name)+"/")
static func license_record(text: String) -> Dictionary:
	var declaration := false
	for line in text.split("\n"):
		var value := line.strip_edges()
		if value.to_lower().begins_with("license:"):
			declaration=true
			var inline_value := value.substr(value.find(":")+1).strip_edges()
			var inline_record := SourceLicense.record(inline_value)
			if inline_record.id!="unknown":return inline_record
		elif declaration and not value.is_empty():
			return SourceLicense.record(value)
	return SourceLicense.record("")
static func pack(repository: Dictionary,entries: Array,license_text: String,license_url: String) -> Dictionary:
	if not official(repository):return {}
	var name := str(repository.name)
	var id := Importer.slug(name)
	# Retain the existing Dungeon Remastered catalog identity.
	if name=="KayKit-Dungeon-Remastered-1.0":id="dungeon_pack"
	var image := ""
	for entry in entries:
		if entry is Dictionary and entry.get("type")=="file" and str(entry.get("name","")).to_lower() in ["icon.png","preview.png","thumbnail.png"] and source_url(str(entry.get("source_file_url","")),repository):
			image=str(entry.source_file_url);break
	var license := license_record(license_text) if source_url(license_url,repository) else SourceLicense.record("")
	var authors := []
	if license_text.contains("Created/distributed by Kay Lousberg"):
		authors=[{"name":"Kay Lousberg","url":"https://kaylousberg.com/"}]
	var branch := str(repository.get("default_branch",""))
	var archive := str(repository.get("archive_url",""))
	var files := []
	if not branch.is_empty() and archive=="https://api.github.com/repos/"+str(repository.full_name)+"/{archive_format}{/ref}":
		files=[{"filename":name+".zip","url":archive.replace("{archive_format}","zipball").replace("{/ref}","/"+branch.uri_encode()),"format":"zip"}]
	return {"id":id,"title":"KayKit - "+name.trim_prefix("KayKit-").replace("-"," "),"url":repository.html_url,"description":repository.get("description","") if repository.get("description")!=null else "","thumbnail":image,"tags":repository.get("topics",[]),"license":license,"authors":authors,"price":{"free":true,"credits":0},"files":files,"repository":repository,"license_text":license_text,"license_source_url":license_url}
