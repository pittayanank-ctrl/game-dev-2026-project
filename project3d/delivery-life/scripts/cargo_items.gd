extends RefCounted
## What the rider is actually carrying: every order gets an item that fits its type (food bag,
## documents, flowers, a wedding cake...). Each item is a small low-poly model built from coloured
## primitives into ONE mesh (vertex colours, see mesh_builder.gd), cached per item.
## Models sit on the passenger seat: origin = middle of a 0.34 m box, so the bottom is y -0.17.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const BOTTOM := -0.17

# Item id -> name shown in the app, and the order types it can turn up for.
const ITEMS := {
	"food": {"name": "Food order", "types": ["standard", "express"]},
	"boba": {"name": "Bubble tea", "types": ["standard", "express"]},
	"parcel": {"name": "Parcel", "types": ["standard"]},
	"groceries": {"name": "Groceries", "types": ["standard"]},
	"documents": {"name": "Documents", "types": ["express"]},
	"medicine": {"name": "Medicine", "types": ["express"]},
	"flowers": {"name": "Flowers", "types": ["fragile", "vip"]},
	"glassware": {"name": "Glassware", "types": ["fragile"]},
	"electronics": {"name": "Electronics", "types": ["fragile", "vip"]},
	"parcels": {"name": "Parcels", "types": ["multi"]},
	"gift": {"name": "Luxury gift", "types": ["vip"]},
	"fruit": {"name": "Fruit basket", "types": ["vip", "standard"]},
	"cake": {"name": "Wedding cake", "types": ["cake"]},
	"pinto": {"name": "Food offering", "types": ["temple"]},
	"race": {"name": "Express parcel", "types": ["race"]},
}

const CARDBOARD := Color("b98a56")
const TAPE := Color("e8d9b0")
const STRAP := Color("1d1d1f")

static var _meshes := {}

## A random item for an order type.
static func pick(type: String, rng: RandomNumberGenerator) -> String:
	var options: Array = []
	for id in ITEMS:
		if type in ITEMS[id]["types"]:
			options.append(id)
	return options[rng.randi() % options.size()] if not options.is_empty() else "parcel"

static func item_name(id: String) -> String:
	return ITEMS.get(id, ITEMS["parcel"])["name"]

## The item's mesh (built once, then shared).
static func mesh(id: String) -> ArrayMesh:
	if not _meshes.has(id):
		var st := MeshBuilder.begin()
		match id:
			"food": _food(st)
			"boba": _boba(st)
			"groceries": _groceries(st)
			"documents": _documents(st)
			"medicine": _medicine(st)
			"flowers": _flowers(st)
			"glassware": _glassware(st)
			"electronics": _electronics(st)
			"parcels": _parcels(st)
			"gift": _gift(st)
			"fruit": _fruit(st)
			"cake": _cake(st)
			"pinto": _pinto(st)
			"race": _race(st)
			_: _parcel(st, Vector3(0, BOTTOM, 0), Vector3(0.42, 0.34, 0.42), TAPE)
		var m := st.commit()
		m.surface_set_material(0, MeshBuilder.vertex_color_material())
		_meshes[id] = m
	return _meshes[id]

# ------------------------------------------------------------------ shapes

static func _arrays(kind: String) -> Array:
	match kind:
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 12
			c.rings = 1
			return MeshBuilder._arrays("cargo_cyl", c)
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 10
			s.rings = 5
			return MeshBuilder._arrays("cargo_sphere", s)
		"cone":
			var k := CylinderMesh.new()
			k.top_radius = 0.5
			k.bottom_radius = 0.0
			k.height = 1.0
			k.radial_segments = 10
			k.rings = 1
			return MeshBuilder._arrays("cargo_cone", k)
	return MeshBuilder.unit_box()

static func _box(st: SurfaceTool, bottom_centre: Vector3, size: Vector3, col: Color) -> void:
	MeshBuilder.add_box(st, bottom_centre + Vector3(0, size.y * 0.5, 0), size, col)

static func _shape(st: SurfaceTool, kind: String, centre: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	MeshBuilder.add(st, _arrays(kind), Transform3D(basis * Basis.from_scale(size), centre), col)

## Bungee strap over the load, front to back, `h` = load height.
static func _strap(st: SurfaceTool, h: float, w: float, d: float) -> void:
	_box(st, Vector3(0, BOTTOM + h, 0), Vector3(0.04, 0.012, d + 0.02), STRAP)
	_box(st, Vector3(0, BOTTOM, -d * 0.5 - 0.006), Vector3(0.04, h, 0.012), STRAP)
	_box(st, Vector3(0, BOTTOM, d * 0.5 - 0.006), Vector3(0.04, h, 0.012), STRAP)

## Cardboard box with a tape stripe over the top (bottom-centre at `at`).
static func _parcel(st: SurfaceTool, at: Vector3, size: Vector3, tape: Color) -> void:
	_box(st, at, size, CARDBOARD)
	_box(st, at + Vector3(0, size.y, 0), Vector3(0.07, 0.006, size.z + 0.006), tape)
	_box(st, at + Vector3(0, 0, -size.z * 0.5 - 0.003), Vector3(0.07, size.y, 0.006), tape)
	_box(st, at + Vector3(0, 0, size.z * 0.5 - 0.003), Vector3(0.07, size.y, 0.006), tape)
	# Shipping label on the back.
	_box(st, at + Vector3(0.09, size.y * 0.45, size.z * 0.5), Vector3(0.12, 0.09, 0.006), Color("f5f5f0"))

# ------------------------------------------------------------------ items

static func _food(st: SurfaceTool) -> void:
	# Insulated delivery bag: rider-app green with a lid seam, logo and reflective stripe.
	var g := Color("16a34a")
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.44, 0.42, 0.44), g)
	_box(st, Vector3(0, BOTTOM + 0.42, 0), Vector3(0.45, 0.03, 0.45), g.darkened(0.25))
	_box(st, Vector3(0, BOTTOM + 0.16, 0.222), Vector3(0.3, 0.05, 0.006), Color("e8e8e8"))
	_shape(st, "cyl", Vector3(0, BOTTOM + 0.3, 0.224), Vector3(0.12, 0.006, 0.12), Color("fde047"), Basis(Vector3.RIGHT, PI * 0.5))
	_box(st, Vector3(0, BOTTOM + 0.45, 0), Vector3(0.18, 0.02, 0.04), STRAP)   # handle

static func _boba(st: SurfaceTool) -> void:
	# Cup carrier with four bubble teas (domed lids, straws, tapioca at the bottom).
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.3, 0.05, 0.3), Color("d6c29a"))
	var teas := [Color("c08552"), Color("e9a3c9"), Color("8bc34a"), Color("d2b48c")]
	var k := 0
	for x in [-0.075, 0.075]:
		for z in [-0.075, 0.075]:
			var c := Vector3(x, BOTTOM + 0.12, z)
			_shape(st, "cyl", c, Vector3(0.11, 0.17, 0.11), teas[k])
			_shape(st, "cyl", c + Vector3(0, -0.065, 0), Vector3(0.112, 0.04, 0.112), Color("2b1d14"))
			_shape(st, "sphere", c + Vector3(0, 0.09, 0), Vector3(0.115, 0.05, 0.115), Color(0.95, 0.95, 0.95))
			_box(st, c + Vector3(0.02, 0.08, 0), Vector3(0.012, 0.12, 0.012), Color("e53935"))
			k += 1

static func _groceries(st: SurfaceTool) -> void:
	# Plastic basket with leafy greens, carrots, bread and a milk carton.
	var basket := Color("1e88e5")
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.44, 0.03, 0.34), basket)
	for s in [-1.0, 1.0]:
		_box(st, Vector3(0.21 * s, BOTTOM, 0), Vector3(0.02, 0.2, 0.34), basket)
		_box(st, Vector3(0, BOTTOM, 0.16 * s), Vector3(0.44, 0.2, 0.02), basket)
	_shape(st, "sphere", Vector3(-0.1, BOTTOM + 0.22, -0.05), Vector3(0.18, 0.16, 0.18), Color("4caf50"))
	_shape(st, "sphere", Vector3(-0.06, BOTTOM + 0.25, 0.06), Vector3(0.12, 0.1, 0.12), Color("66bb6a"))
	for i in 3:
		_shape(st, "cone", Vector3(0.06 + i * 0.035, BOTTOM + 0.22, -0.06), Vector3(0.04, 0.2, 0.04), Color("f57c00"), Basis(Vector3.RIGHT, PI))
	_box(st, Vector3(0.11, BOTTOM + 0.03, 0.05), Vector3(0.1, 0.28, 0.08), Color("f5f5f5"))
	_box(st, Vector3(0.11, BOTTOM + 0.2, 0.05), Vector3(0.102, 0.05, 0.082), Color("1976d2"))
	_shape(st, "sphere", Vector3(0.0, BOTTOM + 0.22, 0.09), Vector3(0.24, 0.1, 0.1), Color("d7a35b"), Basis(Vector3.UP, 0.4))

static func _documents(st: SurfaceTool) -> void:
	# Waterproof document case with a stack of envelopes on top and a clasp.
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.4, 0.09, 0.3), Color("37474f"))
	_box(st, Vector3(0, BOTTOM + 0.09, 0), Vector3(0.36, 0.02, 0.26), Color("c8a46e"))
	_box(st, Vector3(0.01, BOTTOM + 0.11, -0.01), Vector3(0.34, 0.02, 0.24), Color("f1e3c6"))
	_box(st, Vector3(-0.01, BOTTOM + 0.13, 0.01), Vector3(0.35, 0.02, 0.25), Color("c8a46e"))
	_box(st, Vector3(0, BOTTOM + 0.15, 0), Vector3(0.08, 0.004, 0.08), Color("c62828"))   # wax seal
	_box(st, Vector3(0, BOTTOM + 0.03, 0.15), Vector3(0.06, 0.04, 0.012), Color("bdbdbd"))
	_strap(st, 0.15, 0.4, 0.3)

static func _medicine(st: SurfaceTool) -> void:
	# White pharmacy cooler with a red cross on the top and the sides.
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.36, 0.28, 0.3), Color("f5f5f5"))
	_box(st, Vector3(0, BOTTOM + 0.28, 0), Vector3(0.37, 0.03, 0.31), Color("e0e0e0"))
	var red := Color("e53935")
	_box(st, Vector3(0, BOTTOM + 0.31, 0), Vector3(0.18, 0.006, 0.06), red)
	_box(st, Vector3(0, BOTTOM + 0.31, 0), Vector3(0.06, 0.006, 0.18), red)
	for s in [-1.0, 1.0]:
		_box(st, Vector3(0.181 * s, BOTTOM + 0.08, 0), Vector3(0.006, 0.14, 0.05), red)
		_box(st, Vector3(0.181 * s, BOTTOM + 0.125, 0), Vector3(0.006, 0.05, 0.14), red)
	_box(st, Vector3(0, BOTTOM + 0.34, 0), Vector3(0.14, 0.025, 0.03), Color("9e9e9e"))   # handle

static func _flowers(st: SurfaceTool) -> void:
	# Bouquet in a paper cone standing in a small box, roses and greenery on top.
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.26, 0.12, 0.26), Color("f8bbd0"))
	_shape(st, "cone", Vector3(0, BOTTOM + 0.3, 0), Vector3(0.3, 0.38, 0.3), Color("f3e5d0"))
	var blooms := [Color("e91e63"), Color("f44336"), Color("ffeb3b"), Color("ffffff"), Color("ab47bc"), Color("ff7043")]
	var k := 0
	for a in range(0, 360, 60):
		var r := deg_to_rad(a)
		_shape(st, "sphere", Vector3(cos(r) * 0.09, BOTTOM + 0.5, sin(r) * 0.09), Vector3(0.09, 0.08, 0.09), blooms[k % blooms.size()])
		_shape(st, "sphere", Vector3(cos(r + 0.5) * 0.14, BOTTOM + 0.46, sin(r + 0.5) * 0.14), Vector3(0.07, 0.04, 0.07), Color("43a047"))
		k += 1
	_shape(st, "sphere", Vector3(0, BOTTOM + 0.53, 0), Vector3(0.1, 0.09, 0.1), Color("e91e63"))
	_box(st, Vector3(0, BOTTOM + 0.27, 0), Vector3(0.31, 0.04, 0.02), Color("d81b60"))   # ribbon

static func _glassware(st: SurfaceTool) -> void:
	# Box with red FRAGILE bands and a wine-glass symbol, "this way up" arrows.
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.4, 0.34, 0.4), Color("d9b98a"))
	var red := Color("d32f2f")
	_box(st, Vector3(0, BOTTOM + 0.12, 0), Vector3(0.406, 0.08, 0.406), red)
	for s in [-1.0, 1.0]:
		var face := Vector3(0, BOTTOM + 0.22, 0.203 * s)
		_box(st, face, Vector3(0.016, 0.06, 0.004), Color("fafafa"))          # stem
		_box(st, face + Vector3(0, 0.06, 0), Vector3(0.06, 0.04, 0.004), Color("fafafa"))   # bowl
		_box(st, face + Vector3(0, -0.005, 0), Vector3(0.05, 0.01, 0.004), Color("fafafa"))  # foot
	_box(st, Vector3(0, BOTTOM + 0.34, 0), Vector3(0.406, 0.006, 0.07), red)
	_strap(st, 0.34, 0.4, 0.4)

static func _electronics(st: SurfaceTool) -> void:
	# Black retail box with a product picture (a screen) and a brand stripe.
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.44, 0.32, 0.14), Color("212121"))
	for s in [-1.0, 1.0]:
		_box(st, Vector3(0, BOTTOM + 0.06, 0.071 * s), Vector3(0.32, 0.2, 0.004), Color("0d47a1"))
		_box(st, Vector3(0, BOTTOM + 0.1, 0.0725 * s), Vector3(0.2, 0.1, 0.004), Color("4fc3f7"))
	_box(st, Vector3(0, BOTTOM + 0.28, 0), Vector3(0.446, 0.03, 0.146), Color("e53935"))
	_box(st, Vector3(0, BOTTOM + 0.32, 0), Vector3(0.12, 0.02, 0.02), Color("757575"))   # carry handle

static func _parcels(st: SurfaceTool) -> void:
	# Two or three parcels stacked for a multi-drop run, strapped down.
	_parcel(st, Vector3(0, BOTTOM, 0), Vector3(0.42, 0.2, 0.42), Color("8bc34a"))
	_parcel(st, Vector3(-0.04, BOTTOM + 0.2, 0.03), Vector3(0.3, 0.16, 0.3), Color("8bc34a"))
	_parcel(st, Vector3(0.05, BOTTOM + 0.36, -0.02), Vector3(0.18, 0.1, 0.2), Color("8bc34a"))
	_strap(st, 0.46, 0.42, 0.42)

static func _gift(st: SurfaceTool) -> void:
	# Glossy black gift box with a gold ribbon and bow.
	var gold := Color("ffd23f")
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.36, 0.26, 0.36), Color("1a1a1a"))
	_box(st, Vector3(0, BOTTOM + 0.26, 0), Vector3(0.38, 0.06, 0.38), Color("111111"))
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.05, 0.322, 0.384), gold)
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.384, 0.322, 0.05), gold)
	for s in [-1.0, 1.0]:
		_shape(st, "sphere", Vector3(0.06 * s, BOTTOM + 0.36, 0), Vector3(0.12, 0.07, 0.07), gold, Basis(Vector3.FORWARD, 0.4 * s))
	_shape(st, "sphere", Vector3(0, BOTTOM + 0.35, 0), Vector3(0.05, 0.05, 0.05), gold.darkened(0.15))

static func _fruit(st: SurfaceTool) -> void:
	# Woven basket with a pineapple, mangoes, oranges and grapes, wrapped in cellophane ribbon.
	var wicker := Color("a1793f")
	_shape(st, "cyl", Vector3(0, BOTTOM + 0.08, 0), Vector3(0.4, 0.16, 0.34), wicker)
	_shape(st, "cyl", Vector3(0, BOTTOM + 0.165, 0), Vector3(0.42, 0.02, 0.36), wicker.darkened(0.2))
	_shape(st, "sphere", Vector3(-0.08, BOTTOM + 0.3, 0), Vector3(0.13, 0.22, 0.13), Color("f9a825"))   # pineapple
	_shape(st, "cone", Vector3(-0.08, BOTTOM + 0.46, 0), Vector3(0.1, 0.12, 0.1), Color("2e7d32"), Basis(Vector3.RIGHT, PI))
	_shape(st, "sphere", Vector3(0.08, BOTTOM + 0.22, -0.07), Vector3(0.1, 0.1, 0.1), Color("fb8c00"))
	_shape(st, "sphere", Vector3(0.1, BOTTOM + 0.22, 0.07), Vector3(0.12, 0.08, 0.09), Color("fdd835"))   # mango
	_shape(st, "sphere", Vector3(0.0, BOTTOM + 0.21, 0.1), Vector3(0.1, 0.1, 0.1), Color("fb8c00"))
	for i in 5:
		_shape(st, "sphere", Vector3(0.12 + (i % 2) * 0.03, BOTTOM + 0.24 + i * 0.02, -0.0), Vector3(0.04, 0.04, 0.04), Color("6a1b9a"))
	_box(st, Vector3(0, BOTTOM + 0.15, 0), Vector3(0.43, 0.03, 0.03), Color("e53935"))

static func _cake(st: SurfaceTool) -> void:
	# Pink cake box with a clear window: three white tiers with pink trim and a topper.
	var pink := Color("f48fb1")
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.44, 0.03, 0.44), pink)
	for t in 3:
		var r := 0.36 - t * 0.09
		var y := BOTTOM + 0.03 + t * 0.12
		_shape(st, "cyl", Vector3(0, y + 0.055, 0), Vector3(r, 0.11, r), Color("fff8f0"))
		_shape(st, "cyl", Vector3(0, y + 0.005, 0), Vector3(r + 0.01, 0.015, r + 0.01), pink)
	_shape(st, "sphere", Vector3(0, BOTTOM + 0.42, 0), Vector3(0.05, 0.05, 0.05), Color("e91e63"))
	# Clear box: thin frame and tinted panels.
	var frame := pink
	for x in [-0.215, 0.215]:
		for z in [-0.215, 0.215]:
			_box(st, Vector3(x, BOTTOM, z), Vector3(0.015, 0.46, 0.015), frame)
	_box(st, Vector3(0, BOTTOM + 0.46, 0), Vector3(0.445, 0.015, 0.445), frame)
	_box(st, Vector3(0, BOTTOM + 0.475, 0), Vector3(0.1, 0.015, 0.02), Color("ffd23f"))   # gold sticker

static func _pinto(st: SurfaceTool) -> void:
	# Thai "pinto" food carrier: stacked enamel pots in a frame with a handle, marigold garland.
	var pot := Color("ef6c00")
	var steel := Color("cfd8dc")
	for i in 4:
		var y := BOTTOM + 0.04 + i * 0.085
		_shape(st, "cyl", Vector3(0, y + 0.04, 0), Vector3(0.24, 0.075, 0.24), pot if i % 2 == 0 else Color("ffb300"))
		_shape(st, "cyl", Vector3(0, y + 0.08, 0), Vector3(0.25, 0.012, 0.25), steel)
	_shape(st, "cyl", Vector3(0, BOTTOM + 0.39, 0), Vector3(0.2, 0.04, 0.2), steel)   # lid
	for s in [-1.0, 1.0]:
		_box(st, Vector3(0.135 * s, BOTTOM, 0), Vector3(0.015, 0.5, 0.03), steel)
	_box(st, Vector3(0, BOTTOM + 0.49, 0), Vector3(0.285, 0.02, 0.03), steel)
	_shape(st, "cyl", Vector3(0, BOTTOM + 0.47, 0), Vector3(0.08, 0.05, 0.05), Color("8d6e63"), Basis(Vector3.FORWARD, PI * 0.5))
	# Marigold garland hanging from the handle.
	for k in 6:
		var a := deg_to_rad(-60.0 + k * 24.0)
		_shape(st, "sphere", Vector3(sin(a) * 0.12, BOTTOM + 0.44 - cos(a) * 0.06, 0.13), Vector3(0.05, 0.05, 0.05), Color("ffa000"))
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.3, 0.04, 0.3), Color("5d4037"))   # tray

static func _race(st: SurfaceTool) -> void:
	# Jet's challenge parcel: purple express box with a lightning bolt and chequered band.
	_box(st, Vector3(0, BOTTOM, 0), Vector3(0.4, 0.3, 0.36), Color("7b1fa2"))
	for i in 8:
		var c := Color("fafafa") if i % 2 == 0 else Color("212121")
		_box(st, Vector3(-0.175 + i * 0.05, BOTTOM + 0.3, 0), Vector3(0.05, 0.006, 0.364), c)
	for s in [-1.0, 1.0]:
		var face := Vector3(0, BOTTOM + 0.15, 0.181 * s)
		_box(st, face + Vector3(0.02, 0.05, 0), Vector3(0.05, 0.1, 0.004), Color("ffeb3b"), )
		_box(st, face + Vector3(-0.02, -0.04, 0), Vector3(0.05, 0.1, 0.004), Color("ffeb3b"))
		_box(st, face + Vector3(0, 0.0, 0), Vector3(0.09, 0.025, 0.004), Color("ffeb3b"))
	_strap(st, 0.3, 0.4, 0.36)
