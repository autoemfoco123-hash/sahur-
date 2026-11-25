class_name Models
## Mesh helpers for the code-built models. Every model faces -Z. (Godot 3)


static func part(parent: Spatial, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance:
	var mi = MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.translation = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	return mi


static func pivot(parent: Spatial, pname: String, pos := Vector3.ZERO) -> Spatial:
	var n = Spatial.new()
	n.name = pname
	parent.add_child(n)
	n.translation = pos
	return n


static func sphere(r: float, h := -1.0, seg := 32, rings := 16) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if h < 0.0 else h
	m.radial_segments = seg
	m.rings = rings
	return m


static func cyl(top: float, bot: float, h: float, seg := 24, rings := 4) -> CylinderMesh:
	var m = CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bot
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m


static func box(s: Vector3) -> CubeMesh:
	var m = CubeMesh.new()
	m.size = s
	return m


## Box with a vertex every ~`step` metres (for per-vertex lighting on potato).
static func box_sub(s: Vector3, step := 0.6) -> CubeMesh:
	var m = CubeMesh.new()
	m.size = s
	m.subdivide_width = int(max(s.x / step - 1.0, 0.0))
	m.subdivide_height = int(max(s.y / step - 1.0, 0.0))
	m.subdivide_depth = int(max(s.z / step - 1.0, 0.0))
	return m


static func torus(inner: float, outer: float, rings := 32, rseg := 16) -> TorusMesh:
	var m = TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = rseg
	return m


## Upright capsule (Godot 3 capsules lie along Z, so it sits in a rotated child).
## Returns the pivot: move/rotate that.
static func capsule_y(parent: Spatial, r: float, total_h: float, mat: Material) -> Spatial:
	var p = Spatial.new()
	parent.add_child(p)
	var m = CapsuleMesh.new()
	m.radius = r
	m.mid_height = max(total_h - 2.0 * r, 0.001)
	m.radial_segments = 12
	m.rings = 4
	var mi = MeshInstance.new()
	mi.mesh = m
	mi.material_override = mat
	p.add_child(mi)
	mi.rotation_degrees = Vector3(90, 0, 0)
	return p


## Cylinder stretched between two points.
static func limb(parent: Spatial, a: Vector3, b: Vector3, r: float, mat: Material, r2 := -1.0) -> MeshInstance:
	var mi = MeshInstance.new()
	mi.mesh = cyl(r if r2 < 0 else r2, r, a.distance_to(b), 14, 2)
	mi.material_override = mat
	parent.add_child(mi)
	mi.transform = Transform(basis_y(b - a), (a + b) * 0.5)
	return mi


## Basis whose Y axis points along `dir`.
static func basis_y(dir: Vector3) -> Basis:
	var yv = dir.normalized()
	var ref = Vector3.FORWARD if abs(yv.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var xv = yv.cross(ref).normalized()
	return Basis(xv, yv, xv.cross(yv).normalized())


static func finish(root: Spatial, height: float, display: String) -> Spatial:
	root.set_meta("height", height)
	root.set_meta("display", display)
	return root


static func set_layers(root: Node, layers: int) -> void:
	if root is VisualInstance and not (root is Light):
		(root as VisualInstance).layers = layers
	for c in root.get_children():
		set_layers(c, layers)
