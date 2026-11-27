extends Reference
## 67 — sector 3's entity, multidimensional, it shapes worlds with its hands. Flat, like the
## image it came out of: the screaming head cut out in pure black and white, the two white hands
## beside it, the numbers above them (six over its right hand, seven over its left), all laid out
## exactly as in the image, F metres per image pixel. enemies/sixseven.gd keeps the card turned
## towards whoever looks at it.
## Faces -Z; origin on the floor. Joints: "head", "handL" (the six), "handR" (the seven).

const F = 0.0064                 # metres per pixel of the 640 x 480 reference
const CX = 320.0                 # the image column that stands over the origin
const FLOOR_PX = 449.0           # the image row that touches the floor (eyes at ~1.85 m)
const HEAD_Y = 1.53              # between the eyes and the mouth (aim here to fill a view)
const TOP = (FLOOR_PX - 65.0) * F


## Model position of an image pixel (the image's left is the model's +X: its right hand).
static func px(x: float, y: float) -> Vector3:
	return Vector3((CX - x) * F, (FLOOR_PX - y) * F, 0.0)


static func _card(tex: Texture, w_px: float, h_px: float) -> MeshInstance:
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_texture = tex
	m.albedo_color = Color(1.6, 1.6, 1.6)       # extremely hard: its white burns pure white
	m.params_use_alpha_scissor = true
	m.params_alpha_scissor_threshold = 0.5
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	var q = QuadMesh.new()
	q.size = Vector2(w_px, h_px) * F
	var mi = MeshInstance.new()
	mi.mesh = q
	mi.material_override = m
	mi.rotation_degrees = Vector3(0, 180, 0)      # the quad faces +Z; the model faces -Z
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	return mi


static func build() -> Spatial:
	var root = Spatial.new()
	root.name = "SixSeven"
	# the head (crop 195..445 x 55..400 of the image), pivoting about the face
	var head = Models.pivot(root, "head", px(320, 210))
	var face = _card(load("res://textures/67_face.png"), 250, 345)
	head.add_child(face)
	face.translation = px(320, 227.5) - px(320, 210)
	# the hands (crops 0..235 and 405..640 x 195..345), each with its number above it
	for side in [1.0, -1.0]:
		var l_side = side > 0
		var cx = 117.5 if l_side else 522.5
		var hand = Models.pivot(root, "handL" if l_side else "handR", px(cx, 270) + Vector3(0, 0, 0.02))
		hand.add_child(_card(load("res://textures/67_hand_%s.png" % ("l" if l_side else "r")), 235, 150))
		var l = Label3D.new()
		l.text = "6" if l_side else "7"
		l.font = UI.font("medium", 128)
		l.pixel_size = 0.0042
		l.modulate = Color(1.5, 1.5, 1.5)
		l.shaded = false
		l.double_sided = true
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.name = "num"
		hand.add_child(l)
		l.translation = (px(111, 224) if l_side else px(539, 220)) - px(cx, 270)
		l.rotation_degrees = Vector3(0, 180, 0)
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	return Models.finish(root, TOP, "67")
