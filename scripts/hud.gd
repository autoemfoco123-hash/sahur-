class_name Hud
extends CanvasLayer
## source hud x hyper-minimal phone. translucent widgets, a dynamic island, everything lowercase. (Godot 3)

var world
var cells_num: Label
var cells_bar: ProgressBar
var island: PanelContainer
var island_label: Label
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
var eyes: ColorRect         # eyelids (waking up)
var pause_root: ColorRect
var pause_menu: Control
var settings
var note_open = false
var nv_root: Control
var nv_rec: Label
var nv_tc: Label
var nv_range: Label
var nv_hdg: Label
var gyro
var spectate_label: Label
var photo_box: PanelContainer
var photo_img: TextureRect
var photo_score: Label
var photo_name: Label
var photo_grade: Label
var evidence: Label
var _bars = []
var _cine_label: Label
var missions_box: VBoxContainer
var points_label: Label
var points_pop: Label
var _photo_tw
var roster: Label
var _roster_t = 0.0
var _left: Control
var _right: Control
var _island_t = 0.0
var _t0 = 0.0
var boss_root: VBoxContainer   # a boss's name, health and state (sector 3.5)
var boss_name: Label
var boss_bar: ProgressBar
var boss_state: Label


## Gyroscope / attitude indicator drawn inside the goggles.
class Gyro:
	extends Control
	var player
	var col = Color(1, 1, 1, 0.72)
	var dim = Color(1, 1, 1, 0.32)
	var amber = Color(1.0, 0.78, 0.25, 0.9)
	var font: Font
	var small: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = UI.font("medium", 12)
		small = UI.font("medium", 11)

	func _process(_d: float) -> void:
		update()

	func _draw() -> void:
		if player == null:
			return
		var c = rect_size * 0.5
		var ppd = rect_size.y / 70.0
		var roll = deg2rad(player.att_roll)
		var pitch: float = player.att_pitch
		draw_set_transform(c, -roll, Vector2.ONE)
		var off = pitch * ppd
		draw_line(Vector2(-260, off), Vector2(-40, off), col, 1.4, true)
		draw_line(Vector2(40, off), Vector2(260, off), col, 1.4, true)
		draw_line(Vector2(-260, off), Vector2(-260, off + 8), col, 1.4, true)
		draw_line(Vector2(260, off), Vector2(260, off + 8), col, 1.4, true)
		for p in [-30, -20, -10, -5, 5, 10, 20, 30]:
			var y: float = off - p * ppd
			if abs(y) > rect_size.y * 0.38:
				continue
			var w = 70.0 if abs(p) >= 10 else 38.0
			if p > 0:
				draw_line(Vector2(-w - 30, y), Vector2(-30, y), dim, 1.1, true)
				draw_line(Vector2(30, y), Vector2(w + 30, y), dim, 1.1, true)
			else:
				for k in 4:
					var a = -w - 30 + k * w / 4.0
					draw_line(Vector2(a, y), Vector2(a + w / 8.0, y), dim, 1.1, true)
					draw_line(Vector2(30 + k * w / 4.0, y), Vector2(30 + k * w / 4.0 + w / 8.0, y), dim, 1.1, true)
			if abs(p) >= 10:
				draw_string(small, Vector2(w + 38, y + 4), str(int(abs(p))), dim)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rr = rect_size.y * 0.36
		draw_arc(c, rr, deg2rad(-120), deg2rad(-60), 48, dim, 1.1, true)
		for d in [-30, -20, -10, 0, 10, 20, 30]:
			var a = deg2rad(-90 + d)
			var l = 10.0 if d % 30 == 0 else 6.0
			draw_line(c + Vector2(cos(a), sin(a)) * rr, c + Vector2(cos(a), sin(a)) * (rr - l), dim, 1.1, true)
		var pa = deg2rad(-90) - roll
		var tip = c + Vector2(cos(pa), sin(pa)) * (rr - 4)
		var perp = Vector2(-sin(pa), cos(pa))
		var inward = -Vector2(cos(pa), sin(pa))
		draw_colored_polygon(PoolVector2Array([tip, tip + inward * 10 + perp * 5, tip + inward * 10 - perp * 5]), amber)
		draw_line(c + Vector2(-14, 0), c + Vector2(-5, 0), col, 1.4, true)
		draw_line(c + Vector2(5, 0), c + Vector2(14, 0), col, 1.4, true)
		draw_line(c + Vector2(0, 5), c + Vector2(0, 10), col, 1.4, true)
		var v: Vector3 = player.vel_local
		if Vector2(v.x, v.z).length() > 0.4:
			var fov = deg2rad(player.cam.fov)
			var yaw_off = atan2(v.x, -v.z)
			var fp = c + Vector2(clamp(yaw_off / fov * rect_size.y, -rect_size.x * 0.4, rect_size.x * 0.4), v.y * 6.0)
			draw_arc(fp, 7, 0, TAU, 20, amber, 1.4, true)
			draw_line(fp + Vector2(-18, 0), fp + Vector2(-7, 0), amber, 1.4, true)
			draw_line(fp + Vector2(7, 0), fp + Vector2(18, 0), amber, 1.4, true)
			draw_line(fp + Vector2(0, -7), fp + Vector2(0, -13), amber, 1.4, true)
		var g: Vector3 = player.g_vec
		var txt = "g %.2f   lat %+.2f   lon %+.2f   roll %+.1f°   pitch %+.1f°" % [g.length(), g.x, g.z, player.att_roll, player.att_pitch]
		var tw = font.get_string_size(txt).x
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + rr + 34), txt, col)
		var gb = c + Vector2(0, rr + 58)
		draw_arc(gb, 16, 0, TAU, 24, dim, 1.0, true)
		draw_circle(gb + Vector2(clamp(g.x, -1, 1), clamp(-g.z, -1, 1)) * 14.0, 3.0, amber)


## The hush logo: a closed eye.
class HushLogo:
	extends Control

	func _init() -> void:
		rect_min_size = Vector2(22, 18)

	func _draw() -> void:
		var c = Color(1, 1, 1, 0.92)
		draw_arc(Vector2(11, 9), 9.0, 0, TAU, 32, c, 1.2, true)
		draw_arc(Vector2(11, 6), 7.0, deg2rad(30), deg2rad(150), 16, c, 1.2, true)
		for i in 3:
			var x = 6.0 + i * 5.0
			draw_line(Vector2(x, 12.5), Vector2(x - 0.5 + i * 0.5, 15.0), c, 1.0, true)


func _ready() -> void:
	layer = 60
	pause_mode = Node.PAUSE_MODE_PROCESS
	var root = Control.new()
	UI.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# goggles telemetry + gyroscope
	nv_root = Control.new()
	UI.full_rect(nv_root)
	nv_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv_root.visible = false
	root.add_child(nv_root)
	gyro = Gyro.new()
	UI.full_rect(gyro)
	nv_root.add_child(gyro)
	var tl = VBoxContainer.new()
	tl.rect_position = Vector2(30, 26)
	nv_root.add_child(tl)
	var hl = HBoxContainer.new()
	hl.add_constant_override("separation", 10)
	tl.add_child(hl)
	hl.add_child(HushLogo.new())
	hl.add_child(UI.label("hush · nv-7", 15, UI.WHITE, "medium"))
	nv_rec = UI.label("● rec", 13, UI.RED, "medium")
	tl.add_child(nv_rec)
	nv_tc = UI.label("03:00:00:00", 13, Color(1, 1, 1, 0.75))
	tl.add_child(nv_tc)
	tl.add_child(UI.label("operative 03 · lantern", 12, Color(1, 1, 1, 0.5)))
	tl.add_child(UI.label(" ", 6))
	missions_box = VBoxContainer.new()
	missions_box.add_constant_override("separation", 1)
	tl.add_child(missions_box)
	var tr = VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.margin_left = -230
	tr.margin_right = -30
	tr.margin_top = 26
	nv_root.add_child(tr)
	nv_range = UI.label("rng —", 15, UI.WHITE, "medium", Label.ALIGN_RIGHT)
	tr.add_child(nv_range)
	nv_hdg = UI.label("hdg 000°", 13, Color(1, 1, 1, 0.75), "light", Label.ALIGN_RIGHT)
	tr.add_child(nv_hdg)
	tr.add_child(UI.label("ir · on · auto gain · gyro", 12, Color(1, 1, 1, 0.5), "light", Label.ALIGN_RIGHT))
	roster = UI.label("", 12, Color(1, 1, 1, 0.62), "light", Label.ALIGN_RIGHT)
	tr.add_child(UI.label(" ", 8))
	tr.add_child(roster)
	points_label = UI.label("0 pts", 24, UI.AMBER, "light", Label.ALIGN_RIGHT)
	tr.add_child(points_label)
	points_pop = UI.label("", 13, UI.AMBER, "medium", Label.ALIGN_RIGHT)
	points_pop.modulate.a = 0.0
	tr.add_child(points_pop)
	evidence = UI.label("evidence: none yet", 12, UI.AMBER, "medium", Label.ALIGN_RIGHT)
	tr.add_child(evidence)

	# bottom-left: brain cells
	_left = _widget(root, true)
	var lv = VBoxContainer.new()
	lv.add_constant_override("separation", 0)
	lv.rect_position = Vector2(18, 10)
	_left.add_child(lv)
	lv.add_child(UI.label("brain cells", 12, UI.SOFT, "medium"))
	cells_num = UI.label("100", 44, UI.WHITE, "thin")
	lv.add_child(cells_num)
	cells_bar = UI.bar(Color(1, 1, 1, 0.85), 170, 3)
	lv.add_child(cells_bar)
	# bottom-right: goggles status
	_right = _widget(root, false)
	var rv = VBoxContainer.new()
	rv.add_constant_override("separation", 2)
	rv.rect_position = Vector2(18, 10)
	_right.add_child(rv)
	rv.add_child(UI.label("hush nv-7 · goggles", 12, UI.SOFT, "medium"))
	rv.add_child(UI.label("locked", 38, UI.WHITE, "thin"))

	# dynamic island
	island = PanelContainer.new()
	var ist = StyleBoxFlat.new()
	ist.bg_color = Color(0, 0, 0, 0.92)
	ist.set_corner_radius_all(22)
	ist.anti_aliasing = true
	ist.content_margin_left = 22
	ist.content_margin_right = 22
	ist.content_margin_top = 9
	ist.content_margin_bottom = 9
	island.add_stylebox_override("panel", ist)
	island.anchor_left = 0.5
	island.anchor_right = 0.5
	island.margin_top = 14
	island.grow_horizontal = Control.GROW_DIRECTION_BOTH
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(island)
	island_label = UI.label("", 16, UI.WHITE, "light", Label.ALIGN_CENTER)
	island.add_child(island_label)
	island.modulate.a = 0.0

	# a boss: name, health, what its shield is doing
	boss_root = VBoxContainer.new()
	boss_root.add_constant_override("separation", 4)
	boss_root.anchor_left = 0.5
	boss_root.anchor_right = 0.5
	boss_root.margin_left = -220
	boss_root.margin_right = 220
	boss_root.margin_top = 66
	boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.visible = false
	root.add_child(boss_root)
	boss_name = UI.label("", 15, UI.WHITE, "medium", Label.ALIGN_CENTER)
	boss_root.add_child(boss_name)
	boss_bar = UI.bar(Color(1.0, 0.16, 0.1), 440, 6)
	boss_root.add_child(boss_bar)
	boss_state = UI.label("", 12, UI.SOFT, "medium", Label.ALIGN_CENTER)
	boss_root.add_child(boss_state)

	# title card
	title_small = UI.label("", 13, UI.SOFT, "medium", Label.ALIGN_CENTER)
	_center_h(title_small, 0.40)
	root.add_child(title_small)
	title_big = UI.label("", 50, UI.WHITE, "thin", Label.ALIGN_CENTER)
	_center_h(title_big, 0.43)
	root.add_child(title_big)

	# crosshair
	crosshair = Panel.new()
	var cst = StyleBoxFlat.new()
	cst.bg_color = Color(1, 1, 1, 0.75)
	cst.set_corner_radius_all(3)
	crosshair.add_stylebox_override("panel", cst)
	_anchor_center(crosshair, Vector2(5, 5))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# prompt: (e) read note
	prompt_box = PanelContainer.new()
	var pst = StyleBoxFlat.new()
	pst.bg_color = Color(0.05, 0.05, 0.06, 0.55)
	pst.set_corner_radius_all(16)
	pst.content_margin_left = 8
	pst.content_margin_right = 16
	pst.content_margin_top = 6
	pst.content_margin_bottom = 6
	prompt_box.add_stylebox_override("panel", pst)
	prompt_box.anchor_left = 0.5
	prompt_box.anchor_right = 0.5
	prompt_box.anchor_top = 0.5
	prompt_box.anchor_bottom = 0.5
	prompt_box.margin_top = 46
	prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_box)
	var ph = HBoxContainer.new()
	ph.add_constant_override("separation", 10)
	prompt_box.add_child(ph)
	var keycap = PanelContainer.new()
	var kst = StyleBoxFlat.new()
	kst.bg_color = UI.AMBER
	kst.set_corner_radius_all(7)
	kst.content_margin_left = 8
	kst.content_margin_right = 8
	keycap.add_stylebox_override("panel", kst)
	ph.add_child(keycap)
	keycap.add_child(UI.label("e", 15, Color(0.1, 0.08, 0.02), "medium"))
	prompt_label = UI.label("", 16, UI.WHITE)
	ph.add_child(prompt_label)
	prompt_box.visible = false

	# note reader (notes app)
	note_panel = PanelContainer.new()
	var ns = StyleBoxFlat.new()
	ns.bg_color = Color(0.985, 0.975, 0.95)
	ns.set_corner_radius_all(22)
	ns.content_margin_left = 34
	ns.content_margin_right = 34
	ns.content_margin_top = 26
	ns.content_margin_bottom = 26
	ns.shadow_color = Color(0, 0, 0, 0.45)
	ns.shadow_size = 40
	ns.anti_aliasing = true
	note_panel.add_stylebox_override("panel", ns)
	_anchor_center(note_panel, Vector2(600, 470))
	var nv = VBoxContainer.new()
	nv.add_constant_override("separation", 10)
	note_panel.add_child(nv)
	var nh = HBoxContainer.new()
	nv.add_child(nh)
	nh.add_child(UI.label("‹ notes", 16, Color(0.86, 0.62, 0.05), "medium"))
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(sp)
	nh.add_child(UI.label("today, 3:00 am", 13, Color(0.55, 0.53, 0.5)))
	note_text = UI.label("", 18, Color(0.16, 0.15, 0.14))
	note_text.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	note_text.autowrap = true
	note_text.rect_min_size = Vector2(530, 340)
	nv.add_child(note_text)
	nv.add_child(UI.label("e  to close", 12, Color(0.6, 0.58, 0.55), "light", Label.ALIGN_CENTER))
	note_panel.visible = false
	root.add_child(note_panel)

	# the last photo, like a polaroid sliding out of the camera
	photo_box = PanelContainer.new()
	var pst2 = StyleBoxFlat.new()
	pst2.bg_color = Color(0.95, 0.94, 0.9)
	pst2.set_corner_radius_all(5)
	pst2.content_margin_left = 10
	pst2.content_margin_right = 10
	pst2.content_margin_top = 10
	pst2.content_margin_bottom = 12
	pst2.shadow_color = Color(0, 0, 0, 0.5)
	pst2.shadow_size = 18
	photo_box.add_stylebox_override("panel", pst2)
	photo_box.anchor_left = 1.0
	photo_box.anchor_right = 1.0
	photo_box.anchor_top = 0.5
	photo_box.anchor_bottom = 0.5
	photo_box.margin_left = -380
	photo_box.margin_right = -40
	photo_box.margin_top = -170
	photo_box.margin_bottom = 90
	photo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_box.visible = false
	root.add_child(photo_box)
	var pv2 = VBoxContainer.new()
	pv2.add_constant_override("separation", 6)
	photo_box.add_child(pv2)
	photo_img = TextureRect.new()
	photo_img.rect_min_size = Vector2(320, 180)
	photo_img.expand = true
	photo_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pv2.add_child(photo_img)
	var prow = HBoxContainer.new()
	prow.add_constant_override("separation", 12)
	pv2.add_child(prow)
	photo_score = UI.label("0", 40, Color(0.08, 0.08, 0.08), "thin")
	photo_score.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	prow.add_child(photo_score)
	var pcol = VBoxContainer.new()
	prow.add_child(pcol)
	photo_name = UI.label("", 14, Color(0.12, 0.12, 0.12), "medium")
	photo_name.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	pcol.add_child(photo_name)
	photo_grade = UI.label("", 13, Color(0.38, 0.36, 0.33))
	photo_grade.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	pcol.add_child(photo_grade)

	# spectating line
	spectate_label = UI.label("", 16, UI.WHITE, "light", Label.ALIGN_CENTER)
	spectate_label.anchor_left = 0.0
	spectate_label.anchor_right = 1.0
	spectate_label.anchor_top = 1.0
	spectate_label.anchor_bottom = 1.0
	spectate_label.margin_top = -70
	root.add_child(spectate_label)

	# death / ending
	death_root = ColorRect.new()
	UI.full_rect(death_root)
	death_root.color = Color(0, 0, 0, 1)
	death_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_root.visible = false
	root.add_child(death_root)
	death_big = UI.label("", 52, UI.WHITE, "thin", Label.ALIGN_CENTER)
	_center_h(death_big, 0.42)
	death_root.add_child(death_big)
	death_small = UI.label("", 17, UI.SOFT, "light", Label.ALIGN_CENTER)
	_center_h(death_small, 0.53)
	death_small.autowrap = true
	death_root.add_child(death_small)

	eyes = ColorRect.new()
	UI.full_rect(eyes)
	eyes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var em = ShaderMaterial.new()
	em.shader = load("res://scripts/eyelids.shader")
	eyes.material = em
	eyes.visible = false
	root.add_child(eyes)
	fade_rect = ColorRect.new()
	UI.full_rect(fade_rect)
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)

	# pause
	pause_root = ColorRect.new()
	UI.full_rect(pause_root)
	pause_root.color = Color(0, 0, 0, 0.7)
	pause_root.visible = false
	root.add_child(pause_root)
	var center = CenterContainer.new()
	UI.full_rect(center)
	pause_root.add_child(center)
	var pv = VBoxContainer.new()
	pv.add_constant_override("separation", 14)
	center.add_child(pv)
	pause_menu = pv
	pv.add_child(UI.label("paused", 40, UI.WHITE, "thin", Label.ALIGN_CENTER))
	var grp = UI.group_panel()
	grp.rect_min_size = Vector2(340, 0)
	pv.add_child(grp)
	var list = VBoxContainer.new()
	list.add_constant_override("separation", 2)
	grp.add_child(list)
	list.add_child(UI.button("resume", self, "_resume"))
	list.add_child(_sep())
	list.add_child(UI.button("settings", self, "_open_settings"))
	list.add_child(_sep())
	if Net.active():
		list.add_child(UI.button("leave the round", Net, "leave"))
	else:
		list.add_child(UI.button("restart level", Game, "restart_level"))
		list.add_child(_sep())
		list.add_child(UI.button("main menu", Game, "main_menu"))
	settings = load("res://scripts/settings_panel.gd").new()
	settings.visible = false
	center.add_child(settings)
	settings.connect("closed", self, "_close_settings")


func _sep() -> Control:
	var c = ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.rect_min_size = Vector2(0, 1)
	return c


func _widget(root: Control, left: bool) -> Control:
	var w = UI.glass(20)
	w.anchor_top = 1.0
	w.anchor_bottom = 1.0
	w.margin_top = -112
	w.margin_bottom = -24
	if left:
		w.margin_left = 26
		w.margin_right = 236
	else:
		w.anchor_left = 1.0
		w.anchor_right = 1.0
		w.margin_left = -226
		w.margin_right = -26
	root.add_child(w)
	return w


func _center_h(l: Label, anchor_y: float) -> void:
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = anchor_y
	l.anchor_bottom = anchor_y
	l.margin_left = 80
	l.margin_right = -80


func _anchor_center(c: Control, sz: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.margin_left = -sz.x * 0.5
	c.margin_right = sz.x * 0.5
	c.margin_top = -sz.y * 0.5
	c.margin_bottom = sz.y * 0.5


func _resume() -> void:
	world.set_paused(false)


func _open_settings() -> void:
	pause_menu.visible = false
	settings.visible = true


func _close_settings() -> void:
	settings.visible = false
	pause_menu.visible = true


# ------------------------------------------------------------------ island
func _set_island(t: String, expanded: bool) -> void:
	var tw = create_tween()
	if expanded:
		island_label.text = t.to_lower()
		island_label.modulate.a = 0.0
		island.margin_left = 0
		island.margin_right = 0
		tw.tween_property(island, "modulate:a", 1.0, 0.15)
		tw.tween_property(island_label, "modulate:a", 1.0, 0.3)
	else:
		tw.tween_property(island_label, "modulate:a", 0.0, 0.2)
		tw.tween_property(island, "modulate:a", 0.0, 0.25)


func _process(delta: float) -> void:
	if _island_t > 0.0:
		_island_t -= delta
		if _island_t <= 0.0:
			_set_island("", false)
	_roster_t -= delta
	if _roster_t <= 0.0 and Net.active():
		_roster_t = 0.5
		var lines = PoolStringArray()
		for pid in Net.round_ids():
			var p = Net.players[pid]
			var si = int(clamp(int(p.get("sector", 0)), 0, Game.LEVELS.size() - 1))
			var st = "out" if p.escaped else ("rot" if not p.alive else Game.INFO.get(Game.LEVELS[si], {}).get("title", "sector %d" % si))
			lines.append("%s · %s · %d" % [p.name, st, int(p.get("points", 0))])
		roster.text = lines.join("\n")
	var c = Game.brain_cells
	cells_bar.value = c
	cells_num.text = str(int(ceil(c)))
	var col = UI.WHITE if c >= 60.0 else (UI.AMBER if c >= 30.0 else UI.RED)
	cells_num.add_color_override("font_color", col)
	(cells_bar.get_stylebox("fg") as StyleBoxFlat).bg_color = col
	cells_num.modulate.a = 0.55 + 0.45 * sin(OS.get_ticks_msec() * 0.012) if c < 30.0 else 1.0
	if world == null or world.player == null:
		return
	var on: bool = world.player.flashlight_on
	nv_root.visible = on and not death_root.visible and world._scare == 0
	if gyro.player == null:
		gyro.player = world.player
	if on:
		_t0 += delta
		var tt = OS.get_ticks_msec() / 1000.0
		nv_rec.modulate.a = 1.0 if fmod(tt, 1.0) < 0.6 else 0.15
		var secs = 3 * 3600 + int(_t0)
		nv_tc.text = "%02d:%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60, int(fmod(_t0, 1.0) * 30.0)]
		var cam: Camera = world.player.cam
		var from = cam.global_transform.origin
		var hit = cam.get_world().direct_space_state.intersect_ray(from, from - cam.global_transform.basis.z * 120.0, [world.player], Geo.LAYER_WORLD | Geo.LAYER_ENEMY)
		nv_range.text = ("rng %.1f m" % from.distance_to(hit.position)) if not hit.empty() else "rng —"
		var hd = fposmod(-rad2deg(world.player.rotation.y), 360.0)
		var dirs = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
		nv_hdg.text = "hdg %03d° %s" % [int(hd), dirs[int(round(hd / 45.0)) % 8]]


# ------------------------------------------------------------------ api
## A boss's bar (frac 0..1); exposed: its shield is down (the bar burns brighter).
func boss(show: bool, name := "", frac := 1.0, state := "", exposed := false) -> void:
	boss_root.visible = show and not death_root.visible
	if not show:
		return
	boss_name.text = name.to_upper()
	boss_bar.value = clamp(frac, 0.0, 1.0) * 100.0
	boss_state.text = state
	var col = Color(1.0, 0.85, 0.8) if exposed else Color(1.0, 0.16, 0.1)
	(boss_bar.get_stylebox("fg") as StyleBoxFlat).bg_color = col
	boss_state.add_color_override("font_color", UI.WHITE if exposed else UI.SOFT)


func show_stats(on: bool) -> void:
	_left.visible = on
	_right.visible = on
	crosshair.visible = on


## A photo was taken: show it with its score, then let it slide away.
func show_photo(tex: Texture, r: Dictionary, is_best: bool, best: Dictionary) -> void:
	photo_img.texture = tex
	photo_score.text = str(r.score)
	photo_name.text = r.name.to_lower()
	var tail = ""
	if r.get("inst", -1) >= 0:
		tail = ("   +%d pts" % r.gain) if r.get("gain", 0) > 0 else "   no better than your last one"
	photo_grade.text = (r.grade + ("   new best" if is_best else "") + tail).to_lower()
	photo_box.visible = true
	photo_box.modulate.a = 0.0
	photo_box.rect_rotation = rand_range(-3.0, 3.0)
	if _photo_tw and _photo_tw.is_valid():
		_photo_tw.kill()
	_photo_tw = create_tween()
	_photo_tw.tween_property(photo_box, "modulate:a", 1.0, 0.15)
	_photo_tw.tween_interval(3.2)
	_photo_tw.tween_property(photo_box, "modulate:a", 0.0, 0.5)
	_photo_tw.tween_callback(photo_box, "hide")
	var parts = PoolStringArray()
	for k in best:
		parts.append("%s %d" % [k, best[k]])
	evidence.text = ("evidence: " + parts.join(" · ")) if parts.size() > 0 else "evidence: none yet"


## The missions of the sector you are in: ○ to do (with progress), ✓ done.
func set_missions(title: String, ms: Array) -> void:
	for c in missions_box.get_children():
		missions_box.remove_child(c)
		c.queue_free()
	if ms.empty():
		return
	missions_box.add_child(UI.label(("missions · " + title).to_lower(), 14, UI.AMBER, "medium"))
	for m in ms:
		var t = LevelBase.mission_text(m)
		var l = UI.label((("✓  " if m.done else "○  ") + t).to_lower(), 14, UI.GREEN if m.done else UI.WHITE, "medium")
		l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
		l.add_constant_override("shadow_offset_x", 1)
		l.add_constant_override("shadow_offset_y", 1)
		missions_box.add_child(l)


func flash_missions() -> void:
	var tw = create_tween()
	for i in 3:
		tw.tween_property(missions_box, "modulate", Color(1.0, 0.6, 0.2), 0.12)
		tw.tween_property(missions_box, "modulate", Color(1, 1, 1), 0.18)


func set_points(total: int, gain := 0, why := "") -> void:
	points_label.text = "%d pts" % total
	if gain <= 0:
		return
	points_pop.text = ("+%d  %s" % [gain, why]).to_lower()
	points_pop.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(points_pop, "modulate:a", 0.0, 0.8)


## Cutscene framing: black bars slide in, the widgets step aside.
func cinematic(on: bool) -> void:
	if not on and _cine_label:
		_cine_label.text = ""
	if _bars.empty():
		for top in [true, false]:
			var b = ColorRect.new()
			b.color = Color(0, 0, 0, 1)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.anchor_right = 1.0
			if top:
				b.anchor_bottom = 0.0
			else:
				b.anchor_top = 1.0
				b.anchor_bottom = 1.0
			add_child(b)
			_bars.append(b)
	var vp = get_viewport().get_visible_rect().size
	var h = vp.y * 0.11 if on else 0.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_bars[0], "margin_bottom", h, 0.8)
	tw.tween_property(_bars[1], "margin_top", -h, 0.8)
	show_stats(not on)
	missions_box.visible = not on
	nv_root.modulate.a = 0.35 if on else 1.0


## A line of the cutscene, in the bottom bar: who, then what they say.
func cine_line(who: String, text: String) -> void:
	if _cine_label == null:
		_cine_label = UI.label("", 20, UI.WHITE, "light", Label.ALIGN_CENTER)
		_cine_label.autowrap = true
		_cine_label.valign = Label.VALIGN_CENTER
		_cine_label.anchor_left = 0.08
		_cine_label.anchor_right = 0.92
		_cine_label.anchor_top = 0.89
		_cine_label.anchor_bottom = 1.0
		_cine_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_cine_label)
	_cine_label.raise()
	if text == "":
		_cine_label.text = ""
		return
	_cine_label.text = ("%s   %s" % [who + ":" if who != "" else "", text]).to_lower()
	_cine_label.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(_cine_label, "modulate:a", 1.0, 0.25)


## The world tears: jagged red cracks shoot across the screen from the middle, then fade.
func crack_overlay() -> void:
	var vp = get_viewport().get_visible_rect().size
	var c = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(c)
	add_child(c)
	var r = RandomNumberGenerator.new()
	r.randomize()
	for k in 7:
		var dir = Vector2(cos(k * TAU / 7.0 + r.randf_range(-0.3, 0.3)), sin(k * TAU / 7.0 + r.randf_range(-0.3, 0.3)))
		var p = vp * 0.5 + Vector2(r.randf_range(-30, 30), r.randf_range(-20, 20))
		var pts = PoolVector2Array([p])
		while p.x > -50 and p.y > -50 and p.x < vp.x + 50 and p.y < vp.y + 50:
			p += dir.rotated(r.randf_range(-0.6, 0.6)) * r.randf_range(26, 60)
			pts.append(p)
		for layer in [[7.0, Color(0.05, 0.0, 0.0, 0.9)], [2.5, Color(1.0, 0.25, 0.12, 1.0)]]:
			var l = Line2D.new()
			l.points = pts
			l.width = layer[0]
			l.default_color = layer[1]
			l.joint_mode = Line2D.LINE_JOINT_SHARP
			c.add_child(l)
	var tw = create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(c, "modulate:a", 0.0, 1.2)
	tw.tween_callback(c, "queue_free")


func set_spectate(t: String) -> void:
	spectate_label.text = t.to_lower()


func objective(t: String) -> void:
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
	var tw = create_tween()
	tw.tween_property(title_small, "modulate:a", 1.0, 1.2).set_delay(0.8)
	tw.parallel().tween_property(title_big, "modulate:a", 1.0, 1.8).set_delay(1.1)
	tw.tween_interval(2.4)
	tw.tween_property(title_small, "modulate:a", 0.0, 1.4)
	tw.parallel().tween_property(title_big, "modulate:a", 0.0, 1.4)


func set_prompt(t: String) -> void:
	prompt_box.visible = t != ""
	prompt_label.text = t.to_lower()


func show_note(t: String) -> void:
	note_text.text = t.to_lower()
	note_panel.visible = true
	note_open = true


func hide_note() -> void:
	note_panel.visible = false
	note_open = false


func death(big: String, small: String, color := UI.WHITE) -> void:
	death_root.visible = true
	death_root.raise()  # above the fade overlay (the ending fades to black first)
	death_big.text = big.to_lower()
	death_big.add_color_override("font_color", color)
	death_small.text = small.to_lower()
	death_big.modulate.a = 0.0
	death_small.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(death_big, "modulate:a", 1.0, 1.2)
	tw.tween_property(death_small, "modulate:a", 1.0, 1.0)


## Eyelids: 0 shut .. 1 open.
func set_eyes(open: float) -> void:
	eyes.visible = open < 0.995
	eyes.material.set_shader_param("open", open)


func fade(to: float, dur: float):
	var tw = create_tween()
	tw.tween_property(fade_rect, "color:a", to, dur)
	return tw


func set_pause_visible(on: bool) -> void:
	pause_root.visible = on
	pause_menu.visible = true
	settings.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if world and world.paused and event.is_action_pressed("pause"):
		if settings.visible:
			_close_settings()
		else:
			world.set_paused(false)
		get_tree().set_input_as_handled()
