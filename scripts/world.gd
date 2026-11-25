extends Spatial
## Runs one round: environment, operatives, HUD, post-processing, death and escape. (Godot 3)
## Scene layout: Root (Node) -> VC (ViewportContainer) -> VP (Viewport) -> World (this).
## The 3D world renders inside VP so potato mode can draw it at half resolution;
## the HUD and post-processing live on Root at full resolution.
## Multiplayer: every peer builds the same office from Net.round_seed. The server runs the
## brainrots and the rules; clients drive puppets. A dedicated server has no player and no HUD.

const FACE := Vector3(0, 2.2, -0.4)
const Avatar = preload("res://scripts/avatar.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")

var rng = RandomNumberGenerator.new()
var nav
var player
var hud
var level
var env: Environment
var post: ShaderMaterial
var uncanny
var bake      # light_bake.gd of the current level (baked office lighting), or null
var avatars = {}          # peer id -> avatar (the other operatives)
var enemies = []          # brainrots in spawn order (same index on every peer)
var headless = false      # dedicated server: no player, no HUD
var my_out = false        # local operative is dead or escaped (spectating)
var spectate_id = -1
var dying = false
var completing = false
var paused = false
var danger = 0.0
var _heart = 0.0
var _flash = 0.0
var _pulse = 0.0
var _last_yaw = 0.0
var _last_pitch = 0.0
var _blur = Vector2.ZERO
var _nv = 0.0
var _cull_t = 0.0
var _spec_t = 0.0
var _note_open_cb = false
var _rig: Spatial
var _scare = 0            # jumpscare phase: 0 none · 1 dark silence · 2 screaming
var _scare_t = 0.0
var _scare_m: Spatial
var _scare_mouth: MeshInstance
var _scare_base = Vector3.ZERO


func _ready() -> void:
	# The scene root is still adding its children; build everything one step later.
	call_deferred("_setup")


func _setup() -> void:
	headless = Net.dedicated
	rng.randomize()
	if Game.forced_seed >= 0:
		rng.seed = Game.forced_seed
		seed(Game.forced_seed)
	Net.world = self
	Audio.silence_all(false)
	Audio.set_silence(false)
	var we = WorldEnvironment.new()
	env = Environment.new()
	we.environment = env
	add_child(we)
	setup_env({})
	if not headless:
		player = load("res://scripts/player.gd").new()
		player.world = self
		add_child(player)
		hud = load("res://scripts/hud.gd").new()
		hud.world = self
		owner.add_child(hud)
		if TouchControls.wanted():
			var tc = TouchControls.new()
			tc.world = self
			owner.add_child(tc)
		var pl = CanvasLayer.new()
		pl.layer = 50
		# Potato: post-processing runs inside the low-res 3D viewport, so it costs a quarter.
		if int(Game.settings.gfx) == 0:
			get_viewport().add_child(pl)
		else:
			owner.add_child(pl)
		var rect = ColorRect.new()
		UI.full_rect(rect)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		post = ShaderMaterial.new()
		post.shader = load("res://scripts/post.shader")
		rect.material = post
		pl.add_child(rect)
	var id: String = Game.current_level
	level = load("res://scripts/levels/level_%s.gd" % id).new()
	level.world = self
	level.rng = rng
	add_child(level)
	level.build()
	_spawn_players()
	_apply_quality()
	Game.connect("settings_changed", self, "_apply_quality")
	if hud:
		var info: Dictionary = Game.INFO.get(id, {})
		hud.title_card(info.get("title", ""), info.get("name", ""))
		get_tree().create_timer(4.5).connect("timeout", self, "_show_goal", [info.get("goal", "")])
		if not level.boot_goggles:
			hud.fade(0.0, 2.0)


func _show_goal(goal: String) -> void:
	if not dying and hud:
		if TouchControls.wanted():
			goal = goal.replace("(q)", "(tap)")
		var n = Net.round_ids().size()
		hud.objective(goal if n <= 1 else "%d operatives inside.  %s" % [n, goal])


func _spawn_players() -> void:
	var ids = Net.round_ids() if Net.active() else [1]
	var me = Net.my_id()
	var base: Vector3 = level.spawn_pos
	var yaw: float = level.spawn_yaw
	for i in ids.size():
		var pid: int = ids[i]
		var off = Vector3(((i % 3) - 1) * 0.9, 0, int(i / 3) * 0.9).rotated(Vector3.UP, yaw)
		var at = base + off
		if player and pid == me:
			player.global_transform.origin = at
			player.set_look(yaw, 0.0)
		else:
			var a = Avatar.new()
			add_child(a)
			a.setup(pid, Net.pname(pid), Net.pcolor(pid), headless)
			a.place(at, yaw)
			avatars[pid] = a


func setup_env(c: Dictionary) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = c.get("bg", Color(0, 0, 0))
	env.ambient_light_color = c.get("ambient", Color(0.35, 0.3, 0.28))
	env.ambient_light_energy = c.get("ambient_energy", 0.3)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = c.get("exposure", 1.0)
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	# Source-style depth fog (env_fog_controller): starts close, gets thick fast.
	env.fog_enabled = c.get("fog", true)
	env.fog_color = c.get("fog_color", Color(0.02, 0.02, 0.02))
	env.fog_depth_enabled = true
	env.fog_depth_begin = c.get("fog_begin", 6.0)
	env.fog_depth_end = c.get("fog_end", 50.0)
	env.fog_depth_curve = c.get("fog_curve", 1.0)
	env.fog_height_enabled = false
	env.adjustment_enabled = true
	env.adjustment_contrast = c.get("contrast", 1.1)
	env.adjustment_saturation = c.get("saturation", 0.85)
	if post:
		post.set_shader_param("tint", c.get("tint", Vector3(1.0, 0.97, 0.92)))
	set_meta("tint", c.get("tint", Vector3(1.0, 0.97, 0.92)))


## 0 potato (half resolution, few lights, no shadows) · 1 low · 2 high
func _apply_quality() -> void:
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	env.glow_enabled = q >= 1
	for d in get_tree().get_nodes_in_group("dust"):
		d.emitting = q >= 1
		d.visible = q >= 1
	for l in get_tree().get_nodes_in_group("lamp"):
		var want: bool = l.get_meta("shadow_wanted") if l.has_meta("shadow_wanted") else false
		l.shadow_enabled = want and q >= 2
	if post:
		post.set_shader_param("intensity", float(Game.settings.post))
		post.set_shader_param("brightness", float(Game.settings.brightness))
		post.set_shader_param("fisheye", float(Game.settings.fisheye))
		post.set_shader_param("blur_amount", float(Game.settings.motion_blur))
		post.set_shader_param("samples", [1.0, 5.0, 12.0][q])
		post.set_shader_param("cheap", q == 0)
		if has_meta("tint"):
			post.set_shader_param("tint", get_meta("tint"))
	if bake:
		for m in bake.mats:
			m.set_shader_param("lite", q == 0)
	if player:
		player.cam.fov = 88.0 + float(Game.settings.fisheye) * 14.0
		# Nothing past the fog gets drawn on potato.
		player.cam.far = 36.0 if q == 0 else 300.0
	_cull_lamps()


## Old GPUs pay for every light on every object: only the nearest lamps stay on.
func _cull_lamps() -> void:
	if player == null:
		return
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	# Real lamp lights only touch brainrots and props now (the office is baked): a few is plenty.
	var radius: float = [10.0, 16.0, 24.0][q]
	var max_on: int = [3, 5, 8][q]
	var pp: Vector3 = player.global_transform.origin
	var lamps = []
	for l in get_tree().get_nodes_in_group("lamp"):
		lamps.append([l.global_transform.origin.distance_to(pp), l])
	lamps.sort_custom(self, "_by_dist")
	var glare: float = [12.0, 20.0, 30.0][q]
	for i in lamps.size():
		var near: bool = i < max_on and lamps[i][0] < radius
		Geo.lamp_set_near(lamps[i][1], near, lamps[i][0] < glare)


## The nearest brainrot's own top light, drawn into the baked floor: a pool of light and a
## dark contact shadow under its feet.
func _feed_actor() -> void:
	var best = null
	var bd = 1e9
	var pp: Vector3 = player.global_transform.origin
	for e in get_tree().get_nodes_in_group("hostile"):
		if not e.visible:
			continue
		var d = e.global_transform.origin.distance_to(pp)
		if d < bd:
			bd = d
			best = e
	if best == null:
		bake.set_actor(Vector2.ZERO, 0.0)
		return
	var o: Vector3 = best.global_transform.origin
	var k = 0.0
	if best.top_light and best.top_light.visible:
		k = best.top_light.light_energy / max(best.light_energy, 0.001)
	bake.set_actor(Vector2(o.x, o.z), 0.38 * k, 2.4)


func _by_dist(a, b) -> bool:
	return a[0] < b[0]


# ------------------------------------------------------------------ who can be hunted
## Operatives still inside the office: [{id, pos, eye}]. The server's brainrots hunt these.
func targets() -> Array:
	var out = []
	if not Net.active():
		if player and not dying and not completing:
			out.append({"id": 1, "pos": player.global_transform.origin, "eye": player.eye_pos()})
		return out
	var me = Net.my_id()
	for pid in Net.round_ids():
		var p = Net.players[pid]
		if not p.alive or p.escaped:
			continue
		if player and pid == me:
			if not my_out and not dying and not completing:
				out.append({"id": pid, "pos": player.global_transform.origin, "eye": player.eye_pos()})
		elif avatars.has(pid):
			var a = avatars[pid]
			out.append({"id": pid, "pos": a.global_transform.origin, "eye": a.eye_pos()})
	return out


func target_by_id(pid: int):
	for t in targets():
		if t.id == pid:
			return t
	return null


## A brainrot reached an operative (server, or offline).
func catch_target(pid: int, killer: String, msg: String) -> void:
	if Net.active():
		Net.catch(pid, msg)
	elif pid == 1:
		kill(killer, msg)


# ------------------------------------------------------------------ network glue
func net_enemies() -> Array:
	var out = []
	for e in enemies:
		if is_instance_valid(e):
			out.append(e)
	return out


func send_local_state() -> void:
	if player == null or my_out or dying or completing:
		return
	var flags = (1 if player.crouching else 0) | (2 if player.horizontal_speed() > 0.3 else 0)
	Net.send_state(player.global_transform.origin, player.rotation.y, player.head.rotation.x, flags)


func net_player_state(pid: int, pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	if avatars.has(pid):
		var p = Net.players.get(pid)
		if p == null or (p.alive and not p.escaped):
			avatars[pid].net_update(pos, yaw, pitch, flags)


func net_enemy_state(idx: int, pos: Vector3, yaw: float, st: int) -> void:
	if idx < enemies.size() and is_instance_valid(enemies[idx]):
		enemies[idx].net_apply(pos, yaw, st)


func net_event(type: String, args: Array) -> void:
	var me = Net.my_id()
	match type:
		"shout":
			var pid: int = args[0]
			if pid != me:
				if avatars.has(pid):
					avatars[pid].shout()
				if hud:
					hud.subtitle("%s: \"sahur!\"" % Net.pname(pid), 1.6)
		"died":
			var pid: int = args[0]
			var msg: String = args[1] if args.size() > 1 and args[1] != "" else "tung tung tung sahur found you.\nyou should have answered."
			if pid == me and player:
				if not dying:
					kill("tung", msg)
			elif hud:
				hud.subtitle("%s became rot." % Net.pname(pid), 3.5)
				if not dying:
					var at = avatars[pid].global_transform.origin + Vector3(0, 1.6, 0) if avatars.has(pid) else player.global_transform.origin
					Audio.play_at("scare_scream_far", at, self, 8.0, 1.0, 120.0)
		"escaped":
			var pid: int = args[0]
			if pid == me and player:
				complete()
			else:
				if avatars.has(pid):
					avatars[pid].visible = false
				if hud:
					hud.subtitle("%s made it out." % Net.pname(pid), 3.0)
		"left":
			var pid: int = args[0]
			if avatars.has(pid):
				avatars[pid].queue_free()
				avatars.erase(pid)
		_:
			if level and level.has_method("net_event"):
				level.net_event(type, args)


func net_round_over(res: Array) -> void:
	if hud:
		var lines = PoolStringArray()
		for r in res:
			lines.append("%s · %s" % [r[0], r[1]])
		hud.show_stats(false)
		hud.set_spectate("")
		hud.death("round over", lines.join("\n") + "\n\n\nback to the lobby…")
		if player:
			player.controls = false
	get_tree().create_timer(7.0 if hud else 3.0).connect("timeout", Net, "back_to_lobby")


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if level == null or player == null:
		return
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.25
		_cull_lamps()
	if bake:
		_feed_actor()
		# the haze goes dark with the lights
		var fc: Color = get_meta("fog_base") if has_meta("fog_base") else env.fog_color
		if not has_meta("fog_base"):
			set_meta("fog_base", fc)
		env.fog_color = fc.linear_interpolate(Color(0.01, 0.01, 0.01), 0.9 if bake.black else 0.0)
	if my_out:
		_spec_t -= delta
		if _spec_t <= 0.0:
			_spec_t = 0.5
			var a = avatars.get(spectate_id)
			var p = Net.players.get(spectate_id)
			if a == null or not is_instance_valid(a) or p == null or not p.alive or p.escaped:
				_next_spectate()
	var drain: float = level.drain_rate
	var d = 0.0
	if not dying and not completing and not my_out:
		for e in get_tree().get_nodes_in_group("hostile"):
			if not e.visible or e.frozen:
				continue
			var dist: float = e.global_transform.origin.distance_to(player.global_transform.origin)
			d = max(d, clamp(1.0 - dist / 18.0, 0.0, 1.0))
			if e.drains and dist < 16.0 and e.seen_by_player(40.0, 16.0):
				drain += 0.6 + 2.2 * (1.0 - dist / 16.0)
		if not paused and not hud.note_open:
			Game.brain_cells = clamp(Game.brain_cells - drain * delta, 0.0, 100.0)
			if Game.brain_cells <= 0.0:
				var why = "your last brain cell left.\nyou looked at him for too long."
				kill(level.killer_id(), why)
				if Net.active():
					Net.request("died", [why])
		d = max(d, level.danger_bonus)
	danger = lerp(danger, d, clamp(delta * 3.0, 0.0, 1.0))
	if not dying and not completing:
		Audio.set_breath(danger if danger > 0.3 else 0.0)
	var madness: float = clamp((60.0 - Game.brain_cells) / 60.0, 0.0, 1.0) if not my_out else 0.0
	Audio.set_madness(madness * 0.8)
	_flash = max(0.0, _flash - delta * 2.5)
	post.set_shader_param("danger", danger)
	post.set_shader_param("madness", madness)
	post.set_shader_param("flash", _flash)
	# Camera motion blur: how far the view turned this frame, in screen units
	var yaw: float = player.rotation.y
	var pitch: float = player.head.rotation.x
	var dyaw = wrapf(yaw - _last_yaw, -PI, PI)
	var dpitch = pitch - _last_pitch
	_last_yaw = yaw
	_last_pitch = pitch
	var vs = get_viewport().get_visible_rect().size
	var hfov = deg2rad(player.cam.fov) * vs.x / max(vs.y, 1.0)
	var target = Vector2(dyaw / max(hfov, 0.1), -dpitch / deg2rad(player.cam.fov)) * 1.4
	if target.length() > 0.12:
		target = target.normalized() * 0.12
	_blur = _blur.linear_interpolate(target, 0.6)
	post.set_shader_param("blur_dir", _blur)
	post.set_shader_param("radial", clamp(player.horizontal_speed() / 4.2, 0.0, 1.5) * 0.035)
	var nv_target = 1.0 if player.flashlight_on else 0.0
	_nv = move_toward(_nv, nv_target, delta * (2.5 if nv_target > _nv else 8.0))
	var nv_show = _nv
	if nv_target > 0.5 and _nv < 0.98 and randf() < 0.35:
		nv_show = randf() * _nv
	post.set_shader_param("nv", nv_show)
	_heart -= delta
	if danger > 0.35 and _heart <= 0.0 and not dying:
		_heart = 1.25 - danger * 0.6
		Audio.play("heartbeat", -10.0 + danger * 8.0)
		_pulse = 1.0
	_pulse = max(0.0, _pulse - delta * 3.0)
	post.set_shader_param("pulse", _pulse)
	if _scare == 2:
		_scare_frame(delta)


func _unhandled_input(event: InputEvent) -> void:
	if hud == null:
		return
	if hud.note_open and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		close_note()
		get_tree().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and (Net.active() or (not dying and not completing)):
		set_paused(not paused)
		get_tree().set_input_as_handled()
		return
	if my_out and not paused and (((event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed) or event.is_action_pressed("jump")):
		_next_spectate()
		return
	if dying and not Net.active() and event is InputEventMouseButton and event.pressed and has_meta("can_skip"):
		Game.restart_level()


## Single player freezes the world; in multiplayer the office keeps going around you.
func set_paused(on: bool) -> void:
	paused = on
	if not Net.active():
		get_tree().paused = on
	elif player and not my_out and not dying and not completing:
		player.controls = not on
	hud.set_pause_visible(on)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED)


func flash(x := 1.0) -> void:
	_flash = max(_flash, x)


func _on_exit_body(body) -> void:
	if body == player and player and not my_out and not dying and not completing:
		if Net.active():
			Net.request("escaped")
		else:
			complete()


# ------------------------------------------------------------------ notes
func show_note(text: String) -> void:
	Audio.play("page", -4.0)
	player.controls = false
	hud.show_note(text)


func close_note() -> void:
	hud.hide_note()
	Audio.play("page", -8.0, 1.2)
	player.controls = not my_out and not dying and not completing


# ------------------------------------------------------------------ death (the jumpscare)
## A third of a second of nothing at all, then his face is on you, screaming as loud as
## digital audio goes. Then a hard cut to black and silence.
func kill(_id: String, msg: String) -> void:
	if dying or completing or my_out or player == null:
		return
	dying = true
	player.controls = false
	player.look_enabled = false
	if hud.note_open:
		hud.hide_note()
	hud.show_stats(false)
	hud.set_prompt("")
	hud.island.modulate.a = 0.0
	hud._island_t = 0.0
	Audio.silence_all(true)
	hud.fade_rect.color = Color(0, 0, 0, 1)
	for e in get_tree().get_nodes_in_group("hostile"):
		e.visible = false
	_rig = Spatial.new()
	player.cam.add_child(_rig)
	var m = TungModel.build()
	_rig.add_child(m)
	m.rotation.y = PI
	# aim between the eyes and the mouth so the whole screaming face fills the view
	_scare_base = Vector3(0, -0.02, -0.52) - Vector3(0, 2.13, 0.4)
	m.translation = _scare_base - Vector3(0, 0, 0.45)
	# wide awake: no lids, bulging eyes, and a mouth tearing open
	for n in ["lidL", "lidR"]:
		var lid = m.find_node(n, true, false)
		if lid:
			lid.visible = false
	for n in ["eyeL", "eyeR"]:
		var eye = m.find_node(n, true, false)
		if eye:
			eye.scale = Vector3.ONE * 1.3
	var body = m.find_node("body", true, false)
	_scare_mouth = MeshInstance.new()
	_scare_mouth.mesh = Models.sphere(1.0, -1, 24, 12)
	_scare_mouth.material_override = Mats.unshaded(Color(0.035, 0.0, 0.0))
	body.add_child(_scare_mouth)
	_scare_mouth.translation = Vector3(0, TungModel.EY - 0.25, -TungModel.R + 0.012)
	_scare_mouth.scale = Vector3(0.13, 0.001, 0.05)
	var l = SpotLight.new()
	l.light_color = Color(1, 0.97, 0.9)
	l.light_energy = 9.0
	l.spot_range = 5.0
	l.spot_angle = 32.0
	_rig.add_child(l)
	l.translation = Vector3(0, 1.6, -0.75)
	l.rotation_degrees = Vector3(-88, 0, 0)
	var under = OmniLight.new()
	under.light_color = Color(1.0, 0.86, 0.78)
	under.light_energy = 2.4
	under.omni_range = 1.6
	_rig.add_child(under)
	under.translation = Vector3(0, -0.35, -0.15)
	_scare_m = m
	m.visible = false
	_scare = 1
	_scare_t = 0.0
	var tw = create_tween()
	tw.tween_interval(0.32)
	tw.tween_callback(self, "_scare_hit")
	tw.tween_interval(1.95)
	tw.tween_callback(self, "_scare_cut")
	tw.tween_interval(0.8)
	tw.tween_callback(self, "_death_screen", [msg])
	tw.tween_interval(2.6)
	tw.tween_callback(self, "_death_hint", [msg])
	tw.tween_interval(3.5)
	if Net.active():
		tw.tween_callback(self, "_begin_spectate")
	else:
		tw.tween_callback(Game, "restart_level")


func _scare_hit() -> void:
	_scare = 2
	_scare_t = 0.0
	hud.fade_rect.color = Color(0, 0, 0, 0)
	if is_instance_valid(_scare_m):
		_scare_m.visible = true
	Audio.scare("scare_scream", 0.0)
	flash(1.0)
	player.add_trauma(1.0)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(1900)


## Cut, not fade: black and dead silence.
func _scare_cut() -> void:
	_scare = 0
	hud.fade_rect.color = Color(0, 0, 0, 1)
	Audio.silence_all(true)
	if is_instance_valid(_rig):
		_rig.queue_free()


## Every frame while he screams: he lunges in, twitches, the mouth stretches, the picture strobes.
func _scare_frame(delta: float) -> void:
	_scare_t += delta
	if not is_instance_valid(_scare_m):
		return
	var k = clamp(_scare_t / 0.11, 0.0, 1.0)
	k = 1.0 - (1.0 - k) * (1.0 - k)
	var p = _scare_base - Vector3(0, 0, 0.45) * (1.0 - k) + Vector3(0, 0, 0.04) * k
	p += Vector3(rand_range(-1, 1) * 0.024, rand_range(-1, 1) * 0.024, rand_range(-1, 1) * 0.014)
	_scare_m.translation = p
	_scare_m.rotation = Vector3(rand_range(-0.07, 0.07), PI + rand_range(-0.06, 0.06), rand_range(-0.16, 0.16))
	var open = clamp(_scare_t / 0.09, 0.0, 1.0)
	_scare_mouth.scale = Vector3(0.12 + 0.025 * sin(_scare_t * 41.0), 0.001 + (0.1 + 0.02 * sin(_scare_t * 57.0)) * open, 0.05)
	player.add_trauma(delta * 6.0)
	post.set_shader_param("madness", 1.0)
	post.set_shader_param("danger", 1.0)
	post.set_shader_param("flash", 0.6 if fmod(_scare_t, 0.09) < 0.035 else 0.0)


func _death_screen(msg: String) -> void:
	if is_instance_valid(_rig):
		_rig.queue_free()
	hud.death("you became rot", msg)
	hud.fade_rect.color = Color(0, 0, 0, 0)


func _death_hint(msg: String) -> void:
	set_meta("can_skip", true)
	var more = "the others are still inside." if Net.active() else "click to try again"
	hud.death_small.text = (msg + "\n\n\n" + more).to_lower()


# ------------------------------------------------------------------ spectating (multiplayer)
func _begin_spectate() -> void:
	my_out = true
	dying = false
	completing = false
	if Net.state != Net.PLAYING:
		return
	Audio.silence_all(false)
	Audio.set_silence(false)
	hud.death_root.visible = false
	hud.fade(0.0, 0.8)
	hud.show_stats(false)
	for e in get_tree().get_nodes_in_group("hostile"):
		e.visible = true
	_next_spectate()


func _next_spectate() -> void:
	var alive = []
	for pid in Net.round_ids():
		var p = Net.players[pid]
		if p.alive and not p.escaped and avatars.has(pid) and is_instance_valid(avatars[pid]):
			alive.append(pid)
	if spectate_id >= 0 and avatars.has(spectate_id) and is_instance_valid(avatars[spectate_id]):
		avatars[spectate_id].set_spectated(false)
	if alive.empty():
		spectate_id = -1
		player.spectate(null)
		hud.set_spectate("no one left inside.  waiting for the round to end…")
		return
	var i = alive.find(spectate_id)
	spectate_id = alive[(i + 1) % alive.size()]
	avatars[spectate_id].set_spectated(true)
	player.spectate(avatars[spectate_id])
	hud.set_spectate("spectating %s   ·   click for the next" % Net.pname(spectate_id))


# ------------------------------------------------------------------ escape
func complete() -> void:
	if dying or completing or my_out:
		return
	completing = true
	player.controls = false
	Audio.play("ding", -2.0)
	Audio.play("transition", -2.0)
	var tw = hud.fade(1.0, 1.6)
	tw.tween_callback(self, "_ending")
	if Net.active():
		tw.tween_interval(5.0)
		tw.tween_callback(self, "_begin_spectate")
	else:
		tw.tween_interval(7.0)
		tw.tween_callback(self, "_to_menu")


func _ending() -> void:
	hud.show_stats(false)
	if not Net.active():
		Audio.stop_ambient(2.0)
	hud.death("you made it out", "for now.\n\nhush thanks you, operative.\nhe will call again tomorrow, at 3 am.", UI.WHITE)


func _to_menu() -> void:
	Game.finish_game()
	Game.main_menu()
