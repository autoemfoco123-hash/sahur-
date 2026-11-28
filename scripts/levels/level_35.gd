extends LevelBase
## SECTOR 3.5 — SIX SEVEN ULTRA. (Godot 3)
## Past the maze the numbers stop being written and start being built: one hall, seventy-two
## metres a side and twenty-six high, every wall scrawled 6 7 6 7, the floor a grid of stone
## slabs each marked with a six or a seven, and in the middle a pit with no bottom. What lives
## in the pit is 67 with nothing held back: 6-7 ULTRA (enemies/ultra.gd, ultra_model.gd).
##
## The fight (the server decides, every machine plays it; each operative's own damage is worked
## out on their own machine, like everywhere else in the run):
##   its shield      a shell of drifting numbers: photos do nothing through it. Four hush
##                   anchors stand in the corners; switch on all four (e) and the shield breaks
##                   for 13 s. Then photograph its face (f): a photo hurts it by how good it is.
##   slam            a hand rises over someone and comes down: get out of the red circle. The
##                   shockwave around it knocks you down too, unless you are in the air.
##   sweep           a hand drags across the floor round the pit: jump over it.
##   scream          it draws breath, then screams: anyone it can see takes it. Get behind a
##                   pillar.
##   call            SIX! the slabs marked 6 drop into the dark (SEVEN!: the sevens). Stand on
##                   the other number, or a plain slab. In the end it calls both, one after the
##                   other.
##   phases          at two thirds and one third it gets angrier: its shield closes again,
##                   it attacks faster, the lights start to fail.
## Somebody down is sent back in after a while (if anyone is still standing); everybody down,
## and hush sends the whole team back in, three times. Then it is over.

const UltraAI := preload("res://scripts/enemies/ultra.gd")
const TILE = 6.0
const N = 12                     # slabs a side: 72 m
const WALL_H = 26.0
const T = 0.28
const FALL_Y = -6.0
const SHIELD_DOWN = 13.0
const REVIVE_AFTER = 12.0
const REINFORCEMENTS = 3
const PIT = [Vector2(5, 5), Vector2(5, 6), Vector2(6, 5), Vector2(6, 6)]
const ANCHOR_TILES = [Vector2(2, 2), Vector2(9, 2), Vector2(9, 9), Vector2(2, 9)]
const PILLAR_TILES = [Vector2(4, 2), Vector2(7, 2), Vector2(9, 4), Vector2(9, 7), Vector2(7, 9), Vector2(4, 9), Vector2(2, 7), Vector2(2, 4)]
const PILLAR_R = 1.8
const LAMP_N = 8             # the hanging lamps: the same on every quality
const LAMP_RING = 24.5
const LAMP_Y = 21.5
const LAMP_ENERGY = 3.4
const LAMP_POWER = 0.62      # how bright their pools are on the floor (arena_lit.shader)
const ARENA_AMBIENT = 0.2
const SWEEP_R = [6.4, 18.0]
const MSG = {
	"slam": "its hand came down on the number you were standing on.\nhush found what was left in the shape of a seven.",
	"wave": "the floor jumped when its hand hit it.\nyou did not.",
	"sweep": "it swept the floor clean.\nyou were on the floor.",
	"scream": "you heard 6-7 ultra scream.\nnothing else will ever fit in your head again.",
	"fall": "the floor under you was the number it called.\nthere is no bottom down there.",
}

var ultra
var tiles = {}               # cell -> {kind (6 / 7 / 0 plain), body, mesh, y, st, t, warn, hold}
var anchors = []             # {pos, on, light, beam, band}
var pillars = []
var lamps = []
var fight = 0                # 0 waiting · 1 rising · 2 fighting · 3 it is dead
var hp = 1.0
var hp_max = 1.0
var phase = 1
var shield = true
var shield_left = 0.0        # every machine: seconds of shield-down left (for the hud)
var center = Vector3.ZERO
var _rise_in = -1.0          # server: seconds until it rises
var _fight_in = -1.0
var _next_attack = 4.0
var _last = ""
var _last_call = -100.0
var _clock = 0.0
var _followup = []           # server: [seconds, type, args] queued attacks
var _reinf = REINFORCEMENTS
var _dead_since = {}
var _revive_t = 1.0
var _deflect_said = {}
var _regen_wait = 0.0
var _sweeps = []             # this machine: live sweeps to dodge {a0, a1, t, tel, dur, hit, prev}
var _call_fx = -1.0
var _warns = []
var _tile_mats = {}
var _wall_m: ShaderMaterial
var lit_mats = []            # the hall's surfaces (arena_lit.shader); photo.gd turns them up too
var _mm = {}                 # kind -> MultiMesh (every slab of a kind is one draw)
var _shaft_mat: ShaderMaterial
var _ring_shader: Shader
var _arc_shader: Shader
var _flicker = 0.0
var _waves = []              # scream shockwaves {node, t}
var _here_was = false


func build() -> void:
	mono = true
	revive_wakes = false
	extent = Vector2(N * TILE, N * TILE)
	center = origin + Vector3(extent.x * 0.5, 0, extent.y * 0.5)
	env({
		"bg": Color(0, 0, 0), "ambient": Color(1, 1, 1), "ambient_energy": 0.26,
		"fog_color": Color(0.012, 0.012, 0.012), "fog_begin": 14.0, "fog_end": 95.0, "fog_curve": 1.25,
		"tint": Vector3(1.02, 1.0, 0.98), "contrast": 1.22, "saturation": 1.0, "mono": true,
	})
	boot_goggles = true
	greeter = ""
	chalk = Color(0.92, 0.92, 0.92, 0.95)
	drain_rate = 0.0
	view_far = 110.0
	exit_z = origin.z + 6.5 * TILE
	make_nav(Vector2(0, 0), extent, 2.0)
	_layout_tiles()
	_build_tiles()
	_build_walls()
	_build_pillars()
	_build_anchors()
	add_mission("ultra", "put 6-7 ultra down", 1, "")
	var ent_z = entry_z if has_entry else origin.z + 3.0 * TILE
	spawn_player(Vector3(origin.x + 2.0, 0.2, ent_z), -PI * 0.5)
	if has_entry:
		# sent back in, you come in at the door facing the pit
		arrive_pos = Vector3(origin.x + 1.2, 0.2, entry_z)
		var to = center - arrive_pos
		arrive_yaw = atan2(-to.x, -to.z)
	ultra = enemy(UltraAI, "ultra", center)
	ending_text = "6-7 ultra went back down into its pit, still counting.\nsix. seven. six.\n\nhush has the photographs now.\nnobody at hush wants to look at them."
	if world.headless:
		return
	_build_pit()
	_build_lamps()
	_wall_numbers()
	note(Vector3(origin.x + 2.6, 0.0, ent_z + 1.4), "hush · last briefing · sector 3.5\n\nthis is where the numbers come from.\nit lives in the pit. it will not come out. it does not need to.\n\nits shield: photos do nothing through it.\nthe four hush anchors in the corners break it.\nswitch on all four (e), then photograph its face (f). the better the photo, the more it hurts.\n\nred circle: get out.  low arm: jump.\nwhen it breathes in: get behind a pillar.\nwhen it calls a number: get off that number.")
	ir_mark(Vector3(origin.x + 4.0, 0.02, ent_z), 0.0, "anchors in the corners", 110).rotation = Vector3(-PI / 2, -PI * 0.5, 0)


# ------------------------------------------------------------------ the floor
func _tile_center(c: Vector2) -> Vector3:
	return origin + Vector3((c.x + 0.5) * TILE, 0, (c.y + 0.5) * TILE)


func _cell_at(p: Vector3) -> Vector2:
	return Vector2(floor((p.x - origin.x) / TILE), floor((p.z - origin.z) / TILE))


## Every slab a six or a seven, mixed so that from any slab there is always another number
## one step away; plain slabs (they never fall) round the pit, under the pillars and the
## anchors, at the doors.
func _layout_tiles() -> void:
	var plain = {}
	for x in range(4, 8):
		for y in range(4, 8):
			plain[Vector2(x, y)] = true
	for c in ANCHOR_TILES + PILLAR_TILES:
		plain[c] = true
	if has_entry:
		plain[_cell_at(Vector3(origin.x + 1.0, 0, entry_z))] = true
	plain[_cell_at(Vector3(origin.x + extent.x - 1.0, 0, exit_z))] = true
	for x in N:
		for y in N:
			var c = Vector2(x, y)
			if c in PIT:
				continue
			var k = 0 if plain.has(c) else (6 if rng.randf() < 0.5 else 7)
			tiles[c] = {"kind": k, "body": null, "shape": null, "idx": 0, "y": 0.0, "v": 0.0, "st": "up", "t": 0.0, "warn": 0.0, "hold": 0.0}
	# nobody may be stuck on an island of one number
	for it in 6:
		for x in N:
			for y in N:
				var c = Vector2(x, y)
				if not tiles.has(c) or tiles[c].kind == 0:
					continue
				var ok = false
				for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					var nb = tiles.get(c + d)
					if nb and nb.kind != tiles[c].kind:
						ok = true
				if not ok:
					tiles[c].kind = 13 - tiles[c].kind


func _tile_mat(kind: int) -> Material:
	if _tile_mats.has(kind):
		return _tile_mats[kind]
	var m = _lit_mat(0, "res://textures/%s.png" % {6: "tile_6", 7: "tile_7", 0: "tile_safe"}[kind], TILE, 0.82 if kind != 0 else 0.95)
	_tile_mats[kind] = m
	return m


## The hall's own surfaces are lit in arena_lit.shader (the lamps, the boss's glow, the anchors),
## never by real lights: the same picture on every machine and quality, in one pass.
func _lit_mat(mode: int, tex: String, scale: float, tint: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = load("res://scripts/arena_lit.shader")
	m.set_shader_param("mode", mode)
	m.set_shader_param("albedo_tex", load(tex))
	m.set_shader_param("tex_scale", scale)
	m.set_shader_param("tint", Vector3(tint, tint, tint))
	m.set_shader_param("center", center)
	m.set_shader_param("ring_r", LAMP_RING)
	m.set_shader_param("lamp_y", LAMP_Y - 0.8)
	m.set_shader_param("lamp_n", LAMP_N)
	m.set_shader_param("lamp_power", LAMP_POWER)
	m.set_shader_param("ambient", ARENA_AMBIENT)
	lit_mats.append(m)
	return m


## Every frame: the lamps' energies (they fail in the last phase), the boss's glow, the anchors.
func _lit_update() -> void:
	if lit_mats.empty():
		return
	var e = []
	for k in LAMP_N:
		e.append(lamps[k].light_energy / LAMP_ENERGY if k < lamps.size() else 1.0)
	var e0 = Plane(e[0], e[1], e[2], e[3])
	var e1 = Plane(e[4], e[5], e[6], e[7])
	var g = Plane(0, 0, 0, 0)
	if is_instance_valid(ultra) and ultra.model.visible and fight >= 1:
		var gp = ultra.face_world()
		g = Plane(gp.x, gp.y, gp.z, ultra.glow_energy() * 0.35)
	var an = []
	for i in 4:
		var a = anchors[i] if i < anchors.size() else null
		an.append(Plane(a.pos.x, a.pos.y + 3.6, a.pos.z, 1.0 if a.on else 0.0) if a else Plane())
	for m in lit_mats:
		m.set_shader_param("lamp_e0", e0)
		m.set_shader_param("lamp_e1", e1)
		m.set_shader_param("glow", g)
		m.set_shader_param("anc0", an[0])
		m.set_shader_param("anc1", an[1])
		m.set_shader_param("anc2", an[2])
		m.set_shader_param("anc3", an[3])


func _build_tiles() -> void:
	for c in tiles:
		var t = tiles[c]
		var p = _tile_center(c)
		var sb = StaticBody.new()
		sb.collision_layer = Geo.LAYER_WORLD
		sb.collision_mask = 0
		geo.add_child(sb)
		sb.global_transform.origin = p + Vector3(0, -0.3, 0)
		var cs = CollisionShape.new()
		var bs = BoxShape.new()
		bs.extents = Vector3(TILE * 0.5, 0.3, TILE * 0.5)
		cs.shape = bs
		sb.add_child(cs)
		t.body = sb
		t.shape = cs
	if world.headless:
		return
	var count = {}
	for c in tiles:
		var k = tiles[c].kind
		tiles[c].idx = count.get(k, 0)
		count[k] = tiles[c].idx + 1
	for k in count:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.box(Vector3(TILE - 0.05, 0.6, TILE - 0.05))
		mm.instance_count = count[k]
		var mmi = MultiMeshInstance.new()
		mmi.multimesh = mm
		mmi.material_override = _tile_mat(k)
		geo.add_child(mmi)
		_mm[k] = mm
	for c in tiles:
		_tile_draw(tiles[c], tiles[c].body.global_transform.origin)


## Where a slab is drawn (its collision body is moved separately).
func _tile_draw(t: Dictionary, at: Vector3) -> void:
	var mm = _mm.get(t.kind)
	if mm:
		mm.set_instance_transform(t.idx, Transform(Basis(), at))


# ------------------------------------------------------------------ the hall
func _wall_mat() -> ShaderMaterial:
	if _wall_m == null:
		_wall_m = _lit_mat(1, "res://textures/wall_67.png", 3.2, 0.62)
	return _wall_m


func _build_walls() -> void:
	var w = extent.x
	var d = extent.y
	var mat = null if world.headless else _wall_mat()
	var show = not world.headless
	var segs = []
	segs.append([Vector3(w * 0.5, WALL_H * 0.5, 0), Vector3(w + T, WALL_H, T)])
	segs.append([Vector3(w * 0.5, WALL_H * 0.5, d), Vector3(w + T, WALL_H, T)])
	segs += _door_wall(0.0, d, entry_z - origin.z if has_entry else -1.0)
	segs += _door_wall(w, d, exit_z - origin.z)
	for s in segs:
		Geo.solid(geo if show else world, s[1], origin + s[0], mat, null, show)
		nav.block_box(origin + s[0], s[1])
	# the ceiling, far up in the dark
	var cm = null
	if show:
		cm = _lit_mat(1, "res://textures/ceiling_67.png", 5.0, 0.3)
	Geo.solid(geo if show else world, Vector3(w + 2, 0.6, d + 2), origin + Vector3(w * 0.5, WALL_H + 0.3, d * 0.5), cm, null, show)
	var doorways = [Vector2(origin.x + w, exit_z)]
	if has_entry:
		doorways.append(Vector2(origin.x, entry_z))
	for dw in doorways:
		nav.block_box(Vector3(dw.x, 0, dw.y), Vector3(T + 0.6, 2.0, DOOR_W + 0.3))


func _door_wall(x: float, d: float, dz: float) -> Array:
	if dz < 0.0:
		return [[Vector3(x, WALL_H * 0.5, d * 0.5), Vector3(T, WALL_H, d + T)]]
	var z0 = -T * 0.5
	var z1 = d + T * 0.5
	var a = dz - DOOR_W * 0.5
	var b = dz + DOOR_W * 0.5
	return [
		[Vector3(x, WALL_H * 0.5, (z0 + a) * 0.5), Vector3(T, WALL_H, a - z0)],
		[Vector3(x, WALL_H * 0.5, (b + z1) * 0.5), Vector3(T, WALL_H, z1 - b)],
		[Vector3(x, (DOOR_H + WALL_H) * 0.5, dz), Vector3(T, WALL_H - DOOR_H, DOOR_W)],
	]


## The pit: a square shaft with no bottom, its walls black and wet.
func _build_pit() -> void:
	var m = Mats.std(Color(0.035, 0.035, 0.035), 0.4)
	var h = 46.0
	var half = TILE
	for s in [[Vector3(0, -h * 0.5, -half - 0.2), Vector3(half * 2 + 0.8, h, 0.4)], [Vector3(0, -h * 0.5, half + 0.2), Vector3(half * 2 + 0.8, h, 0.4)], [Vector3(-half - 0.2, -h * 0.5, 0), Vector3(0.4, h, half * 2)], [Vector3(half + 0.2, -h * 0.5, 0), Vector3(0.4, h, half * 2)]]:
		var mi = Models.part(geo, Models.box(s[1]), m, center + s[0])
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF


func _build_pillars() -> void:
	var mat = null if world.headless else _wall_mat()
	for c in PILLAR_TILES:
		var p = _tile_center(c)
		pillars.append(p)
		var sb = StaticBody.new()
		sb.collision_layer = Geo.LAYER_WORLD
		sb.collision_mask = 0
		(geo if not world.headless else world).add_child(sb)
		sb.global_transform.origin = p + Vector3(0, WALL_H * 0.5, 0)
		var cs = CollisionShape.new()
		var sh = CylinderShape.new()
		sh.radius = PILLAR_R
		sh.height = WALL_H
		cs.shape = sh
		sb.add_child(cs)
		nav.block_box(p, Vector3(PILLAR_R * 2, 2, PILLAR_R * 2))
		if world.headless:
			continue
		var mi = MeshInstance.new()
		mi.mesh = Models.cyl(PILLAR_R, PILLAR_R, WALL_H, 28, 8)
		mi.material_override = mat
		sb.add_child(mi)
		# a heavy plinth and a capital
		Models.part(sb, Models.cyl(PILLAR_R + 0.35, PILLAR_R + 0.5, 1.0, 28, 1), mat, Vector3(0, -WALL_H * 0.5 + 0.5, 0))
		Models.part(sb, Models.cyl(PILLAR_R + 0.6, PILLAR_R + 0.2, 1.4, 28, 1), mat, Vector3(0, WALL_H * 0.5 - 0.7, 0))


## The four hush anchors: black pylons with a ring of lamps; on, a beam goes up to the ceiling.
func _build_anchors() -> void:
	for i in ANCHOR_TILES.size():
		var p = _tile_center(ANCHOR_TILES[i])
		var a = {"pos": p, "on": false, "light": null, "beam": null, "band": null}
		anchors.append(a)
		var sb = Geo.solid(geo if not world.headless else world, Vector3(0.9, 3.2, 0.9), p + Vector3(0, 1.6, 0), null if world.headless else Mats.std(Color(0.06, 0.06, 0.065), 0.35, 0.6), nav, not world.headless)
		if world.headless:
			continue
		Models.part(sb, Models.box(Vector3(2.0, 0.4, 2.0)), Mats.std(Color(0.1, 0.1, 0.1), 0.6, 0.4), Vector3(0, -1.4, 0))
		var band_m = Mats.glow(Color(0.25, 0.25, 0.25), 0.2)
		band_m.flags_unshaded = true
		var band = Models.part(sb, Models.box(Vector3(1.0, 0.22, 1.0)), band_m, Vector3(0, 1.0, 0))
		a.band = band
		var l = Geo.label3d(sb, "hush · anchor %d" % (i + 1), Vector3(0, 0.1, -0.47), 40, Color(0.85, 0.85, 0.85))
		l.rotation.y = 0.0
		for s in [1, 2, 3]:
			var l2 = Geo.label3d(sb, "hush · anchor %d" % (i + 1), Vector3(0, 0.1, 0), 40, Color(0.85, 0.85, 0.85))
			l2.rotation.y = s * PI * 0.5
			l2.translation = Vector3(sin(s * PI * 0.5), 0, cos(s * PI * 0.5)) * -0.47 + Vector3(0, 0.1, 0)
		var light = Geo.omni(geo, p + Vector3(0, 3.6, 0), Color(1, 1, 1), 2.2, 10.0)
		light.visible = false
		a.light = light
		var beam = MeshInstance.new()
		beam.mesh = Models.cyl(0.35, 0.35, WALL_H - 3.2, 12, 1)
		beam.material_override = _beam_mat()
		beam.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		geo.add_child(beam)
		beam.global_transform.origin = p + Vector3(0, 3.2 + (WALL_H - 3.2) * 0.5, 0)
		beam.visible = false
		a.beam = beam
		if player():
			Interactable.make(world, p + Vector3(0, 1.3, 0), 1.1, "switch on the anchor", self, "_use_anchor", [i], false)


func _beam_mat() -> Material:
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.albedo_color = Color(0.35, 0.37, 0.4, 0.5)
	return m


## Hanging lamps over the floor, each with a shaft of light under it.
func _build_lamps() -> void:
	var n = LAMP_N
	var shade_m = Mats.std(Color(0.05, 0.05, 0.05), 0.5, 0.7)
	var disc_m = Mats.glow(Color(1, 1, 1), 4.0)
	disc_m.flags_unshaded = true
	for k in n:
		var a = TAU * (k + 0.5) / n
		# out over the outer floor, cones narrow enough never to reach it (on GLES2 every light
		# that touches a mesh is another pass over it, whatever its cull mask)
		var p = center + Vector3(sin(a), 0, cos(a)) * LAMP_RING + Vector3(0, LAMP_Y, 0)
		var shade = Models.part(geo, Models.cyl(0.5, 2.0, 1.4, 20, 1), shade_m, p)
		shade.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		Models.part(geo, Models.cyl(1.85, 1.85, 0.05, 20, 1), disc_m, p + Vector3(0, -0.72, 0))
		Models.part(geo, Models.cyl(0.05, 0.05, WALL_H - p.y, 6, 1), shade_m, p + Vector3(0, (WALL_H - p.y) * 0.5 + 0.7, 0))
		var sp = SpotLight.new()
		sp.light_color = Color(1.0, 0.98, 0.95)
		sp.light_energy = LAMP_ENERGY
		sp.spot_range = 25.0
		sp.spot_angle = 30.0
		sp.spot_attenuation = 1.1
		sp.light_cull_mask = 1
		sp.shadow_enabled = k % 4 == 0 and int(Game.settings.gfx) >= 2
		geo.add_child(sp)
		sp.global_transform.origin = p + Vector3(0, -0.8, 0)
		sp.rotation_degrees = Vector3(-90, 0, 0)
		lamps.append(sp)
		var shaft = MeshInstance.new()
		shaft.mesh = Models.cyl(1.9, 7.0, 21.0, 24, 1)
		shaft.material_override = _shaft()
		shaft.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		geo.add_child(shaft)
		shaft.global_transform.origin = p + Vector3(0, -0.8 - 10.5, 0)


func _shaft() -> ShaderMaterial:
	if _shaft_mat:
		return _shaft_mat
	var sh = Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float power = 1.0;
void fragment() {
	float f = abs(dot(NORMAL, VIEW));
	float down = clamp(UV.y, 0.0, 1.0);
	ALBEDO = vec3(0.9, 0.92, 1.0) * f * f * (1.0 - down * 0.85) * 0.05 * power;
}
"""
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = sh
	return _shaft_mat


## The walls say it in letters fifteen metres tall.
func _wall_numbers() -> void:
	var f = UI.font("hand", 220)
	for s in [[Vector3(extent.x * 0.5, 13.0, 0.2), 0.0, "6"], [Vector3(extent.x * 0.5, 13.0, extent.y - 0.2), PI, "7"], [Vector3(extent.x - 0.2, 14.0, extent.y * 0.25), -PI * 0.5, "6 7"], [Vector3(0.2, 14.0, extent.y * 0.75), PI * 0.5, "7 6"]]:
		var l = Label3D.new()
		l.text = s[2]
		l.font = f
		l.pixel_size = 0.07
		l.modulate = Color(0.05, 0.05, 0.05, 0.92)
		l.shaded = true
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		geo.add_child(l)
		l.global_transform.origin = origin + s[0]
		l.rotation.y = s[1]


# ------------------------------------------------------------------ arriving
func enter(boot: bool) -> void:
	if fight == 1 or fight == 2:
		ambient("amb_ultra", -3.0, "amb_heavy", -16.0)
	else:
		ambient("amb_heavy", -9.0, "amb_67", -20.0)
	Audio.set_reverb(0.95, 0.42, 0.3)
	if player():
		player().step_sound = "step_concrete"
		player().step_volume = -14.0
		world.set_dust(200)
	if boot:
		boot_goggles_now()


## Somebody got here: in a few seconds it comes up out of the pit.
func start_wave() -> void:
	wave_started = true
	if authority() and fight == 0 and _rise_in < 0.0:
		_rise_in = 4.0


func killer_id() -> String:
	return "ultra"


# ------------------------------------------------------------------ the server's fight
func _physics_process(delta: float) -> void:
	_clock += delta
	if authority():
		_server_step(delta)


func _server_step(delta: float) -> void:
	if _rise_in > 0.0:
		_rise_in -= delta
		if _rise_in <= 0.0:
			hp_max = 150.0 * (1.0 + 0.55 * max(0, _team_size() - 1))
			hp = hp_max
			_emit("rise", [hp_max])
			_fight_in = UltraAI.RISE_LEN + 0.5
	if _fight_in > 0.0:
		_fight_in -= delta
		if _fight_in <= 0.0 and fight == 1:
			_emit("fight", [])
			_next_attack = 3.0
	if fight != 2:
		return
	_revives(delta)
	if not shield:
		shield_left -= delta
		if shield_left <= 0.0:
			_emit("shield", [1, 0.0])
	for q in _followup.duplicate():
		q[0] -= delta
		if q[0] <= 0.0:
			_followup.erase(q)
			_emit(q[1], q[2])
	var ts = world.targets(index)
	if ts.empty():
		return
	_next_attack -= delta
	if _next_attack > 0.0:
		return
	_attack(ts)


func _team_size() -> int:
	if not Net.active():
		return 1
	var n = 0
	for pid in Net.round_ids():
		if not Net.players[pid].escaped:
			n += 1
	return int(max(n, 1))


## Pick its next move. Every attack says how long it keeps it busy; then a breath.
func _attack(ts: Array) -> void:
	var ph = phase - 1
	var near = []
	for t in ts:
		var r = _flat(t.pos, center)
		if r > SWEEP_R[0] + 0.5 and r < SWEEP_R[1] - 1.0:
			near.append(t)
	var opts = [["slam", 3.0]]
	if not near.empty():
		opts.append(["sweep", 2.6])
	if _last != "scream":
		opts.append(["scream", 1.4 + 0.3 * ph])
	if _clock - _last_call > 14.0 - ph * 3.0:
		opts.append(["call", 1.6 + 0.4 * ph])
	var tot = 0.0
	for o in opts:
		tot += o[1]
	var r = rng.randf() * tot
	var pick = "slam"
	for o in opts:
		r -= o[1]
		if r <= 0.0:
			pick = o[0]
			break
	_last = pick
	var busy = 3.0
	match pick:
		"slam":
			var t = ts[rng.randi() % ts.size()]
			var at = _floor_spot(t.pos)
			var tel = [1.6, 1.3, 1.05][ph]
			var h = 0 if ultra._to_model(at).x > 0.0 else 1
			_emit("slam", [h, at.x, at.z, tel])
			busy = tel + 2.4
			if ph >= 1 and rng.randf() < 0.45:
				var t2 = ts[rng.randi() % ts.size()]
				var at2 = _floor_spot(t2.pos + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)))
				_followup.append([0.55, "slam", [1 - h, at2.x, at2.z, tel]])
				busy += 0.6
		"sweep":
			var t = near[rng.randi() % near.size()]
			var ang = atan2(t.pos.x - center.x, t.pos.z - center.z)
			var h = 0 if ultra._to_model(t.pos).x > 0.0 else 1
			var sgn = 1.0 if rng.randf() < 0.5 else -1.0
			var tel = [1.35, 1.15, 0.95][ph]
			var dur = [1.05, 0.9, 0.75][ph]
			_emit("sweep", [h, ang - sgn * 1.4, ang + sgn * 1.4, tel, dur])
			busy = tel + dur + 2.0
		"scream":
			var inh = [2.4, 2.05, 1.75][ph]
			_emit("scream", [inh])
			busy = inh + 3.2
		"call":
			var n = 6 if rng.randf() < 0.5 else 7
			var warn = [2.6, 2.3, 2.0][ph]
			var hold = 4.2
			_emit("call", [n, warn, hold])
			_last_call = _clock
			busy = warn + 1.6
			if ph >= 2 and rng.randf() < 0.6:
				# and then the other one, as soon as the first comes back up
				_followup.append([warn + hold + 1.6, "call", [13 - n, warn * 0.85, hold]])
				_last_call = _clock + warn + hold
	_next_attack = busy + rng.randf_range([1.8, 1.1, 0.6][ph], [2.8, 1.8, 1.2][ph])


## Where a slam can land: on the floor, outside the pit.
func _floor_spot(p: Vector3) -> Vector3:
	var d = Vector3(p.x - center.x, 0, p.z - center.z)
	var r = d.length()
	if r < 8.0:
		d = (d.normalized() if r > 0.1 else Vector3(1, 0, 0)) * 8.0
	r = d.length()
	if r > 34.0:
		d = d * 34.0 / r
	return Vector3(center.x + d.x, origin.y, center.z + d.z)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Server: the fallen come back in after a while, as long as somebody is still standing.
func _revives(delta: float) -> void:
	if not Net.active():
		return
	_revive_t -= delta
	if _revive_t > 0.0:
		return
	_revive_t = 1.0
	var anyone = not world.targets(index).empty()
	for pid in Net.round_ids():
		var p = Net.players[pid]
		if p.alive or p.escaped or int(p.get("sector", 0)) != index:
			_dead_since.erase(pid)
			continue
		if not _dead_since.has(pid):
			_dead_since[pid] = _clock
		elif anyone and _clock - _dead_since[pid] >= REVIVE_AFTER:
			_dead_since.erase(pid)
			Net.event("revived", [pid, index])


## Server (Net._check_round_end): everybody is down. While it lives, hush sends the whole team
## back in, a few times.
func round_hold() -> bool:
	if (fight != 1 and fight != 2) or _reinf <= 0:
		return false
	_reinf -= 1
	_emit("reinforce", [_reinf])
	get_tree().create_timer(6.0).connect("timeout", self, "_revive_all")
	return true


func _revive_all() -> void:
	if not Net.active():
		return
	for pid in Net.round_ids():
		var p = Net.players[pid]
		if not p.alive and not p.escaped:
			Net.event("revived", [pid, index])
	_dead_since = {}


## Offline (world.gd): you are down. Hush sends you back in a few times; after that the run
## starts again right here, at the door of this hall.
func offline_retry() -> bool:
	if (fight == 1 or fight == 2) and _reinf > 0:
		_reinf -= 1
		get_tree().create_timer(1.6).connect("timeout", self, "_said_reinf")
		return true
	if Game.LEVELS.has("35"):
		Game.current_level = "35"
	return false


func _said_reinf() -> void:
	if here():
		world.hud.subtitle("hush sent you back in.   %d more time%s." % [_reinf, "" if _reinf == 1 else "s"], 4.0)


## Server: requests from operatives in here.
func on_request(pid: int, type: String, args: Array) -> void:
	var t = world.target_by_id(pid)
	match type:
		"anchor":
			var i = int(args[0]) if args.size() > 0 else -1
			if i < 0 or i >= anchors.size() or anchors[i].on or fight != 2 or not shield or t == null:
				return
			if _flat(t.pos, anchors[i].pos) > 4.2:
				return
			_emit("anchor", [i, pid])
			var all = true
			for a in anchors:
				all = all and (a.on or a == anchors[i])
			if all:
				_emit("shield", [0, SHIELD_DOWN])
		"photo":
			if args.empty() or str(args[0]) != "ultra" or fight != 2:
				return
			var score = float(args[1]) if args.size() > 1 else 0.0
			if shield:
				if _clock - float(_deflect_said.get(pid, -100.0)) > 6.0:
					_deflect_said[pid] = _clock
					_emit("deflect", [pid])
				return
			var dmg = max(0.0, (score - 20.0) / 7.0)
			if dmg <= 0.0:
				return
			hp = max(0.0, hp - dmg)
			_emit("hp", [hp, hp_max, pid, dmg])
			if hp <= 0.0:
				_emit("die", [pid])
				mission_set("ultra", 1, pid)
			elif phase == 1 and hp < hp_max * 0.67:
				_emit("phase", [2])
			elif phase == 2 and hp < hp_max * 0.34:
				_emit("phase", [3])


# ------------------------------------------------------------------ every machine
func _use_anchor(i: int) -> void:
	if fight != 2:
		world.hud.subtitle("nothing happens.   not yet." if fight < 2 else "it is over.", 2.0)
		return
	if anchors[i].on:
		world.hud.subtitle("this one is on.   the others.", 2.0)
		return
	if not shield:
		world.hud.subtitle("its shield is already down.   photograph it.", 2.0)
		return
	if Net.active():
		Net.request("anchor", [i])
	else:
		on_request(1, "anchor", [i])


func net_event(type: String, args: Array) -> void:
	var hud = world.hud if here() else null
	match type:
		"rise":
			if fight != 0:
				return
			fight = 1
			hp_max = float(args[0])
			hp = hp_max
			ultra.rise()
			if here():
				ambient("amb_ultra", -3.0, "amb_heavy", -16.0)
				hud.subtitle("something is coming up out of the pit.", 4.0)
		"fight":
			if fight != 1:
				return
			fight = 2
			if hud:
				hud.subtitle("6-7 ULTRA.   switch on the four anchors, then photograph its face.", 5.0)
		"slam":
			var at = Vector3(args[1], origin.y, args[2])
			var tel: float = args[3]
			ultra.slam(int(args[0]), at, tel)
			_warn_ring(at, tel + UltraAI.STRIKE)
			get_tree().create_timer(tel + UltraAI.STRIKE).connect("timeout", self, "_slam_hit", [at])
		"sweep":
			ultra.sweep(int(args[0]), args[1], args[2], args[3], args[4])
			_sweeps.append({"a0": args[1], "a1": args[2], "t": 0.0, "tel": args[3], "dur": args[4], "hit": false, "prev": args[1]})
			_warn_arc(args[1], args[2], args[3], args[4])
		"scream":
			ultra.scream(args[0])
			if hud:
				hud.subtitle("it is breathing in.   get behind a pillar.", float(args[0]) + 0.5)
			get_tree().create_timer(float(args[0]) + 0.25).connect("timeout", self, "_scream_hit")
		"call":
			var n: int = args[0]
			ultra.call_number(n, args[1])
			for c in tiles:
				var t = tiles[c]
				if t.kind == n:
					t.st = "shake"
					t.t = 0.0
					t.warn = args[1]
					t.hold = args[2]
			if hud:
				hud.subtitle("6-7 ULTRA:   %s.   get off the %ss." % ["SIX" if n == 6 else "SEVEN", "six" if n == 6 else "seven"], float(args[1]) + 0.8)
			get_tree().create_timer(float(args[1])).connect("timeout", self, "_tiles_fall", [n])
		"anchor":
			var i: int = args[0]
			anchors[i].on = true
			_anchor_look(i, true)
			if not world.headless:
				Audio.play_at("anchor_on", anchors[i].pos + Vector3(0, 2.5, 0), world, 6.0, 1.0, 90.0)
			if hud:
				var n = 0
				for a in anchors:
					n += 1 if a.on else 0
				var who = "you" if args[1] == Net.my_id() or not Net.active() else Net.pname(args[1])
				hud.subtitle("%s switched on anchor %d.   %d of 4." % [who, i + 1, n], 3.0)
		"shield":
			var on = int(args[0]) == 1
			shield = on
			ultra.set_shield(on)
			if on:
				for i in anchors.size():
					anchors[i].on = false
					_anchor_look(i, false)
				if hud and fight == 2:
					hud.subtitle("its shield is closing again.   the anchors went out.", 3.5)
			else:
				shield_left = float(args[1])
				ultra.stagger()
				if hud:
					hud.subtitle("THE SHIELD IS DOWN.   photograph its face.   now.", 4.0)
					world.flash(0.8)
		"deflect":
			if hud and (args[0] == Net.my_id() or not Net.active()):
				hud.subtitle("the shield swallowed the flash.   the anchors first.", 3.0)
		"hp":
			hp = float(args[0])
			hp_max = float(args[1])
			ultra.hurt()
			if hud and (args[2] == Net.my_id() or not Net.active()):
				hud.subtitle("it felt that.   -%d" % int(round(float(args[3]))), 1.6)
		"phase":
			phase = int(args[0])
			ultra.set_phase(phase)
			if not shield:
				shield = true
				ultra.set_shield(true)
				for i in anchors.size():
					anchors[i].on = false
					_anchor_look(i, false)
			if hud:
				hud.subtitle("it is angrier.   the shield closed, the anchors went out." if phase == 2 else "it is losing it.   the lights are going.", 4.0)
				player().add_trauma(0.7)
		"die":
			fight = 3
			shield = false
			ultra.die()
			for c in tiles:
				if tiles[c].st == "shake":
					tiles[c].st = "up"
			if here():
				Audio.ambient("amb_heavy", -12.0, 0, 6.0)
				Audio.ambient("", -30.0, 1, 3.0)
				var who = "you" if args[0] == Net.my_id() or not Net.active() else Net.pname(args[0])
				hud.subtitle("%s took the last photo.   it is going down." % who, 5.0)
				get_tree().create_timer(9.5).connect("timeout", self, "_after_death")
		"reinforce":
			_reinf = int(args[0])
			if here() or (world.player and world.my_out):
				world.hud.subtitle("hush is sending everybody back in.   %d more time%s." % [args[0], "" if int(args[0]) == 1 else "s"], 5.0)


func _after_death() -> void:
	if here():
		world.hud.subtitle("the door is open.   get out.", 4.0)


# ------------------------------------------------------------------ getting hurt (your machine)
func _hurt(amount: float, why: String, push := Vector3.ZERO) -> void:
	var pl = player()
	if pl == null or world.my_out or world.dying or world.completing or not here():
		return
	Game.brain_cells = max(0.0, Game.brain_cells - amount)
	_regen_wait = 4.5
	pl.add_trauma(clamp(amount / 50.0, 0.3, 1.0))
	world.flash(clamp(amount / 60.0, 0.25, 0.9))
	Audio.play("land_thud", -2.0, 0.7)
	if push != Vector3.ZERO:
		pl.knock(push)
	if Game.brain_cells <= 0.0:
		_die(why)


func _die(why: String) -> void:
	var msg: String = MSG.get(why, ultra.death_msg)
	world.kill("ultra", msg)
	if Net.active():
		Net.request("died", [msg])


func _me() -> Vector3:
	return player().global_transform.origin


func _slam_hit(at: Vector3) -> void:
	if not here() or world.my_out or world.dying:
		return
	var p = _me()
	var d = _flat(p, at)
	var away = Vector3(p.x - at.x, 0, p.z - at.z)
	away = away.normalized() if away.length() > 0.05 else Vector3(1, 0, 0)
	if d < 3.7 and p.y - origin.y < 3.0:
		_hurt(55.0, "slam", away * 11.0 + Vector3(0, 6.0, 0))
	elif d < 9.0 and player().is_on_floor():
		_hurt(12.0, "wave", away * 6.0 + Vector3(0, 3.5, 0))


func _scream_hit() -> void:
	_shockwave()
	if not here() or world.my_out or world.dying or not is_instance_valid(ultra):
		return
	var from = ultra.face_world()
	var to = player().eye_pos()
	var hit = world.get_world().direct_space_state.intersect_ray(from, to, [player(), ultra], Geo.LAYER_WORLD)
	if hit.empty():
		_hurt(45.0, "scream")
		player().add_trauma(1.0)
		_call_fx = 0.3
	else:
		player().add_trauma(0.45)


## Every frame on this machine: the sweeping hands, the falling floor, healing.
func _process(delta: float) -> void:
	var h = here()
	if h or (geo and geo.visible):
		_lit_update()
	if h != _here_was:
		_here_was = h
		if world.hud and not h:
			world.hud.boss(false)
	_tiles_step(delta)
	_waves_step(delta)
	for w in _warns.duplicate():
		w.t += delta
		if is_instance_valid(w.node):
			w.node.material_override.set_shader_param("prog", clamp(w.t / w.dur, 0.0, 1.0))
		if w.t > w.dur + 0.25:
			_warns.erase(w)
			if is_instance_valid(w.node):
				w.node.queue_free()
	if world.player == null:
		return
	for s in _sweeps.duplicate():
		s.t += delta
		if s.t > s.tel + s.dur + 0.2:
			_sweeps.erase(s)
			continue
		if s.t < s.tel or s.hit or not h or world.my_out or world.dying:
			continue
		var k = clamp((s.t - s.tel) / s.dur, 0.0, 1.0)
		var ang = lerp(s.a0, s.a1, k * k * (3.0 - 2.0 * k))
		var p = _me()
		var r = _flat(p, center)
		var pa = atan2(p.x - center.x, p.z - center.z)
		if r > SWEEP_R[0] - 0.5 and r < SWEEP_R[1] + 0.5 and _between(pa, s.prev, ang) and p.y - origin.y < 0.55:
			s.hit = true
			var tang = Vector3(cos(ang), 0, -sin(ang)) * sign(s.a1 - s.a0)
			_hurt(40.0, "sweep", tang * 12.0 + Vector3(0, 5.0, 0))
		s.prev = ang
	if not h:
		return
	# the fall
	if not world.my_out and not world.dying and not world.completing and _me().y < origin.y + FALL_Y:
		_die("fall")
	# the boss bar
	if world.hud and fight >= 1 and fight <= 2 and not world.dying and not world.my_out:
		var st = ""
		if shield:
			var n = 0
			for a in anchors:
				n += 1 if a.on else 0
			st = "shield up · anchors %d/4" % n
		else:
			st = "shield down · %d s" % int(ceil(max(shield_left, 0.0)))
		world.hud.boss(true, "6-7 ultra", hp / max(hp_max, 1.0), st, not shield)
	elif world.hud:
		world.hud.boss(false)
	if not shield:
		shield_left -= delta if not authority() else 0.0
	danger_bonus = 0.45 if fight == 2 else 0.0
	# brain cells come back slowly while nothing hits you
	if fight >= 1 and not world.dying and not world.my_out:
		_regen_wait -= delta
		if _regen_wait <= 0.0:
			Game.brain_cells = min(100.0, Game.brain_cells + delta * 3.0)
	# the negative flash of a call or a scream
	if _call_fx >= 0.0 and world.post:
		_call_fx += delta
		var inv = smoothstep(0.35, 0.5, _call_fx) * (1.0 - smoothstep(0.7, 1.0, _call_fx))
		world.post.set_shader_param("invert", inv if not world.dying else 0.0)
		if _call_fx > 1.1:
			_call_fx = -1.0
			world.post.set_shader_param("invert", 0.0)
	# phase 3: the lamps are failing
	if phase >= 3 and fight == 2:
		_flicker -= delta
		if _flicker <= 0.0:
			_flicker = rand_range(0.05, 0.4)
			for l in lamps:
				l.light_energy = LAMP_ENERGY * (rand_range(0.0, 0.4) if randf() < 0.35 else 1.0)
	elif fight == 3:
		for l in lamps:
			l.light_energy = move_toward(l.light_energy, LAMP_ENERGY, delta)


## Is angle a between b and c (the short way)?
func _between(a: float, b: float, c: float) -> bool:
	var span = wrapf(c - b, -PI, PI)
	var off = wrapf(a - b, -PI, PI)
	if span >= 0.0:
		return off >= -0.04 and off <= span + 0.04
	return off <= 0.04 and off >= span - 0.04


# ------------------------------------------------------------------ the floor falling
func _tiles_fall(n: int) -> void:
	if fight == 3:
		return
	var pp = player().global_transform.origin if player() else center
	var near = []
	for c in tiles:
		var t = tiles[c]
		if t.kind == n and t.st == "shake":
			t.st = "fall"
			t.t = 0.0
			t.v = 0.0
			if t.shape:
				t.shape.set_deferred("disabled", true)
			near.append([t.body.global_transform.origin.distance_to(pp), t.body.global_transform.origin])
	if here():
		_call_fx = 0.0
		near.sort_custom(self, "_asc0")
		for i in min(4, near.size()):
			Audio.play_at("tile_drop", near[i][1] + Vector3(0, 0.5, 0), world, 6.0, rand_range(0.8, 1.0), 70.0)


func _asc0(a, b) -> bool:
	return a[0] < b[0]


func _tiles_step(delta: float) -> void:
	for c in tiles:
		var t = tiles[c]
		if t.st == "up":
			continue
		t.t += delta
		var base = _tile_center(c) + Vector3(0, -0.3, 0)
		match t.st:
			"shake":
				var k = clamp(t.t / max(t.warn, 0.1), 0.0, 1.0)
				var sh = base + Vector3(rand_range(-1, 1), rand_range(-0.4, 0.4), rand_range(-1, 1)) * 0.045 * (0.3 + k)
				t.body.global_transform.origin = sh
				_tile_draw(t, sh)
				if t.t > t.warn + 1.0:
					t.st = "up"
					t.body.global_transform.origin = base
					_tile_draw(t, base)
			"fall":
				t.v += 22.0 * delta
				t.y -= t.v * delta
				t.body.global_transform.origin = base + Vector3(0, t.y, 0)
				_tile_draw(t, base + Vector3(0, t.y, 0))
				if t.y < -60.0:
					t.st = "down"
					t.t = 0.0
					_tile_draw(t, base + Vector3(0, -400, 0))
			"down":
				if t.t > t.hold - 0.6:
					t.st = "rise"
					t.t = 0.0
					t.y = -14.0
			"rise":
				var k = clamp(t.t / 1.3, 0.0, 1.0)
				t.y = -14.0 * pow(1.0 - k, 3.0)
				t.body.global_transform.origin = base + Vector3(0, t.y, 0)
				_tile_draw(t, base + Vector3(0, t.y, 0))
				if k >= 1.0:
					t.st = "up"
					t.y = 0.0
					t.body.global_transform.origin = base
					_tile_draw(t, base)
					if t.shape:
						t.shape.set_deferred("disabled", false)


# ------------------------------------------------------------------ the anchors
func _anchor_look(i: int, on: bool) -> void:
	var a = anchors[i]
	if a.light:
		a.light.visible = on
	if a.beam:
		a.beam.visible = on
	if a.band:
		var m: SpatialMaterial = a.band.material_override
		m.albedo_color = Color(1, 1, 1) if on else Color(0.25, 0.25, 0.25)
		m.emission = m.albedo_color


# ------------------------------------------------------------------ warnings and shockwaves
func _warn_ring(at: Vector3, wlen: float) -> void:
	if world.headless:
		return
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float prog = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.86, 0.93, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float fill = (1.0 - step(prog, r)) * (1.0 - step(1.0, r)) * 0.3;
	float pulse = 0.65 + 0.35 * sin(TIME * (10.0 + 30.0 * prog));
	ALBEDO = vec3(1.0, 0.08, 0.04) * (ring * 0.9 + fill) * pulse;
}
"""
	var m = ShaderMaterial.new()
	m.shader = _ring_shader
	var mi = MeshInstance.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(7.4, 7.4)
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_transform.origin = at + Vector3(0, 0.04, 0)
	_warns.append({"node": mi, "t": 0.0, "dur": wlen})


func _warn_arc(a0: float, a1: float, tel: float, dur: float) -> void:
	if world.headless:
		return
	if _arc_shader == null:
		_arc_shader = Shader.new()
		_arc_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float prog = 0.0;
uniform vec3 center;
uniform float a0;
uniform float a1;
uniform float rmin;
uniform float rmax;
varying vec3 wp;
void vertex() {
	wp = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 d = wp.xz - center.xz;
	float r = length(d);
	float ang = atan(d.x, d.y);
	float mid = (a0 + a1) * 0.5;
	float half = abs(a1 - a0) * 0.5;
	float rel = mod(ang - mid + 3.14159265, 6.2831853) - 3.14159265;
	float inside = step(abs(rel), half) * step(rmin, r) * step(r, rmax);
	float edge = smoothstep(half - 0.04, half, abs(rel)) + smoothstep(rmax - 0.5, rmax, r);
	float pulse = 0.6 + 0.4 * sin(TIME * 14.0);
	ALBEDO = vec3(1.0, 0.08, 0.04) * inside * (0.12 + 0.5 * clamp(edge, 0.0, 1.0)) * pulse * (1.0 - prog);
}
"""
	var m = ShaderMaterial.new()
	m.shader = _arc_shader
	m.set_shader_param("center", center)
	m.set_shader_param("a0", a0)
	m.set_shader_param("a1", a1)
	m.set_shader_param("rmin", SWEEP_R[0])
	m.set_shader_param("rmax", SWEEP_R[1])
	var mi = MeshInstance.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(SWEEP_R[1] * 2.0 + 1.0, SWEEP_R[1] * 2.0 + 1.0)
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_transform.origin = center + Vector3(0, 0.05, 0)
	_warns.append({"node": mi, "t": 0.0, "dur": tel + dur * 0.5})


## The scream, seen: a shell of pressure going out from its mouth.
func _shockwave() -> void:
	if world.headless or not is_instance_valid(ultra):
		return
	var mi = MeshInstance.new()
	mi.mesh = Models.sphere(1.0, -1.0, 32, 16)
	var m = load("res://scripts/ultra_model.gd").shield_mat()
	m.set_shader_param("hit", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_transform.origin = ultra.face_world()
	_waves.append({"node": mi, "t": 0.0, "mat": m})


func _waves_step(delta: float) -> void:
	for w in _waves.duplicate():
		w.t += delta
		if is_instance_valid(w.node):
			w.node.scale = Vector3.ONE * (2.0 + w.t * 70.0)
			w.mat.set_shader_param("power", max(0.0, 1.0 - w.t / 1.3) * 1.5)
		if w.t > 1.3:
			_waves.erase(w)
			if is_instance_valid(w.node):
				w.node.queue_free()
