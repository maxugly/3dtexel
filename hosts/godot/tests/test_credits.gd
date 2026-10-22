extends SceneTree
const Credits = preload("res://addons/3dtexel/credits.gd")
const Metadata = preload("res://addons/3dtexel/metadata.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var asset := {"id":42,"title":"Test dirt","author":{"name":"Test Artist","url":"https://example.test/artist"},"license":{"name":"CC-BY 4.0","url":"https://creativecommons.org/licenses/by/4.0/","attribution_required":true},"url":"https://example.test/material","resolutions":["2k","4k"]}
	check(Credits.available_resolutions(asset)==["2k","4k"],"Explicit available sizes")
	check(Credits.available_resolutions({}).is_empty(),"Unknown availability stays unknown")
	var info := Metadata.from_html('<div>Author</div><div>Another Artist</div><div>Resolution</div><div>4K</div><h3>Available Formats</h3><span>4K TGA 2K TGA</span><p>Login or Register</p>',asset.url)
	check(info.get("author")=="Another Artist" and Credits.available_resolutions(info)==["2k","4k"],"Explicit page declarations")
	check(not Metadata.from_html('<script type="application/ld+json">{"publisher":{"name":"Website"}}</script>',asset.url).has("author"),"Publisher is not invented as asset author")
	var record := Credits.asset_record(asset)
	check(record.authors[0].name=="Test Artist" and not record.review_required,"Author and license retained")
	check(Credits.asset_record({"id":7}).review_required,"Missing metadata flagged, never invented")
	var folder := "res://3DTexel/credits_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var material := StandardMaterial3D.new();ResourceSaver.save(material,folder.path_join("material.res"));material.take_over_path(folder.path_join("material.res"))
	check(Credits.write_asset_sidecars(folder,record)==OK,"Asset and native material sidecars")
	var root_node := Node3D.new();var mesh := MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.material_override=material;root_node.add_child(mesh);mesh.owner=root_node
	var scene := PackedScene.new();scene.pack(root_node);ResourceSaver.save(scene,folder.path_join("sample.tscn"));root_node.free()
	var result := Credits.write_scene(folder.path_join("sample.tscn"))
	check(not result.has("error") and result.asset_count==1,"Saved scene collects dependency credits")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(result.path))
	check(manifest.assets[0].authors[0].name=="Test Artist","Scene attribution linked to author")
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.BROWN);image.save_png(folder.path_join("albedo.png"))
	var handoff := Importer.terrain_handoff(folder,{"albedo":"albedo.png"},asset,"opengl","res://3DTexel/credits_inbox")
	var terrain: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(handoff.manifest))
	check(terrain.credits.authors[0].name=="Test Artist" and FileAccess.file_exists(str(handoff.manifest).get_base_dir().path_join("asset.credits.json")),"Terrain handoff preserves credits")
	print("Credits tests complete; failures=",failures)
	quit(1 if failures else 0)
