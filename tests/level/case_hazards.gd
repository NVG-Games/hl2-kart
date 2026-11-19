extends RefCounted
## P14: hazards, compile side (spec 4.2) on hand-made stadium documents, without content: every one
## of the 19 types (and the ceiling turret, the arc zone) compiles into an entry whose `p` keys are
## keys of its class's defaults() (the class script instanced without a tree) plus BASE_KEYS; the
## DIFFICULTY rows move T and P params the right way; seeds stay across a save / load, a rename and a
## reorder; the setups (barrier cut, see-saw dip, rails, portals, signals, footbridge, wall stub) and
## the setup failures (left out with `hazard_setup`); the tentacle's pit lowered by the carve; legal
## spots; see-saw ops; each lint rule on a crafted case; two compiles identical. With content: a c_
## oval with hazards is written for `tests/hazard_test.tscn -- rules / determinism` (P14 report).

const NEEDS_CONTENT := false
const TIMEOUT := 240.0
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}
const R := 150.0
## Where the content run writes the c_ oval for hazard_test (a folder of its own: not mine_dir).
const SHARE_DIR := "user://hazard_test_tracks"

var t: Node


## A spy on the hazards hook: LevelHazards' own functions, remembering the last context lint saw.
class Spy:
	static var ctx: LevelContext = null

	static func pre_geometry(c: LevelContext) -> void:
		LevelHazards.pre_geometry(c)

	static func geometry(c: LevelContext) -> void:
		LevelHazards.geometry(c)

	static func resolve(c: LevelContext) -> Array:
		return LevelHazards.resolve(c)

	static func lint(c: LevelContext) -> void:
		Spy.ctx = c
		LevelHazards.lint(c)

	static func legal(c: LevelContext, key: String) -> PackedByteArray:
		return LevelHazards.legal(c, key)


func run(tt: Node) -> void:
	t = tt
	_types()
	_difficulty()
	_all_types()
	_setups_fail()
	_no_terrain()
	_seeds()
	_legal()
	_seesaw_ops()
	_lint_rules()
	_template()
	if t.content():
		_content()


# ---------------------------------------------------------------- documents

## A stadium loop on flat ground (world 1024 m, terrain at 0 unless `terrain` is false): the right
## straight x = +R from z = -300 to +300 (points every 100 m, driven toward +z), the top arc, the left
## straight back (x = -R, z = +300 .. -300), the bottom arc. Segment k runs from point k to k + 1:
## 0..5 the right straight (lap 0..600 m), 6..11 the top arc, 12..17 the left straight, 18..23 the
## bottom arc. mods: point index -> keys merged into it.
static func stadium(doc: LevelDoc, mods := {}) -> Array:
	var pos := []
	for k in 7:
		pos.append(Vector3(R, 0.0, -300.0 + 100.0 * k))
	for k in 5:
		var a := PI * (k + 1) / 6.0
		pos.append(Vector3(R * cos(a), 0.0, 300.0 + R * sin(a)))
	for k in 7:
		pos.append(Vector3(-R, 0.0, 300.0 - 100.0 * k))
	for k in 5:
		var a := PI + PI * (k + 1) / 6.0
		pos.append(Vector3(R * cos(a), 0.0, -300.0 + R * sin(a)))
	var pts := []
	for k in pos.size():
		var p: Vector3 = pos[k]
		var d := {"uid": doc.new_uid(), "pos": [p.x, p.y, p.z], "width": 14.0, "style": "asphalt"}
		if mods.has(k):
			d.merge(mods[k], true)
		pts.append(d)
	doc.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	return pts


static func a(pts: Array, seg: int, tt: float) -> Dictionary:
	return {"p": int(pts[seg].uid), "t": tt}


static func hz(doc: LevelDoc, type: String, more: Dictionary) -> Dictionary:
	var h := {"uid": doc.new_uid(), "type": type, "at": null, "side": 0, "zone": null, "feel": "normal", "pts": [], "p": {}}
	h.merge(more, true)
	return h


## Doc A: all 19 types (with the ceiling turret and the arc zone) on good spots.
func doc_all() -> LevelDoc:
	var doc := LevelDoc.blank("Hazards", 1024.0, 513)
	var pts := stadium(doc, {2: {"seesaw": true}, 14: {"style": "tunnel"}})
	doc.data.hazards = [
		hz(doc, "turret", {"at": a(pts, 0, 0.1), "side": 1, "setback": 1.6, "mount": "floor"}),
		hz(doc, "turret", {"at": a(pts, 1, 0.5), "side": 1, "setback": 1.6, "mount": "floor"}),
		hz(doc, "apache", {"zone": [a(pts, 1, 0.2), a(pts, 3, 0.2)]}),
		hz(doc, "seesaw", {"at": a(pts, 2, 0.5)}),
		hz(doc, "tripmine", {"at": a(pts, 3, 0.5), "side": -1}),
		hz(doc, "tentacle", {"at": a(pts, 4, 0.5), "side": 1}),
		hz(doc, "field_gate", {"at": a(pts, 5, 0.5)}),
		hz(doc, "houndeyes", {"at": a(pts, 7, 0.5), "side": -1, "setback": 2.5}),
		hz(doc, "strider", {"at": a(pts, 8, 0.5), "side": 1, "setback": 20.0}),
		hz(doc, "air_strafe", {"zone": [a(pts, 7, 0.1), a(pts, 11, 0.6)]}),
		hz(doc, "controller", {"zone": [a(pts, 9, 0.0), a(pts, 10, 0.9)], "side": 1}),
		hz(doc, "train", {"at": a(pts, 12, 0.5)}),
		hz(doc, "column", {"at": a(pts, 13, 0.5)}),
		hz(doc, "strike_zone", {"zone": [a(pts, 13, 0.2), a(pts, 13, 0.8)], "style": "mortar"}),
		hz(doc, "turret", {"at": a(pts, 14, 0.5), "mount": "ceiling", "lat": 0.0}),
		hz(doc, "minefield", {"at": a(pts, 15, 0.5)}),
		hz(doc, "bullsquid", {"at": a(pts, 16, 0.5), "side": -1, "setback": 7.0}),
		hz(doc, "vortigaunt", {"at": a(pts, 17, 0.5), "side": 1, "setback": 1.6}),
		hz(doc, "strike_zone", {"zone": [a(pts, 17, 0.2), a(pts, 17, 0.8)], "style": "arc", "pts": [[-180.0, 5.0, -250.0]]}),
		hz(doc, "crane", {"at": a(pts, 19, 0.5), "side": 1, "setback": 10.0}),
		hz(doc, "antlion_guard", {"zone": [a(pts, 20, 0.0), a(pts, 21, 0.5)], "side": -1, "setback": 4.0}),
		hz(doc, "antlion", {"zone": [a(pts, 21, 0.5), a(pts, 23, 0.0)], "side": 0,
			"pts": [{"at": a(pts, 22, 0.5), "side": 1, "setback": 6.0}]}),
	]
	return doc


func _compile(doc: LevelDoc, flags := false) -> LevelBuild:
	return LevelCompiler.compile(doc, {"id": "c_test", "registries": REG, "flags": flags, "chunks": false,
		"hooks": {"hazards": Spy}})


func _codes(b: LevelBuild, code: String) -> Array:
	var out := []
	for it in b.report.items:
		if str(it.code) == code:
			out.append(it)
	return out


func _by_type(b: LevelBuild, type: String) -> Array:
	var out := []
	for e in b.data.get("hazards", []):
		if str(e.type) == type:
			out.append(e)
	return out


static func v3(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


# ---------------------------------------------------------------- the table

func _types() -> void:
	var names := PackedStringArray(LevelHazards.TYPES.keys())
	names.sort()
	var want := PackedStringArray(LevelDoc.HAZARD_TYPES)
	want.sort()
	t.check(names == want, "TYPES has the 19 types of LevelDoc.HAZARD_TYPES")
	var heavy := []
	for ty in LevelHazards.TYPES:
		var td: Dictionary = LevelHazards.TYPES[ty]
		for k in ["label", "group", "desc", "heavy", "setup", "placement", "params", "inputs", "blocking", "mounts", "styles"]:
			if not td.has(k):
				t.fail("%s has no %s" % [ty, k])
		if bool(td.heavy):
			heavy.append(ty)
		t.check(bool(td.blocking) == (ty in LevelHazards.BLOCKING), "%s blocking as hazards.py" % ty)
		var st := str(td.setup)
		t.check(st == "" or st in LevelHazards.SETUP_TYPES, "%s setup is a SETUP_TYPES key" % ty)
		var keys := _defaults(ty)
		t.check(not keys.is_empty(), "%s: the class script gives defaults()" % ty)
		for row in LevelHazards.params_of({"type": ty}) + LevelHazards.params_of({"type": ty, "mount": "ceiling", "style": "arc"}):
			t.check(str(row[0]) in keys, "%s param %s is a defaults() key" % [ty, row[0]])
			t.check(str(row[6]) in ["T", "P", ""] and (row as Array).size() == 7, "%s param %s has a feel" % [ty, row[0]])
		for k in LevelHazards.p_keys(ty):
			t.check(k in keys, "%s p key %s is a defaults() key" % [ty, k])
		for row in td.inputs:
			t.check(not (str(row[0]) in LevelHazards.RESOLVED.get(ty, [])), "%s input %s is never passed on" % [ty, row[0]])
		if ty != "strike_zone":
			t.check(LevelHazards.marker_model(ty) != "", "%s has a marker model" % ty)
	heavy.sort()
	var hv := LevelDoc.HEAVY.duplicate()
	hv.sort()
	t.check(heavy == hv, "the heavy types are LevelDoc.HEAVY")
	t.check(LevelHazards.marker_model_for({"type": "turret", "mount": "ceiling"}) == "hl1/turret", "a ceiling turret's marker")
	t.check(LevelHazards.setup_of({"type": "turret", "mount": "ceiling"}) == "turret_ceiling"
		and LevelHazards.setup_of({"type": "seesaw"}) == "seesaw" and LevelHazards.setup_of({"type": "apache"}) == "",
		"setup_of")


## The keys of a type's class defaults(), the script instanced without a tree.
func _defaults(type: String) -> PackedStringArray:
	var cls := HazardDirector.script_for(type)
	if cls == null:
		return PackedStringArray()
	var h = cls.new()
	var d: Dictionary = h.defaults()
	h.free()
	return PackedStringArray(d.keys())


func _difficulty() -> void:
	for ty in LevelHazards.TYPES:
		var nrm := LevelHazards.difficulty_p(ty, "normal")
		var easy := LevelHazards.difficulty_p(ty, "easy")
		var brutal := LevelHazards.difficulty_p(ty, "brutal")
		t.check(LevelHazards.difficulty_p(ty, "custom") == nrm, "%s custom = normal" % ty)
		var moved := 0
		var feels := 0
		for row in LevelHazards.params_of({"type": ty}) + LevelHazards.params_of({"type": ty, "style": "arc"}):
			var k: String = row[0]
			if not nrm.has(k):
				continue
			var same: bool = absf(_first(nrm[k]) - _first(row[5])) < 1e-6 if (row[5] is float or row[5] is int or row[5] is Array) 				and not (row[2] is Array) and k != "pattern" else var_to_str(nrm[k]) == var_to_str(row[5])
			t.check(same, "%s %s normal = the default" % [ty, k])
			var f := str(row[6])
			if f == "":
				t.check(var_to_str(easy[k]) == var_to_str(nrm[k]) and var_to_str(brutal[k]) == var_to_str(nrm[k]), "%s %s not scaled" % [ty, k])
				continue
			feels += 1
			var lo := _first(easy[k]) if f == "T" else _first(brutal[k])
			var hi := _first(brutal[k]) if f == "T" else _first(easy[k])
			# T: easy longer; P: brutal stronger
			if f == "T":
				t.check(_first(easy[k]) >= _first(nrm[k]) and _first(nrm[k]) >= _first(brutal[k]), "%s %s (T) easy >= normal >= brutal" % [ty, k])
			else:
				t.check(_first(easy[k]) <= _first(nrm[k]) and _first(nrm[k]) <= _first(brutal[k]), "%s %s (P) easy <= normal <= brutal" % [ty, k])
			t.check(lo >= float(row[2]) - 1e-6 and hi <= float(row[3]) + 1e-6, "%s %s inside its row" % [ty, k])
			if _first(easy[k]) != _first(nrm[k]) or _first(brutal[k]) != _first(nrm[k]):
				moved += 1
		if feels > 0:
			t.check(moved > 0, "%s: DIFFICULTY moves at least one param" % ty)
	var tp := LevelHazards.difficulty_p("turret", "brutal")
	t.check(int(tp.shots) == 8 and is_equal_approx(float(tp.lock), 0.7) and is_equal_approx(float(tp.range), 50.0),
		"turret BRUTAL: shots 8, lock 0.7, range 50 (%s)" % str(tp))
	var te := LevelHazards.difficulty_p("turret", "easy")
	t.check(int(te.shots) == 5 and is_equal_approx(float(te.cool), 7.0) and is_equal_approx(float(te.range), 30.0),
		"turret EASY: shots 5, cool 6.75 -> 7, range 30 (%s)" % str(te))


func _first(v: Variant) -> float:
	if v is Array:
		return float(v[0]) + float(v[1]) * 0.001
	return float(v)


# ---------------------------------------------------------------- every type

func _all_types() -> void:
	var doc := doc_all()
	var b := _compile(doc)
	var d := b.data
	var list: Array = d.get("hazards", [])
	var setup_err := _codes(b, "hazard_setup")
	t.check(setup_err.is_empty(), "doc A: no hazard_setup errors (%s)" % str(setup_err.map(func(it): return it.text)))
	t.check(list.size() == (doc.data.hazards as Array).size(), "doc A: every hazard kept (%d of %d)" % [list.size(), (doc.data.hazards as Array).size()])
	var seen := {}
	var ctx := LevelContext.new()
	ctx.doc = doc
	var L := b.roads[0].length
	for k in list.size():
		var e: Dictionary = list[k]
		var ty := str(e.type)
		seen[ty] = true
		t.check(int(e.id) == k, "%s id = list order" % ty)
		t.check(int(e.seed) == ctx.seed_of(int(doc.data.hazards[k].uid)), "%s seed = seed_of(uid)" % ty)
		t.check(float(e.s) >= 0.0 and float(e.s) < L, "%s s on the lap" % ty)
		t.check(e.span is Array and (e.span as Array).size() == 2 and float(e.span[1]) >= float(e.span[0]), "%s span" % ty)
		t.check(e.pos is Array and (e.pos as Array).size() == 3, "%s pos" % ty)
		var js := JSON.stringify(e)
		t.check(not js.containsn("nan") and not js.containsn("inf"), "%s: finite numbers only" % ty)
		var keys := _defaults(ty)
		for pk in e.p:
			t.check(str(pk) in keys or str(pk) in LevelHazards.BASE_KEYS, "%s p.%s is a defaults() key" % [ty, pk])
	for ty in LevelHazards.TYPES:
		t.check(seen.has(ty), "doc A has a %s entry" % ty)
	# type details
	var tur := _by_type(b, "turret")
	t.check(tur.size() == 3 and str(tur[2].p.mount) == "ceiling" and str(tur[2].p.model) == "hl1/turret"
		and is_equal_approx(float(tur[2].p.scale), 1.5), "the ceiling turret: mount, model hl1/turret, scale 1.5")
	var m: LevelRoad = b.roads[0]
	var ci := m.idx(float(tur[2].s))
	t.check(absf(float(tur[2].pos[1]) - (m.pos[ci].y + m.height[ci] - 0.25)) < 0.05, "the ceiling turret hangs 0.25 m under the ceiling")
	t.check(str(tur[1].p.mount) == "floor" and int(tur[1].p.shots) == 6, "the floor turret: mount floor, default shots")
	var arc := _by_type(b, "strike_zone")
	t.check(arc.size() == 2 and str(arc[1].p.style) == "arc" and v3(arc[1].p.core).is_equal_approx(Vector3(-180, 5, -250))
		and not arc[0].p.has("core_r"), "the arc zone's core; the mortar has no core_r")
	var fg: Dictionary = _by_type(b, "field_gate")[0]
	t.check((fg.p.posts as Array).size() == 4 and (fg.p.pattern as Array).size() == 4, "field gate: 3 lanes, 4 posts, the class pattern")
	var mf: Dictionary = _by_type(b, "minefield")[0]
	t.check((mf.p.mines as Array).size() == 8 and (mf.p.mines[0] as Array).size() == 5, "minefield: 8 seeded mines [x, y, z, s, lat]")
	var hd: Dictionary = _by_type(b, "houndeyes")[0]
	t.check((hd.p.members as Array).size() == 3 and (hd.p.walks as Array).size() == 3 and (hd.p.spots as Array).size() == 3
		and int(hd.p.side) == -1, "houndeyes: a pack of 3 with walks and spots")
	var ctl: Dictionary = _by_type(b, "controller")[0]
	t.check((ctl.p.path as Array).size() >= 24, "controller: an oval flight of >= 24 points")
	var sd: Dictionary = _by_type(b, "seesaw")[0]
	t.check(absf(float(sd.p.from) - 200.0) < 2.0 and absf(float(sd.p.to) - 300.0) < 2.0
		and absf(float(sd.p.apron) - (float(sd.p.to) - float(sd.p.from) - 49.1) * 0.5) < 0.05, "see-saw: its stretch 200-300 m, flaps (%s)" % str(sd.p))
	var tr: Dictionary = _by_type(b, "train")[0]
	t.check(absf(v3(tr.p.a).distance_to(v3(tr.p.b)) - 260.0) < 0.5 and (tr.p.profile as Array).size() == 66
		and (tr.p.lamps as Array).size() == 2, "train: a 260 m line, a profile every 4 m, 2 lamps")
	var signals := 0
	for p in d.get("props", []):
		if str(p.model) == LevelHazards.SIGNAL_MODEL:
			signals += 1
	t.check(signals == 2, "train: two signal props in data.props")
	var col: Dictionary = _by_type(b, "column")[0]
	var deck_a := v3(col.p.deck[0])
	var deck_b := v3(col.p.deck[1])
	var coli := m.idx(float(col.s))
	t.check(absf(deck_a.y - (m.pos[coli].y + 6.0)) < 0.05 and absf(deck_a.distance_to(deck_b) - (14.0 + 2.0 * (4.0 + 3.0))) < 0.3,
		"column: the deck at road y + 6 m, across the road + 2 x (verge + 3 m) (%.2f m)" % deck_a.distance_to(deck_b))
	var tm: Dictionary = _by_type(b, "tripmine")[0]
	var ti := m.idx(float(tm.s))
	t.check(m.lateral(v3(tm.p.a), ti) < -7.0 and m.lateral(v3(tm.p.b), ti) > 0.0, "tripmine: from the left wall across the centre")
	var cr: Dictionary = _by_type(b, "crane")[0]
	t.check(cr.p.has("phase") and not cr.p.has("legs"), "crane: phase, no legs in p")
	# the setups' geometry
	var names := PackedStringArray()
	for mm in b.meshes.meshes():
		names.append(str(mm.name))
	var hn := func(uid: int, kind: String) -> bool:
		for nm in names:
			if nm.begins_with("%s_h%d_" % [kind, uid]):
				return true
		return false
	var uid_of := func(type: String) -> int:
		for h in doc.data.hazards:
			if str(h.type) == type:
				return int(h.uid)
		return -1
	t.check(hn.call(uid_of.call("train"), "decal") and hn.call(uid_of.call("train"), "walls"), "train: rails decal and portal walls (h<uid>)")
	t.check(hn.call(uid_of.call("column"), "side") and hn.call(uid_of.call("column"), "walls"), "column: the footbridge's deck, railings and pillars")
	t.check(hn.call(uid_of.call("tripmine"), "walls"), "tripmine: a wall stub (no barrier there)")
	var cut := 0
	for i in m.n:
		cut += m.cut[i]
	var ti2 := m.idx(float(tr.s))
	t.check(cut > 0 and m.cut[ti2] == 1 and m.cut[m.idx(float(tr.s) + 40.0)] == 0, "train: the barriers cut round the line only")
	var si := m.idx(250.0)
	t.check(m.skip[si] == 1 and absf(m.dip[si] - 14.0) < 0.01, "see-saw stretch: skip and a 14 m ravine dip")
	t.check(b.terrain.height_at(m.pos[si].x, m.pos[si].z) < m.pos[si].y - 10.0, "the carve digs the ravine")
	# the tentacle's pit
	var tn: Dictionary = _by_type(b, "tentacle")[0]
	var tp := v3(tn.pos)
	var tni := m.idx(float(tn.s))
	t.check(b.terrain.height_at(tp.x, tp.z) < m.pos[tni].y - 20.0 and b.terrain.natural_at(tp.x, tp.z) == 0.0,
		"tentacle: the carve lowers its pit (%.1f m)" % b.terrain.height_at(tp.x, tp.z))
	t.check(absf(tp.y - (m.pos[tni].y - 24.0)) < 0.01, "tentacle: its base 24 m under the road")
	# two compiles are identical
	var b2 := _compile(doc)
	t.check(JSON.stringify(b2.data.hazards) == JSON.stringify(list) and b2.digest() == b.digest(), "two compiles: identical hazards and digest")
	var h1 := {}
	for mm in b.meshes.meshes():
		if str(mm.name).contains("_h"):
			h1[mm.name] = mm.hash
	var h2 := {}
	for mm in b2.meshes.meshes():
		if str(mm.name).contains("_h"):
			h2[mm.name] = mm.hash
	t.check(h1 == h2 and not h1.is_empty(), "two compiles: the same setup meshes")
	# crowds keep out of the hazards' corridors
	t.check(Spy.ctx != null and Spy.ctx.reserved.size() >= 10, "the hazards reserve their corridors (%d)" % (Spy.ctx.reserved.size() if Spy.ctx else 0))


# ---------------------------------------------------------------- setups that fail

func _setups_fail() -> void:
	var doc := LevelDoc.blank("Bad", 1024.0, 513)
	var pts := stadium(doc, {2: {"gap": {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}}, 5: {"seesaw": true}, 14: {"style": "tunnel"}})
	doc.data.items = [{"uid": doc.new_uid(), "road": -1, "at": a(pts, 13, 0.5), "count": 0, "inset": 2.5}]
	doc.data.hazards = [
		hz(doc, "turret", {"at": a(pts, 1, 0.5), "mount": "ceiling"}),
		hz(doc, "tripmine", {"at": a(pts, 2, 0.5), "side": 1}),
		hz(doc, "vortigaunt", {"at": a(pts, 2, 0.95), "side": 1, "setback": 1.6}),
		hz(doc, "seesaw", {"at": a(pts, 3, 0.5)}),
		hz(doc, "field_gate", {"at": a(pts, 13, 0.5)}),
		hz(doc, "train", {"at": a(pts, 14, 0.5)}),
		hz(doc, "tentacle", {"at": a(pts, 14, 0.3), "side": 1}),
		hz(doc, "column", {"at": a(pts, 14, 0.7)}),
		hz(doc, "antlion", {"zone": [a(pts, 14, 0.0), a(pts, 15, 0.0)], "side": 1}),
	]
	var b := _compile(doc)
	var errs := _codes(b, "hazard_setup")
	var types := []
	for it in errs:
		types.append(str(it.get("type", "")))
	for ty in ["turret", "tripmine", "seesaw", "train", "tentacle", "column", "antlion", "seesaw_stretch"]:
		t.check(ty in types, "hazard_setup for the %s (%s)" % [ty, str(types)])
	var kept := []
	for e in b.data.hazards:
		kept.append(str(e.type))
	t.check(kept == ["vortigaunt", "field_gate"], "only the hazards with their setup are kept (%s)" % str(kept))
	var e0: Dictionary = _codes(b, "hazard_setup")[0] if not errs.is_empty() else {"text": "", "fix": ""}
	t.check(str(e0.text) == "The ceiling turret needs a tunnel: move it to a green spot or delete it." and str(e0.fix) == "hazard_setup",
		"the hazard_setup text and fix (%s)" % str(e0.text))
	for it in errs:
		if str(it.type) == "seesaw_stretch":
			t.check(str(it.text).contains("see-saw stretch needs its see-saw"), "an empty see-saw stretch asks for its see-saw")
	t.check(b.report.raceable() == false, "setup errors block hosting")
	var names := PackedStringArray()
	for mm in b.meshes.meshes():
		names.append(str(mm.name))
	var any_h := false
	for nm in names:
		for h in doc.data.hazards:
			if str(h.type) in ["train", "column", "tripmine"] and nm.contains("_h%d_" % int(h.uid)):
				any_h = true
	t.check(not any_h, "no setup geometry for hazards left out")
	var cut := 0
	for i in b.roads[0].n:
		cut += b.roads[0].cut[i]
	t.check(cut == 0, "no barrier cut for a train left out")
	var lint := _lint_texts(b)
	var gi := b.roads[0].idx(250.0)
	t.check(b.roads[0].gap[gi] == 1 and absf(b.roads[0].dip[gi] - 8.0) < 0.01, "a jump gap: its 8 m dip")
	t.check(_has(lint, "Vortigaunt", "on a jump"), "lint: a hazard on a jump (%s)" % str(lint))
	t.check(_has(lint, "Force field gate", "on a crate row"), "lint: a blocking hazard on a crate row")


func _lint_texts(b: LevelBuild) -> Array:
	var out := []
	for it in _codes(b, "hazard_lint"):
		out.append(str(it.text))
	return out


func _has(lines: Array, who: String, what: String) -> bool:
	for l in lines:
		if str(l).begins_with(who) and str(l).contains(what):
			return true
	return false


# ---------------------------------------------------------------- no terrain

func _no_terrain() -> void:
	var doc := LevelDoc.blank("Void", 1024.0, 0)
	var pts := stadium(doc)
	doc.data.hazards = [
		hz(doc, "bullsquid", {"at": a(pts, 1, 0.5), "side": 1, "setback": 7.0}),
		hz(doc, "houndeyes", {"at": a(pts, 3, 0.5), "side": -1, "setback": 5.0}),
		hz(doc, "tentacle", {"at": a(pts, 4, 0.5), "side": 1}),
		hz(doc, "antlion", {"zone": [a(pts, 13, 0.0), a(pts, 14, 0.5)], "side": 1}),
		hz(doc, "strider", {"at": a(pts, 16, 0.5), "side": 1, "setback": 20.0}),
	]
	var b := _compile(doc)
	t.check(b.data.hazards.size() == 5, "no terrain: every hazard compiles")
	t.check(Spy.ctx != null and Spy.ctx.pits.is_empty(), "no terrain: no tentacle pit")
	t.check(not JSON.stringify(b.data.hazards).containsn("nan"), "no terrain: no NAN in the entries")
	var lint := _lint_texts(b)
	t.check(_has(lint, "Bullsquid", "no floor"), "lint: a creature with no floor (%s)" % str(lint))
	t.check(_has(lint, "Houndeyes", "no floor"), "lint: a houndeye with no floor")
	t.check(_has(lint, "Antlions", "open ground beside the road at only 0%"), "lint: an antlion zone with no ground")


# ---------------------------------------------------------------- seeds

func _seeds() -> void:
	var doc := doc_all()
	var b := _compile(doc)
	var seeds := _seed_map(b, doc)
	var rep := LevelReport.new()
	var back := LevelIO.unpack(LevelIO.pack(doc), rep)
	t.check(back != null, "doc A packs and unpacks")
	if back == null:
		return
	var b2 := _compile(back)
	t.check(_seed_map(b2, back) == seeds, "seeds stay across a save / load")
	var same_pos: bool = b2.data.hazards.size() == b.data.hazards.size()
	if same_pos:
		for k in b.data.hazards.size():
			if v3(b.data.hazards[k].pos).distance_to(v3(b2.data.hazards[k].pos)) > 0.02:
				same_pos = false
	t.check(same_pos, "the hazards land on the same spots after a save / load")
	back.apply([LevelDoc.op_set(["name"], "Renamed Hazards")])
	t.check(_seed_map(_compile(back), back) == seeds, "seeds stay across a rename")
	var rev: Array = (back.data.hazards as Array).duplicate(true)
	rev.reverse()
	back.apply([LevelDoc.op_set(["hazards"], rev)])
	t.check(_seed_map(_compile(back), back) == seeds, "seeds stay across a reorder (ids follow the list)")
	var other := doc_all()
	t.check(_seed_map(_compile(other), other) != seeds, "another track (guid) has other seeds")


## uid -> seed of the kept entries (entries in doc order).
func _seed_map(b: LevelBuild, doc: LevelDoc) -> Dictionary:
	var out := {}
	var k := 0
	for h in doc.data.hazards:
		if k < b.data.hazards.size():
			out[int(h.uid)] = int(b.data.hazards[k].seed)
		k += 1
	return out


# ---------------------------------------------------------------- legal spots

func _legal() -> void:
	var doc := LevelDoc.blank("Legal", 1024.0, 513)
	stadium(doc, {2: {"gap": {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}}, 14: {"style": "tunnel"}})
	var b := _compile(doc, true)
	for k in LevelHazards.SETUP_TYPES:
		t.check(b.flags.has("hz_" + k) and (b.flags["hz_" + k] as PackedByteArray).size() == (b.roads[0].n + 2) / 3,
			"flags hz_%s per exported sample" % k)
	var m: LevelRoad = b.roads[0]
	var at := func(key: String, s_m: float) -> int:
		return int((b.flags["hz_" + key] as PackedByteArray)[m.idx(s_m) / 3])
	t.check(at.call("turret_ceiling", 1321.0) == 1 and at.call("turret_ceiling", 150.0) == 0, "ceiling turret: legal in the tunnel only")
	t.check(at.call("tripmine", 250.0) == 0 and at.call("tripmine", 150.0) == 1, "tripmine: not on a jump")
	t.check(at.call("tentacle", 1321.0) == 0 and at.call("tentacle", 450.0) == 1, "tentacle: not in a tunnel")
	t.check(at.call("column", 1321.0) == 0 and at.call("column", 450.0) == 1, "column: not in a tunnel")
	t.check(at.call("train", 1321.0) == 0 and at.call("train", 450.0) == 1 and at.call("train", 250.0) == 0, "train: an open road, not a tunnel or a jump")
	t.check(at.call("seesaw", 450.0) == 1 and at.call("seesaw", 850.0) == 0 and at.call("seesaw", 250.0) == 0,
		"see-saw: a straight 100 m segment, not the arc or a jump")
	t.check(at.call("antlion", 450.0) == 1 and at.call("antlion", 1321.0) == 0, "antlion: open road with ground beside it")
	var no := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	t.check(not no.flags.has("hz_train"), "no flags unless asked")


# ---------------------------------------------------------------- see-saw ops

func _seesaw_ops() -> void:
	var doc := LevelDoc.blank("Seesaw", 1024.0, 513)
	var pts := stadium(doc)
	var uid := int(pts[3].uid)
	var ops := LevelHazards.seesaw_ops(doc, uid, true)
	t.check(ops.size() == 2, "see-saw on: the flag and the hazard (%d ops)" % ops.size())
	var inv := doc.apply(ops)
	var hz_n := (doc.data.hazards as Array).size()
	t.check(bool(doc.find(uid).item.get("seesaw", false)) and hz_n == 1 and str(doc.data.hazards[0].type) == "seesaw",
		"the segment is a see-saw stretch with its see-saw")
	t.check(LevelHazards.seesaw_ops(doc, uid, true).is_empty(), "on again: nothing to do")
	var b := _compile(doc)
	t.check(_by_type(b, "seesaw").size() == 1 and _codes(b, "hazard_setup").is_empty(), "the see-saw compiles on its stretch")
	doc.apply(inv)
	t.check(not bool(doc.find(uid).item.get("seesaw", false)) and (doc.data.hazards as Array).is_empty(), "one undo step takes both back")
	doc.apply(ops)
	var off := LevelHazards.seesaw_ops(doc, uid, false)
	doc.apply(off)
	t.check(not bool(doc.find(uid).item.get("seesaw", false)) and (doc.data.hazards as Array).is_empty(), "see-saw off: the flag and the hazard go")
	t.check(LevelHazards.seesaw_ops(doc, 999999, true).is_empty(), "an unknown point: no ops")


# ---------------------------------------------------------------- lint on crafted cases

func _lint_rules() -> void:
	var doc := doc_all()
	var b := _compile(doc)
	var lint := _lint_texts(b)
	if OS.has_environment("HZ_VERBOSE"):
		for l in lint:
			t.log(l)
		t.log("compile %.0f ms, with flags %.0f ms" % [float(b.stats.compile_ms), t.ms(func(): _compile(doc, true))])
	t.check(_has(lint, "Turret 10 m", "near the start line"), "lint: near the start line (%s)" % str(lint))
	var ctx := Spy.ctx
	if ctx == null:
		t.fail("the spy saw no context")
		return
	var entries: Array = ctx.data.hazards
	var info: Array = ctx.get_meta("hz_info")
	var find := func(type: String) -> int:
		for k in entries.size():
			if str(entries[k].type) == type:
				return k
		return -1
	var check := func(type: String, change: Callable, want: String) -> void:
		var k: int = find.call(type)
		if k < 0:
			t.fail("no %s to lint" % type)
			return
		var e: Dictionary = (entries[k] as Dictionary).duplicate(true)
		var inf: Dictionary = (info[k] as Dictionary).duplicate(true)
		change.call(e, inf)
		var msgs := LevelHazards._checks(ctx, e, inf)
		var hit := false
		for l in msgs:
			if str(l).contains(want):
				hit = true
		t.check(hit, "lint %s: \"%s\" (%s)" % [type, want, str(msgs)])
	var f_cover := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.cover = [5.0, 7.0]
	check.call("tentacle", f_cover, "passes clear of its slam")
	var f_feet := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.feet = [0.0, 2.0, -0.5]
	check.call("strider", f_feet, "uneven ground")
	var f_climb := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.profile = [[0.0, 0.0], [4.0, 0.0], [8.0, 1.0]]
	check.call("train", f_climb, "rails climb")
	var f_fly := func(e: Dictionary, _i: Dictionary) -> void:
		var path: Array = (e.p.path as Array).duplicate(true)
		path[0] = [R, 4.0, 0.0]
		e.p.path = path
	check.call("controller", f_fly, "from a road's edge")
	var f_short := func(e: Dictionary, _i: Dictionary) -> void:
		var a0 := v3(e.p.deck[0])
		var a1 := v3(e.p.deck[1])
		e.p.deck = [e.p.deck[0], [a0.x + (a1.x - a0.x) * 0.2, a0.y, a0.z + (a1.z - a0.z) * 0.2]]
	check.call("column", f_short, "too short")
	var f_low := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.deck = [[e.p.deck[0][0], 0.5, e.p.deck[0][2]], [e.p.deck[1][0], 0.5, e.p.deck[1][2]]]
	check.call("column", f_low, "stands on a road")
	var f_legs := func(_e: Dictionary, i: Dictionary) -> void:
		i["legs"] = [0.0, 3.0, 0.0, 0.0]
	check.call("crane", f_legs, "uneven ground under the tower")
	var f_far := func(e: Dictionary, _i: Dictionary) -> void:
		e.pos = [float(e.pos[0]) + (40.0 if float(e.pos[0]) > 0.0 else -40.0), e.pos[1], e.pos[2]]
	check.call("crane", f_far, "can not reach")
	var f_bent := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.a = [float(e.p.a[0]) + 1.0, e.p.a[1], e.p.a[2]]
	check.call("seesaw", f_bent, "not straight")
	var f_flaps := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.apron = 12.5
	check.call("seesaw", f_flaps, "flaps")
	var f_zone := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.zone = [e.p.zone[0], float(e.p.zone[0]) + 30.0]
	check.call("antlion_guard", f_zone, "zone only")
	var f_core := func(_e: Dictionary, i: Dictionary) -> void:
		i["core"] = Vector3(-300.0, 5.0, -250.0)
	check.call("strike_zone", f_core, "more than 40 m")
	var f_deep := func(e: Dictionary, _i: Dictionary) -> void:
		e.p.members = [[e.pos[0], -10.0, e.pos[2], 0.0]]
	check.call("houndeyes", f_deep, "no floor")
	var f_void := func(_e: Dictionary, i: Dictionary) -> void:
		i["floorless"] = true
	check.call("vortigaunt", f_void, "no floor")
	var f_post := func(e: Dictionary, _i: Dictionary) -> void:
		var mi := ctx.main.idx(float(e.s))
		var on_line := ctx.main.pos[mi] + ctx.main.right[mi] * LevelHazards._line_lat(ctx.main, mi)
		e.p.posts = [e.p.posts[0], [on_line.x, on_line.y, on_line.z], e.p.posts[e.p.posts.size() - 1]]
	check.call("field_gate", f_post, "from the racing line")
	var f_none := func(_e: Dictionary, _i: Dictionary) -> void:
		pass
	# items in a hazard's way: a pad and a crate row of our own
	var tr := ctx.main
	var bk: int = find.call("bullsquid")
	var bs := float(entries[bk].s)
	var mk: int = find.call("minefield")
	var mine := v3(entries[mk].p.mines[0])
	var pads_old = ctx.get_meta("pads", [])
	var rows_old = ctx.get_meta("rows", [])
	ctx.set_meta("pads", [{"uid": 1, "road": -1, "i": tr.idx(bs - 20.0), "s": bs - 20.0, "pos": tr.pos[tr.idx(bs - 20.0)]},
		{"uid": 2, "road": -1, "i": 0, "s": float(entries[mk].p.mines[0][3]), "pos": mine}])
	ctx.set_meta("rows", [{"uid": 3, "road": -1, "i": 0, "s": float(entries[mk].p.mines[1][3]), "crates": [v3(entries[mk].p.mines[1])]}])
	check.call("bullsquid", f_none, "acid on the boost pad")
	check.call("minefield", f_none, "on a boost pad")
	check.call("minefield", f_none, "on a crate row")
	ctx.set_meta("pads", pads_old)
	ctx.set_meta("rows", rows_old)
	# a branch's shared stretch and its road (lint() itself)
	var vk: int = find.call("vortigaunt")
	var ve: Dictionary = entries[vk]
	var vs := float(ve.s)
	var step := float(ctx.data.path.step)
	var saved_br = ctx.data.get("branches", [])
	ctx.data["branches"] = [{"id": "b900", "name": "SHORTCUT", "fork_s": vs - 30.0, "fork_nose_i": int((vs + 10.0) / step),
		"merge_nose_i": int((vs + 300.0) / step), "merge_s": vs + 340.0}]
	var vi := tr.idx(vs)
	var side_pts := []
	for k in 5:
		var q := tr.pos[vi] + tr.fwd[vi] * (-40.0 + 20.0 * k) + tr.flat_right[vi] * 14.0
		side_pts.append({"uid": 900 + k, "pos": [q.x, q.y, q.z], "width": 14.0, "style": "asphalt"})
	var br := LevelRoad.build(side_pts, ctx.styles, false, {"key": 900})
	ctx.roads.append(br)
	ctx.branches.append({"uid": 900, "name": "SHORTCUT", "ok": true})
	ctx.remove_meta("hz_hash")
	var rep := ctx.report
	ctx.report = LevelReport.new()
	LevelHazards.lint(ctx)
	var lines := []
	for it in ctx.report.items:
		lines.append(str(it.text))
	t.check(_has(lines, "Vortigaunt", "in the shared stretch of SHORTCUT"), "lint: in a branch's shared stretch (%s)" % str(lines))
	t.check(_has(lines, "Vortigaunt", "stands on the road of the branch SHORTCUT"), "lint: standing on a branch's road")
	ctx.report = rep
	ctx.roads.pop_back()
	ctx.branches.pop_back()
	ctx.data["branches"] = saved_br
	ctx.remove_meta("hz_hash")


# ---------------------------------------------------------------- the CITY 17 BLOCK template

func _template() -> void:
	var doc := LevelTemplates.make("city", "City")
	var b := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	var types := []
	for e in b.data.get("hazards", []):
		types.append(str(e.type))
	t.check(types == ["turret", "strike_zone"] and _codes(b, "hazard_setup").is_empty(),
		"the city template's turret and mortar zone compile (%s)" % str(types))


# ---------------------------------------------------------------- content: a c_ oval for hazard_test

## The template oval with hazards on it, saved to SHARE_DIR for
## `hazard_test.tscn -- rules c_<id> --tracks <dir>` and `-- determinism c_<id> --tracks <dir>`.
func _content() -> void:
	var doc := LevelTemplates.make("oval", "Hazard Oval")
	var pts: Array = doc.data.road.points
	var n := pts.size()
	var at := func(f: float, tt: float) -> Dictionary:
		return {"p": int(pts[int(f * n) % n].uid), "t": tt}
	doc.apply([LevelDoc.op_set(["hazards"], [
		hz(doc, "turret", {"at": at.call(0.25, 0.5), "side": 1, "setback": 1.6, "mount": "floor"}),
		hz(doc, "tripmine", {"at": at.call(0.4, 0.5), "side": -1}),
		hz(doc, "tentacle", {"at": at.call(0.55, 0.5), "side": 1}),
		hz(doc, "strike_zone", {"zone": [at.call(0.68, 0.0), at.call(0.75, 0.0)], "style": "mortar"}),
		hz(doc, "field_gate", {"at": at.call(0.85, 0.5)}),
	])])
	var b := LevelCompiler.compile(doc, {"registries": LevelCompiler.registries()})
	t.check(b.data.get("hazards", []).size() == 5, "content: the oval's 5 hazards compile (%s)" % str(_codes(b, "hazard_setup").map(func(it): return it.text)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARE_DIR))
	var path := SHARE_DIR + "/hazard_oval.hl2kt"
	t.check(LevelIO.save(doc, path) == OK, "content: the oval saved")
	var id := LevelIO.id_for(LevelIO.file_sha256(path))
	t.log("hazard_test track %s in %s" % [id, ProjectSettings.globalize_path(SHARE_DIR)])
	var rep := LevelReport.new()
	var back := LevelIO.load_file(path, rep)
	t.check(back != null and LevelCompiler.compile(back, {"registries": LevelCompiler.registries()}).data.hazards.size() == 5,
		"content: the saved oval loads and compiles")
