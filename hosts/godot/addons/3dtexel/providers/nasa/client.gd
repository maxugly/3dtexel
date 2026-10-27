@tool
extends Node
const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
## NASA Images HTTP client for images-api.nasa.gov with pacing and disk caching.

const Cache = preload("res://addons/3dtexel/providers/nasa/cache.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var allowed_thumbnails := {}
var active: Array[HTTPRequest] = []
var transport_generation := 0

const BASE_URL := "https://images-api.nasa.gov"

func cancel_all() -> void:
	transport_generation+=1
	Thumbnail.finish_tasks(self)
	Transport.cancel_all(active)

func pace_request() -> void:
	var elapsed := Time.get_ticks_msec() - last_network_request_ms
	var remaining := 100 - elapsed
	if remaining > 0:
		await get_tree().create_timer(remaining / 1000.0).timeout
	last_network_request_ms = Time.get_ticks_msec()

func json_request(path_or_url: String) -> Dictionary:
	var full_url := path_or_url if path_or_url.begins_with("https://") else BASE_URL + path_or_url
	if not full_url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}

	if Cache.cacheable(full_url) and not refreshing:
		var cached: Dictionary = cache.get_response(full_url)
		if not cached.is_empty():
			return cached

	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	var generation := transport_generation
	await pace_request()
	if generation!=transport_generation:return {"error":"Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 30
	request.max_redirects = 0
	request.body_size_limit = 8 * 1024 * 1024
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: GodotAssetLibrary/1.0 (NASA Provider; +https://github.com/godotengine)"
	])
	headers.append_array(cache.conditional_headers(full_url))

	var error := request.request(full_url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed (%s). Check connection and retry." % response[0]}

	var status_code: int = int(response[1])
	if status_code == 304:
		var cached: Dictionary = cache.get_response(full_url)
		if not cached.is_empty():
			return cached
		return {"error": "Site reported 304 Not Modified without prior cached data."}

	if status_code in [301, 302, 303, 307, 308]:
		for header: String in response[2]:
			if header.to_lower().begins_with("location:"):
				var loc := header.substr(header.find(":") + 1).strip_edges()
				if not loc.begins_with("https://"):
					return {"error": "Refused redirect to non-HTTPS URL."}
				return await json_request(loc)

	if status_code < 200 or status_code >= 300:
		return {"error": "HTTP %s" % status_code, "status": status_code}

	var body_bytes: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
	if parsed is not Dictionary:
		return {"error": "Expected JSON dictionary response from NASA API."}

	var validators := {}
	for header: String in response[2]:
		if header.to_lower().begins_with("etag:"):
			validators.etag = header.substr(header.find(":") + 1).strip_edges()
		elif header.to_lower().begins_with("last-modified:"):
			validators.last_modified = header.substr(header.find(":") + 1).strip_edges()

	if Cache.cacheable(full_url):
		cache.put_response(full_url, parsed, validators)

	return parsed

func get_bytes(url: String, destination := "", max_bytes := 67108864, redirects_left := 5) -> Dictionary:
	if url.begins_with("http://"):
		url = "https://" + url.substr(7)
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS downloads are supported."}
	if not network_allowed and not allowed_thumbnails.has(url):
		return {"error": "Network downloads require explicit action."}

	var request := Transport.create_request()
	request.timeout = 120
	if destination.is_empty() and allowed_thumbnails.has(url):request.timeout=10
	request.body_size_limit=max_bytes
	request.max_redirects = 0
	if not destination.is_empty():
		request.download_file = destination
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"User-Agent: GodotAssetLibrary/1.0 (NASA Provider)"
	])
	var error := request.request(url, headers)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start file download (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED] and int(response[1]) in [301, 302, 303, 307, 308] and redirects_left > 0:
		for header: String in response[2]:
			if header.to_lower().begins_with("location:"):
				var raw_loc := header.substr(header.find(":") + 1).strip_edges()
				if raw_loc.begins_with("http://"):
					raw_loc = "https://" + raw_loc.substr(7)
				var location := Transport.thumbnail_redirect(allowed_thumbnails,url,raw_loc)
				if not location.begins_with("https://"):
					return {"error": "Refused a non-HTTPS download redirect."}
				return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"error": "File download failed (HTTP %s, result %s)." % [response[1], response[0]]}

	return {"bytes": response[3]}

func thumbnail(url: String) -> Texture2D:
	return await Thumbnail.load_for(self,url)
