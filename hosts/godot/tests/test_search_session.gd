extends SceneTree
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Session = preload("res://addons/3dtexel/core/search_session.gd")
class Fake:
	extends "res://addons/3dtexel/core/provider.gd"
	var calls := 0
	var id := "fixture"
	func descriptor() -> Dictionary:return {"id":id,"name":id}
	func refresh_page(query: String,_category: String,cursor: String) -> Dictionary:
		calls+=1
		return {"items":[{"provider_id":id,"id":query+cursor,"title":query,"type":"model","price":{"free":true},"license":"CC0"}],"next_cursor":"second" if cursor.is_empty() else ""}
class Slow:
	extends "res://addons/3dtexel/core/provider.gd"
	var id := "slow"
	func descriptor() -> Dictionary:return {"id":id,"name":id}
	func refresh_page(_query: String,_category: String,_cursor: String) -> Dictionary:
		await get_tree().create_timer(5.0).timeout
		return {"items":[],"next_cursor":""}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var hub := Registry.new();root.add_child(hub)
	for provider in hub.providers.values():provider.enabled=false
	hub.catalog.root="user://search_session_test_%s" % Time.get_ticks_usec()
	var fake := Fake.new();hub.register_provider(fake);fake.enabled=true;hub.network_allowed=true;hub.refreshing=true
	var session := Session.new();session.registry=hub;session.begin("bush","model")
	await session.fetch_round()
	check(fake.calls==1 and session.items().size()==1 and session.has_more(),"Initial search requests one page, not entire query")
	check(session.items().size()==1 and fake.calls==1,"Reading results does not refetch metadata")
	await session.fetch_round()
	check(fake.calls==2 and session.items().size()==2 and not session.has_more(),"Additional results fetched on demand")
	session.begin("bush","model");await session.fetch_round()
	check(fake.calls==3,"Submitting same search still queries provider")
	session.begin("rock","model");await session.fetch_round()
	check(session.items().size()==1 and session.items()[0].title=="rock","A new query excludes previous matches")
	var second := Fake.new();second.id="other";hub.register_provider(second);second.enabled=true
	fake.calls=0;second.calls=0
	session.begin("oak","model")
	await session.fetch_round()
	check(fake.calls+second.calls==1,"A round queries one site instead of every site")
	check(session.has_more(),"Unqueried sites remain available for more results")
	await session.fetch_round()
	check(fake.calls+second.calls==2,"The next round queries the next site")
	fake.calls=0;second.calls=0
	session.begin("elm","model")
	var first_id := session.next_id();var second_id := session.next_id()
	check(not first_id.is_empty() and not second_id.is_empty() and first_id!=second_id,"Streaming claims each site once")
	check(session.next_id().is_empty(),"Streaming does not claim a site twice")
	var first_result: Dictionary=await session.fetch_id(first_id)
	check(not first_result.items.is_empty() and fake.calls+second.calls==1,"Streaming fetches one claimed site")
	# A stalled site must fail on its own deadline instead of stalling the sweep.
	var slow := Slow.new();slow.id="slow";hub.register_provider(slow);slow.enabled=true;slow.network_allowed=true
	session.begin("ash","model")
	var slow_result: Dictionary=await session.fetch_id("slow",0.3)
	check(str(slow_result.get("error","")).contains("Timed out"),"A stalled site must time out on its own: %s" % str(slow_result.get("error","")))
	check(str(session.outcomes.get("slow",{}).get("state",""))=="timeout","Timeout outcome must be recorded per site")
	check(not session.next_id().is_empty(),"The sweep must continue after a stalled site")
	session.flush()
	hub.queue_free();await process_frame
	print("Search session tests complete; failures=",failures);quit(1 if failures else 0)
