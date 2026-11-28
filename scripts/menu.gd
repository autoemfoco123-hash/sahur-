extends Spatial

const LightBake = preload("res://scripts/light_bake.gd")
const OfficeMesh = preload("res://scripts/office_mesh.gd")

## Title screen: an office hallway that never ends, and something standing at the end of it. (Godot 3)

var cam: Camera
var tung: Spatial
var post: ShaderMaterial
var menu: VBoxContainer
var host_box: VBoxContainer
var join_box: VBoxContainer
var lobby_box: VBoxContainer
var host_name: LineEdit
var join_name: LineEdit
var join_ip: LineEdit
var join_code: LineEdit
var code_label: Label
var _info_t = 0.0
var lan_list: VBoxContainer
var lobby_title: Label
var lobby_info: Label
var lobby_players: VBoxContainer
var chat_label: Label
var chat_field: LineEdit
var ready_btn: Button
var start_btn: Button
var sector_btn: Label
var status: Label
var count_label: Label
var settings
var title: Label
var _t = 0.0
var _jump = 6.0
var _lights = []


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	if Net.dedicated or "--server" in OS.get_cmdline_args():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	Audio.silence_all(false)
	Audio.set_silence(false)
	var we = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.black
	env.ambient_light_color = Color(0.92, 0.88, 0.62)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = int(Game.settings.gfx) >= 1
	env.fog_enabled = true
	env.fog_color = Color(0.5, 0.48, 0.34)
	env.fog_depth_enabled = true
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 55.0
	env.fog_depth_curve = 1.6
	we.environment = env
	add_child(we)
	# the same baked office as the game: one long hallway
	var om = OfficeMesh.new()
	om.plane("floor", Vector2(-1.8, -58), Vector2(1.8, 6), 0.0, true)
	om.plane("ceiling", Vector2(-1.8, -58), Vector2(1.8, 6), 2.75, false)
	var walls = []
	for x in [-1.75, 1.75]:
		om.box_sides("wall", Vector3(x, 1.375, -26), Vector3(0.3, 2.75, 64))
		walls.append([Vector2(x, -26), Vector2(0.3, 64)])
	var lamp_xz = []
	var lamp_pos = []
	for i in 8:
		var p = Vector3(0.3, 2.746, 4.2 - i * 7.8)
		p.z = floor(p.z / 0.6) * 0.6 + 0.3
		om.panel(p)
		lamp_pos.append(p)
		lamp_xz.append(Vector2(p.x, p.z))
	var bake = LightBake.new()
	add_child(bake)
	bake.build(Rect2(-32, -60, 64, 64), lamp_xz, walls)
	om.commit(self, bake.office_mats(2.75, env))
	for p in lamp_pos:
		_lights.append(Geo.lamp_light(self, p, bake, 1.8))
	tung = TungModel.build()
	Models.set_layers(tung, 1 | Geo.VIS_ACTOR)
	add_child(tung)
	tung.translation = Vector3(0.2, 0, -48)
	cam = Camera.new()
	cam.fov = 88.0 + float(Game.settings.fisheye) * 14.0
	add_child(cam)
	cam.translation = Vector3(0, 1.6, 4)
	cam.current = true
	var pl = CanvasLayer.new()
	pl.layer = 50
	owner.add_child(pl)
	var rect = ColorRect.new()
	UI.full_rect(rect)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://scripts/post.shader")
	post.set_shader_param("intensity", float(Game.settings.post))
	post.set_shader_param("brightness", float(Game.settings.brightness))
	post.set_shader_param("fisheye", float(Game.settings.fisheye))
	post.set_shader_param("samples", 1.0)
	rect.material = post
	pl.add_child(rect)
	_build_ui()
	# the menu theme, with the fluorescent hum of the hallway underneath
	Audio.ambient("amb_menu", -2.0, 0)
	Audio.ambient("amb_hall", -17.0, 1)
	Audio.set_madness(0.0)


func _build_ui() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 60
	owner.add_child(layer)
	var root = Control.new()
	UI.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var box = VBoxContainer.new()
	box.rect_position = Vector2(90, 80)
	box.add_constant_override("separation", 4)
	root.add_child(box)
	title = UI.label("sahur", 140, UI.WHITE, "thin")
	box.add_child(title)
	box.add_child(UI.label("tung tung tung sahur. answer him.  together.", 18, UI.SOFT))
	box.add_child(UI.label(" ", 18))
	# --- main
	menu = VBoxContainer.new()
	box.add_child(menu)
	menu.add_child(UI.button("host a game", self, "_show", ["host"]))
	menu.add_child(UI.button("join a game", self, "_show", ["join"]))
	menu.add_child(UI.button("settings", self, "_open_settings"))
	menu.add_child(UI.button("quit", self, "_quit"))
	# --- host
	host_box = VBoxContainer.new()
	host_box.add_constant_override("separation", 10)
	box.add_child(host_box)
	host_box.add_child(UI.label("your name", 14, UI.SOFT, "medium"))
	host_name = _field(Game.settings.get("name", ""), "operative")
	host_box.add_child(host_name)
	host_box.add_child(UI.button("open the lobby", self, "_do_host"))
	host_box.add_child(UI.label("you get a room code: give it to your friends.\nthey type it in \"join a game\", from anywhere, any network.\non the same wi-fi they also see your game in their list.", 13, UI.FAINT))
	host_box.add_child(UI.button("‹ back", self, "_show", ["main"], 18))
	# --- join
	join_box = VBoxContainer.new()
	join_box.add_constant_override("separation", 10)
	box.add_child(join_box)
	join_box.add_child(UI.label("your name", 14, UI.SOFT, "medium"))
	join_name = _field(Game.settings.get("name", ""), "operative")
	join_box.add_child(join_name)
	join_box.add_child(UI.label("room code", 14, UI.SOFT, "medium"))
	var jc = HBoxContainer.new()
	jc.add_constant_override("separation", 10)
	join_box.add_child(jc)
	join_code = _field("", "6 digits")
	join_code.rect_min_size = Vector2(260, 0)
	join_code.max_length = 7
	join_code.connect("text_entered", self, "_do_join_code")
	jc.add_child(join_code)
	jc.add_child(UI.button("join room", self, "_do_join_code", [""]))
	join_box.add_child(UI.label("on your network", 14, UI.SOFT, "medium"))
	lan_list = VBoxContainer.new()
	join_box.add_child(lan_list)
	join_box.add_child(UI.label("or type the host's ip", 14, UI.SOFT, "medium"))
	var jh = HBoxContainer.new()
	jh.add_constant_override("separation", 10)
	join_box.add_child(jh)
	join_ip = _field(Game.settings.get("last_ip", ""), "192.168.0.10")
	join_ip.rect_min_size = Vector2(260, 0)
	join_ip.connect("text_entered", self, "_do_join_text")
	jh.add_child(join_ip)
	jh.add_child(UI.button("join", self, "_do_join"))
	join_box.add_child(UI.button("‹ back", self, "_show", ["main"], 18))
	# --- lobby
	lobby_box = VBoxContainer.new()
	lobby_box.add_constant_override("separation", 10)
	box.add_child(lobby_box)
	lobby_title = UI.label("lobby", 30, UI.WHITE, "thin")
	lobby_box.add_child(lobby_title)
	code_label = UI.label("", 28, UI.AMBER, "light")
	lobby_box.add_child(code_label)
	lobby_info = UI.label("", 13, UI.SOFT)
	lobby_box.add_child(lobby_info)
	# one run, every sector in a row: each exit door opens into the next one
	var route = PoolStringArray()
	for l in Game.LEVELS:
		route.append(Game.INFO[l].name)
	sector_btn = UI.label("one run:  " + route.join("  →  ") + "  →  out", 15, UI.SOFT)
	sector_btn.autowrap = true
	lobby_box.add_child(sector_btn)
	var grp = UI.group_panel()
	grp.rect_min_size = Vector2(520, 0)
	lobby_box.add_child(grp)
	lobby_players = VBoxContainer.new()
	lobby_players.add_constant_override("separation", 6)
	grp.add_child(lobby_players)
	chat_label = UI.label("", 14, UI.SOFT)
	chat_label.autowrap = true
	chat_label.rect_min_size = Vector2(520, 62)
	chat_label.valign = Label.VALIGN_BOTTOM
	lobby_box.add_child(chat_label)
	chat_field = _field("", "say something…  (enter)")
	chat_field.rect_min_size = Vector2(520, 0)
	chat_field.connect("text_entered", self, "_on_chat")
	lobby_box.add_child(chat_field)
	var lb = HBoxContainer.new()
	lb.add_constant_override("separation", 8)
	lobby_box.add_child(lb)
	ready_btn = UI.button("i'm ready", self, "_toggle_ready")
	lb.add_child(ready_btn)
	start_btn = UI.button("start now", Net, "force_start")
	lb.add_child(start_btn)
	lb.add_child(UI.button("leave", self, "_do_leave"))
	# status line + countdown
	status = UI.label("", 15, UI.AMBER)
	status.autowrap = true
	status.rect_min_size = Vector2(560, 0)
	box.add_child(status)
	count_label = UI.label("", 200, UI.WHITE, "thin", Label.ALIGN_CENTER)
	count_label.anchor_left = 0.55
	count_label.anchor_right = 0.95
	count_label.anchor_top = 0.3
	count_label.anchor_bottom = 0.3
	root.add_child(count_label)
	settings = load("res://scripts/settings_panel.gd").new()
	settings.visible = false
	settings.rect_position = Vector2(80, 140)
	root.add_child(settings)
	settings.connect("closed", self, "_close_settings")
	var hint = UI.label("headphones recommended · he screams loud · don't play at 3 am · %s" % Net.VERSION, 13, UI.FAINT)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.margin_left = 90
	hint.margin_top = -30
	root.add_child(hint)
	Net.connect("players_changed", self, "_refresh_lobby")
	Net.connect("chat", self, "_on_net_chat")
	Net.connect("message", self, "_on_net_message")
	Net.connect("countdown", self, "_on_countdown")
	Net.connect("servers_changed", self, "_refresh_lan")
	Net.connect("failed", self, "_on_failed")
	if Net.state == Net.LOBBY:
		_show("lobby")
	else:
		_show("main")
		if Net.last_error != "":
			status.text = Net.last_error
			Net.last_error = ""


func _field(text: String, placeholder: String) -> LineEdit:
	var e = LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.rect_min_size = Vector2(340, 0)
	e.add_font_override("font", UI.font("light", 20))
	e.add_color_override("font_color", UI.WHITE)
	e.add_stylebox_override("normal", UI.box(Color(1, 1, 1, 0.07), 12))
	e.add_stylebox_override("focus", UI.box(Color(1, 1, 1, 0.13), 12))
	e.caret_blink = true
	return e


func _show(which: String) -> void:
	menu.visible = which == "main"
	host_box.visible = which == "host"
	join_box.visible = which == "join"
	lobby_box.visible = which == "lobby"
	settings.visible = false
	status.text = ""
	if which == "join":
		Net.start_discovery()
		_refresh_lan()
	else:
		Net.stop_discovery()
	if which == "lobby":
		_refresh_lobby()
		_on_net_chat("")


func _save_name(n: String) -> void:
	Game.set_setting("name", n.strip_edges().to_lower())


func _do_host() -> void:
	_save_name(host_name.text)
	if Net.host(host_name.text):
		_show("lobby")


func _do_join_text(_t: String) -> void:
	_do_join()


func _do_join_code(_t := "") -> void:
	_save_name(join_name.text)
	var c = join_code.text.strip_edges().replace(" ", "").replace("-", "")
	if c.length() != 6 or not c.is_valid_integer():
		status.text = "a room code has 6 digits"
		return
	Net.join_room(c, join_name.text)


func _do_join(ip := "") -> void:
	_save_name(join_name.text)
	if ip == "":
		ip = join_ip.text.strip_edges()
		Game.set_setting("last_ip", ip)
	if Net.join(ip, join_name.text):
		status.text = "connecting to %s…" % ip


func _do_leave() -> void:
	Net.leave(true)
	count_label.text = ""
	_show("main")


func _toggle_ready() -> void:
	var me = Net.players.get(Net.my_id())
	if me:
		Net.set_ready(not me.ready)


func _on_chat(t: String) -> void:
	Net.say(t)
	chat_field.text = ""


func _on_net_chat(_t: String) -> void:
	var n = Net.chat_log.size()
	chat_label.text = PoolStringArray(Net.chat_log.slice(max(0, n - 8), n - 1)).join("\n") if n > 0 else ""


func _on_net_message(t: String) -> void:
	if t != "":
		status.text = t


func _on_failed(reason: String) -> void:
	count_label.text = ""
	if lobby_box.visible:
		_show("main")
	status.text = reason


func _on_countdown(n: int) -> void:
	if n > 0:
		count_label.text = str(n)
		count_label.modulate.a = 1.0
		var tw = create_tween()
		tw.tween_property(count_label, "modulate:a", 0.35, 0.9)
	elif n == 0:
		count_label.text = "go"
	else:
		count_label.text = ""
		status.text = "countdown cancelled"


## The line under the code: who is here, and (joined) how good the connection is.
func _lobby_info() -> void:
	if Net.is_server():
		lobby_info.text = ("your ip: %s  ·  udp %d  ·  %d/%d operatives" % [", ".join(PoolStringArray(Net.local_ips())), Net.PORT, Net.players.size(), Net.MAX_PLAYERS]).to_lower()
	else:
		var conn = ""
		if Net.ping_ms >= 0:
			conn = "  ·  ping %d ms%s" % [Net.ping_ms, ("  ·  " + Net.room.path()) if Net.room.mode == "player" else ""]
		lobby_info.text = "%d/%d operatives · everyone ready starts the countdown%s" % [Net.players.size(), Net.MAX_PLAYERS, conn]


func _refresh_lobby() -> void:
	if Net.state == Net.LOBBY and not lobby_box.visible and (menu.visible or join_box.visible or host_box.visible):
		_show("lobby")
	if not lobby_box.visible:
		return
	lobby_title.text = "lobby · %s" % Net.server_name
	if Net.room_code != "":
		code_label.text = "room code  %s %s" % [Net.room_code.substr(0, 3), Net.room_code.substr(3, 3)]
	elif Net.is_server() and Net.room.mode == "host":
		code_label.text = "opening the online room…"
	else:
		code_label.text = ""
	_lobby_info()
	for c in lobby_players.get_children():
		c.queue_free()
	var ids = Net.players.keys()
	ids.sort()
	for pid in ids:
		var p = Net.players[pid]
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 12)
		var dot = UI.label("●", 18, p.color, "medium")
		h.add_child(dot)
		var n = UI.label(p.name + ("  (you)" if pid == Net.my_id() else "") + ("  · host" if pid == 1 else ""), 19, UI.WHITE)
		n.rect_min_size = Vector2(330, 0)
		h.add_child(n)
		var r = ("inside · sector %d" % int(p.get("sector", 0))) if p.in_game else ("ready" if p.ready else "—")
		h.add_child(UI.label(r, 15, UI.GREEN if p.ready else UI.SOFT, "medium"))
		lobby_players.add_child(h)
	var me = Net.players.get(Net.my_id())
	ready_btn.text = "not ready" if me and me.ready else "i'm ready"
	start_btn.visible = Net.is_server()


func _refresh_lan() -> void:
	if lan_list == null:
		return
	for c in lan_list.get_children():
		c.queue_free()
	if Net.found.empty():
		lan_list.add_child(UI.label("searching…", 15, UI.FAINT))
		return
	for ip in Net.found:
		var f = Net.found[ip]
		var t = "%s   ·   %d/%d%s   ·   %s" % [f.name, f.players, f.max, "  · in a round" if f.playing else "", ip]
		if not f.same:
			t += "   (other version)"
		lan_list.add_child(UI.button(t, self, "_do_join", [ip], 18))


func _open_settings() -> void:
	menu.visible = false
	status.text = ""
	settings.visible = true


func _close_settings() -> void:
	settings.visible = false
	menu.visible = true


func _quit() -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	if cam == null:
		return
	_t += delta
	cam.translation.z -= delta * 0.6
	if cam.translation.z < -20.0:
		cam.translation.z = 4.0
	cam.rotation.z = sin(_t * 0.4) * 0.01
	cam.rotation.y = sin(_t * 0.23) * 0.03
	title.modulate = Color(1, 1, 1, 0.55 + randf() * 0.45) if randf() < 0.08 else Color.white
	# Every so often the lights die and he gets closer.
	_jump -= delta
	if _jump <= 0.0:
		_jump = rand_range(5.0, 9.0)
		for l in _lights:
			Geo.lamp_set_on(l, false)
		Audio.play("tung", -12.0, 0.7)
		get_tree().create_timer(0.35).connect("timeout", self, "_lights_on")
	post.set_shader_param("danger", clamp(1.0 - (cam.translation.z - tung.translation.z) / 30.0, 0.0, 0.7))
	_info_t -= delta
	if _info_t <= 0.0:
		_info_t = 1.0
		if lobby_box.visible:
			_lobby_info()


func _lights_on() -> void:
	for l in _lights:
		Geo.lamp_set_on(l, true)
	tung.translation.z = cam.translation.z - rand_range(12.0, 44.0)
	tung.translation.x = rand_range(-0.5, 0.5)
