extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Pagination = preload("res://addons/3dtexel/pagination.gd")
class FakeClient:
	extends Node
	var total := 3000
	var fail_page := -1
	var calls: Array[int] = []
	func json_request(path: String) -> Dictionary:
		var regex := RegEx.create_from_string("[?&]page=([0-9]+)")
		var page := int(regex.search(path).get_string(1))
		calls.append(page)
		if page==fail_page:return {"error":"simulated failure"}
		var items := []
		for i in range((page-1)*50,mini(page*50,total)):
			items.append({"id":i,"title":"Asset %s" % i,"price":{"free":true,"credits":0}})
		return {"items":items,"total":total}
var failures := 0
func check(value: bool, message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var second := Pagination.request_plan(2,96)
	check(second==[{"page":2,"skip":46,"take":4},{"page":3,"skip":0,"take":50},{"page":4,"skip":0,"take":42}],"Non-aligned page boundaries")
	var last := Pagination.request_plan(3,1024)
	var count := 0
	for request in last:count+=request.take;check(request.page<=50,"Respect API page ceiling")
	check(count==452,"Final page ends at 2500 accessible results")
	var browser := Browser.new();root.add_child(browser);await process_frame
	browser.client.queue_free()
	var fake := FakeClient.new();browser.add_child(fake);browser.client=fake
	browser.per_page.select(browser.per_page.get_item_index(96))
	await browser.run_search()
	check(browser.grid.get_child_count()==96,"96 results assembled")
	check(browser.grid.get_child(0).tooltip_text=="Asset 0" and browser.grid.get_child(95).tooltip_text=="Asset 95","First page range")
	browser.page=2;await browser.run_search()
	check(browser.grid.get_child(0).tooltip_text=="Asset 96" and browser.grid.get_child(95).tooltip_text=="Asset 191","No skipped or repeated boundary results")
	check(fake.calls==[1,2,3,4],"Overlapping server pages reused from cache")
	browser.per_page.select(browser.per_page.get_item_index(1024));browser.page=2;await browser.run_search()
	check(browser.grid.get_child_count()==1024,"1024-result batch")
	check(browser.grid.get_child(0).tooltip_text=="Asset 1024" and browser.grid.get_child(1023).tooltip_text=="Asset 2047","Large page correct range")
	browser.page=3;await browser.run_search()
	check(browser.grid.get_child_count()==452 and browser.next.disabled,"Truncated final service page")
	check(browser.grid.get_child(451).tooltip_text=="Asset 2499","Last accessible result")
	fake.total=60;browser.search_cache.clear();browser.page=1;await browser.run_search()
	check(browser.grid.get_child_count()==60 and browser.next.disabled,"Short result set stops fetching early")
	fake.total=3000;fake.fail_page=2;browser.search_cache.clear();await browser.run_search()
	check(browser.grid.get_child_count()==50 and browser.next.disabled and "simulated failure" in browser.status.text,"Partial failure preserves results and prevents skipped pages")
	browser.queue_free();await process_frame
	print("Pagination tests complete; failures=",failures)
	quit(1 if failures else 0)
