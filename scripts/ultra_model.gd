extends Reference
## 6-7 ULTRA — the boss of sector 3.5. What 67 is when it stops pretending to be a picture.
## A hunched thing nineteen metres tall, rising out of a pit in the middle of the arena: a wet,
## near-black hide over swollen veins that glow red with its heartbeat, ribs pushing out through
## the chest, a ridge of bone spines down its back, tendrils gripping the rim of the pit, two
## pairs of withered little arms twitching on its chest, and two enormous arms that stretch as
## far as they need to.
## It has no face. Where the head should be there is a scale, and on the scale the two numbers,
## solid and cracked with red light, the 6 against the 7, weighed for ever.
## Every surface is generated here (tubes along curves, lumpy with noise, normal-mapped skin).
##
## Faces -Z. Origin: the arena floor at the centre of its pit; the body goes on down into it.
## Joints (posed every frame by enemies/ultra.gd): "body", "head" (the scale: "beam", "pan0" with
## the 6, "pan1" with the 7, and "face", what the camera grades), "arm0_u", "arm0_f", "hand0"
## (its right arm, +X), "arm1_u", "arm1_f", "hand1" (its left, -X), "small0".."small3", "shield".

const HEIGHT = 22.0
const HEAD_PIVOT = Vector3(0, 16.4, -2.8)
const BEAM_Y = 4.6                       # the scale: beam height above the neck
const BEAM_HALF = 5.9
const HOOK = 0.6                         # from the beam end down to the ring the chains hang from
const CHAIN = 5.3                        # the plates hang this far under the beam ends
const PAN_R = 2.0
const DIGIT_H = 4.3
const FACE_UP = 1.5                      # the middle of the numbers
const FACE_Y = 16.4 + 1.5                # (photos are graded on it)
const SHOULDER = [Vector3(4.5, 12.4, -0.6), Vector3(-4.5, 12.4, -0.6)]
const L_UP = 9.0
const L_FORE = 9.5
const SKIN_UV = 0.35                     # skin texture repeats per metre of girth

var surfs = {}
var noise: OpenSimplexNoise


# ------------------------------------------------------------------ mesh building
func _init() -> void:
	noise = OpenSimplexNoise.new()
	noise.seed = 67
	noise.octaves = 3
	noise.period = 1.0
	noise.persistence = 0.5


func _s(name: String) -> Dictionary:
	if not surfs.has(name):
		# plain Arrays: a Pool*Array kept in a Dictionary is a copy every time it is read
		surfs[name] = {"p": [], "n": [], "t": [], "uv": [], "i": []}
	return surfs[name]


func commit(mats: Dictionary) -> ArrayMesh:
	var am = ArrayMesh.new()
	for k in surfs:
		var s = surfs[k]
		if s.p.size() == 0:
			continue
		var arr = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PoolVector3Array(s.p)
		arr[Mesh.ARRAY_NORMAL] = PoolVector3Array(s.n)
		arr[Mesh.ARRAY_TANGENT] = PoolRealArray(s.t)
		arr[Mesh.ARRAY_TEX_UV] = PoolVector2Array(s.uv)
		arr[Mesh.ARRAY_INDEX] = PoolIntArray(s.i)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, mats[k])
	surfs = {}
	return am


## Catmull-Rom through the control points, n samples (radii follow linearly).
static func smooth(ctrl: Array, rad: Array, n: int) -> Array:
	var pts = []
	var rs = []
	var m = ctrl.size()
	for k in n:
		var t = float(k) / float(n - 1) * (m - 1)
		var i = int(min(floor(t), m - 2))
		var f = t - i
		var p0: Vector3 = ctrl[max(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[min(i + 2, m - 1)]
		var f2 = f * f
		var f3 = f2 * f
		pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3))
		rs.append(lerp(float(rad[i]), float(rad[i + 1]), f))
	return [pts, rs]


## A tube along points, radius per point, an ellipse across (sn along the frame's normal, which
## starts out facing -Z, sb across it), lumpy with noise. UVs keep the skin's texels square.
func tube(surf: String, ctrl: Array, rad: Array, n: int, segs: int, sn := 1.0, sb := 1.0, bump := 0.0, bfreq := 0.6) -> void:
	var sm = smooth(ctrl, rad, n)
	var pts: Array = sm[0]
	var rs: Array = sm[1]
	var s = _s(surf)
	var base = s.p.size()
	var t0: Vector3 = (pts[1] - pts[0]).normalized()
	var nrm = Vector3(0, 0, -1) - t0 * t0.dot(Vector3(0, 0, -1))
	if nrm.length() < 0.1:
		nrm = Vector3(1, 0, 0) - t0 * t0.x
	nrm = nrm.normalized()
	var prev_t = t0
	var vacc = 0.0
	var ravg = 0.0
	for r in rs:
		ravg += r
	ravg = max(ravg / rs.size(), 0.05)
	var circ = TAU * ravg * max(sn, sb)
	for k in pts.size():
		var c: Vector3 = pts[k]
		var tg: Vector3
		if k == 0:
			tg = t0
		elif k == pts.size() - 1:
			tg = (pts[k] - pts[k - 1]).normalized()
		else:
			tg = (pts[k + 1] - pts[k - 1]).normalized()
		# parallel transport: turn the normal with the tangent, no twisting
		var ax = prev_t.cross(tg)
		if ax.length() > 1e-5:
			nrm = nrm.rotated(ax.normalized(), atan2(ax.length(), prev_t.dot(tg)))
		nrm = (nrm - tg * tg.dot(nrm)).normalized()
		prev_t = tg
		var bn = tg.cross(nrm).normalized()
		if k > 0:
			vacc += c.distance_to(pts[k - 1])
		var r: float = rs[k]
		for j in segs + 1:
			var a = TAU * float(j) / segs
			var ca = cos(a)
			var sa = sin(a)
			var dir = nrm * ca * sn + bn * sa * sb
			var p0 = c + dir * r
			var lump = 1.0
			if bump > 0.0:
				lump += bump * noise.get_noise_3dv(p0 * bfreq)
			s.p.append(c + dir * r * lump)
			s.n.append((nrm * ca / sn + bn * sa / sb).normalized())
			var tng = (-nrm * sa * sn + bn * ca * sb).normalized()
			s.t.append_array([tng.x, tng.y, tng.z, 1.0])
			s.uv.append(Vector2(float(j) / segs * circ * SKIN_UV, vacc * SKIN_UV))
	var row = segs + 1
	for k in pts.size() - 1:
		for j in segs:
			var a = base + k * row + j
			var b = a + row
			s.i.append_array([a, b, a + 1, a + 1, b, b + 1])


## A lumpy ellipsoid.
func blob(surf: String, c: Vector3, r: Vector3, segs := 24, rings := 14, bump := 0.0, bfreq := 0.6) -> void:
	var s = _s(surf)
	var base = s.p.size()
	for i in rings + 1:
		var th = PI * float(i) / rings
		for j in segs + 1:
			var ph = TAU * float(j) / segs
			var u = Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p0 = c + u * r
			var lump = 1.0
			if bump > 0.0:
				lump += bump * noise.get_noise_3dv(p0 * bfreq)
			s.p.append(c + u * r * lump)
			s.n.append(Vector3(u.x / r.x, u.y / r.y, u.z / r.z).normalized())
			s.t.append_array([-sin(ph), 0.0, cos(ph), 1.0])
			s.uv.append(Vector2(float(j) / segs * TAU * r.x * SKIN_UV, float(i) / rings * PI * r.y * SKIN_UV))
	var row = segs + 1
	for i in rings:
		for j in segs:
			var a = base + i * row + j
			var b = a + row
			s.i.append_array([a, b, a + 1, a + 1, b, b + 1])


## A horn / spine / tooth / claw: a curved cone from base along dir, bending by `bend`.
func spike(surf: String, base: Vector3, dir: Vector3, length: float, r: float, bend := Vector3.ZERO, segs := 8) -> void:
	var d = dir.normalized()
	var ctrl = [base - d * r * 0.6, base + d * length * 0.35 + bend * 0.15, base + d * length * 0.7 + bend * 0.55, base + d * length + bend]
	tube(surf, ctrl, [r, r * 0.8, r * 0.45, 0.01], 6, segs)


# ------------------------------------------------------------------ materials
static func skin_mat(bone := false) -> ShaderMaterial:
	var key = "ultra_mat_%s" % bone
	if Game.cache.has(key):
		return Game.cache[key]
	var m = ShaderMaterial.new()
	m.shader = Mats.shader("res://scripts/ultra_skin.shader")
	m.set_shader_param("albedo_tex", load("res://textures/bone_ultra.png" if bone else "res://textures/skin_ultra.png"))
	m.set_shader_param("normal_tex", load("res://textures/skin_ultra_n.png"))
	m.set_shader_param("bone", bone)
	m.set_shader_param("uv_scale", Vector2(1, 1) * (0.7 if bone else 1.0))
	Game.cache[key] = m
	return m


static func shield_mat() -> ShaderMaterial:
	var sh = Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D glyphs : hint_albedo;
uniform float power = 1.0;
uniform float hit = 0.0;
void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	f = f * f * f;
	vec2 uv = UV * vec2(30.0, 14.0) + vec2(TIME * 0.04, -TIME * 0.11);
	vec2 cell = floor(uv);
	float pick = step(0.5, fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453));
	float g = texture(glyphs, fract(uv) * vec2(0.5, 1.0) + vec2(pick * 0.5, 0.0)).a;
	float scan = 0.5 + 0.5 * sin(UV.y * 90.0 - TIME * 3.0);
	vec3 c = vec3(0.8, 0.85, 0.9) * (f * 0.26 + g * (0.04 + 0.2 * f) * (0.6 + 0.4 * scan));
	c += vec3(1.0, 0.2, 0.12) * hit * (0.25 + f);
	ALBEDO = c * power;
}
"""
	var m = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_param("glyphs", load("res://textures/67_glyphs.png"))
	return m


# ------------------------------------------------------------------ the body
func _torso_frame(y: float) -> Array:
	# spine centre z and radius at height y (the same curve the torso is built along)
	var ys = [-15.0, -7.0, 0.0, 5.0, 9.0, 12.4, 14.4]
	var zs = [1.6, 1.7, 1.4, 0.9, 0.2, -0.6, -1.8]
	var rs = [2.6, 3.0, 3.2, 3.9, 4.3, 3.6, 2.0]
	for i in ys.size() - 1:
		if y <= ys[i + 1]:
			var f = clamp((y - ys[i]) / (ys[i + 1] - ys[i]), 0.0, 1.0)
			return [lerp(zs[i], zs[i + 1], f), lerp(rs[i], rs[i + 1], f)]
	return [zs[-1], rs[-1]]


func _body(root: Spatial, skin: Material, bone: Material) -> Spatial:
	var body = Models.pivot(root, "body")
	var SX = 1.25
	var SZ = 0.8
	var ctrl = []
	var rad = []
	for y in [-15.0, -7.0, 0.0, 5.0, 9.0, 12.4, 14.4]:
		var fr = _torso_frame(y)
		ctrl.append(Vector3(0, y, fr[0]))
		rad.append(fr[1])
	tube("skin", ctrl, rad, 44, 32, SZ, SX, 0.07, 0.45)
	# shoulders: great knots of muscle where the arms come out
	for sd in [1.0, -1.0]:
		blob("skin", Vector3(3.9 * sd, 12.2, -0.4), Vector3(2.3, 2.0, 2.1), 16, 9, 0.08, 0.7)
		blob("skin", Vector3(2.6 * sd, 13.4, -0.2), Vector3(2.0, 1.4, 1.8), 14, 8, 0.08, 0.7)
	# great slabs of chest, a hump of muscle behind the neck, collarbones under the skin
	for sd in [1.0, -1.0]:
		var fr = _torso_frame(9.6)
		blob("skin", Vector3(2.3 * sd, 9.6, fr[0] - fr[1] * SZ * 0.72), Vector3(2.5, 1.8, 1.2), 16, 9, 0.07, 0.8)
		tube("bone", [Vector3(0.6 * sd, 12.2, -2.9), Vector3(2.4 * sd, 12.5, -2.6), Vector3(4.0 * sd, 12.9, -1.6)], [0.3, 0.32, 0.26], 10, 8)
		blob("skin", Vector3(1.6 * sd, 13.6, 0.6), Vector3(2.2, 1.6, 2.0), 14, 8, 0.08, 0.7)
	for k in 4:
		var y = 1.0 + k * 1.1
		var fr = _torso_frame(y)
		blob("skin", Vector3(0, y, fr[0] - fr[1] * SZ * 0.8), Vector3(fr[1] * 0.95, 0.55, 0.9), 16, 6, 0.1, 1.2)
	# the neck, hanging the head forward and low
	tube("skin", [Vector3(0, 12.8, -0.9), Vector3(0, 14.6, -1.7), Vector3(0, 15.8, -2.3), Vector3(0, 16.6, -2.6)], [2.2, 1.9, 1.7, 1.6], 12, 20, 0.9, 1.1, 0.08, 0.8)
	# ribs pushing out through the chest, six a side
	for k in 6:
		var y = 4.6 + k * 1.25
		for sd in [1.0, -1.0]:
			var pts = []
			var rr = []
			for q in 7:
				var th = lerp(0.3, 1.75, q / 6.0)
				var yy = y - q * 0.16
				var fr = _torso_frame(yy)
				var r = fr[1] * 1.03
				pts.append(Vector3(sd * sin(th) * r * SX, yy, fr[0] - cos(th) * r * SZ))
				rr.append(0.24 - q * 0.012)
			tube("bone", pts, rr, 12, 6)
	# a sternum of fused bone
	var stp = []
	for y in [4.4, 7.0, 9.6, 11.4]:
		var fr = _torso_frame(y)
		stp.append(Vector3(0, y, fr[0] - fr[1] * SZ * 1.02))
	tube("bone", stp, [0.25, 0.32, 0.3, 0.2], 10, 8, 0.6, 1.2)
	# the ridge of spines down its back
	for k in 10:
		var y = 1.5 + k * 1.35
		var fr = _torso_frame(y)
		var base = Vector3(0, y, fr[0] + fr[1] * SZ * 0.95)
		var ln = 1.4 + 2.2 * sin(PI * (k + 1) / 11.0)
		spike("bone", base, Vector3(0, 0.55, 1.0), ln, 0.45, Vector3(0, 0.6, 0), 6)
		if k % 2 == 0:
			for sd in [1.0, -1.0]:
				spike("bone", base + Vector3(sd * 1.6, -0.3, -0.4), Vector3(sd * 0.6, 0.5, 1.0), ln * 0.55, 0.28, Vector3(0, 0.3, 0), 6)
	# tendrils: some gripping over the rim of the pit, some hanging into the dark
	for k in 9:
		var a = TAU * (k + 0.5) / 9.0
		var dirv = Vector3(sin(a), 0, -cos(a))
		var side = Vector3(cos(a), 0, sin(a))
		var wob = side * (0.6 if k % 2 == 0 else -0.6)
		var r0 = 2.8
		if k % 3 != 1:
			# over the rim and onto the floor
			var c = [dirv * r0 + Vector3(0, -3.5, 0), dirv * 4.8 + Vector3(0, -1.0, 0) + wob, dirv * 6.25 + Vector3(0, 0.75, 0), dirv * 7.6 + Vector3(0, 0.32, 0) - wob * 0.5, dirv * 9.0 + Vector3(0, 0.14, 0) + wob, dirv * 10.2 + Vector3(0, 0.08, 0)]
			tube("skin", c, [1.0, 0.8, 0.62, 0.48, 0.3, 0.03], 18, 9, 0.75, 1.0, 0.12, 1.2)
		else:
			var c = [dirv * r0 + Vector3(0, -4.0, 0), dirv * 4.6 + Vector3(0, -7.0, 0) + wob, dirv * 5.2 + Vector3(0, -11.0, 0) - wob, dirv * 4.4 + Vector3(0, -15.0, 0)]
			tube("skin", c, [1.1, 0.8, 0.55, 0.2], 12, 9, 1.0, 1.0, 0.12, 1.2)
	var mi = MeshInstance.new()
	mi.mesh = commit({"skin": skin, "bone": bone})
	mi.name = "mesh"
	body.add_child(mi)
	return body


## The head is not a head: a scale. A column of vertebrae out of the neck, a beam across the
## top, a pan hanging from each end on three chains, and in the pans the two numbers, solid,
## black stone cracked with red light (ultra_digits.gd): the 6 on its right, the 7 on its left.
## It weighs them, all the time. ultra.gd tips the beam ("beam") and swings the pans ("pan0" the
## 6, "pan1" the 7); the whole scale turns to whoever is looking at it.
func _head(root: Spatial, skin: Material, bone: Material) -> Spatial:
	var head = Models.pivot(root, "head", HEAD_PIVOT)
	var iron = iron_mat()
	# where the neck ends: a ring of bone spines, and the column going up out of it
	for k in 9:
		var a = TAU * k / 9.0
		spike("bone", Vector3(cos(a) * 1.3, -0.4, sin(a) * 1.3), Vector3(cos(a), 0.9, sin(a)), 1.6 + 0.5 * (k % 2), 0.28, Vector3(0, 0.4, 0), 7)
	for k in 6:
		var y = 0.2 + k * 0.72
		var r = lerp(0.95, 0.55, k / 5.0)
		blob("bone", Vector3(0, y, 0), Vector3(r, 0.3, r * 0.9), 18, 8, 0.12, 2.0)
		for sd in [1.0, -1.0]:
			spike("bone", Vector3(sd * r * 0.8, y, 0.1), Vector3(sd, -0.25, 0.5), 0.6 + 0.2 * (k % 2), 0.12, Vector3(0, -0.15, 0), 5)
	var mi = MeshInstance.new()
	mi.mesh = commit({"bone": bone})
	head.add_child(mi)
	tube("iron", [Vector3(0, -0.6, 0), Vector3(0, 2.0, 0), Vector3(0, BEAM_Y, 0)], [0.32, 0.28, 0.22], 6, 12)
	blob("iron", Vector3(0, BEAM_Y, 0), Vector3(0.62, 0.62, 0.62), 18, 10)
	var col = MeshInstance.new()
	col.mesh = commit({"iron": iron})
	head.add_child(col)
	# the beam, and the needle that shows which way it is tipping
	var beam = Models.pivot(head, "beam", Vector3(0, BEAM_Y, 0))
	tube("iron", [Vector3(BEAM_HALF + 0.3, 0.45, 0), Vector3(BEAM_HALF * 0.5, 0.05, 0), Vector3(0, -0.12, 0), Vector3(-BEAM_HALF * 0.5, 0.05, 0), Vector3(-BEAM_HALF - 0.3, 0.45, 0)], [0.16, 0.3, 0.42, 0.3, 0.16], 30, 12, 1.4, 0.8)
	spike("iron", Vector3(0, 0.2, 0), Vector3(0, 1, 0), 2.2, 0.16, Vector3.ZERO, 8)
	for sd in [1.0, -1.0]:
		blob("iron", Vector3(sd * BEAM_HALF, 0.38, 0), Vector3(0.3, 0.3, 0.3), 12, 6)
		spike("iron", Vector3(sd * (BEAM_HALF + 0.25), 0.45, 0), Vector3(sd, 0.6, 0), 1.1, 0.13, Vector3(0, 0.3, 0), 6)
	var bm = MeshInstance.new()
	bm.mesh = commit({"iron": iron})
	beam.add_child(bm)
	# the pans, hanging from the ends of the beam, each with its number standing in it
	var digits = load("res://scripts/ultra_digits.gd")
	for i in 2:
		var sd = 1.0 if i == 0 else -1.0
		var pan = Models.pivot(head, "pan%d" % i, Vector3(sd * BEAM_HALF, BEAM_Y + 0.38, 0))
		# a hook, a ring, three chains straight down round the number, a flat plate
		tube("iron", [Vector3(0, 0.1, 0), Vector3(0, -HOOK * 0.5, 0), Vector3(0, -HOOK, 0)], [0.12, 0.1, 0.1], 4, 8)
		tube("iron", _ring(PAN_R * 0.9, -HOOK, 24), _const(25, 0.08), 25, 6)
		for k in 3:
			var a = TAU * (k + 0.25) / 3.0
			var x = cos(a) * PAN_R * 0.9
			var z = sin(a) * PAN_R * 0.9
			var pts = []
			var rr = []
			for q in 17:
				var t = q / 16.0
				pts.append(Vector3(x, lerp(-HOOK, -CHAIN, t), z))
				rr.append(0.06 + 0.035 * abs(sin(t * PI * 22.0)))    # links
			tube("iron", pts, rr, 17, 6)
		blob("iron", Vector3(0, -CHAIN - 0.06, 0), Vector3(PAN_R, 0.13, PAN_R), 28, 8)
		tube("iron", _ring(PAN_R * 0.97, -CHAIN + 0.02, 28), _const(29, 0.07), 29, 6)
		var pm = MeshInstance.new()
		pm.mesh = commit({"iron": iron})
		pan.add_child(pm)
		var dm = ShaderMaterial.new()
		dm.shader = Mats.shader("res://scripts/ultra_digit.shader")
		var num = MeshInstance.new()
		num.mesh = digits.mesh("6" if i == 0 else "7", DIGIT_H, dm)
		num.name = "num"
		pan.add_child(num)
		num.translation = Vector3(0, -CHAIN + 0.07, 0)
	# what the camera grades as its face: the middle of the scale, between the two numbers
	var face = Spatial.new()
	face.name = "face"
	head.add_child(face)
	face.translation = Vector3(0, FACE_UP, -0.6)
	return head


static func _ring(r: float, y: float, n: int) -> Array:
	var out = []
	for k in n + 1:
		var a = TAU * k / n
		out.append(Vector3(cos(a) * r, y, sin(a) * r))
	return out


static func _const(n: int, v: float) -> Array:
	var out = []
	for k in n:
		out.append(v)
	return out


static func iron_mat() -> SpatialMaterial:
	if Game.cache.has("ultra_iron"):
		return Game.cache["ultra_iron"]
	var m = SpatialMaterial.new()
	m.albedo_color = Color(0.16, 0.15, 0.14)
	m.albedo_texture = load("res://textures/bone_ultra.png")
	m.metallic = 0.85
	m.roughness = 0.42
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.flags_vertex_lighting = Mats.potato()
	Game.cache["ultra_iron"] = m
	return m


func _arm(root: Spatial, i: int, skin: Material, bone: Material) -> void:
	var sd = 1.0 if i == 0 else -1.0
	var up = Models.pivot(root, "arm%d_u" % i)
	tube("skin", [Vector3(0, -0.6, 0), Vector3(0, 2.0, 0), Vector3(0, 5.0, 0), Vector3(0, 7.6, 0), Vector3(0, L_UP + 0.3, 0)], [1.55, 1.6, 1.35, 1.1, 0.95], 18, 16, 1.0, 1.1, 0.12, 0.8)
	var mi = MeshInstance.new()
	mi.mesh = commit({"skin": skin})
	up.add_child(mi)
	var fo = Models.pivot(root, "arm%d_f" % i)
	blob("skin", Vector3(0, 0, 0), Vector3(1.15, 1.15, 1.15), 14, 8, 0.1, 1.0)
	tube("skin", [Vector3(0, 0, 0), Vector3(0, 2.5, 0), Vector3(0, 6.0, 0), Vector3(0, L_FORE, 0)], [1.0, 1.08, 0.86, 0.66], 16, 14, 1.0, 1.15, 0.12, 0.8)
	# bone spurs out of the elbow
	spike("bone", Vector3(0, 0.2, 0.9), Vector3(0, -0.4, 1.0), 1.6, 0.28, Vector3(0, -0.5, 0), 6)
	var mf = MeshInstance.new()
	mf.mesh = commit({"skin": skin, "bone": bone})
	fo.add_child(mf)
	# the hand: +Y along the fingers, palm towards -Z, a claw half closed
	var hand = Models.pivot(root, "hand%d" % i)
	tube("skin", [Vector3(0, -0.4, 0.1), Vector3(0, 0.8, 0), Vector3(0, 1.8, -0.05), Vector3(0, 2.5, -0.1)], [0.8, 1.0, 1.05, 0.95], 10, 14, 0.42, 1.18, 0.08, 1.0)
	for f in 4:
		var x = lerp(-0.85, 0.85, f / 3.0)
		var ln = 1.0 - abs(f - 1.5) * 0.12
		var c = [Vector3(x, 2.2, -0.05), Vector3(x * 1.1, 3.3 * ln + 0.2, -0.3), Vector3(x * 1.15, 4.2 * ln + 0.2, -1.0), Vector3(x * 1.15, 4.4 * ln + 0.2, -1.9)]
		tube("skin", c, [0.34, 0.32, 0.27, 0.22], 10, 8, 1.0, 1.0, 0.1, 1.5)
		spike("bone", c[3] + Vector3(0, -0.05, -0.1), Vector3(0, -0.45, -1.0), 1.0, 0.2, Vector3(0, -0.35, 0), 6)
	var tx = -sd * 1.05
	var tc = [Vector3(tx, 0.6, -0.1), Vector3(tx * 1.7, 1.4, -0.7), Vector3(tx * 1.9, 2.1, -1.5)]
	tube("skin", tc, [0.4, 0.34, 0.26], 10, 10, 1.0, 1.0, 0.1, 1.5)
	spike("bone", tc[2], Vector3(0, 0.3, -1.0), 0.9, 0.2, Vector3(0, -0.3, 0), 6)
	var mh = MeshInstance.new()
	mh.mesh = commit({"skin": skin, "bone": bone})
	hand.add_child(mh)


## Withered little arms on its chest, twitching.
func _small_arm(root: Spatial, k: int, skin: Material, bone: Material) -> void:
	var sd = 1.0 if k % 2 == 0 else -1.0
	var y = 8.2 if k < 2 else 5.6
	var fr = _torso_frame(y)
	var at = Vector3(sd * 2.6, y, fr[0] - fr[1] * 0.62)
	var p = Models.pivot(root, "small%d" % k, at)
	var e = Vector3(sd * 1.6, -2.0, -1.4)
	var w = Vector3(sd * 0.4, -3.4, -2.6)
	tube("skin", [Vector3(0, 0.2, 0.4), Vector3(sd * 0.6, -0.8, -0.6), e], [0.45, 0.36, 0.3], 10, 10, 1.0, 1.0, 0.15, 1.5)
	tube("skin", [e, (e + w) * 0.5 + Vector3(0, 0.3, 0), w], [0.3, 0.26, 0.2], 10, 10, 1.0, 1.0, 0.15, 1.5)
	for f in 3:
		var dv = Vector3(sd * (f - 1) * 0.4, -0.6, -1.0)
		spike("bone", w, dv, 0.9, 0.09, Vector3(0, -0.3, 0), 5)
	var mi = MeshInstance.new()
	mi.mesh = commit({"skin": skin, "bone": bone})
	p.add_child(mi)


static func build() -> Spatial:
	var b = load("res://scripts/ultra_model.gd").new()
	var root = Spatial.new()
	root.name = "SixSevenUltra"
	var skin = skin_mat(false)
	var bone = skin_mat(true)
	b._body(root, skin, bone)
	b._head(root, skin, bone)
	for i in 2:
		b._arm(root, i, skin, bone)
	for k in 4:
		b._small_arm(root, k, skin, bone)
	# its shield: a shell of drifting sixes and sevens (ultra.gd fades it, the anchors break it)
	var sh = MeshInstance.new()
	sh.mesh = Models.sphere(15.0, 30.0, 48, 24)
	sh.material_override = shield_mat()
	sh.name = "shield"
	sh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	root.add_child(sh)
	sh.translation = Vector3(0, 6.5, 0)
	# only its own lights touch it (ultra.gd): the hall's lamps would cost a pass each
	Models.set_layers(root, Geo.VIS_ACTOR)
	root.set_meta("face_node", "head/face")
	return Models.finish(root, HEIGHT, "6-7 ultra")
