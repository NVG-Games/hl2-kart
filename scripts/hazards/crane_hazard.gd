class_name CraneHazard
extends Hazard
## A dock crane beside the road (Highway 17's crane_docks on its tower, crane_frame) with a magnet
## on its cable (cranemagnet01a). Once a cycle its cab turns so the boom swings the magnet over the
## road, the magnet comes down low and switches on (its sound and hum, a glowing ring on the road
## under it, the HUD lock of a kart heading into it), then hangs there for the active window: a kart
## this peer drives that comes within its radius is caught (Kart.magnet_grab). The caught kart
## hangs under the magnet, is lifted and carried a few metres on along the road as the boom swings,
## and is dropped back on the road when the magnet lets go; then the boom swings back to rest.
## One kart per magnet on each peer (online, two players' karts side by side under it can both be
## caught), one catch per pass (the group rule). Where the boom points, how far it
## reaches and where the magnet hangs are functions of the shared hazard clock and the seed: the
## same on every peer with no network traffic. Each kart's owner judges and moves its own karts;
## the other players see them in their streamed state.

const GLOW := Color(1.0, 0.78, 0.25)  # the switched-on magnet: its ring, glow and light
## crane_docks in model space at scale 1: the boom's hinge (x, y), the boom head where the magnet's
## cable leaves it (the cable_tip attachment), the winch on the cab its other cable starts from
## (armcable_base). The boom luffs between LUFF_MIN and LUFF_MAX radians over the level: it
## reaches from about 11 m to 27 m out from the cab's pivot.
const HINGE := Vector2(2.5908, 1.8011)
const TIP := Vector3(17.842, 30.2675, 0.2398)
const WINCH := Vector3(-1.3521, 12.0819, 0.0)
const LUFF_MIN := 0.70
const LUFF_MAX := 1.31
## The tower the cab turns on (crane_frame's height). A constant, not the model's box, so every
## peer places the boom alike whatever content it has installed.
const FRAME_H := 12.707
## cranemagnet01a: its cable eye over its origin and its bottom under it, metres at scale 1
const MAG_EYE := Vector3(-0.0656, 1.9392, 0.0014)
const MAG_BOTTOM := 1.9784
## The cycle's key times (_k): it swings in from rest, switches on and comes down (the warning),
## hangs low catching (active), carries, lets go, rises, swings back.
enum { IN, ON, LOW, CARRY, LET_GO, UP, BACK }
const FRAME_W := 6.4  # the tower's footprint (its collision box), metres at scale 1

var _sc := 1.0
var _ms := 1.0
var _arm_len := 0.0
var _arm_rest := 0.0  # the boom's own luff in the model
var _cab_at := Vector3.ZERO  # the cab's pivot on top of the tower
var _datum := 0.0  # the road's height at s: the magnet's rest height counts from it
var _rest := Vector2.ZERO  # yaw and luff of the boom parked off the road
var _k := PackedFloat32Array()
var _len := 14.0  # seconds per cycle
var _held := {}  # kart this peer drives -> the cycle whose magnet caught it

var _cab: Node3D
var _sk: Skeleton3D
var _m2s := Transform3D.IDENTITY
var _arm_b := -1
var _arm: Node3D  # the stand-in boom when crane_docks is not installed
var _magnet: Node3D
var _cables: Array[MeshInstance3D] = []  # winch to boom head, boom head to the magnet
var _ring: MeshInstance3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _snd := {}
var _idle: AudioStreamPlayer3D
var _turn: AudioStreamPlayer3D
var _winch: AudioStreamPlayer3D
var _hum: AudioStreamPlayer3D
static var _cable_mesh: CylinderMesh
static var _cable_mat: StandardMaterial3D


func defaults() -> Dictionary:
	return {"zone": [s - 14.0, s + 30.0], "cycle": 14.0, "phase": 0.0, "swing": 3.0, "warn": 1.8, "active": 1.5,
		"carry_t": 1.4, "rise": 0.8, "carry": 10.0, "jitter": 4.0, "lat_max": -1.0, "radius": 3.0, "low": 3.9,
		"high": 9.0, "lift": 3.4, "rest_turn": 1.75, "rest_luff": 1.2, "rest_h": 11.0, "scale": 1.0,
		"magnet_scale": 1.0, "effect": "magnet", "frame": true}


func build() -> void:
	_sc = float(p["scale"])
	_ms = float(p["magnet_scale"])
	_arm_len = Vector2(TIP.x, TIP.y).distance_to(HINGE)
	_arm_rest = (Vector2(TIP.x, TIP.y) - HINGE).angle()
	_cab_at = global_position + Vector3.UP * (FRAME_H * _sc if p["frame"] else 0.0)
	var road := road_point(s, 0.0)
	_datum = road.y
	var to := road - _cab_at
	_rest = Vector2(atan2(-to.z, to.x) + float(p["rest_turn"]), clampf(float(p["rest_luff"]), LUFF_MIN, LUFF_MAX))
	_timeline()
	_collider()
	_snd["switch"] = sounds([["vehicles/crane/crane_magnet_switchon.wav"], ["buttons/button1.wav"]])
	_snd["grab"] = sounds([["vehicles/crane/crane_magnet_grab.wav"], ["physics/metal/metal_barrel_impact_hard1.wav",
		"physics/metal/metal_barrel_impact_hard2.wav"]])
	_snd["release"] = sounds([["vehicles/crane/crane_magnet_release.wav"], ["physics/metal/metal_barrel_impact_soft1.wav"]])
	_snd["creak"] = sounds([["vehicles/crane/crane_creak1.wav", "vehicles/crane/crane_creak2.wav",
		"vehicles/crane/crane_creak3.wav", "vehicles/crane/crane_creak4.wav"]])
	_snd["stop"] = sounds([["vehicles/crane/crane_extend_stop.wav"]])
	if not visual:
		return
	_build_crane()
	_build_magnet()
	for i in 2:
		_cables.append(cable_node())
		add_child(_cables[i])
	_ring = Effects.ground_ring(self, global_position, Vector3.UP, float(p["radius"]), Color(GLOW, 0.0))
	_ring.visible = false
	_glow = glow("materials/sprites/glow01.png", 3.5, GLOW, _magnet)
	_glow.position = Vector3(0.0, -MAG_BOTTOM, 0.0)
	_glow.visible = false
	_light = light(GLOW, 14.0, 0.0, true)
	_idle = loop(["vehicles/crane/crane_idle_loop3.wav"], _cab, 20.0, -6.0)
	_turn = loop(["vehicles/crane/crane_turn_loop2.wav"], _cab, 24.0, -2.0)
	_winch = loop(["vehicles/crane/crane_extend_loop1.wav", "plats/crane/vertical_start.wav"], _magnet, 18.0, -3.0)
	_hum = loop(["ambient/energy/force_field_loop1.wav"], _magnet, 12.0, 0.0)
	if _hum:
		_hum.pitch_scale = 0.6
	_show(pose(0.0))


## The cycle's key times at this race's difficulty: rest first, then the swing in (the boom over
## the road at ON), the warning (ON to LOW: the magnet switched on, coming down), the active window
## (LOW to CARRY), the carry, the release (LET_GO), back up and the swing back (UP to BACK).
func _timeline() -> void:
	var sw := float(p["swing"])
	var parts := [sw, tm("warn"), tm("active"), float(p["carry_t"]), float(p["rise"]), sw]
	var total := 0.0
	for x: float in parts:
		total += x
	_len = maxf(tm("cycle"), total + 0.5)
	_k = PackedFloat32Array([_len - total])
	for x: float in parts:
		_k.append(_k[_k.size() - 1] + x)


## The tower stands in the way of a kart that leaves the road there (on a dedicated server too).
func _collider() -> void:
	if not p["frame"]:
		return
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FRAME_W, FRAME_H, FRAME_W) * _sc
	shape.shape = box
	shape.position = Vector3(0.0, FRAME_H * 0.5 * _sc, 0.0)
	body.add_child(shape)
	add_child(body)


# ---------------------------------------------------------------- the crane at clock t (pure)
func cycle_at(t: float) -> int:
	return int(floor((t - float(p["phase"])) / _len))


func cycle_start(c: int) -> float:
	return float(p["phase"]) + c * _len


## Seconds into the cycle at which key `i` (IN, ON, LOW...) comes.
func key(i: int) -> float:
	return _k[i]


## Where cycle c's magnet comes down: (lap metres, metres right of the centre line), within
## `jitter` metres of s and never nearer the road's edge than 2.5 m.
func spot(c: int) -> Vector2:
	var at := fposmod(s + (rnd(c, 1) * 2.0 - 1.0) * float(p["jitter"]), path.length)
	return Vector2(at, (rnd(c, 2) * 2.0 - 1.0) * _lat_max(at))


## Where cycle c's magnet lets go of a kart it caught: `carry` metres on along the lap from its
## spot, as far across as the spot unless that is nearer the edge than 2.5 m there.
func drop_spot(c: int) -> Vector2:
	var a := spot(c)
	var at := fposmod(a.x + float(p["carry"]), path.length)
	var m := _lat_max(at)
	return Vector2(at, clampf(a.y, -m, m))


func _lat_max(at: float) -> float:
	var room := maxf(half_width(at) - 2.5, 0.0)
	var m := float(p["lat_max"])
	return room if m < 0.0 else minf(m, room)


## The boom's yaw and luff that hang the magnet over plan point q (as near as the boom reaches).
func aim(q: Vector3) -> Vector2:
	var d := Vector2(q.x - _cab_at.x, q.z - _cab_at.z)
	var b := TIP.z * _sc
	var a := sqrt(maxf(d.length_squared() - b * b, 0.0))
	var luff := acos(clampf((a / _sc - HINGE.x) / _arm_len, cos(LUFF_MAX), cos(LUFF_MIN)))
	a = (HINGE.x + _arm_len * cos(luff)) * _sc
	return Vector2(atan2(b, a) - atan2(d.y, d.x), luff)


## The boom head (where the magnet's cable leaves it) at yaw `yaw` and luff `luff`.
func tip(yaw: float, luff: float) -> Vector3:
	var local := Vector3(HINGE.x + _arm_len * cos(luff), HINGE.y + _arm_len * sin(luff), TIP.z) * _sc
	return _cab_at + Basis(Vector3.UP, yaw) * local


## Plan metres from the cab's pivot the boom reaches at its lowest and its highest luff.
func reach() -> Vector2:
	return Vector2((HINGE.x + _arm_len * cos(LUFF_MAX)) * _sc, (HINGE.x + _arm_len * cos(LUFF_MIN)) * _sc)


## The crane at clock t: [boom yaw, luff, the magnet's bottom (world), switched on, cycle, seconds
## into it]. Parked off the road, it swings the magnet in high over the spot, lowers it, holds it
## low, lifts it as it carries it to the drop spot, lowers it there and lets go, raises it and
## swings back.
func pose(t: float) -> Array:
	var c := cycle_at(t)
	var u := t - cycle_start(c)
	var a := _road_at(spot(c))
	var b := _road_at(drop_spot(c))
	var ia := aim(a)
	var ib := aim(b)
	var low := float(p["low"]) + sin(t * 2.7) * 0.08
	var high := float(p["high"])
	var parked := _datum + float(p["rest_h"])
	var yaw := _rest.x
	var luff := _rest.y
	var y := parked
	if u >= _k[IN] and u < _k[ON]:
		var e := _ease(u, IN)
		yaw = lerp_angle(_rest.x, ia.x, e)
		luff = lerpf(_rest.y, ia.y, e)
		y = lerpf(parked, a.y + high, e)
	elif u >= _k[ON] and u < _k[LOW]:
		yaw = ia.x
		luff = ia.y
		y = lerpf(a.y + high, a.y + low, _ease(u, ON))
	elif u >= _k[LOW] and u < _k[CARRY]:
		yaw = ia.x
		luff = ia.y
		y = a.y + low
	elif u >= _k[CARRY] and u < _k[LET_GO]:
		var x := (u - _k[CARRY]) / (_k[LET_GO] - _k[CARRY])
		var e := _ease(u, CARRY)
		yaw = lerp_angle(ia.x, ib.x, e)
		luff = lerpf(ia.y, ib.y, e)
		y = lerpf(a.y, b.y, e) + low + float(p["lift"]) * sin(PI * x)
	elif u >= _k[LET_GO] and u < _k[UP]:
		yaw = ib.x
		luff = ib.y
		y = lerpf(b.y + low, b.y + high, _ease(u, LET_GO))
	elif u >= _k[UP] and u < _k[BACK]:
		var e := _ease(u, UP)
		yaw = lerp_angle(ib.x, _rest.x, e)
		luff = lerpf(ib.y, _rest.y, e)
		y = lerpf(b.y + high, parked, e)
	var q := tip(yaw, luff)
	return [yaw, luff, Vector3(q.x, y, q.z), u >= _k[ON] and u < _k[LET_GO], c, u]


## The magnet's bottom at clock t.
func magnet_at(t: float) -> Vector3:
	return pose(t)[2]


## 0..1 eased through the stretch from key i to the next at u seconds into the cycle.
func _ease(u: float, i: int) -> float:
	return smoothstep(0.0, 1.0, (u - _k[i]) / maxf(_k[i + 1] - _k[i], 0.001))


## The road's surface at (lap metres, lateral).
func _road_at(v: Vector2) -> Vector3:
	return road_point(v.x, v.y)


# ---------------------------------------------------------------- the karts it holds (Kart.magnet_grab)
## True while the magnet that caught kart k still holds it (it lets go at its cycle's LET_GO). A
## function of the clock, so a held kart is let go on time even while the crane sleeps.
func holding(k: Kart) -> bool:
	if not _held.has(k):
		return false
	return director.clock() < cycle_start(int(_held[k])) + _k[LET_GO]


## Where a kart the magnet holds is drawn to: hanging under it, its roof on the magnet's bottom.
func hold_point(k: Kart) -> Vector3:
	return magnet_at(director.clock()) - Vector3.UP * (k.spec.height + 0.05)


## One kart per magnet: true when one of this peer's karts already hangs under cycle c's magnet,
## or another player's kart does (off the ground, its roof at the magnet's bottom `m`).
func _taken(c: int, m: Vector3) -> bool:
	for k in _held:
		if is_instance_valid(k) and int(_held[k]) == c:
			return true
	for k in all_karts():
		if k.remote and not k.grounded:
			var d := k.global_position + Vector3.UP * k.spec.height - m
			if Vector2(d.x, d.z).length() < 1.5 and absf(d.y) < 0.6:
				return true
	return false


# ---------------------------------------------------------------- tick
func tick(t: float, _dt: float) -> void:
	var ps := pose(t)
	var c: int = ps[4]
	var u: float = ps[5]
	_events(cycle_start(c), t, ps[2])
	_catch(ps, c, u)
	_lock(ps, t, c, u)
	for k in _held.keys():
		if not is_instance_valid(k) or t >= cycle_start(int(_held[k])) + _k[LET_GO] + 0.5:
			_held.erase(k)
	if visual:
		_show(ps)


## Its sounds and notes as the clock passes the cycle's keys (none on the first tick, nor when the
## clock jumped: at the countdown, from the intro's clock, it does not play the keys it skipped).
func _events(base: float, t: float, m: Vector3) -> void:
	if _last_t < -1e8 or t - _last_t > 0.5:
		return
	if crossed(base + _k[ON], t):
		director.note(self, "warn")
		play(_snd["switch"], m, 4.0, 30.0)
		play(_snd["stop"], _cab_at, 0.0, 30.0)
	if crossed(base + _k[LOW], t):
		director.note(self, "fire")
	if crossed(base + _k[LET_GO], t):
		play(_snd["release"], m, 2.0, 30.0)
	for i in [IN, UP]:
		if crossed(base + _k[i], t) or crossed(base + _k[i + 1], t):
			play(_snd["creak"], _cab_at, -2.0, 35.0)


## In the active window a kart this peer drives whose body comes within the magnet's radius, under
## it, is caught: one a cycle, never one that is down, charged, being rescued or immune.
func _catch(ps: Array, c: int, u: float) -> void:
	if u < _k[LOW] or u >= _k[CARRY]:
		return
	var m: Vector3 = ps[2]
	for k in local_karts():
		if _held.has(k) or k.route >= 0 or not targetable(k):
			continue
		var mid := k.global_position + k.global_basis.y * (k.spec.height * 0.5) - m
		var roof := k.global_position.y + k.spec.height - m.y
		if Vector2(mid.x, mid.z).length() >= float(p["radius"]) or roof < -3.0 or roof > 1.0:
			continue
		if _taken(c, m) or not k.magnet_grab(self):
			continue
		_held[k] = c
		director.on_hit(k, self)
		play(_snd["grab"], m, 4.0, 30.0)
		if visual:
			Effects.sparks(get_parent(), m, 1.2, GLOW)
		return


## While the magnet is on, the karts this peer drives that head into its spot see the lock (HUD,
## bots): until it is down, then a steady warning while it catches.
func _lock(ps: Array, t: float, c: int, u: float) -> void:
	if u < _k[ON] or u >= _k[CARRY]:
		return
	var a := spot(c)
	for k in local_karts():
		if k.route >= 0 or not targetable(k) or ahead(k.lap_progress, a.x) > 70.0:
			continue
		if absf(kart_lat(k) - a.y) > float(p["radius"]) + 3.0:
			continue
		k.hazard_lock = maxf(cycle_start(c) + _k[LOW] - t, 0.05)
		k.hazard_lock_from = ps[2]


# ---------------------------------------------------------------- looks
func _build_crane() -> void:
	if p["frame"]:
		if Game.models.has("cranes/crane_frame"):
			stand("cranes/crane_frame", _sc)
		else:
			_box(self, Vector3(FRAME_W - 1.0, FRAME_H, FRAME_W - 1.0) * _sc, Vector3(0.0, FRAME_H * 0.5 * _sc, 0.0))
	_cab = Node3D.new()
	add_child(_cab)
	_cab.top_level = true
	if Game.models.has("cranes/crane_docks"):
		var m := Game.spawn_model("cranes/crane_docks")
		_cab.add_child(m)
		_sk = HazardRig.skeleton(m)
		if _sk:
			_m2s = HazardRig.model_to_skeleton(m, _sk)
			_arm_b = HazardRig.bone(_sk, "arm")
	else:
		# a stand-in for an install without the crane: the cab and a boom that luffs on its hinge
		_box(_cab, Vector3(10.0, 12.0, 4.6), Vector3(-1.2, 6.0, 0.5))
		_arm = Node3D.new()
		_cab.add_child(_arm)
		_arm.position = Vector3(HINGE.x, HINGE.y, 0.0)
		_box(_arm, Vector3(_arm_len, 1.2, 1.6), Vector3(_arm_len * 0.5, 0.0, 0.0))


func _build_magnet() -> void:
	_magnet = Node3D.new()
	add_child(_magnet)
	_magnet.top_level = true
	if Game.models.has("props_wasteland/cranemagnet01a"):
		_magnet.add_child(Game.spawn_model("props_wasteland/cranemagnet01a"))
	else:
		var mi := _box(_magnet, Vector3.ZERO, Vector3(0.0, -MAG_BOTTOM + 0.6, 0.0))
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.4
		cyl.height = 1.2
		mi.mesh = cyl


## A plain rust-coloured box `size` at `at` under `host` (the stand-ins for missing models).
func _box(host: Node3D, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.24)
	mat.roughness = 0.8
	mi.material_override = mat
	mi.position = at
	host.add_child(mi)
	return mi


## A steel cable (a thin dark cylinder) to stretch with place_cable (the crane rescue's too).
static func cable_node() -> MeshInstance3D:
	if _cable_mesh == null:
		_cable_mesh = CylinderMesh.new()
		_cable_mesh.top_radius = 1.0
		_cable_mesh.bottom_radius = 1.0
		_cable_mesh.height = 1.0
		_cable_mesh.radial_segments = 6
		_cable_mesh.rings = 1
		_cable_mat = StandardMaterial3D.new()
		_cable_mat.albedo_color = Color(0.09, 0.085, 0.08)
		_cable_mat.roughness = 0.5
		_cable_mat.metallic = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = _cable_mesh
	mi.material_override = _cable_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	return mi


## Stretches a cable_node (in the tree) from a to b, world positions, `r` metres thick.
static func place_cable(mi: MeshInstance3D, a: Vector3, b: Vector3, r := 0.06) -> void:
	var d := b - a
	if d.length() < 0.01:
		d = Vector3(0.0, 0.01, 0.0)
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x * r, d, y.cross(x) * r), (a + b) * 0.5)


## Lays the crane out as it is at the pose `ps` (pose()).
func _show(ps: Array) -> void:
	var yaw: float = ps[0]
	var luff: float = ps[1]
	var m: Vector3 = ps[2]
	var on: bool = ps[3]
	var u: float = ps[5]
	var turn := Basis(Vector3.UP, yaw)
	_cab.global_transform = Transform3D(turn.scaled(Vector3.ONE * _sc), _cab_at)
	if _sk and _arm_b >= 0:
		HazardRig.turn(_sk, _arm_b, _m2s.basis * Vector3.BACK, luff - _arm_rest)
	elif _arm:
		_arm.rotation.z = luff
	var head := tip(yaw, luff)
	var origin := m + Vector3.UP * MAG_BOTTOM * _ms
	_magnet.global_transform = Transform3D(turn.scaled(Vector3.ONE * _ms), origin)
	var eye := origin + turn * MAG_EYE * _ms
	place_cable(_cables[0], _cab_at + turn * WINCH * _sc, head, 0.07)
	place_cable(_cables[1], head, eye, 0.06)
	# the ring on the road under the spot while it warns and catches, the glow while it is on
	var warn := u >= _k[ON] and u < _k[CARRY]
	_ring.visible = warn
	if warn:
		var c: int = ps[4]
		var a := spot(c)
		var at := road_point(a.x, a.y)
		Effects.place_ring(_ring, at, path.up[path.index_at(a.x)], float(p["radius"]))
		var hot := u >= _k[LOW]
		var pulse := 0.5 + 0.5 * sin(u * (16.0 if hot else 6.0))
		var fade := clampf((u - _k[ON]) / 0.4, 0.0, 1.0)
		_ring.set_instance_shader_parameter("col", Color(GLOW, fade * (0.55 + 0.4 * pulse if hot else 0.3 + 0.3 * pulse)))
	_glow.visible = on
	if _light:
		_light.global_position = m - Vector3.UP * 0.5
		_light.light_energy = (2.0 + 1.5 * sin(u * 12.0)) if on else 0.0
	_loops(u, on)


## The engine idles while it is awake; the cab's turn loop runs while it swings, the winch while
## the magnet goes up or down, the hum while the magnet is on.
func _loops(u: float, on: bool) -> void:
	var swinging := (u >= _k[IN] and u < _k[ON]) or (u >= _k[CARRY] and u < _k[LET_GO]) or (u >= _k[UP] and u < _k[BACK])
	var winding := (u >= _k[ON] and u < _k[LOW]) or (u >= _k[LET_GO] and u < _k[UP])
	_run(_turn, swinging and awake)
	_run(_winch, winding and awake)
	_run(_hum, on and awake)
	_run(_idle, awake)


static func _run(a: AudioStreamPlayer3D, want: bool) -> void:
	if a and a.playing != want:
		if want:
			a.play()
		else:
			a.stop()


func wake() -> void:
	if visual:
		_show(pose(director.clock()))


func sleep() -> void:
	for a in [_idle, _turn, _winch, _hum]:
		_run(a, false)
	if _ring:
		_ring.visible = false
	if _glow:
		_glow.visible = false
	if _light:
		_light.light_energy = 0.0


# ---------------------------------------------------------------- the rest of the contract
## Keep clear of the magnet's spot while it is on: to the side with more room, or (no room either
## side) slow enough to come after it has gone up.
func advice(_k2: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	var c := cycle_at(t)
	var u := t - cycle_start(c)
	if u < _k[ON] - 1.0 or u >= _k[CARRY]:
		return {}
	var a := spot(c)
	var to := ahead(at_s, a.x)
	if to > 140.0:
		return {}
	var arrive := u + to / maxf(speed, 5.0)
	if arrive < _k[LOW] - 0.4 or arrive > _k[CARRY] + 0.2:
		return {}
	var room := half_width(a.x) - 1.5
	var clear := float(p["radius"]) + 2.2
	var left := a.y - clear
	var right := a.y + clear
	if left >= -room and (right > room or absf(left) <= absf(right)):
		return {"lat": left, "w": 0.85}
	if right <= room:
		return {"lat": right, "w": 0.85}
	return {"vmax": maxf(to / maxf(_k[CARRY] + 0.4 - u, 0.3), 6.0)}


## A kart the scanner puts back on the road here could come down under the magnet.
func blocks_respawn(at_s: float) -> bool:
	var j := float(p["jitter"]) + float(p["radius"]) + 2.0
	return director.in_span(at_s, s - j, s + float(p["carry"]) + j)


func is_active(t: float) -> bool:
	return pose(t)[3]


func snapshot(t: float) -> Array:
	var ps := pose(t)
	var c: int = ps[4]
	return [c, snappedf(ps[5], 0.001), snappedf(ps[0], 0.0001), snappedf(ps[1], 0.0001),
		(ps[2] as Vector3).snapped(Vector3.ONE * 0.01), ps[3], spot(c).snapped(Vector2.ONE * 0.01)]
