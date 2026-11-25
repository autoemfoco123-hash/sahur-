class_name Enemy
extends CharacterBody3D
## Base brainrot: model, harsh personal top-light, grid pathing, limb animation, catching.

var world: World
var model_id := ""
var model: Node3D
var height := 2.0
var hostile := true
var catch_dist := 1.2
var death_msg := ""
var use_gravity := true
var want := Vector3.ZERO
var step_sound := ""
var step_vol := 0.0
var step_stride := 1.4
var step_pitch := 1.0
var anim_speed := 1.0
var anim_amp := 0.6
var top_light: SpotLight3D
var light_energy := 7.0
var frozen := false
var drains := true
var chase_sound := ""
var chase_player: AudioStreamPlayer3D
var aggro_target := 0.0
var aggro := 0.0
var _stinger_cd := 0.0

var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _last_target := Vector3.INF
var _phase := 0.0
var _step_acc := 0.0
var _limbs := {}
var _flick := 0.0


func setup(w: Node, id: String, pos: Vector3, is_hostile := true) -> Enemy:
	world = w
	model_id = id
	hostile = is_hostile
	collision_layer = Geo.LAYER_ENEMY
	collision_mask = Geo.LAYER_WORLD
	model = Models.build(id)
	add_child(model)
	height = model.get_meta("height", 2.0)
	if death_msg == "":
		death_msg = model.get_meta("display", "")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = clampf(height, 1.0, 2.4)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	top_light = SpotLight3D.new()
	top_light.light_color = Color(1.0, 0.9, 0.78)
	top_light.light_energy = light_energy
	top_light.spot_range = height + 4.5
	top_light.spot_angle = 30.0
	top_light.spot_attenuation = 0.4
	top_light.shadow_enabled = true
	top_light.light_volumetric_fog_energy = 3.0
	add_child(top_light)
	top_light.position = Vector3(0, height + 1.8, 0)
	top_light.rotation_degrees = Vector3(-90, 0, 0)
	for n in ["legL", "legR", "leg0", "leg1", "leg2", "footL", "footR", "armL", "armR", "body"]:
		var f := model.find_child(n, true, false)
		if f:
			_limbs[n] = f
	world.add_child(self)
	global_position = pos
	if hostile:
		add_to_group("hostile")
	if chase_sound != "":
		chase_player = Audio.attach(chase_sound, self, -60.0, 80.0)
		chase_player.position.y = height * 0.6
	return self


## Call when this brainrot spots the player: stinger + chase music kicks in.
func alert() -> void:
	if _stinger_cd <= 0.0:
		_stinger_cd = 10.0
		Audio.play("stinger", -4.0)
		world.player.add_trauma(0.35)
	aggro_target = 1.0


func think(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if world == null:
		return
	want = Vector3.ZERO
	if not world.dying and not frozen:
		think(delta)
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(want, clampf(delta * 10.0, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if use_gravity:
		velocity.y = velocity.y - 20.0 * delta if not is_on_floor() else -0.5
	else:
		velocity.y = want.y
	move_and_slide()
	var spd := hv.length()
	_animate(delta, spd)
	if spd > 0.3 and step_sound != "":
		_step_acc += spd * delta
		if _step_acc > step_stride:
			_step_acc = 0.0
			Audio.play_at(step_sound, global_position, world, step_vol, step_pitch * randf_range(0.9, 1.1), 50.0)
	# Flickering personal top light
	_flick -= delta
	if _flick <= 0.0:
		_flick = randf_range(0.05, 0.6)
		top_light.light_energy = light_energy * (randf_range(0.1, 0.5) if randf() < 0.12 else 1.0)
	if hostile and not world.dying and not frozen:
		check_catch()
	_stinger_cd -= delta
	aggro = move_toward(aggro, aggro_target, delta * (2.0 if aggro_target > aggro else 0.35))
	if chase_player:
		Audio.set_base_volume(chase_player, lerpf(-45.0, 3.0, aggro) if aggro > 0.01 else -80.0)


func _animate(delta: float, spd: float) -> void:
	_phase += delta * (2.0 + spd * 2.2) * anim_speed
	var a := clampf(spd / 3.0, 0.0, 1.0) * anim_amp
	var s := sin(_phase)
	if _limbs.has("legL"): _limbs["legL"].rotation.x = s * a
	if _limbs.has("legR"): _limbs["legR"].rotation.x = -s * a
	if _limbs.has("footL"): _limbs["footL"].rotation.x = s * a * 0.5
	if _limbs.has("footR"): _limbs["footR"].rotation.x = -s * a * 0.5
	if _limbs.has("leg0"): _limbs["leg0"].rotation.x = s * a
	if _limbs.has("leg1"): _limbs["leg1"].rotation.x = -s * a
	if _limbs.has("leg2"): _limbs["leg2"].rotation.x = sin(_phase + 1.5) * a
	if _limbs.has("armL"): _limbs["armL"].rotation.x = -s * a * 0.7
	if _limbs.has("armR"): _limbs["armR"].rotation.x = s * a * 0.7
	if _limbs.has("body"):
		_limbs["body"].position.y = _limbs["body"].position.y * 0.9 + (absf(s) * a * 0.06 + _body_base()) * 0.1


func _body_base() -> float:
	if not has_meta("body_y"):
		set_meta("body_y", _limbs["body"].position.y)
	return get_meta("body_y")


# ------------------------------------------------------------------ movement
func move_to(target: Vector3, spd: float, delta: float) -> bool:
	_repath -= delta
	if _repath <= 0.0 or target.distance_to(_last_target) > 1.5:
		_repath = 0.35
		_last_target = target
		if world.nav:
			_path = world.nav.path(global_position, target)
		else:
			_path = PackedVector3Array([target])
		_path_i = 0
	var goal := target
	while _path_i < _path.size():
		var wp := _path[_path_i]
		if Vector2(wp.x - global_position.x, wp.z - global_position.z).length() < 0.45:
			_path_i += 1
		else:
			goal = wp
			break
	var d := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	if d.length() < 0.3:
		return true
	want = d.normalized() * spd
	face_dir(d, delta)
	return false


func face_dir(d: Vector3, delta: float, rate := 8.0) -> void:
	if d.length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * rate, 0.0, 1.0))


func face_point(p: Vector3, delta: float, rate := 8.0) -> void:
	face_dir(p - global_position, delta, rate)


# ------------------------------------------------------------------ senses
func player() -> Player:
	return world.player


func dist_to_player() -> float:
	var p: Vector3 = world.player.global_position
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func eye() -> Vector3:
	return global_position + Vector3(0, height * 0.85, 0)


func sees_player(max_dist := 20.0) -> bool:
	var pe: Vector3 = world.player.eye_pos()
	var from := eye()
	if from.distance_to(pe) > max_dist:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, pe, Geo.LAYER_WORLD)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func seen_by_player(max_angle := 45.0, max_dist := 60.0) -> bool:
	return world.player.can_see(global_position + Vector3(0, height * 0.6, 0), max_angle, max_dist, [get_rid()])


func check_catch() -> void:
	var p: Vector3 = world.player.global_position
	if dist_to_player() < catch_dist and absf(p.y - global_position.y) < 2.5:
		world.kill(model_id, death_msg)


func random_target() -> Vector3:
	if world.nav:
		return world.nav.random_open(world.rng, global_position.y)
	return global_position + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
