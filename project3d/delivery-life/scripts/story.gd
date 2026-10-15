extends Node
## Story mode: five chapters, each with main missions that must all be completed to move on.
## Cutscenes play at the start of the story, between chapters and at the end. Chapters also
## unlock order types (chapter 1: standard only, 2: + express & fragile, 3+: + multi-drop) and
## offer special story orders (wedding cake, temple offering, the race to the skytrain station).
## After chapter 5 the story is finished and the game continues as free ride.

signal progress_changed
signal mission_completed
signal chapter_completed

const CHAPTERS := [
	{
		"title": "Chapter 1", "name": "First Day on the Job",
		"orders": ["standard"],
		"missions": [
			{"id": "deliveries", "text": "Complete 3 deliveries", "target": 3},
			{"id": "earn", "text": "Earn 500 THB from deliveries", "target": 500},
			{"id": "refuel", "text": "Refuel at a gas station", "target": 1},
		],
	},
	{
		"title": "Chapter 2", "name": "Rush Hour",
		"orders": ["standard", "express", "fragile"],
		"missions": [
			{"id": "express", "text": "Complete 3 express orders", "target": 3},
			{"id": "fragile_good", "text": "Deliver 2 fragile packages in 70%+ condition", "target": 2},
			{"id": "rating", "text": "Reach a 4.0 star rating", "target": 1},
		],
	},
	{
		"title": "Chapter 3", "name": "The Big Delivery",
		"orders": ["standard", "express", "fragile", "multi"],
		"missions": [
			{"id": "bike", "text": "Buy a new bike", "target": 1},
			{"id": "cake", "text": "Deliver Mama Noi's wedding cake (80%+ condition)", "target": 1},
		],
	},
	{
		"title": "Chapter 4", "name": "Night Shift",
		"orders": ["standard", "express", "fragile", "multi"],
		"missions": [
			{"id": "night", "text": "Complete 3 deliveries at night", "target": 3},
			{"id": "clean", "text": "Complete 3 deliveries in a row without crashing", "target": 3},
			{"id": "temple", "text": "Take the food offering to Wat Klang Mueang", "target": 1},
		],
	},
	{
		"title": "Chapter 5", "name": "Race Against Jet",
		"orders": ["standard", "express", "fragile", "multi"],
		"missions": [
			{"id": "rating45", "text": "Reach a 4.5 star rating", "target": 1},
			{"id": "vip", "text": "Complete 2 VIP orders", "target": 2},
			{"id": "race", "text": "Beat Jet to the Skytrain station", "target": 1},
		],
	},
]

# Fixed destinations of story orders (other orders go to random spots across town).
const City := preload("res://scripts/city.gd")
const Bangkok := preload("res://scripts/bangkok.gd")
const TEMPLE_DROP := Vector3((Bangkok.TEMPLE_BLOCK.x + 0.5) * City.PITCH + City.PITCH * 0.5 - City.KERB, 0, (Bangkok.TEMPLE_BLOCK.y + 0.5) * City.PITCH)   # temple gate (east side)
const STATION_DROP := Vector3(-City.PITCH + 3.0, 0, Bangkok.STATION_Z)   # under the skytrain station

# Cutscenes. Speakers: mek (player), pim (rider app dispatcher), grandpa, jet (rival), noi (bakery
# owner), monk (Luang Ta at Wat Klang Mueang).
const SCENES := {
	"intro": [
		{"title": "DELIVERY LIFE", "subtitle": "Chapter 1 - First Day on the Job", "shot": "overview", "time": 3.5},
		{"speaker": "mek", "text": "The big city. New start, new job... and one very old scooter.", "shot": "overview"},
		{"speaker": "grandpa", "text": "This scooter carried me for thirty years, Mek. Treat her well.", "shot": "bike_front"},
		{"speaker": "mek", "text": "I will, Grandpa. I'll save up for a bike of my own and pay you back. Promise."},
		{"speaker": "pim", "text": "Hi Mek! I'm Pim from the rider app. Welcome to the team!", "shot": "bike_side"},
		{"speaker": "pim", "text": "First day is easy: finish 3 deliveries, earn 500 baht, and fill up at a gas station."},
		{"speaker": "pim", "text": "Gas stations are the blue G on your map. Stop on the pump and press F to fill up."},
		{"speaker": "pim", "text": "New orders show up in the app on the left. Pick one with 1, 2 or 3."},
		{"speaker": "mek", "text": "Alright. Let's ride!", "shot": "bike_back"},
	],
	"chapter2": [
		{"speaker": "pim", "text": "Three deliveries on day one? Not bad for a rookie!", "shot": "bike_side"},
		{"speaker": "pim", "text": "Rush hour is coming. I'm unlocking express and fragile orders for you."},
		{"speaker": "pim", "text": "They pay more, but customers are picky. Fast for express, gentle for fragile."},
		{"speaker": "mek", "text": "Picky customers... great.", "shot": "bike_front"},
		{"title": "Chapter 2", "subtitle": "Rush Hour", "shot": "overview", "time": 3.0},
		{"speaker": "pim", "text": "Goal: 3 express orders, 2 fragile packages in good shape, and a 4-star rating.", "shot": "bike_back"},
	],
	"chapter3": [
		{"speaker": "jet", "text": "So you're the new guy everyone's talking about? Cute scooter.", "shot": "bike_front"},
		{"speaker": "mek", "text": "It gets the job done."},
		{"speaker": "jet", "text": "We'll see. Mama Noi's bakery has the biggest order of the year. She only hires the best."},
		{"speaker": "pim", "text": "Mek! Mama Noi asked for you! But she wants a rider with a proper bike.", "shot": "bike_side"},
		{"speaker": "pim", "text": "Buy a new bike at the shop, then I'll send you her order: a wedding cake. Don't you dare crash!"},
		{"title": "Chapter 3", "subtitle": "The Big Delivery", "shot": "overview", "time": 3.0},
	],
	"cake_ready": [
		{"speaker": "noi", "text": "So you're Mek. Pim says you're careful. This cake took me three days to make.", "shot": "bike_front"},
		{"speaker": "noi", "text": "It's in your rider app now. Take it to the wedding hall and keep it in one piece!"},
		{"speaker": "mek", "text": "Not a crumb out of place, Mama Noi. I promise."},
	],
	"chapter4": [
		{"speaker": "noi", "text": "Not a single crumb out of place! The bride is in tears - happy ones!", "shot": "bike_front"},
		{"speaker": "jet", "text": "Lucky ride, rookie. Let's see how you do when the sun goes down.", "shot": "bike_side"},
		{"speaker": "pim", "text": "Jet's right about one thing: the city never sleeps. I'm putting you on the night shift."},
		{"speaker": "pim", "text": "Dark roads, tired drivers. Ride clean - no crashes - and keep your headlight on the road."},
		{"speaker": "pim", "text": "Oh, and Luang Ta at Wat Klang Mueang needs food for the morning offering. I'll send it when you're ready."},
		{"title": "Chapter 4", "subtitle": "Night Shift", "shot": "temple", "time": 3.0},
		{"speaker": "mek", "text": "Night shift it is. Grandpa used to say the city is prettiest after dark.", "shot": "bike_back"},
	],
	"temple_ready": [
		{"speaker": "monk", "text": "Mek, is it? Pim told me about you. The food is for the monks' morning meal.", "shot": "temple"},
		{"speaker": "monk", "text": "Ride calmly, my son. Arriving safely is worth more than arriving fast."},
		{"speaker": "mek", "text": "I'll bring it to the temple gate, Luang Ta.", "shot": "bike_front"},
	],
	"chapter5": [
		{"speaker": "monk", "text": "Thank you, Mek. May your road always be clear.", "shot": "temple"},
		{"speaker": "jet", "text": "Still riding, rookie? Then let's settle this.", "shot": "bike_front"},
		{"speaker": "jet", "text": "One parcel, from the same shop to the Skytrain station. First one there is the best rider in town."},
		{"speaker": "pim", "text": "Mek, don't let him rush you. Only the top riders get VIP customers - earn a 4.5 rating and finish two VIP jobs first.", "shot": "bike_side"},
		{"speaker": "pim", "text": "When you're ready, the race order will appear in your app."},
		{"title": "Chapter 5", "subtitle": "Race Against Jet", "shot": "station", "time": 3.0},
	],
	"race_ready": [
		{"speaker": "jet", "text": "Express parcel, Skytrain station. Clock's ticking. Try to keep up!", "shot": "bike_front"},
		{"speaker": "mek", "text": "Just watch my tail light, Jet.", "shot": "bike_back"},
	],
	"race_lost": [
		{"speaker": "jet", "text": "Too slow, rookie! Want a rematch? It's in your app.", "shot": "bike_front"},
	],
	"ending": [
		{"speaker": "jet", "text": "...You beat me. Fair and square. You're good, rookie. See you on the road.", "shot": "station"},
		{"speaker": "pim", "text": "Mek, you did it. The whole city knows your name now.", "shot": "bike_side"},
		{"speaker": "grandpa", "text": "Mama Noi and Luang Ta both called me. I'm proud of you, Mek.", "shot": "overview"},
		{"speaker": "mek", "text": "This is only the beginning. There are a lot more deliveries out there."},
		{"title": "THE END", "subtitle": "Thanks for playing! Free ride unlocked.", "shot": "overview", "time": 4.0},
	],
}

var _delivery: Node
var _cutscene: Node
var _clock: Node
var _queued: Array[String] = []

func _ready() -> void:
	_delivery = get_node("../DeliveryManager")
	_cutscene = get_node("../Cutscene")
	_clock = get_node_or_null("../WorldClock")
	_delivery.delivered.connect(_on_delivered)
	_delivery.failed.connect(_on_failed)
	var bike := get_node_or_null("../Motorcycle")
	if bike:
		bike.crashed.connect(func(_speed): _reset_streak())
	var fuel := get_node_or_null("../FuelSystem")
	if fuel:
		fuel.refuelled.connect(func(_cost): _add("refuel", 1))
	GameState.bike_changed.connect(_check_bike)
	_cutscene.finished.connect(_play_next)
	# Start of the story (after one frame so the city and HUD exist).
	await get_tree().process_frame
	if active() and GameState.chapter == 1:
		_queue("intro")
	elif active() and GameState.chapter >= 4:
		# Also catches saves that finished the old 3-chapter story: they continue here.
		_queue("chapter%d" % GameState.chapter)
	_check_bike()
	_check_story_orders()

## True while the story is still running (chapter 1-5).
func active() -> bool:
	return GameState.chapter <= CHAPTERS.size()

func chapter_info() -> Dictionary:
	return CHAPTERS[GameState.chapter - 1] if active() else {}

## Order types the rider app may offer in the current chapter (all of them after the story).
func allowed_orders() -> Array:
	return chapter_info().get("orders", ["standard", "express", "fragile", "multi"]) if active() else ["standard", "express", "fragile", "multi"]

func progress(mission_id: String) -> int:
	return int(GameState.story_progress.get(mission_id, 0))

func mission_done(m: Dictionary) -> bool:
	return progress(m["id"]) >= m["target"]

## The special order the app should offer right now ("" = none): the wedding cake in chapter 3
## (once the new bike has been bought), the temple offering in chapter 4 (after the night
## deliveries) and the race in chapter 5 (once the VIP jobs are done).
func special_order() -> String:
	if GameState.chapter == 3 and progress("bike") >= 1 and progress("cake") < 1 and "cake_ready" in GameState.seen_scenes:
		return "cake"
	if GameState.chapter == 4 and progress("night") >= 3 and progress("temple") < 1 and "temple_ready" in GameState.seen_scenes:
		return "temple"
	if GameState.chapter == 5 and progress("vip") >= 2 and progress("race") < 1 and "race_ready" in GameState.seen_scenes:
		return "race"
	return ""

## Fixed drop-off for a story order, or null for a random one.
func special_destination(type: String) -> Variant:
	match type:
		"temple":
			return TEMPLE_DROP
		"race":
			return STATION_DROP
	return null

# ------------------------------------------------------------------ progress

func _add(mission_id: String, amount: int) -> void:
	if not active():
		return
	for m in chapter_info()["missions"]:
		if m["id"] == mission_id and not mission_done(m):
			GameState.story_progress[mission_id] = mini(progress(mission_id) + amount, m["target"])
			progress_changed.emit()
			if mission_done(m):
				_delivery.message.emit(tr("Mission complete: %s") % tr(m["text"]))
				mission_completed.emit()
	_check_chapter()

func _on_delivered(pay: int) -> void:
	var type: String = _delivery.order_type
	var cond: float = _delivery.condition
	_add("deliveries", 1)
	_add("earn", pay)
	if type == "express":
		_add("express", 1)
	if type == "fragile" and cond >= 70.0:
		_add("fragile_good", 1)
	if type == "cake":
		if cond >= 80.0:
			_add("cake", 1)
		else:
			_delivery.message.emit(tr("Mama Noi: \"The cake is ruined!\" She'll bake another one - try again."))
	if GameState.ratings.size() >= 3 and GameState.rating() >= 4.0:
		_add("rating", 1)
	if _clock and _clock.night:
		_add("night", 1)
	if type == "vip":
		_add("vip", 1)
	if type == "temple":
		_add("temple", 1)
	if type == "race":
		_add("race", 1)
	if GameState.ratings.size() >= 3 and GameState.rating() >= 4.5:
		_add("rating45", 1)
	_add("clean", 1)
	_check_story_orders()

## Chapter 4: a crash (or a failed job) breaks the no-crash delivery streak.
func _reset_streak() -> void:
	if GameState.chapter == 4 and progress("clean") > 0 and progress("clean") < 3:
		GameState.story_progress["clean"] = 0
		progress_changed.emit()
		_delivery.message.emit(tr("Crash! Your no-crash streak starts again."))

func _on_failed() -> void:
	_reset_streak()
	if _delivery.order_type == "race" and GameState.chapter == 5:
		_cutscene_once_more("race_lost")

## A cutscene that may play more than once (e.g. losing the race).
func _cutscene_once_more(scene_id: String) -> void:
	GameState.seen_scenes.erase(scene_id)
	_queue(scene_id)

## Story orders become available: play their short cutscene first.
func _check_story_orders() -> void:
	if GameState.chapter == 4 and progress("night") >= 3:
		_queue("temple_ready")
	if GameState.chapter == 5 and progress("vip") >= 2:
		_queue("race_ready")

func _check_bike() -> void:
	if GameState.owned.size() > 1:
		_add("bike", 1)
		if GameState.chapter == 3 and "cake_ready" not in GameState.seen_scenes:
			_queue("cake_ready")

func _check_chapter() -> void:
	if not active():
		return
	for m in chapter_info()["missions"]:
		if not mission_done(m):
			return
	# Chapter cleared: move on and play the matching cutscene.
	chapter_completed.emit()
	GameState.chapter += 1
	GameState.story_progress = {}
	GameState.save_game()
	progress_changed.emit()
	match GameState.chapter:
		2:
			_queue("chapter2")
		3:
			_queue("chapter3")
			_check_bike()   # already owns another bike? then that mission is done straight away
		4:
			_queue("chapter4")
		5:
			_queue("chapter5")
			# Already at 4.5 stars? Then that mission is done straight away.
			if GameState.ratings.size() >= 3 and GameState.rating() >= 4.5:
				_add("rating45", 1)
		_:
			_cutscene_once_more("ending")   # saves from the old 3-chapter story already saw an ending

# ------------------------------------------------------------------ cutscenes

func _queue(scene_id: String) -> void:
	if scene_id in GameState.seen_scenes or scene_id in _queued:
		return
	_queued.append(scene_id)
	if not _cutscene.playing:
		_play_next()

func _play_next() -> void:
	if _queued.is_empty() or _cutscene.playing:
		return
	var id: String = _queued.pop_front()
	GameState.seen_scenes.append(id)
	GameState.save_game()
	_cutscene.play(SCENES[id])
