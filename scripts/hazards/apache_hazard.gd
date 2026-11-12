class_name ApacheHazard
extends Hazard
## The HECU Apache hangs over the canyon and fires pairs of rockets at the karts coming
## down it. Its flight is a function of the shared clock; the server (or the offline game)
## picks the target and broadcasts one "salvo" event with the two aim points, and the
## rockets fly and land at the same clock times on every peer.

const DOT := Color(1.0, 0.15, 0.1)

var model: Node3D
var sk: Skeleton3D
var _m2s := Transform3D.IDENTITY
var _rotor_b := -1
var _tail_b := -1
var _rotor := 0.0
var _hover: Array[Vector3] = []
var _salvos: Array = []          # [t_launch, [aim1, aim2], dots, rockets]
var _loops: Array[AudioStreamPlayer3D] = []
var _snd := {}
var _rocket_key := ""


func defaults() -> Dictionary:
	return {"zone": [s - 80.0, s + 80.0], "hover": [], "hover_time": 10.0, "every": 4.5, "rockets": 2, "flight": 1.3,
		"radius": 5.5, "min_d": 25.0, "max_d": 110.0, "effect": "tumble", "push": 0.9, "lift": 0.5,
		"rocket_model": "hl1/rpgrocket", "scale": 1.0}


func build() -> void:
	aims_all = true
	for h in p["hover"]:
		_hover.append(Vector3(h[0], h[1], h[2]))
	if _hover.is_empty():
		_hover.append(global_position)
	_snd["launch"] = sounds([["hl1src/weapons/rocketfire1.wav"], ["weapons/physcannon/superphys_launch1.wav"]])
	_snd["fly"] = sounds([["hl1src/weapons/rocket1.wav"], ["npc/env_headcrabcanister/incoming.wav"]])
	_rocket_key = pick_model([p["rocket_model"], "weapons/w_missile"])
	if not visual or not Game.models.has("hl1/apache"):
		return
	model = Game.spawn_model("hl1/apache")
	add_child(model)
	model.scale = Vector3.ONE * float(p["scale"])
	sk = HazardRig.skeleton(model)
	if sk:
		_m2s = HazardRig.model_to_skeleton(model, sk)
		_rotor_b = HazardRig.bone(sk, "Bone01")
		_tail_b = HazardRig.bone(sk, "Bone09")
	for f in [["hl1src/apache/ap_rotor2.wav", "npc/attack_helicopter/aheli_rotor_loop1.wav"],
			["npc/attack_helicopter/aheli_rotor_loop1.wav"]]:
		var a := loop(f, model, 45.0, 0.0 if _loops.is_empty() else -8.0)
		if a:
			_loops.append(a)


## Where it hovers at clock t: the hover point changes every hover_time seconds, eased over
## 3 s, with a slow bob.
func hover_at(t: float) -> Vector3:
	var ht := float(p["hover_time"])
	var n := _hover.size()
	var k := int(floor(maxf(t, 0.0) / ht))
	var u := smoothstep(0.0, 3.0, maxf(t, 0.0) - k * ht)
	var pos := _hover[posmod(k - 1, n)].lerp(_hover[k % n], u)
	return pos + Vector3.UP * sin(t * 1.3) * 0.8


func tick(t: float, dt: float) -> void:
	var pos := hover_at(t)
	global_position = pos
	if director.authority() and t > 0.0:
		var every := tm("every")
		var c := int(floor(t / every))
		if crossed(c * every, t):
			_attack(t, pos)
	for sv in _salvos.duplicate():
		_tick_salvo(sv, t)
	if model:
		var zone: Array = p["zone"]
		var look := road_point(lerpf(float(zone[0]), float(zone[1]), 0.35), 0.0) - pos
		model.rotation.y = lerp_angle(model.rotation.y, atan2(look.x, look.z), minf(1.0, dt * 1.5))
		model.rotation.x = 0.12
		_rotor = fmod(_rotor + dt * 22.0, TAU)
		HazardRig.turn(sk, _rotor_b, _m2s.basis * Vector3.UP, _rotor)
		HazardRig.turn(sk, _tail_b, _m2s.basis * Vector3.RIGHT, _rotor * 1.6)


func wake() -> void:
	for a in _loops:
		a.play()


func sleep() -> void:
	for a in _loops:
		a.stop()


## The authority picks a kart coming down the zone at a fair distance and aims a pair where it
## will be when they land. A kart that will be past the zone's end by then is let go: rockets
## never land beyond the zone (a jump's ramp may lie just past it).
func _attack(t: float, pos: Vector3) -> void:
	var zone: Array = p["zone"]
	var best: Kart = null
	var bd := INF
	var lead := Vector3.ZERO
	var i := 0
	var at_s := 0.0
	for k in all_karts():
		if not targetable(k) or not on_road(k, float(zone[0]), float(zone[1])):
			continue
		var to := pos - k.global_position
		var d := Vector2(to.x, to.z).length()
		if d < float(p["min_d"]) or d > float(p["max_d"]) or k.velocity().dot(to) <= 0.0 or d >= bd:
			continue
		var at := k.global_position + k.velocity() * (0.35 + float(p["flight"]))
		var j := path.closest(at, k.path_index)
		var s_at := path.progress(at, j)
		if not director.in_span(s_at, float(zone[0]), float(zone[1])):
			continue
		best = k
		bd = d
		lead = at
		i = j
		at_s = s_at
	if best == null:
		return
	var t_launch := t + 0.35
	var hw := half_width(at_s) - 1.0
	var lat := clampf(path.lateral(lead, i), -hw, hw)
	var a1 := road_point(at_s, lat)
	# the second one 3 m towards the middle of the road and 4 m further on
	var a2_s := at_s + minf(4.0, ahead(at_s, float(zone[1])))
	var a2 := road_point(a2_s, clampf(lat - (signf(lat) if absf(lat) > 0.5 else -1.0) * 3.0, -hw, hw))
	send("salvo", [t_launch, a1.x, a1.y, a1.z, a2.x, a2.y, a2.z])


func on_event(kind: String, args: Array) -> void:
	if kind != "salvo" or args.size() < 7:
		return
	var aims: Array[Vector3] = [Vector3(args[1], args[2], args[3]), Vector3(args[4], args[5], args[6])]
	var dots: Array = []
	if visual:
		for a in aims:
			var d := glow("materials/sprites/redglow1.png", 2.4, DOT, get_parent())
			d.global_position = a + Vector3.UP * 0.3
			dots.append(d)
	_salvos.append([float(args[0]), aims, dots, []])
	director.note(self, "warn")


## A salvo from its announcement to the impacts: red dots on the road, then the rockets
## leave the stub wings on an arc, and land `flight` seconds later.
func _tick_salvo(sv: Array, t: float) -> void:
	var t0: float = sv[0]
	var flight := float(p["flight"])
	var aims: Array[Vector3] = sv[1]
	var wing := hover_at(t0)
	if crossed(t0, t):
		director.note(self, "fire")
		play(_snd["launch"], wing, 4.0, 40.0)
		if visual:
			for j in aims.size():
				sv[3].append(_rocket())
	var u := (t - t0) / flight
	for j in (sv[3] as Array).size():
		var r: Node3D = sv[3][j]
		var from := wing + Vector3.DOWN * 1.0 + (model.global_basis.x if model else Vector3.RIGHT) * (1.8 if j == 0 else -1.8)
		var pos := from.lerp(aims[j], clampf(u, 0.0, 1.0)) + Vector3.UP * 2.0 * 4.0 * u * (1.0 - u)
		var vel := (aims[j] - from) + Vector3.UP * 8.0 * (1.0 - 2.0 * u)
		r.global_position = pos
		if vel.length() > 0.1:
			r.look_at(pos + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	for j in (sv[2] as Array).size():
		(sv[2][j] as Node3D).scale = Vector3.ONE * (0.8 + 0.4 * sin(t * 18.0))
	if crossed(t0 + flight, t):
		for a in aims:
			if visual:
				Effects.explosion(get_parent(), a, 0.8, null, false)
			blast(a, float(p["radius"]), str(p["effect"]), float(p["push"]), float(p["lift"]))
	if t > t0 + flight:
		for n in sv[2] + sv[3]:
			(n as Node).queue_free()
		_salvos.erase(sv)


## A rocket with its smoke trail (a glowing sprite when no rocket model is extracted).
func _rocket() -> Node3D:
	var r := Node3D.new()
	get_parent().add_child(r)
	if _rocket_key != "":
		var m := Game.spawn_model(_rocket_key)
		m.scale = Vector3.ONE * 1.5
		m.rotation.y = PI
		r.add_child(m)
	glow("materials/sprites/glow01.png", 1.6, Color(1.0, 0.7, 0.4), r)
	var trail := CPUParticles3D.new()
	trail.amount = 30
	trail.lifetime = 0.8
	trail.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.material = Effects.sprite("particle/smokesprites_0001", false)
	trail.mesh = q
	trail.gravity = Vector3(0, 0.5, 0)
	trail.initial_velocity_max = 0.5
	trail.color = Color(0.75, 0.72, 0.7, 0.7)
	r.add_child(trail)
	var snd := loop(_snd["fly"], r, 14.0, 0.0)
	if snd:
		snd.play()
	return r


func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	for sv in _salvos:
		var left := float(sv[0]) + float(p["flight"]) - t
		if left <= 0.0:
			continue
		for a: Vector3 in sv[1]:
			var i := path.closest(a, k.path_index)
			var r := float(p["radius"]) + 2.0
			var lat := path.lateral(a, i)
			if absf(at_s + speed * left - path.progress(a, i)) < r and absf(kart_lat(k) - lat) < r:
				var hw := half_width(at_s) - 2.5
				return {"lat": clampf(lat - (r + 0.5) if lat > 0.0 else lat + r + 0.5, -hw, hw), "w": 0.9}
	return {}


func is_active(t: float) -> bool:
	return not _salvos.is_empty() and t > 0.0


func spawns() -> Array:
	return [_rocket_key] if _rocket_key != "" else []
