extends PanelContainer
## Reusable options panel (volume, mouse sensitivity, fullscreen, key bindings). Emits `back` when closed.

signal back

var _listening := ""             # action waiting for a new key ("" = not listening)
var _key_buttons := {}           # action -> Button
var _slider_labels: Array[Callable] = []   # re-run on language change

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_SOLID, 16, UITheme.ACCENT, 2))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(500, 540)
	offset_left = -250
	offset_top = -270
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)

	_add_slider(box, "Master volume", 0.0, 1.0, Settings.master_volume, func(v):
		Settings.master_volume = v
		Settings.apply())
	_add_slider(box, "Music volume", 0.0, 1.0, Settings.music_volume, func(v):
		Settings.music_volume = v
		Audio.apply_volumes())
	_add_slider(box, "Effects volume", 0.0, 1.0, Settings.sfx_volume, func(v):
		Settings.sfx_volume = v
		Audio.apply_volumes())
	_add_slider(box, "Mouse sensitivity", 0.2, 2.5, Settings.mouse_sensitivity, func(v):
		Settings.mouse_sensitivity = v)

	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.add_theme_font_size_override("font_size", 20)
	fs.toggled.connect(func(on):
		Settings.fullscreen = on
		Settings.apply())
	box.add_child(fs)

	box.add_child(_choice_row(tr("Graphics"), ["LOW", "MEDIUM", "HIGH"], Settings.graphics, func(i: int): Settings.set_graphics(i)))
	box.add_child(_choice_row(tr("Language"), ["English", "ไทย"], 1 if Settings.language == "th" else 0, func(i: int): Settings.set_language(["en", "th"][i])))

	var controls := Label.new()
	controls.text = "CONTROLS  (click, then press a key)"
	controls.add_theme_font_size_override("font_size", 20)
	controls.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	box.add_child(controls)
	for b in Settings.BINDABLE:
		var action: String = b["action"]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = b["name"]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 18)
		row.add_child(l)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.pressed.connect(func(): _listen(action))
		row.add_child(btn)
		_key_buttons[action] = btn
		box.add_child(row)
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(func():
		Settings.reset_bindings()
		_refresh_keys())
	box.add_child(reset)
	var pad := Label.new()
	pad.text = "Gamepad: RT/A accelerate, LT/B brake, left stick steer,\nright stick camera, Y shop, Start pause"
	pad.add_theme_font_size_override("font_size", 14)
	pad.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	box.add_child(pad)
	_refresh_keys()

	var done := Button.new()
	done.text = "BACK"
	done.custom_minimum_size = Vector2(0, 46)
	done.add_theme_font_size_override("font_size", 22)
	done.pressed.connect(func():
		Settings.save()
		back.emit())
	outer.add_child(done)

## A label with a row of toggle buttons; exactly one is selected.
func _choice_row(title: String, options: Array, selected: int, on_pick: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 20)
	col.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		var on := UITheme.box(UITheme.ACCENT, 9)
		on.set_content_margin_all(8)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_hover_pressed_color", Color(0.1, 0.08, 0.02))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(func(): on_pick.call(i))
		row.add_child(b)
	return col

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for f in _slider_labels:
			f.call()
		_refresh_keys()

func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = tr("Press a key...") if action == _listening else Settings.key_name(action)

func _listen(action: String) -> void:
	_listening = action
	_refresh_keys()

func _input(event: InputEvent) -> void:
	if _listening == "" or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Escape cancels, unless we are binding the pause key itself.
		if event.physical_keycode != KEY_ESCAPE or _listening == "pause":
			Settings.rebind(_listening, event.physical_keycode)
		_listening = ""
		_refresh_keys()
		get_viewport().set_input_as_handled()

func _add_slider(parent: Control, label_text: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 20)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(0, 24)
	s.add_theme_stylebox_override("slider", UITheme.box(UITheme.SURFACE, 4, Color(0, 0, 0, 0), 0, 3.0))
	s.add_theme_stylebox_override("grabber_area", UITheme.box(UITheme.ACCENT, 4, Color(0, 0, 0, 0), 0, 3.0))
	s.add_theme_stylebox_override("grabber_area_highlight", UITheme.box(UITheme.ACCENT, 4, Color(0, 0, 0, 0), 0, 3.0))
	var update := func(v: float):
		l.text = "%s: %d%%" % [tr(label_text), int(round(v * 100.0))]
	update.call(value)
	_slider_labels.append(func(): update.call(s.value))
	s.value_changed.connect(func(v):
		update.call(v)
		on_change.call(v))
	row.add_child(l)
	row.add_child(s)
	parent.add_child(row)
