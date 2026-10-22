extends SceneTree
const Inventory = preload("res://addons/3dtexel/core/download_inventory.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Texel = preload("res://addons/3dtexel/providers/texel/provider.gd")
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var inventory := Inventory.new();inventory.root="user://inventory_test_%s" % Time.get_ticks_usec()
	var folder := inventory.root.path_join("asset/2k");DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var asset := {"provider_id":"fixture","id":"same"}
	Credits.write_json(folder.path_join("provenance.json"),{"provider_id":"fixture","asset_id":"same","returned_resolution":"2k"})
	ResourceSaver.save(StandardMaterial3D.new(),folder.path_join("material.res"))
	inventory.scan(inventory.root);inventory.save()
	check(inventory.has_version(asset,"2k") and not inventory.has_version(asset,"4k"),"Actual imported versions tracked")
	check(not inventory.has_version({"provider_id":"other","id":"same"},"2k"),"Sites cannot share import badges")
	var fresh := Inventory.new();fresh.root=inventory.root
	check(fresh.has_version(asset,"2k"),"Import badges survive restart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join("material.res")))
	check(not fresh.has_version(asset,"2k"),"Missing import no longer marked available")
	var texel := Texel.new();root.add_child(texel)
	check(texel.variants({}).is_empty(),"Unknown sizes never become fake choices")
	check(texel.variants({"resolutions":["2k","4k"]}).size()==2,"Only declared sizes become choices")
	texel.queue_free();await process_frame
	print("Download inventory tests complete; failures=",failures);quit(1 if failures else 0)
