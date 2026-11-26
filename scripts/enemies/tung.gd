extends Enemy
## TUNG TUNG TUNG SAHUR — wanders, calls, and hunts the ones who stay quiet. (Godot 3)
## Procedural body language:
## - legs: two-bone IK with planted feet, heel-strike knocks, toe lift in swing
## - body: inverted-pendulum bob, weight shift + lean onto the stance leg, hip twist, forward lean when fast
## - arms: counter-swing with lagging elbows; the bat swings like a pendulum
## - eyes: track you with saccades; he only blinks when you aren't looking
## - idle: breathing, slow weight shifts; close to you he raises the bat and waits

enum S { WANDER, CHASE, PASSIVE, HUNT }
var state = S.WANDER
var timer = 0.0
var target = Vector3.ZERO
var lost = 0.0
var swing = 0.0
var speed_override = -1.0

const THIGH := 0.3
const SHIN := 0.3
const ANKLE_H := 0.045

var _j = {}
var _ph = 0.0
var _spd = 0.0
var _prev_yaw = 0.0
var _t = 0.0
var _stance = [true, true]
var _arm_lag = [0.0, 0.0]
var _arm_vel = [0.0, 0.0]
var _bat_a = 0.0
var _bat_v = 0.0
var _prev_shoulder_r = 0.0
var _sacc = Vector2.ZERO
var _sacc_t = 0.0
var _blink_t = 3.0
var _blink = 0.0
var _lid_base = {}
var _shift = 0.0
var _shift_t = 0.0
var _bat_base = Basis()
var _bat_up = Basis()


func _init() -> void:
	death_msg = "tung tung tung sahur found you.\nyou should have answered."
	chase_sound = "chase_tung"
	catch_dist = 1.3
	light_energy = 0.35


func _after_setup() -> void:
	for n in ["body", "legL", "legR", "kneeL", "kneeR", "ankleL", "ankleR", "armL", "armR", "elbowL", "elbowR", "handR", "bat", "eyeL", "eyeR", "lidL", "lidR"]:
		_j[n] = model.find_node(n, true, false)
	for n in ["lidL", "lidR"]:
		if _j[n]:
			_lid_base[n] = _j[n].rotation
	_prev_yaw = rotation.y
	_bat_base = TungModel.basis_y(Vector3(0.32, -0.94, -0.12).normalized())
	_bat_up = TungModel.basis_y(Vector3(0.1, 0.6, 0.8).normalized())


func think(delta: float) -> void:
	timer -= delta
	match state:
		S.WANDER:
			if move_to(target, 1.6, delta) or timer <= 0.0:
				target = random_target()
				timer = 20.0
			if dist_to_player() < 8.0 and sees_player(8.0):
				set_state(S.CHASE)
		S.CHASE:
			move_to(target_pos(), 3.4, delta)
			lost = lost + delta if not sees_player(14.0) else 0.0
			if lost > 4.0:
				set_state(S.WANDER)
		S.PASSIVE:
			var sp = speed_override if speed_override > 0.0 else 1.4
			if move_to(target, sp, delta) or timer <= 0.0:
				if timer <= 0.0:
					set_state(S.WANDER)
				else:
					target = random_target()
		S.HUNT:
			move_to(target_pos(), 3.9, delta)
			if timer <= 0.0:
				set_state(S.WANDER)


# ------------------------------------------------------------------ body language
func _animate(delta: float, spd: float) -> void:
	_t += delta
	var b: Spatial = _j.get("body")
	if b == null:
		return
	var yaw_rate = abs(wrapf(rotation.y - _prev_yaw, -PI, PI)) / max(delta, 0.0001)
	_prev_yaw = rotation.y
	var eff: float = max(spd, min(yaw_rate * 0.35, 0.8))
	_spd = lerp(_spd, eff, clamp(delta * 6.0, 0.0, 1.0))
	var v = _spd
	var stride: float = clamp(0.75 + v * 0.22, 0.8, 1.65)
	var w: float = clamp(v / 1.1, 0.0, 1.0)
	var run: float = clamp((v - 2.3) / 1.4, 0.0, 1.0)
	if v > 0.05:
		_ph = fmod(_ph + v / stride * TAU * delta, TAU)
	var ph = _ph
	_shift_t -= delta
	if _shift_t <= 0.0:
		_shift_t = rand_range(2.5, 6.0)
		_shift = rand_range(-1.0, 1.0)
	var idle = 1.0 - w
	var breathe = sin(_t * 1.7)
	var bob = (0.5 - 0.5 * cos(2.0 * ph)) * (0.03 + 0.03 * run) * w
	var sway = -sin(ph) * (0.035 + 0.02 * run) * w + _shift * 0.02 * idle
	var roll = sin(ph) * deg2rad(3.2 + 2.0 * run) * w + _shift * deg2rad(1.2) * idle
	var twist = sin(ph) * deg2rad(5.0) * w
	var lean = deg2rad(2.5 + 9.0 * run) * w + swing * deg2rad(4.0)
	var base_y = TungModel.LEGS - 0.035
	b.translation = Vector3(sway, base_y + bob + breathe * 0.004 * idle, 0)
	b.rotation = Vector3(-lean + breathe * deg2rad(0.6) * idle, twist, roll)
	b.scale = Vector3(1.0 - breathe * 0.003 * idle, 1.0 + breathe * 0.006 * idle, 1.0 - breathe * 0.003 * idle)
	# Legs: planted feet + two-bone IK
	for side in [0, 1]:
		var leg: Spatial = _j["legL" if side == 0 else "legR"]
		var knee: Spatial = _j["kneeL" if side == 0 else "kneeR"]
		var ankle: Spatial = _j["ankleL" if side == 0 else "ankleR"]
		var p = fmod(ph + (0.0 if side == 0 else PI), TAU)
		var stance = p < PI
		var u = p / PI if stance else (p - PI) / PI
		var f = 0.0
		var lift = 0.0
		if stance:
			f = lerp(stride * 0.25, -stride * 0.25, u)
		else:
			f = -stride * 0.25 + stride * 0.5 * (0.5 - 0.5 * cos(PI * u))
			lift = sin(PI * u) * (0.06 + 0.09 * run)
		f *= w
		lift *= w
		var sx = -0.12 if side == 0 else 0.12
		leg.translation = Vector3(sx + sway * 0.6, base_y + 0.02 + bob, 0)
		var down = leg.translation.y - ANKLE_H - lift
		var d: float = clamp(sqrt(f * f + down * down), 0.05, THIGH + SHIN - 0.002)
		var interior = acos(clamp((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0))
		var alpha = acos(clamp((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0))
		var hip = atan2(f, down) + alpha
		var bend = PI - interior
		leg.rotation = Vector3(hip, 0, -roll * 0.5)
		knee.rotation.x = -bend
		var toe = 0.0
		if not stance:
			toe = -sin(PI * u) * deg2rad(18.0) * w
		ankle.rotation.x = -(hip - bend) + toe
		if stance and not _stance[side] and w > 0.3:
			var at = leg.global_transform.origin - Vector3(0, leg.translation.y, 0)
			Audio.play_at("tung", at, world, -14.0 + 6.0 * run, rand_range(0.62, 0.72), 45.0)
			if dist_to_player() < 7.0:
				world.player.add_trauma(0.04 + 0.08 * run)
		_stance[side] = stance
	# Arms: counter-swing, elbows lag
	for side in [0, 1]:
		var arm: Spatial = _j["armL" if side == 0 else "armR"]
		var elbow: Spatial = _j["elbowL" if side == 0 else "elbowR"]
		var amp = (0.32 + 0.55 * run) * w * (0.55 if side == 1 else 1.0)
		var shv = (-cos(ph) if side == 0 else cos(ph)) * amp + idle * sin(_t * 0.9 + side) * 0.03
		var raise = swing if side == 1 else swing * 0.25
		arm.rotation = Vector3(lerp(shv, 2.5, raise), 0, (0.05 if side == 0 else -0.05) * w + (-0.2 if side == 1 else 0.0) * raise)
		_arm_vel[side] += ((shv - _arm_lag[side]) * 60.0 - _arm_vel[side] * 9.0) * delta
		_arm_lag[side] += _arm_vel[side] * delta
		var flex = 0.25 + 0.2 * w + 0.7 * run + max(0.0, _arm_lag[side] - shv) * 1.2 + (0.25 if side == 1 else 0.0)
		elbow.rotation.x = lerp(flex, 1.3, raise)
	# The bat: a heavy pendulum hanging from the fist
	var arm_r: Spatial = _j["armR"]
	var sv = (arm_r.rotation.x - _prev_shoulder_r) / max(delta, 0.0001)
	_prev_shoulder_r = arm_r.rotation.x
	_bat_v += ((-sv * 0.06 - _bat_a) * 40.0 - _bat_v * 5.0) * delta
	_bat_a += _bat_v * delta
	var bat: Spatial = _j.get("bat")
	if bat:
		var bb = _bat_base.slerp(_bat_up, swing)
		bat.transform.basis = bb.rotated(Vector3.RIGHT, _bat_a + swing * sin(_t * 9.0) * 0.06)
	if kill_t >= 0.0:
		_kill_pose(b)
	# Eyes: track you with saccades. Blink only when you look away.
	if world.player == null:
		return
	var cam: Camera = world.player.cam
	_sacc_t -= delta
	if _sacc_t <= 0.0:
		_sacc_t = rand_range(0.25, 1.4)
		_sacc = Vector2(rand_range(-0.05, 0.05), rand_range(-0.035, 0.035))
	for n in ["eyeL", "eyeR"]:
		var e: Spatial = _j.get(n)
		if e == null:
			continue
		var lp: Vector3 = (e.get_parent() as Spatial).to_local(cam.global_transform.origin) - e.translation
		var yaw: float = clamp(atan2(-lp.x, -lp.z), -0.7, 0.7) + _sacc.x
		var pitch: float = clamp(atan2(lp.y, Vector2(lp.x, lp.z).length()), -0.5, 0.5) + _sacc.y
		e.rotation = e.rotation.linear_interpolate(Vector3(pitch, yaw, 0), clamp(delta * 18.0, 0.0, 1.0))
	_blink_t -= delta
	var watched = seen_by_player(35.0, 40.0)
	if _blink_t <= 0.0 and not watched:
		_blink_t = rand_range(2.0, 6.0)
		_blink = 1.0
	_blink = max(0.0, _blink - delta / 0.18)
	var close = sin(PI * (1.0 - _blink)) if _blink > 0.0 else 0.0
	var squint = swing * 0.25
	for n in ["lidL", "lidR"]:
		var l: Spatial = _j.get(n)
		if l and _lid_base.has(n):
			var r0: Vector3 = _lid_base[n]
			l.rotation = Vector3(lerp(r0.x, deg2rad(-88.0), max(close, squint)), r0.y, r0.z)
	var near = dist_to_player() < 3.6 and (state == S.HUNT or state == S.CHASE)
	swing = move_toward(swing, 1.0 if near else 0.0, delta * 2.2)


## The kill: the bat goes up over the right shoulder, then comes down and across, hard,
## his whole body turning into it. Then he settles back.
func _kill_pose(b: Spatial) -> void:
	var t = kill_t
	var wind = smoothstep(0.0, 0.3, t)
	var strike = smoothstep(0.3, kill_hit + 0.02, t)
	var k = 1.0 - smoothstep(0.7, kill_len, t)
	var arm: Spatial = _j["armR"]
	var el: Spatial = _j["elbowR"]
	var arm_l: Spatial = _j["armL"]
	var ax = lerp(lerp(arm.rotation.x, 3.3, wind), 0.8, strike)
	var az = lerp(lerp(arm.rotation.z, -0.6, wind), 0.5, strike)
	arm.rotation = Vector3(lerp(arm.rotation.x, ax, k), 0, lerp(arm.rotation.z, az, k))
	el.rotation.x = lerp(el.rotation.x, lerp(lerp(el.rotation.x, 1.6, wind), 0.08, strike), k)
	arm_l.rotation.x = lerp(arm_l.rotation.x, lerp(0.2, -0.7, strike), k)
	var bat: Spatial = _j.get("bat")
	if bat:
		bat.transform.basis = bat.transform.basis.slerp(Basis(Vector3.RIGHT, -0.25), k)
	b.rotation.y += lerp(lerp(0.0, -0.55, wind), 0.6, strike) * k
	b.rotation.x += lerp(lerp(0.0, 0.14, wind), -0.3, strike) * k


func net_state() -> int:
	return state


## Client: the server's tung changed state. Same sounds and music, no decisions.
func apply_net_state(s: int) -> void:
	state = s
	aggro_target = 1.0 if s == S.CHASE or s == S.HUNT else 0.0
	if s == S.CHASE or s == S.HUNT:
		alert()
	if s == S.CHASE:
		Audio.play_at("tung", global_transform.origin, world, 4.0, 0.6, 80.0)


func set_state(s) -> void:
	state = s
	lost = 0.0
	aggro_target = 1.0 if s == S.CHASE or s == S.HUNT else 0.0
	if s != S.HUNT:
		hunt_id = -1
	match s:
		S.WANDER:
			target = random_target()
			timer = 20.0
		S.PASSIVE:
			target = random_target()
			timer = 14.0
		S.HUNT:
			timer = 16.0
			alert()
		S.CHASE:
			alert()
			timer = 0.0
			Audio.play_at("tung", global_transform.origin, world, 4.0, 0.6, 80.0)


func is_threat() -> bool:
	return state == S.CHASE or state == S.HUNT


func check_catch() -> void:
	if state != S.PASSIVE:
		.check_catch()
