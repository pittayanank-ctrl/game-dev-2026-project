extends Control
## North-up minimap drawn from the city grid: blocks, the shop, traffic, the current delivery target
## (pinned to the edge when it is out of range) and the player arrow in the middle.

const City := preload("res://scripts/city.gd")

const SIZE := 210.0
const RANGE := 120.0              # metres from the centre to the edge of the map
const BG := Color(0.2, 0.21, 0.25, 0.92)
const BLOCK := Color(0.5, 0.55, 0.52)
const SHOP := Color(0.98, 0.8, 0.15)
const CAR := Color(0.85, 0.85, 0.9, 0.8)

var player: Node3D
var delivery: Node3D
var traffic: Node3D

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

var _redraw_timer := 0.0
func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0.0 and is_visible_in_tree():
		_redraw_timer = 1.0 / 15.0
		queue_redraw()

func _to_map(world: Vector3) -> Vector2:
	var rel := Vector2(world.x - player.global_position.x, world.z - player.global_position.z)
	return Vector2(SIZE, SIZE) * 0.5 + rel * (SIZE * 0.5 / RANGE)

func _draw() -> void:
	if player == null:
		return
	var scale := SIZE * 0.5 / RANGE
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), BG)
	# City blocks (the space between roads).
	var inner := (City.PITCH - City.ROAD_WIDTH) * scale
	for i in range(-City.GRID, City.GRID):
		for j in range(-City.GRID, City.GRID):
			var c := _to_map(City.block_centre(i, j))
			if c.x < -inner or c.y < -inner or c.x > SIZE + inner or c.y > SIZE + inner:
				continue
			draw_rect(Rect2(c - Vector2(inner, inner) * 0.5, Vector2(inner, inner)), BLOCK)
	draw_circle(_to_map(City.SHOP_POS), 5.0, SHOP)
	for g in City.gas_stations():
		var gp := _to_map(g)
		draw_circle(gp, 6.0, Color(0.15, 0.6, 0.85))
		draw_string(UITheme.font, gp + Vector2(-4, 4), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	if traffic:
		for car in traffic.cars:
			if not car.waiting:
				draw_circle(_to_map(car.node.global_position), 1.8, CAR)
	# Delivery target, clamped to the map edge when far away.
	if delivery:
		var target = delivery.target_position()
		if target != null:
			var p := _to_map(target)
			var centre := Vector2(SIZE, SIZE) * 0.5
			var off := p - centre
			var limit := SIZE * 0.5 - 8.0
			if absf(off.x) > limit or absf(off.y) > limit:
				off *= limit / maxf(absf(off.x), absf(off.y))
			draw_circle(centre + off, 6.0, delivery.target_color())
			draw_arc(centre + off, 6.0, 0, TAU, 16, Color.BLACK, 1.5)
	# Player arrow pointing where the bike faces.
	var fwd := -player.global_transform.basis.z
	var dir := Vector2(fwd.x, fwd.z).normalized()
	var right := Vector2(-dir.y, dir.x)
	var c0 := Vector2(SIZE, SIZE) * 0.5
	draw_colored_polygon(PackedVector2Array([c0 + dir * 9.0, c0 - dir * 6.0 + right * 6.0, c0 - dir * 3.0, c0 - dir * 6.0 - right * 6.0]), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(1, 1, 1, 0.35), false, 2.0)
