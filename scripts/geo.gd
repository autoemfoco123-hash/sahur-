class_name Geo
## Level geometry helpers.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_INTERACT := 4
const LAYER_ENEMY := 8


static func solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, nav: NavGrid = null, rot_y := 0.0, visible := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	parent.add_child(sb)
	sb.position = pos
	sb.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	if visible:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		sb.add_child(mi)
	if nav:
		nav.block_box(pos, size, rot_y)
	return sb


static func floor_box(parent: Node3D, size: Vector3, center_top: Vector3, mat: Material) -> StaticBody3D:
	return solid(parent, size, center_top - Vector3(0, size.y * 0.5, 0), mat)


static func cylinder_solid(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, nav: NavGrid = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	parent.add_child(sb)
	sb.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = Models.cyl(r, r, h, 20)
	mi.material_override = mat
	sb.add_child(mi)
	if nav:
		nav.block_box(pos, Vector3(r * 2, h, r * 2))
	return sb


## Harsh top-down light with a visible fixture. The signature look of ROT.
static func top_light(parent: Node3D, pos: Vector3, color := Color(1.0, 0.92, 0.75), energy := 6.0, rng := 10.0, angle := 40.0, shadows := true, fixture := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_attenuation = 0.6
	l.spot_angle_attenuation = 0.4
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 2.5
	parent.add_child(l)
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	if fixture:
		var f := MeshInstance3D.new()
		f.mesh = Models.cyl(0.12, 0.35, 0.18, 20)
		f.material_override = Mats.std(Color(0.08, 0.08, 0.08), 0.5, 0.6)
		parent.add_child(f)
		f.position = pos + Vector3(0, 0.12, 0)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b := MeshInstance3D.new()
		b.mesh = Models.sphere(0.09, -1, 12, 6)
		b.material_override = Mats.glow(color, 12.0)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(b)
		b.position = pos
	return l


static func omni(parent: Node3D, pos: Vector3, color: Color, energy := 1.0, rng := 8.0, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadows
	parent.add_child(l)
	l.position = pos
	return l


static func label3d(parent: Node3D, text: String, pos: Vector3, size := 64, color := Color(1, 1, 1), rot_y := 0.0, emissive := true) -> Label3D:
	var l := Label3D.new()
	l.text = text.to_lower()
	l.font_size = size
	l.modulate = color
	l.outline_size = 0
	l.shaded = not emissive
	l.double_sided = false
	parent.add_child(l)
	l.position = pos
	l.rotation.y = rot_y
	return l


## Perfect maze on an odd-sized block grid. true = wall. Extra loops make it less linear.
static func maze(cw: int, ch: int, rng: RandomNumberGenerator, loops := 0.08) -> Array:
	var w := cw * 2 + 1
	var h := ch * 2 + 1
	var g := []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(true)
		g.append(row)
	var stack := [Vector2i(0, 0)]
	var seen := {Vector2i(0, 0): true}
	g[1][1] = false
	while stack.size() > 0:
		var c: Vector2i = stack[-1]
		var opts := []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < cw and n.y < ch and not seen.has(n):
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nx: Vector2i = opts[rng.randi_range(0, opts.size() - 1)]
		seen[nx] = true
		g[nx.y * 2 + 1][nx.x * 2 + 1] = false
		g[c.y + nx.y + 1][c.x + nx.x + 1] = false
		stack.append(nx)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if g[y][x] and rng.randf() < loops:
				var horiz: bool = (x % 2 == 0 and y % 2 == 1)
				var vert: bool = (x % 2 == 1 and y % 2 == 0)
				if horiz or vert:
					g[y][x] = false
	return g


## BFS distances on a block grid (false = open).
static func bfs(g: Array, start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var q := [start]
	var parent := {}
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n.y >= g.size() or n.x < 0 or n.x >= g[0].size():
				continue
			if g[n.y][n.x] or dist.has(n):
				continue
			dist[n] = dist[c] + 1
			parent[n] = c
			q.append(n)
	return {"dist": dist, "parent": parent}


static func dead_ends(g: Array) -> Array:
	var out := []
	for y in range(1, g.size() - 1):
		for x in range(1, g[0].size() - 1):
			if g[y][x]:
				continue
			var open := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not g[y + d.y][x + d.x]:
					open += 1
			if open == 1:
				out.append(Vector2i(x, y))
	return out


## Exit door: glowing frame + trigger. Calls `on_enter` when the player walks in.
static func exit_door(parent: Node3D, pos: Vector3, rot_y: float, on_enter: Callable, color := Color(0.9, 1.0, 0.8), label := "") -> Area3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	var frame := Mats.std(Color(0.1, 0.1, 0.1), 0.6)
	Models.part(root, Models.box(Vector3(0.15, 2.4, 0.2)), frame, Vector3(-0.68, 1.2, 0))
	Models.part(root, Models.box(Vector3(0.15, 2.4, 0.2)), frame, Vector3(0.68, 1.2, 0))
	Models.part(root, Models.box(Vector3(1.5, 0.15, 0.2)), frame, Vector3(0, 2.4, 0))
	var glow := Models.part(root, Models.box(Vector3(1.2, 2.3, 0.05)), Mats.glow(color, 3.5), Vector3(0, 1.15, 0.05))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.0
	l.omni_range = 7.0
	root.add_child(l)
	l.position = Vector3(0, 1.3, -0.8)
	if label != "":
		label3d(root, label, Vector3(0, 2.75, 0.12), 48, Color(1, 0.2, 0.15), 0.0)
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = LAYER_PLAYER
	root.add_child(a)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 2.4, 1.2)
	cs.shape = sh
	a.add_child(cs)
	cs.position = Vector3(0, 1.2, 0)
	a.body_entered.connect(func(b): if b is Player: on_enter.call())
	return a


## Trigger volume.
static func trigger(parent: Node3D, pos: Vector3, size: Vector3, on_enter: Callable) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = LAYER_PLAYER
	parent.add_child(a)
	a.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.body_entered.connect(func(b): if b is Player: on_enter.call())
	return a


## Big sloppy MultiMesh helper for foliage / props.
static func multimesh(parent: Node3D, mesh: Mesh, mat: Material, transforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


## Walls from a block grid (true = wall) as one MultiMesh + one StaticBody.
static func block_grid(parent: Node3D, g: Array, block: float, height: float, mat: Material, nav: NavGrid = null, origin := Vector3.ZERO, y0 := 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	parent.add_child(sb)
	var xforms := []
	var sh := BoxShape3D.new()
	sh.size = Vector3(block, height, block)
	for y in g.size():
		for x in g[0].size():
			if not g[y][x]:
				continue
			var p := origin + Vector3((x + 0.5) * block, y0 + height * 0.5, (y + 0.5) * block)
			var cs := CollisionShape3D.new()
			cs.shape = sh
			sb.add_child(cs)
			cs.position = p
			xforms.append(Transform3D(Basis(), p))
			if nav:
				nav.block_box(p, Vector3(block, height, block))
	multimesh(parent, Models.box(Vector3(block, height, block)), mat, xforms)
	return sb


static func cell_center(c: Vector2i, block: float, origin := Vector3.ZERO, y := 0.0) -> Vector3:
	return origin + Vector3((c.x + 0.5) * block, y, (c.y + 0.5) * block)


static func open_dir(g: Array, c: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if n.y >= 0 and n.y < g.size() and n.x >= 0 and n.x < g[0].size() and not g[n.y][n.x]:
			return d
	return Vector2i(0, 1)


## A Source-style physics prop you can shove around.
static func prop(parent: Node3D, kind: String, pos: Vector3, rot_y := 0.0) -> RigidBody3D:
	var data := Models2.prop_mesh(kind)
	var rb := RigidBody3D.new()
	rb.collision_layer = LAYER_WORLD
	rb.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
	rb.mass = data[2]
	rb.can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05
	rb.physics_material_override = pm
	parent.add_child(rb)
	rb.global_position = pos
	rb.rotation.y = rot_y
	rb.add_child(data[0])
	var cs := CollisionShape3D.new()
	cs.shape = data[1]
	rb.add_child(cs)
	if kind == "tv":
		var a := Audio.attach("static", rb, -18.0, 14.0)
		a.unit_size = 2.0
	rb.body_entered.connect(func(_b):
		if rb.linear_velocity.length() > 2.0:
			Audio.play_at("ev_thud" if rb.mass > 10 else "knock", rb.global_position, parent, -14.0, randf_range(1.2, 1.6), 25.0))
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	return rb



## Flat fluorescent ceiling panel: the light of every liminal space.
static func fluoro(parent: Node3D, pos: Vector3, energy := 2.2, shadows := false, color := Color(0.96, 1.0, 0.9), rng := 7.0) -> SpotLight3D:
	var panel := MeshInstance3D.new()
	panel.mesh = Models.box(Vector3(1.3, 0.05, 0.36))
	panel.material_override = Mats.glow(color, 4.0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(panel)
	panel.position = pos
	var frame := MeshInstance3D.new()
	frame.mesh = Models.box(Vector3(1.42, 0.06, 0.46))
	frame.material_override = Mats.std(Color(0.7, 0.7, 0.68), 0.6, 0.3)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(frame)
	frame.position = pos + Vector3(0, 0.03, 0)
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = 72.0
	l.spot_attenuation = 0.9
	l.spot_angle_attenuation = 0.6
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 1.2
	l.set_meta("panel", panel)
	parent.add_child(l)
	l.position = pos - Vector3(0, 0.05, 0)
	l.rotation_degrees = Vector3(-90, 0, 0)
	# Source-style glow sprite under the tube
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 1.4)
	halo.mesh = q
	halo.material_override = _halo_mat(color)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(halo)
	halo.position = pos - Vector3(0, 0.12, 0)
	l.visibility_changed.connect(func():
		panel.visible = l.visible
		halo.visible = l.visible)
	return l



## A dead fluorescent panel: the fixture is there, the light isn't.
static func dead_panel(parent: Node3D, pos: Vector3) -> void:
	var panel := MeshInstance3D.new()
	panel.mesh = Models.box(Vector3(1.3, 0.05, 0.36))
	panel.material_override = Mats.std(Color(0.55, 0.56, 0.52), 0.3)
	parent.add_child(panel)
	panel.position = pos
	var frame := MeshInstance3D.new()
	frame.mesh = Models.box(Vector3(1.42, 0.06, 0.46))
	frame.material_override = Mats.std(Color(0.5, 0.5, 0.48), 0.6, 0.3)
	parent.add_child(frame)
	frame.position = pos + Vector3(0, 0.03, 0)


static var _halo_cache := {}


static func _halo_mat(color: Color) -> StandardMaterial3D:
	var k := color.to_html()
	if _halo_cache.has(k):
		return _halo_cache[k]
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.55))
	g.set_color(1, Color(color, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = gt
	m.albedo_color = Color(1, 1, 1, 0.5)
	m.disable_receive_shadows = true
	_halo_cache[k] = m
	return m


## Dust hanging in the air around the player: makes every light beam thick.
static func dust(parent: Node3D, amount := 1400) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 6, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9, 2.2, 9)
	pm.gravity = Vector3(0, -0.015, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.95, 0.85, 0.55)
	m.emission_enabled = true
	m.emission = Color(1, 0.9, 0.75)
	m.emission_energy_multiplier = 0.25
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
	return p


## Square drop-ceiling light panel (60 cm), soft and wide.
static func square_panel(parent: Node3D, pos: Vector3, energy := 1.7, shadows := false, color := Color(1.0, 0.98, 0.9)) -> SpotLight3D:
	var panel := MeshInstance3D.new()
	panel.mesh = Models.box(Vector3(0.58, 0.02, 0.58))
	panel.material_override = Mats.glow(color, 5.5)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(panel)
	panel.position = pos
	var frame := MeshInstance3D.new()
	frame.mesh = Models.box(Vector3(0.64, 0.015, 0.64))
	frame.material_override = Mats.std(Color(0.78, 0.78, 0.74), 0.5, 0.2)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(frame)
	frame.position = pos + Vector3(0, 0.006, 0)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	halo.mesh = q
	halo.material_override = _halo_mat(color)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(halo)
	halo.position = pos - Vector3(0, 0.1, 0)
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = 7.5
	l.spot_angle = 84.0
	l.spot_attenuation = 1.1
	l.spot_angle_attenuation = 0.35
	l.shadow_enabled = shadows
	l.shadow_blur = 2.5
	l.light_size = 0.5
	l.light_volumetric_fog_energy = 1.0
	parent.add_child(l)
	l.position = pos - Vector3(0, 0.03, 0)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.visibility_changed.connect(func():
		panel.visible = l.visible
		halo.visible = l.visible)
	return l
