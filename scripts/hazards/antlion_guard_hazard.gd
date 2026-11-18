class_name AntlionGuardHazard
extends Hazard
## The antlion guard, Nova Prospekt's boss (stage D5). It lives beside the road in a zone of the lap
## (p["zone"], and the branches it names in p["branches"]): between charges it stands at its home on
## its own side of the road (the entry's "pos", p["side"]) or walks back there along that verge. When
## karts come into the zone (or the p["lookout"] metres before it: its first charge comes up through the
## floor after a long warning, so it picks a fast kart while it is still that far off) the authority (the
## server, or the offline game) picks one it can reach: the leader of the karts coming at it, or else the
## nearest kart just past it, slow enough to be run down from behind. For that kart it works out where the kart will be (its metres along its road run
## on at its speed, its offset from the centre line kept) when a charge from where the guard stands
## gets there, and sends ONE "charge" event: the serial, the kart's slot, the clock time, how the guard
## appears (standing; up through the floor, its floor_break, the first time; or out of a side gate),
## the kind of run (from the side, or from behind), its speed, and four points: where it starts, where
## it meets the kart's line, where it pulls up and where it steps aside to. From the event its motion is
## a pure function of the shared clock, the same on every peer: first the warning (a roar, the ground
## shaking under the targeted kart's camera, a ring on the road where it rams, the target's HUD lock),
## then the charge, straight at the meeting point, getting up to speed and then flat out; a LOCAL kart
## its body reaches is shoved (Kart.hazard_hit "shove": thrown hard away from it and across the road,
## well past a tumble's limits, so where the road has an open edge the shove can carry the kart over
## it). It pulls up short of any drop, trots off the road to its own side, roars there and walks home.
## A kart in RESPAWN, charged (star), just hit or already hit by this group on this pass is never
## shoved (Hazard.hit, Kart.hazard_hit). The cool-down between charges is p["cool"] (director.scale:
## EASY longer, HARD shorter) and its charge speed is divided by the "charge" scale (EASY slower). It is
## on the road only for its charge and the second or two after it; while it stands or walks it keeps
## p["keep"] metres past the road's edge (its verge), or on a deck wider than the racing line needs
## (Nova Prospekt's collapsed yard) a negative keep holds it that far inside the edge, by its wall and
## off the racing line. While it stands still it is solid (a box on the props' layer), unless a kart is
## where it stands. The bots hear where it runs (advice): they take the lane its run leaves clear, or
## brake to let it pass. Nothing visual on a dedicated server; with old content (no model, no
## animations, no sounds) a box stands in for it and nothing breaks.

enum Ph { HIDDEN, IDLE, WARN, CHARGE, STOP, ASIDE, ROAR, HOME }
## its body in its charge pose, metres at scale 1 along its heading from its origin (the hips): the
## tail behind, the head and claws in front; half its width and its height
const BODY_BACK := 1.9
const BODY_FRONT := 2.7
const BODY_HALF := 1.05
const BODY_H := 3.0
const KART_R := 1.2          # metres round a kart's centre its body has to come within to ram it
const ACC_D := 5.43          # metres its charge_startfast carries it getting up to speed (scale 1)
const FLOOR_LEN := 113.0 / 30.0   # its floor_break (114 frames at 30 fps): it comes up through the floor
const FLOOR_T := 2.4         # ... sped up to this many seconds, before its normal warning
const ANTIC_LEN := 39.0 / 30.0    # charge_anticipate: it crouches, head down, just before it charges
const ROAR_T := 2.6          # seconds it roars where it stepped aside to
const ASIDE_V := 9.0         # m/s it trots off the road at after a charge ...
const ASIDE_T := 1.2         # ... or faster, so that it takes no longer than this (back across the road to its start)
const WALK := 3.05 / (20.0 / 30.0)   # m/s of its walk (a_walkN: 3.05 m in 21 frames at 30 fps), scale 1
const MIN_SPEED := 4.0       # m/s a kart must be doing along its road to be charged at
const CATCH := 5.0           # m/s faster than a kart it runs down from behind
const STEP := 1.0            # metres between the ground points of a run
const FOOT_EVERY := 2.6      # metres (scale 1) between the thuds of its feet as it charges
const POSE_NEAR := 70.0      # metres from the camera within which it is posed every frame
const GLOW := Color(1.0, 0.55, 0.2)
const PATCH := 0.35          # seconds between dust puffs under it as it charges
const REACT := 0.3           # seconds into its charge before the bots see where it runs (advice)
const STOP_V := 22.0         # m/s of a charge that pulls up its whole p["stop"] metres (a slower one sooner)

## serial -> the run it makes (_plan): the same on every peer for the same event
var _runs := {}
var _order: Array[int] = []        # their serials in order of their clock times (the newest last)
var _sending := -1                 # the authority: the serial of the charge it is sending (on_event takes only that)
var _serial := 0                   # the authority's next serial
var _ready_at := -INF              # the authority: clock from which it may charge again
var _retry := {}                   # the authority: kart -> clock before which it is not tried again
var _hits0 := {}                   # the authority: a client's kart -> its net_hits when last charged at
var stats := {"charges": 0, "side": 0, "behind": 0, "blocked": 0}
var _home := Vector3.ZERO          # where it stands between charges (the entry's "pos")
var _home_dir := Vector3.FORWARD   # which way it faces there (the entry's "yaw": the road)
var _home_s := 0.0                 # lap metres beside its home
var _home_lat := 0.0               # its home's offset from the centre line there
var _side := 1.0                   # the side of the road its home and its verge are on
var _gate := Vector3.INF           # where it comes out of a side gate the first time (p["gate"])
var _world := false                # the static world has collision here (the determinism test builds none)
var _adv := {}                     # kart -> [clock, advice] (bots: worked out at most every 0.1 s)
var _solid: StaticBody3D           # its body while it stands still (every peer: it stops local karts)
var _box_xf := Transform3D()        # where _box_lap was worked out for (bots' advice)
var _box_lap := Vector4()           # its standing box on the lap (_box_on_lap)

var _body: Node3D                  # what shows it: the model, or a box standing in for it
var _model: Node3D
var _sk: Skeleton3D
var anims: AnimSet
var _bind_yaw := 0.0               # model without animations: the yaw that turns its bind pose to face +X
var _vis_yaw := 0.0
var _vis_pos := Vector3.INF
var _ring: MeshInstance3D
var _ring_sn := -1
var _dust_t := 0.0
var _last_d := 0.0
var _last_sn := -1
var _idle: AudioStreamPlayer3D
var _idle_t := 4.0
var _snd := {}


## (p["lead"]: it meets a kart 6 to 18 m on from abeam of where it stands, steeply across the road, so
## it is off the road again soon after; a meeting further on is a long shallow run and a long walk back)
func defaults() -> Dictionary:
	return {"zone": [s - 60.0, s + 60.0], "side": 1, "branches": [], "emerge": "floor", "gate": [], "warn": 1.6,
		"cool": 7.0, "speed": [16.0, 30.0], "match": 1.0, "lead": [6.0, 18.0], "reach": 45.0, "chase": 30.0,
		"stop": 6.0, "aside": 4.0, "keep": 2.0, "tail": 20.0, "push": 18.0, "lift": 7.0, "along": 0.5, "lookout": 0.0,
		"effect": "shove", "scale": 1.2, "model": "antlion_guard"}


func build() -> void:
	aims_all = true
	_home = global_position
	_home_dir = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	_side = signf(float(p["side"])) if float(p["side"]) != 0.0 else 1.0
	var hi := path.closest(_home, path.index_at(s))
	_home_s = path.progress(_home, hi)
	_home_lat = path.lateral(_home, hi)
	if float(p["keep"]) < 0.0 and absf(_home_lat) < half_width(_home_s):
		# on a deck: its home moved out by its wall where the racing line comes its way (the same on
		# every peer: the lap's own line)
		var lat := _stand_lat(_home_s, absf(_home_lat))
		if absf(lat - _home_lat) > 0.05:
			var q := road_point(_home_s, lat)
			_home = Vector3(q.x, _home.y + (q.y - road_point(_home_s, _home_lat).y), q.z)
			_home_lat = lat
		# and it stands side-on there, looking down the road at the karts coming, so its body keeps to
		# its own lane instead of reaching its head out toward the racing line
		_home_dir = _oncoming(path.closest(_home, hi))
	var g: Array = p["gate"]
	if g.size() >= 3:
		_gate = Vector3(float(g[0]), float(g[1]), float(g[2]))
	_snd["roar"] = sounds([["npc/antlion_guard/angry1.wav", "npc/antlion_guard/angry2.wav", "npc/antlion_guard/angry3.wav"],
		["npc/antlion/rumble1.wav"], ["npc/strider/striderx_alert4.wav"]])
	_snd["charge"] = sounds([["npc/antlion_guard/growl_high.wav"], ["npc/antlion_guard/angry2.wav"]])
	_snd["foot"] = sounds([["npc/antlion_guard/foot_heavy1.wav", "npc/antlion_guard/foot_heavy2.wav"],
		["npc/strider/strider_step1.wav", "npc/strider/strider_step2.wav"]])
	_snd["step"] = sounds([["npc/antlion_guard/foot_light1.wav", "npc/antlion_guard/foot_light2.wav"],
		["npc/antlion/foot1.wav", "npc/antlion/foot2.wav"]])
	_snd["shove"] = sounds([["npc/antlion_guard/shove1.wav"], ["physics/metal/metal_barrel_impact_hard1.wav",
		"physics/metal/metal_barrel_impact_hard2.wav"]])
	_snd["miss"] = sounds([["npc/antlion_guard/frustrated_growl1.wav", "npc/antlion_guard/frustrated_growl2.wav",
		"npc/antlion_guard/frustrated_growl3.wav"], ["npc/antlion_guard/angry3.wav"]])
	_snd["floor"] = sounds([["physics/concrete/boulder_impact_hard1.wav", "physics/concrete/boulder_impact_hard2.wav",
		"physics/concrete/boulder_impact_hard3.wav"], ["physics/surfaces/sand_impact_bullet1.wav"]])
	_snd["rumble"] = sounds([["ambient/atmosphere/terrain_rumble1.wav"], ["npc/antlion/rumble1.wav"]])
	_snd["idle"] = sounds([["npc/antlion_guard/growl_idle.wav", "npc/antlion_guard/breathe_loop.wav"]])
	var sc0 := float(p["scale"])
	_solid = StaticBody3D.new()
	_solid.name = "GuardSolid"
	_solid.collision_layer = 0
	_solid.collision_mask = 0
	_solid.set_meta("surface", "wall")
	add_child(_solid)
	_solid.top_level = true
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(BODY_BACK + BODY_FRONT, BODY_H, BODY_HALF * 2.0) * sc0
	cs.shape = bx
	cs.position = Vector3((BODY_FRONT - BODY_BACK) * 0.5, BODY_H * 0.5, 0.0) * sc0
	_solid.add_child(cs)
	if not visual:
		return
	_body = Node3D.new()
	_body.name = "Guard"
	add_child(_body)
	_body.top_level = true
	var key := pick_model([str(p["model"]), "antlion_guard"])
	var sc := float(p["scale"])
	if key != "":
		_model = Game.spawn_model(key)
		_body.add_child(_model)
		_sk = AnimSet.skeleton(_model)
		anims = AnimSet.of(key)
		if anims == null and _sk != null:
			# its bind pose faces another way than its animations (+X): turn the head onto +X
			var hb := _sk.find_bone("Antlion_Guard.head")
			var bb := _sk.find_bone("Antlion_Guard.body")
			if hb >= 0 and bb >= 0:
				var f := _sk.get_bone_global_rest(hb).origin - _sk.get_bone_global_rest(bb).origin
				if Vector2(f.x, f.z).length() > 0.2:
					_bind_yaw = atan2(f.z, f.x)
		_model.rotation.y = _bind_yaw
	else:
		# no model in this content: a box of its size in its place
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(BODY_BACK + BODY_FRONT, BODY_H, BODY_HALF * 2.0)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.33, 0.22)
		mi.material_override = m
		mi.position = Vector3((BODY_FRONT - BODY_BACK) * 0.5, BODY_H * 0.5, 0.0)
		_body.add_child(mi)
	_body.scale = Vector3.ONE * sc
	_idle = loop(["npc/antlion_guard/growl_idle.wav", "npc/antlion_guard/breathe_loop.wav"], _body, 10.0, -10.0)
	_show(director.clock(), 0.0)


# ---------------------------------------------------------------- the run (pure)
## Seconds of the warning of a run that appears so (1: up through the floor first).
func _warn_t(emerge: int) -> float:
	return tm("warn") + (FLOOR_T if emerge == 1 else 0.0)


func _acc() -> float:
	return ACC_D * float(p["scale"])


## Seconds a charge of d metres takes at top speed v: steady acceleration over the first _acc()
## metres (its charge_startfast), then flat out.
func run_time(d: float, v: float) -> float:
	var a := _acc()
	if d <= a:
		return 2.0 * sqrt(a * d) / v
	return (a + d) / v


## Metres a charge at top speed v has covered tau seconds after it set off.
func _run_dist(tau: float, v: float) -> float:
	var a := _acc()
	var ta := 2.0 * a / v
	if tau < ta:
		return v * v * tau * tau / (4.0 * a)
	return a + v * (tau - ta)


## Points every STEP metres from a to b on the static world's ground (each looked for near the one
## before, so a deck over it or a floor under it is not taken), b's own height at the end: {"pts",
## "cum", "len", "solid"}; "solid" is false when some point had no ground under it or a step in it is
## higher than a kerb's climb, true with no world to ask.
func _line(a: Vector3, b: Vector3) -> Dictionary:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var d := flat.length()
	var n := maxi(int(ceil(d / STEP)), 1)
	var pts := PackedVector3Array([a])
	var cum := PackedFloat32Array([0.0])
	var y := a.y
	var solid := true
	for k in range(1, n + 1):
		var u := float(k) / n
		var q := a.lerp(b, u)
		var hy := q.y
		if k < n:
			var g := _ground(Vector3(q.x, y, q.z), 1.6, 3.0)
			if g.is_finite():
				hy = g.y
			elif _world:
				solid = false
				hy = lerpf(y, b.y, 1.0 / (n - k + 1))
		if absf(hy - y) > 1.1 * STEP + 0.3:
			solid = false
		y = hy
		pts.append(Vector3(q.x, hy, q.z))
		cum.append(d * u)
	return {"pts": pts, "cum": cum, "len": d, "solid": solid}


## The static world's floor under q, looked for from `up` metres over q down to `down` under it
## (Vector3.INF over nothing, or with no world to ask).
func _ground(q: Vector3, up: float, down: float) -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var rq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * up, q - Vector3.UP * down, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	return Vector3.INF if hit.is_empty() else hit["position"]


static func _along(ln: Dictionary, d: float) -> Vector3:
	var pts: PackedVector3Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	if pts.size() < 2:
		return pts[0]
	var k := clampi(cum.bsearch(d, true) - 1, 0, pts.size() - 2)
	return pts[k].lerp(pts[k + 1], clampf((d - cum[k]) / maxf(cum[k + 1] - cum[k], 0.001), 0.0, 1.0))


static func _tangent(ln: Dictionary, d: float, fallback: Vector3) -> Vector3:
	var pts: PackedVector3Array = ln["pts"]
	if pts.size() < 2:
		return fallback
	var cum: PackedFloat32Array = ln["cum"]
	var k := clampi(cum.bsearch(d, true) - 1, 0, pts.size() - 2)
	var t := pts[k + 1] - pts[k]
	t.y = 0.0
	return t.normalized() if t.length() > 0.001 else fallback


static func _flat_dir(a: Vector3, b: Vector3, fallback: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized() if d.length() > 0.05 else fallback


## The walk home from r along its verge: straight there when home is near (in lap metres), else
## beside the road every 4 m, its offset from the centre line easing from r's to the home's, never
## nearer the road's middle than p["keep"] metres past its edge.
func _home_line(r: Vector3) -> Dictionary:
	var i := path.closest(r, path.index_at(_home_s))
	var u_r := path.progress(r, i)
	var lat_r := path.lateral(r, i)
	var d := wrapf(_home_s - u_r, -path.length * 0.5, path.length * 0.5)
	if absf(d) < 8.0 or signf(lat_r) != _side:
		return _line(r, _home)
	var n := maxi(int(absf(d) / 4.0), 2)
	var pts := PackedVector3Array([r])
	var cum := PackedFloat32Array([0.0])
	var y := r.y
	var total := 0.0
	for k in range(1, n + 1):
		var q := _home
		if k < n:
			var f := float(k) / n
			var u := u_r + d * f
			var lat := lerpf(lat_r, _home_lat, f)
			lat = _stand_lat(u, maxf(absf(lat), half_width(u) + float(p["keep"])))
			q = road_point(u, lat)
			var g := _ground(Vector3(q.x, y, q.z), 1.6, 3.0)
			q.y = g.y if g.is_finite() else lerpf(y, _home.y, 1.0 / (n - k + 1))
		total += Vector2(q.x - pts[k - 1].x, q.z - pts[k - 1].z).length()
		pts.append(q)
		cum.append(total)
		y = q.y
	return {"pts": pts, "cum": cum, "len": total, "solid": true}


## The run of a "charge" event, worked out the same on every peer: its lines and its timetable.
func _plan(args: Array) -> Dictionary:
	var emerge := int(args[3])
	var v := float(args[5])
	var S := Vector3(float(args[6]), float(args[7]), float(args[8]))
	var M := Vector3(float(args[9]), float(args[10]), float(args[11]))
	var E := Vector3(float(args[12]), float(args[13]), float(args[14]))
	var R := Vector3(float(args[15]), float(args[16]), float(args[17]))
	var t0 := float(args[2])
	var run := {"sn": int(args[0]), "slot": int(args[1]), "t0": t0, "emerge": emerge, "kind": int(args[4]), "V": v,
		"S": S, "M": M, "E": E, "R": R, "hit": false, "seen": false, "fired": false}
	run["dir"] = _flat_dir(S, M, _home_dir)
	run["charge"] = _line(S, M)
	run["stop"] = _line(M, E)
	run["aside"] = _line(E, R)
	run["home"] = _home_line(R)
	var d := float(run["charge"]["len"])
	var dme := float(run["stop"]["len"])
	var vm := v if d >= _acc() else v * sqrt(d / _acc())
	run["vm"] = vm
	run["t_go"] = t0 + _warn_t(emerge)
	run["t_meet"] = float(run["t_go"]) + run_time(d, v)
	run["t_stop"] = float(run["t_meet"]) + (2.0 * dme / maxf(vm, 1.0) if dme > 0.05 else 0.3)
	run["v_aside"] = maxf(ASIDE_V, float(run["aside"]["len"]) / ASIDE_T)
	run["t_aside"] = float(run["t_stop"]) + float(run["aside"]["len"]) / float(run["v_aside"])
	run["t_rest"] = float(run["t_aside"]) + ROAR_T
	run["t_home"] = float(run["t_rest"]) + float(run["home"]["len"]) / (WALK * float(p["scale"]))
	# facing the road where it roars (on a deck side-on, looking at the karts coming: _home_dir)
	var ri := path.closest(R, path.index_at(_home_s))
	run["face"] = _oncoming(ri) if _on_deck() else _flat_dir(R, path.center[ri], -_side_dir(ri))
	# the lap metres its run covers (the scanner keeps a rescued kart out of them)
	var lo := INF
	var hi := -INF
	for q: Vector3 in [S, M, E]:
		var at := fposmod(path.progress(q, path.closest(q, ri)) - _home_s, path.length)
		at = wrapf(at, -path.length * 0.5, path.length * 0.5)
		lo = minf(lo, at)
		hi = maxf(hi, at)
	run["s_lo"] = _home_s + lo
	run["s_hi"] = _home_s + hi
	return run


## Its offset from the centre line at lap metres u when it would stand `want` metres out on its side:
## on a deck (inside the road's edge) further out where the racing line comes its way, its body and a
## metre clear of the line while the deck has room (half a metre short of the edge at most).
func _stand_lat(u: float, want: float) -> float:
	var hw := half_width(u)
	if want >= hw:
		return _side * want
	var i := path.index_at(u)
	var line := path.lateral(path.line_at(u), i) * _side
	var clear := line + BODY_HALF * float(p["scale"]) + 1.0
	return _side * maxf(want, minf(clear, hw - 0.5))


## Its home lies inside the road's edge (a deck): p["keep"] negative.
func _on_deck() -> bool:
	return float(p["keep"]) < 0.0


## Back down the lap at sample i, flat: the way it looks standing side-on to the karts coming.
func _oncoming(i: int) -> Vector3:
	var f := -path.fwd[i]
	return Vector3(f.x, 0.0, f.z).normalized()


func _side_dir(i: int) -> Vector3:
	var r := path.right[i] * _side
	return Vector3(r.x, 0.0, r.z).normalized()


## The newest run whose event came at or before clock t ({} before the first); _order is in order of
## the runs' clock times, so a later run always takes over from an earlier one whatever its serial.
func _run_at(t: float) -> Dictionary:
	for j in range(_order.size() - 1, -1, -1):
		var run: Dictionary = _runs[_order[j]]
		if float(run["t0"]) <= t:
			return run
	return {}


## Where the guard is at clock t: [position (on the ground under its hips), heading (plan, unit),
## phase (Ph), seconds into that phase, its run ({} for none), metres into that phase's line].
func state_at(t: float) -> Array:
	var run := _run_at(t)
	if run.is_empty():
		return [_home, _home_dir, Ph.HIDDEN if _hides() else Ph.IDLE, t, run, 0.0]
	var t0 := float(run["t0"])
	var dir: Vector3 = run["dir"]
	if t < float(run["t_go"]):
		return [run["S"], dir, Ph.WARN, t - t0, run, 0.0]
	if t < float(run["t_meet"]):
		var tau := t - float(run["t_go"])
		var d := minf(_run_dist(tau, float(run["V"])), float(run["charge"]["len"]))
		return [_along(run["charge"], d), _tangent(run["charge"], d, dir), Ph.CHARGE, tau, run, d]
	if t < float(run["t_stop"]):
		var tau := t - float(run["t_meet"])
		var len_s := float(run["stop"]["len"])
		var vm := float(run["vm"])
		var d := 0.0
		if len_s > 0.05:
			d = minf(vm * tau - vm * vm / (4.0 * len_s) * tau * tau, len_s)
		return [_along(run["stop"], d), _tangent(run["stop"], d, dir), Ph.STOP, tau, run, d]
	if t < float(run["t_aside"]):
		var tau := t - float(run["t_stop"])
		var d := minf(float(run["v_aside"]) * tau, float(run["aside"]["len"]))
		return [_along(run["aside"], d), _tangent(run["aside"], d, dir), Ph.ASIDE, tau, run, d]
	if t < float(run["t_rest"]):
		return [run["R"], run["face"], Ph.ROAR, t - float(run["t_aside"]), run, 0.0]
	if t < float(run["t_home"]):
		var tau := t - float(run["t_rest"])
		var d := minf(WALK * float(p["scale"]) * tau, float(run["home"]["len"]))
		return [_along(run["home"], d), _tangent(run["home"], d, run["face"]), Ph.HOME, tau, run, d]
	return [_home, _home_dir, Ph.IDLE, t - float(run["t_home"]), run, 0.0]


## Hidden until its first charge: it comes up through the floor, or out of its gate.
func _hides() -> bool:
	return str(p["emerge"]) == "floor" or (str(p["emerge"]) == "gate" and _gate.is_finite())


## True while it is charging or pulling up (its body can ram a kart).
static func ramming(ph: int) -> bool:
	return ph == Ph.CHARGE or ph == Ph.STOP


## True when it may set off on a new charge at clock t (the authority's cool-down is over and it is
## not on a run).
func can_charge(t: float) -> bool:
	var ph := int(state_at(t)[2])
	return t >= _ready_at and not (ph == Ph.WARN or ph == Ph.CHARGE or ph == Ph.STOP or ph == Ph.ASIDE)


# ---------------------------------------------------------------- the hunt (authority)
## The road a kart drives in the zone (or up to `ahead` metres before it), or null outside it (another
## branch, outside its lap metres).
func _road_of(k: Kart, ahead := 0.0) -> TrackPath:
	var zone: Array = p["zone"]
	if not director.in_span(k.lap_progress, float(zone[0]) - ahead, float(zone[1])):
		return null
	if k.route < 0:
		return path
	var br: TrackBranch = path.branches[k.route]
	return br if (p["branches"] as Array).has(br.id) else null


## Metres along road g from u_a forward to u_b (negative behind; the lap wraps, a branch does not).
func _gap(g: TrackPath, u_a: float, u_b: float) -> float:
	if g == path:
		return wrapf(u_b - u_a, -path.length * 0.5, path.length * 0.5)
	return u_b - u_a


func tick(t: float, dt: float) -> void:
	if t >= 0.0 and director.authority() and can_charge(t):
		_hunt(t)
	var st := state_at(t)
	var run: Dictionary = st[4]
	var ph := int(st[2])
	if not run.is_empty():
		if crossed(float(run["t_go"]), t) and not run["fired"]:
			run["fired"] = true
			director.note(self, "fire")
		if t < float(run["t_meet"]):
			_lock(run, st, t)
		if ramming(ph) and (ph == Ph.STOP or float(st[3]) > 0.1):
			_ram(run, st)
	_stand(st)
	if visual:
		_show(t, dt)


## The authority looks for a kart to charge at from where the guard stands now and, finding one,
## sends the run to every peer.
func _hunt(t: float) -> void:
	var st := state_at(t)
	var S: Vector3 = st[0]
	var emerge := 0
	if int(st[2]) == Ph.HIDDEN:
		if str(p["emerge"]) == "floor":
			emerge = 1
		elif _gate.is_finite():
			emerge = 2
			S = _gate
	var best := {}
	var u_s := {}  # road -> metres along it abeam of S
	for k in all_karts():
		var g := _road_of(k, float(p["lookout"]))
		# a client's kart: the server does not see its immunity, only the hits its owner reports. One
		# since it was last charged at and it is left alone until it is out of the zone, as its own
		# director would refuse the shove anyway
		if k.remote and _hits0.has(k):
			if g == null:
				_hits0.erase(k)
			elif k.net_hits > int(_hits0[k]):
				continue
		if g == null or not targetable(k) or float(_retry.get(k, -INF)) > t:
			continue
		if not u_s.has(g):
			u_s[g] = g.progress(S, path.closest(S, path.index_at(_home_s)) if g == path else g.closest(S))
		var c := _intercept(k, g, S, float(u_s[g]), emerge)
		if c.is_empty():
			continue
		if best.is_empty() or _better(c, best):
			best = c
	if best.is_empty():
		return
	var fit := _fit(best, S)
	if fit.is_empty():
		# no clear run (a wall, a pillar, a hole in the way): this kart is tried again in a moment
		stats["blocked"] = int(stats["blocked"]) + 1
		_retry[best["k"]] = t + 0.3
		return
	var M: Vector3 = best["M"]
	var E: Vector3 = fit["E"]
	var R: Vector3 = fit["R"]
	var k: Kart = best["k"]
	var how := "side" if int(best["kind"]) == 0 else "behind"
	stats["charges"] = int(stats["charges"]) + 1
	stats[how] = int(stats[how]) + 1
	if k.remote:
		_hits0[k] = k.net_hits
	var sn := _serial
	_serial += 1
	_sending = sn
	send("charge", [sn, director.slot_of(k), t, emerge, int(best["kind"]), float(best["V"]), S.x, S.y, S.z, M.x, M.y, M.z,
		E.x, E.y, E.z, R.x, R.y, R.z])
	_sending = -1


## The charge that meets kart k on road g from S (u_s metres along g abeam of it): {"k", "kind" (0
## from the side, 1 from behind), "V", "M", "gap", "prog", "g"}, or {} when none fits. The kart's
## metres run on at its speed and its offset from the centre line drifts with its sideways speed (by
## half). The meeting is the first moment past the warning at which the kart will be p["lead"] metres
## on from abeam of the guard (from the side no further than lead[1]), in its reach and in its zone,
## and a run straight there (run_time) takes just the time left at a speed the guard can run: no
## faster than the kart allows (its speed by p["match"], plus CATCH from behind, within p["speed"],
## over the "charge" scale: EASY slower) and no slower than three quarters of that. So a kart still too far off for that is tried again as it comes on, and the long warning of
## its first run (up through the floor) or a kart faster than it can run still finds a meeting ahead
## of it, met by a run that sets off sooner. Looked for every 0.05 s over the next 5 s past the warning.
func _intercept(k: Kart, g: TrackPath, S: Vector3, u_s: float, emerge: int) -> Dictionary:
	var i := k.route_index
	var v := k.velocity()
	var along := v.dot(g.fwd[i])
	if along < MIN_SPEED:
		return {}
	var u_k := k.route_pos()
	var gap := _gap(g, u_k, u_s)
	var kind := 0
	if gap < 0.0:
		if -gap > float(p["chase"]):
			return {}
		kind = 1
	elif gap > 200.0:
		return {}
	var sp: Array = p["speed"]
	var v_hi := clampf(along * float(p["match"]) + (CATCH if kind == 1 else 0.0), float(sp[0]), float(sp[1])) \
		/ director.scale("charge")
	if kind == 1 and along > v_hi - 2.0:
		return {}
	var v_lo := v_hi * 0.75
	var w := _warn_t(emerge)
	var lat_k := g.lateral(k.global_position, i)
	var lat_v := v.dot(g.right[i])
	var lead: Array = p["lead"]
	var zone: Array = p["zone"]
	var T := w + 0.05
	while T <= w + 5.0:
		var u_m := u_k + along * T
		if g != path:
			u_m = clampf(u_m, 0.0, g.length)
		var f := _gap(g, u_s, u_m)
		if kind == 0 and f > float(lead[1]):
			# (the kart only gets further on)
			return {}
		if f >= float(lead[0]):
			var j := g.index_at(u_m)
			var room := maxf(g.width[j] * 0.5 - 1.2, 0.0)
			var M := g.center_at(u_m) + g.right[j] * clampf(lat_k + lat_v * T * 0.5, -room, room)
			var d := Vector2(M.x - S.x, M.z - S.z).length()
			var vn := _run_speed(d, T - w)
			# where it meets the kart is in the zone (its tail past the zone's end too)
			var ms := u_m if g == path else (g as TrackBranch).main_s(u_m)
			if d >= 4.0 and d <= float(p["reach"]) and vn <= v_hi and vn >= v_lo \
					and director.in_span(ms, float(zone[0]), float(zone[1]) + float(p["tail"])):
				return {"k": k, "kind": kind, "V": vn, "M": M, "gap": gap, "prog": k.total_progress, "g": g}
		T += 0.05
	return {}


## The top speed at which a charge of d metres takes tau seconds (run_time turned round).
func _run_speed(d: float, tau: float) -> float:
	var a := _acc()
	return (2.0 * sqrt(a * d) if d <= a else a + d) / maxf(tau, 0.01)


## The one of two charges to make: from the side before from behind; of two from the side the one at
## the leader, of two from behind the one at the nearer kart.
static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["kind"]) != int(b["kind"]):
		return int(a["kind"]) < int(b["kind"])
	if int(a["kind"]) == 0:
		return float(a["prog"]) > float(b["prog"])
	return absf(float(a["gap"])) < absf(float(b["gap"]))


## Where a charge from S to the meeting point pulls up and steps aside to, if its way is clear:
## {"E", "R"}, or {} when its run passes through the world or over a hole. It pulls up p["stop"]
## metres on (less for a slower run: STOP_V), sooner where the ground ends (its front stops short of
## the drop) or a wall stands; it steps off the road to its own side abeam of there, or back to where
## it set off from when that is not open ground (or it met a kart on a branch).
func _fit(c: Dictionary, S: Vector3) -> Dictionary:
	_world = _has_world()
	var M: Vector3 = c["M"]
	var sc := float(p["scale"])
	var run := _line(S, M)
	if not bool(run["solid"]) or not _clear(run):
		return {}
	var dir := _flat_dir(S, M, _home_dir)
	# (a slower run pulls up in a shorter way, in about the time a fast one takes: it is off the road
	# as soon after the meeting)
	var stop := float(p["stop"]) * clampf(float(c["V"]) / STOP_V, 0.5, 1.0)
	var E := M + dir * stop
	if _world:
		var y := M.y
		var bad := INF
		var x := 1.0
		while x <= stop + BODY_FRONT * sc + 0.01:
			var q := M + dir * x
			var g := _ground(Vector3(q.x, y, q.z), 1.2, 2.0)
			if not g.is_finite() or absf(g.y - y) > 1.0 or not _ray_clear(M + dir * (x - 1.0) + Vector3.UP * (y - M.y), Vector3(q.x, y, q.z)):
				bad = x - 1.0
				break
			y = g.y
			x += 1.0
		var go := clampf(bad - BODY_FRONT * sc, 0.0, stop) if bad < INF else stop
		E = M + dir * go
		var ge := _ground(E, 1.2, 2.0)
		if ge.is_finite():
			E.y = ge.y
	var R := S
	var g: TrackPath = c["g"]
	if g == path:
		var i := path.closest(E, path.index_at(_home_s))
		var at := path.progress(E, i)
		var q := road_point(at, _stand_lat(at, half_width(at) + float(p["aside"])))
		var gq := _ground(q, 2.0, 3.0)
		if gq.is_finite() or not _world:
			if gq.is_finite():
				q.y = gq.y
			var aside := _line(E, q)
			if (bool(aside["solid"]) and _clear(aside)) and absf(q.y - path.center[i].y) < 2.5:
				R = q
	return {"E": E, "R": R}


## Nothing of the static world in the way of its body along a line, at its knees and its shoulders.
func _clear(ln: Dictionary) -> bool:
	if not _world:
		return true
	var pts: PackedVector3Array = ln["pts"]
	var sc := float(p["scale"])
	for k in range(0, pts.size() - 1, 2):
		var b := pts[mini(k + 2, pts.size() - 1)]
		for h: float in [1.0, 2.2 * sc]:
			if not _ray_clear(pts[k] + Vector3.UP * (h - 1.0), b + Vector3.UP * (h - 1.0)):
				return false
	return true


## Nothing of the static world between a and b, a metre over each.
func _ray_clear(a: Vector3, b: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var rq := PhysicsRayQueryParameters3D.create(a + Vector3.UP, b + Vector3.UP, Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(rq).is_empty()


## Whether the static world has collision at all here (the determinism test builds none).
func _has_world() -> bool:
	if not is_inside_tree():
		return false
	return _ground(path.center[path.index_at(_home_s)], 3.0, 6.0).is_finite()


func on_event(kind: String, args: Array) -> void:
	if kind != "charge" or args.size() < 18:
		return
	var sn := int(args[0])
	if _runs.has(sn):
		return
	# a charge only the authority sends (_hunt). An online server takes only the one it is sending: a
	# client's "hz" event reaches it too, and a forged charge must not stand in for its own runs. A
	# client takes one from about now only (the server sends it at its clock time), so a forged one
	# from far off can not hang over the runs to come (a later run takes over anyway: _run_at)
	if Net.active and Net.is_server and sn != _sending:
		return
	if Net.active and not Net.is_server and absf(float(args[2]) - director.clock()) > 6.0:
		return
	# its points near home and its run no longer than its reach, so a forged one cannot send the guard
	# across the map or make every peer trace miles
	var S := Vector3(float(args[6]), float(args[7]), float(args[8]))
	var M := Vector3(float(args[9]), float(args[10]), float(args[11]))
	var E := Vector3(float(args[12]), float(args[13]), float(args[14]))
	var R := Vector3(float(args[15]), float(args[16]), float(args[17]))
	var sc := float(p["scale"])
	var far := float(p["reach"]) + 5.0
	if S.distance_to(_home) > 400.0 or S.distance_to(M) > far or M.distance_to(E) > float(p["stop"]) + 3.0 \
			or E.distance_to(R) > 60.0 or float(args[5]) < 1.0 or float(args[5]) > 80.0 * sc:
		return
	_world = _has_world()
	var run := _plan(args)
	_runs[sn] = run
	_order.append(sn)
	_order.sort_custom(func(a: int, b: int) -> bool:
		var ta := float(_runs[a]["t0"])
		var tb := float(_runs[b]["t0"])
		return ta < tb or (ta == tb and a < b))
	while _order.size() > 3:
		_drop(_order[0])
	director.note(self, "warn")
	if int(args[3]) == 1:
		play(_snd["rumble"], S, 6.0, 30.0)
		play(_snd["floor"], S, 6.0, 26.0)
	else:
		play(_snd["roar"], S + Vector3.UP * 2.0, 6.0, 40.0)
	if director.authority():
		_ready_at = float(run["t_aside"]) + tm("cool")


func _drop(sn: int) -> void:
	_runs.erase(sn)
	_order.erase(sn)
	if _ring_sn == sn and _ring:
		_ring.queue_free()
		_ring = null
		_ring_sn = -1


## The target of a run sees the HUD lock while the guard comes for it, if this peer drives it.
func _lock(run: Dictionary, st: Array, t: float) -> void:
	var k := director.kart_at(int(run["slot"]))
	if k and not k.remote and k.state == Kart.State.NORMAL:
		k.hazard_lock = maxf(float(run["t_meet"]) - t, 0.01)
		k.hazard_lock_from = (st[0] as Vector3) + Vector3.UP * 2.0 * float(p["scale"])


## Solid while it stands still (at home, roaring, waiting to charge), so a kart can not drive through
## it; not while it moves (its ram is the shove), nor while a kart is where it stands (a body appearing
## round a kart would throw it).
func _stand(st: Array) -> void:
	if _solid == null:
		return
	var ph := int(st[2])
	var still := ph == Ph.IDLE or ph == Ph.ROAR or (ph == Ph.WARN and not (int((st[4] as Dictionary).get("emerge", 0)) == 1
		and float(st[3]) < FLOOR_T))
	if not still:
		_solid.collision_layer = 0
		return
	var dir: Vector3 = st[1]
	var at: Vector3 = st[0]
	var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) - PI * 0.5), at)
	# (it may turn where it stands, as it does to set off from home: the box turns with it)
	if _solid.collision_layer != 0 and _solid.global_transform.is_equal_approx(xf):
		return
	var sc := float(p["scale"])
	for k in all_karts():
		var rel := xf.affine_inverse() * k.global_position
		if rel.x > -BODY_BACK * sc - 2.0 and rel.x < BODY_FRONT * sc + 2.0 and absf(rel.z) < BODY_HALF * sc + 2.0 \
				and rel.y > -2.0 and rel.y < BODY_H * sc + 1.0:
			_solid.collision_layer = 0
			return
	_solid.global_transform = xf
	_solid.collision_layer = Game.LAYER_PROP


## The karts this peer drives that its body reaches now are shoved: hard across the road, away from
## its own side (where the road's far side is open, over that edge), and on the way it runs, with a hop.
## Any kart its body reaches, this peer's or another player's, makes it pull up as from a hit and roar
## (run "seen"): every peer sees the same karts there, so all show the same, while "hit" (a kart this
## peer drives was shoved) stays this peer's own.
func _ram(run: Dictionary, st: Array) -> void:
	var g: Vector3 = st[0]
	var dir: Vector3 = st[1]
	var right := dir.cross(Vector3.UP)
	var sc := float(p["scale"])
	for k in all_karts():
		var rel := k.global_position - g
		var a := rel.dot(dir)
		var b := rel.dot(right)
		if a < -BODY_BACK * sc - KART_R or a > BODY_FRONT * sc + KART_R or absf(b) > BODY_HALF * sc + KART_R:
			continue
		if rel.y < -1.5 or rel.y > BODY_H * sc:
			continue
		run["seen"] = true
		if k.remote:
			continue
		# (whichever side of its run the kart is on: one met just off its line on its own side would
		# else be thrown back into the wall behind it instead of over the edge)
		var away := -_side_dir(path.closest(k.global_position, path.index_at(_home_s)))
		var push := (dir * float(p["along"]) + away).normalized()
		if hit(k, str(p["effect"]), (push * float(p["push"]) + k.grav_up * float(p["lift"])) * k.mass):
			run["hit"] = true
			if visual:
				play(_snd["shove"], k.global_position, 6.0, 20.0)
				Effects.dust(get_parent(), k.global_position, 1.4)
				_shake_for(k, 0.8)


# ---------------------------------------------------------------- the look
func _show(t: float, dt: float) -> void:
	if _body == null:
		return
	var st := state_at(t)
	var pos: Vector3 = st[0]
	var dir: Vector3 = st[1]
	var ph := int(st[2])
	var since := float(st[3])
	var run: Dictionary = st[4]
	var sc := float(p["scale"])
	_body.visible = ph != Ph.HIDDEN
	if ph == Ph.HIDDEN:
		return
	var yaw := anims.yaw_to(dir) if anims else atan2(dir.x, dir.z) - PI * 0.5
	# turning: quickly as it sets off or steps aside, at once after a jump of the clock or a new run
	if not _vis_pos.is_finite() or _vis_pos.distance_to(pos) > 6.0 or dt <= 0.0:
		_vis_yaw = yaw
	else:
		_vis_yaw = lerp_angle(_vis_yaw, yaw, minf(1.0, dt * (14.0 if ramming(ph) else 6.0)))
	_vis_pos = pos
	var lift := 0.0
	var sn := int(run.get("sn", -1))
	if sn != _last_sn:
		_last_sn = sn
		_last_d = 0.0
	var emerging := ph == Ph.WARN and int(run["emerge"]) == 1 and since < FLOOR_T
	if emerging and (anims == null or _sk == null):
		# no animations: it rises out of the floor
		lift = -BODY_H * sc * (1.0 - since / FLOOR_T)
	_body.global_transform = Transform3D(Basis(Vector3.UP, _vis_yaw).scaled(Vector3.ONE * sc), pos + Vector3.UP * lift)
	if anims == null and _model != null and ramming(ph):
		# a plain gallop's bob
		_body.global_position.y += absf(sin(float(st[5]) * 1.2)) * 0.18 * sc
	_pose(st, t)
	_marks(run, st, t, dt)
	_sounds(run, st, t, dt)


## Its own animations for the phase it is in (none in this content: it keeps its bind pose).
func _pose(st: Array, t: float) -> void:
	if anims == null or _sk == null:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	var near := cam != null and cam.global_position.distance_to(st[0]) < POSE_NEAR
	if not AnimSet.due(_model, t, 0.0 if near else 15.0):
		return
	var ph := int(st[2])
	var since := float(st[3])
	var run: Dictionary = st[4]
	var sc := float(p["scale"])
	match ph:
		Ph.HIDDEN, Ph.IDLE:
			anims.pose(_sk, "idle", t, 1.0, AnimSet.LOOP)
		Ph.WARN:
			var w := float(run["t_go"]) - float(run["t0"])
			var floor_t := FLOOR_T if int(run["emerge"]) == 1 else 0.0
			if since < floor_t:
				anims.pose(_sk, "floor_break", since * FLOOR_LEN / FLOOR_T, 1.0, AnimSet.CLAMP)
				return
			var rest := w - floor_t
			var x := since - floor_t
			if rest <= ANTIC_LEN:
				anims.pose(_sk, "anticipate", x * ANTIC_LEN / maxf(rest, 0.1), 1.0, AnimSet.CLAMP)
			elif x < rest - ANTIC_LEN:
				anims.pose(_sk, "bark", x, 1.0, AnimSet.CLAMP)
			else:
				anims.pose(_sk, "anticipate", x - (rest - ANTIC_LEN), 1.0, AnimSet.CLAMP)
		Ph.CHARGE:
			var d := float(st[5])
			var a := _acc()
			if d < a:
				anims.pose(_sk, "charge_start", d / a * anims.length("charge_start"), 1.0, AnimSet.CLAMP)
			else:
				anims.pose(_sk, "charge", (d - a) / maxf(anims.speed("charge") * sc, 0.1), 1.0, AnimSet.LOOP)
		Ph.STOP:
			var dur := maxf(float(run["t_stop"]) - float(run["t_meet"]), 0.3)
			var an := "hit" if run["seen"] else "stop"
			anims.pose(_sk, an, since / dur * anims.length(an) * 0.6, 1.0, AnimSet.CLAMP)
		Ph.ASIDE:
			anims.pose(_sk, "walk", float(st[5]) / maxf(anims.speed("walk") * sc, 0.1), 1.0, AnimSet.LOOP)
		Ph.ROAR:
			var an := "roar" if run["seen"] else "bark"
			anims.pose(_sk, an, since * anims.length(an) / ROAR_T, 1.0, AnimSet.CLAMP)
		Ph.HOME:
			anims.pose(_sk, "walk", float(st[5]) / maxf(anims.speed("walk") * sc, 0.1), 1.0, AnimSet.LOOP)


## The warning and the charge on show: a ring on the road where it rams (pulsing faster as it
## comes), dust as it comes up through the floor and under its feet as it charges, the cameras of the
## karts it comes for shaking.
func _marks(run: Dictionary, st: Array, t: float, dt: float) -> void:
	var ph := int(st[2])
	var sc := float(p["scale"])
	if not run.is_empty() and t < float(run["t_meet"]) and (ph == Ph.WARN or ph == Ph.CHARGE):
		var M: Vector3 = run["M"]
		if _ring == null or _ring_sn != int(run["sn"]):
			if _ring:
				_ring.queue_free()
			_ring = Effects.ground_ring(self, M, Vector3.UP, BODY_HALF * sc + KART_R + 0.4, Color(GLOW, 0.0))
			_ring_sn = int(run["sn"])
		var u := clampf((t - float(run["t0"])) / maxf(float(run["t_meet"]) - float(run["t0"]), 0.01), 0.0, 1.0)
		_ring.set_instance_shader_parameter("col", Color(GLOW, (0.3 + 0.6 * u) * (0.6 + 0.4 * sin(t * (5.0 + 14.0 * u)))))
		_ring.visible = true
	elif _ring:
		_ring.queue_free()
		_ring = null
		_ring_sn = -1
	if run.is_empty():
		return
	var at: Vector3 = st[0]
	if crossed(float(run["t0"]), t) and int(run["emerge"]) == 1:
		Effects.dust(get_parent(), at + Vector3.UP * 0.3, 2.4)
	if int(run["emerge"]) == 1 and crossed(float(run["t0"]) + FLOOR_T * 0.5, t):
		# it breaks through
		Effects.dust(get_parent(), at + Vector3.UP * 0.5, 3.0)
		play(_snd["floor"], at, 8.0, 30.0)
	if ramming(ph):
		_dust_t -= dt
		if _dust_t <= 0.0:
			_dust_t = PATCH
			Effects.dust(get_parent(), at + Vector3.UP * 0.2, 0.9)
	# the cameras of the karts this peer drives: the target's through the warning, every one near it
	# through the charge, the more the nearer
	if ph == Ph.WARN:
		var k := director.kart_at(int(run["slot"]))
		if k and not k.remote:
			_shake_for(k, 0.35 if int(run["emerge"]) == 1 and float(st[3]) < FLOOR_T else 0.15)
	elif ramming(ph):
		for k in local_karts():
			var d := k.global_position.distance_to(at)
			if d < 30.0:
				_shake_for(k, 0.3 * (1.0 - d / 30.0))


func _shake_for(k: Kart, amount: float) -> void:
	for cam in get_tree().get_nodes_in_group("race_camera"):
		if cam is RaceCamera and (cam as RaceCamera).target == k:
			(cam as RaceCamera).shake(amount)


func _sounds(run: Dictionary, st: Array, t: float, dt: float) -> void:
	var ph := int(st[2])
	var at: Vector3 = st[0]
	var sc := float(p["scale"])
	if _idle:
		var calm := ph == Ph.IDLE or ph == Ph.HOME or ph == Ph.ROAR
		if calm and not _idle.playing:
			_idle.play()
		elif not calm and _idle.playing:
			_idle.stop()
	if not run.is_empty():
		if crossed(float(run["t_go"]), t):
			play(_snd["charge"], at + Vector3.UP * 2.0, 6.0, 40.0)
		if crossed(float(run["t_stop"]), t) and not run["seen"]:
			play(_snd["miss"], at + Vector3.UP * 2.0, 4.0, 30.0)
		if crossed(float(run["t_aside"]), t) and run["seen"]:
			play(_snd["roar"], at + Vector3.UP * 2.0, 6.0, 40.0)
		# its feet: heavy as it charges, light as it trots and walks
		var d := float(st[5])
		if ramming(ph):
			var every := FOOT_EVERY * sc
			if floor(d / every) != floor(_last_d / every) and d > _last_d:
				play(_snd["foot"], at, 4.0, 26.0)
		elif ph == Ph.ASIDE or ph == Ph.HOME:
			var every := 1.6 * sc
			if floor(d / every) != floor(_last_d / every) and d > _last_d:
				play(_snd["step"], at, -4.0, 14.0)
		_last_d = d
	if ph == Ph.IDLE:
		_idle_t -= dt
		if _idle_t <= 0.0:
			_idle_t = 6.0 + rnd(int(t), 3) * 6.0
			play(_snd["miss"], at + Vector3.UP * 2.0, -6.0, 20.0)


func wake() -> void:
	_vis_pos = Vector3.INF


## Nobody near: the warning ring goes and its breath stops (made again from the clock when it wakes).
func sleep() -> void:
	if _ring:
		_ring.queue_free()
		_ring = null
		_ring_sn = -1
	if _idle:
		_idle.stop()


# ---------------------------------------------------------------- the others' questions
## Bots: once it charges (and REACT seconds on: they do not read its warning, a player does), the
## lane its body will not reach as they come by (the one with the most room in a quick look ahead at
## their speed), and a brake when no lane is clear. Before it sets off and from where it rams on (as it
## pulls up, trots aside, roars and walks home), a lane round where it will stand (_box_advice).
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	if k == null:
		return {}
	var t := director.clock()
	var run := _run_at(t)
	var out := {}
	if not run.is_empty() and t >= float(run["t_go"]) + REACT and t < float(run["t_stop"]):
		out = _charge_advice(k, at_s, speed, run, t)
	if out.is_empty() and (run.is_empty() or t >= float(run["t_meet"]) or t < float(run["t_go"])):
		out = _box_advice(k, at_s, speed)
	return out


func _charge_advice(k: Kart, at_s: float, speed: float, run: Dictionary, t: float) -> Dictionary:
	if not director.in_span(at_s, float(run["s_lo"]) - 90.0, float(run["s_hi"]) + 6.0):
		return {}
	var e: Array = _adv.get(k, [])
	if not e.is_empty() and absf(t - float(e[0])) < 0.1:
		return e[1]
	var g := k.geo()
	var u := k.route_pos()
	var hw := g.width[g.index_at(u)] * 0.5 - 1.5
	var now := kart_lat(k) if k.route < 0 else g.lateral(k.global_position, k.route_index)
	var lanes: Array[float] = [now, -hw, -hw * 0.5, 0.0, hw * 0.5, hw]
	var best := -INF
	var best_lat := now
	var here := INF
	for lat in lanes:
		var c := _room(g, u, lat, maxf(speed, 1.0), t, float(run["t_stop"]))
		if lat == now:
			here = c
		if c > best + 0.25:
			best = c
			best_lat = lat
	var out := {}
	if here < 2.0:
		out = {"lat": best_lat, "w": 0.85}
		if best < 1.0:
			out["vmax"] = speed * 0.55
	_adv[k] = [t, out]
	return out


## Bots: while it stands (at home, roaring where it stepped aside to, about to set off) its body is solid
## (_stand) and may reach into the road: a lane past it on the side away from its own, taken however the
## bot rolls for hazards ("solid"), from a few seconds' drive before it until past it; {} when the kart's
## lane already clears it or it is not in the way.
func _box_advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	if _solid == null or k.route >= 0:
		return {}
	var bx := _box_on_lap(_next_stand(director.clock()))
	var half := path.length * 0.5
	if wrapf(bx.x - at_s, -half, half) > maxf(speed * 2.5, 25.0) or wrapf(at_s - bx.y, -half, half) > 1.0:
		return {}
	var m := KART_R + 1.0
	var lat := bx.z - m - 0.4 if _side > 0.0 else bx.w + m + 0.4
	var now := kart_lat(k)
	if (now < lat - 0.5) if _side > 0.0 else (now > lat + 0.5):
		return {}
	var hw := half_width(at_s) - 1.5
	var out := {"lat": clampf(lat, -hw, hw), "w": 0.9, "solid": true}
	if absf(lat) > hw:
		out["vmax"] = maxf(speed * 0.55, 8.0)
	return out


## Where it stands still next at clock t, as its solid box would stand (_stand): at home (also while it
## walks home along its verge or the deck), where it stepped aside to (from its stop on, while it trots
## there and roars), where it starts a run (while it warns).
func _next_stand(t: float) -> Transform3D:
	var run := _run_at(t)
	var at := _home
	var dir := _home_dir
	if not run.is_empty() and t < float(run["t_rest"]):
		if t < float(run["t_go"]):
			at = run["S"]
			dir = run["dir"]
		elif t >= float(run["t_meet"]):
			at = run["R"]
			dir = run["face"]
	return Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) - PI * 0.5), at)


## Its standing box (xf: _next_stand) on the lap: Vector4(lap metres from, to, offset from the centre
## line from, to) over its four corners (worked out again only when it stands somewhere else).
func _box_on_lap(xf: Transform3D) -> Vector4:
	if xf.is_equal_approx(_box_xf):
		return _box_lap
	_box_xf = xf
	var sc := float(p["scale"])
	var i0 := path.closest(xf.origin, path.index_at(_home_s))
	var half := path.length * 0.5
	var v := Vector4(INF, -INF, INF, -INF)
	for a in [-BODY_BACK * sc, BODY_FRONT * sc]:
		for b in [-BODY_HALF * sc, BODY_HALF * sc]:
			var q: Vector3 = xf * Vector3(a, 0.0, b)
			var at := _home_s + wrapf(path.progress(q, i0) - _home_s, -half, half)
			var lat := path.lateral(q, i0)
			v = Vector4(minf(v.x, at), maxf(v.y, at), minf(v.z, lat), maxf(v.w, lat))
	_box_lap = v
	return v


## The least room (metres between a kart's reach and its body) there is for a kart driving lane `lat`
## of road g from u at v m/s, from clock t until `until`.
func _room(g: TrackPath, u: float, lat: float, v: float, t: float, until: float) -> float:
	var sc := float(p["scale"])
	var least := INF
	var x := 0.0
	while x <= minf(until - t, 3.5):
		var st := state_at(t + x)
		if ramming(int(st[2])):
			var uu := u + v * x
			if g != path:
				uu = clampf(uu, 0.0, g.length)
			var q := g.center_at(uu) + g.right[g.index_at(uu)] * lat
			var rel := q - (st[0] as Vector3)
			var dir: Vector3 = st[1]
			var a := rel.dot(dir)
			var b := absf(rel.dot(dir.cross(Vector3.UP)))
			var out_a := maxf(a - BODY_FRONT * sc, -BODY_BACK * sc - a)
			least = minf(least, maxf(out_a, b - BODY_HALF * sc) - KART_R)
		x += 0.1
	return least


## A kart the scanner would put back where a run is on.
func blocks_respawn(at_s: float) -> bool:
	var t := director.clock()
	var run := _run_at(t)
	if run.is_empty() or t >= float(run["t_aside"]) + 0.5:
		return false
	return director.in_span(at_s, float(run["s_lo"]) - 12.0, float(run["s_hi"]) + 20.0)


func is_active(t: float) -> bool:
	return ramming(int(state_at(t)[2]))


func snapshot(t: float) -> Array:
	var st := state_at(t)
	var run: Dictionary = st[4]
	var dir: Vector3 = st[1]
	return [int(run.get("sn", -1)), (st[0] as Vector3).snapped(Vector3.ONE * 0.01), snappedf(atan2(dir.x, dir.z), 0.001), st[2],
		snappedf(float(run.get("t_meet", 0.0)), 0.001)]


## A made-up charge for the determinism test (no world, no karts): from home at the road 18 m on,
## stepping aside to its own side.
func test_event(t0: float, sn := 900) -> Array:
	var i := path.index_at(_home_s)
	var M := road_point(_home_s + 18.0, 0.0)
	var dir := _flat_dir(_home, M, _home_dir)
	var E := M + dir * 4.0
	var at := path.progress(E, path.closest(E, i))
	var R := road_point(at, _side * (half_width(at) + float(p["aside"])))
	return [sn, 0, t0, 1 if _hides() else 0, 0, 20.0, _home.x, _home.y, _home.z, M.x, M.y, M.z, E.x, E.y, E.z, R.x, R.y, R.z]


## True while it stands at home, walks back there or has not come out yet (tests).
func idle() -> bool:
	var ph := int(state_at(director.clock())[2])
	return ph == Ph.IDLE or ph == Ph.HOME or ph == Ph.HIDDEN


## Where it stands for its next charge and the lap metres of its home (tests).
func home() -> Vector3:
	return _home


func home_s() -> float:
	return _home_s
