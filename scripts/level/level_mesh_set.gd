class_name LevelMeshSet
extends RefCounted
## Mesh buckets by (kind, material, road, segment group) with hashes, and the triangle / strip /
## box / quad writers (winding, tangents) the geometry code fills them with (3.5). P2.
##
## A bucket becomes one MeshInstance3D named `<kind>_<road>_<group>_<n>` (`road_m_g12_0`): road
## "m" the main loop (-1), "b<uid>" a branch (uid >= 0), "x" the start line and junction gores
## (-2), "h<uid>" a hazard setup (hazard_key(uid)); n counts the materials of one kind, road and
## group in the order they were first written. Winding: Godot's front face is the reverse of the
## glTF writer's, so a triangle meant to face n is written in the order where
## (b - a).cross(c - a).dot(n) < 0. Tangents are analytic (no SurfaceTool).

const ROAD_MAIN := -1
const ROAD_OTHER := -2
## Road keys at or below this are hazard setups: hazard_key(uid) = HAZARD_BASE - uid.
const HAZARD_BASE := -1000

var _buckets := {}        # "<kind>|<material>|<road>|<group>" -> bucket dict
var _order: Array = []    # bucket keys in creation order
var _tris := 0


## The road key of a hazard setup's meshes (name "h<uid>").
static func hazard_key(uid: int) -> int:
	return HAZARD_BASE - uid


## The road part of a bucket name: "m", "b<uid>", "x" or "h<uid>".
static func road_name(road: int) -> String:
	if road == ROAD_MAIN:
		return "m"
	if road <= HAZARD_BASE:
		return "h%d" % (HAZARD_BASE - road)
	if road < 0:
		return "x"
	return "b%d" % road


## The meta level_road of a bucket's node: -1 main, a branch uid, -2 anything else.
static func meta_road(road: int) -> int:
	return road if road >= ROAD_MAIN else ROAD_OTHER


func tri(kind: String, material: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], road := -1, group := "g0") -> void:
	var nn := n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
	var t := _uv_tangent(a, b, c, uv[0], uv[1], uv[2], nn)
	_flat_faces(_bucket(kind, material, road, group), [a, b, c], uv, nn, t)


## A quad strip between polylines a and b (same length): u across (ua at a, ub at b), v along,
## normals na / nb (each triangle faces its vertices' mean normal). Built in local arrays and
## appended to the bucket once (the drag preview's hot path, 3.11).
func strip(kind: String, material: String, a: PackedVector3Array, b: PackedVector3Array, ua: PackedFloat32Array, ub: PackedFloat32Array, v: PackedFloat32Array, na: PackedVector3Array, nb: PackedVector3Array, road := -1, group := "g0") -> void:
	var m := a.size()
	if m < 2 or b.size() != m:
		return
	var bk := _bucket(kind, material, road, group)
	var bv: PackedVector3Array = bk.v
	var base := bv.size()
	var lv := PackedVector3Array()
	lv.resize(m * 2)
	var ln := PackedVector3Array()
	ln.resize(m * 2)
	var lt := PackedFloat32Array()
	lt.resize(m * 8)
	var luv := PackedVector2Array()
	luv.resize(m * 2)
	for i in m:
		var j := i + 1 if i < m - 1 else i - 1
		var ai := a[i]
		var bi := b[i]
		var along := a[j] - ai
		if j < i:
			along = -along
		var dv := v[mini(i + 1, m - 1)] - v[maxi(i - 1, 0)]
		var across := bi - ai
		var du := ub[i] - ua[i]
		var ga := _strip_tangent(across, du, along, dv, na[i])
		var gb := _strip_tangent(across, du, along, dv, nb[i])
		var q := i * 2
		lv[q] = ai
		lv[q + 1] = bi
		ln[q] = na[i]
		ln[q + 1] = nb[i]
		var o := i * 8
		lt[o] = ga.normal.x
		lt[o + 1] = ga.normal.y
		lt[o + 2] = ga.normal.z
		lt[o + 3] = ga.d
		lt[o + 4] = gb.normal.x
		lt[o + 5] = gb.normal.y
		lt[o + 6] = gb.normal.z
		lt[o + 7] = gb.d
		var vi := v[i]
		luv[q] = Vector2(ua[i], vi)
		luv[q + 1] = Vector2(ub[i], vi)
	var li := PackedInt32Array()
	li.resize((m - 1) * 6)
	var w := 0
	for i in m - 1:
		var a0 := i * 2
		var f := (na[i] + na[i + 1] + nb[i] + nb[i + 1])
		var pa := lv[a0]
		var pb := lv[a0 + 1]
		var pc := lv[a0 + 2]
		var pd := lv[a0 + 3]
		# (a0, b0, a1) then (a1, b0, b1), each wound to face f, degenerate ones left out
		var cr := (pb - pa).cross(pc - pa)
		if cr.length_squared() >= 1e-14:
			li[w] = base + a0
			if cr.dot(f) < 0.0:
				li[w + 1] = base + a0 + 1
				li[w + 2] = base + a0 + 2
			else:
				li[w + 1] = base + a0 + 2
				li[w + 2] = base + a0 + 1
			w += 3
		cr = (pb - pc).cross(pd - pc)
		if cr.length_squared() >= 1e-14:
			li[w] = base + a0 + 2
			if cr.dot(f) < 0.0:
				li[w + 1] = base + a0 + 1
				li[w + 2] = base + a0 + 3
			else:
				li[w + 1] = base + a0 + 3
				li[w + 2] = base + a0 + 1
			w += 3
	li.resize(w)
	bv.append_array(lv)
	bk.v = bv
	var bn: PackedVector3Array = bk.n
	bn.append_array(ln)
	bk.n = bn
	var bt: PackedFloat32Array = bk.t
	bt.append_array(lt)
	bk.t = bt
	var bu: PackedVector2Array = bk.uv
	bu.append_array(luv)
	bk.uv = bu
	var bi2: PackedInt32Array = bk.i
	bi2.append_array(li)
	bk.i = bi2
	_tris += w / 3


## A box with all six faces facing out, its texture `rep` metres a repeat.
func box(kind: String, material: String, xf: Transform3D, size: Vector3, rep := 2.0, road := -1, group := "g0") -> void:
	var h := size * 0.5
	var bx := xf.basis
	var c := xf.origin
	var ax := bx.x * h.x
	var ay := bx.y * h.y
	var az := bx.z * h.z
	for f in [[ax, ay, az], [-ax, ay, az], [az, ay, ax], [-az, ay, ax], [ay, az, ax], [-ay, az, ax]]:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var o := c + nrm
		var lu := u.length() * 2.0 / maxf(rep, 0.01)
		var lw := w.length() * 2.0 / maxf(rep, 0.01)
		quad(kind, material, [o - u - w, o - u + w, o + u + w, o + u - w], nrm,
			[Vector2(0, lu), Vector2(lw, lu), Vector2(lw, 0), Vector2(0, 0)], road, group)


## A flat quad (two triangles 0-1-2, 0-2-3) facing n.
func quad(kind: String, material: String, p: Array, n: Vector3, uv: Array, road := -1, group := "g0") -> void:
	if p.size() < 4 or uv.size() < 4:
		return
	var nn := n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
	var t := _uv_tangent(p[0], p[1], p[2], uv[0], uv[1], uv[2], nn)
	_flat_faces(_bucket(kind, material, road, group), [p[0], p[1], p[2], p[3]], uv, nn, t)


## A convex (or star-shaped about its centroid, center = true) polygon facing n.
func fan(kind: String, material: String, p: Array, n: Vector3, uv: Array, road := -1, group := "g0", center := false) -> void:
	if p.size() < 3:
		return
	var pts := p.duplicate()
	var uvs := uv.duplicate()
	if center:
		var cp := Vector3.ZERO
		var cu := Vector2.ZERO
		for k in p.size():
			cp += p[k]
			cu += uv[k]
		pts = [cp / p.size()] + p + [p[0]]
		uvs = [cu / p.size()] + uv + [uv[0]]
	var nn := n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
	var t := _uv_tangent(pts[0], pts[1], pts[2], uvs[0], uvs[1], uvs[2], nn)
	_flat_faces(_bucket(kind, material, road, group), pts, uvs, nn, t)


## [{name, kind, material, road: int, group: String, hash: int, arrays: Array (Mesh.ARRAY_MAX)}]
func meshes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counts := {}
	for k in _order:
		var bk: Dictionary = _buckets[k]
		if (bk.i as PackedInt32Array).is_empty():
			continue
		var stem := "%s_%s_%s" % [bk.kind, road_name(bk.road), bk.group]
		var nth: int = counts.get(stem, 0)
		counts[stem] = nth + 1
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bk.v
		arrays[Mesh.ARRAY_NORMAL] = bk.n
		arrays[Mesh.ARRAY_TANGENT] = bk.t
		arrays[Mesh.ARRAY_TEX_UV] = bk.uv
		arrays[Mesh.ARRAY_INDEX] = bk.i
		out.append({"name": "%s_%d" % [stem, nth], "kind": bk.kind, "material": bk.material,
			"road": bk.road, "group": bk.group, "hash": _hash(bk), "arrays": arrays})
	return out


func triangles() -> int:
	return _tris


# ---------------------------------------------------------------- additions (P2)

## Drops every bucket of one road (and, when group is given, only that group's).
func remove(road: int, group := "") -> void:
	var keep: Array = []
	for k in _order:
		var bk: Dictionary = _buckets[k]
		if bk.road == road and (group == "" or bk.group == group):
			_tris -= (bk.i as PackedInt32Array).size() / 3
			_buckets.erase(k)
		else:
			keep.append(k)
	_order = keep


## Appends another set's buckets (same keys merge).
func merge(other: LevelMeshSet) -> void:
	for k in other._order:
		var ob: Dictionary = other._buckets[k]
		var bk := _bucket(ob.kind, ob.material, ob.road, ob.group)
		var base: int = (bk.v as PackedVector3Array).size()
		var vv: PackedVector3Array = bk.v
		vv.append_array(ob.v)
		bk.v = vv
		var nn: PackedVector3Array = bk.n
		nn.append_array(ob.n)
		bk.n = nn
		var ta: PackedFloat32Array = bk.t
		ta.append_array(ob.t)
		bk.t = ta
		var uu: PackedVector2Array = bk.uv
		uu.append_array(ob.uv)
		bk.uv = uu
		var idx: PackedInt32Array = bk.i
		for q in (ob.i as PackedInt32Array):
			idx.append(q + base)
		bk.i = idx
		_tris += (ob.i as PackedInt32Array).size() / 3


## The bucket dicts (kind, material, road, group, v, n, t, uv, i) in creation order (tests).
func buckets() -> Array:
	var out := []
	for k in _order:
		out.append(_buckets[k])
	return out


# ---------------------------------------------------------------- internals

func _bucket(kind: String, material: String, road: int, group: String) -> Dictionary:
	var k := "%s|%s|%d|%s" % [kind, material, road, group]
	if _buckets.has(k):
		return _buckets[k]
	var bk := {"kind": kind, "material": material, "road": road, "group": group,
		"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(),
		"uv": PackedVector2Array(), "i": PackedInt32Array()}
	_buckets[k] = bk
	_order.append(k)
	return bk


## One flat polygon's vertices (one normal and tangent) appended to bk at once, then its
## triangles: a fan from vertex 0 (0-1-2, 0-2-3, ...), each wound to face nn (Godot's order:
## cross . nn < 0), degenerate ones left out. tri / quad have 3 / 4 vertices, the same fan.
func _flat_faces(bk: Dictionary, pts: Array, uvs: Array, nn: Vector3, t: Plane) -> void:
	var cnt := pts.size()
	var bv: PackedVector3Array = bk.v
	var base := bv.size()
	var lv := PackedVector3Array()
	lv.resize(cnt)
	var ln := PackedVector3Array()
	ln.resize(cnt)
	var lt := PackedFloat32Array()
	lt.resize(cnt * 4)
	var luv := PackedVector2Array()
	luv.resize(cnt)
	for k in cnt:
		lv[k] = pts[k]
		ln[k] = nn
		lt[k * 4] = t.normal.x
		lt[k * 4 + 1] = t.normal.y
		lt[k * 4 + 2] = t.normal.z
		lt[k * 4 + 3] = t.d
		luv[k] = uvs[k]
	var li := PackedInt32Array()
	var a := lv[0]
	for k in range(1, cnt - 1):
		var cr := (lv[k] - a).cross(lv[k + 1] - a)
		if cr.length_squared() < 1e-14:
			continue
		li.append(base)
		if cr.dot(nn) < 0.0:
			li.append(base + k)
			li.append(base + k + 1)
		else:
			li.append(base + k + 1)
			li.append(base + k)
	bv.append_array(lv)
	bk.v = bv
	var bn: PackedVector3Array = bk.n
	bn.append_array(ln)
	bk.n = bn
	var bt: PackedFloat32Array = bk.t
	bt.append_array(lt)
	bk.t = bt
	var bu: PackedVector2Array = bk.uv
	bu.append_array(luv)
	bk.uv = bu
	var bi: PackedInt32Array = bk.i
	bi.append_array(li)
	bk.i = bi
	_tris += li.size() / 3


## The tangent (normal = T, d = w) of a strip vertex: T = the across direction toward +u
## projected off N; w = sign(dot(N x T, +v direction)).
static func _strip_tangent(across: Vector3, du: float, along: Vector3, dv: float, nrm: Vector3) -> Plane:
	var t := across * (1.0 if du >= 0.0 else -1.0)
	t = t - nrm * t.dot(nrm)
	if t.length_squared() < 1e-12:
		t = along - nrm * along.dot(nrm)
	t = t.normalized() if t.length_squared() > 1e-12 else Vector3.RIGHT
	var vdir := along * (1.0 if dv >= 0.0 else -1.0)
	var w := 1.0 if nrm.cross(t).dot(vdir) >= 0.0 else -1.0
	return Plane(t, w)


## The tangent of a flat triangle from its uv gradient.
static func _uv_tangent(a: Vector3, b: Vector3, c: Vector3, ta: Vector2, tb: Vector2, tc: Vector2, nrm: Vector3) -> Plane:
	var e1 := b - a
	var e2 := c - a
	var d1 := tb - ta
	var d2 := tc - ta
	var det := d1.x * d2.y - d2.x * d1.y
	var t := e1
	var bt := e2
	if absf(det) > 1e-12:
		t = (e1 * d2.y - e2 * d1.y) / det
		bt = (e2 * d1.x - e1 * d2.x) / det
	t = t - nrm * t.dot(nrm)
	t = t.normalized() if t.length_squared() > 1e-12 else Vector3.RIGHT
	var w := 1.0 if nrm.cross(t).dot(bt) >= 0.0 else -1.0
	return Plane(t, w)


static func _hash(bk: Dictionary) -> int:
	return hash([bk.material, bk.v, bk.n, bk.uv, bk.i])
