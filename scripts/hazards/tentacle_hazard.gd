class_name TentacleHazard
extends Hazard
## A Xen tentacle rises out of the void beside a walled bridge: it sways, rears up,
## quivers, then slams down across part of the road and lies there before it lifts away.
## The whole cycle is a function of the shared clock. Its pose is a bone-chain curl worked
## out in the plane across the road, and the part of the road it covers is measured from
## that pose, so what you see is what hits.

const BASE_PERIOD := 7.0
const OVER := 1.6                 # the slam clears the wall by this much...
const REST := 0.5                 # ... and its tip comes to rest this high on the deck

var model: Node3D
var sk: Skeleton3D
var _m2s := Transform3D.IDENTITY
var _chain := PackedInt32Array()
var _len := PackedFloat32Array()  # bone lengths (metres, scaled)
var _rest := PackedFloat32Array() # rest angle of each bone from vertical, towards the road
var _total := 0.0
var _depth := 24.0                # the base is this far below the deck
var _out := 4.0                   # ... and this far out from the road edge
var _side := -1.0
var _cover := Vector2.ZERO        # lateral range the slam covers (measured from the pose)
var _slam := PackedFloat32Array() # absolute bone angles of the slam pose
var _sing: AudioStreamPlayer3D
var _snd := {}
var _pitch := {}


func defaults() -> Dictionary:
	return {"cover": [-6.0, 1.5], "scale": 1.5, "period": BASE_PERIOD, "first": 25.0, "phase": 0.0, "t_rise": 1.6,
		"t_hold": 3.4, "t_slam": 4.3, "t_hit": 4.5, "t_lift": 5.4, "t_idle": 6.6, "model": "hl1/tentacle2"}


func build() -> void:
	var i := path.index_at(s)
	var deck := path.center[i]
	var lat := path.lateral(global_position, i)
	_side = signf(lat) if absf(lat) > 0.1 else -1.0
	_depth = deck.y - global_position.y
	_out = absf(lat) - path.width[i] * 0.5
	var c: Array = p["cover"]
	_cover = Vector2(float(c[0]), float(c[1]))
	_sound_set()
	_measure_chain()
	if _total > 0.0:
		# grown (by up to 40%) until its slam reaches as far across as the spec asks
		var edge := _side * path.width[i] * 0.5
		var want := absf((_cover.y if _side < 0.0 else _cover.x) - edge)
		var grow := 1.0
		_slam = _slam_pose()
		var got := _covered(_slam)
		while absf((got.y if _side < 0.0 else got.x) - edge) < want and grow < 1.4:
			grow *= 1.05
			for k in _len.size():
				_len[k] *= 1.05
			_total *= 1.05
			_slam = _slam_pose()
			got = _covered(_slam)
		_cover = got
		if model:
			model.scale *= grow
	_sing = loop(["hl1src/tentacle/te_sing1.wav"], self, 20.0, -6.0)


func _sound_set() -> void:
	for k in [["alert", ["hl1src/tentacle/te_alert1.wav"], ["npc/zombie/zombie_alert3.wav"]],
			["roar", ["hl1src/tentacle/te_roar1.wav"], ["npc/zombie/zombie_pain5.wav"]],
			["swing", ["hl1src/tentacle/te_swing1.wav"], ["ambient/wind/windgust.wav"]],
			["strike", ["hl1src/tentacle/te_strike1.wav", "hl1src/tentacle/te_strike2.wav"],
				["physics/concrete/boulder_impact_hard1.wav", "physics/concrete/boulder_impact_hard2.wav"]],
			["move", ["hl1src/tentacle/te_move1.wav"], ["physics/flesh/flesh_scrape_rough_loop.wav"]]]:
		_snd[k[0]] = sounds([k[1], k[2]])
		# the stand-in zombie voices sung an octave down
		_pitch[k[0]] = 0.55 if not _snd[k[0]].is_empty() and str(_snd[k[0]][0]).begins_with("npc/zombie") else 1.0


## The bone chain up the tentacle (Bone01..Bone10, then the head and the tip): lengths
## and rest angles in the plane across the road (this node's Y up, +Z towards the road).
func _measure_chain() -> void:
	var key := str(p["model"])
	if not Game.models.has(key):
		return
	var sc := float(p["scale"])
	var pts: Array[Vector3] = []
	# the rig is read on every peer (a dedicated server too): the slam's reach comes from it
	model = Game.spawn_model(key)
	add_child(model)
	model.scale = Vector3.ONE * sc
	sk = HazardRig.skeleton(model)
	if sk:
		_m2s = HazardRig.model_to_skeleton(model, sk)
		for k in 10:
			var bi := HazardRig.bone(sk, "Bone%02d" % (k + 1))
			if bi < 0:
				break
			_chain.append(bi)
			pts.append(_m2s.affine_inverse() * sk.get_bone_global_rest(bi).origin * sc)
		var head := HazardRig.bone(sk, "Dummy04")
		if head >= 0:
			pts.append(_m2s.affine_inverse() * sk.get_bone_global_rest(head).origin * sc)
	if not visual:
		model.queue_free()
		model = null
		sk = null
	if pts.size() < 3:
		return
	var top := Game.model_aabb(key).end.y * sc
	pts.append(Vector3(pts[-1].x, maxf(top, pts[-1].y + 0.5), pts[-1].z + 0.3 * sc))
	for k in pts.size() - 1:
		var d := pts[k + 1] - pts[k]
		_len.append(Vector2(d.z, d.y).length())
		_rest.append(atan2(d.z, d.y))
		_total += _len[k]


## Absolute bone angles (from vertical, towards the road) following a curve that rises
## straight to `bend` metres along it at angle `lean`, then turns to angle `to` over 2*b metres.
func _shape(lean: float, bend: float, to: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var along := 0.0
	for k in _len.size():
		var m := along + _len[k] * 0.5
		out.append(lerpf(lean, to, smoothstep(bend - b, bend + b, m)))
		along += _len[k]
	return out


## Lying across the road: straight from the base to just over the wall, then sloping down
## so the tip rests on the deck however long the lying part is.
func _slam_pose() -> PackedFloat32Array:
	var over := Vector2(_out - 0.4, _depth + OVER)
	var lie := maxf(_total - over.length(), 1.0)
	return _shape(atan2(over.x, over.y), over.length(), PI * 0.5 + atan((OVER - REST) / lie), 1.2)


## Rearing up: nearly upright, its top curled back from the road.
func _rear_pose(q: float) -> PackedFloat32Array:
	return _shape(0.06 + q, _total * 0.7, -0.45 + q * 2.0, _total * 0.2)


## Waiting: leaning out over the void, the tip swaying just above the wall.
func _idle_pose(t: float) -> PackedFloat32Array:
	return _shape(-0.42 + sin(t * 0.9) * 0.05, _total * 0.6, 0.35 + sin(t * 1.3) * 0.17, _total * 0.25)


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, u: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in a.size():
		out.append(lerpf(a[k], b[k], u))
	return out


## Points of a pose in the plane: (towards the road from the base, up from the base).
func _fk(angles: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2.ZERO])
	for k in angles.size():
		out.append(out[k] + Vector2(sin(angles[k]), cos(angles[k])) * _len[k])
	return out


## The part of the road a pose lies on, as a lateral range (metres from the centre line).
func _covered(angles: PackedFloat32Array) -> Vector2:
	var far := _out
	for q in _fk(angles):
		if q.y > _depth - 0.5 and q.y < _depth + 3.0:
			far = maxf(far, q.x + 0.6)
	var hw := path.width[path.index_at(s)] * 0.5
	var a := _side * hw
	var b := _side * (hw + _out - far)
	return Vector2(minf(a, b), maxf(a, b))


# ---------------------------------------------------------------- the cycle (pure)
## Seconds into the cycle at clock t on the unscaled 7 s timeline, or -1 before the first.
func phase_at(t: float) -> float:
	if t < float(p["first"]):
		return -1.0
	var period := tm("period")
	return fposmod(t - float(p["first"]) + float(p["phase"]), period) * float(p["period"]) / period


## Clock time of the cycle's moment `key` (t_slam, t_hit, t_lift...) after clock t.
func next_time(t: float, key: String) -> float:
	var period := tm("period")
	var start := t - fposmod(t - float(p["first"]) + float(p["phase"]), period)
	var at := start + float(p[key]) * period / float(p["period"])
	return at if at >= t else at + period


func snapshot(t: float) -> Array:
	return [snappedf(phase_at(t), 0.001), _cover.snapped(Vector2.ONE * 0.01)]


func pose_at(t: float) -> PackedFloat32Array:
	var u := phase_at(t)
	if u < 0.0 or u >= float(p["t_idle"]):
		return _idle_pose(t)
	var rise := float(p["t_rise"])
	var hold := float(p["t_hold"])
	var slam := float(p["t_slam"])
	var strike := float(p["t_hit"])
	var lift := float(p["t_lift"])
	if u < rise:
		return _idle_pose(t)
	if u < hold:
		return _mix(_idle_pose(t), _rear_pose(0.0), smoothstep(rise, hold, u))
	if u < slam:
		return _rear_pose(sin(t * 31.0) * 0.03)       # quivering at the top
	if u < strike:
		var k := (u - slam) / (strike - slam)
		return _mix(_rear_pose(0.0), _slam, k * k)    # whipping down, faster and faster
	if u < lift:
		return _slam
	return _mix(_slam, _idle_pose(t), smoothstep(lift, float(p["t_idle"]), u))


func tick(t: float, _dt: float) -> void:
	var u := phase_at(t)
	if u >= 0.0:
		var start := t - u * tm("period") / float(p["period"])
		var k := tm("period") / float(p["period"])
		if crossed(start + float(p["t_rise"]) * k, t):
			director.note(self, "warn")
			play(_snd["alert"], _top(), 6.0, 40.0, _pitch["alert"])
		if crossed(start + 2.8 * k, t):
			play(_snd["roar"], _top(), 8.0, 50.0, _pitch["roar"])
		if crossed(start + float(p["t_slam"]) * k, t):
			play(_snd["swing"], _top(), 4.0, 30.0, _pitch["swing"])
		if crossed(start + float(p["t_hit"]) * k, t):
			_impact()
		if crossed(start + float(p["t_lift"]) * k, t):
			play(_snd["move"], road_point(s, (_cover.x + _cover.y) * 0.5), 2.0, 30.0, _pitch["move"])
		if u >= float(p["t_hit"]) - 0.05 and u < float(p["t_lift"]):
			_hit_karts()
	if sk and _total > 0.0:
		_apply(pose_at(t))


func _top() -> Vector3:
	return global_position + Vector3.UP * (_depth + 8.0)


func _impact() -> void:
	director.note(self, "fire")
	if visual:
		play(_snd["strike"], road_point(s, (_cover.x + _cover.y) * 0.5), 8.0, 40.0, _pitch["strike"])
		for k in 4:
			Effects.dust(get_parent(), road_point(s, lerpf(_cover.x, _cover.y, (k + 0.5) / 4.0), 0.3), 1.6)
		var player: Kart = director.race.player if director.race else null
		if player and player.global_position.distance_to(road_point(s, 0.0)) < 25.0:
			for cam in get_tree().get_nodes_in_group("race_camera"):
				cam.shake(0.7)


## Owners: a kart under the tentacle while it lies on the road is thrown.
func _hit_karts() -> void:
	var i := path.index_at(s)
	var c := path.center_at(s)
	for k in local_karts():
		var d := k.global_position - c
		var lat := d.dot(path.right[i])
		var h := d.dot(path.up[i])
		if absf(d.dot(path.fwd[i])) > 2.5 or lat < _cover.x - 0.8 or lat > _cover.y + 0.8 or h > 3.0 or h < -1.5:
			continue
		hit(k, "tumble", (-path.fwd[i] * 0.3 + path.up[i]) * k.mass * 6.0)


## Sets the chain to absolute angles: each bone turns by its change from rest, less what
## its parent already turned.
func _apply(angles: PackedFloat32Array) -> void:
	var rel := PackedFloat32Array()
	var prev := 0.0
	for k in _chain.size():
		var delta := angles[k] - _rest[k]
		rel.append(delta - prev)
		prev = delta
	HazardRig.curl(sk, _chain, _m2s.basis * Vector3.RIGHT, rel)


func wake() -> void:
	if _sing:
		_sing.play()


func sleep() -> void:
	if _sing:
		_sing.stop()


## Take the free part of the road when it will be down as the kart passes; a kart
## committed to the covered part slows to pass after it lifts.
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var dist := ahead(at_s, s)
	if dist > 150.0 or phase_at(director.clock() + dist / maxf(speed, 6.0)) < 0.0:
		return {}
	var t := director.clock()
	var slam := next_time(t, "t_slam")
	var lift := next_time(t, "t_lift")
	var eta := t + dist / maxf(speed, 6.0)
	var danger := (eta > slam - 0.4 and eta < lift + 0.2) or (lift < slam and eta < lift + 0.2)
	if not danger:
		return {}
	var hw := half_width(s) - 1.8
	var free := clampf((_cover.y + 0.8 + hw) * 0.5 if _side < 0.0 else (_cover.x - 0.8 - hw) * 0.5, -hw, hw)
	var lat := kart_lat(k)
	if dist < 25.0 and lat > _cover.x - 0.8 and lat < _cover.y + 0.8:
		return {"lat": free, "w": 0.8, "vmax": dist / maxf(lift + 0.3 - t, 0.3)}
	return {"lat": free, "w": 0.8}


func blocks_respawn(at_s: float) -> bool:
	return absf(fposmod(at_s - s + path.length * 0.5, path.length) - path.length * 0.5) <= 8.0


func is_active(t: float) -> bool:
	var u := phase_at(t)
	return u >= float(p["t_slam"]) and u < float(p["t_lift"])
