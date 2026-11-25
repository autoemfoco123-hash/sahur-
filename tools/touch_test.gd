extends SceneTree
## Dev tool: run the level with touch controls forced on.
var n := 0
var out := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv[0] == "out":
			out = kv[1]

func _process(_d: float) -> bool:
	n += 1
	if n == 1:
		var game = root.get_node("Game")
		game.force_touch = true
		game.current_level = "0"
		change_scene_to_file("res://scenes/world.tscn")
	if n == 90 and out != "":
		root.get_viewport().get_texture().get_image().save_png(out)
	return n > 100
