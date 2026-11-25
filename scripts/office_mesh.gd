extends Reference
## Static office geometry merged into a few chunk meshes: one draw call per chunk and material,
## instead of one per wall / tile (old GPUs and drivers choke on draw calls, not triangles).

const CHUNK = 12.0
const MAX_SEG = 4.2

var tools = {}     # "cx_cz_kind" -> SurfaceTool


func _st(at: Vector3, kind: String) -> SurfaceTool:
	var key = "%d_%d_%s" % [int(floor(at.x / CHUNK)), int(floor(at.z / CHUNK)), kind]
	if not tools.has(key):
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
	return tools[key]


## Quad a-b-c-d facing n (winding fixed automatically: Godot draws clockwise faces).
func quad(kind: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var ua = Vector2(0, 0)
	var ub = Vector2(1, 0)
	var uc = Vector2(1, 1)
	var ud = Vector2(0, 1)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t = b
		b = d
		d = t
		var tu = ub
		ub = ud
		ud = tu
	var st = _st((a + b + c + d) * 0.25, kind)
	for v in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.add_normal(n)
		st.add_uv(v[1])
		st.add_vertex(v[0])


## Horizontal plane split per chunk (floor faces up, ceiling faces down).
func plane(kind: String, from: Vector2, to: Vector2, y: float, up: bool) -> void:
	var x = from.x
	while x < to.x - 0.001:
		var x1 = min(to.x, (floor(x / CHUNK) + 1.0) * CHUNK)
		var z = from.y
		while z < to.y - 0.001:
			var z1 = min(to.y, (floor(z / CHUNK) + 1.0) * CHUNK)
			quad(kind, Vector3(x, y, z), Vector3(x1, y, z), Vector3(x1, y, z1), Vector3(x, y, z1), Vector3(0, 1 if up else -1, 0))
			z = z1
		x = x1


## The four vertical sides of a box (top and bottom are never seen).
func box_sides(kind: String, c: Vector3, s: Vector3) -> void:
	var hx = s.x * 0.5
	var hz = s.z * 0.5
	var y0 = c.y - s.y * 0.5
	var h = s.y
	for sx in [1.0, -1.0]:
		var x = c.x + hx * sx
		_strip(kind, Vector3(x, y0, c.z - hz), Vector3(x, y0, c.z + hz), h, Vector3(sx, 0, 0))
	for sz in [1.0, -1.0]:
		var z = c.z + hz * sz
		_strip(kind, Vector3(c.x - hx, y0, z), Vector3(c.x + hx, y0, z), h, Vector3(0, 0, sz))


func _strip(kind: String, p0: Vector3, p1: Vector3, h: float, n: Vector3) -> void:
	var k = max(1, int(ceil(p0.distance_to(p1) / MAX_SEG)))
	for i in k:
		var a = p0.linear_interpolate(p1, float(i) / k)
		var b = p0.linear_interpolate(p1, float(i + 1) / k)
		quad(kind, a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0), n)


## Square ceiling light lens (UV 0..1 across it), facing down.
func panel(at: Vector3, size := 0.6) -> void:
	var h = size * 0.5
	quad("panel", at + Vector3(-h, 0, -h), at + Vector3(h, 0, -h), at + Vector3(h, 0, h), at + Vector3(-h, 0, h), Vector3.DOWN)


func commit(parent: Spatial, mats: Dictionary) -> int:
	var n = 0
	for key in tools:
		var kind = key.split("_")[2]
		var mi = MeshInstance.new()
		mi.mesh = tools[key].commit()
		mi.material_override = mats[kind]
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		n += 1
	return n
