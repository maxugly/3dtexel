@tool
extends Node
## Official REST API. Credentials are environment-only and never sent to file hosts.
const BASE := "https://3dtexel.com/wp-json/3dtexel-api/v1"
const KEY_NAMES := ["3DTEXEL_API_KEY", "TEXEL_API_KEY", "TEXEL"]
var active: Array[HTTPRequest] = []
func api_key() -> String:
	for name in KEY_NAMES:
		var value := OS.get_environment(name).strip_edges()
		if not value.is_empty(): return value
	return ""
func cancel_all() -> void:
	for request in active:
		if is_instance_valid(request): request.cancel_request()
func json_request(path: String, method := HTTPClient.METHOD_GET, body := {}) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 35
	request.max_redirects = 0
	request.body_size_limit = 8 * 1024 * 1024
	add_child(request)
	active.append(request)
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: Godot3DTexel/0.1"])
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
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if int(response[1]) < 200 or int(response[1]) >= 300:
		var code := "HTTP %s" % response[1]
		if data is Dictionary and data.get("error") is Dictionary: code = str(data.error.get("code",code))
		return {"error":code,"status":int(response[1])}
	if data is not Dictionary: return {"error":"The server returned an unexpected response."}
	return data
func get_bytes(url: String, destination := "", max_bytes := 67108864, redirects_left := 5) -> Dictionary:
	if not url.begins_with("https://"): return {"error":"Only HTTPS downloads are supported."}
	var request := HTTPRequest.new()
	request.timeout = 120
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
				var location := header.substr(header.find(":")+1).strip_edges()
				if not location.begins_with("https://"): return {"error":"Refused a non-HTTPS or relative download redirect."}
				return await get_bytes(location,destination,max_bytes,redirects_left-1)
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"error":"File download failed (HTTP %s, result %s). Retry to obtain fresh links." % [response[1],response[0]]}
	return {"bytes":response[3]}
func thumbnail(url: String) -> Texture2D:
	var result := await get_bytes(url,"",8*1024*1024)
	if result.has("error"): return null
	var image := Image.new()
	var bytes: PackedByteArray = result.bytes
	var error := image.load_webp_from_buffer(bytes)
	if error != OK: error = image.load_png_from_buffer(bytes)
	if error != OK: error = image.load_jpg_from_buffer(bytes)
	if error != OK: return null
	image.resize(192,192,Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)
