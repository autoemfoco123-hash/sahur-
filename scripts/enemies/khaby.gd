extends Enemy
## THE KHABY LAME MECHANISM: friendly. It stands on its table in the middle of the field and
## its chain-driven arms go round and round, stopping palms-up at the top for a moment:
## "it's that simple". It never moves, never hunts, never drains you. It only ever explains.

const KM = preload("res://scripts/khaby_model.gd")
const POSE = 1.35          # rod angle with the palms up, in front of the chest
const SPIN = 1.7           # seconds for one turn
const HOLD = 0.9           # seconds it holds the pose

var presenting = 0.0       # 0..1: holds the pose (cutscene), instead of spinning
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
		if not _turned and world.player and not world.headless:
			_turned = true
			Audio.play_at("khaby_servo", global_transform.origin + Vector3(0, 1.9, 0), world, -2.0, rand_range(0.96, 1.04), 30.0)
	else:
		_turned = false
		# the servo settles: a small shiver in the pose
		a = POSE + sin((u - SPIN) * 38.0) * 0.03 * exp(-(u - SPIN) * 6.0)
	a = lerp(a, POSE + sin(_t * 1.3) * 0.05, presenting)
	for arm in _arms:
		arm.rotation.x = a
	if _head:
		_head.rotation = Vector3(sin(_t * 0.7) * 0.03 + presenting * 0.06, sin(_t * 0.45) * 0.05, 0)
