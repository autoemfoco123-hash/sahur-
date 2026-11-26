extends LevelBase
## LEVEL 2 — BLISS. (Godot 3)
## Behind the key rooms' last door: a green field under a blue sky, rolling hills, a breeze in
## the grass. Nothing hunts you here. In the middle of the field, on a little table, the Khaby
## Lame Mechanism turns its hands over and over. Missions done, talk to it (e): a short
## conversation, and then the ground splits down the middle, the sky goes red, and everyone
## falls into the void... which carries you out.
## The field is two halves of terrain that meet along a jagged line right under the mechanism:
## that is where it tears.

const KhabyAI := preload("res://scripts/enemies/khaby.gd")
const L := 170.0          # field length along x (from the wall with the door)
const HW := 90.0          # half width along z, around the door
const GRID := 2.0
const T := 0.28
const WALL_H := 5.0
const KHABY := Vector2(46.0, 3.0)    # (u, v) of the mechanism
const CUTSCENE := 27.0               # the conversation, in seconds
const CRACK := 8.5                   # from the first crack to the void letting go
const END := CUTSCENE + CRACK

# the conversation: [time, speaker, line, mechanism pose]
# speaker: "a" (who talked to it), "b" (another operative, or the radio), "m" (the mechanism), "r" (radio)
const LINES = [
	[0.4, "a", "...is that what i think it is?", 0.0],
	[3.6, "b", "the khaby lame mechanism. hush file zero. 'friendly. do not explain anything to it.'", 0.0],
	[8.4, "a", "hey. mechanism. how do we get out of here?", 0.0],
	[11.8, "m", "*turns both hands up, slowly. the obvious way.*", 1.0],
	[15.4, "b", "...he's saying there is no door.", 0.0],
	[18.6, "a", "then where do we—", 0.0],
	[20.4, "m", "*looks down at the grass between your feet. it's that simple.*", 1.0],
	[23.6, "r", "03. the ground under you is not reading as ground anymore.", 0.0],
	[25.9, "a", "...oh no.", 0.0],
]

var khaby
var sun: DirectionalLight
var halves = []           # [{root, body, sign}]
var _crack = []           # Vector2(u, v): the jagged line down the middle
var _fissure: Spatial
var zc = 24.0             # world z of the field's centre line (the door)
var beacons = []
var _beacon_nodes = {}
var _beacon_taken = {}
var _beacon_t = 0.0
var scene_t = -1.0        # >= 0: the conversation, then the crack, is playing
var _scene_a = -1
var _scene_b = -1
var _line = -1
var _phase = 0            # 0 talking · 1 cracking · 2 falling · 3 done
var _gather_t = 0.0
var _streaks: CPUParticles
var _ride = -1            # which half the local operative stands on while it pulls away
var _ride_prev = Vector3.ZERO


func build() -> void:
	env({
		"sky": "res://textures/sky_bliss.png", "sky_contribution": 0.55,
		"ambient": Color(0.78, 0.86, 1.0), "ambient_energy": 0.7 if Mats.potato() else 0.55,
		"fog_color": Color(0.7, 0.82, 0.96), "fog_begin": 18.0 if Mats.potato() else 70.0, "fog_end": 34.0 if Mats.potato() else 280.0, "fog_curve": 1.2,
		"tint": Vector3(1.0, 1.0, 1.0), "contrast": 1.04, "saturation": 1.1,
	})
	boot_goggles = true
	greeter = ""
	has_exit_door = false
	ending_text = "the ground opened and you fell.\n\nthe void carried you somewhere else.\nhush lost your signal in sector 2."
	zc = entry_z if has_entry else 24.0
	entry_z = zc
	exit_z = zc
	extent = Vector2(L, HW * 2.0)
	_crack_line()
	make_nav(Vector2(-1, zc - HW), Vector2(L, zc + HW), 2.0)
	# the missions (friendly, not easy): then talk to it
	add_mission("portrait", "a portrait of the mechanism, 95+", 95, "best")
	add_mission("beacons", "switch off the 4 hush beacons in the hills", 4)
	add_mission("gather", "every operative at the mechanism, together", 1, "")
	_place_beacons()
	var at = Vector3(origin.x + 1.6, 0.2, zc)
	spawn_player(at, -PI * 0.5)
	arrive_pos = at
	arrive_yaw = -PI * 0.5
	_build_terrain()
	_build_wall()
	_bounds()
	khaby = enemy(KhabyAI, "khaby", _wp(KHABY.x, KHABY.y) - Vector3(0, 0.04, 0), false)
	khaby.rotation.y = PI * 0.5           # facing the door
	khaby.pinned = true                   # a table on a hill does not slide down it
	if world.headless:
		return
	sun = DirectionalLight.new()
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-46, -125, 0)
	sun.directional_shadow_mode = DirectionalLight.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.visible = false
	world.add_child(sun)
	_build_fissure()
	_grass()
	for i in beacons.size():
		_beacon_visual(i)
	if player():
		Interactable.make(khaby, khaby.global_transform.origin + Vector3(0, 2.1, 0), 1.1, "talk to the mechanism", self, "_talk", [], false)
	note(at + Vector3(2.2, 0.0, 1.4), "hush · sector 2 · field note\n\nthis one is friendly.\nit doesn't hunt. it doesn't drain you. it explains.\n\nhush file zero: the khaby lame mechanism.\ndo not explain anything to it.\nit will only show you, with both hands,\nhow obvious it was.\n\nthe beacons in the hills are ours. switch them off.\nthen go and talk to it. all of you.")


func enter(boot: bool) -> void:
	if boot:
		boot_goggles_now()
	ambient("amb_field", -6.0, "", -60.0)
	Audio.set_reverb(0.12, 0.6)
	if player():
		player().step_sound = "step_grass"
		player().step_volume = -13.0
		world.set_dust(0)


func start_wave() -> void:
	wave_started = true


# ------------------------------------------------------------------ the field
func _wp(u: float, v: float) -> Vector3:
	return Vector3(origin.x + u, _h(u, v), zc + v)


## Rolling hills: one big round one like the wallpaper, smaller ones behind, a hollow in front,
## flat by the wall, and the edges rising all around so the field ends in hills, not in a wall.
func _h(u: float, v: float) -> float:
	var y = 0.0
	y += 9.0 * exp(-(pow(u - 85.0, 2) + pow(v + 22.0, 2)) / (2.0 * 30.0 * 30.0))
	y += 6.0 * exp(-(pow(u - 128.0, 2) + pow(v - 40.0, 2)) / (2.0 * 26.0 * 26.0))
	y += 3.4 * exp(-(pow(u - 38.0, 2) + pow(v - 48.0, 2)) / (2.0 * 17.0 * 17.0))
	y += 2.5 * exp(-(pow(u - 60.0, 2) + pow(v + 62.0, 2)) / (2.0 * 18.0 * 18.0))
	y -= 1.2 * exp(-(pow(u - 30.0, 2) + pow(v - 10.0, 2)) / (2.0 * 12.0 * 12.0))
	y += 0.45 * sin(u * 0.11 + v * 0.07) * sin(v * 0.09 - u * 0.05)
	var e = max(smoothstep(L - 45.0, L, u), smoothstep(HW - 32.0, HW, abs(v)))
	y += e * e * 16.0
	return y * smoothstep(2.0, 18.0, u)


func _crack_line() -> void:
	_crack = [Vector2(0.0, KHABY.y)]
	var u = 3.0
	while u < L:
		var v = KHABY.y + rng.randf_range(-1.7, 1.7)
		if abs(u - KHABY.x) < 3.0:
			v = KHABY.y
		_crack.append(Vector2(u, v))
		u += rng.randf_range(3.0, 5.5)
	_crack.append(Vector2(L, KHABY.y))


## The crack's v at u (straight segments between the jagged points).
func _vc(u: float) -> float:
	for i in _crack.size() - 1:
		var a: Vector2 = _crack[i]
		var b: Vector2 = _crack[i + 1]
		if u <= b.x:
			return lerp(a.y, b.y, clamp((u - a.x) / max(b.x - a.x, 0.001), 0.0, 1.0))
	return _crack[-1].y


## Two halves, each its own mesh, grass, skirt of earth along the tear and collision.
func _build_terrain() -> void:
	var nu = int(L / GRID) + 1
	var nv = int(HW / GRID)
	var tex = null if world.headless else load("res://textures/grass_bliss.png")
	var mid = Vector3(origin.x + L * 0.5, 0.0, zc + KHABY.y)
	for side in [0, 1]:
		var root = Spatial.new()
		root.name = "half%d" % side
		geo.add_child(root)
		root.translation = mid
		var content = Spatial.new()
		root.add_child(content)
		content.translation = -mid
		var faces = PoolVector3Array()
		var grid = []
		for i in nu:
			var u = min(i * GRID, L)
			var vc = _vc(u)
			var col = []
			for j in nv + 1:
				var t = float(j) / nv
				var v = lerp(-HW, vc, t) if side == 0 else lerp(vc, HW, t)
				col.append(_wp(u, v))
			grid.append(col)
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in nu - 1:
			for j in nv:
				var a: Vector3 = grid[i][j]
				var b: Vector3 = grid[i + 1][j]
				var c: Vector3 = grid[i + 1][j + 1]
				var d: Vector3 = grid[i][j + 1]
				for p in [a, b, c, a, c, d]:
					faces.append(p)
					if tex:
						var shade = clamp(0.86 + p.y * 0.02 + 0.06 * sin(p.x * 0.05 + p.z * 0.04), 0.75, 1.08)
						st.add_color(Color(shade, shade, shade))
						st.add_uv(Vector2(p.x, p.z) * 0.22)
						st.add_vertex(p)
		var body = StaticBody.new()
		body.collision_layer = Geo.LAYER_WORLD
		content.add_child(body)
		var cs = CollisionShape.new()
		var sh = ConcavePolygonShape.new()
		sh.set_faces(faces)
		cs.shape = sh
		body.add_child(cs)
		halves.append({"root": root, "body": body, "shape": cs, "sign": -1.0 if side == 0 else 1.0})
		if tex == null:
			continue
		st.index()
		st.generate_normals()
		# the underside: dark earth and rock, for when it breaks away above you
		var ust = SurfaceTool.new()
		ust.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in nu - 1:
			for j in nv:
				var a2: Vector3 = grid[i][j] - Vector3(0, 1.2, 0)
				var b2: Vector3 = grid[i + 1][j] - Vector3(0, 1.2, 0)
				var c2: Vector3 = grid[i + 1][j + 1] - Vector3(0, 1.2, 0)
				var d2: Vector3 = grid[i][j + 1] - Vector3(0, 1.2, 0)
				var k2 = 0.5 + 0.5 * sin(a2.x * 0.3) * sin(a2.z * 0.27)
				var rock = Color(0.16, 0.1, 0.07).linear_interpolate(Color(0.28, 0.06, 0.04), k2)
				for p in [a2, c2, b2, a2, d2, c2]:
					ust.add_color(rock)
					ust.add_vertex(p)
		var um = MeshInstance.new()
		um.mesh = ust.commit()
		var umat = SpatialMaterial.new()
		umat.vertex_color_use_as_albedo = true
		umat.flags_unshaded = true
		um.material_override = umat
		content.add_child(um)
		var mi = MeshInstance.new()
		mi.mesh = st.commit()
		var m = SpatialMaterial.new()
		m.albedo_texture = tex
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		m.flags_vertex_lighting = Mats.potato()
		mi.material_override = m
		content.add_child(mi)
		# the earth under the grass, along the tear: only ever seen once it opens
		var sk = SurfaceTool.new()
		sk.begin(Mesh.PRIMITIVE_TRIANGLES)
		var jj = nv if side == 0 else 0
		for i in nu - 1:
			var p0: Vector3 = grid[i][jj]
			var p1: Vector3 = grid[i + 1][jj]
			var q0 = p0 - Vector3(0, 10, 0)
			var q1 = p1 - Vector3(0, 10, 0)
			var top = Color(0.34, 0.23, 0.12)
			var bot = Color(0.12, 0.02, 0.01)
			var quad = [[p0, top], [p1, top], [q1, bot], [p0, top], [q1, bot], [q0, bot]]
			if side == 1:
				quad = [[p0, top], [q1, bot], [p1, top], [p0, top], [q0, bot], [q1, bot]]
			for vv in quad:
				sk.add_color(vv[1])
				sk.add_vertex(vv[0])
		sk.generate_normals()
		var skm = MeshInstance.new()
		skm.mesh = sk.commit()
		var em = SpatialMaterial.new()
		em.vertex_color_use_as_albedo = true
		em.params_cull_mode = SpatialMaterial.CULL_DISABLED
		em.roughness = 1.0
		skm.material_override = em
		content.add_child(skm)


## Meadow grass close to where people walk: blades in two MultiMeshes, one per half.
func _grass() -> void:
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	var count = [0, 4500, 11000][q]
	if count == 0:
		return
	var blade = ArrayMesh.new()
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PoolVector3Array([Vector3(-0.025, 0, 0), Vector3(0.025, 0, 0), Vector3(0.012, 0.22, 0), Vector3(-0.012, 0.22, 0), Vector3(0.0, 0.4, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PoolVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.55), Vector2(0, 0.55), Vector2(0.5, 1.0)])
	arr[Mesh.ARRAY_NORMAL] = PoolVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_INDEX] = PoolIntArray([0, 1, 2, 0, 2, 3, 3, 2, 4])
	blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat = ShaderMaterial.new()
	mat.shader = load("res://scripts/grass_blade.shader")
	var r = RandomNumberGenerator.new()
	r.seed = rng.seed + 77
	var spots = [[]]
	spots.append([])
	for k in count:
		# mostly between the door and the mechanism, thinning out further away
		var u = r.randf_range(1.0, 95.0) if r.randf() < 0.8 else r.randf_range(1.0, 150.0)
		var v = r.randf_range(-45.0, 45.0) * (0.5 + u / 190.0)
		if abs(u - KHABY.x) < 1.2 and abs(v - KHABY.y) < 1.2:
			continue
		spots[0 if v < _vc(u) else 1].append(_wp(u, v))
	for side in [0, 1]:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = blade
		mm.instance_count = spots[side].size()
		for k in spots[side].size():
			var b = Basis(Vector3.UP, r.randf_range(-PI, PI)).scaled(Vector3.ONE * r.randf_range(0.7, 1.35))
			mm.set_instance_transform(k, Transform(b, spots[side][k]))
		var mi = MultiMeshInstance.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		halves[side].root.get_child(0).add_child(mi)


## The concrete wall with the door in it: tall enough to hide the hotel behind it.
func _build_wall() -> void:
	var mat = null if world.headless else Mats.std(Color(0.62, 0.61, 0.58), 0.95)
	var z0 = min(-0.4, zc - 40.0)
	var z1 = max(48.4, zc + 40.0)
	var a = zc - DOOR_W * 0.5
	var b = zc + DOOR_W * 0.5
	var x = origin.x
	Geo.solid(geo, Vector3(T, WALL_H, a - z0), Vector3(x, WALL_H * 0.5, (z0 + a) * 0.5), mat, null, mat != null)
	Geo.solid(geo, Vector3(T, WALL_H, z1 - b), Vector3(x, WALL_H * 0.5, (b + z1) * 0.5), mat, null, mat != null)
	Geo.solid(geo, Vector3(T, WALL_H - DOOR_H, DOOR_W), Vector3(x, (WALL_H + DOOR_H) * 0.5, zc), mat, null, mat != null)


## Invisible walls where the hills rise too steep to matter.
func _bounds() -> void:
	for spec in [[Vector3(1.0, 40.0, HW * 2.0), Vector3(origin.x + L - 8.0, 20.0, zc)],
			[Vector3(L, 40.0, 1.0), Vector3(origin.x + L * 0.5, 20.0, zc - HW + 8.0)],
			[Vector3(L, 40.0, 1.0), Vector3(origin.x + L * 0.5, 20.0, zc + HW - 8.0)]]:
		Geo.solid(world, spec[0], spec[1], null, null, false)


## The red line that appears first, before the ground opens.
func _build_fissure() -> void:
	_fissure = Spatial.new()
	geo.add_child(_fissure)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _crack.size() - 1:
		var a: Vector2 = _crack[i]
		var b: Vector2 = _crack[i + 1]
		var steps = 6
		for k in steps:
			var u0 = lerp(a.x, b.x, float(k) / steps)
			var u1 = lerp(a.x, b.x, float(k + 1) / steps)
			var v0 = lerp(a.y, b.y, float(k) / steps)
			var v1 = lerp(a.y, b.y, float(k + 1) / steps)
			var w = 0.18
			var p0 = _wp(u0, v0 - w) + Vector3(0, 0.05, 0)
			var p1 = _wp(u1, v1 - w) + Vector3(0, 0.05, 0)
			var p2 = _wp(u1, v1 + w) + Vector3(0, 0.05, 0)
			var p3 = _wp(u0, v0 + w) + Vector3(0, 0.05, 0)
			for p in [p0, p1, p2, p0, p2, p3]:
				st.add_vertex(p)
	var mi = MeshInstance.new()
	mi.mesh = st.commit()
	var m = Mats.glow(Color(1.0, 0.12, 0.05), 4.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_fissure.add_child(mi)
	_fissure.visible = false


# ------------------------------------------------------------------ the beacons
func _place_beacons() -> void:
	var tries = 0
	while beacons.size() < 4 and tries < 400:
		tries += 1
		var u = rng.randf_range(35.0, 140.0)
		var v = rng.randf_range(-62.0, 62.0)
		var p = _wp(u, v)
		var ok = Vector2(u - KHABY.x, v - KHABY.y).length() > 25.0
		for q in beacons:
			if q.distance_to(p) < 38.0:
				ok = false
		if ok:
			beacons.append(p)


func _beacon_visual(i: int) -> void:
	var root = Spatial.new()
	geo.add_child(root)
	root.global_transform.origin = beacons[i]
	var pole = Mats.std(Color(0.2, 0.2, 0.22), 0.5, 0.6)
	for k in 3:
		var a = TAU * k / 3.0
		Models.limb(root, Vector3(cos(a) * 0.35, 0.0, sin(a) * 0.35), Vector3(0, 0.9, 0), 0.02, pole)
	Models.part(root, Models.cyl(0.11, 0.13, 0.22, 16, 1), Mats.std(Color(0.95, 0.45, 0.08), 0.5), Vector3(0, 1.0, 0))
	var lamp = Models.part(root, Models.sphere(0.09, -1, 12, 6), Mats.glow(Color(1.0, 0.35, 0.05), 5.0), Vector3(0, 1.17, 0))
	lamp.name = "lamp"
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	if player():
		Interactable.make(root, beacons[i] + Vector3(0, 1.0, 0), 0.6, "switch off the beacon", self, "_take_beacon", [i], false)
	_beacon_nodes[i] = root


func _take_beacon(i: int) -> void:
	if Net.active():
		Net.request("beacon", [i])
	else:
		on_request(1, "beacon", [i])


func _talk() -> void:
	if Net.active():
		Net.request("talk")
	else:
		on_request(1, "talk", [])


# ------------------------------------------------------------------ server rules
func on_request(pid: int, type: String, args: Array) -> void:
	match type:
		"photo":
			if args.size() > 1 and str(args[0]) == "khaby":
				mission_set("portrait", max(mission_progress("portrait"), float(args[1])), pid)
		"beacon":
			var i = int(args[0]) if args.size() > 0 else -1
			var t = world.target_by_id(pid)
			if i < 0 or i >= beacons.size() or _beacon_taken.has(i) or t == null or t.pos.distance_to(beacons[i]) > 3.0:
				return
			_beacon_taken[i] = true
			_emit("beacon", [i, pid])
			mission_set("beacons", _beacon_taken.size(), pid)
		"talk":
			if scene_t >= 0.0:
				return
			var t = world.target_by_id(pid)
			if t == null or t.pos.distance_to(khaby.global_transform.origin) > 4.5:
				return
			if not missions_done():
				_emit("nope", [pid])
				return
			var other = -1
			for tt in world.targets(index):
				if tt.id != pid:
					other = tt.id
			_emit("scene", [pid, other])


## Every operative who is still in the run, standing at the mechanism at the same time.
func _check_gather() -> void:
	var total = 0
	if Net.active():
		for pid in Net.round_ids():
			var p = Net.players[pid]
			if p.alive and not p.escaped:
				total += 1
	else:
		total = 1
	var near = 0
	var who = -1
	for t in world.targets(index):
		if t.pos.distance_to(khaby.global_transform.origin) < 5.0:
			near += 1
			who = t.id
	if total > 0 and near >= total:
		mission_set("gather", 1.0, who)


func _physics_process(delta: float) -> void:
	if not authority() or not wave_started:
		return
	_gather_t -= delta
	if _gather_t <= 0.0:
		_gather_t = 0.5
		if _mission_index("gather") >= 0 and not missions[_mission_index("gather")].done:
			_check_gather()
	if scene_t >= END and _phase < 3:
		_phase = 3
		# the void lets go: everyone who fell is out of the run
		if Net.active():
			for t in world.targets(index):
				Net.event("escaped", [t.id])
		elif world.player and not world.dying and world.my_sector == index:
			world.complete()


# ------------------------------------------------------------------ every machine
func net_event(type: String, args: Array) -> void:
	var hud = world.hud if here() else null
	match type:
		"beacon":
			var i: int = args[0]
			if _beacon_nodes.has(i) and is_instance_valid(_beacon_nodes[i]):
				var l = _beacon_nodes[i].get_node_or_null("lamp")
				if l:
					l.visible = false
			_beacon_nodes.erase(i)
			if hud:
				var who = "you" if args[1] == Net.my_id() or not Net.active() else Net.pname(args[1])
				hud.subtitle("%s switched off a beacon." % who, 2.5)
				Audio.play("flash_off", -6.0, 0.8)
		"nope":
			if is_instance_valid(khaby):
				var tw = create_tween()
				tw.tween_property(khaby, "presenting", 1.0, 0.4)
				tw.tween_interval(1.8)
				tw.tween_property(khaby, "presenting", 0.0, 0.6)
				Audio.play_at("khaby_servo", khaby.global_transform.origin + Vector3(0, 1.9, 0), world, 0.0, 0.8, 30.0)
			if hud:
				hud.subtitle("the mechanism shows you, with both hands, the missions that are left. it's that simple.", 4.0)
				hud.flash_missions()
		"scene":
			scene_t = 0.0
			_scene_a = args[0]
			_scene_b = args[1]
			_line = -1
			_phase = 0
			if _mine_in_scene():
				world.cinematic(true)


func _mine_in_scene() -> bool:
	return world.player != null and not world.my_out and not world.dying and world.my_sector == index


func _who(pid: int, fallback: String) -> String:
	if pid < 0:
		return fallback
	if not Net.active() or pid == Net.my_id():
		return "you"
	return Net.pname(pid)


func _process(delta: float) -> void:
	# the beacons blink and beep quietly
	if here() and not _beacon_nodes.empty():
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.4
			var pp = player().global_transform.origin
			for i in _beacon_nodes:
				var n = _beacon_nodes[i]
				if not is_instance_valid(n):
					continue
				var l = n.get_node_or_null("lamp")
				if l:
					l.visible = not l.visible
				if n.global_transform.origin.distance_to(pp) < 34.0:
					Audio.play_at("tick", n.global_transform.origin + Vector3(0, 1.1, 0), world, 0.0, 1.4, 34.0)
	if scene_t < 0.0:
		return
	scene_t += delta
	var mine = _mine_in_scene()
	# --- the conversation
	while _line + 1 < LINES.size() and scene_t >= LINES[_line + 1][0]:
		_line += 1
		var ln = LINES[_line]
		var who = ""
		match ln[1]:
			"a":
				who = _who(_scene_a, "you")
			"b":
				who = _who(_scene_b, "hush radio")
			"r":
				who = "hush radio"
			"m":
				who = "the mechanism"
		if here() and world.hud:
			if _mine_in_scene():
				world.hud.cine_line(who, ln[2])
			else:
				world.hud.subtitle("%s:   %s" % [who, ln[2]], 3.4)
			_voice(ln[1], who)
		if is_instance_valid(khaby):
			var tw = create_tween()
			tw.tween_property(khaby, "presenting", float(ln[3]), 0.5)
	if mine and _phase < 2:
		# the camera holds on the mechanism's face
		var head = khaby.global_transform.origin + Vector3(0, 2.35, 0)
		if _line == 6:
			head = khaby.global_transform.origin + Vector3(0, 0.3, 0).linear_interpolate(Vector3(0, 2.35, 0), 0.5)
		var pl = player()
		var to = head - pl.eye_pos()
		var yaw = atan2(-to.x, -to.z)
		var pitch = atan2(to.y, Vector2(to.x, to.z).length())
		pl.set_look(lerp_angle(pl._yaw, yaw, clamp(delta * 2.5, 0.0, 1.0)), lerp(pl._pitch, pitch, clamp(delta * 2.5, 0.0, 1.0)))
	# --- the tear
	var c = scene_t - CUTSCENE
	if c >= 0.0 and _phase == 0:
		_phase = 1
		_tear_begins()
	if _phase >= 1 and _phase < 3:
		_tear(c, delta)


func _voice(who: String, _name: String) -> void:
	match who:
		"m":
			if is_instance_valid(khaby):
				Audio.play_at("khaby_servo", khaby.global_transform.origin + Vector3(0, 1.9, 0), world, 2.0, 0.9, 40.0)
		"r":
			for k in 5:
				get_tree().create_timer(k * 0.11).connect("timeout", Audio, "play", ["radio_blip", -6.0, rand_range(0.95, 1.1)])
		_:
			for k in 6:
				get_tree().create_timer(k * 0.09).connect("timeout", Audio, "play", ["talk_blip", -8.0, rand_range(0.85, 1.2) if who == "a" else rand_range(0.7, 0.9)])


## The world tears: a red line, the sky goes red, the ground splits down the middle.
func _tear_begins() -> void:
	if here():
		Audio.play("crack_break", 0.0)
		Audio.play("crack_rumble", -2.0)
		if world.hud:
			world.hud.crack_overlay()
		world.flash(0.6)
		world.override_env({
			"bg": Color(0.22, 0.02, 0.01), "ambient": Color(1.0, 0.35, 0.28), "ambient_energy": 0.55,
			"fog_color": Color(0.32, 0.03, 0.02), "fog_begin": 8.0, "fog_end": 90.0, "fog_curve": 1.2,
			"tint": Vector3(1.22, 0.72, 0.64), "contrast": 1.18, "saturation": 0.9,
		}, 1.6)
		if world.hud:
			world.hud.cine_line("", "")
	if _fissure:
		_fissure.visible = true
	if sun:
		var tw = create_tween()
		tw.tween_property(sun, "light_color", Color(1.0, 0.25, 0.12), 1.4)
		tw.parallel().tween_property(sun, "light_energy", 0.7, 1.4)
	if is_instance_valid(khaby):
		khaby.pinned = true
		khaby.presenting = 0.0


func _tear(c: float, delta: float) -> void:
	var mine = _mine_in_scene()
	if mine and c < 2.4:
		player().add_trauma(delta * 2.2)
	# open: the halves pull apart and tip away from the tear
	var s = 2.4 * smoothstep(0.4, 2.3, c)
	var tilt = deg2rad(7.0) * smoothstep(0.4, 2.3, c)
	var drop = 0.0
	if c > 2.3:
		var f = c - 2.3
		s += f * f * 2.2
		tilt += deg2rad(34.0) * smoothstep(0.0, 4.0, f)
		drop = 0.5 * 9.8 * f * f * 0.6
	for hh in halves:
		var root: Spatial = hh.root
		var sg: float = hh.sign
		var base = Vector3(origin.x + L * 0.5, 0.0, zc + KHABY.y)
		root.translation = base + Vector3(0, -drop, sg * s)
		root.rotation = Vector3(-sg * tilt, 0, 0)
	# you ride your half as it pulls away (until there is nothing left to stand on)
	if mine and _phase == 1:
		var pl = player()
		if _ride < 0:
			var pp = pl.global_transform.origin
			_ride = 0 if pp.z - zc < _vc(pp.x - origin.x) else 1
			_ride_prev = halves[_ride].root.translation
		var now: Vector3 = halves[_ride].root.translation
		pl.global_transform.origin += Vector3(0, 0, now.z - _ride_prev.z)
		_ride_prev = now
	if c >= 2.3 and _phase == 1:
		_phase = 2
		# nothing to stand on any more
		for hh in halves:
			hh.shape.disabled = true
		if _fissure:
			_fissure.visible = false
		if here():
			Audio.play("void_fall", 0.0)
			world.override_env({
				"bg": Color(0.03, 0.0, 0.0), "ambient": Color(0.6, 0.15, 0.12), "ambient_energy": 0.35,
				"fog_color": Color(0.06, 0.0, 0.0), "fog_begin": 4.0, "fog_end": 60.0, "fog_curve": 1.0,
				"tint": Vector3(1.25, 0.55, 0.48), "contrast": 1.2, "saturation": 1.0,
			}, 2.5)
		if mine:
			_fall_fx()
	if _phase == 2 and mine:
		player().add_trauma(delta * 0.8)
		if c > CRACK - 1.2 and world.hud and world.hud.fade_rect.color.a < 0.01:
			world.hud.fade(1.0, 1.1)


## Falling: red streaks rushing up past you in the dark.
func _fall_fx() -> void:
	_streaks = CPUParticles.new()
	_streaks.amount = 160
	_streaks.lifetime = 0.9
	_streaks.local_coords = false
	_streaks.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(6, 3, 6)
	_streaks.direction = Vector3(0, 1, 0)
	_streaks.spread = 4.0
	_streaks.gravity = Vector3.ZERO
	_streaks.initial_velocity = 38.0
	var q = QuadMesh.new()
	q.size = Vector2(0.03, 1.4)
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_FIXED_Y
	m.albedo_color = Color(1.0, 0.2, 0.1, 0.55)
	q.material = m
	_streaks.mesh = q
	player().add_child(_streaks)
	_streaks.translation = Vector3(0, -2.0, 0)
