extends RefCounted
## editor/case_press (review fixes, CI, fake registries): a held press is protected (1.6). Ctrl+Z
## with the button held in a TERRAIN or PAINT stroke does nothing, and undoing every step after it
## brings the start's ground back; Esc in a SELECT box drag ends the drag (no EDITOR MENU) and a
## bake follows the next edit; Esc in a move takes it back (no redo); Delete and the tool keys wait
## for the release; Esc mid gizmo Alt-duplicate takes the copies back; a LAKE drag or a BRANCH end
## drag cut short leaves no undo gesture open. A text field lets go on a click in the view, on
## Enter (the OUTLINER search) and on Esc. SAVE AS keeps the original file and writes a copy with
## the given name and a new guid; Ctrl+Shift+S asks for the name first.

const NEEDS_CONTENT := false
const S := preload("res://tests/editor/case_select.gd")


func run(t: Node) -> void:
	var doc := S.test_doc()
	var lake_uid := doc.new_uid()
	doc.data["lakes"] = [{"uid": lake_uid, "center": [100.0, -100.0], "size": [60.0, 40.0], "level": 2.0}]
	var ed: TrackEditor = await S.open_editor(t, doc)
	S.look_down(ed, Vector3.ZERO, 300.0)
	await t.frames(2)
	var u := S.uids_of(doc)
	ed.history.merge_window = -1.0
	_terrain_undo(t, ed)
	_paint_undo(t, ed)
	await _box_esc(t, ed, u)
	_move_esc(t, ed, u)
	_gizmo_esc(t, ed, u)
	_lake(t, ed, u, lake_uid)
	_branch(t, ed, u)
	await _focus(t, ed)
	await _first_save(t, ed)
	await _save_as(t, ed)
	ed.history.merge_window = 1.0
	await S.close_editor(t, ed)


## A press already turned into a tool drag (what _drag_motion leaves after drag_begin).
static func pressed(ed: TrackEditor, hit: EditorHit) -> void:
	ed._press = {"pos": hit.screen, "mods": 0, "hit": hit, "drag": true, "double": false}
	ed._dragging = "tool"


func _terrain_undo(t: Node, ed: TrackEditor) -> void:
	ed.set_tool("terrain")
	var tt: TerrainTool = ed.tools.terrain
	tt.throttle = 0.0
	tt.set_brush("raise")
	tt.size = 12.0
	tt.strength = 0.5
	tt.follow = false
	var n0 := ed.history.position()
	var h0 := ed.doc.heights.duplicate()
	tt.stroke_begin(Vector2(-100, 100), 0)
	tt.stroke_to(Vector2(-90, 100))
	tt.stroke_end()
	t.check(ed.history.position() == n0 + 1, "TERRAIN: stroke 1 is a step (%s)" % ed.history.undo_name())
	# stroke 2 over the same ground; Ctrl+Z while the button is held
	var hit := S.hit_at(ed, Vector3(-100, 0, 100))
	tt.stroke_begin(Vector2(-100, 100), 0)
	pressed(ed, hit)
	tt.stroke_to(Vector2(-95, 100))
	S.key(ed, KEY_Z, true)
	t.check(ed.history.position() == n0 + 1 and not ed.history.can_redo(), "Ctrl+Z with the button held in a stroke does nothing")
	tt.stroke_to(Vector2(-90, 100))
	S.button(ed, hit.screen, false)
	t.check(ed._press.is_empty() and ed._dragging == "" and ed.history.position() == n0 + 2,
		"the release ends the stroke: its own step (%d steps)" % (ed.history.position() - n0))
	while ed.history.position() > n0:
		ed.history.undo()
	var diff := 0.0
	for i in h0.size():
		diff = maxf(diff, absf(ed.doc.heights[i] - h0[i]))
	t.check(diff < 1e-5, "after undoing every step the ground is the start's (max diff %.3f m)" % diff)
	# Esc in a stroke takes it back
	tt.stroke_begin(Vector2(-100, 100), 0)
	pressed(ed, hit)
	tt.stroke_to(Vector2(-90, 100))
	S.key(ed, KEY_ESCAPE)
	diff = 0.0
	for i in h0.size():
		diff = maxf(diff, absf(ed.doc.heights[i] - h0[i]))
	t.check(ed._press.is_empty() and tt._stroke.is_empty() and diff < 1e-5 and ed.history.position() == n0,
		"Esc in a stroke takes it back (max diff %.3f m)" % diff)
	ed.history.clear()


func _paint_undo(t: Node, ed: TrackEditor) -> void:
	ed.set_tool("paint")
	var pt: PaintTool = ed.tools.paint
	pt.throttle = 0.0
	var s0 := ed.doc.splat.duplicate()
	pt.stroke_begin(Vector2(-80, -60), 0)
	pt.stroke_to(Vector2(-60, -60))
	pt.stroke_end()
	t.check(ed.history.position() == 1, "PAINT: stroke 1 is a step")
	var h := S.hit_at(ed, Vector3(-80, 0, -60))
	pt.stroke_begin(Vector2(-80, -60), 0)
	pressed(ed, h)
	pt.stroke_to(Vector2(-70, -60))
	S.key(ed, KEY_Z, true)
	t.check(ed.history.position() == 1, "Ctrl+Z with the button held in a PAINT stroke does nothing")
	pt.stroke_to(Vector2(-60, -60))
	S.button(ed, h.screen, false)
	while ed.history.can_undo():
		ed.history.undo()
	t.check(ed.doc.splat == s0, "every step undone: the start's splat")
	ed.history.clear()


func _box_esc(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("select")
	var st: SelectTool = ed.tools.select
	ed.selection.clear()
	var a := ed.camera.unproject_position(Vector3(-100, 0, -100))
	S.button(ed, a, true)
	S.motion(ed, a + Vector2(10, 10))
	S.motion(ed, a + Vector2(40, 40))
	t.check(ed._dragging == "tool" and not st._box.is_empty(), "(a SELECT box drag runs)")
	S.key(ed, KEY_ESCAPE)
	await t.frames(1)
	t.check(ed._dragging == "" and ed._press.is_empty() and st._box.is_empty(), "Esc in a box drag ends the drag")
	t.check(ed.ui.menu == null, "and opens no EDITOR MENU")
	S.motion(ed, a + Vector2(80, 80))
	S.button(ed, a + Vector2(80, 80), false)
	t.check(st._box.is_empty() and ed.selection.uids.is_empty(), "the release after it selects nothing, no box follows the mouse")
	var p1: int = u.props[0]
	ed.select(PackedInt32Array([p1]))
	S.key(ed, KEY_PAGEUP)
	var rev := ed.doc.revision
	var t0 := Time.get_ticks_msec()
	while ed._bake_started < rev and Time.get_ticks_msec() - t0 < 1500:
		await t.frames(1)
	t.check(ed._bake_started >= rev, "an edit after it starts its bake within 1.5 s (started %d, doc %d)" % [ed._bake_started, rev])
	ed.history.undo()
	ed.selection.clear()


func _move_esc(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("select")
	var st: SelectTool = ed.tools.select
	var p3: int = u.props[2]
	var start := SelectTool._v3(ed.doc.find(p3).item.pos)
	var before := JSON.stringify(ed.doc.data)
	var n0 := ed.history.position()
	var hit := S.hit_at(ed, start, "prop", p3)
	t.check(st.drag_begin(hit, 0), "(SELECT drags a prop)")
	pressed(ed, hit)
	S.motion(ed, ed.camera.unproject_position(start + Vector3(12, 0, 0)))
	t.check(ed.history.position() == n0 + 1, "(the move made its step)")
	S.key(ed, KEY_DELETE)
	S.key(ed, KEY_2)
	S.key(ed, KEY_D, true)
	t.check(not ed.doc.find(p3).is_empty() and ed.tool.id == "select" and ed.history.position() == n0 + 1,
		"Delete, a tool key and Ctrl+D wait while the button is held")
	S.key(ed, KEY_ESCAPE)
	t.check(JSON.stringify(ed.doc.data) == before and ed.history.position() == n0 and not ed.history.can_redo()
		and not ed.history.in_gesture(), "Esc in a move takes it back (no redo, no gesture left)")
	S.button(ed, ed.camera.unproject_position(start + Vector3(20, 0, 0)), false)
	t.check(JSON.stringify(ed.doc.data) == before, "the release after Esc moves nothing")
	ed.selection.clear()


func _gizmo_esc(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("select")
	var p1: int = u.props[0]
	ed.select(PackedInt32Array([p1]))
	var n_props := (ed.doc.data.props as Array).size()
	var before := JSON.stringify(ed.doc.data.props)
	var g := ed.gizmo
	var c := ed.camera.unproject_position(g.attached().origin)
	var sn := {"on": false, "duplicate": true}
	g.drag(Gizmo3D.VIEW_PLANE, c, ed.camera, 0, sn)
	g.drag(Gizmo3D.VIEW_PLANE, c + Vector2(30, 0), ed.camera, 1, {"on": false})
	t.check(ed.pressing() and (ed.doc.data.props as Array).size() == n_props + 1, "(an Alt + gizmo duplicate runs: one copy)")
	S.key(ed, KEY_Z, true)
	t.check((ed.doc.data.props as Array).size() == n_props + 1 and ed.history.in_gesture(), "Ctrl+Z mid gizmo duplicate does nothing")
	S.key(ed, KEY_ESCAPE)
	t.check(not ed.pressing() and JSON.stringify(ed.doc.data.props) == before and not ed.history.in_gesture(),
		"Esc mid gizmo duplicate takes the copy back (%d props, %d before)" % [(ed.doc.data.props as Array).size(), n_props])
	ed.selection.clear()


func _lake(t: Node, ed: TrackEditor, u: Dictionary, lake_uid: int) -> void:
	ed.set_tool("terrain")
	var tt: TerrainTool = ed.tools.terrain
	var dot := EditorHit.new()
	dot.hit = true
	dot.what = "marker"
	dot.kind = "lake"
	dot.uid = lake_uid
	dot.sub = 0
	dot.screen = Vector2(800, 450)
	var h := EditorHit.new()
	h.ray_from = Vector3(100.0, 6.0, -300.0)
	h.ray_dir = Vector3(0, 0, 1)
	# a tool switch without a press (the palette): deactivate ends the gesture
	t.check(tt.drag_begin(dot, 0), "(the lake's level dot drags)")
	tt.drag_move(h, 0)
	ed.set_tool("select")
	t.check(not ed.history.in_gesture(), "a tool switch in a LAKE LEVEL drag leaves no gesture open")
	var p3: int = u.props[2]
	ed.select(PackedInt32Array([p3]))
	S.key(ed, KEY_PAGEUP)
	t.check(ed.history.undo_name() == "RAISE OBJECT", "the next edit is its own step (top '%s')" % ed.history.undo_name())
	ed.history.undo()
	t.check(is_equal_approx(float(ed.doc.find(lake_uid).item.level), 6.0), "one undo takes back only the raise")
	ed.history.undo()
	# with the button held a tool key waits; the release ends the drag
	ed.set_tool("terrain")
	t.check(tt.drag_begin(dot, 0), "(the dot drags again)")
	pressed(ed, dot)
	tt.drag_move(h, 0)
	S.key(ed, KEY_1)
	t.check(ed.tool.id == "terrain", "a tool key waits while the button holds a lake drag")
	S.button(ed, Vector2(830, 450), false)
	t.check(not ed.history.in_gesture() and ed.tool.id == "terrain", "the release ends it")
	ed.history.undo()
	ed.selection.clear()


func _branch(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("branch")
	var bt: BranchTool = ed.tools.branch
	var h := S.hit_at(ed, Vector3(150, 1, 0), "marker", 999, "branch")
	h.sub = BranchTool.SUB_FORK
	t.check(bt.drag_begin(h, 0), "(a branch's FORK end drags)")
	bt.cancel()
	t.check(not ed.history.in_gesture(), "BranchTool.cancel in an end drag leaves no gesture open")
	t.check(bt.drag_begin(h, 0), "(it drags again)")
	pressed(ed, h)
	S.key(ed, KEY_ESCAPE)
	S.button(ed, h.screen + Vector2(30, 0), false)
	t.check(not ed.history.in_gesture() and ed._press.is_empty(), "Esc in a branch end drag leaves no gesture open")
	ed.set_tool("select")
	var n0 := ed.history.position()
	ed.select(PackedInt32Array([u.props[0]]))
	S.key(ed, KEY_PAGEUP)
	S.key(ed, KEY_PAGEDOWN)
	S.key(ed, KEY_PAGEUP)
	t.check(ed.history.position() == n0 + 3, "three nudges after it are three steps (%d)" % (ed.history.position() - n0))
	while ed.history.position() > n0:
		ed.history.undo()
	ed.selection.clear()


func _focus(t: Node, ed: TrackEditor) -> void:
	ed.set_tool("select")
	var vp := ed.get_viewport()
	var search: LineEdit = ed.ui.outliner.search
	search.grab_focus()
	await t.frames(1)
	t.check(ed._blocked(), "(typing in the OUTLINER search holds the view's keys)")
	var c := ed.free_center()
	S.button(ed, c, true)
	S.button(ed, c, false)
	t.check(vp.gui_get_focus_owner() == null, "a click in the view lets go of the search")
	S.key(ed, KEY_2)
	t.check(ed.tool.id == "road", "and the keys work again (2: %s)" % ed.tool.id)
	ed.set_tool("select")
	search.grab_focus()
	search.text_submitted.emit(search.text)
	t.check(vp.gui_get_focus_owner() == null, "Enter in the OUTLINER search lets go")
	search.grab_focus()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	ed.ui._input(esc)
	t.check(vp.gui_get_focus_owner() == null, "Esc in a panel's text field lets go")
	# a press on another panel control lets go too (the press goes on)
	search.grab_focus()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = search.get_global_rect().position + Vector2(0, search.size.y + 40)
	ed.ui._input(mb)
	t.check(vp.gui_get_focus_owner() == null, "a press outside the field lets go")
	await t.frames(1)


## The first Ctrl+S of a track still called MY TRACK asks for its name; CANCEL writes nothing, and
## a track with its own name saves at once (_save_as then saves it).
func _first_save(t: Node, ed: TrackEditor) -> void:
	var s := ed.session
	t.check(EditorSession.is_auto_name("MY TRACK") and EditorSession.is_auto_name("my track 12")
		and not EditorSession.is_auto_name("MY TRACKS") and not EditorSession.is_auto_name("Canal Run"), "is_auto_name: MY TRACK and MY TRACK n only")
	if s.path != "":
		return
	var nm0 := str(ed.doc.data.name)
	ed.doc.apply([LevelDoc.op_set(["name"], "MY TRACK")])
	S.key(ed, KEY_S, true)
	await t.frames(2)
	var boxes := ed.get_tree().root.find_children("*", "MessageBox", true, false)
	t.check(boxes.size() == 1 and s.path == "" and not s.saving, "the first Ctrl+S of MY TRACK asks for a name, nothing is written yet")
	if boxes.size() == 1:
		(boxes[0] as MessageBox)._answer(false)
		await t.frames(2)
	t.check(s.path == "" and not s.saving and str(ed.doc.data.name) == "MY TRACK", "CANCEL saves nothing and keeps the name")
	ed.doc.apply([LevelDoc.op_set(["name"], nm0)])


func _save_as(t: Node, ed: TrackEditor) -> void:
	var s := ed.session
	ed.save()
	var t0 := Time.get_ticks_msec()
	while (s.saving or s.path == "") and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	var p0 := s.path
	t.check(p0 != "" and FileAccess.file_exists(p0), "(the track is saved: %s)" % p0)
	if p0 == "":
		return
	var g0 := str(LevelIO.read_meta(p0).get("guid", ""))
	var bytes0 := FileAccess.get_file_as_bytes(p0)
	# the key asks for a name first
	S.key(ed, KEY_S, true, true)
	await t.frames(2)
	var boxes := ed.get_tree().root.find_children("*", "MessageBox", true, false)
	t.check(boxes.size() == 1 and s.path == p0 and not s.saving, "Ctrl+Shift+S asks for a name, nothing is written yet")
	if boxes.size() != 1:
		return
	var box := boxes[0] as MessageBox
	box.field.text = "Press Copy"
	box._answer(true)
	await t.frames(2)
	t0 = Time.get_ticks_msec()
	while (s.saving or s.path == "") and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	var p1 := s.path
	var m1 := LevelIO.read_meta(p1)
	t.check(FileAccess.file_exists(p0) and FileAccess.get_file_as_bytes(p0) == bytes0, "SAVE AS leaves the original file as it was")
	t.check(p1 != p0 and FileAccess.file_exists(p1) and str(m1.get("name", "")) == "Press Copy" and str(m1.get("guid", "")) != g0
		and str(m1.get("guid", "")) != "", "the copy has the new name and its own guid (%s, %s)" % [p1.get_file(), str(m1.get("name", ""))])
	t.check(str(ed.doc.data.get("name", "")) == "Press Copy" and not s.dirty(), "the editor goes on with the saved copy")
	DirAccess.remove_absolute(p0)
	DirAccess.remove_absolute(p1)
	CustomTracks.refresh()
