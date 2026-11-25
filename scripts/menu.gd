extends Node3D
## Title screen: a hallway that never ends, and something standing at the end of it.

var cam: Camera3D
var tung: Node3D
var post: ShaderMaterial
var menu: VBoxContainer
var settings: SettingsPanel
var title: Label
var _t := 0.0
var _jump := 6.0
var _lights := []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.85, 0.6)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.4, 0.35, 0.22)
	env.fog_density = 0.03
	env.volumetric_fog_enabled = int(Game.settings.quality) == 1
	env.volumetric_fog_density = 0.05
	env.volumetric_fog_albedo = Color(1.0, 0.95, 0.8)
	env.volumetric_fog_density = 0.03
	env.ssao_enabled = int(Game.settings.quality) == 1
	we.environment = env
	add_child(we)
	# Endless corridor
	var wall := Mats.surf("wallpaper", Color(0.56, 0.47, 0.27), Color(0.36, 0.28, 0.14), {"wainscot": 1.05, "grime": 0.7, "stains": 0.7})
	var floor_m := Mats.surf("planks", Color(0.34, 0.21, 0.11), Color(0.2, 0.12, 0.06), {"roughness": 0.5})
	var ceil := Mats.surf("tiles", Color(0.55, 0.53, 0.48), Color(0.45, 0.43, 0.4), {"scale": 2.0, "grime": 0.8, "stains": 0.9})
	for i in 14:
		var z := -i * 6.0
		Geo.solid(self, Vector3(0.5, 3.2, 6), Vector3(-1.75, 1.6, z), wall)
		Geo.solid(self, Vector3(0.5, 3.2, 6), Vector3(1.75, 1.6, z), wall)
		Geo.solid(self, Vector3(4, 0.3, 6), Vector3(0, -0.15, z), floor_m)
		Geo.solid(self, Vector3(4, 0.3, 6), Vector3(0, 3.35, z), ceil)
		_lights.append(Geo.fluoro(self, Vector3(0, 3.17, z), 2.2, i < 4, Color(1.0, 0.96, 0.82)))
	tung = TungModel.build()
	add_child(tung)
	tung.position = Vector3(0.3, 0, -54)
	var tl := Geo.top_light(self, Vector3(0.3, 4.5, -54), Color(1, 0.9, 0.8), 9.0, 7.0, 25.0, true, false)
	tl.reparent(tung)
	cam = Camera3D.new()
	cam.fov = 88.0 + float(Game.settings.fisheye) * 14.0
	add_child(cam)
	cam.position = Vector3(0, 1.6, 4)
	cam.current = true
	# Post-processing
	var pl := CanvasLayer.new()
	pl.layer = 50
	add_child(pl)
	var rect := UI.full_rect(ColorRect.new())
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://scripts/post.gdshader")
	post.set_shader_parameter("intensity", float(Game.settings.post))
	post.set_shader_parameter("brightness", float(Game.settings.brightness))
	post.set_shader_parameter("tint", Vector3(1.04, 1.0, 0.82))
	post.set_shader_parameter("fisheye", float(Game.settings.fisheye))
	post.set_shader_parameter("blur_amount", float(Game.settings.motion_blur))
	rect.material = post
	pl.add_child(rect)
	_build_ui()
	Audio.ambient("amb_hall", -8.0)
	Audio.ambient("", 0, 1)
	Audio.set_madness(0.0)
	Audio.set_silence(false)
	Audio.silence_all(false)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var root := UI.full_rect(Control.new())
	layer.add_child(root)
	var box := VBoxContainer.new()
	box.position = Vector2(90, 120)
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	title = UI.label("sahur", 140, UI.WHITE, UI.font("thin"))
	box.add_child(title)
	box.add_child(UI.label("tung tung tung sahur. answer him.", 18, UI.SOFT))
	box.add_child(UI.label(" ", 30))
	menu = VBoxContainer.new()
	box.add_child(menu)
	if Game.has_save():
		var lvl: String = Game.LEVELS[clampi(Game.furthest, 0, Game.LEVELS.size() - 1)]
		menu.add_child(UI.button("CONTINUE   (%s)" % Game.INFO[lvl].title, func(): Game.continue_game()))
	menu.add_child(UI.button("NEW GAME", func(): Game.new_game()))
	menu.add_child(UI.button("SETTINGS", func():
		menu.visible = false
		settings.visible = true))
	menu.add_child(UI.button("QUIT", func(): get_tree().quit()))
	if Game.secret_found:
		box.add_child(UI.label(" ", 20))
		box.add_child(UI.label("♛  KING OF ROT", 18, Color(1, 0.78, 0.25)))
	settings = SettingsPanel.new()
	settings.visible = false
	settings.position = Vector2(80, 140)
	root.add_child(settings)
	settings.closed.connect(func():
		settings.visible = false
		menu.visible = true)
	var hint := UI.label("headphones recommended · don't play at 3 am", 13, UI.FAINT)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 90
	hint.offset_top = -50
	root.add_child(hint)


func _process(delta: float) -> void:
	_t += delta
	cam.position.z -= delta * 0.6
	if cam.position.z < -20.0:
		cam.position.z = 4.0
	cam.rotation.z = sin(_t * 0.4) * 0.01
	cam.rotation.y = sin(_t * 0.23) * 0.03
	# Glitchy title
	title.position.x = (randf() - 0.5) * 6.0 if randf() < 0.06 else 0.0
	title.modulate = Color(1, 1, 1, 0.55 + randf() * 0.45) if randf() < 0.08 else Color.WHITE
	# Every so often the lights die and he gets closer.
	_jump -= delta
	if _jump <= 0.0:
		_jump = randf_range(5.0, 9.0)
		for l in _lights:
			l.visible = false
		Audio.play("tung", -12.0, 0.7)
		get_tree().create_timer(0.35).timeout.connect(func():
			for l in _lights:
				l.visible = true
			tung.position.z = cam.position.z - randf_range(12.0, 50.0)
			tung.position.x = randf_range(-0.6, 0.6))
	post.set_shader_parameter("danger", clampf(1.0 - (cam.position.z - tung.position.z) / 30.0, 0.0, 0.7))
