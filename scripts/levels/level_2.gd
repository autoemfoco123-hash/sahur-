extends LevelBase
## LEVEL 2 — BLISS. (Godot 3)
## Behind the key rooms' last door: a green field under a blue sky, rolling hills, a breeze in
## the grass. Nothing hunts you here. In the middle of the field, on a little table, the Khaby
## Lame Mechanism turns its hands over and over. Missions done, talk to it (e): it talks, only
## it, terrified, about the field (scripts/khaby_lines.gd, a real voice: tools/khaby_voice.py),
## then "watch out!": the ground splits down the middle, the sky goes red, it falls in first,
## screaming, and everyone falls after it into the void. It falls away from you into the dark,
## for ever. The void lets you go in the next sector (you come to on its floor); never it.
## The field is two halves of terrain that meet along a jagged line right under the mechanism:
## that is where it tears.

const KhabyAI := preload("res://scripts/enemies/khaby.gd")
const L := 170.0          # field length along x (from the wall with the door)
const HW := 90.0          # half width along z, around the door
const GRID := 2.0
const T := 0.28
const WALL_H := 5.0
const KHABY := Vector2(46.0, 3.0)    # (u, v) of the mechanism
const KL = preload("res://scripts/khaby_lines.gd")
const CRACK := 8.5                   # from "watch out!" to the void letting go
const GCH := 8.0                     # grass chunk size (m)

var CUTSCENE = KL.TALK_END + 0.5     # the monologue, in seconds
var END = CUTSCENE + CRACK

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
var _khead: Spatial            # the mechanism's head (where its voice comes from)
var _krest = Transform()       # where it stood
var _kfall_off = Vector3.INF   # its offset from you while you both fall (it falls faster)
var _kgone = false
var _gchunks = {}              # grass: Vector2 chunk -> [MultiMeshInstance, MultiMeshInstance]
var _gqueue = []
var _gblade: ArrayMesh
var _gmat: ShaderMaterial
var _gcount = 0
var _gradius = 0.0
var _gt = 0.0
var _hgrid = PoolRealArray()   # terrain height every metre (fast lookups for the grass)
var _hw = 0
var _vcl = PoolRealArray()     # the crack's v every half metre
var _birds = []
var _clods = []                # earth falling into the tear: [node, velocity, spin, life]
var _limbo = []                # debris falling with you in the void: [node, offset, drift, spin]
var _dust: CPUParticles


func build() -> void:
	env({
		"sky": "res://textures/sky_bliss.png", "sky_contribution": 0.6,
		"ambient": Color(0.74, 0.84, 1.0), "ambient_energy": 0.7 if Mats.potato() else 0.5,
		"fog_color": Color(0.69, 0.8, 0.94), "fog_begin": 18.0 if Mats.potato() else 35.0, "fog_end": 34.0 if Mats.potato() else 420.0, "fog_curve": 1.7,
		"fog_sun_color": Color(1.0, 0.93, 0.78), "fog_sun_amount": 0.4,
		"exposure": 1.05, "white": 5.0, "dof_far": 140.0,
		"tint": Vector3(1.0, 1.0, 1.0), "contrast": 1.06, "saturation": 1.08,
	})
	boot_goggles = true
	greeter = ""
	has_exit_door = false
	revive_wakes = false
	ending_text = "the ground opened and you fell.\n\nthe void carried you somewhere else.\nhush lost your signal in sector 2."
	zc = entry_z if has_entry else 24.0
	entry_z = zc
	exit_z = zc
	extent = Vector2(L, HW * 2.0)
	_crack_line()
	_lookups()
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
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_color = Color(0.32, 0.38, 0.5)
	sun.rotation_degrees = Vector3(-46, -125, 0)
	sun.directional_shadow_mode = DirectionalLight.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.visible = false
	world.add_child(sun)
	_build_fissure()
	_grass_setup()
	_birds_build()
	_khead = khaby.model.find_node("head", true, false)
	_krest = khaby.global_transform
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
		_pollen()


func start_wave() -> void:
	wave_started = true


## Pollen and seed fluff drifting in the sunlight around you.
func _pollen() -> void:
	if int(Game.settings.gfx) < 1 or player() == null:
		return
	var p = CPUParticles.new()
	p.amount = 90
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.local_coords = false
	p.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 2.0, 9)
	p.direction = Vector3(1, 0.1, 0.6)
	p.spread = 40.0
	p.gravity = Vector3(0.05, -0.01, 0.03)
	p.initial_velocity = 0.25
	p.scale_amount = 1.0
	p.scale_amount_random = 0.8
	var q = QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var m = SpatialMaterial.new()
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.flags_transparent = true
	m.flags_unshaded = true
	m.albedo_color = Color(1.0, 0.98, 0.88, 0.75)
	q.material = m
	p.mesh = q
	p.add_to_group("dust")
	player().add_child(p)
	p.translation = Vector3(0, 1.0, 0)


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
		umat.albedo_texture = load("res://textures/earth_layers.png")
		umat.uv1_triplanar = true
		umat.uv1_scale = Vector3(0.12, 0.08, 0.12)
		umat.vertex_color_use_as_albedo = true
		umat.roughness = 1.0
		um.material_override = umat
		content.add_child(um)
		var mi = MeshInstance.new()
		mi.mesh = st.commit()
		var m = ShaderMaterial.new()
		m.shader = load("res://scripts/terrain_bliss.shader")
		m.set_shader_param("grass_tex", load("res://textures/grass_ground.png"))
		m.set_shader_param("noise_tex", Mats.noise_tex())
		mi.material_override = m
		content.add_child(mi)
		# the earth under the grass, along the tear: only ever seen once it opens
		var sk = SurfaceTool.new()
		sk.begin(Mesh.PRIMITIVE_TRIANGLES)
		var jj = nv if side == 0 else 0
		var run = 0.0
		for i in nu - 1:
			var p0: Vector3 = grid[i][jj]
			var p1: Vector3 = grid[i + 1][jj]
			var q0 = p0 - Vector3(0, 10, 0)
			var q1 = p1 - Vector3(0, 10, 0)
			# the walls of the tear: turf, roots, soil, clay, stones, rock, then dark
			var r0 = run / 5.0
			run += Vector2(p1.x - p0.x, p1.z - p0.z).length()
			var r1 = run / 5.0
			var quad = [[p0, Vector2(r0, 0)], [p1, Vector2(r1, 0)], [q1, Vector2(r1, 1)], [p0, Vector2(r0, 0)], [q1, Vector2(r1, 1)], [q0, Vector2(r0, 1)]]
			if side == 1:
				quad = [[p0, Vector2(r0, 0)], [q1, Vector2(r1, 1)], [p1, Vector2(r1, 0)], [p0, Vector2(r0, 0)], [q0, Vector2(r0, 1)], [q1, Vector2(r1, 1)]]
			for vv in quad:
				sk.add_uv(vv[1])
				sk.add_vertex(vv[0])
		sk.generate_normals()
		var skm = MeshInstance.new()
		skm.mesh = sk.commit()
		var em = SpatialMaterial.new()
		em.albedo_texture = load("res://textures/earth_layers.png")
		em.params_cull_mode = SpatialMaterial.CULL_DISABLED
		em.roughness = 1.0
		skm.material_override = em
		content.add_child(skm)


## Fast lookups for the grass: the height every metre, the crack every half metre.
func _lookups() -> void:
	_hw = int(HW * 2.0) + 2
	var nu = int(L) + 2
	_hgrid.resize(nu * _hw)
	for i in nu:
		for j in _hw:
			_hgrid[i * _hw + j] = _h(float(i), float(j) - HW)
	_vcl.resize(int(L * 2.0) + 2)
	for i in _vcl.size():
		_vcl[i] = _vc(i * 0.5)


func _hq(u: float, v: float) -> float:
	var x = clamp(u, 0.0, L)
	var y = clamp(v + HW, 0.0, HW * 2.0)
	var i = int(x)
	var j = int(y)
	var fx = x - i
	var fy = y - j
	var a = _hgrid[i * _hw + j]
	var b = _hgrid[(i + 1) * _hw + j]
	var c = _hgrid[i * _hw + j + 1]
	var d = _hgrid[(i + 1) * _hw + j + 1]
	return lerp(lerp(a, b, fx), lerp(c, d, fx), fy)


func _vcq(u: float) -> float:
	return _vcl[int(clamp(u * 2.0, 0.0, _vcl.size() - 1))]


## Meadow grass, dense, in 8 m chunks around wherever you are (built as you walk), each blade
## its own height, lean and green, in clumps; the wind rolls over it in gusts (grass_blade.shader).
## Every chunk is split along the crack, so its blades go with their half when the field tears.
func _grass_setup() -> void:
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	_gcount = [0, 400, 850][q]          # tufts of eight blades per 8 m chunk
	_gradius = [0.0, 20.0, 28.0][q]
	if _gcount == 0:
		return
	# a tuft: five tapered blades curving out from one root, each its own height and lean
	var hh = 0.36
	var blade = [Vector3(-0.011, 0, 0), Vector3(0.011, 0, 0), Vector3(-0.009, 0.13, 0.012), Vector3(0.009, 0.13, 0.012),
		Vector3(-0.006, 0.25, 0.045), Vector3(0.006, 0.25, 0.045), Vector3(0.0, hh, 0.1)]
	var bi = [0, 1, 3, 0, 3, 2, 2, 3, 5, 2, 5, 4, 4, 5, 6]
	var verts = PoolVector3Array()
	var uvs = PoolVector2Array()
	var nrm = PoolVector3Array()
	var idx = PoolIntArray()
	var tr = RandomNumberGenerator.new()
	tr.seed = 4242
	for k in 8:
		var yaw = TAU * k / 8.0 + tr.randf_range(-0.5, 0.5)
		var hs = tr.randf_range(0.55, 1.25)
		var lean = tr.randf_range(0.05, 0.45)
		var off = Vector3(tr.randf_range(-0.09, 0.09), 0, tr.randf_range(-0.09, 0.09))
		var bas = Basis(Vector3.UP, yaw).rotated(Vector3.UP, 0.0)
		var base = verts.size()
		for p in blade:
			var qv = Vector3(p.x, p.y * hs, p.z + p.y * lean)
			verts.append(bas.xform(qv) + off)
			uvs.append(Vector2(0.5 + p.x * 10.0, p.y / hh))
			nrm.append(bas.xform(Vector3(0, 0.4, -1).normalized()))
		for i in bi:
			idx.append(base + i)
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	_gblade = ArrayMesh.new()
	_gblade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_gmat = ShaderMaterial.new()
	_gmat.shader = load("res://scripts/grass_blade.shader")
	_gmat.set_shader_param("fade", Vector2(_gradius - 10.0, _gradius))


func _grass_update(delta: float) -> void:
	if _gcount == 0 or player() == null:
		return
	_gt -= delta
	if _gt <= 0.0:
		_gt = 0.25
		var cp: Vector3 = player().cam.global_transform.origin
		var cu = (cp.x - origin.x) / GCH
		var cv = (cp.z - zc) / GCH
		var k = int(ceil(_gradius / GCH)) + 1
		var want = {}
		for i in range(int(floor(cu)) - k, int(floor(cu)) + k + 1):
			for j in range(int(floor(cv)) - k, int(floor(cv)) + k + 1):
				var c = Vector2(i, j)
				var mid = Vector2((i + 0.5) * GCH, (j + 0.5) * GCH)
				var d = mid.distance_to(Vector2(cu, cv) * GCH)
				if d < _gradius + GCH * 0.75:
					want[c] = true
					if not _gchunks.has(c) and not c in _gqueue:
						_gqueue.append(c)
		for c in _gchunks:
			for mi in _gchunks[c]:
				if mi and is_instance_valid(mi):
					mi.visible = want.has(c)
		# nearest first
		var cc = Vector2(cu, cv)
		_gqueue.sort_custom(self, "_nearer")
		_gnear = cc
	# one chunk per frame
	if not _gqueue.empty():
		var c = _gqueue.pop_front()
		if not _gchunks.has(c):
			_grass_chunk(c)


var _gnear = Vector2.ZERO


func _nearer(a: Vector2, b: Vector2) -> bool:
	return (a + Vector2(0.5, 0.5)).distance_squared_to(_gnear) < (b + Vector2(0.5, 0.5)).distance_squared_to(_gnear)


func _grass_chunk(c: Vector2) -> void:
	var r = RandomNumberGenerator.new()
	r.seed = int(c.x * 7919.0 + c.y * 104729.0) + 31
	var sides = [[], []]
	var u0 = c.x * GCH
	var v0 = c.y * GCH
	var kp = Vector2(KHABY.x, KHABY.y)
	var clumps = int(_gcount / 5)
	for k in clumps:
		var cu = u0 + r.randf() * GCH
		var cv = v0 + r.randf() * GCH
		var n = r.randi_range(3, 7)
		for b in n:
			var u = cu + r.randfn(0.0, 0.6)
			var v = cv + r.randfn(0.0, 0.6)
			if u < 0.6 or u > L - 9.0 or abs(v) > HW - 9.0:
				continue
			if Vector2(u, v).distance_to(kp) < 1.1:
				continue
			sides[0 if v < _vcq(u) else 1].append(Vector3(origin.x + u, _hq(u, v) - 0.02, zc + v))
	var made = [null, null]
	for side in [0, 1]:
		if sides[side].empty():
			continue
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.color_format = MultiMesh.COLOR_8BIT
		mm.mesh = _gblade
		mm.instance_count = sides[side].size()
		for k in sides[side].size():
			var hs = r.randf_range(0.65, 1.45)
			var ws = r.randf_range(0.8, 1.25)
			var b = Basis(Vector3.UP, r.randf_range(-PI, PI))
			b = b.rotated(Vector3(1, 0, 0), r.randf_range(-0.22, 0.22)).rotated(Vector3(0, 0, 1), r.randf_range(-0.22, 0.22))
			b = b.scaled(Vector3(ws, hs, ws))
			mm.set_instance_transform(k, Transform(b, sides[side][k]))
			var g = r.randf_range(0.82, 1.12)
			var y = r.randf_range(0.0, 1.0)
			mm.set_instance_color(k, Color(g * (0.92 + 0.16 * y), g, g * (0.9 - 0.12 * y), r.randf()))
		var mi = MultiMeshInstance.new()
		mi.multimesh = mm
		mi.material_override = _gmat
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		halves[side].root.get_child(0).add_child(mi)
		made[side] = mi
	_gchunks[c] = made


## A few birds far off over the hills, wheeling, flapping, gliding.
func _birds_build() -> void:
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = Color(0.12, 0.12, 0.13)
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	var r = RandomNumberGenerator.new()
	r.seed = rng.seed + 5
	for i in 7:
		var b = Spatial.new()
		geo.add_child(b)
		var wings = []
		for sd in [-1.0, 1.0]:
			var piv = Models.pivot(b, "w", Vector3.ZERO)
			var q = QuadMesh.new()
			q.size = Vector2(0.55, 0.16)
			var w = MeshInstance.new()
			w.mesh = q
			w.material_override = m
			piv.add_child(w)
			w.translation = Vector3(sd * 0.28, 0, 0)
			w.rotation_degrees = Vector3(90, 0, 0)
			wings.append(piv)
		Models.part(b, Models.box(Vector3(0.09, 0.07, 0.34)), m)
		var center = Vector3(origin.x + r.randf_range(40.0, 150.0), 0, zc + r.randf_range(-70.0, 70.0))
		_birds.append({"node": b, "wings": wings, "c": center, "rad": r.randf_range(25.0, 60.0), "h": r.randf_range(24.0, 48.0),
			"spd": r.randf_range(0.08, 0.16) * (1.0 if r.randf() < 0.5 else -1.0), "ph": r.randf() * TAU, "flap": r.randf_range(7.0, 10.0)})


func _birds_update(delta: float) -> void:
	var t = OS.get_ticks_msec() * 0.001
	for bd in _birds:
		bd.ph += bd.spd * delta
		var a = bd.ph
		var p = bd.c + Vector3(cos(a), 0, sin(a)) * bd.rad
		p.y = bd.h + sin(a * 2.3) * 3.0
		var n: Spatial = bd.node
		n.translation = p
		n.rotation = Vector3(0, -a + (0.0 if bd.spd > 0 else PI), sin(a * 1.7) * 0.25)
		# flap in bursts, then glide
		var glide = 0.5 + 0.5 * sin(t * 0.6 + bd.flap)
		var f = sin(t * bd.flap) * 0.7 * (1.0 - smoothstep(0.55, 0.8, glide)) + 0.12
		bd.wings[0].rotation.z = f
		bd.wings[1].rotation.z = -f


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
			if i < 0 or i >= beacons.size() or _beacon_taken.has(i) or t == null or t.pos.distance_to(beacons[i]) > 3.8:
				return
			_beacon_taken[i] = true
			_emit("beacon", [i, pid])
			mission_set("beacons", _beacon_taken.size(), pid)
		"talk":
			if scene_t >= 0.0:
				return
			var t = world.target_by_id(pid)
			if t == null or t.pos.distance_to(khaby.global_transform.origin) > 5.5:
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
		var nxt = index + 1 < world.levels.size()
		# the void lets go: everyone who fell lands in the next sector (or is out of the run)
		if Net.active():
			for t in world.targets(index):
				if nxt:
					Net.advance_to(t.id, index + 1)
				else:
					Net.event("escaped", [t.id])
		elif world.player and not world.dying and world.my_sector == index:
			if nxt:
				world.drop_into(index + 1)
			else:
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
			if is_instance_valid(khaby):
				var tw = create_tween()
				tw.tween_property(khaby, "fear", 1.0, 0.6)
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
	if here():
		_grass_update(delta)
		_birds_update(delta)
	_clods_update(delta)
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
	# --- the monologue: only the mechanism talks, and it is terrified
	while _line + 1 < KL.LINES.size() and scene_t >= KL.LINES[_line + 1][0]:
		_line += 1
		var ln = KL.LINES[_line]
		if here() and world.hud:
			if mine:
				world.hud.cine_line("the mechanism", ln[1])
			else:
				world.hud.subtitle("the mechanism:   %s" % ln[1], ln[5] + 0.6)
		if is_instance_valid(khaby):
			if world.player:
				Audio.play_at(ln[2], _khead_pos(), world, 7.0, 1.0, 80.0)
			khaby.talk = ln[5]
			var tw = create_tween()
			tw.tween_property(khaby, "presenting", float(ln[4]), 0.5)
	if is_instance_valid(khaby) and not world.headless and _phase == 0:
		khaby.gaze_at = _gaze_point()
	if mine and _phase < 2 and is_instance_valid(khaby):
		# the camera stays on it (and looks where it looks, now and then); then it falls
		var target = _khead_pos()
		if _line >= 0 and _phase == 0:
			var ln = KL.LINES[_line]
			var into = scene_t - ln[0]
			if ln[3] == "sky" and into > 1.0 and into < ln[5] + 0.2:
				target = _khead_pos() + Vector3(-9.0, 20.0, 3.0)
			elif ln[3] == "down" and into > 1.3 and into < ln[5] - 0.2:
				target = player().global_transform.origin.linear_interpolate(khaby.global_transform.origin, 0.55)
		_aim(target, delta, 2.2 if _phase == 0 else 5.0)
	# --- watch out: the tear
	var c = scene_t - CUTSCENE
	if c >= 0.0 and _phase == 0:
		_phase = 1
		_tear_begins()
	if _phase >= 1 and _phase < 3:
		_tear(c, delta)


func _aim(target: Vector3, delta: float, rate: float) -> void:
	var pl = player()
	var to = target - pl.eye_pos()
	var yaw = atan2(-to.x, -to.z)
	var pitch = clamp(atan2(to.y, Vector2(to.x, to.z).length()), -1.45, 1.45)
	pl.set_look(lerp_angle(pl._yaw, yaw, clamp(delta * rate, 0.0, 1.0)), lerp(pl._pitch, pitch, clamp(delta * rate, 0.0, 1.0)))


func _khead_pos() -> Vector3:
	if _khead and is_instance_valid(_khead):
		return _khead.global_transform.origin + Vector3(0, 0.15, 0)
	return khaby.global_transform.origin + Vector3(0, 2.35, 0)


## Where the mechanism looks while it talks: at you, at the sky, at a beacon, at the grass...
func _gaze_point() -> Vector3:
	var h = _khead_pos()
	var mode = KL.LINES[_line][3] if _line >= 0 else "you"
	match mode:
		"sky":
			return h + Vector3(-8.0, 22.0, 3.0)
		"beacon":
			var best = h + Vector3(-10, 0, 0)
			var bd = 1e9
			for b in beacons:
				if b.distance_to(h) < bd:
					bd = b.distance_to(h)
					best = b + Vector3(0, 1.0, 0)
			return best
		"down":
			return khaby.global_transform.origin - khaby.global_transform.basis.z * 1.4 - Vector3(0, 0.2, 0)
		"around":
			var a = scene_t * 1.6
			return h + Vector3(cos(a) * 6.0, 0.6 + sin(a * 0.7) * 0.8, sin(a) * 6.0)
	if world.player:
		return world.player.eye_pos()
	return h - khaby.global_transform.basis.z * 3.0


## "Watch out!": the world tears. A red line, the sky goes red, the ground splits down the middle.
func _tear_begins() -> void:
	if here():
		Audio.play("crack_break", 0.0)
		Audio.play("crack_rumble", -2.0)
		if world.hud:
			world.hud.crack_overlay()
			world.hud.cine_line("the mechanism", "watch out!")
		world.flash(0.6)
		world.override_env({
			"bg": Color(0.22, 0.02, 0.01), "ambient": Color(1.0, 0.35, 0.28), "ambient_energy": 0.55,
			"fog_color": Color(0.32, 0.03, 0.02), "fog_begin": 8.0, "fog_end": 90.0, "fog_curve": 1.2,
			"tint": Vector3(1.22, 0.72, 0.64), "contrast": 1.18, "saturation": 0.9,
		}, 1.6)
	if world.player and is_instance_valid(khaby):
		Audio.play_at("khaby_watchout", _khead_pos(), world, 10.0, 1.0, 90.0)
	if _fissure:
		_fissure.visible = true
	if sun:
		var tw = create_tween()
		tw.tween_property(sun, "light_color", Color(1.0, 0.25, 0.12), 1.4)
		tw.parallel().tween_property(sun, "light_energy", 0.7, 1.4)
	if is_instance_valid(khaby):
		khaby.pinned = true
		khaby.fear = 1.0
		khaby.presenting = 0.0
		if world.player:
			khaby.gaze_at = world.player.eye_pos()
	if _mine_in_scene():
		_dust_start()


var _gap = 0.0
var _kscreamed = false
var _kfall_t0 = 0.0


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
	_gap = s * 2.0
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
	_khaby_fall(c, mine)
	# the earth breaks off the edges and falls in
	if mine and c > 0.4 and c < 2.6 and randf() < delta * 14.0:
		_clod()
	if c >= 2.3 and _phase == 1:
		_phase = 2
		# nothing to stand on any more
		for hh in halves:
			hh.shape.disabled = true
		if _fissure:
			_fissure.visible = false
		if _dust and is_instance_valid(_dust):
			_dust.emitting = false
		if here():
			Audio.play("void_fall", 0.0)
			Audio.play("khaby_fall", -1.0)
			world.override_env({
				"bg": Color(0.03, 0.0, 0.0), "ambient": Color(0.6, 0.15, 0.12), "ambient_energy": 0.35,
				"fog_color": Color(0.06, 0.0, 0.0), "fog_begin": 4.0, "fog_end": 60.0, "fog_curve": 1.0,
				"tint": Vector3(1.25, 0.55, 0.48), "contrast": 1.2, "saturation": 1.0,
			}, 2.5)
		if mine:
			_fall_fx()
			_limbo_start()
	if _phase == 2 and mine:
		player().add_trauma(delta * 0.8)
		_limbo_update(delta)
		# you watch it fall away from you, into the dark
		if is_instance_valid(khaby) and khaby.visible and c < 6.4:
			_aim(_khead_pos(), delta, 3.0)
		if c > CRACK - 1.2 and world.hud and world.hud.fade_rect.color.a < 0.01:
			world.hud.fade(1.0, 1.1)


## The mechanism goes first: its table rocks as the ground splits under it, tips, and it drops
## into the tear, screaming, its arms spinning. In the void it falls faster than you, further and
## further below, tumbling, until the dark has it. It never lands anywhere.
func _khaby_fall(c: float, mine: bool) -> void:
	if not is_instance_valid(khaby) or _kgone:
		return
	var k0: Transform = _krest
	if c < 1.0:
		var w = smoothstep(0.25, 1.0, c)
		var b = k0.basis.rotated(Vector3(1, 0, 0), sin(c * 24.0) * 0.05 * w + 0.22 * w * w)
		khaby.global_transform = Transform(b, k0.origin + Vector3(0, -0.2 * w * w, 0))
		return
	if not _kscreamed:
		_kscreamed = true
		khaby.flail = 1.0
		if not world.headless:
			var kl = OmniLight.new()
			kl.light_color = Color(1.0, 0.55, 0.45)
			kl.light_energy = 1.6
			kl.omni_range = 5.0
			kl.light_cull_mask = Geo.VIS_ACTOR | 1
			khaby.add_child(kl)
			kl.translation = Vector3(0.6, 2.6, -0.8)
		if world.player:
			Audio.play_at("khaby_scream", _khead_pos(), world, 10.0, 1.0, 90.0)
	var f = c - 1.0
	var tumble = k0.basis.rotated(Vector3(1, 0, 0), 0.22 + f * 2.4).rotated(Vector3(0, 0, 1), f * 1.1)
	if _phase < 2 or not mine:
		khaby.global_transform = Transform(tumble, k0.origin + Vector3(0, -0.5 * 9.8 * f * f, 0))
		return
	var pp = player().global_transform.origin
	if _kfall_off == Vector3.INF:
		_kfall_off = khaby.global_transform.origin - pp
		_kfall_t0 = c
	var g = c - _kfall_t0
	var off = _kfall_off + Vector3(0.7 * g, -3.4 * g * g - 1.5 * g, 0.5 * g)
	khaby.global_transform = Transform(tumble, pp + off)
	if off.length() > 150.0 or c > CRACK - 0.8:
		khaby.visible = false
		_kgone = true


# ------------------------------------------------------------------ the tear: dust, earth, the void
var _soft: ImageTexture
var _earth_mat: SpatialMaterial


func _soft_tex() -> ImageTexture:
	if _soft:
		return _soft
	var img = Image.new()
	img.create(64, 64, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in 64:
		for x in 64:
			var d = Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	img.unlock()
	_soft = ImageTexture.new()
	_soft.create_from_image(img)
	return _soft


func _earth() -> SpatialMaterial:
	if _earth_mat:
		return _earth_mat
	_earth_mat = SpatialMaterial.new()
	_earth_mat.albedo_texture = load("res://textures/earth_layers.png")
	_earth_mat.albedo_color = Color(0.55, 0.5, 0.46)
	_earth_mat.uv1_triplanar = true
	_earth_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	_earth_mat.roughness = 1.0
	return _earth_mat


## A lump of earth or rock: a squashed, uneven little sphere.
func _rock_mesh(sz: float) -> Mesh:
	var m = SphereMesh.new()
	m.radius = sz * 0.5
	m.height = sz * rand_range(0.55, 0.95)
	m.radial_segments = 6
	m.rings = 3
	return m


## Dust: the tear breathes out a brown cloud along its whole length.
func _dust_start() -> void:
	var p = CPUParticles.new()
	p.amount = 80 if int(Game.settings.gfx) >= 1 else 30
	p.lifetime = 4.0
	p.local_coords = false
	p.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(28, 0.3, 1.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity = 2.4
	p.initial_velocity_random = 0.6
	p.gravity = Vector3(0, -0.3, 0)
	p.damping = 0.5
	p.scale_amount = 3.0
	p.scale_amount_random = 0.7
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.15, Color(1, 1, 1, 0.55))
	g.add_point(0.6, Color(1, 1, 1, 0.35))
	p.color_ramp = g
	var q = QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m = SpatialMaterial.new()
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.flags_transparent = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.5, 0.4, 0.3, 1.0)
	m.albedo_texture = _soft_tex()
	q.material = m
	p.mesh = q
	geo.add_child(p)
	var pp = player().global_transform.origin
	p.global_transform.origin = Vector3(pp.x, _wp(pp.x - origin.x, KHABY.y).y - 0.3, zc + _vcq(pp.x - origin.x))
	_dust = p


## A clod of earth (turf on top) breaking off an edge of the tear and falling in.
func _clod() -> void:
	var pp = player().global_transform.origin
	var u = clamp(pp.x - origin.x + rand_range(-14.0, 14.0), 2.0, L - 2.0)
	var sd = 1.0 if randf() < 0.5 else -1.0
	var p: Vector3 = _wp(u, _vcq(u))
	p.z += sd * _gap * 0.5
	var n = MeshInstance.new()
	var sz = rand_range(0.18, 0.7)
	n.mesh = _rock_mesh(sz)
	n.scale = Vector3(rand_range(0.8, 1.6), 1.0, rand_range(0.8, 1.4))
	n.material_override = _earth()
	geo.add_child(n)
	n.global_transform.origin = p
	n.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_clods.append([n, Vector3(rand_range(-0.6, 0.6), rand_range(-0.5, 1.2), -sd * rand_range(0.3, 1.4)), Vector3(rand_range(-3, 3), rand_range(-3, 3), rand_range(-3, 3)), 0.0])


func _clods_update(delta: float) -> void:
	for i in range(_clods.size() - 1, -1, -1):
		var cl = _clods[i]
		var n: Spatial = cl[0]
		cl[3] += delta
		if not is_instance_valid(n) or cl[3] > 6.0:
			if is_instance_valid(n):
				n.queue_free()
			_clods.remove(i)
			continue
		cl[1].y -= 9.8 * delta
		n.global_transform.origin += cl[1] * delta
		n.rotation += cl[2] * delta


## The void: rocks and slabs of field falling with you, near and far, turning slowly.
func _limbo_start() -> void:
	var count = 26 if int(Game.settings.gfx) >= 1 else 12
	for i in count:
		var n = MeshInstance.new()
		var sz = rand_range(0.3, 3.2)
		n.mesh = _rock_mesh(sz)
		n.scale = Vector3(rand_range(0.8, 2.0), rand_range(0.6, 1.0), rand_range(0.8, 1.7))
		n.material_override = _earth()
		geo.add_child(n)
		var dir = Vector3(rand_range(-1, 1), rand_range(-0.9, 0.7), rand_range(-1, 1)).normalized()
		var off = dir * rand_range(5.0, 45.0)
		_limbo.append([n, off, Vector3(rand_range(-0.6, 0.6), rand_range(-1.5, 1.2), rand_range(-0.6, 0.6)), Vector3(rand_range(-1, 1), rand_range(-1, 1), rand_range(-1, 1)) * 0.6])


func _limbo_update(delta: float) -> void:
	var pp = player().global_transform.origin
	for lb in _limbo:
		var n: Spatial = lb[0]
		if not is_instance_valid(n):
			continue
		lb[1] += lb[2] * delta
		n.global_transform.origin = pp + lb[1]
		n.rotation += lb[3] * delta


## world.gd: the void let go of you (you landed in the next sector). Not of the mechanism.
func left_void() -> void:
	if _streaks and is_instance_valid(_streaks):
		_streaks.queue_free()
	_streaks = null
	for lb in _limbo:
		if is_instance_valid(lb[0]):
			lb[0].queue_free()
	_limbo.clear()
	if world.hud:
		world.hud.cine_line("", "")
	if _dust and is_instance_valid(_dust):
		_dust.queue_free()
	if is_instance_valid(khaby):
		khaby.visible = false
	_kgone = true


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
