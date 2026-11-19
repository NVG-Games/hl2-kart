class_name EditorInput
## The editor's own ed_* InputMap actions (7.4), incl. the prompt-only modifier and key actions.
## Never part of InputBindings.ACTIONS: presets, slot swapping, OPTIONS and gamepad_test only know
## that list. Specs are InputBindings' ("k<key>", "m<button>", "b<button>", "a<axis>+/-") with
## modifier prefixes "c+" (Ctrl), "s+" (Shift) and "a+" (Alt) made into InputEventKey flags here.
## Shortcuts match exactly (`event.is_action_pressed(a, false, true)`: Ctrl+Z is not Z); hold
## actions are polled with Input.is_action_pressed. P8.

## The pad's fly dead zone (1.10; its own, not settings.stick_deadzone).
const DEADZONE := 0.2
## The prompt-only modifier actions (EditorKit.prompt writes them before a combo's key).
const MODS := {"ed_mod_ctrl": KEY_CTRL, "ed_mod_shift": KEY_SHIFT, "ed_mod_alt": KEY_ALT}
## The prompt-only plain key of a combo: "ed_key_" + the combo's action ("ed_key_ed_undo" = Z).
const KEY_PREFIX := "ed_key_"
## The action A presses (it follows settings.nintendo_swap like InputBindings.apply_ui).
const SWAP_ACTION := "ed_pad_test_here"


## action -> its specs, in the order prompts show them (7.4).
static func table() -> Dictionary:
	return {
		"ed_place": [_m(MOUSE_BUTTON_LEFT)],
		"ed_look": [_m(MOUSE_BUTTON_RIGHT)],
		"ed_pan": [_m(MOUSE_BUTTON_MIDDLE)],
		"ed_orbit": [_k(KEY_ALT)],
		"ed_insert": [_k(KEY_CTRL)],
		"ed_vertical": [_k(KEY_SHIFT)],
		"ed_forward": [_k(KEY_W)],
		"ed_back": [_k(KEY_S)],
		"ed_left": [_k(KEY_A)],
		"ed_right": [_k(KEY_D)],
		"ed_down": [_k(KEY_Q)],
		"ed_up": [_k(KEY_E)],
		"ed_fast": [_k(KEY_SHIFT)],
		"ed_slow": [_k(KEY_CTRL)],
		"ed_tool_select": [_k(KEY_1)],
		"ed_tool_road": [_k(KEY_2)],
		"ed_tool_branch": [_k(KEY_3)],
		"ed_tool_terrain": [_k(KEY_4)],
		"ed_tool_paint": [_k(KEY_5)],
		"ed_tool_objects": [_k(KEY_6)],
		"ed_tool_items": [_k(KEY_7)],
		"ed_tool_hazards": [_k(KEY_8)],
		"ed_tool_crowds": [_k(KEY_9)],
		"ed_tool_world": [_k(KEY_0)],
		"ed_select_tool": [_k(KEY_Q)],
		"ed_move": [_k(KEY_W)],
		"ed_rotate": [_k(KEY_E)],
		"ed_scale": [_k(KEY_R)],
		"ed_space": [_k(KEY_X)],
		"ed_grid": [_k(KEY_G)],
		"ed_focus": [_k(KEY_F)],
		"ed_frame_all": ["s+" + _k(KEY_F)],
		"ed_top": [_k(KEY_T), _k(KEY_KP_7)],
		"ed_home": [_k(KEY_HOME)],
		"ed_drop": [_k(KEY_END)],
		"ed_drop_align": ["s+" + _k(KEY_END)],
		"ed_hide": [_k(KEY_H)],
		"ed_unhide": ["a+" + _k(KEY_H)],
		"ed_raise": [_k(KEY_PAGEUP)],
		"ed_lower": [_k(KEY_PAGEDOWN)],
		"ed_draw": [_k(KEY_D)],
		"ed_undo": ["c+" + _k(KEY_Z)],
		"ed_redo": ["c+" + _k(KEY_Y), "c+s+" + _k(KEY_Z)],
		"ed_copy": ["c+" + _k(KEY_C)],
		"ed_cut": ["c+" + _k(KEY_X)],
		"ed_paste": ["c+" + _k(KEY_V)],
		"ed_paste_here": ["c+s+" + _k(KEY_V)],
		"ed_duplicate": ["c+" + _k(KEY_D)],
		"ed_delete": [_k(KEY_DELETE), _k(KEY_BACKSPACE)],
		"ed_select_all": ["c+" + _k(KEY_A)],
		"ed_cancel": [_k(KEY_ESCAPE)],
		"ed_save": ["c+" + _k(KEY_S)],
		"ed_save_as": ["c+s+" + _k(KEY_S)],
		"ed_help": [_k(KEY_F1)],
		"ed_validation": [_k(KEY_F3)],
		"ed_line": [_k(KEY_F4)],
		"ed_test": [_k(KEY_F5)],
		"ed_test_here": ["s+" + _k(KEY_F5)],
		"ed_test_watch": ["c+" + _k(KEY_F5)],
		"ed_brush_smaller": [_k(KEY_BRACKETLEFT)],
		"ed_brush_bigger": [_k(KEY_BRACKETRIGHT)],
		"ed_strength_down": ["s+" + _k(KEY_BRACKETLEFT)],
		"ed_strength_up": ["s+" + _k(KEY_BRACKETRIGHT)],
		"ed_jump": [_k(KEY_J)],
		"ed_close_loop": [_k(KEY_C)],
		"ed_finish": [_k(KEY_ENTER), _k(KEY_KP_ENTER)],
		"ed_scatter": [_k(KEY_B)],
		"ed_turn_left": [_k(KEY_COMMA)],
		"ed_turn_right": [_k(KEY_PERIOD)],
		"ed_fast_forward": [_k(KEY_TAB), InputBindings.axis_spec(JOY_AXIS_TRIGGER_RIGHT, 1)],
		# the pad (1.10); the fly reads the axes per device itself, these are for prompts and buttons
		"ed_pad_move_x": [InputBindings.axis_spec(JOY_AXIS_LEFT_X, -1), InputBindings.axis_spec(JOY_AXIS_LEFT_X, 1)],
		"ed_pad_move_y": [InputBindings.axis_spec(JOY_AXIS_LEFT_Y, -1), InputBindings.axis_spec(JOY_AXIS_LEFT_Y, 1)],
		"ed_pad_look_x": [InputBindings.axis_spec(JOY_AXIS_RIGHT_X, -1), InputBindings.axis_spec(JOY_AXIS_RIGHT_X, 1)],
		"ed_pad_look_y": [InputBindings.axis_spec(JOY_AXIS_RIGHT_Y, -1), InputBindings.axis_spec(JOY_AXIS_RIGHT_Y, 1)],
		"ed_pad_down": [InputBindings.axis_spec(JOY_AXIS_TRIGGER_LEFT, 1)],
		"ed_pad_up": [InputBindings.axis_spec(JOY_AXIS_TRIGGER_RIGHT, 1)],
		"ed_pad_fast": [InputBindings.button_spec(JOY_BUTTON_LEFT_STICK)],
		"ed_pad_faster": [InputBindings.button_spec(JOY_BUTTON_DPAD_UP)],
		"ed_pad_slower": [InputBindings.button_spec(JOY_BUTTON_DPAD_DOWN)],
		"ed_pad_prev_tool": [InputBindings.button_spec(JOY_BUTTON_DPAD_LEFT)],
		"ed_pad_next_tool": [InputBindings.button_spec(JOY_BUTTON_DPAD_RIGHT)],
		"ed_pad_test_here": [InputBindings.button_spec(JOY_BUTTON_A)],
		"ed_pad_test": [InputBindings.button_spec(JOY_BUTTON_X)],
		"ed_pad_watch": [InputBindings.button_spec(JOY_BUTTON_Y)],
		"ed_pad_help": [InputBindings.button_spec(JOY_BUTTON_BACK)],
		"ed_pad_menu": [InputBindings.button_spec(JOY_BUTTON_START)],
	}


## Adds the actions (once, on the editor's _ready; again is harmless: the events are replaced).
static func apply() -> void:
	var t := table()
	for act in t:
		_set_events(act, t[act])
	# prompt-only: the modifiers and each combo's plain key (nothing polls them)
	for act in MODS:
		_set_events(act, [_k(MODS[act])])
	for act in t:
		var plain := _plain_of(t[act])
		if plain != "":
			_set_events(KEY_PREFIX + act, [plain])
	apply_swap(_swapped())
	var ip := _prompts()
	if ip != null and ip.has_signal("prompts_changed") and not ip.is_connected("prompts_changed", _on_prompts_changed):
		ip.connect("prompts_changed", _on_prompts_changed)


## A on the pad's labelled A: the bottom face button, or the right one on a Nintendo pad with
## settings.nintendo_swap (it swaps with B, which the editor leaves to Dialogs).
static func apply_swap(swap: bool) -> void:
	if not InputMap.has_action(SWAP_ACTION):
		return
	InputMap.action_erase_events(SWAP_ACTION)
	InputMap.action_add_event(SWAP_ACTION, InputBindings.event_of(InputBindings.button_spec(JOY_BUTTON_B if swap else JOY_BUTTON_A)))


## The prompt-only action of a combo's plain key ("" when none): "ed_undo" -> "ed_key_ed_undo".
## A combo is an action whose first key event has Ctrl, Shift or Alt.
static func base_key(action: String) -> String:
	if action.begins_with(KEY_PREFIX) or action in MODS:
		return ""
	var specs: Array = table().get(action, [])
	if _plain_of(specs) == "":
		return ""
	return KEY_PREFIX + action


## The modifier prompt actions of an action's first key event, Ctrl before Shift before Alt.
static func mods_of(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	for spec in table().get(action, []):
		var s := str(spec)
		if not (s.begins_with("c+") or s.begins_with("s+") or s.begins_with("a+") or s.begins_with("k")):
			continue
		var m := _split(s)
		if m.ctrl:
			out.append("ed_mod_ctrl")
		if m.shift:
			out.append("ed_mod_shift")
		if m.alt:
			out.append("ed_mod_alt")
		break
	return out


## Every action apply() adds (the table's, the modifiers and the ed_key_ ones).
static func all_actions() -> PackedStringArray:
	var out := PackedStringArray()
	var t := table()
	for act in t:
		out.append(act)
	for act in MODS:
		out.append(act)
	for act in t:
		if _plain_of(t[act]) != "":
			out.append(KEY_PREFIX + act)
	return out


## The InputMap event of a spec with modifier prefixes (null when the spec is not valid).
static func event_of(spec: String) -> InputEvent:
	var m := _split(spec)
	var ev := InputBindings.event_of(m.spec)
	if ev is InputEventWithModifiers:
		var e := ev as InputEventWithModifiers
		e.ctrl_pressed = m.ctrl
		e.shift_pressed = m.shift
		e.alt_pressed = m.alt
	return ev


# ---------------------------------------------------------------- helpers

static func _k(key: Key) -> String:
	return InputBindings.key_spec(key)


static func _m(button: MouseButton) -> String:
	return "m%d" % button


## {spec, ctrl, shift, alt} of a prefixed spec ("c+s+k90").
static func _split(spec: String) -> Dictionary:
	var out := {"spec": spec, "ctrl": false, "shift": false, "alt": false}
	var s := spec
	while s.length() > 2 and s[1] == "+" and s[0] in ["c", "s", "a"]:
		match s[0]:
			"c":
				out.ctrl = true
			"s":
				out.shift = true
			"a":
				out.alt = true
		s = s.substr(2)
	out.spec = s
	return out


## The plain key spec of a combo's first key event ("" when that event has no modifier).
static func _plain_of(specs: Array) -> String:
	for spec in specs:
		var s := str(spec)
		var m := _split(s)
		if not str(m.spec).begins_with("k"):
			continue
		return str(m.spec) if (m.ctrl or m.shift or m.alt) else ""
	return ""


static func _set_events(act: String, specs: Array) -> void:
	if InputMap.has_action(act):
		InputMap.action_erase_events(act)
	else:
		InputMap.add_action(act, DEADZONE)
	for spec in specs:
		var ev := event_of(str(spec))
		if ev != null:
			InputMap.action_add_event(act, ev)


static func _swapped() -> bool:
	var ip := _prompts()
	return ip != null and ip.has_method("swapped") and bool(ip.call("swapped"))


static func _on_prompts_changed() -> void:
	var want := _swapped()
	if not InputMap.has_action(SWAP_ACTION):
		return
	var evs := InputMap.action_get_events(SWAP_ACTION)
	var now_b := not evs.is_empty() and evs[0] is InputEventJoypadButton and (evs[0] as InputEventJoypadButton).button_index == JOY_BUTTON_B
	if now_b != want:
		apply_swap(want)


static func _prompts() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("InputPrompts") if tree and tree.root else null
