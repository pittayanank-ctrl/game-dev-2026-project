extends CanvasLayer
## Autoload "Loader": loading screen for scene changes. `Loader.change_scene(path)` shows the
## screen, loads the scene in the background (progress bar), swaps it in, gives it a moment to
## settle (first frames build the city and compile shaders) and then fades out.

const TIPS := [
	"Tip: Express orders pay more, but the timer is short.",
	"Tip: Crashing damages the package - and your pay and rating.",
	"Tip: Running a red light can get you fined by a traffic camera.",
	"Tip: Refuel at the blue G stations on the minimap.",
	"Tip: Press Shift for Mouse Lock, or hold the right mouse button to look around.",
	"Tip: A 4.5 star rating unlocks VIP orders.",
	"Tip: Upgrades at the shop make your bike faster and safer.",
	"Tip: Roads are slippery in the rain - brake early!",
]
const SETTLE_TIME := 0.6         # seconds the new scene runs behind the screen before it fades

var busy := false
var _root: Control
var _bar: ProgressBar
var _percent: Label
var _tip: Label
var _spinner: Control
var _shown_progress := 0.0
var _target_progress := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks while loading
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)
	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 12)
	title.add_child(_label("DELIVERY", 52, UITheme.ACCENT))
	title.add_child(_label("LIFE", 52, UITheme.TEXT))
	box.add_child(title)
	_spinner = Spinner.new()
	_spinner.custom_minimum_size = Vector2(0, 64)
	box.add_child(_spinner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 12)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_theme_stylebox_override("fill", UITheme.box(UITheme.ACCENT, 6))
	_bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.08), 6))
	row.add_child(_bar)
	_percent = _label("0%", 18, UITheme.TEXT)
	_percent.custom_minimum_size = Vector2(56, 0)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_percent)
	box.add_child(row)
	var loading := _label("Loading...", 16, UITheme.TEXT_DIM)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(loading)
	_tip = Label.new()
	_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip.offset_top = -80
	_tip.custom_minimum_size = Vector2(800, 0)
	_tip.offset_left = -400
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 18)
	_tip.add_theme_color_override("font_color", Color(0.98, 0.86, 0.5))
	_root.add_child(_tip)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

class Spinner extends Control:
	var angle := 0.0
	func _process(delta: float) -> void:
		angle += delta * 5.0
		queue_redraw()
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		draw_arc(c, 22.0, 0, TAU, 48, Color(1, 1, 1, 0.08), 5.0, true)
		draw_arc(c, 22.0, angle, angle + PI * 0.6, 24, UITheme.ACCENT, 5.0, true)

func _process(delta: float) -> void:
	if not _root.visible:
		return
	# Ease the bar towards the real progress so it never jumps backwards or snaps.
	_shown_progress = move_toward(_shown_progress, _target_progress, delta * 1.5)
	_bar.value = _shown_progress
	_percent.text = "%d%%" % int(round(_shown_progress * 100.0))

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func change_scene(path: String) -> void:
	if busy:
		return
	busy = true
	_tip.text = tr(TIPS.pick_random())
	_shown_progress = 0.0
	_target_progress = 0.0
	_root.modulate.a = 0.0
	_root.visible = true
	var fade_in := create_tween()
	fade_in.tween_property(_root, "modulate:a", 1.0, 0.2)
	await fade_in.finished
	await _frames(2)   # make sure the loading screen is on screen before the heavy work

	# 1. Load the scene file (in the background where threads are available).
	ResourceLoader.load_threaded_request(path)
	var progress := []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Loader: failed to load %s" % path)
			busy = false
			_root.visible = false
			return
		_target_progress = 0.6 * float(progress[0]) if not progress.is_empty() else 0.0
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	_target_progress = 0.65
	await _frames(2)

	# 2. Build the scene (the city, traffic and UI are created in _ready) and swap it in.
	var tree := get_tree()
	tree.paused = false
	var old := tree.current_scene
	var scene := packed.instantiate()
	_target_progress = 0.8
	tree.root.add_child(scene)
	tree.current_scene = scene
	if old:
		old.queue_free()
	_target_progress = 0.9

	# 3. Let it run a moment behind the screen (first frames compile shaders), then reveal.
	var t := 0.0
	while t < SETTLE_TIME:
		await tree.process_frame
		t += get_process_delta_time()
	_target_progress = 1.0
	while _shown_progress < 0.999:
		await tree.process_frame
	var fade_out := create_tween()
	fade_out.tween_property(_root, "modulate:a", 0.0, 0.35)
	await fade_out.finished
	_root.visible = false
	busy = false
