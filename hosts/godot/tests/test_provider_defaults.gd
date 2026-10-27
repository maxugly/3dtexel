extends SceneTree
const Registry = preload("res://addons/3dtexel/core/registry.gd")
const Defaults = preload("res://addons/3dtexel/core/provider_defaults.gd")
const Browser = preload("res://addons/3dtexel/browser.gd")
class CustomProvider:
	extends "res://addons/3dtexel/core/provider.gd"
	func descriptor() -> Dictionary:return {"id":"custom_fixture","name":"Custom"}
var failures := 0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	check(not Defaults.complete(null),"Malformed evidence fails closed")
	check(not Defaults.complete({"passed":"true"}),"String flags are not proof of a live pass")
	check(not Defaults.complete({"passed":true,"search":true}),"An HTTP/search-only success cannot enable a provider")
	var complete := {"passed":true,"search":true,"ui_image":true,"download":true,"valid_asset":true,"asset_id":"fixture","variant":"original"}
	check(Defaults.complete(complete),"All required stages plus asset/version identity establish a verified default")
	for stage in ["passed","search","ui_image","download","valid_asset"]:
		var missing := complete.duplicate();missing[stage]=false
		check(not Defaults.complete(missing),"Missing "+stage+" keeps a provider unchecked")
	var key := "asset_browser/providers/artvee/"
	ProjectSettings.set_setting(key+"enabled",true);ProjectSettings.set_setting(key+"enabled_policy_revision","")
	var hub := Registry.new();root.add_child(hub)
	check(not hub.providers.artvee.enabled,"An old enabled preference does not re-enable an unverified provider")
	var expected: Array=["aic","ambientcg","archive_org","freesound","kaykit","kenney","library_of_congress","met_museum","nasa","opengameart","polyhaven","smk","texel","wellcome_collection","wikimedia"]
	var active: Array=hub.active_ids();active.sort()
	check(active==expected,"Exactly the verified live passes start enabled")
	for id in hub.providers:
		check(hub.providers[id].enabled==Defaults.verified(str(id)),"Default checkbox matches full live evidence for "+str(id))
	var custom := CustomProvider.new();hub.register_provider(custom)
	check(custom.enabled,"External provider defaults remain independent of bundled-site evidence")
	hub.queue_free();await process_frame
	ProjectSettings.set_setting(key+"enabled_policy_revision",Defaults.REVISION)
	hub=Registry.new();root.add_child(hub)
	check(hub.providers.artvee.enabled,"An explicit opt-in under the current policy is preserved for later repairs")
	hub.queue_free();await process_frame
	ProjectSettings.set_setting(key+"enabled",false)
	var browser := Browser.new();root.add_child(browser);await process_frame
	var checked_sources: Array=[]
	var names := {}
	for id in browser.client.providers:names[str(browser.client.providers[id].descriptor().name)]=str(id)
	for row in browser.settings_panel.get_children():
		for item in row.get_children():
			if item is CheckBox and names.has(item.text) and item.button_pressed:checked_sources.append(names[item.text])
	checked_sources.sort()
	check(checked_sources==expected,"Settings shows only the verified source checkboxes checked")
	var index := -1
	for i in browser.sites.item_count:
		if str(browser.sites.get_item_metadata(i))=="artvee":index=i
	check(index>=0,"Unchecked sites remain available for later investigation")
	browser._on_site_selected(index)
	check(not browser.client.providers.artvee.enabled and not browser.busy,"Selecting an unchecked site never silently enables it or starts a search")
	check(browser.status.text.contains("explicitly in Settings"),"UI explains how to opt back in explicitly")
	browser.queue_free();await process_frame
	ProjectSettings.set_setting(key+"enabled",null);ProjectSettings.set_setting(key+"enabled_policy_revision",null)
	print("Verified provider default tests complete; failures=",failures)
	quit(1 if failures else 0)
