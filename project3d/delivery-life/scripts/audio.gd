extends Node
## Autoload "Audio": background music and sound effects.
##
## Music: `play_music("menu" | "ride" | "race")`. A playlist shuffles its tracks and cross-fades to
## the next one when a track ends; switching playlists cross-fades too. `duck(true)` lowers the
## music (cutscenes).
## Effects: `play("coins")` plays assets/audio/sfx/coins.ogg (or a random coins_N variant).
## Every button in the game clicks automatically (and ticks softly on hover).
## Music and effects have their own buses ("Music", "SFX") so they get their own volume sliders;
## the bike engine also plays on "SFX".

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const PLAYLISTS := {
	"menu": ["menu_a_cup_of_tea"],
	"ride": ["ride_florist", "ride_cat_caffe", "ride_countryside", "ride_bartender", "ride_morning_rain", "menu_a_cup_of_tea"],
	"race": ["race_stage1"],
}
const MUSIC_DB := -9.0
const DUCK_DB := -9.0               # extra music reduction while ducked
const FADE_TIME := 2.0
const VOICES := 10                   # effects that can play at the same time

var _sfx := {}                       # name -> Array[AudioStream] (variants)
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: Array[AudioStreamPlayer] = []   # two players for cross-fading
var _active := 0
var _playlist := ""
var _queue: Array = []
var _ducked := false
var _rng := RandomNumberGenerator.new()
var _hover_cooldown := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # UI sounds and music keep playing while paused
	_rng.randomize()
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		m.finished.connect(_on_music_finished.bind(i))
		add_child(m)
		_music.append(m)
	get_tree().node_added.connect(_on_node_added)
	apply_volumes()

## Bus volumes from Settings (0..1 each).
func apply_volumes() -> void:
	for pair in [["Music", Settings.music_volume], ["SFX", Settings.sfx_volume]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(pair[1], 0.0001)))
			AudioServer.set_bus_mute(i, pair[1] <= 0.001)

# ------------------------------------------------------------------ effects

func _streams(name: String) -> Array:
	if not _sfx.has(name):
		var list: Array = []
		var single := SFX_DIR + name + ".ogg"
		if ResourceLoader.exists(single):
			list.append(load(single))
		for n in range(1, 10):
			var variant := "%s%s_%d.ogg" % [SFX_DIR, name, n]
			if ResourceLoader.exists(variant):
				list.append(load(variant))
		_sfx[name] = list
	return _sfx[name]

## Play an effect. `volume_db` adds to its level; pitch is varied a little so repeats sound natural.
func play(name: String, volume_db := 0.0, pitch_jitter := 0.04) -> void:
	var list := _streams(name)
	if list.is_empty():
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = list[_rng.randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()

# Every Button gets a click (and a soft hover tick) without touching the UI code.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(func(): play("click", -4.0))
		node.mouse_entered.connect(_on_hover.bind(node))

func _on_hover(button: BaseButton) -> void:
	if button.disabled or _hover_cooldown > 0.0:
		return
	_hover_cooldown = 0.06
	play("hover", -14.0)

# ------------------------------------------------------------------ music

func play_music(playlist: String) -> void:
	if playlist == _playlist:
		return
	_playlist = playlist
	_queue.clear()
	_next_track()

func _next_track() -> void:
	if _queue.is_empty():
		_queue = PLAYLISTS.get(_playlist, []).duplicate()
		_queue.shuffle()
	if _queue.is_empty():
		return
	var path: String = MUSIC_DIR + _queue.pop_front() + ".ogg"
	if not ResourceLoader.exists(path):
		return
	# Cross-fade: the new track starts on the idle player, the old one fades out.
	var old := _music[_active]
	_active = 1 - _active
	var new := _music[_active]
	var stream: AudioStream = load(path)
	if "loop" in stream:
		stream.loop = _playlist != "ride"   # one-track playlists loop; the ride playlist moves on
	new.stream = stream
	new.volume_db = -60.0
	new.play()
	var t := create_tween().set_parallel()
	t.tween_property(new, "volume_db", _music_level(), FADE_TIME)
	t.tween_property(old, "volume_db", -80.0, FADE_TIME)
	t.chain().tween_callback(old.stop)

func _on_music_finished(index: int) -> void:
	if index == _active:
		_next_track()

func _music_level() -> float:
	return MUSIC_DB + (DUCK_DB if _ducked else 0.0)

## Lower the music while something else should be heard (cutscene dialogue).
func duck(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	create_tween().tween_property(_music[_active], "volume_db", _music_level(), 0.6)

func stop_music() -> void:
	_playlist = ""
	for m in _music:
		create_tween().tween_property(m, "volume_db", -80.0, 1.0)

func _process(delta: float) -> void:
	_hover_cooldown -= delta
