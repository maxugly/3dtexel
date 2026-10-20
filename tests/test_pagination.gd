extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Client = preload("res://addons/3dtexel/client.gd")
class FakeClient:
	extends Client
	var calls := 0
	func transport_json(path: String,_method:=HTTPClient.METHOD_GET,_body:={})->Dictionary:
		calls+=1
		var page := int(RegEx.create_from_string("[?&]page=([0-9]+)").search(path).get_string(1))
		var items := []
		for i in range((page-1)*50,mini(page*50,1100)):items.append({"id":i,"type":"pbr","title":"Asset %s" % i,"price":{"free":true,"credits":0},"license":"CC0"})
		return {"items":items,"total":1100}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var browser := Browser.new();root.add_child(browser);await process_frame
	var adapter: Node=browser.client.providers.texel
	adapter.client.free();var fake := FakeClient.new();adapter.add_child(fake);adapter.client=fake;fake.cache.root="user://offline_page_test_%s" % Time.get_ticks_usec()
	browser.client.catalog.root=fake.cache.root+"_core";browser.client.catalog.loaded=false;browser.client.catalog.records={}
	browser.per_page.select(browser.per_page.get_item_index(12))
	await browser.start_search()
	check(fake.calls==1 and browser.grid.get_child_count()==12,"Search queries one page instead of the whole query")
	await browser.next_page();check(fake.calls==1,"Already fetched pages reuse metadata")
	browser.page=5;browser.run_search();await browser.next_page()
	check(fake.calls==2 and browser.page==6,"Crossing fetched page boundary queries next site page")
	browser.search.text="Asset 99";await browser.start_search()
	check(fake.calls==3,"Submitting a search always queries site")
	browser.run_search();check(fake.calls==3,"Redrawing/filtering does not repeat query")
	browser.queue_free();await process_frame
	print("Search pagination tests complete; failures=",failures);quit(1 if failures else 0)
