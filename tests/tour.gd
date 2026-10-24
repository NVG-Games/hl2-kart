extends Node3D
## Track photo tour: camera placed along the centre line at given distances.
## usage: godot --path . res://tests/tour.tscn -- <out_prefix> s1,s2,... [height] [back]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ss: PackedStringArray = a[1].split(",")
	var height := float(a[2]) if a.size() > 2 else 4.0
	var back := float(a[3]) if a.size() > 3 else 10.0
	var trk := Track.new()
	add_child(trk)
	trk.build("city17_circuit")
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	for i in ss.size():
		var s := float(ss[i])
		var t := trk.path.transform_at(s - back)
		var look := trk.path.center_at(s + 25.0)
		cam.global_position = t.origin + Vector3.UP * height
		cam.look_at(look + Vector3.UP * 1.5, Vector3.UP)
		for f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [out, i])
	get_tree().quit()
