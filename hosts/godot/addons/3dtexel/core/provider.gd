@tool
extends Node
## Provider contract v1. No UI, native packing or scene traversal in adapters.
var enabled := true
var network_allowed := false
var refreshing := false

## Providers whose host cannot be queried programmatically (WAF blocks, retired
## services, dead domains) opt out of the default sweep and say why. A user can
## still enable them by hand from the site list.
func default_enabled() -> bool:return true
func disabled_reason() -> String:return ""
func descriptor() -> Dictionary:
	return {"id":"","name":"","website":"","key_env":[],"capabilities":[]}
func api_key() -> String:return ""
func set_session_key(_value: String) -> void:pass
func credential_status() -> String:return "No key required."
func can_download(_asset: Dictionary) -> bool:return false
func local_assets() -> Array:return []
func local_import_roots() -> Array:return []
func asset_details(asset: Dictionary) -> Dictionary:return await refresh_asset(asset)
func refresh_page(_query: String,_category: String,_cursor: String) -> Dictionary:
	return {"error":"Provider does not implement refresh_page."}
func refresh_asset(_asset: Dictionary) -> Dictionary:
	return {"error":"Provider does not implement refresh_asset."}
func resolve_download(_asset: Dictionary,_variant: String) -> Dictionary:
	return {"error":"Provider does not implement resolve_download."}
func variants(asset: Dictionary) -> Array:return asset.get("variants",[])
func thumbnail(_url: String) -> Texture2D:return null
func get_bytes(_url: String,_destination: String,_limit: int) -> Dictionary:
	return {"error":"Provider does not implement downloads."}
func check_connection() -> Dictionary:return {"ok":true}
func legacy_folder(_output: String,_asset: Dictionary,_variant: String) -> String:return ""
func cancel_all() -> void:pass
