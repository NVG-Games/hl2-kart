extends RefCounted
## editor/case_home (P18, CI): TRACK EDITOR's home (1.1) and NEW RACE's MY TRACKS (5.3) in
## user://tracks_test/. The templates' card outlines match their documents; with no own track the
## home opens on TEMPLATES with the first-visit card; CREATE opens an unsaved "MY TRACK" session
## with no dialog (and ends the card); own / kept / cached tracks are listed (+ NEW TRACK first,
## newest first, badges, dimmed with errors, details); HOST is refused with errors and otherwise
## sets EditorSession.return_to / host_track; PLAY picks the track; EDIT opens the session;
## DUPLICATE / RENAME / DELETE / OPEN FOLDER / KEEP / REMIX; dropped files: a good one is imported,
## hostile ones are refused with their reason; the recovery prompt (RECOVER, DISCARD); the pad:
## LB / RB tabs, the D-pad walking the grid and stopping at its edges, A / Y / X / B. The menu:
## TRACK EDITOR at index 3 (FIND SERVERS second, QUIT last), the home opened and closed, return_to
## "home" / "host", _go_race preparing a custom track behind its fade (a failure says why). NEW
## RACE: the eighth card shows the custom pick (never reset), TrackBrowser picks, refuses a track
## with errors, and BACK keeps the pick.

const NEEDS_CONTENT := false
const TIMEOUT := 180.0
const DEV := 1

var t: Node
var tree: SceneTree
var _now := 0


func run(t_: Node) -> void:
	t = t_
	tree = t.get_tree()
	_now = int(Time.get_unix_time_from_system())
	var saved_auto := CustomTracks.auto_check
	CustomTracks.auto_check = false
	_wipe(CustomTracks.mine_dir())
	CustomTracks.reset()
	_reset_session()
	Game.settings["editor_hints"] = []
	Game.settings["check_updates"] = false
	Game.settings["tutorial_seen"] = true
	_outlines()
	await _empty_home()
	var ids := _make_tracks()
	await _home_lists(ids)
	await _thumbs()
	await _actions(ids)
	await _imports()
	await _downloads()
	await _recovery()
	await _layout()
	await _pad()
	# the menu and NEW RACE build their backgrounds, fonts and the 3D preview from the HL2 content
	if t.content():
		await _menu(ids)
		await _new_race()
	else:
		t.log("skip the menu and NEW RACE parts (no content)")
	_reset_session()
	CustomTracks.auto_check = saved_auto
	_wipe(CustomTracks.mine_dir())
	CustomTracks.reset()


# ---------------------------------------------------------------- helpers

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


func _reset_session() -> void:
	var s := EditorSession.current()
	s.close()
	s.return_to = ""
	s.host_track = ""


## A home on the screen, its signals counted in rec.
func _home(rec: Dictionary, check_recovery := false) -> EditorHome:
	var h := EditorHome.new()
	h.check_recovery = check_recovery
	for k in ["back", "open_editor", "play", "host"]:
		rec[k] = []
	h.back.connect(func(): rec.back.append(true))
	h.open_editor.connect(func(): rec.open_editor.append(true))
	h.play.connect(func(id: String): rec.play.append(id))
	h.host.connect(func(id: String): rec.host.append(id))
	tree.root.add_child(h)
	await t.frames(2)
	return h


func _free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.get_parent().remove_child(n)
		n.queue_free()
	await t.frames(1)


func _ids(h: EditorHome) -> Array:
	return h.list.entries.map(func(e: Dictionary) -> String: return str(e.id))


## An own track written straight to MY TRACKS with the facts its "compile" gave.
func _own(nm: String, tid: String, ago: int, facts: Dictionary, author := "Tester") -> String:
	var d := LevelTemplates.make(tid, nm)
	d.data["author"] = author
	d.data["modified"] = _now - ago
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CustomTracks.mine_dir()))
	var p := LevelIO.free_path(CustomTracks.mine_dir(), nm)
	var hdr := {"outline": TrackList.outline_of_doc(d)}
	for k in facts:
		hdr[k] = facts[k]
	var err := LevelIO.save(d, p, hdr)
	t.check(err == OK, "%s written (%d)" % [nm, err])
	return CustomTracks.note_saved(p, facts)


func _facts(raceable: bool, errors: int, length: float, props := 0, branches := 0, hazards := 0) -> Dictionary:
	return {"raceable": raceable, "errors": errors, "warnings": 0, "length": length, "branches": branches,
		"props": props, "hazards": hazards}


func _file(p: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _pad_button(b: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = down
		e.device = DEV
		Input.parse_input_event(e)
		await t.frames(2)


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await t.frames(2)


func _focus() -> Control:
	return tree.root.gui_get_focus_owner()


func _boxes() -> Array:
	return tree.root.find_children("*", "MessageBox", true, false).filter(func(n: Node) -> bool:
		return not n.is_queued_for_deletion())


# ---------------------------------------------------------------- templates' outlines

func _outlines() -> void:
	for tid in LevelTemplates.IDS:
		var got := TrackList.outline_of_doc(LevelTemplates.make(tid, "X"))
		var want: Array = TrackList.TEMPLATE_OUTLINES.get(tid, [])
		var same := got.size() == want.size()
		if same:
			for i in got.size():
				if absf(float(got[i][0]) - float(want[i][0])) > 0.002 or absf(float(got[i][1]) - float(want[i][1])) > 0.002:
					same = false
					break
		t.check(same, "TEMPLATE_OUTLINES[%s] matches the template's control points" % tid)
		if not same:
			t.log("%s: %s" % [tid, JSON.stringify(got)])
	var o := TrackList.Outline.new()
	o.size = Vector2(200, 120)
	o.set_points(TrackList.TEMPLATE_OUTLINES.get("oval", []))
	var px := o.path_px()
	t.check(px.size() > 40 and px[0].is_equal_approx(px[px.size() - 1]), "the oval's outline is smoothed and closed (%d points)" % px.size())
	var inside := true
	for p in px:
		inside = inside and Rect2(Vector2.ZERO, o.size).has_point(p)
	t.check(inside, "the outline stays inside its box")
	o.set_points([])
	t.check(o.path_px().is_empty(), "no road: no outline (NO ROAD YET)")
	o.free()


# ---------------------------------------------------------------- empty MY TRACKS

func _empty_home() -> void:
	t.check(CustomTracks.list("mine").is_empty() and EditorHome.initial_tab() == "templates", "no own track: TEMPLATES first")
	var rec := {}
	var h := await _home(rec)
	t.check(h.tab == "templates" and h.tabs.current_tab == 2, "the home opens on TEMPLATES (%s)" % h.tab)
	t.check(h.list.cards.size() == LevelTemplates.IDS.size(), "one card per template (%d)" % h.list.cards.size())
	t.check(h.hint_shown() and h.hint_card.is_visible_in_tree(), "the first visit shows the three-step card")
	var hint_text := (h.hint_card.get_node("Text") as PromptLabel).get_parsed_text()
	t.check(hint_text.contains("Pick a template") and hint_text.contains("drive it") and not hint_text.contains("{ed_test}"),
		"the card names the test drive's key: %s" % hint_text)
	t.check(h.buttons["CREATE"].is_visible_in_tree() and not h.buttons["EDIT"].visible and not h.buttons["HOST"].visible,
		"TEMPLATES shows CREATE (no EDIT / HOST)")
	t.check((h.list.cards[1].get_node("Inner/Pic/Outline") as TrackList.Outline) != null, "a template card draws its outline")
	var oval := h.list.index_of(TrackList.TEMPLATE_PREFIX + "oval")
	h.list.select(oval, true)
	t.check(h.details.name_label.text == LevelTemplates.title("oval") and h.details.desc_label.text == LevelTemplates.describe("oval"),
		"the details show the template (%s)" % h.details.name_label.text)
	# CREATE: the editor opens at once on an unsaved MY TRACK; no dialog, no name box
	h._do("CREATE")
	await t.frames(1)
	var s := EditorSession.current()
	t.check(rec.open_editor.size() == 1, "CREATE asks for the editor (%d)" % rec.open_editor.size())
	t.check(s.is_open() and s.path == "" and str(s.doc.data.get("name", "")) == "MY TRACK", "an unsaved MY TRACK session (%s, '%s')" %
		[s.doc.data.get("name", "") if s.doc else "-", s.path])
	t.check(_boxes().is_empty() and h.dialog == null, "no dialog on CREATE")
	t.check(not h.hint_shown() and (Game.settings.editor_hints as Array).has(EditorHome.HINT_KEY), "the first CREATE ends the card for good")
	_reset_session()
	await _free(h)
	# a second visit: no card
	var h2 := await _home(rec)
	t.check(not h2.hint_shown(), "the card is not shown again")
	await _free(h2)


# ---------------------------------------------------------------- tracks

func _make_tracks() -> Dictionary:
	var ids := {}
	ids["a"] = _own("CANAL RUN", "oval", 300, _facts(true, 0, 1103.0, 12))
	ids["b"] = _own("BROKEN LOOP", "empty", 200, _facts(false, 2, 0.0))
	ids["c"] = _own("HILL CLIMB", "oval", 100, _facts(true, 0, 2330.0, 160, 1, 2))
	# a cached download (a friend's server)
	var d := LevelTemplates.make("oval", "DUNE DRIFT")
	d.data["author"] = "Stranger"
	var bytes := LevelIO.pack(d, {})
	var sha := LevelIO.sha256(bytes)
	var part := CustomTracks.cache_part(sha)
	_file(part, bytes)
	ids["cache"] = CustomTracks.cache_add(sha, part, _facts(true, 0, 1103.0))
	t.check(ids.a != "" and ids.b != "" and ids.c != "" and ids.cache != "", "four tracks: %s" % [ids])
	t.check(EditorHome.initial_tab() == "mine", "with own tracks the home opens on MY TRACKS")
	return ids


func _home_lists(ids: Dictionary) -> void:
	var rec := {}
	var h := await _home(rec)
	t.check(h.tab == "mine", "MY TRACKS first (%s)" % h.tab)
	t.check(_ids(h) == [TrackList.NEW_ID, ids.c, ids.b, ids.a], "+ NEW TRACK, then the newest first: %s" % [_ids(h)])
	t.check(TrackList.caption_of(h.list.entries[0]) == "NEW TRACK" and h.list.cards[0].get_node_or_null("Inner/Pic/Outline") == null,
		"the + NEW TRACK card")
	var cb := h.list.card_of(ids.b)
	var badge := cb.get_node_or_null("Badge/Text") as Label
	t.check(badge != null and badge.text == "2 ERRORS", "BROKEN LOOP: 2 ERRORS (%s)" % (badge.text if badge else "-"))
	t.check(cb.modulate.a < 0.9, "a track with errors is dimmed")
	var ca := h.list.card_of(ids.a)
	t.check((ca.get_node("Badge/Text") as Label).text == "RACEABLE" and ca.modulate.a == 1.0, "CANAL RUN: RACEABLE, not dimmed")
	t.check(ca.get_node_or_null("Inner/Pic/Outline") != null, "no thumbnail: the header's outline is drawn")
	h.list.select(h.list.index_of(ids.c))
	var dt := h.details
	t.check(dt.name_label.text == "HILL CLIMB" and dt.author_label.text == "by Tester", "details: name and author")
	t.check(dt.stats_label.text.begins_with("LAP 2.3 KM · 1 SHORTCUT · 160 OBJECTS · 2 HAZARDS · "), "stats: %s" % dt.stats_label.text)
	t.check(dt.date_label.text.begins_with("MODIFIED "), "the modified date: %s" % dt.date_label.text)
	t.check(not dt.why_label.visible, "a raceable track shows no reason")
	h.list.select(h.list.index_of(ids.b))
	t.check(dt.why_label.visible and dt.why_label.text.contains("2 errors"), "with errors the reason shows: %s" % dt.why_label.text)
	# search filters by name / author, + NEW TRACK stays
	h.search.text = "hill"
	h.search.text_changed.emit("hill")
	t.check(_ids(h) == [TrackList.NEW_ID, ids.c], "search 'hill': %s" % [_ids(h)])
	h.search.text_changed.emit("tester")
	t.check(h.list.entries.size() == 4, "search by author")
	h.search.text_changed.emit("")
	await _free(h)


## A track with a picture: the card shows the outline while the worker decodes it, then the
## picture (Game.track_thumb_ready), and so do the details.
func _thumbs() -> void:
	var d := LevelTemplates.make("oval", "PHOTO FINISH")
	var img := Image.create(48, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.4, 0.1))
	d.thumb = img.save_png_to_buffer()
	d.data["modified"] = _now - 10
	var p := LevelIO.free_path(CustomTracks.mine_dir(), "PHOTO FINISH")
	LevelIO.save(d, p, {})
	var id := CustomTracks.note_saved(p, _facts(true, 0, 1103.0))
	var rec := {}
	var h := await _home(rec)
	h.list.select(h.list.index_of(id), true)
	var shown := await _until(func() -> bool:
		var b := h.list.card_of(id)
		return b != null and b.get_node_or_null("Inner/Pic/Thumb") != null, 5.0)
	t.check(shown, "the card shows the decoded picture")
	var pic := h.details.holder.get_child(0) if h.details.holder.get_child_count() > 0 else null
	t.check(pic is TextureRect and (pic as TextureRect).texture != null and (pic as TextureRect).texture.get_width() == 48,
		"the details show it big")
	await _free(h)
	CustomTracks.remove(id)


func _actions(ids: Dictionary) -> void:
	var rec := {}
	var h := await _home(rec)
	var s := EditorSession.current()
	var a := CustomTracks.meta(ids.a)
	var b := CustomTracks.meta(ids.b)
	# HOST: refused with errors, else return_to "host" + host_track and the signal
	var why := h.host_track(b)
	t.check(why.contains("Fix the 2 errors") and s.return_to == "" and rec.host.is_empty(), "HOST refused with errors: %s" % why)
	t.check(h.notice.text == why, "the refusal is said under the cards")
	why = h.host_track(a)
	t.check(why == "" and s.return_to == "host" and s.host_track == ids.a and rec.host == [ids.a],
		"HOST sets return_to / host_track (%s, %s)" % [s.return_to, s.host_track])
	s.return_to = ""
	s.host_track = ""
	# PLAY
	t.check(h.play_track(b) != "" and rec.play.is_empty(), "PLAY refused with errors")
	t.check(h.play_track(a) == "" and rec.play == [ids.a] and Game.settings.track == ids.a and Game.settings.track_guid == str(a.guid),
		"PLAY picks the track (track + track_guid)")
	# EDIT
	t.check(h.edit(a) == "" and rec.open_editor.size() == 1 and s.path == str(a.path) and s.track_id == ids.a, "EDIT opens the file in the session")
	_reset_session()
	# DUPLICATE (a worker save)
	t.check(h.duplicate_track(a) == "" and h.busy(), "DUPLICATE starts a copy")
	t.check(await _until(func() -> bool: return not h.busy(), 20.0), "the copy is saved")
	var copy := CustomTracks.list("mine").filter(func(e: Dictionary) -> bool: return e.name == "CANAL RUN 2")
	t.check(copy.size() == 1 and str(copy[0].guid) != str(a.guid), "a copy CANAL RUN 2 with its own guid")
	if copy.size() == 1:
		t.check(str(h.list.current.get("id", "")) == str(copy[0].id) and h.notice.text == "Copied as CANAL RUN 2.",
			"the copy is selected: %s" % h.notice.text)
	# RENAME through its MessageBox
	h.ask_rename(a)
	var box := h.dialog as MessageBox
	t.check(box != null and box.field != null and box.field.text == "CANAL RUN", "RENAME asks with the name in a field")
	if box:
		box.field.text = "CANAL CLASSIC"
		box._answer(true)
	await t.frames(2)
	var renamed := CustomTracks.id_for_guid(str(a.guid))
	var rm := CustomTracks.meta(renamed)
	t.check(str(rm.get("name", "")) == "CANAL CLASSIC" and not FileAccess.file_exists(str(a.path)), "renamed, the old file gone (%s)" % rm.get("path", ""))
	t.check(str(h.list.current.get("id", "")) == renamed, "the renamed track stays selected")
	ids["a"] = renamed
	# DELETE: CANCEL focused, then to the trash
	var c := CustomTracks.meta(ids.c)
	h.ask_delete(c)
	box = h.dialog as MessageBox
	t.check(box != null and box.focus_cancel and box.text_label.text == "Move HILL CLIMB to the trash? It stays in the tracks folder's .trash until you empty it yourself.",
		"DELETE asks first, CANCEL focused")
	if box:
		box._answer(true)
	await t.frames(2)
	t.check(not CustomTracks.has(ids.c) and not FileAccess.file_exists(str(c.path)), "HILL CLIMB left MY TRACKS")
	var trash := DirAccess.get_files_at(CustomTracks.trash_dir())
	t.check(Array(trash).any(func(f: String) -> bool: return f.begins_with("hill_climb")), "it is in .trash (%s)" % [trash])
	t.check(h.list.index_of(ids.c) < 0, "and off the cards")
	# OPEN FOLDER (headless: recorded, no file manager)
	h.open_folder()
	t.check(h.shell_calls == [ProjectSettings.globalize_path(CustomTracks.mine_dir())], "OPEN FOLDER: the tracks folder %s" % [h.shell_calls])
	await _free(h)


func _imports() -> void:
	var rec := {}
	var h := await _home(rec)
	var before := CustomTracks.list("downloaded").size()
	# hostile files: each refused with its reason, nothing stored
	var evil: String = t.tmp("evil.hl2kt")
	_file(evil, "MZ this is not a track at all".to_utf8_buffer())
	var lines := h.import_files(PackedStringArray([evil]))
	t.check(lines.size() == 1 and lines[0] == "evil.hl2kt was not imported: %s" % LevelIO.FATAL.bad_magic, "garbage refused: %s" % [lines])
	t.check(h.notice.text.contains(str(LevelIO.FATAL.bad_magic)), "the reason is shown: %s" % h.notice.text)
	var good := LevelIO.pack(LevelTemplates.make("oval", "CANYON RUN"), {})
	var cut: String = t.tmp("cut.hl2kt")
	_file(cut, good.slice(0, good.size() / 2))
	lines = h.import_files(PackedStringArray([cut]))
	t.check(lines.size() == 1 and lines[0].begins_with("cut.hl2kt was not imported: ") and lines[0].length() > 30, "a cut file refused: %s" % [lines])
	var txt: String = t.tmp("notes.txt")
	_file(txt, "hello".to_utf8_buffer())
	lines = h.import_files(PackedStringArray([txt]))
	t.check(lines[0] == "notes.txt is not a track file (.hl2kt).", "another file type refused: %s" % [lines])
	t.check(CustomTracks.list("downloaded").size() == before and h.tab == "mine", "nothing stored, the tab unchanged")
	# a good one: DOWNLOADED with it selected
	var d := LevelTemplates.make("oval", "CANYON RUN")
	d.data["author"] = "Sasha"
	var okp: String = t.tmp("canyon_run.hl2kt")
	_file(okp, LevelIO.pack(d, {}))
	lines = h.import_files(PackedStringArray([okp]))
	t.check(lines == PackedStringArray(["Imported CANYON RUN by Sasha"]) and h.notice.text == "Imported CANYON RUN by Sasha", "imported: %s" % [lines])
	t.check(h.tab == "downloaded" and str(h.list.current.get("name", "")) == "CANYON RUN" and str(h.list.current.get("kind", "")) == "kept",
		"DOWNLOADED shows it selected (%s)" % h.tab)
	await _free(h)


func _downloads() -> void:
	var rec := {}
	var h := await _home(rec)
	h.show_tab("downloaded")
	t.check(h.list.entries.size() == 2, "DOWNLOADED: the kept import and the cached download (%d)" % h.list.entries.size())
	for a in ["PLAY", "HOST", "KEEP", "REMIX", "DELETE"]:
		t.check(h.buttons[a].visible, "DOWNLOADED shows %s" % a)
	t.check(not h.buttons["EDIT"].visible and not h.buttons["RENAME"].visible, "and no EDIT / RENAME")
	var cached := h.list.entries.filter(func(e: Dictionary) -> bool: return e.kind == "cache")
	var kept := h.list.entries.filter(func(e: Dictionary) -> bool: return e.kind == "kept")
	if cached.size() != 1 or kept.size() != 1:
		t.fail("one cached and one kept download")
		await _free(h)
		return
	var cid := str(cached[0].id)
	h.list.select(h.list.index_of(cid))
	t.check(not h.buttons["KEEP"].disabled, "KEEP for a cached download")
	t.check(h.keep_track(cached[0]) == "" and str(CustomTracks.meta(cid).get("kind", "")) == "kept", "KEEP moves it to downloaded/")
	var kb := h.list.card_of(cid).get_node_or_null("Badge/Text") as Label
	t.check(kb != null and kb.text == "KEPT", "a kept download says KEPT (%s)" % (kb.text if kb else "-"))
	t.check(h.buttons["KEEP"].disabled, "no second KEEP")
	# the import was never compiled here: not raceable until its local check
	var imp: Dictionary = kept[0]
	t.check(not TrackList.pickable(imp) and h.play_track(imp).contains("has not been checked"), "an unchecked import is not raced: %s" % h.notice.text)
	CustomTracks.build_for(str(imp.id))
	h.show_tab("downloaded", str(imp.id))
	t.check(TrackList.pickable(h.list.current), "after its local compile it can be raced")
	# REMIX: a copy in the editor with the credit
	var s := EditorSession.current()
	t.check(h.remix(h.list.current) == "" and rec.open_editor.size() == 1, "REMIX opens the editor")
	var rx = s.doc.data.get("remix_of", {}) if s.doc else {}
	t.check(rx is Dictionary and rx.get("name") == "CANYON RUN" and rx.get("author") == "Sasha" and s.path == "" and s.dirty(),
		"an unsaved remix crediting CANYON RUN by Sasha")
	_reset_session()
	# DELETE a download
	var dm := CustomTracks.meta(cid)
	h.ask_delete(dm)
	var box := h.dialog as MessageBox
	if box:
		box._answer(true)
	await t.frames(2)
	t.check(not CustomTracks.has(cid) and h.list.entries.size() == 1, "DELETE removes the download")
	await _free(h)


func _recovery() -> void:
	# a never-saved track with an autosave
	var w := EditorSession.new()
	w.create("oval", "LOST TRACK")
	w.doc.apply([LevelDoc.op_set(["desc"], "edited")])
	w.autosave()
	var ap := w.autosave_path()
	t.check(await _until(func() -> bool: return FileAccess.file_exists(ap), 10.0), "an autosave is written")
	var rec := {}
	var h := await _home(rec, true)
	await t.frames(2)
	var box := h.dialog as MessageBox
	t.check(box != null and box.title_label.text == "RECOVER YOUR TRACK?" and box.text_label.text.begins_with("LOST TRACK has changes from "),
		"entering the home offers the recovery: %s" % (box.text_label.text if box else "-"))
	if box:
		box._answer(true)
	await t.frames(2)
	var s := EditorSession.current()
	t.check(rec.open_editor.size() == 1 and s.is_open() and str(s.doc.data.name) == "LOST TRACK" and s.path == "", "RECOVER opens it in the editor")
	_reset_session()
	await _free(h)
	# B: not now (asked again next time); DISCARD: to .trash
	h = await _home(rec, true)
	await t.frames(2)
	box = h.dialog as MessageBox
	if box:
		box.close()
	await t.frames(2)
	t.check(FileAccess.file_exists(ap) and not h._dialog_open(), "B leaves the autosave for later")
	await _free(h)
	h = await _home(rec, true)
	await t.frames(2)
	box = h.dialog as MessageBox
	var discard: Button = null
	if box:
		for c in box.buttons.get_children():
			if c is Button and (c as Button).text == "DISCARD":
				discard = c
	t.check(discard != null, "RECOVER / DISCARD")
	if discard:
		discard.pressed.emit()
	await t.frames(3)
	t.check(not FileAccess.file_exists(ap) and _boxes().is_empty(), "DISCARD moves the autosave away and asks nothing more")
	await _free(h)


# ---------------------------------------------------------------- layout

## ui_fit's rule for the home (each tab, the first-visit card) and TrackBrowser at the three
## window shapes: nothing outside the screen, nothing squeezed below its minimum size.
func _layout() -> void:
	var size0 := tree.root.size
	for win in [Vector2i(1280, 720), Vector2i(1280, 1024), Vector2i(2560, 1080)]:
		tree.root.size = win
		await t.frames(2)
		Game.settings["editor_hints"] = []
		var rec := {}
		var h := await _home(rec)
		for tb in ["mine", "downloaded", "templates"]:
			h.show_tab(tb)
			if not h.list.cards.is_empty():
				h.list.select(h.list.cards.size() - 1, true)
			await t.frames(3)
			_fits(h, "home %s at %s" % [tb, win])
		t.check(h.hint_card.is_visible_in_tree(), "the first-visit card shows at %s" % win)
		await _free(h)
		var br := TrackBrowser.new()
		tree.root.add_child(br)
		await t.frames(3)
		_fits(br, "TrackBrowser at %s" % win)
		await _free(br)
	tree.root.size = size0
	await t.frames(2)


func _fits(screen: Control, what: String) -> void:
	var vr := screen.get_viewport().get_visible_rect().grow(1.0)
	var bad := []
	for c in screen.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl is ScrollBar:
			continue
		var p := ctl.get_parent()
		var scrolled := false
		while p != null and p != screen:
			if p is ScrollContainer:
				scrolled = true
			p = p.get_parent()
		if scrolled:
			continue
		var r := ctl.get_global_rect()
		if r.size.x < 1 or r.size.y < 1:
			continue
		if not vr.encloses(r):
			bad.append("OUTSIDE %s %s" % [ctl.name, r])
		var m := ctl.get_combined_minimum_size()
		if ctl is Label and (ctl as Label).clip_text:
			m.x = 0
		if ctl.size.x + 1 < m.x or ctl.size.y + 1 < m.y:
			bad.append("SQUEEZED %s %s < %s" % [ctl.name, ctl.size, m])
	t.check(bad.is_empty(), "%s fits (%s)" % [what, bad.slice(0, 4)])


# ---------------------------------------------------------------- the pad

func _pad() -> void:
	var rec := {}
	var h := await _home(rec)
	t.check(h.tab == "mine", "the pad walk starts on MY TRACKS")
	h.list.cards[0].grab_focus()
	await t.frames(1)
	# RB / LB switch tabs and the focus follows into the list
	await _pad_button(JOY_BUTTON_RIGHT_SHOULDER)
	t.check(h.tab == "downloaded" and h.list.is_ancestor_of(_focus()), "RB: DOWNLOADED, a card focused (%s)" % h.tab)
	await _pad_button(JOY_BUTTON_RIGHT_SHOULDER)
	t.check(h.tab == "templates", "RB: TEMPLATES")
	await _pad_button(JOY_BUTTON_RIGHT_SHOULDER)
	t.check(h.tab == "mine", "RB wraps round to MY TRACKS")
	await _pad_button(JOY_BUTTON_LEFT_SHOULDER)
	t.check(h.tab == "templates" and h.list.is_ancestor_of(_focus()), "LB: back to TEMPLATES")
	# the grid walk: 5 templates in rows of 4
	h.list.cards[0].grab_focus()
	await t.frames(1)
	await _pad_button(JOY_BUTTON_DPAD_LEFT)
	t.check(_focus() == h.list.cards[0], "left at the row's start stays")
	for i in 3:
		await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	t.check(_focus() == h.list.cards[3], "right walks the row")
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	t.check(_focus() == h.list.cards[3], "right at the row's end stays (no jump to the details)")
	await _pad_button(JOY_BUTTON_DPAD_DOWN)
	t.check(_focus() == h.buttons["CREATE"], "down from a card with none below: the buttons (%s)" % _focus())
	await _pad_button(JOY_BUTTON_DPAD_UP)
	t.check(_focus() == h.list.cards[3], "up from the buttons: back to the selected card (%s)" % _focus())
	h.list.cards[0].grab_focus()
	await t.frames(1)
	await _pad_button(JOY_BUTTON_DPAD_DOWN)
	t.check(_focus() == h.list.cards[4], "down: the next row's card")
	t.check(str(h.list.current.get("template", "")) == LevelTemplates.IDS[4], "the focus selects (the details follow)")
	h.list.cards[1].grab_focus()
	await t.frames(1)
	await _pad_button(JOY_BUTTON_DPAD_UP)
	t.check(_focus() == h.search, "up from the first row: the search field")
	await _pad_button(JOY_BUTTON_DPAD_DOWN)
	t.check(_focus() == h.list.cards[1], "down from the search field: the selected card (%s)" % _focus())
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	await _pad_button(JOY_BUTTON_DPAD_DOWN)
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	t.check(h.button_row.is_ancestor_of(_focus()), "right along the buttons stays in their row (%s)" % _focus())
	# A on a template: CREATE
	h.list.cards[1].grab_focus()
	await t.frames(1)
	await _pad_button(JOY_BUTTON_A)
	t.check(rec.open_editor.size() == 1 and EditorSession.current().is_open(), "A on a template creates the track")
	_reset_session()
	# MY TRACKS: Y plays, X hosts, A edits
	h.show_tab("mine")
	var own := h.list.entries.filter(func(e: Dictionary) -> bool: return TrackList.pickable(e) and e.has("path"))
	if own.is_empty():
		t.fail("a raceable own track for the pad")
	else:
		var oid := str(own[0].id)
		h.list.select(h.list.index_of(oid), true)
		await t.frames(1)
		await _pad_button(JOY_BUTTON_Y)
		t.check(rec.play == [oid], "Y: PLAY (%s)" % [rec.play])
		await _pad_button(JOY_BUTTON_X)
		t.check(rec.host == [oid] and EditorSession.current().return_to == "host", "X: HOST")
		_reset_session()
		h.list.select(h.list.index_of(oid), true)
		await _pad_button(JOY_BUTTON_A)
		t.check(rec.open_editor.size() == 2 and EditorSession.current().path == str(own[0].path), "A on an own track: EDIT")
		_reset_session()
	# A on + NEW TRACK: TEMPLATES
	h.list.select(0, true)
	await _pad_button(JOY_BUTTON_A)
	t.check(h.tab == "templates", "A on + NEW TRACK: TEMPLATES")
	# B: back
	await _pad_button(JOY_BUTTON_B)
	t.check(rec.back.size() == 1, "B: BACK")
	await _free(h)


# ---------------------------------------------------------------- the main menu

func _menu(ids: Dictionary) -> void:
	_reset_session()
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(3)
	var items: VBoxContainer = menu.items
	t.check(items.get_child_count() == 8 and (items.get_child(3) as Button).text == "TRACK EDITOR", "TRACK EDITOR is the fourth of eight entries")
	t.check((items.get_child(1) as Button).text == "FIND SERVERS" and (items.get_child(7) as Button).text == "QUIT", "FIND SERVERS second, QUIT last")
	(items.get_child(3) as Button).pressed.emit()
	await t.frames(2)
	t.check(menu.home != null and menu.home.is_visible_in_tree() and not items.visible, "TRACK EDITOR opens the home over the hidden menu")
	if menu.home:
		menu.home.back.emit()
	await t.frames(2)
	t.check(menu.home == null and items.visible and _focus() == items.get_child(3), "BACK: the menu, TRACK EDITOR focused (%s)" % _focus())
	# _go_race: a custom track is prepared behind the fade; a failure fades back with why
	Game.settings["track"] = ids.b
	var scene0 := tree.current_scene
	menu._go_race()
	var said := await _until(func() -> bool: return menu.dialog != null and is_instance_valid(menu.dialog) and menu.dialog is MessageBox, 15.0)
	t.check(said and (menu.dialog as MessageBox).text_label.text.begins_with("BROKEN LOOP could not be prepared: "),
		"a track that cannot be built is refused behind the fade: %s" % ((menu.dialog as MessageBox).text_label.text if said else "-"))
	t.check(tree.current_scene == scene0, "and the race does not load")
	if said:
		menu.dialog.close()
	await t.frames(2)
	await _free(menu)
	# back from the editor: return_to "home" reopens the home, used once
	var s := EditorSession.current()
	s.return_to = "home"
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(3)
	t.check(menu.home != null and s.return_to == "", "return_to home: the home opens (and return_to is used up)")
	await _free(menu)
	# "host": CREATE SERVER with the track picked
	s.return_to = "host"
	s.host_track = ids.a
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(3)
	var cs = menu.dialog
	t.check(cs is CreateServer and (cs as CreateServer).track_id == ids.a and s.return_to == "" and s.host_track == "",
		"return_to host: CREATE SERVER on the track (%s)" % (cs.track_id if cs is CreateServer else "-"))
	await _free(menu)
	# -- --editor [file | template:<id>]
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(2)
	t.check(menu.open_from_args(PackedStringArray(["--editor", "template:city"])) == "editor" and s.is_open() and s.path == ""
		and str(s.doc.data.get("name", "")) == EditorSession.auto_name() and str(s.doc.data.get("theme", "")) == "city17",
		"--editor template:city: a new unsaved track from the template")
	await _free(menu)
	_reset_session()
	var ap := str(CustomTracks.meta(ids.a).path)
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(2)
	t.check(menu.open_from_args(PackedStringArray(["--editor", ap])) == "editor" and s.path == ap, "--editor <file>: that file")
	await _free(menu)
	_reset_session()
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(2)
	t.check(menu.open_from_args(PackedStringArray(["--editor", "nosuch.hl2kt"])) == "home" and not s.is_open(), "--editor <missing file>: the home")
	await t.frames(2)
	t.check(menu.home != null and menu._toast.visible and menu._toast_label.text.begins_with("nosuch.hl2kt: "), "with why in the corner")
	await _free(menu)
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(2)
	t.check(menu.open_from_args(PackedStringArray(["--editor"])) == "home" and menu.open_from_args(PackedStringArray(["ci"])) == "",
		"--editor alone: the home; no --editor: nothing")
	await t.frames(2)
	t.check(menu.home != null, "the home is open")
	await _free(menu)
	# HOST in the home through the menu
	menu = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(menu)
	await t.frames(3)
	menu._open_editor_home()
	await t.frames(2)
	menu.home.host_track(CustomTracks.meta(ids.a))
	await t.frames(3)
	t.check(menu.home == null and menu.dialog is CreateServer and (menu.dialog as CreateServer).track_id == ids.a,
		"HOST in the home: CREATE SERVER with the track")
	await _free(menu)
	Game.stop_music()
	_reset_session()


# ---------------------------------------------------------------- NEW RACE

func _new_race() -> void:
	var a := CustomTracks.meta(CustomTracks.list("mine").filter(func(e: Dictionary) -> bool: return e.name == "CANAL CLASSIC")[0].id)
	var b: Dictionary = CustomTracks.list("mine").filter(func(e: Dictionary) -> bool: return e.name == "BROKEN LOOP")[0]
	Game.settings["track"] = str(a.id)
	Game.settings["track_guid"] = str(a.guid)
	var setup := RaceSetup.new()
	tree.root.add_child(setup)
	await t.frames(2)
	t.check(setup.track_cards.size() == Game.TRACKS.size() + 1 and setup.track_cards[-1] == setup.my_card, "the eighth card: MY TRACKS, last")
	t.check(Game.settings.track == str(a.id), "a custom pick is not reset to a circuit (%s)" % Game.settings.track)
	var cap := setup.my_card.get_child(0).get_child(1) as Label
	t.check(cap.text == str(a.short) and setup.my_card.button_pressed, "the card shows the custom pick, pressed (%s)" % cap.text)
	t.check(setup.track_desc.text.contains("by Tester") and setup.track_desc.text.contains("1.1 KM"), "ABOUT THE TRACK: %s" % setup.track_desc.text)
	var grid := setup.my_card.get_parent() as GridContainer
	t.check(grid.columns == 4, "still four columns, two rows (%d)" % grid.columns)
	t.check(setup.start_button.focus_neighbor_top == setup.start_button.get_path_to(setup.my_card), "up from START: the MY TRACKS card")
	t.check(setup.my_card.focus_neighbor_bottom == setup.my_card.get_path_to(setup.start_button), "down from it: START RACE")
	t.check(Game.track_pick() == str(a.id), "track_pick keeps the custom track")
	# Enter on the pressed card opens the browser
	setup.my_card.grab_focus()
	await t.frames(1)
	await _key(KEY_ENTER)
	var br := setup.browser
	t.check(br != null and br.is_visible_in_tree(), "the MY TRACKS card opens TrackBrowser")
	if br == null:
		await _free(setup)
		return
	t.check(br.tab == "mine" and str(br.list.current.get("id", "")) == str(a.id), "it opens on the pick")
	var why := br.pick(b)
	t.check(why.contains("cannot be raced") and br.is_visible_in_tree(), "a track with errors cannot be picked: %s" % why)
	br.list.select(br.list.index_of(str(b.id)))
	t.check(br.pick_button.disabled, "RACE THIS TRACK off on it")
	var other := CustomTracks.list("mine").filter(func(e: Dictionary) -> bool: return e.name == "CANAL RUN 2")
	if not other.is_empty():
		br.list.select(br.list.index_of(str(other[0].id)), true)
		await _pad_button(JOY_BUTTON_A)
		t.check(Game.settings.track == str(other[0].id) and Game.settings.track_guid == str(other[0].guid), "A picks it (track + guid)")
		t.check(setup.browser == null and cap.text == str(other[0].short), "the browser closes, the card shows it (%s)" % cap.text)
	# a circuit: the card goes back to MY TRACKS, track_guid cleared
	var first := setup.track_cards[0]
	first.pressed.emit()
	await t.frames(1)
	t.check(Game.settings.track == Game.TRACKS[0].id and Game.settings.track_guid == "" and cap.text == "MY TRACKS" and not setup.my_card.button_pressed,
		"a circuit: MY TRACKS without a pick")
	# BACK in the browser keeps the circuit
	setup.my_card.pressed.emit()
	await t.frames(2)
	t.check(setup.browser != null, "the browser again")
	await _pad_button(JOY_BUTTON_B)
	await t.frames(2)
	t.check(setup.browser == null and Game.settings.track == Game.TRACKS[0].id and first.button_pressed and not setup.my_card.button_pressed,
		"B closes it, the circuit stays picked")
	t.check(setup.is_inside_tree(), "B in the browser does not leave NEW RACE")
	await _free(setup)
