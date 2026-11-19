extends RefCounted
## P13: the FIX buttons of 1.8 (LevelFixes) without content. Each crafted document raises its
## error; LevelFixes.ops of that issue, committed as one EditHistory step, compiles without it,
## and one undo gives the document back exactly: CLOSE LOOP, NARROW THE ROAD HERE, MAKE A BRIDGE
## (a crossing and an embankment), CLEAR THE GRID (a bank and a jump), REMOVE THE JUMP, SMOOTH
## HEIGHTS HERE (steep and steep_warn), RAISE ABOVE THE WATER (the sea and a lake), MOVE TO A
## LEGAL SPOT (a fork on a banked bend), ADD THE SEE-SAW / DELETE (hazard_setup), AUTO ITEMS and
## DELETE (a prop on the road); LABELS names every fix id of LevelValidate.FIXES.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}
const CaseCompile := preload("res://tests/level/case_compile.gd")

var t: Node


func run(tt: Node) -> void:
	t = tt
	_labels()
	_close_loop()
	_narrow()
	_crossing()
	_embankment()
	_grid()
	_start_jump()
	_steep()
	_water()
	_legal_spot()
	_hazard_setup()
	_items_and_props()


# ---------------------------------------------------------------- helpers

func _compile(doc: LevelDoc) -> LevelBuild:
	return LevelCompiler.compile(doc, {"id": "c_edit", "registries": REG, "flags": true, "chunks": false})


func _codes(b: LevelBuild) -> PackedStringArray:
	var out := PackedStringArray()
	for it in b.report.items:
		out.append(str(it.code))
	return out


## The issue `code` of doc's bake, its FIX applied as one history step, recompiled: the code is
## gone; one undo gives the document back. Returns the bake after the fix (null when it did not fire).
func _fix(doc: LevelDoc, code: String, what: String, pick := Callable()) -> LevelBuild:
	var b := _compile(doc)
	var it := b.report.first(code)
	if pick.is_valid():
		for x in b.report.all_of(code):
			if pick.call(x):
				it = x
	t.check(not it.is_empty(), "%s: %s fires (%s)" % [what, code, str(_codes(b))])
	if it.is_empty():
		return null
	var fix := str(it.get("fix", ""))
	t.check(LevelFixes.LABELS.has(fix), "%s: the fix %s has a label" % [what, fix])
	var before := _json(doc)
	var h := EditHistory.new(doc)
	var ops := LevelFixes.ops(it, doc, b)
	t.check(not ops.is_empty(), "%s: FIX %s gives ops" % [what, LevelFixes.LABELS.get(fix, fix)])
	h.commit("FIX: " + str(LevelFixes.LABELS.get(fix, fix)), ops)
	var after := _compile(doc)
	var near := 0
	for x in after.report.all_of(code):
		if not (it.get("pos") is Vector3) or not (x.get("pos") is Vector3) or (x.pos as Vector3).distance_to(it.pos) < 40.0:
			near += 1
	t.check(near == 0, "%s: after FIX %s no %s there (%s)" % [what, LevelFixes.LABELS.get(fix, fix), code, str(_codes(after))])
	t.check(h.can_undo() and h.undo_name().begins_with("FIX: "), "%s: one undo step named FIX: ... (%s)" % [what, h.undo_name()])
	h.undo()
	t.check(_json(doc) == before and not h.can_undo(), "%s: one undo gives the document back" % what)
	h.redo()
	return after


## The document without next_uid (new uids are taken outside the history, 7.5).
func _json(doc: LevelDoc) -> String:
	var d: Dictionary = doc.data.duplicate(true)
	d.erase("next_uid")
	return JSON.stringify(d)


func _oval(doc: LevelDoc, a := 180.0, b := 110.0, count := 20, y := 0.0, style := "asphalt", w := 14.0) -> Array:
	return CaseCompile.oval(doc, a, b, count, y, style, w)


## A stadium loop on the plain (no terrain): the right straight x = +r from z = -400 to +400
## (100 m between points, driven toward +z), the arcs, the left straight. uids from 1.
func _stadium(doc: LevelDoc, r := 200.0) -> Array:
	var raw := []
	for k in 9:
		raw.append(Vector3(r, 0.0, -400.0 + 100.0 * k))
	var arc := maxi(3, roundi(PI * r / 75.0) - 1)
	for k in arc:
		var a := PI * (k + 1) / (arc + 1)
		raw.append(Vector3(r * cos(a), 0.0, 400.0 + r * sin(a)))
	for k in 9:
		raw.append(Vector3(-r, 0.0, 400.0 - 100.0 * k))
	for k in arc:
		var a := PI + PI * (k + 1) / (arc + 1)
		raw.append(Vector3(r * cos(a), 0.0, -400.0 + r * sin(a)))
	var pts := []
	for k in raw.size():
		var p: Vector3 = raw[k]
		pts.append({"uid": k + 1, "pos": [p.x, p.y, p.z], "width": 14.0, "style": "asphalt"})
	doc.data.road = {"closed": true, "start": {"p": 12, "t": 0.0}, "points": pts}
	doc.data.next_uid = 200
	return pts


# ---------------------------------------------------------------- cases

func _labels() -> void:
	for code in LevelValidate.FIXES:
		var fix := str(LevelValidate.FIXES[code])
		if fix != "":
			t.check(LevelFixes.LABELS.has(fix), "LABELS names the fix %s (%s)" % [fix, code])
	t.check(LevelFixes.label({"fix": "hazard_setup", "type": "seesaw_stretch"}) == "ADD THE SEE-SAW"
		and LevelFixes.label({"fix": "hazard_setup", "type": "turret"}) == "DELETE", "hazard_setup's label follows the issue")
	t.check(LevelFixes.ops({}, LevelDoc.blank("x", 512.0, 0), null).is_empty(), "no issue: no ops")


func _close_loop() -> void:
	var d := LevelDoc.blank("Fix", 1024.0, 0)
	_oval(d)
	d.data.road.closed = false
	_fix(d, "open_loop", "an open road")
	t.check(bool(d.data.road.closed), "CLOSE LOOP closes it")


func _narrow() -> void:
	# a 30 m road through a hairpin of about 25 m radius (needs <= 2 x (R - 4 - 2))
	var d := LevelDoc.blank("Fix", 1024.0, 0)
	var hp := []
	for p in [[-150, -25], [-75, -25], [0, -25], [75, -25], [120, -18], [140, 0], [120, 18], [75, 25], [0, 25], [-75, 25], [-150, 25], [-210, 0]]:
		hp.append({"uid": d.new_uid(), "pos": [float(p[0]), 0.0, float(p[1])], "width": 30.0, "style": "asphalt"})
	d.data.road = {"closed": true, "start": {"p": hp[1].uid, "t": 0.0}, "points": hp}
	var b := _fix(d, "too_tight", "a 30 m road round a hairpin", func(x: Dictionary) -> bool: return float(x.pos.x) > 60.0)
	if b == null:
		return
	var narrowed := 0
	for p in d.data.road.points:
		if float(p.width) < 30.0:
			narrowed += 1
			t.check(float(p.width) >= LevelFixes.MIN_WIDTH, "a narrowed point keeps at least 6 m (%.1f)" % float(p.width))
	t.check(narrowed >= 2 and narrowed <= 6, "the points of the bend were narrowed (%d)" % narrowed)
	t.check(float(d.data.road.points[1].width) == 30.0, "the straight keeps its width")


func _crossing() -> void:
	var d := LevelDoc.blank("Fix", 1024.0, 0)
	CaseCompile.figure8(d, 0.0)
	var b := _fix(d, "crossing", "a flat figure eight")
	if b == null:
		return
	var raised := 0
	var bridges := 0
	for p in d.data.road.points:
		if float(p.pos[1]) > 6.9:
			raised += 1
		if str(p.style) == "bridge":
			bridges += 1
	t.check(raised >= 1, "MAKE A BRIDGE raised the stretch by 7 m (%d points)" % raised)
	t.check(bridges >= 2, "its segments are bridges (%d)" % bridges)


func _embankment() -> void:
	var v := LevelDoc.blank("Fix", 512.0, 257)
	var res := v.res()
	for z in res:
		for x in res:
			v.heights[z * res + x] = -25.0 if absf(v.origin().x + x * v.cell()) < 50.0 else 0.0
	_oval(v)
	_fix(v, "embankment", "a road over a 25 m valley")


func _grid() -> void:
	var g := LevelDoc.blank("Fix", 1024.0, 0)
	var pts := _oval(g)
	pts[19]["bank"] = 10.0
	pts[18]["bank"] = 10.0
	_fix(g, "grid", "an explicit bank behind the line")
	t.check(g.data.road.points[19].get("bank") == null and g.data.road.points[18].get("bank") == null, "the banks are AUTO again")
	var j := LevelDoc.blank("Fix", 1024.0, 0)
	var jp := _oval(j)
	jp[19]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	jp[10]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	_fix(j, "grid", "a jump behind the line")
	t.check(j.data.road.points[19].get("gap") == null and j.data.road.points[10].get("gap") is Dictionary,
		"only the jump in the grid went")


func _start_jump() -> void:
	var s := LevelDoc.blank("Fix", 1024.0, 0)
	var sp := _oval(s)
	sp[0]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	s.data.road.start = {"p": sp[0].uid, "t": 0.5}
	_fix(s, "start_jump", "the start on a jump")


func _steep() -> void:
	var hill := LevelDoc.blank("Fix", 1024.0, 0)
	var hp := _oval(hill, 200.0, 150.0, 24)
	hp[5].pos[1] = 30.0
	var b := _fix(hill, "steep", "a 30 m rise over 50 m")
	if b != null:
		t.check(not b.report.has("steep_warn"), "smoothed below the warning too (%s)" % str(_codes(b)))
	var soft := LevelDoc.blank("Fix", 1024.0, 0)
	var sp := _oval(soft, 200.0, 150.0, 24)
	sp[4].pos[1] = 8.0
	sp[5].pos[1] = 22.0
	sp[6].pos[1] = 8.0
	_fix(soft, "steep_warn", "a 22 m rise over three points")
	# the tool option: every point half way to its neighbours' average
	var fresh := LevelDoc.blank("Fix", 1024.0, 0)
	var fp := _oval(fresh, 200.0, 150.0, 24)
	fp[4].pos[1] = 8.0
	fp[5].pos[1] = 22.0
	fp[6].pos[1] = 8.0
	var all := LevelFixes.smooth_ops(fresh, -1, 0.5)
	t.check(all.size() >= 5 and all.size() <= 9, "SMOOTH HEIGHTS (0.5) moves the hill's points only (%d)" % all.size())


func _water() -> void:
	var s := LevelDoc.blank("Fix", 1024.0, 0)
	_oval(s)
	s.data.water = {"sea": true, "level": 5.0}
	_fix(s, "under_water", "a road under the sea")
	t.check(float(s.data.road.points[3].pos[1]) >= 6.5 - 1e-3, "raised to the sea + 1.5 m")
	var l := LevelDoc.blank("Fix", 1024.0, 0)
	_oval(l)
	l.data.lakes = [{"uid": l.new_uid(), "center": [180.0, 0.0], "size": [40.0, 60.0], "level": 3.0}]
	_fix(l, "under_water", "a road through a lake")
	var dry := 0
	for p in l.data.road.points:
		if absf(float(p.pos[1])) < 1e-3:
			dry += 1
	t.check(dry >= 14, "only the stretch at the lake was raised (%d points left alone)" % dry)


func _legal_spot() -> void:
	# a branch whose fork sits on an explicitly banked stretch of the right straight
	var d := LevelDoc.blank("Fix", 2048.0, 0)
	var pts := _stadium(d)
	for k in [2, 3]:
		pts[k]["bank"] = 6.0
	d.data.branches = [{"uid": 100, "name": "QUARRY", "kind": "alt", "fork": {"p": 3, "t": 0.5}, "merge": {"p": 7, "t": 0.5},
		"side": 0, "merge_side": 0,
		"points": [{"uid": 101, "pos": [235.0, 0.0, -50.0], "width": 10.0, "style": "asphalt"},
			{"uid": 102, "pos": [245.0, 0.0, 50.0], "width": 10.0, "style": "asphalt"},
			{"uid": 103, "pos": [235.0, 0.0, 150.0], "width": 10.0, "style": "asphalt"}],
		"ai": {"take": 0.5, "min_skill": 0.0, "commit": 40.0}, "risk": 0.0, "respawn": "before", "retry_back": 45.0,
		"offtrack": -1.0}]
	var before := JSON.stringify(d.data.branches[0].fork)
	var b := _fix(d, "branch_bank", "a fork on a banked stretch")
	if b == null:
		return
	t.check(JSON.stringify(d.data.branches[0].fork) != before and JSON.stringify(d.data.branches[0].merge).contains("7"),
		"MOVE TO A LEGAL SPOT moved the fork only (%s)" % JSON.stringify(d.data.branches[0].fork))
	var m := LevelFixes.road_of(b, -1)
	var flags: PackedByteArray = b.flags.get("branch_fork", PackedByteArray())
	if m != null and not flags.is_empty():
		var e := posmod(roundi(m.anchor_s(d.data.branches[0].fork) / (3.0 * m.step)), flags.size())
		t.check(flags[e] == 1, "the fork now sits on a legal sample")


func _hazard_setup() -> void:
	var d := LevelDoc.blank("Fix", 2048.0, 0)
	_stadium(d)
	d.data.road.points[3]["seesaw"] = true
	var b := _compile(d)
	var it := {}
	for x in b.report.all_of("hazard_setup"):
		if str(x.get("type", "")) == "seesaw_stretch":
			it = x
	t.check(not it.is_empty(), "a see-saw stretch without its see-saw: hazard_setup (%s)" % str(_codes(b)))
	if not it.is_empty():
		var h := EditHistory.new(d)
		h.commit("FIX: ADD THE SEE-SAW", LevelFixes.ops(it, d, b))
		var hz: Array = d.data.hazards
		t.check(hz.size() == 1 and str(hz[0].type) == "seesaw" and int(hz[0].at.p) == 4, "ADD THE SEE-SAW adds it on the stretch")
		var after := _compile(d)
		var left := 0
		for x in after.report.all_of("hazard_setup"):
			if str(x.get("type", "")) == "seesaw_stretch":
				left += 1
		t.check(left == 0, "the stretch has its see-saw now (%s)" % str(_codes(after)))
		h.undo()
		t.check((d.data.hazards as Array).is_empty(), "one undo takes it away")
	# a ceiling turret on an open road: DELETE
	var c := LevelDoc.blank("Fix", 2048.0, 0)
	_stadium(c)
	c.data.hazards = [{"uid": 150, "type": "turret", "at": {"p": 3, "t": 0.5}, "side": 0, "zone": null, "mount": "ceiling",
		"feel": "normal", "pts": [], "p": {}}]
	_fix(c, "hazard_setup", "a ceiling turret outside a tunnel")
	t.check((c.data.hazards as Array).is_empty(), "DELETE took the turret away")


func _items_and_props() -> void:
	var n := LevelDoc.blank("Fix", 1024.0, 0)
	_oval(n, 200.0, 140.0)
	_fix(n, "no_items", "a lap without crates")
	t.check(not (n.data.items as Array).is_empty(), "AUTO ITEMS added crate rows")
	var p := LevelDoc.blank("Fix", 1024.0, 0)
	_oval(p)
	p.data.props = [{"uid": 900, "model": "props_junk/wood_crate001a", "pos": [180.0, 0.0, 0.0], "yaw": 0.0, "scale": 1.0}]
	var ops := LevelFixes.ops({"code": "prop_on_road", "fix": "delete", "uid": 900}, p, null)
	t.check(ops.size() == 1 and str(ops[0][0]) == "remove", "DELETE removes the prop on the road")
	t.check(LevelFixes.ops({"code": "prop_on_road", "fix": "delete", "uid": 901}, p, null).is_empty(), "a uid that is gone: no ops")
