class_name Mats
## Procedural materials (noise-based textures, no image files).

static var _cache := {}


static func _noise_tex(key: String, freq: float, octaves: int, dark: Color, light: Color, normal := false, bump := 4.0, stretch := Vector2.ONE, constant := false, threshold := 0.5) -> NoiseTexture2D:
	var k := "%s|%s|%s|%s|%s|%s|%s|%s" % [key, freq, octaves, dark, light, normal, stretch, constant]
	if _cache.has(k):
		return _cache[k]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = hash(key) % 10000
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	if stretch != Vector2.ONE:
		n.domain_warp_enabled = false
		t.width = int(256 * stretch.x)
		t.height = int(256 * stretch.y)
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	else:
		var g := Gradient.new()
		if constant:
			g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			g.set_offset(0, 0.0)
			g.set_color(0, light)
			g.set_offset(1, threshold)
			g.set_color(1, dark)
		else:
			g.set_color(0, dark)
			g.set_color(1, light)
		t.color_ramp = g
	_cache[k] = t
	return t


static func std(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Noisy, bumpy surface. `triplanar` for level geometry, UV for characters.
static func surface(key: String, base: Color, variation := 0.35, freq := 0.02, bump := 3.0, rough := 0.8, triplanar := false, uv_scale := Vector3.ONE, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var dark := base.darkened(variation)
	var light := base.lightened(variation * 0.5)
	m.albedo_texture = _noise_tex(key, freq, 4, dark, light)
	m.normal_enabled = true
	m.normal_texture = _noise_tex(key + "n", freq * 1.5, 4, Color.BLACK, Color.WHITE, true, bump)
	m.normal_scale = 1.0
	m.roughness = rough
	m.metallic = metal
	m.uv1_scale = uv_scale
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
	return m


static func wood(base := Color(0.55, 0.36, 0.2), triplanar := false, scale := Vector3(1, 1, 1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex("wood%s" % base, 0.012, 3, base.darkened(0.45), base.lightened(0.15), false, 0, Vector2(1, 1))
	m.normal_enabled = true
	m.normal_texture = _noise_tex("woodn", 0.03, 5, Color.BLACK, Color.WHITE, true, 6.0)
	m.roughness = 0.85
	m.uv1_scale = scale if not triplanar else scale * 0.25
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	return m


static func skin(base: Color, wet := false) -> StandardMaterial3D:
	var m := surface("skin%s" % base, base, 0.25, 0.04, 2.0, 0.25 if wet else 0.6)
	if wet:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.1
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.3
	return m


static func spots(white: Color, black: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex("cowspots", 0.012, 2, black, white, false, 0, Vector2.ONE, true, 0.62)
	m.normal_enabled = true
	m.normal_texture = _noise_tex("cown", 0.05, 4, Color.BLACK, Color.WHITE, true, 2.0)
	m.roughness = 0.7
	m.uv1_scale = Vector3(2, 1, 1)
	return m


static func eye_black() -> StandardMaterial3D:
	var m := std(Color(0.01, 0.01, 0.01), 0.05)
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.0
	m.metallic_specular = 1.0
	return m


static func teeth() -> StandardMaterial3D:
	var m := std(Color(0.86, 0.82, 0.66), 0.35)
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.3
	return m


static func gums() -> StandardMaterial3D:
	var m := std(Color(0.25, 0.02, 0.04), 0.3)
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	return m


static func metal(base: Color, rough := 0.35) -> StandardMaterial3D:
	return surface("metal%s" % base, base, 0.2, 0.05, 1.0, rough, false, Vector3.ONE, 0.85)


## World-space material for level geometry.
static func level(key: String, base: Color, variation := 0.35, freq := 0.05, bump := 2.0, rough := 0.85, scale := 0.25) -> StandardMaterial3D:
	return surface(key, base, variation, freq, bump, rough, true, Vector3.ONE * scale)


static func water() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec3 tint = vec3(0.02, 0.06, 0.07);
uniform float speed = 0.6;
float h(vec2 p, float t) {
	return sin(p.x * 1.7 + t) * 0.5 + sin(p.y * 2.3 - t * 1.3) * 0.5 + sin((p.x + p.y) * 3.1 + t * 0.7) * 0.25;
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += h(w.xz * 0.5, TIME * speed) * 0.03;
}
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float e = 0.05;
	float t = TIME * speed;
	float hx = h((w.xz + vec2(e, 0.0)) * 2.0, t) - h(w.xz * 2.0, t);
	float hz = h((w.xz + vec2(0.0, e)) * 2.0, t) - h(w.xz * 2.0, t);
	vec3 n = normalize(vec3(-hx * 0.4, 1.0, -hz * 0.4));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ALBEDO = tint;
	ROUGHNESS = 0.04;
	METALLIC = 0.3;
	SPECULAR = 1.0;
}
"""
	m.shader = s
	return m


static func deep_fry_overlay() -> ShaderMaterial:
	if _cache.has("fry"):
		return _cache["fry"]
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back;
float rnd(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void vertex() {
	float t = floor(TIME * 12.0);
	VERTEX += NORMAL * (rnd(VERTEX + t) - 0.3) * 0.07;
}
void fragment() {
	float t = floor(TIME * 8.0);
	vec3 c = vec3(rnd(vec3(t, 1.0, 2.0)), rnd(vec3(t, 5.0, 3.0)), rnd(vec3(t, 9.0, 7.0)));
	c = pow(c, vec3(0.5)) * vec3(1.0, 0.6, 0.2);
	ALBEDO = c * 0.55;
}
"""
	m.shader = s
	_cache["fry"] = m
	return m


# ------------------------------------------------------------------ Source-style procedural surfaces
const PATTERNS := {"planks": 0, "tiles": 1, "concrete": 2, "wallpaper": 3, "dev": 4, "missing": 5, "carpet": 6, "metal": 7, "plain": 8, "ceiling": 9}
static var _surface_shader: Shader
static var _surface_noise: NoiseTexture2D


static func surf(kind: String, a: Color, b: Color, opts := {}) -> ShaderMaterial:
	if _surface_shader == null:
		_surface_shader = load("res://scripts/surface.gdshader")
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.008
		n.fractal_octaves = 5
		_surface_noise = NoiseTexture2D.new()
		_surface_noise.width = 512
		_surface_noise.height = 512
		_surface_noise.seamless = true
		_surface_noise.noise = n
	var m := ShaderMaterial.new()
	m.shader = _surface_shader
	m.set_shader_parameter("pattern", PATTERNS[kind])
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("noise_tex", _surface_noise)
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	return m


static func missing() -> ShaderMaterial:
	return surf("missing", Color.BLACK, Color.MAGENTA, {"grime": 0.0, "stains": 0.0, "roughness": 0.6})


static func tv_static() -> ShaderMaterial:
	if _cache.has("tv"):
		return _cache["tv"]
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded;
float r(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 q = floor(UV * vec2(160.0, 120.0));
	float n = r(q + floor(TIME * 30.0) * 7.0);
	float roll = smoothstep(0.0, 0.1, fract(UV.y - TIME * 0.3)) * 0.3 + 0.7;
	ALBEDO = vec3(n) * roll * 1.6;
}
"""
	m.shader = s
	_cache["tv"] = m
	return m
