class_name RaceCamera
extends Camera3D
## Chase camera (Source view: fov 75 at 4:3, hor+), intro flyby and finish orbit. While its kart
## drops out of play (into a liquid, off a deck, short of a jump) it stands back above the edge
## the kart went over and watches; it never sweeps through a wall or a deck.

enum Mode { INTRO, CHASE, ORBIT }

var target: Kart
var mode := Mode.INTRO
var intro_t := 0.0
var _fwd := Vector3.FORWARD
var _shake := 0.0
var _pos := Vector3.ZERO
var _orbit := 0.0
var _up := Vector3.UP  # rolls with the kart in a tube
var _edge := Vector3.ZERO  # where the kart was last driving on its road, and which way
var _edge_fwd := Vector3.FORWARD
var _dropped := false  # the last frame was a drop view (_drop_view)
var _seen_from := Vector3.ZERO  # drop view: where round the kart it is seen from (_spot), ZERO while the wanted spot sees it
var _look_t := 0.0  # drop view: seconds until that spot is looked for again


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
	_up = Kart.ease_up(_up, k.grav_up, delta * 5.0)
	var space := get_world_3d().direct_space_state
	var floor_y := _drop_floor(k)
	if floor_y > -INF:
		_drop_view(k, floor_y, space, delta)
		return
	if k.grounded and k.state == Kart.State.NORMAL and k.geo().on_road(k.global_position, k.route_index) < 0.5:
		var vh := Vector3(k.linear_velocity.x, 0.0, k.linear_velocity.z)
		if vh.length() > 2.0:
			_edge = k.global_position
			_edge_fwd = vh.normalized()
	var kfwd := -k.global_basis.z
	var v := k.linear_velocity
	if v.length() > 6.0 and v.normalized().dot(kfwd) > 0.0 and k.grounded:
		kfwd = (kfwd + v.normalized() * 1.2).normalized()
	kfwd -= _up * kfwd.dot(_up) * 0.6
	if kfwd.length() < 0.1:
		kfwd = _fwd
	kfwd = kfwd.normalized()
	var turn_rate := 4.5 if k.state == Kart.State.NORMAL else 1.0
	# back from a drop view (cut to the road the scanner put it on): straight in behind it
	_fwd = kfwd if _dropped else _fwd.slerp(kfwd, minf(1.0, delta * turn_rate)).normalized()
	var back := k.in_look_back
	var dir := -_fwd if back else _fwd
	# frame bigger vehicles (APCs) from further back and higher, relative to the jeep
	var ref := VehicleSpec.get_spec("buggy")
	var size := clampf(1.0 + (k.spec.length / ref.length - 1.0) * 0.5, 0.9, 1.15)
	var rise := maxf(0.0, k.spec.height - ref.height)
	var dist := (8.6 + clampf(k.speed / 35.0, 0.0, 1.0) * 1.6) * size
	var focus := k.global_position
	var desired := focus - dir * dist + _up * (3.3 + rise * 0.5)
	# keep the camera out of walls (canal, buildings)
	var from := focus + _up * 1.6
	var q := PhysicsRayQueryParameters3D.create(from, desired, Game.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit["position"] + (from - desired).normalized() * 0.6
	# never sweep through a wall or a deck: a move that would (back from a drop view onto the
	# road the scanner put the kart on, say) is a cut
	if _dropped or not _clear(space, _pos, desired):
		_pos = desired
	else:
		_pos = _pos.lerp(desired, minf(1.0, delta * 18.0))
	_dropped = false
	_seen_from = Vector3.ZERO
	_look_t = 0.0
	global_position = _pos
	look_at(focus + dir * 5.0 + _up * (1.4 + rise * 0.4), _up)
	var fov_t := 66.0 + clampf(k.speed / k.max_speed, 0.0, 1.3) * 8.0 + (6.0 if k.boost_time > 0.0 else 0.0)
	fov = lerpf(fov, fov_t, minf(1.0, delta * 3.0))


## Height the camera keeps above while its kart drops out of play, -INF while it races: sinking
## (above the liquid and the road it went in from), dropping out of sight on a FALL rescue (the
## edge it went over), or airborne well below its road before a rescue starts (thrown over a
## wall, short of a jump).
func _drop_floor(k: Kart) -> float:
	var g := k.geo()
	var road_y := g.center[k.route_index].y
	if k.state == Kart.State.RESPAWN:
		if k.rescue == Kart.Rescue.SINK:
			return maxf(k.liquid.x + 2.2, road_y + 2.5)
		if k.rescue == Kart.Rescue.FALL and not k.freeze:
			return k.fall_floor + 2.5
		return -INF
	if not k.grounded and k.air_time > 0.35 and g.mag[k.route_index] <= 0.0 and k.global_position.y < road_y - 3.0:
		return road_y + 2.5
	return -INF


## The kart drops out of play: the camera stands back above the edge it went over (where it was
## last driving on its road; where it is when that is far off), at least `floor_y` up and clear of
## the splash, and watches it go; where something solid hides the kart from there, it watches from
## a spot round the kart that sees it. It moves only along a clear line: when the first move is
## blocked (it was following the kart down beside a rock), or the kart is hidden from where it is, it cuts.
func _drop_view(k: Kart, floor_y: float, space: PhysicsDirectSpaceState3D, delta: float) -> void:
	var focus := k.global_position
	if k.state == Kart.State.RESPAWN and k.rescue == Kart.Rescue.SINK:
		focus.y = maxf(focus.y, k.liquid.x)
	var want := Vector3(_pos.x, maxf(_pos.y, floor_y), _pos.z)
	if Vector2(focus.x - _edge.x, focus.z - _edge.z).length() < 45.0:
		var base := _edge + Vector3.UP
		want = _edge - _edge_fwd * 6.0 + Vector3.UP * 4.5
		want.y = maxf(want.y, floor_y)
		# under a roof or against a wall: as far out along that line as is clear
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base, want, Game.LAYER_WORLD))
		if not hit.is_empty():
			want = hit["position"] + (base - want).normalized() * 0.4
	# the kart stays in sight: where the deck or the lip hides it (it struck the landing wall's top and
	# sank right under it, or sank under the kicker it fell short of), a spot round it that sees it
	# (looked for again at most 4 times a second, while the last one found no longer sees it)
	_look_t -= delta
	if _sees(space, want, focus):
		_seen_from = Vector3.ZERO
	else:
		var lost := _seen_from == Vector3.ZERO or not _sees(space, _spot(_seen_from, want, focus), focus)
		if lost and _look_t <= 0.0:
			_look_t = 0.25
			_seen_from = _around(space, want, focus)
		if _seen_from != Vector3.ZERO:
			want = _spot(_seen_from, want, focus)
	if _clear(space, _pos, want):
		_pos = _pos.lerp(want, minf(1.0, delta * 5.0))
	elif not _dropped or not _sees(space, _pos, focus):
		_pos = want
	_dropped = true
	global_position = _pos
	var look := focus - _pos
	if look.length() > 0.1:
		look_at(focus, Vector3.UP if absf(look.normalized().y) < 0.97 else _edge_fwd)
	# zoomed in on a kart far below, framed about as wide as the chase camera frames it
	var zoom := rad_to_deg(2.0 * atan(tan(deg_to_rad(33.0)) * 14.0 / maxf(look.length(), 14.0)))
	fov = lerpf(fov, clampf(zoom, 32.0, 66.0), minf(1.0, delta * 3.0))


## Where round `focus` (the dropped kart) it can be seen from (see _spot): as far out as `want`
## (6-14 m), the nearest way round from it first, then straight over it; ZERO when nowhere there does.
func _around(space: PhysicsDirectSpaceState3D, want: Vector3, focus: Vector3) -> Vector3:
	var flat := Vector3(want.x - focus.x, 0.0, want.z - focus.z)
	var dir := flat.normalized() if flat.length() > 0.1 else -_edge_fwd
	var r := clampf(flat.length(), 6.0, 14.0)
	for n: int in [0, 1, -1, 2, -2, 3, -3, 4]:
		var o := dir.rotated(Vector3.UP, n * PI / 4.0) * r
		o.y = 3.0
		if _sees(space, _spot(o, want, focus), focus):
			return o
	var top := Vector3(0.0, 6.0, 0.0)
	return top if _sees(space, _spot(top, want, focus), focus) else Vector3.ZERO


## A drop view spot `o` round the kart at `focus` (x, z: its offset from the kart; y: at least that
## much over it), as high as `want`: it stays up at the edge while the kart falls away.
static func _spot(o: Vector3, want: Vector3, focus: Vector3) -> Vector3:
	return Vector3(focus.x + o.x, maxf(want.y, focus.y + o.y), focus.z + o.z)


## The kart at `focus` can be seen from `from`: nothing solid between, either way (a camera inside a
## rock sees out through its back faces), up to half a metre short of it (the ground it lies on).
func _sees(space: PhysicsDirectSpaceState3D, from: Vector3, focus: Vector3) -> bool:
	var to := focus + (from - focus).normalized() * 0.5
	return _clear(space, from, to) and _clear(space, to, from)


## Nothing solid on the straight line from a to b.
func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	if a.distance_squared_to(b) < 0.0001:
		return true
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, Game.LAYER_WORLD)).is_empty()
