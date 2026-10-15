extends RefCounted
## Builds one mesh out of many coloured primitives (boxes, capsules, spheres) so a whole car or
## pedestrian is a single draw call instead of one per part. Colours are stored per vertex, so use
## a material with vertex_color_use_as_albedo.

static var _cache := {}

static func _arrays(key: String, mesh: PrimitiveMesh) -> Array:
	if not _cache.has(key):
		_cache[key] = mesh.get_mesh_arrays()
	return _cache[key]

static func unit_box() -> Array:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return _arrays("box", b)

## Append a primitive's triangles to `st`, transformed by `xf` and painted `color`.
static func add(st: SurfaceTool, arrays: Array, xf: Transform3D, color: Color) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	for i in indices:
		st.set_color(color)
		st.set_normal((nb * normals[i]).normalized())
		st.add_vertex(xf * verts[i])

static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	add(st, unit_box(), Transform3D(Basis.from_scale(size), center), color)

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Material that takes its colour from the vertices (shared by every built mesh).
static func vertex_color_material() -> StandardMaterial3D:
	if not _cache.has("vc_mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true   # colours are picked in sRGB, like albedo_color
		_cache["vc_mat"] = m
	return _cache["vc_mat"]
