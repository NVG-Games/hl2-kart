extends Node
## Headless walk through every menu screen with a pad only (synthetic pad events, no window; TRACK
## EDITOR's home, NEW RACE's track browser and the TRACK columns of FIND SERVERS and the lobby too): the
## focus enters each screen and is never lost, B leaves every screen and closes every dialog (and
## the focus goes back where it was), LB / RB switch tabs, OPTIONS > KEYBOARD & MOUSE and CONTROLLER
## rebind (a table slot, a label on the pad's picture, an ADD chip), swap, clear, cancel and pick a
## layout, the lobby asks before leaving, and in a race HOW TO DRIVE shows until GO, the intro skips
## on A, the pause menu shows the controls beside it, B resumes from it and a pad going away pauses
## with a note. Prints each failure and a total; exits 1 on any failure. Restores the settings it
## changes. Takes about a minute (it loads a race).
## usage: godot --headless --path . res://tests/pad_nav.tscn


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Runner.new())


class Runner:
	extends Node
	var failures := 0
	var checks := 0
	var _saved := {}

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func check(ok: bool, what: String) -> void:
		checks += 1
		if not ok:
			failures += 1
			print("FAIL: ", what)

	func _frames(n := 2) -> void:
		for i in n:
			await get_tree().process_frame

	func _wait(s: float) -> void:
		await get_tree().create_timer(s, true).timeout

	func _pad(b: JoyButton) -> void:
		for down in [true, false]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.pressed = down
			e.device = 1
			Input.parse_input_event(e)
			await _frames()

	## Holds a pad button for `seconds` (Godot's Slider and TabBar repeat a held D-pad).
	func _hold(b: JoyButton, seconds: float) -> void:
		for down in [true, false]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.pressed = down
			e.device = 1
			Input.parse_input_event(e)
			await _frames()
			if down:
				await _wait(seconds)

	func _key(k: Key) -> void:
		for down in [true, false]:
			var e := InputEventKey.new()
			e.keycode = k
			e.physical_keycode = k
			e.pressed = down
			Input.parse_input_event(e)
			await _frames()

	func _focus() -> Control:
		return get_viewport().gui_get_focus_owner()

	func _focus_name() -> String:
		var f := _focus()
		if f == null:
			return "<none>"
		return "%s '%s'" % [f.get_class(), f.text if f is Button else ""]

	## Moves the focus with the D-pad, checking it never drops.
	func _move(b: JoyButton, times := 1, where := "") -> void:
		for i in times:
			await _pad(b)
			check(_focus() != null, "%s: the D-pad lost the focus" % where)

	func _menu_item(menu: Node, text: String) -> Button:
		for c in menu.items.get_children():
			if (c as Button).text == text:
				return c
		return null

	func _ready() -> void:
		# a 16:9 canvas (1600x900), as ui_fit does: headless the window is 0x0 and the canvas would be
		# 1600x1600, so a panel below y 900 would still count as on the screen
		get_tree().root.size = Vector2i(1280, 720)
		await get_tree().process_frame
		_saved = Game.settings.duplicate(true)
		Game.settings["tutorial_seen"] = true
		# no network beyond the LAN scan: the browser's other lists stay empty
		Game.settings["master_server"] = ""
		Game.settings["favorites"] = []
		Game.settings["history"] = []
		Game.settings["bindings"] = {}
		InputBindings.apply()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		await _wait(1.5)
		await _run()
		for k in _saved:
			Game.settings[k] = _saved[k]
		Game.save_settings()
		InputBindings.apply()
		Game.settings_changed.emit()
		print("pad_nav: %d checks, failures: %d" % [checks, failures])
		get_tree().quit(1 if failures > 0 else 0)

	func _run() -> void:
		var menu: Node = get_tree().current_scene
		await _main_menu(menu)
		await _options(menu)
		await _how_to_play(menu)
		await _soundtrack(menu)
		await _editor_home(menu)
		await _browser(menu)
		await _create(menu)
		await _lobby(menu)
		await _track_browser(menu)
		await _race(menu)

	# ------------------------------------------------------------ main menu
	func _main_menu(menu: Node) -> void:
		await _pad(JOY_BUTTON_DPAD_DOWN)
		check(InputPrompts.using_pad(), "a pad button makes the pad the active device")
		check(_focus() == menu.items.get_child(1), "D-pad down: FIND SERVERS (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		check(_focus() == menu.items.get_child(menu.items.get_child_count() - 1), "B on the menu goes to QUIT (%s)" % _focus_name())
		check(get_tree().current_scene == menu, "B does not quit")
		# the safety net: nothing focused, the D-pad gives the focus back
		_focus().release_focus()
		await _pad(JOY_BUTTON_DPAD_DOWN)
		check(_focus() == menu.items.get_child(0), "safety net: the D-pad with no focus focuses NEW RACE (%s)" % _focus_name())
		# the now-playing strip is never a D-pad stop
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "menu")
		check(menu.items.is_ancestor_of(_focus()), "D-pad right stays in the menu entries (%s)" % _focus_name())

	func _open_item(menu: Node, text: String) -> void:
		_menu_item(menu, text).grab_focus()
		await _pad(JOY_BUTTON_A)
		await _frames(3)

	# ------------------------------------------------------------ options
	func _options(menu: Node) -> void:
		await _open_item(menu, "OPTIONS")
		var o := menu.dialog as OptionsPanel
		check(o != null, "A on OPTIONS opens it")
		if o == null:
			return
		check(_focus() == o.tabs, "Options: the tab bar has the focus (%s)" % _focus_name())
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(o.tabs.current_tab == 1 and o.pages[1].visible, "RB: VIDEO")
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check(o.tabs.current_tab == 4 and o.pad.visible, "LB from AUDIO wraps to CONTROLLER (%d)" % o.tabs.current_tab)
		check(o.prompt_bar.get_child_count() == 4, "CONTROLLER hints: CHANGE, CLEAR, BACK, TABS (%d)" % o.prompt_bar.get_child_count())
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check(o.tabs.current_tab == 3 and o.keys.visible, "LB again: KEYBOARD & MOUSE (%d)" % o.tabs.current_tab)
		check(o.prompt_bar.get_child_count() == 4, "KEYBOARD & MOUSE hints: CHANGE, CLEAR, BACK, TABS (%d)" % o.prompt_bar.get_child_count())
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		# a slider on VIDEO... no: on AUDIO, focus inside a page then LB/RB: the tab bar takes it
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(o.tabs.current_tab == 0, "RB from CONTROLLER wraps to AUDIO (%d)" % o.tabs.current_tab)
		await _move(JOY_BUTTON_DPAD_DOWN, 1, "audio")
		check(_focus() is HSlider, "D-pad down from the tabs: the master volume slider (%s)" % _focus_name())
		var s := _focus() as HSlider
		var v0 := s.value if s else 0.0
		var up := v0 < s.max_value if s else true
		await _pad(JOY_BUTTON_DPAD_RIGHT if up else JOY_BUTTON_DPAD_LEFT)
		check(s and s.value != v0, "the D-pad moves the slider (%s -> %s)" % [v0, s.value if s else 0.0])
		await _pad(JOY_BUTTON_DPAD_LEFT if up else JOY_BUTTON_DPAD_RIGHT)
		check(s and is_equal_approx(s.value, v0), "and back")
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(_focus() == o.tabs, "RB with the focus on a page: the tab bar takes it (%s)" % _focus_name())
		# VIDEO: down through every row and back up, the focus never drops
		await _move(JOY_BUTTON_DPAD_DOWN, 5, "video")
		check(o.pages[1].is_ancestor_of(_focus()) or o.buttons.is_ancestor_of(_focus()), "video: the D-pad stays in the dialog (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_LEFT, 3, "video left")
		check(o.is_ancestor_of(_focus()), "the focus never leaves the dialog for the menu behind it (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_UP, 8, "video up")
		# the safety net inside a dialog: the focused page hidden from code
		o.tabs.grab_focus()
		await _move(JOY_BUTTON_DPAD_DOWN, 1, "video")
		o._show_tab(0)
		await _frames()
		await _pad(JOY_BUTTON_DPAD_DOWN)
		check(_focus() != null and o.is_ancestor_of(_focus()), "safety net in a dialog (%s)" % _focus_name())
		o.tabs.current_tab = OptionsPanel.KEYS_TAB
		await _frames()
		await _keys(o)
		o.tabs.current_tab = OptionsPanel.PAD_TAB
		await _frames()
		await _pad_tab(o)
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(not is_instance_valid(o) or o.is_queued_for_deletion(), "B closes Options")
		check(_focus() == _menu_item(menu, "OPTIONS"), "the focus is back on OPTIONS (%s)" % _focus_name())

	## Picks item `want` of a dropdown with the pad alone: A opens it, the D-pad moves to the item,
	## A picks it.
	func _pick(dd: OptionButton, want: int, where: String) -> void:
		dd.grab_focus()
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		var pop := dd.get_popup()
		check(pop.visible, "%s: A opens the dropdown" % where)
		for i in dd.item_count + 1:
			if pop.get_focused_item() == want:
				break
			await _pad(JOY_BUTTON_DPAD_DOWN)
		check(pop.get_focused_item() == want, "%s: the D-pad reaches %s (%d)" % [where, dd.get_item_text(want), pop.get_focused_item()])
		await _pad(JOY_BUTTON_A)
		await _frames(3)

	func _selected(dd: OptionButton) -> String:
		return dd.get_item_text(dd.selected) if dd.selected >= 0 else ""

	# ------------------------------------------------------------ OPTIONS > KEYBOARD & MOUSE
	func _keys(o: OptionsPanel) -> void:
		var page := o.keys
		var K := InputBindings.KEY
		o.tabs.grab_focus()
		await _move(JOY_BUTTON_DPAD_DOWN, 1, "keys")
		check(_focus() == page.slot_button("accelerate", 0), "KEYBOARD & MOUSE: D-pad down from the tabs: Accelerate's first key (%s)" % _focus_name())
		# a key slot: A listens, a key binds it
		await _pad(JOY_BUTTON_A)
		check(InputPrompts.is_listening(), "A on a slot listens")
		check(o._hint.visible and o._hint.prompt.contains("Press a key"), "the foot says what to press: %s" % o._hint.prompt)
		check(page.keyboard.pulse_spec == InputBindings.key_spec(KEY_W), "the drawn keyboard pulses W while its slot listens (%s)" % page.keyboard.pulse_spec)
		await _wait(0.2)
		await _key(KEY_K)
		check(InputBindings.get_slot("accelerate", K, 0) == InputBindings.key_spec(KEY_K), "K bound to Accelerate")
		check(is_instance_valid(o) and not o.is_queued_for_deletion(), "the dialog stays open")
		check(_focus() == page.slot_button("accelerate", 0), "the focus stays on the slot (%s)" % _focus_name())
		check(page.keyboard.key_rect(InputBindings.key_spec(KEY_K)).has_area() and page.keyboard._lit.get(InputBindings.key_spec(KEY_K), -1) == 0,
			"the drawn keyboard lights K as action 1")
		check(InputBindings.preset_of(K) == "custom" and _selected(page.layout_dd) == "CUSTOM", "LAYOUT: CUSTOM (%s)" % _selected(page.layout_dd))
		await _pad(JOY_BUTTON_DPAD_DOWN)
		check(page.keyboard.highlight_action == "brake", "the focused row's keys are the highlighted ones (%s)" % page.keyboard.highlight_action)
		# X clears a key slot; the last key of a needed action is refused
		page.slot_button("brake", 1).grab_focus()
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("brake", K, 1) == "", "X clears a key slot")
		page.slot_button("brake", 0).grab_focus()
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("brake", K, 0) != "" and o._hint.prompt.contains("needs at least one key"),
			"the last key of Brake stays, and the foot says why: %s" % o._hint.prompt)
		# the locked slot (Esc) only explains
		page.slot_button("pause", 0).grab_focus()
		await _pad(JOY_BUTTON_A)
		check(not InputPrompts.is_listening() and o._hint.prompt.contains("can't be changed"), "Esc's slot is locked: %s" % o._hint.prompt)
		# right of a row's last slot: LAYOUT, then RESET KEYS
		page.slot_button("steer_left", InputBindings.KEY_SLOTS - 1).grab_focus()
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "keys right")
		check(_focus() == page.layout_dd, "right of a row's last slot: LAYOUT (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "keys right")
		check(_focus() == page.reset_button, "and right again: RESET KEYS (%s)" % _focus_name())
		# a layout over CUSTOM asks first; REPLACE puts it in
		await _pick(page.layout_dd, 1, "keys LAYOUT")
		var box := _top_dialog()
		check(box is MessageBox and _focus() == (box as MessageBox).cancel_button, "over CUSTOM the layout asks, CANCEL focused (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "layout box")
		check(box is MessageBox and _focus() == (box as MessageBox).ok_button, "D-pad right: REPLACE (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		check(InputBindings.preset_of(K) == "arrows" and _selected(page.layout_dd) == "ARROWS",
			"A on REPLACE: the ARROWS layout (%s, %s)" % [InputBindings.preset_of(K), _selected(page.layout_dd)])
		check(InputBindings.get_slot("accelerate", K, 0) == InputBindings.key_spec(KEY_UP), "ARROWS: Up accelerates")
		# from one layout to another: no question
		await _pick(page.layout_dd, 0, "keys LAYOUT")
		check(_top_dialog() == o and InputBindings.preset_of(K) == "wasd", "back to WASD without a question (%s)" % InputBindings.preset_of(K))
		check(_focus() == page.layout_dd, "the focus is on LAYOUT (%s)" % _focus_name())
		# RESET KEYS asks, CANCEL focused; B answers no
		InputBindings.set_slot("accelerate", K, 0, InputBindings.key_spec(KEY_K))
		page.reset_button.grab_focus()
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		box = _top_dialog()
		check(box is MessageBox and _focus() == (box as MessageBox).cancel_button, "RESET asks, CANCEL focused (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(InputBindings.get_slot("accelerate", K, 0) == InputBindings.key_spec(KEY_K), "B on the question resets nothing")
		check(_focus() == page.reset_button, "the focus is back on RESET (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		box = _top_dialog()
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "reset box")
		check(box is MessageBox and _focus() == (box as MessageBox).ok_button, "D-pad right: the box's RESET (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		check(InputBindings.get_slot("accelerate", K, 0) == InputBindings.key_spec(KEY_W) and Game.settings["bindings"].is_empty(),
			"RESET KEYS puts the keys back (%s, focus %s)" % [Game.settings["bindings"], _focus_name()])
		check(_focus() != null and o.is_ancestor_of(_focus()), "the focus is in Options after the reset (%s)" % _focus_name())

	# ------------------------------------------------------------ OPTIONS > CONTROLLER
	func _rows(page: PadPage, side: int) -> Array:
		return page.diagram.rows().filter(func(r): return (r as ControllerDiagram.Row).side == side)

	func _pad_tab(o: OptionsPanel) -> void:
		var page := o.pad
		var P := InputBindings.PAD
		o.tabs.grab_focus()
		await _move(JOY_BUTTON_DPAD_DOWN, 1, "controller")
		check(_focus() != null and _focus() == page.diagram.first_row(), "CONTROLLER: D-pad down from the tabs: the first label (%s)" % _focus_name())
		check(page.diagram.shown_style() == InputPrompts.pad_style(), "the picture follows BUTTON PROMPTS / the pad (%s)" % page.diagram.shown_style())
		# down the left column, across, down the right one: always on a label, always in the dialog
		var left := _rows(page, -1)
		var right := _rows(page, 1)
		var walked := true
		for i in range(1, left.size()):
			await _pad(JOY_BUTTON_DPAD_DOWN)
			walked = walked and _focus() == left[i]
		check(walked and left.size() > 3, "D-pad down walks the left column's labels (%d, %s)" % [left.size(), _focus_name()])
		await _pad(JOY_BUTTON_DPAD_RIGHT)
		check(_focus() in right, "D-pad right: across to the right column (%s)" % _focus_name())
		(right[0] as Control).grab_focus()
		var on_labels := true
		for i in range(1, right.size()):
			await _pad(JOY_BUTTON_DPAD_DOWN)
			on_labels = on_labels and _focus() == right[i]
		check(on_labels, "D-pad down walks the right column's labels (%d, %s)" % [right.size(), _focus_name()])
		await _move(JOY_BUTTON_DPAD_DOWN, 1, "right column down")
		check(page.extras.is_ancestor_of(_focus()), "down from the last label: the extras under the picture (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_UP, 1, "extras up")
		check(_focus() in page.diagram.rows(), "up from the extras: a label (%s)" % _focus_name())
		(right[0] as Control).grab_focus()
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "controller right")
		check(_focus() in page._side_controls(), "D-pad right from a right-column label: the side column (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_LEFT, 1, "side left")
		check(_focus() in page.diagram.rows(), "and left: back to a label (%s)" % _focus_name())
		# a layout over a layout: no question
		await _pick(page.layout_dd, 1, "pad LAYOUT")
		check(_top_dialog() == o and InputBindings.preset_of(P) == "triggers" and _selected(page.layout_dd) == "TRIGGERS",
			"LAYOUT: TRIGGERS, no question (%s)" % InputBindings.preset_of(P))
		var acc = page.diagram.row_for("accelerate", 0)
		check(acc != null and acc.control == "rt", "TRIGGERS: Accelerate's label is on RT (%s)" % (acc.control if acc else "none"))
		await _pick(page.layout_dd, 0, "pad LAYOUT")
		check(InputBindings.preset_of(P) == "standard", "back to STANDARD (%s)" % InputBindings.preset_of(P))
		# rebind through a label: look behind to X, which brake had (they swap)
		var lb = page.diagram.row_for("look_back", 0)
		lb.grab_focus()
		await _pad(JOY_BUTTON_A)
		check(InputPrompts.is_listening() and lb.text == "PRESS...", "A on a label listens (%s)" % lb.text)
		check(o._hint.prompt.contains("Press a button"), "the foot says what to press: %s" % o._hint.prompt)
		await _wait(0.2)
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("look_back", P, 0) == "b2", "X bound to Look behind")
		check(page.diagram.row_for("look_back", 0) != null and page.diagram.row_for("look_back", 0).control == "face_w",
			"its label moved to the left face button")
		check(InputBindings.get_slot("brake", P, 0) == "b3", "Brake took Y")
		check(_focus() == page.diagram.row_for("look_back", 0), "the focus is on Look behind's label (%s)" % _focus_name())
		check(o._hint.prompt.contains("moved from BRAKE / REVERSE"), "the swap is told: %s" % o._hint.prompt)
		check(InputBindings.preset_of(P) == "custom" and _selected(page.layout_dd) == "CUSTOM", "LAYOUT: CUSTOM (%s)" % _selected(page.layout_dd))
		# B binds in a listening slot (it does not close the dialog)
		await _pad(JOY_BUTTON_A)
		await _wait(0.2)
		await _pad(JOY_BUTTON_B)
		check(is_instance_valid(o) and not o.is_queued_for_deletion(), "B while listening does not close the dialog")
		check(InputBindings.get_slot("look_back", P, 0) == "b1", "B bound while listening")
		# Start cancels (and does not close the dialog either)
		await _pad(JOY_BUTTON_A)
		await _wait(0.2)
		await _pad(JOY_BUTTON_START)
		check(not InputPrompts.is_listening() and is_instance_valid(o) and not o.is_queued_for_deletion(), "Start cancels, the dialog stays")
		check(InputBindings.get_slot("look_back", P, 0) == "b1", "a cancel changes nothing")
		# X clears a label: its action's ADD chip takes the focus; A on the chip listens
		page.diagram.row_for("look_back", 0).grab_focus()
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("look_back", P, 0) == "" and page.diagram.row_for("look_back", 0) == null, "X clears the slot")
		check(page.chip_for("look_back") != null and _focus() == page.chip_for("look_back"), "the focus goes to its ADD chip (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		check(InputPrompts.is_listening() and page.chip_for("look_back") != null and page.chip_for("look_back").text == "PRESS...",
			"A on the chip listens")
		await _wait(0.2)
		await _pad(JOY_BUTTON_Y)
		check(InputBindings.get_slot("look_back", P, 0) == "b3" and _focus() == page.diagram.row_for("look_back", 0),
			"Y from the chip: Look behind's label is back and focused (%s)" % _focus_name())
		# the last pad binding of a needed action stays
		page.diagram.row_for("accelerate", 0).grab_focus()
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("accelerate", P, 0) == "", "X clears Accelerate's first pad slot")
		page.diagram.row_for("accelerate", 1).grab_focus()
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("accelerate", P, 1) != "", "the last pad binding of Accelerate stays")
		check(o._hint.prompt.contains("needs at least one pad button"), "and the foot says why: %s" % o._hint.prompt)
		# the locked Start label only explains
		page.diagram.row_for("pause", 0).grab_focus()
		await _pad(JOY_BUTTON_A)
		check(not InputPrompts.is_listening() and o._hint.prompt.contains("can't be changed"), "Start's label is locked: %s" % o._hint.prompt)
		# the settings column: vibration buzzes the pad
		var vib := page.vib.get_child(0) as HSlider
		vib.grab_focus()
		InputPrompts.stop_rumble()
		await _pad(JOY_BUTTON_DPAD_LEFT)
		check(InputPrompts.rumble_now() != Vector3.ZERO or float(Game.settings["vibration"]) == 0.0, "a vibration change buzzes the pad")
		InputPrompts.stop_rumble()
		# a held D-pad keeps stepping a slider
		var dz := page.dz.get_child(0) as HSlider
		dz.grab_focus()
		dz.value = dz.min_value
		await _hold(JOY_BUTTON_DPAD_RIGHT, 1.0)
		check(dz.value >= dz.min_value + 3 * dz.step, "holding the D-pad repeats the slider's step (%s)" % dz.value)
		check(is_equal_approx(float(Game.settings["stick_deadzone"]), dz.value / 100.0), "the dead zone follows the slider")
		await _move(JOY_BUTTON_DPAD_DOWN, 4, "controller settings")
		check(page._side.is_ancestor_of(_focus()) or o.buttons.is_ancestor_of(_focus()), "settings column reachable (%s)" % _focus_name())
		# the picture: another family, the detected one untouched
		var det := InputPrompts.pad_style()
		page.picture_dd.select(5)
		page.picture_dd.item_selected.emit(5)
		await _frames()
		check(page.diagram.shown_style() == "ps5" and InputPrompts.pad_style() == det,
			"CONTROLLER PICTURE: PlayStation 5 drawn, the prompts still %s (%s)" % [det, page.diagram.shown_style()])
		page.picture_dd.select(0)
		page.picture_dd.item_selected.emit(0)
		await _frames()
		# RESET CONTROLLER asks, CANCEL focused; RESET puts STANDARD back
		page.reset_button.grab_focus()
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		var box := _top_dialog()
		check(box is MessageBox and _focus() == (box as MessageBox).cancel_button, "RESET CONTROLLER asks, CANCEL focused (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(InputBindings.preset_of(P) == "custom" and _focus() == page.reset_button, "B on the question resets nothing (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "reset box")
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		check(InputBindings.preset_of(P) == "standard" and Game.settings["bindings"].is_empty() and _selected(page.layout_dd) == "STANDARD",
			"RESET CONTROLLER: STANDARD again (%s)" % [Game.settings["bindings"]])
		check(_focus() != null and o.is_ancestor_of(_focus()), "the focus is in Options after the reset (%s)" % _focus_name())

	## The styles the InputGlyphs under `n` draw in, each once.
	func _glyph_styles(n: Node) -> Array:
		var out := []
		for g in n.find_children("*", "InputGlyph", true, false):
			if not (g as InputGlyph).style in out:
				out.append((g as InputGlyph).style)
		return out

	func _top_dialog() -> Dialog:
		var s := get_tree().get_nodes_in_group(InputPrompts.SCREEN_GROUP)
		for i in range(s.size() - 1, -1, -1):
			if s[i] is Dialog and (s[i] as Dialog).is_visible_in_tree() and not s[i].is_queued_for_deletion():
				return s[i]
		return null

	# ------------------------------------------------------------ how to play
	func _how_to_play(menu: Node) -> void:
		await _open_item(menu, "HOW TO PLAY")
		var h := menu.dialog as HowToPlay
		check(h != null, "A on HOW TO PLAY opens it")
		if h == null:
			return
		check(_focus() == h.next_b, "How to Play: NEXT has the focus (%s)" % _focus_name())
		var glyphs := h.pages[0].find_children("*", "InputGlyph", true, false).size()
		check(glyphs >= 20, "the CONTROLS page shows the bindings as icons (%d)" % glyphs)
		var head := ""
		for l in h.pages[0].find_children("*", "Label", true, false):
			if (l as Label).text.begins_with("GAMEPAD"):
				head = (l as Label).text
		check(head.contains("XBOX"), "the pad column names the family: %s" % head)
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(h.tabs.current_tab == 1, "RB: DRIVING")
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check(h.tabs.current_tab == 0 and _focus() == h.next_b, "LB: back to CONTROLS, focus kept")
		for i in h.pages.size() - 1:
			await _pad(JOY_BUTTON_A)
		check(h.tabs.current_tab == h.pages.size() - 1, "A on NEXT to the last page (%d)" % h.tabs.current_tab)
		check(_focus() == h.close_b, "NEXT went dead: the focus moved to CLOSE (%s)" % _focus_name())
		check(h.next_b.focus_mode == Control.FOCUS_NONE, "a dead NEXT is skipped by the D-pad")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(_focus() == _menu_item(menu, "HOW TO PLAY"), "B closes How to Play, focus back (%s)" % _focus_name())

	# ------------------------------------------------------------ soundtrack
	func _soundtrack(menu: Node) -> void:
		await _open_item(menu, "SOUNDTRACK")
		var d: Dialog = menu.dialog
		check(d is SoundtrackPanel and d.is_ancestor_of(_focus()), "Soundtrack: a track row has the focus (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_DOWN, 3, "soundtrack")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(_focus() == _menu_item(menu, "SOUNDTRACK"), "B closes the Soundtrack (%s)" % _focus_name())

	# ------------------------------------------------------------ track editor's home
	func _editor_home(menu: Node) -> void:
		await _open_item(menu, "TRACK EDITOR")
		await _frames(3)
		var home: EditorHome = menu.home
		check(home != null and home.is_visible_in_tree(), "A on TRACK EDITOR opens the editor's home")
		if home == null:
			return
		# a leftover autosave asks RECOVER YOUR TRACK? first: B is "not now"
		if home._dialog_open():
			await _pad(JOY_BUTTON_B)
			await _frames(3)
		check(not menu.items.is_visible_in_tree(), "the menu hides under the home")
		check(_focus() != null and home.is_ancestor_of(_focus()), "editor home: the focus is in it (%s)" % _focus_name())
		var t0 := home.tab
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(home.tab == EditorHome.TABS[posmod(EditorHome.TABS.find(t0) + 1, 3)], "RB: the next tab (%s)" % home.tab)
		check(_focus() != null and home.is_ancestor_of(_focus()), "RB keeps the focus in the home (%s)" % _focus_name())
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check(home.tab == t0, "LB: back to %s (%s)" % [t0, home.tab])
		for i in 3:
			if home.tab == "templates":
				break
			await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(home.tab == "templates" and home.list.cards.size() == LevelTemplates.IDS.size(), "TEMPLATES: a card per template (%d)" % home.list.cards.size())
		check(_focus() in home.list.cards, "TEMPLATES: a card has the focus (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_RIGHT, 6, "home cards")
		check(_focus() in home.list.cards, "D-pad right stops at the row's end (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_DOWN, 3, "home")
		check(_focus() is Button and home.button_row.is_ancestor_of(_focus()), "down: the button row (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_RIGHT, 12, "home buttons")
		check(_focus() is Button and home.button_row.is_ancestor_of(_focus()), "the button row walks along itself (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_UP, 1, "home")
		check(_focus() == home.list.current_card(), "up from the buttons: the selected card (%s)" % _focus_name())
		check(get_tree().current_scene == menu, "nothing opened the editor")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(menu.home == null and menu.items.is_visible_in_tree(), "B closes the home")
		check(_focus() == _menu_item(menu, "TRACK EDITOR"), "B: TRACK EDITOR focused (%s)" % _focus_name())

	# ------------------------------------------------------------ find servers
	func _browser(menu: Node) -> void:
		await _open_item(menu, "FIND SERVERS")
		var b := menu.dialog as ServerBrowser
		check(b != null and _focus() == b.tabs, "Find servers: the tab bar has the focus (%s)" % _focus_name())
		if b == null:
			return
		var t0 := b.tabs.current_tab
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check(b.tabs.current_tab == posmod(t0 - 1, 4), "LB switches the list")
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(b.tabs.current_tab == t0, "RB back")
		await _move(JOY_BUTTON_DPAD_DOWN, 2, "browser")
		# the TRACK column with a server on a custom track (a fake reply, as ServerFinder gives it)
		b._on_found(_fake_server())
		await _frames(2)
		var row := b.list.get_root().get_child(b.list.get_root().get_child_count() - 1) if b.list.get_root() else null
		check(row != null and row.get_text(2) == "Canal Run  (custom)", "browser: the TRACK column names the custom track (%s)" % (row.get_text(2) if row else "?"))
		if row:
			b.list.grab_focus()
			b.list.set_selected(row, 1)
			await _frames(2)
			check(b.status.text.contains("CUSTOM TRACK: Canal Run  by Sasha"), "browser: the selected row's custom track line (%s)" % b.status.text.replace("
", " / "))
			await _move(JOY_BUTTON_DPAD_UP, 1, "browser list")
		# the password box: B cancels it, the focus comes back to the browser
		var was := _focus()
		b._ask_and_join("127.0.0.1", 27999, true)
		await _frames(3)
		var box := _top_dialog() as MessageBox
		check(box != null and _focus() == box.field, "the password box focuses its field (%s)" % _focus_name())
		check(box != null and box._kb_note.visible, "it says a keyboard is needed")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(_focus() == was, "B closes the password box, focus back in the browser (%s)" % _focus_name())
		# CONNECTING...: B stops connecting
		menu._join("127.0.0.1", 27998, "")
		await _frames(3)
		check(Net.active and _top_dialog() is MessageBox, "connecting box up")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(not Net.active, "B on CONNECTING stops connecting")
		check(_focus() != null and b.is_ancestor_of(_focus()), "and the focus is back in the browser (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(_focus() == _menu_item(menu, "FIND SERVERS"), "B closes Find servers (%s)" % _focus_name())

	## A LAN reply of a server racing a custom track (192.0.2.x: a documentation address, never dialled).
	func _fake_server() -> Dictionary:
		return {"address": "192.0.2.10", "port": 27015, "name": "Canal GP", "map": "Canal Run", "cu": 1,
			"msha": "0123456789abcdef", "mkb": 1400, "mau": "Sasha", "players": 3, "max": 8, "state": "lobby",
			"ping": 42, "compatible": true, "list": ["Gordon", "Alyx", "Barney"]}

	# ------------------------------------------------------------ create server
	func _create(menu: Node) -> void:
		await _open_item(menu, "CREATE SERVER")
		var c := menu.dialog as CreateServer
		check(c != null and _focus() is Button and (_focus() as Button).text == "START SERVER", "Create server: START SERVER focused (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_UP, 6, "create")
		await _move(JOY_BUTTON_DPAD_LEFT, 2, "create")
		check(c and c.is_ancestor_of(_focus()), "create: the focus stays in the dialog (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(_focus() == _menu_item(menu, "CREATE SERVER"), "B closes Create server (%s)" % _focus_name())

	# ------------------------------------------------------------ lobby
	func _lobby(menu: Node) -> void:
		await _open_item(menu, "CREATE SERVER")
		var c := menu.dialog as CreateServer
		if c == null:
			check(false, "Create server for the lobby")
			return
		Game.settings["host_port"] = 27291
		Game.settings["host_upnp"] = false
		Game.settings["host_lan_only"] = true
		c._start()
		await _wait(1.0)
		var lobby: Lobby = menu.lobby
		check(lobby != null and _focus() == lobby.ready_button, "lobby: READY focused (%s)" % _focus_name())
		if lobby == null:
			Net.leave()
			return
		var tc: Label = lobby._track_cells.get(1)
		check(tc != null and tc.is_visible_in_tree() and tc.text in ["✓ OK", "..."], "lobby: the host's TRACK cell (%s)" % (tc.text if tc else "none"))
		check(tc == null or tc.focus_mode == Control.FOCUS_NONE, "the TRACK cell is never a D-pad stop")
		check(lobby.start_button == null or lobby.start_button.disabled == (Net.can_start() != ""), "START RACE follows can_start (%s)" % Net.can_start())
		await _pad(JOY_BUTTON_START)
		check(lobby.ready_button.button_pressed, "Start toggles READY")
		await _pad(JOY_BUTTON_START)
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		var box := _top_dialog() as MessageBox
		check(box != null and _focus() == box.cancel_button, "B in the lobby asks first, CANCEL focused (%s)" % _focus_name())
		check(Net.active, "nothing stopped yet")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(Net.active and _focus() == lobby.ready_button, "B again: still in the lobby, READY focused (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_LEFT, 6, "lobby")
		await _move(JOY_BUTTON_DPAD_UP, 4, "lobby")
		await _move(JOY_BUTTON_DPAD_RIGHT, 6, "lobby")
		await _move(JOY_BUTTON_DPAD_DOWN, 6, "lobby")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "leave box")
		await _pad(JOY_BUTTON_A)
		await _wait(0.5)
		check(not Net.active and menu.lobby == null, "STOP SERVER leaves the lobby")
		check(_focus() == menu.items.get_child(0), "back on the menu, NEW RACE focused (%s)" % _focus_name())

	# ------------------------------------------------------------ NEW RACE > MY TRACKS (TrackBrowser)
	func _track_browser(menu: Node) -> void:
		await _open_item(menu, "NEW RACE")
		var setup: RaceSetup = menu.setup
		check(setup != null and setup.my_card != null and setup.my_card in setup.track_cards, "NEW RACE has the MY TRACKS card")
		if setup == null or setup.my_card == null:
			return
		setup.my_card.grab_focus()
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		var tb: TrackBrowser = setup.browser
		check(tb != null and tb.is_visible_in_tree(), "A on MY TRACKS opens the track browser")
		if tb == null:
			return
		check(_focus() != null and tb.is_ancestor_of(_focus()), "track browser: the focus is in it (%s)" % _focus_name())
		var t0 := tb.tab
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(tb.tab != t0 and tb.tab in TrackBrowser.TABS, "RB: the other tab (%s)" % tb.tab)
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check(tb.tab == t0, "LB: back (%s)" % tb.tab)
		await _move(JOY_BUTTON_DPAD_DOWN, 3, "track browser")
		await _move(JOY_BUTTON_DPAD_RIGHT, 4, "track browser")
		check(_focus() != null and tb.is_ancestor_of(_focus()), "the focus stays in the track browser (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(setup.browser == null or not is_instance_valid(setup.browser) or setup.browser.is_queued_for_deletion(), "B closes the track browser")
		check(_focus() == setup.my_card, "B: back on MY TRACKS (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(menu.setup == null, "B leaves NEW RACE")

	# ------------------------------------------------------------ new race, the race
	func _race(menu: Node) -> void:
		await _open_item(menu, "NEW RACE")
		var setup: RaceSetup = menu.setup
		check(setup != null and _focus() == setup.start_button, "NEW RACE: START RACE focused (%s)" % _focus_name())
		if setup == null:
			return
		await _move(JOY_BUTTON_DPAD_UP, 1, "setup")
		check(_focus() in setup.track_cards, "up from START: the picked track (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_UP, 3, "setup")
		await _move(JOY_BUTTON_DPAD_LEFT, 8, "setup")
		await _move(JOY_BUTTON_DPAD_UP, 3, "setup")
		check(_focus() in setup.cards or _focus() in setup.vehicle_cards, "up into the racer cards (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_RIGHT, 8, "setup")
		check(_focus() in setup.cards or _focus() in setup.vehicle_cards, "right stops at the grid's edge (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(menu.setup == null and _focus() == menu.items.get_child(0), "B leaves NEW RACE (%s)" % _focus_name())
		await _open_item(menu, "NEW RACE")
		await _pad(JOY_BUTTON_START)
		# the race loads (a fresh scene): wait for its intro
		var race: Node = null
		for i in 60:
			await _wait(0.5)
			race = get_tree().current_scene
			if race and race.get("_phase") == "intro":
				break
		check(race != null and race.get("_phase") == "intro", "Start on NEW RACE starts the race (%s)" % (race.get("_phase") if race else "?"))
		if race == null or race.get("hud") == null:
			return
		var hud: Hud = race.hud
		await _frames(2)
		check(hud.skip_hint.visible, "the intro shows the SKIP prompt")
		check(hud.rescue_label.get_parsed_text().contains("STUCK?"), "the rescue hint is a prompt: %s" % hud.rescue_label.get_parsed_text())
		# HOW TO DRIVE over the intro, clear of the HUD's prompts and boxes
		var card: DriveCard = race.drive_card
		check(card != null and card.panel.is_visible_in_tree(), "the intro shows HOW TO DRIVE")
		if card:
			var cr := card.panel.get_global_rect()
			for c in [hud.skip_hint, hud.big, hud.minimap, hud.standings]:
				check(not cr.intersects((c as Control).get_global_rect()), "HOW TO DRIVE %s is clear of %s %s" % [cr, c.name,
					(c as Control).get_global_rect()])
			check(get_viewport().get_visible_rect().encloses(cr), "HOW TO DRIVE is on the screen (%s)" % cr)
			check(card.shown_actions().size() == 7, "HOW TO DRIVE has its 7 rows: %s" % [card.shown_actions()])
			check(_glyph_styles(card.panel) == [InputPrompts.pad_style()], "its icons are the pad's (%s)" % [_glyph_styles(card.panel)])
			await _key(KEY_K)
			check(_glyph_styles(card.panel) == [InputPrompts.KEYBOARD], "a key press: the keys (%s)" % [_glyph_styles(card.panel)])
		# paused in the intro, B (also Use item) resumes without skipping it
		await _pad(JOY_BUTTON_START)
		check(get_tree().paused, "Start pauses the intro")
		check(card == null or not card.panel.is_visible_in_tree(), "the pause hides HOW TO DRIVE")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(not get_tree().paused and race._phase == "intro", "B resumes, the intro goes on (%s)" % race._phase)
		check(card == null or card.panel.is_visible_in_tree(), "and HOW TO DRIVE is back")
		await _pad(JOY_BUTTON_A)
		await _frames(2)
		check(race._phase == "count", "A skips the intro (%s)" % race._phase)
		check(card == null or (is_instance_valid(card) and card.panel.is_visible_in_tree()), "HOW TO DRIVE stays for the countdown")
		var until := Time.get_ticks_msec() + 10000
		while race._phase != "race" and Time.get_ticks_msec() < until:
			await _frames(1)
		check(race._phase == "race" and race.drive_card == null, "GO (%s)" % race._phase)
		await _wait(0.6)
		check(card == null or not is_instance_valid(card), "HOW TO DRIVE is gone 0.6 s after GO")
		var was: bool = Game.settings.get("controls_card", true)
		Game.settings["controls_card"] = false
		check(not DriveCard.wanted(race), "OPTIONS > GAME turns HOW TO DRIVE off")
		Game.settings["controls_card"] = was
		await _pad(JOY_BUTTON_START)
		check(get_tree().paused and _focus() == hud.pause_panel.get_meta("first"), "Start pauses, RESUME focused (%s)" % _focus_name())
		# the controls beside the pause menu: the pad in use, clear of the column and the HUD's boxes
		var cp := hud.controls_panel
		check(cp != null and cp.is_visible_in_tree() and cp.pad_diagram != null and cp.keyboard == null, "the pause menu shows the pad's controls")
		if cp:
			await _frames(2)
			var pr := cp.get_global_rect()
			var boxes: Array[Control] = [hud.pause_panel.get_child(1), hud.minimap, hud.speed_num.get_parent(), hud.time_lbl.get_parent(),
				hud.item_box, hud.pos_num.get_parent(), hud.lap_num.get_parent(), hud.aux_label.get_parent()]
			for c in boxes:
				check(not pr.intersects(c.get_global_rect()), "the controls panel %s is clear of %s %s" % [pr, c.name, c.get_global_rect()])
			check(get_viewport().get_visible_rect().encloses(pr), "the controls panel is on the screen (%s)" % pr)
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "pause right")
		check(_focus() == hud.pause_panel.get_meta("first"), "D-pad right from RESUME stays in the pause column (%s)" % _focus_name())
		await _key(KEY_K)
		check(cp and cp.keyboard != null and cp.pad_diagram == null and cp.is_visible_in_tree(), "a key press: the keyboard's controls")
		if cp and cp.keyboard:
			await _frames(2)
			check(not cp.get_global_rect().intersects(hud.minimap.get_global_rect()) and get_viewport().get_visible_rect().encloses(cp.get_global_rect()),
				"the keyboard's panel %s is clear of the minimap and on the screen" % cp.get_global_rect())
		await _move(JOY_BUTTON_DPAD_DOWN, 2, "pause")
		check(cp == null or cp.pad_diagram != null, "the pad again: the pad's controls")
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		check(hud._options != null and is_instance_valid(hud._options), "OPTIONS from the pause menu")
		check(cp == null or not cp.visible, "OPTIONS hides the controls panel")
		await _move(JOY_BUTTON_DPAD_LEFT, 2, "pause options")
		check(hud._options and hud._options.is_ancestor_of(_focus()), "the focus stays in Options over the pause menu (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(get_tree().paused and _focus() == hud.pause_panel.get_meta("first"), "B closes Options, RESUME focused (%s)" % _focus_name())
		check(cp == null or cp.is_visible_in_tree(), "and the controls panel is back")
		await _pad(JOY_BUTTON_B)
		await _frames(2)
		check(not get_tree().paused and not hud.pause_panel.visible, "B resumes")
		check(cp == null or not cp.is_visible_in_tree(), "the controls panel goes with the pause menu")
		# the pad in use goes away: the race pauses with a note; back: the note says so, still paused
		await _pad(JOY_BUTTON_A)
		InputPrompts._on_joy_connection(1, false)
		await _frames(2)
		check(get_tree().paused and hud._pad_note.visible and hud._pad_note.text.contains("DISCONNECTED"), "a lost pad pauses the race")
		check(cp == null or (cp.pad_diagram != null) == PauseControls.pad_in_use(), "the controls panel follows the device in use")
		InputPrompts._on_joy_connection(1, true)
		await _frames(2)
		check(get_tree().paused and hud._pad_note.text.contains("CONNECTED"), "back: still paused, the note says so")
		await _pad(JOY_BUTTON_B)
		await _frames(2)
		check(not get_tree().paused and not hud._pad_note.visible, "B resumes, the note goes")
		# results: RACE AGAIN focused, the safety net finds it
		hud.show_results(race.karts)
		await _frames(2)
		check(_focus() is Button and (_focus() as Button).text == "RACE AGAIN", "results: RACE AGAIN focused (%s)" % _focus_name())
		_focus().release_focus()
		await _pad(JOY_BUTTON_DPAD_DOWN)
		check(_focus() is Button and (_focus() as Button).text == "RACE AGAIN", "results: safety net (%s)" % _focus_name())
		race.to_menu()
		await _wait(1.5)
		check(get_tree().current_scene.name == "Main", "back to the menu")
