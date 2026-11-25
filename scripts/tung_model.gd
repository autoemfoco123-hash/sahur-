class_name TungModel
## Tung Tung Tung Sahur, sculpted vertex by vertex.
## A varnished log with a carved face: heavy-lidded bulging green eyes, raised brows,
## long nose, a closed smug smile with dimples, thin wooden arms and a baseball bat.
## Faces -Z. Root at the feet.

const H := 1.95        # log height
const R := 0.33        # log radius
const LEGS := 0.62     # leg length (body sits on top)
const EY := H - 0.30   # eye line (body-local y)
const EX := 0.135      # eye x offset
const ER := 0.1        # eye radius

static var _body: ArrayMesh
static var _bat: ArrayMesh
static var _wood: ShaderMaterial
static var _wood_lite: ShaderMaterial
static var _wood_bat: ShaderMaterial
static var _eye: ShaderMaterial


static func build() -> Node3D:
	_materials()
	var root := Node3D.new()
	root.name = "Tung"
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	body.position.y = LEGS
	var mi := MeshInstance3D.new()
	mi.mesh = _body_mesh()
	mi.material_override = _wood
	body.add_child(mi)
	# Eyes + heavy lids
	for s in [-1, 1]:
		var th: float = s * EX / R
		var rr := R - 0.035
		var c := Vector3(sin(th) * rr, EY - 0.005, -cos(th) * rr)
		var eye := Node3D.new()
		eye.name = "eyeL" if s > 0 else "eyeR"
		body.add_child(eye)
		eye.position = c
		var ball := MeshInstance3D.new()
		ball.mesh = Models.sphere(ER, -1, 48, 24)
		ball.material_override = _eye
		eye.add_child(ball)
		var lid := Node3D.new()
		lid.name = "lidL" if s > 0 else "lidR"
		body.add_child(lid)
		lid.position = c + Vector3(0, ER * 0.3, 0.012)
		lid.rotation = Vector3(deg_to_rad(-14), s * 0.1, s * -0.08)
		var shell := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = ER * 1.07
		hs.height = ER * 1.07
		hs.is_hemisphere = true
		hs.radial_segments = 48
		hs.rings = 16
		shell.mesh = hs
		shell.material_override = _wood_lite
		lid.add_child(shell)
		# lid crease rim
		var rim := MeshInstance3D.new()
		rim.mesh = Models.torus(ER * 0.96, ER * 1.1, 48, 12)
		rim.material_override = _wood_lite
		lid.add_child(rim)
		rim.scale = Vector3(1, 0.55, 1)
		# lower lid
		var low := MeshInstance3D.new()
		low.mesh = Models.torus(ER * 0.93, ER * 1.22, 48, 14)
		low.material_override = _wood_lite
		body.add_child(low)
		low.position = c + Vector3(0, 0, 0.012)
		low.rotation = Vector3(PI / 2, 0, 0)
		low.scale = Vector3(1, 0.7, 1)
	# Arms: shoulder -> elbow -> hand (real joints, animated by the tung brain)
	for s in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "armR" if s > 0 else "armL"
		body.add_child(arm)
		arm.position = Vector3(s * 0.318, H - 0.56, -0.06)
		var el := Vector3(s * 0.1, -0.4, -0.02)
		var hd := Vector3(-s * 0.02, -0.38, -0.05)
		_joint(arm, Vector3.ZERO, 0.045)
		_limb(arm, Vector3.ZERO, el, 0.034, 0.03)
		var elbow := Node3D.new()
		elbow.name = "elbowR" if s > 0 else "elbowL"
		arm.add_child(elbow)
		elbow.position = el
		_joint(elbow, Vector3.ZERO, 0.033)
		_limb(elbow, Vector3.ZERO, hd, 0.03, 0.026)
		var hand := Node3D.new()
		hand.name = "handR" if s > 0 else "handL"
		elbow.add_child(hand)
		hand.position = hd
		_hand(hand, Vector3.ZERO, s, s > 0)
		if s > 0:
			var bat := Node3D.new()
			bat.name = "bat"
			hand.add_child(bat)
			var bm := MeshInstance3D.new()
			bm.mesh = _bat_mesh()
			bm.material_override = _wood_bat
			bat.add_child(bm)
			bat.basis = _basis_y(Vector3(0.32, -0.94, -0.12).normalized())
			bm.position = Vector3(0, -0.1, 0)
	# Legs: hip -> knee -> ankle -> foot
	for s in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "legL" if s < 0 else "legR"
		root.add_child(leg)
		leg.position = Vector3(s * 0.12, LEGS + 0.02, 0)
		_joint(leg, Vector3.ZERO, 0.042)
		_limb(leg, Vector3.ZERO, Vector3(0, -0.3, 0), 0.04, 0.034)
		var knee := Node3D.new()
		knee.name = "kneeL" if s < 0 else "kneeR"
		leg.add_child(knee)
		knee.position = Vector3(0, -0.3, 0)
		_joint(knee, Vector3.ZERO, 0.036)
		_limb(knee, Vector3.ZERO, Vector3(0, -0.3, 0), 0.034, 0.03)
		var ankle := Node3D.new()
		ankle.name = "ankleL" if s < 0 else "ankleR"
		knee.add_child(ankle)
		ankle.position = Vector3(0, -0.3, 0)
		_joint(ankle, Vector3.ZERO, 0.03)
		var foot := MeshInstance3D.new()
		foot.mesh = Models.capsule(0.045, 0.2, 16)
		foot.material_override = _wood_lite
		ankle.add_child(foot)
		foot.position = Vector3(0, 0.0, -0.06)
		foot.rotation = Vector3(PI / 2, 0, 0)
	return Models.finish(root, LEGS + H, "TUNG TUNG TUNG SAHUR")


# ------------------------------------------------------------------ materials
static func _materials() -> void:
	if _wood:
		return
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.01
	n.fractal_octaves = 5
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = n
	var sh: Shader = load("res://scripts/carved_wood.gdshader")
	_wood = ShaderMaterial.new()
	_wood.shader = sh
	_wood.set_shader_parameter("noise_tex", nt)
	_wood_lite = _wood.duplicate()
	_wood_lite.set_shader_parameter("cylindrical", false)
	_wood_lite.set_shader_parameter("cavity", 0.0)
	_wood_lite.set_shader_parameter("grain_freq", 400.0)
	_wood_bat = _wood_lite.duplicate()
	_wood_bat.set_shader_parameter("base", Color(0.78, 0.6, 0.38))
	_wood_bat.set_shader_parameter("dark", Color(0.5, 0.34, 0.18))
	_wood_bat.set_shader_parameter("light", Color(0.95, 0.82, 0.6))
	_eye = ShaderMaterial.new()
	_eye.shader = load("res://scripts/eye.gdshader")


# ------------------------------------------------------------------ the carved log
static func _g(x: float, y: float, cx: float, cy: float, sx: float, sy: float) -> float:
	var dx := (x - cx) / sx
	var dy := (y - cy) / sy
	return exp(-0.5 * (dx * dx + dy * dy))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _mouth_y(x: float) -> float:
	return -0.245 + 1.45 * x * x - 0.06 * x


## Carved relief in face space. x = arc length from the front (+X side positive), fy = height above the eye line.
static func _face(x: float, fy: float) -> float:
	var d := 0.0
	for s in [-1.0, 1.0]:
		var ex: float = s * EX
		# deep sockets behind the eyeballs
		d -= 0.04 * _g(x, fy, ex, 0.0, 0.075, 0.07)
		# puffy under-eye
		d += 0.02 * _g(x, fy, ex, -0.115, 0.06, 0.022)
		# raised, arched brows
		var dx := x - ex
		var by: float = 0.14 + 0.028 * (1.0 - clampf((dx / 0.11) * (dx / 0.11), 0.0, 1.0)) - s * dx * 0.08
		d += 0.042 * exp(-0.5 * pow((fy - by) / 0.02, 2.0)) * exp(-0.5 * pow(dx / 0.08, 2.0))
		# cheeks (the smirk side sits higher)
		d += 0.05 * _g(x, fy, s * 0.15, -0.19 + (0.012 if s < 0 else 0.0), 0.055, 0.05)
		# smile lines
		var nl := _seg_dist(Vector2(x, fy), Vector2(s * 0.052, -0.135), Vector2(s * 0.178, -0.2 + (0.012 if s < 0 else 0.0)))
		d -= 0.016 * exp(-0.5 * pow(nl / 0.008, 2.0))
		# dimples at the mouth corners
		var cx: float = s * 0.178
		var cy := _mouth_y(cx)
		d -= 0.022 * _g(x, fy, cx, cy, 0.013, 0.015)
		d += 0.012 * _g(x, fy, cx - s * 0.014, cy + 0.012, 0.016, 0.02)
		# nostril wings
		d += 0.026 * _g(x, fy, s * 0.045, -0.152, 0.022, 0.018)
		d -= 0.012 * _g(x, fy, s * 0.03, -0.172, 0.011, 0.008)
	# forehead wrinkles
	for wy in [0.205, 0.24]:
		d -= 0.008 * exp(-0.5 * pow((fy - wy) / 0.006, 2.0)) * exp(-0.5 * pow(x / 0.1, 2.0))
	# nose: bridge between the eyes down to a heavy tip
	if fy < 0.08 and fy > -0.22:
		var t := clampf((0.03 - fy) / 0.18, 0.0, 1.0)
		var w := lerpf(0.028, 0.055, t)
		var a := lerpf(0.026, 0.11, t)
		var vy := smoothstep(0.07, 0.0, fy) * (1.0 - smoothstep(-0.155, -0.185, fy))
		d += a * exp(-0.5 * x * x / (w * w)) * vy
	d += 0.055 * _g(x, fy, 0.0, -0.14, 0.045, 0.034)
	# the closed smile
	var my := _mouth_y(x)
	var env := 1.0 - smoothstep(0.15, 0.185, absf(x))
	d -= 0.042 * exp(-0.5 * pow((fy - my) / 0.0065, 2.0)) * env
	d += 0.018 * exp(-0.5 * pow((fy - my - 0.018) / 0.011, 2.0)) * (1.0 - smoothstep(0.11, 0.17, absf(x)))
	d += 0.03 * exp(-0.5 * pow((fy - my + 0.028) / 0.016, 2.0)) * (1.0 - smoothstep(0.09, 0.155, absf(x)))
	# chin
	d += 0.024 * _g(x, fy, 0.0, -0.345, 0.07, 0.04)
	return d


static func _radius(th: float, y: float) -> Vector2:
	## returns (radius, relief)
	var r := R + 0.004 * sin(th * 3.0 + y * 2.3) + 0.003 * sin(th * 7.0 - y * 4.1) + 0.002 * sin(th * 13.0 + y * 9.0)
	var relief := 0.0
	if absf(th) < 1.25 and y > EY - 0.5:
		relief = _face(th * R, y - EY)
	r += relief
	var ft := 0.05
	if y > H - ft:
		var dy := y - (H - ft)
		r -= ft - sqrt(maxf(ft * ft - dy * dy, 0.0))
	var fb := 0.03
	if y < fb:
		var db := fb - y
		r -= fb - sqrt(maxf(fb * fb - db * db, 0.0))
	return Vector2(r, relief)


static func _body_mesh() -> ArrayMesh:
	if _body:
		return _body
	var seg := 240
	var ys := PackedFloat32Array()
	var y := 0.0
	while y < H:
		ys.append(y)
		var dy := 0.006 if y > EY - 0.45 else 0.04
		if y < 0.04 or y > H - 0.06:
			dy = 0.006
		y += dy
	ys.append(H)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := seg + 1
	for j in ys.size():
		var yy := ys[j]
		for i in cols:
			var u := float(i) / seg
			var th := (u - 0.5) * TAU
			var rr := _radius(th, yy)
			var occ := clampf(1.0 + rr.y * 16.0, 0.3, 1.0) if rr.y < 0.0 else 1.0
			st.set_color(Color(occ, occ, occ))
			st.set_uv(Vector2(u, yy / H))
			st.add_vertex(Vector3(sin(th) * rr.x, yy, -cos(th) * rr.x))
	for j in ys.size() - 1:
		for i in seg:
			var a := j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	# caps
	var top_c := ys.size() * cols
	st.set_color(Color.WHITE)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(Vector3(0, H, 0))
	var bot_c := top_c + 1
	st.set_uv(Vector2(0.5, 0.0))
	st.add_vertex(Vector3(0, 0, 0))
	var last := (ys.size() - 1) * cols
	for i in seg:
		st.add_index(top_c)
		st.add_index(last + i + 1)
		st.add_index(last + i)
		st.add_index(bot_c)
		st.add_index(i)
		st.add_index(i + 1)
	st.generate_normals()
	st.generate_tangents()
	_body = st.commit()
	return _body


# ------------------------------------------------------------------ limbs, hands, bat
static func _basis_y(dir: Vector3) -> Basis:
	var yv := dir.normalized()
	var xv := yv.cross(Vector3.FORWARD if absf(yv.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(xv, yv, xv.cross(yv).normalized())


static func _limb(p: Node3D, a: Vector3, b: Vector3, r1: float, r2: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.cyl(r2, r1, a.distance_to(b), 20, 3)
	mi.material_override = _wood_lite
	p.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.basis = _basis_y(b - a)


static func _joint(p: Node3D, at: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.sphere(r, -1, 20, 10)
	mi.material_override = _wood_lite
	p.add_child(mi)
	mi.position = at


static func _hand(p: Node3D, at: Vector3, s: float, fist: bool) -> void:
	var palm := MeshInstance3D.new()
	palm.mesh = Models.sphere(0.04, 0.07, 20, 10)
	palm.material_override = _wood_lite
	p.add_child(palm)
	palm.position = at
	for f in 4:
		var fz := -0.02 + f * 0.014
		var fing := MeshInstance3D.new()
		fing.mesh = Models.capsule(0.011, 0.055 if fist else 0.07, 10)
		fing.material_override = _wood_lite
		p.add_child(fing)
		if fist:
			fing.position = at + Vector3(-s * 0.025, -0.02 - f * 0.004, fz - 0.03)
			fing.rotation = Vector3(0.2, 0, s * 1.3)
		else:
			fing.position = at + Vector3(s * 0.008, -0.05, fz - 0.01)
			fing.rotation = Vector3(0.1 * f - 0.15, 0, -s * 0.15)
	var thumb := MeshInstance3D.new()
	thumb.mesh = Models.capsule(0.012, 0.05, 10)
	thumb.material_override = _wood_lite
	p.add_child(thumb)
	thumb.position = at + Vector3(-s * 0.02, 0.0, -0.04)
	thumb.rotation = Vector3(0.6, 0, -s * 0.5)


## Turned baseball bat (lathe). Knob at y = +0.1, barrel downwards.
static func _bat_mesh() -> ArrayMesh:
	if _bat:
		return _bat
	var prof := [
		Vector2(0.0, 0.14), Vector2(0.028, 0.135), Vector2(0.036, 0.12), Vector2(0.03, 0.105),
		Vector2(0.018, 0.09), Vector2(0.017, -0.2), Vector2(0.019, -0.32), Vector2(0.028, -0.45),
		Vector2(0.04, -0.58), Vector2(0.046, -0.7), Vector2(0.047, -0.82), Vector2(0.044, -0.88),
		Vector2(0.032, -0.91), Vector2(0.0, -0.92),
	]
	var seg := 32
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in prof.size():
		for i in seg + 1:
			var a := float(i) / seg * TAU
			var pr: Vector2 = prof[j]
			st.set_uv(Vector2(float(i) / seg, float(j) / prof.size()))
			st.add_vertex(Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x))
	for j in prof.size() - 1:
		for i in seg:
			var a := j * (seg + 1) + i
			var c := a + seg + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(c + 1)
	st.generate_normals()
	st.generate_tangents()
	_bat = st.commit()
	return _bat
