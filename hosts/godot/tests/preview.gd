extends SceneTree
## Synthetic, offline layout preview. No provider transport is used.
const Browser = preload("res://addons/3dtexel/browser.gd")
class PreviewProvider:
	extends "res://addons/3dtexel/core/provider.gd"
	func descriptor() -> Dictionary:return {"id":"preview","name":"Preview fixtures","website":"https://example.invalid","key_env":[]}
	func can_download(_asset: Dictionary) -> bool:return true
	func variants(asset: Dictionary) -> Array:return asset.get("variants",[])
func _initialize():call_deferred("run")
func run():
	var args := OS.get_cmdline_user_args();root.size=Vector2i(int(args[0]),int(args[1])) if args.size()>=2 else Vector2i(1280,900)
	var destination := args[2] if args.size()>=3 else "/tmp/asset_library_preview.png"
	var margin := MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["margin_left","margin_right","margin_top","margin_bottom"]:margin.add_theme_constant_override(edge,16)
	root.add_child(margin);var browser := Browser.new();margin.add_child(browser);await process_frame
	for provider in browser.client.providers.values():provider.enabled=false
	var fixture := PreviewProvider.new();browser.client.register_provider(fixture);fixture.enabled=true
	browser.client.catalog.root="user://preview_%s" % Time.get_ticks_usec();browser.client.catalog.loaded=false;browser.client.catalog.records={}
	browser.client.inventory.root=browser.client.catalog.root+"_imports";browser.client.inventory.loaded=false;browser.client.inventory.records={}
	var assets := []
	for i in 8:
		var material := i%3!=2
		var options := [{"id":"1k","label":"1K","resolution":"1k","confirmed":true},{"id":"2k","label":"2K","resolution":"2k","confirmed":true},{"id":"4k","label":"4K","resolution":"4k","confirmed":true}] if material else [{"id":"low","label":"L","lod":"low","triangles":1200,"confirmed":true},{"id":"high","label":"H","lod":"high","triangles":4800,"confirmed":true}]
		var asset := {"provider_id":"preview","provider":"Fixture","id":str(i),"title":["Weathered steel","Grass and broad leaves","Industrial shelf","Riverbank mud","Worn brickwork","Workshop ladder","Cracked asphalt","Mossy stone"][i],"type":"material" if material else "model","license":"CC0","price":{"free":true},"variants":options}
		assets.append(asset);browser.session.identities.append("preview:"+str(i))
		if i==1:
			var folder: String=browser.client.inventory.root.path_join("asset/2k");DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder));browser.Credits.write_json(folder.path_join("provenance.json"),{"asset_id":str(i),"returned_resolution":"2k"});ResourceSaver.save(StandardMaterial3D.new(),folder.path_join("material.res"));browser.client.inventory.record_import(asset,"2k",folder)
	browser.client.index_assets(assets);browser.rebuild_sites();browser.update_filter_choices();browser.run_search()
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination);print("Saved ",destination);quit()
