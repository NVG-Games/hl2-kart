extends RefCounted
## editor/case_objects (P17, CI + content): the OBJECTS, ITEMS and CROWDS tools in the editor scene
## with fabricated hits. The catalog drawer (tabs, LIGHTS & FX, search, Ctrl + click picks, stars,
## SHOW ANIMATED, no thumbnails headless); STAMP (place, Shift / Ctrl + wheel, RANDOM SCALE, ALIGN
## TO SURFACE, SINK, RECENT, Esc); SCATTER seeded (the same stroke twice gives the same props, one
## undo step, one group, spacing, keep off roads, the live count), Ctrl erase, a dab past 3000
## stops at the cap with the toast; ALONG ROAD (every N m at the setback, one group uid, facing the
## road, double click selects the row); LIGHTS & FX (a light in data.lights, the screen refused
## without the COMBINE arch); ITEMS (rows, a crate, pads on the line and in a lane, barrels, zones:
## all in the build in doc order; zone end bars; red warnings; AUTO ITEMS); CROWDS (a group on each
## side, end bars, eggs and a path, PEOPLE); delete + undo of every kind. Content: the real catalog,
## a real model in the build, PHYSICS only for light models.

const NEEDS_CONTENT := false
const CaseSelect := preload("res://tests/editor/case_select.gd")
const KEYS := ["props_junk/wood_crate001a", "props_c17/oildrum001", "props_junk/trafficcone001a", "props_foliage/tree_pine04"]
const FILLER := "props_test/pebble"

var t: Node
var _fav0: Variant
var _rec0: Variant


func run(tt: Node) -> void:
	t = tt
	_fav0 = (Game.settings.get("editor_fav_props", []) as Array).duplicate() if Game.settings.get("editor_fav_props") is Array else []
	_rec0 = (Game.settings.get("editor_recent_props", []) as Array).duplicate() if Game.settings.get("editor_recent_props") is Array else []
	if not t.content():
		PropCatalog.set_source(_fake_models())
	var ed := await _open(_doc())
	_catalog(ed)
	_stamp(ed)
	_scatter(ed)
	_erase(ed)
	_cap(ed)
	_along(ed)
	_fx(ed)
	await _items(ed)
	_crowds(ed)
	_delete_undo(ed)
	if t.content():
		await _content(ed)
	await CaseSelect.close_editor(t, ed)
	PropCatalog.set_source({})
	Game.settings["editor_fav_props"] = _fav0
	Game.settings["editor_recent_props"] = _rec0
	Game.save_settings()


# ---------------------------------------------------------------- helpers

## A 512 m world with flat terrain and a closed 8-point loop (r 150, 14 m asphalt).
static func _doc() -> LevelDoc:
	var doc := LevelDoc.blank("Objects", 512.0, 257)
	var pts := []
	for k in 8:
		var a := TAU * k / 8
		pts.append({"uid": doc.new_uid(), "pos": [150.0 * cos(a), 1.0, 150.0 * sin(a)], "width": 14.0, "style": "asphalt"})
	doc.data["road"] = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	return doc


static func _fake_models() -> Dictionary:
	var m := {}
	m[KEYS[0]] = {"kind": "props", "mass": 30.0, "aabb_min": [-0.5, -0.5, -0.5], "aabb_max": [0.5, 0.5, 0.5]}
	m[KEYS[1]] = {"kind": "props", "mass": 30.0, "aabb_min": [-0.37, 0, -0.37], "aabb_max": [0.37, 1.14, 0.37]}
	m[KEYS[2]] = {"kind": "props", "mass": 10.0, "aabb_min": [-0.2, -0.38, -0.2], "aabb_max": [0.2, 0.38, 0.2]}
	m[KEYS[3]] = {"kind": "props", "mass": 10.0, "aabb_min": [-3.9, 0, -4.0], "aabb_max": [3.8, 14.9, 3.6]}
	m["antlion"] = {"kind": "props", "mass": 50.0, "aabb_min": [-1, 0, -1], "aabb_max": [1, 1.5, 1]}
	return m


func _open(doc: LevelDoc) -> TrackEditor:
	var ed: TrackEditor = await CaseSelect.open_editor(t, doc)
	ed.set_tool("objects")
	CaseSelect.look_down(ed, Vector3.ZERO, 420.0)
	await t.frames(2)
	return ed


func _ot(ed: TrackEditor) -> ObjectsTool:
	return ed.tools["objects"] as ObjectsTool


func _props(ed: TrackEditor) -> Array:
	return ed.doc.data.props


func _road(ed: TrackEditor) -> LevelRoad:
	return LevelFixes.road_of(ed.build, -1)


## A road hit on the main road at sample i, lat across.
func _road_hit(ed: TrackEditor, i: int, lat := 0.0) -> EditorHit:
	var r := _road(ed)
	var h := CaseSelect.hit_at(ed, r.surface(i, lat), "road")
	h.road = -1
	h.sample = i
	h.s = r.s[i]
	h.lat = lat
	return h


func _ground(ed: TrackEditor, p: Vector3) -> EditorHit:
	return CaseSelect.hit_at(ed, p, "terrain")


## [model, pos, yaw, scale] of the props after index n0.
func _facts(ed: TrackEditor, n0: int) -> Array:
	var out := []
	var l := _props(ed)
	for k in range(n0, l.size()):
		out.append([str(l[k].model), l[k].pos, float(l[k].yaw), float(l[k].scale), float(l[k].pitch), float(l[k].roll)])
	return out


func _stroke(ed: TrackEditor, pts: Array, mods := 0) -> void:
	var ot := _ot(ed)
	ot.drag_begin(_ground(ed, pts[0]), mods)
	for k in range(1, pts.size() - 1):
		ot.drag_move(_ground(ed, pts[k]), mods)
	ot.drag_end(_ground(ed, pts[-1]), mods)


func _new_uids(before: Dictionary, list: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for it in list:
		if not before.has(int(it.uid)):
			out.append(int(it.uid))
	return out


func _uid_set(list: Array) -> Dictionary:
	var d := {}
	for it in list:
		d[int(it.uid)] = true
	return d


# ---------------------------------------------------------------- the drawer

func _catalog(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	var cat := ot.catalog
	t.check(cat != null and cat.visible and cat.get_parent() == ed.ui.catalog_host, "OBJECTS opens the catalog drawer in the catalog host")
	var tabs := cat.tabs()
	t.check(tabs.size() >= 20 and Array(tabs.slice(0, 4)) == ["FAVOURITES", "RECENT", "ALL", "LIGHTS & FX"],
		"tabs: FAVOURITES, RECENT, ALL, LIGHTS & FX, then the categories (%d)" % tabs.size())
	cat.set_tab(PropCatalog.TAB_FX)
	cat.flush()
	t.check(Array(cat.shown()) == ["fx:light", "fx:fire", "fx:embers", "fx:screen"] and cat.cell_count() == 4,
		"LIGHTS & FX lists the four stamps (%s)" % str(cat.shown()))
	cat.set_tab(PropCatalog.TAB_ALL)
	cat.flush()
	var all := PropCatalog.keys(PropCatalog.TAB_ALL)
	t.check(cat.cell_count() == all.size() and cat.cell_count() > 0, "ALL: a cell per model (%d)" % cat.cell_count())
	var b0 = cat._cells.get(KEYS[0])
	t.check(b0 is Button and (b0 as Button).find_child("Size", true, false) != null and (b0 as Button).find_child("Star", true, false) != null,
		"a cell has its size badge and star")
	cat.set_query("crate")
	var only_crates := not cat.shown().is_empty()
	for k in cat.shown():
		only_crates = only_crates and (k.contains("crate") or str(PropCatalog.fact(k).get("category", "")).to_lower().contains("crate"))
	t.check(only_crates and KEYS[0] in cat.shown(), "search 'crate' narrows the grid (%d)" % cat.shown().size())
	cat.set_query("")
	cat.press(KEYS[0])
	t.check(Array(ot.picked) == [KEYS[0]], "a click picks the model")
	cat.press(KEYS[1], true)
	cat.press(KEYS[2], true)
	t.check(Array(ot.picked) == [KEYS[0], KEYS[1], KEYS[2]], "Ctrl + click adds models to the pick (%s)" % str(ot.picked))
	cat.press(KEYS[1], true)
	t.check(Array(ot.picked) == [KEYS[0], KEYS[2]], "Ctrl + click again takes one out")
	cat.flush()
	var painted := 0
	for k in cat._cells:
		if (cat._cells[k] as Button).has_theme_stylebox_override("normal"):
			painted += 1
	t.check(painted == 2, "the picked cells are highlighted (%d)" % painted)
	var was := PropCatalog.is_favourite(KEYS[3])
	cat.toggle_star(KEYS[3])
	t.check(PropCatalog.is_favourite(KEYS[3]) != was, "the star toggles a favourite")
	cat.set_tab(PropCatalog.TAB_FAVOURITES)
	t.check((KEYS[3] in cat.shown()) != was, "FAVOURITES follows the star")
	cat.toggle_star(KEYS[3])
	cat.set_tab(PropCatalog.TAB_ALL)
	cat.set_show_animated(true)
	t.check(PropCatalog.ANIMATED in cat.tabs(), "SHOW ANIMATED adds the ANIMATED tab")
	cat.set_show_animated(false)
	t.check(not (PropCatalog.ANIMATED in cat.tabs()), "and takes it away")
	t.check(not PropThumbs.enabled() and cat.thumbs.get_thumb(KEYS[0]) == null and cat.thumbs.pending() == 0,
		"no thumbnails headless (nothing queued)")
	t.check(PropThumbs.file_of("props_c17/bench01a").ends_with("/props_c17__bench01a.png"), "thumbnail files: / becomes __")
	ed.set_tool("items")
	t.check(not cat.visible, "the drawer hides with another tool")
	ed.set_tool("objects")
	t.check(cat.visible and ot.catalog == cat, "and comes back with OBJECTS")


# ---------------------------------------------------------------- STAMP

func _stamp(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	ot.set_mode("stamp")
	ot.pick_model(KEYS[0])
	var steps := ed.history.position()
	var n0 := _props(ed).size()
	var h := _ground(ed, Vector3(30, 0, 30))
	t.check(str(ot.hints(h)).contains("PLACE"), "stamp hint: CLICK PLACE (%s)" % str(ot.hints(h)))
	t.check(ot.click(h, 0), "a click stamps")
	var p: Dictionary = _props(ed)[-1]
	t.check(_props(ed).size() == n0 + 1 and str(p.model) == KEYS[0] and ItemsTool._v3(p.pos).distance_to(Vector3(30, 0, 30)) < 0.01
		and float(p.scale) == 1.0 and float(p.yaw) == 0.0, "the prop sits at the click with the model, yaw 0, scale 1")
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "ADD OBJECT", "one undo step ADD OBJECT")
	t.check(PropCatalog.recent().size() > 0 and PropCatalog.recent()[0] == KEYS[0], "RECENT has it first")
	var pu := int(p.uid)
	var box := VBoxContainer.new()
	t.check(ot.inspect(PackedInt32Array([pu]), box) and box.get_child_count() >= 9, "the prop inspector (%d rows)" % box.get_child_count())
	box.free()
	ot.replacing = PackedInt32Array([pu])
	ot.pick_model(KEYS[2])
	t.check(str(ed.doc.find(pu).item.model) == KEYS[2] and ot.replacing.is_empty() and ed.history.undo_name() == "REPLACE MODEL",
		"REPLACE...: the next pick replaces the model (one step)")
	t.check(Array(ot.picked) == [KEYS[0]], "and keeps the stamp's pick")
	ed.history.undo()
	t.check(ot.wheel(h, EditorTool.MOD_SHIFT, 1) and is_equal_approx(ot.yaw, 15.0), "Shift + wheel turns 15° (%s)" % ot.yaw)
	t.check(ot.wheel(h, EditorTool.MOD_CTRL, 1) and is_equal_approx(ot.scale, 1.05), "Ctrl + wheel scales 5 %% (%s)" % ot.scale)
	t.check(not ot.wheel(h, 0, 1), "a plain wheel stays the camera's")
	ot.click(_ground(ed, Vector3(34, 0, 30)), 0)
	p = _props(ed)[-1]
	t.check(is_equal_approx(float(p.yaw), 15.0) and is_equal_approx(float(p.scale), 1.05), "the next stamp takes yaw and scale")
	var n1 := _props(ed).size()
	var at := ed.camera.unproject_position(Vector3(-30, 0, -30))
	CaseSelect.button(ed, at, true)
	CaseSelect.button(ed, at, false)
	t.check(_props(ed).size() == n1 + 1 and ItemsTool._v3(_props(ed)[-1].pos).distance_to(Vector3(-30, 0, -30)) < 1.0,
		"a click through the editor's input stamps under the cursor (%s)" % str(_props(ed)[-1].pos))
	ot.random_scale = true
	ot.scale_min = 0.5
	ot.scale_max = 2.0
	ot._roll()
	var scales := {}
	var in_range := true
	for k in 6:
		ot.click(_ground(ed, Vector3(40 + k * 3, 0, 30)), 0)
		var sc := float(_props(ed)[-1].scale)
		scales[sc] = true
		in_range = in_range and sc >= 0.5 and sc <= 2.0
	t.check(in_range and scales.size() > 1, "RANDOM SCALE stays in 0.5-2 and varies (%s)" % str(scales.keys()))
	ot.random_scale = false
	ot.align = true
	var tilted := _ground(ed, Vector3(60, 0, 40))
	tilted.normal = Vector3(0.6, 0.8, 0.0)
	ot.yaw = 0.0
	ot.click(tilted, 0)
	p = _props(ed)[-1]
	t.check(absf(float(p.roll)) > 1.0 and absf(float(p.roll)) <= 20.0 and absf(float(p.pitch)) <= 20.0,
		"ALIGN TO SURFACE tilts at most 20° (pitch %s roll %s)" % [p.pitch, p.roll])
	ot.align = false
	ot.sink = 0.5
	ot.click(_ground(ed, Vector3(64, 0, 40)), 0)
	t.check(is_equal_approx(ItemsTool._v3(_props(ed)[-1].pos).y, -0.5), "SINK lowers it")
	ot.sink = 0.0
	ot.scale = 1.0
	CaseSelect.key(ed, KEY_ESCAPE)
	t.check(ot.picked.is_empty() and not ot.stamping(), "Esc ends stamping")
	t.check(not ot.click(_ground(ed, Vector3(70, 0, 40)), 0), "a click without a pick is the common rule's")
	while ed.history.position() > steps:
		ed.history.undo()
	t.check(_props(ed).size() == n0, "undo takes the stamps away")


# ---------------------------------------------------------------- SCATTER

func _scatter(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	ot.set_mode("stamp")
	CaseSelect.key(ed, KEY_B)
	t.check(ot.mode == "scatter", "B: SCATTER")
	CaseSelect.key(ed, KEY_B)
	t.check(ot.mode == "stamp", "B again: STAMP")
	ot.set_mode("scatter")
	ot.radius = 20.0
	CaseSelect.key(ed, KEY_BRACKETRIGHT)
	t.check(is_equal_approx(ot.radius, 25.0), "] makes the brush bigger (%s)" % ot.radius)
	CaseSelect.key(ed, KEY_BRACKETLEFT)
	t.check(is_equal_approx(ot.radius, 20.0), "[ smaller")
	ot.picked = PackedStringArray([KEYS[0], KEYS[1]])
	ot.density = 2.0
	ot.spacing = 3.0
	ot.radius = 20.0
	ot.keep_off = 3.0
	ot.scatter_seed = 7
	var n0 := _props(ed).size()
	var steps := ed.history.position()
	var stroke := [Vector3(-20, 0, 0), Vector3(0, 0, 0), Vector3(20, 0, 0)]
	_stroke(ed, stroke)
	var a := _facts(ed, n0)
	t.check(a.size() > 10, "a stroke scatters props (%d)" % a.size())
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "SCATTER", "one undo step SCATTER")
	t.check(ot.scatter_seed == 8, "the seed advances per stroke")
	var groups := {}
	var models_ok := true
	var min_d := INF
	var l := _props(ed)
	for k in range(n0, l.size()):
		groups[int(l[k].get("group", 0))] = true
		models_ok = models_ok and str(l[k].model) in [KEYS[0], KEYS[1]]
		for j in range(n0, k):
			var pa := ItemsTool._v3(l[k].pos)
			var pb := ItemsTool._v3(l[j].pos)
			min_d = minf(min_d, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	t.check(groups.size() == 1 and not groups.has(0), "the stroke's props share one group uid")
	t.check(models_ok, "only the picked models")
	t.check(min_d >= 3.0 - 1e-3, "MIN SPACING kept (%.2f m)" % min_d)
	t.check(ot.count_text() == "PROPS %d / 1500" % _props(ed).size(), "the live count (%s)" % ot.count_text())
	ed.history.undo()
	t.check(_props(ed).size() == n0, "undone in one step")
	ot.scatter_seed = 7
	_stroke(ed, stroke)
	var b := _facts(ed, n0)
	t.check(a == b, "the same stroke with the same seed gives the same props (%d / %d)" % [a.size(), b.size()])
	ed.history.undo()
	ot.scatter_seed = 7
	_stroke(ed, [Vector3(-20, 0, 2), Vector3(20, 0, 2)])
	t.check(_facts(ed, n0) != a, "another stroke gives other props")
	ed.history.undo()
	# keep off roads: a stroke over the loop
	var r := _road(ed)
	_stroke(ed, [Vector3(150, 0, -10), Vector3(150, 0, 10)])
	var off_ok := true
	var n_road := 0
	for k in range(n0, _props(ed).size()):
		n_road += 1
		var q := ItemsTool._v3(_props(ed)[k].pos)
		var i := r.closest(q)
		var edge := r.width[i] * 0.5 + maxf(r.treatment(i, -1), r.treatment(i, 1))
		off_ok = off_ok and Vector2(q.x - r.pos[i].x, q.z - r.pos[i].z).length() - edge >= 3.0 - 0.01
	t.check(off_ok, "KEEP OFF ROADS: none within 3 m of the road's edge (%d placed)" % n_road)
	ed.history.undo()
	t.check(_props(ed).size() == n0, "clean again")


func _erase(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	ot.picked = PackedStringArray([KEYS[0], KEYS[1]])
	ot.scatter_seed = 7
	var n0 := _props(ed).size()
	_stroke(ed, [Vector3(-20, 0, 0), Vector3(20, 0, 0)])
	var n1 := _props(ed).size()
	var crates_in := 0
	var drums := 0
	for k in range(n0, n1):
		var q := ItemsTool._v3(_props(ed)[k].pos)
		if str(_props(ed)[k].model) == KEYS[0] and Vector2(q.x, q.z).length() <= 10.0:
			crates_in += 1
		if str(_props(ed)[k].model) == KEYS[1]:
			drums += 1
	ot.picked = PackedStringArray([KEYS[0]])
	ot.radius = 10.0
	var steps := ed.history.position()
	ot.click(_ground(ed, Vector3.ZERO), EditorTool.MOD_CTRL)
	var left_in := 0
	var drums_after := 0
	for k in range(n0, _props(ed).size()):
		var q := ItemsTool._v3(_props(ed)[k].pos)
		if str(_props(ed)[k].model) == KEYS[0] and Vector2(q.x, q.z).length() <= 10.0:
			left_in += 1
		if str(_props(ed)[k].model) == KEYS[1]:
			drums_after += 1
	t.check(crates_in > 0 and left_in == 0 and drums_after == drums, "Ctrl + click erases the picked model in the brush, others stay (%d crates)" % crates_in)
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "ERASE OBJECTS", "erase is one undo step")
	ed.history.undo()
	t.check(_props(ed).size() == n1, "undo brings them back")
	ed.history.undo()
	ot.radius = 20.0


func _cap(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	var n0 := _props(ed).size()
	var fill := []
	for k in 2995 - n0:
		var x := -240.0 + float(k % 60) * 1.5
		var z := -240.0 + float(k / 60) * 1.5
		fill.append(ItemsTool.op_add("props", {"uid": ed.doc.new_uid(), "model": FILLER, "pos": [x, 0.0, z], "yaw": 0.0,
			"pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": ""}))
	ed.commit("FILL", fill)
	t.check(_props(ed).size() == 2995, "2995 props")
	t.check(ot.count_text() == "PROPS 2995 / 1500", "the count says so (%s)" % ot.count_text())
	ot.set_mode("scatter")
	ot.picked = PackedStringArray([KEYS[2]])
	ot.density = 10.0
	ot.spacing = 1.0
	ot.radius = 20.0
	ed.last_toast = ""
	ot.click(_ground(ed, Vector3(0, 0, 60)), 0)
	t.check(_props(ed).size() == 3000, "a dab past 3000 places up to the cap (%d)" % _props(ed).size())
	t.check(ed.last_toast == "Prop limit reached (3000)", "and toasts (%s)" % ed.last_toast)
	ot.click(_ground(ed, Vector3(30, 0, 60)), 0)
	t.check(_props(ed).size() == 3000, "the next dab adds nothing")
	ot.set_mode("stamp")
	ot.pick_model(KEYS[0])
	ed.last_toast = ""
	ot.click(_ground(ed, Vector3(30, 0, 70)), 0)
	t.check(_props(ed).size() == 3000 and ed.last_toast == "Prop limit reached (3000)", "a stamp at the cap is refused with the toast")
	ed.history.undo()
	ed.history.undo()
	t.check(_props(ed).size() == n0, "undo: back to %d" % n0)
	ot.end_stamping()


# ---------------------------------------------------------------- ALONG ROAD

func _along(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	ot.set_mode("along")
	ot.picked = PackedStringArray([KEYS[2], KEYS[3]])
	ot.every = 20.0
	ot.setback = 3.0
	ot.facing = "road"
	ot.jitter = 0.0
	ot.jitter_yaw = 0.0
	var r := _road(ed)
	var i0 := r.idx(100.0)
	var i1 := r.idx(200.0)
	var w := r.width[i0] * 0.5
	var h0 := _ground(ed, r.surface(i0, w + 1.0))
	var h1 := _ground(ed, r.surface(i1, w + 1.5))
	var before := _uid_set(_props(ed))
	var steps := ed.history.position()
	t.check(str(ot.hints(h0)).contains("ALONG"), "the hint says what a drag does")
	t.check(ot.drag_begin(h0, 0), "a press beside the road starts a row")
	ot.drag_move(_ground(ed, r.surface(r.idx(150.0), w + 1.0)), 0)
	ot.drag_end(h1, 0)
	var made := _new_uids(before, _props(ed))
	var ds := r.s[i1] - r.s[i0]
	var want := floori(absf(ds) / 20.0 + 1e-6) + 1
	t.check(made.size() == want, "a prop every 20 m from press to release (%d, want %d)" % [made.size(), want])
	t.check(ed.history.position() == steps + 1 and ed.history.undo_name() == "ALONG ROAD", "one undo step ALONG ROAD")
	var lat_ok := true
	var face_ok := true
	var group := -1
	var group_ok := true
	var cyc_ok := true
	var spacing_ok := true
	var last_s := -1.0
	for k in made.size():
		var it: Dictionary = ed.doc.find(made[k]).item
		var p := ItemsTool._v3(it.pos)
		var i := r.closest(p)
		var want_lat := r.width[i] * 0.5 + r.treatment(i, 1) + 3.0
		var off := p - r.pos[i]
		off.y = 0.0
		lat_ok = lat_ok and absf(off.dot(r.flat_right[i]) - want_lat) < 0.1
		var yaw := deg_to_rad(float(it.yaw))
		var to := (r.pos[i] - p)
		to.y = 0.0
		face_ok = face_ok and Vector3(sin(yaw), 0, cos(yaw)).dot(to.normalized()) > 0.99
		if group < 0:
			group = int(it.get("group", 0))
		group_ok = group_ok and int(it.get("group", 0)) == group and group > 0
		cyc_ok = cyc_ok and str(it.model) == KEYS[2 + k % 2]
		if last_s >= 0.0:
			spacing_ok = spacing_ok and absf(r.s[i] - last_s - 20.0) <= 2.5
		last_s = r.s[i]
	t.check(lat_ok, "at the setback past the edge treatment (right side)")
	t.check(face_ok, "FACING THE ROAD")
	t.check(group_ok, "one shared group uid")
	t.check(cyc_ok, "models cycled in pick order")
	t.check(spacing_ok, "about 20 m apart along the road")
	var hp := CaseSelect.hit_at(ed, ItemsTool._v3(ed.doc.find(made[2]).item.pos), "prop", made[2], "prop")
	t.check(ot.double_click(hp, 0) and CaseSelect.sorted(ed.selection.uids) == CaseSelect.sorted(made), "a double click selects the row")
	ed.selection.clear()
	ed.history.undo()
	t.check(_new_uids(before, _props(ed)).is_empty(), "undone")
	# the other side, ALONG THE ROAD
	ot.facing = "along"
	ot.drag_begin(_ground(ed, r.surface(i0, -w - 1.0)), 0)
	ot.drag_end(_ground(ed, r.surface(r.idx(140.0), -w - 1.0)), 0)
	var made2 := _new_uids(before, _props(ed))
	var want2 := floori(absf(r.s[r.idx(140.0)] - r.s[i0]) / 20.0 + 1e-6) + 1
	var left_ok := made2.size() == want2
	for u in made2:
		var p := ItemsTool._v3(ed.doc.find(u).item.pos)
		left_ok = left_ok and r.lateral(p, r.closest(p)) < -w
	t.check(left_ok, "the cursor's side: left (%d, want %d)" % [made2.size(), want2])
	ed.history.undo()
	ot.facing = "road"
	ot.set_mode("stamp")


# ---------------------------------------------------------------- LIGHTS & FX

func _fx(ed: TrackEditor) -> void:
	var ot := _ot(ed)
	ot.set_mode("stamp")
	ot.catalog.press("fx:light")
	t.check(ot.fx == "light" and ot.stamping(), "LIGHT from the drawer stamps")
	var steps := ed.history.position()
	ot.click(_ground(ed, Vector3(40, 0, -40)), 0)
	var lights: Array = ed.doc.data.lights
	t.check(lights.size() == 1 and ItemsTool._v3(lights[0].pos).distance_to(Vector3(40, 4, -40)) < 0.01, "a light 4 m over the click")
	var lu := int(lights[0].uid)
	ot.pick_fx("fire")
	ot.click(_ground(ed, Vector3(44, 0, -40)), 0)
	ot.pick_fx("embers")
	ot.click(_ground(ed, Vector3(48, 0, -40)), 0)
	var fires: Array = ed.doc.data.fires
	t.check(fires.size() == 2 and float(fires[0].size) == 1.0 and float(fires[1].size) == 0.0 and not bool(fires[1].light),
		"FIRE and EMBERS")
	ot.pick_fx("screen")
	ot.click(_ground(ed, Vector3(52, 0, -40)), 0)
	t.check((ed.doc.data.screens as Array).size() == 1, "a Breencast screen with the COMBINE arch")
	var b := LevelCompiler.compile(ed.doc, {"id": CustomTracks.EDIT_ID, "registries": CaseSelect.REG})
	var found := false
	for l in b.data.get("lights", []):
		if ItemsTool._v3(l.pos).distance_to(Vector3(40, 4, -40)) < 0.01:
			found = true
	t.check(found, "the stamped light is in data.lights")
	t.check((b.data.get("fires", []) as Array).size() == 2 and (b.data.get("screens", []) as Array).size() == 1, "fires and the screen are in the build")
	var box := VBoxContainer.new()
	t.check(ot.inspect(PackedInt32Array([lu]), box) and box.get_child_count() >= 4, "the light's inspector")
	box.free()
	var mk := ed.markers.entries("objects")
	var kinds := {}
	for e in mk:
		kinds[e.kind] = true
	ed.refresh_markers()
	ed._refresh_markers()
	mk = ed.markers.entries("objects")
	kinds = {}
	for e in mk:
		kinds[e.kind] = true
	t.check(kinds.has("light") and kinds.has("fire") and kinds.has("screen"), "light, fire and screen markers (%s)" % str(kinds.keys()))
	ed.commit("START ARCH", [LevelDoc.op_set(["race", "gantry"], "blackmesa")])
	ot.end_stamping()
	ot.pick_fx("screen")
	t.check(ot.fx == "", "no Breencast screen without the COMBINE arch")
	ot.catalog.set_tab(PropCatalog.TAB_FX)
	ot.catalog.flush()
	t.check((ot.catalog._cells["fx:screen"] as Button).disabled, "its cell is greyed")
	ot.catalog.set_tab(PropCatalog.TAB_ALL)
	while ed.history.position() > steps:
		ed.history.undo()
	t.check((ed.doc.data.lights as Array).is_empty() and (ed.doc.data.fires as Array).is_empty(), "undone")


# ---------------------------------------------------------------- ITEMS

func _items(ed: TrackEditor) -> void:
	ed.set_tool("items")
	var it := ed.tools["items"] as ItemsTool
	var r := _road(ed)
	var steps := ed.history.position()
	it.set_mode("row")
	t.check(str(it.hints(_road_hit(ed, 300))).contains("CRATE ROW"), "row hint on the road")
	t.check(it.click(_road_hit(ed, 300), 0) and it.click(_road_hit(ed, 60), 0), "two crate rows")
	var rows: Array = ed.doc.data.items
	t.check(rows.size() == 2 and int(rows[0].road) == -1 and int(rows[0].count) == 0 and float(rows[0].inset) == 2.5,
		"rows: on the main road, count AUTO, inset 2.5")
	t.check(absf(r.anchor_s(rows[0].at) - r.s[300]) < 1.0, "the row's anchor is the clicked spot")
	t.check(not it.click(_ground(ed, Vector3(0, 0, 0)), 0) or rows.size() == 2, "the ground is no road")
	t.check(rows.size() == 2, "nothing added off the road")
	it.set_mode("crate")
	it.click(_ground(ed, Vector3(20, 0, -20)), 0)
	t.check((ed.doc.data.crates as Array).size() == 1 and ItemsTool._v3(ed.doc.data.crates[0].pos).distance_to(Vector3(20, 1.2, -20)) < 0.01,
		"a single crate 1.2 m over the click")
	it.set_mode("pad")
	t.check(str(it.hints(_road_hit(ed, 120))).contains("LANE"), "pad hints: racing line and lane")
	it.click(_road_hit(ed, 120), 0)
	it.click(_road_hit(ed, 160, 3.0), EditorTool.MOD_SHIFT)
	var pads: Array = ed.doc.data.pads
	t.check(pads.size() == 2 and pads[0].lat == null and is_equal_approx(float(pads[1].lat), 3.0), "a pad on the racing line, one in the clicked lane")
	it.set_mode("barrels")
	it.click(_road_hit(ed, 240), 0)
	t.check((ed.doc.data.barrels as Array).size() == 1, "barrels")
	it.set_mode("zone")
	it.click(_road_hit(ed, 400), 0)
	it.click(_road_hit(ed, 200), 0)
	var zones: Array = ed.doc.data.zones
	var za := r.anchor_s(zones[0].a)
	var zb := r.anchor_s(zones[0].b)
	t.check(zones.size() == 2 and absf(za - (r.s[400] - 30.0)) < 1.0 and absf(zb - (r.s[400] + 30.0)) < 1.0
		and is_equal_approx(float(zones[0].scale), 0.4) and is_equal_approx(float(zones[0].ease), 15.0), "a 60 m zone round the click")
	t.check(ed.history.position() == steps + 8, "one undo step each (%d)" % (ed.history.position() - steps))
	# the build, in doc order
	var b := LevelCompiler.compile(ed.doc, {"id": CustomTracks.EDIT_ID, "registries": CaseSelect.REG})
	var boxes: Array = b.data.get("item_boxes", [])
	var per := 0
	var count_ok := boxes.size() >= 3
	if count_ok:
		per = (boxes.size() - 1) / 2
	var first := ItemsTool._v3(boxes[0]) if count_ok else Vector3.ZERO
	t.check(count_ok and first.distance_to(r.pos[300]) < first.distance_to(r.pos[60]), "the first row's crates come first (doc order)")
	t.check(count_ok and ItemsTool._v3(boxes[-1]).distance_to(Vector3(20, 1.2, -20)) < 0.01, "then the single crate")
	var bp: Array = b.data.get("boost_pads", [])
	t.check(bp.size() == 2 and ItemsTool._v3(bp[0].pos).distance_to(r.pos[120]) < ItemsTool._v3(bp[1].pos).distance_to(r.pos[120]),
		"two boost pads in doc order")
	var p1 := ItemsTool._v3(bp[1].pos) if bp.size() == 2 else Vector3.ZERO
	t.check(bp.size() == 2 and absf(r.lateral(p1, r.closest(p1)) - 3.0) < 0.2, "the lane pad 3 m right")
	var lg: Array = b.data.get("low_gravity", [])
	t.check(lg.size() == 2 and absf(float(lg[0].s0) - za) < 0.5 and absf(float(lg[1].s0) - r.anchor_s(zones[1].a)) < 0.5,
		"both zones in data.low_gravity in doc order")
	var drums := 0
	for p in b.data.get("props", []):
		if str(p.get("model", "")) == LevelCompiler.BARREL_MODEL:
			drums += 1
	t.check(drums == 3, "three drums from the barrels (%d)" % drums)
	# markers, warnings
	ed._refresh_markers()
	var kinds := {}
	for e in ed.markers.entries("items"):
		kinds["%s:%d" % [e.kind, int(e.sub)]] = true
	t.check(kinds.has("item_row:0") and kinds.has("crate:0") and kinds.has("pad:0") and kinds.has("barrels:0")
		and kinds.has("zone:3") and kinds.has("zone:4"), "markers for every kind, zones with two end bars (%s)" % str(kinds.keys()))
	it.set_mode("pad")
	it.click(_road_hit(ed, r.n - 6), 0)
	var near_grid := int(ed.doc.data.pads[-1].uid)
	var warn := it.warning_map()
	t.check(warn.has(near_grid) and str(warn[near_grid]).contains("grid"), "a pad by the grid is flagged (%s)" % str(warn.get(near_grid)))
	t.check(not warn.has(int(pads[0].uid)), "the pad out on the road is not")
	var box := VBoxContainer.new()
	t.check(it.inspect(PackedInt32Array([near_grid]), box), "the pad inspector")
	var red := false
	for c in box.get_children():
		if c is PromptLabel and (c as PromptLabel).prompt.contains("GRID"):
			red = true
	t.check(red, "the inspector shows the warning")
	box.free()
	ed.history.undo()
	# zone end bar slid along the road
	var zu := int(zones[0].uid)
	var bar := CaseSelect.hit_at(ed, r.pos[r.idx(zb)], "marker", zu, "zone")
	bar.sub = 4
	t.check(it.drag_begin(bar, 0), "a zone's end bar drags")
	it.drag_move(_ground(ed, r.pos[r.idx(zb + 10.0)]), 0)
	it.drag_end(_ground(ed, r.pos[r.idx(zb + 20.0)]), 0)
	t.check(absf(r.anchor_s(ed.doc.find(zu).item.b) - (zb + 20.0)) < 2.5 and absf(r.anchor_s(ed.doc.find(zu).item.a) - za) < 0.01,
		"the end moved, the other stayed")
	t.check(ed.history.undo_name() == "MOVE LOW GRAVITY ZONE", "one step (%s)" % ed.history.undo_name())
	ed.history.undo()
	t.check(absf(r.anchor_s(ed.doc.find(zu).item.b) - zb) < 0.01, "undone")
	# a row slid from SELECT through slide()
	var ru := int(rows[0].uid)
	it.slide(ru, CaseSelect.hit_at(ed, r.pos[300], "marker", ru, "item_row"), 0)
	var ops := it.slide(ru, _ground(ed, r.pos[320]), 2)
	t.check(ops.size() == 1 and str(ops[0][1]) == str(["items", "#%d" % ru, "at"]), "slide() re-anchors a row")
	# inspector of a row
	box = VBoxContainer.new()
	t.check(it.inspect(PackedInt32Array([ru]), box) and box.get_child_count() >= 3, "the row inspector")
	box.free()
	t.check(it.counts_text().begins_with("ROWS 2 / 40 · CRATES 1 / 64"), "the counts (%s)" % it.counts_text())
	# AUTO ITEMS
	var before := (ed.doc.data.items as Array).size()
	ed.last_toast = ""
	var pos0 := ed.history.position()
	it.auto_items()
	for k in 200:
		if ed.history.position() != pos0 or ed.last_toast != "":
			break
		await t.wait(0.05)
	t.check(ed.history.undo_name() == "AUTO ITEMS" or ed.last_toast == "No crate rows to add.",
		"AUTO ITEMS runs on a bake (%s, %s)" % [ed.history.undo_name(), ed.last_toast])
	if ed.history.undo_name() == "AUTO ITEMS":
		t.check((ed.doc.data.items as Array).size() > before, "and adds crate rows")
		ed.history.undo()
	while ed.history.position() > steps:
		ed.history.undo()
	t.check((ed.doc.data.items as Array).is_empty() and (ed.doc.data.zones as Array).is_empty(), "all undone")


# ---------------------------------------------------------------- CROWDS

func _crowds(ed: TrackEditor) -> void:
	ed.set_tool("crowds")
	var ct := ed.tools["crowds"] as CrowdsTool
	var r := _road(ed)
	var steps := ed.history.position()
	var w := r.width[80] * 0.5
	ct.set_mode("group")
	t.check(ct.click(_ground(ed, r.surface(80, w + 5.0)), 0), "a click beside the road")
	t.check(ct.click(_ground(ed, r.surface(200, -w - 5.0)), 0), "and one on the other side")
	var groups: Array = ed.doc.data.crowds
	t.check(groups.size() == 2 and int(groups[0].side) == 1 and int(groups[1].side) == -1 and float(groups[0].length) == 20.0
		and str(groups[0].role) == "citizen", "two groups, each on its side, 20 m of citizens")
	t.check(absf(r.anchor_s(groups[0].at) - r.s[80]) < 1.5, "anchored at the click")
	ct.click(_ground(ed, Vector3(0, 0, 0)), 0)
	t.check(groups.size() == 2, "nothing far from a road")
	# an end bar makes it longer
	var gu := int(groups[0].uid)
	var s0 := r.anchor_s(groups[0].at)
	var bar := CaseSelect.hit_at(ed, r.surface(r.idx(s0 + 10.0), w + 5.0), "marker", gu, "crowd")
	bar.sub = 4
	t.check(ct.drag_begin(bar, 0), "an end bar drags")
	ct.drag_end(_ground(ed, r.surface(r.idx(s0 + 20.0), w + 5.0)), 0)
	var g: Dictionary = ed.doc.find(gu).item
	t.check(absf(float(g.length) - 30.0) < 2.5 and absf(r.anchor_s(g.at) - (s0 + 5.0)) < 1.5,
		"the end moved 10 m: 30 m long, the other end kept (%s m)" % str(g.length))
	ed.history.undo()
	# the body slides
	var body := CaseSelect.hit_at(ed, r.surface(r.idx(s0), w + 5.0), "marker", gu, "crowd")
	ct.drag_begin(body, 0)
	ct.drag_end(_ground(ed, r.surface(r.idx(s0 + 30.0), w + 5.0)), 0)
	t.check(absf(r.anchor_s(ed.doc.find(gu).item.at) - (s0 + 30.0)) < 2.5, "the group slides along the road")
	ed.history.undo()
	ed._refresh_markers()
	var subs := {}
	for e in ed.markers.entries("crowds"):
		if e.kind == "crowd" and int(e.uid) == gu:
			subs[int(e.sub)] = true
	t.check(subs.has(0) and subs.has(3) and subs.has(4), "group marker and two end bars")
	var box := VBoxContainer.new()
	t.check(ct.inspect(PackedInt32Array([gu]), box) and box.get_child_count() >= 9, "the crowd inspector (%d rows)" % box.get_child_count())
	box.free()
	# eggs
	ct.set_mode("gman")
	ct.click(_ground(ed, Vector3(10, 0, 10)), 0)
	var eggs: Array = ed.doc.data.eggs
	t.check(eggs.size() == 1 and str(eggs[0].kind) == "gman" and is_equal_approx(float(eggs[0].chance), 0.5), "the G-Man")
	ct.set_mode("zombies")
	ct.click(_ground(ed, Vector3(-10, 0, 10)), 0)
	t.check(str(ct.hints(_ground(ed, Vector3(-20, 0, 10)))).contains("PATH"), "Ctrl + click adds a path point (hint)")
	ct.click(_ground(ed, Vector3(-20, 0, 10)), EditorTool.MOD_CTRL)
	ct.click(_ground(ed, Vector3(-30, 0, 14)), EditorTool.MOD_CTRL)
	var z: Dictionary = eggs[-1]
	t.check(str(z.kind) == "zombies" and (z.path as Array).size() == 3 and int(z.count) == 3, "zombies with a 3-point path")
	ct.set_mode("birds")
	ct.click(_ground(ed, Vector3(0, 0, -10)), 0)
	t.check(str(eggs[-1].kind) == "birds" and str(eggs[-1].species) == "pigeon", "birds")
	t.check(ct.people_text() == "PEOPLE %d / 450" % int(ed.build.stats.get("people", 0)), "the PEOPLE counter (%s)" % ct.people_text())
	var b := LevelCompiler.compile(ed.doc, {"id": CustomTracks.EDIT_ID, "registries": CaseSelect.REG})
	t.check((b.data.get("crowd_groups", []) as Array).size() >= 1 and (b.data.get("crowd_eggs", []) as Array).size() >= 2,
		"the groups and the eggs are in the build (%d, %d)" % [(b.data.get("crowd_groups", []) as Array).size(), (b.data.get("crowd_eggs", []) as Array).size()])
	while ed.history.position() > steps:
		ed.history.undo()
	t.check((ed.doc.data.crowds as Array).is_empty() and (ed.doc.data.eggs as Array).is_empty(), "undone")


# ---------------------------------------------------------------- delete + undo

func _delete_undo(ed: TrackEditor) -> void:
	var r := _road(ed)
	var steps := ed.history.position()
	ed.set_tool("objects")
	var ot := _ot(ed)
	ot.pick_model(KEYS[0])
	ot.click(_ground(ed, Vector3(10, 0, -30)), 0)
	ot.pick_fx("light")
	ot.click(_ground(ed, Vector3(14, 0, -30)), 0)
	ot.end_stamping()
	var it := ed.tools["items"] as ItemsTool
	it.place_row(it.road_spot(_road_hit(ed, 100)))
	it.place_crate(Vector3(0, 0, -50))
	it.place_pad(it.road_spot(_road_hit(ed, 130)), false)
	it.place_barrels(it.road_spot(_road_hit(ed, 160)))
	it.place_zone(it.road_spot(_road_hit(ed, 190)))
	var ct := ed.tools["crowds"] as CrowdsTool
	ct.place_group(it.road_spot(_road_hit(ed, 220, 5.0)))
	ct.place_egg("gnome", Vector3(5, 0, 5))
	var json0 := JSON.stringify(ed.doc.data)
	var all := PackedInt32Array()
	for sec in ["props", "lights", "items", "crates", "pads", "barrels", "zones", "crowds", "eggs"]:
		for e in ed.doc.data[sec]:
			all.append(int(e.uid))
	t.check(all.size() == 9, "one item of every kind (%d)" % all.size())
	var aabb_ok := true
	for u in all:
		var k := ed.kind_of(u)
		var own := SelectTool.owner_tool(ed, k)
		var bx := own.item_aabb(u) if own != null else AABB()
		aabb_ok = aabb_ok and (bx.has_volume() or bx.position != Vector3.ZERO)
	t.check(aabb_ok, "every kind has a box (framing, box select)")
	var pos := ed.history.position()
	ed.select(all)
	SelectTool.delete_selection(ed)
	var left := 0
	for sec in ["props", "lights", "items", "crates", "pads", "barrels", "zones", "crowds", "eggs"]:
		left += (ed.doc.data[sec] as Array).size()
	t.check(left == 0 and ed.history.position() == pos + 1, "Delete takes them all in one undo step")
	ed.history.undo()
	t.check(JSON.stringify(ed.doc.data) == json0, "undo brings back the same document")
	while ed.history.position() > steps:
		ed.history.undo()
	t.check(r != null, "done")


# ---------------------------------------------------------------- content

func _content(ed: TrackEditor) -> void:
	PropCatalog.set_source({})
	var ot := _ot(ed)
	ed.set_tool("objects")
	ot.catalog.set_tab(PropCatalog.TAB_ALL)
	ot.catalog.refresh()
	var all := PropCatalog.keys(PropCatalog.TAB_ALL)
	t.check(all.size() > 300 and ot.catalog.shown().size() == all.size(), "the real catalog: %d models in ALL" % all.size())
	t.check(KEYS[0] in all and PropCatalog.physics_ok(KEYS[0]) and not PropCatalog.physics_ok(KEYS[3]),
		"a crate may be a physics object, a pine tree may not")
	var steps := ed.history.position()
	ot.set_mode("stamp")
	ot.pick_model(KEYS[0])
	var u := ot.stamp(_ground(ed, Vector3(25, 0, -25)))
	ot.pick_model(KEYS[3])
	var u2 := ot.stamp(_ground(ed, Vector3(35, 0, -25)))
	ot.set_physics(PackedInt32Array([u, u2]), true)
	t.check(bool(ed.doc.find(u).item.physics) and not bool(ed.doc.find(u2).item.physics), "PHYSICS only for the light model")
	var box := VBoxContainer.new()
	t.check(ot.inspect(PackedInt32Array([u2]), box), "the prop inspector")
	var ph_disabled := false
	for row in box.get_children():
		if row is HBoxContainer and row.get_child_count() > 1 and (row.get_child(0) as Label) != null and (row.get_child(0) as Label).text == "PHYSICS":
			ph_disabled = (row.get_child(1) as CheckButton).disabled
	t.check(ph_disabled, "its PHYSICS switch is greyed")
	box.free()
	var b := LevelCompiler.compile(ed.doc, {"id": CustomTracks.EDIT_ID})
	var found := 0
	for p in b.data.get("props", []):
		if str(p.get("model", "")) in [KEYS[0], KEYS[3]]:
			found += 1
	t.check(found == 2, "the real models are in the build (%d)" % found)
	await t.frames(10)
	t.check(ed.view.node_of(u) != null, "the view shows the stamped model")
	ot.end_stamping()
	while ed.history.position() > steps:
		ed.history.undo()
