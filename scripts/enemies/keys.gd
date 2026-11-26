extends Enemy
## KEYS — tall golden keys with faces. They only move when nobody is looking at them.
## Watched, they are dead still. Unwatched, they hop on their tips, fast, and the jingle gets closer.
## One of them is the master key: it does not hunt, it flees. Keep it in sight, walk up to it and
## take it (e): the exit unlocks for everyone, and the others stop being patient.

const KeysModel = preload("res://scripts/keys_model.gd")

var master = false
var taken = false
var enraged = false
var observed = false
var dormant = 9.0
var _hop = 0.0
var _land = false
var _lean = 0.0
var _body: Spatial
var _glow: OmniLight
var stun = 0.0            # seconds the camera flash keeps it frozen
var _flee_goal = Vector3.ZERO
var _flee_t = 0.0


func _init() -> void:
	death_msg = "the keys found you.\nyou looked away."
	chase_sound = "chase_keys"
	catch_dist = 1.05
	light_energy = 0.0
	drains = false


func _after_setup() -> void:
	_body = model.find_node("key", true, false)
	top_light.visible = false


## The master key: brighter, warmer, it hums.
func make_master() -> void:
	master = true
	model.set_meta("photo_id", "master key")
	hostile = false
	remove_from_group("hostile")
	if world.headless:
		return
	KeysModel.make_glow(model)
	_glow = OmniLight.new()
	_glow.light_color = Color(1.0, 0.72, 0.3)
	_glow.light_energy = 1.6
	_glow.omni_range = 3.5
	_glow.light_cull_mask = Geo.VIS_ACTOR | 1
	add_child(_glow)
	_glow.translation = Vector3(0, 1.4, -0.4)


# ------------------------------------------------------------------ server brain
## Is any operative looking at this key right now (view cone + line of sight)?
func _watched() -> bool:
	var me = global_transform.origin + Vector3(0, 1.3, 0)
	for t in world.targets():
		if not t.has("fwd"):
			continue
		var to: Vector3 = me - t.eye
		var d = to.length()
		if d > 45.0:
			continue
		if t.fwd.dot(to / d) < cos(deg2rad(52.0)):
			continue
		var ex = [self]
		if world.player:
			ex.append(world.player)
		if get_world().direct_space_state.intersect_ray(t.eye, me, ex, Geo.LAYER_WORLD).empty():
			return true
	return false


func think(delta: float) -> void:
	if taken:
		return
	stun -= delta
	observed = stun > 0.0 or _watched()
	dormant -= delta
	if observed or dormant > 0.0:
		velocity = Vector3.ZERO          # not a slide, not a twitch: still
		aggro_target = 0.0
		return
	if master:
		# flee: hop away from the nearest operative
		var best = null
		var bd = 1e9
		for t in world.targets():
			var dd = t.pos.distance_to(global_transform.origin)
			if dd < bd:
				bd = dd
				best = t
		if best and bd < 14.0:
			var away = global_transform.origin + (global_transform.origin - best.pos).normalized() * 6.0
			if world.nav:
				var c: Vector2 = world.nav.to_cell(away)
				if c.x < 0 or c.y < 0 or c.x >= world.nav.w or c.y >= world.nav.h or not world.nav.is_open(away):
					if _flee_t <= 0.0:
						_flee_goal = world.nav.random_open(world.rng, global_transform.origin.y)
						_flee_t = 3.0
					away = _flee_goal
			_flee_t -= delta
			move_to(away, 3.2, delta)
		return
	aggro_target = 1.0
	move_to(target_pos(), 6.2 if enraged else 4.6, delta)


func check_catch() -> void:
	if master or taken or observed or dormant > 0.0:
		return
	.check_catch()


func is_threat() -> bool:
	return not master and not taken and aggro > 0.3


# ------------------------------------------------------------------ network
func net_state() -> int:
	return (1 if velocity.length() > 0.2 else 0) | (2 if taken else 0) | (4 if master else 0) | (8 if enraged else 0)


func apply_net_state(s: int) -> void:
	if s & 4 and not master:
		make_master()
	enraged = s & 8 != 0
	aggro_target = 1.0 if s & 1 and not master else 0.0
	if s & 2 and not taken:
		set_taken()


func set_taken() -> void:
	taken = true
	visible = false
	velocity = Vector3.ZERO
	if chase_player:
		chase_player.stop()
	for c in get_children():
		if c is CollisionShape:
			c.disabled = true


# ------------------------------------------------------------------ body language
## Hops on its tip while it moves; perfectly still the moment it is seen.
func _animate(delta: float, spd: float) -> void:
	if _body == null:
		return
	if spd < 0.25:
		_hop = 0.0
		_lean = 0.0
		_body.translation = Vector3.ZERO
		_body.rotation = Vector3.ZERO
		return
	_hop += delta * (2.6 + spd * 0.55)
	var ph = fmod(_hop, 1.0)
	var air = sin(ph * PI)
	_body.translation.y = air * (0.1 + 0.03 * spd)
	_lean = lerp(_lean, clamp(spd / 6.0, 0.0, 1.0) * 0.22, clamp(delta * 8.0, 0.0, 1.0))
	_body.rotation = Vector3(-_lean - air * 0.05, 0, sin(_hop * PI) * 0.05)
	var landed = ph < 0.12
	if landed and not _land and world.player and not world.headless:
		Audio.play_at("key_hop", global_transform.origin, world, -6.0, rand_range(0.9, 1.15), 40.0)
	_land = landed
