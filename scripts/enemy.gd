class_name Enemy
extends KinematicBody
## Base brainrot: model, personal top-light, grid pathing, catching, chase music. (Godot 3)

var world
var model_id = ""
var model: Spatial
var height = 2.0
var hostile = true
var catch_dist = 1.2
var death_msg = ""
var want = Vector3.ZERO
var velocity = Vector3.ZERO
var top_light: SpotLight
var light_energy = 7.0
var frozen = false
var puppet = false          # multiplayer client: the server moves this one, we only animate it
var chase_id = -1           # operative being chased / hunted (server)
var hunt_id = -1
var _net_pos = Vector3.ZERO
var _net_yaw = 0.0
var _net_have = false
var _pspd = 0.0
var drains = true
var chase_sound = ""
var chase_player: AudioStreamPlayer3D
var aggro_target = 0.0
var aggro = 0.0
var pinned = false          # held where it is (no gravity, no moving), still animated
var kill_t = -1.0           # seconds into the kill animation (-1: not killing)
var kill_at = Vector3.ZERO  # where the victim stands
var kill_hit = 0.42         # when the blow lands (the body flies then)
var kill_len = 1.1
var kill_force = 9.0        # how fast the body leaves (m/s)
var kill_lift = 4.0

var nav                   # the NavGrid of the sector it lives in
var sector = 0            # brainrots never leave their sector: they only hunt operatives in it
var _path = PoolVector3Array()
var _path_i = 0
var _repath = 0.0
var _last_target = Vector3(1e9, 1e9, 1e9)
var _flick = 0.0
var _stinger_cd = 0.0


func setup(w, id: String, pos: Vector3, is_hostile := true):
	world = w
	nav = w.nav
	sector = w.sector_at(pos)
	model_id = id
	hostile = is_hostile
	collision_layer = Geo.LAYER_ENEMY
	collision_mask = Geo.LAYER_WORLD
	model = Brainrots.build_headless(id) if w.headless else Brainrots.build(id)
	add_child(model)
	height = model.get_meta("height")
	if death_msg == "":
		death_msg = model.get_meta("display")
	var cs = CollisionShape.new()
	var cap = CapsuleShape.new()
	cap.radius = 0.4
	cap.height = clamp(height, 1.0, 2.4) - 0.8
	cs.shape = cap
	cs.rotation_degrees = Vector3(90, 0, 0)
	cs.translation.y = clamp(height, 1.0, 2.4) * 0.5
	add_child(cs)
	top_light = SpotLight.new()
	top_light.light_color = Color(1.0, 0.9, 0.78)
	top_light.light_energy = light_energy
	top_light.spot_range = height + 4.5
	top_light.spot_angle = 30.0
	top_light.spot_attenuation = 0.4
	top_light.shadow_enabled = false
	top_light.light_cull_mask = Geo.VIS_ACTOR
	add_child(top_light)
	top_light.translation = Vector3(0, height + 1.8, 0)
	top_light.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(self)
	global_transform.origin = pos
	puppet = Net.active() and not Net.is_server()
	world.enemies.append(self)
	if hostile:
		add_to_group("hostile")
	if chase_sound != "":
		chase_player = Audio.attach(chase_sound, self, -60.0, 80.0)
		chase_player.translation.y = height * 0.6
	_after_setup()
	return self


func _after_setup() -> void:
	pass


## Call when this brainrot spots the player: stinger + chase music kicks in.
func alert() -> void:
	if _stinger_cd <= 0.0:
		_stinger_cd = 10.0
		if world.player and _local_dist() < 30.0:
			Audio.play("stinger", -4.0)
			world.player.add_trauma(0.35)
	aggro_target = 1.0


func think(_delta: float) -> void:
	pass


func _animate(_delta: float, _spd: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if world == null:
		return
	if kill_t >= 0.0:
		kill_t += delta
		var to = kill_at - global_transform.origin
		to.y = 0.0
		face_dir(to, delta, 14.0)
		if kill_t > kill_len:
			kill_t = -1.0
	if pinned:
		_animate(delta, 0.0)
		return
	if puppet:
		_puppet_step(delta)
		return
	want = Vector3.ZERO
	if not world.dying and not frozen and kill_t < 0.0:
		think(delta)
	var hv = Vector3(velocity.x, 0, velocity.z).linear_interpolate(want, clamp(delta * 10.0, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = velocity.y - 20.0 * delta if not is_on_floor() else -0.5
	velocity = move_and_slide(velocity, Vector3.UP)
	_animate(delta, hv.length())
	_flick -= delta
	if _flick <= 0.0:
		_flick = rand_range(0.05, 0.6)
		top_light.light_energy = light_energy * (rand_range(0.1, 0.5) if randf() < 0.12 else 1.0)
	if hostile and not world.dying and not frozen and kill_t < 0.0:
		check_catch()
	_stinger_cd -= delta
	aggro = move_toward(aggro, aggro_target, delta * (2.0 if aggro_target > aggro else 0.35))
	if chase_player:
		Audio.set_base_volume(chase_player, lerp(-45.0, 3.0, aggro) if aggro > 0.01 else -80.0)


# ------------------------------------------------------------------ network
## Small int the server sends every tick (state machine etc.). Override.
func net_state() -> int:
	return 0


func apply_net_state(_s: int) -> void:
	pass


func net_apply(pos: Vector3, yaw: float, st: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if not _net_have:
		_net_have = true
		global_transform.origin = pos
		rotation.y = yaw
	if st != net_state():
		apply_net_state(st)


## Everyone sees it: turn to the victim and kill them (the hit lands at kill_hit).
func play_kill(at: Vector3) -> void:
	kill_t = 0.0
	kill_at = at


func _puppet_step(delta: float) -> void:
	var o = global_transform.origin
	var k = clamp(delta * 10.0, 0.0, 1.0)
	var np = o.linear_interpolate(_net_pos, k) if _net_have else o
	global_transform.origin = np
	rotation.y = lerp_angle(rotation.y, _net_yaw, k)
	var v = (np - o) / max(delta, 0.0001)
	_pspd = lerp(_pspd, Vector2(v.x, v.z).length(), clamp(delta * 8.0, 0.0, 1.0))
	_animate(delta, _pspd)
	_flick -= delta
	if _flick <= 0.0:
		_flick = rand_range(0.05, 0.6)
		top_light.light_energy = light_energy * (rand_range(0.1, 0.5) if randf() < 0.12 else 1.0)
	_stinger_cd -= delta
	aggro = move_toward(aggro, aggro_target, delta * (2.0 if aggro_target > aggro else 0.35))
	if chase_player:
		Audio.set_base_volume(chase_player, lerp(-45.0, 3.0, aggro) if aggro > 0.01 else -80.0)


# ------------------------------------------------------------------ movement
func move_to(target: Vector3, spd: float, delta: float) -> bool:
	_repath -= delta
	var pos = global_transform.origin
	if _repath <= 0.0 or target.distance_to(_last_target) > 1.5:
		_repath = 0.35
		_last_target = target
		if nav:
			_path = nav.path(pos, target)
		else:
			_path = PoolVector3Array([target])
		_path_i = 0
	var goal = target
	while _path_i < _path.size():
		var wp: Vector3 = _path[_path_i]
		if Vector2(wp.x - pos.x, wp.z - pos.z).length() < 0.45:
			_path_i += 1
		else:
			goal = wp
			break
	var d = Vector3(goal.x - pos.x, 0, goal.z - pos.z)
	if d.length() < 0.3:
		return true
	want = d.normalized() * spd
	face_dir(d, delta)
	return false


func face_dir(d: Vector3, delta: float, rate := 8.0) -> void:
	if d.length() < 0.01:
		return
	var yaw = atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, clamp(delta * rate, 0.0, 1.0))


# ------------------------------------------------------------------ senses
## Distance to the local operative (for effects on this machine only).
func _local_dist() -> float:
	if world.player == null or world.my_out:
		return 1e9
	var p: Vector3 = world.player.global_transform.origin
	var o = global_transform.origin
	return Vector2(p.x - o.x, p.z - o.z).length()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Nearest operative still inside (server: anyone; puppet: you).
func dist_to_player() -> float:
	if puppet:
		return _local_dist()
	var best = 1e9
	for t in world.targets(sector):
		best = min(best, _flat(t.pos, global_transform.origin))
	return best


func eye() -> Vector3:
	return global_transform.origin + Vector3(0, height * 0.85, 0)


## Can it see any operative? Remembers who, so it chases that one.
func sees_player(max_dist := 20.0) -> bool:
	var from = eye()
	var best = 1e9
	var seen = -1
	for t in world.targets(sector):
		var d = from.distance_to(t.eye)
		if d > max_dist or d > best:
			continue
		var ex = [self]
		if world.player:
			ex.append(world.player)
		if get_world().direct_space_state.intersect_ray(from, t.eye, ex, Geo.LAYER_WORLD).empty():
			best = d
			seen = t.id
	if seen >= 0:
		chase_id = seen
		return true
	return false


## Where to run: the hunted / chased operative if still inside, else the nearest one.
func target_pos() -> Vector3:
	for want_id in [hunt_id, chase_id]:
		if want_id >= 0:
			var t = world.target_by_id(want_id, sector)
			if t != null:
				return t.pos
	var best = 1e9
	var at = global_transform.origin
	for t in world.targets(sector):
		var d = _flat(t.pos, global_transform.origin)
		if d < best:
			best = d
			at = t.pos
	return at


## Is the local operative looking at it? (drain, blinking)
func seen_by_player(max_angle := 45.0, max_dist := 60.0) -> bool:
	if world.player == null or world.my_out:
		return false
	return world.player.can_see(global_transform.origin + Vector3(0, height * 0.6, 0), max_angle, max_dist, [self])


func check_catch() -> void:
	for t in world.targets(sector):
		if _flat(t.pos, global_transform.origin) < catch_dist and abs(t.pos.y - global_transform.origin.y) < 2.5:
			world.catch_target(t.id, model_id, death_msg, world.enemies.find(self))


func random_target() -> Vector3:
	if nav:
		return nav.random_open(world.rng, global_transform.origin.y)
	return global_transform.origin + Vector3(rand_range(-10, 10), 0, rand_range(-10, 10))
