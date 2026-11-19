extends RefCounted
## editor/case_world (P16, CI, fake registries): the WORLD tool in the editor scene. THEME is one
## undo step that sets the keys of 4.4 (the fixed keys and the fallback sky without content; the
## circuit's look with it); every lighting preset writes its env in one step and keeps the sky;
## AMBIENT STRENGTH reaches the built environment (the sky's ambient and a colour's); a dragged
## number folds into one step; water, race, music. Then 1.11: the tool hint cards (first pick
## only, fade on success or after 12 s, "?" recall, SHOW HINTS AGAIN) and the help overlay (two
## columns through EditorKit.prompt, the sections, the last line, any key / B closes it).

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}

var t: Node
var ed: TrackEditor
var tool: WorldTool


func run(t_: Node) -> void:
	t = t_
	var hints0: Array = (Game.settings.get("editor_hints", []) as Array).duplicate()
	var doc := LevelDoc.blank("World tool", 512.0, 257)
	var pts := []
	for k in 12:
		var a := TAU * k / 12
		pts.append({"uid": doc.new_uid(), "pos": [150.0 * cos(a), 0.3, 150.0 * sin(a)], "width": 14.0, "style": "asphalt"})
	doc.data["road"] = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG, "flags": true})
	var s := EditorSession.current()
	s._take(doc)
	s.build = b
	ed = load("res://scenes/editor.tscn").instantiate()
	t.get_tree().root.add_child(ed)
	ed.view.flush()
	ed.set_tool("world")
	tool = ed.tool as WorldTool
	t.check(tool != null and ed.ui.options_box.get_child_count() > 20, "WORLD's options are built (%d rows)" % ed.ui.options_box.get_child_count())
	_theme()
	_presets()
	await _ambient()
	_settings()
	await _hints()
	await _help()
	for k in 900:
		if ed._bake_t < 0.0 and not ed.baking() and not ed.view.busy():
			break
		await t.frames(1)
	ed.queue_free()
	await t.frames(2)
	s.close()
	HintCard._set_seen(hints0)


func _j(v: Variant) -> String:
	return JSON.stringify(v, "", true)


func _theme() -> void:
	var doc := ed.doc
	var before := _j([doc.data.env, doc.data.race, doc.data.terrain, doc.data.theme])
	var n0 := ed.history.position()
	tool.apply_theme("xen")
	t.check(ed.history.position() == n0 + 1 and ed.history.undo_name() == "THEME: XEN", "THEME is one undo step (%s)" % ed.history.undo_name())
	var race: Dictionary = doc.data.race
	t.check(race.gantry == "xen" and race.background == "none" and str(doc.data.theme) == "xen", "THEME: XEN sets the start arch, the background and doc.theme")
	t.check(str(race.rescue) in LevelDoc.RESCUES and (t.content() or race.rescue == "xen_portal"), "and the rescue (%s)" % race.rescue)
	var src := LevelThemes.circuit("xen")
	if src.is_empty():
		t.check(doc.data.env.sky == "hl1_xen8", "without the circuit's JSON: the fallback sky (%s)" % doc.data.env.sky)
	else:
		t.check(doc.data.env.sky == str(src.get("sky", "")), "with content: the circuit's sky (%s)" % doc.data.env.sky)
	for k in ["fog_begin", "fog_end", "exposure", "glow", "sdfgi"]:
		if not doc.data.env.has(k):
			t.fail("THEME leaves env.%s out" % k)
	ed.history.undo()
	t.check(_j([doc.data.env, doc.data.race, doc.data.terrain, doc.data.theme]) == before, "undo takes the whole theme back")
	var gantries := {}
	for id in LevelThemes.IDS:
		tool.apply_theme(id)
		gantries[id] = str(doc.data.race.gantry) + "/" + str(doc.data.race.background)
	t.check(gantries.city17 == "combine/city17" and gantries.blackmesa == "blackmesa/none" and gantries.desert == "military/none"
		and gantries.whiteforest == "combine/forest", "every theme's fixed keys (%s)" % str(gantries))
	t.check(str(doc.data.theme) == "desert", "the last theme applied is remembered (AUTO DRESS's palette)")


func _presets() -> void:
	var doc := ed.doc
	tool.set_env_key("sky", "sky_day01_05", "SKY")
	var n0 := ed.history.position()
	tool.apply_preset("night")
	var e: Dictionary = doc.data.env
	t.check(ed.history.position() == n0 + 1 and ed.history.undo_name() == "LIGHT: NIGHT", "a preset is one undo step")
	t.check(is_equal_approx(float(e.sky_energy), 0.15) and is_equal_approx(float(e.sun_energy), 0.25) and _j(e.ambient) == _j([0.08, 0.1, 0.16])
		and is_equal_approx(float(e.fog_begin), 60.0) and is_equal_approx(float(e.fog_end), 700.0) and is_equal_approx(float(e.exposure), 1.25),
		"NIGHT writes its env (%s)" % _j(e))
	t.check(e.sky == "sky_day01_05", "a preset keeps the sky")
	tool.apply_preset("golden")
	e = doc.data.env
	t.check(e.sun is Dictionary and is_equal_approx(float(e.sun.el), 12.0) and _j(e.sun_color) == _j([1.0, 0.72, 0.45]) and not e.has("sky_energy")
		and not e.has("ambient"), "GOLDEN HOUR: the sun at 12 deg, warm, NIGHT's keys gone")
	tool.apply_preset("overcast")
	e = doc.data.env
	t.check(is_equal_approx(float(e.sun_energy), 0.4) and is_equal_approx(float(e.ambient_energy), 1.4) and not e.has("ambient")
		and is_equal_approx(float(e.fog_end), 900.0), "OVERCAST: a weak sun, the sky's ambient at 1.4, fog 120-900")
	tool.apply_preset("alien")
	t.check(_j(doc.data.env.ambient) == _j([0.45, 0.25, 0.6]) and is_equal_approx(float(doc.data.env.glow), 0.8), "ALIEN: purple ambient, glow 0.8")
	tool.apply_preset("noon")
	e = doc.data.env
	t.check(str(e.sun) == "sky" and not e.has("sun_color") and not e.has("ambient") and is_equal_approx(float(e.exposure), 1.08), "NOON: the sky's own sun, exposure 1.08")
	# the sanitizer keeps every preset's env as it is
	for p in WorldTool.PRESETS:
		var env := tool.preset_env(doc.data.env, p)
		var raw := doc.data.duplicate(true)
		raw.env = env
		var clean := LevelDoc.sanitize(raw, LevelReport.new())
		if _j(clean.env) != _j(LevelDoc.sanitize(clean, LevelReport.new()).env) or not clean.env.has("exposure"):
			t.fail("preset %s does not survive sanitize" % p)
	t.check(true, "every preset's env passes sanitize")


func _ambient() -> void:
	var doc := ed.doc
	tool.apply_preset("noon")
	tool.set_env_key("ambient_energy", 2.5)
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG})
	var parts := Track.make_environment(b.data)
	var env: Environment = parts[2]
	t.check(is_equal_approx(env.ambient_light_energy, 2.5) and env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY, "AMBIENT STRENGTH 2.5 reaches the built env on the sky's ambient (%.2f)" % env.ambient_light_energy)
	for n in parts:
		if n is Node:
			(n as Node).free()
	tool.set_env_key("ambient", [0.3, 0.2, 0.1], "AMBIENT")
	b = LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG})
	parts = Track.make_environment(b.data)
	env = parts[2]
	t.check(is_equal_approx(env.ambient_light_energy, 2.5) and env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and env.ambient_light_color.is_equal_approx(Color(0.3, 0.2, 0.1)), "and on an ambient colour")
	for n in parts:
		if n is Node:
			(n as Node).free()
	tool.set_env_key("sun_energy", 0.0)
	b = LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG})
	parts = Track.make_environment(b.data)
	t.check(not (parts[1] as DirectionalLight3D).visible, "SUN STRENGTH 0 hides the sun")
	for n in parts:
		if n is Node:
			(n as Node).free()
	tool.set_env_key("sun", {"az": 90.0, "el": 30.0}, "SUN")
	var rt := WorldTool.runtime_env(doc)
	var d: Array = rt.env.sun_dir
	t.check(absf(float(d[0]) - cos(deg_to_rad(30.0))) < 1e-3 and absf(float(d[1]) - 0.5) < 1e-3 and absf(float(d[2])) < 1e-3, "a custom sun becomes the compiler's sun_dir (%s)" % str(d))
	tool.preview_env()
	t.check(ed.view.env != null and is_equal_approx(ed.view.env.ambient_light_energy, 2.5), "the view shows the light at once")
	# a dragged number folds into one step
	var n0 := ed.history.position()
	for v in [200.0, 220.0, 240.0, 260.0]:
		tool.set_env_key("fog_begin", v)
	t.check(ed.history.position() == n0 + 1 and is_equal_approx(float(doc.data.env.fog_begin), 260.0), "dragging FOG START is one undo step")
	tool.set_env_key("fog_begin", 260.0)
	t.check(ed.history.position() == n0 + 1, "the same value again is no step")
	tool.erase_env_key("ambient")
	t.check(not doc.data.env.has("ambient"), "AMBIENT FROM THE SKY drops the colour")
	await t.frames(1)


func _settings() -> void:
	var doc := ed.doc
	tool.set_water("sea", true)
	tool.set_water("level", -2.5)
	t.check(bool(doc.data.water.sea) and is_equal_approx(float(doc.data.water.level), -2.5), "SEA on at -2.5 m")
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG})
	t.check(is_equal_approx(float(b.data.get("sea_level", 0.0)), -2.5), "the sea reaches the build")
	tool.set_race("laps", 5, "DEFAULT LAPS")
	tool.set_race("offtrack", 120.0, "OFF-TRACK LIMIT")
	tool.set_race("rescue", "crane", "RESCUE")
	tool.set_race("background", "city17", "BACKGROUND")
	tool.set_citadel(3, 4.5)
	tool.set_seagulls(true)
	var r: Dictionary = doc.data.race
	t.check(int(r.laps) == 5 and is_equal_approx(float(r.offtrack), 120.0) and r.rescue == "crane", "DEFAULT LAPS, OFF-TRACK LIMIT, RESCUE")
	t.check(r.citadel is Array and is_equal_approx(float(r.citadel[3]), 4.5) and (r.seagulls as Array).size() == 3, "the Citadel's scale and three seagull flocks (CITY 17)")
	b = LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG})
	t.check(is_equal_approx(float(b.data.citadel[3]), 4.5) and (b.data.get("seagulls", []) as Array).size() == 3, "both reach the build")
	tool.set_music(["hl1_song3", "hl1_song3", "hl2_song4"] + range(20).map(func(i: int) -> String: return "song_%d" % i))
	t.check((r.music as Array).size() == 12 and r.music[0] == "hl1_song3" and r.music[1] == "hl2_song4", "MUSIC: no repeats, at most 12")
	tool.set_music([])
	t.check((doc.data.race.music as Array).is_empty(), "MUSIC none: the game's race mix")
	ed.ui.refresh_tool()
	t.check(ed.ui.options_box.get_child_count() > 20, "the options rebuild with CITY 17's rows")


func _hints() -> void:
	Game.settings["editor_hints"] = []
	ed.set_tool("terrain")
	var c := HintCard.current(ed)
	t.check(c != null and c.tool_id == "terrain" and c.get_parent() == ed.ui.hint_host, "the first TERRAIN pick shows its card in the hint host")
	t.check(c != null and c.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the card is not modal (the mouse goes through)")
	var lines := HintCard.lines(ed, "terrain")
	t.check(lines.size() == 3, "three lines")
	var text := ""
	if c != null:
		for l in c.find_children("*", "PromptLabel", true, false):
			text += (l as PromptLabel).prompt + "\n"
	t.check(text.find("{ed_mod_ctrl}") >= 0 and text.find("{ed_brush_smaller}") >= 0, "with the tool's key icons")
	t.check("terrain" in HintCard.seen_ids(), "settings.editor_hints holds it")
	ed.set_tool("paint")
	var cp := HintCard.current(ed)
	t.check(cp != null and cp.tool_id == "paint", "PAINT's first pick shows PAINT's card")
	(ed.tool as PaintTool).throttle = 0.0
	var h := EditorHit.new()
	h.hit = true
	h.what = "terrain"
	h.pos = Vector3(40, 0, 40)
	ed.tool.click(h, 0)
	t.check(cp.fading, "the tool's first successful action fades it")
	ed.set_tool("terrain")
	t.check(HintCard.current(ed) == null, "a tool seen before shows no card")
	HintCard.recall(ed, "terrain")
	var cr := HintCard.current(ed)
	t.check(cr != null and cr.tool_id == "terrain", "the palette's ? brings it back")
	cr.age = HintCard.SHOW_S + 0.1
	await t.frames(1)
	t.check(cr.fading or not is_instance_valid(cr), "it fades by itself after 12 s")
	await t.frames(1)
	ed.set_tool("road")
	var rl := HintCard.lines(ed, "road")
	t.check(rl.size() == 3 and str(rl[0]).begins_with("Drag a point"), "ROAD on a closed loop: the loop's card")
	ed.set_tool("world")


func _help() -> void:
	ed.ui.open_help()
	var ov: HelpOverlay = null
	for c in ed.ui.get_children():
		if c is HelpOverlay:
			ov = c
	t.check(ov != null and ov.is_in_group("editor_modal") and ov.mouse_filter == Control.MOUSE_FILTER_STOP, "F1: the help overlay, modal for the pad")
	if ov == null:
		return
	t.check(ed.camera.blocked(), "the pad stops flying while it is up")
	var secs := {}
	var pads := 0
	var undo_row := ""
	for r in ov.rows:
		if r.side == "keys":
			secs[r.section] = true
			if str(r.words).begins_with("UNDO"):
				undo_row = r.prompt
		else:
			pads += 1
	t.check(secs.keys() == ["CAMERA", "SELECT & MOVE", "EDIT", "ROAD & BRANCHES", "TERRAIN & PAINT", "OBJECTS", "TEST DRIVE"], "KEYBOARD & MOUSE: the seven sections (%s)" % str(secs.keys()))
	t.check(pads >= 10, "CONTROLLER rows (%d)" % pads)
	t.check(undo_row.find("{ed_mod_ctrl}+{ed_key_ed_undo}") >= 0, "combos through EditorKit.prompt (%s)" % undo_row)
	var last := false
	for l in ov.find_children("*", "Label", true, false):
		if (l as Label).text == HelpOverlay.LAST_LINE:
			last = true
	t.check(last, "it ends with \"%s\"" % HelpOverlay.LAST_LINE)
	var styles := {}
	for p in ov.find_children("*", "PromptLabel", true, false):
		styles[(p as PromptLabel).style] = true
	t.check(styles.has(InputPrompts.KEYBOARD), "the left column is drawn in key style")
	await t.frames(1)
	var k := InputEventKey.new()
	k.keycode = KEY_SHIFT
	k.pressed = true
	ov._input(k)
	t.check(not ov.is_queued_for_deletion(), "a modifier alone does not close it")
	k = InputEventKey.new()
	k.keycode = KEY_W
	k.pressed = true
	ov._input(k)
	t.check(ov.is_queued_for_deletion(), "any key closes it")
	await t.frames(1)
	ed.ui.open_help()
	ov = null
	for c in ed.ui.get_children():
		if c is HelpOverlay and not c.is_queued_for_deletion():
			ov = c
	await t.frames(1)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_B
	jb.pressed = true
	if ov != null:
		ov._input(jb)
	t.check(ov != null and (ov.is_queued_for_deletion() or not InputMap.action_has_event("ui_cancel", jb)), "B closes it")
	await t.frames(1)
	ed.ui.open_help()
	for c in ed.ui.get_children():
		if c is HelpOverlay and not c.is_queued_for_deletion():
			ov = c
	Game.settings["editor_hints"] = ["world", "terrain"]
	ov.hints_button.pressed.emit()
	t.check(ov.is_queued_for_deletion() and HintCard.seen_ids() == ["world"] and HintCard.current(ed) != null and HintCard.current(ed).tool_id == "world",
		"SHOW HINTS AGAIN forgets the cards seen and shows the tool's")
	await t.frames(2)
	t.check(not ed.camera.blocked() or ed.ui.is_typing(), "the pad flies again once it is gone")
	await t.wait(0.5)   # the button's click sound ends before the scene goes
