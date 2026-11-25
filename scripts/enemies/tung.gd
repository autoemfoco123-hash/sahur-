extends Enemy
## TUNG TUNG TUNG SAHUR — wanders, calls, and hunts the ones who stay quiet.
## Procedural body language:
## - legs: two-bone IK with planted feet (no sliding), heel-strike knocks, toe lift in swing
## - body: inverted-pendulum bob, weight shift + lean toward the stance leg, hip twist, forward lean when fast
## - arms: counter-swing with lagging elbows; the bat arm carries weight, the bat swings like a pendulum
## - eyes: track you with tiny saccades; he only blinks when you aren't looking at him
## - idle: breathing, slow weight shifts; close to you he raises the bat and waits

enum S { WANDER, CHASE, PASSIVE, HUNT }
var state := S.WANDER
var timer := 0.0
var target := Vector3.ZERO
var lost := 0.0
var swing := 0.0
var speed_override := -1.0

const THIGH := 0.3
const SHIN := 0.3
const ANKLE_H := 0.045

var _j := {}
var _ph := 0.0
var _spd := 0.0
var _prev_yaw := 0.0
var _t := 0.0
var _stance := [true, true]
var _arm_lag := [0.0, 0.0]
var _arm_vel := [0.0, 0.0]
var _bat_a := 0.0
var _bat_v := 0.0
var _prev_shoulder_r := 0.0
var _sacc := Vector2.ZERO
var _sacc_t := 0.0
var _blink_t := 3.0
var _blink := 0.0
var _lid_base := {}
var _shift := 0.0
var _shift_t := 0.0


func _init() -> void:
	death_msg = "tung tung tung sahur found you.\nyou should have answered."
	step_sound = ""
	chase_sound = "chase_tung"
	catch_dist = 1.3
	light_energy = 0.7


func setup(w: Node, id: String, pos: Vector3, is_hostile := true) -> Enemy:
	super.setup(w, id, pos, is_hostile)
	for n in ["body", "legL", "legR", "kneeL", "kneeR", "ankleL", "ankleR", "armL", "armR", "elbowL", "elbowR", "handR", "bat", "eyeL", "eyeR", "lidL", "lidR"]:
		_j[n] = model.find_child(n, true, false)
	for n in ["lidL", "lidR"]:
		if _j[n]:
			_lid_base[n] = (_j[n] as Node3D).rotation
	_prev_yaw = rotation.y
	return self


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
			move_to(world.player.global_position, 3.4, delta)
			lost = lost + delta if not sees_player(14.0) else 0.0
			if lost > 4.0:
				set_state(S.WANDER)
		S.PASSIVE:
			if move_to(target, speed_override if speed_override > 0.0 else 1.4, delta) or timer <= 0.0:
				if timer <= 0.0:
					set_state(S.WANDER)
				else:
					target = random_target()
		S.HUNT:
			move_to(world.player.global_position, 3.9, delta)
			if timer <= 0.0:
				set_state(S.WANDER)


# ------------------------------------------------------------------ body language
func _animate(delta: float, spd: float) -> void:
	_t += delta
	var b: Node3D = _j.get("body")
	if b == null:
		return
	# Turning in place still makes him shuffle his feet.
	var yaw_rate := absf(wrapf(rotation.y - _prev_yaw, -PI, PI)) / maxf(delta, 0.0001)
	_prev_yaw = rotation.y
	var eff := maxf(spd, minf(yaw_rate * 0.35, 0.8))
	_spd = lerpf(_spd, eff, clampf(delta * 6.0, 0.0, 1.0))
	var v := _spd
	var stride := clampf(0.75 + v * 0.22, 0.8, 1.65)    # one full cycle = two steps
	var w := clampf(v / 1.1, 0.0, 1.0)                   # walking weight
	var run := clampf((v - 2.3) / 1.4, 0.0, 1.0)        # running weight
	if v > 0.05:
		_ph = fmod(_ph + v / stride * TAU * delta, TAU)
	var ph := _ph
	# Idle weight shifts
	_shift_t -= delta
	if _shift_t <= 0.0:
		_shift_t = randf_range(2.5, 6.0)
		_shift = randf_range(-1.0, 1.0)
	var idle := 1.0 - w
	var breathe := sin(_t * 1.7)
	# Body: inverted pendulum (highest at mid-stance), lean onto the stance leg, twist, lean forward
	var bob := (0.5 - 0.5 * cos(2.0 * ph)) * (0.03 + 0.03 * run) * w
	var sway := -sin(ph) * (0.035 + 0.02 * run) * w + _shift * 0.02 * idle
	var roll := sin(ph) * deg_to_rad(3.2 + 2.0 * run) * w + _shift * deg_to_rad(1.2) * idle
	var twist := sin(ph) * deg_to_rad(5.0) * w
	var lean := deg_to_rad(2.5 + 9.0 * run) * w + swing * deg_to_rad(4.0)
	var base_y := TungModel.LEGS - 0.035
	b.position = Vector3(sway, base_y + bob + breathe * 0.004 * idle, 0)
	b.rotation = Vector3(-lean + breathe * deg_to_rad(0.6) * idle, twist, roll)
	b.scale = Vector3(1.0 - breathe * 0.003 * idle, 1.0 + breathe * 0.006 * idle, 1.0 - breathe * 0.003 * idle)
	# Legs: planted feet + 2-bone IK
	for side in [0, 1]:
		var leg: Node3D = _j["legL" if side == 0 else "legR"]
		var knee: Node3D = _j["kneeL" if side == 0 else "kneeR"]
		var ankle: Node3D = _j["ankleL" if side == 0 else "ankleR"]
		var p := fmod(ph + (0.0 if side == 0 else PI), TAU)
		var stance := p < PI
		var u := p / PI if stance else (p - PI) / PI
		var f := 0.0
		var lift := 0.0
		if stance:
			f = lerpf(stride * 0.25, -stride * 0.25, u)
		else:
			f = -stride * 0.25 + stride * 0.5 * (0.5 - 0.5 * cos(PI * u))
			lift = sin(PI * u) * (0.06 + 0.09 * run)
		f *= w
		lift *= w
		var sx := -0.12 if side == 0 else 0.12
		leg.position = Vector3(sx + sway * 0.6, base_y + 0.02 + bob, 0)
		var down := leg.position.y - ANKLE_H - lift
		var d := clampf(sqrt(f * f + down * down), 0.05, THIGH + SHIN - 0.002)
		var interior := acos(clampf((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0))
		var alpha := acos(clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0))
		var hip := atan2(f, down) + alpha
		var bend := PI - interior
		leg.rotation = Vector3(hip, 0, -roll * 0.5)
		knee.rotation.x = -bend
		var toe := -sin(PI * u) * deg_to_rad(18.0) * w if not stance else 0.0
		ankle.rotation.x = -(hip - bend) + toe
		# Heel strike: the log knocks on the floor
		if stance and not _stance[side] and w > 0.3:
			var at := leg.global_position + Vector3(0, -leg.position.y, 0)
			Audio.play_at("tung", at, world, -14.0 + 6.0 * run, randf_range(0.62, 0.72), 45.0)
			if dist_to_player() < 7.0:
				world.player.add_trauma(0.04 + 0.08 * run)
		_stance[side] = stance
	# Arms: counter-swing, elbows lag behind the shoulders
	for side in [0, 1]:
		var arm: Node3D = _j["armL" if side == 0 else "armR"]
		var elbow: Node3D = _j["elbowL" if side == 0 else "elbowR"]
		var amp := (0.32 + 0.55 * run) * w * (0.55 if side == 1 else 1.0)
		var sh := (-cos(ph) if side == 0 else cos(ph)) * amp + idle * sin(_t * 0.9 + side) * 0.03
		var raise := swing if side == 1 else swing * 0.25
		arm.rotation = Vector3(lerpf(sh, 2.5, raise), 0, (0.05 if side == 0 else -0.05) * w + (-0.2 if side == 1 else 0.0) * raise)
		var tgt := sh
		_arm_vel[side] += ((tgt - _arm_lag[side]) * 60.0 - _arm_vel[side] * 9.0) * delta
		_arm_lag[side] += _arm_vel[side] * delta
		var flex := 0.25 + 0.2 * w + 0.7 * run + maxf(0.0, _arm_lag[side] - sh) * 1.2 + (0.25 if side == 1 else 0.0)
		elbow.rotation.x = lerpf(flex, 1.3, raise)
	# The bat: a heavy pendulum hanging from the fist
	var arm_r: Node3D = _j["armR"]
	var sv := (arm_r.rotation.x - _prev_shoulder_r) / maxf(delta, 0.0001)
	_prev_shoulder_r = arm_r.rotation.x
	_bat_v += ((-sv * 0.06 - _bat_a) * 40.0 - _bat_v * 5.0) * delta
	_bat_a += _bat_v * delta
	var bat: Node3D = _j.get("bat")
	if bat:
		bat.rotation.x = 0.0
		var base := TungModel._basis_y(Vector3(0.32, -0.94, -0.12).normalized())
		var raised := TungModel._basis_y(Vector3(0.1, 0.6, 0.8).normalized())
		bat.basis = base.slerp(raised, swing).rotated(Vector3.RIGHT, _bat_a + swing * sin(_t * 9.0) * 0.06)
	# Eyes: track you, with saccades. Blink only when you look away.
	var cam: Camera3D = world.player.cam
	_sacc_t -= delta
	if _sacc_t <= 0.0:
		_sacc_t = randf_range(0.25, 1.4)
		_sacc = Vector2(randf_range(-0.05, 0.05), randf_range(-0.035, 0.035))
	for n in ["eyeL", "eyeR"]:
		var e: Node3D = _j.get(n)
		if e == null:
			continue
		var lp: Vector3 = (e.get_parent() as Node3D).to_local(cam.global_position) - e.position
		var yaw := clampf(atan2(-lp.x, -lp.z), -0.7, 0.7) + _sacc.x
		var pitch := clampf(atan2(lp.y, Vector2(lp.x, lp.z).length()), -0.5, 0.5) + _sacc.y
		e.rotation = e.rotation.lerp(Vector3(pitch, yaw, 0), clampf(delta * 18.0, 0.0, 1.0))
	_blink_t -= delta
	var watched := seen_by_player(35.0, 40.0)
	if _blink_t <= 0.0 and not watched:
		_blink_t = randf_range(2.0, 6.0)
		_blink = 1.0
	_blink = maxf(0.0, _blink - delta / 0.18)
	var close := sin(PI * (1.0 - _blink)) if _blink > 0.0 else 0.0
	var squint := swing * 0.25
	for n in ["lidL", "lidR"]:
		var l: Node3D = _j.get(n)
		if l and _lid_base.has(n):
			var r0: Vector3 = _lid_base[n]
			l.rotation = Vector3(lerpf(r0.x, deg_to_rad(-88.0), maxf(close, squint)), r0.y, r0.z)
	# Close to you while hunting: the bat goes up, and stays up.
	var near := dist_to_player() < 3.6 and (state == S.HUNT or state == S.CHASE)
	swing = move_toward(swing, 1.0 if near else 0.0, delta * 2.2)


func set_state(s: S) -> void:
	state = s
	lost = 0.0
	aggro_target = 1.0 if s == S.CHASE or s == S.HUNT else 0.0
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
			Audio.play_at("tung", global_position, world, 4.0, 0.6, 80.0)


func is_threat() -> bool:
	return state == S.CHASE or state == S.HUNT


func check_catch() -> void:
	if state != S.PASSIVE:
		super.check_catch()
