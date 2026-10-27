extends SceneTree
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const IDS := ["artsmia", "artvee", "british_library_flickr", "david_rumsey", "freesound", "getty", "heritagetype", "lacma", "librivox", "mixkit", "mkg_hamburg", "morphosource", "nasa_visible_earth", "oldbookillustrations", "openverse", "pdimagearchive", "picryl", "public_work", "rawpixel", "scan_the_world", "sonniss", "tuckdb_postcards", "usda_watercolors", "usgs_astrogeology", "wellcome_collection", "yale_british_art"]
var failures := 0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	for id in IDS:await test_adapter(id)
	print("Provider functionality tests complete; adapters=",IDS.size(),"; failures=",failures)
	quit(1 if failures else 0)
func test_adapter(id: String) -> void:
	var path := "res://addons/3dtexel/providers/"+id+"/"
	var provider: Node=load(path+"provider.gd").new();root.add_child(provider)
	# Inherit the real client implementation, overriding every network entry.
	var original := FileAccess.get_file_as_string(path+"client.gd")
	var signature := RegEx.create_from_string("(?m)^func search[^\n]+").search(original).get_string()
	var mock_script := GDScript.new()
	mock_script.source_code=('extends "'+path+'client.gd"\nvar file_calls := 0\nvar search_calls := 0\nvar reply := {}\n'+signature+
		'\n\tsearch_calls+=1\n\treturn reply if network_allowed else {"error":"Offline gate"}\n'+
		'func get_bytes(_url: String,destination := "",_limit := 67108864,_redirects := 5) -> Dictionary:\n\tfile_calls+=1\n\tvar image := Image.create(8,8,false,Image.FORMAT_RGBA8)\n\timage.fill(Color.GREEN)\n\treturn {"bytes":image.save_png_to_buffer()}\n')
	check(mock_script.reload()==OK,id+": mock client compiles")
	var mock: Node=mock_script.new();provider.client.free();provider.client=mock;provider.add_child(mock)
	var cache: RefCounted=mock.cache
	cache.root="user://provider_functionality_"+id+"_"+str(Time.get_ticks_usec())
	cache.catalog_path=cache.root.path_join("catalog.json");cache.assets_path=cache.root.path_join("assets.json")
	var url := "https://images.example.invalid/"+id+".png"
	provider.network_allowed=false
	check(await provider.thumbnail(url)==null and mock.file_calls==0,id+": unrequested preview stays offline")
	mock.allowed_thumbnails[url]=true
	check(await provider.thumbnail(url)!=null,id+": authorized preview decodes after search ends")
	check(await provider.thumbnail(url)!=null and mock.file_calls==1,id+": preview cache avoids repeated transport")
	check(await provider.thumbnail(url+"?other")==null and mock.file_calls==1,id+": exact preview grant does not authorize other URLs")
	check((await provider.check_connection()).has("error") and mock.search_calls==0,id+": connection check requires explicit action")
	provider.network_allowed=true;mock.reply={"error":"Fixture failure"}
	check((await provider.check_connection()).get("error")=="Fixture failure" and mock.search_calls==1,id+": checks perform a bounded query and propagate site errors")
	var unknown := {"provider_id":id,"id":"unknown","type":"model" if id in ["morphosource","scan_the_world"] else "image"}
	check(provider.variants(unknown).is_empty(),id+": missing file metadata offers no fictional versions")
	check((await provider.resolve_download(unknown,"unreported")).has("error"),id+": unavailable versions are not substituted")
	cache.catalog={"nested":{"authorization":"SECRET","files":[{"url":"https://example.invalid/a?signature=SECRET","token":"SECRET"}],"authors":[{"name":"Fixture Artist"}]}}
	cache.save()
	var saved := FileAccess.get_file_as_string(cache.catalog_path)
	check(not saved.contains("SECRET") and saved.contains("Fixture Artist"),id+": persistence recursively strips secrets and keeps creator evidence")
	check(Registry.cache_path_size(cache.catalog_path)>0,id+": legacy cache files are measurable")
	provider.queue_free();await process_frame
	Registry.clear_cache_path(cache.root)
	check(not FileAccess.file_exists(cache.catalog_path),id+": cache files clear with previews")
