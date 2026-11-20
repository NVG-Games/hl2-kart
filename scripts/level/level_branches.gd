class_name LevelBranches
## Forks and shortcuts, compile side (3.6): a port of track_gen.Branch and tools/branches.py with
## the constants unchanged. build() makes each branch's open road from its fork to its merge on the
## main loop (ends on the main road's edge and along its tangent, phantom points, pad frames, the
## follow onto the main road's surface), walks both junctions (noses, junction flags, the inner
## edge clipped to the main road's, side cuts) and runs the early lint: a failing branch is left
## out (ok = false, not in ctx.roads, no masks on the main road) with its branch_* errors kept.
## Then the flat junction zones, safe drops, the lap line adjust and the branch racing lines, the
## gores, the data.branches entries (path.s_main inside the path), the item rules and legal spots.
##
## ctx.branches holds one Dictionary per doc branch (opaque to other lanes): uid, name, ok, index
## (in data.branches, -1 when left out), road (LevelRoad or null), errors (codes), i0 / i1 (fork /
## merge dense main samples), side0 / side1, lat0 / lat1, zones {fork, merge}, pts (the points
## the road was built from: the fork end, the doc's points, the merge end).
## A branch's road carries the branch uid as its key; its fork end point carries the branch uid as
## its point uid (so an anchor {p: branch uid, t} lies on the segment from the fork to the first
## point), its merge end point -uid.

## The kinds of main road a junction may meet.
const JUNCTION_KINDS := ["open", "street", "bridge"]
## Beside the main road the roads part for good where they are this far apart in height.
const NOSE_DY := 2.5
## The shared stretch ends within NOSE_MAX of the fork and of the merge, at least NOSE_MIN from it.
const NOSE_MAX := 70.0
const NOSE_MIN := 15.0
## Where the branch still lies on the main road it takes its surface, easing back over this far
## beyond (or at this grade where it was further off).
const FOLLOW_EASE := 20.0
const FOLLOW_GRADE := 0.08
## The inner edge is clipped onto the main road's edge only where their heights agree.
const SNAP_DY := 0.3
## Main road samples beyond each end (end frames, racing line pads).
const PAD := 16
## The racing line holds the branch's first and last PINS samples on its centre.
const PINS := 6
## The game's gravity; a jump needs SPEED_MARGIN times its ballistic launch speed, and one past
## TOP_SPEED is for boosted karts only.
const G := 15.24
const SPEED_MARGIN := 1.08
const TOP_SPEED := 31.0
## TrackPath.closest's search window round its hint (exported samples).
const WINDOW := Vector2i(-12, 25)
## s_main: the game's own progress where the branch runs within this far of the main road.
const NEAR := 20.0
## Legal spots: this far of junction-friendly road ahead of a fork / behind a merge.
const LEGAL_SPAN := 80.0
## Forks and merges lie inside this share of the lap.
const LAP_MIN := 0.04
const LAP_MAX := 0.96
## A branch longer than this (LevelRoad.length_bounds) is left out unsampled (6.9), and so is one
## that takes the branches sampled before it (doc order) past MAX_TOTAL in all.
const MAX_LEN := 8000.0
const MAX_TOTAL := 20000.0
## Plan radius a junction's main road needs, and the bank it may carry (rad, |right.y|).
const MIN_RADIUS := 120.0
const MAX_BANK := 0.01
## A branch's centre may lie this far over the main road's centre before it counts as crossing
## (a branch as wide as the main road starts on its centre line).
const CROSS_EPS := 0.05
## Flat zones reach this far past the fork / merge and past NOSE_MAX.
const FLAT_PAD := 10.0
## Lap items keep this many samples off a junction; branch items this many off a jump.
const LAP_ITEM_GAP := 4
const ITEM_JUMP := 8

## Fallback texts (1.8's wording) when LevelValidate.text gives none; {name} and {m} are filled.
const TEXTS := {
	"branch_range": "The branch {name} leaves or rejoins too close to the start line: keep both ends between 4 % and 96 % of the lap.",
	"branch_order": "The branch {name} rejoins the road before it leaves it: swap its ends.",
	"branch_nose": "The branch {name} parts from the road {m} m after the fork: it should part within 15-70 m. Move its first point.",
	"branch_nose_merge": "The branch {name} joins the road {m} m before the merge: it should join within 15-70 m. Move its last point.",
	"branch_nose_never": "The branch {name} never parts from the road: move its points out.",
	"branch_kind": "The branch {name} leaves or rejoins in a tunnel or on a see-saw: forks need an open road, a street or a bridge.",
	"branch_bank": "The branch {name} leaves the road on a banked bend: set that bank to AUTO or move the fork to a straight.",
	"branch_radius": "The branch {name} leaves the road on a bend tighter than 120 m: move the fork to a straighter stretch.",
	"branch_jump": "The branch {name} shares its first or last metres with a jump: move the jump or the fork.",
	"branch_cross": "The branch {name} crosses the main road: keep it on one side.",
	"branch_edge": "The branch {name} runs inside the main road: move its points out.",
	"branch_tight": "The branch {name} has a bend too tight for its width: drag the point outward.",
	"branch_items": "Crates or a pad on the branch {name} sit where it still shares the main road.",
	"branch_long": "The branch {name} is {km} km long: 8 km is the most.",
	"branch_long_total": "The branches come to {km} km with {name}: 20 km in all is the most, so it is left out.",
}


## Builds every doc branch's road, walks its junctions and runs the early lint (3.6 #1-6, #12):
## kept branches join ctx.roads (main first, then the kept ones in doc order) and mark the main
## road (junction, side_off); failing ones get ok = false and their branch_* errors.
static func build(ctx: LevelContext) -> void:
	ctx.branches = []
	ctx.set_meta("branch_len", 0.0)
	var m := ctx.main
	var roads: Array[LevelRoad] = []
	if m != null:
		roads.append(m)
	ctx.roads = roads
	if m == null or m.n < 6 or ctx.doc == null:
		return
	var list = ctx.doc.data.get("branches", [])
	if not (list is Array):
		return
	var kept := 0
	for q in (list as Array).size():
		var spec = list[q]
		if not (spec is Dictionary):
			continue
		var b := _make(ctx, spec)
		b["doc_index"] = q
		ctx.branches.append(b)
		if b.road != null:
			_early_lint(ctx, b)
		b.ok = (b.errors as Array).is_empty() and b.road != null
		if not b.ok:
			b.index = -1
			continue
		for i in b.main_junction:
			m.junction[i] = 1
		for k in b.main_side_off:
			m.side_off[k] = 1
		var t: LevelRoad = b.road
		_end_frames(m, t.mesh_road(), b)
		b.index = kept
		kept += 1
		ctx.roads.append(t)


## [{a, before, after}] of every branch's fork and merge (3.6 #13); P4 adds the grid zone and
## passes all to LevelRoad.build.
static func flat_zones(doc: LevelDoc) -> Array:
	var out := []
	if doc == null:
		return out
	var list = doc.data.get("branches", [])
	if not (list is Array):
		return out
	for b in list:
		if not (b is Dictionary):
			continue
		if b.get("fork") is Dictionary:
			out.append({"a": (b.fork as Dictionary).duplicate(), "before": FLAT_PAD, "after": NOSE_MAX + FLAT_PAD})
		if b.get("merge") is Dictionary:
			out.append({"a": (b.merge as Dictionary).duplicate(), "before": NOSE_MAX + FLAT_PAD, "after": FLAT_PAD})
	return out


## No fall where another road lies under a sample a kart could drop from (track_gen.safe_drop):
## a pit sample is cleared where a road surface (more than a metre inside its edge; a tunnel's
## floor beside the road too) lies 2-25 m below, on another road or more than 20 samples along the
## same one. Run after every kept road's mark_pits.
static func safe_drop(ctx: LevelContext) -> void:
	var roads := ctx.roads
	var grids := {}
	for ra in roads.size():
		var t := roads[ra]
		if t == null or t.n == 0 or t.pit.size() != t.n:
			continue
		var ids := PackedInt32Array()
		for i in t.n:
			if t.pit[i] == 1:
				ids.append(i)
		if ids.is_empty():
			continue
		for rb in roads.size():
			var t2 := roads[rb]
			if t2 == null or t2.n == 0:
				continue
			if not grids.has(rb):
				grids[rb] = _drop_grid(t2)
			var gr: Dictionary = grids[rb]
			var cell: float = gr.cell
			var half: PackedFloat32Array = gr.half
			var map: Dictionary = gr.map
			for i in ids:
				if t.pit[i] == 0:
					continue
				var p := t.pos[i]
				var cx := floori(p.x / cell)
				var cz := floori(p.z / cell)
				var hit := false
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var c = map.get(Vector2i(cx + dx, cz + dz))
						if c == null:
							continue
						for j in (c as PackedInt32Array):
							if t2.gap[j] == 1 or (t2.skip.size() == t2.n and t2.skip[j] == 1):
								continue
							var q := t2.pos[j]
							if Vector2(p.x - q.x, p.z - q.z).length() >= half[j]:
								continue
							var dy := p.y - q.y
							if dy < 2.0 or dy > 25.0:
								continue
							if ra == rb:
								var dk := absi(i - j)
								if t.closed:
									dk = mini(dk, t.n - dk)
								if dk <= 20:
									continue
							hit = true
							break
						if hit:
							break
					if hit:
						break
				if hit:
					t.pit[i] = 0


## The lap line over each kept branch's shared stretches (track_gen.lap_line): from 10 samples
## before to 10 after, 3 m off the side the branch leaves or joins from, easing out at 0.4 m per
## sample beyond, so a computer driver that stays on the lap clears the nose.
static func adjust_lap_line(ctx: LevelContext, off: PackedFloat32Array) -> PackedFloat32Array:
	var out := off.duplicate()
	var m := ctx.main
	if m == null or out.size() != m.n:
		return out
	for b in ctx.branches:
		if not b.ok:
			continue
		for end in ["fork", "merge"]:
			var z: Dictionary = b.zones[end]
			var side := float(z.side)
			var a: int = b.i0 if end == "fork" else _nose_i(b, "merge")
			var e: int = _nose_i(b, "fork") if end == "fork" else b.i1
			var span := posmod(e - a, m.n)
			for d in range(-10, span + 11):
				var i := m.wrap(a + d)
				var lim := m.width[i] * 0.5 - 3.0 + maxf(0.0, maxf(-d, d - span)) * 0.4
				out[i] = minf(out[i] * side, lim) * side
	return out


## Each kept branch's racing line and speeds (Branch.racing): LevelLine over the 16 main samples
## before the fork (moved onto the branch's centre), the branch and the 16 after the merge, the
## first and last 6 branch samples held on the centre; beside an open edge it keeps to the middle.
## Fills road.line, road.speed, road.line_off. Needs the pit flags (step 6).
static func racing(ctx: LevelContext) -> void:
	var m := ctx.main
	for b in ctx.branches:
		if not b.ok:
			continue
		var t: LevelRoad = b.road
		var n := t.n
		var lane := LevelRoad.new()
		lane.closed = false
		lane.n = n + 2 * PAD
		lane.step = t.step
		lane.styles = t.styles
		var i0: int = b.i0
		var i1: int = b.i1
		var lp := _shifted(m, i0 - PAD, i0, b.lat0)
		lp.append_array(t.pos)
		lp.append_array(_shifted(m, i1 + 1, i1 + 1 + PAD, b.lat1))
		var lr := PackedVector3Array()
		for j in range(i0 - PAD, i0):
			lr.append(m.right[m.wrap(j)])
		lr.append_array(t.right)
		for j in range(i1 + 1, i1 + 1 + PAD):
			lr.append(m.right[m.wrap(j)])
		var lw := PackedFloat32Array()
		var lg := PackedByteArray()
		var ls := PackedInt32Array()
		for q in lane.n:
			var k := clampi(q - PAD, 0, n - 1)
			lw.append(t.width[k])
			ls.append(t.style[k])
			var held := q < PAD or q >= PAD + n or t.gap[k] == 1 or k < PINS or k >= n - PINS
			lg.append(1 if held else 0)
		lane.pos = lp
		lane.right = lr
		lane.width = lw
		lane.gap = lg
		lane.style = ls
		var off_l := LevelLine.racing(lane)
		var vt_l := LevelLine.speeds(lane, off_l)
		var off := off_l.slice(PAD, PAD + n)
		var vt := vt_l.slice(PAD, PAD + n)
		if t.pit.size() == n:
			for k in n:
				if t.pit[k] == 1 and t.gap[k] == 0:
					var lim := maxf(t.width[k] * 0.5 - LevelLine.OPEN_EDGE, 0.0)
					off[k] = clampf(off[k], -lim, lim)
		t.line_off = off
		t.line = PackedVector3Array()
		t.line.resize(n)
		for k in n:
			t.line[k] = t.pos[k] + t.right[k] * off[k]
		t.speed = vt


## The gores (build_gores' surface): between the main road's edge and the branch's inner edge
## from where their edges part to the nose, a road strip at the main road's surface in the main
## road's material, with the nose's edge face below it (and the gore's underside over a deck).
## Road key = the branch's uid, group = the branch's group at the nose.
static func geometry(ctx: LevelContext) -> void:
	var m := ctx.main
	if m == null:
		return
	if ctx.meshes == null:
		ctx.meshes = LevelMeshSet.new()
	for b in ctx.branches:
		if not b.ok:
			continue
		for end in ["fork", "merge"]:
			_gore(ctx, m, b, end)


## The data.branches entries of the kept branches in doc order (Branch.export + branches.entry):
## every field TrackBranch reads, the path (3.2 export of the branch, with its racing line) with
## path.s_main (monotone, fork_s .. merge_s) and what its jumps need.
static func export_entries(ctx: LevelContext) -> Array:
	var out := []
	var m := ctx.main
	if m == null or m.n < 3:
		return out
	var lap := _lap(m)
	for b in ctx.branches:
		if not b.ok:
			continue
		out.append(_entry(ctx, m, lap, b))
	return out


## The item rules (step 13): a kept branch's crate rows, pads and barrels lie between its noses,
## clear of its jumps; the lap's lie at least 4 samples off a kept branch's shared stretch.
static func lint(ctx: LevelContext) -> void:
	var m := ctx.main
	if m == null or ctx.doc == null:
		return
	for sec in ["items", "pads", "barrels"]:
		var list = ctx.doc.data.get(sec, [])
		if not (list is Array):
			continue
		for it in list:
			if not (it is Dictionary) or not (it.get("at") is Dictionary):
				continue
			var road := int(it.get("road", -1))
			for b in ctx.branches:
				if not b.ok:
					continue
				if road == int(b.uid):
					var t: LevelRoad = b.road
					var k := t.anchor_i(it.at)
					var a := _nose_k(b, "fork")
					var e := _nose_k(b, "merge")
					var jump := false
					for j in range(maxi(k - ITEM_JUMP, 0), mini(k + ITEM_JUMP, t.n - 1) + 1):
						if t.gap[j] == 1:
							jump = true
							break
					if not (a < k and k < e) or jump:
						_error(ctx, b, "branch_items", {"uid": int(it.get("uid", 0)), "road": int(b.uid),
							"s": t.s[k], "pos": t.pos[k], "branch": int(b.uid), "item": sec})
				elif road == -1:
					var i := m.anchor_i(it.at)
					var near := false
					var jn: Dictionary = b.main_set
					for d in range(-LAP_ITEM_GAP, LAP_ITEM_GAP + 1):
						if jn.has(m.wrap(i + d)):
							near = true
							break
					if near:
						_error(ctx, b, "branch_items", {"uid": int(it.get("uid", 0)), "road": -1,
							"s": m.s[i], "pos": m.pos[i], "branch": int(b.uid), "item": sec})


## Legal spots per exported main sample (3.6 #14): bit "branch_fork" where a fork may start
## (junction-friendly road over the next 80 m: kind open / street / bridge, no gap, tunnel or
## see-saw, plan radius >= 120 m, no explicit bank over 0.01 rad, not inside another kept branch's
## shared stretch, lap fraction 0.04..0.96), "branch_merge" the same over the previous 80 m.
## Also "branch_fork_b<uid>" / "branch_merge_b<uid>" per kept branch: the same flags with that
## branch's own shared stretches not counting (where its fork / merge marker may be dragged).
## except_uid: leave that branch's stretches out of the two main arrays too.
static func legal(ctx: LevelContext, except_uid := -1) -> Dictionary:
	var m := ctx.main
	if m == null or m.n < 3:
		return {"branch_fork": PackedByteArray(), "branch_merge": PackedByteArray()}
	var n := m.n
	var road := PackedByteArray()
	road.resize(n)
	for j in n:
		var no := not (m.kind(j) in JUNCTION_KINDS) or m.gap[j] == 1 or m.seesaw[j] == 1
		no = no or (m.skip.size() == n and m.skip[j] == 1)
		no = no or absf(m.curv[j]) > 1.0 / MIN_RADIUS + 1e-6
		no = no or (m.bank_set[j] == 1 and absf(m.bank[j]) > MAX_BANK)
		road[j] = 1 if no else 0
	var kept := []
	for b in ctx.branches:
		if b.ok:
			kept.append(b)
	var out := _legal_bits(m, road, kept, except_uid, "")
	for b in kept:
		out.merge(_legal_bits(m, road, kept, int(b.uid), "_b%d" % int(b.uid)))
	return out


## The fork / merge bits over `road` (1 = not junction-friendly) with the kept branches' shared
## stretches added, except the one of `except_uid`.
static func _legal_bits(m: LevelRoad, road: PackedByteArray, kept: Array, except_uid: int, suffix: String) -> Dictionary:
	var n := m.n
	var ne := n / 3
	var fork := PackedByteArray()
	var merge := PackedByteArray()
	fork.resize(ne)
	merge.resize(ne)
	var bad := road.duplicate()
	for b in kept:
		if int(b.uid) == except_uid:
			continue
		for rng: Vector2i in [Vector2i(int(b.i0), _nose_i(b, "fork")), Vector2i(_nose_i(b, "merge"), int(b.i1))]:
			for d in posmod(rng.y - rng.x, n) + 1:
				bad[m.wrap(rng.x + d)] = 1
	# prefix sums over two laps (windows wrap)
	var pre := PackedInt32Array()
	pre.resize(2 * n + 1)
	for q in 2 * n:
		pre[q + 1] = pre[q] + bad[q % n]
	var w := mini(ceili(LEGAL_SPAN / maxf(m.step, 0.01)), n - 1)
	for e in ne:
		var i := 3 * e
		var f := float(i) / n
		if f <= LAP_MIN or f >= LAP_MAX:
			continue
		# [i, i + w] ahead, [i - w, i] behind (shifted by a lap so the indices stay positive)
		if pre[i + w + 1] - pre[i] == 0:
			fork[e] = 1
		if pre[i + n + 1] - pre[i - w + n] == 0:
			merge[e] = 1
	return {"branch_fork" + suffix: fork, "branch_merge" + suffix: merge}


## Speed at a kicker's lip (a u^2 ramp rising `lift` over `ramp_len` metres) that carries a kart
## over `gap` metres and 2 more, with the far road `drop` metres below the lip, under gravity g
## (branches.launch_speed: 60 bisections between 1 and 120 m/s).
static func launch_speed(gap: float, lift: float, ramp_len: float, drop: float, g := 15.24) -> float:
	var th := atan2(2.0 * lift, maxf(ramp_len, 1e-6))
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


# ---------------------------------------------------------------- additions (P6)

## The share of gravity at metres s under low-gravity zones [{s0, s1, scale, ease}]
## (branches.gravity_scale, LowGravityField.scale_at without the lap's wrap).
static func gravity_scale(zones: Array, s_m: float) -> float:
	var out := 1.0
	for z in zones:
		var span := float(z.s1) - float(z.s0)
		var d := s_m - float(z.s0)
		if d < 0.0 or d > span:
			continue
		var e := maxf(minf(float(z.get("ease", 15.0)), span * 0.5), 1e-3)
		var u0 := minf(d / e, 1.0)
		var u1 := minf((span - d) / e, 1.0)
		var w := u0 * u0 * (3.0 - 2.0 * u0) * u1 * u1 * (3.0 - 2.0 * u1)
		out = minf(out, 1.0 + (float(z.scale) - 1.0) * w)
	return out


## Branch metres of a nose (where the roads part for good): the fork's first sample or the
## merge's last when the walk found none.
static func nose_u(b: Dictionary, end: String) -> float:
	var t: LevelRoad = b.road
	if t == null:
		return 0.0
	return t.s[_nose_k(b, end)]


# ---------------------------------------------------------------- internals: the road

## One doc branch: its state dict, its road built when the ends resolve, the junction walk done.
static func _make(ctx: LevelContext, spec: Dictionary) -> Dictionary:
	var m := ctx.main
	var uid := int(spec.get("uid", 0))
	var b := {"uid": uid, "name": str(spec.get("name", "BRANCH")), "spec": spec, "ok": false, "index": -1,
		"road": null, "errors": [], "i0": 0, "i1": 0, "side0": 1, "side1": 1, "lat0": 0.0, "lat1": 0.0,
		"zones": {}, "pts": [], "trim_seg": {}, "main_junction": PackedInt32Array(),
		"main_side_off": PackedInt32Array(), "main_set": {}, "follow": null}
	var pts_doc: Array = []
	for p in spec.get("points", []):
		if p is Dictionary:
			pts_doc.append(p)
	var fa = spec.get("fork")
	var ma = spec.get("merge")
	if pts_doc.is_empty() or not (fa is Dictionary) or not (ma is Dictionary) \
			or not (int(fa.get("p", -1)) in m.point_uids) or not (int(ma.get("p", -1)) in m.point_uids):
		_error(ctx, b, "branch_range", {"uid": uid, "road": -1, "s": 0.0, "pos": m.pos[0], "branch": uid, "end": "fork"})
		return b
	var i0 := _resolve(m, fa)
	var i1 := _resolve(m, ma)
	var first: Dictionary = pts_doc[0]
	var last: Dictionary = pts_doc[-1]
	var s0 := int(spec.get("side", 0))
	var s1 := int(spec.get("merge_side", 0))
	var side0 := (1 if s0 > 0 else -1) if s0 != 0 else _side_of(m, i0, LevelRoad._vec(first.get("pos")))
	var side1 := (1 if s1 > 0 else -1) if s1 != 0 else _side_of(m, i1, LevelRoad._vec(last.get("pos")))
	# (a branch as wide as the main road or wider starts centred on it)
	var lat0 := side0 * maxf(m.width[i0] - float(first.get("width", 14.0)), 0.0) * 0.5
	var lat1 := side1 * maxf(m.width[i1] - float(last.get("width", 14.0)), 0.0) * 0.5
	var a := m.pos[i0] + m.right[i0] * lat0
	var e := m.pos[i1] + m.right[i1] * lat1
	var pts := [_end_point(uid, a, first)]
	pts.append_array(pts_doc)
	pts.append(_end_point(-uid, e, last))
	b.i0 = i0
	b.i1 = i1
	b.side0 = side0
	b.side1 = side1
	b.lat0 = lat0
	b.lat1 = lat1
	b.pts = pts
	var follow := _Follow.new(m, i0, i1, side0, side1)
	b.follow = follow
	var opts := {"key": uid, "pre": _phantom(m, a, LevelRoad._vec(first.get("pos")), i0),
		"post": _phantom(m, e, LevelRoad._vec(last.get("pos")), i1),
		"pad_before": _shifted(m, i0 - PAD, i0, lat0), "pad_after": _shifted(m, i1 + 1, i1 + 1 + PAD, lat1),
		"follow": follow.apply}
	var bake = ctx.doc.data.get("bake", {})
	if bake is Dictionary and bake.get("branch_n") is Dictionary:
		var hint := int(bake.branch_n.get(str(uid), 0))
		if hint > 0:
			opts["n_hint"] = hint
	var mats = ctx.registries.get("materials", {})
	if mats is Dictionary and not (mats as Dictionary).is_empty():
		opts["materials"] = mats
	# a branch far longer than any lap is refused before it is sampled (6.9)
	var lb := LevelRoad.length_bounds(pts, false, opts)
	if lb.x > MAX_LEN or lb.y > MAX_LEN * LevelRoad.LONG_BOUND:
		_error(ctx, b, "branch_long", {"uid": uid, "road": -1, "s": m.s[i0], "pos": m.pos[i0], "branch": uid,
			"end": "fork", "km": maxi(roundi(lb.x / 1000.0), 9)})
		return b
	var used := float(ctx.get_meta("branch_len", 0.0))
	if used + lb.x > MAX_TOTAL:
		_error(ctx, b, "branch_long", {"uid": uid, "road": -1, "s": m.s[i0], "pos": m.pos[i0], "branch": uid,
			"end": "fork", "km": roundi((used + lb.x) / 1000.0)}, 0, "total")
		return b
	ctx.set_meta("branch_len", used + lb.x)
	var t := LevelRoad.build(pts, ctx.styles, false, opts)
	if t.n < 4:
		_error(ctx, b, "branch_nose", {"uid": uid, "road": -1, "s": m.s[i0], "pos": m.pos[i0], "branch": uid, "end": "fork"}, 0, "never")
		return b
	b.road = t
	_end_frames(m, t, b)
	b.zones = {"fork": _junction(m, t, b, "fork"), "merge": _junction(m, t, b, "merge")}
	_cut_sides(m, t, b)
	for i in b.main_junction:
		(b.main_set as Dictionary)[i] = true
	return b


## The fork / merge end point: on the main road's edge, the doc's first / last point's width,
## style, grip and barriers (its segment is the fork's own).
static func _end_point(uid: int, p: Vector3, like: Dictionary) -> Dictionary:
	var out := {"uid": uid, "pos": p, "width": float(like.get("width", 14.0)), "style": str(like.get("style", "asphalt"))}
	for k in ["grip", "barrier_l", "barrier_r", "tunnel_h"]:
		if like.get(k) != null:
			out[k] = like[k]
	return out


## The end samples' frames are the main road's own (fork and merge).
static func _end_frames(m: LevelRoad, t: LevelRoad, b: Dictionary) -> void:
	if t == null or t.n < 2:
		return
	for pr: Vector2i in [Vector2i(0, int(b.i0)), Vector2i(t.n - 1, int(b.i1))]:
		var k := pr.x
		var i := pr.y
		t.fwd[k] = m.fwd[i]
		t.right[k] = m.right[i]
		t.up[k] = m.up[i]
		t.flat_right[k] = m.flat_right[i]
		if t.bank.size() == t.n and m.bank.size() == m.n:
			t.bank[k] = m.bank[i]


## Main sample of an anchor rounded to an exported one (every third), so its lap metres are exact.
static func _resolve(m: LevelRoad, a: Dictionary) -> int:
	var i := m.anchor_i(a)
	return mini(3 * roundi(i / 3.0), 3 * ((m.n - 1) / 3))


static func _side_of(m: LevelRoad, i: int, p: Vector3) -> int:
	return 1 if (p - m.pos[i]).dot(m.flat_right[i]) > 0.0 else -1


## The phantom point beside end p for its neighbour control point c: c mirrored about the main
## road's tangent line at sample i through p, so the curve leaves / joins along that tangent.
static func _phantom(m: LevelRoad, p: Vector3, c: Vector3, i: int) -> Vector3:
	var f := m.fwd[i]
	var d := c - p
	return p - (f * (2.0 * f.dot(d)) - d)


## Main samples a .. b - 1 (wrapped) moved `lat` across.
static func _shifted(m: LevelRoad, a: int, b: int, lat: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in range(a, b):
		var w := m.wrap(j)
		out.append(m.pos[w] + m.right[w] * lat)
	return out


## Sample nearest p in plan within `window` samples of hint.
static func _nearest(m: LevelRoad, p: Vector3, hint: int, window: int) -> int:
	var best := m.wrap(hint)
	var bd := INF
	for k in range(-window, window + 1):
		var j := m.wrap(hint + k)
		var q := m.pos[j]
		var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d < bd:
			bd = d
			best = j
	return best


## Height of the main road's surface (its plane at sample i, carried on past its edge) under the
## plan point p.
static func _main_y(m: LevelRoad, i: int, p: Vector3) -> float:
	var d := p - m.pos[i]
	var f := m.fwd[i]
	var r := m.right[i]
	var fl := maxf(Vector2(f.x, f.z).length(), 1e-9)
	var rl := maxf(Vector2(r.x, r.z).length(), 1e-9)
	var along := (d.x * f.x + d.z * f.z) / fl
	var lat := (d.x * r.x + d.z * r.z) / rl
	return m.pos[i].y + along * f.y / fl + lat * r.y / rl


## Branch._follow as a LevelRoad follow hook (called on the race sampling and on the mesh road,
## before frames): where the branch's road still overlaps the main road in plan it lies on the
## main road's surface; beyond it eases back to its own heights over max(20, |offset| / 0.08) m.
class _Follow:
	extends RefCounted
	var m: LevelRoad
	var i0 := 0
	var i1 := 0
	var side0 := 1
	var side1 := 1
	## end -> [largest move, u from, u to, ease] (the race sampling's)
	var moved := {}

	func _init(main: LevelRoad, a: int, b: int, s0: int, s1: int) -> void:
		m = main
		i0 = a
		i1 = b
		side0 = s0
		side1 = s1

	func apply(t: LevelRoad) -> void:
		var total := PackedFloat32Array()
		total.resize(t.n)
		for end in ["fork", "merge"]:
			var pairs := _overlap(t, end)
			if pairs.is_empty():
				continue
			var off := PackedFloat32Array()
			off.resize(t.n)
			var big := 0.0
			for pr in pairs:
				off[pr.x] = LevelBranches._main_y(m, pr.y, t.pos[pr.x]) - t.pos[pr.x].y
				big = maxf(big, absf(off[pr.x]))
			var k_last: int = pairs[-1].x
			var ease := maxf(LevelBranches.FOLLOW_EASE, absf(off[k_last]) / LevelBranches.FOLLOW_GRADE)
			var dir := 1 if end == "fork" else -1
			var k := k_last + dir
			while k >= 0 and k < t.n:
				if t.gap[k] == 1:
					break
				var d := absf(t.s[k] - t.s[k_last])
				off[k] = off[k_last] * (1.0 - smoothstep(0.0, ease, d))
				k += dir
			for q in t.n:
				total[q] += off[q]
			moved[end] = [big, t.s[mini(pairs[0].x, k_last)], t.s[maxi(pairs[0].x, k_last)], ease]
		for q in t.n:
			var p := t.pos[q]
			p.y += total[q]
			t.pos[q] = p

	## (branch sample, main sample) pairs from one end while the roads overlap in plan, up to a jump.
	func _overlap(t: LevelRoad, end: String) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var fork := end == "fork"
		var side := side0 if fork else side1
		var i := i0 if fork else i1
		for q in t.n:
			var k := q if fork else t.n - 1 - q
			if t.gap[k] == 1:
				break
			i = LevelBranches._nearest(m, t.pos[k], i, 30)
			var lat := (t.pos[k] - m.pos[i]).dot(m.flat_right[i]) * side
			if lat - t.width[k] * 0.5 - m.width[i] * 0.5 >= 0.0:
				break
			out.append(Vector2i(k, i))
		return out


# ---------------------------------------------------------------- internals: junctions

## Metres between the road edges at a nose: both side treatments side by side and a metre; -1
## where either road is a kind no junction may meet (no gap nose then, only a height one).
static func _gore_gap(m: LevelRoad, i: int, side: int, t: LevelRoad, k: int) -> float:
	if not (m.kind(i) in JUNCTION_KINDS) or not (t.kind(k) in JUNCTION_KINDS):
		return -1.0
	return m.treatment(i, side) + t.treatment(k, -side) + 1.0


## One end's shared stretch (Branch._junction), walking from the fork (or back from the merge):
## per branch sample the main sample abreast, the edge gap and the height apart; k_sep = the first
## gap > 0; the nose = the first sample where gap >= the gore gap or |dy| > 2.5. Flags the
## branch's junction samples (the main road's are kept in b.main_junction until the lint passes)
## and clips its inner edge onto the main road's where it still lies on it.
static func _junction(m: LevelRoad, t: LevelRoad, b: Dictionary, end: String) -> Dictionary:
	var fork := end == "fork"
	var side: int = b.side0 if fork else b.side1
	var i: int = b.i0 if fork else b.i1
	var gore := _gore_gap(m, i, side, t, 0 if fork else t.n - 1)
	var z := {"side": side, "gore": gore, "k_sep": -1, "k_nose": -1, "i_nose": -1, "walk": []}
	var mj: PackedInt32Array = b.main_junction
	for q in t.n:
		var k := q if fork else t.n - 1 - q
		i = _nearest(m, t.pos[k], i, 30)
		var lat := (t.pos[k] - m.pos[i]).dot(m.flat_right[i]) * side
		var gp := lat - t.width[k] * 0.5 - m.width[i] * 0.5
		var dy := t.pos[k].y - m.pos[i].y
		if z.k_sep < 0 and gp > 0.0:
			z.k_sep = k
		if (gore >= 0.0 and gp >= gore) or absf(dy) > NOSE_DY:
			z.k_nose = k
			z.i_nose = i
			break
		t.junction[k] = 1
		mj.append(i)
		(z.walk as Array).append([k, i, gp, lat, dy])
		if gp < 0.0 and absf(dy) < SNAP_DY:
			var hit := _on_edge(m, t, i, side, k)
			if not hit.is_empty():
				t.clip_in[k] = hit[0]
				t.clip_side[k] = 0 if side > 0 else 1
				(b.trim_seg as Dictionary)[k] = [hit[1], hit[2], hit[3]]
	b.main_junction = mj
	return z


## Where branch sample k's cross-section (along its right) crosses the main road's edge on `side`
## near main sample i: [lateral along t.right, main sample j0, u along j0..j0+1, the point], or [].
static func _on_edge(m: LevelRoad, t: LevelRoad, i: int, side: int, k: int) -> Array:
	var c := t.pos[k]
	var r := t.right[k]
	var best := []
	for j in range(i - 4, i + 4):
		var j0 := m.wrap(j)
		var j1 := m.wrap(j + 1)
		if j1 == j0:
			continue
		var a := m.pos[j0] + m.right[j0] * (side * m.width[j0] * 0.5)
		var e := m.pos[j1] + m.right[j1] * (side * m.width[j1] * 0.5) - a
		var det := e.x * r.z - r.x * e.z
		if absf(det) < 1e-9:
			continue
		var w := a - c
		var sl := (e.x * w.z - w.x * e.z) / det
		var u := (r.x * w.z - w.x * r.z) / det
		if u >= -1e-6 and u <= 1.0 + 1e-6 and (best.is_empty() or absf(sl) < absf(float(best[0]))):
			var uc := clampf(u, 0.0, 1.0)
			best = [sl, j0, uc, a + e * uc]
	return best


## Side treatments left out over the shared stretches (Branch._cut_sides): the main road's on the
## branch's side from the fork to the nose and from the merge nose to the merge (kept in
## b.main_side_off until the lint passes), the branch's on its inner side.
static func _cut_sides(m: LevelRoad, t: LevelRoad, b: Dictionary) -> void:
	var mso: PackedInt32Array = b.main_side_off
	for end in ["fork", "merge"]:
		var z: Dictionary = b.zones[end]
		if z.k_nose < 0:
			continue
		var side: int = z.side
		var col_m := (side + 1) / 2
		var col_b := (1 - side) / 2
		if end == "fork":
			for d in range(1, posmod(int(z.i_nose) - int(b.i0), m.n)):
				mso.append(m.wrap(b.i0 + d) * 2 + col_m)
			for k in int(z.k_nose):
				t.side_off[k * 2 + col_b] = 1
		else:
			for d in range(1, posmod(int(b.i1) - int(z.i_nose), m.n)):
				mso.append(m.wrap(int(z.i_nose) + d) * 2 + col_m)
			for k in range(int(z.k_nose) + 1, t.n):
				t.side_off[k * 2 + col_b] = 1
	b.main_side_off = mso


## Branch sample of a nose (the end sample when the walk found none).
static func _nose_k(b: Dictionary, end: String) -> int:
	var t: LevelRoad = b.road
	var z: Dictionary = b.zones.get(end, {})
	if z.is_empty() or int(z.k_nose) < 0:
		return 0 if end == "fork" else t.n - 1
	return int(z.k_nose)


## Main sample abreast of a nose (the fork / merge sample when the walk found none).
static func _nose_i(b: Dictionary, end: String) -> int:
	var z: Dictionary = b.zones.get(end, {})
	if z.is_empty() or int(z.i_nose) < 0:
		return int(b.i0) if end == "fork" else int(b.i1)
	return int(z.i_nose)


# ---------------------------------------------------------------- internals: the early lint

## The rules known after the junction walk (3.6 #11-12; track_gen.validate's branch part): range
## and order, noses 15-70 m, kind / see-saw / tunnel, jumps, bank, radius, centre crossing, outer
## edge on each shared stretch (the first problem per end), and the branch's own tightest bend.
static func _early_lint(ctx: LevelContext, b: Dictionary) -> void:
	var m := ctx.main
	var t: LevelRoad = b.road
	var n := m.n
	var uid: int = b.uid
	var f0 := float(b.i0) / n
	var f1 := float(b.i1) / n
	if not (f0 > LAP_MIN and f0 < LAP_MAX and f1 > LAP_MIN and f1 < LAP_MAX):
		var bad_end := "fork" if not (f0 > LAP_MIN and f0 < LAP_MAX) else "merge"
		var bi: int = b.i0 if bad_end == "fork" else b.i1
		_error(ctx, b, "branch_range", {"uid": uid, "road": -1, "s": m.s[bi], "pos": m.pos[bi], "branch": uid, "end": bad_end})
	if int(b.i1) <= int(b.i0):
		_error(ctx, b, "branch_order", {"uid": uid, "road": -1, "s": m.s[b.i1], "pos": m.pos[b.i1], "branch": uid, "end": "merge"})
	for end in ["fork", "merge"]:
		var z: Dictionary = b.zones[end]
		var ei: int = b.i0 if end == "fork" else b.i1
		var where := {"uid": uid, "road": -1, "s": m.s[ei], "pos": m.pos[ei], "branch": uid, "end": end}
		if int(z.k_nose) < 0:
			_error(ctx, b, "branch_nose", where, 0, "never")
		else:
			var kn := int(z.k_nose)
			var u := t.s[kn] if end == "fork" else t.length - t.s[kn]
			if u > NOSE_MAX or u < NOSE_MIN:
				var w2 := where.duplicate()
				w2.road = uid
				w2.s = t.s[kn]
				w2.pos = t.pos[kn]
				_error(ctx, b, "branch_nose", w2, roundi(u), "" if end == "fork" else "merge")
		var walk: Array = z.walk
		var lim := mini(walk.size(), int(NOSE_MAX / maxf(t.step, 0.01)))
		for q in lim:
			var w: Array = walk[q]
			var k: int = w[0]
			var i: int = w[1]
			var lat: float = w[3]
			var code := ""
			if not (m.kind(i) in JUNCTION_KINDS) or m.seesaw[i] == 1 or (m.skip.size() == n and m.skip[i] == 1):
				code = "branch_kind"
			elif t.kind(k) == "tunnel" or t.seesaw[k] == 1:
				code = "branch_kind"
			elif t.gap[k] == 1 or m.gap[i] == 1:
				code = "branch_jump"
			elif absf(m.right[i].y) > MAX_BANK:
				code = "branch_bank"
			elif absf(m.curv[i]) > 1.0 / MIN_RADIUS + 1e-6:
				code = "branch_radius"
			elif lat < -CROSS_EPS:
				code = "branch_cross"
			elif lat + t.width[k] * 0.5 < m.width[i] * 0.5 - 0.05:
				code = "branch_edge"
			if code != "":
				_error(ctx, b, code, {"uid": uid, "road": -1, "s": m.s[i], "pos": m.pos[i], "branch": uid,
					"end": end, "u": t.s[k]})
				break
	for k in t.n:
		if t.gap[k] == 1:
			continue
		var c := absf(t.curv[k])
		var need := t.width[k] * 0.5 + t.treatment(k, 1 if t.curv[k] > 0.0 else -1) + 2.0
		if c * need > 1.0:
			_error(ctx, b, "branch_tight", {"uid": uid, "road": uid, "s": t.s[k], "pos": t.pos[k], "branch": uid,
				"point": _point_at(b, k)})
			break


## The doc point uid that owns branch sample k's segment (the fork end's is the branch uid).
static func _point_at(b: Dictionary, k: int) -> int:
	var t: LevelRoad = b.road
	var pts: Array = b.pts
	var si := clampi(t.seg[k], 0, pts.size() - 1)
	return int(pts[si].get("uid", 0))


## Files a branch_* error with its text (LevelValidate's when it has one, else 1.8's here) and
## fix id; `variant` picks the merge / never wording of branch_nose.
static func _error(ctx: LevelContext, b: Dictionary, code: String, where: Dictionary, metres := 0, variant := "") -> void:
	(b.errors as Array).append(code)
	if ctx.report == null:
		return
	var name := str(b.name)
	var text := ""
	var args := {"name": name, "m": metres, "args": [name, metres]}
	for k in where:
		if not args.has(k):
			args[k] = where[k]
	if variant == "":
		text = LevelValidate.text(code, args)
	if text == "" or text.contains("%s") or text.contains("%d"):
		var key := code if variant == "" else "%s_%s" % [code, variant]
		text = str(TEXTS.get(key, TEXTS.get(code, code))).format(args)
	var fix := str(LevelValidate.FIXES.get(code, ""))
	where["name"] = name
	ctx.report.error(code, text, where, fix)


# ---------------------------------------------------------------- internals: gores

static func _gore(ctx: LevelContext, m: LevelRoad, b: Dictionary, end: String) -> void:
	var t: LevelRoad = b.road
	var z: Dictionary = b.zones[end]
	if float(z.gore) < 0.0 or int(z.k_nose) < 0:
		return
	var fork := end == "fork"
	var side: int = z.side
	var k_nose: int = z.k_nose
	var i_nose: int = z.i_nose
	var k_sep: int = z.k_sep if int(z.k_sep) >= 0 else k_nose
	var k_t := k_sep - 1 if fork else k_sep + 1
	var ts: Dictionary = b.trim_seg
	if not ts.has(k_t):
		return
	var j0: int = ts[k_t][0]
	var p0: Vector3 = ts[k_t][2]
	var span := posmod(i_nose - j0, m.n) if fork else posmod(j0 - i_nose, m.n)
	if span > m.n / 2:
		return
	var inner := PackedVector3Array()
	for k in range(mini(k_sep, k_nose), maxi(k_sep, k_nose) + 1):
		inner.append(t.pos[k] + t.right[k] * (-side * t.width[k] * 0.5))
	var A := PackedVector3Array()
	var B := PackedVector3Array()
	if fork:
		A.append(p0)
		for d in range(1, span + 1):
			var j := m.wrap(j0 + d)
			A.append(m.pos[j] + m.right[j] * (side * m.width[j] * 0.5))
		B.append(p0)
		B.append_array(inner)
	else:
		for d in span + 1:
			var j := m.wrap(i_nose + d)
			A.append(m.pos[j] + m.right[j] * (side * m.width[j] * 0.5))
		A.append(p0)
		B.append_array(inner)
		B.append(p0)
	var st := m.style_at(i_nose)
	var mat := str(st.get("road", LevelStyles.FALLBACK_MAT))
	var group := t.group_name(t.group_of(t.seg[k_nose]))
	var rk: int = b.uid
	var P := A.duplicate()
	P.append_array(B)
	var ax := Vector3(m.fwd[i_nose].x, 0.0, m.fwd[i_nose].z)
	var ay := m.flat_right[i_nose]
	var uv := []
	for p in P:
		uv.append(Vector2((p - p0).dot(ax) / 3.0, (p - p0).dot(ay) / 3.0))
	var tris := _zipper(A, B)
	var up := Vector3.UP
	for tr: Vector3i in tris:
		var a := P[tr.x]
		var bb := P[tr.y]
		var c := P[tr.z]
		if (bb - a).cross(c - a).length() <= 1e-6:
			continue
		ctx.meshes.tri("road", mat, a, bb, c, up, [uv[tr.x], uv[tr.y], uv[tr.z]], rk, group)
	# the nose's edge down below the ground (or the deck's underside), and under a deck the gore's
	# own underside
	var na := A[A.size() - 1] if fork else A[0]
	var nb := B[B.size() - 1] if fork else B[0]
	var deck := m.kind(i_nose) == "bridge"
	var depth := float(st.get("skirt_h", 1.6)) if deck else 0.6
	var side_mat := str(st.get("skirt", mat)) if deck else mat
	var low := minf(na.y, nb.y) - depth
	var w := na.distance_to(nb) / 4.0
	var hgt := (maxf(na.y, nb.y) - low) / 4.0
	ctx.meshes.quad("side", side_mat, [na, nb, Vector3(nb.x, low, nb.z), Vector3(na.x, low, na.z)],
		m.fwd[i_nose] * (1.0 if fork else -1.0), [Vector2(0, 0), Vector2(w, 0), Vector2(w, hgt), Vector2(0, hgt)], rk, group)
	if deck:
		for tr: Vector3i in tris:
			var a := P[tr.x] - up * depth
			var bb := P[tr.y] - up * depth
			var c := P[tr.z] - up * depth
			if (bb - a).cross(c - a).length() <= 1e-6:
				continue
			ctx.meshes.tri("side", side_mat, a, bb, c, -up, [uv[tr.x], uv[tr.y], uv[tr.z]], rk, group)


## Triangles (index triples into A + B) between two polylines walked side by side, each advancing
## by its share of its own plan length (track_gen._zipper).
static func _zipper(A: PackedVector3Array, B: PackedVector3Array) -> Array[Vector3i]:
	var ta := _fracs(A)
	var tb := _fracs(B)
	var na := A.size()
	var nb := B.size()
	var out: Array[Vector3i] = []
	var i := 0
	var j := 0
	while i < na - 1 or j < nb - 1:
		if j == nb - 1 or (i < na - 1 and ta[i + 1] <= tb[j + 1]):
			out.append(Vector3i(i, i + 1, na + j))
			i += 1
		else:
			out.append(Vector3i(i, na + j + 1, na + j))
			j += 1
	return out


static func _fracs(P: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(P.size())
	var acc := 0.0
	for q in range(1, P.size()):
		acc += Vector2(P[q].x - P[q - 1].x, P[q].z - P[q - 1].z).length()
		out[q] = acc
	for q in P.size():
		out[q] = out[q] / maxf(acc, 1e-9)
	return out


# ---------------------------------------------------------------- internals: export

## The main loop as the game samples it (the exported path; branches.LapPath).
static func _lap(m: LevelRoad) -> Dictionary:
	var c := PackedVector3Array()
	var f := PackedVector3Array()
	var i := 0
	while i < m.n:
		c.append(m.pos[i])
		f.append(m.fwd[i])
		i += 3
	return {"c": c, "f": f, "n": c.size(), "length": m.length, "step": m.length / maxf(c.size(), 1)}


## TrackPath.closest: the exported sample nearest p around hint (height counts double, every
## sample away from the hint costs a little); `ahead` widens the search forward. [i, k]
static func _lap_closest(lap: Dictionary, p: Vector3, hint: int, ahead: int) -> Vector2i:
	var c: PackedVector3Array = lap.c
	var n: int = lap.n
	var step: float = lap.step
	var best := Vector2i(posmod(hint, n), 0)
	var bd := INF
	for k in range(WINDOW.x, maxi(WINDOW.y, ahead + 1)):
		var i := posmod(hint + k, n)
		var dv := p - c[i]
		var d := dv.x * dv.x + dv.z * dv.z + 4.0 * dv.y * dv.y + absi(k) * step * 0.5
		if d < bd:
			bd = d
			best = Vector2i(i, k)
	return best


## TrackPath.progress: lap metres of p near exported sample i.
static func _lap_progress(lap: Dictionary, p: Vector3, i: int) -> float:
	var c: PackedVector3Array = lap.c
	var f: PackedVector3Array = lap.f
	var n: int = lap.n
	var step: float = lap.step
	var length: float = lap.length
	i = posmod(i, n)
	var d := (p - c[i]).dot(f[i])
	var s_m := i * step + d
	var j := posmod(i + (1 if d >= 0.0 else -1), n)
	var dj := (p - c[j]).dot(f[j])
	if d >= 0.0 and 0.0 > dj:
		s_m = i * step + step * d / (d - dj)
	elif d < 0.0 and 0.0 <= dj:
		s_m = i * step - step * d / (d - dj)
	return fposmod(s_m, length)


## branches.s_main: lap metres per exported branch sample, monotone fork_s .. merge_s; the game's
## own progress up to the fork nose, from the merge nose and along steady runs beside the main
## road, a monotone cubic (Fritsch-Carlson rates) in between.
static func _s_main(lap: Dictionary, pts: PackedVector3Array, near: PackedByteArray, fork_i: int, merge_i: int, nose0: int, nose1: int) -> PackedFloat32Array:
	var mcount := pts.size()
	var step_l: float = lap.step
	var length: float = lap.length
	var fork_s := fork_i * step_l
	var merge_s := merge_i * step_l
	var proj := PackedFloat64Array()
	proj.resize(mcount)
	proj.fill(NAN)
	var hint := fork_i
	for k in mcount:
		if near[k] == 0:
			continue
		var ck := _lap_closest(lap, pts[k], hint, merge_i - hint + 12)
		var s_m := _lap_progress(lap, pts[k], ck.x)
		proj[k] = fork_s + fposmod(s_m - fork_s + length * 0.5, length) - length * 0.5
		hint = maxi(hint, ck.x)
	var step := pts[0].distance_to(pts[1]) if mcount > 1 else 1.0
	step = maxf(step, 1e-6)
	var keep := PackedByteArray()
	keep.resize(mcount)
	for k in mcount:
		if k <= nose0 or k >= nose1:
			keep[k] = 1
	var steady := PackedByteArray()
	steady.resize(mcount)
	for k in range(1, mcount):
		var rate := (proj[k] - proj[k - 1]) / step
		steady[k] = 1 if (not is_nan(rate) and rate > 0.25 and rate < 3.0) else 0
	var k := nose0 + 1
	while k < nose1:
		if steady[k] == 0:
			k += 1
			continue
		var e := k
		while e < nose1 and steady[e] == 1:
			e += 1
		if (e - k) * step >= 30.0:
			for q in range(k + 1, e - 1):
				keep[q] = 1
		k = e
	for q in mcount:
		if keep[q] == 0:
			proj[q] = NAN
	proj[0] = fork_s
	proj[mcount - 1] = merge_s
	var out := proj.duplicate()
	var anchors := PackedInt32Array()
	for q in mcount:
		if not is_nan(proj[q]):
			anchors.append(q)
	for q in anchors.size() - 1:
		var a := anchors[q]
		var b := anchors[q + 1]
		if b - a < 2:
			continue
		var span := (b - a) * step
		var sec := (proj[b] - proj[a]) / span
		var ra := sec
		if a > 0 and not is_nan(proj[a - 1]):
			ra = (proj[a] - proj[a - 1]) / step
		var rb := sec
		if b < mcount - 1 and not is_nan(proj[b + 1]):
			rb = (proj[b + 1] - proj[b]) / step
		var top := 3.0 * maxf(sec, 0.0)
		ra = clampf(ra, 0.0, top)
		rb = clampf(rb, 0.0, top)
		for x_i in b - a + 1:
			var x := float(x_i) / (b - a)
			out[a + x_i] = (2 * x * x * x - 3 * x * x + 1) * proj[a] + (x * x * x - 2 * x * x + x) * span * ra \
				+ (3 * x * x - 2 * x * x * x) * proj[b] + (x * x * x - x * x) * span * rb
	var res := PackedFloat32Array()
	res.resize(mcount)
	var run := -INF
	for q in mcount:
		run = maxf(run, out[q])
		res[q] = snappedf(clampf(run, fork_s, merge_s), 0.01)
	res[0] = snappedf(fork_s, 0.01)
	res[mcount - 1] = snappedf(merge_s, 0.01)
	return res


## The branch's jumps: [first sample, end sample, gap m, lift, ramp, drop, launch speed].
static func _jumps(ctx: LevelContext, b: Dictionary) -> Array:
	var t: LevelRoad = b.road
	var pts: Array = b.pts
	var zones := _gravity_zones(ctx, b)
	var out := []
	for g in t.gaps:
		var a := g.x
		var e := g.y
		var ci := clampi(t.seg[a], 0, pts.size() - 1)
		var gd = pts[ci].get("gap")
		var lift := 1.8
		var ramp := 16.0
		if gd is Dictionary:
			lift = clampf(float(gd.get("lift", 1.8)), 0.0, 20.0)
			ramp = clampf(float(gd.get("ramp", 16.0)), 0.0, 200.0)
		var gap := (e - a + 1) * t.step
		var drop := t.pos[maxi(a - 1, 0)].y - t.pos[mini(e, t.n - 1)].y
		var gv := G * gravity_scale(zones, t.s[a])
		out.append([a, e, gap, lift, ramp, drop, launch_speed(gap, lift, ramp, drop, gv)])
	return out


## The doc's low-gravity zones on this branch as {s0, s1, scale, ease} in branch metres.
static func _gravity_zones(ctx: LevelContext, b: Dictionary) -> Array:
	var out := []
	var t: LevelRoad = b.road
	var list = ctx.doc.data.get("zones", []) if ctx.doc != null else []
	if not (list is Array):
		return out
	for z in list:
		if not (z is Dictionary) or int(z.get("road", -1)) != int(b.uid):
			continue
		if not (z.get("a") is Dictionary) or not (z.get("b") is Dictionary):
			continue
		var s0 := t.anchor_s(z.a)
		var s1 := t.anchor_s(z.b)
		out.append({"s0": minf(s0, s1), "s1": maxf(s0, s1), "scale": float(z.get("scale", 0.4)), "ease": float(z.get("ease", 15.0))})
	return out


static func _entry(ctx: LevelContext, m: LevelRoad, lap: Dictionary, b: Dictionary) -> Dictionary:
	var t: LevelRoad = b.road
	var spec: Dictionary = b.spec
	var path := t.export_path()
	var ids := PackedVector3Array()
	var wb := PackedFloat32Array()
	var k := 0
	while k < t.n:
		ids.append(t.pos[k])
		wb.append(t.width[k])
		k += 3
	var fork_i: int = int(b.i0) / 3
	var merge_i: int = int(b.i1) / 3
	# near the main road: its stretch from the fork to the merge within 20 m (edge to edge)
	var near := PackedByteArray()
	near.resize(ids.size())
	var span_n := posmod(int(b.i1) - int(b.i0), m.n) + 41
	for q in ids.size():
		var p := ids[q]
		var best := INF
		for d in span_n:
			var j := m.wrap(int(b.i0) - 20 + d)
			var dd := Vector2(p.x - m.pos[j].x, p.z - m.pos[j].z).length() - (wb[q] + m.width[j]) * 0.5
			best = minf(best, dd)
			if best < NEAR:
				break
		near[q] = 1 if best < NEAR else 0
	var nose0 := _nose_k(b, "fork") / 3
	var nose1 := ceili(_nose_k(b, "merge") / 3.0)
	path["s_main"] = Array(_s_main(lap, ids, near, fork_i, merge_i, nose0, nose1))
	var jumps := _jumps(ctx, b)
	var need := 0.0
	for j in jumps:
		need = maxf(need, SPEED_MARGIN * float(j[6]))
	var lap_step: float = lap.step
	var fork_s := snappedf(fork_i * lap_step, 0.01)
	var merge_s := snappedf(merge_i * lap_step, 0.01)
	var ne: int = lap.n
	var ai = spec.get("ai", {})
	if not (ai is Dictionary):
		ai = {}
	return {"id": "b%d" % int(b.uid), "name": str(b.name), "index": int(b.index), "kind": str(spec.get("kind", "alt")),
		"fork_s": fork_s, "merge_s": merge_s, "fork_i": fork_i, "merge_i": merge_i,
		"fork_nose_u": snappedf(t.s[_nose_k(b, "fork")], 0.01), "merge_nose_u": snappedf(t.s[_nose_k(b, "merge")], 0.01),
		"fork_nose_i": posmod(roundi(_nose_i(b, "fork") / 3.0), ne), "merge_nose_i": posmod(roundi(_nose_i(b, "merge") / 3.0), ne),
		"side": int(b.side0), "merge_side": int(b.side1), "length": snappedf(t.length, 0.01),
		"saves": snappedf(merge_s - fork_s - t.length, 0.01), "need_speed": snappedf(need, 0.01),
		"need_boost": need > TOP_SPEED, "risk": float(spec.get("risk", 0.0)),
		"ai": {"take": float(ai.get("take", 0.5)), "min_skill": float(ai.get("min_skill", 0.0)), "commit": float(ai.get("commit", 40.0))},
		"respawn": str(spec.get("respawn", "before")), "retry_back": float(spec.get("retry_back", 45.0)),
		"offtrack": float(spec.get("offtrack", -1.0)), "merge_type": "gore", "in_hall": false, "path": path}


## Safe-drop's spatial hash of one road's samples: {cell, half (landing half-width per sample),
## map: Vector2i -> PackedInt32Array}.
static func _drop_grid(t: LevelRoad) -> Dictionary:
	var half := PackedFloat32Array()
	half.resize(t.n)
	var big := 4.0
	for j in t.n:
		var fl := 0.0
		if t.kind(j) == "tunnel":
			fl = float(t.style_at(j).get("wall_gap", 0.6))
		half[j] = t.width[j] * 0.5 + fl - 1.0
		big = maxf(big, half[j])
	var map := {}
	for j in t.n:
		var key := Vector2i(floori(t.pos[j].x / big), floori(t.pos[j].z / big))
		var arr: PackedInt32Array = map.get(key, PackedInt32Array())
		arr.append(j)
		map[key] = arr
	return {"cell": big, "half": half, "map": map}
