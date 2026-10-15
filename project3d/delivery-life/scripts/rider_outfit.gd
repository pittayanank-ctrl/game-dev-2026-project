extends RefCounted
## Rider outfit: the character model has one untextured mesh, so the clothes are painted as vertex
## colours chosen by the bone each vertex follows (jacket on the spine and arms, trousers on the
## legs, gloves, sneakers, skin on the neck and face) plus a reflective stripe across the jacket.
## The helmet is a separate low-poly model attached to the head bone, so it follows every pose
## (and shrinks away with the head in first-person view).
## Both meshes are built once and shared by every rider.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const JACKET := Color("16a34a")      # rider-app green, like the delivery bag
const STRIPE := Color("e2e8f0")      # reflective band
const CUFF := Color("14532d")
const PANTS := Color("1e2a3a")
const GLOVES := Color("1c1c1e")
const SHOES := Color("2f343c")   # dark sneakers (blend softly into the trousers)
const SOLE := Color("151515")   # low-poly shins run knee-to-sole, so the sole must stay dark
const SKIN := Color("e3b48f")
const HELMET := Color("16a34a")
const HELMET_STRIPE := Color("f5f5f5")
const VISOR := Color("20262e")

# Bone name (without "mixamorig_") -> clothing region.
const REGIONS := {
	"Hips": "pants", "Spine": "jacket", "Spine1": "jacket", "Spine2": "jacket",
	"Neck": "skin", "Head": "skin", "HeadTop_End": "skin",
	"LeftShoulder": "jacket", "LeftArm": "jacket", "LeftForeArm": "cuff", "LeftHand": "gloves",
	"RightShoulder": "jacket", "RightArm": "jacket", "RightForeArm": "cuff", "RightHand": "gloves",
	"LeftUpLeg": "pants", "LeftLeg": "pants", "LeftFoot": "shoes", "LeftToeBase": "shoes", "LeftToe_End": "shoes",
	"RightUpLeg": "pants", "RightLeg": "pants", "RightFoot": "shoes", "RightToeBase": "shoes", "RightToe_End": "shoes",
}
const TORSO := ["Spine", "Spine1", "Spine2"]

static var _body_mesh: ArrayMesh
static var _helmet_mesh: ArrayMesh

## Dress a freshly instanced character (MeshInstance3D with a Skin, and its Skeleton3D).
static func apply(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> void:
	if _body_mesh == null:
		_body_mesh = _paint(mesh_instance, skeleton)
	mesh_instance.mesh = _body_mesh
	var attach := BoneAttachment3D.new()
	attach.bone_name = "mixamorig_Head"
	skeleton.add_child(attach)
	var helmet := MeshInstance3D.new()
	helmet.mesh = _helmet()
	attach.add_child(helmet)

static func _bind_name(skin: Skin, skeleton: Skeleton3D, bind: int) -> String:
	var n := skin.get_bind_name(bind)
	if n == "":
		n = skeleton.get_bone_name(skin.get_bind_bone(bind))
	return n.replace("mixamorig_", "")

static func _paint(mi: MeshInstance3D, sk: Skeleton3D) -> ArrayMesh:
	var src: Mesh = mi.mesh
	var skin: Skin = mi.skin
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	# Main bone of each vertex, and the height range of the torso and the feet (mesh space, Z up).
	var main: Array[String] = []
	var torso_lo := INF
	var torso_hi := -INF
	var foot_lo := INF
	for i in verts.size():
		var best := 0
		var bw := -1.0
		for k in per:
			if weights[i * per + k] > bw:
				bw = weights[i * per + k]
				best = bones[i * per + k]
		var name := _bind_name(skin, sk, best)
		main.append(name)
		var h := verts[i].z
		if name in TORSO:
			torso_lo = minf(torso_lo, h)
			torso_hi = maxf(torso_hi, h)
		if REGIONS.get(name, "") == "shoes":
			foot_lo = minf(foot_lo, h)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var region: String = REGIONS.get(main[i], "jacket")
		var h := verts[i].z
		var col := JACKET
		match region:
			"jacket":
				col = JACKET
				# Reflective band across the chest and back.
				if main[i] in TORSO:
					var t := (h - torso_lo) / maxf(torso_hi - torso_lo, 0.0001)
					if t > 0.52 and t < 0.66:
						col = STRIPE
			"cuff": col = CUFF
			"pants": col = PANTS
			"gloves": col = GLOVES
			"shoes": col = SOLE if h < foot_lo + 0.0012 else SHOES
			"skin": col = SKIN
		colors[i] = col
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	var flags: int = src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.8
	out.surface_set_material(0, mat)
	return out

# ------------------------------------------------------------------ helmet

static func _sphere(hemi: bool) -> Array:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 0.5 if hemi else 1.0
	s.is_hemisphere = hemi
	s.radial_segments = 20
	s.rings = 8
	return MeshBuilder._arrays("helmet_hemi" if hemi else "helmet_sphere", s)

## Open-face helmet in head-bone space (units of the FBX: the head is about 1.8 wide and 2 tall,
## face towards +Z, top of the head at y 1.75).
static func _helmet() -> ArrayMesh:
	if _helmet_mesh:
		return _helmet_mesh
	var st := MeshBuilder.begin()
	# Dome over the top of the head, from the brow up.
	MeshBuilder.add(st, _sphere(true), Transform3D(Basis.from_scale(Vector3(2.05, 2.9, 2.15)), Vector3(0, 0.5, 0.2)), HELMET)
	# Back and sides, down over the ears (the face stays open at the front).
	MeshBuilder.add(st, _sphere(false), Transform3D(Basis.from_scale(Vector3(2.0, 1.9, 1.75)), Vector3(0, 0.75, -0.22)), HELMET)
	# White stripe over the top, front to back.
	MeshBuilder.add(st, _sphere(true), Transform3D(Basis.from_scale(Vector3(0.42, 2.98, 2.2)), Vector3(0, 0.5, 0.2)), HELMET_STRIPE)
	# Visor peak over the forehead.
	MeshBuilder.add(st, _sphere(false), Transform3D(Basis(Vector3.RIGHT, 0.25) * Basis.from_scale(Vector3(1.75, 0.32, 1.1)), Vector3(0, 1.05, 0.85)), VISOR)
	# Chin strap.
	MeshBuilder.add_box(st, Vector3(0, 0.05, -0.05), Vector3(1.62, 0.08, 0.08), Color("111111"))
	_helmet_mesh = st.commit()
	var mat := MeshBuilder.vertex_color_material().duplicate() as StandardMaterial3D
	mat.roughness = 0.35
	mat.metallic = 0.1
	_helmet_mesh.surface_set_material(0, mat)
	return _helmet_mesh
