extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
class FixtureProvider:
	extends "res://addons/3dtexel/core/provider.gd"
	func descriptor() -> Dictionary:return {"id":"fixture","name":"Fixture","website":"https://example.invalid","key_env":[]}
	func can_download(_asset: Dictionary) -> bool:return true
	func variants(asset: Dictionary) -> Array:return asset.get("variants",[])
class FixtureBrowser:
	extends Browser
	var times := []
	func download_resolution(_asset: Dictionary,_version: String) -> Dictionary:
		times.append(Time.get_ticks_msec());return {"note":"Offline fixture"}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var browser := FixtureBrowser.new();root.add_child(browser);await process_frame
	for provider in browser.client.providers.values():provider.enabled=false
	var provider := FixtureProvider.new();browser.client.register_provider(provider);provider.enabled=true
	browser.client.catalog.root="user://batch_cards_%s" % Time.get_ticks_usec();browser.client.catalog.loaded=false;browser.client.catalog.records={}
	browser.client.inventory.root=browser.client.catalog.root+"_imports";browser.client.inventory.loaded=false;browser.client.inventory.records={}
	var asset := {"provider_id":"fixture","provider":"Fixture","id":"texture","title":"Texture","type":"material","price":{"free":true},"license":"CC0","variants":[{"id":"2k","label":"2K","resolution":"2k","confirmed":true},{"id":"4k","label":"4K","resolution":"4k","confirmed":true}]}
	var model := {"provider_id":"fixture","provider":"Fixture","id":"model","title":"Model","type":"model","price":{"free":true},"license":"CC0","variants":[{"id":"low","label":"L","lod":"low","triangles":1000,"confirmed":true},{"id":"high","label":"H","lod":"high","triangles":4000,"confirmed":true}]}
	var unknown := asset.duplicate(true);unknown.id="unknown";unknown.variants=[{"id":"1k","label":"1K","confirmed":false}]
	browser.thumbnail_textures[browser.thumbnail_key(asset)]=GradientTexture1D.new()
	browser.client.index_assets([asset,model,unknown]);browser.session.identities.assign(["fixture:texture","fixture:model","fixture:unknown"]);browser.update_filter_choices();browser.run_search()
	check(browser.delay.value==5,"Default pause is five seconds")
	check(browser.selection.jobs(browser.filtered_items()).size()==4,"Missing real versions selected by default")
	var card := browser.grid.get_child(0)
	check(card.get_node("Contents/Header/Select").visible,"Card checkbox always visible")
	var versions := card.get_node("Contents/Versions")
	check(versions.get_child_count()==2 and versions.get_child(0).text.begins_with("2K"),"Direct version buttons on card")
	var model_card := browser.grid.get_child(1)
	check(model_card.get_node("Contents/Versions").get_child(0).text.begins_with("L"),"Model LOD buttons retain model labels")
	check(browser.selection.options(unknown,false).is_empty(),"Speculative variants never offered")
	browser.toggle_all(false);check(browser.selection.jobs(browser.filtered_items()).is_empty(),"Uncheck all clears displayed cards")
	browser.toggle_all(true);check(browser.selection.jobs(browser.filtered_items()).size()==4,"Check all selects displayed choices")
	var folder: String = browser.client.inventory.root.path_join("existing/2k");DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	Credits.write_json(folder.path_join("provenance.json"),{"provider_id":"fixture","asset_id":"texture","returned_resolution":"2k"});ResourceSaver.save(StandardMaterial3D.new(),folder.path_join("material.res"));browser.client.inventory.record_import(asset,"2k",folder)
	browser.selection.checked.clear();browser.run_search()
	var jobs := browser.selection.jobs(browser.filtered_items())
	check(jobs.size()==3 and jobs[0].version=="4k","Owned versions omitted from default batch")
	browser.selection.filter_key="resolution:2k";browser.selection.checked.clear();browser.run_search()
	check(browser.visible_assets.size()==1 and browser.selection.jobs(browser.filtered_items()).is_empty(),"2K filter excludes models and does not auto-select owned version")
	browser.toggle_all(true);jobs=browser.selection.jobs(browser.filtered_items())
	check(jobs.size()==1 and jobs[0].version=="2k","Explicit checkbox can select an existing version")
	browser.selection.filter_key="";browser.selection.checked.clear();browser.run_search()
	browser.delay.step=.01;browser.delay.value=.2
	await browser.run_jobs([{"asset":asset,"version":"2k"},{"asset":asset,"version":"4k"}])
	check(browser.times.size()==2 and browser.times[1]-browser.times[0]>=180,"Queue respects configured pause")
	browser.times.clear();browser.delay.value=1
	get_tree_timer_stop(browser)
	await browser.run_jobs([{"asset":asset,"version":"2k"},{"asset":asset,"version":"4k"}])
	check(browser.times.size()==1 and browser.status.text.contains("stopped"),"Stop interrupts waiting before next download")
	browser.queue_free();await process_frame
	print("Batch card tests complete; failures=",failures);quit(1 if failures else 0)
func get_tree_timer_stop(browser: Node) -> void:
	await create_timer(.15).timeout;browser.stopping=true
