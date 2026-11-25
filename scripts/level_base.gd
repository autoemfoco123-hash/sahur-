class_name LevelBase
extends Node
## Base for every level. Override build() and _physics_process for level logic.

var world: World
var rng: RandomNumberGenerator
var drain_rate := 0.0
var boot_goggles := false
var danger_bonus := 0.0
var pixelate := 0.0


func build() -> void:
	pass


func killer_id() -> String:
	return "tung"


func player() -> Player:
	return world.player


func spawn_player(pos: Vector3, yaw := 0.0) -> void:
	world.player.global_position = pos
	world.player.set_look(yaw, 0.0)


func make_nav(min_xz: Vector2, max_xz: Vector2, cell := 1.0) -> NavGrid:
	world.nav = NavGrid.new(min_xz, max_xz, cell)
	return world.nav


func note(pos: Vector3, text: String) -> void:
	var m := Models2.note()
	world.add_child(m)
	m.global_position = pos
	var glow := Geo.omni(m, Vector3(0, 0.25, 0), Color(1, 0.85, 0.6), 0.4, 1.6)
	glow.shadow_enabled = false
	Interactable.make(world, pos + Vector3(0, 0.15, 0), 0.45, "read note", func():
		world.show_note(text)
		m.queue_free())


func battery(pos: Vector3) -> void:
	var m := Models2.battery()
	world.add_child(m)
	m.global_position = pos
	Interactable.make(world, pos + Vector3(0, 0.12, 0), 0.4, "take visor cell", func():
		Game.flashlight_battery = minf(100.0, Game.flashlight_battery + 40.0)
		Audio.play("pickup", -6.0)
		world.hud.subtitle("visor cell · +40%", 1.5)
		m.queue_free())


func enemy(script: Script, id: String, pos: Vector3, hostile := true) -> Enemy:
	var e: Enemy = script.new()
	e.setup(world, id, pos, hostile)
	return e


func ambient(sname: String, vol := -6.0, sname2 := "", vol2 := -12.0) -> void:
	Audio.ambient(sname, vol, 0)
	Audio.ambient(sname2, vol2, 1)


## Scatter items into random open nav cells far enough from `avoid`.
func scatter_points(count: int, avoid: Vector3, min_dist := 8.0, y := 0.0) -> Array:
	var out := []
	var tries := 0
	while out.size() < count and tries < 400:
		tries += 1
		var p: Vector3 = world.nav.random_open(rng, y)
		if p.distance_to(avoid) < min_dist:
			continue
		var ok := true
		for q in out:
			if p.distance_to(q) < 5.0:
				ok = false
				break
		if ok:
			out.append(p)
	return out



## Infrared chalk left by earlier hush operatives. Only visible through the visor.
func ir_mark(pos: Vector3, rot_y: float, text: String, size := 90) -> Label3D:
	var l := Geo.label3d(world, text, pos, size, Color(0.9, 1.0, 0.9), rot_y, true)
	l.font = UI.font("medium")
	l.pixel_size = 0.006
	l.double_sided = true
	l.layers = Player.NV_LAYER
	return l
