class_name LevelBase
extends Node
## Base for every sector. Override build() and _physics_process for sector logic. (Godot 3)
## One round is one run through every sector: they all live in the same world, side by side,
## SECTOR_GAP metres apart along x (far past the camera's far plane, so only one is ever drawn).
## The exit door of a sector opens straight into the next one.
## Build everything relative to `origin` (use _cell / o2() / make_nav, which already add it).

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
var exit_root: Spatial      # this sector's exit door


func build() -> void:
	pass


## The local operative's view just moved into this sector (arrival, spawn, spectating, revive).
## Ambience, footsteps, dust. `boot`: the very start of the run (goggles power up).
func enter(_boot: bool) -> void:
	pass


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
	var l = Geo.label3d(world, text, pos, size, Color(0.9, 1.0, 0.9), rot_y)
	l.layers = 2
	return l


# ------------------------------------------------------------------ the exit door
## A real door, shut, with the next sector's light leaking around it. [E] opens it
## (world.use_exit decides: locked, the next sector, or the way out).
func make_exit(pos: Vector3, rot_y: float, color: Color) -> Spatial:
	var root = Spatial.new()
	root.name = "ExitDoor"
	world.add_child(root)
	exit_root = root
	root.translation = pos
	root.rotation.y = rot_y
	# solid: you open it, you don't walk through it
	var sb = StaticBody.new()
	sb.collision_layer = Geo.LAYER_WORLD
	root.add_child(sb)
	var cs = CollisionShape.new()
	var sh = BoxShape.new()
	sh.extents = Vector3(0.75, 1.2, 0.08)
	cs.shape = sh
	sb.add_child(cs)
	cs.translation = Vector3(0, 1.2, 0)
	if world.headless:
		return root
	var frame = Mats.std(Color(0.07, 0.07, 0.07), 0.6)
	Models.part(root, Models.box(Vector3(0.15, 2.4, 0.2)), frame, Vector3(-0.68, 1.2, 0))
	Models.part(root, Models.box(Vector3(0.15, 2.4, 0.2)), frame, Vector3(0.68, 1.2, 0))
	Models.part(root, Models.box(Vector3(1.5, 0.15, 0.2)), frame, Vector3(0, 2.4, 0))
	# the light on the other side: a thin bright line all around the door, brightest at the floor
	var g = Models.part(root, Models.box(Vector3(1.2, 2.32, 0.03)), Mats.glow(color, 4.0), Vector3(0, 1.16, -0.03))
	g.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	g.name = "glow"
	var hinge = Spatial.new()
	hinge.name = "hinge"
	root.add_child(hinge)
	hinge.translation = Vector3(-0.585, 0, 0.03)
	var slab_mat = Mats.std(Color(0.15, 0.14, 0.12), 0.55)
	Models.part(hinge, Models.box(Vector3(1.11, 2.2, 0.05)), slab_mat, Vector3(0.555, 1.15, 0))
	Models.part(hinge, Models.box(Vector3(0.05, 0.05, 0.08)), Mats.std(Color(0.45, 0.42, 0.36), 0.3, 0.8), Vector3(1.0, 1.02, 0.05))
	Models.part(hinge, Models.box(Vector3(0.16, 0.035, 0.05)), Mats.std(Color(0.45, 0.42, 0.36), 0.3, 0.8), Vector3(0.94, 1.02, 0.09))
	var spill = Geo.omni(root, Vector3(0, 0.12, 0.45), color, 0.9, 2.2)
	spill.light_cull_mask = Geo.VIS_ACTOR
	Geo.label3d(root, "exit", Vector3(0, 2.75, 0.12), 48, Color(1, 0.2, 0.15), 0.0)
	Models.set_layers(root, 1 | Geo.VIS_ACTOR)
	if world.player:
		Interactable.make(root, root.global_transform.xform(Vector3(0, 1.2, 0.35)), 0.7, "open the door", world, "use_exit", [self, root], false)
	return root
