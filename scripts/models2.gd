class_name Models2
## Second batch of code-built brainrots + props.




# ------------------------------------------------------------------ BOMBARDIRO CROCODILO
static func bombardiro() -> Node3D:
	var root := Node3D.new()
	root.name = "Bombardiro"
	var croc := Mats.skin(Color(0.22, 0.32, 0.12))
	croc.normal_scale = 2.5
	var belly := Mats.skin(Color(0.6, 0.6, 0.35))
	var steel := Mats.metal(Color(0.35, 0.38, 0.32))
	part3(root, Models.capsule(0.85, 7.0, 32), croc, Vector3(0, 0, 0.5), Vector3(90, 0, 0))
	part3(root, Models.capsule(0.6, 5.5, 24), belly, Vector3(0, -0.35, 0.6), Vector3(90, 0, 0))
	# Scutes along the back
	for i in 10:
		part3(root, Models.prism(Vector3(0.3, 0.35, 0.3)), croc, Vector3(0, 0.85, -2.0 + i * 0.55))
	# Head + snout with teeth
	var head := Models.pivot(root, "head", Vector3(0, 0.1, -3.2))
	part3(head, Models.box(Vector3(1.0, 0.45, 2.4)), croc, Vector3(0, 0.15, -1.0))
	part3(head, Models.box(Vector3(0.95, 0.3, 2.3)), croc, Vector3(0, -0.3, -0.95), Vector3(8, 0, 0), "jaw")
	for s in [-1, 1]:
		for i in 9:
			part3(head, Models.prism(Vector3(0.08, 0.18, 0.08)), Mats.teeth(), Vector3(0.47 * s, -0.12, -2.0 + i * 0.24), Vector3(180, 0, 0))
		Models.eye(head, Vector3(0.35 * s, 0.5, 0.0), 0.16, Color(1.0, 0.75, 0.1), 0.45, 10.0)
	# Wings
	part3(root, Models.box(Vector3(11.0, 0.18, 2.2)), steel, Vector3(0, 0.0, 0.2))
	part3(root, Models.box(Vector3(4.0, 0.12, 1.2)), steel, Vector3(0, 0.2, 3.8))
	part3(root, Models.box(Vector3(0.12, 1.6, 1.2)), steel, Vector3(0, 0.9, 3.9))
	for s in [-1, 1]:
		var eng := Models.pivot(root, "eng", Vector3(3.0 * s, -0.25, -0.4))
		part3(eng, Models.cyl(0.38, 0.32, 1.8, 20), steel, Vector3.ZERO, Vector3(90, 0, 0))
		var prop := Models.pivot(eng, "prop", Vector3(0, 0, -0.95))
		prop.add_to_group("prop")
		part3(prop, Models.box(Vector3(2.4, 0.18, 0.05)), Mats.std(Color(0.1, 0.1, 0.1)), Vector3.ZERO)
		part3(prop, Models.box(Vector3(0.18, 2.4, 0.05)), Mats.std(Color(0.1, 0.1, 0.1)), Vector3.ZERO)
	# Little croc legs dangling under the fuselage
	for x in [-1, 1]:
		for z in [-1.5, 2.0]:
			Models.limb(root, Vector3(0.6 * x, -0.6, z), Vector3(0.75 * x, -1.4, z - 0.3), 0.12, croc)
	return Models.finish(root, 3.0, "BOMBARDIRO CROCODILO")


static func part3(p: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, pname := "") -> MeshInstance3D:
	return Models.part(p, mesh, mat, pos, rot, Vector3.ONE, pname)


# ------------------------------------------------------------------ BOMBOMBINI GUSINI
static func gusini() -> Node3D:
	var root := Node3D.new()
	root.name = "Gusini"
	var feather := Mats.surface("feather", Color(0.92, 0.92, 0.9), 0.15, 0.2, 3.0, 0.8)
	var beak := Mats.skin(Color(0.95, 0.45, 0.05))
	var steel := Mats.metal(Color(0.5, 0.52, 0.55))
	part3(root, Models.capsule(0.7, 4.5, 28), feather, Vector3(0, 0, 0.6), Vector3(90, 0, 0))
	# Long curved neck
	var pts := [Vector3(0, 0.3, -1.5), Vector3(0, 0.9, -2.0), Vector3(0, 1.3, -2.7), Vector3(0, 1.3, -3.4)]
	for i in pts.size() - 1:
		Models.limb(root, pts[i], pts[i + 1], 0.28, feather, 0.3)
	var head := Models.pivot(root, "head", Vector3(0, 1.35, -3.6))
	part3(head, Models.sphere(0.4, 0.6), feather)
	part3(head, Models.cone(0.18, 0.9), beak, Vector3(0, -0.05, -0.65), Vector3(-90, 0, 0))
	for i in 8:
		part3(head, Models.prism(Vector3(0.04, 0.08, 0.04)), Mats.teeth(), Vector3(0.12 - i * 0.034, -0.12, -0.45 - i * 0.03), Vector3(180, 0, 0))
	for s in [-1, 1]:
		Models.eye(head, Vector3(0.28 * s, 0.1, -0.1), 0.08, Color(1, 0.3, 0.1), 0.4, 10.0)
	# Swept jet wings
	for s in [-1, 1]:
		part3(root, Models.box(Vector3(4.8, 0.14, 1.6)), steel, Vector3(2.4 * s, 0, 1.0), Vector3(0, -25 * s, 0))
		var eng := Models.pivot(root, "eng", Vector3(1.8 * s, -0.35, 1.0))
		part3(eng, Models.cyl(0.32, 0.38, 1.6, 20), steel, Vector3.ZERO, Vector3(90, 0, 0))
		part3(eng, Models.cyl(0.28, 0.28, 0.05, 20), Mats.glow(Color(1.0, 0.45, 0.1), 8.0), Vector3(0, 0, 0.82), Vector3(90, 0, 0))
	part3(root, Models.box(Vector3(0.12, 1.4, 1.0)), steel, Vector3(0, 0.8, 2.8))
	return Models.finish(root, 2.5, "BOMBOMBINI GUSINI")


# ------------------------------------------------------------------ LIRILI LARILA
static func lirili() -> Node3D:
	var root := Node3D.new()
	root.name = "Lirili"
	var cactus := Mats.skin(Color(0.2, 0.42, 0.2))
	cactus.normal_scale = 2.0
	var spike := Mats.std(Color(0.9, 0.88, 0.75), 0.4)
	var hide := Mats.skin(Color(0.42, 0.4, 0.4))
	var leather := Mats.surface("leather", Color(0.4, 0.25, 0.12), 0.3, 0.1, 3.0, 0.7)
	var body := Models.pivot(root, "body", Vector3(0, 0.35, 0))
	part3(body, Models.capsule(0.55, 2.0, 32), cactus, Vector3(0, 1.0, 0))
	# Ribs + spikes
	for r in 8:
		var a := r * TAU / 8.0
		for h in 6:
			var p := Vector3(cos(a) * 0.56, 0.35 + h * 0.27, sin(a) * 0.56)
			var n := Vector3(cos(a), 0.15, sin(a)).normalized()
			Models.limb(body, p, p + n * 0.15, 0.02, spike, 0.0)
	# Cactus arms
	for s in [-1, 1]:
		var arm := Models.pivot(body, "armL" if s < 0 else "armR", Vector3(0.55 * s, 1.2, 0))
		Models.limb(arm, Vector3.ZERO, Vector3(0.45 * s, 0.0, 0), 0.16, cactus)
		Models.limb(arm, Vector3(0.45 * s, 0, 0), Vector3(0.45 * s, 0.6, 0), 0.16, cactus)
		part3(arm, Models.sphere(0.16), cactus, Vector3(0.45 * s, 0.6, 0))
	# Pocket watch in the right hand
	var clock := Models.pivot(body, "clock", Vector3(0.95, 1.45, -0.15))
	part3(clock, Models.cyl(0.26, 0.26, 0.06, 32), Mats.metal(Color(0.8, 0.62, 0.2), 0.2), Vector3.ZERO, Vector3(90, 0, 0))
	part3(clock, Models.cyl(0.22, 0.22, 0.02, 32), Mats.glow(Color(0.95, 0.92, 0.8), 1.5), Vector3(0, 0, -0.035), Vector3(90, 0, 0))
	var hand := Models.pivot(clock, "hand", Vector3(0, 0, -0.05))
	part3(hand, Models.box(Vector3(0.015, 0.18, 0.01)), Mats.std(Color.BLACK), Vector3(0, 0.08, 0))
	# Elephant head
	var head := Models.pivot(body, "head", Vector3(0, 2.3, 0))
	part3(head, Models.sphere(0.5, 0.85), hide)
	for s in [-1, 1]:
		part3(head, Models.sphere(0.45, 0.9), hide, Vector3(0.55 * s, 0.0, 0.1), Vector3(0, 20 * s, 0), "ear")
		Models.eye(head, Vector3(0.2 * s, 0.1, -0.4), 0.05, Color(1, 0.1, 0.1), 0.4, 10.0)
		part3(head, Models.cone(0.06, 0.5), Mats.teeth(), Vector3(0.18 * s, -0.3, -0.45), Vector3(-120, 0, 0))
	var trunk := Models.pivot(head, "trunk", Vector3(0, -0.05, -0.42))
	var tp := [Vector3.ZERO, Vector3(0, -0.3, -0.12), Vector3(0, -0.65, -0.12), Vector3(0, -0.95, -0.0), Vector3(0, -1.1, -0.15)]
	for i in tp.size() - 1:
		Models.limb(trunk, tp[i], tp[i + 1], 0.12 - i * 0.022, hide, 0.13 - i * 0.022)
	# Sandals
	for s in [-1, 1]:
		var leg := Models.pivot(root, "legL" if s < 0 else "legR", Vector3(0.25 * s, 0.4, 0))
		Models.limb(leg, Vector3.ZERO, Vector3(0, -0.35, 0), 0.13, hide)
		part3(leg, Models.box(Vector3(0.3, 0.05, 0.45)), leather, Vector3(0, -0.38, -0.06))
		part3(leg, Models.box(Vector3(0.32, 0.04, 0.05)), leather, Vector3(0, -0.3, -0.12))
	return Models.finish(root, 3.4, "LIRILI LARILA")


# ------------------------------------------------------------------ BRR BRR PATAPIM
static func patapim() -> Node3D:
	var root := Node3D.new()
	root.name = "Patapim"
	var bark := Mats.wood(Color(0.32, 0.22, 0.14), false, Vector3(8, 0.3, 1))
	var leaf := Mats.surface("leaf", Color(0.12, 0.25, 0.08), 0.4, 0.3, 4.0, 0.9)
	var flesh := Mats.skin(Color(0.78, 0.55, 0.45), true)
	var body := Models.pivot(root, "body", Vector3(0, 0.9, 0))
	part3(body, Models.cyl(0.5, 0.75, 2.4, 28, 6), bark, Vector3(0, 1.1, 0))
	for i in 5:
		var a := i * TAU / 5.0
		Models.limb(body, Vector3(cos(a) * 0.5, 0.2, sin(a) * 0.5), Vector3(cos(a) * 1.0, -0.6, sin(a) * 1.0), 0.12, bark, 0.06)
	# Face
	var head := Models.pivot(body, "head", Vector3(0, 1.9, 0))
	part3(head, Models.sphere(0.48, 0.8), flesh, Vector3(0, 0, -0.2), Vector3.ZERO, "")
	part3(head, Models.sphere(0.24, 0.6), flesh, Vector3(0, -0.15, -0.62), Vector3(20, 0, 0), "nose")
	for s in [-1, 1]:
		Models.eye(head, Vector3(0.2 * s, 0.15, -0.58), 0.08, Color(1, 1, 0.8), 0.18, 7.0)
		part3(head, Models.box(Vector3(0.22, 0.04, 0.06)), bark, Vector3(0.2 * s, 0.28, -0.6), Vector3(0, 0, -20 * s))
	Models.mouth(head, Vector3(0, -0.42, -0.5), 0.4, 0.1, 10, 0.05)
	# Branch crown with leaves
	for i in 6:
		var a := i * TAU / 6.0 + 0.3
		var tip := Vector3(cos(a) * 1.0, 3.3 + sin(i * 1.3) * 0.3, sin(a) * 1.0)
		Models.limb(body, Vector3(0, 2.2, 0), tip, 0.08, bark, 0.04)
		part3(body, Models.sphere(0.45, 0.6), leaf, tip)
	# Arms
	for s in [-1, 1]:
		var arm := Models.pivot(body, "armL" if s < 0 else "armR", Vector3(0.6 * s, 1.5, 0))
		Models.limb(arm, Vector3.ZERO, Vector3(0.6 * s, -0.8, -0.2), 0.11, bark)
		Models.limb(arm, Vector3(0.6 * s, -0.8, -0.2), Vector3(0.7 * s, -1.6, -0.3), 0.09, bark)
	# Giant feet
	for s in [-1, 1]:
		var foot := Models.pivot(root, "footL" if s < 0 else "footR", Vector3(0.55 * s, 0.0, 0))
		Models.limb(foot, Vector3(0, 0.9, 0), Vector3(0, 0.25, 0), 0.18, flesh)
		var sole := part3(foot, Models.sphere(0.5, 0.45), flesh, Vector3(0, 0.18, -0.35), Vector3.ZERO)
		sole.scale = Vector3(1.1, 1, 1.9)
		for t in 4:
			part3(foot, Models.sphere(0.1), flesh, Vector3(-0.27 + t * 0.18, 0.1, -1.25))
	return Models.finish(root, 4.0, "BRR BRR PATAPIM")


# ------------------------------------------------------------------ FRIGO CAMELO
static func frigo() -> Node3D:
	var root := Node3D.new()
	root.name = "Frigo"
	var enamel := Mats.std(Color(0.88, 0.9, 0.92), 0.2)
	var fur := Mats.surface("camel", Color(0.72, 0.55, 0.32), 0.3, 0.15, 4.0, 0.95)
	var boot := Mats.surface("boot", Color(0.3, 0.18, 0.08), 0.3, 0.1, 2.0, 0.6)
	var body := Models.pivot(root, "body", Vector3(0, 0.55, 0))
	part3(body, Models.box(Vector3(0.95, 1.9, 0.8)), enamel, Vector3(0, 0.95, 0))
	part3(body, Models.box(Vector3(0.9, 1.8, 0.02)), Mats.glow(Color(0.7, 0.9, 1.0), 2.0), Vector3(0, 0.95, -0.4))
	var door := Models.pivot(body, "door", Vector3(-0.475, 0.95, -0.41))
	part3(door, Models.box(Vector3(0.95, 1.88, 0.06)), enamel, Vector3(0.47, 0, -0.03))
	part3(door, Models.box(Vector3(0.04, 0.5, 0.05)), Mats.metal(Color(0.7, 0.7, 0.7)), Vector3(0.85, 0.2, -0.1))
	door.rotation_degrees = Vector3(0, -110, 0)
	for i in 3:
		part3(body, Models.box(Vector3(0.85, 0.02, 0.7)), Mats.std(Color(0.8, 0.9, 1.0), 0.1), Vector3(0, 0.4 + i * 0.5, 0))
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.85, 1.0)
	light.light_energy = 3.0
	light.omni_range = 5.0
	light.shadow_enabled = true
	body.add_child(light)
	light.position = Vector3(0, 1.0, -0.8)
	# Camel neck & head out of the top
	Models.limb(body, Vector3(0, 1.8, 0.1), Vector3(0, 2.5, -0.1), 0.16, fur)
	Models.limb(body, Vector3(0, 2.5, -0.1), Vector3(0, 2.8, -0.45), 0.14, fur)
	var head := Models.pivot(body, "head", Vector3(0, 2.85, -0.55))
	part3(head, Models.capsule(0.17, 0.6), fur, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
	part3(head, Models.sphere(0.15, 0.22), Mats.skin(Color(0.6, 0.45, 0.3)), Vector3(0, -0.05, -0.38))
	for s in [-1, 1]:
		Models.eye(head, Vector3(0.14 * s, 0.08, -0.05), 0.045, Color(0.7, 0.9, 1.0), 0.3, 4.0)
		part3(head, Models.box(Vector3(0.1, 0.03, 0.06)), fur, Vector3(0.14 * s, 0.12, -0.07), Vector3(0, 0, 15 * s))
		part3(head, Models.cone(0.05, 0.14), fur, Vector3(0.12 * s, 0.2, 0.12))
	# Hump on top of the fridge
	part3(body, Models.sphere(0.35, 0.4), fur, Vector3(0, 1.95, 0.15))
	for s in [-1, 1]:
		var leg := Models.pivot(root, "legL" if s < 0 else "legR", Vector3(0.3 * s, 0.55, 0))
		Models.limb(leg, Vector3.ZERO, Vector3(0, -0.4, 0), 0.06, fur)
		part3(leg, Models.cyl(0.1, 0.11, 0.28, 16), boot, Vector3(0, -0.35, 0))
		part3(leg, Models.box(Vector3(0.2, 0.08, 0.32)), boot, Vector3(0, -0.5, -0.06))
	return Models.finish(root, 3.3, "FRIGO CAMELO")


# ------------------------------------------------------------------ LA VACA SATURNO SATURNITA
static func saturnita() -> Node3D:
	var root := Node3D.new()
	root.name = "Saturnita"
	var hide := Mats.spots(Color(0.92, 0.9, 0.86), Color(0.05, 0.04, 0.04))
	var pink := Mats.skin(Color(0.9, 0.55, 0.58), true)
	var R := 7.0
	part3(root, Models.sphere(R, -1, 64, 32), hide)
	var face := Models.pivot(root, "face", Vector3.ZERO)
	part3(face, Models.sphere(2.2, 2.6), pink, Vector3(0, -1.6, -R + 0.3))
	for s in [-1, 1]:
		part3(face, Models.sphere(0.4), Mats.std(Color(0.2, 0.05, 0.06), 0.3), Vector3(0.8 * s, -1.6, -R - 0.9))
		Models.eye(face, Vector3(2.0 * s, 1.6, -R + 0.8), 1.0, Color(1, 0.9, 0.7), 0.18, 12.0)
		part3(face, Models.cone(0.6, 3.0), Mats.teeth(), Vector3(4.2 * s, 5.6, -2.0), Vector3(-10, 0, -40 * s))
		part3(face, Models.sphere(1.6, 0.9), hide, Vector3(5.8 * s, 2.6, -2.5), Vector3(0, 0, 30 * s), "ear")
	for x in [-1, 1]:
		for z in [-1, 1]:
			var a := Vector3(2.8 * x, -R * 0.85, 2.8 * z)
			Models.limb(root, a, a + Vector3(0.3 * x, -3.0, 0.3 * z), 0.45, hide)
			part3(root, Models.cyl(0.55, 0.6, 0.6, 16), Mats.std(Color(0.1, 0.08, 0.06)), a + Vector3(0.3 * x, -3.2, 0.3 * z))
	return Models.finish(root, 16.0, "LA VACA SATURNO SATURNITA")


# ------------------------------------------------------------------ props
static func battery() -> Node3D:
	var root := Node3D.new()
	part3(root, Models.cyl(0.05, 0.05, 0.2, 16), Mats.std(Color(0.1, 0.1, 0.1), 0.4), Vector3(0, 0.1, 0))
	part3(root, Models.cyl(0.052, 0.052, 0.08, 16), Mats.glow(Color(0.2, 1.0, 0.3), 2.0), Vector3(0, 0.14, 0))
	part3(root, Models.cyl(0.02, 0.02, 0.03, 8), Mats.metal(Color(0.8, 0.8, 0.8)), Vector3(0, 0.215, 0))
	return root


static func note() -> Node3D:
	var root := Node3D.new()
	var paper := Mats.surface("paper", Color(0.85, 0.8, 0.65), 0.2, 0.1, 1.0, 1.0)
	part3(root, Models.box(Vector3(0.22, 0.005, 0.3)), paper, Vector3(0, 0.01, 0), Vector3(0, 17, 0))
	for i in 5:
		part3(root, Models.box(Vector3(0.16, 0.002, 0.008)), Mats.std(Color(0.25, 0.05, 0.05)), Vector3(0, 0.014, -0.1 + i * 0.045), Vector3(0, 17, 0))
	return root


static func lantern(lit: bool) -> Node3D:
	var root := Node3D.new()
	var iron := Mats.metal(Color(0.15, 0.15, 0.13), 0.6)
	Models.limb(root, Vector3(0, 0, 0), Vector3(0, 1.6, 0), 0.05, Mats.wood())
	part3(root, Models.box(Vector3(0.3, 0.4, 0.3)), iron, Vector3(0, 1.8, 0))
	part3(root, Models.box(Vector3(0.24, 0.32, 0.24)), Mats.glow(Color(1.0, 0.6, 0.2), 4.0) if lit else Mats.std(Color(0.1, 0.1, 0.08), 0.2), Vector3(0, 1.8, 0), Vector3.ZERO, "glass")
	return root


static func crown() -> Node3D:
	var root := Node3D.new()
	var gold := Mats.metal(Color(1.0, 0.75, 0.2), 0.15)
	part3(root, Models.cyl(0.25, 0.25, 0.15, 32), gold)
	for i in 6:
		var a := i * TAU / 6.0
		part3(root, Models.cone(0.06, 0.2), gold, Vector3(cos(a) * 0.23, 0.17, sin(a) * 0.23))
		part3(root, Models.sphere(0.03), Mats.glow(Color(1, 0.1, 0.2), 4.0), Vector3(cos(a) * 0.25, 0.05, sin(a) * 0.25))
	return root


static func tire() -> Node3D:
	var root := Node3D.new()
	var rubber := Mats.surface("rubber", Color(0.06, 0.06, 0.06), 0.3, 0.25, 8.0, 0.75)
	part3(root, Models.torus(0.28, 0.55, 40, 16), rubber, Vector3(0, 0.55, 0), Vector3(0, 0, 90))
	part3(root, Models.cyl(0.3, 0.3, 0.18, 24), Mats.metal(Color(0.3, 0.3, 0.3)), Vector3(0, 0.55, 0), Vector3(0, 0, 90))
	return root


static func melting_clock() -> Node3D:
	var root := Node3D.new()
	var gold := Mats.metal(Color(0.8, 0.6, 0.2), 0.3)
	var c := part3(root, Models.cyl(0.6, 0.6, 0.08, 32), gold, Vector3(0, 0.05, 0))
	c.scale = Vector3(1, 1, 1.6)
	var face := part3(root, Models.cyl(0.52, 0.52, 0.02, 32), Mats.std(Color(0.9, 0.88, 0.8), 0.5), Vector3(0, 0.1, 0))
	face.scale = Vector3(1, 1, 1.6)
	part3(root, Models.box(Vector3(0.03, 0.01, 0.5)), Mats.std(Color.BLACK), Vector3(0, 0.12, -0.2), Vector3(0, 40, 0))
	return root


# ------------------------------------------------------------------ uncanny figures
## Faceless grey humanoid stuck in a T-pose. It should not be here.
static func tposer(mat: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = "TPoser"
	var m := mat if mat else Mats.std(Color(0.72, 0.72, 0.7), 0.9)
	Models.limb(root, Vector3(-0.12, 0, 0), Vector3(-0.12, 0.95, 0), 0.08, m, 0.1)
	Models.limb(root, Vector3(0.12, 0, 0), Vector3(0.12, 0.95, 0), 0.08, m, 0.1)
	part3(root, Models.capsule(0.22, 0.75), m, Vector3(0, 1.3, 0))
	Models.limb(root, Vector3(-0.2, 1.55, 0), Vector3(-0.95, 1.55, 0), 0.06, m)
	Models.limb(root, Vector3(0.2, 1.55, 0), Vector3(0.95, 1.55, 0), 0.06, m)
	part3(root, Models.cyl(0.06, 0.07, 0.12, 12), m, Vector3(0, 1.72, 0))
	part3(root, Models.sphere(0.13, 0.3), m, Vector3(0, 1.88, 0))
	return Models.finish(root, 2.0, "???")


# ------------------------------------------------------------------ physics props
static func prop_mesh(kind: String) -> Array:
	## Returns [root Node3D, Shape3D, mass]
	var root := Node3D.new()
	match kind:
		"crate":
			var w := Mats.surf("planks", Color(0.6, 0.45, 0.28), Color(0.4, 0.28, 0.15), {"grime": 0.3})
			part3(root, Models.box(Vector3(0.9, 0.9, 0.9)), w)
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.9, 0.9, 0.9)
			return [root, sh, 25.0]
		"barrel":
			var col: Color = [Color(0.55, 0.08, 0.05), Color(0.1, 0.2, 0.45), Color(0.15, 0.3, 0.1)][randi() % 3]
			part3(root, Models.cyl(0.32, 0.32, 0.95, 24), Mats.surf("metal", col, col.darkened(0.5), {"roughness": 0.45, "metallic": 0.6}))
			for y in [-0.3, 0.3]:
				part3(root, Models.torus(0.31, 0.345, 24, 6), Mats.metal(Color(0.3, 0.3, 0.3)), Vector3(0, y, 0))
			var sh := CylinderShape3D.new()
			sh.radius = 0.32
			sh.height = 0.95
			return [root, sh, 30.0]
		"chair":
			var w := Mats.surf("planks", Color(0.45, 0.3, 0.18), Color(0.3, 0.2, 0.1), {"grime": 0.2})
			part3(root, Models.box(Vector3(0.45, 0.05, 0.45)), w, Vector3(0, 0.0, 0))
			part3(root, Models.box(Vector3(0.45, 0.5, 0.05)), w, Vector3(0, 0.27, 0.2))
			for x in [-0.19, 0.19]:
				for z in [-0.19, 0.19]:
					part3(root, Models.box(Vector3(0.04, 0.45, 0.04)), w, Vector3(x, -0.24, z))
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.45, 0.95, 0.45)
			return [root, sh, 6.0]
		"cone":
			part3(root, Models.cone(0.2, 0.6, 16), Mats.std(Color(1.0, 0.35, 0.05), 0.6), Vector3(0, 0.02, 0))
			part3(root, Models.box(Vector3(0.45, 0.04, 0.45)), Mats.std(Color(0.1, 0.1, 0.1)), Vector3(0, -0.3, 0))
			part3(root, Models.cyl(0.11, 0.135, 0.1, 16), Mats.std(Color(0.95, 0.95, 0.95), 0.4), Vector3(0, 0.05, 0))
			var sh := CylinderShape3D.new()
			sh.radius = 0.2
			sh.height = 0.62
			return [root, sh, 2.0]
		"tv":
			part3(root, Models.box(Vector3(0.7, 0.55, 0.5)), Mats.std(Color(0.12, 0.1, 0.09), 0.5))
			part3(root, Models.box(Vector3(0.56, 0.42, 0.02)), Mats.tv_static(), Vector3(0, 0.02, -0.25))
			var l := OmniLight3D.new()
			l.light_color = Color(0.7, 0.8, 1.0)
			l.light_energy = 0.8
			l.omni_range = 3.5
			root.add_child(l)
			l.position = Vector3(0, 0, -0.6)
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.7, 0.55, 0.5)
			return [root, sh, 18.0]
	return prop_mesh("crate")
