extends Node
## Engine sound for the player's bike. Every bike model has its own folder of sounds:
##
##   assets/audio/motorcycles/<model>/idle.ogg    engine idling (loop)
##   assets/audio/motorcycles/<model>/low.ogg     low / mid revs (loop)
##   assets/audio/motorcycles/<model>/high.ogg    high revs (loop)
##   assets/audio/motorcycles/<model>/rev.ogg     throttle held against the brake (loop)
##   assets/audio/motorcycles/<model>/coast.ogg   throttle released while rolling (played once, or
##                                                looped while rolling for folders in COAST_LOOP)
##   assets/audio/motorcycles/<model>/start.ogg   engine start (played once)
##   assets/audio/motorcycles/<model>/horn.ogg    horn (H key)
##
## Every file is optional and may be .ogg, .wav or .mp3. A missing drive loop falls back to the
## next one (high -> low -> idle). Bikes listed in SHARE use another bike's folder (same engine).
## A sound found in none of those comes from .../default/, and then from the PCX (FALLBACK).
## The drive loops are cross-faded and pitched by a simulated RPM: scooters (CVT) hold their revs
## while accelerating and drop to near idle when coasting. Models listed in GEARS rev up and drop
## at every simulated shift. The bike calls crank() when the rider starts the engine, and passes
## `running` = false while the engine is off (silence).

const ROOT := "res://assets/audio/motorcycles/"
const EXTENSIONS := ["ogg", "wav", "mp3"]
# Models whose revs should rise and drop through simulated gears (model -> gear count). The Wave
# 125 recordings already contain their own gear changes, so it is left out on purpose.
const GEARS := {}
# Where a loop restarts (seconds), for clips that begin with a run-up before the steady part.
# Keyed by the folder the file came from.
const LOOP_START := {"pcx": {"low": 2.0}, "giorno": {"low": 9.0}}
# Bikes that share another bike's sound folder (same engine).
const SHARE := {"forza350": "giorno"}
const VOLUME_DB := -4.0
# Pitch of each loop at 0 and full revs.
const PITCH := {"idle": Vector2(0.95, 1.35), "low": Vector2(0.6, 1.08), "high": Vector2(0.88, 1.15), "rev": Vector2(1.0, 1.0)}
# Per-folder pitch ranges replacing PITCH (recordings that already change pitch on their own).
const PITCH_OVERRIDE := {"wave125": {"idle": Vector2(0.95, 1.2), "low": Vector2(0.9, 1.12), "high": Vector2(0.95, 1.15)}}
# Folders whose coast.ogg is a steady engine-braking sound that loops while rolling; elsewhere it
# is a one-shot "coming off the gas" (PCX, Giorno).
const COAST_LOOP := []
# Bike models (not folders) that play no coast sound: letting go of the throttle goes straight to
# idle. The Forza shares the Giorno's folder but keeps its coast sound.
const NO_COAST := ["giorno"]
# Extra volume (dB) for a bike model's engine sounds (loops and coast), e.g. a quieter old scooter.
const MODEL_GAIN_DB := {"oldscooter": -6.0}
# Drive revs follow the road speed: at (speed / top speed) = HIGH_FROM the "high" loop starts to
# fade in, and it has fully taken over at HIGH_FULL. Below that the "low" loop is heard.
const HIGH_FROM := 0.6
const HIGH_FULL := 0.85
const RPM_RISE := 5.0                # how fast the revs climb / fall (per second)
const RPM_FALL := 4.0
# Folders whose low.ogg is a full acceleration recording: it plays once from the start while
# riding on the throttle (pausing when you let go) and, when it reaches its end, the "high"
# loop takes over. Coming to a stop resets it, so the next pull-away starts the clip again.
const LOW_ONCE := ["wave125"]
const LOOPS := ["idle", "low", "high", "rev", "coast"]
const FALLBACK := "pcx"

var model_id := ""
var rpm := 0.0                       # 0 = idle, 1 = red line
var _loops := {}                     # loop name -> AudioStreamPlayer
var _start: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _coast: AudioStreamPlayer
var _rev_mix := 0.0                  # 0..1 how much of the brake+throttle rev is heard
var _coast_mix := 0.0                # 0..1 how much of the coasting loop is heard
var _prev_gas := 0.0
var _folder := {}                    # sound name -> folder it was loaded from
var _low_once := false               # current bike uses LOW_ONCE
var _low_started := false            # LOW_ONCE clip has been started (may be paused)
var _low_done := false               # LOW_ONCE clip reached its end: "high" from now on
var _high_mix := 0.0                 # LOW_ONCE cross-fade from low to high
var _off_mix := 0.0                  # 0..1 off the throttle: the drive loops hand over to idle

func _ready() -> void:
	for layer in LOOPS:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = -80.0
		p.finished.connect(_on_loop_finished.bind(layer))
		add_child(p)
		_loops[layer] = p
	_start = _one_shot(0.0)
	_horn = _one_shot(2.0)
	_coast = _one_shot(-2.0)

func _on_loop_finished(layer: String) -> void:
	if layer == "low" and _low_once:
		_low_done = true          # the acceleration clip is over: switch to "high"
		return
	_loops[layer].play(_loop_start(layer))   # WAV/MP3 without a loop flag: restart

func _one_shot(extra_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.volume_db = VOLUME_DB + extra_db
	add_child(p)
	return p

func _loop_start(layer: String) -> float:
	return LOOP_START.get(_folder.get(layer, ""), {}).get(layer, 0.0)

## Load the sounds of a bike model (e.g. "pcx").
func set_model(id: String) -> void:
	if id == model_id:
		return
	model_id = id
	var idle: AudioStream = _find(id, "idle")
	var low: AudioStream = _find(id, "low")
	var high: AudioStream = _find(id, "high")
	if low == null:
		low = idle
		_folder["low"] = _folder.get("idle", "")
	if high == null:
		high = low
		_folder["high"] = _folder.get("low", "")
	if idle == null:
		idle = low
		_folder["idle"] = _folder.get("low", "")
	# A long coast clip loops while rolling; a short one is a one-shot "coming off the gas".
	var coast: AudioStream = null if id in NO_COAST else _find(id, "coast")
	var coast_loop: AudioStream = coast if coast and _folder.get("coast", "") in COAST_LOOP else null
	_coast.stream = null if coast_loop else coast
	for pair in [["idle", idle], ["low", low], ["high", high], ["rev", _find(id, "rev")], ["coast", coast_loop]]:
		var p: AudioStreamPlayer = _loops[pair[0]]
		p.stop()
		p.stream_paused = false
		p.stream = pair[1]
		if pair[0] == "low":
			_low_once = p.stream != null and _folder.get("low", "") in LOW_ONCE
			_low_started = false
			_low_done = false
			_high_mix = 0.0
			if _low_once:
				if "loop" in p.stream:
					p.stream.loop = false
				continue   # started by update() when the rider pulls away
		if p.stream:
			# Seamless looping for OGG/MP3 (from the loop start point, if the clip has a run-up).
			if "loop" in p.stream:
				p.stream.loop = true
			if "loop_offset" in p.stream:
				p.stream.loop_offset = _loop_start(pair[0])
			p.play(_loop_start(pair[0]))
	_start.stream = _find(id, "start")
	_horn.stream = _find(id, "horn")
	rpm = 0.0

## A sound file for this model (any supported format), else the default folder's, else the
## fallback bike's, else null. Remembers which folder it came from (for LOOP_START).
func _find(id: String, sound: String) -> AudioStream:
	_folder.erase(sound)
	for folder in [id, SHARE.get(id, id), "default", FALLBACK]:
		for ext in EXTENSIONS:
			var path := "%s%s/%s.%s" % [ROOT, folder, sound, ext]
			if ResourceLoader.exists(path):
				_folder[sound] = folder
				return load(path) as AudioStream
	return null

func _pitch_range(layer: String) -> Vector2:
	return PITCH_OVERRIDE.get(_folder.get(layer, ""), {}).get(layer, PITCH.get(layer, Vector2.ONE))

## Engine start sound; returns how long it lasts (the bike waits that long before it runs).
func crank() -> float:
	if _start.stream == null:
		return 0.5
	_start.play()
	return clampf(_start.stream.get_length(), 0.3, 2.0)

func horn() -> void:
	if _horn.stream and not _horn.playing:
		_horn.play()

## Called every physics frame by the bike. `gas` / `brake` are the raw inputs (0..1).
func update(delta: float, speed: float, max_speed: float, gas: float, brake: float, running: bool) -> void:
	var has_fuel := running   # engine off (or out of fuel): everything is silent
	var ratio := clampf(absf(speed) / maxf(max_speed, 0.1), 0.0, 1.0)
	gas = clampf(gas, 0.0, 1.0)
	var revving := gas > 0.1 and brake > 0.1 and has_fuel
	var target := 0.0
	var gears: int = GEARS.get(model_id, 0)
	if not has_fuel:
		target = 0.0
	elif revving:
		target = 0.9
	elif gas == 0.0:
		target = 0.1 + ratio * 0.25          # rolling off the throttle: revs fall towards idle
	elif gears > 0:
		# Revs climb through each gear and drop at the shift.
		var g := minf(ratio * gears, gears - 0.001)
		target = 0.3 + (g - floorf(g)) * 0.65 + gas * 0.05
	else:
		# Revs rise with the road speed (plus a little for the throttle), so the "low" loop is heard
		# while pulling away and "high" only near the top. rpm 0.65 = HIGH_FROM, 0.9 = HIGH_FULL.
		var k := 0.0
		if ratio < HIGH_FROM:
			k = lerpf(0.4, 0.65, ratio / HIGH_FROM)
		else:
			k = lerpf(0.65, 0.9, clampf((ratio - HIGH_FROM) / (HIGH_FULL - HIGH_FROM), 0.0, 1.0)) + maxf(ratio - HIGH_FULL, 0.0) * 0.4
		target = k + gas * 0.03
	rpm = lerpf(rpm, clampf(target, 0.0, 1.0), clampf((RPM_RISE if target > rpm else RPM_FALL) * delta, 0.0, 1.0))

	# Let go of the throttle while still rolling: the "coming off the gas" sound.
	if _prev_gas > 0.3 and gas == 0.0 and absf(speed) > 3.0 and has_fuel and _coast.stream:
		_coast.pitch_scale = lerpf(0.9, 1.15, ratio)
		_coast.volume_db = VOLUME_DB - 2.0 + MODEL_GAIN_DB.get(model_id, 0.0)
		_coast.play()
	_prev_gas = gas

	# Off the throttle the drive loops cross-fade straight into idle (no gap while the revs fall);
	# idle's pitch follows the falling revs, so it sounds like the engine winding down.
	_off_mix = move_toward(_off_mix, 1.0 if gas == 0.0 and not revving else 0.0, delta * 8.0)
	var has_rev: bool = _loops["rev"].stream != null
	_rev_mix = move_toward(_rev_mix, 1.0 if revving and has_rev else 0.0, delta * 6.0)
	var coasting := gas == 0.0 and absf(speed) > 3.0 and has_fuel and _loops["coast"].stream != null
	_coast_mix = move_toward(_coast_mix, clampf(absf(speed) / 8.0, 0.0, 1.0) if coasting else 0.0, delta * 4.0)
	# Cross-fade the drive loops: idle at low revs, "low" in the middle, "high" near the top.
	var w_idle := 1.0 - smoothstep(0.1, 0.35, rpm)
	var w_high := smoothstep(0.65, 0.9, rpm)
	var w_low := clampf(1.0 - w_idle - w_high, 0.0, 1.0)
	if _low_once:
		_update_low_once(delta, speed, gas, revving, has_fuel)
		w_low = (1.0 - w_idle) * (1.0 - _high_mix)
		w_high = (1.0 - w_idle) * _high_mix
	w_idle = lerpf(w_idle, 1.0, _off_mix)
	w_low *= 1.0 - _off_mix
	w_high *= 1.0 - _off_mix
	var drive := clampf(1.0 - _rev_mix - _coast_mix, 0.0, 1.0)
	var load_gain := 0.7 + 0.3 * gas      # louder under throttle
	var weights := {"idle": w_idle * drive, "low": w_low * drive * load_gain,
		"high": w_high * drive * load_gain, "rev": _rev_mix, "coast": _coast_mix}
	for layer in LOOPS:
		var p: AudioStreamPlayer = _loops[layer]
		if p.stream == null:
			continue
		var w: float = weights[layer]
		p.volume_db = VOLUME_DB + MODEL_GAIN_DB.get(model_id, 0.0) + linear_to_db(maxf(w, 0.0001)) if has_fuel else -80.0
		if layer == "coast":
			p.pitch_scale = lerpf(0.85, 1.1, ratio)   # follows the road speed, not the revs
			continue
		if layer == "low" and _low_once:
			p.pitch_scale = 1.0   # the recording already has its own revs and gear changes
			continue
		var range := _pitch_range(layer)
		p.pitch_scale = lerpf(range.x, range.y, rpm)

## LOW_ONCE: run the acceleration clip while on the throttle, then hand over to "high".
func _update_low_once(delta: float, speed: float, gas: float, revving: bool, has_fuel: bool) -> void:
	var p: AudioStreamPlayer = _loops["low"]
	if absf(speed) < 1.5 and gas == 0.0:
		# Stopped: the next pull-away plays the clip from the start again.
		p.stop()
		p.stream_paused = false
		_low_started = false
		_low_done = false
	var pulling := gas > 0.1 and not revving and has_fuel
	if pulling and not _low_done:
		if not _low_started:
			p.play(0.0)
			_low_started = true
		p.stream_paused = false
	elif _low_started and not _low_done and _off_mix > 0.98:
		p.stream_paused = true   # off the throttle (after the fade to idle): hold the clip there
	_high_mix = move_toward(_high_mix, 1.0 if _low_done else 0.0, delta * 3.0)
