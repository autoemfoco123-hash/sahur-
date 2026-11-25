class_name Uncanny
extends Node3D
## The things that make a level feel wrong.
## - Watchers: brainrots standing in the dark, staring. Look at them and they're gone.
## - T-posers: faceless figures that are always facing you when you look back.
## - ERROR: it's just there.
## - Distant events: slams, whispers, running, a radio, something laughing.
## - Blackouts: every light dies. When they come back, something is closer.

var world: World
var lights: Array = []
var watcher_ids: Array = ["tung"]
var max_watchers := 2
var events: Array = ["ev_slam", "ev_groan", "ev_run", "ev_whisper", "ev_tung", "ev_laugh", "ev_radio", "ev_drip", "ev_knock", "ev_thud"]
var event_range := Vector2(10.0, 24.0)
var floor_y := 0.0
var blackout_range := Vector2(55.0, 100.0)
var blackouts := true
var nv_chance := 0.4

var _watchers := []
var _tposers := []
var _event_t := 8.0
var _respawn_t := 10.0
var _blackout_t := 70.0
var _behind_t := 75.0
var _behind: Node3D
var _behind_seen := 0.0
var _behind_life := 0.0
var behind_ids: Array = []


func setup(w: World, opts := {}) -> Uncanny:
	world = w
	for k in opts:
		set(k, opts[k])
	world.add_child(self)
	_blackout_t = randf_range(blackout_range.x, blackout_range.y)
	return self


func add_tposers(n: int, mat: Material = null) -> void:
	for i in n:
		var p := _far_point(16.0)
		if p == Vector3.INF:
			continue
		var t := Models2.tposer(mat)
		world.add_child(t)
		t.global_position = p
		_tposers.append(t)


func add_error(pos: Vector3, rot_y := 0.0) -> void:
	var l := Geo.label3d(world, "ERROR", pos, 160, Color(1, 0.05, 0.05), rot_y, true)
	l.double_sided = true
	l.pixel_size = 0.006
	l.font = UI.title_font()
	l.set_meta("base_y", pos.y)
	l.add_to_group("rot_error")


func _far_point(min_dist: float) -> Vector3:
	if world.nav == null:
		return Vector3.INF
	for i in 40:
		var p: Vector3 = world.nav.random_open(world.rng, floor_y)
		if p.distance_to(world.player.global_position) > min_dist and not world.player.can_see(p + Vector3(0, 1.5, 0), 60.0, 200.0):
			return p
	return Vector3.INF


func _spawn_watcher(at := Vector3.INF) -> void:
	var p := at if at != Vector3.INF else _far_point(22.0)
	if p == Vector3.INF:
		return
	var w := Node3D.new()
	var id: String = watcher_ids[randi() % watcher_ids.size()]
	var m := Models.build(id)
	if id == "saturnita" or id == "bombardiro" or id == "gusini":
		m.scale = Vector3.ONE * 0.3
	w.add_child(m)
	# No light, no sound. It is just standing there.
	world.add_child(w)
	w.global_position = p
	w.set_meta("seen", 0.0)
	w.set_meta("h", float(m.get_meta("height", 2.0)))
	_watchers.append(w)


func _vanish(w: Node3D) -> void:
	# No sound. It's just not there anymore.
	_watchers.erase(w)
	w.queue_free()
	_respawn_t = randf_range(14.0, 35.0)


func _process(delta: float) -> void:
	if world == null or world.player == null or world.dying:
		return
	var pl := world.player
	var pp := pl.global_position
	# Watchers
	for w in _watchers.duplicate():
		var to: Vector3 = pp - w.global_position
		w.rotation.y = atan2(-to.x, -to.z)
		var head: Vector3 = w.global_position + Vector3(0, float(w.get_meta("h")) * 0.8, 0)
		var d := to.length()
		if d < 11.0:
			_vanish(w)
			continue
		if pl.can_see(head, 28.0, 80.0):
			w.set_meta("seen", float(w.get_meta("seen")) + delta)
			Game.brain_cells = maxf(0.0, Game.brain_cells - delta * 1.5)
			if float(w.get_meta("seen")) > 0.45:
				_vanish(w)
	_respawn_t -= delta
	if _respawn_t <= 0.0 and _watchers.size() < max_watchers:
		_respawn_t = randf_range(10.0, 25.0)
		_spawn_watcher()
	# T-posers turn toward you whenever you're not looking
	for t in _tposers:
		if not pl.can_see(t.global_position + Vector3(0, 1.2, 0), 70.0, 200.0):
			var to2: Vector3 = pp - t.global_position
			t.rotation.y = atan2(-to2.x, -to2.z)
	for e in get_tree().get_nodes_in_group("rot_error"):
		e.position.y = float(e.get_meta("base_y")) + sin(Time.get_ticks_msec() * 0.001) * 0.08
	# Distant events
	_event_t -= delta
	if _event_t <= 0.0 and events.size() > 0:
		_event_t = randf_range(event_range.x, event_range.y)
		var ang := randf() * TAU
		var p := pp + Vector3(cos(ang), 0, sin(ang)) * randf_range(16.0, 40.0) + Vector3(0, 1.5, 0)
		Audio.play_at(events[randi() % events.size()], p, world, randf_range(-6.0, 0.0), randf_range(0.85, 1.05), 90.0)
	# Something stands right behind you, and the world goes quiet.
	_behind_t -= delta
	if _behind == null and _behind_t <= 0.0:
		_behind_t = randf_range(70.0, 130.0)
		_spawn_behind()
	if _behind:
		_behind_life -= delta
		var head2: Vector3 = _behind.global_position + Vector3(0, 1.8, 0)
		if pl.can_see(head2, 35.0, 30.0):
			_behind_seen += delta
		if _behind_seen > 0.6 or _behind_life <= 0.0:
			_behind.queue_free()
			_behind = null
			Audio.set_silence(false)
	# Blackouts
	if blackouts and lights.size() > 0:
		_blackout_t -= delta
		if _blackout_t <= 0.0:
			_blackout_t = randf_range(blackout_range.x, blackout_range.y)
			_blackout()


func _blackout() -> void:
	Audio.play("ev_thud", -2.0, 0.6)
	for l in lights:
		if is_instance_valid(l):
			l.set_meta("was", l.visible)
			l.visible = false
	var pl := world.player
	var fwd := -pl.cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var spot := pl.global_position + fwd * randf_range(13.0, 17.0)
	spot.y = floor_y
	var ok := world.nav == null or world.nav.is_open(spot)
	if ok and _watchers.size() < max_watchers + 1:
		var q := PhysicsRayQueryParameters3D.create(pl.eye_pos(), spot + Vector3(0, 1.5, 0), Geo.LAYER_WORLD)
		if pl.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			get_tree().create_timer(1.2).timeout.connect(func(): _spawn_watcher(spot))
	get_tree().create_timer(1.6).timeout.connect(func():
		for l in lights:
			if is_instance_valid(l):
				l.visible = l.get_meta("was", true)
		Audio.play("flash_on", -8.0, 0.5))



func _spawn_behind() -> void:
	var pl := world.player
	var back := pl.cam.global_basis.z
	back.y = 0
	back = back.normalized()
	var spot := pl.global_position + back * 2.6
	if world.nav and not world.nav.is_open(spot):
		return
	var q := PhysicsRayQueryParameters3D.create(pl.eye_pos(), spot + Vector3(0, 1.4, 0), Geo.LAYER_WORLD)
	if not pl.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return
	var ids := behind_ids if behind_ids.size() > 0 else watcher_ids
	var m := Models.build(ids[randi() % ids.size()])
	if float(m.get_meta("height", 2.0)) > 4.0:
		m.scale = Vector3.ONE * (3.0 / float(m.get_meta("height", 2.0)))
	world.add_child(m)
	m.global_position = Vector3(spot.x, pl.global_position.y, spot.z)
	var to := pl.global_position - m.global_position
	m.rotation.y = atan2(-to.x, -to.z)
	_behind = m
	_behind_seen = 0.0
	_behind_life = 9.0
	Audio.set_silence(true)
