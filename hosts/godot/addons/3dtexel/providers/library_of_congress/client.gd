@tool
extends Node
const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
## Library of Congress HTTP client with rate pacing and disk caching.

const Cache = preload("res://addons/3dtexel/providers/library_of_congress/cache.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var allowed_thumbnails := {}
var active: Array[HTTPRequest] = []
var transport_generation := 0

const BASE_URL := "https://www.loc.gov"

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
	request.max_redirects = 3
	request.body_size_limit = 16 * 1024 * 1024
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
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
				var target: String = header.split(":", false, 1)[1].strip_edges()
				if not target.begins_with("https://"):
					return {"error": "Insecure or invalid redirect."}
				return await json_request(target)

	if status_code != 200:
		return {"error": "Site returned HTTP %s." % status_code}

	var body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var data := {}
	if parsed is Dictionary:
		data = parsed
	elif parsed is Array:
		data = {"items": parsed}

	var validators := {}
	for header: String in response[2]:
		var lower := header.to_lower()
		if lower.begins_with("etag:"):
			validators["etag"] = header.split(":", false, 1)[1].strip_edges()
		elif lower.begins_with("last-modified:"):
			validators["last_modified"] = header.split(":", false, 1)[1].strip_edges()

	cache.put_response(full_url, data, validators)
	return data

func search(query: String = "", offset: int = 0, limit: int = 24) -> Dictionary:
	var q := query.strip_edges()
	var page := int(offset / limit) + 1
	var path := "/pictures/search/?fo=json&c=" + str(limit) + "&sp=" + str(page)
	if not q.is_empty():
		path += "&q=" + q.uri_encode()
	return await json_request(path)

func get_bytes(url: String, destination: String, max_bytes: int, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS downloads are supported."}
	if not network_allowed and not allowed_thumbnails.has(url):
		return {"error": "Network downloads require explicit action."}

	var generation := transport_generation
	if not (destination.is_empty() and allowed_thumbnails.has(url)):
		await pace_request()
	if generation!=transport_generation:return {"error":"Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 180
	if destination.is_empty() and allowed_thumbnails.has(url):request.timeout=10
	request.body_size_limit=max_bytes
	request.use_threads = true
	request.max_redirects = 0
	if not destination.is_empty():
		request.download_file = destination
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])
	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not begin download (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED] and int(response[1]) in [301, 302, 303, 307, 308] and redirects_left > 0:
		for header: String in response[2]:
			if header.to_lower().begins_with("location:"):
				var location := Transport.thumbnail_redirect(allowed_thumbnails,url,header.substr(header.find(":") + 1).strip_edges())
				if not location.begins_with("https://"):
					return {"error": "Refused a non-HTTPS download redirect."}
				return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"error": "File download failed (HTTP %s, result %s)." % [response[1], response[0]]}

	return {"bytes": response[3]}

func thumbnail(url: String) -> Texture2D:
	return await Thumbnail.load_for(self,url)
