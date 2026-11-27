extends Enemy
## 6-7 ULTRA (sector 3.5): the boss. It never leaves its pit; it does not need to. Everything it
## does, it does with its arms and its voice, and level_35.gd decides what and when (the server)
## and tells every machine; this script only performs it, the same everywhere:
##   rise()                         it comes up out of the pit
##   slam(h, at, tel)               hand h rises over `at`, hangs there for `tel`, comes down
##   sweep(h, a0, a1, tel, dur)     hand h drags across the floor from angle a0 to a1
##   scream(inhale)                 it draws breath for `inhale` seconds, then screams
##   call_number(n, warn)           it lifts the hand with that number and shouts it
##   hurt(), stagger(), set_shield(on), set_phase(p), die()
## The arms are two-bone IK chains that stretch when the target is further than they reach.
## The body turns slowly toward whatever it is busy with; its head, a scale with the 6 and the 7
## in its pans, turns to whoever is looking at it (on every machine its own camera), weighs the
## two numbers all the time, and tips hard toward the one it calls.

const UM = preload("res://scripts/ultra_model.gd")
const STRIKE = 0.16          # seconds from the end of a slam's telegraph to the impact
const RISE_LEN = 6.5
const DEATH_LEN = 9.0
const PIT_DEPTH = 27.0

enum B { HIDDEN, RISE, IDLE, SCREAM, CALL, STAGGER, DEATH }
var body_act = B.HIDDEN
var body_t = 0.0
var inhale = 2.0
var call_n = 0
var call_warn = 2.0
var hact = [{}, {}]          # per hand: {k: "idle"/"slam"/"sweep"/"raise"/"flail", t, ...}
var focus = Vector3.ZERO     # world point it is busy with
var shield_on = true
var phase = 1
var gone = false             # fully sunk after dying
var _shield_k = 1.0
var _shield_hit = 0.0
var _hurt = 0.0
var _t = 0.0
var _yaw_goal = 0.0
var _hp = [Vector3.ZERO, Vector3.ZERO]      # hand positions (model space)
var _hb = [Basis(), Basis()]
var _j = {}
var _skin: ShaderMaterial
var _bone: ShaderMaterial
var _dmat = []               # the 6's and the 7's materials (heat when called)
var _heat = [0.0, 0.0]
var _tilt = 0.0              # the beam: + tips the 7 down, - the 6
var _tilt_v = 0.0
var _swing = [Vector2.ZERO, Vector2.ZERO]
var _swing_v = [Vector2.ZERO, Vector2.ZERO]
var _prev_yaw = 0.0
var _shield_mat: ShaderMaterial
var _glow: OmniLight
var _rest = [Vector3(7.6, 0.55, -4.9), Vector3(-7.6, 0.55, -4.9)]
var _sink = 0.0              # how far down the pit it is (0: up)
var _cam_yaw = 0.0


func _init() -> void:
	death_msg = "6-7 ultra counted you.\nsix. seven. gone."
	chase_sound = ""
	light_energy = 0.0
	pinned = true
	drains = false
	catch_dist = -1.0


func _after_setup() -> void:
	collision_layer = Geo.LAYER_ENEMY
	collision_mask = 0
	top_light.visible = false
	for n in ["body", "head", "arm0_u", "arm0_f", "hand0", "arm1_u", "arm1_f", "hand1", "small0", "small1", "small2", "small3", "shield"]:
		var j = model.get_node_or_null(n)
		if j:
			_j[n] = j
	for i in 2:
		_hp[i] = _rest[i]
		hact[i] = {"k": "idle", "t": 0.0}
	_sink = PIT_DEPTH
	model.translation.y = -_sink
	model.visible = false
	if world.headless:
		return
	_skin = UM.skin_mat(false)
	_bone = UM.skin_mat(true)
	_skin.set_shader_param("vein_glow", 1.0)
	_skin.set_shader_param("pulse_rate", 1.1)
	_skin.set_shader_param("hurt", 0.0)
	_skin.set_shader_param("dying", 0.0)
	for i in 2:
		var num = model.get_node_or_null("head/pan%d/num" % i)
		if num:
			_dmat.append(num.mesh.surface_get_material(0))
	if _j.has("shield"):
		_shield_mat = _j.shield.material_override
	# the numbers light what is round them, red
	_glow = OmniLight.new()
	_glow.light_color = Color(1.0, 0.12, 0.06)
	_glow.light_energy = 1.4
	_glow.omni_range = 13.0
	_glow.omni_attenuation = 1.6
	_glow.light_cull_mask = 1 | Geo.VIS_ACTOR
	_j.head.add_child(_glow)
	_glow.translation = Vector3(0, UM.FACE_UP, -2.4)
	# and a cold light from high above, to carve it out of the dark
	var key = SpotLight.new()
	key.light_color = Color(0.82, 0.86, 0.95)
	key.light_energy = 3.2
	key.spot_range = 40.0
	key.spot_angle = 34.0
	key.spot_attenuation = 0.6
	key.shadow_enabled = int(Game.settings.gfx) >= 2
	key.light_cull_mask = Geo.VIS_ACTOR
	add_child(key)
	key.translation = Vector3(0, 34, -10)
	key.rotation_degrees = Vector3(-62, 180, 0)
	# cold light grazing it from behind, both sides: the wet hide shines along its edges
	# (one on low, none on potato: each light is one more pass over the whole body)
	var q = int(Game.settings.gfx)
	for sd in ([1.0, -1.0] if q >= 2 else ([1.0] if q == 1 else [])):
		var rim = SpotLight.new()
		rim.light_color = Color(0.7, 0.78, 0.9)
		rim.light_energy = 2.6
		rim.spot_range = 42.0
		rim.spot_angle = 30.0
		rim.light_cull_mask = Geo.VIS_ACTOR
		add_child(rim)
		rim.transform = Transform(Basis(), Vector3(sd * 16, 26, 18)).looking_at(Vector3(0, 10, 0), Vector3.UP)


func is_threat() -> bool:
	return body_act != B.HIDDEN and body_act != B.DEATH


func check_catch() -> void:
	pass             # it never just touches you: everything it does is an attack (level_35.gd)


func net_state() -> int:
	return 0


# ------------------------------------------------------------------ what it is told to do
func rise() -> void:
	model.visible = true
	body_act = B.RISE
	body_t = 0.0
	_snd("ultra_roar", _head_world(), world, 8.0, 0.75, 160.0)
	_snd("tile_drop", global_transform.origin, world, 6.0, 0.5, 120.0)


func slam(h: int, at: Vector3, tel: float) -> void:
	hact[h] = {"k": "slam", "t": 0.0, "at": at, "tel": tel, "from": _hp[h]}
	focus = at
	_snd("ultra_inhale", _head_world(), world, 0.0, 0.6, 120.0)


func sweep(h: int, a0: float, a1: float, tel: float, dur: float) -> void:
	hact[h] = {"k": "sweep", "t": 0.0, "a0": a0, "a1": a1, "tel": tel, "dur": dur}
	focus = global_transform.origin + Vector3(sin((a0 + a1) * 0.5), 0, cos((a0 + a1) * 0.5)) * 14.0


func scream(inhale_len: float) -> void:
	body_act = B.SCREAM
	body_t = 0.0
	inhale = inhale_len
	_snd("ultra_inhale", _head_world(), world, 6.0, 0.85, 160.0)


func call_number(n: int, warn: float) -> void:
	body_act = B.CALL
	body_t = 0.0
	call_n = n
	call_warn = warn
	var h = 0 if n == 6 else 1
	hact[h] = {"k": "raise", "t": 0.0, "warn": warn}


func hurt() -> void:
	_hurt = 1.0
	_snd("ultra_hit", _head_world(), world, 6.0, rand_range(0.85, 1.05), 140.0)


func stagger() -> void:
	body_act = B.STAGGER
	body_t = 0.0
	for i in 2:
		hact[i] = {"k": "flail", "t": 0.0}


func set_shield(on: bool) -> void:
	if on == shield_on:
		return
	shield_on = on
	_shield_hit = 1.0
	_snd("shield_up" if on else "shield_break", global_transform.origin + Vector3(0, 10, 0), world, 6.0, 1.0, 160.0)


func set_phase(p: int) -> void:
	phase = p
	if _skin:
		_skin.set_shader_param("vein_glow", [1.0, 1.0, 1.6, 2.4][clamp(p, 0, 3)])
		_skin.set_shader_param("pulse_rate", [1.1, 1.1, 1.6, 2.2][clamp(p, 0, 3)])
	for m in _dmat:
		m.set_shader_param("pulse_rate", [1.1, 1.1, 1.6, 2.2][clamp(p, 0, 3)])
	_snd("ultra_roar", _head_world(), world, 10.0, 0.62, 180.0)


func die() -> void:
	body_act = B.DEATH
	body_t = 0.0
	shield_on = false
	for i in 2:
		hact[i] = {"k": "flail", "t": 0.0}
	_snd("ultra_death", _head_world(), world, 10.0, 1.0, 200.0)


func _snd(sname: String, pos: Vector3, _parent, vol := 0.0, pitch := 1.0, dist := 60.0) -> void:
	if not world.headless:
		Audio.play_at(sname, pos, world, vol, pitch, dist)


# ------------------------------------------------------------------ where things are
func _head_world() -> Vector3:
	if _j.has("head"):
		return _j.head.global_transform.origin
	return global_transform.origin + Vector3(0, UM.FACE_Y, 0)


## Where its "face" is right now, the middle of the scale (screams come from here).
func face_world() -> Vector3:
	if _j.has("head"):
		var f = _j.head.get_node_or_null("face")
		if f:
			return f.global_transform.origin
	return global_transform.origin + Vector3(0, UM.FACE_Y, 0)


func hand_world(h: int) -> Vector3:
	return model.global_transform.xform(_hp[h])


func _to_model(p: Vector3) -> Vector3:
	return model.global_transform.affine_inverse().xform(p)


# ------------------------------------------------------------------ performing it
func _animate(delta: float, _spd: float) -> void:
	if world == null or _j.empty():
		return
	_t += delta
	body_t += delta
	var center = global_transform.origin
	# turning: slowly, toward what it is busy with (or the nearest operative)
	var f = focus
	if f == Vector3.ZERO or body_act == B.IDLE and hact[0].k == "idle" and hact[1].k == "idle":
		var best = 1e9
		for t in world.targets(sector):
			var d = _flat(t.pos, center)
			if d < best:
				best = d
				f = t.pos
	if f != Vector3.ZERO:
		var to = f - center
		_yaw_goal = atan2(-to.x, -to.z)
	if body_act != B.DEATH and body_act != B.HIDDEN:
		rotation.y = lerp_angle(rotation.y, _yaw_goal, clamp(delta * 0.9, 0.0, 1.0))
	_body_step(delta)
	for i in 2:
		_hand_step(i, delta)
		_pose_arm(i)
	_head_step(delta)
	_fx_step(delta)


func _body_step(delta: float) -> void:
	var body: Spatial = _j.body
	var breathe = sin(_t * 0.9)
	var lean = 0.0
	var roll = sin(_t * 0.37) * 0.02
	match body_act:
		B.HIDDEN:
			_sink = PIT_DEPTH
		B.RISE:
			var k = clamp(body_t / RISE_LEN, 0.0, 1.0)
			_sink = PIT_DEPTH * pow(1.0 - k, 2.2)
			roll += sin(_t * 9.0) * 0.03 * (1.0 - k)
			if world.player and not world.my_out and body_t < RISE_LEN:
				world.player.add_trauma(delta * 0.9)
			if body_t >= RISE_LEN:
				body_act = B.IDLE
		B.SCREAM:
			if body_t < inhale:
				lean = -0.16 * smoothstep(0.0, inhale, body_t)
			elif body_t < inhale + 2.4:
				lean = 0.22 + sin(_t * 31.0) * 0.015
				if body_t - delta < inhale:
					_snd("ultra_roar", _head_world(), world, 14.0, 0.95, 220.0)
			else:
				lean = 0.22 * (1.0 - smoothstep(inhale + 2.4, inhale + 3.4, body_t))
				if body_t > inhale + 3.4:
					body_act = B.IDLE
		B.CALL:
			lean = -0.2 * smoothstep(0.0, 0.5, body_t) * (1.0 - smoothstep(call_warn, call_warn + 0.6, body_t))
			if body_t - delta < 0.35 and body_t >= 0.35:
				_snd("chant_%d" % call_n, _head_world(), world, 16.0, 0.55, 220.0)
				_snd("ultra_roar", _head_world(), world, 4.0, 1.2, 160.0)
			if body_t > call_warn + 1.0:
				body_act = B.IDLE
		B.STAGGER:
			lean = 0.3 * smoothstep(0.0, 0.4, body_t) * (1.0 - smoothstep(2.6, 3.4, body_t))
			roll += sin(_t * 7.0) * 0.05 * (1.0 - smoothstep(2.0, 3.4, body_t))
			if body_t > 3.4:
				body_act = B.IDLE
				for i in 2:
					if hact[i].k == "flail":
						hact[i] = {"k": "idle", "t": 0.0}
		B.DEATH:
			var k = body_t
			roll += sin(_t * 13.0) * 0.08 * (1.0 - smoothstep(2.5, 4.0, k))
			lean = 0.35 * smoothstep(0.0, 1.5, k) - 0.5 * smoothstep(3.0, 6.0, k)
			_sink = PIT_DEPTH * smoothstep(3.0, DEATH_LEN, k) * 1.2
			if world.player and not world.my_out and k < 7.0:
				world.player.add_trauma(delta * (1.2 if k < 3.0 else 0.6))
			if k > DEATH_LEN and not gone:
				gone = true
				model.visible = false
	lean -= _hurt * 0.12
	body.rotation = Vector3(lean, 0, roll)
	body.scale = Vector3(1.0 + breathe * 0.012, 1.0 + breathe * 0.006, 1.0 + breathe * 0.018)
	model.translation.y = -_sink
	# its little arms never stop
	for k in 4:
		var s: Spatial = _j.get("small%d" % k)
		if s:
			var w = 3.0 + k
			s.rotation = Vector3(sin(_t * w + k) * 0.25 + (sin(_t * 23.0 + k * 3.0) * 0.12 if randf() < 0.2 else 0.0), sin(_t * w * 0.7) * 0.2, cos(_t * w * 1.3 + k) * 0.18)


## Where hand i should be now (model space), and its basis.
func _hand_step(i: int, delta: float) -> void:
	var a: Dictionary = hact[i]
	a.t = a.get("t", 0.0) + delta
	var sd = 1.0 if i == 0 else -1.0
	var rest: Vector3 = _rest[i] + Vector3(0, sin(_t * 0.9 + i) * 0.08, 0)
	var tgt = rest
	var rate = 4.0
	var out = Vector3(rest.x, 0, rest.z).normalized()
	var fdir = (out + Vector3(0, -0.3, 0)).normalized()
	var palm_n = Vector3(0, -1, 0)
	match a.k:
		"idle":
			pass
		"slam":
			var at = _to_model(a.at)
			var tel: float = a.tel
			var above = at + Vector3(0, 11.0, 0) - Vector3(at.x, 0, at.z).normalized() * 2.0
			if a.t < tel:
				tgt = above + Vector3(sin(_t * 5.0), sin(_t * 7.0), 0) * 0.25
				rate = 3.5
				fdir = (Vector3(at.x, 0, at.z).normalized() + Vector3(0, 0.6, 0)).normalized()
				palm_n = Vector3(0, -1, 0)
				a.strike_from = _hp[i]
			elif a.t < tel + STRIKE:
				var k = (a.t - tel) / STRIKE
				_hp[i] = a.get("strike_from", above).linear_interpolate(at + Vector3(0, 0.45, 0), k * k * k)
				tgt = _hp[i]
				rate = 1000.0
				fdir = (Vector3(at.x, 0, at.z).normalized() + Vector3(0, -0.8, 0)).normalized()
				if a.t + delta >= tel + STRIKE and not a.get("hit", false):
					a.hit = true
					_impact(model.global_transform.xform(at))
			elif a.t < tel + STRIKE + 1.0:
				tgt = at + Vector3(0, 0.3, 0)
				rate = 30.0
				fdir = (Vector3(at.x, 0, at.z).normalized() + Vector3(0, -0.25, 0)).normalized()
			else:
				rate = 2.5
				if a.t > tel + STRIKE + 2.4:
					hact[i] = {"k": "idle", "t": 0.0}
		"sweep":
			var R = 12.5
			var tel: float = a.tel
			var dur: float = a.dur
			var ang: float = a.a0
			if a.t < tel:
				ang = a.a0
				rate = 3.0
			elif a.t < tel + dur:
				var k = (a.t - tel) / dur
				ang = lerp(a.a0, a.a1, k * k * (3.0 - 2.0 * k))
				rate = 1000.0
				if a.t - delta < tel:
					_snd("ultra_sweep", hand_world(i), world, 10.0, 0.9, 120.0)
			else:
				ang = a.a1
				rate = 2.0
				if a.t > tel + dur + 2.0:
					hact[i] = {"k": "idle", "t": 0.0}
			if a.t < tel + dur + 0.5:
				var wp = global_transform.origin + Vector3(sin(ang), 0, cos(ang)) * R + Vector3(0, 0.9 if a.t >= tel else 2.4, 0)
				tgt = _to_model(wp)
				var tang = Vector3(cos(ang), 0, -sin(ang)) * sign(a.a1 - a.a0)
				palm_n = model.global_transform.basis.xform_inv(tang).normalized()
				fdir = Vector3(0, -1, 0)
				if rate > 100.0:
					_hp[i] = tgt
				# grinding sparks of stone along the floor
				if a.t >= tel and a.t < tel + dur and randf() < 0.5:
					_dust_at(wp + Vector3(0, -0.6, 0), 0.4)
		"raise":
			var warn: float = a.warn
			if a.t < warn:
				tgt = SHOULDER_UP(i)
				rate = 2.6
				fdir = Vector3(sd * 0.2, 1.0, -0.3).normalized()
				palm_n = Vector3(0, 0, -1)
			elif a.t < warn + 0.2:
				var k = (a.t - warn) / 0.2
				_hp[i] = a.get("from", SHOULDER_UP(i)).linear_interpolate(rest, k * k)
				tgt = _hp[i]
				rate = 1000.0
				if a.t + delta >= warn + 0.2 and not a.get("hit", false):
					a.hit = true
					_impact(model.global_transform.xform(rest), 0.6)
			else:
				if a.t > warn + 1.2:
					hact[i] = {"k": "idle", "t": 0.0}
			if a.t < warn:
				a.from = _hp[i]
		"flail":
			var n = Vector3(sin(_t * 3.1 + i * 2.0), sin(_t * 2.3 + i), cos(_t * 2.7 + i * 1.3))
			tgt = rest + Vector3(sd * 2.0, 6.0, -2.0) + n * Vector3(4.0, 4.0, 3.0)
			rate = 5.0
			fdir = (n + Vector3(0, 0.3, 0)).normalized()
			palm_n = Vector3(0, 0, -1)
			if body_act == B.DEATH and body_t > 3.0:
				# its hands slide off the rim last
				tgt = rest + Vector3(0, -2.0 - (body_t - 3.0) * 3.0, 0)
	if rate < 100.0:
		_hp[i] = _hp[i].linear_interpolate(tgt, clamp(delta * rate, 0.0, 1.0))
	# the hand's frame: +Y along the fingers, -Z the palm
	var y = fdir.normalized()
	var z = -palm_n
	z = (z - y * y.dot(z))
	if z.length() < 0.05:
		z = Vector3(0, 0, 1) - y * y.z
	z = z.normalized()
	_hb[i] = _hb[i].slerp(Basis(y.cross(z), y, z).orthonormalized(), clamp(delta * (25.0 if rate > 100.0 else 6.0), 0.0, 1.0)) if _hb[i].determinant() > 0.5 else Basis(y.cross(z), y, z)


func SHOULDER_UP(i: int) -> Vector3:
	var sd = 1.0 if i == 0 else -1.0
	return UM.SHOULDER[i] + Vector3(sd * 3.0, 9.0, -3.5)


## Two bones from the shoulder to the hand, the elbow out and back; they stretch past their length.
func _pose_arm(i: int) -> void:
	var up: Spatial = _j["arm%d_u" % i]
	var fo: Spatial = _j["arm%d_f" % i]
	var hand: Spatial = _j["hand%d" % i]
	var sd = 1.0 if i == 0 else -1.0
	var bt: Transform = _j.body.transform
	var S: Vector3 = bt.xform(UM.SHOULDER[i])
	var W: Vector3 = _hp[i]
	var d = max(S.distance_to(W), 0.5)
	var s = max(1.0, d / ((UM.L_UP + UM.L_FORE) * 0.985))
	var l1 = UM.L_UP * s
	var l2 = UM.L_FORE * s
	var dir = (W - S) / d
	var a = (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h = sqrt(max(0.0, l1 * l1 - a * a))
	var pole = Vector3(sd, 0.6, 0.7)
	var pp = pole - dir * dir.dot(pole)
	if pp.length() < 0.01:
		pp = Vector3(0, 1, 0)
	var E = S + dir * a + pp.normalized() * h
	var bu = Models.basis_y(E - S)
	bu.y *= S.distance_to(E) / UM.L_UP
	up.transform = Transform(bu, S)
	var bf = Models.basis_y(W - E)
	bf.y *= E.distance_to(W) / UM.L_FORE
	fo.transform = Transform(bf, E)
	hand.transform = Transform(_hb[i], W)


func _head_step(delta: float) -> void:
	var head: Spatial = _j.head
	var hp = _j.body.transform.xform(UM.HEAD_PIVOT)
	head.translation = hp
	# the scale turns to whoever is looking (each machine: its own camera), so the numbers
	# always read the right way round; when it screams it turns on what it is screaming at
	var look = Vector3(0, UM.FACE_Y, -20)
	var cam = get_viewport().get_camera() if not world.headless else null
	if cam and body_act != B.SCREAM:
		look = _to_model(cam.global_transform.origin)
	elif focus != Vector3.ZERO:
		look = _to_model(focus + Vector3(0, 1.6, 0))
	var d = look - hp
	var yaw = clamp(atan2(-d.x, -d.z), -1.35, 1.35)
	_cam_yaw = lerp_angle(_cam_yaw, yaw, clamp(delta * 2.0, 0.0, 1.0))
	var jit = Vector3.ZERO
	var scr = body_act == B.SCREAM and body_t > inhale and body_t < inhale + 2.4
	if scr:
		jit = Vector3(rand_range(-1, 1), rand_range(-1, 1), rand_range(-1, 1)) * 0.03
	if _hurt > 0.0:
		jit += Vector3(rand_range(-1, 1), 0, rand_range(-1, 1)) * 0.05 * _hurt
	head.rotation = Vector3(0, _cam_yaw, 0) + jit
	# the beam: it weighs the six against the seven, all the time; a call tips it hard
	var goal = sin(_t * 0.55) * 0.1 + sin(_t * 1.7) * 0.03
	if body_act == B.CALL:
		goal = (-0.42 if call_n == 6 else 0.42) * smoothstep(0.1, 0.5, body_t)
	elif body_act == B.SCREAM and body_t < inhale:
		goal = sin(_t * 9.0) * 0.12 * smoothstep(0.0, inhale, body_t)
	elif scr:
		goal = sin(_t * 23.0) * 0.18
	elif body_act == B.STAGGER:
		goal = sin(_t * 4.0) * 0.3
	elif body_act == B.DEATH:
		goal = 0.55
	_tilt_v += ((goal - _tilt) * 26.0 - _tilt_v * 4.5) * delta
	_tilt += _tilt_v * delta
	_tilt_v -= _hurt * sin(_t * 31.0) * delta * 4.0
	var beam: Spatial = head.get_node("beam")
	beam.rotation = Vector3(0, 0, _tilt)
	# the pans hang straight down from the ends of the beam, swinging when it moves
	var turn = wrapf(_cam_yaw - _prev_yaw, -PI, PI) / max(delta, 0.001)
	_prev_yaw = _cam_yaw
	for i in 2:
		var sd = 1.0 if i == 0 else -1.0
		var pan: Spatial = head.get_node("pan%d" % i)
		pan.translation = beam.transform.xform(Vector3(sd * UM.BEAM_HALF, 0.38, 0))
		var push = Vector2(-_tilt_v * sd * 0.6, -turn * 0.25 * sd)
		if scr:
			push += Vector2(rand_range(-1, 1), rand_range(-1, 1)) * 2.5
		_swing_v[i] += (push - _swing[i] * 9.0 - _swing_v[i] * 1.2) * delta
		_swing[i] += _swing_v[i] * delta
		_swing[i] = _swing[i].limit_length(0.5)
		pan.rotation = Vector3(_swing[i].y, 0, _swing[i].x)
		# the number it calls burns
		var h = 1.0 if body_act == B.CALL and call_n == (6 if i == 0 else 7) and body_t < call_warn + 0.8 else 0.0
		if scr:
			h = 0.7
		_heat[i] = move_toward(_heat[i], h, delta * (3.0 if h > _heat[i] else 1.2))
		var num: Spatial = pan.get_node_or_null("num")
		if num:
			num.scale = Vector3.ONE * (1.0 + 0.12 * _heat[i])
			num.translation.y = -UM.CHAIN + 0.07 + (rand_range(-1, 1) * 0.04 * _heat[i] if _heat[i] > 0.3 else 0.0)
			# leaning out over its plate toward whoever looks up at it
			num.rotation.x = -0.22


func _fx_step(delta: float) -> void:
	_hurt = max(0.0, _hurt - delta * 2.2)
	_shield_hit = max(0.0, _shield_hit - delta * 1.5)
	_shield_k = move_toward(_shield_k, 1.0 if shield_on and body_act != B.DEATH else 0.0, delta * (0.6 if shield_on else 2.5))
	if _j.has("shield"):
		_j.shield.visible = (_shield_k > 0.01 or _shield_hit > 0.01) and model.visible
	if world.headless:
		return
	if _shield_mat:
		_shield_mat.set_shader_param("power", _shield_k + _shield_hit * 0.8)
		_shield_mat.set_shader_param("hit", _shield_hit)
	var scr = body_act == B.SCREAM and body_t > inhale and body_t < inhale + 2.4
	if _skin:
		_skin.set_shader_param("hurt", _hurt)
		if body_act == B.DEATH:
			_skin.set_shader_param("dying", smoothstep(1.0, 6.0, body_t))
	for i in _dmat.size():
		var m: ShaderMaterial = _dmat[i]
		m.set_shader_param("heat", _heat[i])
		m.set_shader_param("hurt", _hurt)
		m.set_shader_param("glow", 1.0 + (1.2 * smoothstep(0.0, inhale, body_t) if body_act == B.SCREAM and body_t < inhale else 0.0))
		if body_act == B.DEATH:
			m.set_shader_param("dying", smoothstep(1.0, 6.0, body_t))
	if _glow:
		var e = 1.4 + (3.0 if scr else 0.0) + _hurt * 2.0
		if body_act == B.DEATH:
			e *= 1.0 - smoothstep(1.0, 5.0, body_t)
		_glow.light_energy = e * (0.9 + 0.1 * sin(_t * 17.0))


# ------------------------------------------------------------------ effects
## A hand hit the floor: dust, a boom, the ground shakes under everyone near.
func _impact(at: Vector3, k := 1.0) -> void:
	_snd("ultra_slam", at + Vector3(0, 0.5, 0), world, 10.0 * k, rand_range(0.85, 1.0) * (1.2 if k < 1.0 else 1.0), 160.0)
	_dust_at(at, 2.5 * k)
	if world.player and not world.my_out:
		var d = world.player.global_transform.origin.distance_to(at)
		world.player.add_trauma(clamp(1.0 - d / 30.0, 0.0, 1.0) * 0.9 * k)


func _dust_at(at: Vector3, size: float) -> void:
	if world.headless:
		return
	var p = CPUParticles.new()
	p.one_shot = true
	p.emitting = true
	p.amount = int(clamp(24 * size, 6, 64))
	p.lifetime = 2.2
	p.explosiveness = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2 * size
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -3.0, 0)
	p.initial_velocity = 3.5 * size
	p.initial_velocity_random = 0.6
	p.damping = 2.0
	p.scale_amount = 2.5 * size
	p.scale_amount_random = 0.5
	var q = QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m = SpatialMaterial.new()
	m.flags_transparent = true
	m.flags_unshaded = true
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.albedo_texture = load("res://textures/lamp_round.png")
	m.albedo_color = Color(0.5, 0.5, 0.5, 0.35)
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	world.add_child(p)
	p.global_transform.origin = at
	get_tree().create_timer(2.6).connect("timeout", p, "queue_free")
