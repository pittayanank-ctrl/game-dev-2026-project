extends Node
## Fuel: the bike burns fuel as it rides (see motorcycle.gd). On a gas station pad, press the
## refuel key (F) to open the gas station popup (see fuel_popup.gd) and buy fuel there.
## Fuel costs GameState.FUEL_PRICE per litre.

signal message(text: String)
signal refuelled(cost: int)

const City := preload("res://scripts/city.gd")
const STATION_RADIUS := 4.5
const LOW_FUEL := 0.25            # warn below this fraction of the tank

var _player: Node3D
var _warned_low := false
var _warned_empty := false

func _ready() -> void:
	_player = get_node("../Motorcycle")

func near_station() -> bool:
	var p := Vector3(_player.global_position.x, 0, _player.global_position.z)
	for s in City.gas_stations():
		if p.distance_to(s) < STATION_RADIUS:
			return true
	return false

## Litres that still fit in the tank.
func missing() -> float:
	return maxf(GameState.fuel_capacity() - GameState.fuel, 0.0)

## Price of `litres`, rounded up to whole baht.
func cost_of(litres: float) -> int:
	return ceili(litres * GameState.FUEL_PRICE - 0.001)

## Buy up to `litres` (limited by tank space and money). Returns litres actually bought.
func buy(litres: float) -> float:
	litres = minf(litres, missing())
	litres = minf(litres, float(GameState.money) / GameState.FUEL_PRICE)
	if litres < 0.01:
		return 0.0
	var paid := GameState.spend_money(cost_of(litres))
	GameState.fuel = minf(GameState.fuel + litres, GameState.fuel_capacity())
	GameState.today["fuel_spent"] += paid
	GameState.save_game()
	message.emit(tr("Refuelled: -%d THB") % paid)
	refuelled.emit(paid)
	return litres

func _physics_process(_delta: float) -> void:
	# Warnings.
	var ratio := GameState.fuel / GameState.fuel_capacity()
	if ratio > LOW_FUEL + 0.05:
		_warned_low = false
	if GameState.fuel > 0.01:
		_warned_empty = false
	if ratio <= LOW_FUEL and not _warned_low:
		_warned_low = true
		message.emit(tr("Low fuel! Find a gas station (blue G on the minimap)."))
	if GameState.fuel <= 0.0 and not _warned_empty:
		_warned_empty = true
		message.emit(tr("Out of fuel! Push the bike to a gas station."))
