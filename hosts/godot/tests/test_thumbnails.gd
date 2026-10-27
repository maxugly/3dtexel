extends SceneTree
const Browser = preload("res://addons/3dtexel/browser.gd")
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Transport = preload("res://addons/3dtexel/core/request_transport.gd")
class FakeClient:
	extends Registry
	var started := 0
	var active := 0
	var peak := 0
	func thumbnail(url: String,_asset: Dictionary) -> Texture2D:
		started+=1;active+=1;peak=maxi(peak,active)
		await get_tree().create_timer(.05).timeout
		active-=1
		return null if url.ends_with("broken") else GradientTexture1D.new()
class GatedClient:
	extends Node
	var allowed_thumbnails := {}
	var network_allowed := false
	func thumbnail(url: String) -> Texture2D:
		if not network_allowed and not allowed_thumbnails.has(url):return null
		return GradientTexture1D.new()
class FakeProvider:
	extends Node
	var enabled := true
	var network_allowed := false
	var client: GatedClient
	func descriptor() -> Dictionary:return {"id":"fake_registry"}
	func thumbnail(url: String) -> Texture2D:return client.thumbnail(url)
	func cancel_all() -> void:pass
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1200,900)
	var browser := Browser.new();root.add_child(browser);await process_frame
	browser.set_process(false);browser.client.queue_free()
	var fake := FakeClient.new();browser.add_child(fake);browser.client=fake;browser.selection.registry=fake;browser.session.registry=fake
	var assets := []
	for i in 8:
		assets.append({"id":i,"title":"Test","url":"https://www.example.invalid/assets/item?q=x","thumbnail":"https://example.invalid/"+("broken" if i==7 else str(i)),"price":{"free":true,"credits":0}})
		browser.grid.add_child(browser.make_asset_tile(assets[-1],browser.serial))
	check(browser.grid.get_children().all(func(card):return not card.visible),"No cards appear before their images")
	check(browser.domain_name(assets[0])=="example.invalid","Domain label excludes www, path and query")
	browser.pump_thumbnails()
	check(fake.started==4 and fake.peak==4,"At most four thumbnail requests start together")
	# Rebuild while the original four jobs are running, as streamed batches do.
	for card in browser.grid.get_children():browser.grid.remove_child(card);card.queue_free()
	browser.serial+=1;browser.thumbnail_queue.clear()
	for asset in assets:browser.grid.add_child(browser.make_asset_tile(asset,browser.serial))
	for i in 12:
		await create_timer(.025).timeout
		browser.pump_thumbnails()
	check(fake.started==8 and fake.peak==4,"Grid rebuild reuses in-flight images without duplicate requests")
	check(browser.grid.get_children().filter(func(card):return card.visible).size()==7,"Only successfully loaded images reveal cards")
	check(browser.thumbnails_active==0 and browser.thumbnail_pending.is_empty(),"Failed images release queue capacity")
	var card := browser.grid.get_child(0)
	var before: Vector2=card.get_combined_minimum_size()
	browser.show_domains.set_pressed_no_signal(true)
	var overlay := card.find_child("Domain",true,false);overlay.show()
	check(overlay.text=="example.invalid" and overlay.get_parent().name=="Thumbnail","Small domain label is over the image")
	check(card.get_combined_minimum_size()==before,"Domain overlay does not enlarge cards")
	var calls := fake.started
	var cached := browser.make_asset_tile(assets[0],browser.serial);browser.grid.add_child(cached)
	check(cached.visible,"A cached image displays immediately on redraw")
	browser.pump_thumbnails();check(fake.started==calls,"Cached images do not refetch")
	browser.thumbnail_queue.append({"key":"stale","token":browser.serial-1})
	browser.pump_thumbnails();check(browser.thumbnail_queue.is_empty(),"Stale queued jobs are discarded")
	await test_thumbnail_allow_list()
	var allowed := {"https://example.invalid/old.png":true}
	var redirected := Transport.thumbnail_redirect(allowed,"https://example.invalid/old.png","/images/new.png")
	check(redirected=="https://example.invalid/images/new.png" and allowed.has(redirected),"An authorized image can follow a relative redirect after search ends")
	check(Transport.thumbnail_redirect(allowed,redirected,"http://example.invalid/unsafe").is_empty(),"Redirects cannot downgrade image transport to HTTP")
	Transport.thumbnail_redirect(allowed,"https://unrequested.invalid/old.png","https://unrequested.invalid/new.png")
	check(not allowed.has("https://unrequested.invalid/new.png"),"Redirect helpers grant no permission to unrequested images")
	await test_transport_cancellation()
	browser.queue_free();await process_frame
	print("Thumbnail queue tests complete; failures=",failures)
	quit(1 if failures else 0)
func test_thumbnail_allow_list() -> void:
	var registry := Registry.new();root.add_child(registry);await process_frame
	var provider := FakeProvider.new();provider.client=GatedClient.new();registry.register_provider(provider)
	var url := "https://example.invalid/thumbnail.png"
	var texture: Texture2D=await registry.thumbnail(url,{"provider_id":"fake_registry"})
	check(texture!=null,"Finished searches still authorize their exact thumbnail URLs")
	check(provider.client.allowed_thumbnails.has(url),"Exact URL is recorded in the allow list")
	check(await provider.thumbnail("https://example.invalid/other.png")==null,"Unrequested URLs stay blocked")
	provider.client.queue_free();registry.queue_free();await process_frame
func await_cancel(request: HTTPRequest,active: Array[HTTPRequest],holder: Dictionary) -> void:
	var result: Array=await request.request_completed
	active.erase(request);request.queue_free()
	holder.completed+=1;holder.failed=holder.failed and result[0]!=HTTPRequest.RESULT_SUCCESS
func test_transport_cancellation() -> void:
	var active: Array[HTTPRequest]=[];var holder := {"completed":0,"failed":true}
	for i in 4:
		var request := Transport.create_request();root.add_child(request);active.append(request)
		check(request.use_threads,"All provider HTTP runs in threads")
		# No network is started: these synthetic awaiters exercise cancellation.
		await_cancel(request,active,holder)
	Transport.cancel_all(active);Transport.cancel_all(active)
	check(holder.completed==4 and holder.failed and active.is_empty(),"Cancellation resumes every waiter exactly once despite active-list mutation")
	await process_frame
