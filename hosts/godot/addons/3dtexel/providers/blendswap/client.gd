@tool
extends Node
## Blend Swap HTTP client with pacing, caching, bearer authentication, and zero-credit downloads.

const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
const Cache = preload("res://addons/3dtexel/providers/blendswap/cache.gd")

var cache := Cache.new()
var network_allowed := false
var refreshing := false
var api_token := ""
var last_network_request_ms := -1000
var allowed_thumbnails := {}
var active: Array[HTTPRequest] = []
var transport_generation := 0

const BASE_URL := "https://blendswap.com"
const API_URL := "https://blendswap.com/api/v1"

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

func search(query := "", page := 1, limit := 25) -> Dictionary:
	var q := query.strip_edges()
	# If we have an API token, prefer the official REST API
	if not api_token.is_empty():
		var endpoint := "%s/assets?page=%d&per_page=%d" % [API_URL, page, limit]
		if not q.is_empty():
			endpoint += "&q=" + q.uri_encode()
		var res: Dictionary = await json_request(endpoint)
		if not res.has("error"):
			return res

	# Otherwise, query the public web search endpoint
	var web_path := "/3d"
	if not q.is_empty():
		web_path = "/3d/" + q.uri_encode()
	if page > 1:
		web_path += ("&" if web_path.contains("?") else "?") + "page=" + str(page)
	return await request_web_search(BASE_URL + web_path)

func get_asset(asset_id: String) -> Dictionary:
	var clean_id := asset_id.strip_edges()
	if not api_token.is_empty():
		var endpoint := "%s/assets/%s" % [API_URL, clean_id.uri_encode()]
		var res: Dictionary = await json_request(endpoint)
		if not res.has("error"):
			return res
	return await request_web_asset(BASE_URL + "/blend/" + clean_id.uri_encode())

func get_download(asset_id: int, file_id := 0) -> Dictionary:
	if not network_allowed:
		return {"error": "Network downloads require explicit authorization."}

	var endpoint := API_URL + "/downloads"
	var body_dict := {"asset_id": asset_id}
	if file_id > 0:
		body_dict["file_id"] = file_id

	var body_str := JSON.stringify(body_dict)
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
		"Content-Type: application/json",
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])
	if not api_token.is_empty():
		headers.append("Authorization: Bearer " + api_token)

	var error := request.request(endpoint, headers, HTTPClient.METHOD_POST, body_str)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start download request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed (%s)." % response[0]}

	var status_code: int = int(response[1])
	if status_code == 401 or status_code == 403:
		return {"error": "Authentication failed (HTTP %s). Check BLENDSWAP_KEY." % status_code}
	if status_code == 402:
		return {"error": "Blend Swap returned HTTP 402 (Insufficient free allowance or credits required)."}
	if status_code != 200 and status_code != 201:
		return {"error": "Download endpoint returned HTTP %s." % status_code}

	var body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"error": "Invalid download response format."}

	# Zero-credit guardrail
	var charged: bool = bool(parsed.get("charged", false))
	var spent: int = int(parsed.get("credits_spent", 0))
	var reason: String = str(parsed.get("reason", "free_allowance"))
	if charged or spent > 0 or (not reason.is_empty() and reason not in ["free_allowance", "repeat", "own_asset"]):
		return {"error": "Download blocked: requires %d paid credits. Only zero-credit assets may be imported." % spent}

	return parsed

func json_request(full_url: String) -> Dictionary:
	if not full_url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}

	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	var generation := transport_generation
	await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

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
	if not api_token.is_empty():
		headers.append("Authorization: Bearer " + api_token)

	var error := request.request(full_url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed (%s)." % response[0]}

	var status_code: int = int(response[1])
	if status_code == 401 or status_code == 403:
		return {"error": "Authentication failed (HTTP %s). Check BLENDSWAP_KEY." % status_code}
	if status_code != 200:
		return {"error": "Site returned HTTP %s." % status_code}

	var body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {"error": "Invalid JSON response."}

func request_web_search(url: String) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}
	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	var generation := transport_generation
	await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 30
	request.max_redirects = 3
	request.body_size_limit = 8 * 1024 * 1024
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"Accept: text/html,application/xhtml+xml",
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed (%s)." % response[0]}

	var status_code: int = int(response[1])
	if status_code != 200:
		return {"error": "Site returned HTTP %s." % status_code}

	var html: String = response[3].get_string_from_utf8()
	var items := parse_html_listing(html)
	return {"data": items, "pagination": {"page": 1, "per_page": items.size(), "count": items.size()}}

func request_web_asset(url: String) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS requests are permitted."}
	if not network_allowed:
		return {"error": "Network requests require explicit action."}

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
		"Accept: text/html,application/xhtml+xml",
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start request (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed (%s)." % response[0]}

	var status_code: int = int(response[1])
	if status_code != 200:
		return {"error": "Site returned HTTP %s." % status_code}

	var html: String = response[3].get_string_from_utf8()
	var asset := parse_html_asset(html, url)
	return {"data": asset}

## Parse public card listing from Blend Swap HTML
static func parse_html_listing(html: String) -> Array:
	var results := []
	var card_regex := RegEx.create_from_string("(?is)<a[^>]*href=[\"']/blend/(\\d+)[\"'][^>]*>(.*?)</a>")
	var matches := card_regex.search_all(html)
	var seen_ids := {}

	for m in matches:
		var item_id := m.get_string(1)
		if seen_ids.has(item_id):
			continue
		seen_ids[item_id] = true

		var inner := m.get_string(2)
		var title := "Blend " + item_id
		var alt_regex := RegEx.create_from_string("alt=[\"']([^\"']+)[\"']")
		var alt_m := alt_regex.search(inner)
		if alt_m:
			title = alt_m.get_string(1).xml_unescape().strip_edges()

		var thumb := ""
		var src_regex := RegEx.create_from_string("src=[\"'](https?://[^\"']+)[\"']")
		var src_m := src_regex.search(inner)
		if src_m:
			thumb = src_m.get_string(1)

		results.append({
			"id": item_id,
			"title": title,
			"url": "https://blendswap.com/blend/" + item_id,
			"thumbnail_url": thumb,
			"license": {"key": "cc-by", "name": "CC-BY", "url": "https://creativecommons.org/licenses/by/4.0/"},
			"author": {"name": "Blend Swap Artist", "url": "https://blendswap.com"}
		})
	return results

## Parse individual blend page HTML for metadata
static func parse_html_asset(html: String, page_url: String) -> Dictionary:
	var asset_id := page_url.get_file()
	var title := "Blend " + asset_id
	var desc := ""
	var license_key := "cc-by"
	var author_name := "Blend Swap Artist"
	var author_url := "https://blendswap.com"

	var title_regex := RegEx.create_from_string("(?i)<title>(.*?) - Free Blender.*?</title>")
	var tm := title_regex.search(html)
	if tm:
		title = tm.get_string(1).xml_unescape().strip_edges()

	var desc_regex := RegEx.create_from_string("(?i)<meta\\s+name=[\"']description[\"']\\s+content=[\"']([^\"']+)[\"']")
	var dm := desc_regex.search(html)
	if dm:
		desc = dm.get_string(1).xml_unescape().strip_edges()
		if desc.to_lower().contains("cc0") or desc.to_lower().contains("cc-0"):
			license_key = "cc0"
		elif desc.to_lower().contains("cc-by-sa"):
			license_key = "cc-by-sa"
		elif desc.to_lower().contains("cc-by"):
			license_key = "cc-by"

	var author_regex := RegEx.create_from_string("href=[\"'](/profile/\\d+)[\"'][^>]*>([^<]+)</a>")
	var am := author_regex.search(html)
	if am:
		author_url = "https://blendswap.com" + am.get_string(1)
		author_name = am.get_string(2).xml_unescape().strip_edges()

	return {
		"id": asset_id,
		"title": title,
		"url": page_url,
		"description": desc,
		"license": {"key": license_key},
		"author": {"name": author_name, "url": author_url}
	}

func get_bytes(url: String, destination: String, max_bytes: int, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": "Only HTTPS downloads are supported."}
	if not network_allowed and not allowed_thumbnails.has(url):
		return {"error": "Network downloads require explicit action."}

	var generation := transport_generation
	if not (destination.is_empty() and allowed_thumbnails.has(url)):
		await pace_request()
	if generation != transport_generation:
		return {"error": "Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 180
	if destination.is_empty() and allowed_thumbnails.has(url):
		request.timeout = 10
	request.body_size_limit = max_bytes
	request.use_threads = true
	request.max_redirects = 0
	if not destination.is_empty():
		request.download_file = destination
	add_child(request)
	active.append(request)

	var headers := PackedStringArray([
		"User-Agent: 3dtexel-AssetLibrary/1.0 (Godot Engine; https://github.com/3dtexel)"
	])
	if not api_token.is_empty():
		headers.append("Authorization: Bearer " + api_token)

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
				var location := Transport.thumbnail_redirect(allowed_thumbnails, url, header.substr(header.find(":") + 1).strip_edges())
				if not location.begins_with("https://"):
					return {"error": "Refused a non-HTTPS download redirect."}
				return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"error": "File download failed (HTTP %s, result %s)." % [response[1], response[0]]}

	return {"bytes": response[3]}

func thumbnail(url: String) -> Texture2D:
	return await Thumbnail.load_for(self, url)
