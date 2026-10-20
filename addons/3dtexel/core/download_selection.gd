@tool
extends RefCounted
## Card selection and version filters. No network access.
var registry: Node
var filter_key := ""
var checked := {}
static func identity(asset: Dictionary) -> String:
	return str(asset.get("provider_id",""))+":"+str(asset.get("id",""))
static func option_key(asset: Dictionary,option: Dictionary) -> String:
	if asset.get("type","")=="material" and not str(option.get("resolution","")).is_empty():return "resolution:"+str(option.resolution).to_lower()
	if not str(option.get("filter_key","")).is_empty():return str(option.filter_key)
	if asset.get("type","")=="model" and option.has("lod"):return "lod:"+str(option.lod).to_lower()
	return "version:"+str(option.get("id",""))
func options(asset: Dictionary, filtered := true) -> Array:
	var provider: Node=registry.provider_for(asset)
	if not provider:return []
	var result := []
	for option: Dictionary in provider.variants(asset):
		if not option.get("confirmed",false):continue
		if not filtered or filter_key.is_empty() or option_key(asset,option)==filter_key:result.append(option)
	return result
func missing(asset: Dictionary) -> Array:
	return options(asset).filter(func(option):return not registry.inventory.has_version(asset,str(option.id)))
func ensure_default(asset: Dictionary) -> void:
	var key := identity(asset)
	if not checked.has(key):checked[key]={"selected":not missing(asset).is_empty(),"include_existing":false}
func set_checked(asset: Dictionary,value: bool) -> void:
	checked[identity(asset)]={"selected":value,"include_existing":value and missing(asset).is_empty()}
func is_checked(asset: Dictionary) -> bool:
	ensure_default(asset);return bool(checked[identity(asset)].selected)
func jobs(assets: Array) -> Array:
	var result := []
	for asset: Dictionary in assets:
		if not checked.has(identity(asset)):continue
		var state: Dictionary=checked[identity(asset)]
		if not state.selected or not registry.can_download(asset):continue
		for option: Dictionary in options(asset):
			if state.include_existing or not registry.inventory.has_version(asset,str(option.id)):result.append({"asset":asset.duplicate(true),"version":str(option.id)})
	return result
