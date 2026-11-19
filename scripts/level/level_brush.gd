class_name LevelBrush
## Pure brush maths on height / splat arrays (1.6 TERRAIN and PAINT): raise, lower, smooth,
## flatten, noise, paint, auto paint, the antlion's sand band, resample. Nothing here touches a node
## or the history: the tools write the document's arrays with these, then record the stroke
## (EditHistory.push_applied) with `region` copies of the touched rectangle. Heights stay within
## -500..1500 m; holes (NAN) are left alone. Rects are in samples (x, z), clamped to the grid. P16.
##
## The splat is RGBA8 per sample: R dirt, G rock, B pave, A sand (the terrain shader's order);
## BASE is what shows where the four are 0.

const MODES := ["raise", "lower", "smooth", "flatten", "noise"]
const FALLOFFS := ["smooth", "linear", "flat"]
## Paint layers: 0 base (erases the four), then the splat channels R G B A.
const LAYERS := ["base", "dirt", "rock", "pave", "sand"]
const HEIGHT_MIN := -500.0
const HEIGHT_MAX := 1500.0
## Metres a RAISE / LOWER / NOISE dab moves the ground at its centre at full strength:
## RATE x radius + RATE_MIN (a 20 m brush at strength 0.5: 0.93 m a dab).
const RATE := 0.08
const RATE_MIN := 0.25
## NOISE: the feature size when none is given (NOISE SCALE 8-256 m).
const NOISE_SCALE := 32.0
## The radius fraction where each falloff starts to fall (1 inside it).
const INNER := {"smooth": 0.35, "linear": 0.0, "flat": 0.9}
## AUTO PAINT defaults (1.6 PAINT).
const AUTO := {"rock": true, "slope": 32.0, "fade": 6.0, "sand": false, "sand_below": 0.0, "sand_fade": 2.0,
	"dirt": 0.0}
## The sand band's soft rim beyond its width (m).
const BAND_RIM := 2.0
## Below this a paint weight changes nothing (so rounding never creeps).
const MIN_A := 0.002


## One height dab: mode raise / lower / smooth / flatten (to `target`) / noise (seeded, NOISE_SCALE)
## over a circle of `radius` m at `center` (world x, z) with a falloff; strength 0.01-1. Returns the
## samples' box (empty when the circle misses the grid).
static func dab_height(t: LevelTerrain, h: PackedFloat32Array, center: Vector2, radius: float, strength: float, mode: String, falloff: String, target := 0.0, seed_v := 0) -> Rect2i:
	if mode == "noise":
		return dab_noise(t, h, center, radius, strength, falloff, NOISE_SCALE, seed_v)
	if t == null or radius <= 0.0 or h.size() != t.res * t.res:
		return Rect2i()
	var m := MODES.find(mode)
	if m < 0:
		return Rect2i()
	var rect := t.rect_of(center, radius)
	if not rect.has_area():
		return rect
	var s := clampf(strength, 0.0, 1.0)
	var amount := s * (RATE * radius + RATE_MIN)
	if m == 1:
		amount = -amount
	var avg := PackedFloat32Array()
	if m == 2:
		avg = _box_avg(h, t.res, rect, clampi(roundi(radius / t.cell * 0.25), 1, 6))
	var inner := float(INNER.get(falloff, 0.35))
	var ftype := FALLOFFS.find(falloff)
	var r2 := radius * radius
	var res := t.res
	for z in range(rect.position.y, rect.end.y):
		var dz := t.origin.y + z * t.cell - center.y
		var row := z * res
		var lrow := (z - rect.position.y) * rect.size.x
		for x in range(rect.position.x, rect.end.x):
			var dx := t.origin.x + x * t.cell - center.x
			var d2 := dx * dx + dz * dz
			if d2 >= r2:
				continue
			var w := _weight(sqrt(d2) / radius, ftype, inner)
			if w <= 0.0:
				continue
			var i := row + x
			var v := h[i]
			if is_nan(v):
				continue
			if m == 3:
				v = lerpf(v, target, s * w)
			elif m == 2:
				var a := avg[lrow + x - rect.position.x]
				if not is_nan(a):
					v = lerpf(v, a, s * w)
			else:
				v += amount * w
			h[i] = clampf(v, HEIGHT_MIN, HEIGHT_MAX)
	return rect


## A splat dab: paints `layer` (0 base .. 4 sand) towards full over a circle; the other channels
## give way by the same share (BASE takes all four down). Returns the samples' box.
static func dab_splat(t: LevelTerrain, s: PackedByteArray, center: Vector2, radius: float, strength: float, layer: int, falloff: String) -> Rect2i:
	if t == null or radius <= 0.0 or s.size() != t.res * t.res * 4 or layer < 0 or layer >= LAYERS.size():
		return Rect2i()
	var rect := t.rect_of(center, radius)
	if not rect.has_area():
		return rect
	var st := clampf(strength, 0.0, 1.0)
	var inner := float(INNER.get(falloff, 0.35))
	var ftype := FALLOFFS.find(falloff)
	var r2 := radius * radius
	for z in range(rect.position.y, rect.end.y):
		var dz := t.origin.y + z * t.cell - center.y
		for x in range(rect.position.x, rect.end.x):
			var dx := t.origin.x + x * t.cell - center.x
			var d2 := dx * dx + dz * dz
			if d2 >= r2:
				continue
			var a := st * _weight(sqrt(d2) / radius, ftype, inner)
			if a > MIN_A:
				mix_layer(s, (z * t.res + x) * 4, layer, a)
	return rect


## The antlion's sand band (4.2): samples i0..i1 of road r (wrapping on a loop), on `side` (-1 left,
## 1 right, 0 both), `width` m of `layer` from the road's edge out past its side treatment, full
## inside and fading over BAND_RIM m beyond. Returns the touched samples' box.
static func band_splat(t: LevelTerrain, s: PackedByteArray, r: LevelRoad, i0: int, i1: int, side: int, width: float, layer: int) -> Rect2i:
	if t == null or r == null or r.n <= 1 or s.size() != t.res * t.res * 4 or width <= 0.0 or layer < 0 or layer >= LAYERS.size():
		return Rect2i()
	var idx := _span(r, i0, i1)
	var sides: Array = [-1, 1] if side == 0 else [signi(side)]
	var acc := {}  # sample index -> weight (the strongest)
	var lo := Vector2i(t.res, t.res)
	var hi := Vector2i(-1, -1)
	var stp := maxf(t.cell * 0.5, 0.25)
	for i in idx:
		var half := r.width[i] * 0.5
		var along := maxf(r.step, stp) * 0.5
		for sg in sides:
			var edge := half + r.treatment(i, sg)
			var far := edge + width + BAND_RIM
			var lat := half * 0.5
			while lat <= far + 1e-4:
				var w := 1.0 if lat <= edge + width else 1.0 - (lat - edge - width) / BAND_RIM
				for off in [0.0, along]:
					var q: Vector3 = r.pos[i] + r.flat_right[i] * (lat * sg) + r.fwd[i] * off
					var c := t.cell_of(q.x, q.z)
					if c.x < 0 or c.y < 0 or c.x >= t.res or c.y >= t.res:
						continue
					var k := c.y * t.res + c.x
					if w > float(acc.get(k, 0.0)):
						acc[k] = w
						lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
						hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
				lat += stp
	if acc.is_empty():
		return Rect2i()
	for k in acc:
		mix_layer(s, int(k) * 4, layer, float(acc[k]))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## AUTO PAINT over the whole grid (1.6): opts {rock: bool, slope: 32 deg, fade: 6 deg, sand: bool,
## sand_below: m, sand_fade: m, dirt: 0-8 m beside road edges (0 off), roads: [LevelRoad]} (AUTO's
## defaults for missing keys). ROCK from the carved ground's slope, SAND under a height, DIRT near
## the roads; each rule writes only its own channel (PAVE is left as painted). Returns the grid.
static func auto_paint(t: LevelTerrain, s: PackedByteArray, opts: Dictionary) -> Rect2i:
	if t == null or t.res < 2 or s.size() != t.res * t.res * 4:
		return Rect2i()
	var o := AUTO.duplicate()
	o.merge(opts, true)
	var res := t.res
	var hs := t.heights if t.heights.size() == res * res else t.natural
	if hs.size() != res * res:
		return Rect2i()
	var do_rock := bool(o.rock)
	var do_sand := bool(o.sand)
	var slope0 := float(o.slope)
	var fade := maxf(float(o.fade), 0.01)
	var below := float(o.sand_below)
	var sfade := maxf(float(o.sand_fade), 0.01)
	if do_rock or do_sand:
		for z in res:
			var row := z * res
			var zb := maxi(z - 1, 0)
			var zf := mini(z + 1, res - 1)
			for x in res:
				var i := row + x
				var c := hs[i]
				if is_nan(c):
					continue
				if do_rock:
					var xl := maxi(x - 1, 0)
					var xr := mini(x + 1, res - 1)
					var l := hs[row + xl]
					var rr := hs[row + xr]
					var b := hs[zb * res + x]
					var f := hs[zf * res + x]
					var gx := 0.0 if is_nan(l) or is_nan(rr) else (rr - l) / ((xr - xl) * t.cell)
					var gz := 0.0 if is_nan(b) or is_nan(f) else (f - b) / ((zf - zb) * t.cell)
					var ang := rad_to_deg(atan(sqrt(gx * gx + gz * gz)))
					s[i * 4 + 1] = _byte(smoothstep(0.0, 1.0, (ang - slope0) / fade))
				if do_sand:
					s[i * 4 + 3] = _byte(1.0 - smoothstep(below - sfade * 0.5, below + sfade * 0.5, c))
	var dirt := clampf(float(o.dirt), 0.0, 8.0)
	if dirt > 0.0:
		var acc := PackedFloat32Array()
		acc.resize(res * res)
		acc.fill(0.0)
		var stp := maxf(t.cell * 0.5, 0.25)
		for r in o.get("roads", []):
			if not (r is LevelRoad) or (r as LevelRoad).n <= 1:
				continue
			var rd := r as LevelRoad
			for i in rd.n:
				var half := rd.width[i] * 0.5
				for sg in [-1, 1]:
					var edge := half + rd.treatment(i, sg)
					var far := edge + dirt
					var lat := half * 0.5
					while lat <= far + 1e-4:
						var w := 1.0 if lat <= far - 1.5 else clampf((far - lat) / 1.5, 0.0, 1.0)
						for off in [0.0, rd.step * 0.5]:
							var q: Vector3 = rd.pos[i] + rd.flat_right[i] * (lat * sg) + rd.fwd[i] * off
							var cc := t.cell_of(q.x, q.z)
							if cc.x < 0 or cc.y < 0 or cc.x >= res or cc.y >= res:
								continue
							var k := cc.y * res + cc.x
							if w > acc[k]:
								acc[k] = w
						lat += stp
		for k in acc.size():
			if not is_nan(hs[k]):
				s[k * 4] = _byte(acc[k])
	return Rect2i(0, 0, res, res)


## A copy of h inside rect (rect.size.x * rect.size.y values, row by row); cells outside the grid
## read NAN.
static func region(h: PackedFloat32Array, res: int, rect: Rect2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return out
	out.resize(rect.size.x * rect.size.y)
	var ok := h.size() == res * res
	var k := 0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out[k] = h[z * res + x] if ok and x >= 0 and z >= 0 and x < res and z < res else NAN
			k += 1
	return out


## RESIZE WORLD as ops (one undo step): the world's new (size, res), the heights and splat
## resampled bilinearly in world space (the ground stays under the roads; outside the old world the
## border carries on). [] for a (size, res) pair LevelDoc.WORLDS does not allow.
static func resample(doc: LevelDoc, size: float, res: int) -> Array:
	if doc == null or not _allowed(size, res):
		return []
	var w = doc.data.get("world", {})
	var world := (w as Dictionary).duplicate() if w is Dictionary else {}
	world["size"] = float(size)
	world["res"] = res
	var out := []
	var has := doc.has_terrain()
	world["terrain"] = has
	out.append(LevelDoc.op_set(["world"], world))
	if not has:
		return out
	var ores := doc.res()
	var ocell := doc.cell()
	var oorg := doc.origin()
	var cell := size / float(res - 1)
	var org := Vector2(-size * 0.5, -size * 0.5)
	var nh := PackedFloat32Array()
	nh.resize(res * res)
	var ns := PackedByteArray()
	ns.resize(res * res * 4)
	var sp_ok := doc.splat.size() == ores * ores * 4
	for z in res:
		var fz := clampf((org.y + z * cell - oorg.y) / ocell, 0.0, ores - 1.0)
		var iz := mini(int(fz), ores - 2)
		var v := fz - iz
		for x in res:
			var fx := clampf((org.x + x * cell - oorg.x) / ocell, 0.0, ores - 1.0)
			var ix := mini(int(fx), ores - 2)
			var u := fx - ix
			var i0 := iz * ores + ix
			var a := doc.heights[i0]
			var b := doc.heights[i0 + 1]
			var c := doc.heights[i0 + ores]
			var d := doc.heights[i0 + ores + 1]
			var k := z * res + x
			if is_nan(a) or is_nan(b) or is_nan(c) or is_nan(d):
				# a hole stays a hole at its nearest sample
				nh[k] = doc.heights[roundi(fz) * ores + roundi(fx)]
			else:
				nh[k] = snappedf(clampf(lerpf(lerpf(a, b, u), lerpf(c, d, u), v), HEIGHT_MIN, HEIGHT_MAX), 0.01)
			for ch in 4:
				var val := 0.0
				if sp_ok:
					var sa := float(doc.splat[i0 * 4 + ch])
					var sb := float(doc.splat[(i0 + 1) * 4 + ch])
					var sc := float(doc.splat[(i0 + ores) * 4 + ch])
					var sd := float(doc.splat[(i0 + ores + 1) * 4 + ch])
					val = lerpf(lerpf(sa, sb, u), lerpf(sc, sd, u), v)
				ns[k * 4 + ch] = clampi(roundi(val), 0, 255)
	out.append(LevelDoc.op_heights_all(nh))
	out.append(LevelDoc.op_splat_all(ns))
	return out


# ---------------------------------------------------------------- additions (P16)

## A NOISE dab with its feature size (NOISE SCALE 8-256 m) and seed: the same seed gives the same
## pattern in world space, so dabs build on each other.
static func dab_noise(t: LevelTerrain, h: PackedFloat32Array, center: Vector2, radius: float, strength: float, falloff: String, scale: float, seed_v := 0) -> Rect2i:
	if t == null or radius <= 0.0 or h.size() != t.res * t.res:
		return Rect2i()
	var rect := t.rect_of(center, radius)
	if not rect.has_area():
		return rect
	var fn := noise(scale, seed_v)
	var amount := clampf(strength, 0.0, 1.0) * (RATE * radius + RATE_MIN)
	var inner := float(INNER.get(falloff, 0.35))
	var ftype := FALLOFFS.find(falloff)
	var r2 := radius * radius
	for z in range(rect.position.y, rect.end.y):
		var wz := t.origin.y + z * t.cell
		var dz := wz - center.y
		for x in range(rect.position.x, rect.end.x):
			var wx := t.origin.x + x * t.cell
			var dx := wx - center.x
			var d2 := dx * dx + dz * dz
			if d2 >= r2:
				continue
			var i := z * t.res + x
			var v := h[i]
			if is_nan(v):
				continue
			var w := _weight(sqrt(d2) / radius, ftype, inner)
			h[i] = clampf(v + amount * w * fn.get_noise_2d(wx, wz), HEIGHT_MIN, HEIGHT_MAX)
	return rect


## The seeded noise NOISE dabs use (values about -1..1).
static func noise(scale: float, seed_v: int) -> FastNoiseLite:
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 1.0 / clampf(scale, 1.0, 4096.0)
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	return fn


## The brush weight at u = distance / radius (0 centre, 1 edge) for a falloff.
static func weight(u: float, falloff: String) -> float:
	return _weight(u, FALLOFFS.find(falloff), float(INNER.get(falloff, 0.35)))


## The radius fraction where the falloff's weight is one half: the brush circle's inner ring.
static func ring(falloff: String) -> float:
	var inner := float(INNER.get(falloff, 0.35))
	return inner + (1.0 - inner) * 0.5


## A copy of the splat inside rect (4 bytes a sample; 0 outside the grid).
static func region_splat(s: PackedByteArray, res: int, rect: Rect2i) -> PackedByteArray:
	var out := PackedByteArray()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return out
	out.resize(rect.size.x * rect.size.y * 4)
	out.fill(0)
	var ok := s.size() == res * res * 4
	var k := 0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if ok and x >= 0 and z >= 0 and x < res and z < res:
				var g := (z * res + x) * 4
				for c in 4:
					out[k + c] = s[g + c]
			k += 4
	return out


## Bilinear on a res x res grid at world (x, z); NAN outside it or at a hole.
static func sample(h: PackedFloat32Array, res: int, origin: Vector2, cell: float, x: float, z: float) -> float:
	if res < 2 or h.size() != res * res or cell <= 0.0:
		return NAN
	var fx := (x - origin.x) / cell
	var fz := (z - origin.y) / cell
	if is_nan(fx) or is_nan(fz) or fx < 0.0 or fz < 0.0 or fx > res - 1.0 or fz > res - 1.0:
		return NAN
	var ix := mini(int(fx), res - 2)
	var iz := mini(int(fz), res - 2)
	var u := fx - ix
	var v := fz - iz
	var i0 := iz * res + ix
	var a := h[i0]
	var b := h[i0 + 1]
	var c := h[i0 + res]
	var d := h[i0 + res + 1]
	if is_nan(a) or is_nan(b) or is_nan(c) or is_nan(d):
		return NAN
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## ROADS FOLLOW THE GROUND: the `set` ops that keep every road and branch point with FOLLOW on
## whose sample lies in rect at its height above the ground: y += new natural - old natural
## (`before` is the heightmap before the stroke, the document's heights are the new one).
static func follow_ops(doc: LevelDoc, before: PackedFloat32Array, rect: Rect2i) -> Array:
	var out := []
	if doc == null or not rect.has_area() or before.size() != doc.heights.size() or doc.heights.is_empty():
		return out
	var res := doc.res()
	var cell := doc.cell()
	var org := doc.origin()
	var lists := []
	var road = doc.data.get("road", {})
	if road is Dictionary and road.get("points") is Array:
		lists.append([["road", "points"], road.points])
	for b in doc.data.get("branches", []):
		if b is Dictionary and b.get("points") is Array and int(b.get("uid", 0)) > 0:
			lists.append([["branches", "#%d" % int(b.uid), "points"], b.points])
	for l in lists:
		for p in l[1]:
			if not (p is Dictionary) or not bool(p.get("follow", false)) or not (p.get("pos") is Array) or (p.pos as Array).size() < 3:
				continue
			var x := float(p.pos[0])
			var z := float(p.pos[2])
			var c := Vector2i(roundi((x - org.x) / cell), roundi((z - org.y) / cell))
			if not rect.grow(1).has_point(c):
				continue
			var old := sample(before, res, org, cell, x, z)
			var now := sample(doc.heights, res, org, cell, x, z)
			if is_nan(old) or is_nan(now) or absf(now - old) < 0.0005:
				continue
			var y := clampf(float(p.pos[1]) + now - old, HEIGHT_MIN, HEIGHT_MAX)
			out.append(LevelDoc.op_set((l[0] as Array) + ["#%d" % int(p.uid), "pos"], [x, snappedf(y, 0.001), z]))
	return out


## NO TERRAIN on / off as ops: off drops the heights and splat (floating roads over a void); on
## brings back a flat ground at 0 m of the world's res.
static func terrain_ops(doc: LevelDoc, on: bool) -> Array:
	if doc == null or doc.has_terrain() == on:
		return []
	var w = doc.data.get("world", {})
	var world := (w as Dictionary).duplicate() if w is Dictionary else {}
	world["terrain"] = on
	var out := [LevelDoc.op_set(["world"], world)]
	if on:
		var res := int(world.get("res", 513))
		var h := PackedFloat32Array()
		h.resize(res * res)
		h.fill(0.0)
		var sp := PackedByteArray()
		sp.resize(res * res * 4)
		sp.fill(0)
		out.append(LevelDoc.op_heights_all(h))
		out.append(LevelDoc.op_splat_all(sp))
	else:
		out.append(LevelDoc.op_heights_all(PackedFloat32Array()))
		out.append(LevelDoc.op_splat_all(PackedByteArray()))
	return out


## The strongest layer at sample i (0 base when none of the four passes 96): the eyedropper.
static func strongest(s: PackedByteArray, i: int) -> int:
	if i < 0 or i * 4 + 3 >= s.size():
		return 0
	var best := 0
	var bv := 96
	for c in 4:
		if s[i * 4 + c] > bv:
			bv = s[i * 4 + c]
			best = c + 1
	return best


## Moves the 4 bytes at g towards `layer` by share a (0..1): its channel up, the others down.
static func mix_layer(s: PackedByteArray, g: int, layer: int, a: float) -> void:
	for c in 4:
		var v := int(s[g + c])
		var nv := v
		if c == layer - 1:
			nv = roundi(v + (255 - v) * a)
			if nv == v and v < 255:
				nv = v + 1
		else:
			nv = roundi(v * (1.0 - a))
			if nv == v and v > 0:
				nv = v - 1
		s[g + c] = clampi(nv, 0, 255)


static func _weight(u: float, ftype: int, inner: float) -> float:
	if u >= 1.0:
		return 0.0
	if u <= inner:
		return 1.0
	var k := (u - inner) / maxf(1.0 - inner, 1e-6)
	if ftype == 1 or ftype == 2:
		return 1.0 - k  # linear; flat's thin rim fades linearly too
	return 1.0 - smoothstep(0.0, 1.0, k)


## The box average (half-width k samples, holes left out) of every sample of rect, row by row,
## from a summed-area table of the padded region.
static func _box_avg(h: PackedFloat32Array, res: int, rect: Rect2i, k: int) -> PackedFloat32Array:
	var pad := rect.grow(k).intersection(Rect2i(0, 0, res, res))
	var pw := pad.size.x
	var ph := pad.size.y
	var sum := PackedFloat64Array()
	var cnt := PackedInt32Array()
	sum.resize((pw + 1) * (ph + 1))
	cnt.resize((pw + 1) * (ph + 1))
	sum.fill(0.0)
	cnt.fill(0)
	for z in ph:
		var acc := 0.0
		var ac := 0
		var row := (pad.position.y + z) * res + pad.position.x
		for x in pw:
			var v := h[row + x]
			if not is_nan(v):
				acc += v
				ac += 1
			var o := (z + 1) * (pw + 1) + x + 1
			sum[o] = sum[o - pw - 1] + acc
			cnt[o] = cnt[o - pw - 1] + ac
	var out := PackedFloat32Array()
	out.resize(rect.size.x * rect.size.y)
	var j := 0
	for z in range(rect.position.y, rect.end.y):
		var z0 := clampi(z - k, pad.position.y, pad.end.y - 1) - pad.position.y
		var z1 := clampi(z + k, pad.position.y, pad.end.y - 1) - pad.position.y + 1
		for x in range(rect.position.x, rect.end.x):
			var x0 := clampi(x - k, pad.position.x, pad.end.x - 1) - pad.position.x
			var x1 := clampi(x + k, pad.position.x, pad.end.x - 1) - pad.position.x + 1
			var a := z1 * (pw + 1) + x1
			var b := z0 * (pw + 1) + x1
			var c := z1 * (pw + 1) + x0
			var d := z0 * (pw + 1) + x0
			var n := cnt[a] - cnt[b] - cnt[c] + cnt[d]
			out[j] = float((sum[a] - sum[b] - sum[c] + sum[d]) / n) if n > 0 else NAN
			j += 1
	return out


## The sample indices i0..i1 of r (wrapping on a loop; i1 < i0 on an open road gives none).
static func _span(r: LevelRoad, i0: int, i1: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if r.closed:
		var a := posmod(i0, r.n)
		var count := posmod(i1 - i0, r.n) + 1
		for q in count:
			out.append((a + q) % r.n)
	else:
		for i in range(clampi(i0, 0, r.n - 1), clampi(i1, 0, r.n - 1) + 1):
			out.append(i)
	return out


static func _allowed(size: float, res: int) -> bool:
	for p in LevelDoc.WORLDS:
		if is_equal_approx(float(p[0]), size) and int(p[1]) == res:
			return true
	return false


static func _byte(w: float) -> int:
	return clampi(roundi(clampf(w, 0.0, 1.0) * 255.0), 0, 255)
