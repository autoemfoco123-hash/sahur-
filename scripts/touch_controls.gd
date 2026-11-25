extends CanvasLayer
## Phone / tablet controls, same minimal language as the hud (Godot 3):
## left thumb  = floating analog joystick (walk)
## right thumb = drag to look
## tap         = answer him (only while he is calling)
## buttons     = e (only when something is interactable) · crouch · pause

const STICK_R = 70.0

var world
var _stick_id = -1
var _stick_origin = Vector2.ZERO
var _stick_vec = Vector2.ZERO
var _look_id = -1
var _look_last = Vector2.ZERO
var _look_start = Vector2.ZERO
var _look_t0 = 0
var _crouch = false
var _base: Control
var _knob: Control
var _btn_e: TouchScreenButton
var _buttons = []


static func wanted() -> bool:
	return OS.has_feature("mobile") or OS.has_touchscreen_ui_hint() or Game.force_touch


func _ready() -> void:
	layer = 61
	pause_mode = Node.PAUSE_MODE_PROCESS
	var root = Control.new()
	UI.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_base = _circle(STICK_R * 2.0, Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.35))
	root.add_child(_base)
	_knob = _circle(64.0, Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0))
	root.add_child(_knob)
	_base.visible = false
	_knob.visible = false
	_btn_e = _add_button("e", "interact", 46.0, Color(1, 1, 1, 0.85), Color(0.08, 0.08, 0.08))
	var bc = _add_button("crouch", "", 34.0, Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.9))
	bc.connect("pressed", self, "_on_crouch")
	var bp = _add_button("ii", "", 26.0, Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.9))
	bp.connect("pressed", self, "_on_pause")
	get_viewport().connect("size_changed", self, "_relayout")
	_relayout()


func _on_crouch() -> void:
	_crouch = not _crouch
	if _crouch:
		Input.action_press("crouch")
	else:
		Input.action_release("crouch")


func _on_pause() -> void:
	if world:
		world.set_paused(not world.paused)


func _relayout() -> void:
	var vp = get_viewport().get_visible_rect().size
	var spots = [Vector2(vp.x - 130, vp.y - 110), Vector2(vp.x - 115, vp.y - 285), Vector2(vp.x - 90, 150)]
	for i in _buttons.size():
		var b = _buttons[i]
		var r: float = b.get_meta("r")
		b.position = spots[i] - Vector2(r, r)


func _circle(d: float, fill: Color, ring: Color) -> Panel:
	var p = Panel.new()
	var s = StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = ring
	s.set_border_width_all(2 if ring.a > 0.0 else 0)
	s.set_corner_radius_all(int(d * 0.5))
	s.anti_aliasing = true
	p.add_stylebox_override("panel", s)
	p.rect_size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _disc_texture(r: float, col: Color) -> Texture:
	var g = Gradient.new()
	g.offsets = PoolRealArray([0.0, 0.93, 1.0])
	g.colors = PoolColorArray([col, col, Color(col.r, col.g, col.b, 0.0)])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = int(r * 2.0)
	t.height = int(r * 2.0)
	return t


func _add_button(text: String, action: String, r: float, fill: Color, ink: Color) -> TouchScreenButton:
	var b = TouchScreenButton.new()
	b.normal = _disc_texture(r, fill)
	b.pressed = _disc_texture(r, fill.lightened(0.3))
	if action != "":
		b.action = action
	var sh = CircleShape2D.new()
	sh.radius = r
	b.shape = sh
	b.shape_centered = true
	b.set_meta("r", r)
	b.passby_press = false
	add_child(b)
	var l = UI.label(text, int(r * 0.42) if text.length() > 2 else int(r * 0.7), ink, "medium", Label.ALIGN_CENTER)
	l.valign = Label.VALIGN_CENTER
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	l.rect_size = Vector2(r * 2.0, r * 2.0)
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
	if world == null or world.hud == null:
		return
	var vp = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if world.hud.note_open:
				world.close_note()
				return
			if _on_button(event.position) or world.paused or world.dying or world.my_out:
				return
			if event.position.x < vp.x * 0.45 and _stick_id == -1:
				_stick_id = event.index
				_stick_origin = event.position
				_stick_vec = Vector2.ZERO
				_base.visible = true
				_knob.visible = true
				_place_stick()
			elif event.position.x >= vp.x * 0.45 and _look_id == -1:
				_look_id = event.index
				_look_last = event.position
				_look_start = event.position
				_look_t0 = OS.get_ticks_msec()
		else:
			if event.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				_base.visible = false
				_knob.visible = false
				_apply_stick()
			elif event.index == _look_id:
				_look_id = -1
				# A quick tap (no drag) while he is calling = you answer him.
				var quick = OS.get_ticks_msec() - _look_t0 < 300 and event.position.distance_to(_look_start) < 18.0
				if quick and _he_is_calling():
					var ev = InputEventAction.new()
					ev.action = "shout"
					ev.pressed = true
					Input.parse_input_event(ev)
					var ev2 = InputEventAction.new()
					ev2.action = "shout"
					ev2.pressed = false
					Input.parse_input_event(ev2)
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			var v = event.position - _stick_origin
			if v.length() > STICK_R:
				# the stick follows the thumb if it wanders too far
				_stick_origin += v - v.normalized() * STICK_R
				v = v.normalized() * STICK_R
			_stick_vec = v / STICK_R
			_place_stick()
			_apply_stick()
		elif event.index == _look_id and world.player and world.player.controls and world.player.look_enabled:
			var d = event.position - _look_last
			_look_last = event.position
			var s: float = float(Game.settings.sensitivity) * 0.018
			world.player._yaw -= d.x * s
			world.player._pitch = clamp(world.player._pitch - d.y * s, -1.45, 1.45)


func _he_is_calling() -> bool:
	var l = world.level
	return l != null and "calling" in l and l.calling and not l.answered


func _place_stick() -> void:
	_base.rect_position = _stick_origin - _base.rect_size * 0.5
	_knob.rect_position = _stick_origin + _stick_vec * STICK_R - _knob.rect_size * 0.5


func _apply_stick() -> void:
	var v = _stick_vec
	if v.length() < 0.12:
		v = Vector2.ZERO
	_set_axis("move_right", max(v.x, 0.0))
	_set_axis("move_left", max(-v.x, 0.0))
	_set_axis("move_back", max(v.y, 0.0))
	_set_axis("move_forward", max(-v.y, 0.0))


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, clamp(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func _process(_d: float) -> void:
	if world == null or world.hud == null:
		return
	world.hud._right.visible = false
	_btn_e.visible = world.hud.prompt_box.visible
	for b in _buttons:
		if b != _btn_e:
			b.visible = not world.dying and not world.my_out
