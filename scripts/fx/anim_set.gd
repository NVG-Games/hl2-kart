class_name AnimSet
extends RefCounted
## Plays a model's own animations on the Skeleton3D of its Game.spawn_model instances: the
## assets/models/<key>.anims.json that tools/mdl_anim.py (Source models) or tools/goldsrc_anim.py
## (Half-Life 1 models: hl1/controller, hl1/houndeye, hl1/bullsquid) writes, listed in ANIMS of
## tools/extract_all.py. One AnimSet per model key is loaded once and shared by every creature of
## that model; each skeleton's bone indices and rest pose are looked up once and kept on it.
##
## Use (a hazard's build() and tick(t, dt), t the shared hazard clock):
##   var anims := AnimSet.of("hl1/houndeye")   # null when this content has no animations for the key
##   var node := Game.spawn_model("hl1/houndeye")
##   var skel := AnimSet.skeleton(node)        # its Skeleton3D, null when it has none
##   anims.pose(skel, "run", t)                # "run" t seconds in; loops (the file's own loop flag)
##   anims.pose(skel, "attack", t - t0, 1.0, AnimSet.CLAMP)   # once from t0, then holds its last frame
##   anims.pose(skel, "walk", t)               # two animations blended: walk ...
##   anims.pose(skel, "run", t, 0.4)           # ... then 40 % of the way to run
##   if AnimSet.due(node, t, 15.0): ...        # pose a far creature only 15 times a second
##
## pose(skel, anim, time, weight = 1.0, mode = AUTO)
##   Weight 1 sets every bone the set animates: the ones this animation moves to its pose at `time`,
##   the others back to their rest. A weight between 0 and 1 mixes from the skeleton's current pose
##   (whatever the calls before it left) towards the animation, so blending two animations is two
##   calls. Mode AUTO loops when the file says the animation loops (HL1 sequences carry the flag,
##   Source ones count as looping), LOOP always loops, CLAMP plays once and holds the last frame.
##   Time 0 is the first frame; a loop's cycle is length(anim) and its last frame is its first again.
##   Between two frames bones turn by slerp and move by lerp. An unknown animation leaves the pose.
## length(anim)    seconds of one cycle: (frames - 1) / fps
## frames(anim), fps(anim), loops(anim), has(anim), names()
## move(anim)      metres one cycle carries the creature along forward(), at the model's own size
## speed(anim)     move / length in m/s: a creature scaled by s that walks at v m/s plays the
##                 animation at rate v / (speed(anim) * s), i.e. its time advances by dt times that
## forward()       the way the animated model faces in its own space: +Z for the HL1 creatures
##                 (their bind pose faces there too), +X when the file does not say (Source models)
## yaw_to(dir)     the node rotation.y that turns forward() onto the horizontal world direction dir
## events(anim)    [[frame, event, options], ...] of an HL1 sequence (empty for Source models)
## event_time(anim, event)  seconds into the animation of the first event with that number, -1 if
##                 none: the bullsquid's spit is event 1 of "range", the houndeye's blast event 3 of
##                 "attack", the controller's big ball event 2 of "shoot" (small shots: event 3 of
##                 "attack1")
## frame_at(anim, time, mode)  the fractional frame pose() samples at that time
## missing(skel)   names of animated bones this skeleton lacks (empty when everything maps)
## AnimSet.due(node, t, hz)  whether `node` is due another pose at clock time t, posing it at most
##                 hz times a second (hz <= 0: always); creatures start at different phases so a
##                 group does not pose all on the same frame
## AnimSet.skeleton(node)    the first Skeleton3D under a spawned model
##
## The controller's sequences hold its body about 0.9 m lower than its bind pose (HL1 floats it
## round its origin): animated it spans y -0.5 to 1.7 m, while Game.model_aabb gives the bind box
## (0.6 to 2.6 m). The houndeye and the bullsquid stand on y = 0 as in their bind pose (the feet
## within a few centimetres; the houndeye's jumpback lands 0.2 m low, the bullsquid's whip 0.1 m).
##
## Cost: 15 to 60 animated bones per HL1 creature; a pose touches only the bones the set animates,
## reuses the cached bone indices and skips position channels that never leave their rest. Measured
## headless (bullsquid, 57 bones): 24 us a pose, 59 us for two blended, so ten creatures at full rate
## take about 0.6 ms a frame. AnimSet.of() parses the JSON the first time (the bullsquid's 1.5 MB in
## about 30 ms), so call it in build(), not in the first tick().

const AUTO := -1
const CLAMP := 0
const LOOP := 1

static var _sets := {}  # key -> AnimSet, or null when the content has none

var key := ""
var _anims := {}  # name -> _Anim
var _bones := PackedStringArray()  # the set's bone slots: every bone any of its animations moves
var _pos_moved := PackedByteArray()  # per slot: 1 when some animation moves that bone off its rest place
var _forward := Vector3.RIGHT


class _Anim:
	var fps := 30.0
	var frames := 1
	var move := 0.0
	var loop := true
	var events: Array = []
	var slots := PackedInt32Array()  # per track: the bone's slot in the set
	var rots: Array = []  # per track: Array[Quaternion], a single entry when it never changes
	var poss: Array = []  # per track: Array[Vector3], a single entry when it never changes, empty at rest
	var idle := PackedInt32Array()  # slots of the set this animation leaves at rest


class _Map:
	var owner_key := ""
	var idx := PackedInt32Array()  # slot -> skeleton bone index, -1 when the skeleton lacks it
	var rest_r: Array[Quaternion] = []
	var rest_p: Array[Vector3] = []


## The animations of model `key` (loaded the first time, then shared), or null when there are none.
static func of(model_key: String) -> AnimSet:
	if _sets.has(model_key):
		return _sets[model_key]
	var s: AnimSet = null
	var path := "res://assets/models/%s.anims.json" % model_key
	if FileAccess.file_exists(path):
		var data = Game.load_json(path)
		if data is Dictionary and not (data as Dictionary).is_empty():
			s = AnimSet.new()
			s._load(model_key, data)
	_sets[model_key] = s
	return s


static func skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node
	var found := node.find_children("*", "Skeleton3D", true, false)
	return found[0] if found.size() > 0 else null


static func due(node: Object, t: float, hz: float) -> bool:
	if hz <= 0.0 or node == null:
		return true
	var period := 1.0 / hz
	if not node.has_meta(&"anim_t"):
		# start part of a period early, a different part per creature
		node.set_meta(&"anim_t", t - fmod(float(node.get_instance_id() % 1009) * 0.618034, 1.0) * period)
		return true
	var last: float = node.get_meta(&"anim_t")
	if t >= last + period or t < last:
		node.set_meta(&"anim_t", t if t < last else last + period * floorf((t - last) / period))
		return true
	return false


func _load(model_key: String, data: Dictionary) -> void:
	key = model_key
	var slot_of := {}
	for an in data:
		var src: Dictionary = data[an]
		var a := _Anim.new()
		a.fps = maxf(float(src.get("fps", 30.0)), 0.001)
		a.frames = maxi(int(src.get("frames", 1)), 1)
		a.move = float(src.get("move", 0.0))
		a.loop = bool(src.get("loop", true))
		a.events = src.get("events", [])
		if src.has("forward"):
			var f: Array = src["forward"]
			_forward = Vector3(f[0], f[1], f[2])
		var tracks: Dictionary = src.get("bones", {})
		for bn in tracks:
			if not slot_of.has(bn):
				slot_of[bn] = _bones.size()
				_bones.append(bn)
				_pos_moved.append(0)
			var slot: int = slot_of[bn]
			var rots: Array[Quaternion] = []
			for r in tracks[bn]["r"]:
				rots.append(Quaternion(r[0], r[1], r[2], r[3]).normalized())
			var poss: Array[Vector3] = []
			for v in tracks[bn]["p"]:
				poss.append(Vector3(v[0], v[1], v[2]))
			# a channel that holds still keeps one value
			if _still_q(rots):
				rots = rots.slice(0, 1)
			if _still_v(poss):
				poss = poss.slice(0, 1)
			a.slots.append(slot)
			a.rots.append(rots)
			a.poss.append(poss)
		_anims[an] = a
	# a position channel at the bone's rest place is dropped, the bone keeps its rest; the rest comes
	# from the skeleton, so that is decided per skeleton in _map: here only which slots move at all
	for an in _anims:
		var a: _Anim = _anims[an]
		var in_anim := {}
		for k in a.slots.size():
			in_anim[a.slots[k]] = true
		for s in _bones.size():
			if not in_anim.has(s):
				a.idle.append(s)


static func _still_q(qs: Array[Quaternion]) -> bool:
	for q in qs:
		if absf(q.dot(qs[0])) < 0.9999999:
			return false
	return true


static func _still_v(vs: Array[Vector3]) -> bool:
	for v in vs:
		if not v.is_equal_approx(vs[0]):
			return false
	return true


## The skeleton's bone indices and rest pose for this set's slots, looked up once per skeleton.
func _map(skel: Skeleton3D) -> _Map:
	if skel.has_meta(&"anim_set_map"):
		var m = skel.get_meta(&"anim_set_map")
		if m is _Map and (m as _Map).owner_key == key:
			return m
	var mm := _Map.new()
	mm.owner_key = key
	for s in _bones.size():
		var bn := _bones[s]
		var i := skel.find_bone(bn)
		if i < 0:
			i = skel.find_bone(bn.replace(".", "_"))
		mm.idx.append(i)
		var r := skel.get_bone_rest(i) if i >= 0 else Transform3D.IDENTITY
		mm.rest_r.append(r.basis.get_rotation_quaternion())
		mm.rest_p.append(r.origin)
	# from now on a position track equal to the rest is the same as no track
	for an in _anims:
		var a: _Anim = _anims[an]
		for k in a.slots.size():
			var ps: Array = a.poss[k]
			if ps.size() == 1 and (ps[0] as Vector3).is_equal_approx(mm.rest_p[a.slots[k]]):
				var none: Array[Vector3] = []
				a.poss[k] = none
			elif not ps.is_empty():
				_pos_moved[a.slots[k]] = 1
	skel.set_meta(&"anim_set_map", mm)
	return mm


func has(anim: String) -> bool:
	return _anims.has(anim)


func names() -> PackedStringArray:
	return PackedStringArray(_anims.keys())


func frames(anim: String) -> int:
	var a: _Anim = _anims.get(anim)
	return a.frames if a else 0


func fps(anim: String) -> float:
	var a: _Anim = _anims.get(anim)
	return a.fps if a else 0.0


func loops(anim: String) -> bool:
	var a: _Anim = _anims.get(anim)
	return a.loop if a else false


func length(anim: String) -> float:
	var a: _Anim = _anims.get(anim)
	return float(a.frames - 1) / a.fps if a else 0.0


func move(anim: String) -> float:
	var a: _Anim = _anims.get(anim)
	return a.move if a else 0.0


func speed(anim: String) -> float:
	var l := length(anim)
	return move(anim) / l if l > 0.0 else 0.0


func forward() -> Vector3:
	return _forward


func yaw_to(dir: Vector3) -> float:
	return atan2(dir.x, dir.z) - atan2(_forward.x, _forward.z)


func events(anim: String) -> Array:
	var a: _Anim = _anims.get(anim)
	return a.events if a else []


func event_time(anim: String, event: int) -> float:
	var a: _Anim = _anims.get(anim)
	if a == null:
		return -1.0
	for e in a.events:
		if int(e[1]) == event:
			return float(e[0]) / a.fps
	return -1.0


func frame_at(anim: String, time: float, mode := AUTO) -> float:
	var a: _Anim = _anims.get(anim)
	return _frame(a, time, mode) if a else 0.0


func _frame(a: _Anim, time: float, mode: int) -> float:
	if a.frames <= 1:
		return 0.0
	var last := float(a.frames - 1)
	if (a.loop if mode == AUTO else mode == LOOP):
		return fposmod(time * a.fps, last)
	return clampf(time * a.fps, 0.0, last)


func missing(skel: Skeleton3D) -> PackedStringArray:
	var out := PackedStringArray()
	if skel == null:
		return _bones
	var m := _map(skel)
	for s in _bones.size():
		if m.idx[s] < 0:
			out.append(_bones[s])
	return out


func pose(skel: Skeleton3D, anim: String, time: float, weight := 1.0, mode := AUTO) -> void:
	if skel == null or weight <= 0.0:
		return
	var a: _Anim = _anims.get(anim)
	if a == null:
		return
	var m := _map(skel)
	var f := _frame(a, time, mode)
	var i0 := int(f)
	var i1 := mini(i0 + 1, a.frames - 1)
	var t := f - float(i0)
	var full := weight >= 1.0
	for k in a.slots.size():
		var slot := a.slots[k]
		var bi := m.idx[slot]
		if bi < 0:
			continue
		var rs: Array[Quaternion] = a.rots[k]
		var q: Quaternion = rs[0] if rs.size() == 1 else rs[i0].slerp(rs[i1], t)
		if not full:
			q = skel.get_bone_pose_rotation(bi).slerp(q, weight)
		skel.set_bone_pose_rotation(bi, q)
		var ps: Array[Vector3] = a.poss[k]
		if ps.is_empty():
			if _pos_moved[slot] == 0:
				continue
			var rp := m.rest_p[slot]
			skel.set_bone_pose_position(bi, rp if full else skel.get_bone_pose_position(bi).lerp(rp, weight))
			continue
		var p: Vector3 = ps[0] if ps.size() == 1 else ps[i0].lerp(ps[i1], t)
		skel.set_bone_pose_position(bi, p if full else skel.get_bone_pose_position(bi).lerp(p, weight))
	# the set's other bones: this animation leaves them at rest
	for slot in a.idle:
		var bi := m.idx[slot]
		if bi < 0:
			continue
		var rq := m.rest_r[slot]
		skel.set_bone_pose_rotation(bi, rq if full else skel.get_bone_pose_rotation(bi).slerp(rq, weight))
		if _pos_moved[slot] == 1:
			var rp := m.rest_p[slot]
			skel.set_bone_pose_position(bi, rp if full else skel.get_bone_pose_position(bi).lerp(rp, weight))
