extends Node3D
## Builds a simple grid city at runtime: ground, roads with markings and crosswalks, sidewalks,
## buildings, trees, street lamps and the shop pad. Road centre lines sit at multiples of PITCH;
## the shop is at the origin intersection. Repeated props use MultiMeshes to stay cheap.

const PITCH := 52.0
const ROAD_WIDTH := 12.0
const GRID := 4           # blocks from -GRID..GRID-1 on both axes
# The motorcycle showroom takes the whole block next to the start; you drive in from its
# west side. SHOP_POS is the "drive in here" ring on its forecourt (see places.gd).
const SHOP_BLOCK := Vector2i(0, 0)
const SHOP_EDGE := Vector3(-1, 0, 0)
const SHOP_POS := Vector3(14, 0, 26)
const Places := preload("res://scripts/places.gd")
const Bangkok := preload("res://scripts/bangkok.gd")
const SIDEWALK_WIDTH := 2.0
const SIDEWALK_OFFSET := ROAD_WIDTH * 0.5 + SIDEWALK_WIDTH * 0.5   # sidewalk centre from road centre (7 m)
const CROSSWALK_DIST := 7.0   # crosswalk centre from the intersection centre (stop line is at 8)

# Gas stations: (block i, block j, edge direction) - the pad sits on the road at that block edge.
const GAS_STATION_SITES := [[-3, -2, Vector3(1, 0, 0)], [1, -4, Vector3(0, 0, 1)], [2, 2, Vector3(-1, 0, 0)], [-2, 3, Vector3(0, 0, -1)]]
const KERB := ROAD_WIDTH * 0.5 - 1.5   # kerbside spots sit this far from the road centre line

var spots: Array[Vector3] = []   # kerbside points used for pickups / dropoffs
var _lamp_mat: StandardMaterial3D

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_build_ground()
	_build_roads()
	_build_markings()
	_build_sidewalks()
	add_child(Bangkok.new())   # shophouses, towers, skytrain, temple, power lines (bangkok.gd)
	_build_trees_and_lamps()
	add_child(Places.new())
	# Delivery spots: on the road next to the kerb, halfway along every block edge (not at gas stations).
	var stations := gas_stations()
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			for edge in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
				var p := _kerb_spot(i, j, edge)
				if p not in stations:
					spots.append(p)

static func block_centre(i: int, j: int) -> Vector3:
	return Vector3((i + 0.5) * PITCH, 0, (j + 0.5) * PITCH)

static func _kerb_spot(i: int, j: int, edge: Vector3) -> Vector3:
	return block_centre(i, j) + edge * (PITCH * 0.5 - KERB)

## Refuel points: between the pump islands under each station's canopy.
static func gas_stations() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for site in GAS_STATION_SITES:
		out.append(block_centre(site[0], site[1]) + site[2] * (PITCH * 0.5 - ROAD_WIDTH * 0.5 - 9.0))
	return out

## True if the block edge (block i, j, facing `edge`) is the front of the shop or a gas station.
static func is_place_front(i: int, j: int, edge: Vector3) -> bool:
	if Vector2i(i, j) == SHOP_BLOCK and edge == SHOP_EDGE:
		return true
	for site in GAS_STATION_SITES:
		if site[0] == i and site[1] == j and site[2] == edge:
			return true
	return false

## True if the building in block (i, j) at quadrant offset (dx, dz) must make room for a place.
static func building_removed(i: int, j: int, dx: float, dz: float) -> bool:
	if Vector2i(i, j) == SHOP_BLOCK:
		return true
	for site in GAS_STATION_SITES:
		var e: Vector3 = site[2]
		if site[0] == i and site[1] == j and dx * e.x + dz * e.z > 0.0:
			return true
	return false

## Street lamps glow at night (called by the day/night controller).
func set_night(on: bool) -> void:
	_lamp_mat.emission_energy_multiplier = 4.0 if on else 0.0

# ------------------------------------------------------------------ helpers

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m

func _box(size: Vector3, pos: Vector3, color: Color, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	if size.y < 1.5:   # roads, ground: nothing to shadow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)

## One MultiMesh for many copies of `mesh`; transforms carry position, rotation and scale.
func _multi(mesh: Mesh, mat: Material, transforms: Array[Transform3D], shadows := false, colors: Array[Color] = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _unit_box() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b

func _scaled(pos: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)

# ------------------------------------------------------------------ pieces

func _build_ground() -> void:
	var size := (GRID * 2 + 2) * PITCH
	_box(Vector3(size, 1, size), Vector3(0, -0.5, 0), Color(0.36, 0.55, 0.3), true)

func _build_roads() -> void:
	var extent := GRID * PITCH + PITCH * 0.5
	var length := extent * 2.0
	for k in range(-GRID, GRID + 1):
		_box(Vector3(ROAD_WIDTH, 0.04, length), Vector3(k * PITCH, 0.02, 0), Color(0.18, 0.18, 0.2), false)
		_box(Vector3(length, 0.04, ROAD_WIDTH), Vector3(0, 0.03, k * PITCH), Color(0.18, 0.18, 0.2), false)

func _build_markings() -> void:
	var extent := GRID * PITCH + PITCH * 0.5
	var dashes: Array[Transform3D] = []
	var zebra: Array[Transform3D] = []
	var clear := CROSSWALK_DIST + 1.5   # keep dashes out of crosswalks / intersections
	for k in range(-GRID, GRID + 1):
		var line := k * PITCH
		# Dashed centre line along both axes, skipping intersections.
		var s := -extent
		while s < extent:
			var near := absf(fposmod(s + PITCH * 0.5, PITCH) - PITCH * 0.5)
			if near > clear and absf(s) < extent - 2.0:
				dashes.append(_scaled(Vector3(line, 0.05, s), Vector3(0.18, 0.02, 3.0)))
				dashes.append(_scaled(Vector3(s, 0.06, line), Vector3(3.0, 0.02, 0.18)))
			s += 6.0
	# Zebra crossings on all four arms of every intersection.
	for i in range(-GRID, GRID + 1):
		for j in range(-GRID, GRID + 1):
			var c := Vector3(i * PITCH, 0.07, j * PITCH)
			for side in [-1.0, 1.0]:
				for n in 6:
					var across := -5.0 + n * 2.0
					zebra.append(_scaled(c + Vector3(across, 0, side * CROSSWALK_DIST), Vector3(1.0, 0.02, 1.6)))
					zebra.append(_scaled(c + Vector3(side * CROSSWALK_DIST, 0, across), Vector3(1.6, 0.02, 1.0)))
	var white := _mat(Color(0.92, 0.92, 0.9))
	_multi(_unit_box(), white, dashes)
	_multi(_unit_box(), white, zebra)

func _build_sidewalks() -> void:
	var strips: Array[Transform3D] = []
	var inner := PITCH - ROAD_WIDTH   # block width between roads (40 m)
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			var c := block_centre(i, j)
			var o := PITCH * 0.5 - SIDEWALK_OFFSET
			strips.append(_scaled(c + Vector3(0, 0.05, -o), Vector3(inner, 0.1, SIDEWALK_WIDTH)))
			strips.append(_scaled(c + Vector3(0, 0.05, o), Vector3(inner, 0.1, SIDEWALK_WIDTH)))
			strips.append(_scaled(c + Vector3(-o, 0.05, 0), Vector3(SIDEWALK_WIDTH, 0.1, inner)))
			strips.append(_scaled(c + Vector3(o, 0.05, 0), Vector3(SIDEWALK_WIDTH, 0.1, inner)))
	_multi(_unit_box(), _mat(Color(0.62, 0.62, 0.6)), strips)

func _build_buildings(rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.85, 0.8, 0.7), Color(0.7, 0.75, 0.85), Color(0.9, 0.7, 0.65),
			Color(0.75, 0.85, 0.75), Color(0.8, 0.8, 0.85)]
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			var centre := block_centre(i, j)
			for dx in [-10.0, 10.0]:
				for dz in [-10.0, 10.0]:
					var h := rng.randf_range(8.0, 32.0)
					if building_removed(i, j, dx, dz):
						continue
					var size := Vector3(16, h, 16)
					var pos: Vector3 = centre + Vector3(dx, h * 0.5, dz)
					transforms.append(_scaled(pos, size))
					colors.append(palette[rng.randi() % palette.size()])
					var body := StaticBody3D.new()
					var cs := CollisionShape3D.new()
					var shape := BoxShape3D.new()
					shape.size = size
					cs.shape = shape
					body.add_child(cs)
					body.position = pos
					add_child(body)
	# All buildings in one draw call; colour per instance.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	_multi(_unit_box(), mat, transforms, true, colors)

func _build_trees_and_lamps() -> void:
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var o := PITCH * 0.5 - SIDEWALK_OFFSET + 0.6   # kerb side of the sidewalk (people walk on the inner side)
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			var c := block_centre(i, j)
			# Each block edge: a tree in the middle (lined up with the gap between buildings) and two lamps.
			for edge in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
				var along := Vector3(edge.z, 0, edge.x)   # direction along the edge
				var mid: Vector3 = c + edge * o
				if not is_place_front(i, j, edge):   # keep driveways clear
					trunks.append(_scaled(mid + Vector3(0, 1.1, 0), Vector3(0.3, 2.2, 0.3)))
					crowns.append(_scaled(mid + Vector3(0, 3.0, 0), Vector3(2.6, 2.4, 2.6)))
				for side in [-12.0, 12.0]:
					var p: Vector3 = mid + along * side
					poles.append(_scaled(p + Vector3(0, 2.5, 0), Vector3(0.14, 5.0, 0.14)))
					heads.append(_scaled(p + Vector3(0, 5.0, 0) + edge * 0.5, Vector3(0.5, 0.15, 0.5)))
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.5
	trunk_mesh.bottom_radius = 0.5
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	_multi(trunk_mesh, _mat(Color(0.4, 0.28, 0.18)), trunks)
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.5
	crown_mesh.height = 1.0
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 5
	_multi(crown_mesh, _mat(Color(0.25, 0.52, 0.25)), crowns, true)
	_multi(_unit_box(), _mat(Color(0.25, 0.26, 0.28)), poles)
	_lamp_mat = _mat(Color(1.0, 0.95, 0.8))
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.85, 0.55)
	_lamp_mat.emission_energy_multiplier = 0.0
	_multi(_unit_box(), _lamp_mat, heads)


