extends Enemy
## 67 — multidimensional. It drifts straight through the walls of its maze (nothing in there
## stops it), its two hands weighing six against seven. When it calls a number it lifts that
## hand and the maze answers (level_3.gd): the gates with that number sink into the floor, the
## others rise. Then it is somewhere else.
## Slower than you in a straight line, but it never needs the corridors.
## It is flat, like the image it came out of, and the card always turns to face you.

enum S { DRIFT, CHASE, HUNT, CALL }
var state = S.DRIFT
var timer = 0.0
var target = Vector3.ZERO
var dormant = 0.0
var call_n = 0             # the number it is calling (6 / 7), 0: none
var call_t = -1.0          # seconds into the call gesture
var _t = 0.0
var _j = {}
var _base = {}
var _glitch = 0.0
var _glitch_t = 3.0


func _init() -> void:
	death_msg = "67 took you somewhere between six and seven.\nthe walls were never the problem."
	chase_sound = "chase_67"
	catch_dist = 1.4
	light_energy = 0.0
	floats = true
	kill_hit = 0.32
	kill_len = 1.0
	kill_force = 3.0
	kill_lift = 9.0


func _after_setup() -> void:
	collision_mask = 0          # walls do not exist for it
	top_light.visible = false
	hover_y = global_transform.origin.y
	target = global_transform.origin
	for n in ["head", "handL", "handR"]:
		var j = model.find_node(n, true, false)
		if j:
			_j[n] = j
			_base[n] = j.translation


func think(delta: float) -> void:
	timer -= delta
	if dormant > 0.0:
		dormant -= delta
		return
	match state:
		S.CALL:
			return
		S.DRIFT:
			if _drift(target, 1.2, delta) or timer <= 0.0:
				target = random_target()
				timer = 14.0
			if dist_to_player() < 9.0:
				set_state(S.CHASE)
		S.CHASE:
			_drift(target_pos(), 2.4, delta)
			if dist_to_player() > 13.0:
				set_state(S.DRIFT)
		S.HUNT:
			_drift(target_pos(), 3.0, delta)
			if timer <= 0.0:
				set_state(S.DRIFT)


## Straight at it, through whatever is in the way.
func _drift(to: Vector3, spd: float, delta: float) -> bool:
	var d = Vector3(to.x - global_transform.origin.x, 0, to.z - global_transform.origin.z)
	if d.length() < 0.4:
		return true
	want = d.normalized() * spd
	face_dir(d, delta, 3.0)
	return false


func set_state(s) -> void:
	state = s
	aggro_target = 1.0 if s == S.CHASE or s == S.HUNT else 0.0
	if s != S.HUNT:
		hunt_id = -1
	match s:
		S.DRIFT:
			chase_id = -1
			target = random_target()
			timer = 14.0
		S.CHASE:
			alert()
			chase_id = _nearest_id()
		S.HUNT:
			alert()
			timer = 14.0


func _nearest_id() -> int:
	var best = 1e9
	var id = -1
	for t in world.targets(sector):
		var d = _flat(t.pos, global_transform.origin)
		if d < best:
			best = d
			id = t.id
	return id


func is_threat() -> bool:
	return state == S.CHASE or state == S.HUNT


func check_catch() -> void:
	if dormant <= 0.0 and state != S.CALL and call_t < 0.0:
		.check_catch()


func net_state() -> int:
	return state


func apply_net_state(s: int) -> void:
	state = s
	aggro_target = 1.0 if s == S.CHASE or s == S.HUNT else 0.0
	if s == S.CHASE or s == S.HUNT:
		alert()


## Every machine: it calls n (6 / 7) and lifts that hand. The server holds it still meanwhile.
func do_call(n: int) -> void:
	call_n = n
	call_t = 0.0
	if not puppet:
		state = S.CALL
		want = Vector3.ZERO


## Every machine: it is somewhere else now (no gliding there: it is just there).
func relocate(pos: Vector3) -> void:
	global_transform.origin = pos
	hover_y = pos.y
	_net_pos = pos
	_net_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	_glitch = 0.3
	if not puppet:
		set_state(S.DRIFT)


# ------------------------------------------------------------------ body language
func _animate(delta: float, _spd: float) -> void:
	_t += delta
	var head: Spatial = _j.get("head")
	var hl: Spatial = _j.get("handL")
	var hr: Spatial = _j.get("handR")
	if call_t >= 0.0:
		call_t += delta
		if call_t > 1.9:
			call_t = -1.0
			call_n = 0
	if head == null or hl == null or hr == null:
		return
	model.translation = Vector3(0, sin(_t * 1.3) * 0.07, 0)
	# flat: the card turns to whoever is looking (each machine to its own camera), except
	# while it is taking someone: then it faces them
	var cam = get_viewport().get_camera()
	var yaw = 0.0
	if cam and kill_t < 0.0:
		var to = cam.global_transform.origin - global_transform.origin
		yaw = wrapf(atan2(-to.x, -to.z) - rotation.y, -PI, PI)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, clamp(delta * 12.0, 0.0, 1.0))
	# the hands weigh six against seven, faster when it is after you
	var w = sin(_t * (2.2 + 2.6 * aggro))
	var c = 0.0
	if call_t >= 0.0:
		c = smoothstep(0.0, 0.35, call_t) * (1.0 - smoothstep(1.35, 1.9, call_t))
	var lift6 = c * (1.0 if call_n == 6 else -0.3)
	var lift7 = c * (1.0 if call_n == 7 else -0.3)
	hl.translation = _base.handL + Vector3(0, w * 0.16 * (1.0 - c) + lift6, 0)
	hr.translation = _base.handR + Vector3(0, -w * 0.16 * (1.0 - c) + lift7, 0)
	hl.rotation = Vector3(0, 0, w * 0.12 * (1.0 - c) + (0.35 if call_n == 6 else 0.0) * c)
	hr.rotation = Vector3(0, 0, w * 0.12 * (1.0 - c) - (0.35 if call_n == 7 else 0.0) * c)
	# it throws its head back when it calls
	head.rotation = Vector3(-0.12 * c, 0, sin(_t * 0.9) * 0.04 + sin(_t * 23.0) * 0.03 * c)
	head.scale = Vector3.ONE * (1.0 + 0.12 * c)
	for side in [[hl, 6], [hr, 7]]:
		var num = side[0].get_node_or_null("num")
		if num:
			var on = c if call_n == side[1] else 0.0
			num.modulate = Color(1.5, 1.5, 1.5)
			num.scale = Vector3.ONE * (1.0 + 0.9 * on)
	# now and then it is not quite here
	_glitch_t -= delta
	if _glitch_t <= 0.0:
		_glitch_t = rand_range(1.5, 5.0) * (0.4 if aggro > 0.5 else 1.0)
		_glitch = 0.12
	if _glitch > 0.0:
		_glitch -= delta
		model.translation += Vector3(rand_range(-0.25, 0.25), rand_range(-0.08, 0.08), rand_range(-0.25, 0.25))
		head.rotation.z += rand_range(-0.3, 0.3)
	if kill_t >= 0.0:
		# both hands come together on you
		var reach = smoothstep(0.0, kill_hit, kill_t) * (1.0 - smoothstep(0.6, kill_len, kill_t))
		for n in ["handL", "handR"]:
			var b: Vector3 = _base[n]
			var h: Spatial = _j[n]
			h.translation = h.translation.linear_interpolate(Vector3(b.x * 0.3, b.y + 0.15, b.z - 1.1), reach)
