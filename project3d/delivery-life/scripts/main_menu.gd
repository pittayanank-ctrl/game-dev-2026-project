extends Node3D
## Main menu: a slowly turning bike on a platform, with Continue / New Game / Quit.

const GAME_SCENE := "res://scenes/main.tscn"
const OptionsPanel := preload("res://scripts/options_panel.gd")
const CreditsPanel := preload("res://scripts/credits_panel.gd")
const BIKE_SCENE := preload("res://scenes/motorcycle.tscn")

var _turntable: Node3D
var _confirm: ConfirmationDialog
var _options: PanelContainer
var _options_layer: Control
var _credits_layer: Control
var _ui_layer: CanvasLayer
var _built_locale := ""            # language the menu texts were built in

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Audio.play_music("menu")
	_build_world()
	_build_ui()
	# Launch option for testing exported builds: `DeliveryLife.exe -- --start` or `?start` in the
	# web page URL skips the menu.
	if PerfProbe.has_flag("start"):
		_start_game.call_deferred()

func _process(delta: float) -> void:
	_turntable.rotate_y(0.6 * delta)

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 1.0)
	env.ambient_light_energy = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_color = Color(1.0, 0.8, 0.4)
	rim.light_energy = 0.8
	add_child(rim)

	# The bike sits to the right so the menu fits on the left.
	_turntable = Node3D.new()
	_turntable.position = Vector3(1.9, 0, 0)
	add_child(_turntable)
	var platform := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.7
	disc.bottom_radius = 1.7
	disc.height = 0.1
	platform.mesh = disc
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.75, 0.1)
	platform.material_override = pmat
	platform.position.y = -0.05
	_turntable.add_child(platform)
	var bike := BIKE_SCENE.instantiate()
	_turntable.add_child(bike)
	bike.set_physics_process(false)   # no gravity/input here, it's just a display model

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 4.3)
	add_child(cam)
	cam.look_at(Vector3(0, 0.8, 0))   # bike is off to the right of the view centre
	cam.current = true

func _label(text: String, size: int, color := UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # we translate ourselves (leading spaces)
	b.text = "   " + tr(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(handler)
	return b

func _chip(text: String, bg: Color, fg: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := UITheme.box(bg, 7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(_label(text, 15, fg))
	return chip

## A small "key + what it does" pair for the controls strip.
func _keycap(key: String, what: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_chip(key, UITheme.SURFACE_HOVER, UITheme.TEXT))
	row.add_child(_label(what, 15, UITheme.TEXT_DIM))
	return row

func _build_ui() -> void:
	_built_locale = TranslationServer.get_locale()
	var layer := CanvasLayer.new()
	_ui_layer = layer
	add_child(layer)

	# Dark gradient behind the menu column so the text reads well over the 3D scene.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.05, 0.06, 0.09, 0.96))
	grad.set_color(1, Color(0.05, 0.06, 0.09, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.45, 0)
	tex.fill_to = Vector2(1, 0)
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 620
	layer.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 70)
	layer.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 14)
	title.add_child(_label("DELIVERY", 66, UITheme.ACCENT))
	title.add_child(_label("LIFE", 66))
	box.add_child(title)
	var bar := ColorRect.new()
	bar.color = UITheme.ACCENT
	bar.custom_minimum_size = Vector2(90, 5)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(bar)
	box.add_child(_label("Ride. Deliver. Upgrade.", 22, UITheme.TEXT_DIM))

	if GameState.has_save():
		var info := HBoxContainer.new()
		info.add_theme_constant_override("separation", 8)
		var chapter := tr("FREE RIDE") if GameState.chapter > 5 else tr("CHAPTER %d") % GameState.chapter
		info.add_child(_chip(chapter, UITheme.INFO, Color(0.05, 0.08, 0.12)))
		info.add_child(_chip(tr("DAY %d") % GameState.day, UITheme.SURFACE, UITheme.TEXT))
		info.add_child(_chip("%d THB" % GameState.money, UITheme.ACCENT, Color(0.08, 0.07, 0.02)))
		info.add_child(_chip(tr(GameState.current_bike()["name"]), UITheme.SURFACE, UITheme.TEXT))
		box.add_child(info)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	box.add_child(gap)

	if GameState.has_save():
		var first := _button("CONTINUE", _start_game)
		box.add_child(first)
		first.call_deferred("grab_focus")   # lets a gamepad / keyboard navigate the menu
		box.add_child(_button("NEW GAME", _on_new_game))
	else:
		var first := _button("START GAME", _start_game)
		box.add_child(first)
		first.call_deferred("grab_focus")
	box.add_child(_button("OPTIONS", func(): _options_layer.visible = true))
	box.add_child(_button("CREDITS", func(): _credits_layer.visible = true))
	box.add_child(_button("QUIT", func(): get_tree().quit()))

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 18)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 64
	controls.offset_top = -48
	for pair in [["W / S", "throttle / brake"], ["A / D", "steer"], ["RMB / Shift", "camera"], ["Wheel", "zoom"], ["B", "shop"], ["Esc", "menu"]]:
		controls.add_child(_keycap(pair[0], pair[1]))
	layer.add_child(controls)

	# Options open over a dimmed backdrop.
	_options_layer = Control.new()
	_options_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_layer.visible = false
	layer.add_child(_options_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_layer.add_child(dim)
	_options = OptionsPanel.new()
	_options.back.connect(func():
		_options_layer.visible = false
		# The language may have changed in Options: rebuild the menu so every text follows it.
		if TranslationServer.get_locale() != _built_locale:
			_rebuild_ui.call_deferred())
	_options_layer.add_child(_options)

	# Credits, same dimmed overlay.
	_credits_layer = Control.new()
	_credits_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits_layer.visible = false
	layer.add_child(_credits_layer)
	var dim2 := ColorRect.new()
	dim2.color = Color(0.02, 0.03, 0.05, 0.8)
	dim2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits_layer.add_child(dim2)
	var credits := CreditsPanel.new()
	credits.back.connect(func(): _credits_layer.visible = false)
	_credits_layer.add_child(credits)

	_confirm = ConfirmationDialog.new()
	_confirm.theme = UITheme.theme
	_confirm.title = tr("New Game")
	_confirm.dialog_text = tr("This erases your saved money, bikes and colors.\nStart a new game?")
	_confirm.ok_button_text = tr("Start new game")
	_confirm.cancel_button_text = tr("Cancel")
	_confirm.confirmed.connect(func():
		GameState.reset_game()
		_start_game())
	add_child(_confirm)

func _rebuild_ui() -> void:
	_ui_layer.queue_free()
	_confirm.queue_free()
	_build_ui()

func _on_new_game() -> void:
	_confirm.popup_centered()

func _start_game() -> void:
	Loader.change_scene(GAME_SCENE)
