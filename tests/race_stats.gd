extends Node
## Fast headless AI race for tuning: prints lap times, respawns, places.
## usage: godot --headless --path . res://tests/race_stats.tscn -- <seconds> <time_scale> <laps> [difficulty] [track]

var seconds := 120.0
var t := 0.0
var race: Node
var _next := 10.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		seconds = float(a[0])
	if a.size() > 1:
		Engine.time_scale = float(a[1])
		Engine.max_physics_steps_per_frame = 64
	Game.settings["demo"] = true
	Game.settings["laps"] = int(a[2]) if a.size() > 2 else 2
	Game.settings["difficulty"] = int(a[3]) if a.size() > 3 else 1
	Game.settings["track"] = a[4] if a.size() > 4 else "city17_circuit"
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)


func _process(_d: float) -> void:
	if Time.get_ticks_msec() > 280000:
		print("real-time limit hit")
		get_tree().quit()


func _physics_process(delta: float) -> void:
	t += delta
	if race == null or race.get("karts") == null or race.karts.is_empty():
		return
	if t > _next:
		_next += 10.0
		var line := "t=%.0f " % t
		for k in race.karts:
			line += "%s:L%d/%.0f/v%.0f/r%d%s " % [k.character_id.left(4), k.lap, k.lap_progress, k.speed, k.respawns, "*" if k.state != Kart.State.NORMAL else ""]
		print(line)
		if "--why" in OS.get_cmdline_user_args():
			for k in race.karts:
				if k.speed < 2.0 and k.state == Kart.State.NORMAL and race.racing:
					var p: Vector3 = k.global_position
					var lat: float = race.track.path.lateral(p, k.path_index)
					var hit: Array = k.get_colliding_bodies().map(func(b): return str(b.name) + "@" + str(b.get_parent().name))
					print("   stuck %s at (%.1f, %.1f, %.1f) s=%.0f lat=%.1f w=%.1f wheels=%d touching %s" % [k.character_id, p.x, p.y, p.z, k.lap_progress, lat, race.track.path.width[k.path_index], k.wheels_on_ground, hit])
	var done := true
	for k in race.karts:
		if not k.finished:
			done = false
	if t >= seconds or done:
		for k in race.karts:
			print("%-10s %-6s place=%d finished=%s time=%.1f laps=%s respawns=%d" % [k.character_id, k.spec.id, k.place, k.finished, k.finish_time, str(k.lap_times), k.respawns])
		get_tree().quit()
