extends RefCounted
## editor/case_ui (P10, CI): EditorKit.prompt writes {ed_undo} as {ed_mod_ctrl}+{ed_key_ed_undo}
## (Ctrl + Z), combos with two modifiers in order, mouse buttons as words, other tokens alone;
## the validation drawer lists a report's issues errors first, then warnings, then info, with a
## FIX button only where fix != "", and a FIX press calls TrackEditor.apply_fix; a row's click
## frames the spot and selects the item; the EDITOR MENU walks by pad (the D-pad goes down every
## entry and back, A opens the TOOL page, B goes back to the main page, B closes it); the
## COMPLEXITY colours at 0.79 / 0.81 / 1.01 and its breakdown; the badge; the palette sets the
## tool; the status bar shows tool.hints through prompt; is_typing; the panels let go of the focus.

const NEEDS_CONTENT := false
const Sel := preload("res://tests/editor/case_select.gd")
const DEV := 1


func run(t: Node) -> void:
	var ed: TrackEditor = await Sel.open_editor(t, Sel.test_doc())
	_prompts(t)
	await _drawer(t, ed)
	_complexity(t, ed)
	await _palette_status(t, ed)
	await _menu(t, ed)
	await _outliner(t, ed)
	await _menus(t, ed)
	await _dialogs(t, ed)
	_number(t)
	await Sel.close_editor(t, ed)


func _prompts(t: Node) -> void:
	t.check(EditorKit.prompt("{ed_undo}") == "{ed_mod_ctrl}+{ed_key_ed_undo}", "prompt: {ed_undo} -> {ed_mod_ctrl}+{ed_key_ed_undo} (%s)" % EditorKit.prompt("{ed_undo}"))
	var segs := InputPrompts.parse_prompt(EditorKit.prompt("{ed_undo} UNDO"))
	var acts := []
	for s in segs:
		if s is Dictionary:
			acts.append(str(s.action))
	t.check(acts == ["ed_mod_ctrl", "ed_key_ed_undo"], "the combo shows two keycaps (%s)" % str(acts))
	var ctrl := InputPrompts.action_text("ed_mod_ctrl", "keyboard").to_upper()
	var z := InputPrompts.action_text("ed_key_ed_undo", "keyboard").to_upper()
	t.check(ctrl.begins_with("CTRL") and z == "Z", "they read Ctrl + Z (%s + %s)" % [ctrl, z])
	t.check(EditorKit.plain("{ed_undo}").to_upper() == ctrl + "+Z", "plain: %s" % EditorKit.plain("{ed_undo}"))
	t.check(EditorKit.prompt("{ed_save_as}") == "{ed_mod_ctrl}+{ed_mod_shift}+{ed_key_ed_save_as}", "Ctrl before Shift (%s)" % EditorKit.prompt("{ed_save_as}"))
	t.check(EditorKit.prompt("{ed_unhide}") == "{ed_mod_alt}+{ed_key_ed_unhide}", "Alt + H (%s)" % EditorKit.prompt("{ed_unhide}"))
	t.check(EditorKit.prompt("press {ed_tool_road} or {ed_delete}") == "press {ed_tool_road} or {ed_delete}", "plain keys stay single tokens")
	t.check(EditorKit.prompt("{ed_look} LOOK · {ed_pan} PAN") == "RIGHT MOUSE LOOK · MIDDLE MOUSE PAN", "mouse buttons are words (%s)" % EditorKit.prompt("{ed_look} LOOK · {ed_pan} PAN"))
	t.check(EditorKit.prompt("{accelerate} GO {nothing}") == "{accelerate} GO {nothing}", "other tokens stay as they are")
	t.check(EditorKit.prompt("{ed_mod_shift} DRAG") == "{ed_mod_shift} DRAG", "a modifier token stays itself")
	var h := EditorKit.hint("{ed_undo} UNDO")
	t.check(h.prompt == "{ed_mod_ctrl}+{ed_key_ed_undo} UNDO", "hint() is a PromptLabel of prompt()")
	h.free()


func _drawer(t: Node, ed: TrackEditor) -> void:
	var ui := ed.ui
	var pad_uid := int(ed.doc.data.pads[0].uid)
	var r := LevelReport.new()
	r.warning("no_items", "No item crates on the lap yet.", {}, "auto_items")
	r.info("bot_lap", "BOT LAP 1:23.4, 0 RESCUES", {})
	r.error("too_tight", "The bend 40 m after the start is too tight for a 14 m road: narrow it ({ed_mod_ctrl} + wheel).", {"s": 40.0, "pos": Vector3(150, 1, 0)}, "narrow")
	r.warning("budget", "Past the budget for props (1600 of 1500): slow PCs may stutter.", {})
	r.error("no_road", "No road yet: press {ed_tool_road} and click on the ground.", {})
	r.warning("pad_grid", "A boost pad is within 12 m of the grid.", {"uid": pad_uid, "pos": Vector3(0, 1, 150)})
	ui.set_report(r)
	ui.toggle_validation()
	await t.frames(2)
	var d := ui.drawer
	var codes := d.shown.map(func(it: Dictionary) -> String: return str(it.code))
	t.check(codes == ["too_tight", "no_road", "no_items", "budget", "pad_grid", "bot_lap"], "the drawer: errors first, then warnings, then info (%s)" % str(codes))
	var fixes := d.fix_buttons.map(func(b: Button) -> String: return str(b.get_meta("issue").fix))
	t.check(fixes == ["narrow", "auto_items"], "FIX buttons only where fix != \"\" (%s)" % str(fixes))
	t.check(d.fix_buttons.size() == 2 and d.fix_buttons[0].text == "NARROW THE ROAD HERE" and d.fix_buttons[1].text == "AUTO ITEMS", "the buttons say what they fix (%s)" % str(d.fix_buttons.map(func(b: Button) -> String: return b.text)))
	var labels := d.list.find_children("*", "PromptLabel", true, false)
	t.check(labels.size() == 6 and (labels[0] as PromptLabel).prompt.find("{ed_mod_ctrl}") >= 0, "every row has its text, key tokens as icons (%d)" % labels.size())
	t.check(ui.badge.text == "2 ERRORS · 3 WARNINGS", "the badge counts them (%s)" % ui.badge.text)
	t.check(d.visible and d.title.text.ends_with("2 ERRORS · 3 WARNINGS"), "F3's drawer is up with the counts")
	# a FIX press calls apply_fix (LevelFixes' ops in one step, or the toast when it has none)
	var steps := ed.history.undo_name()
	ed.last_toast = ""
	d.fix_buttons[0].pressed.emit()
	await t.frames(1)
	t.check(ed.last_toast == "This one cannot be fixed automatically." or ed.history.undo_name().begins_with("FIX: "),
		"a FIX press runs TrackEditor.apply_fix (toast '%s', undo '%s' was '%s')" % [ed.last_toast, ed.history.undo_name(), steps])
	# a row's click frames the spot and selects the item
	ed.selection.clear()
	var cam0 := ed.camera.global_position
	var row := d.list.get_child(5) as Control   # pad_grid (the empty-state label is child 0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	row.gui_input.emit(ev)
	await t.frames(1)
	t.check(ed.selection.uids == PackedInt32Array([pad_uid]), "a row's click selects its item (%s)" % str(ed.selection.uids))
	t.check(not ed.camera.global_position.is_equal_approx(cam0), "and frames its spot")
	ui.toggle_validation()
	t.check(not d.visible, "F3 again hides the drawer")
	# a raceable report
	ui.set_report(LevelReport.new())
	t.check(ui.badge.text == "RACEABLE" and d.shown.is_empty() and d.fix_buttons.is_empty(), "no issues: RACEABLE, an empty drawer")


func _complexity(t: Node, ed: TrackEditor) -> void:
	var ui := ed.ui
	t.check(EditorUI.complexity_color(0.79) == EditorKit.OK_COLOR and EditorUI.complexity_color(0.81) == EditorKit.WARN_COLOR
		and EditorUI.complexity_color(1.01) == EditorKit.ERROR_COLOR, "COMPLEXITY colours: 0.79 normal, 0.81 yellow, 1.01 red")
	for e in [[{"props": 1185}, 0.79, EditorKit.OK_COLOR], [{"props": 1215}, 0.81, EditorKit.WARN_COLOR], [{"lights": 65, "props": 10}, 65.0 / 64.0, EditorKit.ERROR_COLOR]]:
		ui.set_stats(e[0])
		t.near(float(ui.complexity.value), float(e[1]), 0.001, "COMPLEXITY of %s" % str(e[0]))
		t.check(ui.complexity_bar.color == e[2], "the bar's colour at %.2f" % float(e[1]))
	ui.set_stats({"props": 812, "lights": 12, "people": 40, "heavy": 2, "crates": 30})
	t.check(str(ui.complexity.text).begins_with("PROPS 812 / 1500 · LIGHTS 12 / 64 · PEOPLE 40 / 450 · HEAVY HAZARDS 2 / 6 · CRATES 30 / 64"),
		"the breakdown names each term (%s)" % str(ui.complexity.text))
	t.check(ui.complexity_box.tooltip_text.find("PROPS 812 / 1500") >= 0, "hover shows it")
	var big := EditorUI.complexity_of({}, 1025)
	t.near(float(big.value), 0.8, 0.0001, "a 1025 terrain alone is 80 %")


func _palette_status(t: Node, ed: TrackEditor) -> void:
	var ui := ed.ui
	(ui.tool_buttons["select"] as Button).pressed.emit()
	await t.frames(1)
	t.check(ed.tool.id == "select" and (ui.tool_buttons["select"] as Button).button_pressed and not (ui.tool_buttons["road"] as Button).button_pressed,
		"a palette button picks its tool, the active one is lit")
	t.check((ui.tool_buttons["road"] as Button).icon != null and (ui.tool_buttons["road"] as Button).tooltip_text.begins_with("ROAD (2)"), "the palette shows the keycaps and the purpose")
	t.check(ui.options_box.get_child_count() > 0, "SELECT's options are in the right column")
	ed.set_tool("road")
	t.check((ui.tool_buttons["road"] as Button).button_pressed, "a key's tool switch lights its button")
	ed.set_tool("select")
	ed.hover = EditorHit.new()
	ui.refresh_status()
	await t.frames(2)
	var shown := []
	for c in ui.hints_bar.get_children():
		if c is PromptLabel and (c as PromptLabel).visible:
			shown.append((c as PromptLabel).prompt)
	var want: Array = ed.tool.hints(ed.hover).map(func(e: Array) -> String: return EditorKit.prompt(str(e[0])))
	t.check(not shown.is_empty() and shown == want.slice(0, shown.size()), "the status bar shows tool.hints through prompt (%s)" % str(shown))
	t.check(ui.hints_bar.get_combined_minimum_size().x <= ui.hints_holder.size.x + 1.0, "the hints fit the bar")
	ed.status("UNDO MOVE POINT")
	await t.frames(1)
	t.check(ui.message.prompt == "UNDO MOVE POINT", "the status line's text")
	ed.status("")
	ed.select(PackedInt32Array([int(ed.doc.data.props[0].uid), int(ed.doc.data.props[1].uid)]))
	await t.frames(2)
	t.check(ui.sel_label.text == "2 selected", "the selection count (%s)" % ui.sel_label.text)
	t.check(ui.inspector.box.get_child_count() > 0, "the inspector is filled for it (%s)" % ui.inspector.filled_by)
	ed.selection.clear()
	await t.frames(2)
	t.check(ui.inspector.filled_by == "empty", "an empty selection: 'Select something to edit it here.'")
	# typing
	ui.outliner.search.grab_focus()
	t.check(ui.is_typing(), "a text field with the focus: is_typing")
	ui.outliner.search.release_focus()
	t.check(not ui.is_typing(), "and not after")
	# the panels let go of the focus (Enter and the arrows stay the editor's)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	ui.options_box.add_child(b)
	b.grab_focus()
	await t.frames(2)
	t.check(ed.get_viewport().gui_get_focus_owner() == null, "a panel button lets go of the focus")
	b.queue_free()
	# the snap group follows G
	ed.snap["on"] = false
	ui.refresh_status()
	await t.frames(1)
	t.check(not ui.grid_toggle.button_pressed and ui.snap_label.text == "GRID OFF", "the GRID toggle follows the snap state")
	ui.grid_toggle.button_pressed = true
	t.check(bool(ed.snap.on) and bool(Game.settings.editor_snap.on), "GRID on from the bar (and kept in the settings)")
	ui.grid_size.select(4)
	ui.grid_size.item_selected.emit(4)
	t.check(is_equal_approx(float(ed.snap.grid), 4.0), "the grid step from the bar (%s)" % str(ed.snap.grid))
	# toasts and cards
	ed.toast("Copied 12 objects")
	t.check(ui.toasts.get_child_count() >= 1 and ui.toast_log[-1] == "Copied 12 objects", "a toast")
	ed.show_card("PREPARING TEST DRIVE...")
	t.check(ui.card_panel.visible and ui.card_label.text == "PREPARING TEST DRIVE...", "a card")
	ed.hide_card()
	t.check(not ui.card_panel.visible, "and away")


func _menu(t: Node, ed: TrackEditor) -> void:
	var ui := ed.ui
	# the pad wakes (FLY), Start opens the EDITOR MENU
	await _press(t, JOY_BUTTON_LEFT_STICK)
	ui.open_menu()
	await t.frames(3)
	var m := ui.menu
	t.check(m != null and m.is_inside_tree() and m.is_top(), "the EDITOR MENU is up, a Dialog on top")
	if m == null:
		return
	var texts := m.items.map(func(b: Button) -> String: return b.text)
	t.check(texts == EditorMenu.MAIN.map(func(e: Array) -> String: return e[0]), "its entries are 1.10's (%s)" % str(texts))
	t.check(not ed.camera.flying(), "the pad is the menu's while it is up")
	t.check(_focus(ed) == m.items[0], "the focus starts on RESUME (%s)" % _fname(ed))
	var walked := true
	for k in range(1, m.items.size()):
		await _press(t, JOY_BUTTON_DPAD_DOWN)
		if _focus(ed) != m.items[k]:
			walked = false
			t.fail("D-pad down %d: the focus is on %s, not %s" % [k, _fname(ed), m.items[k].text])
			break
	t.check(walked, "the D-pad walks down every entry")
	for k in range(m.items.size() - 2, 0, -1):
		await _press(t, JOY_BUTTON_DPAD_UP)
	t.check(_focus(ed) == m.items[1], "and back up to TOOL (%s)" % _fname(ed))
	await _press(t, JOY_BUTTON_A)
	t.check(m.page == "tool" and m.items.size() == 10 and m.is_ancestor_of(_focus(ed)), "A on TOOL opens the tool page, focused (%s)" % _fname(ed))
	await _press(t, JOY_BUTTON_DPAD_DOWN)
	t.check(m.is_ancestor_of(_focus(ed)), "the D-pad walks the tools")
	await _press(t, JOY_BUTTON_B)
	await t.frames(1)
	t.check(m.page == "main" and is_instance_valid(m) and not m.is_queued_for_deletion() and _focus(ed) == m.items[1], "B goes back to the main page, on TOOL (%s)" % _fname(ed))
	await _press(t, JOY_BUTTON_B)
	await t.frames(2)
	t.check(ui.menu == null and (not is_instance_valid(m) or m.is_queued_for_deletion()), "B on the main page closes the menu")
	t.check(ed.camera.flying(), "and the pad flies again")
	# VIEW > RACING LINE from the menu runs the shortcut's code
	ui.open_menu()
	await t.frames(2)
	ui.menu.show_page("view")
	var line0 := ed.show_line
	ui.menu.items[1].pressed.emit()
	await t.frames(2)
	t.check(ed.show_line != line0 and ui.menu == null, "VIEW > RACING LINE toggles it and closes the menu")
	# the keyboard takes over again
	var k := InputEventKey.new()
	k.keycode = KEY_F12
	k.physical_keycode = KEY_F12
	k.pressed = true
	Input.parse_input_event(k)
	await t.frames(2)
	k = k.duplicate()
	k.pressed = false
	Input.parse_input_event(k)
	await t.frames(2)


## The top bar's menus and the TEST DRIVE options run without a window.
func _menus(t: Node, ed: TrackEditor) -> void:
	var ui := ed.ui
	ui._menus_state()
	var pm := ui.edit_menu.get_popup()
	t.check(pm.get_item_text(pm.get_item_index(EditorUI.E_UNDO)).begins_with("UNDO"), "EDIT names the undo step (%s)" % pm.get_item_text(pm.get_item_index(EditorUI.E_UNDO)))
	t.check(pm.get_item_accelerator(pm.get_item_index(EditorUI.E_UNDO)) == (KEY_Z | KEY_MASK_CTRL), "and shows Ctrl+Z beside it")
	var line0 := ed.show_line
	ui.menu_pressed(EditorUI.V_LINE)
	t.check(ed.show_line != line0, "VIEW > RACING LINE runs F4's code")
	ui.menu_pressed(EditorUI.V_PINS)
	t.check(not bool(ui.view_flags.pins), "VIEW > ISSUE PINS off")
	ui.menu_pressed(EditorUI.V_PINS)
	ed.select(PackedInt32Array([int(ed.doc.data.props[0].uid)]))
	ui.menu_pressed(EditorUI.E_DESELECT)
	t.check(ed.selection.uids.is_empty(), "EDIT > DESELECT")
	ui._open_test_options()
	await t.frames(1)
	t.check(ui._test_pop != null and ui._test_pop.visible, "the TEST DRIVE arrow opens its options")
	var sl := ui._test_pop.find_children("*", "HSlider", true, false)
	(sl[0] as HSlider).value = 3
	t.check(int(EditorSession.test_options({}).bots) == 3, "BOTS 3 is what the next drive takes")
	ui._test_pop.hide()
	await t.frames(1)


## TRACK PROPERTIES renames in one step; AUTO DRESS hands its toggles to TrackEditor.auto_dress;
## OLDER VERSIONS lists none for a new track; MaterialPicker filters by prefix and emits picked.
func _dialogs(t: Node, ed: TrackEditor) -> void:
	var ui := ed.ui
	ui._open_properties()
	await t.frames(2)
	var pd: Dialog = null
	for c in ed.get_node("UI").get_children():
		if c is EditorUI.PropertiesDialog:
			pd = c
	t.check(pd != null, "the name opens TRACK PROPERTIES")
	if pd != null:
		pd.name_f.text = "Moya trassa"
		pd.desc_f.text = "Two hairpins and a jump"
		pd._ok()
		await t.frames(2)
		t.check(str(ed.doc.data.name) == "Moya trassa" and str(ed.doc.data.desc) == "Two hairpins and a jump" and str(ed.doc.data.short) == "MOYA TRASSA",
			"OK renames it and keeps the description (%s / %s)" % [ed.doc.data.name, ed.doc.data.short])
		t.check(ed.history.undo_name() == "RENAME", "as undo steps (%s)" % ed.history.undo_name())
		ui._update_status()
		t.check(ui.name_button.text.begins_with("Moya trassa"), "the top bar shows the new name (%s)" % ui.name_button.text)
	var ad := AutoDressDialog.new(ed)
	ed.open_dialog(ad)
	await t.frames(1)
	t.check(ad.toggles.size() == 5 and ad.opts.values().all(func(v: bool) -> bool: return v), "AUTO DRESS: five toggles, all on")
	(ad.toggles["scenery"] as CheckButton).button_pressed = false
	t.check(ad.opts.scenery == false, "a toggle turns its part off")
	var before := ed.history.undo_name()
	ed.last_toast = ""
	ad.dress()
	for i in 60:
		await t.frames(1)
		if ed.history.undo_name() == "AUTO DRESS" or ed.last_toast != "":
			break
	t.check(ed.history.undo_name() == "AUTO DRESS" or ed.last_toast == "Nothing to add.", "DRESS runs TrackEditor.auto_dress (undo '%s' was '%s', toast '%s')" % [ed.history.undo_name(), before, ed.last_toast])
	var od := EditorUI.OlderDialog.new(ui)
	ed.open_dialog(od)
	await t.frames(1)
	t.check(od.default_focus != null and od.default_focus.text == "CLOSE", "OLDER VERSIONS: none yet for an unsaved track")
	od.close()
	var mp := MaterialPicker.new("nature/grassfloor002a", PackedStringArray(["nature/"]))
	ed.open_dialog(mp)
	await t.frames(2)
	t.check(mp.keys.size() <= MaterialPicker.MAX_SHOWN and Array(mp.keys).all(func(k: String) -> bool: return k.begins_with("nature/")), "MaterialPicker: only the prefix's materials (%d)" % mp.keys.size())
	var got := []
	mp.picked.connect(func(k: String) -> void: got.append(k))
	if not mp.keys.is_empty():
		mp._pick(0)
		t.check(got == [mp.keys[0]], "a pick emits picked(key)")
	else:
		mp.close()
	await t.frames(1)


## The outliner lists the document by group; a row's pick selects, the editor's selection shows.
func _outliner(t: Node, ed: TrackEditor) -> void:
	var o := ed.ui.outliner
	o.rebuild()
	var groups := []
	for g in o.tree.get_root().get_children():
		groups.append(g.get_text(0))
	t.check(groups == ["ROAD (8)", "OBJECTS (3)", "LIGHTS & FX (1)", "ITEMS (1)"], "the outliner's groups (%s)" % str(groups))
	var pad_uid := int(ed.doc.data.pads[0].uid)
	t.check(o.rows.size() == 13 and o.rows.has(pad_uid), "a row per item (%d)" % o.rows.size())
	ed.select(PackedInt32Array([pad_uid]))
	await t.frames(1)
	t.check((o.rows[pad_uid] as TreeItem).is_selected(0), "the editor's selection shows in the tree")
	var light := int(ed.doc.data.lights[0].uid)
	o.tree.deselect_all()
	(o.rows[light] as TreeItem).select(0)
	o._picked()
	t.check(ed.selection.uids == PackedInt32Array([light]), "a row's pick selects it (%s)" % str(ed.selection.uids))
	o.search.text = "crate"
	o.search.text_changed.emit("crate")
	await t.frames(1)
	t.check(o.rows.size() == 3, "the search filters (%d)" % o.rows.size())
	o.search.text = ""
	o.search.text_changed.emit("")
	await t.frames(1)
	ed.selection.clear()


## EditorNumber: a sideways drag (final false while it runs, true at the end), a typed value
## with its suffix, the clamp.
func _number(t: Node) -> void:
	var got := []
	var n := EditorKit.number(14.0, 6.0, 40.0, 0.5, func(v: float, final: bool) -> void: got.append([v, final]), "%.1f", " m")
	t.check(n.text == "14.0 m", "it shows the value with its suffix (%s)" % n.text)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 5)
	n._gui_input(press)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(30, 5)
	n._gui_input(mm)
	var up := press.duplicate()
	up.pressed = false
	up.position = Vector2(30, 5)
	n._gui_input(up)
	t.check(got == [[16.5, false], [16.5, true]], "a 20 px drag: five steps, final at the release (%s)" % str(got))
	got.clear()
	n.text = "99 m"
	n._commit_text()
	t.check(got == [[40.0, true]] and n.value == 40.0, "a typed value is clamped and final (%s)" % str(got))
	n.set_mixed()
	t.check(n.text == "-", "a mixed value shows -")
	n.free()


func _focus(ed: TrackEditor) -> Control:
	return ed.get_viewport().gui_get_focus_owner()


func _fname(ed: TrackEditor) -> String:
	var f := _focus(ed)
	if f == null:
		return "<none>"
	return "%s '%s'" % [f.get_class(), f.text if f is Button else ""]


func _press(t: Node, b: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = DEV
		e.button_index = b
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
		Input.parse_input_event(e)
		await t.frames(2)
