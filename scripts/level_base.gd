class_name LevelBase
extends Node
## Base for every sector. Override build() and _physics_process for sector logic. (Godot 3)
## One round is one run through every sector, and they are built wall to wall along x: the
## east wall of a sector touches the west wall of the next, and a sliding door (slide_door.gd)
## goes through both. Open it and the next sector is simply there.
## Build everything relative to `origin` (use _cell / o2() / make_nav, which already add it),
## cut the doorways at entry_z (west wall, if has_entry) and exit_z (east wall), report extent,
## and put the static meshes under `geo` (world.gd hides a sector nobody can see into).

const DOOR_W = 1.3
const DOOR_H = 2.2
const MISSION_POINTS = 300

var world
var rng: RandomNumberGenerator
var index = 0               # this sector's number in the run
var origin = Vector3.ZERO   # where this sector sits in the shared world
var nav                     # this sector's NavGrid
var env_cfg = {}            # this sector's look (world.setup_env), applied when you are in it
var uncanny_cfg = {}        # this sector's uncanny setup (watchers, blackouts...), per operative
var greeter = ""            # brainrot waiting face to face for whoever comes through the door
var drain_rate = 0.0
var danger_bonus = 0.0
var boot_goggles = false
var spawn_pos = Vector3.ZERO
var spawn_yaw = 0.0
var arrive_pos = Vector3.INF   # where you stand after coming through the previous sector's door
var arrive_yaw = 0.0
var wave_started = false
var extent = Vector2.ZERO   # size on x/z (world.gd puts the next sector right after it)
var has_entry = false       # a door from the previous sector in the west wall...
var entry_z = 0.0           # ...at this world z
var exit_z = 0.0            # world z of the exit door in the east wall
var geo: Spatial            # this sector's static meshes
var has_exit_door = true    # false: this sector ends some other way (world.gd builds no door)
var mono = false            # monochrome sector: only the operatives keep their colour
var ending_text = ""        # what you read when the run ends here
var chalk = Color(0.9, 1.0, 0.9)   # colour of the hush marks on walls and floors
var wall_blockers = []      # spots on walls taken by something (hotel doors): no writing there
var missions = []           # [{id, text, goal, progress, done, fmt}] (team missions; the door opens when all are done)


func build() -> void:
	pass


## The local operative's view just moved into this sector (arrival, spawn, spectating, revive).
## Ambience, footsteps, dust. `boot`: the very start of the run (goggles power up).
func enter(_boot: bool) -> void:
	pass


## The goggles power up at the start of the run (whatever sector it starts in).
func boot_goggles_now() -> void:
	get_tree().create_timer(1.0).connect("timeout", self, "_boot_1")
	get_tree().create_timer(2.4).connect("timeout", self, "_boot_2")


func _boot_1() -> void:
	world.hud.subtitle("hush nv-7 · booting…", 1.6)


func _boot_2() -> void:
	if not world.dying:
		player().set_visor(true)
		world.hud.fade(0.0, 0.5)
		world.hud.subtitle("goggles locked · gyro calibrated · auto gain", 2.5)


## The first operative reached this sector (runs on every machine): wake it up.
func start_wave() -> void:
	wave_started = true


func o2() -> Vector2:
	return Vector2(origin.x, origin.z)


## The local operative is looking at this sector (subtitles, sounds that are not positional).
func here() -> bool:
	return world.player != null and world.view_sector == index


func env(cfg: Dictionary) -> void:
	env_cfg = cfg
	world.setup_env(cfg)


func killer_id() -> String:
	return "tung"


func player():
	return world.player


## Where the operatives start (world.gd places everyone around it).
func spawn_player(pos: Vector3, yaw := 0.0) -> void:
	spawn_pos = pos
	spawn_yaw = yaw


## Bounds are relative to the sector origin.
func make_nav(min_xz: Vector2, max_xz: Vector2, cell := 1.0):
	nav = NavGrid.new(min_xz + o2(), max_xz + o2(), cell)
	world.nav = nav
	return nav


func note(pos: Vector3, text: String) -> void:
	var m = Models2.note()
	world.add_child(m)
	m.global_transform.origin = pos
	var gl = Geo.omni(m, Vector3(0, 0.25, 0), Color(1, 0.85, 0.6), 0.4, 1.6)
	gl.light_cull_mask = Geo.VIS_ACTOR
	Models.set_layers(m, 1 | Geo.VIS_ACTOR)
	Interactable.make(world, pos + Vector3(0, 0.15, 0), 0.45, "read note", self, "_on_note", [text, m])


func _on_note(text: String, m: Spatial) -> void:
	world.show_note(text)
	if is_instance_valid(m):
		m.queue_free()


## Only the server (or an offline game) makes decisions; clients just watch.
func authority() -> bool:
	return not Net.active() or Net.is_server()


func enemy(script: Script, id: String, pos: Vector3, hostile := true):
	var e = script.new()
	e.setup(world, id, pos, hostile)
	return e


func ambient(sname: String, vol := -6.0, sname2 := "", vol2 := -12.0) -> void:
	Audio.ambient(sname, vol, 0)
	Audio.ambient(sname2, vol2, 1)


func scatter_points(count: int, avoid: Vector3, min_dist := 8.0, y := 0.0) -> Array:
	var out = []
	var tries = 0
	while out.size() < count and tries < 400:
		tries += 1
		var p: Vector3 = nav.random_open(rng, y)
		if p.distance_to(avoid) < min_dist:
			continue
		var ok = true
		for q in out:
			if p.distance_to(q) < 5.0:
				ok = false
				break
		if ok:
			out.append(p)
	return out


## hush chalk: only visible through the goggles (render layer 2).
func ir_mark(pos: Vector3, rot_y: float, text: String, size := 90) -> Label3D:
	var l = Geo.label3d(world, text, pos, size, chalk, rot_y)
	l.layers = 2
	return l



# ------------------------------------------------------------------ events and missions
## Sector events go to the same sector on every machine.
func _emit(type: String, args: Array) -> void:
	if Net.active():
		Net.event("sector", [index, type, args])
	else:
		net_event(type, args)


func net_event(_type: String, _args: Array) -> void:
	pass


## fmt: "count" (2/4) · "best" (best 62/85) · "secs" (3/8 s) · "" (nothing)
func add_mission(id: String, text: String, goal: float, fmt := "count") -> void:
	missions.append({"id": id, "text": text, "goal": goal, "progress": 0.0, "done": false, "fmt": fmt})


func _mission_index(id: String) -> int:
	for i in missions.size():
		if missions[i].id == id:
			return i
	return -1


func mission_progress(id: String) -> float:
	var i = _mission_index(id)
	return missions[i].progress if i >= 0 else 0.0


## Server (or offline): set a mission's progress; it completes at its goal. pid gets the bonus.
func mission_set(id: String, value: float, pid := -1) -> void:
	if not authority():
		return
	var i = _mission_index(id)
	if i < 0 or missions[i].done or value == missions[i].progress:
		return
	var done = value >= missions[i].goal
	if Net.active():
		Net.event("sector", [index, "mission", [i, value, done, pid]])
	else:
		apply_mission([i, value, done, pid])


## Every machine: a mission moved.
func apply_mission(a: Array) -> void:
	var m = missions[a[0]]
	var was: bool = m.done
	m.progress = a[1]
	m.done = was or a[2]
	if m.done and not was:
		if authority() and a[3] >= 0:
			world.award(a[3], MISSION_POINTS, "mission")
		if here() and world.hud:
			var who = "you" if a[3] == Net.my_id() or not Net.active() else Net.pname(a[3])
			world.hud.subtitle("mission done: %s   (%s)" % [m.text, who], 3.5)
			Audio.play("ding", -4.0, 1.1)
			if missions_done():
				get_tree().create_timer(3.6).connect("timeout", self, "_all_done")
	world.missions_changed(self)


func _all_done() -> void:
	if here() and world.hud:
		world.hud.subtitle("every mission done.   the door is open.", 4.0)
		Audio.play("ding", -2.0, 0.8)


func missions_done() -> bool:
	for m in missions:
		if not m.done:
			return false
	return true


func missions_left() -> int:
	var n = 0
	for m in missions:
		if not m.done:
			n += 1
	return n


## The exit door stays locked until every mission of the sector is done.
func exit_locked() -> bool:
	return not missions_done()


## "2/4", "best 62/85", "3/8 s" for the hud.
static func mission_text(m: Dictionary) -> String:
	if m.done:
		return m.text
	match m.fmt:
		"count":
			return "%s   %d/%d" % [m.text, int(m.progress), int(m.goal)]
		"best":
			return "%s   best %d" % [m.text, int(m.progress)]
		"secs":
			return "%s   %d/%d s" % [m.text, int(m.progress), int(m.goal)]
	return m.text
