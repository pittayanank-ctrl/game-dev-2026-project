extends Node
## Time of day and weather. Moves the sun, tints the sky and ambient light, switches street lamps
## and headlights on at night, starts/stops rain (slippery roads), and ends the day at midnight.

signal weather_changed(raining: bool)
signal day_ended

const DAY_START_HOUR := 6.0
const DAY_END_HOUR := 24.0
const DAY_LENGTH := 600.0              # real seconds from 06:00 to 24:00
const RAIN_START_CHANCE := 0.12        # per in-game hour, when dry
const RAIN_STOP_CHANCE := 0.35         # per in-game hour, when raining
const RAIN_GRIP := 0.72                # bike grip multiplier on wet roads

const SKY_DAY := Color(0.53, 0.75, 0.95)
const SKY_NIGHT := Color(0.03, 0.04, 0.1)
const SKY_TWILIGHT := Color(0.95, 0.55, 0.35)
const SKY_RAIN := Color(0.45, 0.48, 0.52)

var hour := DAY_START_HOUR
var raining := false
var night := false

var _sun: DirectionalLight3D
var _env: Environment
var _rain: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _last_hour := -1
var _ended := false

func _ready() -> void:
	_rng.randomize()
	_sun = get_node("../Sun")
	_env = get_node("../WorldEnvironment").environment
	_build_rain()
	_apply_graphics()
	Settings.graphics_changed.connect(_apply_graphics)
	_set_night(false, true)
	_apply()

func _process(delta: float) -> void:
	if not _ended:
		hour += delta * (DAY_END_HOUR - DAY_START_HOUR) / DAY_LENGTH
		if hour >= DAY_END_HOUR:
			hour = DAY_END_HOUR
			_ended = true
			day_ended.emit()
		if int(hour) != _last_hour:
			_last_hour = int(hour)
			_roll_weather()
	_apply()
	var cam := get_viewport().get_camera_3d()
	if cam and _rain.emitting:
		_rain.global_position = cam.global_position + Vector3(0, 12, 0)

## Shadows by quality: off (low), 2 splits within 70 m (medium) or 110 m (high).
## The default 4-split shadows redraw the whole city 4 extra times, so we never use them.
func _apply_graphics() -> void:
	_sun.shadow_enabled = Settings.graphics > 0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 110.0 if Settings.graphics == 2 else 70.0
	_rain.amount = [600, 1200, 1600][Settings.graphics]

func start_new_day() -> void:
	hour = DAY_START_HOUR
	_ended = false
	_last_hour = -1
	_set_rain(_rng.randf() < 0.2)

func time_text() -> String:
	var h := int(hour) % 24
	var m := int((hour - floorf(hour)) * 60.0)
	return "%02d:%02d" % [h, m]

func grip() -> float:
	return RAIN_GRIP if raining else 1.0

# ------------------------------------------------------------------ internals

func _roll_weather() -> void:
	if raining and _rng.randf() < RAIN_STOP_CHANCE:
		_set_rain(false)
	elif not raining and _rng.randf() < RAIN_START_CHANCE:
		_set_rain(true)

func _set_rain(on: bool) -> void:
	if on == raining:
		return
	raining = on
	_rain.emitting = on
	_env.fog_enabled = on
	var bike := get_node_or_null("../Motorcycle")
	if bike:
		bike.grip_factor = grip()
	weather_changed.emit(on)

## Sun height in degrees: 0 at 06:00 and 18:00, highest at noon, negative at night.
func _sun_elevation() -> float:
	return sin((hour - 6.0) / 12.0 * PI) * 70.0

func _apply() -> void:
	var elev := _sun_elevation()
	var daylight := smoothstep(-6.0, 14.0, elev)                 # 0 = night, 1 = full day
	var twilight := clampf(1.0 - absf(daylight * 2.0 - 1.0), 0.0, 1.0) * 0.6
	var sky := SKY_NIGHT.lerp(SKY_DAY, daylight).lerp(SKY_TWILIGHT, twilight)
	if raining:
		sky = sky.lerp(SKY_RAIN * maxf(daylight, 0.25), 0.7)
	_env.background_color = sky
	_env.fog_light_color = sky
	_env.fog_density = 0.012
	_env.ambient_light_color = Color(0.55, 0.6, 0.9).lerp(Color.WHITE, daylight)
	_env.ambient_light_energy = lerpf(0.22, 0.5, daylight) * (0.8 if raining else 1.0)

	if elev > 0.0:
		_sun.rotation_degrees = Vector3(-maxf(elev, 4.0), -90.0 + (hour - 6.0) / 12.0 * 180.0, 0)
		_sun.light_color = Color(1.0, 0.75, 0.5).lerp(Color.WHITE, clampf(elev / 30.0, 0.0, 1.0))
	else:
		# Moonlight from high up so the city stays readable at night.
		_sun.rotation_degrees = Vector3(-55, 30, 0)
		_sun.light_color = Color(0.55, 0.65, 1.0)
	_sun.light_energy = lerpf(0.18, 1.0, daylight) * (0.5 if raining else 1.0)

	var is_night := daylight < 0.35
	if is_night != night:
		_set_night(is_night)

func _set_night(on: bool, force := false) -> void:
	if on == night and not force:
		return
	night = on
	for path in ["../City", "../TrafficManager", "../Motorcycle"]:
		var n := get_node_or_null(path)
		if n and n.has_method("set_night"):
			n.set_night(on)

func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 1600
	_rain.lifetime = 0.9
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(28, 1, 28)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 26.0
	_rain.gravity = Vector3(0, -9.8, 0)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.45, 0.02)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	drop.material = mat
	_rain.mesh = drop
	_rain.emitting = false
	add_child(_rain)
