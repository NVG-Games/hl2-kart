class_name LevelTerrain
extends RefCounted
## The heightmap at runtime (3.4): the road carve (pits, skip, tunnels keep the hill), render chunks
## (LOD0 + LOD1 + skirts), the edge skirt, square collision tiles, hashes, sampling and raycasts.
## Pure data apart from tile_body / chunk_node / edge_skirt_node (main thread), so a compile runs it
## on a worker. Samples are `res x res`, `cell` metres apart, sample (0, 0) at `origin` (x, z);
## a sample index is `iz * res + ix`; a Rect2i over samples is (ix, iz, w, d).

const CHUNK := 64
const TILE := 128
const CLEAR := 0.06
## LOD1 chunks hang a skirt this far down round their border (cracks against LOD0 neighbours).
const LOD_SKIRT := 1.5
## The world edge skirt drops this far all round.
const EDGE_DROP := 60.0
## LOD0 / LOD1 swap distance margin (metres, fade SELF).
const LOD_MARGIN := 32.0
const HEIGHT_MIN := -500.0
const HEIGHT_MAX := 1500.0
## Natural ground this far above a tunnel's floor (and under its roof + 1.5) is a hole: the mouth.
const MOUTH_MIN := 0.25

enum { K_OPEN, K_STREET, K_TUNNEL, K_BRIDGE }

var res := 513
var cell := 2.0
var origin := Vector2(-512, -512)
var natural := PackedFloat32Array()
var heights := PackedFloat32Array()
var splat := PackedByteArray()
var layers := {}

# the carve's nearest candidate per cell and class (grounded: open / street / tunnel; aerial:
# bridge, gap and dip samples): index into the carve's roads, sample, signed lateral, plan distance
var _g_road := PackedInt32Array()
var _g_i := PackedInt32Array()
var _g_lat := PackedFloat32Array()
var _g_d := PackedFloat32Array()
var _a_road := PackedInt32Array()
var _a_i := PackedInt32Array()
var _a_lat := PackedFloat32Array()
var _a_d := PackedFloat32Array()


## null when world.terrain is false (or the document has no heightmap).
static func from_doc(doc: LevelDoc) -> LevelTerrain:
	if doc == null or not doc.has_terrain():
		return null
	var t := LevelTerrain.new()
	t.res = doc.res()
	t.cell = doc.cell()
	t.origin = doc.origin()
	var n := t.res * t.res
	if doc.heights.size() != n:
		return null
	t.natural = doc.heights.duplicate()
	t.heights = doc.heights.duplicate()
	if doc.splat.size() == n * 4:
		t.splat = doc.splat.duplicate()
	else:
		t.splat = PackedByteArray()
		t.splat.resize(n * 4)
		t.splat.fill(0)
	var tr = doc.data.get("terrain", {})
	if tr is Dictionary and tr.get("layers") is Dictionary:
		t.layers = (tr["layers"] as Dictionary).duplicate()
	return t


## A flat terrain of `res` samples over `size` metres at height `y` (tests, the editor's previews).
static func flat_world(size_m: float, samples: int, y := 0.0) -> LevelTerrain:
	var t := LevelTerrain.new()
	t.res = maxi(samples, 2)
	t.cell = size_m / float(t.res - 1)
	t.origin = Vector2(-size_m * 0.5, -size_m * 0.5)
	t.natural.resize(t.res * t.res)
	t.natural.fill(y)
	t.heights = t.natural.duplicate()
	t.splat.resize(t.res * t.res * 4)
	t.splat.fill(0)
	return t


## World size in metres.
func size() -> float:
	return cell * float(res - 1)


# ---------------------------------------------------------------- carve

## The road carve (3.4) from `natural` into `heights`: a bed 0.35 m under every grounded road and its
## treatment, flat shoulders `flat` m wide, a smoothstep `blend` back to the natural ground; tunnels
## keep the hill over them (natural at or above roof + 1.5 stays, natural between the floor and
## that is a hole: the mouths; a kept cell beside a carved one under its roof is a hole too, the
## mouth in a steep face); bridges keep the ground under their skirt; gap / see-saw samples
## dip it; `pits` ({center: Vector2, radius, floor_y}) sink it; one 3 x 3 pass smooths where two
## carves meet; the ground stays CLEAR under every open / street surface; all within -500..1500 m.
## `rect` (samples) re-carves only those cells from the samples whose influence meets it; `skip`
## ({road key: PackedInt32Array of segment indices}) leaves those segments' samples out.
func carve(roads: Array, flat: float, blend: float, rect := Rect2i(), pits := [], skip := {}) -> void:
	var flat_m := maxf(flat, 0.0)
	var cells := res * res
	if res < 2 or natural.size() != cells:
		return
	var grid := Rect2i(0, 0, res, res)
	var full := rect.size.x <= 0 or rect.size.y <= 0
	var area := grid if full else rect.intersection(grid)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	if full or _g_d.size() != cells or heights.size() != cells:
		heights = natural.duplicate()
		_alloc(cells)
	else:
		for z in range(area.position.y, area.end.y):
			var row := z * res
			for x in range(area.position.x, area.end.x):
				var ci := row + x
				heights[ci] = natural[ci]
				_g_d[ci] = INF
				_a_d[ci] = INF
				_g_road[ci] = -1
				_a_road[ci] = -1
	blend = maxf(blend, 0.01)
	# 1-2. raster every road's samples into the nearest candidate per cell and class
	var preps: Array = []
	var touched := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(cells)
	seen.fill(0)
	for ri in roads.size():
		var r = roads[ri]
		if not r is LevelRoad:
			preps.append({})
			continue
		var pr := _prep(r, flat_m, blend)
		preps.append(pr)
		var skipped := {}
		var sk = skip.get(r.key, skip.get(str(r.key)))
		if sk != null:
			for sgi in sk:
				skipped[int(sgi)] = true
		_raster(r, ri, pr, area, skipped, touched, seen)
	# 3. heights per touched cell
	var avg := PackedByteArray()
	avg.resize(touched.size())
	avg.fill(0)
	var capy := PackedFloat32Array()
	capy.resize(touched.size())
	capy.fill(INF)
	# the roof over each tunnel-bed cell that kept the hill (NAN = not one)
	var kept := PackedFloat32Array()
	kept.resize(touched.size())
	kept.fill(NAN)
	for k in touched.size():
		var ci := touched[k]
		var nat := natural[ci]
		if is_nan(nat):
			continue  # the author's hole stays
		var h := nat
		var gd := _g_d[ci]
		var gin := false
		var bed := false
		if gd < INF:
			var pr: Dictionary = preps[_g_road[ci]]
			var i := _g_i[ci]
			var lat := _g_lat[ci]
			var half: float = (pr["hr"] if lat >= 0.0 else pr["hl"])[i]
			var w2: float = pr["w2"][i]
			var bank: float = pr["bank"][i]
			var surf: float = pr["y"][i] + bank * clampf(lat, -w2, w2)
			var under := surf - 0.35 - absf(bank) * 1.5
			var kd: int = pr["kind"][i]
			if gd < half + flat_m + blend:
				gin = true
				bed = gd <= half + 1.5
				if kd == K_TUNNEL and gd < half + cell + 0.5:
					bed = true
					var roof: float = pr["roof"][i]
					if nat >= roof + 1.5:
						h = nat
						kept[k] = roof
					elif nat > surf + MOUTH_MIN:
						h = NAN
					else:
						h = under
				else:
					var t := smoothstep(half + flat_m, half + flat_m + blend, gd)
					h = lerpf(under, nat, t)
					if kd == K_TUNNEL:
						h = maxf(h, nat)  # beside the tube the hill stays: fill only, never cut
			if kd <= K_STREET and gd <= w2:
				capy[k] = surf - CLEAR
		var ad := _a_d[ci]
		if ad < INF and not is_nan(h):
			var pa: Dictionary = preps[_a_road[ci]]
			var j := _a_i[ci]
			var alat := _a_lat[ci]
			var ahalf: float = (pa["hr"] if alat >= 0.0 else pa["hl"])[j]
			if not gin or ad < gd:
				if pa["kind"][j] == K_BRIDGE and ad < ahalf + 2.0:
					h = minf(h, pa["y"][j] - pa["skirt"][j] - 1.0)
					gin = true
				var dip: float = pa["dip"][j]
				if dip > 0.0 and ad < ahalf + 12.0:
					var u := 1.0 - smoothstep(ahalf, ahalf + 12.0, ad)
					h = lerpf(h, minf(h, pa["y"][j] - dip), u)
					gin = true
		heights[ci] = h
		if gin and not bed:
			avg[k] = 1
	# 3b. the mouths in a steep face: a tunnel-bed cell that kept the hill beside a carved cell under
	# its roof (the street's bed at the face, a tunnel floor) is a hole, or the heightmap climbs
	# from the bed to the hill across the opening and walls it off; the portal frame covers it
	_mouths(touched, kept)
	# 4. pits (the tentacle's)
	for p in pits:
		if not p is Dictionary:
			continue
		var c = p.get("center", Vector2.ZERO)
		var cv := Vector2.ZERO
		if c is Array and c.size() >= 2:
			cv = Vector2(float(c[0]), float(c[1]))
		elif c is Vector2:
			cv = c
		var rad := float(p.get("radius", 0.0))
		var fy := float(p.get("floor_y", 0.0))
		if rad <= 0.0:
			continue
		var pr_rect := rect_of(cv, rad + 4.0).intersection(area)
		for z in range(pr_rect.position.y, pr_rect.end.y):
			for x in range(pr_rect.position.x, pr_rect.end.x):
				var ci := z * res + x
				var h := heights[ci]
				if is_nan(h):
					continue
				var d := Vector2(origin.x + x * cell, origin.y + z * cell).distance_to(cv)
				if d >= rad + 4.0:
					continue
				var w := 1.0 - smoothstep(rad, rad + 4.0, d)
				heights[ci] = clampf(lerpf(h, minf(h, fy), w), HEIGHT_MIN, HEIGHT_MAX)
	# 5. one 3 x 3 pass where carves blend (outside every bed; holes left alone)
	var smooth := PackedFloat32Array()
	smooth.resize(touched.size())
	for k in touched.size():
		if avg[k] == 0:
			continue
		var ci := touched[k]
		var x := ci % res
		var z := ci / res
		var sum := 0.0
		var cnt := 0
		for dz in range(-1, 2):
			var zz := z + dz
			if zz < 0 or zz >= res:
				continue
			for dx in range(-1, 2):
				var xx := x + dx
				if xx < 0 or xx >= res:
					continue
				var v := heights[zz * res + xx]
				if not is_nan(v):
					sum += v
					cnt += 1
		smooth[k] = sum / float(cnt) if cnt > 0 else heights[ci]
	for k in touched.size():
		if avg[k] == 1 and not is_nan(heights[touched[k]]):
			heights[touched[k]] = smooth[k]
	# 6. the cap under open / street surfaces, and the height range
	for k in touched.size():
		var ci := touched[k]
		var h := heights[ci]
		if is_nan(h):
			continue
		heights[ci] = clampf(minf(h, capy[k]), HEIGHT_MIN, HEIGHT_MAX)


## Step 3b of carve: kept[k] is the roof over touched[k] when that tunnel-bed cell kept the hill.
## It becomes a hole when an 8-neighbour is carved (more than 0.5 m under its natural ground) to
## under that roof. One pass on the heights step 3 made (a rect re-carve reads its neighbours
## outside the rect as the last carve left them).
func _mouths(touched: PackedInt32Array, kept: PackedFloat32Array) -> void:
	var holes := PackedInt32Array()
	for k in touched.size():
		var roof := kept[k]
		if is_nan(roof):
			continue
		var ci := touched[k]
		var x := ci % res
		var z := ci / res
		var open := false
		for dz in range(-1, 2):
			var zz := z + dz
			if zz < 0 or zz >= res:
				continue
			for dx in range(-1, 2):
				var xx := x + dx
				if xx < 0 or xx >= res or (dx == 0 and dz == 0):
					continue
				var nb := zz * res + xx
				var v := heights[nb]
				if not is_nan(v) and v < roof and v < natural[nb] - 0.5:
					open = true
					break
			if open:
				break
		if open:
			holes.append(ci)
	for ci in holes:
		heights[ci] = NAN


func _alloc(cells: int) -> void:
	_g_road.resize(cells)
	_a_road.resize(cells)
	_g_i.resize(cells)
	_a_i.resize(cells)
	_g_lat.resize(cells)
	_g_d.resize(cells)
	_a_lat.resize(cells)
	_a_d.resize(cells)
	_g_road.fill(-1)
	_a_road.fill(-1)
	_g_i.fill(0)
	_a_i.fill(0)
	_g_lat.fill(0.0)
	_a_lat.fill(0.0)
	_g_d.fill(INF)
	_a_d.fill(INF)


## Per-sample numbers of one road for the carve: kind, half widths per side (width / 2 + the
## side's treatment), bank slope, roof, skirt, dip, aerial flag, plan frames, raster radius.
func _prep(r: LevelRoad, flat_m: float, blend: float) -> Dictionary:
	var n: int = r.n if r.n > 0 else r.pos.size()
	n = mini(n, r.pos.size())
	var kind := PackedInt32Array()
	var hl := PackedFloat32Array()
	var hr := PackedFloat32Array()
	var w2 := PackedFloat32Array()
	var bank := PackedFloat32Array()
	var roof := PackedFloat32Array()
	var skirt := PackedFloat32Array()
	var dip := PackedFloat32Array()
	var aerial := PackedByteArray()
	var y := PackedFloat32Array()
	var fr := PackedVector3Array()
	var ff := PackedVector3Array()
	var rad := PackedFloat32Array()
	kind.resize(n)
	hl.resize(n)
	hr.resize(n)
	w2.resize(n)
	bank.resize(n)
	roof.resize(n)
	skirt.resize(n)
	dip.resize(n)
	y.resize(n)
	rad.resize(n)
	aerial.resize(n)
	fr.resize(n)
	ff.resize(n)
	var treat_cache := {}
	for i in n:
		var st := _style(r, i)
		var k := str(st.get("kind", "open"))
		var kd := K_OPEN
		match k:
			"street":
				kd = K_STREET
			"tunnel":
				kd = K_TUNNEL
			"bridge":
				kd = K_BRIDGE
		kind[i] = kd
		var w := float(r.width[i]) if i < r.width.size() else 10.0
		w2[i] = w * 0.5
		hl[i] = w * 0.5 + _treat(r, i, 0, st, treat_cache)
		hr[i] = w * 0.5 + _treat(r, i, 1, st, treat_cache)
		var p := r.pos[i]
		y[i] = p.y
		# plan frames: flat_right = normalize(-f.z, 0, f.x), fwd flattened
		var f := r.fwd[i] if i < r.fwd.size() else Vector3.ZERO
		if f.length_squared() < 1e-8:
			var a := r.pos[maxi(i - 1, 0)]
			var b := r.pos[mini(i + 1, n - 1)]
			f = b - a
		var fp := Vector3(f.x, 0.0, f.z)
		fp = fp.normalized() if fp.length_squared() > 1e-10 else Vector3.FORWARD
		ff[i] = fp
		var rt := r.flat_right[i] if i < r.flat_right.size() else Vector3.ZERO
		rt = Vector3(rt.x, 0.0, rt.z)
		fr[i] = rt.normalized() if rt.length_squared() > 1e-10 else Vector3(-fp.z, 0.0, fp.x)
		var rb := r.right[i] if i < r.right.size() else fr[i]
		var rxz := Vector2(rb.x, rb.z).length()
		bank[i] = rb.y / rxz if rxz > 1e-4 else 0.0
		var hgt := float(r.height[i]) if i < r.height.size() else 0.0
		if hgt <= 0.0:
			hgt = float(st.get("height", 7.5))
		roof[i] = p.y + hgt
		skirt[i] = float(st.get("skirt_h", 1.5))
		var g := i < r.gap.size() and r.gap[i] != 0
		var dp := float(r.dip[i]) if i < r.dip.size() else 0.0
		if g and dp <= 0.0:
			dp = 8.0
		dip[i] = dp
		var air := kd == K_BRIDGE or g or dp > 0.0
		aerial[i] = 1 if air else 0
		var half := maxf(hl[i], hr[i])
		if air:
			rad[i] = half + (12.0 if dp > 0.0 else 2.0) + cell
		else:
			rad[i] = half + flat_m + blend
	return {"n": n, "kind": kind, "hl": hl, "hr": hr, "w2": w2, "bank": bank, "roof": roof, "skirt": skirt,
		"dip": dip, "aerial": aerial, "y": y, "fr": fr, "ff": ff, "rad": rad, "step": maxf(r.step, 0.1),
		"closed": r.closed}


static func _style(r: LevelRoad, i: int) -> Dictionary:
	if i < r.style.size():
		var si := r.style[i]
		if si >= 0 and si < r.styles.size():
			return r.styles[si]
	return {}


## The side treatment of sample i (LevelStyles.treatment with the sample's own barrier).
static func _treat(r: LevelRoad, i: int, side: int, st: Dictionary, cache: Dictionary) -> float:
	var bars := r.bar_r if side >= 1 else r.bar_l
	var bi := -2
	if i < bars.size():
		bi = bars[i]
	var si := r.style[i] if i < r.style.size() else -1
	var ck := Vector3i(si, bi, side)
	if cache.has(ck):
		return cache[ck]
	var bar: Variant = null
	if bi >= 0 and bi < r.barriers.size():
		bar = r.barriers[bi]
	elif bi == -2:
		bar = st.get("barrier_r" if side >= 1 else "barrier_l")
	var probe := {"kind": st.get("kind", "open"), "walk": st.get("walk", 4.0), "wall_gap": st.get("wall_gap", 0.6),
		"verge_w": st.get("verge_w", 4.0), "barrier_l": bar, "barrier_r": bar}
	var v := LevelStyles.treatment(probe, side)
	cache[ck] = v
	return v


## Steps 1-2 for one road: lateral steps of cell / 2 out to the sample's raster radius, along offsets
## 0 and step / 2; the cell under each point keeps the candidate with the smallest exact plan
## distance per class.
func _raster(r: LevelRoad, ri: int, pr: Dictionary, area: Rect2i, skipped: Dictionary, touched: PackedInt32Array, seen: PackedByteArray) -> void:
	var n: int = pr["n"]
	var step: float = pr["step"]
	var hs := step * 0.5
	var fr: PackedVector3Array = pr["fr"]
	var ff: PackedVector3Array = pr["ff"]
	var rad: PackedFloat32Array = pr["rad"]
	var aerial: PackedByteArray = pr["aerial"]
	var lat_step := cell * 0.5
	var inv := 1.0 / cell
	var ox := origin.x
	var oz := origin.y
	var ax0 := area.position.x
	var az0 := area.position.y
	var ax1 := area.end.x
	var az1 := area.end.y
	var has_skip := not skipped.is_empty()
	for i in n:
		if has_skip and i < r.seg.size() and skipped.has(r.seg[i]):
			continue
		var p := r.pos[i]
		var R: float = rad[i]
		# the sample's influence box against the area
		if (p.x + R + step - ox) * inv < ax0 - 1 or (p.x - R - step - ox) * inv > ax1 + 1:
			continue
		if (p.z + R + step - oz) * inv < az0 - 1 or (p.z - R - step - oz) * inv > az1 + 1:
			continue
		var rx := fr[i].x
		var rz := fr[i].z
		var fx := ff[i].x
		var fz := ff[i].z
		var air := aerial[i] != 0
		var steps := int(ceil(R / lat_step))
		var last := -1
		for along in [0.0, hs]:
			var bx: float = p.x + fx * along
			var bz: float = p.z + fz * along
			for li in range(-steps, steps + 1):
				var lat := li * lat_step
				var ix := int(round((bx + rx * lat - ox) * inv))
				var iz := int(round((bz + rz * lat - oz) * inv))
				if ix < ax0 or ix >= ax1 or iz < az0 or iz >= az1:
					continue
				var ci := iz * res + ix
				if ci == last:
					continue
				last = ci
				var dx := ox + ix * cell - p.x
				var dz := oz + iz * cell - p.z
				var clat := dx * rx + dz * rz
				var cal := absf(dx * fx + dz * fz) - hs
				var d := sqrt(clat * clat + (cal * cal if cal > 0.0 else 0.0))
				if d > R:
					continue
				if air:
					if d < _a_d[ci]:
						_a_d[ci] = d
						_a_road[ci] = ri
						_a_i[ci] = i
						_a_lat[ci] = clat
				else:
					if d < _g_d[ci]:
						_g_d[ci] = d
						_g_road[ci] = ri
						_g_i[ci] = i
						_g_lat[ci] = clat
				if seen[ci] == 0:
					seen[ci] = 1
					touched.append(ci)


## The sample box a stretch of road (samples i0..i1, wrapping on a loop) can carve: its samples'
## raster radius (width / 2 + treatment + flat + blend) plus a step, clamped to the grid.
func influence_rect(r: LevelRoad, i0: int, i1: int, flat: float, blend: float) -> Rect2i:
	if r == null or r.pos.is_empty():
		return Rect2i()
	var pr := _prep(r, maxf(flat, 0.0), maxf(blend, 0.01))
	var n: int = pr["n"]
	if n <= 0:
		return Rect2i()
	var rad: PackedFloat32Array = pr["rad"]
	var step: float = pr["step"]
	var out := Rect2i()
	var first := true
	var count := i1 - i0 + 1
	if count <= 0:
		count = (i1 + n - i0) % n + 1 if r.closed else 0
	count = mini(count, n)
	for k in count:
		var i := (i0 + k) % n if r.closed else clampi(i0 + k, 0, n - 1)
		var rr := rect_of(Vector2(r.pos[i].x, r.pos[i].z), rad[i] + step)
		if rr.size.x <= 0 or rr.size.y <= 0:
			continue
		out = rr if first else out.merge(rr)
		first = false
	return out


# ---------------------------------------------------------------- sampling

## Bilinear on the carved heights; NAN outside the world, at a hole, or with no terrain.
func height_at(x: float, z: float) -> float:
	return _sample(heights, x, z)


## Bilinear on the natural (uncarved) heights.
func natural_at(x: float, z: float) -> float:
	return _sample(natural, x, z)


func _sample(h: PackedFloat32Array, x: float, z: float) -> float:
	if h.size() != res * res or res < 2:
		return NAN
	var fx := (x - origin.x) / cell
	var fz := (z - origin.y) / cell
	var top_i := float(res - 1)
	if fx < 0.0 or fz < 0.0 or fx > top_i or fz > top_i or is_nan(fx) or is_nan(fz):
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


## The ground normal from central differences (Vector3.UP where it cannot tell).
func normal_at(x: float, z: float) -> Vector3:
	var c := height_at(x, z)
	if is_nan(c):
		return Vector3.UP
	var l := height_at(x - cell, z)
	var r := height_at(x + cell, z)
	var b := height_at(x, z - cell)
	var f := height_at(x, z + cell)
	var dx := 0.0
	var dz := 0.0
	if not is_nan(l) and not is_nan(r):
		dx = (r - l) / (2.0 * cell)
	elif not is_nan(r):
		dx = (r - c) / cell
	elif not is_nan(l):
		dx = (c - l) / cell
	if not is_nan(b) and not is_nan(f):
		dz = (f - b) / (2.0 * cell)
	elif not is_nan(f):
		dz = (f - c) / cell
	elif not is_nan(b):
		dz = (c - b) / cell
	return Vector3(-dx, 1.0, -dz).normalized()


## The highest non-hole height (0 when every sample is a hole).
func top() -> float:
	var m := -INF
	for v in heights:
		if v > m:
			m = v
	return m if m > -INF else 0.0


## The lowest non-hole height (0 when every sample is a hole).
func bottom() -> float:
	var m := INF
	for v in heights:
		if v < m:
			m = v
	return m if m < INF else 0.0


## Where a ray first meets the carved ground (holes let it through); Vector3(NAN, NAN, NAN) on a
## miss. Marches in cell steps inside the world box, then bisects.
func raycast(from: Vector3, dir: Vector3, max_d := 6000.0) -> Vector3:
	var miss := Vector3(NAN, NAN, NAN)
	if heights.size() != res * res or res < 2 or dir.length_squared() < 1e-12:
		return miss
	var d := dir.normalized()
	var lo := Vector3(origin.x, HEIGHT_MIN, origin.y)
	var hi := Vector3(origin.x + size(), HEIGHT_MAX, origin.y + size())
	var t0 := 0.0
	var t1 := max_d
	for a in 3:
		var o := from[a]
		var v := d[a]
		if absf(v) < 1e-12:
			if o < lo[a] or o > hi[a]:
				return miss
			continue
		var ta := (lo[a] - o) / v
		var tb := (hi[a] - o) / v
		if ta > tb:
			var s := ta
			ta = tb
			tb = s
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return miss
	var st := cell * 0.75
	var prev_t := -1.0
	var t := t0
	while t <= t1 + 1e-6:
		var p := from + d * t
		var h := height_at(p.x, p.z)
		if not is_nan(h):
			if p.y <= h:
				if prev_t >= 0.0:
					var a := prev_t
					var b := t
					for k in 12:
						var m := (a + b) * 0.5
						var q := from + d * m
						var hm := height_at(q.x, q.z)
						if not is_nan(hm) and q.y <= hm:
							b = m
						else:
							a = m
					var hit := from + d * b
					var hy := height_at(hit.x, hit.z)
					return Vector3(hit.x, hy if not is_nan(hy) else hit.y, hit.z)
			else:
				prev_t = t
		else:
			prev_t = t  # over a hole the ray is free
		t += st
	return miss


## The nearest sample to a world point (not clamped to the grid).
func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(roundi((x - origin.x) / cell), roundi((z - origin.y) / cell))


## The samples within a circle's box, clamped to the grid (an empty Rect2i outside).
func rect_of(center: Vector2, radius: float) -> Rect2i:
	var x0 := maxi(floori((center.x - radius - origin.x) / cell), 0)
	var z0 := maxi(floori((center.y - radius - origin.y) / cell), 0)
	var x1 := mini(ceili((center.x + radius - origin.x) / cell), res - 1)
	var z1 := mini(ceili((center.y + radius - origin.y) / cell), res - 1)
	if x1 < x0 or z1 < z0:
		return Rect2i()
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


# ---------------------------------------------------------------- chunks

## Render chunks per side (CHUNK cells each).
func chunk_count() -> int:
	return ceili(float(res - 1) / CHUNK) if res > 1 else 0


## Collision tiles per side (TILE cells each).
func tile_count() -> int:
	return ceili(float(res - 1) / TILE) if res > 1 else 0


## The chunks whose mesh (vertices, and the normals' neighbours one sample out) uses a sample of
## `rect`: the ones to rebuild after a change there.
func chunks_in(rect: Rect2i) -> Array[Vector2i]:
	return _windows(rect, CHUNK, 1, chunk_count())


## The tiles whose height samples include a sample of `rect`.
func tiles_in(rect: Rect2i) -> Array[Vector2i]:
	return _windows(rect, TILE, 0, tile_count())


func _windows(rect: Rect2i, span: int, pad: int, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rect.size.x <= 0 or rect.size.y <= 0 or count <= 0:
		return out
	var x0 := clampi(ceili(float(rect.position.x - span - pad) / span), 0, count - 1)
	var x1 := clampi(floori(float(rect.end.x - 1 + pad) / span), 0, count - 1)
	var z0 := clampi(ceili(float(rect.position.y - span - pad) / span), 0, count - 1)
	var z1 := clampi(floori(float(rect.end.y - 1 + pad) / span), 0, count - 1)
	if rect.end.x - 1 < -pad or rect.position.x > res - 1 + pad or rect.end.y - 1 < -pad or rect.position.y > res - 1 + pad:
		return out
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			out.append(Vector2i(cx, cz))
	return out


## Mesh arrays (Mesh.ARRAY_MAX) of one render chunk: lod 0 every sample (65 x 65), lod 1 every
## second (33 x 33) plus a LOD_SKIRT skirt round its border. World coordinates, normals from central
## differences, COLOR = splat / 255, UV = (x, z) / 4, tangents along +X; triangles touching a hole
## are left out. [] when the chunk has no triangle (all holes) or is outside the grid.
func chunk_arrays(cx: int, cz: int, lod := 0) -> Array:
	var cc := chunk_count()
	if cx < 0 or cz < 0 or cx >= cc or cz >= cc or heights.size() != res * res:
		return []
	var stride := 2 if lod >= 1 else 1
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	var span_x := mini(CHUNK, res - 1 - x0)
	var span_z := mini(CHUNK, res - 1 - z0)
	var nx := span_x / stride + 1
	var nz := span_z / stride + 1
	var nv := nx * nz
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var hole := PackedByteArray()
	verts.resize(nv)
	norms.resize(nv)
	tans.resize(nv * 4)
	cols.resize(nv)
	uvs.resize(nv)
	hole.resize(nv)
	hole.fill(0)
	var hs := heights
	var sp := splat
	var has_sp := sp.size() == res * res * 4
	var fallback := INF
	for j in nz:
		var row := (z0 + j * stride) * res + x0
		for i in nx:
			var v := hs[row + i * stride]
			if v < fallback:
				fallback = v
	if fallback == INF:
		return []
	var inv255 := 1.0 / 255.0
	var two_c := 2.0 * cell
	var last := res - 1
	var none := Color(0, 0, 0, 0)
	for j in nz:
		var sz := z0 + j * stride
		var row := sz * res
		var wz := origin.y + sz * cell
		for i in nx:
			var sx := x0 + i * stride
			var k := j * nx + i
			var ci := row + sx
			var h := hs[ci]
			var wx := origin.x + sx * cell
			uvs[k] = Vector2(wx * 0.25, wz * 0.25)
			if has_sp:
				var si := ci * 4
				cols[k] = Color(sp[si] * inv255, sp[si + 1] * inv255, sp[si + 2] * inv255, sp[si + 3] * inv255)
			else:
				cols[k] = none
			var k4 := k * 4
			if h != h:  # NAN: a hole
				hole[k] = 1
				verts[k] = Vector3(wx, fallback, wz)
				norms[k] = Vector3.UP
				tans[k4] = 1.0
				tans[k4 + 1] = 0.0
				tans[k4 + 2] = 0.0
				tans[k4 + 3] = -1.0
				continue
			verts[k] = Vector3(wx, h, wz)
			# central differences (one-sided at the world edge and beside a hole)
			var l := hs[ci - 1] if sx > 0 else NAN
			var r := hs[ci + 1] if sx < last else NAN
			var bk := hs[ci - res] if sz > 0 else NAN
			var fw := hs[ci + res] if sz < last else NAN
			var dx := 0.0
			var dz := 0.0
			# (x == x is false only for NAN)
			if l == l:
				dx = (r - l) / two_c if r == r else (h - l) / cell
			elif r == r:
				dx = (r - h) / cell
			if bk == bk:
				dz = (fw - bk) / two_c if fw == fw else (h - bk) / cell
			elif fw == fw:
				dz = (fw - h) / cell
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			norms[k] = nrm
			# tangent along +X off the normal; w so the binormal (N x T * w) runs along +Z (V)
			var tv := Vector3(1.0 - nrm.x * nrm.x, -nrm.x * nrm.y, -nrm.x * nrm.z).normalized()
			tans[k4] = tv.x
			tans[k4 + 1] = tv.y
			tans[k4 + 2] = tv.z
			tans[k4 + 3] = 1.0 if nrm.x * tv.y - nrm.y * tv.x >= 0.0 else -1.0
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var ni := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# Godot's front face: (a, b, c), (b, d, c) seen from above
			if hole[b] != 0 or hole[c] != 0:
				continue
			if hole[a] == 0:
				idx[ni] = a
				idx[ni + 1] = b
				idx[ni + 2] = c
				ni += 3
			if hole[d] == 0:
				idx[ni] = b
				idx[ni + 1] = d
				idx[ni + 2] = c
				ni += 3
	idx.resize(ni)
	if idx.is_empty():
		return []
	if lod >= 1:
		_lod_skirt(verts, norms, tans, cols, uvs, hole, idx, nx, nz)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## LOD1's skirt: the border vertices copied LOD_SKIRT down, a strip each way round the border.
func _lod_skirt(verts: PackedVector3Array, norms: PackedVector3Array, tans: PackedFloat32Array, cols: PackedColorArray, uvs: PackedVector2Array, hole: PackedByteArray, idx: PackedInt32Array, nx: int, nz: int) -> void:
	var ring := PackedInt32Array()
	for i in nx:
		ring.append(i)
	for j in range(1, nz):
		ring.append(j * nx + nx - 1)
	for i in range(nx - 2, -1, -1):
		ring.append((nz - 1) * nx + i)
	for j in range(nz - 2, -1, -1):
		ring.append(j * nx)
	var low := PackedInt32Array()
	low.resize(ring.size())
	var base := verts.size()
	verts.resize(base + ring.size())
	norms.resize(base + ring.size())
	tans.resize((base + ring.size()) * 4)
	cols.resize(base + ring.size())
	uvs.resize(base + ring.size())
	for q in ring.size():
		var src := ring[q]
		var k := base + q
		low[q] = k
		verts[k] = verts[src] - Vector3(0, LOD_SKIRT, 0)
		norms[k] = norms[src]
		for c in 4:
			tans[k * 4 + c] = tans[src * 4 + c]
		cols[k] = cols[src]
		uvs[k] = uvs[src] + Vector2(0, LOD_SKIRT / 4.0)
	for q in ring.size() - 1:
		var a := ring[q]
		var b := ring[q + 1]
		if hole[a] != 0 or hole[b] != 0:
			continue
		# both faces: the skirt is seen from whichever side the neighbour leaves open
		idx.append_array([a, b, low[q], b, low[q + 1], low[q]])
		idx.append_array([a, low[q], b, b, low[q], low[q + 1]])


## Mesh arrays of the world's edge skirt ("deco_world_edge"): a wall EDGE_DROP m down from every
## border sample, facing out, in the base layer's colour. [] without terrain.
func edge_skirt_arrays() -> Array:
	if heights.size() != res * res or res < 2:
		return []
	var ring := PackedInt32Array()
	for i in res:
		ring.append(i)
	for j in range(1, res):
		ring.append(j * res + res - 1)
	for i in range(res - 2, -1, -1):
		ring.append((res - 1) * res + i)
	for j in range(res - 2, -1, -1):
		ring.append(j * res)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var mid := Vector3(origin.x + size() * 0.5, 0, origin.y + size() * 0.5)
	var along := 0.0
	for q in ring.size() - 1:
		var a := ring[q]
		var b := ring[q + 1]
		var ha := heights[a]
		var hb := heights[b]
		var pa := Vector3(origin.x + (a % res) * cell, ha, origin.y + (a / res) * cell)
		var pb := Vector3(origin.x + (b % res) * cell, hb, origin.y + (b / res) * cell)
		var seg := pa.distance_to(Vector3(pb.x, ha, pb.z))
		if is_nan(ha) or is_nan(hb):
			along += cell
			continue
		var out_n := Vector3((pa.x + pb.x) * 0.5 - mid.x, 0, (pa.z + pb.z) * 0.5 - mid.z)
		# the side of the world this edge is on
		out_n = Vector3(signf(out_n.x), 0, 0) if absf(out_n.x) > absf(out_n.z) else Vector3(0, 0, signf(out_n.z))
		var k := verts.size()
		verts.append_array([pa, pb, pb - Vector3(0, EDGE_DROP, 0), pa - Vector3(0, EDGE_DROP, 0)])
		for c in 4:
			norms.append(out_n)
			cols.append(Color(0, 0, 0, 0))
		uvs.append_array([Vector2(along, -ha) / 4.0, Vector2(along + seg, -hb) / 4.0,
			Vector2(along + seg, -hb + EDGE_DROP) / 4.0, Vector2(along, -ha + EDGE_DROP) / 4.0])
		along += seg
		_tri_facing(idx, verts, k, k + 1, k + 2, out_n)
		_tri_facing(idx, verts, k, k + 2, k + 3, out_n)
	if idx.is_empty():
		return []
	var tans := PackedFloat32Array()
	tans.resize(verts.size() * 4)
	for k in verts.size():
		var t := Vector3.UP.cross(norms[k]).normalized()
		tans[k * 4] = t.x
		tans[k * 4 + 1] = t.y
		tans[k * 4 + 2] = t.z
		tans[k * 4 + 3] = 1.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## One triangle wound so its front faces `facing` (Godot: clockwise seen from the front).
static func _tri_facing(idx: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, facing: Vector3) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(facing) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


## A hash of everything one chunk's meshes are made of (its height window one sample out, for
## the normals, and its splat), so a bake swaps only the chunks that changed.
func chunk_hash(cx: int, cz: int) -> int:
	var cc := chunk_count()
	if cx < 0 or cz < 0 or cx >= cc or cz >= cc:
		return 0
	var x0 := maxi(cx * CHUNK - 1, 0)
	var x1 := mini(cx * CHUNK + CHUNK + 1, res - 1)
	var z0 := maxi(cz * CHUNK - 1, 0)
	var z1 := mini(cz * CHUNK + CHUNK + 1, res - 1)
	var hb := PackedFloat32Array()
	for z in range(z0, z1 + 1):
		hb.append_array(heights.slice(z * res + x0, z * res + x1 + 1))
	var sb := PackedByteArray()
	var sx0 := cx * CHUNK
	var sx1 := mini(cx * CHUNK + CHUNK, res - 1)
	if splat.size() == res * res * 4:
		for z in range(cz * CHUNK, mini(cz * CHUNK + CHUNK, res - 1) + 1):
			sb.append_array(splat.slice((z * res + sx0) * 4, (z * res + sx1 + 1) * 4))
	return hash([hash(hb.to_byte_array()), hash(sb), cx, cz, res])


## A hash of one collision tile's heights (129 x 129 samples).
func tile_hash(tx: int, tz: int) -> int:
	var tc := tile_count()
	if tx < 0 or tz < 0 or tx >= tc or tz >= tc:
		return 0
	var x0 := tx * TILE
	var x1 := mini(x0 + TILE, res - 1)
	var hb := PackedFloat32Array()
	for z in range(tz * TILE, mini(tz * TILE + TILE, res - 1) + 1):
		hb.append_array(heights.slice(z * res + x0, z * res + x1 + 1))
	return hash([hash(hb.to_byte_array()), tx, tz, res])


## HeightMapShape3D data of one tile: (TILE + 1)^2 samples of heights / cell (NAN for a hole; a
## tile past the grid's end repeats the last sample). Pure, so a worker can make it.
func tile_data(tx: int, tz: int) -> PackedFloat32Array:
	var w := TILE + 1
	var md := PackedFloat32Array()
	md.resize(w * w)
	var inv := 1.0 / cell
	for j in w:
		var sz := mini(tz * TILE + j, res - 1)
		for i in w:
			var sx := mini(tx * TILE + i, res - 1)
			md[j * w + i] = heights[sz * res + sx] * inv
	return md


## Main thread: StaticBody3D "col_terrain_<tx>_<tz>" (world layer, mask 0, surface offroad,
## friction 0.9) with a square HeightMapShape3D scaled by `cell`, at the tile's centre.
func tile_body(tx: int, tz: int) -> StaticBody3D:
	var tc := tile_count()
	if tx < 0 or tz < 0 or tx >= tc or tz >= tc or heights.size() != res * res:
		return null
	var sh := HeightMapShape3D.new()
	sh.map_width = TILE + 1
	sh.map_depth = TILE + 1
	sh.map_data = tile_data(tx, tz)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.scale = Vector3.ONE * cell
	var body := StaticBody3D.new()
	body.name = "col_terrain_%d_%d" % [tx, tz]
	body.collision_layer = 1  # Game.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", "offroad")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	body.physics_material_override = pm
	body.position = Vector3(origin.x + (tx * TILE + TILE * 0.5) * cell, 0.0, origin.y + (tz * TILE + TILE * 0.5) * cell)
	body.add_child(cs)
	return body


## Main thread: the MeshInstance3D of one chunk ("terrain_<cx>_<cz>" / "terrain_lod_<cx>_<cz>",
## meta no_collision, LOD1 also no_shadow, visibility ranges 3.4), or null for an empty chunk.
## Track.dress gives it the shared terrain material.
func chunk_node(cx: int, cz: int, lod := 0) -> MeshInstance3D:
	var arr := chunk_arrays(cx, cz, lod)
	if arr.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = ("terrain_lod_%d_%d" if lod >= 1 else "terrain_%d_%d") % [cx, cz]
	mi.set_meta("no_collision", true)
	var chunk_m := CHUNK * cell
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if lod >= 1:
		mi.set_meta("no_shadow", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_begin = 3.0 * chunk_m
		mi.visibility_range_begin_margin = LOD_MARGIN
	else:
		mi.visibility_range_end = 3.0 * chunk_m + LOD_MARGIN
		mi.visibility_range_end_margin = LOD_MARGIN
	return mi


## Main thread: the world edge skirt "deco_world_edge" (meta no_collision, no_shadow), its
## surface material a placeholder named after the base layer's material key (Track.dress swaps in
## the world material). null without terrain.
func edge_skirt_node() -> MeshInstance3D:
	var arr := edge_skirt_arrays()
	if arr.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := StandardMaterial3D.new()
	m.resource_name = str(layers.get("base", "nature/grassfloor002a"))
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "deco_world_edge"
	mi.set_meta("no_collision", true)
	mi.set_meta("no_shadow", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
