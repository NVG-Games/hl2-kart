extends RefCounted
## editor/case_select (P8, CI, fake registries): selection in the editor scene (1.5). Fabricated
## hits: click / Shift adds / Ctrl toggles / a click on nothing deselects; through the input path:
## a press moved 3 px is a click, a drag from empty space draws a box that selects in SELECT only;
## Ctrl+A; delete of props and a road point is one undo step that comes back exactly; PgUp presses
## merge within the merge window; a marker drag moves on the ground (one step), an anchored item's
## drag goes through its owner's slide(); copy / paste in place / paste at the cursor (a pad
## re-anchors on the road) / Ctrl+D; End drops a light to the ground.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}


func run(t: Node) -> void:
	var doc := test_doc()
	var ed: TrackEditor = await open_editor(t, doc)
	var u := uids_of(doc)
	ed.set_tool("select")
	look_down(ed, Vector3(0, 0, 0), 200.0)
	await t.frames(2)
	_click_rules(t, ed, u)
	_hints(t, ed, u)
	_threshold_and_box(t, ed, u)
	_select_all(t, ed, u)
	_delete_undo(t, ed, u)
	_nudge(t, ed, u)
	_marker_drag(t, ed, u)
	_slide(t, ed, u)
	_clipboard(t, ed, u)
	await _drop(t, ed, u)
	await close_editor(t, ed)


## A 512 m world: a closed 8-point loop (r 150), three props, a light, a pad on the loop.
static func test_doc() -> LevelDoc:
	var doc := LevelDoc.blank("Select", 512.0, 257)
	var pts := []
	for k in 8:
		var ang := TAU * k / 8
		pts.append({"uid": doc.new_uid(), "pos": [150.0 * cos(ang), 1.0, 150.0 * sin(ang)], "width": 14.0, "style": "asphalt"})
	doc.data["road"] = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	for p in [[10.0, 0.0, 10.0], [20.0, 0.0, 10.0], [-60.0, 0.0, -40.0]]:
		doc.data.props.append({"uid": doc.new_uid(), "model": "props_junk/wood_crate001a", "pos": p, "yaw": 0.0, "scale": 1.0})
	doc.data.lights.append({"uid": doc.new_uid(), "pos": [0.0, 8.0, 0.0], "color": [1.0, 0.9, 0.7], "range": 16.0, "energy": 1.2})
	doc.data.pads.append({"uid": doc.new_uid(), "road": -1, "at": {"p": pts[2].uid, "t": 0.5}, "lat": null, "turn": 0.0})
	return doc


## {points: [...], props: [...], light, pad}
static func uids_of(doc: LevelDoc) -> Dictionary:
	var pts := []
	for p in doc.data.road.points:
		pts.append(int(p.uid))
	var props := []
	for p in doc.data.props:
		props.append(int(p.uid))
	return {"points": pts, "props": props, "light": int(doc.data.lights[0].uid), "pad": int(doc.data.pads[0].uid)}


## The editor scene on doc with a synchronous bake (shown at once, as after a test drive).
static func open_editor(t: Node, doc: LevelDoc) -> TrackEditor:
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG, "flags": true})
	var s := EditorSession.current()
	s._take(doc)
	s.build = b
	var ed: TrackEditor = load("res://scenes/editor.tscn").instantiate()
	t.get_tree().root.add_child(ed)
	await t.frames(2)
	return ed


static func close_editor(t: Node, ed: TrackEditor) -> void:
	ed.queue_free()
	await t.frames(1)
	EditorSession.current().close()


## The camera h metres straight above c, north up (perspective).
static func look_down(ed: TrackEditor, c: Vector3, h: float) -> void:
	ed.camera.go_to(Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), c + Vector3.UP * h))


## An EditorHit as TrackEditor's pick makes it, at a world point.
static func hit_at(ed: TrackEditor, p: Vector3, what := "terrain", uid := 0, kind := "") -> EditorHit:
	var h := EditorHit.new()
	var sc := ed.camera.unproject_position(p)
	h.screen = sc
	h.ray_from = ed.camera.project_ray_origin(sc)
	h.ray_dir = ed.camera.project_ray_normal(sc)
	h.hit = what != ""
	h.what = what
	h.pos = p
	h.uid = uid
	h.kind = kind
	return h


static func button(ed: TrackEditor, at: Vector2, down: bool, mods := 0) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.position = at
	b.shift_pressed = (mods & EditorTool.MOD_SHIFT) != 0
	b.ctrl_pressed = (mods & EditorTool.MOD_CTRL) != 0
	ed._unhandled_input(b)


static func motion(ed: TrackEditor, at: Vector2, mods := 0) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.shift_pressed = (mods & EditorTool.MOD_SHIFT) != 0
	ed._unhandled_input(m)


static func key(ed: TrackEditor, code: Key, ctrl := false, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	ed._unhandled_input(k)


static func sorted(a: PackedInt32Array) -> Array:
	var out := Array(a)
	out.sort()
	return out


func _prop_pos(ed: TrackEditor, uid: int) -> Vector3:
	return SelectTool._v3(ed.doc.find(uid).item.pos)


func _click_rules(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var p1: int = u.props[0]
	var p2: int = u.props[1]
	ed.click(hit_at(ed, Vector3(10, 0, 10), "prop", p1), 0)
	t.check(ed.selection.uids == PackedInt32Array([p1]), "click selects")
	ed.click(hit_at(ed, Vector3(20, 0, 10), "prop", p2), EditorTool.MOD_SHIFT)
	t.check(sorted(ed.selection.uids) == sorted(PackedInt32Array([p1, p2])), "Shift+click adds")
	ed.click(hit_at(ed, Vector3(10, 0, 10), "prop", p1), EditorTool.MOD_CTRL)
	t.check(ed.selection.uids == PackedInt32Array([p2]), "Ctrl+click toggles off")
	ed.click(hit_at(ed, Vector3(10, 0, 10), "prop", p1), EditorTool.MOD_CTRL)
	t.check(sorted(ed.selection.uids) == sorted(PackedInt32Array([p1, p2])), "Ctrl+click toggles on")
	ed.click(hit_at(ed, Vector3(10, 0, 10), "marker", u.light, "light"), 0)
	t.check(ed.selection.uids == PackedInt32Array([u.light]), "a click on a light's marker selects it alone")
	t.check(ed.gizmo.visible and ed.gizmo.attached().origin.distance_to(Vector3(0, 8, 0)) < 0.01, "the gizmo sits on the selected light")
	ed.click(hit_at(ed, Vector3(80, 0, 80), "terrain"), 0)
	t.check(ed.selection.uids.is_empty() and not ed.gizmo.visible, "a click on nothing deselects (and the gizmo goes)")
	ed.select(PackedInt32Array([u.pad]))
	t.check(not ed.gizmo.visible, "an anchored item (a pad) shows no gizmo")
	ed.selection.clear()


## What the status bar's PromptBar says over each thing (C2 M2); the tool options build.
func _hints(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var tool: SelectTool = ed.tools.select
	var hp := tool.hints(hit_at(ed, Vector3(10, 0, 10), "prop", u.props[0]))
	t.check(hp.size() >= 3 and hp[1] == ["DRAG MOVE"] and hp[2] == ["{ed_mod_shift} DRAG HEIGHT"], "over a prop: CLICK SELECT · DRAG MOVE · Shift DRAG HEIGHT")
	var hs := tool.hints(hit_at(ed, Vector3(0, 1, 150), "marker", u.pad, "pad"))
	t.check(hs[1] == ["DRAG SLIDE ALONG THE ROAD"], "over a pad: DRAG SLIDE ALONG THE ROAD")
	t.check(tool.hints(EditorHit.new())[1] == ["DRAG BOX SELECT"], "over nothing: DRAG BOX SELECT")
	var g := EditorHit.new()
	g.hit = true
	g.what = "gizmo"
	t.check(tool.hints(g)[1] == ["{ed_mod_alt} DRAG DUPLICATE"], "over the gizmo: Alt DRAG DUPLICATE")
	var box := VBoxContainer.new()
	tool.options(box)
	t.check(box.get_child_count() == 3, "the tool options: mode buttons, LOCAL AXES, the hint")
	box.free()


func _threshold_and_box(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var cam := ed.camera
	var a := cam.unproject_position(Vector3(10, 0, 10)) - Vector2(15, 15)
	var b := cam.unproject_position(Vector3(20, 0, 10)) + Vector2(15, 15)
	ed.select(PackedInt32Array([u.props[2]]))
	button(ed, a, true)
	motion(ed, a + Vector2(3, 0))
	button(ed, a + Vector2(3, 0), false)
	t.check(ed.selection.uids.is_empty(), "a press moved 3 px on empty ground is a click: it deselects")
	button(ed, a, true)
	motion(ed, a + Vector2(2, 2))
	motion(ed, (a + b) * 0.5)
	var sel_tool: SelectTool = ed.tools.select
	var shown: bool = sel_tool._box_ctl != null and sel_tool._box_ctl.visible
	motion(ed, b)
	button(ed, b, false)
	t.check(shown and not sel_tool._box_ctl.visible, "the box is drawn while dragged, gone after")
	t.check(sorted(ed.selection.uids) == sorted(PackedInt32Array([u.props[0], u.props[1]])), "a drag from empty space box-selects the two props inside (%s)" % str(ed.selection.uids))
	var c := cam.unproject_position(Vector3(0, 8, 0))
	button(ed, c + Vector2(-12, -12), true, EditorTool.MOD_SHIFT)
	motion(ed, c + Vector2(12, 12), EditorTool.MOD_SHIFT)
	button(ed, c + Vector2(12, 12), false, EditorTool.MOD_SHIFT)
	t.check(ed.selection.uids.size() == 3 and ed.selection.has(u.light), "Shift + box adds the light")
	ed.set_tool("world")
	ed.selection.clear()
	button(ed, a, true)
	motion(ed, a + Vector2(6, 6))
	motion(ed, b)
	button(ed, b, false)
	t.check(ed.selection.uids.is_empty(), "the same drag in another tool (WORLD) selects nothing: box select is SELECT's")
	ed.set_tool("select")


func _select_all(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	key(ed, KEY_A, true)
	var want := (u.points as Array).size() + (u.props as Array).size() + 2
	t.check(ed.selection.uids.size() == want, "Ctrl+A in SELECT selects everything (%d of %d)" % [ed.selection.uids.size(), want])
	key(ed, KEY_ESCAPE)
	t.check(ed.selection.uids.is_empty(), "Esc deselects")


func _delete_undo(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var before := JSON.stringify(ed.doc.data)
	var steps := ed.history.position()
	ed.select(PackedInt32Array([u.props[0], u.props[1], u.points[5]]))
	key(ed, KEY_DELETE)
	t.check(ed.doc.data.props.size() == 1 and ed.doc.data.road.points.size() == 7, "Delete removes two props and a road point (%d props, %d points)" % [ed.doc.data.props.size(), ed.doc.data.road.points.size()])
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "DELETE 3 OBJECTS", "one undo step (%s)" % ed.history.undo_name())
	t.check(ed.selection.uids.is_empty(), "the deleted items leave the selection")
	key(ed, KEY_Z, true)
	t.check(JSON.stringify(ed.doc.data) == before, "Ctrl+Z brings the document back exactly")
	ed.history.redo()
	ed.history.undo()
	t.check(JSON.stringify(ed.doc.data) == before, "redo + undo: identical again")


func _nudge(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var p3: int = u.props[2]
	ed.select(PackedInt32Array([p3]))
	var y0 := _prop_pos(ed, p3).y
	var steps := ed.history.position()
	key(ed, KEY_PAGEUP)
	key(ed, KEY_PAGEUP)
	t.check(is_equal_approx(_prop_pos(ed, p3).y, y0 + 2.0), "two PgUp raise by two grid steps (%.2f)" % _prop_pos(ed, p3).y)
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "RAISE OBJECT", "presses within 1 s merge into one step (%s)" % ed.history.undo_name())
	ed.history.merge_window = -1.0
	key(ed, KEY_PAGEDOWN)
	ed.history.merge_window = 1.0
	t.check(ed.history.position() == steps + 2 and is_equal_approx(_prop_pos(ed, p3).y, y0 + 1.0), "a press after the window is its own step (LOWER)")
	ed.snap["on"] = false
	ed.snap["grid"] = 4.0
	key(ed, KEY_PAGEDOWN)
	ed.snap["on"] = true
	ed.snap["grid"] = 1.0
	t.check(is_equal_approx(_prop_pos(ed, p3).y, y0) and ed.history.position() == steps + 2, "with the grid off the step is 1 m (and it merged into LOWER)")
	ed.history.undo()
	ed.history.undo()
	t.check(is_equal_approx(_prop_pos(ed, p3).y, y0) and not ed.history.can_undo(), "two undos take all four presses back")


func _marker_drag(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var p3: int = u.props[2]
	ed.selection.clear()
	var tool: SelectTool = ed.tools.select
	var steps := ed.history.position()
	var start := Vector3(-60, 0, -40)
	t.check(tool.drag_begin(hit_at(ed, start, "prop", p3), 0), "SELECT owns a drag that starts on a prop")
	t.check(ed.selection.uids == PackedInt32Array([p3]), "the dragged prop is selected")
	tool.drag_move(hit_at(ed, start + Vector3(5.2, 0, 3.1), "terrain"), 0)
	tool.drag_move(hit_at(ed, start + Vector3(10.3, 0, -6.8), "terrain"), 0)
	tool.drag_end(hit_at(ed, start + Vector3(10.3, 0, -6.8), "terrain"), 0)
	var p := _prop_pos(ed, p3)
	t.check(p.distance_to(Vector3(-50, 0, -47)) < 0.05, "a marker drag moves it on the ground, on the 1 m grid (%s)" % str(p))
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "MOVE OBJECT", "one step (%s)" % ed.history.undo_name())
	# Shift + drag: height
	tool.drag_begin(hit_at(ed, p, "prop", p3), EditorTool.MOD_SHIFT)
	var h := hit_at(ed, p, "terrain")
	h.screen += Vector2(0, -20)
	tool.drag_end(h, EditorTool.MOD_SHIFT)
	t.check(_prop_pos(ed, p3).y > 2.0 and Vector2(_prop_pos(ed, p3).x, _prop_pos(ed, p3).z).distance_to(Vector2(p.x, p.z)) < 0.01,
		"Shift + drag lifts it straight up (%.2f m)" % _prop_pos(ed, p3).y)
	ed.history.undo()
	ed.history.undo()
	t.check(_prop_pos(ed, p3).distance_to(start) < 0.01, "both undone")
	ed.selection.clear()


func _slide(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var keep: EditorTool = ed.tools.items
	var fake := FakeItems.new(ed)
	ed.tools["items"] = fake
	var tool: SelectTool = ed.tools.select
	var steps := ed.history.position()
	var at0: Dictionary = ed.doc.find(u.pad).item.at.duplicate()
	t.check(tool.drag_begin(hit_at(ed, Vector3(0, 1, 150), "marker", u.pad, "pad"), 0), "a pad's marker drag is SELECT's")
	tool.drag_move(hit_at(ed, Vector3(-10, 1, 150), "road"), 0)
	tool.drag_end(hit_at(ed, Vector3(-20, 1, 150), "road"), 0)
	t.check(fake.phases == [0, 1, 2], "it goes through the owner tool's slide() (phases %s)" % str(fake.phases))
	t.check(ed.history.position() == steps + 1 and absf(float(ed.doc.find(u.pad).item.at.t) - 0.75) < 1e-6, "the slide's ops are one step")
	t.check(not ed.gizmo.visible, "no gizmo on the slid pad")
	ed.history.undo()
	t.check(ed.doc.find(u.pad).item.at == at0, "undone")
	ed.tools["items"] = keep


func _clipboard(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var p1: int = u.props[0]
	var n0: int = ed.doc.data.props.size()
	ed.select(PackedInt32Array([p1]))
	key(ed, KEY_C, true)
	t.check(ed.session.clipboard.size() == 1 and (ed.session.clipboard[0].items as Array).size() == 1, "Ctrl+C copies the prop into the session's clipboard")
	var json := JSON.stringify(ed.session.clipboard[0])
	var back = JSON.parse_string(json)
	t.check(back is Dictionary and back.kind == SelectTool.CLIP_KIND, "the copy is JSON (the OS clipboard's form)")
	key(ed, KEY_V, true, true)
	var made := ed.selection.uids.duplicate()
	t.check(ed.doc.data.props.size() == n0 + 1 and made.size() == 1 and made[0] != p1, "Ctrl+Shift+V pastes a copy with a new uid")
	t.check(_prop_pos(ed, made[0]).distance_to(Vector3(10, 0, 10)) < 0.01, "in place")
	ed.hover = hit_at(ed, Vector3(100, 0, 50), "terrain")
	key(ed, KEY_V, true)
	var at_cursor := ed.selection.uids.duplicate()
	t.check(at_cursor.size() == 1 and _prop_pos(ed, at_cursor[0]).distance_to(Vector3(100, 0, 50)) < 0.01, "Ctrl+V pastes at the cursor's hit point (%s)" % str(_prop_pos(ed, at_cursor[0]) if at_cursor.size() == 1 else "-"))
	ed.select(PackedInt32Array([p1]))
	key(ed, KEY_D, true)
	var dup := ed.selection.uids.duplicate()
	t.check(dup.size() == 1 and _prop_pos(ed, dup[0]).distance_to(Vector3(12, 0, 10)) < 0.01, "Ctrl+D duplicates two grid steps to the camera's right (%s)" % str(_prop_pos(ed, dup[0]) if dup.size() == 1 else "-"))
	t.check(ed.history.undo_name() == "DUPLICATE OBJECT", "one step (%s)" % ed.history.undo_name())
	# an anchored pad re-anchors at the nearest road spot
	ed.select(PackedInt32Array([u.pad]))
	SelectTool.copy_selection(ed)
	var p6: Array = ed.doc.find(u.points[6]).item.pos
	ed.hover = hit_at(ed, Vector3(float(p6[0]), 1.0, float(p6[2])) + Vector3(4, 0, 0), "road")
	SelectTool.paste(ed)
	var pads: Array = ed.doc.data.pads
	var np: Dictionary = pads[-1]
	var r := ed.road(-1)
	var s_new := r.anchor_s(np.at)
	var s_want := r.s[r.closest(ed.hover.pos)]
	t.check(pads.size() == 2 and int(np.uid) != u.pad and absf(s_new - s_want) < 0.5, "a pasted pad re-anchors at the nearest road spot (s %.1f, want %.1f)" % [s_new, s_want])
	# a copy from another track through sanitize_items: junk keys and a bad model are cleaned
	ed.session.clipboard = [{"kind": SelectTool.CLIP_KIND, "v": 1, "center": [0, 0, 0],
		"items": [{"section": "props", "item": {"model": "props_junk/wood_crate001a", "pos": [1, 0, 1], "evil": 1, "scale": 99.0}}]}]
	ed.hover = hit_at(ed, Vector3(-100, 0, 0), "terrain")
	SelectTool.paste(ed)
	var last: Dictionary = ed.doc.data.props[-1]
	t.check(ed.doc.data.props.size() == n0 + 4 and not last.has("evil") and float(last.get("scale", 1.0)) <= 4.0 		and SelectTool._v3(last.pos).distance_to(Vector3(-99, 0, 1)) < 0.01, "pasted JSON goes through sanitize_items (%s)" % str(last))
	for k in 6:
		ed.history.undo()
	t.check(ed.doc.data.props.size() == n0 and ed.doc.data.pads.size() == 1, "every paste is one undo step")
	ed.hover = EditorHit.new()
	ed.selection.clear()


func _drop(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	await t.frames(3)
	ed.select(PackedInt32Array([u.light]))
	key(ed, KEY_END)
	var y := float(ed.doc.find(u.light).item.pos[1])
	t.check(absf(y) < 0.05, "End drops the light onto the ground (y %.2f)" % y)
	t.check(ed.history.undo_name() == "DROP OBJECT", "one step (%s)" % ed.history.undo_name())
	ed.history.undo()
	ed.selection.clear()


## An ITEMS tool whose slide moves the pad's anchor t to 0.75 and records the phases.
class FakeItems:
	extends EditorTool
	var phases: Array = []

	func _init(ed: TrackEditor) -> void:
		super(ed)
		id = "items"

	func kinds() -> PackedStringArray:
		return PackedStringArray(["item_row", "crate", "pad", "barrels", "zone"])

	func slide(uid: int, _hit: EditorHit, phase: int) -> Array:
		phases.append(phase)
		var at: Dictionary = editor.doc.find(uid).item.at.duplicate()
		at["t"] = 0.5 + 0.125 * phase
		return [LevelDoc.op_set(editor.doc.path_of(uid) + ["at"], at)]
