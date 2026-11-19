extends Node
## The one visual-review window of the track editor (9.5): walks the screens in order and saves
## PNGs to user://editor_shots/ (NN_name.png, plus index.txt with the list; earlier pictures are
## removed first, never by a dry run, which writes index_dry.txt). Run it once, windowed,
## at 1600 x 900:
##   godot --path . --resolution 1600x900 res://tests/editor_shots.tscn
## With --headless (or `-- dry`) it walks the same screens and saves nothing: a check that every
## step still runs. Every step has a time limit; one that fails or stalls is listed and the walk
## goes on. Sound is muted; MY TRACKS is the test folder (user://tracks_test), emptied first.
##
## The shots: 1 the menu with TRACK EDITOR; 2 the home on TEMPLATES with the first-visit card; 3 the
## home's MY TRACKS (three tracks, + NEW TRACK) with details and HOST; 4 the editor on the oval,
## framed, ROAD, the hint card; 5 ROAD hover over a point with the status-bar hints; 6 an open
## road's rubber band and the CLOSE LOOP glow; 7 a point drag with its readout and the on-top centre
## line; 8 the segment inspector (barriers, a jump); 9 top view, markers and the racing line; 10
## BRANCH on the hills (tint, noses); 11 TERRAIN brush with SHOW CARVE; 12 PAINT and its layers; 13
## OBJECTS' catalog drawer and a stamp ghost; 14 ALONG ROAD lamp posts; 15 ITEMS: a crate row, a pad
## with its red warning, a low-gravity zone; 16 HAZARDS: the see-saw tint and a turret's SIDE / ZONE /
## DIFFICULTY inspector; 17 CROWDS: a stand and PEOPLE; 18 WORLD: WHITE FOREST on the hills; 19 the
## validation drawer, FIX buttons and "!" pins; 20 COMPLEXITY; 21 the help overlay; 22 pad FLY with
## the reticle and the kart ghost; 23 a test drive's pause menu with the errors line; 24 back in the
## editor with the toast and the trail; 25 NEW RACE with the MY TRACKS card picked; 26 the lobby (a
## friend at 42 % with the time left and another at NO TRACK; the friend's RETRY; the host's START
## RACE locked with its status line); 27 the server browser's TRACK column (fake replies).


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Walker.new(OS.get_cmdline_user_args()))


## Lives under the root so the scene changes (menu, editor, race) do not free it.
class Walker:
	extends Node

	const OUT := "user://editor_shots"
	const MENU := "res://scenes/main.tscn"
	const EDITOR := "res://scenes/editor.tscn"
	const RACE := "res://scenes/race.tscn"
	const CaseSelect := preload("res://tests/editor/case_select.gd")
	const STEP_SECONDS := 60.0

	var dry := false
	var only := PackedStringArray()   # `-- steps a,b,c`: just these steps (with what they need), for a dry check
	var shots: Array = []          # [file, note]
	var failed: Array = []         # step names that failed or stalled
	var _done := false
	var _n := 0
	var ed: TrackEditor
	var mine := {}                 # name -> id of the three own tracks
	var _keep := {}

	func _init(args: PackedStringArray) -> void:
		name = "EditorShots"
		process_mode = Node.PROCESS_MODE_ALWAYS
		dry = args.has("dry") or DisplayServer.get_name() == "headless"
		var k := args.find("steps")
		if k >= 0 and k + 1 < args.size():
			only = args[k + 1].split(",", false)

	func _ready() -> void:
		_keep = {"editor_hints": Game.settings.get("editor_hints", []), "check_updates": Game.settings.get("check_updates", true),
			"tutorial_seen": Game.settings.get("tutorial_seen", false), "master_server": Game.settings.get("master_server", ""),
			"track": Game.settings.get("track", ""), "track_guid": Game.settings.get("track_guid", "")}
		Game.settings["editor_hints"] = []
		Game.settings["check_updates"] = false
		Game.settings["tutorial_seen"] = true
		Game.settings["master_server"] = ""
		AudioServer.set_bus_mute(0, true)
		if not dry:
			get_window().size = Vector2i(1600, 900)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		if not dry:
			_clear_out()   # a dry run never touches a real run's pictures
		_wipe(CustomTracks.mine_dir())
		CustomTracks.auto_check = false
		CustomTracks.reset()
		var s := EditorSession.current()
		s.close()
		s.return_to = ""
		s.host_track = ""
		print("editor_shots: %s, out %s" % ["dry run (nothing saved)" if dry else "windowed", ProjectSettings.globalize_path(OUT)])
		var steps := [
			["menu", _s_menu], ["home_templates", _s_home_templates], ["home_mine", _s_home_mine],
			["editor_oval", _s_editor_oval], ["road_hover", _s_road_hover], ["open_road", _s_open_road],
			["point_drag", _s_point_drag], ["segment", _s_segment], ["top_view", _s_top_view],
			["branch_hills", _s_branch], ["terrain", _s_terrain], ["paint", _s_paint], ["objects", _s_objects],
			["along_road", _s_along], ["items", _s_items], ["hazards", _s_hazards], ["crowds", _s_crowds],
			["world", _s_world], ["validation", _s_validation], ["complexity", _s_complexity], ["help", _s_help],
			["pad_fly", _s_pad_fly], ["test_drive_pause", _s_drive_pause], ["back_in_editor", _s_back],
			["new_race", _s_new_race], ["lobby", _s_lobby], ["server_browser", _s_browser]]
		for st in steps:
			if not only.is_empty() and not only.has(str(st[0])):
				continue
			await _step(str(st[0]), st[1])
		_finish()

	# ---------------------------------------------------------------- the frame of a step

	func _step(step_name: String, fn: Callable) -> void:
		_done = false
		fn.call()
		var t0 := Time.get_ticks_msec()
		while not _done and Time.get_ticks_msec() - t0 < int(STEP_SECONDS * 1000.0):
			await get_tree().process_frame
		if not _done:
			failed.append(step_name)
			print("editor_shots: step %s did not finish" % step_name)

	func _ok() -> void:
		_done = true

	## Saves the window as NN_<name>.png (dry: only listed).
	func shot(shot_name: String, note: String, settle := 0.5) -> void:
		await _frames(4)
		await get_tree().create_timer(settle, true, false, true).timeout
		_n += 1
		var file := "%02d_%s.png" % [_n, shot_name]
		if not dry:
			var img := get_viewport().get_texture().get_image()
			if img != null and not img.is_empty():
				img.save_png(OUT.path_join(file))
			else:
				note += " (no image)"
		shots.append([file, note])
		print("editor_shots: %s  %s" % [file, note])

	func _finish() -> void:
		var lines := PackedStringArray()
		for sh in shots:
			lines.append("%s\t%s" % [sh[0], sh[1]])
		if not failed.is_empty():
			lines.append("FAILED STEPS: " + ", ".join(PackedStringArray(failed)))
		var f := FileAccess.open(OUT.path_join("index_dry.txt" if dry else "index.txt"), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			f.close()
		print("editor_shots: %d shots, %d failed steps%s" % [shots.size(), failed.size(),
			"" if failed.is_empty() else " (" + ", ".join(PackedStringArray(failed)) + ")"])
		_reset_net()
		var s := EditorSession.current()
		s.close()
		s.return_to = ""
		for k in _keep:
			Game.settings[k] = _keep[k]
		Game.save_settings()
		_wipe(CustomTracks.mine_dir())
		CustomTracks.reset()
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().quit(0 if failed.is_empty() else 1)

	# ---------------------------------------------------------------- helpers

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout

	func _until(cond: Callable, sec: float) -> bool:
		var t0 := Time.get_ticks_msec()
		while not cond.call():
			if Time.get_ticks_msec() - t0 > int(sec * 1000.0):
				return false
			await get_tree().process_frame
		return true

	func _scene(path: String, sec := 30.0) -> Node:
		var ok := await _until(func() -> bool:
			var cs := get_tree().current_scene
			return cs != null and cs.scene_file_path == path and cs.is_node_ready(), sec)
		return get_tree().current_scene if ok else null

	func _wipe(dir: String) -> void:
		if not dir.begins_with("user://tracks_test"):
			return
		var d := DirAccess.open(dir)
		if d == null:
			return
		d.include_hidden = true
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
		for sub in d.get_directories():
			_wipe(dir.path_join(sub))
			DirAccess.remove_absolute(dir.path_join(sub))

	func _clear_out() -> void:
		var d := DirAccess.open(OUT)
		if d == null:
			return
		for f in d.get_files():
			if f.ends_with(".png") or f == "index.txt":
				DirAccess.remove_absolute(OUT.path_join(f))

	func _menu() -> Node:
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU)
		var m := await _scene(MENU)
		await _frames(3)
		Game.stop_music()
		return m

	## A new unsaved track from a template in the editor scene, its first bake shown.
	func _editor_on(template: String) -> TrackEditor:
		var s := EditorSession.current()
		s.close()
		s.create(template)
		get_tree().change_scene_to_file(EDITOR)
		var e := await _scene(EDITOR) as TrackEditor
		if e == null:
			return null
		await _settle(e)
		Game.stop_music()
		return e

	## Until the editor has a bake of the current revision on show.
	func _settle(e: TrackEditor, sec := 30.0) -> void:
		await _until(func() -> bool: return e.build != null and e.card == "" and not e.baking() and not e.view.busy(), sec)
		await _frames(3)

	func _main(e: TrackEditor) -> LevelRoad:
		return LevelFixes.road_of(e.build, -1) if e != null else null

	## The screen spot of a world point.
	func _screen(p: Vector3) -> Vector2:
		return ed.camera.unproject_position(p)

	## The mouse over a world point (an editor motion event: hover, hints, ghosts).
	func _hover_at(p: Vector3, mask := 0) -> void:
		_hover_screen(_screen(p), mask)

	func _hover_screen(sp: Vector2, mask := 0) -> void:
		var m := InputEventMouseMotion.new()
		m.position = sp
		m.global_position = sp
		m.button_mask = mask
		ed._unhandled_input(m)

	## An EditorHit on the main road s metres along, lat across.
	func _road_hit(s_m: float, lat := 0.0) -> EditorHit:
		var r := _main(ed)
		var i := r.idx(s_m)
		var h := CaseSelect.hit_at(ed, r.surface(i, lat), "road")
		h.road = -1
		h.sample = i
		h.s = r.s[i]
		h.lat = lat
		return h

	## The camera looking at a spot from the side and above (pitch deg down, dist m away).
	func _look(at: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
		var b := Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0.0))
		ed.camera.go_to(Transform3D(b, at + b.z * dist))

	func _frame_all() -> void:
		var aabb := ed.track_aabb()
		if aabb.size.length() > 1.0:
			ed.frame(aabb)

	## An own track written to MY TRACKS (as case_home), its facts from a real compile.
	func _own(nm: String, tid: String, ago: int) -> String:
		var d := LevelTemplates.make(tid, nm)
		d.data["author"] = "Sasha"
		d.data["modified"] = int(Time.get_unix_time_from_system()) - ago
		var b := LevelCompiler.compile(d, {"id": CustomTracks.EDIT_ID})
		var facts := b.facts() if b != null else {}
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CustomTracks.mine_dir()))
		var p := LevelIO.free_path(CustomTracks.mine_dir(), nm)
		var hdr := {"outline": TrackList.outline_of_doc(d)}
		for k in facts:
			hdr[k] = facts[k]
		if LevelIO.save(d, p, hdr) != OK:
			return ""
		return CustomTracks.note_saved(p, facts)

	# ---------------------------------------------------------------- 1-3 the menu and the home

	func _s_menu() -> void:
		var m := await _menu()
		await _wait(1.0)
		var items: VBoxContainer = m.items
		if items.get_child_count() > 3:
			(items.get_child(3) as Control).grab_focus()
		await shot("menu", "the main menu with TRACK EDITOR (focused)")
		_ok()

	func _s_home_templates() -> void:
		var m := get_tree().current_scene
		m._open_editor_home()
		await _until(func() -> bool: return m.home != null and m.home.is_visible_in_tree(), 5.0)
		await shot("home_templates", "TRACK EDITOR home on TEMPLATES (no own track) with the first-visit card", 0.8)
		m.home.back.emit()
		await _frames(2)
		_ok()

	func _s_home_mine() -> void:
		mine["CANAL RUN"] = _own("CANAL RUN", "oval", 3000)
		mine["CITY BLOCKS"] = _own("CITY BLOCKS", "city", 2000)
		mine["HILL CLIMB"] = _own("HILL CLIMB", "hills", 1000)
		CustomTracks.refresh(true)
		var m := get_tree().current_scene
		m._open_editor_home()
		await _until(func() -> bool: return m.home != null and m.home.is_visible_in_tree(), 5.0)
		var h = m.home
		var cid := str(mine["CANAL RUN"])
		if h.list.index_of(cid) >= 0:
			h.list.select(h.list.index_of(cid))
		await _wait(1.5)   # the thumbnails decode on a worker
		await shot("home_mine", "MY TRACKS: three tracks + NEW TRACK, CANAL RUN's details, HOST among the buttons", 0.5)
		h.back.emit()
		await _frames(2)
		_ok()

	# ---------------------------------------------------------------- 4-9 the editor on the oval

	func _s_editor_oval() -> void:
		ed = await _editor_on("oval")
		if ed == null:
			return
		await _wait(0.8)
		await shot("editor_oval", "the editor on the oval, framed whole, ROAD active, ROAD's hint card")
		_ok()

	func _s_road_hover() -> void:
		var pts: Array = ed.doc.data.road.points
		var p := ItemsTool._v3(pts[1].pos)
		_look(p, 30.0, 40.0, 140.0)
		await _frames(3)
		_hover_at(p)
		await _frames(3)
		_hover_at(p)
		await shot("road_hover", "ROAD: the mouse over a point (orange), what a click / drag does in the status bar")
		_ok()

	func _s_open_road() -> void:
		ed.commit("OPEN LOOP", [LevelDoc.op_set(["road", "closed"], false)])
		ed.bake_soon(0.0)
		await _settle(ed)
		var pts: Array = ed.doc.data.road.points
		var a := ItemsTool._v3(pts[0].pos)
		var b := ItemsTool._v3(pts[-1].pos)
		_look((a + b) * 0.5, 0.0, 55.0, 260.0)
		await _frames(3)
		# beside the first point, off the road: the other end glows
		var rt := ed.tools["road"] as RoadTool
		var c := _screen(b)   # the last point (the first one has the start gantry on it)
		var found := false
		var seen := []
		var toward := (_screen(a) - c).normalized()
		for d in [toward * 11.0, toward * 9.0 + toward.orthogonal() * 6.0, toward * 9.0 - toward.orthogonal() * 6.0, Vector2(11, 0),
				Vector2(-11, 0), Vector2(0, 11), Vector2(0, -11)]:
			_hover_screen(c + d)
			await _frames(3)
			var h := ed.hover
			seen.append("%s/%d" % [h.what if h != null else "-", rt.close_target(h) if h != null else 0])
			if h != null and (not h.hit or h.what in ["terrain", "water", ""]) and rt.close_target(h) != 0:
				found = true
				break
		if not found:
			# every spot within 12 px is road or verge here: a ground hover beside the end point, as a
			# mouse a few pixels further out would give at this zoom
			var h := CaseSelect.hit_at(ed, b, "terrain")
			h.screen = c + toward * 8.0
			ed.hover = h
			ed.hover_changed.emit(h)
			ed.redraw()
			if ed.ui != null:
				ed.ui.refresh_status()
			found = rt.close_target(h) != 0
			print("editor_shots: open road hover spots %s; a ground hover set (glow %s)" % [str(seen), str(found)])
		await shot("open_road", "an open road: the CLOSE LOOP glow on the other end%s" % ("" if found else " (no glow spot found: the rubber band)"))
		ed.history.undo()
		ed.bake_soon(0.0)
		await _settle(ed)
		_ok()

	func _s_point_drag() -> void:
		var pts: Array = ed.doc.data.road.points
		var p := ItemsTool._v3(pts[2].pos)
		_look(p, 20.0, 45.0, 220.0)
		await _frames(3)
		var sp := _screen(p)
		_hover_screen(sp)
		await _frames(2)
		CaseSelect.button(ed, sp, true)
		for k in 6:
			_hover_screen(sp + Vector2(10.0 * (k + 1), -4.0 * (k + 1)), MOUSE_BUTTON_MASK_LEFT)
			await _frames(2)
		await shot("point_drag", "dragging a point: the readout (R, GRADE, WIDE, SEGMENT) and the centre line on top", 0.3)
		CaseSelect.button(ed, sp + Vector2(60, -24), false)
		await _frames(2)
		ed.history.undo()
		ed.bake_soon(0.0)
		await _settle(ed)
		_ok()

	func _s_segment() -> void:
		var r := _main(ed)
		var best := 0
		for k in r.seg_len.size():
			if r.seg_len[k] > r.seg_len[best]:
				best = k
		var uid := r.point_uids[best]
		var path := ["road", "points", "#%d" % uid]
		ed.commit("ADD JUMP", [LevelDoc.op_set(path + ["gap"], {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0})])
		ed.bake_soon(0.0)
		await _settle(ed)
		r = _main(ed)
		var mid := r.pos[r.seg_first[best] + (r.seg_first[(best + 1) % r.seg_first.size()] - r.seg_first[best]) / 2] if best + 1 < r.seg_first.size() else r.pos[r.seg_first[best]]
		var rt := ed.tools["road"] as RoadTool
		rt.select_segment(uid)
		_look(mid, 60.0, 30.0, 110.0)
		await _wait(0.4)
		await shot("segment", "the segment inspector: STYLE, BARRIER LEFT / RIGHT, the jump's read-out")
		_ok()

	func _s_top_view() -> void:
		ed.selection.clear()
		ed.show_line = true
		ed.redraw()
		var aabb := ed.track_aabb()
		ed.camera.toggle_top(aabb.get_center())
		await _wait(0.6)
		_frame_all()
		await _wait(0.6)
		await shot("top_view", "TOP VIEW: 14 px markers and the racing line (F4)")
		ed.camera.toggle_top(aabb.get_center())
		ed.show_line = false
		ed.redraw()
		await _frames(2)
		_ok()

	# ---------------------------------------------------------------- 10-18 on the hills

	func _s_branch() -> void:
		ed = await _editor_on("hills")
		if ed == null:
			return
		ed.set_tool("branch")
		_frame_all()
		await _wait(0.8)
		await shot("branch_hills", "BRANCH on the hills: the green / red fork tint and the noses of its branch")
		_ok()

	## A spot on the ground 40 m beside the main road, s metres along.
	func _beside(s_m: float, off := 40.0) -> Vector3:
		var r := _main(ed)
		var i := r.idx(s_m)
		var q := r.pos[i] + r.flat_right[i] * (r.width[i] * 0.5 + off)
		var t := ed.terrain()
		if t != null:
			var y := t.height_at(q.x, q.z)
			if not is_nan(y):
				q.y = y
		return q

	func _s_terrain() -> void:
		ed.set_tool("terrain")
		var q := _beside(300.0, 30.0)
		_look(q, 40.0, 40.0, 160.0)
		await _frames(3)
		_hover_at(q)
		await _frames(3)
		_hover_at(q)
		await shot("terrain", "TERRAIN: the brush circle with its falloff ring, SHOW CARVE on")
		_ok()

	func _s_paint() -> void:
		ed.set_tool("paint")
		var q := _beside(300.0, 30.0)
		_hover_at(q)
		await _frames(3)
		_hover_at(q)
		await shot("paint", "PAINT: the layer picker in the tool options, the brush on the ground")
		_ok()

	func _s_objects() -> void:
		ed.set_tool("objects")
		var ot := ed.tools["objects"] as ObjectsTool
		var key := _model_like(["props_junk/wood_crate001a", "props_c17/oildrum001", "props_junk/trafficcone001a"])
		if key != "":
			ot.pick_model(key)
		var q := _beside(450.0, 12.0)
		_look(q, 70.0, 35.0, 60.0)
		await _frames(3)
		_hover_at(q)
		await _wait(4.0)   # thumbnails render one a frame
		_hover_at(q)
		await shot("objects", "OBJECTS: the catalog drawer with thumbnails, a stamp ghost of %s" % key)
		_ok()

	## The first of these models this install has, else any lamp / first model ("" none).
	func _model_like(keys: Array) -> String:
		var models: Dictionary = Game.models
		for k in keys:
			if models.has(k):
				return str(k)
		for k in models:
			if str(k).contains("lamp") or str(k).contains("light_post"):
				return str(k)
		return str(models.keys()[0]) if not models.is_empty() else ""

	func _s_along() -> void:
		var ot := ed.tools["objects"] as ObjectsTool
		ot.set_mode("along")
		var lamp := _model_like(["props_c17/lamppost03a_off", "props_c17/lamppost03a_on", "props_wasteland/light_spotlight01_lamp"])
		if lamp != "":
			ot.pick_model(lamp)
		var made := ot.along(-1, 500.0, 650.0, 1)
		if not made.is_empty():
			ed.select(made)
		await _wait(0.5)
		ed.bake_soon(0.0)
		await _settle(ed)
		var r := _main(ed)
		_look(r.pos[r.idx(575.0)], 100.0, 25.0, 120.0)
		await _wait(0.6)
		await shot("along_road", "ALONG ROAD: %d lamp posts (%s) every 20 m on the right, one group" % [made.size(), lamp])
		ot.set_mode("stamp")
		_ok()

	func _s_items() -> void:
		ed.set_tool("items")
		var it := ed.tools["items"] as ItemsTool
		var r := _main(ed)
		var row := it.place_row(it.road_spot(_road_hit(150.0)))
		var pad := it.place_pad(it.road_spot(_road_hit(4.0, 2.0)), true)
		var zone := it.place_zone(it.road_spot(_road_hit(260.0)))
		ed.select(PackedInt32Array([pad]))
		ed.bake_soon(0.0)
		await _settle(ed)
		_look(r.pos[r.idx(120.0)], -60.0, 45.0, 190.0)
		await _wait(0.6)
		await shot("items", "ITEMS: a crate row (%d), a pad by the grid in red (%d, selected), a low-gravity zone (%d)" % [row, pad, zone])
		_ok()

	func _s_hazards() -> void:
		ed.set_tool("hazards")
		var ht := ed.tools["hazards"] as HazardsTool
		ht.set_choice("turret")
		var u := ht.place(_road_hit(380.0, 4.0))
		ht.set_choice("seesaw")
		ed.bake_soon(0.0)
		await _settle(ed)
		if u > 0:
			ed.select(PackedInt32Array([u]))
		var r := _main(ed)
		_look(r.pos[r.idx(380.0)], -30.0, 50.0, 260.0)
		_hover_at(r.pos[r.idx(330.0)])
		await _wait(0.6)
		await shot("hazards", "HAZARDS: SEE-SAW BRIDGE chosen (green / red segments), a turret's SIDE / ZONE / DIFFICULTY inspector")
		_ok()

	func _s_crowds() -> void:
		ed.set_tool("crowds")
		var ct := ed.tools["crowds"] as CrowdsTool
		var u := ct.place_group(ct._h.road_spot(_road_hit(60.0, 6.0)))
		if u > 0:
			ed.commit("CROWD", [ItemsTool.op_field("crowds", u, "rows", 4), ItemsTool.op_field("crowds", u, "length", 40.0),
				ItemsTool.op_field("crowds", u, "sit", 0.5)])
			ed.select(PackedInt32Array([u]))
		ed.bake_soon(0.0)
		await _settle(ed)
		var r := _main(ed)
		_look(r.pos[r.idx(60.0)], -100.0, 25.0, 70.0)
		await _wait(1.0)
		await shot("crowds", "CROWDS: a 4-row stand beside the start and PEOPLE n / 450")
		_ok()

	func _s_world() -> void:
		ed.set_tool("world")
		var wt := ed.tools["world"] as WorldTool
		wt.apply_theme("whiteforest")
		ed.bake_soon(0.0)
		await _settle(ed)
		ed.selection.clear()
		_frame_all()
		await _wait(1.2)
		await shot("world", "WORLD: THEME WHITE FOREST on the hills")
		_ok()

	# ---------------------------------------------------------------- 19-24 drawer, help, pad, drive

	func _s_validation() -> void:
		ed.set_tool("hazards")
		var ht := ed.tools["hazards"] as HazardsTool
		var m := _main(ed)
		# a ceiling turret on an open road: a setup error with a FIX
		var hz := ht.new_hazard(HazardsTool.choice_of("turret_ceiling"), m, 700.0, 0.0)
		ed.commit("ADD CEILING TURRET", [ItemsTool.op_add("hazards", hz)])
		ed.bake_soon(0.0)
		await _settle(ed)
		ed.set_tool("select")
		if ed.ui != null:
			ed.ui.toggle_validation()
		_frame_all()
		await _wait(0.8)
		await shot("validation", "the validation drawer (errors, warnings, FIX buttons) and the \"!\" pins")
		if ed.ui != null:
			ed.ui.toggle_validation()
		_ok()

	func _s_complexity() -> void:
		if ed.ui != null and ed.ui.complexity_box != null:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ed.ui.complexity_box.gui_input.emit(ev)
		await shot("complexity", "COMPLEXITY clicked: the breakdown toast", 0.4)
		_ok()

	func _s_help() -> void:
		if ed.ui != null:
			ed.ui.open_help()
		await shot("help", "the help overlay: keyboard column with modifier keycaps, the Xbox pad column")
		if ed.ui != null:
			ed.ui.open_help()
		await _frames(2)
		_ok()

	func _s_pad_fly() -> void:
		var m := _main(ed)
		_look(m.pos[m.idx(200.0)] + Vector3.UP * 6.0, 0.0, 12.0, 40.0)
		await _frames(2)
		for down in [true, false]:
			var e := InputEventJoypadButton.new()
			e.device = 1
			e.button_index = JOY_BUTTON_LEFT_STICK
			e.pressed = down
			e.pressure = 1.0 if down else 0.0
			Input.parse_input_event(e)
			await _frames(2)
		await _wait(0.6)
		await shot("pad_fly", "pad FLY (a synthetic pad): the reticle and the kart ghost at the aimed spot (flying %s)" % str(ed.camera.flying()))
		var mm := InputEventMouseMotion.new()
		mm.position = Vector2(800, 450)
		Input.parse_input_event(mm)
		var k := InputEventKey.new()
		k.keycode = KEY_SHIFT
		k.physical_keycode = KEY_SHIFT
		k.pressed = true
		Input.parse_input_event(k)
		k = k.duplicate()
		k.pressed = false
		Input.parse_input_event(k)
		await _frames(3)
		_ok()

	func _s_drive_pause() -> void:
		Game.settings["editor_test"] = {"bots": 0, "laps": 1, "hazards": 1, "difficulty": 1}
		ed.test_drive("start")
		var race := await _scene(RACE, 40.0)
		if race == null:
			return
		await _until(func() -> bool: return bool(race.racing), 20.0)
		await _wait(0.5)
		var hud: Hud = race.hud
		if int(race.test_drive.get("errors", 0)) == 0:
			race.test_drive["errors"] = 1
		hud._set_test_line()
		hud._toggle_pause()
		await shot("test_drive_pause", "a test drive's pause menu: RESUME, BACK TO EDITOR, RESTART, OPTIONS; the TEST DRIVE errors line", 0.6)
		_ok()

	func _s_back() -> void:
		var race := get_tree().current_scene
		if race == null or not race.has_method("to_editor"):
			return
		race.to_editor()
		var e := await _scene(EDITOR, 30.0) as TrackEditor
		if e == null:
			return
		ed = e
		await _until(func() -> bool: return ed.card == "" and not ed.view.busy(), 15.0)
		await shot("back_in_editor", "back in the editor: the toast (%s) and the drive's trail" % ed.last_toast, 0.3)
		Game.stop_music()
		_ok()

	# ---------------------------------------------------------------- 25-27 NEW RACE, lobby, browser

	func _s_new_race() -> void:
		var s := EditorSession.current()
		s.close()
		s.return_to = ""
		ed = null
		var cid := str(mine.get("CANAL RUN", ""))
		if cid != "":
			Game.settings["track"] = cid
			Game.settings["track_guid"] = str(CustomTracks.meta(cid).get("guid", ""))
		var m := await _menu()
		m._open_setup()
		await _wait(1.5)
		await shot("new_race", "NEW RACE: the MY TRACKS card with CANAL RUN picked, ABOUT THE TRACK")
		if m.setup != null:
			m.setup.back.emit()
		await _frames(2)
		_ok()

	var _net_keep := {}

	func _reset_net() -> void:
		if _net_keep.is_empty():
			return
		Net.multiplayer.multiplayer_peer = null
		Net.active = _net_keep.active
		Net.is_server = _net_keep.server
		Net.state = _net_keep.state
		Net.cfg = _net_keep.cfg
		Net.players = _net_keep.players
		Net.share._local = Net.share._blank_local()
		Net.share._hist = []
		Net.set_process(true)
		_net_keep = {}

	## The menu scene (the lobby and the browser open over it).
	func _ensure_menu() -> Node:
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path == MENU:
			return cs
		var s := EditorSession.current()
		s.close()
		s.return_to = ""
		ed = null
		return await _menu()

	func _s_lobby() -> void:
		var m := await _ensure_menu()
		var cid := str(mine.get("CANAL RUN", ""))
		var meta := CustomTracks.meta(cid)
		var sha := str(meta.get("sha", "0123456789abcdef"))
		var ch: String = Game.CHARACTERS[0]["id"]
		var vh: String = Game.VEHICLES[1 % Game.VEHICLES.size()]["id"]
		_net_keep = {"cfg": Net.cfg, "players": Net.players, "active": Net.active, "server": Net.is_server, "state": Net.state}
		Net.set_process(false)   # no pings to the fake roster
		if cid != "" and not CustomTracks.is_prepared(cid):
			CustomTracks.prepare(cid, func(_a = null, _b = null) -> void: pass)
		Net.cfg = {"name": "Sasha's server", "track": cid, "laps": 3, "difficulty": 1, "bots": false, "grid": 8, "max_players": 8,
			"custom": {"sha": sha, "size": 1468006, "name": "Canal Run", "author": "Sasha"}}
		Net.players = {
			1: {"nick": "Me", "character": ch, "vehicle": vh, "ready": false, "ping": 30, "track": "get", "why": "", "dl": 0.42, "missing": 0},
			7: {"nick": "Sasha", "character": ch, "vehicle": vh, "ready": true, "ping": 0, "host": true, "track": "ok", "why": "", "dl": 1.0, "missing": 0},
			9: {"nick": "Vance", "character": str(Game.CHARACTERS[2 % Game.CHARACTERS.size()]["id"]), "vehicle": vh, "ready": true, "ping": 40,
				"track": "fail", "why": "stalled", "dl": 0.3, "missing": 0},
		}
		Net.active = true
		Net.is_server = false
		Net.state = "lobby"
		Net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		var sh: TrackShare = Net.share
		sh._local = sh._blank_local()
		var loc := {"key": "c:" + sha, "sha": sha, "id": cid, "state": "get", "dl": 0.42, "name": "Canal Run", "size": 1468006}
		for k in loc:
			sh._local[k] = loc[k]
		sh._hist = [[0.0, 0], [3.0, 520000]]
		m._open_lobby()
		await _frames(3)
		var lobby: Lobby = m.lobby
		if lobby == null:
			return
		lobby._on_cfg()
		lobby._show_local()
		await shot("lobby_friend", "a friend's lobby: your download (%s), Vance at NO TRACK%s" % [lobby.dl_label.text,
			"" if lobby.is_visible_in_tree() else " (NOT ON SCREEN)"])
		# the friend's own download fails: the reason and RETRY
		sh._local["state"] = "fail"
		sh._local["code"] = "stalled"
		sh._local["why"] = TrackShare.TEXT_STALLED
		lobby._show_local()
		await shot("lobby_retry", "the friend's download stalled: the reason and RETRY")
		lobby.queue_free()
		m.lobby = null
		await _frames(2)
		# the host's view: START RACE locked with the status line
		Net.is_server = true
		Net.players = {
			1: {"nick": "Sasha", "character": ch, "vehicle": vh, "ready": true, "ping": 0, "host": true, "track": "ok", "why": "", "dl": 1.0, "missing": 0},
			4: {"nick": "Alyx", "character": ch, "vehicle": vh, "ready": true, "ping": 25, "track": "get", "why": "", "dl": 0.42, "missing": 0},
			9: {"nick": "Vance", "character": ch, "vehicle": vh, "ready": false, "ping": 40, "track": "fail", "why": "stalled", "dl": 0.3, "missing": 0},
		}
		sh._local = sh._blank_local()
		sh._hist = []
		await _until(func() -> bool: return CustomTracks.is_prepared(cid), 20.0)
		m._open_lobby()
		await _frames(3)
		var host: Lobby = m.lobby
		if host == null:
			return
		host._on_cfg()
		host._rebuild_players()
		host._update_status()
		await shot("lobby_host", "the host's lobby: Alyx at 42 %%, Vance at NO TRACK, START RACE off: %s" % host.status_label.text)
		host.queue_free()
		m.lobby = null
		m._set_menu_visible(true)
		await _frames(2)
		_reset_net()
		_ok()

	func _s_browser() -> void:
		var m := await _ensure_menu()
		var b := ServerBrowser.new()
		m._open(b)
		await _frames(3)
		var cid := str(mine.get("CANAL RUN", ""))
		var sha := str(CustomTracks.meta(cid).get("sha", ""))
		var replies := [
			{"address": "192.168.1.20", "port": 27015, "name": "Sasha's server", "map": "Canal Run", "cu": 1, "msha": sha, "mkb": 1434,
				"mau": "Sasha", "players": 3, "max": 8, "state": "lobby", "ping": 12, "compatible": true},
			{"address": "192.168.1.31", "port": 27015, "name": "Friday night", "map": "Dune Drift", "cu": 1, "msha": "ffeeddccbbaa0099", "mkb": 2210,
				"mau": "Gordon", "players": 5, "max": 8, "state": "racing", "ping": 31, "compatible": true},
			{"address": "192.168.1.40", "port": 27016, "name": "Highway 17 only", "map": "Highway 17", "players": 1, "max": 6,
				"state": "lobby", "ping": 48, "bots": true, "compatible": true},
			{"address": "10.0.0.7", "port": 27015, "name": "Old version", "map": "Canals", "players": 0, "max": 8, "state": "lobby", "ping": 80,
				"compatible": false},
		]
		for r in replies:
			b._on_found(r)
		var root: TreeItem = b.list.get_root()
		if root != null and root.get_first_child() != null:
			root.get_first_child().select(1)
		await shot("server_browser", "FIND SERVERS: the TRACK column, \"(custom)\" after custom tracks (fake replies)")
		b.close()
		await _frames(2)
		_ok()
