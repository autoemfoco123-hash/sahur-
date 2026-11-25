extends LevelBase
## Dev-only stage for checking Tung's body language. Not part of the game flow.

const TungAI := preload("res://scripts/enemies/tung.gd")
var tung: TungAI
var a := Vector3(-6, 0.1, 0)
var b := Vector3(6, 0.1, 0)
var to_b := true
var t := 0.0


func build() -> void:
	world.setup_env({"ambient": Color(0.92, 0.88, 0.62), "ambient_energy": 0.25, "vol": 0.0, "fog": false, "ssil": true, "auto_exposure": 0.0})
	make_nav(Vector2(-20, -20), Vector2(20, 20), 0.5)
	var carpet := Mats.surf("carpet", Color(0.5, 0.45, 0.3), Color(0.33, 0.29, 0.19), {"stains": 0.5})
	Geo.floor_box(world, Vector3(40, 0.4, 40), Vector3.ZERO, carpet)
	var wall := Mats.surf("plain", Color(0.83, 0.79, 0.5), Color(0.74, 0.7, 0.43), {"wainscot": 0.09})
	Geo.solid(world, Vector3(40, 2.8, 0.3), Vector3(0, 1.4, -4), wall)
	for x in range(-8, 9, 4):
		Geo.square_panel(world, Vector3(x, 2.79, 0), 2.0, true)
	Geo.solid(world, Vector3(40, 0.3, 40), Vector3(0, 2.95, 0), Mats.surf("ceiling", Color(0.86, 0.84, 0.72), Color(0.7, 0.69, 0.62)))
	spawn_player(Vector3(0, 0.2, 5.5), 0.0)
	player().set_visor(true, true)
	tung = enemy(TungAI, "tung", a) as TungAI
	tung.set_state(TungAI.S.PASSIVE)


func _physics_process(delta: float) -> void:
	t += delta
	tung.state = TungAI.S.PASSIVE
	tung.timer = 99.0
	tung.speed_override = 1.5 if t < 6.0 else 3.9
	tung.drains = false
	tung.target = b if to_b else a
	if tung.global_position.distance_to(tung.target) < 0.6:
		to_b = not to_b


