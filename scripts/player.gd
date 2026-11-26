class_name Player
extends KinematicBody
## First-person player (hush operative 03): walk, crouch, jump, interact, shout.
## Seen entirely through the hush nv-7 goggles. (Godot 3)

signal shouted

const WALK := 4.2
const CROUCH := 1.6
const STAND_H := 1.75
const CROUCH_H := 1.1
const RADIUS := 0.35
const NV_LAYER := 2

var world
var controls = true
var look_enabled = true
var speed_mult = 1.0
var gravity = 14.0
var jump_vel = 5.0
var step_sound = "step_grass"
var step_volume = -16.0
var crouching = false
var flashlight_on = false   # "goggles on" (old name kept)
var flicker = 0.0
var trauma = 0.0
var velocity = Vector3.ZERO

var head: Spatial
var rig: Spatial
var cam: Camera
var ray: RayCast
var shape: CollisionShape
var capsule: CapsuleShape
var _hum: AudioStreamPlayer

var _yaw = 0.0
var _pitch = 0.0
var _shout_cd = 0.0
var _noise = OpenSimplexNoise.new()
var _t = 0.0
var _hover = null
var _air_t = 0.0
var _height = STAND_H
# head motion + gyroscope data
var _phase = 0.0
var _bob_amp = 0.0
var _last_step = 0
var _tilt = 0.0
var _prev_yaw = 0.0
var _prev_lv = Vector3.ZERO
var _sp_pos = Vector2.ZERO
var _sp_vel = Vector2.ZERO
var _land = 0.0
var _land_v = 0.0
var spectate_target = null   # avatar we ride along with after death / escape
var g_vec = Vector3(0, 1, 0)
var vel_local = Vector3.ZERO
var att_roll = 0.0
var att_pitch = 0.0


func _init() -> void:
	collision_layer = Geo.LAYER_PLAYER
	collision_mask = Geo.LAYER_WORLD
	shape = CollisionShape.new()
	capsule = CapsuleShape.new()
	capsule.radius = RADIUS
	capsule.height = STAND_H - 2.0 * RADIUS
	shape.shape = capsule
	shape.rotation_degrees = Vector3(90, 0, 0)
	shape.translation.y = STAND_H * 0.5
	add_child(shape)
	head = Spatial.new()
	head.translation.y = 1.6
	add_child(head)
	rig = Spatial.new()
	head.add_child(rig)
	cam = Camera.new()
	cam.fov = 78
	cam.near = 0.03
	cam.far = 300
	rig.add_child(cam)
	ray = RayCast.new()
	ray.enabled = true
	ray.cast_to = Vector3(0, 0, -2.6)
	ray.collision_mask = Geo.LAYER_INTERACT | Geo.LAYER_WORLD
	ray.collide_with_areas = true
	ray.add_exception(self)
	cam.add_child(ray)
	_noise.period = 1.2


func _ready() -> void:
	cam.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_hum = AudioStreamPlayer.new()
	_hum.stream = Audio.get_stream("nv_hum")
	_hum.volume_db = -22.0
	add_child(_hum)
	set_visor(false, true)
	Audio.listener_cam = cam


func set_look(yaw: float, pitch := 0.0) -> void:
	_yaw = yaw
	_pitch = pitch
	_prev_yaw = yaw


func _unhandled_input(event: InputEvent) -> void:
	if not controls:
		return
	if event.is_action_pressed("shout") and _shout_cd <= 0.0:
		_shout_cd = 1.2
		Audio.play("shout", -3.0, rand_range(0.95, 1.05))
		if world:
			world.hud.subtitle("you: \"sahur!\"", 1.4)
		emit_signal("shouted")
	if event.is_action_pressed("interact") and _hover and is_instance_valid(_hover):
		_hover.use()


## Ride along behind another operative's eyes (multiplayer, after death or escape).
func spectate(a) -> void:
	spectate_target = a
	controls = false
	look_enabled = false
	shape.disabled = true
	if a == null:
		velocity = Vector3.ZERO


## Back in your own body (revived for a new wave).
func unspectate() -> void:
	spectate_target = null
	shape.disabled = false
	velocity = Vector3.ZERO
	controls = true
	look_enabled = true


func _physics_process(delta: float) -> void:
	_t += delta
	_shout_cd -= delta
	if shape.disabled:
		Game.take_mouse()
		if spectate_target != null and is_instance_valid(spectate_target):
			var a = spectate_target
			global_transform.origin = a.global_transform.origin
			_yaw = a.yaw
			_pitch = a.pitch
			rotation.y = _yaw
			head.rotation.x = _pitch
			head.translation.y = 1.6 - a.crouch * 0.6
			velocity = -global_transform.basis.z * a.speed
			_head_motion(delta)
		_update_hover()
		return
	# Mouse look: raw window pixels collected by Game (independent of resolution / ui scale).
	var md: Vector2 = Game.take_mouse()
	if look_enabled and controls and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var s: float = float(Game.settings.sensitivity) * 0.01
		_yaw -= md.x * s
		_pitch = clamp(_pitch - md.y * s, -1.45, 1.45)
	rotation.y = _yaw
	head.rotation.x = _pitch
	var input = Vector2.ZERO
	if controls:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = controls and Input.is_action_pressed("crouch")
	if not crouching and _height < STAND_H:
		var q = PhysicsShapeQueryParameters.new()
		var test = CapsuleShape.new()
		test.radius = 0.3
		test.height = STAND_H - 0.6
		q.set_shape(test)
		q.transform = Transform(Basis(Vector3.RIGHT, PI / 2), global_transform.origin + Vector3(0, STAND_H * 0.5 + 0.05, 0))
		q.collision_mask = Geo.LAYER_WORLD
		q.exclude = [self]
		if get_world().direct_space_state.intersect_shape(q, 1).size() > 0:
			crouching = true
	var target_h = CROUCH_H if crouching else STAND_H
	_height = move_toward(_height, target_h, delta * 4.0)
	capsule.height = max(_height - 2.0 * RADIUS, 0.05)
	shape.translation.y = _height * 0.5
	head.translation.y = _height - 0.15
	var spd = (CROUCH if crouching else WALK) * speed_mult
	var dir = (transform.basis.xform(Vector3(input.x, 0, input.y))).normalized()
	var hv = Vector3(velocity.x, 0, velocity.z)
	var accel = 12.0 if is_on_floor() else 3.0
	hv = hv.linear_interpolate(dir * spd, clamp(accel * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	var snap = Vector3.DOWN * 0.4
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif controls and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = jump_vel
		snap = Vector3.ZERO
	velocity = move_and_slide_with_snap(velocity, snap, Vector3.UP, true, 4, deg2rad(50))
	if is_on_floor() and _air_t > 0.35:
		Audio.play(step_sound, step_volume + 4.0, 0.8)
		_land_v -= 1.6 * min(_air_t, 1.0)
		add_trauma(0.15)
	_air_t = 0.0 if is_on_floor() else _air_t + delta
	_head_motion(delta)
	trauma = max(0.0, trauma - delta * 1.2)
	var sh = trauma * trauma
	cam.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * sh * 0.25
	cam.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * sh * 0.25
	cam.rotation.z = _noise.get_noise_2d(_t * 30.0, 50.0) * sh * 0.12
	_update_hover()


## Light head bob, strong lean-into-turns tilt, and a spring that makes the head lag behind
## every acceleration. Footsteps land exactly on the bottom of each bob.
func _head_motion(delta: float) -> void:
	var hs = horizontal_speed()
	var moving = is_on_floor() and hs > 0.25
	var step_len = 0.74 if not crouching else 0.5
	if moving:
		_phase += hs * delta / step_len * PI
	_bob_amp = lerp(_bob_amp, clamp(hs / WALK, 0.0, 1.3) if moving else 0.0, clamp(delta * 6.0, 0.0, 1.0))
	var k = _bob_amp
	var bob_y = (0.5 - abs(sin(_phase))) * 0.045 * k
	var bob_x = sin(_phase) * 0.028 * k
	var bob_roll = sin(_phase) * deg2rad(1.2) * k
	var bob_pitch = cos(_phase * 2.0) * deg2rad(0.5) * k
	var bob_yaw = sin(_phase) * deg2rad(0.35) * k
	var idx = int(floor(_phase / PI))
	if idx != _last_step:
		_last_step = idx
		if moving:
			Audio.play(step_sound, step_volume - (6.0 if crouching else 0.0), rand_range(0.88, 1.08))
	var lv: Vector3 = global_transform.basis.xform_inv(velocity)
	var acc = (lv - _prev_lv) / max(delta, 0.0001)
	_prev_lv = lv
	vel_local = lv
	var g_target = Vector3(acc.x / 9.81, 1.0 + acc.y / 9.81, -acc.z / 9.81)
	g_vec = g_vec.linear_interpolate(g_target, clamp(delta * 8.0, 0.0, 1.0))
	var yaw_rate = wrapf(_yaw - _prev_yaw, -PI, PI) / max(delta, 0.0001)
	_prev_yaw = _yaw
	var tilt_target = -lv.x / WALK * deg2rad(15.0) + clamp(yaw_rate, -5.0, 5.0) * deg2rad(3.4)
	tilt_target = clamp(tilt_target, deg2rad(-20.0), deg2rad(20.0))
	_tilt = lerp(_tilt, tilt_target, clamp(delta * 4.0, 0.0, 1.0))
	var sp_target = Vector2(clamp(-acc.z, -20.0, 20.0) * deg2rad(0.22), clamp(-acc.x, -20.0, 20.0) * deg2rad(0.2))
	_sp_vel += ((sp_target - _sp_pos) * 70.0 - _sp_vel * 9.0) * delta
	_sp_pos += _sp_vel * delta
	_land_v += (-_land * 90.0 - _land_v * 10.0) * delta
	_land += _land_v * delta
	var br = sin(_t * 1.35) * (1.0 - k)
	rig.translation = Vector3(bob_x, bob_y + _land * 0.25 + br * 0.008, 0)
	rig.rotation = Vector3(bob_pitch + _sp_pos.x + br * deg2rad(0.4) + _land * 0.15, bob_yaw, _tilt + bob_roll + _sp_pos.y)
	att_roll = rad2deg(rig.rotation.z + cam.rotation.z)
	att_pitch = rad2deg(head.rotation.x + rig.rotation.x)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## The hush nv-7 goggles are bolted on. Layer 2 (hush chalk marks) only exists through them.
func set_visor(on: bool, silent := false) -> void:
	flashlight_on = on
	if on:
		cam.cull_mask = cam.cull_mask | NV_LAYER
		_hum.play()
	else:
		cam.cull_mask = cam.cull_mask & ~NV_LAYER
		_hum.stop()
	if not silent:
		Audio.play("nv_on" if on else "nv_off", -4.0)


func _update_hover() -> void:
	_hover = null
	if controls and ray.is_colliding():
		var c = ray.get_collider()
		if c and c.has_method("use") and c.enabled:
			_hover = c
	if world:
		world.hud.set_prompt(_hover.prompt if _hover else "")


func add_trauma(x: float) -> void:
	trauma = clamp(trauma + x, 0.0, 1.0)


func eye_pos() -> Vector3:
	return cam.global_transform.origin


## Is a world point on screen and unobstructed?
func can_see(p: Vector3, max_angle_deg := 50.0, max_dist := 80.0, exclude := []) -> bool:
	var from = cam.global_transform.origin
	var to = p - from
	if to.length() > max_dist:
		return false
	var fwd = -cam.global_transform.basis.z
	if fwd.dot(to.normalized()) < cos(deg2rad(max_angle_deg)):
		return false
	var ex = [self] + exclude
	return get_world().direct_space_state.intersect_ray(from, p, ex, Geo.LAYER_WORLD).empty()
