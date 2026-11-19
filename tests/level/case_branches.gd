extends RefCounted
## P6: branches, compile side (spec 3.6) without content, the context built by hand from
## LevelRoad.build and a flat LevelTerrain: a good branch's data.branches entry carries every field
## TrackBranch reads and path.s_main (monotone fork_s .. merge_s), its noses lie 15-70 m from its
## ends, TrackPath.new + add_branches loads it; the junction masks, the follow, the lap line and the
## branch line, the gores; each branch_* error on a crafted bad branch, which is then left out of
## ctx.roads, the main road's masks and the export; the item rules; legal flags; flat zones;
## safe_drop; launch_speed against tools/branches.py.

const NEEDS_CONTENT := false
const FIELDS := ["id", "name", "index", "kind", "fork_s", "merge_s", "fork_i", "merge_i", "fork_nose_u",
	"merge_nose_u", "fork_nose_i", "merge_nose_i", "side", "merge_side", "length", "saves", "risk",
	"need_speed", "need_boost", "ai", "respawn", "retry_back", "offtrack", "merge_type", "in_hall", "path"]

var styles := {}
var t: Node


func run(tt: Node) -> void:
	t = tt
	styles = LevelStyles.resolve({}, {})
	_good()
	_items()
	_bad()
	_legal()
	_safe_drop()
	_launch()


# ---------------------------------------------------------------- helpers

## A stadium loop: the right straight x = +r from z = -half_len to +half_len (100 m between
## points, driven toward +z, so its left is +x), the top arc, the left straight back, the bottom
## arc. uids from 1 in driving order: the right straight's points are 1 (z = -half_len) .. 9.
## mods: uid -> keys merged into that point.
func _stadium(r: float, half_len := 400.0, mods := {}) -> Array:
	var pts := []
	var arc := maxi(3, roundi(PI * r / 75.0) - 1)
	var cnt := int(2.0 * half_len / 100.0) + 1
	for k in cnt:
		pts.append(Vector3(r, 0.0, -half_len + 100.0 * k))
	for k in arc:
		var a := PI * (k + 1) / (arc + 1)
		pts.append(Vector3(r * cos(a), 0.0, half_len + r * sin(a)))
	for k in cnt:
		pts.append(Vector3(-r, 0.0, half_len - 100.0 * k))
	for k in arc:
		var a := PI + PI * (k + 1) / (arc + 1)
		pts.append(Vector3(r * cos(a), 0.0, -half_len + r * sin(a)))
	var out := []
	for k in pts.size():
		var p: Vector3 = pts[k]
		var d := {"uid": k + 1, "pos": [p.x, p.y, p.z], "width": 14.0, "style": "asphalt"}
		if mods.has(k + 1):
			d.merge(mods[k + 1], true)
		out.append(d)
	return out


func _pt(uid: int, x: float, y: float, z: float, w := 10.0, extra := {}) -> Dictionary:
	var d := {"uid": uid, "pos": [x, y, z], "width": w, "style": "asphalt"}
	d.merge(extra, true)
	return d


## The good branch: forks at z = -250 on the right straight, out to x = 205 on its left (+x),
## a 12 m jump on its middle segment, back at z = +250.
func _good_branch(extra := {}) -> Dictionary:
	var b := {"uid": 100, "name": "OLD QUARRY", "kind": "jump", "fork": {"p": 2, "t": 0.5}, "merge": {"p": 7, "t": 0.5},
		"side": 0, "merge_side": 0,
		"points": [_pt(101, 195.0, 1.5, -150.0), _pt(102, 205.0, 0.0, 0.0, 10.0, {"gap": {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}}),
			_pt(103, 195.0, 0.0, 150.0)],
		"ai": {"take": 0.7, "min_skill": 0.2, "commit": 35.0}, "risk": 0.4, "respawn": "before", "retry_back": 45.0,
		"offtrack": -1.0}
	b.merge(extra, true)
	return b


func _doc(main_pts: Array, branches: Array, extra := {}) -> LevelDoc:
	var doc := LevelDoc.new()
	doc.data = {"guid": "0123456789abcdef0123456789abcdef", "name": "BRANCH TEST",
		"road": {"closed": true, "start": {"p": int(main_pts[0].uid), "t": 0.0}, "points": main_pts},
		"branches": branches, "items": [], "crates": [], "pads": [], "barrels": [], "zones": [],
		"bake": {"main_n": 0, "branch_n": {}, "rows": {}}}
	doc.data.merge(extra, true)
	return doc


## Steps 1-4 of 3.1 by hand: styles, the main road with the branches' flat zones, the branches.
func _ctx(doc: LevelDoc) -> LevelContext:
	var ctx := LevelContext.new()
	ctx.doc = doc
	ctx.report = LevelReport.new()
	ctx.meshes = LevelMeshSet.new()
	ctx.styles = styles
	var road: Dictionary = doc.data.road
	ctx.main = LevelRoad.build(road.points, styles, true, {"start": road.start, "flat": LevelBranches.flat_zones(doc)})
	ctx.roads = [ctx.main]
	ctx.terrain = LevelTerrain.flat_world(2048.0, 257, 0.0)
	LevelBranches.build(ctx)
	return ctx


## Steps 6-10: pits + safe_drop, lines, gores, export (the main path goes into data first).
func _rest(ctx: LevelContext) -> Array:
	for r in ctx.roads:
		r.mark_pits(Callable(ctx, "ground"))
	LevelBranches.safe_drop(ctx)
	var off := LevelLine.racing(ctx.main)
	off = LevelBranches.adjust_lap_line(ctx, off)
	LevelLine.apply(ctx.main, off)
	LevelBranches.racing(ctx)
	LevelBranches.geometry(ctx)
	ctx.data["path"] = ctx.main.export_path()
	var entries := LevelBranches.export_entries(ctx)
	ctx.data["branches"] = entries
	return entries


func _codes(ctx: LevelContext) -> PackedStringArray:
	var out := PackedStringArray()
	for it in ctx.report.items:
		out.append(str(it.code))
	return out


# ---------------------------------------------------------------- the good branch

func _good() -> void:
	var main_pts := _stadium(150.0)
	var doc := _doc(main_pts, [_good_branch()])
	var ctx := _ctx(doc)
	var m := ctx.main
	t.check(ctx.branches.size() == 1, "one branch state")
	var b: Dictionary = ctx.branches[0]
	t.check(b.ok and ctx.roads.size() == 2 and ctx.road(100) != null, "the good branch is kept (errors: %s)" % str(_codes(ctx)))
	if not b.ok:
		return
	var r: LevelRoad = b.road
	t.check(r.key == 100 and not r.closed and r.n % 3 == 1, "the branch road: key, open, 3k + 1 samples (%d)" % r.n)
	t.check(int(b.side0) == -1 and int(b.side1) == -1, "auto side: left of the main road (+x)")
	t.check(int(b.i0) % 3 == 0 and int(b.i1) % 3 == 0 and int(b.i0) < int(b.i1), "fork / merge on exported samples")
	# ends on the main road's edge, along its tangent, with its frames
	var lat0 := (r.pos[0] - m.pos[b.i0]).dot(m.flat_right[b.i0])
	t.near(lat0, -(14.0 - 10.0) * 0.5, 0.01, "the fork end: the outer edge on the main road's edge")
	t.check(r.fwd[0].is_equal_approx(m.fwd[b.i0]) and r.right[r.n - 1].is_equal_approx(m.right[b.i1]), "end frames copied from the main road")
	var f1 := (r.pos[2] - r.pos[0]).normalized()
	t.check(f1.dot(m.fwd[b.i0]) > 0.999, "leaves along the main road's tangent (%.5f)" % f1.dot(m.fwd[b.i0]))
	var mr := r.mesh_road()
	t.check(mr.fwd[0].is_equal_approx(m.fwd[b.i0]) and mr.up[mr.n - 1].is_equal_approx(m.up[b.i1]), "the mesh road's end frames too")
	# noses
	var zf: Dictionary = b.zones.fork
	var zm: Dictionary = b.zones.merge
	t.check(int(zf.k_nose) > 0 and int(zm.k_nose) > 0 and int(zf.k_sep) >= 0, "both noses found")
	var u0 := r.s[int(zf.k_nose)]
	var u1 := r.length - r.s[int(zm.k_nose)]
	t.check(u0 >= 15.0 and u0 <= 70.0 and u1 >= 15.0 and u1 <= 70.0, "noses 15-70 m from the ends (%.1f, %.1f)" % [u0, u1])
	t.log("noses %.1f m / %.1f m, gore gap %.2f m, branch %.0f m, %d samples" % [u0, u1, float(zf.gore), r.length, r.n])
	# follow: where the roads overlap the branch lies on the main road's surface
	var worst := 0.0
	for w in zf.walk:
		if float(w[2]) < 0.0:
			worst = maxf(worst, absf(r.pos[w[0]].y - LevelBranches._main_y(m, w[1], r.pos[w[0]])))
	t.check(worst <= 0.05, "the overlap follows the main road's surface (%.3f m off)" % worst)
	t.check(r.pos[r.closest(Vector3(195, 0, -150))].y > 1.2, "beyond the overlap the branch keeps its own heights")
	# masks: junction on both, the main road's left side cut to the nose, the branch clipped
	var ia: int = b.i0 + 3
	t.check(m.junction[ia] == 1 and r.junction[3] == 1, "junction flags on both roads")
	t.check(m.side_off[ia * 2] == 1 and m.side_off[ia * 2 + 1] == 0, "the main road's left side treatment cut at the fork")
	t.check(m.side_off[(int(zf.i_nose) + 3) * 2] == 0, "and kept past the nose")
	t.check(r.side_off[3 * 2 + 1] == 1 and r.side_off[3 * 2] == 0, "the branch's inner (right) side cut")
	var clipped := 0
	for k in r.n:
		if not is_nan(r.clip_in[k]):
			clipped += 1
			if r.clip_side[k] != 1:
				t.fail("clip_side 1 (the right edge moves) on a left branch")
				break
	t.check(clipped > 3 and not (b.trim_seg as Dictionary).is_empty(), "the inner edge clipped onto the main road's (%d samples)" % clipped)
	# flat zones cover the shared stretches; AUTO bank 0 there
	var zones := LevelBranches.flat_zones(doc)
	t.check(zones.size() == 2, "a flat zone per fork and merge")
	var za := m.anchor_s(zones[0].a)
	var zb := m.anchor_s(zones[1].a)
	t.check(za - float(zones[0].before) <= m.s[b.i0] and m.s[zf.i_nose] <= za + float(zones[0].after), "the fork zone covers fork..nose")
	t.check(zb - float(zones[1].before) <= m.s[zm.i_nose] and m.s[b.i1] <= zb + float(zones[1].after), "the merge zone covers nose..merge")
	var bank := 0.0
	for d in posmod(int(zf.i_nose) - int(b.i0), m.n) + 1:
		bank = maxf(bank, absf(m.bank[m.wrap(b.i0 + d)]))
	t.check(bank < 1e-4, "no bank over the shared stretch (%.5f)" % bank)
	# the rest of the compile
	var entries := _rest(ctx)
	t.check(ctx.report.errors() == 0, "no errors (%s)" % str(_codes(ctx)))
	t.check(entries.size() == 1, "one entry")
	if entries.is_empty():
		return
	var e: Dictionary = entries[0]
	var missing := []
	for f in FIELDS:
		if not e.has(f):
			missing.append(f)
	t.check(missing.is_empty(), "every field TrackBranch reads (missing %s)" % str(missing))
	t.check(e.id == "b100" and e.index == 0 and e.kind == "jump" and e.name == "OLD QUARRY", "id, index, kind, name")
	var ai: Dictionary = e.ai
	t.check(is_equal_approx(ai.take, 0.7) and is_equal_approx(ai.min_skill, 0.2) and is_equal_approx(ai.commit, 35.0), "ai take / min_skill / commit")
	t.check(e.side == -1 and e.merge_side == -1 and e.merge_type == "gore" and e.in_hall == false, "sides, merge type, in_hall")
	var lap_step := m.length / (m.n / 3)
	t.near(e.fork_s, e.fork_i * lap_step, 0.01, "fork_s = fork_i * the lap's exported step")
	t.check(e.fork_i * 3 == int(b.i0) and e.merge_i * 3 == int(b.i1), "fork_i / merge_i exported indices")
	t.near(e.saves, e.merge_s - e.fork_s - e.length, 0.02, "saves")
	t.check(e.fork_nose_u >= 15.0 and e.length - e.merge_nose_u >= 15.0 and e.fork_nose_u <= 70.0 and e.length - e.merge_nose_u <= 70.0, "nose metres in the entry")
	var path: Dictionary = e.path
	t.check(path.has("s_main"), "path.s_main present")
	var sm: Array = path.get("s_main", [])
	t.check(sm.size() == (path.center as Array).size(), "one s_main per exported sample (%d)" % sm.size())
	var mono := true
	for k in range(1, sm.size()):
		if float(sm[k]) < float(sm[k - 1]):
			mono = false
	t.check(mono and sm.size() > 1 and is_equal_approx(float(sm[0]), e.fork_s) and is_equal_approx(float(sm[-1]), e.merge_s), "s_main monotone fork_s .. merge_s")
	# up to the fork nose s_main is the main road's own progress
	var sp := float(sm[1])
	t.check(sp > e.fork_s and sp < e.fork_s + 12.0, "s_main near the fork follows the lap (%.2f)" % sp)
	# the jump
	var g: Vector2i = r.gaps[0] if not r.gaps.is_empty() else Vector2i(-1, -1)
	t.check(r.gaps.size() == 1, "one jump on the branch")
	if g.x > 0:
		var gap := (g.y - g.x + 1) * r.step
		var drop := r.pos[g.x - 1].y - r.pos[g.y].y
		var want := 1.08 * LevelBranches.launch_speed(gap, 1.8, 16.0, drop)
		t.near(e.need_speed, want, 0.011, "need_speed = 1.08 x launch_speed")
		t.check(e.need_boost == (want > 31.0), "need_boost")
		t.log("jump %.1f m, drop %.2f m, needs %.2f m/s" % [gap, drop, e.need_speed])
	# TrackPath loads it
	var tp := TrackPath.new(m.export_path())
	tp.add_branches(entries)
	t.check(tp.branches.size() == 1, "TrackPath.add_branches loads the entry")
	if tp.branches.size() == 1:
		var tb: TrackBranch = tp.branches[0]
		t.check(tb.s_main.size() == tb.n and tb.n == sm.size(), "TrackBranch took s_main (no linear fallback)")
		t.near(tb.main_s(0.0), e.fork_s, 0.02, "main_s at the fork")
		t.near(tb.main_s(tb.length), e.merge_s, 0.02, "main_s at the merge")
		t.check(tb.fork_i == e.fork_i and tb.merge_nose_i == e.merge_nose_i and tb.side == -1, "indices and side read back")
		t.check(tb.gap.count(1) > 0 and is_equal_approx(tb.ai_commit, 35.0), "the jump and ai commit read back")
		t.check(not tp.junctions_near(e.fork_i + 2).is_empty(), "the fork zone registers a junction")
		# what tests/branch_check.gd checks on a built circuit's data
		var nn: int = (path.center as Array).size()
		var keys_ok := true
		for key in ["line", "fwd", "right", "up", "width", "speed", "gap", "pit", "mag", "theme", "s_main"]:
			keys_ok = keys_ok and path.has(key) and (path[key] as Array).size() == nn
		t.check(keys_ok and not bool(path.get("closed", true)), "path keys per sample, closed false")
		t.check(absf(tb.fork_i * tp.step - tb.fork_s) < tp.step and absf(tb.merge_i * tp.step - tb.merge_s) < tp.step, "fork_i / merge_i match fork_s / merge_s")
		var c0 := tb.center[0].distance_to(tp.center_at(tb.fork_s))
		var c1 := tb.center[tb.n - 1].distance_to(tp.center_at(tb.merge_s))
		t.check(c0 <= tp.width[tb.fork_i] * 0.5 + 0.5 and c1 <= tp.width[tb.merge_i] * 0.5 + 0.5, "starts and ends on the main road (%.2f, %.2f m)" % [c0, c1])
		t.check(tb.gap[0] == 0 and tb.gap[tb.n - 1] == 0, "no gap at either end")
		t.check(tb.fork_nose_u > 0.0 and tb.fork_nose_u < tb.merge_nose_u and tb.merge_nose_u < tb.length, "noses inside the branch, in order")
		t.check(tb.step * (tb.n - 2) <= tb.length + 0.01 and tb.step * (tb.n - 1) >= tb.length - 0.01, "samples evenly spaced")
		var slope := 0.0
		for q in tb.n - 1:
			slope = maxf(slope, (tb.s_main[q + 1] - tb.s_main[q]) / maxf(tb.u_of(q + 1) - tb.u_of(q), 0.01))
		t.check(slope < 3.01, "s_main rate stays under 3 (%.2f)" % slope)
		for nu in [tb.fork_nose_u, tb.merge_nose_u]:
			var qp := tb.center_at(nu)
			var ci := tp.closest(qp, tp.index_at(tb.main_s(nu)) - 4)
			var ds := absf(tp.progress(qp, ci) - tb.main_s(nu))
			t.check(ds < 2.0, "s_main matches the main road's progress at the nose u %.0f (off by %.2f m)" % [nu, ds])
	# the lap line keeps 3 m off the branch's side over the shared stretches
	var worst_l := -INF
	for d in posmod(int(zf.i_nose) - int(b.i0), m.n) + 1:
		var i := m.wrap(b.i0 + d)
		worst_l = maxf(worst_l, m.line_off[i] * -1.0 - (m.width[i] * 0.5 - 3.0))
	t.check(worst_l <= 1e-4, "the lap line keeps clear of the fork side (%.4f)" % worst_l)
	# the branch's racing line
	t.check(r.line.size() == r.n and r.speed.size() == r.n and r.line_off.size() == r.n, "branch line and speeds filled")
	var pinned := true
	for k in LevelBranches.PINS:
		pinned = pinned and absf(r.line_off[k]) < 1e-6 and absf(r.line_off[r.n - 1 - k]) < 1e-6
	t.check(pinned, "first and last 6 samples on the centre")
	var moves := false
	for k in r.n:
		if absf(r.line_off[k]) > 0.5:
			moves = true
	t.check(moves, "the line uses the road in between")
	# gores: road strips in the main road's material on the branch's key
	var gore_tris := 0
	var mat := str(m.style_at(b.i0).road)
	var lo_y := INF
	var hi_y := -INF
	for bk in ctx.meshes.buckets():
		if int(bk.road) == 100 and bk.kind == "road" and bk.material == mat:
			gore_tris += (bk.i as PackedInt32Array).size() / 3
			for v in (bk.v as PackedVector3Array):
				lo_y = minf(lo_y, v.y)
				hi_y = maxf(hi_y, v.y)
	t.check(gore_tris >= 4, "gore triangles at both noses (%d)" % gore_tris)
	var top := -INF
	for k in r.n:
		if k <= int(zf.k_nose) or k >= int(zm.k_nose):
			top = maxf(top, maxf(r.surface(k, -5.0).y, r.surface(k, 5.0).y))
	t.check(lo_y >= -0.05 and hi_y <= top + 0.05, "the gores run from the main road's surface to the branch's edge (%.3f..%.3f)" % [lo_y, hi_y])
	# legal flags: red inside the kept branch's shared stretch unless it is the one being edited
	var fl := LevelBranches.legal(ctx)
	var e0: int = int(b.i0) / 3
	t.check((fl.branch_fork as PackedByteArray).size() == m.n / 3, "a flag per exported main sample")
	t.check(fl.branch_fork[e0] == 0, "no fork inside a branch's shared stretch")
	var fl2 := LevelBranches.legal(ctx, 100)
	t.check(fl2.branch_fork[e0] == 1, "its own stretch does not count (except_uid)")
	t.check(fl.has("branch_fork_b100") and fl.branch_fork_b100[e0] == 1 and fl.branch_merge_b100.size() == m.n / 3,
		"per-branch flags without its own stretches (marker drags)")
	# determinism (and what the branch steps cost: build, then pits..export)
	var doc2 := _doc(_stadium(150.0), [_good_branch()])
	var hold := []
	var t_main: float = t.ms(func() -> void: LevelRoad.build(doc2.data.road.points, styles, true, {"start": doc2.data.road.start}))
	var t_build: float = t.ms(func() -> void: hold.append(_ctx(doc2)))
	t_build -= t_main
	var ctx2: LevelContext = hold[0]
	var t_rest: float = t.ms(func() -> void: hold.append(_rest(ctx2)))
	var again: Array = hold[1]
	t.log("branch build %.1f ms, pits + lines + gores + export %.1f ms (main road %.1f ms)" % [t_build, t_rest, t_main])
	t.check(JSON.stringify(again) == JSON.stringify(entries), "two compiles give identical entries")
	# low gravity over the jump lowers what it needs
	var zdoc := _doc(_stadium(150.0), [_good_branch()], {"zones": [{"uid": 300, "road": 100, "a": {"p": 102, "t": 0.1},
		"b": {"p": 102, "t": 0.9}, "scale": 0.4, "ease": 5.0}]})
	var zctx := _ctx(zdoc)
	var ze := _rest(zctx)
	t.check(ze.size() == 1 and float(ze[0].need_speed) < float(e.need_speed) - 1.0, "a low-gravity zone lowers need_speed (%.2f < %.2f)" % [float(ze[0].need_speed) if ze.size() == 1 else -1.0, e.need_speed])


# ---------------------------------------------------------------- item rules

func _items() -> void:
	var doc := _doc(_stadium(150.0), [_good_branch()], {
		"items": [{"uid": 200, "road": 100, "at": {"p": 101, "t": 0.4}, "count": 0, "inset": 2.5}],
		"pads": [{"uid": 201, "road": -1, "at": {"p": 4, "t": 0.0}, "lat": null, "turn": 0.0}]})
	var ctx := _ctx(doc)
	_rest(ctx)
	LevelBranches.lint(ctx)
	t.check(ctx.report.errors() == 0, "items between the noses and lap items away from junctions pass (%s)" % str(_codes(ctx)))
	# a crate row inside the branch's shared stretch, a pad on the lap at the fork, a barrel on the jump
	var doc2 := _doc(_stadium(150.0), [_good_branch()], {
		"items": [{"uid": 210, "road": 100, "at": {"p": 100, "t": 0.05}, "count": 0, "inset": 2.5}],
		"pads": [{"uid": 211, "road": -1, "at": {"p": 2, "t": 0.55}, "lat": null, "turn": 0.0}],
		"barrels": [{"uid": 212, "road": 100, "at": {"p": 102, "t": 0.5}}]})
	var ctx2 := _ctx(doc2)
	_rest(ctx2)
	LevelBranches.lint(ctx2)
	var hit := {}
	for it in ctx2.report.items:
		if it.code == "branch_items":
			hit[int(it.uid)] = it
	t.check(hit.has(210), "branch_items: a crate row in the branch's shared stretch")
	t.check(hit.has(211), "branch_items: a lap pad within 4 samples of a junction")
	t.check(hit.has(212), "branch_items: a barrel on the branch's jump")
	if hit.has(210):
		var it: Dictionary = hit[210]
		t.check(int(it.branch) == 100 and int(it.road) == 100 and str(it.text).contains("OLD QUARRY") and not str(it.text).contains("{"),
			"the issue names the branch and carries where it is")


# ---------------------------------------------------------------- crafted bad branches

func _bad() -> void:
	var good_pts: Array = _good_branch().points
	var cases := [
		["branch_range", _stadium(150.0), _good_branch({"fork": {"p": 1, "t": 0.03}})],
		["branch_order", _stadium(150.0), _good_branch({"fork": {"p": 7, "t": 0.5}, "merge": {"p": 2, "t": 0.5},
			"points": [_pt(101, 195.0, 0.0, 150.0), _pt(102, 205.0, 0.0, 0.0), _pt(103, 195.0, 0.0, -150.0)]})],
		["branch_nose", _stadium(150.0), _good_branch({"points": [_pt(101, 160.0, 0.0, -150.0), _pt(102, 160.0, 0.0, 0.0),
			_pt(103, 160.0, 0.0, 150.0)]})],
		["branch_kind", _stadium(150.0, 400.0, {2: {"style": "tunnel"}}), _good_branch()],
		["branch_bank", _stadium(150.0, 400.0, {3: {"bank": 8.0}}), _good_branch()],
		["branch_radius", _stadium(80.0), {"uid": 100, "name": "BEND", "kind": "alt", "fork": {"p": 10, "t": 0.2},
			"merge": {"p": 12, "t": 0.6}, "side": 0, "merge_side": 0,
			"points": [_pt(101, 110.0, 0.0, 470.0), _pt(102, 0.0, 0.0, 530.0), _pt(103, -110.0, 0.0, 470.0)]}],
		["branch_jump", _stadium(150.0, 400.0, {2: {"gap": {"len": 8.0, "at": 0.6, "lift": 1.0, "ramp": 10.0}}}), _good_branch()],
		["branch_cross", _stadium(150.0), _good_branch({"side": 1, "points": [_pt(101, 195.0, 0.0, -150.0, 14.0),
			_pt(102, 205.0, 0.0, 0.0, 14.0), _pt(103, 195.0, 0.0, 150.0, 14.0)]})],
		["branch_edge", _stadium(150.0), _good_branch({"points": [_pt(101, 151.5, 0.0, -200.0, 6.0), _pt(102, 205.0, 0.0, -40.0, 6.0),
			_pt(103, 205.0, 0.0, 100.0, 6.0), _pt(104, 180.0, 0.0, 190.0, 6.0)]})],
		["branch_tight", _stadium(150.0), _good_branch({"points": [good_pts[0], _pt(110, 250.0, 0.0, -140.0, 20.0),
			_pt(111, 262.0, 0.0, -128.0, 20.0), _pt(112, 250.0, 0.0, -116.0, 20.0),
			good_pts[1], good_pts[2]]})],
	]
	for c in cases:
		var code: String = c[0]
		var doc := _doc(c[1], [c[2]])
		var ctx := _ctx(doc)
		var b: Dictionary = ctx.branches[0] if not ctx.branches.is_empty() else {}
		var codes := _codes(ctx)
		t.check(code in codes, "%s fires (got %s)" % [code, str(codes)])
		t.log("%s case: %s" % [code, str(codes)])
		t.check(not b.is_empty() and not b.ok and int(b.index) == -1, "%s: the branch is marked not ok" % code)
		t.check(ctx.roads.size() == 1 and ctx.road(100) == null, "%s: left out of ctx.roads" % code)
		var m := ctx.main
		t.check(m.junction.count(1) == 0 and m.side_off.count(1) == 0, "%s: no junction masks on the main road" % code)
		var entries := _rest(ctx)
		t.check(entries.is_empty(), "%s: left out of data.branches" % code)
		var tris := 0
		for bk in ctx.meshes.buckets():
			if int(bk.road) == 100:
				tris += 1
		t.check(tris == 0, "%s: no gore geometry" % code)
		for it in ctx.report.items:
			if it.code == code:
				t.check(str(it.text) != "" and not str(it.text).contains("{") and int(it.branch) == 100 and it.pos is Vector3,
					"%s: text and where (%s)" % [code, str(it.text)])
				break
	# a good branch next to a bad one keeps index 0 and the main road keeps only its masks
	var doc2 := _doc(_stadium(150.0), [_good_branch({"uid": 90, "side": 1}), _good_branch()])
	var ctx2 := _ctx(doc2)
	t.check(ctx2.branches.size() == 2 and not ctx2.branches[0].ok and ctx2.branches[1].ok, "a bad branch before a good one")
	var ent := _rest(ctx2)
	t.check(ent.size() == 1 and ent[0].index == 0 and ent[0].id == "b100", "kept branches count in doc order")


# ---------------------------------------------------------------- legal spots

func _legal() -> void:
	# R 60 m arcs; a 10 deg bank on the right straight at z = 200 (uid 7); the left straight's
	# segment from z = 0 to -100 a tunnel (uid 17: left straight from uid 13 at z = 400)
	var pts := _stadium(60.0, 400.0, {7: {"bank": 10.0}, 17: {"style": "tunnel"}})
	t.check(is_equal_approx(float(pts[16].pos[2]), 0.0) and float(pts[16].pos[0]) < 0.0, "the tunnel point sits on the left straight at z 0")
	var ctx := _ctx(_doc(pts, []))
	var m := ctx.main
	var fl := LevelBranches.legal(ctx)
	var fork: PackedByteArray = fl.branch_fork
	var merge: PackedByteArray = fl.branch_merge
	var at := func(p: Vector3) -> int: return roundi(m.closest(p) / 3.0) % (m.n / 3)
	t.check(fork[at.call(Vector3(60, 0, -200))] == 1 and merge[at.call(Vector3(60, 0, -100))] == 1, "legal on a straight")
	t.check(fork[at.call(Vector3(60, 0, 200))] == 0 and merge[at.call(Vector3(60, 0, 200))] == 0, "not on a banked stretch")
	t.check(fork[at.call(Vector3(0, 0, 460))] == 0 and merge[at.call(Vector3(0, 0, 460))] == 0, "not on a 60 m bend")
	t.check(fork[at.call(Vector3(-60, 0, -50))] == 0 and merge[at.call(Vector3(-60, 0, -50))] == 0, "not in a tunnel")
	t.check(fork[0] == 0 and merge[0] == 0, "not at the start line")
	t.check(fork[at.call(Vector3(-60, 0, 60))] == 0, "a fork needs 80 m clear ahead (a tunnel 60 m on)")
	t.check(merge[at.call(Vector3(-60, 0, 60))] == 1, "a merge looks behind")
	var any := 0
	for v in fork:
		any += v
	t.log("legal forks on %d of %d exported samples" % [any, fork.size()])


# ---------------------------------------------------------------- safe drop

func _safe_drop() -> void:
	# road A 10 m over road B where they cross; no terrain: every sample is a pit at first
	var a_pts := [_pt(1, 0.0, 10.0, 0.0, 12.0), _pt(2, 0.0, 10.0, 200.0, 12.0), _pt(3, 0.0, 10.0, 400.0, 12.0)]
	var b_pts := [_pt(11, -200.0, 0.0, 200.0, 14.0), _pt(12, 0.0, 0.0, 200.0, 14.0), _pt(13, 200.0, 0.0, 200.0, 14.0)]
	var ra := LevelRoad.build(a_pts, styles, false)
	var rb := LevelRoad.build(b_pts, styles, false, {"key": 5})
	var ctx := LevelContext.new()
	ctx.report = LevelReport.new()
	ctx.main = ra
	ctx.roads = [ra, rb]
	for r in ctx.roads:
		r.mark_pits(Callable(ctx, "ground"))
	t.check(ra.pit.count(0) == 0 and rb.pit.count(0) == 0, "without terrain every sample is a pit")
	LevelBranches.safe_drop(ctx)
	var over := ra.closest(Vector3(0, 10, 200))
	var away := ra.closest(Vector3(0, 10, 100))
	t.check(ra.pit[over] == 0 and ra.pit[away] == 1, "a pit over another road is cleared, others stay")
	var cleared := ra.pit.count(0)
	t.check(cleared >= 4 and cleared <= 8, "only over the lower road's surface less a metre (%d samples)" % cleared)
	t.check(rb.pit.count(0) == 0, "the lower road keeps its pits")
	# too far below (30 m): kept
	var a2 := LevelRoad.build([_pt(1, 0.0, 30.0, 0.0, 12.0), _pt(2, 0.0, 30.0, 200.0, 12.0), _pt(3, 0.0, 30.0, 400.0, 12.0)], styles, false)
	var ctx2 := LevelContext.new()
	ctx2.roads = [a2, rb]
	a2.mark_pits(Callable(ctx2, "ground"))
	LevelBranches.safe_drop(ctx2)
	t.check(a2.pit.count(0) == 0, "a road 30 m below does not catch a fall")


# ---------------------------------------------------------------- launch speed

func _launch() -> void:
	# tools/branches.py launch_speed for the same inputs
	t.near(LevelBranches.launch_speed(12.0, 1.8, 16.0, 0.0, 15.24), 22.31896801676398, 1e-5, "launch_speed(12, 1.8, 16, 0)")
	t.near(LevelBranches.launch_speed(20.0, 2.5, 20.0, -3.0, 15.24), 39.42689437427199, 1e-5, "launch_speed(20, 2.5, 20, -3)")
	t.near(LevelBranches.launch_speed(8.0, 0.0, 16.0, 2.0, 9.8), 15.652475842498529, 1e-5, "launch_speed(8, 0, 16, 2, g 9.8)")
	t.near(LevelBranches.launch_speed(12.0, 1.8, 16.0, 0.0, 15.24 * 0.4), 14.115754791485058, 1e-5, "launch_speed under low gravity")
	t.check(LevelBranches.launch_speed(12.0, 1.8, 16.0, 0.0) == LevelBranches.launch_speed(12.0, 1.8, 16.0, 0.0, LevelBranches.G), "default g = 15.24")
	var zones := [{"s0": 100.0, "s1": 200.0, "scale": 0.4, "ease": 15.0}]
	t.near(LevelBranches.gravity_scale(zones, 150.0), 0.4, 1e-6, "gravity_scale inside a zone")
	t.near(LevelBranches.gravity_scale(zones, 50.0), 1.0, 1e-6, "gravity_scale outside")
	t.near(LevelBranches.gravity_scale(zones, 107.5), 0.7, 1e-6, "gravity_scale easing in")
