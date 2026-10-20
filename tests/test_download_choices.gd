extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Client = preload("res://addons/3dtexel/client.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
class ChoiceBrowser:
	extends Browser
	var requested: Array[String]=[]
	func download_resolution(_asset: Dictionary, size: String)->Dictionary:
		requested.append(size);return {"note":size}
class OfflineClient:
	extends Client
	var calls := 0
	func transport_json(_path: String,_method:=HTTPClient.METHOD_GET,_body:={})->Dictionary:
		calls+=1;return {"error":"Network forbidden in tests"}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var browser := ChoiceBrowser.new();root.add_child(browser);await process_frame
	var asset := {"provider_id":"texel","provider":"3DTexel","id":"77","title":"Local dirt","price":{"free":true,"credits":0},"resolutions":["2k","4k"],"author":"Local Artist","license":"CC0"}
	browser.client.providers.texel.set_session_key("offline-fixture");browser.selected=asset;browser.update_resolution_choices(asset)
	check(browser.resolution_boxes.size()==2 and browser.resolution_boxes.has("4k") and not browser.resolution_boxes.has("1k"),"Only reported available resolutions shown")
	for box in browser.resolution_boxes.values():box.button_pressed=true
	await browser.download_selected()
	check(browser.requested==["2k","4k"],"Every checked resolution handled once")
	browser.queue_free();await process_frame
	var real_browser := Browser.new();root.add_child(real_browser);await process_frame
	var adapter: Node=real_browser.client.providers.texel
	adapter.client.free();var offline := OfflineClient.new();adapter.add_child(offline);adapter.client=offline
	real_browser.output.text="res://3DTexel/reuse_test_%s" % Time.get_ticks_usec()
	var folder := real_browser.output.text.path_join("%s_77" % Importer.slug(asset.title)).path_join("2k")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	ResourceSaver.save(StandardMaterial3D.new(),folder.path_join("material.res"))
	Importer.write_json(folder.path_join("provenance.json"),{"title":asset.title,"asset_id":77,"maps":{},"returned_resolution":"2k","license":"CC0"})
	var reused: Dictionary=await real_browser.download_resolution(asset,"2k")
	check(not reused.has("error") and offline.calls==0,"Existing download reused without API call")
	check(FileAccess.file_exists(folder.path_join("material.res.credits.json")),"Existing local material receives credits")
	real_browser.queue_free();await process_frame
	print("Resolution and local-reuse tests complete; failures=",failures)
	quit(1 if failures else 0)
