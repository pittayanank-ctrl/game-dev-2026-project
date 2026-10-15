extends Node
## Autoload "UITheme": one Theme for every screen (menus, shop, HUD, dialogs), applied to the root
## window so all Controls pick it up. Also exposes the palette and small style helpers.

const ACCENT := Color(0.98, 0.78, 0.16)
const ACCENT_DARK := Color(0.78, 0.58, 0.05)
const TEXT := Color(0.94, 0.95, 0.98)
const TEXT_DIM := Color(0.64, 0.69, 0.78)
const BG := Color(0.07, 0.09, 0.13, 0.86)
const BG_SOLID := Color(0.08, 0.1, 0.15, 0.97)
const SURFACE := Color(0.15, 0.18, 0.25)
const SURFACE_HOVER := Color(0.2, 0.24, 0.33)
const GOOD := Color(0.35, 0.85, 0.5)
const BAD := Color(0.95, 0.38, 0.35)
const INFO := Color(0.35, 0.65, 1.0)

var font: Font
var theme: Theme

func _ready() -> void:
	# Sarabun (OFL, bundled) covers Latin and Thai. Browsers can't use system fonts, so the web
	# build uses it directly; on desktop it is the fallback for Thai behind the system font.
	var bundled: FontFile = load("res://assets/fonts/Sarabun-SemiBold.ttf")
	if OS.has_feature("web"):
		font = bundled
		ThemeDB.fallback_font = bundled   # anything not covered by our theme still gets Thai
	else:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Helvetica", "Arial"])
		f.font_weight = 600
		f.fallbacks = [bundled]
		font = f
	theme = _build()
	# Our UI lives under CanvasLayers, which don't pass a Window's theme down to their Controls,
	# so merge our styles into Godot's default theme: that one applies to every Control.
	ThemeDB.get_default_theme().merge_with(theme)
	get_tree().root.theme = theme

static func box(color: Color, radius := 12, border := Color(0, 0, 0, 0), border_width := 0, pad := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	if pad > 0.0:
		sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

## Rounded translucent card used by the HUD.
static func card(pad := 12.0) -> StyleBoxFlat:
	return box(BG, 14, Color(1, 1, 1, 0.07), 1, pad)

func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 18
	# Godot's built-in theme sets a font on each control type, which beats `default_font`,
	# so set ours explicitly for every type we use.
	for type in ["Label", "Button", "CheckBox", "LineEdit", "TooltipLabel", "ProgressBar"]:
		t.set_font("font", type, font)
	t.set_font("normal_font", "RichTextLabel", font)
	t.set_font("title_font", "Window", font)

	# Buttons: dark rounded surface, accent ring on hover/focus, accent fill when pressed.
	var normal := box(SURFACE, 9, Color(1, 1, 1, 0.06), 1)
	normal.set_content_margin_all(10)
	var hover := box(SURFACE_HOVER, 9, ACCENT, 2)
	hover.set_content_margin_all(10)
	var pressed := box(ACCENT_DARK, 9, ACCENT, 2)
	pressed.set_content_margin_all(10)
	var disabled := box(Color(0.13, 0.15, 0.2, 0.9), 9, Color(1, 1, 1, 0.05), 1)
	disabled.set_content_margin_all(10)
	var focus := box(Color(0, 0, 0, 0), 9, Color(ACCENT, 0.8), 2)
	for type in ["Button", "CheckBox"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_pressed_color", type, Color(0.1, 0.08, 0.02))
		t.set_color("font_hover_pressed_color", type, Color(0.1, 0.08, 0.02))
		t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.85))

	t.set_stylebox("panel", "PanelContainer", box(BG_SOLID, 14, Color(1, 1, 1, 0.07), 1))
	t.set_stylebox("panel", "Panel", box(BG_SOLID, 14, Color(1, 1, 1, 0.07), 1))
	t.set_color("font_color", "Label", TEXT)

	# Sliders and progress bars.
	t.set_stylebox("slider", "HSlider", box(SURFACE, 4, Color(0, 0, 0, 0), 0, 3.0))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 4, Color(0, 0, 0, 0), 0, 3.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 4, Color(0, 0, 0, 0), 0, 3.0))
	var knob := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	knob.fill(Color(0, 0, 0, 0))
	for y in 18:
		for x in 18:
			var d := Vector2(x - 8.5, y - 8.5).length()
			if d < 8.5:
				knob.set_pixel(x, y, TEXT if d < 6.5 else ACCENT)
	var knob_tex := ImageTexture.create_from_image(knob)
	t.set_icon("grabber", "HSlider", knob_tex)
	t.set_icon("grabber_highlight", "HSlider", knob_tex)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), 5))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 5))

	t.set_stylebox("panel", "TooltipPanel", box(BG_SOLID, 8, ACCENT, 1, 8.0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("separator", "HSeparator", box(Color(1, 1, 1, 0.1), 1))
	t.set_constant("separation", "HSeparator", 12)
	t.set_stylebox("panel", "AcceptDialog", box(BG_SOLID, 12, ACCENT, 1, 16.0))
	return t

## Small "–" / "+" button that collapses HUD panels: hides `targets` and remembers the choice
## (Settings.hud_collapsed[key]). `on_toggle(open)` runs after every change.
func collapse_button(key: String, targets: Array, on_toggle := Callable()) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 22)
	b.add_theme_font_size_override("font_size", 15)
	b.tooltip_text = tr("Show / hide")
	for state in ["normal", "hover", "pressed"]:
		var sb := box(Color(1, 1, 1, 0.08 if state == "normal" else 0.18), 6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(state, sb)
	var apply := func(open: bool) -> void:
		b.text = "–" if open else "+"
		for t in targets:
			if is_instance_valid(t):
				t.visible = open
		if on_toggle.is_valid():
			on_toggle.call(open)
	apply.call(not Settings.hud_collapsed.get(key, false))
	b.pressed.connect(func():
		var open: bool = Settings.hud_collapsed.get(key, false)   # was collapsed -> open it
		Settings.hud_collapsed[key] = not open
		Settings.save()
		apply.call(open))
	return b
