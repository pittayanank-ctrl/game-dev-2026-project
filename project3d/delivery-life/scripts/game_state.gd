extends Node
## Autoload "GameState": money, owned bikes, upgrades, career stats, goals, day counter, save/load.

signal money_changed(amount: int)
signal bike_changed
signal goal_completed(goal: Dictionary)

const SAVE_PATH := "user://save.json"

# Ids stay the same when a slot gets a new bike, so old saves keep working ("sport" is the
# Giorno, "super" the Wave 125). "model" picks the 3D model (see motorcycle.gd MODELS); bikes without one use the PCX model.
const BIKES: Array[Dictionary] = [
	{"id": "starter", "name": "Used Scooter", "model": "oldscooter", "price": 0, "max_speed": 18.0, "acceleration": 8.0, "turn_speed": 1.8, "brake_force": 18.0, "tank": 3.0, "economy": 1.2},
	{"id": "pcx", "name": "PCX", "price": 1500, "max_speed": 26.0, "acceleration": 12.0, "turn_speed": 2.0, "brake_force": 24.0, "tank": 4.0, "economy": 1.15},
	{"id": "sport", "name": "Giorno", "model": "giorno", "price": 5000, "max_speed": 36.0, "acceleration": 16.0, "turn_speed": 2.2, "brake_force": 30.0, "tank": 5.0, "economy": 1.05},
	{"id": "super", "name": "Wave 125", "model": "wave125", "price": 12000, "max_speed": 48.0, "acceleration": 22.0, "turn_speed": 2.4, "brake_force": 36.0, "tank": 6.0, "economy": 0.95},
	{"id": "forza", "name": "Forza 350", "model": "forza350", "price": 20000, "max_speed": 52.0, "acceleration": 24.0, "turn_speed": 2.6, "brake_force": 40.0, "tank": 7.0, "economy": 0.9},
]

# Fuel: litres per tank and km per litre are in BIKES ("tank", "economy"); price per litre here.
const FUEL_PRICE := 25

# Customer rating: the average of the last RATING_WINDOW deliveries (1-5 stars) scales pay and
# unlocks VIP orders.
const RATING_WINDOW := 20
const VIP_MIN_RATING := 4.5
const VIP_MIN_RATINGS := 5

# Upgrades: each level adds `per_level` of the bike's base stat. Level n costs
# UPGRADE_COST_FRACTION * n of the bike's value (at least UPGRADE_MIN_VALUE), so a full upgrade
# line costs about 90% of the bike: upgrading never beats simply buying the next bike.
const MAX_UPGRADE_LEVEL := 5
const UPGRADE_COST_FRACTION := 0.06
const UPGRADE_MIN_VALUE := 800
const UPGRADES: Array[Dictionary] = [
	{"id": "top_speed", "name": "Engine Tuning", "stat": "max_speed", "per_level": 0.06},
	{"id": "acceleration", "name": "Turbo Kit", "stat": "acceleration", "per_level": 0.10},
	{"id": "handling", "name": "Suspension", "stat": "turn_speed", "per_level": 0.06},
	{"id": "braking", "name": "Brake Pads", "stat": "brake_force", "per_level": 0.12},
]

# Zones the player can repaint in the shop. Other zones are fixed in motorcycle.gd (FIXED_ZONE_COLORS).
const ZONES: Array[Dictionary] = [
	{"id": "body", "name": "Body"},
]

# Paint colours. Price 0 = free from the start.
const COLORS: Array[Dictionary] = [
	{"id": "white", "name": "White", "color": Color("f8f8f8"), "price": 0},
	{"id": "black", "name": "Black", "color": Color("282828"), "price": 0},
	{"id": "red", "name": "Red", "color": Color("c3101b"), "price": 300},
	{"id": "blue", "name": "Blue", "color": Color("0042b8"), "price": 300},
	{"id": "skyblue", "name": "Sky Blue", "color": Color("0b8ded"), "price": 300},
	{"id": "yellow", "name": "Yellow", "color": Color("f8d600"), "price": 300},
	{"id": "orange", "name": "Orange", "color": Color("f09700"), "price": 300},
	{"id": "khaki", "name": "Khaki", "color": Color("a5a075"), "price": 500},
]

# Long-term goals, checked in order of the list. `stat` is a key of `stats` (or a special check),
# `target` the value to reach, `reward` paid once on completion.
const GOALS: Array[Dictionary] = [
	{"id": "first_delivery", "text": "Complete your first delivery", "stat": "deliveries", "target": 1, "reward": 100},
	{"id": "deliveries_10", "text": "Complete 10 deliveries", "stat": "deliveries", "target": 10, "reward": 300},
	{"id": "earn_2000", "text": "Earn 2,000 THB from deliveries", "stat": "earned", "target": 2000, "reward": 300},
	{"id": "new_bike", "text": "Buy a new bike", "stat": "bikes_owned", "target": 2, "reward": 400},
	{"id": "perfect_5", "text": "Make 5 deliveries without damage", "stat": "perfect", "target": 5, "reward": 400},
	{"id": "express_5", "text": "Complete 5 express orders", "stat": "express", "target": 5, "reward": 500},
	{"id": "fragile_5", "text": "Deliver 5 fragile packages", "stat": "fragile", "target": 5, "reward": 500},
	{"id": "rating_45", "text": "Reach a 4.5 star rating", "stat": "rating45", "target": 1, "reward": 1000},
	{"id": "max_upgrade", "text": "Max out any upgrade", "stat": "max_upgrade", "target": 1, "reward": 800},
	{"id": "deliveries_50", "text": "Complete 50 deliveries", "stat": "deliveries", "target": 50, "reward": 1500},
	{"id": "super_bike", "text": "Own the Wave 125", "stat": "super_bike", "target": 1, "reward": 2000},
	{"id": "forza", "text": "Own the Forza 350", "stat": "forza", "target": 1, "reward": 3000},
]

var money := 0
var owned: Array[String] = ["starter"]
var current_id := "starter"
var owned_colors: Array[String] = ["white", "black"]
var zone_colors := {"body": "white"}   # zone id -> colour id
var upgrades := {}                      # bike id -> {upgrade id -> level}
var day := 1
var tutorial_done := false
var stats := {"deliveries": 0, "earned": 0, "perfect": 0, "express": 0, "fragile": 0, "best_wheelie": 0}
var goals_done: Array[String] = []
var fuel := 3.0                 # litres in the current bike
var ratings: Array[int] = []    # most recent star ratings, newest last
var chapter := 1                # story chapter (1-5); 6 = story finished, free ride
var story_progress := {}        # objective id -> progress in the current chapter
var seen_scenes: Array[String] = []   # cutscenes already played

# Per-day numbers for the end-of-day summary (not saved; a day restarts if you quit mid-way).
var today := {}

func _ready() -> void:
	reset_today()
	fuel = fuel_capacity()
	load_game()

# Money cheat: "<" (the , key) = +1,000 THB, ">" (the . key) = +10,000 THB.
# Shift does not matter, so both "," / "<" and "." / ">" work. Works in exported builds too;
# set CHEATS_ENABLED to false to turn it off for a public release.
const CHEATS_ENABLED := true

func _unhandled_input(event: InputEvent) -> void:
	if not CHEATS_ENABLED:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_COMMA:
			add_money(1000)
		elif event.physical_keycode == KEY_PERIOD:
			add_money(10000)

# ------------------------------------------------------------------ bikes & upgrades

func current_bike() -> Dictionary:
	return bike_by_id(current_id)

func bike_by_id(id: String) -> Dictionary:
	for b in BIKES:
		if b["id"] == id:
			return b
	return BIKES[0]

func upgrade_def(up_id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == up_id:
			return u
	return {}

func upgrade_level(bike_id: String, up_id: String) -> int:
	return int(upgrades.get(bike_id, {}).get(up_id, 0))

func upgrade_cost(bike_id: String, up_id: String) -> int:
	var value := maxf(float(bike_by_id(bike_id)["price"]), UPGRADE_MIN_VALUE)
	return int(round(value * UPGRADE_COST_FRACTION * (upgrade_level(bike_id, up_id) + 1) / 10.0)) * 10

func buy_upgrade(bike_id: String, up_id: String) -> bool:
	if bike_id not in owned or upgrade_level(bike_id, up_id) >= MAX_UPGRADE_LEVEL:
		return false
	var cost := upgrade_cost(bike_id, up_id)
	if money < cost:
		return false
	money -= cost
	if not upgrades.has(bike_id):
		upgrades[bike_id] = {}
	upgrades[bike_id][up_id] = upgrade_level(bike_id, up_id) + 1
	money_changed.emit(money)
	bike_changed.emit()
	check_goals()
	save_game()
	return true

## Base stats of a bike with its purchased upgrades applied (and the best possible value if `maxed`).
func effective_stats(bike_id: String, maxed := false) -> Dictionary:
	var b := bike_by_id(bike_id)
	var out := {}
	for stat in ["max_speed", "acceleration", "turn_speed", "brake_force"]:
		out[stat] = b[stat]
	for u in UPGRADES:
		var level := MAX_UPGRADE_LEVEL if maxed else upgrade_level(bike_id, u["id"])
		out[u["stat"]] = b[u["stat"]] * (1.0 + u["per_level"] * level)
	return out

func buy_bike(id: String) -> bool:
	var b := bike_by_id(id)
	if id in owned or money < b["price"]:
		return false
	money -= b["price"]
	owned.append(id)
	money_changed.emit(money)
	equip_bike(id)
	fuel = fuel_capacity()   # new bikes come with a full tank
	check_goals()
	return true

func equip_bike(id: String) -> void:
	if id not in owned:
		return
	current_id = id
	fuel = minf(fuel, fuel_capacity())
	bike_changed.emit()
	save_game()

# ------------------------------------------------------------------ paint

func color_by_id(id: String) -> Dictionary:
	for c in COLORS:
		if c["id"] == id:
			return c
	return COLORS[0]

func buy_color(zone: String, id: String) -> bool:
	var c := color_by_id(id)
	if id in owned_colors or money < c["price"]:
		return false
	money -= c["price"]
	owned_colors.append(id)
	money_changed.emit(money)
	equip_color(zone, id)
	return true

func equip_color(zone: String, id: String) -> void:
	if id not in owned_colors:
		return
	zone_colors[zone] = id
	bike_changed.emit()
	save_game()

# ------------------------------------------------------------------ money

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
	save_game()

## Takes up to `amount` THB (never below zero) and returns what was actually paid.
func spend_money(amount: int) -> int:
	var paid := mini(amount, money)
	money -= paid
	money_changed.emit(money)
	save_game()
	return paid

# ------------------------------------------------------------------ fuel

func fuel_capacity() -> float:
	return float(current_bike()["tank"])

## Litres burnt for `metres` ridden on the current bike.
func fuel_for_distance(metres: float) -> float:
	return metres / 1000.0 / float(current_bike()["economy"])

# ------------------------------------------------------------------ rating

## Average stars, or 0 when there are no ratings yet.
func rating() -> float:
	if ratings.is_empty():
		return 0.0
	var total := 0
	for r in ratings:
		total += r
	return float(total) / ratings.size()

## Pay multiplier from the rating: 0.85x at 1 star up to 1.2x at 5 stars (1.0x with no ratings).
func rating_multiplier() -> float:
	if ratings.is_empty():
		return 1.0
	return lerpf(0.85, 1.2, (rating() - 1.0) / 4.0)

func vip_unlocked() -> bool:
	return ratings.size() >= VIP_MIN_RATINGS and rating() >= VIP_MIN_RATING

func add_rating(stars: int) -> void:
	ratings.append(clampi(stars, 1, 5))
	while ratings.size() > RATING_WINDOW:
		ratings.remove_at(0)
	today["stars"] += stars
	today["rated"] += 1
	check_goals()

# ------------------------------------------------------------------ career stats, goals, days

func reset_today() -> void:
	today = {"deliveries": 0, "failed": 0, "earned": 0, "damage_lost": 0, "distance": 0.0, "crashes": 0,
		"fuel_spent": 0, "fines": 0, "stars": 0, "rated": 0}

## Called by the delivery manager when an order is completed.
func record_delivery(order_type: String, pay: int, damage_lost: int, perfect: bool) -> void:
	stats["deliveries"] += 1
	stats["earned"] += pay
	if perfect:
		stats["perfect"] += 1
	if order_type == "express":
		stats["express"] += 1
	elif order_type == "fragile":
		stats["fragile"] += 1
	today["deliveries"] += 1
	today["earned"] += pay
	today["damage_lost"] += damage_lost
	add_money(pay)
	check_goals()

func record_failed() -> void:
	today["failed"] += 1

func goal_progress(g: Dictionary) -> int:
	match g["stat"]:
		"bikes_owned":
			return owned.size()
		"super_bike":
			return 1 if "super" in owned else 0
		"forza":
			return 1 if "forza" in owned else 0
		"rating45":
			return 1 if ratings.size() >= VIP_MIN_RATINGS and rating() >= 4.5 else 0
		"max_upgrade":
			for bid in upgrades:
				for uid in upgrades[bid]:
					if int(upgrades[bid][uid]) >= MAX_UPGRADE_LEVEL:
						return 1
			return 0
	return int(stats.get(g["stat"], 0))

## First goal that is not done yet (empty when everything is complete).
func next_goal() -> Dictionary:
	for g in GOALS:
		if g["id"] not in goals_done:
			return g
	return {}

func check_goals() -> void:
	for g in GOALS:
		if g["id"] in goals_done:
			continue
		if goal_progress(g) >= g["target"]:
			goals_done.append(g["id"])
			money += g["reward"]
			money_changed.emit(money)
			goal_completed.emit(g)
	save_game()

func finish_day() -> void:
	day += 1
	reset_today()
	save_game()

func complete_tutorial() -> void:
	tutorial_done = true
	save_game()

# ------------------------------------------------------------------ save / load

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Wipes progress and writes a fresh save.
func reset_game() -> void:
	money = 0
	owned = ["starter"]
	current_id = "starter"
	owned_colors = ["white", "black"]
	zone_colors = {"body": "white"}
	upgrades = {}
	day = 1
	tutorial_done = false
	stats = {"deliveries": 0, "earned": 0, "perfect": 0, "express": 0, "fragile": 0}
	goals_done = []
	ratings = []
	chapter = 1
	story_progress = {}
	seen_scenes = []
	fuel = fuel_capacity()
	reset_today()
	money_changed.emit(money)
	bike_changed.emit()
	save_game()

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"money": money, "owned": owned, "current": current_id,
			"owned_colors": owned_colors, "zone_colors": zone_colors, "upgrades": upgrades,
			"day": day, "tutorial_done": tutorial_done, "stats": stats, "goals_done": goals_done,
			"fuel": fuel, "ratings": ratings,
			"chapter": chapter, "story_progress": story_progress, "seen_scenes": seen_scenes,
		}))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (data is Dictionary):
		return
	money = int(data.get("money", 0))
	owned.clear()
	for id in data.get("owned", ["starter"]):
		owned.append(str(id))
	if "wave" in owned:   # the Wave 125 used to be a separate cheap bike before it took the "super" slot
		owned.erase("wave")
		if "super" not in owned:
			owned.append("super")
	current_id = str(data.get("current", "starter"))
	if current_id == "wave":
		current_id = "super"
	if current_id not in owned:
		current_id = "starter"
	owned_colors.clear()
	for id in data.get("owned_colors", ["white", "black"]):
		owned_colors.append(str(id))
	upgrades.clear()
	var saved_up = data.get("upgrades", {})
	if saved_up is Dictionary:
		for bid in saved_up:
			if saved_up[bid] is Dictionary:
				upgrades[str(bid)] = {}
				for uid in saved_up[bid]:
					upgrades[str(bid)][str(uid)] = clampi(int(saved_up[bid][uid]), 0, MAX_UPGRADE_LEVEL)
	var saved = data.get("zone_colors", {})
	if saved is Dictionary:
		for z in saved:
			if str(saved[z]) in owned_colors:
				zone_colors[str(z)] = str(saved[z])
	day = maxi(int(data.get("day", 1)), 1)
	# Saves from before the tutorial existed: skip it for players who have already made progress.
	tutorial_done = bool(data.get("tutorial_done", money > 0 or owned.size() > 1))
	var saved_stats = data.get("stats", {})
	if saved_stats is Dictionary:
		for k in stats:
			stats[k] = int(saved_stats.get(k, 0))
	goals_done.clear()
	for g in data.get("goals_done", []):
		goals_done.append(str(g))
	fuel = clampf(float(data.get("fuel", fuel_capacity())), 0.0, fuel_capacity())
	ratings.clear()
	for r in data.get("ratings", []):
		ratings.append(clampi(int(r), 1, 5))
	chapter = clampi(int(data.get("chapter", 1)), 1, 6)
	story_progress = {}
	var sp = data.get("story_progress", {})
	if sp is Dictionary:
		for k in sp:
			story_progress[str(k)] = int(sp[k])
	seen_scenes.clear()
	for sc in data.get("seen_scenes", []):
		seen_scenes.append(str(sc))
