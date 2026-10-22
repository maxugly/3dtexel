@tool
extends Node
## Kenney HTTP client with pacing and disk caching.

const Cache = preload("res://addons/3dtexel/providers/kenney/cache.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var allowed_thumbnails := {}
var active: Array[HTTPRequest] = []

const BASE_URL := "https://kenney.nl"

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

func json_request(path_or_url: String) -> Dictionary:
	var fetched: Dictionary=await _fetch(path_or_url)
	if fetched.has("error"):
		return fetched
	var body := str(fetched.get("body",""))
	var parsed: Variant = JSON.parse_string(body)
	var data := {}
	if parsed is Dictionary:
		data = parsed
	elif parsed is Array:
		data = {"items": parsed}
	else:
		data = {"raw_text": body}
	var validators := {}
	for header: String in fetched.get("headers",[]):
		var lower := header.to_lower()
		if lower.begins_with("etag:"):
			validators["etag"] = header.split(":", false, 1)[1].strip_edges()
		elif lower.begins_with("last-modified:"):
			validators["last_modified"] = header.split(":", false, 1)[1].strip_edges()
	cache.put_response(str(fetched.get("url","")), data, validators)
	return data

## Reads a page as text. Used for the HTML listings this provider is built on.
func text_request(path_or_url: String) -> Dictionary:
	var fetched: Dictionary=await _fetch(path_or_url)
	if fetched.has("error"):
		return fetched
	return {"raw_text": str(fetched.get("body",""))}

## Performs the paced request, following safe redirects, and returns the body.
func _fetch(path_or_url: String) -> Dictionary:
	var full_url := path_or_url if path_or_url.begins_with("https://") else BASE_URL + path_or_url
	if not full_url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}

	if Cache.cacheable(full_url) and not refreshing:
		var cached: Dictionary = cache.get_response(full_url)
		if not cached.is_empty():
			return {"url":full_url,"headers":[],"body":str(cached.get("raw_text",""))}

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
		"Accept: text/html, application/json",
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
			return {"url":full_url,"headers":[],"body":str(cached.get("raw_text",""))}
		return {"error": "Site reported 304 Not Modified without prior cached data."}

	if status_code in [301, 302, 303, 307, 308]:
		for header: String in response[2]:
			if header.to_lower().begins_with("location:"):
				var target: String = header.split(":", false, 1)[1].strip_edges()
				if not target.begins_with("https://"):
					return {"error": "Insecure or invalid redirect."}
				return await _fetch(target)

	if status_code != 200:
		return {"error": "Site returned HTTP %s." % status_code}

	return {"url":full_url,"headers":response[2],"body":response[3].get_string_from_utf8()}

func fetch_packs(query := "",page := 1) -> Dictionary:
	var path := "/assets" if page<=1 else "/assets/page:%d" % page
	if not query.strip_edges().is_empty():
		path += "?search=" + query.uri_encode()
	return await text_request(path)

## Reads one pack page, used to resolve the direct archive link.
func fetch_pack_page(id: String) -> Dictionary:
	return await text_request("/assets/" + id.uri_encode())

func get_bytes(url: String, destination: String, max_bytes: int, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS downloads are supported."}
	if not network_allowed and not allowed_thumbnails.has(url):
		return {"error": "Network downloads require explicit action."}

	await pace_request()

	var request := HTTPRequest.new()
	request.timeout = 120
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
				var location := header.substr(header.find(":") + 1).strip_edges()
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
