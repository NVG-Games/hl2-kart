class_name PadPage
extends BindingsPage
## OPTIONS > CONTROLLER. A big picture of a pad (ControllerDiagram) with every bound button's
## action written beside it on a leader line: press a label (A / Enter / a click, or a click on the
## button itself), then the new button, stick or trigger (BindingsPage: a button another action had
## swaps over, both labels flash, the foot says what moved); X / Delete empties it. Under the
## picture: the bindings it has no place for (paddles, the touchpad) and an ADD chip for every
## action with a free pad slot. Beside it: LAYOUT (STANDARD, TRIGGERS, CLASSIC KART, LEFT-HANDED),
## CONTROLLER PICTURE, BUTTON PROMPTS, vibration (each change buzzes the pad), the stick's dead
## zone, the Nintendo confirm swap, the pad connected and RESET CONTROLLER. Works whatever is
## plugged in.
##
## Two dropdowns name a pad family. CONTROLLER PICTURE is which pad this tab draws, and the
## labels' icons follow it; it is not saved, and its AUTO is InputPrompts.pad_style(): the BUTTON
## PROMPTS choice, else the pad in use or connected, else an Xbox pad. So picking a picture
## previews another family without changing the one detected. BUTTON PROMPTS is the saved
## setting: the icons in every menu and on the HUD (and AUTO there is the detected pad).

const SIDE_W := 300
const CHIP_H := 36.0  # an ADD chip and a NOT ON THE PICTURE row
# Game.settings' defaults for the settings on this page (RESET CONTROLLER)
const DEFAULT_VIBRATION := 0.7
const DEFAULT_DEADZONE := 0.2

var diagram: ControllerDiagram
## Under the picture, two groups on their own lines: NOT ON THE PICTURE and its rows, then ADD and
## its chips (in a scroll box that takes the rest of the page and follows the focus: a crowded set
## never pushes the dialog's foot down).
var extras: VBoxContainer
var extras_box: ScrollContainer
var _off_flow: HFlowContainer  # NOT ON THE PICTURE and its rows
var _add_flow: HFlowContainer  # ADD and its chips
var picture_dd: OptionButton
var style_dd: OptionButton  # BUTTON PROMPTS
var vib: HBoxContainer  # UiKit.slider
var dz: HBoxContainer
var swap: CheckButton
var pad_info: Label
var reset_button: Button
var _side: VBoxContainer
var _extra_head: Label  # NOT ON THE PICTURE
var _add_head: Label  # ADD
var _extra_rows := {}  # "action|slot" -> ControllerDiagram.Row: bound, but no place on the picture
var _chips := {}  # action -> Button: ADD, for an action with a free pad slot
var _listen_on: Control  # the chip or extra row listening (the diagram's rows pulse by themselves)
var _wire_queued := false


func _init(owner_dialog: Dialog = null) -> void:
	super(owner_dialog, InputBindings.PAD)
	add_theme_constant_override("separation", 24)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	diagram = ControllerDiagram.new()
	diagram.interactive = true
	diagram.slot_pressed.connect(press_slot)
	diagram.clear_requested.connect(clear)
	diagram.laid_out.connect(_queue_wire)
	left.add_child(diagram)
	extras_box = ScrollContainer.new()
	extras_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	extras_box.follow_focus = true
	extras_box.focus_mode = Control.FOCUS_NONE  # (its chips and rows are the D-pad's stops, not the box)
	extras_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(extras_box)
	extras = VBoxContainer.new()
	extras.add_theme_constant_override("separation", 6)
	extras.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_off_flow = _flow()
	_add_flow = _flow()
	extras.add_child(_off_flow)
	extras.add_child(_add_flow)
	_extra_head = _head("NOT ON THE PICTURE")
	_add_head = _head("ADD")
	extras_box.add_child(extras)
	add_child(left)
	_side = _settings()
	_side.sort_children.connect(_queue_wire)
	add_child(_side)
	_rebuild()


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.sort_children.connect(_queue_wire)
	return f


static func _head(text: String) -> Label:
	var l := UiKit.section(text)
	l.custom_minimum_size.y = CHIP_H
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## The pad family's name for people (XBOX, PLAYSTATION...), GAMEPAD for an unknown pad.
static func pad_title(style_id: String) -> String:
	var fam := InputPrompts.family(style_id)
	return "GAMEPAD" if fam == "generic" else str(InputPrompts.STYLE_TITLES.get(fam, "GAMEPAD"))


## The ADD chip of an action: null when it has no free pad slot.
func chip_for(action: String) -> Button:
	return _chips.get(action)


## The NOT ON THE PICTURE row of a slot: null when there is none.
func extra_row(action: String, slot: int) -> Button:
	return _extra_rows.get(_key(action, slot))


# ---------------------------------------------------------------- under the picture
static func _first_empty(action: String) -> int:
	var s := InputBindings.slots(action, InputBindings.PAD)
	return s.find("")


## Rows for the bindings the picture has no place for, then a chip per action with a free slot;
## the nodes are kept while they stay (so is the focus).
func _rebuild_extras() -> void:
	var st := _page_style()
	var offs: Array[Control] = []  # NOT ON THE PICTURE, then its rows
	var rows_now := {}
	var off := diagram.unplaced()
	offs.append(_extra_head)
	for e in off:
		var key := _key(str(e[0]), int(e[1]))
		var r: ControllerDiagram.Row = _extra_rows.get(key)
		if r == null:
			r = ControllerDiagram.make_row(str(e[0]), int(e[1]), str(e[2]), st, false, 1, true)
			r.name = "extra_%s_%d" % [e[0], e[1]]
			# as wide as the picture's labels (a row clips its text, so it would take no more than its icon)
			r.custom_minimum_size = Vector2(ControllerDiagram.FULL["col_w"], CHIP_H)
			# on the plate the picture's labels have, so it reads as pressable as the chips beside it
			var plate := UiKit.box(ControllerDiagram.PLATE, ControllerDiagram.PLATE_EDGE, 1, 3, 6)
			plate.content_margin_top = 2
			plate.content_margin_bottom = 2
			r.add_theme_stylebox_override("normal", plate)
			_live_button(r)
			r.pressed.connect(func(): press_slot(r.action, r.slot))
			r.gui_input.connect(_extra_input.bind(r))
		r.spec = str(e[2])
		r.control = ""
		ControllerDiagram._dress_row(r, st, false, key == _listening)
		r.tooltip_text = "%s: press to change" % InputPrompts.spec_text(r.spec, st)
		rows_now[key] = r
		offs.append(r)
	for key in _extra_rows:
		if not rows_now.has(key):
			_drop(_extra_rows[key])
	_extra_rows = rows_now
	var chips_now := {}
	for act in InputBindings.ACTIONS:
		if InputBindings.slot_count(act, cls) == 0 or _first_empty(act) < 0:
			continue
		var b: Button = _chips.get(act)
		if b == null:
			b = Button.new()
			b.name = "add_%s" % act
			b.custom_minimum_size = Vector2(0, CHIP_H)
			b.set_meta("action", act)
			_live_button(b)
			b.pressed.connect(_on_chip.bind(act))
		var none := act in InputBindings.REQUIRED and InputBindings.slots(act, cls).count("") == InputBindings.slot_count(act, cls)
		if _listening != "" and _listening.begins_with(act + "|") and _listen_on == b:
			b.text = "PRESS..."  # (its width stays pinned: _listen_started)
		else:
			b.custom_minimum_size.x = 0.0
			b.text = "+ %s%s" % [_title(act), " (NONE)" if none else ""]
			b.modulate.a = 1.0
		for c in ["font_color", "font_hover_color", "font_focus_color"]:
			if none:
				b.add_theme_color_override(c, WARN)
			else:
				b.remove_theme_color_override(c)
		b.tooltip_text = "Bind a pad button to %s" % _title(act)
		chips_now[act] = b
	for act in _chips:
		if not chips_now.has(act):
			_drop(_chips[act])
	_chips = chips_now
	var adds: Array[Control] = [_add_head]  # ADD, then its chips
	for act in InputBindings.ACTIONS:
		if _chips.has(act):
			adds.append(_chips[act])
	# the two heads stay children (hidden when they head nothing), so they are freed with the page
	_extra_head.visible = not off.is_empty()
	_add_head.visible = not _chips.is_empty()
	_off_flow.visible = not off.is_empty()
	_add_flow.visible = not _chips.is_empty()
	for pair in [[_off_flow, offs], [_add_flow, adds]]:
		var flow: HFlowContainer = pair[0]
		var list: Array = pair[1]
		for i in list.size():
			var c: Control = list[i]
			if c.get_parent() != flow:
				if c.get_parent():
					c.get_parent().remove_child(c)
				flow.add_child(c)
			flow.move_child(c, i)


func _drop(c: Control) -> void:
	if c.get_parent():
		c.get_parent().remove_child(c)
	c.queue_free()


func _live_button(b: Button) -> void:
	b.focus_mode = Control.FOCUS_ALL
	UiKit.hover_focus(b)
	b.focus_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -10.0))


func _extra_input(event: InputEvent, r: ControllerDiagram.Row) -> void:
	if InputPrompts.is_listening() or not event.is_action_pressed("ui_clear"):
		return
	r.accept_event()
	clear(r.action, r.slot)


func _on_chip(action: String) -> void:
	var s := _first_empty(action)
	if s >= 0:
		press_slot(action, s)


## The extras that take the focus, in order: the off-picture rows, then the chips.
func _extras_focusables() -> Array:
	var out := []
	for flow in [_off_flow, _add_flow]:
		for c in (flow as Node).get_children():
			if c is BaseButton and (c as Control).visible:
				out.append(c)
	return out


# ---------------------------------------------------------------- the settings column
func _settings() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = SIDE_W
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.section("LAYOUT"))
	v.add_child(_layout_dropdown(SIDE_W))
	_layout_note = UiKit.label("", 14, UiKit.TEXT_DIM)
	_layout_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# two lines kept for it, so the column below never jumps when a one-line note (CUSTOM) comes in
	_layout_note.custom_minimum_size = Vector2(SIDE_W, 40)
	_layout_note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(_layout_note)
	v.add_child(_vgap())
	v.add_child(UiKit.section("CONTROLLER PICTURE"))
	var pics: Array = ["AUTO"]
	for st in InputPrompts.PAD_STYLES:
		pics.append(ControllerDiagram.PICTURE_TITLES[st])
	picture_dd = UiKit.dropdown(pics, 0, _on_picture)
	picture_dd.custom_minimum_size.x = SIDE_W
	picture_dd.clip_text = true
	picture_dd.tooltip_text = "The pad drawn here. AUTO follows BUTTON PROMPTS (or the pad in use). Only for this page."
	v.add_child(picture_dd)
	v.add_child(_vgap())
	v.add_child(UiKit.section("BUTTON PROMPTS"))
	var names: Array = InputPrompts.STYLE_CHOICES.map(func(c: String) -> String: return InputPrompts.STYLE_TITLES[c])
	var at := maxi(InputPrompts.STYLE_CHOICES.find(str(Game.settings.get("prompt_style", "auto"))), 0)
	style_dd = UiKit.dropdown(names, at, func(i: int):
		Game.settings["prompt_style"] = InputPrompts.STYLE_CHOICES[i]
		Game.settings_changed.emit()
		_swap_note())
	style_dd.custom_minimum_size.x = SIDE_W
	style_dd.clip_text = true  # (AUTO's detected family never widens the dialog)
	style_dd.tooltip_text = "The button icons in the menus and on the HUD."
	v.add_child(style_dd)
	v.add_child(_vgap())
	v.add_child(UiKit.section("VIBRATION"))
	vib = UiKit.slider(0, 100, 10, roundf(float(Game.settings.get("vibration", DEFAULT_VIBRATION)) * 100.0), func(x: float):
		Game.settings["vibration"] = x / 100.0
		# a short buzz at the new strength (also from the keyboard or the mouse, to feel it)
		InputPrompts.rumble(0.6, 0.6, 0.25, true), "%d%%", 190)
	v.add_child(vib)
	v.add_child(UiKit.section("STICK DEAD ZONE"))
	dz = UiKit.slider(5, 50, 5, roundf(float(Game.settings.get("stick_deadzone", DEFAULT_DEADZONE)) * 100.0), func(x: float):
		Game.settings["stick_deadzone"] = x / 100.0
		Game.settings_changed.emit(), "%d%%", 190)
	v.add_child(dz)
	v.add_child(_vgap())
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 10)
	var sl := UiKit.label("Nintendo pads: confirm with A", 16, UiKit.TEXT)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sw.add_child(sl)
	swap = UiKit.toggle(bool(Game.settings.get("nintendo_swap", true)), func(on: bool):
		Game.settings["nintendo_swap"] = on
		Game.settings_changed.emit()
		_swap_note())
	sw.add_child(swap)
	v.add_child(sw)
	pad_info = UiKit.label("", 14, UiKit.TEXT_DIM)
	pad_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad_info.custom_minimum_size.x = SIDE_W
	v.add_child(pad_info)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	reset_button = UiKit.button("RESET CONTROLLER", SIDE_W)
	reset_button.pressed.connect(_ask_reset)
	v.add_child(reset_button)
	return v


static func _vgap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 4
	return c


## The side column's controls the D-pad stops on, top to bottom.
func _side_controls() -> Array:
	return [layout_dd, picture_dd, style_dd, vib.get_child(0), dz.get_child(0), swap, reset_button]


func _on_picture(i: int) -> void:
	diagram.style = "" if i <= 0 else InputPrompts.PAD_STYLES[i - 1]
	_rebuild_extras()
	_queue_wire()


## The menus' confirm / back change over only when the player leaves this page (OptionsPanel
## holds them, InputPrompts.hold_swap): say so, or the next press would surprise them.
func _swap_note() -> void:
	if InputPrompts.swap_pending():
		_say("Menus will confirm with the %s face button once you leave this page." % ("bottom" if InputPrompts.swapped()
			else "right"), "", HINT)


func _ask_reset() -> void:
	_ask("RESET CONTROLLER", "Put every pad button, the button prompts, vibration and the dead zone back the way they came?",
		"RESET", reset_pad)


func reset_pad() -> void:
	if _listening != "":
		InputPrompts.cancel_listen()
	Game.settings["prompt_style"] = "auto"
	Game.settings["vibration"] = DEFAULT_VIBRATION
	Game.settings["stick_deadzone"] = DEFAULT_DEADZONE
	Game.settings["nintendo_swap"] = true
	InputBindings.apply_preset(cls, "standard")
	Game.settings_changed.emit()
	style_dd.select(0)
	_set_slider(vib, DEFAULT_VIBRATION * 100.0)
	_set_slider(dz, DEFAULT_DEADZONE * 100.0)
	swap.set_pressed_no_signal(true)
	_rebuild()
	_say("The controller is back the way it came.", "", HINT)
	_swap_note()


static func _set_slider(h: HBoxContainer, v: float) -> void:
	(h.get_child(0) as HSlider).set_value_no_signal(v)
	(h.get_child(1) as Label).text = "%d%%" % roundi(v)


# ---------------------------------------------------------------- BindingsPage
func _page_style() -> String:
	return diagram.shown_style() if diagram else InputPrompts.pad_style()


func _rebuild() -> void:
	if diagram == null or _side == null:
		return
	var det := InputPrompts.detected_style()
	style_dd.set_item_text(0, "AUTO  (%s)" % (pad_title(det) if det != "" else "XBOX"))
	picture_dd.set_item_text(0, "AUTO  (%s)" % ControllerDiagram.PICTURE_TITLES.get(InputPrompts.pad_style(), "XBOX SERIES"))
	var pads := InputPrompts.connected_pads()
	if pads.is_empty():
		pad_info.text = "No controller connected."
	else:
		var n := InputPrompts.pad_name()
		pad_info.text = (n if n != "" else "Controller") + ("" if InputPrompts.can_rumble() else "  ·  no vibration") \
			+ ("" if pads.size() < 2 else "  ·  %d connected" % pads.size())
	vib.modulate.a = 1.0 if InputPrompts.can_rumble() else 0.55
	_rebuild_extras()
	super()
	_queue_wire()


func _slot_node(action: String, slot: int) -> Control:
	var r := diagram.row_for(action, slot)
	if r:
		return r
	if _extra_rows.has(_key(action, slot)):
		return _extra_rows[_key(action, slot)]
	return _chips.get(action) if InputBindings.get_slot(action, cls, slot) == "" else null


func _listen_started(action: String, slot: int) -> void:
	var key := _key(action, slot)
	_listen_on = null
	if diagram.row_for(action, slot):
		diagram.set_listening(action, slot)
	elif _extra_rows.has(key):
		_listen_on = _extra_rows[key]
		ControllerDiagram._dress_row(_listen_on, _page_style(), false, true)
	elif _chips.has(action):
		_listen_on = _chips[action]
		# (pinned to its width first, so the chips after it never jump left under the player's eyes)
		_listen_on.custom_minimum_size.x = _listen_on.size.x
		(_listen_on as Button).text = "PRESS..."


func _listen_ended(_action: String, _slot: int) -> void:
	diagram.set_listening("", -1)
	if is_instance_valid(_listen_on):
		_listen_on.modulate.a = 1.0
		if _listen_on in _chips.values():
			_listen_on.custom_minimum_size.x = 0.0
	_listen_on = null


func _pulse(alpha: float) -> void:
	if is_instance_valid(_listen_on):
		_listen_on.modulate.a = alpha


## The new binding's label takes the focus (it may be on another button of the picture now), and
## it and the label of the slot it swapped with flash.
func _after_capture(action: String, slot: int, result: Dictionary) -> void:
	var keys := [_key(action, slot)]
	if str(result.get("moved_action", "")) != "":
		keys.append(_key(str(result["moved_action"]), int(result.get("moved_slot", -1))))
	diagram.flash(keys)
	var n := _slot_node(action, slot)
	if n == null:
		n = diagram.first_row()
	if n and n.is_visible_in_tree():
		n.grab_focus()


## The emptied slot's label is gone: its action's ADD chip takes the focus.
func _after_clear(action: String, _slot: int) -> void:
	var c := chip_for(action)
	if c and c.is_visible_in_tree():
		c.grab_focus()


## Down from the tab bar: the first label (the left column's top).
func aim_tabs() -> void:
	_aim()
	_queue_wire()


func _aim() -> void:
	if dialog == null or dialog.tabs == null or not is_inside_tree() or not dialog.tabs.is_inside_tree() \
			or not is_visible_in_tree():
		return
	var first := diagram.first_row()
	if first:
		dialog.tabs.focus_neighbor_bottom = dialog.tabs.get_path_to(first)


# ---------------------------------------------------------------- the D-pad's ways
func _queue_wire() -> void:
	if not _wire_queued:
		_wire_queued = true
		_wire.call_deferred()


static func _cy(c: Control) -> float:
	return c.get_global_rect().get_center().y


## The control of `list` nearest in height to `from` (null: none).
static func _nearest_y(from: Control, list: Array) -> Control:
	var best: Control = null
	var bd := INF
	var y := _cy(from)
	for o in list:
		var d := absf(_cy(o) - y)
		if d < bd - 0.01:
			bd = d
			best = o
	return best


## The neighbours that leave the picture (the diagram sets those inside it after every layout):
## the columns' top rows go up to the tab bar and their bottom rows down to the first extra; the
## right column's right goes to the side column control nearest in height, whose left comes back;
## the side column goes up and down in order; the extras go left and right among themselves, up to
## the nearer column's bottom row and, from the last one, right to RESET CONTROLLER.
func _wire() -> void:
	_wire_queued = false
	if not is_inside_tree() or dialog == null or dialog.tabs == null or not dialog.tabs.is_inside_tree():
		return
	var tabs: Control = dialog.tabs
	var left: Array = []
	var right: Array = []
	for r in diagram.rows():
		(left if (r as ControllerDiagram.Row).side < 0 else right).append(r)
	var ex := _extras_focusables()
	var side := _side_controls()
	for col in [left, right]:
		if col.is_empty():
			continue
		var top: Control = col[0]
		top.focus_neighbor_top = top.get_path_to(tabs)
		var bot: Control = col[col.size() - 1]
		bot.focus_neighbor_bottom = bot.get_path_to(ex[0] if not ex.is_empty() else bot)
	for r in right:
		(r as Control).focus_neighbor_right = (r as Control).get_path_to(_nearest_y(r, side))
	for i in side.size():
		var c: Control = side[i]
		c.focus_neighbor_top = c.get_path_to(side[i - 1] if i > 0 else tabs)
		c.focus_neighbor_bottom = c.get_path_to(side[i + 1]) if i < side.size() - 1 else NodePath()
		var near := _nearest_y(c, right if not right.is_empty() else left)
		c.focus_neighbor_left = c.get_path_to(near) if near else NodePath()
	var mid := diagram.get_global_rect().get_center().x
	for i in ex.size():
		var c: Control = ex[i]
		c.focus_neighbor_left = c.get_path_to(ex[i - 1] if i > 0 else c)
		c.focus_neighbor_right = c.get_path_to(ex[i + 1] if i < ex.size() - 1 else reset_button)
		var col: Array = left if not left.is_empty() and (right.is_empty() or c.get_global_rect().get_center().x < mid) \
			else right
		c.focus_neighbor_top = c.get_path_to(col[col.size() - 1]) if not col.is_empty() else NodePath()
	_aim()
