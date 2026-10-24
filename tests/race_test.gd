extends Node
## Headless-ish race test: demo race (all AI), periodic screenshots + stats.
## usage: godot --path . res://tests/race_test.tscn -- <out_prefix> <seconds> [interval] [vehicle] [character] [track]

var out := "user://race"
var seconds := 30.0
var t := 0.0
var shots := 0
var race: Node
var next_shot := 2.0
var interval := 5.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		seconds = float(a[1])
	if a.size() > 2:
		interval = float(a[2])
	if a.size() > 3:
		Game.settings["vehicle"] = a[3]
	if a.size() > 4:
		Game.settings["character"] = a[4]
	if a.size() > 5:
		Game.settings["track"] = a[5]
	Game.settings["demo"] = true
	Game.settings["difficulty"] = 1
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)
	get_tree().set_deferred("current_scene", race)


func _process(delta: float) -> void:
	t += delta
	if t >= next_shot:
		next_shot += interval
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [out, shots])
		shots += 1
		if race and race.get("karts"):
			var line := "t=%.1f fps=%d " % [t, Engine.get_frames_per_second()]
			for k in race.karts:
				line += "[%s L%d %.0fm v%.0f %s] " % [k.character_id.left(4), k.lap, k.lap_progress, k.speed, Kart.State.keys()[k.state]]
			print(line)
	if t >= seconds:
		get_tree().quit()
