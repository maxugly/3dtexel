@tool
extends Node
## OpenGameArt HTTP client with request pacing, disk caching and strict HTTPS.

const Cache = preload("res://addons/3dtexel/providers/opengameart/cache.gd")
const Parser = preload("res://addons/3dtexel/providers/opengameart/parser.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var allowed_thumbnails := {}
var active: Array[HTTPRequest] = []

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

func http_get_string(url: String) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}

	if Cache.cacheable(url) and not refreshing:
		var cached: Dictionary = cache.get_response(url)
		if not cached.is_empty():
			return cached

	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	await pace_request()

	var request := HTTPRequest.new()
	request.timeout = 30
	request.max_redirects = 0
	request.body_size_limit = 8 * 1024 * 1024
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
		"User-Agent: GodotAssetLibrary/1.0 (OpenGameArt Provider; +https://github.com/godotengine)"
	])
	headers.append_array(cache.conditional_headers(url))

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
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
		var cached: Dictionary = cache.get_response(url)
		if not cached.is_empty():
			return cached
		return {"error": "Site reported 304 Not Modified without prior cached data."}

	# Follow safe HTTPS redirects if needed (301, 302, 303, 307, 308)
	if status_code in [301, 302, 303, 307, 308]:
		for header: String in response[2]:
			if header.to_lower().begins_with("location:"):
				var loc := header.substr(header.find(":") + 1).strip_edges()
				if not loc.begins_with("https://"):
					loc = Parser.clean_url(loc)
				if not loc.begins_with("https://"):
					return {"error": "Refused redirect to non-HTTPS URL."}
				return await http_get_string(loc)

	if status_code < 200 or status_code >= 300:
		return {"error": "HTTP %s" % status_code, "status": status_code}

	var body_bytes: PackedByteArray = response[3]
	var body_str := body_bytes.get_string_from_utf8()
	if body_str.is_empty() and body_bytes.size() > 0:
		body_str = body_bytes.get_string_from_ascii()

	var validators := {}
	for header: String in response[2]:
		if header.to_lower().begins_with("etag:"):
			validators.etag = header.substr(header.find(":") + 1).strip_edges()
		elif header.to_lower().begins_with("last-modified:"):
			validators.last_modified = header.substr(header.find(":") + 1).strip_edges()

	var result := {"body": body_str, "status": status_code, "url": url}
	if Cache.cacheable(url):
		cache.put_response(url, result, validators)

	return result

func get_bytes(url: String, destination := "", max_bytes := 67108864, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS downloads are supported."}

	var request := HTTPRequest.new()
	request.timeout = 120
	request.max_redirects = 0
	request.body_size_limit = max_bytes
	if not destination.is_empty():
		request.download_file = destination
	add_child(request)
	active.append(request)

	# Deliberately NO authorization header on CDN/download URLs.
	var headers := PackedStringArray([
		"User-Agent: GodotAssetLibrary/1.0 (OpenGameArt Provider)"
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
				var location := header.substr(header.find(":") + 1).strip_edges()
				if not location.begins_with("https://"):
					location = Parser.clean_url(location)
				if not location.begins_with("https://"):
					return {"error": "Refused a non-HTTPS download redirect."}
				return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"error": "File download failed (HTTP %s, result %s)." % [response[1], response[0]]}

	return {"bytes": response[3]}

func thumbnail(url: String) -> Texture2D:
	var path := cache.thumbnail_path(url)
	if FileAccess.file_exists(path):
		var stored := Image.load_from_file(ProjectSettings.globalize_path(path))
		if stored:
			return ImageTexture.create_from_image(stored)

	if not allowed_thumbnails.has(url) and not network_allowed:
		return null

	var result := await get_bytes(url, "", 8 * 1024 * 1024)
	if result.has("error"):
		return null

	var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
	if bytes.is_empty():
		return null

	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 4 and bytes[0] == 137 and bytes[1] == 80:
		err = image.load_png_from_buffer(bytes)
	elif bytes.size() >= 2 and bytes[0] == 255 and bytes[1] == 216:
		err = image.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		err = image.load_webp_from_buffer(bytes)

	if err != OK:
		return null

	image.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	image.save_png(ProjectSettings.globalize_path(path))
	allowed_thumbnails.erase(url)
	return ImageTexture.create_from_image(image)
