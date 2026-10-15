extends Node3D
## Simple AI traffic: box cars drive the grid roads in lanes (left-hand traffic), follow the car in
## front, obey the traffic lights (or give way to the main road where a junction has none), yield
## to the player's bike and occasionally turn left.
## A car is described by (axis, road, sign, s): it travels along Z (or X) on road line `road`
## (position on the other axis = road * PITCH), in direction `sign`, at coordinate `s`.
## There are several vehicle types, and the number of cars on the road follows the time of day
## (rush hours are busy, nights are quiet).

const City := preload("res://scripts/city.gd")
const Lights := preload("res://scripts/traffic_lights.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const PITCH := City.PITCH
const GRID := City.GRID
const EXTENT := City.GRID * City.PITCH + City.PITCH * 0.5   # roads end here
const LANE := 3.0                 # lane centre offset from the road centre line
const CAR_LEN := 4.2              # typical car length (used by other systems as a default)
const STOP_LINE := 8.0            # stop line distance from the intersection centre
const ACCEL := 3.5
const BRAKE := 8.0
const COMFORT_DECEL := 6.0        # deceleration used to plan stops
const TURN_SPEED := 6.0
const POOL_SIZE := 90             # cars created; how many drive depends on the hour and graphics setting
const MAX_SPAWNS_PER_TICK := 2
# Vehicle types: size (width, height, length), speed range, how often they appear.
const KINDS := {
	"sedan": {"size": Vector3(1.8, 1.5, 4.2), "speed": Vector2(9, 14), "weight": 40},
	"hatch": {"size": Vector3(1.7, 1.5, 3.6), "speed": Vector2(9, 13), "weight": 18},
	"suv": {"size": Vector3(1.95, 1.9, 4.6), "speed": Vector2(9, 13), "weight": 14},
	"van": {"size": Vector3(1.95, 2.1, 4.8), "speed": Vector2(8, 12), "weight": 8},
	"taxi": {"size": Vector3(1.8, 1.6, 4.4), "speed": Vector2(10, 14), "weight": 9},
	"bus": {"size": Vector3(2.5, 3.0, 10.0), "speed": Vector2(7, 10), "weight": 3},
	"tuktuk": {"size": Vector3(1.4, 1.9, 2.9), "speed": Vector2(7, 10), "weight": 8},
}
const TURN_CHANCE := 0.3
const NONE := 1 << 30

class Car:
	var node: AnimatableBody3D
	var z_axis := true
	var road := 0
	var sign := 1
	var s := 0.0
	var speed := 0.0
	var max_speed := 10.0
	var kind := "sedan"
	var length := 4.2
	var width := 1.8
	var stop_center := 10.6   # where the car's centre stops before a junction (depends on length)
	var turning := false
	var waiting := false   # parked off-map until a free spot opens up
	var leader_gap := INF  # gap to the car in front in our lane (refreshed every tick)
	var arc: Array[Vector3] = []   # bezier control points: start, corner, end
	var arc_len := 1.0
	var arc_u := 0.0
	var dest_z_axis := true
	var dest_road := 0
	var dest_sign := 1
	var dest_s := 0.0

var player: Node3D
var lights: Node3D
var pedestrians: Node3D
var _headlight_mat: StandardMaterial3D
var _road_peds: Array[Vector3] = []   # pedestrians currently crossing a street (refreshed every tick)
var _turning: Array[Car] = []         # cars in the middle of a turn (refreshed every tick)
var _taillight_mat: StandardMaterial3D
var _st_body: SurfaceTool   # builders for the car being made
var _st_head: SurfaceTool
var _st_tail: SurfaceTool
var cars: Array[Car] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	player = get_node("../Motorcycle")
	lights = get_node("../TrafficLights")
	pedestrians = get_node_or_null("../Pedestrians")
	_headlight_mat = StandardMaterial3D.new()
	_headlight_mat.albedo_color = Color(0.95, 0.95, 0.85)
	_headlight_mat.emission_enabled = true
	_headlight_mat.emission = Color(1.0, 0.95, 0.8)
	_headlight_mat.emission_energy_multiplier = 0.0
	_taillight_mat = StandardMaterial3D.new()
	_taillight_mat.albedo_color = Color(0.6, 0.05, 0.05)
	_taillight_mat.emission_enabled = true
	_taillight_mat.emission = Color(1.0, 0.1, 0.1)
	_taillight_mat.emission_energy_multiplier = 0.0
	rng.randomize()
	var target := target_count()
	for n in POOL_SIZE:
		_spawn_car(n < target)

# ------------------------------------------------------------------ helpers

func _dir(c: Car) -> Vector3:
	return Vector3(0, 0, c.sign) if c.z_axis else Vector3(c.sign, 0, 0)

func _lane_pos(z_axis: bool, road: int, sign: int, s: float) -> Vector3:
	var d := Vector3(0, 0, sign) if z_axis else Vector3(sign, 0, 0)
	var p := Vector3(road * PITCH, 0, 0) if z_axis else Vector3(0, 0, road * PITCH)
	p += Vector3.UP.cross(d) * LANE
	if z_axis:
		p.z = s
	else:
		p.x = s
	return p

func _car_pos(c: Car) -> Vector3:
	return _lane_pos(c.z_axis, c.road, c.sign, c.s)

func _place(c: Car, pos: Vector3, dir: Vector3) -> void:
	c.node.global_position = pos
	c.node.rotation.y = atan2(-dir.x, -dir.z)   # car faces its own -Z

func _lane_is_free(z_axis: bool, road: int, sign: int, s: float, margin: float, except: Car = null) -> bool:
	for o in cars:
		if o == except or o.waiting:
			continue
		# A car mid-turn occupies the lane it is turning into.
		var o_z := o.dest_z_axis if o.turning else o.z_axis
		var o_road := o.dest_road if o.turning else o.road
		var o_sign := o.dest_sign if o.turning else o.sign
		var o_s := o.dest_s if o.turning else o.s
		if o_z == z_axis and o_road == road and o_sign == sign and absf(o_s - s) < margin:
			return false
	return true

# ------------------------------------------------------------------ spawning

func _pick_kind() -> String:
	var total := 0
	for k in KINDS:
		total += KINDS[k]["weight"]
	var roll := rng.randi_range(1, total)
	for k in KINDS:
		roll -= KINDS[k]["weight"]
		if roll <= 0:
			return k
	return "sedan"

## Add a box to the car being built: lights go to their own surfaces, everything else is merged
## into the body surface with its colour stored per vertex.
func _part(_body: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D, _shadow := true) -> void:
	if mat == _headlight_mat:
		MeshBuilder.add_box(_st_head, pos, size, Color.WHITE)
	elif mat == _taillight_mat:
		MeshBuilder.add_box(_st_tail, pos, size, Color.WHITE)
	else:
		MeshBuilder.add_box(_st_body, pos, size, mat.albedo_color)

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m

## Build the box model for a vehicle type. Cars face their own -Z.
func _build_car(c: Car) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false   # we move cars ourselves every physics frame
	_st_body = MeshBuilder.begin()
	_st_head = MeshBuilder.begin()
	_st_tail = MeshBuilder.begin()
	var size: Vector3 = KINDS[c.kind]["size"]
	var w := size.x
	var h := size.y
	var l := size.z
	var paint := _mat(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.5, 0.95)))
	var glass := _mat(Color(0.12, 0.16, 0.2))
	var dark := _mat(Color(0.12, 0.12, 0.13))
	match c.kind:
		"sedan", "taxi":
			if c.kind == "taxi":
				paint = _mat([Color("e8508f"), Color("37b24d"), Color("f2c230"), Color("2f7fe0")].pick_random())
			_part(body, Vector3(w, 0.8, l), Vector3(0, 0.7, 0), paint)
			_part(body, Vector3(w - 0.2, 0.6, l * 0.52), Vector3(0, 1.4, 0.2), glass)
			if c.kind == "taxi":
				_part(body, Vector3(0.7, 0.2, 0.35), Vector3(0, 1.8, 0.2), _mat(Color(0.95, 0.95, 0.9)), false)
		"hatch":
			_part(body, Vector3(w, 0.8, l), Vector3(0, 0.7, 0), paint)
			_part(body, Vector3(w - 0.15, 0.65, l * 0.58), Vector3(0, 1.42, 0.45), glass)
		"suv":
			_part(body, Vector3(w, 1.0, l), Vector3(0, 0.8, 0), paint)
			_part(body, Vector3(w - 0.1, 0.75, l * 0.66), Vector3(0, 1.67, 0.3), glass)
		"van":
			_part(body, Vector3(w, h - 0.3, l), Vector3(0, (h - 0.3) * 0.5 + 0.3, 0), paint)
			_part(body, Vector3(w + 0.02, 0.6, 1.0), Vector3(0, h - 0.6, -l * 0.5 + 0.4), glass)
		"bus":
			paint = _mat([Color("e8742a"), Color("2f6fd0"), Color("d33b3b")].pick_random())
			_part(body, Vector3(w, h - 0.35, l), Vector3(0, (h - 0.35) * 0.5 + 0.35, 0), paint)
			_part(body, Vector3(w + 0.03, 0.8, l - 0.6), Vector3(0, h - 0.95, 0), glass)
		"tuktuk":
			paint = _mat([Color("1f6fd1"), Color("2ba84a"), Color("e2a417")].pick_random())
			_part(body, Vector3(w, 0.55, l), Vector3(0, 0.55, 0), paint)
			_part(body, Vector3(w * 0.7, 0.7, 0.9), Vector3(0, 1.1, -l * 0.5 + 0.45), glass)
			_part(body, Vector3(w + 0.1, 0.1, l * 0.8), Vector3(0, h - 0.05, 0.15), paint)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_part(body, Vector3(0.06, h - 0.85, 0.06), Vector3(corner.x * (w * 0.5 - 0.05), (h - 0.85) * 0.5 + 0.8, corner.y * l * 0.38 + 0.15), dark, false)
	var lamp_y := 0.8 if c.kind != "tuktuk" else 0.65
	for side in [-w * 0.33, w * 0.33]:
		_part(body, Vector3(0.36, 0.18, 0.06), Vector3(side, lamp_y, -l * 0.5 - 0.02), _headlight_mat, false)
		_part(body, Vector3(0.36, 0.18, 0.06), Vector3(side, lamp_y, l * 0.5 + 0.02), _taillight_mat, false)
	var mesh := _st_body.commit()
	_st_head.commit(mesh)
	_st_tail.commit(mesh)
	mesh.surface_set_material(0, MeshBuilder.vertex_color_material())
	mesh.surface_set_material(1, _headlight_mat)
	mesh.surface_set_material(2, _taillight_mat)
	var model := MeshInstance3D.new()
	model.mesh = mesh
	body.add_child(model)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, l)
	shape.shape = box
	shape.position.y = h * 0.5
	body.add_child(shape)
	add_child(body)
	c.node = body

func _spawn_car(active: bool) -> void:
	var c := Car.new()
	c.kind = _pick_kind()
	var k: Dictionary = KINDS[c.kind]
	c.width = k["size"].x
	c.length = k["size"].z
	c.stop_center = STOP_LINE + 0.4 + c.length * 0.5
	c.max_speed = rng.randf_range(k["speed"].x, k["speed"].y)
	_build_car(c)
	cars.append(c)
	if active:
		_respawn(c, true)
	else:
		_park(c)

## How many cars should be driving right now: busy at rush hour, quiet at night.
func target_count() -> int:
	var density := 0.65
	var clock := get_node_or_null("../WorldClock")
	if clock:
		var h: float = clock.hour
		if (h >= 7.0 and h < 9.5) or (h >= 17.0 and h < 19.5):
			density = 1.0
		elif h >= 22.0 or h < 6.5:
			density = 0.35
	return int(POOL_SIZE * density * Settings.crowd_scale())

func _park(c: Car) -> void:
	c.waiting = true
	c.turning = false
	c.speed = 0.0
	c.node.global_position = Vector3(0, -50, 0)

## Put a car on a random lane. `anywhere` scatters it along the road (start of the game);
## otherwise it enters at the edge of the city.
func _respawn(c: Car, anywhere := false) -> void:
	c.turning = false
	for attempt in 30:
		c.z_axis = rng.randf() < 0.5
		c.road = rng.randi_range(-GRID, GRID)
		c.sign = 1 if rng.randf() < 0.5 else -1
		c.s = rng.randf_range(-EXTENT + 10.0, EXTENT - 10.0) if anywhere else -c.sign * (EXTENT - 2.0)
		var near_junction := absf(fposmod(c.s + PITCH * 0.5, PITCH) - PITCH * 0.5) < 14.0
		if anywhere and near_junction:
			continue
		if _lane_is_free(c.z_axis, c.road, c.sign, c.s, 10.0 + c.length, c) and _car_pos(c).distance_to(player.global_position) > 20.0:
			c.waiting = false
			c.speed = c.max_speed * 0.6
			_place(c, _car_pos(c), _dir(c))
			return
	# No free spot right now: park the car under the map and try again later.
	_park(c)

# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	_update_leaders()
	_turning.clear()
	for c in cars:
		if c.turning and not c.waiting:
			_turning.append(c)
	_road_peds.clear()
	if pedestrians:
		for p in pedestrians.peds:
			if p.mode == pedestrians.Mode.CROSS:
				_road_peds.append(p.node.global_position)
	# Bring parked cars back (a couple per tick) while there are fewer on the road than wanted.
	var active := 0
	for c in cars:
		if not c.waiting:
			active += 1
	var target := target_count()
	var spawns := 0
	for c in cars:
		if c.waiting:
			if active < target and spawns < MAX_SPAWNS_PER_TICK:
				spawns += 1
				_respawn(c)
				if not c.waiting:
					active += 1
		elif c.turning:
			_step_turn(c, delta)
		else:
			_step_straight(c, delta)

## Index of the next intersection whose stop line is ahead of the car (or NONE).
func _next_intersection(c: Car) -> int:
	var j: int
	if c.sign > 0:
		j = floori((c.s + c.stop_center) / PITCH) + 1
	else:
		j = ceili((c.s - c.stop_center) / PITCH) - 1
	if j < -GRID or j > GRID:
		return NONE
	return j

static func _lane_key(z_axis: bool, road: int, sign: int) -> int:
	return (1000 if z_axis else 0) + (road + 100) * 3 + (sign + 1)

## Group cars by lane, sort each lane along its axis and store every car's gap to the one ahead.
## A car mid-turn counts as already being in the lane it is turning into.
func _update_leaders() -> void:
	var lanes := {}
	for c in cars:
		c.leader_gap = INF
		if c.waiting:
			continue
		var key := _lane_key(c.dest_z_axis, c.dest_road, c.dest_sign) if c.turning else _lane_key(c.z_axis, c.road, c.sign)
		if not lanes.has(key):
			lanes[key] = []
		lanes[key].append(c)
	for key in lanes:
		var lane: Array = lanes[key]
		if lane.size() < 2:
			continue
		lane.sort_custom(func(a: Car, b: Car): return _lane_s(a) < _lane_s(b))
		var sign: int = lane[0].dest_sign if lane[0].turning else lane[0].sign
		for k in lane.size():
			var ahead := k + sign
			if ahead >= 0 and ahead < lane.size():
				lane[k].leader_gap = absf(_lane_s(lane[ahead]) - _lane_s(lane[k])) - (lane[ahead].length + lane[k].length) * 0.5

func _lane_s(c: Car) -> float:
	return c.dest_s if c.turning else c.s

func _gap_ahead(c: Car) -> float:
	var best := c.leader_gap
	# The player's bike counts as an obstacle when it is in our lane ahead of us.
	var d := _dir(c)
	var rel := player.global_position - _car_pos(c)
	var ahead := rel.dot(d)
	var lateral := absf(rel.dot(Vector3.UP.cross(d)))
	if ahead > 0.0 and ahead < 30.0 and lateral < c.width * 0.5 + 0.7:
		best = minf(best, ahead - c.length * 0.5 - 1.0)
	# Cars turning in front of us: the lane sort already counts them in the lane they turn into,
	# so the car behind them in the lane they are leaving has to see them here.
	for t in _turning:
		if t == c or t.z_axis != c.z_axis or t.road != c.road or t.sign != c.sign:
			continue   # only the lane the turning car is leaving
		var r: Vector3 = t.node.global_position - _car_pos(c)
		var a := r.dot(d)
		if a > 0.0 and a < 30.0 and absf(r.dot(Vector3.UP.cross(d))) < (c.width + t.width) * 0.5 + 0.3:
			best = minf(best, a - (c.length + t.length) * 0.5 - 1.0)
	# Pedestrians on the road in front of us (crossing).
	for pp in _road_peds:
		var r: Vector3 = pp - _car_pos(c)
		var a := r.dot(d)
		if a > 0.0 and a < 16.0 + c.length * 0.5 and absf(r.dot(Vector3.UP.cross(d))) < c.width * 0.5 + 1.5:
			best = minf(best, a - c.length * 0.5 - 1.4)
	return best

## Headlights and tail lights glow at night (called by the day/night controller).
func set_night(on: bool) -> void:
	_headlight_mat.emission_energy_multiplier = 3.0 if on else 0.0
	_taillight_mat.emission_energy_multiplier = 2.0 if on else 0.0

func _pedestrian_in_cone(pos: Vector3, dir: Vector3, reach: float, half_width: float) -> bool:
	var side := Vector3.UP.cross(dir)
	for pp in _road_peds:
		var r: Vector3 = pp - pos
		var a := r.dot(dir)
		if a > -1.0 and a < reach and absf(r.dot(side)) < half_width:
			return true
	return false

func _pedestrian_near(pos: Vector3, radius: float) -> bool:
	for pp in _road_peds:
		if pp.distance_to(pos) < radius:
			return true
	return false

func _speed_for_gap(gap: float) -> float:
	if gap == INF:
		return INF
	return sqrt(2.0 * COMFORT_DECEL * maxf(gap - 2.0, 0.0))

func _step_straight(c: Car, delta: float) -> void:
	var v_target := minf(c.max_speed, _speed_for_gap(_gap_ahead(c)))
	var j := _next_intersection(c)
	if j != NONE:
		var dist := (j * PITCH - c.sign * c.stop_center - c.s) * c.sign
		var i_idx := c.road if c.z_axis else j
		var j_idx := j if c.z_axis else c.road
		var must_stop := false
		if Lights.has_light(i_idx, j_idx):
			must_stop = lights.light_state(i_idx, j_idx, c.z_axis) != Lights.Light.GREEN
		elif dist > 0.0 and dist < 30.0:
			# No lights: the side road waits for a gap; the main road only stops for a car crossing.
			var major := Lights.is_major(i_idx, j_idx, c.z_axis)
			must_stop = _junction_busy(c, i_idx, j_idx, major)
		if dist > 0.0 and must_stop:
			# Brake for the stop line unless we're too close to stop comfortably (then run it).
			var needed := c.speed * c.speed / (2.0 * maxf(dist, 0.01))
			if needed <= COMFORT_DECEL * 1.5:
				v_target = minf(v_target, sqrt(2.0 * COMFORT_DECEL * maxf(dist - 0.3, 0.0)))
	c.speed = move_toward(c.speed, v_target, (ACCEL if v_target > c.speed else BRAKE) * delta)
	c.s += c.sign * c.speed * delta
	_place(c, _car_pos(c), _dir(c))

	if j != NONE and _next_intersection(c) != j:
		# Just crossed the stop line of intersection j: sometimes turn left.
		if rng.randf() < TURN_CHANCE:
			_try_turn(c, j)
	if absf(c.s) > EXTENT:
		# Leaving the city: come back at an edge, or park if there are too many cars for the hour.
		var active := 0
		for o in cars:
			if not o.waiting:
				active += 1
		if active > target_count():
			_park(c)
		else:
			_respawn(c)

## Junction (i, j) without lights: is it unsafe for `c` to enter? A car on the main road (`major`)
## only waits for cross traffic already in the junction; a side-road car also waits for main-road
## cars that are coming and for the player's bike.
func _junction_busy(c: Car, i: int, j: int, major: bool) -> bool:
	var centre := Vector3(i * PITCH, 0, j * PITCH)
	var box := City.ROAD_WIDTH * 0.5 + 1.5
	for o in cars:
		if o == c or o.waiting:
			continue
		var rel := _car_pos(o) - centre
		if o.turning or o.z_axis != c.z_axis:
			if absf(rel.x) < box and absf(rel.z) < box:
				return true
		if not major and not o.turning and o.z_axis != c.z_axis:
			# Main-road car still coming towards the junction?
			var o_road_ok := o.road == (i if o.z_axis else j)
			var ahead := ((j if o.z_axis else i) * PITCH - o.s) * o.sign
			if o_road_ok and ahead > -box and ahead < 45.0:
				return true
	if not major and player:
		var pr := player.global_position - centre
		if absf(pr.x) < box + 2.0 and absf(pr.z) < box + 2.0:
			return true
	return false

func _try_turn(c: Car, j: int) -> void:
	var d := _dir(c)
	var nd := Vector3.UP.cross(d)   # left of the direction of travel
	var centre := Vector3(c.road * PITCH, 0, j * PITCH) if c.z_axis else Vector3(j * PITCH, 0, c.road * PITCH)
	c.dest_z_axis = not c.z_axis
	c.dest_road = j   # the crossing road is line j for both axes
	c.dest_sign = roundi(nd.x + nd.z)   # nd is +/- one axis unit
	var exit_pos := centre + nd * (City.ROAD_WIDTH * 0.5)
	c.dest_s = exit_pos.x if c.dest_z_axis == false else exit_pos.z
	if c.kind == "bus" or not _lane_is_free(c.dest_z_axis, c.dest_road, c.dest_sign, c.dest_s, 12.0 + c.length, c):
		return
	var end := _lane_pos(c.dest_z_axis, c.dest_road, c.dest_sign, c.dest_s)
	var left_of_d := Vector3.UP.cross(d)
	var left_of_nd := Vector3.UP.cross(nd)
	var corner := centre + left_of_d * LANE + d * (LANE * left_of_nd.dot(d))
	var start := _car_pos(c)
	c.arc = [start, corner, end]
	c.arc_len = 0.0
	var prev := start
	for k in range(1, 9):
		var p := _bezier(c.arc, k / 8.0)
		c.arc_len += prev.distance_to(p)
		prev = p
	c.arc_u = 0.0
	c.turning = true

func _bezier(pts: Array[Vector3], u: float) -> Vector3:
	return pts[0].lerp(pts[1], u).lerp(pts[1].lerp(pts[2], u), u)

func _step_turn(c: Car, delta: float) -> void:
	# Wait in the junction while someone is walking across the street we are turning into.
	var here := _bezier(c.arc, c.arc_u)
	var heading := (_bezier(c.arc, minf(c.arc_u + 0.05, 1.0)) - here)
	heading = heading.normalized() if heading.length() > 0.001 else _dir(c)
	var exit_dir := (c.arc[2] - c.arc[1]).normalized()
	var blocked := _pedestrian_in_cone(here, heading, 7.0 + c.length * 0.5, c.width * 0.5 + 1.5)
	for check in [_bezier(c.arc, minf(c.arc_u + 0.3, 1.0)), _bezier(c.arc, minf(c.arc_u + 0.65, 1.0)), c.arc[2], c.arc[2] + exit_dir * 3.0]:
		blocked = blocked or _pedestrian_near(check, 3.0)
	if blocked:
		c.speed = move_toward(c.speed, 0.0, BRAKE * 1.5 * delta)
		return
	c.speed = move_toward(c.speed, TURN_SPEED, ACCEL * delta)
	c.arc_u = minf(c.arc_u + c.speed * delta / maxf(c.arc_len, 0.1), 1.0)
	var pos := _bezier(c.arc, c.arc_u)
	var ahead := _bezier(c.arc, minf(c.arc_u + 0.02, 1.0))
	var dir := (ahead - pos)
	if dir.length() < 0.001:
		dir = _dir(c)
	_place(c, pos, dir.normalized())
	if c.arc_u >= 1.0:
		c.z_axis = c.dest_z_axis
		c.road = c.dest_road
		c.sign = c.dest_sign
		c.s = c.dest_s
		c.turning = false
