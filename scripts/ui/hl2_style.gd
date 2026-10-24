class_name Hl2Style
## HL2 clientscheme.res values: FgColor 255 220 0 100, BgColor 0 0 0 76,
## BrightFg 255 220 0 255; HudNumbers = "HalfLife2" font, labels Verdana bold.

const FG := Color8(255, 220, 0, 100)
const FG_TEXT := Color8(255, 220, 0, 200)
const BRIGHT := Color8(255, 220, 0, 255)
const BG := Color8(0, 0, 0, 76)
const DAMAGED := Color8(180, 0, 0, 230)
const UNIT := 900.0 / 480.0  # HUD layout units (640x480) -> our 1600x900 canvas

static var _numbers: FontFile
static var _verdana: SystemFont
static var _verdana_bold: SystemFont


static func numbers_font() -> Font:
	if _numbers == null:
		_numbers = load("res://assets/fonts/halflife2.ttf")
	return _numbers


static func text_font(bold := true) -> Font:
	if bold:
		if _verdana_bold == null:
			_verdana_bold = SystemFont.new()
			_verdana_bold.font_names = PackedStringArray(["Verdana", "Tahoma", "DejaVu Sans"])
			_verdana_bold.font_weight = 700
		return _verdana_bold
	if _verdana == null:
		_verdana = SystemFont.new()
		_verdana.font_names = PackedStringArray(["Verdana", "Tahoma", "DejaVu Sans"])
	return _verdana


static func panel_style(bg := BG, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius * UNIT))
	sb.anti_aliasing = true
	return sb


static func label(text: String, size_px: float, color := FG_TEXT, bold := true) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = text_font(bold)
	ls.font_size = int(size_px)
	ls.font_color = color
	l.label_settings = ls
	return l


## Big HUD digits with the additive glow (HudNumbersGlow: blur 4).
static func number(text: String, size_px: float, color := FG_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = numbers_font()
	ls.font_size = int(size_px)
	ls.font_color = color
	ls.outline_size = int(size_px * 0.12)
	ls.outline_color = Color(color.r, color.g, color.b, 0.12)
	ls.shadow_size = int(size_px * 0.25)
	ls.shadow_color = Color(color.r, color.g, color.b, 0.18)
	ls.shadow_offset = Vector2.ZERO
	l.label_settings = ls
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", text_font(true))
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", BRIGHT)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -6.0))
	b.focus_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -8.0))
	b.pressed.connect(func(): Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -4.0))
	return b
