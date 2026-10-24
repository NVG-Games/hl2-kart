extends Node3D
## Physics regression cases (headless): item box hit, off-road return,
## kart-vs-kart bump, rest stance. Prints measurements.
## usage: godot --headless --path . res://tests/physics_cases.tscn -- [vehicle]

var trk: Track
var vehicle_id := "buggy"
var race_stub: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		vehicle_id = args[0]
	print("vehicle ", vehicle_id)
	trk = Track.new()
	add_child(trk)
	trk.build("city17_circuit")
	await _stance()
	await _item_box()
	for c in [[1250.0, "coast"], [1420.0, "dirt"], [1500.0, "dirt"], [900.0, "coast"], [1350.0, "dirt"], [1495.0, "dirt"], [1890.0, "canal-exit"]]:
		await _offroad_return(c[0], c[1])
	await _bump()
	get_tree().quit()


func _kart(id: String, idx: int) -> Kart:
	var k := Kart.new()
	add_child(k)
	k.setup(id, idx, trk, false, vehicle_id)
	k.add_to_group("karts")
	return k


func _place(k: Kart, s: float, lateral: float, yaw := 0.0) -> void:
	var t := trk.path.transform_at(s)
	var b := t.basis.rotated(Vector3.UP, yaw)
	k.global_transform = Transform3D(b, t.origin + t.basis.x * lateral + Vector3.UP * 0.8)
	k.linear_velocity = Vector3.ZERO
	k.angular_velocity = Vector3.ZERO
	_sync(k)


## Teleports need the kart's path index re-found globally (the game only ever
## moves karts along the track, where the windowed search is enough).
func _sync(k: Kart) -> void:
	k.path_index = trk.path.closest(k.global_position)
	k._last_s = trk.path.progress(k.global_position, k.path_index)
	k._watch_progress = k._last_s
	k._watch_time = 0.0


func _drive_frames(ks: Array, frames: int, throttle := 1.0, steer_fn := Callable()) -> void:
	for f in frames:
		for k in ks:
			k.in_throttle = throttle
			k.in_steer = steer_fn.call(k) if steer_fn.is_valid() else 0.0
		await get_tree().physics_frame


func _stance() -> void:
	var k := _kart("breen", 0)
	_place(k, 20.0, 0.0)
	await _drive_frames([k], 240, 0.0)
	var vis := k.visual
	var lows := []
	for w in 4:
		lows.append(snappedf(float(k.wheel_compress[w]) - Kart.TRAVEL * 0.5, 0.001))
	print("STANCE wheel visual offsets (0 = touching ground): ", lows, " tilt=", snappedf(rad_to_deg(acos(clampf(k.global_basis.y.dot(Vector3.UP), -1, 1))), 0.1), "deg")
	k.queue_free()
	await get_tree().physics_frame


func _item_box() -> void:
	# drive along the line straight through the first item box row
	var box: ItemBox = trk.item_boxes[2]
	var i := trk.path.closest(box.global_position)
	var s := i * trk.path.step - 60.0
	var k := _kart("alyx", 1)
	var lat := trk.path.lateral(box.global_position, i)
	_place(k, s, lat)
	var steer := func(kk: Kart) -> float:
		var tgt := box.global_position
		var to := tgt - kk.global_position
		return clampf(atan2(to.dot(kk.global_basis.x), to.dot(-kk.global_basis.z)) * 2.0, -1.0, 1.0)
	var vmin := INF
	var vbefore := 0.0
	for f in 600:
		k.in_throttle = 1.0
		var d := k.global_position.distance_to(box.global_position)
		k.in_steer = steer.call(k) if d > 6.0 else 0.0
		await get_tree().physics_frame
		if d < 12.0 and vbefore == 0.0:
			vbefore = k.speed
		if vbefore > 0.0:
			vmin = minf(vmin, k.speed)
		if vbefore > 0.0 and d > 15.0 and k.global_position.distance_to(box.global_position) > 15.0 and (k.global_position - box.global_position).dot(-k.global_basis.z) > 0.0:
			break
	print("ITEMBOX speed before=%.1f min after=%.1f item=%s" % [vbefore, vmin, k.item])
	k.queue_free()
	await get_tree().physics_frame


func _offroad_return(s: float, label: String) -> void:
	var k := _kart("barney", 2)
	var half := trk.path.width[trk.path.index_at(s)] * 0.5
	var side := 1.0
	_place(k, s, side * (half + 9.0), side * 0.9)
	# drop it onto the actual ground at that spot
	var top := k.global_position + Vector3.UP * 60.0
	var q := PhysicsRayQueryParameters3D.create(top, top - Vector3.UP * 140.0, Game.LAYER_WORLD, [k.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		k.global_position = hit["position"] + Vector3.UP * 1.0
	_sync(k)
	print("  placed at y=%.1f (road centre y=%.1f)" % [k.global_position.y, trk.path.center_at(s).y])
	await _drive_frames([k], 30, 0.0)
	var respawns0 := 0
	print("    after settle: state=%s respawns=%d up=%.2f" % [Kart.State.keys()[k.state], k.respawns, k.global_basis.y.dot(Vector3.UP)])
	var back_on := -1.0
	var t := 0.0
	for f in 120 * 8:
		var i := trk.path.closest(k.global_position)
		var tgt := trk.path.center_at(i * trk.path.step + 15.0)
		var to := tgt - k.global_position
		k.in_throttle = 1.0
		k.in_steer = clampf(atan2(to.dot(k.global_basis.x), to.dot(-k.global_basis.z)) * 2.0, -1.0, 1.0)
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if f % 60 == 0:
			print("    t=%.1f state=%s v=%.1f lat=%.1f up=%.2f wheels=%d off=%s y=%.1f" % [t, Kart.State.keys()[k.state], k.speed, trk.path.lateral(k.global_position, trk.path.closest(k.global_position)), k.global_basis.y.dot(Vector3.UP), k.wheels_on_ground, k.offroad, k.global_position.y])
			if k.speed < 2.0 and t > 1.0:
				print("      touching: ", k.get_colliding_bodies().map(func(b: Node): return b.name + "@" + str(b.get_parent().name)))
				var st := PhysicsServer3D.body_get_direct_state(k.get_rid())
				for ci in st.get_contact_count():
					print("        shape %d at %s normal %s" % [st.get_contact_local_shape(ci), k.to_local(st.get_contact_local_position(ci)), st.get_contact_local_normal(ci)])
		if absf(trk.path.lateral(k.global_position, trk.path.closest(k.global_position))) < half - 1.5:
			back_on = t
			break
	print("OFFROAD %s start lateral=%.1f back on tarmac after %s s (speed %.1f, rescued=%s)" % [label, half + 9.0, "NEVER" if back_on < 0 else "%.1f" % back_on, k.speed, k.respawns > respawns0])
	k.queue_free()
	await get_tree().physics_frame


func _bump() -> void:
	# a stub race node so Race._bump_karts runs between the two karts
	race_stub = load("res://scripts/race/race.gd").new()
	race_stub.set("karts", [] as Array[Kart])
	var a := _kart("eli", 3)
	var b := _kart("kleiner", 4)
	race_stub.karts.append(a)
	race_stub.karts.append(b)
	_place(a, 100.0, -3.0)
	_place(b, 100.0, 3.0)
	await _drive_frames([a, b], 300, 1.0)
	var va := a.speed
	var vb := b.speed
	var maxyaw := 0.0
	var minspeed := INF
	for f in 240:
		a.in_throttle = 1.0
		b.in_throttle = 1.0
		a.in_steer = 0.6 if f < 60 else 0.0
		b.in_steer = 0.0
		race_stub.call("_bump_karts")
		await get_tree().physics_frame
		maxyaw = maxf(maxyaw, absf(b.angular_velocity.y))
		minspeed = minf(minspeed, minf(a.speed, b.speed))
	print("BUMP side swipe: speeds before %.1f/%.1f, lowest during %.1f, max yaw rate on victim %.2f rad/s, gap now %.1f m" % [va, vb, minspeed, maxyaw, a.global_position.distance_to(b.global_position)])
	# rear-end
	_place(a, 300.0, 0.0)
	_place(b, 312.0, 0.0)
	for f in 360:
		a.in_throttle = 1.0
		b.in_throttle = 0.25
		a.in_steer = 0.0
		b.in_steer = 0.0
		race_stub.call("_bump_karts")
		await get_tree().physics_frame
	print("BUMP rear-end: rammer %.1f m/s, rammed %.1f m/s, rammed state %s" % [a.speed, b.speed, Kart.State.keys()[b.state]])
