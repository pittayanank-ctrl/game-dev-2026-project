extends Node3D
## Visual effects: crash sparks (+ camera shake), a gold burst when a delivery is completed,
## tyre smoke when braking hard, wheel spray and ground splashes when it rains.

var _bike: Node3D
var _camera_rig: Node3D
var _clock: Node
var _smoke: CPUParticles3D
var _spray: CPUParticles3D
var _splashes: CPUParticles3D

func _ready() -> void:
	_bike = get_node("../Motorcycle")
	_camera_rig = get_node_or_null("../CameraRig")
	_clock = get_node_or_null("../WorldClock")
	_bike.crashed.connect(_on_crash)
	var delivery := get_node_or_null("../DeliveryManager")
	if delivery:
		delivery.delivered.connect(func(_pay): _burst(_bike.global_position + Vector3(0, 1.3, 0), Color(1.0, 0.82, 0.2), 40, 5.0, 0.9, -6.0, 0.09))
	_smoke = _emitter(Color(0.75, 0.75, 0.78, 0.5), 0.28, 1.0, 1.5, 28)
	_smoke.gravity = Vector3(0, 1.2, 0)
	_spray = _emitter(Color(0.8, 0.88, 1.0, 0.55), 0.06, 0.45, 4.0, 60)
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.direction = Vector3(0, 1, 1)
	_spray.spread = 25.0
	_splashes = _emitter(Color(0.8, 0.88, 1.0, 0.5), 0.05, 0.25, 1.5, 260)
	_splashes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splashes.emission_box_extents = Vector3(18, 0.05, 18)
	_splashes.direction = Vector3(0, 1, 0)
	_splashes.gravity = Vector3(0, -6, 0)

func _quality() -> float:
	return [0.4, 0.8, 1.0][Settings.graphics]

## A continuous emitter (toggled on/off every frame) using small unshaded boxes.
func _emitter(color: Color, size: float, lifetime: float, speed: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(int(amount * _quality()), 4)
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.spread = 40.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.mesh = _dot_mesh(color, size)
	add_child(p)
	return p

func _dot_mesh(color: Color, size: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	return m

## One-shot burst of particles that cleans itself up.
func _burst(pos: Vector3, color: Color, amount: int, speed: float, lifetime: float, gravity_y: float, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(int(amount * _quality()), 6)
	p.lifetime = lifetime
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity_y, 0)
	p.mesh = _dot_mesh(color, size)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)

func _on_crash(impact: float) -> void:
	var front: Vector3 = _bike.global_position - _bike.global_transform.basis.z * 1.0 + Vector3(0, 0.6, 0)
	_burst(front, Color(1.0, 0.65, 0.15), int(10 + impact * 4), 4.0 + impact * 0.5, 0.45, -12.0, 0.06)
	if _camera_rig and _camera_rig.has_method("shake"):
		_camera_rig.shake(clampf(impact / 14.0, 0.15, 1.0))

func _process(_delta: float) -> void:
	var rear: Vector3 = _bike.global_transform * Vector3(0, 0.15, 0.75)
	var spd: float = absf(_bike.speed)
	var braking: bool = Input.get_action_strength("brake") > 0.3 and _bike.speed > 6.0
	_smoke.global_position = rear
	_smoke.emitting = braking and _bike.is_on_floor()
	var wet: bool = _clock != null and _clock.raining
	_spray.global_position = rear
	_spray.direction = _bike.global_transform.basis.z + Vector3(0, 0.8, 0)
	_spray.emitting = wet and spd > 5.0
	_splashes.emitting = wet
	var cam := get_viewport().get_camera_3d()
	if cam:
		_splashes.global_position = Vector3(cam.global_position.x, 0.06, cam.global_position.z)
