@tool
extends RefCounted
## Pure reported-metadata -> file choices. No guessed variants or URL fallbacks.
const Importer = preload("res://addons/3dtexel/importer.gd")
static func offers(asset: Dictionary,fields: Array=[]) -> Array:
	var source: Dictionary=asset.get("source_metadata",asset)
	var listed: Variant=source.get("files",asset.get("files",[]))
	var result := [];var seen := {}
	if listed is Array:
		for entry in listed:
			if not entry is Dictionary:continue
			var key := str(entry.get("format","")) if asset.get("type")=="model" else str(entry.get("resolution",entry.get("id","")))
			if key.is_empty():key=str(entry.get("filename","")).get_basename()
			add(result,seen,asset,key,str(entry.get("label",key.to_upper())),str(entry.get("url","")),str(entry.get("filename","")))
	elif listed is Dictionary:
		for key in listed:
			var entry: Variant=listed[key]
			var url := str(entry.get("url","")) if entry is Dictionary else str(entry)
			var filename := str(entry.get("filename","")) if entry is Dictionary else ""
			add(result,seen,asset,str(key),str(key).to_upper(),url,filename)
	# Providers pass field mappings in priority order, keeping existing choice IDs.
	for spec in fields:
		var url := str(source.get(spec[0],""))
		if spec[0]=="thumbnail":url=str(asset.get("thumbnail",""))
		add(result,seen,asset,str(spec[1]),str(spec[2]),url,"")
	return result
static func add(result: Array,seen: Dictionary,asset: Dictionary,key: String,label: String,url: String,filename: String) -> void:
	var id := Importer.slug(key)
	if id.is_empty() or seen.has(id) or not url.begins_with("https://"):return
	if filename.is_empty():
		var extension := url.get_slice("?",0).get_slice("#",0).get_extension().to_lower()
		if extension.is_empty():return # Do not invent a format for an opaque URL.
		filename=Importer.slug(str(asset.get("id","asset")))+"_"+id+"."+extension
	if filename!=filename.get_file() or ".." in filename or ":" in filename or "\\" in filename:return
	seen[id]=true
	result.append({"id":id,"label":label,"kind":"files","confirmed":true,"files":[{"filename":filename,"url":url}]})
static func variants(offers: Array) -> Array:
	var result := []
	for offer in offers:
		var item: Dictionary=offer.duplicate(true);item.erase("files");result.append(item)
	return result
static func plan(asset: Dictionary,requested: String,offers: Array) -> Dictionary:
	if offers.is_empty():return {"error":"The source has not reported downloadable files for this asset."}
	var target := requested if not requested.is_empty() else str(offers[0].id)
	for offer in offers:
		if str(offer.id)==target:return {"kind":"files","asset":asset,"variant":target,"files":offer.files.duplicate(true)}
	return {"error":"The requested version is not reported by this asset; no file was substituted."}
