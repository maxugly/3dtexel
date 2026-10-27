extends SceneTree
## Manual, explicitly authorized live check. NEVER included in offline CI.
const Browser = preload("res://addons/3dtexel/browser.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
var browser: Control
var provider_id := ""
var evidence_dir := ""
var report := {"search":false,"ui_image":false,"download":false,"valid_asset":false,"passed":false,"reason":"not_started"}
func _initialize():call_deferred("run")
func run() -> void:
	if OS.get_environment("ASSET_LIBRARY_ALLOW_LIVE_CHECK")!="1":quit(2);return
	if DisplayServer.get_name()=="headless":
		push_error("A rendering display is required to verify the actual UI image.");quit(2);return
	var args := OS.get_cmdline_user_args()
	if args.size()<3:quit(2);return
	provider_id=args[0];evidence_dir=args[2]
	if not evidence_dir.begins_with("res://AssetLibrary/live-verification/") or ".." in evidence_dir:quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_dir))
	report.provider_id=provider_id;report.query=args[1];report.checked_date=OS.get_environment("ASSET_LIBRARY_LIVE_CHECK_DATE")
	if str(report.checked_date).is_empty():report.checked_date=Time.get_date_string_from_system()
	root.size=Vector2i(1400,1000)
	browser=Browser.new();root.add_child(browser);await process_frame
	browser.show_domains.set_pressed_no_signal(true)
	browser.seeded=true # isolated fresh caches; skip unrelated local import discovery
	for provider in browser.client.providers.values():provider.enabled=false
	if not browser.client.providers.has(provider_id):finish("unknown_provider");return
	var provider: Node=browser.client.providers[provider_id]
	var info: Dictionary=provider.descriptor();report.name=info.name
	var try_public := args.size()>3 and args[3]=="anonymous"
	if not info.get("key_env",[]).is_empty() and provider.api_key().is_empty() and not try_public:finish("credentials_not_configured");return
	provider.enabled=true;browser.client.scope=provider_id
	browser.client.catalog.root="user://live_catalog";browser.client.inventory.root="user://live_imports"
	browser.client.inventory.loaded=true;browser.client.inventory.records={}
	browser.search.text=args[1];browser.kind.select(0)
	browser.output.text=evidence_dir.path_join("imports")
	browser.delay.value=0
	await browser.refresh_search()
	var items: Array=browser.session.items();report.results=items.size()
	if items.is_empty():
		var outcome: Dictionary=browser.session.outcomes.get(provider_id,{})
		finish(safe_failure(str(outcome.get("error","")),"no_search_results"));return
	report.search=true
	var deadline := Time.get_ticks_msec()+22000
	while Time.get_ticks_msec()<deadline:
		browser.pump_thumbnails()
		if browser.displayed_assets().filter(cleared).size()>=3:break
		if browser.thumbnail_queue.is_empty() and browser.thumbnails_active==0:break
		await process_frame
	if browser.displayed_assets().is_empty():finish("no_image_in_ui");return
	report.ui_image=true
	var candidates: Array=browser.displayed_assets().filter(cleared).slice(0,3)
	var failure := "no_confirmed_free_download"
	for initial: Dictionary in candidates:
		var asset := initial
		if not cleared(asset):continue
		if browser.selection.options(asset,false).is_empty():
			await browser.load_options(asset)
			asset=browser.client.cached_asset(asset)
		if not cleared(asset):continue
		var options: Array=browser.selection.options(asset,false)
		options.sort_custom(func(a,b):return priority(a)<priority(b))
		var tried := 0
		for option: Dictionary in options:
			if tried>=2:break
			# An image thumbnail alone is not an asset download.
			if asset.get("type")=="image" and ("preview" in str(option.get("label","")).to_lower() or str(option.id) in ["preview","thumb","512"]):continue
			tried+=1
			browser.client.network_allowed=true
			var plan: Dictionary=await provider.resolve_download(asset,str(option.id))
			browser.client.network_allowed=false
			if plan.has("error"):failure=safe_failure(str(plan.error),"download_resolution_failed");continue
			if not cleared(plan.get("asset",asset)):failure="download_terms_not_confirmed_free";continue
			if plan.get("kind")=="files":
				var files: Array=plan.get("files",[])
				if files.size()>4:failure="asset_check_would_require_bulk_download";continue
				if asset.get("type")=="model" and not files.any(func(entry):return str(entry.get("filename","")).get_extension().to_lower() in ["glb","gltf","obj","fbx","blend","stl","zip"]):failure="download_does_not_contain_a_model";continue
			if plan.get("kind")=="files" and asset.get("type")=="image":
				var same := false
				for file in plan.get("files",[]):
					if str(file.get("url",""))==str(asset.get("thumbnail","")):same=true
				if same:failure="only_thumbnail_download_available";continue
			report.asset_id=str(asset.id);report.variant=str(option.id)
			await browser.download_one(asset,str(option.id))
			var owned: Dictionary=browser.client.inventory.versions(asset)
			if owned.is_empty():failure="asset_import_failed";continue
			var folder := str(owned.values()[0].folder)
			if not verify_asset(folder):failure="downloaded_content_invalid";continue
			report.requested_variant=str(option.id)
			report.variant=str(owned.keys()[0])
			report.download=true;report.valid_asset=true;report.import_folder=folder
			browser.run_search()
			for i in 8:await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			if frame.is_empty():failure="ui_frame_unavailable";continue
			var shown := false
			for card in browser.grid.get_children():
				var image := card.find_child("Thumbnail",true,false) as TextureRect
				if card.visible and image and image.texture and image.texture.get_width()>1 and image.is_visible_in_tree():shown=true;break
			if not shown:failure="downloaded_tile_not_visible";continue
			var screenshot := evidence_dir.path_join(provider_id+".png")
			if frame.save_png(ProjectSettings.globalize_path(screenshot))!=OK:failure="screenshot_failed";continue
			report.screenshot=screenshot;report.passed=true
			finish("verified_search_ui_image_and_asset_download");return
	finish(failure)
func cleared(asset: Dictionary) -> bool:
	var price: Dictionary=asset.get("price",{})
	if not price.get("free",false) or float(price.get("credits",0))!=0:return false
	if int(Policy.evaluate(asset).status) not in [Policy.Status.PERMISSIVE,Policy.Status.ATTRIBUTION]:return false
	var source: Dictionary=asset.get("source_metadata",{})
	if source.has("isPublicDomain") and not source.isPublicDomain:return false
	if source.has("is_public_domain") and not source.is_public_domain:return false
	return true
func priority(option: Dictionary) -> int:
	var id := str(option.id)
	if id in ["1k","1024","2k","2048","mp3_hq","ogg_hq","glb"]:return 0
	if id in ["orig","original","full","max"]:return 1
	return 2
func verify_asset(folder: String) -> bool:
	if not FileAccess.file_exists(folder.path_join("provenance.json")) or not FileAccess.file_exists(folder.path_join("asset.credits.json")):return false
	if FileAccess.file_exists(folder.path_join("material.res")):
		var material := ResourceLoader.load(folder.path_join("material.res"),"",ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
		return material!=null and material.albedo_texture!=null and material.albedo_texture.get_width()>1
	var receipt: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("import_receipt.json")))
	if not receipt is Dictionary:return false
	var verified := 0
	for name in receipt.get("sha256",{}):
		var path := folder.path_join(str(name));var extension := str(name).get_extension().to_lower()
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=str(receipt.sha256[name]):return false
		if extension in ["png","jpg","jpeg","webp","tga","exr","hdr"]:
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image==null or image.get_width()<2 or image.get_height()<2:return false
			verified+=1
		elif extension=="zip":
			var zip := ZIPReader.new()
			if zip.open(path)!=OK:return false
			var entries := zip.get_files();zip.close()
			if entries.is_empty():return false
			verified+=1
		elif extension=="glb":
			var document := GLTFDocument.new();var state := GLTFState.new()
			if document.append_from_file(ProjectSettings.globalize_path(path),state)!=OK:return false
			verified+=1
		elif extension in ["mp3","ogg","wav"]:
			var stream: AudioStream
			if extension=="mp3":stream=AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(path))
			elif extension=="ogg":stream=AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
			else:stream=AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
			if stream==null or stream.get_length()<=0:return false
			verified+=1
	return verified>0
func safe_failure(message: String,fallback: String) -> String:
	var match_http := RegEx.create_from_string("HTTP [0-9]{3}").search(message)
	if match_http:return match_http.get_string().to_lower().replace(" ","_")
	if "Timed out" in message:return "search_timeout"
	if "Connection failed" in message:return "connection_failed"
	if "not HTTPS" in message or "non-HTTPS" in message:return "download_url_not_https"
	if "No downloadable" in message or "No download URL" in message:return "no_downloadable_asset"
	if "not found" in message:return "version_not_found"
	return fallback
func finish(reason: String) -> void:
	report.reason=reason
	var file := FileAccess.open(evidence_dir.path_join(provider_id+".result.json"),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("LIVE_RESULT ",provider_id," ","PASS" if report.passed else "UNCHECKED"," ",reason)
	browser.set_process(false);browser.serial+=1;browser.thumbnail_queue.clear();browser.client.cancel_all()
	var deadline := Time.get_ticks_msec()+2000
	while browser.thumbnails_active>0 and Time.get_ticks_msec()<deadline:await process_frame
	browser.queue_free();await process_frame
	quit(0 if report.passed else 1)
