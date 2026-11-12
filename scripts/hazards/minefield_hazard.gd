class_name MinefieldHazard
extends Hazard
## Combine hopper mines sown across a dirt road, gaps between them to weave through. Only
## a local kart sets one off: its owner sends one "pop" event, every peer sees the mine
## hop at that kart and blow `hop` seconds later, and the mine climbs back out of the
## dirt `rearm` seconds after it went (on the shared clock).

const GRAVITY := 20.0
const RISE := 0.4

var _mines: Array = []    # [rest position, lap s, lateral, model, glow, armed, re-arm time, hop]
var _beep := 0.0
var _blink := 0.0
var _snd := {}


## range: how close a kart sets a mine off; radius: who its blast catches (the kart it hopped at,
## rarely a second); lead: how far ahead of its target it jumps (seconds of the target's speed,
## less than the hop takes: a kart at full speed gets away, a slow one is caught); blast: the
## explosion's look (Effects.explosion scale)
func defaults() -> Dictionary:
	return {"mines": [], "range": 3.5, "hop": 0.38, "lead": 0.2, "blast": 0.65, "radius": 4.5, "rearm": 15.0,
		"model": "props_combine/combine_mine01", "effect": "tumble"}


func build() -> void:
	_snd["tick"] = sounds([["weapons/grenade/tick1.wav"]])
	_snd["arm"] = sounds([["weapons/slam/mine_mode.wav"]])
	_snd["beep"] = sounds([["buttons/blip1.wav"]])
	var key := str(p["model"])
	for i in (p["mines"] as Array).size():
		var m: Array = p["mines"][i]
		var at := Vector3(m[0], m[1], m[2])
		var node: Node3D = null
		var g: MeshInstance3D = null
		if visual:
			node = Game.spawn_model(key) if Game.models.has(key) else Node3D.new()
			add_child(node)
			node.global_position = at + Vector3.UP * -Game.model_aabb(key).position.y
			node.global_rotation.y = rnd(i, 5) * TAU
			g = glow("materials/sprites/redglow1.png", 0.7, Color(1.0, 0.15, 0.1), node)
			g.position = Vector3.UP * 0.5
		_mines.append([at, float(m[3]) if m.size() > 3 else s, float(m[4]) if m.size() > 4 else 0.0, node, g, true,
			-1.0, []])


func tick(t: float, dt: float) -> void:
	_blink += dt
	_beep -= dt
	if _beep <= 0.0:
		_beep = 2.0
		play(_snd["beep"], road_point(span.x + 6.0, 0.0), -14.0, 8.0)
	for i in _mines.size():
		var m: Array = _mines[i]
		var hop: Array = m[7]
		if not hop.is_empty():
			_tick_hop(m, t)
			continue
		if not m[5]:
			if t >= float(m[6]):
				_rise(m, t)
			continue
		if visual and m[4]:
			(m[4] as Node3D).visible = fmod(_blink + i * 0.37, 1.0) < 0.4
		if t < 0.0:
			continue
		for k in local_karts():
			if k.state == Kart.State.RESPAWN or k.finished:
				continue
			if k.global_position.distance_to(m[0]) < float(p["range"]):
				send("pop", [i, t, director.slot_of(k)])
				break


## A disarmed mine whose time has come climbs back out of the dirt.
func _rise(m: Array, t: float) -> void:
	var u := clampf((t - float(m[6])) / RISE, 0.0, 1.0)
	var node: Node3D = m[3]
	if node:
		node.visible = true
		node.global_position = (m[0] as Vector3) + Vector3.UP * (-Game.model_aabb(str(p["model"])).position.y - 0.6 * (1.0 - u))
	if u >= 1.0:
		m[5] = true
		play(_snd["arm"], m[0], 0.0, 10.0)


func on_event(kind: String, args: Array) -> void:
	if kind != "pop" or args.size() < 3:
		return
	var i := int(args[0])
	if i < 0 or i >= _mines.size():
		return
	var m: Array = _mines[i]
	var t0 := float(args[1])
	# armed on the sender's clock is armed: a peer a tick behind may not have seen it climb out
	# yet (one already hopping is not)
	if not m[5] and (not (m[7] as Array).is_empty() or t0 < float(m[6]) + RISE - 0.1):
		return
	m[5] = false
	m[6] = t0 + tm("rearm")
	# it springs at where its target will be (the target's streamed position on other peers)
	var from: Vector3 = m[0]
	var target := director.kart_at(int(args[2]))
	var aim := target.global_position + target.velocity() * float(p["lead"]) - from if target else Vector3.ZERO
	var vel := aim / float(p["hop"]) + Vector3.UP * 4.0
	m[7] = [t0, from, vel]
	director.note(self, "fire", target)
	play(_snd["tick"], from, 2.0, 10.0, 1.4)


func _tick_hop(m: Array, t: float) -> void:
	var hop: Array = m[7]
	var tau := clampf(t - float(hop[0]), 0.0, float(p["hop"]))
	var pos: Vector3 = (hop[1] as Vector3) + (hop[2] as Vector3) * tau + Vector3.DOWN * GRAVITY * 0.5 * tau * tau
	if m[3]:
		(m[3] as Node3D).global_position = pos
	if t < float(hop[0]) + float(p["hop"]):
		return
	m[7] = []
	if m[3]:
		(m[3] as Node3D).visible = false
	if visual:
		Effects.explosion(get_parent(), pos, float(p["blast"]), null, false)
	blast(pos, float(p["radius"]), str(p["effect"]), 1.0, 0.4)


func snapshot(t: float) -> Array:
	var out := []
	for m in _mines:
		out.append_array([m[5], snappedf(m[6], 0.001) if t >= 0.0 else -1.0])
	return out


## Weave: pass the next armed mine out of its reach (and lean away from the one after),
## moving off the current line no more than that needs.
func advice(k: Kart, at_s: float, _speed: float) -> Dictionary:
	var next: Array = []
	for m in _mines:
		var d := ahead(at_s, float(m[1]))
		if m[5] and d < 30.0:
			next.append([d, float(m[2])])
	if next.is_empty():
		return {}
	next.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var hw := half_width(at_s) - 1.5
	var here := kart_lat(k)
	var clear := float(p["range"]) + 0.8
	var best := here
	var cost := INF
	var lat := -hw
	while lat <= hw:
		var c := absf(lat - here) * 0.1
		for j in mini(next.size(), 2):
			c += maxf(clear - absf(lat - float(next[j][1])), 0.0) * (2.0 if j == 0 else 0.6)
		if c < cost:
			cost = c
			best = lat
		lat += 0.5
	return {"lat": best, "w": 0.6}


func blocks_respawn(at_s: float) -> bool:
	return director.in_span(at_s, span.x, span.y)


func is_active(_t: float) -> bool:
	for m in _mines:
		if not (m[7] as Array).is_empty():
			return true
	return false
