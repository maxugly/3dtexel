@tool
extends RefCounted
## A submitted search queries providers; browsing only fetches additional pages as needed.
var registry: Node
const PRIORITY := ["texel","polyhaven","ambientcg","kenney","quaternius","opengameart","kaykit","polypizza","grab3d","cgbookcase","textures3d","texturecan","sharetextures","scan_the_world","morphosource","nih_3d","smithsonian","nasa","itch_io"]
var query := ""
var category := "all"
var states := {}
var identities: Array[String]=[]
var order: Array[String]=[]
var order_index := 0
var claimed := {}
var in_flight := {}
var ranks := {}
var identity_seq := {}
var requests := 0
var outcomes := {}
var _cached_items: Array = []
var _cached_count := -1
var _cached_catalog_rev := -1
func begin(text: String, kind: String) -> void:
	query=text;category=kind;states.clear();identities.clear();requests=0;outcomes.clear()
	order.clear();order_index=0;claimed.clear();in_flight.clear();ranks.clear();identity_seq.clear()
	_cached_items.clear();_cached_count=-1;_cached_catalog_rev=-1
	var ids: Array=registry.active_ids()
	for id in PRIORITY:
		if id in ids:order.append(id)
	for id in ids:
		if str(id) not in order:order.append(str(id))
	for index in order.size():ranks[order[index]]=index
	for id in order:states[id]={"cursor":"","done":false,"seen":{}}
func reset() -> void:
	query="";category="all";states.clear();identities.clear();order.clear();order_index=0;claimed.clear();in_flight.clear();ranks.clear();identity_seq.clear();requests=0;outcomes.clear()
	_cached_items.clear();_cached_count=-1;_cached_catalog_rev=-1
func next_id() -> String:
	for id in order:
		if claimed.has(id):continue
		var state: Dictionary=states.get(id,{})
		if state.is_empty() or state.done:continue
		claimed[id]=true;in_flight[id]=true
		return id
	return ""
func fetch_id(id: String, timeout_seconds := 0.0) -> Dictionary:
	var started := Time.get_ticks_msec()
	var state: Dictionary=states.get(id,{})
	var provider: Node=registry.providers.get(id)
	if state.is_empty() or not provider or not provider.enabled or state.done:
		in_flight.erase(id)
		return {"id":id,"items":[],"error":"","done":true}
	if not provider.network_allowed:
		in_flight.erase(id)
		return {"id":id,"items":[],"error":"Search was not started.","done":true}
	var response: Dictionary=await _fetch_page(provider,str(state.cursor),timeout_seconds)
	in_flight.erase(id);requests+=1
	var elapsed := Time.get_ticks_msec()-started
	if response.has("error"):
		state.done=true
		var message := str(provider.descriptor().name)+": "+str(response.error)
		_record_outcome(id,provider,"timeout" if response.get("timeout",false) else "failed",0,message,elapsed)
		return {"id":id,"items":[],"error":message,"done":true,"ms":elapsed}
	var items: Array=response.get("items",[])
	registry.index_assets(items,false)
	var added: Array=[]
	for asset: Dictionary in items:
		if str(asset.get("provider_id",""))!=str(id):continue
		var identity := str(id)+":"+str(asset.id)
		if not identity_seq.has(identity):
			identities.append(identity);identity_seq[identity]=identities.size();added.append(asset)
			_cached_count=-1
	var next := str(response.get("next_cursor",""))
	state.done=next.is_empty() or state.seen.has(next)
	var error := ""
	if state.seen.has(next):error=str(provider.descriptor().name)+": repeated search page; stopped."
	state.cursor=next;state.seen[next]=true
	if not error.is_empty():
		_record_outcome(id,provider,"failed",added.size(),error,elapsed)
	elif added.is_empty() and state.done:
		_record_outcome(id,provider,"empty",0,str(provider.descriptor().name)+": no matching assets.",elapsed)
	else:
		_record_outcome(id,provider,"ok",added.size(),"",elapsed)
	return {"id":id,"items":added,"error":error,"done":state.done,"ms":elapsed}
## Runs one provider page with an optional per-provider deadline so a single slow
## site cannot stall the whole sweep. The abandoned call is left to finish on its
## own; its result is discarded.
func _fetch_page(provider: Node,cursor: String,timeout_seconds: float) -> Dictionary:
	if timeout_seconds <= 0.0:
		return await provider.refresh_page(query,category,cursor)
	var holder := {"finished":false,"response":{}}
	_refresh_async(provider,cursor,holder)
	var deadline := Time.get_ticks_msec()+roundi(timeout_seconds*1000)
	while not holder.finished and Time.get_ticks_msec() < deadline:
		await registry.get_tree().process_frame
	if holder.finished:return holder.response
	return {"error":"Timed out after %s s." % int(timeout_seconds),"timeout":true}
func _refresh_async(provider: Node,cursor: String,holder: Dictionary) -> void:
	holder.response=await provider.refresh_page(query,category,cursor)
	holder.finished=true
func _record_outcome(id: String,provider: Node,state: String,items: int,error: String,elapsed: int) -> void:
	var previous: Dictionary=outcomes.get(id,{})
	outcomes[id]={"name":str(provider.descriptor().name),"state":state,"items":int(previous.get("items",0))+items,"error":error,"ms":int(previous.get("ms",0))+elapsed}
func outcome_summary() -> Dictionary:
	var counts := {"ok":0,"empty":0,"failed":0,"timeout":0}
	for id in outcomes:
		var state := str(outcomes[id].get("state","failed"))
		if state=="timed_out":state="timeout"
		if counts.has(state):counts[state]+=1
	return counts
func flush() -> void:
	registry.catalog.save()
func has_more() -> bool:
	for id in states:
		if registry.providers.has(id) and registry.providers[id].enabled and not states[id].done:return true
	return false
func fetch_round(timeout_seconds := 0.0) -> Dictionary:
	var added := 0;var errors := []
	if order.is_empty():return {"added":added,"errors":errors}
	var checked := 0
	while checked<order.size():
		var id: String=order[order_index]
		order_index=(order_index+1)%order.size();checked+=1
		var state: Dictionary=states.get(id,{})
		if state.is_empty():continue
		var provider: Node=registry.providers.get(id)
		if not provider or not provider.enabled or state.done:continue
		if not provider.network_allowed:return {"error":"Search was not started."}
		var response: Dictionary=await _fetch_page(provider,str(state.cursor),timeout_seconds)
		requests+=1
		if response.has("error"):
			var message := str(provider.descriptor().name)+": "+str(response.error)
			_record_outcome(id,provider,"timeout" if response.get("timeout",false) else "failed",0,message,0)
			errors.append(message);state.done=true;return {"added":added,"errors":errors}
		var items: Array=response.get("items",[])
		registry.index_assets(items,false)
		for asset: Dictionary in items:
			if str(asset.get("provider_id",""))!=str(id):continue
			var identity := str(id)+":"+str(asset.id)
			if not identity_seq.has(identity):
				identities.append(identity);identity_seq[identity]=identities.size();added+=1
				_cached_count=-1
		var next := str(response.get("next_cursor",""))
		state.done=next.is_empty() or state.seen.has(next)
		if state.seen.has(next):errors.append(str(provider.descriptor().name)+": repeated search page; stopped.")
		state.cursor=next;state.seen[next]=true
		return {"added":added,"errors":errors}
	return {"added":added,"errors":errors}
func items() -> Array:
	registry.catalog.load_catalog()
	if _cached_count==identities.size() and _cached_catalog_rev==registry.catalog.revision:
		return _cached_items
	var result := []
	for i in identities.size():
		var identity := identities[i]
		if not identity_seq.has(identity):identity_seq[identity]=i+1
		if registry.catalog.records.has(identity):result.append(registry.catalog.records[identity])
	result.sort_custom(func(a: Dictionary,b: Dictionary):
		var ar := int(ranks.get(str(a.get("provider_id","")),999999));var br := int(ranks.get(str(b.get("provider_id","")),999999))
		if ar!=br:return ar<br
		var ak := str(a.get("provider_id",""))+":"+str(a.get("id",""));var bk := str(b.get("provider_id",""))+":"+str(b.get("id",""))
		return int(identity_seq.get(ak,0))<int(identity_seq.get(bk,0)))
	_cached_items=result;_cached_count=identities.size();_cached_catalog_rev=registry.catalog.revision
	return _cached_items
