@tool
extends RefCounted
## Standalone native Godot material preparation and optional Terrain Auto Import handoff.
const Credits = preload("res://addons/3dtexel/credits.gd")
const MAPS := ["albedo","normal","roughness","height","ao","metallic"]
static func slug(value: String) -> String:
	var regex := RegEx.create_from_string("[^a-z0-9]+")
	return regex.sub(value.to_lower(),"_",true).strip_edges().trim_prefix("_").trim_suffix("_").left(70)
static func extension(url: String) -> String:
	var ext := url.get_slice("?",0).get_extension().to_lower()
	return ext if ext in ["png","jpg","jpeg","webp","tga","exr","hdr","dds"] else "png"
static func file_url(value: Variant) -> String:
	if value is String: return value
	if value is Dictionary: return str(value.get("url",value.get("download_url","")))
	return ""
static func free_asset(asset: Dictionary) -> bool:
	var price: Dictionary = asset.get("price",{})
	return price.get("free",false) == true and int(price.get("credits",0)) == 0
static func write_json(path: String, value: Dictionary) -> Error:
	var file := FileAccess.open(path+".pending",FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value,"\t"));file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".pending"),ProjectSettings.globalize_path(path))
static func pack_image(path: String, flip_green := false) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if not image: return null
	if image.is_compressed() and image.decompress() != OK: return null
	image.convert(Image.FORMAT_RGBA8)
	if flip_green:
		var bytes := image.get_data()
		for i in range(1,bytes.size(),4): bytes[i] = 255-bytes[i]
		image = Image.create_from_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,bytes)
	image.generate_mipmaps()
	if image.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_RGBA) != OK: return null
	return image
static func make_material(folder: String, maps: Dictionary, normal_format: String, props := {}) -> Dictionary:
	var material := StandardMaterial3D.new()
	material.resource_name = folder.get_file()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness = float(props.get("roughness_mult",1.0))
	material.metallic = float(props.get("metallic",0.0))
	material.metallic_specular = float(props.get("specular",0.5))
	var sizes := {}
	for role in maps:
		var image := pack_image(folder.path_join(maps[role]), role == "normal" and normal_format.to_lower() == "directx")
		if not image: return {"error":"Cannot decode/compress the %s map." % role}
		var texture := ImageTexture.create_from_image(image)
		var texture_path := folder.path_join(role+"_texture.res")
		if ResourceSaver.save(texture,texture_path,ResourceSaver.FLAG_COMPRESS) != OK: return {"error":"Cannot save the compressed %s texture." % role}
		texture.take_over_path(texture_path)
		sizes[role] = [image.get_width(),image.get_height()]
		match role:
			"albedo": material.albedo_texture = texture
			"normal": material.normal_enabled = true; material.normal_texture = texture
			"roughness": material.roughness_texture = texture; material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			"ao": material.ao_enabled = true; material.ao_texture = texture; material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			"height": material.heightmap_enabled = false; material.heightmap_texture = texture
			"metallic": material.metallic_texture = texture; material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var path := folder.path_join("material.res")
	if ResourceSaver.save(material,path,ResourceSaver.FLAG_COMPRESS) != OK: return {"error":"Cannot save the native material."}
	return {"material":path,"dimensions":sizes}
static func terrain_handoff(folder: String, maps: Dictionary, asset: Dictionary, normal_format: String, inbox: String) -> Dictionary:
	if not inbox.begins_with("res://") or ".." in inbox: return {"error":"Terrain inbox must be inside res://."}
	var target := inbox.path_join(slug(str(asset.get("provider_id","3dtexel")))).path_join(slug(str(asset.id))+"_"+str(asset.id).sha256_text().left(12)).path_join(folder.get_file())
	var source := target.path_join("_source")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source))
	var manifest_maps := {}
	for role in maps:
		var name: String = str(maps[role]).get_file()
		var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(folder.path_join(maps[role])),ProjectSettings.globalize_path(source.path_join(name)))
		if error != OK: return {"error":"Could not copy terrain source maps."}
		manifest_maps[role] = "_source/"+name
	var record := Credits.asset_record(asset)
	var credit_error := Credits.write_json(target.path_join("asset.credits.json"),record)
	if credit_error!=OK:return {"error":"Cannot preserve terrain credits."}
	var manifest := {"credits":record,"credits_sidecar":"asset.credits.json","name":"%s (%s source)" % [asset.title,folder.get_file().to_upper()],"maps":manifest_maps,"normal_format":normal_format,"source_url":asset.get("url",""),"provider":asset.get("provider",asset.get("provider_id","Unknown")),"asset_id":asset.id,"license":asset.get("license","")}
	# Final atomic manifest publishes a complete set; watcher ignores _source while copying.
	if write_json(target.path_join("terrain_import.json"),manifest) != OK: return {"error":"Cannot publish terrain manifest."}
	return {"manifest":target.path_join("terrain_import.json")}
