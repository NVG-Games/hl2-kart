class_name LevelFixes
## The FIX buttons of 1.8 as ops (one undo step "FIX: <label>", committed by TrackEditor.apply_fix).
## Each fix reads the issue's where (road, s, uid, road_b / s_b, s_end, branch / end, point, type)
## against the last full bake (compiled here when there is none) and writes only points, segments
## and items that are in the document now. P13.

## fix id -> button label (1.8)
const LABELS := {"close_loop": "CLOSE LOOP", "narrow": "NARROW THE ROAD HERE", "bridge": "MAKE A BRIDGE",
	"clear_grid": "CLEAR THE GRID", "remove_jump": "REMOVE THE JUMP", "smooth": "SMOOTH HEIGHTS HERE",
	"raise_water": "RAISE ABOVE THE WATER", "legal_spot": "MOVE TO A LEGAL SPOT", "auto_items": "AUTO ITEMS",
	"hazard_setup": "DELETE / ADD THE SEE-SAW", "delete": "DELETE"}

## MAKE A BRIDGE: the stretch within this many metres of the crossing is raised by BRIDGE_RAISE,
## eased back to the road's height over EASE metres each side.
const BRIDGE_REACH := 60.0
const BRIDGE_RAISE := 7.0
const EASE := 40.0
## RAISE ABOVE THE WATER: the surface goes this far over the level.
const WATER_CLEAR := 1.5
## The validator's own margin (LevelValidate.WATER_CLEAR).
const WATER_TEST := 0.7
const MIN_WIDTH := 6.0
const MAX_WIDTH := 40.0
## NARROW THE ROAD HERE looks this far either side of the issue's spot.
const NARROW_REACH := 80.0
## SMOOTH HEIGHTS HERE: this many points round the spot, a moving average over SMOOTH_WINDOW.
const SMOOTH_POINTS := 7
const SMOOTH_WINDOW := 5
const GRID_BACK := 70.0
## MOVE TO A LEGAL SPOT: the metres past a fork (before a merge) that must lie flat.
const LEVEL_REACH := 80.0
const T_STEP := 1.0 / 65536.0


static func ops(issue: Dictionary, doc: LevelDoc, build: LevelBuild) -> Array:
	if issue.is_empty() or doc == null:
		return []
	var fix := str(issue.get("fix", ""))
	if fix == "":
		fix = str(LevelValidate.FIXES.get(str(issue.get("code", "")), ""))
	match fix:
		"close_loop":
			return close_loop_ops(doc)
		"delete":
			return _delete_item(doc, "props", int(issue.get("uid", 0)))
		"hazard_setup":
			return _hazard_setup(issue, doc)
	var b := _bake(doc, build)
	if b == null:
		return []
	match fix:
		"narrow":
			return _narrow(issue, doc, b)
		"bridge":
			if str(issue.get("code", "")) == "embankment":
				return _bridge_embankment(issue, doc, b)
			return _bridge_crossing(issue, doc, b)
		"clear_grid":
			return _clear_grid(doc, b)
		"remove_jump":
			return _remove_jump(issue, doc, b)
		"smooth":
			return _smooth_here(issue, doc, b)
		"raise_water":
			return _raise_water(issue, doc, b)
		"legal_spot":
			return _legal_spot(issue, doc, b)
		"auto_items":
			return LevelDress.items_ops(doc, b)
	return []


## The button label of an issue's fix ("ADD THE SEE-SAW" or "DELETE" for a hazard_setup).
static func label(issue: Dictionary) -> String:
	var fix := str(issue.get("fix", ""))
	if fix == "hazard_setup":
		return "ADD THE SEE-SAW" if str(issue.get("type", "")) == "seesaw_stretch" else "DELETE"
	return str(LABELS.get(fix, fix.to_upper().replace("_", " ")))


# ---------------------------------------------------------------- fixes that need no bake

## CLOSE LOOP: closed = true (a road needs 3 points for it).
static func close_loop_ops(doc: LevelDoc) -> Array:
	var road = doc.data.get("road")
	if not (road is Dictionary) or not (road.get("points") is Array) or (road.points as Array).size() < 3:
		return []
	if bool(road.get("closed", false)):
		return []
	return [LevelDoc.op_set(["road", "closed"], true)]


static func _delete_item(doc: LevelDoc, section: String, uid: int) -> Array:
	var f := doc.find(uid)
	if f.is_empty() or str(f.get("section", "")) != section:
		return []
	return [["remove", [section], "#%d" % uid]]


## A see-saw stretch without its see-saw gets one (LevelHazards.seesaw_ops); a hazard that misses
## its setup is deleted.
static func _hazard_setup(issue: Dictionary, doc: LevelDoc) -> Array:
	var uid := int(issue.get("uid", 0))
	if str(issue.get("type", "")) == "seesaw_stretch":
		return LevelHazards.seesaw_ops(doc, uid, true)
	return _delete_item(doc, "hazards", uid)


# ---------------------------------------------------------------- road fixes

## NARROW THE ROAD HERE (too_tight, branch_tight): every point of a bend near the spot gets the
## widest width that passes (width / 2 + treatment + 2 m <= radius), at least 6 m.
static func _narrow(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var key := int(issue.get("road", -1))
	var r := road_of(b, key)
	if r == null or r.n < 3 or r.curv.size() != r.n:
		return []
	var i0 := r.idx(float(issue.get("s", 0.0)))
	var reach := ceili(NARROW_REACH / maxf(r.step, 0.1))
	var allow := {}
	for d in range(-reach, reach + 1):
		var i := i0 + d
		if not r.closed and (i < 0 or i >= r.n):
			continue
		i = r.wrap(i)
		var c := absf(r.curv[i])
		if c < 1e-7:
			continue
		var tr := maxf(r.treatment(i, 0), r.treatment(i, 1))
		if c * (r.width[i] * 0.5 + tr + 2.0) <= 1.0:
			continue
		var w := maxf(floorf(4.0 * (1.0 / c - tr - 2.0)) * 0.5, MIN_WIDTH)
		for uid in _seg_points(r, r.seg[i]):
			allow[uid] = minf(float(allow.get(uid, INF)), w)
	var out := []
	for uid in allow:
		var f := _point(doc, key, uid)
		if f.is_empty():
			continue
		var cur := float(f.item.get("width", 14.0))
		var w: float = allow[uid]
		if w < cur - 1e-3:
			out.append(LevelDoc.op_set(point_path(key, uid) + ["width"], w))
	return out


## MAKE A BRIDGE (crossing): the shorter of the two stretches within +-60 m of the crossing (a
## branch's before the main road's; else the one with fewer points) is raised by 7 m, eased over
## 40 m each side, and its segments become the `bridge` style.
static func _bridge_crossing(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var ka := int(issue.get("road", -1))
	var kb := int(issue.get("road_b", ka))
	var sa := float(issue.get("s", 0.0))
	var sb := float(issue.get("s_b", sa))
	var a := _stretch(doc, b, ka, sa)
	var c := _stretch(doc, b, kb, sb)
	if a.is_empty() and c.is_empty():
		return []
	var pick := c
	if c.is_empty():
		pick = a
	elif not a.is_empty():
		if ka != kb and ka != -1 and kb == -1:
			pick = a
		elif ka != kb and kb != -1 and ka == -1:
			pick = c
		elif (a.full as Array).size() < (c.full as Array).size():
			pick = a
	return _raise_stretch(doc, b, pick)


## MAKE A BRIDGE (embankment): the stretch's open / street segments become the `bridge` style.
static func _bridge_embankment(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var key := int(issue.get("road", -1))
	var r := road_of(b, key)
	if r == null or r.n < 2:
		return []
	var s0 := float(issue.get("s", 0.0))
	var s1 := float(issue.get("s_end", s0))
	var i0 := r.idx(s0)
	var i1 := r.idx(s1)
	var count := posmod(i1 - i0, r.n) + 1 if r.closed else absi(i1 - i0) + 1
	var owners := {}
	for q in count:
		var i := r.wrap(i0 + q) if r.closed else clampi(mini(i0, i1) + q, 0, r.n - 1)
		owners[r.seg[i]] = true
	var kinds := _style_kinds(doc)
	var out := []
	for k in owners:
		var uid := _uid_of(r, int(k))
		var f := _point(doc, key, uid)
		if f.is_empty():
			continue
		var st := str(f.item.get("style", "asphalt"))
		if str(kinds.get(st, "open")) in ["open", "street"]:
			out.append(LevelDoc.op_set(point_path(key, uid) + ["style"], "bridge"))
	return out


## CLEAR THE GRID: in the 70 m behind the start line explicit banks go back to AUTO, jumps are
## removed and see-saw stretches are turned off (with their see-saws).
static func _clear_grid(doc: LevelDoc, b: LevelBuild) -> Array:
	var m := road_of(b, -1)
	if m == null or m.n < 3:
		return []
	var back := ceili(GRID_BACK / m.step) + 1
	var owners := {}
	for q in back + 1:
		owners[m.seg[m.wrap(-q)]] = true
	var out := []
	var banks := {}
	for k in owners:
		var pair := _seg_points(m, int(k))
		for uid in pair:
			banks[uid] = true
		if pair.is_empty():
			continue
		var uid: int = pair[0]
		var f := _point(doc, -1, uid)
		if f.is_empty():
			continue
		if f.item.get("gap") != null:
			out.append(LevelDoc.op_erase(point_path(-1, uid) + ["gap"]))
		if bool(f.item.get("seesaw", false)):
			out.append_array(LevelHazards.seesaw_ops(doc, uid, false))
	for uid in banks:
		var f := _point(doc, -1, uid)
		if not f.is_empty() and f.item.get("bank") != null:
			out.append(LevelDoc.op_erase(point_path(-1, uid) + ["bank"]))
	return out


## REMOVE THE JUMP (start_jump): the jumps of the segments at the start line.
static func _remove_jump(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var m := road_of(b, -1)
	var uids := {}
	if int(issue.get("uid", 0)) > 0:
		uids[int(issue.uid)] = true
	if m != null and m.n >= 3:
		for q in range(-3, 4):
			var i := m.wrap(q)
			if m.gap[i] == 1 or (m.lift.size() == m.n and m.lift[i] > 0.0):
				uids[_uid_of(m, m.seg[i])] = true
	var out := []
	for uid in uids:
		var f := _point(doc, -1, uid)
		if not f.is_empty() and f.item.get("gap") != null:
			out.append(LevelDoc.op_erase(point_path(-1, uid) + ["gap"]))
	return out


## SMOOTH HEIGHTS HERE: SMOOTH HEIGHTS over the 7 points round the spot, strength 1.
static func _smooth_here(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var key := int(issue.get("road", -1))
	var uid := int(issue.get("uid", 0))
	if _point(doc, key, uid).is_empty():
		var r := road_of(b, key)
		if r == null or r.n <= 0:
			return []
		uid = _uid_of(r, r.seg[r.idx(float(issue.get("s", 0.0)))])
	var pts := points_of(doc, key)
	var at := -1
	for k in pts.size():
		if pts[k] is Dictionary and int(pts[k].get("uid", 0)) == uid:
			at = k
	if at < 0:
		return []
	return smooth_ops(doc, key, 1.0, at, SMOOTH_POINTS)


## SMOOTH HEIGHTS (the ROAD tool's option and the fix): each point's height moves `strength` of
## the way to the average of the SMOOTH_WINDOW points round it (from the heights before the pass).
## `count` points centred on index `center` (count <= 0: every point).
static func smooth_ops(doc: LevelDoc, key: int, strength: float, center := 0, count := 0) -> Array:
	var pts := points_of(doc, key)
	var n := pts.size()
	if n < 3:
		return []
	var closed := key == -1 and bool(doc.data.road.get("closed", false))
	var ys := PackedFloat32Array()
	ys.resize(n)
	for k in n:
		ys[k] = _vec(pts[k].get("pos")).y
	var idx := []
	if count <= 0 or count >= n:
		for k in n:
			idx.append(k)
	else:
		var half := count / 2
		for d in range(-half, count - half):
			var k := center + d
			if closed:
				k = posmod(k, n)
			elif k < 0 or k >= n:
				continue
			if not k in idx:
				idx.append(k)
	var half_w := SMOOTH_WINDOW / 2
	var out := []
	for k in idx:
		var sum := 0.0
		var cnt := 0
		for d in range(-half_w, half_w + 1):
			var j: int = k + d
			if closed:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			sum += ys[j]
			cnt += 1
		var y := lerpf(ys[k], sum / maxf(cnt, 1), clampf(strength, 0.0, 1.0))
		if absf(y - ys[k]) < 1e-4:
			continue
		var p := _vec(pts[k].get("pos"))
		out.append(LevelDoc.op_set(point_path(key, int(pts[k].uid)) + ["pos"], [p.x, snappedf(y, 0.001), p.z]))
	return out


## RAISE ABOVE THE WATER: the points of the stretch that runs under the water go to its level +
## 1.5 m; the point either side is eased half way.
static func _raise_water(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var key := int(issue.get("road", -1))
	var r := road_of(b, key)
	if r == null or r.n < 2:
		return []
	var water = doc.data.get("water", {})
	var sea := water is Dictionary and bool(water.get("sea", false))
	var sea_y := float(water.get("level", 0.0)) if water is Dictionary else 0.0
	var lakes := []
	for l in doc.data.get("lakes", []):
		if l is Dictionary and l.get("center") is Array and l.get("size") is Array:
			var c := Vector2(float(l.center[0]), float(l.center[1]))
			var sz := Vector2(float(l.size[0]), float(l.size[1]))
			lakes.append([Rect2(c - sz * 0.5, sz), float(l.get("level", 0.0))])
	var level_at := func(i: int) -> float:
		var p := r.pos[i]
		var lv := -INF
		if sea and p.y < sea_y + WATER_TEST:
			lv = sea_y
		for l in lakes:
			if (l[0] as Rect2).has_point(Vector2(p.x, p.z)) and p.y < float(l[1]) + WATER_TEST:
				lv = maxf(lv, float(l[1]))
		return lv
	var i0 := r.idx(float(issue.get("s", 0.0)))
	var target := {}   # point uid -> height
	var limit := r.n
	# from the run's first sample forward (and back a little: the issue's s is its first sample)
	for dir in [1, -1]:
		var q := 0 if dir == 1 else -1
		while absi(q) < limit:
			var i := i0 + q
			if not r.closed and (i < 0 or i >= r.n):
				break
			i = r.wrap(i)
			var lv: float = level_at.call(i)
			if lv == -INF:
				break
			for uid in _seg_points(r, r.seg[i]):
				target[uid] = maxf(float(target.get(uid, -INF)), lv + WATER_CLEAR)
			q += dir
	if target.is_empty():
		return []
	var pts := points_of(doc, key)
	var n := pts.size()
	var closed := key == -1 and bool(doc.data.road.get("closed", false))
	var ys := {}
	for k in n:
		var uid := int(pts[k].get("uid", 0))
		if not target.has(uid):
			continue
		ys[uid] = maxf(_vec(pts[k].get("pos")).y, float(target[uid]))
		for d in [-1, 1]:
			var j: int = k + d
			if closed:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			var ou := int(pts[j].get("uid", 0))
			if target.has(ou):
				continue
			var oy := _vec(pts[j].get("pos")).y
			var eased := lerpf(oy, float(target[uid]), 0.5)
			ys[ou] = maxf(float(ys.get(ou, oy)), maxf(oy, eased))
	var out := []
	for k in n:
		var uid := int(pts[k].get("uid", 0))
		if not ys.has(uid):
			continue
		var p := _vec(pts[k].get("pos"))
		if float(ys[uid]) > p.y + 1e-4:
			out.append(LevelDoc.op_set(point_path(key, uid) + ["pos"], [p.x, snappedf(float(ys[uid]), 0.001), p.z]))
	return out


## MOVE TO A LEGAL SPOT: the branch's fork or merge anchor (the issue's `end`, else whichever is
## not legal) moved to the nearest exported sample of build.flags that allows it.
static func _legal_spot(issue: Dictionary, doc: LevelDoc, b: LevelBuild) -> Array:
	var buid := int(issue.get("branch", 0))
	if buid <= 0:
		buid = int(issue.get("uid", 0))
	var f := doc.find(buid)
	if f.is_empty() or str(f.get("section", "")) != "branches" or f.has("branch"):
		return []
	var m := road_of(b, -1)
	if m == null or m.n < 3:
		return []
	var ends: Array = [str(issue.end)] if str(issue.get("end", "")) in ["fork", "merge"] else ["fork", "merge"]
	var only_bad := not str(issue.get("end", "")) in ["fork", "merge"]
	var out := []
	for end in ends:
		var flags := legal_flags(b, end, buid)
		var a = f.item.get(end)
		if flags.is_empty() or not (a is Dictionary):
			continue
		var e := nearest_legal(m, flags, m.anchor_s(a), end)
		if e < 0:
			continue
		var cur := posmod(roundi(m.anchor_s(a) / (3.0 * m.step)), flags.size())
		if only_bad and flags[cur] == 1:
			continue
		var na := m.s_to_anchor(m.s[mini(e * 3, m.n - 1)])
		if na.is_empty():
			continue
		na.t = snappedf(float(na.t), T_STEP)
		out.append(LevelDoc.op_set(["branches", "#%d" % buid, end], na))
	return out


## build.flags for a branch end: the branch's own key when it is kept (its stretches not
## counting), else branch_fork / branch_merge.
static func legal_flags(b: LevelBuild, end: String, buid := 0) -> PackedByteArray:
	if b == null:
		return PackedByteArray()
	var own := "branch_%s_b%d" % [end, buid]
	if buid > 0 and b.flags.get(own) is PackedByteArray and not (b.flags[own] as PackedByteArray).is_empty():
		return b.flags[own]
	var k := "branch_" + end
	if b.flags.get(k) is PackedByteArray:
		return b.flags[k]
	return PackedByteArray()


## The exported sample nearest s_m (lap metres) whose flag is set, -1 when none is. With `end`
## ("fork" / "merge") the road must also lie flat (no bank, AUTO's included) over the shared
## stretch the branch lint walks (LEVEL_REACH metres ahead of a fork, behind a merge); without
## such a spot the flag alone decides.
static func nearest_legal(m: LevelRoad, flags: PackedByteArray, s_m: float, end := "") -> int:
	var ne := flags.size()
	if ne == 0 or m == null or m.step <= 0.0:
		return -1
	var e0 := posmod(roundi(s_m / (3.0 * m.step)), ne)
	var loose := -1
	for d in ne / 2 + 1:
		for e in [e0 + d, e0 - d]:
			var w := posmod(e, ne)
			if flags[w] != 1:
				continue
			if end == "" or _level_end(m, w * 3, end):
				return w
			if loose < 0:
				loose = w
	return loose


## The road has no bank over the LEVEL_REACH metres a branch end shares with it.
static func _level_end(m: LevelRoad, i: int, end: String) -> bool:
	if m.right.size() != m.n:
		return true
	var reach := ceili(LEVEL_REACH / maxf(m.step, 0.1))
	var dir := 1 if end == "fork" else -1
	for q in reach + 1:
		if absf(m.right[m.wrap(i + q * dir)].y) > 0.01:
			return false
	return true


# ---------------------------------------------------------------- helpers

## The bake to read (the given one, else a synchronous compile of the document).
static func _bake(doc: LevelDoc, build: LevelBuild) -> LevelBuild:
	if build != null and not build.partial:
		return build
	return LevelCompiler.compile(doc, {"id": "c_edit", "flags": true, "chunks": false})


static func road_of(b: LevelBuild, key: int) -> LevelRoad:
	if b == null:
		return null
	for r in b.roads:
		if r != null and r.key == key and not r.partial:
			return r
	return null


## The live point list of a road (-1 the main road, else a branch uid).
static func points_of(doc: LevelDoc, key: int) -> Array:
	if key == -1:
		var road = doc.data.get("road")
		if road is Dictionary and road.get("points") is Array:
			return road.points
		return []
	for br in doc.data.get("branches", []):
		if br is Dictionary and int(br.get("uid", 0)) == key and br.get("points") is Array:
			return br.points
	return []


## The document path of a point by uid.
static func point_path(key: int, uid: int) -> Array:
	if key == -1:
		return ["road", "points", "#%d" % uid]
	return ["branches", "#%d" % key, "points", "#%d" % uid]


## doc.find of a point on that road, {} when it is not one.
static func _point(doc: LevelDoc, key: int, uid: int) -> Dictionary:
	if uid <= 0:
		return {}
	var f := doc.find(uid)
	if f.is_empty():
		return {}
	if key == -1 and str(f.get("section", "")) == "road":
		return f
	if key != -1 and str(f.get("section", "")) == "branches" and f.has("branch") and int(f.get("road", -2)) == key:
		return f
	return {}


## The point uid owning segment k of a compiled road (0 for a branch's fork / merge end points).
static func _uid_of(r: LevelRoad, k: int) -> int:
	if k < 0 or k >= r.point_uids.size():
		return 0
	var u := r.point_uids[k]
	return u if u > 0 and (r.key == -1 or u != r.key) else 0


## The two point uids of segment k (its owner and the next point), real document points only.
static func _seg_points(r: LevelRoad, k: int) -> Array:
	var out := []
	var np := r.point_uids.size()
	if np == 0:
		return out
	for kk in [k, k + 1]:
		var j: int = posmod(kk, np) if r.src_closed else kk
		if j < 0 or j >= np:
			continue
		var u := _uid_of(r, j)
		if u > 0 and not u in out:
			out.append(u)
	return out


## Metres along a compiled road of a document point (NAN when it is not on it).
static func point_s(r: LevelRoad, uid: int) -> float:
	var k := -1
	for j in r.point_uids.size():
		if r.point_uids[j] == uid:
			k = j
			break
	if k < 0:
		return NAN
	if k < r.seg_first.size() and r.seg_first[k] >= 0:
		return r.s[r.seg_first[k]]
	if k == r.point_uids.size() - 1 and r.n > 0:
		return r.s[r.n - 1]
	return NAN


## |a - b| along a road (wrapped round a loop).
static func lap_d(a: float, b: float, length: float, closed: bool) -> float:
	var d := absf(a - b)
	if closed and length > 0.0:
		d = fposmod(d, length)
		d = minf(d, length - d)
	return d


## The points of a road within BRIDGE_REACH of s0 ({key, full: [uid], ease: {uid: f}, owners}).
static func _stretch(doc: LevelDoc, b: LevelBuild, key: int, s0: float) -> Dictionary:
	var r := road_of(b, key)
	if r == null or r.n < 2:
		return {}
	var full := []
	var ease := {}
	for p in points_of(doc, key):
		if not (p is Dictionary):
			continue
		var uid := int(p.get("uid", 0))
		var sp := point_s(r, uid)
		if is_nan(sp):
			continue
		var d := lap_d(sp, s0, r.length, r.closed)
		if d <= BRIDGE_REACH:
			full.append(uid)
		elif d < BRIDGE_REACH + EASE:
			ease[uid] = 1.0 - smoothstep(BRIDGE_REACH, BRIDGE_REACH + EASE, d)
	var owners := {}
	var i0 := r.idx(s0)
	var reach := ceili(BRIDGE_REACH / maxf(r.step, 0.1))
	for d in range(-reach, reach + 1):
		var i := i0 + d
		if not r.closed and (i < 0 or i >= r.n):
			continue
		var u := _uid_of(r, r.seg[r.wrap(i)])
		if u > 0:
			owners[u] = true
	if full.is_empty():
		for u in _seg_points(r, r.seg[i0]):
			full.append(u)
			ease.erase(u)
	if full.is_empty():
		return {}
	return {"key": key, "full": full, "ease": ease, "owners": owners.keys()}


static func _raise_stretch(doc: LevelDoc, b: LevelBuild, st: Dictionary) -> Array:
	var key := int(st.key)
	var out := []
	var kinds := _style_kinds(doc)
	for uid in st.full:
		var f := _point(doc, key, int(uid))
		if f.is_empty():
			continue
		var p := _vec(f.item.get("pos"))
		out.append(LevelDoc.op_set(point_path(key, int(uid)) + ["pos"], [p.x, snappedf(p.y + BRIDGE_RAISE, 0.001), p.z]))
	for uid in st.ease:
		var f := _point(doc, key, int(uid))
		if f.is_empty():
			continue
		var p := _vec(f.item.get("pos"))
		out.append(LevelDoc.op_set(point_path(key, int(uid)) + ["pos"],
			[p.x, snappedf(p.y + BRIDGE_RAISE * float(st.ease[uid]), 0.001), p.z]))
	for uid in st.owners:
		var f := _point(doc, key, int(uid))
		if f.is_empty():
			continue
		var sid := str(f.item.get("style", "asphalt"))
		if str(kinds.get(sid, "open")) in ["open", "street"]:
			out.append(LevelDoc.op_set(point_path(key, int(uid)) + ["style"], "bridge"))
	return out


## style id -> kind of every style the document can use.
static func _style_kinds(doc: LevelDoc) -> Dictionary:
	var out := {}
	var all := LevelStyles.resolve(doc.data, {})
	for id in all:
		out[id] = str(all[id].get("kind", "open"))
	return out


static func _vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
