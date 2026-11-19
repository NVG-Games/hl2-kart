class_name LevelGeometry
## Road cross-sections of the four kinds (open, street, bridge, tunnel), barriers, colonly walls,
## the start line, centre dashes and every mask (3.5; ports of track_gen build_geometry, _open,
## _street, _bridge, _tunnel simplified, _barrier, _nose_cap). P2.
##
## Drawn on the road's mesh road (LevelRoad.mesh_road: every segment sampled on its own) with
## the dense road's masks mapped onto it, bucketed per segment group (8 segments), UVs per
## segment (each segment holds a whole number of repeats), so a group's meshes depend only on its
## own segments. Masks: `gap` (no surface, sides, barrier or colonly: runs stop at the kicker's
## lip), `skip` (no surface, no sides), `side_off` (no verge / kerb / barrier on that side),
## `clip_in` (+ `clip_side`: the surface starts at that lateral), `cut` (no barrier). A side run
## that starts or ends at a mask gets an end face (the nose cap).

const UP := Vector3.UP
## At most this many tunnel lights per compile: every tunnel's light_every widens in 2 m steps.
const LIGHT_CAP := 96
const LIGHT_WIDEN := 2.0
const LINE_W := 0.24
const DASH := 6.0
const PANEL := 2.0
const PANEL_W := 0.6
const FRAME := 1.5
const PILLAR_MAX := 80.0
const JERSEY := [Vector2(0.0, 0.0), Vector2(0.0, 0.25), Vector2(0.22, 0.55), Vector2(0.32, 1.05),
	Vector2(0.62, 1.05), Vector2(0.72, 0.55), Vector2(0.95, 0.25), Vector2(0.95, -1.0)]


## Empty groups = all.
static func build_road(ctx: LevelContext, r: LevelRoad, groups := PackedInt32Array()) -> void:
	if r == null or r.n < 2:
		return
	if ctx.meshes == null:
		ctx.meshes = LevelMeshSet.new()
	if ctx.light_extra < 0.0:
		var rs: Array = ctx.roads if not ctx.roads.is_empty() else [r]
		ctx.light_extra = light_extra(rs, ctx.report)
	var m := r.mesh_road()
	var want := {}
	for g in groups:
		want[g] = true
	var rk := r.key
	for si in m.styles.size():
		var st: Dictionary = m.styles[si]
		var k := str(st.get("kind", "open"))
		_surfaces(ctx, m, si, st, want, rk)
		if bool(st.get("lines", false)):
			_lines(ctx, m, si, st, want, rk)
		if k == "tunnel":
			_tunnel(ctx, m, si, st, want, rk)
			continue
		for sgn in [-1, 1]:
			_sides(ctx, m, si, st, k, sgn, want, rk)
		if k == "bridge":
			_underside(ctx, m, si, st, want, rk)
	for sgn in [-1, 1]:
		for b in m.barriers.size():
			_barriers(ctx, m, b, sgn, want, rk)


static func start_line(ctx: LevelContext) -> void:
	var r := ctx.main
	if r == null or r.n < 2 or not r.closed:
		return
	if ctx.meshes == null:
		ctx.meshes = LevelMeshSet.new()
	# at sample 0's spot, on the mesh road's frame there (local, so it keeps its hash)
	var fr := r.mesh_road().frame_at_u(r.u_of(0))
	var hw: float = fr[4] * 0.5
	var nrm: Vector3 = fr[2]
	var c: Vector3 = r.pos[0] + nrm * 0.03
	var rt: Vector3 = fr[1]
	var f: Vector3 = fr[3]
	var a0 := c - rt * hw - f * 1.5
	var a1 := c + rt * hw - f * 1.5
	var b1 := c + rt * hw + f * 1.5
	var b0 := c - rt * hw + f * 1.5
	ctx.meshes.quad("decal", LevelStyles.START_LINE_MAT, [a0, a1, b1, b0], nrm,
		[Vector2(0, 0), Vector2(0, 4), Vector2(1, 4), Vector2(1, 0)], LevelMeshSet.ROAD_OTHER,
		r.group_name(r.group_of(r.seg[0])))


## {} = none.
static func barrier_of(r: LevelRoad, i: int, side: int) -> Dictionary:
	var b := r.bar_r[i] if side >= 1 else r.bar_l[i]
	if b < 0 or b >= r.barriers.size():
		return {}
	return r.barriers[b]


# ---------------------------------------------------------------- additions (P2)

## Metres every tunnel style's light_every is widened by (2 m steps) so `roads` hold at most
## LIGHT_CAP tunnel lights; a warning `tunnel_lights` when it had to widen.
static func light_extra(roads: Array, report: LevelReport = null) -> float:
	var extra := 0.0
	var before := light_count(roads, 0.0)
	var count := before
	var guard := 0
	while count > LIGHT_CAP and guard < 1000:
		extra += LIGHT_WIDEN
		count = light_count(roads, extra)
		guard += 1
	if extra > 0.0 and report != null:
		report.warning("tunnel_lights", "The tunnels would have %d lights; they are spaced %d m wider to keep %d." % [before, int(extra), count])
	return extra


## The tunnel lights `roads` make with every light_every widened by `extra` metres.
static func light_count(roads: Array, extra: float) -> int:
	var count := 0
	for r in roads:
		if not (r is LevelRoad):
			continue
		var road: LevelRoad = r
		for k in road.segments():
			count += _seg_lights(road, k, extra)
	return count


static func _seg_lights(r: LevelRoad, k: int, extra: float) -> int:
	var st := r.seg_style(k)
	if str(st.get("kind", "")) != "tunnel" or str(st.get("light", "")) == "" or r.seg_seesaw(k):
		return 0
	var every := maxf(float(st.get("light_every", 8.0)), 2.0) + extra
	return maxi(1, roundi(r.seg_len[k] / every))


# ---------------------------------------------------------------- runs and pieces

## Runs of pred (trimmed of a trailing masked sample), clipped to a partial road's emit range.
static func _runs(m: LevelRoad, pred: Callable, with_gaps: bool, masked: Callable) -> Array:
	var out := []
	for ids in m.runs(pred, with_gaps):
		var run := ids
		if run.size() >= 2 and masked.call(run[run.size() - 1]):
			run = run.slice(0, run.size() - 1)
		if m.partial:
			var keep := PackedInt32Array()
			for i in run:
				if i >= m.emit_from and i <= m.emit_to:
					keep.append(i)
			run = keep
		if run.size() >= 2:
			out.append(run)
	return out


## A run split at segment-group boundaries (the first sample of a group closes the piece before
## it): [[ids, group index]], only the wanted groups.
static func _pieces(m: LevelRoad, run: PackedInt32Array, want: Dictionary) -> Array:
	var out := []
	var cur := -1
	var start := 0
	for q in run.size():
		var g := m.group_of(m.seg[run[q]])
		if cur == -1:
			cur = g
			start = q
			continue
		if g != cur:
			if q - start >= 1 and (want.is_empty() or want.has(cur)):
				out.append([run.slice(start, q + 1), cur])
			cur = g
			start = q
	if run.size() - start >= 2 and (want.is_empty() or want.has(cur)):
		out.append([run.slice(start), cur])
	return out


## V along a piece in repeats of `rep` metres, per segment: segment k holds repeats(k, rep)
## whole repeats, so a group's coordinates depend only on its own segments.
static func _vs(m: LevelRoad, ids: PackedInt32Array, rep: float, full := false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(ids.size())
	var base := 0.0
	var prev := m.seg[ids[0]]
	for q in ids.size():
		var i := ids[q]
		var k := m.seg[i]
		if q > 0 and k != prev:
			base += _reps(m, prev, rep, full)
			prev = k
		out[q] = base + m.segt[i] * _reps(m, k, rep, full)
	return out


static func _reps(m: LevelRoad, k: int, rep: float, full: bool) -> int:
	if full:
		var i := maxi(m.seg_first[k], 0)
		return m.repeats(k, m.width[i])
	return m.repeats(k, rep)


static func _gname(m: LevelRoad, g: int) -> String:
	return m.group_name(g)


static func _wanted(m: LevelRoad, i: int, want: Dictionary) -> bool:
	return want.is_empty() or want.has(m.group_of(m.seg[i]))


# ---------------------------------------------------------------- the surface and dashes

static func _surfaces(ctx: LevelContext, m: LevelRoad, si: int, st: Dictionary, want: Dictionary, rk: int) -> void:
	for gr in [0, 1]:
		var pred := func(i: int) -> bool: return m.style[i] == si and m.grip[i] == gr and m.skip[i] == 0
		var masked := func(i: int) -> bool: return m.skip[i] == 1
		for run: PackedInt32Array in _runs(m, pred, false, masked):
			for pc in _pieces(m, run, want):
				_surface(ctx, m, pc[0], _gname(m, pc[1]), st, gr == 1, rk)


static func _surface(ctx: LevelContext, m: LevelRoad, ids: PackedInt32Array, group: String, st: Dictionary, offroad: bool, rk: int) -> void:
	var kind := "verge" if offroad else "road"
	var mat := str(st.get("road", LevelStyles.FALLBACK_MAT))
	var full := str(st.get("road_u", "rep")) == "full"
	var rep := maxf(float(st.get("road_rep", 6.0)), 0.1)
	var v := _vs(m, ids, rep, full)
	var A := PackedVector3Array()
	var B := PackedVector3Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	var vv := PackedFloat32Array()
	var nn := PackedVector3Array()
	for q in ids.size():
		var i := ids[q]
		var hw := m.width[i] * 0.5
		var lo := -hw
		var hi := hw
		var c := m.clip_in[i]
		if not is_nan(c):
			if m.clip_side[i] == 1:
				hi = minf(hi, c)
			else:
				lo = maxf(lo, c)
		if hi - lo < 0.2:
			# hidden under the main road: flush what came before
			_flush_strip(ctx, kind, mat, A, B, ua, ub, vv, nn, rk, group)
			A = PackedVector3Array()
			B = PackedVector3Array()
			ua = PackedFloat32Array()
			ub = PackedFloat32Array()
			vv = PackedFloat32Array()
			nn = PackedVector3Array()
			continue
		A.append(m.surface(i, lo))
		B.append(m.surface(i, hi))
		if full:
			ua.append((lo + hw) / maxf(2.0 * hw, 0.01))
			ub.append((hi + hw) / maxf(2.0 * hw, 0.01))
		else:
			ua.append(lo / rep)
			ub.append(hi / rep)
		vv.append(v[q])
		nn.append(m.up[i])
	_flush_strip(ctx, kind, mat, A, B, ua, ub, vv, nn, rk, group)


static func _flush_strip(ctx: LevelContext, kind: String, mat: String, A: PackedVector3Array, B: PackedVector3Array, ua: PackedFloat32Array, ub: PackedFloat32Array, v: PackedFloat32Array, nn: PackedVector3Array, rk: int, group: String) -> void:
	if A.size() >= 2:
		ctx.meshes.strip(kind, mat, A, B, ua, ub, v, nn, nn, rk, group)


## Centre dashes: a 0.24 m decal strip, on for 6 m of every 12, the period fitted per segment.
static func _lines(ctx: LevelContext, m: LevelRoad, si: int, st: Dictionary, want: Dictionary, rk: int) -> void:
	var mat := str(st.get("lines_mat", LevelStyles.START_LINE_MAT))
	var pred := func(i: int) -> bool: return m.style[i] == si and m.skip[i] == 0 and is_nan(m.clip_in[i]) and m.junction[i] == 0
	var masked := func(i: int) -> bool: return m.skip[i] == 1 or not is_nan(m.clip_in[i]) or m.junction[i] == 1
	for run: PackedInt32Array in _runs(m, pred, false, masked):
		for pc in _pieces(m, run, want):
			var ids: PackedInt32Array = pc[0]
			var v := _vs(m, ids, 3.0)
			var on := PackedInt32Array()
			for q in ids.size():
				var i := ids[q]
				var k := m.seg[i]
				var per := maxi(1, roundi(m.seg_len[k] / (2.0 * DASH)))
				var ph := fposmod(m.segt[i] * per, 1.0)
				if m.segt[i] >= 1.0:
					ph = 0.0
				if ph < 0.5:
					on.append(q)
					continue
				_dash(ctx, m, ids, on, v, mat, rk, _gname(m, pc[1]))
				on = PackedInt32Array()
			_dash(ctx, m, ids, on, v, mat, rk, _gname(m, pc[1]))


static func _dash(ctx: LevelContext, m: LevelRoad, ids: PackedInt32Array, on: PackedInt32Array, v: PackedFloat32Array, mat: String, rk: int, group: String) -> void:
	if on.size() < 2:
		return
	var A := PackedVector3Array()
	var B := PackedVector3Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	var vv := PackedFloat32Array()
	var nn := PackedVector3Array()
	for q in on:
		var i := ids[q]
		A.append(m.surface(i, -LINE_W * 0.5, 0.02))
		B.append(m.surface(i, LINE_W * 0.5, 0.02))
		ua.append(0.0)
		ub.append(1.0)
		vv.append(v[q])
		nn.append(m.up[i])
	ctx.meshes.strip("decal", mat, A, B, ua, ub, vv, nn, nn, rk, group)


# ---------------------------------------------------------------- sides

static func _side_masked(m: LevelRoad, i: int, col: int) -> bool:
	return m.skip[i] == 1 or m.side_off[i * 2 + col] == 1 or m.gap[i] == 1


static func _sides(ctx: LevelContext, m: LevelRoad, si: int, st: Dictionary, k: String, sgn: int, want: Dictionary, rk: int) -> void:
	var col := 1 if sgn > 0 else 0
	var pred := func(i: int) -> bool: return m.style[i] == si and m.skip[i] == 0 and m.side_off[i * 2 + col] == 0
	var masked := func(i: int) -> bool: return m.skip[i] == 1 or m.side_off[i * 2 + col] == 1
	for run: PackedInt32Array in _runs(m, pred, false, masked):
		for pc in _pieces(m, run, want):
			var ids: PackedInt32Array = pc[0]
			var group := _gname(m, pc[1])
			match k:
				"street":
					_street(ctx, m, ids, st, sgn, rk, group)
				"bridge":
					_skirt(ctx, m, ids, st, sgn, rk, group)
				_:
					_open(ctx, m, ids, st, sgn, rk, group)
		if k == "bridge":
			continue
		# nose caps where the side starts or ends at a mask
		var first := run[0]
		var last := run[run.size() - 1]
		var before := first - 1
		var after := last + 1
		if m.closed:
			before = posmod(before, m.n)
			after = posmod(after, m.n)
		for end: int in [0, 1]:
			var i: int = first if end == 0 else last
			var nb: int = before if end == 0 else after
			if nb < 0 or nb >= m.n or m.style[nb] != si or not _side_masked(m, nb, col):
				continue
			if not _wanted(m, i, want):
				continue
			var pr := _profile(m, i, st, k, sgn)
			var depth := 0.4 + (float(st.get("curb_h", 0.16)) if k == "street" else 0.0)
			var mat := str(st.get("curb", "")) if k == "street" else str(st.get("verge", ""))
			_nose_cap(ctx, m, i, pr[0], pr[1], end, depth, mat, rk, _gname(m, m.group_of(m.seg[i])))


## The top of a side treatment across at sample i: [inner point, outer point].
static func _profile(m: LevelRoad, i: int, st: Dictionary, k: String, sgn: int) -> Array:
	var rf := m.flat_right[i] * sgn
	var E := m.surface(i, sgn * m.width[i] * 0.5)
	if k == "street":
		var e1 := E + UP * float(st.get("curb_h", 0.16))
		return [e1, e1 + rf * (0.3 + _walk(m, i, st, sgn))]
	var ki := _k_in(m, i, st, sgn)
	var dd := float(st.get("verge_drop", 0.27)) + absf(m.right[i].y) * 1.5
	return [E, E + rf * float(st.get("verge_w", 4.0)) * ki - UP * dd]


## The inside-bend squeeze of an open side (Trk.side_reach / _side_w): 1 = the full width.
static func _k_in(m: LevelRoad, i: int, st: Dictionary, sgn: int) -> float:
	var tw := maxf(m.treatment(i, 1 if sgn > 0 else 0), 0.01)
	var rr := m.reach(sgn, tw)[i]
	var w := tw if rr >= tw else clampf(rr, 0.0, tw)
	return clampf(w / tw, 0.0, 1.0)


## _k_in with the reach array looked up once per treatment width.
static func _k_in_fast(m: LevelRoad, i: int, col: int, sgn: int) -> float:
	var tw := maxf(m.treatment(i, col), 0.01)
	var rr := m.reach(sgn, tw)[i]
	if rr >= tw:
		return 1.0
	return clampf(rr / tw, 0.0, 1.0)


## A street's pavement width at sample i, narrowed in a bend too tight for it.
static func _walk(m: LevelRoad, i: int, st: Dictionary, sgn: int) -> float:
	var walk := float(st.get("walk", 4.0))
	var tw := m.treatment(i, 1 if sgn > 0 else 0)
	var extra := tw - walk
	var rr := m.reach(sgn, walk + extra)[i]
	return walk if rr >= walk + extra else clampf(rr - extra, 0.0, walk)


static func _open(ctx: LevelContext, m: LevelRoad, ids: PackedInt32Array, st: Dictionary, sgn: int, rk: int, group: String) -> void:
	var vw := float(st.get("verge_w", 4.0))
	var drop := float(st.get("verge_drop", 0.27))
	var mat := str(st.get("verge", LevelStyles.FALLBACK_MAT))
	var v := _vs(m, ids, 4.0)
	var E := PackedVector3Array()
	var O := PackedVector3Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	var nn := PackedVector3Array()
	var col := 1 if sgn > 0 else 0
	for q in ids.size():
		var i := ids[q]
		var ki := _k_in_fast(m, i, col, sgn)
		var e := m.surface(i, sgn * m.width[i] * 0.5)
		var o := e + m.flat_right[i] * (sgn * vw * ki) - UP * (drop + absf(m.right[i].y) * 1.5)
		E.append(e)
		O.append(o)
		ua.append(0.0)
		ub.append(vw * ki / 4.0)
		var nrm := (o - e).cross(m.fwd[i])
		if nrm.y < 0.0:
			nrm = -nrm
		nn.append(nrm.normalized() if nrm.length_squared() > 1e-12 else m.up[i])
	ctx.meshes.strip("verge", mat, E, O, ua, ub, v, nn, nn, rk, group)


static func _street(ctx: LevelContext, m: LevelRoad, ids: PackedInt32Array, st: Dictionary, sgn: int, rk: int, group: String) -> void:
	var curb := str(st.get("curb", LevelStyles.FALLBACK_MAT))
	var walk_mat := str(st.get("walk_mat", LevelStyles.FALLBACK_MAT))
	var curb_h := float(st.get("curb_h", 0.16))
	var v3 := _vs(m, ids, 3.0)
	var v4 := _vs(m, ids, 4.0)
	var e0 := PackedVector3Array()
	var e1 := PackedVector3Array()
	var e2 := PackedVector3Array()
	var e3 := PackedVector3Array()
	var e4 := PackedVector3Array()
	var inn := PackedVector3Array()
	var out := PackedVector3Array()
	var upn := PackedVector3Array()
	var z := PackedFloat32Array()
	var u06 := PackedFloat32Array()
	var u12 := PackedFloat32Array()
	var uw := PackedFloat32Array()
	var u1 := PackedFloat32Array()
	for q in ids.size():
		var i := ids[q]
		var rf := m.flat_right[i] * sgn
		var a := m.surface(i, sgn * m.width[i] * 0.5)
		var b := a + UP * curb_h
		var c := b + rf * 0.3
		var wk := _walk(m, i, st, sgn)
		var d := c + rf * wk
		e0.append(a)
		e1.append(b)
		e2.append(c)
		e3.append(d)
		e4.append(d - UP * 1.0)
		inn.append(-rf)
		out.append(rf)
		upn.append(UP)
		z.append(0.0)
		u06.append(0.06)
		u12.append(0.12)
		uw.append(wk / 4.0)
		u1.append(0.25)
	ctx.meshes.strip("side", curb, e0, e1, z, u06, v3, inn, inn, rk, group)
	ctx.meshes.strip("road", curb, e1, e2, u06, u12, v3, upn, upn, rk, group)
	ctx.meshes.strip("road", walk_mat, e2, e3, z, uw, v4, upn, upn, rk, group)
	ctx.meshes.strip("side", curb, e3, e4, z, u1, v3, out, out, rk, group)


static func _skirt(ctx: LevelContext, m: LevelRoad, ids: PackedInt32Array, st: Dictionary, sgn: int, rk: int, group: String) -> void:
	var mat := str(st.get("skirt", LevelStyles.FALLBACK_MAT))
	var sh := float(st.get("skirt_h", 1.5))
	var v := _vs(m, ids, 4.0)
	var E := PackedVector3Array()
	var L := PackedVector3Array()
	var nn := PackedVector3Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	for q in ids.size():
		var i := ids[q]
		var e := m.surface(i, sgn * m.width[i] * 0.5)
		E.append(e)
		L.append(e - UP * sh)
		nn.append(m.flat_right[i] * sgn)
		ua.append(0.0)
		ub.append(sh / 4.0)
	ctx.meshes.strip("side", mat, E, L, ua, ub, v, nn, nn, rk, group)


## A bridge's underside (facing down) and its pillars (every pillar_every, per segment, not on
## the first / last 2 samples of a run; none over a drop under 1 m or without ground).
static func _underside(ctx: LevelContext, m: LevelRoad, si: int, st: Dictionary, want: Dictionary, rk: int) -> void:
	var mat := str(st.get("skirt", LevelStyles.FALLBACK_MAT))
	var sh := float(st.get("skirt_h", 1.5))
	var pmat := str(st.get("pillar", ""))
	var every := maxf(float(st.get("pillar_every", 30.0)), 2.0)
	var ps := maxf(float(st.get("pillar_size", 2.4)), 0.1)
	var pred := func(i: int) -> bool: return m.style[i] == si and m.skip[i] == 0
	var masked := func(i: int) -> bool: return m.skip[i] == 1
	for run: PackedInt32Array in _runs(m, pred, false, masked):
		for pc in _pieces(m, run, want):
			var ids: PackedInt32Array = pc[0]
			var v := _vs(m, ids, 4.0)
			var A := PackedVector3Array()
			var B := PackedVector3Array()
			var nn := PackedVector3Array()
			var ua := PackedFloat32Array()
			var ub := PackedFloat32Array()
			for q in ids.size():
				var i := ids[q]
				var hw := m.width[i] * 0.5
				A.append(m.surface(i, -hw) - UP * sh)
				B.append(m.surface(i, hw) - UP * sh)
				nn.append(-UP)
				ua.append(0.0)
				ub.append(1.0)
			ctx.meshes.strip("side", mat, A, B, ua, ub, v, nn, nn, rk, _gname(m, pc[1]))
		if pmat == "":
			continue
		# pillars: per segment, at (q + 0.5) / count of its length
		var by_seg := {}
		for q in run.size():
			if q < 2 or q > run.size() - 3:
				continue
			var i := run[q]
			var k := m.seg[i]
			if m.style[i] != si:
				continue
			if not by_seg.has(k):
				by_seg[k] = []
			by_seg[k].append(i)
		for k in by_seg:
			var cnt := maxi(1, roundi(m.seg_len[k] / every))
			for c in cnt:
				var target := (c + 0.5) / cnt
				var best := -1
				var bd := INF
				for i in by_seg[k]:
					var d := absf(m.segt[i] - target)
					if d < bd:
						bd = d
						best = i
				if best < 0 or bd * m.seg_len[k] > 2.5 or not _wanted(m, best, want):
					continue
				_pillar(ctx, m, best, ps, sh, pmat, rk)


static func _pillar(ctx: LevelContext, m: LevelRoad, i: int, ps: float, sh: float, mat: String, rk: int) -> void:
	var hw := m.width[i] * 0.5
	var f := Vector3(m.fwd[i].x, 0.0, m.fwd[i].z)
	f = f.normalized() if f.length_squared() > 1e-12 else Vector3(0, 0, 1)
	var rf := m.flat_right[i]
	for sgn in [-1.0, 1.0]:
		var lat: float = sgn * maxf(hw - ps, 0.0)
		var top := m.surface(i, lat) - UP * sh
		var g := ctx.ground(top.x, top.z)
		if is_nan(g):
			continue
		var bottom := g - 0.5
		var h := minf(top.y - bottom, PILLAR_MAX)
		if top.y - g < 1.0 or h <= 0.0:
			continue
		var xf := Transform3D(Basis(rf, UP, f), Vector3(top.x, top.y - h * 0.5, top.z))
		ctx.meshes.box("side", mat, xf, Vector3(ps, h, ps), 2.0, rk, m.group_name(m.group_of(m.seg[i])))


## The end face of a side treatment at a mask: across its top from top_in to top_out, down to
## `depth` under the lower of them; end 0 faces back along the road, 1 on along it.
static func _nose_cap(ctx: LevelContext, m: LevelRoad, i: int, top_in: Vector3, top_out: Vector3, end: int, depth: float, mat: String, rk: int, group: String) -> void:
	if mat == "":
		mat = LevelStyles.FALLBACK_MAT
	var low := minf(top_in.y, top_out.y) - depth
	var a := Vector3(top_in.x, low, top_in.z)
	var b := Vector3(top_out.x, low, top_out.z)
	var w := top_in.distance_to(top_out) / 4.0
	var hgt := (maxf(top_in.y, top_out.y) - low) / 4.0
	ctx.meshes.quad("side", mat, [a, b, top_out, top_in], m.fwd[i] * (-1.0 if end == 0 else 1.0),
		[Vector2(0, hgt), Vector2(w, hgt), Vector2(w, 0), Vector2(0, 0)], rk, group)


# ---------------------------------------------------------------- tunnels

static func _tunnel(ctx: LevelContext, m: LevelRoad, si: int, st: Dictionary, want: Dictionary, rk: int) -> void:
	var wall := str(st.get("wall", LevelStyles.FALLBACK_MAT))
	var ceil_mat := str(st.get("ceil", LevelStyles.FALLBACK_MAT))
	var floor_mat := str(st.get("road", LevelStyles.FALLBACK_MAT))
	var light := str(st.get("light", ""))
	var wg := maxf(float(st.get("wall_gap", 0.6)), 0.0)
	var rep := 4.0
	var every := maxf(float(st.get("light_every", 8.0)), 2.0) + maxf(ctx.light_extra, 0.0)
	var pred := func(i: int) -> bool: return m.style[i] == si and m.skip[i] == 0
	var masked := func(i: int) -> bool: return m.skip[i] == 1
	for run: PackedInt32Array in _runs(m, pred, true, masked):
		for pc in _pieces(m, run, want):
			var ids: PackedInt32Array = pc[0]
			var group := _gname(m, pc[1])
			var v := _vs(m, ids, rep)
			var WL := PackedVector3Array()
			var WR := PackedVector3Array()
			var TL := PackedVector3Array()
			var TR := PackedVector3Array()
			var nl := PackedVector3Array()
			var nr := PackedVector3Array()
			var nd := PackedVector3Array()
			var z := PackedFloat32Array()
			var uh := PackedFloat32Array()
			var one := PackedFloat32Array()
			for q in ids.size():
				var i := ids[q]
				var hw := m.width[i] * 0.5 + wg
				var hgt := maxf(m.height[i], 2.0)
				var l := m.pos[i] - m.flat_right[i] * hw
				var r := m.pos[i] + m.flat_right[i] * hw
				WL.append(l)
				WR.append(r)
				TL.append(l + UP * hgt)
				TR.append(r + UP * hgt)
				nl.append(m.flat_right[i])
				nr.append(-m.flat_right[i])
				nd.append(-UP)
				z.append(0.0)
				uh.append(hgt / rep)
				one.append(2.0 * hw / rep)
			ctx.meshes.strip("walls", wall, WL, TL, z, uh, v, nl, nl, rk, group)
			ctx.meshes.strip("walls", wall, WR, TR, z, uh, v, nr, nr, rk, group)
			ctx.meshes.strip("ceil", ceil_mat, TL, TR, z, one, v, nd, nd, rk, group)
			# the floor between the road edge and the walls, broken over a jump
			if wg > 0.05:
				for sgn in [-1, 1]:
					_tunnel_floor(ctx, m, ids, v, wg, sgn, floor_mat, rk, group)
		# light panels and their lights, per segment
		if light != "":
			var by_seg := {}
			for i in run:
				if m.style[i] != si:
					continue
				var k := m.seg[i]
				if not by_seg.has(k):
					by_seg[k] = []
				by_seg[k].append(i)
			for k in by_seg:
				if m.seg_seesaw(k):
					continue
				var cnt := maxi(1, roundi(m.seg_len[k] / every))
				for c in cnt:
					var target := (c + 0.5) / cnt
					var best := -1
					var bd := INF
					for i in by_seg[k]:
						var d := absf(m.segt[i] - target)
						if d < bd:
							bd = d
							best = i
					if best < 0 or not _wanted(m, best, want):
						continue
					_light(ctx, m, best, st, light, wg, rk)
		# frames round the openings
		for end: int in [0, 1]:
			var i: int = run[0] if end == 0 else run[run.size() - 1]
			var nb: int = i - 1 if end == 0 else i + 1
			if m.closed:
				nb = posmod(nb, m.n)
			if nb >= 0 and nb < m.n and m.kind(nb) == "tunnel":
				continue
			if not _wanted(m, i, want):
				continue
			_portal(ctx, m, i, wg, wall, end, rk)


static func _tunnel_floor(ctx: LevelContext, m: LevelRoad, ids: PackedInt32Array, v: PackedFloat32Array, wg: float, sgn: int, mat: String, rk: int, group: String) -> void:
	var A := PackedVector3Array()
	var B := PackedVector3Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	var vv := PackedFloat32Array()
	var nn := PackedVector3Array()
	for q in ids.size():
		var i := ids[q]
		if m.gap[i] == 1:
			_flush_strip(ctx, "road", mat, A, B, ua, ub, vv, nn, rk, group)
			A = PackedVector3Array()
			B = PackedVector3Array()
			ua = PackedFloat32Array()
			ub = PackedFloat32Array()
			vv = PackedFloat32Array()
			nn = PackedVector3Array()
			continue
		var hw := m.width[i] * 0.5
		var e := m.surface(i, sgn * hw) - UP * 0.01
		A.append(e)
		B.append(e + m.flat_right[i] * sgn * wg)
		ua.append(hw / 4.0)
		ub.append((hw + wg) / 4.0)
		vv.append(v[q])
		nn.append(m.up[i])
	_flush_strip(ctx, "road", mat, A, B, ua, ub, vv, nn, rk, group)


static func _light(ctx: LevelContext, m: LevelRoad, i: int, st: Dictionary, mat: String, wg: float, rk: int) -> void:
	var hgt := maxf(m.height[i], 2.0)
	var f := Vector3(m.fwd[i].x, 0.0, m.fwd[i].z)
	f = f.normalized() if f.length_squared() > 1e-12 else Vector3(0, 0, 1)
	var rf := m.flat_right[i]
	var c := m.pos[i] + UP * (hgt - 0.02)
	var hl := PANEL * 0.5
	var hwp := PANEL_W * 0.5
	ctx.meshes.quad("glow", mat, [c - rf * hwp - f * hl, c + rf * hwp - f * hl, c + rf * hwp + f * hl, c - rf * hwp + f * hl],
		-UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], rk, m.group_name(m.group_of(m.seg[i])))
	var col = st.get("light_color", [1.0, 0.9, 0.75])
	var color := [1.0, 0.9, 0.75]
	if col is Array and (col as Array).size() >= 3:
		color = [float(col[0]), float(col[1]), float(col[2])]
	var lp := m.pos[i] + UP * (hgt - 0.4)
	ctx.tunnel_lights.append({"pos": [snappedf(lp.x, 0.001), snappedf(lp.y, 0.001), snappedf(lp.z, 0.001)],
		"color": color, "range": maxf(12.0, m.width[i] + 2.0 * wg), "energy": float(st.get("light_energy", 1.6))})


## A 1.5 m frame face round a tunnel opening (walls kind): both jambs and the lintel.
static func _portal(ctx: LevelContext, m: LevelRoad, i: int, wg: float, mat: String, end: int, rk: int) -> void:
	var hw := m.width[i] * 0.5 + wg
	var hgt := maxf(m.height[i], 2.0)
	var rf := m.flat_right[i]
	var f := Vector3(m.fwd[i].x, 0.0, m.fwd[i].z)
	f = f.normalized() if f.length_squared() > 1e-12 else Vector3(0, 0, 1)
	var nrm := f * (-1.0 if end == 0 else 1.0)
	var c := m.pos[i]
	var low := c.y - 0.5
	var top := c.y + hgt + FRAME
	var group := m.group_name(m.group_of(m.seg[i]))
	var rects := [[-(hw + FRAME), -hw, low, top], [hw, hw + FRAME, low, top], [-hw, hw, c.y + hgt, top]]
	for rc in rects:
		var a: Vector3 = c + rf * float(rc[0])
		var b: Vector3 = c + rf * float(rc[1])
		var p := [Vector3(a.x, rc[2], a.z), Vector3(b.x, rc[2], b.z), Vector3(b.x, rc[3], b.z), Vector3(a.x, rc[3], a.z)]
		var w := (float(rc[1]) - float(rc[0])) / 4.0
		var h := (float(rc[3]) - float(rc[2])) / 4.0
		ctx.meshes.quad("walls", mat, p, nrm, [Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0)], rk, group)


# ---------------------------------------------------------------- barriers

static func _barriers(ctx: LevelContext, m: LevelRoad, b: int, sgn: int, want: Dictionary, rk: int) -> void:
	var col := 1 if sgn > 0 else 0
	var bar: Dictionary = m.barriers[b]
	var pred := func(i: int) -> bool:
		var bi := m.bar_r[i] if col == 1 else m.bar_l[i]
		return bi == b and m.skip[i] == 0 and m.side_off[i * 2 + col] == 0 and m.cut[i] == 0 and m.kind(i) != "tunnel"
	var masked := func(i: int) -> bool: return m.skip[i] == 1 or m.side_off[i * 2 + col] == 1 or m.cut[i] == 1
	for run: PackedInt32Array in _runs(m, pred, false, masked):
		var pcs := _pieces(m, run, want)
		for p in pcs.size():
			var ids: PackedInt32Array = pcs[p][0]
			var base := PackedVector3Array()
			var rf := PackedVector3Array()
			for i in ids:
				base.append(_bar_base(m, i, sgn, bar))
				rf.append(m.flat_right[i] * sgn)
			var v := _vs(m, ids, maxf(float(bar.get("rep", 3.0)), 0.1))
			var open0: bool = ids[0] == run[0]
			var open1: bool = ids[ids.size() - 1] == run[run.size() - 1]
			if m.closed and run.size() == m.n + 1:
				open0 = false
				open1 = false
			_barrier(ctx, bar, base, rf, v, sgn, rk, _gname(m, pcs[p][1]), open0, open1)


## Where a barrier stands at sample i: open roads `off` past the edge (squeezed in a tight bend),
## streets at the pavement's back, bridges at the deck edge.
static func _bar_base(m: LevelRoad, i: int, sgn: int, bar: Dictionary) -> Vector3:
	var st := m.style_at(i)
	var k := m.kind(i)
	var rf := m.flat_right[i] * sgn
	var E := m.surface(i, sgn * m.width[i] * 0.5)
	match k:
		"street":
			return E + UP * float(st.get("curb_h", 0.16)) + rf * (0.3 + _walk(m, i, st, sgn))
		"bridge":
			return E
		_:
			return E + rf * float(bar.get("off", 0.2)) * _k_in_fast(m, i, 1 if sgn > 0 else 0, sgn)


## A barrier along a polyline: wall / fence / rail a box `thick` wide and h + 0.3 tall from 0.3 m
## under the base; jersey the 8-point profile; col_h above its top adds a one-sided colonly wall
## facing the road. cap0 / cap1 close the ends (a run's ends, not group seams).
static func _barrier(ctx: LevelContext, bar: Dictionary, base: PackedVector3Array, rf: PackedVector3Array, v: PackedFloat32Array, sgn: int, rk: int, group: String, cap0: bool, cap1: bool) -> void:
	var kind := str(bar.get("kind", "wall"))
	var h := float(bar.get("h", 1.0))
	var mat := str(bar.get("mat", LevelStyles.FALLBACK_MAT))
	var nn := base.size()
	var top := 1.05 if kind == "jersey" else h
	var inset := 0.32 if kind == "jersey" else 0.0
	var col_h := float(bar.get("col_h", 0.0))
	var inward := PackedVector3Array()
	var outward := PackedVector3Array()
	var upn := PackedVector3Array()
	for q in nn:
		inward.append(-rf[q])
		outward.append(rf[q])
		upn.append(UP)
	if col_h > top + 0.05:
		var lo := PackedVector3Array()
		var hi := PackedVector3Array()
		var z := PackedFloat32Array()
		var uh := PackedFloat32Array()
		for q in nn:
			var l := base[q] + rf[q] * inset
			lo.append(l + UP * top)
			hi.append(l + UP * col_h)
			z.append(0.0)
			uh.append((col_h - top) / 3.0)
		ctx.meshes.strip("colonly", "colonly", lo, hi, z, uh, v, inward, inward, rk, group)
	if kind == "jersey":
		var rings: Array = []
		for pt in JERSEY:
			var ring := PackedVector3Array()
			for q in nn:
				ring.append(base[q] + rf[q] * pt.x + UP * pt.y)
			rings.append(ring)
		var pu := [0.5]
		for k in range(1, JERSEY.size()):
			pu.append(pu[k - 1] + (JERSEY[k] - JERSEY[k - 1]).length() / 2.0)
		for k in JERSEY.size() - 1:
			var A: PackedVector3Array = rings[k]
			var B: PackedVector3Array = rings[k + 1]
			var ua := PackedFloat32Array()
			var ub := PackedFloat32Array()
			var vv := PackedFloat32Array()
			var na := PackedVector3Array()
			var d: Vector2 = JERSEY[k + 1] - JERSEY[k]
			for q in nn:
				ua.append(pu[k])
				ub.append(pu[k + 1])
				vv.append(v[q] * 0.75)
				# the profile's outward normal (away from the road at the faces, up at the top)
				var t2 := Vector2(d.y, -d.x).normalized()
				na.append((rf[q] * -t2.x + UP * -t2.y).normalized())
			ctx.meshes.strip("walls", mat, A, B, ua, ub, vv, na, na, rk, group)
		if nn > 1:
			for end: int in [0, 1]:
				if (end == 0 and not cap0) or (end == 1 and not cap1):
					continue
				var q := 0 if end == 0 else nn - 1
				var along := base[0] - base[1] if end == 0 else base[nn - 1] - base[nn - 2]
				var poly := []
				var uvp := []
				for k in JERSEY.size():
					poly.append((rings[k] as PackedVector3Array)[q])
					uvp.append(Vector2(JERSEY[k].x, -JERSEY[k].y))
				ctx.meshes.fan("walls", mat, poly, along.normalized(), uvp, rk, group, true)
		return
	var thick := float(bar.get("thick", 0.4 if kind == "wall" else 0.05))
	var rep := maxf(float(bar.get("rep", 3.0)), 0.1)
	var b_in := PackedVector3Array()
	var b_out := PackedVector3Array()
	var t_in := PackedVector3Array()
	var t_out := PackedVector3Array()
	var z := PackedFloat32Array()
	var uh := PackedFloat32Array()
	var ut := PackedFloat32Array()
	for q in nn:
		var bi := base[q] - UP * 0.3
		var bo := bi + rf[q] * thick
		b_in.append(bi)
		b_out.append(bo)
		t_in.append(bi + UP * (h + 0.3))
		t_out.append(bo + UP * (h + 0.3))
		z.append(0.0)
		uh.append((h + 0.3) / rep)
		ut.append(0.25)
	ctx.meshes.strip("walls", mat, b_in, t_in, z, uh, v, inward, inward, rk, group)
	ctx.meshes.strip("walls", mat, b_out, t_out, z, uh, v, outward, outward, rk, group)
	ctx.meshes.strip("walls", mat, t_in, t_out, z, ut, v, upn, upn, rk, group)
	if nn > 1:
		for end: int in [0, 1]:
			if (end == 0 and not cap0) or (end == 1 and not cap1):
				continue
			var q := 0 if end == 0 else nn - 1
			var along := base[0] - base[1] if end == 0 else base[nn - 1] - base[nn - 2]
			var w := thick / rep
			var hh := (h + 0.3) / rep
			ctx.meshes.quad("walls", mat, [b_in[q], b_out[q], t_out[q], t_in[q]], along.normalized(),
				[Vector2(0, hh), Vector2(w, hh), Vector2(w, 0), Vector2(0, 0)], rk, group)
