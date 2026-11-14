class_name StriderHazard
extends Hazard
## A Combine strider beside the road. It walks its own route beside the track (p["walk"]: points
## on the ground that tools/hazards.py resolved from the spec's waypoints; with none it stands
## where it was placed), its body and guns turned to the road. Once a cycle it halts at the next
## station of its route, crouches and fires its warp cannon at the nearest kart it can see; while
## it walks on it rakes the road with its machine gun. Where it is, how it steps and every burst
## of the gun are
## functions of the shared hazard clock and its seed: the same on every peer with no network
## traffic. Only the cannon's target is chosen by the server (or the offline game), which sends
## one "aim" event when the charge starts; the cannon goes off at t_fire on the shared clock on
## every peer, and each kart's owner judges its own karts. Its three legs are posed by IK onto
## footholds on the static world: each foot lifts, swings and lands, planted while it is down.

const GLOW := Color(0.45, 0.75, 1.0)
const LASER := Color(0.4, 0.75, 1.0, 0.8)
const LEGS := ["Right", "Left", "Hind"]
const FEET := {"Left": 0, "Right": 1, "Hind": 2}   # order of p["feet"] and FOOT_HOME (tools/hazards.py)
## Where each foot meets the ground at rest, model space (the model's foot attachments): the gait
## steps between footholds found from these, the same on every peer whatever model is installed.
const FOOT_HOME := [Vector3(2.308, 0.0, 3.043), Vector3(-2.148, 0.0, 2.994), Vector3(0.0, 0.0, -3.848)]
## Where in the gait cycle each foot lifts: one foot in the air at a time, left, hind, right.
const GAIT_OFFSET := [0.0, 1.0 / 3.0, 2.0 / 3.0]
const SWING := 0.32         # the share of its gait cycle a foot spends in the air
const LIFT := 1.4           # metres (model) a foot lifts mid-swing on a full stride
const CROUCH := 1.5         # metres it sinks to fire its cannon
const WALK_CROUCH := 1.0    # metres it sinks while it walks, so its legs reach the long strides
const PRE := 1.0            # seconds it stands at a station before its charge starts
const AFTER := 1.4          # seconds it stands after its shot before it walks on
const RAMP := 0.2           # the share of a walk it spends speeding up (and as much slowing down)
const RESCUED := 2.5        # seconds after a rescue a kart is not taken as a target
## the shares of its lead the cannon tries in turn for an aim point its gun sees (_aim_point)
const AIM_LEADS := [1.0, 0.6, 0.3, 0.0]
const LINE_SEGS := 6

var model: Node3D
var sk: Skeleton3D
var _m2s := Transform3D.IDENTITY
var _body_b := -1
var _neck_b := -1
var _head_b := -1
var _gun_b := -1
var _mg_b := -1
var _gun_m := Vector3(0.03, 10.36, 2.38)   # BigGun, model space
var _mg_m := Vector3(0.05, 10.85, 2.33)    # MiniGun, model space
## [upper, lower, hip, knee, foot, rest foot target, l1, l2, foot index, foot bone - contact]
## (skeleton space)
var _legs: Array = []
## cycle -> [t_fire, aim point, lap s, lateral, target's slot (-1: none), where the target was]
var _aims := {}
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _line: Array[MeshInstance3D] = []      # the machine gun's laser line on the road
var _sight: MeshInstance3D                 # the machine gun's sweeping laser sight
var _head := Vector2.ZERO                  # yaw, pitch the head has turned
var _crouch := 0.0                         # metres the body sinks now (set each frame)
var _bob := 0.0
var _feet_now: Array = []                  # the feet's world points this frame (none: at rest)
var _fired_at := -1e9
var _idle_t := 4.0
var _snd := {}
# its route, all from the hazard's data and the lap: the same on every peer
var _route := PackedVector3Array()
var _cum := PackedFloat32Array()           # metres along the route at each point
var _stations := PackedFloat32Array()      # metres along the route where it halts
var _watch := PackedFloat32Array()         # lap s of the road point each station looks at
var _face := PackedFloat32Array()          # yaw facing that road point from each station
var _pass: Array[bool] = []                # stations on a road crossing: it walks on through them
var _j0 := 0
var _gait := 2.4                           # seconds per gait cycle
var _pace := 0.0                           # metres a second while it walks
var _holds := {}                           # foothold cache: step * 3 + foot -> world point
var _bursts := {}                          # cycle -> its machine gun burst (burst())
var _rescued := {}                         # kart -> clock it was last seen being rescued


func defaults() -> Dictionary:
	return {"zone": [s - 40.0, s + 110.0], "scale": 1.15, "cycle": 9.0, "phase": 4.0, "charge": 2.4, "radius": 6.5,
		"push": 0.3, "lift": 0.6, "lead": 0.9, "effect": "tumble", "feet": [0.0, 0.0, 0.0], "range": 110.0,
		"fov": 140.0, "sight": true, "walk": [], "cross": [], "speed": 2.4, "stride": 4.2, "start": -1,
		"gun": true, "gun_warn": 1.0, "gun_time": 1.4, "gun_rate": 12.0, "gun_sweep": 16.0, "gun_ahead": 14.0,
		"gun_lat": 3.0, "gun_jitter": 1.0, "gun_hit": 2.0, "gun_effect": "spin", "gun_range": 90.0}


func build() -> void:
	aims_all = true
	_snd["alert"] = sounds([["npc/strider/striderx_alert4.wav"], ["npc/strider/striderx_alert2.wav"]])
	_snd["charge"] = sounds([["npc/strider/charging.wav"]])
	_snd["fire"] = sounds([["npc/strider/fire.wav"]])
	_snd["idle"] = sounds([["npc/strider/creak1.wav", "npc/strider/creak2.wav"], ["npc/strider/strider_step1.wav"]])
	_snd["step"] = sounds([["npc/strider/strider_step1.wav", "npc/strider/strider_step2.wav",
		"npc/strider/strider_step3.wav", "npc/strider/strider_step4.wav", "npc/strider/strider_step5.wav",
		"npc/strider/strider_step6.wav"]])
	_snd["gun_warn"] = sounds([["npc/strider/strider_hunt1.wav", "npc/strider/strider_hunt2.wav"],
		["npc/strider/striderx_alert2.wav"]])
	_snd["gun"] = sounds([["npc/strider/strider_minigun.wav", "npc/strider/strider_minigun2.wav"],
		["weapons/irifle/irifle_fire2.wav"]])
	_snd["ric"] = sounds(TurretHazard.RICOCHETS)
	_route_setup()
	if not visual or not Game.models.has("combine_strider"):
		return
	model = Game.spawn_model("combine_strider")
	add_child(model)
	model.top_level = true
	var sc := float(p["scale"])
	var xf := body_xf(0.0)
	model.global_transform = Transform3D(xf.basis.scaled(Vector3.ONE * sc), xf.origin)
	sk = HazardRig.skeleton(model)
	var gun := HazardRig.attachment("combine_strider", "BigGun")
	if not gun.is_empty():
		_gun_m = gun[0]
	var mg := HazardRig.attachment("combine_strider", "MiniGun")
	if not mg.is_empty():
		_mg_m = mg[0]
	if sk:
		_m2s = HazardRig.model_to_skeleton(model, sk)
		_body_b = HazardRig.bone(sk, "Body_Bone")
		_neck_b = HazardRig.bone(sk, "Neck_Bone")
		_head_b = HazardRig.bone(sk, "Head_Bone")
		_gun_b = HazardRig.bone(sk, gun[1]) if not gun.is_empty() else _head_b
		_mg_b = HazardRig.bone(sk, mg[1]) if not mg.is_empty() else _head_b
		_setup_legs()
	_beam = Effects.beam_node(Color(GLOW, 0.0), 0.12, "materials/effects/bluelaser1.png")
	add_child(_beam)
	_beam.visible = false
	_ring = Effects.ground_ring(self, global_position, Vector3.UP, float(p["radius"]), Color(0.3, 0.9, 1.0, 0.0))
	_ring.visible = false
	_glow = glow("materials/effects/strider_muzzle.png", 2.0, GLOW)
	_glow.visible = false
	_light = light(GLOW, 16.0, 0.0)
	_sight = Effects.beam_node(LASER, 0.07, "materials/effects/bluelaser1.png")
	add_child(_sight)
	_sight.visible = false
	for i in LINE_SEGS:
		var b := Effects.beam_node(LASER, 0.2, "materials/sprites/laserbeam.png", true)
		add_child(b)
		b.visible = false
		_line.append(b)


## Hip, knee and foot of each leg at rest; at rest the foot's target sits on the ground under it
## (tools/hazards.py measured how far each foot's ground is above or below the body's).
func _setup_legs() -> void:
	var feet: Array = p["feet"]
	var sc := float(p["scale"])
	for leg in LEGS:
		var up := HazardRig.bone(sk, "Leg_%s_Bone" % leg)
		var low := HazardRig.bone(sk, "Leg_%s_Bone1" % leg)
		var foot := HazardRig.bone(sk, "Foot_%s" % leg)
		if up < 0 or low < 0 or foot < 0:
			continue
		var hip := sk.get_bone_global_rest(up).origin
		var kn := sk.get_bone_global_rest(low).origin
		var ft := sk.get_bone_global_rest(foot).origin
		var k: int = FEET[leg]
		var target := ft + _m2s.basis * Vector3(0.0, float(feet[k]) / sc, 0.0)
		_legs.append([up, low, hip, kn, ft, target, hip.distance_to(kn), kn.distance_to(ft), k,
			ft - _m2s * (FOOT_HOME[k] as Vector3)])


# ---------------------------------------------------------------- the route (pure)
## The route from p["walk"], the stations it halts at (evenly spaced, at most as far apart as it
## walks in a cycle at NORMAL; one on a road crossing it walks through), the road point each
## station looks at, and its pace and gait. A strider with no walk has one station where it stands.
func _route_setup() -> void:
	for q in p["walk"]:
		if q is Array and (q as Array).size() >= 3:
			_route.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if _route.size() < 2:
		_route = PackedVector3Array([position])
	_cum.resize(_route.size())
	var total := 0.0
	for i in _route.size():
		if i > 0:
			total += Vector2(_route[i].x - _route[i - 1].x, _route[i].z - _route[i - 1].z).length()
		_cum[i] = total
	var walk_t := maxf(float(p["cycle"]) - PRE - float(p["charge"]) - AFTER, 1.0)
	var m := 0 if total < 1.0 else maxi(1, ceili(total / (float(p["speed"]) * walk_t)))
	for j in m + 1:
		var u := total * j / maxf(m, 1.0)
		_stations.append(u)
		_pass.append(j > 0 and j < m and _on_crossing(u))
		var q := _point(u)
		var ws := _watch_point(q)
		_watch.append(ws)
		var to := road_point(ws, 0.0) - q
		_face.append(atan2(to.x, to.z) if m > 0 else rotation.y)
	_j0 = int(p["start"]) if int(p["start"]) >= 0 else int(rnd(3, 1) * 2.0 * m)
	if m > 0:
		_pace = total / m / _walk_time()
		_gait = clampf(float(p["stride"]) / maxf(_pace, 0.1), 0.9, 3.2)
		# the camera wakes it from anywhere near its route
		var mid := Vector3.ZERO
		for q in _route:
			mid += q / _route.size()
		position = mid


## True when `u` metres along the route lie on (or within 6 m of) a stretch where it steps over a
## road (p["cross"]): it never halts there.
func _on_crossing(u: float) -> bool:
	for c in p["cross"]:
		if c is Array and (c as Array).size() == 2 and u > float(c[0]) - 6.0 and u < float(c[1]) + 6.0:
			return true
	return false


## The lap metres (inside its zone) of the road point nearest q: where the strider looks from there.
func _watch_point(q: Vector3) -> float:
	var zone: Array = p["zone"]
	var z0 := float(zone[0])
	var length := ahead(z0, float(zone[1]))
	var best := fposmod(z0, path.length)
	var bd := INF
	var x := 0.0
	while x <= length:
		var d := q.distance_squared_to(path.center_at(z0 + x))
		if d < bd:
			bd = d
			best = fposmod(z0 + x, path.length)
		x += 2.0
	return best


## Seconds it walks in a cycle at this race's difficulty.
func _walk_time() -> float:
	return maxf(tm("cycle") - PRE - tm("charge") - AFTER, 1.0)


func _cycle_at(t: float) -> int:
	return int(floor((t - float(p["phase"])) / tm("cycle")))


## When cycle c starts: the charge of its cannon (it has stood at its station since PRE before).
func _cycle_start(c: int) -> float:
	return float(p["phase"]) + c * tm("cycle")


## The station it reaches for cycle c's start: back and forth along the route.
func _station(c: int) -> int:
	var m := _stations.size() - 1
	if m <= 0:
		return 0
	var n := posmod(c + _j0, 2 * m)
	return n if n <= m else 2 * m - n


## True when it halts for cycle c (its station is not on a road crossing): it may fire then.
func halts(c: int) -> bool:
	return not _pass[_station(c)]


## The first cycle from c on that it halts for.
func next_halt(c: int) -> int:
	var b := c
	while not halts(b) and b < c + 32:
		b += 1
	return b


## Its walk at clock t: [the station it set off from, the station it halts at next, 0..1 of the
## time between]. It stands at a cycle's station from PRE before the charge until AFTER the shot,
## and walks on through a station on a road crossing without stopping.
func _leg(t: float) -> Array:
	if _stations.size() < 2:
		return [0, 0, 0.0]
	var c := _cycle_at(t)
	var r := t - _cycle_start(c)
	var post := tm("charge") + AFTER
	if halts(c) and r <= post:
		return [_station(c), _station(c), 0.0]
	if halts(c + 1) and r >= tm("cycle") - PRE:
		return [_station(c + 1), _station(c + 1), 0.0]
	var a := c
	while not halts(a) and a > c - 32:
		a -= 1
	var b := next_halt(c + 1)
	var t0 := _cycle_start(a) + post
	var t1 := _cycle_start(b) - PRE
	return [_station(a), _station(b), clampf((t - t0) / maxf(t1 - t0, 0.1), 0.0, 1.0)]


## 0..1 of the way along a walk at 0..1 of its time: speeding up, steady, slowing down.
static func _ease(x: float) -> float:
	var k := 2.0 * RAMP * (1.0 - RAMP)
	if x < RAMP:
		return x * x / k
	if x > 1.0 - RAMP:
		return 1.0 - (1.0 - x) * (1.0 - x) / k
	return (x - RAMP * 0.5) / (1.0 - RAMP)


## Metres along its route at clock t.
func route_u(t: float) -> float:
	if _stations.size() < 2:
		return 0.0
	var lg := _leg(t)
	return lerpf(_stations[lg[0]], _stations[lg[1]], _ease(lg[2]))


## The ground point `u` metres along its route.
func _point(u: float) -> Vector3:
	var n := _route.size()
	if n == 1:
		return _route[0]
	u = clampf(u, 0.0, _cum[n - 1])
	var i := clampi(_cum.bsearch(u), 1, n - 1)
	var a := _cum[i - 1]
	return _route[i - 1].lerp(_route[i], (u - a) / maxf(_cum[i] - a, 0.0001))


## Its heading at clock t: towards the road point its station watches, turning slowly from one
## station's to the next as it walks. Like HL2's strider it walks any way it likes (sideways
## along the road, mostly) while it keeps its body and guns on the road.
func yaw_at(t: float) -> float:
	var lg := _leg(t)
	return lerp_angle(_face[lg[0]], _face[lg[1]], smoothstep(0.0, 1.0, float(lg[2])))


## Where it stands (the ground under its body, on its route) and which way it faces at clock t.
func body_xf(t: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw_at(t)), _point(route_u(t)))


## 0..1: how fast it is walking at clock t (1 at its pace).
func _moving(t: float) -> float:
	if _pace <= 0.0:
		return 0.0
	return clampf(absf(route_u(t + 0.1) - route_u(t - 0.1)) / 0.2 / _pace, 0.0, 1.0)


## The lap s it looks at, at clock t (between its stations' while it walks).
func _watch_at(t: float) -> float:
	var lg := _leg(t)
	var a := _watch[lg[0]]
	var d := wrapf(_watch[lg[1]] - a, -path.length * 0.5, path.length * 0.5)
	return fposmod(a + d * _ease(lg[2]), path.length)


## Lap metres where a kart on the centre line is in its cannon's sight when cycle c starts (tests:
## pick c with next_halt).
func probe_s(c: int) -> float:
	return _watch[_station(c)]


# ---------------------------------------------------------------- the gait (pure)
## The foothold of foot k for its step n: under where the body will be half way through that
## step's stance, on the ground (the static world's, or its route's height where there is none).
func _foothold(k: int, n: int) -> Vector3:
	var key := n * 3 + k
	if _holds.has(key):
		return _holds[key]
	var mid := (n + SWING + (1.0 - SWING) * 0.5 - float(GAIT_OFFSET[k])) * _gait
	var xf := body_xf(mid)
	var q: Vector3 = xf * ((FOOT_HOME[k] as Vector3) * float(p["scale"]))
	q.y = _ground(q, xf.origin.y, k)
	if _holds.size() > 96:
		_holds.clear()
	_holds[key] = q
	return q


## The ground height under q: on a walk the first floor of the static world under it (not
## something it stands under, nor a wall top); a strider that stands still has its feet's
## heights from its data.
func _ground(q: Vector3, hint: float, k: int) -> float:
	if _route.size() < 2:
		return hint + float((p["feet"] as Array)[k])
	if not visual or not is_inside_tree():
		return hint
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, hint + 6.0, q.z), Vector3(q.x, hint - 10.0, q.z), Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	if not hit.is_empty() and float(hit["position"].y) < hint + 4.0:
		return float(hit["position"].y)
	return hint


## Foot k at clock t: [where it is (lifted while it swings), the ground under it].
func foot_at(k: int, t: float) -> Array:
	var ph := t / _gait + float(GAIT_OFFSET[k])
	var n := floori(ph)
	var f := ph - n
	var to := _foothold(k, n)
	if f >= SWING:
		return [to, to.y]
	var from := _foothold(k, n - 1)
	var w := f / SWING
	var q := from.lerp(to, smoothstep(0.0, 1.0, w))
	var floor_y := q.y
	var d := Vector2(to.x - from.x, to.z - from.z).length()
	q.y += sin(PI * w) * LIFT * float(p["scale"]) * clampf(d / 1.5, 0.0, 1.0)
	return [q, floor_y]


# ---------------------------------------------------------------- the machine gun (pure)
## Cycle c's machine gun burst while it walks: [warning from, first shot, lap s of the first
## impact, lateral], or [] (no gun, too little time, the road out of its range, before the race).
## The burst walks its impacts back down the lap from its first one, towards the oncoming karts.
func burst(c: int) -> Array:
	if _bursts.has(c):
		return _bursts[c]
	var out := []
	var walk := _walk_time()
	var warn := float(p["gun_warn"]) * director.scale("warn")
	var dur := float(p["gun_time"])
	if bool(p["gun"]) and walk >= warn + dur + 0.6:
		var tw := _cycle_start(c) + tm("charge") + AFTER + (walk - warn - dur) * (0.25 + 0.5 * rnd(c, 11))
		var mid := tw + warn + dur * 0.5
		var ws := _watch_at(mid)
		if tw > 0.5 and road_point(ws, 0.0).distance_to(body_xf(mid).origin) <= float(p["gun_range"]):
			var lat := (-1.0 if rnd(c, 12) < 0.5 else 1.0) * float(p["gun_lat"])
			out = [tw, tw + warn, _line_start(ws + float(p["gun_ahead"])), lat]
	if _bursts.size() > 8:
		_bursts.clear()
	_bursts[c] = out
	return out


## The first impact's lap s, moved so the whole line lies inside the zone.
func _line_start(at_s: float) -> float:
	var zone: Array = p["zone"]
	var z0 := float(zone[0])
	var span_len := ahead(z0, float(zone[1]))
	var line := float(p["gun_sweep"]) * float(p["gun_time"])
	var x := wrapf(at_s - z0, -path.length * 0.5, path.length * 0.5)
	return fposmod(z0 + clampf(x, minf(line, span_len), span_len), path.length)


func _shots() -> int:
	return int(float(p["gun_time"]) * float(p["gun_rate"]))


## Shot k of cycle c's burst: [clock time, impact point on the road].
func shot(c: int, k: int) -> Array:
	var b := burst(c)
	var u := k / float(p["gun_rate"])
	var at_s := float(b[2]) - float(p["gun_sweep"]) * u
	var hw := half_width(at_s) - 0.8
	var lat := float(b[3]) + (rnd(c, 100 + k) * 2.0 - 1.0) * float(p["gun_jitter"])
	return [float(b[1]) + u, road_point(at_s, clampf(lat, -hw, hw), 0.05)]


func snapshot(t: float) -> Array:
	var xf := body_xf(t)
	var c := _cycle_at(t)
	var out: Array = [xf.origin.snapped(Vector3.ONE * 0.01), snappedf(yaw_at(t), 0.001), _station(c)]
	for k in 3:
		out.append((foot_at(k, t)[0] as Vector3).snapped(Vector3.ONE * 0.01))
	var b := burst(c)
	out.append(b.size())
	if not b.is_empty():
		out.append_array([snappedf(b[0], 0.001), snappedf(b[2], 0.01), b[3]])
		for k in 3:
			var sh := shot(c, k)
			out.append_array([snappedf(sh[0], 0.001), (sh[1] as Vector3).snapped(Vector3.ONE * 0.01)])
	return out


# ---------------------------------------------------------------- tick
func tick(t: float, dt: float) -> void:
	if t >= 0.0 and director.authority():
		for k in all_karts():
			if k.state == Kart.State.RESPAWN:
				_rescued[k] = t
		var c := _cycle_at(t)
		if crossed(_cycle_start(c), t) and halts(c) and not _aims.has(c):
			_pick(c)
	var active: Array = []
	for c in _aims.keys():
		var e: Array = _aims[c]
		if crossed(e[0], t):
			_fire(e[1], t)
		if t > float(e[0]) + 1.0:
			_aims.erase(c)
		elif t < float(e[0]):
			active = e
			_lock(e, t)
	_gun_tick(t)
	if visual:
		_animate(t, dt, active)


## The authority picks the nearest kart its cannon can see from the station it halts at (in
## range, in its field of view, nothing in the way, on the road of its zone, not being or just
## rescued) and aims where that kart will be when the charge is done (or short of that, where the
## gun can not see that spot: _aim_point). A kart it sees but has no clear shot at (its roof over
## a deck's edge, say) gives way to the next nearest one, so a cycle is not lost while another kart
## is in plain view.
func _pick(c: int) -> void:
	var zone: Array = p["zone"]
	var xf := body_xf(_cycle_start(c))
	var gun := xf * (_gun_m * float(p["scale"]))
	var fwd := xf.basis.z
	var half := deg_to_rad(float(p["fov"])) * 0.5
	var near: Array = []  # [distance, kart]
	var now := _cycle_start(c)
	for k in all_karts():
		if not targetable(k) or not on_road(k, float(zone[0]) - 30.0, float(zone[1])):
			continue
		if _rescued.has(k) and now - float(_rescued[k]) < RESCUED:
			continue
		var to := k.global_position - gun
		var d := to.length()
		if d >= float(p["range"]):
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 1.0 and fwd.angle_to(flat) > half:
			continue
		if bool(p["sight"]) and not _sees(gun, k):
			continue
		near.append([d, k])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var t_fire := _cycle_start(c) + tm("charge")
	for e in near:
		var k: Kart = e[1]
		var aim := _aim_point(k, gun, zone)
		if aim == Vector3.INF:
			continue
		var was := k.global_position
		send("aim", [c, t_fire, aim.x, aim.y, aim.z, director.slot_of(k), was.x, was.y, was.z])
		return


## The road point the cannon aims at for kart k: where k will be when the charge is done or, where
## the gun can not see that spot (a deck's edge or a wall between them: the kart drops into the
## viaduct's collapsed span, say), the nearest one to that on k's way there that it sees, so its
## beam never passes through the world. INF when it sees none of them.
func _aim_point(k: Kart, gun: Vector3, zone: Array) -> Vector3:
	for f in AIM_LEADS:
		var pred := k.global_position + k.velocity() * tm("charge") * float(p["lead"]) * float(f)
		var i := path.closest(pred, k.path_index)
		var at_s := path.progress(pred, i)
		if not director.in_span(at_s, float(zone[0]), float(zone[1])):
			at_s = float(zone[0]) if ahead(at_s, float(zone[0])) < ahead(float(zone[1]), at_s) else float(zone[1])
		var hw := half_width(at_s) - 1.5
		var aim := road_point(at_s, clampf(path.lateral(pred, i), -hw, hw))
		# (from the gun as it stands and as it fires, the body crouched and the head bowed)
		var to := aim + Vector3.UP * 0.5
		if not bool(p["sight"]) or (_clear(gun, to) and _clear(gun - Vector3.UP * (CROUCH + 0.5), to)):
			return aim
	return Vector3.INF


## Nothing of the static world between its gun and kart k (no world to ask: it sees).
func _sees(from: Vector3, k: Kart) -> bool:
	return _clear(from, k.global_position + k.grav_up * 0.8)


## Nothing of the static world on the line from a to b (no world to ask: clear).
func _clear(a: Vector3, b: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var rq := PhysicsRayQueryParameters3D.create(a, b, Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(rq).is_empty()


func on_event(kind: String, args: Array) -> void:
	if kind != "aim" or args.size() < 5:
		return
	var aim := Vector3(float(args[2]), float(args[3]), float(args[4]))
	var i := path.closest(aim)
	var slot := int(args[5]) if args.size() > 5 else -1
	var was := Vector3(float(args[6]), float(args[7]), float(args[8])) if args.size() > 8 else aim
	_aims[int(args[0])] = [float(args[1]), aim, path.progress(aim, i), path.lateral(aim, i), slot, was]
	director.note(self, "warn")
	play(_snd["alert"], gun_at() + Vector3.UP * 2.0, 6.0, 60.0)
	play(_snd["charge"], gun_at(), 4.0, 40.0)


## The cannon's target, while it charges, sees the lock warning (HUD, bots) if this peer drives it.
func _lock(e: Array, t: float) -> void:
	var k := director.kart_at(int(e[4])) if int(e[4]) >= 0 else null
	if k and not k.remote and k.state == Kart.State.NORMAL:
		k.hazard_lock = maxf(float(e[0]) - t, 0.01)
		k.hazard_lock_from = gun_at()


func _fire(aim: Vector3, t: float) -> void:
	director.note(self, "fire")
	_fired_at = t
	if visual:
		Effects.beam(get_parent(), gun_at(), aim, "materials/effects/blueblacklargebeam.png", Color(0.7, 0.85, 1.0), 1.2, 0.2)
		Effects.explosion(get_parent(), aim, 1.3, null, false)
		play(_snd["fire"], gun_at(), 8.0, 60.0)
	blast(aim, float(p["radius"]), str(p["effect"]), float(p["push"]), float(p["lift"]))


## Warnings, shots and hits of the machine gun's bursts (this cycle's and the last one's).
func _gun_tick(t: float) -> void:
	var c := _cycle_at(t)
	for cc in [c - 1, c]:
		var b := burst(cc)
		if b.is_empty():
			continue
		if crossed(b[0], t):
			director.note(self, "gun")
			play(_snd["gun_warn"], mg_at(), 4.0, 50.0)
		if crossed(b[1], t) or crossed(float(b[1]) + 0.7, t):
			if crossed(b[1], t):
				director.note(self, "burst")
			play(_snd["gun"], mg_at(), 6.0, 60.0)
		for k in _shots():
			var sh := shot(cc, k)
			if crossed(sh[0], t):
				_shoot(sh[1], k)


func _shoot(at: Vector3, k: int) -> void:
	for kart in local_karts():
		var d := kart.global_position - at
		if Vector2(d.x, d.z).length() < float(p["gun_hit"]) and absf(d.y) < 3.0:
			hit(kart, str(p["gun_effect"]), (kart.global_position - at).normalized() * kart.mass * 1.5)
	if not visual:
		return
	var from := mg_at()
	Effects.tracer(get_parent(), from, at, Color(0.6, 0.85, 1.0))
	if k % 3 == 0:
		Effects.muzzle(get_parent(), from, (at - from).normalized(), "materials/effects/combinemuzzle2.png", 1.4)
	if k % 2 == 0:
		Effects.dust(get_parent(), at, 0.8)
	else:
		Effects.sparks(get_parent(), at, 0.4, Color(0.6, 0.85, 1.0))
	if k % 3 == 1:
		play(_snd["ric"], at, -2.0, 12.0)


## The cannon's muzzle now (it moves with the head).
func gun_at() -> Vector3:
	if model == null:
		return body_xf(director.clock()) * (_gun_m * float(p["scale"]))
	return HazardRig.follow(model, sk, _gun_b, _gun_m)


## The machine gun's muzzle now.
func mg_at() -> Vector3:
	if model == null:
		return body_xf(director.clock()) * (_mg_m * float(p["scale"]))
	return HazardRig.follow(model, sk, _mg_b, _mg_m)


# ---------------------------------------------------------------- the look
func _animate(t: float, dt: float, active: Array) -> void:
	if model == null:
		return
	var sc := float(p["scale"])
	var xf := body_xf(t)
	_feet_now.clear()
	var floor_y := 0.0
	for k in 3:
		var f := foot_at(k, t)
		_feet_now.append(f[0])
		floor_y += float(f[1]) / 3.0
	model.global_transform = Transform3D(xf.basis.scaled(Vector3.ONE * sc), Vector3(xf.origin.x, floor_y, xf.origin.z))
	var charge := 0.0
	var focus: Vector3
	var gun_point := _gun_point(t)
	if not active.is_empty():
		charge = clampf(1.0 - (float(active[0]) - t) / tm("charge"), 0.0, 1.0)
		focus = _laser_end(active, charge)
	elif not gun_point.is_empty():
		focus = gun_point[0]
	else:
		focus = _nearest_kart(t)
	var moving := _moving(t)
	var recoil := clampf(1.0 - (t - _fired_at) / 1.2, 0.0, 1.0) if t >= _fired_at else 0.0
	_bob = 0.18 * moving * (0.5 - 0.5 * cos(TAU * 3.0 * t / _gait))
	_crouch = WALK_CROUCH * moving + CROUCH * maxf(charge, recoil)
	_crouch += _reach(_crouch + _bob)
	_pose(t, focus, dt)
	var gun := gun_at()
	_beam.visible = charge > 0.0
	_ring.visible = charge > 0.0
	_glow.visible = charge > 0.0
	if charge > 0.0:
		Effects.place_beam(_beam, gun, focus)
		_beam.set_instance_shader_parameter("col", Color(GLOW, 0.4 + 0.5 * charge))
		Effects.place_ring(_ring, active[1], path.up[path.index_at(float(active[2]))], float(p["radius"]))
		var pulse := 0.5 + 0.5 * sin(t * TAU * (2.0 + 6.0 * charge))
		_ring.set_instance_shader_parameter("col", Color(0.3, 0.9, 1.0, 0.35 + 0.55 * pulse))
		_glow.global_position = gun
		_glow.scale = Vector3.ONE * (0.5 + 2.5 * charge)
	if _light:
		_light.global_position = gun
		_light.light_energy = 6.0 * charge
	_show_gun(t, gun_point)
	_steps(t)
	_idle_t -= dt
	if _idle_t <= 0.0:
		_idle_t = 5.0 + rnd(int(t)) * 6.0
		play(_snd["idle"], xf.origin + Vector3.UP * 12.0, 0.0, 40.0)


## How much lower than `sink` metres the body must sit for every leg to reach its foot this frame
## (a long step to the side, a foothold down a slope).
func _reach(sink: float) -> float:
	var sc := float(p["scale"])
	var need := 0.0
	for leg in _legs:
		var hip: Vector3 = model.global_transform * (_m2s.affine_inverse() * (leg[2] as Vector3)) + Vector3.DOWN * sink
		var f: Vector3 = _feet_now[leg[8]]
		var reach := (float(leg[6]) + float(leg[7])) * sc * 0.97
		var hd := Vector2(f.x - hip.x, f.z - hip.z).length()
		need = maxf(need, hip.y - f.y - sqrt(maxf(reach * reach - hd * hd, 0.0)))
	return need


## Where the cannon's laser lies while it charges: on the target kart, then sliding onto the
## spot it will fire at (the ring), where it stays for the last part of the charge.
func _laser_end(e: Array, charge: float) -> Vector3:
	var on: Vector3 = e[5]
	var k := director.kart_at(int(e[4])) if int(e[4]) >= 0 else null
	if k and is_instance_valid(k) and k.state != Kart.State.RESPAWN:
		on = k.global_position + k.grav_up * 0.6
	return on.lerp(e[1], smoothstep(0.45, 0.7, charge))


## The machine gun's laser while a burst is announced or under way: [where its sight lies now,
## lap s where the line still to come starts, burst] or [].
func _gun_point(t: float) -> Array:
	var c := _cycle_at(t)
	for cc in [c - 1, c]:
		var b := burst(cc)
		if b.is_empty() or t < float(b[0]) or t > float(b[1]) + float(p["gun_time"]):
			continue
		var line := float(p["gun_sweep"]) * float(p["gun_time"])
		if t < float(b[1]):
			# the sight sweeps the line once, start to end, while the gun warns
			var w := (t - float(b[0])) / maxf(float(b[1]) - float(b[0]), 0.01)
			return [road_point(float(b[2]) - line * w, float(b[3]), 0.1), float(b[2]), b]
		var at_s := float(b[2]) - float(p["gun_sweep"]) * (t - float(b[1]))
		return [road_point(at_s, float(b[3]), 0.1), at_s, b]
	return []


## The laser line on the road (the part of the burst still to come) and the sweeping sight.
func _show_gun(t: float, gp: Array) -> void:
	var on := not gp.is_empty()
	for b in _line:
		b.visible = on
	_sight.visible = false
	if not on:
		return
	_sight.visible = t < float((gp[2] as Array)[1])
	var b: Array = gp[2]
	var end := float(b[2]) - float(p["gun_sweep"]) * float(p["gun_time"])
	var a := float(gp[1])
	var step := wrapf(a - end, -path.length * 0.5, path.length * 0.5) / LINE_SEGS
	for i in LINE_SEGS:
		Effects.place_beam(_line[i], road_point(a - step * i, float(b[3]), 0.15), road_point(a - step * (i + 1), float(b[3]), 0.15))
	if _sight.visible:
		Effects.place_beam(_sight, mg_at(), gp[0])


## A foot's thud as it lands (when it has moved).
func _steps(t: float) -> void:
	for k in 3:
		var n := floori(t / _gait + float(GAIT_OFFSET[k]) - SWING)
		var t_land := (n + SWING - float(GAIT_OFFSET[k])) * _gait
		if crossed(t_land, t):
			var a := _foothold(k, n)
			if a.distance_to(_foothold(k, n - 1)) > 0.5:
				play(_snd["step"], a, 2.0, 30.0)


func _nearest_kart(t: float) -> Vector3:
	var best := road_point(_watch_at(t), 0.0)
	var bd := 150.0
	for k in all_karts():
		var d := k.global_position.distance_to(model.global_position)
		if d < bd:
			bd = d
			best = k.global_position
	return best


## Body sway, bob and crouch with the legs solved to the feet (this frame's, or at rest); the
## head turns the cannon towards `focus`.
func _pose(t: float, focus: Vector3, dt: float) -> void:
	if sk == null:
		return
	var sc := float(p["scale"])
	var sway := Vector3(sin(t * 0.37) * 0.25, -_crouch - _bob, cos(t * 0.29) * 0.15) / sc
	var d := Transform3D(Basis(), _m2s.basis * sway)
	if _body_b >= 0:
		sk.set_bone_global_pose(_body_b, d * sk.get_bone_global_rest(_body_b))
	var to_model := model.global_transform.affine_inverse()
	for leg in _legs:
		var hip: Vector3 = d * (leg[2] as Vector3)
		var target: Vector3 = leg[5]
		if _feet_now.size() == 3:
			target = _m2s * (to_model * (_feet_now[leg[8]] as Vector3)) + (leg[9] as Vector3)
		var rest_knee: Vector3 = leg[3]
		var mid: Vector3 = ((leg[2] as Vector3) + (leg[4] as Vector3)) * 0.5
		var pole := d * (rest_knee + (rest_knee - mid) * 2.0)
		var kn := HazardRig.knee(hip, target, leg[6], leg[7], pole)
		HazardRig.point(sk, leg[0], rest_knee - (leg[2] as Vector3), kn - hip)
		HazardRig.point(sk, leg[1], (leg[4] as Vector3) - rest_knee, target - kn)
	# the head: yaw at the neck, pitch at the head, from the cannon's rest direction
	var local := model.global_transform.affine_inverse() * focus
	var pivot := _m2s.affine_inverse() * sk.get_bone_global_rest(_head_b).origin if _head_b >= 0 else _gun_m
	var rest_dir := _gun_m - pivot
	var want := local - pivot
	var want_yaw := atan2(want.x, want.z) - atan2(rest_dir.x, rest_dir.z)
	var want_pitch := atan2(want.y, Vector2(want.x, want.z).length()) - atan2(rest_dir.y, Vector2(rest_dir.x, rest_dir.z).length())
	_head.x = move_toward(_head.x, clampf(wrapf(want_yaw, -PI, PI), -1.4, 1.4), dt * 1.4)
	_head.y = move_toward(_head.y, clampf(want_pitch, -0.9, 0.5), dt * 0.8)
	var nd := HazardRig.turn(sk, _neck_b, _m2s.basis * Vector3.UP, _head.x, d)
	HazardRig.turn(sk, _head_b, _m2s.basis * Vector3.RIGHT, -_head.y, nd)


func sleep() -> void:
	if _beam:
		_beam.visible = false
		_ring.visible = false
		_glow.visible = false
		_sight.visible = false
		for b in _line:
			b.visible = false
	if _light:
		_light.light_energy = 0.0


## Bots: out of the cannon's ring when it is about to fire where they will be, and to the other
## half of the road while a burst of the machine gun is announced or under way ahead of them.
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	for e in _aims.values():
		var left := float(e[0]) - t
		if left <= 0.0 or left > 2.5:
			continue
		var r := float(p["radius"]) + 2.0
		var lat := kart_lat(k)
		if absf(fposmod(at_s + speed * left - float(e[2]) + path.length * 0.5, path.length) - path.length * 0.5) > r \
				or absf(lat - float(e[3])) > r:
			continue
		var hw := half_width(float(e[2])) - 2.5
		var away := float(e[3]) - (r + 0.5) if float(e[3]) > 0.0 else float(e[3]) + r + 0.5
		return {"lat": clampf(away, -hw, hw), "w": 0.85}
	var c := _cycle_at(t)
	for cc in [c - 1, c]:
		var b := burst(cc)
		if b.is_empty() or t < float(b[0]) or t > float(b[1]) + float(p["gun_time"]):
			continue
		var end := float(b[2]) - float(p["gun_sweep"]) * float(p["gun_time"])
		if director.in_span(at_s, end - 70.0, float(b[2]) + 4.0):
			var hw := half_width(at_s) - 2.0
			return {"lat": clampf(-signf(float(b[3])) * 4.0, -hw, hw), "w": 0.7}
	return {}


func is_active(t: float) -> bool:
	for e in _aims.values():
		if t < float(e[0]) and t > float(e[0]) - tm("charge"):
			return true
	var c := _cycle_at(t)
	for cc in [c - 1, c]:
		var b := burst(cc)
		if not b.is_empty() and t > float(b[1]) and t < float(b[1]) + float(p["gun_time"]):
			return true
	return false
