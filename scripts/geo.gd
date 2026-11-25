class_name Geo
## Level geometry helpers. (Godot 3 / GLES2)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_INTERACT := 4
const LAYER_ENEMY := 8
## Render layer of things lit by real lights (brainrots, props). The baked office is not on it,
## so lamps cost nothing on walls, floor and ceiling.
const VIS_ACTOR := 16


static func solid(parent: Spatial, size: Vector3, pos: Vector3, mat: Material, nav = null, visible := true) -> StaticBody:
	var sb = StaticBody.new()
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	parent.add_child(sb)
	sb.translation = pos
	var cs = CollisionShape.new()
	var sh = BoxShape.new()
	sh.extents = size * 0.5
	cs.shape = sh
	sb.add_child(cs)
	if visible:
		var mi = MeshInstance.new()
		mi.mesh = Models.box(size)
		mi.material_override = mat
		sb.add_child(mi)
	if nav:
		nav.block_box(pos, size)
	return sb


static func omni(parent: Spatial, pos: Vector3, color: Color, energy := 1.0, rng := 8.0) -> OmniLight:
	var l = OmniLight.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	parent.add_child(l)
	l.translation = pos
	return l


static func label3d(parent: Spatial, text: String, pos: Vector3, size := 64, color := Color(1, 1, 1), rot_y := 0.0) -> Label3D:
	var l = Label3D.new()
	l.text = text.to_lower()
	l.font = UI.font("medium", size)
	l.modulate = color
	l.shaded = false
	l.double_sided = true
	l.pixel_size = 0.006
	parent.add_child(l)
	l.translation = pos
	l.rotation.y = rot_y
	return l


# ------------------------------------------------------------------ lamps
## Lamps carry three flags: "on" (flicker / blackout), "near" (its real light is on: weak PCs
## keep only the closest few) and "glare" (its glare billboard is drawn).
static func lamp_set_on(l: Light, on: bool) -> void:
	l.set_meta("on", on)
	if l.has_meta("bake"):
		var b = l.get_meta("bake")
		if is_instance_valid(b):
			b.set_lamp(l.get_meta("xz"), on)
	_lamp_refresh(l)


static func lamp_set_near(l: Light, near: bool, glare := true) -> void:
	l.set_meta("near", near)
	l.set_meta("glare", glare)
	_lamp_refresh(l)


static func _lamp_refresh(l: Light) -> void:
	var on = l.get_meta("on") if l.has_meta("on") else true
	var near = l.get_meta("near") if l.has_meta("near") else true
	var glare = l.get_meta("glare") if l.has_meta("glare") else true
	l.visible = on and near
	if l.has_meta("panel"):
		var p = l.get_meta("panel")
		if is_instance_valid(p):
			p.visible = on
	if l.has_meta("halo"):
		var h = l.get_meta("halo")
		if is_instance_valid(h):
			h.visible = on and glare


static func halo_mat(color: Color) -> SpatialMaterial:
	var k = "halo_" + color.to_html()
	if Game.cache.has(k):
		return Game.cache[k]
	var g = Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 0.55))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gt = GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
	m.albedo_texture = gt
	m.albedo_color = Color(1, 1, 1, 0.5)
	Game.cache[k] = m
	return m


## Square drop-ceiling light panel (60 cm), soft and wide.
static func square_panel(parent: Spatial, pos: Vector3, energy := 1.7, shadows := false, color := Color(1.0, 0.98, 0.9)) -> SpotLight:
	var panel = MeshInstance.new()
	panel.mesh = Models.box(Vector3(0.58, 0.02, 0.58))
	panel.material_override = Mats.glow(color, 5.5)
	panel.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(panel)
	panel.translation = pos
	var halo = null
	if not Mats.potato():
		var frame = MeshInstance.new()
		frame.mesh = Models.box(Vector3(0.64, 0.015, 0.64))
		frame.material_override = Mats.std(Color(0.78, 0.78, 0.74), 0.5, 0.2)
		frame.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		parent.add_child(frame)
		frame.translation = pos + Vector3(0, 0.006, 0)
		halo = MeshInstance.new()
		var q = QuadMesh.new()
		q.size = Vector2(1.5, 1.5)
		halo.mesh = q
		halo.material_override = halo_mat(color)
		halo.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		parent.add_child(halo)
		halo.translation = pos - Vector3(0, 0.1, 0)
	var l = SpotLight.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = 7.5
	l.spot_angle = 84.0
	l.spot_attenuation = 1.1
	l.spot_angle_attenuation = 0.35
	l.shadow_enabled = shadows
	l.set_meta("shadow_wanted", shadows)
	l.set_meta("panel", panel)
	if halo:
		l.set_meta("halo", halo)
	l.add_to_group("lamp")
	parent.add_child(l)
	l.translation = pos - Vector3(0, 0.03, 0)
	l.rotation_degrees = Vector3(-90, 0, 0)
	return l


## Baked lamp: the lens lives in the merged ceiling mesh and its light in the light map.
## This SpotLight only lights brainrots and props; a cheap glare billboard hangs under the lens.
static func lamp_light(parent: Spatial, pos: Vector3, bake: Node, energy := 1.7, color := Color(1.0, 0.98, 0.9)) -> SpotLight:
	var halo = MeshInstance.new()
	var q = QuadMesh.new()
	q.size = Vector2(1.25, 1.25)
	halo.mesh = q
	halo.material_override = halo_mat(Color(color.r * 0.6, color.g * 0.6, color.b * 0.55))
	halo.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(halo)
	halo.translation = pos - Vector3(0, 0.06, 0)
	var l = SpotLight.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = 7.5
	l.spot_angle = 84.0
	l.spot_attenuation = 1.1
	l.spot_angle_attenuation = 0.35
	l.light_cull_mask = VIS_ACTOR
	l.set_meta("shadow_wanted", false)
	l.set_meta("halo", halo)
	l.set_meta("bake", bake)
	l.set_meta("xz", Vector2(pos.x, pos.z))
	l.add_to_group("lamp")
	parent.add_child(l)
	l.translation = pos - Vector3(0, 0.03, 0)
	l.rotation_degrees = Vector3(-90, 0, 0)
	return l


static func dead_panel(parent: Spatial, pos: Vector3) -> void:
	Models.part(parent, Models.box(Vector3(0.58, 0.02, 0.58)), Mats.std(Color(0.55, 0.56, 0.52), 0.3), pos)
	Models.part(parent, Models.box(Vector3(0.64, 0.015, 0.64)), Mats.std(Color(0.5, 0.5, 0.48), 0.6, 0.3), pos + Vector3(0, 0.006, 0))


## Exit door: glowing frame + trigger that calls target.method(body).
static func exit_door(parent: Spatial, pos: Vector3, rot_y: float, target: Object, method: String, color := Color(0.9, 1.0, 0.8), label := "") -> Area:
	var root = Spatial.new()
	parent.add_child(root)
	root.translation = pos
	root.rotation.y = rot_y
	var frame = Mats.std(Color(0.1, 0.1, 0.1), 0.6)
	Models.part(root, Models.box(Vector3(0.15, 2.4, 0.2)), frame, Vector3(-0.68, 1.2, 0))
	Models.part(root, Models.box(Vector3(0.15, 2.4, 0.2)), frame, Vector3(0.68, 1.2, 0))
	Models.part(root, Models.box(Vector3(1.5, 0.15, 0.2)), frame, Vector3(0, 2.4, 0))
	var g = Models.part(root, Models.box(Vector3(1.2, 2.3, 0.05)), Mats.glow(color, 3.5), Vector3(0, 1.15, 0.05))
	g.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var l = omni(root, Vector3(0, 1.3, -0.8), color, 2.0, 7.0)
	l.light_cull_mask = VIS_ACTOR
	l.add_to_group("lamp")
	if label != "":
		label3d(root, label, Vector3(0, 2.75, 0.12), 48, Color(1, 0.2, 0.15), 0.0)
	var a = Area.new()
	a.collision_layer = 0
	a.collision_mask = LAYER_PLAYER
	root.add_child(a)
	var cs = CollisionShape.new()
	var sh = BoxShape.new()
	sh.extents = Vector3(0.7, 1.2, 0.6)
	cs.shape = sh
	a.add_child(cs)
	cs.translation = Vector3(0, 1.2, 0)
	a.connect("body_entered", target, method)
	Models.set_layers(root, 1 | VIS_ACTOR)
	return a


## Dust hanging in the air around the player (CPU particles: fine on GLES2).
static func dust(parent: Spatial, amount := 500) -> CPUParticles:
	var p = CPUParticles.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 2.2, 9)
	p.gravity = Vector3(0, -0.015, 0)
	p.initial_velocity = 0.04
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.scale_amount = 1.0
	p.scale_amount_random = 0.6
	var q = QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m = SpatialMaterial.new()
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.flags_transparent = true
	m.flags_unshaded = true
	m.albedo_color = Color(1, 0.95, 0.85, 0.5)
	q.material = m
	p.mesh = q
	p.add_to_group("dust")
	parent.add_child(p)
	return p
