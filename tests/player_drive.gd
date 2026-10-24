extends Node
## Simulated keyboard input for the player's kart: checks it drives, drifts, uses items.

var race: Node
var t := 0.0
var phase := 0
var log_t := 0.0


func _ready() -> void:
	Game.settings["demo"] = false
	Game.settings["character"] = "alyx"
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)


func _physics_process(delta: float) -> void:
	t += delta
	if race == null or race.get("player") == null:
		return
	var k: Kart = race.player
	if not race.racing:
		Input.action_press("accelerate") if race._countdown > 2.8 and race._phase == "count" else Input.action_release("accelerate")
		return
	Input.action_press("accelerate")
	# crude steering toward the racing line so we survive corners
	var p: TrackPath = k.track.path
	var target := p.line_at(k.lap_progress + 14.0)
	var to := target - k.global_position
	var ang := atan2(to.dot(k.global_basis.x), to.dot(-k.global_basis.z))
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if ang > 0.05:
		Input.action_press("steer_right", clampf(ang * 2.0, 0.0, 1.0))
	elif ang < -0.05:
		Input.action_press("steer_left", clampf(-ang * 2.0, 0.0, 1.0))
	# drift through a bend between 14 s and 16 s
	if t > 14.0 and t < 15.6 and absf(ang) > 0.05:
		Input.action_press("drift")
	else:
		Input.action_release("drift")
	if k.item != "" and k.roulette <= 0.0:
		Input.action_press("use_item")
	else:
		Input.action_release("use_item")
	log_t += delta
	if log_t > 2.0:
		log_t = 0.0
		print("t=%.1f s=%.0f lap=%d v=%.1f place=%d drift=%s lvl=%d boost=%.2f item=%s state=%s" % [t, k.lap_progress, k.lap, k.speed, k.place, k.drifting, k.drift_level, k.boost_time, k.item, Kart.State.keys()[k.state]])
	if t > 40.0:
		get_tree().quit()
