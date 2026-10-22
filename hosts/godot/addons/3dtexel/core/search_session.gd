@tool
extends RefCounted
## A submitted search queries providers; browsing only fetches additional pages as needed.
var registry: Node
const PRIORITY := ["texel","polyhaven","ambientcg","kenney","quaternius","opengameart","kaykit","polypizza","grab3d"]
var query := ""
var category := "all"
var states := {}
var identities: Array[String]=[]
var order: Array[String]=[]
var order_index := 0
var requests := 0
func begin(text: String, kind: String) -> void:
	query=text;category=kind;states.clear();identities.clear();requests=0
	order.clear();order_index=0
	var ids: Array=registry.active_ids()
	for id in PRIORITY:
		if id in ids:order.append(id)
	for id in ids:
		if str(id) not in order:order.append(str(id))
	for id in order:states[id]={"cursor":"","done":false,"seen":{}}
func reset() -> void:
	query="";category="all";states.clear();identities.clear();order.clear();order_index=0;requests=0
func has_more() -> bool:
	for id in states:
		if registry.providers.has(id) and registry.providers[id].enabled and not states[id].done:return true
	return false
func fetch_round() -> Dictionary:
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
		var response: Dictionary=await provider.refresh_page(query,category,str(state.cursor))
		requests+=1
		if response.has("error"):
			errors.append(str(provider.descriptor().name)+": "+str(response.error));state.done=true;return {"added":added,"errors":errors}
		var items: Array=response.get("items",[])
		registry.index_assets(items)
		for asset: Dictionary in items:
			if str(asset.get("provider_id",""))!=str(id):continue
			var identity := str(id)+":"+str(asset.id)
			if identity not in identities:identities.append(identity);added+=1
		var next := str(response.get("next_cursor",""))
		state.done=next.is_empty() or state.seen.has(next)
		if state.seen.has(next):errors.append(str(provider.descriptor().name)+": repeated search page; stopped.")
		state.cursor=next;state.seen[next]=true
		return {"added":added,"errors":errors}
	return {"added":added,"errors":errors}
func items() -> Array:
	registry.catalog.load_catalog();var result := []
	for identity in identities:
		if registry.catalog.records.has(identity):result.append(registry.catalog.records[identity].duplicate(true))
	return result
