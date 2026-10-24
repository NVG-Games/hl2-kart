extends Node3D
## Track photo tour: camera placed along the centre line at given distances.
## usage: godot --path . res://tests/tour.tscn -- <out_prefix> s1,s2,... [height] [back] [track]
## "top" in the list renders the whole circuit from straight above.

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ss: PackedStringArray = a[1].split(",")
	var height := float(a[2]) if a.size() > 2 else 4.0
	var back := float(a[3]) if a.size() > 3 else 10.0
	var trk := Track.new()
	add_child(trk)
	trk.build(a[4] if a.size() > 4 else "city17_circuit")
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	for i in ss.size():
		if ss[i] == "top":
			var lo := Vector3(INF, 0, INF)
			var hi := Vector3(-INF, 0, -INF)
			for c in trk.path.center:
				lo = Vector3(minf(lo.x, c.x), 0, minf(lo.z, c.z))
				hi = Vector3(maxf(hi.x, c.x), 0, maxf(hi.z, c.z))
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = maxf(hi.z - lo.z, (hi.x - lo.x) * 9.0 / 16.0) * 1.15
			cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), (lo + hi) * 0.5 + Vector3.UP * 600.0)
			for f in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [out, i])
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			continue
		var s := float(ss[i])
		var t := trk.path.transform_at(s - back)
		var look := trk.path.center_at(s + 25.0)
		cam.global_position = t.origin + Vector3.UP * height
		cam.look_at(look + Vector3.UP * 1.5, Vector3.UP)
		for f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [out, i])
	get_tree().quit()
