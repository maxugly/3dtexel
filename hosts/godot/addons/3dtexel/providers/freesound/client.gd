@tool
extends Node
const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
## Freesound HTTP client with rate pacing and caching.

const Cache = preload("res://addons/3dtexel/providers/freesound/cache.gd")

var cache := Cache.new()
var allowed_thumbnails := {}
var network_allowed := false
var refreshing := false
var last_network_request_ms := -1000
var active: Array[HTTPRequest] = []
var transport_generation := 0
var custom_key := ""

const BASE_URL := "https://freesound.org"

func cancel_all() -> void:
	transport_generation+=1;last_network_request_ms=-1000
	Thumbnail.finish_tasks(self)
	Transport.cancel_all(active)

func pace_request() -> void:
	var now := Time.get_ticks_msec()
	var slot := maxi(now,last_network_request_ms+100)
	last_network_request_ms=slot
	if slot>now:await get_tree().create_timer((slot-now)/1000.0).timeout
func api_key() -> String:
	if not custom_key.strip_edges().is_empty():return custom_key.strip_edges()
	return OS.get_environment("FREESOUND_API_KEY").strip_edges()
func oauth_token() -> String:
	return OS.get_environment("FREESOUND_OAUTH_ACCESS_TOKEN").strip_edges()
static func api_url(url: String) -> bool:
	return url.begins_with(BASE_URL+"/apiv2/")
static func original_download_url(url: String,id := "") -> bool:
	var found := RegEx.create_from_string("^https://freesound\\.org/apiv2/sounds/([0-9]+)/download/$").search(url)
	return found!=null and (id.is_empty() or found.get_string(1)==id)
func download_headers(url: String) -> PackedStringArray:
	var headers := PackedStringArray(["User-Agent: 3dtexel-AssetLibrary/1.0"])
	if original_download_url(url) and not oauth_token().is_empty():headers.append("Authorization: Bearer "+oauth_token())
	return headers

func search(query := "", page := 1, page_size := 24) -> Dictionary:
	page=maxi(1,page);page_size=clampi(page_size,1,24)
	var endpoint := "%s/apiv2/search/?page=%d&page_size=%d&fields=id,name,url,description,username,license,previews,images,duration,samplerate,channels,filesize,type,tags,download" % [BASE_URL, page, page_size]
	var q := query.strip_edges()
	if not q.is_empty():
		endpoint += "&query=" + q.uri_encode()
	else:
		endpoint += "&query="

	return await json_request(endpoint)

func fetch_sound(id: String) -> Dictionary:
	if not id.is_valid_int() or int(id)<1:return {"error":"Invalid Freesound ID."}
	return await json_request(BASE_URL+"/apiv2/sounds/"+id+"/")
func api_headers(url: String) -> PackedStringArray:
	var headers := PackedStringArray(["Accept: application/json","User-Agent: 3dtexel-AssetLibrary/1.0"])
	if api_url(url):
		if not oauth_token().is_empty():headers.append("Authorization: Bearer "+oauth_token())
		elif not api_key().is_empty():headers.append("Authorization: Token "+api_key())
	return headers

func json_request(full_url: String) -> Dictionary:
	if not api_url(full_url):return {"error":"Only the Freesound HTTPS API origin is permitted."}

	if not network_allowed:
		return {"error": "Network requests require explicit action."}

	if api_key().is_empty() and oauth_token().is_empty():return {"error":"Configure FREESOUND_API_KEY for live Freesound searches.","credentials_required":true}
	var generation := transport_generation
	await pace_request()
	if generation!=transport_generation:return {"error":"Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 30
	request.max_redirects = 0
	request.body_size_limit = 16 * 1024 * 1024
	add_child(request)
	active.append(request)

	var headers := api_headers(full_url)

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

	if original_download_url(url) and oauth_token().is_empty():return {"error":"Original Freesound downloads require an OAuth access token."}
	if not network_allowed and not allowed_thumbnails.has(url):
		return {"error": "Network downloads require explicit authorization."}

	if redirects_left <= 0:
		return {"error": "Too many redirects."}

	var generation := transport_generation
	if not (destination.is_empty() and allowed_thumbnails.has(url)):
		await pace_request()
	if generation!=transport_generation:return {"error":"Request cancelled."}

	var request := Transport.create_request()
	request.timeout = 10 if allowed_thumbnails.has(url) and destination.is_empty() else 60
	request.max_redirects=0
	request.use_threads = true
	request.body_size_limit = max_bytes
	if not destination.is_empty():
		request.download_file = destination

	add_child(request)
	active.append(request)

	var headers := download_headers(url)

	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		active.erase(request)
		request.queue_free()
		return {"error": "Could not start download (%s)." % error}

	var response: Array = await request.request_completed
	active.erase(request)
	request.queue_free()

	var status_code: int = int(response[1])
	if response[0] in [HTTPRequest.RESULT_SUCCESS,HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED] and status_code in [301, 302, 303, 307, 308]:
		var location := ""
		var resp_headers: PackedStringArray = response[2]
		for h in resp_headers:
			if h.to_lower().begins_with("location:"):
				location = h.substr(9).strip_edges()
				break
		location=Transport.thumbnail_redirect(allowed_thumbnails,url,location)
		if not location.is_empty():
			return await get_bytes(location, destination, max_bytes, redirects_left - 1)

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Download failed (%s)." % response[0]}

	if status_code != 200:
		return {"error": "Download returned HTTP %s." % status_code}

	if not destination.is_empty():
		return {"path": destination}
	return {"bytes": response[3]}

func thumbnail(url: String) -> Texture2D:
	return await Thumbnail.load_for(self,url)
