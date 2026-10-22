extends Control
## Manual UI audit: hosts the real browser panel, runs a real search, then audits
## the rendered control tree (rects, zero-size nodes, overlaps, clipped text,
## missing thumbnails) and prints it. No images needed to judge layout.
## Usage: godot --path hosts/godot res://tools/ui_audit.tscn

const Browser = preload("res://addons/3dtexel/browser.gd")

var browser: Control
var problems: Array[String] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser = Browser.new()
	add_child(browser)
	await get_tree().process_frame
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var query := OS.get_environment("TEXEL_UI_QUERY")
	if query.is_empty():query = "wood"
	var only := OS.get_environment("TEXEL_UI_ONLY")
	if not only.is_empty():
		for id in browser.client.providers:browser.client.providers[id].enabled = false
		for id in only.split(",", false):browser.client.providers[id].enabled = true
	browser.search.text = query
	await get_tree().process_frame
	browser.start_search()
	var deadline := Time.get_ticks_msec() + 90000
	while browser.busy and Time.get_ticks_msec() < deadline:await get_tree().process_frame
	await get_tree().process_frame
	audit()
	await diagnose_thumbnails()
	get_tree().quit(0)

func audit() -> void:
	var viewport := get_viewport_rect().size
	print("[audit] viewport=", viewport, " status=\"", browser.status.text, "\"")
	print("[audit] page=", browser.page_label.text, " cards=", browser.grid.get_child_count())
	var card_rects: Array = []
	var with_texture := 0
	var missing_title := 0
	for card in browser.grid.get_children():
		var rect: Rect2 = card.get_global_rect()
		card_rects.append(rect)
		if rect.size.x < 10 or rect.size.y < 10:problems.append("card has no size: %s" % rect)
		var title: Node = card.find_child("Title", true, false)
		if title == null or str(title.text).strip_edges().is_empty():missing_title += 1
		var image: Node = card.find_child("Thumbnail", true, false)
		if image != null and image.texture != null:with_texture += 1
	print("[audit] cards=%s with_thumbnail=%s missing_title=%s" % [card_rects.size(), with_texture, missing_title])
	if missing_title > 0:problems.append("%s cards have no title" % missing_title)

	# overlapping cards
	var overlaps := 0
	for i in card_rects.size():
		for j in range(i + 1, card_rects.size()):
			if card_rects[i].intersects(card_rects[j]):overlaps += 1
	print("[audit] overlapping_card_pairs=", overlaps)
	if overlaps > 0:problems.append("%s card pairs overlap" % overlaps)

	# key controls
	for name in ["search", "search_button", "sites", "kind", "grid", "results_scroll", "status", "page_label"]:
		var node: Control = browser.get(name)
		if node == null:
			problems.append("missing control: %s" % name)
			continue
		var rect: Rect2 = node.get_global_rect()
		print("[audit] %-14s type=%-22s rect=%s visible=%s" % [name, node.get_class(), rect, node.is_visible_in_tree()])
		if not node.is_visible_in_tree():problems.append("control not visible: %s" % name)
		if rect.size.x <= 0 or rect.size.y <= 0:problems.append("control has no size: %s" % name)
		if rect.position.x < -1 or rect.position.y < -1:problems.append("control off-screen (top-left): %s %s" % [name, rect.position])
		if rect.position.x + rect.size.x > viewport.x + 1:problems.append("control overflows right edge: %s (%s > %s)" % [name, rect.position.x + rect.size.x, viewport.x])
		if rect.position.y + rect.size.y > viewport.y + 1:problems.append("control overflows bottom edge: %s (%s > %s)" % [name, rect.position.y + rect.size.y, viewport.y])

	# status text must be readable and not empty
	if str(browser.status.text).strip_edges().is_empty():problems.append("status label is empty")
	# toolbar buttons must be usable
	if browser.search_button.disabled:problems.append("search button disabled after search finished")
	if not browser.search.editable:problems.append("search field not editable after search finished")
	# grid must sit inside the scroll area horizontally and start below its top edge
	var grid_rect: Rect2 = browser.grid.get_global_rect()
	var scroll_rect: Rect2 = browser.results_scroll.get_global_rect()
	if grid_rect.position.x < scroll_rect.position.x - 1 or grid_rect.position.x + grid_rect.size.x > scroll_rect.position.x + scroll_rect.size.x + 1:
		problems.append("grid %s escapes scroll area width %s" % [grid_rect, scroll_rect])
	if grid_rect.position.y < scroll_rect.position.y - 1:
		problems.append("grid %s starts above scroll area %s" % [grid_rect, scroll_rect])

	print("[audit] problems=%s" % problems.size())
	for problem in problems:print("[audit] PROBLEM: ", problem)

func diagnose_thumbnails() -> void:
	print("[audit] is_processing=%s process_mode=%s tick=%s" % [browser.is_processing(), browser.process_mode, browser.thumbnail_tick])
	await get_tree().create_timer(0.5).timeout
	print("[audit] tick after 0.5s=%s (0 means _process never ran)" % browser.thumbnail_tick)
	print("[audit] thumb queue=%s active=%s serial=%s browser_visible=%s busy=%s" % [browser.thumbnail_queue.size(), browser.thumbnails_active, browser.serial, browser.is_visible_in_tree(), browser.busy])
	if browser.thumbnail_queue.size() > 0:
		var job: Dictionary = browser.thumbnail_queue[0]
		var image: Node = job.get("image")
		print("[audit] job token=%s serial=%s valid=%s in_tree=%s rect=%s" % [job.get("token"), browser.serial, is_instance_valid(image), (image.is_inside_tree() if is_instance_valid(image) else false), (image.get_global_rect() if is_instance_valid(image) else Rect2())])
		print("[audit] scroll rect=%s visible_area=%s" % [browser.results_scroll.get_global_rect(), browser.results_scroll.get_global_rect().grow(140)])
	browser.pump_thumbnails()
	print("[audit] after manual pump queue=%s active=%s" % [browser.thumbnail_queue.size(), browser.thumbnails_active])
	await get_tree().create_timer(3.0).timeout
	var textured := 0
	for card in browser.grid.get_children():
		var image: Node = card.find_child("Thumbnail", true, false)
		if image != null and image.texture != null:textured += 1
	print("[audit] cards_with_texture_after_pump=%s" % textured)
	var shown := 0
	for asset: Dictionary in browser.visible_assets:
		if shown >= 3:break
		shown += 1
		var url := str(asset.get("thumbnail",""))
		var provider_id := str(asset.get("provider_id",""))
		print("[audit] thumb sample provider=%s url=%s" % [provider_id, url])
		if url.is_empty():continue
		var provider: Node = browser.client.providers.get(provider_id)
		if provider == null:
			print("[audit]   no provider node for ", provider_id)
			continue
		var provider_client: Variant = provider.get("client")
		var allowed := false
		if provider_client != null and "allowed_thumbnails" in provider_client:
			allowed = provider_client.allowed_thumbnails.has(url)
		print("[audit]   allow-listed=%s network_allowed=%s" % [allowed, browser.client.network_allowed])
		# a cache-busting variant guarantees the network gate is exercised
		var probe_url := url + (("&" if url.contains("?") else "?") + "texel_probe=audit")
		var gated: Texture2D = await provider.thumbnail(probe_url)
		var texture: Texture2D = await browser.client.thumbnail(probe_url,asset)
		print("[audit]   A/B gated(no allow-list)=%s  allow-listed=%s" % ["null" if gated == null else "%dx%d" % [gated.get_width(), gated.get_height()], "null" if texture == null else "%dx%d" % [texture.get_width(), texture.get_height()]])

func find_control(root: Node,name: String) -> Control:
	if root.name == name and root is Control:return root
	for child in root.get_children():
		var found := find_control(child,name)
		if found != null:return found
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:get_tree().quit(0)
