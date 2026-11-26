extends MeshInstance
## Tung's mouth in the jumpscare (Godot 3): the carved smile tears open. A dark hole that follows
## the smile line around the log's curve, raw red at the edges and black inside, with splinters of
## pale torn wood hanging from both lips. Drawn over the face (no depth test), so the carving can
## never cut into it. Lives under the model's "body" node: vertices are in body space.

const TM = preload("res://scripts/tung_model.gd")
const W = 0.205         # half width along the face (a bit past the carved corners)
const UP = 0.04         # how far the upper lip lifts (stays under the nose)
const DOWN = 0.19       # how far the jaw drops
const N = 32            # columns across
const M = 6             # rows from lip to lip

var _upper = []         # splinters: [u, width, length (share of the opening), slant]
var _lower = []


func _init() -> void:
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.vertex_color_use_as_albedo = true
	m.flags_no_depth_test = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.render_priority = 10
	material_override = m
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var r = RandomNumberGenerator.new()
	r.randomize()
	for i in 11:
		_upper.append([lerp(-0.84, 0.84, (i + r.randf_range(-0.35, 0.35)) / 10.0), r.randf_range(0.012, 0.03), r.randf_range(0.16, 0.48), r.randf_range(-0.35, 0.35)])
	for i in 9:
		_lower.append([lerp(-0.78, 0.78, (i + r.randf_range(-0.35, 0.35)) / 8.0), r.randf_range(0.014, 0.032), r.randf_range(0.12, 0.36), r.randf_range(-0.35, 0.35)])
	set_open(0.0)


## The upper and lower lip lines (face y) at u in -1..1, for an opening a in 0..1.
func _edges(u: float, a: float) -> Vector2:
	var x = u * W
	var k = pow(max(0.0, 1.0 - u * u), 0.7)
	var my = TM._mouth_y(x)
	return Vector2(my + 0.011 + UP * a * k, my - 0.011 - DOWN * a * k)


## Face coordinates (arc length from the front, height above the eye line) to body space.
func _p(x: float, fy: float, lift := 0.0) -> Vector3:
	var th = x / TM.R
	var rr = TM.R + 0.02 + lift
	return Vector3(sin(th) * rr, TM.EY + fy, -cos(th) * rr)


## a: 0 = a thin dark slit along the smile, 1 = torn wide open. wob: -1..1 shiver.
func set_open(a: float, wob := 0.0) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var raw = Color(0.24, 0.035, 0.02)
	var deep = Color(0.012, 0.0, 0.0)
	var grid = []
	for i in N + 1:
		var u = -1.0 + 2.0 * float(i) / N
		var e = _edges(u, a)
		var col = []
		for j in M + 1:
			var t = float(j) / M
			var inner = sin(t * PI) * (1.0 - pow(abs(u), 5.0))
			col.append([_p(u * W, lerp(e.x, e.y, t)), raw.linear_interpolate(deep, smoothstep(0.0, 0.5, inner))])
		grid.append(col)
	for i in N:
		for j in M:
			_quad(st, grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
	# torn wood, drawn after the hole
	for s in _upper:
		_splinter(st, s, a, true, wob)
	for s in _lower:
		_splinter(st, s, a, false, wob)
	mesh = st.commit()


func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_color(v[1])
		st.add_vertex(v[0])


func _splinter(st: SurfaceTool, s: Array, a: float, upper: bool, wob: float) -> void:
	var u: float = s[0]
	var e = _edges(u, a)
	var h = e.x - e.y
	if h < 0.035:
		return
	var dir = -1.0 if upper else 1.0
	var base_y = (e.x + 0.005) if upper else (e.y - 0.005)
	var length = h * float(s[2]) * (1.0 + 0.08 * wob)
	var x0 = u * W
	var hw = float(s[1]) * 0.5
	var tip = _p(x0 + float(s[3]) * length * 0.45, base_y + dir * length, 0.003)
	var base = Color(0.55, 0.4, 0.25)
	var pale = Color(0.92, 0.83, 0.64)
	st.add_color(base)
	st.add_vertex(_p(x0 - hw, base_y))
	st.add_color(base)
	st.add_vertex(_p(x0 + hw, base_y))
	st.add_color(pale)
	st.add_vertex(tip)
	# a second, shorter shard next to the long ones: torn, not cut
	if float(s[2]) > 0.3:
		var x1 = x0 + hw * 1.6
		st.add_color(base)
		st.add_vertex(_p(x1 - hw * 0.6, base_y))
		st.add_color(base)
		st.add_vertex(_p(x1 + hw * 0.6, base_y))
		st.add_color(pale)
		st.add_vertex(_p(x1 + hw, base_y + dir * length * 0.45, 0.003))
