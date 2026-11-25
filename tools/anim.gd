extends SceneTree
## Dev tool: film Tung walking/running on the test stage.
var started := false
var seconds := 10.0

func _process(_d: float) -> bool:
	if not started:
		started = true
		var game = root.get_node("Game")
		game.current_level = "anim"
		change_scene_to_file("res://scenes/world.tscn")
		return false
	seconds -= 1.0 / 30.0
	return seconds <= 0.0
