extends Node3D
## Delivery loop. While idle, the rider app offers three orders (keys 1/2/3); take one, go to the
## pickup beacon, then to the dropoff beacon(s) before time runs out. Orders come in types
## (standard / express / fragile / multi-drop / VIP) with different pay, time and damage rules.
## Crashing while carrying damages the package. Each delivery is rated 1-5 stars; the rating
## scales future pay and unlocks VIP orders.

signal state_changed(text: String)
signal message(text: String)
signal order_accepted
signal offers_ready                  # new orders appeared in the rider app
signal picked_up
signal delivered(pay: int)
signal failed

enum State { IDLE, TO_PICKUP, TO_DROPOFF }

# pay / time: multipliers; damage: multiplier on crash damage; drops: number of dropoffs.
const CargoItems := preload("res://scripts/cargo_items.gd")

const ORDER_TYPES := {
	"standard": {"name": "Standard", "weight": 50, "pay": 1.0, "time": 1.0, "damage": 1.0, "drops": 1, "tape": Color("e8d9b0")},
	"express": {"name": "Express", "weight": 20, "pay": 1.6, "time": 0.65, "damage": 1.0, "drops": 1, "tape": Color("3fa9f5")},
	"fragile": {"name": "Fragile", "weight": 20, "pay": 1.5, "time": 1.15, "damage": 2.5, "drops": 1, "tape": Color("e53935")},
	"multi": {"name": "Multi-drop", "weight": 10, "pay": 1.1, "time": 1.0, "damage": 1.0, "drops": 2, "tape": Color("8bc34a")},
	"vip": {"name": "VIP", "weight": 0, "pay": 2.2, "time": 0.8, "damage": 1.6, "drops": 1, "tape": Color("ffd23f")},
	# Story-only order (chapter 3): never rolled at random, offered by the story manager.
	"cake": {"name": "Wedding Cake", "weight": 0, "pay": 3.0, "time": 1.1, "damage": 2.0, "drops": 1, "tape": Color("f48fb1")},
	# Chapter 4: food offering for the temple. Chapter 5: race Jet to the skytrain station (tight time).
	"temple": {"name": "Temple Offering", "weight": 0, "pay": 2.5, "time": 1.2, "damage": 1.5, "drops": 1, "tape": Color("ff9800")},
	"race": {"name": "Race vs Jet", "weight": 0, "pay": 4.0, "time": 0.6, "damage": 1.0, "drops": 1, "tape": Color("e040fb")},
}
const OFFER_COUNT := 3
const OFFER_LIFETIME := 25.0      # seconds before an offer is replaced
const VIP_CHANCE := 0.25          # per offer slot, once VIP is unlocked

@export var trigger_radius := 6.0
@export var min_trip := 80.0
@export var max_trip := 260.0
@export var base_reward := 50.0
@export var reward_per_meter := 0.6
@export var time_bonus_per_sec := 2.0
@export var expected_speed := 8.0          # m/s used to compute the time limit
@export var time_per_stop := 14.0          # extra seconds per pickup/dropoff
@export var damage_per_mps := 6.0          # condition % lost per m/s of impact above the crash threshold
@export var min_pay_fraction := 0.4        # pay at 0% condition (fragile breaks instead)

var player: Node3D
var city: Node3D
var state := State.IDLE
var order_type := "standard"
var item := "parcel"                 # what is being delivered (cargo_items.gd)
var _wheelie_warned := false
var pickup_pos := Vector3.ZERO
var drops: Array[Vector3] = []
var time_left := 0.0
var time_limit := 1.0       # time given for the current order (for the HUD timer bar)
var trip_length := 0.0
var condition := 100.0
var offers: Array[Dictionary] = []   # {type, pickup, drops, trip, time, pay, expires}
var last_stars := 0
var story: Node                      # story manager (optional): limits order types, adds special orders
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D

func _ready() -> void:
	_rng.randomize()
	player = get_node("../Motorcycle")
	city = get_node("../City")
	story = get_node_or_null("../Story")
	player.crashed.connect(_on_crash)
	_beacon = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.5
	mesh.bottom_radius = 2.5
	mesh.height = 60.0
	_beacon.mesh = mesh
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon.material_override = _beacon_mat
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	add_child(_beacon)
	# City builds its spots in its own _ready; wait a frame.
	await get_tree().process_frame
	_fill_offers()

func order_info() -> Dictionary:
	return ORDER_TYPES[order_type]

# ------------------------------------------------------------------ offers

func _pick_type() -> String:
	# The story unlocks order types chapter by chapter; VIP needs the rating and chapter 3+.
	var allowed: Array = story.allowed_orders() if story else ORDER_TYPES.keys()
	if GameState.vip_unlocked() and (story == null or GameState.chapter >= 3) and _rng.randf() < VIP_CHANCE:
		return "vip"
	var total := 0
	for k in allowed:
		total += ORDER_TYPES[k]["weight"]
	var roll := _rng.randi_range(1, maxi(total, 1))
	for k in allowed:
		roll -= ORDER_TYPES[k]["weight"]
		if roll <= 0:
			return k
	return "standard"

func _spot_between(from: Vector3, lo: float, hi: float) -> Vector3:
	var spots: Array[Vector3] = city.spots
	var ok: Array[Vector3] = spots.filter(func(s: Vector3): var d := s.distance_to(from); return d > lo and d < hi)
	return ok.pick_random() if not ok.is_empty() else spots.pick_random()

## Full pay for a trip of this type and length (before damage, bonus and rating).
func _full_pay(type: String, trip: float) -> float:
	return (base_reward + trip * reward_per_meter) * ORDER_TYPES[type]["pay"]

func _make_offer(forced_type := "") -> Dictionary:
	var type := forced_type if forced_type != "" else _pick_type()
	var special := forced_type != ""
	var here := _flat(player.global_position)
	var fixed = story.special_destination(type) if story and special else null
	# Story orders to a landmark start from the far side of town so the trip is a real ride.
	var pickup := _spot_between(fixed, 260.0, 400.0) if fixed != null else _spot_between(here, 20.0, 220.0)
	var list: Array[Vector3] = []
	var prev := pickup
	var trip := 0.0
	for n in ORDER_TYPES[type]["drops"]:
		# Story orders go across town (or to their landmark).
		var d: Vector3 = fixed if fixed != null else _spot_between(prev, 280.0 if special else min_trip, 420.0 if special else (max_trip if n == 0 else 200.0))
		list.append(d)
		trip += prev.distance_to(d)
		prev = d
	var time: float = (trip / expected_speed + time_per_stop * list.size()) * ORDER_TYPES[type]["time"]
	return {"type": type, "item": CargoItems.pick(type, _rng), "pickup": pickup, "drops": list, "trip": trip, "time": time,
		"pay": int(round(_full_pay(type, trip) * GameState.rating_multiplier())),
		"story": special,
		"expires": INF if special else _clock + OFFER_LIFETIME + _rng.randf_range(-4.0, 4.0)}

## Make sure the story's special order (if any) is the first offer in the app.
func _ensure_special_offer() -> void:
	var special: String = story.special_order() if story else ""
	if special == "" or offers.is_empty():
		return
	for o in offers:
		if o["type"] == special:
			return
	offers[0] = _make_offer(special)

func _fill_offers() -> void:
	offers.clear()
	for n in OFFER_COUNT:
		offers.append(_make_offer())
	_ensure_special_offer()
	message.emit(tr("New orders in the rider app! Press 1, 2 or 3 to take one."))
	offers_ready.emit()

func offer_distance(o: Dictionary) -> float:
	return _flat(player.global_position).distance_to(o["pickup"])

func accept_offer(index: int) -> void:
	if state != State.IDLE or index < 0 or index >= offers.size():
		return
	var o := offers[index]
	order_type = o["type"]
	item = o.get("item", "parcel")
	pickup_pos = o["pickup"]
	drops = o["drops"].duplicate()
	trip_length = o["trip"]
	time_limit = o["time"]
	condition = 100.0
	offers.clear()
	state = State.TO_PICKUP
	_show_beacon(pickup_pos, Color(1.0, 0.85, 0.1, 0.35))
	message.emit(tr("%s order accepted! Pick it up at the yellow marker.") % (tr(order_info()["name"]) + ": " + tr(CargoItems.item_name(item))))
	order_accepted.emit()

func cancel_order() -> void:
	if state == State.IDLE:
		return
	GameState.add_rating(1)
	_fail(tr("Order cancelled. The customer gave you 1 star."))

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	for n in OFFER_COUNT:
		if event.is_action_pressed("order_%d" % (n + 1)):
			accept_offer(n)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("cancel_order"):
		cancel_order()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ running an order

func _show_beacon(pos: Vector3, color: Color) -> void:
	_beacon.global_position = pos + Vector3(0, 30, 0)
	_beacon_mat.albedo_color = color
	_beacon.visible = true

func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0, p.z)

func _process(delta: float) -> void:
	_clock += delta
	if player == null:
		return
	if state == State.IDLE:
		# Replace offers as they expire.
		for n in offers.size():
			if _clock > offers[n]["expires"]:
				offers[n] = _make_offer()
		_ensure_special_offer()
		return
	var here := _flat(player.global_position)
	# Wheelies shake a delicate package.
	if state == State.TO_DROPOFF and player.wheelie > 0.5 and order_type in ["fragile", "cake", "temple", "vip"]:
		condition = maxf(condition - 6.0 * delta, 0.0)
		if not _wheelie_warned:
			_wheelie_warned = true
			message.emit(tr("Careful! Wheelies shake the package."))
	if state != State.TO_DROPOFF:
		_wheelie_warned = false
	match state:
		State.TO_PICKUP:
			if here.distance_to(pickup_pos) < trigger_radius:
				state = State.TO_DROPOFF
				player.set_carrying(true, item)
				time_left = time_limit
				_show_beacon(drops[0], Color(0.2, 1.0, 0.3, 0.35))
				var extra := tr("  Handle with care!") if order_type in ["fragile", "vip", "cake", "temple"] else ""
				message.emit(tr("Package picked up! Deliver it to the green marker.") + extra)
				picked_up.emit()
		State.TO_DROPOFF:
			time_left -= delta
			if here.distance_to(drops[0]) < trigger_radius:
				drops.remove_at(0)
				if drops.is_empty():
					_complete()
				else:
					_show_beacon(drops[0], Color(0.2, 1.0, 0.3, 0.35))
					message.emit(tr("Drop done! %d more to go.") % drops.size())
			elif time_left <= 0.0:
				GameState.add_rating(1)
				_fail(tr("Time's up! Delivery failed."))
	state_changed.emit(objective_text())

func _on_crash(impact: float) -> void:
	if state != State.TO_DROPOFF:
		return
	var loss: float = (impact - player.crash_min_speed + 1.0) * damage_per_mps * order_info()["damage"]
	condition = maxf(condition - loss, 0.0)
	if order_type in ["fragile", "cake", "temple"] and condition <= 0.0:
		GameState.add_rating(1)
		_fail(tr("The fragile package broke! Delivery failed."))
	else:
		message.emit(tr("Crash! Package condition %d%%") % int(condition))

## Stars for a finished delivery: full marks for an intact package with time to spare.
func _stars() -> int:
	var stars := 5
	if condition < 90.0:
		stars -= 1
	if condition < 60.0:
		stars -= 1
	if time_left < time_limit * 0.15:
		stars -= 1
	return clampi(stars, 1, 5)

func _complete() -> void:
	var full := _full_pay(order_type, trip_length) * GameState.rating_multiplier()
	var cond_factor := lerpf(min_pay_fraction, 1.0, condition / 100.0)
	var bonus := maxf(time_left, 0.0) * time_bonus_per_sec
	var pay := int(round(full * cond_factor + bonus))
	var lost := int(round(full - full * cond_factor))
	last_stars = _stars()
	GameState.record_delivery(order_type, pay, lost, condition >= 100.0)
	GameState.add_rating(last_stars)
	var note := "" if lost == 0 else tr("  (-%d THB damage)") % lost
	message.emit(tr("Delivered! +%d THB") % pay + "  " + "★".repeat(last_stars) + "☆".repeat(5 - last_stars) + note)
	delivered.emit(pay)
	_next_job_later()

func _fail(text: String) -> void:
	GameState.record_failed()
	message.emit(text)
	failed.emit()
	_next_job_later()

func _next_job_later() -> void:
	state = State.IDLE
	offers.clear()
	player.set_carrying(false)
	_beacon.visible = false
	await get_tree().create_timer(1.5).timeout
	if state == State.IDLE:
		_fill_offers()

## World position of the current goal, or null when there is no active order.
func target_position() -> Variant:
	match state:
		State.TO_PICKUP:
			return pickup_pos
		State.TO_DROPOFF:
			return drops[0]
	return null

func target_color() -> Color:
	return Color(1.0, 0.85, 0.1) if state == State.TO_PICKUP else Color(0.2, 1.0, 0.3)

func objective_text() -> String:
	var here := _flat(player.global_position)
	var tag: String = tr(String(order_info()["name"])).to_upper()
	match state:
		State.TO_PICKUP:
			return "[%s]  %s  %d m" % [tag, tr("Pick up package"), int(here.distance_to(pickup_pos))]
		State.TO_DROPOFF:
			return "[%s]  %s  %d m   %d s   %d%%" % [tag, tr("Deliver"), int(here.distance_to(drops[0])), int(maxf(time_left, 0.0)), int(condition)]
	return tr("Choose an order in the rider app")
