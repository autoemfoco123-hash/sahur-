extends Spatial
## Runs one round: environment, operatives, HUD, post-processing, death and escape. (Godot 3)
## Scene layout: Root (Node) -> VC (ViewportContainer) -> VP (Viewport) -> World (this).
## The 3D world renders inside VP so potato mode can draw it at half resolution;
## the HUD and post-processing live on Root at full resolution.
## Multiplayer: every peer builds the same office from Net.round_seed. The server runs the
## brainrots and the rules; clients drive puppets. A dedicated server has no player and no HUD.
## One round is one run: every sector is built at once, wall to wall along x, and each exit
## is a sliding door that opens onto the next sector itself (a wave game). `level` is the
## sector the local camera is in; `levels[i]` is sector i; `doors[i]` is sector i's exit.

const FACE := Vector3(0, 2.2, -0.4)
const WALL_T = 0.28        # outer wall thickness of a sector (level_0.gd T)
const SlideDoor = preload("res://scripts/slide_door.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const MAX_CORPSES = 6
const Avatar = preload("res://scripts/avatar.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")

var rng = RandomNumberGenerator.new()
var nav
var player
var hud
var level                 # the sector the local camera is in (view_sector)
var levels = []           # every sector of the run, by number
var view_sector = -1
var my_sector = 0         # the sector the local operative is in
var start_sector = 0
var env: Environment
var post: ShaderMaterial
var uncanny
var bake      # light_bake.gd of the current level (baked office lighting), or null
var photo     # photo.gd: the hush field camera
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
var _mouth_closed = Vector3.ONE
var _mouth_open = Vector3.ONE
var _scare_sound = "scare_scream"
var _booted = false
var doors = {}            # sector -> its exit door (slide_door.gd)
var _greeter: Spatial     # the thing waiting on the other side of the door
var _greeter_door = null
var _greeter_gone = 0.0
var _greeter_id = ""
var _greeted = {}
var _fog_base = Color(0, 0, 0)
var _points = 0           # offline: the local operative's points
var _photo_best_off = {}  # offline: enemy index -> best photo score
var _pending_revive = -1
var round_over = false
var corpses = []
var _my_corpse = null


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
		var cam_node = load("res://scripts/photo.gd").new()
		cam_node.world = self
		cam_node.name = "Camera"
		add_child(cam_node)
		photo = cam_node
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
	# every sector of the run, side by side; each one gets its own seed so every machine
	# builds the same rooms no matter what the others drew before
	var id: String = Game.current_level
	start_sector = int(clamp(Game.LEVELS.find(id), 0, Game.LEVELS.size() - 1))
	var base_seed: int = Game.forced_seed if Game.forced_seed >= 0 else int(rng.randi() % 2000000000)
	var x = 0.0
	for i in Game.LEVELS.size():
		var lv = load("res://scripts/levels/level_%s.gd" % Game.LEVELS[i]).new()
		lv.world = self
		lv.index = i
		# each sector's west wall stands right against the previous sector's east wall,
		# and its entrance lines up with the previous exit
		lv.origin = Vector3(x, 0, 0)
		if i > 0:
			lv.has_entry = true
			lv.entry_z = levels[i - 1].exit_z
		lv.geo = Spatial.new()
		lv.geo.name = "Sector%d" % i
		add_child(lv.geo)
		var r = RandomNumberGenerator.new()
		r.seed = base_seed + i * 7919
		seed(base_seed + i * 7919)
		lv.rng = r
		add_child(lv)
		levels.append(lv)
		lv.build()
		x = lv.origin.x + lv.extent.x + WALL_T
	_build_doors()
	level = levels[start_sector]
	nav = level.nav
	my_sector = start_sector
	setup_env(level.env_cfg)
	_spawn_players()
	if player:
		player.connect("shouted", self, "_local_shout")
	_apply_quality()
	Game.connect("settings_changed", self, "_apply_quality")
	level.start_wave()
	if player:
		set_view(start_sector)
	if hud:
		var info: Dictionary = Game.INFO.get(id, {})
		hud.title_card(info.get("title", ""), info.get("name", ""))
		get_tree().create_timer(4.5).connect("timeout", self, "_show_goal", [info.get("goal", "")])
		if not level.boot_goggles:
			hud.fade(0.0, 2.0)


func _show_goal(goal: String) -> void:
	if not dying and hud:
		if TouchControls.wanted():
			goal = goal.replace("(q)", "(tap)").replace("(f)", "(camera)")
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


# ------------------------------------------------------------------ sectors
## Sectors are wall to wall along x: the seam between two is the middle of the double wall.
func sector_at(p: Vector3) -> int:
	for i in range(levels.size() - 1, 0, -1):
		if p.x >= levels[i].origin.x - WALL_T * 0.5:
			return i
	return 0


## The sector an operative is in (the server's word in multiplayer).
func level_of(pid: int):
	if levels.empty():
		return null
	var s = my_sector
	if Net.active() and Net.players.has(pid):
		s = int(Net.players[pid].get("sector", 0))
	return levels[int(clamp(s, 0, levels.size() - 1))]


## The local camera moved into sector s: its look, its sound, its ghosts.
func set_view(s: int, force := false) -> void:
	if s < 0 or s >= levels.size() or (s == view_sector and not force):
		return
	var boot = not _booted
	_booted = true
	view_sector = s
	level = levels[s]
	nav = level.nav
	bake = level.get("bake")
	_apply_quality()
	if boot or player == null:
		setup_env(level.env_cfg)
	else:
		_blend_env(level.env_cfg, 1.2)
	if player == null:
		return
	missions_changed(level)
	level.enter(boot and level.boot_goggles)
	if uncanny != null and is_instance_valid(uncanny):
		uncanny.queue_free()
	uncanny = null
	if not my_out and not level.uncanny_cfg.empty():
		uncanny = Uncanny.new()
		uncanny.setup(self, level.uncanny_cfg)
		uncanny.add_tposers(int(level.uncanny_cfg.get("tposers", 0)))


# ------------------------------------------------------------------ points and missions
## Server (or offline): a photo was taken. It is worth how much it beats that operative's best
## photo of that same brainrot (x1.5 if it was hunting at the time). Then the sector's rules.
func photo_scored(pid: int, id: String, score: int, inst: int) -> void:
	if inst >= 0 and inst < enemies.size() and is_instance_valid(enemies[inst]):
		var best: Dictionary = _photo_best_off
		if Net.active() and Net.players.has(pid):
			if not Net.players[pid].has("photo_best"):
				Net.players[pid].photo_best = {}
			best = Net.players[pid].photo_best
		var k = str(inst)
		var gain = score - int(best.get(k, 0))
		if gain > 0:
			best[k] = score
			if enemies[inst].is_threat():
				gain = int(round(gain * 1.5))
			award(pid, gain, "photo")
	var lv = level_of(pid)
	if lv and lv.has_method("on_request"):
		lv.on_request(pid, "photo", [id, score, inst])


## Server (or offline): give an operative points.
func award(pid: int, pts: int, why: String) -> void:
	if pts <= 0:
		return
	if Net.active():
		Net.award(pid, pts, why)
	else:
		_points += pts
		if hud:
			hud.set_points(_points, pts, why)


## A mission moved: refresh the list if it is the sector you are looking at.
func missions_changed(lv) -> void:
	if hud and lv == level:
		hud.set_missions(Game.INFO.get(Game.LEVELS[lv.index], {}).get("title", ""), lv.missions)


func my_points() -> int:
	if Net.active() and Net.players.has(Net.my_id()):
		return int(Net.players[Net.my_id()].get("points", 0))
	return _points


## Dust around the player, the amount the sector wants.
func set_dust(amount: int) -> void:
	if player == null:
		return
	for d in get_tree().get_nodes_in_group("dust"):
		if d.get_parent() == player:
			d.remove_from_group("dust")
			d.queue_free()
	var p = Geo.dust(player, amount)
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	p.emitting = q >= 1
	p.visible = q >= 1


func _local_shout() -> void:
	if Net.active():
		Net.request("shout")
	elif not levels.empty():
		levels[my_sector].on_shout(1)


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
	_fog_base = env.fog_color
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
	for lv in levels:
		var b = lv.get("bake")
		if b:
			for m in b.mats:
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
## Operatives still inside: [{id, pos, eye, fwd, sector}]. The server's brainrots hunt these.
## sector >= 0: only the ones in that sector (a brainrot never leaves its own).
func targets(sector := -1) -> Array:
	var all = _targets()
	if sector < 0:
		return all
	var out = []
	for t in all:
		if t.sector == sector:
			out.append(t)
	return out


func _targets() -> Array:
	var out = []
	if not Net.active():
		if player and not dying and not completing:
			var pp = player.global_transform.origin
			out.append({"id": 1, "pos": pp, "eye": player.eye_pos(), "fwd": -player.cam.global_transform.basis.z, "sector": sector_at(pp)})
		return out
	var me = Net.my_id()
	for pid in Net.round_ids():
		var p = Net.players[pid]
		if not p.alive or p.escaped:
			continue
		if player and pid == me:
			if not my_out and not dying and not completing:
				var pp = player.global_transform.origin
				out.append({"id": pid, "pos": pp, "eye": player.eye_pos(), "fwd": -player.cam.global_transform.basis.z, "sector": sector_at(pp)})
		elif avatars.has(pid):
			var a = avatars[pid]
			var fwd = Basis(Vector3.UP, a.yaw).xform(Basis(Vector3.RIGHT, a.pitch).xform(Vector3.FORWARD))
			var ap = a.global_transform.origin
			out.append({"id": pid, "pos": ap, "eye": a.eye_pos(), "fwd": fwd, "sector": sector_at(ap)})
	return out


func target_by_id(pid: int, sector := -1):
	for t in targets(sector):
		if t.id == pid:
			return t
	return null


## A brainrot reached an operative (server, or offline).
func catch_target(pid: int, killer: String, msg: String, enemy_idx := -1) -> void:
	if Net.active():
		Net.catch(pid, msg, killer, enemy_idx)
	elif pid == 1:
		_death_show(1, enemy_idx)
		kill(killer, msg)


# ------------------------------------------------------------------ how a death looks to everyone
## The brainrot that did it plays its kill (Tung brings the bat down, a key slams into them) and
## when the blow lands the body goes flying as a ragdoll. Everyone in the round sees it; the
## victim gets the jumpscare instead, and finds their body lying there afterwards.
func _death_show(pid: int, enemy_idx: int) -> void:
	var me = Net.my_id() if Net.active() else 1
	var at = Vector3.INF
	var yaw = 0.0
	var mine = pid == me and player != null
	if mine:
		at = player.global_transform.origin
		yaw = player.rotation.y
	elif avatars.has(pid) and is_instance_valid(avatars[pid]):
		at = avatars[pid].global_transform.origin
		yaw = avatars[pid].yaw
	var e = null
	if enemy_idx >= 0 and enemy_idx < enemies.size() and is_instance_valid(enemies[enemy_idx]):
		e = enemies[enemy_idx]
	if e and at != Vector3.INF:
		e.play_kill(at)
	if headless or at == Vector3.INF:
		return
	var push = Vector3(rand_range(-0.6, 0.6), 1.2, rand_range(-0.6, 0.6))
	var hit = 0.0
	if e:
		var dir = at - e.global_transform.origin
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		# a little sideways too: the bat comes across the body
		dir = (dir + dir.cross(Vector3.UP) * rand_range(-0.35, 0.35)).normalized()
		push = dir * e.kill_force + Vector3(0, e.kill_lift, 0)
		hit = e.kill_hit
	var color = Net.pcolor(pid) if Net.active() else UI.AMBER
	get_tree().create_timer(hit).connect("timeout", self, "_body_flies", [pid, mine, at, yaw, color, push, e != null])


func _body_flies(pid: int, mine: bool, at: Vector3, yaw: float, color: Color, push: Vector3, struck: bool) -> void:
	if not mine and avatars.has(pid) and is_instance_valid(avatars[pid]):
		avatars[pid].visible = false
	var r = Ragdoll.new()
	r.build(self, color, at, yaw, push)
	corpses.append(r)
	while corpses.size() > MAX_CORPSES:
		var old = corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	if mine:
		# behind the jumpscare: shown when the scream cuts, lying wherever it landed
		r.visible = false
		_my_corpse = r
	if struck:
		var hp = at + Vector3(0, 1.3, 0)
		Audio.play_at("tung", hp, self, 10.0, 0.5, 70.0)
		Audio.play_at("stomp", hp, self, 4.0, 0.75, 60.0)
		if player and not mine and player.global_transform.origin.distance_to(at) < 14.0:
			player.add_trauma(0.35)


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
			var a = avatars[pid]
			if a.global_transform.origin.distance_to(pos) > 12.0:
				a.place(pos, yaw)      # through a door, or back from the dead: no gliding
			a.net_update(pos, yaw, pitch, flags)


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
			_death_show(pid, int(args[3]) if args.size() > 3 else -1)
			var msg: String = args[1] if args.size() > 1 and args[1] != "" else "tung tung tung sahur found you.\nyou should have answered."
			if pid == me and player:
				if not dying:
					kill(args[2] if args.size() > 2 else level.killer_id(), msg)
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
		"sector":
			var s: int = args[0]
			if s >= 0 and s < levels.size():
				if args[1] == "mission":
					levels[s].apply_mission(args[2])
				else:
					levels[s].net_event(args[1], args[2])
		"wave":
			var s: int = args[0]
			if s < levels.size() and not levels[s].wave_started:
				levels[s].start_wave()
		"advanced":
			var pid: int = args[0]
			var s: int = args[1]
			if pid != me and hud and player and view_sector == s - 1 and not dying:
				var info: Dictionary = Game.INFO.get(Game.LEVELS[s], {})
				hud.subtitle("%s went through to %s." % [Net.pname(pid), info.get("name", "")], 3.5)
		"door":
			var d = doors.get(int(args[0]))
			if d:
				d.open()
		"points":
			if args[0] == me and hud:
				hud.set_points(int(args[1]), int(args[2]), str(args[3]))
		"revived":
			var pid: int = args[0]
			if pid == me and player:
				revive_local(args[1])
			else:
				if avatars.has(pid):
					avatars[pid].visible = true
				if hud and not dying:
					hud.subtitle("%s is back.   hush sent them in again." % Net.pname(pid), 3.5)
		_:
			if level and level.has_method("net_event"):
				level.net_event(type, args)


func net_round_over(res: Array) -> void:
	round_over = true
	if hud:
		var lines = PoolStringArray()
		var team = 0
		for r in res:
			team += int(r[5]) if r.size() > 5 else 0
			var pts = "%d pts · " % int(r[5]) if r.size() > 5 else ""
			if r[0] == "next":
				lines.append("\nnext: %s" % r[1])
			elif r.size() > 4 and r[3] > 0:
				lines.append("%s · %s · %sbest photo %d (%s)" % [r[0], r[1], pts, r[3], r[4]])
			else:
				lines.append("%s · %s · %sno photo" % [r[0], r[1], pts])
		hud.show_stats(false)
		hud.set_spectate("")
		hud.death("round over", lines.join("\n") + "\n\nteam · %d pts\n\nback to the lobby…" % team)
		if player:
			player.controls = false
	get_tree().create_timer(7.0 if hud else 3.0).connect("timeout", Net, "back_to_lobby")


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if level == null or player == null:
		return
	set_view(sector_at(player.cam.global_transform.origin))
	if not my_out and not dying and not completing:
		var ps = sector_at(player.global_transform.origin)
		if ps > my_sector:
			_arrive(ps)
	_greeter_check()
	if _greeter != null:
		_greeter_frame(delta)
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.25
		_cull_lamps()
		_update_sector_vis()
	if bake:
		_feed_actor()
		# the haze goes dark with the lights
		env.fog_color = _fog_base.linear_interpolate(Color(0.01, 0.01, 0.01), 0.9 if bake.black else 0.0)
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


# ------------------------------------------------------------------ the doors between sectors
## Every exit is a sliding door in the east wall: into the next sector, or (the last one) out.
func _build_doors() -> void:
	for i in levels.size():
		var lv = levels[i]
		var last = i == levels.size() - 1
		var x = lv.origin.x + lv.extent.x + (0.0 if last else WALL_T * 0.5)
		var d = SlideDoor.new()
		d.setup(self, Vector3(x, lv.origin.y, lv.exit_z), i, -1 if last else i + 1, WALL_T if last else WALL_T * 2.0)
		doors[i] = d
		if last:
			_build_way_out(d)


## Behind the last door: a short concrete corridor, a green exit sign, and the way out.
func _build_way_out(d) -> void:
	var o: Vector3 = d.global_transform.origin
	var x0 = o.x + d.depth * 0.5
	var L = 3.4
	var hw = 1.1
	var hh = 2.5
	var mat = null if headless else Mats.std(Color(0.2, 0.2, 0.19), 0.9)
	var show = not headless
	Geo.solid(self, Vector3(L + 0.2, 0.2, hw * 2.0 + 0.4), Vector3(x0 + L * 0.5, o.y - 0.1, o.z), mat, null, show)
	Geo.solid(self, Vector3(L + 0.2, 0.2, hw * 2.0 + 0.4), Vector3(x0 + L * 0.5, o.y + hh + 0.1, o.z), mat, null, show)
	for s in [-1.0, 1.0]:
		Geo.solid(self, Vector3(L + 0.2, hh, 0.2), Vector3(x0 + L * 0.5, o.y + hh * 0.5, o.z + s * (hw + 0.1)), mat, null, show)
	Geo.solid(self, Vector3(0.2, hh, hw * 2.0 + 0.4), Vector3(x0 + L + 0.1, o.y + hh * 0.5, o.z), mat, null, show)
	var a = Area.new()
	a.collision_layer = 0
	a.collision_mask = Geo.LAYER_PLAYER
	add_child(a)
	var cs = CollisionShape.new()
	var sh = BoxShape.new()
	sh.extents = Vector3(0.6, 1.2, hw)
	cs.shape = sh
	a.add_child(cs)
	a.global_transform.origin = Vector3(x0 + 1.5, o.y + 1.2, o.z)
	a.connect("body_entered", self, "_on_way_out")
	if show:
		Geo.label3d(self, "exit", Vector3(x0 + L - 0.02, o.y + 2.0, o.z), 64, Color(0.4, 1.0, 0.5), -PI * 0.5)
		var g = Models.part(self, Models.box(Vector3(0.03, 0.16, 0.5)), Mats.glow(Color(0.3, 1.0, 0.45), 3.0), Vector3(x0 + L - 0.02, o.y + 2.32, o.z))
		g.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var l = Geo.omni(self, Vector3(x0 + L - 0.7, o.y + 2.2, o.z), Color(0.45, 1.0, 0.55), 1.5, 5.5)
		l.add_to_group("lamp")


func _on_way_out(body) -> void:
	if body == player and player and not my_out and not dying and not completing:
		if Net.active():
			Net.request("escaped")
		else:
			complete()


## [E] on a door.
func door_use(door) -> void:
	if player == null or my_out or dying or completing:
		return
	if player.global_transform.origin.x > door.global_transform.origin.x:
		door.deny()       # it only opens from the side you leave through
		return
	if door.locked():
		var n = levels[door.from_sector].missions_left()
		hud.subtitle("locked.   %d mission%s left." % [n, "" if n == 1 else "s"], 2.5)
		hud.flash_missions()
		door.deny()
		return
	if door.want_open:
		door.open()       # just keeps it open a little longer
		return
	if Net.active():
		Net.request("door", [door.from_sector])
	else:
		door.open()


## You walked through a door into sector s.
func _arrive(s: int) -> void:
	my_sector = s
	if Net.active():
		Net.request("advance", [s - 1])
	elif not levels[s].wave_started:
		levels[s].start_wave()
	var info: Dictionary = Game.INFO.get(Game.LEVELS[s], {})
	get_tree().create_timer(0.8).connect("timeout", self, "_title", [info])


func _title(info: Dictionary) -> void:
	if hud and not dying and not my_out:
		hud.title_card(info.get("title", ""), info.get("name", ""))
		get_tree().create_timer(4.5).connect("timeout", self, "_show_goal", [info.get("goal", "")])


## Only the sector you are in is drawn, plus a neighbour you can see into (you are near its
## door, or the door is open). Brainrots in hidden sectors are not drawn either.
func _update_sector_vis() -> void:
	var cam: Vector3 = player.cam.global_transform.origin
	var shown = {}
	for lv in levels:
		var v = lv.index == view_sector
		for k in [lv.index, lv.index - 1]:
			var d = doors.get(k)
			if v or d == null:
				continue
			if (d.from_sector == view_sector or d.to_sector == view_sector) and (d.open_amt > 0.0 or d.global_transform.origin.distance_to(cam) < 14.0):
				v = true
		shown[lv.index] = v
		if lv.geo:
			lv.geo.visible = v
	for e in enemies:
		if is_instance_valid(e) and e.model:
			e.model.visible = shown.get(e.sector, true)


## The next sector's brainrot waits right behind the door, facing it: you see it through the
## little window before you open it. Only you see yours. Once the door is open, look away and
## it is gone.
func _greeter_check() -> void:
	if my_out or dying or completing or _greeted.has(my_sector):
		return
	var d = doors.get(my_sector)
	if d == null or d.to_sector < 0:
		return
	if d.global_transform.origin.distance_to(player.global_transform.origin) > 9.0:
		return
	_greeted[my_sector] = true
	var lv = levels[d.to_sector]
	if lv.greeter == "":
		return
	_clear_greeter()
	_greeter_id = lv.greeter
	_greeter_door = d
	_greeter = Spatial.new()
	add_child(_greeter)
	_greeter.add_child(Brainrots.build(lv.greeter))
	_greeter.global_transform.origin = d.global_transform.origin + Vector3(d.depth * 0.5 + 1.5, 0, 0)
	_greeter.rotation.y = PI * 0.5        # facing the door
	var l = OmniLight.new()
	l.light_color = Color(1.0, 0.86, 0.72)
	l.light_energy = 1.2
	l.omni_range = 3.0
	l.light_cull_mask = Geo.VIS_ACTOR
	_greeter.add_child(l)
	l.translation = Vector3(0, 2.2, -0.6)
	_greeter_gone = 0.0


func _clear_greeter() -> void:
	if _greeter != null and is_instance_valid(_greeter):
		_greeter.queue_free()
	_greeter = null


func _greeter_frame(delta: float) -> void:
	if not is_instance_valid(_greeter):
		_greeter = null
		return
	if not is_instance_valid(_greeter_door) or _greeter_door.open_amt < 0.7:
		return            # waiting behind the closed door
	var head = _greeter.global_transform.origin + Vector3(0, 1.4, 0)
	var near = player.global_transform.origin.distance_to(_greeter.global_transform.origin) < 1.0
	if near or not player.can_see(head, 34.0, 14.0):
		_greeter_gone += delta
		if near or _greeter_gone > 0.12:
			# gone, and something lands right behind you
			_clear_greeter()
			var back: Vector3 = player.cam.global_transform.basis.z
			back.y = 0.0
			var at = player.global_transform.origin + back.normalized() * 1.4 + Vector3(0, 1.2, 0)
			Audio.play_at("key_hop" if _greeter_id == "keys" else "ev_whisper", at, self, 6.0, 0.8, 20.0)
			Audio.play("whisper", -8.0, 0.7)
	else:
		_greeter_gone = 0.0


## Moving between sectors: the haze, the light and the tint drift over instead of snapping.
func _blend_env(c: Dictionary, dur: float) -> void:
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(env, "ambient_light_color", c.get("ambient", Color(0.35, 0.3, 0.28)), dur)
	tw.tween_property(env, "ambient_light_energy", c.get("ambient_energy", 0.3), dur)
	tw.tween_property(env, "fog_depth_begin", c.get("fog_begin", 6.0), dur)
	tw.tween_property(env, "fog_depth_end", c.get("fog_end", 50.0), dur)
	tw.tween_property(env, "fog_depth_curve", c.get("fog_curve", 1.0), dur)
	tw.tween_property(env, "adjustment_contrast", c.get("contrast", 1.1), dur)
	tw.tween_property(env, "adjustment_saturation", c.get("saturation", 0.85), dur)
	tw.tween_property(self, "_fog_base", c.get("fog_color", Color(0.02, 0.02, 0.02)), dur)
	var t0: Vector3 = get_meta("tint") if has_meta("tint") else Vector3(1, 1, 1)
	var t1: Vector3 = c.get("tint", Vector3(1.0, 0.97, 0.92))
	tw.tween_method(self, "_set_tint", t0, t1, dur)
	set_meta("tint", t1)


func _set_tint(t: Vector3) -> void:
	if post:
		post.set_shader_param("tint", t)


# ------------------------------------------------------------------ back from the dead (waves)
## A new wave started: hush sends the dead back in, at the start of that sector.
func revive_local(s: int) -> void:
	if player == null or s < 0 or s >= levels.size():
		return
	if dying:
		_pending_revive = s      # after the scream is over
		return
	_pending_revive = -1
	_clear_greeter()
	if spectate_id >= 0 and avatars.has(spectate_id) and is_instance_valid(avatars[spectate_id]):
		avatars[spectate_id].set_spectated(false)
	spectate_id = -1
	my_out = false
	dying = false
	completing = false
	if has_meta("can_skip"):
		remove_meta("can_skip")
	player.unspectate()
	my_sector = s
	var lv = levels[s]
	var arrive = lv.arrive_pos != Vector3.INF
	var yaw = lv.arrive_yaw if arrive else lv.spawn_yaw
	var fwd = Vector3(-sin(yaw), 0, -cos(yaw))
	player.global_transform.origin = (lv.arrive_pos if arrive else lv.spawn_pos) + fwd * rand_range(0.3, 0.9) + fwd.cross(Vector3.UP) * rand_range(-0.6, 0.6)
	player.velocity = Vector3.ZERO
	player.set_look(yaw, 0.0)
	Game.brain_cells = 100.0
	Audio.silence_all(false)
	Audio.set_silence(false)
	post.set_shader_param("ca_amount", 1.0)
	for e in get_tree().get_nodes_in_group("hostile"):
		e.visible = true
	hud.death_root.visible = false
	hud.set_spectate("")
	hud.show_stats(true)
	hud.fade_rect.color = Color(0, 0, 0, 1)
	hud.fade(0.0, 1.4)
	set_view(s, true)
	var info: Dictionary = Game.INFO.get(Game.LEVELS[s], {})
	hud.subtitle("hush pulled you back in.   %s · %s." % [info.get("title", ""), info.get("name", "")], 4.5)
	Audio.play("nv_on", -4.0)


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
## The instant you are caught his face is on you, screaming as loud as digital audio goes.
## Then a hard cut to black and silence.
func kill(_id: String, msg: String) -> void:
	if dying or completing or my_out or player == null:
		return
	dying = true
	_clear_greeter()
	player.controls = false
	player.look_enabled = false
	if hud.note_open:
		hud.hide_note()
	hud.show_stats(false)
	hud.set_prompt("")
	hud.island.modulate.a = 0.0
	hud._island_t = 0.0
	for e in get_tree().get_nodes_in_group("hostile"):
		e.visible = false
	_rig = Spatial.new()
	player.cam.add_child(_rig)
	var m: Spatial
	_scare_sound = "scare_keys" if _id == "keys" else "scare_scream"
	if _id == "keys":
		m = load("res://scripts/keys_model.gd").build()
		_rig.add_child(m)
		m.rotation.y = PI
		# the face from the photo fills the view
		var KM = load("res://scripts/keys_model.gd")
		var fp = KM._uv_pos((KM.MOUTH + KM.EYES) * 0.5)
		_scare_base = Vector3(0, -0.02, -0.55) - Vector3(-fp.x, KM.BOW_Y, -fp.z)
		# the face exactly as in the photo: no mouth, no colour fringing
		_scare_mouth = null
		post.set_shader_param("ca_amount", 0.0)
	else:
		m = TungModel.build()
		_rig.add_child(m)
		m.rotation.y = PI
		# aim between the eyes and the mouth so the whole screaming face fills the view
		_scare_base = Vector3(0, -0.02, -0.52) - Vector3(0, 2.13, 0.4)
		# wide awake: no lids, bulging eyes, and a mouth tearing open
		for n in ["lidL", "lidR"]:
			var lid = m.find_node(n, true, false)
			if lid:
				lid.visible = false
		for n in ["eyeL", "eyeR"]:
			var eye = m.find_node(n, true, false)
			if eye:
				eye.scale = Vector3.ONE * 1.3
		# the carved smile tears open (scare_mouth.gd), right along the carving
		var body = m.find_node("body", true, false)
		_scare_mouth = load("res://scripts/scare_mouth.gd").new()
		body.add_child(_scare_mouth)
	m.translation = _scare_base - Vector3(0, 0, 0.45)
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
	# no warning, no pause: the instant he has you, he is in your face, screaming
	_scare_hit()
	var tw = create_tween()
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
	Audio.scare(_scare_sound, 0.0)
	flash(1.0)
	player.add_trauma(1.0)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(1900)


## Cut, not fade: black and dead silence.
func _scare_cut() -> void:
	_scare = 0
	if _my_corpse != null and is_instance_valid(_my_corpse):
		_my_corpse.visible = true
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
	if is_instance_valid(_scare_mouth):
		open = 1.0 - (1.0 - open) * (1.0 - open)
		_scare_mouth.set_open(open * (0.9 + 0.1 * sin(_scare_t * 41.0)), sin(_scare_t * 57.0))
	player.add_trauma(delta * 6.0)
	post.set_shader_param("madness", 1.0)
	post.set_shader_param("danger", 1.0)
	# a few hard flashes (~3 per second, under the photosensitive danger band), not a flicker
	post.set_shader_param("flash", 0.6 if fmod(_scare_t, 0.33) < 0.05 else 0.0)


func _death_screen(msg: String) -> void:
	if round_over:
		return            # the round ended meanwhile: the results stay on screen
	if is_instance_valid(_rig):
		_rig.queue_free()
	hud.death("you became rot", msg)
	hud.fade_rect.color = Color(0, 0, 0, 0)


func _death_hint(msg: String) -> void:
	if round_over:
		return
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
	if _pending_revive >= 0:
		revive_local(_pending_revive)
		return
	Audio.silence_all(false)
	Audio.set_silence(false)
	hud.death_root.visible = false
	hud.fade(0.0, 0.8)
	post.set_shader_param("ca_amount", 1.0)
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
