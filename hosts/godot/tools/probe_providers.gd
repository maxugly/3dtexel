extends SceneTree
## Manual diagnostic (not an automated test): calls every provider once and reports
## outcome, item count and elapsed time per site.
## Usage: TEXEL_ALLOW_LIVE_TESTS=1 godot --headless --path hosts/godot -s tools/probe_providers.gd
## Env: TEXEL_PROBE_QUERY (default "wood"), TEXEL_PROBE_TIMEOUT (seconds, default 20),
##      TEXEL_PROBE_CONCURRENCY (default 6), TEXEL_PROBE_OUT (file path for the JSON report).

const Registry = preload("res://addons/3dtexel/core/registry.gd")

var client: Node
var query := "wood"
var timeout_ms := 20000
var concurrency := 6
var queue: Array = []
var results: Array = []
var started_ms := 0

func _initialize() -> void:
	if OS.get_environment("TEXEL_ALLOW_LIVE_TESTS") != "1":
		push_error("Live provider probe disabled. Set TEXEL_ALLOW_LIVE_TESTS=1 to run it.")
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	query = OS.get_environment("TEXEL_PROBE_QUERY")
	if query.is_empty():query = "wood"
	timeout_ms = int(float(OS.get_environment("TEXEL_PROBE_TIMEOUT")) * 1000.0) if not OS.get_environment("TEXEL_PROBE_TIMEOUT").is_empty() else 20000
	concurrency = int(OS.get_environment("TEXEL_PROBE_CONCURRENCY")) if not OS.get_environment("TEXEL_PROBE_CONCURRENCY").is_empty() else 6

	client = Registry.new()
	root.add_child(client)
	await process_frame
	client.network_allowed = true
	client.refreshing = true

	var only := OS.get_environment("TEXEL_PROBE_ONLY")
	for id in client.active_ids():
		if not only.is_empty() and not only.split(",", false).has(str(id)):continue
		queue.append(str(id))
	started_ms = Time.get_ticks_msec()
	print("Probing %s providers for '%s' (timeout %s ms, concurrency %s)" % [queue.size(), query, timeout_ms, concurrency])

	var total := queue.size()
	for _i in mini(concurrency, maxi(1, total)):_worker()
	while results.size() < total:await process_frame

	var elapsed := Time.get_ticks_msec() - started_ms
	var ok_count := 0
	var error_count := 0
	var item_total := 0
	print("")
	print("%-28s %-6s %-6s %-8s %s" % ["provider", "state", "items", "ms", "detail"])
	print("-".repeat(120))
	for entry: Dictionary in results:
		var state := "ok" if not entry.has("error") else "ERR"
		if state == "ok":ok_count += 1
		else:error_count += 1
		item_total += int(entry.get("count", 0))
		var detail := str(entry.get("error", "")) if entry.has("error") else ""
		print("%-28s %-6s %-6s %-8s %s" % [entry.get("id", "?"), state, str(entry.get("count", 0)), str(entry.get("ms", 0)), detail.left(90)])
	print("-".repeat(120))
	print("ok=%s error=%s items=%s wall=%s ms" % [ok_count, error_count, item_total, elapsed])

	var report := {"query": query, "elapsed_ms": elapsed, "ok": ok_count, "errors": error_count, "items": item_total, "results": results}
	var out := OS.get_environment("TEXEL_PROBE_OUT")
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
			print("report written to %s" % out)
	client.network_allowed = false
	quit(0)

func _worker() -> void:
	while not queue.is_empty():
		var id: String = queue.pop_front()
		results.append(await _probe(id))

func _probe(id: String) -> Dictionary:
	var provider: Node = client.providers.get(id)
	if provider == null:return {"id": id, "error": "provider missing"}
	var box := {"done": false, "result": {}}
	var started := Time.get_ticks_msec()
	_fetch(provider, box)
	while not box["done"] and Time.get_ticks_msec() - started < timeout_ms:
		await process_frame
	var ms := Time.get_ticks_msec() - started
	if not box["done"]:
		provider.cancel_all()
		return {"id": id, "ms": ms, "error": "TIMEOUT after %s ms" % timeout_ms, "count": 0}
	var result: Dictionary = box["result"]
	if result.has("error"):
		return {"id": id, "ms": ms, "error": str(result.error), "count": 0}
	return {"id": id, "ms": ms, "count": result.get("items", []).size(), "next_cursor": str(result.get("next_cursor", ""))}

func _fetch(provider: Node, box: Dictionary) -> void:
	var result: Dictionary = await provider.refresh_page(query, "all", "")
	box["result"] = result
	box["done"] = true
