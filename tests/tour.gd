extends Node3D
## Track photo tour: camera placed along the centre line at given distances.
## usage: godot --path . res://tests/tour.tscn -- <out_prefix> s1,s2,... [height] [back] [track]
## "top" in the list renders the whole circuit (branches included) from straight above.
## Branches (by index or id): "b<branch>:<u>" stands on the branch u metres from its fork,
## "fork:<branch>" looks along the fork from 25 m before it, "nose:<branch>" looks at the
## fork's nose from 25 m before it, "merge:<branch>" looks down the branch onto its merge.

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ss: PackedStringArray = a[1].split(",")
	var height := float(a[2]) if a.size() > 2 else 4.0
	var back := float(a[3]) if a.size() > 3 else 10.0
	var trk := Track.new()
	add_child(trk)
	trk.build(a[4] if a.size() > 4 else "city17_circuit")
	var p := trk.path
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	for i in ss.size():
		var spec := ss[i]
		if spec == "top":
			var lo := Vector3(INF, 0, INF)
			var hi := Vector3(-INF, 0, -INF)
			for g: TrackPath in [p] + p.branches:
				for c in g.center:
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
		var from: Vector3
		var look: Vector3
		var up := Vector3.UP
		var look_up := Vector3.UP
		if spec.contains(":"):
			var head := spec.get_slice(":", 0)
			var tail := spec.get_slice(":", 1)
			var b := _branch(p, tail if head in ["fork", "nose", "merge"] else head.substr(1))
			match head:
				"fork":
					from = p.center_at(b.fork_s - 25.0)
					look = b.center_at(b.fork_nose_u)
				"nose":
					from = b.center_at(maxf(b.fork_nose_u - 25.0, 0.0))
					look = b.center_at(b.fork_nose_u + 10.0)
				"merge":
					from = b.center_at(maxf(b.merge_nose_u - 25.0, 0.0))
					look = p.center_at(b.merge_s + 10.0)
				_:
					var u := float(tail)
					var t := b.transform_at(u - back)
					from = t.origin
					look = b.center_at(u + 25.0)
					up = _road_up(t)
					look_up = _road_up(b.transform_at(u + 25.0))
		else:
			var s := float(spec)
			var t := p.transform_at(s - back)
			from = t.origin
			look = p.center_at(s + 25.0)
			up = _road_up(t)
			look_up = _road_up(p.transform_at(s + 25.0))
		cam.global_position = from + up * height
		cam.look_at(look + look_up * 1.5, up)
		for f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [out, i])
	get_tree().quit()


## World up, except where the road rolls far over (tubes, loops): there the road's own up,
## so the camera stays inside the pipe the way the race camera does.
func _road_up(t: Transform3D) -> Vector3:
	return t.basis.y if t.basis.y.dot(Vector3.UP) < 0.9 else Vector3.UP


## A branch by index ("0") or id ("canal_jump").
func _branch(p: TrackPath, key: String) -> TrackBranch:
	if key.is_valid_int():
		return p.branches[int(key)]
	for b in p.branches:
		if b.id == key:
			return b
	push_error("no branch " + key)
	return p.branches[0]
