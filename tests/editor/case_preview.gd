extends RefCounted
## editor/case_preview (P7, CI, fake registries): the drag budget (C1 M5, 3.11). The editor scene
## opens on a 4 km loop over MEDIUM terrain with the session's bake (shown at once, no compile);
## dragging a point rebuilds 1-3 segment groups in <= 12 ms a frame (commit + preview_segments +
## the group swap) and leaves every other road node alone; settle (gesture end: the groups'
## collision, the local re-carve, the chunks) takes <= 40 ms and puts the ground under the moved
## road; road() and road_hit read the preview while it is newer than the bake.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}

## The budgets of 3.11 are this PC's; a CI runner gets three times as long.
var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0


func run(t: Node) -> void:
	var doc := LevelDoc.blank("Preview", 2048.0, 513)
	var pts := []
	for k in 64:
		var ang := TAU * k / 64
		pts.append({"uid": doc.new_uid(), "pos": [640.0 * cos(ang), 6.0 * sin(ang * 3.0), 640.0 * sin(ang)], "width": 14.0, "style": "asphalt"})
	doc.data["road"] = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG, "flags": true})
	t.near(b.roads[0].length, 4021.0, 30.0, "a 4 km loop")
	var s := EditorSession.current()
	var keep_doc := s.doc
	s._take(doc)
	s.build = b
	var t0 := Time.get_ticks_usec()
	var ed: TrackEditor = load("res://scenes/editor.tscn").instantiate()
	t.get_tree().root.add_child(ed)
	var open_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.check(ed.build == b and ed.card == "" and ed._bake_started == -1, "the session's bake is shown at once, nothing compiled (%.0f ms)" % open_ms)
	ed.view.flush()
	var before := {}
	for nm in ed.view.mesh_nodes():
		before[nm] = (ed.view.mesh_nodes()[nm] as Node).get_instance_id()
	t.check(before.size() > 8, "the bake's road buckets are up (%d)" % before.size())
	var uid: int = pts[33].uid
	var path := ["road", "points", "#%d" % uid, "pos"]
	var p0: Array = (pts[33].pos as Array).duplicate()
	var best := INF
	var frames := []
	for k in 8:
		var moved := p0.duplicate()
		moved[0] = float(p0[0]) + 5.0 * (k + 1) * cos(TAU * 33 / 64)
		moved[2] = float(p0[2]) + 5.0 * (k + 1) * sin(TAU * 33 / 64)
		var ms: float = t.ms(func() -> void:
			ed.commit("MOVE POINT", [LevelDoc.op_set(path, moved)], "drag")
			ed.preview_roads(-1, PackedInt32Array([uid])))
		frames.append(snappedf(ms, 0.01))
		best = minf(best, ms)
	var groups: PackedStringArray = ed.preview.stats.get("groups", PackedStringArray())
	t.log("drag frames on a 4 km loop: %s ms (best %.2f; preview_segments %.2f, groups %s)" % [str(frames), best,
		float(ed.preview.stats.get("compile_ms", 0.0)), str(groups)])
	t.check(groups.size() >= 1 and groups.size() <= 3, "a drag rebuilds 1-3 groups (%d)" % groups.size())
	t.check(best <= 12.0 * slack, "a drag frame (commit + preview + group swap) <= 12 ms (%.2f ms)" % best)
	var swapped := 0
	var kept := true
	var gset := {}
	for g in groups:
		gset[g] = true
	for nm in ed.view.mesh_nodes():
		var mi: MeshInstance3D = ed.view.mesh_nodes()[nm]
		var in_group := int(mi.get_meta("level_road", -2)) == -1 and gset.has(str(mi.get_meta("level_group", "")))
		if in_group:
			swapped += 1
			kept = kept and mi.has_meta("preview") and mi.has_meta("no_collision") and mi.get_child_count() == 0
		else:
			kept = kept and before.get(nm, 0) == mi.get_instance_id()
	t.check(swapped > 0 and kept, "only the dragged groups' nodes were swapped, without collision (%d)" % swapped)
	var pr := ed.road(-1)
	t.check(pr != null and pr.partial and pr == ed.preview.roads[0], "road(-1) is the preview while it is newer than the bake")
	# the ray hit on the moved road (analytic, on the partial road)
	var q := Vector3(p0[0], p0[1], p0[2]) + Vector3(cos(TAU * 33 / 64), 0, sin(TAU * 33 / 64)) * 40.0
	var cam := ed.camera
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), q + Vector3(0, 120, 0))
	await t.frames(1)
	var hit := ed.road_hit(cam.unproject_position(q))
	t.check(hit.hit and hit.road == -1 and absf(hit.lat) < 7.5, "road_hit finds the moved road under the cursor (%s, lat %.1f)" % [hit.what, hit.lat])
	# gesture end
	var first: float = t.ms(func() -> void: ed.settle(-1, PackedInt32Array([uid])))
	var first_times := ed.settle_times.duplicate()
	var again: float = t.ms(func() -> void: ed.settle(-1, PackedInt32Array([uid])))
	t.log("settle: %.2f ms (%s); again (collision already in) %.2f ms" % [first, str(first_times), again])
	t.check(first <= 40.0 * slack, "settle (collision of the groups + local carve + chunks) <= 40 ms (%.2f ms)" % first)
	var bodies := 0
	for nm in ed.view.mesh_nodes():
		var mi: MeshInstance3D = ed.view.mesh_nodes()[nm]
		if mi.has_meta("preview") and int(mi.get_meta("level_road", -2)) == -1:
			for c in mi.get_children():
				if c is StaticBody3D:
					bodies += 1
	t.check(bodies > 0, "the changed groups have their collision after settle (%d bodies)" % bodies)
	var tr := ed.terrain()
	var i := pr.closest(q)
	var under := tr.height_at(pr.pos[i].x, pr.pos[i].z)
	t.check(absf(under - (pr.pos[i].y - 0.35)) < 0.4, "the ground under the moved road is its bed after settle (%.2f vs road %.2f)" % [under, pr.pos[i].y])
	var old_i := b.roads[0].closest(Vector3(p0[0], p0[1], p0[2]))
	var old_p := b.roads[0].pos[old_i]
	t.check(tr.height_at(old_p.x, old_p.z) > old_p.y - 0.3 or absf(old_p.y) < 0.5, "the old spot is no longer carved as a bed")
	t.check(ed.view.counts.get("preview", 0) > 0 and ed._bake_t > 0.0, "a background bake is due after settle")
	_input_case(t, ed)
	ed.queue_free()
	await t.frames(1)
	s.close()
	if keep_doc != null:
		t.log("a session doc was open before the case (closed)")


## The input routing (1.5, C2 M2) with a recording tool: a press that moves <= 4 px is a click, more
## is a drag (begin, moves, end, no click); a double click goes to double_click only; the wheel and
## keys reach the tool first.
func _input_case(t: Node, ed: TrackEditor) -> void:
	var rec := Recorder.new(ed)
	ed.tools["road"] = rec
	ed.tool = rec
	var at := ed.free_center()
	_button(ed, at, true)
	_motion(ed, at + Vector2(3, 0))
	_button(ed, at + Vector2(3, 0), false)
	t.check(rec.calls == ["click"], "a press moved 3 px is a click (%s)" % str(rec.calls))
	rec.calls.clear()
	_button(ed, at, true)
	_motion(ed, at + Vector2(2, 2))
	_motion(ed, at + Vector2(9, 0))
	_motion(ed, at + Vector2(20, 0))
	_button(ed, at + Vector2(20, 0), false)
	t.check(rec.calls == ["drag_begin", "drag_move", "drag_move", "drag_end"], "past 4 px it is a drag, never a click (%s)" % str(rec.calls))
	rec.calls.clear()
	_button(ed, at, true, true)
	_button(ed, at, false)
	t.check(rec.calls == ["double"], "a double click goes to double_click only (%s)" % str(rec.calls))
	rec.calls.clear()
	var wh := InputEventMouseButton.new()
	wh.button_index = MOUSE_BUTTON_WHEEL_UP
	wh.pressed = true
	wh.position = at
	ed._unhandled_input(wh)
	var k := InputEventKey.new()
	k.keycode = KEY_J
	k.pressed = true
	ed._unhandled_input(k)
	t.check(rec.calls == ["wheel 1", "key"], "the wheel and keys reach the tool first (%s)" % str(rec.calls))
	t.check(rec.mods == EditorTool.MOD_SHIFT, "modifiers reach the tool as MOD_* bits")


func _button(ed: TrackEditor, at: Vector2, down: bool, double := false) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.double_click = double
	b.position = at
	b.shift_pressed = true
	ed._unhandled_input(b)


func _motion(ed: TrackEditor, at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.shift_pressed = true
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	ed._unhandled_input(m)


class Recorder:
	extends EditorTool
	var calls: Array = []
	var mods := 0

	func _init(ed: TrackEditor) -> void:
		super(ed)
		id = "road"

	func click(_hit: EditorHit, m: int) -> bool:
		calls.append("click")
		mods = m
		return true

	func double_click(_hit: EditorHit, _m: int) -> bool:
		calls.append("double")
		return true

	func drag_begin(_hit: EditorHit, _m: int) -> bool:
		calls.append("drag_begin")
		return true

	func drag_move(_hit: EditorHit, _m: int) -> void:
		calls.append("drag_move")

	func drag_end(_hit: EditorHit, _m: int) -> void:
		calls.append("drag_end")

	func wheel(_hit: EditorHit, _m: int, notches: int) -> bool:
		calls.append("wheel %d" % notches)
		return true

	func key(_ev: InputEvent) -> bool:
		calls.append("key")
		return true
