class_name LevelValidate
## What makes a track raceable (1.8 / 3.9): every rule with its text and FIX id. P4.
##
## run(ctx) checks the road, grid, world, water, items, budget and missing-content rules on a
## compile's context, then calls the hooks (LevelBranches.lint, LevelHazards.lint,
## LevelCrowds.lint) and finally fills the text and fix of every issue a hook reported with only
## its code. Every issue is {level, code, text, fix, uid, road, s, pos} (+ the args it was made
## from). Texts: `%s` names, `%d` numbers, `%%` a percent sign; `{ed_x}` tokens are the editor's
## key prompts (EditorKit.prompt fills them; plain() writes them as words elsewhere).

## code -> text template (1.8)
const TEXTS := {
	"no_road": "No road yet: press {ed_tool_road} and click on the ground, or hold the button and draw.",
	"open_loop": "The road is not a closed loop: click one of its two ends (the blue points) or press {ed_close_loop}.",
	"lap_short": "The lap is %d m long: a lap needs at least 200 m.",
	"lap_long": "The lap is %d km long: 20 km is the most.",
	"outside": "The road leaves the world %d m after the start: drag the point back inside, or make the world bigger (TERRAIN > RESIZE WORLD).",
	"too_tight": "The bend %d m after the start is too tight for a %d m road: drag its point outward or narrow the road ({ed_mod_ctrl} + wheel).",
	"crossing": "Two roads meet %d m after the start at the same height: raise one by 7 m and make it a BRIDGE.",
	"grid": "The start needs 70 m of flat, straight road behind it: a %s is %d m behind the line.",
	"start_jump": "The start line is on a jump: move the start line or remove the jump.",
	"steep": "The road climbs %d %% %d m after the start: 45 %% is the most a kart can drive.",
	"under_water": "The road runs under the water %d m after the start: raise it or lower the water.",
	"branch_range": "The branch %s leaves or rejoins too close to the start line: keep both ends between 4 %% and 96 %% of the lap.",
	"branch_order": "The branch %s rejoins the road before it leaves it: swap its ends.",
	"branch_nose": "The branch %s parts from the road %d m after the fork: it should part within 15-70 m. Move its first point.",
	"branch_kind": "The branch %s leaves or rejoins in a tunnel or on a see-saw: forks need an open road, a street or a bridge.",
	"branch_bank": "The branch %s leaves the road on a banked bend: set that bank to AUTO or move the fork to a straight.",
	"branch_radius": "The branch %s leaves the road on a bend tighter than 120 m: move the fork to a straighter stretch.",
	"branch_jump": "The branch %s shares its first or last metres with a jump: move the jump or the fork.",
	"branch_cross": "The branch %s crosses the main road: keep it on one side.",
	"branch_edge": "The branch %s runs inside the main road: move its points out.",
	"branch_tight": "The branch %s has a bend too tight for its width: drag the point outward.",
	"branch_items": "Crates or a pad on the branch %s sit where it still shares the main road.",
	"branch_long": "The branch %s is %d km long: 8 km is the most.",
	"hazard_setup": "The %s needs %s: move it to a green spot or delete it.",
	"over_cap": "Too many %s: %d of %d. Delete some.",
	"compile": "The track could not be built: %s.",
	"pad_grid": "A boost pad is within 12 m of the grid.",
	"pad_crate": "A boost pad is within 10 m of a crate row.",
	"item_jump": "Crates or a pad sit on or within 16 m of a jump.",
	"jump_boost": "The jump %d m after the start needs %d m/s: only boosted karts make it.",
	"no_items": "No item crates on the lap yet.",
	"steep_warn": "The road climbs %d %% %d m after the start: karts will crawl up it.",
	"embankment": "This stretch runs %d m over the ground: it may look better as a bridge.",
	"hazard_lint": "%s",
	"crowd": "%d of %d spectators were left out: %s.",
	"budget": "Past the budget for %s (%d of %d): slow PCs may stutter.",
	"tunnel_lights": "The tunnel lights were spaced out to keep within 96.",
	"missing": "%d objects, materials or songs are not on this computer; they are left out here.",
	"prop_on_road": "A solid object stands on the road %d m after the start.",
	"bot_lap": "%s",
	# additions (P4): what the compiler itself skips or changes
	"prop_static": "%d objects are too heavy or too big to knock over: they stand still here.",
	"screens": "%d Breencast screens are left out: they need the Combine start arch.",
	"bake_n": "The road was sampled again (%d samples, the save had %d): save the track to keep it.",
}

## A count text's singular (its count is 1): used as it is, no placeholders.
const TEXTS_ONE := {
	"missing": "1 object, material or song is not on this computer; it is left out here.",
	"prop_static": "1 object is too heavy or too big to knock over: it stands still here.",
	"screens": "1 Breencast screen is left out: it needs the Combine start arch.",
}

## code -> fix id ("" none): LevelFixes.ops (P13) turns an issue into its FIX ops.
const FIXES := {
	"no_road": "", "open_loop": "close_loop", "lap_short": "", "lap_long": "", "outside": "",
	"too_tight": "narrow", "crossing": "bridge", "grid": "clear_grid", "start_jump": "remove_jump",
	"steep": "smooth", "under_water": "raise_water", "branch_range": "legal_spot",
	"branch_order": "", "branch_nose": "", "branch_kind": "legal_spot", "branch_bank": "legal_spot",
	"branch_radius": "legal_spot", "branch_jump": "legal_spot", "branch_cross": "", "branch_edge": "",
	"branch_tight": "narrow", "branch_items": "", "branch_long": "", "hazard_setup": "hazard_setup", "over_cap": "",
	"compile": "", "pad_grid": "", "pad_crate": "", "item_jump": "", "jump_boost": "",
	"no_items": "auto_items", "steep_warn": "smooth", "embankment": "bridge", "hazard_lint": "",
	"crowd": "", "budget": "", "tunnel_lights": "", "missing": "", "prop_on_road": "delete",
	"bot_lap": "", "prop_static": "", "screens": "", "bake_n": "",
}

# ---------------------------------------------------------------- additions (P4)

## code -> level ("error" / "warning" / "info").
const LEVELS := {
	"no_road": "error", "open_loop": "error", "lap_short": "error", "lap_long": "error",
	"outside": "error", "too_tight": "error", "crossing": "error", "grid": "error",
	"start_jump": "error", "steep": "error", "under_water": "error", "branch_range": "error",
	"branch_order": "error", "branch_nose": "error", "branch_kind": "error", "branch_bank": "error",
	"branch_radius": "error", "branch_jump": "error", "branch_cross": "error", "branch_edge": "error",
	"branch_tight": "error", "branch_items": "error", "branch_long": "error", "hazard_setup": "error", "over_cap": "error",
	"compile": "error", "pad_grid": "warning", "pad_crate": "warning", "item_jump": "warning",
	"jump_boost": "warning", "no_items": "warning", "steep_warn": "warning", "embankment": "warning",
	"hazard_lint": "warning", "crowd": "warning", "budget": "warning", "tunnel_lights": "warning",
	"missing": "warning", "prop_on_road": "warning", "bot_lap": "info", "prop_static": "warning",
	"screens": "warning", "bake_n": "info",
}

## code -> the issue keys that fill the template's placeholders, in order.
const ARGS := {
	"lap_short": ["m"], "lap_long": ["km"], "outside": ["m"], "too_tight": ["m", "w"],
	"crossing": ["m"], "grid": ["what", "m"], "steep": ["pct", "m"], "under_water": ["m"],
	"branch_range": ["name"], "branch_order": ["name"], "branch_nose": ["name", "m"],
	"branch_kind": ["name"], "branch_bank": ["name"], "branch_radius": ["name"],
	"branch_jump": ["name"], "branch_cross": ["name"], "branch_edge": ["name"],
	"branch_tight": ["name"], "branch_items": ["name"], "branch_long": ["name", "km"], "hazard_setup": ["what", "needs"],
	"over_cap": ["what", "count", "cap"], "compile": ["why"], "jump_boost": ["m", "speed"],
	"steep_warn": ["pct", "m"], "embankment": ["h"], "hazard_lint": ["line"],
	"crowd": ["left", "count", "why"], "budget": ["what", "count", "budget"], "missing": ["count"],
	"prop_on_road": ["m"], "bot_lap": ["line"], "prop_static": ["count"], "screens": ["count"],
	"bake_n": ["n", "was"],
}

## The words the race side shows for the editor's key tokens (plain()).
const KEY_WORDS := {"ed_tool_road": "R", "ed_close_loop": "C", "ed_mod_ctrl": "Ctrl"}

## Soft budgets (4.5): [what (text), stats / data count, budget].
const BUDGET_PROPS := 1500
const BUDGET_LIGHTS := 64
const BUDGET_PEOPLE := 450
const BUDGET_HAZARDS := 32
const BUDGET_HEAVY := 6
const BUDGET_CRATES := 64
const BUDGET_LAP := 8000.0
const BUDGET_BRANCHES := 4
## Hard caps the compile itself counts (2.10).
const CAP_CRATES := 256
const CAP_LIGHTS := 128

const LAP_MIN := 200.0
const LAP_MAX := 20000.0
const EDGE := 40.0              # roads keep this far inside the world's edge
const GRID_BACK := 70.0
const GRID_BANK := 2.0          # degrees
const STEEP := 0.45
const STEEP_WARN := 0.30
const WATER_CLEAR := 0.7
const EMBANK_H := 8.0
const EMBANK_LEN := 40.0
const CROSS_DY := 6.5
const CROSS_CELL := 16.0
const CROSS_SAME := 13          # exported samples of the same road never cross
const PAD_GRID := 12.0
const PAD_CRATE := 10.0
const ITEM_JUMP := 16.0
const TOP_SPEED := 31.0
const SPEED_MARGIN := 1.08
const G := 15.24
## At most this many issues of one code per road (the rest of a long stretch says nothing new).
const PER_ROAD := 6


static func run(ctx: LevelContext) -> void:
	if ctx == null or ctx.report == null:
		return
	var rep := ctx.report
	var hooks: Dictionary = ctx.get_meta("hooks", {}) if ctx.has_meta("hooks") else {}
	if _road_blocked(ctx):
		_content_rules(ctx)
		_finish(rep)
		return
	var m := ctx.main
	if m.length < LAP_MIN:
		issue(rep, "lap_short", {"m": roundi(m.length)}, {"road": -1, "s": 0.0, "pos": m.pos[0]})
	elif m.length > LAP_MAX:
		issue(rep, "lap_long", {"km": roundi(m.length / 1000.0)}, {"road": -1, "s": 0.0, "pos": m.pos[0]})
	_grid(ctx)
	for r in ctx.roads:
		if r == null or r.n < 2:
			continue
		_outside(ctx, r)
		if r == m:
			_too_tight(ctx, r)
		_steep(ctx, r)
		_under_water(ctx, r)
		_embankment(ctx, r)
	_jumps(ctx, m)
	_crossings(ctx)
	_items(ctx)
	_props_on_road(ctx)
	_content_rules(ctx)
	_call(hooks.get("branches", LevelBranches), "lint", ctx)
	_call(hooks.get("hazards", LevelHazards), "lint", ctx)
	_call(hooks.get("crowds", LevelCrowds), "lint", ctx)
	_finish(rep)


static func text(code: String, args: Dictionary) -> String:
	var tpl := str(TEXTS.get(code, ""))
	if tpl == "":
		return ""
	var keys: Array = ARGS.get(code, [])
	if keys.is_empty():
		return tpl
	if TEXTS_ONE.has(code):
		var c = args.get(keys[0])
		if (c is int or c is float) and roundi(float(c)) == 1:
			return TEXTS_ONE[code]
	var vals := []
	var specs := _specs(tpl)
	for k in specs.size():
		var key: String = keys[k] if k < keys.size() else ""
		var v = args.get(key)
		if specs[k] == "d":
			vals.append(roundi(float(v)) if v is float or v is int else 0)
		else:
			vals.append(str(v) if v != null else "")
	return tpl % vals


# ---------------------------------------------------------------- additions (P4)

## Adds an issue at its code's level with its text (filled from args) and fix id; `where` holds
## uid / road / s / pos (and anything a FIX needs). Hooks report through this.
static func issue(report: LevelReport, code: String, args := {}, where := {}) -> void:
	if report == null:
		return
	var w := where.duplicate()
	for k in args:
		if not w.has(k):
			w[k] = args[k]
	var t := text(code, args)
	if t == "":
		t = code
	match str(LEVELS.get(code, "warning")):
		"error":
			report.error(code, t, w, str(FIXES.get(code, "")))
		"info":
			report.info(code, t, w)
		_:
			report.warning(code, t, w, str(FIXES.get(code, "")))


## Whether a code stops a TEST DRIVE (1.7): no road, an open main loop, a compile failure.
static func blocks(code: String) -> bool:
	return code in LevelReport.BLOCKING


## A text with the editor's {ed_x} key tokens written as words (the race side, NEW RACE cards).
static func plain(t: String) -> String:
	for k in KEY_WORDS:
		t = t.replace("{%s}" % k, str(KEY_WORDS[k]))
	var rx := RegEx.create_from_string("\\{ed_[a-z0-9_]+\\}")
	return rx.sub(t, "the key", true)


## The launch speed a kicker needs (branches.launch_speed port; P6's LevelBranches.launch_speed is
## used when it answers): over `gap` + 2 m, the far road `drop` metres below the lip.
static func launch_speed(gap: float, lift: float, ramp_len: float, drop: float, g := G) -> float:
	var v0 := LevelBranches.launch_speed(gap, lift, ramp_len, drop, g)
	if v0 > 0.0:
		return v0
	var th := atan(2.0 * lift / maxf(ramp_len, 0.01))
	var lo := 1.0
	var hi := 120.0
	for _k in 60:
		var v := 0.5 * (lo + hi)
		var vs := v * sin(th)
		var vc := v * cos(th)
		var disc := vs * vs + 2.0 * g * drop
		if disc >= 0.0 and vc * (vs + sqrt(disc)) / g >= gap + 2.0:
			hi = v
		else:
			lo = v
	return hi


# ---------------------------------------------------------------- the rules

## no_road / open_loop / compile: true when there is no closed, sampled main loop to check (also
## when the compiler refused a far too long road unsampled: its lap_long blocks).
static func _road_blocked(ctx: LevelContext) -> bool:
	var rep := ctx.report
	if rep.has("no_road") or rep.has("open_loop") or rep.has("compile"):
		return true
	var road = ctx.doc.data.get("road", {}) if ctx.doc != null else {}
	var pts: Array = road.get("points", []) if road is Dictionary else []
	if pts.is_empty():
		issue(rep, "no_road")
		return true
	if not bool(road.get("closed", false)) or pts.size() < 3:
		issue(rep, "open_loop", {}, {"road": -1, "uid": int(pts[0].get("uid", 0)) if pts[0] is Dictionary else 0})
		return true
	if bool(rep.first("lap_long").get("blocks", false)):
		return true
	if ctx.main == null or ctx.main.n < 3:
		issue(rep, "compile", {"why": "the road has no length"}, {"road": -1})
		return true
	return false


static func _grid(ctx: LevelContext) -> void:
	var m := ctx.main
	var back := ceili(GRID_BACK / m.step)
	for k in range(1, mini(back, m.n - 1) + 1):
		var i := m.wrap(-k)
		var what := ""
		if m.gap[i] == 1 or (m.lift.size() == m.n and m.lift[i] > 0.0):
			what = "jump"
		elif m.seesaw.size() == m.n and m.seesaw[i] == 1:
			what = "see-saw"
		elif m.bank_set.size() == m.n and m.bank_set[i] == 1 and absf(rad_to_deg(m.bank[i])) > GRID_BANK:
			what = "banked bend"
		if what != "":
			issue(ctx.report, "grid", {"what": what, "m": k * m.step},
				{"road": -1, "s": m.s[i], "pos": m.pos[i], "uid": _uid_at(m, i)})
			break
	for k in range(-2, 3):
		var i := m.wrap(k)
		if m.gap[i] == 1:
			issue(ctx.report, "start_jump", {}, {"road": -1, "s": 0.0, "pos": m.pos[0], "uid": _uid_at(m, i)})
			break


static func _outside(ctx: LevelContext, r: LevelRoad) -> void:
	var half := ctx.doc.world_size() * 0.5 - EDGE
	var hits := 0
	var last := -INF
	for i in r.n:
		var p := r.pos[i]
		if absf(p.x) <= half and absf(p.z) <= half:
			continue
		if r.s[i] - last < 60.0 and last > -INF:
			last = r.s[i]
			continue
		last = r.s[i]
		issue(ctx.report, "outside", {"m": r.s[i]}, {"road": r.key, "s": r.s[i], "pos": p, "uid": _uid_at(r, i)})
		hits += 1
		if hits >= PER_ROAD:
			return


static func _too_tight(ctx: LevelContext, r: LevelRoad) -> void:
	var runs := r.runs(func(i: int) -> bool:
		var tr := maxf(r.treatment(i, 0), r.treatment(i, 1))
		return absf(r.curv[i]) * (r.width[i] * 0.5 + tr + 2.0) > 1.0)
	var hits := 0
	for run in runs:
		var best := run[0]
		for i in run:
			if absf(r.curv[i]) > absf(r.curv[best]):
				best = i
		issue(ctx.report, "too_tight", {"m": r.s[best], "w": r.width[best]},
			{"road": r.key, "s": r.s[best], "pos": r.pos[best], "uid": _uid_at(r, best)})
		hits += 1
		if hits >= PER_ROAD:
			return


static func _steep(ctx: LevelContext, r: LevelRoad) -> void:
	var grade := PackedFloat32Array()
	grade.resize(r.n)
	var has_lift := r.lift.size() == r.n
	var last := r.n if r.closed else r.n - 1
	for i in last:
		var j := r.wrap(i + 1)
		if r.gap[i] == 1 or r.gap[j] == 1 or (has_lift and (r.lift[i] > 0.0 or r.lift[j] > 0.0)):
			continue
		grade[i] = absf(r.pos[j].y - r.pos[i].y) / maxf(r.step, 0.01)
	for code in ["steep", "steep_warn"]:
		var lim: float = STEEP if code == "steep" else STEEP_WARN
		var runs := r.runs(func(i: int) -> bool: return grade[i] > lim, true)
		var hits := 0
		for run in runs:
			var best := run[0]
			for i in run:
				if grade[i] > grade[best]:
					best = i
			if code == "steep_warn" and grade[best] > STEEP:
				continue
			issue(ctx.report, code, {"pct": grade[best] * 100.0, "m": r.s[best]},
				{"road": r.key, "s": r.s[best], "pos": r.pos[best], "uid": _uid_at(r, best)})
			hits += 1
			if hits >= PER_ROAD:
				break


static func _under_water(ctx: LevelContext, r: LevelRoad) -> void:
	var water = ctx.doc.data.get("water", {})
	var sea := water is Dictionary and bool(water.get("sea", false))
	var sea_y := float(water.get("level", 0.0)) if water is Dictionary else 0.0
	var lakes := []
	for l in ctx.doc.data.get("lakes", []):
		if l is Dictionary and l.get("center") is Array and l.get("size") is Array:
			var c := Vector2(float(l.center[0]), float(l.center[1]))
			var sz := Vector2(float(l.size[0]), float(l.size[1]))
			lakes.append([Rect2(c - sz * 0.5, sz), float(l.get("level", 0.0))])
	if not sea and lakes.is_empty():
		return
	var runs := r.runs(func(i: int) -> bool:
		var p := r.pos[i]
		if sea and p.y < sea_y + WATER_CLEAR:
			return true
		for l in lakes:
			if (l[0] as Rect2).has_point(Vector2(p.x, p.z)) and p.y < float(l[1]) + WATER_CLEAR:
				return true
		return false, true)
	var hits := 0
	for run in runs:
		var i := run[0]
		issue(ctx.report, "under_water", {"m": r.s[i]}, {"road": r.key, "s": r.s[i], "pos": r.pos[i], "uid": _uid_at(r, i)})
		hits += 1
		if hits >= PER_ROAD:
			return


static func _embankment(ctx: LevelContext, r: LevelRoad) -> void:
	var t := ctx.terrain
	if t == null:
		return
	var over := PackedFloat32Array()
	over.resize(r.n)
	for i in r.n:
		var k := r.kind(i)
		if r.gap[i] == 1 or not (k == "open" or k == "street"):
			continue
		var g := t.natural_at(r.pos[i].x, r.pos[i].z)
		if not is_nan(g):
			over[i] = r.pos[i].y - g
	var runs := r.runs(func(i: int) -> bool: return over[i] > EMBANK_H, true)
	var hits := 0
	for run in runs:
		if (run.size() - 1) * r.step < EMBANK_LEN:
			continue
		var best := run[0]
		for i in run:
			if over[i] > over[best]:
				best = i
		issue(ctx.report, "embankment", {"h": over[best]},
			{"road": r.key, "s": r.s[run[0]], "pos": r.pos[best], "uid": _uid_at(r, best),
			"s_end": r.s[run[run.size() - 1]]})
		hits += 1
		if hits >= PER_ROAD:
			return


## jump_boost: each jump of the main loop the karts' top speed cannot clear.
static func _jumps(ctx: LevelContext, r: LevelRoad) -> void:
	var pts: Array = ctx.doc.data.get("road", {}).get("points", [])
	for gp in r.gaps:
		var first := gp.x
		var end := gp.y
		var lip := r.wrap(first - 1)
		var land := r.wrap(end)
		var k := r.seg[first]
		var gd = pts[k].get("gap") if k < pts.size() and pts[k] is Dictionary else null
		if not (gd is Dictionary):
			continue
		var length := maxf(float(end - first + 1) * r.step, float(gd.get("len", 12.0)))
		var drop := r.pos[lip].y - r.pos[land].y
		var need := SPEED_MARGIN * launch_speed(length, float(gd.get("lift", 1.8)), float(gd.get("ramp", 16.0)), drop)
		if need > TOP_SPEED:
			issue(ctx.report, "jump_boost", {"m": r.s[first], "speed": need},
				{"road": r.key, "s": r.s[first], "pos": r.pos[first], "uid": _uid_at(r, first)})


## crossing: two stretches closer in plan than half their widths + 1 m with less than 6.5 m between
## their surfaces, on exported samples, away from the same road's next 13 samples and from a
## branch's junction ranges (read from its data.branches entry).
static func _crossings(ctx: LevelContext) -> void:
	var roads: Array = []
	for r in ctx.roads:
		if r != null and r.n >= 3:
			roads.append(r)
	if roads.is_empty():
		return
	var ranges := {}   # branch key -> [Vector2i fork range, Vector2i merge range] (main exported indices)
	for e in ctx.data.get("branches", []):
		if not (e is Dictionary):
			continue
		var key := str(e.get("id", "")).trim_prefix("b").to_int()
		ranges[key] = [Vector2i(int(e.get("fork_i", -1)) - 2, int(e.get("fork_nose_i", -1)) + 2),
			Vector2i(int(e.get("merge_nose_i", -1)) - 2, int(e.get("merge_i", -1)) + 2)]
	var cells := {}
	for ri in roads.size():
		var r: LevelRoad = roads[ri]
		var e := 0
		while e * 3 < r.n:
			var p := r.pos[e * 3]
			var c := Vector2i(floori(p.x / CROSS_CELL), floori(p.z / CROSS_CELL))
			if not cells.has(c):
				cells[c] = []
			cells[c].append(Vector2i(ri, e))
			e += 1
	var reported := {}   # "ra|rb" -> [exported index on ra of each report]
	var hits := 0
	for ri in roads.size():
		var ra: LevelRoad = roads[ri]
		var e := 0
		while e * 3 < ra.n:
			var i := e * 3
			if ra.gap[i] == 1:
				e += 1
				continue
			var p := ra.pos[i]
			var c := Vector2i(floori(p.x / CROSS_CELL), floori(p.z / CROSS_CELL))
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					for q in cells.get(c + Vector2i(dx, dz), []):
						var rj: int = q.x
						var f: int = q.y
						if rj < ri or (rj == ri and f <= e):
							continue
						var rb: LevelRoad = roads[rj]
						var j := f * 3
						if rb.gap[j] == 1:
							continue
						if rj == ri:
							var ne := (ra.n + 2) / 3
							var d := absi(f - e)
							if ra.closed:
								d = mini(d, ne - d)
							if d <= CROSS_SAME:
								continue
						var pb := rb.pos[j]
						var plan := Vector2(p.x - pb.x, p.z - pb.z).length()
						if plan >= (ra.width[i] + rb.width[j]) * 0.5 + 1.0 or absf(p.y - pb.y) >= CROSS_DY:
							continue
						if ri == 0 and rj > 0 and ra == ctx.main and _in_junction(ranges.get(rb.key), e):
							continue
						var pk := "%d|%d" % [ri, rj]
						var near := false
						for prev in reported.get(pk, []):
							if absi(int(prev) - e) < 20:
								near = true
								break
						if near:
							continue
						if not reported.has(pk):
							reported[pk] = []
						reported[pk].append(e)
						issue(ctx.report, "crossing", {"m": ra.s[i]}, {"road": ra.key, "s": ra.s[i],
							"pos": (p + pb) * 0.5, "uid": _uid_at(ra, i), "road_b": rb.key, "s_b": rb.s[j]})
						hits += 1
						if hits >= PER_ROAD * 2:
							return
			e += 1


static func _in_junction(rg: Variant, e: int) -> bool:
	if not (rg is Array):
		return false
	for v in rg:
		var a: Vector2i = v
		if a.x <= e and e <= a.y and a.y >= 0:
			return true
	return false


## Items: no_items, pad_grid / pad_crate, item_jump; over_cap and budget of the compiled data.
static func _items(ctx: LevelContext) -> void:
	var rep := ctx.report
	var data := ctx.data
	var boxes: Array = data.get("item_boxes", [])
	if boxes.is_empty():
		issue(rep, "no_items", {}, {"road": -1})
	var grid := []
	for g in data.get("grid", []):
		grid.append(_v3(g.get("pos")))
	var rows: Array = ctx.get_meta("rows", []) if ctx.has_meta("rows") else []
	var pads: Array = ctx.get_meta("pads", []) if ctx.has_meta("pads") else []
	for pd in pads:
		var p: Vector3 = pd.pos
		var where := {"uid": int(pd.uid), "road": int(pd.road), "s": float(pd.s), "pos": p}
		for g in grid:
			if p.distance_to(g) < PAD_GRID:
				issue(rep, "pad_grid", {}, where)
				break
		for rw in rows:
			var hit := false
			for c in rw.crates:
				if p.distance_to(c) < PAD_CRATE:
					hit = true
					break
			if hit:
				issue(rep, "pad_crate", {}, where)
				break
	for list in [rows, pads]:
		for it in list:
			var r := ctx.road(int(it.road))
			if r == null:
				continue
			if _near_gap(r, int(it.i), ITEM_JUMP):
				issue(rep, "item_jump", {}, {"uid": int(it.uid), "road": int(it.road), "s": float(it.s), "pos": r.pos[int(it.i)]})


static func _near_gap(r: LevelRoad, i: int, metres: float) -> bool:
	var k := ceili(metres / maxf(r.step, 0.01))
	for d in range(-k, k + 1):
		var j := i + d
		if not r.closed and (j < 0 or j >= r.n):
			continue
		if r.gap[r.wrap(j)] == 1:
			return true
	return false


## prop_on_road: a solid doc prop (static, not deco / far / float) standing on a road's surface.
static func _props_on_road(ctx: LevelContext) -> void:
	var src: Array = ctx.get_meta("props_src", []) if ctx.has_meta("props_src") else []
	if src.is_empty():
		return
	var cells := {}
	for r in ctx.roads:
		if r == null:
			continue
		var e := 0
		while e * 3 < r.n:
			var p := r.pos[e * 3]
			var c := Vector2i(floori(p.x / CROSS_CELL), floori(p.z / CROSS_CELL))
			if not cells.has(c):
				cells[c] = []
			cells[c].append([r, e * 3])
			e += 1
	var hits := 0
	for pr in src:
		var e: Dictionary = pr[1]
		if bool(e.get("physics", false)) or str(e.get("tag", "")) in ["deco", "far", "float"]:
			continue
		var p := _v3(e.get("pos"))
		var c := Vector2i(floori(p.x / CROSS_CELL), floori(p.z / CROSS_CELL))
		var found := false
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				for q in cells.get(c + Vector2i(dx, dz), []):
					var r: LevelRoad = q[0]
					var i: int = q[1]
					var d := p - r.pos[i]
					var along := absf(d.x * r.fwd[i].x + d.z * r.fwd[i].z)
					var lat := absf(d.dot(r.flat_right[i]))
					if r.gap[i] == 0 and along < r.step * 2.0 and lat < r.width[i] * 0.5 and absf(d.y) < 3.0:
						issue(ctx.report, "prop_on_road", {"m": r.s[i]}, {"uid": int(pr[0]), "road": r.key, "s": r.s[i], "pos": p})
						found = true
						break
				if found:
					break
			if found:
				break
		if found:
			hits += 1
			if hits >= PER_ROAD * 4:
				return


## over_cap, budget and missing: counts of the compiled data and the report.
static func _content_rules(ctx: LevelContext) -> void:
	var rep := ctx.report
	var data := ctx.data
	var stats: Dictionary = ctx.get_meta("stats", {}) if ctx.has_meta("stats") else {}
	var crates: int = (data.get("item_boxes", []) as Array).size()
	var lights := int(stats.get("lights_wanted", (data.get("lights", []) as Array).size()))
	if crates > CAP_CRATES:
		issue(rep, "over_cap", {"what": "crates", "count": crates, "cap": CAP_CRATES})
	if lights > CAP_LIGHTS:
		issue(rep, "over_cap", {"what": "lights", "count": lights, "cap": CAP_LIGHTS})
	var heavy := 0
	for h in data.get("hazards", []):
		if h is Dictionary and str(h.get("type", "")) in LevelDoc.HEAVY:
			heavy += 1
	var people := int(stats.get("people", (data.get("crowds", []) as Array).size()))
	var lap := ctx.main.length if ctx.main != null else 0.0
	var budgets := [
		["props", (data.get("props", []) as Array).size(), BUDGET_PROPS],
		["lights", mini(lights, CAP_LIGHTS), BUDGET_LIGHTS],
		["spectators", people, BUDGET_PEOPLE],
		["hazards", (data.get("hazards", []) as Array).size(), BUDGET_HAZARDS],
		["heavy hazards", heavy, BUDGET_HEAVY],
		["crates", mini(crates, CAP_CRATES), BUDGET_CRATES],
		["branches", (data.get("branches", []) as Array).size(), BUDGET_BRANCHES],
	]
	for b in budgets:
		if int(b[1]) > int(b[2]):
			issue(rep, "budget", {"what": b[0], "count": b[1], "budget": b[2]})
	if lap > BUDGET_LAP and lap <= LAP_MAX:
		issue(rep, "budget", {"what": "the lap length (m)", "count": lap, "budget": BUDGET_LAP})
	var miss := rep.missing_total()
	if miss > 0:
		issue(rep, "missing", {"count": miss})


## Fills the text and fix of issues a hook reported with only a code (or without a fix id).
static func _finish(rep: LevelReport) -> void:
	for it in rep.items:
		var code := str(it.code)
		if not TEXTS.has(code):
			continue
		if str(it.get("fix", "")) == "" and it.level != "info":
			it.fix = str(FIXES.get(code, ""))
		if str(it.get("text", "")) == "" or str(it.text) == code:
			it.text = text(code, it)


# ---------------------------------------------------------------- helpers

## The format specs of a template in order ("d", "s"), %% skipped.
static func _specs(tpl: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while i < tpl.length() - 1:
		if tpl[i] == "%":
			var c := tpl[i + 1]
			if c == "%":
				i += 2
				continue
			out.append("d" if c == "d" else "s")
			i += 2
			continue
		i += 1
	return out


static func _uid_at(r: LevelRoad, i: int) -> int:
	if i < 0 or i >= r.seg.size():
		return 0
	var k := r.seg[i]
	return r.point_uids[k] if k >= 0 and k < r.point_uids.size() else 0


static func _call(hook: Variant, method: String, ctx: LevelContext) -> void:
	if hook != null and hook.has_method(method):
		hook.call(method, ctx)


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
