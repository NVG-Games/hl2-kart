extends Node3D
## Windowed: drop a kart beside the track at s/lateral, drive back toward the centre line, photograph.
## usage: godot --path . res://tests/offroad_shot.tscn -- <out_prefix> <s> <lateral>

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var s := float(a[1])
	var lat := float(a[2])
	var trk := Track.new()
	add_child(trk)
	trk.build("city17_circuit")
	var k := Kart.new()
	add_child(k)
	k.setup("barney", 0, trk, false)
	var t := trk.path.transform_at(s)
	var yaw := float(a[3]) if a.size() > 3 else 0.9
	k.global_transform = Transform3D(t.basis.rotated(Vector3.UP, yaw * signf(lat)), t.origin + t.basis.x * lat + Vector3.UP * 30.0)
	var q := PhysicsRayQueryParameters3D.create(k.global_position + Vector3.UP * 30.0, k.global_position - Vector3.UP * 120.0, Game.LAYER_WORLD, [k.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		k.global_position = hit["position"] + Vector3.UP
	k.path_index = trk.path.closest(k.global_position)
	k._last_s = trk.path.progress(k.global_position, k.path_index)
	k._watch_progress = k._last_s
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for f in 120 * 6:
		var i := trk.path.closest(k.global_position)
		var to := trk.path.center_at(i * trk.path.step + 15.0) - k.global_position
		k.in_throttle = 1.0
		k.in_steer = clampf(atan2(to.dot(k.global_basis.x), to.dot(-k.global_basis.z)) * 2.0, -1.0, 1.0)
		cam.look_at_from_position(k.global_position + Vector3(0, 9, 0) + k.global_basis.z * 6.0, k.global_position)
		await get_tree().physics_frame
		if f % 120 == 0:
			var ii := trk.path.closest(k.global_position)
			print("  t=%.0f lat=%.1f y=%.2f roadY=%.2f v=%.1f steer=%.2f wheels=%d" % [f / 120.0, trk.path.lateral(k.global_position, ii), k.global_position.y, trk.path.center[ii].y, k.speed, k.in_steer, k.wheels_on_ground])
		if f == 60:
			get_viewport().get_texture().get_image().save_png(out + "_a.png")
	get_viewport().get_texture().get_image().save_png(out + "_b.png")
	print("end state ", Kart.State.keys()[k.state], " speed ", k.speed, " lat ", trk.path.lateral(k.global_position, trk.path.closest(k.global_position)))
	get_tree().quit()
