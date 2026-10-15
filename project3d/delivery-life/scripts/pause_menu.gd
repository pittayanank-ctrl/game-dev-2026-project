extends CanvasLayer
## Pause menu (Esc): Resume, Options, Main Menu, Quit. Ignores Esc while the shop is open.

const OptionsPanel := preload("res://scripts/options_panel.gd")
const MENU_SCENE := "res://scenes/main_menu.tscn"

var _root: Control
var _buttons: VBoxContainer
var _card: PanelContainer
var _options: PanelContainer

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# Title and buttons sit on a card in the middle of the screen.
	_card = PanelContainer.new()
	var sb := UITheme.box(UITheme.BG_SOLID, 16, UITheme.ACCENT, 2, 26.0)
	_card.add_theme_stylebox_override("panel", sb)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_card)
	_buttons = VBoxContainer.new()
	_buttons.custom_minimum_size = Vector2(320, 0)
	_buttons.add_theme_constant_override("separation", 12)
	_card.add_child(_buttons)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.add_child(title)
	_add_button("RESUME", _close)
	_add_button("OPTIONS", func():
		_card.visible = false
		_options.visible = true)
	_add_button("MAIN MENU", _to_menu)
	_add_button("QUIT GAME", func(): get_tree().quit())

	_options = OptionsPanel.new()
	_options.visible = false
	_options.back.connect(func():
		_options.visible = false
		_card.visible = true)
	_root.add_child(_options)

func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(handler)
	_buttons.add_child(b)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _root.visible:
		if _options.visible:
			Settings.save()
			_options.visible = false
			_card.visible = true
		else:
			_close()
	elif not get_tree().paused:
		_open()
	else:
		return   # paused by something else (the shop): leave Esc to it
	get_viewport().set_input_as_handled()

func _open() -> void:
	Audio.play("open", -6.0)
	_root.visible = true
	_card.visible = true
	_options.visible = false
	get_tree().paused = true
	_buttons.get_child(1).grab_focus()   # first button, for gamepad navigation

func _close() -> void:
	Audio.play("close", -6.0)
	_root.visible = false
	get_tree().paused = false

func _to_menu() -> void:
	GameState.save_game()
	get_tree().paused = false
	Loader.change_scene(MENU_SCENE)
