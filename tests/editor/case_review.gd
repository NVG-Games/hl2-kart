extends RefCounted
## editor/case_review (review fixes, CI, fake registries): the smaller fixes of the editor review.
## FIX buttons and steps name the issue's own fix (hazard_setup: DELETE / ADD THE SEE-SAW); the
## editor camera's own environment keeps the race's fog off the track (none in TOP VIEW) and the
## overlay ignores fog; crowd members show as stand-ins after a bake and the inspector's PEOPLE
## line follows the bakes; VIEW > GRID draws, VIEW > LABELS names the markers; the stored view is
## the perspective one; a failed drive says why and opens the drawer; SELECT's Delete keeps a
## closed loop at 3 points; DISCARD drops the autosave; the Esc that clears the trail does only
## that; a status message gives way to the step line; a hint that repeats the message goes; the
## closed loop's hints offer no DRAW; , and . turn objects; the menu has UNDO / REDO / SET
## THUMBNAIL; the readout stays in the free area; the complexity toast is one term a line; a save
## keeps the trail; a lone autosave .tmp is offered; a second Ctrl+S waits; G is saved; H says how
## many it hid; J acts on the hovered segment; the kart ghost is kart-sized with an arrow; WATCH A
## BOT LAP lands in the checklist; clearing the selection updates the status bar; the wording.

const NEEDS_CONTENT := false
const S := preload("res://tests/editor/case_select.gd")


func run(t: Node) -> void:
	var doc := S.test_doc()
	var ed: TrackEditor = await S.open_editor(t, doc)
	S.look_down(ed, Vector3.ZERO, 300.0)
	await t.frames(3)
	var u := S.uids_of(doc)
	ed.history.merge_window = -1.0
	_fix_labels(t, ed, u)
	await _fog(t, ed)
	await _crowds(t, ed)
	await _hazard_models(t, ed, u)
	await _view_flags(t, ed, u)
	_stored_view(t, ed)
	_failed_drive(t, ed)
	_loop_delete(t, ed, u)
	_discard(t, ed)
	_escape_trail(t, ed)
	await _status(t, ed)
	_hints(t, ed)
	_turn(t, ed, u)
	_menu(t, ed)
	_readout(t, ed)
	_complexity(t)
	_save_trail(t, ed)
	_lone_tmp(t, ed)
	await _double_save(t, ed)
	_grid_key(t, ed)
	_hide(t, ed, u)
	_jump_here(t, ed, u)
	_ghost(t, ed)
	_bot_lap(t, ed)
	await _selection_status(t, ed, u)
	_music(t, ed)
	_wording(t, ed)
	ed.history.merge_window = 1.0
	await S.close_editor(t, ed)


func _fix_labels(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var rep := LevelReport.new()
	rep.error("hazard_setup", "The ceiling turret needs a tunnel: move it to a green spot or delete it.", {"uid": 77, "type": "turret"}, "hazard_setup")
	rep.error("hazard_setup", "The see-saw stretch needs its see-saw: move it to a green spot or delete it.", {"uid": 78, "type": "seesaw_stretch"}, "hazard_setup")
	var vp := ed.ui.drawer
	vp.set_report(rep)
	var labels := vp.fix_buttons.map(func(b: Button) -> String: return b.text)
	t.check(labels == ["DELETE", "ADD THE SEE-SAW"], "the FIX buttons name the issue's own fix (%s)" % str(labels))
	var hu := ed.doc.new_uid()
	ed.doc.apply([LevelDoc.op_insert(["hazards"], -1, {"uid": hu, "type": "turret", "mount": "ceiling", "at": {"p": int(u.points[1]), "t": 0.5}, "side": 0})])
	ed.apply_fix({"fix": "hazard_setup", "type": "turret", "uid": hu})
	t.check(ed.history.undo_name() == "FIX: DELETE" and ed.doc.find(hu).is_empty(), "the FIX step says what it did (%s)" % ed.history.undo_name())
	ed.history.undo()
	ed.history.clear()
	vp.set_report(ed.build.report if ed.build != null else LevelReport.new())


func _fog(t: Node, ed: TrackEditor) -> void:
	for k in 120:
		if ed.view.env != null and ed.camera.environment != null:
			break
		await t.frames(1)
	var env := ed.camera.environment
	var src := ed.view.env
	t.check(src != null and env != null and env != src, "the editor camera has its own copy of the world's environment")
	if env == null or src == null:
		return
	var reach := ed.view_reach()
	t.check(env.fog_depth_begin >= reach + 199.0 and env.fog_depth_end >= reach + 1499.0,
		"its depth fog starts past the track (begin %d, end %d, reach %d)" % [int(env.fog_depth_begin), int(env.fog_depth_end), int(reach)])
	ed.camera.toggle_top(Vector3.ZERO)
	await t.frames(2)
	t.check(not ed.camera.environment.fog_enabled, "TOP VIEW: no fog")
	ed.camera.toggle_top(Vector3.ZERO)
	await t.frames(2)
	t.check(ed.camera.environment.fog_enabled == src.fog_enabled, "and back in perspective as the world has it")
	ed.set_tool("world")
	await t.frames(2)
	t.check(is_equal_approx(ed.camera.environment.fog_depth_begin, src.fog_depth_begin), "the WORLD tool shows the race's own fog")
	ed.set_tool("select")
	await t.frames(2)
	var mats := []
	for m in ed.draw._mats:
		mats.append((m as StandardMaterial3D).disable_fog)
	t.check(not mats.is_empty() and not (false in mats), "the overlay's materials ignore fog (%s)" % str(mats))


func _crowds(t: Node, ed: TrackEditor) -> void:
	ed.set_tool("crowds")
	var ct: CrowdsTool = ed.tools.crowds
	var gu := ct.place_group({"key": -1, "s": 120.0, "lat": 12.0})
	t.check(gu > 0, "(a crowd group placed)")
	ed.select(PackedInt32Array([gu]))
	ed.ui.inspector.rebuild()
	var done := [false]
	ed.bake_now(func(_b: LevelBuild) -> void: done[0] = true)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	for k in 30:
		if not ed.view.busy():
			break
		await t.frames(1)
	await t.frames(2)
	var n := (ed.build.data.get("crowds", []) as Array).size()
	t.log("crowd members baked: %d" % n)
	var mm := ed.view.crowd_mm
	t.check(mm != null and mm.multimesh.instance_count == n and (n == 0 or mm.visible),
		"the crowd's members stand in the view (%d of %d)" % [mm.multimesh.instance_count if mm != null else -1, n])
	var pl := ed.ui.inspector.box.find_child("People", true, false) as PromptLabel
	t.check(pl != null and pl.prompt == ct.people_text(), "the inspector's PEOPLE line follows the bake (%s)" % (pl.prompt if pl != null else "-"))
	ed.history.undo()
	ed.selection.clear()
	ed.set_tool("select")


func _hazard_models(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	var key := "hl1/sentry"
	if not Game.models.has(key):
		t.log("skip the hazard model check (no %s)" % key)
		return
	var hu := ed.doc.new_uid()
	ed.commit("ADD TURRET", [LevelDoc.op_insert(["hazards"], -1, {"uid": hu, "type": "turret", "mount": "floor",
		"at": {"p": int(u.points[2]), "t": 0.3}, "side": 1})])
	var done := [false]
	ed.bake_now(func(_b: LevelBuild) -> void: done[0] = true)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	await t.frames(2)
	var ht: HazardsTool = ed.tools.hazards
	var n: Node3D = ht.model_nodes().get(hu)
	t.check(n != null and is_instance_valid(n) and str(n.get_meta("model", "")) == key and n.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"a hazard shows its model where it stands, without collision")
	ed._set_hidden(PackedInt32Array([hu]))
	t.check(not ht.model_nodes().has(hu), "a hidden hazard's model goes")
	ed._set_hidden(PackedInt32Array())
	ed.history.undo()
	ed.bake_now(func(_b: LevelBuild) -> void: done[0] = false)
	t0 = Time.get_ticks_msec()
	while done[0] and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	t.check(not ht.model_nodes().has(hu), "a deleted hazard's model goes")


func _view_flags(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("select")
	ed.hover = EditorHit.new()
	ed.ui.view_flags["grid"] = false
	ed._redraw_overlay()
	var v0 := int(ed.draw.vertex_count().lines)
	t.check(v0 > 0, "the race's direction arrows and grid slots are drawn in every tool (%d)" % v0)
	ed.ui.view_flags["grid"] = true
	ed._redraw_overlay()
	var v1 := int(ed.draw.vertex_count().lines)
	t.check(v1 > v0 + 200, "VIEW > GRID draws the grid (%d -> %d)" % [v0, v1])
	ed.ui.view_flags["grid"] = false
	ed.set_labels(true)
	t.check(ed.markers.label_of.is_valid() and str(ed.markers.label_of.call(int(u.props[0]))) == "WOOD CRATE001A",
		"VIEW > LABELS names the markers (%s)" % (str(ed.markers.label_of.call(int(u.props[0]))) if ed.markers.label_of.is_valid() else "-"))
	ed.set_labels(false)
	t.check(not ed.markers.label_of.is_valid(), "and off again")


func _stored_view(t: Node, ed: TrackEditor) -> void:
	var xf := ed.camera.global_transform
	ed.camera.toggle_top(Vector3.ZERO)
	ed._store_view()
	t.check(ed.session.top_view and ed.session.camera.is_equal_approx(xf), "TOP VIEW stores the perspective view and a flag")
	ed.camera.toggle_top(Vector3.ZERO)
	ed._store_view()


func _failed_drive(t: Node, ed: TrackEditor) -> void:
	if ed.ui.drawer.visible:
		ed.ui.toggle_validation()
	ed.session.last_drive = {"failed": "The track could not be built: probe."}
	ed._show_last_drive()
	t.check(ed.last_toast == "The track could not be built: probe." and ed.ui.drawer.visible,
		"a drive that could not be built says why and opens the drawer (%s)" % ed.last_toast)
	ed.ui.toggle_validation()
	ed.status("")


func _loop_delete(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("select")
	var n0 := (ed.doc.data.road.points as Array).size()
	var sel := PackedInt32Array()
	for k in 6:
		sel.append(int(u.points[k]))
	ed.select(sel)
	SelectTool.delete_selection(ed)
	t.check((ed.doc.data.road.points as Array).size() == n0 and bool(ed.doc.data.road.closed),
		"SELECT's Delete keeps a closed loop at 3 points (ROAD's rule; %d points)" % (ed.doc.data.road.points as Array).size())


func _discard(t: Node, ed: TrackEditor) -> void:
	var a := ed.session.autosave_path()
	DirAccess.make_dir_recursive_absolute(CustomTracks.autosave_dir())
	LevelIO.save(ed.doc, a, {"autosave": true})
	t.check(FileAccess.file_exists(a), "(an autosave is there)")
	var went := [false]
	ed.ui._left("discard", func() -> void: went[0] = true)
	t.check(went[0] and not FileAccess.file_exists(a), "DISCARD moves the autosave away (no RECOVER card later)")


func _escape_trail(t: Node, ed: TrackEditor) -> void:
	ed.selection.clear()
	ed.trail = {"points": PackedVector3Array([Vector3.ZERO, Vector3.ONE]), "speeds": PackedFloat32Array()}
	ed.escape()
	t.check(ed.trail.is_empty() and ed.ui.menu == null, "the Esc that clears the trail opens no menu")


func _status(t: Node, ed: TrackEditor) -> void:
	ed.set_tool("road")
	ed.status("UNDO MOVE POINT")
	ed.set_tool("branch")
	t.check(ed.status_text == "", "a tool switch clears the status message (the step line shows)")
	ed.status("GRID OFF")
	ed._status_t = 0.05
	await t.wait(0.2)
	await t.frames(2)
	t.check(ed.status_text == "", "a status message gives way to the step line after a while")
	ed.status("Click the road where the start line goes", true)
	t.check(ed._status_t < 0.0, "a sticky prompt has no timeout")
	ed.status("")
	ed.set_tool("select")


func _hints(t: Node, ed: TrackEditor) -> void:
	t.check(EditorUI.hint_repeats("CLICK ADD A CRATE ROW", "Click a road to add a crate row"), "a hint that repeats the message is found")
	t.check(not EditorUI.hint_repeats("{ed_cancel} CANCEL", "Click a road to add a crate row"), "(another one is not)")
	ed.set_tool("road")
	var h := EditorHit.new()
	h.hit = true
	h.what = "terrain"
	var txt := str((ed.tools.road as RoadTool).hints(h))
	t.check(txt.find("DRAW") < 0, "ROAD on a closed loop offers no DRAW (%s)" % txt)
	var ht: HazardsTool = ed.tools.hazards
	var hs := str(ht.hints(S.hit_at(ed, Vector3(150, 1, 0), "road")))
	t.check(hs.find("PLACE A ") < 0, "the hazard hints have no 'A APACHE' (%s)" % hs)
	ed.set_tool("select")


func _turn(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("objects")
	var p: int = u.props[0]
	ed.select(PackedInt32Array([p]))
	var y0 := float(ed.doc.find(p).item.get("yaw", 0.0))
	S.key(ed, KEY_COMMA)
	var y1 := float(ed.doc.find(p).item.get("yaw", 0.0))
	t.check(is_equal_approx(ObjectsTool.wrap_deg(y1 - y0), 15.0) and ed.history.undo_name() == "ROTATE OBJECT",
		", turns the selected object by the angle step (%.1f -> %.1f, %s)" % [y0, y1, ed.history.undo_name()])
	S.key(ed, KEY_PERIOD)
	t.check(is_equal_approx(float(ed.doc.find(p).item.get("yaw", 0.0)), y0), ". turns it back")
	ed.history.undo()
	ed.history.undo()
	ed.selection.clear()
	ed.set_tool("select")


func _menu(t: Node, ed: TrackEditor) -> void:
	var ids := EditorMenu.MAIN.map(func(e: Array) -> String: return e[1])
	t.check("undo" in ids and "redo" in ids and "thumb" in ids, "the EDITOR MENU has UNDO, REDO and SET THUMBNAIL FROM CAMERA (the pad's way)")
	var p: int = int(ed.doc.data.props[0].uid)
	ed.select(PackedInt32Array([p]))
	S.key(ed, KEY_PAGEUP)
	var m := EditorMenu.new(ed)
	var texts := m.items.map(func(b: Button) -> String: return b.text)
	t.check("UNDO RAISE OBJECT" in texts, "UNDO names its step (%s)" % str(texts))
	m.free()
	ed.history.undo()
	ed.selection.clear()


func _readout(t: Node, ed: TrackEditor) -> void:
	var fr := ed.free_rect()
	var at := Vector2(fr.end.x - 30.0, fr.position.y + 10.0)
	var sz := Vector2(300, 24)
	var pos := RoadTool.readout_pos(at, sz, fr)
	t.check(fr.encloses(Rect2(pos, sz)) and pos.x + sz.x <= at.x, "the drag readout flips left and below near the panel and the top (%s)" % str(pos))


func _complexity(t: Node) -> void:
	var c := EditorUI.complexity_of({"props": 168, "lights": 3, "people": 0}, 513)
	var txt := EditorUI.complexity_lines(c)
	var lines := txt.split("\n")
	t.check(lines.size() >= 3 and txt.find("168" + String.chr(0xA0) + "/" + String.chr(0xA0) + "1500") >= 0
		and txt.find("513" + String.chr(0xA0) + "x" + String.chr(0xA0) + "513") >= 0,
		"the COMPLEXITY breakdown is one term a line, no break inside a number pair")


func _save_trail(t: Node, ed: TrackEditor) -> void:
	ed.trail = {"points": PackedVector3Array([Vector3.ZERO, Vector3.ONE]), "speeds": PackedFloat32Array()}
	ed.session.saving_meta = true
	ed.doc.apply([LevelDoc.op_set(["modified"], 12345), LevelDoc.op_set(["app"], "0.3.0")])
	ed.session.saving_meta = false
	t.check(not ed.trail.is_empty(), "a save's own meta keeps the last drive's trail")
	ed.doc.apply([LevelDoc.op_set(["name"], "Select 2")])
	t.check(ed.trail.is_empty(), "(an edit clears it)")
	ed.doc.apply([LevelDoc.op_set(["name"], "Select")])


func _lone_tmp(t: Node, ed: TrackEditor) -> void:
	var dir := CustomTracks.autosave_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var d := LevelDoc.blank("LONE TMP", 512.0, 0)
	d.data["guid"] = "feedfacefeedfacefeedfacefeedface"
	var p := dir.path_join(d.data.guid + LevelIO.EXT)
	LevelIO.save(d, p, {"autosave": true})
	DirAccess.rename_absolute(p, p + ".tmp")
	var offered := false
	for r in EditorSession.recoveries():
		if str(r.name) == "LONE TMP":
			offered = true
	t.check(offered and FileAccess.file_exists(p), "a lone autosave .tmp is put in place and offered")
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(p + ".tmp")


func _double_save(t: Node, ed: TrackEditor) -> void:
	var s := ed.session
	var rev0 := ed.doc.revision
	ed.save()
	ed.save()
	var t0 := Time.get_ticks_msec()
	while (s.saving or ed._save_pending) and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	t.check(ed.doc.revision == rev0 + 1 and s.path != "", "two quick saves write once (revision %d -> %d)" % [rev0, ed.doc.revision])
	ed.trail = {"points": PackedVector3Array([Vector3.ZERO, Vector3.ONE]), "speeds": PackedFloat32Array()}
	ed.save()
	t0 = Time.get_ticks_msec()
	while (s.saving or ed._save_pending) and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	t.check(not ed.trail.is_empty(), "SAVE keeps the last drive's trail")
	ed.clear_trail()
	if s.path != "":
		DirAccess.remove_absolute(s.path)
		s.path = ""
		CustomTracks.refresh()
	if s.path != "":
		DirAccess.remove_absolute(s.path)
		s.path = ""
		CustomTracks.refresh()


func _grid_key(t: Node, ed: TrackEditor) -> void:
	var on0 := bool(ed.snap.get("on", true))
	S.key(ed, KEY_G)
	var saved = Game.settings.get("editor_snap", {})
	t.check(bool(ed.snap.on) != on0 and saved is Dictionary and bool(saved.get("on", true)) == bool(ed.snap.on), "G is saved like the GRID button")
	S.key(ed, KEY_G)


func _hide(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("select")
	ed.select(PackedInt32Array([int(u.props[1])]))
	S.key(ed, KEY_H)
	ed.ui._update_status()
	t.check(ed.last_toast.begins_with("Hidden 1") and ed.ui.sel_label.text.find("1 HIDDEN") >= 0,
		"H says what it hid (%s; %s)" % [ed.last_toast, ed.ui.sel_label.text])
	ed._set_hidden(PackedInt32Array())


func _jump_here(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.set_tool("road")
	var rt: RoadTool = ed.tools.road
	var r := ed.road(-1)
	ed.select(PackedInt32Array([int(u.points[0])]))
	rt.segment = int(u.points[0])
	var h := EditorHit.new()
	h.hit = true
	h.what = "road"
	h.road = -1
	h.sample = r.idx(r.length * 0.55)
	h.pos = r.pos[h.sample]
	var owner := rt.segment_owner(h)
	ed.hover = h
	S.key(ed, KEY_J)
	t.check(owner != int(u.points[0]) and ed.doc.find(owner).item.get("gap") is Dictionary and not (ed.doc.find(int(u.points[0])).item.get("gap") is Dictionary),
		"J puts the jump on the hovered segment, not the selected one")
	ed.history.undo()
	ed.hover = EditorHit.new()
	rt.segment = 0
	ed.selection.clear()
	ed.set_tool("select")


func _ghost(t: Node, ed: TrackEditor) -> void:
	ed.camera._update_ghost()
	var g := ed.camera._ghost
	var bm := g.mesh as BoxMesh if g != null else null
	t.check(bm != null and bm.size.is_equal_approx(Vector3(1.8, 1.0, 3.0)) and g.get_node_or_null("Arrow") != null,
		"the pad's kart ghost is kart-sized with an arrow on its nose")


func _bot_lap(t: Node, ed: TrackEditor) -> void:
	ed.session.last_drive = {"from": "watch", "finished": false, "stuck_at_s": 120.0, "rescues": 1}
	ed._show_last_drive()
	var it := ed.build.report.first("bot_lap") if ed.build != null and ed.build.report != null else {}
	var pinned := false
	for e in ed.markers.entries(EditorMarkers.ISSUES):
		var iss := ed.markers.issue(int(e.uid))
		if str(iss.get("code", "")) == "bot_lap":
			pinned = true
	t.check(not it.is_empty() and pinned, "WATCH A BOT LAP's result is in the checklist with a pin (%s)" % str(it.get("text", "-")))
	ed.clear_trail()


func _selection_status(t: Node, ed: TrackEditor, u: Dictionary) -> void:
	ed.select(PackedInt32Array([int(u.props[0])]))
	await t.frames(2)
	ed.selection.clear()
	await t.frames(2)
	t.check(ed.ui.sel_label.text == "", "clearing the selection clears '1 selected' at once (%s)" % ed.ui.sel_label.text)


func _music(t: Node, ed: TrackEditor) -> void:
	if not t.content():
		t.log("skip the music check (no content)")
		return
	Game.stop_music()
	t.check(ed.resume_music() and Game.now_playing != "", "the editor starts the menu music again after a drive stopped it (%s)" % Game.now_playing)
	Game.stop_music()
	ed.ui.view_flags["music"] = false
	t.check(not ed.resume_music() and Game.now_playing == "", "VIEW > MUSIC off keeps it quiet")
	ed.ui.view_flags["music"] = true


func _wording(t: Node, ed: TrackEditor) -> void:
	t.check(RoadTool.BARRIER_NAMES[0] == RoadTool.GRIPS[0], "BARRIER and GRIP both say STYLE'S")
	t.check(HelpOverlay.DIM >= 0.94, "the help overlay hides the editor behind it")
	t.check(Outliner.model_name("props_c17/lamppost03a_off") == "LAMPPOST03A OFF", "the outliner writes model names as the dropdowns do")
