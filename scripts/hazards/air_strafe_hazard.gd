class_name AirStrafeHazard
extends Hazard
## The Combine gunship over Highway 17: it circles off the coast, then dives at the road
## and strafes it head-on, one side at a time, walking its impacts towards the karts. A
## red scanning laser paints the strafe line first. The whole run (side, start, every
## impact) is a function of the shared clock and the seed, the same on every peer.

const LASER := Color(1.0, 0.1, 0.05, 0.8)
const CLIMB := 6.0
const LASER_SEGS := 8

var model: Node3D
var sk: Skeleton3D
var _m2s := Transform3D.IDENTITY
var _rotor_b := -1
var _rotor := 0.0
var _muzzle_m := Vector3(0.0, -0.98, 6.0)
var _muzzle_b := -1
var _loiter := Vector3.ZERO
var _laser: Array[MeshInstance3D] = []
var _engine: AudioStreamPlayer3D
var _fire_loop: AudioStreamPlayer3D
var _snd := {}
var _ric_t := 0.0


func defaults() -> Dictionary:
	return {"model": "gunship", "scale": 1.4, "zone": [s - 200.0, s + 200.0], "run": 170.0, "speed": 28.0, "alt": 18.0,
		"side": 3.5, "jitter": 1.2, "rate": 10.0, "lead": 18.0, "hit_r": 2.2, "effect": "spin", "period": 40.0,
		"first": 35.0, "warn": 2.5, "loiter": []}


func build() -> void:
	var l: Array = p["loiter"]
	_loiter = Vector3(l[0], l[1], l[2]) if l.size() == 3 else global_position
	_snd["see"] = sounds([["npc/combine_gunship/see_enemy.wav"], ["npc/scanner/scanner_siren1.wav"]])
	_snd["start"] = sounds([["npc/combine_gunship/attack_start2.wav"]])
	_snd["stop"] = sounds([["npc/combine_gunship/attack_stop2.wav"]])
	_snd["shot"] = sounds([["weapons/irifle/irifle_fire2.wav"]])
	_snd["ric"] = sounds(TurretHazard.RICOCHETS)
	var key := pick_model([p["model"]])
	if not visual or key == "":
		return
	model = Game.spawn_model(key)
	add_child(model)
	model.top_level = true
	model.scale = Vector3.ONE * float(p["scale"])
	sk = HazardRig.skeleton(model)
	var mz := HazardRig.attachment(key, "muzzle")
	if not mz.is_empty():
		_muzzle_m = mz[0]
	if sk:
		_m2s = HazardRig.model_to_skeleton(model, sk)
		_rotor_b = HazardRig.bone(sk, "Propeller")
		_muzzle_b = HazardRig.bone(sk, mz[1]) if not mz.is_empty() else -1
	_engine = loop(["npc/combine_gunship/gunship_engine_loop3.wav"], model, 40.0, -2.0)
	_fire_loop = loop(["npc/combine_gunship/gunship_fire_loop1.wav"], model, 40.0, 2.0)
	for i in LASER_SEGS:
		var b := Effects.beam_node(LASER, 0.22, "materials/sprites/laserbeam.png", true)
		add_child(b)
		b.visible = false
		_laser.append(b)


# ---------------------------------------------------------------- the run (pure)
## [cycle, seconds into it] at clock t, or [] before the first run.
func cycle_at(t: float) -> Array:
	var tt := t - float(p["first"])
	if tt < 0.0:
		return []
	var c := int(floor(tt / tm("period")))
	return [c, tt - c * tm("period")]


func t0() -> float:
	return tm("warn") + 3.0


func run_time() -> float:
	return float(p["run"]) / float(p["speed"])


## Which side of the road cycle c strafes (metres from the centre line).
func side_of(c: int) -> float:
	return (-1.0 if rnd(c, 1) < 0.5 else 1.0) * float(p["side"])


## Where cycle c's run starts on the lap (its far end: it flies back down the lap).
func start_of(c: int) -> float:
	var z: Array = p["zone"]
	var room := ahead(float(z[0]), float(z[1])) - float(p["run"]) - float(p["lead"])
	return float(z[1]) - float(p["lead"]) - rnd(c, 2) * maxf(room, 0.0)


## Shot k of cycle c: [clock time, impact point].
func shot(c: int, k: int) -> Array:
	var u := t0() + k / float(p["rate"])
	var at_s := start_of(c) - float(p["speed"]) * (u - t0()) - float(p["lead"])
	var lat := side_of(c) + (rnd(c, 100 + k) * 2.0 - 1.0) * float(p["jitter"])
	return [float(p["first"]) + c * tm("period") + u, road_point(at_s, lat)]


func _circle(t: float) -> Vector3:
	return _loiter + Vector3(cos(t * 0.12) * 120.0, sin(t * 0.3) * 5.0, sin(t * 0.12) * 120.0)


## The gunship at clock t: circling, diving at the road, strafing down it, climbing away.
func gunship_at(t: float) -> Vector3:
	var cy := cycle_at(t)
	if cy.is_empty():
		return _circle(t)
	var c: int = cy[0]
	var u: float = cy[1]
	var alt := float(p["alt"])
	var start := road_point(start_of(c), side_of(c), alt)
	if u < t0():
		return _circle(t - u).lerp(start, smoothstep(0.0, t0(), u))
	if u < t0() + run_time():
		return road_point(start_of(c) - float(p["speed"]) * (u - t0()), side_of(c), alt)
	var end := road_point(start_of(c) - float(p["run"]), side_of(c), alt)
	return end.lerp(_circle(t), smoothstep(t0() + run_time(), t0() + run_time() + CLIMB, u))


func snapshot(t: float) -> Array:
	var cy := cycle_at(t)
	var out: Array = [gunship_at(t).snapped(Vector3.ONE * 0.01)]
	if not cy.is_empty():
		out.append_array([cy[0], side_of(cy[0]), snappedf(start_of(cy[0]), 0.01)])
		for k in 3:
			var sh := shot(cy[0], k)
			out.append_array([snappedf(sh[0], 0.001), (sh[1] as Vector3).snapped(Vector3.ONE * 0.01)])
	return out


func tick(t: float, dt: float) -> void:
	_ric_t -= dt
	var pos := gunship_at(t)
	if model:
		model.global_position = pos
		# nose along the flight path (a function of the clock too)
		var vel := gunship_at(t + 0.25) - gunship_at(t - 0.25)
		if vel.length() > 0.05:
			model.global_basis = Basis.looking_at(-vel.normalized(), Vector3.UP).scaled(Vector3.ONE * float(p["scale"]))
		_rotor = fmod(_rotor + dt * 30.0, TAU)
		HazardRig.turn(sk, _rotor_b, _m2s.basis * Vector3.UP, _rotor)
	var cy := cycle_at(t)
	if cy.is_empty():
		_show_laser(-1, 0.0)
		return
	var c: int = cy[0]
	var u: float = cy[1]
	var c0 := float(p["first"]) + c * tm("period")
	if crossed(c0 + t0() - 2.9, t):
		director.note(self, "warn")
		play(_snd["see"], pos, 6.0, 60.0)
	if crossed(c0 + t0(), t):
		play(_snd["start"], pos, 6.0, 60.0)
		if _fire_loop:
			_fire_loop.play()
	if crossed(c0 + t0() + run_time(), t):
		play(_snd["stop"], pos, 6.0, 60.0)
		if _fire_loop:
			_fire_loop.stop()
	var shots := int(run_time() * float(p["rate"]))
	for k in shots:
		var sh := shot(c, k)
		if crossed(sh[0], t):
			_shoot(sh[1], k)
	_show_laser(c, u)


func _shoot(at: Vector3, k: int) -> void:
	if k == 0:
		director.note(self, "fire")
	for kart in local_karts():
		var d := kart.global_position - at
		if Vector2(d.x, d.z).length() < float(p["hit_r"]) and absf(d.y) < 3.0:
			hit(kart, str(p["effect"]), (kart.global_position - at).normalized() * kart.mass * 1.5)
	if not visual:
		return
	var from := HazardRig.follow(model, sk, _muzzle_b, _muzzle_m) if model else at + Vector3.UP * float(p["alt"])
	Effects.tracer(get_parent(), from, at, Color(0.6, 0.85, 1.0))
	Effects.muzzle(get_parent(), from, (at - from).normalized(), "materials/effects/combinemuzzle2.png", 1.4)
	if k % 2 == 0:
		Effects.dust(get_parent(), at, 0.8)
	else:
		Effects.sparks(get_parent(), at, 0.4, Color(0.6, 0.85, 1.0))
	if _fire_loop == null:
		play(_snd["shot"], from, 2.0, 50.0)
	if _ric_t <= 0.0:
		_ric_t = 0.15
		play(_snd["ric"], at, -2.0, 12.0)


## The red line it paints on the road before and during the run (the part still to come).
func _show_laser(c: int, u: float) -> void:
	var on := c >= 0 and u > t0() - 1.5 and u < t0() + run_time()
	for b in _laser:
		b.visible = on
	# a dedicated server (or an install without the gunship) has no beams to place
	if not on or _laser.is_empty():
		return
	var lead := float(p["lead"])
	var a := start_of(c) - lead - float(p["speed"]) * maxf(u - t0(), 0.0)
	var end := start_of(c) - lead - float(p["run"])
	var step := (a - end) / LASER_SEGS
	for i in LASER_SEGS:
		Effects.place_beam(_laser[i], road_point(a - step * i, side_of(c), 0.15), road_point(a - step * (i + 1), side_of(c), 0.15))


func wake() -> void:
	if _engine:
		_engine.play()


func sleep() -> void:
	if _engine:
		_engine.stop()
	if _fire_loop:
		_fire_loop.stop()
	_show_laser(-1, 0.0)


## Keep to the other half of the road while a run is announced or under way.
func advice(_k: Kart, _at_s: float, _speed: float) -> Dictionary:
	var cy := cycle_at(director.clock())
	if cy.is_empty() or float(cy[1]) < t0() - 2.9 or float(cy[1]) > t0() + run_time():
		return {}
	return {"lat": -signf(side_of(cy[0])) * 4.0, "w": 0.7}


func is_active(t: float) -> bool:
	var cy := cycle_at(t)
	return not cy.is_empty() and float(cy[1]) > t0() and float(cy[1]) < t0() + run_time()
