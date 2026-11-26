extends Reference
## KEYS: a tall golden key that stands on its tip. The face is the one from the photo.
## The key is flat, like a real key: the photo cut-out on the front, polished gold on the back,
## and thin layers in between that read as the metal edge from the side.
## Faces -Z, root at the tip of the blade (the ground).
## Joints: "key" (whole body, for hops and leans), "mouth" (dark opening, closed until it screams).

const H = 1.9           # tip to top of the ring
const W = H * 374.0 / 810.0
const THICK = 0.09
const FACE_Z = -THICK * 0.5
const MOUTH = Vector2(0.519, 0.341)   # in the photo cut-out (u, v from the top)
const EYES = Vector2(0.519, 0.168)
const BOW_Y = H * (1.0 - (MOUTH.y + EYES.y) * 0.5)


## Seen from the front (-Z), the photo's left edge is at +x.
static func _uv_pos(uv: Vector2) -> Vector3:
	return Vector3((0.5 - uv.x) * W, H * (1.0 - uv.y), FACE_Z)


static func _mat(tex: String, cull_off: bool, emission := 0.35, tint := Color(1, 1, 1)) -> SpatialMaterial:
	var k = "keys_mat_%s_%s_%.2f_%s" % [tex, str(cull_off), emission, tint.to_html()]
	if Game.cache.has(k):
		return Game.cache[k]
	var m = SpatialMaterial.new()
	var t = load("res://textures/%s.png" % tex)
	m.albedo_texture = t
	m.albedo_color = tint
	m.params_use_alpha_scissor = true
	m.params_alpha_scissor_threshold = 0.5
	m.roughness = 0.6
	m.metallic = 0.0
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 1.0
	m.emission_enabled = emission > 0.0
	m.emission_texture = t
	m.emission = Color(1, 1, 1)
	m.emission_energy = emission
	m.flags_vertex_lighting = Mats.potato()
	# drawn with the photo's own colours: the scene's lights never touch it (uncanny on purpose)
	m.flags_unshaded = true
	if cull_off:
		m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	Game.cache[k] = m
	return m


## A flat quad of the key at depth z. Every layer maps the same silhouette to the same place
## (u = 0 at +x), so the photo reads right from the front and the back is its true mirror.
static func _quad(st: SurfaceTool, z: float, facing: float, _mirror := false) -> void:
	var hw = W * 0.5
	var n = Vector3(0, 0, facing)
	var pts = [Vector3(-hw, 0, z), Vector3(hw, 0, z), Vector3(hw, H, z), Vector3(-hw, H, z)]
	var uvs = [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)]
	# Godot draws clockwise faces: seen from -Z that is 0-1-2 / 0-2-3, seen from +Z the reverse
	var order = [0, 1, 2, 0, 2, 3] if facing < 0 else [0, 2, 1, 0, 3, 2]
	for i in order:
		st.add_normal(n)
		st.add_uv(uvs[i])
		st.add_vertex(pts[i])


static func _meshes() -> Array:
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	var key = "keys_mesh_%d" % q
	if Game.cache.has(key):
		return Game.cache[key]
	var front = SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(front, -THICK * 0.5, -1.0, false)
	var back = SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(back, THICK * 0.5, 1.0, true)
	var edge = SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers = [4, 8, 12][q]
	for i in range(1, layers):
		var z = -THICK * 0.5 + THICK * float(i) / layers
		_quad(edge, z, -1.0, false)
	var out = [front.commit(), back.commit(), edge.commit()]
	Game.cache[key] = out
	return out


static func build() -> Spatial:
	var root = Spatial.new()
	root.name = "Keys"
	var key = Models.pivot(root, "key", Vector3.ZERO)
	var ms = _meshes()
	var parts = [
		[ms[0], _mat("key_front", false, 0.0, Color(0.62, 0.62, 0.62))],
		[ms[1], _mat("key_back", false, 0.0, Color(0.55, 0.55, 0.55))],
		[ms[2], _mat("key_back", true, 0.0, Color(0.36, 0.29, 0.19))],
	]
	for p in parts:
		var mi = MeshInstance.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		key.add_child(mi)
	# the mouth that tears open over the photo's lips when it screams
	var mouth = Models.part(key, Models.sphere(0.05, -1, 20, 10), Mats.unshaded(Color(0.03, 0.0, 0.0)), _uv_pos(MOUTH) - Vector3(0, 0, 0.012))
	mouth.name = "mouth"
	mouth.scale = Vector3(1.9, 0.02, 0.5)
	mouth.visible = false
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	return Models.finish(root, H, "keys")


## The master key glows warmer and brighter.
static func make_glow(root: Spatial) -> void:
	for mi in _all_meshes(root):
		var m = mi.material_override
		if m is SpatialMaterial and m.albedo_texture != null:
			var g = m.duplicate()
			g.emission_energy = m.emission_energy + 0.55
			g.emission = Color(1.0, 0.85, 0.55)
			mi.material_override = g


static func _all_meshes(n: Node) -> Array:
	var out = []
	if n is MeshInstance:
		out.append(n)
	for c in n.get_children():
		out += _all_meshes(c)
	return out
