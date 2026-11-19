class_name InputBindings
extends RefCounted
## The game's actions and what drives them. Built into the InputMap at startup (InputPrompts) and
## again on every change in OPTIONS (KEYBOARD & MOUSE, CONTROLLER). A binding is kept as a short
## string, a "spec":
##   "k<physical keycode>"  a key (where it sits on the keyboard, so WASD stays WASD on AZERTY)
##   "m<mouse button>"      a mouse button
##   "b<pad button>"        a pad button, by position (JOY_BUTTON_A = the bottom face button)
##   "a<axis>+" / "a<axis>-"  a stick or trigger pushed that way (JOY_AXIS_*)
## Each action has KEY_SLOTS keyboard slots and PAD_SLOTS pad slots ("" = empty). The player's
## changes live in Game.settings["bindings"] as {action: {"key": [specs], "pad": [specs]}}, only
## for the classes that differ from defaults(). Every event matches any device (device -1):
## code-made events default to one device id, which only the first pad would drive. With a
## joystick SDL does not know plugged in (a wheel, a flight stick), sticks and triggers count
## only on the known pads and the active one (InputPrompts.axis_devs).

const ALL_DEVICES := -1
const KEY := "key"  # slot class: keyboard and mouse
const PAD := "pad"  # slot class: gamepad
const KEY_SLOTS := 3  # Use item came with three keys (E, Ctrl, Enter)
const PAD_SLOTS := 2
## Gameplay actions in the order OPTIONS lists them (KEYBOARD & MOUSE numbers them in this order).
const ACTIONS: Array[String] = ["accelerate", "brake", "steer_left", "steer_right", "drift", "use_item",
	"look_back", "respawn", "pause", "chat"]
const TITLES := {"accelerate": "Accelerate", "brake": "Brake / reverse", "steer_left": "Steer left",
	"steer_right": "Steer right", "drift": "Hop & drift", "use_item": "Use item", "look_back": "Look behind",
	"respawn": "Call for help", "pause": "Pause / menu", "chat": "Chat (online)"}
## Actions that must keep at least one binding in each class they have (clear_slot refuses).
const REQUIRED: Array[String] = ["accelerate", "brake", "steer_left", "steer_right", "pause"]
## Actions with no pad slots (typing needs a keyboard anyway).
const KEYBOARD_ONLY: Array[String] = ["chat"]
const STEER: Array[String] = ["steer_left", "steer_right"]
const DEADZONE := 0.2  # every action but steering (Game.settings["stick_deadzone"])


static func key_spec(key: Key) -> String:
	return "k%d" % key


static func button_spec(button: JoyButton) -> String:
	return "b%d" % button


static func axis_spec(axis: JoyAxis, dir: int) -> String:
	return "a%d%s" % [axis, "+" if dir > 0 else "-"]


## The bindings a new player gets.
static func defaults() -> Dictionary:
	return {
		"accelerate": {KEY: [key_spec(KEY_W), key_spec(KEY_UP), ""],
			PAD: [button_spec(JOY_BUTTON_A), axis_spec(JOY_AXIS_TRIGGER_RIGHT, 1)]},
		"brake": {KEY: [key_spec(KEY_S), key_spec(KEY_DOWN), ""],
			PAD: [button_spec(JOY_BUTTON_X), axis_spec(JOY_AXIS_TRIGGER_LEFT, 1)]},
		"steer_left": {KEY: [key_spec(KEY_A), key_spec(KEY_LEFT), ""],
			PAD: [axis_spec(JOY_AXIS_LEFT_X, -1), button_spec(JOY_BUTTON_DPAD_LEFT)]},
		"steer_right": {KEY: [key_spec(KEY_D), key_spec(KEY_RIGHT), ""],
			PAD: [axis_spec(JOY_AXIS_LEFT_X, 1), button_spec(JOY_BUTTON_DPAD_RIGHT)]},
		"drift": {KEY: [key_spec(KEY_SHIFT), key_spec(KEY_SPACE), ""], PAD: [button_spec(JOY_BUTTON_RIGHT_SHOULDER), ""]},
		"use_item": {KEY: [key_spec(KEY_E), key_spec(KEY_CTRL), key_spec(KEY_ENTER)],
			PAD: [button_spec(JOY_BUTTON_LEFT_SHOULDER), button_spec(JOY_BUTTON_B)]},
		"look_back": {KEY: [key_spec(KEY_C), "", ""], PAD: [button_spec(JOY_BUTTON_Y), ""]},
		"respawn": {KEY: [key_spec(KEY_R), "", ""], PAD: [button_spec(JOY_BUTTON_BACK), ""]},
		"pause": {KEY: [key_spec(KEY_ESCAPE), key_spec(KEY_P), ""], PAD: [button_spec(JOY_BUTTON_START), ""]},
		"chat": {KEY: [key_spec(KEY_Y), key_spec(KEY_T), ""], PAD: []},
	}


## Esc and Start always pause (and cancel a rebind), so they can't be bound to anything else;
## the Guide / Home button belongs to Windows and Steam, and Share / Capture / the DualSense mic
## button to the system too.
static func is_reserved(spec: String) -> bool:
	return spec in [key_spec(KEY_ESCAPE), button_spec(JOY_BUTTON_START), button_spec(JOY_BUTTON_GUIDE),
		button_spec(JOY_BUTTON_MISC1)]


## Pause keeps Esc in its first keyboard slot and Start in its first pad slot.
static func is_locked(action: String, _cls: String, slot: int) -> bool:
	return action == "pause" and slot == 0


## A pad's bottom and right face buttons confirm and go back in every menu (Nintendo pads swap
## them), and a pause press is BACK in a dialog and START in the race setup: they never pause.
static func refused(action: String, cls: String, spec: String) -> bool:
	return action == "pause" and cls == PAD and spec in [button_spec(JOY_BUTTON_A), button_spec(JOY_BUTTON_B)]


static func slot_count(action: String, cls: String) -> int:
	if cls == PAD:
		return 0 if action in KEYBOARD_ONLY else PAD_SLOTS
	return KEY_SLOTS


## "key" for a keyboard or mouse spec, "pad" for a pad one, "" for anything else.
static func class_of(spec: String) -> String:
	if spec.begins_with("k") or spec.begins_with("m"):
		return KEY
	if spec.begins_with("b") or spec.begins_with("a"):
		return PAD
	return ""


## The spec of an input event ("" when it can not be a binding: the mouse wheel, a stick at rest).
static func spec_of(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var ke := ev as InputEventKey
		var code := ke.physical_keycode if ke.physical_keycode != KEY_NONE else ke.keycode
		return key_spec(code) if code != KEY_NONE else ""
	if ev is InputEventMouseButton:
		var mb := (ev as InputEventMouseButton).button_index
		return "" if mb in [MOUSE_BUTTON_NONE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] else "m%d" % mb
	if ev is InputEventJoypadButton:
		return button_spec((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		return "" if is_zero_approx(jm.axis_value) else axis_spec(jm.axis, 1 if jm.axis_value > 0.0 else -1)
	return ""


## The InputMap event for a spec (null if the spec is not valid). It matches any device: a real
## keyboard, mouse and pad each report their own device id.
static func event_of(spec: String) -> InputEvent:
	if spec.length() < 2:
		return null
	var body := spec.substr(1)
	match spec[0]:
		"k":
			if not body.is_valid_int() or int(body) <= 0:
				return null
			var ke := InputEventKey.new()
			ke.physical_keycode = int(body) as Key
			ke.device = ALL_DEVICES
			return ke
		"m":
			if not body.is_valid_int() or int(body) <= 0:
				return null
			var mb := InputEventMouseButton.new()
			mb.button_index = int(body) as MouseButton
			mb.device = ALL_DEVICES
			return mb
		"b":
			if not body.is_valid_int() or int(body) < 0 or int(body) >= JOY_BUTTON_MAX:
				return null
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(body) as JoyButton
			jb.device = ALL_DEVICES
			return jb
		"a":
			var dir := body.right(1)
			var axis := body.left(-1)
			if dir not in ["+", "-"] or not axis.is_valid_int() or int(axis) < 0 or int(axis) >= JOY_AXIS_MAX:
				return null
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(axis) as JoyAxis
			jm.axis_value = 1.0 if dir == "+" else -1.0
			jm.device = ALL_DEVICES
			return jm
	return null


## The player's slots for an action and class (their changes over the defaults), slot_count long.
static func slots(action: String, cls: String) -> Array:
	return resolve(_overrides()).get(action, {}).get(cls, [])


## Every action's slots of one class, {action: [specs]}: one resolve() for all of them (slots()
## resolves the whole table for each action).
static func all_slots(cls: String) -> Dictionary:
	var t := resolve(_overrides())
	var out := {}
	for act in ACTIONS:
		out[act] = t[act][cls]
	return out


static func get_slot(action: String, cls: String, slot: int) -> String:
	var s := slots(action, cls)
	return s[slot] if slot >= 0 and slot < s.size() else ""


## Every bound spec of an action (both classes), in slot order.
static func specs(action: String) -> Array[String]:
	var out: Array[String] = []
	for cls in [KEY, PAD]:
		for s in slots(action, cls):
			if s != "":
				out.append(s)
	return out


## Which action and slot hold `spec` (in its class): [action, slot], or [] when it is free.
static func find(spec: String) -> Array:
	var cls := class_of(spec)
	var t := resolve(_overrides())
	for act in ACTIONS:
		var i: int = (t[act][cls] as Array).find(spec) if cls != "" else -1
		if i >= 0:
			return [act, i]
	return []


## Binds `spec` to a slot. If another slot of the same class already has it (another action's,
## or this action's other one), the two swap: that slot gets this slot's old binding (which may be
## empty). Applies at once. Returns {"ok", "spec", "moved_action", "moved_slot", "moved_spec",
## "dropped_spec", "why"}: moved_* name the slot that took the old binding ("" / -1 when nothing
## moved); dropped_spec is an old binding that slot may not take (a menu button for pause: the
## slot is left empty and the button is free). Refused (ok false, nothing changes): a locked slot,
## a reserved input, a spec of the other class, a menu button for pause (why "menus").
static func set_slot(action: String, cls: String, slot: int, spec: String) -> Dictionary:
	var res := {"ok": false, "spec": spec, "moved_action": "", "moved_slot": -1, "moved_spec": "", "dropped_spec": "",
		"why": ""}
	if action not in ACTIONS or slot < 0 or slot >= slot_count(action, cls) or is_locked(action, cls, slot) \
			or is_reserved(spec) or class_of(spec) != cls or event_of(spec) == null:
		return res
	if refused(action, cls, spec):
		res["why"] = "menus"
		return res
	var t := resolve(_overrides())
	var old: String = t[action][cls][slot]
	res["ok"] = true
	if old == spec:
		return res
	var hit := find(spec)
	t[action][cls][slot] = spec
	if not hit.is_empty():
		var back := "" if refused(hit[0], cls, old) else old
		t[hit[0]][cls][hit[1]] = back
		res["moved_action"] = hit[0]
		res["moved_slot"] = hit[1]
		res["moved_spec"] = back
		if back != old:
			res["dropped_spec"] = old
	_store(t)
	return res


## Empties a slot. Refused (false) for a locked slot, or when it holds the last binding a
## REQUIRED action has in that class.
static func clear_slot(action: String, cls: String, slot: int) -> bool:
	if action not in ACTIONS or slot < 0 or slot >= slot_count(action, cls) or is_locked(action, cls, slot):
		return false
	var t := resolve(_overrides())
	var s: Array = t[action][cls]
	if s[slot] == "":
		return true
	if action in REQUIRED and s.count("") == s.size() - 1:
		return false
	s[slot] = ""
	_store(t)
	return true


## Back to defaults(): one action, or every action with "". An action reset on its own takes
## its default inputs back from whoever got them in a swap; that slot gets its own default again
## when it is free, else it is left empty.
static func reset(action := "") -> void:
	if action == "":
		Game.settings["bindings"] = {}
		apply()
		return
	if action not in ACTIONS:
		return
	var d := defaults()
	var t := resolve(_overrides())
	t[action] = d[action].duplicate(true)
	for act in ACTIONS:
		if act == action:
			continue
		for cls in [KEY, PAD]:
			var s: Array = t[act][cls]
			for i in s.size():
				if s[i] != "" and s[i] in d[action][cls]:
					var own: String = d[act][cls][i] if i < d[act][cls].size() else ""
					s[i] = own if own != "" and not _held(t, own, cls) else ""
	_store(t)


## REQUIRED actions left with no binding in a class: [[action, class], ...] (a swap can do that).
static func missing() -> Array:
	var out := []
	var t := resolve(_overrides())
	for act in REQUIRED:
		for cls in [KEY, PAD]:
			var s: Array = t[act][cls]
			if not s.is_empty() and s.count("") == s.size():
				out.append([act, cls])
	return out


# ---------------------------------------------------------------- layouts (presets)
## Ready-made layouts (OPTIONS: LAYOUT), by class, in menu order: every action's slots, slot_count long.
## KEY: physical keycodes (k<code>); PAD: positional buttons (b0 = the bottom face button) and axes.
const PRESETS := {
	KEY: {
		"wasd": {  # = defaults()
			"accelerate": ["k87", "k4194320", ""],  # W, Up
			"brake": ["k83", "k4194322", ""],  # S, Down
			"steer_left": ["k65", "k4194319", ""],  # A, Left
			"steer_right": ["k68", "k4194321", ""],  # D, Right
			"drift": ["k4194325", "k32", ""],  # Shift, Space
			"use_item": ["k69", "k4194326", "k4194309"],  # E, Ctrl, Enter
			"look_back": ["k67", "", ""],  # C
			"respawn": ["k82", "", ""],  # R
			"pause": ["k4194305", "k80", ""],  # Esc (locked), P
			"chat": ["k89", "k84", ""],  # Y, T
		},
		"arrows": {  # the right hand on the arrows, the left on Space, Shift, Ctrl, X, C, R
			"accelerate": ["k4194320", "", ""],  # Up
			"brake": ["k4194322", "", ""],  # Down
			"steer_left": ["k4194319", "", ""],  # Left
			"steer_right": ["k4194321", "", ""],  # Right
			"drift": ["k32", "k4194325", ""],  # Space, Shift
			"use_item": ["k4194326", "k88", ""],  # Ctrl, X
			"look_back": ["k67", "", ""],  # C
			"respawn": ["k82", "", ""],  # R
			"pause": ["k4194305", "k80", ""],  # Esc, P
			"chat": ["k89", "k84", ""],  # Y, T
		},
		"one_hand": {  # everything round the arrows (right Shift / Ctrl: a binding takes either side)
			"accelerate": ["k4194320", "", ""],  # Up
			"brake": ["k4194322", "", ""],  # Down
			"steer_left": ["k4194319", "", ""],  # Left
			"steer_right": ["k4194321", "", ""],  # Right
			"drift": ["k4194325", "", ""],  # Shift
			"use_item": ["k4194326", "k4194309", ""],  # Ctrl, Enter
			"look_back": ["k4194318", "", ""],  # End
			"respawn": ["k4194324", "", ""],  # Page Down
			"pause": ["k4194305", "k80", ""],  # Esc, P
			"chat": ["k89", "k84", ""],  # Y, T
		},
	},
	PAD: {
		"standard": {  # = defaults()
			"accelerate": ["b0", "a5+"],  # A, RT
			"brake": ["b2", "a4+"],  # X, LT
			"steer_left": ["a0-", "b13"],  # LS left, D-pad left
			"steer_right": ["a0+", "b14"],  # LS right, D-pad right
			"drift": ["b10", ""],  # RB
			"use_item": ["b9", "b1"],  # LB, B
			"look_back": ["b3", ""],  # Y
			"respawn": ["b4", ""],  # Back / View
			"pause": ["b6", ""],  # Start (locked)
			"chat": [],
		},
		"triggers": {  # gas and brake on the triggers only; the bottom button hops
			"accelerate": ["a5+", ""],  # RT
			"brake": ["a4+", ""],  # LT
			"steer_left": ["a0-", "b13"],
			"steer_right": ["a0+", "b14"],
			"drift": ["b0", "b10"],  # A, RB
			"use_item": ["b1", "b9"],  # B, LB
			"look_back": ["b3", ""],  # Y
			"respawn": ["b4", ""],
			"pause": ["b6", ""],
			"chat": [],
		},
		"classic": {  # Mario Kart's buttons by position: the right face button drives, the bottom one brakes
			"accelerate": ["b1", ""],  # east: Nintendo A, Xbox B, Circle
			"brake": ["b0", ""],  # south: Nintendo B, Xbox A, Cross
			"steer_left": ["a0-", "b13"],
			"steer_right": ["a0+", "b14"],
			"drift": ["b10", "a5+"],  # R, ZR
			"use_item": ["b9", "a4+"],  # L, ZL
			"look_back": ["b3", ""],  # north: Nintendo X, Xbox Y, Triangle
			"respawn": ["b4", ""],
			"pause": ["b6", ""],
			"chat": [],
		},
		"lefty": {  # STANDARD mirrored: steer with the right stick, drive with the D-pad and LT
			"accelerate": ["b12", "a4+"],  # D-pad down, LT
			"brake": ["b14", "a5+"],  # D-pad right, RT
			"steer_left": ["a2-", ""],  # RS left
			"steer_right": ["a2+", ""],  # RS right
			"drift": ["b9", ""],  # LB
			"use_item": ["b10", "b13"],  # RB, D-pad left
			"look_back": ["b11", ""],  # D-pad up
			"respawn": ["b4", ""],  # Back stays (Start is pause's)
			"pause": ["b6", ""],
			"chat": [],
		},
	},
}
const PRESET_TITLES := {"wasd": "WASD", "arrows": "ARROWS", "one_hand": "ONE HAND", "standard": "STANDARD",
	"triggers": "TRIGGERS", "classic": "CLASSIC KART", "lefty": "LEFT-HANDED", "custom": "CUSTOM"}
const PRESET_NOTES := {
	"standard": "The bottom button or the right trigger drives; the stick or the D-pad steers.",
	"triggers": "Gas and brake on the triggers; the bottom button hops.",
	"classic": "The right face button drives and the bottom one brakes, as in classic kart games.",
	"lefty": "Steer with the right stick; drive with the D-pad and the left trigger.",
	"wasd": "WASD or the arrows drive; the actions sit round the left hand.",
	"arrows": "The arrows drive; Space, Shift, Ctrl, X, C and R do the rest.",
	"one_hand": "Everything round the arrows: Shift, Ctrl, Enter, End and Page Down.",
	"custom": "Your own layout.",
}
## Short action names for the compact diagram (pause panel).
const SHORT_TITLES := {"accelerate": "ACCELERATE", "brake": "BRAKE", "steer_left": "STEER LEFT",
	"steer_right": "STEER RIGHT", "drift": "DRIFT", "use_item": "ITEM", "look_back": "LOOK BACK", "respawn": "CALL HELP",
	"pause": "PAUSE", "chat": "CHAT"}


## The presets of a class in menu order.
static func preset_ids(cls: String) -> Array:
	return (PRESETS.get(cls, {}) as Dictionary).keys()


## Puts every slot of one class (KEY or PAD) to a preset, the way set_slot stores changes (only classes that
## differ from defaults() stay in Game.settings["bindings"]); the other class is not touched. False: no such
## preset, or a broken one (preset_problems).
static func apply_preset(cls: String, id: String) -> bool:
	var p = (PRESETS.get(cls, {}) as Dictionary).get(id)
	if not p is Dictionary:
		return false
	var bad := preset_problems(cls, id)
	if not bad.is_empty():
		push_error("InputBindings: preset %s/%s is broken: %s" % [cls, id, bad])
		return false
	var t := resolve(_overrides())
	for act in ACTIONS:
		if slot_count(act, cls) > 0:
			t[act][cls] = (p[act] as Array).duplicate()
	_store(t)
	return true


## The preset a class matches now, or "custom". Slot order does not matter (W, Up = Up, W).
static func preset_of(cls: String) -> String:
	var t := resolve(_overrides())
	for id in preset_ids(cls):
		var same := true
		for act in ACTIONS:
			if slot_count(act, cls) == 0:
				continue
			var a: Array = (t[act][cls] as Array).filter(func(s): return s != "")
			var b: Array = (PRESETS[cls][id][act] as Array).filter(func(s): return s != "")
			a.sort()
			b.sort()
			if a != b:
				same = false
				break
		if same:
			return id
	return "custom"


## What is wrong with a preset ([] = nothing): every action has slot_count slots; every spec is valid,
## of the class and in it once; pause's locked slot holds its default (Esc / Start) and nothing else
## is reserved; every REQUIRED action is bound.
static func preset_problems(cls: String, id: String) -> Array[String]:
	var out: Array[String] = []
	var p = (PRESETS.get(cls, {}) as Dictionary).get(id)
	if not p is Dictionary:
		out.append("no preset %s/%s" % [cls, id])
		return out
	var d := defaults()
	var used := []
	for act in ACTIONS:
		var s = (p as Dictionary).get(act)
		if not s is Array or (s as Array).size() != slot_count(act, cls):
			out.append("%s: %s slots, not %d" % [act, str((s as Array).size()) if s is Array else "no",
				slot_count(act, cls)])
			continue
		for i in (s as Array).size():
			var spec := str(s[i])
			if is_locked(act, cls, i):
				if spec != str(d[act][cls][i]):
					out.append("%s slot %d is locked to %s, not %s" % [act, i, d[act][cls][i], spec])
			elif spec != "" and (is_reserved(spec) or class_of(spec) != cls or event_of(spec) == null):
				out.append("%s: %s can not be bound here" % [act, spec])
			if spec == "":
				continue
			if spec in used:
				out.append("%s: %s is bound twice" % [act, spec])
			used.append(spec)
		if act in REQUIRED and (s as Array).count("") == (s as Array).size():
			out.append("%s: nothing bound" % act)
	return out


## Builds every action's events into the InputMap, with steering's dead zone and the menus' pad
## buttons (apply_ui, until InputPrompts decides the Nintendo swap). Sticks and triggers match
## the devices in InputPrompts.axis_devs ([-1]: any).
static func apply() -> void:
	var t := resolve(_overrides())
	var ip := _prompts()
	var axis_devs: Array = [ALL_DEVICES]
	if ip and ip.get("axis_devs") is Array and not (ip.get("axis_devs") as Array).is_empty():
		axis_devs = ip.get("axis_devs")
	var any_axis := axis_devs.size() == 1 and int(axis_devs[0]) == ALL_DEVICES
	for act in ACTIONS:
		if InputMap.has_action(act):
			InputMap.action_erase_events(act)
		else:
			InputMap.add_action(act, DEADZONE)
		for cls in [KEY, PAD]:
			for spec in t[act][cls]:
				var ev := event_of(spec)
				if ev == null:
					continue
				if ev is InputEventJoypadMotion and not any_axis:
					for dev in axis_devs:
						var one := ev.duplicate() as InputEventJoypadMotion
						one.device = dev
						InputMap.action_add_event(act, one)
				else:
					InputMap.action_add_event(act, ev)
	apply_deadzone()
	if not InputMap.has_action("ui_tab_prev"):
		apply_ui(false)
	if ip and ip.has_method("bindings_changed"):
		ip.call("bindings_changed")


## Adds `device`'s sticks and triggers to every action bound to one (InputPrompts.axis_devs: a
## joystick SDL does not know that the player started using). Adding lets go of nothing held.
static func add_axis_device(device: int) -> void:
	var t := resolve(_overrides())
	for act in ACTIONS:
		if not InputMap.has_action(act):
			continue
		for spec in t[act][PAD]:
			var ev := event_of(spec)
			if ev is InputEventJoypadMotion:
				ev.device = device
				if not InputMap.action_has_event(act, ev):
					InputMap.action_add_event(act, ev)


## Steering's dead zone from Game.settings["stick_deadzone"]: the share of the stick's travel that
## does nothing, so a worn stick does not steer by itself.
static func apply_deadzone() -> void:
	var dz := clampf(float(Game.settings.get("stick_deadzone", DEADZONE)), 0.05, 0.9)
	for act in STEER:
		if InputMap.has_action(act):
			InputMap.action_set_deadzone(act, dz)


## The menus' pad buttons: the bottom face button confirms (ui_accept) and the right one goes
## back (ui_cancel), or the other way round with `swap` (Nintendo pads print A on the right).
## LB / RB and Page Up / Page Down switch tabs (ui_tab_prev / ui_tab_next); the left face button
## and Delete / Backspace empty a binding slot in OPTIONS' binding tabs (ui_clear). Godot's own ui_*
## actions have no pad confirm or back at all.
static func apply_ui(swap: bool) -> void:
	for act in ["ui_accept", "ui_cancel"]:
		for ev in InputMap.action_get_events(act):
			if ev is InputEventJoypadButton:
				InputMap.action_erase_event(act, ev)
	InputMap.action_add_event("ui_accept", event_of(button_spec(JOY_BUTTON_B if swap else JOY_BUTTON_A)))
	InputMap.action_add_event("ui_cancel", event_of(button_spec(JOY_BUTTON_A if swap else JOY_BUTTON_B)))
	for t in [["ui_tab_prev", KEY_PAGEUP, JOY_BUTTON_LEFT_SHOULDER], ["ui_tab_next", KEY_PAGEDOWN, JOY_BUTTON_RIGHT_SHOULDER]]:
		if not InputMap.has_action(t[0]):
			InputMap.add_action(t[0], 0.5)
			InputMap.action_add_event(t[0], event_of(key_spec(t[1])))
			InputMap.action_add_event(t[0], event_of(button_spec(t[2])))
	if not InputMap.has_action("ui_clear"):
		InputMap.add_action("ui_clear", 0.5)
		for spec in [key_spec(KEY_DELETE), key_spec(KEY_BACKSPACE), button_spec(JOY_BUTTON_X)]:
			InputMap.action_add_event("ui_clear", event_of(spec))


## Every action's slots from an overrides dict over defaults(), slot_count long. A bad or reserved
## spec, one of the other class, or one an earlier action or slot already holds (a hand-edited or
## old settings file) becomes ""; locked slots are always their default.
static func resolve(o: Dictionary) -> Dictionary:
	var d := defaults()
	var used := {KEY: [], PAD: []}
	var t := {}
	for act in ACTIONS:
		t[act] = {}
		for cls in [KEY, PAD]:
			var def: Array = d[act][cls]
			var src: Array = def
			var entry = o.get(act)
			if entry is Dictionary and (entry as Dictionary).get(cls) is Array:
				src = entry[cls]
			var out := []
			for i in slot_count(act, cls):
				var spec := str(src[i]) if i < src.size() else ""
				if is_locked(act, cls, i):
					spec = str(def[i])
				elif spec != "" and (is_reserved(spec) or class_of(spec) != cls or event_of(spec) == null \
						or spec in used[cls] or refused(act, cls, spec)):
					spec = ""
				if spec != "":
					used[cls].append(spec)
				out.append(spec)
			t[act][cls] = out
	return t


## Some action's slot of class `cls` in table `t` holds `spec`.
static func _held(t: Dictionary, spec: String, cls: String) -> bool:
	for act in ACTIONS:
		if spec in (t[act][cls] as Array):
			return true
	return false


static func _overrides() -> Dictionary:
	var o = Game.settings.get("bindings", {})
	return o if o is Dictionary else {}


## Keeps only the classes that differ from the defaults in Game.settings["bindings"], then applies.
static func _store(t: Dictionary) -> void:
	var d := defaults()
	var o := {}
	for act in ACTIONS:
		for cls in [KEY, PAD]:
			var s: Array = t[act][cls]
			if s != d[act][cls]:
				if not o.has(act):
					o[act] = {}
				o[act][cls] = s.duplicate()
	Game.settings["bindings"] = o
	apply()


static func _prompts() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("InputPrompts") if tree and tree.root else null
