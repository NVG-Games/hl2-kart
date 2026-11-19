class_name EditorKit
## Compact editor widgets and the editor theme (a copy of UiKit.theme() plus number fields,
## ItemList, PopupPanel, ColorPicker, HScrollBar, TextEdit, MenuButton / PopupMenu styles);
## prompt() expands combos into modifier keycaps (C1 S25). P10.
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
const OK_COLOR := Color(0.45, 0.85, 0.35)
const WARN_COLOR := Color(1.0, 0.82, 0.2)
const ERROR_COLOR := Color(1.0, 0.32, 0.25)
const INFO_COLOR := Color(0.45, 0.7, 1.0)
## Mouse buttons in prompts are words (no mouse icons ship).
const MOUSE_WORDS := {MOUSE_BUTTON_LEFT: "LEFT MOUSE", MOUSE_BUTTON_RIGHT: "RIGHT MOUSE",
	MOUSE_BUTTON_MIDDLE: "MIDDLE MOUSE", MOUSE_BUTTON_WHEEL_UP: "WHEEL", MOUSE_BUTTON_WHEEL_DOWN: "WHEEL"}

static var _theme: Theme
static var _icons := {}


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
	# a toggle / segment: on = solid orange (the active tool, GRID, the picked mode)
	t.set_type_variation("EdToggle", "Button")
	t.set_stylebox("normal", "EdToggle", UiKit.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 1, 3, 8))
	t.set_stylebox("hover", "EdToggle", UiKit.box(Color(1, 1, 1, 0.12), o, 1, 3, 8))
	t.set_stylebox("pressed", "EdToggle", UiKit.box(o, o, 1, 3, 8))
	t.set_stylebox("hover_pressed", "EdToggle", UiKit.box(o.lightened(0.15), Color.WHITE, 1, 3, 8))
	t.set_stylebox("focus", "EdToggle", UiKit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 3, 8))
	t.set_color("font_pressed_color", "EdToggle", Color.BLACK)
	t.set_color("font_hover_pressed_color", "EdToggle", Color.BLACK)
	t.set_color("icon_pressed_color", "EdToggle", Color.WHITE)
	# flat buttons (the track name, "?", the drawer's rows)
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
	# the one orange filled button of the bar (TEST DRIVE)
	t.set_type_variation("EdAccent", "Button")
	t.set_stylebox("normal", "EdAccent", UiKit.box(o, o, 1, 3, 10))
	t.set_stylebox("hover", "EdAccent", UiKit.box(o.lightened(0.15), Color.WHITE, 1, 3, 10))
	t.set_stylebox("pressed", "EdAccent", UiKit.box(UiKit.PRESSED, Color.WHITE, 1, 3, 10))
	t.set_stylebox("focus", "EdAccent", UiKit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 3, 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "EdAccent", Color.BLACK)
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
	# scroll bars
	var sbar := UiKit.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 0)
	t.set_stylebox("scroll", "HScrollBar", sbar)
	t.set_stylebox("grabber", "HScrollBar", UiKit.box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber_highlight", "HScrollBar", UiKit.box(o, Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber_pressed", "HScrollBar", UiKit.box(o, Color(0, 0, 0, 0), 0, 3, 0))
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


static func section(text: String) -> Label:
	var l := UiKit.label(text, FONT_SMALL, UiKit.ORANGE, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## [label ....... control]; the label is clipped to its column, the tooltip on both.
static func row(label: String, c: Control, tip := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiKit.label(label, FONT_SMALL, UiKit.TEXT)
	l.custom_minimum_size = Vector2(LABEL_W, ROW_H - 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.tooltip_text = tip
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


static func button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = plain(tip)
	b.custom_minimum_size.y = ROW_H - 2
	b.clip_text = false
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -8.0)
			cb.call())
	return b


## A toggle button (orange when on); cb(on).
static func toggle(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.theme_type_variation = "EdToggle"
	b.custom_minimum_size.y = ROW_H - 2
	if cb.is_valid():
		b.toggled.connect(func(v: bool) -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			cb.call(v))
	return b


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


## One of N as joined toggle buttons; on_select(index).
static func modes(items: Array, selected: int, on_select: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in items.size():
		var b := Button.new()
		b.text = str(items[i])
		b.theme_type_variation = "EdToggle"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = ROW_H - 2
		b.clip_text = true
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


## A small round icon: "tick" (raceable), "error", "warning", "info".
static func icon(kind: String, px := 16) -> Texture2D:
	var key := "%s_%d" % [kind, px]
	if _icons.has(key):
		return _icons[key]
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color = {"tick": OK_COLOR, "error": ERROR_COLOR, "warning": WARN_COLOR}.get(kind, INFO_COLOR)
	var r := px * 0.5
	for y in px:
		for x in px:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(Vector2(r, r))
			var a := clampf(r - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var c := col
			var u := p / px
			var mark := false
			if kind == "tick":
				mark = _seg(u, Vector2(0.26, 0.52), Vector2(0.43, 0.7)) < 0.075 or _seg(u, Vector2(0.43, 0.7), Vector2(0.75, 0.32)) < 0.075
			elif kind == "info":
				mark = _seg(u, Vector2(0.5, 0.45), Vector2(0.5, 0.75)) < 0.07 or u.distance_to(Vector2(0.5, 0.28)) < 0.08
			else:
				mark = _seg(u, Vector2(0.5, 0.22), Vector2(0.5, 0.56)) < 0.07 or u.distance_to(Vector2(0.5, 0.74)) < 0.08
			if mark:
				c = Color(0.05, 0.05, 0.05)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


static func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var k := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * k)


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
