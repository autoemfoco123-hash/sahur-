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
var writings = []         # the handwritten lines on the walls
var ink_light = {}        # the wall lighting opts (light_tint, exposure, ambient) the ink must match
var _ink_jobs = []
var _ink_queued = false
var tapes = []            # where the lost hush tapes lie (the same on every machine)
var _tape_nodes = {}
var _tape_taken = {}
var _tape_t = 0.0
var streak = 0            # calls answered in a row
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
	chalk = Color(0.15, 0.14, 0.11, 0.95)   # dark marker reads on the pale yellow walls
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
	add_mission("portrait", "a portrait of him, 85+", 85, "best")
	add_mission("streak", "answer him 3 calls in a row", 3)
	add_mission("tapes", "recover the 4 lost hush tapes", 4)
	_place_tapes(dist, start, far)
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
	# the exit is the sliding door in the east wall (world.gd): the key rooms are behind it
	if world.headless:
		# dedicated server: collision, navigation and rules only, nothing to draw
		spawn_player(_cell(start) + Vector3(0, 0.2, 0), -PI * 0.75)
		_arrival(start)
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
	lxz.append(Vector2(origin.x + size.x - 1.0, exit_z))     # a lamp right in front of the door
	bake.build(Rect2(o2() + Vector2(-1.6, -1.6), size + Vector2(3.2, 3.2)), lxz, walls2d)
	om.commit(geo, bake.office_mats(H, world.env))
	for lp in lamp_pos:
		lights.append(Geo.lamp_light(world, lp, bake, rng.randf_range(1.5, 1.9)))
	# Player
	var sp = _cell(start)
	spawn_player(sp + Vector3(0, 0.2, 0), -PI * 0.75)
	_arrival(start)
	note(sp + Vector3(0.7, 0.0, -0.7), "hush · descent briefing · operative 03\n\nyou are below the feed now. this is the rot.\nthe nv-7 goggles are bolted to your skull. they do not come off.\nnaked eyes don't work down here. we tried.\n\nsector 0 is held by subject 'tung'. he calls three times.\nanswer him: shout sahur (q) before the third call ends.\nstay quiet, and he comes looking for the quiet one.\n\nwe do not speak of it. we watch it.")
	var pts = scatter_points(6, sp, 14.0, 0.0)
	if pts.size() > 0:
		note(pts[0], "do not shout when he isn't calling.\nhe hates being called for nothing.\ni learned that the hard way.\n\nall the lights are on. all of them. all the time.\nthe carpet is wet and nobody knows why.\n\n- operative 02")
	if pts.size() > 1:
		note(pts[1], "hush · incident log · operative 01\n\noperative 01 pried his goggles off at 03:00:41.\nthe feed shows him standing still for six hours.\nsmiling.\n\nthe goggles kept recording on the floor.\nthe last frame is a wooden face.\n\n(operative 01 was not recovered)")
	# Tung
	tung = enemy(TungAI, "tung", _tung_spawn(dist, far, sp) + Vector3(0, 0.1, 0))
	for i in tapes.size():
		_tape_visual(i)
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


## Size, navigation, floor/ceiling colliders and the merged floor/ceiling meshes.
## Floors stop at the outer walls' centre lines, so two sectors wall to wall never overlap.
func _shell(size: Vector2):
	extent = size
	make_nav(Vector2(-1, -1), size + Vector2(1, 1), 0.5)
	nav.margin = 0.3
	# One collider each for floor and ceiling; what you see is the merged, light-baked office mesh.
	Geo.solid(world, Vector3(size.x + 2, 0.4, size.y + 2), origin + Vector3(size.x * 0.5, -0.2, size.y * 0.5), null, null, false)
	Geo.solid(world, Vector3(size.x + 2, 0.4, size.y + 2), origin + Vector3(size.x * 0.5, H + 0.2, size.y * 0.5), null, null, false)
	var om = OfficeMesh.new()
	var a = o2() - Vector2(T, T) * 0.5
	var b = o2() + size + Vector2(T, T) * 0.5
	om.plane("floor", a, b, 0.0, true)
	om.plane("ceiling", a, b, H, false)
	_layout()
	return om


## The run starts in the corner; later sectors start at the door you came in through.
func _start_cell() -> Vector2:
	if not has_entry:
		return Vector2(0, 0)
	return Vector2(0, clamp(floor((entry_z - origin.z) / C), 0, CH - 1))


## The exit: the cell on the east edge that is furthest to walk to.
func _exit_cell(dist: Dictionary) -> Vector2:
	var best = Vector2(CW - 1, CH - 1)
	var bd = -1
	var cells = dist.keys()
	cells.sort()
	for c in cells:
		if int(c.x) == CW - 1 and dist[c] > bd:
			bd = dist[c]
			best = c
	return best


## Where you stand after walking in through the door (and where the dead come back).
func _arrival(start: Vector2) -> void:
	if has_entry:
		arrive_pos = Vector3(origin.x + 1.1, 0.2, entry_z)
		arrive_yaw = -PI * 0.5


# ------------------------------------------------------------------ the lost tapes
## Four tapes, deep in the dead ends furthest from the start, spread out.
func _place_tapes(dist: Dictionary, start: Vector2, far: Vector2) -> void:
	var cells = dist.keys()
	cells.sort()
	var cand = []
	for c in cells:
		if c == start or c == far:
			continue
		var opens = []
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if _passable(c, c + d):
				opens.append(d)
		# dead ends first (one way in), then simply the furthest cells
		var score = dist[c] + (1000 if opens.size() == 1 else 0)
		var back = opens[0] if opens.size() == 1 else Vector2.ZERO
		cand.append([score, c, back])
	cand.sort_custom(self, "_desc0")
	for e in cand:
		if tapes.size() >= 4:
			break
		var p: Vector3 = _cell(e[1]) - Vector3(e[2].x, 0, e[2].y) * 1.3
		var ok = _cell(e[1]).distance_to(_cell(start)) > 16.0
		for q in tapes:
			if q.distance_to(p) < 12.0:
				ok = false
		if ok:
			tapes.append(p)


func _desc0(a, b) -> bool:
	return a[0] > b[0]


func _tape_visual(i: int) -> void:
	var root = Spatial.new()
	geo.add_child(root)
	root.global_transform.origin = tapes[i]
	root.rotation.y = rng.randf_range(-PI, PI)
	var shell = Mats.std(Color(0.11, 0.11, 0.12), 0.55, 0.2)
	Models.part(root, Models.box(Vector3(0.22, 0.05, 0.14)), shell, Vector3(0, 0.025, 0))
	Models.part(root, Models.box(Vector3(0.13, 0.004, 0.05)), Mats.std(Color(0.85, 0.8, 0.62), 0.8), Vector3(-0.02, 0.052, -0.02))
	for x in [-0.05, 0.05]:
		Models.part(root, Models.box(Vector3(0.035, 0.006, 0.035)), Mats.std(Color(0.3, 0.3, 0.32), 0.4, 0.6), Vector3(x, 0.052, 0.035))
	var led = Models.part(root, Models.box(Vector3(0.016, 0.012, 0.016)), Mats.unshaded(Color(1.0, 0.08, 0.04)), Vector3(0.085, 0.056, 0.05))
	led.name = "led"
	var l = Geo.omni(root, Vector3(0, 0.3, 0), Color(1.0, 0.25, 0.15), 0.7, 1.8)
	l.light_cull_mask = Geo.VIS_ACTOR
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	if player():
		Interactable.make(root, tapes[i] + Vector3(0, 0.15, 0), 0.45, "take the tape", self, "_take_tape", [i], false)
	_tape_nodes[i] = root


func _take_tape(i: int) -> void:
	if Net.active():
		Net.request("tape", [i])
	else:
		on_request(1, "tape", [i])


## The tapes blink and beep quietly: you can hunt for them by ear.
func _process(delta: float) -> void:
	if _tape_nodes.empty() or not here():
		return
	_tape_t -= delta
	if _tape_t > 0.0:
		return
	_tape_t = 1.6
	var pp = player().global_transform.origin
	for i in _tape_nodes:
		var n = _tape_nodes[i]
		if not is_instance_valid(n):
			continue
		var led = n.get_node_or_null("led")
		if led:
			led.visible = not led.visible
		if n.global_transform.origin.distance_to(pp) < 16.0:
			Audio.play_at("tick", n.global_transform.origin + Vector3(0, 0.1, 0), world, -4.0, 1.7, 16.0)


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
	# west and east: whole, or with a doorway for the sliding doors
	segs += _door_wall(0.0, d, entry_z - origin.z if has_entry else -1.0)
	segs += _door_wall(w, d, exit_z - origin.z)
	for x in range(1, CW):
		for y in range(1, CH):
			var touching = walls_h.has(Vector2(x - 1, y - 1)) or walls_h.has(Vector2(x, y - 1)) or walls_v.has(Vector2(x - 1, y - 1)) or walls_v.has(Vector2(x - 1, y))
			if not touching and rng.randf() < pillar_ratio:
				segs.append([Vector3(x * C, H * 0.5, y * C), Vector3(0.95, H, 0.95)])
	for sgm in segs:
		sgm[0] += origin
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		var listed = sgm.size() < 3      # a lintel over a door is not a wall to write on
		var cs = CollisionShape.new()
		var sh = BoxShape.new()
		sh.extents = sz * 0.5
		cs.shape = sh
		sb.add_child(cs)
		cs.translation = pos
		nav.block_box(pos, sz)
		om.box_sides("wall", pos, sz)
		if listed:
			_wall_list.append(sgm)
	# nothing walks into a doorway on its own
	var doorways = [Vector2(origin.x + w, exit_z)]
	if has_entry:
		doorways.append(Vector2(origin.x, entry_z))
	for dw in doorways:
		nav.block_box(Vector3(dw.x, 0, dw.y), Vector3(T + 0.6, 2.0, DOOR_W + 0.3))


## A boundary wall at x (relative) along the whole z range; with a doorway at dz if dz >= 0.
func _door_wall(x: float, d: float, dz: float) -> Array:
	if dz < 0.0:
		return [[Vector3(x, H * 0.5, d * 0.5), Vector3(T, H, d + T)]]
	var z0 = -T * 0.5
	var z1 = d + T * 0.5
	var a = dz - DOOR_W * 0.5
	var b = dz + DOOR_W * 0.5
	return [
		[Vector3(x, H * 0.5, (z0 + a) * 0.5), Vector3(T, H, a - z0)],
		[Vector3(x, H * 0.5, (b + z1) * 0.5), Vector3(T, H, z1 - b)],
		[Vector3(x, (DOOR_H + H) * 0.5, dz), Vector3(T, H - DOOR_H, DOOR_W), "lintel"],
	]


## Writing on the walls (only the goggles see it), by hand: each line on one cell's stretch of
## wall, between two corners, wrapped / shrunk until it fits with a margin, every line a little
## crooked and off, like someone wrote it in a hurry.
func _wall_writing(lines: Array) -> void:
	var picks = _wall_list.duplicate()
	picks.shuffle()
	var placed = 0
	var font = _hand_font()
	for sgm in picks:
		if placed >= lines.size():
			break
		var pos: Vector3 = sgm[0]
		var sz: Vector3 = sgm[1]
		var along_x = sz.x > sz.z
		var length = sz.x if along_x else sz.z
		if length < C:
			continue          # pillars and short stubs
		# the stretches of this wall that lie between two grid corners (cell centres)
		var a0 = (pos.x if along_x else pos.z) - length * 0.5
		var a1 = a0 + length
		var base = origin.x if along_x else origin.z
		var spots = []
		for k in (CW if along_x else CH):
			var c = base + (k + 0.5) * C
			if c - C * 0.5 >= a0 - 0.01 and c + C * 0.5 <= a1 + 0.01:
				spots.append(c)
		if spots.empty():
			continue
		var c_al: float = spots[rng.randi() % spots.size()]
		var normal = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
		if rng.randf() < 0.5:
			normal = -normal
		var at = Vector3(c_al, 1.6, pos.z) if along_x else Vector3(pos.x, 1.6, c_al)
		at += normal * (min(sz.x, sz.z) * 0.5 + 0.012)
		var rel = at - origin
		if rel.x < 0.5 or rel.z < 0.5 or rel.x > CW * C - 0.5 or rel.z > CH * C - 0.5:
			continue
		var taken = false
		for b in wall_blockers:
			if Vector2(b.x - at.x, b.z - at.z).length() < (C - T) * 0.5 + 0.7:
				taken = true
		if taken:
			continue
		var fit = _fit_text(str(lines[placed]).to_lower(), font, C - T - 0.9, 0.0064 * rng.randf_range(0.9, 1.08))
		_scrawl(at, atan2(normal.x, normal.z), fit[0].split("\n"), fit[1], font)
		placed += 1


## Real handwriting (Nothing You Could Do, OFL), the stroke thickened a touch like a felt-tip pen.
func _hand_font() -> DynamicFont:
	if Game.cache.has("font_hand_wall"):
		return Game.cache["font_hand_wall"]
	var f: DynamicFont = UI.font("hand", 64).duplicate()
	f.outline_size = 1
	f.outline_color = Color(1, 1, 1)
	Game.cache["font_hand_wall"] = f
	return f


## One handwritten line at a time: crooked, shifted, the second line never quite under the first.
func _scrawl(at: Vector3, rot_y: float, text_lines: Array, ps: float, font: DynamicFont) -> void:
	var lh = font.get_height() * ps * 0.82
	var n = text_lines.size()
	var right = Vector3(cos(rot_y), 0, -sin(rot_y))
	var tilt = rng.randf_range(-0.06, 0.06)
	for i in n:
		var p = at + Vector3(0, (n - 1) * lh * 0.5 - i * lh, 0) + right * rng.randf_range(-0.09, 0.09)
		_ink_line(p, rot_y, tilt + rng.randf_range(-0.035, 0.035), text_lines[i], ps * rng.randf_range(0.95, 1.05), font)
	if not _ink_queued:
		_ink_queued = true
		call_deferred("_ink_bake")


## A line of ink on the wall: rendered once into a texture, then lit by the wall's own baked
## light (wall_ink.shader), so it is exactly as dark or as bright as the wall around it.
func _ink_line(at: Vector3, rot_y: float, roll: float, text: String, ps: float, font: DynamicFont) -> void:
	var ts: Vector2 = font.get_string_size(text) + Vector2(20, 16)
	var w = 1
	while w < ts.x:
		w *= 2
	var h = 1
	while h < ts.y:
		h *= 2
	var vp = Viewport.new()
	vp.size = Vector2(w, h)
	vp.transparent_bg = true
	vp.usage = Viewport.USAGE_2D
	vp.disable_3d = true
	vp.render_target_v_flip = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	var lb = Label.new()
	lb.text = text
	lb.add_font_override("font", font)
	lb.add_color_override("font_color", Color(1, 1, 1))
	lb.add_color_override("font_outline_modulate", Color(1, 1, 1))
	lb.rect_position = (Vector2(w, h) - font.get_string_size(text)) * 0.5
	vp.add_child(lb)
	geo.add_child(vp)
	var q = QuadMesh.new()
	q.size = Vector2(w, h) * ps
	var mi = MeshInstance.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var m = ShaderMaterial.new()
	m.shader = preload("res://scripts/wall_ink.shader")
	m.set_shader_param("ink", chalk)
	m.set_shader_param("wall_h", H)
	for k in ink_light:
		m.set_shader_param(k, ink_light[k])
	if bake:
		bake.register(m)
	mi.material_override = m
	mi.layers = 2
	mi.visible = false
	geo.add_child(mi)
	mi.global_transform.origin = at
	mi.rotation = Vector3(0, rot_y, roll)
	writings.append(mi)
	_ink_jobs.append([vp, mi, m])


## A few frames later the lines are drawn: keep them as mipmapped textures, drop the viewports.
func _ink_bake() -> void:
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	for j in _ink_jobs:
		var vp: Viewport = j[0]
		if not is_instance_valid(vp):
			continue
		var img = vp.get_texture().get_data()
		var tex = ImageTexture.new()
		tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		j[2].set_shader_param("text_tex", tex)
		j[1].visible = true
		vp.queue_free()
	_ink_jobs.clear()


## Wrap words into lines no wider than max_w metres; shrink if one word alone is too wide.
func _fit_text(text: String, font: Font, max_w: float, ps: float) -> Array:
	var out = []
	var cur = ""
	for w in text.split(" "):
		var t = w if cur == "" else cur + " " + w
		if cur != "" and font.get_string_size(t).x * ps > max_w:
			out.append(cur)
			cur = w
		else:
			cur = t
	out.append(cur)
	var widest = 0.0
	for l in out:
		widest = max(widest, font.get_string_size(l).x * ps)
	if widest > max_w:
		ps *= max_w / widest
	return [PoolStringArray(out).join("\n"), ps]


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
				streak = 0
				mission_set("streak", 0)
				# "he is coming for the quiet one": somebody who stayed quiet
				var ts = world.targets(index)
				tung.hunt_id = ts[randi() % ts.size()].id
				_emit("unanswered", [tung.hunt_id])
				tung.set_state(TungAI.S.HUNT)
				tung.hunt_id = tung.hunt_id
			_emit("call_end", [])


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
		"tape":
			var i: int = args[0]
			if _tape_nodes.has(i) and is_instance_valid(_tape_nodes[i]):
				_tape_nodes[i].queue_free()
			_tape_nodes.erase(i)
			if hud:
				var who = "you" if args[1] == Net.my_id() or not Net.active() else Net.pname(args[1])
				hud.subtitle("%s recovered a tape." % who, 2.5)
				Audio.play("pickup", -3.0, 0.9)
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
	if type == "tape":
		var i = int(args[0]) if args.size() > 0 else -1
		var t = world.target_by_id(pid)
		if i < 0 or i >= tapes.size() or _tape_taken.has(i) or t == null or t.pos.distance_to(tapes[i]) > 2.8:
			return
		_tape_taken[i] = true
		_emit("tape", [i, pid])
		mission_set("tapes", _tape_taken.size(), pid)
		return
	if type != "photo" or tung == null or args.empty() or str(args[0]) != "tung":
		return
	if args.size() > 1:
		mission_set("portrait", max(mission_progress("portrait"), float(args[1])), pid)
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
		streak += 1
		mission_set("streak", streak, pid)
	elif not calling:
		streak = 0
		mission_set("streak", 0)
		_emit("wrong_shout", [pid])
		tung.set_state(TungAI.S.HUNT)
		tung.hunt_id = pid
