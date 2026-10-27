@tool
extends Node
const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
## Official REST API. Credentials are environment-only and never sent to file hosts.
const Cache = preload("res://addons/3dtexel/providers/texel/cache.gd")
var cache := Cache.new()
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var allowed_thumbnails := {}
const Metadata = preload("res://addons/3dtexel/providers/texel/metadata.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const BASE := "https://3dtexel.com/wp-json/3dtexel-api/v1"
const KEY_NAMES := ["3D_TEXEL_API_KEY", "3DTEXEL_API_KEY", "TEXEL_API_KEY", "TEXEL"]
var session_key := ""
var active: Array[HTTPRequest] = []
var transport_generation := 0
var response_validators := {}
func api_key() -> String:
	if not session_key.strip_edges().is_empty():return session_key.strip_edges()
	for name in KEY_NAMES:
		var value := OS.get_environment(name).strip_edges()
		if not value.is_empty(): return value
	return ""
func cancel_all() -> void:
	transport_generation+=1;last_network_request_ms=-1000
	Thumbnail.finish_tasks(self)
	Transport.cancel_all(active)

func json_request(path: String, method := HTTPClient.METHOD_GET, body := {}) -> Dictionary:
	if method!=HTTPClient.METHOD_GET and not network_allowed:return {"error":"Downloads require an explicit user action."}
	if method==HTTPClient.METHOD_GET and Cache.cacheable(path):
		if not refreshing:
			var cached := cache.get_response(path)
			if not cached.is_empty():return cached
		if not network_allowed:return {"error":"Asset details are not available yet."}
	if not network_allowed:return {"error":"Network requests require explicit action."}
	var result := await transport_json(path,method,body)
	if method==HTTPClient.METHOD_GET:cache.put_response(path,result,response_validators.get(path,{}))
	return result
func transport_json(path: String, method := HTTPClient.METHOD_GET, body := {}) -> Dictionary:
	if not network_allowed:return {"error":"Network requests require explicit action."}
	if not path.begins_with("/") or path.begins_with("//") or ".." in path or "#" in path:return {"error":"Invalid API path."}
	var generation := transport_generation
	var now := Time.get_ticks_msec();var slot := maxi(now,last_network_request_ms+100)
	last_network_request_ms=slot
	if slot>now:await get_tree().create_timer((slot-now)/1000.0).timeout
	if generation!=transport_generation:return {"error":"Request cancelled."}
	var request := Transport.create_request()
	request.timeout = 35
	request.max_redirects = 0
	request.body_size_limit = 8 * 1024 * 1024
	add_child(request)
	active.append(request)
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: Godot3DTexel/0.1"])
	if method==HTTPClient.METHOD_GET:headers.append_array(cache.conditional_headers(path))
	var key := api_key()
	if not key.is_empty(): headers.append("Authorization: Bearer " + key)
	if method != HTTPClient.METHOD_GET:
		headers.append("Content-Type: application/json")
		headers.append("Idempotency-Key: godot-%s-%s" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()])
	var error := request.request(BASE + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if error != OK:
		active.erase(request); request.queue_free()
		return {"error":"Could not start request (%s)." % error}
	var response: Array = await request.request_completed
	active.erase(request); request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS: return {"error":"Connection failed (%s). Check your connection and retry." % response[0]}
	if int(response[1])==304:
		var cached := cache.get_response(path)
		return cached if not cached.is_empty() else {"error":"The site returned an unchanged response without local metadata."}
	var validators := {}
	if method==HTTPClient.METHOD_GET and Cache.cacheable(path):
		for header: String in response[2]:
			if header.to_lower().begins_with("etag:"):validators.etag=header.substr(header.find(":")+1).strip_edges()
			elif header.to_lower().begins_with("last-modified:"):validators.last_modified=header.substr(header.find(":")+1).strip_edges()
		response_validators[path]=validators
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if int(response[1]) < 200 or int(response[1]) >= 300:
		var code := "HTTP %s" % response[1]
		if data is Dictionary and data.get("error") is Dictionary: code = str(data.error.get("code",code))
		return {"error":code,"status":int(response[1])}
	if data is not Dictionary: return {"error":"The server returned an unexpected response."}
	return data
func get_bytes(url: String, destination := "", max_bytes := 67108864, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"): return {"error":"Only HTTPS downloads are supported."}
	if not network_allowed and not allowed_thumbnails.has(url):return {"error":"Downloads require explicit action."}
	var request := Transport.create_request()
	request.timeout = 120
	if destination.is_empty() and allowed_thumbnails.has(url):request.timeout=10
	request.body_size_limit=max_bytes
	request.max_redirects = 0
	request.body_size_limit = max_bytes
	if not destination.is_empty(): request.download_file = destination
	add_child(request); active.append(request)
	# Deliberately NO authorization header on CDN/signed download URLs.
	var error := request.request(url)
	if error != OK:
		active.erase(request); request.queue_free()
		return {"error":"Could not start file download."}
	var response: Array = await request.request_completed
	active.erase(request); request.queue_free()
	if response[0] in [HTTPRequest.RESULT_SUCCESS,HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED] and int(response[1]) in [301,302,303,307,308] and redirects_left > 0:
		for header: String in response[2]:
			if header.to_lower().begins_with("location:"):
				var location := Transport.thumbnail_redirect(allowed_thumbnails,url,header.substr(header.find(":")+1).strip_edges())
				if not location.begins_with("https://"): return {"error":"Refused a non-HTTPS or relative download redirect."}
				return await get_bytes(location,destination,max_bytes,redirects_left-1)
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"error":"File download failed (HTTP %s, result %s). Retry to obtain fresh links." % [response[1],response[0]]}
	return {"path":destination} if not destination.is_empty() else {"bytes":response[3]}
func thumbnail(url: String) -> Texture2D:
	return await Thumbnail.load_for(self,url)

func enrich_asset(asset: Dictionary, force := false) -> Dictionary:
	cache.ensure_loaded()
	var path := cache.root.path_join("page_%s.json" % int(asset.id))
	var extra := {}
	if FileAccess.file_exists(path) and not force:
		var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary:extra=saved
	elif network_allowed and (Credits.authors(asset).is_empty() or Credits.available_resolutions(asset).is_empty()):
		var url := str(asset.get("url",""))
		if url.begins_with("https://3dtexel.com/product/"):
			var response := await get_bytes(url,"",4*1024*1024)
			if not response.has("error"):
				extra=Metadata.from_html(response.bytes.get_string_from_utf8(),url)
				Credits.write_json(path,extra)
	if Credits.authors(asset).is_empty() and extra.has("author"):asset.author=extra.author
	if Credits.available_resolutions(asset).is_empty() and extra.has("formats"):asset.formats=extra.formats
	if extra.has("metadata_source_url"):asset.metadata_source_url=extra.metadata_source_url
	cache.upsert(asset)
	Credits.write_json(cache.root.path_join("catalog.json"),cache.catalog)
	return asset
