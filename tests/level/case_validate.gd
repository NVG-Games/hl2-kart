extends RefCounted
## P4: validation (spec 1.8, 3.9) without content: every code of 1.8 has its text (no format spec
## left once filled), its level and its FIX id; each rule the compiler checks fires on a crafted
## document (no_road, open_loop, compile, lap_short / lap_long, outside, too_tight, crossing, grid,
## start_jump, steep / steep_warn, under_water (sea and lake), embankment, pad_grid / pad_crate,
## item_jump, jump_boost, no_items, budget, over_cap, missing, prop_on_road, tunnel_lights and the
## compiler's own prop_static / screens / bake_n); the hooks' codes (branch_*, hazard_setup,
## hazard_lint, crowd) get their text and fix filled; blocks_drive only for no_road / open_loop /
## compile.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}
const CaseCompile := preload("res://tests/level/case_compile.gd")

## Every code of the 1.8 table, and the fix ids of the ones that have a FIX button there.
const CODES_18 := ["no_road", "open_loop", "lap_short", "lap_long", "outside", "too_tight", "crossing", "grid",
	"start_jump", "steep", "under_water", "branch_range", "branch_order", "branch_nose", "branch_kind",
	"branch_bank", "branch_radius", "branch_jump", "branch_cross", "branch_edge", "branch_tight", "branch_items",
	"hazard_setup", "over_cap", "pad_grid", "pad_crate", "item_jump", "jump_boost", "no_items", "steep_warn",
	"embankment", "hazard_lint", "crowd", "budget", "tunnel_lights", "missing", "prop_on_road", "bot_lap"]
const FIX_18 := {"open_loop": "close_loop", "too_tight": "narrow", "crossing": "bridge", "grid": "clear_grid",
	"start_jump": "remove_jump", "steep": "smooth", "under_water": "raise_water", "branch_range": "legal_spot",
	"branch_kind": "legal_spot", "branch_bank": "legal_spot", "branch_radius": "legal_spot", "branch_jump": "legal_spot",
	"branch_tight": "narrow", "hazard_setup": "hazard_setup", "no_items": "auto_items", "steep_warn": "smooth",
	"embankment": "bridge", "prop_on_road": "delete"}
const ARGS := {"m": 120, "w": 14, "km": 21, "what": "jump", "pct": 50, "name": "SHORTCUT", "needs": "a tunnel",
	"count": 3, "cap": 2, "why": "the road has no length", "speed": 40, "h": 12, "line": "a lint line", "left": 3,
	"budget": 2, "n": 10, "was": 12}

## Codes seen firing (each is checked once for its text, fix, level and the drive rule).
var fired := {}


func run(t: Node) -> void:
	_texts(t)
	_blocking(t)
	_road_rules(t)
	_grid_rules(t)
	_height_rules(t)
	_water_rules(t)
	_item_rules(t)
	_content_rules(t)
	_hook_codes(t)
	var left := []
	for code in LevelValidate.TEXTS:
		if not fired.has(code) and not code in ["bot_lap"]:
			left.append(code)
	t.check(left.is_empty(), "every code fired on a crafted doc (left: %s)" % str(left))


# ---------------------------------------------------------------- helpers

func _doc(size := 1024.0, res := 0) -> LevelDoc:
	return LevelDoc.blank("Validate", size, res)


func _compile(doc: LevelDoc, o := {}) -> LevelBuild:
	var opts := {"registries": REG, "chunks": false}
	for k in o:
		opts[k] = o[k]
	return LevelCompiler.compile(doc, opts)


func _no_spec(s: String) -> bool:
	return s != "" and not (s.contains("%d") or s.contains("%s") or s.contains("%.") or s.contains("%i") or s.contains("%f"))


## The build reports `code` with a complete text, its level and its fix id; blocks_drive is set
## exactly when a blocking code is in the report.
func _fires(t: Node, b: LevelBuild, code: String, what: String) -> Dictionary:
	var it := b.report.first(code)
	t.check(not it.is_empty(), "%s: %s fires (%s)" % [what, code, str(_codes(b))])
	if it.is_empty():
		return it
	fired[code] = true
	t.check(_no_spec(str(it.text)), "%s: the %s text is complete (%s)" % [what, code, it.text])
	t.check(it.level == LevelValidate.LEVELS[code], "%s: %s is a %s" % [what, code, LevelValidate.LEVELS[code]])
	if it.level != "info":
		t.check(it.fix == LevelValidate.FIXES[code], "%s: %s fix id %s" % [what, code, LevelValidate.FIXES[code]])
	var blocking := false
	for c in LevelReport.BLOCKING:
		blocking = blocking or b.report.has(c)
	t.check((b.report.blocks_drive() != "") == blocking, "%s: blocks_drive only for no_road / open_loop / compile" % what)
	return it


func _codes(b: LevelBuild) -> PackedStringArray:
	var out := PackedStringArray()
	for it in b.report.items:
		out.append(str(it.code))
	return out


func _oval(doc: LevelDoc, a := 180.0, b := 110.0, count := 20, y := 0.0, style := "asphalt", w := 14.0) -> Array:
	return CaseCompile.oval(doc, a, b, count, y, style, w)


# ---------------------------------------------------------------- texts

func _texts(t: Node) -> void:
	for code in CODES_18:
		t.check(LevelValidate.TEXTS.has(code) and LevelValidate.FIXES.has(code) and LevelValidate.LEVELS.has(code),
			"1.8 code %s has a text, a fix entry and a level" % code)
	for code in LevelValidate.TEXTS:
		var tpl: String = LevelValidate.TEXTS[code]
		var s := LevelValidate.text(code, ARGS)
		t.check(_no_spec(s), "text(%s) leaves no format spec (%s)" % [code, s])
		var specs := tpl.replace("%%", "").count("%")
		var keys: Array = LevelValidate.ARGS.get(code, [])
		t.check(specs == keys.size(), "%s: %d placeholders, %d arg keys" % [code, specs, keys.size()])
		t.check(s.count("%") == tpl.count("%%"), "%s: only literal percent signs left" % code)
		t.check(LevelValidate.FIXES.has(code) and LevelValidate.LEVELS.has(code), "%s: fix and level entries" % code)
	for code in FIX_18:
		t.check(LevelValidate.FIXES[code] == FIX_18[code], "%s: FIX %s" % [code, FIX_18[code]])
	for code in CODES_18:
		if not FIX_18.has(code):
			t.check(LevelValidate.FIXES[code] == "", "%s: no FIX" % code)
	t.check(LevelValidate.text("steep", {"pct": 52.4, "m": 300}) == "The road climbs 52 % 300 m after the start: 45 % is the most a kart can drive.",
		"steep's text with its numbers")
	t.check(LevelValidate.text("nope", {}) == "", "an unknown code has no text")
	t.check(LevelValidate.text("over_cap", {}).begins_with("Too many : 0 of 0"), "missing args fill as empty / 0")
	var p := LevelValidate.plain(LevelValidate.TEXTS.no_road)
	t.check(not p.contains("{") and p.contains("press R"), "plain() writes the key tokens as words (%s)" % p)
	t.check(LevelValidate.blocks("no_road") and LevelValidate.blocks("open_loop") and LevelValidate.blocks("compile")
		and not LevelValidate.blocks("crossing"), "blocks()")


# ---------------------------------------------------------------- what cannot build

func _blocking(t: Node) -> void:
	_fires(t, _compile(_doc()), "no_road", "an empty doc")
	var d := _doc()
	_oval(d)
	d.data.road.closed = false
	_fires(t, _compile(d), "open_loop", "an open road")
	var c := _doc()
	var pts := []
	for k in 3:
		pts.append({"uid": c.new_uid(), "pos": [5.0, 0.0, 5.0], "width": 14.0, "style": "asphalt"})
	c.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var bc := _compile(c)
	_fires(t, bc, "compile", "three points on one spot")
	t.check(bc.report.blocks_drive().contains("could not be built"), "the compile failure is the drive blocker")
	# errors that do not stop a test drive
	var x := _doc()
	CaseCompile.figure8(x, 0.0)
	var bx := _compile(x)
	t.check(bx.report.has("crossing") and not bx.report.raceable() and bx.report.blocks_drive() == "",
		"a crossing makes the track unraceable but drivable")


# ---------------------------------------------------------------- the road

func _road_rules(t: Node) -> void:
	var s := _doc()
	_oval(s, 25.0, 15.0, 12)
	_fires(t, _compile(s), "lap_short", "a 130 m lap")
	var l := _doc()
	l.data.world.size = 8192.0
	var pts := []
	for k in 64:
		var a := TAU * k / 64
		pts.append({"uid": l.new_uid(), "pos": [3250.0 * cos(a), 0.0, 3250.0 * sin(a)], "width": 14.0, "style": "asphalt"})
	l.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var bl := _compile(l)
	var it := _fires(t, bl, "lap_long", "a 20 km lap")
	t.check(not it.is_empty() and str(it.text).contains("20 km"), "the lap's km in the text (%s)" % it.get("text", ""))
	t.check(not bl.report.has("budget") or bl.report.first("budget").what != "the lap length (m)", "no lap budget warning past the cap")
	var o := _doc(512.0)
	_oval(o, 240.0, 100.0)
	_fires(t, _compile(o), "outside", "a road within 40 m of the edge")
	# a hairpin of about 10 m radius on a 14 m road
	var h := _doc()
	var hp := []
	for p in [[-100, -10], [-50, -10], [0, -10], [50, -10], [100, -10], [110, 0], [100, 10], [50, 10], [0, 10], [-50, 10], [-100, 10], [-160, 0]]:
		hp.append({"uid": h.new_uid(), "pos": [float(p[0]), 0.0, float(p[1])], "width": 14.0, "style": "asphalt"})
	h.data.road = {"closed": true, "start": {"p": hp[1].uid, "t": 0.0}, "points": hp}
	var bh := _compile(h)
	var tt := _fires(t, bh, "too_tight", "a 10 m hairpin")
	t.check(not tt.is_empty() and absf(tt.pos.x - 108.0) < 15.0 and int(tt.uid) > 0, "too_tight at the hairpin, with its point")
	var x := _doc()
	CaseCompile.figure8(x, 0.0)
	var cr := _fires(t, _compile(x), "crossing", "a flat figure eight")
	t.check(not cr.is_empty() and cr.has("road_b") and cr.has("s_b"), "a crossing names the other stretch")
	var y := _doc()
	CaseCompile.figure8(y, 8.0)
	t.check(not _compile(y).report.has("crossing"), "8 m apart: no crossing")
	# a branch's junction ranges are not crossings (read from data.branches)
	var j := _doc()
	_oval(j, 200.0, 140.0)
	var bj := _compile(j, {"hooks": {"branches": OnTopBranch}})
	t.check(not bj.report.has("crossing") and bj.roads.size() == 2, "a branch on top of the main road inside its junction ranges: no crossing")
	var bk := _compile(j, {"hooks": {"branches": OnTopNoRanges}})
	t.check(bk.report.has("crossing"), "the same branch without junction ranges: a crossing")


## A branch lying on the main road's samples 30..60 (exported 10..20), its junction ranges
## covering that stretch.
class OnTopBranch:
	const RANGES := true

	static func build(ctx: LevelContext) -> void:
		var m := ctx.main
		var pts := []
		for k in 4:
			var i := 30 + k * 10
			pts.append({"uid": 800 + k, "pos": [m.pos[i].x, m.pos[i].y, m.pos[i].z], "width": 10.0, "style": "asphalt"})
		ctx.roads.append(LevelRoad.build(pts, ctx.styles, false, {"key": 44}))

	static func export_entries(_ctx: LevelContext) -> Array:
		return [{"id": "b44", "fork_i": 10, "fork_nose_i": 16, "merge_nose_i": 16, "merge_i": 20}]


class OnTopNoRanges:
	static func build(ctx: LevelContext) -> void:
		OnTopBranch.build(ctx)

	static func export_entries(_ctx: LevelContext) -> Array:
		return [{"id": "b44", "fork_i": 100, "fork_nose_i": 101, "merge_nose_i": 102, "merge_i": 103}]


# ---------------------------------------------------------------- the grid and jumps

func _grid_rules(t: Node) -> void:
	var g := _doc()
	var pts := _oval(g)
	pts[19]["bank"] = 10.0
	pts[18]["bank"] = 10.0
	var it := _fires(t, _compile(g), "grid", "an explicit bank behind the line")
	t.check(not it.is_empty() and str(it.text).contains("banked bend"), "the grid text names the bank")
	var a := _doc()
	var ap := _oval(a)
	t.check(not _compile(a).report.has("grid"), "AUTO bank behind the line: no grid error (flat zone)")
	ap[19]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	var bj := _compile(a)
	var gj := _fires(t, bj, "grid", "a jump behind the line")
	t.check(not gj.is_empty() and str(gj.text).contains("jump"), "the grid text names the jump")
	var s := _doc()
	var sp := _oval(s)
	sp[0]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	s.data.road.start = {"p": sp[0].uid, "t": 0.5}
	_fires(t, _compile(s), "start_jump", "the start on a jump")
	# a long flat jump nobody clears without a boost; an ordinary one is fine
	var jb := _doc()
	var jp := _oval(jb, 200.0, 140.0)
	jp[8]["gap"] = {"len": 40.0, "at": 0.5, "lift": 0.0, "ramp": 30.0}
	jp[12]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	var b := _compile(jb)
	var it2 := _fires(t, b, "jump_boost", "a 40 m jump without a kicker")
	t.check(b.report.all_of("jump_boost").size() == 1 and absf(it2.pos.x - 200.0 * cos(TAU * 8.5 / 20)) < 40.0,
		"only the long jump needs a boost")
	t.near(LevelValidate.launch_speed(12.0, 1.8, 16.0, 0.0), 22.0, 2.0, "launch_speed of an ordinary kicker")


# ---------------------------------------------------------------- heights

func _height_rules(t: Node) -> void:
	# a hill: point 5 30 m up, about 46 m from its neighbours (steep); 8, 22, 8 m (about 35 %: steep_warn)
	var hill := _doc()
	var hp := _oval(hill, 200.0, 150.0, 24)
	hp[5].pos[1] = 30.0
	var bs := _compile(hill)
	var it := _fires(t, bs, "steep", "a 30 m rise over 50 m")
	t.check(not it.is_empty() and float(it.pct) > 45.0, "steep's grade (%s)" % str(it.get("pct")))
	var soft := _doc()
	var sp := _oval(soft, 200.0, 150.0, 24)
	sp[4].pos[1] = 8.0
	sp[5].pos[1] = 22.0
	sp[6].pos[1] = 8.0
	var bw := _compile(soft)
	var w := _fires(t, bw, "steep_warn", "a 22 m rise over three points")
	t.check(not w.is_empty() and float(w.pct) > 30.0 and float(w.pct) <= 45.0 and not bw.report.has("steep"),
		"steep_warn between 30 and 45 %% (%s)" % str(w.get("pct")))
	# embankment: the road crosses a 25 m deep valley
	var v := _doc(512.0, 257)
	var res := v.res()
	for z in res:
		for x in res:
			v.heights[z * res + x] = -25.0 if absf(v.origin().x + x * v.cell()) < 50.0 else 0.0
	_oval(v)
	var be := _compile(v)
	var e := _fires(t, be, "embankment", "a road over a 25 m valley")
	t.check(not e.is_empty() and absf(float(e.h) - 25.0) < 1.5, "the embankment's height (%s)" % str(e.get("h")))
	var flat := _doc(512.0, 257)
	_oval(flat)
	t.check(not _compile(flat).report.has("embankment"), "on the ground: no embankment")


# ---------------------------------------------------------------- water

func _water_rules(t: Node) -> void:
	var s := _doc()
	_oval(s)
	s.data.water = {"sea": true, "level": 5.0}
	var it := _fires(t, _compile(s), "under_water", "a road under the sea")
	t.check(not it.is_empty() and int(it.road) == -1, "under_water names its road")
	s.data.water = {"sea": true, "level": -0.8}
	t.check(not _compile(s).report.has("under_water"), "0.8 m over the sea: dry")
	var l := _doc()
	_oval(l)
	l.data.lakes = [{"uid": l.new_uid(), "center": [180.0, 0.0], "size": [40.0, 60.0], "level": 3.0}]
	var bl := _compile(l)
	var li := bl.report.first("under_water")
	t.check(not li.is_empty() and absf(li.pos.x - 180.0) < 25.0, "a road through a lake: under_water at the lake")
	l.data.lakes[0].level = -2.0
	t.check(not _compile(l).report.has("under_water"), "a lake under the road: dry")


# ---------------------------------------------------------------- items

func _item_rules(t: Node) -> void:
	var n := _doc()
	_oval(n)
	_fires(t, _compile(n), "no_items", "no crates")
	var d := _doc()
	var pts := _oval(d)
	d.data.items = [{"uid": d.new_uid(), "road": -1, "at": {"p": pts[5].uid, "t": 0.5}, "count": 0, "inset": 2.5}]
	d.data.pads = [
		{"uid": d.new_uid(), "road": -1, "at": {"p": pts[0].uid, "t": 0.0}, "lat": null, "turn": 0.0},
		{"uid": d.new_uid(), "road": -1, "at": {"p": pts[5].uid, "t": 0.55}, "lat": 0.0, "turn": 0.0},
		{"uid": d.new_uid(), "road": -1, "at": {"p": pts[12].uid, "t": 0.5}, "lat": 0.0, "turn": 0.0},
	]
	pts[12]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	var b := _compile(d)
	t.check(not b.report.has("no_items"), "crates: no no_items")
	var pg := _fires(t, b, "pad_grid", "a pad on the start line")
	t.check(not pg.is_empty() and int(pg.uid) == int(d.data.pads[0].uid), "pad_grid names its pad")
	var pc := _fires(t, b, "pad_crate", "a pad just after a crate row")
	t.check(not pc.is_empty() and int(pc.uid) == int(d.data.pads[1].uid), "pad_crate names its pad")
	var ij := _fires(t, b, "item_jump", "a pad on a jump")
	t.check(not ij.is_empty() and int(ij.uid) == int(d.data.pads[2].uid), "item_jump names its pad")
	# a solid object on the road; a physics one and a deco one are fine
	var p := _doc()
	var pp := _oval(p)
	var at: Array = pp[3].pos
	p.data.props = [
		{"uid": p.new_uid(), "model": "props_c17/concrete_barrier001a", "pos": [float(at[0]), 0.5, float(at[2])], "yaw": 0.0,
			"pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": ""},
		{"uid": p.new_uid(), "model": "props_junk/x", "pos": [float(pp[6].pos[0]), 0.5, float(pp[6].pos[2])], "yaw": 0.0,
			"pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": true, "tag": ""},
		{"uid": p.new_uid(), "model": "props_junk/y", "pos": [float(pp[9].pos[0]), 0.5, float(pp[9].pos[2])], "yaw": 0.0,
			"pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": "deco"},
	]
	var bp := _compile(p)
	var po := _fires(t, bp, "prop_on_road", "a concrete barrier on the road")
	t.check(bp.report.all_of("prop_on_road").size() == 1 and int(po.uid) == int(p.data.props[0].uid), "only the solid prop")


# ---------------------------------------------------------------- counts and content

func _content_rules(t: Node) -> void:
	var l := _doc()
	_oval(l)
	var lights := []
	for k in 65:
		lights.append({"uid": l.new_uid(), "pos": [float(k), 5.0, 0.0], "color": [1, 1, 1], "range": 10.0, "energy": 1.0})
	l.data.lights = lights
	var bb := _compile(l)
	var it := _fires(t, bb, "budget", "65 lights")
	t.check(not it.is_empty() and str(it.text).contains("lights (65 of 64)"), "budget names what and how many (%s)" % it.get("text", ""))
	for k in 70:
		lights.append({"uid": l.new_uid(), "pos": [float(k), 6.0, 0.0], "color": [1, 1, 1], "range": 10.0, "energy": 1.0})
	var bo := _compile(l)
	var oc := _fires(t, bo, "over_cap", "135 lights")
	t.check(not oc.is_empty() and str(oc.text).contains("135 of 128") and (bo.data.lights as Array).size() == 128,
		"over_cap counts them; the build keeps 128")
	# crates past 256
	var c := _doc()
	var cp := _oval(c)
	var items := []
	for k in 40:
		items.append({"uid": c.new_uid(), "road": -1, "at": {"p": cp[k % 20].uid, "t": 0.1 + 0.4 * (k / 20)}, "count": 5, "inset": 2.5})
	var crates := []
	for k in 64:
		crates.append({"uid": c.new_uid(), "pos": [float(k), 1.2, 0.0]})
	c.data.items = items
	c.data.crates = crates
	var bc := _compile(c)
	var cc := _fires(t, bc, "over_cap", "264 crates")
	t.check(not cc.is_empty() and str(cc.text).contains("crates"), "over_cap for crates")
	# missing content: a model this install lacks (a registry that knows others)
	var m := _doc()
	_oval(m)
	m.data.props = [{"uid": m.new_uid(), "model": "x/unknown", "pos": [0.0, 0.0, 0.0], "yaw": 0.0, "pitch": 0.0, "roll": 0.0,
		"scale": 1.0, "physics": false, "tag": ""},
		{"uid": m.new_uid(), "model": "x/heavy", "pos": [5.0, 0.0, 0.0], "yaw": 0.0, "pitch": 0.0, "roll": 0.0,
		"scale": 1.0, "physics": true, "tag": ""}]
	m.data.race.music = ["no_such_song"]
	m.data.env.sky = "no_such_sky"
	var reg := {"models": {"x/heavy": {"mass": 75.0, "aabb_min": [0, 0, 0], "aabb_max": [1, 1, 1]}},
		"materials": {}, "skies": {"sky_day01_01": {}}, "music": {"hl2_song1": true}}
	var bm := _compile(m, {"registries": reg})
	var mi := _fires(t, bm, "missing", "an unknown model, song and sky")
	t.check(not mi.is_empty() and int(mi.count) == 3 and bm.report.missing.models == 1 and bm.report.missing.music == 1
		and bm.report.missing.skies == 1, "missing counts each (%s)" % str(bm.report.missing))
	t.check((bm.data.props as Array).size() == 1 and bm.data.sky == "sky_day01_01" and (bm.data.music as Array).is_empty(),
		"the unknown model, sky and song are left out here")
	var ps := _fires(t, bm, "prop_static", "a 75 kg physics prop")
	t.check(not ps.is_empty() and not bm.data.props[0].has("physics"), "too heavy to knock over: compiled static")
	# screens without the Combine arch
	var s := _doc()
	_oval(s)
	s.data.race.gantry = "blackmesa"
	s.data.screens = [{"uid": s.new_uid(), "pos": [0.0, 10.0, 0.0], "yaw": 0.0, "w": 8.0, "h": 4.5}]
	var bs := _compile(s)
	_fires(t, bs, "screens", "a screen with the Black Mesa arch")
	t.check((bs.data.screens as Array).is_empty(), "the screen is left out")
	# tunnel lights past 96 (LevelGeometry's warning, its code in the table)
	var tl := _doc()
	var tp := []
	for k in 20:
		var a := TAU * k / 20
		tp.append({"uid": tl.new_uid(), "pos": [300.0 * cos(a), 0.0, 300.0 * sin(a)], "width": 14.0, "style": "tunnel" if k < 11 else "asphalt"})
	tl.data.road = {"closed": true, "start": {"p": tp[15].uid, "t": 0.0}, "points": tp}
	var bt := _compile(tl)
	_fires(t, bt, "tunnel_lights", "a 1 km tunnel")
	t.check((bt.data.lights as Array).size() <= 96, "at most 96 tunnel lights")
	# the stored sample count is used when close, else a note
	var bk := _doc()
	_oval(bk)
	var own := _compile(bk).roads[0].n
	bk.data.bake = {"main_n": own + 3, "branch_n": {}, "rows": {}}
	var bh := _compile(bk)
	t.check(bh.roads[0].n == own + 3 and not bh.report.has("bake_n"), "bake.main_n within +-3 is used")
	bk.data.bake.main_n = own + 30
	var bn := _compile(bk)
	_fires(t, bn, "bake_n", "a stale bake.main_n")
	t.check(bn.roads[0].n == own, "a stale count is not used")


# ---------------------------------------------------------------- hook codes

## Reports each hook-owned code the way a hook may: through LevelValidate.issue, or with only the
## code and its args (the final pass fills the text and fix).
class CodeHooks:
	const BRANCH := ["branch_range", "branch_order", "branch_nose", "branch_kind", "branch_bank", "branch_radius",
		"branch_jump", "branch_cross", "branch_edge", "branch_tight", "branch_items"]

	static func build(ctx: LevelContext) -> void:
		for k in BRANCH.size():
			if k % 2 == 0:
				LevelValidate.issue(ctx.report, BRANCH[k], {"name": "SHORTCUT", "m": 90}, {"uid": 700 + k, "road": 700})
			else:
				ctx.report.error(BRANCH[k], "", {"uid": 700 + k, "road": 700, "name": "SHORTCUT", "m": 90})

	static func lint(ctx: LevelContext) -> void:
		ctx.report.warning("hazard_lint", "", {"uid": 3, "line": "the strider stands too close to the road"})
		ctx.report.warning("crowd", "", {"uid": 4, "left": 3, "count": 20, "why": "a wall stands there"})

	static func resolve(ctx: LevelContext) -> Array:
		ctx.report.error("hazard_setup", "", {"uid": 9, "what": "ceiling turret", "needs": "a tunnel"})
		return []


func _hook_codes(t: Node) -> void:
	var d := _doc()
	_oval(d)
	var b := _compile(d, {"hooks": {"branches": CodeHooks, "hazards": CodeHooks, "crowds": CodeHooks}})
	for code in CodeHooks.BRANCH:
		var it := _fires(t, b, code, "a hook's %s" % code)
		t.check(not it.is_empty() and str(it.text).contains("SHORTCUT"), "%s names its branch" % code)
	var hs := _fires(t, b, "hazard_setup", "a setup-less hazard")
	t.check(not hs.is_empty() and str(hs.text) == "The ceiling turret needs a tunnel: move it to a green spot or delete it.",
		"hazard_setup's text (%s)" % hs.get("text", ""))
	var hl := _fires(t, b, "hazard_lint", "a hazards.py lint line")
	t.check(not hl.is_empty() and str(hl.text) == "the strider stands too close to the road", "hazard_lint keeps the line")
	var cw := _fires(t, b, "crowd", "spectators left out")
	t.check(not cw.is_empty() and str(cw.text) == "3 of 20 spectators were left out: a wall stands there.", "crowd's text")
	t.check(b.report.blocks_drive() == "" and not b.report.raceable(), "hook errors never stop the drive")
