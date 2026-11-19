class_name LevelLine
## The racing line and the speed profile (3.3, a 1:1 port of build_track.racing_line and the
## open-edge rule of track_gen.lap_line). Works on the dense samples of a LevelRoad. P2.

## Smoothing passes of the lateral offset and how far each moves it toward its neighbours' mid.
const PASSES := 400
const GAIN := 0.8
## The line keeps this far inside the edge; beside an open edge (pit and no gap) this far.
const EDGE := 3.8
const OPEN_EDGE := 6.5
## Speed: v = clip(sqrt(14 r), 12, 40) over a +-4 sample window, 4 braking passes of 2.5 m/s per 3.
const LAT_ACCEL := 14.0
const V_MIN := 12.0
const V_MAX := 40.0
const BRAKE := 2.5


## Lateral offsets of the racing line per dense sample: 400 passes of p = pos + right * off,
## off += dot(mid - p, right) * 0.8, clipped to +-(width / 2 - 3.8), 0 over gaps and on `held`
## samples (a branch's first and last 6); then +-max(width / 2 - 6.5, 0) beside an open edge.
static func racing(r: LevelRoad, held := PackedByteArray()) -> PackedFloat32Array:
	var n := r.n
	var off := PackedFloat32Array()
	off.resize(n)
	if n < 3:
		return off
	# off_i += 0.8 * (c0_i + a_i off_{i-1} + b_i off_{i+1} - off_i), the dot products precomputed
	var c0 := PackedFloat32Array()
	c0.resize(n)
	var ca := PackedFloat32Array()
	ca.resize(n)
	var cb := PackedFloat32Array()
	cb.resize(n)
	var lim := PackedFloat32Array()
	lim.resize(n)
	var zero := PackedByteArray()
	zero.resize(n)
	for i in n:
		var ip := posmod(i - 1, n) if r.closed else maxi(i - 1, 0)
		var iq := (i + 1) % n if r.closed else mini(i + 1, n - 1)
		var ri := r.right[i]
		c0[i] = 0.5 * ((r.pos[ip] - r.pos[i]).dot(ri) + (r.pos[iq] - r.pos[i]).dot(ri))
		ca[i] = 0.5 * r.right[ip].dot(ri)
		cb[i] = 0.5 * r.right[iq].dot(ri)
		lim[i] = maxf(r.width[i] * 0.5 - EDGE, 0.0)
		var z := r.gap[i] == 1 or (held.size() == n and held[i] == 1)
		zero[i] = 1 if z else 0
	var nxt := PackedFloat32Array()
	nxt.resize(n)
	for _p in PASSES:
		for i in n:
			if zero[i] == 1:
				nxt[i] = 0.0
				continue
			var ip := posmod(i - 1, n) if r.closed else maxi(i - 1, 0)
			var iq := (i + 1) % n if r.closed else mini(i + 1, n - 1)
			var o := off[i]
			o += (c0[i] + ca[i] * off[ip] + cb[i] * off[iq] - o) * GAIN
			var l := lim[i]
			nxt[i] = clampf(o, -l, l)
		var tmp := off
		off = nxt
		nxt = tmp
	if r.pit.size() == n:
		for i in n:
			if r.pit[i] == 1 and r.gap[i] == 0:
				var l := maxf(r.width[i] * 0.5 - OPEN_EDGE, 0.0)
				off[i] = clampf(off[i], -l, l)
	return off


## Target speeds for the line at `off`: the plan angle over +-4 samples gives the radius, v =
## clip(sqrt(14 r), 12, 40), 4 passes of v = min(v, v[i + 3] + 2.5), then each style's vmax and
## `vmax`.
static func speeds(r: LevelRoad, off: PackedFloat32Array, vmax := 40.0) -> PackedFloat32Array:
	var n := r.n
	var v := PackedFloat32Array()
	v.resize(n)
	if n == 0:
		return v
	var p := PackedVector3Array()
	p.resize(n)
	for i in n:
		p[i] = r.pos[i] + r.right[i] * (off[i] if off.size() == n else 0.0)
	for i in n:
		var i4 := (i + 4) % n if r.closed else mini(i + 4, n - 1)
		var i0 := posmod(i - 4, n) if r.closed else maxi(i - 4, 0)
		var a := p[i4] - p[i]
		var b := p[i] - p[i0]
		var ang := atan2(a.x * b.z - a.z * b.x, a.x * b.x + a.z * b.z)
		var radius := absf(4.0 * r.step / maxf(absf(ang), 1e-4))
		v[i] = clampf(sqrt(LAT_ACCEL * radius), V_MIN, V_MAX)
	for _p in 4:
		var nv := v.duplicate()
		for i in n:
			var j := (i + 3) % n if r.closed else mini(i + 3, n - 1)
			nv[i] = minf(v[i], v[j] + BRAKE)
		v = nv
	for i in n:
		var cap := minf(vmax, float(r.styles[r.style[i]].get("vmax", vmax)))
		v[i] = minf(v[i], cap)
	return v


## Fills r.line and r.speed (and r.line_off) from the offsets.
static func apply(r: LevelRoad, off: PackedFloat32Array) -> void:
	var n := r.n
	r.line_off = off.duplicate()
	r.line = PackedVector3Array()
	r.line.resize(n)
	for i in n:
		r.line[i] = r.pos[i] + r.right[i] * (off[i] if off.size() == n else 0.0)
	r.speed = speeds(r, off)
