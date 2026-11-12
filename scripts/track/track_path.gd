class_name TrackPath
extends RefCounted
## Sampled centre line + racing line of a circuit (written by tools/build_track.py).
## The main loop is closed (distances wrap at `length`); a branch (TrackBranch) is an open
## path whose distances clamp to 0..length. The main loop also owns the branches.

var center := PackedVector3Array()
var line := PackedVector3Array()
var fwd := PackedVector3Array()
var right := PackedVector3Array()
var up := PackedVector3Array()
var width := PackedFloat32Array()
var speed := PackedFloat32Array()
var gap := PackedByteArray()
## 1 where falling below the road means leaving the track (open edges, jumps)
var pit := PackedByteArray()
## tube stretches: the pipe's radius (gravity pulls towards its wall), 0 elsewhere
var mag := PackedFloat32Array()
## liquids with no floor a kart can fall into (Black Mesa's slime pits and coolant pool):
## surface height under the road (jump pits, pools) and beside it (side channels),
## -1000 where there is none; the kind is 0 none, 1 water, 2 slime
var liquid := PackedFloat32Array()
var liquid_side := PackedFloat32Array()
var liquid_kind := PackedByteArray()
var theme: Array = []
var step := 6.0
var length := 1000.0
var n := 0
var closed := true
## shortcuts and alternative roads of the main loop (Track.build: add_branches)
var branches: Array[TrackBranch] = []
var _junction_ids := {}  # main sample index -> branch indices whose fork or merge zone covers it


## `open`: a branch (TrackBranch), whatever the data says.
func _init(d: Dictionary, open := false) -> void:
	step = d["step"]
	length = d["length"]
	closed = not open and bool(d.get("closed", true))
	for p in d["center"]:
		center.append(Vector3(p[0], p[1], p[2]))
	for p in d["line"]:
		line.append(Vector3(p[0], p[1], p[2]))
	for p in d["fwd"]:
		fwd.append(Vector3(p[0], p[1], p[2]))
	for p in d["right"]:
		right.append(Vector3(p[0], p[1], p[2]))
	for p in d["up"]:
		up.append(Vector3(p[0], p[1], p[2]))
	for w in d["width"]:
		width.append(w)
	for v in d["speed"]:
		speed.append(v)
	for g in d["gap"]:
		gap.append(g)
	for g in d.get("pit", d["gap"]):
		pit.append(g)
	for r in d.get("mag", []):
		mag.append(r)
	if mag.size() != gap.size():
		mag.resize(gap.size())
		mag.fill(0.0)
	for v in d.get("liquid", []):
		liquid.append(v)
	for v in d.get("liquid_side", []):
		liquid_side.append(v)
	for v in d.get("liquid_kind", []):
		liquid_kind.append(v)
	if liquid.size() != gap.size() or liquid_side.size() != gap.size() or liquid_kind.size() != gap.size():
		# track data from before liquids were exported
		liquid.resize(gap.size())
		liquid.fill(-1000.0)
		liquid_side.resize(gap.size())
		liquid_side.fill(-1000.0)
		liquid_kind.resize(gap.size())
		liquid_kind.fill(0)
	theme = d["theme"]
	n = center.size()
	set_closed(closed)


## A loop spreads its samples evenly over `length`; an open path keeps the exported step,
## with a shorter last interval when its end is not on the step (every 3rd sample + the end).
func set_closed(c: bool) -> void:
	closed = c
	if closed:
		step = length / n
	elif step * (n - 2) > length + 0.01 or step * (n - 1) < length - 0.01:
		step = length / maxf(n - 1, 1)


func wi(i: int) -> int:
	return posmod(i, n) if closed else clampi(i, 0, n - 1)


## Metres along the path of sample i.
func u_of(i: int) -> float:
	if closed:
		return wi(i) * step
	return length if i >= n - 1 else maxf(i, 0) * step


## Fractional sample index of `s` metres along the path (wraps on a loop, clamps when open).
func _frac(s: float) -> float:
	if closed:
		return fposmod(s, length) / step
	var last := (n - 2) * step
	s = clampf(s, 0.0, length)
	if s <= last:
		return s / step
	return n - 2 + (s - last) / maxf(length - last, 0.001)


## Closest sample index; with a hint only a window around it is searched.
func closest(p: Vector3, hint := -1) -> int:
	var best := 0
	var bd := INF
	if hint < 0:
		for i in n:
			var d := p.distance_squared_to(center[i])
			if d < bd:
				bd = d
				best = i
		return best
	# stay on the same stretch: a part of the lap that passes close by (a hairpin,
	# an overpass) must not steal the kart, so height counts double and every
	# sample away from the hint costs a little
	for k in range(-12, 25):
		var i := wi(hint + k)
		var dv := p - center[i]
		var d := dv.x * dv.x + dv.z * dv.z + 4.0 * dv.y * dv.y + absf(k) * step * 0.5
		if d < bd:
			bd = d
			best = i
	return best


## Distance along the lap (0..length) for a point near sample i: where the point lies between
## the cross-section planes of sample i and its neighbour, so it runs on smoothly from one
## sample to the next even well off the centre line in a bend.
func progress(p: Vector3, i: int) -> float:
	i = wi(i)
	var d := (p - center[i]).dot(fwd[i])
	var s := u_of(i) + d
	var j := i + (1 if d >= 0.0 else -1)
	if closed or (j >= 0 and j < n):
		j = wi(j)
		var dj := (p - center[j]).dot(fwd[j])
		var seg := step if closed else absf(u_of(j) - u_of(i))
		if d >= 0.0 and dj < 0.0:
			s = u_of(i) + seg * d / (d - dj)
		elif d < 0.0 and dj >= 0.0:
			s = u_of(i) - seg * d / (d - dj)
	return fposmod(s, length) if closed else clampf(s, 0.0, length)


func lateral(p: Vector3, i: int) -> float:
	return (p - center[i]).dot(right[i])


func index_at(s: float) -> int:
	return wi(int(floor(_frac(s))))


func center_at(s: float) -> Vector3:
	var f := _frac(s)
	var i := int(floor(f))
	var t := f - i
	return center[wi(i)].lerp(center[wi(i + 1)], t)


func line_at(s: float) -> Vector3:
	var f := _frac(s)
	var i := int(floor(f))
	var t := f - i
	return line[wi(i)].lerp(line[wi(i + 1)], t)


func transform_at(s: float) -> Transform3D:
	var i := index_at(s)
	var f := fwd[i]
	var u := up[i]
	var r := f.cross(u).normalized()
	var b := Basis(r, u, -f)
	return Transform3D(b, center_at(s))


# ---------------------------------------------------------------- branches
## Branches from the track JSON (data["branches"]): a TrackBranch per entry.
func add_branches(list: Array) -> void:
	for d in list:
		var k := branches.size()
		var b := TrackBranch.new(d, k)
		if b.fork_i < 0:
			b.fork_i = index_at(b.fork_s)
		if b.merge_i < 0:
			b.merge_i = index_at(b.merge_s)
		if b.fork_nose_i < 0:
			b.fork_nose_i = index_at(b.main_s(b.fork_nose_u))
		if b.merge_nose_i < 0:
			b.merge_nose_i = index_at(b.main_s(b.merge_nose_u))
		branches.append(b)
		for i in range(b.fork_i - 2, b.fork_nose_i + 3):
			(_junction_ids.get_or_add(wi(i), []) as Array).append(k)
		for i in range(b.merge_nose_i - 2, b.merge_i + 3):
			(_junction_ids.get_or_add(wi(i), []) as Array).append(k)


## The road of a route: the main loop for -1, else that branch.
func geo(route: int) -> TrackPath:
	return self if route < 0 else branches[route]


## Branches whose fork or merge zone covers main sample i.
func junctions_near(i: int) -> Array:
	return _junction_ids.get(i, [])


## 0 on the road surface at sample i, otherwise roughly the metres off it: sideways past the
## edge, height above / below it counted double, and past either end of an open path.
func on_road(p: Vector3, i: int) -> float:
	i = wi(i)
	if mag[i] > 0.0:
		var axis := center[i] + up[i] * mag[i]
		var r := (p - axis - fwd[i] * (p - axis).dot(fwd[i])).length()
		return maxf(absf(r - mag[i]) - 2.0, 0.0)
	var d := p - center[i]
	var off := maxf(absf(d.dot(right[i])) - width[i] * 0.5, 0.0) + 2.0 * maxf(absf(d.dot(up[i])) - 2.0, 0.0)
	if not closed:
		off += maxf(-(p - center[0]).dot(fwd[0]), 0.0) + maxf((p - center[n - 1]).dot(fwd[n - 1]), 0.0)
	return off


## Where a kart driving `d` metres on from (route, u) ends up: Vector2(route, u). It turns into
## a branch only when plan[branch index] is true and it has not passed that fork's nose yet;
## past a branch's end it carries on along the main loop from the merge.
func walk(route: int, u: float, d: float, plan: Dictionary) -> Vector2:
	if route >= 0:
		var b := branches[route]
		if u + d <= b.length:
			return Vector2(route, u + d)
		return Vector2(-1, fposmod(b.merge_s + u + d - b.length, length))
	var best := -1
	var best_fork := INF
	for k in branches.size():
		if not plan.get(k, false):
			continue
		var b := branches[k]
		var past := fposmod(u - b.fork_s, length)
		if past < b.fork_nose_u - 2.0:
			# still in the part both roads share: the branch from the same spot (its metres are
			# the lap's there)
			return walk(k, past, d, plan)
		var to_fork := fposmod(b.fork_s - u, length)
		if to_fork <= d and to_fork < best_fork:
			best_fork = to_fork
			best = k
	if best >= 0:
		return walk(best, 0.0, d - best_fork, plan)
	return Vector2(-1, fposmod(u + d, length))


## Route and sample index for a point with no history (race start, a bot takeover): a global
## search, the main loop unless a branch's surface is clearly closer. Vector2i(route, index).
func locate(p: Vector3) -> Vector2i:
	var i := closest(p)
	var best := Vector2i(-1, i)
	var bd := on_road(p, i)
	for k in branches.size():
		var b := branches[k]
		var j := b.closest(p)
		var dj := b.on_road(p, j)
		if dj + 0.75 < bd:
			best = Vector2i(k, j)
			bd = dj
	return best
