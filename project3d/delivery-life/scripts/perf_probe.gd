extends Node
## Autoload "PerfProbe": dev helper. When the game is started with --perf (desktop: `-- --perf`)
## or with ?perf in the page URL (web), prints FPS and frame timings every 3 seconds.

var _enabled := false
var _timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep reporting (and start tests) during cutscenes/pauses
	_enabled = has_flag("perf") or has_flag("shot") or has_flag("autotest") or has_flag("verify=")
	# Web: `gfx=0/1/2` in the URL forces a graphics level (for comparing performance).
	if OS.has_feature("web"):
		var query = JavaScriptBridge.eval("window.location.search")
		if query is String and query.contains("gfx="):
			Settings.set_graphics(int(query.split("gfx=")[1].substr(0, 1)))
		if query is String and query.contains("lang=th"):
			Settings.set_language("th")
	set_process(_enabled)

## `autotest` / `verify=N`: run the smoke test (see smoke_test.gd) once the game scene is up.
func _start_smoke_test() -> void:
	var verify := -1
	if OS.has_feature("web"):
		var query = JavaScriptBridge.eval("window.location.search")
		if query is String and query.contains("verify="):
			verify = int(query.split("verify=")[1].split("&")[0])
	var test: Node = load("res://scripts/smoke_test.gd").new()
	add_child(test)
	test.run(get_tree().current_scene, verify)

## True if `name` was passed as a launch flag (desktop) or appears in the page URL (web).
static func has_flag(name: String) -> bool:
	if OS.has_feature("web"):
		var query = JavaScriptBridge.eval("window.location.search")
		return query is String and query.contains(name)
	return ("--" + name) in OS.get_cmdline_user_args()

## Web only: `off=A,B` in the URL disables those nodes of the game scene (to find what is slow).
func _disable_from_url() -> void:
	if not OS.has_feature("web"):
		return
	var query = JavaScriptBridge.eval("window.location.search")
	if not (query is String) or not query.contains("off="):
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.has_node("TrafficManager"):
		return
	var names: String = query.split("off=")[1].split("&")[0]
	for n in names.split(","):
		var node := scene.get_node_or_null(n)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is CanvasLayer or node is Node3D:
				node.visible = false
	print("PERF disabled: ", names)

## Web: `shot` in the URL prints one in-game screenshot (half size, base64 PNG) to the console.
func _console_screenshot() -> void:
	var f: Font = UITheme.font
	print("FONT name=%s has_thai=%s class=%s text_server=%s" % [f.get_font_name(), f.has_char(0x0E01), f.get_class(), TextServerManager.get_primary_interface().get_name()])
	var labels := get_tree().current_scene.find_children("*", "Label", true, false)
	if not labels.is_empty():
		var lf: Font = labels[0].get_theme_font("font")
		print("FONT label uses=%s (%s) root_theme=%s fallbacks=%d" % [lf.get_font_name(), lf.get_class(), get_tree().root.theme != null, lf.fallbacks.size()])
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var n := ceili(b64.length() / 4000.0)
	for k in n:
		print("SHOT %d/%d %s" % [k + 1, n, b64.substr(k * 4000, 4000)])

var _shot_done := false
var _done_disable := false
func _process(delta: float) -> void:
	if not _done_disable and get_tree().current_scene and get_tree().current_scene.has_node("TrafficManager"):
		_done_disable = true
		_disable_from_url.call_deferred()
		if has_flag("autotest") or has_flag("verify="):
			_start_smoke_test.call_deferred()
	if not _shot_done and OS.has_feature("web") and Engine.get_frames_drawn() > 600 and has_flag("shot"):
		_shot_done = true
		_console_screenshot()
	_timer += delta
	if _timer < 3.0:
		return
	_timer = 0.0
	print("PERF fps=%d process=%.1fms physics=%.1fms draw_calls=%d objects=%d" % [
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
