class_name SettingsPanel
extends PanelContainer
## settings, grouped like a phone's settings app.

signal closed


func _ready() -> void:
	var s := UI._box(Color(0.1, 0.1, 0.11, 0.82), 22)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 22
	s.content_margin_bottom = 18
	add_theme_stylebox_override("panel", s)
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(UI.label("settings", 32, UI.WHITE, UI.font("thin")))
	_slider(v, "mouse sensitivity", "sensitivity", 0.03, 1.0, 0.01)
	_slider(v, "volume", "volume", 0.0, 1.0, 0.01)
	_slider(v, "post-processing", "post", 0.0, 1.5, 0.05)
	_slider(v, "fisheye", "fisheye", 0.0, 1.0, 0.05)
	_slider(v, "motion blur", "motion_blur", 0.0, 2.0, 0.05)
	_slider(v, "brightness", "brightness", 0.6, 1.8, 0.05)
	var q := HBoxContainer.new()
	q.add_child(_name("graphics"))
	var ob := OptionButton.new()
	ob.add_item("low")
	ob.add_item("high · fog, ssao, reflections")
	ob.add_item("ultra · + global illumination")
	ob.selected = int(Game.settings.quality)
	ob.add_theme_font_override("font", UI.font("light"))
	ob.item_selected.connect(func(i): Game.set_setting("quality", i))
	q.add_child(ob)
	v.add_child(q)
	var f := HBoxContainer.new()
	f.add_child(_name("fullscreen"))
	var cb := CheckButton.new()
	cb.button_pressed = bool(Game.settings.fullscreen)
	cb.toggled.connect(func(on): Game.set_setting("fullscreen", on))
	f.add_child(cb)
	v.add_child(f)
	v.add_child(UI.label("wasd move · mouse look · e interact · q shout\nctrl crouch · space jump · esc pause", 13, UI.FAINT))
	v.add_child(UI.button("‹ back", func(): closed.emit(), 18))


func _name(t: String) -> Label:
	var l := UI.label(t, 16, UI.WHITE)
	l.custom_minimum_size = Vector2(200, 0)
	return l


func _slider(parent: Control, text: String, key: String, mn: float, mx: float, step: float) -> void:
	var h := HBoxContainer.new()
	h.add_child(_name(text))
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = float(Game.settings[key])
	sl.custom_minimum_size = Vector2(250, 24)
	var val := UI.label("%.2f" % sl.value, 14, UI.SOFT)
	val.custom_minimum_size = Vector2(50, 0)
	sl.value_changed.connect(func(x):
		val.text = "%.2f" % x
		Game.set_setting(key, x))
	h.add_child(sl)
	h.add_child(val)
	parent.add_child(h)
