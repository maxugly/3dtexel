@tool
extends Node
## Generic source imports. Archives remain intact; no unsafe automatic extraction.
const Credits = preload("res://addons/3dtexel/credits.gd")
func prepare(provider: Node,folder: String,asset: Dictionary,plan: Dictionary) -> Dictionary:
	var files: Array=plan.get("files",[])
	if files.is_empty():return {"error":"Provider returned no files."}
	var names := {};var supported := ["glb","gltf","bin","mtl","obj","fbx","blend","stl","dae","ply","3ds","usd","usda","usdc","usdz","png","jpg","jpeg","webp","tga","tif","tiff","bmp","gif","svg","exr","hdr","wav","ogg","mp3","flac","m4a","mp4","ogv","webm","mkv","zip","7z","rar","tar","gz","tgz","txt","md","pdf"]
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
	
	# Automated Model & Audio conversions
	var convert_models := bool(ProjectSettings.get_setting("asset_browser/preparation/convert_models_to_glb", true))
	var delete_source_models := bool(ProjectSettings.get_setting("asset_browser/preparation/delete_source_models", true))
	var convert_audio := bool(ProjectSettings.get_setting("asset_browser/preparation/convert_audio_to_opus", true))
	var audio_bitrate := int(ProjectSettings.get_setting("asset_browser/preparation/audio_opus_bitrate", 128))
	var delete_source_audio := bool(ProjectSettings.get_setting("asset_browser/preparation/delete_source_audio", true))

	var blender_bin := OS.get_environment("BLENDER_BIN")
	if blender_bin.is_empty():
		for b in ["/home/m/.local/bin/blender", "/usr/bin/blender"]:
			if FileAccess.file_exists(b):
				blender_bin = b; break

	var ffmpeg_bin := OS.get_environment("FFMPEG_BIN")
	if ffmpeg_bin.is_empty():
		for fb in ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg"]:
			if FileAccess.file_exists(fb):
				ffmpeg_bin = fb; break

	for entry: Dictionary in files:
		var fname := str(entry.filename)
		var ext := fname.get_extension().to_lower()
		var source_path := folder.path_join(fname)
		var global_source := ProjectSettings.globalize_path(source_path)

		if convert_models and ext in ["blend", "obj", "fbx"] and not blender_bin.is_empty():
			var glb_name := fname.get_basename() + ".glb"
			var glb_path := folder.path_join(glb_name)
			var global_glb := ProjectSettings.globalize_path(glb_path)
			var py_script := "import bpy, mathutils\n"
			if ext == "blend":
				py_script += "bpy.ops.wm.open_mainfile(filepath='%s')\n" % global_source
			else:
				py_script += "bpy.ops.wm.read_factory_settings(use_empty=True)\n"
				if ext in ["gltf", "glb"]: py_script += "bpy.ops.import_scene.gltf(filepath='%s')\n" % global_source
				elif ext == "obj": py_script += "try:\n    bpy.ops.wm.obj_import(filepath='%s')\nexcept:\n    bpy.ops.import_scene.obj(filepath='%s')\n" % [global_source, global_source]
				elif ext == "fbx": py_script += "bpy.ops.import_scene.fbx(filepath='%s')\n" % global_source
			py_script += "m = [o for o in bpy.context.scene.objects if o.type == 'MESH']\n"
			py_script += "if m:\n    mx = min(min((o.matrix_world @ mathutils.Vector(c)).x for c in o.bound_box) for o in m)\n"
			py_script += "    Mx = max(max((o.matrix_world @ mathutils.Vector(c)).x for c in o.bound_box) for o in m)\n"
			py_script += "    my = min(min((o.matrix_world @ mathutils.Vector(c)).y for c in o.bound_box) for o in m)\n"
			py_script += "    My = max(max((o.matrix_world @ mathutils.Vector(c)).y for c in o.bound_box) for o in m)\n"
			py_script += "    mz = min(min((o.matrix_world @ mathutils.Vector(c)).z for c in o.bound_box) for o in m)\n"
			py_script += "    off = mathutils.Vector((-(mx+Mx)/2.0, -(my+My)/2.0, -mz))\n"
			py_script += "    for o in [o for o in bpy.context.scene.objects if o.parent is None]: o.location += off\n"
			py_script += "bpy.ops.export_scene.gltf(filepath='%s', export_format='GLB', use_selection=False, export_apply=False)\n" % global_glb

			var script_file := "user://blender_conv.py"
			var sf := FileAccess.open(script_file, FileAccess.WRITE)
			if sf:
				sf.store_string(py_script); sf.close()
				var global_sf := ProjectSettings.globalize_path(script_file)
				var output_arr := []
				OS.execute(blender_bin, ["--background", "--python", global_sf], output_arr, true)
				DirAccess.remove_absolute(global_sf)
				if FileAccess.file_exists(glb_path) and FileAccess.get_file_as_bytes(glb_path).size() > 0:
					hashes[glb_name] = FileAccess.get_sha256(glb_path)
					Credits.write_json(glb_path + ".credits.json", record)
					if delete_source_models:
						DirAccess.remove_absolute(global_source)
						DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path + ".credits.json"))
						hashes.erase(fname)

		elif convert_audio and ext in ["wav", "flac", "aiff"] and not ffmpeg_bin.is_empty():
			var opus_name := fname.get_basename() + ".opus"
			var opus_path := folder.path_join(opus_name)
			var global_opus := ProjectSettings.globalize_path(opus_path)
			var output_arr := []
			var exit_code := OS.execute(ffmpeg_bin, ["-y", "-i", global_source, "-c:a", "libopus", "-b:a", "%dk" % audio_bitrate, global_opus], output_arr, true)
			if exit_code == 0 and FileAccess.file_exists(opus_path):
				hashes[opus_name] = FileAccess.get_sha256(opus_path)
				Credits.write_json(opus_path + ".credits.json", record)
				if delete_source_audio:
					DirAccess.remove_absolute(global_source)
					DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path + ".credits.json"))
					hashes.erase(fname)

	for entry: Dictionary in files:
		if hashes.has(str(entry.filename)):
			Credits.write_json(folder.path_join(str(entry.filename))+".credits.json",record)
	for name in ["asset.credits.json","provenance.json","import_receipt.json"]:
		if Credits.write_json(folder.path_join(name),record)!=OK:return {"error":"Cannot save import metadata."}
	return {"note":"Source files imported with credits. Archives are preserved intact; extract through a reviewed importer."}
