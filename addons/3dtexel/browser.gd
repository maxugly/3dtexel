@tool
extends Control
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Preparation = preload("res://addons/3dtexel/core/preparation.gd")
const Session = preload("res://addons/3dtexel/core/search_session.gd")
const Selection = preload("res://addons/3dtexel/core/download_selection.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")
const Credits = preload("res://addons/3dtexel/credits.gd")
const Pagination = preload("res://addons/3dtexel/pagination.gd")
var editor_plugin: EditorPlugin
var content: VBoxContainer
var client: Node
var preparation: Node
var session := Session.new()
var selection := Selection.new()
var search: LineEdit
var sites: OptionButton
var kind: OptionButton
var search_button: Button
var price_filter: OptionButton
var license_filter: OptionButton
var policy_filter: OptionButton
var version_filter: OptionButton
var check_all: CheckBox
var download: Button
var stop_button: Button
var delay: SpinBox
var settings_panel: VBoxContainer
var output: LineEdit
var handoff: CheckBox
var inbox: LineEdit
var account: Label
var results_scroll: ScrollContainer
var grid: GridContainer
var previous: Button
var next: Button
var per_page: OptionButton
var page_label: Label
var status: Label
var progress: ProgressBar
var selected := {}
var visible_assets: Array=[]
var page := 1
var busy := false
var stopping := false
var serial := 0
var thumbnail_queue: Array[Dictionary]=[]
var thumbnails_active := 0
var thumbnail_tick := 0.0
func button(text: String,action: Callable,parent: Node) -> Button:
	var item := Button.new();item.text=text;item.pressed.connect(action);parent.add_child(item);return item
func label(text: String,parent: Node) -> Label:
	var item := Label.new();item.text=text;parent.add_child(item);return item
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL;size_flags_vertical=Control.SIZE_EXPAND_FILL
	content=VBoxContainer.new();content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.add_theme_constant_override("separation",8);add_child(content)
	client=Registry.new();add_child(client);session.registry=client;selection.registry=client
	preparation=Preparation.new();add_child(preparation);preparation.registry=client
	preparation.progress.connect(func(message):status.text=message)
	label("Asset Library",content).add_theme_font_size_override("font_size",24)
	var toolbar := HFlowContainer.new();content.add_child(toolbar)
	search=LineEdit.new();search.placeholder_text="Search assets…";search.custom_minimum_size.x=200;search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(search)
	search.text_submitted.connect(func(_text):start_search())
	sites=OptionButton.new();toolbar.add_child(sites);rebuild_sites();sites.item_selected.connect(func(index):client.scope=str(sites.get_item_metadata(index));start_search())
	kind=OptionButton.new()
	for name in ["All assets","Materials","Models","Audio","2D images"]:kind.add_item(name)
	toolbar.add_child(kind);kind.item_selected.connect(func(_index):start_search())
	search_button=button("Search",start_search,toolbar)
	button("Settings",func():settings_panel.visible=not settings_panel.visible,toolbar)
	var filters := HFlowContainer.new();content.add_child(filters)
	price_filter=OptionButton.new();price_filter.add_item("Free only");price_filter.add_item("All prices");filters.add_child(price_filter)
	license_filter=OptionButton.new();license_filter.add_item("Any license");filters.add_child(license_filter)
	policy_filter=OptionButton.new();policy_filter.add_item("All license statuses",-1)
	for i in Policy.LABELS.size():policy_filter.add_item(Policy.LABELS[i],i)
	filters.add_child(policy_filter)
	version_filter=OptionButton.new();version_filter.add_item("All versions");version_filter.set_item_metadata(0,"");filters.add_child(version_filter)
	for control in [price_filter,license_filter,policy_filter]:control.item_selected.connect(func(_index):page=1;run_search())
	version_filter.item_selected.connect(func(index):selection.filter_key=str(version_filter.get_item_metadata(index));selection.checked.clear();page=1;run_search())
	var actions := HFlowContainer.new();content.add_child(actions)
	check_all=CheckBox.new();check_all.text="Check all";check_all.tooltip_text="Select or unselect the cards on this page.";actions.add_child(check_all);check_all.toggled.connect(toggle_all)
	download=button("Download selected",download_selected,actions);download.disabled=true
	label("Pause between downloads:",actions)
	delay=SpinBox.new();delay.min_value=0;delay.max_value=300;delay.step=1;delay.value=5;delay.suffix="s";actions.add_child(delay)
	stop_button=button("Stop",func():stopping=true;status.text="Stopping after the current operation…",actions);stop_button.disabled=true
	settings_panel=VBoxContainer.new();settings_panel.visible=false;content.add_child(settings_panel);build_settings()
	results_scroll=ScrollContainer.new();results_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;results_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;results_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;content.add_child(results_scroll)
	grid=GridContainer.new();grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);results_scroll.add_child(grid)
	var pages := HBoxContainer.new();content.add_child(pages)
	previous=button("← Previous",func():page=maxi(1,page-1);run_search(),pages)
	label("Per page:",pages);per_page=OptionButton.new()
	var preferences := ConfigFile.new()
	if preferences.load("user://asset_browser.cfg")!=OK:preferences.load("user://3dtexel_browser.cfg")
	for count in Pagination.PAGE_SIZES:per_page.add_item(str(count),count)
	per_page.select(maxi(0,per_page.get_item_index(int(preferences.get_value("browser","per_page",12)))));pages.add_child(per_page)
	per_page.item_selected.connect(change_page_size)
	page_label=label("",pages);page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;page_label.clip_text=true
	next=button("Next →",next_page,pages)
	progress=ProgressBar.new();progress.custom_minimum_size.y=6;progress.show_percentage=false;content.add_child(progress)
	status=label("Search for assets to begin.",content);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	client.seed(output.text)
	update_filter_choices();update_actions()
	resized.connect(update_layout);results_scroll.resized.connect(update_layout);call_deferred("update_layout")
func build_settings() -> void:
	var row := HFlowContainer.new();settings_panel.add_child(row)
	label("Save to:",row);output=LineEdit.new();output.text=str(ProjectSettings.get_setting("asset_browser/output_directory",ProjectSettings.get_setting("3dtexel/output_directory","res://AssetLibrary")));output.custom_minimum_size.x=230;row.add_child(output)
	button("Open folder",func():OS.shell_open(ProjectSettings.globalize_path(output.text)),row)
	var terrain := HFlowContainer.new();settings_panel.add_child(terrain)
	handoff=CheckBox.new();handoff.text="Also send materials to Terrain imports";terrain.add_child(handoff)
	inbox=LineEdit.new();inbox.text=str(ProjectSettings.get_setting("asset_browser/terrain_inbox",ProjectSettings.get_setting("3dtexel/terrain_inbox","res://assets/terrain/inbox")));inbox.custom_minimum_size.x=230;terrain.add_child(inbox)
	var credits := HFlowContainer.new();settings_panel.add_child(credits)
	var auto := CheckBox.new();auto.text="Credits on scene save";auto.button_pressed=bool(ProjectSettings.get_setting("asset_browser/automatic_scene_credits",ProjectSettings.get_setting("3dtexel/automatic_scene_credits",true)));credits.add_child(auto)
	auto.toggled.connect(func(value):ProjectSettings.set_setting("asset_browser/automatic_scene_credits",value);ProjectSettings.save())
	button("Write scene credits",write_scene_credits,credits);button("Check connections",check_connection,credits)
	account=label("API keys can come from the environment or be entered for this editor session.",settings_panel);account.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for id in client.providers:
		var provider: Node=client.providers[id];var info: Dictionary=provider.descriptor()
		var site := HFlowContainer.new();settings_panel.add_child(site)
		var enabled := CheckBox.new();enabled.text=str(info.name);enabled.button_pressed=provider.enabled;site.add_child(enabled)
		enabled.toggled.connect(func(value):
			if busy:enabled.set_pressed_no_signal(provider.enabled);return
			client.set_enabled(str(info.id),value);rebuild_sites();start_search())
		button("Website",func():OS.shell_open(str(info.website)),site)
		var state := label(provider.credential_status(),site)
		if not info.get("key_env",[]).is_empty():
			var key := LineEdit.new();key.secret=true;key.placeholder_text="Session API key";key.custom_minimum_size.x=180;site.add_child(key)
			var apply := func():provider.set_session_key(key.text);key.clear();state.text=provider.credential_status();run_search()
			key.text_submitted.connect(func(_value):apply.call());button("Use key",apply,site)
func update_layout() -> void:
	if not is_instance_valid(results_scroll):return
	var available := results_scroll.size.x-results_scroll.get_v_scroll_bar().size.x
	grid.columns=clampi(floori((available+12.0)/222.0),1,8)
func rebuild_sites() -> void:
	var scope: String=client.scope
	sites.clear();sites.add_item("All enabled sites");sites.set_item_metadata(0,"")
	for id in client.providers:
		if not client.providers[id].enabled:continue
		sites.add_item(str(client.providers[id].descriptor().name));sites.set_item_metadata(sites.item_count-1,id)
		if scope==id:sites.select(sites.item_count-1)
	client.scope=str(sites.get_item_metadata(sites.selected))
func start_search() -> void:
	if busy:return
	await refresh_search()
func refresh_search() -> void:
	if busy:return
	busy=true;stopping=false;page=1;selection.checked.clear();session.begin(search.text,["all","material","model","audio","image"][kind.selected])
	client.network_allowed=true;client.refreshing=true;update_actions();status.text="Searching…"
	var errors := []
	for _round in 100:
		if stopping:break
		var result: Dictionary=await session.fetch_round()
		if result.has("error"):errors.append(str(result.error));break
		errors.append_array(result.get("errors",[]))
		if session.items().size()>=per_page.get_selected_id() or not session.has_more():break
		status.text="Searching · %s results…" % session.items().size()
	client.network_allowed=false;client.refreshing=false;busy=false
	update_filter_choices();run_search();update_actions()
	status.text="Search stopped." if stopping else ("; ".join(errors) if not errors.is_empty() else "%s results loaded." % session.items().size())
func filtered_items() -> Array:
	var result := []
	var license_name := license_filter.get_item_text(license_filter.selected)
	for asset: Dictionary in session.items():
		if str(asset.get("provider_id","")) not in client.active_ids():continue
		if price_filter.selected==0 and not asset.get("price",{}).get("free",false):continue
		if license_name!="Any license" and Credits.license_record(asset.get("license","")).name!=license_name:continue
		if policy_filter.selected>0 and int(Policy.evaluate(asset).status)!=policy_filter.get_selected_id():continue
		if not selection.filter_key.is_empty() and selection.options(asset).is_empty():continue
		result.append(asset)
	return result
func run_search() -> void:
	if busy:return
	serial+=1;thumbnail_queue.clear()
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	results_scroll.scroll_vertical=0
	var items := filtered_items();var count := per_page.get_selected_id();var pages := maxi(1,ceili(float(items.size())/count))
	page=clampi(page,1,pages);visible_assets=items.slice((page-1)*count,mini(items.size(),page*count))
	for asset: Dictionary in visible_assets:grid.add_child(make_asset_tile(asset,serial))
	page_label.text="Page %s · %s results%s" % [page,items.size()," · more available" if session.has_more() else ""]
	previous.disabled=page<=1;next.disabled=page>=pages and not session.has_more()
	status.text="%s assets on this page." % visible_assets.size() if not items.is_empty() else "No matching results."
	update_actions()
func update_filter_choices() -> void:
	var selected_license := license_filter.get_item_text(license_filter.selected) if license_filter.selected>=0 else "Any license"
	license_filter.clear();license_filter.add_item("Any license")
	var licenses := [];var options := {}
	for asset: Dictionary in session.items():
		var name := str(Credits.license_record(asset.get("license","")).name)
		if name not in licenses:licenses.append(name)
		for option: Dictionary in selection.options(asset,false):
			var key := Selection.option_key(asset,option)
			var default_label := str(option.get("label",option.id))
			if asset.get("type")=="material":default_label="Resolution: "+default_label
			elif asset.get("type")=="model":default_label="Model: "+default_label
			options[key]=str(option.get("filter_label",default_label))
	licenses.sort()
	for name in licenses:
		license_filter.add_item(name)
		if name==selected_license:license_filter.select(license_filter.item_count-1)
	version_filter.clear();version_filter.add_item("All versions");version_filter.set_item_metadata(0,"")
	for key in options:
		version_filter.add_item(str(options[key]));version_filter.set_item_metadata(version_filter.item_count-1,key)
		if key==selection.filter_key:version_filter.select(version_filter.item_count-1)
	if version_filter.selected==0:selection.filter_key=""
func change_page_size(_index: int) -> void:
	var prefs := ConfigFile.new();prefs.set_value("browser","per_page",per_page.get_selected_id());prefs.save("user://asset_browser.cfg")
	page=1
	if session.items().size()<per_page.get_selected_id() and session.has_more():await load_more(per_page.get_selected_id()-1)
	run_search()
func load_more(wanted: int) -> void:
	busy=true;stopping=false;client.network_allowed=true;client.refreshing=true;update_actions();status.text="Loading more results…"
	var budget := session.items().size()+per_page.get_selected_id()
	for _round in 100:
		var result: Dictionary=await session.fetch_round()
		if result.has("error") or not result.get("errors",[]).is_empty():break
		if stopping or not session.has_more() or filtered_items().size()>wanted or session.items().size()>=budget:break
	client.network_allowed=false;client.refreshing=false;busy=false;update_filter_choices()
func next_page() -> void:
	if busy:return
	var wanted := page*per_page.get_selected_id()
	if filtered_items().size()<=wanted and session.has_more():
		await load_more(wanted)
	page+=1;run_search()
func update_actions() -> void:
	if not is_instance_valid(download):return
	var jobs := selection.jobs(filtered_items()) if is_instance_valid(license_filter) else []
	download.text="Download selected (%s)" % jobs.size();download.disabled=busy or jobs.is_empty()
	stop_button.disabled=not busy;search_button.disabled=busy;delay.editable=not busy;search.editable=not busy
	for control in [sites,kind,price_filter,license_filter,policy_filter,version_filter,per_page]:control.disabled=busy
	var eligible := visible_assets.filter(func(asset):return not selection.options(asset).is_empty() and client.can_download(asset))
	check_all.disabled=busy or eligible.is_empty()
	check_all.set_pressed_no_signal(not eligible.is_empty() and eligible.all(func(asset):return selection.is_checked(asset)))
func toggle_all(value: bool) -> void:
	if busy:return
	for asset: Dictionary in visible_assets:
		if not selection.options(asset).is_empty() and client.can_download(asset):selection.set_checked(asset,value)
	run_search()
func make_asset_tile(asset: Dictionary,token: int) -> PanelContainer:
	selection.ensure_default(asset)
	var card := PanelContainer.new();card.custom_minimum_size=Vector2(210,280);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.tooltip_text=str(asset.get("title","Asset"))
	var contents := VBoxContainer.new();contents.name="Contents";contents.add_theme_constant_override("separation",6);card.add_child(contents)
	var header := HBoxContainer.new();header.name="Header";contents.add_child(header)
	var check := CheckBox.new();check.name="Select";check.button_pressed=selection.is_checked(asset);check.disabled=busy or selection.options(asset).is_empty() or not client.can_download(asset);header.add_child(check)
	check.toggled.connect(func(value):selection.set_checked(asset,value);update_actions())
	var imported: Dictionary=client.inventory.versions(asset)
	var badge := label("✓ Downloaded" if not imported.is_empty() else "",header);badge.name="Imported";badge.tooltip_text=" · ".join(imported.keys())
	var main := Button.new();main.name="Inspect";main.flat=true;main.size_flags_horizontal=Control.SIZE_EXPAND_FILL;main.custom_minimum_size=Vector2(210,210);main.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;contents.add_child(main)
	var padding := MarginContainer.new();padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);padding.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for edge in ["margin_left","margin_right","margin_top","margin_bottom"]:padding.add_theme_constant_override(edge,8)
	main.add_child(padding)
	var info := VBoxContainer.new();info.mouse_filter=Control.MOUSE_FILTER_IGNORE;padding.add_child(info)
	var image := TextureRect.new();image.name="Thumbnail";image.mouse_filter=Control.MOUSE_FILTER_IGNORE;image.custom_minimum_size=Vector2(190,125);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;info.add_child(image)
	var title := label(str(asset.get("title","Asset")),info);title.name="Title";title.mouse_filter=Control.MOUSE_FILTER_IGNORE;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.custom_minimum_size=Vector2(190,44)
	var license_name := str(Credits.license_record(asset.get("license","")).name)
	var license_label := label(license_name,info);license_label.name="License";license_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;license_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;license_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	main.tooltip_text=str(asset.get("description",""))+"\n"+str(Policy.evaluate(asset).reason)
	main.pressed.connect(func():select_asset(asset,image.texture))
	info.minimum_size_changed.connect(func():main.custom_minimum_size.y=maxf(210,info.get_combined_minimum_size().y+16))
	var versions := HFlowContainer.new();versions.name="Versions";contents.add_child(versions)
	for option: Dictionary in selection.options(asset,false):
		var version := str(option.id);var owned := imported.has(version)
		var item := button(str(option.get("label",version))+(" ✓" if owned else " ↓"),func():download_one(asset,version),versions)
		item.name="Version_"+version;item.disabled=busy or (not client.can_download(asset) and not owned)
		item.tooltip_text="Already imported. Click to use the existing files." if owned else "Download "+str(option.get("label",version))
		if option.has("triangles"):item.tooltip_text+=" · %s triangles" % option.triangles
		if not selection.filter_key.is_empty() and Selection.option_key(asset,option)!=selection.filter_key:item.modulate=Color(1,1,1,.45)
	for version in imported:
		if not selection.options(asset,false).any(func(option):return str(option.id)==str(version)):label(str(version).to_upper()+" ✓",versions)
	if selection.options(asset,false).is_empty():button("Show versions",func():load_options(asset),versions).disabled=busy
	var footer := HBoxContainer.new();contents.add_child(footer)
	button("Details",func():show_details(asset),footer);button("Website",func():OS.shell_open(str(asset.get("url",""))),footer)
	var url := str(asset.get("thumbnail",""))
	if not url.is_empty():thumbnail_queue.append({"url":url,"image":image,"asset":asset,"token":token})
	return card
func select_asset(asset: Dictionary,_texture: Texture2D) -> void:
	selected=asset
	if selection.options(asset,false).is_empty():await load_options(asset)
	else:show_details(asset)
func load_options(asset: Dictionary) -> void:
	if busy:return
	var provider: Node=client.provider_for(asset)
	if not provider or not provider.enabled:return
	busy=true;stopping=false;client.network_allowed=true;status.text="Loading versions for "+str(asset.title)+"…";update_actions()
	var result: Dictionary=await provider.asset_details(asset)
	client.network_allowed=false;busy=false
	if not result.has("error"):
		client.index_assets([result]);selection.checked.erase(Selection.identity(asset));update_filter_choices()
	run_search()
	status.text=str(result.error) if result.has("error") else ("Available versions loaded." if not selection.options(result,false).is_empty() else "This site did not report available versions. Open its website to check.")
func show_details(asset: Dictionary) -> void:
	var record := Credits.asset_record(asset);var names := []
	for person in record.authors:names.append(str(person.name))
	var dialog := AcceptDialog.new();dialog.title=str(asset.get("title","Asset"));dialog.dialog_text="Creator: %s\nLicense: %s\n%s\n\n%s" % [", ".join(names) if not names.is_empty() else "Not supplied",record.license.name,Policy.evaluate(asset).reason,asset.get("description","")];add_child(dialog);dialog.popup_centered(Vector2i(520,300));dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free)
func download_selected() -> void:
	await run_jobs(selection.jobs(filtered_items()))
func download_one(asset: Dictionary,version: String) -> void:
	await run_jobs([{"asset":asset.duplicate(true),"version":version}])
func run_jobs(jobs: Array) -> void:
	if busy or jobs.is_empty():return
	if not output.text.begins_with("res://") or ".." in output.text:status.text="Choose an output folder inside res://.";return
	if handoff.button_pressed and (not inbox.text.begins_with("res://") or ".." in inbox.text):status.text="Choose a Terrain inbox inside res://.";return
	busy=true;stopping=false;update_actions();progress.max_value=jobs.size();progress.value=0
	var completed := 0;var failure := ""
	for job: Dictionary in jobs:
		if stopping:break
		status.text="Downloading %s / %s · %s · %s…" % [completed+1,jobs.size(),job.asset.title,str(job.version).to_upper()]
		client.network_allowed=true
		var result: Dictionary=await download_resolution(job.asset,str(job.version))
		client.network_allowed=false
		if result.has("error"):failure=str(result.error);break
		completed+=1;progress.value=completed;selection.checked.erase(Selection.identity(job.asset))
		if completed<jobs.size() and not stopping:
			var deadline := Time.get_ticks_msec()+roundi(delay.value*1000)
			while Time.get_ticks_msec()<deadline and not stopping:
				var remaining := (deadline-Time.get_ticks_msec())/1000.0
				status.text="%s / %s complete · next download in %s s…" % [completed,jobs.size(),ceili(remaining)]
				await get_tree().create_timer(minf(.1,remaining)).timeout
	busy=false;client.network_allowed=false;run_search();update_actions()
	if Engine.is_editor_hint():EditorInterface.get_resource_filesystem().scan()
	status.text="Download stopped: "+failure if not failure.is_empty() else "%s / %s downloads complete%s" % [completed,jobs.size()," · stopped" if stopping else "."]
func download_resolution(asset: Dictionary,requested: String) -> Dictionary:
	preparation.output_directory=output.text;preparation.send_to_terrain=handoff.button_pressed and asset.get("type","")=="material";preparation.terrain_inbox=inbox.text
	return await preparation.prepare(asset,requested)
func _process(delta: float) -> void:
	thumbnail_tick+=delta
	if thumbnail_tick<.2:return
	thumbnail_tick=0;pump_thumbnails()
func pump_thumbnails() -> void:
	if not is_visible_in_tree():return
	var visible_area := results_scroll.get_global_rect().grow(140);var i := 0
	while i<thumbnail_queue.size() and thumbnails_active<4:
		var job: Dictionary=thumbnail_queue[i]
		if job.token!=serial or not is_instance_valid(job.image):thumbnail_queue.remove_at(i);continue
		if not job.image.is_inside_tree() or not job.image.get_global_rect().intersects(visible_area):i+=1;continue
		thumbnail_queue.remove_at(i);thumbnails_active+=1;load_queued_thumbnail(job)
func load_queued_thumbnail(job: Dictionary) -> void:
	var texture: Texture2D=await client.thumbnail(job.url,job.asset)
	if is_instance_valid(job.image) and serial==job.token:job.image.texture=texture
	thumbnails_active-=1
func write_scene_credits() -> void:
	if not Engine.is_editor_hint():status.text="Scene credits are available in the editor.";return
	var root := EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path.is_empty():status.text="Save the scene first.";return
	var result := Credits.write_scene(root.scene_file_path)
	status.text=str(result.error) if result.has("error") else "Scene credits written · %s assets, %s resources missing credits." % [result.asset_count,result.missing_count]
func check_connection() -> void:
	if busy:return
	busy=true;stopping=false;client.network_allowed=true;status.text="Checking connections…";update_actions()
	var messages := []
	for id in client.active_ids():
		var provider: Node=client.providers[id];var result: Dictionary=await provider.check_connection();messages.append(str(provider.descriptor().name)+": "+str(result.get("error","Connected")))
	client.network_allowed=false;busy=false;account.text="; ".join(messages);status.text=account.text;update_actions()
