extends Node
## Headless walk through every menu screen with a pad only (synthetic pad events, no window): the
## focus enters each screen and is never lost, B leaves every screen and closes every dialog (and
## the focus goes back where it was), LB / RB switch tabs, OPTIONS > CONTROLS rebinds, swaps,
## clears and cancels, the lobby asks before leaving, and in a race the intro skips on A, B resumes
## from the pause menu and a pad going away pauses with a note. Prints each failure and a total;
## exits 1 on any failure. Restores the settings it changes. Takes about a minute (it loads a race).
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
		await _browser(menu)
		await _create(menu)
		await _lobby(menu)
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
		check(o.tabs.current_tab == 3 and o.controls.visible, "LB from AUDIO wraps to CONTROLS")
		check(o.prompt_bar.get_child_count() == 4, "CONTROLS hints: CHANGE, CLEAR, BACK, TABS (%d)" % o.prompt_bar.get_child_count())
		# a slider on VIDEO... no: on AUDIO, focus inside a page then LB/RB: the tab bar takes it
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
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
		o.tabs.current_tab = 3
		await _frames()
		await _controls(o)
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(not is_instance_valid(o) or o.is_queued_for_deletion(), "B closes Options")
		check(_focus() == _menu_item(menu, "OPTIONS"), "the focus is back on OPTIONS (%s)" % _focus_name())

	func _slot(o: OptionsPanel, act: String, cls: String, i: int) -> Button:
		return o.controls._slots.get("%s|%s|%d" % [act, cls, i])

	func _controls(o: OptionsPanel) -> void:
		var page := o.controls
		o.tabs.grab_focus()
		await _move(JOY_BUTTON_DPAD_DOWN, 1, "controls")
		check(_focus() == _slot(o, "accelerate", "pad", 0), "D-pad down with a pad: Accelerate's first pad slot (%s)" % _focus_name())
		# a key slot: A listens, a key binds it
		_slot(o, "accelerate", "key", 0).grab_focus()
		await _pad(JOY_BUTTON_A)
		check(InputPrompts.is_listening(), "A on a slot listens")
		check(o._hint.visible and o._hint.prompt.contains("Press a key"), "the foot says what to press: %s" % o._hint.prompt)
		await _wait(0.2)
		await _key(KEY_K)
		check(InputBindings.get_slot("accelerate", "key", 0) == InputBindings.key_spec(KEY_K), "K bound to Accelerate")
		check(is_instance_valid(o) and not o.is_queued_for_deletion(), "the dialog stays open")
		check(_focus() == _slot(o, "accelerate", "key", 0), "the focus stays on the slot (%s)" % _focus_name())
		# a pad slot: Y is Look behind's, so the two swap
		_slot(o, "accelerate", "pad", 0).grab_focus()
		await _pad(JOY_BUTTON_A)
		await _wait(0.2)
		await _pad(JOY_BUTTON_Y)
		check(InputBindings.get_slot("accelerate", "pad", 0) == InputBindings.button_spec(JOY_BUTTON_Y), "Y bound to Accelerate")
		check(InputBindings.get_slot("look_back", "pad", 0) == InputBindings.button_spec(JOY_BUTTON_A), "Look behind took A")
		check(o._hint.prompt.contains("moved from LOOK BEHIND"), "the swap is told: %s" % o._hint.prompt)
		# B binds in a listening pad slot (it does not close the dialog)
		await _pad(JOY_BUTTON_A)
		await _wait(0.2)
		await _pad(JOY_BUTTON_B)
		check(is_instance_valid(o) and not o.is_queued_for_deletion(), "B while listening does not close the dialog")
		check(InputBindings.get_slot("accelerate", "pad", 0) == InputBindings.button_spec(JOY_BUTTON_B), "B bound while listening")
		# Start cancels (and does not close the dialog either)
		await _pad(JOY_BUTTON_A)
		await _wait(0.2)
		await _pad(JOY_BUTTON_START)
		check(not InputPrompts.is_listening() and is_instance_valid(o) and not o.is_queued_for_deletion(), "Start cancels, the dialog stays")
		check(InputBindings.get_slot("accelerate", "pad", 0) == InputBindings.button_spec(JOY_BUTTON_B), "a cancel changes nothing")
		# X clears a slot; the last one of a needed action is refused
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("accelerate", "pad", 0) == "", "X clears the slot")
		_slot(o, "accelerate", "pad", 1).grab_focus()
		await _pad(JOY_BUTTON_X)
		check(InputBindings.get_slot("accelerate", "pad", 1) != "", "the last pad binding of Accelerate stays")
		check(o._hint.prompt.contains("needs at least one"), "and the foot says why: %s" % o._hint.prompt)
		# the locked slot (Esc) only explains
		_slot(o, "pause", "key", 0).grab_focus()
		await _pad(JOY_BUTTON_A)
		check(not InputPrompts.is_listening() and o._hint.prompt.contains("can't be changed"), "Esc's slot is locked: %s" % o._hint.prompt)
		# the settings column: vibration buzzes the pad
		var vib := page._vib.get_child(0) as HSlider
		vib.grab_focus()
		InputPrompts.stop_rumble()
		await _pad(JOY_BUTTON_DPAD_LEFT)
		check(InputPrompts.rumble_now() != Vector3.ZERO or float(Game.settings["vibration"]) == 0.0, "a vibration change buzzes the pad")
		InputPrompts.stop_rumble()
		# a held D-pad keeps stepping a slider
		var dz := page._dz.get_child(0) as HSlider
		dz.grab_focus()
		dz.value = dz.min_value
		await _hold(JOY_BUTTON_DPAD_RIGHT, 1.0)
		check(dz.value >= dz.min_value + 3 * dz.step, "holding the D-pad repeats the slider's step (%s)" % dz.value)
		check(is_equal_approx(float(Game.settings["stick_deadzone"]), dz.value / 100.0), "the dead zone follows the slider")
		await _move(JOY_BUTTON_DPAD_DOWN, 4, "controls settings")
		check(page.is_ancestor_of(_focus()) or o.buttons.is_ancestor_of(_focus()), "settings column reachable (%s)" % _focus_name())
		# RESET TO DEFAULTS asks, CANCEL focused; B answers no
		page._reset.grab_focus()
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		var box := _top_dialog()
		check(box is MessageBox and _focus() == (box as MessageBox).cancel_button, "RESET asks, CANCEL focused (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(InputBindings.get_slot("accelerate", "key", 0) == InputBindings.key_spec(KEY_K), "B on the question resets nothing")
		check(_focus() == page._reset, "the focus is back on RESET (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		box = _top_dialog()
		await _move(JOY_BUTTON_DPAD_RIGHT, 1, "reset box")
		check(box is MessageBox and _focus() == (box as MessageBox).ok_button, "D-pad right: the box's RESET (%s)" % _focus_name())
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		check(InputBindings.get_slot("accelerate", "key", 0) == InputBindings.key_spec(KEY_W) and Game.settings["bindings"].is_empty(),
			"RESET puts the controls back (%s, focus %s)" % [Game.settings["bindings"], _focus_name()])
		check(_focus() != null and o.is_ancestor_of(_focus()), "the focus is in Options after the reset (%s)" % _focus_name())

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
		# paused in the intro, B (also Use item) resumes without skipping it
		await _pad(JOY_BUTTON_START)
		check(get_tree().paused, "Start pauses the intro")
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(not get_tree().paused and race._phase == "intro", "B resumes, the intro goes on (%s)" % race._phase)
		await _pad(JOY_BUTTON_A)
		await _frames(2)
		check(race._phase == "count", "A skips the intro (%s)" % race._phase)
		for i in 20:
			await _wait(0.5)
			if race._phase == "race":
				break
		await _pad(JOY_BUTTON_START)
		check(get_tree().paused and _focus() == hud.pause_panel.get_meta("first"), "Start pauses, RESUME focused (%s)" % _focus_name())
		await _move(JOY_BUTTON_DPAD_DOWN, 2, "pause")
		await _pad(JOY_BUTTON_A)
		await _frames(3)
		check(hud._options != null and is_instance_valid(hud._options), "OPTIONS from the pause menu")
		await _move(JOY_BUTTON_DPAD_LEFT, 2, "pause options")
		check(hud._options and hud._options.is_ancestor_of(_focus()), "the focus stays in Options over the pause menu (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(3)
		check(get_tree().paused and _focus() == hud.pause_panel.get_meta("first"), "B closes Options, RESUME focused (%s)" % _focus_name())
		await _pad(JOY_BUTTON_B)
		await _frames(2)
		check(not get_tree().paused and not hud.pause_panel.visible, "B resumes")
		# the pad in use goes away: the race pauses with a note; back: the note says so, still paused
		await _pad(JOY_BUTTON_A)
		InputPrompts._on_joy_connection(1, false)
		await _frames(2)
		check(get_tree().paused and hud._pad_note.visible and hud._pad_note.text.contains("DISCONNECTED"), "a lost pad pauses the race")
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
