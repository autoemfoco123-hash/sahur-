extends SceneTree
## Records a whole run, from the menu to the way out: every sector, every mission. Frame by
## frame in game time (run with --fixed-fps 30), with the sound logged for tools/mix_log.py.
## Sector 0 uses a few cuts (a quick fade) between its tapes; from sector 1 to the end it is
## one continuous take: the operative walks everywhere, through the key rooms, across the
## whole field, and through the 67 maze, waiting at its gates for the calls that open them.
## Frames are dumped raw and encoded in the background in segments (seg_NNN.mp4).
##   godot3 --path . --fixed-fps 30 --resolution 1280x720 high -s tools/fullrun_rec.gd out=DIR [dry]
## dry: no frames, no audio log (to check the scenario quickly at a small resolution).

const FPS = 30.0
const SEG = 600
const C = 4.0       # maze cell size (level_0.gd)

var out = "/tmp/fullrun"
var dry = false
var n = 0
var t = 0.0
var max_t = 1500.0
var log_f: File
var seen = {}
var phase = "menu"
var done_t = -1.0
var seg = 0
var seg_n = 0
var raw: File
var raw_fmt = ""
var raw_w = 0
var raw_h = 0
var _dir_started = false
var _mv = {}        # walking: {pts, i, r, speed}
var _look = null    # a point to keep the eyes on (smoothly)
var _stuck_t = 0.0
var _stuck_at = Vector3.ZERO
var start_sector = 0
var map_seed = -1


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("secs="):
			max_t = float(a.substr(5))
		elif a == "dry":
			dry = true
		elif a.begins_with("seed="):
			map_seed = int(a.substr(5))
		elif a.begins_with("start="):
			start_sector = int(a.substr(6))
	Directory.new().make_dir_recursive(out)
	if not dry:
		log_f = File.new()
		log_f.open(out + "/audio.jsonl", File.WRITE)


func _net():
	return root.get_node("Net")


func _w():
	return _net().world


func _idle(_d: float) -> bool:
	n += 1
	t = (n - 1) / FPS
	if n == 2:
		change_scene("res://scenes/menu.tscn")
	_menu()
	_steer()
	if n > 2 and not dry:
		_shot()
		_log_audio()
	if n % 150 == 0:
		var w = _w()
		var ms = ""
		if w and w.level:
			for m in w.levels[w.my_sector].missions:
				ms += "%s=%s%s " % [m.id, str(m.progress), "+" if m.done else ""]
		var pos = str(w.player.global_transform.origin.round()) if w and w.player else ""
		print("rec t=%.1f phase=%s sector=%s %s pos=%s" % [t, phase, str(w.my_sector) if w else "-", ms, pos])
	var stop = t >= max_t or (done_t > 0.0 and t > done_t)
	if stop:
		_finish()
	return stop


# ------------------------------------------------------------------ menu -> world
func _menu() -> void:
	var net = _net()
	var menu = root.find_node("Menu", true, false)
	if phase == "menu":
		if t >= 2.4 and menu and menu.host_box and not menu.host_box.visible and not net.active():
			menu._show("host")
			menu.host_name.text = "lantern"
		if t >= 3.6 and not net.active() and menu:
			menu._do_host()
		if t >= 5.2 and net.active() and net.counting < 0 and net.state == net.LOBBY:
			net.level_id = str(start_sector)
			net.seed_override = map_seed
			net.force_start()
			phase = "countdown"
	elif phase == "countdown":
		var w = _w()
		if w and w.player and w.level and not _dir_started:
			_dir_started = true
			phase = "run"
			_director()


# ------------------------------------------------------------------ helpers
func _wait(sec: float):
	for i in int(max(1.0, round(sec * FPS))):
		yield(self, "idle_frame")


func _fade_out():
	_w().hud.fade(1.0, 0.25)
	yield(_wait(0.32), "completed")


func _fade_in():
	_w().hud.fade(0.0, 0.35)
	yield(_wait(0.2), "completed")


## Every frame: walk toward the current waypoint, keep the eyes on what matters.
func _steer() -> void:
	var w = _w()
	if w == null or w.player == null:
		return
	var pl = w.player
	if not _mv.empty():
		var pos: Vector3 = pl.global_transform.origin
		var pts: Array = _mv.pts
		while _mv.i < pts.size() - 1 and Vector2(pts[_mv.i].x - pos.x, pts[_mv.i].z - pos.z).length() < 0.9:
			_mv.i += 1
		var goal: Vector3 = pts[_mv.i]
		# look a little ahead along the way, so corners are taken smoothly
		var aim = goal
		if _mv.i + 1 < pts.size():
			var dg = Vector2(goal.x - pos.x, goal.z - pos.z).length()
			aim = goal.linear_interpolate(pts[_mv.i + 1], clamp((2.2 - dg) / 2.2, 0.0, 0.5))
		var d = Vector2(goal.x - pos.x, goal.z - pos.z)
		if _mv.i == pts.size() - 1 and d.length() < _mv.r:
			Input.action_release("move_forward")
			_mv = {}
		else:
			var da = Vector2(aim.x - pos.x, aim.z - pos.z)
			var yaw = atan2(-da.x, -da.y)
			if _look == null:
				pl._yaw = lerp_angle(pl._yaw, yaw, 0.14)
				pl._pitch = lerp(pl._pitch, -0.04, 0.06)
			else:
				# eyes elsewhere: walk by strafing toward the goal (the body still heads there)
				pass
			# the stick has a 0.5 dead zone: strength 0.5 + 0.5 * f walks at f of full speed
			if _look == null or abs(wrapf(pl._yaw - yaw, -PI, PI)) < 0.6:
				Input.action_press("move_forward", 0.5 + 0.5 * clamp(_mv.speed, 0.05, 1.0))
			else:
				Input.action_release("move_forward")
			# stuck on a corner: skip ahead
			_stuck_t += 1.0 / FPS
			if _stuck_t > 1.5:
				if pos.distance_to(_stuck_at) < 0.25 and _mv.i < pts.size() - 1:
					_mv.i += 1
				_stuck_t = 0.0
				_stuck_at = pos
	if _look != null:
		var to: Vector3 = _look - pl.eye_pos()
		pl._yaw = lerp_angle(pl._yaw, atan2(-to.x, -to.z), 0.12)
		pl._pitch = lerp(pl._pitch, atan2(to.y, Vector2(to.x, to.z).length()), 0.12)


func _go(pts: Array, radius := 0.8, speed := 1.0) -> void:
	_mv = {"pts": pts, "i": 0, "r": radius, "speed": speed}
	_stuck_t = 0.0


func _until_arrived(timeout := 60.0):
	var k = 0
	while not _mv.empty() and k < timeout * FPS:
		k += 1
		yield(self, "idle_frame")
	_mv = {}
	Input.action_release("move_forward")


## Walk there along the sector's navigation grid, stop radius metres short.
func _walk(to: Vector3, radius := 1.0, speed := 1.0, timeout := 60.0):
	var w = _w()
	var pts = [to]
	var nav = w.levels[w.my_sector].nav
	if nav:
		var p = nav.path(w.player.global_transform.origin, to)
		if p.size() > 0:
			pts = Array(p)
			pts.append(to)
	_go(pts, radius, speed)
	yield(_until_arrived(timeout), "completed")


## Cut (fade) to a spot, looking at a point. (sector 0 only)
func _cut(at: Vector3, look: Vector3):
	yield(_fade_out(), "completed")
	_place(at, look)
	yield(_wait(0.1), "completed")
	yield(_fade_in(), "completed")


func _place(at: Vector3, look: Vector3) -> void:
	var pl = _w().player
	pl.global_transform.origin = at + Vector3(0, 0.1, 0)
	pl.velocity = Vector3.ZERO
	var to = look - (at + Vector3(0, 1.6, 0))
	pl.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))


## A spot `dist` metres before `target` along the way from `from`, on open floor.
func _before(from: Vector3, target: Vector3, dist: float) -> Vector3:
	var w = _w()
	var nav = w.levels[w.my_sector].nav
	var p = Array(nav.path(from, target)) if nav else []
	if p.empty():
		return target + (from - target).normalized() * dist
	p.append(target)
	var acc = 0.0
	for i in range(p.size() - 1, 0, -1):
		var a: Vector3 = p[i]
		var b: Vector3 = p[i - 1]
		var seg_l = Vector2(a.x - b.x, a.z - b.z).length()
		if acc + seg_l >= dist:
			return a.linear_interpolate(b, (dist - acc) / max(seg_l, 0.001))
		acc += seg_l
	return p[0]


## Open floor around `c` at `dist`, with a clear line to `face` (eye height), nearest to `pref`.
func _spot_around(c: Vector3, dist: float, face: Vector3, pref := Vector3.INF) -> Vector3:
	var w = _w()
	var nav = w.levels[w.my_sector].nav
	var space = w.get_world().direct_space_state
	var best = c + Vector3(dist, 0, 0)
	var bs = -1e9
	for k in 24:
		var a = TAU * k / 24.0
		var p = c + Vector3(cos(a), 0, sin(a)) * dist
		if nav and not nav.is_open(p):
			continue
		var eye = p + Vector3(0, 1.6, 0)
		if not space.intersect_ray(eye, face, [w.player], 1).empty():    # 1: the world layer
			continue
		var s = 0.0 if pref == Vector3.INF else -p.distance_to(pref)
		if s > bs:
			bs = s
			best = p
	return best


func _face(m: Spatial) -> Vector3:
	return m.global_transform.xform(Vector3(0, m.get_meta("face_y"), 0))


## Look at it until the camera has settled, then take the photo.
func _portrait(m: Spatial, settle := 1.2):
	_look = _face(m)
	yield(_wait(settle), "completed")
	_w().photo.take()
	yield(_wait(1.9), "completed")
	_look = null


func _shout() -> void:
	var ev = InputEventAction.new()
	ev.action = "shout"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up = InputEventAction.new()
	up.action = "shout"
	up.pressed = false
	Input.parse_input_event(up)


func _mission_done(id: String) -> bool:
	var w = _w()
	for m in w.levels[w.my_sector].missions:
		if m.id == id:
			return m.done
	return false


func _full() -> void:
	root.get_node("Game").brain_cells = 100.0


## Walk up to sector s's sliding door, open it, walk through into the next sector.
func _door(s: int):
	var w = _w()
	var d = w.doors[s]
	var o: Vector3 = d.global_transform.origin
	var front = o + Vector3(-d.depth * 0.5 - 1.1, 0, 0)
	yield(_walk(front + Vector3(-1.4, 0, 0), 0.5, 1.0), "completed")
	_go([front], 0.25, 0.5)
	_look = o + Vector3(0, 1.4, 0)
	yield(_until_arrived(6.0), "completed")
	yield(_wait(0.7), "completed")
	w.door_use(d)
	yield(_wait(1.5), "completed")
	_look = null
	_go([o + Vector3(d.depth * 0.5 + 3.0, 0, 0)], 0.3, 0.8)
	yield(_until_arrived(10.0), "completed")


func _nearest_first(from: Vector3, items: Array) -> Array:
	var left = items.duplicate()
	var outl = []
	var at = from
	while not left.empty():
		var bi = 0
		for i in left.size():
			if at.distance_to(left[i][0]) < at.distance_to(left[bi][0]):
				bi = i
		outl.append(left[bi])
		at = left[bi][0]
		left.remove(bi)
	return outl


# ------------------------------------------------------------------ the run
func _director():
	yield(_wait(4.0), "completed")          # the goggles boot
	if start_sector <= 0:
		yield(_sector0(), "completed")
	if start_sector <= 1:
		yield(_sector1(), "completed")
	if start_sector <= 2:
		yield(_sector2(), "completed")
	yield(_sector3(), "completed")


func _sector0():
	var w = _w()
	var lv = w.levels[0]
	_full()
	lv.tung.frozen = true                  # he stays where he is while we film
	# walk the chalk; he calls, we answer, three times in a row
	var path: Array = lv.demo_path
	var pi = 1
	for k in 3:
		lv.call_timer = 0.6
		var shouted = false
		var waited = 0
		while waited < 13 * FPS:
			waited += 1
			if _mv.empty() and pi < path.size() - 2:
				pi += 1
				_go([path[pi]], 0.8, 0.55)
			if lv.calling and lv.call_t > 1.3 and not shouted:
				shouted = true
				_mv = {}
				Input.action_release("move_forward")
				_shout()
			if shouted and not lv.calling:
				break
			yield(self, "idle_frame")
		yield(_wait(1.2), "completed")
	_mv = {}
	Input.action_release("move_forward")
	lv.call_timer = 1e9                    # no more calls: three in a row was the mission
	# a portrait of him: he is right there in the corridor, the flash goes off in his face
	var pl = w.player
	var at = pl.global_transform.origin
	var tung = lv.tung
	var spot = _spot_around(at, 3.0, at + Vector3(0, 2.0, 0))
	yield(_fade_out(), "completed")
	tung.global_transform.origin = spot
	tung.look_at(at, Vector3.UP)
	tung.rotation.x = 0
	_place(at, _face(tung.model))
	yield(_fade_in(), "completed")
	yield(_portrait(tung.model, 1.4), "completed")
	# he woke up. run. (the tapes, one dead end after another)
	for i in lv.tapes.size():
		_full()
		var tp: Vector3 = lv.tapes[i]
		var from = _before(lv.spawn_pos, tp, 4.0)
		yield(_cut(from, tp + Vector3(0, 0.6, 0)), "completed")
		yield(_walk(tp, 1.0, 0.6), "completed")
		_look = tp + Vector3(0, 0.5, 0)
		yield(_wait(0.5), "completed")
		lv._take_tape(i)
		yield(_wait(1.3), "completed")
		_look = null
	yield(_wait(0.6), "completed")
	# to the door: the last cut. from here on, one take to the end
	var d = w.doors[0]
	var o: Vector3 = d.global_transform.origin
	yield(_cut(o + Vector3(-d.depth * 0.5 - 6.0, 0, 0), o + Vector3(0, 1.4, 0)), "completed")
	yield(_door(0), "completed")


func _sector1():
	var w = _w()
	var lv = w.levels[1]
	_full()
	for k in lv.keys:
		k.dormant = 1e9                    # they only move unwatched: we keep an eye on them all
	# where to stand for each key's photo (decided now, while they are out of sight)
	var shots = []
	for i in range(1, lv.keys.size()):
		var k = lv.keys[i]
		var kp: Vector3 = k.global_transform.origin
		var fwd = -k.global_transform.basis.z
		var spot = _spot_around(kp, 2.5, kp + Vector3(0, 1.6, 0), kp + fwd * 2.5)
		k.look_at(Vector3(spot.x, kp.y, spot.z), Vector3.UP)
		k.rotation.x = 0
		shots.append([spot, k])
	var pl = w.player
	shots = _nearest_first(pl.global_transform.origin, shots)
	yield(_wait(1.5), "completed")
	var stared = false
	for s in shots:
		_full()
		var k = s[1]
		yield(_walk(s[0], 0.35, 1.0), "completed")
		yield(_portrait(k.model, 1.2), "completed")
		if not stared:
			# hold its gaze, closer than 2 m, eight seconds
			stared = true
			var kp: Vector3 = k.global_transform.origin
			var close = kp + (s[0] - kp).normalized() * 1.5
			_look = _face(k.model)
			_go([close], 0.15, 0.35)
			var q = 0
			while not _mission_done("stare") and q < 16 * FPS:
				q += 1
				yield(self, "idle_frame")
			_mv = {}
			Input.action_release("move_forward")
			yield(_wait(0.8), "completed")
			_look = null
			_go([s[0]], 0.3, 0.5)
			yield(_until_arrived(4.0), "completed")
	# the master key: it glows. walk up and take it
	_full()
	var m = lv.master
	var mp: Vector3 = m.global_transform.origin
	yield(_walk(mp, 2.6, 1.0), "completed")
	_look = _face(m.model)
	_go([mp], 1.4, 0.4)
	yield(_until_arrived(6.0), "completed")
	yield(_wait(0.5), "completed")
	lv._grab()
	yield(_wait(2.2), "completed")
	_look = null
	yield(_door(1), "completed")


func _sector2():
	var w = _w()
	var lv = w.levels[2]
	_full()
	var pl = w.player
	# out into the field, the sky
	_look = pl.eye_pos() + Vector3(10, 3.5, -2)
	yield(_wait(2.2), "completed")
	_look = null
	var kp: Vector3 = lv.khaby.global_transform.origin
	# the beacons, nearest first, across the whole field (straight lines: it is open grass)
	var items = []
	for i in lv.beacons.size():
		items.append([lv.beacons[i], i])
	items = _nearest_first(pl.global_transform.origin, items)
	for it in items:
		_full()
		var b: Vector3 = it[0]
		_go(_around(pl.global_transform.origin, b, kp, 3.5), 2.4, 1.0)
		yield(_until_arrived(60.0), "completed")
		_look = b + Vector3(0, 1.0, 0)
		_go([b], 1.3, 0.4)
		yield(_until_arrived(4.0), "completed")
		yield(_wait(0.3), "completed")
		lv._take_beacon(it[1])
		yield(_wait(1.1), "completed")
		_look = null
	# to the mechanism: stand in front of it, a portrait, then talk
	var dir = -lv.khaby.global_transform.basis.z
	dir.y = 0
	var at = kp + dir.normalized() * 3.8
	_go(_around(pl.global_transform.origin, at, kp, 3.5), 0.3, 1.0)
	yield(_until_arrived(60.0), "completed")
	yield(_portrait(lv.khaby.model, 1.5), "completed")
	yield(_wait(1.2), "completed")
	lv._talk()
	var k = 0
	while w.my_sector == 2 and k < 60 * FPS:
		k += 1
		yield(self, "idle_frame")
	yield(_wait(1.5), "completed")


## A straight walk from a to b, stepping around a round obstacle at c (radius r).
func _around(a: Vector3, b: Vector3, c: Vector3, r: float) -> Array:
	var ab = Vector2(b.x - a.x, b.z - a.z)
	var ac = Vector2(c.x - a.x, c.z - a.z)
	var l = ab.length()
	if l < 0.01:
		return [b]
	var u = clamp(ac.dot(ab) / (l * l), 0.0, 1.0)
	var closest = Vector2(a.x, a.z) + ab * u
	var off = Vector2(c.x, c.z) - closest
	if off.length() > r or u <= 0.0 or u >= 1.0:
		return [b]
	var side = -off.normalized() if off.length() > 0.01 else Vector2(-ab.y, ab.x).normalized()
	var p = Vector2(c.x, c.z) + side * r * 1.3
	return [Vector3(p.x, a.y, p.y), b]


# ------------------------------------------------------------------ sector 3: the maze
func _cell_of(lv, p: Vector3) -> Vector2:
	return Vector2(clamp(floor((p.x - lv.origin.x) / C), 0, 11), clamp(floor((p.z - lv.origin.z) / C), 0, 11))


func _gate_between(lv, a: Vector2, b: Vector2):
	for g in lv.gates:
		if (g.a == a and g.b == b) or (g.a == b and g.b == a):
			return g
	return null


## Cells from a to b; with gates: only through the ones that are down right now.
func _route(lv, a: Vector2, b: Vector2, gates: bool) -> Array:
	var prev = {a: a}
	var q = [a]
	while not q.empty():
		var c: Vector2 = q.pop_front()
		if c == b:
			break
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var nb: Vector2 = c + d
			if prev.has(nb) or not lv._passable(c, nb):
				continue
			if gates:
				var g = _gate_between(lv, c, nb)
				if g and g.want < 0.5:
					continue
			prev[nb] = c
			q.append(nb)
	if not prev.has(b):
		return []
	var r = [b]
	while r[-1] != a:
		r.append(prev[r[-1]])
	r.invert()
	return r


## Walk through the maze to `to` (stop radius short). A gate in the way that is up: walk to it,
## wait for 67 to call its number (calling it a little sooner), then go on.
func _walk3(to: Vector3, radius := 0.8, speed := 1.0):
	var w = _w()
	var lv = w.levels[3]
	var tries = 0
	while tries < 30:
		tries += 1
		var pl = w.player
		var a = _cell_of(lv, pl.global_transform.origin)
		var b = _cell_of(lv, to)
		var r = _route(lv, a, b, true)
		if not r.empty():
			var pts = []
			for c in r:
				pts.append(lv._cell(c))
			pts.append(to)
			if pts.size() > 1 and r.size() > 1:
				pts.remove(0)      # we are already in the first cell
			_go(pts, radius, speed)
			var lay = lv.layout
			var k = 0
			while not _mv.empty() and lv.layout == lay and k < 60 * FPS:
				k += 1
				_full()
				yield(self, "idle_frame")
			if _mv.empty():
				return
			continue           # the maze changed under us: plan again
		# blocked: walk up to the first gate that is up, and wait for its number
		var full_r = _route(lv, a, b, false)
		var stop = a
		var gate = null
		for i in range(1, full_r.size()):
			var g = _gate_between(lv, full_r[i - 1], full_r[i])
			if g and g.want < 0.5:
				gate = g
				break
			stop = full_r[i]
		if gate == null:
			return
		var sr = _route(lv, a, stop, true)
		var pts = []
		for c in sr:
			pts.append(lv._cell(c))
		if pts.size() > 1:
			pts.remove(0)
		pts.append(lv._cell(stop))
		_go(pts, 0.6, speed)
		yield(_until_arrived(40.0), "completed")
		_look = gate.pos + Vector3(0, 1.3, 0)
		var lay = lv.layout
		lv._next_call = min(lv._next_call, 2.5)
		var k = 0
		while lv.layout == lay and k < 30 * FPS:
			k += 1
			_full()
			yield(self, "idle_frame")
		yield(_wait(1.0), "completed")     # the slab sinks
		_look = null


func _sector3():
	var w = _w()
	var lv = w.levels[3]
	_full()
	lv.ss.frozen = true
	var pl = w.player
	# get up, look around
	yield(_wait(2.5), "completed")
	# it calls, and when the picture turns back it is right there: its portrait
	lv._next_call = 0.0
	yield(_wait(1.42), "completed")
	var at = pl.global_transform.origin
	var spot = _spot_around(at, 3.8, at + Vector3(0, 1.6, 0), at - pl.global_transform.basis.z * 3.8)
	lv.ss.relocate(spot + Vector3(0, 0.1, 0))
	yield(_portrait(lv.ss.model, 1.3), "completed")
	yield(_wait(0.5), "completed")
	# the six and the seven, each in its dead end behind gates of its own number
	var nums = _nearest_first(pl.global_transform.origin, [[lv.numerals[6].pos, 6], [lv.numerals[7].pos, 7]])
	for it in nums:
		yield(_walk3(it[0], 1.3, 1.0), "completed")
		_look = it[0] + Vector3(0, 1.1, 0)
		yield(_wait(0.6), "completed")
		lv._take_num(it[1])
		yield(_wait(1.6), "completed")
		_look = null
	# the way out: through the maze to the door, and wait there for the last of its calls
	var d = w.doors[3]
	var o: Vector3 = d.global_transform.origin
	var front = o + Vector3(-d.depth * 0.5 - 1.6, 0, 0)
	yield(_walk3(front, 0.4, 1.0), "completed")
	_look = o + Vector3(0, 1.4, 0)
	var k = 0
	while not _mission_done("calls") and k < 120 * FPS:
		k += 1
		_full()
		if lv._next_call > 5.0:
			lv._next_call = 5.0
		yield(self, "idle_frame")
	yield(_wait(2.5), "completed")
	_go([o + Vector3(-d.depth * 0.5 - 1.0, 0, 0)], 0.2, 0.4)
	yield(_until_arrived(4.0), "completed")
	w.door_use(d)
	yield(_wait(1.5), "completed")
	_look = null
	_go([o + Vector3(6.0, 0, 0)], 0.3, 0.7)
	k = 0
	while not w.completing and k < 12 * FPS:
		k += 1
		yield(self, "idle_frame")
	_mv = {}
	Input.action_release("move_forward")
	done_t = t + 11.0


# ------------------------------------------------------------------ capture
func _shot() -> void:
	var img = root.get_texture().get_data()
	if seg_n == 0:
		raw = File.new()
		raw.open("%s/seg_%03d.raw" % [out, seg], File.WRITE)
		raw_fmt = "rgba" if img.get_format() == Image.FORMAT_RGBA8 else "rgb24"
		raw_w = img.get_width()
		raw_h = img.get_height()
	raw.store_buffer(img.get_data())
	seg_n += 1
	if seg_n >= SEG:
		_encode(false)


## Encode the current segment in the background (ffmpeg, then the raw file goes).
func _encode(wait: bool) -> void:
	if seg_n == 0:
		return
	raw.close()
	var r = "%s/seg_%03d.raw" % [out, seg]
	var mp4 = "%s/seg_%03d.mp4" % [out, seg]
	var cmd = "ffmpeg -y -loglevel error -f rawvideo -pix_fmt %s -s %dx%d -r 30 -i '%s' -vf vflip -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p '%s' && rm -f '%s'" % [raw_fmt, raw_w, raw_h, r, mp4, r]
	OS.execute("bash", ["-c", cmd], wait)
	seg += 1
	seg_n = 0


func _finish() -> void:
	Input.action_release("move_forward")
	if not dry:
		_encode(true)
		log_f.close()
	print("rec done t=%.1f frames=%d segments=%d" % [t, n - 3, seg])


func _players(nd: Node, acc: Array) -> void:
	if nd is AudioStreamPlayer or nd is AudioStreamPlayer3D:
		acc.append(nd)
	for c in nd.get_children():
		_players(c, acc)


func _log_audio() -> void:
	var au = root.get_node("Audio")
	var lst = []
	var cam = au.listener_cam
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
		var tr = cam.global_transform
		lst = [tr.origin.x, tr.origin.y, tr.origin.z, tr.basis.x.x, tr.basis.x.y, tr.basis.x.z]
	var m = AudioServer.get_bus_index("Master")
	var buses = [AudioServer.is_bus_mute(m), AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		AudioServer.is_bus_mute(AudioServer.get_bus_index("Amb")), AudioServer.get_bus_volume_db(m)]
	var fx = [au._dist.drive, au._lp.cutoff_hz, au._reverb.wet, au._reverb.room_size]
	var rows = []
	var ps = []
	_players(root, ps)
	for p in ps:
		if not p.playing or p.stream == null:
			continue
		var id = p.get_instance_id()
		var row = {"id": id, "s": p.stream.resource_path, "p": p.pitch_scale, "b": p.bus}
		if p is AudioStreamPlayer3D:
			var o = p.global_transform.origin
			row["k"] = "3d"
			row["v"] = p.unit_db
			row["x"] = [o.x, o.y, o.z]
			row["md"] = p.max_distance
			row["us"] = p.unit_size
			row["c"] = p.attenuation_filter_cutoff_hz
		else:
			row["k"] = "2d"
			row["v"] = p.volume_db
		if not seen.has(id):
			seen[id] = true
			row["new"] = true
			row["off"] = p.get_playback_position()
		rows.append(row)
	log_f.store_line(to_json({"f": n - 3, "L": lst, "B": buses, "fx": fx, "P": rows}))
	log_f.flush()
