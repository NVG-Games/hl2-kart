class_name BindingsPage
extends HBoxContainer
## What OPTIONS' two binding tabs share (KeysPage: KEYBOARD & MOUSE, PadPage: CONTROLLER), one
## slot class each (`cls`): press a slot, then the new key or button (InputPrompts.listen), with a
## countdown at the dialog's foot; what a capture, a swap, a cancel or a clear (X / Delete) did,
## and a warning when a needed action is left with nothing; a locked slot (pause's Esc / Start)
## only explains; the LAYOUT dropdown (InputBindings' presets, CUSTOM when the slots match none,
## asking before it replaces the player's own layout); questions in a MessageBox. Both tabs work
## whatever is plugged in. A subclass builds the page and says which control stands for a slot
## (_slot_node), how it redraws (_rebuild) and where the tab bar's down goes (aim_tabs).
## Everything applies at once; Dialog.close saves it.

## The line for the dialog's foot while a slot listens, or after a change ("" = the usual hints);
## its {tokens} are drawn in `style` ("" = the player's device).
signal hint_changed(text: String, style: String, color: Color)

const HINT_SECONDS := 5.0
const HINT := UiKit.ORANGE
const WARN := Color(1, 0.5, 0.38)
const PULSE_RATE := 5.0

var dialog: Dialog
## InputBindings.KEY or InputBindings.PAD.
var cls := ""
## The LAYOUT dropdown: the class's presets, then CUSTOM (disabled: shown while no preset matches).
var layout_dd: OptionButton
var _layout_note: Label
var _layout_ids: Array = []
var _listening := ""  # "action|slot" of the slot listening for its new input
var _left := -1  # the seconds the listening hint shows
var _hint_t := 0.0  # the after-a-change hint goes away after this
var _t := 0.0


func _init(owner_dialog: Dialog = null, slot_class := "") -> void:
	dialog = owner_dialog
	cls = slot_class


func _enter_tree() -> void:
	if not visibility_changed.is_connected(_on_visibility):
		visibility_changed.connect(_on_visibility)
	InputPrompts.prompts_changed.connect(_on_prompts)
	InputPrompts.rebind_captured.connect(_on_captured)
	InputPrompts.rebind_cancelled.connect(_on_cancelled)
	_rebuild()


func _exit_tree() -> void:
	InputPrompts.prompts_changed.disconnect(_on_prompts)
	InputPrompts.rebind_captured.disconnect(_on_captured)
	InputPrompts.rebind_cancelled.disconnect(_on_cancelled)
	if _listening != "":
		_listening = ""
		InputPrompts.cancel_listen()


func _on_prompts() -> void:
	_rebuild()


## Another tab took over: a slot still listening gives up, and this page's line leaves the foot.
func _on_visibility() -> void:
	if not is_visible_in_tree():
		_hint_t = 0.0
		if _listening != "":
			InputPrompts.cancel_listen()
	aim_tabs()


# ---------------------------------------------------------------- for the subclasses
## Redraws the page from the bindings (InputPrompts.prompts_changed: a binding, the device, the
## pad's family).
func _rebuild() -> void:
	_sync_layout()


## Points the dialog's tab bar down at this page's first control while the page shows.
func aim_tabs() -> void:
	pass


## The control that stands for a slot (it pulses while it listens, and takes the focus back).
func _slot_node(_action: String, _slot: int) -> Control:
	return null


## The style the page draws its bindings in: the keyboard's, or the pad family on the page.
func _page_style() -> String:
	return InputPrompts.KEYBOARD if cls == InputBindings.KEY else InputPrompts.pad_style()


## The style the foot's messages name buttons in: the keyboard's, or the family of the pad in the
## player's hands (InputPrompts.pad_style()), even while CONTROLLER previews another picture.
func _msg_style() -> String:
	return InputPrompts.KEYBOARD if cls == InputBindings.KEY else InputPrompts.pad_style()


## A slot started listening (the page shows PRESS... on it) / stopped (it shows its binding again).
func _listen_started(_action: String, _slot: int) -> void:
	pass


func _listen_ended(_action: String, _slot: int) -> void:
	pass


## The listening slot's control, this bright (0.1 .. 1).
func _pulse(alpha: float) -> void:
	var p := _listening.split("|")
	var n := _slot_node(p[0], int(p[1])) if p.size() == 2 else null
	if n:
		n.modulate.a = alpha


## A new binding went in (result: InputBindings.set_slot's), after the page redrew.
func _after_capture(action: String, slot: int, _result: Dictionary) -> void:
	var n := _slot_node(action, slot)
	if n and n.is_visible_in_tree():
		n.grab_focus()


## A slot was emptied, after the page redrew.
func _after_clear(_action: String, _slot: int) -> void:
	pass


# ---------------------------------------------------------------- changing a slot
static func _key(action: String, slot: int) -> String:
	return "%s|%d" % [action, slot]


static func _title(action: String) -> String:
	return str(InputBindings.TITLES.get(action, action)).to_upper()


## "key" or "pad button", as the messages name a binding of this class.
func _thing() -> String:
	return "key" if cls == InputBindings.KEY else "pad button"


## A slot was pressed (A / Enter / a click): listen for its new input; a locked one explains.
func press_slot(action: String, slot: int) -> void:
	if InputPrompts.is_listening():
		return
	if InputBindings.is_locked(action, cls, slot):
		_say("%s always pauses and goes back in the menus: it can't be changed." % ("Esc" if cls == InputBindings.KEY
			else "{pause}"), _msg_style(), WARN)
		return
	if not InputPrompts.listen(action, cls, slot):
		return
	Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0)
	_listening = _key(action, slot)
	_left = -1
	_hint_t = 0.0
	_t = 0.0
	_listen_started(action, slot)
	_listen_hint()


## The slot listening now ("action|slot", "" = none).
func listening_slot() -> String:
	return _listening


func _listen_hint() -> void:
	var l := InputPrompts.listening_for()
	if l.is_empty():
		return
	var secs := ceili(InputPrompts.listen_time_left())
	if secs == _left:
		return
	_left = secs
	var what := _title(l["action"])
	if l["cls"] == InputBindings.PAD:
		hint_changed.emit("Press a button, or push a stick or trigger, for %s    {pause} or Esc cancels  (%d)" % [what, secs],
			_msg_style(), HINT)
	else:
		hint_changed.emit("Press a key or a mouse button for %s    Esc%s cancels  (%d)" % [what,
			" or any pad button" if InputPrompts.using_pad() else "", secs], InputPrompts.KEYBOARD, HINT)


func _on_captured(act: String, c: String, slot: int, _ev: InputEvent, result: Dictionary) -> void:
	if _listening == "" or c != cls:
		return
	_listening = ""
	_listen_ended(act, slot)
	_rebuild()
	var st := _msg_style()
	if not result.get("ok", false):
		if result.get("why", "") == "menus":
			_say("%s confirms or goes back in the menus, so it can't pause: pick another." % InputPrompts.spec_text(
				str(result["spec"]), st), st, WARN)
		else:
			_say("That one belongs to the system: pick another.", st, WARN)
		return
	var title := _title(act)
	var got := InputPrompts.spec_text(str(result["spec"]), st)
	var msg := "%s: %s" % [title, got]
	var color := HINT
	var moved: String = result.get("moved_action", "")
	var moved_spec := str(result.get("moved_spec", ""))
	if moved == act:
		# the action's own two slots traded places (the picture makes it easy: A pressed for RT)
		msg = ("%s: %s and %s swapped slots." % [title, got, InputPrompts.spec_text(moved_spec, st)]) if moved_spec != "" \
			else "%s: %s moved to this slot." % [title, got]
	elif moved != "":
		var other := _title(moved)
		msg = "%s moved from %s to %s" % [got, other, title]
		if moved_spec != "":
			msg += "; %s takes %s instead" % [other, InputPrompts.spec_text(moved_spec, st)]
		elif str(result.get("dropped_spec", "")) != "":
			msg += "; %s is free now (it can't pause)" % InputPrompts.spec_text(str(result["dropped_spec"]), st)
		msg += "."
	var miss := _missing_text()
	if miss != "":
		msg += "  " + miss
		color = WARN
	_say(msg, st, color)
	_after_capture(act, slot, result)


func _on_cancelled(act: String, c: String, slot: int) -> void:
	if _listening == "" or c != cls:
		return
	_listening = ""
	_listen_ended(act, slot)
	_rebuild()
	_say("Not changed.", "", HINT, 1.5)


## A REQUIRED action a swap left with nothing in a class: "ACCELERATE has no pad button now."
func _missing_text() -> String:
	var out := PackedStringArray()
	for m in InputBindings.missing():
		out.append("%s has no %s now." % [_title(m[0]), "key" if m[1] == InputBindings.KEY else "pad button"])
	return " ".join(out)


## X / Delete / Backspace on a slot empties it (not the last key or button of an action that needs
## one); on the locked slot it explains.
func clear(action: String, slot: int) -> void:
	if InputPrompts.is_listening() or InputBindings.get_slot(action, cls, slot) == "":
		return
	var title := _title(action)
	if InputBindings.is_locked(action, cls, slot):
		press_slot(action, slot)
	elif InputBindings.clear_slot(action, cls, slot):
		Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0)
		_say("%s: slot cleared." % title, "", HINT)
		_after_clear(action, slot)
	else:
		_say("%s needs at least one %s." % [title, _thing()], "", WARN)


func _say(text: String, style: String, color: Color, seconds := HINT_SECONDS) -> void:
	_hint_t = seconds
	hint_changed.emit(text, style, color)


## A question over the dialog (CANCEL focused); `on_ok` runs on the answer yes, `on_no` on no.
func _ask(title: String, text: String, ok_text: String, on_ok: Callable, on_no := Callable()) -> MessageBox:
	var m := MessageBox.new(title, text, false, false, ok_text, "CANCEL")
	m.focus_cancel = true
	m.answered.connect(func(ok: bool, _text: String):
		if ok:
			on_ok.call()
		elif on_no.is_valid():
			on_no.call())
	(dialog if dialog else self).add_child(m)
	return m


func _process(delta: float) -> void:
	_t += delta
	if _listening != "":
		_pulse(0.55 + 0.45 * absf(sin(_t * PULSE_RATE)))
		_listen_hint()
	elif _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0:
			hint_changed.emit("", "", HINT)


# ---------------------------------------------------------------- LAYOUT (presets)
## The LAYOUT dropdown, `w` px wide.
func _layout_dropdown(w: int) -> OptionButton:
	_layout_ids = InputBindings.preset_ids(cls)
	var names: Array = _layout_ids.map(func(id: String) -> String: return InputBindings.PRESET_TITLES[id])
	names.append(InputBindings.PRESET_TITLES["custom"])
	layout_dd = UiKit.dropdown(names, 0, _on_layout)
	layout_dd.set_item_disabled(names.size() - 1, true)
	layout_dd.custom_minimum_size.x = w
	layout_dd.clip_text = true
	return layout_dd


## The dropdown and its note show the preset the slots match now (CUSTOM: none).
func _sync_layout() -> void:
	if layout_dd == null:
		return
	var id := InputBindings.preset_of(cls)
	var i := _layout_ids.find(id)
	layout_dd.select(i if i >= 0 else _layout_ids.size())
	if _layout_note:
		_layout_note.text = str(InputBindings.PRESET_NOTES.get(id, ""))


## A layout picked: put in at once over another layout; over the player's own one, ask first.
func _on_layout(i: int) -> void:
	if i < 0 or i >= _layout_ids.size():
		_sync_layout()
		return
	var id: String = _layout_ids[i]
	var now := InputBindings.preset_of(cls)
	if now == id:
		return
	if now != "custom":
		_use_layout(id)
		return
	var pad := cls == InputBindings.PAD
	_ask("CONTROLLER LAYOUT" if pad else "KEYBOARD LAYOUT", "Replace your own %s with %s?" % ["buttons" if pad else "keys",
		InputBindings.PRESET_TITLES[id]], "REPLACE", _use_layout.bind(id), _sync_layout)


func _use_layout(id: String) -> void:
	if _listening != "":
		InputPrompts.cancel_listen()
	InputBindings.apply_preset(cls, id)
	_sync_layout()
	_say("Layout: %s." % InputBindings.PRESET_TITLES[id], "", HINT)
