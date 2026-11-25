extends LevelBase
## LEVEL 0 — THE SAHUR HALLWAYS.
## Endless open-plan office space: mono-yellow walls, damp carpet, a drop ceiling of square lights.
## Answer the call. Never shout when he isn't calling.

const TungAI := preload("res://scripts/enemies/tung.gd")
const C := 4.0      # cell size
const H := 2.75     # ceiling height
const T := 0.28     # wall thickness
const CW := 12
const CH := 12

var tung: TungAI
var call_timer := 14.0
var calling := false
var call_t := 0.0
var answered := false
var lights := []
var demo_path := []
var walls_h := {}   # Vector2i(x, y) -> wall between (x,y) and (x,y+1)
var walls_v := {}   # Vector2i(x, y) -> wall between (x,y) and (x+1,y)


func build() -> void:
	world.setup_env({
		"ambient": Color(0.92, 0.88, 0.62), "ambient_energy": 0.3,
		"fog_color": Color(0.62, 0.6, 0.42), "fog_depth": Vector2(8.0, 60.0), "fog_curve": 1.7, "fog_density": 0.45,
		"vol": 0.016, "vol_albedo": Color(1.0, 0.97, 0.85), "vol_length": 40.0,
		"tint": Vector3(1.02, 1.0, 0.88), "auto_exposure": 0.0, "contrast": 1.04, "saturation": 0.86, "glow": 0.9,
		"ssil": true,
	})
	boot_goggles = true
	ambient("amb_hall", -9.0, "amb_heavy", -11.0)
	Audio.set_reverb(0.75, 0.28)
	player().step_sound = "step_grass"
	player().step_volume = -16.0
	player().flashlight_on = false
	Geo.dust(player(), 700)
	var size := Vector2(CW * C, CH * C)
	make_nav(Vector2(-1, -1), size + Vector2(1, 1), 0.5)
	world.nav.margin = 0.3
	var wall_m := Mats.surf("plain", Color(0.83, 0.79, 0.5), Color(0.74, 0.7, 0.43), {"wainscot": 0.09, "wood_a": Color(0.26, 0.2, 0.12), "wood_b": Color(0.16, 0.12, 0.07), "grime": 0.35, "stains": 0.35, "roughness": 0.9})
	var carpet := Mats.surf("carpet", Color(0.5, 0.45, 0.3), Color(0.33, 0.29, 0.19), {"grime": 0.2, "stains": 0.55, "roughness": 1.0, "bump": 0.6})
	var ceil := Mats.surf("ceiling", Color(0.86, 0.84, 0.72), Color(0.7, 0.69, 0.62), {"grime": 0.15, "stains": 0.45, "roughness": 0.95})
	# One big collider each, but the visible floor and ceiling are per-room tiles:
	# phones only light each object with a handful of lamps.
	Geo.solid(world, Vector3(size.x + 2, 0.4, size.y + 2), Vector3(size.x * 0.5, -0.2, size.y * 0.5), carpet, null, 0.0, false)
	Geo.solid(world, Vector3(size.x + 2, 0.4, size.y + 2), Vector3(size.x * 0.5, H + 0.2, size.y * 0.5), ceil, null, 0.0, false)
	var fmesh := Models.box(Vector3(C, 0.4, C))
	for x in CW:
		for y in CH:
			var f := MeshInstance3D.new()
			f.mesh = fmesh
			f.material_override = carpet
			world.add_child(f)
			f.position = Vector3((x + 0.5) * C, -0.2, (y + 0.5) * C)
			var cl := MeshInstance3D.new()
			cl.mesh = fmesh
			cl.material_override = ceil
			world.add_child(cl)
			cl.position = Vector3((x + 0.5) * C, H + 0.2, (y + 0.5) * C)
	_layout()
	_build_walls(wall_m)
	# Graph search over open cell edges
	var start := Vector2i(0, 0)
	var info := _bfs(start)
	var dist: Dictionary = info.dist
	var par: Dictionary = info.parent
	var far := start
	for c in dist:
		if dist[c] > dist[far]:
			far = c
	# Square ceiling panels: soft, even, everywhere.
	var cells := dist.keys()
	cells.shuffle()
	var n := 0
	for c in cells:
		if c == start or c == far or rng.randf() < 0.5:
			var cp := _cell(c, H - 0.01) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)).snapped(Vector3(0.6, 1, 0.6))
			var l := Geo.square_panel(world, cp, rng.randf_range(1.5, 1.9), n < 10)
			lights.append(l)
			n += 1
	# Exit: a plain door standing in the farthest room
	var back: Vector2i = par.get(far, far)
	var dirv := Vector3(back.x - far.x, 0, back.y - far.y)
	Geo.exit_door(world, _cell(far) - dirv * 1.2, atan2(dirv.x, dirv.z), world.complete, Color(1.0, 0.97, 0.88), "exit")
	# Player
	var sp := _cell(start)
	spawn_player(sp + Vector3(0, 0.2, 0), -PI * 0.75)
	note(sp + Vector3(0.7, 0.0, -0.7), "hush · descent briefing · operative 03\n\nyou are below the feed now. this is the rot.\nthe nv-7 goggles are bolted to your skull. they do not come off.\nnaked eyes don't work down here. we tried.\n\nsector 0 is held by subject 'tung'. he calls three times.\nanswer him (q). shout sahur before the third call ends.\nstay quiet, and he comes looking for the quiet one.\n\nwe do not speak of it. we watch it.")
	var pts := scatter_points(6, sp, 14.0, 0.0)
	if pts.size() > 0:
		note(pts[0], "do not shout when he isn't calling.\nhe hates being called for nothing.\ni learned that the hard way.\n\nall the lights are on. all of them. all the time.\nthe carpet is wet and nobody knows why.\n\n- operative 02")
	if pts.size() > 1:
		note(pts[1], "hush · incident log · operative 01\n\noperative 01 pried his goggles off at 03:00:41.\nthe feed shows him standing still for six hours.\nsmiling.\n\nthe goggles kept recording on the floor.\nthe last frame is a wooden face.\n\n(operative 01 was not recovered)")
	# Tung, somewhere in the middle of it all
	var tp := sp
	var best := 1 << 30
	for c in dist:
		var dd: int = absi(dist[c] - dist[far] / 2)
		if dd < best and _cell(c).distance_to(sp) > 20.0:
			best = dd
			tp = _cell(c)
	tung = enemy(TungAI, "tung", tp + Vector3(0, 0.1, 0)) as TungAI
	player().shouted.connect(_on_shout)
	# hush chalk on the carpet: arrows from the start to the exit
	var path := [far]
	while path[-1] != start and par.has(path[-1]):
		path.append(par[path[-1]])
	path.reverse()
	for i in range(1, path.size() - 1, 2):
		var a: Vector2i = path[i]
		var b: Vector2i = path[i + 1]
		var m := ir_mark(_cell(a, 0.02), 0.0, "↑", 170)
		m.rotation = Vector3(-PI / 2, atan2(-(b.x - a.x), -(b.y - a.y)), 0)
	demo_path = []
	for c in path:
		demo_path.append(_cell(c))
	_wall_writing(["he is listening", "answer once", "don't look up", "we watched. we did nothing", "03 you are not the first", "behind you"])
	world.uncanny = Uncanny.new().setup(world, {"lights": lights, "watcher_ids": ["tung"], "max_watchers": 2})
	world.uncanny.add_tposers(1)
	# Goggles boot: black, then the world arrives through them, and never leaves.
	get_tree().create_timer(1.0).timeout.connect(func(): world.hud.subtitle("hush nv-7 · booting…", 1.6))
	get_tree().create_timer(2.4).timeout.connect(func():
		if not world.dying:
			player().set_visor(true)
			world.hud.fade(0.0, 0.5)
			world.hud.subtitle("goggles locked · gyro calibrated · auto gain", 2.5))


# ------------------------------------------------------------------ layout
func _cell(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3((c.x + 0.5) * C, y, (c.y + 0.5) * C)


## Perfect maze, then knock out half the remaining walls: open-plan, endless, still lost.
func _layout() -> void:
	for x in CW:
		for y in CH:
			if y < CH - 1:
				walls_h[Vector2i(x, y)] = true
			if x < CW - 1:
				walls_v[Vector2i(x, y)] = true
	var stack := [Vector2i(0, 0)]
	var seen := {Vector2i(0, 0): true}
	while stack.size() > 0:
		var c: Vector2i = stack[-1]
		var opts := []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if nb.x >= 0 and nb.y >= 0 and nb.x < CW and nb.y < CH and not seen.has(nb):
				opts.append(nb)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nx: Vector2i = opts[rng.randi() % opts.size()]
		seen[nx] = true
		_open(c, nx)
		stack.append(nx)
	for k in walls_h.keys():
		if rng.randf() < 0.5:
			walls_h.erase(k)
	for k in walls_v.keys():
		if rng.randf() < 0.5:
			walls_v.erase(k)


func _open(a: Vector2i, b: Vector2i) -> void:
	if a.x == b.x:
		walls_h.erase(Vector2i(a.x, mini(a.y, b.y)))
	else:
		walls_v.erase(Vector2i(mini(a.x, b.x), a.y))


func _passable(a: Vector2i, b: Vector2i) -> bool:
	if b.x < 0 or b.y < 0 or b.x >= CW or b.y >= CH:
		return false
	if a.x == b.x:
		return not walls_h.has(Vector2i(a.x, mini(a.y, b.y)))
	return not walls_v.has(Vector2i(mini(a.x, b.x), a.y))


func _bfs(start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var parent := {}
	var q := [start]
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if _passable(c, nb) and not dist.has(nb):
				dist[nb] = dist[c] + 1
				parent[nb] = c
				q.append(nb)
	return {"dist": dist, "parent": parent}


func _build_walls(mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Geo.LAYER_WORLD
	world.add_child(sb)
	var xf := []
	var segs := []
	# interior walls
	for k in walls_h:
		segs.append([Vector3((k.x + 0.5) * C, H * 0.5, (k.y + 1) * C), Vector3(C + T, H, T)])
	for k in walls_v:
		segs.append([Vector3((k.x + 1) * C, H * 0.5, (k.y + 0.5) * C), Vector3(T, H, C + T)])
	# outer shell
	var w := CW * C
	var d := CH * C
	segs.append([Vector3(w * 0.5, H * 0.5, 0), Vector3(w + T, H, T)])
	segs.append([Vector3(w * 0.5, H * 0.5, d), Vector3(w + T, H, T)])
	segs.append([Vector3(0, H * 0.5, d * 0.5), Vector3(T, H, d + T)])
	segs.append([Vector3(w, H * 0.5, d * 0.5), Vector3(T, H, d + T)])
	# thick pillars at some free corners
	for x in range(1, CW):
		for y in range(1, CH):
			var touching := walls_h.has(Vector2i(x - 1, y - 1)) or walls_h.has(Vector2i(x, y - 1)) or walls_v.has(Vector2i(x - 1, y - 1)) or walls_v.has(Vector2i(x - 1, y))
			if not touching and rng.randf() < 0.45:
				segs.append([Vector3(x * C, H * 0.5, y * C), Vector3(0.95, H, 0.95)])
	for sgm in segs:
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = sz
		cs.shape = sh
		sb.add_child(cs)
		cs.position = pos
		world.nav.block_box(pos, sz)
		var mi := MeshInstance3D.new()
		mi.mesh = Models.box(sz)
		mi.material_override = mat
		world.add_child(mi)
		mi.position = pos
		_wall_list.append(sgm)


var _wall_list := []


func _wall_writing(lines: Array) -> void:
	var picks := _wall_list.duplicate()
	picks.shuffle()
	var placed := 0
	for sgm in picks:
		if placed >= lines.size():
			break
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		if sz.x < 1.5 and sz.z < 1.5:
			continue
		var normal := Vector3(0, 0, 1) if sz.x > sz.z else Vector3(1, 0, 0)
		if rng.randf() < 0.5:
			normal = -normal
		var at := pos + normal * (minf(sz.x, sz.z) * 0.5 + 0.02)
		at.y = 1.55
		if at.x < 0.5 or at.z < 0.5 or at.x > CW * C - 0.5 or at.z > CH * C - 0.5:
			continue
		ir_mark(at, atan2(normal.x, normal.z), lines[placed], 64)
		placed += 1


# ------------------------------------------------------------------ the call
func _physics_process(delta: float) -> void:
	if world.dying:
		return
	# A tube somewhere stutters, then catches again.
	if randf() < 0.02 and lights.size() > 0:
		var l: SpotLight3D = lights[randi() % lights.size()]
		l.visible = false
		get_tree().create_timer(randf_range(0.04, 0.25)).timeout.connect(func(): l.visible = true)
	if not calling:
		call_timer -= delta
		if call_timer <= 0.0:
			calling = true
			answered = false
			call_t = 0.0
	else:
		var prev := call_t
		call_t += delta
		for k in 3:
			var t0 := k * 2.6
			if prev < t0 and call_t >= t0:
				_knock(k)
		if call_t > 3 * 2.6 + 0.8:
			calling = false
			call_timer = rng.randf_range(20.0, 30.0)
			if not answered:
				world.hud.subtitle("he heard nothing.  he is coming for the quiet one.", 4.0)
				Audio.play("tung", -2.0, 0.5)
				tung.set_state(TungAI.S.HUNT)
	danger_bonus = 0.55 if tung.is_threat() else (0.25 if calling and not answered else 0.0)


func _knock(k: int) -> void:
	if answered:
		return
	for i in 3:
		get_tree().create_timer(i * 0.32).timeout.connect(func():
			Audio.play_at("tung", tung.global_position + Vector3(0, 2, 0), world, 6.0, 0.85, 200.0)
			Audio.play("tung", -16.0, 0.8))
	get_tree().create_timer(1.1).timeout.connect(func():
		if not answered:
			Audio.play_at("sahur_low", tung.global_position + Vector3(0, 2, 0), world, 6.0, 1.0, 200.0)
			Audio.play("sahur_low", -14.0))
	world.hud.subtitle("tung  tung  tung …  sahur      (%d/3)" % (k + 1), 2.4)


func _on_shout() -> void:
	if calling and not answered:
		answered = true
		world.hud.subtitle("you answered.  he walks past you.", 3.0)
		tung.set_state(TungAI.S.PASSIVE)
	elif not calling:
		world.hud.subtitle("you shouted when he wasn't calling.   he heard you.", 3.0)
		tung.set_state(TungAI.S.HUNT)
