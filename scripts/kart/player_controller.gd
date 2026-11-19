class_name PlayerController
extends RefCounted
## Keyboard / gamepad input -> kart controls. The actions and their bindings are InputBindings',
## built at startup by the InputPrompts autoload; any pad drives them.

var _frame := -1  # the physics frame of the last drive()
var _latch_item := false  # use_item / drift held through a pause: ignored until let go
var _latch_drift := false


## The InputMap from the player's bindings (InputPrompts already does this at startup).
static func setup_input_map() -> void:
	InputBindings.apply()


func drive(k: Kart, _delta: float) -> void:
	if k.state == Kart.State.FINISHED:
		k.in_throttle = 0.0
		k.in_brake = 0.3
		k.in_steer = 0.0
		k.in_drift = false
		k.in_item = false
		return
	var race_on: bool = k.race == null or k.race.racing
	# online the race never pauses: typing in chat / the menu releases the controls
	var blocked: bool = k.race != null and k.race.get("input_blocked")
	if blocked:
		race_on = false
	# back from a pause (no physics frames went by) or the online menu: a button still held from
	# the menu (B, Enter closing it) fires no item and starts no drift until it is let go
	var frame := Engine.get_physics_frames()
	if blocked or (_frame >= 0 and frame - _frame > 1):
		_latch_item = true
		_latch_drift = true
	_frame = frame
	var item := Input.is_action_pressed("use_item")
	var drift := Input.is_action_pressed("drift")
	_latch_item = _latch_item and item
	_latch_drift = _latch_drift and drift
	k.in_throttle = Input.get_action_strength("accelerate") if race_on else 0.0
	k.in_brake = Input.get_action_strength("brake") if race_on else 0.0
	k.in_steer = 0.0 if blocked else Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	k.in_drift = drift and race_on and not _latch_drift
	k.in_item = item and race_on and not _latch_item
	k.in_look_back = Input.is_action_pressed("look_back") and not blocked
	if Input.is_action_just_pressed("respawn") and race_on and k.state == Kart.State.NORMAL:
		k.start_respawn()
