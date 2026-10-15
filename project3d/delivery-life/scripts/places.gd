extends Node3D
## Builds the special locations of the city: the motorcycle showroom and the gas stations.
## Each place is laid out in its own frame: `x` = metres in from the block edge that faces the
## road, `t` = metres sideways along that edge. All boxes of a place are merged into one mesh
## (vertex colours) plus one glowing surface for lights and signs, so a place costs ~2 draw calls.

const City := preload("res://scripts/city.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const WHITE := Color(0.93, 0.93, 0.92)
const CONCRETE := Color(0.5, 0.5, 0.49)
const DARK := Color(0.16, 0.17, 0.19)
const GLASS := Color(0.16, 0.26, 0.36)
const SHOP_YELLOW := Color(0.98, 0.76, 0.12)
const GAS_RED := Color(0.85, 0.16, 0.14)
const GAS_BLUE := Color(0.15, 0.55, 0.85)

var _glow_mat: StandardMaterial3D

# The place being built.
var _centre := Vector3.ZERO
var _edge := Vector3.ZERO      # unit vector from block centre towards the road
var _side := Vector3.ZERO      # unit vector along the edge
var _st: SurfaceTool
var _st_glow: SurfaceTool

func _ready() -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.vertex_color_is_srgb = true
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # signs and lights always read bright
	_build_shop()
	for site in City.GAS_STATION_SITES:
		_build_gas_station(site[0], site[1], site[2])

# ------------------------------------------------------------------ helpers

func _begin(i: int, j: int, edge: Vector3) -> void:
	_centre = City.block_centre(i, j)
	_edge = edge
	_side = Vector3(edge.z, 0, -edge.x)
	_st = MeshBuilder.begin()
	_st_glow = MeshBuilder.begin()

## World position of a point `x` metres in from the block edge, `t` along it, `y` up.
func _p(x: float, t: float, y: float) -> Vector3:
	return _centre + _edge * (City.PITCH * 0.5 - City.ROAD_WIDTH * 0.5 - x) + _side * t + Vector3(0, y, 0)

## World-space size of a box `depth` deep (away from the road), `height` tall, `width` along the edge.
func _size(depth: float, height: float, width: float) -> Vector3:
	return Vector3(depth, height, width) if absf(_edge.x) > 0.5 else Vector3(width, height, depth)

## Add a box whose base sits at local (x, t, y). `glow` boxes go on the unshaded surface.
func _box(x: float, t: float, y: float, depth: float, height: float, width: float, color: Color, collide := false, glow := false) -> void:
	var size := _size(depth, height, width)
	var pos := _p(x, t, y + height * 0.5)
	MeshBuilder.add_box(_st_glow if glow else _st, pos, size, color)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		add_child(body)

func _commit() -> void:
	var mesh := _st.commit()
	mesh.surface_set_material(0, MeshBuilder.vertex_color_material())
	_st_glow.commit(mesh)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _glow_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

## A sign facing the road.
func _label(text: String, x: float, t: float, y: float, size: int, color: Color, outline := Color.BLACK) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = maxi(size / 6, 4)
	l.outline_modulate = outline
	l.modulate = color
	l.pixel_size = 0.01
	l.position = _p(x, t, y)
	l.rotation.y = atan2(_edge.x, _edge.z)   # Label3D reads from its +Z side
	add_child(l)
	return l

# ------------------------------------------------------------------ motorcycle showroom

func _build_shop() -> void:
	_begin(City.SHOP_BLOCK.x, City.SHOP_BLOCK.y, City.SHOP_EDGE)
	# Forecourt paving with a darker border, and the yellow "drive in here" ring.
	_box(10.0, 0, 0.0, 21.0, 0.04, 38.0, Color(0.36, 0.37, 0.4))
	_box(10.5, 0, 0.0, 19.0, 0.05, 36.0, Color(0.56, 0.54, 0.5))
	for a in 16:
		var ang := TAU * a / 16.0
		var off := _edge * cos(ang) * 4.0 + _side * sin(ang) * 4.0
		MeshBuilder.add_box(_st_glow, City.SHOP_POS + off + Vector3(0, 0.07, 0), Vector3(0.9, 0.04, 0.9), SHOP_YELLOW)

	# Showroom: solid back and sides, glass front with mullions, flat roof with overhang.
	var x0 := 21.0          # front wall distance from the block edge
	var depth := 16.0
	var width := 32.0
	var h := 8.0
	_box(x0 + depth - 0.5, 0, 0, 1.0, h, width, WHITE, true)                       # back wall
	for s in [-1.0, 1.0]:
		_box(x0 + depth * 0.5, s * (width * 0.5 - 0.5), 0, depth, h, 1.0, WHITE, true)   # side walls
	_box(x0, 0, 0, 0.3, h - 1.2, width - 2.0, GLASS, true)                         # glass front
	for k in 7:
		_box(x0 - 0.05, -width * 0.5 + 1.0 + k * (width - 2.0) / 6.0, 0, 0.4, h - 1.2, 0.35, DARK)
	_box(x0 - 0.1, 0, h - 1.2, 0.4, 1.2, width, DARK)                              # header band
	_box(x0 + depth * 0.5 - 1.0, 0, h, depth + 2.0, 0.5, width + 2.0, WHITE)       # roof, 2 m overhang at the front
	_box(x0 - 2.0, 0, h - 0.3, 1.0, 0.8, width + 2.0, SHOP_YELLOW)                 # yellow fascia
	_box(x0 - 0.25, -6, 0, 0.35, 3.2, 0.2, Color(0.9, 0.9, 0.9))                   # door frame
	_box(x0 - 0.25, -2, 0, 0.35, 3.2, 0.2, Color(0.9, 0.9, 0.9))
	# Warm interior light visible through the glass at night.
	_box(x0 + 0.4, 0, h - 1.7, 0.2, 0.3, width - 4.0, Color(1.0, 0.92, 0.7), false, true)

	# Big rooftop sign.
	_box(x0 + 1.0, 0, h + 0.5, 0.5, 0.6, 2.0, DARK)                                # sign legs
	_box(x0 + 1.0, -8, h + 0.5, 0.5, 0.6, 0.6, DARK)
	_box(x0 + 1.0, 8, h + 0.5, 0.5, 0.6, 0.6, DARK)
	_box(x0 + 0.8, 0, h + 1.1, 0.5, 2.6, 22.0, SHOP_YELLOW)
	_label("MOTO SHOP", x0 + 0.5, 0, h + 2.45, 200, Color(0.08, 0.07, 0.05), SHOP_YELLOW)

	# Display podiums with spotlights, on the forecourt in front of the glass.
	for t in [-10.0, 10.0]:
		_box(16.0, t, 0, 4.0, 0.35, 4.0, DARK, true)
		_box(16.0, t, 0.35, 3.6, 0.06, 3.6, Color(0.95, 0.95, 0.95))
		_box(16.0, t + 2.2, 0.35, 3.6, 0.08, 0.15, SHOP_YELLOW, false, true)          # glowing trim

	# Dealership flags along the road edge.
	var flag_colors := [SHOP_YELLOW, Color(0.2, 0.5, 0.95), Color(0.9, 0.2, 0.25), SHOP_YELLOW]
	for k in 4:
		var t: float = -15.0 + k * 10.0
		if absf(t) < 4.0:
			continue
		_box(1.0, t, 0, 0.2, 6.5, 0.2, Color(0.8, 0.8, 0.82), true)
		_box(1.0, t + 0.75, 3.6, 0.1, 2.8, 1.3, flag_colors[k])
	# Planters by the entrance.
	for t in [-14.0, 14.0]:
		_box(19.0, t, 0, 1.6, 0.6, 1.6, DARK, true)
		_box(19.0, t, 0.6, 1.3, 0.9, 1.3, Color(0.25, 0.55, 0.28))
	_commit()

	# Two display bikes (not on LOW graphics: the bike model is heavy for slower machines).
	if Settings.graphics >= 1:
		var bike_scene: PackedScene = load("res://scenes/motorcycle.tscn")
		var colors := [Color("c3101b"), Color("0042b8")]
		for k in 2:
			var bike: Node3D = bike_scene.instantiate()
			bike.preview_only = true
			add_child(bike)
			bike.global_position = _p(16.0, [-10.0, 10.0][k], 0.41)
			bike.rotation.y = atan2(_edge.x, _edge.z) + deg_to_rad(35.0 if k == 0 else -35.0)
			bike.apply_body_color(colors[k])
			bike._rider.visible = false

# ------------------------------------------------------------------ gas station

func _build_gas_station(i: int, j: int, edge: Vector3) -> void:
	_begin(i, j, edge)
	var pump_x := 9.0       # distance in from the block edge to the pump line (the refuel point)
	# Forecourt slab.
	_box(10.0, 0, 0, 21.0, 0.04, 38.0, Color(0.3, 0.31, 0.33))
	_box(10.5, 0, 0, 19.0, 0.05, 36.0, CONCRETE)
	# Canopy on four pillars, white with a red fascia and glowing panels underneath.
	var cw := 16.0
	var cd := 10.0
	for sx in [-1.0, 1.0]:
		for st in [-1.0, 1.0]:
			_box(pump_x + sx * 3.5, st * 6.5, 0, 0.45, 5.0, 0.45, WHITE, true)
	_box(pump_x, 0, 5.0, cd, 0.5, cw, WHITE)
	_box(pump_x - cd * 0.5, 0, 4.9, 0.15, 0.8, cw + 0.2, GAS_RED)
	_box(pump_x + cd * 0.5, 0, 4.9, 0.15, 0.8, cw + 0.2, GAS_RED)
	for st in [-1.0, 1.0]:
		_box(pump_x, st * (cw * 0.5), 4.9, cd, 0.8, 0.15, GAS_RED)
	for k in 3:
		_box(pump_x - 3.0 + k * 3.0, 0, 4.92, 1.2, 0.06, cw - 3.0, Color(1, 1, 0.95), false, true)
	_label("GAS", pump_x - cd * 0.5 - 0.2, 0, 5.3, 110, Color.WHITE, GAS_RED)

	# Two pump islands either side of the refuel lane.
	for st in [-3.6, 3.6]:
		_box(pump_x, st, 0, 4.0, 0.25, 1.1, CONCRETE, true)
		for sx in [-1.0, 1.0]:
			_box(pump_x + sx * 1.0, st, 0.25, 0.7, 1.6, 0.6, GAS_RED, true)
			_box(pump_x + sx * 1.0, st, 1.85, 0.72, 0.25, 0.62, WHITE)
			_box(pump_x + sx * 1.0, st - 0.31 * signf(st), 1.1, 0.4, 0.35, 0.04, Color(0.4, 0.9, 1.0), false, true)   # screen

	# Mini-mart kiosk at the back corner.
	var kx := 17.0
	var kt := -11.0
	_box(kx, kt, 0, 6.0, 3.6, 9.0, WHITE, true)
	_box(kx - 3.05, kt, 0.3, 0.1, 2.4, 6.0, GLASS)
	_box(kx - 3.1, kt, 2.6, 0.12, 0.25, 6.2, Color(1.0, 0.95, 0.8), false, true)   # lit window strip
	_box(kx - 0.5, kt, 3.6, 7.2, 0.3, 10.0, GAS_RED)
	_label("MINI MART", kx - 3.6, kt, 3.15, 56, Color.WHITE, GAS_RED)

	# Tall price sign by the road.
	var pt := 15.0
	_box(1.2, pt, 0, 0.4, 7.0, 0.4, DARK, true)
	_box(1.2, pt, 6.0, 0.4, 3.2, 2.6, GAS_RED)
	_box(1.0, pt, 6.2, 0.1, 1.2, 2.2, Color(0.08, 0.08, 0.1))
	_label("GAS", 0.95, pt, 8.45, 80, Color.WHITE, GAS_RED)
	_label("%d฿/L" % GameState.FUEL_PRICE, 0.9, pt, 6.8, 64, Color(1.0, 0.85, 0.2), Color.BLACK)
	_commit()
