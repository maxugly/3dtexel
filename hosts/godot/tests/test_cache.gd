extends SceneTree
const Client = preload("res://addons/3dtexel/client.gd")
const Thumbnail = preload("res://addons/3dtexel/core/thumbnail_image.gd")
const Registry = preload("res://addons/3dtexel/core/registry.gd")
class FakeClient:
	extends Client
	var calls := 0
	var files := 0
	func transport_json(_path: String,_method:=HTTPClient.METHOD_GET,_body:={})->Dictionary:
		calls+=1
		return {"id":99,"title":"Cached grass","type":"pbr","author":{"name":"Test Artist","api_key":"NEVER_STORE"},"license":{"name":"CC-BY 4.0","url":"https://example.test/license"},"price":{"free":true,"credits":0},"owned":true}
	func get_bytes(_url: String,_destination:="",_max_bytes:=67108864,_redirects_left:=5)->Dictionary:
		files+=1
		var image := Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.GREEN)
		return {"bytes":image.save_png_to_buffer()}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var client := FakeClient.new();root.add_child(client);client.cache.root="user://offline_cache_test_%s" % Time.get_ticks_usec()
	var missing: Dictionary=await client.json_request("/assets/99")
	check(missing.has("error") and client.calls==0,"Cache miss never contacts API without explicit refresh")
	client.network_allowed=true;client.refreshing=true
	await client.json_request("/assets/99")
	client.network_allowed=false;client.refreshing=false
	await client.json_request("/assets/99")
	check(client.calls==1,"Repeated API lookup served from disk")
	var other := FakeClient.new();root.add_child(other);other.cache.root=client.cache.root
	var restored: Dictionary=await other.json_request("/assets/99")
	check(restored.get("title")=="Cached grass" and other.calls==0,"Cache survives a new client/editor session")
	check(not restored.has("owned") and not restored.author.has("api_key"),"Public metadata sanitization")
	other.cache.put_response("/me",{"authorization":"NEVER_STORE"})
	other.cache.put_response("/assets/99/download",{"files":{"url":"https://example.test/?signature=secret"}})
	check(other.cache.get_response("/me").is_empty() and other.cache.get_response("/assets/99/download").is_empty(),"Account and signed-link responses never cached")
	client.cache.put_response("/assets/search?q=fixture",{"items":[],"total":0},{"etag":"fixture-v1"})
	check(client.cache.conditional_headers("/assets/search?q=fixture")==PackedStringArray(["If-None-Match: fixture-v1"]),"Provider queries can revalidate existing metadata without a repeated body")
	var thumb := "https://example.test/thumbnail.png"
	await client.thumbnail(thumb);check(client.files==0,"Uncached thumbnail stays offline")
	client.allowed_thumbnails[thumb]=true
	await client.thumbnail(thumb)
	await other.thumbnail(thumb)
	check(client.files==1 and other.files==0,"Thumbnail persists on disk")
	check(other.cache.search("grass","pbr",true,"CC-BY 4.0").size()==1,"Free non-CC0 asset filter")
	check(other.cache.search("grass","pbr",true,"CC0").is_empty(),"Exact local license filter")
	var cache_root := "user://offline_cache_size_test_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_root.path_join("nested")))
	var first := FileAccess.open(cache_root.path_join("metadata.json"),FileAccess.WRITE);first.store_buffer(PackedByteArray([1,2,3,4]));first.close()
	var second := FileAccess.open(cache_root.path_join("nested/thumbnail.png"),FileAccess.WRITE);second.store_buffer(PackedByteArray([5,6,7]));second.close()
	check(Registry.cache_path_size(cache_root)==7,"Cache size counts nested metadata and thumbnails")
	check(Registry.format_size(2048)=="2.0 KB","Cache size is human readable")
	Registry.clear_cache_path(cache_root)
	check(Registry.cache_path_size(cache_root)==0 and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cache_root)),"Clear cache removes nested files and directories")
	var holder := {"done":false}
	complete_disk_job(client,holder)
	client.cancel_all();client.cancel_all()
	var deadline := Time.get_ticks_msec()+1000
	while not holder.done and Time.get_ticks_msec()<deadline:await process_frame
	check(holder.done,"Cancelling an image decode joins its worker and resumes its caller")
	client.queue_free();other.queue_free();await process_frame
	print("Disk cache tests complete; failures=",failures)
	quit(1 if failures else 0)

func complete_disk_job(client: Node,holder: Dictionary) -> void:
	await Thumbnail.image_task(client,func():return Image.create(4,4,false,Image.FORMAT_RGBA8))
	holder.done=true
