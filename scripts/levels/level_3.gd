extends "res://scripts/levels/level_0.gd"
## LEVEL 3 — SIX SEVEN. (Godot 3)
## A labyrinth with no colour left in it: paper-white walls, and every inch of every wall, floor
## and ceiling written over by hand, 6 7 6 7 6 7, the air itself full of drifting sixes and
## sevens. Only the operatives still have colour.
## 67 lives here. It is multidimensional: walls do not stop it, and it shapes the maze with its
## hands. Every call (SIX! / SEVEN!) the world turns negative for a breath, the black gates
## marked with that number sink into the floor and the others rise. The way changes every call.
## You fall in here from the void under the field (sector 2), or come in through a door.

const SixSevenAI := preload("res://scripts/enemies/sixseven.gd")
const CALL_FIRST = 12.0
const GATE_DUR = 0.9
const GATE_SINK = H - 0.012     # open: the slab's top lies flush in the floor, a black strip

var ss                      # 67
var layout = 6              # the gates with this number are open (sunk)
var gates = []              # {a, b, n, pos, along_x, open, want, root, shape}
var numerals = {}           # 6 / 7 -> {pos, root}
var _num_taken = {}
var _next_call = CALL_FIRST
var _calls_ok = 0           # calls lived through in a row, nobody taken
var _alive_prev = -1
var _call_fx = -1.0         # seconds since the last call began (the negative flash)
var _digits: CPUParticles
var _gate_mat: Material
var _num_font: DynamicFont


func build() -> void:
	mono = true
	env({
		"bg": Color(0, 0, 0), "ambient": Color(1, 1, 1), "ambient_energy": 0.42 if Mats.potato() else 0.3,
		"fog_color": Color(0, 0, 0), "fog_begin": 4.0, "fog_end": 22.0 if Mats.potato() else 27.0, "fog_curve": 1.3,
		"tint": Vector3(1.03, 1.0, 0.97), "contrast": 1.18, "saturation": 1.0, "mono": true,
	})
	boot_goggles = true
	greeter = "67"
	chalk = Color(0.06, 0.06, 0.06, 0.95)     # black marker on white paper
	open_ratio = 0.06                          # a real labyrinth: almost no shortcuts
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
	# where you land (from the void) or walk in (through a door), and where the dead come back
	var sp = _cell(start)
	var yaw = _face_open(start)
	spawn_player(sp + Vector3(0, 0.2, 0), yaw)
	if has_entry:
		_arrival(start)
	else:
		arrive_pos = sp + Vector3(0, 0.2, 0)
		arrive_yaw = yaw
	# the missions: the way out stays shut until all four are done
	add_mission("portrait", "a portrait of 67, 90+", 90, "best")
	add_mission("six", "bring back the six", 1, "")
	add_mission("seven", "bring back the seven", 1, "")
	add_mission("calls", "live through 7 calls in a row, nobody taken", 7)
	# its gates and the two numbers (decided before anything visual touches the rng)
	var path = [far]
	while path[-1] != start and par.has(path[-1]):
		path.append(par[path[-1]])
	path.invert()
	_choose_gates(dist, path, start, far)
	_build_gates()
	ss = enemy(SixSevenAI, "67", _tung_spawn(dist, far, sp) + Vector3(0, 0.1, 0))
	ss.dormant = 1e9
	if world.headless:
		return
	# sparse white lamps; the fog eats the rest
	var cells = dist.keys()
	cells.sort()
	var lamp_pos = []
	for c in cells:
		if c == start or c == far or rng.randf() < 0.3:
			var lp = _cell(c, H - 0.004)
			lp.x = floor(lp.x / 0.6) * 0.6 + 0.3
			lp.z = floor(lp.z / 0.6) * 0.6 + 0.3
			lamp_pos.append(lp)
			om.panel(lp)
	bake = LightBake.new()
	world.add_child(bake)
	var walls2d = []
	for sgm in _wall_list:
		walls2d.append([Vector2(sgm[0].x, sgm[0].z), Vector2(sgm[1].x, sgm[1].z)])
	var lxz = []
	for lp in lamp_pos:
		lxz.append(Vector2(lp.x, lp.z))
	lxz.append(Vector2(origin.x + size.x - 1.0, exit_z))     # a lamp in front of the way out
	if has_entry:
		lxz.append(Vector2(origin.x + 1.0, entry_z))
	bake.build(Rect2(o2() + Vector2(-1.6, -1.6), size + Vector2(3.2, 3.2)), lxz, walls2d, 0.95)
	ink_light = {"light_tint": Vector3(1, 1, 1), "exposure": 1.0, "ambient": 0.03}
	om.commit(geo, bake.office_mats(H, world.env, {
		"tex": {"floor": ["floor_67", 3.0], "wall": ["wall_67", 2.2], "ceiling": ["ceiling_67", 3.0], "panel": ["panel", 0.6]},
		"tint": Vector3(1, 1, 1), "exposure": 1.0, "ambient": 0.03, "mono": true,
	}))
	for lp in lamp_pos:
		lights.append(Geo.lamp_light(world, lp, bake, rng.randf_range(1.3, 1.6), Color(1, 1, 1)))
	_gate_visuals()
	_numeral_visuals()
	note(sp + Vector3(0.7, 0.0, -0.7), "hush · descent briefing · sector 3\n\nno colour down here. only you.\nthe walls say it. the floor says it. the air says it.\n\nsubject '67' does not walk the corridors. it goes through them.\nwhen it calls a number, the maze obeys:\nthe black gates with that number sink, the others rise.\nthe way out is a different way every call.\n\nthe six and the seven are down here,\neach behind gates of its own number. bring them back.\nshout, and it comes for you.")
	var pts = scatter_points(6, sp, 14.0, 0.0)
	if pts.size() > 0:
		note(pts[0], "i counted. it calls every twenty seconds or so.\nsix, then seven, then six.\nit never calls the same number twice.\n\nwhen the picture goes negative, the walls are moving.\ndon't stand in a gate.\n\n- operative 07")
	if pts.size() > 1:
		note(pts[1], "it isn't in the maze.\nthe maze is in it.\n\nwe wrote on every wall so we would know which ones were real.\nit wrote back.\n\n- operative 04")
	# hush chalk on the floor: arrows to the way out (the gates on the way still move)
	for i in range(1, path.size() - 1, 2):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var m = ir_mark(_cell(a, 0.02), 0.0, "↑", 170)
		m.rotation = Vector3(-PI / 2, atan2(-(b.x - a.x), -(b.y - a.y)), 0)
	demo_path = []
	for c in path:
		demo_path.append(_cell(c))
	_wall_writing(["six seven", "it moves the walls", "6 7 6 7 6 7 6 7", "which number is it now", "don't stand in a gate", "it was never a joke", "the hands", "six"])
	uncanny_cfg = {"lights": lights, "watcher_ids": ["67"], "max_watchers": 1}
	ending_text = "you walked out between the six and the seven.\nbehind you the maze closed, one number at a time.\n\nhush has stopped asking what is down there.\nthe goggles keep recording anyway."


func enter(boot: bool) -> void:
	ambient("amb_67", -6.0, "amb_heavy", -18.0)
	Audio.set_reverb(0.6, 0.25)
	if player():
		player().step_sound = "step_concrete"
		player().step_volume = -16.0
		world.set_dust(0)
		_air_digits()
	if boot:
		boot_goggles_now()


## Somebody got here: it wakes up, and starts calling.
func start_wave() -> void:
	wave_started = true
	_next_call = CALL_FIRST
	if is_instance_valid(ss):
		ss.dormant = 6.0


func killer_id() -> String:
	return "67"


## Facing the way out of a cell (the first open side).
func _face_open(c: Vector2) -> float:
	for d in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
		if _passable(c, c + d):
			return atan2(-d.x, -d.y)
	return -PI * 0.5


# ------------------------------------------------------------------ gates
## Gates on passages: a few along the way out (so the way is shut and open by turns), one in
## front of each number's dead end (its own number), and more all over so the whole maze moves.
func _choose_gates(dist: Dictionary, path: Array, start: Vector2, far: Vector2) -> void:
	var on_path = {}
	for c in path:
		on_path[c] = true
	var cells = dist.keys()
	cells.sort()
	# the six and the seven: two dead ends off the way out, far from the start and apart
	var ends = []
	for c in cells:
		if on_path.has(c) or c == start:
			continue
		var opens = []
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if _passable(c, c + d):
				opens.append(c + d)
		if opens.size() == 1 and opens[0] != start and opens[0] != far:
			ends.append([dist[c], c, opens[0]])
	ends.sort_custom(self, "_desc0")
	for n in [6, 7]:
		for strict in [true, false]:
			if numerals.has(n):
				break
			for e in ends:
				var c: Vector2 = e[1]
				var p = _cell(c)
				var ok = true
				for m in numerals:
					if numerals[m].cell == c or (strict and numerals[m].pos.distance_to(p) < 16.0):
						ok = false
				if strict and p.distance_to(_cell(start)) < 18.0:
					ok = false
				if ok:
					numerals[n] = {"pos": p, "root": null, "cell": c}
					_add_gate(c, e[2], n, true)
					break
		if not numerals.has(n):
			# no dead end left at all (never seen): out in the open, far away
			var c: Vector2 = path[int(path.size() * (0.5 if n == 6 else 0.75))]
			numerals[n] = {"pos": _cell(c), "root": null, "cell": c}
	# gates along the way out, so the way is shut and open by turns
	var k = 4
	while k < path.size() - 3:
		_add_gate(path[k], path[k + 1], 6 if rng.randf() < 0.5 else 7)
		k += rng.randi_range(5, 8)
	# and more, everywhere, so the whole maze moves
	var passages = []
	for c in cells:
		for d in [Vector2(1, 0), Vector2(0, 1)]:
			var b: Vector2 = c + d
			if dist.has(b) and _passable(c, b) and not c in [start, far] and not b in [start, far]:
				passages.append([c, b])
	for i in range(passages.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var t = passages[i]
		passages[i] = passages[j]
		passages[j] = t
	var extra = 0
	for pr in passages:
		if extra >= 9:
			break
		if _add_gate(pr[0], pr[1], 6 if extra % 2 == 0 else 7):
			extra += 1


## A gate between cells a and b, unless one is too close already (force: the numbers' own gates).
func _add_gate(a: Vector2, b: Vector2, n: int, force := false) -> bool:
	var pos = (_cell(a) + _cell(b)) * 0.5
	for g in gates:
		if (g.a == a and g.b == b) or (g.a == b and g.b == a):
			return false
		if not force and g.pos.distance_to(pos) < C * 1.6:
			return false
	var o = 1.0 if n == layout else 0.0
	gates.append({"a": a, "b": b, "n": n, "pos": pos, "along_x": a.x == b.x, "open": o, "want": o, "root": null, "shape": null})
	return true


func _gate_size(g: Dictionary) -> Vector3:
	var l = C - T - 0.03
	return Vector3(l, H - 0.01, T * 0.86) if g.along_x else Vector3(T * 0.86, H - 0.01, l)


func _build_gates() -> void:
	for g in gates:
		var sb = StaticBody.new()
		sb.collision_layer = Geo.LAYER_WORLD
		world.add_child(sb)
		sb.global_transform.origin = g.pos + Vector3(0, H * 0.5, 0)
		var cs = CollisionShape.new()
		var bs = BoxShape.new()
		bs.extents = _gate_size(g) * 0.5
		cs.shape = bs
		sb.add_child(cs)
		cs.disabled = g.open > 0.5
		g.shape = cs


## Black slabs from the other side, white numbers on both faces; open, they lie flush in the
## floor as a black strip with the number on it.
func _gate_visuals() -> void:
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_texture = load("res://textures/gate_67.png")
	m.albedo_color = Color(0.62, 0.62, 0.62)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / 2.2
	_gate_mat = m
	_num_font = UI.font("hand", 200)
	for g in gates:
		var root = Spatial.new()
		geo.add_child(root)
		root.translation = g.pos + Vector3(0, -GATE_SINK * _ease(g.open), 0)
		var sz = _gate_size(g)
		Models.part(root, Models.box(sz), _gate_mat, Vector3(0, H * 0.5, 0))
		var nrm = Vector3(0, 0, 1) if g.along_x else Vector3(1, 0, 0)
		for s in [1.0, -1.0]:
			var l = _digit(root, str(g.n), 0.0066)
			l.translation = Vector3(0, 1.3, 0) + nrm * s * (sz.z if g.along_x else sz.x) * 0.5 + nrm * s * 0.006
			l.rotation.y = atan2(nrm.x * s, nrm.z * s)
			# smaller ones scrawled around it
			for i in 4:
				var sm = _digit(root, str(g.n), 0.0016 * rng.randf_range(0.8, 1.3))
				var along = Vector3(1, 0, 0) if g.along_x else Vector3(0, 0, 1)
				sm.translation = l.translation + along * rng.randf_range(-1.4, 1.4) + Vector3(0, rng.randf_range(-1.0, 1.1), 0) + nrm * s * 0.002
				sm.rotation = Vector3(0, l.rotation.y, rng.randf_range(-0.5, 0.5))
		# the number on its top: what you read in the floor when it is open
		var top = _digit(root, str(g.n), 0.0022)
		top.translation = Vector3(0, H + 0.004, 0)
		top.rotation = Vector3(-PI * 0.5, 0.0 if g.along_x else PI * 0.5, 0)
		Models.set_layers(root, 1)
		g.root = root


func _digit(parent: Spatial, text: String, ps: float) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.font = _num_font
	l.pixel_size = ps
	l.modulate = Color(0.85, 0.85, 0.85)
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	parent.add_child(l)
	return l


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Every machine: the gates follow the layout. Whoever stands where one rises is shoved out.
func _gates_step(delta: float) -> void:
	var pl = player()
	for g in gates:
		if g.open == g.want:
			continue
		g.open = move_toward(g.open, g.want, delta / GATE_DUR)
		if g.root:
			g.root.translation.y = g.pos.y - GATE_SINK * _ease(g.open)
		var solid = g.open < 0.5
		if g.shape and g.shape.disabled == solid:
			g.shape.set_deferred("disabled", not solid)
		if g.want < 0.5 and pl and not world.my_out and not world.dying:
			var p: Vector3 = pl.global_transform.origin
			var d = p - g.pos
			var perp = d.z if g.along_x else d.x
			var along = d.x if g.along_x else d.z
			var half = (T * 0.43 + 0.42)
			if abs(perp) < half and abs(along) < (C - T) * 0.5 + 0.2:
				var sgn = 1.0 if perp >= 0.0 else -1.0
				if g.along_x:
					p.z = g.pos.z + sgn * (half + 0.05)
				else:
					p.x = g.pos.x + sgn * (half + 0.05)
				pl.global_transform.origin = p
				pl.add_trauma(0.25)


## Every machine: the maze answers the call.
func _apply_layout(n: int) -> void:
	layout = n
	for g in gates:
		g.want = 1.0 if g.n == n else 0.0
	if not here():
		return
	# you hear the slabs nearest to you
	var pp = player().global_transform.origin
	var near = []
	for g in gates:
		near.append([g.pos.distance_to(pp), g.pos])
	near.sort_custom(self, "_asc0")
	for i in min(4, near.size()):
		if near[i][0] < 30.0:
			Audio.play_at("gate_move", near[i][1] + Vector3(0, 0.6, 0), world, 3.0, rand_range(0.9, 1.1), 30.0)


func _asc0(a, b) -> bool:
	return a[0] < b[0]


# ------------------------------------------------------------------ the six and the seven
## Standing numbers in their dead ends, cut from the same black as the gates, glowing white.
func _numeral_visuals() -> void:
	var f = UI.font("hand", 200)
	for n in numerals:
		var root = Spatial.new()
		geo.add_child(root)
		root.translation = numerals[n].pos
		root.rotation.y = rng.randf_range(-PI, PI)       # it turns slowly, floating (_process)
		for i in 10:
			var l = Label3D.new()
			l.text = str(n)
			l.font = f
			l.pixel_size = 0.0075
			l.modulate = Color(1, 1, 1) if i == 0 or i == 9 else Color(0.28, 0.28, 0.28)
			l.shaded = false
			l.double_sided = true
			l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			root.add_child(l)
			l.translation = Vector3(0, 1.05, -0.06 + i * 0.0135)
		var gl = Geo.omni(root, Vector3(0, 1.2, 0.6), Color(1, 1, 1), 0.6, 2.6)
		gl.light_cull_mask = Geo.VIS_ACTOR
		Models.set_layers(root, 1 | Geo.VIS_ACTOR)
		if player():
			Interactable.make(root, numerals[n].pos + Vector3(0, 1.0, 0), 0.8, "take the %s" % ("six" if n == 6 else "seven"), self, "_take_num", [n], false)
		numerals[n].root = root


func _take_num(n: int) -> void:
	if Net.active():
		Net.request("num", [n])
	else:
		on_request(1, "num", [n])


# ------------------------------------------------------------------ the air
## The empty space is written on too: sixes and sevens drifting in the air around you.
func _air_digits() -> void:
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	var p = CPUParticles.new()
	p.amount = [40, 90, 160][q]
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.local_coords = false
	p.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(8, 1.3, 8)
	p.gravity = Vector3(0, -0.02, 0)
	p.initial_velocity = 0.08
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.scale_amount = 1.0
	p.scale_amount_random = 0.7
	p.anim_offset_random = 1.0
	var qm = QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var m = SpatialMaterial.new()
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 2
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.flags_transparent = true
	m.flags_unshaded = true
	m.albedo_texture = load("res://textures/67_glyphs.png")
	m.albedo_color = Color(0.75, 0.75, 0.75, 0.55)
	qm.material = m
	p.mesh = qm
	p.add_to_group("dust")
	player().add_child(p)
	p.translation = Vector3(0, 1.3, 0)
	_digits = p


# ------------------------------------------------------------------ the calls
func _physics_process(delta: float) -> void:
	if ss == null or not is_instance_valid(ss):
		return
	_gates_step(delta)
	danger_bonus = 0.5 if ss.is_threat() else 0.0
	if not authority() or not wave_started:
		return
	var ts = world.targets(index)
	# somebody was taken: the count starts over
	if ts.size() < _alive_prev and not missions_done():
		_calls_ok = 0
		mission_set("calls", 0)
	_alive_prev = ts.size()
	if ts.empty():
		return
	_next_call -= delta
	if _next_call <= 0.0:
		_next_call = rng.randf_range(17.0, 23.0)
		var n = 13 - layout             # it never calls the same number twice
		_emit("call", [n, _relocate_spot(ts)])
		_calls_ok += 1
		mission_set("calls", _calls_ok, ts[randi() % ts.size()].id)


## Where it is after a call: a cell 12-24 m from the nearest operative (it is never far).
func _relocate_spot(ts: Array) -> Vector3:
	var best = ss.global_transform.origin
	var best_score = -1e9
	for k in 40:
		var c = Vector2(rng.randi() % CW, rng.randi() % CH)
		var p = _cell(c, 0.1)
		var near = 1e9
		for t in ts:
			near = min(near, Vector2(t.pos.x - p.x, t.pos.z - p.z).length())
		var score = -abs(near - 17.0)
		if near < 12.0:
			score -= 100.0
		if score > best_score:
			best_score = score
			best = p
	return best


## Every machine (server included).
func net_event(type: String, args: Array) -> void:
	var hud = world.hud if here() else null
	match type:
		"call":
			var n: int = args[0]
			if is_instance_valid(ss):
				ss.do_call(n)
			get_tree().create_timer(0.6).connect("timeout", self, "_apply_layout", [n])
			get_tree().create_timer(1.25).connect("timeout", self, "_relocate", [args[1]])
			if hud:
				_call_fx = 0.0
				hud.subtitle("67:   %s." % ("SIX" if n == 6 else "SEVEN"), 2.6)
				Audio.play("chant_%d" % n, -4.0)
				if is_instance_valid(ss):
					Audio.play_at("chant_%d" % n, ss.global_transform.origin + Vector3(0, 1.7, 0), world, 6.0, 1.0, 60.0)
		"heard":
			if hud:
				var who = "you" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0])
				hud.subtitle("67 heard %s.   it is coming, straight through the walls." % who, 3.5)
				Audio.play("whisper", -6.0, 0.6)
		"flash_woke":
			if hud:
				var who = "your" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0]) + "'s"
				hud.subtitle("%s flash woke it." % who, 3.0)
		"num":
			var n: int = args[0]
			if numerals.has(n) and numerals[n].root and is_instance_valid(numerals[n].root):
				numerals[n].root.queue_free()
			_num_taken[n] = args[1]
			if hud:
				var who = "you" if args[1] == Net.my_id() or not Net.active() else Net.pname(args[1])
				hud.subtitle("%s took the %s." % [who, "six" if n == 6 else "seven"], 3.0)
				Audio.play("pickup", -3.0, 0.7)


func _relocate(at: Vector3) -> void:
	if is_instance_valid(ss):
		ss.relocate(at)


## The negative flash of a call, and the drifting digits only while you are in here.
func _process(delta: float) -> void:
	if _digits and is_instance_valid(_digits):
		_digits.visible = here()
	if here():
		for n in numerals:
			var r = numerals[n].root
			if r and is_instance_valid(r):
				r.rotation.y += delta * 0.7
				r.translation.y = numerals[n].pos.y + 0.12 + sin(OS.get_ticks_msec() * 0.0015 + n) * 0.08
	if _call_fx < 0.0 or world.post == null:
		return
	_call_fx += delta
	var inv = smoothstep(0.35, 0.6, _call_fx) * (1.0 - smoothstep(0.9, 1.3, _call_fx))
	if not here() or world.dying:
		inv = 0.0
	world.post.set_shader_param("invert", inv)
	if _call_fx > 0.55 and _call_fx - delta <= 0.55 and here():
		player().add_trauma(0.35)
	if _call_fx > 1.4:
		_call_fx = -1.0
		world.post.set_shader_param("invert", 0.0)


## Server: requests from operatives in here.
func on_request(pid: int, type: String, args: Array) -> void:
	var t = world.target_by_id(pid)
	match type:
		"num":
			var n = int(args[0]) if args.size() > 0 else -1
			if not numerals.has(n) or _num_taken.has(n) or t == null or t.pos.distance_to(numerals[n].pos) > 2.8:
				return
			_num_taken[n] = pid
			_emit("num", [n, pid])
			mission_set("six" if n == 6 else "seven", 1, pid)
		"photo":
			if args.empty() or str(args[0]) != "67" or not is_instance_valid(ss):
				return
			if args.size() > 1:
				mission_set("portrait", max(mission_progress("portrait"), float(args[1])), pid)
			if t and t.pos.distance_to(ss.global_transform.origin) < 10.0 and not ss.is_threat() and ss.dormant <= 0.0:
				ss.chase_id = pid
				ss.set_state(SixSevenAI.S.CHASE)
				ss.chase_id = pid
				_emit("flash_woke", [pid])


## Server: somebody shouted. It hears everything.
func on_shout(pid: int) -> void:
	if not is_instance_valid(ss) or ss.dormant > 0.0:
		return
	ss.set_state(SixSevenAI.S.HUNT)
	ss.hunt_id = pid
	_emit("heard", [pid])
