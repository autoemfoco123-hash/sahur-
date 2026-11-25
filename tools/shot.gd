extends SceneTree
## Dev tool: render a level and save screenshots.
## godot --path . -s res://tools/shot.gd -- level=0 out=/tmp/x frames=90 mode=enemy
var frames := 90
var level := "0"
var out := "/tmp/rot_shot"
var mode := "spawn"
var n := 0
var shots := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"level": level = kv[1]
			"out": out = kv[1]
			"frames": frames = int(kv[1])
			"mode": mode = kv[1]

func _process(_d: float) -> bool:
	n += 1
	if n == 1:
		var game = root.get_node_or_null("Game")
		game.current_level = level
		change_scene_to_file("res://scenes/menu.tscn" if level == "menu" else "res://scenes/world.tscn")
		return false
	var w = current_scene
	if n == 5 and w and mode == "enemy" and "player" in w:
		var es = get_nodes_in_group("hostile")
		if es.size() > 0:
			var e = es[0]
			var p: Vector3 = e.global_position - e.global_basis.z * 4.0
			w.player.global_position = p
			var d: Vector3 = e.global_position - p
			w.player.set_look(atan2(-d.x, -d.z), 0.12)
			e.frozen = true
	if n == frames - 10 and w and mode == "turn" and "player" in w:
		w.player.set_look(w.player._yaw + 0.5, 0.0)
	if n == 5 and w and mode == "nv" and "player" in w:
		w.player.set_visor(true)
		w.player.set_look(w.player._yaw, -0.35)
	if n == 5 and w and mode == "path" and "level" in w:
		var pth: Array = w.level.demo_path
		var a: Vector3 = pth[min(3, pth.size() - 1)]
		var b: Vector3 = pth[min(6, pth.size() - 1)]
		w.player.global_position = a + Vector3(0, 0.2, 0)
		var d: Vector3 = b - a
		w.player.set_look(atan2(-d.x, -d.z), 0.05)
		for e in get_nodes_in_group("hostile"):
			e.global_position = b + Vector3(0, 0.1, 0)
			e.frozen = true
			var to: Vector3 = a - b
			e.rotation.y = atan2(-to.x, -to.z)
	if n == 5 and w and mode == "high":
		w.player.set_look(w.player._yaw, -0.2)
	if n == frames or n == frames + 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [out, shots])
		shots += 1
	if n > frames + 40:
		return true
	return false
