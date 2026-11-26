extends Reference
## THE KHABY LAME MECHANISM (sector 2, friendly). Built from the reference photo: a bust
## (head, neck and a chest cup, the face projected from the photo by khaby_bust.shader) on a
## white turned pedestal, on a small round table in a white cloth. Two steel rods hang from
## sprockets at the shoulders, one chain-driven axle turns both, and the hands (cut out of the
## photo) go round and round, stopping palms-up at the top: "it's that simple".
## Faces -Z, feet at y = 0. Joints: "head", "armL", "armR" (rotate about X).
## Every size is in photo pixels times PX, measured on the reference (637 x 358, face at x 318).

const PX = 0.0058
const TABLE_H = 0.85
const SHOULDER = Vector3(0.528, TABLE_H + (350 - 175) * PX, 0.0)
const ROD = 0.46
const EYE_Y = TABLE_H + (350 - 70) * PX
const TOP_Y = TABLE_H + (350 - 3) * PX

# (photo y, half width in photo px) from the top of the head down
const HEAD = [[3, 0], [7, 24], [14, 40], [26, 51], [45, 57], [70, 58], [95, 56], [115, 52], [130, 46], [144, 37], [154, 24], [159, 0]]
const NECK = [[146, 31], [172, 30]]
const CUP = [[163, 0], [163.5, 30], [166, 60], [171, 80], [180, 88], [195, 84], [210, 72], [224, 52], [235, 25], [236, 0]]
const PEDESTAL = [[235, 0], [235.5, 24], [240, 40], [250, 42], [257, 30], [265, 22], [280, 24], [292, 40], [305, 52], [325, 56], [345, 54], [350, 50], [350.5, 0]]


static func _y(yp: float) -> float:
	return TABLE_H + (350.0 - yp) * PX


## A turned shape from a profile of (photo y, half width). zk squashes the depth.
static func _lathe(profile: Array, zk: float, seg := 40, zoff := 0.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings = []
	for p in profile:
		var ring = []
		var r = float(p[1]) * PX
		for i in seg + 1:
			var a = TAU * float(i) / seg
			ring.append(Vector3(cos(a) * r, _y(float(p[0])), sin(a) * r * zk + zoff))
		rings.append(ring)
	for j in rings.size() - 1:
		for i in seg:
			var a: Vector3 = rings[j][i]
			var b: Vector3 = rings[j][i + 1]
			var c: Vector3 = rings[j + 1][i + 1]
			var d: Vector3 = rings[j + 1][i]
			# Godot draws clockwise faces seen from outside
			for v in [a, c, b, a, d, c]:
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


static func build() -> Spatial:
	var root = Spatial.new()
	root.name = "KhabyMechanism"
	var bust = ShaderMaterial.new()
	bust.shader = load("res://scripts/khaby_bust.shader")
	bust.set_shader_param("face_tex", load("res://textures/khaby_face.png"))
	bust.set_shader_param("px", PX)
	bust.set_shader_param("table_h", TABLE_H)
	var white = Mats.std(Color(0.93, 0.93, 0.9), 0.32)
	var cloth = Mats.std(Color(0.95, 0.95, 0.93), 0.92)
	var steel = Mats.std(Color(0.55, 0.56, 0.58), 0.3, 0.85)
	var dark = Mats.std(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	# the little round table in its white cloth
	Models.part(root, Models.cyl(0.36, 0.43, TABLE_H, 32, 1), cloth, Vector3(0, TABLE_H * 0.5, 0))
	Models.part(root, Models.cyl(0.37, 0.37, 0.02, 32, 1), cloth, Vector3(0, TABLE_H - 0.01, 0))
	# pedestal and chest cup are fixed; the head can nod on its neck
	var ped = MeshInstance.new()
	ped.mesh = _lathe(PEDESTAL, 1.0)
	ped.material_override = white
	root.add_child(ped)
	var cup = MeshInstance.new()
	cup.mesh = _lathe(CUP, 0.72)
	cup.material_override = bust
	root.add_child(cup)
	var head = Models.pivot(root, "head", Vector3.ZERO)
	var neck = MeshInstance.new()
	neck.mesh = _lathe(NECK, 1.0)
	neck.material_override = bust
	head.add_child(neck)
	var skull = MeshInstance.new()
	skull.mesh = _lathe(HEAD, 1.12, 48, 0.02)
	skull.material_override = bust
	head.add_child(skull)
	# the drive: an axle behind the neck, a motor box on the right, a chain to the sprocket
	var axle = Models.part(root, Models.cyl(0.016, 0.016, SHOULDER.x * 2.0 + 0.1, 12, 1), steel, Vector3(0, SHOULDER.y, 0.12))
	axle.rotation_degrees = Vector3(0, 0, 90)
	var motor = Vector3(-0.68, SHOULDER.y - 0.25, 0.1)
	Models.part(root, Models.box(Vector3(0.18, 0.3, 0.17)), Mats.std(Color(0.86, 0.83, 0.72), 0.6), motor)
	Models.part(root, Models.box(Vector3(0.12, 0.08, 0.005)), Mats.std(Color(0.55, 0.78, 0.35), 0.6), motor + Vector3(0, 0.03, -0.088))
	var pulley = Models.part(root, Models.cyl(0.04, 0.04, 0.03, 16, 1), dark, motor + Vector3(0.0, 0.17, 0.0))
	pulley.rotation_degrees = Vector3(0, 0, 90)
	var chain_from = motor + Vector3(-0.02, 0.17, 0.0)
	var chain_to = Vector3(-SHOULDER.x, SHOULDER.y, 0.0)
	for s in [-1.0, 1.0]:
		var off = Vector3(0, 0, 0.04 * s)
		Models.limb(root, chain_from + off, chain_to + off, 0.008, dark)
	# the arms
	for side in [1.0, -1.0]:
		var sname = "L" if side > 0 else "R"
		var arm = Models.pivot(root, "arm" + sname, Vector3(SHOULDER.x * side, SHOULDER.y, 0.0))
		var spr = Models.part(arm, Models.cyl(0.075, 0.075, 0.03, 20, 1), steel, Vector3(0.03 * side, 0, 0))
		spr.rotation_degrees = Vector3(0, 0, 90)
		for i in 12:
			var a = TAU * i / 12.0
			Models.part(arm, Models.box(Vector3(0.026, 0.022, 0.022)), steel, Vector3(0.03 * side, cos(a) * 0.084, sin(a) * 0.084))
		Models.part(arm, Models.cyl(0.012, 0.012, ROD, 10, 1), steel, Vector3(0.03 * side, -ROD * 0.5, 0))
		Models.part(arm, Models.box(Vector3(0.05, 0.05, 0.04)), dark, Vector3(0.03 * side, -ROD, 0))
		_hand(arm, "l" if side > 0 else "r", Vector3(0.09 * side, -ROD + 0.02, 0))
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	return Models.finish(root, TOP_Y, "the khaby lame mechanism")


## A hand cut out of the photo: three thin layers (a little thickness), wrist at the top.
static func _hand(arm: Spatial, side: String, wrist: Vector3) -> void:
	var tex: Texture = load("res://textures/khaby_hand_%s.png" % side)
	var h = 0.5
	var w = h * float(tex.get_width()) / float(tex.get_height())
	var m = SpatialMaterial.new()
	m.albedo_texture = tex
	m.params_use_alpha_scissor = true
	m.params_alpha_scissor_threshold = 0.5
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.albedo_color = Color(0.78, 0.72, 0.72)
	m.roughness = 0.85
	m.metallic_specular = 0.2
	var q = QuadMesh.new()
	q.size = Vector2(w, h)
	for i in 3:
		var mi = MeshInstance.new()
		mi.mesh = q
		mi.material_override = m
		arm.add_child(mi)
		mi.translation = wrist + Vector3(0, -h * 0.5, -0.012 + i * 0.012)
		# the quad faces +Z; the palm has to face the front (-Z)
		mi.rotation_degrees = Vector3(0, 180, 0)
