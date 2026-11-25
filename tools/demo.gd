extends SceneTree
## Dev tool: autopilot gameplay recording.
## godot --path . --write-movie out.avi --fixed-fps 30 --resolution 1280x720 -s res://tools/demo.gd -- seconds=30 seed=7
var seconds := 30.0
var seed_v := 7
var t := 0.0
var started := false
var w
var lvl
var i := 1
var yaw_noise := FastNoiseLite.new()
var shouted := false
var tung_set := false
var hunt_set := false
var stuck_t := 0.0
var unstick_t := 0.0
var unstick_dir := 1
const DT := 1.0 / 30.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"seconds": seconds = float(kv[1])
			"seed": seed_v = int(kv[1])
	yaw_noise.frequency = 0.35


func _process(_d: float) -> bool:
	if not started:
		started = true
		var game = root.get_node("Game")
		game.forced_seed = seed_v
		game.current_level = "0"
		game.settings.sensitivity = 0.25
		change_scene_to_file("res://scenes/world.tscn")
		return false
	w = current_scene
	if w == null or not ("level" in w) or w.level == null:
		return false
	lvl = w.level
	t += DT
	_drive()
	return t >= seconds


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _drive() -> void:
	var p = w.player
	if t < 0.1:
		lvl.call_timer = 6.0
		if lvl.tung:
			var far: Vector3 = lvl.demo_path[-1]
			lvl.tung.global_position = Vector3(far.x, 0.1, far.z)
			lvl.tung.frozen = true
	var path: Array = lvl.demo_path
	# Stand still while the visor boots, glance around a little
	if t < 3.2:
		p._pitch = sin(t * 1.3) * 0.08 - 0.05
		return
	if w.dying:
		_press("move_forward", false)
		_press("move_right", false)
		_press("move_left", false)
		return
	# Follow the maze path
	while i < path.size() - 1 and Vector2(path[i].x - p.global_position.x, path[i].z - p.global_position.z).length() < 1.1:
		i += 1
	var target: Vector3 = path[min(i, path.size() - 1)]
	var d: Vector3 = target - p.global_position
	var want := atan2(-d.x, -d.z) + yaw_noise.get_noise_1d(t * 10.0) * 0.18
	var diff := wrapf(want - p._yaw, -PI, PI)
	p._yaw += clampf(diff * 3.2 * DT * 1.6, -2.6 * DT, 2.6 * DT)
	p._pitch = lerpf(p._pitch, sin(t * 0.7) * 0.1 - 0.06 + yaw_noise.get_noise_1d(t * 6.0 + 50.0) * 0.08, 0.05)
	_press("move_forward", absf(diff) < 0.9)
	# Getting stuck on a prop or a corner? Sidestep like a person would.
	if p.horizontal_speed() < 0.6 and absf(diff) < 0.9:
		stuck_t += DT
	else:
		stuck_t = 0.0
	if stuck_t > 0.4:
		stuck_t = 0.0
		unstick_t = 0.6
		unstick_dir = -unstick_dir
		i = min(i + 1, path.size() - 1)
	unstick_t -= DT
	# Strafe bursts show off the tilt
	var sr := (fmod(t, 9.0) > 6.3 and fmod(t, 9.0) < 7.0) or (unstick_t > 0.0 and unstick_dir > 0)
	var sl := (fmod(t, 9.0) > 7.5 and fmod(t, 9.0) < 8.2) or (unstick_t > 0.0 and unstick_dir < 0)
	_press("move_right", sr)
	_press("move_left", sl)
	# Answer his call after the second knock
	if lvl.calling and lvl.call_t > 3.0 and not shouted:
		shouted = true
		var ev := InputEventAction.new()
		ev.action = "shout"
		ev.pressed = true
		Input.parse_input_event(ev)
		var ev2 := InputEventAction.new()
		ev2.action = "shout"
		ev2.pressed = false
		Input.parse_input_event(ev2)
	# He's waiting further down the hall...
	if t > seconds - 14.0 and not tung_set and lvl.tung:
		tung_set = true
		var k: int = min(i + 5, path.size() - 1)
		var tp: Vector3 = path[k]
		lvl.tung.global_position = Vector3(tp.x, 0.1, tp.z)
		var to: Vector3 = w.player.global_position - lvl.tung.global_position
		lvl.tung.rotation.y = atan2(-to.x, -to.z)
		lvl.tung.frozen = true
	# ...and then he comes.
	if t > seconds - 10.0 and not hunt_set and lvl.tung:
		hunt_set = true
		lvl.tung.frozen = false
		lvl.tung.set_state(lvl.tung.S.HUNT)
