extends Reference
## hush field operative (containment division). Built in code, like everything in sahur.
## Charcoal containment coverall, olive load vest, backpack + air tank, helmet, respirator,
## and the nv-7: four goggle tubes whose lenses glow in the operative's colour.
## Faces -Z, feet at y = 0. Joints (named nodes): hips, torso, head, armL/armR, elbowL/elbowR,
## legL/legR, kneeL/kneeR.

const HIP_Y = 0.95


static func build(color: Color) -> Spatial:
	var suit = Mats.std(Color(0.22, 0.225, 0.23), 0.85)
	var suit2 = Mats.std(Color(0.15, 0.155, 0.16), 0.9)
	var vest = Mats.std(Color(0.25, 0.27, 0.2), 0.9)
	var strap = Mats.std(Color(0.08, 0.08, 0.08), 0.7)
	var helmet = Mats.std(Color(0.2, 0.21, 0.2), 0.55, 0.1)
	var metal = Mats.std(Color(0.12, 0.12, 0.13), 0.35, 0.6)
	var rubber = Mats.std(Color(0.05, 0.05, 0.055), 0.6)
	var stripe = Mats.std(Color(0.95, 0.72, 0.2), 0.4)
	var patch = Mats.std(Color(0.9, 0.9, 0.88), 0.7)
	var lens = Mats.glow(color, 2.6)

	var root = Spatial.new()
	root.name = "operative"
	# --- legs
	for side in [-1.0, 1.0]:
		var sname = "L" if side < 0 else "R"
		var leg = Models.pivot(root, "leg" + sname, Vector3(0.1 * side, HIP_Y, 0))
		Models.capsule_y(leg, 0.078, 0.5, suit).translation = Vector3(0, -0.22, 0)
		Models.part(leg, Models.box(Vector3(0.07, 0.12, 0.05)), vest, Vector3(0.07 * side, -0.24, 0.0))  # thigh pocket
		var knee = Models.pivot(leg, "knee" + sname, Vector3(0, -0.45, 0))
		Models.part(knee, Models.sphere(0.068, -1, 12, 6), suit2, Vector3(0, 0, -0.02))      # knee pad
		Models.capsule_y(knee, 0.066, 0.46, suit).translation = Vector3(0, -0.2, 0)
		Models.part(knee, Models.cyl(0.071, 0.071, 0.035, 12, 1), stripe, Vector3(0, -0.12, 0))
		Models.part(knee, Models.box(Vector3(0.12, 0.1, 0.27)), rubber, Vector3(0, -0.44, -0.045))   # boot
		Models.part(knee, Models.box(Vector3(0.125, 0.025, 0.28)), strap, Vector3(0, -0.49, -0.045))
	# --- body
	var hips = Models.pivot(root, "hips", Vector3(0, HIP_Y, 0))
	Models.part(hips, Models.box(Vector3(0.36, 0.14, 0.22)), suit2, Vector3(0, 0.0, 0))
	Models.part(hips, Models.box(Vector3(0.38, 0.05, 0.24)), strap, Vector3(0, 0.06, 0))            # belt
	var torso = Models.pivot(hips, "torso", Vector3(0, 0.04, 0))
	var chest = Models.capsule_y(torso, 0.19, 0.64, suit)
	chest.translation = Vector3(0, 0.3, 0)
	chest.scale = Vector3(1.12, 1.0, 0.78)
	Models.part(torso, Models.box(Vector3(0.44, 0.4, 0.3)), vest, Vector3(0, 0.36, -0.005))
	for i in 3:
		Models.part(torso, Models.box(Vector3(0.1, 0.12, 0.06)), vest, Vector3(-0.13 + i * 0.13, 0.26, -0.17))
	Models.part(torso, Models.box(Vector3(0.3, 0.04, 0.02)), stripe, Vector3(0, 0.47, -0.162))
	Models.part(torso, Models.box(Vector3(0.36, 0.44, 0.18)), vest, Vector3(0, 0.36, 0.23))          # backpack
	Models.part(torso, Models.cyl(0.075, 0.075, 0.5, 14, 1), metal, Vector3(0, 0.38, 0.35))           # air tank
	Models.part(torso, Models.sphere(0.075, -1, 12, 6), metal, Vector3(0, 0.63, 0.35))
	Models.part(torso, Models.box(Vector3(0.05, 0.5, 0.04)), strap, Vector3(-0.15, 0.42, -0.16))
	Models.part(torso, Models.box(Vector3(0.05, 0.5, 0.04)), strap, Vector3(0.15, 0.42, -0.16))
	# --- head: balaclava, helmet, respirator, nv-7
	var head = Models.pivot(torso, "head", Vector3(0, 0.66, 0))
	Models.part(head, Models.cyl(0.065, 0.075, 0.1, 12, 1), suit2, Vector3(0, 0.0, 0))               # neck
	Models.part(head, Models.sphere(0.115, 0.26, 16, 8), suit2, Vector3(0, 0.14, 0))
	var hm = Models.part(head, Models.sphere(0.138, 0.2, 18, 8), helmet, Vector3(0, 0.205, 0.012))
	hm.scale = Vector3(1.0, 1.0, 1.08)
	Models.part(head, Models.box(Vector3(0.3, 0.02, 0.03)), strap, Vector3(0, 0.15, -0.115))          # chin strap line
	Models.part(head, Models.sphere(0.072, -1, 14, 7), rubber, Vector3(0, 0.085, -0.1))              # respirator
	for s in [-1.0, 1.0]:
		var f = Models.part(head, Models.cyl(0.035, 0.035, 0.05, 12, 1), metal, Vector3(0.075 * s, 0.07, -0.12))
		f.rotation_degrees = Vector3(90, 0, -35.0 * s)
	Models.part(head, Models.box(Vector3(0.08, 0.05, 0.05)), metal, Vector3(0, 0.29, -0.13))          # nvg mount
	var tubes = Models.pivot(head, "nvg", Vector3(0, 0.205, -0.15))
	Models.part(tubes, Models.box(Vector3(0.19, 0.05, 0.05)), metal, Vector3(0, 0, 0.01))
	var xs = [-0.072, -0.026, 0.026, 0.072]
	for i in 4:
		var t = Models.part(tubes, Models.cyl(0.021, 0.024, 0.085, 12, 1), metal, Vector3(xs[i], 0, -0.03))
		t.rotation_degrees = Vector3(90, (14.0 if i == 0 else (-14.0 if i == 3 else 0.0)), 0)
		var l = Models.part(tubes, Models.cyl(0.018, 0.018, 0.006, 12, 1), lens, Vector3(xs[i] * 1.06, 0, -0.075))
		l.rotation_degrees = Vector3(90, t.rotation_degrees.y, 0)
	# --- arms
	for side in [-1.0, 1.0]:
		var sname = "L" if side < 0 else "R"
		var arm = Models.pivot(torso, "arm" + sname, Vector3(0.245 * side, 0.55, 0))
		Models.part(arm, Models.sphere(0.075, -1, 12, 6), vest, Vector3(0, 0.0, 0))                 # shoulder
		Models.capsule_y(arm, 0.058, 0.34, suit).translation = Vector3(0, -0.15, 0)
		Models.part(arm, Models.cyl(0.061, 0.061, 0.03, 12, 1), stripe, Vector3(0, -0.07, 0))
		if side < 0:
			var pt = Models.part(arm, Models.box(Vector3(0.01, 0.06, 0.06)), patch, Vector3(-0.058, -0.05, 0))
			pt.rotation_degrees.y = 0
		var elbow = Models.pivot(arm, "elbow" + sname, Vector3(0, -0.31, 0))
		Models.capsule_y(elbow, 0.052, 0.3, suit).translation = Vector3(0, -0.13, 0)
		Models.part(elbow, Models.sphere(0.05, -1, 10, 6), rubber, Vector3(0, -0.3, -0.01))          # glove
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	return root
