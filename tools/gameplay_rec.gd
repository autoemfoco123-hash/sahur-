extends SceneTree
## Records a scripted gameplay video, frame by frame, in game time.
## Run with --fixed-fps 30 so every frame advances exactly 1/30 s however slow rendering is.
##   godot3 --path . --fixed-fps 30 --resolution 1280x720 --high -s tools/gameplay_rec.gd out=DIR
## Writes DIR/f_00000.png ... and DIR/audio.jsonl (every playing sound, every frame) that
## tools/mix_log.py turns into the soundtrack.
##
## The scenario: menu -> host -> countdown -> boot the goggles -> walk the hallways following the
## hush chalk -> he calls three times -> nobody answers -> he comes -> turn around -> jumpscare.

const FPS = 30.0

var out = "/tmp/rec"
var n = 0
var t = 0.0
var max_t = 70.0
var log_f: File
var seen = {}
var phase = "menu"
var w_t0 = -1.0
var path_i = 1
var yaw_goal = 0.0
var hunted_t = -1.0
var kill_t = -1.0
var turned = false
var look_off = 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("secs="):
			max_t = float(a.substr(5))
	Directory.new().make_dir_recursive(out)
	log_f = File.new()
	log_f.open(out + "/audio.jsonl", File.WRITE)


func _net():
	return root.get_node("Net")


func _audio():
	return root.get_node("Audio")


func _idle(_d: float) -> bool:
	n += 1
	t = (n - 1) / FPS
	if n == 2:
		change_scene("res://scenes/menu.tscn")
	_direct()
	if n > 2:
		_shot()
		_log_audio()
	if n % 30 == 0:
		print("rec t=%.1f phase=%s" % [t, phase])
	return t >= max_t or (kill_t > 0.0 and t > kill_t + 8.5)


# ------------------------------------------------------------------ the scenario
func _direct() -> void:
	var net = _net()
	var menu = root.find_node("Menu", true, false)
	if phase == "menu":
		if t >= 3.2 and menu and menu.host_box and not menu.host_box.visible and not net.active():
			menu._show("host")
			menu.host_name.text = "lantern"
		if t >= 4.6 and not net.active() and menu:
			menu._do_host()
		if t >= 6.6 and net.active() and net.counting < 0 and net.state == net.LOBBY:
			net.force_start()
			phase = "countdown"
	elif phase == "countdown":
		if net.world and net.world.player and net.world.level:
			phase = "world"
			w_t0 = t
	elif phase == "world":
		_play(t - w_t0)


func _play(wt: float) -> void:
	var w = _net().world
	if w == null or w.player == null or w.level == null:
		return
	var pl = w.player
	var lv = w.level
	var tung = lv.tung
	# walk the chalk arrows toward the exit
	if wt >= 3.0 and hunted_t < 0.0:
		var pos: Vector3 = pl.global_transform.origin
		while path_i < lv.demo_path.size() - 1 and Vector2(lv.demo_path[path_i].x - pos.x, lv.demo_path[path_i].z - pos.z).length() < 1.6:
			path_i += 1
		var goal: Vector3 = lv.demo_path[min(path_i, lv.demo_path.size() - 1)]
		# start turning before the corner: blend toward the waypoint after this one
		if path_i + 1 < lv.demo_path.size():
			var dgoal = Vector2(goal.x - pos.x, goal.z - pos.z).length()
			var nxt: Vector3 = lv.demo_path[path_i + 1]
			goal = goal.linear_interpolate(nxt, clamp((3.0 - dgoal) / 3.0, 0.0, 0.6))
		var to = goal - pos
		yaw_goal = atan2(-to.x, -to.z)
		# hesitate while he is calling: stop, look around
		var calling = lv.calling and not lv.answered
		look_off = sin(wt * 0.9) * 0.35 if calling else sin(wt * 0.5) * 0.08
		pl._yaw = lerp_angle(pl._yaw, yaw_goal + look_off, 0.14)
		pl._pitch = lerp(pl._pitch, -0.05 + sin(wt * 0.7) * 0.06, 0.05)
		var walk = not (calling and fmod(lv.call_t, 2.6) < 1.4)
		if walk:
			Input.action_press("move_forward", 0.75)
		else:
			Input.action_release("move_forward")
	# he calls
	if wt >= 8.0 and wt < 8.2 and not lv.calling:
		lv.call_timer = 0.0
	# nobody answered: he is hunting us. put him in the hallway behind, in sight
	if tung and tung.state == 3 and hunted_t < 0.0:  # S.HUNT
		hunted_t = wt
		var back = max(0, path_i - 4)
		var at: Vector3 = lv.demo_path[back]
		if at.distance_to(pl.global_transform.origin) < 7.0:
			at = pl.global_transform.origin - (-pl.global_transform.basis.z) * 11.0
			at = w.nav.nearest_open(at) if w.nav and w.nav.has_method("nearest_open") else at
		tung.global_transform.origin = Vector3(at.x, tung.global_transform.origin.y, at.z)
		tung._repath = 0.0
		Input.action_release("move_forward")
	if hunted_t >= 0.0 and kill_t < 0.0:
		var ht = wt - hunted_t
		# hear him, stop, turn around slowly
		if ht > 0.7:
			var to = tung.global_transform.origin + Vector3(0, 2.0, 0) - pl.eye_pos()
			var yaw_to = atan2(-to.x, -to.z)
			var pitch_to = atan2(to.y, Vector2(to.x, to.z).length())
			var k = 0.05 if ht < 2.2 else 0.12
			pl._yaw = lerp_angle(pl._yaw, yaw_to, k)
			pl._pitch = lerp(pl._pitch, pitch_to, k)
		if ht > 2.0:
			Input.action_press("move_back", 0.45)
		if ht > 9.0:
			# never let the video run long: he is simply there
			tung.global_transform.origin = pl.global_transform.origin - pl.global_transform.basis.z * 0.9
	if w.dying and kill_t < 0.0:
		kill_t = t
		Input.action_release("move_back")
		Input.action_release("move_forward")


# ------------------------------------------------------------------ capture
func _shot() -> void:
	var img = root.get_texture().get_data()
	img.flip_y()
	img.save_png("%s/f_%05d.png" % [out, n - 3])


func _players(nd: Node, acc: Array) -> void:
	if nd is AudioStreamPlayer or nd is AudioStreamPlayer3D:
		acc.append(nd)
	for c in nd.get_children():
		_players(c, acc)


func _log_audio() -> void:
	var au = _audio()
	var lst = []
	var cam = au.listener_cam
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
		var tr = cam.global_transform
		lst = [tr.origin.x, tr.origin.y, tr.origin.z, tr.basis.x.x, tr.basis.x.y, tr.basis.x.z]
	var m = AudioServer.get_bus_index("Master")
	var buses = [AudioServer.is_bus_mute(m), AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		AudioServer.is_bus_mute(AudioServer.get_bus_index("Amb")), AudioServer.get_bus_volume_db(m)]
	var fx = [au._dist.drive, au._lp.cutoff_hz, au._reverb.wet, au._reverb.room_size]
	var rows = []
	var ps = []
	_players(root, ps)
	for p in ps:
		if not p.playing or p.stream == null:
			continue
		var id = p.get_instance_id()
		var path = p.stream.resource_path
		var row = {"id": id, "s": path, "p": p.pitch_scale, "b": p.bus}
		if p is AudioStreamPlayer3D:
			var o = p.global_transform.origin
			row["k"] = "3d"
			row["v"] = p.unit_db
			row["x"] = [o.x, o.y, o.z]
			row["md"] = p.max_distance
			row["us"] = p.unit_size
			row["c"] = p.attenuation_filter_cutoff_hz
		else:
			row["k"] = "2d"
			row["v"] = p.volume_db
		if not seen.has(id):
			seen[id] = true
			row["new"] = true
			row["off"] = p.get_playback_position()
		rows.append(row)
	log_f.store_line(to_json({"f": n - 3, "L": lst, "B": buses, "fx": fx, "P": rows}))
	log_f.flush()
