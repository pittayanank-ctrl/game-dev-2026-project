extends Node3D
## Third-person camera: orbits the bike with the mouse, follows smoothly, and swings back
## behind the bike after a moment without mouse input. A SpringArm keeps it out of buildings.
## Mouse wheel zooms in/out.
## Mouse works like Roblox: the cursor is visible and you hold the right button to turn the
## camera; Shift toggles Mouse Lock (cursor locked to the centre, mouse turns the camera).
## V (or zooming all the way in) switches to first person: the camera sits at the rider's eyes,
## leans and wheelies with the bike, and the mouse / right stick turns the rider's head.

@export var distance := 6.0
@export var min_distance := 2.5
@export var max_distance := 14.0
@export var zoom_step := 0.7             # metres per wheel notch
@export var zoom_smoothing := 8.0
@export var height := 1.6
@export var default_pitch := 14.0        # degrees above the horizon
@export var min_pitch := -10.0
@export var max_pitch := 70.0
@export var mouse_sensitivity := 0.003
@export var follow_speed := 10.0
@export var recenter_delay := 1.5        # seconds without mouse input before recentring
@export var recenter_speed := 3.0

var target: Node3D
var _arm: SpringArm3D
var _cam: Camera3D
var _yaw_offset := 0.0                   # orbit angle relative to the bike's heading
var _pitch := 0.0                        # radians
var _idle_time := 0.0
var _target_distance := 0.0
var locked := false                      # Mouse Lock (Shift): cursor captured, mouse turns the camera
var _dragging := false                   # right mouse button held: turn the camera while held
var _lock_icon: Control
var _shake := 0.0                        # 0..1, decays over time
var _rng := RandomNumberGenerator.new()

const BASE_FOV := 70.0
const SPEED_FOV := 12.0                  # extra field of view at top speed
const FP_FOV := 80.0
const FP_MAX_YAW := 110.0                # how far the rider can look around (degrees)
const FP_MAX_PITCH := 40.0
const FP_LOOK_DOWN := 13.0               # default downward tilt (degrees)
const FP_ROLL_CANCEL := 0.6              # share of the bike's lean taken out of the view

var first_person := false
var _fp_cam: Camera3D
var _fp_yaw := 0.0
var _fp_pitch := 0.0

## Short camera shake, e.g. on a crash (0..1).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	target = get_node("../Motorcycle")
	_pitch = deg_to_rad(default_pitch)
	_target_distance = clampf(distance, min_distance, max_distance)
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.3
	_arm.shape = SphereShape3D.new()
	_arm.shape.radius = 0.3
	add_child(_arm)
	_arm.add_excluded_object(target.get_rid())
	_cam = Camera3D.new()
	_arm.add_child(_cam)
	_cam.current = true
	# First-person camera rides on the bike's lean pivot (it leans and wheelies with the bike).
	_fp_cam = Camera3D.new()
	_fp_cam.near = 0.03
	_fp_cam.fov = FP_FOV
	target._lean_pivot.add_child(_fp_cam)
	global_position = target.global_position + Vector3(0, height, 0)
	rotation.y = target.global_rotation.y
	# Small ring in the middle of the screen while Mouse Lock is on.
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_lock_icon = LockIcon.new()
	_lock_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_icon.visible = false
	layer.add_child(_lock_icon)

class LockIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 9.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 4.0, true)
		draw_arc(c, 9.0, 0, TAU, 32, Color(1, 1, 1, 0.95), 2.0, true)
		draw_circle(c, 2.0, Color(1, 1, 1, 0.95))

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("camera_view"):
		set_first_person(not first_person)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mouse_lock"):
		locked = not locked
		_dragging = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_dragging = event.pressed
	if event is InputEventMouseMotion and (locked or _dragging) and first_person:
		_fp_yaw = clampf(_fp_yaw - event.relative.x * mouse_sensitivity * Settings.mouse_sensitivity, -deg_to_rad(FP_MAX_YAW), deg_to_rad(FP_MAX_YAW))
		_fp_pitch = clampf(_fp_pitch - event.relative.y * mouse_sensitivity * Settings.mouse_sensitivity, -deg_to_rad(FP_MAX_PITCH), deg_to_rad(FP_MAX_PITCH))
		_idle_time = 0.0
	elif event is InputEventMouseMotion and (locked or _dragging):
		_yaw_offset -= event.relative.x * mouse_sensitivity * Settings.mouse_sensitivity
		_pitch = clampf(_pitch + event.relative.y * mouse_sensitivity * Settings.mouse_sensitivity, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_idle_time = 0.0
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _target_distance <= min_distance + 0.01 and not first_person:
				set_first_person(true)   # zoomed all the way in: go first person
			_target_distance = clampf(_target_distance - zoom_step, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if first_person:
				set_first_person(false)
				return
			_target_distance = clampf(_target_distance + zoom_step, min_distance, max_distance)

## Switch between the third-person orbit camera and the rider's-eye view.
func set_first_person(on: bool) -> void:
	first_person = on
	_fp_yaw = 0.0
	_fp_pitch = 0.0
	if on:
		_fp_cam.current = true
	else:
		_cam.current = true
	var rider = target.get("_rider")
	if rider:
		rider.hide_head = on   # the head would block the view

func _process(delta: float) -> void:
	var paused := get_tree().paused
	if paused:
		_dragging = false
	var capture := not paused and (locked or _dragging)
	var want := Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	_lock_icon.visible = locked and not paused
	if paused:
		return

	# Gamepad right stick orbits the camera too.
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if first_person:
		_update_first_person(delta, stick)
		return
	if stick.length() > Settings.GAMEPAD_DEADZONE:
		_yaw_offset -= stick.x * 2.5 * Settings.mouse_sensitivity * delta
		_pitch = clampf(_pitch + stick.y * 1.5 * Settings.mouse_sensitivity * delta, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_idle_time = 0.0

	_idle_time += delta
	if _idle_time > recenter_delay:
		_yaw_offset = lerp_angle(_yaw_offset, 0.0, clampf(recenter_speed * delta, 0.0, 1.0))
		_pitch = lerpf(_pitch, deg_to_rad(default_pitch), clampf(recenter_speed * delta, 0.0, 1.0))

	var t := clampf(follow_speed * delta, 0.0, 1.0)
	global_position = global_position.lerp(target.global_position + Vector3(0, height, 0), t)
	rotation.y = lerp_angle(rotation.y, target.global_rotation.y + _yaw_offset, t)
	_arm.rotation.x = -_pitch
	# Field of view widens with speed; shake jitters the camera and fades out.
	var ratio := clampf(absf(target.speed) / maxf(target.max_speed, 1.0), 0.0, 1.0)
	_cam.fov = lerpf(_cam.fov, BASE_FOV + SPEED_FOV * ratio * ratio, clampf(4.0 * delta, 0.0, 1.0))
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var s := _shake * _shake * 0.35
	_cam.h_offset = _rng.randf_range(-s, s)
	_cam.v_offset = _rng.randf_range(-s, s)
	_arm.spring_length = lerpf(_arm.spring_length, _target_distance, clampf(zoom_smoothing * delta, 0.0, 1.0))

## First person: eyes just above the rider's head bone, looking along the bike plus the head turn.
func _update_first_person(delta: float, stick: Vector2) -> void:
	if stick.length() > Settings.GAMEPAD_DEADZONE:
		_fp_yaw = clampf(_fp_yaw - stick.x * 2.5 * Settings.mouse_sensitivity * delta, -deg_to_rad(FP_MAX_YAW), deg_to_rad(FP_MAX_YAW))
		_fp_pitch = clampf(_fp_pitch - stick.y * 1.5 * Settings.mouse_sensitivity * delta, -deg_to_rad(FP_MAX_PITCH), deg_to_rad(FP_MAX_PITCH))
		_idle_time = 0.0
	_idle_time += delta
	if _idle_time > recenter_delay:
		var k := clampf(recenter_speed * delta, 0.0, 1.0)
		_fp_yaw = lerpf(_fp_yaw, 0.0, k)
		_fp_pitch = lerpf(_fp_pitch, 0.0, k)
	var pivot: Node3D = target._lean_pivot
	var rider = target.get("_rider")
	var eye := Vector3(0, 1.62, 0.05)
	if rider and rider._sk:
		var sk: Skeleton3D = rider._sk
		var head := sk.find_bone("mixamorig_Head")
		if head >= 0:
			eye = pivot.to_local(sk.global_transform * sk.get_bone_global_pose(head).origin) + Vector3(0, 0.08, -0.1)
	_fp_cam.position = eye
	# The view leans with the bike, but only partly (a full lean is hard to watch), and looks a
	# little down so the handlebars and hands are in view.
	var roll: float = deg_to_rad(target.max_lean_angle) * target._lean_visual
	_fp_cam.basis = Basis(Vector3.BACK, -roll * FP_ROLL_CANCEL) * Basis(Vector3.UP, _fp_yaw) * Basis(Vector3.RIGHT, _fp_pitch - deg_to_rad(FP_LOOK_DOWN))
	var ratio := clampf(absf(target.speed) / maxf(target.max_speed, 1.0), 0.0, 1.0)
	_fp_cam.fov = lerpf(_fp_cam.fov, FP_FOV + SPEED_FOV * ratio * ratio, clampf(4.0 * delta, 0.0, 1.0))
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var s := _shake * _shake * 0.2
	_fp_cam.h_offset = _rng.randf_range(-s, s)
	_fp_cam.v_offset = _rng.randf_range(-s, s)
	# Keep the third-person rig following, so switching back is smooth.
	global_position = target.global_position + Vector3(0, height, 0)
	rotation.y = target.global_rotation.y
