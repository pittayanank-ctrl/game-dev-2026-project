extends Control
## Gas station popup (opened by the HUD with the refuel key while on a pump pad). Shows the tank,
## the price, and buttons to fill up or add one litre. The game is paused while it is open.

signal closed

var fuel: Node                     # FuelSystem
var _bar: ProgressBar
var _amount: Label
var _price: Label
var _fill_button: Button
var _litre_button: Button
var _close_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_SOLID, 16, UITheme.INFO, 2, 24.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "GAS STATION"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UITheme.INFO)
	box.add_child(title)
	_price = Label.new()
	_price.add_theme_font_size_override("font_size", 16)
	_price.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(_price)

	var tank_row := HBoxContainer.new()
	tank_row.add_theme_constant_override("separation", 10)
	var tank_label := Label.new()
	tank_label.text = "TANK"
	tank_label.add_theme_font_size_override("font_size", 15)
	tank_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	tank_row.add_child(tank_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_theme_stylebox_override("fill", UITheme.box(UITheme.INFO, 6))
	_bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.08), 6))
	tank_row.add_child(_bar)
	_amount = Label.new()
	_amount.add_theme_font_size_override("font_size", 18)
	_amount.custom_minimum_size = Vector2(96, 0)
	_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tank_row.add_child(_amount)
	box.add_child(tank_row)

	_fill_button = _button(func(): _buy(fuel.missing()))
	_fill_button.add_theme_stylebox_override("normal", UITheme.box(UITheme.INFO, 9))
	_fill_button.add_theme_color_override("font_color", Color(0.04, 0.08, 0.12))
	box.add_child(_fill_button)
	_litre_button = _button(func(): _buy(1.0))
	box.add_child(_litre_button)
	_close_button = _button(func(): close())
	box.add_child(_close_button)

func _button(handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(handler)
	return b

func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh()
	(_fill_button if not _fill_button.disabled else _close_button).grab_focus()

func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()

func _buy(litres: float) -> void:
	var before := GameState.fuel
	if fuel.buy(litres) <= 0.0:
		return
	# Animate the tank filling up.
	_bar.value = before / GameState.fuel_capacity()
	var t := create_tween()
	t.tween_property(_bar, "value", GameState.fuel / GameState.fuel_capacity(), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_refresh(false)

func _refresh(update_bar := true) -> void:
	var cap := GameState.fuel_capacity()
	if update_bar:
		_bar.value = GameState.fuel / cap
	_amount.text = "%.1f / %.1f L" % [GameState.fuel, cap]
	_price.text = tr("%d THB per litre    Your money: %d THB") % [GameState.FUEL_PRICE, GameState.money]
	var missing: float = fuel.missing()
	var can_afford := GameState.money >= 1
	if missing < 0.05:
		_fill_button.text = tr("TANK IS FULL")
		_fill_button.disabled = true
	else:
		_fill_button.text = tr("FILL UP  (%.1f L)  %d THB") % [missing, fuel.cost_of(missing)]
		_fill_button.disabled = not can_afford
	var one := minf(1.0, missing)
	_litre_button.text = tr("ADD 1 LITRE  %d THB") % fuel.cost_of(maxf(one, 0.0))
	_litre_button.disabled = missing < 0.05 or not can_afford
	_close_button.text = tr("CLOSE")
