class_name TripmineHazard
extends Hazard
## An HL1 laser tripmine on the corridor wall with its beam across part of the road to a
## stand of crates: drive through the beam and it goes off. Only a local kart can trip
## it; its owner sends one "trip" event, every peer replays the blast, and the mine
## re-arms on the shared clock (never while a kart is on the beam).

const BEAM := Color(1.0, 0.1, 0.08, 0.9)

var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _n := Vector3.RIGHT          # the beam plane's normal (horizontal)
var _floor := 0.0
var _armed := true
var _rearm_at := -1.0
var _charging := false
var _sides := {}                 # kart -> which side of the beam it was on last tick
var _beam: MeshInstance3D
var _ends: Array[MeshInstance3D] = []
var _led: MeshInstance3D
var _hum: AudioStreamPlayer3D
var _blink := 0.0
var _free_lat := 0.0
var _crates: Array = []          # the stand, crate by crate (a kart may have freed some)
var _snd := {}


func defaults() -> Dictionary:
	return {"a": [], "b": [], "stand": [], "stand_yaw": 0.0, "stand_model": "props_junk/wood_crate001a", "stand_n": 2,
		"model": "hl1/p_tripmine", "fallback": "weapons/w_slam", "rearm": 10.0, "radius": 4.5, "effect": "tumble"}


func build() -> void:
	var a: Array = p["a"]
	var b: Array = p["b"]
	_a = Vector3(a[0], a[1], a[2]) if a.size() == 3 else global_position
	_b = Vector3(b[0], b[1], b[2]) if b.size() == 3 else global_position + global_basis.z * 6.0
	_n = Vector3.UP.cross(_b - _a).normalized()
	var i := path.index_at(s)
	_floor = path.center[i].y
	var la := path.lateral(_a, i)
	var lb := path.lateral(_b, i)
	var hw := half_width(s)
	# the open part of the road: from just past the stand to the far edge
	var past := lb + signf(lb - la) * 2.6
	_free_lat = (past + signf(lb - la) * (hw - 1.4)) * 0.5
	_build_stand()
	_snd["charge"] = sounds([["hl1src/weapons/mine_charge.wav"], ["npc/roller/mine/rmine_blip1.wav"]])
	_snd["activate"] = sounds([["hl1src/weapons/mine_activate.wav"], ["buttons/button17.wav"]])
	if not visual:
		return
	# the mine on the wall faces along the beam (this node's +Z points at the stand)
	var key := pick_model([p["model"], p["fallback"]])
	if key != "":
		add_child(Game.spawn_model(key))
	else:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.22, 0.14)
		box.mesh = bm
		box.material_override = SourceMaterials.world_material("metal/citadel_metalwall072a", Vector2.ONE)
		add_child(box)
	_beam = Effects.beam_node(BEAM, 0.08, "materials/sprites/laserbeam.png", true)
	add_child(_beam)
	Effects.place_beam(_beam, _a, _b)
	for at in [_a, _b]:
		var g := glow("materials/sprites/redglow1.png", 0.5, BEAM)
		g.global_position = at
		_ends.append(g)
	_led = glow("materials/sprites/redglow1.png", 0.25, Color(1.0, 0.2, 0.1))
	_led.position = Vector3(0.0, 0.05, 0.08)
	_hum = loop(["ambient/energy/force_field_loop1.wav", "weapons/physcannon/hold_loop.wav"], self, 4.0, -20.0)


## A stack of crates the beam ends on, so the beam has an end you can see. Like street
## furniture they are not solid to karts: one that runs into the stand knocks the crates flying
## (Kart._knock_over) instead of being wedged on it, and the mine stacks them again as it re-arms.
func _build_stand() -> void:
	var st: Array = p["stand"]
	if st.size() != 3:
		return
	var key := str(p["stand_model"])
	var box := Game.model_aabb(key)
	for k in maxi(int(p["stand_n"]), 1):
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_KNOCK
		body.collision_mask = 0
		body.set_meta("surface", "wall")
		body.set_meta("knockable", key)
		add_child(body)
		body.global_position = Vector3(st[0], st[1], st[2]) + Vector3.UP * (-box.position.y + box.size.y * k)
		body.global_rotation = Vector3(0.0, float(p["stand_yaw"]) + 0.35 * k, 0.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size
		cs.shape = bs
		cs.position = box.get_center()
		body.add_child(cs)
		if visual and Game.models.has(key):
			body.add_child(Game.spawn_model(key))
		_crates.append(body)


func tick(t: float, dt: float) -> void:
	if not _armed and t >= _rearm_at - 4.0 and not _charging:
		_charging = true
		play(_snd["charge"], _a, -4.0, 8.0)
	if not _armed and t >= _rearm_at and not _on_beam():
		_arm()
	if visual:
		_blink += dt * (6.0 if _charging and not _armed else 1.0)
		_led.visible = fmod(_blink, 1.0) < 0.3
	if not _armed or t < 0.0:
		return
	for k in local_karts():
		var side := signf((k.global_position - _a).dot(_n))
		var was: float = _sides.get(k, side)
		_sides[k] = side
		if side == was or k.state == Kart.State.RESPAWN or k.finished:
			continue
		var at := Geometry3D.get_closest_point_to_segment(k.global_position, _a, _b)
		if at.distance_to(k.global_position) < 2.0 and k.global_position.y - _floor < 1.6:
			send("trip", [0, t, at.x, at.y, at.z])
			return


func _on_beam() -> bool:
	for k in all_karts():
		if Geometry3D.get_closest_point_to_segment(k.global_position, _a, _b).distance_to(k.global_position) < 2.0:
			return true
	return false


func _arm() -> void:
	_armed = true
	_charging = false
	_sides.clear()
	play(_snd["activate"], _a, 0.0, 8.0)
	# a stand a kart knocked over is stacked again
	if _crates.any(func(c) -> bool: return not is_instance_valid(c)):
		for c in _crates:
			if is_instance_valid(c):
				c.queue_free()
		_crates.clear()
		_build_stand()
	if not visual:
		return
	_beam.visible = true
	for g in _ends:
		g.visible = true
	# a short flicker as it comes back on
	var tw := _beam.create_tween()
	for i in 3:
		tw.tween_callback(func(): _beam.visible = false)
		tw.tween_interval(0.035)
		tw.tween_callback(func(): _beam.visible = true)
		tw.tween_interval(0.035)
	if _hum:
		_hum.play()


func on_event(kind: String, args: Array) -> void:
	# armed on the sender's clock is armed: a peer a tick behind (or one that waited for a kart
	# to clear the beam) may not have re-armed it yet
	if kind != "trip" or args.size() < 5 or (not _armed and float(args[1]) < _rearm_at - 0.1):
		return
	var at := Vector3(float(args[2]), float(args[3]), float(args[4]))
	_armed = false
	_charging = false
	_rearm_at = float(args[1]) + tm("rearm")
	director.note(self, "fire")
	if visual:
		Effects.explosion(get_parent(), at, 0.6, null, false)
		_beam.visible = false
		for g in _ends:
			g.visible = false
		if _hum:
			_hum.stop()
	blast(at, float(p["radius"]), str(p["effect"]), 1.0, 0.4)


func wake() -> void:
	if _hum and _armed:
		_hum.play()


func sleep() -> void:
	_sides.clear()
	if _hum:
		_hum.stop()


## Keep to the open part of the road while the beam is up (from 60 m before it: time enough
## to change lanes, not a whole corridor on the wrong line).
func advice(_k: Kart, at_s: float, _speed: float) -> Dictionary:
	return {"lat": _free_lat, "w": 0.6} if _armed and ahead(at_s, s) < 60.0 else {}


func blocks_respawn(at_s: float) -> bool:
	return absf(fposmod(at_s - s + path.length * 0.5, path.length) - path.length * 0.5) <= 6.0


func is_active(_t: float) -> bool:
	return _armed
