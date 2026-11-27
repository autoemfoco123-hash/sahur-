extends Node
## Bakes the office lighting once, on the GPU, while the level loads (fine on OpenGL 2.1).
##   direct : soft-shadowed light of every ceiling lamp seen from above (Light2D + LightOccluder2D;
##            each lamp is 4 sub-lights so shadows get a real penumbra)
##   walls  : wall footprint, white on black
##   soft   : r = wide blur of direct (light bounced off carpet and walls)
##            g = narrow blur of walls (ambient occlusion in corners and along wall bases)
## The static world reads both maps by world xz in world_lit.shader. Lamps that flicker or die
## are subtracted in the shader, so nothing is re-baked at runtime.

const LAMP_H = 2.75
const RADIUS = 9.0
const GAIN = 0.5          # light written into the 8-bit map; shaders divide it back out
const RES = 512

var origin = Vector2.ZERO
var span = 1.0            # metres covered by the (square) map
var ppm = 1.0             # map pixels per metre
var direct_vp: Viewport
var walls_vp: Viewport
var soft_vp: Viewport
var mats = []
var lamps = []            # Vector2 xz of every baked lamp
var _off = {}             # lamp key -> Vector2 xz, lamps currently off
var _frames = 0
var _actor = Plane(0, 0, 0, 0)
var _dirty = false
var black = false


func build(area: Rect2, lamp_list: Array, walls: Array, lamp_gain := 1.0) -> void:
	origin = area.position
	span = max(area.size.x, area.size.y)
	ppm = RES / span
	lamps = lamp_list
	walls_vp = _vp(RES)
	direct_vp = _vp(RES)
	soft_vp = _vp(RES / 2)
	# --- wall footprint (also the occluder map for the direct pass)
	var wbg = ColorRect.new()
	wbg.rect_size = Vector2(RES, RES)
	wbg.color = Color(0, 0, 0)
	walls_vp.add_child(wbg)
	for w in walls:
		var c: Vector2 = w[0]
		var s: Vector2 = w[1]
		var r = ColorRect.new()
		r.color = Color(1, 1, 1)
		r.rect_position = _px(c - s * 0.5)
		r.rect_size = s * ppm
		walls_vp.add_child(r)
	# --- direct light: one additive quad per lamp, all sharing one material
	var bg = ColorRect.new()
	bg.rect_size = Vector2(RES, RES)
	bg.color = Color(0, 0, 0)
	direct_vp.add_child(bg)
	var rpx = RADIUS * ppm
	var lm = ShaderMaterial.new()
	lm.shader = load("res://scripts/lm_lamp.shader")
	lm.set_shader_param("walls", walls_vp.get_texture())
	lm.set_shader_param("res", float(RES))
	lm.set_shader_param("ppm", ppm)
	lm.set_shader_param("radius_px", rpx)
	lm.set_shader_param("gain", GAIN * lamp_gain)
	lm.set_shader_param("lamp_h", LAMP_H)
	for lp in lamp_list:
		var q = ColorRect.new()
		q.rect_size = Vector2(rpx, rpx) * 2.0
		q.rect_position = _px(lp) - Vector2(rpx, rpx)
		q.material = lm
		direct_vp.add_child(q)
	# --- bounce + occlusion
	var sr = ColorRect.new()
	sr.rect_size = Vector2(RES / 2, RES / 2)
	var sm = ShaderMaterial.new()
	sm.shader = load("res://scripts/lm_soft.shader")
	sm.set_shader_param("direct", direct_vp.get_texture())
	sm.set_shader_param("walls", walls_vp.get_texture())
	sm.set_shader_param("wide", 2.6 / span)
	sm.set_shader_param("narrow", 0.55 / span)
	sr.material = sm
	soft_vp.add_child(sr)
	set_process(true)


func _vp(n: int) -> Viewport:
	var v = Viewport.new()
	v.size = Vector2(n, n)
	v.usage = Viewport.USAGE_2D
	v.disable_3d = true
	v.transparent_bg = false
	v.render_target_v_flip = true
	v.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(v)
	v.get_texture().flags = Texture.FLAG_FILTER
	return v


func _px(p: Vector2) -> Vector2:
	return (p - origin) * ppm


## Render a few frames, then freeze the maps (their textures stay valid).
func _process(_d: float) -> void:
	_frames += 1
	if _frames == 5 and "lmdump" in OS.get_cmdline_args():
		direct_vp.get_texture().get_data().save_png("user://lm_direct.png")
		soft_vp.get_texture().get_data().save_png("user://lm_soft.png")
		walls_vp.get_texture().get_data().save_png("user://lm_walls.png")
	if _frames == 8:
		for v in [direct_vp, walls_vp, soft_vp]:
			v.render_target_update_mode = Viewport.UPDATE_DISABLED
		set_process(false)


# ------------------------------------------------------------------ materials
## Office surface lit by this bake. kind: 0 carpet · 1 wallpaper · 2 drop ceiling · 3 light lens
func surface(kind: int, tex: String, scale: float, wall_h: float, env: Environment, opts := {}) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = load("res://scripts/world_lit.shader")
	m.set_shader_param("kind", kind)
	m.set_shader_param("albedo_tex", load("res://textures/%s.png" % tex))
	m.set_shader_param("tex_scale", scale)
	m.set_shader_param("noise_tex", Mats.noise_tex())
	m.set_shader_param("lite", Mats.potato())
	m.set_shader_param("wall_h", wall_h)
	m.set_shader_param("fog_color", Vector3(env.fog_color.r, env.fog_color.g, env.fog_color.b))
	# distance haze comes from the Environment fog (it also covers unshaded materials)
	m.set_shader_param("fog", Plane(env.fog_depth_begin, env.fog_depth_end, env.fog_depth_curve, 0.0))
	if opts.has("tint"):
		m.set_shader_param("light_tint", opts.tint)
	if opts.has("exposure"):
		m.set_shader_param("exposure", opts.exposure)
	if opts.has("ambient"):
		m.set_shader_param("ambient", opts.ambient)
	if opts.has("mono"):
		m.set_shader_param("mono", opts.mono)
	return register(m)


## The office materials for OfficeMesh.commit(). opts.tex overrides textures per mesh kind
## ({"wall": ["wallpaper_green", 1.0]}); extra kinds ("door", "knob") are lit like walls.
func office_mats(wall_h: float, env: Environment, opts := {}) -> Dictionary:
	var tex = {"floor": ["carpet", 1.0], "wall": ["wallpaper", 1.0], "ceiling": ["ceiling", 1.2], "panel": ["panel", 0.6]}
	var kinds = {"floor": 0, "wall": 1, "ceiling": 2, "panel": 3, "door": 1, "knob": 1}
	for k in opts.get("tex", {}):
		tex[k] = opts.tex[k]
	var out = {}
	for k in tex:
		out[k] = surface(kinds.get(k, 1), tex[k][0], tex[k][1], wall_h, env, opts)
	return out


func register(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_param("lm_direct", direct_vp.get_texture())
	m.set_shader_param("lm_soft", soft_vp.get_texture())
	m.set_shader_param("lm_rect", Plane(origin.x, origin.y, 1.0 / span, 1.0 / span))
	m.set_shader_param("lm_gain", 1.0 / GAIN)
	mats.append(m)
	_push_one(m)
	return m


func lamp_key(p: Vector2) -> String:
	return "%d_%d" % [int(round(p.x * 10.0)), int(round(p.y * 10.0))]


func set_lamp(p: Vector2, on: bool) -> void:
	var k = lamp_key(p)
	if on:
		_off.erase(k)
	else:
		_off[k] = p
	# a blackout switches dozens of lamps in one frame: push the uniforms once
	if not _dirty:
		_dirty = true
		call_deferred("_flush")


func _flush() -> void:
	_dirty = false
	_push()


## Moving light (a brainrot's own top light): xz, intensity, radius.
func set_actor(p: Vector2, intensity: float, radius := 2.6) -> void:
	_actor = Plane(p.x, p.y, intensity, radius)
	for m in mats:
		m.set_shader_param("actor", _actor)


func _push() -> void:
	for m in mats:
		_push_one(m)


func _push_one(m: ShaderMaterial) -> void:
	var offs = _off.values()
	black = offs.size() > 4
	for i in 4:
		var v = Plane(0, 0, 0, 0)
		if not black and i < offs.size():
			v = Plane(offs[i].x, offs[i].y, 1.0, 0)
		m.set_shader_param("off%d" % i, v)
	m.set_shader_param("blackout", 1.0 if black else 0.0)
	m.set_shader_param("actor", _actor)
