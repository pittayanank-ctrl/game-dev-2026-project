extends CanvasLayer
## End-of-day screen (shown at midnight): today's deliveries, earnings and losses, career totals and
## the next goal. "Start next day" saves and resets the clock to 06:00.

const ACCENT := Color(0.98, 0.8, 0.15)

var _root: Control
var _body: VBoxContainer
var _title: Label
var _next_button: Button
var _clock: Node

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clock = get_node_or_null("../WorldClock")
	if _clock:
		_clock.day_ended.connect(_show)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_SOLID, 16, UITheme.ACCENT, 2))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.offset_left = -280
	panel.offset_top = -260
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", ACCENT)
	box.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	box.add_child(_body)
	_next_button = Button.new()
	_next_button.custom_minimum_size = Vector2(0, 52)
	_next_button.add_theme_font_size_override("font_size", 24)
	_next_button.pressed.connect(_next_day)
	box.add_child(_next_button)

func _row(left: String, right: String, color := Color(0.88, 0.9, 0.96)) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = left
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	row.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_font_size_override("font_size", 20)
	r.add_theme_color_override("font_color", color)
	row.add_child(r)
	_body.add_child(row)

func _show() -> void:
	for c in _body.get_children():
		c.queue_free()
	var t := GameState.today
	_title.text = tr("DAY %d COMPLETE") % GameState.day
	_row("Deliveries completed", str(t["deliveries"]))
	_row("Deliveries failed", str(t["failed"]), Color(1, 0.55, 0.5) if t["failed"] > 0 else Color(0.88, 0.9, 0.96))
	_row("Earned today", "%d THB" % t["earned"], ACCENT)
	_row("Lost to package damage", "%d THB" % t["damage_lost"], Color(1, 0.55, 0.5) if t["damage_lost"] > 0 else Color(0.88, 0.9, 0.96))
	_row(tr("Spent on fuel"), "%d THB" % t["fuel_spent"])
	_row(tr("Traffic fines"), "%d THB" % t["fines"], Color(1, 0.55, 0.5) if t["fines"] > 0 else Color(0.88, 0.9, 0.96))
	var avg := "-" if t["rated"] == 0 else "%.1f ★" % (float(t["stars"]) / t["rated"])
	_row(tr("Average rating today"), avg, UITheme.ACCENT)
	_row("Crashes", str(t["crashes"]))
	_row("Distance ridden", "%.1f km" % (t["distance"] / 1000.0))
	_body.add_child(HSeparator.new())
	_row("Money", "%d THB" % GameState.money, ACCENT)
	_row("Career deliveries", str(GameState.stats["deliveries"]))
	var g := GameState.next_goal()
	var goal_text := tr("All goals complete!") if g.is_empty() else "%s (%d/%d)" % [tr(g["text"]), mini(GameState.goal_progress(g), g["target"]), g["target"]]
	var goal := Label.new()
	goal.text = tr("Next goal: ") + goal_text
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.add_theme_font_size_override("font_size", 18)
	goal.add_theme_color_override("font_color", Color(0.98, 0.85, 0.4))
	_body.add_child(goal)
	_next_button.text = tr("START DAY %d") % (GameState.day + 1)
	_root.visible = true
	get_tree().paused = true
	_next_button.grab_focus()

func _next_day() -> void:
	GameState.finish_day()
	if _clock:
		_clock.start_new_day()
	_root.visible = false
	get_tree().paused = false

func is_open() -> bool:
	return _root.visible
