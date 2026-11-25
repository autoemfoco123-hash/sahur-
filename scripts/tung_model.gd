class_name TungModel
## Tung Tung Tung Sahur, sculpted vertex by vertex. (Godot 3 port)
## A varnished log with a carved face: heavy-lidded bulging green eyes, raised brows,
## long nose, a closed smug smile with dimples, thin wooden arms and a baseball bat.
## Faces -Z. Root at the feet.

const H := 1.95        # log height
const R := 0.33        # log radius
const LEGS := 0.62     # leg length (body sits on top)
const EY := H - 0.30   # eye line (body-local y)
const EX := 0.135      # eye x offset
const ER := 0.1        # eye radius


static func build() -> Spatial:
	_materials()
	var wood: ShaderMaterial = Game.cache["tung_wood"]
	var lite: ShaderMaterial = Game.cache["tung_lite"]
	var root = Spatial.new()
	root.name = "Tung"
	var body = Spatial.new()
	body.name = "body"
	root.add_child(body)
	body.translation.y = LEGS
	var mi = MeshInstance.new()
	mi.mesh = _body_mesh()
	mi.material_override = wood
	body.add_child(mi)
	# Eyes + heavy lids + wooden sockets
	for s in [-1, 1]:
		var th: float = s * EX / R
		var rr = R - 0.035
		var c = Vector3(sin(th) * rr, EY - 0.005, -cos(th) * rr)
		var eye = Spatial.new()
		eye.name = "eyeL" if s > 0 else "eyeR"
		body.add_child(eye)
		eye.translation = c
		var ball = MeshInstance.new()
		ball.mesh = Models.sphere(ER, -1, 24 if Mats.potato() else 40, 12 if Mats.potato() else 20)
		ball.material_override = Game.cache["tung_eye"]
		eye.add_child(ball)
		var lid = Spatial.new()
		lid.name = "lidL" if s > 0 else "lidR"
		body.add_child(lid)
		lid.translation = c + Vector3(0, ER * 0.3, 0.012)
		lid.rotation = Vector3(deg2rad(-14), s * 0.1, s * -0.08)
		var shell = MeshInstance.new()
		var hs = SphereMesh.new()
		hs.radius = ER * 1.07
		hs.height = ER * 1.07
		hs.is_hemisphere = true
		hs.radial_segments = 40
		hs.rings = 14
		shell.mesh = hs
		shell.material_override = lite
		lid.add_child(shell)
		var rim = MeshInstance.new()
		rim.mesh = Models.torus(ER * 0.96, ER * 1.1, 40, 10)
		rim.material_override = lite
		lid.add_child(rim)
		rim.scale = Vector3(1, 0.55, 1)
		var low = MeshInstance.new()
		low.mesh = Models.torus(ER * 0.93, ER * 1.22, 40, 12)
		low.material_override = lite
		body.add_child(low)
		low.translation = c + Vector3(0, 0, 0.012)
		low.rotation = Vector3(PI / 2, 0, 0)
		low.scale = Vector3(1, 0.7, 1)
	# Arms: shoulder -> elbow -> hand (+ bat)
	for s in [-1, 1]:
		var arm = Spatial.new()
		arm.name = "armR" if s > 0 else "armL"
		body.add_child(arm)
		arm.translation = Vector3(s * 0.318, H - 0.56, -0.06)
		var el = Vector3(s * 0.1, -0.4, -0.02)
		var hd = Vector3(-s * 0.02, -0.38, -0.05)
		_joint(arm, Vector3.ZERO, 0.045)
		_limb(arm, Vector3.ZERO, el, 0.034, 0.03)
		var elbow = Spatial.new()
		elbow.name = "elbowR" if s > 0 else "elbowL"
		arm.add_child(elbow)
		elbow.translation = el
		_joint(elbow, Vector3.ZERO, 0.033)
		_limb(elbow, Vector3.ZERO, hd, 0.03, 0.026)
		var hand = Spatial.new()
		hand.name = "handR" if s > 0 else "handL"
		elbow.add_child(hand)
		hand.translation = hd
		_hand(hand, s, s > 0)
		if s > 0:
			var bat = Spatial.new()
			bat.name = "bat"
			hand.add_child(bat)
			var bm = MeshInstance.new()
			bm.mesh = _bat_mesh()
			bm.material_override = Game.cache["tung_bat"]
			bat.add_child(bm)
			bat.transform.basis = basis_y(Vector3(0.32, -0.94, -0.12).normalized())
			bm.translation = Vector3(0, -0.1, 0)
	# Legs: hip -> knee -> ankle -> foot
	for s in [-1, 1]:
		var leg = Spatial.new()
		leg.name = "legL" if s < 0 else "legR"
		root.add_child(leg)
		leg.translation = Vector3(s * 0.12, LEGS + 0.02, 0)
		_joint(leg, Vector3.ZERO, 0.042)
		_limb(leg, Vector3.ZERO, Vector3(0, -0.3, 0), 0.04, 0.034)
		var knee = Spatial.new()
		knee.name = "kneeL" if s < 0 else "kneeR"
		leg.add_child(knee)
		knee.translation = Vector3(0, -0.3, 0)
		_joint(knee, Vector3.ZERO, 0.036)
		_limb(knee, Vector3.ZERO, Vector3(0, -0.3, 0), 0.034, 0.03)
		var ankle = Spatial.new()
		ankle.name = "ankleL" if s < 0 else "ankleR"
		knee.add_child(ankle)
		ankle.translation = Vector3(0, -0.3, 0)
		_joint(ankle, Vector3.ZERO, 0.03)
		# capsule meshes lie along Z in Godot 3: exactly how a foot should lie
		var foot = MeshInstance.new()
		var fm = CapsuleMesh.new()
		fm.radius = 0.045
		fm.mid_height = 0.11
		fm.radial_segments = 16
		foot.mesh = fm
		foot.material_override = lite
		ankle.add_child(foot)
		foot.translation = Vector3(0, 0.0, -0.06)
	return Models.finish(root, LEGS + H, "TUNG TUNG TUNG SAHUR")


# ------------------------------------------------------------------ materials
static func _materials() -> void:
	if Game.cache.has("tung_wood") and Game.cache.get("tung_potato") == Mats.potato():
		return
	Game.cache["tung_potato"] = Mats.potato()
	var sh: Shader = Mats.shader("res://scripts/carved_wood.shader")
	var wood = ShaderMaterial.new()
	wood.shader = sh
	wood.set_shader_param("noise_tex", Mats.noise_tex())
	wood.set_shader_param("lite", Mats.potato())
	var lite: ShaderMaterial = wood.duplicate()
	lite.set_shader_param("cylindrical", false)
	lite.set_shader_param("cavity", 0.0)
	lite.set_shader_param("grain_freq", 400.0)
	var bat: ShaderMaterial = lite.duplicate()
	bat.set_shader_param("base", Color(0.78, 0.6, 0.38))
	bat.set_shader_param("dark", Color(0.5, 0.34, 0.18))
	bat.set_shader_param("light", Color(0.95, 0.82, 0.6))
	var eye = ShaderMaterial.new()
	eye.shader = Mats.shader("res://scripts/eye.shader")
	Game.cache["tung_wood"] = wood
	Game.cache["tung_lite"] = lite
	Game.cache["tung_bat"] = bat
	Game.cache["tung_eye"] = eye


# ------------------------------------------------------------------ the carved log
static func _g(x: float, y: float, cx: float, cy: float, sx: float, sy: float) -> float:
	var dx = (x - cx) / sx
	var dy = (y - cy) / sy
	return exp(-0.5 * (dx * dx + dy * dy))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var t = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _mouth_y(x: float) -> float:
	return -0.245 + 1.45 * x * x - 0.06 * x


## Carved relief. x = arc length from the front (+X side positive), fy = height above the eye line.
static func _face(x: float, fy: float) -> float:
	var d = 0.0
	for s in [-1.0, 1.0]:
		var ex: float = s * EX
		d -= 0.04 * _g(x, fy, ex, 0.0, 0.075, 0.07)
		d += 0.02 * _g(x, fy, ex, -0.115, 0.06, 0.022)
		var dx: float = x - ex
		var by: float = 0.14 + 0.028 * (1.0 - clamp((dx / 0.11) * (dx / 0.11), 0.0, 1.0)) - s * dx * 0.08
		d += 0.042 * exp(-0.5 * pow((fy - by) / 0.02, 2.0)) * exp(-0.5 * pow(dx / 0.08, 2.0))
		var smirk: float = 0.012 if s < 0 else 0.0
		d += 0.05 * _g(x, fy, s * 0.15, -0.19 + smirk, 0.055, 0.05)
		var nl = _seg_dist(Vector2(x, fy), Vector2(s * 0.052, -0.135), Vector2(s * 0.178, -0.2 + smirk))
		d -= 0.016 * exp(-0.5 * pow(nl / 0.008, 2.0))
		var cx: float = s * 0.178
		var cy = _mouth_y(cx)
		d -= 0.022 * _g(x, fy, cx, cy, 0.013, 0.015)
		d += 0.012 * _g(x, fy, cx - s * 0.014, cy + 0.012, 0.016, 0.02)
		d += 0.026 * _g(x, fy, s * 0.045, -0.152, 0.022, 0.018)
		d -= 0.012 * _g(x, fy, s * 0.03, -0.172, 0.011, 0.008)
	for wy in [0.205, 0.24]:
		d -= 0.008 * exp(-0.5 * pow((fy - wy) / 0.006, 2.0)) * exp(-0.5 * pow(x / 0.1, 2.0))
	if fy < 0.08 and fy > -0.22:
		var t: float = clamp((0.03 - fy) / 0.18, 0.0, 1.0)
		var w: float = lerp(0.028, 0.055, t)
		var a: float = lerp(0.026, 0.11, t)
		var vy: float = smoothstep(0.07, 0.0, fy) * (1.0 - smoothstep(-0.155, -0.185, fy))
		d += a * exp(-0.5 * x * x / (w * w)) * vy
	d += 0.055 * _g(x, fy, 0.0, -0.14, 0.045, 0.034)
	var my = _mouth_y(x)
	var env: float = 1.0 - smoothstep(0.15, 0.185, abs(x))
	d -= 0.042 * exp(-0.5 * pow((fy - my) / 0.0065, 2.0)) * env
	d += 0.018 * exp(-0.5 * pow((fy - my - 0.018) / 0.011, 2.0)) * (1.0 - smoothstep(0.11, 0.17, abs(x)))
	d += 0.03 * exp(-0.5 * pow((fy - my + 0.028) / 0.016, 2.0)) * (1.0 - smoothstep(0.09, 0.155, abs(x)))
	d += 0.024 * _g(x, fy, 0.0, -0.345, 0.07, 0.04)
	return d


## returns (radius, relief)
static func _radius(th: float, y: float) -> Vector2:
	var r = R + 0.004 * sin(th * 3.0 + y * 2.3) + 0.003 * sin(th * 7.0 - y * 4.1) + 0.002 * sin(th * 13.0 + y * 9.0)
	var relief = 0.0
	if abs(th) < 1.25 and y > EY - 0.5:
		relief = _face(th * R, y - EY)
	r += relief
	var ft = 0.05
	if y > H - ft:
		var dy = y - (H - ft)
		r -= ft - sqrt(max(ft * ft - dy * dy, 0.0))
	var fb = 0.03
	if y < fb:
		var db = fb - y
		r -= fb - sqrt(max(fb * fb - db * db, 0.0))
	return Vector2(r, relief)


static func _body_mesh() -> ArrayMesh:
	# Three levels of detail: potato / low / high (GLES2 redraws the mesh once per light).
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	var key = "tung_body_%d" % q
	if Game.cache.has(key):
		return Game.cache[key]
	var seg = [72, 128, 200][q]
	var face_dy = [0.018, 0.011, 0.007][q]
	var body_dy = [0.09, 0.06, 0.045][q]
	var ys = []
	var y = 0.0
	while y < H:
		ys.append(y)
		var dy = face_dy if y > EY - 0.45 else body_dy
		if y < 0.04 or y > H - 0.06:
			dy = face_dy
		y += dy
	ys.append(H)
	var rows = ys.size()
	var cols = seg + 1
	var pos = PoolVector3Array()
	var uv = PoolVector2Array()
	var colr = PoolColorArray()
	pos.resize(rows * cols)
	uv.resize(rows * cols)
	colr.resize(rows * cols)
	for j in rows:
		var yy: float = ys[j]
		for i in cols:
			var u = float(i) / seg
			var th = (u - 0.5) * TAU
			var rr = _radius(th, yy)
			var occ = 1.0
			if rr.y < 0.0:
				occ = clamp(1.0 + rr.y * 16.0, 0.3, 1.0)
			var k = j * cols + i
			pos[k] = Vector3(sin(th) * rr.x, yy, -cos(th) * rr.x)
			uv[k] = Vector2(u, yy / H)
			colr[k] = Color(occ, occ, occ)
	# Normals from the grid itself, always pointing out of the log
	var nrm = PoolVector3Array()
	nrm.resize(rows * cols)
	for j in rows:
		for i in cols:
			var il = i - 1 if i > 0 else seg - 1
			var ir = i + 1 if i < seg else 1
			var jd = max(j - 1, 0)
			var ju = min(j + 1, rows - 1)
			var du: Vector3 = pos[j * cols + ir] - pos[j * cols + il]
			var dv: Vector3 = pos[ju * cols + i] - pos[jd * cols + i]
			var n = dv.cross(du).normalized()
			var p: Vector3 = pos[j * cols + i]
			if n.dot(Vector3(p.x, 0, p.z)) < 0.0:
				n = -n
			nrm[j * cols + i] = n
	var idx = PoolIntArray()
	for j in rows - 1:
		for i in seg:
			var a = j * cols + i
			var b = a + 1
			var c = a + cols
			var d = c + 1
			idx.append_array([a, b, c, b, d, c])
	# caps
	var top_c = pos.size()
	pos.append(Vector3(0, H, 0))
	nrm.append(Vector3.UP)
	uv.append(Vector2(0.5, 1.0))
	colr.append(Color.white)
	var bot_c = pos.size()
	pos.append(Vector3.ZERO)
	nrm.append(Vector3.DOWN)
	uv.append(Vector2(0.5, 0.0))
	colr.append(Color.white)
	var last = (rows - 1) * cols
	for i in seg:
		idx.append_array([top_c, last + i + 1, last + i, bot_c, i, i + 1])
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = colr
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	Game.cache[key] = mesh
	return mesh


# ------------------------------------------------------------------ limbs, hands, bat
static func basis_y(dir: Vector3) -> Basis:
	var yv = dir.normalized()
	var ref = Vector3.FORWARD if abs(yv.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var xv = yv.cross(ref).normalized()
	return Basis(xv, yv, xv.cross(yv).normalized())


static func _limb(p: Spatial, a: Vector3, b: Vector3, r1: float, r2: float) -> void:
	var mi = MeshInstance.new()
	mi.mesh = Models.cyl(r2, r1, a.distance_to(b), 16, 2)
	mi.material_override = Game.cache["tung_lite"]
	p.add_child(mi)
	mi.transform = Transform(basis_y(b - a), (a + b) * 0.5)


static func _joint(p: Spatial, at: Vector3, r: float) -> void:
	var mi = MeshInstance.new()
	mi.mesh = Models.sphere(r, -1, 16, 8)
	mi.material_override = Game.cache["tung_lite"]
	p.add_child(mi)
	mi.translation = at


static func _hand(p: Spatial, s: float, fist: bool) -> void:
	var lite: ShaderMaterial = Game.cache["tung_lite"]
	var palm = MeshInstance.new()
	palm.mesh = Models.sphere(0.04, 0.07, 16, 8)
	palm.material_override = lite
	p.add_child(palm)
	for f in 4:
		var fz = -0.02 + f * 0.014
		var fing = Models.capsule_y(p, 0.011, 0.055 if fist else 0.07, lite)
		if fist:
			fing.translation = Vector3(-s * 0.025, -0.02 - f * 0.004, fz - 0.03)
			fing.rotation = Vector3(0.2, 0, s * 1.3)
		else:
			fing.translation = Vector3(s * 0.008, -0.05, fz - 0.01)
			fing.rotation = Vector3(0.1 * f - 0.15, 0, -s * 0.15)
	var thumb = Models.capsule_y(p, 0.012, 0.05, lite)
	thumb.translation = Vector3(-s * 0.02, 0.0, -0.04)
	thumb.rotation = Vector3(0.6, 0, -s * 0.5)


## Turned baseball bat (lathe). Knob at y = +0.1, barrel downwards.
static func _bat_mesh() -> ArrayMesh:
	if Game.cache.has("tung_batmesh"):
		return Game.cache["tung_batmesh"]
	var prof = [
		Vector2(0.0, 0.14), Vector2(0.028, 0.135), Vector2(0.036, 0.12), Vector2(0.03, 0.105),
		Vector2(0.018, 0.09), Vector2(0.017, -0.2), Vector2(0.019, -0.32), Vector2(0.028, -0.45),
		Vector2(0.04, -0.58), Vector2(0.046, -0.7), Vector2(0.047, -0.82), Vector2(0.044, -0.88),
		Vector2(0.032, -0.91), Vector2(0.0, -0.92),
	]
	var seg = 24
	var cols = seg + 1
	var pos = PoolVector3Array()
	var uv = PoolVector2Array()
	for j in prof.size():
		for i in cols:
			var a = float(i) / seg * TAU
			var pr: Vector2 = prof[j]
			pos.append(Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x))
			uv.append(Vector2(float(i) / seg, float(j) / prof.size()))
	var nrm = PoolVector3Array()
	nrm.resize(pos.size())
	for j in prof.size():
		for i in cols:
			var a = float(i) / seg * TAU
			var jd = max(j - 1, 0)
			var ju = min(j + 1, prof.size() - 1)
			var pd: Vector2 = prof[ju] - prof[jd]
			# profile tangent (dr, dy) -> outward normal (dy, -dr) in the (radial, y) plane
			var n2 = Vector2(-pd.y, pd.x).normalized()
			if n2.x < 0.0:
				n2 = -n2
			nrm[j * cols + i] = Vector3(cos(a) * n2.x, n2.y, sin(a) * n2.x).normalized()
	var idx = PoolIntArray()
	for j in prof.size() - 1:
		for i in seg:
			var a = j * cols + i
			var c = a + cols
			idx.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	Game.cache["tung_batmesh"] = mesh
	return mesh
