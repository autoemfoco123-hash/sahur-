class_name UI
## sahur's ui kit: source hud x hyper-minimal phone. thin type, everything lowercase. Godot 3.

const AMBER := Color(1.0, 0.78, 0.25)
const WHITE := Color(1, 1, 1, 0.92)
const SOFT := Color(1, 1, 1, 0.55)
const FAINT := Color(1, 1, 1, 0.3)
const RED := Color(1.0, 0.27, 0.23)
const GREEN := Color(0.2, 0.84, 0.29)

const FONT_FILES := {
	"light": "res://fonts/Inter-Light.ttf",
	"medium": "res://fonts/Inter-Medium.ttf",
	"thin": "res://fonts/InterDisplay-Thin.ttf",
	"xlight": "res://fonts/InterDisplay-ExtraLight.ttf",
}


static func font(weight := "light", size := 18) -> DynamicFont:
	var key = "font_%s_%d" % [weight, size]
	if Game.cache.has(key):
		return Game.cache[key]
	var dkey = "fontdata_" + weight
	if not Game.cache.has(dkey):
		var d = DynamicFontData.new()
		d.font_path = FONT_FILES.get(weight, FONT_FILES["light"])
		d.antialiased = true
		d.hinting = DynamicFontData.HINTING_LIGHT
		Game.cache[dkey] = d
	var f = DynamicFont.new()
	f.font_data = Game.cache[dkey]
	f.size = size
	f.use_filter = true
	Game.cache[key] = f
	return f


static func label(text: String, size := 18, color := WHITE, weight := "light", align := Label.ALIGN_LEFT) -> Label:
	var l = Label.new()
	l.text = text.to_lower()
	l.add_font_override("font", font(weight, size))
	l.add_color_override("font_color", color)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.35))
	l.add_constant_override("shadow_offset_y", 1)
	l.add_constant_override("shadow_offset_x", 0)
	l.align = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, radius := 12) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.anti_aliasing = true
	return s


## Translucent rounded panel (the GLES2 stand-in for frosted glass).
static func glass(radius := 20) -> Panel:
	var p = Panel.new()
	var s = box(Color(0.06, 0.06, 0.07, 0.55), radius)
	s.border_color = Color(1, 1, 1, 0.1)
	s.set_border_width_all(1)
	p.add_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func button(text: String, target: Object, method: String, binds := [], size := 22) -> Button:
	var b = Button.new()
	b.text = text.to_lower()
	b.align = Button.ALIGN_LEFT
	b.add_font_override("font", font("light", size))
	b.add_color_override("font_color", WHITE)
	b.add_color_override("font_color_hover", Color.white)
	b.add_color_override("font_color_focus", Color.white)
	b.add_color_override("font_color_pressed", AMBER)
	b.add_stylebox_override("normal", box(Color(1, 1, 1, 0.0)))
	b.add_stylebox_override("hover", box(Color(1, 1, 1, 0.10)))
	b.add_stylebox_override("focus", box(Color(1, 1, 1, 0.06)))
	b.add_stylebox_override("pressed", box(Color(1, 0.78, 0.25, 0.18)))
	b.connect("pressed", Audio, "play", ["ui_click", -10.0])
	b.connect("mouse_entered", Audio, "play", ["ui_hover", -16.0])
	b.connect("pressed", target, method, binds)
	return b


static func full_rect(c: Control) -> Control:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.margin_left = 0
	c.margin_top = 0
	c.margin_right = 0
	c.margin_bottom = 0
	return c


static func bar(color: Color, w := 160.0, h := 3.0) -> ProgressBar:
	var b = ProgressBar.new()
	b.rect_min_size = Vector2(w, h)
	b.percent_visible = false
	b.max_value = 100
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	bg.set_corner_radius_all(int(h))
	var fg = StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(int(h))
	b.add_stylebox_override("bg", bg)
	b.add_stylebox_override("fg", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func group_panel() -> PanelContainer:
	var p = PanelContainer.new()
	var s = box(Color(0.1, 0.1, 0.11, 0.85), 22)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_stylebox_override("panel", s)
	return p
