class_name UI
## rot's ui kit: source hud x hyper-minimal phone. frosted glass, thin type, everything lowercase.

const AMBER := Color(1.0, 0.78, 0.25)
const WHITE := Color(1, 1, 1, 0.92)
const SOFT := Color(1, 1, 1, 0.55)
const FAINT := Color(1, 1, 1, 0.3)
const RED := Color(1.0, 0.27, 0.23)
const GREEN := Color(0.2, 0.84, 0.29)
# legacy names used around the codebase
const PALE := WHITE
const DIM := SOFT

static var _fonts := {}
static var _glass: Shader


static func font(weight := "light") -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var path: String = {
		"light": "res://fonts/Inter-Light.ttf",
		"medium": "res://fonts/Inter-Medium.ttf",
		"thin": "res://fonts/InterDisplay-Thin.ttf",
		"xlight": "res://fonts/InterDisplay-ExtraLight.ttf",
	}.get(weight, "res://fonts/Inter-Light.ttf")
	var f: Font = load(path)
	_fonts[weight] = f
	return f


static func mono() -> Font:
	return font("light")


static func title_font() -> Font:
	return font("thin")


static func label(text: String, size := 18, color := WHITE, f: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text.to_lower()
	l.add_theme_font_override("font", f if f else font("light"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Frosted glass panel with rounded corners (blurs whatever is behind it).
static func glass(radius := 18.0, tint := Color(0.08, 0.08, 0.09, 0.42), border := 0.10) -> ColorRect:
	if _glass == null:
		_glass = Shader.new()
		_glass.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(200.0, 80.0);
uniform float radius = 18.0;
uniform vec4 tint : source_color = vec4(0.08, 0.08, 0.09, 0.42);
uniform float border = 0.1;
uniform float blur = 3.2;
float box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float d = box(p, size * 0.5, radius);
	float a = 1.0 - smoothstep(-1.0, 0.5, d);
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	bg = mix(bg, vec3(dot(bg, vec3(0.333))), 0.35) * 1.05;
	vec3 c = mix(bg, tint.rgb, tint.a);
	float edge = (1.0 - smoothstep(-1.6, -0.4, d)) * smoothstep(-2.6, -1.4, d);
	c += edge * border;
	COLOR = vec4(c, a);
}
"""
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = _glass
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("border", border)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.resized.connect(func(): m.set_shader_parameter("size", r.size))
	return r


static func _box(bg: Color, radius := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.anti_aliasing = true
	return s


static func button(text: String, cb: Callable, size := 22) -> Button:
	var b := Button.new()
	b.text = text.to_lower()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font("light"))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.0)))
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.10)))
	b.add_theme_stylebox_override("focus", _box(Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("pressed", _box(Color(1, 0.78, 0.25, 0.18)))
	b.pressed.connect(func():
		Audio.play("ui_click", -10.0, randf_range(0.95, 1.05))
		cb.call())
	b.mouse_entered.connect(func(): Audio.play("ui_hover", -16.0))
	return b


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


## A hairline progress bar with rounded ends.
static func bar(color: Color, w := 160.0, h := 3.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	bg.set_corner_radius_all(int(h))
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(int(h))
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## A grouped, frosted settings-style list (iOS-ish).
static func group_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var s := _box(Color(0.1, 0.1, 0.11, 0.78), 22)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	return p
