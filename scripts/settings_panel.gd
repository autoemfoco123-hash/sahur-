class_name SettingsPanel
extends PanelContainer
## settings, grouped like a phone's settings app. (Godot 3)

signal closed

var _vals = {}


func _ready() -> void:
	var s = UI.box(Color(0.08, 0.08, 0.09, 0.97), 22)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 22
	s.content_margin_bottom = 18
	add_stylebox_override("panel", s)
	pause_mode = Node.PAUSE_MODE_PROCESS
	rect_min_size = Vector2(560, 0)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 12)
	add_child(v)
	v.add_child(UI.label("settings", 32, UI.WHITE, "thin"))
	var touch = OS.has_feature("mobile") or Game.force_touch
	_slider(v, "look sensitivity" if touch else "mouse sensitivity", "sensitivity", 0.03, 1.0, 0.01)
	_slider(v, "volume", "volume", 0.0, 1.0, 0.01)
	_slider(v, "post-processing", "post", 0.0, 1.5, 0.05)
	_slider(v, "fisheye", "fisheye", 0.0, 1.0, 0.05)
	_slider(v, "motion blur", "motion_blur", 0.0, 2.0, 0.05)
	_slider(v, "brightness", "brightness", 0.6, 1.8, 0.05)
	var q = HBoxContainer.new()
	q.add_child(_name("graphics"))
	var ob = OptionButton.new()
	ob.add_item("potato · any pc, half resolution")
	ob.add_item("low")
	ob.add_item("high · shadows, more lights")
	ob.selected = int(Game.settings.gfx)
	ob.add_font_override("font", UI.font("light", 16))
	ob.connect("item_selected", self, "_on_gfx")
	q.add_child(ob)
	v.add_child(q)
	if not touch:
		var f = HBoxContainer.new()
		f.add_child(_name("fullscreen"))
		var cb = CheckButton.new()
		cb.pressed = bool(Game.settings.fullscreen)
		cb.connect("toggled", self, "_on_fullscreen")
		f.add_child(cb)
		v.add_child(f)
		v.add_child(UI.label("wasd move · mouse look · e interact · q answer him\nf / right click photo · ctrl crouch · space jump · esc pause", 13, UI.FAINT))
	else:
		v.add_child(UI.label("left thumb walks · drag on the right to look\nquick tap answers him · photo / e / crouch / pause buttons", 13, UI.FAINT))
	v.add_child(UI.button("‹ back", self, "_back", [], 18))


func _back() -> void:
	emit_signal("closed")


func _on_gfx(i: int) -> void:
	Game.set_setting("gfx", i)


func _on_fullscreen(on: bool) -> void:
	Game.set_setting("fullscreen", on)


func _name(t: String) -> Label:
	var l = UI.label(t, 16, UI.WHITE)
	l.rect_min_size = Vector2(200, 0)
	return l


func _slider(parent: Control, text: String, key: String, mn: float, mx: float, step: float) -> void:
	var h = HBoxContainer.new()
	h.add_child(_name(text))
	var sl = HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = float(Game.settings[key])
	sl.rect_min_size = Vector2(250, 24)
	var val = UI.label("%.2f" % sl.value, 14, UI.SOFT)
	val.rect_min_size = Vector2(50, 0)
	_vals[key] = val
	sl.connect("value_changed", self, "_on_slider", [key])
	h.add_child(sl)
	h.add_child(val)
	parent.add_child(h)


func _on_slider(x: float, key: String) -> void:
	_vals[key].text = "%.2f" % x
	Game.set_setting(key, x)
