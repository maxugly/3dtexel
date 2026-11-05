@tool
extends Node
## BlenderKit HTTP client with pacing, caching, bearer authentication, and zero-credit downloads.

const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
const Cache = preload("res://addons/3dtexel/providers/blenderkit/cache.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var api_token := ""
var last_network_request_ms := -1000
var active: Array[HTTPRequest] = []
var transport_generation := 0

const BASE_URL := "https://www.blendkit.com"
const API_URL := "https://www.blendkit.com/api/v1"

func cancel_all() -> void:
	transport_generation += 1
	Thumbnail.finish_tasks(self)
	Transport.cancel_all(active)

func pace_request() -> void:
	var elapsed := Time.get_ticks_msec() - last_network_request_ms
	var remaining := 100 - elapsed
	if remaining > 0:
		await get_tree().create_timer(remaining / 1000.0).timeout
	last_network_request_ms = Time.get_ticks_msec()

func search(query := "", page := 1, _limit := 25) -> Dictionary:
	var q := query.strip_edges()

	# Check if query is a BlenderKit gallery URL or contains a UUID
	var regex := RegEx.new()
	regex.compile("([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})")
	var match_res := regex.search(q)
	if match_res:
		var candidate_uuid := match_res.get_string(1)
		# Try direct asset query first
		var asset_res: Dictionary = await get_asset(candidate_uuid)
		if not asset_res.has("error") and not asset_res.is_empty():
			return {"results": [asset_res], "count": 1, "next": null}

		# If 404, query gallery web page to resolve data-asset-id
		var page_url := "%s/asset-gallery-detail/%s/" % [BASE_URL, candidate_uuid]
		var html_res: Dictionary = await text_request(page_url)
		if not html_res.has("error"):
			var html_text: String = str(html_res.get("text", ""))
			var id_regex := RegEx.new()
			id_regex.compile("data-asset-id=\"([a-f0-9-]+)\"")
			var id_match := id_regex.search(html_text)
			if id_match:
				var resolved_id := id_match.get_string(1)
				var resolved_asset: Dictionary = await get_asset(resolved_id)
				if not resolved_asset.has("error") and not resolved_asset.is_empty():
					return {"results": [resolved_asset], "count": 1, "next": null}

	# Standard search API
	var endpoint := "%s/search/?asset_type=model&page=%d" % [API_URL, page]
	if not q.is_empty():
		endpoint += "&query=" + q.uri_encode()
	return await json_request(endpoint)

func get_asset(asset_id: String) -> Dictionary:
	var clean_id := asset_id.strip_edges()
	var endpoint := "%s/assets/%s/" % [API_URL, clean_id.uri_encode()]
	return await json_request(endpoint)

func get_download_url(download_endpoint: String) -> Dictionary:
	if not network_allowed:
		return {"error": "Network downloads require explicit authorization."}

	var endpoint := download_endpoint
	if not endpoint.contains("?"):
		endpoint += "?scene_uuid=00000000-0000-0000-0000-000000000000"
	elif not endpoint.contains("scene_uuid="):
		endpoint += "&scene_uuid=00000000-0000-0000-0000-000000000000"

	var generation := transport_generation
	await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 30
	request.max_redirects = 3
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: BlenderKit/3.21",
		"Platform-Version: Linux",
		"Client-Version: 1.0.0",
		"Origin-Name: Blender"
	])
	if not api_token.is_empty():
		headers.append("Authorization: Bearer " + api_token)

	var error := request.request(endpoint, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start download request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Download URL request failed (transport %d)." % int(response[0])}
	var status: int = response[1]
	if status < 200 or status >= 300:
		return {"error": "Download URL HTTP %d." % status}

	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"error": "Invalid response format from download endpoint."}
	return parsed as Dictionary

func json_request(url: String) -> Dictionary:
	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	var generation := transport_generation
	await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 20
	request.max_redirects = 5
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])
	if not api_token.is_empty():
		headers.append("Authorization: Bearer " + api_token)

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start HTTP request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Network request failed (transport %d)." % int(response[0])}
	var status: int = response[1]
	if status == 404:
		return {"error": "Not found (404)."}
	if status < 200 or status >= 300:
		return {"error": "HTTP %d response." % status}

	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {"error": "Non-dictionary response."}

func text_request(url: String) -> Dictionary:
	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	var generation := transport_generation
	await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 20
	request.max_redirects = 5
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: text/html,application/xhtml+xml",
		"User-Agent: Mozilla/5.0"
	])

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start HTTP request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Network request failed (transport %d)." % int(response[0])}
	var status: int = response[1]
	if status < 200 or status >= 300:
		return {"error": "HTTP %d response." % status}

	return {"text": response[3].get_string_from_utf8()}

func get_bytes(url: String, destination := "", max_bytes := 134217728, redirects_left := 5) -> Dictionary:
	if not network_allowed:
		return {"error": "Network downloads require explicit authorization."}
	if redirects_left <= 0:
		return {"error": "Too many redirects."}

	var generation := transport_generation
	await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 180
	request.max_redirects = 0
	request.body_size_limit = max_bytes
	if not destination.is_empty():
		request.download_file = destination
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0"
	])

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start download (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Download failed (transport %d)." % int(response[0])}

	var status: int = response[1]
	if status in [301, 302, 303, 307, 308]:
		var location := ""
		for header in response[2]:
			if header.to_lower().begins_with("location:"):
				location = header.substr(9).strip_edges()
				break
		if location.is_empty():
			return {"error": "Redirect missing Location header."}
		return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if status < 200 or status >= 300:
		return {"error": "HTTP %d during download." % status}

	if destination.is_empty():
		return {"bytes": response[3]}
	return {}
