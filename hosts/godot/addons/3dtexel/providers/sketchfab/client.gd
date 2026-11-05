@tool
extends Node
## Sketchfab REST API v3 client.

const Cache = preload("res://addons/3dtexel/providers/sketchfab/cache.gd")
const BASE_URL := "https://api.sketchfab.com/v3"

var cache: RefCounted
var network_allowed := false
var refreshing := false
var api_token := ""

func _init() -> void:
	cache = Cache.new()

func get_headers() -> PackedStringArray:
	var h := PackedStringArray(["Accept: application/json", "User-Agent: 3DTexel-AssetLibrary/0.1"])
	if not api_token.is_empty():
		h.append("Authorization: Token " + api_token)
	return h

func search(query: String, cursor := "") -> Dictionary:
	if not network_allowed:
		return {"error": "Network access disabled."}
	if api_token.is_empty():
		return {"error": "Sketchfab API key required."}

	var url := BASE_URL + "/search?type=models&downloadable=true&q=" + query.uri_encode()
	if not cursor.is_empty():
		url += "&cursor=" + cursor.uri_encode()

	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, get_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"error": "HTTP request failed"}

	var resp: Array = await http.request_completed
	http.queue_free()
	var code: int = resp[1]
	var body: PackedByteArray = resp[3]

	if code != 200:
		return {"error": "Search failed with status %d" % code}

	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json is not Dictionary:
		return {"error": "Invalid JSON response"}

	return json

func resolve_download(uid: String) -> Dictionary:
	if not network_allowed:
		return {"error": "Network access disabled."}
	if api_token.is_empty():
		return {"error": "Sketchfab API key required."}

	var url := BASE_URL + "/models/" + uid.uri_encode() + "/download"
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, get_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"error": "HTTP request failed"}

	var resp: Array = await http.request_completed
	http.queue_free()
	var code: int = resp[1]
	var body: PackedByteArray = resp[3]

	if code != 200:
		return {"error": "Download resolution failed with status %d" % code}

	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json is not Dictionary:
		return {"error": "Invalid JSON response"}

	return json
