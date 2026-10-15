extends Node3D
## Dresses the city grid up as Bangkok: rows of shophouses with Thai shop signs, downtown glass
## towers, an elevated skytrain line with a station and a running train, a temple, concrete power
## poles with sagging wires, street-food carts and spirit houses.
## Every block is merged into one mesh (vertex colours) to keep draw calls low; Thai sign text uses
## Label3D with a visibility range so only nearby signs are drawn.

const City := preload("res://scripts/city.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const PITCH := City.PITCH
const GRID := City.GRID
const HALF := City.PITCH * 0.5
const FRONT := City.PITCH * 0.5 - City.ROAD_WIDTH * 0.5 - City.SIDEWALK_WIDTH   # facade line from block centre (18 m)
const TEMPLE_BLOCK := Vector2i(-3, 1)
const SKYTRAIN_ROAD_X := -52.0          # the skytrain runs above this north-south road
const SKYTRAIN_HEIGHT := 10.0
const STATION_Z := 26.0                 # skytrain station, between two junctions
const SIGN_RANGE := 70.0                # Thai sign text is only drawn this close

const SHOP_SIGNS := ["ข้าวมันไก่", "ก๋วยเตี๋ยว", "ร้านกาแฟ", "ร้านขายยา", "ซ่อมมอเตอร์ไซค์", "ร้านทอง",
	"มินิมาร์ท", "ข้าวผัด", "ส้มตำ", "นวดแผนไทย", "ร้านตัดผม", "โรงแรม", "ชาไทย", "หมูปิ้ง",
	"ร้านโชห่วย", "ผัดไทย", "ข้าวขาหมู", "ร้านซักรีด", "โทรศัพท์มือถือ", "ร้านเสริมสวย"]
const FACADES := [Color("e3c88f"), Color("a9c7d8"), Color("eba57a"), Color("9fcf8f"), Color("e39b9b"),
	Color("f0d264"), Color("8fa9de"), Color("d6d3cc"), Color("c99a6e"), Color("7fc4b6"), Color("e6b3d0"), Color("f2efe8")]
const SIGN_COLORS := [Color("d62828"), Color("f2c230"), Color("1d6fd1"), Color("2a9d4b"), Color("e76f2b"), Color("8e3fbf")]
const AWNINGS := [Color("c0392b"), Color("2e86c1"), Color("27ae60"), Color("e67e22"), Color("16a085")]
const GOLD := Color("d9aa3a")
const TEMPLE_ORANGE := Color("d9611a")
const TEMPLE_GREEN := Color("2f7d4b")

var rng := RandomNumberGenerator.new()
var _font: Font
var _sign_mats := {}
var _shape_cache := {}

# Frame of the edge being built (same convention as places.gd).
var _centre := Vector3.ZERO
var _edge := Vector3.ZERO
var _side := Vector3.ZERO
var _st: SurfaceTool

func _ready() -> void:
	rng.seed = 2468
	_font = load("res://assets/fonts/Sarabun-SemiBold.ttf")
	var detail := Settings.graphics >= 1
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			_build_block(i, j, detail)
	_build_skytrain()
	_build_wires()
	_build_street_stuff(detail)

# ------------------------------------------------------------------ helpers

func _shape(key: String) -> Array:
	if not _shape_cache.has(key):
		var m: PrimitiveMesh
		match key:
			"prism":
				m = PrismMesh.new()
			"cyl":
				var c := CylinderMesh.new()
				c.radial_segments = 12
				c.rings = 1
				m = c
			"cone":
				var c2 := CylinderMesh.new()
				c2.top_radius = 0.0
				c2.radial_segments = 12
				c2.rings = 1
				m = c2
			"sphere":
				var sp := SphereMesh.new()
				sp.radius = 0.5
				sp.height = 1.0
				sp.radial_segments = 12
				sp.rings = 6
				m = sp
			"bell":
				var c3 := CylinderMesh.new()
				c3.top_radius = 0.6
				c3.bottom_radius = 1.0
				c3.radial_segments = 14
				c3.rings = 1
				m = c3
		_shape_cache[key] = m.get_mesh_arrays()
	return _shape_cache[key]

func _frame(i: int, j: int, edge: Vector3) -> void:
	_centre = City.block_centre(i, j)
	_edge = edge
	_side = Vector3(edge.z, 0, -edge.x)

## Point `x` metres in from the facade line, `t` along the edge, `y` up.
func _p(x: float, t: float, y: float) -> Vector3:
	return _centre + _edge * (FRONT - x) + _side * t + Vector3(0, y, 0)

func _size(depth: float, height: float, width: float) -> Vector3:
	return Vector3(depth, height, width) if absf(_edge.x) > 0.5 else Vector3(width, height, depth)

## Box in the current edge frame, base at height y.
func _box(x: float, t: float, y: float, depth: float, height: float, width: float, color: Color) -> void:
	MeshBuilder.add_box(_st, _p(x, t, y + height * 0.5), _size(depth, height, width), color)

func _collider(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	add_child(body)

func _commit(st: SurfaceTool, range_end := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshBuilder.vertex_color_material()
	if range_end > 0.0:
		mi.visibility_range_end = range_end
		mi.visibility_range_end_margin = 20.0
	add_child(mi)

## Thai text on a sign, facing out of the current edge.
func _sign_text(text: String, x: float, t: float, y: float, size: int, color := Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size
	l.outline_size = 0
	l.modulate = color
	l.pixel_size = 0.01
	l.position = _p(x, t, y)
	l.rotation.y = atan2(_edge.x, _edge.z)
	l.visibility_range_end = SIGN_RANGE
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)

# ------------------------------------------------------------------ blocks

func _is_downtown(i: int, j: int) -> bool:
	return maxf(absf(i + 0.5), absf(j + 0.5)) <= 1.5

func _station_edge(i: int, j: int) -> Variant:
	for site in City.GAS_STATION_SITES:
		if site[0] == i and site[1] == j:
			return site[2]
	return null

func _build_block(i: int, j: int, detail: bool) -> void:
	if Vector2i(i, j) == City.SHOP_BLOCK:
		return
	_st = MeshBuilder.begin()
	if Vector2i(i, j) == TEMPLE_BLOCK:
		_build_temple(i, j)
	elif _is_downtown(i, j):
		_build_towers(i, j)
	else:
		var station = _station_edge(i, j)
		for edge in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
			# A gas station takes its edge and the two side rows; keep the row opposite it.
			if station != null and edge != -station:
				continue
			_build_shophouse_row(i, j, edge, detail)
		if station == null and rng.randf() < 0.45:
			_build_courtyard_condo(i, j)
	_commit(_st, 320.0)

## A row of 4 m wide shophouses facing the street along one block edge.
func _build_shophouse_row(i: int, j: int, edge: Vector3, detail: bool) -> void:
	_frame(i, j, edge)
	var full := absf(edge.z) > 0.5          # rows on the north/south edges run the full block width
	var length := FRONT * 2.0 if full else 12.0
	var depth := 12.0
	var count := int(length / 4.0)
	var max_h := 0.0
	for u in count:
		var t := -length * 0.5 + 2.0 + u * 4.0
		var floors := rng.randi_range(3, 4)
		var h := floors * 3.2 + 0.6
		max_h = maxf(max_h, h)
		var facade: Color = FACADES[rng.randi() % FACADES.size()]
		_box(depth * 0.5, t, 0, depth, h, 3.92, facade)
		# Ground floor: roll-up shutter, or an open shop with an awning (and maybe a sign).
		if rng.randf() < 0.3:
			_box(-0.04, t, 0, 0.1, 2.8, 3.5, Color("8e9399"))
			for k in 4:
				_box(-0.1, t, 0.5 + k * 0.6, 0.04, 0.05, 3.5, Color("6d7277"))
		else:
			_box(-0.03, t, 0, 0.08, 2.8, 3.5, Color("2b2a28"))
			_box(-0.6, t, 2.9, 1.2, 0.12, 3.8, AWNINGS[rng.randi() % AWNINGS.size()])
			if rng.randf() < 0.55:
				var sign_color: Color = SIGN_COLORS[rng.randi() % SIGN_COLORS.size()]
				_box(-0.12, t, 3.1, 0.14, 0.95, 3.6, sign_color)
				var text_color := Color.WHITE if sign_color.get_luminance() < 0.55 else Color(0.1, 0.08, 0.05)
				_sign_text(SHOP_SIGNS[rng.randi() % SHOP_SIGNS.size()], -0.2, t, 3.58, 64, text_color)
		# Upper floors: windows, some balconies, some air-con units.
		for f in range(1, floors):
			var y := f * 3.2
			_box(-0.03, t, y + 0.9, 0.08, 1.4, 3.0, Color("26333d"))
			if detail and rng.randf() < 0.45:
				_box(-0.45, t, y, 0.9, 0.15, 3.7, Color("dedad2"))
				_box(-0.86, t, y + 0.15, 0.06, 0.9, 3.7, Color("5c5f63"))
			if detail and rng.randf() < 0.35:
				_box(-0.25, t + (1.3 if rng.randf() < 0.5 else -1.3), y + 0.35, 0.45, 0.55, 0.8, Color("f1f1ee"))
		_box(0.1, t, h, 0.3, 0.5, 3.92, facade.lightened(0.15))   # parapet
	_collider(_p(depth * 0.5, 0, max_h * 0.5), _size(depth, max_h, length))

## A residential condo tower in the block's courtyard, for skyline variety.
func _build_courtyard_condo(i: int, j: int) -> void:
	var c := City.block_centre(i, j)
	var h := rng.randf_range(24.0, 46.0)
	var col: Color = [Color("f2efe6"), Color("e6e0d0"), Color("d8dde3")][rng.randi() % 3]
	MeshBuilder.add_box(_st, c + Vector3(0, h * 0.5, 0), Vector3(10, h, 10), col)
	var y := 3.0
	while y < h - 1.0:
		MeshBuilder.add_box(_st, c + Vector3(0, y, 0), Vector3(10.4, 0.25, 10.4), col.darkened(0.2))
		MeshBuilder.add_box(_st, c + Vector3(0, y + 1.3, 0), Vector3(10.08, 1.1, 10.08), Color("2d3a46"))
		y += 3.0
	_collider(c + Vector3(0, h * 0.5, 0), Vector3(10, h, 10))

## Downtown: glass office towers on the four corners of the block, some with rooftop billboards.
func _build_towers(i: int, j: int) -> void:
	var c := City.block_centre(i, j)
	for dx in [-10.0, 10.0]:
		for dz in [-10.0, 10.0]:
			if City.building_removed(i, j, dx, dz):
				continue
			var h := rng.randf_range(30.0, 72.0)
			var base := c + Vector3(dx, 0, dz)
			var glass: Color = [Color("4f7fa6"), Color("5d8f9e"), Color("6b7f99"), Color("3f6d8e")][rng.randi() % 4]
			MeshBuilder.add_box(_st, base + Vector3(0, 3.0, 0), Vector3(16, 6.0, 16), Color("d9d5cc"))   # podium
			MeshBuilder.add_box(_st, base + Vector3(0, h * 0.5 + 3.0, 0), Vector3(14, h, 14), glass)
			for k in 5:   # vertical mullions
				var o := -6.0 + k * 3.0
				MeshBuilder.add_box(_st, base + Vector3(o, h * 0.5 + 3.0, 0), Vector3(0.3, h, 14.1), glass.lightened(0.35))
				MeshBuilder.add_box(_st, base + Vector3(0, h * 0.5 + 3.0, o), Vector3(14.1, h, 0.3), glass.lightened(0.35))
			MeshBuilder.add_box(_st, base + Vector3(0, h + 3.4, 0), Vector3(14.4, 0.8, 14.4), Color("cfd3d6"))
			if rng.randf() < 0.35:   # rooftop billboard
				var bcol: Color = SIGN_COLORS[rng.randi() % SIGN_COLORS.size()]
				MeshBuilder.add_box(_st, base + Vector3(0, h + 4.6, 0), Vector3(0.6, 2.0, 0.6), Color("555"))
				MeshBuilder.add_box(_st, base + Vector3(0, h + 7.0, 0), Vector3(10, 3.6, 0.4), bcol)
			_collider(base + Vector3(0, (h + 6.0) * 0.5, 0), Vector3(16, h + 6.0, 16))

# ------------------------------------------------------------------ temple

func _build_temple(i: int, j: int) -> void:
	var c := City.block_centre(i, j)
	var white := Color("f3efe6")
	# Compound wall with a gate facing east (towards the bigger road).
	for e in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var s := Vector3(e.z, 0, -e.x)
		# Each wall is two halves; on the east wall they leave a 6 m gap for the gate.
		var gate: bool = e.x > 0.5
		var length := 15.0 if gate else 18.0
		for half in [-1.0, 1.0]:
			var seg: Vector3 = c + e * (FRONT - 0.3) + s * (half * (18.0 - length * 0.5))
			var sz := Vector3(0.5, 2.2, length) if absf(e.x) > 0.5 else Vector3(length, 2.2, 0.5)
			MeshBuilder.add_box(_st, seg + Vector3(0, 1.1, 0), sz, white)
			_collider(seg + Vector3(0, 1.1, 0), sz)
	# Gate posts with little roofs.
	for side in [-3.0, 3.0]:
		var gp := c + Vector3(FRONT - 0.3, 0, side)
		MeshBuilder.add_box(_st, gp + Vector3(0, 2.0, 0), Vector3(0.9, 4.0, 0.9), white)
		MeshBuilder.add_box(_st, gp + Vector3(0, 4.3, 0), Vector3(1.2, 0.6, 1.2), GOLD)
	# Ordination hall (ubosot): platform, white walls, three-tier orange roof with green edges.
	var hall := c + Vector3(-2, 0, 0)
	MeshBuilder.add_box(_st, hall + Vector3(0, 0.6, 0), Vector3(26, 1.2, 15), white)
	MeshBuilder.add_box(_st, hall + Vector3(0, 4.2, 0), Vector3(22, 6.0, 11), white)
	for k in 6:   # gold-framed windows/doors
		MeshBuilder.add_box(_st, hall + Vector3(-8.5 + k * 3.4, 3.4, 5.55), Vector3(1.4, 2.6, 0.1), Color("7a3b1b"))
		MeshBuilder.add_box(_st, hall + Vector3(-8.5 + k * 3.4, 3.4, -5.55), Vector3(1.4, 2.6, 0.1), Color("7a3b1b"))
	var roof_rot := Basis(Vector3.UP, PI * 0.5)   # PrismMesh ridge runs along Z; turn it along X
	var tiers := [[7.2, Vector3(15.0, 4.4, 25.0)], [9.6, Vector3(12.0, 3.6, 20.0)], [11.6, Vector3(8.0, 3.0, 15.0)]]
	for tier in tiers:
		var y: float = tier[0]
		var sz: Vector3 = tier[1]
		MeshBuilder.add(_st, _shape("prism"), Transform3D(roof_rot * Basis.from_scale(sz + Vector3(0.9, 0.15, -0.8)), hall + Vector3(0, y + sz.y * 0.5 - 0.15, 0)), TEMPLE_GREEN)
		MeshBuilder.add(_st, _shape("prism"), Transform3D(roof_rot * Basis.from_scale(sz), hall + Vector3(0, y + sz.y * 0.5, 0)), TEMPLE_ORANGE)
	# Gold chofa finials at the gable ends.
	for end in [-1.0, 1.0]:
		MeshBuilder.add_box(_st, hall + Vector3(end * 7.6, 15.6, 0), Vector3(0.3, 1.8, 0.3), GOLD)
		MeshBuilder.add_box(_st, hall + Vector3(end * 8.0, 16.4, 0), Vector3(0.9, 0.3, 0.3), GOLD)
	_collider(hall + Vector3(0, 4.0, 0), Vector3(26, 8.0, 15))
	# Golden chedi behind the hall.
	var ch := c + Vector3(-13, 0, 10)
	MeshBuilder.add(_st, _shape("cyl"), Transform3D(Basis.from_scale(Vector3(8, 2.0, 8)), ch + Vector3(0, 1.0, 0)), white)
	MeshBuilder.add(_st, _shape("cyl"), Transform3D(Basis.from_scale(Vector3(6.4, 1.2, 6.4)), ch + Vector3(0, 2.6, 0)), white)
	MeshBuilder.add(_st, _shape("bell"), Transform3D(Basis.from_scale(Vector3(5.2, 5.0, 5.2)), ch + Vector3(0, 5.7, 0)), GOLD)
	MeshBuilder.add(_st, _shape("cyl"), Transform3D(Basis.from_scale(Vector3(2.2, 1.0, 2.2)), ch + Vector3(0, 8.7, 0)), GOLD)
	MeshBuilder.add(_st, _shape("cone"), Transform3D(Basis.from_scale(Vector3(2.4, 9.0, 2.4)), ch + Vector3(0, 13.7, 0)), GOLD)
	_collider(ch + Vector3(0, 4.0, 0), Vector3(8, 8, 8))
	# Bodhi trees in the courtyard.
	for p in [Vector3(12, 0, -12), Vector3(-14, 0, -12), Vector3(12, 0, 13)]:
		MeshBuilder.add(_st, _shape("cyl"), Transform3D(Basis.from_scale(Vector3(0.9, 5.0, 0.9)), c + p + Vector3(0, 2.5, 0)), Color("6b4a2f"))
		MeshBuilder.add(_st, _shape("sphere"), Transform3D(Basis.from_scale(Vector3(8.5, 6.0, 8.5)), c + p + Vector3(0, 7.0, 0)), Color("3f7a3a"))
	_frame(i, j, Vector3(1, 0, 0))
	_sign_text("วัดกลางเมือง", -0.6, 0, 4.9, 110, GOLD)

# ------------------------------------------------------------------ skytrain

func _build_skytrain() -> void:
	var st := MeshBuilder.begin()
	var extent := GRID * PITCH + HALF
	var x := SKYTRAIN_ROAD_X
	var concrete := Color("c9c6be")
	# Elevated deck along the whole road, with two rails.
	MeshBuilder.add_box(st, Vector3(x, SKYTRAIN_HEIGHT, 0), Vector3(8.0, 1.2, extent * 2.0), concrete)
	for rx in [-1.8, 1.8]:
		MeshBuilder.add_box(st, Vector3(x + rx, SKYTRAIN_HEIGHT + 0.75, 0), Vector3(0.3, 0.3, extent * 2.0), Color("7d8085"))
	MeshBuilder.add_box(st, Vector3(x - 4.0, SKYTRAIN_HEIGHT + 1.0, 0), Vector3(0.3, 0.8, extent * 2.0), concrete.darkened(0.1))
	MeshBuilder.add_box(st, Vector3(x + 4.0, SKYTRAIN_HEIGHT + 1.0, 0), Vector3(0.3, 0.8, extent * 2.0), concrete.darkened(0.1))
	# Pillars down the middle of the road (clear of the lanes and the junctions).
	var z := -extent + 13.0
	while z < extent:
		var near_junction := absf(fposmod(z + HALF, PITCH) - HALF) < 12.0
		if not near_junction:
			MeshBuilder.add_box(st, Vector3(x, SKYTRAIN_HEIGHT * 0.5 - 0.3, z), Vector3(1.3, SKYTRAIN_HEIGHT - 0.6, 1.3), concrete)
			MeshBuilder.add_box(st, Vector3(x, SKYTRAIN_HEIGHT - 1.1, z), Vector3(7.0, 1.0, 1.5), concrete)
			_collider(Vector3(x, SKYTRAIN_HEIGHT * 0.5, z), Vector3(1.3, SKYTRAIN_HEIGHT, 1.3))
		z += 13.0
	# Station: wider platforms, a long roof and the station sign.
	var sz := STATION_Z
	MeshBuilder.add_box(st, Vector3(x, SKYTRAIN_HEIGHT - 0.2, sz), Vector3(15.0, 1.0, 34.0), concrete)
	for px in [-5.6, 5.6]:
		MeshBuilder.add_box(st, Vector3(x + px, SKYTRAIN_HEIGHT + 1.0, sz), Vector3(3.6, 0.3, 32.0), Color("bdbab2"))
		MeshBuilder.add_box(st, Vector3(x + px * 1.27, SKYTRAIN_HEIGHT + 2.6, sz), Vector3(0.2, 3.2, 32.0), Color("9fc4d6"))   # glass screens
	for k in 5:
		var pz := sz - 14.0 + k * 7.0
		for px2 in [-7.0, 7.0]:
			MeshBuilder.add_box(st, Vector3(x + px2, SKYTRAIN_HEIGHT + 2.5, pz), Vector3(0.3, 3.6, 0.3), Color("8a8d91"))
	MeshBuilder.add_box(st, Vector3(x, SKYTRAIN_HEIGHT + 4.6, sz), Vector3(16.0, 0.4, 34.0), Color("e9e7e1"))
	MeshBuilder.add_box(st, Vector3(x, SKYTRAIN_HEIGHT + 5.2, sz), Vector3(10.0, 0.8, 30.0), Color("6aa84f"))
	for side in [-1.0, 1.0]:
		MeshBuilder.add_box(st, Vector3(x + side * 8.05, SKYTRAIN_HEIGHT + 3.8, sz), Vector3(0.2, 1.4, 10.0), Color("1f6e3d"))
	_commit(st)
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "สถานีกลางเมือง"
		l.font = _font
		l.font_size = 90
		l.modulate = Color.WHITE
		l.pixel_size = 0.01
		l.position = Vector3(x + side * 8.2, SKYTRAIN_HEIGHT + 3.85, sz)
		l.rotation.y = PI * 0.5 * side
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(l)
	add_child(SkyTrain.new(x, extent, sz))

## The train: three white cars with a green stripe, shuttling along the line and stopping at the station.
class SkyTrain extends Node3D:
	const SPEED := 14.0
	const DWELL := 6.0
	var _x := 0.0
	var _extent := 0.0
	var _station := 0.0
	var _dir := 1.0
	var _z := 0.0
	var _wait := 0.0
	var _stopped_here := false

	func _init(x: float, extent: float, station_z: float) -> void:
		_x = x
		_extent = extent - 30.0
		_station = station_z
		_z = -_extent

	func _ready() -> void:
		var st := MeshBuilder.begin()
		for k in 3:
			var cz := -14.0 + k * 14.0
			MeshBuilder.add_box(st, Vector3(1.5, 2.0, cz), Vector3(3.0, 3.0, 13.2), Color("f4f4f2"))
			MeshBuilder.add_box(st, Vector3(1.5, 2.1, cz), Vector3(3.05, 0.9, 12.6), Color("1d2a33"))   # windows
			MeshBuilder.add_box(st, Vector3(1.5, 1.0, cz), Vector3(3.06, 0.35, 13.2), Color("2e9d52"))  # stripe
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = MeshBuilder.vertex_color_material()
		mi.position = Vector3(-1.5, 0, 0)
		add_child(mi)
		position = Vector3(_x - 1.8, SKYTRAIN_HEIGHT + 0.6, _z)

	func _process(delta: float) -> void:
		if _wait > 0.0:
			_wait -= delta
			return
		_z += _dir * SPEED * delta
		if not _stopped_here and absf(_z - _station) < 0.5:
			_stopped_here = true
			_wait = DWELL
		if absf(_z - _station) > 25.0:
			_stopped_here = false
		if absf(_z) > _extent:
			_z = clampf(_z, -_extent, _extent)
			_dir = -_dir
			_wait = 3.0
		# Each direction runs on its own track.
		position = Vector3(_x + (1.8 if _dir > 0.0 else -1.8), SKYTRAIN_HEIGHT + 0.6, _z)

# ------------------------------------------------------------------ power lines, carts, spirit houses

## Concrete power poles along every street with sagging bundles of cables between them.
func _build_wires() -> void:
	var poles: Array[Transform3D] = []
	var wires: Array[Transform3D] = []
	var o := HALF - City.ROAD_WIDTH * 0.5 - 0.25   # just behind the kerb
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			if Vector2i(i, j) == TEMPLE_BLOCK:
				continue
			var c := City.block_centre(i, j)
			for edge in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
				if City.is_place_front(i, j, edge):
					continue
				var s := Vector3(edge.z, 0, -edge.x)
				var a: Vector3 = c + edge * o - s * 6.0
				var b: Vector3 = c + edge * o + s * 6.0
				for p in [a, b]:
					poles.append(Transform3D(Basis.from_scale(Vector3(0.28, 9.0, 0.28)), p + Vector3(0, 4.5, 0)))
					poles.append(Transform3D(Basis.from_scale(Vector3(1.6, 0.18, 0.18) if absf(s.x) > 0.5 else Vector3(0.18, 0.18, 1.6)), p + Vector3(0, 8.2, 0)))
				for k in 5:
					var h := 6.6 + k * 0.35
					var off: Vector3 = edge * (-0.25 + k * 0.12)
					_cable(wires, a + off + Vector3(0, h, 0), b + off + Vector3(0, h, 0), 0.5 + k * 0.08)
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3.ONE
	_multi(pole_mesh, Color("a7a49c"), poles, true)
	_multi(pole_mesh, Color("141414"), wires, false)

## A cable from a to b sagging by `sag` metres, as a few straight segments.
func _cable(out: Array[Transform3D], a: Vector3, b: Vector3, sag: float) -> void:
	const SEGMENTS := 4
	var prev := a
	for n in range(1, SEGMENTS + 1):
		var u := float(n) / SEGMENTS
		var p := a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
		var mid := (prev + p) * 0.5
		var dir := p - prev
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
		out.append(Transform3D(basis * Basis.from_scale(Vector3(0.045, 0.045, dir.length())), mid))
		prev = p

func _multi(mesh: Mesh, color: Color, transforms: Array[Transform3D], shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Street-food carts with umbrellas, and spirit houses, on the sidewalks.
func _build_street_stuff(detail: bool) -> void:
	var st := MeshBuilder.begin()
	for i in range(-GRID, GRID):
		for j in range(-GRID, GRID):
			if Vector2i(i, j) == TEMPLE_BLOCK or Vector2i(i, j) == City.SHOP_BLOCK:
				continue
			for edge in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
				if City.is_place_front(i, j, edge):
					continue
				_frame(i, j, edge)
				_st = st
				if rng.randf() < (0.45 if detail else 0.25):
					_food_cart(-1.0, (9.0 if rng.randf() < 0.5 else -9.0))
				if rng.randf() < 0.12:
					_spirit_house(-0.6, 15.5)
	_commit(st, 160.0)

func _food_cart(x: float, t: float) -> void:
	var body: Color = [Color("c9ced3"), Color("d64545"), Color("3a7bd5"), Color("e3a72f")][rng.randi() % 4]
	_box(x, t, 0.35, 0.9, 0.9, 1.6, body)
	_box(x, t, 1.25, 0.95, 0.06, 1.65, Color("e8e8e6"))
	_box(x - 0.2, t, 1.31, 0.5, 0.3, 1.4, Color("9aa3a8"))      # glass display
	for w in [-0.6, 0.6]:
		_box(x, t + w, 0.0, 0.9, 0.35, 0.12, Color("222"))
	var umbrella: Color = [Color("e74c3c"), Color("2e86c1"), Color("27ae60"), Color("f39c12")][rng.randi() % 4]
	MeshBuilder.add(_st, _shape("cyl"), Transform3D(Basis.from_scale(Vector3(0.06, 2.6, 0.06)), _p(x, t, 1.3) + Vector3(0, 1.3, 0)), Color("666"))
	MeshBuilder.add(_st, _shape("cone"), Transform3D(Basis.from_scale(Vector3(2.8, 0.7, 2.8)), _p(x, t, 2.9)), umbrella)

func _spirit_house(x: float, t: float) -> void:
	_box(x, t, 0, 0.35, 1.3, 0.35, Color("f3efe6"))                 # post
	_box(x, t, 1.3, 0.9, 0.12, 0.9, Color("b8862d"))
	_box(x, t, 1.42, 0.6, 0.6, 0.6, Color("c0392b"))                 # house
	MeshBuilder.add(_st, _shape("prism"), Transform3D(Basis.from_scale(Vector3(0.8, 0.5, 0.8)), _p(x, t, 2.27)), GOLD)
	_box(x - 0.45, t, 1.42, 0.12, 0.25, 0.5, Color("ffcf6b"))       # offerings
