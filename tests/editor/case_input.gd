extends RefCounted
## editor/case_input (P8, CI): the editor's InputMap actions (7.4). Every ed_* action exists with
## its events (and apply() twice changes nothing), none is in InputBindings.ACTIONS, the prompt-only
## ed_mod_* / ed_key_* actions exist, combos match exactly (Ctrl+Z fires ed_undo and no plain-key
## action; no combo fires a plain key's action and no plain key a combo's), base_key gives the plain
## key, and A follows the Nintendo swap.

const NEEDS_CONTENT := false


func run(t: Node) -> void:
	EditorInput.apply()
	var counts := {}
	for a in EditorInput.all_actions():
		counts[a] = InputMap.action_get_events(a).size() if InputMap.has_action(a) else -1
	EditorInput.apply()
	var same := true
	var missing := []
	for a in EditorInput.all_actions():
		if not InputMap.has_action(a) or InputMap.action_get_events(a).is_empty():
			missing.append(a)
		elif InputMap.action_get_events(a).size() != int(counts[a]):
			same = false
	t.check(missing.is_empty(), "every ed_* action exists with events (%d actions; missing %s)" % [EditorInput.all_actions().size(), str(missing)])
	t.check(same, "apply() again replaces the events, it does not add more")
	var table := EditorInput.table()
	var spec_names := ["ed_place", "ed_look", "ed_pan", "ed_orbit", "ed_insert", "ed_vertical", "ed_forward", "ed_back",
		"ed_left", "ed_right", "ed_down", "ed_up", "ed_fast", "ed_slow", "ed_tool_select", "ed_tool_road", "ed_tool_branch",
		"ed_tool_terrain", "ed_tool_paint", "ed_tool_objects", "ed_tool_items", "ed_tool_hazards", "ed_tool_crowds",
		"ed_tool_world", "ed_select_tool", "ed_move", "ed_rotate", "ed_scale", "ed_space", "ed_grid", "ed_focus",
		"ed_frame_all", "ed_top", "ed_home", "ed_drop", "ed_drop_align", "ed_hide", "ed_unhide", "ed_raise", "ed_lower",
		"ed_draw", "ed_undo", "ed_redo", "ed_copy", "ed_cut", "ed_paste", "ed_paste_here", "ed_duplicate", "ed_delete",
		"ed_select_all", "ed_cancel", "ed_save", "ed_save_as", "ed_help", "ed_validation", "ed_line", "ed_test",
		"ed_test_here", "ed_test_watch", "ed_brush_smaller", "ed_brush_bigger", "ed_strength_down", "ed_strength_up",
		"ed_jump", "ed_close_loop", "ed_finish", "ed_scatter", "ed_turn_left", "ed_turn_right", "ed_fast_forward",
		"ed_pad_move_x", "ed_pad_move_y", "ed_pad_look_x", "ed_pad_look_y", "ed_pad_down", "ed_pad_up", "ed_pad_fast",
		"ed_pad_faster", "ed_pad_slower", "ed_pad_prev_tool", "ed_pad_next_tool", "ed_pad_test_here", "ed_pad_test",
		"ed_pad_watch", "ed_pad_help", "ed_pad_menu", "ed_mod_ctrl", "ed_mod_shift", "ed_mod_alt"]
	var absent := []
	for a in spec_names:
		if not InputMap.has_action(a):
			absent.append(a)
	t.check(absent.is_empty(), "the 7.4 table's actions are all there (%s)" % str(absent))
	var leaked := []
	for a in EditorInput.all_actions():
		if a in InputBindings.ACTIONS or not a.begins_with("ed_"):
			leaked.append(a)
	t.check(leaked.is_empty(), "no editor action is in InputBindings.ACTIONS (%s)" % str(leaked))
	_events(t)
	_exact(t, table)
	_base_keys(t, table)
	_swap(t)


func _key(code: Key, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	k.alt_pressed = alt
	return k


func _events(t: Node) -> void:
	t.check(_key(KEY_Z, true).is_action_pressed("ed_undo", false, true), "Ctrl+Z is ed_undo")
	t.check(_key(KEY_Y, true).is_action_pressed("ed_redo", false, true) and _key(KEY_Z, true, true).is_action_pressed("ed_redo", false, true),
		"Ctrl+Y and Ctrl+Shift+Z are ed_redo")
	t.check(_key(KEY_T).is_action_pressed("ed_top", false, true) and _key(KEY_KP_7).is_action_pressed("ed_top", false, true), "T and Numpad 7 are ed_top")
	t.check(_key(KEY_F, false, true).is_action_pressed("ed_frame_all", false, true) and not _key(KEY_F, false, true).is_action_pressed("ed_focus", false, true),
		"Shift+F frames all, not the selection")
	t.check(_key(KEY_F5, false, true).is_action_pressed("ed_test_here", false, true) and _key(KEY_F5, true).is_action_pressed("ed_test_watch", false, true)
		and _key(KEY_F5).is_action_pressed("ed_test", false, true) and not _key(KEY_F5, true).is_action_pressed("ed_test", false, true),
		"F5 / Shift+F5 / Ctrl+F5 are three different drives")
	t.check(_key(KEY_H, false, false, true).is_action_pressed("ed_unhide", false, true) and not _key(KEY_H, false, false, true).is_action_pressed("ed_hide", false, true),
		"Alt+H shows all and does not hide")
	var pad := InputEventJoypadButton.new()
	pad.device = 1
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	t.check(pad.is_action_pressed("ed_pad_test") and not pad.is_action_pressed("ed_pad_test_here"), "pad X on device 1 is ed_pad_test")
	pad.button_index = JOY_BUTTON_DPAD_RIGHT
	t.check(pad.is_action_pressed("ed_pad_next_tool"), "D-pad right is the next tool")
	var lt := InputEventJoypadMotion.new()
	lt.device = 1
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	t.check(lt.is_action_pressed("ed_pad_down"), "LT is ed_pad_down")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	t.check(mb.is_action_pressed("ed_look"), "RMB is ed_look")
	t.check(is_equal_approx(InputMap.action_get_deadzone("ed_pad_move_x"), EditorInput.DEADZONE), "the fly's dead zone is 0.2")


## Every combo event fires only its own action(s); every plain key event fires no combo action;
## Ctrl+Z in particular fires no plain-key action.
func _exact(t: Node, table: Dictionary) -> void:
	var plain_hit := []
	for a in InputMap.get_actions():
		var name := str(a)
		if name.begins_with("ed_") and _key(KEY_Z, true).is_action_pressed(name, false, true) and name != "ed_undo":
			plain_hit.append(name)
	t.check(plain_hit.is_empty(), "Ctrl+Z triggers nothing but ed_undo (%s)" % str(plain_hit))
	var bad := []
	for act in table:
		for spec in table[act]:
			var ev := EditorInput.event_of(str(spec))
			if not (ev is InputEventKey):
				continue
			(ev as InputEventKey).pressed = true
			for other in table:
				# the same key with the same modifiers in two actions is allowed (W flies and moves)
				if other != act and ev.is_action_pressed(other, false, true) and not (spec in table[other]):
					bad.append("%s fires %s" % [spec, other])
	t.check(bad.is_empty(), "exact match: no combo fires a plain key's action, no plain key a combo's (%s)" % str(bad.slice(0, 6)))
	# hold actions still read while a modifier is down (Shift + W flies fast forward)
	var w := _key(KEY_W, false, true)
	t.check(w.is_action_pressed("ed_forward", false, false) and not w.is_action_pressed("ed_move", false, true), "Shift+W still holds ed_forward (polled) but is not the MOVE shortcut")


func _base_keys(t: Node, table: Dictionary) -> void:
	t.check(EditorInput.base_key("ed_undo") == "ed_key_ed_undo", "base_key(ed_undo) = ed_key_ed_undo")
	var evs := InputMap.action_get_events("ed_key_ed_undo")
	var plain_z := evs.size() == 1 and evs[0] is InputEventKey and (evs[0] as InputEventKey).physical_keycode == KEY_Z \
		and not (evs[0] as InputEventKey).ctrl_pressed and not (evs[0] as InputEventKey).shift_pressed
	t.check(plain_z, "ed_key_ed_undo is the plain Z")
	t.check(EditorInput.base_key("ed_move") == "" and EditorInput.base_key("ed_top") == "" and EditorInput.base_key("ed_pad_test") == "",
		"actions without modifiers have no base key")
	var ok := true
	var n := 0
	for act in table:
		var bk := EditorInput.base_key(act)
		if bk == "":
			continue
		n += 1
		if not InputMap.has_action(bk) or EditorInput.mods_of(act).is_empty():
			ok = false
	t.check(ok and n == 17, "every combo has its ed_key_ action and modifier prompts (%d combos)" % n)
	t.check(EditorInput.mods_of("ed_save_as") == PackedStringArray(["ed_mod_ctrl", "ed_mod_shift"]), "Ctrl before Shift in a combo's prompt")
	t.check(EditorInput.mods_of("ed_unhide") == PackedStringArray(["ed_mod_alt"]), "Alt+H prompts Alt")
	var ms := InputMap.action_get_events("ed_mod_shift")
	t.check(ms.size() == 1 and (ms[0] as InputEventKey).physical_keycode == KEY_SHIFT, "ed_mod_shift is the Shift key")


func _swap(t: Node) -> void:
	EditorInput.apply_swap(true)
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_B
	a.pressed = true
	var swapped := a.is_action_pressed("ed_pad_test_here")
	EditorInput.apply_swap(false)
	var back := not a.is_action_pressed("ed_pad_test_here")
	a.button_index = JOY_BUTTON_A
	t.check(swapped and back and a.is_action_pressed("ed_pad_test_here"), "A follows the Nintendo swap (the right face button with it on)")
	EditorInput.apply()
