extends RefCounted
## P5: EditorSession (1.7, 1.9, 7.3) in user://tracks_test/: auto names, create (unsaved, no name
## box), dirty, autosave under the guid, recovery_for / recoveries, save through the worker (file
## name from the name, history copy, the autosave deleted, the registry re-indexed), open,
## open_copy (DUPLICATE / REMIX), drive_blocker, start_test_drive, keep, current(); and the five
## templates (1.2): canonical docs that pass LevelDoc.sanitize unchanged with an empty report.

const NEEDS_CONTENT := false

var t: Node
var _real := false


func run(t_: Node) -> void:
	t = t_
	var saved_auto := CustomTracks.auto_check
	CustomTracks.auto_check = false
	_wipe(CustomTracks.mine_dir())
	CustomTracks.reset()
	_real = LevelCompiler.compile(LevelDoc.blank("x", 512.0, 257)).report.errors() > 0
	_templates()
	await _lifecycle()
	_recovery()
	await _copies()
	await _drive()
	await _misc()
	CustomTracks.auto_check = saved_auto
	_wipe(CustomTracks.mine_dir())
	CustomTracks.reset()


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


func _until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(seconds * 1000.0):
			return false
		await t.frames(1)
	return true


## Saves and waits for done; returns the error (-1 when done never came).
func _save(s: EditorSession, p := "") -> int:
	var res := [-1]
	s.save(p, {}, func(err: Error) -> void: res[0] = err)
	await _until(func() -> bool: return int(res[0]) != -1, 10.0)
	return int(res[0])


# ---------------------------------------------------------------- templates (1.2)

func _templates() -> void:
	t.check(LevelTemplates.IDS == ["empty", "oval", "figure8", "hills", "city"], "the five template ids")
	var spans := {"oval": [900.0, 1300.0], "figure8": [1300.0, 1900.0], "hills": [2000.0, 2800.0], "city": [1500.0, 2000.0]}
	for id in LevelTemplates.IDS:
		var ms: float = t.ms(func() -> void: LevelTemplates.make(id, "T"))
		var d := LevelTemplates.make(id, "Template " + id)
		t.check(LevelTemplates.title(id) != "" and LevelTemplates.describe(id) != "", "%s: title and description" % id)
		t.check(LevelTemplates.last_report.items.is_empty(), "%s: sanitize had nothing to clean (%s)" % [id,
			str(LevelTemplates.last_report.to_dict()).left(300)])
		var rep := LevelReport.new()
		var again := LevelDoc.sanitize(d.data, rep)
		t.check(again == d.data and rep.items.is_empty() and rep.dropped.is_empty(), "%s: passes sanitize unchanged" % id)
		t.check(JSON.stringify(again) == JSON.stringify(d.data), "%s: JSON-identical after sanitize" % id)
		t.check(str(d.data.theme) == str(LevelTemplates.THEMES[id]), "%s: theme %s" % [id, d.data.theme])
		t.check(float(d.data.world.size) == 1024.0 and int(d.data.world.res) == 513 and d.heights.size() == 513 * 513,
			"%s: world 1024 m, res 513" % id)
		t.check(str(d.data.name) == "Template " + id, "%s: named" % id)
		var u := LevelIO.unpack(LevelIO.pack(d), LevelReport.new())
		t.check(u != null and u.data == d.data and u.heights == d.heights, "%s: pack -> unpack gives it back" % id)
		var pts: Array = d.data.road.points
		if id == "empty":
			t.check(pts.is_empty() and not bool(d.data.road.closed), "empty: no road")
			continue
		t.check(bool(d.data.road.closed) and pts.size() >= 8, "%s: a closed loop (%d points)" % [id, pts.size()])
		var lap := 0.0
		var inside := true
		for i in pts.size():
			var a := Vector3(pts[i].pos[0], pts[i].pos[1], pts[i].pos[2])
			var b := Vector3(pts[(i + 1) % pts.size()].pos[0], pts[(i + 1) % pts.size()].pos[1], pts[(i + 1) % pts.size()].pos[2])
			lap += a.distance_to(b)
			if absf(a.x) > 512.0 - 40.0 or absf(a.z) > 512.0 - 40.0:
				inside = false
		var span: Array = spans[id]
		t.check(lap >= float(span[0]) and lap <= float(span[1]), "%s: lap about right (%.0f m by its points)" % [id, lap])
		t.check(inside, "%s: every point 40 m inside the world" % id)
		t.log("%s: %d points, %.0f m, %d props, made in %.0f ms" % [id, pts.size(), lap, d.data.props.size(), ms])
		if _real:
			var b := LevelCompiler.compile(d)
			t.check(b.report.errors() == 0, "%s: compiles without errors (%s)" % [id, str(b.report.to_dict()).left(300)])
			var codes := []
			for it in b.report.items:
				if it.level == "warning":
					codes.append(str(it.code))
			t.log("%s: compiled, %.0f m lap, warnings %s, missing %s" % [id, float(b.meta.get("length", 0.0)), str(codes),
				str(b.report.missing)])
			for it in b.report.items:
				if it.code == "missing":
					t.log("  " + str(it.text))
	var o := LevelTemplates.make("oval", "o")
	t.check(o.data.items.size() == 4 and o.data.pads.size() == 2 and o.data.crowds.size() == 2, "oval: 4 rows, 2 pads, 2 crowds")
	t.check(str(o.data.race.gantry) == "combine", "oval: the combine gantry")
	var f := LevelTemplates.make("figure8", "f")
	var top := 0.0
	var bridged := false
	for p in f.data.road.points:
		top = maxf(top, float(p.pos[1]))
		bridged = bridged or str(p.style) == "canal_bridge"
	t.check(is_equal_approx(top, 9.0) and bridged and f.data.styles.has("canal_bridge"), "figure8: a 9 m bridge of its own style")
	var hmax := 0.0
	for v in f.heights:
		hmax = maxf(hmax, v)
	t.check(hmax > 5.0 and hmax <= 9.0, "figure8: the ground ramps up to the bridge (%.1f m)" % hmax)
	var hl := LevelTemplates.make("hills", "h")
	t.check(hl.data.branches.size() == 1 and str(hl.data.branches[0].kind) == "trail" and is_equal_approx(float(hl.data.branches[0].ai.take), 0.5),
		"hills: a trail shortcut, ai take 0.5")
	var gap := false
	var styles := {}
	for p in hl.data.road.points:
		gap = gap or (p.has("gap") and is_equal_approx(float(p.gap.len), 14.0))
		styles[str(p.style)] = true
	t.check(gap and styles.has("dirt") and styles.has("asphalt"), "hills: a 14 m jump, dirt and asphalt")
	t.check(hl.data.props.size() >= 100 and str(hl.data.race.background) == "forest", "hills: pines, the forest background")
	t.check(hl.data.env.sun is Dictionary and float(hl.data.env.sun.el) <= 15.0, "hills: evening light")
	t.check(JSON.stringify(LevelTemplates.make("hills", "h").data.props) == JSON.stringify(hl.data.props), "hills: seeded (the same pines)")
	var c := LevelTemplates.make("city", "c")
	var kinds := {}
	for p in c.data.road.points:
		kinds[str(p.style)] = true
	var types := []
	for hz in c.data.hazards:
		types.append(str(hz.type))
	t.check(kinds.has("street") and kinds.has("tunnel"), "city: streets and a tunnel")
	t.check("turret" in types and "strike_zone" in types, "city: a turret and a strike zone")
	t.check(c.data.props.size() >= 20 and str(c.data.race.background) == "city17", "city: buildings, the city17 background")
	t.check(LevelTemplates.make("nope", "x").data.road.points.is_empty(), "an unknown template id: the empty field")


# ---------------------------------------------------------------- create / save / open

func _lifecycle() -> void:
	t.check(EditorSession.auto_name() == "MY TRACK", "auto_name: MY TRACK in an empty folder")
	var s := EditorSession.new()
	t.check(not s.is_open() and not s.dirty(), "a new session has no document")
	s.create("oval")
	t.check(s.is_open() and str(s.doc.data.name) == "MY TRACK" and s.path == "", "create: unsaved, MY TRACK")
	t.check(s.history != null and s.history.doc == s.doc, "create: a history on the document")
	t.check(not s.dirty(), "create: clean until the first edit")
	t.check(str(s.doc.data.author) == Game.nickname().left(24), "create: you are the author")
	s.history.commit("DESCRIPTION", [LevelDoc.op_set(["desc"], "First lap.")])
	t.check(s.dirty(), "an edit makes it dirty")
	# autosave under the guid
	s.autosave()
	var ap := s.autosave_path()
	t.check(ap == CustomTracks.autosave_dir().path_join(str(s.doc.data.guid) + ".hl2kt"), "autosave: .autosave/<guid>.hl2kt")
	var ok: bool = await _until(func() -> bool: return FileAccess.file_exists(ap), 5.0)
	t.check(ok, "autosave written (on a worker)")
	await t.frames(2)
	t.check(s.recovery_for(ap) == ap, "recovery_for: the autosave of a never-saved track")
	var rec := EditorSession.recoveries()
	t.check(rec.size() == 1 and str(rec[0].path) == "" and str(rec[0].name) == "MY TRACK", "recoveries: one, never saved")
	t.check(s.dirty(), "autosave does not make it clean")
	# the first save: no dialog, the name's slug in MY TRACKS
	var err: int = await _save(s)
	t.check(err == OK, "save: OK (%d)" % err)
	var p := CustomTracks.mine_dir() + "/my_track.hl2kt"
	t.check(s.path == p and FileAccess.file_exists(p), "save: my_track.hl2kt")
	t.check(not s.dirty() and not s.saving, "save: clean")
	t.check(not FileAccess.file_exists(ap), "a clean save deletes the autosave")
	t.check(EditorSession.recoveries().is_empty(), "nothing to recover after the save")
	t.check(CustomTracks.valid_id(s.track_id) and CustomTracks.path(s.track_id) == p, "save: re-indexed (note_saved)")
	var m := CustomTracks.meta(s.track_id)
	t.check(str(m.get("name")) == "MY TRACK" and bool(m.get("checked")), "the registry has its local facts")
	if _real:
		t.check(bool(m.get("raceable")), "the oval is raceable")
	var hm := LevelIO.read_meta(p)
	t.check(hm.has("outline") and (hm.outline as Array).size() >= 8, "the header has an outline")
	t.check(int(hm.get("modified", 0)) >= int(Time.get_unix_time_from_system()) - 60, "save sets modified")
	t.check(EditorSession.auto_name() == "MY TRACK 2", "auto_name: MY TRACK 2 when taken")
	var s2 := EditorSession.new()
	s2.create("empty")
	t.check(str(s2.doc.data.name) == "MY TRACK 2", "create: the next auto name")
	# open gives the same document back
	var s3 := EditorSession.new()
	t.check(s3.open(p) == "" and s3.path == p and not s3.dirty(), "open")
	t.check(s3.doc.data == s.doc.data, "open: the document that was saved")
	t.check(s3.track_id == s.track_id, "open: its id")
	t.check(s3.open(CustomTracks.mine_dir() + "/missing.hl2kt") != "", "open: a missing file gives a reason")
	# a second save keeps the first version in the history
	s.history.commit("DESCRIPTION", [LevelDoc.op_set(["desc"], "Second lap.")])
	err = await _save(s)
	t.check(err == OK and not s.dirty(), "save again")
	var h := CustomTracks.history(str(s.doc.data.guid))
	t.check(h.size() == 1, "the previous version is in .history (%d)" % h.size())
	if h.size() == 1:
		var old := LevelIO.load_file(str(h[0].path), LevelReport.new())
		t.check(old != null and str(old.data.desc) == "First lap.", "history: the version before")
	t.check(CustomTracks.list("mine").size() == 1, "one track in MY TRACKS")
	# an edit made while the save waits for its bake is written too (the snapshot is taken then)
	s.history.commit("DESCRIPTION", [LevelDoc.op_set(["desc"], "Third lap.")])
	var res := [-1]
	s.save("", {}, func(e: Error) -> void: res[0] = e)
	t.check(s.saving, "saving while the save runs")
	s.history.commit("DESCRIPTION", [LevelDoc.op_set(["desc"], "Fourth lap.")])
	await _until(func() -> bool: return int(res[0]) != -1, 10.0)
	var back := LevelIO.load_file(p, LevelReport.new())
	t.check(int(res[0]) == OK and back != null and str(back.data.desc) == "Fourth lap." and not s.dirty(),
		"an edit before the write is saved with it")
	s.history.commit("DESCRIPTION", [LevelDoc.op_set(["desc"], "Fifth lap.")])
	t.check(s.dirty(), "dirty again")
	s.mark_clean()
	t.check(not s.dirty(), "mark_clean")


func _recovery() -> void:
	var s := EditorSession.new()
	var p := CustomTracks.mine_dir() + "/my_track.hl2kt"
	t.check(s.open(p) == "", "open for recovery")
	var hm := LevelIO.read_meta(p)
	var ap := CustomTracks.autosave_dir().path_join(str(hm.guid) + ".hl2kt")
	var d := LevelIO.load_file(p, LevelReport.new())
	d.data["modified"] = int(hm.modified) + 120
	d.data["desc"] = "recovered text"
	DirAccess.make_dir_recursive_absolute(CustomTracks.autosave_dir())
	LevelIO.save(d, ap)
	t.check(s.recovery_for(p) == ap, "recovery_for: an autosave newer than the file")
	t.check(s.recovery_for(ap) == ap, "recovery_for: the autosave itself, newer than its track")
	var rec := EditorSession.recoveries()
	t.check(rec.size() == 1 and str(rec[0].path) == p, "recoveries: names the track's file")
	var r := EditorSession.new()
	t.check(r.recover(ap) == "" and str(r.doc.data.desc) == "recovered text" and r.path == p and r.dirty(),
		"recover: the autosave's document, at its file, unsaved")
	d.data["modified"] = int(hm.modified) - 120
	LevelIO.save(d, ap)
	t.check(s.recovery_for(p) == "" and s.recovery_for(ap) == "", "recovery_for: an older autosave is not offered")
	EditorSession.discard_autosave(ap)
	t.check(not FileAccess.file_exists(ap), "discard: the autosave leaves")
	t.check(s.recovery_for("") == "" and s.recovery_for(CustomTracks.mine_dir() + "/none.hl2kt") == "", "recovery_for: nothing")


func _copies() -> void:
	var p := CustomTracks.mine_dir() + "/my_track.hl2kt"
	var orig := LevelIO.read_meta(p)
	var s := EditorSession.new()
	t.check(s.open_copy(p, false) == "", "open_copy: DUPLICATE")
	t.check(str(s.doc.data.guid) != str(orig.guid) and s.path == "" and s.dirty(), "duplicate: a new guid, unsaved, dirty")
	t.check(str(s.doc.data.name) != "MY TRACK" and str(s.doc.data.name).begins_with("MY TRACK"), "duplicate: a free name (%s)" % s.doc.data.name)
	t.check(not s.doc.data.has("remix_of"), "duplicate: no remix credit")
	var r := EditorSession.new()
	t.check(r.open_copy(p, true) == "", "open_copy: REMIX")
	t.check(r.doc.data.remix_of is Dictionary and str(r.doc.data.remix_of.guid) == str(orig.guid), "remix: credits the original")
	t.check(str(r.doc.data.author) == Game.nickname().left(24), "remix: you are the author")
	var err: int = await _save(r)
	t.check(err == OK and r.path != p and FileAccess.file_exists(r.path), "remix: saved as its own file (%s)" % r.path.get_file())
	t.check(CustomTracks.list("mine").size() == 2, "two tracks in MY TRACKS")
	t.check(LevelIO.read_meta(r.path).get("remix_of", {}).get("guid", "") == str(orig.guid), "the header carries remix_of")
	# RENAME: the name inside and the file name; the guid stays
	var guid := str(r.doc.data.guid)
	var np := EditorSession.rename_track(r.path, "Canal Remix")
	t.check(np == CustomTracks.mine_dir() + "/canal_remix.hl2kt" and EditorSession.last_error == "", "rename_track: a new file name (%s)" % np)
	t.check(FileAccess.file_exists(np) and not FileAccess.file_exists(r.path), "rename_track: the old file is gone")
	var nm := LevelIO.read_meta(np)
	t.check(str(nm.get("name")) == "Canal Remix" and str(nm.get("short")) == "CANAL REMIX" and str(nm.get("guid")) == guid,
		"rename_track: the name inside, the same guid")
	var rid := CustomTracks.find("Canal Remix")
	t.check(rid != "" and CustomTracks.path(rid) == np and CustomTracks.id_for_guid(guid) == rid, "rename_track: re-indexed")
	t.check(CustomTracks.list("mine").size() == 2, "rename_track: still two tracks")
	t.check(EditorSession.rename_track(np, "  ") == "" and EditorSession.last_error != "", "rename_track: an empty name is refused")


func _drive() -> void:
	var s := EditorSession.new()
	t.check(s.drive_blocker() != "", "drive_blocker: no document")
	s.create("empty")
	t.check(s.drive_blocker() == EditorSession.TEXT_NO_ROAD, "drive_blocker: no road")
	var pts := []
	for i in 3:
		var a := TAU * i / 3.0
		pts.append({"uid": s.doc.new_uid(), "pos": [100.0 * cos(a), 0.0, 100.0 * sin(a)], "width": 14.0, "style": "asphalt"})
	s.history.commit("ROAD", [LevelDoc.op_set(["road", "points"], pts)])
	t.check(s.drive_blocker() == EditorSession.TEXT_OPEN and s.drive_blocker().contains("{ed_close_loop}"),
		"drive_blocker: an open road (Close the loop)")
	var got := []
	s.start_test_drive(null, {}, func(why: String) -> void: got.append(why))
	t.check(got.is_empty(), "start_test_drive: done is deferred")
	await t.frames(2)
	t.check(got.size() == 1 and str(got[0]) == EditorSession.TEXT_OPEN, "start_test_drive: refused with the reason")
	t.check(Game.test_drive.is_empty(), "a refused drive leaves Game.test_drive empty")
	var o := EditorSession.new()
	o.create("oval")
	t.check(o.drive_blocker() == "", "drive_blocker: the oval drives")
	got.clear()
	o.start_test_drive(null, {"bots": 9, "from": "here", "s": 12.5, "lat": 8.0, "route": -1}, func(why: String) -> void: got.append(why))
	var ok: bool = await _until(func() -> bool: return got.size() == 1, 10.0)
	t.check(ok, "start_test_drive: done came")
	if _real:
		t.check(ok and str(got[0]) == "", "start_test_drive: the oval starts (%s)" % (str(got[0]) if ok else ""))
		var td: Dictionary = Game.test_drive
		t.check(str(td.get("track")) == CustomTracks.EDIT_ID and int(td.get("bots")) == 7 and str(td.get("from")) == "here",
			"Game.test_drive: c_edit, bots clamped, from here")
		t.check(is_equal_approx(float(td.get("lat")), 3.0) and int(td.get("laps")) == 1 and td.has("errors"),
			"Game.test_drive: lat clamped to 3 m, laps from editor_test, errors")
		t.check(CustomTracks.has(CustomTracks.EDIT_ID) and o.build != null, "c_edit in memory, the session keeps the build")
	else:
		t.check(ok and str(got[0]).begins_with("The track could not be built"), "start_test_drive: the stub compiler cannot build (%s)" % (str(got[0]) if ok else ""))
	var td2 := EditorSession.test_options({"difficulty": -4, "hazards": 1, "from": "elsewhere"})
	t.check(int(td2.difficulty) == 0 and str(td2.from) == "start" and int(td2.bots) == int(Game.settings.editor_test.bots),
		"test_options: clamped, from start, settings.editor_test")
	Game.test_drive = {}
	CustomTracks.forget(CustomTracks.EDIT_ID)


func _misc() -> void:
	var s := EditorSession.new()
	s.create("empty", "Named Track")
	t.check(str(s.doc.data.name) == "Named Track", "create with a name")
	# the autosave clock
	Game.settings["editor_autosave"] = 5
	s.autosave_tick(10.0)
	await t.frames(2)
	t.check(not FileAccess.file_exists(s.autosave_path()), "autosave_tick: nothing to save while clean")
	s.history.commit("DESCRIPTION", [LevelDoc.op_set(["desc"], "ticked")])
	s.autosave_tick(3.0)
	await t.frames(2)
	t.check(not FileAccess.file_exists(s.autosave_path()), "autosave_tick: not before editor_autosave seconds")
	s.autosave_tick(3.0)
	var ok: bool = await _until(func() -> bool: return FileAccess.file_exists(s.autosave_path()), 5.0)
	t.check(ok, "autosave_tick: autosaves after editor_autosave seconds while dirty")
	await t.frames(2)
	var img := ImageTexture.new()
	s.keep(img)
	s.keep(img)
	s.keep(null)
	t.check(s.resources.size() == 1, "keep: once per resource")
	s.close()
	t.check(not s.is_open() and s.resources.is_empty() and s.path == "", "close")
	var g := t.get_node("/root/Game")
	var was = g.get("editor")
	g.set("editor", null)
	var c1 := EditorSession.current()
	t.check(c1 != null and g.get("editor") == c1 and EditorSession.current() == c1, "current(): Game.editor, made once")
	g.set("editor", was)
