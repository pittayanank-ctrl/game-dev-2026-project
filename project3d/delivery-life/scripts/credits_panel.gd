extends PanelContainer
## Credits screen (opened from the main menu). The text lives in CREDITS below: edit it there.
## The list scrolls slowly by itself; the mouse wheel or a drag takes over. Emits `back` when closed.

signal back

# Put your name (or team name) here.
const DEVELOPER := "นายธนพล สุขเสริม 673380319-1
นางสาวพิชชาอร ณ นครพนม 673380331-1
นายพิทยนันท์ กัญญะลา 673380525-8"

# Sections: [title, [[left, right], ...]]. Left = what, right = who / license.
const CREDITS := [
	["GAME", [
		["A game by", DEVELOPER],
		["Engine", "Godot Engine 4.7 (MIT)"],
	]],

]

const SCROLL_SPEED := 28.0           # pixels per second while auto-scrolling

var _scroll: ScrollContainer
var _auto := true
var _pos := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_SOLID, 16, UITheme.ACCENT, 2))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(620, 560)
	offset_left = -310
	offset_top = -280
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var title := _label("CREDITS", 32, UITheme.ACCENT)
	outer.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton or e is InputEventScreenDrag or e is InputEventMouseMotion and e.button_mask != 0:
			_auto = false)
	outer.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	_scroll.add_child(list)

	var logo := HBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", 10)
	logo.add_child(_label("DELIVERY", 40, UITheme.ACCENT))
	logo.add_child(_label("LIFE", 40, UITheme.TEXT))
	list.add_child(logo)
	list.add_child(_gap(10))

	for section in CREDITS:
		var head := _label(section[0], 20, UITheme.ACCENT)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(head)
		for row in section[1]:
			var what := _label(row[0], 15, UITheme.TEXT_DIM)
			what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(what)
			var who := _label(row[1], 18, UITheme.TEXT)
			who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(who)
			list.add_child(_gap(4))
		list.add_child(_gap(16))
	var thanks := _label("Thanks for playing!", 24, UITheme.ACCENT)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(thanks)
	list.add_child(_gap(40))

	var close := Button.new()
	close.text = "BACK"
	close.custom_minimum_size = Vector2(0, 46)
	close.pressed.connect(func(): back.emit())
	outer.add_child(close)
	visibility_changed.connect(func():
		if visible:
			_auto = true
			_pos = 0.0
			_scroll.scroll_vertical = 0
			close.call_deferred("grab_focus"))

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not _auto:
		return
	_pos += SCROLL_SPEED * delta
	_scroll.scroll_vertical = int(_pos)

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		back.emit()
		get_viewport().set_input_as_handled()
