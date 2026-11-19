extends RefCounted
## editor/case_hazards_tool (P19, CI): the HAZARDS tool (1.6) in the editor scene with fabricated
## hits. The grouped list (21 entries, five groups, heavy counts); every type that needs no setup
## placed on the oval template (its side from the click, one undo step each, all compiled); a
## ceiling turret on the oval (no tunnel) and a level crossing in a tunnel refused with the reason;
## the setup types placed on a purpose-built stadium (tunnel, straights) on green and compiled
## without a setup error; a see-saw placement makes its stretch in the same undo step (undo takes
## both, deleting it takes both); antlions paint their sand band in the same step; DIFFICULTY
## rewrites p from LevelHazards.difficulty_p (the ceiling turret keeps its model); an ADVANCED edit
## makes it CUSTOM; points (Ctrl + click mines, Delete removes the selected one); zone end bars;
## the inspector rows, markers, tint, hints and lint lines.

const NEEDS_CONTENT := false
const CaseSelect := preload("res://tests/editor/case_select.gd")
const CaseHazards := preload("res://tests/level/case_hazards.gd")
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}

var t: Node


func run(tt: Node) -> void:
	t = tt
	var adv0 := HazardsTool.advanced_open
	_list()
	await _oval()
	await _stadium()
	HazardsTool.advanced_open = adv0


# ---------------------------------------------------------------- helpers

func _open(doc: LevelDoc, at: Vector3, h: float) -> TrackEditor:
	var ed: TrackEditor = await CaseSelect.open_editor(t, doc)
	ed.set_tool("hazards")
	CaseSelect.look_down(ed, at, h)
	await t.frames(2)
	return ed


func _ht(ed: TrackEditor) -> HazardsTool:
	return ed.tools["hazards"] as HazardsTool


## A road hit on the main road s metres along, lat across.
func _road_hit(ed: TrackEditor, s_m: float, lat := 0.0) -> EditorHit:
	var r := LevelFixes.road_of(ed.build, -1)
	var i := r.idx(s_m)
	var h := CaseSelect.hit_at(ed, r.surface(i, lat), "road")
	h.road = -1
	h.sample = i
	h.s = r.s[i]
	h.lat = lat
	return h


func _hazards(ed: TrackEditor) -> Array:
	return ed.doc.data.get("hazards", []) if ed.doc.data.get("hazards") is Array else []


func _hz(ed: TrackEditor, uid: int) -> Dictionary:
	return _ht(ed).item_of(uid)


func _compile(doc: LevelDoc) -> LevelBuild:
	return LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG, "flags": true})


func _by_type(b: LevelBuild, ty: String) -> Array:
	var out := []
	for e in b.data.get("hazards", []):
		if e is Dictionary and str(e.get("type", "")) == ty:
			out.append(e)
	return out


func _setup_errors(b: LevelBuild) -> Array:
	var out := []
	for it in b.report.items:
		if str(it.code) == "hazard_setup":
			out.append(str(it.text))
	return out


# ---------------------------------------------------------------- the list

func _list() -> void:
	var all := HazardsTool.choices()
	t.check(all.size() == 21, "the list has 21 entries (19 types, the ceiling turret and the arc zone apart): %d" % all.size())
	var groups := {}
	var types := {}
	for c in all:
		groups[str(c.group)] = true
		types[str(c.type)] = true
		t.check(str(c.desc).length() > 20, "%s has a one-line description" % str(c.label))
	t.check(groups.size() == 5 and types.size() == 19, "five groups, every one of the 19 types")
	var order := []
	for c in all:
		if order.is_empty() or order[-1] != str(c.group):
			order.append(str(c.group))
	t.check(order == HazardsTool.GROUPS, "grouped in the order TURRETS & SOLDIERS ... TRAINS & BRIDGES")
	var setups := []
	for c in all:
		if str(c.setup) != "":
			setups.append(str(c.setup))
	setups.sort()
	var want: Array = LevelHazards.SETUP_TYPES.duplicate()
	want.sort()
	t.check(setups == want, "the setup entries are LevelHazards.SETUP_TYPES")
	t.check(str(HazardsTool.choice_for({"type": "turret", "mount": "ceiling"}).id) == "turret_ceiling"
		and str(HazardsTool.choice_for({"type": "strike_zone", "style": "arc"}).id) == "strike_arc"
		and str(HazardsTool.choice_for({"type": "crane"}).id) == "crane", "a doc hazard finds its entry")


# ---------------------------------------------------------------- the oval: every type without a setup

func _oval() -> void:
	var doc := LevelTemplates.make("oval", "Hazards Oval")
	doc.data.hazards = []
	var ed := await _open(doc, Vector3.ZERO, 700.0)
	var ht := _ht(ed)
	var m := ed.road(-1)
	t.check(m != null and m.closed and ed.flags("hz_turret_ceiling").size() > 0, "the oval is baked with the hazard flags")
	if m == null:
		await CaseSelect.close_editor(t, ed)
		return
	# the options
	var box := VBoxContainer.new()
	ht.set_choice("strider")
	ht.options(box)
	var buttons := 0
	for b in box.find_children("*", "Button", true, false):
		if (b as Button).has_meta("hazard"):
			buttons += 1
	t.check(buttons == 21, "the options list a button per entry (%d)" % buttons)
	t.check(ht.desc_text().contains("HEAVY: 0 of 8"), "a heavy type says so: %s" % ht.desc_text())
	box.free()
	# every type without a setup, spread round the lap
	var plain := []
	for c in HazardsTool.choices():
		if str(c.setup) == "":
			plain.append(c)
	t.check(plain.size() == 14, "14 entries need no setup")
	var placed := {}
	var k := 0
	var step := m.length / float(plain.size() + 1)
	for c in plain:
		k += 1
		var s := 60.0 + step * (k - 1)
		var lat := 3.0 if k % 2 == 0 else -3.0
		ht.set_choice(str(c.id))
		var n0 := _hazards(ed).size()
		var u := ht.place(_road_hit(ed, s, lat))
		var hz := _hz(ed, u)
		var ok := u > 0 and _hazards(ed).size() == n0 + 1 and str(hz.get("type", "")) == str(c.type)
		t.check(ok, "%s placed on the oval (%s)" % [str(c.label), ht.refusal])
		t.check(ed.history.undo_name() == "ADD %s" % str(c.label), "one undo step: %s" % ed.history.undo_name())
		if not ok:
			continue
		placed[str(c.id)] = u
		var sides: Array = LevelHazards.TYPES[str(c.type)].placement.side
		if not sides.is_empty():
			t.check(int(hz.side) == (1 if lat > 0.0 else -1), "%s on the clicked side" % str(c.label))
		if str(c.mount) != "":
			t.check(str(hz.get("mount", "")) == str(c.mount), "the turret's mount")
		if str(c.style) != "":
			t.check(str(hz.get("style", "")) == str(c.style), "the strike zone's style %s" % str(c.style))
		var pl: Dictionary = LevelHazards.TYPES[str(c.type)].placement
		if bool(pl.at):
			t.check(hz.at is Dictionary and absf(m.anchor_s(hz.at) - m.s[m.idx(s)]) < 3.0, "%s anchored at the click" % str(c.label))
		else:
			t.check(hz.at == null and hz.zone is Array, "%s: a zone round the click, no anchor" % str(c.label))
		t.check(ed.selection.has(u), "the new hazard is selected")
	t.check(ht.heavy_count() == 3 and ht.counts_text() == "HAZARDS 14 / 48 · HEAVY 3 / 8", "counts: %s" % ht.counts_text())
	# markers: a triangle each, end bars for zones
	ed._refresh_markers()
	var tri := 0
	var bars := 0
	for e in ed.markers._lists.get("hazards", []):
		if int(e.shape) == EditorMarkers.Shape.TRIANGLE:
			tri += 1
		elif int(e.shape) == EditorMarkers.Shape.BAR:
			bars += 1
	t.check(tri == 14 and bars >= 2 * 9, "a triangle per hazard (%d) and zone end bars (%d)" % [tri, bars])
	# all of them compile
	var b := _compile(ed.doc)
	var missing := []
	for c in plain:
		var want := 1
		if str(c.type) in ["turret", "strike_zone"]:
			want = 1
		var got := 0
		for e in _by_type(b, str(c.type)):
			got += 1
		if got < want:
			missing.append(str(c.type))
	t.check(missing.is_empty() and (b.data.hazards as Array).size() == 14 and _setup_errors(b).is_empty(),
		"all 14 compile on the oval (%d entries; missing %s)" % [(b.data.hazards as Array).size(), str(missing)])
	# a click on red: the ceiling turret needs a tunnel
	ht.set_choice("turret_ceiling")
	ed.draw.clear()
	ht.overlay(ed.draw)
	t.check(int(ed.draw.vertex_count().tris) > 0, "the legal-spot tint is drawn for a setup type")
	var red := _road_hit(ed, 300.0)
	t.check(not ht.legal_at("turret_ceiling", red.sample), "the oval has no tunnel: red for a ceiling turret")
	t.check(str(ht.hints(red)).contains("NO CEILING TURRET HERE"), "the hint says no")
	var n1 := _hazards(ed).size()
	var undo1 := ed.history.undo_name()
	ed.click(red, 0)
	t.check(_hazards(ed).size() == n1 and ed.history.undo_name() == undo1, "a click on red is refused: nothing added")
	t.check(ed.status_text == "A ceiling turret needs a tunnel." and ht.status_step() == ed.status_text,
		"the reason in the status line: %s" % ed.status_text)
	# DIFFICULTY and ADVANCED on the floor turret
	var tu := int(placed.get("turret", 0))
	if tu > 0:
		_difficulty(ed, tu)
	# the inspector of a zone type
	var gu := int(placed.get("antlion_guard", 0))
	if gu > 0:
		_inspector(ed, gu)
		_zone_bars(ed, gu)
	var mu := int(placed.get("minefield", 0))
	if mu > 0:
		await _points(ed, mu)
	await CaseSelect.close_editor(t, ed)


func _difficulty(ed: TrackEditor, uid: int) -> void:
	var ht := _ht(ed)
	var steps := ed.history.undo_name()
	ht.set_feel(uid, "brutal")
	var hz := _hz(ed, uid)
	var want := LevelHazards.difficulty_p("turret", "brutal")
	var same := true
	for row in LevelHazards.params_of(hz):
		if str(row[6]) in ["T", "P"] and str(hz.p.get(row[0])) != str(want[row[0]]):
			same = false
	t.check(same and str(hz.feel) == "brutal", "BRUTAL rewrites p: %s" % JSON.stringify(hz.p))
	t.check(float(hz.p.lock) < 0.9 and float(hz.p.range) > 40.0, "BRUTAL: less time, more power")
	t.check(ed.history.undo_name() == "DIFFICULTY: BRUTAL" and ed.history.undo_name() != steps, "one undo step")
	ht.set_feel(uid, "easy")
	hz = _hz(ed, uid)
	t.check(str(hz.feel) == "easy" and float(hz.p.lock) > 0.9 and str(hz.p.range) == str(LevelHazards.difficulty_p("turret", "easy").range),
		"EASY rewrites p the other way")
	# an ADVANCED edit makes it CUSTOM
	ht.set_param(uid, "range", 52.0, true)
	hz = _hz(ed, uid)
	t.check(str(hz.feel) == "custom" and float(hz.p.range) == 52.0 and float(hz.p.lock) > 0.9, "an ADVANCED edit: CUSTOM, the rest kept")
	ht.set_feel(uid, "normal")
	hz = _hz(ed, uid)
	t.check(str(hz.feel) == "normal" and float(hz.p.range) == 40.0 and float(hz.p.lock) == 0.9, "NORMAL: the defaults again")
	# through the inspector's ADVANCED rows
	HazardsTool.advanced_open = true
	var box := VBoxContainer.new()
	t.check(ht.inspect(PackedInt32Array([uid]), box), "the turret's inspector")
	var labels := _labels(box)
	t.check(labels.has("SIDE") and labels.has("ZONE") and labels.has("DIFFICULTY") and labels.has("MOUNT"), "SIDE, ZONE, DIFFICULTY, MOUNT rows")
	t.check(labels.has("SETBACK") and labels.has("RANGE") and labels.has("LOCK TIME") and labels.has("MODEL"), "ADVANCED: SETBACK and the params")
	var num := _number_in(box, "COOL DOWN")
	t.check(num != null, "the COOL DOWN field")
	if num != null:
		num.set_value(8.0, true)
		hz = _hz(ed, uid)
		t.check(str(hz.feel) == "custom" and float(hz.p.cool) == 8.0, "typing in ADVANCED makes it CUSTOM (%s)" % str(hz.feel))
	box.free()
	HazardsTool.advanced_open = false
	box = VBoxContainer.new()
	ht.inspect(PackedInt32Array([uid]), box)
	t.check(not _labels(box).has("RANGE"), "ADVANCED collapsed: no param rows")
	box.free()


func _inspector(ed: TrackEditor, uid: int) -> void:
	var ht := _ht(ed)
	var box := VBoxContainer.new()
	t.check(ht.inspect(PackedInt32Array([uid]), box), "the guard's inspector")
	var labels := _labels(box)
	t.check(labels.has("TYPE") and labels.has("SIDE") and labels.has("ZONE") and labels.has("DIFFICULTY") and not labels.has("MOUNT"),
		"TYPE, SIDE, ZONE, DIFFICULTY (no MOUNT)")
	box.free()
	ht.set_side(uid, 1)
	t.check(int(_hz(ed, uid).side) == 1 and ed.history.undo_name() == "HAZARD SIDE", "SIDE: one step")
	var z0 := ht.zone_s(_hz(ed, uid))
	var s := ht.hazard_s(_hz(ed, uid))
	ht.set_zone(uid, -50.0, NAN)
	var z1 := ht.zone_s(_hz(ed, uid))
	t.check(absf(float(z1[0]) - (s - 50.0)) < 1.5 and absf(float(z1[1]) - float(z0[1])) < 1.5, "ZONE start typed: %.1f .. %.1f" % [z1[0], z1[1]])
	# the guard's zone stays 60-160 m long
	ht.set_zone(uid, NAN, -40.0)
	var z2 := ht.zone_s(_hz(ed, uid))
	t.check(float(z2[1]) - float(z2[0]) >= 59.0, "the zone keeps the type's least length (%.1f m)" % (float(z2[1]) - float(z2[0])))


func _zone_bars(ed: TrackEditor, uid: int) -> void:
	var ht := _ht(ed)
	var m := ed.road(-1)
	var z := ht.zone_s(_hz(ed, uid))
	var end_b := m.surface(m.idx(float(z[1])), 0.0, 0.5)
	var hit := CaseSelect.hit_at(ed, end_b, "marker", uid, "hazard")
	hit.sub = HazardsTool.SUB_B
	t.check(str(ht.hints(hit)).contains("THIS END"), "an end bar's hint")
	t.check(ht.drag_begin(hit, 0), "an end bar drag starts")
	var to := m.surface(m.idx(ItemsTool.wrap_s(m, float(z[1]) + 30.0)), 0.0)
	ht.drag_move(CaseSelect.hit_at(ed, to, "road"), 0)
	ht.drag_end(CaseSelect.hit_at(ed, to, "road"), 0)
	var z2 := ht.zone_s(_hz(ed, uid))
	t.check(absf(float(z2[1]) - float(z[1]) - 30.0) < 3.0 and absf(float(z2[0]) - float(z[0])) < 1.0,
		"the end bar moved that end 30 m (%.1f -> %.1f)" % [z[1], z2[1]])
	t.check(ed.history.undo_name() == "HAZARD ZONE", "one undo step for the drag")
	# the body slides the whole hazard
	var p := ht.marker_pos(_hz(ed, uid))
	var body := CaseSelect.hit_at(ed, p, "marker", uid, "hazard")
	ht.drag_begin(body, 0)
	var s0 := ItemsTool.s_near(m, p)
	var to2 := m.surface(m.idx(ItemsTool.wrap_s(m, s0 + 20.0)), 0.0)
	ht.drag_move(CaseSelect.hit_at(ed, to2, "road"), 0)
	ht.drag_end(CaseSelect.hit_at(ed, to2, "road"), 0)
	var z3 := ht.zone_s(_hz(ed, uid))
	t.check(absf(float(z3[0]) - float(z2[0]) - 20.0) < 3.0 and absf(float(z3[1]) - float(z2[1]) - 20.0) < 3.0, "the body slides the zone 20 m")


func _points(ed: TrackEditor, uid: int) -> void:
	var ht := _ht(ed)
	ed.select(PackedInt32Array([uid]))
	var s := ht.hazard_s(_hz(ed, uid))
	t.check(ht.points_target() == uid, "Ctrl + click adds to the selected minefield")
	t.check(str(ht.hints(_road_hit(ed, s + 5.0))).contains("ADD A MINE"), "the hint offers a mine")
	for k in 5:
		ed.click(_road_hit(ed, s - 10.0 + 5.0 * k, -2.0 + k), EditorTool.MOD_CTRL)
	var pts: Array = _hz(ed, uid).pts
	t.check(pts.size() == 5 and pts[0] is Dictionary and pts[0].at is Dictionary and _num(pts[0].lat), "five mines {at, lat} (%d)" % pts.size())
	t.check(ed.history.undo_name() == "ADD MINE", "each mine is a step")
	ed._refresh_markers()
	var dots := 0
	for e in ed.markers._lists.get("hazards", []):
		if str(e.kind) == "hazard_point" and int(e.uid) == uid:
			dots += 1
	t.check(dots == 5, "a dot per mine (%d)" % dots)
	# click the third, Delete removes it
	var q := ht.point_pos(_hz(ed, uid), 2)
	var ph := CaseSelect.hit_at(ed, q, "marker", uid, "hazard_point")
	ph.sub = HazardsTool.POINT_SUB + 2
	ed.click(ph, 0)
	t.check(ht.point.get("k", -1) == 2 and ed.selection.has(uid), "a click picks the point (and selects its hazard)")
	var keep: Array = (_hz(ed, uid).pts as Array).duplicate(true)
	CaseSelect.key(ed, KEY_DELETE)
	pts = _hz(ed, uid).pts
	t.check(pts.size() == 4 and not _hz(ed, uid).is_empty(), "Delete removes the selected point, the hazard stays")
	t.check(JSON.stringify(pts[2]) == JSON.stringify(keep[3]), "the right point went")
	ed.history.undo()
	t.check(JSON.stringify(_hz(ed, uid).pts) == JSON.stringify(keep), "undo puts it back")
	# a mine dragged along
	var q2 := ht.point_pos(_hz(ed, uid), 0)
	var dh := CaseSelect.hit_at(ed, q2, "marker", uid, "hazard_point")
	dh.sub = HazardsTool.POINT_SUB
	ht.drag_begin(dh, 0)
	var dest := _road_hit(ed, s - 30.0, 4.0)
	ht.drag_move(dest, 0)
	ht.drag_end(dest, 0)
	var p0: Dictionary = _hz(ed, uid).pts[0]
	t.check(absf(float(p0.lat) - 4.0) < 0.6 and absf(ed.road(-1).anchor_s(p0.at) - dest.s) < 3.0, "a mine dragged to a new spot")
	# Delete with the hazard (not a point) selected deletes the whole hazard through SELECT
	ht.point = {}
	var n0 := _hazards(ed).size()
	ed.select(PackedInt32Array([uid]))
	CaseSelect.key(ed, KEY_DELETE)
	t.check(_hazards(ed).size() == n0 - 1 and _hz(ed, uid).is_empty(), "Delete on the hazard removes it")
	ed.history.undo()
	t.check(not _hz(ed, uid).is_empty(), "and undo brings it back")
	await t.frames(1)


# ---------------------------------------------------------------- the stadium: the setup types

func _stadium() -> void:
	var doc := LevelDoc.blank("Hazards Setup", 1024.0, 513)
	var pts := CaseHazards.stadium(doc, {14: {"style": "tunnel"}})
	doc.data.hazards = []
	var ed := await _open(doc, Vector3.ZERO, 900.0)
	var ht := _ht(ed)
	var m := ed.road(-1)
	if m == null or ed.flags("hz_seesaw").is_empty():
		t.fail("the stadium is baked with flags")
		await CaseSelect.close_editor(t, ed)
		return
	# refused: a level crossing in the tunnel
	ht.set_choice("train")
	var n0 := _hazards(ed).size()
	t.check(ht.place(_road_hit(ed, 1321.0)) == 0 and _hazards(ed).size() == n0, "a level crossing in the tunnel is refused")
	t.check(ht.refusal.begins_with("A level crossing needs an open road or a street"), "with the reason: %s" % ht.refusal)
	# the see-saw: its segment becomes the stretch in the same undo step
	ht.set_choice("seesaw")
	var seg_uid := int(pts[2].uid)
	t.check(ht.legal_at("seesaw", m.idx(250.0)), "the right straight's segment is green for a see-saw")
	var su := ht.place(_road_hit(ed, 250.0))
	var shz := _hz(ed, su)
	t.check(su > 0 and bool(ed.doc.find(seg_uid).item.get("seesaw", false)) and int(shz.at.p) == seg_uid,
		"the see-saw sits on its segment, which is now a see-saw stretch")
	t.check(ed.history.undo_name() == "ADD SEE-SAW BRIDGE", "one undo step: %s" % ed.history.undo_name())
	ed.history.undo()
	t.check(not bool(ed.doc.find(seg_uid).item.get("seesaw", false)) and _hz(ed, su).is_empty(), "undo takes the stretch and the see-saw back together")
	ed.history.redo()
	t.check(bool(ed.doc.find(seg_uid).item.get("seesaw", false)) and not _hz(ed, su).is_empty(), "redo: both again")
	t.check(ht.slide(su, CaseSelect.hit_at(ed, m.pos[m.idx(250.0)], "marker", su, "hazard"), 0).is_empty()
		and ht.slide(su, CaseSelect.hit_at(ed, m.pos[m.idx(290.0)], "road"), 1).is_empty(), "a see-saw does not slide off its stretch")
	# antlions paint their sand band in the same step
	ht.set_choice("antlion")
	var s_ant := 800.0
	t.check(ht.legal_at("antlion", m.idx(s_ant)), "the top bend is green for antlions")
	var splat0 := ed.doc.splat.duplicate()
	var au := ht.place(_road_hit(ed, s_ant, 4.0))
	t.check(au > 0 and int(_hz(ed, au).side) == 1, "antlions placed on the right")
	var t_live := LevelTerrain.from_doc(ed.doc)
	var i := m.idx(s_ant)
	var q := m.pos[i] + m.flat_right[i] * (m.width[i] * 0.5 + m.treatment(i, 1) + 8.0)
	var c := t_live.cell_of(q.x, q.z)
	var at4 := (c.y * t_live.res + c.x) * 4 + 3
	var ql := m.pos[i] - m.flat_right[i] * (m.width[i] * 0.5 + m.treatment(i, 0) + 8.0)
	var cl := t_live.cell_of(ql.x, ql.z)
	var at4l := (cl.y * t_live.res + cl.x) * 4 + 3
	t.check(ed.doc.splat[at4] > splat0[at4] + 100 and ed.doc.splat[at4l] == splat0[at4l],
		"the sand band is painted on its side (%d -> %d), not the other (%d)" % [splat0[at4], ed.doc.splat[at4], ed.doc.splat[at4l]])
	t.check(ed.history.undo_name() == "ADD ANTLIONS", "hazard and sand: one undo step")
	ed.history.undo()
	t.check(ed.doc.splat == splat0 and _hz(ed, au).is_empty(), "undo: the sand and the antlions go together")
	ed.history.redo()
	# the other setup types on green
	var spots := {"turret_ceiling": [1321.0, 0.0], "tripmine": [120.0, -5.0], "tentacle": [380.0, 5.0], "column": [1150.0, 0.0],
		"train": [450.0, 0.0]}
	for cid in spots:
		ht.set_choice(cid)
		var sv: Array = spots[cid]
		var sg := _green_near(ed, str(HazardsTool.choice_of(cid).setup), float(sv[0]))
		t.check(not is_nan(sg) and absf(sg - float(sv[0])) <= 60.0, "%s: green near %d m (%.0f)" % [cid, int(sv[0]), sg])
		if is_nan(sg):
			continue
		var hit := _road_hit(ed, sg, float(sv[1]))
		t.check(ht.legal_at(str(HazardsTool.choice_of(cid).setup), hit.sample), "%s: green at %d m" % [cid, int(sg)])
		t.check(str(ht.hints(hit)).contains("CLICK PLACE"), "%s: the hint offers it" % cid)
		var n1 := _hazards(ed).size()
		ed.click(hit, 0)
		t.check(_hazards(ed).size() == n1 + 1, "%s placed through a click (%s)" % [cid, ht.refusal])
	var ce := {}
	for h in _hazards(ed):
		if str(h.type) == "turret" and str(h.get("mount", "")) == "ceiling":
			ce = h
	t.check(not ce.is_empty() and _num(ce.get("lat")), "the ceiling turret: mount and lat")
	if ce.is_empty():
		await CaseSelect.close_editor(t, ed)
		return
	# the ceiling turret keeps its model through DIFFICULTY
	ht.set_feel(int(ce.uid), "brutal")
	var cp: Dictionary = _hz(ed, int(ce.uid)).p
	t.check(not cp.has("model") and not cp.has("scale") and cp.has("range"), "DIFFICULTY leaves the ceiling turret's model alone")
	# all of them compile with their setups
	var b := _compile(ed.doc)
	var kinds := {}
	for e in b.data.hazards:
		kinds[str(e.type)] = true
	t.check(_setup_errors(b).is_empty(), "no setup errors: %s" % str(_setup_errors(b)))
	t.check(kinds.has("seesaw") and kinds.has("antlion") and kinds.has("turret") and kinds.has("tripmine") and kinds.has("tentacle")
		and kinds.has("column") and kinds.has("train"), "every setup type is in the build: %s" % str(kinds.keys()))
	t.check(b.meshes != null, "the setups are built")
	# lint lines in the inspector, from the bake
	ed.build = b
	var lint := ht.lint_map()
	var box := VBoxContainer.new()
	ht.inspect(PackedInt32Array([int(ce.uid)]), box)
	box.free()
	t.check(lint is Dictionary, "lint map from the bake (%d hazards with lines)" % lint.size())
	if not lint.is_empty():
		var lu := int(lint.keys()[0])
		var box2 := VBoxContainer.new()
		ht.inspect(PackedInt32Array([lu]), box2)
		var lines := 0
		for ch in box2.get_children():
			if ch.has_meta("lint"):
				lines += 1
		t.check(lines > 0, "the inspector shows its lint lines (%d)" % lines)
		box2.free()
	# deleting the see-saw takes its stretch
	var ops := ht.delete_ops(PackedInt32Array([su]))
	ed.commit("DELETE", ops)
	t.check(_hz(ed, su).is_empty() and not bool(ed.doc.find(seg_uid).item.get("seesaw", false)), "deleting the see-saw takes its stretch too")
	ed.history.undo()
	t.check(not _hz(ed, su).is_empty() and bool(ed.doc.find(seg_uid).item.get("seesaw", false)), "undo: both back")
	# a setup type does not slide onto red: the column into the tunnel
	var cu := 0
	for h in _hazards(ed):
		if str(h.type) == "column":
			cu = int(h.uid)
	if cu > 0:
		var cpos := ht.marker_pos(_hz(ed, cu))
		ht.slide(cu, CaseSelect.hit_at(ed, cpos, "marker", cu, "hazard"), 0)
		var ops2 := ht.slide(cu, CaseSelect.hit_at(ed, m.pos[m.idx(470.0 + (1321.0 - 470.0))], "road"), 1)
		t.check(ops2.is_empty() and ed.status_text.begins_with("A Combine column needs open sky"), "a column does not slide into the tunnel")
		ht.slide(cu, CaseSelect.hit_at(ed, m.pos[m.idx(470.0)], "road"), 2)
	await CaseSelect.close_editor(t, ed)


## The lap metres of the green sample of `key` nearest s (NAN none within 200 m).
func _green_near(ed: TrackEditor, key: String, s_m: float) -> float:
	var m := ed.road(-1)
	var ht := _ht(ed)
	for d in range(0, 201, 2):
		for sg in [1.0, -1.0]:
			var s := ItemsTool.wrap_s(m, s_m + sg * d)
			if ht.legal_at(key, m.idx(s)):
				return m.s[m.idx(s)]
	return NAN


# ---------------------------------------------------------------- widget lookups

static func _labels(box: Node) -> Dictionary:
	var out := {}
	for l in box.find_children("*", "Label", true, false):
		out[(l as Label).text] = true
	return out


## The EditorNumber in the row labelled `label`.
static func _number_in(box: Node, label: String) -> EditorNumber:
	for h in box.find_children("*", "HBoxContainer", true, false):
		var kids := h.get_children()
		if kids.size() >= 2 and kids[0] is Label and (kids[0] as Label).text == label and kids[1] is EditorNumber:
			return kids[1] as EditorNumber
	return null


static func _num(v: Variant) -> bool:
	return v is float or v is int
