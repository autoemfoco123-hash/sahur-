class_name Uncanny
extends Spatial
## The things that make a level feel wrong. (Godot 3)
## - Watchers: standing in the distance, staring. Look at them and they're gone. No sound.
## - T-posers: faceless figures that are always facing you when you look back.
## - Distant events: slams, whispers, running, a radio, something laughing.
## - Blackouts: every light dies. When they come back, something is closer.
## - Behind you: the world goes quiet. Something is standing right behind you.

var world
var lights = []
var watcher_ids = ["tung"]
var max_watchers = 2
var events = ["ev_slam", "ev_groan", "ev_run", "ev_whisper", "ev_tung", "ev_laugh", "ev_radio", "ev_drip", "ev_knock", "ev_thud"]
var event_range = Vector2(10.0, 24.0)
var floor_y = 0.0
var blackout_range = Vector2(55.0, 100.0)
var blackouts = true

var nav                   # the sector's NavGrid (one Uncanny per sector you are in)
var _watchers = []
var _tposers = []
var _event_t = 8.0
var _respawn_t = 10.0
var _blackout_t = 70.0
var _behind_t = 75.0
var _behind = null
var _behind_seen = 0.0
var _behind_life = 0.0


func setup(w, opts := {}) -> void:
	world = w
	nav = w.nav
	for k in opts:
		set(k, opts[k])
	world.add_child(self)
	_blackout_t = rand_range(blackout_range.x, blackout_range.y)


## Leaving the sector takes its ghosts along.
func _exit_tree() -> void:
	for n in _watchers + _tposers:
		if is_instance_valid(n):
			n.queue_free()
	_watchers.clear()
	_tposers.clear()
	if _behind != null and is_instance_valid(_behind):
		_behind.queue_free()
		_behind = null
		Audio.set_silence(false)


func add_tposers(n: int) -> void:
	for i in n:
		var p = _far_point(16.0)
		if p == Vector3.INF:
			continue
		var t = Models2.tposer()
		world.add_child(t)
		t.global_transform.origin = p
		_tposers.append(t)


func _far_point(min_dist: float) -> Vector3:
	if nav == null:
		return Vector3.INF
	for i in 40:
		var p: Vector3 = nav.random_open(world.rng, floor_y)
		if p.distance_to(world.player.global_transform.origin) > min_dist and not world.player.can_see(p + Vector3(0, 1.5, 0), 60.0, 200.0):
			return p
	return Vector3.INF


func _spawn_watcher(at := Vector3.INF) -> void:
	var p = at if at != Vector3.INF else _far_point(22.0)
	if p == Vector3.INF:
		return
	var w = Spatial.new()
	var m = Brainrots.build(watcher_ids[randi() % watcher_ids.size()])
	w.add_child(m)
	world.add_child(w)
	w.global_transform.origin = p
	w.set_meta("seen", 0.0)
	w.set_meta("h", float(m.get_meta("height")))
	_watchers.append(w)


func _vanish(w) -> void:
	_watchers.erase(w)
	w.queue_free()
	_respawn_t = rand_range(14.0, 35.0)


func _process(delta: float) -> void:
	if world == null or world.player == null or world.dying:
		return
	var pl = world.player
	var pp: Vector3 = pl.global_transform.origin
	for w in _watchers.duplicate():
		var to: Vector3 = pp - w.global_transform.origin
		w.rotation.y = atan2(-to.x, -to.z)
		var head: Vector3 = w.global_transform.origin + Vector3(0, float(w.get_meta("h")) * 0.8, 0)
		if to.length() < 11.0:
			_vanish(w)
			continue
		if pl.can_see(head, 28.0, 80.0):
			w.set_meta("seen", float(w.get_meta("seen")) + delta)
			Game.brain_cells = max(0.0, Game.brain_cells - delta * 1.5)
			if float(w.get_meta("seen")) > 0.45:
				_vanish(w)
	_respawn_t -= delta
	if _respawn_t <= 0.0 and _watchers.size() < max_watchers:
		_respawn_t = rand_range(10.0, 25.0)
		_spawn_watcher()
	for t in _tposers:
		if not pl.can_see(t.global_transform.origin + Vector3(0, 1.2, 0), 70.0, 200.0):
			var to2: Vector3 = pp - t.global_transform.origin
			t.rotation.y = atan2(-to2.x, -to2.z)
	_event_t -= delta
	if _event_t <= 0.0 and events.size() > 0:
		_event_t = rand_range(event_range.x, event_range.y)
		var ang = randf() * TAU
		var p = pp + Vector3(cos(ang), 0, sin(ang)) * rand_range(16.0, 40.0) + Vector3(0, 1.5, 0)
		Audio.play_at(events[randi() % events.size()], p, world, rand_range(-6.0, 0.0), rand_range(0.85, 1.05), 90.0)
	_behind_t -= delta
	if _behind == null and _behind_t <= 0.0:
		_behind_t = rand_range(70.0, 130.0)
		_spawn_behind()
	if _behind != null:
		_behind_life -= delta
		if pl.can_see(_behind.global_transform.origin + Vector3(0, 1.8, 0), 35.0, 30.0):
			_behind_seen += delta
		if _behind_seen > 0.6 or _behind_life <= 0.0:
			_behind.queue_free()
			_behind = null
			Audio.set_silence(false)
	if blackouts and lights.size() > 0:
		_blackout_t -= delta
		if _blackout_t <= 0.0:
			_blackout_t = rand_range(blackout_range.x, blackout_range.y)
			_blackout()


func _blackout() -> void:
	Audio.play("ev_thud", -2.0, 0.6)
	for l in lights:
		if is_instance_valid(l):
			Geo.lamp_set_on(l, false)
	var pl = world.player
	var fwd: Vector3 = -pl.cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var spot: Vector3 = pl.global_transform.origin + fwd * rand_range(13.0, 17.0)
	spot.y = floor_y
	if (nav == null or nav.is_open(spot)) and _watchers.size() <= max_watchers:
		var clear: bool = pl.get_world().direct_space_state.intersect_ray(pl.eye_pos(), spot + Vector3(0, 1.5, 0), [pl], Geo.LAYER_WORLD).empty()
		if clear:
			get_tree().create_timer(1.2).connect("timeout", self, "_spawn_watcher", [spot])
	get_tree().create_timer(1.6).connect("timeout", self, "_lights_back")


func _lights_back() -> void:
	for l in lights:
		if is_instance_valid(l):
			Geo.lamp_set_on(l, true)
	Audio.play("flash_on", -8.0, 0.5)


func _spawn_behind() -> void:
	var pl = world.player
	var back: Vector3 = pl.cam.global_transform.basis.z
	back.y = 0
	back = back.normalized()
	var spot: Vector3 = pl.global_transform.origin + back * 2.6
	if nav and not nav.is_open(spot):
		return
	if not pl.get_world().direct_space_state.intersect_ray(pl.eye_pos(), spot + Vector3(0, 1.4, 0), [pl], Geo.LAYER_WORLD).empty():
		return
	var m = Brainrots.build(watcher_ids[randi() % watcher_ids.size()])
	world.add_child(m)
	m.global_transform.origin = Vector3(spot.x, pl.global_transform.origin.y, spot.z)
	var to: Vector3 = pl.global_transform.origin - m.global_transform.origin
	m.rotation.y = atan2(-to.x, -to.z)
	_behind = m
	_behind_seen = 0.0
	_behind_life = 9.0
	Audio.set_silence(true)
