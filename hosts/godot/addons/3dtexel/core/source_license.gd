@tool
extends RefCounted
## Preserve source CC terms and versions rather than guessing CC0/CC-BY 4.0.
const Credits = preload("res://addons/3dtexel/credits.gd")
static func record(value: Variant,version := "") -> Dictionary:
	if value is Dictionary:return Credits.license_record(value)
	var text := str(value).strip_edges();var code := text.to_lower().replace(" ","-")
	if code in ["cc0","cc0-1.0"] or RegEx.create_from_string("^https?://creativecommons\\.org/publicdomain/zero/1\\.0/?(?:deed.*)?$").search(code):
		return {"id":"cc0-1.0","name":"CC0 1.0","url":"https://creativecommons.org/publicdomain/zero/1.0/","attribution_required":false}
	if code in ["pdm","publicdomain","public-domain"] or RegEx.create_from_string("^https?://creativecommons\\.org/publicdomain/mark/1\\.0/?(?:deed.*)?$").search(code):
		return {"id":"public-domain","name":"Public Domain Mark 1.0","url":"https://creativecommons.org/publicdomain/mark/1.0/","attribution_required":false}
	var found := RegEx.create_from_string("^https?://creativecommons\\.org/licenses/(by(?:-nc)?(?:-sa|-nd)?)/([0-9]+\\.[0-9]+)/?(?:deed.*)?$").search(code)
	if found:code=found.get_string(1);version=found.get_string(2)
	var versioned := RegEx.create_from_string("^(?:cc-)?(by(?:-nc)?(?:-sa|-nd)?)-([0-9]+\\.[0-9]+)$").search(code)
	if versioned:code=versioned.get_string(1);version=versioned.get_string(2)
	code=code.trim_prefix("cc-")
	if code in ["by","by-sa","by-nd","by-nc","by-nc-sa","by-nc-nd"] and version in ["1.0","2.0","2.5","3.0","4.0"]:
		return {"id":"cc-"+code+"-"+version,"name":"CC-"+code.to_upper()+" "+version,"url":"https://creativecommons.org/licenses/"+code+"/"+version+"/","attribution_required":true}
	if code in ["by-sa","by-nd","by-nc","by-nc-sa","by-nc-nd"]:
		return {"id":"cc-"+code,"name":"CC-"+code.to_upper()+" (version not reported)","url":"","attribution_required":true}
	return {"id":"unknown","name":text if not text.is_empty() else "Unknown","url":text if text.begins_with("https://") else "","attribution_required":false}
