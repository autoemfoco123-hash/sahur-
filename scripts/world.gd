class_name World
extends Node3D
## Runs one level: environment, player, HUD, post-processing, death and completion.

const FACE := {
	"tung": Vector3(0, 2.2, -0.4), "tralalero": Vector3(0, 2.05, -0.45), "ballerina": Vector3(0, 1.85, -0.25),
	"assassino": Vector3(0, 1.75, -0.32), "chimp": Vector3(0, 0.9, -0.4), "boneca": Vector3(0, 1.22, -0.36),
	"bombardiro": Vector3(0, 0.4, -4.6), "gusini": Vector3(0, 1.4, -4.0), "lirili": Vector3(0, 2.75, -0.5),
	"patapim": Vector3(0, 2.85, -0.75), "frigo": Vector3(0, 3.45, -0.9), "saturnita": Vector3(0, 0.6, -7.6),
}
const SCALE := {"bombardiro": 0.6, "gusini": 0.6, "saturnita": 0.28, "patapim": 0.85, "lirili": 0.9}

var rng := RandomNumberGenerator.new()
var nav: NavGrid
var player: Player
var hud: Hud
var level: LevelBase
var env: Environment
var cam_attr: CameraAttributesPractical
var uncanny: Uncanny
var post: ShaderMaterial
var dying := false
var completing := false
var paused := false
var danger := 0.0
var _heart := 0.0
var _flash := 0.0
var _pulse := 0.0
var _last_yaw := 0.0
var _last_pitch := 0.0
var _blur := Vector2.ZERO
var _nv := 0.0
var _note_cb: Callable


func _ready() -> void:
	rng.randomize()
	if Game.forced_seed >= 0:
		rng.seed = Game.forced_seed
		seed(Game.forced_seed)
	Audio.silence_all(false)
	Audio.set_silence(false)
	var we := WorldEnvironment.new()
	env = Environment.new()
	we.environment = env
	# Source-style HDR eye adaptation: walk out of the dark and the world blooms white.
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.35
	cam_attr.auto_exposure_speed = 0.6
	cam_attr.auto_exposure_min_sensitivity = 60.0
	cam_attr.auto_exposure_max_sensitivity = 260.0
	we.camera_attributes = cam_attr
	add_child(we)
	setup_env({})
	player = Player.new()
	player.world = self
	add_child(player)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	if TouchControls.wanted():
		var tc := TouchControls.new()
		tc.world = self
		add_child(tc)
	var pl := CanvasLayer.new()
	pl.layer = 50
	add_child(pl)
	var rect := UI.full_rect(ColorRect.new())
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://scripts/post.gdshader")
	rect.material = post
	pl.add_child(rect)
	var id := Game.current_level
	var path := "res://scripts/levels/level_%s.gd" % id.replace(".", "_")
	level = load(path).new()
	level.world = self
	level.rng = rng
	add_child(level)
	level.build()
	_apply_quality()
	Game.settings_changed.connect(_apply_quality)
	var info: Dictionary = Game.INFO.get(id, {})
	if id != "inf":
		hud.title_card(info.get("title", ""), info.get("name", ""))
		get_tree().create_timer(4.5).timeout.connect(func(): if not dying: hud.objective(info.get("goal", "")))
	if not level.boot_goggles:
		hud.fade(0.0, 2.0)


func setup_env(c: Dictionary) -> void:
	env.background_mode = Environment.BG_COLOR if not c.has("sky") else Environment.BG_SKY
	env.background_color = c.get("bg", Color(0, 0, 0))
	if c.has("sky"):
		var sky := Sky.new()
		sky.sky_material = c["sky"]
		env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = c.get("ambient", Color(0.35, 0.3, 0.28))
	env.ambient_light_energy = c.get("ambient_energy", 0.3)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = c.get("exposure", 1.0)
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = c.get("glow", 0.9)
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.8
	env.ssao_power = 1.8
	env.fog_enabled = c.get("fog", true)
	if c.has("fog_depth"):
		# Source-style depth fog (env_fog_controller): starts close, gets thick fast.
		var fd: Vector2 = c["fog_depth"]
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = fd.x
		env.fog_depth_end = fd.y
		env.fog_depth_curve = c.get("fog_curve", 1.0)
	else:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = c.get("fog_color", Color(0.02, 0.02, 0.02))
	env.fog_density = c.get("fog_density", 0.04)
	env.fog_sky_affect = c.get("fog_sky", 0.0)
	env.volumetric_fog_density = c.get("vol", 0.035)
	env.volumetric_fog_albedo = c.get("vol_albedo", Color(0.8, 0.78, 0.72))
	env.volumetric_fog_emission = c.get("vol_emission", Color(0, 0, 0))
	env.volumetric_fog_length = c.get("vol_length", 48.0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = c.get("gi", 0.8)
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.adjustment_enabled = true
	env.adjustment_contrast = c.get("contrast", 1.12)
	env.adjustment_saturation = c.get("saturation", 0.85)
	set_meta("vol_wanted", c.get("vol", 0.035) > 0.0)
	set_meta("ssr", c.get("ssr", true))
	set_meta("ssil", c.get("ssil", false))
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.3
	env.ssil_sharpness = 0.9
	env.ssil_normal_rejection = 1.0
	set_meta("gi_ok", c.get("gi_ok", true))
	if cam_attr:
		cam_attr.auto_exposure_scale = c.get("auto_exposure", 0.35)
		cam_attr.auto_exposure_enabled = c.get("auto_exposure", 0.35) > 0.0
	if post:
		post.set_shader_parameter("tint", c.get("tint", Vector3(1.0, 0.97, 0.92)))
	_apply_quality()


func _apply_quality() -> void:
	var q := int(Game.settings.quality)
	var high := q >= 1
	env.ssao_enabled = high
	env.ssr_enabled = high and get_meta("ssr", true)
	env.ssil_enabled = high and get_meta("ssil", false)
	env.volumetric_fog_enabled = high and get_meta("vol_wanted", true)
	env.sdfgi_enabled = q >= 2 and get_meta("gi_ok", true)
	if post:
		post.set_shader_parameter("intensity", float(Game.settings.post))
		post.set_shader_parameter("brightness", float(Game.settings.brightness))
		post.set_shader_parameter("fisheye", float(Game.settings.fisheye))
		post.set_shader_parameter("blur_amount", float(Game.settings.motion_blur))
	if player:
		player.cam.fov = 88.0 + float(Game.settings.fisheye) * 14.0


func _process(delta: float) -> void:
	if level == null:
		return
	# Brain cells + danger
	var drain := level.drain_rate
	var d := 0.0
	if not dying and not completing:
		for e in get_tree().get_nodes_in_group("hostile"):
			var en := e as Enemy
			if en == null or not en.visible or en.frozen:
				continue
			var dist := en.global_position.distance_to(player.global_position)
			d = maxf(d, clampf(1.0 - dist / 18.0, 0.0, 1.0))
			if en.drains and dist < 16.0 and en.seen_by_player(40.0, 16.0):
				drain += 0.6 + 2.2 * (1.0 - dist / 16.0)
		if not paused and not hud.note_open:
			Game.brain_cells = clampf(Game.brain_cells - drain * delta, 0.0, 100.0)
			if Game.brain_cells <= 0.0:
				kill(level.killer_id(), "your last brain cell left.\nyou looked at him for too long.")
	d = maxf(d, level.danger_bonus)
	danger = lerpf(danger, d, clampf(delta * 3.0, 0.0, 1.0))
	player.flicker = danger
	if not dying and not completing:
		Audio.set_breath(danger if danger > 0.3 else 0.0)
	var madness := clampf((60.0 - Game.brain_cells) / 60.0, 0.0, 1.0)
	Audio.set_madness(madness * 0.8)
	_flash = maxf(0.0, _flash - delta * 2.5)
	post.set_shader_parameter("danger", danger)
	post.set_shader_parameter("madness", madness)
	post.set_shader_parameter("flash", _flash)
	post.set_shader_parameter("pixelate", level.pixelate)
	# Camera motion blur: how far the view turned this frame, in screen units
	var yaw := player.rotation.y
	var pitch := player.head.rotation.x
	var dyaw := wrapf(yaw - _last_yaw, -PI, PI)
	var dpitch := pitch - _last_pitch
	_last_yaw = yaw
	_last_pitch = pitch
	var hfov := deg_to_rad(player.cam.fov) * get_viewport().get_visible_rect().size.aspect()
	var target := Vector2(dyaw / maxf(hfov, 0.1), -dpitch / deg_to_rad(player.cam.fov)) * 1.4
	_blur = _blur.lerp(target.limit_length(0.12), 0.6)
	post.set_shader_parameter("blur_dir", _blur)
	# Visor power-up: the tube flickers before it settles
	var nv_target := 1.0 if player.flashlight_on else 0.0
	_nv = move_toward(_nv, nv_target, delta * (2.5 if nv_target > _nv else 8.0))
	var nv_show := _nv
	if nv_target > 0.5 and _nv < 0.98 and randf() < 0.35:
		nv_show = randf() * _nv
	post.set_shader_parameter("nv", nv_show)
	post.set_shader_parameter("radial", clampf(player.horizontal_speed() / 4.2, 0.0, 1.5) * 0.035)
	# Heartbeat
	_heart -= delta
	if danger > 0.35 and _heart <= 0.0 and not dying:
		_heart = 1.25 - danger * 0.6
		Audio.play("heartbeat", -10.0 + danger * 8.0)
		_pulse = 1.0
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	post.set_shader_parameter("pulse", _pulse)


func _unhandled_input(event: InputEvent) -> void:
	if hud.note_open and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		close_note()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not dying and not completing:
		set_paused(not paused)
		get_viewport().set_input_as_handled()
	if dying and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and has_meta("can_skip"):
		Game.restart_level()


func set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	hud.set_pause_visible(on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func flash(x := 1.0) -> void:
	_flash = maxf(_flash, x)


# ------------------------------------------------------------------ notes
func show_note(text: String, cb := Callable()) -> void:
	Audio.play("page", -4.0)
	player.controls = false
	hud.show_note(text)
	_note_cb = cb


func close_note() -> void:
	hud.hide_note()
	Audio.play("page", -8.0, 1.2)
	player.controls = true
	if _note_cb.is_valid():
		_note_cb.call()
		_note_cb = Callable()


# ------------------------------------------------------------------ death
func kill(id: String, msg: String) -> void:
	if dying or completing:
		return
	dying = true
	player.controls = false
	player.look_enabled = false
	if hud.note_open:
		hud.hide_note()
	hud.show_stats(false)
	hud.set_prompt("")
	# The worst jumpscare is the silent one: every sound in the world stops.
	Audio.silence_all(true)
	for e in get_tree().get_nodes_in_group("hostile"):
		(e as Node3D).visible = false
	var rig := Node3D.new()
	player.cam.add_child(rig)
	var m := Models.build(id)
	rig.add_child(m)
	var s: float = SCALE.get(id, 1.0)
	var face: Vector3 = FACE.get(id, Vector3(0, m.get_meta("height", 2.0) * 0.85, -0.3)) * s
	m.scale = Vector3.ONE * s
	m.rotation.y = PI
	m.position = Vector3(0, -0.02, -0.62) - Vector3(-face.x, face.y, -face.z)
	var l := SpotLight3D.new()
	l.light_color = Color(1, 0.97, 0.9)
	l.light_energy = 9.0
	l.spot_range = 5.0
	l.spot_angle = 32.0
	l.shadow_enabled = true
	rig.add_child(l)
	l.position = Vector3(0, 1.6, -0.75)
	l.rotation_degrees = Vector3(-88, 0, 0)
	player.flashlight.visible = false
	# It doesn't lunge. It doesn't scream. It just looks at you, and tilts its head.
	var tw := create_tween()
	tw.tween_property(m, "rotation:z", deg_to_rad(9.0), 1.9).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(m, "position:z", m.position.z + 0.12, 1.9)
	tw.tween_callback(func():
		rig.queue_free()
		hud.death("you became rot", msg))
	tw.tween_interval(2.6)
	tw.tween_callback(func():
		set_meta("can_skip", true)
		hud.death_small.text = (msg + "\n\n\n" + ("tap" if TouchControls.wanted() else "click") + " to try again").to_lower())
	tw.tween_interval(3.5)
	tw.tween_callback(func(): Game.restart_level())


# ------------------------------------------------------------------ completion
func complete() -> void:
	if dying or completing:
		return
	completing = true
	player.controls = false
	Audio.play("ding", -2.0)
	Audio.play("transition", -2.0)
	var last := Game.LEVELS.find(Game.current_level) + 1 >= Game.LEVELS.size()
	var tw := hud.fade(1.0, 1.6)
	if last:
		tw.tween_callback(func():
			hud.show_stats(false)
			Audio.stop_ambient(2.0)
			hud.death("you made it out", "for now.\n\nhush thanks you, operative 03.\nhe will call again tomorrow, at 3 am.", UI.WHITE))
		tw.tween_interval(7.0)
		tw.tween_callback(func():
			Game.finish_game()
			Game.main_menu())
	else:
		tw.tween_interval(0.6)
		tw.tween_callback(func(): Game.next_level())
