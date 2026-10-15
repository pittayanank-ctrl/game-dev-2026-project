extends Node3D
## Traffic lights for the bigger intersections of the city grid (see city.gd). Junctions of two
## main roads (even road numbers) and the downtown ones have lights; the rest have none: traffic on
## the main road goes straight through and the side road gives way (see has_light / is_major).
## Each intersection runs a two-phase cycle: Z-axis traffic goes first, then X-axis traffic, with
## yellow and an all-red gap between. Intersections are offset from each other so the city doesn't
## flash in sync. Cars (traffic_manager.gd) and anything else can query light_state().

const City := preload("res://scripts/city.gd")

signal red_light_run(fine: int)   # the player entered an intersection on red

enum Light { GREEN, YELLOW, RED }

const GREEN_TIME := 7.0
const YELLOW_TIME := 2.0
const ALL_RED_TIME := 1.0     # red for each direction = the other direction's green + yellow + 2 x this
const HALF_CYCLE := GREEN_TIME + YELLOW_TIME + ALL_RED_TIME
const CYCLE := HALF_CYCLE * 2.0
const STOP_DIST := 8.0        # stop line distance from the intersection centre
const FINE_ENABLED := true     # traffic cameras: the player may be fined for running a red light
const CATCH_CHANCE := 0.35     # chance a camera catches a given red-light run
const FINE := 150             # THB
const FINE_COOLDOWN := 6.0    # seconds before the same intersection can fine again
const POLE_OFFSET := 6.8      # pole distance from the road centre line (just outside the road)

var player: Node3D
var _time := 0.0
var _last_player_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _fine_ready := {}   # Vector2i(i, j) -> time when it can fine again
var _approaches: Array[Dictionary] = []   # {i, j, z_axis, lamp, state}
var _mats := {}
const LAMP_COLORS := [Color(0.15, 1.0, 0.3), Color(1.0, 0.8, 0.1), Color(1.0, 0.15, 0.1)]   # by Light
# All poles/heads/lines/lamps are drawn with one MultiMesh per material (thousands of boxes, 4 draw calls).
var _parts := {}                  # material -> Array[Transform3D]
var _lamp_mm: MultiMesh
var _lamp_timer := 0.0

func _ready() -> void:
	_rng.randomize()
	player = get_node_or_null("../Motorcycle")
	for state in [Light.GREEN, Light.YELLOW, Light.RED]:
		var m := StandardMaterial3D.new()
		var col: Color = [Color(0.1, 1.0, 0.2), Color(1.0, 0.8, 0.1), Color(1.0, 0.1, 0.1)][state]
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.5
		_mats[state] = m
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.9)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # always bright, colour per instance
	lamp_mat.vertex_color_use_as_albedo = true
	lamp_mat.vertex_color_is_srgb = true
	for i in range(-City.GRID, City.GRID + 1):
		for j in range(-City.GRID, City.GRID + 1):
			_build_intersection(i, j, dark, white, lamp_mat)
	for mat in _parts:
		var mm := _make_multimesh(_parts[mat], mat == lamp_mat)
		if mat == lamp_mat:
			_lamp_mm = mm
			for k in _approaches.size():
				mm.set_instance_color(k, LAMP_COLORS[Light.RED])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

## True if intersection (i, j) has traffic lights.
static func has_light(i: int, j: int) -> bool:
	return (posmod(i, 2) == 0 and posmod(j, 2) == 0) or (absi(i) <= 1 and absi(j) <= 1)

## At a junction without lights: true if traffic moving along Z (z_axis) is on the main road.
## Z traffic drives on road line i, X traffic on road line j; even lines are main roads.
static func is_major(i: int, j: int, z_axis: bool) -> bool:
	var z_major := posmod(i, 2) == 0 or posmod(j, 2) != 0
	return z_major == z_axis

## State of the light for traffic moving along Z (z_axis = true) or X at intersection (i, j).
## Junctions without lights always report GREEN (cars there follow the give-way rule instead).
func light_state(i: int, j: int, z_axis: bool) -> int:
	if not has_light(i, j):
		return Light.GREEN
	var offset := fposmod(i * 7.0 + j * 13.0, CYCLE)
	var t := fposmod(_time + offset + (0.0 if z_axis else HALF_CYCLE), CYCLE)
	if t < GREEN_TIME:
		return Light.GREEN
	if t < GREEN_TIME + YELLOW_TIME:
		return Light.YELLOW
	return Light.RED

## Seconds of red left for traffic moving along Z (z_axis) or X at (i, j); 0 if it is not red.
## Pedestrians use this to decide whether they can cross before the cars get green.
func red_time_left(i: int, j: int, z_axis: bool) -> float:
	if not has_light(i, j):
		return 0.0
	var offset := fposmod(i * 7.0 + j * 13.0, CYCLE)
	var t := fposmod(_time + offset + (0.0 if z_axis else HALF_CYCLE), CYCLE)
	if t < GREEN_TIME + YELLOW_TIME:
		return 0.0
	return CYCLE - t

func _physics_process(delta: float) -> void:
	_time += delta
	_check_player()
	_lamp_timer -= delta
	if _lamp_timer > 0.0:
		return
	_lamp_timer = 0.2
	for a in _approaches:
		var s := light_state(a["i"], a["j"], a["z_axis"])
		if s != a["state"]:
			a["state"] = s
			_lamp_mm.set_instance_color(a["lamp"], LAMP_COLORS[s])

## Fines the player when they enter an intersection while the light for their direction is red.
func _check_player() -> void:
	if not FINE_ENABLED or player == null:
		return
	var p := player.global_position
	var i := roundi(p.x / City.PITCH)
	var j := roundi(p.z / City.PITCH)
	if absi(i) <= City.GRID and absi(j) <= City.GRID:
		var half := City.ROAD_WIDTH * 0.5
		var centre := Vector3(i * City.PITCH, 0, j * City.PITCH)
		var rel := p - centre
		var prev := _last_player_pos - centre
		var inside := absf(rel.x) < half and absf(rel.z) < half
		var was_inside := absf(prev.x) < half and absf(prev.z) < half
		if inside and not was_inside:
			var z_axis := absf(prev.z) >= half   # came in through the north or south side
			var key := Vector2i(i, j)
			if has_light(i, j) and light_state(i, j, z_axis) == Light.RED and _fine_ready.get(key, 0.0) <= _time:
				_fine_ready[key] = _time + FINE_COOLDOWN
				if _rng.randf() < CATCH_CHANCE:
					red_light_run.emit(FINE)
	_last_player_pos = p

## Queue a box for the MultiMesh of `mat`; returns its instance index.
func _box(size: Vector3, pos: Vector3, mat: Material) -> int:
	if not _parts.has(mat):
		_parts[mat] = [] as Array[Transform3D]
	_parts[mat].append(Transform3D(Basis.from_scale(size), pos))
	return _parts[mat].size() - 1

func _make_multimesh(transforms: Array, colored: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	return mm

func _build_intersection(i: int, j: int, dark: Material, white: Material, lamp_mat: Material) -> void:
	var c := Vector3(i * City.PITCH, 0, j * City.PITCH)
	if not has_light(i, j):
		_build_give_way(i, j, c, dark, white)
		return
	for z_axis in [true, false]:
		for sgn in [1, -1]:
			var d := Vector3(0, 0, sgn) if z_axis else Vector3(sgn, 0, 0)
			var left := Vector3.UP.cross(d)
			# Stop line across this approach's lane(s).
			var line_size := Vector3(6, 0.03, 0.4) if z_axis else Vector3(0.4, 0.03, 6)
			_box(line_size, c + left * 3.0 - d * STOP_DIST + Vector3(0, 0.06, 0), white)
			# Pole at the kerb on the driver's left, head facing the oncoming cars.
			var base := c + left * POLE_OFFSET - d * STOP_DIST
			_box(Vector3(0.2, 4.2, 0.2), base + Vector3(0, 2.1, 0), dark)
			var head_size := Vector3(0.5, 0.9, 0.4) if z_axis else Vector3(0.4, 0.9, 0.5)
			_box(head_size, base + Vector3(0, 4.2, 0), dark)
			var lamp_size := Vector3(0.36, 0.36, 0.06) if z_axis else Vector3(0.06, 0.36, 0.36)
			var lamp := _box(lamp_size, base + Vector3(0, 4.2, 0) - d * 0.22, lamp_mat)
			_approaches.append({"i": i, "j": j, "z_axis": z_axis, "lamp": lamp, "state": Light.RED})

## Junction without lights: dashed give-way lines and a small sign on the side-road approaches.
func _build_give_way(i: int, j: int, c: Vector3, dark: Material, white: Material) -> void:
	if not _mats.has("sign"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.1, 0.1)
		_mats["sign"] = m
	for z_axis in [true, false]:
		if is_major(i, j, z_axis):
			continue
		for sgn in [1, -1]:
			var d := Vector3(0, 0, sgn) if z_axis else Vector3(sgn, 0, 0)
			var left := Vector3.UP.cross(d)
			for k in 4:
				var dash := Vector3(0.9, 0.03, 0.4) if z_axis else Vector3(0.4, 0.03, 0.9)
				_box(dash, c + left * (0.9 + k * 1.5) - d * STOP_DIST + Vector3(0, 0.06, 0), white)
			var base := c + left * POLE_OFFSET - d * STOP_DIST
			_box(Vector3(0.1, 2.4, 0.1), base + Vector3(0, 1.2, 0), dark)
			var plate := Vector3(0.7, 0.7, 0.05) if z_axis else Vector3(0.05, 0.7, 0.7)
			_box(plate, base + Vector3(0, 2.4, 0) - d * 0.06, _mats["sign"])
			var inner := Vector3(0.45, 0.45, 0.05) if z_axis else Vector3(0.05, 0.45, 0.45)
			_box(inner, base + Vector3(0, 2.4, 0) - d * 0.09, white)
