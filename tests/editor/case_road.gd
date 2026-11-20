extends RefCounted
## editor/case_road (P13, CI): the ROAD tool (1.6) in the editor scene with fabricated hits. An
## open road grows from the end it grew last, Shift + click from the end nearest the cursor (both
## ends; width and style from the neighbour); 8 clicks round an ellipse keep the click order and a
## click on the first point closes the loop; a click near its other end and C close it too; an undo
## keeps the growing end, OPEN LOOP and DRAW set it; a ground click on a closed loop adds
## nothing; a "+" dot dragged inserts one point (one undo step), Ctrl + click on the road inserts
## one; DRAW of a circle of samples makes a closed loop of about 40 m spacing (one undo step);
## FOLLOW GROUND keeps a point's offset over a hill, Shift + drag changes only the height; the
## drag readout's numbers (and red past the limit); barrier overrides write 2.5's dicts; reverse,
## delete (a closed loop keeps 3), jump, wheel width / bank, AUTO handle, open the loop, SET START
## LINE are undoable; hints for every hover case.

const NEEDS_CONTENT := false
const CaseSelect := preload("res://tests/editor/case_select.gd")

var t: Node


func run(tt: Node) -> void:
	t = tt
	await _extend_and_close()
	await _click_round()
	await _closed_loop()
	await _draw()
	await _follow_ground()
	await _readout()
	await _segment_fields()


# ---------------------------------------------------------------- helpers

func _open(doc: LevelDoc, h := 420.0, at := Vector3.ZERO) -> TrackEditor:
	var ed: TrackEditor = await CaseSelect.open_editor(t, doc)
	ed.set_tool("road")
	CaseSelect.look_down(ed, at, h)
	await t.frames(2)
	return ed


func _rt(ed: TrackEditor) -> RoadTool:
	return ed.tools["road"] as RoadTool


func _pts(ed: TrackEditor) -> Array:
	return ed.doc.data.road.points


func _pos(p: Dictionary) -> Vector3:
	return RoadTool._v3(p.pos)


func _json(doc: LevelDoc) -> String:
	var d: Dictionary = doc.data.duplicate(true)
	d.erase("next_uid")
	return JSON.stringify(d)


func _marker(ed: TrackEditor, kind: String, uid: int, p: Vector3, sub := 0) -> EditorHit:
	var h := CaseSelect.hit_at(ed, p, "marker", uid, kind)
	h.sub = sub
	return h


## A road hit on the bake's main road at sample i.
func _road_hit(ed: TrackEditor, i: int) -> EditorHit:
	var r := LevelFixes.road_of(ed.build, -1)
	var h := CaseSelect.hit_at(ed, r.pos[i], "road")
	h.road = -1
	h.sample = i
	h.s = r.s[i]
	return h


func _circle_doc(n := 8, r := 150.0, w := 14.0) -> LevelDoc:
	var doc := LevelDoc.blank("Road", 1024.0, 0)
	var pts := []
	for k in n:
		var a := TAU * k / n
		pts.append({"uid": doc.new_uid(), "pos": [r * cos(a), 1.0, r * sin(a)], "width": w, "style": "asphalt"})
	doc.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	return doc


# ---------------------------------------------------------------- open roads

func _extend_and_close() -> void:
	var doc := LevelDoc.blank("Road", 1024.0, 0)
	var a := {"uid": doc.new_uid(), "pos": [0.0, 0.0, 0.0], "width": 14.0, "style": "asphalt"}
	var b := {"uid": doc.new_uid(), "pos": [100.0, 0.0, 0.0], "width": 20.0, "style": "dirt"}
	doc.data.road = {"closed": false, "start": {"p": a.uid, "t": 0.0}, "points": [a, b]}
	var ed := await _open(doc)
	var rt := _rt(ed)
	var hs := rt.hints(CaseSelect.hit_at(ed, Vector3(180, 0, 50), "terrain"))
	t.check(str(hs).contains("EXTEND"), "hint on the ground of an open road: extend (%s)" % str(hs))
	# a road this session did not grow yet: the end nearest the cursor (B for x = 180)
	rt.click(CaseSelect.hit_at(ed, Vector3(180, 0, 60), "terrain"), 0)
	var pts := _pts(ed)
	t.check(pts.size() == 3 and _pos(pts[2]).distance_to(Vector3(180, 0, 60)) < 0.01, "a click extends from the nearer end (after B)")
	t.check(float(pts[2].width) == 20.0 and str(pts[2].style) == "dirt", "the new point takes its neighbour's width and style")
	# then the end it grew last, even for a spot nearer A; Shift: the nearer end
	t.check(rt.extend_end(Vector3(-80, 0, 70)) == 2, "the next click grows the end it grew last (%d)" % rt.extend_end(Vector3(-80, 0, 70)))
	t.check(rt.extend_end(Vector3(-80, 0, 70), true) == 0, "with Shift the end nearest the cursor (A)")
	t.check(str(rt.hints(CaseSelect.hit_at(ed, Vector3(-80, 0, 70), "terrain"))).contains("NEARER END"), "the hint names Shift + click")
	rt.click(CaseSelect.hit_at(ed, Vector3(-80, 0, 70), "terrain"), EditorTool.MOD_SHIFT)
	pts = _pts(ed)
	t.check(pts.size() == 4 and _pos(pts[0]).distance_to(Vector3(-80, 0, 70)) < 0.01 and int(pts[1].uid) == int(a.uid),
		"Shift + click near A extends before it")
	t.check(float(pts[0].width) == 14.0, "the prepended point takes A's width")
	t.check(ed.history.undo_name() == "ADD POINT", "each point is an undo step (%s)" % ed.history.undo_name())
	ed.history.undo()
	t.check(_pts(ed).size() == 3, "undo takes the prepended point away")
	ed.history.redo()
	# the CLOSE LOOP glow: within 12 px of the other end
	var last := _pos(_pts(ed)[3])
	var near := CaseSelect.hit_at(ed, last + Vector3(1.0, 0, 0), "terrain")
	t.check(rt.close_target(near) == int(_pts(ed)[3].uid), "the other end glows within 12 px")
	t.check(str(rt.hints(near)).contains("CLOSE LOOP"), "the hint reads CLICK CLOSE LOOP")
	t.check(rt.close_target(CaseSelect.hit_at(ed, last + Vector3(30.0, 0, 0), "terrain")) == 0, "30 m off: no glow")
	ed.draw.clear()
	ed.hover = CaseSelect.hit_at(ed, Vector3(300, 0, 100), "terrain")
	rt.overlay(ed.draw)
	t.check(_drawn(ed.draw) > 0, "the rubber band is drawn")
	rt.click(near, 0)
	t.check(bool(ed.doc.data.road.closed) and _pts(ed).size() == 4, "that click closes the loop (no point added)")
	ed.history.undo()
	t.check(not bool(ed.doc.data.road.closed), "undo opens it again")
	CaseSelect.key(ed, KEY_C)
	t.check(bool(ed.doc.data.road.closed), "C closes the loop")
	ed.history.undo()
	await CaseSelect.close_editor(t, ed)


## The critic's loop: 8 clicks round an ellipse (220 x 160 m), the 8th nearer the first point than
## the 7th, keep the click order; a click on the first point closes the loop (TrackEditor.click as
## the mouse does); after an undo the next click still grows the last end; OPEN LOOP lets the
## nearest end grow.
func _click_round() -> void:
	var ed := await _open(LevelDoc.blank("Road", 1024.0, 0), 700.0)
	var rt := _rt(ed)
	var ring: Array[Vector3] = []
	for k in 8:
		var an := TAU * k / 8.0
		ring.append(Vector3(220.0 * cos(an), 0.0, 160.0 * sin(an)))
	for p in ring:
		ed.click(CaseSelect.hit_at(ed, p, "terrain"), 0)
	var pts := _pts(ed)
	var order := []
	for q in pts:
		var best := 0
		for k in ring.size():
			if _pos(q).distance_to(ring[k]) < _pos(q).distance_to(ring[best]):
				best = k
		order.append(best)
	t.check(order == [0, 1, 2, 3, 4, 5, 6, 7], "8 clicks round an ellipse: the doc keeps the click order (%s)" % str(order))
	t.check(not bool(ed.doc.data.road.closed) and ed.selection.uids == PackedInt32Array([int(pts[7].uid)]),
		"the road is open, the last click selected")
	# the rubber band runs from the last click, also over the first point's side
	var spot := Vector3(200, 0, -30)
	t.check(rt.extend_end(spot) == 7, "the rubber band starts at the last click (%d)" % rt.extend_end(spot))
	ed.draw.clear()
	ed.hover = CaseSelect.hit_at(ed, spot, "terrain")
	rt.overlay(ed.draw)
	t.check(_drawn(ed.draw) > 0, "the rubber band is drawn")
	var first := _marker(ed, "road_point", int(pts[0].uid), ring[0])
	t.check(rt.close_target(first) == int(pts[0].uid), "the first point glows: CLOSE LOOP")
	t.check(str(rt.hints(first)).contains("CLICK CLOSE LOOP"), "its hint reads CLICK CLOSE LOOP (%s)" % str(rt.hints(first)))
	ed.click(first, 0)
	pts = _pts(ed)
	t.check(bool(ed.doc.data.road.closed) and pts.size() == 8, "a click on the first point closes the loop (%d points)" % pts.size())
	t.check(ed.history.undo_name() == "CLOSE LOOP", "one step: CLOSE LOOP (%s)" % ed.history.undo_name())
	ed.history.undo()
	# open again: a ground click nearer the first point still grows the last click's end
	ed.click(CaseSelect.hit_at(ed, spot, "terrain"), 0)
	pts = _pts(ed)
	t.check(pts.size() == 9 and _pos(pts[8]).distance_to(spot) < 0.01, "after the undo the click still grows the last end")
	ed.history.undo()
	t.check(rt.extend_end(spot) == 7, "an undone click: its end keeps growing (%d)" % rt.extend_end(spot))
	ed.history.redo()
	t.check(rt.extend_end(spot) == 8, "a redone click: the redone point grows (%d)" % rt.extend_end(spot))
	ed.history.undo()
	ed.click(_marker(ed, "road_point", int(_pts(ed)[0].uid), ring[0]), 0)
	t.check(bool(ed.doc.data.road.closed), "the first point closes it again")
	# OPEN LOOP: the next point first; no end grown, so the nearest end grows
	var o := int(_pts(ed)[3].uid)
	rt.open_loop_at(o)
	pts = _pts(ed)
	t.check(not bool(ed.doc.data.road.closed) and int(pts[-1].uid) == o, "OPEN LOOP at a segment")
	t.check(rt.extend_end(_pos(pts[0]) + Vector3(5, 0, 5)) == 0 and rt.extend_end(_pos(pts[-1]) + Vector3(5, 0, 5)) == 7,
		"after OPEN LOOP the end nearest the cursor grows")
	t.check(str(LevelValidate.TEXTS.open_loop).contains("two ends"), "the open_loop problem says either end closes it")
	await CaseSelect.close_editor(t, ed)


# ---------------------------------------------------------------- closed loops

func _closed_loop() -> void:
	var doc := _circle_doc()
	var ed := await _open(doc)
	var rt := _rt(ed)
	var n := _pts(ed).size()
	var u0 := int(_pts(ed)[0].uid)
	ed.select(PackedInt32Array([u0]))
	var hit := CaseSelect.hit_at(ed, Vector3(0, 0, 0), "terrain")
	t.check(str(rt.hints(hit)).contains("DESELECT"), "hint on the ground of a closed loop: deselect")
	t.check(rt.click(hit, 0), "a ground click on a closed loop is the road tool's")
	t.check(_pts(ed).size() == n and ed.selection.uids.is_empty(), "it adds nothing and deselects")
	# "+" dot drag: one new point, one undo step
	var before := _json(ed.doc)
	var mid := rt.curve_at(-1, 0, 0.5)
	t.check(rt.drag_begin(_marker(ed, "segment_mid", u0, mid, 5), 0), "a + dot drag begins")
	var to := mid + Vector3(12, 0, 8)
	rt.drag_move(CaseSelect.hit_at(ed, to, "terrain"), 0)
	rt.drag_end(CaseSelect.hit_at(ed, to, "terrain"), 0)
	var pts := _pts(ed)
	t.check(pts.size() == n + 1 and int(pts[0].uid) == u0, "the + drag inserted one point after its segment's owner")
	var g := SelectTool.grid_of(ed)
	var want := Vector3(snappedf(to.x, g), mid.y, snappedf(to.z, g)) if g > 0.0 else Vector3(to.x, mid.y, to.z)
	t.check(_pos(pts[1]).distance_to(want) < 0.01, "the new point followed the drag on the grid (%s, want %s)" % [str(_pos(pts[1])), str(want)])
	t.check(ed.history.undo_name() == "ADD POINT", "one step: ADD POINT (%s)" % ed.history.undo_name())
	ed.history.undo()
	t.check(_json(ed.doc) == before, "one undo takes it all back")
	# Ctrl + click on the road inserts at that spot (the bake's road: a preview may be newer)
	var r := LevelFixes.road_of(ed.build, -1)
	var i := r.seg_first[2] + 10
	rt.click(_road_hit(ed, i), EditorTool.MOD_CTRL)
	t.check(_pts(ed).size() == n + 1 and _pos(_pts(ed)[3]).distance_to(r.pos[i]) < 0.01, "Ctrl + click inserts a point on the road")
	ed.history.undo()
	# a click on the road selects its segment
	rt.click(_road_hit(ed, r.seg_first[4] + 5), 0)
	var owner := int(_pts(ed)[4].uid)
	t.check(rt.segment == owner and ed.selection.uids == PackedInt32Array([owner]), "a road click selects the segment (its owner)")
	var box := VBoxContainer.new()
	t.check(rt.inspect(ed.selection.uids, box) and _has_label(box, "BARRIER LEFT"), "the segment inspector")
	box.free()
	# J: a jump on the selected segment, undoable
	CaseSelect.key(ed, KEY_J)
	t.check(_pts(ed)[4].get("gap") == RoadTool.JUMP, "J puts a 12 m jump on the segment")
	ed.history.undo()
	t.check(_pts(ed)[4].get("gap") == null, "undo takes the jump away")
	# C opens the loop at the selected segment (asked first; the test answers)
	rt.ask_open = false
	var nxt := int(_pts(ed)[5].uid)
	CaseSelect.key(ed, KEY_C)
	t.check(not bool(ed.doc.data.road.closed) and int(_pts(ed)[0].uid) == nxt, "C opens the loop: the next point comes first")
	t.check(int(_pts(ed)[-1].uid) == owner and _pts(ed).size() == n, "the segment's owner is the open road's last point")
	ed.history.undo()
	t.check(bool(ed.doc.data.road.closed) and int(_pts(ed)[0].uid) == u0, "undo closes it as it was")
	# reverse
	var rev0 := _json(ed.doc)
	rt.reverse()
	t.check(_json(ed.doc) != rev0 and ed.history.undo_name() == "REVERSE TRACK DIRECTION", "REVERSE DIRECTION")
	ed.history.undo()
	t.check(_json(ed.doc) == rev0, "undo reverses it back")
	# delete: two points in one step; a closed loop keeps 3
	ed.select(PackedInt32Array([int(_pts(ed)[2].uid), int(_pts(ed)[5].uid)]))
	SelectTool.delete_selection(ed)
	t.check(_pts(ed).size() == n - 2, "Delete removes the two points")
	ed.history.undo()
	t.check(_pts(ed).size() == n and _json(ed.doc) == rev0, "one undo brings both back")
	var all := PackedInt32Array()
	for p in _pts(ed):
		all.append(int(p.uid))
	t.check(rt.point_delete_ops(ed.doc, all).size() > 0 and rt.refuse_delete(all), "deleting every point of a loop is refused")
	var tmp := LevelDoc.new()
	tmp.data = ed.doc.data.duplicate(true)
	tmp.apply(RoadTool.point_delete_ops(tmp, all))
	t.check((tmp.data.road.points as Array).size() == 3, "the delete ops keep 3 points of a closed loop")
	# wheel over a point: width and bank
	var hp := _marker(ed, "road_point", u0, _pos(_pts(ed)[0]))
	t.check(rt.wheel(hp, EditorTool.MOD_CTRL, 2), "Ctrl + wheel over a point")
	t.check(float(_pts(ed)[0].width) == 15.0, "width + 2 x 0.5 m")
	t.check(not rt.wheel(hp, 0, 1), "a plain wheel is the camera's")
	rt.wheel(hp, EditorTool.MOD_ALT, -3)
	t.check(_pts(ed)[0].get("bank") != null, "Alt + wheel: the bank leaves AUTO (%s)" % str(_pts(ed)[0].get("bank")))
	var b1 := float(_pts(ed)[0].get("bank", 0.0))
	rt.wheel(hp, EditorTool.MOD_ALT, 1)
	t.check(absf(float(_pts(ed)[0].get("bank", 0.0)) - b1 - 1.0) < 1e-3, "Alt + wheel: + 1 deg a notch")
	# a handle drag makes it CUSTOM, a double click AUTO again
	ed.select(PackedInt32Array([u0]))
	var h := rt.handle_of(-1, 0)
	var tip: Vector3 = _pos(_pts(ed)[0]) + (h[0] as Vector3) * float(h[2])
	t.check(rt.drag_begin(_marker(ed, "handle", u0, tip, 2), 0), "a handle drag begins")
	rt.drag_move(CaseSelect.hit_at(ed, tip + Vector3(10, 0, 0), "terrain"), 0)
	rt.drag_end(CaseSelect.hit_at(ed, tip + Vector3(10, 0, 0), "terrain"), 0)
	var hd = _pts(ed)[0].get("handle")
	t.check(hd is Dictionary and absf(float(hd["in"]) - float(h[1])) < 0.02 and float(hd.out) > float(h[2]),
		"the handle is CUSTOM: out longer, in kept (%s)" % str(hd))
	rt.double_click(_marker(ed, "road_point", u0, _pos(_pts(ed)[0])), 0)
	t.check(_pts(ed)[0].get("handle") == null, "a double click puts the handle back to AUTO")
	# SET START LINE then a click on the road
	rt.picking_start = true
	var st0 = ed.doc.data.road.start.duplicate()
	rt.click(_road_hit(ed, r.seg_first[3] + 7), 0)
	t.check(not rt.picking_start and int(ed.doc.data.road.start.p) == int(_pts(ed)[3].uid) and ed.doc.data.road.start != st0,
		"SET START LINE puts the start where the road was clicked")
	ed.history.undo()
	# hints of every hover case
	for c in [["road_point", 0], ["handle", 2], ["segment_mid", 5], ["start", 0]]:
		t.check(not rt.hints(_marker(ed, c[0], u0, Vector3.ZERO, c[1])).is_empty(), "a hint for a %s" % c[0])
	t.check(str(rt.hints(_road_hit(ed, 20))).contains("ADD A POINT"), "a hint on the road")
	await CaseSelect.close_editor(t, ed)


func _drawn(d: EditorDraw) -> int:
	var n := 0
	for v in d.vertex_count().values():
		n += int(v)
	return n


func _has_label(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _has_label(c, text):
			return true
	return false


# ---------------------------------------------------------------- DRAW

func _draw() -> void:
	var doc := LevelDoc.blank("Road", 1024.0, 0)
	var ed := await _open(doc, 520.0)
	var rt := _rt(ed)
	t.check(str(rt.hints(CaseSelect.hit_at(ed, Vector3(10, 0, 0), "terrain"))).contains("DRAW"), "no road yet: drag draws")
	var radius := 150.0
	var steps := 360
	var hits := []
	for k in steps + 1:
		var a := TAU * k / steps * 0.985
		hits.append(CaseSelect.hit_at(ed, Vector3(radius * cos(a), 0.0, radius * sin(a)), "terrain"))
	t.check(rt.drag_begin(hits[0], 0), "with no road a drag draws")
	for k in range(1, steps):
		rt.drag_move(hits[k], 0)
	t.check(rt.draw_pts.size() > 150 and rt.draw_pts.size() < 260, "a sample every 4 m of travel (%d)" % rt.draw_pts.size())
	rt.drag_end(hits[steps], 0)
	var pts := _pts(ed)
	t.check(bool(ed.doc.data.road.closed), "released near its start: a closed loop")
	var want := roundi(TAU * radius / RoadTool.DRAW_SPACING)
	t.check(absi(pts.size() - want) <= 2, "about 40 m apart: %d points (want %d)" % [pts.size(), want])
	var lo := INF
	var hi := 0.0
	for k in pts.size():
		var d := _pos(pts[k]).distance_to(_pos(pts[(k + 1) % pts.size()]))
		lo = minf(lo, d)
		hi = maxf(hi, d)
	t.check(lo > 28.0 and hi < 52.0, "spacing %.1f .. %.1f m" % [lo, hi])
	t.check(ed.history.undo_name() == "DRAW ROAD", "one undo step: DRAW ROAD")
	ed.history.undo()
	t.check(_pts(ed).is_empty(), "undo takes the drawn road away")
	# an open stroke stays open
	var line := []
	for k in 60:
		line.append(CaseSelect.hit_at(ed, Vector3(-150.0 + k * 5.0, 0.0, 40.0 * sin(k * 0.1)), "terrain"))
	rt.drag_begin(line[0], 0)
	for k in range(1, 59):
		rt.drag_move(line[k], 0)
	rt.drag_end(line[59], 0)
	t.check(not bool(ed.doc.data.road.closed) and _pts(ed).size() >= 6 and _pts(ed).size() <= 10,
		"an open stroke: an open road (%d points)" % _pts(ed).size())
	var n := _pts(ed).size()
	t.check(rt.extend_end(Vector3(-160, 0, 0)) == n - 1 and rt.extend_end(Vector3(-160, 0, 0), true) == 0,
		"the stroke's last point grows next (Shift: the nearer end)")
	t.check(RoadTool.douglas_peucker(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 1), Vector3(20, 0, 0)]), 3.0).size() == 2,
		"Douglas-Peucker drops a point 1 m off the line")
	await CaseSelect.close_editor(t, ed)


# ---------------------------------------------------------------- FOLLOW GROUND

func _follow_ground() -> void:
	var doc := LevelDoc.blank("Road", 512.0, 257)
	var res := doc.res()
	for z in res:
		for x in res:
			var wx := doc.origin().x + x * doc.cell()
			var wz := doc.origin().y + z * doc.cell()
			doc.heights[z * res + x] = 20.0 * exp(-(pow(wx - 100.0, 2.0) + wz * wz) / (2.0 * 40.0 * 40.0))
	var pts := []
	for p in [[-120.0, 0.0], [0.0, -60.0], [-60.0, 80.0]]:
		pts.append({"uid": doc.new_uid(), "pos": [p[0], 0.3, p[1]], "width": 14.0, "style": "asphalt", "follow": true})
	pts[1].pos[1] = 2.0   # 2 m over the ground
	doc.data.road = {"closed": false, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var ed := await _open(doc, 300.0)
	var rt := _rt(ed)
	var uid := int(pts[1].uid)
	var p0 := _pos(_pts(ed)[1])
	var g0 := rt.natural(p0.x, p0.z)
	t.check(not is_nan(g0) and absf(g0) < 0.5, "the point starts on the plain")
	t.check(rt.drag_begin(_marker(ed, "road_point", uid, p0), 0), "a point drag begins")
	var to := Vector3(100.0, p0.y, 0.0)
	rt.drag_move(CaseSelect.hit_at(ed, Vector3(50.0, p0.y, -30.0), "terrain"), 0)
	rt.drag_end(CaseSelect.hit_at(ed, to, "terrain"), 0)
	var p1 := _pos(_pts(ed)[1])
	var g1 := rt.natural(p1.x, p1.z)
	t.check(Vector2(p1.x, p1.z).distance_to(Vector2(100, 0)) < 1.01, "the point moved in the plane (%s)" % str(p1))
	t.check(g1 > 15.0 and absf((p1.y - g1) - (p0.y - g0)) < 0.05, "FOLLOW GROUND keeps the offset over the hill (%.2f over %.2f)" % [p1.y - g1, g1])
	t.check(ed.history.undo_name() == "MOVE POINT", "one undo step: MOVE POINT")
	t.check(ed.last_settle_ms > 0.0 or ed.settle_times.has("collision"), "the release settled the road")
	# Shift + drag: the height only, FOLLOW stays on
	var sc := ed.camera.unproject_position(p1)
	var press := _marker(ed, "road_point", uid, p1)
	rt.drag_begin(press, EditorTool.MOD_SHIFT)
	var up := EditorHit.new()
	up.screen = sc + Vector2(0, -40)
	up.ray_from = ed.camera.project_ray_origin(up.screen)
	up.ray_dir = ed.camera.project_ray_normal(up.screen)
	rt.drag_end(up, EditorTool.MOD_SHIFT)
	var p2 := _pos(_pts(ed)[1])
	t.check(p2.y > p1.y + 1.0 and Vector2(p2.x, p2.z).distance_to(Vector2(p1.x, p1.z)) < 0.01, "Shift + drag lifts it in place (%.1f -> %.1f)" % [p1.y, p2.y])
	t.check(bool(_pts(ed)[1].get("follow", false)), "FOLLOW stays on")
	# a click on the terrain makes a FOLLOW point 0.3 m over the ground
	var gp := Vector3(40.0, 0.0, 120.0)
	rt.click(CaseSelect.hit_at(ed, Vector3(gp.x, rt.natural(gp.x, gp.z), gp.z), "terrain"), 0)
	var np: Dictionary = _pts(ed)[-1] if _pos(_pts(ed)[-1]).distance_to(gp) < 30.0 else _pts(ed)[0]
	t.check(bool(np.get("follow", false)) and absf(_pos(np).y - rt.natural(gp.x, gp.z) - 0.3) < 0.01, "a point made on terrain: FOLLOW on, 0.3 m up")
	# DRAPE ON TERRAIN
	rt.drape()
	var ok := true
	for p in _pts(ed):
		ok = ok and absf(_pos(p).y - rt.natural(_pos(p).x, _pos(p).z) - 0.3) < 0.01
	t.check(ok and ed.history.undo_name() == "DRAPE ON TERRAIN", "DRAPE ON TERRAIN puts every point 0.3 m over the ground")
	await CaseSelect.close_editor(t, ed)


# ---------------------------------------------------------------- readouts

func _readout() -> void:
	var ed := await _open(_circle_doc())
	var rt := _rt(ed)
	var uid := int(_pts(ed)[2].uid)
	var p0 := _pos(_pts(ed)[2])
	rt.drag_begin(_marker(ed, "road_point", uid, p0), 0)
	rt.drag_move(CaseSelect.hit_at(ed, p0 + Vector3(2, 0, 0), "terrain"), 0)
	var ro := rt.readout
	t.check(not ro.is_empty(), "a readout while dragging")
	if not ro.is_empty():
		t.check(float(ro.r) > 100.0 and float(ro.r) < 230.0, "R of an 8-point circle of 150 m (%.1f)" % float(ro.r))
		t.check(float(ro.width) == 14.0 and absf(float(ro.seg) - TAU * 150.0 / 8.0) < 12.0, "14 m wide, a segment of about 118 m (%.1f)" % float(ro.seg))
		t.check(float(ro.grade) < 0.02 and not ro.r_bad and not ro.grade_bad, "level and wide enough: nothing red")
		t.check(str(ro.text).contains("14 m WIDE") and str(ro.text).contains("GRADE 0 %") and str(ro.text).contains("SEGMENT"),
			"the label's words (%s)" % str(ro.text))
	rt.drag_end(CaseSelect.hit_at(ed, p0 + Vector3(2, 0, 0), "terrain"), 0)
	t.check(rt.readout.is_empty(), "the readout goes at the release")
	await CaseSelect.close_editor(t, ed)
	# a 30 m road round a hairpin: R red; a point 30 m up a 75 m segment: GRADE red
	var hp := LevelDoc.blank("Road", 1024.0, 0)
	var hpts := []
	for q in [[-150, -25], [-75, -25], [0, -25], [75, -25], [120, -18], [140, 0], [120, 18], [75, 25], [0, 25], [-75, 25], [-150, 25], [-210, 0]]:
		hpts.append({"uid": hp.new_uid(), "pos": [float(q[0]), 0.0, float(q[1])], "width": 30.0, "style": "asphalt"})
	hpts[1].pos[1] = 30.0
	hp.data.road = {"closed": true, "start": {"p": hpts[2].uid, "t": 0.0}, "points": hpts}
	var ed2 := await _open(hp, 400.0)
	var rt2 := _rt(ed2)
	for c in [[5, "r_bad"], [1, "grade_bad"]]:
		var u2 := int(_pts(ed2)[c[0]].uid)
		var q0 := _pos(_pts(ed2)[c[0]])
		rt2.drag_begin(_marker(ed2, "road_point", u2, q0), 0)
		rt2.drag_move(CaseSelect.hit_at(ed2, q0 + Vector3(0.2, 0, 0), "terrain"), 0)
		var r2 := rt2.readout
		t.check(not r2.is_empty() and bool(r2.get(c[1], false)) and str(r2.text).contains("[color=#"),
			"%s: red past the limit (%s)" % [c[1], str(r2.get("text", ""))])
		rt2.drag_end(CaseSelect.hit_at(ed2, q0 + Vector3(0.2, 0, 0), "terrain"), 0)
	await CaseSelect.close_editor(t, ed2)


# ---------------------------------------------------------------- segment fields

func _segment_fields() -> void:
	var ed := await _open(_circle_doc())
	var rt := _rt(ed)
	var uid := int(_pts(ed)[1].uid)
	rt.set_barrier(-1, uid, "barrier_l", "rail", 0.0)
	t.check(_pts(ed)[1].get("barrier_l") == LevelStyles.BARRIERS.rail, "BARRIER LEFT RAIL writes the RAIL dict")
	rt.set_barrier(-1, uid, "barrier_r", "none", 0.0)
	t.check(_pts(ed)[1].get("barrier_r") == {"kind": "none"}, "BARRIER RIGHT NONE writes {kind: none}")
	rt.set_barrier(-1, uid, "barrier_l", "wall", 2.0)
	var w = _pts(ed)[1].get("barrier_l")
	t.check(w is Dictionary and str(w.kind) == "wall" and float(w.h) == 2.0 and float(w.col_h) == 2.5 and float(w.thick) == 0.5,
		"WALL with HEIGHT 2: h 2, col_h 2.5 (%s)" % str(w))
	rt.set_barrier(-1, uid, "barrier_l", "jersey", 3.0)
	w = _pts(ed)[1].get("barrier_l")
	t.check(w is Dictionary and str(w.kind) == "jersey" and float(w.h) == 3.0 and float(w.col_h) == 3.0, "JERSEY with HEIGHT 3: col_h 3")
	rt.set_barrier(-1, uid, "barrier_l", "style", 0.0)
	t.check(_pts(ed)[1].get("barrier_l") == null, "STYLE takes the override away")
	ed.history.undo()
	t.check(_pts(ed)[1].get("barrier_l") is Dictionary, "undo brings the override back")
	# the style editor: COPY STYLE makes an own style; its fields change, a preset's do not
	var se := StyleEditor.new(ed)
	var nid := se.copy_style("asphalt")
	t.check(nid != "" and ed.doc.data.styles.has(nid) and str(ed.doc.data.styles[nid].kind) == "open"
		and str(ed.doc.data.styles[nid].road) == "concrete/concretefloor037b", "COPY STYLE copies a preset (%s)" % nid)
	t.check(nid in LevelStyles.ids(ed.doc.data) and se.current == nid, "the copy is listed and shown")
	se.set_field("lines", true)
	se.set_field("grip", "offroad")
	se.set_field("name", "MY ROAD")
	t.check(bool(ed.doc.data.styles[nid].lines) and str(ed.doc.data.styles[nid].grip) == "offroad"
		and str(ed.doc.data.styles[nid].name) == "MY ROAD", "CENTRE LINES, GRIP and NAME of an own style")
	se.current = "asphalt"
	se.set_field("lines", true)
	t.check(not LevelStyles.resolve(ed.doc.data, {}).asphalt.lines, "a preset cannot be changed")
	t.check(se.new_id("asphalt") != nid, "a new copy gets a new id")
	se.free()
	# the see-saw stretch toggle adds its see-saw (one step) where the segment is legal
	var straight := LevelDoc.blank("Road", 2048.0, 0)
	var sp := []
	for p in [[0, -600], [0, -300], [0, 0], [0, 300], [0, 600], [600, 600], [600, -600]]:
		sp.append({"uid": straight.new_uid(), "pos": [float(p[0]), 0.0, float(p[1])], "width": 14.0, "style": "asphalt"})
	straight.data.road = {"closed": true, "start": {"p": sp[5].uid, "t": 0.0}, "points": sp}
	await CaseSelect.close_editor(t, ed)
	var ed2 := await _open(straight, 900.0)
	var rt2 := _rt(ed2)
	var su := int(sp[1].uid)
	t.check(rt2.seesaw_legal(su), "a long level straight may be a see-saw stretch")
	rt2.set_seesaw(su, true)
	t.check(bool(_pts(ed2)[1].get("seesaw", false)) and (ed2.doc.data.hazards as Array).size() == 1, "the toggle adds the stretch and its see-saw")
	ed2.history.undo()
	t.check(not bool(_pts(ed2)[1].get("seesaw", false)) and (ed2.doc.data.hazards as Array).is_empty(), "one undo takes both away")
	rt2.toggle_jump(su)
	t.check(rt2.jump_need(-1, su) > 15.0 and rt2.jump_need(-1, su) < 31.0, "a default jump: every kart makes it (%.1f m/s)" % rt2.jump_need(-1, su))
	await CaseSelect.close_editor(t, ed2)
