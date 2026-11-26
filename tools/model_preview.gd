extends SceneTree
## Dev tool: render a brainrot model from a few angles.
##   godot3 --path . -s tools/model_preview.gd model=keys out=/tmp/keys
var n = 0
var out = "/tmp/model"
var model_id = "keys"
var cam: Camera
var pivot: Spatial
var angles = [0.0, 35.0, 90.0, 180.0]
var arms = -99.0


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("model="):
			model_id = a.substr(6)
		elif a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("arms="):
			arms = float(a.substr(5))


func _setup() -> void:
	var w = Spatial.new()
	root.add_child(w)
	var we = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.11, 0.09)
	env.ambient_light_color = Color(0.9, 0.85, 0.7)
	env.ambient_light_energy = 0.35
	we.environment = env
	w.add_child(we)
	pivot = Spatial.new()
	w.add_child(pivot)
	var m = root.get_node("Game")  # autoloads are up
	var model = load("res://scripts/brainrots.gd").build(model_id)
	pivot.add_child(model)
	if arms > -90.0:
		for nm in ["armL", "armR"]:
			var j = model.find_node(nm, true, false)
			if j:
				j.rotation.x = arms
	var top = SpotLight.new()
	top.light_energy = 3.0
	top.spot_range = 8.0
	top.spot_angle = 60.0
	top.light_cull_mask = 0xFFFFF
	w.add_child(top)
	top.translation = Vector3(0.3, 3.6, -1.2)
	top.rotation_degrees = Vector3(-70, 0, 0)
	var fill = OmniLight.new()
	fill.light_energy = 0.6
	fill.omni_range = 6.0
	fill.light_color = Color(1.0, 0.9, 0.75)
	w.add_child(fill)
	fill.translation = Vector3(-1.5, 1.4, -2.0)
	cam = Camera.new()
	cam.fov = 40
	w.add_child(cam)
	var h = model.get_meta("height") if model.has_meta("height") else 2.0
	cam.translation = Vector3(0, h * 0.62, -h * 1.55)
	cam.look_at(Vector3(0, h * 0.55, 0), Vector3.UP)
	cam.current = true


func _idle(_d: float) -> bool:
	n += 1
	if n == 2:
		_setup()
	var i = (n - 6) / 4
	if n >= 6 and (n - 6) % 4 == 0 and i < angles.size():
		pivot.rotation_degrees.y = angles[i]
	if n >= 8 and (n - 8) % 4 == 0 and (n - 8) / 4 < angles.size():
		var img = root.get_texture().get_data()
		img.flip_y()
		img.save_png("%s_%d.png" % [out, (n - 8) / 4])
	return n > 6 + angles.size() * 4 + 4
