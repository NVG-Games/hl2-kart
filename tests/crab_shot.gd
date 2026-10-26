extends Node
## One screenshot of the HEADCRAB item on the player's camera (FaceCrab) and one
## of a headcrab riding a racer ahead.
## usage: godot --path . res://tests/crab_shot.tscn -- <out_dir> [track]

var out := ""
var race: Node
var t := 0.0
var step := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	Game.settings["track"] = a[1] if a.size() > 1 else "ct17"
	Game.settings["demo"] = true
	DirAccess.make_dir_recursive_absolute(out)
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)


func _process(delta: float) -> void:
	if race == null or not race.get("racing"):
		return
	t += delta
	var p: Kart = race.get("player")
	match step:
		0:
			if t > 2.0:
				# someone ahead of the filmed kart gets a crab; the filmed kart gets one on the lens
				for k in race.get("karts"):
					if k != p and (k as Kart).total_progress > p.total_progress:
						(k as Kart).blind(4.0)
				p.is_player = true
				p.blind(4.0)
				step = 1
				t = 0.0
		1:
			if t > 0.8:
				get_viewport().get_texture().get_image().save_png(out + "/crab_lens.png")
				p.blind_time = 0.0
				for c in p.find_children("*", "FaceCrab", true, false):
					c.queue_free()
				for c in get_viewport().get_camera_3d().find_children("*", "FaceCrab", true, false):
					c.queue_free()
				step = 2
				t = 0.0
		2:
			if t > 0.3:
				get_viewport().get_texture().get_image().save_png(out + "/crab_ahead.png")
				get_tree().quit()
