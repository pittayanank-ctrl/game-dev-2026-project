extends Node
## Plays music and effects for game events (see the Audio autoload): ride music (race music during
## the race against Jet), order notifications, pick-up / delivered / failed, money in and out,
## crashes, the traffic camera, refuelling, missions, chapters and goals, cutscene lines, and a
## clock tick during the last 10 seconds of a delivery.

var _delivery: Node
var _bike: Node
var _cutscene: Node
var _last_money := 0
var _last_tick := -1

func _ready() -> void:
	Audio.play_music("ride")
	_delivery = get_node("../DeliveryManager")
	_bike = get_node("../Motorcycle")
	_cutscene = get_node("../Cutscene")
	_delivery.offers_ready.connect(func(): Audio.play("notify", -4.0, 0.0))
	_delivery.order_accepted.connect(func(): Audio.play("confirm", -4.0))
	_delivery.picked_up.connect(func(): Audio.play("pickup", 0.0))
	_delivery.delivered.connect(func(_pay): Audio.play("deliver", -2.0, 0.0))
	_delivery.failed.connect(func(): Audio.play("fail", -2.0, 0.0))
	_bike.crashed.connect(_on_crash)
	_bike.notice.connect(func(_t): Audio.play("error", -8.0))
	_bike.stunt.connect(func(_t): Audio.play("mission", -6.0, 0.0))
	var lights := get_node_or_null("../TrafficLights")
	if lights:
		lights.red_light_run.connect(func(_fine): Audio.play("camera", 2.0, 0.0))
	var fuel := get_node_or_null("../FuelSystem")
	if fuel:
		fuel.refuelled.connect(func(_cost): Audio.play("refuel", 0.0))
	var story := get_node_or_null("../Story")
	if story:
		story.mission_completed.connect(func(): Audio.play("mission", -2.0, 0.0))
		story.chapter_completed.connect(func(): Audio.play("chapter", 0.0, 0.0))
	GameState.goal_completed.connect(func(_g): Audio.play("goal", -2.0, 0.0))
	_cutscene.line_shown.connect(func(): Audio.play("dialogue", -12.0))
	_last_money = GameState.money
	GameState.money_changed.connect(_on_money)

func _on_money(money: int) -> void:
	if money > _last_money:
		Audio.play("coins", -2.0)
	elif money < _last_money:
		Audio.play("cash", -4.0)
	_last_money = money

func _on_crash(speed: float) -> void:
	# Louder, heavier impacts for harder crashes.
	if speed < 8.0:
		Audio.play("bump", -2.0)
	else:
		Audio.play("crash", clampf(-8.0 + speed * 0.4, -8.0, 2.0))

func _process(_delta: float) -> void:
	# Race against Jet: chiptune; otherwise the lo-fi ride playlist.
	var racing: bool = _delivery.order_type == "race" and _delivery.state != _delivery.State.IDLE
	Audio.play_music("race" if racing else "ride")
	Audio.duck(_cutscene.playing)
	# Last 10 seconds of a delivery: tick every second.
	if _delivery.state == _delivery.State.TO_DROPOFF and _delivery.time_left < 10.0 and _delivery.time_left > 0.0:
		var s := ceili(_delivery.time_left)
		if s != _last_tick:
			_last_tick = s
			Audio.play("tick", -6.0, 0.0)
	else:
		_last_tick = -1
