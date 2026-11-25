class_name Models2
## Small props and the faceless T-poser. (Godot 3)


static func note() -> Spatial:
	var root = Spatial.new()
	var paper = Mats.std(Color(0.85, 0.8, 0.65), 1.0)
	Models.part(root, Models.box(Vector3(0.22, 0.005, 0.3)), paper, Vector3(0, 0.01, 0), Vector3(0, 17, 0))
	var ink = Mats.std(Color(0.25, 0.05, 0.05))
	for i in 5:
		Models.part(root, Models.box(Vector3(0.16, 0.002, 0.008)), ink, Vector3(0, 0.014, -0.1 + i * 0.045), Vector3(0, 17, 0))
	return root


## Faceless grey humanoid stuck in a T-pose. It should not be here.
static func tposer(mat: Material = null) -> Spatial:
	var root = Spatial.new()
	root.name = "TPoser"
	var m: Material = mat if mat else Mats.std(Color(0.72, 0.72, 0.7), 0.9)
	Models.limb(root, Vector3(-0.12, 0, 0), Vector3(-0.12, 0.95, 0), 0.08, m, 0.1)
	Models.limb(root, Vector3(0.12, 0, 0), Vector3(0.12, 0.95, 0), 0.08, m, 0.1)
	var torso = Models.capsule_y(root, 0.22, 1.19, m)
	torso.translation = Vector3(0, 1.3, 0)
	Models.limb(root, Vector3(-0.2, 1.55, 0), Vector3(-0.95, 1.55, 0), 0.06, m)
	Models.limb(root, Vector3(0.2, 1.55, 0), Vector3(0.95, 1.55, 0), 0.06, m)
	Models.part(root, Models.cyl(0.06, 0.07, 0.12, 12), m, Vector3(0, 1.72, 0))
	Models.part(root, Models.sphere(0.13, 0.3), m, Vector3(0, 1.88, 0))
	return Models.finish(root, 2.0, "???")
