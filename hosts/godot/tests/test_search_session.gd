extends SceneTree
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Session = preload("res://addons/3dtexel/core/search_session.gd")
class Fake:
	extends "res://addons/3dtexel/core/provider.gd"
	var calls := 0
	func descriptor() -> Dictionary:return {"id":"fixture","name":"Fixture"}
	func refresh_page(query: String,_category: String,cursor: String) -> Dictionary:
		calls+=1
		return {"items":[{"provider_id":"fixture","id":query+cursor,"title":query,"type":"model","price":{"free":true},"license":"CC0"}],"next_cursor":"second" if cursor.is_empty() else ""}
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
	hub.queue_free();await process_frame
	print("Search session tests complete; failures=",failures);quit(1 if failures else 0)
