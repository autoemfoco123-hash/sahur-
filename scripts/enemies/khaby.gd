extends Enemy
## THE KHABY LAME MECHANISM: friendly. It stands on its table in the middle of the field and
## its chain-driven arms go round and round, stopping palms-up at the top for a moment:
## "it's that simple". It never moves, never hunts, never drains you. It only ever explains.

const KM = preload("res://scripts/khaby_model.gd")
const POSE = 1.35          # rod angle with the palms up, in front of the chest
const SPIN = 1.7           # seconds for one turn
const HOLD = 0.9           # seconds it holds the pose

var presenting = 0.0       # 0..1: holds the pose (cutscene), instead of spinning
var fear = 0.0             # 0..1: terrified (the monologue): no more spinning, it shakes
var talk = 0.0             # seconds of speech left (it nods along as it talks)
var gaze_at = Vector3.INF  # what it looks at (the level points it: you, the sky, the ground...)
var flail = 0.0            # 0..1: falling: the arms spin wildly
var _arm_a = POSE
var _look = Vector2.ZERO
var _t = 0.0
var _turned = false
var _arms = []
var _head: Spatial


func _init() -> void:
	death_msg = "the mechanism explained it to you."
	catch_dist = 0.0
	light_energy = 0.0
	drains = false


func _after_setup() -> void:
	top_light.visible = false
	for n in ["armL", "armR"]:
		var a = model.find_node(n, true, false)
		if a:
			_arms.append(a)
	_head = model.find_node("head", true, false)


func think(_delta: float) -> void:
	want = Vector3.ZERO


func is_threat() -> bool:
	return false


func _animate(delta: float, _spd: float) -> void:
	_t += delta
	var cycle = SPIN + HOLD
	var u = fmod(_t, cycle)
	var a = POSE
	if u < SPIN:
		var k = u / SPIN
		k = k * k * (3.0 - 2.0 * k)
		a = POSE + TAU * k
		if not _turned and world.player and not world.headless and fear <= 0.0:
			_turned = true
			Audio.play_at("khaby_servo", global_transform.origin + Vector3(0, 1.9, 0), world, -2.0, rand_range(0.96, 1.04), 30.0)
	else:
		_turned = false
		# the servo settles: a small shiver in the pose
		a = POSE + sin((u - SPIN) * 38.0) * 0.03 * exp(-(u - SPIN) * 6.0)
	a = lerp(a, POSE + sin(_t * 1.3) * 0.05, presenting)
	if fear > 0.0:
		# terrified: the arms hang half raised and shake, or come up (hands up) when it says so
		var shake = (sin(_t * 31.0) * 0.045 + sin(_t * 47.0 + 1.3) * 0.03) * (0.6 + 0.4 * sin(_t * 2.3))
		var held = lerp(POSE - 1.15, POSE, presenting) + shake
		_arm_a = lerp(_arm_a, held, clamp(delta * 6.0, 0.0, 1.0))
		a = lerp(a, _arm_a, fear)
	if flail > 0.0:
		a = lerp(a, _t * 13.0, flail)
	if talk > 0.0:
		talk -= delta
	for i in _arms.size():
		_arms[i].rotation.x = a + (sin(_t * 23.0 + i * 2.1) * 0.05 * fear if flail <= 0.0 else float(i) * 1.7 * flail)
	if _head:
		var r = Vector3(sin(_t * 0.7) * 0.03 + presenting * 0.06, sin(_t * 0.45) * 0.05, 0)
		if gaze_at != Vector3.INF and fear > 0.0:
			var par: Spatial = _head.get_parent()
			var lp = par.global_transform.xform_inv(gaze_at) - _head.translation
			var want = Vector2(clamp(atan2(lp.y, Vector2(lp.x, lp.z).length()), -0.55, 0.6), clamp(atan2(-lp.x, -lp.z), -1.1, 1.1))
			_look = _look.linear_interpolate(want, clamp(delta * 5.0, 0.0, 1.0))
			# frightened: quick little jerks of the head, a tremor, nodding along while it talks
			var jerk = sin(_t * 9.0) * sin(_t * 3.7) * 0.05
			var nod = sin(_t * 11.0) * 0.035 * (1.0 if talk > 0.0 else 0.0)
			r = r.linear_interpolate(Vector3(_look.x + nod + sin(_t * 41.0) * 0.012, _look.y + jerk + sin(_t * 37.0) * 0.015, sin(_t * 5.0) * 0.03), fear)
		_head.rotation = r
	if fear > 0.0 and flail <= 0.0:
		model.translation = Vector3(sin(_t * 43.0) * 0.004, abs(sin(_t * 29.0)) * 0.003, sin(_t * 39.0) * 0.004) * fear
