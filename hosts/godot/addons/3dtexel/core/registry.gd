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
	var fallback: bool = provider.default_enabled() if provider.has_method("default_enabled") else true
	provider.enabled=bool(ProjectSettings.get_setting("asset_browser/providers/"+id+"/enabled",fallback))
	provider.network_allowed=network_allowed and provider.enabled
	return OK
func set_enabled(id: String,value: bool) -> void:
	var provider: Node=providers[id];provider.enabled=value;provider.network_allowed=network_allowed and value
	if not value:provider.cancel_all()
	ProjectSettings.set_setting("asset_browser/providers/"+id+"/enabled",value);ProjectSettings.save()
## Providers that are switched off by default, with the reason they give.
func disabled_providers() -> Array:
	var result: Array=[]
	for id in providers:
		var provider: Node=providers[id]
		if provider.enabled:continue
		var reason := str(provider.disabled_reason()) if provider.has_method("disabled_reason") else ""
		result.append({"id":str(id),"name":str(provider.descriptor().get("name",id)),"reason":reason})
	return result
func active_ids() -> Array:
	var result := []
	for id in providers:
		if providers[id].enabled and (scope.is_empty() or scope==id):result.append(id)
	return result
func provider_for(asset: Dictionary) -> Node:
	return providers.get(str(asset.get("provider_id","")))
func index_assets(items: Array, save := true) -> void:
	for asset: Dictionary in items:
		var policy := Policy.evaluate(asset)
		asset.license_status=policy.status;asset.license_reason=policy.reason;catalog.upsert(asset)
	if save:catalog.save()
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
	allow_thumbnail(provider,url)
	return await provider.thumbnail(url)
## Thumbnails are part of rendering an already authorised search result, so the
## exact requested URL is allow-listed on the provider client. Without this the
## per-URL allow list stays empty and every grid tile renders blank once the
## search that produced it has finished.
func allow_thumbnail(provider: Node,url: String) -> void:
	if url.is_empty():return
	var provider_client: Variant=provider.get("client")
	if provider_client == null:return
	if not "allowed_thumbnails" in provider_client:return
	provider_client.allowed_thumbnails[url]=true
func cancel_all() -> void:
	for provider in providers.values():provider.cancel_all()
func cache_roots() -> Array[String]:
	var roots: Array[String]=[]
	var catalog_root := str(catalog.root)
	if not catalog_root.is_empty():roots.append(catalog_root)
	for provider in providers.values():
		var cache: Variant=provider_cache(provider)
		if cache == null:continue
		var root := str(cache.get("root"))
		if not root.is_empty() and root not in roots:roots.append(root)
	return roots
func provider_cache(provider: Node) -> Variant:
	var provider_client: Variant=provider.get("client")
	if provider_client == null:return null
	return provider_client.get("cache")
func cache_size() -> int:
	var total := 0
	for root in cache_roots():total+=cache_path_size(root)
	return total
func clear_caches() -> void:
	for provider in providers.values():
		provider.cancel_all()
		var cache: Variant=provider_cache(provider)
		if cache == null:continue
		var records: Variant=cache.get("catalog")
		if records is Dictionary:records.clear()
		cache.set("loaded",false)
		var provider_client: Variant=provider.get("client")
		var thumbs: Variant=provider_client.get("allowed_thumbnails") if provider_client!=null else null
		if thumbs is Dictionary:thumbs.clear()
	for root in cache_roots():clear_cache_path(root)
	catalog.records.clear();catalog.loaded=false
static func cache_path_size(path: String) -> int:
	var directory := DirAccess.open(path)
	if not directory:return 0
	directory.include_hidden=true
	var total := 0
	for name in directory.get_files():
		var file := FileAccess.open(path.path_join(name),FileAccess.READ)
		if file:total+=file.get_length();file.close()
	for name in directory.get_directories():total+=cache_path_size(path.path_join(name))
	return total
static func clear_cache_path(path: String) -> void:
	if not path.begins_with("user://") or path=="user://":return
	var directory := DirAccess.open(path)
	if not directory:return
	directory.include_hidden=true
	for name in directory.get_files():DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
	for name in directory.get_directories():
		clear_cache_path(path.path_join(name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
static func format_size(bytes: int) -> String:
	if bytes<1024:return "%d B" % bytes
	if bytes<1048576:return "%.1f KB" % (bytes/1024.0)
	if bytes<1073741824:return "%.1f MB" % (bytes/1048576.0)
	return "%.2f GB" % (bytes/1073741824.0)

func _exit_tree() -> void:cancel_all()
