@tool
extends Node
## Openverse HTTP client with rate pacing and caching.

const Cache = preload("res://addons/3dtexel/providers/openverse/cache.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var active: Array[HTTPRequest] = []

const BASE_URL := "https://api.openverse.org"

func cancel_all() -> void:
	for request in active:
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	active.clear()

func pace_request() -> void:
	var elapsed := Time.get_ticks_msec() - last_network_request_ms
	var remaining := 500 - elapsed
	if remaining > 0:
		await get_tree().create_timer(remaining / 1000.0).timeout
	last_network_request_ms = Time.get_ticks_msec()

func search(query := "", category := "image", page := 1, page_size := 24) -> Dictionary:
	var media_path := "audio" if category == "audio" else "images"
	# Anonymous requests are capped at twenty records per page; asking for more
	# is answered with a 401 that only says the page size is too large.
	page_size = clampi(page_size, 1, 20)
	var endpoint := "%s/v1/%s/?page=%d&page_size=%d" % [BASE_URL, media_path, page, page_size]
	var q := query.strip_edges()
	if not q.is_empty():
		endpoint += "&q=" + q.uri_encode()
	return await json_request(endpoint)

func json_request(full_url: String) -> Dictionary:
	if not full_url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}

	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	await pace_request()

	var request := HTTPRequest.new()
	request.timeout = 30
	request.max_redirects = 3
	request.body_size_limit = 16 * 1024 * 1024
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])

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
	if status_code != 200:
		return {"error": "Site returned HTTP %s." % status_code}

	var body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {"error": "Invalid JSON response."}

func get_bytes(url: String, destination := "", max_bytes := 67108864, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS URLs are permitted."}

	if not network_allowed:
		return {"error": "Network downloads require explicit authorization."}

	if redirects_left <= 0:
		return {"error": "Too many redirects."}

	await pace_request()

	var request := HTTPRequest.new()
	request.timeout = 60
	request.use_threads = true
	request.body_size_limit = max_bytes
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
		return {"error": "Could not start download (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	var status_code: int = int(response[1])
	if status_code in [301, 302, 303, 307, 308]:
		var location := ""
		var resp_headers: PackedStringArray = response[2]
		for h in resp_headers:
			if h.to_lower().begins_with("location:"):
				location = h.substr(9).strip_edges()
				break
		if location.begins_with("/"):
			location = BASE_URL + location
		if not location.is_empty():
			return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Download failed (%s)." % response[0]}

	if status_code != 200:
		return {"error": "Download returned HTTP %s." % status_code}

	if not destination.is_empty():
		return {"path": destination}
	return {"bytes": response[3]}
