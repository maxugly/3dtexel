extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Client = preload("res://addons/3dtexel/client.gd")
const Pagination = preload("res://addons/3dtexel/pagination.gd")
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
	var plan := Pagination.request_plan(3,1024);var total := 0
	for request in plan:total+=request.take;check(request.page<=50,"API cap")
	check(total==452,"Bounded server page plan")
	var browser := Browser.new();root.add_child(browser);await process_frame
	browser.client.queue_free();var fake := FakeClient.new();browser.add_child(fake);browser.client=fake;fake.cache.root="user://offline_page_test_%s" % Time.get_ticks_usec()
	browser.per_page.select(browser.per_page.get_item_index(1024))
	browser.run_search();check(fake.calls==0 and browser.grid.get_child_count()==0,"Initial search is local")
	await browser.refresh_search()
	check(fake.calls==22 and browser.grid.get_child_count()==1024,"Explicit refresh hydrates the catalog once")
	browser.per_page.select(browser.per_page.get_item_index(96));browser.run_search()
	check(browser.grid.get_child_count()==96,"Local page size")
	browser.page=2;browser.run_search()
	check(browser.grid.get_child(0).tooltip_text=="Asset 96" and browser.grid.get_child(95).tooltip_text=="Asset 191","Local page boundaries")
	browser.search.text="Asset 99";browser.start_search()
	check(fake.calls==22,"Searching and paging never request API data")
	browser.queue_free();await process_frame
	print("Cache-first pagination tests complete; failures=",failures)
	quit(1 if failures else 0)
