extends RefCounted
## editor/case_gizmo (P8, CI): Gizmo3D with a headless Camera3D. Handles are picked in screen space
## within 8 px (axes, planes, the centre, the rings, the scale box; none behind the camera; pitch and
## roll rings for props only); axis / plane drags snap to the grid (world axes round the moved
## origin, local axes the offset), off without it; a ring drag snaps to the angle step; a scale
## drag snaps to 0.05. In the editor: a gizmo drag through TrackEditor's input moves the selection
## (one step), a ring drag turns a prop (yaw 45), Alt + drag on a handle duplicates the selection
## and moves the copies (one step).

const NEEDS_CONTENT := false
const SNAP := {"on": true, "grid": 1.0, "angle": 15.0, "angle_on": true, "surface": false, "invert": false}
const Sel := preload("res://tests/editor/case_select.gd")

var _moves: Array = []


func run(t: Node) -> void:
	var root := Node3D.new()
	root.name = "CaseGizmo"
	t.get_tree().root.add_child(root)
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -12, -24).normalized(), Vector3.UP), Vector3(0, 12, 24))
	cam.current = true
	var g := Gizmo3D.new()
	root.add_child(g)
	g.moved.connect(func(d: Transform3D, final: bool) -> void: _moves.append([d, final]))
	await t.frames(1)
	t.check(not g.visible and g.pick(Vector2(800, 450), cam) == -1, "a detached gizmo is hidden and never picked")
	g.attach(Transform3D(), false)
	var length := Gizmo3D.LENGTH_PX * Gizmo3D.world_per_px(cam, Vector3.ZERO)
	_pick(t, g, cam, length)
	_drags(t, g, cam, length)
	root.queue_free()
	await t.frames(1)
	await _editor(t)


func _sc(cam: Camera3D, p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _pick(t: Node, g: Gizmo3D, cam: Camera3D, length: float) -> void:
	g.mode = "move"
	var tip := _sc(cam, Vector3(length * 0.9, 0, 0))
	var axis_dir := (_sc(cam, Vector3(length, 0, 0)) - _sc(cam, Vector3(length * 0.5, 0, 0))).normalized()
	var side := Vector2(-axis_dir.y, axis_dir.x)
	t.check(g.pick(tip, cam) == Gizmo3D.X_AXIS, "the X arrow is picked on it")
	t.check(g.pick(tip + side * 7.0, cam) == Gizmo3D.X_AXIS, "and 7 px beside it")
	t.check(g.pick(tip + side * 12.0, cam) == -1, "not 12 px beside it")
	t.check(g.pick(_sc(cam, Vector3(0, length * 0.8, 0)), cam) == Gizmo3D.Y_AXIS, "the Y arrow")
	t.check(g.pick(_sc(cam, Vector3(0, 0, length * 0.8)), cam) == Gizmo3D.Z_AXIS, "the Z arrow")
	t.check(g.pick(_sc(cam, Vector3.ZERO), cam) == Gizmo3D.VIEW_PLANE, "the centre box (camera plane)")
	t.check(g.pick(_sc(cam, Vector3(length * 0.35, 0, length * 0.35)), cam) == Gizmo3D.XZ_PLANE, "the XZ square")
	var px := Gizmo3D.world_per_px(cam, Vector3.ZERO)
	t.check(absf(_sc(cam, Vector3(length, 0, 0)).distance_to(_sc(cam, Vector3.ZERO)) - Gizmo3D.LENGTH_PX) < 12.0, "the arrows are about 96 px long on screen (%.1f m per px)" % px)
	g.mode = "rotate"
	t.check(g.pick(_sc(cam, Vector3(length * 0.9, 0, 0)), cam) == Gizmo3D.YAW_RING, "ROTATE: the yaw ring")
	var top := _sc(cam, Vector3(0, length * 0.78, 0))
	t.check(g.pick(top, cam) != Gizmo3D.PITCH_RING, "no pitch ring unless every item is a prop")
	g.attach(Transform3D(), true)
	t.check(g.pick(top, cam) == Gizmo3D.PITCH_RING, "props: the pitch ring")
	var roll_at := Vector3(cos(deg_to_rad(70.0)), sin(deg_to_rad(70.0)), 0.0) * length * 0.66
	t.check(g.pick(_sc(cam, roll_at), cam) == Gizmo3D.ROLL_RING, "and the roll ring")
	g.mode = "scale"
	t.check(g.pick(_sc(cam, Vector3.ZERO), cam) == Gizmo3D.SCALE_BOX, "SCALE: the uniform cube")
	g.attach(Transform3D(Basis(), Vector3(0, 12, 40)), false)
	t.check(g.pick(_sc(cam, Vector3(0, 12, 30)), cam) == -1, "a gizmo behind the camera is never picked")
	g.attach(Transform3D(), false)
	g.mode = "move"


func _drag(g: Gizmo3D, cam: Camera3D, h: int, from: Vector3, to: Vector3, snap: Dictionary) -> Transform3D:
	_moves.clear()
	g.drag(h, _sc(cam, from), cam, 0, snap)
	g.drag(h, _sc(cam, from.lerp(to, 0.5)), cam, 1, snap)
	g.drag(h, _sc(cam, to), cam, 2, snap)
	return _moves[-1][0] if not _moves.is_empty() else Transform3D()


func _drags(t: Node, g: Gizmo3D, cam: Camera3D, length: float) -> void:
	var a := Vector3(length * 0.6, 0, 0)
	var d := _drag(g, cam, Gizmo3D.X_AXIS, a, a + Vector3(3.3, 0, 0), SNAP)
	t.check(d.origin.distance_to(Vector3(3, 0, 0)) < 1e-3 and d.basis.is_equal_approx(Basis()), "X drag of 3.3 m snaps to 3 m (%s)" % str(d.origin))
	t.check(_moves.size() == 2 and not _moves[0][1] and _moves[-1][1] and g.dragging == -1, "moved: one move, then final")
	var off := SNAP.duplicate()
	off["on"] = false
	d = _drag(g, cam, Gizmo3D.X_AXIS, a, a + Vector3(3.3, 0, 0), off)
	t.check(absf(d.origin.x - 3.3) < 0.01, "without the grid: 3.3 m (%.3f)" % d.origin.x)
	var inv := SNAP.duplicate()
	inv["invert"] = true
	d = _drag(g, cam, Gizmo3D.X_AXIS, a, a + Vector3(3.3, 0, 0), inv)
	t.check(absf(d.origin.x - 3.3) < 0.01, "Ctrl held inverts the grid snap")
	var b := Vector3(0, length * 0.6, 0)
	d = _drag(g, cam, Gizmo3D.Y_AXIS, b, b + Vector3(0, 2.6, 0), SNAP)
	t.check(d.origin.distance_to(Vector3(0, 3, 0)) < 1e-3, "Y drag of 2.6 m snaps to 3 m (%s)" % str(d.origin))
	var c := Vector3(length * 0.35, 0, length * 0.35)
	d = _drag(g, cam, Gizmo3D.XZ_PLANE, c, c + Vector3(2.4, 0, -1.7), SNAP)
	t.check(d.origin.distance_to(Vector3(2, 0, -2)) < 1e-3, "XZ plane drag snaps x and z (%s)" % str(d.origin))
	# off-grid start: the moved origin lands on the grid (world axes)
	g.attach(Transform3D(Basis(), Vector3(0.4, 0, 0)), false)
	d = _drag(g, cam, Gizmo3D.X_AXIS, Vector3(0.4 + length * 0.6, 0, 0), Vector3(0.4 + length * 0.6 + 1.2, 0, 0), SNAP)
	t.check(absf(0.4 + d.origin.x - 2.0) < 1e-3, "world axes: the moved origin lands on the grid (0.4 + %.2f)" % d.origin.x)
	# LOCAL axes: a yawed frame's X is world -Z; the offset along it snaps
	g.attach(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), true)
	g.local = true
	var ax := Basis(Vector3.UP, PI * 0.5).x
	d = _drag(g, cam, Gizmo3D.X_AXIS, ax * length * 0.6, ax * (length * 0.6 + 2.6), SNAP)
	t.check(d.origin.distance_to(ax * 3.0) < 1e-3, "LOCAL: along the item's own X, the offset snapped (%s)" % str(d.origin))
	g.local = false
	g.attach(Transform3D(), false)
	# rotate: the yaw ring 40 deg -> 45 with the 15 deg step
	g.mode = "rotate"
	var r0 := Vector3(length * 0.9, 0, 0)
	_moves.clear()
	g.drag(Gizmo3D.YAW_RING, _sc(cam, r0), cam, 0, SNAP)
	g.drag(Gizmo3D.YAW_RING, _sc(cam, Basis(Vector3.UP, deg_to_rad(40.0)) * r0), cam, 2, SNAP)
	var yaw := rad_to_deg(_moves[-1][0].basis.get_euler().y) if not _moves.is_empty() else 0.0
	t.check(absf(yaw - 45.0) < 0.01, "a 40 deg turn of the yaw ring snaps to 45 (%.2f)" % yaw)
	var no_angle := SNAP.duplicate()
	no_angle["angle_on"] = false
	_moves.clear()
	g.drag(Gizmo3D.YAW_RING, _sc(cam, r0), cam, 0, no_angle)
	g.drag(Gizmo3D.YAW_RING, _sc(cam, Basis(Vector3.UP, deg_to_rad(40.0)) * r0), cam, 2, no_angle)
	yaw = rad_to_deg(_moves[-1][0].basis.get_euler().y) if not _moves.is_empty() else 0.0
	t.check(absf(yaw - 40.0) < 0.5, "without the angle snap: 40 (%.2f)" % yaw)
	# scale: 100 px right-and-up = x e, snapped to 0.05
	g.mode = "scale"
	_moves.clear()
	var s0 := _sc(cam, Vector3.ZERO)
	g.drag(Gizmo3D.SCALE_BOX, s0, cam, 0, SNAP)
	g.drag(Gizmo3D.SCALE_BOX, s0 + Vector2(50, -50), cam, 2, SNAP)
	var f: float = _moves[-1][0].basis.get_scale().x if not _moves.is_empty() else 0.0
	t.check(absf(f - 2.7) < 1e-3, "a scale drag of 100 px gives x 2.70 (snapped, %.3f)" % f)
	g.mode = "move"


func _editor(t: Node) -> void:
	var doc: LevelDoc = Sel.test_doc()
	var ed: TrackEditor = await Sel.open_editor(t, doc)
	var u: Dictionary = Sel.uids_of(doc)
	ed.set_tool("select")
	Sel.look_down(ed, Vector3(15, 0, 10), 120.0)
	ed.snap["surface"] = false
	await t.frames(1)
	var cam := ed.camera
	var p1: int = u.props[0]
	var p2: int = u.props[1]
	# a plain drag of the X arrow through TrackEditor's input: one MOVE step
	ed.select(PackedInt32Array([p1]))
	var o := ed.gizmo.attached().origin
	t.check(ed.gizmo.visible and o.distance_to(Vector3(10, 0, 10)) < 1e-3, "the gizmo is on the selected prop")
	var length := Gizmo3D.LENGTH_PX * Gizmo3D.world_per_px(cam, o)
	var at := o + Vector3(length * 0.6, 0, 0)
	t.check(ed.pick(cam.unproject_position(at)).what == "gizmo", "TrackEditor.pick finds the handle first")
	var steps := ed.history.position()
	Sel.button(ed, cam.unproject_position(at), true)
	Sel.motion(ed, cam.unproject_position(at + Vector3(1.0, 0, 0)))
	Sel.motion(ed, cam.unproject_position(at + Vector3(4.2, 0, 0)))
	Sel.button(ed, cam.unproject_position(at + Vector3(4.2, 0, 0)), false)
	var p := SelectTool._v3(ed.doc.find(p1).item.pos)
	t.check(p.distance_to(Vector3(14, 0, 10)) < 1e-3, "a gizmo drag moves the prop 4 m along X (%s)" % str(p))
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "MOVE OBJECT", "one step (%s)" % ed.history.undo_name())
	t.check(ed.gizmo.attached().origin.distance_to(Vector3(14, 0, 10)) < 1e-3, "the gizmo follows")
	ed.history.undo()
	t.check(ed.gizmo.attached().origin.distance_to(Vector3(10, 0, 10)) < 1e-3, "and comes back with the undo")
	# a ring drag turns the prop
	ed.gizmo.mode = "rotate"
	var r0 := o + Vector3(length * 0.9, 0, 0)
	ed.gizmo.drag(Gizmo3D.YAW_RING, cam.unproject_position(r0), cam, 0, ed.snap)
	ed.gizmo.drag(Gizmo3D.YAW_RING, cam.unproject_position(o + Basis(Vector3.UP, deg_to_rad(40.0)) * (r0 - o)), cam, 2, ed.snap)
	var yaw := float(ed.doc.find(p1).item.get("yaw", 0.0))
	t.check(absf(yaw - 45.0) < 0.01 and ed.history.undo_name() == "ROTATE OBJECT", "the yaw ring turns the prop to 45 deg (%.2f, %s)" % [yaw, ed.history.undo_name()])
	ed.history.undo()
	ed.gizmo.mode = "move"
	# Alt + drag on a handle: the copies move, the originals stay
	ed.select(PackedInt32Array([p1, p2]))
	o = ed.gizmo.attached().origin
	length = Gizmo3D.LENGTH_PX * Gizmo3D.world_per_px(cam, o)
	at = o + Vector3(length * 0.6, 0, 0)
	steps = ed.history.position()
	var n0: int = ed.doc.data.props.size()
	_alt(ed, cam.unproject_position(at), true)
	_alt_motion(ed, cam.unproject_position(at + Vector3(1.0, 0, 0)))
	_alt_motion(ed, cam.unproject_position(at + Vector3(5.2, 0, 0)))
	_alt(ed, cam.unproject_position(at + Vector3(5.2, 0, 0)), false)
	var props: Array = ed.doc.data.props
	t.check(props.size() == n0 + 2, "Alt + drag made two copies (%d props)" % props.size())
	var sel := ed.selection.uids
	var copies_ok := sel.size() == 2 and not (p1 in sel) and not (p2 in sel)
	var spots := []
	for c in sel:
		spots.append(SelectTool._v3(ed.doc.find(c).item.pos))
	t.check(copies_ok and spots.size() == 2 and (spots[0] as Vector3).distance_to(Vector3(15, 0, 10)) < 1e-3 and (spots[1] as Vector3).distance_to(Vector3(25, 0, 10)) < 1e-3,
		"the copies are selected and moved 5 m (%s)" % str(spots))
	t.check(SelectTool._v3(ed.doc.find(p1).item.pos).distance_to(Vector3(10, 0, 10)) < 1e-3 and SelectTool._v3(ed.doc.find(p2).item.pos).distance_to(Vector3(20, 0, 10)) < 1e-3,
		"the originals stay")
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "DUPLICATE 2 OBJECTS", "copy + move are one step (%s)" % ed.history.undo_name())
	ed.history.undo()
	t.check(ed.doc.data.props.size() == n0 and ed.selection.uids.is_empty(), "undo takes the copies away (and out of the selection)")
	await Sel.close_editor(t, ed)


func _alt(ed: TrackEditor, at: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.position = at
	b.alt_pressed = true
	ed.gizmo._unhandled_input(b)


func _alt_motion(ed: TrackEditor, at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.alt_pressed = true
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	ed.gizmo._unhandled_input(m)
