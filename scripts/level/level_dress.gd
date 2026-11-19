class_name LevelDress
## AUTO DRESS (4.4): crate rows on the straights, boost pads at the exits of the two longest
## bends, rails on the outside of tight bends, a scatter of the theme's scenery beside every road
## and a grandstand at the start, each as doc ops (the editor pushes them as one undo step
## "AUTO DRESS"). It reads the last bake's roads (`build.roads`, `build.terrain`, `build.data`) and
## is seeded from the guid: the same track dresses the same way. Main thread (the scenery palette
## reads PropCatalog). P15.

const ROW_MIN := 350.0          # metres between two crate rows on the lap ...
const ROW_MAX := 450.0          # ... at most (when a straight is there)
const STRAIGHT := 1.0 / 150.0   # |curvature| under this ...
const STRAIGHT_SPAN := 30.0     # ... over this many metres is a straight
const GRID_BEFORE := 80.0       # no rows or pads this far behind the start line ...
const GRID_AFTER := 20.0        # ... or after it
const JUMP_CLEAR := 30.0        # rows keep this far from a jump gap ...
const JUNCTION_CLEAR := 30.0    # ... and from a branch's junction
const ROW_KEEP := 150.0         # an existing row this close stands for a new one
const PAD_CRATE := 10.0         # pads keep this far from crate rows
const PAD_JUMP := 16.0          # ... and from a jump
const PAD_KEEP := 30.0          # an existing pad this close to a bend's exit stands for a new one
const PAD_NUDGE := 60.0         # metres a pad may move on past the exit to find a clear spot
const BEND_MERGE := 10.0        # bends this close together are one bend
const SCENERY_NEAR := 8.0       # metres off the road edge ...
const SCENERY_FAR := 40.0       # ... to this
const SCENERY_EVERY := 30.0     # about one prop per this many metres per side
const SCENERY_BUDGET := 1500    # the soft budget of props (4.5)
const SCENERY_HAZARD := 6.0     # metres scenery keeps from a hazard
const SCENERY_ROAD := 2.0       # metres a prop's footprint keeps from any road (and its sides)
const SCENERY_SCALE := Vector2(0.8, 1.2)
const PALETTE_MAX := 12
const PALETTE_SIZE := Vector2(1.0, 12.0)
const STAND_LENGTH := 20.0      # the start grandstand ...
const STAND_ROWS := 2
const START_NEAR := 30.0        # a group this close to the start line already is one
const DEFAULT_THEME := "city17"

## What the last `ops` / `*_ops` call did: {rows, rows_kept, pads, pads_kept, rails, props,
## crowd} (the editor's toast).
static var last := {}


## AUTO DRESS: the five parts as one op list; opts {items, pads, rails, scenery, crowd: bool}
## (missing = on).
static func ops(doc: LevelDoc, build: LevelBuild, opts: Dictionary) -> Array:
	var out := []
	var counts := {}
	var planned := []
	if doc == null or build == null:
		last = counts
		return out
	if bool(opts.get("items", true)):
		var it := _items(doc, build)
		out.append_array(it.ops)
		planned = it.planned
		counts.merge(it.counts)
	if bool(opts.get("pads", true)):
		var pd := _pads(doc, build, planned)
		out.append_array(pd.ops)
		counts.merge(pd.counts)
	if bool(opts.get("rails", true)):
		var rl := rails_ops(doc, build)
		out.append_array(rl)
		counts["rails"] = rl.size()
	if bool(opts.get("scenery", true)):
		var sc := scenery_ops(doc, build, str(doc.data.get("theme", "")))
		out.append_array(sc)
		counts["props"] = sc.size()
	if bool(opts.get("crowd", true)):
		var cr := crowd_ops(doc, build)
		out.append_array(cr)
		counts["crowd"] = cr.size()
	last = counts
	return out


## AUTO ITEMS: crate rows every 350-450 m on the main loop's straights (off the grid, jumps and
## junctions), one per branch at its middle.
static func items_ops(doc: LevelDoc, build: LevelBuild) -> Array:
	var it := _items(doc, build)
	last = it.counts
	return it.ops


## Boost pads on the racing line at the exits of the two longest bends.
static func pads_ops(doc: LevelDoc, build: LevelBuild) -> Array:
	var pd := _pads(doc, build, [])
	last = pd.counts
	return pd.ops


## RAILS ON TIGHT BENDS: a RAIL override on the outside of every segment whose radius is under
## `radius` and whose outside has no barrier (tunnels, bridges, jumps and see-saws left alone;
## an author's own override, NONE included, is kept).
static func rails_ops(doc: LevelDoc, build: LevelBuild, radius := 60.0) -> Array:
	var out := []
	if doc == null or build == null:
		return out
	for r in build.roads:
		if r == null or r.partial or r.n < 3:
			continue
		for k in r.segments():
			var ids := _seg_samples(r, k)
			if ids.size() < 2:
				continue
			var cmax := 0.0
			var turn := 0.0
			var skip := false
			for j in ids:
				var kind := r.kind(j)
				if kind == "tunnel" or kind == "bridge" or r.gap[j] == 1 or r.skip[j] == 1 or r.seesaw[j] == 1:
					skip = true
					break
				cmax = maxf(cmax, absf(r.curv[j]))
				var nx := r.wrap(j + 1)
				if r.closed or j + 1 < r.n:
					turn += r.fwd[nx].dot(r.flat_right[j])
			if skip or cmax <= 1e-6 or 1.0 / cmax >= radius:
				continue
			# turning right: the outside is the left
			var side := "barrier_l" if turn > 0.0 else "barrier_r"
			var bars := r.bar_l if side == "barrier_l" else r.bar_r
			var has_bar := false
			for j in ids:
				if bars[j] >= 0:
					has_bar = true
					break
			if has_bar or k >= r.point_uids.size():
				continue
			var puid := r.point_uids[k]
			var path := _point_path(doc, r.key, puid)
			if path.is_empty():
				continue
			var pt = doc.get_at(path)
			if not (pt is Dictionary) or (pt as Dictionary).get(side) != null:
				continue
			path.append(side)
			out.append(LevelDoc.op_set(path, LevelStyles.barrier("rail")))
	return out


## SCENERY: the theme's palette scattered beside every road, 8-40 m off the edge, about one per
## 30 m per side, on the ground, random yaw and scale 0.8-1.2; never in a road's bed, a lake,
## the sea, the grid or 6 m of a hazard; up to 1500 props in all. Needs terrain.
static func scenery_ops(doc: LevelDoc, build: LevelBuild, theme_id: String) -> Array:
	var out := []
	if doc == null or build == null or build.terrain == null or build.roads.is_empty():
		return out
	var pal := palette(theme_id)
	if pal.is_empty():
		return out
	var props: Array = doc.data.get("props", [])
	var room := SCENERY_BUDGET - props.size()
	if room <= 0:
		return out
	var rng := _rng(doc, "scenery")
	var hash := _Samples.new(build.roads)
	var taken := _Taken.new()
	for p in props:
		if p is Dictionary:
			taken.add(_v3(p.get("pos")), _foot(str(p.get("model", "")), float(p.get("scale", 1.0))))
	var hz := _hazard_points(doc, build)
	var lakes: Array = doc.data.get("lakes", [])
	var water = doc.data.get("water", {})
	var sea := float(water.get("level", 0.0)) if water is Dictionary and bool(water.get("sea", false)) else -INF
	var half := doc.world_size() * 0.5
	var main := _main(build)
	var zone := _grid_zone(main)
	var t := build.terrain
	var group := 0
	var at := props.size()
	for r in build.roads:
		if r == null or r.n < 2 or out.size() >= room:
			continue
		var s := rng.randf_range(0.0, SCENERY_EVERY)
		while s < r.length and out.size() < room:
			for side in [-1, 1]:
				if out.size() >= room:
					break
				var key := pal[rng.randi() % pal.size()]
				var off := rng.randf_range(SCENERY_NEAR, SCENERY_FAR)
				var along := rng.randf_range(-SCENERY_EVERY * 0.3, SCENERY_EVERY * 0.3)
				var yaw := snappedf(rng.randf_range(0.0, 360.0), 0.1)
				var sc := snappedf(rng.randf_range(SCENERY_SCALE.x, SCENERY_SCALE.y), 0.05)
				var i := r.idx(s + along)
				var edge := r.width[i] * 0.5 + r.treatment(i, side)
				var q := r.pos[i] + r.flat_right[i] * float(side) * (edge + off)
				var foot := _foot(key, sc)
				if absf(q.x) > half - foot or absf(q.z) > half - foot:
					continue
				var y := _stand(t, q, foot)
				if is_nan(y) or y < sea + 0.3:
					continue
				q.y = y
				if hash.gap(q, SCENERY_FAR + 30.0) < foot + SCENERY_ROAD:
					continue
				if _in_lake(lakes, q, foot) or _near_any(hz, q, SCENERY_HAZARD + foot):
					continue
				if _near_any(zone, q, SCENERY_FAR + foot + 10.0 + (main.width[0] * 0.5 if main != null else 0.0)):
					continue
				if taken.hit(q, foot):
					continue
				if group == 0:
					group = doc.new_uid()
				taken.add(q, foot)
				var p := {"uid": doc.new_uid(), "model": key, "pos": _r3(q), "yaw": yaw, "pitch": 0.0, "roll": 0.0,
					"scale": sc, "physics": false, "tag": "", "group": group}
				out.append(LevelDoc.op_insert(["props"], at + out.size(), p))
			s += SCENERY_EVERY
	return out


## CROWD: a grandstand at the start (both sides, 20 m, 2 rows, citizens, FANS, CHEER THE START)
## unless the start already has a group.
static func crowd_ops(doc: LevelDoc, build: LevelBuild) -> Array:
	var out := []
	if doc == null or build == null:
		return out
	var m := _main(build)
	var road = doc.data.get("road", {})
	if m == null or not (road is Dictionary) or not (road.get("start") is Dictionary):
		return out
	var crowds: Array = doc.data.get("crowds", [])
	for g in crowds:
		if not (g is Dictionary) or int(g.get("road", -1)) != -1:
			continue
		var tags = g.get("tags", [])
		if (tags is Array and "start" in tags) or (g.get("at") is Dictionary and _lap_d(m.anchor_s(g.at), 0.0, m.length) <= START_NEAR):
			return out
	var at := 0
	for side in [-1, 1]:
		var g := {"uid": doc.new_uid(), "road": -1, "at": (road.start as Dictionary).duplicate(), "side": side,
			"length": STAND_LENGTH, "rows": STAND_ROWS, "density": 1.0, "setback": 2.5, "role": "citizen",
			"mood": "fan", "sit": 0.0, "tags": ["start"]}
		out.append(LevelDoc.op_insert(["crowds"], crowds.size() + at, g))
		at += 1
	return out


## Up to 12 models of the theme's scenery categories with a catalog size of 1-12 m, static (not
## a physics prop) and not animated, every k-th by key order. Empty without a catalog.
static func palette(theme_id: String) -> PackedStringArray:
	var cats := LevelThemes.categories(theme_id)
	if cats.is_empty():
		cats = LevelThemes.categories(DEFAULT_THEME)
	var all := PropCatalog.facts()
	var ks := all.keys()
	ks.sort()
	var cand := PackedStringArray()
	for k in ks:
		var f: Dictionary = all[k]
		var size := float(f.get("size", 0.0))
		if str(f.get("category", "")) in cats and size >= PALETTE_SIZE.x and size <= PALETTE_SIZE.y \
				and not bool(f.get("skinned", false)) and not bool(f.get("physics_ok", false)):
			cand.append(str(k))
	var out := PackedStringArray()
	if cand.is_empty():
		return out
	var every := maxi(1, cand.size() / PALETTE_MAX)
	var i := 0
	while i < cand.size() and out.size() < PALETTE_MAX:
		out.append(cand[i])
		i += every
	return out


# ---------------------------------------------------------------- items and pads

## {ops, planned: [main-road metres of the rows to come and the kept ones], counts}
static func _items(doc: LevelDoc, build: LevelBuild) -> Dictionary:
	var res := {"ops": [], "planned": [], "counts": {"rows": 0, "rows_kept": 0}}
	var m := _main(build)
	if doc == null or m == null:
		return res
	var items: Array = doc.data.get("items", [])
	var have := []
	var branch_rows := {}
	for it in items:
		if not (it is Dictionary) or not (it.get("at") is Dictionary):
			continue
		var rk := int(it.get("road", -1))
		if rk == -1:
			have.append(m.anchor_s(it.at))
		else:
			branch_rows[rk] = true
	var ok := _row_mask(m, build)
	var rng := _rng(doc, "items")
	var L := m.length
	var spots := []
	var first := -1
	for i in m.n:
		if ok[i] == 1:
			first = i
			break
	if first >= 0:
		var s0 := m.s[first]
		var pick := _valid_from(m, ok, s0 + rng.randf_range(0.0, 30.0), s0 + 60.0)
		if pick < 0.0:
			pick = s0
		spots.append(pick)
		var stop := pick + L - ROW_MIN
		var last_s := pick
		while true:
			var lo := last_s + ROW_MIN
			if lo > stop:
				break
			var target := last_s + rng.randf_range(ROW_MIN, ROW_MAX)
			var nxt := _valid_near(m, ok, target, lo, minf(last_s + ROW_MAX, stop))
			if nxt < 0.0:
				nxt = _valid_from(m, ok, last_s + ROW_MAX, stop)
			if nxt < 0.0:
				break
			spots.append(nxt)
			last_s = nxt
	var out := []
	var add := []
	for s in spots:
		var kept := false
		for h in have:
			if _lap_d(s, h, L) <= ROW_KEEP:
				kept = true
				break
		if kept:
			res["counts"]["rows_kept"] += 1
			continue
		var s_m := fposmod(float(s), L)
		add.append(s_m)
		out.append(LevelDoc.op_insert(["items"], items.size() + out.size(),
			{"uid": doc.new_uid(), "road": -1, "at": m.s_to_anchor(s_m), "count": 0, "inset": 2.5}))
	for r in build.roads:
		if r == null or r.key == -1 or r.n < 2 or branch_rows.has(r.key):
			continue
		var i := _clear_near(r, r.idx(r.length * 0.5), maxi(1, r.n / 4))
		if i < 0:
			continue
		out.append(LevelDoc.op_insert(["items"], items.size() + out.size(),
			{"uid": doc.new_uid(), "road": r.key, "at": r.s_to_anchor(r.s[i]), "count": 0, "inset": 2.5}))
	res.ops = out
	res["counts"]["rows"] = out.size()
	var planned := have.duplicate()
	planned.append_array(add)
	res.planned = planned
	return res


## Samples of the main loop a crate row may sit on: straights, off the grid, jumps, junctions,
## see-saws and holes.
static func _row_mask(m: LevelRoad, build: LevelBuild) -> PackedByteArray:
	var n := m.n
	var bend := PackedByteArray()
	bend.resize(n)
	var jump := PackedByteArray()
	jump.resize(n)
	var junc := PackedByteArray()
	junc.resize(n)
	for i in n:
		bend[i] = 1 if absf(m.curv[i]) >= STRAIGHT else 0
		jump[i] = 1 if m.gap[i] == 1 else 0
		junc[i] = 1 if m.junction.size() > i and m.junction[i] == 1 else 0
	var br = build.data.get("branches", []) if build.data is Dictionary else []
	if br is Array:
		for e in br:
			if e is Dictionary:
				for k in ["fork_s", "merge_s"]:
					if e.has(k):
						junc[m.idx(float(e[k]))] = 1
	var d_bend := _dist(bend, m.closed)
	var d_jump := _dist(jump, m.closed)
	var d_junc := _dist(junc, m.closed)
	var ok := PackedByteArray()
	ok.resize(n)
	var st := maxf(m.step, 0.01)
	for i in n:
		var s := m.s[i]
		var good := d_bend[i] * st > STRAIGHT_SPAN * 0.5 and d_jump[i] * st > JUMP_CLEAR and d_junc[i] * st > JUNCTION_CLEAR
		good = good and m.skip[i] == 0 and m.seesaw[i] == 0 and not _in_grid_s(s, m.length)
		ok[i] = 1 if good else 0
	return ok


## {ops, counts}: pads at the exits of the two longest bends, clear of rows (doc + planned).
static func _pads(doc: LevelDoc, build: LevelBuild, planned: Array) -> Dictionary:
	var res := {"ops": [], "counts": {"pads": 0, "pads_kept": 0}}
	var m := _main(build)
	if doc == null or m == null:
		return res
	var rows := planned.duplicate()
	if rows.is_empty():
		for it in doc.data.get("items", []):
			if it is Dictionary and int(it.get("road", -1)) == -1 and it.get("at") is Dictionary:
				rows.append(m.anchor_s(it.at))
	var pads: Array = doc.data.get("pads", [])
	var have := []
	for p in pads:
		if p is Dictionary and int(p.get("road", -1)) == -1 and p.get("at") is Dictionary:
			have.append(m.anchor_s(p.at))
	var jump := PackedByteArray()
	jump.resize(m.n)
	for i in m.n:
		jump[i] = m.gap[i]
	var d_jump := _dist(jump, m.closed)
	var out := []
	for e in bends(m).slice(0, 2):
		var s_exit := m.s[int(e.exit)]
		var kept := false
		for h in have:
			if _lap_d(s_exit, h, m.length) <= PAD_KEEP:
				kept = true
				break
		if kept:
			res["counts"]["pads_kept"] += 1
			continue
		var s := s_exit
		var found := -1.0
		while s <= s_exit + PAD_NUDGE:
			var i := m.idx(s)
			var clear := not _in_grid_s(m.s[i], m.length) and d_jump[i] * m.step > PAD_JUMP and m.skip[i] == 0
			for rs in rows:
				if _lap_d(m.s[i], rs, m.length) < PAD_CRATE:
					clear = false
					break
			if clear:
				found = m.s[i]
				break
			s += m.step
		if found < 0.0:
			continue
		out.append(LevelDoc.op_insert(["pads"], pads.size() + out.size(),
			{"uid": doc.new_uid(), "road": -1, "at": m.s_to_anchor(found), "lat": null, "turn": 0.0}))
	res.ops = out
	res["counts"]["pads"] = out.size()
	return res


## The bends of a road, longest first: [{start, exit, length}] (sample indices; exit = the
## first straight sample after the bend). Bends closer than 10 m are one.
static func bends(r: LevelRoad) -> Array:
	var n := r.n
	var out := []
	if n < 3:
		return out
	var bend := PackedByteArray()
	bend.resize(n)
	var any_straight := false
	for i in n:
		bend[i] = 1 if absf(r.curv[i]) >= STRAIGHT else 0
		if bend[i] == 0:
			any_straight = true
	if not any_straight:
		return out
	# start the walk on a straight sample so no run is cut by the wrap
	var s0 := 0
	if r.closed:
		while bend[s0] == 1:
			s0 += 1
	var runs := []
	var i := 0
	var count := n if r.closed else n - s0
	while i < count:
		var j := s0 + i
		if bend[r.wrap(j)] == 1:
			var a := j
			while i < count and bend[r.wrap(s0 + i)] == 1:
				i += 1
			runs.append([a, s0 + i])
		else:
			i += 1
	# merge runs split by a short straight
	var merge := roundi(BEND_MERGE / maxf(r.step, 0.01))
	var merged := []
	for run in runs:
		if not merged.is_empty() and int(run[0]) - int(merged[-1][1]) <= merge:
			merged[-1][1] = run[1]
		else:
			merged.append(run)
	if r.closed and merged.size() > 1 and int(merged[0][0]) + n - int(merged[-1][1]) <= merge:
		merged[0][0] = int(merged[-1][0]) - n
		merged.pop_back()
	for run in merged:
		var a: int = run[0]
		var b: int = run[1]
		if not r.closed and b >= n:
			continue
		out.append({"start": r.wrap(a), "exit": r.wrap(b), "length": (b - a) * r.step})
	out.sort_custom(func(x, y): return float(x.length) > float(y.length) or (float(x.length) == float(y.length) and int(x.start) < int(y.start)))
	return out


# ---------------------------------------------------------------- helpers

static func _main(build: LevelBuild) -> LevelRoad:
	if build == null:
		return null
	for r in build.roads:
		if r != null and r.key == -1 and r.closed and r.n >= 3 and not r.partial:
			return r
	return null


## The doc path of a road point by uid ([] when it is not there).
static func _point_path(doc: LevelDoc, road_key: int, puid: int) -> Array:
	var f := doc.find(puid)
	if f.is_empty():
		return []
	if road_key == -1 and str(f.get("section", "")) == "road":
		return ["road", "points", "#%d" % puid]
	if road_key != -1 and str(f.get("section", "")) == "branches" and int(f.get("road", 0)) == road_key:
		return ["branches", "#%d" % road_key, "points", "#%d" % puid]
	return []


## The dense samples of segment k in order.
static func _seg_samples(r: LevelRoad, k: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if k >= r.seg_first.size() or r.seg_first[k] < 0:
		return out
	var i := r.seg_first[k]
	var guard := 0
	while guard < r.n and r.seg[i] == k:
		out.append(i)
		guard += 1
		if i + 1 >= r.n and not r.closed:
			break
		i = r.wrap(i + 1)
	return out


## Samples (cyclic when closed) from each sample to the nearest flagged one (INF without any).
static func _dist(flag: PackedByteArray, closed: bool) -> PackedFloat32Array:
	var n := flag.size()
	var d := PackedFloat32Array()
	d.resize(n)
	d.fill(INF)
	var any := false
	for i in n:
		if flag[i] == 1:
			d[i] = 0.0
			any = true
	if not any:
		return d
	var passes := 2 if closed else 1
	for _p in passes:
		for k in n:
			var i := k
			var j := i - 1
			if j < 0:
				if not closed:
					continue
				j = n - 1
			d[i] = minf(d[i], d[j] + 1.0)
		for k in n:
			var i := n - 1 - k
			var j := i + 1
			if j >= n:
				if not closed:
					continue
				j = 0
			d[i] = minf(d[i], d[j] + 1.0)
	return d


## The first sample at or after s_from (lap metres, may pass the lap end) that is ok, up to s_to;
## its metres (unwrapped), -1 when none.
static func _valid_from(m: LevelRoad, ok: PackedByteArray, s_from: float, s_to: float) -> float:
	var s := s_from
	while s <= s_to:
		if ok[m.idx(s)] == 1:
			return s
		s += m.step
	return -1.0


## The ok sample within [lo, hi] nearest to target (unwrapped metres), -1 when none.
static func _valid_near(m: LevelRoad, ok: PackedByteArray, target: float, lo: float, hi: float) -> float:
	var best := -1.0
	var bd := INF
	var s := lo
	while s <= hi:
		if ok[m.idx(s)] == 1 and absf(s - target) < bd:
			bd = absf(s - target)
			best = s
		s += m.step
	return best


## The sample nearest i (within `reach`) that is not a jump, hole or junction; -1 when none.
static func _clear_near(r: LevelRoad, i: int, reach: int) -> int:
	for k in reach + 1:
		for sg: int in [1, -1]:
			var j := i + sg * k
			if not r.closed and (j < 0 or j >= r.n):
				continue
			j = r.wrap(j)
			if r.gap[j] == 0 and r.skip[j] == 0 and (r.junction.size() <= j or r.junction[j] == 0):
				return j
	return -1


static func _in_grid_s(s: float, length: float) -> bool:
	var u := fposmod(s, length)
	return u <= GRID_AFTER or u >= length - GRID_BEFORE


## The main road's samples along the grid (80 m behind the start line to 20 m after it).
static func _grid_zone(m: LevelRoad) -> PackedVector3Array:
	var out := PackedVector3Array()
	if m == null:
		return out
	for i in m.n:
		if _in_grid_s(m.s[i], m.length):
			out.append(m.pos[i])
	return out


static func _lap_d(a: float, b: float, length: float) -> float:
	var d := fposmod(a - b, length)
	return minf(d, length - d)


## The ground a prop of footprint foot stands on at q: the lowest of its centre and four points
## round it (so no corner floats); NAN off the terrain.
static func _stand(t: LevelTerrain, q: Vector3, foot: float) -> float:
	var y := t.height_at(q.x, q.z)
	if is_nan(y):
		return NAN
	var r := foot * 0.5
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var g := t.height_at(q.x + d.x, q.z + d.y)
		if is_nan(g):
			return NAN
		y = minf(y, g)
	return y


## A model's plan footprint radius at a scale (the catalog's, 1 m when unknown).
static func _foot(key: String, sc: float) -> float:
	var f := PropCatalog.fact(key)
	return maxf(0.5, float(f.get("foot", 1.0))) * maxf(sc, 0.05)


static func _in_lake(lakes: Array, q: Vector3, foot: float) -> bool:
	for l in lakes:
		if not (l is Dictionary) or not (l.get("center") is Array) or not (l.get("size") is Array):
			continue
		if absf(q.x - float(l.center[0])) <= float(l.size[0]) * 0.5 + foot \
				and absf(q.z - float(l.center[1])) <= float(l.size[1]) * 0.5 + foot:
			return true
	return false


static func _near_any(pts: PackedVector3Array, q: Vector3, r: float) -> bool:
	for p in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < r:
			return true
	return false


## Where the hazards stand: the doc's anchored ones beside their road, and every point of the
## last bake's runtime entries.
static func _hazard_points(doc: LevelDoc, build: LevelBuild) -> PackedVector3Array:
	var out := PackedVector3Array()
	var m := _main(build)
	for h in doc.data.get("hazards", []):
		if not (h is Dictionary) or m == null or not (h.get("at") is Dictionary):
			continue
		var i := m.anchor_i(h.at)
		var side := int(h.get("side", 0))
		var q := m.pos[i]
		if side != 0:
			q += m.flat_right[i] * signf(side) * (m.width[i] * 0.5 + float(h.get("setback", 0.0)))
		out.append(q)
	var hz = build.data.get("hazards", []) if build.data is Dictionary else []
	if hz is Array:
		var found := []
		for e in hz:
			if e is Dictionary:
				for v in (e as Dictionary).values():
					_points_in(v, found, 0)
		for q in found:
			out.append(q)
	return out


## Every [x, y, z] in v (nested up to two lists deep) appended to out.
static func _points_in(v: Variant, out: Array, depth: int) -> void:
	if depth > 2 or not (v is Array):
		return
	var a: Array = v
	if a.size() == 3 and (a[0] is float or a[0] is int) and (a[1] is float or a[1] is int) and (a[2] is float or a[2] is int):
		out.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
		return
	for e in a:
		_points_in(e, out, depth + 1)


## A generator seeded from the guid and a tag (the same scheme as LevelContext.seed_of).
static func _rng(doc: LevelDoc, tag: String) -> RandomNumberGenerator:
	var h := ("%s:dress:%s" % [str(doc.data.get("guid", "")), tag]).sha256_buffer()
	var r := RandomNumberGenerator.new()
	r.seed = ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) & 0x7fffffff
	return r


static func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## Road samples in a plan hash: the gap from a spot to the nearest road's sides.
class _Samples:
	const CELL := 16.0
	var roads: Array = []
	var grid := {}

	func _init(rs: Array) -> void:
		roads = rs
		for ri in rs.size():
			var r: LevelRoad = rs[ri]
			if r == null:
				continue
			for i in r.n:
				var k := Vector2i(floori(r.pos[i].x / CELL), floori(r.pos[i].z / CELL))
				if not grid.has(k):
					grid[k] = []
				(grid[k] as Array).append((ri << 20) | i)

	## Plan metres from q past the nearest road's edge and side treatment (INF beyond `reach`).
	func gap(q: Vector3, reach: float) -> float:
		var c := Vector2i(floori(q.x / CELL), floori(q.z / CELL))
		var cr := int(ceil(reach / CELL))
		var best := INF
		for dx in range(-cr, cr + 1):
			for dz in range(-cr, cr + 1):
				var k := Vector2i(c.x + dx, c.y + dz)
				if not grid.has(k):
					continue
				for code in grid[k]:
					var r: LevelRoad = roads[code >> 20]
					var i: int = code & 0xfffff
					var d := Vector3(q.x - r.pos[i].x, 0.0, q.z - r.pos[i].z)
					var lat := d.dot(r.flat_right[i])
					var fw := Vector3(r.fwd[i].x, 0.0, r.fwd[i].z).normalized()
					var along := absf(d.dot(fw))
					var side := 1 if lat >= 0.0 else -1
					var edge := r.width[i] * 0.5 + r.treatment(i, side)
					var g := absf(lat) - edge if along <= r.step * 0.6 else d.length() - edge
					best = minf(best, g)
		return best


## Spots already taken by props (plan circles in a hash).
class _Taken:
	const CELL := 8.0
	var grid := {}

	func add(q: Vector3, r: float) -> void:
		var k := Vector2i(floori(q.x / CELL), floori(q.z / CELL))
		if not grid.has(k):
			grid[k] = []
		(grid[k] as Array).append([q, r])

	## Whether a prop of radius r at q would overlap a taken one (1 m apart at least); radii up to
	## 3 cells away are looked at.
	func hit(q: Vector3, r: float) -> bool:
		var c := Vector2i(floori(q.x / CELL), floori(q.z / CELL))
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				for e in grid.get(Vector2i(c.x + dx, c.y + dz), []):
					var p: Vector3 = e[0]
					if Vector2(p.x - q.x, p.z - q.z).length() < r + float(e[1]) + 1.0:
						return true
		return false
