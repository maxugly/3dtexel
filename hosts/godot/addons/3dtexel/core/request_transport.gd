@tool
extends RefCounted
## Shared transport mechanics; URLs, headers and pacing remain in each provider.
static func create_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	request.use_threads=true
	return request

static func cancel_all(active: Array[HTTPRequest]) -> void:
	# HTTPRequest.cancel_request() does not emit request_completed. Resume awaiters
	# explicitly so cancelled thumbnails and searches always release their slots.
	var requests := active.duplicate()
	active.clear()
	for request in requests:
		if not is_instance_valid(request) or request.is_queued_for_deletion():continue
		request.cancel_request()
		request.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED,0,PackedStringArray(),PackedByteArray())
		if is_instance_valid(request):request.queue_free()

static func thumbnail_redirect(allowed: Dictionary,source: String,location: String) -> String:
	var target := resolve_redirect(source,location)
	# A redirect is part of the same explicitly requested image, even after the
	# metadata search has switched its global network permission back off.
	if not target.is_empty() and allowed.has(source):allowed[target]=true
	return target

static func resolve_redirect(source: String,location: String) -> String:
	if not source.begins_with("https://") or location.is_empty():return ""
	if location.begins_with("https://"):return location
	if location.begins_with("//"):return "https:"+location
	if ":" in location.get_slice("/",0):return ""
	var origin := "https://"+source.trim_prefix("https://").get_slice("/",0).get_slice("?",0).get_slice("#",0)
	if location.begins_with("/"):return origin+location
	var clean := source.get_slice("?",0).get_slice("#",0)
	if location.begins_with("?"):return clean+location
	var directory := origin if clean==origin else clean.get_base_dir()
	return directory+"/"+location
