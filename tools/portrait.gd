extends SceneTree
## Dev tool: studio portrait of Tung to compare with the reference.
var n := 0
var out := "/tmp/tung.png"
var yaw := 0.0
var dist := 2.2
var h := 2.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"out": out = kv[1]
			"yaw": yaw = float(kv[1])
			"dist": dist = float(kv[1])
			"h": h = float(kv[1])
	var root3 := Node3D.new()
	root.add_child(root3)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.02, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.8, 0.7)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	we.environment = env
	root3.add_child(we)
	var t := TungModel.build()
	root3.add_child(t)
	t.rotation.y = yaw
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.shadow_enabled = true
	root3.add_child(key)
	key.rotation_degrees = Vector3(-35, -25, 0)
	var fill := OmniLight3D.new()
	fill.light_energy = 1.2
	fill.omni_range = 6
	root3.add_child(fill)
	fill.position = Vector3(-1.2, 2.2, -1.6)
	var cam := Camera3D.new()
	cam.fov = 35
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(sin(yaw) * 0.0, h, -dist)).looking_at(Vector3(0, h - 0.12, 0), Vector3.UP)
	cam.current = true

func _process(_d: float) -> bool:
	n += 1
	if n == 30:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
