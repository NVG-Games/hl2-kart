class_name KeysPage
extends BindingsPage
## OPTIONS > KEYBOARD & MOUSE. Left: every action's three keyboard and mouse slots as icons, each
## row numbered. Press a slot, then the new key or mouse button (BindingsPage: a key another action
## had swaps over, and the foot says what moved); X / Delete empties a slot; Esc's slot is locked.
## Right: LAYOUT (WASD, ARROWS, ONE HAND), RESET KEYS, and a drawn keyboard and mouse with the
## bound keys lit in orange, numbered as the table (KeyboardDiagram): the focused or hovered row's
## keys turn white, a listening slot's key pulses, and a click on a lit key changes it as its slot
## would. Works whatever is plugged in; the pad's own settings are on CONTROLLER (PadPage).

const SLOT := Vector2(80, 34)
const ICON_PX := 26.0
const LABEL_W := 150
const GAP := 6  # between slots
const BADGE := 22.0
const BADGE_BG := Color(0.075, 0.075, 0.075)  # as the drawn keyboard's badges
const HINT_TEXT := "Click a key on the picture or a slot in the table, then press the new key. The numbers match the table."

var table: VBoxContainer
var keyboard: KeyboardDiagram
var reset_button: Button
var _slots := {}  # "action|slot" -> Button
var _unplaced: HFlowContainer  # bound keys the picture has no key for (the numpad, F13 and up...)
var _hover := ""  # the action whose slot is under the mouse


func _init(owner_dialog: Dialog = null) -> void:
	super(owner_dialog, InputBindings.KEY)
	add_theme_constant_override("separation", 30)
	table = _table()
	add_child(table)
	add_child(_side())
	_rebuild()


# ---------------------------------------------------------------- the table
static func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A row's number (the badges on the drawn keyboard carry the same one).
static func _badge(n: int) -> Label:
	var l := UiKit.label(str(n), 12, Color.WHITE, true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BADGE_BG
	sb.set_corner_radius_all(int(BADGE * 0.5))
	sb.set_border_width_all(1)
	sb.border_color = Color(UiKit.ORANGE, 0.85)
	sb.anti_aliasing = true
	l.add_theme_stylebox_override("normal", sb)
	l.custom_minimum_size = Vector2(BADGE, BADGE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _table() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", GAP)
	var a := UiKit.section("ACTION")
	a.custom_minimum_size.x = BADGE + GAP + LABEL_W + GAP + 4
	head.add_child(a)
	head.add_child(UiKit.section("KEYBOARD & MOUSE"))
	v.add_child(head)
	for n in InputBindings.ACTIONS.size():
		var act: String = InputBindings.ACTIONS[n]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		row.add_child(_badge(n + 1))
		var l := UiKit.label(InputBindings.TITLES[act], 16, UiKit.TEXT)
		l.custom_minimum_size = Vector2(LABEL_W, SLOT.y)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		row.add_child(_gap(4))
		for i in InputBindings.slot_count(act, InputBindings.KEY):
			row.add_child(_slot(act, i))
		v.add_child(row)
	return v


func _slot_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	return UiKit.box(bg, border, bw, 3, 6)


func _slot(act: String, i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_ALL
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	# the theme's button margins are for text buttons: an icon slot is lower
	b.add_theme_stylebox_override("normal", _slot_style(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 1))
	b.add_theme_stylebox_override("hover", _slot_style(Color(1, 1, 1, 0.12), UiKit.ORANGE, 1))
	b.add_theme_stylebox_override("pressed", _slot_style(Color(UiKit.ORANGE, 0.35), UiKit.ORANGE, 1))
	b.add_theme_stylebox_override("focus", _slot_style(Color(0, 0, 0, 0), UiKit.ORANGE, 2))
	b.add_theme_stylebox_override("disabled", _slot_style(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.06), 1))
	b.set_meta("action", act)
	b.set_meta("slot", i)
	b.name = "slot_%s_%d" % [act, i]
	b.pressed.connect(press_slot.bind(act, i))
	b.gui_input.connect(_slot_input.bind(act, i))
	b.focus_entered.connect(func():
		Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -10.0)
		_update_highlight.call_deferred())
	b.focus_exited.connect(func(): _update_highlight.call_deferred())
	b.mouse_entered.connect(func():
		_hover = act
		_update_highlight())
	b.mouse_exited.connect(func():
		if _hover == act:
			_hover = ""
		_update_highlight())
	_slots[_key(act, i)] = b
	return b


## A keyboard / mouse slot's button (today's table): null for no such slot.
func slot_button(action: String, slot: int) -> Button:
	return _slots.get(_key(action, slot))


func _slot_node(action: String, slot: int) -> Control:
	return slot_button(action, slot)


func _refresh_slot(key: String) -> void:
	var p := key.split("|")
	var act := p[0]
	var i := int(p[1])
	var b: Button = _slots[key]
	b.modulate.a = 1.0
	if key == _listening:
		b.icon = null
		b.text = "PRESS..."
		b.tooltip_text = ""
		return
	var spec := InputBindings.get_slot(act, cls, i)
	var st := InputPrompts.KEYBOARD
	var tex := InputPrompts.spec_icon(spec, ICON_PX, st) if spec != "" else null
	b.icon = tex
	b.text = "" if tex else (InputPrompts.spec_text(spec, st) if spec != "" else "—")
	var locked := InputBindings.is_locked(act, cls, i)
	if locked:
		b.modulate.a = 0.6
	b.tooltip_text = ("%s (always pauses)" if locked else "%s: press to change") % InputPrompts.spec_text(spec, st) \
		if spec != "" else "Empty: press to bind"


## X / Delete / Backspace on a slot empties it (BindingsPage.clear).
func _slot_input(event: InputEvent, act: String, i: int) -> void:
	if InputPrompts.is_listening() or not event.is_action_pressed("ui_clear"):
		return
	get_viewport().set_input_as_handled()
	clear(act, i)


# ---------------------------------------------------------------- the right side
func _side() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var sec := UiKit.section("LAYOUT")
	sec.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sec)
	row.add_child(_layout_dropdown(240))
	_layout_note = UiKit.label("", 14, UiKit.TEXT_DIM)
	_layout_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layout_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_layout_note)
	reset_button = UiKit.button("RESET KEYS", 200)
	reset_button.pressed.connect(_ask_reset)
	row.add_child(reset_button)
	v.add_child(row)
	keyboard = KeyboardDiagram.new()
	keyboard.interactive = true
	keyboard.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	keyboard.key_clicked.connect(_on_key_clicked)
	v.add_child(keyboard)
	_unplaced = HFlowContainer.new()
	_unplaced.add_theme_constant_override("h_separation", 14)
	_unplaced.add_theme_constant_override("v_separation", 4)
	_unplaced.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unplaced.visible = false
	v.add_child(_unplaced)
	var hint := UiKit.label(HINT_TEXT, 14, UiKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	return v


## The keys bound but not drawn: "NOT ON THE PICTURE:  [KP 8] ACCELERATE  ...".
func _fill_unplaced() -> void:
	for c in _unplaced.get_children():
		_unplaced.remove_child(c)
		c.queue_free()
	var list := KeyboardDiagram.unplaced({})
	_unplaced.visible = not list.is_empty()
	if list.is_empty():
		return
	var head := UiKit.label("NOT ON THE PICTURE:", 15, UiKit.ORANGE, true)
	head.custom_minimum_size.y = 26
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unplaced.add_child(head)
	for e in list:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := InputGlyph.new("", 26.0)
		g.style = InputPrompts.KEYBOARD
		g.spec = str(e[2])
		h.add_child(g)
		var l := UiKit.label(_title(str(e[0])), 15, UiKit.TEXT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
		_unplaced.add_child(h)


## A lit key on the picture clicked: its slot takes the focus and listens, as if it was pressed.
func _on_key_clicked(spec: String) -> void:
	if InputPrompts.is_listening():
		return
	var hit := InputBindings.find(spec)
	if hit.is_empty():
		return
	var b := slot_button(hit[0], hit[1])
	if b:
		b.grab_focus()
	press_slot(hit[0], hit[1])


## The picture lights the action whose slot is hovered (else focused) white, the others dimmer.
func _update_highlight() -> void:
	if keyboard == null or not is_inside_tree():
		return
	var act := _hover
	if act == "":
		var f := get_viewport().gui_get_focus_owner()
		if f and f.has_meta("action") and is_ancestor_of(f):
			act = str(f.get_meta("action"))
	keyboard.highlight_action = act


# ---------------------------------------------------------------- BindingsPage
func _rebuild() -> void:
	if table == null:
		return
	for key in _slots:
		_refresh_slot(key)
	_fill_unplaced()
	super()
	aim_tabs()


func _listen_started(action: String, slot: int) -> void:
	_refresh_slot(_key(action, slot))
	keyboard.pulse_spec = InputBindings.get_slot(action, cls, slot)


func _listen_ended(_action: String, _slot: int) -> void:
	keyboard.pulse_spec = ""


## Down from the tab bar: Accelerate's first key.
func aim_tabs() -> void:
	if dialog == null or dialog.tabs == null or not is_inside_tree() or not dialog.tabs.is_inside_tree() \
			or not is_visible_in_tree():
		return
	dialog.tabs.focus_neighbor_bottom = dialog.tabs.get_path_to(slot_button("accelerate", 0))
	_wire()


## The D-pad's ways out of the table: right of a row's last slot the LAYOUT dropdown, then RESET
## KEYS; up from those the tab bar. (Again each time the page shows: the dialog moves its tab bar
## into a row with the LB / RB icons once it is ready, which breaks paths made before.)
func _wire() -> void:
	if not is_inside_tree() or dialog == null or dialog.tabs == null or not dialog.tabs.is_inside_tree():
		return
	var last := InputBindings.KEY_SLOTS - 1
	for act in InputBindings.ACTIONS:
		var b := slot_button(act, last)
		if b:
			b.focus_neighbor_right = b.get_path_to(layout_dd)
	layout_dd.focus_neighbor_left = layout_dd.get_path_to(slot_button("accelerate", last))
	layout_dd.focus_neighbor_right = layout_dd.get_path_to(reset_button)
	layout_dd.focus_neighbor_top = layout_dd.get_path_to(dialog.tabs)
	reset_button.focus_neighbor_left = reset_button.get_path_to(layout_dd)
	reset_button.focus_neighbor_right = reset_button.get_path_to(reset_button)
	reset_button.focus_neighbor_top = reset_button.get_path_to(dialog.tabs)


func _ask_reset() -> void:
	_ask("RESET KEYS", "Put every key and mouse button back the way they came?", "RESET", reset_keys)


func reset_keys() -> void:
	if _listening != "":
		InputPrompts.cancel_listen()
	InputBindings.apply_preset(cls, "wasd")
	_rebuild()
	_say("The keys are back the way they came.", "", HINT)
