extends RefCounted
## editor/case_branch_tool (P13, CI): the BRANCH tool (1.6) in the editor scene with fabricated
## hits on a stadium loop. The legal tint is drawn from build.flags; a fork click on red (near the
## start line) is refused with a reason and starts nothing; a click on green snaps the FORK to a
## green exported sample; the three steps (fork, points on the ground, merge on green, Enter) make
## one branch in one undo step; a merge on red is refused; the fork marker slides along the road
## on green; the branch inspector; Delete on the branch removes it (undoable).

const NEEDS_CONTENT := false
const CaseSelect := preload("res://tests/editor/case_select.gd")

var t: Node


func run(tt: Node) -> void:
	t = tt
	var doc := _stadium()
	var ed: TrackEditor = await CaseSelect.open_editor(t, doc)
	ed.set_tool("branch")
	CaseSelect.look_down(ed, Vector3(200, 0, 0), 600.0)
	await t.frames(2)
	var bt := ed.tools["branch"] as BranchTool
	var m := ed.road(-1)
	var flags := ed.flags("branch_fork")
	t.check(m != null and not flags.is_empty(), "the bake has the main road and the fork flags")
	if m == null or flags.is_empty():
		await CaseSelect.close_editor(t, ed)
		return
	# the tint
	ed.draw.clear()
	bt.overlay(ed.draw)
	t.check(int(ed.draw.vertex_count().tris) > 0, "the legal-spot tint is drawn on the road")
	t.check(bt.step() == 1 and bt.status_step() == "Click the road where the branch leaves", "step 1's line")
	# red: right after the start line
	var red := _road_hit(ed, m.idx(6.0))
	t.check(not bt.legal_at("fork", red.s), "the start line is red for a fork")
	t.check(str(bt.hints(red)).contains("NO FORK"), "the hint says no fork there")
	bt.click(red, 0)
	t.check(bt.draft.is_empty() and bt.refusal != "" and bt.status_step() == bt.refusal, "a fork on red is refused with a reason (%s)" % bt.refusal)
	# green: the right straight, a spot between exported samples
	var i_fork := m.closest(Vector3(200, 0, -250)) + 1
	var green := _road_hit(ed, i_fork)
	t.check(bt.legal_at("fork", green.s), "the right straight is green")
	bt.click(green, 0)
	t.check(bt.step() == 2 and bt.draft.fork is Dictionary, "a fork on green: step 2")
	if bt.draft.is_empty():
		await CaseSelect.close_editor(t, ed)
		return
	var fs := m.anchor_s(bt.draft.fork)
	var e := posmod(roundi(fs / (3.0 * m.step)), flags.size())
	t.check(absf(fs - green.s) <= 3.0 * m.step + 0.01 and flags[e] == 1 and absf(fs - m.s[e * 3]) < 0.5,
		"the fork snapped to a green exported sample (%.1f -> %.1f)" % [green.s, fs])
	t.check(bt.status_step().begins_with("Click the ground"), "step 2's line")
	# step 2: points on the ground, then the merge
	for p in [Vector3(235, 0, -150), Vector3(245, 0, 0), Vector3(235, 0, 150)]:
		bt.click(CaseSelect.hit_at(ed, p, "terrain"), 0)
	t.check((bt.draft.points as Array).size() == 3, "three points laid out")
	var red_merge := _road_hit(ed, m.idx(m.length - 4.0))
	bt.click(red_merge, 0)
	t.check(bt.step() == 2 and bt.refusal != "", "a merge on red is refused (%s)" % bt.refusal)
	var i_merge := m.closest(Vector3(200, 0, 250))
	bt.click(_road_hit(ed, i_merge), 0)
	t.check(bt.step() == 3 and bt.draft.merge is Dictionary, "the merge on green: step 3")
	t.check(bt.status_step().contains("to finish"), "step 3's line")
	var n0 := (ed.doc.data.branches as Array).size()
	var steps0 := ed.history.undo_name()
	CaseSelect.key(ed, KEY_ENTER)
	var brs: Array = ed.doc.data.branches
	t.check(brs.size() == n0 + 1 and bt.draft.is_empty(), "Enter finishes: one branch")
	if brs.size() == n0 + 1:
		var b: Dictionary = brs[-1]
		t.check((b.points as Array).size() == 3 and b.fork is Dictionary and b.merge is Dictionary and str(b.kind) == "alt",
			"the branch has its fork, merge and three points")
		t.check(ed.history.undo_name() == "ADD BRANCH", "one undo step: ADD BRANCH")
		var buid := int(b.uid)
		var box := VBoxContainer.new()
		t.check(bt.inspect(PackedInt32Array([buid]), box) and box.get_child_count() > 6, "the branch inspector")
		box.free()
		# slide the fork marker along the road: it stays on green
		var fork0 := JSON.stringify(b.fork)
		var fork_pos := m.pos[m.idx(m.anchor_s(b.fork))]
		var hit := CaseSelect.hit_at(ed, fork_pos, "marker", buid, "branch")
		hit.sub = BranchTool.SUB_FORK
		t.check(bt.drag_begin(hit, 0), "the fork marker drags")
		var to := _road_hit(ed, i_fork - 25)
		bt.drag_move(to, 0)
		bt.drag_end(to, 0)
		var f2 = (ed.doc.data.branches[-1] as Dictionary).fork
		var e2 := posmod(roundi(m.anchor_s(f2) / (3.0 * m.step)), flags.size())
		t.check(absf(m.anchor_s(f2) - to.s) < 7.0 and flags[e2] == 1, "the fork slid to the green sample by the cursor")
		ed.history.undo()
		t.check(JSON.stringify((ed.doc.data.branches[-1] as Dictionary).fork) == fork0, "undo puts the fork back")
		# Delete on the branch
		ed.select(PackedInt32Array([buid]))
		SelectTool.delete_selection(ed)
		t.check((ed.doc.data.branches as Array).size() == n0, "Delete removes the branch")
		ed.history.undo()
		t.check((ed.doc.data.branches as Array).size() == n0 + 1, "undo brings it back")
		ed.history.undo()
		t.check((ed.doc.data.branches as Array).size() == n0 and ed.history.undo_name() == steps0, "undo ADD BRANCH: no branch")
	# Esc cancels a branch being made
	bt.click(green, 0)
	t.check(bt.step() == 2, "a new fork")
	CaseSelect.key(ed, KEY_ESCAPE)
	t.check(bt.draft.is_empty(), "Esc cancels it")
	await CaseSelect.close_editor(t, ed)


## A stadium loop (no terrain): the right straight x = +200 from z = -400 to +400 (100 m between
## points, driven toward +z), the arcs, the left straight; the start on the top arc.
func _stadium() -> LevelDoc:
	var doc := LevelDoc.blank("Branch", 2048.0, 0)
	var raw := []
	var r := 200.0
	for k in 9:
		raw.append(Vector3(r, 0.0, -400.0 + 100.0 * k))
	var arc := 7
	for k in arc:
		var a := PI * (k + 1) / (arc + 1)
		raw.append(Vector3(r * cos(a), 0.0, 400.0 + r * sin(a)))
	for k in 9:
		raw.append(Vector3(-r, 0.0, 400.0 - 100.0 * k))
	for k in arc:
		var a := PI + PI * (k + 1) / (arc + 1)
		raw.append(Vector3(r * cos(a), 0.0, -400.0 + r * sin(a)))
	var pts := []
	for p in raw:
		pts.append({"uid": doc.new_uid(), "pos": [p.x, p.y, p.z], "width": 14.0, "style": "asphalt"})
	doc.data.road = {"closed": true, "start": {"p": pts[12].uid, "t": 0.0}, "points": pts}
	return doc


func _road_hit(ed: TrackEditor, i: int) -> EditorHit:
	var r := ed.road(-1)
	var h := CaseSelect.hit_at(ed, r.pos[i], "road")
	h.road = -1
	h.sample = i
	h.s = r.s[i]
	return h
