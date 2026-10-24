class_name RaceCamera
extends Camera3D
## Chase camera (Source view: fov 75 at 4:3, hor+), intro flyby and finish orbit.

enum Mode { INTRO, CHASE, ORBIT }

var target: Kart
var mode := Mode.INTRO
var intro_t := 0.0
var _fwd := Vector3.FORWARD
var _shake := 0.0
var _pos := Vector3.ZERO
var _orbit := 0.0


func _ready() -> void:
	add_to_group("race_camera")
	fov = 66.0
	near = 0.08
	far = 9000.0
	keep_aspect = Camera3D.KEEP_HEIGHT


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var kp := target.global_position
	match mode:
		Mode.INTRO:
			intro_t += delta
			var a := intro_t * 0.35 + 0.6
			var r := 16.0 - intro_t * 1.2
			var c := kp - target.global_basis.z * 6.0
			var p := c + Vector3(cos(a) * r, 4.0 + 5.0 / (1.0 + intro_t), sin(a) * r)
			global_position = p
			look_at(c + Vector3.UP * 1.2, Vector3.UP)
			_fwd = -target.global_basis.z
			_pos = global_position
		Mode.CHASE:
			_chase(delta)
		Mode.ORBIT:
			_orbit += delta * 0.4
			var p2 := kp + Vector3(cos(_orbit) * 9.0, 3.5, sin(_orbit) * 9.0)
			global_position = global_position.lerp(p2, minf(1.0, delta * 3.0))
			look_at(kp + Vector3.UP * 1.3, Vector3.UP)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		h_offset = randf_range(-1, 1) * _shake * 0.35
		v_offset = randf_range(-1, 1) * _shake * 0.35
	else:
		h_offset = 0.0
		v_offset = 0.0


func _chase(delta: float) -> void:
	var k := target
	var kfwd := -k.global_basis.z
	var v := k.linear_velocity
	if v.length() > 6.0 and v.normalized().dot(kfwd) > 0.0 and k.grounded:
		kfwd = (kfwd + v.normalized() * 1.2).normalized()
	kfwd.y *= 0.4
	if kfwd.length() < 0.1:
		kfwd = _fwd
	kfwd = kfwd.normalized()
	var turn_rate := 4.5 if k.state == Kart.State.NORMAL else 1.0
	_fwd = _fwd.slerp(kfwd, minf(1.0, delta * turn_rate)).normalized()
	var back := k.in_look_back
	var dir := -_fwd if back else _fwd
	# frame bigger vehicles (APCs) from further back and higher, relative to the jeep
	var ref := VehicleSpec.get_spec("buggy")
	var size := clampf(1.0 + (k.spec.length / ref.length - 1.0) * 0.5, 0.9, 1.15)
	var rise := maxf(0.0, k.spec.height - ref.height)
	var dist := (8.6 + clampf(k.speed / 35.0, 0.0, 1.0) * 1.6) * size
	var desired := k.global_position - dir * dist + Vector3.UP * (3.3 + rise * 0.5)
	# keep the camera out of walls (canal, buildings)
	var space := get_world_3d().direct_space_state
	var from := k.global_position + Vector3.UP * 1.6
	var q := PhysicsRayQueryParameters3D.create(from, desired, Game.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit["position"] + (from - desired).normalized() * 0.6
	_pos = _pos.lerp(desired, minf(1.0, delta * 18.0))
	global_position = _pos
	look_at(k.global_position + dir * 5.0 + Vector3.UP * (1.4 + rise * 0.4), Vector3.UP)
	var fov_t := 66.0 + clampf(k.speed / k.max_speed, 0.0, 1.3) * 8.0 + (6.0 if k.boost_time > 0.0 else 0.0)
	fov = lerpf(fov, fov_t, minf(1.0, delta * 3.0))
