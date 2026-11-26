class_name Brainrots
## Model factory (kept apart from Models so Godot 3 sees no cyclic class references).


## Dedicated server: no body to draw, just the facts the AI needs.
static func build_headless(id: String) -> Spatial:
	var m = Spatial.new()
	m.set_meta("height", {"tung": 1.95, "keys": 1.86, "khaby": 2.86}.get(id, 1.8))
	m.set_meta("display", "tung tung tung sahur" if id == "tung" else id)
	return m


static func build(id: String) -> Spatial:
	var m: Spatial
	match id:
		"tposer":
			m = Models2.tposer()
		"keys":
			m = load("res://scripts/keys_model.gd").build()
		"khaby":
			m = load("res://scripts/khaby_model.gd").build()
		_:
			m = TungModel.build()
	Models.set_layers(m, 1 | Geo.VIS_ACTOR)
	m.set_meta("photo_id", id)
	m.set_meta("face_y", {"tung": 2.27, "keys": load("res://scripts/keys_model.gd").BOW_Y, "khaby": load("res://scripts/khaby_model.gd").EYE_Y - 0.12}.get(id, m.get_meta("height") * 0.85))
	m.add_to_group("photographable")
	return m
