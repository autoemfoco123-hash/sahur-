class_name Mats
## Procedural materials (noise-based, no image files). Godot 3 / GLES2.

const PATTERNS := {"missing": 5, "carpet": 6, "plain": 8, "ceiling": 9}


static func noise_tex() -> NoiseTexture:
	if Game.cache.has("noise"):
		return Game.cache["noise"]
	var n = OpenSimplexNoise.new()
	n.seed = 7
	n.octaves = 4
	n.period = 110.0
	n.persistence = 0.5
	var t = NoiseTexture.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	Game.cache["noise"] = t
	return t


## Potato mode lights per vertex instead of per pixel (decided when a level is built).
static func potato() -> bool:
	return int(Game.settings.gfx) == 0


## Load a spatial shader, in its vertex-lit variant when on potato.
static func shader(path: String) -> Shader:
	var key = "sh_%s_%s" % [path, potato()]
	if Game.cache.has(key):
		return Game.cache[key]
	var base: Shader = load(path)
	var sh: Shader = base
	if potato():
		sh = Shader.new()
		sh.code = base.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode vertex_lighting;")
	Game.cache[key] = sh
	return sh


static func std(color: Color, rough := 0.8, metal := 0.0) -> SpatialMaterial:
	var m = SpatialMaterial.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.flags_vertex_lighting = potato()
	return m


static func glow(color: Color, energy := 3.0) -> SpatialMaterial:
	var m = SpatialMaterial.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy = energy
	return m


static func unshaded(color: Color) -> SpatialMaterial:
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = color
	if color.a < 1.0:
		m.flags_transparent = true
	return m


## World-space office surfaces (see surface.shader).
static func surf(kind: String, a: Color, b: Color, opts := {}) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = shader("res://scripts/surface.shader")
	m.set_shader_param("pattern", PATTERNS[kind])
	m.set_shader_param("color_a", a)
	m.set_shader_param("color_b", b)
	m.set_shader_param("noise_tex", noise_tex())
	m.set_shader_param("lite", potato())
	for k in opts:
		m.set_shader_param(k, opts[k])
	return m


static func missing() -> ShaderMaterial:
	return surf("missing", Color.black, Color(1, 0, 1), {"grime": 0.0, "stains": 0.0, "roughness": 0.6})
