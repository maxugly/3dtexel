@tool
extends Node
## Register provider Scripts here or from another addon; browser never imports site code.
const Catalog = preload("res://addons/3dtexel/core/catalog.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
var catalog := Catalog.new()
var inventory := preload("res://addons/3dtexel/core/download_inventory.gd").new()
var providers := {}
var scope := ""
var network_allowed := false:
	set(value):
		network_allowed=value
		for provider in providers.values():provider.network_allowed=value and provider.enabled
var refreshing := false:
	set(value):
		refreshing=value
		for provider in providers.values():provider.refreshing=value
func _init() -> void:
	var directory := DirAccess.open("res://addons/3dtexel/providers")
	if directory:
		for name in directory.get_directories():
			var path := "res://addons/3dtexel/providers/"+name+"/provider.gd"
			if ResourceLoader.exists(path):
				var script: Script=load(path)
				if script and script.can_instantiate():register_provider(script.new())
func register_provider(provider: Node) -> Error:
	var id := str(provider.descriptor().get("id",""))
	if id.is_empty() or not id.is_valid_identifier() or providers.has(id):provider.free();return ERR_INVALID_PARAMETER
	providers[id]=provider;add_child(provider)
	provider.enabled=bool(ProjectSettings.get_setting("asset_browser/providers/"+id+"/enabled",true))
	return OK
func set_enabled(id: String,value: bool) -> void:
	var provider: Node=providers[id];provider.enabled=value;provider.network_allowed=network_allowed and value
	if not value:provider.cancel_all()
	ProjectSettings.set_setting("asset_browser/providers/"+id+"/enabled",value);ProjectSettings.save()
func active_ids() -> Array:
	var result := []
	for id in providers:
		if providers[id].enabled and (scope.is_empty() or scope==id):result.append(id)
	return result
func provider_for(asset: Dictionary) -> Node:
	return providers.get(str(asset.get("provider_id","")))
func index_assets(items: Array) -> void:
	for asset: Dictionary in items:
		var policy := Policy.evaluate(asset)
		asset.license_status=policy.status;asset.license_reason=policy.reason;catalog.upsert(asset)
	catalog.save()
func seed(output: String) -> void:
	inventory.scan(output)
	# Legacy import discovery is optional and belongs to its adapter.
	for provider in providers.values():
		if provider.has_method("load_local_imports"):provider.load_local_imports(output)
		index_assets(provider.local_assets())
		for folder in provider.local_import_roots():inventory.scan(str(folder))
	inventory.save()
func search(query: String,category: String,free_only: bool,license_name: String) -> Array:
	return catalog.search(active_ids(),query,category,free_only,license_name)
func licenses() -> Array[String]:
	var result: Array[String]=[]
	for asset: Dictionary in search("","all",false,"Any license"):
		var name := str(asset.get("license",{}).get("name","Unknown"))
		if name not in result:result.append(name)
	result.sort();return result
func cached_asset(asset: Dictionary) -> Dictionary:
	catalog.load_catalog();return catalog.records.get(str(asset.get("provider_id",""))+":"+str(asset.id),{}).duplicate(true)
func can_download(asset: Dictionary) -> bool:
	var provider := provider_for(asset)
	return provider!=null and provider.enabled and int(Policy.evaluate(asset).status)!=Policy.Status.BLOCKED and provider.can_download(asset)
func thumbnail(url: String,asset: Dictionary) -> Texture2D:
	var provider := provider_for(asset)
	if not provider or not provider.enabled:return null
	return await provider.thumbnail(url)
func cancel_all() -> void:
	for provider in providers.values():provider.cancel_all()

func _exit_tree() -> void:cancel_all()
