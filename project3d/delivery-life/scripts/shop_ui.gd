extends Control
## Motorcycle shop: bike list on the left, a live 3D preview in the middle (with the selected paint),
## stats and paint swatches on the right. Opened/closed by the HUD (B / Esc).

const BIKE_SCENE := preload("res://scenes/motorcycle.tscn")
const ACCENT := Color(0.98, 0.8, 0.15)
const PANEL_BG := Color(0.09, 0.11, 0.16, 0.97)

var _sel_bike := ""
var _sel_color := ""

var _money_label: Label
var _bike_list: VBoxContainer
var _name_label: Label
var _status_label: Label
var _stats_box: VBoxContainer
var _swatches: GridContainer
var _page_bikes: VBoxContainer
var _page_up: VBoxContainer
var _up_list: VBoxContainer
var _tab := 0
var _tab_buttons: Array[Button] = []
var _bike_button: Button
var _color_button: Button
var _turntable: Node3D
var _preview_vp: SubViewport
var _preview_bike: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep animating while the game is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	GameState.money_changed.connect(func(_m): _refresh())
	GameState.bike_changed.connect(_refresh)

func _process(delta: float) -> void:
	if visible and _turntable:
		_turntable.rotate_y(0.7 * delta)

func _notification(what: int) -> void:
	# A hidden SubViewport still renders its whole 3D scene every frame unless we stop it.
	if what == NOTIFICATION_VISIBILITY_CHANGED and _preview_vp:
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED

func open() -> void:
	_sel_bike = GameState.current_id
	_sel_color = GameState.zone_colors.get("body", "white")
	_refresh()

# ---------------------------------------------------------------- layout

func _style(color: Color, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1080, 600)
	panel.offset_left = -540
	panel.offset_top = -300
	panel.add_theme_stylebox_override("panel", _style(PANEL_BG, 14))
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# Header
	var header := HBoxContainer.new()
	root.add_child(header)
	header.add_child(_label("MOTORCYCLE SHOP", 34, ACCENT))
	var tab_gap := Control.new()
	tab_gap.custom_minimum_size = Vector2(30, 0)
	header.add_child(tab_gap)
	for i in 2:
		var tb := Button.new()
		tb.text = ["BIKES & PAINT", "UPGRADES"][i]
		tb.custom_minimum_size = Vector2(170, 40)
		tb.add_theme_font_size_override("font_size", 18)
		tb.add_theme_color_override("font_disabled_color", ACCENT)   # the active tab is the disabled one
		tb.pressed.connect(func():
			_tab = i
			_refresh())
		header.add_child(tb)
		_tab_buttons.append(tb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_money_label = _label("", 26)
	header.add_child(_money_label)
	root.add_child(_label("B / Esc to close", 16, Color(0.6, 0.65, 0.75)))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)

	# Left: bike list
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	left.add_child(_label("BIKES", 20, Color(0.7, 0.75, 0.85)))
	_bike_list = VBoxContainer.new()
	_bike_list.add_theme_constant_override("separation", 8)
	left.add_child(_bike_list)

	# Middle: 3D preview
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 6)
	body.add_child(middle)
	_name_label = _label("", 34)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_name_label)
	_status_label = _label("", 18, Color(0.7, 0.75, 0.85))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_status_label)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _style(Color(0.14, 0.17, 0.24), 12))
	middle.add_child(frame)
	frame.add_child(_build_preview())

	# Right: stats (always) + a page below: paint & buy, or upgrades
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	right.add_child(_label("STATS", 20, Color(0.7, 0.75, 0.85)))
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	right.add_child(_stats_box)

	_page_bikes = VBoxContainer.new()
	_page_bikes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_bikes.add_theme_constant_override("separation", 10)
	right.add_child(_page_bikes)
	_page_bikes.add_child(_label("BODY PAINT", 20, Color(0.7, 0.75, 0.85)))
	_swatches = GridContainer.new()
	_swatches.columns = 4
	_swatches.add_theme_constant_override("h_separation", 8)
	_swatches.add_theme_constant_override("v_separation", 8)
	_page_bikes.add_child(_swatches)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_bikes.add_child(grow)
	_color_button = _action_button()
	_color_button.pressed.connect(_on_color_action)
	_page_bikes.add_child(_color_button)
	_bike_button = _action_button()
	_bike_button.pressed.connect(_on_bike_action)
	_page_bikes.add_child(_bike_button)

	_page_up = VBoxContainer.new()
	_page_up.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_up.add_theme_constant_override("separation", 8)
	right.add_child(_page_up)
	_page_up.add_child(_label("UPGRADES", 20, Color(0.7, 0.75, 0.85)))
	_up_list = VBoxContainer.new()
	_up_list.add_theme_constant_override("separation", 8)
	_page_up.add_child(_up_list)

func _action_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 22)
	return b

func _build_preview() -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(440, 380)
	var vp := SubViewport.new()
	_preview_vp = vp
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED   # turned on only while the shop is open
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_color = Color(1.0, 0.8, 0.4)
	rim.light_energy = 0.7
	vp.add_child(rim)

	_turntable = Node3D.new()
	vp.add_child(_turntable)
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.7
	disc_mesh.bottom_radius = 1.7
	disc_mesh.height = 0.08
	disc.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.2, 0.23, 0.3)
	disc.material_override = disc_mat
	disc.position.y = -0.04
	_turntable.add_child(disc)
	_preview_bike = BIKE_SCENE.instantiate()
	_preview_bike.preview_only = true
	_turntable.add_child(_preview_bike)

	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.1, 2.7), Vector3(0, 0.68, 0))
	cam.current = true
	return container

# ---------------------------------------------------------------- state

func _refresh() -> void:
	if not visible and _sel_bike == "":
		return
	_money_label.text = "%d THB" % GameState.money
	_refresh_bikes()
	_refresh_stats()
	_refresh_swatches()
	_refresh_actions()
	_refresh_upgrades()
	_refresh_tabs()
	var col: Color = GameState.color_by_id(_sel_color)["color"]
	_preview_bike.set_model(str(GameState.bike_by_id(_sel_bike).get("model", "pcx")))
	_preview_bike.apply_body_color(col)

func _refresh_bikes() -> void:
	for c in _bike_list.get_children():
		c.queue_free()
	for b in GameState.BIKES:
		var id: String = b["id"]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 62)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 20)
		var tag := tr("EQUIPPED") if id == GameState.current_id else (tr("OWNED") if id in GameState.owned else "%d THB" % b["price"])
		btn.text = "  %s\n  %s" % [tr(b["name"]), tag]
		var selected := id == _sel_bike
		btn.add_theme_stylebox_override("normal", _style(Color(0.22, 0.27, 0.38) if selected else Color(0.14, 0.17, 0.24), 8))
		btn.add_theme_stylebox_override("hover", _style(Color(0.26, 0.32, 0.45), 8))
		btn.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.36, 0.5), 8))
		if selected:
			var sb := _style(Color(0.22, 0.27, 0.38), 8)
			sb.set_border_width_all(2)
			sb.border_color = ACCENT
			btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(func():
			_sel_bike = id
			_refresh())
		_bike_list.add_child(btn)

func _refresh_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	var b := GameState.bike_by_id(_sel_bike)
	_name_label.text = b["name"]
	_status_label.text = tr("Equipped") if _sel_bike == GameState.current_id else (tr("Owned") if _sel_bike in GameState.owned else tr("Not owned  -  %d THB") % b["price"])
	# Bars are scaled against the best fully-upgraded bike so upgrades visibly fill them.
	var best := {}
	for stat in ["max_speed", "acceleration", "turn_speed", "brake_force"]:
		best[stat] = 0.0
		for o in GameState.BIKES:
			best[stat] = maxf(best[stat], GameState.effective_stats(o["id"], true)[stat])
	var eff := GameState.effective_stats(_sel_bike)
	_add_stat(tr("Top speed  %d km/h") % int(eff["max_speed"] * 3.6), eff["max_speed"] / best["max_speed"], b["max_speed"] / best["max_speed"])
	_add_stat(tr("Acceleration  %d") % int(round(eff["acceleration"])), eff["acceleration"] / best["acceleration"], b["acceleration"] / best["acceleration"])
	_add_stat(tr("Handling  %.1f") % eff["turn_speed"], eff["turn_speed"] / best["turn_speed"], b["turn_speed"] / best["turn_speed"])
	_add_stat(tr("Braking  %d") % int(round(eff["brake_force"])), eff["brake_force"] / best["brake_force"], b["brake_force"] / best["brake_force"])

func _add_stat(text: String, ratio: float, base_ratio: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label(text, 15, Color(0.85, 0.88, 0.95))
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = ratio
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", _style(Color(0.16, 0.19, 0.27), 5))
	bar.add_theme_stylebox_override("fill", _style(Color(0.35, 0.85, 0.5) if ratio > base_ratio + 0.001 else ACCENT, 5))
	row.add_child(bar)
	_stats_box.add_child(row)

func _refresh_swatches() -> void:
	for c in _swatches.get_children():
		c.queue_free()
	for c in GameState.COLORS:
		var id: String = c["id"]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(56, 56)
		btn.tooltip_text = c["name"]
		var owned: bool = id in GameState.owned_colors
		btn.text = "" if owned else "%d" % c["price"]
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_outline_color", Color.BLACK)
		btn.add_theme_constant_override("outline_size", 5)
		var sb := _style(c["color"], 8)
		if id == _sel_color:
			sb.set_border_width_all(3)
			sb.border_color = ACCENT
		elif id == GameState.zone_colors.get("body", "white"):
			sb.set_border_width_all(2)
			sb.border_color = Color(1, 1, 1, 0.6)
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, sb)
		btn.pressed.connect(func():
			_sel_color = id
			_refresh())
		_swatches.add_child(btn)

func _refresh_actions() -> void:
	# Bike
	var b := GameState.bike_by_id(_sel_bike)
	if _sel_bike == GameState.current_id:
		_bike_button.text = "EQUIPPED"
		_bike_button.disabled = true
	elif _sel_bike in GameState.owned:
		_bike_button.text = "EQUIP BIKE"
		_bike_button.disabled = false
	else:
		_bike_button.text = tr("BUY BIKE  %d THB") % b["price"]
		_bike_button.disabled = GameState.money < b["price"]
	# Paint
	var c := GameState.color_by_id(_sel_color)
	if _sel_color == GameState.zone_colors.get("body", "white"):
		_color_button.text = "PAINT APPLIED"
		_color_button.disabled = true
	elif _sel_color in GameState.owned_colors:
		_color_button.text = tr("APPLY %s") % tr(c["name"]).to_upper()
		_color_button.disabled = false
	else:
		_color_button.text = tr("BUY %s  %d THB") % [tr(c["name"]).to_upper(), c["price"]]
		_color_button.disabled = GameState.money < c["price"]

func _on_bike_action() -> void:
	if _sel_bike in GameState.owned:
		GameState.equip_bike(_sel_bike)
	else:
		GameState.buy_bike(_sel_bike)

func _on_color_action() -> void:
	if _sel_color in GameState.owned_colors:
		GameState.equip_color("body", _sel_color)
	else:
		GameState.buy_color("body", _sel_color)

func _refresh_tabs() -> void:
	_page_bikes.visible = _tab == 0
	_page_up.visible = _tab == 1
	for i in _tab_buttons.size():
		_tab_buttons[i].disabled = i == _tab

func _refresh_upgrades() -> void:
	for c in _up_list.get_children():
		c.queue_free()
	if _sel_bike not in GameState.owned:
		var hint := _label("Buy this bike to upgrade it.", 18, Color(0.7, 0.75, 0.85))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_up_list.add_child(hint)
		return
	for u in GameState.UPGRADES:
		var uid: String = u["id"]
		var level := GameState.upgrade_level(_sel_bike, uid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := _label(u["name"], 16)
		name_label.custom_minimum_size = Vector2(118, 0)
		name_label.tooltip_text = tr("+%d%% per level (now +%d%%)") % [int(round(u["per_level"] * 100.0)), int(round(u["per_level"] * level * 100.0))]
		row.add_child(name_label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in GameState.MAX_UPGRADE_LEVEL:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(14, 14)
			pip.color = ACCENT if i < level else Color(0.2, 0.24, 0.33)
			pips.add_child(pip)
		row.add_child(pips)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gap)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 34)
		btn.add_theme_font_size_override("font_size", 15)
		if level >= GameState.MAX_UPGRADE_LEVEL:
			btn.text = "MAX"
			btn.disabled = true
		else:
			var cost := GameState.upgrade_cost(_sel_bike, uid)
			btn.text = "%d THB" % cost
			btn.disabled = GameState.money < cost
			btn.pressed.connect(func(): GameState.buy_upgrade(_sel_bike, uid))
		row.add_child(btn)
		_up_list.add_child(row)
