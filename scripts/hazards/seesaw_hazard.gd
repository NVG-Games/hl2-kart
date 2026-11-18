class_name SeesawHazard
extends Hazard
## Episode Two's see-saw bridge: a 49 m steel span on a pivot in its middle over a ravine, tipping
## towards the side the karts' weight is on. Empty it rests with its entry end a little down; karts on
## its near half push that end further down (they climb towards the pivot); their weight past the
## pivot swings it down towards the exit (they ride down it), and a pack still behind the leaders
## holds it back towards the entry (the leaders climb). It never hurts a kart.
##
## Each end of the span is met by an approach flap: a row of hinged plates from the fixed road (the
## hinge, level with the road) onto the span's end that bends in one smooth curve, so whatever the
## tilt a kart never meets a step or a wall. Unseen walls stand along both sides of the whole stretch;
## railings ride on the span and the flaps. The circuit leaves the stretch unbuilt (a style with
## "seesaw": True, tools/track_gen.py) and hands it to this hazard (tools/hazards.py: _seesaw).
##
## The angle is a function of the shared hazard clock and of the authority's "tilt" events: the
## server (or the offline game) weighs every kart it knows on the span a few times a second, by its
## vehicle's mass and where it will be in a moment, and when the side the span should tip to changes it
## sends one event: the clock time, the angle and turning speed at that time and the target angle. Every
## peer turns the span from that event along the same profile (accelerate, cruise, slow down to rest at
## the target, within the same limits), so the same clock gives the same angle everywhere, and each
## event carries all a peer needs (one that missed the ones before is right again from the next). Its
## collision is built on every peer, the dedicated server too: the span and every plate are kinematic
## bodies moved in the physics step, so karts riding them move with them (Kart's dampers work against
## the deck's own motion).
##
## Where the deck falls away under a kart faster than a road would (over a flap's crest at speed, or the
## span swinging down under it) the kart's owner holds it down by what that needs (_hold_down), so no
## kart is thrown off the deck or flies over half the span.

## The span model (49.08 x 0.81 x 6.37 m), laid side by side to the road's width and stretched to the
## span's length.
const SPAN_MODEL := "seesawbridge/bridgemetalnondynamic"
## The span's steel plate (its top at the road's height) and how far under that the model's highest
## point lies (its top beams, 0.09 m under that point, are then inside the plate).
const SPAN_PLATE := 0.16
const SPAN_SINK := 0.04
## Thickness of the span's collision box and of each flap plate; the plates overlap by PLATE_LAP at
## each end so no crack opens between them as the flap bends.
const DECK_T := 0.8
const PLATE_T := 0.3
const PLATE_LAP := 0.12
## About this many metres of flap per plate (each flap has a whole number of them).
const PLATE_LEN := 1.15
## The unseen side walls: thick, and tall enough above and below the road for every tilt.
const WALL_T := 0.7
const WALL_UP := 4.5
## Seconds of clock between two weighings, the least between two events, and how often the
## authority sends the state it rests in again while a kart is near (for a peer that lost an event).
const WEIGH := 0.2
const HOLD := 0.5
const RESEND := 6.0
## A kart is held to the deck while it is no more than HOLD_NEAR metres over it: by as much as a flap's
## crest falls away under it beyond p["hold_share"] of gravity (its tyres unload a little over the crest,
## as on any road, but never leave it) and by all of the turning deck's fall; the hold eases off at
## p["hold_ease"] m/s^2 per second once the deck stops falling away (let go at once, the springs it
## pressed would throw the kart up).
const HOLD_NEAR := 0.8
## The weight about the pivot (each kart's mass over a buggy's, times where it is over half the span's
## length) past which the span tips that way; inside it the side it tips to stays as it is.
const DEAD := 0.15
## A client: the most of its old swing it shows after a late tilt event (radians), and how fast it lets
## that go (radians per second, half its usual turning speed or less).
const EASE_MAX := 0.03
const EASE_RATE := 0.06

var _pivot := Vector3.ZERO   # the deck's top at the pivot
var _fwd := Vector3.FORWARD  # level, along the road from the entry to the exit
var _right := Vector3.RIGHT
var _len := 49.1
var _w := 12.0
var _ha := Vector3.ZERO      # the entry hinge (where the fixed road ends) and the exit hinge
var _hb := Vector3.ZERO
var _n_plates := 14
var _vmax := 0.0             # radians per second, radians per second squared
var _amax := 0.0
var _lim := Vector2.ZERO     # the angles it may take (x: entry end down, negative; y: exit end down)
## The event it is turning by: [seq, t0, angle at t0, turning speed at t0, target angle] (radians).
var _seg := [0, -1e9, 0.0, 0.0, 0.0]
var _seq := 0
var _side := 0               # the side the authority last sent: -1 entry down, 0 empty, 1 exit down
var _next_weigh := -1e9
var _sent_t := -1e9
var _resent_t := -1e9
var _sending := false        # the authority is sending: an online server takes only its own events
var _placed := NAN           # the angle the bodies were last put at
var _tc := NAN               # the clock the bodies follow: the shared clock, a step at a time (tick)
var _ease := 0.0             # a client: radians it still shows of the swing it had before a late tilt
## Built by a director with the race's hazards OFF: the span still spans its gap (it is the road), level
## and still; it is not in the director's list, so it never ticks.
var still := false

var _span_body: AnimatableBody3D
var _plates: Array[AnimatableBody3D] = []  # the entry flap's plates from its hinge, then the exit flap's
var _span_vis: Node3D
var _plate_vis: Array[Node3D] = []
var _snd := {}
var _move: AudioStreamPlayer3D
var _moving := false
var _held := {}              # kart this peer drives -> how hard it is held down now (m/s^2)


func defaults() -> Dictionary:
	return {"length": 49.1, "apron": 16.0, "width": -1.0, "max": 2.0, "back": 2.0, "rest": -1.0, "speed": 7.0,
		"accel": 18.0, "lead": 0.25, "hold": 40.0, "hold_share": 0.25, "hold_ease": 50.0, "bend": 1.0,
		"model": SPAN_MODEL, "from": NAN, "to": NAN, "a": [], "b": [], "pier": NAN, "group": "seesaw"}


func build() -> void:
	aims_all = true
	_len = float(p["length"])
	_vmax = deg_to_rad(float(p["speed"]))
	_amax = deg_to_rad(float(p["accel"]))
	_lim = Vector2(-deg_to_rad(absf(float(p["back"]))), deg_to_rad(absf(float(p["max"]))))
	var a: Array = p["a"]
	var b: Array = p["b"]
	if a.size() == 3 and b.size() == 3:
		_ha = Vector3(a[0], a[1], a[2])
		_hb = Vector3(b[0], b[1], b[2])
	else:
		# no hinges in the data (a span put on a track at run time, tests): the road round s
		var half := _len * 0.5 + float(p["apron"])
		_ha = road_point(s - half, 0.0)
		_hb = road_point(s + half, 0.0)
	_fwd = Vector3(_hb.x - _ha.x, 0.0, _hb.z - _ha.z).normalized()
	_right = _fwd.cross(Vector3.UP).normalized()
	_pivot = (_ha + _hb) * 0.5
	_w = float(p["width"]) if float(p["width"]) > 0.0 else path.width[path.index_at(s)]
	var apron := (_hb - _ha).dot(_fwd) * 0.5 - _len * 0.5
	_n_plates = maxi(4, ceili(apron / PLATE_LEN))
	var rest := _rest()
	_seg = [0, -1e9, rest, 0.0, rest]
	_collision()
	_snd["strain"] = sounds([["physics/metal/metal_solid_strain1.wav", "physics/metal/metal_solid_strain2.wav",
		"physics/metal/metal_solid_strain3.wav", "physics/metal/metal_solid_strain4.wav",
		"physics/metal/metal_solid_strain5.wav"], ["physics/metal/metal_box_strain1.wav", "physics/metal/metal_box_strain2.wav"]])
	_snd["stop"] = sounds([["doors/drawbridge_stop1.wav"], ["physics/metal/metal_barrel_impact_soft1.wav"]])
	_snd["creak"] = sounds([["ambient/materials/creak5.wav", "ambient/materials/wood_creak1.wav",
		"ambient/materials/wood_creak2.wav", "ambient/materials/wood_creak3.wav"]])
	if visual:
		_build_visuals()
		_move = loop(["doors/drawbridge_move1.wav", "plats/crane/vertical_start.wav"], _span_vis, 22.0, -4.0)
	_place(rest)


func _rest() -> float:
	return 0.0 if still else clampf(deg_to_rad(float(p["rest"])), _lim.x, _lim.y)


## The target angle for a side (-1 entry end down, 0 empty, 1 exit end down).
func target(side: int) -> float:
	return _lim.y if side > 0 else (_lim.x if side < 0 else _rest())


# ---------------------------------------------------------------- the angle at clock t (pure)
## Vector3(angle, turning speed, its rate of change) at clock t of the event `seg` ([seq, t0, angle,
## speed, target]): it turns towards the target as fast as it may (at most vmax, speeding up and slowing
## down at amax) and comes to rest on it. Only +, -, *, / and sqrt: the same numbers on every machine.
static func profile(seg: Array, t: float, vmax: float, amax: float) -> Vector3:
	var t0 := float(seg[1])
	var x0 := float(seg[2])
	var v0 := clampf(float(seg[3]), -vmax, vmax)
	var d := float(seg[4]) - x0
	var tau := maxf(t - t0, 0.0)
	# which way it has to speed up: towards the target, unless it would overshoot it even stopping now
	var stop := v0 * absf(v0) / (2.0 * amax)
	var dir := 1.0 if d - stop >= 0.0 else -1.0
	var dd := d * dir
	var u0 := v0 * dir
	var peak := sqrt(maxf(amax * dd + u0 * u0 * 0.5, 0.0))
	var cruise := 0.0
	if peak > vmax:
		peak = vmax
		cruise = maxf((dd - (2.0 * vmax * vmax - u0 * u0) / (2.0 * amax)) / vmax, 0.0)
	var t1 := maxf((peak - u0) / amax, 0.0)
	var d1 := (peak * peak - u0 * u0) / (2.0 * amax)
	var t3 := peak / amax
	var x := 0.0
	var v := 0.0
	var acc := 0.0
	if tau < t1:
		x = u0 * tau + amax * tau * tau * 0.5
		v = u0 + amax * tau
		acc = amax
	elif tau < t1 + cruise:
		x = d1 + peak * (tau - t1)
		v = peak
	elif tau < t1 + cruise + t3:
		var w := tau - t1 - cruise
		x = d1 + peak * cruise + peak * w - amax * w * w * 0.5
		v = peak - amax * w
		acc = -amax
	else:
		x = dd
		v = 0.0
	return Vector3(x0 + x * dir, v * dir, acc * dir)


func angle_at(t: float) -> Vector3:
	return profile(_seg, t, _vmax, _amax)


## The deck's height over the pivot's at metres x from the pivot along the road, at angle th (on the
## span or on a flap; the hinge's height past it), and its slope there (tests check the bodies by it).
func deck_at(x: float, th: float) -> Vector2:
	var half := _len * 0.5
	if x <= _xa() or x >= _xb():
		return Vector2(((_ha.y if x < 0.0 else _hb.y) - _pivot.y), 0.0)
	if absf(x) <= half * cos(th):
		return Vector2(-x * tan(th), -tan(th))
	if x < 0.0:
		var y := flap_y(flap_of(0, th), x - _xa())
		return Vector2(y.x + (_ha.y - _pivot.y), y.y)
	var z := flap_y(flap_of(1, th), _xb() - x)
	return Vector2(z.x + (_hb.y - _pivot.y), -z.y)


## The deck's height over the pivot's at x and angle th in full precision (deck_at's height).
func deck_h(x: float, th: float) -> float:
	var half := _len * 0.5
	if x <= _xa() or x >= _xb():
		return (_ha.y if x < 0.0 else _hb.y) - _pivot.y
	if absf(x) <= half * cos(th):
		return -x * tan(th)
	var f := flap_of(0 if x < 0.0 else 1, th)
	var u := x - _xa() if x < 0.0 else _xb() - x
	var a := float(f[1])
	var c1 := float(f[2])
	u = clampf(u, 0.0, float(f[0]))
	var y := c1 * u * u * 0.5 if u <= a else c1 * a * a * 0.5 + c1 * a * (u - a) + float(f[3]) * (u - a) * (u - a) * 0.5
	return y + ((_ha.y if x < 0.0 else _hb.y) - _pivot.y)


## How fast the deck under a kart at x going v m/s along the road falls away from it (m/s^2, the
## deck's own downward acceleration along the kart's path; negative where it rises into it), as
## Vector2(the bend of a flap's crest: v^2 times its curvature, the turning deck's: 2 v times its
## turning speed and x times that speed's rate of change, on the span and the flaps it bends). st: the
## angle, its speed and its rate of change (angle_at).
func fall_away(x: float, v: float, st: Vector3) -> Vector2:
	var hx := 0.5
	var e := 2e-4
	var th := st.x
	var h0 := deck_h(x, th)
	var dxx := (deck_h(x + hx, th) - 2.0 * h0 + deck_h(x - hx, th)) / (hx * hx)
	var dxt := (deck_h(x + hx, th + e) - deck_h(x + hx, th - e) - deck_h(x - hx, th + e) + deck_h(x - hx, th - e)) / (4.0 * hx * e)
	var dt := (deck_h(x, th + e) - deck_h(x, th - e)) / (2.0 * e)
	var dtt := (deck_h(x, th + e) - 2.0 * h0 + deck_h(x, th - e)) / (e * e)
	return Vector2(-v * v * dxx, -(2.0 * v * st.y * dxt + st.y * st.y * dtt + st.z * dt))


func _xa() -> float:
	return (_ha - _pivot).dot(_fwd)


func _xb() -> float:
	return (_hb - _pivot).dot(_fwd)


## The entry flap (side 0) or the exit flap (1) at angle th, from its hinge to the span's end (flap).
func flap_of(side: int, th: float) -> Array:
	var half := _len * 0.5
	if side == 0:
		return flap(-half * cos(th) - _xa(), half * sin(th) - (_ha.y - _pivot.y), -tan(th), float(p["bend"]))
	return flap(_xb() - half * cos(th), -half * sin(th) - (_hb.y - _pivot.y), tan(th), float(p["bend"]))


## A flap from its hinge (level, height 0) over `len` metres to a span end `ye` up whose slope (going
## away from the hinge) is m: two arcs, the first bending one way and the second the other, meeting the
## hinge and the span end without a kink. The arc that bends up (a hollow, where the springs take the
## bend) has `r` times the curvature of the one that bends over a crest (where _hold_down keeps the karts
## on it). [len, a (where the arcs meet), c1, c2 (their curvatures)].
static func flap(len: float, ye: float, m: float, r := 1.0) -> Array:
	if absf(ye) < 1e-9 and absf(m) < 1e-9:
		return [len, len * 0.5, 0.0, 0.0]
	# a hump (it climbs, then bends over onto the span) starts with the hollow, a dip with the crest
	var hump := ye > 0.0 or (ye == 0.0 and m < 0.0)
	var rho := 1.0 / r if hump else r
	# b, the second arc's length: m b^2 - 2 ye b - (m len^2 - 2 ye len) / (1 + rho) = 0, its root in (0, len)
	var c := (m * len * len - 2.0 * ye * len) / (1.0 + rho)
	var b := len / (1.0 + rho)
	if absf(m) > 1e-12:
		var disc := maxf(ye * ye + m * c, 0.0)
		var q := ye + (sqrt(disc) if ye >= 0.0 else -sqrt(disc))
		var b1 := q / m
		var b2 := -c / q if absf(q) > 1e-15 else INF
		b = b1 if b1 > 0.0 and b1 < len else b2
	b = clampf(b, 0.0, len)
	var a := len - b
	var den_h := len * len * 0.5 - (1.0 + rho) * b * b * 0.5
	var den_s := a - rho * b
	var c1 := ye / den_h if absf(den_h) >= absf(den_s) * len * 0.5 else m / den_s
	return [len, a, c1, -rho * c1]


## Height and slope of flap f at u metres from its hinge.
static func flap_y(f: Array, u: float) -> Vector2:
	var a := float(f[1])
	var c1 := float(f[2])
	var c2 := float(f[3])
	u = clampf(u, 0.0, float(f[0]))
	if u <= a:
		return Vector2(c1 * u * u * 0.5, c1 * u)
	var w := u - a
	return Vector2(c1 * a * a * 0.5 + c1 * a * w + c2 * w * w * 0.5, c1 * a + c2 * w)


# ---------------------------------------------------------------- bodies and visuals
func _collision() -> void:
	_span_body = _body("road")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_w + 0.3, DECK_T, _len)
	cs.shape = box
	cs.position = Vector3(0.0, -DECK_T * 0.5, 0.0)
	_span_body.add_child(cs)
	var apron := (_hb - _ha).dot(_fwd) * 0.5 - _len * 0.5
	for i in _n_plates * 2:
		var pb := _body("road")
		var ps := CollisionShape3D.new()
		var pbox := BoxShape3D.new()
		pbox.size = Vector3(_w + 0.3, PLATE_T, apron / _n_plates + 2.0 * PLATE_LAP)
		ps.shape = pbox
		ps.position = Vector3(0.0, -PLATE_T * 0.5, 0.0)
		pb.add_child(ps)
		_plates.append(pb)
	# the side walls stand still: from below the lowest the deck goes to well above the highest
	var walls := StaticBody3D.new()
	walls.collision_layer = Game.LAYER_WORLD
	walls.collision_mask = 0
	walls.set_meta("surface", "wall")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05
	pm.bounce = 0.15
	walls.physics_material_override = pm
	add_child(walls)
	walls.top_level = true
	var low := _len * 0.5 * sin(maxf(-_lim.x, _lim.y)) + 2.0
	var length := (_hb - _ha).dot(_fwd) + 2.0
	walls.global_transform = Transform3D(Basis(_right, Vector3.UP, -_fwd), _pivot)
	for sg in [-1.0, 1.0]:
		var ws := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(WALL_T, low + WALL_UP, length)
		ws.shape = wb
		ws.position = Vector3(sg * (_w * 0.5 + WALL_T * 0.5), (WALL_UP - low) * 0.5, 0.0)
		walls.add_child(ws)


## A kinematic body of the deck (surface "road": the tyres ride it).
func _body(surface: String) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.collision_layer = Game.LAYER_WORLD
	b.collision_mask = 0
	b.sync_to_physics = true
	b.set_meta("surface", surface)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	b.physics_material_override = pm
	add_child(b)
	b.top_level = true
	return b


func _build_visuals() -> void:
	var metal := _mat("models/seesawbridge/bridge_colour", Color(0.36, 0.38, 0.33), 0.25)
	var floor := _mat("metal/metalfloor001a", Color(0.42, 0.42, 0.4), 0.5)
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.3, 0.32, 0.28)
	rail.roughness = 0.7
	rail.metallic = 0.3
	_span_vis = Node3D.new()
	add_child(_span_vis)
	_span_vis.top_level = true
	var key := pick_model([str(p["model"]), SPAN_MODEL])
	var copies := 1 if _w <= 7.5 else ceili(_w / 6.6)
	if key != "":
		var box := Game.model_aabb(key)
		var c := box.get_center()
		var top := box.end.y
		for j in copies:
			var m := Game.spawn_model(key)
			_span_vis.add_child(m)
			# the model's long axis (x) along the road, its width (z) across, its deck top on the road
			var sw := (_w / copies) / box.size.z
			var basis := Basis(Vector3(0, 0, -1) * _len / box.size.x, Vector3.UP, Vector3.RIGHT * sw)
			var lat := (j + 0.5) * _w / copies - _w * 0.5
			m.transform = Transform3D(basis, Vector3(lat, -SPAN_SINK, 0.0) - basis * Vector3(c.x, top, c.z))
		# the model is a girder frame with an alpha-tested grating whose top beams run along its edges
		# and turn across it at its ends: a steel plate over the whole span at the road's height is the
		# road the wheels ride on, with the model's top beams under it and its girders showing below (a
		# plate under the top beams left rust-red beams lying along and across the lanes). It stops
		# short of the span's ends by the flaps' overlap, where the first plate of each flap lies.
		_span_vis.add_child(_mesh([[Vector3(0.0, -SPAN_PLATE * 0.5, 0.0),
			Vector3(_w - 0.02, SPAN_PLATE, _len - 2.0 * PLATE_LAP - 0.02)]], floor))
	else:
		# a stand-in for an install without Episode Two's span: a plain steel deck
		_span_vis.add_child(_mesh([[Vector3(0.0, -DECK_T * 0.5, 0.0), Vector3(_w, DECK_T, _len)]], metal))
	# its railings (posts every 3 m, a top and a middle rail) and the axle under the pivot
	var bars := []
	for sg in [-1.0, 1.0]:
		var x: float = sg * (_w * 0.5 - 0.06)
		bars.append([Vector3(x, 1.05, 0.0), Vector3(0.1, 0.1, _len)])
		bars.append([Vector3(x, 0.55, 0.0), Vector3(0.06, 0.06, _len)])
		var n := int(_len / 3.0)
		for k in n + 1:
			bars.append([Vector3(x, 0.55, -_len * 0.5 + _len * k / n), Vector3(0.1, 1.1, 0.1)])
	bars.append([Vector3(0.0, -DECK_T - 0.45, 0.0), Vector3(_w + 1.6, 0.9, 0.9)])
	_span_vis.add_child(_mesh(bars, rail))
	# the flaps' plates, each with its piece of railing
	var apron := (_hb - _ha).dot(_fwd) * 0.5 - _len * 0.5
	var pl := apron / _n_plates + 2.0 * PLATE_LAP
	for i in _n_plates * 2:
		var host := Node3D.new()
		add_child(host)
		host.top_level = true
		host.add_child(_mesh([[Vector3(0.0, -PLATE_T * 0.5, 0.0), Vector3(_w, PLATE_T, pl)]], floor))
		var pr := []
		for sg in [-1.0, 1.0]:
			var x: float = sg * (_w * 0.5 - 0.06)
			pr.append([Vector3(x, 1.05, 0.0), Vector3(0.1, 0.1, pl)])
			pr.append([Vector3(x, 0.55, 0.0), Vector3(0.06, 0.06, pl)])
			pr.append([Vector3(x, 0.55, 0.0), Vector3(0.1, 1.1, 0.1)])
		host.add_child(_mesh(pr, rail))
		_plate_vis.append(host)
	# the pier under the pivot down to the ravine's floor, and a beam under each hinge
	var concrete := _mat("concrete/concretewall008a", Color(0.55, 0.54, 0.5), 0.25)
	var fixed := Node3D.new()
	add_child(fixed)
	fixed.top_level = true
	fixed.global_transform = Transform3D(Basis(_right, Vector3.UP, -_fwd), _pivot)
	var parts := []
	var floor_y := float(p["pier"])
	if is_finite(floor_y) and floor_y < _pivot.y - 3.0:
		var top := -DECK_T - 0.9
		var h := top - (floor_y - _pivot.y) + 1.0
		parts.append([Vector3(0.0, top - h * 0.5, 0.0), Vector3(minf(_w * 0.6, 6.0), h, 3.0)])
	for xh in [(_ha - _pivot).dot(_fwd), (_hb - _pivot).dot(_fwd)]:
		var back := signf(xh) * 0.6
		parts.append([Vector3(0.0, -1.0, -(xh + back)), Vector3(_w + 1.4, 1.9, 1.2)])
	fixed.add_child(_mesh(parts, concrete))


## A triplanar material from a Source texture (`fallback` colour when it is not installed).
static func _mat(name: String, fallback: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := SourceMaterials.albedo(name)
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * scale
	else:
		m.albedo_color = fallback
	m.roughness = 0.85
	return m


## One mesh of boxes ([centre, size] each) in one material.
static func _mesh(boxes: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		var bm := BoxMesh.new()
		bm.size = b[1]
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, b[0]))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## Puts the span, the plates and their visuals at angle th (radians, positive: the exit end down).
func _place(th: float) -> void:
	if is_equal_approx(th, _placed):
		return
	_placed = th
	var d := _fwd * cos(th) - Vector3.UP * sin(th)
	var nrm := Vector3.UP * cos(th) + _fwd * sin(th)
	var xf := Transform3D(Basis(_right, nrm, -d), _pivot)
	_span_body.global_transform = xf
	if _span_vis:
		_span_vis.global_transform = xf
	var hinges := [_ha, _hb]
	for side in 2:
		var h: Vector3 = hinges[side]
		var along := _fwd if side == 0 else -_fwd
		var f := flap_of(side, th)
		var prev := h
		for i in _n_plates:
			var u := float(f[0]) * (i + 1) / _n_plates
			var q := h + along * u + Vector3.UP * flap_y(f, u).x
			var c := q - prev
			var n := _right.cross(c.normalized())
			if n.y < 0.0:
				n = -n
			var pxf := Transform3D(Basis(_right, n, _right.cross(n)), (prev + q) * 0.5)
			var k := side * _n_plates + i
			_plates[k].global_transform = pxf
			if k < _plate_vis.size():
				_plate_vis[k].global_transform = pxf
			prev = q


# ---------------------------------------------------------------- the race
func tick(t: float, dt: float) -> void:
	# the bodies follow the shared clock a physics step at a time, slewed toward it: online the clock is
	# the wall clock, read by a frame's physics steps back to back (a whole frame on the first, nothing on
	# the next), and the deck moved in jerks the karts on it felt and were thrown by at 30 fps. Offline the
	# clock moves by dt a step: the same angle.
	if not is_finite(_tc) or absf(t - (_tc + dt)) > 0.25:
		_tc = t
	else:
		_tc += dt + clampf(t - (_tc + dt), -0.1 * dt, 0.1 * dt)
	var st := angle_at(_tc)
	_ease = move_toward(_ease, 0.0, EASE_RATE * dt)
	_place(clampf(st.x + _ease, _lim.x - 0.01, _lim.y + 0.01))
	if float(p["hold"]) > 0.0:
		_hold_down(st, dt)
	if director.authority():
		_weigh_tick(t)
	if visual:
		var moving := st.y != 0.0
		if moving != _moving:
			_moving = moving
			if _move:
				if moving:
					_move.play()
				else:
					_move.stop()
			if not moving:
				play(_snd["stop"], _pivot, 2.0, 24.0)


## Keeps the karts this peer drives on the deck wherever it falls away under them faster than the road
## would: over a flap's crest (from climbing to falling, or where it falls away from its hinge) and on
## the span swinging down under a kart driving along it. There a kart at speed would leave the deck
## with the deck still dropping and fly over half the span. While it is on the deck (not once it is in
## the air) it is held down by what the deck's fall needs (HOLD_NEAR), up to p["hold"] m/s^2, easing
## off after.
func _hold_down(st: Vector3, dt: float) -> void:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var xa := _xa()
	var xb := _xb()
	for k in local_karts():
		var want := 0.0
		var q := k.global_position - _pivot
		var x := q.dot(_fwd)
		var dk := deck_at(x, st.x)
		var on := k.state != Kart.State.RESPAWN and not k.freeze and x > xa and x < xb \
			and absf(q.dot(_right)) <= _w * 0.5 + 0.5 and q.y - dk.x <= HOLD_NEAR
		if on:
			var fall := fall_away(x, k.linear_velocity.dot(_fwd), st)
			want = clampf(maxf(fall.x - g * float(p["hold_share"]), 0.0) + maxf(fall.y, 0.0), 0.0, float(p["hold"]))
		var now := maxf(want, float(_held.get(k, 0.0)) - float(p["hold_ease"]) * dt)
		if now <= 0.0:
			_held.erase(k)
			continue
		_held[k] = now
		if on:
			k.apply_central_force(-(Vector3.UP - _fwd * dk.y).normalized() * k.mass * now)


func _weigh_tick(t: float) -> void:
	if t < _next_weigh:
		return
	_next_weigh = t + WEIGH
	var want := weigh()
	if want != _side and t - _sent_t >= HOLD:
		_side = want
		_emit(t)
	elif t - maxf(_sent_t, _resent_t) >= RESEND and angle_at(t).y == 0.0:
		# at rest, the state it rests in again as a fresh event (every peer that has it turns exactly as
		# before): a peer that lost an event, or took a forged one, is right again
		_resent_t = t
		_seq += 1
		_sending = true
		send("tilt", [_seq, t, float(_seg[4]), 0.0, float(_seg[4])])
		_sending = false


## Sends the event for the side the authority now wants, from the angle and speed at clock t (at rest,
## the angle it rests at to the last digit: angle_at's own is a float32 one).
func _emit(t: float) -> void:
	var st := angle_at(t)
	var from := float(_seg[4]) if st.y == 0.0 else st.x
	_seq += 1
	_sent_t = t
	_sending = true
	send("tilt", [_seq, t, from, st.y, target(_side)])
	_sending = false


## The side the span should tip to for the karts on it now: -1 its entry end down, 1 its exit end,
## 0 nobody on it; inside the dead band the side it tips to stays.
func weigh() -> int:
	var half := _len * 0.5
	var torque := 0.0
	var on := false
	for k in all_karts():
		if not is_instance_valid(k) or k.state == Kart.State.RESPAWN:
			continue
		var q := k.global_position - _pivot
		var x := q.dot(_fwd)
		if absf(x) > half or absf(q.dot(_right)) > _w * 0.5 + 1.0 or absf(q.y) > 4.0:
			continue
		on = true
		x = clampf(x + k.velocity().dot(_fwd) * float(p["lead"]), -half, half)
		torque += x / half * k.mass / Kart.JEEP_MASS
	if not on:
		return 0
	if torque > DEAD:
		return 1
	if torque < -DEAD:
		return -1
	return _side if _side != 0 else (1 if torque > 0.0 else -1)


## "tilt" [seq, t0, angle, speed, target] (radians, radians per second): turn from that event on.
## Only the authority sends one; an older one than the event it is turning by is dropped, and a
## forged one can not take the span past its limits or hold it for long (the next weighing replaces it).
func on_event(kind: String, args: Array) -> void:
	if kind != "tilt" or args.size() < 5:
		return
	if Net.active and Net.is_server and not _sending:
		return
	var t0 := float(args[1])
	if Net.active and not Net.is_server and absf(t0 - director.clock()) > 6.0:
		return
	var seq := int(args[0])
	if t0 < float(_seg[1]) or (t0 == float(_seg[1]) and seq <= int(_seg[0])):
		return
	var ev := [seq, t0, clampf(float(args[2]), _lim.x - 0.01, _lim.y + 0.01), clampf(float(args[3]), -_vmax, _vmax),
		clampf(float(args[4]), _lim.x, _lim.y)]
	# a client hears of a tilt a latency after the server's clock t0 it starts at, and online even the
	# server's deck (on _tc) runs a moment behind its clock: the new swing would put the deck somewhere
	# else in one step. It eases over from where the deck is shown instead (offline: no difference, 0).
	var tc := _tc if is_finite(_tc) else director.clock()
	var before := _placed if is_finite(_placed) else angle_at(tc).x
	_seg = ev
	_ease = clampf(before - angle_at(tc).x, -EASE_MAX, EASE_MAX)
	_seq = maxi(_seq, seq)
	director.note(self, "fire")
	if visual and absf(float(ev[4]) - float(ev[2])) > 0.005:
		play(_snd["strain"], _pivot + Vector3.DOWN * 1.5, 4.0, 30.0)
		play(_snd["creak"], _pivot - _fwd * _len * 0.4, 0.0, 18.0)


func wake() -> void:
	_tc = NAN
	_ease = 0.0
	_place(angle_at(director.clock()).x)


func sleep() -> void:
	if _move:
		_move.stop()
	_moving = false
	_held.clear()
	_tc = NAN
	_ease = 0.0


## A kart put back on the road here could come down on a tilted deck or inside it.
func blocks_respawn(at_s: float) -> bool:
	var a := float(p["from"]) if is_finite(float(p["from"])) else s - _len * 0.5 - float(p["apron"])
	var b := float(p["to"]) if is_finite(float(p["to"])) else s + _len * 0.5 + float(p["apron"])
	return director.in_span(at_s, a - 6.0, b + 6.0)


## A kart blocked just past the exit hinge (on the exit deck already) goes on a few metres, off the
## stretch, not back before the entry (~145 m and the see-saw again).
func respawn_s(at_s: float) -> float:
	var b := float(p["to"]) if is_finite(float(p["to"])) else s + _len * 0.5 + float(p["apron"])
	if director.in_span(at_s, b - 12.0, b + 6.0):
		return fposmod(b + 6.5, path.length)
	return super(at_s)


## It never hurts a kart: the minimap leaves it out.
func on_map() -> bool:
	return false


func snapshot(t: float) -> Array:
	var st := angle_at(t)
	return [int(_seg[0]), snappedf(st.x, 1e-6), snappedf(st.y, 1e-6), snappedf(float(_seg[4]), 1e-6)]


## Made-up events for the determinism test (no karts): a swing down towards the exit at t0, and
## from wherever that has got to at t0 + 0.6 back towards the entry.
func test_events(t0: float) -> Array:
	var first := [1, t0, _rest(), 0.0, _lim.y]
	var mid := profile(first, t0 + 0.6, _vmax, _amax)
	return [first, [2, t0 + 0.6, mid.x, mid.y, _lim.x]]
