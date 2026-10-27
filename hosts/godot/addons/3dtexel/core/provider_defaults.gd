@tool
extends RefCounted
## Bundled providers start checked only after a complete, explicit live check.
## This file reads public verification evidence; it never performs network work.
const REVISION := "live-2026-10-26-v3"
const EVIDENCE_PATH := "res://addons/3dtexel/provider_verification.json"
static var _loaded := false
static var _modified := -1
static var _records: Dictionary={}
static func records() -> Dictionary:
	var modified := FileAccess.get_modified_time(EVIDENCE_PATH)
	if not _loaded or modified!=_modified:
		_loaded=true;_modified=modified;_records={}
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
		if value is Dictionary and value.get("providers") is Dictionary:_records=value.providers
	return _records
static func bundled(provider: Node,_id: String) -> bool:
	var script: Script=provider.get_script()
	return script!=null and script.resource_path.begins_with("res://addons/3dtexel/providers/") and script.resource_path.ends_with("/provider.gd")
static func verified(id: String) -> bool:
	return complete(records().get(id,{}))
static func complete(entry: Variant) -> bool:
	if not entry is Dictionary:return false
	for stage in ["passed","search","ui_image","download","valid_asset"]:
		if not entry.get(stage) is bool or not entry[stage]:return false
	for field in ["asset_id","variant"]:
		if not entry.get(field) is String or str(entry[field]).is_empty():return false
	return true
static func reason(id: String) -> String:
	var value: Variant=records().get(id,{})
	var entry: Dictionary=value if value is Dictionary else {}
	var status := str(entry.get("reason","not_yet_verified")).replace("_"," ")
	if verified(id):return "Live verified: search, UI image, asset download and content validation (%s)." % str(entry.get("checked_date","date not recorded"))
	return "Unchecked by default: %s. Requires a live search, visible image and validated asset download before default enablement." % status
