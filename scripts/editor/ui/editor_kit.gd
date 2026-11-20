class_name EditorKit
## Compact editor widgets and the editor theme (a copy of UiKit.theme() plus number fields,
## ItemList, PopupPanel, ColorPicker, HScrollBar, TextEdit, MenuButton / PopupMenu and tooltip
## styles); prompt() expands combos into modifier keycaps (C1 S25); icon() loads the editor's line
## icons. P10.
##
## Every widget's callback may take the value alone or the value and `final` (true when an edit
## ends: a typed number, the end of a drag, a picked colour): drags call it with final false while
## they run, so a tool can merge them into one undo step.

const ROW_H := 30
const FONT := 15

## Small text (hints, the status bar, list rows).
const FONT_SMALL := 13
## The label column of row().
const LABEL_W := 128
## A scroll bar's width (VScrollBar) or height (HScrollBar).
const BAR_W := 8.0
const OK_COLOR := Color(0.45, 0.85, 0.35)
const WARN_COLOR := Color(1.0, 0.82, 0.2)
const ERROR_COLOR := Color(1.0, 0.32, 0.25)
const INFO_COLOR := Color(0.45, 0.7, 1.0)
## Mouse buttons in prompts are words (no mouse icons ship).
const MOUSE_WORDS := {MOUSE_BUTTON_LEFT: "LEFT MOUSE", MOUSE_BUTTON_RIGHT: "RIGHT MOUSE",
	MOUSE_BUTTON_MIDDLE: "MIDDLE MOUSE", MOUSE_BUTTON_WHEEL_UP: "WHEEL", MOUSE_BUTTON_WHEEL_DOWN: "WHEEL"}
## The editor's line icons: 24 x 24 SVGs drawn for this game, 2 px strokes in currentColor. Loaded
## at run time like InputPrompts' Kenney icons (the folder has a .gdignore: Godot never imports it).
const ICON_DIR := "res://art/editor_icons/"
## Icon sizes: beside a button's text; on the top bar's icon buttons.
const ICON := 18
const ICON_BAR := 20
## Status names -> [file, colour] (the validation levels, the badge).
const STATUS := {"tick": ["status_ok", OK_COLOR], "ok": ["status_ok", OK_COLOR], "error": ["status_error", ERROR_COLOR],
	"warning": ["status_warning", WARN_COLOR], "info": ["status_info", INFO_COLOR]}
## Each tool's icon (the palette, its hint card, the EDITOR MENU's TOOL page).
const TOOL_ICONS := {"select": "tool_select", "road": "tool_road", "branch": "tool_branch", "terrain": "tool_terrain",
	"paint": "tool_paint", "objects": "tool_objects", "items": "tool_items", "hazards": "tool_hazards",
	"crowds": "tool_crowds", "world": "tool_world"}

static var _theme: Theme
static var _icons := {}
static var _styles := {}


## The editor's theme: UiKit's look, compact (15 px text, 30 px rows, small paddings).
static func theme() -> Theme:
	if _theme:
		return _theme
	var t: Theme = UiKit.theme().duplicate(true)
	var o := UiKit.ORANGE
	t.default_font_size = FONT
	# compact buttons
	t.set_stylebox("normal", "Button", UiKit.box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.16), 1, 3, 8))
	t.set_stylebox("hover", "Button", UiKit.box(Color(1, 1, 1, 0.12), o, 1, 3, 8))
	t.set_stylebox("pressed", "Button", UiKit.box(Color(o.r, o.g, o.b, 0.35), o, 1, 3, 8))
	t.set_stylebox("focus", "Button", UiKit.box(Color(0, 0, 0, 0), o, 2, 3, 8))
	t.set_stylebox("disabled", "Button", UiKit.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 1, 3, 8))
	t.set_font_size("font_size", "Button", FONT)
	# the line icons are white: these colours tint them like the text beside them
	t.set_constant("h_separation", "Button", 6)
	_icon_colors(t, "Button", UiKit.TEXT, Color.WHITE, Color.WHITE, Color.BLACK)
	# a toggle / segment: on = solid orange (the active tool, GRID, the picked mode)
	t.set_type_variation("EdToggle", "Button")
	t.set_stylebox("normal", "EdToggle", UiKit.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 1, 3, 8))
	t.set_stylebox("hover", "EdToggle", UiKit.box(Color(1, 1, 1, 0.12), o, 1, 3, 8))
	t.set_stylebox("pressed", "EdToggle", UiKit.box(o, o, 1, 3, 8))
	t.set_stylebox("hover_pressed", "EdToggle", UiKit.box(o.lightened(0.15), Color.WHITE, 1, 3, 8))
	t.set_stylebox("focus", "EdToggle", UiKit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 3, 8))
	t.set_color("font_pressed_color", "EdToggle", Color.BLACK)
	t.set_color("font_hover_pressed_color", "EdToggle", Color.BLACK)
	_icon_colors(t, "EdToggle", UiKit.TEXT, Color.WHITE, Color.BLACK, Color.BLACK)
	# flat buttons (the track name, the top bar's icons, the drawer's rows)
	t.set_type_variation("EdFlat", "Button")
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 6
	empty.content_margin_right = 6
	t.set_stylebox("normal", "EdFlat", empty)
	t.set_stylebox("pressed", "EdFlat", empty)
	t.set_stylebox("disabled", "EdFlat", empty)
	t.set_stylebox("focus", "EdFlat", UiKit.box(Color(0, 0, 0, 0), o, 1, 3, 6))
	t.set_stylebox("hover", "EdFlat", UiKit.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_stylebox("hover_pressed", "EdFlat", UiKit.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_color("font_hover_color", "EdFlat", o)
	_icon_colors(t, "EdFlat", UiKit.TEXT, o, o, o)
	# the one orange filled button of the bar (TEST DRIVE)
	t.set_type_variation("EdAccent", "Button")
	t.set_stylebox("normal", "EdAccent", UiKit.box(o, o, 1, 3, 10))
	t.set_stylebox("hover", "EdAccent", UiKit.box(o.lightened(0.15), Color.WHITE, 1, 3, 10))
	t.set_stylebox("pressed", "EdAccent", UiKit.box(UiKit.PRESSED, Color.WHITE, 1, 3, 10))
	t.set_stylebox("focus", "EdAccent", UiKit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 3, 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "EdAccent", Color.BLACK)
	_icon_colors(t, "EdAccent", Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK)
	# hover tooltips: the editor's dark card, readable text
	t.set_stylebox("panel", "TooltipPanel", UiKit.box(Color(0.06, 0.06, 0.06, 0.97), Color(1, 1, 1, 0.22), 1, 3, 8))
	t.set_font("font", "TooltipLabel", UiKit.font(false))
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("font_color", "TooltipLabel", UiKit.TEXT)
	t.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "TooltipLabel", 2)
	# menus of the top bar
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(st, "MenuButton", t.get_stylebox(st, "EdFlat"))
	t.set_stylebox("hover", "MenuButton", UiKit.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 3, 8))
	t.set_stylebox("pressed", "MenuButton", UiKit.box(Color(o.r, o.g, o.b, 0.35), Color(0, 0, 0, 0), 0, 3, 8))
	t.set_font("font", "MenuButton", UiKit.font(true))
	t.set_font_size("font_size", "MenuButton", FONT)
	t.set_color("font_color", "MenuButton", UiKit.TEXT)
	t.set_color("font_hover_color", "MenuButton", Color.WHITE)
	t.set_color("font_pressed_color", "MenuButton", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", FONT)
	t.set_font_size("font_accelerator_size", "PopupMenu", FONT_SMALL)
	t.set_color("font_accelerator_color", "PopupMenu", UiKit.TEXT_DIM)
	t.set_color("font_disabled_color", "PopupMenu", Color(1, 1, 1, 0.3))
	t.set_color("font_separator_color", "PopupMenu", UiKit.TEXT_DIM)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("h_separation", "PopupMenu", 10)
	t.set_stylebox("panel", "PopupPanel", UiKit.box(Color(0.1, 0.1, 0.1, 1.0), Color(1, 1, 1, 0.18), 1, 3, 10))
	# dropdowns, toggles, text
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(st, "OptionButton", t.get_stylebox(st, "Button"))
	t.set_font_size("font_size", "OptionButton", FONT)
	t.set_font_size("font_size", "CheckButton", FONT)
	t.set_font_size("font_size", "Label", FONT)
	var le := UiKit.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.18), 1, 3, 6)
	var le_f := UiKit.box(Color(0, 0, 0, 0.55), o, 1, 3, 6)
	var le_r := UiKit.box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.08), 1, 3, 6)
	for k in [["normal", le], ["focus", le_f], ["read_only", le_r]]:
		t.set_stylebox(k[0], "LineEdit", k[1])
		t.set_stylebox(k[0], "TextEdit", k[1])
	t.set_font_size("font_size", "LineEdit", FONT)
	t.set_font_size("font_size", "TextEdit", FONT)
	t.set_color("font_color", "TextEdit", Color.WHITE)
	t.set_color("caret_color", "TextEdit", o)
	t.set_color("selection_color", "TextEdit", Color(o.r, o.g, o.b, 0.4))
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))
	# number fields: drag sideways to change, the value right-aligned
	t.set_type_variation("EdNumber", "LineEdit")
	t.set_stylebox("normal", "EdNumber", UiKit.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.14), 1, 3, 6))
	t.set_stylebox("focus", "EdNumber", le_f)
	t.set_color("font_color", "EdNumber", Color.WHITE)
	# lists
	t.set_stylebox("panel", "ItemList", UiKit.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 1, 2, 4))
	t.set_stylebox("focus", "ItemList", UiKit.box(Color(0, 0, 0, 0), o, 1, 2, 4))
	t.set_stylebox("selected", "ItemList", UiKit.box(Color(o.r, o.g, o.b, 0.55), Color(0, 0, 0, 0), 0, 0, 2))
	t.set_stylebox("selected_focus", "ItemList", UiKit.box(Color(o.r, o.g, o.b, 0.7), Color(0, 0, 0, 0), 0, 0, 2))
	t.set_stylebox("hovered", "ItemList", UiKit.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 0, 2))
	t.set_color("font_color", "ItemList", UiKit.TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_font_size("font_size", "ItemList", FONT_SMALL)
	t.set_font_size("font_size", "Tree", FONT_SMALL)
	t.set_constant("v_separation", "Tree", 3)
	t.set_constant("item_margin", "Tree", 12)
	t.set_font_size("title_button_font_size", "Tree", FONT_SMALL)
	# scroll bars: 8 px (UiKit's have no width), a grey grabber, orange under the mouse
	for bar in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", bar, _bar(Color(1, 1, 1, 0.06)))
		t.set_stylebox("scroll_focus", bar, _bar(Color(1, 1, 1, 0.06)))
		t.set_stylebox("grabber", bar, _bar(Color(1, 1, 1, 0.35)))
		t.set_stylebox("grabber_highlight", bar, _bar(o))
		t.set_stylebox("grabber_pressed", bar, _bar(o))
	# panels: FRAME_BG, thin padding (the editor's columns)
	t.set_stylebox("panel", "PanelContainer", UiKit.box(UiKit.FRAME_BG, Color(1, 1, 1, 0.1), 1, 0, 6))
	t.set_type_variation("EdCard", "PanelContainer")
	t.set_stylebox("panel", "EdCard", UiKit.box(Color(0.06, 0.06, 0.06, 0.94), Color(o.r, o.g, o.b, 0.8), 1, 4, 16))
	t.set_stylebox("panel", "ColorPicker", StyleBoxEmpty.new())
	t.set_constant("separation", "HSeparator", 6)
	t.set_constant("separation", "VSeparator", 10)
	# sliders: a thinner grabber row
	t.set_constant("center_grabber", "HSlider", 0)
	_theme = t
	return t


## Expands {ed_*} combos into modifier keycaps + "+" + the key (S25): "{ed_undo}" becomes
## "{ed_mod_ctrl}+{ed_key_ed_undo}" (Ctrl before Shift before Alt). Mouse-button actions become
## words ("RIGHT MOUSE"). Other tokens and plain text stay as they are.
static func prompt(text: String) -> String:
	if text.find("{ed_") < 0:
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var open := text.find("{", i)
		var close := text.find("}", open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			out += text.substr(i)
			break
		out += text.substr(i, open - i)
		var act := text.substr(open + 1, close - open - 1)
		out += _expand(act) if act.begins_with("ed_") else text.substr(open, close - open + 1)
		i = close + 1
	return out


static func _expand(act: String) -> String:
	var key := EditorInput.base_key(act)
	if key != "":
		var parts := PackedStringArray()
		for m in EditorInput.mods_of(act):
			parts.append("{%s}" % m)
		parts.append("{%s}" % key)
		return "+".join(parts)
	if InputMap.has_action(act):
		for ev in InputMap.action_get_events(act):
			if ev is InputEventMouseButton:
				return str(MOUSE_WORDS.get((ev as InputEventMouseButton).button_index, "MOUSE"))
			if ev is InputEventKey:
				break
	return "{%s}" % act


## The same text with every {action} written as its key's name ("CTRL+Z"): tooltips, menus.
static func plain(text: String) -> String:
	var out := ""
	for seg in InputPrompts.parse_prompt(prompt(text)):
		if seg is String:
			out += seg
		else:
			var t := InputPrompts.action_text(str(seg.action), "keyboard")
			out += t if t != "" else str(seg.action)
	return out


## The editor's Button stylebox of a state with 6 px sides (the action grid's narrow cells), cached.
static func _compact(state: String) -> StyleBox:
	if not _styles.has(state):
		var sb := theme().get_stylebox(state, "Button").duplicate() as StyleBox
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		_styles[state] = sb
	return _styles[state]


## A button type's icon tints: idle, under the mouse, pressed (or on), pressed under the mouse.
static func _icon_colors(t: Theme, type: String, idle: Color, hover: Color, pressed: Color, hover_pressed: Color) -> void:
	t.set_color("icon_normal_color", type, idle)
	t.set_color("icon_focus_color", type, idle)
	t.set_color("icon_hover_color", type, hover)
	t.set_color("icon_pressed_color", type, pressed)
	t.set_color("icon_hover_pressed_color", type, hover_pressed)
	t.set_color("icon_disabled_color", type, Color(idle, idle.a * 0.35))


## A scroll bar part: BAR_W across (4 px margins on every side).
static func _bar(c: Color) -> StyleBoxFlat:
	var sb := UiKit.box(c, Color(0, 0, 0, 0), 0, 3, 0)
	sb.set_content_margin_all(BAR_W * 0.5)
	return sb


static func section(text: String) -> Label:
	var l := UiKit.label(text, FONT_SMALL, UiKit.ORANGE, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## section() after an orange icon (icon()'s names): the tool options' and the inspector's headings
## that name a kind (WATER, a hazard group, BOOST PAD...).
static func section_icon(text: String, icon_name: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon_rect(icon_name, 16, UiKit.ORANGE))
	h.add_child(section(text))
	return h


## A TextureRect of icon(), centred in a px square (labels, rows).
static func icon_rect(icon_name: String, px := 16, color := Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name, px, color)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## [label ....... control]; the label is clipped to its column (its whole text in its tooltip),
## the tip in the tooltip of both.
static func row(label: String, c: Control, tip := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiKit.label(label, FONT_SMALL, UiKit.TEXT)
	l.custom_minimum_size = Vector2(LABEL_W, ROW_H - 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = label if tip == "" else ("%s\n%s" % [label, tip] if label != "" else tip)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	if c != null:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if tip != "" and c.tooltip_text == "":
			c.tooltip_text = tip
		h.add_child(c)
	return h


static func number(value: float, min_v: float, max_v: float, step: float, on_change: Callable, fmt := "%.1f", suffix := "") -> EditorNumber:
	var n := EditorNumber.new()
	n.min_value = min_v
	n.max_value = max_v
	n.step = step
	n.fmt = fmt
	n.suffix = suffix
	n.set_value(value, false)
	if on_change.is_valid():
		var last := []
		n.changed.connect(func(v: float, final: bool) -> void: _call2(on_change, v, final, last))
	return n


## Three number fields X Y Z; on_change(Vector3[, final]).
static func vec3(value: Vector3, on_change: Callable, step := 0.1) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var fields: Array[EditorNumber] = []
	for i in 3:
		var n := EditorNumber.new()
		n.min_value = -100000.0
		n.max_value = 100000.0
		n.step = step
		n.fmt = "%.2f" if step < 0.1 else "%.1f"
		n.prefix = ["X ", "Y ", "Z "][i]
		n.set_value(value[i], false)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.custom_minimum_size.x = 60
		fields.append(n)
		h.add_child(n)
	var last := []
	for i in 3:
		fields[i].changed.connect(func(_v: float, final: bool) -> void:
			if on_change.is_valid():
				_call2(on_change, Vector3(fields[0].value, fields[1].value, fields[2].value), final, last))
	return h


## A colour swatch; a click opens a ColorPicker in a popup; on_change(Color[, final]).
static func color(value: Color, on_change: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, ROW_H - 4)
	b.focus_mode = Control.FOCUS_ALL
	var sw := UiKit.box(value, Color(1, 1, 1, 0.3), 1, 3, 4)
	b.add_theme_stylebox_override("normal", sw)
	b.add_theme_stylebox_override("hover", UiKit.box(value, UiKit.ORANGE, 2, 3, 4))
	b.add_theme_stylebox_override("pressed", UiKit.box(value, UiKit.ORANGE, 2, 3, 4))
	b.tooltip_text = "#" + value.to_html(false).to_upper()
	b.set_meta("color", value)
	b.pressed.connect(func() -> void:
		var pop := PopupPanel.new()
		var cp := ColorPicker.new()
		cp.color = b.get_meta("color", value)
		cp.edit_alpha = false
		cp.presets_visible = false
		cp.sampler_visible = false
		cp.color_modes_visible = false
		pop.add_child(cp)
		b.add_child(pop)
		var last := []
		cp.color_changed.connect(func(c: Color) -> void:
			_paint_swatch(b, c)
			if on_change.is_valid():
				_call2(on_change, c, false, last))
		pop.popup_hide.connect(func() -> void:
			if on_change.is_valid() and _argc(on_change) >= 2:
				on_change.call(b.get_meta("color", value), true)
			pop.queue_free())
		pop.popup(Rect2i(Vector2i(b.get_screen_position() + Vector2(0, b.size.y)), Vector2i(300, 380))))
	return b


static func _paint_swatch(b: Button, c: Color) -> void:
	b.set_meta("color", c)
	b.tooltip_text = "#" + c.to_html(false).to_upper()
	(b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = c
	(b.get_theme_stylebox("hover") as StyleBoxFlat).bg_color = c
	(b.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color = c


static func check(on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.custom_minimum_size.y = ROW_H - 4
	if on_change.is_valid():
		c.toggled.connect(func(v: bool) -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			on_change.call(v))
	return c


## A dropdown; on_change(index).
static func choice(items: Array, selected: int, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	o.fit_to_longest_item = false
	o.clip_text = true
	o.custom_minimum_size = Vector2(80, ROW_H - 4)
	if on_change.is_valid():
		o.item_selected.connect(func(i: int) -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			on_change.call(i))
	return o


## A slider with its value beside it; on_change(value[, final]) (final at the drag's end).
static func slider(min_v: float, max_v: float, step: float, value: float, on_change: Callable, fmt := "%d") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(90, 20)
	h.add_child(s)
	var v := UiKit.label(fmt % value, FONT_SMALL, Color.WHITE, true)
	v.custom_minimum_size.x = 46
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	var dragging := [false]
	var last := []
	s.drag_started.connect(func() -> void: dragging[0] = true)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		if on_change.is_valid():
			_call2(on_change, x, not dragging[0], last))
	s.drag_ended.connect(func(changed: bool) -> void:
		dragging[0] = false
		if changed and on_change.is_valid():
			_call2(on_change, s.value, true, last))
	return h


## A button; with an icon (icon()'s names) it stands before the text. The tip's {ed_*} combos are
## written as their keys.
static func button(text: String, cb: Callable, tip := "", icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = plain(tip)
	b.custom_minimum_size.y = ROW_H - 2
	b.clip_text = false
	if icon_name != "":
		# the text follows its icon (a wide button would leave the icon alone at the edge)
		b.icon = icon(icon_name, ICON)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -8.0)
			cb.call())
	return b


## A toggle button (orange when on); cb(on). With an icon it stands before the text.
static func toggle(text: String, on: bool, cb: Callable, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.theme_type_variation = "EdToggle"
	b.custom_minimum_size.y = ROW_H - 2
	if icon_name != "":
		b.icon = icon(icon_name, ICON)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if cb.is_valid():
		b.toggled.connect(func(v: bool) -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			cb.call(v))
	return b


## A square button with only an icon (the top bar's UNDO, SAVE, HELP...): the tip names what it
## does and its key ({ed_*} combos written as their keys). EdFlat; toggle_mode for an on / off one.
static func icon_button(icon_name: String, cb: Callable, tip: String, px := ICON_BAR) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name, px)
	b.theme_type_variation = "EdFlat"
	b.tooltip_text = plain(tip)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(px + 10, ROW_H)
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -8.0)
			cb.call())
	return b


## Action buttons in a grid of `cols` columns, icon and a short name each (the tool options'
## OPEN LOOP, REVERSE...): entries [text, icon, callback, tip]. The tip says it in full with its
## key; a name too long for its cell trims with "..." (the tip has it whole).
static func actions(entries: Array, cols := 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	for e in entries:
		var b := button(str(e[0]), e[2] if e.size() > 2 else Callable(), str(e[3]) if e.size() > 3 else "", str(e[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", FONT_SMALL)
		b.add_theme_constant_override("h_separation", 5)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, _compact(st))
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size.x = 60
		if not b.tooltip_text.begins_with(b.text):
			b.tooltip_text = b.text + ("\n" + b.tooltip_text if b.tooltip_text != "" else "")
		g.add_child(b)
	return g


## A text field; on_change(text[, final]): live with final false, once more with final true when
## the typing ends (Enter, or the field lets go of the focus). One-argument callbacks get the end only.
static func text(value: String, on_change: Callable, max_len := 48) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.max_length = max_len
	e.custom_minimum_size = Vector2(80, ROW_H - 4)
	e.set_meta("last", value)
	if on_change.is_valid():
		var two := _argc(on_change) >= 2
		if two:
			e.text_changed.connect(func(t: String) -> void: on_change.call(t, false))
		var done := func(_t := "") -> void:
			if e.text == str(e.get_meta("last", "")) and not two:
				return
			e.set_meta("last", e.text)
			_call2(on_change, e.text, true)
		e.text_submitted.connect(func(t: String) -> void:
			done.call(t)
			e.release_focus())
		e.focus_exited.connect(done)
	return e


## A list; on_pick(index) when a row is picked.
static func list(items: Array, on_pick: Callable) -> ItemList:
	var l := ItemList.new()
	for it in items:
		l.add_item(str(it))
	l.custom_minimum_size = Vector2(80, ROW_H * 4)
	l.auto_height = false
	if on_pick.is_valid():
		l.item_selected.connect(func(i: int) -> void: on_pick.call(i))
	return l


## PromptLabel of prompt(text), dim and wrapped to the column.
static func hint(text: String) -> PromptLabel:
	var l := PromptLabel.new(prompt(text), FONT_SMALL, UiKit.TEXT_DIM)
	l.add_theme_font_override("normal_font", UiKit.font(false))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 60
	return l


## One of N as joined toggle buttons; on_select(index). Names that do not fit one line wrap to
## more lines (never cut); each button's tooltip has its name (or tips[i], {ed_*} written as keys).
## With icons (icon()'s names) each button has its icon before the name; an empty name makes an
## icon-only button (its tip says what it is).
static func modes(items: Array, selected: int, on_select: Callable, icons: Array = [], tips: Array = []) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 2)
	h.add_theme_constant_override("v_separation", 2)
	var group := ButtonGroup.new()
	for i in items.size():
		var b := Button.new()
		b.text = str(items[i])
		b.tooltip_text = plain(str(tips[i])) if i < tips.size() and str(tips[i]) != "" else str(items[i])
		if i < icons.size() and str(icons[i]) != "":
			b.icon = icon(str(icons[i]), ICON)
			if b.text == "":
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			elif items.size() == 1:
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "EdToggle"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = ROW_H - 2
		var idx := i
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			if on_select.is_valid():
				on_select.call(idx))
		h.add_child(b)
	return h


## One of N as tiles, the icon above the name (the brushes, OBJECTS' and ITEMS' kinds): one row,
## the tiles share its width; a name wraps to a second line rather than being cut. on_select(index);
## tips[i] is the tile's tooltip under its name ({ed_*} written as keys).
static func tiles(items: Array, selected: int, on_select: Callable, icons: Array, tips: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in items.size():
		var b := Tile.new(str(items[i]), str(icons[i]) if i < icons.size() else "")
		var tip := plain(str(tips[i])) if i < tips.size() else ""
		b.tooltip_text = str(items[i]) + ("\n" + tip if tip != "" else "")
		b.button_group = group
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			if on_select.is_valid():
				on_select.call(idx))
		h.add_child(b)
	return h


# ---------------------------------------------------------------- additions (P10)

## A compact keycap chip (the palette's "[2]").
static func keycap(text: String) -> Texture2D:
	return KeycapTexture.of(text, 20.0)


## An editor icon `px` high, cached, crisp at any scale (DPITexture): a line icon of ICON_DIR by its
## file name in `color` (white by default: a Button's icon_*_color theme colours tint it), or a
## status disc ("tick" / "ok", "error", "warning", "info") in its level's colour. null when there is
## no such file.
static func icon(icon_name: String, px := 16, color := Color.WHITE) -> Texture2D:
	var file := icon_name
	var col := color
	if STATUS.has(icon_name):
		file = str(STATUS[icon_name][0])
		if color == Color.WHITE:
			col = STATUS[icon_name][1]
	var hex := col.to_html(false)
	var key := "%s@%d#%s" % [file, px, hex]
	if _icons.has(key):
		return _icons[key]
	var tex: Texture2D = null
	var path := ICON_DIR + file + ".svg"
	if file != "" and FileAccess.file_exists(path):
		var src := FileAccess.get_file_as_string(path).replace("currentColor", "#" + hex)
		tex = DPITexture.create_from_string(src, maxf(px, 4.0) / 24.0)
	elif file != "":
		push_warning("EditorKit.icon: no icon %s" % path)
	_icons[key] = tex
	return tex


## A tool's icon (TOOL_ICONS).
static func tool_icon(tool_id: String, px := ICON, color := Color.WHITE) -> Texture2D:
	return icon(str(TOOL_ICONS.get(tool_id, "")), px, color)


## How many arguments a callable takes (bound arguments taken off).
static func _argc(cb: Callable) -> int:
	if not cb.is_valid():
		return 0
	return maxi(cb.get_argument_count() - cb.get_bound_arguments_count(), 0)


## cb(v, final) or cb(v), by what it takes. A one-argument callback gets every change once: the
## final call of a drag that ends on the value it last sent is left out (`last` holds that value).
static func _call2(cb: Callable, v: Variant, final: bool, last: Array = []) -> void:
	if not cb.is_valid():
		return
	if _argc(cb) >= 2:
		cb.call(v, final)
		return
	if final and not last.is_empty() and last[0] == v:
		last.clear()
		return
	if final:
		last.clear()
	elif last.is_empty():
		last.append(v)
	else:
		last[0] = v
	cb.call(v)


## tiles()' button: a toggle with its icon above its name (wrapped to two lines when the tile is
## narrow), drawn in the EdToggle colours of its state. The name is `label` (text stays empty, so
## the Button sizes by custom_minimum_size).
class Tile:
	extends Button
	const ICON_PX := 22
	const FONT_PX := 12
	const PAD := 5.0
	const GAP := 3.0
	var label := ""
	var icon_name := ""
	var _lines := PackedStringArray()

	func _init(text_: String, icon_: String) -> void:
		label = text_
		icon_name = icon_
		theme_type_variation = "EdToggle"
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		clip_contents = true
		resized.connect(_fit)

	func _ready() -> void:
		_fit()

	func _font() -> Font:
		return UiKit.font(true)

	## The name's lines at this width (word wrap), and the minimum size that holds them.
	func _fit() -> void:
		var f := _font()
		var words := label.split(" ", false)
		var widest := 0.0
		for w in words:
			widest = maxf(widest, f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x)
		var room := maxf(size.x - PAD * 2.0, widest)
		var lines := PackedStringArray()
		var cur := ""
		for w in words:
			var t := w if cur == "" else cur + " " + w
			if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x > room:
				lines.append(cur)
				cur = w
			else:
				cur = t
		if cur != "":
			lines.append(cur)
		_lines = lines
		var line_h := f.get_height(FONT_PX)
		var want := Vector2(ceilf(maxf(widest, ICON_PX) + PAD * 2.0), ceilf(PAD * 2.0 + ICON_PX + GAP + line_h * maxi(lines.size(), 1)))
		if not custom_minimum_size.is_equal_approx(want):
			custom_minimum_size = want
		queue_redraw()

	func _draw() -> void:
		var mode := {DRAW_NORMAL: "normal", DRAW_PRESSED: "pressed", DRAW_HOVER: "hover", DRAW_DISABLED: "disabled",
			DRAW_HOVER_PRESSED: "hover_pressed"}.get(get_draw_mode(), "normal") as String
		var fc := get_theme_color("font_color" if mode == "normal" else "font_%s_color" % mode)
		var ic := get_theme_color("icon_%s_color" % mode)
		var f := _font()
		var line_h := f.get_height(FONT_PX)
		var block := ICON_PX + GAP + line_h * _lines.size()
		var y := floorf((size.y - block) * 0.5)
		var tex := EditorKit.icon(icon_name, ICON_PX)
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(floorf((size.x - ICON_PX) * 0.5), y), Vector2(ICON_PX, ICON_PX)), false, ic)
		y += ICON_PX + GAP
		for l in _lines:
			draw_string(f, Vector2(PAD, y + f.get_ascent(FONT_PX)), l, HORIZONTAL_ALIGNMENT_CENTER, size.x - PAD * 2.0, FONT_PX, fc)
			y += line_h
