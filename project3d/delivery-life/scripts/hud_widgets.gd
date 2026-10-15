extends RefCounted
## Small custom-drawn HUD widgets: arc speedometer and the direction-arrow badge.

class Speedometer extends Control:
	var value := 0.0          # km/h
	var max_value := 100.0
	var fuel := 1.0           # 0..1

	func _init() -> void:
		custom_minimum_size = Vector2(170, 170)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		var start := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		draw_circle(c, r + 6.0, UITheme.BG)
		draw_arc(c, r - 6.0, start, start + sweep, 48, Color(1, 1, 1, 0.1), 9.0, true)
		var ratio := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
		if ratio > 0.0:
			var col := UITheme.ACCENT.lerp(UITheme.BAD, smoothstep(0.75, 1.0, ratio))
			draw_arc(c, r - 6.0, start, start + sweep * ratio, 48, col, 9.0, true)
		var f := UITheme.font
		var num := str(int(value))
		var size_big := 46
		var w := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, size_big).x
		draw_string(f, c + Vector2(-w * 0.5, 12), num, HORIZONTAL_ALIGNMENT_LEFT, -1, size_big, UITheme.TEXT)
		var unit := "km/h"
		var uw := f.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(f, c + Vector2(-uw * 0.5, 36), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.TEXT_DIM)
		# Fuel gauge along the bottom of the dial.
		var bar := Rect2(c + Vector2(-34, 50), Vector2(68, 7))
		draw_rect(bar, Color(1, 1, 1, 0.1))
		var fcol := UITheme.BAD if fuel < 0.25 else UITheme.INFO
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fuel, 0.0, 1.0), bar.size.y)), fcol)
		draw_string(f, bar.position + Vector2(-14, 8), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fcol)

## Streaks rushing in from the screen edges at high speed.
class SpeedLines extends Control:
	var strength := 0.0       # 0..1
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if strength <= 0.01:
			return
		var c := size * 0.5
		var radius := size.length() * 0.5
		for n in int(10 + 22 * strength):
			var a := _rng.randf() * TAU
			var dir := Vector2(cos(a), sin(a))
			var outer := c + dir * radius
			var inner := c + dir * radius * _rng.randf_range(0.55, 0.8)
			draw_line(inner, outer, Color(1, 1, 1, 0.12 * strength), _rng.randf_range(1.0, 3.0))

class ArrowBadge extends Control:
	var angle := 0.0          # screen rotation, 0 = straight ahead
	var color := Color.WHITE
	var distance := 0

	func _init() -> void:
		custom_minimum_size = Vector2(84, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 38)
		draw_circle(c, 32.0, UITheme.BG)
		draw_arc(c, 32.0, 0, TAU, 40, Color(color, 0.6), 2.0, true)
		var pts := PackedVector2Array([Vector2(0, -20), Vector2(15, 14), Vector2(0, 6), Vector2(-15, 14)])
		var xf := Transform2D(angle, c)
		draw_colored_polygon(xf * pts, color)
		var txt := "%d m" % distance
		var f := UITheme.font
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string_outline(f, Vector2(c.x - w * 0.5, 90), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(c.x - w * 0.5, 90), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.TEXT)
