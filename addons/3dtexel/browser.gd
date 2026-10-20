@tool
extends Control
const Client = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Pagination = preload("res://addons/3dtexel/pagination.gd")
var content: VBoxContainer
var editor_plugin: EditorPlugin
var client: Node
var preparation: Node
var sites: OptionButton
var provider_settings: VBoxContainer
var policy_filter: OptionButton
var search: LineEdit
var kind: OptionButton
var resolution_boxes := {}
var resolution_row: HFlowContainer
var resolution_note: Label
var price_filter: OptionButton
var license_filter: OptionButton
var refresh: Button
var stop_refresh := false
var output: LineEdit
var inbox: LineEdit
var handoff: CheckBox
var status: Label
var account: Label
var body: SplitContainer
var results_scroll: ScrollContainer
var side: VBoxContainer
var grid: GridContainer
var detail: RichTextLabel
var preview: TextureRect
var download: Button
var previous: Button
var next: Button
var per_page: OptionButton
var page_label: Label
var selected := {}
var page := 1
var busy := false
var serial := 0
var pending_details := false
var tile_group := ButtonGroup.new()
var search_cache := {}
var thumbnail_queue: Array[Dictionary] = []
var thumbnails_active := 0
var thumbnail_tick := 0.0
func button(text: String, action: Callable, parent: Node) -> Button:
	var item := Button.new(); item.text = text; item.pressed.connect(action); parent.add_child(item)
	return item
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	content = VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	self.add_child(content)
	content.add_theme_constant_override("separation",10)
	client = Client.new(); content.add_child(client)
	preparation=Preparation.new();content.add_child(preparation);preparation.progress.connect(func(message):status.text=message)
	var title := Label.new(); title.text = "Asset Library · cached assets and credits"; title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; title.add_theme_font_size_override("font_size",24);content.add_child(title)
	var toolbar := HFlowContainer.new();content.add_child(toolbar)
	search = LineEdit.new();search.custom_minimum_size.x = 220;search.placeholder_text = "Search cached assets…";search.size_flags_horizontal = Control.SIZE_EXPAND_FILL;toolbar.add_child(search)
	search.text_submitted.connect(func(_text): start_search())
	sites=OptionButton.new();toolbar.add_child(sites);rebuild_sites();sites.item_selected.connect(func(index):client.scope=str(sites.get_item_metadata(index));start_search())
	kind = OptionButton.new();kind.add_item("All assets");kind.add_item("Materials");kind.add_item("Models");kind.add_item("Audio");kind.add_item("2D images");toolbar.add_child(kind);kind.item_selected.connect(func(_index):start_search())
	button("Search cache",start_search,toolbar)
	refresh=button("Refresh",refresh_search,toolbar)
	button("Check connection",check_connection,toolbar)
	button("Sites / keys",toggle_provider_settings,toolbar)
	account = Label.new();account.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;account.text="Keys are read from the environment or entered for this editor session only.";content.add_child(account)
	provider_settings=VBoxContainer.new();provider_settings.visible=false;content.add_child(provider_settings);build_provider_settings()
	var settings := HFlowContainer.new();content.add_child(settings)
	var label := Label.new();label.text = "Save to:";settings.add_child(label)
	output = LineEdit.new();output.custom_minimum_size.x = 180;output.text = str(ProjectSettings.get_setting("asset_browser/output_directory",ProjectSettings.get_setting("3dtexel/output_directory","res://AssetLibrary")));output.tooltip_text = "Native material and original maps; separate asset and actual-resolution folders.";output.size_flags_horizontal = Control.SIZE_EXPAND_FILL;settings.add_child(output)
	button("Open folder",func(): OS.shell_open(ProjectSettings.globalize_path(output.text)),settings)
	var filters := HFlowContainer.new();content.add_child(filters)
	price_filter=OptionButton.new();price_filter.add_item("Free only");price_filter.add_item("All prices · browse");filters.add_child(price_filter)
	license_filter=OptionButton.new();license_filter.add_item("Any license");license_filter.tooltip_text="License names reported by cached assets; free does not mean CC0.";filters.add_child(license_filter)
	price_filter.item_selected.connect(func(_index):start_search())
	license_filter.item_selected.connect(func(_index):start_search())
	policy_filter=OptionButton.new();policy_filter.add_item("All license statuses",-1)
	for i in Policy.LABELS.size():policy_filter.add_item(Policy.LABELS[i],i)
	filters.add_child(policy_filter);policy_filter.item_selected.connect(func(_index):start_search())
	button("Write saved-scene credits",write_scene_credits,filters)
	var auto_credits := CheckBox.new();auto_credits.text="Credits on scene save";auto_credits.button_pressed=bool(ProjectSettings.get_setting("asset_browser/automatic_scene_credits",ProjectSettings.get_setting("3dtexel/automatic_scene_credits",true)));filters.add_child(auto_credits)
	auto_credits.toggled.connect(func(value):ProjectSettings.set_setting("asset_browser/automatic_scene_credits",value);ProjectSettings.save())
	var terrain_row := HFlowContainer.new();content.add_child(terrain_row)
	handoff = CheckBox.new();handoff.text = "Also send to Terrain imports";handoff.button_pressed = false;terrain_row.add_child(handoff)
	inbox = LineEdit.new();inbox.custom_minimum_size.x = 180;inbox.text = str(ProjectSettings.get_setting("asset_browser/terrain_inbox",ProjectSettings.get_setting("3dtexel/terrain_inbox","res://assets/terrain/inbox")));inbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL;terrain_row.add_child(inbox)
	var hint := Label.new();hint.text = "Download resolution ≠ Terrain imports output resolution. Terrain handoff uses that plugin’s current packing size.";hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(hint)
	body = SplitContainer.new();body.size_flags_horizontal = Control.SIZE_EXPAND_FILL;body.size_flags_vertical = Control.SIZE_EXPAND_FILL;content.add_child(body)
	results_scroll = ScrollContainer.new();results_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL;results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL;results_scroll.custom_minimum_size = Vector2(175,160);results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(results_scroll)
	grid = GridContainer.new();grid.columns = 3;grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);results_scroll.add_child(grid)
	side = VBoxContainer.new();side.custom_minimum_size.x = 240;side.size_flags_horizontal = Control.SIZE_EXPAND_FILL;body.add_child(side)
	preview = TextureRect.new();preview.custom_minimum_size = Vector2(180,180);preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;side.add_child(preview)
	detail = RichTextLabel.new();detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size.y = 100;detail.size_flags_vertical = Control.SIZE_EXPAND_FILL;detail.text = "Search the library, then select an asset.\n\nOriginal source maps and provenance are preserved. Godot materials use mipmapped BC3 textures and anisotropic filtering.\n\nFree downloads only in this version; paid assets can be opened on the website.";side.add_child(detail)
	resolution_row=HFlowContainer.new();side.add_child(resolution_row)
	resolution_note=Label.new();resolution_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;side.add_child(resolution_note)
	update_resolution_choices({})
	button("Refresh selected metadata",refresh_selected_metadata,side)
	download = button("Download and prepare",download_selected,side);download.disabled = true
	button("Open selected on website",func():
		if not selected.is_empty(): OS.shell_open(str(selected.get("url",""))),side)
	var pages := HBoxContainer.new();content.add_child(pages)
	previous = button("← Previous",func(): page=maxi(1,page-1); run_search(),pages)
	var count_label := Label.new();count_label.text="Per page:";pages.add_child(count_label)
	per_page = OptionButton.new()
	var preferences := ConfigFile.new()
	if preferences.load("user://asset_browser.cfg")!=OK:preferences.load("user://3dtexel_browser.cfg")
	var saved_count := int(preferences.get_value("browser","per_page",12))
	for count in Pagination.PAGE_SIZES: per_page.add_item(str(count),count)
	per_page.select(maxi(0,per_page.get_item_index(saved_count)))
	per_page.tooltip_text="Large batches are assembled from multiple server pages. Thumbnails load as you scroll."
	pages.add_child(per_page)
	per_page.item_selected.connect(change_page_size)
	page_label = Label.new();page_label.clip_text = true;page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pages.add_child(page_label)
	next = button("Next →",func(): page+=1; run_search(),pages)
	previous.disabled=true;next.disabled=true
	status = Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.text="Search reads the local cache. Refresh checks the website; downloads are explicit.";content.add_child(status)
	resized.connect(update_layout)
	results_scroll.resized.connect(update_columns)
	client.seed(output.text)
	update_license_choices()
	call_deferred("update_layout")
func update_layout() -> void:
	if not is_instance_valid(body): return
	var stacked := size.x < 720
	body.vertical = stacked
	side.custom_minimum_size = Vector2(240,240 if stacked else 0)
	preview.custom_minimum_size.y = 90 if stacked else 180
	body.split_offset = roundi(body.size.y * 0.55) if stacked else maxi(175,roundi(size.x-clampf(size.x*.36,240,360)))
	update_columns()
func update_columns() -> void:
	if not is_instance_valid(results_scroll): return
	var maximum := size.x if body.vertical else maxf(175,size.x-side.custom_minimum_size.x-12)
	var available := minf(results_scroll.size.x,maximum)-results_scroll.get_v_scroll_bar().size.x
	grid.columns = clampi(floori((available+12.0)/177.0),1,8)
func start_search() -> void:
	if busy: return
	page = 1
	run_search()
func change_page_size(_index: int) -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("browser","per_page",per_page.get_selected_id())
	preferences.save("user://asset_browser.cfg")
	page=1
	run_search()
func update_license_choices() -> void:
	var chosen := license_filter.get_item_text(license_filter.selected) if license_filter.selected>=0 else "Any license"
	license_filter.clear();license_filter.add_item("Any license")
	for name in client.licenses():license_filter.add_item(name)
	for i in license_filter.item_count:
		if license_filter.get_item_text(i)==chosen:license_filter.select(i);break
func run_search() -> void:
	if busy:return
	serial+=1
	var count := per_page.get_selected_id()
	thumbnail_queue.clear()
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	results_scroll.scroll_vertical=0
	var type: String = ["all","material","model","audio","image"][kind.selected]
	var items: Array=client.search(search.text,type,price_filter.selected==0,license_filter.get_item_text(license_filter.selected))
	if policy_filter.selected>0:items=items.filter(func(asset):return int(asset.get("license_status",Policy.Status.UNKNOWN))==policy_filter.get_selected_id())
	var page_count := maxi(1,ceili(float(items.size())/count))
	page=clampi(page,1,page_count)
	var first := (page-1)*count
	var shown := items.slice(first,mini(items.size(),first+count))
	page_label.text="Page %s / %s · %s cached" % [page,page_count,items.size()]
	previous.disabled=page<=1;next.disabled=page>=page_count
	for asset: Dictionary in shown:grid.add_child(make_asset_tile(asset,serial))
	status.text="%s cached results on this page. Refresh checks for new or updated matches." % shown.size()
	if items.is_empty():status.text="No cached matches. Click Refresh to fetch this search, or change the local filters."
func refresh_search() -> void:
	if busy:
		if client.refreshing:stop_refresh=true;status.text="Stopping after the current request; cached data will be kept."
		return
	stop_refresh=false
	busy=true;refresh.text="Stop refresh";per_page.disabled=true
	client.network_allowed=true;client.refreshing=true
	var failure := ""
	var fetched := 0
	for id in client.active_ids():
		var provider: Node=client.providers[id]
		var cursor := ""
		var seen_cursors := {}
		for _batch in 100:
			if stop_refresh:failure="Stopped; cached data retained.";break
			status.text="Refreshing "+str(provider.descriptor().name)+"…"
			var data: Dictionary=await provider.refresh_page(search.text,["all","material","model","audio","image"][kind.selected],cursor)
			if data.has("error"):failure=str(data.error);break
			client.index_assets(data.get("items",[]));fetched+=data.get("items",[]).size()
			cursor=str(data.get("next_cursor",""))
			if cursor.is_empty():break
			if seen_cursors.has(cursor):failure="Provider repeated a page cursor; refresh stopped.";break
			seen_cursors[cursor]=true
		if not failure.is_empty():break
	client.network_allowed=false;client.refreshing=false
	busy=false;refresh.text="Refresh";refresh.disabled=false;per_page.disabled=false
	update_license_choices();page=1;run_search()
	status.text="Refresh cached %s records. " % fetched + ("Stopped: "+failure if not failure.is_empty() else "Search and paging are local; missing thumbnails from this refresh load as you scroll.")
func update_resolution_choices(asset: Dictionary) -> void:
	var previously_checked := []
	for value in resolution_boxes:
		if resolution_boxes[value].button_pressed:previously_checked.append(value)
	for child in resolution_row.get_children():resolution_row.remove_child(child);child.queue_free()
	resolution_boxes.clear()
	var provider: Node=client.provider_for(asset)
	var options: Array=provider.variants(asset) if provider else []
	var known := true
	for option: Dictionary in options:
		var value := str(option.id)
		var box := CheckBox.new();box.text=str(option.get("label",value));resolution_row.add_child(box);resolution_boxes[value]=box
		box.button_pressed=value in previously_checked if not previously_checked.is_empty() else value==("2k" if options.any(func(item):return item.id=="2k") else str(options[0].id))
		known=known and bool(option.get("confirmed",false))
	resolution_note.text="Reported available variants. Select one or more." if known else "Availability not reported. These are requests; the provider may substitute."
func write_scene_credits() -> void:
	if not Engine.is_editor_hint():status.text="Scene credits are available in the Godot editor.";return
	var root := EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path.is_empty():status.text="Save the scene first.";return
	var result := Credits.write_scene(root.scene_file_path)
	status.text=str(result.error) if result.has("error") else "Wrote %s · %s assets, %s resources missing credits. Uses saved dependencies; review dynamic assets separately." % [result.path,result.asset_count,result.missing_count]
func refresh_selected_metadata() -> void:
	if busy or selected.is_empty():return
	busy=true;client.network_allowed=true;client.refreshing=true
	status.text="Refreshing selected asset metadata…"
	var provider: Node=client.provider_for(selected)
	var data: Dictionary=await provider.refresh_asset(selected) if provider and provider.enabled else {"error":"Provider disabled."}
	if not data.has("error"):client.index_assets([data])
	client.network_allowed=false;client.refreshing=false;busy=false
	if data.has("error"):status.text="Metadata refresh failed: "+str(data.error);return
	select_asset(data,preview.texture)
	update_license_choices()
	status.text="Selected metadata cached. Author or resolution fields not supplied remain marked unknown."
func _process(delta: float) -> void:
	thumbnail_tick+=delta
	if thumbnail_tick<0.2:return
	thumbnail_tick=0.0
	pump_thumbnails()
func pump_thumbnails() -> void:
	if not is_visible_in_tree() or not is_instance_valid(results_scroll):return
	var visible_area := results_scroll.get_global_rect().grow(140)
	var i := 0
	while i<thumbnail_queue.size() and thumbnails_active<4:
		var job: Dictionary=thumbnail_queue[i]
		var image: TextureRect=job.image if is_instance_valid(job.image) else null
		if job.token!=serial or not image:
			thumbnail_queue.remove_at(i)
			continue
		if not image.is_inside_tree() or not image.get_global_rect().intersects(visible_area):
			i+=1
			continue
		thumbnail_queue.remove_at(i)
		thumbnails_active+=1
		load_queued_thumbnail(job)
func load_queued_thumbnail(job: Dictionary) -> void:
	await load_thumbnail(job.url,job.image,job.token,job.asset)
	thumbnails_active-=1
func make_asset_tile(asset: Dictionary, token: int) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(165,236)
	tile.toggle_mode = true
	tile.button_group = tile_group
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.tooltip_text = str(asset.get("title","Material"))
	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["margin_left","margin_right","margin_top","margin_bottom"]: padding.add_theme_constant_override(edge,8)
	tile.add_child(padding)
	var contents := VBoxContainer.new()
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_theme_constant_override("separation",8)
	padding.add_child(contents)
	var image := TextureRect.new()
	image.name = "Thumbnail"
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.custom_minimum_size = Vector2(145,130)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	contents.add_child(image)
	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = str(asset.get("title","Material"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 60
	contents.add_child(title)
	var license_label := Label.new()
	license_label.name = "License"
	license_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var license_name := str(Credits.license_record(asset.get("license","")).name)
	license_label.text = ("Free · " if Importer.free_asset(asset) else "Browse · ")+("CC0" if "cc0" in license_name.to_lower() else license_name)
	var assessment := Policy.evaluate(asset)
	license_label.text+="\n"+Policy.LABELS[int(assessment.status)]
	license_label.tooltip_text=license_name+"\n"+str(assessment.reason)
	license_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	license_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(license_label)
	contents.minimum_size_changed.connect(func(): tile.custom_minimum_size.y = maxf(236,contents.get_combined_minimum_size().y+16))
	tile.pressed.connect(func(): select_asset(asset,image.texture))
	var thumbnail_url := str(asset.get("thumbnail",""))
	if not thumbnail_url.is_empty():thumbnail_queue.append({"url":thumbnail_url,"image":image,"asset":asset,"token":token})
	return tile
func load_thumbnail(url: String, image: TextureRect, token: int, asset := {}) -> void:
	if url.is_empty(): return
	var texture: Texture2D = await client.thumbnail(url,asset)
	if is_instance_valid(image) and serial==token: image.texture=texture
func select_asset(asset: Dictionary, texture: Texture2D) -> void:
	if busy:return
	selected=asset.duplicate(true);preview.texture=texture;download.disabled=true
	var cached: Dictionary=client.cached_asset(asset)
	selected.merge(cached,true)
	var record := Credits.asset_record(selected)
	var names := []
	for person in record.authors:names.append(str(person.name))
	detail.text="%s\n\n%s\n\nAuthor: %s\nLicense: %s\nAsset ID: %s" % [selected.get("title",""),str(selected.get("description","")).strip_edges(),", ".join(names) if not names.is_empty() else "Not supplied · review source",record.license.name,selected.id]+"\nSite: "+str(selected.get("provider",selected.get("provider_id","")))+"\n"+str(Policy.evaluate(selected).reason)
	update_resolution_choices(selected)
	download.disabled=not client.can_download(selected)
	if not Importer.free_asset(selected):status.text="Paid assets are browse-only. Free and license are separate filters."
func check_connection() -> void:
	if busy:return
	busy=true;client.network_allowed=true
	var messages := []
	for id in client.active_ids():
		var provider: Node=client.providers[id]
		var result: Dictionary=await provider.check_connection()
		messages.append(str(provider.descriptor().name)+": "+str(result.get("error","Connected")))
	client.network_allowed=false;busy=false;account.text="; ".join(messages)
func download_selected() -> void:
	if busy or pending_details or selected.is_empty() or not client.can_download(selected):return
	if not output.text.begins_with("res://") or ".." in output.text:status.text="Choose an output directory inside res://.";return
	if handoff.button_pressed and (not inbox.text.begins_with("res://") or ".." in inbox.text):status.text="Choose an inbox inside res://.";return
	var requests := []
	for value in resolution_boxes:
		if resolution_boxes[value].button_pressed:requests.append(value)
	if requests.is_empty():status.text="Select at least one variant.";return
	busy=true;download.disabled=true;client.network_allowed=true
	var asset := selected.duplicate(true)
	var done := []
	for requested in requests:
		var result: Dictionary=await download_resolution(asset,requested)
		if result.has("error"):
			client.network_allowed=false;finish_error(str(result.error));return
		done.append(str(result.note))
	client.network_allowed=false;busy=false;download.disabled=false
	if Engine.is_editor_hint():EditorInterface.get_resource_filesystem().scan()
	status.text="Ready: "+"; ".join(done)
func download_resolution(asset: Dictionary, requested: String) -> Dictionary:
	preparation.registry=client;preparation.output_directory=output.text;preparation.send_to_terrain=handoff.button_pressed;preparation.terrain_inbox=inbox.text
	return await preparation.prepare(asset,requested)
func finish_error(message: String) -> void:
	status.text="Import stopped: "+message
	busy=false;download.disabled=false

func rebuild_sites() -> void:
	var scope: String=client.scope
	sites.clear();sites.add_item("All enabled sites");sites.set_item_metadata(0,"")
	for id in client.active_ids() if scope.is_empty() else client.providers.keys():
		if not client.providers[id].enabled:continue
		sites.add_item(str(client.providers[id].descriptor().name));sites.set_item_metadata(sites.item_count-1,id)
		if scope==id:sites.select(sites.item_count-1)
	client.scope=str(sites.get_item_metadata(sites.selected))
func toggle_provider_settings() -> void:provider_settings.visible=not provider_settings.visible
func build_provider_settings() -> void:
	for id in client.providers:
		var provider: Node=client.providers[id];var info: Dictionary=provider.descriptor()
		var row := HFlowContainer.new();provider_settings.add_child(row)
		var enabled := CheckBox.new();enabled.text=str(info.name);enabled.button_pressed=provider.enabled;row.add_child(enabled)
		enabled.toggled.connect(func(value):
			if busy:enabled.set_pressed_no_signal(provider.enabled);return
			client.set_enabled(str(info.id),value);rebuild_sites();update_license_choices();start_search())
		button("Website",func():OS.shell_open(str(info.website)),row)
		var state := Label.new();state.text=provider.credential_status();row.add_child(state)
		if not info.get("key_env",[]).is_empty():
			var key := LineEdit.new();key.secret=true;key.placeholder_text="Session API key (never saved)";key.custom_minimum_size.x=210;row.add_child(key)
			key.text_submitted.connect(func(value):provider.set_session_key(value);key.clear();state.text=provider.credential_status();download.disabled=selected.is_empty() or not client.can_download(selected))
			button("Use session key",func():provider.set_session_key(key.text);key.clear();state.text=provider.credential_status();download.disabled=selected.is_empty() or not client.can_download(selected),row)
