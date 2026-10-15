extends Node3D
## Pedestrians walk around city blocks on the sidewalks and sometimes cross the street at a
## crosswalk. They only start crossing when the cars on that street have a red light with enough
## time left to get across. Cars (traffic_manager.gd) stop for pedestrians in front of them.

const City := preload("res://scripts/city.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const COUNT := 60
const PATH_OFFSET := City.PITCH * 0.5 - City.SIDEWALK_OFFSET - 0.4   # walking line from block centre
const CROSS_CHANCE := 0.5
const CROSS_SPEED := 2.0          # people hurry across the road
const RED_GRACE := 1.5            # wait this long into the red so late cars have cleared the junction
const MAX_WAIT := 25.0            # give up waiting to cross after this many seconds
# Block corners in walking order (x, z signs relative to the block centre).
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

enum Mode { WALK, WAIT, CROSS }

class Ped:
	var node: Node3D
	var bi := 0                    # current block
	var bj := 0
	var corner := 0                # index into CORNERS we are walking to / standing at
	var step := 1                  # +1 or -1 around the block
	var mode := Mode.WALK
	var speed := 1.3
	var target := Vector3.ZERO
	var wait_time := 0.0
	var side := 0.0                # small sideways offset so people don't walk in a single file
	var blocked_time := 0.0        # how long a car has been in our way while crossing
	var detour: Array[Vector3] = [] # waypoints around a car that is waiting for us
	var bob := 0.0
	# pending crossing
	var cross_to := Vector3.ZERO
	var next_bi := 0
	var next_bj := 0
	var next_corner := 0
	var light_i := 0
	var light_j := 0
	var light_z := true

var peds: Array[Ped] = []
var lights: Node3D
var traffic: Node3D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	lights = get_node_or_null("../TrafficLights")
	traffic = get_node_or_null("../TrafficManager")
	for n in int(COUNT * Settings.crowd_scale()):
		var p := Ped.new()
		p.node = _make_body()
		p.bi = rng.randi_range(-City.GRID, City.GRID - 1)
		p.bj = rng.randi_range(-City.GRID, City.GRID - 1)
		p.corner = rng.randi_range(0, 3)
		p.step = 1 if rng.randf() < 0.5 else -1
		p.speed = rng.randf_range(1.1, 1.5)
		p.side = rng.randf_range(-0.4, 0.4)
		p.bob = rng.randf() * TAU
		# Start somewhere along the edge leading to our corner.
		var from := _corner_pos(p.bi, p.bj, (p.corner - p.step + 4) % 4)
		var to := _corner_pos(p.bi, p.bj, p.corner)
		p.node.global_position = from.lerp(to, rng.randf())
		p.target = to
		peds.append(p)

func _corner_pos(bi: int, bj: int, corner: int) -> Vector3:
	var s := CORNERS[corner]
	return City.block_centre(bi, bj) + Vector3(s.x, 0, s.y) * PATH_OFFSET

static var _body_arrays: Array = []
static var _head_arrays: Array = []

## Body (capsule) and head (sphere) merged into one low-poly mesh with vertex colours.
func _make_body() -> Node3D:
	if _body_arrays.is_empty():
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.22
		capsule.height = 1.3
		capsule.radial_segments = 8
		capsule.rings = 2
		_body_arrays = capsule.get_mesh_arrays()
		var sphere := SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		sphere.radial_segments = 8
		sphere.rings = 4
		_head_arrays = sphere.get_mesh_arrays()
	var shirt := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 0.9))
	var skin: Color = [Color("f1c27d"), Color("e0ac69"), Color("c68642"), Color("8d5524")].pick_random()
	var height := rng.randf_range(0.8, 1.1)   # some kids, some tall adults
	var st := MeshBuilder.begin()
	MeshBuilder.add(st, _body_arrays, Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), shirt)
	MeshBuilder.add(st, _head_arrays, Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)), skin)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshBuilder.vertex_color_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * height
	add_child(mi)
	return mi

func _physics_process(delta: float) -> void:
	for p in peds:
		match p.mode:
			Mode.WALK:
				_move(p, p.target, p.speed, delta)
				if _flat_dist(p.node.global_position, p.target) < 0.3:
					_arrive_at_corner(p)
			Mode.WAIT:
				p.wait_time += delta
				if _can_cross(p):
					p.mode = Mode.CROSS
					p.blocked_time = 0.0
				elif p.wait_time > MAX_WAIT:
					_walk_on(p)
			Mode.CROSS:
				if not p.detour.is_empty():
					_move(p, p.detour[0], CROSS_SPEED, delta)
					if _flat_dist(p.node.global_position, p.detour[0]) < 0.3:
						p.detour.remove_at(0)
					continue
				# Don't walk into a car standing in the crosswalk. If it doesn't move (it may be
				# waiting for us), walk around behind it.
				var ahead := p.node.global_position + (p.cross_to - p.node.global_position).normalized() * 0.9
				var car = _car_hit(ahead, 0.4)
				if car != null:
					p.blocked_time += delta
					if p.blocked_time > 2.0:
						p.detour = _detour_around(car, p.node.global_position)
						p.blocked_time = 0.0
				else:
					_move(p, p.cross_to, CROSS_SPEED, delta)
				if _flat_dist(p.node.global_position, p.cross_to) < 0.3:
					p.bi = p.next_bi
					p.bj = p.next_bj
					p.corner = p.next_corner
					_walk_on(p)

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _move(p: Ped, to: Vector3, spd: float, delta: float) -> void:
	var pos := p.node.global_position
	var dir := Vector3(to.x - pos.x, 0, to.z - pos.z)
	var dist := dir.length()
	if dist < 0.001:
		return
	dir /= dist
	pos += dir * minf(spd * delta, dist)
	p.bob += delta * 9.0
	pos.y = absf(sin(p.bob)) * 0.05
	p.node.global_position = pos
	p.node.rotation.y = atan2(dir.x, dir.z)

func _arrive_at_corner(p: Ped) -> void:
	if rng.randf() < CROSS_CHANCE and _plan_crossing(p):
		p.mode = Mode.WAIT
		p.wait_time = 0.0
	else:
		_walk_on(p)

func _walk_on(p: Ped) -> void:
	p.mode = Mode.WALK
	p.corner = (p.corner + p.step + 4) % 4
	var t := _corner_pos(p.bi, p.bj, p.corner)
	# Sideways offset perpendicular to the walking direction.
	var from := p.node.global_position
	var along := Vector3(t.x - from.x, 0, t.z - from.z).normalized()
	p.target = t + Vector3(-along.z, 0, along.x) * p.side

## Choose which street to cross from the current corner. Returns false if there is none (city edge).
func _plan_crossing(p: Ped) -> bool:
	var s := CORNERS[p.corner]
	var across_x := rng.randf() < 0.5
	for attempt in 2:
		if across_x:
			var nbi := p.bi + s.x
			if nbi >= -City.GRID and nbi < City.GRID:
				p.next_bi = nbi
				p.next_bj = p.bj
				p.next_corner = CORNERS.find(Vector2i(-s.x, s.y))
				# Walking along X crosses a street where cars drive along Z.
				p.light_i = p.bi + (1 if s.x > 0 else 0)
				p.light_j = p.bj + (1 if s.y > 0 else 0)
				p.light_z = true
				p.cross_to = _corner_pos(p.next_bi, p.next_bj, p.next_corner)
				return true
		else:
			var nbj := p.bj + s.y
			if nbj >= -City.GRID and nbj < City.GRID:
				p.next_bi = p.bi
				p.next_bj = nbj
				p.next_corner = CORNERS.find(Vector2i(s.x, -s.y))
				p.light_i = p.bi + (1 if s.x > 0 else 0)
				p.light_j = p.bj + (1 if s.y > 0 else 0)
				p.light_z = false
				p.cross_to = _corner_pos(p.next_bi, p.next_bj, p.next_corner)
				return true
		across_x = not across_x
	return false

func _can_cross(p: Ped) -> bool:
	if lights == null:
		return true
	var distance := _flat_dist(p.node.global_position, p.cross_to)
	if not lights.has_light(p.light_i, p.light_j):
		# No lights here: cross when no car is close.
		var mid := p.node.global_position.lerp(p.cross_to, 0.5)
		if traffic:
			for c in traffic.cars:
				if not c.waiting and _flat_dist(c.node.global_position, mid) < 28.0:
					return false
		return true
	var left: float = lights.red_time_left(p.light_i, p.light_j, p.light_z)
	var red_total: float = lights.CYCLE - lights.GREEN_TIME - lights.YELLOW_TIME
	if left < distance / CROSS_SPEED + 0.5 or left > red_total - RED_GRACE:
		return false
	# Also wait while a car is sitting on the crosswalk.
	var from := p.node.global_position
	for k in range(1, 6):
		if _car_at(from.lerp(p.cross_to, k / 6.0), 0.8):
			return false
	return true

## True if `point` is inside (or within `margin` of) any traffic car's footprint.
func _car_at(point: Vector3, margin: float) -> bool:
	return _car_hit(point, margin) != null

## The traffic car whose footprint (grown by `margin`) contains `point`, or null.
func _car_hit(point: Vector3, margin: float):
	if traffic == null:
		return null
	for c in traffic.cars:
		if c.waiting:
			continue
		var local: Vector3 = c.node.global_transform.affine_inverse() * point
		if absf(local.x) < c.width * 0.5 + margin and absf(local.z) < c.length * 0.5 + margin:
			return c
	return null

## Two waypoints: beside the car, then behind it (cars face their -Z), on our side of it.
func _detour_around(car, from: Vector3) -> Array[Vector3]:
	var xf: Transform3D = car.node.global_transform
	var local: Vector3 = xf.affine_inverse() * from
	var side := 1.0 if local.x >= 0.0 else -1.0
	var behind: float = car.length * 0.5 + 1.2
	var out: float = car.width * 0.5 + 1.1
	var a: Vector3 = xf * Vector3(side * out, 0, local.z)
	var b: Vector3 = xf * Vector3(side * out, 0, behind)
	a.y = 0.0
	b.y = 0.0
	return [a, b]
