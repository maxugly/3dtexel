extends SceneTree
## Unit and contract tests for multi-scope credits collection, compliance audit and markdown exporter.

const Credits = preload("res://addons/3dtexel/credits.gd")
const Collector = preload("res://addons/3dtexel/core/credits_collector.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("Starting credits collector & audit tests...")

	var fixture_dir := "res://tests/fixtures_credits_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_dir))

	# 1. Create test assets with sidecars:
	# Asset A: Cleared CC0 texture
	var texture_path := fixture_dir.path_join("grass.png")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	img.save_png(ProjectSettings.globalize_path(texture_path))

	var record_a := {
		"schema_version": 1,
		"provider": "TestProvider",
		"asset_id": "grass-01",
		"title": "Grass Texture",
		"authors": [{"name": "Nature Artist", "url": "https://example.com/artist"}],
		"license": {"name": "CC0", "url": "https://creativecommons.org/publicdomain/zero/1.0/", "attribution_required": false},
		"price": {"free": true},
		"source_url": "https://example.com/grass",
		"attribution_text": ""
	}
	Credits.write_json(texture_path + ".credits.json", record_a)
	Credits.write_json(fixture_dir.path_join("grass_mat.res.credits.json"), record_a)

	# Asset B: Cleared CC-BY 3.0 model with attribution text
	var model_path := fixture_dir.path_join("sword.glb")
	var f := FileAccess.open(ProjectSettings.globalize_path(model_path), FileAccess.WRITE)
	f.store_string("mock glb content")
	f.close()

	var record_b := {
		"schema_version": 1,
		"provider": "OpenGameArt",
		"asset_id": "iron-sword",
		"title": "Iron Sword",
		"authors": [{"name": "Blacksmith", "url": "https://example.com/smith"}],
		"license": {"name": "CC-BY 3.0", "url": "https://creativecommons.org/licenses/by/3.0/", "attribution_required": true},
		"price": {"free": true},
		"source_url": "https://opengameart.org/content/iron-sword",
		"attribution_text": "Created by Blacksmith. Licensed under CC-BY 3.0."
	}
	Credits.write_json(model_path + ".credits.json", record_b)

	# Asset C: Review required (Unknown author & license)
	var sound_path := fixture_dir.path_join("mystery_sound.wav")
	f = FileAccess.open(ProjectSettings.globalize_path(sound_path), FileAccess.WRITE)
	f.store_string("mock wav content")
	f.close()

	var record_c := {
		"schema_version": 1,
		"provider": "UnknownSite",
		"asset_id": "mystery-01",
		"title": "Mystery Sound",
		"authors": [],
		"price": {"free": true},
		"license": {"name": "Unknown"},
		"review_required": true
	}
	Credits.write_json(sound_path + ".credits.json", record_c)

	# Asset D: Blocked (Non-Commercial CC-BY-NC)
	var banner_path := fixture_dir.path_join("banner.png")
	img.fill(Color.RED)
	img.save_png(ProjectSettings.globalize_path(banner_path))

	var record_d := {
		"schema_version": 1,
		"provider": "CustomSite",
		"asset_id": "banner-nc",
		"title": "Kingdom Banner",
		"authors": [{"name": "Restricted Artist", "url": ""}],
		"price": {"free": true},
		"license": {"name": "CC-BY-NC 4.0"}
	}
	Credits.write_json(banner_path + ".credits.json", record_d)

	# Untracked media file: no .credits.json sidecar
	var untracked_path := fixture_dir.path_join("untracked_prop.png")
	img.fill(Color.WHITE)
	img.save_png(ProjectSettings.globalize_path(untracked_path))

	# 2. Create a test scene referencing texture_path
	var material := StandardMaterial3D.new()
	var texture_res := ImageTexture.create_from_image(img)
	material.albedo_texture = texture_res
	ResourceSaver.save(material, fixture_dir.path_join("grass_mat.res"))
	material.take_over_path(fixture_dir.path_join("grass_mat.res"))
	Credits.write_json(fixture_dir.path_join("grass_mat.res.credits.json"), record_a)

	var root_node := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = material
	root_node.add_child(mesh)
	mesh.owner = root_node
	var scene := PackedScene.new()
	scene.pack(root_node)
	var scene_path := fixture_dir.path_join("level.tscn")
	ResourceSaver.save(scene, scene_path)
	root_node.free()

	# 3. Test Scene Scope
	var scene_res := Collector.collect_scene(scene_path)
	check(scene_res.scope == "scene", "Scene scope identified")
	check(scene_res.assets.size() >= 1, "Scene dependencies collected")

	# 4. Test Project Scope
	var proj_res := Collector.collect_project(fixture_dir, [])
	check(proj_res.scope == "project", "Project scope identified")
	check(proj_res.assets.size() == 4, "Project scope finds all 4 tracked assets")
	check(proj_res.untracked.size() >= 1, "Untracked media file without sidecar detected")
	check(untracked_path in proj_res.untracked, "Specific untracked prop identified")

	# Check compliance classification
	check(proj_res.cleared.size() == 2, "Cleared bucket has 2 assets (Grass CC0 and Sword CC-BY)")
	check(proj_res.review.size() == 1, "Review bucket has 1 asset (Mystery Sound)")
	check(proj_res.blocked.size() == 1, "Blocked bucket has 1 asset (Banner CC-BY-NC)")

	# 5. Test Markdown Formatting with License Toggles
	# Test with CC0 included
	var md_all := Collector.format_markdown(proj_res, {
		"title": "Game Credits",
		"include_cc0": true,
		"include_attribution": true,
		"include_untracked": true
	})
	check("# Game Credits" in md_all, "Markdown title rendered")
	check("## License: CC0" in md_all, "CC0 section included")
	check("## License: CC-BY 3.0" in md_all, "CC-BY section included")
	check("Created by Blacksmith" in md_all, "Attribution notice verbatim rendered")
	check("Untracked Media Files" in md_all, "Untracked section rendered")

	# Test with CC0 toggled OFF
	var md_no_cc0 := Collector.format_markdown(proj_res, {
		"include_cc0": false,
		"include_attribution": true
	})
	check("## License: CC0" not in md_no_cc0, "CC0 section excluded when toggle is false")
	check("## License: CC-BY 3.0" in md_no_cc0, "CC-BY still present")

	# 6. Test Export to File (CREDITS.md and .credits.json)
	var export_target := fixture_dir.path_join("CREDITS.md")
	var exp_res := Collector.export_credits(proj_res, export_target, {"include_cc0": true})
	check(not exp_res.has("error"), "Credits exported without error")
	check(FileAccess.file_exists(export_target), "CREDITS.md written to disk")
	check(FileAccess.file_exists(fixture_dir.path_join("CREDITS.credits.json")), "JSON companion manifest written")

	var exported_text := FileAccess.get_file_as_string(export_target)
	check("Blacksmith" in exported_text, "Author preserved in exported file")

	# 7. Test Convenience API in Credits
	var cov_res := Credits.collect_project(fixture_dir, [])
	check(cov_res.summary.total_assets == 4, "Credits wrapper passes through correctly")

	# Clean up fixture files
	var d := DirAccess.open(fixture_dir)
	if d:
		for file in d.get_files():
			d.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_dir))

	print("Credits collector & audit tests complete; failures=", failures)
	quit(1 if failures else 0)
