extends Node
## Global game state: settings, save data, level flow, input map. (Godot 3.6 / GLES2)

const LEVELS := ["0", "1"]
const INFO := {
	"0": {"title": "sector 0", "name": "the sahur hallways", "goal": "photograph him (f).  answer when he calls (q).  find the way out."},
	"1": {"title": "sector 1", "name": "the key rooms", "goal": "photograph them (f).  take the master key.  they only move when nobody is looking."},
}

var settings = {
	"sensitivity": 0.25,
	"volume": 0.8,
	"post": 1.0,
	"fisheye": 1.0,
	"motion_blur": 1.2,
	"brightness": 1.0,
	"fullscreen": false,
	"gfx": 1,  # 0 potato · 1 low · 2 high
	"name": "",
	"last_ip": "",
}

var current_level = "0"
var brain_cells = 100.0
var level_start_cells = 100.0
var furthest = 0
var forced_seed = -1
var cache = {}   # shared resource cache for the static helper classes

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"

signal settings_changed

var _saved_keys = {}
var _mouse = Vector2.ZERO
var force_touch = false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_setup_inputs()
	load_settings()
	if not _saved_keys.has("gfx"):
		settings.gfx = _guess_gfx()
	var args = []
	for a in OS.get_cmdline_args():
		args.append(a.trim_prefix("--"))
	if "potato" in args:
		settings.gfx = 0
	elif "low" in args:
		settings.gfx = 1
	elif "high" in args:
		settings.gfx = 2
	force_touch = "touch" in args
	if "server" in args:
		call_deferred("_boot_server", args)
	print("sahur: gpu '%s' · graphics %s" % [VisualServer.get_video_adapter_name(), ["potato", "low", "high"][int(settings.gfx)]])
	load_save()
	apply_settings()


## Mouse motion in real window pixels. The root viewport reports it in ui units
## (scaled by the 2d stretch), so undo that scale here.
func _input(event: InputEvent) -> void:
	# On phones the touchscreen also fakes mouse motion: the touch controls own the camera there.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not _touch():
		var r = get_tree().root
		var k = float(r.size.x) / max(1.0, r.get_visible_rect().size.x)
		_mouse += event.relative * k


func _touch() -> bool:
	return force_touch or OS.has_feature("mobile")


func take_mouse() -> Vector2:
	var m = _mouse
	_mouse = Vector2.ZERO
	return m


## Headless dedicated server: ./sahur-server --main-pack Sahur.pck --server [--name=my-server]
func _boot_server(args: Array) -> void:
	var n = "sahur server"
	for a in args:
		if a.begins_with("name="):
			n = a.substr(5)
		elif a.begins_with("level=") and INFO.has(a.substr(6)):
			Net.level_id = a.substr(6)
	if Net.host(n, true):
		get_tree().change_scene("res://scenes/server.tscn")
	else:
		print("[sahur-net] ", Net.last_error)
		get_tree().quit(1)


func _setup_inputs() -> void:
	var keys = {
		"move_forward": [KEY_W, KEY_UP, KEY_Z],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"crouch": [KEY_CONTROL, KEY_C],
		"interact": [KEY_E],
		"shout": [KEY_Q],
		"pause": [KEY_ESCAPE, KEY_P],
		"photo": [KEY_F],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev = InputEventKey.new()
			ev.physical_scancode = k
			InputMap.action_add_event(action, ev)
	var lclick = InputEventMouseButton.new()
	lclick.button_index = BUTTON_LEFT
	InputMap.action_add_event("interact", lclick)
	var rclick = InputEventMouseButton.new()
	rclick.button_index = BUTTON_RIGHT
	InputMap.action_add_event("photo", rclick)


# ------------------------------------------------------------------ settings
func load_settings() -> void:
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings.keys():
			if cf.has_section_key("settings", k):
				_saved_keys[k] = true
				settings[k] = cf.get_value("settings", k, settings[k])


## First launch: software GL and old integrated GPUs start on potato.
func _guess_gfx() -> int:
	var gpu = (VisualServer.get_video_adapter_name() + " " + VisualServer.get_video_adapter_vendor()).to_lower()
	for weak in ["llvmpipe", "softpipe", "swrast", "software", "gma", "gdi generic", "mobile intel", "intel(r) g", "sandybridge", "ironlake", "pineview", "i915", "radeon xpress", "geforce 6", "geforce 7", "mali-4", "videocore"]:
		if weak in gpu:
			return 0
	if OS.get_processor_count() <= 2:
		return 0
	return 1


func save_settings() -> void:
	var cf = ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func apply_settings() -> void:
	var bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear2db(max(0.0001, float(settings.volume))))
	OS.window_fullscreen = bool(settings.fullscreen)
	emit_signal("settings_changed")


func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	save_settings()


# ------------------------------------------------------------------ save
func load_save() -> void:
	var cf = ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		furthest = cf.get_value("save", "furthest", 0)
		brain_cells = cf.get_value("save", "brain_cells", 100.0)


func write_save() -> void:
	var cf = ConfigFile.new()
	cf.set_value("save", "furthest", furthest)
	cf.set_value("save", "brain_cells", level_start_cells)
	cf.save(SAVE_PATH)


func has_save() -> bool:
	return furthest > 0


# ------------------------------------------------------------------ flow
func new_game() -> void:
	furthest = 0
	brain_cells = 100.0
	goto_level("0")


func continue_game() -> void:
	goto_level(LEVELS[int(clamp(furthest, 0, LEVELS.size() - 1))])


func goto_level(id: String) -> void:
	current_level = id
	level_start_cells = max(brain_cells, 50.0)
	brain_cells = level_start_cells
	var idx = LEVELS.find(id)
	if idx > furthest:
		furthest = idx
	write_save()
	get_tree().paused = false
	get_tree().change_scene("res://scenes/world.tscn")


func restart_level() -> void:
	brain_cells = level_start_cells
	get_tree().paused = false
	get_tree().change_scene("res://scenes/world.tscn")


func next_level() -> void:
	var idx = LEVELS.find(current_level)
	if idx < 0 or idx + 1 >= LEVELS.size():
		main_menu()
		return
	goto_level(LEVELS[idx + 1])


func finish_game() -> void:
	furthest = 0
	brain_cells = 100.0
	write_save()


func main_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene("res://scenes/menu.tscn")
