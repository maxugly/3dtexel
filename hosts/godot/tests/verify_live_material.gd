extends SceneTree
## Rebuild only the ignored live-test fixture; checks all maps reload as BC3.
const Importer = preload("res://addons/3dtexel/importer.gd")
func _initialize():call_deferred("run")
func run():
	var folder := "res://3DTexel/live_smoke/green_grass_surface_pbr_material_24509/2k"
	if not FileAccess.file_exists(folder.path_join("provenance.json")):push_error("Run the explicit live smoke first.");quit(1);return
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))
	var result := Importer.make_material(folder,provenance.maps,provenance.normal_format)
	if not result.has("material"):push_error("Live fixture preparation failed.");quit(1);return
	for role in provenance.maps:
		var texture := ResourceLoader.load(folder.path_join(role+"_texture.res"),"",ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		if not texture or not texture.get_image().is_compressed() or not texture.get_image().has_mipmaps():push_error("Compressed map reload failed: "+role);quit(1);return
	var material := ResourceLoader.load(result.material,"",ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
	if not material or not material.normal_texture or not material.albedo_texture:push_error("Live material references missing.");quit(1);return
	print("Live grass fixture: all five saved texture resources reload compressed with mipmaps; native material references valid.")
	quit()
