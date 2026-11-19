extends Node
## Autoload "InputPrompts": which device the player is using (keyboard and mouse, or a pad and its
## family), the icons of an action's bindings for that device, rumble on that pad, pads coming and
## going, and listening for a new binding (OPTIONS > KEYBOARD & MOUSE / CONTROLLER). It builds the InputMap
## (InputBindings) at startup, after Game has loaded the settings.
##
## Prompt styles: "keyboard", or a pad style: "xbox" (One / Series: View, Menu), "xbox360" (Back,
## Start), "ps3" (Select), "ps4" (Share), "ps5" (Create), "switch", "steamdeck", or "generic" (a
## joystick SDL does not know, whose button numbers are its own: shapes and text). Pad buttons are
## positional (SDL3): JOY_BUTTON_A is the bottom face button, which a Nintendo pad labels B.
## Icons are Kenney's Input Prompts (CC0) in art/input_prompts, read as SVG and drawn sharp at any
## size (DPITexture); that folder has a .gdignore, so Godot never imports them.

## The prompt style changed: "keyboard" or a pad style (the player switched device or pad family).
signal style_changed(style: String)
## Redraw every prompt: the style, the bindings or the menus' confirm / back buttons changed.
signal prompts_changed
signal pad_connected(device: int, pad_name: String)
signal pad_disconnected(device: int, pad_name: String)
## The pad the player was using went away (offline race: pause; online: a notice).
signal controller_lost
## After controller_lost: a pad is back (by_pad), or the player went on with the keyboard or mouse.
signal controller_back(by_pad: bool)
## listen() caught an input: `event` (a pad event matches any pad), applied already when listen
## was asked to; `result` is InputBindings.set_slot's ({} when not applied).
signal rebind_captured(action: String, cls: String, slot: int, event: InputEvent, result: Dictionary)
## listen() ended with nothing: Esc, Start, a left click or the time ran out.
signal rebind_cancelled(action: String, cls: String, slot: int)

const KEYBOARD := "keyboard"
const PAD_STYLES: Array[String] = ["xbox", "xbox360", "ps3", "ps4", "ps5", "switch", "steamdeck", "generic"]
## Game.settings["prompt_style"] choices (OPTIONS > CONTROLLER > BUTTON PROMPTS); "auto" = detected.
const STYLE_CHOICES: Array[String] = ["auto", "xbox", "playstation", "nintendo", "steamdeck", "generic"]
const STYLE_TITLES := {"auto": "AUTO", "xbox": "XBOX", "playstation": "PLAYSTATION", "nintendo": "NINTENDO",
	"steamdeck": "STEAM DECK", "generic": "GENERIC"}
## A pad style's family (STYLE_CHOICES names) and its pad's name for people.
const FAMILY := {"xbox": "xbox", "xbox360": "xbox", "ps3": "playstation", "ps4": "playstation", "ps5": "playstation",
	"switch": "nintendo", "steamdeck": "steamdeck", "generic": "generic", "keyboard": "keyboard"}
const STYLE_NAMES := {"xbox": "Xbox", "xbox360": "Xbox 360", "ps3": "PlayStation 3", "ps4": "PlayStation 4",
	"ps5": "PlayStation 5", "switch": "Nintendo Switch", "steamdeck": "Steam Deck", "generic": "Gamepad",
	"keyboard": "Keyboard and mouse"}

const ICON_DIR := "res://art/input_prompts/"
## Kenney's file name prefix -> its folder; "controller_" are the whole-pad pictures (ControllerDiagram).
const ICON_FOLDERS := {"xbox_": "xbox", "playstation": "playstation", "switch_": "nintendo", "steamdeck_": "steamdeck",
	"generic_": "generic", "keyboard_": "keyboard_mouse", "mouse_": "keyboard_mouse", "controller_": "devices"}

const STICK_WAKE := 0.5  # a stick pushed past this (from near rest) makes its pad the active device
const TRIGGER_WAKE := 0.35
const REARM := 0.6  # ...and must come back under this share of it before it can again (drift)
const MOUSE_TRAVEL := 8.0  # px the mouse must travel to take over from the keyboard or a pad
const TWIN_MS := 100  # one press from two devices this close together: one pad seen twice
const LISTEN_ARM := 0.15  # s listen() ignores input for (the press that started it)
const AXIS_CAPTURE := 0.6  # how far from where it rested an axis must go to be bound
const AXIS_NEAR := 0.3  # ...after it has been this near its rest (a held trigger must come back first)
const REPEAT_DELAY := 400  # ms a pad holds a menu direction before it repeats
const REPEAT_EVERY := 80  # ms between repeats
const ACCENT := "#FF9B00"  # UiKit.ORANGE: in place of Kenney's red on D-pads and mouse buttons
const KENNEY_RED := "#E73246"
## Menu screens (Dialog, NEW RACE, the lobby, the race's pause and results, the main menu, the
## first start) join this group and have focus_default() -> bool: the focus safety net.
const SCREEN_GROUP := "ui_screen"
const NAV_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept",
	&"ui_focus_next", &"ui_focus_prev"]
const NAV_DIRS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]

const VID_MICROSOFT := 0x045E
const VID_SONY := 0x054C
const VID_NINTENDO := 0x057E
const VID_VALVE := 0x28DE
const PID_XBOX360: Array[int] = [0x028E, 0x0719, 0x02A1]
const PID_PS5: Array[int] = [0x0CE6, 0x0DF2]
const PID_PS3 := 0x0268
const PID_DECK := 0x1205

## Pad icons by family set: face buttons by position [south, east, west, north].
const FACE := {
	"xbox": ["xbox_button_a", "xbox_button_b", "xbox_button_x", "xbox_button_y"],
	"playstation": ["playstation_button_cross", "playstation_button_circle", "playstation_button_square",
		"playstation_button_triangle"],
	"switch": ["switch_button_b", "switch_button_a", "switch_button_y", "switch_button_x"],
	"steamdeck": ["steamdeck_button_a", "steamdeck_button_b", "steamdeck_button_x", "steamdeck_button_y"],
	"generic": ["switch_buttons_down", "switch_buttons_right", "switch_buttons_left", "switch_buttons_up"],
}
const FACE_TEXT := {"xbox": ["A", "B", "X", "Y"], "playstation": ["CROSS", "CIRCLE", "SQUARE", "TRIANGLE"],
	"switch": ["B", "A", "Y", "X"], "steamdeck": ["A", "B", "X", "Y"],
	"generic": ["BUTTON 1", "BUTTON 2", "BUTTON 3", "BUTTON 4"]}
## [LB, RB, LT, RT, left stick press, right stick press]
const SHOULDERS := {
	"xbox": ["xbox_lb", "xbox_rb", "xbox_lt", "xbox_rt", "xbox_ls", "xbox_rs"],
	"playstation": ["playstation_trigger_l1", "playstation_trigger_r1", "playstation_trigger_l2",
		"playstation_trigger_r2", "playstation_button_l3", "playstation_button_r3"],
	"switch": ["switch_button_l", "switch_button_r", "switch_button_zl", "switch_button_zr", "switch_stick_l_press",
		"switch_stick_r_press"],
	"steamdeck": ["steamdeck_button_l1", "steamdeck_button_r1", "steamdeck_button_l2", "steamdeck_button_r2",
		"steamdeck_stick_l_press", "steamdeck_stick_r_press"],
	"generic": ["", "", "", "", "generic_stick_press", "generic_stick_press"],
}
const SHOULDER_TEXT := {"xbox": ["LB", "RB", "LT", "RT", "LS", "RS"], "playstation": ["L1", "R1", "L2", "R2", "L3", "R3"],
	"switch": ["L", "R", "ZL", "ZR", "LS", "RS"], "steamdeck": ["L1", "R1", "L2", "R2", "L3", "R3"],
	"generic": ["L1", "R1", "L2", "R2", "L3", "R3"]}
## [Back, Start] by pad style. Kenney draws the PlayStation, Xbox 360 and Steam Deck ones as tiny
## capsules nobody can read at prompt size: those show their name in a keycap (MENU_TEXT).
const MENU_BUTTONS := {"xbox": ["xbox_button_view", "xbox_button_menu"], "xbox360": ["", ""], "ps3": ["", ""],
	"ps4": ["", ""], "ps5": ["", ""], "switch": ["switch_button_minus", "switch_button_plus"], "steamdeck": ["", ""],
	"generic": ["", ""]}
const MENU_TEXT := {"xbox": ["VIEW", "MENU"], "xbox360": ["BACK", "START"], "ps3": ["SELECT", "START"],
	"ps4": ["SHARE", "OPTIONS"], "ps5": ["CREATE", "OPTIONS"], "switch": ["MINUS", "PLUS"], "steamdeck": ["VIEW", "MENU"],
	"generic": ["SELECT", "START"]}
const DIRS: Array[String] = ["up", "down", "left", "right"]

## Keys Kenney draws as a symbol (letters, digits and F-keys come from _key_stem). The keys that
## carry a word (Shift, Ctrl, Space, Enter, Esc, Page Up...) are 4-6 px tall words at prompt size:
## they show their name in a keycap instead (KEY_TEXT, KeycapTexture).
const KEY_ICONS := {KEY_META: "win", KEY_UP: "arrow_up", KEY_DOWN: "arrow_down", KEY_LEFT: "arrow_left",
	KEY_RIGHT: "arrow_right", KEY_APOSTROPHE: "apostrophe", KEY_COMMA: "comma", KEY_PERIOD: "period",
	KEY_SEMICOLON: "semicolon", KEY_MINUS: "minus", KEY_EQUAL: "equals", KEY_BRACKETLEFT: "bracket_open",
	KEY_BRACKETRIGHT: "bracket_close", KEY_SLASH: "slash_forward", KEY_BACKSLASH: "slash_back", KEY_QUOTELEFT: "tilde",
	KEY_ASCIITILDE: "tilde", KEY_ASTERISK: "asterisk", KEY_KP_MULTIPLY: "asterisk", KEY_KP_ADD: "numpad_plus",
	KEY_KP_SUBTRACT: "minus", KEY_KP_DIVIDE: "slash_forward", KEY_KP_PERIOD: "period"}
## Short names for keys whose system name is long (the rest: OS.get_keycode_string, upper case).
const KEY_TEXT := {KEY_ESCAPE: "ESC", KEY_PAGEUP: "PG UP", KEY_PAGEDOWN: "PG DN", KEY_DELETE: "DEL", KEY_INSERT: "INS",
	KEY_CAPSLOCK: "CAPS LOCK", KEY_NUMLOCK: "NUM LOCK", KEY_SCROLLLOCK: "SCROLL LOCK", KEY_PRINT: "PRT SC",
	KEY_KP_ENTER: "NUM ENTER", KEY_META: "WIN", KEY_CTRL: "CTRL", KEY_KP_0: "NUM 0", KEY_KP_1: "NUM 1",
	KEY_KP_2: "NUM 2", KEY_KP_3: "NUM 3", KEY_KP_4: "NUM 4", KEY_KP_5: "NUM 5", KEY_KP_6: "NUM 6", KEY_KP_7: "NUM 7",
	KEY_KP_8: "NUM 8", KEY_KP_9: "NUM 9"}
const MOUSE_ICONS := {MOUSE_BUTTON_RIGHT: "mouse_right", MOUSE_BUTTON_MIDDLE: "mouse_scroll",
	MOUSE_BUTTON_XBUTTON1: "mouse_side_back", MOUSE_BUTTON_XBUTTON2: "mouse_side_forward"}
const MOUSE_TEXT := {MOUSE_BUTTON_LEFT: "LEFT CLICK", MOUSE_BUTTON_RIGHT: "RIGHT CLICK", MOUSE_BUTTON_MIDDLE: "MIDDLE CLICK",
	MOUSE_BUTTON_XBUTTON1: "MOUSE 4", MOUSE_BUTTON_XBUTTON2: "MOUSE 5"}

## Hide the mouse cursor while a pad is the active device (it shows again when the mouse moves).
var hide_cursor_with_pad := true
## The devices whose sticks and triggers drive the actions (InputBindings.apply): [-1] (any) while
## every connected device is a pad SDL knows. A wheel or a flight stick plugged in beside a pad
## is left out until it is used (_allow_axes): its axes rest anywhere (a pedal at +1 would hold
## accelerate down for the whole race).
var axis_devs: Array = [InputBindings.ALL_DEVICES]

var _kind := "key"  # the device the player used last: "key", "mouse" or "pad"
var _pad := -1  # the pad used last (or the first one connected); -1: none
var _pads := {}  # device -> {"name": String, "style": String}
var _style := KEYBOARD
var _shown_pad_style := ""  # pad_style() when prompts were last told
var _swap := false  # ui_accept / ui_cancel swapped for a Nintendo pad
var _travel := 0.0  # mouse travel since the keyboard or a pad was used
var _armed := {}  # device * 16 + axis -> the axis came back near rest since it last woke a pad
var _lost := false
var _focused := true
var _cursor_hidden := false
var _icons := {}  # "stem@px" -> Texture2D (null: no such icon)
var _glyph_boxes := {}  # stem -> Rect2 (glyph_box)
var _axis_ok := {}  # joysticks SDL does not know that were used: their axes count (axis_devs)
var _press := {}  # device -> [input ("b<button>" / "a<axis>"), msec] of its last press or push
var _twins := {}  # device -> the pad it echoes (one pad seen as two: DS4Windows, Steam Input)
var _pending := {}  # a twin's input waiting TWIN_MS for the active pad's echo: {device, input, at}
var _nav: StringName = &""  # the menu direction a pad holds (repeated in _process)
var _nav_src := ""  # what holds it: "b<button>@<device>" or "a<axis>@<device>"
var _nav_next := 0  # msec of its next repeat
var _swap_held := false  # hold_swap(): the menus' confirm / back stay as they are
var _r_dev := -1  # rumble: the pad, when it ends (msec) and its motors
var _r_end := 0
var _r_weak := 0.0
var _r_strong := 0.0
var _r_forced := false  # the running buzz is a forced one (OPTIONS test): a pause does not stop it
var _r_after_end := 0  # a longer buzz a short strong one cut into: it goes on when that ends
var _r_after_weak := 0.0
var _r_after_strong := 0.0
var _listen := {}  # listen(): action, cls, slot, apply, armed, end (msec)
var _rest := {}  # listen(): device * 16 + axis -> where that axis rests
var _arm := {}  # listen(): device * 16 + axis -> it has been near its rest since listening began


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for d in Input.get_connected_joypads():
		_register(d)
	if not _pads.is_empty():
		_pad = _pads.keys()[0]
	axis_devs = _axis_devices()
	InputBindings.apply()
	Input.joy_connection_changed.connect(_on_joy_connection)
	get_tree().root.window_input.connect(_on_window_input)
	Game.settings_changed.connect(_on_settings_changed)
	_swap = not _wants_swap()  # so _refresh applies the menus' pad buttons once
	_refresh()


# ---------------------------------------------------------------- the active device
## A pad is the device the player used last.
func using_pad() -> bool:
	return _kind == "pad"


## The mouse is the device the player used last (hover may take the focus).
func mouse_active() -> bool:
	return _kind == "mouse"


## The prompt style now: "keyboard" or the pad style (pad_style).
func style() -> String:
	return _style


## The icon style for pad bindings: the player's choice in Options, else the family of the pad
## used last (or connected), else Xbox's (the usual layout on PC). Also what pad icons show while
## the keyboard is active (OPTIONS > CONTROLLER, the pause menu's picture).
func pad_style() -> String:
	var det := detected_style()
	match str(Game.settings.get("prompt_style", "auto")):
		"xbox":
			return "xbox360" if det == "xbox360" else "xbox"
		"playstation":
			return det if det in ["ps3", "ps4", "ps5"] else "ps5"
		"nintendo":
			return "switch"
		"steamdeck":
			return "steamdeck"
		"generic":
			return "generic"
	return det if det != "" else "xbox"


## The family of the pad that would be shown, ignoring the Options choice ("" with no pad seen).
func detected_style() -> String:
	if _pads.has(_pad):
		return _pads[_pad]["style"]
	return ""


## A style's family: "xbox", "playstation", "nintendo", "steamdeck", "generic" or "keyboard".
func family(style_id := "") -> String:
	return FAMILY.get(style_id if style_id != "" else _style, "xbox")


## The pad used last (or the first connected), -1 with none.
func active_pad() -> int:
	return _pad


func connected_pads() -> Array[int]:
	return Input.get_connected_joypads()


## A pad's name as the system gives it ("" with none): the active pad's by default.
func pad_name(device := -1) -> String:
	var d := device if device >= 0 else _pad
	return str(_pads.get(d, {}).get("name", ""))


## The menus confirm with the right face button and go back with the bottom one (Nintendo pads).
func swapped() -> bool:
	return _swap


## The pad the player was using went away, and they have not gone on with another device yet.
func is_controller_lost() -> bool:
	return _lost


## The style of one connected pad.
func detect_style(device: int) -> String:
	var info := Input.get_joy_info(device)
	return style_for(Input.get_joy_name(device), str(info.get("raw_name", "")), int(str(info.get("vendor_id", "0"))),
		int(str(info.get("product_id", "0"))), Input.is_joy_known(device), info.has("xinput_index"))


## A pad's style from what the system says of it: USB vendor and product ids first (Sony, Nintendo,
## Valve and Microsoft make only their own pads; other makers build pads of every family), then
## words in its name, then XInput, else Xbox. A joystick SDL does not map as a gamepad (a wheel,
## a flight stick) numbers its buttons its own way: "generic".
static func style_for(pad_name_: String, raw_name: String, vendor: int, product: int, known: bool, xinput: bool) -> String:
	if not known:
		return "generic"
	match vendor:
		VID_SONY:
			if product in PID_PS5:
				return "ps5"
			return "ps3" if product == PID_PS3 else "ps4"
		VID_NINTENDO:
			return "switch"
		VID_VALVE:
			if product == PID_DECK:
				return "steamdeck"
		VID_MICROSOFT:
			return "xbox360" if product in PID_XBOX360 else "xbox"
	var n := (pad_name_ + " " + raw_name).to_lower()
	if n.contains("dualsense") or n.contains("ps5"):
		return "ps5"
	if n.contains("ps3") or n.contains("dualshock 3"):
		return "ps3"
	if n.contains("dualshock") or n.contains("ps4") or n.contains("playstation"):
		return "ps4"
	if n.contains("nintendo") or n.contains("switch") or n.contains("joy-con"):
		return "switch"
	if n.contains("steam deck"):
		return "steamdeck"
	if n.contains("360"):
		return "xbox360"
	if n.contains("xbox") or n.contains("x-box") or n.contains("xinput") or xinput:
		return "xbox"
	return "xbox"


func _on_window_input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		if ev.is_pressed() and not ev.is_echo():
			_use("key", -1)
	elif ev is InputEventMouseButton:
		if ev.is_pressed():
			_use("mouse", -1)
	elif ev is InputEventMouseMotion:
		if _kind != "mouse":
			_travel += (ev as InputEventMouseMotion).relative.length()
			if _travel > MOUSE_TRAVEL:
				_use("mouse", -1)
	elif ev is InputEventJoypadButton:
		_track_nav(ev)
		if ev.is_pressed():
			_pad_input(ev.device, "b%d" % (ev as InputEventJoypadButton).button_index)
	elif ev is InputEventJoypadMotion:
		_track_nav(ev)
		# a resting trigger, a drifting stick or a wheel's pedal never take over: the axis must go
		# from near rest to well past it (an axis first seen far from rest, a pedal, must come back;
		# a known pad's sticks and triggers rest at 0, so their first push counts)
		var m := ev as InputEventJoypadMotion
		var key := m.device * 16 + m.axis
		var wake := TRIGGER_WAKE if m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT else STICK_WAKE
		var v := absf(m.axis_value)
		if v < wake * REARM:
			_armed[key] = true
		elif v >= wake and _armed.get(key, m.axis < JOY_AXIS_SDL_MAX and Input.is_joy_known(m.device)):
			_armed[key] = false
			_pad_input(m.device, "a%d" % m.axis)


## A pad's button press or stick push: that pad becomes the active device, unless it is the
## active pad's twin echoing the same input (one pad that reaches the game as two devices:
## DS4Windows' virtual pad beside the real one, Steam Input's). A device seen echoing before
## takes over only when the active pad does not echo it within TWIN_MS (_process).
func _pad_input(device: int, input: String) -> void:
	var now := Time.get_ticks_msec()
	_press[device] = [input, now]
	if device == _pad or _pad < 0:
		if not _pending.is_empty() and _pending["input"] == input:
			_pending = {}
		_use("pad", device)
		return
	var last: Array = _press.get(_pad, ["", 0])
	if last[0] == input and now - int(last[1]) < TWIN_MS:
		_twins[device] = _pad
		return
	if _twins.get(device, -2) == _pad:
		_pending = {"device": device, "input": input, "at": now}
		return
	_use("pad", device)


func _use(kind: String, device: int) -> void:
	if kind == "pad":
		_travel = 0.0
		if not _pads.has(device):
			_register(device)
		if device != _pad:
			if _r_dev >= 0 and _r_dev != device:
				stop_rumble()
			_pad = device
		_allow_axes(device)
	elif kind == "key":
		_travel = 0.0
	if _lost:
		_lost = false
		controller_back.emit(kind == "pad")
	if kind != _kind:
		_kind = kind
		_cursor()
	_refresh()


func _register(device: int) -> void:
	# a pad that is not connected sent this (an event made in code): the usual layout
	var real := device in Input.get_connected_joypads()
	_pads[device] = {"name": Input.get_joy_name(device) if real else "",
		"style": detect_style(device) if real else "xbox"}


func _on_joy_connection(device: int, connected: bool) -> void:
	if connected:
		# pads plugged in before the game started are reported again a frame after _ready
		var fresh := not _pads.has(device)
		_register(device)
		if _pad < 0:
			_pad = device
		if fresh:
			pad_connected.emit(device, pad_name(device))
		if _lost:
			_lost = false
			controller_back.emit(true)
		_update_axis_devices()
		_refresh()
		return
	var had := _pads.has(device)
	var nm := pad_name(device)
	_pads.erase(device)
	if _r_dev == device:
		stop_rumble()
	for ax in JOY_AXIS_MAX:
		_armed.erase(device * 16 + ax)
	_press.erase(device)
	_axis_ok.erase(device)
	_twins.erase(device)
	for d in _twins.keys():
		if _twins[d] == device:
			_twins.erase(d)
	if not _pending.is_empty() and _pending["device"] == device:
		_pending = {}
	if device == _pad:
		var left: Array[int] = Input.get_connected_joypads()
		left.erase(device)
		_pad = left[0] if not left.is_empty() else -1
		if _pad >= 0 and not _pads.has(_pad):
			_register(_pad)
		if _kind == "pad":
			if _pad < 0:
				_kind = "key"
				_cursor()
			_lost = true
			controller_lost.emit()
	if had:
		pad_disconnected.emit(device, nm)
	_update_axis_devices()
	_refresh()


## axis_devs for the devices connected now: the known pads and the joysticks used since they were
## plugged in; any device ([-1]) when that is all of them, or with no known pad at all.
func _axis_devices() -> Array:
	var pads := Input.get_connected_joypads()
	var out := []
	for d in pads:
		if Input.is_joy_known(d) or _axis_ok.has(d):
			out.append(d)
	return out if not out.is_empty() and out.size() < pads.size() else [InputBindings.ALL_DEVICES]


## A device came or went: rebuilds the InputMap if the devices whose axes count changed.
func _update_axis_devices() -> void:
	var a := _axis_devices()
	if a != axis_devs:
		axis_devs = a
		InputBindings.apply()


## A joystick SDL does not know was used (a button, or an axis from rest): its sticks and pedals
## count from now on, until it is unplugged. They are added to the InputMap, where a rebuild
## would let go of what the player holds.
func _allow_axes(device: int) -> void:
	if Input.is_joy_known(device) or _axis_ok.has(device) or device not in Input.get_connected_joypads():
		return
	_axis_ok[device] = true
	if axis_devs.size() == 1 and int(axis_devs[0]) == InputBindings.ALL_DEVICES:
		return
	axis_devs.append(device)
	InputBindings.add_axis_device(device)


func _on_settings_changed() -> void:
	InputBindings.apply_deadzone()
	_refresh()


func _wants_swap() -> bool:
	return bool(Game.settings.get("nintendo_swap", true)) and family(pad_style()) == "nintendo"


## OPTIONS > CONTROLLER: while `on`, the menus' confirm and back buttons stay as they are (the
## Nintendo swap turned on there would make the next press of the same button go back); off
## applies what the settings ask for.
func hold_swap(on: bool) -> void:
	if _swap_held == on:
		return
	_swap_held = on
	if not on:
		_refresh()


## The settings ask for another confirm / back than the menus have (hold_swap keeps it waiting).
func swap_pending() -> bool:
	return _wants_swap() != _swap


## Works out the style and the menus' confirm / back buttons, and tells the prompts what changed.
func _refresh() -> void:
	var changed := false
	var sw := _wants_swap()
	if sw != _swap and not _swap_held:
		_swap = sw
		InputBindings.apply_ui(sw)
		changed = true
	var ps := pad_style()
	if ps != _shown_pad_style:
		_shown_pad_style = ps
		changed = true
	var s := ps if _kind == "pad" else KEYBOARD
	if s != _style:
		_style = s
		changed = true
		style_changed.emit(s)
	if changed:
		prompts_changed.emit()


## InputBindings.apply rebuilt the InputMap.
func bindings_changed() -> void:
	prompts_changed.emit()


func _cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _kind == "pad" and hide_cursor_with_pad and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_cursor_hidden = true
	elif _kind == "mouse" and _cursor_hidden:
		if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_cursor_hidden = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		stop_rumble()
		_nav = &""
		_nav_src = ""
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if get_tree().paused and not _r_forced and (now < _r_end or _r_after_end > now):
		stop_rumble()
	elif _r_after_end > 0 and now >= _r_end:
		# the short strong buzz is over: the longer one it cut into goes on for what is left of it
		var e := _r_after_end
		_r_after_end = 0
		if e > now and _r_dev >= 0:
			_start_rumble(_r_dev, _r_after_weak, _r_after_strong, e, _r_forced)
	if not _listen.is_empty() and now > int(_listen["end"]):
		_cancel_listen()
	if not _pending.is_empty() and now - int(_pending["at"]) >= TWIN_MS:
		# the active pad did not echo it: the other device is in use after all
		var d: int = _pending["device"]
		_pending = {}
		_twins.erase(d)
		_use("pad", d)
	if _nav != &"" and now >= _nav_next:
		_nav_next = now + REPEAT_EVERY
		_repeat_nav()


## Which menu direction a pad's D-pad or stick holds (Godot moves the focus once per press, and a
## stick only when it crosses the threshold): _process repeats it after REPEAT_DELAY.
func _track_nav(ev: InputEvent) -> void:
	var jb := ev as InputEventJoypadButton
	var src := ("b%d@%d" % [jb.button_index, ev.device]) if jb else ("a%d@%d" % [(ev as InputEventJoypadMotion).axis, ev.device])
	if src == _nav_src:
		if not ev.is_action_pressed(_nav):
			_nav = &""
			_nav_src = ""
		return
	if (jb and not jb.pressed) or not _listen.is_empty():
		return
	for d in NAV_DIRS:
		if ev.is_action_pressed(d):
			_nav = d
			_nav_src = src
			_nav_next = Time.get_ticks_msec() + REPEAT_DELAY
			return


## One more step of the held direction, as an action event, for the focused list, grid or menu
## (not a slider or a tab bar, which repeat on their own, nor a text field being typed in).
func _repeat_nav() -> void:
	if not _listen.is_empty() or not _focused:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not f.is_visible_in_tree() or f is Slider or f is TabBar \
			or (f is LineEdit and (f as LineEdit).is_editing()):
		return
	for down in [true, false]:
		var a := InputEventAction.new()
		a.action = _nav
		a.pressed = down
		a.strength = 1.0 if down else 0.0
		Input.parse_input_event(a)


## The focus safety net: with nothing focused (the focused control was hidden or freed) the D-pad,
## the stick, the arrows and confirm do nothing in Godot, so they give the focus to the topmost
## screen that takes it (SCREEN_GROUP, latest in the tree first). That press only shows the focus.
## A stick counts only as it crosses the threshold, not for every motion past it (steering).
func _unhandled_input(event: InputEvent) -> void:
	if not _listen.is_empty() or event is InputEventMouse or not event.is_pressed() or event.is_echo():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var motion := event is InputEventJoypadMotion
	var nav := false
	for a in NAV_ACTIONS:
		if event.is_action_pressed(a) and (not motion or Input.is_action_just_pressed(a)):
			nav = true
			break
	if not nav:
		return
	var screens := get_tree().get_nodes_in_group(SCREEN_GROUP)
	for i in range(screens.size() - 1, -1, -1):
		var s: Node = screens[i]
		if s.has_method("focus_default") and s.call("focus_default"):
			get_viewport().set_input_as_handled()
			return


# ---------------------------------------------------------------- icons and text
## The events bound to an action for a pad (true) or for the keyboard and mouse (false), in the
## InputMap's order (the binding slots' order; ui_* actions work too).
func action_events(action: String, pad: bool) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) == pad:
			out.append(ev)
	return out


## The binding a prompt shows for an action in a style ("" = the active one): its first binding
## for that kind of device, or the other kind's when it has none (chat shows its key on a pad).
func prompt_event(action: String, style_id := "") -> InputEvent:
	var pad := (style_id if style_id != "" else _style) != KEYBOARD
	var evs := action_events(action, pad)
	if evs.is_empty():
		evs = action_events(action, not pad)
	return evs[0] if not evs.is_empty() else null


## The icon of an action's binding for the active device (or `style_id`), `px` high; null when
## it has no binding or the binding has no icon (show action_text then).
func action_icon(action: String, px := 32.0, style_id := "") -> Texture2D:
	return event_icon(prompt_event(action, style_id), px, style_id)


## The name of an action's binding for the active device ("W", "SHIFT", "RT", "CROSS", "LS LEFT").
func action_text(action: String, style_id := "") -> String:
	return event_text(prompt_event(action, style_id), _pad_style_or(style_id))


func event_icon(ev: InputEvent, px := 32.0, style_id := "") -> Texture2D:
	return icon(icon_name(ev, _pad_style_or(style_id)), px) if ev else null


## A binding spec's icon (InputBindings): key specs as keys, pad specs in the pad style.
func spec_icon(spec: String, px := 32.0, style_id := "") -> Texture2D:
	return event_icon(InputBindings.event_of(spec), px, style_id)


func spec_text(spec: String, style_id := "") -> String:
	var ev := InputBindings.event_of(spec)
	return event_text(ev, _pad_style_or(style_id)) if ev else ""


func _pad_style_or(style_id: String) -> String:
	return style_id if style_id in PAD_STYLES else pad_style()


## An icon by its Kenney file name (stem), `px` high, cached; null when there is no such file.
func icon(stem: String, px := 32.0) -> Texture2D:
	if stem == "":
		return null
	var key := "%s@%d" % [stem, roundi(px)]
	if _icons.has(key):
		return _icons[key]
	var tex: Texture2D = null
	var path := icon_path(stem)
	if path != "" and FileAccess.file_exists(path):
		var src := FileAccess.get_file_as_string(path)
		if src != "":
			tex = DPITexture.create_from_string(src.replace(KENNEY_RED, ACCENT), maxf(px, 4.0) / 64.0)
	_icons[key] = tex
	return tex


## The opaque part of an icon as a share of its 64x64 canvas (Kenney leaves a margin, more on the
## flat shoulder buttons), cached: where to put the texture so the glyph itself fills a box.
## Rect2(0, 0, 1, 1) for a missing or empty file.
func glyph_box(stem: String) -> Rect2:
	if _glyph_boxes.has(stem):
		return _glyph_boxes[stem]
	var box := Rect2(0, 0, 1, 1)
	var path := icon_path(stem)
	if path != "" and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 1.0) == OK and not img.is_empty():
			var used := img.get_used_rect()
			if used.has_area():
				box = Rect2(Vector2(used.position) / 64.0, Vector2(used.size) / 64.0)
	_glyph_boxes[stem] = box
	return box


static func icon_path(stem: String) -> String:
	for p in ICON_FOLDERS:
		if stem.begins_with(p):
			return ICON_DIR + ICON_FOLDERS[p] + "/" + stem + ".svg"
	return ""


## One icon for both ways of a stick or the D-pad along the same line (steering: the left stick
## pushed sideways instead of two left-stick icons that differ by a 3 px nub); "" when `neg` and
## `pos` are not such a pair ("a0-" / "a0+": the left stick, "a2-" / "a2+": the right one,
## "b13" / "b14": the D-pad).
static func pair_stem(neg: String, pos: String, pad_style_id: String) -> String:
	var fam := _icon_set(pad_style_id if pad_style_id in PAD_STYLES else "xbox")
	match "%s|%s" % [neg, pos]:
		"a0-|a0+":
			return "generic_stick_horizontal" if fam == "generic" else "%s_stick_l_horizontal" % fam
		"a2-|a2+":
			return "generic_stick_horizontal" if fam == "generic" else "%s_stick_r_horizontal" % fam
		"b13|b14":
			return "%s_dpad_horizontal" % ("xbox" if fam == "generic" else fam)
	return ""


## The icon file name (stem) for an input event in a pad style, "" when there is none.
static func icon_name(ev: InputEvent, pad_style_id: String) -> String:
	if ev is InputEventKey:
		var code := _key_label(ev as InputEventKey)
		return "keyboard_" + _key_stem(code) if _key_stem(code) != "" else ""
	if ev is InputEventMouseButton:
		return MOUSE_ICONS.get((ev as InputEventMouseButton).button_index, "")
	var st := pad_style_id if pad_style_id in PAD_STYLES else "xbox"
	var fam := _icon_set(st)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return SHOULDERS[fam][2]
			JOY_AXIS_TRIGGER_RIGHT:
				return SHOULDERS[fam][3]
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				var d := _axis_dir(m)
				if fam == "generic":
					return "generic_stick_" + d
				return "%s_stick_%s_%s" % [fam, "l" if m.axis <= JOY_AXIS_LEFT_Y else "r", d]
		return ""
	if ev is InputEventJoypadButton:
		var bi := (ev as InputEventJoypadButton).button_index
		if bi >= JOY_BUTTON_A and bi <= JOY_BUTTON_Y:
			return FACE[fam][bi]
		match bi:
			JOY_BUTTON_BACK:
				return MENU_BUTTONS[st][0]
			JOY_BUTTON_START:
				return MENU_BUTTONS[st][1]
			JOY_BUTTON_LEFT_SHOULDER:
				return SHOULDERS[fam][0]
			JOY_BUTTON_RIGHT_SHOULDER:
				return SHOULDERS[fam][1]
			JOY_BUTTON_LEFT_STICK:
				return SHOULDERS[fam][4]
			JOY_BUTTON_RIGHT_STICK:
				return SHOULDERS[fam][5]
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				return "%s_dpad_%s" % ["xbox" if fam == "generic" else fam, DIRS[bi - JOY_BUTTON_DPAD_UP]]
			JOY_BUTTON_PADDLE1, JOY_BUTTON_PADDLE2, JOY_BUTTON_PADDLE3, JOY_BUTTON_PADDLE4:
				# (Kenney's Elite paddles are thin slivers at prompt size: every family shows a P1..P4 keycap)
				return ""
			JOY_BUTTON_TOUCHPAD:
				return {"ps4": "playstation4_touchpad_press", "ps5": "playstation5_touchpad_press"}.get(st, "")
	return ""


## A short name for an input event in a pad style: "W", "SHIFT", "LEFT CLICK", "RT", "CROSS",
## "LS LEFT", "D-PAD UP" ("" for null).
static func event_text(ev: InputEvent, pad_style_id: String) -> String:
	if ev == null:
		return ""
	if ev is InputEventKey:
		var code := _key_label(ev as InputEventKey)
		return KEY_TEXT.get(code, OS.get_keycode_string(code).to_upper())
	if ev is InputEventMouseButton:
		var mb := (ev as InputEventMouseButton).button_index
		return MOUSE_TEXT.get(mb, "MOUSE %d" % mb)
	var st := pad_style_id if pad_style_id in PAD_STYLES else "xbox"
	var fam := _icon_set(st)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return SHOULDER_TEXT[fam][2]
			JOY_AXIS_TRIGGER_RIGHT:
				return SHOULDER_TEXT[fam][3]
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				return "%s %s" % ["LS" if m.axis <= JOY_AXIS_LEFT_Y else "RS", _axis_dir(m).to_upper()]
		return "AXIS %d%s" % [m.axis, "+" if m.axis_value > 0.0 else "-"]
	if ev is InputEventJoypadButton:
		var bi := (ev as InputEventJoypadButton).button_index
		if bi >= JOY_BUTTON_A and bi <= JOY_BUTTON_Y:
			return FACE_TEXT[fam][bi]
		match bi:
			JOY_BUTTON_BACK:
				return MENU_TEXT[st][0]
			JOY_BUTTON_START:
				return MENU_TEXT[st][1]
			JOY_BUTTON_GUIDE:
				return "GUIDE"
			JOY_BUTTON_LEFT_SHOULDER:
				return SHOULDER_TEXT[fam][0]
			JOY_BUTTON_RIGHT_SHOULDER:
				return SHOULDER_TEXT[fam][1]
			JOY_BUTTON_LEFT_STICK:
				return SHOULDER_TEXT[fam][4]
			JOY_BUTTON_RIGHT_STICK:
				return SHOULDER_TEXT[fam][5]
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				return "D-PAD " + DIRS[bi - JOY_BUTTON_DPAD_UP].to_upper()
			JOY_BUTTON_PADDLE1, JOY_BUTTON_PADDLE2, JOY_BUTTON_PADDLE3, JOY_BUTTON_PADDLE4:
				return "P%d" % [1, 3, 2, 4][bi - JOY_BUTTON_PADDLE1]
			JOY_BUTTON_TOUCHPAD:
				return "TOUCHPAD"
		return "BUTTON %d" % (bi + 1)
	return ""


## The icon set a pad style draws from (FACE / SHOULDERS keys).
static func _icon_set(st: String) -> String:
	match st:
		"xbox", "xbox360":
			return "xbox"
		"ps3", "ps4", "ps5":
			return "playstation"
		"switch", "steamdeck", "generic":
			return st
	return "xbox"


static func _axis_dir(m: InputEventJoypadMotion) -> String:
	var neg := m.axis_value < 0.0
	if m.axis == JOY_AXIS_LEFT_X or m.axis == JOY_AXIS_RIGHT_X:
		return "left" if neg else "right"
	return "up" if neg else "down"


## What the key is labelled on the player's keyboard layout (AZERTY's Z for the W position). A
## letter Kenney has no icon for (Cyrillic, Greek...) gives the key's position instead: those
## keyboards print the Latin letter too, and players know WASD by it.
static func _key_label(ke: InputEventKey) -> Key:
	var phys := ke.physical_keycode if ke.physical_keycode != KEY_NONE else ke.keycode
	if phys == KEY_NONE or DisplayServer.get_name() == "headless":
		return phys
	var lbl := DisplayServer.keyboard_get_label_from_physical(phys)
	if lbl == KEY_NONE or (lbl > 127 and lbl < KEY_SPECIAL and _key_stem(lbl) == ""):
		return phys
	return lbl


## Kenney's name for a key ("" when it has no icon for it; the numpad's digits have none on purpose:
## their NUM 0..NUM 9 keycaps never pass for the top row's digits).
static func _key_stem(code: Key) -> String:
	if code >= KEY_A and code <= KEY_Z:
		return char(code).to_lower()
	if code >= KEY_0 and code <= KEY_9:
		return char(code)
	if code >= KEY_F1 and code <= KEY_F12:
		return "f%d" % (code - KEY_F1 + 1)
	return KEY_ICONS.get(code, "")


## Splits a prompt into text and actions: "STUCK? PRESS {respawn} TO CALL THE CRANE" ->
## ["STUCK? PRESS ", {"action": "respawn"}, " TO CALL THE CRANE"]. A {word} that is not an
## InputMap action stays text.
static func parse_prompt(text: String) -> Array:
	var out := []
	var buf := ""
	var i := 0
	while i < text.length():
		var open := text.find("{", i)
		var close := text.find("}", open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			buf += text.substr(i)
			break
		var act := text.substr(open + 1, close - open - 1)
		buf += text.substr(i, open - i)
		if InputMap.has_action(act):
			if buf != "":
				out.append(buf)
			buf = ""
			out.append({"action": act})
		else:
			buf += text.substr(open, close - open + 1)
		i = close + 1
	if buf != "":
		out.append(buf)
	return out


# ---------------------------------------------------------------- rumble
## A buzz on the pad the player is using: `weak` drives the high-frequency motor, `strong` the
## low one (0..1, times Game.settings["vibration"]), for `seconds`. Nothing happens on the keyboard,
## with vibration off, while the game is paused or in the background. A weaker buzz never cuts a
## stronger one short: while one runs, each motor keeps the stronger of the two.
## force: buzz the last used pad even while the keyboard or mouse is active, and while paused
## (OPTIONS > CONTROLLER shows the strength this way). A stronger buzz over a longer one plays for
## its own time (each motor at the stronger of the two), then the longer one goes on; a weaker
## one that outlasts the running buzz goes on after it the same way.
func rumble(weak: float, strong: float, seconds: float, force := false) -> void:
	var dev := _pad
	var amp := clampf(float(Game.settings.get("vibration", 0.7)), 0.0, 1.0)
	if dev < 0 or amp <= 0.0 or seconds <= 0.0 or not _focused:
		return
	if not force and (_kind != "pad" or get_tree().paused):
		return
	weak = clampf(weak * amp, 0.0, 1.0)
	strong = clampf(strong * amp, 0.0, 1.0)
	var now := Time.get_ticks_msec()
	var end := now + int(seconds * 1000.0)
	if now < _r_end and _r_dev == dev:
		if weak <= _r_weak and strong <= _r_strong:
			if end > _r_end and end > _r_after_end:
				_set_after(weak, strong, end)
			return
		if _r_end > end:
			_set_after(_r_weak, _r_strong, _r_end)
		weak = maxf(weak, _r_weak)
		strong = maxf(strong, _r_strong)
	else:
		_r_after_end = 0
	_start_rumble(dev, weak, strong, end, force)


func _set_after(weak: float, strong: float, end: int) -> void:
	_r_after_weak = weak
	_r_after_strong = strong
	_r_after_end = end


func _start_rumble(dev: int, weak: float, strong: float, end: int, force: bool) -> void:
	_r_dev = dev
	_r_weak = weak
	_r_strong = strong
	_r_end = end
	_r_forced = force
	Input.start_joy_vibration(dev, weak, strong, maxi(end - Time.get_ticks_msec(), 1) / 1000.0)


func stop_rumble() -> void:
	if _r_dev >= 0:
		Input.stop_joy_vibration(_r_dev)
	_r_end = 0
	_r_weak = 0.0
	_r_strong = 0.0
	_r_forced = false
	_r_after_end = 0


## The rumble playing now: Vector3(weak, strong, seconds left), zero when none.
func rumble_now() -> Vector3:
	var left := (_r_end - Time.get_ticks_msec()) / 1000.0
	return Vector3(_r_weak, _r_strong, left) if left > 0.0 else Vector3.ZERO


## The pad (the active one by default) has motors the game can drive.
func can_rumble(device := -1) -> bool:
	var d := device if device >= 0 else _pad
	return d >= 0 and d in Input.get_connected_joypads() and Input.has_joy_vibration(d)


# ---------------------------------------------------------------- rebinding
## Waits for the next input to bind to slot `slot` of `action` in class `cls` (InputBindings.KEY:
## a key, or a mouse button but the left one and the wheel; InputBindings.PAD: a pad button, or a
## stick or trigger pushed well away from where it rested). Esc, a left click, a pad's Start or
## `timeout` seconds cancel it (and in a key slot any pad button; in a pad slot other keys are
## ignored). While it listens it takes every key, button and axis, so nothing else reacts. With
## `apply` the input is bound at once (InputBindings.set_slot: a clash swaps the two slots). Ends
## with rebind_captured or rebind_cancelled. False: the slot can not be changed.
func listen(action: String, cls: String, slot: int, timeout := 5.0, apply := true) -> bool:
	if action not in InputBindings.ACTIONS or slot < 0 or slot >= InputBindings.slot_count(action, cls) \
			or InputBindings.is_locked(action, cls, slot):
		return false
	if not _listen.is_empty():
		_cancel_listen()
	var now := Time.get_ticks_msec()
	_listen = {"action": action, "cls": cls, "slot": slot, "apply": apply, "armed": now + int(LISTEN_ARM * 1000.0),
		"end": now + int(timeout * 1000.0)}
	_rest.clear()
	_arm.clear()
	var devs: Array = Input.get_connected_joypads()
	for d in _pads:
		if d not in devs:
			devs.append(d)
	for d in devs:
		for ax in JOY_AXIS_MAX:
			var v := Input.get_joy_axis(d, ax)
			var rest := 0.0 if _rests_at_zero(d, ax) else v
			_rest[d * 16 + ax] = rest
			_arm[d * 16 + ax] = absf(v - rest) < AXIS_NEAR
	return true


## A pad's stick or trigger that rests at 0 (SDL centres a known pad's sticks and puts its triggers
## at 0; an event made in code counts as one); a joystick SDL does not know rests anywhere.
static func _rests_at_zero(device: int, axis: int) -> bool:
	return axis < JOY_AXIS_SDL_MAX and (Input.is_joy_known(device) or device not in Input.get_connected_joypads())


func is_listening() -> bool:
	return not _listen.is_empty()


## What listen() waits for: {action, cls, slot}, {} when it is not listening.
func listening_for() -> Dictionary:
	if _listen.is_empty():
		return {}
	return {"action": _listen["action"], "cls": _listen["cls"], "slot": _listen["slot"]}


## Seconds before listen() gives up (0 when it is not listening).
func listen_time_left() -> float:
	return maxf((int(_listen["end"]) - Time.get_ticks_msec()) / 1000.0, 0.0) if not _listen.is_empty() else 0.0


func cancel_listen() -> void:
	if not _listen.is_empty():
		_cancel_listen()


func _input(event: InputEvent) -> void:
	if _listen.is_empty() or event is InputEventMouseMotion:
		return
	var take := event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
		or event is InputEventJoypadMotion
	if not take:
		return
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() < int(_listen["armed"]):
		return
	var pad: bool = _listen["cls"] == InputBindings.PAD
	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.physical_keycode == KEY_ESCAPE or ke.keycode == KEY_ESCAPE:
			_cancel_listen()
		elif not pad:
			_capture(event)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_cancel_listen()
		elif not pad and InputBindings.spec_of(mb) != "":
			_capture(event)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		if not pad or jb.button_index == JOY_BUTTON_START:
			_cancel_listen()
		elif not InputBindings.is_reserved(InputBindings.spec_of(jb)):
			_capture(event)
	elif event is InputEventJoypadMotion and pad:
		# an axis held when the slot opened (a trigger still down) must come back near its rest
		# first, so letting it go is never bound as a push the other way; a pad's trigger only
		# pulls one way
		var m := event as InputEventJoypadMotion
		var key := m.device * 16 + m.axis
		var zero := _rests_at_zero(m.device, m.axis)
		if not _rest.has(key):
			_rest[key] = 0.0 if zero else m.axis_value
		var off := m.axis_value - float(_rest[key])
		if not _arm.get(key, true):
			if absf(off) < AXIS_NEAR:
				_arm[key] = true
			return
		if absf(off) > AXIS_CAPTURE:
			if off < 0.0 and zero and (m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT):
				return
			var jm := InputEventJoypadMotion.new()
			jm.axis = m.axis
			jm.axis_value = 1.0 if off > 0.0 else -1.0
			_capture(jm)


func _capture(event: InputEvent) -> void:
	var l := _listen
	_listen = {}
	var spec := InputBindings.spec_of(event)
	var ev := InputBindings.event_of(spec)
	var result := {}
	if l["apply"]:
		result = InputBindings.set_slot(l["action"], l["cls"], l["slot"], spec)
	rebind_captured.emit(l["action"], l["cls"], l["slot"], ev, result)


func _cancel_listen() -> void:
	var l := _listen
	_listen = {}
	rebind_cancelled.emit(l["action"], l["cls"], l["slot"])
