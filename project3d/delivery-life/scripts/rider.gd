extends Node3D
## Puts the character on the bike in a riding pose.
## The FBX is a Mixamo T-pose rig (~7.7 units tall), so the pose is built in code:
## hips on the seat, hands on the grips and feet on the floorboard via two-bone IK.
## All points below are in the bike's local space (ground = y 0, forward = -Z).

@export var model_scene: PackedScene
@export var target_height := 1.84
@export var source_height := 7.68
@export var seat_point := Vector3(0.0, 0.93, 0.14)    # hips sit on (not in) the seat
@export var grip_left := Vector3(-0.3, 1.06, -0.31)
@export var grip_right := Vector3(0.3, 1.06, -0.31)
@export var foot_left := Vector3(-0.17, 0.56, -0.24)    # ankles on the floorboard, knees bent
@export var foot_right := Vector3(0.17, 0.56, -0.24)
@export var lean_degrees := 22.0                      # torso leans towards the handlebars
@export var body_lean_side := 0.25     # how far the torso leans sideways into a turn
@export var head_turn := 0.35          # how far the head looks toward the turn

const RiderOutfit := preload("res://scripts/rider_outfit.gd")

var _sk: Skeleton3D
var _model: Node3D
var hide_head := false                 # first-person view: shrink the head so it doesn't block it

func _ready() -> void:
	if model_scene == null:
		return
	var model := model_scene.instantiate() as Node3D
	_model = model
	add_child(model)
	# The FBX ships with its own light and a T-pose animation; drop both.
	for n in model.find_children("*", "Light3D", true, false):
		n.queue_free()
	for n in model.find_children("*", "AnimationPlayer", true, false):
		n.queue_free()

	# Face the bike's forward (-Z); the rig faces +Z.
	var s := target_height / source_height
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * s), Vector3.ZERO)
	_sk = model.find_children("*", "Skeleton3D", true, false)[0]
	# Jacket, trousers, gloves, shoes and a helmet (see rider_outfit.gd).
	var body := model.find_children("*", "MeshInstance3D", true, false)
	if not body.is_empty():
		RiderOutfit.apply(body[0], _sk)
	fit(seat_point, grip_left, grip_right, foot_left, foot_right)

## Sit on a (different) bike: hips on `seat`, hands on the grips, feet on the floorboard.
func fit(seat: Vector3, gl: Vector3, gr: Vector3, fl: Vector3, fr: Vector3) -> void:
	seat_point = seat
	grip_left = gl
	grip_right = gr
	foot_left = fl
	foot_right = fr
	if _sk == null:
		return
	_sk.reset_bone_poses()
	# Move the model so the hips land on the seat.
	var hips := _sk.find_bone("mixamorig_Hips")
	var hips_now: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(hips).origin
	# Work in this node's own space: the bike may be facing any direction when this runs.
	_model.position += seat_point - to_local(hips_now)
	update_pose(0.0, 0.0, grip_left, grip_right)

func _to_sk(p: Vector3) -> Vector3:
	return _sk.global_transform.affine_inverse() * to_global(p)

func _dir_to_sk(d: Vector3) -> Vector3:
	return (_sk.global_transform.affine_inverse().basis * global_transform.basis * d).normalized()

## Rebuild the riding pose. `steer` / `lean` are the bike's smoothed values in -1..1 (positive = left);
## `gl` / `gr` are the current grip positions (they move with the handlebars).
func update_pose(steer: float, lean_amount: float, gl: Vector3, gr: Vector3) -> void:
	if _sk == null:
		return
	_sk.reset_bone_poses()
	if hide_head:
		var head := _sk.find_bone("mixamorig_Head")
		if head >= 0:
			_sk.set_bone_pose_scale(head, Vector3.ONE * 0.01)
	var up := Vector3.UP
	var fwd := Vector3.FORWARD    # bike-local
	var lean := deg_to_rad(lean_degrees)

	# Torso leans a little into the turn, and the head looks where the bike is going.
	_aim("Spine", "Spine1", up * cos(lean) + fwd * sin(lean) + Vector3(-lean_amount * body_lean_side, 0, 0))
	_aim("Neck", "Head", up + fwd * 0.15 + Vector3(-steer * head_turn, 0, 0))

	# Pole vectors keep elbows out/down and knees forward/out.
	_two_bone("LeftArm", "LeftForeArm", "LeftHand", _to_sk(gl), _dir_to_sk(Vector3(-0.8, -0.7, 0.4)))
	_two_bone("RightArm", "RightForeArm", "RightHand", _to_sk(gr), _dir_to_sk(Vector3(0.8, -0.7, 0.4)))
	_two_bone("LeftUpLeg", "LeftLeg", "LeftFoot", _to_sk(foot_left), _dir_to_sk(Vector3(-0.25, 0.4, -1)))
	_two_bone("RightUpLeg", "RightLeg", "RightFoot", _to_sk(foot_right), _dir_to_sk(Vector3(0.25, 0.4, -1)))
	_aim("LeftFoot", "LeftToeBase", fwd + Vector3(0, -0.1, 0))
	_aim("RightFoot", "RightToeBase", fwd + Vector3(0, -0.1, 0))

## Rotate `bone` so that the direction to `child` points along `dir` (bike-local space).
func _aim(bone_name: String, child_name: String, dir: Vector3) -> void:
	_aim_sk(_sk.find_bone("mixamorig_" + bone_name), _sk.find_bone("mixamorig_" + child_name), _dir_to_sk(dir))

func _aim_sk(bone: int, child: int, dir: Vector3) -> void:
	if bone < 0 or child < 0:
		return
	var gp := _sk.get_bone_global_pose(bone)
	var cur := (_sk.get_bone_global_pose(child).origin - gp.origin).normalized()
	var new_basis := Basis(Quaternion(cur, dir.normalized())) * gp.basis
	var parent := _sk.get_bone_parent(bone)
	var parent_basis := _sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_rotation(bone, (parent_basis.inverse() * new_basis).orthonormalized().get_rotation_quaternion())

## Analytic two-bone IK (shoulder/elbow/hand or hip/knee/ankle) in skeleton space.
func _two_bone(root_name: String, mid_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var root := _sk.find_bone("mixamorig_" + root_name)
	var mid := _sk.find_bone("mixamorig_" + mid_name)
	var end := _sk.find_bone("mixamorig_" + end_name)
	if root < 0 or mid < 0 or end < 0:
		return
	var r := _sk.get_bone_global_pose(root).origin
	var m := _sk.get_bone_global_pose(mid).origin
	var e := _sk.get_bone_global_pose(end).origin
	var l1 := r.distance_to(m)
	var l2 := m.distance_to(e)
	var d := target - r
	var dist := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var elbow := r + dir * a + perp * h
	_aim_sk(root, mid, elbow - r)
	_aim_sk(mid, end, r + dir * dist - elbow)
