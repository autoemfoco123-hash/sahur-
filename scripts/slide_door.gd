extends Spatial
## The electronic sliding door between two sectors (Godot 3): brushed steel, a small square
## window in the middle, a keypad light beside it. [E] on its front side (the sector you are
## leaving) slides it into the wall, and behind it is simply the next sector, already there.
## It closes again by itself. From the far side it does not open: the panel stays red.
## Built in world axes: the door plane is perpendicular to x; -x is the front (from_sector),
## +x is the next sector (or the corridor out, for the last one).

const W = LevelBase.DOOR_W      # opening width
const DH = LevelBase.DOOR_H     # opening height
const WIN = 0.3                 # the square window
const WIN_Y = 1.5               # window centre height
const SLAB_T = 0.06
const SPEED = 2.6               # metres per second

var world
var from_sector = 0
var to_sector = 1               # -1: the way out
var depth = 0.56                # how deep the doorway is (the walls it passes through)
var slab: Spatial
var open_amt = 0.0              # 0 closed .. 1 open
var want_open = false
var _close_t = 0.0
var _panel_t = 0.0
var _front_light: SpatialMaterial
var _back_light: SpatialMaterial
var _use                       # the [E] spot (only usable from the front)
var mono = false               # in a monochrome sector: greys, no signal colours


func setup(w, at: Vector3, from_s: int, to_s: int, wall_depth: float) -> void:
	world = w
	from_sector = from_s
	to_sector = to_s
	depth = wall_depth
	mono = from_s < w.levels.size() and w.levels[from_s].mono
	name = "Door%d" % from_s
	w.add_child(self)
	global_transform.origin = at
	_build()


func locked() -> bool:
	var lv = world.levels[from_sector] if from_sector < world.levels.size() else null
	return lv != null and lv.has_method("exit_locked") and lv.exit_locked()


func open() -> void:
	_close_t = 4.0
	if want_open:
		return
	want_open = true
	if not world.headless:
		Audio.play_at("door_slide", global_transform.origin + Vector3(0, 1.4, 0), world, 3.0, rand_range(0.97, 1.03), 35.0)


func close() -> void:
	if not want_open:
		return
	want_open = false
	if not world.headless:
		Audio.play_at("door_close", global_transform.origin + Vector3(0, 1.4, 0), world, 2.0, rand_range(0.97, 1.03), 35.0)


func deny() -> void:
	Audio.play_at("door_deny", global_transform.origin + Vector3(-depth * 0.5, 1.2, W * 0.5 + 0.32), world, 0.0, 1.0, 20.0)
	_panel_t = 0.6
	if _front_light:
		_front_light.albedo_color = _c(Color(1.0, 0.08, 0.05))


func _process(delta: float) -> void:
	var target = 1.0 if want_open else 0.0
	if open_amt != target:
		open_amt = move_toward(open_amt, target, delta * SPEED / W)
		var k = open_amt * open_amt * (3.0 - 2.0 * open_amt)
		slab.translation.z = -k * (W + 0.06)
	if want_open:
		_close_t -= delta
		if _close_t <= 0.0:
			if _someone_in_the_way():
				_close_t = 0.5
			else:
				close()
	if _use and world.player:
		# one way: from the far side the door does not answer
		_use.enabled = world.player.global_transform.origin.x < global_transform.origin.x - depth * 0.5
	_panel_t -= delta
	if _panel_t <= 0.0 and _front_light:
		_panel_t = 0.3
		if want_open:
			_front_light.albedo_color = _c(Color(0.25, 1.0, 0.45))
		elif locked():
			_front_light.albedo_color = _c(Color(1.0, 0.45, 0.05))
		else:
			_front_light.albedo_color = _c(Color(0.35, 0.85, 1.0))


## Nobody gets cut in half: stay open while an operative stands in the doorway.
func _someone_in_the_way() -> bool:
	var pts = []
	if world.player and not world.my_out:
		pts.append(world.player.global_transform.origin)
	for pid in world.avatars:
		var a = world.avatars[pid]
		if is_instance_valid(a) and a.visible:
			pts.append(a.global_transform.origin)
	for p in pts:
		var l = p - global_transform.origin
		if abs(l.x) < depth * 0.5 + 0.7 and abs(l.z) < W * 0.5 + 0.35:
			return true
	return false


# ------------------------------------------------------------------ model
func _build() -> void:
	slab = Spatial.new()
	slab.name = "slab"
	add_child(slab)
	# solid while closed: it moves with the slab
	var sb = StaticBody.new()
	sb.collision_layer = Geo.LAYER_WORLD
	slab.add_child(sb)
	var cs = CollisionShape.new()
	var sh = BoxShape.new()
	sh.extents = Vector3(0.06, DH * 0.5, W * 0.5)
	cs.shape = sh
	sb.add_child(cs)
	cs.translation = Vector3(0, DH * 0.5, 0)
	if world.headless:
		return
	var steel = Mats.std(Color(0.5, 0.52, 0.55), 0.38, 0.75)
	var dark = Mats.std(Color(0.06, 0.06, 0.065), 0.7)
	var lining = Mats.std(Color(0.34, 0.35, 0.37), 0.45, 0.7)
	# the slab: four steel pieces around the window, a kick plate, a rubber leading edge
	var lo = WIN_Y - WIN * 0.5
	var hi = WIN_Y + WIN * 0.5
	var side_w = (W - WIN) * 0.5
	_box(slab, Vector3(SLAB_T, lo, W), Vector3(0, lo * 0.5, 0), steel)
	_box(slab, Vector3(SLAB_T, DH - hi, W), Vector3(0, (hi + DH) * 0.5, 0), steel)
	for s in [-1.0, 1.0]:
		_box(slab, Vector3(SLAB_T, WIN, side_w), Vector3(0, WIN_Y, s * (WIN * 0.5 + side_w * 0.5)), steel)
	_box(slab, Vector3(SLAB_T + 0.012, 0.22, W - 0.04), Vector3(0, 0.13, 0), Mats.std(Color(0.3, 0.31, 0.33), 0.3, 0.85))
	_box(slab, Vector3(SLAB_T + 0.01, DH, 0.03), Vector3(0, DH * 0.5, W * 0.5 - 0.015), dark)
	# the window: a dark rubber gasket and wired safety glass
	for s in [-1.0, 1.0]:
		_box(slab, Vector3(SLAB_T + 0.02, 0.025, WIN + 0.05), Vector3(0, WIN_Y + s * (WIN * 0.5 + 0.0125), 0), dark)
		_box(slab, Vector3(SLAB_T + 0.02, WIN, 0.025), Vector3(0, WIN_Y, s * (WIN * 0.5 + 0.0125)), dark)
	var glass = SpatialMaterial.new()
	glass.flags_transparent = true
	glass.albedo_color = _c(Color(0.62, 0.74, 0.78, 0.16))
	glass.roughness = 0.05
	glass.metallic = 0.4
	glass.params_cull_mode = SpatialMaterial.CULL_DISABLED
	var q = QuadMesh.new()
	q.size = Vector2(WIN, WIN)
	var gm = MeshInstance.new()
	gm.mesh = q
	gm.material_override = glass
	gm.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	slab.add_child(gm)
	gm.translation = Vector3(0, WIN_Y, 0)
	gm.rotation_degrees = Vector3(0, 90, 0)
	# the doorway: steel lining, a threshold plate, the lintel, trims on both faces
	_box(self, Vector3(depth + 0.04, 0.012, W), Vector3(0, 0.006, 0), lining)
	_box(self, Vector3(depth, 0.05, W + 0.06), Vector3(0, DH + 0.025, 0), lining)
	for s in [-1.0, 1.0]:
		_box(self, Vector3(depth, DH, 0.03), Vector3(0, DH * 0.5, s * (W * 0.5 + 0.015)), lining)
		var fx = s * (depth * 0.5 + 0.012)
		for zs in [-1.0, 1.0]:
			_box(self, Vector3(0.024, DH + 0.1, 0.08), Vector3(fx, (DH + 0.1) * 0.5, zs * (W * 0.5 + 0.04)), dark)
		_box(self, Vector3(0.024, 0.09, W + 0.16), Vector3(fx, DH + 0.045, 0), dark)
	# keypad panels: front (blue = ready, amber = locked, green = open) and back (always red)
	_front_light = _panel(-1.0, _c(Color(0.35, 0.85, 1.0)))
	_back_light = _panel(1.0, _c(Color(1.0, 0.08, 0.05)))
	# a sign above the door, both sides
	var nxt = "exit" if to_sector < 0 else Game.INFO.get(Game.LEVELS[to_sector], {}).get("title", "")
	var here = Game.INFO.get(Game.LEVELS[from_sector], {}).get("title", "")
	Geo.label3d(self, nxt, Vector3(-depth * 0.5 - 0.03, DH + 0.32, 0), 40, _c(Color(0.55, 1.0, 0.6)) if to_sector < 0 else _c(Color(1.0, 0.78, 0.3)), -PI * 0.5)
	Geo.label3d(self, here, Vector3(depth * 0.5 + 0.03, DH + 0.32, 0), 40, Color(1, 1, 1, 0.45), PI * 0.5)
	# a cold light over each side so the steel reads
	for s in [-1.0, 1.0]:
		var l = Geo.omni(self, Vector3(s * (depth * 0.5 + 0.7), DH + 0.25, 0), _c(Color(0.85, 0.92, 1.0)), 1.1, 3.5)
		l.light_cull_mask = Geo.VIS_ACTOR
		l.add_to_group("lamp")
	Models.set_layers(self, 1 | Geo.VIS_ACTOR)
	if world.player:
		var at = global_transform.origin + Vector3(-depth * 0.5 - 0.45, 1.25, 0)
		_use = Interactable.make(self, at, 0.7, "open the door", world, "door_use", [self], false)


## Colour, or its grey in a monochrome sector.
func _c(col: Color) -> Color:
	if not mono:
		return col
	var l = col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	return Color(l, l, l, col.a)


func _panel(side: float, col: Color) -> SpatialMaterial:
	var x = side * (depth * 0.5 + 0.016)
	var z = (W * 0.5 + 0.32) * (-side)
	_box(self, Vector3(0.03, 0.22, 0.13), Vector3(x, 1.2, z), Mats.std(Color(0.1, 0.1, 0.11), 0.5, 0.4))
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = col
	_box(self, Vector3(0.036, 0.035, 0.09), Vector3(x, 1.27, z), m)
	for i in 3:
		_box(self, Vector3(0.034, 0.025, 0.025), Vector3(x, 1.18 - i * 0.035, z - 0.03), Mats.std(Color(0.4, 0.4, 0.42), 0.4, 0.6))
		_box(self, Vector3(0.034, 0.025, 0.025), Vector3(x, 1.18 - i * 0.035, z + 0.03), Mats.std(Color(0.4, 0.4, 0.42), 0.4, 0.6))
	return m


func _box(parent: Spatial, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance:
	var mi = Models.part(parent, Models.box(size), mat, pos)
	return mi
