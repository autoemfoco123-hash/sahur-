class_name Player
extends CharacterBody3D
## First-person player (hush operative 03): walk, crouch, jump, interact, shout.
## Seen entirely through the hush nv-7 goggles, which can't be removed.
## (internally the visor still uses the old 'flashlight' names.)

signal shouted

const WALK := 4.2
const CROUCH := 1.6
const STAND_H := 1.75
const CROUCH_H := 1.1

var world: World
var controls := true
var look_enabled := true
var speed_mult := 1.0
var gravity := 14.0
var jump_vel := 5.0
var step_sound := "step_concrete"
var step_volume := -14.0
var crouching := false
var flashlight_on := false
const NV_LAYER := 2
const ROT_LAYER := 4
var _hum: AudioStreamPlayer
var flicker := 0.0
var battery_drain := 1.0 / 2.4
var trauma := 0.0

var head: Node3D
var cam: Camera3D
var flashlight: SpotLight3D
var ray: RayCast3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D

var _bob := 0.0
var _step_acc := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _shout_cd := 0.0
var _flash_target := Basis()
var _noise := FastNoiseLite.new()
var _t := 0.0
var _hover: Interactable
var _air_t := 0.0

# --- head motion (bob, sway, tilt, inertia) and the gyroscope it feeds
var rig: Node3D
var _phase := 0.0
var _bob_amp := 0.0
var _last_step := 0
var _tilt := 0.0
var _prev_yaw := 0.0
var _prev_lv := Vector3.ZERO
var _sp_pos := Vector2.ZERO   # spring: (pitch, roll) radians
var _sp_vel := Vector2.ZERO
var _land := 0.0
var _land_v := 0.0
var g_vec := Vector3(0, 1, 0)   # (lateral, vertical, longitudinal) in g
var vel_local := Vector3.ZERO
var att_roll := 0.0             # degrees
var att_pitch := 0.0            # degrees


func _init() -> void:
	collision_layer = Geo.LAYER_PLAYER
	collision_mask = Geo.LAYER_WORLD
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = STAND_H
	shape.shape = capsule
	shape.position.y = STAND_H * 0.5
	add_child(shape)
	head = Node3D.new()
	head.position.y = 1.6
	add_child(head)
	rig = Node3D.new()
	head.add_child(rig)
	cam = Camera3D.new()
	cam.fov = 78
	cam.near = 0.03
	cam.far = 400
	rig.add_child(cam)
	flashlight = SpotLight3D.new()
	# Infrared illuminator: only matters through the visor.
	flashlight.light_color = Color(0.9, 1.0, 0.92)
	flashlight.light_energy = 1.6
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 62.0
	flashlight.spot_attenuation = 0.7
	flashlight.spot_angle_attenuation = 0.8
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.05
	flashlight.light_volumetric_fog_energy = 0.7
	head.add_child(flashlight)
	flashlight.position = Vector3(0.18, -0.15, 0.05)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.6)
	ray.collision_mask = Geo.LAYER_INTERACT | Geo.LAYER_WORLD
	ray.collide_with_areas = true
	cam.add_child(ray)
	_noise.frequency = 0.8


func _ready() -> void:
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_yaw = rotation.y
	rotation.y = 0
	_hum = AudioStreamPlayer.new()
	_hum.stream = Audio.get_stream("nv_hum")
	_hum.volume_db = -22.0
	add_child(_hum)
	set_visor(false, true)


func set_look(yaw: float, pitch := 0.0) -> void:
	_yaw = yaw
	_pitch = pitch


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and look_enabled and controls:
		var s: float = Game.settings.sensitivity * 0.01
		_yaw -= event.relative.x * s
		_pitch = clampf(_pitch - event.relative.y * s, -1.45, 1.45)
	if not controls:
		return
	if event.is_action_pressed("shout") and _shout_cd <= 0.0:
		_shout_cd = 1.2
		Audio.play("shout", -3.0, randf_range(0.95, 1.05))
		if world:
			world.hud.subtitle("you: \"sahur!\"", 1.4)
		shouted.emit()
	if event.is_action_pressed("interact") and _hover and is_instance_valid(_hover):
		_hover.use()


func _physics_process(delta: float) -> void:
	_t += delta
	_shout_cd -= delta
	rotation.y = _yaw
	head.rotation.x = _pitch
	# Movement
	var input := Vector2.ZERO
	if controls:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = controls and Input.is_action_pressed("crouch")
	if not crouching and capsule.height < STAND_H:
		var q := PhysicsShapeQueryParameters3D.new()
		var test := CapsuleShape3D.new()
		test.radius = 0.3
		test.height = STAND_H
		q.shape = test
		q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_H * 0.5 + 0.05, 0))
		q.collision_mask = Geo.LAYER_WORLD
		if get_world_3d().direct_space_state.intersect_shape(q, 1).size() > 0:
			crouching = true
	var target_h := CROUCH_H if crouching else STAND_H
	capsule.height = move_toward(capsule.height, target_h, delta * 4.0)
	shape.position.y = capsule.height * 0.5
	head.position.y = capsule.height - 0.15
	var spd := (CROUCH if crouching else WALK) * speed_mult
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := 12.0 if is_on_floor() else 3.0
	hv = hv.lerp(dir * spd, clampf(accel * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif controls and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = jump_vel
	move_and_slide()
	# Shove physics props like in a sandbox game
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb:
			rb.apply_central_impulse(-c.get_normal() * minf(rb.mass, 30.0) * 0.12)
	# Landing
	if is_on_floor() and _air_t > 0.35:
		Audio.play(step_sound, step_volume + 4.0, 0.8)
		_land_v -= 1.6 * minf(_air_t, 1.0)
		add_trauma(0.15)
	_air_t = 0.0 if is_on_floor() else _air_t + delta
	_head_motion(delta)
	# Camera shake
	trauma = maxf(0.0, trauma - delta * 1.2)
	var sh := trauma * trauma
	cam.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * sh * 0.25
	cam.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * sh * 0.25
	cam.rotation.z = _noise.get_noise_2d(_t * 30.0, 50.0) * sh * 0.12
	_update_flashlight(delta)
	_update_hover()


## Heavy head bob, sway, lean-into-turns tilt, and a spring that makes the head lag
## behind every acceleration. Footsteps land exactly on the bottom of each bob.
func _head_motion(delta: float) -> void:
	var hs := _hspeed()
	var grounded := is_on_floor()
	var moving := grounded and hs > 0.25
	var step_len := 0.74 if not crouching else 0.5
	if moving:
		_phase += hs * delta / step_len * PI
	_bob_amp = lerpf(_bob_amp, clampf(hs / WALK, 0.0, 1.3) if moving else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var k := _bob_amp
	var bob_y := (0.5 - absf(sin(_phase))) * 0.045 * k
	var bob_x := sin(_phase) * 0.028 * k
	var bob_roll := sin(_phase) * deg_to_rad(1.2) * k
	var bob_pitch := cos(_phase * 2.0) * deg_to_rad(0.5) * k
	var bob_yaw := sin(_phase) * deg_to_rad(0.35) * k
	var idx := int(floor(_phase / PI))
	if idx != _last_step:
		_last_step = idx
		if moving:
			Audio.play(step_sound, step_volume - (6.0 if crouching else 0.0), randf_range(0.88, 1.08))
	# Local velocity + acceleration (the accelerometer)
	var lv := global_basis.inverse() * velocity
	var acc := (lv - _prev_lv) / maxf(delta, 0.0001)
	_prev_lv = lv
	vel_local = lv
	var g_target := Vector3(acc.x / 9.81, 1.0 + acc.y / 9.81, -acc.z / 9.81)
	g_vec = g_vec.lerp(g_target, clampf(delta * 8.0, 0.0, 1.0))
	# Tilt: lean into strafes and turns
	var yaw_rate := wrapf(_yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_yaw = _yaw
	var tilt_target := -lv.x / WALK * deg_to_rad(15.0) + clampf(yaw_rate, -5.0, 5.0) * deg_to_rad(3.4)
	tilt_target = clampf(tilt_target, deg_to_rad(-20.0), deg_to_rad(20.0))
	_tilt = lerpf(_tilt, tilt_target, clampf(delta * 4.0, 0.0, 1.0))
	# Inertia spring: head pitches back when you speed up, forward when you stop
	var sp_target := Vector2(clampf(-acc.z, -20.0, 20.0) * deg_to_rad(0.22), clampf(-acc.x, -20.0, 20.0) * deg_to_rad(0.2))
	_sp_vel += ((sp_target - _sp_pos) * 70.0 - _sp_vel * 9.0) * delta
	_sp_pos += _sp_vel * delta
	_land_v += (-_land * 90.0 - _land_v * 10.0) * delta
	_land += _land_v * delta
	# Breathing when still
	var br := sin(_t * 1.35) * (1.0 - k)
	rig.position = Vector3(bob_x, bob_y + _land * 0.25 + br * 0.008, 0)
	rig.rotation = Vector3(bob_pitch + _sp_pos.x + br * deg_to_rad(0.4) + _land * 0.15, bob_yaw, _tilt + bob_roll + _sp_pos.y)
	att_roll = rad_to_deg(rig.rotation.z + cam.rotation.z)
	att_pitch = rad_to_deg(head.rotation.x + rig.rotation.x)


func _hspeed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func horizontal_speed() -> float:
	return _hspeed()


func _update_flashlight(delta: float) -> void:
	# The beam lags behind the camera a little. It feels heavier, more scared.
	flashlight.global_basis = flashlight.global_basis.orthonormalized().slerp(cam.global_basis.orthonormalized(), clampf(delta * 14.0, 0.0, 1.0)).orthonormalized()
	var e := 1.6
	if Game.flashlight_battery < 15.0:
		e *= 0.4 + 0.6 * Game.flashlight_battery / 15.0
	if flicker > 0.0 and randf() < flicker * 0.5:
		e *= randf_range(0.0, 0.4)
	flashlight.light_energy = 0.0
	flashlight.visible = false


## The hush nv-7 goggles are bolted on. Once they boot, they never come off:
## everything you see in sahur, you see through them. (Layer 2 = hush chalk marks.)
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
		var c := ray.get_collider()
		if c is Interactable and c.enabled:
			_hover = c
	if world:
		world.hud.set_prompt(("[E]  " + _hover.prompt) if _hover else "")


func add_trauma(x: float) -> void:
	trauma = clampf(trauma + x, 0.0, 1.0)


func eye_pos() -> Vector3:
	return cam.global_position


## Is a world point on screen and unobstructed?
func can_see(p: Vector3, max_angle_deg := 50.0, max_dist := 80.0, exclude: Array = []) -> bool:
	var from := cam.global_position
	var to := p - from
	if to.length() > max_dist:
		return false
	var fwd := -cam.global_basis.z
	if fwd.dot(to.normalized()) < cos(deg_to_rad(max_angle_deg)):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, p, Geo.LAYER_WORLD)
	var ex: Array[RID] = [get_rid()]
	for e in exclude:
		ex.append(e)
	q.exclude = ex
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Something above your head? (shelter test)
func is_sheltered() -> bool:
	var from := global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 40, 0), Geo.LAYER_WORLD)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
