extends Node
## Headless check of the gamepad layer (InputBindings, InputPrompts, PromptLabel): pads on any
## device id drive the kart, the pad family's icons and names, bindings saved and loaded, reset and
## swapped on a clash, the Nintendo confirm / back swap, prompt text, listening for a new binding,
## rumble, which device is active and a pad going away. Prints each failure and a total; exits 1
## on any failure. Restores the settings it changes.
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
