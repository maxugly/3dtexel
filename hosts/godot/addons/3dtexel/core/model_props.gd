@tool
extends RefCounted
## Editor-facing adapter for the shared static prop builder.
##
## The prop builder (src/core/prop_builder.gd and prop_geometry.gd) belongs to the
## host game project, not to this addon. Both are resolved lazily so the addon
## still loads, searches and downloads in a project that does not ship them;
## prop creation then reports that it is unavailable instead of failing to compile.
const Credits = preload("res://addons/3dtexel/credits.gd")
const Importer = preload("res://addons/3dtexel/importer.gd")
const BuilderPath := "res://src/core/prop_builder.gd"
const GeometryPath := "res://src/core/prop_geometry.gd"
const DEFAULT_OUTPUT := "res://scenes/world/props"
const MISSING_BUILDER := "Prop creation needs the host project's shared prop builder at res://src/core/prop_builder.gd."

static func available() -> bool:
	return ResourceLoader.exists(BuilderPath) and ResourceLoader.exists(GeometryPath)

static func builder() -> GDScript:
	return load(BuilderPath) as GDScript if ResourceLoader.exists(BuilderPath) else null

static func geometry() -> GDScript:
	return load(GeometryPath) as GDScript if ResourceLoader.exists(GeometryPath) else null

static func glbs(folder: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir:
		for name in dir.get_files():
			if name.get_extension().to_lower() == "glb": result.append(folder.path_join(name))
	result.sort()
	return result

static func wrapper_path(asset: Dictionary, version: String, source: String, output := DEFAULT_OUTPUT) -> String:
	var identity := "%s\n%s\n%s\n%s" % [asset.get("provider_id", ""), asset.get("id", ""), version, source.get_file()]
	var label := Importer.slug(str(asset.get("provider_id", "asset"))) + "_" + Importer.slug(str(asset.get("title", "model"))).left(40)
	return output.path_join("Library_%s_%s.tscn" % [label, identity.sha256_text().left(20)])

static func create(asset: Dictionary, version: String, source: String, output := DEFAULT_OUTPUT) -> Dictionary:
	if not source.begins_with("res://") or source.get_extension().to_lower() != "glb" or not FileAccess.file_exists(source):
		return {"error":"The downloaded GLB is missing or invalid."}
	var geometry_script := geometry()
	var builder_script := builder()
	if not geometry_script or not builder_script:
		return {"error":MISSING_BUILDER}
	var credit_path := source + ".credits.json"
	var credit: Variant = JSON.parse_string(FileAccess.get_file_as_string(credit_path)) if FileAccess.file_exists(credit_path) else null
	if not credit is Dictionary:
		return {"error":"The GLB has no readable credits; its files were preserved."}
	var source_hash := FileAccess.get_sha256(source)
	var identity := "%s\n%s\n%s\n%s" % [asset.get("provider_id", ""), asset.get("id", ""), version, source.get_file()]
	var target := wrapper_path(asset, version, source, output)
	if FileAccess.file_exists(target):
		var existing := ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if not existing: return {"error":"A different file already occupies " + target}
		var node := existing.instantiate()
		var matches := str(node.get_meta("library_source", "")) == source and str(node.get_meta("library_sha256", "")) == source_hash and str(node.get_meta("library_identity", "")) == identity
		var errors: PackedStringArray = geometry_script.validate(node)
		node.free()
		if not matches or not errors.is_empty(): return {"error":"Existing wrapper differs or needs review: " + target}
		if Credits.write_json(target + ".credits.json", credit) != OK: return {"error":"Cannot save wrapper credits: " + target}
		return {"path":target, "reused":true}
	var model := ResourceLoader.load(source, "PackedScene") as PackedScene
	if not model: return {"error":"Godot could not import this GLB; the downloaded files were preserved."}
	var prop: Node3D = builder_script.build(model, source.get_file().get_basename(), 1.0, {"collision_profile":"auto", "library_source":source, "library_sha256":source_hash, "library_version":version, "library_identity":identity})
	if not prop: return {"error":"Could not build valid collision for this model; the downloaded files were preserved."}
	if FileAccess.file_exists(output) or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		prop.free()
		return {"error":"Cannot create the prop output folder."}
	# Refuse replacement even when another file appears while geometry is prepared.
	if FileAccess.file_exists(target):
		prop.free()
		return {"error":"A file already occupies " + target}
	var err: int = geometry_script.save_prop(prop, target)
	prop.free()
	if err != OK: return {"error":"Could not save a budget-compliant prop (%s)." % err}
	if Credits.write_json(target + ".credits.json", credit) != OK: return {"error":"Prop saved but credits failed; use Create Prop to retry: " + target}
	return {"path":target, "reused":false}
