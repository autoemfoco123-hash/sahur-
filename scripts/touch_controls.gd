class_name TouchControls
extends CanvasLayer
## iPhone controls, same minimal language as the hud:
## left thumb  = floating analog joystick (walk)
## right thumb = drag to look
## buttons     = sahur (shout) · e (interact, only when something is interactable) · crouch · pause

var world: World
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _crouch := false
var _base: Control
var _knob: Control
var _btn_e: TouchScreenButton
var _buttons: Array[TouchScreenButton] = []
const STICK_R := 70.0


static func wanted() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("ios") or Game.force_touch


func _ready() -> void:
	layer = 61
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_base = _circle(STICK_R * 2.0, Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.35))
	root.add_child(_base)
	_knob = _circle(64.0, Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0))
	root.add_child(_knob)
	_base.visible = false
	_knob.visible = false
	var vp := get_viewport().get_visible_rect().size
	_add_button("sahur", "shout", Vector2(vp.x - 140, vp.y - 120), 62.0, UI.AMBER, Color(0.1, 0.08, 0.02))
	_btn_e = _add_button("e", "interact", Vector2(vp.x - 285, vp.y - 95), 42.0, Color(1, 1, 1, 0.85), Color(0.08, 0.08, 0.08))
	_add_button("crouch", "", Vector2(vp.x - 115, vp.y - 285), 34.0, Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.9)).pressed.connect(func():
		_crouch = not _crouch
		if _crouch:
			Input.action_press("crouch")
		else:
			Input.action_release("crouch"))
	_add_button("ii", "", Vector2(vp.x - 90, 150), 26.0, Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.9)).pressed.connect(func():
		if world and not world.dying:
			world.set_paused(not world.paused))
	get_viewport().size_changed.connect(_relayout)


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var spots := [Vector2(vp.x - 140, vp.y - 120), Vector2(vp.x - 285, vp.y - 95), Vector2(vp.x - 115, vp.y - 285), Vector2(vp.x - 90, 150)]
	for i in _buttons.size():
		var b := _buttons[i]
		b.position = spots[i] - Vector2(b.get_meta("r"), b.get_meta("r"))


func _circle(d: float, fill: Color, ring: Color) -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = ring
	s.set_border_width_all(2 if ring.a > 0.0 else 0)
	s.set_corner_radius_all(int(d * 0.5))
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _disc_texture(r: float, col: Color) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.93, 1.0])
	g.colors = PackedColorArray([col, col, Color(col, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = int(r * 2.0)
	t.height = int(r * 2.0)
	return t


func _add_button(text: String, action: String, center: Vector2, r: float, fill: Color, ink: Color) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _disc_texture(r, fill)
	b.texture_pressed = _disc_texture(r, fill.lightened(0.3))
	if action != "":
		b.action = action
	var sh := CircleShape2D.new()
	sh.radius = r
	b.shape = sh
	b.shape_centered = true
	b.position = center - Vector2(r, r)
	b.set_meta("r", r)
	b.passby_press = false
	add_child(b)
	var l := UI.label(text, int(r * 0.42) if text.length() > 2 else int(r * 0.7), ink, UI.font("medium"), HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.size = Vector2(r * 2.0, r * 2.0)
	b.add_child(l)
	_buttons.append(b)
	return b


func _on_button(pos: Vector2) -> bool:
	for b in _buttons:
		if not b.visible:
			continue
		var r: float = b.get_meta("r")
		if pos.distance_to(b.position + Vector2(r, r)) <= r * 1.1:
			return true
	return false


func _input(event: InputEvent) -> void:
	if world == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if world.hud.note_open:
				world.close_note()
				return
			if _on_button(st.position) or world.paused or world.dying:
				return
			if st.position.x < vp.x * 0.45 and _stick_id == -1:
				_stick_id = st.index
				_stick_origin = st.position
				_stick_vec = Vector2.ZERO
				_base.visible = true
				_knob.visible = true
				_place_stick()
			elif st.position.x >= vp.x * 0.45 and _look_id == -1:
				_look_id = st.index
				_look_last = st.position
		else:
			if st.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				_base.visible = false
				_knob.visible = false
				_apply_stick()
			elif st.index == _look_id:
				_look_id = -1
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_id:
			var v := sd.position - _stick_origin
			if v.length() > STICK_R:
				# The stick follows the thumb if it wanders too far
				_stick_origin += v - v.normalized() * STICK_R
				v = v.normalized() * STICK_R
			_stick_vec = v / STICK_R
			_place_stick()
			_apply_stick()
		elif sd.index == _look_id and world.player and world.player.controls and world.player.look_enabled:
			var d := sd.position - _look_last
			_look_last = sd.position
			var s: float = float(Game.settings.sensitivity) * 0.018
			world.player._yaw -= d.x * s
			world.player._pitch = clampf(world.player._pitch - d.y * s, -1.45, 1.45)


func _place_stick() -> void:
	_base.position = _stick_origin - _base.size * 0.5
	_knob.position = _stick_origin + _stick_vec * STICK_R - _knob.size * 0.5


func _apply_stick() -> void:
	var v := _stick_vec
	if v.length() < 0.12:
		v = Vector2.ZERO
	_set_axis("move_right", maxf(v.x, 0.0))
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_back", maxf(v.y, 0.0))
	_set_axis("move_forward", maxf(-v.y, 0.0))


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func _process(_d: float) -> void:
	if world == null:
		return
	world.hud._right.visible = false
	_btn_e.visible = world.hud.prompt_box.visible
	for b in _buttons:
		if b != _btn_e:
			b.visible = not world.dying
