class_name Brainrots
## Model factory (kept apart from Models so Godot 3 sees no cyclic class references).


## Dedicated server: no body to draw, just the facts the AI needs.
static func build_headless(id: String) -> Spatial:
	var m = Spatial.new()
	m.set_meta("height", 1.95 if id == "tung" else 1.8)
	m.set_meta("display", "tung tung tung sahur" if id == "tung" else id)
	return m


static func build(id: String) -> Spatial:
	var m: Spatial
	match id:
		"tposer":
			m = Models2.tposer()
		_:
			m = TungModel.build()
	Models.set_layers(m, 1 | Geo.VIS_ACTOR)
	return m
