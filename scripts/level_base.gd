class_name LevelBase
extends Node
## Base for every level. Override build() and _physics_process for level logic. (Godot 3)

var world
var rng: RandomNumberGenerator
var drain_rate = 0.0
var danger_bonus = 0.0
var boot_goggles = false
var spawn_pos = Vector3.ZERO
var spawn_yaw = 0.0


func build() -> void:
	pass


func killer_id() -> String:
	return "tung"


func player():
	return world.player


## Where the operatives start (world.gd places everyone around it).
func spawn_player(pos: Vector3, yaw := 0.0) -> void:
	spawn_pos = pos
	spawn_yaw = yaw


func make_nav(min_xz: Vector2, max_xz: Vector2, cell := 1.0):
	world.nav = NavGrid.new(min_xz, max_xz, cell)
	return world.nav


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
		var p: Vector3 = world.nav.random_open(rng, y)
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
