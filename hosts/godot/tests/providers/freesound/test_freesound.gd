extends SceneTree
## Comprehensive offline contract and regression tests for Freesound provider.

const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")

const Provider = preload("res://addons/3dtexel/providers/freesound/provider.gd")
const Client = preload("res://addons/3dtexel/providers/freesound/client.gd")

class MockFreesoundClient:
	extends Client
	var calls := 0
	var downloaded_files := 0
	var fixtures := {}

	func _init() -> void:
		cache.root="user://freesound_fixture_"+str(Time.get_ticks_usec())
		cache.catalog_path=cache.root.path_join("catalog.json")
		cache.assets_path=cache.root.path_join("assets.json")
		fixtures["sounds"] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/providers/freesound/fixtures/sounds.json"))

	var requests: Array[String] = []
	var oauth_available := false
	func oauth_token() -> String:return "offline-fixture-token" if oauth_available else ""
	func api_key() -> String:return "offline-fixture-key"
	func json_request(url: String) -> Dictionary:
		calls += 1;requests.append(url)
		if not network_allowed:return {"error":"Explicit action required."}
		if url.contains("/search/?"):return fixtures.sounds.duplicate(true)
		for sound in fixtures.sounds.results:
			if url.ends_with("/sounds/"+str(sound.id)+"/"):return sound.duplicate(true)
		return {"error":"Unexpected offline endpoint."}
	func get_bytes(url: String, destination := "", _max_bytes := 67108864, _redirects_left := 5) -> Dictionary:
		if not network_allowed and not allowed_thumbnails.has(url):return {"error":"Explicit action required."}
		downloaded_files += 1
		var bytes := PackedByteArray()
		if url.ends_with(".png"):
			var image := Image.create(32,16,false,Image.FORMAT_RGBA8)
			image.fill(Color.GREEN);bytes=image.save_png_to_buffer()
		elif original_download_url(url):
			if not oauth_available:return {"error":"OAuth required."}
			bytes=FileAccess.get_file_as_bytes("res://tests/providers/freesound/fixtures/original.wav")
		elif url.ends_with(".mp3") or url.ends_with(".ogg"):
			bytes=FileAccess.get_file_as_bytes("res://tests/providers/freesound/fixtures/preview."+url.get_extension())
		else:return {"error":"Unexpected offline file."}
		if not destination.is_empty():
			var file := FileAccess.open(destination,FileAccess.WRITE)
			if not file:return {"error":"Cannot write fixture."}
			file.store_buffer(bytes);file.close();return {"path":destination}
		return {"bytes":bytes}

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting Freesound offline provider tests...")

	# 1. Descriptor and contract metadata
	var provider := Provider.new()
	root.add_child(provider)
	var desc := provider.descriptor()
	check(desc.id == "freesound", "Descriptor ID is freesound")
	check(desc.name == "Freesound", "Descriptor name matches")
	check(desc.website.contains("freesound.org"), "Website points to freesound.org")
	check(desc.capabilities.has("audio") and desc.capabilities.has("files"), "Capabilities include audio and files")
	check(desc.key_env.has("FREESOUND_API_KEY"), "Key env lists FREESOUND_API_KEY")

	# 2. Attach mock transport
	var mock := MockFreesoundClient.new()
	provider.remove_child(provider.client)
	provider.client.queue_free()
	provider.client = mock
	provider.add_child(mock)

	# 3. Category filtering (image/model/material category returns empty)
	provider.network_allowed = true
	var img_resp: Dictionary = await provider.refresh_page("", "image", "")
	check(img_resp.get("items", []).is_empty(), "Image category returns empty for audio provider")

	# 4. Network disabled enforcement
	provider.network_allowed = false
	var blocked_resp: Dictionary = await provider.refresh_page("", "audio", "")
	check(blocked_resp.has("error"), "Network disabled rejects search")

	# 5. Search and pagination
	provider.network_allowed = true
	var search_res: Dictionary = await provider.refresh_page("laser", "audio", "")
	check(not search_res.has("error"), "Search executed without error")
	var items: Array = search_res.get("items", [])
	check(items.size() == 2, "Found 2 items in mock fixtures")

	# 6. Item normalization & license policy
	var item0: Dictionary = items[0]
	check(item0.id == "12345", "Item 0 ID normalized correctly")
	check(item0.provider_id == "freesound", "Provider ID preserved")
	check(item0.type == "audio", "Item type is audio")
	check(item0.title.contains("Laser"), "Title matches fixture")
	check(item0.authors[0].name == "sound_wizard", "Author matches fixture")

	# License evaluation: item 0 is CC0 -> PERMISSIVE
	var lic0: Dictionary = item0.license
	check(lic0.id == "cc0-1.0", "License 0 is cc0-1.0")
	var eval_res0: Dictionary = Policy.evaluate(item0)
	check(eval_res0.status == Policy.Status.PERMISSIVE, "CC0 evaluates to PERMISSIVE")

	# License evaluation: item 1 is CC-BY -> ATTRIBUTION
	var item1: Dictionary = items[1]
	check(item1.id == "67890", "Item 1 ID normalized correctly")
	check(item1.type == "audio", "Item 1 type is audio")
	var lic1: Dictionary = item1.license
	check(lic1.id == "cc-by-4.0", "License 1 is cc-by-4.0")
	var eval_res1: Dictionary = Policy.evaluate(item1)
	check(eval_res1.status == Policy.Status.ATTRIBUTION, "CC-BY evaluates to ATTRIBUTION")

	# Variants
	var vars: Array = item0.variants
	check(vars.size() >= 3, "At least 3 audio variants available")
	check(vars[0].id == "mp3_hq", "First variant is mp3_hq")

	# 7. Preparation & Mock Download
	var hub := Registry.new()
	root.add_child(hub)
	hub.catalog.root = "user://freesound_reg_%s" % Time.get_ticks_usec()
	hub.inventory.root = hub.catalog.root.path_join("imports")
	for p_id in hub.providers:
		if p_id != "freesound":
			hub.providers[p_id].enabled = false

	var hub_provider: Provider = hub.providers["freesound"]
	# Explicit opt-in keeps this fixture independent of verified defaults.
	hub_provider.enabled = true
	hub_provider.network_allowed = true
	var hub_mock := MockFreesoundClient.new()
	hub_provider.remove_child(hub_provider.client)
	hub_provider.client.queue_free()
	hub_provider.client = hub_mock
	hub_provider.add_child(hub_mock)
	hub_provider.network_allowed = true

	var prep := Preparation.new()
	prep.registry = hub
	prep.output_directory = "res://AssetLibrary/freesound_%s" % Time.get_ticks_usec()
	root.add_child(prep)

	var prep_res: Dictionary = await prep.prepare(item0, vars[0].id)
	check(not prep_res.has("error"), "Preparation succeeds: "+str(prep_res.get("error","")))
	check(hub_mock.downloaded_files > 0, "Mock transport performed download")

	# Reproduce UI handoff: metadata was fetched, then image loading revoked client network.
	mock.network_allowed=false
	var result: Dictionary=await provider.get_bytes(str(item0.previews["preview-hq-mp3"]),"",1024*1024)
	check(not result.has("error"),"Download synchronizes explicit permission after cached details")
	check(AudioStreamMP3.load_from_buffer(result.get("bytes",PackedByteArray())).get_length()>0,"MP3 fixture decodes")
	var restored: Dictionary=provider.normalize(item0)
	check(restored.title==item0.title and restored.authors==item0.authors and restored.thumbnail==item0.thumbnail,"Cached name, creator and waveform survive normalization")
	check(restored.tags==item0.tags and restored.source_metadata.type=="wav","Cached source format and tags stay stable")
	var fallback: Dictionary=mock.fixtures.sounds.results[0].duplicate(true)
	fallback.images.waveform_m="";fallback.username=null
	var normalized: Dictionary=provider.normalize(fallback)
	check(normalized.thumbnail.ends_with("_spec.png") and normalized.authors.is_empty(),"Empty waveform falls back without inventing creator")
	fallback.previews=null
	check(provider.normalize(fallback).variants.is_empty(),"Null previews create no invented download choices")
	var count := mock.calls
	await provider.refresh_page("wind","model","")
	await provider.refresh_page("wind","audio","invalid")
	check(mock.calls==count,"Unsupported category and cursor make no requests")
	await mock.search("wind & rain",0,999)
	check(mock.requests.back().contains("page=1&page_size=24") and mock.requests.back().contains("query=wind%20%26%20rain"),"Search is bounded and query encoded")
	count=mock.calls
	await provider.asset_details(item0)
	check(mock.calls==count,"Existing metadata needs no repeated details request")
	var unavailable: Dictionary=item0.duplicate(true)
	unavailable.previews={"preview-lq-mp3":"https://cdn.freesound.org/offline.mp3"}
	mock.cache.catalog.clear()
	check((await provider.resolve_download(unavailable,"mp3_hq")).has("error"),"Missing high quality never substitutes low quality")
	check((await provider.resolve_download(item0,"original")).has("error"),"Originals require OAuth")
	mock.oauth_available=true
	var original: Dictionary=provider.normalize(mock.fixtures.sounds.results[0])
	check(provider.variants(original).any(func(v):return v.id=="original"),"OAuth offers explicitly reported supported originals")
	check(Client.original_download_url("https://freesound.org/apiv2/sounds/12345/download/","12345"),"Exact original endpoint accepted")
	check(not Client.original_download_url("https://freesound.org/apiv2/sounds/67890/download/","12345"),"Wrong sound original rejected")
	check(mock.download_headers("https://cdn.freesound.org/preview.mp3").size()==1,"Credentials never reach CDN")
	check(mock.api_headers("https://freesound.org.evil.test/apiv2/").size()==2,"Credentials never reach lookalike API")
	check(mock.download_headers("https://freesound.org/apiv2/sounds/12345/download/").size()==2,"OAuth authenticates exact original endpoint")
	for variant in ["mp3_hq","ogg_hq","original"]:
		hub_mock.oauth_available=true
		hub_mock.network_allowed=false
		var audio: Dictionary=hub_provider.normalize(hub_mock.fixtures.sounds.results[0])
		var prepared: Dictionary=await prep.prepare(audio,variant)
		check(not prepared.has("error"),"Real preparation succeeds for "+variant+": "+str(prepared.get("error","")))
		var versions: Dictionary=hub.inventory.versions(audio)
		check(versions.has(variant),"Import receipt records "+variant)
		if not versions.has(variant):continue
		var folder: String=versions[variant].folder
		var extension: String = "wav" if variant=="original" else variant.get_slice("_",0)
		var path := folder.path_join("12345_"+variant+"."+extension)
		var stream: AudioStream
		if extension=="mp3":stream=AudioStreamMP3.load_from_file(path)
		elif extension=="ogg":stream=AudioStreamOggVorbis.load_from_file(path)
		else:stream=AudioStreamWAV.load_from_file(path)
		check(stream!=null and stream.get_length()>0,"Imported audio decodes for "+variant)
		var provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))
		check(provenance.sha256.get(path.get_file(),"")==FileAccess.get_sha256(path),"Saved hash matches "+variant)
		check(FileAccess.file_exists(path+".credits.json") and not provenance.get("authors",[]).is_empty(),"Creator and file credits preserved for "+variant)
	for license_url in ["https://creativecommons.org/licenses/by-nc/4.0/","https://creativecommons.org/licenses/by-nd/4.0/","unknown"]:
		var denied: Dictionary=mock.fixtures.sounds.results[0].duplicate(true)
		denied.license=license_url
		check(not provider.can_download(provider.normalize(denied)),"Uncleared license blocked: "+license_url)
	var paid: Dictionary=item0.duplicate(true);paid.price={"free":false,"credits":1}
	check(not provider.can_download(paid),"Paid audio blocked")

	remove_fixture_tree(prep.output_directory)

	print("Freesound offline tests complete; failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func remove_fixture_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if not directory:return
	for child in directory.get_directories():remove_fixture_tree(path.path_join(child))
	for file in directory.get_files():directory.remove(file)
	DirAccess.remove_absolute(path)
