extends Spatial
## Another operative in the round: interpolated network movement, a procedural walk,
## footsteps and a name tag. Dead operatives stop updating and just stand there.

const OperativeModel = preload("res://scripts/operative_model.gd")
const DELAY = 0.1

var id = 0
var model: Spatial
var tag: Label3D
var yaw = 0.0
var pitch = 0.0
var crouch = 0.0
var speed = 0.0
var spectated = false
var _j = {}
var _target = Vector3.ZERO
var _tyaw = 0.0
var _tpitch = 0.0
var _flags = 0
var _have = false
var _ph = 0.0
var _last_step = 0
var _prev = Vector3.ZERO
var _vel = Vector3.ZERO    # how fast it was going between its last two states (to see ahead)
var _last_t = -1           # the sender's clock on the last state (ms, 16 bits)
var _last_rx = 0           # when it arrived (our clock)


func setup(peer_id: int, pname: String, color: Color, headless := false) -> void:
	id = peer_id
	if headless:
		# dedicated server: only the position matters
		model = Spatial.new()
		add_child(model)
		return
	model = OperativeModel.build(color)
	add_child(model)
	for n in ["hips", "torso", "head", "armL", "armR", "elbowL", "elbowR", "legL", "legR", "kneeL", "kneeR"]:
		_j[n] = model.find_node(n, true, false)
	tag = Label3D.new()
	tag.text = pname
	tag.font = UI.font("medium", 40)
	tag.pixel_size = 0.0045
	tag.billboard = SpatialMaterial.BILLBOARD_ENABLED
	tag.modulate = Color(color.r, color.g, color.b, 0.85)
	tag.outline_modulate = Color(0, 0, 0, 0.6)
	tag.translation = Vector3(0, 2.08, 0)
	tag.layers = 1
	add_child(tag)


func place(pos: Vector3, y: float) -> void:
	translation = pos
	_target = pos
	_prev = pos
	_vel = Vector3.ZERO
	yaw = y
	_tyaw = y
	rotation.y = y
	_have = true


func net_update(pos: Vector3, y: float, p: float, flags: int, t := -1) -> void:
	if t >= 0 and _last_t >= 0:
		var dt = ((t - _last_t) & 0xffff) / 1000.0
		if dt <= 0.0 or dt > 30.0:
			return                         # older than what we have: it came the long way round
		if dt < 0.5:
			var v = (pos - _target) / dt
			_vel = _vel.linear_interpolate(v if v.length() < 12.0 else Vector3.ZERO, 0.6)
		else:
			_vel = Vector3.ZERO
	_last_t = t
	_last_rx = OS.get_ticks_msec()
	_target = pos
	_tyaw = y
	_tpitch = p
	_flags = flags
	if not _have:
		place(pos, y)


## Where this operative really is, as far as the network knows: its last state, carried on at
## its speed (the drawn body is smoothed and lags a little behind this). The rules use this.
func net_pos() -> Vector3:
	if not _have:
		return translation
	return _target + _vel * min((OS.get_ticks_msec() - _last_rx) / 1000.0, 0.15)


## Its own machine just said exactly where it stands (sent right before a request).
func net_snap(pos: Vector3) -> void:
	_target = pos
	_last_rx = OS.get_ticks_msec()
	if not _have:
		place(pos, yaw)


func eye_pos() -> Vector3:
	return global_transform.origin + Vector3(0, 1.6 - crouch * 0.6, 0)


func set_spectated(on: bool) -> void:
	spectated = on
	model.visible = not on
	if tag:
		tag.visible = not on


func _process(delta: float) -> void:
	# smooth toward where it is now: the last state, carried on at its speed for as long as the
	# next one takes (states come 30 times a second)
	var age = min((OS.get_ticks_msec() - _last_rx) / 1000.0 + 0.03, 0.18)
	var k = clamp(delta * 16.0, 0.0, 1.0)
	translation = translation.linear_interpolate(_target + _vel * age, k)
	yaw = lerp_angle(yaw, _tyaw, k)
	pitch = lerp(pitch, _tpitch, k)
	rotation.y = yaw
	crouch = move_toward(crouch, 1.0 if _flags & 1 else 0.0, delta * 4.0)
	var v = (translation - _prev) / max(delta, 0.0001)
	_prev = translation
	speed = lerp(speed, Vector2(v.x, v.z).length(), clamp(delta * 8.0, 0.0, 1.0))
	_animate(delta)


func _animate(delta: float) -> void:
	if _j.get("hips") == null:
		return
	var w = clamp(speed / 3.0, 0.0, 1.0)
	if speed > 0.15:
		_ph += speed / 1.45 * TAU * delta
	var sw = sin(_ph)
	var hips: Spatial = _j["hips"]
	hips.translation.y = OperativeModel.HIP_Y - crouch * 0.38 - abs(cos(_ph)) * 0.035 * w + 0.015
	hips.rotation = Vector3(0, sw * 0.08 * w, 0)
	(_j["torso"] as Spatial).rotation = Vector3(-0.08 * w - crouch * 0.35, -sw * 0.1 * w, 0)
	(_j["head"] as Spatial).rotation = Vector3(clamp(-pitch * 0.7, -0.8, 0.8) + crouch * 0.3, 0, 0)
	for side in [0, 1]:
		var s = "L" if side == 0 else "R"
		var ph = _ph + (0.0 if side == 0 else PI)
		var leg: Spatial = _j["leg" + s]
		var knee: Spatial = _j["knee" + s]
		leg.translation.y = hips.translation.y
		leg.rotation.x = sin(ph) * 0.55 * w - crouch * 1.1
		knee.rotation.x = -max(0.0, -cos(ph)) * 0.9 * w - crouch * 1.9 * 0.5 - 0.05
		var arm: Spatial = _j["arm" + s]
		var el: Spatial = _j["elbow" + s]
		arm.rotation = Vector3(-sin(ph) * 0.45 * w, 0, (0.08 if side == 0 else -0.08))
		el.rotation.x = 0.35 + 0.35 * w
	if tag == null:
		return
	# footsteps you can hear through the office
	var idx = int(floor(_ph / PI))
	if idx != _last_step:
		_last_step = idx
		if speed > 0.8 and not spectated:
			Audio.play_at("step_grass", global_transform.origin, get_parent(), -14.0 - crouch * 6.0, rand_range(0.88, 1.08), 22.0)


func shout() -> void:
	Audio.play_at("shout", global_transform.origin + Vector3(0, 1.6, 0), get_parent(), 2.0, rand_range(0.92, 1.06), 70.0)
