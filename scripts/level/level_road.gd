class_name LevelRoad
extends RefCounted
## Dense samples of one road (3.2): Bezier segments through the control points sampled every 2 m,
## frames, banking, widths, styles and barriers per side, gaps, masks, flat zones, anchors, segment
## groups, the racing line and the exported path TrackPath reads. A port of track_gen.Trk.
##
## Two samplings share this class. `build` is the race sampling: n = 3 * round(L / 6) on a loop
## (3k + 1 on an open road), uniform `step = L / n`, rotated so sample 0 is the start line; the
## path, the racing line, the carve, branches and gameplay data use it. `build_partial` (the drag
## preview) and `mesh_road()` (what LevelGeometry draws) sample each segment on its own (about
## 2 m, its own count), so a segment's samples depend only on its own curve: moving one point
## changes only the meshes of the segments it bends (3.5), and preview and bake draw the same road.

const STEP := 2.0
const SEG_GROUP := 8
## Points per segment when measuring arc length (as the generator).
const FLATTEN := 200
## A road is refused unsampled when length_bounds' upper bound is over this many times its cap,
## however short its estimate (only handles folded back on short segments get there).
const LONG_BOUND := 4.0
## Points per segment outside a partial road's window (lengths only).
const COARSE := 16
## The race sampling's most samples: 3 x this (a backstop; the compiler refuses a lap over 25 km
## before it is sampled, 6.9).
const MAX_THIRDS := 4000
## AUTO bank: clip(plan curvature x 120, +-0.15 rad), then 30 passes of (b[i-1] + 2 b[i] + b[i+1]) / 4.
const BANK_GAIN := 120.0
const BANK_AUTO := 0.15
const BANK_PASSES := 30
## Every bank is clamped to +-25 deg.
const BANK_MAX := 0.4363323129985824
## Outside a flat zone the AUTO bank eases back in over this many metres.
const FLAT_EASE := 20.0

var key := -1                       # -1 the main loop, else the branch's uid
var closed := true
var partial := false                # a preview road (build_partial)
var n := 0
var step := 2.0
var length := 0.0
var pos := PackedVector3Array()
var fwd := PackedVector3Array()
var right := PackedVector3Array()
var flat_right := PackedVector3Array()
var up := PackedVector3Array()
var width := PackedFloat32Array()
var curv := PackedFloat32Array()
var s := PackedFloat32Array()
var style := PackedInt32Array()     # index into styles
var styles: Array[Dictionary] = []
var seg := PackedInt32Array()       # owning point index
var segt := PackedFloat32Array()
var seg_first := PackedInt32Array() # first dense sample of each segment
var point_uids := PackedInt32Array()
var height := PackedFloat32Array()  # tunnel ceiling (0 = none)
var bar_l := PackedInt32Array()     # index into barriers (-1 none)
var bar_r := PackedInt32Array()
var barriers: Array[Dictionary] = []
var gap := PackedByteArray()
var pit := PackedByteArray()
var gaps: Array[Vector2i] = []
var side_off := PackedByteArray()   # 2 per sample (0 left, 1 right)
var clip_in := PackedFloat32Array() # NAN or the lateral where the surface starts
var cut := PackedByteArray()
var skip := PackedByteArray()
var dip := PackedFloat32Array()     # metres the ground must stay under the road (0 none)
var junction := PackedByteArray()
var line := PackedVector3Array()    # racing line (after step 7)
var speed := PackedFloat32Array()
var emit_from := 0                  # partial roads: the samples geometry is emitted for
var emit_to := -1

# ---------------------------------------------------------------- additions (P2)
var bank := PackedFloat32Array()      # final bank per sample (rad; > 0 lowers the right edge)
var bank_set := PackedByteArray()     # 1 where an explicit point bank takes part
var grip := PackedByteArray()         # 1 = off-road grip (the surface mesh is a verge)
var seesaw := PackedByteArray()       # 1 on a see-saw stretch: kind bridge, skip, no barriers, no pillars
var clip_side := PackedByteArray()    # the edge clip_in moves: 0 the left (surface clip_in..+w/2), 1 the right (-w/2..clip_in)
var lift := PackedFloat32Array()      # the kicker's lift per sample (already in pos.y)
var line_off := PackedFloat32Array()  # racing line lateral offsets (LevelLine.apply)
var style_ids := PackedStringArray()  # the style id of each entry of styles
var seg_len := PackedFloat64Array()   # arc length of each segment
var seg_u := PackedFloat64Array()     # arc position of each segment's start on the curve (point 0 = 0)
var total := 0.0                      # arc length of the whole curve (= length on a full road)
var s_off := 0.0                      # arc position on the curve of this road's s = 0
var uniform := true                   # samples are i * step (build), else per segment
var src_closed := true                # the curve is a loop (a partial road is open, its curve may not be)
var n_own := 0                        # the sample count this road computed itself
var hinted := false                   # n came from opts.n_hint

var _pts: Array = []                  # the point dicts
var _P := PackedVector3Array()        # control point positions
var _hout := PackedVector3Array()
var _hin := PackedVector3Array()
var _flat: Array = []                 # per segment: PackedVector3Array of FLATTEN + 1 points
var _cum: Array = []                  # per segment: PackedFloat64Array cumulative arc
var _pt_style := PackedInt32Array()   # per point: index into styles
var _pt_bar := PackedInt32Array()     # per point: barrier index left, right (2 per point)
var _opts := {}
var _mesh: LevelRoad = null
var _treat := {}
var _reach := {}


## opts: start (anchor), n_hint (int), pre / post (Vector3 phantoms), pad_before / pad_after
## (PackedVector3Array main-road samples for the end frames), follow (Callable(road)), key (int),
## flat (Array of {a: anchor, before: float, after: float}: AUTO bank 0 there, eased 20 m),
## materials (Dictionary: a registry to check segment barrier materials against).
static func build(points: Array, styles: Dictionary, closed: bool, opts := {}) -> LevelRoad:
	var r := LevelRoad.new()
	r.closed = closed
	r.key = int(opts.get("key", -1))
	if not r._setup(points, styles, closed, opts):
		return r
	r._flatten(PackedInt32Array())
	if r.total < 0.01:
		r.n = 0
		return r
	r._sample_uniform(opts)
	r._finish(opts)
	return r


## Vector2(about, most) of the curve's arc length, without sampling it: `about` from COARSE chords
## per segment (a little under the true length), `most` an upper bound, each segment's control
## polygon |p0 -> p0 + out| + |-> p1 - in| + |-> p1| (handles as build makes them; opts: pre /
## post as build). Cheap, so a hostile road is refused before it costs anything (6.9).
static func length_bounds(points: Array, closed: bool, opts := {}) -> Vector2:
	var r := LevelRoad.new()
	r.src_closed = closed
	for p in points:
		if p is Dictionary:
			r._pts.append(p)
			r._P.append(_vec(p.get("pos", [0, 0, 0])))
	var np := r._P.size()
	if np < 2:
		return Vector2.ZERO
	r._handles(opts)
	var about := 0.0
	var most := 0.0
	for k in (np if closed else np - 1):
		var k1 := (k + 1) % np
		var p0 := r._P[k]
		var p1 := p0 + r._hout[k]
		var p3 := r._P[k1]
		var p2 := p3 - r._hin[k1]
		most += r._hout[k].length() + p1.distance_to(p2) + r._hin[k1].length()
		var ca := -p0 + p1 * 3.0 - p2 * 3.0 + p3
		var cb := p0 * 3.0 - p1 * 6.0 + p2 * 3.0
		var cc := (p1 - p0) * 3.0
		var last := p0
		for j in range(1, COARSE + 1):
			var tt := float(j) / COARSE
			var q := ((ca * tt + cb) * tt + cc) * tt + p0
			about += q.distance_to(last)
			last = q
	return Vector2(about, most)


## The upper bound of length_bounds.
static func poly_length(points: Array, closed: bool, opts := {}) -> float:
	return length_bounds(points, closed, opts).y


## The drag preview's road: segments first_seg - 1 .. last_seg + 1, each sampled on its own at
## len / max(1, round(len / 2)); emit_from / emit_to are the samples of first_seg..last_seg (the
## last one the end of last_seg); frames and banking inside this window only; never exported.
static func build_partial(points: Array, styles: Dictionary, closed: bool, first_seg: int, last_seg: int, opts := {}) -> LevelRoad:
	var r := LevelRoad.new()
	r.closed = false
	r.partial = true
	r.key = int(opts.get("key", -1))
	if not r._setup(points, styles, closed, opts):
		return r
	var ns := r._P.size() if closed else r._P.size() - 1
	var segs := PackedInt32Array()
	if closed:
		var a := posmod(first_seg, ns)
		var b := posmod(last_seg, ns)
		var span := posmod(b - a, ns) + 1
		var count := mini(span + 2, ns)
		var start := posmod(a - 1, ns) if span + 2 <= ns else a
		for q in count:
			segs.append(posmod(start + q, ns))
	else:
		var a := clampi(first_seg, 0, ns - 1)
		var b := clampi(last_seg, a, ns - 1)
		for k in range(maxi(a - 1, 0), mini(b + 1, ns - 1) + 1):
			segs.append(k)
	r._flatten(segs)
	if r.total < 0.01:
		r.n = 0
		return r
	r._sample_segments(segs, false)
	r._finish(opts)
	var f0 := posmod(first_seg, ns) if closed else clampi(first_seg, 0, ns - 1)
	var l0 := posmod(last_seg, ns) if closed else clampi(last_seg, f0, ns - 1)
	r.emit_from = maxi(r.seg_first[f0], 0)
	var nxt := (l0 + 1) % ns if closed else l0 + 1
	if nxt < ns and r.seg_first[nxt] > r.emit_from:
		r.emit_to = r.seg_first[nxt]
	else:
		r.emit_to = r.n - 1
	return r


func wrap(i: int) -> int:
	return _w(i)


func _w(i: int) -> int:
	if n <= 0:
		return 0
	return posmod(i, n) if closed else clampi(i, 0, n - 1)


## The sample nearest s_m metres along this road.
func idx(s_m: float) -> int:
	if n <= 0:
		return 0
	if uniform:
		if closed:
			return posmod(roundi(s_m / step), n)
		return clampi(roundi(s_m / step), 0, n - 1)
	if closed:
		s_m = fposmod(s_m, length)
	var j := s.bsearch(s_m)
	if j <= 0:
		return 0
	if j >= n:
		return 0 if closed and s_m - s[n - 1] > (length - s[n - 1]) * 0.5 else n - 1
	return j if s[j] - s_m < s_m - s[j - 1] else j - 1


## A point `lat` metres across sample i and `h` above it (on the banked frame).
func surface(i: int, lat: float, h := 0.0) -> Vector3:
	return pos[i] + right[i] * lat + up[i] * h


func kind(i: int) -> String:
	if seesaw.size() > i and seesaw[i] == 1:
		return "bridge"
	return str(styles[style[i]].get("kind", "open"))


func style_at(i: int) -> Dictionary:
	return styles[style[i]]


## Metres the side treatment takes beyond the road edge at sample i on one side (side <= 0 left),
## with the segment's barrier override in place of the style's.
func treatment(i: int, side: int) -> float:
	var b := bar_r[i] if side >= 1 else bar_l[i]
	var k := ((style[i] * 4096 + b + 1) << 1) | (1 if side >= 1 else 0)
	if _treat.has(k):
		return _treat[k]
	var st: Dictionary = styles[style[i]].duplicate()
	st["barrier_r" if side >= 1 else "barrier_l"] = barriers[b] if b >= 0 else null
	var t := LevelStyles.treatment(st, side)
	_treat[k] = t
	return t


## The closest sample to p; with a hint only `window` samples either side of it are searched.
func closest(p: Vector3, hint := -1, window := 30) -> int:
	var best := 0
	var bd := INF
	if n <= 0:
		return 0
	if hint < 0:
		for i in n:
			var d := p.distance_squared_to(pos[i])
			if d < bd:
				bd = d
				best = i
		return best
	for k in range(-window, window + 1):
		var i := hint + k
		if not closed and (i < 0 or i >= n):
			continue
		i = _w(i)
		var d := p.distance_squared_to(pos[i])
		if d < bd:
			bd = d
			best = i
	return best


## {i, pos, lat} of the banked strip under a ray (the nearest hit), or {}. Gaps and see-saw
## stretches are holes.
func ray_hit(from: Vector3, dir: Vector3) -> Dictionary:
	if n < 2 or dir.length_squared() < 1e-12:
		return {}
	dir = dir.normalized()
	var best_t := INF
	var out := {}
	var last := n if closed else n - 1
	for i in last:
		if gap[i] == 1 or skip[i] == 1:
			continue
		var j := _w(i + 1)
		var a := pos[i]
		var nrm := up[i]
		var den := dir.dot(nrm)
		if absf(den) < 1e-6:
			continue
		var t := (a - from).dot(nrm) / den
		if t <= 0.0 or t >= best_t:
			continue
		var q := from + dir * t
		var along := pos[j] - a
		var al := along.length()
		if al < 1e-6:
			continue
		var u := (q - a).dot(along) / (al * al)
		if u < -0.02 or u > 1.02:
			continue
		var w := width[i] + (width[j] - width[i]) * clampf(u, 0.0, 1.0)
		var lat := (q - a).dot(right[i])
		if absf(lat) > w * 0.5:
			continue
		best_t = t
		out = {"i": i if u < 0.5 else j, "pos": q, "lat": lat}
	return out


## Metres across the road of p at sample i (+ right).
func lateral(p: Vector3, i: int) -> float:
	return (p - pos[i]).dot(right[i])


## Metres along this road of an anchor {p: point uid, t: 0..1 by arc along its segment}.
func anchor_s(a: Dictionary) -> float:
	var u := _anchor_u(a)
	if is_nan(u):
		return 0.0
	return _own_s(u)


func anchor_i(a: Dictionary) -> int:
	return idx(anchor_s(a))


## The anchor of a spot s_m metres along this road.
func s_to_anchor(s_m: float) -> Dictionary:
	if seg_len.is_empty():
		return {}
	var u := s_off + s_m
	if src_closed:
		u = fposmod(u, total)
	else:
		u = clampf(u, 0.0, total)
	var k := clampi(seg_u.bsearch(u, false) - 1, 0, seg_len.size() - 1)
	var t := 0.0
	if seg_len[k] > 1e-9:
		t = clampf((u - seg_u[k]) / seg_len[k], 0.0, 1.0)
	return {"p": point_uids[k], "t": t}


## seg_index / SEG_GROUP
func group_of(seg_index: int) -> int:
	return seg_index / SEG_GROUP


## "g<first point uid>"
func group_name(group: int) -> String:
	var k := group * SEG_GROUP
	if k < 0 or k >= point_uids.size():
		return "g0"
	return "g%d" % point_uids[k]


## Index runs (wrapped round a loop) where pred(i) holds and the road exists. A run carries the
## next sample too, so strips join up, unless that sample is a jump gap (a run that ends at a
## kicker stops at its lip) or past an open road's end (track_gen.py:444-452).
func runs(pred: Callable, with_gaps := false) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	if n <= 0:
		return out
	var mask := PackedByteArray()
	mask.resize(n)
	var all := true
	var any := false
	for i in n:
		var ok: bool = pred.call(i) and (with_gaps or gap[i] == 0)
		mask[i] = 1 if ok else 0
		all = all and ok
		any = any or ok
	if not any:
		return out
	var bounds: Array[Vector2i] = []
	var i := 0
	while i < n:
		if mask[i] == 1:
			var j := i
			while j < n and mask[j] == 1:
				j += 1
			bounds.append(Vector2i(i, j))
			i = j
		else:
			i += 1
	if closed:
		if all:
			bounds = [Vector2i(0, n + 1)]
		elif bounds.size() >= 2 and bounds[0].x == 0 and bounds[-1].y == n:
			var last: Vector2i = bounds.pop_back()
			var first: Vector2i = bounds.pop_front()
			bounds.append(Vector2i(last.x, first.y + n))
		for b in bounds:
			var end := b.y
			if all or with_gaps or gap[b.y % n] == 0:
				end = b.y + 1
			if all:
				end = n + 1
			var ids := PackedInt32Array()
			for q in range(b.x, end):
				ids.append(q % n)
			out.append(ids)
	else:
		for b in bounds:
			var end := b.y + 1 if b.y < n and (with_gaps or gap[b.y] == 0) else b.y
			var ids := PackedInt32Array()
			for q in range(b.x, end):
				ids.append(q)
			out.append(ids)
	return out


## Plan radius (INF on a straight).
func radius_at(i: int) -> float:
	var c := absf(curv[i])
	return INF if c < 1e-7 else 1.0 / c


## TrackPath's dict (path_data): every third sample, `step = 3 * step` (a loop's exported step
## equals length / n_e exactly), positions 3 decimals, unit vectors 4.
func export_path() -> Dictionary:
	var center := []
	var ln := []
	var fw := []
	var rt := []
	var u := []
	var wd := []
	var sp := []
	var gp := []
	var pt := []
	var mg := []
	var th := []
	var has_line := line.size() == n
	var has_speed := speed.size() == n
	var i := 0
	while i < n:
		center.append(_r3(pos[i]))
		ln.append(_r3(line[i] if has_line else pos[i]))
		fw.append(_r4(fwd[i]))
		rt.append(_r4(right[i]))
		u.append(_r4(up[i]))
		wd.append(snappedf(width[i], 0.001))
		sp.append(snappedf(speed[i] if has_speed else float(styles[style[i]].get("vmax", 40.0)), 0.001))
		gp.append(int(gap[i]))
		pt.append(int(pit[i]))
		mg.append(0.0)
		th.append(kind(i))
		i += 3
	return {"closed": closed, "step": snappedf(3.0 * step, 0.000001), "length": snappedf(length, 0.001),
		"center": center, "line": ln, "fwd": fw, "right": rt, "up": u, "width": wd, "speed": sp,
		"gap": gp, "pit": pt, "mag": mg, "theme": th}


# ---------------------------------------------------------------- additions (P2)

## The road LevelGeometry draws: every segment sampled on its own (as build_partial), with this
## road's masks (cut, skip, side_off, clip_in, clip_side, junction, dip) mapped onto it by arc
## position. A partial road is its own mesh road. Built once, masks mapped on every call.
func mesh_road() -> LevelRoad:
	if partial or not uniform or n <= 0:
		return self
	if _mesh == null:
		var m := LevelRoad.new()
		m.closed = closed
		m.key = key
		m._share_curve(self)
		var segs := PackedInt32Array()
		for k in seg_len.size():
			segs.append(k)
		m._sample_segments(segs, closed)
		m._finish(_opts)
		m.emit_from = 0
		m.emit_to = m.n - 1
		_mesh = m
	_map_masks(_mesh)
	return _mesh


## The dense sample of this road at the curve's arc position u.
func sample_at_u(u: float) -> int:
	return idx(_own_s(u))


## [pos, right, up, fwd, width] at the curve's arc position u, interpolated between the two
## samples around it (the start line draws on the mesh road's frames this way).
func frame_at_u(u: float) -> Array:
	var i := sample_at_u(u)
	var du := u - u_of(i)
	if src_closed:
		du = wrapf(du, -total * 0.5, total * 0.5)
	var j := _w(i + 1) if du >= 0.0 else _w(i - 1)
	var d := absf(u_of(j) - u_of(i))
	if src_closed:
		d = minf(d, total - d)
	var f := clampf(absf(du) / d, 0.0, 1.0) if d > 1e-6 else 0.0
	return [pos[i].lerp(pos[j], f), right[i].lerp(right[j], f).normalized(), up[i].lerp(up[j], f).normalized(),
		fwd[i].lerp(fwd[j], f).normalized(), lerpf(width[i], width[j], f)]


## The arc position on the curve of sample i (from its segment, in doubles).
func u_of(i: int) -> float:
	var k := seg[i]
	return seg_u[k] + segt[i] * seg_len[k]


## Pit flags (3.2, compile step 6): a gap, or a side with no barrier whose ground (ground.call(x,
## z) at the edge + treatment + 2 m) lies more than 5 m below the road; a NAN ground (no terrain, a
## hole, outside the world) counts as below.
func mark_pits(ground: Callable) -> void:
	pit = gap.duplicate()
	for i in n:
		if pit[i] == 1:
			continue
		for side in [0, 1]:
			var b := bar_r[i] if side == 1 else bar_l[i]
			if b >= 0:
				continue
			var sgn := 1.0 if side == 1 else -1.0
			var q := pos[i] + right[i] * sgn * width[i] * 0.5 + flat_right[i] * sgn * (treatment(i, side) + 2.0)
			var g: float = ground.call(q.x, q.z)
			if is_nan(g) or g < pos[i].y - 5.0:
				pit[i] = 1
				break


## The side_reach squeeze (track_gen Trk.side_reach): per sample, how far past the edge (plan
## metres) a strip on side sgn may reach when it wants `beyond`; on the inside of a bend too tight
## for it 85 % of the room to the centre of curvature, eased.
func reach(sgn: int, beyond: float) -> PackedFloat32Array:
	var ck := Vector2(sgn, snappedf(beyond, 0.0001))
	if _reach.has(ck):
		return _reach[ck]
	var segr := PackedFloat32Array()
	segr.resize(n)
	for i in n:
		var j := _w(i + 1)
		var f := Vector2(fwd[i].x, fwd[i].z)
		f = f.normalized() if f.length_squared() > 1e-12 else Vector2(0, 1)
		var dp := pos[j] - pos[i]
		var ahead := dp.x * f.x + dp.z * f.y
		var df := flat_right[j] - flat_right[i]
		var turn := (df.x * f.x + df.z * f.y) * sgn
		segr[i] = 0.85 * ahead / maxf(-turn, 1e-9) if turn < -1e-9 else INF
	var out := PackedFloat32Array()
	out.resize(n)
	var room := PackedFloat32Array()
	room.resize(n)
	var tight := false
	for i in n:
		var pi := posmod(i - 1, n) if closed else maxi(i - 1, 0)
		room[i] = maxf(minf(segr[i], segr[pi]) - width[i] * 0.5, 0.0)
		out[i] = beyond
		if beyond > room[i]:
			tight = true
	if tight:
		for i in n:
			out[i] = minf(out[i], room[i])
		for _p in 3:
			var nxt := out.duplicate()
			for i in n:
				var a := out[posmod(i - 1, n)] if closed else out[maxi(i - 1, 0)]
				var b := out[posmod(i + 1, n)] if closed else out[mini(i + 1, n - 1)]
				nxt[i] = minf((a + 2.0 * out[i] + b) * 0.25, beyond)
			out = nxt
		for i in n:
			out[i] = minf(out[i], room[i])
	_reach[ck] = out
	return out


## The number of whole texture repeats segment k holds for `rep` metres a repeat (3.5).
func repeats(k: int, rep: float) -> int:
	return maxi(1, roundi(seg_len[k] / maxf(rep, 0.01)))


## The style of segment k (its first point's).
func seg_style(k: int) -> Dictionary:
	return styles[_pt_style[k]]


## Whether segment k is a see-saw stretch.
func seg_seesaw(k: int) -> bool:
	return bool(_pts[k].get("seesaw", false))


## The number of segments of the curve.
func segments() -> int:
	return seg_len.size()


# ---------------------------------------------------------------- internals

func _setup(points: Array, st_all: Dictionary, curve_closed: bool, opts: Dictionary) -> bool:
	_opts = opts
	src_closed = curve_closed
	_pts = []
	_P = PackedVector3Array()
	point_uids = PackedInt32Array()
	for p in points:
		if not (p is Dictionary):
			continue
		_pts.append(p)
		_P.append(_vec(p.get("pos", [0, 0, 0])))
		point_uids.append(int(p.get("uid", 0)))
	var np := _P.size()
	if np < 2 or (curve_closed and np < 3 and _P[0].distance_to(_P[1]) < 1e-6):
		n = 0
		return false
	# styles used, in order of first use
	var by_id := {}
	_pt_style = PackedInt32Array()
	_pt_bar = PackedInt32Array()
	var mats: Dictionary = opts.get("materials", {}) if opts.get("materials", {}) is Dictionary else {}
	var bar_ids := {}
	for k in np:
		var sid := str(_pts[k].get("style", "asphalt"))
		if not by_id.has(sid):
			by_id[sid] = styles.size()
			styles.append(_style_dict(st_all, sid))
			style_ids.append(sid)
		var si: int = by_id[sid]
		_pt_style.append(si)
		var st: Dictionary = styles[si]
		var see := bool(_pts[k].get("seesaw", false))
		for side in ["barrier_l", "barrier_r"]:
			var b = _pts[k].get(side)
			var full = null
			var bk := ""
			if b is Dictionary:
				full = _full_barrier(b, mats)
				bk = JSON.stringify(full, "", true) if full is Dictionary else ""
			else:
				full = st.get(side)
				bk = "%d|%s" % [si, side]
			if see or not (full is Dictionary) or str(full.get("kind", "wall")) == "none":
				_pt_bar.append(-1)
				continue
			if not bar_ids.has(bk):
				bar_ids[bk] = barriers.size()
				barriers.append(full)
			_pt_bar.append(bar_ids[bk])
	_handles(opts)
	return true


## Copies the curve of another road (points, handles, flattening, styles) without recomputing it.
func _share_curve(o: LevelRoad) -> void:
	_opts = o._opts
	src_closed = o.src_closed
	_pts = o._pts
	_P = o._P
	point_uids = o.point_uids
	styles = o.styles
	style_ids = o.style_ids
	barriers = o.barriers
	_pt_style = o._pt_style
	_pt_bar = o._pt_bar
	_hout = o._hout
	_hin = o._hin
	_flat = o._flat
	_cum = o._cum
	seg_len = o.seg_len
	seg_u = o.seg_u
	total = o.total


## AUTO handles (Blender's: dir = next - prev, a third of each chord) or the point's CUSTOM one.
func _handles(opts: Dictionary) -> void:
	var np := _P.size()
	_hout.resize(np)
	_hin.resize(np)
	for k in np:
		var prev: Vector3
		var next: Vector3
		if src_closed:
			prev = _P[posmod(k - 1, np)]
			next = _P[(k + 1) % np]
		else:
			if k > 0:
				prev = _P[k - 1]
			elif opts.get("pre") is Vector3:
				prev = opts.pre
			else:
				prev = _P[0] * 2.0 - _P[1]
			if k < np - 1:
				next = _P[k + 1]
			elif opts.get("post") is Vector3:
				next = opts.post
			else:
				next = _P[k] * 2.0 - _P[k - 1]
		var h = _pts[k].get("handle")
		var d := Vector3.ZERO
		if h is Dictionary and h.has("dir"):
			d = _vec(h.dir)
		if d.length_squared() > 1e-12:
			d = d.normalized()
			_hout[k] = d * clampf(float(h.get("out", 0.0)), 0.0, 200.0)
			_hin[k] = d * clampf(float(h.get("in", 0.0)), 0.0, 200.0)
		else:
			d = next - prev
			d = d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO
			_hout[k] = d * (next - _P[k]).length() / 3.0
			_hin[k] = d * (_P[k] - prev).length() / 3.0


## Each segment flattened at FLATTEN points (only the segments of `fine` when it is not empty,
## the others at COARSE: a partial road needs their lengths, not their shape), cumulative arc in
## doubles.
func _flatten(fine: PackedInt32Array) -> void:
	var np := _P.size()
	var ns := np if src_closed else np - 1
	var res := PackedInt32Array()
	res.resize(ns)
	res.fill(FLATTEN if fine.is_empty() else COARSE)
	for k in fine:
		res[k] = FLATTEN
	_flat = []
	_cum = []
	seg_len = PackedFloat64Array()
	seg_u = PackedFloat64Array()
	total = 0.0
	for k in ns:
		var k1 := (k + 1) % np
		var p0 := _P[k]
		var p1 := p0 + _hout[k]
		var p3 := _P[k1]
		var p2 := p3 - _hin[k1]
		var ca := -p0 + p1 * 3.0 - p2 * 3.0 + p3
		var cb := p0 * 3.0 - p1 * 6.0 + p2 * 3.0
		var cc := (p1 - p0) * 3.0
		var m := res[k]
		var pts := PackedVector3Array()
		pts.resize(m + 1)
		var cum := PackedFloat64Array()
		cum.resize(m + 1)
		var acc := 0.0
		var last := p0
		pts[0] = p0
		cum[0] = 0.0
		for j in range(1, m + 1):
			var tt := float(j) / m
			var q := ((ca * tt + cb) * tt + cc) * tt + p0
			var dx := float(q.x) - float(last.x)
			var dy := float(q.y) - float(last.y)
			var dz := float(q.z) - float(last.z)
			acc += sqrt(dx * dx + dy * dy + dz * dz)
			pts[j] = q
			cum[j] = acc
			last = q
		_flat.append(pts)
		_cum.append(cum)
		seg_u.append(total)
		seg_len.append(acc)
		total += acc


## The point `local` metres (arc) along segment k.
func _at(k: int, local: float) -> Vector3:
	var cum: PackedFloat64Array = _cum[k]
	var pts: PackedVector3Array = _flat[k]
	var m := cum.size() - 1
	if local <= 0.0:
		return pts[0]
	if local >= cum[m]:
		return pts[m]
	var j := clampi(cum.bsearch(local, false) - 1, 0, m - 1)
	var d := cum[j + 1] - cum[j]
	var f := 0.0 if d < 1e-12 else (local - cum[j]) / d
	return pts[j].lerp(pts[j + 1], f)


## The race sampling: uniform, n = 3 * round(L / 6) (+1 open), rotated to the start anchor.
func _sample_uniform(opts: Dictionary) -> void:
	uniform = true
	length = total
	var base := clampi(roundi(total / 6.0), 1, MAX_THIRDS)
	n_own = 3 * base if closed else 3 * base + 1
	n = n_own
	var hint := int(opts.get("n_hint", 0))
	if hint > 0 and hint != n_own and absi(hint - n_own) <= 3 and posmod(hint, 3) == (0 if closed else 1):
		n = hint
		hinted = true
	step = total / n if closed else total / maxf(n - 1, 1)
	s_off = 0.0
	if closed and opts.get("start") is Dictionary:
		var ua := _anchor_u(opts.start)
		if not is_nan(ua):
			s_off = posmod(roundi(ua / step), n) * step
	_alloc(n)
	for i in n:
		var u := s_off + i * step
		if closed:
			u = fposmod(u, total)
		else:
			u = minf(u, total)
		var k := clampi(seg_u.bsearch(u, false) - 1, 0, seg_len.size() - 1)
		var local := clampf(u - seg_u[k], 0.0, seg_len[k])
		pos[i] = _at(k, local)
		seg[i] = k
		segt[i] = 0.0 if seg_len[k] < 1e-9 else local / seg_len[k]
		s[i] = i * step
	_seg_firsts()


## The segment sampling (preview, mesh road): each segment of `segs` on its own at about 2 m;
## `loop` = the samples close round (all segments of a loop), else the window's end is a sample.
func _sample_segments(segs: PackedInt32Array, loop: bool) -> void:
	uniform = false
	var ks := PackedInt32Array()
	var ls := PackedFloat64Array()
	for k in segs:
		var L := seg_len[k]
		var m := maxi(1, roundi(L / STEP))
		var h := L / m
		for j in m:
			ks.append(k)
			ls.append(j * h)
	if not loop and not segs.is_empty():
		ks.append(segs[-1])
		ls.append(seg_len[segs[-1]])
	n = ks.size()
	n_own = n
	_alloc(n)
	var acc := 0.0
	for i in n:
		var k := ks[i]
		pos[i] = _at(k, ls[i])
		seg[i] = k
		segt[i] = 0.0 if seg_len[k] < 1e-9 else clampf(ls[i] / seg_len[k], 0.0, 1.0)
		if i > 0:
			var kp := ks[i - 1]
			acc += (ls[i] - ls[i - 1]) if kp == k else (seg_len[kp] - ls[i - 1]) + ls[i]
		s[i] = acc
	length = acc
	if loop and n > 0:
		length = acc + seg_len[ks[n - 1]] - ls[n - 1]
	step = length / maxf(n if loop else n - 1, 1)
	s_off = seg_u[segs[0]] if not segs.is_empty() else 0.0
	_seg_firsts()


func _alloc(count: int) -> void:
	pos.resize(count)
	seg.resize(count)
	segt.resize(count)
	s.resize(count)


func _seg_firsts() -> void:
	seg_first = PackedInt32Array()
	seg_first.resize(seg_len.size())
	seg_first.fill(-1)
	for i in n:
		var k := seg[i]
		if seg_first[k] < 0 or segt[i] < segt[seg_first[k]]:
			seg_first[k] = i


## Per-sample data, gaps, follow, frames and banking, empty masks.
func _finish(opts: Dictionary) -> void:
	_attrs()
	_apply_gaps()
	var follow = opts.get("follow")
	if follow is Callable and (follow as Callable).is_valid():
		(follow as Callable).call(self)
	_frames(opts)
	pit = gap.duplicate()
	side_off = PackedByteArray()
	side_off.resize(n * 2)
	clip_in = PackedFloat32Array()
	clip_in.resize(n)
	clip_in.fill(NAN)
	clip_side = PackedByteArray()
	clip_side.resize(n)
	cut = PackedByteArray()
	cut.resize(n)
	skip = seesaw.duplicate()
	dip = PackedFloat32Array()
	dip.resize(n)
	junction = PackedByteArray()
	junction.resize(n)
	emit_from = 0
	emit_to = n - 1


func _attrs() -> void:
	var np := _P.size()
	width.resize(n)
	style.resize(n)
	grip.resize(n)
	height.resize(n)
	bar_l.resize(n)
	bar_r.resize(n)
	seesaw.resize(n)
	gap.resize(n)
	gap.fill(0)
	lift.resize(n)
	lift.fill(0.0)
	var ph := PackedFloat32Array()
	ph.resize(np)
	var pw := PackedFloat32Array()
	pw.resize(np)
	var pg := PackedByteArray()
	pg.resize(np)
	var pk := PackedStringArray()
	pk.resize(np)
	var ps := PackedByteArray()
	ps.resize(np)
	for k in np:
		var st: Dictionary = styles[_pt_style[k]]
		pk[k] = str(st.get("kind", ""))
		ps[k] = 1 if bool(_pts[k].get("seesaw", false)) else 0
		pw[k] = clampf(float(_pts[k].get("width", 14.0)), 1.0, 200.0)
		var g = _pts[k].get("grip")
		var gs := str(g) if g != null else str(st.get("grip", "road"))
		pg[k] = 1 if gs == "offroad" else 0
		var hv = _pts[k].get("tunnel_h")
		if str(st.get("kind", "")) == "tunnel":
			ph[k] = float(hv) if hv != null else float(st.get("height", 7.5))
		else:
			ph[k] = 0.0
	for i in n:
		var k := seg[i]
		var k1 := (k + 1) % np
		var t := segt[i]
		var sm := t * t * (3.0 - 2.0 * t)
		width[i] = pw[k] + (pw[k1] - pw[k]) * sm
		style[i] = _pt_style[k]
		grip[i] = pg[k]
		var h1 := ph[k1] if pk[k1] == pk[k] else ph[k]
		height[i] = ph[k] + (h1 - ph[k]) * sm
		seesaw[i] = ps[k]
		bar_l[i] = _pt_bar[k * 2]
		bar_r[i] = _pt_bar[k * 2 + 1]


## Jumps (Trk._apply_gaps): samples of the segment within at * len +- len / 2 are gaps; the
## round(ramp / step) samples before the first rise by lift * u^2 (the kicker).
func _apply_gaps() -> void:
	gaps = []
	for k in seg_len.size():
		var gd = _pts[k].get("gap")
		if not (gd is Dictionary) or seg_first[k] < 0:
			continue
		var L := seg_len[k]
		var gl := clampf(float(gd.get("len", 12.0)), 0.5, 200.0)
		var at := clampf(float(gd.get("at", 0.5)), 0.0, 1.0)
		var lo := at * L - gl * 0.5
		var hi := at * L + gl * 0.5
		var ids := PackedInt32Array()
		var i := seg_first[k]
		var guard := 0
		while guard < n and seg[i] == k:
			var local := segt[i] * L
			if local >= lo and local <= hi:
				ids.append(i)
			elif local > hi:
				break
			var j := i + 1
			if j >= n:
				if not closed:
					break
				j = 0
			i = j
			guard += 1
		if ids.is_empty():
			continue
		for q in ids:
			gap[q] = 1
		var first := ids[0]
		var h := step
		if not uniform:
			h = L / maxi(1, roundi(L / STEP))
		var ramp := roundi(clampf(float(gd.get("ramp", 16.0)), 0.0, 200.0) / maxf(h, 0.01))
		var lf := clampf(float(gd.get("lift", 1.8)), 0.0, 20.0)
		for kc in ramp:
			var j := first - ramp + kc
			if not closed and j < 0:
				continue
			j = posmod(j, n)
			var u := float(kc + 1) / ramp
			var q := pos[j]
			q.y += lf * u * u
			pos[j] = q
			lift[j] += lf * u * u
		gaps.append(Vector2i(first, first + ids.size()))


## Frames (Trk._frames): forward, flat right, plan curvature, AUTO bank (smoothed), flat zones,
## explicit banks, the banked right and up.
func _frames(opts: Dictionary) -> void:
	var pb := PackedVector3Array()
	var pa := PackedVector3Array()
	if not closed:
		if opts.get("pad_before") is PackedVector3Array:
			pb = opts.pad_before
		if opts.get("pad_after") is PackedVector3Array:
			pa = opts.pad_after
	var off := pb.size()
	var NP := off + n + pa.size()
	var P := PackedVector3Array()
	P.resize(NP)
	for i in off:
		P[i] = pb[i]
	for i in n:
		P[off + i] = pos[i]
	for i in pa.size():
		P[off + n + i] = pa[i]
	var f := PackedVector3Array()
	f.resize(NP)
	var hx := PackedFloat32Array()
	hx.resize(NP)
	var hz := PackedFloat32Array()
	hz.resize(NP)
	for i in NP:
		var a: Vector3
		var b: Vector3
		if closed:
			a = P[posmod(i - 1, NP)]
			b = P[(i + 1) % NP]
		else:
			a = P[maxi(i - 1, 0)]
			b = P[mini(i + 1, NP - 1)]
		var d := b - a
		f[i] = d.normalized() if d.length_squared() > 1e-12 else Vector3(0, 0, 1)
		hx[i] = f[i].x
		hz[i] = f[i].z
	var cv := PackedFloat32Array()
	cv.resize(NP)
	var b0 := PackedFloat32Array()
	b0.resize(NP)
	var banked := PackedByteArray()
	banked.resize(styles.size())
	for q in styles.size():
		banked[q] = 1 if bool(styles[q].get("bank", false)) else 0
	for i in NP:
		var ia := posmod(i - 3, NP) if closed else maxi(i - 3, 0)
		var ib := (i + 3) % NP if closed else mini(i + 3, NP - 1)
		var cr := hx[ia] * hz[ib] - hz[ia] * hx[ib]
		var span := 6.0 * step
		if not uniform or not closed:
			span = _arc_between(P, ia, ib)
		cv[i] = cr / maxf(span, 1e-6)
		var ri := i - off
		if ri >= 0 and ri < n and banked[style[ri]] == 1 and seesaw[ri] == 0:
			b0[i] = clampf(cv[i] * BANK_GAIN, -BANK_AUTO, BANK_AUTO)
	for _p in BANK_PASSES:
		var nb := b0.duplicate()
		for i in NP:
			var a := b0[posmod(i - 1, NP)] if closed else b0[maxi(i - 1, 0)]
			var c := b0[(i + 1) % NP] if closed else b0[mini(i + 1, NP - 1)]
			nb[i] = (a + 2.0 * b0[i] + c) * 0.25
		b0 = nb
	fwd.resize(n)
	right.resize(n)
	flat_right.resize(n)
	up.resize(n)
	curv.resize(n)
	bank.resize(n)
	bank_set.resize(n)
	var scale := _flat_scale(opts.get("flat", []))
	var np := _P.size()
	for i in n:
		var fi := f[off + i]
		var fr := Vector3(-fi.z, 0.0, fi.x)
		fr = fr.normalized() if fr.length_squared() > 1e-12 else Vector3(1, 0, 0)
		var auto := b0[off + i] * scale[i]
		var k := seg[i]
		var k1 := (k + 1) % np
		var e0 = _pts[k].get("bank")
		var e1 = _pts[k1].get("bank")
		var b := auto
		bank_set[i] = 0
		if (e0 != null or e1 != null) and seesaw[i] == 0:
			var t := segt[i]
			var sm := t * t * (3.0 - 2.0 * t)
			var A := deg_to_rad(float(e0)) if e0 != null else auto
			var B := deg_to_rad(float(e1)) if e1 != null else auto
			b = A * (1.0 - sm) + B * sm
			bank_set[i] = 1
		b = clampf(b, -BANK_MAX, BANK_MAX)
		bank[i] = b
		var up0 := fr.cross(fi)
		var rb := fr * cos(b) - up0 * sin(b)
		fwd[i] = fi
		flat_right[i] = fr
		right[i] = rb
		up[i] = rb.cross(fi).normalized()
		curv[i] = cv[off + i]


## The chord length from P[ia] to P[ib] (forward, wrapping): local, so a per-segment road's
## curvature depends only on its neighbourhood.
func _arc_between(P: PackedVector3Array, ia: int, ib: int) -> float:
	var acc := 0.0
	var i := ia
	var guard := 0
	while i != ib and guard < P.size():
		var j := (i + 1) % P.size()
		acc += P[i].distance_to(P[j])
		i = j
		guard += 1
	return acc


## 1 - w per sample: w = 1 inside a flat zone, smoothstepping to 0 over FLAT_EASE metres outside.
func _flat_scale(zones: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(1.0)
	if not (zones is Array) or (zones as Array).is_empty():
		return out
	var ranges: Array[Vector2] = []
	for z in zones:
		if not (z is Dictionary) or not (z.get("a") is Dictionary):
			continue
		var u := _anchor_u(z.a)
		if is_nan(u):
			continue
		var c := _own_s(u)
		ranges.append(Vector2(c - maxf(float(z.get("before", 0.0)), 0.0), c + maxf(float(z.get("after", 0.0)), 0.0)))
	if ranges.is_empty():
		return out
	var loop := closed or (src_closed and partial)
	var period := total if partial else length
	for i in n:
		var w := 0.0
		for r in ranges:
			var d := 0.0
			if loop:
				var x := fposmod(s[i] - r.x, period)
				var spanl := r.y - r.x
				d = 0.0 if x <= spanl else minf(x - spanl, period - x)
			else:
				d = maxf(maxf(r.x - s[i], s[i] - r.y), 0.0)
			var wi := 1.0
			if d > 0.0:
				var t := clampf(d / FLAT_EASE, 0.0, 1.0)
				wi = 1.0 - t * t * (3.0 - 2.0 * t)
			w = maxf(w, wi)
		out[i] = 1.0 - w
	return out


## The arc position on the curve of an anchor, NAN when its point is not on this road.
func _anchor_u(a: Dictionary) -> float:
	var uid := int(a.get("p", -1))
	var k := -1
	for q in point_uids.size():
		if point_uids[q] == uid:
			k = q
			break
	if k < 0:
		return NAN
	var t := clampf(float(a.get("t", 0.0)), 0.0, 1.0)
	if k >= seg_len.size():
		return total
	return seg_u[k] + t * seg_len[k]


## A curve arc position as metres along this road.
func _own_s(u: float) -> float:
	if closed:
		return fposmod(u - s_off, length)
	if partial and src_closed:
		var d := fposmod(u - s_off, total)
		if d > length + (total - length) * 0.5:
			d -= total
		return d
	return u - s_off


## Copies this road's masks onto its mesh road by arc position.
func _map_masks(m: LevelRoad) -> void:
	for j in m.n:
		var i := sample_at_u(m.u_of(j))
		m.cut[j] = cut[i]
		m.skip[j] = 1 if (skip[i] == 1 or m.seesaw[j] == 1) else 0
		m.side_off[j * 2] = side_off[i * 2]
		m.side_off[j * 2 + 1] = side_off[i * 2 + 1]
		m.clip_in[j] = clip_in[i]
		m.clip_side[j] = clip_side[i]
		m.junction[j] = junction[i]
		m.dip[j] = dip[i]


func _style_dict(st_all: Dictionary, sid: String) -> Dictionary:
	if st_all.get(sid) is Dictionary:
		return st_all[sid]
	if st_all.get("asphalt") is Dictionary:
		return st_all["asphalt"]
	var presets := LevelStyles.resolve({}, {})
	return presets.get(sid, presets["asphalt"])


static func _full_barrier(b: Dictionary, mats: Dictionary) -> Variant:
	if str(b.get("kind", "wall")) == "none":
		return {"kind": "none"}
	var out: Dictionary = LevelStyles.BARRIER_BASE.duplicate(true)
	for k in b:
		out[k] = b[k]
	if not str(out.kind) in LevelStyles.BARRIER_KINDS:
		out.kind = "wall"
	if not mats.is_empty() and not mats.has(str(out.mat)):
		out.mat = LevelStyles.FALLBACK_MAT
	return out


static func _vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _r4(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
