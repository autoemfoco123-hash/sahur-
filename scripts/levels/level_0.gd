extends LevelBase
## LEVEL 0 — THE SAHUR HALLWAYS. (Godot 3)
## Endless open-plan office space: mono-yellow walls, damp carpet, a drop ceiling of square lights.
## Answer the call. Never shout when he isn't calling.

const TungAI := preload("res://scripts/enemies/tung.gd")
const LightBake := preload("res://scripts/light_bake.gd")
const OfficeMesh := preload("res://scripts/office_mesh.gd")
const C := 4.0
const H := 2.75
const T := 0.28
const CW := 12
const CH := 12

var tung
var call_timer = 14.0
var calling = false
var call_t = 0.0
var answered = false
var lights = []
var demo_path = []
var walls_h = {}
var walls_v = {}
var _wall_list = []
var bake
var open_ratio = 0.5      # share of maze walls knocked out (open-plan office)
var pillar_ratio = 0.45   # free-standing pillars at empty corners


func build() -> void:
	env({
		"ambient": Color(0.92, 0.88, 0.62), "ambient_energy": 0.62 if Mats.potato() else 0.42,
		"fog_color": Color(0.62, 0.6, 0.42), "fog_begin": 6.0 if Mats.potato() else 8.0, "fog_end": 34.0 if Mats.potato() else 60.0, "fog_curve": 1.4 if Mats.potato() else 1.7,
		"tint": Vector3(1.03, 1.0, 0.86), "contrast": 1.05, "saturation": 1.0,
	})
	boot_goggles = true
	greeter = "tung"
	var size = Vector2(CW * C, CH * C)
	make_nav(Vector2(-1, -1), size + Vector2(1, 1), 0.5)
	nav.margin = 0.3
	# One collider each for floor and ceiling; what you see is the merged, light-baked office mesh.
	Geo.solid(world, Vector3(size.x + 2, 0.4, size.y + 2), origin + Vector3(size.x * 0.5, -0.2, size.y * 0.5), null, null, false)
	Geo.solid(world, Vector3(size.x + 2, 0.4, size.y + 2), origin + Vector3(size.x * 0.5, H + 0.2, size.y * 0.5), null, null, false)
	var om = OfficeMesh.new()
	om.plane("floor", o2() + Vector2(-0.2, -0.2), o2() + size + Vector2(0.4, 0.4), 0.0, true)
	om.plane("ceiling", o2() + Vector2(-0.2, -0.2), o2() + size + Vector2(0.4, 0.4), H, false)
	_layout()
	_build_walls(om)
	var start = Vector2(0, 0)
	var info = _bfs(start)
	var dist: Dictionary = info.dist
	var par: Dictionary = info.parent
	var far = start
	for c in dist:
		if dist[c] > dist[far]:
			far = c
	# Square ceiling panels, snapped to the 60 cm drop-ceiling grid
	var cells = dist.keys()
	cells.shuffle()
	var lamp_pos = []
	for c in cells:
		if c == start or c == far or rng.randf() < 0.5:
			var lp = _cell(c, H - 0.004) + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			lp.x = floor(lp.x / 0.6) * 0.6 + 0.3
			lp.z = floor(lp.z / 0.6) * 0.6 + 0.3
			lamp_pos.append(lp)
			om.panel(lp)
	# Exit
	var back: Vector2 = par.get(far, far)
	var dirv = Vector3(back.x - far.x, 0, back.y - far.y)
	var exit_at = _cell(far) - dirv * 1.2
	# the way on: it opens straight into the key rooms
	make_exit(exit_at, atan2(dirv.x, dirv.z), Color(1.0, 0.72, 0.42))
	if world.headless:
		# dedicated server: collision, navigation and rules only, nothing to draw
		spawn_player(_cell(start) + Vector3(0, 0.2, 0), -PI * 0.75)
		tung = enemy(TungAI, "tung", _tung_spawn(dist, far, _cell(start)) + Vector3(0, 0.1, 0))
		return
	# Bake the light once (GPU, 2D soft shadows + bounce + occlusion), then build the meshes
	bake = LightBake.new()
	world.add_child(bake)
	var walls2d = []
	for sgm in _wall_list:
		walls2d.append([Vector2(sgm[0].x, sgm[0].z), Vector2(sgm[1].x, sgm[1].z)])
	var lxz = []
	for lp in lamp_pos:
		lxz.append(Vector2(lp.x, lp.z))
	var eg = exit_at + dirv * 0.9
	lxz.append(Vector2(eg.x, eg.z))
	bake.build(Rect2(o2() + Vector2(-1.6, -1.6), size + Vector2(3.2, 3.2)), lxz, walls2d)
	om.commit(world, bake.office_mats(H, world.env))
	for lp in lamp_pos:
		lights.append(Geo.lamp_light(world, lp, bake, rng.randf_range(1.5, 1.9)))
	# Player
	var sp = _cell(start)
	spawn_player(sp + Vector3(0, 0.2, 0), -PI * 0.75)
	note(sp + Vector3(0.7, 0.0, -0.7), "hush · descent briefing · operative 03\n\nyou are below the feed now. this is the rot.\nthe nv-7 goggles are bolted to your skull. they do not come off.\nnaked eyes don't work down here. we tried.\n\nsector 0 is held by subject 'tung'. he calls three times.\nanswer him: shout sahur (q) before the third call ends.\nstay quiet, and he comes looking for the quiet one.\n\nwe do not speak of it. we watch it.")
	var pts = scatter_points(6, sp, 14.0, 0.0)
	if pts.size() > 0:
		note(pts[0], "do not shout when he isn't calling.\nhe hates being called for nothing.\ni learned that the hard way.\n\nall the lights are on. all of them. all the time.\nthe carpet is wet and nobody knows why.\n\n- operative 02")
	if pts.size() > 1:
		note(pts[1], "hush · incident log · operative 01\n\noperative 01 pried his goggles off at 03:00:41.\nthe feed shows him standing still for six hours.\nsmiling.\n\nthe goggles kept recording on the floor.\nthe last frame is a wooden face.\n\n(operative 01 was not recovered)")
	# Tung
	tung = enemy(TungAI, "tung", _tung_spawn(dist, far, sp) + Vector3(0, 0.1, 0))
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
	_wall_writing(["he is listening", "answer once", "don't look up", "we watched. we did nothing", "03 you are not the first", "behind you"])
	# scares are personal: every operative gets their own (world.gd makes them on entering)
	uncanny_cfg = {"lights": lights, "watcher_ids": ["tung"], "max_watchers": 2, "tposers": 1}


func enter(boot: bool) -> void:
	ambient("amb_hall", -9.0, "amb_heavy", -11.0)
	Audio.set_reverb(0.75, 0.28)
	if player():
		player().step_sound = "step_grass"
		player().step_volume = -16.0
		world.set_dust(500)
	if boot:
		get_tree().create_timer(1.0).connect("timeout", self, "_boot_1")
		get_tree().create_timer(2.4).connect("timeout", self, "_boot_2")


func start_wave() -> void:
	.start_wave()
	call_timer = 14.0


## Tung starts halfway down the maze, far from the operatives.
func _tung_spawn(dist: Dictionary, far: Vector2, sp: Vector3) -> Vector3:
	var tp = sp
	var best = 1 << 30
	var keys = dist.keys()
	keys.sort()
	for c in keys:
		var dd: int = int(abs(dist[c] - dist[far] / 2))
		if dd < best and _cell(c).distance_to(sp) > 20.0:
			best = dd
			tp = _cell(c)
	return tp


func _boot_1() -> void:
	world.hud.subtitle("hush nv-7 · booting…", 1.6)


func _boot_2() -> void:
	if not world.dying:
		player().set_visor(true)
		world.hud.fade(0.0, 0.5)
		world.hud.subtitle("goggles locked · gyro calibrated · auto gain", 2.5)


# ------------------------------------------------------------------ layout
func _cell(c: Vector2, y := 0.0) -> Vector3:
	return origin + Vector3((c.x + 0.5) * C, y, (c.y + 0.5) * C)


func _layout() -> void:
	for x in CW:
		for y in CH:
			if y < CH - 1:
				walls_h[Vector2(x, y)] = true
			if x < CW - 1:
				walls_v[Vector2(x, y)] = true
	var stack = [Vector2(0, 0)]
	var seen = {Vector2(0, 0): true}
	while stack.size() > 0:
		var c: Vector2 = stack[-1]
		var opts = []
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var nb: Vector2 = c + d
			if nb.x >= 0 and nb.y >= 0 and nb.x < CW and nb.y < CH and not seen.has(nb):
				opts.append(nb)
		if opts.empty():
			stack.pop_back()
			continue
		var nx: Vector2 = opts[rng.randi() % opts.size()]
		seen[nx] = true
		_open(c, nx)
		stack.append(nx)
	for k in walls_h.keys():
		if rng.randf() < open_ratio:
			walls_h.erase(k)
	for k in walls_v.keys():
		if rng.randf() < open_ratio:
			walls_v.erase(k)


func _open(a: Vector2, b: Vector2) -> void:
	if a.x == b.x:
		walls_h.erase(Vector2(a.x, min(a.y, b.y)))
	else:
		walls_v.erase(Vector2(min(a.x, b.x), a.y))


func _passable(a: Vector2, b: Vector2) -> bool:
	if b.x < 0 or b.y < 0 or b.x >= CW or b.y >= CH:
		return false
	if a.x == b.x:
		return not walls_h.has(Vector2(a.x, min(a.y, b.y)))
	return not walls_v.has(Vector2(min(a.x, b.x), a.y))


func _bfs(start: Vector2) -> Dictionary:
	var dist = {start: 0}
	var parent = {}
	var q = [start]
	while q.size() > 0:
		var c: Vector2 = q.pop_front()
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var nb: Vector2 = c + d
			if _passable(c, nb) and not dist.has(nb):
				dist[nb] = dist[c] + 1
				parent[nb] = c
				q.append(nb)
	return {"dist": dist, "parent": parent}


func _build_walls(om) -> void:
	var sb = StaticBody.new()
	sb.collision_layer = Geo.LAYER_WORLD
	world.add_child(sb)
	var segs = []
	for k in walls_h:
		segs.append([Vector3((k.x + 0.5) * C, H * 0.5, (k.y + 1) * C), Vector3(C + T, H, T)])
	for k in walls_v:
		segs.append([Vector3((k.x + 1) * C, H * 0.5, (k.y + 0.5) * C), Vector3(T, H, C + T)])
	var w = CW * C
	var d = CH * C
	segs.append([Vector3(w * 0.5, H * 0.5, 0), Vector3(w + T, H, T)])
	segs.append([Vector3(w * 0.5, H * 0.5, d), Vector3(w + T, H, T)])
	segs.append([Vector3(0, H * 0.5, d * 0.5), Vector3(T, H, d + T)])
	segs.append([Vector3(w, H * 0.5, d * 0.5), Vector3(T, H, d + T)])
	for x in range(1, CW):
		for y in range(1, CH):
			var touching = walls_h.has(Vector2(x - 1, y - 1)) or walls_h.has(Vector2(x, y - 1)) or walls_v.has(Vector2(x - 1, y - 1)) or walls_v.has(Vector2(x - 1, y))
			if not touching and rng.randf() < pillar_ratio:
				segs.append([Vector3(x * C, H * 0.5, y * C), Vector3(0.95, H, 0.95)])
	for sgm in segs:
		sgm[0] += origin
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		var cs = CollisionShape.new()
		var sh = BoxShape.new()
		sh.extents = sz * 0.5
		cs.shape = sh
		sb.add_child(cs)
		cs.translation = pos
		nav.block_box(pos, sz)
		om.box_sides("wall", pos, sz)
		_wall_list.append(sgm)


func _wall_writing(lines: Array) -> void:
	var picks = _wall_list.duplicate()
	picks.shuffle()
	var placed = 0
	for sgm in picks:
		if placed >= lines.size():
			break
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		if sz.x < 1.5 and sz.z < 1.5:
			continue
		var normal = Vector3(0, 0, 1) if sz.x > sz.z else Vector3(1, 0, 0)
		if rng.randf() < 0.5:
			normal = -normal
		var at = pos + normal * (min(sz.x, sz.z) * 0.5 + 0.02)
		at.y = 1.55
		var rel = at - origin
		if rel.x < 0.5 or rel.z < 0.5 or rel.x > CW * C - 0.5 or rel.z > CH * C - 0.5:
			continue
		ir_mark(at, atan2(normal.x, normal.z), lines[placed], 64)
		placed += 1


# ------------------------------------------------------------------ the call
## The server runs the call; every machine hears it through net_event().
func _physics_process(delta: float) -> void:
	# Godot 3 runs every _physics_process in the class chain: sectors built on this one
	# (no tung) skip the call entirely.
	if tung == null or not is_instance_valid(tung):
		return
	# A tube somewhere stutters, then catches again (each operative sees their own).
	if here() and randf() < 0.02 and lights.size() > 0:
		var l: SpotLight = lights[randi() % lights.size()]
		Geo.lamp_set_on(l, false)
		get_tree().create_timer(rand_range(0.04, 0.25)).connect("timeout", self, "_relight", [l])
	danger_bonus = 0.55 if tung.is_threat() else (0.25 if calling and not answered else 0.0)
	if not authority() or not wave_started or world.targets(index).empty():
		return
	if not calling:
		call_timer -= delta
		if call_timer <= 0.0:
			_emit("call_start", [])
			call_t = 0.0
	else:
		var prev = call_t
		call_t += delta
		for k in 3:
			var t0 = k * 2.6
			if prev < t0 and call_t >= t0 and not answered:
				_emit("knock", [k])
		if call_t > 3 * 2.6 + 0.8:
			call_timer = rng.randf_range(20.0, 30.0)
			if not answered:
				# "he is coming for the quiet one": somebody who stayed quiet
				var ts = world.targets(index)
				tung.hunt_id = ts[randi() % ts.size()].id
				_emit("unanswered", [tung.hunt_id])
				tung.set_state(TungAI.S.HUNT)
				tung.hunt_id = tung.hunt_id
			_emit("call_end", [])


## Sector events go to the same sector on every machine.
func _emit(type: String, args: Array) -> void:
	if Net.active():
		Net.event("sector", [index, type, args])
	else:
		net_event(type, args)


## Runs on every machine (server included). Only operatives looking at this sector see the text.
func net_event(type: String, args: Array) -> void:
	var hud = world.hud if here() else null
	match type:
		"call_start":
			calling = true
			answered = false
		"call_end":
			calling = false
		"knock":
			_knock_fx(args[0])
		"answered":
			answered = true
			if hud:
				var who = "you" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0])
				hud.subtitle("%s answered.  he walks past." % who, 3.0)
		"wrong_shout":
			if hud:
				var who = "you" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0])
				hud.subtitle("%s shouted when he wasn't calling.   he heard." % who, 3.0)
		"flash_woke":
			if hud:
				var who = "your" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0]) + "'s"
				hud.subtitle("%s flash woke him up." % who, 3.0)
		"unanswered":
			if hud:
				var quiet = "you" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0])
				hud.subtitle("he heard nothing.  he is coming for the quiet one:  %s." % quiet, 4.5)
				Audio.play("tung", -2.0, 0.5)


func _relight(l: SpotLight) -> void:
	if is_instance_valid(l):
		Geo.lamp_set_on(l, true)


func _knock_fx(k: int) -> void:
	if world.hud == null or not here():
		return
	for i in 3:
		get_tree().create_timer(i * 0.32).connect("timeout", self, "_knock_hit")
	get_tree().create_timer(1.1).connect("timeout", self, "_knock_voice")
	world.hud.subtitle("tung  tung  tung …  sahur      (%d/3)" % (k + 1), 2.4)


func _knock_hit() -> void:
	Audio.play_at("tung", tung.global_transform.origin + Vector3(0, 2, 0), world, 6.0, 0.85, 200.0)
	Audio.play("tung", -16.0, 0.8)


func _knock_voice() -> void:
	if not answered:
		Audio.play_at("sahur_low", tung.global_transform.origin + Vector3(0, 2, 0), world, 6.0, 1.0, 200.0)
		Audio.play("sahur_low", -14.0)


## Server: requests from operatives. A flash in his face wakes him up.
func on_request(pid: int, type: String, args: Array) -> void:
	if type != "photo" or tung == null or args.empty() or str(args[0]) != "tung":
		return
	var t = world.target_by_id(pid)
	if t and t.pos.distance_to(tung.global_transform.origin) < 12.0 and not tung.is_threat():
		tung.chase_id = pid
		tung.set_state(TungAI.S.CHASE)
		_emit("flash_woke", [pid])


## Server: operative `pid` shouted.
func on_shout(pid: int) -> void:
	if calling and not answered:
		_emit("answered", [pid])
		tung.set_state(TungAI.S.PASSIVE)
	elif not calling:
		_emit("wrong_shout", [pid])
		tung.set_state(TungAI.S.HUNT)
		tung.hunt_id = pid
