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
	_long_rules(t)
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
## exactly when a blocking code (or an error marked blocks: a lap too long to build) is in the report.
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
	for x in b.report.items:
		blocking = blocking or (x.level == "error" and bool(x.get("blocks", false)))
	t.check((b.report.blocks_drive() != "") == blocking, "%s: blocks_drive only for no_road / open_loop / compile / a lap too long to build" % what)
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
	t.check(LevelValidate.text("missing", {"count": 1}) == "1 object, material or song is not on this computer; it is left out here."
		and LevelValidate.text("missing", {"count": 2}).begins_with("2 objects, materials or songs are"), "missing: singular for 1, plural for 2")
	for code in LevelValidate.TEXTS_ONE:
		var one := LevelValidate.text(code, {"count": 1})
		t.check(one.begins_with("1 ") and _no_spec(one) and not one.contains(" are ") and one != LevelValidate.text(code, {"count": 3}),
			"%s: its singular (%s)" % [code, one])
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
	t.check(EditorSession.build_text(bc.report.blocks_drive()) == bc.report.blocks_drive(),
		"the editor shows the compile failure once (%s)" % EditorSession.build_text(bc.report.blocks_drive()))
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
	t.check(bl.roads.size() == 1 and bl.data.get("path") is Dictionary and bl.report.blocks_drive() == "",
		"a 20 km lap is still built and can be test-driven (%s)" % bl.report.blocks_drive())
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


## 6.9's bound (L1): 400 points between the far corners of a 4096 m world (over 2000 km) pass the
## gate and compile in well under a second, not raceable, with one blocking lap_long and nothing
## sampled, carved or meshed; a branch over 8 km is left out with branch_long; LevelRoad's own
## sampling never passes 3 x MAX_THIRDS samples.
func _long_rules(t: Node) -> void:
	var c := [Vector3(-2040, 0, -2040), Vector3(2040, 0, 2040), Vector3(-2040, 0, 2040), Vector3(2040, 0, -2040)]
	var d := _corners(_doc(4096.0, 1), c)
	var rep := LevelReport.new()
	var doc := LevelIO.unpack(LevelIO.pack(d), rep)
	t.check(doc != null and (doc.data.road.points as Array).size() == 400, "the far-corner document passes the gate (%s)" % rep.fatal())
	if doc == null:
		return
	var lb := LevelRoad.length_bounds(doc.data.road.points, true)
	var est := lb.x
	t.check(lb.y > 2000000.0 and est <= lb.y and est > 0.5 * lb.y and is_equal_approx(LevelRoad.poly_length(doc.data.road.points, true), lb.y),
		"length_bounds brackets the lap (about %.0f km, at most %.0f km)" % [est / 1000.0, lb.y / 1000.0])
	# the estimate is the true length within 1 %, the bound over it, on a lap that is built
	var w := _doc()
	CaseCompile.figure8(w, 8.0)
	var wb := LevelRoad.length_bounds(w.data.road.points, true)
	var wl := _compile(w).roads[0].length
	t.check(absf(wb.x - wl) < 0.01 * wl and wb.y >= wl, "on a figure eight: about %.1f, true %.1f, at most %.1f m" % [wb.x, wl, wb.y])
	var t0 := Time.get_ticks_usec()
	var b := LevelCompiler.compile(doc, {"registries": REG})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.check(ms < 1000.0, "a 2000+ km lap compiles in under 1 s (%.0f ms)" % ms)
	var it := _fires(t, b, "lap_long", "a 2000+ km lap")
	t.check(b.report.all_of("lap_long").size() == 1 and str(it.get("text", "")).contains("%d km" % roundi(est / 1000.0)),
		"one lap_long, naming the lap's km (%s)" % it.get("text", ""))
	t.check(not b.report.raceable() and b.report.blocks_drive() == str(it.get("text", "")) and not b.report.has("compile"),
		"not raceable, and the lap_long is what stops a test drive (%s)" % b.report.blocks_drive())
	t.check(EditorSession.build_text(b.report.blocks_drive()) == b.report.blocks_drive()
		and EditorSession.build_text("the road has no length") == "The track could not be built: the road has no length.",
		"the editor shows the lap_long as it is (%s)" % EditorSession.build_text(b.report.blocks_drive()))
	t.check(b.roads.is_empty() and not (b.data.get("path") is Dictionary) and b.meshes.triangles() == 0,
		"nothing sampled or meshed (%d roads, %d triangles)" % [b.roads.size(), b.meshes.triangles()])
	# on terrain: not carved
	var tr := _corners(_doc(1024.0, 257), [Vector3(-480, 0, -480), Vector3(480, 0, 480), Vector3(-480, 0, 480), Vector3(480, 0, -480)])
	var bt := LevelCompiler.compile(tr, {"registries": REG, "chunks": false})
	t.check(bt.report.has("lap_long") and bt.terrain != null and is_zero_approx(bt.terrain.height_at(0.0, 0.0))
		and is_zero_approx(bt.terrain.height_at(-480.0, -480.0)), "a 560 km lap on terrain: lap_long, the ground not carved")
	# an open road as long: refused the same way, still told to close the loop
	doc.data.road.closed = false
	var bo := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	t.check(bo.report.has("lap_long") and bo.report.has("open_loop") and bo.roads.is_empty(), "an open 2000+ km road: lap_long, open_loop, nothing built (%s)" % str(_codes(bo)))
	# LevelRoad's own backstop: an open road of about 50 km samples 3 x MAX_THIRDS + 1 times
	var zz := []
	for i in 10:
		var p: Vector3 = c[i % 4]
		zz.append({"uid": i + 1, "pos": [p.x, 0.0, p.z], "width": 14.0, "style": "asphalt"})
	var r := LevelRoad.build(zz, {}, false)
	t.check(r.length > 3.0 * LevelRoad.MAX_THIRDS * 2.0 and r.n == 3 * LevelRoad.MAX_THIRDS + 1,
		"a %.0f km road samples at most 3 x %d + 1 times (%d)" % [r.length / 1000.0, LevelRoad.MAX_THIRDS, r.n])
	# a branch over 8 km is left out unsampled, the lap still built
	var e := _doc(4096.0)
	var op := _oval(e, 600.0, 400.0, 24)
	e.data.branches = [{"uid": 900, "name": "LONG WAY", "kind": "road", "fork": {"p": int(op[2].uid), "t": 0.5},
		"merge": {"p": int(op[8].uid), "t": 0.5}, "side": 0, "merge_side": 0,
		"points": [{"uid": 901, "pos": [1900.0, 0.0, 1900.0], "width": 12.0, "style": "asphalt"},
			{"uid": 902, "pos": [-1900.0, 0.0, 1900.0], "width": 12.0, "style": "asphalt"},
			{"uid": 903, "pos": [-1900.0, 0.0, -1900.0], "width": 12.0, "style": "asphalt"}]}]
	e.data.next_uid = 1000
	var be := _compile(e)
	var bi := _fires(t, be, "branch_long", "a 9 km branch")
	t.check(not bi.is_empty() and str(bi.text).contains("LONG WAY") and str(bi.text).contains(" km long") and not str(bi.text).contains(" 0 km"),
		"branch_long names the branch and its km (%s)" % bi.get("text", ""))
	t.check(be.roads.size() == 1 and be.data.get("path") is Dictionary and be.report.blocks_drive() == "",
		"the lap is still built without the branch (%d roads)" % be.roads.size())
	# four branches of about 7 km: the first two are sampled, the next would pass 20 km in all
	var f := _doc(4096.0)
	var fp := _oval(f, 600.0, 400.0, 24)
	f.data.branches = []
	for q in 4:
		f.data.branches.append({"uid": 910 + q * 10, "name": "WAY %d" % (q + 1), "kind": "road",
			"fork": {"p": int(fp[1 + q].uid), "t": 0.5}, "merge": {"p": int(fp[8 + q].uid), "t": 0.5}, "side": 0, "merge_side": 0,
			"points": [{"uid": 911 + q * 10, "pos": [1900.0, 0.0, 1900.0], "width": 12.0, "style": "asphalt"},
				{"uid": 912 + q * 10, "pos": [-900.0, 0.0, 1900.0], "width": 12.0, "style": "asphalt"}]})
	var bf := _compile(f)
	var longs := bf.report.all_of("branch_long")
	var names := []
	for lg in longs:
		names.append(str(lg.name))
	t.check(names == ["WAY 3", "WAY 4"] and str(longs[0].text).contains("20 km in all") if longs.size() == 2 else false,
		"branches past 20 km in all are left out, in doc order (%s: %s)" % [str(names), str(longs[0].text) if not longs.is_empty() else ""])


## 400 points alternating between the four corners `c` (nudged 0.5 m apart).
func _corners(d: LevelDoc, c: Array) -> LevelDoc:
	var pts := []
	for i in 400:
		var p: Vector3 = c[i % 4] + Vector3(i * 0.5, 0, 0)
		pts.append({"uid": d.new_uid(), "pos": [p.x, p.y, p.z], "width": 14.0, "style": "asphalt"})
	d.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	return d


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
	# L5: PHYSICS compiles as the catalog offers it (PropCatalog.physics_ok: a props model, its AABB's
	# largest side under 3 m), at the prop's scale
	var models := {"x/fence": {"mass": 30.0, "aabb_min": [-1.4, 0, -0.1], "aabb_max": [1.4, 2.0, 0.1]},
		"x/pole": {"mass": 20.0, "aabb_min": [0, 0, 0], "aabb_max": [0.2, 3.2, 0.2]},
		"x/gib": {"mass": 5.0, "kind": "gibs", "aabb_min": [0, 0, 0], "aabb_max": [0.5, 0.5, 0.5]}}
	var ph := _doc()
	_oval(ph)
	ph.data.props = []
	for key in ["x/fence", "x/pole", "x/gib", "x/fence"]:
		ph.data.props.append({"uid": ph.new_uid(), "model": key, "pos": [float(ph.data.props.size()) * 5.0, 0.0, 0.0], "yaw": 0.0,
			"pitch": 0.0, "roll": 0.0, "scale": 1.2 if ph.data.props.size() == 3 else 1.0, "physics": true, "tag": ""})
	var bp := _compile(ph, {"registries": {"models": models, "materials": {}, "skies": {}, "music": {}}})
	var got := []
	for e in bp.data.props:
		got.append(bool(e.get("physics", false)))
	var want := [PropCatalog.make_facts("x/fence", models["x/fence"]).physics_ok, PropCatalog.make_facts("x/pole", models["x/pole"]).physics_ok,
		PropCatalog.make_facts("x/gib", models["x/gib"]).physics_ok, false]
	t.check(got == [true, false, false, false] and got == want and int(bp.report.first("prop_static").get("count", 0)) == 3,
		"PHYSICS as the catalog offers it: a 2.8 m fence knocks over, a 3.2 m pole, a gib and the fence at 1.2x stand still (%s, catalog %s)" % [str(got), str(want)])
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
