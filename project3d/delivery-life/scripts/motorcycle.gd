extends CharacterBody3D
## Arcade motorcycle controller: accelerate, brake, steer (steering scales with speed).
## Stats come from the currently equipped bike in GameState.

signal crashed(impact_speed: float)   # hit a wall/car hard enough to matter
signal engine_changed(on: bool)        # engine started / switched off / stalled
signal notice(text: String)            # short message for the HUD (warnings)
signal stunt(text: String)             # a finished wheelie (distance), for the HUD

const CargoItems := preload("res://scripts/cargo_items.gd")
const EngineAudio := preload("res://scripts/engine_audio.gd")

@export var max_speed := 25.0
@export var reverse_speed := 6.0
@export var acceleration := 12.0
@export var brake_force := 25.0
@export var friction := 6.0
@export var turn_speed := 2.0
@export var gravity := 30.0

# Paint zones come from node names in pcx.fbx: a mesh named "black", "black_001", "silver_003", ...
# gets that colour zone (prefix before the first "_"). Body-panel nodes are listed in BODY_NODES and
# follow the shop colour (GameState.zone_colors); material "fairing.0" is also treated as body.
const BODY_NODES := ["chassi", "mudgruad", "primary"]
const BLACK_NODES := ["wheel_front", "wheel_rear"]   # rims: named after the wheel, painted black
const FIXED_ZONE_COLORS := {
	"black": Color("1a1a1a"),
	"silver": Color("b9bcc2"),
	"red": Color("c3101b"),
	"blue": Color("0042b8"),
	"glass": Color(0.12, 0.17, 0.22, 0.45),
	"wheel_front_001": Color("1a1a1a"),
	"wheel_rear_001": Color("1a1a1a"),
}

# Per-model setup. Positions are in bike space (ground = y 0, forward = -Z): "y" lifts the model so
# the tyres touch the ground, "wheels" are the front/rear tyre radii, the rest place the rider
# (hips, right grip, right foot; left side is mirrored), the delivery box and the headlight.
const MODELS := {
	"pcx": {"scene": "res://assets/models/motorcycles/pcx.fbx", "y": 0.373, "wheels": [0.27, 0.31],
		"black_wheels": true, "seat": Vector3(0, 0.93, 0.14), "grip": Vector3(0.3, 1.06, -0.31),
		"foot": Vector3(0.17, 0.56, -0.24), "cargo": Vector3(0, 1.06, 0.6), "headlight": Vector3(0, 0.95, -0.95)},
	"oldscooter": {"scene": "res://assets/models/motorcycles/oldscooter.fbx", "y": 0.586, "wheels": [0.237, 0.237],
		"black_wheels": false, "seat": Vector3(0, 0.96, 0.24), "grip": Vector3(0.34, 1.12, -0.3),
		"foot": Vector3(0.14, 0.43, -0.14), "cargo": Vector3(0, 1.08, 0.62), "headlight": Vector3(0, 1.05, -0.55)},
	# Forza 350: no textures, every part is coloured by its node name (see "colors"). The rear tyre
	# is bigger than the front, so the model is pitched nose-down a little ("pitch", degrees).
	"forza350": {"scene": "res://assets/models/motorcycles/forza350.fbx", "y": 0.525, "pitch": -1.46, "wheels": [0.339, 0.384],
		"black_wheels": true, "seat": Vector3(0, 1.0, 0.18), "grip": Vector3(0.38, 1.27, -0.33),
		"foot": Vector3(0.19, 0.5, -0.4), "cargo": Vector3(0, 1.2, 0.8), "headlight": Vector3(0, 0.95, -1.15),
		"colors": {
			"grey": Color("55585e"), "white": Color("e6e6e6"), "whitegrey": Color("b9bcc2"), "whitelight": Color("d8d8d8"),
			"orange": Color("e88a10"), "rim": Color("1a1a1a"), "rimblack": Color("1a1a1a"), "blackrubber": Color("101010"),
			"handlebar": Color("1a1a1a"), "gauge": Color("202226"), "seat": Color("1c1c1e"),
			"headlight": Color(0.85, 0.9, 0.95, 0.75), "tail": Color(0.75, 0.05, 0.05, 0.85), "windshield": Color(0.25, 0.3, 0.35, 0.45),
		},
		# Parts with an image texture (node-name prefix -> file). The FBX looks for its images next to
		# the model file, so they are applied here from assets/textures instead.
		"textures": {"asdasd": "res://assets/textures/motorcycles/asdasd.png"}},   # exhaust
	# Wave 125: some nodes carry their colour at the end of the name ("forks_front_primary",
	# "wheel_rear_black"), so the pivot nodes are named in "nodes". No textures; coloured by name.
	"wave125": {"scene": "res://assets/models/motorcycles/wave125.fbx", "y": 0.6, "wheels": [0.315, 0.343],
		"black_wheels": true, "seat": Vector3(0, 0.97, 0.12), "grip": Vector3(0.3, 1.06, -0.5),
		"foot": Vector3(0.2, 0.36, 0.0), "cargo": Vector3(0, 1.11, 0.56), "headlight": Vector3(0, 1.04, -0.78),
		"nodes": {"forks": "forks_front_primary", "wheel_rear": "wheel_rear_black"},
		"textures": {"lolokuj": "res://assets/textures/motorcycles/lolokuj.png"},   # exhaust
		"body": ["object_046"],   # extra body-paint nodes (exact names)
		"colors": {
			"blackgrey": Color("2b2d31"), "white": Color("e6e6e6"), "wihte": Color("e6e6e6"), "whitegrey": Color("b9bcc2"),
			"grey": Color("55585e"), "orangered": Color("ff4a1a"), "yellow": Color("f2c200"), "green": Color("30d040"),
			"orange": Color("ffa000"), "skyblue": Color("4fb3e8"), "greyrubber": Color("2a2a2a"), "blackrubber": Color("101010"),
			"seat": Color("1c1c1e"), "object": Color("c0c3c8"),   # exhaust heat shields
			"object_078": Color("1a1a1a"),   # a full node name overrides the prefix colour
			"headlight": Color(0.85, 0.9, 0.95, 0.75), "speedo": Color(0.8, 0.85, 0.9, 0.4),
		}},
	# Giorno: colour at the end of some node names, small 12" wheels; pitched a little nose-down so
	# both tyres touch the ground.
	"giorno": {"scene": "res://assets/models/motorcycles/giorno.fbx", "y": 0.258, "pitch": -0.94, "wheels": [0.2475, 0.2475],
		"black_wheels": false, "seat": Vector3(0, 0.74, 0.08), "grip": Vector3(0.31, 0.98, -0.42),
		"foot": Vector3(0.14, 0.32, -0.3), "cargo": Vector3(0, 0.86, 0.5), "headlight": Vector3(0, 1.0, -0.65),
		"nodes": {"forks": "forks_front_white", "wheel_front": "wheel_front_black", "wheel_rear": "wheel_rear_black"},
		"colors": {
			"greyblack": Color("2b2d31"), "greywhite": Color("cfd2d6"), "grey": Color("6a6d73"), "white": Color("ececec"),
			"whitegrey": Color("b9bcc2"), "gold": Color("c9a24a"), "greyrubber": Color("1c1c1c"), "seat": Color("3b2a20"),
			"headlight": Color(0.85, 0.9, 0.95, 0.75),
		}},
}

@export var preview_only := false   # display model (shop): no input, physics or game hooks
@export var crash_min_speed := 4.0  # m/s; slower bumps don't count as crashes

var grip_factor := 1.0              # < 1 on wet roads (set by WorldClock)

var speed := 0.0
var spawn_transform: Transform3D
var _zone_mats := {}   # zone id -> Array[StandardMaterial3D]
var _wheels: Array[Dictionary] = []   # {node, base, axis, radius, angle}
var _rider: Node3D
var _cargo: Node3D                    # delivery box on the passenger seat
var _lean_pivot: Node3D               # model + rider roll together around the ground contact line
var _forks: Node3D
var _forks_base: Transform3D          # forks transform in bike space at rest
var _steer_pivot := Vector3.ZERO      # front hub position in bike space
var _steer_axis := Vector3(0, 0.76, 0.53).normalized()   # steering head axis (raked back)
var _steer_visual := 0.0
var _lean_visual := 0.0
var _moving_visual := 0.0             # 0 = standing still, 1 = riding (scales the rider's head turn)
var _crash_cooldown := 0.0
var _headlight: SpotLight3D
var _cargo_mesh: MeshInstance3D       # the item model (food bag, cake, ...)
var _engine: Node                     # engine sound (player bike only), see engine_audio.gd
# Engine on/off (E): the game starts with the engine off. While it is off the bike can only be
# pushed at walking pace, uses no fuel, makes no engine sound and has no headlight.
var engine_on := false
var _cranking := 0.0                  # > 0 while the starter is turning (seconds left)
var _night := false
var _remind_cooldown := 0.0
const PUSH_SPEED := 3.0               # m/s when pushing the bike (engine off / out of fuel)
# Wheelie (hold T): the bike pivots on the rear tyre's contact point and the front wheel lifts.
const WHEELIE_ANGLE := 22.0           # degrees at full lift
const WHEELIE_MIN_SPEED := 2.0        # m/s
var wheelie := 0.0                    # 0 = both wheels down, 1 = full wheelie
var _rear_contact := Vector3.ZERO     # rear tyre on the ground, bike space
var _wheelie_dist := 0.0
var _wobble := 0.0
var model_id := "pcx"                 # the scene's Model node starts as the PCX
var _black_wheels := true
var _body_nodes: Array = []             # extra body-paint node names of the current model
var _nodes := {}                        # pivot node names of the current model (see MODELS "nodes")
var _zone_colors := FIXED_ZONE_COLORS   # fixed colours for the current model

@export var max_steer_angle := 22.0   # degrees the front fork turns
@export var max_lean_angle := 22.0    # degrees the bike leans at full speed + full steer

func _ready() -> void:
	if preview_only:
		set_physics_process(false)
	else:
		add_to_group("player")
		GameState.bike_changed.connect(_apply_stats)
	spawn_transform = global_transform
	_lean_pivot = Node3D.new()
	add_child(_lean_pivot)
	$Model.reparent(_lean_pivot)
	_rider = $Rider
	_rider.reparent(_lean_pivot)
	_build_cargo()
	_build_headlight()
	if not preview_only:
		_engine = EngineAudio.new()
		add_child(_engine)
	set_model(model_id if preview_only else str(GameState.current_bike().get("model", "pcx")), true)
	_apply_stats()

## Swap the 3D model (e.g. "pcx", "oldscooter") and re-fit wheels, steering, paint and rider.
func set_model(id: String, force := false) -> void:
	if not MODELS.has(id):
		id = "pcx"
	if id == model_id and not force:
		return
	var cfg: Dictionary = MODELS[id]
	_lean_pivot.transform = Transform3D.IDENTITY   # set up at rest, not mid-lean
	var model := _lean_pivot.get_node("Model") as Node3D
	if id != model_id:
		_lean_pivot.remove_child(model)
		model.queue_free()
		model = (load(cfg["scene"]) as PackedScene).instantiate()
		model.name = "Model"
		_lean_pivot.add_child(model)
		model_id = id
	model.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(cfg.get("pitch", 0.0))), Vector3(0, cfg["y"], 0))
	# The handlebars turn with the front fork.
	_nodes = {"forks": "forks_front", "wheel_front": "wheel_front", "wheel_rear": "wheel_rear", "handlebars": "handlebars"}
	_nodes.merge(cfg.get("nodes", {}), true)
	var forks := model.find_child(_nodes["forks"], true, false) as Node3D
	var bars := model.find_child(_nodes["handlebars"], true, false) as Node3D
	if forks and bars and not forks.is_ancestor_of(bars):
		bars.reparent(forks)
	_black_wheels = cfg["black_wheels"]
	_body_nodes = cfg.get("body", [])
	_zone_colors = FIXED_ZONE_COLORS.merged(cfg.get("colors", {}), true)
	_zone_mats.clear()
	_wheels.clear()
	_setup_paint()
	_apply_textures(model, cfg.get("textures", {}))
	_setup_wheels(cfg["wheels"])
	_setup_steering()
	_cargo.position = cfg["cargo"]
	_headlight.position = cfg["headlight"]
	var g: Vector3 = cfg["grip"]
	var f: Vector3 = cfg["foot"]
	_apply_colors()
	if _engine:
		_engine.set_model(id)
		stop_engine()   # a different bike: start it with the key
	_rider.fit(cfg["seat"], Vector3(-g.x, g.y, g.z), g, Vector3(-f.x, f.y, f.z), f)

# Wheel nodes in pcx.fbx have their pivot at the hub; spin them around the bike's X axis.
func _setup_wheels(radii: Array) -> void:
	for info in [[_nodes["wheel_front"], radii[0]], [_nodes["wheel_rear"], radii[1]]]:
		var w := _lean_pivot.get_node("Model").find_child(info[0], true, false) as Node3D
		if w == null:
			continue
		var axis := (w.global_transform.basis.inverse() * global_transform.basis.x).normalized()
		_wheels.append({"node": w, "base": w.transform.basis, "axis": axis, "radius": info[1], "angle": 0.0})
		if info[0] == _nodes["wheel_rear"]:
			var hub := to_local(w.global_position)
			_rear_contact = Vector3(0, 0, hub.z)

func _setup_steering() -> void:
	# forks_front (with wheel_front as a child) turns around an axis through the front hub.
	var hub := _lean_pivot.get_node("Model").find_child(_nodes["wheel_front"], true, false) as Node3D
	_forks = _lean_pivot.get_node("Model").find_child(_nodes["forks"], true, false) as Node3D
	if _forks == null or hub == null:
		_forks = null
		return
	_forks_base = global_transform.affine_inverse() * _forks.global_transform
	_steer_pivot = to_local(hub.global_position)

func _animate_body(delta: float, steer: float) -> void:
	# Lean into turns only when riding forward; stand upright when slow, stopped or reversing.
	var forward_ratio := clampf(speed / maxf(max_speed, 0.1), 0.0, 1.0)
	var moving := clampf((speed - 1.0) / 4.0, 0.0, 1.0)   # 0 below 1 m/s, 1 above 5 m/s
	_steer_visual = lerpf(_steer_visual, steer, clampf(10.0 * delta, 0.0, 1.0))
	var lean_rate := 6.0 if moving > 0.0 else 10.0         # straighten up quickly when stopping
	_lean_visual = lerpf(_lean_visual, steer * forward_ratio * moving, clampf(lean_rate * delta, 0.0, 1.0))
	_moving_visual = lerpf(_moving_visual, moving, clampf(6.0 * delta, 0.0, 1.0))
	# Lean (roll) around the ground line, and the wheelie (pitch) around the rear tyre.
	_wobble += delta
	var pitch := deg_to_rad(WHEELIE_ANGLE) * wheelie + deg_to_rad(2.0) * sin(_wobble * 6.0) * wheelie
	var roll := Transform3D(Basis(Vector3.BACK, deg_to_rad(max_lean_angle) * _lean_visual), Vector3.ZERO)
	_lean_pivot.transform = Transform3D(Basis.IDENTITY, _rear_contact) * Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -_rear_contact) * roll
	if _forks:
		# Rotate the fork around the steering axis through the front hub (positive = left).
		var rot := Basis(_steer_axis, deg_to_rad(max_steer_angle) * _steer_visual)
		var t := Transform3D(Basis.IDENTITY, _steer_pivot) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_steer_pivot)
		_forks.global_transform = _lean_pivot.global_transform * (t * _forks_base)
	_animate_rider()

# The rider's hands follow the turning handlebars, and the torso/head lean into the turn.
func _animate_rider() -> void:
	if _rider == null:
		return
	var gl: Vector3 = _rider.grip_left
	var gr: Vector3 = _rider.grip_right
	if _forks:
		var rot := Basis(_steer_axis, deg_to_rad(max_steer_angle) * _steer_visual)
		gl = _steer_pivot + rot * (gl - _steer_pivot)
		gr = _steer_pivot + rot * (gr - _steer_pivot)
	# The head only turns to look into a corner while actually riding.
	_rider.update_pose(_steer_visual * _moving_visual, _lean_visual, gl, gr)

func _spin_wheels(delta: float) -> void:
	for wd in _wheels:
		# Rolling forward (-Z) means the top of the wheel moves toward -Z: negative rotation about +X.
		wd["angle"] -= speed / wd["radius"] * delta
		wd["node"].transform.basis = wd["base"] * Basis(wd["axis"], wd["angle"])

# Give each body-panel surface its own copy of the material so we can recolour it at runtime.
func _zone_for(m: Node, mat: Material) -> String:
	var node_name := str(m.name).to_lower()
	if node_name in BODY_NODES or node_name in _body_nodes or mat.resource_name == "primary":
		return "body"
	if _black_wheels and node_name in BLACK_NODES:
		return "black"
	if _zone_colors.has(node_name):   # exact node name, e.g. "object_078"
		return node_name
	var parts := node_name.split("_")
	var prefix := parts[0]
	if prefix == "primary" or parts[-1] == "primary":
		return "body"
	if _zone_colors.has(prefix):
		return prefix
	if _zone_colors.has(parts[-1]):   # colour at the end of the name, e.g. "wheel_rear_black"
		return parts[-1]
	if mat.resource_name == "fairing.0":
		return "body"
	return ""

# Cardboard box strapped on the passenger seat; only visible while carrying an order.
func _build_cargo() -> void:
	_cargo = Node3D.new()
	_cargo.position = Vector3(0, 1.06, 0.6)   # seat top is ~0.89, box is 0.34 tall
	_cargo.visible = false
	_lean_pivot.add_child(_cargo)
	_cargo_mesh = MeshInstance3D.new()
	_cargo_mesh.mesh = CargoItems.mesh("parcel")
	_cargo.add_child(_cargo_mesh)

## Recolour the body panels directly (used by the shop preview).
func apply_body_color(col: Color) -> void:
	for mat in _zone_mats.get("body", []):
		mat.albedo_color = col

## Show what we're delivering on the passenger seat (see cargo_items.gd for the item ids).
func set_carrying(carrying: bool, item := "parcel") -> void:
	_cargo.visible = carrying
	if carrying:
		_cargo_mesh.mesh = CargoItems.mesh(item)

func _build_headlight() -> void:
	_headlight = SpotLight3D.new()
	_headlight.position = Vector3(0, 0.95, -0.95)
	_headlight.rotation_degrees = Vector3(-8, 0, 0)   # spotlights shine along -Z
	_headlight.spot_range = 28.0
	_headlight.spot_angle = 32.0
	_headlight.light_energy = 3.0
	_headlight.light_color = Color(1.0, 0.95, 0.85)
	_headlight.visible = false
	_lean_pivot.add_child(_headlight)

func set_night(on: bool) -> void:
	_night = on
	_headlight.visible = on and engine_on

## Turn the key: the starter cranks for the length of the start sound, then the engine runs.
func start_engine() -> void:
	if engine_on or _cranking > 0.0:
		return
	if GameState.fuel <= 0.0:
		notice.emit(tr("No fuel - refuel before starting the engine."))
		return
	_cranking = _engine.crank() if _engine else 0.5

func stop_engine() -> void:
	_cranking = 0.0
	if engine_on:
		engine_on = false
		_headlight.visible = false
		engine_changed.emit(false)

func toggle_engine() -> void:
	if engine_on or _cranking > 0.0:
		stop_engine()
	else:
		start_engine()

func _update_engine(delta: float) -> void:
	if _cranking > 0.0:
		_cranking -= delta
		if _cranking <= 0.0:
			_cranking = 0.0
			engine_on = true
			_headlight.visible = _night
			engine_changed.emit(true)
	if engine_on and GameState.fuel <= 0.0:
		stop_engine()   # ran dry: the engine stalls (the fuel system shows the message)

## Put an image texture on the parts listed in the model's "textures" (by node-name prefix).
func _apply_textures(model: Node, textures: Dictionary) -> void:
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var prefix := str(m.name).to_lower().split("_")[0]
		if not textures.has(prefix):
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(textures[prefix]) as Texture2D
		mat.metallic = 0.6
		mat.roughness = 0.35
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, mat)

func _setup_paint() -> void:
	var copies := {}   # "material|zone" -> duplicated material, shared by surfaces with the same pair
	for m in _lean_pivot.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		for i in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var zone := _zone_for(m, mat)
			if zone == "":
				continue
			var key := "%s|%s" % [mat.resource_name, zone]
			if not copies.has(key):
				copies[key] = mat.duplicate()
				if not _zone_mats.has(zone):
					_zone_mats[zone] = []
				_zone_mats[zone].append(copies[key])
			m.set_surface_override_material(i, copies[key])

func _apply_stats() -> void:
	if not preview_only:
		set_model(str(GameState.current_bike().get("model", "pcx")))
	_apply_colors()
	var b := GameState.effective_stats(GameState.current_id)
	max_speed = b["max_speed"]
	acceleration = b["acceleration"]
	turn_speed = b["turn_speed"]
	brake_force = b["brake_force"]

func _apply_colors() -> void:
	for zone in _zone_mats:
		var col: Color
		if _zone_colors.has(zone):
			col = _zone_colors[zone]
		else:
			col = GameState.color_by_id(GameState.zone_colors.get(zone, "white"))["color"]
		for mat in _zone_mats[zone]:
			mat.albedo_color = col
			if col.a < 1.0:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var throttle := Input.get_axis("brake", "accelerate")
	var steer := Input.get_axis("steer_right", "steer_left")
	if Input.is_action_just_pressed("horn"):
		_engine.horn()
	if Input.is_action_just_pressed("engine"):
		toggle_engine()
	_update_engine(delta)
	_remind_cooldown -= delta
	if not engine_on and _cranking <= 0.0 and throttle > 0.0 and GameState.fuel > 0.0 and _remind_cooldown <= 0.0:
		_remind_cooldown = 5.0
		notice.emit(tr("The engine is off. Press %s to start it.") % Settings.key_name("engine"))

	# Wet roads (grip_factor < 1) mean weaker acceleration, braking and turning.
	var accel := acceleration * lerpf(0.5, 1.0, grip_factor)
	# Engine off or out of fuel: you can only push the bike along at walking pace.
	var top := max_speed if engine_on else PUSH_SPEED
	if not engine_on:
		accel = minf(accel, 2.0)
	if speed > top:
		speed = move_toward(speed, top, friction * delta)   # engine died: coast down
	elif throttle > 0.0:
		speed = move_toward(speed, top, accel * delta)
	elif throttle < 0.0:
		if speed > 0.1:
			speed = move_toward(speed, 0.0, brake_force * grip_factor * delta)
		else:
			speed = move_toward(speed, -reverse_speed, accel * delta)
	else:
		speed = move_toward(speed, 0.0, friction * delta)

	_update_wheelie(delta, throttle)

	# Steering only works while moving, and flips when reversing. Front wheel up: less steering.
	var grip := clampf(absf(speed) / 5.0, 0.0, 1.0) * (1.0 - 0.6 * wheelie)
	rotate_y(steer * turn_speed * grip_factor * grip * signf(speed) * delta)

	var forward := -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	GameState.today["distance"] += moved
	if engine_on:
		GameState.fuel = maxf(GameState.fuel - GameState.fuel_for_distance(moved), 0.0)
	if wheelie > 0.6:
		_wheelie_dist += moved
	_spin_wheels(delta)
	_animate_body(delta, steer)
	_engine.update(delta, speed, max_speed, maxf(Input.get_action_strength("accelerate"), wheelie), Input.get_action_strength("brake"), engine_on)

	# Hitting a wall kills speed instead of grinding along it.
	if get_slide_collision_count() > 0 and absf(speed) > 1.0:
		var hit := false
		for i in get_slide_collision_count():
			if absf(get_slide_collision(i).get_normal().y) < 0.5:
				hit = true
		if hit:
			if absf(speed) >= crash_min_speed and _crash_cooldown <= 0.0:
				_crash_cooldown = 0.6
				GameState.today["crashes"] += 1
				crashed.emit(absf(speed))
			speed *= 0.5
	_crash_cooldown -= delta

	if global_position.y < -20.0:
		global_transform = spawn_transform
		speed = 0.0
		velocity = Vector3.ZERO

## Hold the wheelie key while riding: the front lifts; let go (or brake, or slow down) to land.
## A finished wheelie reports its distance and keeps the best one.
func _update_wheelie(delta: float, throttle: float) -> void:
	var want := Input.is_action_pressed("wheelie") and engine_on and speed > WHEELIE_MIN_SPEED and throttle >= 0.0
	var rate := 2.2 if want else (7.0 if throttle < 0.0 else 3.0)   # braking drops the front fast
	wheelie = move_toward(wheelie, 1.0 if want else 0.0, rate * delta)
	if wheelie < 0.15 and _wheelie_dist > 0.0:
		var dist := _wheelie_dist
		_wheelie_dist = 0.0
		if dist >= 3.0:
			var best: int = GameState.stats.get("best_wheelie", 0)
			if int(dist) > best:
				GameState.stats["best_wheelie"] = int(dist)
				stunt.emit(tr("Wheelie! %d m  -  new best!") % int(dist))
			else:
				stunt.emit(tr("Wheelie! %d m  (best %d m)") % [int(dist), best])

func speed_kmh() -> float:
	return absf(speed) * 3.6
