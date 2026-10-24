class_name UiKit
## Shared menu look built from HL2's GameUI scheme (platform SourceSchemeBase.res):
## MainMenu.TextColor White, MainMenu.DepressedTextColor 192 186 80,
## Menu.ArmedBgColor Orange 255 155 0, Slider.TrackColor 31 31 31,
## Slider.NobColor 108 108 108, fonts Verdana.

const ORANGE := Color8(255, 155, 0)
const PRESSED := Color8(192, 186, 80)
const TEXT := Color(1, 1, 1, 0.92)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const MENU_IDLE := Color(1, 1, 1, 0.62)
const FRAME_BG := Color(0.075, 0.075, 0.075, 0.97)
const TRACK := Color8(31, 31, 31)
const NOB := Color8(108, 108, 108)

static var _theme: Theme
static var _icons := {}


static func font(bold := false) -> Font:
	return Hl2Style.text_font(bold)


static func box(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 3, pad := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.anti_aliasing = true
	return sb


static func _img_icon(key: String, w: int, h: int, painter: Callable) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var c: Color = painter.call(x, y, w, h)
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


static func _disc(col: Color, r: float) -> Callable:
	return func(x: int, y: int, w: int, h: int) -> Color:
		var d := Vector2(x + 0.5 - w * 0.5, y + 0.5 - h * 0.5).length()
		var a := clampf(r - d + 0.5, 0.0, 1.0)
		return Color(col.r, col.g, col.b, col.a * a)


static func _switch(on: bool, hover: bool) -> Callable:
	return func(x: int, y: int, w: int, h: int) -> Color:
		var r := h * 0.5
		var cx := clampf(x + 0.5, r, w - r)
		var d := Vector2(x + 0.5 - cx, y + 0.5 - r).length()
		var a := clampf(r - d + 0.5, 0.0, 1.0)
		if a <= 0.0:
			return Color(0, 0, 0, 0)
		var knob_x := (w - r) if on else r
		var kd := Vector2(x + 0.5 - knob_x, y + 0.5 - r).length()
		if kd < r - 3.0:
			return Color(1, 1, 1, 1) if hover or on else Color(0.8, 0.8, 0.8, 1)
		var bg := ORANGE if on else Color(0.24, 0.24, 0.24)
		return Color(bg.r, bg.g, bg.b, a)


static func _arrow(col: Color) -> Callable:
	return func(x: int, y: int, w: int, h: int) -> Color:
		var fx := (x + 0.5) / w
		var fy := (y + 0.5) / h
		if fy > 0.3 and fy < 0.72 and absf(fx - 0.5) < (0.72 - fy) * 0.9:
			return col
		return Color(0, 0, 0, 0)


## The project-wide menu theme (dialogs, sliders, dropdowns, tabs, toggles).
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 18
	# labels
	t.set_color("font_color", "Label", TEXT)
	# dialog buttons
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.16), 1, 3, 14))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.12), ORANGE, 1, 3, 14))
	t.set_stylebox("pressed", "Button", box(Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.35), ORANGE, 1, 3, 14))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ORANGE, 2, 3, 14))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 1, 3, 14))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.BLACK)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 17)
	# segmented toggle (difficulty etc.): selected = solid orange
	t.set_type_variation("SegButton", "Button")
	t.set_stylebox("normal", "SegButton", box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 1, 2, 16))
	t.set_stylebox("hover", "SegButton", box(Color(1, 1, 1, 0.12), ORANGE, 1, 2, 16))
	t.set_stylebox("pressed", "SegButton", box(ORANGE, ORANGE, 1, 2, 16))
	t.set_stylebox("hover_pressed", "SegButton", box(ORANGE.lightened(0.15), Color.WHITE, 1, 2, 16))
	t.set_color("font_pressed_color", "SegButton", Color.BLACK)
	t.set_color("font_hover_pressed_color", "SegButton", Color.BLACK)
	# main-menu items: flat Verdana text like the HL2 GameMenu
	t.set_type_variation("MenuItem", "Button")
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		t.set_stylebox(st, "MenuItem", empty)
	t.set_color("font_color", "MenuItem", MENU_IDLE)
	t.set_color("font_hover_color", "MenuItem", Color.WHITE)
	t.set_color("font_focus_color", "MenuItem", Color.WHITE)
	t.set_color("font_pressed_color", "MenuItem", PRESSED)
	t.set_color("font_hover_pressed_color", "MenuItem", PRESSED)
	t.set_font_size("font_size", "MenuItem", 25)
	t.set_constant("outline_size", "MenuItem", 0)
	# panels / dialog frames
	t.set_stylebox("panel", "Panel", box(FRAME_BG, Color(1, 1, 1, 0.1), 1, 4, 0))
	t.set_stylebox("panel", "PanelContainer", box(FRAME_BG, Color(1, 1, 1, 0.1), 1, 4, 22))
	# sliders
	var track := box(TRACK, Color(1, 1, 1, 0.12), 1, 4, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.85), Color(0, 0, 0, 0), 0, 4, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _img_icon("grab", 22, 22, _disc(Color8(200, 200, 200), 9.5)))
	t.set_icon("grabber_highlight", "HSlider", _img_icon("grab_h", 22, 22, _disc(Color.WHITE, 10.5)))
	t.set_icon("tick", "HSlider", _img_icon("tick", 4, 10, func(_x, _y, _w, _h): return Color(1, 1, 1, 0.35)))
	t.set_constant("center_grabber", "HSlider", 0)
	# dropdowns
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(st, "OptionButton", t.get_stylebox(st, "Button"))
	t.set_icon("arrow", "OptionButton", _img_icon("arrow", 16, 16, _arrow(Color(1, 1, 1, 0.85))))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_font("font", "OptionButton", font(false))
	t.set_font_size("font_size", "OptionButton", 17)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.1, 0.1, 0.1, 0.97), Color(1, 1, 1, 0.18), 1, 2, 6))
	t.set_stylebox("hover", "PopupMenu", box(ORANGE, Color(0, 0, 0, 0), 0, 2, 6))
	t.set_color("font_hover_color", "PopupMenu", Color.BLACK)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_font_size("font_size", "PopupMenu", 17)
	t.set_constant("v_separation", "PopupMenu", 8)
	# toggles
	t.set_icon("checked", "CheckButton", _img_icon("sw_on", 44, 22, _switch(true, false)))
	t.set_icon("unchecked", "CheckButton", _img_icon("sw_off", 44, 22, _switch(false, false)))
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", StyleBoxEmpty.new() if st != "focus" else box(Color(0, 0, 0, 0), ORANGE, 1, 3, 4))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	# tabs
	t.set_stylebox("tab_selected", "TabBar", _tab(true))
	t.set_stylebox("tab_unselected", "TabBar", _tab(false))
	t.set_stylebox("tab_hovered", "TabBar", _tab(false, true))
	t.set_stylebox("tab_focus", "TabBar", box(Color(0, 0, 0, 0), ORANGE, 1, 2, 4))
	t.set_color("font_selected_color", "TabBar", Color.WHITE)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", Color.WHITE)
	t.set_font("font", "TabBar", font(true))
	t.set_font_size("font_size", "TabBar", 17)
	# scrolling lists
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sbar := box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 0)
	t.set_stylebox("scroll", "VScrollBar", sbar)
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ORANGE, Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ORANGE, Color(0, 0, 0, 0), 0, 3, 0))
	# text fields
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.18), 1, 3, 10))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.55), ORANGE, 1, 3, 10))
	t.set_stylebox("read_only", "LineEdit", box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.08), 1, 3, 10))
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.35))
	t.set_color("caret_color", "LineEdit", ORANGE)
	t.set_color("selection_color", "LineEdit", Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.4))
	t.set_font_size("font_size", "LineEdit", 17)
	# server list (VGUI ListPanel look)
	t.set_stylebox("panel", "Tree", box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 1, 2, 4))
	t.set_stylebox("focus", "Tree", box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.12), 1, 2, 4))
	t.set_stylebox("selected", "Tree", box(Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.55), Color(0, 0, 0, 0), 0, 0, 2))
	t.set_stylebox("selected_focus", "Tree", box(Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.7), Color(0, 0, 0, 0), 0, 0, 2))
	t.set_stylebox("title_button_normal", "Tree", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 0, 6))
	t.set_stylebox("title_button_hover", "Tree", box(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 0, 0, 6))
	t.set_stylebox("title_button_pressed", "Tree", box(Color(1, 1, 1, 0.2), Color(0, 0, 0, 0), 0, 0, 6))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("title_button_color", "Tree", TEXT_DIM)
	t.set_font("title_button_font", "Tree", font(true))
	t.set_font_size("title_button_font_size", "Tree", 14)
	t.set_font_size("font_size", "Tree", 17)
	t.set_constant("v_separation", "Tree", 8)
	t.set_constant("h_separation", "Tree", 10)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	_theme = t
	return t


static func _tab(selected: bool, hover := false) -> StyleBoxFlat:
	var sb := box(Color(1, 1, 1, 0.1 if selected else (0.06 if hover else 0.0)), Color(0, 0, 0, 0), 0, 0, 18)
	sb.border_color = ORANGE if selected else Color(1, 1, 1, 0.2 if hover else 0.0)
	sb.border_width_bottom = 3 if selected else (2 if hover else 0)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


# ---------------------------------------------------------------- widgets
static func label(text: String, size := 18, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _sounds(c: Control) -> void:
	c.mouse_entered.connect(func():
		if c is BaseButton and not (c as BaseButton).disabled:
			Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -8.0))
	if c is BaseButton:
		(c as BaseButton).pressed.connect(func(): Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0))


## Main-menu entry: one highlight at a time (mouse hover moves keyboard focus).
static func menu_item(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -8.0))
	b.pressed.connect(func(): Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0))
	return b


static func button(text: String, min_w := 150) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 42)
	b.focus_mode = Control.FOCUS_ALL
	_sounds(b)
	return b


## Labelled row: [title .......... control]
static func row(title: String, control: Control, title_w := 260) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var l := label(title, 18, TEXT)
	l.custom_minimum_size.x = title_w
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


## Slider with a live value readout. `fmt` gets the value.
static func slider(min_v: float, max_v: float, step: float, value: float, on_change: Callable, fmt := "%d") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(220, 24)
	s.focus_mode = Control.FOCUS_ALL
	var steps := int(round((max_v - min_v) / step))
	if steps <= 10:
		s.tick_count = steps + 1
		s.ticks_on_borders = true
	h.add_child(s)
	var v := label(fmt % value, 18, Color.WHITE, true)
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	s.value_changed.connect(func(x: float):
		v.text = fmt % x
		on_change.call(x))
	s.drag_ended.connect(func(_c): Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0))
	return h


static func dropdown(items: Array, selected: int, on_select: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(clampi(selected, 0, items.size() - 1))
	o.custom_minimum_size = Vector2(260, 42)
	o.fit_to_longest_item = false
	o.item_selected.connect(func(i: int):
		Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0)
		on_select.call(i))
	_sounds(o)
	return o


static func toggle(on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(func(v: bool):
		Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0)
		on_change.call(v))
	return c


## Segmented choice (one of N), e.g. difficulty.
static func segmented(items: Array, selected: int, on_select: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for i in items.size():
		var b := Button.new()
		b.text = str(items[i])
		b.theme_type_variation = "SegButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(118, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		var idx := i
		b.pressed.connect(func(): on_select.call(idx))
		_sounds(b)
		h.add_child(b)
	return h


## A keyboard key cap for the tutorial.
static func keycap(text: String, wide := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0.18, 0.18, 0.18), Color(1, 1, 1, 0.35), 1, 5, 10)
	sb.border_width_bottom = 4
	sb.border_color = Color(0.55, 0.55, 0.55)
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, 16, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 64 if wide else 26
	p.add_child(l)
	return p


static func text_field(text: String, placeholder: String, on_change: Callable, min_w := 260) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(min_w, 42)
	e.text_changed.connect(func(t: String): on_change.call(t))
	return e


static func section(text: String) -> Label:
	var l := label(text, 15, ORANGE, true)
	return l
