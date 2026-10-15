extends Node
## Autoload "Settings": player options (volume, mouse sensitivity, fullscreen, graphics quality,
## language, key bindings), saved to user://settings.cfg. Also sets up gamepad bindings.

signal graphics_changed

const PATH := "user://settings.cfg"

# Actions the player can rebind, with their display names and default keys.
const BINDABLE: Array[Dictionary] = [
	{"action": "accelerate", "name": "Accelerate", "key": KEY_W},
	{"action": "brake", "name": "Brake / Reverse", "key": KEY_S},
	{"action": "steer_left", "name": "Steer left", "key": KEY_A},
	{"action": "steer_right", "name": "Steer right", "key": KEY_D},
	{"action": "open_shop", "name": "Open shop", "key": KEY_B},
	{"action": "refuel", "name": "Refuel (at a gas station)", "key": KEY_F},
	{"action": "order_1", "name": "Take order 1", "key": KEY_1},
	{"action": "order_2", "name": "Take order 2", "key": KEY_2},
	{"action": "order_3", "name": "Take order 3", "key": KEY_3},
	{"action": "cancel_order", "name": "Cancel order", "key": KEY_X},
	{"action": "engine", "name": "Engine start / stop", "key": KEY_E},
	{"action": "horn", "name": "Horn", "key": KEY_H},
	{"action": "wheelie", "name": "Wheelie (hold)", "key": KEY_T},
	{"action": "mouse_lock", "name": "Mouse Lock (toggle)", "key": KEY_SHIFT},
	{"action": "camera_view", "name": "Camera view (TPP / FPP)", "key": KEY_V},
	{"action": "pause", "name": "Pause / Back", "key": KEY_ESCAPE},
]
const GAMEPAD_DEADZONE := 0.2

var master_volume := 0.8        # 0..1
var music_volume := 0.7         # 0..1 (Music bus)
var sfx_volume := 0.9           # 0..1 (SFX bus: effects and the engine)
var mouse_sensitivity := 1.0    # multiplier for the camera
var fullscreen := false
var bindings := {}              # action -> physical keycode
var graphics := 1               # 0 = low, 1 = medium, 2 = high
var language := "en"            # "en" or "th"
var hud_collapsed := {}         # HUD panel id -> true when the player collapsed it

const GRAPHICS_NAMES := ["LOW", "MEDIUM", "HIGH"]

func _ready() -> void:
	for b in BINDABLE:
		bindings[b["action"]] = b["key"]
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		master_volume = float(cfg.get_value("options", "master_volume", master_volume))
		music_volume = float(cfg.get_value("options", "music_volume", music_volume))
		sfx_volume = float(cfg.get_value("options", "sfx_volume", sfx_volume))
		mouse_sensitivity = float(cfg.get_value("options", "mouse_sensitivity", mouse_sensitivity))
		fullscreen = bool(cfg.get_value("options", "fullscreen", fullscreen))
		graphics = clampi(int(cfg.get_value("options", "graphics", graphics)), 0, 2)
		language = str(cfg.get_value("options", "language", language))
		var hc = cfg.get_value("hud", "collapsed", {})
		if hc is Dictionary:
			hud_collapsed = hc
		for action in bindings:
			bindings[action] = int(cfg.get_value("controls", action, bindings[action]))
	else:
		# First run: follow the browser / system language (Thai players start in Thai).
		language = "th" if OS.get_locale_language() == "th" else "en"
		if OS.has_feature("web"):
			graphics = 0   # first run in a browser: start on LOW, the player can raise it in Options
	_setup_actions()
	apply()

## How many cars / pedestrians to run, relative to the full amount.
func crowd_scale() -> float:
	# Browsers run game code single-threaded in WebAssembly, so keep crowds smaller there.
	if OS.has_feature("web"):
		return [0.35, 0.55, 0.75][graphics]
	return [0.5, 0.8, 1.0][graphics]

func set_graphics(level: int) -> void:
	graphics = clampi(level, 0, 2)
	apply()
	graphics_changed.emit()

func set_language(lang: String) -> void:
	language = lang
	TranslationServer.set_locale(lang)

func apply() -> void:
	TranslationServer.set_locale(language)
	var vp := get_tree().root
	vp.msaa_3d = Viewport.MSAA_2X if graphics == 2 else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0   # render scaling adds an extra pass in the Compatibility renderer (slower on web)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.apply_volumes()
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("options", "master_volume", master_volume)
	cfg.set_value("options", "music_volume", music_volume)
	cfg.set_value("options", "sfx_volume", sfx_volume)
	cfg.set_value("options", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("options", "fullscreen", fullscreen)
	cfg.set_value("options", "graphics", graphics)
	cfg.set_value("options", "language", language)
	cfg.set_value("hud", "collapsed", hud_collapsed)
	for action in bindings:
		cfg.set_value("controls", action, bindings[action])
	cfg.save(PATH)

# ------------------------------------------------------------------ input

func key_name(action: String) -> String:
	return OS.get_keycode_string(bindings.get(action, KEY_NONE))

func rebind(action: String, physical_keycode: int) -> void:
	bindings[action] = physical_keycode
	_set_key(action, physical_keycode)
	save()

func reset_bindings() -> void:
	for b in BINDABLE:
		rebind(b["action"], b["key"])

func _set_key(action: String, physical_keycode: int) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, ev)

func _add_joy_button(action: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _add_joy_axis(action: String, axis: JoyAxis, direction: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)

## Make sure every action exists, apply the saved keys and add gamepad controls:
## RT/A accelerate, LT/B brake, left stick steer, Y shop, Start pause (right stick = camera).
func _setup_actions() -> void:
	for b in BINDABLE:
		var action: String = b["action"]
		if not InputMap.has_action(action):
			InputMap.add_action(action, GAMEPAD_DEADZONE)
		InputMap.action_set_deadzone(action, GAMEPAD_DEADZONE)
		_set_key(action, bindings[action])
	_add_joy_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_button("accelerate", JOY_BUTTON_A)
	_add_joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_button("brake", JOY_BUTTON_B)
	_add_joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_button("open_shop", JOY_BUTTON_Y)
	_add_joy_button("refuel", JOY_BUTTON_X)
	_add_joy_button("engine", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("wheelie", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("camera_view", JOY_BUTTON_RIGHT_STICK)
	_add_joy_button("pause", JOY_BUTTON_START)
	_add_joy_button("order_1", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("order_2", JOY_BUTTON_DPAD_UP)
	_add_joy_button("order_3", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("cancel_order", JOY_BUTTON_BACK)
