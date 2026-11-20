extends Node
## Headless check of the game side of custom tracks (the editor, the compiler and the net code have
## their own tests): the download cache never keeps more than CustomTracks.MAX_PARTS .part files,
## however many tracks a server announces; the loading word sits in the same place on the menu's
## cover and on the race's loading card; a track nobody knows is "This track" in TRACK NOT READY;
## a test drive's TEST DRIVE line, with its errors (one ERROR: fix it), moves into the pause menu
## under PAUSED, clear of the prompts, in a red that reads on the dim, and back on resume. The test
## drive part needs the built content (it is skipped without it). Prints each failure and a total;
## exits 1 on any failure.
## usage: godot --headless --path . res://tests/custom_game_test.tscn

func _ready() -> void:
	var r := Runner.new()
	get_tree().root.add_child.call_deferred(r)
	r.ready.connect(r._run, CONNECT_ONE_SHOT)


class Runner:
	extends Node

	const MAIN := "res://scenes/main.tscn"
	const RACE := "res://scenes/race.tscn"

	var failures := 0
	var checks := 0

	func _init() -> void:
		# (a scene change frees the current scene: the checks run from the root)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _run() -> void:
		await _frames(2)
		var tut = Game.settings.get("tutorial_seen", false)
		Game.settings["tutorial_seen"] = true
		_parts()
		_track_ref()
		await _loading_word()
		if FileAccess.file_exists("res://assets/track/city17_circuit.json"):
			await _test_drive_pause()
		else:
			print("  skip the test drive: no built content")
		Game.settings["tutorial_seen"] = tut
		print("custom_game_test: %d checks, failures: %d" % [checks, failures])
		get_tree().quit(1 if failures > 0 else 0)

	func check(ok: bool, what: String) -> void:
		checks += 1
		if not ok:
			failures += 1
			print("  FAIL ", what)
		else:
			print("    ok ", what)

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	# ---------------------------------------------------------------- the download parts (6.6)

	func _part_files() -> PackedStringArray:
		var out := PackedStringArray()
		var d := DirAccess.open(CustomTracks.cache_dir())
		if d:
			for f in d.get_files():
				if f.ends_with(".part"):
					out.append(f)
		return out

	func _write(path: String, n: int) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		var b := PackedByteArray()
		b.resize(n)
		f.store_buffer(b)
		f.close()

	## A server that announces a new track again and again (each sent short of its last chunk): every
	## new download's cache_part prunes the others, so the parts stay at MAX_PARTS, never the old way's
	## one per announced track; the part being resumed is never the one that goes, however old.
	func _parts() -> void:
		var saved_age := CustomTracks.part_max_age
		var saved_off := CustomTracks.time_offset
		for f in _part_files():
			DirAccess.remove_absolute(CustomTracks.cache_dir().path_join(f))
		var shas := []
		for i in 6:
			var sha := ("announced %d" % i).sha256_text()
			shas.append(sha)
			var p := CustomTracks.cache_part(sha)
			check(p == CustomTracks.cache_dir().path_join(sha + ".part"), "cache_part %d: cache/<sha>.part" % i)
			_write(p, 4096)
			check(_part_files().size() <= CustomTracks.MAX_PARTS, "after %d announced tracks %d .part files (at most %d)" % [i + 1,
				_part_files().size(), CustomTracks.MAX_PARTS])
		var last := str(shas[5])
		check(FileAccess.file_exists(CustomTracks.cache_dir().path_join(last + ".part")), "the newest download's part is there")
		# asking for a part again (a resume) keeps it, the others within bounds
		CustomTracks.cache_part(last)
		check(FileAccess.file_exists(CustomTracks.cache_dir().path_join(last + ".part")) and _part_files().size() <= CustomTracks.MAX_PARTS,
			"a resume keeps its own part (%s)" % [_part_files()])
		# a day later: the old parts go, the one being resumed stays
		CustomTracks.time_offset = CustomTracks.part_max_age + 3600
		CustomTracks.cache_part(last)
		check(_part_files() == PackedStringArray([last + ".part"]), "after a day only the resumed part is left (%s)" % [_part_files()])
		CustomTracks.prune_parts()
		check(_part_files().is_empty(), "prune_parts with no download in hand: the old part goes too")
		CustomTracks.time_offset = saved_off
		CustomTracks.part_max_age = saved_age
		check(CustomTracks.cache_part("../x") == "", "cache_part still refuses a path")

	# ---------------------------------------------------------------- TRACK NOT READY

	func _track_ref() -> void:
		var unknown := LevelIO.id_for("not here".sha256_text())
		check(Track._track_ref(unknown) == "This track", "an unknown custom track is 'This track' (%s)" % Track._track_ref(unknown))
		var circuit: Dictionary = Game.TRACKS[0]
		check(Track._track_ref(str(circuit["id"])) == "The track %s" % circuit["name"], "a circuit by its name (%s)" % Track._track_ref(str(circuit["id"])))
		var t := Track.new()
		t.build(unknown)
		check(t.build_failed == "This track is not ready on this computer.", "the message: %s" % t.build_failed)
		t.free()

	# ---------------------------------------------------------------- the loading word

	## The menu's cover and the race's loading card end the word in one place (110 px from the right).
	func _loading_word() -> void:
		get_tree().change_scene_to_file(MAIN)
		await get_tree().create_timer(1.0).timeout
		var menu: Node = get_tree().current_scene
		var w := get_viewport().get_visible_rect().size.x
		if menu == null or not menu.has_method("_cover"):
			check(false, "the menu is up")
			return
		for text in ["LOADING...", "PREPARING TRACK..."]:
			var cover: Array = menu._cover(text)
			await _frames(2)
			var r := (cover[1] as Label).get_global_rect()
			check(absf(r.end.x - (w - 110.0)) <= 1.0, "the menu's %s ends 110 px from the right (%s)" % [text, r])
			for n in cover:
				(n as Node).queue_free()
		var l := UiKit.loading_word("LOADING... CANAL RUN WITH A LONG NAME by Someone")
		menu.root.add_child(l)
		await _frames(2)
		check(absf(l.get_global_rect().end.x - (w - 110.0)) <= 1.0 and l.get_global_rect().position.x > 0.0,
			"a custom track's long card ends there too, growing left (%s)" % l.get_global_rect())
		l.queue_free()

	# ---------------------------------------------------------------- the test drive's pause

	func _test_drive_pause() -> void:
		var saved = Game.settings.get("editor_test")
		Game.settings["editor_test"] = {"bots": 0, "laps": 1, "hazards": 1, "difficulty": 1}
		var s := EditorSession.current()
		s.create("oval")
		var b := LevelCompiler.compile(s.doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()})
		if b.revision < 0:
			b.revision = s.doc.revision
		s.build = b
		var st := {"why": null}
		s.start_test_drive(get_tree(), {"from": "start", "bots": 0, "laps": 1}, func(why: String) -> void: st.why = why)
		var race: Node = null
		for i in 900:
			var cs := get_tree().current_scene
			if st.why != null and cs != null and cs.scene_file_path == RACE and cs.is_node_ready():
				race = cs
				break
			await _frames(1)
		check(race != null and str(st.why) == "", "the test drive starts (%s)" % str(st.why))
		if race == null:
			_end_drive(s, saved)
			return
		var hud: Hud = race.hud
		# the race card's word: where the menu's was
		var card: CanvasLayer = race._loading_card()
		await _frames(2)
		var cl: Label = card.find_children("*", "Label", true, false)[0]
		check(absf(cl.get_global_rect().end.x - (get_viewport().get_visible_rect().size.x - 110.0)) <= 1.0,
			"the race card's %s ends 110 px from the right, like the menu's (%s)" % [cl.text, cl.get_global_rect()])
		card.queue_free()
		race.test_drive["errors"] = 1
		hud._set_test_line()
		check(hud.test_line.text == "TEST DRIVE · 1 ERROR: fix it before you host", "one error: 'fix it' (%s)" % hud.test_line.text)
		race.test_drive["errors"] = 2
		hud._set_test_line()
		check(hud.test_line.text == "TEST DRIVE · 2 ERRORS: fix them before you host", "two errors: 'fix them' (%s)" % hud.test_line.text)
		race.test_drive["errors"] = 1
		hud._set_test_line()
		hud._toggle_pause()
		await _frames(3)
		var pl := hud.pause_test_line
		check(get_tree().paused and pl != null and pl.is_visible_in_tree() and not hud.test_line.is_visible_in_tree(),
			"paused: the line is in the pause menu, the HUD's one hidden")
		if pl:
			check(pl.text == "TEST DRIVE · 1 ERROR: fix it before you host", "under PAUSED: %s" % pl.text)
			var col := pl.get_theme_color("font_color")
			check(col.is_equal_approx(Hud.PAUSE_RED) and col.r > 0.9 and col.g > 0.3, "in the light red that reads on the dim (%s)" % col)
			var r := pl.get_global_rect()
			check(get_viewport().get_visible_rect().encloses(r), "on the screen (%s)" % r)
			for n in hud._pause_col.get_children():
				if n is PromptBar or n is Button:
					check(not r.intersects((n as Control).get_global_rect()), "clear of %s %s" % [n.name, (n as Control).get_global_rect()])
			var title: Control = hud._pause_col.get_child(0)
			check(r.position.y >= title.get_global_rect().end.y, "under PAUSED (%s, title %s)" % [r, title.get_global_rect()])
		hud._toggle_pause()
		await _frames(3)
		check(not get_tree().paused and hud.test_line.is_visible_in_tree() and not hud.pause_panel.visible,
			"resumed: the HUD's line is back")
		race.test_drive["errors"] = 0
		hud._set_test_line()
		check(hud.test_line.text == "TEST DRIVE" and pl != null and pl.text == "TEST DRIVE", "no errors: TEST DRIVE (%s / %s)" % [
			hud.test_line.text, pl.text if pl else "none"])
		_end_drive(s, saved)
		get_tree().unload_current_scene()
		await _frames(2)

	func _end_drive(s: EditorSession, saved) -> void:
		get_tree().paused = false
		Game.test_drive = {}
		s.close()
		if saved == null:
			Game.settings.erase("editor_test")
		else:
			Game.settings["editor_test"] = saved
