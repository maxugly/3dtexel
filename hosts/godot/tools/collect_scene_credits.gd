extends SceneTree
const Credits = preload("res://addons/3dtexel/credits.gd")
func _initialize():call_deferred("run")
func run():
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Pass one saved res:// scene path after --.");quit(1);return
	var result := Credits.write_scene(args[0])
	print(JSON.stringify(result))
	quit(1 if result.has("error") else 0)
