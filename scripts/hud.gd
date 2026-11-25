class_name Hud
extends CanvasLayer
## source hud x hyper-minimal phone. frosted widgets, a dynamic island, everything lowercase.

var world: World
var cells_num: Label
var cells_bar: ProgressBar
var cells_cap: Label
var batt_icon: BatteryIcon
var batt_num: Label
var batt_cap: Label
var island: PanelContainer
var island_label: Label
var timer_label: Label
var title_small: Label
var title_big: Label
var prompt_box: PanelContainer
var prompt_label: Label
var crosshair: Panel
var note_panel: PanelContainer
var note_text: Label
var death_root: ColorRect
var death_big: Label
var death_small: Label
var fade_rect: ColorRect
var pause_root: Control
var pause_menu: Control
var settings: SettingsPanel
var note_open := false
var _left: Control
var _right: Control
var _island_t := 0.0
var _island_tw: Tween
var nv_root: Control
var nv_rec: Label
var nv_tc: Label
var nv_range: Label
var nv_hdg: Label
var _t0 := 0.0
var gyro: Gyro


## Gyroscope / attitude indicator drawn inside the visor.
## Horizon + pitch ladder follow head tilt, the ring marker follows where you're actually moving,
## and the g-readout comes from the player's accelerometer.
class Gyro:
	extends Control
	var player: Player
	var col := Color(1, 1, 1, 0.72)
	var dim := Color(1, 1, 1, 0.32)
	var amber := Color(1.0, 0.78, 0.25, 0.9)
	var font: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = UI.font("medium")

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if player == null:
			return
		var c := size * 0.5
		var ppd := size.y / 70.0
		var roll := deg_to_rad(player.att_roll)
		var pitch := player.att_pitch
		var rot := Transform2D(-roll, c)
		draw_set_transform_matrix(rot)
		var off := pitch * ppd
		# horizon
		draw_line(Vector2(-260, off), Vector2(-40, off), col, 1.4, true)
		draw_line(Vector2(40, off), Vector2(260, off), col, 1.4, true)
		draw_line(Vector2(-260, off), Vector2(-260, off + 8), col, 1.4, true)
		draw_line(Vector2(260, off), Vector2(260, off + 8), col, 1.4, true)
		# pitch ladder
		for p in [-30, -20, -10, -5, 5, 10, 20, 30]:
			var y: float = off - p * ppd
			if absf(y) > size.y * 0.38:
				continue
			var w := 70.0 if absf(p) >= 10 else 38.0
			if p > 0:
				draw_line(Vector2(-w - 30, y), Vector2(-30, y), dim, 1.1, true)
				draw_line(Vector2(30, y), Vector2(w + 30, y), dim, 1.1, true)
			else:
				for k in 4:
					var a := -w - 30 + k * w / 4.0
					draw_line(Vector2(a, y), Vector2(a + w / 8.0, y), dim, 1.1, true)
					draw_line(Vector2(30 + k * w / 4.0, y), Vector2(30 + k * w / 4.0 + w / 8.0, y), dim, 1.1, true)
			if absf(p) >= 10:
				draw_string(font, Vector2(w + 38, y + 4), str(absi(p)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# roll arc + pointer (fixed to the visor)
		var rc := Vector2(c.x, c.y)
		var rr := size.y * 0.36
		draw_arc(rc, rr, deg_to_rad(-120), deg_to_rad(-60), 48, dim, 1.1, true)
		for d in [-30, -20, -10, 0, 10, 20, 30]:
			var a := deg_to_rad(-90 + d)
			var l := 10.0 if d % 30 == 0 else 6.0
			draw_line(rc + Vector2(cos(a), sin(a)) * rr, rc + Vector2(cos(a), sin(a)) * (rr - l), dim, 1.1, true)
		var pa := deg_to_rad(-90) - roll
		var tip := rc + Vector2(cos(pa), sin(pa)) * (rr - 4)
		var perp := Vector2(-sin(pa), cos(pa))
		var inward := -Vector2(cos(pa), sin(pa))
		draw_colored_polygon(PackedVector2Array([tip, tip + inward * 10 + perp * 5, tip + inward * 10 - perp * 5]), amber)
		# boresight
		draw_line(c + Vector2(-14, 0), c + Vector2(-5, 0), col, 1.4, true)
		draw_line(c + Vector2(5, 0), c + Vector2(14, 0), col, 1.4, true)
		draw_line(c + Vector2(0, 5), c + Vector2(0, 10), col, 1.4, true)
		# flight path marker: where you are actually going
		var v := player.vel_local
		if Vector2(v.x, v.z).length() > 0.4:
			var fov := deg_to_rad(player.cam.fov)
			var yaw_off := atan2(v.x, -v.z)
			var fp := c + Vector2(clampf(yaw_off / fov * size.y, -size.x * 0.4, size.x * 0.4), -pitch * ppd * 0.0 + v.y * 6.0)
			draw_arc(fp, 7, 0, TAU, 20, amber, 1.4, true)
			draw_line(fp + Vector2(-18, 0), fp + Vector2(-7, 0), amber, 1.4, true)
			draw_line(fp + Vector2(7, 0), fp + Vector2(18, 0), amber, 1.4, true)
			draw_line(fp + Vector2(0, -7), fp + Vector2(0, -13), amber, 1.4, true)
		# accelerometer readout
		var g := player.g_vec
		var txt := "g %.2f   lat %+.2f   lon %+.2f   roll %+.1f°   pitch %+.1f°" % [g.length(), g.x, g.z, player.att_roll, player.att_pitch]
		draw_string(font, Vector2(c.x - 230, c.y + rr + 34), txt, HORIZONTAL_ALIGNMENT_CENTER, 460, 12, col)
		# tiny g-ball
		var gb := c + Vector2(0, rr + 58)
		draw_arc(gb, 16, 0, TAU, 24, dim, 1.0, true)
		draw_circle(gb + Vector2(clampf(g.x, -1, 1), clampf(-g.z, -1, 1)) * 14.0, 3.0, amber)


## The hush logo: a closed eye.
class HushLogo:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(22, 18)

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.92)
		draw_arc(Vector2(11, 9), 9.0, 0, TAU, 32, c, 1.2, true)
		draw_arc(Vector2(11, 6), 7.0, deg_to_rad(30), deg_to_rad(150), 16, c, 1.2, true)
		for i in 3:
			var x := 6.0 + i * 5.0
			draw_line(Vector2(x, 12.5), Vector2(x - 0.5 + i * 0.5, 15.0), c, 1.0, true)


class BatteryIcon:
	extends Control
	var level := 100.0
	var on := true

	func _draw() -> void:
		var w := 30.0
		var h := 14.0
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color(0, 0, 0, 0)
		outline.border_color = Color(1, 1, 1, 0.55)
		outline.set_border_width_all(1)
		outline.set_corner_radius_all(4)
		outline.anti_aliasing = true
		draw_style_box(outline, Rect2(0, 0, w, h))
		draw_rect(Rect2(w + 1.5, h * 0.32, 2, h * 0.36), Color(1, 1, 1, 0.5))
		var fill := StyleBoxFlat.new()
		var c := UI.GREEN if level > 35.0 else (UI.AMBER if level > 15.0 else UI.RED)
		fill.bg_color = c if on else Color(1, 1, 1, 0.35)
		fill.set_corner_radius_all(2)
		fill.anti_aliasing = true
		var fw := maxf(0.0, (w - 4.0) * level / 100.0)
		if fw > 1.0:
			draw_style_box(fill, Rect2(2, 2, fw, h - 4))


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- bottom-left: brain cells (source health box, phone widget manners)
	_left = _widget(root, true)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	lv.position = Vector2(18, 12)
	_left.add_child(lv)
	cells_cap = UI.label("brain cells", 12, UI.SOFT, UI.font("medium"))
	lv.add_child(cells_cap)
	cells_num = UI.label("100", 44, UI.WHITE, UI.font("thin"))
	lv.add_child(cells_num)
	cells_bar = UI.bar(Color(1, 1, 1, 0.85), 170, 3)
	lv.add_child(cells_bar)

	# ---- bottom-right: flashlight battery
	_right = _widget(root, false)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	rv.position = Vector2(18, 12)
	_right.add_child(rv)
	batt_cap = UI.label("visor", 12, UI.SOFT, UI.font("medium"))
	rv.add_child(batt_cap)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	rv.add_child(bh)
	batt_num = UI.label("100%", 38, UI.WHITE, UI.font("thin"))
	bh.add_child(batt_num)
	batt_icon = BatteryIcon.new()
	batt_icon.custom_minimum_size = Vector2(36, 16)
	batt_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(batt_icon)

	# ---- dynamic island
	island = PanelContainer.new()
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color(0, 0, 0, 0.92)
	ist.set_corner_radius_all(22)
	ist.anti_aliasing = true
	ist.content_margin_left = 22
	ist.content_margin_right = 22
	ist.content_margin_top = 9
	ist.content_margin_bottom = 9
	island.add_theme_stylebox_override("panel", ist)
	island.anchor_left = 0.5
	island.anchor_right = 0.5
	island.offset_top = 14
	island.grow_horizontal = Control.GROW_DIRECTION_BOTH
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(island)
	island_label = UI.label("", 16, UI.WHITE, UI.font("light"), HORIZONTAL_ALIGNMENT_CENTER)
	island_label.custom_minimum_size = Vector2(90, 20)
	island.add_child(island_label)
	island.modulate.a = 0.0

	timer_label = UI.label("", 56, UI.AMBER, UI.font("thin"), HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(timer_label, 64)
	root.add_child(timer_label)

	# ---- hush visor overlay (telemetry, lowercase, thin)
	nv_root = UI.full_rect(Control.new())
	nv_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv_root.visible = false
	root.add_child(nv_root)
	var tl := VBoxContainer.new()
	tl.position = Vector2(64 if TouchControls.wanted() else 30, 26)
	nv_root.add_child(tl)
	var hl := HBoxContainer.new()
	hl.add_theme_constant_override("separation", 10)
	tl.add_child(hl)
	hl.add_child(HushLogo.new())
	hl.add_child(UI.label("hush · nv-7", 15, Color(1, 1, 1, 0.92), UI.font("medium")))
	nv_rec = UI.label("● rec", 13, UI.RED, UI.font("medium"))
	tl.add_child(nv_rec)
	nv_tc = UI.label("00:00:00:00", 13, Color(1, 1, 1, 0.75))
	tl.add_child(nv_tc)
	tl.add_child(UI.label("operative 03 · lantern", 12, Color(1, 1, 1, 0.5)))
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -254 if TouchControls.wanted() else -220
	tr.offset_right = -64 if TouchControls.wanted() else -30
	tr.offset_top = 26
	nv_root.add_child(tr)
	nv_range = UI.label("rng —", 15, Color(1, 1, 1, 0.92), UI.font("medium"), HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(nv_range)
	nv_hdg = UI.label("hdg 000°", 13, Color(1, 1, 1, 0.75), null, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(nv_hdg)
	tr.add_child(UI.label("ir · on · auto gain · gyro", 12, Color(1, 1, 1, 0.5), null, HORIZONTAL_ALIGNMENT_RIGHT))

	gyro = Gyro.new()
	UI.full_rect(gyro)
	nv_root.add_child(gyro)
	nv_root.move_child(gyro, 0)

	# ---- title card
	title_small = UI.label("", 13, UI.SOFT, UI.font("medium"), HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(title_small, -1, 0.40)
	root.add_child(title_small)
	title_big = UI.label("", 50, UI.WHITE, UI.font("thin"), HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(title_big, -1, 0.43)
	root.add_child(title_big)

	# ---- crosshair
	crosshair = Panel.new()
	var cst := StyleBoxFlat.new()
	cst.bg_color = Color(1, 1, 1, 0.75)
	cst.set_corner_radius_all(3)
	crosshair.add_theme_stylebox_override("panel", cst)
	_anchor_center(crosshair, Vector2(5, 5))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# ---- interaction prompt: (e) read note
	prompt_box = PanelContainer.new()
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(0.05, 0.05, 0.06, 0.55)
	pst.set_corner_radius_all(16)
	pst.content_margin_left = 8
	pst.content_margin_right = 16
	pst.content_margin_top = 6
	pst.content_margin_bottom = 6
	prompt_box.add_theme_stylebox_override("panel", pst)
	prompt_box.anchor_left = 0.5
	prompt_box.anchor_right = 0.5
	prompt_box.anchor_top = 0.5
	prompt_box.anchor_bottom = 0.5
	prompt_box.offset_top = 46
	prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_box)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	prompt_box.add_child(ph)
	var keycap := PanelContainer.new()
	var kst := StyleBoxFlat.new()
	kst.bg_color = UI.AMBER
	kst.set_corner_radius_all(7)
	kst.content_margin_left = 8
	kst.content_margin_right = 8
	keycap.add_theme_stylebox_override("panel", kst)
	ph.add_child(keycap)
	keycap.add_child(UI.label("e", 15, Color(0.1, 0.08, 0.02), UI.font("medium")))
	prompt_label = UI.label("", 16, UI.WHITE)
	ph.add_child(prompt_label)
	prompt_box.visible = false

	# ---- note reader (notes app)
	note_panel = PanelContainer.new()
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color(0.985, 0.975, 0.95)
	ns.set_corner_radius_all(22)
	ns.content_margin_left = 34
	ns.content_margin_right = 34
	ns.content_margin_top = 26
	ns.content_margin_bottom = 26
	ns.shadow_color = Color(0, 0, 0, 0.45)
	ns.shadow_size = 40
	ns.anti_aliasing = true
	note_panel.add_theme_stylebox_override("panel", ns)
	_anchor_center(note_panel, Vector2(600, 470))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 10)
	note_panel.add_child(nv)
	var nh := HBoxContainer.new()
	nv.add_child(nh)
	nh.add_child(UI.label("‹ notes", 16, Color(0.86, 0.62, 0.05), UI.font("medium")))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(sp)
	nh.add_child(UI.label("today, 3:00 am", 13, Color(0.55, 0.53, 0.5)))
	note_text = UI.label("", 18, Color(0.16, 0.15, 0.14))
	note_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	note_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	note_text.custom_minimum_size = Vector2(530, 340)
	nv.add_child(note_text)
	nv.add_child(UI.label("e  to close", 12, Color(0.6, 0.58, 0.55), null, HORIZONTAL_ALIGNMENT_CENTER))
	note_panel.visible = false
	root.add_child(note_panel)

	# ---- death / ending
	death_root = UI.full_rect(ColorRect.new())
	death_root.color = Color(0, 0, 0, 1)
	death_root.visible = false
	root.add_child(death_root)
	death_big = UI.label("", 52, UI.WHITE, UI.font("thin"), HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(death_big, -1, 0.42)
	death_root.add_child(death_big)
	death_small = UI.label("", 17, UI.SOFT, null, HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(death_small, -1, 0.53)
	death_small.autowrap_mode = TextServer.AUTOWRAP_WORD
	death_root.add_child(death_small)

	fade_rect = UI.full_rect(ColorRect.new())
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)

	# ---- pause: blurred world + grouped list
	pause_root = UI.full_rect(UI.glass(0.0, Color(0, 0, 0, 0.35), 0.0))
	(pause_root.material as ShaderMaterial).set_shader_parameter("blur", 5.0)
	pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.visible = false
	root.add_child(pause_root)
	var center := UI.full_rect(CenterContainer.new())
	pause_root.add_child(center)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 14)
	center.add_child(pv)
	pause_menu = pv
	pv.add_child(UI.label("paused", 40, UI.WHITE, UI.font("thin"), HORIZONTAL_ALIGNMENT_CENTER))
	var grp := UI.group_panel()
	grp.custom_minimum_size = Vector2(340, 0)
	pv.add_child(grp)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	grp.add_child(list)
	list.add_child(UI.button("resume", func(): world.set_paused(false)))
	list.add_child(_sep())
	list.add_child(UI.button("settings", _open_settings))
	list.add_child(_sep())
	list.add_child(UI.button("restart level", func(): Game.restart_level()))
	list.add_child(_sep())
	list.add_child(UI.button("main menu", func(): Game.main_menu()))
	settings = SettingsPanel.new()
	settings.visible = false
	center.add_child(settings)
	settings.closed.connect(func():
		settings.visible = false
		pause_menu.visible = true)


func _sep() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.custom_minimum_size = Vector2(0, 1)
	return c


func _widget(root: Control, left: bool) -> Control:
	var w := UI.glass(20.0)
	w.anchor_top = 1.0
	w.anchor_bottom = 1.0
	w.offset_top = -112
	w.offset_bottom = -24
	var m := 64 if TouchControls.wanted() else 26
	if left:
		w.offset_left = m
		w.offset_right = m + 210
	else:
		w.anchor_left = 1.0
		w.anchor_right = 1.0
		w.offset_left = -226
		w.offset_right = -26
	root.add_child(w)
	return w


func _center_h(l: Label, top := -1.0, anchor_y := 0.0) -> void:
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	if top >= 0.0:
		l.anchor_top = 0.0
		l.anchor_bottom = 0.0
		l.offset_top = top
	else:
		l.anchor_top = anchor_y
		l.anchor_bottom = anchor_y
	l.offset_left = 80
	l.offset_right = -80
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _anchor_center(c: Control, sz: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -sz.x * 0.5
	c.offset_right = sz.x * 0.5
	c.offset_top = -sz.y * 0.5
	c.offset_bottom = sz.y * 0.5


func _open_settings() -> void:
	pause_menu.visible = false
	settings.visible = true


# ------------------------------------------------------------------ island
func _set_island(t: String, expanded: bool) -> void:
	if _island_tw:
		_island_tw.kill()
	_island_tw = create_tween()
	if expanded:
		island_label.text = t.to_lower()
		island_label.modulate.a = 0.0
		island.offset_left = 0
		island.offset_right = 0
		_island_tw.tween_property(island, "modulate:a", 1.0, 0.15)
		_island_tw.tween_property(island_label, "modulate:a", 1.0, 0.3)
	else:
		_island_tw.tween_property(island_label, "modulate:a", 0.0, 0.2)
		_island_tw.tween_property(island, "modulate:a", 0.0, 0.25)


func _process(delta: float) -> void:
	if _island_t > 0.0:
		_island_t -= delta
		if _island_t <= 0.0:
			_set_island("", false)
	var c := Game.brain_cells
	cells_bar.value = c
	cells_num.text = str(int(ceil(c)))
	var col := UI.WHITE if c >= 60.0 else (UI.AMBER if c >= 30.0 else UI.RED)
	cells_num.add_theme_color_override("font_color", col)
	(cells_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = col
	cells_num.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012) if c < 30.0 else 1.0
	var on: bool = world != null and world.player != null and world.player.flashlight_on
	batt_num.text = "locked" if on else "boot…"
	batt_cap.text = "hush nv-7 · goggles"
	batt_icon.visible = false
	# visor telemetry
	nv_root.visible = on and not death_root.visible
	if world and world.player and gyro.player == null:
		gyro.player = world.player
	if on:
		_t0 += delta
		var tt := Time.get_ticks_msec() / 1000.0
		nv_rec.modulate.a = 1.0 if fmod(tt, 1.0) < 0.6 else 0.15
		var secs := 3 * 3600 + int(_t0)
		nv_tc.text = "%02d:%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60, int(fmod(_t0, 1.0) * 30.0)]
		var cam: Camera3D = world.player.cam
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 120.0, Geo.LAYER_WORLD | Geo.LAYER_ENEMY)
		q.exclude = [world.player.get_rid()]
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		nv_range.text = ("rng %.1f m" % cam.global_position.distance_to(hit.position)) if hit else "rng —"
		var hd := fposmod(-rad_to_deg(world.player.rotation.y), 360.0)
		var dirs := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
		nv_hdg.text = "hdg %03d° %s" % [int(hd), dirs[int(round(hd / 45.0)) % 8]]


# ------------------------------------------------------------------ api
func show_stats(on: bool) -> void:
	_left.visible = on
	_right.visible = on
	crosshair.visible = on


func objective(t: String) -> void:
	if TouchControls.wanted():
		t = t.replace("answer (q)", "tap the screen to answer")
	_set_island(t, true)
	_island_t = 8.0


func subtitle(t: String, dur := 3.0) -> void:
	_set_island(t, true)
	_island_t = dur


func title_card(t: String, n: String) -> void:
	title_small.text = t.to_lower()
	title_big.text = n.to_lower()
	title_small.modulate.a = 0.0
	title_big.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(title_small, "modulate:a", 1.0, 1.2).set_delay(0.8)
	tw.parallel().tween_property(title_big, "modulate:a", 1.0, 1.8).set_delay(1.1)
	tw.tween_interval(2.4)
	tw.tween_property(title_small, "modulate:a", 0.0, 1.4)
	tw.parallel().tween_property(title_big, "modulate:a", 0.0, 1.4)


func set_prompt(t: String) -> void:
	t = t.replace("[E]", "").strip_edges()
	prompt_box.visible = t != ""
	prompt_label.text = t.to_lower()


func set_timer(t: String, color := UI.AMBER) -> void:
	timer_label.text = t.to_lower()
	timer_label.add_theme_color_override("font_color", color)


func show_note(t: String) -> void:
	note_text.text = t.to_lower()
	note_panel.visible = true
	note_open = true


func hide_note() -> void:
	note_panel.visible = false
	note_open = false


func death(big: String, small: String, color := UI.WHITE, bg := Color.BLACK) -> void:
	death_root.visible = true
	death_root.color = bg
	death_big.text = big.to_lower()
	death_big.add_theme_color_override("font_color", color)
	death_small.text = small.to_lower()
	death_big.modulate.a = 0.0
	death_small.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(death_big, "modulate:a", 1.0, 1.2)
	tw.tween_property(death_small, "modulate:a", 1.0, 1.0)


func fade(to: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", to, dur)
	return tw


func set_pause_visible(on: bool) -> void:
	pause_root.visible = on
	pause_menu.visible = true
	settings.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if world and world.paused and event.is_action_pressed("pause"):
		if settings.visible:
			settings.visible = false
			pause_menu.visible = true
		else:
			world.set_paused(false)
		get_viewport().set_input_as_handled()
