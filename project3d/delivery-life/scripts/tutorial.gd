extends CanvasLayer
## First-time tutorial: a short list of steps shown in a box at the bottom left. Each step finishes
## when the player does the thing (or after a timeout for the informational ones). Enter skips it.

var _steps: Array[Dictionary] = []
var _index := 0
var _timer := 0.0
var _driven := 0.0
var _looked := 0.0
var _panel: PanelContainer
var _text: Label
var _counter: Label
var _player: Node3D
var _delivery: Node3D

func _ready() -> void:
	if GameState.tutorial_done:
		set_process(false)
		set_process_input(false)
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node("../Motorcycle")
	var delivery := get_node("../DeliveryManager")
	_delivery = delivery
	delivery.order_accepted.connect(func(): _complete_step("choose"))
	delivery.picked_up.connect(func(): _complete_step("pickup"))
	delivery.delivered.connect(func(_pay): _complete_step("deliver"))
	_steps = [
		{"id": "engine", "text": tr("Press %s to start the engine.") % Settings.key_name("engine")},
		{"id": "drive", "text": tr("Hold %s to accelerate and %s to brake / reverse. Steer with %s and %s.") % [
			Settings.key_name("accelerate"), Settings.key_name("brake"), Settings.key_name("steer_left"), Settings.key_name("steer_right")]},
		{"id": "look", "text": tr("Hold the right mouse button and drag to look around, or press %s for Mouse Lock. Scroll to zoom.") % Settings.key_name("mouse_lock"), "timeout": 12.0},
		{"id": "choose", "text": tr("The rider app (left) lists new orders. Press %s, %s or %s to take one.") % [
			Settings.key_name("order_1"), Settings.key_name("order_2"), Settings.key_name("order_3")]},
		{"id": "pickup", "text": tr("Follow the arrow (or the minimap) to the yellow marker to pick up the package.")},
		{"id": "deliver", "text": tr("Take it to the green marker before the timer runs out. Crashing damages the package and lowers your pay and rating!")},
		{"id": "shop", "text": tr("Watch your fuel (blue bar under the speedometer). At a blue G gas station press %s to refuel. Spend money at the shop (press %s on the yellow pad). Good luck!") % [
			Settings.key_name("refuel"), Settings.key_name("open_shop")], "timeout": 14.0},
	]
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.11, 0.16, 0.9)
	bg.set_corner_radius_all(10)
	bg.border_color = Color(0.98, 0.8, 0.15)
	bg.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.custom_minimum_size = Vector2(400, 0)
	_panel.offset_left = 20
	# Sized by its content and anchored at the bottom, so it shrinks when collapsed.
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = -20
	_panel.offset_bottom = -20
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 15)
	_counter.add_theme_color_override("font_color", Color(0.98, 0.8, 0.15))
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_counter)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 19)
	box.add_child(_text)
	var skip := Label.new()
	skip.text = tr("Enter: skip tutorial")
	skip.add_theme_font_size_override("font_size", 13)
	skip.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	box.add_child(skip)
	head.add_child(UITheme.collapse_button("tutorial", [_text, skip]))
	_show_step()

func _show_step() -> void:
	if _index >= _steps.size():
		GameState.complete_tutorial()
		queue_free()
		return
	_timer = 0.0
	_counter.text = tr("TUTORIAL  %d / %d") % [_index + 1, _steps.size()]
	_text.text = _steps[_index]["text"]

func _complete_step(id: String) -> void:
	if _index < _steps.size() and _steps[_index]["id"] == id:
		Audio.play("confirm", -10.0)
		_index += 1
		_show_step()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_looked += event.relative.length()
	elif event.is_action_pressed("ui_accept") and not get_tree().paused:
		_index = _steps.size()
		_show_step()

func _process(delta: float) -> void:
	if _panel == null:
		return
	_panel.visible = not get_tree().paused   # don't cover the shop / pause menu / day summary
	if _index >= _steps.size() or get_tree().paused:
		return
	_timer += delta
	var step := _steps[_index]
	match step["id"]:
		"engine":
			if _player.engine_on:
				_complete_step("engine")
		"drive":
			if _player.speed > 5.0:
				_driven += delta
			if _driven > 2.0:
				_complete_step("drive")
		"look":
			if _looked > 600.0 or _timer > step["timeout"]:
				_complete_step("look")
		# Already done ahead of the tutorial? Then skip the step.
		"choose":
			if _delivery.state != _delivery.State.IDLE:
				_complete_step("choose")
		"pickup":
			if _delivery.state == _delivery.State.TO_DROPOFF:
				_complete_step("pickup")
		"shop":
			if _timer > step["timeout"]:
				_complete_step("shop")
