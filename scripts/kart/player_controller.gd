class_name PlayerController
extends RefCounted
## Keyboard / gamepad input -> kart controls.

static func setup_input_map() -> void:
	var map := {
		"accelerate": [KEY_W, KEY_UP, JOY_BUTTON_A, "axis:5"],
		"brake": [KEY_S, KEY_DOWN, JOY_BUTTON_X, "axis:4"],
		"steer_left": [KEY_A, KEY_LEFT, "axis:0-"],
		"steer_right": [KEY_D, KEY_RIGHT, "axis:0+"],
		"drift": [KEY_SHIFT, KEY_SPACE, JOY_BUTTON_RIGHT_SHOULDER],
		"use_item": [KEY_E, KEY_CTRL, KEY_ENTER, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_B],
		"look_back": [KEY_C, JOY_BUTTON_Y],
		"respawn": [KEY_R, JOY_BUTTON_BACK],
		"pause": [KEY_ESCAPE, KEY_P, JOY_BUTTON_START],
		"chat": [KEY_Y, KEY_T],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for k in map[action]:
			if k is String:
				var parts: PackedStringArray = k.split(":")
				var spec: String = parts[1]
				var ev := InputEventJoypadMotion.new()
				if spec.ends_with("-") or spec.ends_with("+"):
					ev.axis = int(spec.substr(0, spec.length() - 1)) as JoyAxis
					ev.axis_value = -1.0 if spec.ends_with("-") else 1.0
				else:
					ev.axis = int(spec) as JoyAxis
					ev.axis_value = 1.0
				InputMap.action_add_event(action, ev)
			elif k >= KEY_SPACE:
				var ke := InputEventKey.new()
				ke.physical_keycode = k
				InputMap.action_add_event(action, ke)
			else:
				var jb := InputEventJoypadButton.new()
				jb.button_index = k
				InputMap.action_add_event(action, jb)


func drive(k: Kart, _delta: float) -> void:
	if k.state == Kart.State.FINISHED:
		k.in_throttle = 0.0
		k.in_brake = 0.3
		k.in_steer = 0.0
		k.in_drift = false
		k.in_item = false
		return
	var race_on: bool = k.race == null or k.race.racing
	# online the race never pauses: typing in chat / the menu releases the pedals
	if k.race and k.race.get("input_blocked"):
		race_on = false
	k.in_throttle = Input.get_action_strength("accelerate") if race_on else 0.0
	k.in_brake = Input.get_action_strength("brake") if race_on else 0.0
	k.in_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	k.in_drift = Input.is_action_pressed("drift") and race_on
	k.in_item = Input.is_action_pressed("use_item") and race_on
	k.in_look_back = Input.is_action_pressed("look_back")
	if Input.is_action_just_pressed("respawn") and race_on and k.state == Kart.State.NORMAL:
		k.start_respawn()
