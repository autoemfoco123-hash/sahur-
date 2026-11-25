class_name Models
## Code-built medium-poly brainrots. Every model faces -Z.

# ------------------------------------------------------------------ helpers
static func part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, pname := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if pname != "":
		mi.name = pname
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	return mi


static func pivot(parent: Node3D, pname: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	parent.add_child(n)
	n.position = pos
	return n


static func sphere(r: float, h := -1.0, seg := 32, rings := 16) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if h < 0.0 else h
	m.radial_segments = seg
	m.rings = rings
	return m


static func cyl(top: float, bot: float, h: float, seg := 24, rings := 4) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bot
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func capsule(r: float, h: float, seg := 24) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = 8
	return m


static func cone(r: float, h: float, seg := 12) -> CylinderMesh:
	return cyl(0.0, r, h, seg, 1)


static func torus(inner: float, outer: float, rings := 32, rseg := 16) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = rseg
	return m


static func prism(s: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = s
	return m


## Cylinder stretched between two points.
static func limb(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, r2 := -1.0) -> MeshInstance3D:
	var d := b - a
	var mi := part(parent, cyl(r if r2 < 0 else r2, r, d.length(), 16, 2), mat, (a + b) * 0.5)
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.basis = Basis(x, y, z)
	return mi


## Glossy black eye with a tiny glowing pupil — staring forward (-Z).
static func eye(parent: Node3D, pos: Vector3, r: float, pupil := Color(1, 1, 0.9), pupil_scale := 0.22, energy := 6.0) -> Node3D:
	var e := pivot(parent, "eye", pos)
	part(e, sphere(r, -1, 24, 12), Mats.eye_black())
	part(e, sphere(r * pupil_scale, -1, 12, 6), Mats.glow(pupil, energy), Vector3(0, 0, -r * 0.92))
	return e


## Row of pointed teeth along X. `down` = upper jaw teeth pointing down.
static func teeth(parent: Node3D, center: Vector3, width: float, count: int, h: float, down := true, curve := 0.0) -> void:
	var tm := Mats.teeth()
	var w := width / count
	for i in count:
		var fx := (i + 0.5) / count - 0.5
		var x := fx * width
		var z := curve * fx * fx * 4.0
		var hh := h * (0.75 + 0.5 * absf(sin(i * 2.7)))
		part(parent, prism(Vector3(w * 0.9, hh, w * 0.6)), tm, center + Vector3(x, -hh * 0.5 if down else hh * 0.5, z), Vector3(0 if down else 180, 0, 180 if down else 0))


## A gaping mouth: dark gums + two rows of teeth.
static func mouth(parent: Node3D, center: Vector3, width: float, height: float, n := 10, curve := 0.0) -> Node3D:
	var m := pivot(parent, "mouth", center)
	part(m, box(Vector3(width, height, 0.05)), Mats.gums())
	part(m, box(Vector3(width * 0.92, height * 0.6, 0.04)), Mats.std(Color.BLACK, 1.0), Vector3(0, 0, -0.01))
	teeth(m, Vector3(0, height * 0.5, -0.03), width * 0.95, n, height * 0.45, true, curve)
	teeth(m, Vector3(0, -height * 0.5, -0.03), width * 0.9, n - 1, height * 0.4, false, curve)
	return m


static func finish(root: Node3D, height: float, display: String) -> Node3D:
	root.set_meta("height", height)
	root.set_meta("display", display)
	return root


static func all_meshes(n: Node, out: Array) -> Array:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		all_meshes(c, out)
	return out


## Make something exist only through the hush visor (render layer 2).
static func nv_only(root: Node) -> void:
	if root is VisualInstance3D and not (root is Light3D):
		(root as VisualInstance3D).layers = 2  # Player.NV_LAYER
	for c in root.get_children():
		nv_only(c)


## Hallucinations: only visible when you're NOT protected by the goggles (render layer 3).
static func rot_only(root: Node) -> void:
	if root is VisualInstance3D and not (root is Light3D):
		(root as VisualInstance3D).layers = 4  # Player.ROT_LAYER
	for c in root.get_children():
		rot_only(c)


static func deep_fry(root: Node3D) -> void:
	for mi in all_meshes(root, []):
		mi.material_overlay = Mats.deep_fry_overlay()


static func build(id: String) -> Node3D:
	match id:
		"tung": return TungModel.build()
		"tralalero": return tralalero()
		"ballerina": return ballerina()
		"assassino": return assassino()
		"chimp": return chimp()
		"boneca": return boneca()
		"bombardiro": return Models2.bombardiro()
		"gusini": return Models2.gusini()
		"lirili": return Models2.lirili()
		"patapim": return Models2.patapim()
		"frigo": return Models2.frigo()
		"saturnita": return Models2.saturnita()
	return tung()


# ------------------------------------------------------------------ TUNG TUNG TUNG SAHUR
static func tung() -> Node3D:
	var root := Node3D.new()
	root.name = "Tung"
	var wood := Mats.wood(Color(0.62, 0.42, 0.24), false, Vector3(7, 0.3, 1))
	var dark := Mats.wood(Color(0.3, 0.18, 0.1))
	var body := pivot(root, "body", Vector3(0, 0.62, 0))
	part(body, cyl(0.3, 0.34, 2.0, 28, 8), wood, Vector3(0, 1.0, 0))
	# Bark rings / cut top
	part(body, cyl(0.29, 0.29, 0.03, 28), Mats.wood(Color(0.78, 0.6, 0.38)), Vector3(0, 2.01, 0))
	part(body, torus(0.27, 0.33, 28, 8), dark, Vector3(0, 0.15, 0), Vector3(0, 0, 0), Vector3(1, 0.4, 1))
	part(body, torus(0.26, 0.31, 28, 8), dark, Vector3(0, 1.98, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	# Face — far too high, far too wide.
	var face := pivot(body, "head", Vector3(0, 1.62, 0))
	eye(face, Vector3(-0.12, 0.05, -0.27), 0.095, Color(1, 1, 1), 0.16, 9.0)
	eye(face, Vector3(0.12, 0.05, -0.27), 0.095, Color(1, 1, 1), 0.16, 9.0)
	part(face, box(Vector3(0.14, 0.025, 0.04)), dark, Vector3(-0.12, 0.17, -0.3), Vector3(0, 0, -18))
	part(face, box(Vector3(0.14, 0.025, 0.04)), dark, Vector3(0.12, 0.17, -0.3), Vector3(0, 0, 18))
	part(face, capsule(0.035, 0.12), wood, Vector3(0, -0.06, -0.33), Vector3(-80, 0, 0))
	mouth(face, Vector3(0, -0.24, -0.31), 0.32, 0.09, 12, 0.03)
	# Arms
	var arm_l := pivot(body, "armL", Vector3(-0.34, 1.35, 0))
	limb(arm_l, Vector3.ZERO, Vector3(-0.08, -0.75, 0), 0.04, wood)
	part(arm_l, sphere(0.06), wood, Vector3(-0.08, -0.78, 0))
	var arm_r := pivot(body, "armR", Vector3(0.34, 1.35, 0))
	limb(arm_r, Vector3.ZERO, Vector3(0.08, -0.75, 0), 0.04, wood)
	part(arm_r, sphere(0.06), wood, Vector3(0.08, -0.78, 0))
	# The bat
	var bat := pivot(arm_r, "bat", Vector3(0.08, -0.78, 0))
	part(bat, cyl(0.065, 0.025, 1.05, 20), Mats.wood(Color(0.45, 0.26, 0.14)), Vector3(0, 0.45, -0.25), Vector3(-30, 0, 0))
	# Legs
	for s in [-1, 1]:
		var leg := pivot(root, "legL" if s < 0 else "legR", Vector3(0.13 * s, 0.66, 0))
		limb(leg, Vector3.ZERO, Vector3(0, -0.62, 0), 0.045, wood)
		part(leg, box(Vector3(0.12, 0.06, 0.2)), dark, Vector3(0, -0.63, -0.04))
	return finish(root, 2.75, "TUNG TUNG TUNG SAHUR")


# ------------------------------------------------------------------ TRALALERO TRALALA
static func tralalero() -> Node3D:
	var root := Node3D.new()
	root.name = "Tralalero"
	var skin := Mats.skin(Color(0.36, 0.43, 0.5), true)
	var belly := Mats.skin(Color(0.85, 0.84, 0.8), true)
	var body := pivot(root, "body", Vector3(0, 1.05, 0))
	var torso := pivot(body, "torso", Vector3.ZERO)
	torso.rotation_degrees = Vector3(-18, 0, 0)
	part(torso, sphere(0.48, 2.1, 32, 18), skin, Vector3(0, 0.55, 0))
	part(torso, sphere(0.4, 1.8, 32, 16), belly, Vector3(0, 0.45, -0.13), Vector3.ZERO, Vector3(0.95, 1, 0.8))
	# Snout and the gash of a mouth
	var head := pivot(torso, "head", Vector3(0, 1.15, -0.1))
	mouth(head, Vector3(0, 0.0, -0.36), 0.5, 0.2, 14, 0.12)
	eye(head, Vector3(-0.3, 0.22, -0.18), 0.06, Color(1, 0.95, 0.8), 0.3, 6.0)
	eye(head, Vector3(0.3, 0.22, -0.18), 0.06, Color(1, 0.95, 0.8), 0.3, 6.0)
	for s in [-1, 1]:
		for g in 3:
			part(head, box(Vector3(0.01, 0.12, 0.03)), Mats.std(Color(0.1, 0.1, 0.12)), Vector3(0.43 * s, -0.15 - g * 0.08, -0.05 + g * 0.05), Vector3(0, 0, 10 * s))
	# Fins
	part(torso, prism(Vector3(0.08, 0.7, 0.6)), skin, Vector3(0, 0.75, 0.55), Vector3(-90, 0, 0))
	part(torso, prism(Vector3(0.06, 0.6, 0.35)), skin, Vector3(-0.5, 0.35, 0.05), Vector3(0, 0, 60))
	part(torso, prism(Vector3(0.06, 0.6, 0.35)), skin, Vector3(0.5, 0.35, 0.05), Vector3(0, 0, -60))
	part(torso, prism(Vector3(0.06, 0.8, 0.5)), skin, Vector3(0, -0.45, 0.4), Vector3(150, 0, 0))
	# Three legs in blue sneakers
	var shoe := Mats.std(Color(0.08, 0.25, 0.85), 0.5)
	var sole := Mats.std(Color(0.95, 0.95, 0.95), 0.6)
	var legmat := Mats.skin(Color(0.33, 0.4, 0.47))
	var xs := [-0.25, 0.25, 0.0]
	var zs := [0.0, 0.0, 0.3]
	for i in 3:
		var leg := pivot(root, "leg%d" % i, Vector3(xs[i], 1.0, zs[i]))
		limb(leg, Vector3.ZERO, Vector3(0, -0.88, 0), 0.07, legmat, 0.06)
		part(leg, box(Vector3(0.17, 0.1, 0.34)), shoe, Vector3(0, -0.9, -0.06))
		part(leg, box(Vector3(0.18, 0.04, 0.36)), sole, Vector3(0, -0.96, -0.06))
		part(leg, box(Vector3(0.185, 0.03, 0.18)), sole, Vector3(0, -0.88, -0.04), Vector3(0, 0, 0))
	return finish(root, 2.4, "TRALALERO TRALALA")


# ------------------------------------------------------------------ BALLERINA CAPPUCCINA
static func ballerina() -> Node3D:
	var root := Node3D.new()
	root.name = "Ballerina"
	var pink := Mats.skin(Color(0.9, 0.62, 0.66))
	var tutu := Mats.surface("tutu", Color(0.95, 0.55, 0.65), 0.2, 0.2, 4.0, 0.9)
	var cup := Mats.std(Color(0.95, 0.94, 0.9), 0.15)
	cup.clearcoat_enabled = true
	var spin := pivot(root, "spin", Vector3.ZERO)
	limb(spin, Vector3(0, 0.02, 0), Vector3(0, 1.0, 0), 0.035, pink, 0.05)
	limb(spin, Vector3(0.0, 1.0, 0), Vector3(0.28, 0.62, 0.1), 0.035, pink, 0.05)
	limb(spin, Vector3(0.28, 0.62, 0.1), Vector3(0.05, 0.6, 0.0), 0.03, pink)
	part(spin, cone(0.03, 0.06), pink, Vector3(0, 0.02, 0), Vector3(180, 0, 0))
	part(spin, cyl(0.12, 0.6, 0.16, 32), tutu, Vector3(0, 1.05, 0))
	part(spin, cyl(0.15, 0.5, 0.12, 32), tutu, Vector3(0, 1.13, 0), Vector3(0, 20, 0))
	part(spin, capsule(0.11, 0.55), pink, Vector3(0, 1.38, 0))
	# Arms raised in a ring over the head
	limb(spin, Vector3(-0.12, 1.55, 0), Vector3(-0.3, 1.95, 0), 0.025, pink)
	limb(spin, Vector3(0.12, 1.55, 0), Vector3(0.3, 1.95, 0), 0.025, pink)
	limb(spin, Vector3(-0.3, 1.95, 0), Vector3(0.0, 2.25, 0), 0.022, pink)
	limb(spin, Vector3(0.3, 1.95, 0), Vector3(0.0, 2.25, 0), 0.022, pink)
	# Cappuccino head
	var head := pivot(spin, "head", Vector3(0, 1.82, 0))
	part(head, cyl(0.24, 0.17, 0.3, 32), cup, Vector3.ZERO)
	part(head, cyl(0.225, 0.225, 0.02, 32), Mats.surface("foam", Color(0.82, 0.68, 0.5), 0.3, 0.15, 6.0, 0.9), Vector3(0, 0.145, 0))
	part(head, torus(0.06, 0.1, 24, 8), cup, Vector3(0.24, 0.0, 0), Vector3(90, 0, 0))
	part(head, cyl(0.3, 0.3, 0.02, 32), cup, Vector3(0, -0.16, 0))
	# Hollow face painted on the cup
	for s in [-1, 1]:
		part(head, sphere(0.05, 0.08), Mats.eye_black(), Vector3(0.08 * s, 0.04, -0.2))
		part(head, sphere(0.008), Mats.glow(Color(1, 0.2, 0.2), 8.0), Vector3(0.08 * s, 0.04, -0.245))
	part(head, box(Vector3(0.16, 0.012, 0.02)), Mats.std(Color(0.1, 0.0, 0.0)), Vector3(0, -0.07, -0.215))
	for i in 7:
		part(head, box(Vector3(0.006, 0.04, 0.02)), Mats.std(Color(0.1, 0.0, 0.0)), Vector3(-0.07 + i * 0.023, -0.07, -0.216))
	return finish(root, 2.3, "BALLERINA CAPPUCCINA")


# ------------------------------------------------------------------ CAPPUCCINO ASSASSINO
static func assassino() -> Node3D:
	var root := Node3D.new()
	root.name = "Assassino"
	var cup := Mats.std(Color(0.9, 0.88, 0.84), 0.2)
	var cloth := Mats.surface("cloth", Color(0.05, 0.05, 0.06), 0.3, 0.3, 3.0, 0.95)
	var blade := Mats.std(Color(0.9, 0.92, 0.95), 0.08, 1.0)
	var body := pivot(root, "body", Vector3(0, 0.9, 0))
	part(body, cyl(0.36, 0.26, 0.75, 32), cup, Vector3(0, 0.3, 0))
	part(body, cyl(0.34, 0.34, 0.03, 32), Mats.std(Color(0.18, 0.09, 0.04), 0.1), Vector3(0, 0.66, 0))
	part(body, torus(0.08, 0.14, 24, 8), cup, Vector3(0.36, 0.3, 0), Vector3(90, 0, 0))
	# Hood + mask
	var head := pivot(body, "head", Vector3(0, 0.85, 0))
	part(head, sphere(0.34, 0.6), cloth, Vector3(0, 0.0, 0.04))
	part(head, cone(0.25, 0.4), cloth, Vector3(0, 0.3, 0.12), Vector3(-25, 0, 0))
	part(head, box(Vector3(0.5, 0.12, 0.1)), Mats.std(Color(0.01, 0.01, 0.01), 0.9), Vector3(0, 0.0, -0.27))
	for s in [-1, 1]:
		part(head, box(Vector3(0.1, 0.02, 0.02)), Mats.glow(Color(1, 0.05, 0.02), 14.0), Vector3(0.09 * s, 0.01, -0.33), Vector3(0, 0, 12 * s))
	# Arms holding katanas
	for s in [-1, 1]:
		var arm := pivot(body, "armL" if s < 0 else "armR", Vector3(0.36 * s, 0.45, 0))
		limb(arm, Vector3.ZERO, Vector3(0.18 * s, -0.4, -0.2), 0.045, cloth)
		var k := pivot(arm, "katana", Vector3(0.18 * s, -0.4, -0.2))
		part(k, box(Vector3(0.04, 0.22, 0.05)), Mats.std(Color(0.2, 0.05, 0.05)), Vector3(0, 0, 0))
		part(k, box(Vector3(0.14, 0.02, 0.06)), Mats.metal(Color(0.6, 0.5, 0.2)), Vector3(0, 0.11, 0))
		part(k, box(Vector3(0.015, 1.0, 0.05)), blade, Vector3(0, 0.62, 0))
		k.rotation_degrees = Vector3(-60, 0, 0)
	for s in [-1, 1]:
		var leg := pivot(root, "legL" if s < 0 else "legR", Vector3(0.14 * s, 0.92, 0))
		limb(leg, Vector3.ZERO, Vector3(0, -0.88, 0), 0.05, cloth)
		part(leg, box(Vector3(0.12, 0.07, 0.22)), cloth, Vector3(0, -0.9, -0.04))
	return finish(root, 2.1, "CAPPUCCINO ASSASSINO")


# ------------------------------------------------------------------ CHIMPANZINI BANANINI
static func chimp() -> Node3D:
	var root := Node3D.new()
	root.name = "Chimp"
	var peel := Mats.skin(Color(0.95, 0.8, 0.15))
	var fur := Mats.surface("fur", Color(0.28, 0.17, 0.1), 0.4, 0.15, 5.0, 0.95)
	var face := Mats.skin(Color(0.75, 0.55, 0.42))
	var body := pivot(root, "body", Vector3(0, 0.15, 0))
	# Banana: curved stack of capsules
	for i in 5:
		var a := (i - 2) * 0.22
		part(body, capsule(0.24 - absf(i - 2) * 0.03, 0.4), peel, Vector3(sin(a) * 0.15, 0.25 + i * 0.22, cos(a) * 0.12 - 0.1), Vector3(-a * 40.0, 0, 0))
	part(body, cyl(0.03, 0.05, 0.15), Mats.std(Color(0.25, 0.2, 0.08)), Vector3(0, 1.32, 0.0))
	# Peel flaps
	for s in [-1, 1]:
		part(body, sphere(0.18, 0.6), peel, Vector3(0.24 * s, 0.85, -0.15), Vector3(0, 0, 35 * s), Vector3(0.4, 1, 0.8))
	# Chimp peeking out
	var head := pivot(body, "head", Vector3(0, 0.72, -0.18))
	part(head, sphere(0.2), fur)
	part(head, sphere(0.15, 0.22), face, Vector3(0, -0.03, -0.1))
	for s in [-1, 1]:
		eye(head, Vector3(0.065 * s, 0.03, -0.18), 0.035, Color(1, 0.9, 0.6), 0.35, 4.0)
		part(head, sphere(0.06, 0.1), face, Vector3(0.2 * s, 0.02, 0.0))
	part(head, sphere(0.09, 0.07), face, Vector3(0, -0.09, -0.2))
	part(head, box(Vector3(0.1, 0.01, 0.02)), Mats.std(Color.BLACK), Vector3(0, -0.11, -0.28))
	for s in [-1, 1]:
		var arm := pivot(body, "armL" if s < 0 else "armR", Vector3(0.18 * s, 0.6, -0.2))
		limb(arm, Vector3.ZERO, Vector3(0.15 * s, -0.25, -0.1), 0.035, fur)
	for s in [-1, 1]:
		var leg := pivot(root, "legL" if s < 0 else "legR", Vector3(0.1 * s, 0.3, -0.05))
		limb(leg, Vector3.ZERO, Vector3(0, -0.3, 0), 0.04, fur)
	return finish(root, 1.4, "CHIMPANZINI BANANINI")


# ------------------------------------------------------------------ BONECA AMBALABU
static func boneca() -> Node3D:
	var root := Node3D.new()
	root.name = "Boneca"
	var rubber := Mats.surface("rubber", Color(0.06, 0.06, 0.06), 0.3, 0.25, 8.0, 0.75)
	var frog := Mats.skin(Color(0.25, 0.42, 0.12), true)
	var legmat := Mats.skin(Color(0.75, 0.56, 0.45))
	var tire := pivot(root, "tire", Vector3(0, 0.55, 0))
	part(tire, torus(0.28, 0.55, 40, 16), rubber, Vector3.ZERO, Vector3(0, 0, 90))
	part(tire, cyl(0.3, 0.3, 0.18, 24), Mats.metal(Color(0.3, 0.3, 0.3)), Vector3.ZERO, Vector3(0, 0, 90))
	# Head (hidden while disguised)
	var head := pivot(root, "head", Vector3(0, 1.25, -0.05))
	part(head, sphere(0.38, 0.5), frog, Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 1, 1))
	for s in [-1, 1]:
		var e := pivot(head, "bulge", Vector3(0.2 * s, 0.2, -0.1))
		part(e, sphere(0.12), frog)
		part(e, sphere(0.09), Mats.std(Color(0.85, 0.7, 0.1), 0.1), Vector3(0, 0.02, -0.05))
		part(e, box(Vector3(0.09, 0.02, 0.02)), Mats.glow(Color(0, 0, 0), 0.0), Vector3(0, 0.02, -0.14))
	mouth(head, Vector3(0, -0.08, -0.33), 0.55, 0.1, 16, 0.12)
	var legs := pivot(root, "legs", Vector3(0, 0.15, 0))
	for s in [-1, 1]:
		limb(legs, Vector3(0.12 * s, 0.05, 0), Vector3(0.18 * s, -0.12, -0.05), 0.06, legmat)
		part(legs, box(Vector3(0.13, 0.07, 0.24)), Mats.std(Color(0.9, 0.9, 0.9)), Vector3(0.18 * s, -0.14, -0.1))
	return finish(root, 1.6, "BONECA AMBALABU")
