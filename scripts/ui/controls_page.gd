class_name ControlsPage
extends HBoxContainer
## OPTIONS > CONTROLS. Left: every action's three keyboard and two pad slots as icons (the pad's
## in the BUTTON PROMPTS family). Press a slot, then the new key or button (InputPrompts.listen): a
## key or button another action has swaps over, and the foot of the dialog says what moved;
## X / Delete empties a slot. Right: the button prompts, vibration strength (each change buzzes
## the pad), the stick's dead zone, the Nintendo confirm swap, the pad connected and RESET TO
## DEFAULTS. Everything applies at once (the menus' confirm / back swap once the page is left:
## OptionsPanel); Dialog.close saves it.

## The line for the dialog's foot while a slot listens, or after a change ("" = the usual hints);
## its {tokens} are drawn in `style` ("" = the player's device).
signal hint_changed(text: String, style: String, color: Color)

const SLOT := Vector2(80, 34)
const ICON_PX := 26.0
const LABEL_W := 150
const GAP := 6  # between slots
const HINT_SECONDS := 5.0
const HINT := UiKit.ORANGE
const WARN := Color(1, 0.5, 0.38)
# Game.settings' defaults for the settings on this page (RESET TO DEFAULTS)
const DEFAULT_VIBRATION := 0.7
const DEFAULT_DEADZONE := 0.2

var dialog: Dialog
var _slots := {}  # "action|class|slot" -> Button
var _pad_head: Label
var _style_dd: OptionButton
var _vib: HBoxContainer
var _dz: HBoxContainer
var _swap: CheckButton
var _pad_info: Label
var _reset: Button
var _listening := ""  # the slot key listening for its new input
var _left := -1  # the seconds the listening hint shows
var _hint_t := 0.0  # the after-a-change hint goes away after this
var _t := 0.0


func _init(owner_dialog: Dialog = null) -> void:
	dialog = owner_dialog
	add_theme_constant_override("separation", 26)
	add_child(_table())
	add_child(_settings())
	_refresh()


func _enter_tree() -> void:
	if not visibility_changed.is_connected(_aim_tabs):
		visibility_changed.connect(_aim_tabs)
	InputPrompts.prompts_changed.connect(_refresh)
	InputPrompts.rebind_captured.connect(_on_captured)
	InputPrompts.rebind_cancelled.connect(_on_cancelled)
	_refresh()


func _exit_tree() -> void:
	InputPrompts.prompts_changed.disconnect(_refresh)
	InputPrompts.rebind_captured.disconnect(_on_captured)
	InputPrompts.rebind_cancelled.disconnect(_on_cancelled)
	if _listening != "":
		_listening = ""
		InputPrompts.cancel_listen()


# ---------------------------------------------------------------- the bindings table
static func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _table() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var a := UiKit.section("ACTION")
	a.custom_minimum_size.x = LABEL_W + 10
	head.add_child(a)
	var k := UiKit.section("KEYBOARD")
	k.custom_minimum_size.x = SLOT.x * InputBindings.KEY_SLOTS + GAP * (InputBindings.KEY_SLOTS - 1) + 20
	head.add_child(k)
	# as wide as the pad slots whatever the family's name, so the dialog never changes width
	_pad_head = UiKit.section("GAMEPAD")
	_pad_head.custom_minimum_size.x = SLOT.x * InputBindings.PAD_SLOTS + GAP * (InputBindings.PAD_SLOTS - 1)
	_pad_head.clip_text = true
	_pad_head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_pad_head)
	v.add_child(head)
	for act in InputBindings.ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UiKit.label(InputBindings.TITLES[act], 16, UiKit.TEXT)
		l.custom_minimum_size = Vector2(LABEL_W, SLOT.y)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		row.add_child(_gap(4))
		for i in InputBindings.slot_count(act, InputBindings.KEY):
			row.add_child(_slot(act, InputBindings.KEY, i))
		row.add_child(_gap(14))
		if InputBindings.slot_count(act, InputBindings.PAD) == 0:
			var only := UiKit.label("keyboard only", 14, UiKit.TEXT_DIM)
			only.custom_minimum_size = Vector2(SLOT.x * InputBindings.PAD_SLOTS + GAP * (InputBindings.PAD_SLOTS - 1), SLOT.y)
			only.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			only.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(only)
		else:
			for i in InputBindings.slot_count(act, InputBindings.PAD):
				row.add_child(_slot(act, InputBindings.PAD, i))
		v.add_child(row)
	return v


func _slot_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	return UiKit.box(bg, border, bw, 3, 6)


func _slot(act: String, cls: String, i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_ALL
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	# the theme's button margins are for text buttons: an icon slot is lower
	b.add_theme_stylebox_override("normal", _slot_style(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 1))
	b.add_theme_stylebox_override("hover", _slot_style(Color(1, 1, 1, 0.12), UiKit.ORANGE, 1))
	b.add_theme_stylebox_override("pressed", _slot_style(Color(UiKit.ORANGE.r, UiKit.ORANGE.g, UiKit.ORANGE.b, 0.35), UiKit.ORANGE, 1))
	b.add_theme_stylebox_override("focus", _slot_style(Color(0, 0, 0, 0), UiKit.ORANGE, 2))
	b.add_theme_stylebox_override("disabled", _slot_style(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.06), 1))
	b.pressed.connect(_on_slot.bind(act, cls, i))
	b.gui_input.connect(_slot_input.bind(act, cls, i))
	b.focus_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -10.0))
	_slots[_key(act, cls, i)] = b
	return b


static func _key(act: String, cls: String, i: int) -> String:
	return "%s|%s|%d" % [act, cls, i]


static func _style_of(cls: String) -> String:
	return InputPrompts.pad_style() if cls == InputBindings.PAD else InputPrompts.KEYBOARD


func _refresh_slot(key: String) -> void:
	var p := key.split("|")
	var act := p[0]
	var cls := p[1]
	var i := int(p[2])
	var b: Button = _slots[key]
	b.modulate.a = 1.0
	if key == _listening:
		b.icon = null
		b.text = "PRESS..."
		b.tooltip_text = ""
		return
	var spec := InputBindings.get_slot(act, cls, i)
	var st := _style_of(cls)
	var tex := InputPrompts.spec_icon(spec, ICON_PX, st) if spec != "" else null
	b.icon = tex
	b.text = "" if tex else (InputPrompts.spec_text(spec, st) if spec != "" else "—")
	var locked := InputBindings.is_locked(act, cls, i)
	if locked:
		b.modulate.a = 0.6
	b.tooltip_text = ("%s (always pauses)" if locked else "%s: press to change") % InputPrompts.spec_text(spec, st) \
		if spec != "" else "Empty: press to bind"


## The pad column's head: the family's name (XBOX, PLAYSTATION...), GAMEPAD for an unknown pad.
static func pad_title(style_id: String) -> String:
	var fam := InputPrompts.family(style_id)
	return "GAMEPAD" if fam == "generic" else str(InputPrompts.STYLE_TITLES.get(fam, "GAMEPAD"))


func _refresh() -> void:
	if _pad_head == null:
		return
	_pad_head.text = pad_title(InputPrompts.pad_style())
	for key in _slots:
		_refresh_slot(key)
	var det := InputPrompts.detected_style()
	_style_dd.set_item_text(0, "AUTO  (%s)" % (pad_title(det) if det != "" else "XBOX"))
	var pads := InputPrompts.connected_pads()
	if pads.is_empty():
		_pad_info.text = "No controller connected."
	else:
		var n := InputPrompts.pad_name()
		_pad_info.text = (n if n != "" else "Controller") + ("" if InputPrompts.can_rumble() else "  ·  no vibration") \
			+ ("" if pads.size() < 2 else "  ·  %d connected" % pads.size())
	_vib.modulate.a = 1.0 if InputPrompts.can_rumble() else 0.55
	_aim_tabs()


## With a pad in use, down from the tab bar goes to the first pad slot (not across the keyboard's).
func _aim_tabs() -> void:
	if dialog == null or dialog.tabs == null or not is_inside_tree() or not dialog.tabs.is_inside_tree():
		return
	if not is_visible_in_tree():
		dialog.tabs.focus_neighbor_bottom = NodePath()
		return
	var to: Button = _slots[_key("accelerate", InputBindings.PAD if InputPrompts.using_pad() else InputBindings.KEY, 0)]
	dialog.tabs.focus_neighbor_bottom = dialog.tabs.get_path_to(to)


# ---------------------------------------------------------------- changing a slot
func _on_slot(act: String, cls: String, i: int) -> void:
	if InputPrompts.is_listening():
		return
	if InputBindings.is_locked(act, cls, i):
		_say("%s always pauses and goes back in the menus: it can't be changed." % ("Esc" if cls == InputBindings.KEY
			else "{pause}"), _style_of(cls), WARN)
		return
	if not InputPrompts.listen(act, cls, i):
		return
	Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0)
	_listening = _key(act, cls, i)
	_left = -1
	_hint_t = 0.0
	_refresh_slot(_listening)
	_listen_hint()


func _listen_hint() -> void:
	var l := InputPrompts.listening_for()
	if l.is_empty():
		return
	var secs := ceili(InputPrompts.listen_time_left())
	if secs == _left:
		return
	_left = secs
	var what := str(InputBindings.TITLES[l["action"]]).to_upper()
	if l["cls"] == InputBindings.PAD:
		hint_changed.emit("Press a button, or push a stick or trigger, for %s    {pause} or Esc cancels  (%d)" % [what, secs],
			InputPrompts.pad_style(), HINT)
	else:
		hint_changed.emit("Press a key or a mouse button for %s    Esc%s cancels  (%d)" % [what,
			" or any pad button" if InputPrompts.using_pad() else "", secs], InputPrompts.KEYBOARD, HINT)


func _on_captured(act: String, cls: String, _slot_i: int, _ev: InputEvent, result: Dictionary) -> void:
	if _listening == "":
		return
	_listening = ""
	for key in _slots:
		_refresh_slot(key)
	var st := _style_of(cls)
	if not result.get("ok", false):
		_say("That one belongs to the system: pick another.", st, WARN)
		return
	var title := str(InputBindings.TITLES[act]).to_upper()
	var got := InputPrompts.spec_text(str(result["spec"]), st)
	var msg := "%s: %s" % [title, got]
	var color := HINT
	var moved: String = result.get("moved_action", "")
	if moved != "":
		var other := str(InputBindings.TITLES[moved]).to_upper()
		msg = "%s moved from %s to %s" % [got, other, title]
		if str(result.get("moved_spec", "")) != "":
			msg += "; %s takes %s instead" % [other, InputPrompts.spec_text(str(result["moved_spec"]), st)]
		msg += "."
	var miss := _missing_text()
	if miss != "":
		msg += "  " + miss
		color = WARN
	_say(msg, st, color)


func _on_cancelled(_act: String, _cls: String, _slot_i: int) -> void:
	if _listening == "":
		return
	var key := _listening
	_listening = ""
	_refresh_slot(key)
	_say("Not changed.", "", HINT, 1.5)


## A REQUIRED action a swap left with nothing in a class: "ACCELERATE has no pad button now."
func _missing_text() -> String:
	var out := PackedStringArray()
	for m in InputBindings.missing():
		out.append("%s has no %s now." % [str(InputBindings.TITLES[m[0]]).to_upper(),
			"key" if m[1] == InputBindings.KEY else "pad button"])
	return " ".join(out)


## X / Delete / Backspace on a slot empties it (not the last key or button of an action that needs one).
func _slot_input(event: InputEvent, act: String, cls: String, i: int) -> void:
	if InputPrompts.is_listening() or not event.is_action_pressed("ui_clear"):
		return
	get_viewport().set_input_as_handled()
	var title := str(InputBindings.TITLES[act]).to_upper()
	if InputBindings.get_slot(act, cls, i) == "":
		return
	if InputBindings.is_locked(act, cls, i):
		_on_slot(act, cls, i)
	elif InputBindings.clear_slot(act, cls, i):
		Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0)
		_say("%s: slot cleared." % title, "", HINT)
	else:
		_say("%s needs at least one %s." % [title, "key" if cls == InputBindings.KEY else "pad button"], "", WARN)


func _say(text: String, style: String, color: Color, seconds := HINT_SECONDS) -> void:
	_hint_t = seconds
	hint_changed.emit(text, style, color)


func _process(delta: float) -> void:
	_t += delta
	if _listening != "":
		(_slots[_listening] as Button).modulate.a = 0.55 + 0.45 * absf(sin(_t * 5.0))
		_listen_hint()
	elif _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0:
			hint_changed.emit("", "", HINT)


# ---------------------------------------------------------------- the settings column
func _settings() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.section("BUTTON PROMPTS"))
	var names: Array = InputPrompts.STYLE_CHOICES.map(func(c: String) -> String: return InputPrompts.STYLE_TITLES[c])
	var at := maxi(InputPrompts.STYLE_CHOICES.find(str(Game.settings.get("prompt_style", "auto"))), 0)
	_style_dd = UiKit.dropdown(names, at, func(i: int):
		Game.settings["prompt_style"] = InputPrompts.STYLE_CHOICES[i]
		Game.settings_changed.emit()
		_swap_note())
	_style_dd.custom_minimum_size.x = 280
	_style_dd.clip_text = true  # (AUTO's detected family never widens the dialog)
	v.add_child(_style_dd)
	v.add_child(_vgap())
	v.add_child(UiKit.section("VIBRATION"))
	_vib = UiKit.slider(0, 100, 10, roundf(float(Game.settings.get("vibration", DEFAULT_VIBRATION)) * 100.0), func(x: float):
		Game.settings["vibration"] = x / 100.0
		# a short buzz at the new strength (also from the keyboard or the mouse, to feel it)
		InputPrompts.rumble(0.6, 0.6, 0.25, true), "%d%%", 190)
	v.add_child(_vib)
	v.add_child(_vgap())
	v.add_child(UiKit.section("STICK DEAD ZONE"))
	_dz = UiKit.slider(5, 50, 5, roundf(float(Game.settings.get("stick_deadzone", DEFAULT_DEADZONE)) * 100.0), func(x: float):
		Game.settings["stick_deadzone"] = x / 100.0
		Game.settings_changed.emit(), "%d%%", 190)
	v.add_child(_dz)
	v.add_child(_vgap())
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 10)
	var sl := UiKit.label("Nintendo pads: confirm with A", 16, UiKit.TEXT)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sw.add_child(sl)
	_swap = UiKit.toggle(bool(Game.settings.get("nintendo_swap", true)), func(on: bool):
		Game.settings["nintendo_swap"] = on
		Game.settings_changed.emit()
		_swap_note())
	sw.add_child(_swap)
	v.add_child(sw)
	_pad_info = UiKit.label("", 14, UiKit.TEXT_DIM)
	_pad_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pad_info.custom_minimum_size.x = 280
	v.add_child(_pad_info)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	_reset = UiKit.button("RESET TO DEFAULTS", 280)
	_reset.pressed.connect(_ask_reset)
	v.add_child(_reset)
	return v


## The menus' confirm / back change over only when the player leaves this page (OptionsPanel
## holds them, InputPrompts.hold_swap): say so, or the next press would surprise them.
func _swap_note() -> void:
	if InputPrompts.swap_pending():
		_say("Menus will confirm with the %s face button once you leave this page." % ("bottom" if InputPrompts.swapped()
			else "right"), "", HINT)


static func _vgap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 4
	return c


func _ask_reset() -> void:
	var m := MessageBox.new("RESET CONTROLS", "Put every key and button, the button prompts, vibration and the dead zone back the way they came?",
		false, false, "RESET", "CANCEL")
	m.focus_cancel = true
	m.answered.connect(func(ok: bool, _t: String):
		if ok:
			reset_all())
	(dialog if dialog else self).add_child(m)


func reset_all() -> void:
	Game.settings["prompt_style"] = "auto"
	Game.settings["vibration"] = DEFAULT_VIBRATION
	Game.settings["stick_deadzone"] = DEFAULT_DEADZONE
	Game.settings["nintendo_swap"] = true
	InputBindings.reset()
	Game.settings_changed.emit()
	_style_dd.select(0)
	_set_slider(_vib, DEFAULT_VIBRATION * 100.0)
	_set_slider(_dz, DEFAULT_DEADZONE * 100.0)
	_swap.set_pressed_no_signal(true)
	_refresh()
	_say("Every control is back the way it came.", "", HINT)
	_swap_note()


static func _set_slider(h: HBoxContainer, v: float) -> void:
	(h.get_child(0) as HSlider).set_value_no_signal(v)
	(h.get_child(1) as Label).text = "%d%%" % roundi(v)
