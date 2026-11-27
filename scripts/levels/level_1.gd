extends "res://scripts/levels/level_0.gd"
## LEVEL 1 — THE KEY ROOMS. (Godot 3)
## A hotel floor that never ends: green damask, red carpet, warm round lamps far apart, and doors
## that never open. KEYS only move while nobody is looking at them. One of them is the master key:
## keep it in sight, walk up to it and take it. Then the exit opens, for everyone.

const KeysAI := preload("res://scripts/enemies/keys.gd")

var keys = []
var master
var key_holder = -1
var _key_shots = {}       # enemy index -> photographed 75+
var _stare = 0.0          # team seconds spent face to face with a key


func build() -> void:
	env({
		"ambient": Color(0.95, 0.72, 0.5), "ambient_energy": 0.5 if Mats.potato() else 0.36,
		"fog_color": Color(0.11, 0.075, 0.05), "fog_begin": 4.0 if Mats.potato() else 5.0, "fog_end": 30.0 if Mats.potato() else 44.0, "fog_curve": 1.5,
		"tint": Vector3(1.05, 0.98, 0.86), "contrast": 1.08, "saturation": 1.0,
	})
	boot_goggles = true
	greeter = "keys"
	chalk = Color(0.8, 0.8, 0.76, 0.85)     # chalk; the wall light under it decides how bright it reads
	open_ratio = 0.22
	pillar_ratio = 0.0
	var size = Vector2(CW * C, CH * C)
	var om = _shell(size)
	var start = _start_cell()
	var info = _bfs(start)
	var dist: Dictionary = info.dist
	var par: Dictionary = info.parent
	var far = _exit_cell(dist)
	exit_z = _cell(far).z
	_build_walls(om)
	# the missions: the door stays shut until all three are done
	add_mission("master", "take the master key", 1, "")
	add_mission("keys", "photograph every key, 75+ each", 4)
	add_mission("stare", "hold a key's gaze, closer than 2 m", 8, "secs")
	var sp = _cell(start)
	spawn_player(sp + Vector3(0, 0.2, 0), -PI * 0.5 if has_entry else -PI * 0.75)
	_arrival(start)
	# the keys (decided before anything visual touches the rng, so every machine agrees).
	# They sleep until the first operative comes through the door (start_wave).
	var spots = _key_spots(dist, sp, 4)
	for i in spots.size():
		var k = enemy(KeysAI, "keys", spots[i] + Vector3(0, 0.05, 0))
		k.rotation.y = rng.randf_range(-PI, PI)
		k.dormant = 1e9
		keys.append(k)
	master = keys[0]
	master.make_master()
	# the exit is the sliding door in the east wall, locked until someone holds the master key
	if world.headless:
		return
	if player():
		var grab = Interactable.make(master, master.global_transform.origin + Vector3(0, 1.3, 0), 0.75, "take the master key", self, "_grab", [], false)
		master.set_meta("grab", grab)
	# warm round lamps, far apart
	var cells = dist.keys()
	cells.sort()
	var lamp_pos = []
	for c in cells:
		if c == start or c == far or rng.randf() < 0.34:
			var lp = _cell(c, H - 0.004)
			lp.x = floor(lp.x / 0.6) * 0.6 + 0.3
			lp.z = floor(lp.z / 0.6) * 0.6 + 0.3
			lamp_pos.append(lp)
			om.panel(lp)
	_place_doors(om)
	bake = LightBake.new()
	world.add_child(bake)
	var walls2d = []
	for sgm in _wall_list:
		walls2d.append([Vector2(sgm[0].x, sgm[0].z), Vector2(sgm[1].x, sgm[1].z)])
	var lxz = []
	for lp in lamp_pos:
		lxz.append(Vector2(lp.x, lp.z))
	lxz.append(Vector2(origin.x + size.x - 1.0, exit_z))     # a lamp in front of the exit door
	if has_entry:
		lxz.append(Vector2(origin.x + 1.0, entry_z))         # and one by the door you came in through
	bake.build(Rect2(o2() + Vector2(-1.6, -1.6), size + Vector2(3.2, 3.2)), lxz, walls2d, 0.85)
	ink_light = {"light_tint": Vector3(1.0, 0.8, 0.58), "exposure": 0.95, "ambient": 0.035}
	om.commit(geo, bake.office_mats(H, world.env, {
		"tex": {"floor": ["carpet_red", 1.0], "wall": ["wallpaper_green", 1.0], "ceiling": ["plaster", 2.0],
			"panel": ["lamp_round", 0.6], "door": ["wood", 1.0], "knob": ["brass", 0.3]},
		"tint": Vector3(1.0, 0.8, 0.58), "exposure": 0.95, "ambient": 0.035,
	}))
	for lp in lamp_pos:
		lights.append(Geo.lamp_light(world, lp, bake, 1.25, Color(1.0, 0.8, 0.55)))
	note(sp + Vector3(0.7, 0.0, -0.7), "hush · descent briefing · sector 1\n\nthe key rooms. a hotel floor that does not end.\nevery door is locked. every lock is the same.\n\nsubject 'keys' does not move while it is watched.\nnot an inch. look away and it is closer.\n\none of them is the master key. it glows. it runs.\nkeep your eyes on it, walk up, take it (e).\nthe exit opens for all of you.\n\nwatch each other's backs. literally.")
	var pts = scatter_points(6, sp, 14.0, 0.0)
	if pts.size() > 0:
		note(pts[0], "they jingle when they move.\nif you hear keys behind you,\ndo not turn around slowly.\n\n- operative 05")
	if pts.size() > 1:
		note(pts[1], "the master key does not want to be held.\nwe caught it once. it was warm.\nit was breathing.\n\n- operative 02")
	# hush chalk on the carpet: arrows to the exit
	var path = [far]
	while path[-1] != start and par.has(path[-1]):
		path.append(par[path[-1]])
	path.invert()
	for i in range(1, path.size() - 1, 2):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var m = ir_mark(_cell(a, 0.02), 0.0, "↑", 170)
		m.rotation = Vector3(-PI / 2, atan2(-(b.x - a.x), -(b.y - a.y)), 0)
	demo_path = []
	for c in path:
		demo_path.append(_cell(c))
	_wall_writing(["don't blink", "it was right there", "keep looking", "the master key runs", "03 the doors are not doors", "behind you"])
	uncanny_cfg = {"lights": lights, "watcher_ids": ["keys"], "max_watchers": 2}


func enter(boot: bool) -> void:
	ambient("amb_keys", -5.0, "amb_heavy", -16.0)
	Audio.set_reverb(0.5, 0.2)
	if player():
		player().step_sound = "step_grass"
		player().step_volume = -18.0
		world.set_dust(350)
	if boot:
		boot_goggles_now()


## Somebody came through the door: the keys wake up, one after another.
func start_wave() -> void:
	wave_started = true
	for i in keys.size():
		if is_instance_valid(keys[i]):
			keys[i].dormant = 9.0 + i * 1.5


func killer_id() -> String:
	return "keys"


## Spread out, far from the operatives.
func _key_spots(dist: Dictionary, sp: Vector3, n: int) -> Array:
	var cells = dist.keys()
	cells.sort()
	var far_cells = []
	for c in cells:
		if _cell(c).distance_to(sp) > 18.0:
			far_cells.append(c)
	var out = []
	for i in n:
		var best = null
		var bd = -1.0
		for k in 24:
			var c = far_cells[rng.randi() % far_cells.size()]
			var d = 1e9
			for o in out:
				d = min(d, _cell(c).distance_to(o))
			if out.empty():
				d = _cell(c).distance_to(sp)
			if d > bd:
				bd = d
				best = c
		out.append(_cell(best))
	return out


## Hotel doors along the corridors: dark wood, a frame, a brass knob and a room plate.
func _place_doors(om) -> void:
	for sgm in _wall_list:
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		var along_x = sz.x > sz.z
		var length = sz.x if along_x else sz.z
		if length < 3.5:
			continue
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.55:
				continue
			var n = Vector3(0, 0, side) if along_x else Vector3(side, 0, 0)
			var t = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
			var off = rng.randf_range(-length * 0.5 + 0.9, length * 0.5 - 0.9)
			var face = pos + n * (T * 0.5) + t * off
			face.y = 0.0
			var rel = face - origin
			if rel.x < 0.3 or rel.z < 0.3 or rel.x > CW * C - 0.3 or rel.z > CH * C - 0.3:
				continue
			if (rel.x < 1.0 and has_entry and abs(face.z - entry_z) < 1.7) or (rel.x > CW * C - 1.0 and abs(face.z - exit_z) < 1.7):
				continue      # the sliding doors have this spot
			_hotel_door(om, face, n, t, 0.92)


## One locked hotel door on a wall face: slab, frame, brass knob, room plate.
func _hotel_door(om, face: Vector3, n: Vector3, t: Vector3, w: float) -> void:
	wall_blockers.append(face)
	om.box_sides("door", face + n * 0.025 + Vector3(0, 1.04, 0), _sz(t, n, w, 2.08, 0.05))
	for s2 in [-1.0, 1.0]:
		om.box_sides("door", face + n * 0.035 + t * (w * 0.5 + 0.035) * s2 + Vector3(0, 1.08, 0), _sz(t, n, 0.07, 2.16, 0.07))
	om.box_sides("door", face + n * 0.035 + Vector3(0, 2.15, 0), _sz(t, n, w + 0.14, 0.07, 0.07))
	om.box_sides("knob", face + n * 0.08 + t * (w * 0.5 - 0.1) + Vector3(0, 1.0, 0), _sz(t, n, 0.06, 0.06, 0.06))
	om.box_sides("knob", face + n * 0.055 + t * (w * 0.5 - 0.1) + Vector3(0, 0.9, 0), _sz(t, n, 0.04, 0.11, 0.012))
	om.box_sides("knob", face + n * 0.055 + Vector3(0, 1.6, 0), _sz(t, n, 0.13, 0.07, 0.012))


func _sz(t: Vector3, n: Vector3, w: float, h: float, d: float) -> Vector3:
	var v = t.abs() * w + n.abs() * d
	v.y = h
	return v


# ------------------------------------------------------------------ rules
func _physics_process(_delta: float) -> void:
	if here() and randf() < 0.015 and lights.size() > 0:
		var l: SpotLight = lights[randi() % lights.size()]
		Geo.lamp_set_on(l, false)
		get_tree().create_timer(rand_range(0.05, 0.3)).connect("timeout", self, "_relight", [l])
	var threat = 0.0
	for k in keys:
		if is_instance_valid(k) and k.is_threat():
			threat = 0.45
	danger_bonus = threat
	# server: someone face to face with a frozen key, closer than 2 m, counts the seconds
	if authority() and wave_started and _mission_index("stare") >= 0 and not missions[_mission_index("stare")].done:
		var who = -1
		for k in keys:
			if not is_instance_valid(k) or k.master or k.taken or not k.observed:
				continue
			var kp: Vector3 = k.global_transform.origin
			for t in world.targets(index):
				if Vector2(t.pos.x - kp.x, t.pos.z - kp.z).length() < 2.0:
					who = t.id
			if who >= 0:
				break
		if who >= 0:
			var before = int(_stare)
			_stare += _delta
			if int(_stare) != before:
				mission_set("stare", float(int(_stare)), who)


## Shouting does nothing here. The keys don't care.
func on_shout(_pid: int) -> void:
	pass


func _grab() -> void:
	if Net.active():
		Net.request("grab")
	else:
		on_request(1, "grab", [])


## Server: someone wants the master key. Only if they are actually next to it.
func on_request(pid: int, type: String, args: Array) -> void:
	if type == "photo":
		# a good photo of a key counts it (every key, the master too)
		if args.size() > 2 and float(args[1]) >= 75.0:
			var inst = int(args[2])
			if inst >= 0 and inst < world.enemies.size() and world.enemies[inst] in keys:
				_key_shots[inst] = true
				mission_set("keys", _key_shots.size(), pid)
		# the flash holds every key in front of the lens for two seconds
		var tp = world.target_by_id(pid)
		if tp == null or not tp.has("fwd"):
			return
		for k in keys:
			var to: Vector3 = k.global_transform.origin + Vector3(0, 1.3, 0) - tp.eye
			if to.length() < 14.0 and tp.fwd.dot(to.normalized()) > 0.6:
				k.stun = 2.0
		return
	if type != "grab" or master == null or master.taken:
		return
	var t = world.target_by_id(pid)
	if t == null or t.pos.distance_to(master.global_transform.origin) > 2.8:
		return
	for k in keys:
		k.enraged = true
	_emit("key_taken", [pid])
	mission_set("master", 1, pid)
	# once taken the master key is gone from sight: nobody could photograph it any more and
	# "every key" would be stuck at 3/4 for good. Holding it counts as its evidence.
	var mi = world.enemies.find(master)
	if mi >= 0 and not _key_shots.has(mi):
		_key_shots[mi] = true
		mission_set("keys", _key_shots.size(), pid)


func net_event(type: String, args: Array) -> void:
	match type:
		"key_taken":
			key_holder = args[0]
			if master and not master.taken:
				master.set_taken()
				if master.has_meta("grab") and is_instance_valid(master.get_meta("grab")):
					master.get_meta("grab").queue_free()
			for k in keys:
				k.enraged = true
			var hud = world.hud
			if hud and here():
				var who = "you" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0])
				hud.subtitle("%s took the master key.   they are not patient anymore." % who, 4.0)
				Audio.play("pickup", -2.0, 0.8)
				Audio.play("ev_slam", -6.0, 0.7)
		"shout":
			pass
