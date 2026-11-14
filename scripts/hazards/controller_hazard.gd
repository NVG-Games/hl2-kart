class_name ControllerHazard
extends Hazard
## An alien controller of Half-Life floating over the void beside the road. It flies round its own
## loop (p["path"]: an oval of points tools/hazards.py laid over the void) at a steady pace, a
## function of the shared hazard clock, turned to the road. Once a cycle it winds up (its attack1
## animation, an orange glow growing between its hands) and throws a slow orange energy ball at a
## kart. The server (or the offline game) picks the kart and the road point it will reach when
## the ball lands, and sends one "aim" event as the wind-up starts; every peer then shows the same
## wind-up, flight and burst at the same clock times, and each kart's owner judges its own karts.
## An orange ring marks the spot from the aim on, the target's HUD shows the lock, and the burst
## spins out a kart within `radius` of it: one that changes its line in time is missed.

const ORANGE := Color(1.0, 0.55, 0.15)
## seconds into attack1 where its hands let go of the ball (event 3, the small shot, frame 29 at 15 fps)
const RELEASE := 29.0 / 15.0
const RESCUED := 2.5        # seconds after a rescue a kart is not taken as a target
const POSE_NEAR := 70.0     # metres from the camera within which it is posed every frame
const WINDOW := 0.6         # the share of a cycle, from its start, in which it may wind up

var model: Node3D
var sk: Skeleton3D
var anims: AnimSet
var _route := PackedVector3Array()
var _cum := PackedFloat32Array()   # metres along the loop at each point (and back at the first)
var _len := 0.0
var _off := 0.0                    # metres along its loop at clock 0
var _phase := 0.0
## cycle -> [t_throw, aim point, lap s, lateral, target's slot, {visual nodes}, ball start]
var _aims := {}
var _hands: Array[int] = []
var _glow: MeshInstance3D
var _light: OmniLight3D
var _yaw := 0.0
var _idle_t := 6.0
var _snd := {}
var _rescued := {}
var _thrown := -1000000            # the last cycle the authority aimed in (once a cycle)
var _hint := -1                    # the lap sample it flies beside (the road it looks at)


func defaults() -> Dictionary:
	return {"zone": [s - 60.0, s + 60.0], "path": [], "model": "hl1/controller", "scale": 1.6, "speed": 4.5,
		"cycle": 10.0, "phase": -1.0, "warn": 1.4, "flight": 1.5, "radius": 3.6, "lead": 1.0, "range": 65.0,
		"effect": "spin", "push": 0.25, "lift": 0.15, "bob": 0.6}


func build() -> void:
	aims_all = true
	for q in p["path"]:
		_route.append(Vector3(q[0], q[1], q[2]))
	if _route.is_empty():
		_route.append(global_position)
	_cum.append(0.0)
	for j in _route.size():
		_len += _route[j].distance_to(_route[(j + 1) % _route.size()])
		_cum.append(_len)
	_off = rnd(1) * _len
	_phase = float(p["phase"]) if float(p["phase"]) >= 0.0 else rnd(2) * float(p["cycle"])
	_snd["alert"] = sounds([["hl1src/controller/con_alert1.wav", "hl1src/controller/con_alert2.wav",
		"hl1src/controller/con_alert3.wav"], ["hl1src/aslave/slv_alert1.wav"]])
	_snd["attack"] = sounds([["hl1src/controller/con_attack1.wav", "hl1src/controller/con_attack2.wav",
		"hl1src/controller/con_attack3.wav"], ["hl1src/debris/zap1.wav"]])
	_snd["idle"] = sounds([["hl1src/controller/con_idle1.wav", "hl1src/controller/con_idle2.wav",
		"hl1src/controller/con_idle3.wav", "hl1src/controller/con_idle4.wav"]])
	_snd["throw"] = sounds([["hl1src/weapons/electro4.wav", "hl1src/weapons/electro5.wav"], ["weapons/gauss/fire1.wav"]])
	_snd["burst"] = sounds([["hl1src/x/x_ballattack1.wav"], ["hl1src/debris/zap4.wav"], ["ambient/energy/zap5.wav"]])
	_snd["ball"] = sounds([["hl1src/x/x_teleattack1.wav"], ["weapons/physcannon/energy_sing_loop4.wav"]])
	global_position = pos_at(0.0)
	if not visual:
		return
	_glow = glow("materials/sprites/orangeflare1.png", 1.0, ORANGE)
	_glow.visible = false
	_light = light(ORANGE, 10.0, 0.0)
	var key := str(p["model"])
	if not Game.models.has(key):
		return
	model = Game.spawn_model(key)
	add_child(model)
	model.scale = Vector3.ONE * float(p["scale"])
	sk = AnimSet.skeleton(model)
	anims = AnimSet.of(key)
	if sk:
		for side in ["L", "R"]:
			var bn := "ValveBiped.Bip01_%s_Finger1" % side
			var bi := sk.find_bone(bn)
			_hands.append(bi if bi >= 0 else sk.find_bone(bn.replace(".", "_")))


# ---------------------------------------------------------------- the clock
## Where it is at clock t: round its loop at p["speed"], bobbing gently.
func pos_at(t: float) -> Vector3:
	var n := _route.size()
	if n < 2 or _len <= 0.0:
		return _route[0]
	var d := fposmod(t * float(p["speed"]) + _off, _len)
	var j := clampi(_cum.bsearch(d, true) - 1, 0, n - 1)
	var seg := maxf(_cum[j + 1] - _cum[j], 0.001)
	var at := _route[j].lerp(_route[(j + 1) % n], (d - _cum[j]) / seg)
	return at + Vector3.UP * sin(t * 1.3 + float(seed_v % 97)) * float(p["bob"])


func _cycle_at(t: float) -> int:
	return int(floor((t - _phase) / tm("cycle")))


## When cycle c starts. In the first WINDOW of it, the authority aims (the wind-up starts) as soon
## as a kart comes in reach, once; the ball leaves tm("warn") after the aim.
func _cycle_start(c: int) -> float:
	return _phase + c * tm("cycle")


## Where its ball leaves at clock t: in front of its chest (the same on every peer, whatever the
## model; the ball drawn leaves from between its hands).
func throw_point(t: float) -> Vector3:
	return pos_at(t) + Vector3.UP * 0.8 * float(p["scale"])


func snapshot(t: float) -> Array:
	return [pos_at(t).snapped(Vector3.ONE * 0.01), _cycle_at(t)]


# ---------------------------------------------------------------- tick
func tick(t: float, dt: float) -> void:
	global_position = pos_at(t)
	if t >= 0.0 and director.authority():
		for k in all_karts():
			if k.state == Kart.State.RESPAWN:
				_rescued[k] = t
		var c := _cycle_at(t)
		# once a cycle, as soon as a kart comes in reach in the first part of it
		if c > _thrown and t - _cycle_start(c) < WINDOW * tm("cycle"):
			_pick(c, t)
	var flight := float(p["flight"])
	for c in _aims.keys():
		var e: Array = _aims[c]
		var t_throw: float = e[0]
		if t < t_throw + flight:
			_lock(e, t)
		if crossed(t_throw, t):
			_throw(e)
		if crossed(t_throw + flight, t):
			_burst(e)
		if visual:
			_show(e, t)
		if t > t_throw + flight + 0.5:
			_drop(c)
	if visual:
		_animate(t, dt)


## The authority picks, from the karts coming down the road of its zone, the one nearest its
## throw whose road point at the burst lies in the zone and in its range, and aims there.
func _pick(c: int, now: float) -> void:
	var zone: Array = p["zone"]
	var t_throw := now + tm("warn")
	var ahead_t := t_throw + float(p["flight"]) - now
	var from := throw_point(t_throw)
	var best: Kart = null
	var bd := float(p["range"])
	var aim_s := 0.0
	var aim_lat := 0.0
	for k in all_karts():
		if not targetable(k) or not on_road(k, float(zone[0]) - 100.0, float(zone[1])):
			continue
		if _rescued.has(k) and now - float(_rescued[k]) < RESCUED:
			continue
		var pred := k.global_position + k.velocity() * ahead_t * float(p["lead"])
		var i := path.closest(pred, k.path_index)
		var at_s := path.progress(pred, i)
		if not director.in_span(at_s, float(zone[0]), float(zone[1])):
			continue
		var d := from.distance_to(pred)
		if d >= bd:
			continue
		best = k
		bd = d
		aim_s = at_s
		aim_lat = path.lateral(pred, i)
	if best == null:
		return
	var hw := half_width(aim_s) - 1.2
	var aim := road_point(aim_s, clampf(aim_lat, -hw, hw), 0.1)
	_thrown = c
	send("aim", [c, t_throw, aim.x, aim.y, aim.z, director.slot_of(best)])


func on_event(kind: String, args: Array) -> void:
	if kind != "aim" or args.size() < 6:
		return
	var aim := Vector3(float(args[2]), float(args[3]), float(args[4]))
	var i := path.closest(aim)
	_aims[int(args[0])] = [float(args[1]), aim, path.progress(aim, i), path.lateral(aim, i), int(args[5]), {},
		Vector3.ZERO]
	director.note(self, "warn")
	play(_snd["alert"], global_position, 4.0, 30.0)


## While it winds up and the ball flies, its target sees the lock (HUD, bots) if this peer drives it.
func _lock(e: Array, t: float) -> void:
	var k := director.kart_at(int(e[4])) if int(e[4]) >= 0 else null
	if k and not k.remote and k.state == Kart.State.NORMAL:
		k.hazard_lock = maxf(float(e[0]) + float(p["flight"]) - t, 0.01)
		k.hazard_lock_from = global_position


func _throw(e: Array) -> void:
	director.note(self, "fire")
	play(_snd["attack"], global_position, 4.0, 30.0)
	play(_snd["throw"], global_position, 2.0, 24.0)
	if visual:
		e[6] = _between_hands()


func _burst(e: Array) -> void:
	var aim: Vector3 = e[1]
	if visual:
		var up := path.up[path.closest(aim)]
		Effects.shock_ring(get_parent(), aim, up, float(p["radius"]), Color(ORANGE, 0.9), 0.35)
		Effects.sparks(get_parent(), aim + up * 0.5, 1.2, ORANGE)
		Effects.flash_light(get_parent(), aim + up * 1.5, ORANGE, 6.0, 12.0, 0.4)
		play(_snd["burst"], aim, 4.0, 20.0)
	blast(aim, float(p["radius"]), str(p["effect"]), float(p["push"]), float(p["lift"]))


func _drop(c: int) -> void:
	var e: Array = _aims[c]
	for n in (e[5] as Dictionary).values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	_aims.erase(c)


# ---------------------------------------------------------------- the look
## The ring on the spot (fading in over the wind-up, pulsing faster as the ball nears) and the
## ball on its way there: from between its hands, a little over the straight line, at a steady pace.
## Both are made when first shown (none for an aim this peer slept through) and freed when it sleeps.
func _show(e: Array, t: float) -> void:
	var nodes: Dictionary = e[5]
	var t_throw: float = e[0]
	var flight := float(p["flight"])
	if t < t_throw + flight and not nodes.has("ring"):
		nodes["ring"] = Effects.ground_ring(get_parent(), e[1], path.up[path.closest(e[1])], float(p["radius"]),
			Color(ORANGE, 0.0))
	if t >= t_throw and t < t_throw + flight and not nodes.has("ball"):
		if e[6] == Vector3.ZERO:
			e[6] = throw_point(t_throw)
		nodes["ball"] = _ball()
	var ring: MeshInstance3D = nodes.get("ring")
	if is_instance_valid(ring):
		var u := clampf((t - (t_throw - tm("warn"))) / (tm("warn") + flight), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * (6.0 + 14.0 * u))
		ring.set_instance_shader_parameter("col", Color(ORANGE, (0.3 + 0.6 * u) * (0.6 + 0.4 * pulse)))
		ring.visible = t < t_throw + flight
	var ball: Node3D = nodes.get("ball")
	if is_instance_valid(ball):
		var u := clampf((t - t_throw) / flight, 0.0, 1.0)
		var from: Vector3 = e[6]
		ball.global_position = from.lerp(e[1], u) + Vector3.UP * 2.0 * 4.0 * u * (1.0 - u)
		ball.scale = Vector3.ONE * (0.9 + 0.15 * sin(t * 25.0))
		ball.visible = t < t_throw + flight


## The pose: its own float and flight animations as it goes round, the wind-up and throw of attack1
## through a cycle it aims in (sped up or slowed so its hands let go as the ball leaves), turned to
## the road or to its aim; the glow between its hands grows through the wind-up.
func _animate(t: float, dt: float) -> void:
	var act: Array = []
	for e in _aims.values():
		if t >= float(e[0]) - tm("warn") and t < float(e[0]) + 1.6:
			act = e
	var look: Vector3
	if not act.is_empty():
		look = act[1]
	else:
		_hint = path.closest(global_position, _hint if _hint >= 0 else path.index_at(s))
		look = path.center[_hint]
	var to := look - global_position
	if Vector2(to.x, to.z).length() > 0.5:
		_yaw = lerp_angle(_yaw, atan2(to.x, to.z), minf(1.0, dt * 3.0))
	var wind := 0.0
	if not act.is_empty():
		wind = clampf(1.0 - (float(act[0]) - t) / tm("warn"), 0.0, 1.0) if t < float(act[0]) else 0.0
	if _light:
		_light.light_energy = move_toward(_light.light_energy, 5.0 * wind, dt * 25.0)
	if _glow:
		_glow.visible = wind > 0.0
		if wind > 0.0:
			_glow.position = to_local(_between_hands())
			_glow.scale = Vector3.ONE * (0.4 + 1.6 * wind) * (0.9 + 0.1 * sin(t * 30.0))
	if _light and _glow:
		_light.position = _glow.position
	if model == null:
		return
	model.rotation.y = _yaw - rotation.y
	_idle_t -= dt
	if _idle_t <= 0.0:
		_idle_t = 5.0 + rnd(int(t), 5) * 7.0
		play(_snd["idle"], global_position, -2.0, 18.0)
	if anims == null or sk == null:
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < POSE_NEAR
	if not AnimSet.due(model, t, 0.0 if near else 12.0):
		return
	anims.pose(sk, "float", t + float(id) * 0.7)
	var fly := pos_at(t + 0.25) - pos_at(t)
	anims.pose(sk, "forward", t + float(id) * 0.7, clampf(Vector2(fly.x, fly.z).length() * 0.6, 0.0, 0.5))
	if act.is_empty():
		return
	var t0 := float(act[0]) - tm("warn")
	# through the wind-up at the pace that lets go as the ball leaves, then on at its own pace
	var a_t := (t - t0) * RELEASE / tm("warn") if t < float(act[0]) else RELEASE + (t - float(act[0]))
	var w := clampf((t - t0) / 0.25, 0.0, 1.0) * clampf((anims.length("attack1") - a_t) / 0.3, 0.0, 1.0)
	anims.pose(sk, "attack1", a_t, w, AnimSet.CLAMP)


## Between its hands as drawn now (in front of its chest without a model).
func _between_hands() -> Vector3:
	if sk and _hands.size() == 2 and _hands[0] >= 0 and _hands[1] >= 0:
		var a := sk.global_transform * sk.get_bone_global_pose(_hands[0]).origin
		var b := sk.global_transform * sk.get_bone_global_pose(_hands[1]).origin
		return (a + b) * 0.5
	return throw_point(director.clock())


## The ball: an orange flare in a glow, a light and a trail of sparks, humming.
func _ball() -> Node3D:
	var r := Node3D.new()
	get_parent().add_child(r)
	glow("materials/sprites/orangeflare1.png", 2.2, ORANGE, r)
	glow("materials/sprites/glow01.png", 3.2, Color(1.0, 0.7, 0.35, 0.8), r)
	var l := OmniLight3D.new()
	l.light_color = ORANGE
	l.omni_range = 9.0
	l.light_energy = 3.0
	l.shadow_enabled = false
	r.add_child(l)
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.5
	trail.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = Effects.sprite("materials/sprites/glow01.png", true, ORANGE)
	trail.mesh = q
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_max = 0.6
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.2
	r.add_child(trail)
	var snd := loop(_snd["ball"], r, 12.0, 0.0)
	if snd:
		snd.play()
	return r


func sleep() -> void:
	if _glow:
		_glow.visible = false
	if _light:
		_light.light_energy = 0.0
	for e in _aims.values():
		for n in (e[5] as Dictionary).values():
			if is_instance_valid(n):
				(n as Node).queue_free()
		(e[5] as Dictionary).clear()


## Bots: out of the burst when they would be in it as the ball lands.
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	for e in _aims.values():
		var left := float(e[0]) + float(p["flight"]) - t
		if left <= 0.0 or left > 3.5:
			continue
		var r := float(p["radius"]) + 2.0
		var lat := kart_lat(k)
		if absf(fposmod(at_s + speed * left - float(e[2]) + path.length * 0.5, path.length) - path.length * 0.5) > r \
				or absf(lat - float(e[3])) > r:
			continue
		var hw := half_width(float(e[2])) - 2.5
		var away := float(e[3]) - (r + 0.5) if float(e[3]) > 0.0 else float(e[3]) + r + 0.5
		return {"lat": clampf(away, -hw, hw), "w": 0.85}
	return {}


func is_active(t: float) -> bool:
	for e in _aims.values():
		if t > float(e[0]) - tm("warn") and t < float(e[0]) + float(p["flight"]):
			return true
	return false
