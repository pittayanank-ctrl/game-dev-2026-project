extends CanvasLayer
## Cutscene player: letterbox bars, a scripted camera that glides between shots, title cards and
## a dialogue box with typewriter text. The game is paused while a cutscene plays.
##
## A cutscene is an Array of steps (Dictionaries):
##   {"title": "CHAPTER 1", "subtitle": "First Day", "time": 3.0}     title card, auto-advances
##   {"speaker": "pim", "text": "Hello!"}                              dialogue line, waits for input
##   any step may add "shot": "bike_front" / "bike_side" / "bike_back" / "overview" / "shop"
## Space / Enter / click / gamepad A: finish the line or go to the next one. Esc / B: skip.

signal finished
signal line_shown                    # a dialogue line started (for the blip sound)

const SPEAKERS := {
	"mek": {"name": "Mek", "color": Color(0.98, 0.78, 0.16)},
	"pim": {"name": "Pim", "color": Color(0.35, 0.75, 1.0)},
	"grandpa": {"name": "Grandpa Somchai", "color": Color(0.65, 0.85, 0.5)},
	"jet": {"name": "Jet", "color": Color(0.95, 0.38, 0.35)},
	"noi": {"name": "Mama Noi", "color": Color(0.98, 0.55, 0.8)},
	"monk": {"name": "Luang Ta", "color": Color(1.0, 0.62, 0.15)},
}
const CHARS_PER_SEC := 45.0

var playing := false
var _steps: Array = []
var _index := 0
var _shown := 0.0             # characters revealed so far
var _step_time := 0.0
var _cam: Camera3D
var _shot := ""
var _shot_time := 0.0
var _prev_camera: Camera3D

var _root: Control
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _title: Label
var _subtitle: Label
var _box: PanelContainer
var _portrait: Control
var _portrait_letter: Label
var _name: Label
var _text: Label
var _hint: Label

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_top_bar = _bar(Control.PRESET_TOP_WIDE)
	_bottom_bar = _bar(Control.PRESET_BOTTOM_WIDE)

	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.offset_top = -60
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 60)
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 12)
	_root.add_child(_title)
	_subtitle = Label.new()
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle.offset_top = 20
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 28)
	_subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	_subtitle.add_theme_constant_override("outline_size", 8)
	_root.add_child(_subtitle)

	# Dialogue box: portrait circle, speaker name, text, "press to continue" hint.
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_SOLID, 14, Color(1, 1, 1, 0.1), 1, 16.0))
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_box.custom_minimum_size = Vector2(820, 130)
	_box.offset_left = -410
	_box.offset_right = 410
	_box.offset_top = -214
	_box.offset_bottom = -30
	_root.add_child(_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_box.add_child(row)
	_portrait = PanelContainer.new()
	_portrait.custom_minimum_size = Vector2(84, 84)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait)
	_portrait_letter = Label.new()
	_portrait_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_letter.add_theme_font_size_override("font_size", 40)
	_portrait_letter.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	_portrait.add_child(_portrait_letter)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	col.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 21)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_text)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	col.add_child(_hint)

func _bar(preset: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.set_anchors_and_offsets_preset(preset)
	r.custom_minimum_size = Vector2(0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r

# ------------------------------------------------------------------ playback

func play(steps: Array) -> void:
	_steps = steps
	_index = 0
	playing = true
	_root.visible = true
	get_tree().paused = true
	_prev_camera = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 60.0
	get_parent().add_child(_cam)
	_shot = ""
	_set_bars(1.0)
	_begin_step()

func _set_bars(amount: float) -> void:
	var h := 80.0 * amount
	var t := create_tween().set_parallel(true)
	t.tween_property(_top_bar, "offset_bottom", h, 0.4)
	t.tween_property(_bottom_bar, "offset_top", -h, 0.4)

func _begin_step() -> void:
	if _index >= _steps.size():
		_end()
		return
	var step: Dictionary = _steps[_index]
	_step_time = 0.0
	_shown = 0.0
	if step.has("shot") and step["shot"] != _shot:
		_shot = step["shot"]
		_shot_time = 0.0
		_snap_camera()
	var is_title := step.has("title")
	_title.visible = is_title
	_subtitle.visible = is_title
	_box.visible = not is_title
	if is_title:
		_title.text = tr(step["title"])
		_subtitle.text = tr(step.get("subtitle", ""))
		for l in [_title, _subtitle]:
			l.modulate.a = 0.0
			l.reset_size()
			l.offset_left = -l.size.x * 0.5
			l.offset_right = l.size.x * 0.5
			create_tween().tween_property(l, "modulate:a", 1.0, 0.6)
	else:
		var sp: Dictionary = SPEAKERS.get(step.get("speaker", "mek"), SPEAKERS["mek"])
		line_shown.emit()
		_name.text = tr(sp["name"])
		_name.add_theme_color_override("font_color", sp["color"])
		_portrait.add_theme_stylebox_override("panel", UITheme.box(sp["color"], 42))
		_portrait_letter.text = _initial(tr(sp["name"]))
		_text.text = tr(step["text"])
		_text.visible_characters = 0
		_hint.text = tr("Space: continue    Esc: skip")

## First letter for the portrait; skips Thai leading vowels (เ แ โ ใ ไ) so เจ็ท shows จ.
static func _initial(name: String) -> String:
	var i := 0
	while i < name.length() - 1 and "เแโใไ".contains(name[i]):
		i += 1
	return name[i]

func _advance() -> void:
	var step: Dictionary = _steps[_index]
	var typing := _text.visible_characters != -1 and _text.visible_characters < _text.get_total_character_count()
	if not step.has("title") and typing:
		_shown = 9999.0   # first press: show the whole line
		_text.visible_characters = -1
		return
	_index += 1
	_begin_step()

func _end() -> void:
	playing = false
	_set_bars(0.0)
	_box.visible = false
	_title.visible = false
	_subtitle.visible = false
	await get_tree().create_timer(0.4, true, false, true).timeout
	_root.visible = false
	if is_instance_valid(_cam):
		_cam.queue_free()
	if is_instance_valid(_prev_camera):
		_prev_camera.current = true
	get_tree().paused = false
	finished.emit()

func _input(event: InputEvent) -> void:
	if not playing:
		return
	var next: bool = event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if next:
		_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_index = _steps.size()
		_end()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not playing or _index >= _steps.size():
		return
	var step: Dictionary = _steps[_index]
	_step_time += delta
	if step.has("title"):
		if _step_time > step.get("time", 3.0):
			_advance()
	else:
		_shown += CHARS_PER_SEC * delta
		if _text.visible_characters >= 0:
			_text.visible_characters = mini(int(_shown), _text.get_total_character_count())
	_shot_time += delta
	_update_camera(delta)

# ------------------------------------------------------------------ camera shots

## Where the camera sits and looks for a shot, `t` seconds in (shots drift slowly).
func _shot_frame(t: float) -> Array:
	var bike: Node3D = get_parent().get_node("Motorcycle")
	var b := bike.global_position
	var fwd := -bike.global_transform.basis.z
	var right := bike.global_transform.basis.x
	match _shot:
		"bike_front":
			var a := deg_to_rad(20.0 + t * 3.0)
			var dir := (fwd * cos(a) + right * sin(a)).normalized()
			return [b + dir * 4.2 + Vector3(0, 1.5, 0), b + Vector3(0, 1.1, 0)]
		"bike_side":
			return [b + right * 4.5 + fwd * (0.8 - t * 0.15) + Vector3(0, 1.3, 0), b + Vector3(0, 1.0, 0)]
		"bike_back":
			return [b - fwd * 5.5 + right * 1.2 + Vector3(0, 2.2, 0), b + fwd * 6.0 + Vector3(0, 1.0, 0)]
		"overview":
			var a2 := t * 0.05
			return [b + Vector3(cos(a2) * 45.0, 38.0, sin(a2) * 45.0), b]
		"shop":
			var sp: Vector3 = preload("res://scripts/city.gd").SHOP_POS
			return [sp + Vector3(-16, 6, -14 + t * 0.6), sp + Vector3(8, 3, 0)]
		"temple":
			var tp: Vector3 = preload("res://scripts/story.gd").TEMPLE_DROP
			return [tp + Vector3(10.0, 5.0, 14.0 - t * 0.5), tp + Vector3(-22.0, 6.0, 0)]
		"station":
			var st: Vector3 = preload("res://scripts/story.gd").STATION_DROP
			return [st + Vector3(2.0, 17.0, 46.0 - t * 0.8), st + Vector3(-3.0, 10.0, 0)]
	return [b - fwd * 6.0 + Vector3(0, 2.5, 0), b + Vector3(0, 1.0, 0)]

func _snap_camera() -> void:
	var f := _shot_frame(0.0)
	if _cam.current:
		# Already in a cutscene: glide to the new shot instead of cutting.
		var from := _cam.global_transform
		var to := Transform3D(Basis.IDENTITY, f[0]).looking_at(f[1], Vector3.UP)
		_glide_from = from
		_glide_to = to
		_glide = 0.0
	else:
		_cam.look_at_from_position(f[0], f[1])
		_cam.current = true
		_glide = 1.0

var _glide := 1.0
var _glide_from: Transform3D
var _glide_to: Transform3D

func _update_camera(delta: float) -> void:
	var f := _shot_frame(_shot_time)
	var target := Transform3D(Basis.IDENTITY, f[0]).looking_at(f[1], Vector3.UP)
	if _glide < 1.0:
		_glide = minf(_glide + delta / 1.2, 1.0)
		var k := smoothstep(0.0, 1.0, _glide)
		_cam.global_transform = _glide_from.interpolate_with(target, k)
	else:
		_cam.global_transform = target
