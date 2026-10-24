extends Node
## Gameplay clip for the README: a demo race that fast-forwards until the player's
## kart reaches a point of the lap, then plays in slow motion and saves every
## frame with its race time, so a GIF can be cut at an even frame rate.
## usage: godot --path . --resolution 1280x720 res://tests/clip.tscn -- <out_dir> <track>
##        <character> <vehicle> <metres into lap 1> <seconds>

var out := ""
var at := 0.0
var dur := 6.0
var race: Node
var t := 0.0
var rec_t := -1.0
var frame := 0
var log_lines: PackedStringArray = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	Game.settings["track"] = a[1]
	Game.settings["character"] = a[2]
	Game.settings["vehicle"] = a[3]
	at = float(a[4])
	dur = float(a[5])
	Game.settings["demo"] = true
	Game.settings["difficulty"] = 1
	DirAccess.make_dir_recursive_absolute(out)
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)
	get_tree().set_deferred("current_scene", race)


## The kart the race camera follows (in a demo race an AI drives it).
func _player() -> Kart:
	if race == null:
		return null
	return race.get("player") as Kart


func _process(delta: float) -> void:
	t += delta
	var p := _player()
	if p == null:
		return
	if rec_t < 0.0:
		# fast forward to the spot (lap 1, `at` metres in)
		var there := p.lap >= 1 or (p.lap == 0 and p.lap_progress >= at and p.lap_progress < at + 400.0)
		Engine.time_scale = 1.0 if there or not race.racing else 3.0
		if there and race.racing:
			rec_t = 0.0
			Engine.time_scale = 0.2
		return
	rec_t += delta
	get_viewport().get_texture().get_image().save_png("%s/c%05d.png" % [out, frame])
	log_lines.append("%d %.4f" % [frame, rec_t])
	frame += 1
	if rec_t >= dur:
		var f := FileAccess.open(out + "/times.txt", FileAccess.WRITE)
		f.store_string("\n".join(log_lines))
		Engine.time_scale = 1.0
		get_tree().quit()
	if t > 900.0:
		get_tree().quit()
