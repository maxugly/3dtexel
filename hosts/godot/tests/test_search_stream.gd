extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Provider = preload("res://addons/3dtexel/core/provider.gd")
class Fake:
	extends Provider
	var id := "fake"
	var delay := 0.05
	var fail := false
	func descriptor() -> Dictionary:return {"id":id,"name":id}
	func refresh_page(query: String,_category: String,_cursor: String) -> Dictionary:
		await get_tree().create_timer(delay).timeout
		if fail:return {"error":"Connection failed (13). Check connection and retry."}
		return {"items":[{"provider_id":id,"id":query,"title":id+" "+query,"type":"model","price":{"free":true},"license":"CC0"}],"next_cursor":""}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var browser := Browser.new();root.add_child(browser);await process_frame
	var root_path := "user://search_stream_test_%s" % Time.get_ticks_usec()
	browser.client.catalog.root=root_path;browser.client.catalog.loaded=false;browser.client.catalog.records={}
	for provider in browser.client.providers.values():provider.enabled=false
	for spec in [["fast",0.05,false],["slow",0.15,false],["bad",0.1,true]]:
		var fake := Fake.new();fake.id=spec[0];fake.delay=spec[1];fake.fail=spec[2]
		browser.client.register_provider(fake);fake.enabled=true
	browser.search.text="oak";browser.kind.select(0)
	await browser.refresh_search()
	check(browser.status.text=="Search complete · 2 results · 2 ok · 1 failed.","Unexpected status: %s" % browser.status.text)
	check(browser.grid.get_child_count()==2,"Expected two result cards, got %s" % browser.grid.get_child_count())
	check(browser.status.tooltip_text.contains("bad: Connection failed"),"Per-site failure detail missing from the report: %s" % browser.status.tooltip_text)
	check(browser.status.tooltip_text.contains("fast"),"Per-site report is missing working sites: %s" % browser.status.tooltip_text)
	browser.search.text="oak";browser.start_search()
	await create_timer(0.02).timeout
	browser.search.text="pine";browser.start_search()
	var guard := 0
	while browser.busy and guard<200:await create_timer(0.01).timeout;guard+=1
	check(not browser.busy,"Restarted search must finish")
	check(not browser.visible_assets.is_empty() and browser.visible_assets.all(func(asset):return str(asset.title).ends_with(" pine")),"Restarted search must discard in-flight old results")
	browser.queue_free();await process_frame
	var catalog_file := ProjectSettings.globalize_path(root_path.path_join("assets.json"))
	if FileAccess.file_exists(catalog_file):DirAccess.remove_absolute(catalog_file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path))
	print("Search stream tests complete; failures=",failures)
	quit(1 if failures else 0)
