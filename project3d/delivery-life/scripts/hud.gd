extends CanvasLayer
## HUD: money/day/goal card, current-order card with timer and package bars, direction arrow,
## minimap, speedometer, toast messages and the shop prompt. Also opens the bike shop (B / Esc).

const ShopUI := preload("res://scripts/shop_ui.gd")
const Minimap := preload("res://scripts/minimap.gd")
const Widgets := preload("res://scripts/hud_widgets.gd")
const FuelPopup := preload("res://scripts/fuel_popup.gd")

var player: CharacterBody3D
var delivery: Node3D
var clock: Node
@export var shop_position := preload("res://scripts/city.gd").SHOP_POS
@export var shop_radius := 5.0

var _hud: Control                 # everything except the shop (hidden while shopping)
var _money: Label
var _day: Label
var _time: Label
var _weather: PanelContainer
var _goal: Label
var _goal_reward: Label
var _goal_bar: ProgressBar
var _rating: Label
var _app: PanelContainer
var _app_rows: VBoxContainer
var _app_title: Label
var _app_open := true
var _map_frame: PanelContainer
var _map_toggle: Button
var _speed_lines: Control
var _flash: ColorRect
var _hint_text: Label
var fuel: Node
var _badge: PanelContainer
var _badge_label: Label
var _order_title: Label
var _order_dist: Label
var _time_row: HBoxContainer
var _time_bar: ProgressBar
var _time_value: Label
var _pkg_row: HBoxContainer
var _pkg_bar: ProgressBar
var _pkg_value: Label
var _arrow: Control
var _speedo: Control
var _minimap: Control
var _missions: PanelContainer
var _mission_title: Label
var _mission_list: VBoxContainer
var story: Node
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _hint: PanelContainer
var _hint_key: Label
var _shop: Control
var _fuel_popup: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node("../Motorcycle")
	delivery = get_node("../DeliveryManager")
	clock = get_node_or_null("../WorldClock")
	fuel = get_node_or_null("../FuelSystem")
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_speed_lines = Widgets.SpeedLines.new()
	_speed_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_speed_lines)
	_build_status_card()
	_build_app()
	_build_order_card()
	_build_minimap()
	_build_missions()
	_build_speedometer()
	_build_toast()
	_build_hint()
	_shop = ShopUI.new()
	add_child(_shop)
	_fuel_popup = FuelPopup.new()
	_fuel_popup.fuel = get_node_or_null("../FuelSystem")
	add_child(_fuel_popup)

	GameState.money_changed.connect(func(_m): _refresh())
	delivery.message.connect(show_message)
	player.notice.connect(show_message)
	player.stunt.connect(show_message)
	var lights := get_node_or_null("../TrafficLights")
	if lights:
		lights.red_light_run.connect(func(fine: int):
			var paid := GameState.spend_money(fine)
			GameState.today["fines"] += paid
			_camera_flash()
			show_message(tr("Traffic camera caught you on red!  Fine: -%d THB") % paid))
	if clock:
		clock.weather_changed.connect(func(raining: bool):
			show_message(tr("It started raining - the roads are slippery!") if raining else tr("The rain has stopped.")))
	if fuel:
		fuel.message.connect(show_message)
	GameState.goal_completed.connect(func(g: Dictionary):
		show_message(tr("Goal complete: %s  +%d THB") % [tr(g["text"]), g["reward"]]))
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_refresh()

# ------------------------------------------------------------------ building blocks

func _label(text: String, size: int, color := UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.card(14.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box

func _bar(fill: Color, height := 8) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", UITheme.box(fill, 4))
	bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.08), 4))
	return bar

func _chip(text: String, bg: Color, fg := Color(0.06, 0.07, 0.1)) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := UITheme.box(bg, 6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)
	var l := _label(text, 13, fg)
	chip.add_child(l)
	return chip

func _build_status_card() -> void:
	var holder := MarginContainer.new()
	holder.position = Vector2(16, 16)
	holder.custom_minimum_size = Vector2(290, 0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(holder)
	var box := _card(holder)
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	_money = _label("0", 34, UITheme.ACCENT)
	money_row.add_child(_money)
	var unit := _label("THB", 16, UITheme.TEXT_DIM)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	money_row.add_child(unit)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_row.add_child(fill)
	box.add_child(money_row)
	var day_row := HBoxContainer.new()
	day_row.add_theme_constant_override("separation", 8)
	_day = _label("DAY 1", 16, UITheme.TEXT_DIM)
	day_row.add_child(_day)
	_time = _label("06:00", 16)
	day_row.add_child(_time)
	_weather = _chip("RAIN", UITheme.INFO)
	_weather.visible = false
	day_row.add_child(_weather)
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	day_row.add_child(grow)
	_rating = _label("", 16, UITheme.ACCENT)
	day_row.add_child(_rating)
	box.add_child(day_row)
	var goal_sep := HSeparator.new()
	box.add_child(goal_sep)
	var goal_row := HBoxContainer.new()
	_goal = _label("", 14, Color(0.98, 0.86, 0.5))
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_row.add_child(_goal)
	_goal_reward = _label("", 14, UITheme.GOOD)
	_goal_reward.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	goal_row.add_child(_goal_reward)
	box.add_child(goal_row)
	_goal_bar = _bar(UITheme.ACCENT, 6)
	box.add_child(_goal_bar)
	var toggle := UITheme.collapse_button("status_goal", [goal_sep, goal_row, _goal_bar])
	toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	money_row.add_child(toggle)

func _build_order_card() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.custom_minimum_size = Vector2(430, 0)
	column.offset_left = -215
	column.offset_top = 16
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(column)
	var box := _card(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_badge = _chip("STANDARD", UITheme.ACCENT)
	_badge_label = _badge.get_child(0)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_badge)
	_order_title = _label("", 20)
	top.add_child(_order_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_order_dist = _label("", 20, UITheme.ACCENT)
	top.add_child(_order_dist)
	box.add_child(top)
	_time_row = _stat_row("TIME", UITheme.GOOD)
	_time_bar = _time_row.get_child(1)
	_time_value = _time_row.get_child(2)
	box.add_child(_time_row)
	_pkg_row = _stat_row("PACKAGE", UITheme.GOOD)
	_pkg_bar = _pkg_row.get_child(1)
	_pkg_value = _pkg_row.get_child(2)
	box.add_child(_pkg_row)
	_arrow = Widgets.ArrowBadge.new()
	_arrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_arrow)

func _stat_row(name: String, fill: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(name, 13, UITheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	row.add_child(_bar(fill))
	var v := _label("", 15)
	v.custom_minimum_size = Vector2(46, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

## Story missions card under the minimap: chapter name and a checklist with progress.
func _build_missions() -> void:
	story = get_node_or_null("../Story")
	_missions = PanelContainer.new()
	_missions.add_theme_stylebox_override("panel", UITheme.card(12.0))
	_missions.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_missions.offset_left = -238
	_missions.offset_top = 256
	_missions.offset_right = -16
	_missions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_missions)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_missions.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	_mission_title = _label("", 15, UITheme.ACCENT)
	_mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_mission_title)
	_mission_list = VBoxContainer.new()
	_mission_list.add_theme_constant_override("separation", 4)
	box.add_child(_mission_list)
	var toggle := UITheme.collapse_button("missions", [_mission_list])
	toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(toggle)
	if story:
		story.progress_changed.connect(_refresh_missions)
	_refresh_missions()

func _refresh_missions() -> void:
	_missions.visible = story != null and story.active()
	if not _missions.visible:
		return
	var info: Dictionary = story.chapter_info()
	_mission_title.text = "%s  -  %s" % [tr(info["title"]).to_upper(), tr(info["name"])]
	for c in _mission_list.get_children():
		c.queue_free()
	for m in info["missions"]:
		var done: bool = story.mission_done(m)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var tick := _label("✔" if done else "○", 14, UITheme.GOOD if done else UITheme.TEXT_DIM)
		tick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(tick)
		var text := _label(tr(m["text"]), 13, UITheme.TEXT_DIM if done else UITheme.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		if not done and m["target"] > 1:
			var p := _label("%d/%d" % [story.progress(m["id"]), m["target"]], 13, UITheme.ACCENT)
			p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(p)
		_mission_list.add_child(row)

func _build_minimap() -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.card(6.0))
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -238
	frame.offset_top = 16
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(frame)
	_map_frame = frame
	_map_toggle = UITheme.collapse_button("minimap", [frame], func(open: bool):
		if _map_toggle:
			_map_toggle.text = "–" if open else tr("MAP") + "  +")
	if not frame.visible:
		_map_toggle.text = tr("MAP") + "  +"
	_map_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_map_toggle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map_toggle.offset_right = -22
	_map_toggle.offset_top = 22
	_minimap = Minimap.new()
	_minimap.player = player
	_minimap.delivery = delivery
	_minimap.traffic = get_node_or_null("../TrafficManager")
	frame.add_child(_minimap)
	_hud.add_child(_map_toggle)   # drawn over the map's corner

func _build_speedometer() -> void:
	_speedo = Widgets.Speedometer.new()
	_speedo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speedo.offset_left = -190
	_speedo.offset_top = -190
	_speedo.offset_right = -20
	_speedo.offset_bottom = -20
	_hud.add_child(_speedo)

# Notifications slide up from the bottom edge (above the key hint), stay a moment, then slide
# back down, so they don't cover the road ahead.
const TOAST_REST := -88.0            # bottom edge when shown (pixels from the screen bottom)
var _toast_slide := 0.0              # 0 = hidden below the screen, 1 = shown

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_hud.add_child(_toast)
	_toast_label = _label("", 18)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)

func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", UITheme.card(10.0))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -74
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_hint.add_child(row)
	var key := PanelContainer.new()
	var sb := UITheme.box(UITheme.ACCENT, 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	key.add_theme_stylebox_override("panel", sb)
	_hint_key = _label("B", 18, Color(0.08, 0.07, 0.02))
	key.add_child(_hint_key)
	row.add_child(key)
	_hint_text = _label("Open the motorcycle shop", 18)
	row.add_child(_hint_text)

# ------------------------------------------------------------------ updates

## Rider app: the three order offers shown while waiting for a job.
func _build_app() -> void:
	_app = PanelContainer.new()
	_app.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app.add_theme_stylebox_override("panel", UITheme.card(12.0))
	_app.position = Vector2(16, 200)
	_app.custom_minimum_size = Vector2(320, 0)
	_app.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_app)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_app.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_app_title = _label("RIDER APP", 15, UITheme.ACCENT)
	head.add_child(_app_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var hint := _label("Click or press 1-3", 13, UITheme.TEXT_DIM)
	head.add_child(hint)
	box.add_child(head)
	_app_rows = VBoxContainer.new()
	_app_rows.add_theme_constant_override("separation", 6)
	box.add_child(_app_rows)
	head.add_child(UITheme.collapse_button("rider_app", [_app_rows, hint], func(open: bool): _app_open = open))
	_app.visible = false

func _offer_row(n: int, o: Dictionary) -> PanelContainer:
	var info: Dictionary = delivery.ORDER_TYPES[o["type"]]
	var vip: bool = o["type"] == "vip" or o.get("story", false)
	var row := PanelContainer.new()
	var sb := UITheme.box(Color(1, 1, 1, 0.05), 8, UITheme.ACCENT if vip else Color(1, 1, 1, 0.06), 2 if vip else 1, 8.0)
	var hover := UITheme.box(Color(1, 1, 1, 0.12), 8, UITheme.ACCENT, 2, 8.0)
	row.add_theme_stylebox_override("panel", sb)
	# Clickable: hover highlights the card, left click takes the order. PASS (not STOP) so a
	# right-button drag over the card still reaches the camera.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = ""
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", sb))
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			row.accept_event()
			delivery.accept_offer(n))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var key := _chip(Settings.key_name("order_%d" % (n + 1)), UITheme.SURFACE_HOVER, UITheme.TEXT)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(key)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var badge := _chip(tr(info["name"]).to_upper(), info["tape"])
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(badge)
	var what := _label(tr(delivery.CargoItems.item_name(o.get("item", "parcel"))), 14, UITheme.TEXT)
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(what)
	mid.add_child(top)
	var details := _label(_offer_details(o), 13, UITheme.TEXT_DIM)
	_offer_details_labels.append(details)
	mid.add_child(details)
	h.add_child(mid)
	var pay := _label("%d" % o["pay"], 20, UITheme.ACCENT)
	pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pay)
	# Children must not catch the mouse, so clicks land on the card itself.
	for c in row.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

func _offer_details(o: Dictionary) -> String:
	return tr("%d m away  ·  trip %d m  ·  %d s") % [int(delivery.offer_distance(o)), int(o["trip"]), int(o["time"])]

var _app_signature := ""
var _offer_details_labels: Array[Label] = []
var _details_timer := 0.0
func _update_app() -> void:
	var idle: bool = delivery.state == delivery.State.IDLE and not delivery.offers.is_empty()
	_app.visible = idle
	_app_title.text = tr("RIDER APP") if _app_open else "%s  (%d)" % [tr("RIDER APP"), delivery.offers.size()]
	if _map_frame:
		_missions.offset_top = (_map_frame.get_rect().end.y if _map_frame.visible else 50.0) + 12.0
	if not idle:
		_app_signature = ""
		return
	# Rebuild the cards only when the offers themselves change (keeps hover/clicks working);
	# the distances are refreshed in place twice a second.
	var sig := str(delivery.offers.hash())
	if sig != _app_signature:
		_app_signature = sig
		for c in _app_rows.get_children():
			c.queue_free()
		_offer_details_labels.clear()
		for n in delivery.offers.size():
			_app_rows.add_child(_offer_row(n, delivery.offers[n]))
	_details_timer -= get_process_delta_time()
	if _details_timer <= 0.0:
		_details_timer = 0.5
		for n in mini(_offer_details_labels.size(), delivery.offers.size()):
			_offer_details_labels[n].text = _offer_details(delivery.offers[n])

func _camera_flash() -> void:
	_flash.color = Color(1, 1, 1, 0.75)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.45)

func _refresh() -> void:
	_money.text = _thousands(GameState.money)
	var g := GameState.next_goal()
	if g.is_empty():
		_goal.text = tr("All goals complete - Delivery Legend!")
		_goal_reward.text = ""
		_goal_bar.value = 1.0
	else:
		var p := mini(GameState.goal_progress(g), g["target"])
		_goal.text = "%s  (%d/%d)" % [tr(g["text"]), p, g["target"]]
		_goal_reward.text = "+%d" % g["reward"]
		_goal_bar.value = float(p) / float(g["target"])

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## Animated message banner. The border colour follows the kind of news.
func show_message(text: String) -> void:
	var lower := text.to_lower()
	var col := UITheme.ACCENT
	if lower.contains("crash") or lower.contains("fail") or lower.contains("broke") or lower.contains("fine"):
		col = UITheme.BAD
	elif lower.contains("delivered") or lower.contains("goal complete"):
		col = UITheme.GOOD
	elif lower.contains("rain"):
		col = UITheme.INFO
	var sb := UITheme.box(UITheme.BG_SOLID, 12, col, 2, 14.0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	_toast.add_theme_stylebox_override("panel", sb)
	_toast_label.text = text
	_toast.visible = true
	_toast.reset_size()
	var w := _toast.get_combined_minimum_size().x
	_toast.offset_left = -w * 0.5
	_toast.offset_right = w * 0.5
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	# Slide up (from wherever it is now), wait, slide back down.
	_toast_tween.tween_method(_place_toast, _toast_slide, 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_method(_place_toast, 1.0, 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_toast_tween.tween_callback(func(): _toast.visible = false)

func _place_toast(slide: float) -> void:
	_toast_slide = slide
	var h := _toast.get_combined_minimum_size().y
	var bottom := lerpf(h + 12.0, TOAST_REST, slide)   # hidden: just below the screen edge
	_toast.offset_bottom = bottom
	_toast.offset_top = bottom - h

func _near_shop() -> bool:
	var flat := Vector3(player.global_position.x, 0, player.global_position.z)
	return flat.distance_to(shop_position) < shop_radius

func _set_shop_open(open: bool) -> void:
	if open != _shop.visible:
		Audio.play("open" if open else "close", -6.0)
	_shop.visible = open
	get_tree().paused = open
	if open:
		_shop.open()

func _unhandled_input(event: InputEvent) -> void:
	if _fuel_popup.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("refuel"):
			_fuel_popup.close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("refuel") and fuel and fuel.near_station() and not get_tree().paused:
		_fuel_popup.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_shop"):
		# Don't open over another pause (pause menu, day summary).
		if _shop.visible or (_near_shop() and not get_tree().paused):
			_set_shop_open(not _shop.visible)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and _shop.visible:
		_set_shop_open(false)
		get_viewport().set_input_as_handled()

var _locale := ""
var _speed_lines_drawn := false
var _last_dial := Vector2i(-1, -1)
var _last_arrow := Vector2i(-9999, -1)
func _process(_delta: float) -> void:
	if player == null:
		return
	if TranslationServer.get_locale() != _locale:   # language switched: redraw translated texts
		_locale = TranslationServer.get_locale()
		_refresh()
		_refresh_missions()
		_app_signature = ""
	_hud.visible = not get_tree().paused   # shop, pause menu and day summary cover the screen
	_speedo.value = player.speed_kmh()
	_speedo.max_value = player.max_speed * 3.6
	_speedo.fuel = GameState.fuel / GameState.fuel_capacity()
	var ratio := clampf(absf(player.speed) / maxf(player.max_speed, 1.0), 0.0, 1.0)
	_speed_lines.strength = clampf((ratio - 0.6) / 0.4, 0.0, 1.0)
	if _speed_lines.strength > 0.0 or _speed_lines_drawn:
		_speed_lines.queue_redraw()
		_speed_lines_drawn = _speed_lines.strength > 0.0
	_rating.text = "★ " + ("%.1f" % GameState.rating() if not GameState.ratings.is_empty() else tr("NEW"))
	_update_app()
	# Redraw the dial only when what it shows changes.
	var dial := Vector2i(int(_speedo.value), int(_speedo.fuel * 100.0))
	if dial != _last_dial:
		_last_dial = dial
		_speedo.queue_redraw()
	if clock:
		_day.text = tr("DAY %d") % GameState.day
		_time.text = clock.time_text()
		_weather.visible = clock.raining
	_update_order()
	_update_arrow()
	# Bottom prompt: shop, or refuelling at a gas station.
	if fuel and fuel.near_station():
		_hint.visible = true
		_hint_key.text = Settings.key_name("refuel")
		_hint_text.text = tr("Refuel at the gas station")
	elif _near_shop():
		_hint.visible = not _shop.visible
		_hint_key.text = Settings.key_name("open_shop")
		_hint_text.text = tr("Open the motorcycle shop")
	else:
		# Engine off (and not out of fuel): remind how to start it.
		_hint.visible = not player.engine_on and player._cranking <= 0.0 and GameState.fuel > 0.0
		_hint_key.text = Settings.key_name("engine")
		_hint_text.text = tr("Start the engine")

func _update_order() -> void:
	var info: Dictionary = delivery.order_info()
	var carrying: bool = delivery.state == delivery.State.TO_DROPOFF
	_badge.visible = delivery.state != delivery.State.IDLE
	_badge_label.text = tr(info["name"]).to_upper() + "  ·  " + tr(delivery.CargoItems.item_name(delivery.item))
	_set_style(_badge, "panel", _badge_style(info["tape"]))
	var target = delivery.target_position()
	match delivery.state:
		delivery.State.TO_PICKUP:
			_order_title.text = tr("Pick up the package")
		delivery.State.TO_DROPOFF:
			var stops: int = delivery.drops.size()
			_order_title.text = tr("Deliver") if stops == 1 else tr("Deliver  (%d stops)") % stops
		_:
			_order_title.text = tr("Choose an order in the rider app")
	if target != null:
		var here := Vector3(player.global_position.x, 0, player.global_position.z)
		_order_dist.text = "%d m" % int(here.distance_to(Vector3(target.x, 0, target.z)))
	else:
		_order_dist.text = ""
	_time_row.visible = carrying
	_pkg_row.visible = carrying
	if carrying:
		var t := maxf(delivery.time_left, 0.0)
		_time_bar.value = t / maxf(delivery.time_limit, 0.1)
		_time_value.text = "%ds" % int(t)
		var urgent := t < 10.0
		_set_style(_time_bar, "fill", _fill_style(UITheme.BAD if urgent else UITheme.GOOD))
		if _time_value.get_theme_color("font_color") != (UITheme.BAD if urgent else UITheme.TEXT):
			_time_value.add_theme_color_override("font_color", UITheme.BAD if urgent else UITheme.TEXT)
		var cond: float = delivery.condition
		_pkg_bar.value = cond / 100.0
		_pkg_value.text = "%d%%" % int(cond)
		var col := UITheme.GOOD if cond > 70.0 else (UITheme.ACCENT if cond > 35.0 else UITheme.BAD)
		_set_style(_pkg_bar, "fill", _fill_style(col))

## Theme overrides make a Control re-layout, so only apply them when they actually change.
func _set_style(c: Control, name: String, sb: StyleBox) -> void:
	if c.get_theme_stylebox(name) != sb:
		c.add_theme_stylebox_override(name, sb)

var _fill_cache := {}
func _fill_style(col: Color) -> StyleBoxFlat:
	if not _fill_cache.has(col):
		_fill_cache[col] = UITheme.box(col, 4)
	return _fill_cache[col]

var _badge_cache := {}
func _badge_style(col: Color) -> StyleBoxFlat:
	if not _badge_cache.has(col):
		var sb := UITheme.box(col, 6)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		_badge_cache[col] = sb
	return _badge_cache[col]

func _update_arrow() -> void:
	var cam := get_viewport().get_camera_3d()
	var target = delivery.target_position()
	if cam == null or target == null:
		_arrow.visible = false
		return
	var to_target: Vector3 = target - cam.global_position
	to_target.y = 0.0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001 or to_target.length() < 0.001:
		return
	# Positive signed angle = target is to the left; screen rotation is clockwise-positive.
	_arrow.angle = -fwd.signed_angle_to(to_target, Vector3.UP)
	_arrow.color = delivery.target_color()
	var here := Vector3(player.global_position.x, 0, player.global_position.z)
	_arrow.distance = int(here.distance_to(Vector3(target.x, 0, target.z)))
	_arrow.visible = true
	var key := Vector2i(int(_arrow.angle * 60.0), _arrow.distance)
	if key != _last_arrow:
		_last_arrow = key
		_arrow.queue_redraw()
