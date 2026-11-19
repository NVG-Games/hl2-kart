extends RefCounted
## P2: roads, racing line and road geometry (spec 3.2, 3.3, 3.5) without content: sample counts
## and the exported path TrackPath reads, the start rotation, orthonormal frames, flat zones and
## explicit banks, gaps and kickers, synthetic masks (side_off, clip_in, cut, skip) each removing
## exactly their pieces, winding, segment-group names and hashes under a point move, the partial
## road's budget and agreement with the full build, the tunnel-light cap and the racing line.

const NEEDS_CONTENT := false

var styles := {}


func run(t: Node) -> void:
	styles = LevelStyles.resolve({}, {})
	_counts(t)
	_start(t)
	_frames(t)
	_flat_and_banks(t)
	_gaps(t)
	_masks(t)
	_winding(t)
	_groups(t)
	_partial(t)
	_lights(t)
	_line(t)
	_kinds(t)
	_misc(t)


## A context whose ground lies 20 m under the origin (bridge pillars).
class LowGround:
	extends LevelContext
	func ground(x: float, z: float) -> float:
		return -20.0


# ---------------------------------------------------------------- helpers

func _circle(radius: float, count: int, style_id := "asphalt", w := 14.0, uid0 := 1, hills := 0.0) -> Array:
	var pts := []
	for k in count:
		var a := TAU * k / count
		pts.append({"uid": uid0 + k, "pos": [radius * cos(a), hills * sin(a * 3.0), radius * sin(a)],
			"width": w, "style": style_id})
	return pts


## A wiggly loop (bends both ways, hills).
func _wiggle(count := 24) -> Array:
	var pts := []
	for k in count:
		var a := TAU * k / count
		var rr := 300.0 + 90.0 * sin(a * 3.0)
		pts.append({"uid": 100 + k, "pos": [rr * cos(a), 12.0 * sin(a * 2.0), rr * sin(a)],
			"width": 12.0 + 4.0 * cos(a * 2.0), "style": "asphalt"})
	return pts


## A straight open road along +z (right = -x, so lateral = -x and s = z).
func _straight(style_id: String, length := 400.0, w := 14.0) -> Array:
	var pts := []
	var count := int(length / 100.0) + 1
	for k in count:
		pts.append({"uid": 1 + k, "pos": [0.0, 0.0, k * 100.0], "width": w, "style": style_id})
	return pts


func _ctx(r: LevelRoad) -> LevelContext:
	var ctx := LevelContext.new()
	ctx.report = LevelReport.new()
	ctx.meshes = LevelMeshSet.new()
	ctx.main = r
	ctx.roads.append(r)
	return ctx


## [kind, material, a, b, c] per triangle of a mesh set.
func _tris(ms: LevelMeshSet) -> Array:
	var out := []
	for bk in ms.buckets():
		var v: PackedVector3Array = bk.v
		var idx: PackedInt32Array = bk.i
		for q in range(0, idx.size(), 3):
			out.append([bk.kind, bk.material, v[idx[q]], v[idx[q + 1]], v[idx[q + 2]]])
	return out


func _key(tr: Array) -> String:
	var c: Vector3 = (tr[2] + tr[3] + tr[4]) / 3.0
	return "%s|%s|%.2f|%.2f|%.2f" % [tr[0], tr[1], c.x, c.y, c.z]


func _centroid(tr: Array) -> Vector3:
	return (tr[2] + tr[3] + tr[4]) / 3.0


# ---------------------------------------------------------------- counts and the export

func _counts(t: Node) -> void:
	var r := LevelRoad.build(_wiggle(), styles, true, {})
	t.check(r.n > 100 and r.n % 3 == 0, "loop n %% 3 == 0 (n %d)" % r.n)
	t.near(r.step, r.length / r.n, 1e-6, "loop step = L / n")
	t.near(float(r.n) / 3.0, roundf(r.length / 6.0), 0.01, "loop n = 3 * round(L / 6)")
	var e := r.export_path()
	var ne: int = (e.center as Array).size()
	t.check(ne * 3 == r.n, "exported n_e = n / 3 (%d)" % ne)
	t.near(float(e.step), float(e.length) / ne, 1e-4, "exported step = length / n_e")
	var tp := TrackPath.new(e)
	t.check(tp.n == ne, "TrackPath loads the export (n %d)" % tp.n)
	t.near(tp.step, float(e.step), 1e-4, "TrackPath step == length / n_e")
	t.check(tp.closed, "TrackPath closed")
	for k in ["center", "line", "fwd", "right", "up", "width", "speed", "gap", "pit", "mag", "theme"]:
		t.check((e[k] as Array).size() == ne, "export %s has n_e entries" % k)
	t.check(JSON.parse_string(JSON.stringify(e)) is Dictionary, "export is JSON")
	var o := LevelRoad.build(_straight("asphalt", 500.0), styles, false, {})
	t.check(o.n % 3 == 1, "open road n = 3k + 1 (n %d)" % o.n)
	t.near(o.step * (o.n - 1), o.length, 1e-3, "open road ends on its last sample")
	var oe := o.export_path()
	t.check((oe.center as Array).size() == (o.n - 1) / 3 + 1, "open export ends on the last sample")
	var last: Array = (oe.center as Array)[-1]
	t.near(float(last[2]), 500.0, 0.01, "open export's last centre is the road's end")
	# bake hint
	var h := LevelRoad.build(_wiggle(), styles, true, {"n_hint": r.n + 3})
	t.check(h.n == r.n + 3 and h.hinted, "n_hint within one rounding step is used")
	var h2 := LevelRoad.build(_wiggle(), styles, true, {"n_hint": r.n + 30})
	t.check(h2.n == r.n and not h2.hinted, "a far n_hint is ignored")


func _start(t: Node) -> void:
	var pts := _wiggle()
	var a := {"p": pts[7].uid, "t": 0.3}
	var r := LevelRoad.build(pts, styles, true, {"start": a})
	var k := 7
	var want: Vector3 = r._at(k, 0.3 * r.seg_len[k])
	t.check(r.pos[0].distance_to(want) <= r.step * 0.5 + 0.01, "sample 0 sits at the start anchor (%.2f m)" % r.pos[0].distance_to(want))
	var sa := r.anchor_s(a)
	t.check(minf(sa, r.length - sa) <= r.step * 0.5 + 1e-3, "anchor_s(start) ~ 0 (%.3f)" % sa)
	t.near(r.s[1] - r.s[0], r.step, 1e-4, "s[i] = i * step")
	var b := r.s_to_anchor(123.0)
	t.near(r.anchor_s(b), 123.0, 0.01, "s_to_anchor / anchor_s round trip")
	t.check(r.anchor_i({"p": pts[3].uid, "t": 0.0}) == r.seg_first[3] or absi(r.anchor_i({"p": pts[3].uid, "t": 0.0}) - r.seg_first[3]) <= 1, "anchor_i of a point is its segment's first sample")
	var r0 := LevelRoad.build(pts, styles, true, {})
	t.check(r0.pos[0].distance_to(r0._P[0]) < 0.01, "no start anchor: sample 0 at point 0")


func _frames(t: Node) -> void:
	var pts := _wiggle()
	pts[5]["bank"] = 12.0
	pts[11]["bank"] = -20.0
	var r := LevelRoad.build(pts, styles, true, {})
	var bad := 0
	for i in r.n:
		var f := r.fwd[i]
		var rt := r.right[i]
		var u := r.up[i]
		if absf(f.length() - 1.0) > 1e-4 or absf(rt.length() - 1.0) > 1e-4 or absf(u.length() - 1.0) > 1e-4:
			bad += 1
		elif absf(f.dot(rt)) > 1e-4 or absf(f.dot(u)) > 1e-4 or absf(rt.dot(u)) > 1e-4:
			bad += 1
		elif u.y <= 0.0 or absf(r.flat_right[i].y) > 1e-6:
			bad += 1
	t.check(bad == 0, "frames orthonormal, up up, flat_right level (%d bad)" % bad)
	var m := r.mesh_road()
	bad = 0
	for i in m.n:
		if absf(m.fwd[i].dot(m.right[i])) > 1e-4 or absf(m.right[i].dot(m.up[i])) > 1e-4 or absf(m.up[i].length() - 1.0) > 1e-4:
			bad += 1
	t.check(bad == 0, "mesh road frames orthonormal")


func _flat_and_banks(t: Node) -> void:
	# a circle of 640 m radius: the AUTO bank saturates at 0.15 rad everywhere
	var pts := _circle(640.0, 64)
	var plain := LevelRoad.build(pts, styles, true, {})
	var mid := plain.n / 2
	t.near(absf(plain.bank[mid]), LevelRoad.BANK_AUTO, 1e-3, "AUTO bank on a tight-enough circle")
	var zone := {"a": {"p": pts[0].uid, "t": 0.0}, "before": 80.0, "after": 10.0}
	var r := LevelRoad.build(pts, styles, true, {"flat": [zone]})
	var worst_in := 0.0
	var worst_out := 0.0
	for i in r.n:
		var s_m := r.s[i]
		var d := s_m if s_m < r.length * 0.5 else s_m - r.length    # metres from the zone's anchor
		if d >= -80.0 and d <= 10.0:
			worst_in = maxf(worst_in, absf(r.bank[i]))
		elif d <= -105.0 or d >= 35.0:
			worst_out = maxf(worst_out, absf(r.bank[i] - plain.bank[i]))
	t.check(rad_to_deg(worst_in) < 0.5, "flat zone: |bank| < 0.5 deg inside (%.3f deg)" % rad_to_deg(worst_in))
	t.check(worst_out < 1e-5, "flat zone: the AUTO bank 25 m outside (%.6f)" % worst_out)
	# explicit banks win (also inside a flat zone)
	var pe := _circle(640.0, 64)
	pe[0]["bank"] = 10.0
	pe[30]["bank"] = -15.0
	var re := LevelRoad.build(pe, styles, true, {"flat": [zone]})
	var i0 := re.anchor_i({"p": pe[0].uid, "t": 0.0})
	var i30 := re.anchor_i({"p": pe[30].uid, "t": 0.0})
	t.near(rad_to_deg(re.bank[i0]), 10.0, 0.3, "explicit bank at its point wins over the flat zone")
	t.near(rad_to_deg(re.bank[i30]), -15.0, 0.3, "explicit bank at its point wins over AUTO")
	t.check(re.bank_set[i30] == 1 and plain.bank_set[i30] == 0, "bank_set marks explicit banks")
	var pc := _circle(640.0, 64)
	pc[10]["bank"] = 60.0
	var rc := LevelRoad.build(pc, styles, true, {})
	t.near(rad_to_deg(rc.bank[rc.anchor_i({"p": pc[10].uid, "t": 0.0})]), 25.0, 0.01, "banks clamp to 25 deg")
	# a banked road's right edge goes down for a positive bank
	var j := rc.anchor_i({"p": pc[10].uid, "t": 0.0})
	t.check(rc.right[j].y < 0.0, "a positive bank lowers the right edge")


# ---------------------------------------------------------------- gaps

func _gaps(t: Node) -> void:
	var pts := _straight("asphalt_rail", 400.0)
	pts[1]["gap"] = {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
	var r := LevelRoad.build(pts, styles, false, {})
	t.check(r.gaps.size() == 1, "one gap run")
	var g: Vector2i = r.gaps[0] if r.gaps.size() > 0 else Vector2i(0, 0)
	var first := g.x
	t.check(r.gap[first] == 1 and r.gap[first - 1] == 0, "the gap starts after the lip")
	t.near(r.s[first], 150.0 - 6.0, r.step, "the gap starts at at * len - len / 2")
	t.near(r.pos[first - 1].y, 1.8, 1e-4, "the kicker's lip has the full lift")
	t.near(r.pos[first - 1 - roundi(16.0 / r.step) + 1].y, 1.8 / roundi(16.0 / r.step) ** 2, 1e-3, "the kicker starts low (u^2)")
	t.check(r.pos[first - roundi(16.0 / r.step) - 1].y == 0.0, "no lift before the kicker")
	var ctx := _ctx(r)
	LevelGeometry.build_road(ctx, r)
	var m := r.mesh_road()
	var mg := -1
	for i in m.n:
		if m.gap[i] == 1:
			mg = i
			break
	var mend := mg
	while mend < m.n and m.gap[mend] == 1:
		mend += 1
	t.check(mg > 0, "the mesh road has the gap too")
	var lip := m.s[mg - 1]
	var land := m.s[mend]
	t.near(m.pos[mg - 1].y, 1.8, 1e-4, "mesh road: lip at full lift")
	var over := 0
	var lip_hit := false
	for tr in _tris(ctx.meshes):
		if not tr[0] in ["road", "verge", "walls", "colonly", "side"]:
			continue
		var c := _centroid(tr)
		if c.z > lip + 0.01 and c.z < land - 0.01:
			over += 1
		if tr[0] == "road":
			for q in [2, 3, 4]:
				if absf((tr[q] as Vector3).z - lip) < 0.01:
					lip_hit = true
	t.check(over == 0, "no surface / side / barrier / colonly triangle over the gap (%d)" % over)
	t.check(lip_hit, "the surface ends at the kicker's lip")


# ---------------------------------------------------------------- masks (C1 S5)

func _build_tris(r: LevelRoad) -> Array:
	var ctx := _ctx(r)
	LevelGeometry.build_road(ctx, r)
	return _tris(ctx.meshes)


## Compares a masked build with the plain one: every removed triangle must satisfy `may_go`, every
## added one `may_add`, and nothing that satisfies `must_go` may remain.
func _mask_case(t: Node, what: String, base: Array, masked: Array, may_go: Callable, may_add: Callable, must_go: Callable) -> void:
	var bk := {}
	for tr in base:
		bk[_key(tr)] = tr
	var mk := {}
	for tr in masked:
		mk[_key(tr)] = tr
	var removed := 0
	var wrong_go := 0
	for k in bk:
		if not mk.has(k):
			removed += 1
			if not may_go.call(bk[k]):
				wrong_go += 1
	var wrong_add := 0
	for k in mk:
		if not bk.has(k) and not may_add.call(mk[k]):
			wrong_add += 1
	var left := 0
	for tr in masked:
		if must_go.call(tr):
			left += 1
	t.check(removed > 0, "%s removes pieces (%d)" % [what, removed])
	t.check(wrong_go == 0, "%s removes only its pieces (%d others)" % [what, wrong_go])
	t.check(wrong_add == 0, "%s adds only its end faces (%d others)" % [what, wrong_add])
	t.check(left == 0, "%s leaves none of its pieces (%d)" % [what, left])


func _masks(t: Node) -> void:
	var pts := _straight("street", 400.0)
	var plain := LevelRoad.build(pts, styles, false, {})
	var base := _build_tris(plain)
	var a := 60
	var b := 90
	var sa := plain.s[a]
	var sb := plain.s[b]
	var hw := 7.0
	var inside := func(c: Vector3, pad: float) -> bool: return c.z > sa - pad and c.z < sb + pad
	var deep := func(c: Vector3) -> bool: return c.z > sa + 3.0 and c.z < sb - 3.0
	var near_end := func(c: Vector3) -> bool: return absf(c.z - sa) < 3.5 or absf(c.z - sb) < 3.5
	# side_off on the right (lateral -x): no kerb, pavement or barrier there
	var r1 := LevelRoad.build(pts, styles, false, {})
	for i in range(a, b + 1):
		r1.side_off[i * 2 + 1] = 1
	var right_side := func(tr: Array) -> bool: return -_centroid(tr).x > hw - 0.05
	_mask_case(t, "side_off", base, _build_tris(r1),
		func(tr: Array) -> bool: return right_side.call(tr) and inside.call(_centroid(tr), 2.5),
		func(tr: Array) -> bool: return (tr[0] == "side" or tr[0] == "walls") and right_side.call(tr) and near_end.call(_centroid(tr)),
		func(tr: Array) -> bool: return right_side.call(tr) and deep.call(_centroid(tr)))
	# clip_in: the surface runs from the centre line to the left edge (+x... lateral 0..+hw)
	var r2 := LevelRoad.build(pts, styles, false, {})
	for i in range(a, b + 1):
		r2.clip_in[i] = 0.0
	var surf := func(tr: Array) -> bool: return tr[0] == "road" and tr[1] == str(styles.street.road)
	_mask_case(t, "clip_in", base, _build_tris(r2),
		func(tr: Array) -> bool: return surf.call(tr) and inside.call(_centroid(tr), 2.5),
		func(tr: Array) -> bool: return surf.call(tr) and inside.call(_centroid(tr), 2.5) and -_centroid(tr).x > -0.01,
		func(tr: Array) -> bool: return surf.call(tr) and deep.call(_centroid(tr)) and -_centroid(tr).x < -0.01)
	# cut: no barrier, no colonly
	var r3 := LevelRoad.build(pts, styles, false, {})
	for i in range(a, b + 1):
		r3.cut[i] = 1
	var barrier := func(tr: Array) -> bool: return tr[0] == "walls" or tr[0] == "colonly"
	_mask_case(t, "cut", base, _build_tris(r3),
		func(tr: Array) -> bool: return barrier.call(tr) and inside.call(_centroid(tr), 2.5),
		func(tr: Array) -> bool: return tr[0] == "walls" and near_end.call(_centroid(tr)),
		func(tr: Array) -> bool: return barrier.call(tr) and deep.call(_centroid(tr)))
	# skip: no surface, no sides, no barriers
	var r4 := LevelRoad.build(pts, styles, false, {})
	for i in range(a, b + 1):
		r4.skip[i] = 1
	_mask_case(t, "skip", base, _build_tris(r4),
		func(tr: Array) -> bool: return inside.call(_centroid(tr), 2.5),
		func(tr: Array) -> bool: return near_end.call(_centroid(tr)) and (tr[0] == "side" or tr[0] == "walls"),
		func(tr: Array) -> bool: return deep.call(_centroid(tr)))


# ---------------------------------------------------------------- winding

func _winding(t: Node) -> void:
	var pts := _straight("street", 300.0)
	var r := LevelRoad.build(pts, styles, false, {})
	var ctx := _ctx(r)
	LevelGeometry.build_road(ctx, r)
	var road_bad := 0
	var road_n := 0
	var col_bad := 0
	var col_n := 0
	for tr in _tris(ctx.meshes):
		var a: Vector3 = tr[2]
		var b: Vector3 = tr[3]
		var c3: Vector3 = tr[4]
		var cr := (b - a).cross(c3 - a)
		if tr[0] == "road":
			road_n += 1
			if cr.dot(Vector3.UP) >= 0.0:
				road_bad += 1
		elif tr[0] == "colonly":
			col_n += 1
			var c := _centroid(tr)
			var toward := Vector3(-signf(c.x), 0.0, 0.0)
			if cr.dot(toward) >= 0.0:
				col_bad += 1
	t.check(road_n > 0 and road_bad == 0, "road triangles face up (%d of %d wrong)" % [road_bad, road_n])
	t.check(col_n > 0 and col_bad == 0, "colonly faces the road (%d of %d wrong)" % [col_bad, col_n])
	var names := {}
	var ok := true
	for mi in ctx.meshes.meshes():
		ok = ok and (mi.arrays as Array).size() == Mesh.ARRAY_MAX and not names.has(mi.name)
		names[mi.name] = true
		var nrm: PackedVector3Array = mi.arrays[Mesh.ARRAY_NORMAL]
		var tan: PackedFloat32Array = mi.arrays[Mesh.ARRAY_TANGENT]
		ok = ok and tan.size() == nrm.size() * 4
	t.check(ok, "buckets: unique names, ARRAY_MAX arrays, 4 tangent floats per vertex")
	t.check(names.has("road_m_g1_0"), "bucket names <kind>_<road>_g<uid>_<n> (%s)" % ", ".join(PackedStringArray(names.keys().slice(0, 3))))
	# a box faces out, a quad faces its normal
	var ms := LevelMeshSet.new()
	ms.box("walls", "x", Transform3D(Basis(), Vector3(0, 5, 0)), Vector3(2, 2, 2))
	var out_ok := true
	for tr in _tris(ms):
		var a: Vector3 = tr[2]
		var b: Vector3 = tr[3]
		var c3: Vector3 = tr[4]
		var cr := (b - a).cross(c3 - a)
		if cr.dot(_centroid(tr) - Vector3(0, 5, 0)) >= 0.0:
			out_ok = false
	t.check(out_ok and ms.triangles() == 12, "box faces outward (12 triangles)")
	var probe := LevelMeshSet.new()
	probe.tri("road", "x", Vector3(20, 0, 0), Vector3(30, 0, 0), Vector3(20, 0, 10), Vector3.UP)
	var pt: Array = _tris(probe)[0]
	var pc: Vector3 = (pt[3] - pt[2]).cross(pt[4] - pt[2])
	t.check(pc.y < 0.0, "tri facing up is wound like the collision probe")


# ---------------------------------------------------------------- groups and hashes

func _hashes(r: LevelRoad) -> Dictionary:
	var ctx := _ctx(r)
	LevelGeometry.build_road(ctx, r)
	LevelGeometry.start_line(ctx)
	var out := {}
	for mi in ctx.meshes.meshes():
		out[mi.name] = mi.hash
	return out


func _groups(t: Node) -> void:
	var pts := _circle(640.0, 64, "asphalt_rail")
	var r := LevelRoad.build(pts, styles, true, {"start": {"p": pts[0].uid, "t": 0.0}})
	t.check(r.group_of(17) == 2 and r.group_name(2) == "g%d" % pts[16].uid, "group 2 = segments 16-23, named by point 16's uid")
	var h0 := _hashes(r)
	var h0b := _hashes(LevelRoad.build(pts, styles, true, {"start": {"p": pts[0].uid, "t": 0.0}}))
	t.check(h0 == h0b, "hashes are deterministic")
	var moved := _circle(640.0, 64, "asphalt_rail")
	var p: Array = moved[20].pos
	moved[20]["pos"] = [p[0] * 1.006, p[1] + 1.5, p[2] * 1.006]
	var r1 := LevelRoad.build(moved, styles, true, {"start": {"p": pts[0].uid, "t": 0.0}})
	var h1 := _hashes(r1)
	t.check(h0.keys() == h1.keys(), "group names stable under a point move (%d buckets)" % h0.size())
	var changed := []
	var wrong := []
	var gname := "_g%d_" % pts[16].uid
	for k in h0:
		if h1.get(k) != h0[k]:
			changed.append(k)
			if not gname in k:
				wrong.append(k)
	t.check(changed.size() > 0, "the moved point's group changes (%d of %d buckets)" % [changed.size(), h0.size()])
	t.log("point move: %d of %d buckets changed hash" % [changed.size(), h0.size()])
	t.check(wrong.is_empty(), "only the moved point's group changes hash (%s)" % ", ".join(PackedStringArray(wrong)))


# ---------------------------------------------------------------- partial roads

func _partial(t: Node) -> void:
	var pts := _circle(640.0, 64, "asphalt", 14.0, 1, 6.0)
	pts[33]["bank"] = 8.0
	var full := LevelRoad.build(pts, styles, true, {})
	t.near(full.length, 4021.0, 15.0, "a 4 km loop")
	var best := INF
	var hold := [null]
	for _k in 6:
		var ms: float = t.ms(func() -> void: hold[0] = LevelRoad.build_partial(pts, styles, true, 30, 33, {}))
		best = minf(best, ms)
	var pr: LevelRoad = hold[0]
	t.check(best < 3.0, "build_partial of 4 segments of a 4 km loop < 3 ms (%.2f ms)" % best)
	t.check(pr.partial and not pr.closed and pr.emit_from >= 0 and pr.emit_to > pr.emit_from, "partial road flags and emit range")
	t.check(pr.seg[pr.emit_from] == 30 and pr.segt[pr.emit_from] == 0.0, "emit_from = the start of first_seg")
	t.check(pr.seg[pr.emit_to] == 34 or (pr.seg[pr.emit_to] == 33 and pr.segt[pr.emit_to] >= 1.0), "emit_to = the end of last_seg")
	var worst := 0.0
	var fm := full.mesh_road()
	var worst_mesh := 0.0
	for k in range(30, 35):
		var j := pr.seg_first[k]
		if j < 0:
			continue
		var s_f := full.anchor_s({"p": pts[k].uid, "t": 0.0})
		var i0 := int(floor(s_f / full.step))
		var f := s_f / full.step - i0
		var i1 := full.wrap(i0 + 1)
		i0 = full.wrap(i0)
		for lat in [0.0, -7.0, 7.0]:
			var q := full.surface(i0, lat).lerp(full.surface(i1, lat), f)
			worst = maxf(worst, q.distance_to(pr.surface(j, lat)))
		var mj := fm.seg_first[k]
		for lat in [0.0, -7.0, 7.0]:
			worst_mesh = maxf(worst_mesh, fm.surface(mj, lat).distance_to(pr.surface(j, lat)))
	t.check(worst < 0.1, "build_partial within 0.1 m of the full build at the segment ends (%.3f m)" % worst)
	t.check(worst_mesh < 0.05, "and within 0.05 m of the full build's mesh road (%.3f m)" % worst_mesh)
	# emitted geometry of the partial road: only its groups, inside its window
	var ctx := _ctx(pr)
	var tpg: float = t.ms(func() -> void: LevelGeometry.build_road(ctx, pr, PackedInt32Array([pr.group_of(30), pr.group_of(33)])))
	t.log("partial road of 4 segments: %.2f ms, its geometry %.2f ms (%d triangles)" % [best, tpg, ctx.meshes.triangles()])
	var names := {}
	for mi in ctx.meshes.meshes():
		names[str(mi.group)] = true
	t.check(names.keys() == ["g%d" % pts[24].uid] or names.keys() == ["g%d" % pts[24].uid, "g%d" % pts[32].uid], "partial geometry only in its groups (%s)" % str(names.keys()))
	var tf: float = t.ms(func() -> void: LevelRoad.build(pts, styles, true, {}))
	var ctx2 := _ctx(full)
	var tg: float = t.ms(func() -> void: LevelGeometry.build_road(ctx2, full))
	t.log("full 4 km road: build %.1f ms, geometry %.1f ms, %d triangles" % [tf, tg, ctx2.meshes.triangles()])


# ---------------------------------------------------------------- tunnel lights

func _lights(t: Node) -> void:
	var pts := _circle(300.0, 20)
	for k in 11:
		pts[k]["style"] = "tunnel"
	var r := LevelRoad.build(pts, styles, true, {})
	var tl := 0.0
	for k in 11:
		tl += r.seg_len[k]
	t.check(tl > 1000.0, "a 1 km tunnel (%.0f m)" % tl)
	t.check(LevelGeometry.light_count([r], 0.0) > LevelGeometry.LIGHT_CAP, "it would have more than 96 lights")
	var ctx := _ctx(r)
	LevelGeometry.build_road(ctx, r)
	t.check(ctx.tunnel_lights.size() <= LevelGeometry.LIGHT_CAP and ctx.tunnel_lights.size() > 60, "tunnel lights capped at 96 (%d)" % ctx.tunnel_lights.size())
	t.check(ctx.light_extra > 0.0 and fmod(ctx.light_extra, 2.0) == 0.0, "light_every widened in 2 m steps (+%.0f m)" % ctx.light_extra)
	t.check(ctx.report.has("tunnel_lights"), "warning tunnel_lights")
	var glow := 0
	var kinds := {}
	for mi in ctx.meshes.meshes():
		kinds[mi.kind] = true
		if mi.kind == "glow":
			glow += (mi.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 6
	t.check(glow == ctx.tunnel_lights.size(), "one glow panel per light (%d)" % glow)
	t.check(kinds.has("walls") and kinds.has("ceil") and kinds.has("road"), "tunnel walls, ceiling and floor")
	var l: Dictionary = ctx.tunnel_lights[0] if ctx.tunnel_lights.size() > 0 else {}
	t.check(l.has("pos") and l.has("color") and float(l.get("range", 0)) >= 12.0, "light entries as data.lights ({pos, color, range, energy})")


# ---------------------------------------------------------------- racing line

func _line(t: Node) -> void:
	var r := LevelRoad.build(_wiggle(), styles, true, {})
	var off := LevelLine.racing(r)
	var bad := 0
	var used := 0.0
	for i in r.n:
		if absf(off[i]) > maxf(r.width[i] * 0.5 - 3.8, 0.0) + 1e-4:
			bad += 1
		used = maxf(used, absf(off[i]))
	t.check(bad == 0, "the racing line stays within width / 2 - 3.8 (%d outside)" % bad)
	t.check(used > 1.0, "the racing line cuts the bends (%.2f m)" % used)
	LevelLine.apply(r, off)
	var vbad := 0
	for i in r.n:
		if r.speed[i] < 12.0 - 1e-4 or r.speed[i] > 40.0 + 1e-4:
			vbad += 1
	t.check(r.line.size() == r.n and vbad == 0, "line and speeds filled, speeds 12..40")
	t.near(r.lateral(r.line[10], 10), off[10], 1e-3, "line = pos + right * off")
	# gaps hold the line at 0; open edges keep within width / 2 - 6.5
	var pts := _straight("asphalt", 400.0)
	pts[1]["gap"] = {"len": 12.0}
	var o := LevelRoad.build(pts, styles, false, {})
	for i in o.n:
		o.pit[i] = 1 if o.gap[i] == 1 or (i > 100 and i < 150) else 0
	var oo := LevelLine.racing(o)
	var gbad := 0
	for i in o.n:
		if o.gap[i] == 1 and oo[i] != 0.0:
			gbad += 1
		if o.pit[i] == 1 and o.gap[i] == 0 and absf(oo[i]) > maxf(o.width[i] * 0.5 - 6.5, 0.0) + 1e-5:
			gbad += 1
	t.check(gbad == 0, "line 0 over gaps, inside width / 2 - 6.5 beside open edges")
	var tm: float = t.ms(func() -> void: LevelLine.racing(r))
	t.log("racing line: %d samples in %.1f ms" % [r.n, tm])


# ---------------------------------------------------------------- the other kinds

func _kinds_of(ms: LevelMeshSet) -> Dictionary:
	var out := {}
	for tr in _tris(ms):
		var k := "%s|%s" % [tr[0], tr[1]]
		out[k] = int(out.get(k, 0)) + 1
	return out


func _kinds(t: Node) -> void:
	# highway: jersey barriers both sides, a full-width surface texture
	var hw := LevelRoad.build(_circle(400.0, 24, "highway"), styles, true, {})
	var c1 := _ctx(hw)
	LevelGeometry.build_road(c1, hw)
	var k1 := _kinds_of(c1.meshes)
	var jm := "walls|%s" % str(styles.highway.barrier_l.mat)
	t.check(int(k1.get(jm, 0)) > 0 and int(k1.get("colonly|colonly", 0)) > 0, "jersey barriers with their colonly wall")
	t.check(int(k1.get("verge|%s" % str(styles.highway.verge), 0)) > 0, "highway verges")
	# a bridge over low ground: skirts, underside, pillars
	var br := LevelRoad.build(_straight("bridge", 300.0), styles, false, {})
	var c2 := LowGround.new()
	c2.report = LevelReport.new()
	c2.meshes = LevelMeshSet.new()
	c2.main = br
	LevelGeometry.build_road(c2, br)
	var k2 := _kinds_of(c2.meshes)
	var skirt := "side|%s" % str(styles.bridge.skirt)
	var down := 0
	var pillar_tris := 0
	for tr in _tris(c2.meshes):
		var a: Vector3 = tr[2]
		var b: Vector3 = tr[3]
		var c3: Vector3 = tr[4]
		if tr[0] == "side" and absf(_centroid(tr).y + float(styles.bridge.skirt_h)) < 0.01 and absf(_centroid(tr).x) < 6.9:
			if (b - a).cross(c3 - a).dot(Vector3.DOWN) < 0.0:
				down += 1
		if tr[0] == "side" and _centroid(tr).y < -5.0:
			pillar_tris += 1
	t.check(int(k2.get(skirt, 0)) > 0 and down > 0, "bridge skirts and an underside facing down")
	# 3 segments x round(100 / 30) spots x 2 boxes x 10 triangles below -5 m (the top faces sit higher)
	t.check(pillar_tris == 3 * 3 * 2 * 10, "bridge pillars down to the ground, per segment (%d triangles)" % pillar_tris)
	var c2b := _ctx(br)
	LevelGeometry.build_road(c2b, br)
	var none := 0
	for tr in _tris(c2b.meshes):
		if _centroid(tr).y < -5.0:
			none += 1
	t.check(none == 0, "no pillars without ground")
	# centre dashes on an own style, a rail override
	var own := {"styles": {"lined": {"name": "LINED", "kind": "open", "lines": true}}}
	var st2 := LevelStyles.resolve(own, {})
	var pts := _straight("lined", 300.0)
	pts[1]["barrier_l"] = {"kind": "rail", "mat": "metal/metalrail013a", "h": 1.0, "thick": 0.05}
	var ln := LevelRoad.build(pts, st2, false, {})
	var c3c := _ctx(ln)
	LevelGeometry.build_road(c3c, ln)
	var dashes := 0
	var rail := 0
	for tr in _tris(c3c.meshes):
		if tr[0] == "decal":
			dashes += 1
		if tr[0] == "walls" and tr[1] == "metal/metalrail013a":
			rail += 1
			if _centroid(tr).z < 99.0 or _centroid(tr).z > 201.0:
				rail = -100000
	t.check(dashes > 0, "centre dashes (%d triangles)" % dashes)
	t.check(rail > 0, "a segment's rail stands on that segment only")
	# UVs: a whole number of repeats per segment
	var m := hw.mesh_road()
	var run: PackedInt32Array = m.runs(func(i: int) -> bool: return true)[0]
	var v := LevelGeometry._vs(m, run, 6.0)
	var whole := true
	for q in run.size():
		if m.segt[run[q]] == 0.0 and absf(v[q] - roundf(v[q])) > 1e-4:
			whole = false
	t.check(whole and v[v.size() - 1] > v[0], "every segment holds a whole number of texture repeats")


# ---------------------------------------------------------------- the rest of the API

func _misc(t: Node) -> void:
	var pts := _wiggle()
	pts[4]["barrier_r"] = {"kind": "wall", "h": 2.0}
	pts[6]["barrier_l"] = {"kind": "none"}
	var st := styles.duplicate()
	var r := LevelRoad.build(pts, st, true, {})
	var i4 := r.seg_first[4]
	var i6 := r.seg_first[6]
	t.check(LevelGeometry.barrier_of(r, i4, 1).get("kind") == "wall" and float(LevelGeometry.barrier_of(r, i4, 1).h) == 2.0, "segment barrier override")
	t.check(LevelGeometry.barrier_of(r, i6, 0).is_empty() and LevelGeometry.barrier_of(r, i6, 1).is_empty(), "asphalt has no barriers; NONE stays none")
	t.check(r.treatment(i4, 1) >= 4.0 and r.treatment(i4, 0) >= 4.0, "treatment (open: the verge)")
	var c := r.closest(r.pos[50] + Vector3(0.3, 0, 0))
	t.check(c == 50, "closest")
	t.check(r.closest(r.pos[50], 48, 5) == 50, "closest with a hint")
	var hit := r.ray_hit(r.pos[80] + Vector3(0, 30, 0) + r.right[80] * 2.0, Vector3.DOWN)
	t.check(not hit.is_empty() and absi(int(hit.i) - 80) <= 1 and absf(float(hit.lat) - 2.0) < 0.2, "ray_hit on the banked strip (%s)" % str(hit))
	t.check(r.ray_hit(r.pos[80] + Vector3(0, 30, 0) + r.right[80] * 40.0, Vector3.DOWN).is_empty(), "ray_hit misses beside the road")
	t.check(is_inf(LevelRoad.build(_straight("asphalt"), st, false, {}).radius_at(50)), "radius_at a straight is INF")
	t.near(LevelRoad.build(_circle(640.0, 64), st, true, {}).radius_at(100), 640.0, 6.0, "radius_at a 640 m circle")
	var runs := r.runs(func(i: int) -> bool: return true)
	t.check(runs.size() == 1 and runs[0].size() == r.n + 1 and runs[0][r.n] == 0, "runs: a whole loop closes on sample 0")
	var half := r.runs(func(i: int) -> bool: return i >= 10 and i < 20)
	t.check(half.size() == 1 and half[0].size() == 11 and half[0][10] == 20, "runs carry the next sample")
	var wrapr := r.runs(func(i: int) -> bool: return i < 5 or i > r.n - 6)
	t.check(wrapr.size() == 1 and wrapr[0][0] == r.n - 5, "runs wrap round the lap")
	var seesaw := _straight("bridge", 300.0)
	seesaw[1]["seesaw"] = true
	var sr := LevelRoad.build(seesaw, st, false, {})
	var si := sr.seg_first[1] + 3
	t.check(sr.skip[si] == 1 and sr.kind(si) == "bridge" and sr.bar_l[si] == -1, "a see-saw stretch: skip, kind bridge, no barriers")
	# context helpers
	var ctx := _ctx(r)
	t.check(ctx.road(-1) == r and ctx.road(5) == null, "ctx.road")
	t.check(is_nan(ctx.ground(0, 0)), "ctx.ground is NAN without terrain")
	var sp := ctx.side_point(r, 30, 1, 2.0)
	t.check(sp.distance_to(r.surface(30, r.width[30] * 0.5)) < 2.2 and sp.y < r.surface(30, r.width[30] * 0.5).y, "side_point on the verge")
	t.near(ctx.floor_y(r, r.surface(30, 1.0), 30), r.surface(30, 1.0).y, 0.05, "floor_y on the road")
	ctx.props = [{"pos": [sp.x, sp.y, sp.z]}]
	var s2 := ctx.clear_spot(r, r.s[30], 1, 2.0)
	t.check(absf(s2 - r.s[30]) >= 1.5, "clear_spot moves off a prop")
	ctx.registries = {"models": {"props/a": {}}}
	t.check(ctx.has_model("props/a") and not ctx.has_model("props/b"), "has_model")
	var cnt := 0
	r.mark_pits(func(x: float, z: float) -> float: return NAN)
	for i in r.n:
		cnt += r.pit[i]
	t.check(cnt == r.n, "pit: no ground beside an unrailed road counts as below")
	r.mark_pits(func(x: float, z: float) -> float: return 0.0)
	cnt = 0
	for i in r.n:
		cnt += r.pit[i]
	t.check(cnt < r.n, "pit: ground near the road clears it")
	# degenerate input never breaks
	var one := LevelRoad.build([{"uid": 1, "pos": [0, 0, 0]}], st, true, {})
	var same := LevelRoad.build([{"uid": 1, "pos": [5, 0, 5]}, {"uid": 2, "pos": [5, 0, 5]}, {"uid": 3, "pos": [5, 0, 5]}], st, true, {})
	var dctx := _ctx(same)
	LevelGeometry.build_road(dctx, same)
	LevelGeometry.start_line(dctx)
	t.check(one.n == 0 and same.n == 0 and same.export_path().center.is_empty() and dctx.meshes.triangles() == 0, "a point or a zero-length loop gives an empty road")
