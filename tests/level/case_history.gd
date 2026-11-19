extends RefCounted
## P1: EditHistory (7.5) and the document's REVERSE / DELETE ops (2.4). A seeded 500-op fuzz through
## commit / gestures / merge keys / push_applied with undo and redo between, all undone, gives the
## identical document; "#uid" paths survive reorders; merge keys and gestures fold; the step and byte
## caps; push_applied; reverse twice = identical, reverse moves the per-segment fields, negates
## handle dirs and swaps branch sides (C1 S22); deleting a point re-anchors what sat on it.

const NEEDS_CONTENT := false

var t: Node


func run(t_: Node) -> void:
	t = t_
	_fuzz()
	_uid_paths()
	await _merges()
	_gestures()
	_caps()
	_push_applied()
	_reverse()
	_delete()


# ---------------------------------------------------------------- the fuzz

func _seed_doc(d: LevelDoc, next: Array, rng: RandomNumberGenerator) -> void:
	var ops := []
	for i in 6:
		ops.append(LevelDoc.op_insert(["road", "points"], -1, {"uid": _uid(next), "pos": [i * 30.0, 0.0, 0.0], "width": 14.0,
			"style": "asphalt"}))
	for i in 2:
		var pts := []
		for j in 3:
			pts.append({"uid": _uid(next), "pos": [j * 10.0, 0.0, 40.0 + i], "width": 10.0})
		ops.append(LevelDoc.op_insert(["branches"], -1, {"uid": _uid(next), "name": "B%d" % i, "points": pts}))
	for sec in ["props", "items", "hazards", "lights"]:
		for i in 4:
			ops.append(LevelDoc.op_insert([sec], -1, {"uid": _uid(next), "pos": [rng.randf_range(-100, 100), 0.0, rng.randf_range(-100, 100)]}))
	d.apply(ops)


func _uid(next: Array) -> int:
	next[0] += 1
	return next[0]


## A random op valid on the document as it is now.
func _random_op(d: LevelDoc, rng: RandomNumberGenerator, next: Array) -> Array:
	var lists := ["props", "items", "hazards", "lights"]
	var sec: String = lists[rng.randi() % lists.size()]
	var arr: Array = d.data[sec]
	match rng.randi() % 9:
		0, 1:
			if arr.is_empty():
				return LevelDoc.op_set(["env", "fog_sky"], rng.randf())
			var it: Dictionary = arr[rng.randi() % arr.size()]
			return LevelDoc.op_set([sec, "#%d" % int(it.uid), "pos"], [rng.randf(), rng.randf(), rng.randf()])
		2:
			if arr.is_empty():
				return LevelDoc.op_set(["name"], "N%d" % rng.randi())
			var it2: Dictionary = arr[rng.randi() % arr.size()]
			var k := "tag"
			if it2.has(k):
				return LevelDoc.op_erase([sec, "#%d" % int(it2.uid), k])
			return LevelDoc.op_set([sec, "#%d" % int(it2.uid), k], "x%d" % (rng.randi() % 9))
		3, 4:
			return LevelDoc.op_insert([sec], rng.randi_range(-1, arr.size()), {"uid": _uid(next), "pos": [rng.randf(), 0.0, rng.randf()]})
		5:
			if arr.size() < 2:
				return LevelDoc.op_set(["race", "laps"], rng.randi_range(1, 9))
			var it3: Dictionary = arr[rng.randi() % arr.size()]
			return ["remove", [sec], "#%d" % int(it3.uid)]
		6:
			var pts: Array = d.data.road.points
			return LevelDoc.op_set(["road", "points", "#%d" % int(pts[rng.randi() % pts.size()].uid), "width"], rng.randf_range(6, 40))
		7:
			var b: Dictionary = d.data.branches[rng.randi() % 2]
			if rng.randf() < 0.5:
				return LevelDoc.op_insert(["branches", "#%d" % int(b.uid), "points"], rng.randi_range(0, b.points.size()),
					{"uid": _uid(next), "pos": [rng.randf(), 0.0, rng.randf()]})
			var bp: Dictionary = b.points[rng.randi() % b.points.size()]
			return LevelDoc.op_set(["branches", "#%d" % int(b.uid), "points", "#%d" % int(bp.uid), "pos", 1], rng.randf_range(0, 9))
		_:
			var res_g := d.res()
			var w := rng.randi_range(1, 8)
			var h := rng.randi_range(1, 8)
			var vals := PackedFloat32Array()
			vals.resize(w * h)
			for i in vals.size():
				vals[i] = snappedf(rng.randf_range(-500, 1500), 0.01)
			return LevelDoc.op_heights(Rect2i(rng.randi_range(0, res_g - w), rng.randi_range(0, res_g - h), w, h), vals)


## A brush stroke written live, then pushed.
func _brush(d: LevelDoc, hist: EditHistory, rng: RandomNumberGenerator) -> void:
	var r := d.res()
	var rect := Rect2i(rng.randi_range(0, r - 6), rng.randi_range(0, r - 6), 5, 5)
	var before := PackedFloat32Array()
	var after := PackedFloat32Array()
	for z in rect.size.y:
		for x in rect.size.x:
			var i := (rect.position.y + z) * r + rect.position.x + x
			before.append(d.heights[i])
			d.heights[i] = snappedf(d.heights[i] + rng.randf_range(-2, 2), 0.01)
			after.append(d.heights[i])
	d.notify(PackedStringArray(["terrain"]), PackedInt32Array(), rect)
	hist.push_applied("Raise", [LevelDoc.op_heights(rect, after)], [LevelDoc.op_heights(rect, before)])


func _fuzz() -> void:
	var d := LevelDoc.blank("Fuzz", 512.0, 257)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var next := [1000]
	_seed_doc(d, next, rng)
	var hist := EditHistory.new(d)
	var data0 := d.data.duplicate(true)
	var h0 := d.heights.duplicate()
	var s0 := d.splat.duplicate()
	var ops := 0
	var undos := 0
	var redos := 0
	var signals := [0]
	hist.changed.connect(func() -> void: signals[0] += 1)
	while ops < 500:
		var r := rng.randf()
		if r < 0.55:
			var key := "" if rng.randf() < 0.7 else "k%d" % (rng.randi() % 3)
			hist.commit("Op %d" % ops, [_random_op(d, rng, next)], key)
			ops += 1
		elif r < 0.65:
			hist.begin_gesture("Drag %d" % ops)
			for i in rng.randi_range(1, 6):
				hist.commit("drag", [_random_op(d, rng, next)], "k0" if rng.randf() < 0.3 else "")
				ops += 1
			hist.end_gesture()
		elif r < 0.75:
			_brush(d, hist, rng)
			ops += 1
		elif r < 0.83:
			var batch := []
			for i in rng.randi_range(2, 3):
				batch.append(_random_op(d, rng, next))
			# a batch is drawn on the state before it applies: only take it when it applies whole
			var probe := LevelDoc.new()
			probe.data = d.data.duplicate(true)
			probe.heights = d.heights.duplicate()
			probe.splat = d.splat.duplicate()
			var inv := probe.apply(batch)
			if inv.size() == batch.size():
				hist.commit("Batch", batch)
				ops += batch.size()
		elif r < 0.95:
			if hist.undo():
				undos += 1
		else:
			if hist.redo():
				redos += 1
	t.check(hist.count() <= EditHistory.MAX_STEPS and hist.count() > 50, "fuzz: %d steps for 500 ops (%d undos, %d redos)" % [hist.count(), undos, redos])
	t.check(signals[0] > 0, "fuzz: changed was emitted")
	var data1 := d.data.duplicate(true)
	var h1 := d.heights.duplicate()
	var n := 0
	while hist.undo():
		n += 1
	t.check(not hist.can_undo() and hist.can_redo() and n == hist.position() + n and hist.undo_name() == "", "fuzz: undone to the start (%d steps)" % n)
	t.check(d.data == data0 and JSON.stringify(d.data) == JSON.stringify(data0), "fuzz: 500 ops undone give the identical data")
	t.check(d.heights == h0 and d.splat == s0, "fuzz: identical heights and splat")
	while hist.redo():
		pass
	t.check(d.data == data1 and d.heights == h1, "fuzz: redone gives the same state again")
	while hist.undo():
		pass
	t.check(d.data == data0 and d.heights == h0, "fuzz: undone again")
	hist.clear()
	t.check(hist.count() == 0 and hist.bytes == 0 and not hist.can_undo() and not hist.can_redo(), "clear")


# ---------------------------------------------------------------- focused cases

func _small() -> LevelDoc:
	var d := LevelDoc.blank("Small", 512.0, 257)
	d.apply([LevelDoc.op_insert(["props"], -1, {"uid": 1, "model": "a", "pos": [0.0, 0.0, 0.0]}),
		LevelDoc.op_insert(["props"], -1, {"uid": 2, "model": "b", "pos": [1.0, 0.0, 0.0]}),
		LevelDoc.op_insert(["props"], -1, {"uid": 3, "model": "c", "pos": [2.0, 0.0, 0.0]})])
	return d


func _uid_paths() -> void:
	var d := _small()
	var hist := EditHistory.new(d)
	hist.commit("Move b", [LevelDoc.op_set(["props", "#2", "pos"], [9.0, 9.0, 9.0])])
	hist.commit("Add at 0", [LevelDoc.op_insert(["props"], 0, {"uid": 4, "model": "d", "pos": [3.0, 0.0, 0.0]})])
	hist.commit("Remove a", [["remove", ["props"], "#1"]])
	t.check(d.data.props[1].uid == 2 and d.data.props[1].pos == [9.0, 9.0, 9.0], "#uid: b moved, then shifted by an insert")
	hist.undo()
	hist.undo()
	hist.undo()
	t.check(d.data.props.size() == 3 and d.data.props[1].uid == 2 and d.data.props[1].pos == [1.0, 0.0, 0.0], "#uid: all undone")
	# reorder behind the history's back (another step order): the uid path still finds b
	hist.redo()
	t.check(d.data.props[1].pos == [9.0, 9.0, 9.0], "#uid: redo")
	hist.commit("Reorder", [LevelDoc.op_set(["props"], [d.data.props[2].duplicate(true), d.data.props[1].duplicate(true), d.data.props[0].duplicate(true)])])
	hist.commit("Move b again", [LevelDoc.op_set(["props", "#2", "pos", 0], 5.0)])
	hist.undo()
	hist.undo()
	hist.redo()
	hist.redo()
	t.check(d.data.props[1].uid == 2 and d.data.props[1].pos == [5.0, 9.0, 9.0] and d.data.props[0].uid == 3, "#uid paths survive reorders")
	t.check(hist.undo_name() == "Move b again" and hist.names().size() == 3, "names")


func _merges() -> void:
	var d := _small()
	var hist := EditHistory.new(d)
	var orig := d.data.duplicate(true)
	for i in 5:
		hist.commit("Width", [LevelDoc.op_set(["props", "#1", "scale"], 1.0 + i)], "scale1")
	t.check(hist.count() == 1 and d.data.props[0].scale == 5.0, "same merge key within the window: one step")
	hist.commit("Other", [LevelDoc.op_set(["props", "#2", "scale"], 2.0)], "scale2")
	t.check(hist.count() == 2, "another key: a new step")
	hist.undo()
	hist.undo()
	t.check(d.data == orig, "a merged step undoes to before its first commit")
	hist.redo()
	hist.commit("Width", [LevelDoc.op_set(["props", "#1", "scale"], 7.0)], "scale1")
	t.check(hist.count() == 2 and not hist.can_redo(), "after an undo / redo the same key does not merge (and drops the redo)")
	hist.merge_window = 0.05
	hist.commit("W", [LevelDoc.op_set(["props", "#3", "scale"], 1.5)], "scale3")
	await t.frames(1)
	OS.delay_msec(80)
	hist.commit("W", [LevelDoc.op_set(["props", "#3", "scale"], 2.5)], "scale3")
	t.check(hist.count() == 4, "the same key after the window: a new step")
	hist.commit("Plain", [LevelDoc.op_set(["props", "#3", "scale"], 3.0)])
	hist.commit("Plain", [LevelDoc.op_set(["props", "#3", "scale"], 3.5)])
	t.check(hist.count() == 6, "no key: never merged")
	hist.commit("Nothing", [LevelDoc.op_erase(["props", "#3", "nope"])])
	t.check(hist.count() == 6, "ops that change nothing make no step")


func _gestures() -> void:
	var d := _small()
	var hist := EditHistory.new(d)
	var orig := d.data.duplicate(true)
	hist.begin_gesture("Move")
	t.check(hist.in_gesture() and hist.count() == 0, "a gesture makes no step until its first commit")
	for i in 10:
		hist.commit("drag", [LevelDoc.op_set(["props", "#1", "pos"], [float(i), 0.0, 0.0])], "k" if i % 2 == 0 else "")
	hist.end_gesture()
	var moved := d.data.duplicate(true)
	t.check(hist.count() == 1 and hist.undo_name() == "Move", "10 commits in a gesture: one step named after the gesture")
	hist.commit("Move", [LevelDoc.op_set(["props", "#1", "pos"], [99.0, 0.0, 0.0])], "k")
	t.check(hist.count() == 2, "a commit after the gesture does not fold into it")
	hist.undo()
	hist.undo()
	t.check(d.data == orig, "the gesture undone in one step")
	hist.redo()
	t.check(d.data == moved, "and redone")
	hist.begin_gesture("Slide")
	hist.commit("s", [LevelDoc.op_set(["props", "#2", "scale"], 2.0)])
	hist.undo()
	t.check(not hist.in_gesture() and d.data == moved, "undo inside a gesture ends it")


func _caps() -> void:
	var d := _small()
	var hist := EditHistory.new(d)
	for i in 600:
		hist.commit("Step %d" % i, [LevelDoc.op_set(["props", "#1", "scale"], float(i))])
	t.check(hist.count() == EditHistory.MAX_STEPS and hist.position() == EditHistory.MAX_STEPS, "600 steps: the oldest 100 dropped (500 kept)")
	while hist.undo():
		pass
	t.check(d.data.props[0].scale == 99.0 and hist.redo_name() == "Step 100", "undo stops at the oldest kept step")
	hist.clear()
	# the byte cap: brush steps of 64 KB each with a 300 KB cap
	hist.max_bytes = 300000
	var r := d.res()
	for k in 8:
		var vals := PackedFloat32Array()
		vals.resize(r * 32)
		vals.fill(float(k))
		var before := PackedFloat32Array()
		before.resize(r * 32)
		hist.push_applied("Brush %d" % k, [LevelDoc.op_heights(Rect2i(0, 0, r, 32), vals)], [LevelDoc.op_heights(Rect2i(0, 0, r, 32), before)])
	t.check(hist.bytes <= 300000 and hist.count() >= 2 and hist.count() < 8 and hist.undo_name() == "Brush 7",
		"the byte cap drops the oldest steps (%d steps, %d bytes)" % [hist.count(), hist.bytes])
	t.check(EditHistory.size_of(PackedFloat32Array([1.0, 2.0])) == 8 and EditHistory.size_of(PackedByteArray([1, 2, 3])) == 3,
		"packed arrays counted exactly")


func _push_applied() -> void:
	var d := LevelDoc.blank("Brush", 512.0, 257)
	var hist := EditHistory.new(d)
	var h0 := d.heights.duplicate()
	var r := d.res()
	var rect := Rect2i(10, 10, 4, 4)
	var before := PackedFloat32Array()
	var after := PackedFloat32Array()
	for z in 4:
		for x in 4:
			var i := (10 + z) * r + 10 + x
			before.append(d.heights[i])
			d.heights[i] = 3.25
			after.append(3.25)
	var rev := d.revision
	hist.push_applied("Raise", [LevelDoc.op_heights(rect, after)], [LevelDoc.op_heights(rect, before)])
	t.check(d.revision == rev and hist.undo_name() == "Raise", "push_applied records without applying")
	var h1 := d.heights.duplicate()
	hist.undo()
	t.check(d.heights == h0, "push_applied: undo restores the before-copy")
	hist.redo()
	t.check(d.heights == h1, "push_applied: redo writes the stroke again")
	# a stroke inside a gesture folds into it (+ a point set of ROADS FOLLOW THE GROUND)
	hist.begin_gesture("Smooth")
	hist.commit("x", [LevelDoc.op_set(["water", "level"], 2.0)])
	d.heights[0] = 9.0
	hist.push_applied("Smooth", [LevelDoc.op_heights(Rect2i(0, 0, 1, 1), PackedFloat32Array([9.0]))],
		[LevelDoc.op_heights(Rect2i(0, 0, 1, 1), PackedFloat32Array([0.0]))])
	hist.end_gesture()
	t.check(hist.count() == 2, "push_applied inside a gesture folds into its step")
	hist.undo()
	t.check(d.heights == h1 and d.data.water.level == 0.0, "the folded stroke and set undo together")


# ---------------------------------------------------------------- reverse and delete

func _p(uid: int, x: float, z: float, style: String) -> Dictionary:
	return {"uid": uid, "pos": [x, 0.0, z], "width": 14.0, "style": style, "seesaw": false, "follow": false}


func _rev_doc() -> LevelDoc:
	var d := LevelDoc.blank("Reverse", 1024.0, 513)
	var pts := [_p(1, 0.0, 0.0, "asphalt"), _p(2, 100.0, 0.0, "dirt"), _p(3, 100.0, 100.0, "sand"), _p(4, 0.0, 150.0, "street"),
		_p(5, -50.0, 60.0, "bridge")]
	pts[0]["handle"] = {"dir": [1.0, 0.0, 0.0], "in": 10.0, "out": 20.0}
	pts[1]["gap"] = {"len": 12.0, "at": 0.25, "lift": 1.8, "ramp": 16.0}
	pts[2]["barrier_l"] = LevelStyles.barrier("rail", 1.0)
	pts[3]["bank"] = 5.0
	pts[4]["grip"] = "offroad"
	d.data.road = {"closed": true, "start": {"p": 1, "t": 0.5}, "points": pts}
	d.data.branches = [{"uid": 10, "name": "CUT", "kind": "alt", "fork": {"p": 1, "t": 0.25}, "merge": {"p": 3, "t": 0.5},
		"side": 1, "merge_side": -1, "points": [_p(11, 50.0, 30.0, "dirt"), _p(12, 80.0, 60.0, "sand")],
		"ai": {"take": 0.5, "min_skill": 0.0, "commit": 40.0}, "risk": 0.0, "respawn": "before", "retry_back": 45.0, "offtrack": -1.0}]
	d.data.items = [{"uid": 20, "road": -1, "at": {"p": 2, "t": 0.25}, "count": 0, "inset": 2.5},
		{"uid": 25, "road": 10, "at": {"p": 11, "t": 0.5}, "count": 0, "inset": 2.5}]
	d.data.pads = [{"uid": 21, "road": -1, "at": {"p": 4, "t": 0.5}, "lat": 2.0, "turn": 10.0}]
	d.data.crowds = [{"uid": 22, "road": -1, "at": {"p": 3, "t": 0.5}, "side": 1, "length": 20.0, "rows": 2, "density": 1.0,
		"setback": 2.5, "role": "citizen", "mood": "fan", "sit": 0.0, "tags": []}]
	d.data.zones = [{"uid": 23, "road": -1, "a": {"p": 1, "t": 0.0}, "b": {"p": 2, "t": 0.5}, "scale": 0.4, "ease": 15.0}]
	d.data.hazards = [{"uid": 24, "type": "antlion", "at": {"p": 5, "t": 0.5}, "side": -1, "lat": 1.5,
		"zone": [{"p": 1, "t": 0.25}, {"p": 2, "t": 0.75}], "feel": "normal", "pts": [{"at": {"p": 3, "t": 0.5}, "side": 1, "setback": 4.0}], "p": {}},
		{"uid": 26, "type": "minefield", "at": {"p": 2, "t": 0.5}, "side": 0, "zone": null, "feel": "normal", "pts": [[10.0, -2.0], [12.0, 3.0]], "p": {}},
		{"uid": 27, "type": "strike_zone", "at": null, "side": 0, "zone": [{"p": 3, "t": 0.0}, {"p": 4, "t": 0.0}], "feel": "normal",
			"style": "arc", "pts": [[30.0, 5.0, -20.0]], "p": {}}]
	d.data.next_uid = 30
	return d


func _find(list: Array, uid: int) -> Dictionary:
	for it in list:
		if int(it.uid) == uid:
			return it
	return {}


func _reverse() -> void:
	var d := _rev_doc()
	var san := LevelDoc.sanitize(d.data, LevelReport.new())
	t.check(san == d.data, "reverse: the test doc is canonical")
	var orig := d.data.duplicate(true)
	var hist := EditHistory.new(d)
	hist.commit("Reverse track direction", d.reverse_ops())
	var x: Dictionary = d.data
	var uids := []
	for p in x.road.points:
		uids.append(int(p.uid))
	t.check(uids == [5, 4, 3, 2, 1], "reverse: point order %s" % str(uids))
	var p1 := _find(x.road.points, 1)
	var p2 := _find(x.road.points, 2)
	var p3 := _find(x.road.points, 3)
	var p4 := _find(x.road.points, 4)
	var p5 := _find(x.road.points, 5)
	t.check(p2.style == "asphalt" and p3.style == "dirt" and p4.style == "sand" and p5.style == "street" and p1.style == "bridge",
		"reverse: each segment's style moved to its new owner")
	t.check(not p2.has("gap") and p3.has("gap") and p3.gap.at == 0.75, "reverse: the gap moved with its segment, at -> 1 - at")
	t.check(not p3.has("barrier_l") and p4.has("barrier_r") and not p4.has("barrier_l") and p4.barrier_r.kind == "rail",
		"reverse: barrier_l became barrier_r on the new owner")
	t.check(p1.has("grip") and p1.grip == "offroad" and not p5.has("grip"), "reverse: grip moved (closing segment)")
	t.check(p1.handle.dir == [-1.0, 0.0, 0.0] and p1.handle.in == 20.0 and p1.handle.out == 10.0, "reverse: handle dir negated, in / out swapped")
	t.check(p4.bank == -5.0, "reverse: bank negated")
	t.check(x.road.start == {"p": 2, "t": 0.5}, "reverse: the start anchor is the same spot ({next(p), 1 - t})")
	t.check(_find(x.items, 20).at == {"p": 3, "t": 0.75}, "reverse: a crate row anchor -> {next(p), 1 - t}")
	var pad := _find(x.pads, 21)
	t.check(pad.at == {"p": 5, "t": 0.5} and pad.lat == -2.0 and pad.turn == -10.0, "reverse: pad lat and turn negated")
	t.check(_find(x.crowds, 22).side == -1, "reverse: crowd side negated")
	var zn := _find(x.zones, 23)
	t.check(zn.a == {"p": 3, "t": 0.5} and zn.b == {"p": 2, "t": 1.0}, "reverse: zone ends swapped")
	var hz := _find(x.hazards, 24)
	t.check(hz.at == {"p": 1, "t": 0.5} and hz.side == 1 and hz.lat == -1.5 and hz.zone == [{"p": 3, "t": 0.25}, {"p": 2, "t": 0.75}]
		and hz.pts[0].at == {"p": 4, "t": 0.5} and hz.pts[0].side == -1, "reverse: hazard anchor, side, lat, zone and points")
	t.check(_find(x.hazards, 26).pts == [[10.0, 2.0], [12.0, -3.0]] and _find(x.hazards, 27).pts == [[30.0, 5.0, -20.0]],
		"reverse: [s, lat] points change side, a strike_zone core stays put")
	var br: Dictionary = x.branches[0]
	t.check(br.fork == {"p": 4, "t": 0.5} and br.merge == {"p": 2, "t": 0.75} and br.side == 1 and br.merge_side == -1
		and br.respawn == "after", "reverse: branch fork / merge swapped, sides swapped and negated, respawn before -> after")
	t.check(br.points[0].uid == 12 and br.points[0].style == "dirt" and br.points[1].style == "sand", "reverse: branch points reversed with their segments")
	t.check(_find(x.items, 25).at == {"p": 12, "t": 0.5}, "reverse: an anchor on the branch follows the branch")
	t.check(LevelDoc.sanitize(d.data, LevelReport.new()) == d.data, "reverse: the result is canonical")
	hist.commit("Reverse track direction", d.reverse_ops())
	t.check(d.data == orig and JSON.stringify(d.data) == JSON.stringify(orig), "reverse twice = identical")
	hist.undo()
	hist.undo()
	t.check(d.data == orig and hist.count() == 2, "reverse: each is one undo step")
	# an open road
	var o := _rev_doc()
	o.data.road.closed = false
	var o0 := o.data.duplicate(true)
	o.apply(o.reverse_ops())
	t.check(o.data.road.points[0].uid == 5 and o.data.road.points[-1].style == "bridge", "reverse: an open road")
	o.apply(o.reverse_ops())
	t.check(o.data == o0, "reverse twice = identical (open road)")
	t.check(LevelDoc.blank("E").reverse_ops().is_empty(), "reverse of an empty road: no ops")


func _del_doc() -> LevelDoc:
	var d := LevelDoc.blank("Delete", 1024.0, 513)
	d.data.road = {"closed": true, "start": {"p": 2, "t": 0.5}, "points": [_p(1, 0.0, 0.0, "asphalt"), _p(2, 30.0, 0.0, "asphalt"),
		_p(3, 40.0, 0.0, "asphalt"), _p(4, 40.0, 40.0, "asphalt")]}
	d.data.items = [{"uid": 10, "road": -1, "at": {"p": 1, "t": 0.5}, "count": 0, "inset": 2.5},
		{"uid": 11, "road": -1, "at": {"p": 2, "t": 0.5}, "count": 0, "inset": 2.5},
		{"uid": 22, "road": 20, "at": {"p": 21, "t": 0.5}, "count": 0, "inset": 2.5}]
	d.data.pads = [{"uid": 12, "road": -1, "at": {"p": 3, "t": 0.25}, "turn": 0.0}]
	d.data.hazards = [{"uid": 13, "type": "antlion", "at": null, "side": 0, "zone": [{"p": 1, "t": 0.0}, {"p": 2, "t": 1.0}], "feel": "normal",
		"pts": [{"at": {"p": 2, "t": 0.0}, "side": 1}], "p": {}}]
	d.data.branches = [{"uid": 20, "name": "B", "kind": "alt", "fork": {"p": 2, "t": 0.25}, "merge": {"p": 4, "t": 0.5}, "side": 0,
		"merge_side": 0, "points": [_p(21, 20.0, 20.0, "dirt")], "ai": {"take": 0.5, "min_skill": 0.0, "commit": 40.0}, "risk": 0.0,
		"respawn": "before", "retry_back": 45.0, "offtrack": -1.0}]
	d.data.next_uid = 30
	return d


func _delete() -> void:
	var d := _del_doc()
	t.check(LevelDoc.sanitize(d.data, LevelReport.new()) == d.data, "delete: the test doc is canonical")
	var orig := d.data.duplicate(true)
	var hist := EditHistory.new(d)
	# B (uid 2): A-B 30 m, B-C 10 m
	hist.commit("Delete point", d.delete_point_ops(2))
	var x: Dictionary = d.data
	t.check(x.road.points.size() == 3 and d.find(2).is_empty() and x.road.closed, "delete: the point is gone, the loop stays closed")
	t.check(x.road.start == {"p": 1, "t": 0.875}, "delete: the start re-anchored onto the previous segment")
	t.check(_find(x.items, 10).at == {"p": 1, "t": 0.375} and _find(x.items, 11).at == {"p": 1, "t": 0.875},
		"delete: items on both segments re-anchored, t rescaled by length (0.5 -> 0.375, 0.5 -> 0.875)")
	t.check(_find(x.pads, 12).at == {"p": 3, "t": 0.25} and _find(x.items, 22).at == {"p": 21, "t": 0.5}, "delete: items elsewhere untouched")
	var hz := _find(x.hazards, 13)
	t.check(hz.zone == [{"p": 1, "t": 0.0}, {"p": 1, "t": 1.0}] and hz.pts[0].at == {"p": 1, "t": 0.75}, "delete: hazard zone and points re-anchored")
	t.check(x.branches[0].fork == {"p": 1, "t": 0.8125} and x.branches[0].merge == {"p": 4, "t": 0.5}, "delete: a branch end re-anchored")
	t.check(LevelDoc.sanitize(d.data, LevelReport.new()) == d.data, "delete: the result is canonical (every anchor valid)")
	hist.undo()
	t.check(d.data == orig, "delete: one undo step restores everything")
	# a closed loop left with 2 points opens
	hist.redo()
	hist.commit("Delete point", d.delete_point_ops(3))
	t.check(not d.data.road.closed and d.data.road.points.size() == 2 and LevelDoc.sanitize(d.data, LevelReport.new()) == d.data,
		"delete: a loop of 2 points opens, every anchor still valid")
	hist.undo()
	hist.undo()
	t.check(d.data == orig, "delete: undone")
	# open road ends
	var o := _del_doc()
	o.data.road.closed = false
	o.apply(o.delete_point_ops(1))
	t.check(_find(o.data.items, 10).at == {"p": 2, "t": 0.0} and o.data.hazards[0].zone[0] == {"p": 2, "t": 0.0},
		"delete: the first point of an open road: its items move to the next point")
	var o2 := _del_doc()
	o2.data.road.closed = false
	o2.data.pads[0].at = {"p": 3, "t": 0.5}
	o2.apply(o2.delete_point_ops(4))
	t.check(_find(o2.data.pads, 12).at == {"p": 2, "t": 1.0} and o2.data.branches[0].merge == {"p": 2, "t": 1.0}
		and LevelDoc.sanitize(o2.data, LevelReport.new()) == o2.data, "delete: the last point of an open road")
	# a branch's only point: the branch and what sits on it go
	var b := _del_doc()
	var bh := EditHistory.new(b)
	var b0 := b.data.duplicate(true)
	bh.commit("Delete point", b.delete_point_ops(21))
	t.check(b.data.branches.is_empty() and _find(b.data.items, 22).is_empty() and b.data.items.size() == 2, "delete: a branch's last point removes the branch")
	bh.undo()
	t.check(b.data == b0, "delete: the branch comes back with one undo")
	# the main road's last point: everything anchored on it goes
	var m := LevelDoc.blank("One", 1024.0, 513)
	m.data.road.points = [_p(1, 0.0, 0.0, "asphalt")]
	m.data.road.start = {"p": 1, "t": 0.0}
	m.data.items = [{"uid": 5, "road": -1, "at": {"p": 1, "t": 0.0}, "count": 0, "inset": 2.5}]
	m.data.props = [{"uid": 6, "model": "a", "pos": [0.0, 0.0, 0.0], "yaw": 0.0, "pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": ""}]
	m.apply(m.delete_point_ops(1))
	t.check(m.data.road.points.is_empty() and m.data.items.is_empty() and m.data.props.size() == 1 and m.data.road.start == {"p": 0, "t": 0.0},
		"delete: the main road's last point removes its items, keeps props")
	t.check(d.delete_point_ops(10).is_empty() and d.delete_point_ops(999).is_empty(), "delete: not a road point -> no ops")
