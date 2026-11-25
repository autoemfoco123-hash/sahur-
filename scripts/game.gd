extends Node
## Global game state: settings, save data, level flow, input map.

const LEVELS := ["0"]
const SECRET := "0.5"

const INFO := {
	"0": {"title": "sector 0", "name": "the sahur hallways", "goal": "find the way out.  when he calls, answer (q)."},
}

var settings := {
	"sensitivity": 0.25,
	"volume": 0.8,
	"post": 1.0,
	"fisheye": 1.0,
	"motion_blur": 1.2,
	"brightness": 1.0,
	"fullscreen": false,
	"quality": 1,
}

var current_level := "0"
var brain_cells := 100.0
var level_start_cells := 100.0
var furthest := 0
var secret_found := false
var secret_return := "1"
var flashlight_battery := 100.0
var level_start_battery := 100.0
var forced_seed := -1
var force_touch := false

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"

signal settings_changed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	if OS.has_feature("mobile"):
		settings.quality = 0
		settings.motion_blur = 0.8
	load_settings()
	load_save()
	apply_settings()


func _setup_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP, KEY_Z],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"crouch": [KEY_CTRL, KEY_C],
		"interact": [KEY_E],
		"flashlight": [KEY_F],
		"shout": [KEY_Q],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("flashlight", click)
	var lclick := InputEventMouseButton.new()
	lclick.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("interact", lclick)


# ---------------------------------------------------------------- settings
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings.keys():
			settings[k] = cf.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(max(0.0001, float(settings.volume))))
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	settings_changed.emit()


func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	save_settings()


# ---------------------------------------------------------------- save
func load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		furthest = cf.get_value("save", "furthest", 0)
		secret_found = cf.get_value("save", "secret_found", false)
		brain_cells = cf.get_value("save", "brain_cells", 100.0)
		flashlight_battery = cf.get_value("save", "battery", 100.0)


func write_save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "furthest", furthest)
	cf.set_value("save", "secret_found", secret_found)
	cf.set_value("save", "brain_cells", level_start_cells)
	cf.set_value("save", "battery", level_start_battery)
	cf.save(SAVE_PATH)


func has_save() -> bool:
	return furthest > 0


# ---------------------------------------------------------------- flow
func new_game() -> void:
	furthest = 0
	brain_cells = 100.0
	flashlight_battery = 100.0
	goto_level("0")


func continue_game() -> void:
	goto_level(LEVELS[clampi(furthest, 0, LEVELS.size() - 1)])


func goto_level(id: String) -> void:
	current_level = id
	level_start_cells = max(brain_cells, 50.0)
	brain_cells = level_start_cells
	level_start_battery = max(flashlight_battery, 40.0)
	flashlight_battery = level_start_battery
	var idx := LEVELS.find(id)
	if idx > furthest:
		furthest = idx
	write_save()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func restart_level() -> void:
	brain_cells = level_start_cells
	flashlight_battery = level_start_battery
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func next_level() -> void:
	if current_level == SECRET:
		goto_level(secret_return)
		return
	var idx := LEVELS.find(current_level)
	if idx < 0 or idx + 1 >= LEVELS.size():
		main_menu()
		return
	goto_level(LEVELS[idx + 1])


func enter_secret() -> void:
	secret_return = "1"
	goto_level(SECRET)


func finish_game() -> void:
	furthest = 0
	brain_cells = 100.0
	flashlight_battery = 100.0
	write_save()


func main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
