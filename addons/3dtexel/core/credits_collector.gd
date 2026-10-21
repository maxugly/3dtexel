@tool
extends RefCounted
## Project-wide and scene-scoped attribution collector, audit engine, and Markdown exporter.

const Credits = preload("res://addons/3dtexel/credits.gd")
const Policy = preload("res://addons/3dtexel/core/license_policy.gd")

const MEDIA_EXTENSIONS := [
	"png", "jpg", "jpeg", "webp", "tga", "exr", "hdr", "dds",
	"glb", "gltf", "fbx", "obj", "blend",
	"wav", "ogg", "mp3"
]

const DEFAULT_IGNORE_DIRS := [
	".godot", ".git", ".import", ".system_generated", "tests"
]

static func collect_scene(scene_path: String) -> Dictionary:
	var result: Dictionary = Credits.collect_scene(scene_path)
	result["scope"] = "scene"
	result["scope_target"] = scene_path
	return enrich_collection(result)

static func collect_game(main_scene_path := "") -> Dictionary:
	var target_scene := main_scene_path.strip_edges()
	if target_scene.is_empty():
		target_scene = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if target_scene.is_empty() or not FileAccess.file_exists(target_scene):
		return {
			"error": "No valid main scene configured in ProjectSettings (application/run/main_scene)."
		}
	var result: Dictionary = Credits.collect_scene(target_scene)
	result["scope"] = "game"
	result["scope_target"] = target_scene
	return enrich_collection(result)

static func collect_project(res_root := "res://", ignore_dirs := []) -> Dictionary:
	var ignores := DEFAULT_IGNORE_DIRS.duplicate()
	for d in ignore_dirs:
		if d not in ignores:
			ignores.append(str(d))

	var all_scenes: Array[String] = []
	var media_files: Array[String] = []
	scan_directory(res_root, ignores, all_scenes, media_files)

	var assets := {}
	var missing_sidecars := []
	var scene_dependencies := {}

	# 1. Analyze scene dependencies to discover usage across all project scenes
	for scene_path in all_scenes:
		var scene_deps: Array[String] = [scene_path]
		var visited := {}
		while not scene_deps.is_empty():
			var cur: String = scene_deps.pop_back()
			if visited.has(cur):
				continue
			visited[cur] = true
			if not scene_dependencies.has(cur):
				scene_dependencies[cur] = []
			if scene_path not in scene_dependencies[cur]:
				scene_dependencies[cur].append(scene_path)

			for dep: String in ResourceLoader.get_dependencies(cur):
				var candidate: String = dep.get_slice("::", dep.get_slice_count("::") - 1)
				if candidate.begins_with("uid://"):
					var uid_id := ResourceUID.text_to_id(candidate)
					candidate = ResourceUID.get_id_path(uid_id) if ResourceUID.has_id(uid_id) else ""
				if candidate.begins_with("res://"):
					scene_deps.append(candidate)

	# 2. Check sidecars for all discovered media files
	for file_path in media_files:
		var sidecar := file_path + ".credits.json"
		var folder := file_path.get_base_dir()
		var record: Variant = null

		if FileAccess.file_exists(sidecar):
			record = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
		elif FileAccess.file_exists(folder.path_join("asset.credits.json")):
			record = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("asset.credits.json")))
		elif FileAccess.file_exists(folder.path_join("provenance.json")):
			record = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("provenance.json")))

		if record is Dictionary:
			var normalized := Credits.asset_record(record)
			var people: Array = normalized.authors
			var license: Dictionary = normalized.license
			var needs_review: bool = normalized.review_required or bool(record.get("review_required", false))
			normalized.merge(record, true)
			normalized.authors = people
			normalized.license = license
			normalized.review_required = needs_review
			record = normalized

			var asset_identity: Variant = record.get("asset_id")
			if asset_identity == null:
				asset_identity = record.get("source_url", sidecar)
			if str(asset_identity).is_empty():
				asset_identity = sidecar
			var identity := str(record.get("provider", "Unknown")) + ":" + str(asset_identity)

			if not assets.has(identity):
				assets[identity] = record.duplicate(true)
				assets[identity]["used_by"] = []
				assets[identity]["files"] = []

			if file_path not in assets[identity]["files"]:
				assets[identity]["files"].append(file_path)

			var scenes_using_file: Array = scene_dependencies.get(file_path, [])
			for sc in scenes_using_file:
				if sc not in assets[identity]["used_by"]:
					assets[identity]["used_by"].append(sc)
		else:
			missing_sidecars.append(file_path)

	var result := {
		"schema_version": 2,
		"scope": "project",
		"scope_target": res_root,
		"generated_utc": Time.get_datetime_string_from_system(true),
		"assets": assets.values(),
		"missing_sidecars": missing_sidecars,
		"note": "Full project scan across all media resources and scenes."
	}
	return enrich_collection(result)

static func scan_directory(dir_path: String, ignores: Array, out_scenes: Array[String], out_media: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != ".." and not name.begins_with("."):
			var full_path := dir_path.path_join(name)
			if dir.current_is_dir():
				var should_ignore := false
				for ig in ignores:
					if name == ig or full_path.ends_with("/" + ig) or full_path == ig:
						should_ignore = true
						break
				if not should_ignore:
					scan_directory(full_path, ignores, out_scenes, out_media)
			else:
				var ext := name.get_extension().to_lower()
				if ext in ["tscn", "scn"]:
					out_scenes.append(full_path)
				elif ext in MEDIA_EXTENSIONS and not name.ends_with(".credits.json"):
					out_media.append(full_path)
		name = dir.get_next()

static func enrich_collection(data: Dictionary) -> Dictionary:
	var raw_assets: Array = data.get("assets", [])
	var missing: Array = data.get("missing_sidecars", [])

	var cleared: Array[Dictionary] = []
	var review: Array[Dictionary] = []
	var blocked: Array[Dictionary] = []
	var license_counts: Dictionary = {}

	for asset in raw_assets:
		if asset is not Dictionary:
			continue
		if not asset.has("price"):
			var lic_rec := Credits.license_record(asset.get("license", {}))
			var lic_name := str(lic_rec.get("name", "")).to_lower()
			if lic_name in ["cc0", "cc-by-3.0", "cc-by-4.0", "oga-by-3.0", "oga-by-4.0", "public-domain"]:
				asset["price"] = {"free": true, "credits": 0}

		var policy := Policy.evaluate(asset)
		var lic_rec := Credits.license_record(asset.get("license", {}))
		var lic_name := str(lic_rec.get("name", "Unknown"))
		if not lic_name.is_empty():
			license_counts[lic_name] = int(license_counts.get(lic_name, 0)) + 1

		var authors := Credits.authors(asset)
		var is_review: bool = bool(asset.get("review_required", false)) or authors.is_empty() or lic_name == "Unknown" or int(policy.status) == Policy.Status.UNKNOWN

		if int(policy.status) == Policy.Status.BLOCKED:
			asset["compliance_status"] = "blocked"
			asset["compliance_reason"] = str(policy.reason)
			blocked.append(asset)
		elif is_review:
			asset["compliance_status"] = "review"
			asset["compliance_reason"] = str(policy.reason) if int(policy.status) == Policy.Status.UNKNOWN else "Attribution or creator metadata incomplete"
			review.append(asset)
		else:
			asset["compliance_status"] = "cleared"
			asset["compliance_reason"] = str(policy.reason)
			cleared.append(asset)

	data["cleared"] = cleared
	data["review"] = review
	data["blocked"] = blocked
	data["untracked"] = missing
	data["summary"] = {
		"total_assets": raw_assets.size(),
		"cleared_count": cleared.size(),
		"review_count": review.size(),
		"blocked_count": blocked.size(),
		"untracked_count": missing.size(),
		"licenses": license_counts
	}
	return data

static func license_category(lic_name: String) -> String:
	var lower := lic_name.to_lower().replace(" ", "-")
	if "cc0" in lower or "public-domain" in lower or "unlicense" in lower:
		return "cc0"
	if "-sa" in lower or "gpl" in lower or "share-alike" in lower:
		return "copyleft"
	if "cc-by" in lower or "oga-by" in lower or "by" in lower:
		return "attribution"
	return "proprietary"

static func format_markdown(collected: Dictionary, options := {}) -> String:
	var include_cc0: bool = bool(options.get("include_cc0", true))
	var include_attr: bool = bool(options.get("include_attribution", true))
	var include_copyleft: bool = bool(options.get("include_copyleft", true))
	var include_proprietary: bool = bool(options.get("include_proprietary", true))
	var include_untracked: bool = bool(options.get("include_untracked", true))
	var include_review: bool = bool(options.get("include_review", true))
	var allowed_licenses: Array = options.get("licenses", [])
	var doc_title: String = str(options.get("title", "Asset Credits & Attribution"))

	var assets: Array = collected.get("assets", [])
	var filtered_assets: Array[Dictionary] = []

	for item: Dictionary in assets:
		var lic_rec := Credits.license_record(item.get("license", {}))
		var lic_name := str(lic_rec.get("name", "Unknown"))
		if not allowed_licenses.is_empty() and lic_name not in allowed_licenses:
			continue
		var cat := license_category(lic_name)
		if cat == "cc0" and not include_cc0:
			continue
		if cat == "attribution" and not include_attr:
			continue
		if cat == "copyleft" and not include_copyleft:
			continue
		if cat == "proprietary" and not include_proprietary:
			continue
		filtered_assets.append(item)

	var summary: Dictionary = collected.get("summary", {})
	var lines: Array[String] = []
	lines.append("# " + doc_title)
	lines.append("")
	lines.append("This document records third-party media assets, author attributions, and license records.")
	lines.append("")
	lines.append("## Distribution Summary")
	lines.append("- **Scope**: " + str(collected.get("scope", "unknown")).capitalize() + " (`" + str(collected.get("scope_target", "res://")) + "`)")
	lines.append("- **Total Tracked Assets**: " + str(filtered_assets.size()))
	lines.append("- **Cleared for Release**: " + str(collected.get("cleared", []).size()))
	lines.append("- **Needs Review**: " + str(collected.get("review", []).size()))
	lines.append("- **Blocked / Conflicts**: " + str(collected.get("blocked", []).size()))
	lines.append("- **Untracked Media Files**: " + str(collected.get("untracked", []).size()))
	lines.append("- **Generated**: " + str(collected.get("generated_utc", Time.get_datetime_string_from_system(true))) + " UTC")
	lines.append("")

	# Group by License
	var groups := {}
	for a in filtered_assets:
		var lic := str(Credits.license_record(a.get("license", {})).name)
		if not groups.has(lic):
			groups[lic] = []
		groups[lic].append(a)

	var sorted_licenses := groups.keys()
	sorted_licenses.sort()

	for lic_name in sorted_licenses:
		lines.append("---")
		lines.append("")
		lines.append("## License: " + lic_name)
		var cat := license_category(lic_name)
		if cat == "cc0":
			lines.append("> [!NOTE]")
			lines.append("> These assets are in the Public Domain or declared under CC0. Attribution is not legally required, but acknowledged here for provenance.")
		elif cat == "copyleft":
			lines.append("> [!WARNING]")
			lines.append("> These assets carry Share-Alike or Copyleft terms. Verify license compatibility with your distribution model.")
		lines.append("")

		for asset in groups[lic_name]:
			var title := str(asset.get("title", "Untitled Asset"))
			lines.append("### " + title)

			var author_names := []
			for p in asset.get("authors", []):
				var pname := str(p.get("name", "")).strip_edges()
				var purl := str(p.get("url", "")).strip_edges()
				if not purl.is_empty():
					author_names.append("[%s](%s)" % [pname, purl])
				elif not pname.is_empty():
					author_names.append(pname)
			var authors_str := ", ".join(author_names) if not author_names.is_empty() else "Author not declared"
			lines.append("- **Creator**: " + authors_str)

			var lic_rec := Credits.license_record(asset.get("license", {}))
			var lic_url := str(lic_rec.get("url", "")).strip_edges()
			if not lic_url.is_empty():
				lines.append("- **License Terms**: [%s](%s)" % [lic_name, lic_url])
			else:
				lines.append("- **License Terms**: " + lic_name)

			var src_url := str(asset.get("source_url", asset.get("url", ""))).strip_edges()
			if not src_url.is_empty():
				lines.append("- **Source**: " + src_url)

			var attr_text := str(asset.get("attribution_text", asset.get("attribution", ""))).strip_edges()
			if not attr_text.is_empty():
				lines.append("- **Attribution Notice**: \"" + attr_text + "\"")

			var used_files: Array = asset.get("files", [])
			if not used_files.is_empty():
				var file_basenames := []
				for f in used_files:
					file_basenames.append(str(f).get_file())
				lines.append("- **Files**: `" + ", ".join(file_basenames) + "`")

			var used_scenes: Array = asset.get("used_by", [])
			if not used_scenes.is_empty():
				lines.append("- **Used in**: " + ", ".join(used_scenes))

			if asset.get("compliance_status") == "review":
				lines.append("- ⚠️ *Review Notice*: " + str(asset.get("compliance_reason", "Metadata review recommended before distribution.")))
			lines.append("")

	# Untracked media section
	var untracked: Array = collected.get("untracked", [])
	if include_untracked and not untracked.is_empty():
		lines.append("---")
		lines.append("")
		lines.append("## Untracked Media Files (Missing Sidecars)")
		lines.append("> [!IMPORTANT]")
		lines.append("> The following files were found in the project without `.credits.json` or provenance records. Review before publishing.")
		lines.append("")
		for u in untracked:
			lines.append("- `" + str(u) + "`")
		lines.append("")

	return "\n".join(lines)

static func export_credits(collected: Dictionary, target_path := "res://CREDITS.md", options := {}) -> Dictionary:
	var markdown := format_markdown(collected, options)
	var md_file := FileAccess.open(target_path, FileAccess.WRITE)
	if not md_file:
		return {"error": "Cannot open target file for writing: %s" % target_path}
	md_file.store_string(markdown)
	md_file.close()

	var json_path := target_path.get_basename() + ".credits.json"
	var err := Credits.write_json(json_path, collected)
	if err != OK:
		return {"error": "Could not write JSON credits: %s" % err}

	return {
		"markdown_path": target_path,
		"json_path": json_path,
		"assets_count": collected.get("assets", []).size(),
		"cleared_count": collected.get("cleared", []).size(),
		"review_count": collected.get("review", []).size(),
		"blocked_count": collected.get("blocked", []).size(),
		"untracked_count": collected.get("untracked", []).size()
	}
