extends RefCounted
## level/case_test_drive (P12, content): the editor's TEST DRIVE through race.tscn on the COMBINE
## TEST OVAL (5.4, 1.7). FROM THE START alone: one kart, no fly-by, GO after 1 s, the TEST DRIVE
## line, the pause menu's entries and the pad-only X prompt; a driven lap gives a report with the
## lap, the rescues and the 5 Hz trail, and the results read DRIVE AGAIN / BACK TO EDITOR. With 2
## bots: three karts, the normal 3-2-1. FROM HERE: on the road where the editor pointed, a free
## drive (99 laps, no lap count). WATCH A BOT LAP: one computer kart, the camera on it, Tab fast
## forwards x4, the report after its lap. The round trip from the editor scene: F5 to control
## <= 2 s, BACK TO EDITOR to editing <= 1.5 s (measured, 3.11); a track that cannot be built
## spawns nothing and goes back to the editor. A test drive never reaches an online race.

const NEEDS_CONTENT := true
const TIMEOUT := 420
const RACE := "res://scenes/race.tscn"
const EDITOR := "res://scenes/editor.tscn"
const F5_MS := 2000.0
const BACK_MS := 1500.0

var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0


func run(t: Node) -> void:
	var steps := Engine.max_physics_steps_per_frame
	# the TEST DRIVE options F5 uses (the runner puts the settings back after the case)
	Game.settings["editor_test"] = {"bots": 0, "laps": 1, "hazards": 1, "difficulty": 1}
	_online_case(t)
	var s := EditorSession.current()
	s.create("oval")
	var b := LevelCompiler.compile(s.doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()})
	if b.revision < 0:
		b.revision = s.doc.revision
	s.build = b
	t.check(s.drive_blocker() == "" and b.report.errors() == 0, "the oval can be driven (%s)" % s.drive_blocker())
	await _start_case(t, s)
	await _bots_case(t, s)
	await _here_case(t, s)
	await _watch_case(t, s)
	await _round_trip(t, s)
	await _branch_here(t, s)
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = steps
	Game.test_drive = {}
	s.close()
	t.get_tree().unload_current_scene()
	await t.frames(2)


## Starts a drive through the session (as TrackEditor.test_drive does) and returns the race scene.
func _drive(t: Node, s: EditorSession, opts: Dictionary) -> Node:
	var st := {"why": null}
	var on_add := _mark_ready()
	t.get_tree().node_added.connect(on_add)
	s.start_test_drive(t.get_tree(), opts, func(w: String) -> void: st.why = w)
	var guard := 0
	while st.why == null and guard < 600:
		await t.frames(1)
		guard += 1
	t.check(str(st.why) == "", "%s: the drive starts (%s)" % [opts.get("from", "start"), str(st.why)])
	var race := await _scene(t, RACE)
	t.get_tree().node_added.disconnect(on_add)
	return race


## Marks the race scene with the physics frame its _ready ended on (_frames_to_go counts from it).
static func _mark_ready() -> Callable:
	return func(n: Node) -> void:
		if n.scene_file_path == RACE:
			n.ready.connect(func() -> void: n.set_meta("p12_frame0", Engine.get_physics_frames()), CONNECT_ONE_SHOT)


## The current scene once it is `path` and ready (null after `guard` frames).
func _scene(t: Node, path: String, guard := 900) -> Node:
	for i in guard:
		var cs := t.get_tree().current_scene
		if cs != null and cs.scene_file_path == path and cs.is_node_ready():
			return cs
		await t.frames(1)
	t.fail("%s never became the scene" % path)
	return null


## Physics frames from the race's _ready to GO (racing), whenever this is called.
func _frames_to_go(t: Node, race: Node, limit := 900) -> int:
	var n := 0
	while not race.racing and n < limit:
		await t.get_tree().physics_frame
		n += 1
	return Engine.get_physics_frames() - int(race.get_meta("p12_frame0", Engine.get_physics_frames() - n))


func _buttons(c: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in c.find_children("*", "Button", true, false):
		out.append((n as Button).text)
	return out


func _start_case(t: Node, s: EditorSession) -> void:
	var race := await _drive(t, s, {"from": "start", "bots": 0, "laps": 1})
	if race == null:
		return
	t.check(race.is_test_drive() and race.test_from() == "start" and race.laps == 1, "start: a test drive of 1 lap")
	t.check(race.karts.size() == 1 and race.player != null and race.player.is_player, "start, 0 bots: one kart, the player's (%d)" % race.karts.size())
	t.check(race._phase == "count" and race.camera.mode == RaceCamera.Mode.CHASE and race.drive_card == null,
		"start: no fly-by, no HOW TO DRIVE card (%s)" % race._phase)
	var go := await _frames_to_go(t, race)
	var hz := float(Engine.physics_ticks_per_second)
	t.check(go >= int(hz * 0.85) and go <= int(hz * 1.25), "start, 0 bots: GO after 1 s (%d physics frames)" % go)
	var by := str(s.doc.data.get("author", ""))
	var card := "LOADING... %s%s" % [str(s.doc.data.get("name", "")), " by " + by if by != "" else ""]
	t.check(race.loading_text() == card, "the loading card names the track (%s)" % race.loading_text())
	var hud: Hud = race.hud
	t.check(hud.test_line != null and hud.test_line.text == "TEST DRIVE", "the TEST DRIVE line (%s)" % (hud.test_line.text if hud.test_line else "none"))
	race.test_drive["errors"] = 2
	hud._set_test_line()
	t.check(hud.test_line.text == "TEST DRIVE · 2 ERRORS: fix them before you host", "the errors line (%s)" % hud.test_line.text)
	race.test_drive["errors"] = 0
	t.check(_buttons(hud._pause_col) == PackedStringArray(["RESUME", "BACK TO EDITOR", "RESTART", "OPTIONS"]),
		"the pause menu of a test drive (%s)" % ", ".join(_buttons(hud._pause_col)))
	var bar: PromptBar = null
	for n in hud._pause_col.get_children():
		if n is PromptBar:
			bar = n
	t.check(bar != null and bar._entries.size() == 3 and str(bar._entries[2][1]) == "pad"
		and (bar._entries[2][0] as PromptLabel).prompt == "{ui_clear} BACK TO EDITOR", "the pause menu's pad-only X: BACK TO EDITOR")
	# a lap by a computer driver at x4: the report and the results
	race.player.controller = AIController.new(0.95, 7)
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 64
	var guard := 0
	while not race.player.finished and guard < 20000:
		await t.get_tree().physics_frame
		guard += 1
	Engine.time_scale = 1.0
	var rep: Dictionary = race._test_drive_report()
	t.check(rep.finished and int(rep.laps_done) == 1 and float(rep.best_lap) > 20.0 and is_equal_approx(float(rep.best_lap), float(rep.lap_times[0])),
		"start: the report has the lap (%s, %s)" % [str(rep.get("laps_done")), str(rep.get("best_lap"))])
	for k in ["from", "laps_done", "best_lap", "lap_times", "rescues", "rescue_pos", "finished", "stuck_at_s", "trail", "speeds"]:
		t.check(rep.has(k), "the report has %s" % k)
	var trail: PackedVector3Array = rep.trail
	var want := int(race.race_time / race.TRAIL_DT)
	t.check(rep.trail is PackedVector3Array and rep.speeds is PackedFloat32Array and trail.size() == (rep.speeds as PackedFloat32Array).size()
		and absi(trail.size() - want) <= 3, "the trail at 5 Hz: %d points for %.1f s" % [trail.size(), race.race_time])
	var far := 0.0
	for p in trail:
		var i: int = race.track.path.closest(p)
		far = maxf(far, Vector2(p.x - race.track.path.center[i].x, p.z - race.track.path.center[i].z).length())
	t.check(far < 25.0, "the trail follows the road (at most %.1f m off)" % far)
	t.check(rep.rescue_pos is PackedVector3Array and (rep.rescue_pos as PackedVector3Array).size() == int(rep.rescues), "rescue places, one per rescue (%d)" % int(rep.rescues))
	await t.frames(3)
	t.check(hud.results_panel != null and _buttons(hud.results_panel) == PackedStringArray(["DRIVE AGAIN", "BACK TO EDITOR"]),
		"the results of a test drive (%s)" % (", ".join(_buttons(hud.results_panel)) if hud.results_panel else "none"))


func _bots_case(t: Node, s: EditorSession) -> void:
	var race := await _drive(t, s, {"from": "start", "bots": 2, "laps": 1})
	if race == null:
		return
	var back: Vector3 = race.track.spawn_transform(7).origin
	t.check(race.karts.size() == 3 and race.player.is_player and race.player.global_position.distance_to(back) < 1.5,
		"start, 2 bots: three karts, the player's at the back of the grid (%d)" % race.karts.size())
	t.check(race._phase == "count" and not race._quick_go and race._countdown < 1.0, "with bots the 3-2-1 runs (%.2f)" % race._countdown)
	var go := await _frames_to_go(t, race)
	var hz := float(Engine.physics_ticks_per_second)
	t.check(go >= int(hz * race.COUNT_TIME * 0.9), "with bots GO after the count (%d physics frames)" % go)


func _here_case(t: Node, s: EditorSession) -> void:
	var race := await _drive(t, s, {"from": "here", "route": -1, "s": 300.0, "lat": 1.5})
	if race == null:
		return
	var p: TrackPath = race.track.path
	var xf := p.transform_at(300.0)
	var want := xf.origin + xf.basis.x * 1.5 + xf.basis.y * 0.6
	var k: Kart = race.player
	t.check(race.karts.size() == 1 and k.is_player, "here: one kart, the player's")
	t.check(k.global_position.distance_to(want) < 1.0 and (-k.global_basis.z).dot(xf.basis * Vector3.FORWARD) > 0.95,
		"here: on the road where the editor pointed, facing along it (%.2f m off)" % k.global_position.distance_to(want))
	t.check(race.laps == race.FREE_LAPS and race.free_drive() and k.lap == -1 and absf(k._last_s - 300.0) < 3.0,
		"here: a free drive (laps %d, lap %d, s %.1f)" % [race.laps, k.lap, k._last_s])
	t.check(race._phase == "count" and race._quick_go, "here: no 3-2-1")
	var go := await _frames_to_go(t, race)
	var hz := float(Engine.physics_ticks_per_second)
	t.check(go >= int(hz * 0.85) and go <= int(hz * 1.25), "here: GO after 1 s (%d physics frames)" % go)
	await t.frames(2)
	var hud: Hud = race.hud
	t.check(hud.lap_of.text == "" and hud.test_line.text == "TEST DRIVE", "here: no lap count on the HUD (%s)" % hud.lap_of.text)
	t.check(_buttons(hud._pause_col)[2] == "RESTART HERE", "here: RESTART HERE")


func _watch_case(t: Node, s: EditorSession) -> void:
	var race := await _drive(t, s, {"from": "watch"})
	if race == null:
		return
	race.auto_return = false
	var k: Kart = race.player
	t.check(race.karts.size() == 1 and not k.is_player and k.controller is AIController and race.camera.target == k,
		"watch: one computer kart, the camera on it")
	t.check(race.laps == 1, "watch: one lap")
	t.check(race.hud.test_line.text.begins_with("WATCH A BOT LAP"), "watch: the line says how to fast forward (%s)" % race.hud.test_line.text)
	await _frames_to_go(t, race)
	Engine.max_physics_steps_per_frame = 64
	_tab(true)
	await t.frames(3)
	t.check(is_equal_approx(Engine.time_scale, 4.0) and race.fast_forward(), "watch: holding Tab fast forwards x4 (%.1f)" % Engine.time_scale)
	t.check(race.hud.test_line.text == "FAST FORWARD", "watch: FAST FORWARD on the HUD")
	var guard := 0
	while not race._watch_done and guard < 20000:
		await t.get_tree().physics_frame
		guard += 1
	_tab(false)
	await t.frames(3)
	t.check(is_equal_approx(Engine.time_scale, 1.0) and not race.fast_forward(), "watch: back to x1 on release")
	var rep: Dictionary = race._test_drive_report()
	t.check(str(rep.from) == "watch" and rep.finished and float(rep.stuck_at_s) < 0.0 and int(rep.laps_done) == 1,
		"watch: the bot's lap in the report (%s s, %d rescues)" % [str(rep.best_lap), int(rep.rescues)])
	t.check((rep.trail as PackedVector3Array).size() > 50, "watch: the bot's trail (%d)" % (rep.trail as PackedVector3Array).size())


static func _tab(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_TAB
	e.physical_keycode = KEY_TAB
	e.pressed = down
	Input.parse_input_event(e)


## The editor scene -> F5 (TrackEditor.test_drive) -> GO, and BACK TO EDITOR -> the editor showing
## the session's bake: both measured on the wall clock.
func _round_trip(t: Node, s: EditorSession) -> void:
	t.get_tree().change_scene_to_file(EDITOR)
	var ed: TrackEditor = await _scene(t, EDITOR)
	if ed == null:
		return
	var guard := 0
	while (ed.card != "" or ed.view.busy() or ed.build == null) and guard < 1200:
		await t.frames(1)
		guard += 1
	t.check(ed.build == s.build, "the editor shows the session's bake")
	var t0 := Time.get_ticks_msec()
	ed.test_drive("start")
	var race := await _scene(t, RACE)
	if race == null:
		return
	while not race.racing and Time.get_ticks_msec() - t0 < 10000:
		await t.frames(1)
	var f5 := float(Time.get_ticks_msec() - t0)
	t.log("F5 to control: %.0f ms" % f5)
	t.check(race.racing and f5 <= F5_MS * slack, "F5 to control in %.0f ms (<= %.0f)" % [f5, F5_MS])
	await t.frames(30)
	var t1 := Time.get_ticks_msec()
	race.to_editor()
	var ed2: TrackEditor = await _scene(t, EDITOR)
	if ed2 == null:
		return
	while (ed2.card != "" or ed2.view.busy() or ed2.view.mesh_nodes().is_empty()) and Time.get_ticks_msec() - t1 < 10000:
		await t.frames(1)
	var back := float(Time.get_ticks_msec() - t1)
	t.log("BACK TO EDITOR to editing: %.0f ms" % back)
	t.check(ed2.card == "" and not ed2.view.busy() and not ed2.view.mesh_nodes().is_empty() and back <= BACK_MS * slack, "BACK TO EDITOR to editing in %.0f ms (<= %.0f)" % [back, BACK_MS])
	t.check(ed2.build == s.build and ed2._bake_started == -1, "the way back shows the session's bake without compiling")
	t.check(ed2.last_toast.begins_with("Back from the test drive") and s.last_drive.is_empty() and Game.test_drive.is_empty(),
		"the drive's report is toasted and used up, Game.test_drive cleared (%s)" % ed2.last_toast)
	await _failed_case(t, s)


## A drive whose track is gone from memory: Track.build fails, race.gd spawns nothing (no null
## path reaches the karts) and goes back to the editor with the reason in the report.
func _failed_case(t: Node, s: EditorSession) -> void:
	CustomTracks.forget(CustomTracks.EDIT_ID)
	Game.test_drive = EditorSession.test_options({"from": "start"})
	# (the race leaves at once: what it did is read as it becomes ready)
	var got := {}
	var on_add := func(n: Node) -> void:
		if n.scene_file_path == RACE:
			n.ready.connect(func() -> void:
				got.merge({"failed": n.failed, "karts": n.karts.size(), "path": n.track.path, "hud": n.hud}), CONNECT_ONE_SHOT)
	t.get_tree().node_added.connect(on_add)
	t.get_tree().change_scene_to_file(RACE)
	var ed: TrackEditor = await _scene(t, EDITOR)
	t.get_tree().node_added.disconnect(on_add)
	t.check(not got.is_empty() and str(got.failed) != "" and int(got.karts) == 0 and got.path == null and got.hud == null,
		"a track that cannot be built: nothing spawned (%s)" % str(got.get("failed", "no race")))
	t.check(ed != null and Game.test_drive.is_empty() and s.last_drive.is_empty(), "...and straight back to the editor")
	CustomTracks.put_memory(CustomTracks.EDIT_ID, s.build, {"name": "COMBINE TEST OVAL"})


## FROM HERE on a branch (the hills' LOGGING TRAIL): the kart starts on the branch's road with its
## route, its metres along it and the lap metres beside them.
func _branch_here(t: Node, s: EditorSession) -> void:
	t.get_tree().unload_current_scene()
	await t.frames(2)
	s.create("hills")
	var b := LevelCompiler.compile(s.doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()})
	if b.revision < 0:
		b.revision = s.doc.revision
	s.build = b
	var race := await _drive(t, s, {"from": "here", "route": 0, "s": 60.0, "lat": -1.0})
	if race == null:
		return
	var p: TrackPath = race.track.path
	t.check(p.branches.size() == 1, "hills: the trail is in the race")
	if p.branches.is_empty():
		return
	var br: TrackBranch = p.branches[0]
	var xf := br.transform_at(60.0)
	var k: Kart = race.player
	t.check(k.route == 0 and absf(k.route_u - 60.0) < 3.0 and absf(k._last_s - br.main_s(k.route_u)) < 0.5,
		"here on a branch: its route, u %.1f, lap metres %.0f" % [k.route_u, k._last_s])
	t.check(k.global_position.distance_to(xf.origin - xf.basis.x + xf.basis.y * 0.6) < 1.0, "here on a branch: on its road")
	await _frames_to_go(t, race)
	race.player.controller = AIController.new(0.95, 7)
	for i in 180:
		await t.get_tree().physics_frame
	t.check(k.route_u > 70.0 or k.route == -1, "here on a branch: it drives on along it (route %d, u %.0f)" % [k.route, k.route_u])


## A test drive id never reaches an online race: Game.race_setting ignores it and race.gd drops
## it while Net is active; the lobby's validators refuse c_edit.
func _online_case(t: Node) -> void:
	var race_gd: GDScript = load("res://scripts/race/race.gd")
	Game.test_drive = {"track": CustomTracks.EDIT_ID, "laps": 1, "bots": 0, "hazards": 1, "difficulty": 1, "from": "start",
		"route": -1, "s": 0.0, "lat": 0.0, "errors": 0}
	t.check(str(Game.race_setting("track")) == CustomTracks.EDIT_ID, "offline the test drive's track is raced")
	var was: bool = Net.active
	Net.active = true
	var tr := str(Game.race_setting("track"))
	var td: Dictionary = race_gd.take_test_drive()
	Net.active = was
	t.check(tr != CustomTracks.EDIT_ID and td.is_empty() and Game.test_drive.is_empty(),
		"online the test drive is dropped (track %s)" % tr)
	t.check(not TrackShare.valid_cfg({"track": CustomTracks.EDIT_ID}) and not TrackShare.valid_rules({"track": CustomTracks.EDIT_ID}),
		"the lobby refuses c_edit")
