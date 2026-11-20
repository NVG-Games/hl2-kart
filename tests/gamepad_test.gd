extends Node
## Headless check of the gamepad layer (InputBindings, InputPrompts, PromptLabel): pads on any
## device id drive the kart, the pad family's icons and names, bindings saved and loaded, reset and
## swapped on a clash, the Nintendo confirm / back swap, prompt text, listening for a new binding,
## rumble, which device is active and a pad going away; the ready-made layouts (presets), the
## controller pictures and their anchors, and the ControllerDiagram / KeyboardDiagram widgets (rows,
## callout layout for every pad style, states, the drawn keyboard); OPTIONS' KEYBOARD & MOUSE and
## CONTROLLER pages, the pause menu's controls panel and HOW TO DRIVE. Prints each failure and a
## total; exits 1 on any failure. Restores the settings it changes.
## usage: godot --headless --path . res://tests/gamepad_test.tscn

const KEEP := ["bindings", "prompt_style", "vibration", "stick_deadzone", "nintendo_swap"]

var failures := 0
var checks := 0
var _saved := {}
var _events: Array = []  # signals heard: [name, args...]
var _redraws := 0  # InputPrompts.prompts_changed heard


func _ready() -> void:
	for k in KEEP:
		_saved[k] = Game.settings[k].duplicate(true) if Game.settings[k] is Dictionary else Game.settings[k]
	Game.settings["bindings"] = {}
	Game.settings["prompt_style"] = "auto"
	Game.settings["vibration"] = 0.5
	Game.settings["stick_deadzone"] = 0.2
	Game.settings["nintendo_swap"] = true
	InputBindings.apply()
	Game.settings_changed.emit()
	InputPrompts.prompts_changed.connect(func(): _redraws += 1)
	InputPrompts.controller_lost.connect(func(): _events.append(["lost"]))
	InputPrompts.controller_back.connect(func(by_pad: bool): _events.append(["back", by_pad]))
	InputPrompts.rebind_captured.connect(func(act: String, cls: String, slot: int, ev: InputEvent, res: Dictionary):
		_events.append(["captured", act, cls, slot, InputBindings.spec_of(ev), res]))
	InputPrompts.rebind_cancelled.connect(func(act: String, cls: String, slot: int):
		_events.append(["cancelled", act, cls, slot]))
	await _run()
	for k in KEEP:
		Game.settings[k] = _saved[k]
	Game.save_settings()
	InputBindings.apply()
	print("gamepad_test: %d checks, failures: %d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _test_any_pad_drives()
	await _test_keyboard_as_before()
	_test_detection()
	_test_icons()
	await _test_device_tracking()
	await _test_twins()
	await _test_save_load_reset()
	await _test_conflicts()
	await _test_nintendo_swap()
	await _test_style_while_keyboard()
	await _test_prompts()
	await _test_listen()
	await _test_rumble()
	await _test_menu_repeat()
	await _test_disconnect()
	_test_presets()
	_test_device_art()
	_test_anchors()
	await _test_controller_diagram()
	await _test_diagram_layouts()
	await _test_keyboard_diagram()
	await _test_pages()


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frame() -> void:
	await get_tree().process_frame


func _button(b: JoyButton, pressed: bool, dev := 1) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = pressed
	e.device = dev
	Input.parse_input_event(e)
	await _frame()


func _axis(axis: JoyAxis, v: float, dev := 1) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	e.device = dev
	Input.parse_input_event(e)
	await _frame()


func _key(code: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	await _frame()


func _mouse_move(px: float) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(px, 0.0)
	e.position = Vector2(400, 300)
	Input.parse_input_event(e)
	await _frame()


## One PlayerController step, as the next physics frame after the last (no pause in between).
func _drive(pc: PlayerController, k: Kart) -> void:
	pc._frame = Engine.get_physics_frames() - 1
	pc.drive(k, 1.0 / 120.0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _pad_events_all_devices() -> bool:
	for act in InputBindings.ACTIONS + ["ui_accept", "ui_cancel", "ui_tab_prev", "ui_tab_next"]:
		for ev in InputMap.action_get_events(act):
			if (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and ev.device != InputBindings.ALL_DEVICES:
				return false
	return true


# ---------------------------------------------------------------- tests
## A pad that is not device 0 drives the kart through PlayerController.
func _test_any_pad_drives() -> void:
	check(_pad_events_all_devices(), "every pad event in the InputMap matches any device (-1)")
	var k := Kart.new()
	var pc := PlayerController.new()
	await _button(JOY_BUTTON_A, true, 1)
	await _axis(JOY_AXIS_LEFT_X, 0.8, 1)
	_drive(pc, k)
	check(k.in_throttle > 0.99, "pad 1's A accelerates (%.2f)" % k.in_throttle)
	check(absf(k.in_steer - 0.75) < 0.01, "pad 1's stick at 0.8 steers right 0.75 with dead zone 0.2 (%.3f)" % k.in_steer)
	await _button(JOY_BUTTON_A, false, 1)
	await _axis(JOY_AXIS_LEFT_X, 0.0, 1)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9, 3)
	await _button(JOY_BUTTON_DPAD_LEFT, true, 2)
	_drive(pc, k)
	check(k.in_throttle > 0.8, "pad 3's right trigger accelerates (%.2f)" % k.in_throttle)
	check(k.in_steer < -0.99, "pad 2's D-pad left steers left (%.2f)" % k.in_steer)
	await _button(JOY_BUTTON_DPAD_LEFT, false, 2)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0, 3)
	await _axis(JOY_AXIS_LEFT_X, 0.1, 4)
	_drive(pc, k)
	check(k.in_throttle == 0.0 and k.in_steer == 0.0, "a stick at 0.1 (inside the dead zone) does nothing")
	Game.settings["stick_deadzone"] = 0.05
	Game.settings_changed.emit()
	await _axis(JOY_AXIS_LEFT_X, 0.1, 4)
	_drive(pc, k)
	check(k.in_steer > 0.0, "with dead zone 0.05 the same stick steers (%.3f)" % k.in_steer)
	Game.settings["stick_deadzone"] = 0.2
	Game.settings_changed.emit()
	await _axis(JOY_AXIS_LEFT_X, 0.0, 4)
	# a button held through a pause fires no item when the race goes on
	await _button(JOY_BUTTON_B, true, 1)
	_drive(pc, k)
	check(k.in_item, "B uses an item")
	pc._frame = Engine.get_physics_frames() - 10  # as if the tree had been paused for 10 physics frames
	pc.drive(k, 1.0 / 120.0)
	check(not k.in_item, "B held through a pause fires nothing")
	await _button(JOY_BUTTON_B, false, 1)
	_drive(pc, k)
	await _button(JOY_BUTTON_B, true, 1)
	_drive(pc, k)
	check(k.in_item, "a fresh press of B uses an item again")
	await _button(JOY_BUTTON_B, false, 1)
	# a wheel or a flight stick plugged in too (InputPrompts.axis_devs names the pads that count):
	# its resting pedal holds nothing down, the pads' sticks and triggers still drive, buttons of any
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, 5)
	_drive(pc, k)
	check(k.in_throttle > 0.99, "with every device counting, device 5's axis 5 accelerates")
	InputPrompts.axis_devs = [1, 3]
	InputBindings.apply()
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, 5)
	_drive(pc, k)
	check(k.in_throttle == 0.0, "left out, the wheel's pedal at +1 holds nothing (%.2f)" % k.in_throttle)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9, 3)
	_drive(pc, k)
	check(k.in_throttle > 0.8, "pad 3's trigger still accelerates (%.2f)" % k.in_throttle)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0, 3)
	await _button(JOY_BUTTON_A, true, 5)
	_drive(pc, k)
	check(k.in_throttle > 0.99, "buttons of any device still count")
	# that joystick used: its axes are added, and the button still held stays held
	InputBindings.add_axis_device(5)
	check(Input.is_action_pressed("accelerate"), "adding a device's axes lets go of nothing")
	await _button(JOY_BUTTON_A, false, 5)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, 5)
	_drive(pc, k)
	check(k.in_throttle > 0.99, "and its trigger drives now (%.2f)" % k.in_throttle)
	InputPrompts.axis_devs = [InputBindings.ALL_DEVICES]
	InputBindings.apply()
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0, 5)
	check(_pad_events_all_devices(), "back to any device")
	k.free()


## The keyboard drives as it did before pads were supported: Enter, E and Ctrl all use an item.
func _test_keyboard_as_before() -> void:
	check(InputBindings.slots("use_item", "key") == ["k%d" % KEY_E, "k%d" % KEY_CTRL, "k%d" % KEY_ENTER],
		"Use item has E, Ctrl and Enter: %s" % [InputBindings.slots("use_item", "key")])
	check(_key_is("use_item", KEY_ENTER) and _key_is("use_item", KEY_E) and _key_is("use_item", KEY_CTRL), "Enter uses an item")
	check(InputBindings.slot_count("drift", "key") == 3 and InputBindings.slot_count("drift", "pad") == 2,
		"three keyboard slots, two pad slots")
	var k := Kart.new()
	var pc := PlayerController.new()
	await _key(KEY_ENTER)
	_drive(pc, k)
	check(k.in_item, "Enter fires the item in the kart")
	await _key(KEY_ENTER, false)
	_drive(pc, k)
	k.free()


func _test_detection() -> void:
	var cases := [
		["Xbox Series X Controller", "", 0x045E, 0x0B13, true, true, "xbox"],
		["Xbox 360 Controller", "", 0x045E, 0x028E, true, true, "xbox360"],
		["PS4 Controller", "", 0x054C, 0x09CC, true, false, "ps4"],
		["DualSense Wireless Controller", "", 0x054C, 0x0CE6, true, false, "ps5"],
		["DualSense Edge Wireless Controller", "", 0x054C, 0x0DF2, true, false, "ps5"],
		["PS3 Controller", "", 0x054C, 0x0268, true, false, "ps3"],
		["Nintendo Switch Pro Controller", "", 0x057E, 0x2009, true, false, "switch"],
		["Nintendo Switch Joy-Con (L/R)", "", 0x057E, 0x200E, true, false, "switch"],
		["Steam Deck", "", 0x28DE, 0x1205, true, false, "steamdeck"],
		["Steam Virtual Gamepad", "", 0x28DE, 0x11FF, true, false, "xbox"],
		["HORI Wireless Switch Pad", "", 0x0F0D, 0x00F6, true, false, "switch"],
		["Wireless Controller", "DUALSHOCK 4", 0x146B, 0x0D01, true, false, "ps4"],
		["Controller (XBOX 360 For Windows)", "", 0, 0, true, true, "xbox360"],
		["8BitDo Pro 2", "", 0x2DC8, 0x6003, true, false, "xbox"],
		["Some Pad", "", 0x1234, 0x0001, true, true, "xbox"],
		["Logitech G29 Driving Force Racing Wheel", "", 0x046D, 0xC24F, false, false, "generic"],
	]
	for c in cases:
		var got := InputPrompts.style_for(c[0], c[1], c[2], c[3], c[4], c[5])
		check(got == c[6], "%s (%04X:%04X) is %s, not %s" % [c[0], c[2], c[3], c[6], got])


func _test_icons() -> void:
	var south := _ev_button(JOY_BUTTON_A)
	var east := _ev_button(JOY_BUTTON_B)
	var west := _ev_button(JOY_BUTTON_X)
	var north := _ev_button(JOY_BUTTON_Y)
	var back := _ev_button(JOY_BUTTON_BACK)
	var start := _ev_button(JOY_BUTTON_START)
	var table := {
		"xbox": [["xbox_button_a", "A"], ["xbox_button_b", "B"], ["xbox_button_x", "X"], ["xbox_button_y", "Y"],
			["xbox_button_view", "VIEW"], ["xbox_button_menu", "MENU"]],
		# (Back / Start Kenney draws as unreadable capsules: their names on keycaps)
		"xbox360": [["xbox_button_a", "A"], ["xbox_button_b", "B"], ["xbox_button_x", "X"], ["xbox_button_y", "Y"],
			["", "BACK"], ["", "START"]],
		"ps3": [["playstation_button_cross", "CROSS"], ["playstation_button_circle", "CIRCLE"],
			["playstation_button_square", "SQUARE"], ["playstation_button_triangle", "TRIANGLE"],
			["", "SELECT"], ["", "START"]],
		"ps4": [["playstation_button_cross", "CROSS"], ["playstation_button_circle", "CIRCLE"],
			["playstation_button_square", "SQUARE"], ["playstation_button_triangle", "TRIANGLE"],
			["", "SHARE"], ["", "OPTIONS"]],
		"ps5": [["playstation_button_cross", "CROSS"], ["playstation_button_circle", "CIRCLE"],
			["playstation_button_square", "SQUARE"], ["playstation_button_triangle", "TRIANGLE"],
			["", "CREATE"], ["", "OPTIONS"]],
		# Nintendo prints B at the bottom, A on the right, Y on the left, X on top
		"switch": [["switch_button_b", "B"], ["switch_button_a", "A"], ["switch_button_y", "Y"], ["switch_button_x", "X"],
			["switch_button_minus", "MINUS"], ["switch_button_plus", "PLUS"]],
		"steamdeck": [["steamdeck_button_a", "A"], ["steamdeck_button_b", "B"], ["steamdeck_button_x", "X"],
			["steamdeck_button_y", "Y"], ["", "VIEW"], ["", "MENU"]],
		"generic": [["switch_buttons_down", "BUTTON 1"], ["switch_buttons_right", "BUTTON 2"],
			["switch_buttons_left", "BUTTON 3"], ["switch_buttons_up", "BUTTON 4"], ["", "SELECT"], ["", "START"]],
	}
	var evs := [south, east, west, north, back, start]
	for st in table:
		for i in evs.size():
			var want: Array = table[st][i]
			var got_icon := InputPrompts.icon_name(evs[i], st)
			var got_text := InputPrompts.event_text(evs[i], st)
			check(got_icon == want[0] and got_text == want[1], "%s button %d: %s / %s, not %s / %s" % [st,
				(evs[i] as InputEventJoypadButton).button_index, want[0], want[1], got_icon, got_text])
	check(InputPrompts.icon_name(_ev_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), "ps5") == "playstation_trigger_r2", "ps5 RT is R2")
	check(InputPrompts.icon_name(_ev_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), "switch") == "switch_button_zl", "switch LT is ZL")
	check(InputPrompts.icon_name(_ev_axis(JOY_AXIS_LEFT_X, -1.0), "xbox") == "xbox_stick_l_left", "xbox stick left")
	# the Elite paddles and the numpad's digits show keycaps (a thin sliver, a top-row digit's twin)
	check(InputPrompts.icon_name(_ev_button(JOY_BUTTON_PADDLE1), "xbox") == "" and InputPrompts.spec_text("b16", "xbox") == "P1",
		"an Elite paddle is a P1 keycap")
	var kp8 := InputEventKey.new()
	kp8.physical_keycode = KEY_KP_8
	check(InputPrompts.icon_name(kp8, "xbox") == "" and InputPrompts.event_text(kp8, "xbox") == "NUM 8", "the numpad's 8 is NUM 8")
	# one icon for a stick's or the D-pad's two ways (HOW TO DRIVE's STEER)
	for st in InputPrompts.PAD_STYLES:
		for pair in [["a0-", "a0+"], ["a2-", "a2+"], ["b13", "b14"]]:
			var stem := InputPrompts.pair_stem(pair[0], pair[1], st)
			check(stem != "" and FileAccess.file_exists(InputPrompts.icon_path(stem)), "%s %s: %s" % [st, pair, stem])
	check(InputPrompts.pair_stem("a0-", "b14", "xbox") == "" and InputPrompts.pair_stem("a0+", "a0-", "xbox") == "", "no pair, no icon")
	check(InputPrompts.icon_name(_ev_axis(JOY_AXIS_RIGHT_Y, 1.0), "steamdeck") == "steamdeck_stick_r_down", "deck right stick down")
	check(InputPrompts.event_text(_ev_axis(JOY_AXIS_LEFT_X, 1.0), "xbox") == "LS RIGHT", "stick text")
	check(InputPrompts.icon_name(_ev_button(JOY_BUTTON_DPAD_LEFT), "ps4") == "playstation_dpad_left", "ps4 D-pad left")
	check(InputPrompts.icon_name(_ev_button(JOY_BUTTON_LEFT_SHOULDER), "switch") == "switch_button_l", "switch LB is L")
	# every icon a binding can show is shipped, and it loads
	var stems := {}
	for st in InputPrompts.PAD_STYLES:
		for bi in JOY_BUTTON_SDL_MAX:
			stems[InputPrompts.icon_name(_ev_button(bi as JoyButton), st)] = true
		for ax in JOY_AXIS_SDL_MAX:
			for v in [-1.0, 1.0]:
				stems[InputPrompts.icon_name(_ev_axis(ax as JoyAxis, v), st)] = true
	var keys: Array = InputPrompts.KEY_ICONS.keys()
	for c in range(KEY_A, KEY_Z + 1) + range(KEY_0, KEY_9 + 1) + range(KEY_F1, KEY_F12 + 1) + range(KEY_KP_0, KEY_KP_9 + 1):
		keys.append(c)
	for c in keys:
		var ke := InputEventKey.new()
		ke.physical_keycode = c
		stems[InputPrompts.icon_name(ke, "xbox")] = true
	for mb in InputPrompts.MOUSE_ICONS:
		var me := InputEventMouseButton.new()
		me.button_index = mb
		stems[InputPrompts.icon_name(me, "xbox")] = true
	stems.erase("")
	var missing := []
	for s in stems:
		if not FileAccess.file_exists(InputPrompts.icon_path(s)):
			missing.append(s)
	check(missing.is_empty(), "icons shipped for every binding (%d), missing: %s" % [stems.size(), missing])
	check(stems.size() >= 150, "the icon tables name %d icons" % stems.size())
	var tex := InputPrompts.icon("xbox_button_a", 48.0)
	check(tex != null and roundi(tex.get_height()) == 48, "an icon loads %d px high" % (tex.get_height() if tex else -1))
	check(InputPrompts.icon("xbox_button_a", 48.0) == tex, "icons are cached")
	check(InputPrompts.icon("no_such_icon", 48.0) == null, "a missing icon is null")
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	check(InputPrompts.icon_name(w, "xbox") == "keyboard_w" and InputPrompts.event_text(w, "xbox") == "W", "key W")
	# keys Kenney draws as a word too small to read show their name on a keycap instead
	for c in [KEY_SHIFT, KEY_CTRL, KEY_SPACE, KEY_ENTER, KEY_ESCAPE, KEY_PAGEUP, KEY_BACKSPACE]:
		var ke := InputEventKey.new()
		ke.physical_keycode = c
		check(InputPrompts.icon_name(ke, "xbox") == "", "%s has no icon (a keycap)" % OS.get_keycode_string(c))
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	check(InputPrompts.event_text(esc, "xbox") == "ESC", "Esc's keycap says ESC")
	var cap := KeycapTexture.of("SHIFT", 21.0)
	check(cap.get_height() == 21 and cap.get_width() > cap.get_height() and KeycapTexture.of("SHIFT", 21.0) == cap,
		"a keycap is the icon's height, as wide as its name, and cached (%dx%d)" % [cap.get_width(), cap.get_height()])
	check(InputPrompts.icon("xbox_dpad_up", 32.0) != null, "a D-pad icon (orange, not Kenney's red) loads")
	# a keyboard key loses Kenney's margin: the key is as high as a keycap's (F5, W, [ and Z read 87 %)
	for stem in ["keyboard_f5", "keyboard_w", "keyboard_bracket_open", "keyboard_z", "keyboard_numpad_plus"]:
		var kt := InputPrompts.icon(stem, 22.0)
		check(kt != null and kt.get_height() == 22 and kt.get_width() < 22, "%s: 22 px high, the key's width (%s)" % [stem,
			kt.get_size() if kt else Vector2.ZERO])
		var gb := InputPrompts.glyph_box(stem)
		var svg := InputPrompts.key_svg(FileAccess.get_file_as_string(InputPrompts.icon_path(stem)), gb)
		var img := Image.new()
		var ok := svg != "" and img.load_svg_from_string(svg, 220.0 * KeycapTexture.KEY_SHARE / (gb.size.y * 64.0)) == OK
		var used := img.get_used_rect() if ok else Rect2i()
		var share := float(used.size.y) / float(img.get_height()) if ok else 0.0
		check(ok and absf(share - KeycapTexture.KEY_SHARE) < 0.02 and used.size.x >= img.get_width() - 2
			and absi(used.position.y - (img.get_height() - used.end.y)) <= 2,
			"%s: the key fills %.2f of the icon's height like a keycap (%.2f), centred, full width (%s in %s)" % [stem, share,
			KeycapTexture.KEY_SHARE, used, img.get_size() if ok else Vector2i.ZERO])
	check(InputPrompts.key_svg("<svg viewBox=\"0 0 10 10\"/>", Rect2(0.1, 0.1, 0.8, 0.8)) == "", "key_svg leaves other SVGs alone")
	check(InputPrompts.icon("xbox_button_a", 22.0).get_width() == 22, "pad icons keep Kenney's square canvas")


func _ev_button(b: JoyButton) -> InputEventJoypadButton:
	return InputBindings.event_of(InputBindings.button_spec(b)) as InputEventJoypadButton


func _ev_axis(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	return InputBindings.event_of(InputBindings.axis_spec(axis, 1 if v > 0.0 else -1)) as InputEventJoypadMotion


## Which device is active: a resting stick or trigger never takes over, a real push does; the
## mouse needs a real move.
func _test_device_tracking() -> void:
	await _key(KEY_W)
	await _key(KEY_W, false)
	check(not InputPrompts.using_pad() and InputPrompts.style() == InputPrompts.KEYBOARD, "a key press: keyboard")
	await _axis(JOY_AXIS_RIGHT_X, -1.0, 7)
	check(not InputPrompts.using_pad(), "an axis first seen far from rest (a wheel's pedal) does not take over")
	await _axis(JOY_AXIS_RIGHT_X, 0.0, 7)
	await _axis(JOY_AXIS_LEFT_X, 0.2, 2)
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.3, 2)
	check(not InputPrompts.using_pad(), "a drifting stick (0.2) or resting trigger (0.3) does not take over")
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.0, 2)
	await _axis(JOY_AXIS_LEFT_X, 0.7, 2)
	check(InputPrompts.using_pad() and InputPrompts.active_pad() == 2 and InputPrompts.style() == "xbox",
		"a stick pushed to 0.7 makes pad 2 active (xbox style for an unknown pad)")
	await _key(KEY_W)
	await _key(KEY_W, false)
	await _axis(JOY_AXIS_LEFT_X, 0.75, 2)
	check(not InputPrompts.using_pad(), "a stick held past the wake point does not take over again")
	await _axis(JOY_AXIS_LEFT_X, 0.0, 2)
	await _button(JOY_BUTTON_A, true, 3)
	await _button(JOY_BUTTON_A, false, 3)
	check(InputPrompts.using_pad() and InputPrompts.active_pad() == 3, "a button press makes pad 3 active")
	await _mouse_move(3.0)
	check(InputPrompts.using_pad(), "a 3 px mouse nudge does not take over")
	await _mouse_move(10.0)
	check(InputPrompts.mouse_active() and InputPrompts.style() == InputPrompts.KEYBOARD, "a 13 px mouse move does")


## One pad that reaches the game as two devices (DS4Windows, Steam Input): the second device's
## echo of a press never takes over, so the prompts do not flicker; that device used on its own
## does, a moment later.
func _test_twins() -> void:
	await _wait(0.15)  # (pad 3 pressed A a moment ago: pad 1's A now would look like its echo)
	await _button(JOY_BUTTON_A, true, 1)
	await _button(JOY_BUTTON_A, false, 1)
	check(InputPrompts.active_pad() == 1, "pad 1 active")
	var n := _redraws
	for i in 3:
		await _twin_press(JOY_BUTTON_X, 1, 9)
		await _twin_press(JOY_BUTTON_Y, 9, 1)
	check(InputPrompts.active_pad() == 1, "the twin's echoes never take over (active %d)" % InputPrompts.active_pad())
	check(_redraws - n <= 2, "the prompts are not redrawn for every echo (%d)" % (_redraws - n))
	# the twin used on its own (no echo from pad 1): it takes over once the echo window is past
	await _button(JOY_BUTTON_B, true, 9)
	await _button(JOY_BUTTON_B, false, 9)
	await _wait(0.15)
	check(InputPrompts.active_pad() == 9, "the other device used on its own takes over (%d)" % InputPrompts.active_pad())
	InputPrompts._on_joy_connection(9, false)
	await _button(JOY_BUTTON_A, true, 1)
	await _button(JOY_BUTTON_A, false, 1)


## The same press from two devices in one frame, `first` reporting first.
func _twin_press(b: JoyButton, first: int, second: int) -> void:
	for down in [true, false]:
		for dev in [first, second]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.pressed = down
			e.device = dev
			Input.parse_input_event(e)
		await _frame()


func _test_save_load_reset() -> void:
	InputBindings.reset()
	var r := InputBindings.set_slot("drift", InputBindings.KEY, 1, InputBindings.key_spec(KEY_Q))
	check(r["ok"] and r["moved_action"] == "", "Q binds to drift's second key slot")
	check(_key_is("drift", KEY_Q) and not _key_is("drift", KEY_SPACE), "the InputMap has Q, not Space, for drift")
	check(Game.settings["bindings"] == {"drift": {"key": ["k%d" % KEY_SHIFT, "k%d" % KEY_Q, ""]}},
		"only the changed class is stored: %s" % Game.settings["bindings"])
	Game.save_settings()
	Game.settings["bindings"] = {}
	InputBindings.apply()
	check(_key_is("drift", KEY_SPACE), "cleared: Space drifts again")
	Game._load_settings()
	InputBindings.apply()
	check(_key_is("drift", KEY_Q) and InputBindings.get_slot("drift", "key", 1) == "k%d" % KEY_Q,
		"loaded from the settings file: Q drifts")
	InputBindings.set_slot("look_back", InputBindings.PAD, 1, InputBindings.button_spec(JOY_BUTTON_RIGHT_STICK))
	InputBindings.reset("drift")
	check(_key_is("drift", KEY_SPACE) and Game.settings["bindings"].has("look_back") \
		and not Game.settings["bindings"].has("drift"), "reset of one action")
	InputBindings.reset()
	check(Game.settings["bindings"].is_empty() and InputBindings.get_slot("look_back", "pad", 1) == "", "reset of all")
	# one action reset after a swap takes its key back, and the other action gets its own again
	InputBindings.set_slot("use_item", InputBindings.KEY, 0, InputBindings.key_spec(KEY_W))
	check(InputBindings.get_slot("accelerate", "key", 0) == "k%d" % KEY_E, "W to Use item gives Accelerate E")
	InputBindings.reset("use_item")
	check(InputBindings.get_slot("use_item", "key", 0) == "k%d" % KEY_E and InputBindings.get_slot("accelerate", "key", 0) == "k%d" % KEY_W
		and Game.settings["bindings"].is_empty(), "reset of Use item gives W back to Accelerate: %s" % Game.settings["bindings"])
	# a broken or hand-edited settings file: a key another action has, junk and Esc are dropped
	Game.settings["bindings"] = {"drift": {"key": ["k%d" % KEY_W, "zz", "k%d" % KEY_ESCAPE]}, "pause": {"pad": ["b1", "b2"]}}
	check(InputBindings.slots("drift", "key") == ["", "", ""], "drift keeps neither W (accelerate's) nor junk: %s"
		% [InputBindings.slots("drift", "key")])
	check(InputBindings.slots("pause", "pad")[0] == "b%d" % JOY_BUTTON_START, "pause keeps Start in its locked slot")
	check(InputBindings.slots("pause", "pad")[1] == "", "b2 (X) stays brake's: %s" % [InputBindings.slots("pause", "pad")])
	Game.settings["bindings"] = {}
	InputBindings.apply()


func _key_is(action: String, code: Key) -> bool:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return InputMap.event_is_action(e, action, true)


func _pad_is(action: String, b: JoyButton) -> bool:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	e.device = 5
	return InputMap.event_is_action(e, action, true)


func _test_conflicts() -> void:
	InputBindings.reset()
	# A is accelerate's first pad slot: binding it to drift's empty second slot swaps the two
	var r := InputBindings.set_slot("drift", InputBindings.PAD, 1, InputBindings.button_spec(JOY_BUTTON_A))
	check(r["ok"] and r["moved_action"] == "accelerate" and r["moved_slot"] == 0 and r["moved_spec"] == "",
		"A moved from accelerate: %s" % r)
	check(_pad_is("drift", JOY_BUTTON_A) and not _pad_is("accelerate", JOY_BUTTON_A), "A drifts now, and no longer accelerates")
	check(InputBindings.slots("accelerate", "pad") == ["", "a5+"], "accelerate keeps RT: %s" % [InputBindings.slots("accelerate", "pad")])
	# within one action the two slots swap
	r = InputBindings.set_slot("accelerate", InputBindings.KEY, 0, InputBindings.key_spec(KEY_UP))
	check(InputBindings.slots("accelerate", "key") == ["k%d" % KEY_UP, "k%d" % KEY_W, ""], "Up and W swap slots")
	# a key of another action swaps with this slot's old key
	r = InputBindings.set_slot("brake", InputBindings.KEY, 0, InputBindings.key_spec(KEY_W))
	check(r["moved_action"] == "accelerate" and InputBindings.get_slot("accelerate", "key", 1) == "k%d" % KEY_S,
		"W to brake gives accelerate S")
	check(_key_is("brake", KEY_W) and _key_is("accelerate", KEY_S), "the InputMap follows the swap")
	# refused
	check(not InputBindings.set_slot("pause", "key", 0, InputBindings.key_spec(KEY_Q))["ok"], "pause's Esc slot is locked")
	check(not InputBindings.set_slot("drift", "key", 0, InputBindings.key_spec(KEY_ESCAPE))["ok"], "Esc is reserved")
	check(not InputBindings.set_slot("drift", "pad", 0, InputBindings.button_spec(JOY_BUTTON_START))["ok"], "Start is reserved")
	check(not InputBindings.set_slot("drift", "pad", 0, InputBindings.button_spec(JOY_BUTTON_GUIDE))["ok"], "Guide is reserved")
	check(not InputBindings.set_slot("drift", "key", 0, InputBindings.button_spec(JOY_BUTTON_X))["ok"], "a pad spec in a key slot")
	check(not InputBindings.set_slot("chat", "pad", 0, InputBindings.button_spec(JOY_BUTTON_X))["ok"], "chat has no pad slot")
	check(not InputBindings.clear_slot("accelerate", "pad", 1), "accelerate's last pad binding can not be cleared")
	check(InputBindings.clear_slot("drift", "pad", 0), "drift's RB can be cleared")
	# a swap with an empty slot can leave an action with nothing: missing() says so
	InputBindings.set_slot("look_back", InputBindings.PAD, 1, InputBindings.axis_spec(JOY_AXIS_TRIGGER_RIGHT, 1))
	check(["accelerate", "pad"] in InputBindings.missing(), "accelerate has no pad binding left: %s" % [InputBindings.missing()])
	InputBindings.reset()
	check(InputBindings.missing().is_empty() and _pad_is("accelerate", JOY_BUTTON_A), "reset brings A back to accelerate")
	# the menus' confirm and back buttons never pause (a pause press is BACK in a dialog)
	var A := InputBindings.button_spec(JOY_BUTTON_A)
	r = InputBindings.set_slot("pause", InputBindings.PAD, 1, A)
	check(not r["ok"] and r["why"] == "menus" and InputBindings.slots("pause", "pad") == ["b6", ""] and _pad_is("accelerate", JOY_BUTTON_A),
		"A can't pause: %s" % r)
	check(not InputBindings.set_slot("pause", InputBindings.PAD, 1, InputBindings.button_spec(JOY_BUTTON_B))["ok"], "nor can B")
	InputBindings.set_slot("pause", InputBindings.PAD, 1, InputBindings.button_spec(JOY_BUTTON_BACK))
	r = InputBindings.set_slot("accelerate", InputBindings.PAD, 0, InputBindings.button_spec(JOY_BUTTON_BACK))
	check(r["ok"] and r["moved_action"] == "pause" and r["moved_spec"] == "" and r["dropped_spec"] == A
		and InputBindings.slots("pause", "pad") == ["b6", ""] and InputBindings.find(A).is_empty(),
		"View from pause to accelerate: pause does not take A, A is free (%s)" % r)
	Game.settings["bindings"] = {"pause": {"pad": ["b6", A]}}
	InputBindings.apply()
	check(InputBindings.slots("pause", "pad") == ["b6", ""], "a settings file with A on pause loses it: %s" % [InputBindings.slots("pause", "pad")])
	InputBindings.reset()


func _ui_pad(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return (ev as InputEventJoypadButton).button_index
	return -1


func _test_nintendo_swap() -> void:
	check(_ui_pad("ui_accept") == JOY_BUTTON_A and _ui_pad("ui_cancel") == JOY_BUTTON_B, "menus: A confirms, B goes back")
	check(_ui_pad("ui_tab_prev") == JOY_BUTTON_LEFT_SHOULDER and _ui_pad("ui_tab_next") == JOY_BUTTON_RIGHT_SHOULDER,
		"LB / RB switch tabs")
	# a Nintendo pad is used
	InputPrompts._pads[6] = {"name": "Nintendo Switch Pro Controller", "style": "switch"}
	await _button(JOY_BUTTON_X, true, 6)
	await _button(JOY_BUTTON_X, false, 6)
	check(InputPrompts.style() == "switch" and InputPrompts.swapped(), "a Switch pad: switch style, swapped")
	check(_ui_pad("ui_accept") == JOY_BUTTON_B and _ui_pad("ui_cancel") == JOY_BUTTON_A,
		"Switch: the right button (A) confirms, the bottom one (B) goes back")
	check(InputPrompts.action_text("ui_accept") == "A" and InputPrompts.action_text("ui_cancel") == "B",
		"its prompts say A to confirm, B to go back")
	check(InputPrompts.icon_name(InputPrompts.prompt_event("ui_accept"), InputPrompts.style()) == "switch_button_a",
		"the confirm icon is Nintendo's A")
	check(InputPrompts.action_text("accelerate") == "B", "accelerate (the bottom button) is B on a Switch pad")
	Game.settings["nintendo_swap"] = false
	Game.settings_changed.emit()
	check(not InputPrompts.swapped() and _ui_pad("ui_accept") == JOY_BUTTON_A, "the swap can be turned off")
	Game.settings["nintendo_swap"] = true
	Game.settings["prompt_style"] = "xbox"
	Game.settings_changed.emit()
	check(InputPrompts.style() == "xbox" and not InputPrompts.swapped(), "prompts forced to Xbox: no swap")
	Game.settings["prompt_style"] = "nintendo"
	await _button(JOY_BUTTON_A, true, 2)
	await _button(JOY_BUTTON_A, false, 2)
	check(InputPrompts.style() == "switch" and InputPrompts.swapped(), "prompts forced to Nintendo on another pad: swapped")
	Game.settings["prompt_style"] = "playstation"
	Game.settings_changed.emit()
	check(InputPrompts.style() == "ps5" and not InputPrompts.swapped() and _ui_pad("ui_accept") == JOY_BUTTON_A,
		"forced to PlayStation: ps5 style, A (cross) confirms again")
	# OPTIONS > CONTROLS holds the menus' confirm / back while it is open
	InputPrompts.hold_swap(true)
	Game.settings["prompt_style"] = "nintendo"
	Game.settings_changed.emit()
	check(_ui_pad("ui_accept") == JOY_BUTTON_A and InputPrompts.swap_pending(), "held: the bottom button still confirms")
	InputPrompts.hold_swap(false)
	check(_ui_pad("ui_accept") == JOY_BUTTON_B and not InputPrompts.swap_pending(), "let go: the Nintendo swap applies")
	Game.settings["prompt_style"] = "auto"
	Game.settings_changed.emit()
	InputPrompts._pads.erase(6)


## The pad icons OPTIONS > CONTROLS shows while the keyboard is in use follow the Options choice.
func _test_style_while_keyboard() -> void:
	await _key(KEY_W)
	await _key(KEY_W, false)
	var n := _redraws
	Game.settings["prompt_style"] = "playstation"
	Game.settings_changed.emit()
	check(InputPrompts.style() == InputPrompts.KEYBOARD and InputPrompts.pad_style() == "ps5" and _redraws > n,
		"on the keyboard, a new pad style still redraws the prompts")
	check(InputPrompts.spec_text(InputBindings.button_spec(JOY_BUTTON_A)) == "CROSS", "pad specs show in the pad style")
	check(InputPrompts.spec_text(InputBindings.key_spec(KEY_SHIFT)) == "SHIFT", "key specs show as keys")
	Game.settings["prompt_style"] = "auto"
	Game.settings_changed.emit()


func _test_prompts() -> void:
	var p := InputPrompts.parse_prompt("STUCK? PRESS {respawn} TO CALL THE CRANE")
	check(p == ["STUCK? PRESS ", {"action": "respawn"}, " TO CALL THE CRANE"], "prompt parsed: %s" % [p])
	p = InputPrompts.parse_prompt("{use_item} SKIP")
	check(p == [{"action": "use_item"}, " SKIP"], "leading action: %s" % [p])
	p = InputPrompts.parse_prompt("{nope} and {ui_accept}{ui_cancel}")
	check(p == ["{nope} and ", {"action": "ui_accept"}, {"action": "ui_cancel"}], "unknown token stays text: %s" % [p])
	p = InputPrompts.parse_prompt("PRESS {respawn")
	check(p == ["PRESS {respawn"], "unclosed token stays text: %s" % [p])
	check(InputPrompts.action_text("respawn", "keyboard") == "R", "respawn on the keyboard: R")
	check(InputPrompts.action_text("respawn", "xbox") == "VIEW", "respawn on Xbox: View")
	check(InputPrompts.action_text("respawn", "ps4") == "SHARE", "respawn on PS4: Share")
	check(InputPrompts.action_text("respawn", "ps5") == "CREATE", "respawn on PS5: Create")
	check(InputPrompts.action_text("respawn", "switch") == "MINUS", "respawn on Switch: minus")
	check(InputPrompts.action_text("chat", "xbox") == "Y", "chat on a pad falls back to its key (Y)")
	check(InputPrompts.action_text("ui_tab_next", "keyboard") == "PG DN", "tabs on the keyboard: %s"
		% InputPrompts.action_text("ui_tab_next", "keyboard"))
	check(InputPrompts.action_icon("respawn", 30.0, "keyboard") != null and InputPrompts.action_icon("respawn", 30.0, "xbox") != null,
		"respawn has icons")
	check(InputPrompts.action_icon("respawn", 30.0, "ps5") == null, "PS5's Create shows as a keycap, not a capsule icon")
	# the widget redraws on a device change
	await _key(KEY_W)
	await _key(KEY_W, false)
	var label := PromptLabel.new("STUCK? PRESS {respawn} TO CALL THE CRANE", 20)
	add_child(label)
	await _frame()
	check(label.get_parsed_text().begins_with("STUCK? PRESS "), "PromptLabel text: %s" % label.get_parsed_text())
	var glyph := InputGlyph.new("respawn", 30.0)
	add_child(glyph)
	var kb_tex := glyph.texture
	check(kb_tex != null and glyph.text() == "R", "InputGlyph shows R's key")
	await _button(JOY_BUTTON_Y, true, 1)
	await _button(JOY_BUTTON_Y, false, 1)
	check(glyph.texture != null and glyph.texture != kb_tex and glyph.text() == "VIEW", "InputGlyph follows the pad: %s"
		% glyph.text())
	glyph.spec = InputBindings.axis_spec(JOY_AXIS_TRIGGER_RIGHT, 1)
	check(glyph.text() == "RT", "InputGlyph shows a spec")
	# no icon: the name on a keycap, as wide as it needs
	glyph.style = "ps5"
	glyph.spec = InputBindings.button_spec(JOY_BUTTON_BACK)
	check(glyph.texture is KeycapTexture and glyph.custom_minimum_size.x > glyph.custom_minimum_size.y,
		"InputGlyph: Create on a keycap (%s)" % glyph.custom_minimum_size)
	glyph.style = "pad"
	check(glyph.text() == InputPrompts.spec_text(glyph.spec, InputPrompts.pad_style()), "InputGlyph style pad: the pad's family")
	label.queue_free()
	glyph.queue_free()


func _test_listen() -> void:
	InputBindings.reset()
	_events.clear()
	# a pad slot takes a button; X is brake's, so brake gets drift's empty slot
	check(InputPrompts.listen("drift", "pad", 1), "listen starts")
	check(not InputPrompts.listen("pause", "key", 0), "a locked slot does not listen")
	check(InputPrompts.is_listening() and InputPrompts.listening_for()["action"] == "drift", "listening for drift")
	await _button(JOY_BUTTON_X, true, 1)  # the press that started it (inside LISTEN_ARM): ignored
	await _button(JOY_BUTTON_X, false, 1)
	check(_events.is_empty() and InputPrompts.is_listening(), "input right after listen() is ignored")
	await _wait(0.2)
	await _button(JOY_BUTTON_X, true, 1)
	await _button(JOY_BUTTON_X, false, 1)
	check(_events.size() == 1 and _events[0][0] == "captured" and _events[0][4] == "b%d" % JOY_BUTTON_X,
		"X captured: %s" % [_events])
	if not _events.is_empty() and _events[0].size() > 5:
		check(_events[0][5]["moved_action"] == "brake", "X moved from brake")
	check(InputBindings.get_slot("drift", "pad", 1) == "b%d" % JOY_BUTTON_X and InputBindings.get_slot("brake", "pad", 0) == "",
		"drift has X, brake's slot is empty")
	# a stick pushed from rest
	_events.clear()
	InputPrompts.listen("look_back", "pad", 1)
	await _wait(0.2)
	await _axis(JOY_AXIS_RIGHT_Y, -0.3, 1)
	check(_events.is_empty(), "a small push is not taken")
	await _axis(JOY_AXIS_RIGHT_Y, -0.9, 1)
	check(_events.size() == 1 and _events[0][4] == "a%d-" % JOY_AXIS_RIGHT_Y, "right stick up captured: %s" % [_events])
	await _axis(JOY_AXIS_RIGHT_Y, 0.0, 1)
	# a trigger held when the slot opens: letting it go binds nothing (not "RT backwards"); it has
	# to come back to rest, then a pull binds it
	_events.clear()
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.8, 1)
	InputPrompts.listen("look_back", "pad", 1)
	await _wait(0.2)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0, 1)
	check(_events.is_empty(), "releasing a held trigger binds nothing: %s" % [_events])
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9, 1)
	check(_events.size() == 1 and _events[0][4] == "a%d+" % JOY_AXIS_TRIGGER_RIGHT, "then a pull binds RT: %s" % [_events])
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0, 1)
	InputBindings.reset()
	# Esc cancels a key slot, and nothing reaches the menus meanwhile
	_events.clear()
	InputPrompts.listen("drift", "key", 1)
	await _wait(0.2)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE, false)
	check(_events.size() == 1 and _events[0][0] == "cancelled" and InputBindings.get_slot("drift", "key", 1) == "k%d" % KEY_SPACE,
		"Esc cancels: %s" % [_events])
	# a key slot takes a key; Start cancels a pad slot; time runs out
	_events.clear()
	InputPrompts.listen("drift", "key", 1)
	await _wait(0.2)
	await _key(KEY_F)
	await _key(KEY_F, false)
	check(InputBindings.get_slot("drift", "key", 1) == "k%d" % KEY_F, "F captured for drift")
	_events.clear()
	InputPrompts.listen("drift", "pad", 0)
	await _wait(0.2)
	await _button(JOY_BUTTON_START, true, 1)
	await _button(JOY_BUTTON_START, false, 1)
	check(_events.size() == 1 and _events[0][0] == "cancelled", "Start cancels a pad slot")
	_events.clear()
	InputPrompts.listen("drift", "pad", 0, 0.3)
	await _wait(0.5)
	check(_events.size() == 1 and _events[0][0] == "cancelled" and not InputPrompts.is_listening(), "the time runs out")
	InputBindings.reset()


func _test_rumble() -> void:
	InputPrompts.stop_rumble()
	await _button(JOY_BUTTON_A, true, 1)
	await _button(JOY_BUTTON_A, false, 1)
	Game.settings["vibration"] = 0.5
	InputPrompts.rumble(0.8, 0.4, 0.3)
	var r := InputPrompts.rumble_now()
	check(is_equal_approx(r.x, 0.4) and is_equal_approx(r.y, 0.2) and r.z > 0.2, "rumble at half strength: %s" % r)
	InputPrompts.rumble(0.1, 0.1, 1.0)
	r = InputPrompts.rumble_now()
	check(is_equal_approx(r.x, 0.4) and r.z < 0.35, "a weaker buzz does not cut a stronger one: %s" % r)
	InputPrompts.rumble(0.2, 1.0, 0.1)
	r = InputPrompts.rumble_now()
	check(is_equal_approx(r.x, 0.4) and is_equal_approx(r.y, 0.5), "each motor keeps the stronger: %s" % r)
	InputPrompts.stop_rumble()
	# a short strong buzz over a long weak one lasts its own time, then the long one goes on
	InputPrompts.rumble(0.4, 0.4, 0.6)
	InputPrompts.rumble(0.2, 1.6, 0.15)
	r = InputPrompts.rumble_now()
	check(is_equal_approx(r.y, 0.8) and r.z < 0.2, "the hit plays for its own time: %s" % r)
	await _wait(0.25)
	r = InputPrompts.rumble_now()
	check(is_equal_approx(r.x, 0.2) and is_equal_approx(r.y, 0.2) and r.z > 0.1 and r.z < 0.4,
		"then the long buzz goes on: %s" % r)
	InputPrompts.stop_rumble()
	await _key(KEY_W)
	await _key(KEY_W, false)
	InputPrompts.rumble(1.0, 1.0, 1.0)
	check(InputPrompts.rumble_now() == Vector3.ZERO, "no rumble while the keyboard is in use")
	InputPrompts.rumble(1.0, 1.0, 1.0, true)
	check(InputPrompts.rumble_now() != Vector3.ZERO, "forced rumble (Options test) reaches the last pad")
	InputPrompts.stop_rumble()
	Game.settings["vibration"] = 0.0
	await _button(JOY_BUTTON_A, true, 1)
	await _button(JOY_BUTTON_A, false, 1)
	InputPrompts.rumble(1.0, 1.0, 1.0)
	check(InputPrompts.rumble_now() == Vector3.ZERO, "vibration 0 is off")
	Game.settings["vibration"] = 0.5
	# only the local player's kart buzzes
	var bot := Kart.new()
	bot.rumble(1.0, 1.0, 1.0)
	check(InputPrompts.rumble_now() == Vector3.ZERO, "a kart that is not the player's does not buzz")
	bot.free()


## A D-pad held on a list keeps moving the focus (Godot moves it once per press).
func _test_menu_repeat() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	for i in 30:
		var b := Button.new()
		b.text = str(i)
		b.focus_mode = Control.FOCUS_ALL
		box.add_child(b)
	await _frame()
	(box.get_child(0) as Control).grab_focus()
	await _button(JOY_BUTTON_DPAD_DOWN, true, 1)
	await _wait(0.2)
	var f := get_viewport().gui_get_focus_owner()
	check(f == box.get_child(1), "the press moves one row (%s)" % (f.text if f is Button else "none"))
	await _wait(0.6)
	f = get_viewport().gui_get_focus_owner()
	check(f != null and f.get_index() >= 4, "held, it keeps moving (row %d)" % (f.get_index() if f else -1))
	await _button(JOY_BUTTON_DPAD_DOWN, false, 1)
	var at := f.get_index() if f else -1
	await _wait(0.3)
	f = get_viewport().gui_get_focus_owner()
	check(f != null and f.get_index() == at, "let go, it stops (row %d, was %d)" % [f.get_index() if f else -1, at])
	box.queue_free()


func _test_disconnect() -> void:
	_events.clear()
	await _button(JOY_BUTTON_A, true, 1)
	await _button(JOY_BUTTON_A, false, 1)
	InputPrompts._on_joy_connection(1, false)
	check(_events == [["lost"]] and InputPrompts.is_controller_lost(), "the pad in use went away: %s" % [_events])
	check(not InputPrompts.using_pad() and InputPrompts.style() == InputPrompts.KEYBOARD, "prompts back to the keyboard")
	InputPrompts._on_joy_connection(1, true)
	check(_events.size() == 2 and _events[1] == ["back", true] and not InputPrompts.is_controller_lost(), "it is back: %s" % [_events])
	_events.clear()
	await _button(JOY_BUTTON_A, true, 1)
	await _button(JOY_BUTTON_A, false, 1)
	InputPrompts._on_joy_connection(1, false)
	await _key(KEY_W)
	await _key(KEY_W, false)
	check(_events == [["lost"], ["back", false]], "going on with the keyboard clears it: %s" % [_events])
	_events.clear()
	InputPrompts._on_joy_connection(4, false)
	check(_events.is_empty(), "a pad not in use going away changes nothing")


# ---------------------------------------------------------------- layouts, pictures, diagrams
## The pad sets the callout layout is also checked with: every control used at once, and the
## D-pad, the right stick and the face buttons crowded.
const STRESS_BINDS := {
	"stress": {"accelerate": ["b0", "a5+"], "brake": ["b2", "a4+"], "steer_left": ["a0-", "b13"],
		"steer_right": ["a0+", "b14"], "drift": ["b10", "a1-"], "use_item": ["b9", "b1"], "look_back": ["b3", "a3+"],
		"respawn": ["b4", "b7"], "pause": ["b6", "b8"], "chat": []},
	"dpad_all": {"accelerate": ["b11", "a5+"], "brake": ["b12", "a4+"], "steer_left": ["a2-", "b13"],
		"steer_right": ["a2+", "b14"], "drift": ["b10", "a1+"], "use_item": ["b9", "b3"], "look_back": ["b0", "a3-"],
		"respawn": ["b4", "b1"], "pause": ["b6", "b2"], "chat": []},
}
## Each silhouette's outline in SVG units (x0, y0, x1, y1), measured from its path data.
const OUTLINES := {"xbox": [7.99, 15.0, 56.01, 48.0], "xbox360": [7.99, 15.01, 55.99, 48.99], "ps3": [8.0, 16.0, 56.0, 46.0],
	"ps4": [8.0, 16.0, 56.0, 46.01], "ps5": [7.99, 16.05, 56.01, 48.0], "switch": [8.0, 14.99, 56.0, 47.99],
	"steamdeck": [8.0, 20.0, 56.0, 44.0], "generic": [7.98, 14.0, 55.99, 46.95]}


## Every preset is a valid set of bindings; applying one gives it back from preset_of and leaves the
## other class alone; STANDARD and WASD are the defaults.
func _test_presets() -> void:
	var K := InputBindings.KEY
	var P := InputBindings.PAD
	InputBindings.reset()
	check(InputBindings.preset_ids(P) == ["standard", "triggers", "classic", "lefty"], "pad presets in menu order: %s"
		% [InputBindings.preset_ids(P)])
	check(InputBindings.preset_ids(K) == ["wasd", "arrows", "one_hand"], "key presets: %s" % [InputBindings.preset_ids(K)])
	var d := InputBindings.defaults()
	for cls in [K, P]:
		for id in InputBindings.preset_ids(cls):
			var tag := "%s/%s" % [cls, id]
			var bad := InputBindings.preset_problems(cls, id)
			check(bad.is_empty(), "%s is valid: %s" % [tag, bad])
			check(InputBindings.PRESET_TITLES.has(id) and InputBindings.PRESET_NOTES.has(id), "%s has a title and a note" % tag)
			var p: Dictionary = InputBindings.PRESETS[cls][id]
			var seen := {}
			for act in InputBindings.ACTIONS:
				var s: Array = p[act]
				check(s.size() == InputBindings.slot_count(act, cls), "%s %s has %d slots" % [tag, act, s.size()])
				for i in s.size():
					var spec: String = s[i]
					if spec == "":
						continue
					check(not seen.has(spec), "%s: %s only once" % [tag, spec])
					seen[spec] = true
					check(InputBindings.event_of(spec) != null and InputBindings.class_of(spec) == cls, "%s: %s is a %s binding"
						% [tag, spec, cls])
					check((act == "pause" and i == 0) or not InputBindings.is_reserved(spec), "%s: %s is reserved" % [tag, spec])
				if act in InputBindings.REQUIRED:
					check(s.count("") < s.size(), "%s binds %s" % [tag, act])
			check(p["pause"][0] == (InputBindings.key_spec(KEY_ESCAPE) if cls == K else InputBindings.button_spec(JOY_BUTTON_START)),
				"%s pauses with Esc / Start" % tag)
			if cls == P:
				check((p["chat"] as Array).is_empty(), "%s has no chat button" % tag)
	for act in InputBindings.ACTIONS:
		check(InputBindings.PRESETS[P]["standard"][act] == d[act][P], "STANDARD is the default for %s" % act)
		check(InputBindings.PRESETS[K]["wasd"][act] == d[act][K], "WASD is the default for %s" % act)
	check(InputBindings.preset_of(P) == "standard" and InputBindings.preset_of(K) == "wasd", "the defaults are STANDARD and WASD")
	# each applied: preset_of gives it back, the other class keeps its own change, nothing is missing
	for cls in [K, P]:
		var other := P if cls == K else K
		for id in InputBindings.preset_ids(cls):
			InputBindings.reset()
			InputBindings.set_slot("look_back", other, 1, InputBindings.button_spec(JOY_BUTTON_RIGHT_STICK) if other == P
				else InputBindings.key_spec(KEY_V))
			var before := {}
			for act in InputBindings.ACTIONS:
				before[act] = InputBindings.slots(act, other)
			check(InputBindings.apply_preset(cls, id), "%s/%s applies" % [cls, id])
			check(InputBindings.preset_of(cls) == id, "%s/%s: preset_of says %s" % [cls, id, InputBindings.preset_of(cls)])
			var same := true
			var exact := true
			for act in InputBindings.ACTIONS:
				same = same and InputBindings.slots(act, other) == before[act]
				exact = exact and InputBindings.slots(act, cls) == InputBindings.PRESETS[cls][id][act]
			check(same, "%s/%s leaves the %s slots alone" % [cls, id, other])
			check(exact, "%s/%s: the slots are the preset's" % [cls, id])
			check(InputBindings.missing().is_empty(), "%s/%s leaves nothing unbound: %s" % [cls, id, InputBindings.missing()])
	# back to the default preset: nothing stored for that class
	InputBindings.reset()
	InputBindings.apply_preset(P, "triggers")
	InputBindings.apply_preset(K, "arrows")
	InputBindings.apply_preset(P, "standard")
	check(_stored(P).is_empty() and not _stored(K).is_empty(), "STANDARD again stores no pad slots: %s" % Game.settings["bindings"])
	InputBindings.apply_preset(K, "wasd")
	check(Game.settings["bindings"].is_empty(), "WASD again stores nothing: %s" % Game.settings["bindings"])
	# one change makes it CUSTOM; the same buttons in another slot order do not
	InputBindings.apply_preset(P, "triggers")
	InputBindings.set_slot("drift", P, 0, InputBindings.button_spec(JOY_BUTTON_RIGHT_SHOULDER))
	check(InputBindings.slots("drift", P) == ["b10", "b0"] and InputBindings.preset_of(P) == "triggers",
		"the slots swapped round: still TRIGGERS (%s)" % InputBindings.preset_of(P))
	InputBindings.set_slot("look_back", P, 1, InputBindings.button_spec(JOY_BUTTON_RIGHT_STICK))
	check(InputBindings.preset_of(P) == "custom", "one more button: CUSTOM (%s)" % InputBindings.preset_of(P))
	var snap: Dictionary = Game.settings["bindings"].duplicate(true)
	check(not InputBindings.apply_preset(P, "no_such_layout") and not InputBindings.apply_preset("wheel", "standard")
		and Game.settings["bindings"] == snap, "an unknown preset changes nothing")
	# the InputMap follows: CLASSIC KART drives with the right face button
	InputBindings.apply_preset(P, "classic")
	check(_pad_is("accelerate", JOY_BUTTON_B) and _pad_is("brake", JOY_BUTTON_A) and not _pad_is("accelerate", JOY_BUTTON_A),
		"CLASSIC KART: B (east) accelerates, A (south) brakes")
	InputBindings.reset()


## The ellipses inscribed in two boxes overlap (sampled round each).
func _ellipses_meet(a: Rect2, b: Rect2) -> bool:
	for pair in [[a, b], [b, a]]:
		var e: Rect2 = pair[0]
		var f: Rect2 = pair[1]
		for i in 72:
			var t := TAU * i / 72.0
			var p := e.get_center() + Vector2(cos(t) * e.size.x, sin(t) * e.size.y) * 0.5
			var d := (p - f.get_center()) / (f.size * 0.5)
			if d.length_squared() < 1.0:
				return true
	return false


## Waits `seconds` by the clock (frames in between).
func _real_wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await _frame()


## The overrides stored for one class: {action: specs}.
func _stored(cls: String) -> Dictionary:
	var out := {}
	for act in Game.settings["bindings"]:
		if (Game.settings["bindings"][act] as Dictionary).has(cls):
			out[act] = Game.settings["bindings"][act][cls]
	return out


## The pad pictures and the icons drawn on them are shipped and load; their outlines are where the
## anchors were measured.
func _test_device_art() -> void:
	for st in InputPrompts.PAD_STYLES:
		var stem: String = ControllerDiagram.DEVICE_SVG[st]
		var path := InputPrompts.icon_path(stem)
		check(path == "res://art/input_prompts/devices/%s.svg" % stem, "%s's picture path: %s" % [st, path])
		check(FileAccess.file_exists(path), "%s's picture is shipped" % st)
		var src := FileAccess.get_file_as_string(path)
		check(src.contains(ControllerDiagram.SVG_FILL) or src.contains(ControllerDiagram.SVG_FILL_GENERIC),
			"%s's picture has the white fill the diagram recolours" % st)
		var img := Image.new()
		check(img.load_svg_from_string(src, 1.0) == OK, "%s's picture loads" % st)
		var u := img.get_used_rect()
		var want: Array = OUTLINES[st]
		check(absf(u.position.x - want[0]) <= 1.05 and absf(u.position.y - want[1]) <= 1.05 and absf(u.end.x - want[2]) <= 1.05
			and absf(u.end.y - want[3]) <= 1.05, "%s's outline %s is where it was measured %s" % [st, u, want])
		var tex := ControllerDiagram.device_texture(st, 10.0, 0.35)
		check(tex != null and roundi(tex.get_width()) == 640, "%s's recoloured picture loads at 10 px a unit (%s)" % [st,
			tex.get_size() if tex else Vector2.ZERO])
		check(ControllerDiagram.device_texture(st, 10.0, 0.35) == tex, "%s's picture is cached" % st)
		for ctl in ControllerDiagram.HOLE_ICONS[st]:
			var s: String = ControllerDiagram.HOLE_ICONS[st][ctl]
			check(FileAccess.file_exists(InputPrompts.icon_path(s)) and InputPrompts.icon(s, 40.0) != null, "%s %s icon %s loads"
				% [st, ctl, s])
		# every control is drawn as an icon that loads, or (no icon) a keycap above or a capsule on the body
		var drawn := {"icon": [], "keycap": [], "capsule": []}
		for ctl in ControllerDiagram.DEVICE_ANCHORS[st]:
			var shown := ControllerDiagram.picture_stem(st, ctl)
			if shown != "":
				check(InputPrompts.icon(shown, 40.0) != null, "%s %s: %s loads" % [st, ctl, shown])
				drawn["icon"].append(ctl)
			else:
				drawn["keycap" if ControllerDiagram.DEVICE_ANCHORS[st][ctl]["kind"] == "above" else "capsule"].append(ctl)
		var caps: Array = [] if st in ["xbox", "switch"] else ["back", "start"]
		var keycaps: Array = ["lt", "lb", "rt", "rb"] if st == "generic" else []
		drawn["capsule"].sort()
		drawn["keycap"].sort()
		caps.sort()
		keycaps.sort()
		check(drawn["capsule"] == caps and drawn["keycap"] == keycaps, "%s draws %s" % [st, drawn])
	var gb := InputPrompts.glyph_box("xbox_button_a")
	check(gb.position.is_equal_approx(Vector2(0.125, 0.125)) and absf(gb.size.x - 0.75) < 0.01 and absf(gb.size.y - 0.75) < 0.01,
		"xbox A's glyph box %s" % gb)
	gb = InputPrompts.glyph_box("xbox_lb")
	check(absf(gb.position.y - 0.25) < 0.01 and absf(gb.size.y - 0.5) < 0.01, "LB's glyph is flat %s" % gb)
	check(InputPrompts.glyph_box("no_such_icon") == Rect2(0, 0, 1, 1), "a missing icon's glyph box is the whole canvas")


## Every pad input with a place on the picture has an anchor in every style; the anchors sit inside
## the picture, on their side, without overlapping; no leader crosses another or runs through a
## button, for every preset (and two crowded sets) in both sizes.
func _test_anchors() -> void:
	var sets: Dictionary = (InputBindings.PRESETS[InputBindings.PAD] as Dictionary).duplicate()
	sets.merge(STRESS_BINDS)
	for ctl in ControllerDiagram.REP_SPEC:
		check(ControllerDiagram.control_of(ControllerDiagram.REP_SPEC[ctl]) == ctl, "%s's own spec shows on it" % ctl)
	for spec in ["b5", "b15", "b16", "b20", "a4-", "a5-", "a6+"]:
		check(ControllerDiagram.control_of(spec) == "", "%s has no place on the picture" % spec)
	for st in InputPrompts.PAD_STYLES:
		var anchors: Dictionary = ControllerDiagram.DEVICE_ANCHORS[st]
		check(ControllerDiagram.PICTURE_TITLES.has(st) and ControllerDiagram.HOLE_ICONS.has(st), "%s has a title and icons" % st)
		for spec in ControllerDiagram.CONTROL_OF:
			check(anchors.has(ControllerDiagram.CONTROL_OF[spec]), "%s has a place for %s" % [st, spec])
		var names: Array = anchors.keys()
		for i in names.size():
			var a: Dictionary = anchors[names[i]]
			var r: Rect2 = a["icon"]
			check(a["kind"] in ["hole", "marker", "above"], "%s %s kind %s" % [st, names[i], a["kind"]])
			check((ControllerDiagram.DEVICE_BOUNDS[st] as Rect2).grow(0.01).encloses(r), "%s %s inside the picture" % [st, names[i]])
			check(int(a["side"]) == (-1 if (a["at"] as Vector2).x < 32.0 else 1), "%s %s's label is on its side" % [st, names[i]])
			for j in range(i + 1, names.size()):
				# (boxes round a cross and a disc may share an empty corner: the PlayStation D-pad and left stick)
				var q: Rect2 = anchors[names[j]]["icon"]
				check(not r.intersects(q) or not _ellipses_meet(r, q), "%s %s and %s do not overlap" % [st, names[i], names[j]])
		for id in sets:
			for m in [ControllerDiagram.FULL, ControllerDiagram.COMPACT]:
				var pl := ControllerDiagram.plan(st, sets[id], m)
				var bad := ControllerDiagram.crossings(st, pl)
				check(bad.is_empty(), "%s/%s %s: no leader crosses (%s)" % [st, id, "compact" if m == ControllerDiagram.COMPACT
					else "full", bad])
		var full := ControllerDiagram.plan(st, sets["standard"], ControllerDiagram.FULL)
		var small := ControllerDiagram.plan(st, sets["standard"], ControllerDiagram.COMPACT)
		check(full["size"] == Vector2(1012, 440) and small["size"] == Vector2(572, 220), "%s's sizes %s / %s" % [st, full["size"],
			small["size"]])


## OPTIONS' big diagram: a row per bound slot, the locked Start, rows following a swap, the
## signals, listening, flashing, the picture under the mouse, the family from BUTTON PROMPTS; the
## compact one takes no focus; a paddle is listed off the picture.
func _test_controller_diagram() -> void:
	var P := InputBindings.PAD
	InputBindings.reset()
	var d := ControllerDiagram.new()
	d.style = "ps5"
	d.interactive = true
	var laid := [0]
	d.laid_out.connect(func(): laid[0] += 1)
	add_child(d)
	await _frame()
	check(d.size == Vector2(1012, 440) and d.rows().size() == 14, "ps5 STANDARD: 1012x440 and 14 rows (%s, %d)" % [d.size,
		d.rows().size()])
	check(laid[0] > 0, "laid_out tells the page")
	var pause = d.row_for("pause", 0)
	check(pause != null and is_equal_approx(pause.modulate.a, 0.6) and pause.control == "start"
		and pause.tooltip_text.contains("always pauses"), "the Start row is the locked one")
	check(d.first_row() == d.rows()[0] and (d.first_row() as ControllerDiagram.Row).side == -1, "the first row is the left column's top")
	var all_ok := true
	for r in d.rows():
		all_ok = all_ok and r.focus_mode == Control.FOCUS_ALL and r.size == Vector2(230, 30) \
			and r.get_meta("control") == ControllerDiagram.control_of(r.get_meta("spec"))
	check(all_ok, "every row is focusable, 230x30, on its spec's control")
	# focus: down the column, across to the nearest row; the edges are the page's
	var left: Array = d.rows().filter(func(r): return r.side < 0)
	var right: Array = d.rows().filter(func(r): return r.side > 0)
	check(left[0].focus_neighbor_top == NodePath() and left[0].get_node(left[0].focus_neighbor_bottom) == left[1]
		and right[-1].focus_neighbor_bottom == NodePath() and right[0].focus_neighbor_right == NodePath(),
		"up / down within a column; the outer edges left to the page")
	check(left[0].get_node(left[0].focus_neighbor_left) == left[0] and right.has(left[0].get_node(left[0].focus_neighbor_right))
		and left.has(right[0].get_node(right[0].focus_neighbor_left)), "left / right between the columns")
	# a swap moves the rows: look behind to the left face button, brake takes Triangle
	var lb = d.row_for("look_back", 0)
	InputBindings.set_slot("look_back", P, 0, InputBindings.button_spec(JOY_BUTTON_X))
	await _frame()
	check(d.row_for("look_back", 0) == lb and lb.control == "face_w", "look behind's row moved to the left face button (%s)"
		% lb.control)
	check(d.row_for("brake", 0).control == "face_n" and d.row_for("brake", 0).spec == "b3", "brake's row moved to the top one")
	# the signals: A / click on a row, X / Delete on it, a click on a bound button on the picture
	var got := []
	d.slot_pressed.connect(func(a: String, s: int): got.append(["press", a, s]))
	d.clear_requested.connect(func(a: String, s: int): got.append(["clear", a, s]))
	lb.pressed.emit()
	var clr := InputEventAction.new()
	clr.action = &"ui_clear"
	clr.pressed = true
	lb.gui_input.emit(clr)
	var ls_box: Rect2 = ControllerDiagram.DEVICE_ANCHORS["ps5"]["ls"]["icon"]
	var at: Vector2 = d._off + d._plan["origin"] + ls_box.get_center() * d._plan["scale"]
	check(d.control_at(at) == "ls", "the left stick is under its box (%s)" % d.control_at(at))
	check(d._get_tooltip(at) == "LEFT STICK: STEER LEFT, STEER RIGHT", "its tooltip: %s" % d._get_tooltip(at))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	d._gui_input(click)
	check(got == [["press", "look_back", 0], ["clear", "look_back", 0], ["press", "steer_left", 0]],
		"row press, row clear and a click on the stick: %s" % [got])
	# listening: the row reads PRESS... and pulses until InputPrompts catches the new button
	await _frame()
	check(InputPrompts.listen("look_back", P, 0), "listen on look behind")
	d.set_listening("look_back", 0)
	check(lb.text == "PRESS..." and lb.icon == null and d.is_processing(), "the listening row reads PRESS...")
	await _real_wait(0.25)  # past listen()'s arming time by the clock (a timer can fire early after a long frame)
	await _button(JOY_BUTTON_Y, true, 1)
	await _button(JOY_BUTTON_Y, false, 1)
	await _frame()
	check(InputBindings.get_slot("look_back", P, 0) == "b3" and lb.control == "face_n" and lb.text == "LOOK BEHIND"
		and lb.icon != null, "Y caught: the row is back on Triangle (%s, %s)" % [lb.control, lb.text])
	d.flash(["look_back|0", "brake|0"])
	check(lb.modulate.is_equal_approx(UiKit.ORANGE) or d.is_processing(), "the changed rows flash")
	await _wait(0.95)
	check(lb.modulate.is_equal_approx(Color.WHITE) and not d.is_processing(), "the flash fades (%s)" % lb.modulate)
	# the family follows BUTTON PROMPTS while style is ""
	d.style = ""
	Game.settings["prompt_style"] = "nintendo"
	Game.settings_changed.emit()
	await _frame()
	check(d.shown_style() == "switch" and d.row_for("accelerate", 0).icon == InputPrompts.spec_icon("b0", 26.0, "switch"),
		"style \"\" follows BUTTON PROMPTS: %s" % d.shown_style())
	Game.settings["prompt_style"] = "auto"
	Game.settings_changed.emit()
	# a paddle has no place on the picture: unplaced, no row; clearing a slot drops its row
	InputBindings.set_slot("drift", P, 1, InputBindings.button_spec(JOY_BUTTON_PADDLE1))
	check(["drift", 1, "b16"] in d.unplaced() and d.row_for("drift", 1) == null, "a paddle is listed off the picture: %s"
		% [d.unplaced()])
	InputBindings.clear_slot("use_item", P, 1)
	check(d.row_for("use_item", 1) == null and d.rows().size() == 13, "a cleared slot's row goes")
	# the compact one: smaller, no focus anywhere
	InputBindings.reset()
	var c := ControllerDiagram.new()
	c.compact = true
	c.style = "xbox"
	add_child(c)
	await _frame()
	var none := c.focus_mode == Control.FOCUS_NONE and c.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for r in c.rows():
		none = none and r.focus_mode == Control.FOCUS_NONE and r.mouse_filter == Control.MOUSE_FILTER_IGNORE
	check(none and c.rows().size() == 14 and c.size == Vector2(572, 220), "the compact one has no focusable control (%s)" % c.size)
	check(c.row_for("respawn", 0).text == "CALL HELP", "the compact one's short titles")
	# the picture alone
	var p := ControllerDiagram.new()
	p.callouts = false
	p.style = "steamdeck"
	add_child(p)
	await _frame()
	check(p.rows().is_empty() and p.size.x == 480.0, "the picture alone (%s)" % p.size)
	InputBindings.reset()
	d.queue_free()
	c.queue_free()
	p.queue_free()


## Every style, every pad preset (and the crowded sets), both sizes: one row per bound input on the
## picture, rows of the mode's size inside the widget, none over another or over a button, every
## label whole (no ellipsis), and the drawn leaders cross nothing.
func _test_diagram_layouts() -> void:
	var sets: Dictionary = (InputBindings.PRESETS[InputBindings.PAD] as Dictionary).duplicate()
	sets.merge(STRESS_BINDS)
	var font := UiKit.font(true)
	var bad := []
	var n := 0
	for st in InputPrompts.PAD_STYLES:
		for id in sets:
			for cm in [false, true]:
				var m: Dictionary = ControllerDiagram.COMPACT if cm else ControllerDiagram.FULL
				var d := ControllerDiagram.new()
				d.style = st
				d.compact = cm
				d.interactive = not cm
				d.binds = sets[id]
				add_child(d)
				await _frame()
				n += 1
				var tag := "%s/%s/%s" % [st, id, "compact" if cm else "full"]
				var want := 0
				for act in sets[id]:
					for spec in sets[id][act]:
						want += 1 if ControllerDiagram.control_of(spec) != "" else 0
				var rows := d.rows()
				if rows.size() != want:
					bad.append("%s: %d rows, %d bound" % [tag, rows.size(), want])
				var widget := Rect2(Vector2.ZERO, d.size)
				var s: float = d._plan["scale"]
				var o: Vector2 = d._off + d._plan["origin"]
				for i in rows.size():
					var r: Button = rows[i]
					var rr := Rect2(r.position, r.size)
					if not widget.encloses(rr) or rr.size != Vector2(m["col_w"], m["row_h"]):
						bad.append("%s: %s at %s" % [tag, r.text, rr])
					var sb := r.get_theme_stylebox("normal")
					var need: float = font.get_string_size(r.text, HORIZONTAL_ALIGNMENT_LEFT, -1, m["font"]).x \
						+ (r.icon.get_width() if r.icon else 0.0) + r.get_theme_constant("h_separation") \
						+ sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
					if need > rr.size.x:
						bad.append("%s: %s is cut (%d > %d)" % [tag, r.text, need, rr.size.x])
					for j in range(i + 1, rows.size()):
						if rr.intersects(Rect2(rows[j].position, rows[j].size)):
							bad.append("%s: %s over %s" % [tag, r.text, rows[j].text])
					for ctl in ControllerDiagram.DEVICE_ANCHORS[st]:
						var ir: Rect2 = ControllerDiagram.DEVICE_ANCHORS[st][ctl]["icon"]
						if rr.intersects(Rect2(o + ir.position * s, ir.size * s)):
							bad.append("%s: %s over the %s" % [tag, r.text, ctl])
				var drawn := ControllerDiagram.crossings(st, {"blocks": d.callout_blocks(), "origin": o, "scale": s})
				if not drawn.is_empty():
					bad.append("%s: drawn leaders cross %s" % [tag, drawn])
				d.queue_free()
	check(bad.is_empty(), "%d callout layouts are tidy: %s" % [n, bad])
	check(n == InputPrompts.PAD_STYLES.size() * 6 * 2, "every style, set and size was laid out (%d)" % n)


## The drawn keyboard: every key of the three key presets and the mouse buttons are on it, the
## numpad is listed off it; sizes, a click on a bound key, the tooltip.
func _test_keyboard_diagram() -> void:
	var k := KeyboardDiagram.new()
	k.interactive = true
	add_child(k)
	await _frame()
	check(k.size == Vector2(872, 257), "the full keyboard is 872x257 (%s)" % k.size)
	for id in InputBindings.preset_ids(InputBindings.KEY):
		for act in InputBindings.ACTIONS:
			for spec in InputBindings.PRESETS[InputBindings.KEY][id][act]:
				if spec != "":
					check(k.key_rect(spec).has_area(), "%s's %s (%s) is on the keyboard" % [id, act, spec])
	for mb in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		check(k.key_rect("m%d" % mb).has_area(), "mouse button %d is on the mouse" % mb)
	var kp := "k%d" % KEY_KP_8
	check(not k.key_rect(kp).has_area() and KeyboardDiagram.unplaced({"accelerate": [kp, "k%d" % KEY_W, ""]})
		== [["accelerate", 0, kp]], "the numpad is listed off the picture")
	check(KeyboardDiagram.unplaced({}).is_empty(), "the default keys are all on the picture")
	# both Shift keys are Shift
	var right_shift := Rect2(Vector2(12.25, 4.25) * KeyboardDiagram.UNIT_FULL, Vector2(2.75, 1) * KeyboardDiagram.UNIT_FULL)
	check(k.spec_at(right_shift.get_center()) == "k%d" % KEY_SHIFT, "the right Shift is Shift too")
	var w := k.key_rect("k%d" % KEY_W).get_center()
	check(k._get_tooltip(w) == "W: ACCELERATE" and k._get_tooltip(k.key_rect("k%d" % KEY_G).get_center()) == "G: free",
		"tooltips: %s / %s" % [k._get_tooltip(w), k._get_tooltip(k.key_rect("k%d" % KEY_G).get_center())])
	var got := []
	k.key_clicked.connect(func(s: String): got.append(s))
	for at in [w, k.key_rect("k%d" % KEY_G).get_center()]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = at
		k._gui_input(click)
	check(got == ["k%d" % KEY_W], "a click on W says so, one on a free key nothing: %s" % [got])
	k.pulse_spec = "k%d" % KEY_W
	check(k.is_processing(), "a listening key pulses")
	k.pulse_spec = ""
	check(not k.is_processing(), "and stops")
	var c := KeyboardDiagram.new()
	c.compact = true
	add_child(c)
	await _frame()
	check(c.size == Vector2(510, 150) and c.mouse_filter == Control.MOUSE_FILTER_IGNORE and c.focus_mode == Control.FOCUS_NONE,
		"the compact keyboard is 510x150 and takes no input (%s)" % c.size)
	k.queue_free()
	c.queue_free()


## OPTIONS' two binding tabs, the pause menu's controls panel and HOW TO DRIVE, built without the
## Half-Life content (pad_nav walks them with the pad alone in a real race).
func _test_pages() -> void:
	var P := InputBindings.PAD
	var K := InputBindings.KEY
	InputBindings.reset()
	var o := OptionsPanel.new()
	add_child(o)
	await _frame()
	await _frame()
	check(o.tabs.tab_count == 5 and o.pages.size() == 5 and o.pages[OptionsPanel.KEYS_TAB] == o.keys
		and o.pages[OptionsPanel.PAD_TAB] == o.pad and o.keys.cls == K and o.pad.cls == P,
		"OPTIONS: five tabs, KEYBOARD & MOUSE and CONTROLLER last, one slot class each")
	check(o.frame.size == OptionsPanel.SIZE, "OPTIONS is 1400x800 (%s)" % o.frame.size)
	o.tabs.current_tab = OptionsPanel.PAD_TAB
	await _frame()
	check(o.pad.visible and InputPrompts._swap_held, "CONTROLLER holds the menus' confirm / back while it shows")
	o.tabs.current_tab = OptionsPanel.KEYS_TAB
	await _frame()
	check(o.keys.visible and not InputPrompts._swap_held, "KEYBOARD & MOUSE does not")
	# LAYOUT: over a layout at once, over the player's own one only after a yes
	var pp := o.pad
	pp._on_layout(1)
	check(InputBindings.preset_of(P) == "triggers" and pp.layout_dd.get_item_text(pp.layout_dd.selected) == "TRIGGERS",
		"a layout over a layout goes in at once (%s)" % InputBindings.preset_of(P))
	InputBindings.set_slot("look_back", P, 1, InputBindings.button_spec(JOY_BUTTON_TOUCHPAD))
	await _frame()
	check(pp.layout_dd.get_item_text(pp.layout_dd.selected) == "CUSTOM", "one change: CUSTOM")
	pp._on_layout(2)
	await _frame()
	var box: MessageBox = null
	for c in o.get_children():
		if c is MessageBox:
			box = c
	check(box != null and InputBindings.preset_of(P) == "custom", "over CUSTOM the layout asks first")
	if box:
		box._answer(true)
	await _frame()
	check(InputBindings.preset_of(P) == "classic" and InputBindings.preset_of(K) == "wasd", "a yes puts CLASSIC KART in, the keys untouched")
	# under the picture: a paddle, and ADD chips for the actions with a free pad slot
	InputBindings.set_slot("drift", P, 1, InputBindings.button_spec(JOY_BUTTON_PADDLE1))
	await _frame()
	check(pp.extra_row("drift", 1) != null and pp._extra_head.visible, "a paddle is listed under the picture")
	InputBindings.reset()
	await _frame()
	check(pp.extra_row("drift", 1) == null and not pp._extra_head.visible and pp.chip_for("drift") != null
		and pp.chip_for("accelerate") == null and pp._add_head.visible, "STANDARD: no extra rows, ADD chips where a pad slot is free")
	# CONTROLLER PICTURE previews a family; BUTTON PROMPTS (and so every other prompt) stays
	var ps := InputPrompts.pad_style()
	pp.picture_dd.select(5)
	pp._on_picture(5)
	await _frame()
	check(pp.diagram.shown_style() == "ps5" and InputPrompts.pad_style() == ps, "the picture shows PlayStation 5, the prompts stay %s" % ps)
	pp.picture_dd.select(0)
	pp._on_picture(0)
	await _frame()
	check(pp.diagram.shown_style() == ps, "AUTO: the BUTTON PROMPTS family again")
	check(pp.diagram.mouse_filter == Control.MOUSE_FILTER_STOP, "the big picture hears the mouse (hover, click, tooltips)")
	# the foot's messages: an action's own two slots trading places, a menu button refused for pause
	o.tabs.current_tab = OptionsPanel.PAD_TAB
	await _frame()
	pp._listening = "accelerate|1"
	pp._on_captured("accelerate", P, 1, null, InputBindings.set_slot("accelerate", P, 1, "b0"))
	check(o._hint.prompt.contains("swapped slots"), "an action's own slots: %s" % o._hint.prompt)
	pp._listening = "pause|1"
	pp._on_captured("pause", P, 1, null, InputBindings.set_slot("pause", P, 1, "b0"))
	check(o._hint.prompt.contains("can't pause") and InputBindings.slots("pause", P) == ["b6", ""], "A refused for pause: %s"
		% o._hint.prompt)
	# the ADD chip keeps its width while it listens (the chips after it stay put)
	var chip := pp.chip_for("drift")
	var w0 := chip.size.x if chip else 0.0
	pp.press_slot("drift", 1)
	await _frame()
	check(chip != null and chip.text == "PRESS..." and absf(chip.size.x - w0) < 0.5, "a listening chip keeps its width (%s, %s)"
		% [w0, chip.size.x if chip else -1.0])
	InputPrompts.cancel_listen()
	await _frame()
	check(chip != null and chip.text.begins_with("+ ") and chip.custom_minimum_size.x == 0.0, "and lets it go after")
	InputBindings.reset()
	o.tabs.current_tab = OptionsPanel.KEYS_TAB
	await _frame()
	# KEYBOARD & MOUSE: a click on a lit key listens on its slot
	o.keys._on_key_clicked(InputBindings.key_spec(KEY_W))
	check(InputPrompts.is_listening() and o.keys.listening_slot() == "accelerate|0"
		and o.keys.keyboard.pulse_spec == InputBindings.key_spec(KEY_W), "a click on W listens on Accelerate's first key")
	InputPrompts.cancel_listen()
	check(not InputPrompts.is_listening() and o.keys.listening_slot() == "" and o.keys.keyboard.pulse_spec == "", "and stops")
	o.queue_free()
	await _frame()
	check(not InputPrompts._swap_held, "OPTIONS gone: nothing held")
	# the pause menu's controls: the device in use
	var cp := PauseControls.new(false)
	add_child(cp)
	await _button(JOY_BUTTON_DPAD_UP, true)
	await _button(JOY_BUTTON_DPAD_UP, false)
	check(cp.pad_diagram != null and cp.keyboard == null and cp.pad_diagram.compact and cp.pad_diagram.rows().size() == 14,
		"a pad in use: the compact picture with its labels")
	await _key(KEY_F9)
	await _key(KEY_F9, false)
	check(cp.keyboard != null and cp.pad_diagram == null and cp._list.get_child_count() == InputBindings.ACTIONS.size() - 1,
		"the keyboard in use: the drawn keyboard and the actions but CHAT (%d)" % (cp._list.get_child_count() if cp._list else -1))
	check(cp.mouse_filter == Control.MOUSE_FILTER_IGNORE and cp.find_children("*", "Control", true, false).all(
		func(c): return (c as Control).focus_mode != Control.FOCUS_ALL), "it never takes the focus")
	cp.queue_free()
	# HOW TO DRIVE
	var fake := Node.new()
	add_child(fake)
	var card := DriveCard.new()
	fake.add_child(card)
	card.setup(fake)
	await _frame()
	check(card.layer == DriveCard.LAYER and card.shown_actions().size() == 7, "HOW TO DRIVE: 7 rows (%s)" % [card.shown_actions()])
	var styles := []
	for g in card.panel.find_children("*", "InputGlyph", true, false):
		if not (g as InputGlyph).style in styles:
			styles.append((g as InputGlyph).style)
	check(styles == [InputPrompts.KEYBOARD], "the keyboard in use: keys (%s)" % [styles])
	var was: bool = Game.settings.get("controls_card", true)
	Game.settings["controls_card"] = true
	check(DriveCard.wanted(fake), "wanted in a race")
	Game.settings["controls_card"] = false
	check(not DriveCard.wanted(fake), "OPTIONS > GAME turns it off")
	Game.settings["controls_card"] = was
	card.leave()
	await _wait(0.6)
	check(not is_instance_valid(card), "it fades out and goes at GO")
	fake.queue_free()
	InputBindings.reset()
