@tool
extends Control
const Client = preload("res://addons/3dtexel/client.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
var content: VBoxContainer
var editor_plugin: EditorPlugin
var client: Node
var search: LineEdit
var kind: OptionButton
var resolution: OptionButton
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
var page_label: Label
var selected := {}
var page := 1
var busy := false
var serial := 0
var pending_details := false
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
	var title := Label.new(); title.text = "3D Texel · PBR material library"; title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; title.add_theme_font_size_override("font_size",24);content.add_child(title)
	var toolbar := HFlowContainer.new();content.add_child(toolbar)
	search = LineEdit.new();search.custom_minimum_size.x = 220;search.placeholder_text = "Search grass, worn concrete, rusty metal…";search.size_flags_horizontal = Control.SIZE_EXPAND_FILL;toolbar.add_child(search)
	search.text_submitted.connect(func(_text): start_search())
	kind = OptionButton.new();kind.add_item("Handmade · free CC0");kind.add_item("Community · AI materials");toolbar.add_child(kind)
	button("Search",start_search,toolbar)
	button("Check connection",check_connection,toolbar)
	button("Website",func(): OS.shell_open("https://3dtexel.com/pbr-material/"),toolbar)
	account = Label.new();account.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;account.text = "Environment key found." if not client.api_key().is_empty() else "Browsing works without a key. Downloads need an environment API key; restart Godot after setting it."
	content.add_child(account)
	var settings := HFlowContainer.new();content.add_child(settings)
	var label := Label.new();label.text = "Download:";settings.add_child(label)
	resolution = OptionButton.new()
	for value in ["1K","2K","4K"]: resolution.add_item(value)
	resolution.select(1); settings.add_child(resolution)
	output = LineEdit.new();output.custom_minimum_size.x = 180;output.text = str(ProjectSettings.get_setting("3dtexel/output_directory","res://3DTexel/Materials"));output.tooltip_text = "Native material and original maps; separate asset and actual-resolution folders.";output.size_flags_horizontal = Control.SIZE_EXPAND_FILL;settings.add_child(output)
	button("Open folder",func(): OS.shell_open(ProjectSettings.globalize_path(output.text)),settings)
	var terrain_row := HFlowContainer.new();content.add_child(terrain_row)
	handoff = CheckBox.new();handoff.text = "Also send to Terrain imports";handoff.button_pressed = false;terrain_row.add_child(handoff)
	inbox = LineEdit.new();inbox.custom_minimum_size.x = 180;inbox.text = str(ProjectSettings.get_setting("3dtexel/terrain_inbox","res://assets/terrain/inbox"));inbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL;terrain_row.add_child(inbox)
	var hint := Label.new();hint.text = "Download resolution ≠ Terrain imports output resolution. Terrain handoff uses that plugin’s current packing size.";hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(hint)
	body = SplitContainer.new();body.size_flags_horizontal = Control.SIZE_EXPAND_FILL;body.size_flags_vertical = Control.SIZE_EXPAND_FILL;content.add_child(body)
	results_scroll = ScrollContainer.new();results_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL;results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL;results_scroll.custom_minimum_size = Vector2(175,160);results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(results_scroll)
	grid = GridContainer.new();grid.columns = 3;grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);results_scroll.add_child(grid)
	side = VBoxContainer.new();side.custom_minimum_size.x = 240;side.size_flags_horizontal = Control.SIZE_EXPAND_FILL;body.add_child(side)
	preview = TextureRect.new();preview.custom_minimum_size = Vector2(180,180);preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;side.add_child(preview)
	detail = RichTextLabel.new();detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size.y = 100;detail.size_flags_vertical = Control.SIZE_EXPAND_FILL;detail.text = "Search the library, then select a material.\n\nOriginal source maps and provenance are preserved. Godot materials use mipmapped BC3 textures and anisotropic filtering.\n\nFree downloads only in this version; paid assets can be opened on the website.";side.add_child(detail)
	download = button("Download and prepare",download_selected,side);download.disabled = true
	button("Open selected on website",func():
		if not selected.is_empty(): OS.shell_open(str(selected.get("url","https://3dtexel.com"))),side)
	var pages := HBoxContainer.new();content.add_child(pages)
	previous = button("← Previous",func(): page=maxi(1,page-1); run_search(),pages)
	page_label = Label.new();page_label.clip_text = true;page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pages.add_child(page_label)
	next = button("Next →",func(): page+=1; run_search(),pages)
	previous.disabled=true;next.disabled=true
	status = Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.text="Ready. No downloads or changes occur until you choose a material.";content.add_child(status)
	resized.connect(update_layout)
	results_scroll.resized.connect(update_columns)
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
func run_search() -> void:
	if busy: return
	busy=true;serial+=1
	var token := serial
	status.text="Searching…"
	previous.disabled=true;next.disabled=true
	for child in grid.get_children(): child.queue_free()
	var type := "pbr" if kind.selected == 0 else "ai-pbr"
	var data: Dictionary = await client.json_request("/assets/search?q=%s&type=%s&page=%s&per_page=12" % [search.text.uri_encode(),type,page])
	busy=false
	if data.has("error"): status.text="Search failed: "+str(data.error);return
	var items: Array = data.get("items",[])
	var total := int(data.get("total",0))
	page_label.text="Page %s · %s materials" % [page,total]
	previous.disabled=page<=1;next.disabled=page*12>=total or page>=50
	status.text="%s results on this page. Select a card for details." % items.size()
	for asset: Dictionary in items:
		var card := VBoxContainer.new();card.custom_minimum_size.x=165;grid.add_child(card)
		var image := TextureRect.new();image.custom_minimum_size=Vector2(155,130);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.add_child(image)
		var choose := button(str(asset.get("title","Material")),func(): select_asset(asset,image.texture),card)
		choose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;choose.custom_minimum_size.y=54
		var license_label := Label.new();license_label.text="Free · CC0" if Importer.free_asset(asset) else "Website download · check license";card.add_child(license_label)
		load_thumbnail(str(asset.get("thumbnail","")),image,token)
func load_thumbnail(url: String, image: TextureRect, token: int) -> void:
	if url.is_empty(): return
	var texture: Texture2D = await client.thumbnail(url)
	if is_instance_valid(image) and serial==token: image.texture=texture
func select_asset(asset: Dictionary, texture: Texture2D) -> void:
	if busy: return
	selected=asset;preview.texture=texture;download.disabled=true
	pending_details=true
	var id := int(asset.id)
	detail.text=str(asset.title)+"\n\nLoading details…"
	var data: Dictionary = await client.json_request("/assets/%s" % id)
	if selected.is_empty() or int(selected.id)!=id: return
	pending_details=false
	if data.has("error"): detail.text="Details unavailable: "+str(data.error);return
	# API may expand license and return canonical asset metadata.
	selected.merge(data,true)
	var license_value: Variant = selected.get("license","")
	var license_text := str(license_value.get("name","")) if license_value is Dictionary else str(license_value)
	var availability: Dictionary = selected.get("download",{})
	detail.text="%s\n\n%s\n\nLicense: %s\nAsset ID: %s\n%s" % [selected.get("title",""),str(selected.get("description","")).strip_edges(),license_text,id,"Available through the API." if availability.get("via_api",true) else "Download this asset from its website."]
	download.disabled=not Importer.free_asset(selected) or client.api_key().is_empty() or availability.get("via_api",true)==false
	if not Importer.free_asset(selected): status.text="Paid assets are browse-only here. Open the website to review them."
func check_connection() -> void:
	if busy:return
	if client.api_key().is_empty():account.text="No key in Godot’s environment. Launch Godot from a shell that loads your secrets.";return
	account.text="Checking…"
	var result: Dictionary = await client.json_request("/me")
	account.text="Connection failed: "+str(result.error) if result.has("error") else "Connected · API key accepted. Key remains in the environment."
func download_selected() -> void:
	if busy or pending_details or selected.is_empty():return
	if not Importer.free_asset(selected):return
	if not output.text.begins_with("res://") or ".." in output.text:
		status.text="Choose an output directory inside res://, without parent traversal.";return
	if handoff.button_pressed and (not inbox.text.begins_with("res://") or ".." in inbox.text):
		status.text="Choose a terrain inbox inside res://, without parent traversal.";return
	busy=true;download.disabled=true
	var asset := selected.duplicate(true)
	var requested := resolution.get_item_text(resolution.selected).to_lower()
	status.text="Requesting free %s download…" % requested
	var response: Dictionary = await client.json_request("/assets/%s/download" % int(asset.id),HTTPClient.METHOD_POST,{"max_credits":0,"resolution":requested})
	if response.has("error"): finish_error(str(response.error));return
	var files: Dictionary = response.get("files",{})
	if int(response.get("charged_credits",0))!=0:finish_error("Unexpected charged response; no further action taken.");return
	var actual := Importer.slug(str(files.get("resolution",requested)))
	var folder := output.text.path_join("%s_%s" % [Importer.slug(str(asset.title)),int(asset.id)]).path_join(actual)
	if FileAccess.file_exists(folder.path_join("provenance.json")):
		finish_error("This version already exists at %s. Choose another resolution or move that folder to preserve it before retrying." % folder);return
	var source := folder.path_join("_source")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source))
	var ignore := FileAccess.open(source.path_join(".gdignore"),FileAccess.WRITE)
	if ignore:ignore.close()
	var maps := {};var hashes := {}
	for role in Importer.MAPS:
		var url := Importer.file_url(files.get(role,""))
		if url.is_empty():continue
		var relative := "_source/%s.%s" % [role,Importer.extension(url)]
		var destination := folder.path_join(relative)
		status.text="Downloading %s · %s…" % [asset.title,role]
		var result: Dictionary = await client.get_bytes(url,ProjectSettings.globalize_path(destination+".pending"),256*1024*1024)
		if result.has("error"):finish_error(str(result.error));return
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(destination+".pending"),ProjectSettings.globalize_path(destination))!=OK:
			finish_error("Cannot finish downloaded map.");return
		maps[role]=relative;hashes[role]=FileAccess.get_sha256(destination)
	if not maps.has("albedo"):finish_error("No supported albedo map was returned. Original files are retained.");return
	status.text="Packing mipmaps and GPU-compressed materials…"
	await get_tree().process_frame
	var normal_format := str(files.get("normal_format","opengl"))
	var result := Importer.make_material(folder,maps,normal_format,files.get("material_props",{}))
	if result.has("error"):finish_error(str(result.error));return
	var provenance := {"provider":"3DTexel","asset_id":int(asset.id),"title":asset.title,"source_url":asset.get("url",""),"license":response.get("license",asset.get("license","")),"requested_resolution":requested,"returned_resolution":actual,"normal_format":normal_format,"maps":maps,"sha256":hashes,"dimensions":result.dimensions,"imported_utc":Time.get_datetime_string_from_system(true),"charged_credits":0}
	if Importer.write_json(folder.path_join("provenance.json"),provenance)!=OK:finish_error("Could not save provenance.");return
	var note := ""
	if handoff.button_pressed:
		var terrain := Importer.terrain_handoff(folder,maps,asset,normal_format,inbox.text)
		note=" Terrain handoff failed: "+str(terrain.error) if terrain.has("error") else " Sent to Terrain imports at its current output size."
	ProjectSettings.set_setting("3dtexel/output_directory",output.text)
	ProjectSettings.set_setting("3dtexel/terrain_inbox",inbox.text)
	ProjectSettings.save()
	if Engine.is_editor_hint():EditorInterface.get_resource_filesystem().scan()
	status.text="Ready: %s.%s%s" % [result.material," Server supplied %s instead of %s." % [actual,requested] if actual!=requested else "",note]
	busy=false;download.disabled=false
func finish_error(message: String) -> void:
	status.text="Import stopped: "+message
	busy=false;download.disabled=false
