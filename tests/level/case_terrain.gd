extends RefCounted
## P3 (spec 3.4): LevelTerrain without content. The carve on hand-made LevelRoad arrays (the bed at
## road_y - 0.35, natural 60 m away, a cutting, tunnels keeping the hill with NAN mouths and a clear
## floor, a bridge, a gap's dip, a pit, `skip`, a local re-carve by rect equal to the full one),
## chunk and tile counts, square 129 tiles, holes skipping triangles, the winding, the LOD1 and
## edge skirts, raycasts, hashes that change only for touched chunks / tiles, and a tile body in
## the physics world.

const NEEDS_CONTENT := false

const OPEN := {"kind": "open", "verge_w": 4.0, "bank": true}
const TUNNEL := {"kind": "tunnel", "height": 7.5, "wall_gap": 0.6, "bank": false}
const BRIDGE := {"kind": "bridge", "skirt_h": 1.5, "bank": false}
const FLAT := 6.0
const BLEND := 28.0


func run(t: Node) -> void:
	_from_doc(t)
	_carve_open(t)
	_carve_tunnel(t)
	_carve_aerial(t)
	_pit_and_skip(t)
	_local_recarve(t)
	_chunks(t)
	_holes_and_winding(t)
	_raycast(t)
	_hashes(t)
	await _physics(t)
	_dress(t)
	_cost(t)


## A straight road along +x at z = 0 from x0 to x1 (2 m samples), height y (a Callable(x) or a
## float), style index per sample from `kind_of` (Callable(x) -> int, default 0).
static func road(x0: float, x1: float, y: Variant, styles: Array, kind_of := Callable(), width := 10.0, closed := false) -> LevelRoad:
	var r := LevelRoad.new()
	var n := int(round((x1 - x0) / 2.0)) + 1
	r.n = n
	r.step = 2.0
	r.closed = closed
	r.key = -1
	r.length = x1 - x0
	var st: Array[Dictionary] = []
	for s in styles:
		st.append(s)
	r.styles = st
	for i in n:
		var x := x0 + i * 2.0
		var yy: float = (y as Callable).call(x) if y is Callable else float(y)
		r.pos.append(Vector3(x, yy, 0.0))
		r.fwd.append(Vector3(1, 0, 0))
		r.flat_right.append(Vector3(0, 0, 1))
		r.right.append(Vector3(0, 0, 1))
		r.up.append(Vector3.UP)
		r.width.append(width)
		r.style.append(int(kind_of.call(x)) if kind_of.is_valid() else 0)
		r.seg.append(i / 10)
		r.segt.append((i % 10) / 10.0)
		r.s.append(i * 2.0)
		r.height.append(0.0)
		r.gap.append(0)
		r.dip.append(0.0)
		r.bar_l.append(-1)
		r.bar_r.append(-1)
	return r


static func _world(natural: Callable, size := 512.0, res := 257) -> LevelTerrain:
	var tr := LevelTerrain.flat_world(size, res)
	for iz in tr.res:
		for ix in tr.res:
			tr.natural[iz * tr.res + ix] = natural.call(tr.origin.x + ix * tr.cell, tr.origin.y + iz * tr.cell)
	tr.heights = tr.natural.duplicate()
	return tr


func _from_doc(t: Node) -> void:
	var doc := LevelDoc.blank("terrain test", 512.0, 257)
	doc.heights[5] = 12.5
	var tr := LevelTerrain.from_doc(doc)
	t.check(tr != null, "from_doc: a terrain for a world with terrain")
	if tr == null:
		return
	t.check(tr.res == 257 and is_equal_approx(tr.cell, 2.0) and tr.origin == Vector2(-256, -256), "from_doc: res 257, cell 2, origin -256 (got %d, %s, %s)" % [tr.res, tr.cell, tr.origin])
	t.check(tr.natural.size() == 257 * 257 and tr.heights.size() == 257 * 257 and tr.splat.size() == 257 * 257 * 4, "from_doc: arrays sized")
	t.check(is_equal_approx(tr.natural[5], 12.5), "from_doc: the doc's heights")
	tr.natural[5] = 1.0
	t.check(is_equal_approx(doc.heights[5], 12.5), "from_doc: copies, never shares the doc's arrays")
	t.check(tr.layers.has("base"), "from_doc: the layers")
	t.check(LevelTerrain.from_doc(LevelDoc.blank("none", 512.0, 0)) == null, "from_doc: null without terrain")
	t.check(is_nan(tr.height_at(400.0, 0.0)) and is_nan(tr.height_at(0.0, -300.0)), "height_at: NAN outside the world")


func _carve_open(t: Node) -> void:
	# a road 5 m above flat ground (an embankment) and one 15 m under a plateau (a cutting)
	var tr := _world(func(_x: float, _z: float) -> float: return 0.0)
	var r := road(-150.0, 150.0, 5.0, [OPEN])
	var ms: float = t.ms(func() -> void: tr.carve([r], FLAT, BLEND))
	t.log("carve of a 300 m road on 257 x 257: %.1f ms" % ms)
	t.near(tr.height_at(0.0, 0.0), 5.0 - 0.35, 0.05, "open: the bed at road_y - 0.35 on the centre line")
	t.near(tr.height_at(1.0, 3.0), 5.0 - 0.35, 0.05, "open: the bed under the road's side")
	t.near(tr.height_at(0.0, 5.0 + 4.0 + FLAT - 0.5), 5.0 - 0.35, 0.05, "open: flat shoulders out to half + flat")
	t.check(tr.height_at(0.0, 60.0) == 0.0, "open: natural 60 m away (%s)" % tr.height_at(0.0, 60.0))
	var mid := tr.height_at(0.0, 5.0 + 4.0 + FLAT + BLEND * 0.5)
	t.check(mid > 0.5 and mid < 4.5, "open: blending in between (%s)" % mid)
	t.check(tr.height_at(0.0, 0.0) <= 5.0 - LevelTerrain.CLEAR, "open: CLEAR under the surface")
	t.check(tr.natural_at(0.0, 0.0) == 0.0, "open: natural untouched")
	t.check(tr.height_at(185.0, 0.0) < 4.0 and tr.height_at(200.0, 0.0) == 0.0, "open: the carve ends past the open road's end")
	var cut := _world(func(_x: float, _z: float) -> float: return 20.0)
	cut.carve([road(-150.0, 150.0, 5.0, [OPEN])], FLAT, BLEND)
	t.near(cut.height_at(0.0, 0.0), 4.65, 0.05, "cutting: the bed under the plateau")
	t.check(cut.height_at(0.0, 60.0) == 20.0, "cutting: the plateau 60 m away")
	# banked: the bed follows the bank inside the width
	var bank := _world(func(_x: float, _z: float) -> float: return 0.0)
	var rb := road(-150.0, 150.0, 5.0, [OPEN])
	var b := 0.1
	for i in rb.n:
		rb.right[i] = Vector3(0, -sin(b), cos(b))
	bank.carve([rb], FLAT, BLEND)
	var slope := -sin(b) / cos(b)
	t.near(bank.height_at(0.0, 4.0) - bank.height_at(0.0, -4.0), slope * 8.0, 0.1, "bank: the bed tilts with the road")
	t.check(bank.height_at(0.0, 4.0) <= 5.0 + slope * 4.0 - LevelTerrain.CLEAR, "bank: CLEAR under the low side")


func _carve_tunnel(t: Node) -> void:
	# a hill (30 m, sloping to 0 between |x| 20 and 50) over a tunnel stretch |x| < 60 at y 0.5
	var hill := func(x: float, _z: float) -> float: return 30.0 * clampf(1.0 - (absf(x) - 20.0) / 30.0, 0.0, 1.0)
	var tr := _world(hill)
	var r := road(-150.0, 150.0, 0.5, [OPEN, TUNNEL], func(x: float) -> int: return 1 if absf(x) < 60.0 else 0)
	tr.carve([r], FLAT, BLEND)
	var surf := 0.5
	var roof := surf + 7.5
	t.check(tr.height_at(0.0, 0.0) == 30.0, "tunnel: the hill over the tube keeps its height (%s)" % tr.height_at(0.0, 0.0))
	t.check(tr.height_at(0.0, 15.0) == 30.0, "tunnel: the hill beside the tube stays (%s)" % tr.height_at(0.0, 15.0))
	var mouth := tr.cell_of(44.0, 0.0)
	t.check(is_nan(tr.heights[mouth.y * tr.res + mouth.x]), "tunnel: the mouth is a hole")
	var mouth2 := tr.cell_of(-46.0, 2.0)
	t.check(is_nan(tr.heights[mouth2.y * tr.res + mouth2.x]), "tunnel: the other mouth is a hole")
	t.check(not is_nan(tr.height_at(30.0, 0.0)) and tr.height_at(30.0, 0.0) >= roof + 1.5, "tunnel: still hill inside at x 30")
	var bad := 0
	var holes := 0
	var half := 5.0 + 0.6 + 0.5
	for iz in tr.res:
		var z := tr.origin.y + iz * tr.cell
		if absf(z) > half:
			continue
		for ix in tr.res:
			var x := tr.origin.x + ix * tr.cell
			if absf(x) >= 58.0:
				continue
			var h := tr.heights[iz * tr.res + ix]
			if is_nan(h):
				holes += 1
			elif h > surf - LevelTerrain.CLEAR and h < roof + 1.5 - 1e-3:
				bad += 1
	t.check(bad == 0, "tunnel: the floor stays clear (no ground between the floor and the roof + 1.5; %d cells)" % bad)
	t.check(holes > 0, "tunnel: holes at the mouths (%d)" % holes)
	t.near(tr.height_at(100.0, 0.0), 0.15, 0.05, "tunnel: the open road beyond keeps its bed")
	_steep_face(t)


## L3: a tunnel mouth in a steep hill face (10 m of hill, a 2 m face at |x| 59..61, the tube
## |x| < 60, its roof 7.5 m): along the road, at its centre and 3 m to each side, the ground is the
## bed, a hole or the hill above the roof + 1.5 m, never a slope across the opening at kart height;
## the hill over and beside the tube stays; a local re-carve of the mouth equals the full carve.
func _steep_face(t: Node) -> void:
	var face := func(x: float, _z: float) -> float: return 10.0 * clampf((61.0 - absf(x)) / 2.0, 0.0, 1.0)
	var tr := _world(face)
	var r := road(-150.0, 150.0, 0.0, [OPEN, TUNNEL], func(x: float) -> int: return 1 if absf(x) < 60.0 else 0)
	tr.carve([r], FLAT, BLEND)
	var roof := 7.5
	var wall := 0
	var at := ""
	for z in [-3.0, 0.0, 3.0]:
		var x := -80.0
		while x <= 80.0:
			var h := tr.height_at(x, z)
			if not is_nan(h) and h > -LevelTerrain.CLEAR + 0.01 and h < roof + 1.5 - 0.01:
				wall += 1
				if at == "":
					at = "(%.2f, %.0f) %.2f m" % [x, z, h]
			x += 0.25
	t.check(wall == 0, "steep face: no ground across either mouth between the floor and the roof + 1.5 (%d points; first %s)" % [wall, at])
	t.check(tr.height_at(0.0, 0.0) == 10.0 and tr.height_at(40.0, 0.0) == 10.0, "steep face: the hill over the tube stays")
	t.check(tr.height_at(0.0, 15.0) == 10.0 and tr.height_at(56.0, 12.0) == 10.0, "steep face: the hill beside the tube stays (%s)" % tr.height_at(56.0, 12.0))
	# the local re-carve round the east mouth: the same heights (NAN where the full carve has a hole)
	var full := tr.heights.duplicate()
	var rect := tr.influence_rect(r, 100, 112, FLAT, BLEND)
	tr.carve([r], FLAT, BLEND, rect)
	var holes := 0
	var diff := 0
	var worst := 0.0
	for ci in full.size():
		var a := full[ci]
		var b := tr.heights[ci]
		if is_nan(a) != is_nan(b):
			diff += 1
		elif is_nan(a):
			holes += 1
		else:
			worst = maxf(worst, absf(a - b))
	t.check(rect.size.x > 0 and holes > 0 and diff == 0 and worst < 0.05,
		"steep face: a local re-carve of the east mouth equals the full carve (%d holes, %d differ, worst %.4f m)" % [holes, diff, worst])


func _carve_aerial(t: Node) -> void:
	# a bridge 20 m over flat ground at 10 m: the ground stays under the skirt; open approaches
	var tr := _world(func(_x: float, _z: float) -> float: return 10.0)
	var deck := 12.0
	var r := road(-150.0, 150.0, deck, [OPEN, BRIDGE], func(x: float) -> int: return 1 if absf(x) < 50.0 else 0)
	tr.carve([r], FLAT, BLEND)
	t.check(tr.height_at(0.0, 0.0) <= deck - 1.5 - 1.0 + 1e-3, "bridge: the ground under the skirt (%s)" % tr.height_at(0.0, 0.0))
	t.check(tr.height_at(0.0, 40.0) == 10.0, "bridge: natural beside it")
	# a gap (jump) on an open road: the ground dips 8 m under it
	var g := _world(func(_x: float, _z: float) -> float: return 0.0)
	var rg := road(-150.0, 150.0, 1.0, [OPEN])
	for i in rg.n:
		if absf(rg.pos[i].x) < 30.0:
			rg.gap[i] = 1
	g.carve([rg], FLAT, BLEND)
	t.check(g.height_at(0.0, 0.0) <= 1.0 - 8.0 + 0.5, "gap: the ground dips under the jump (%s)" % g.height_at(0.0, 0.0))
	t.near(g.height_at(100.0, 0.0), 0.65, 0.05, "gap: the bed past it")


func _pit_and_skip(t: Node) -> void:
	var tr := _world(func(_x: float, _z: float) -> float: return 0.0)
	var r := road(-150.0, 150.0, 5.0, [OPEN])
	tr.carve([r], FLAT, BLEND, Rect2i(), [{"center": Vector2(0, 120), "radius": 10.0, "floor_y": -20.0}])
	t.near(tr.height_at(0.0, 120.0), -20.0, 0.01, "pit: the floor at its centre")
	t.near(tr.height_at(8.0, 120.0), -20.0, 0.01, "pit: the floor within the radius")
	var rim := tr.height_at(12.0, 120.0)
	t.check(rim > -20.0 and rim < 0.0, "pit: a rim between (%s)" % rim)
	t.check(tr.height_at(20.0, 120.0) == 0.0, "pit: natural beyond the rim")
	t.near(tr.height_at(0.0, 0.0), 4.65, 0.05, "pit: the road's bed unchanged")
	# skip: segments 5..10 (x -50 .. 68) left out
	var sk := _world(func(_x: float, _z: float) -> float: return 0.0)
	sk.carve([r], FLAT, BLEND, Rect2i(), [], {-1: PackedInt32Array([5, 6, 7, 8, 9, 10])})
	t.check(sk.height_at(9.0, 0.0) == 0.0, "skip: the skipped samples' cells stay natural (%s)" % sk.height_at(9.0, 0.0))
	t.near(sk.height_at(-100.0, 0.0), 4.65, 0.05, "skip: the rest is carved")


func _local_recarve(t: Node) -> void:
	var tr := _world(func(x: float, z: float) -> float: return 3.0 * sin(x * 0.02) + 2.0 * cos(z * 0.03))
	var r := road(-200.0, 200.0, 5.0, [OPEN])
	tr.carve([r], FLAT, BLEND)
	var before := tr.heights.duplicate()
	# raise segment 20 (samples 100..109, x 0..18) by 4 m and re-carve only its influence box
	var r2 := road(-200.0, 200.0, func(x: float) -> float: return 9.0 if x >= 0.0 and x <= 18.0 else 5.0, [OPEN])
	var rect := tr.influence_rect(r2, 99, 110, FLAT, BLEND)
	t.check(rect.size.x > 0 and rect.size.y > 0, "influence_rect: a box (%s)" % rect)
	var ms: float = t.ms(func() -> void: tr.carve([r2], FLAT, BLEND, rect))
	t.log("local re-carve of %d x %d samples: %.1f ms" % [rect.size.x, rect.size.y, ms])
	var full := _world(func(x: float, z: float) -> float: return 3.0 * sin(x * 0.02) + 2.0 * cos(z * 0.03))
	full.carve([r2], FLAT, BLEND)
	var outside := 0
	var worst := 0.0
	for iz in tr.res:
		for ix in tr.res:
			var ci := iz * tr.res + ix
			if rect.has_point(Vector2i(ix, iz)):
				worst = maxf(worst, absf(tr.heights[ci] - full.heights[ci]))
			elif tr.heights[ci] != before[ci]:
				outside += 1
	t.check(outside == 0, "local re-carve: nothing outside the rect changes (%d)" % outside)
	t.check(worst < 0.05, "local re-carve: equals the full carve inside the rect (worst %.4f m)" % worst)
	t.near(tr.height_at(9.0, 0.0), 9.0 - 0.35, 0.05, "local re-carve: the raised bed")


func _chunks(t: Node) -> void:
	var tr := LevelTerrain.flat_world(512.0, 257, 2.0)
	t.check(tr.chunk_count() == 4 and tr.tile_count() == 2, "257: 4 chunks and 2 tiles per side")
	var big := LevelTerrain.flat_world(1024.0, 513)
	t.check(big.chunk_count() == 8 and big.tile_count() == 4, "513: 8 chunks and 4 tiles per side")
	var huge := LevelTerrain.flat_world(4096.0, 1025)
	t.check(huge.chunk_count() == 16 and huge.tile_count() == 8, "1025: 16 chunks (256) and 8 tiles (64) per side")
	var a := tr.chunk_arrays(1, 2, 0)
	t.check(a.size() == Mesh.ARRAY_MAX, "chunk_arrays: Mesh.ARRAY_MAX arrays")
	if a.size() == Mesh.ARRAY_MAX:
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		t.check(v.size() == 65 * 65, "LOD0: 65 x 65 vertices (%d)" % v.size())
		t.check(idx.size() == 64 * 64 * 6, "LOD0: 64 x 64 x 2 triangles")
		t.check((a[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == v.size() * 4 and (a[Mesh.ARRAY_COLOR] as PackedColorArray).size() == v.size() and (a[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == v.size(), "LOD0: tangents, colours, UVs per vertex")
		t.check(v[0].is_equal_approx(Vector3(-256.0 + 64 * 2.0, 2.0, -256.0 + 128 * 2.0)), "LOD0: world coordinates (%s)" % v[0])
		t.check((a[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[0].is_equal_approx(Vector2(v[0].x, v[0].z) / 4.0), "LOD0: UV = (x, z) / 4")
	var l1 := tr.chunk_arrays(1, 2, 1)
	if l1.size() == Mesh.ARRAY_MAX:
		var v1: PackedVector3Array = l1[Mesh.ARRAY_VERTEX]
		var i1: PackedInt32Array = l1[Mesh.ARRAY_INDEX]
		t.check(v1.size() == 33 * 33 + 129, "LOD1: 33 x 33 vertices + the skirt ring (%d)" % v1.size())
		t.check(i1.size() == 32 * 32 * 6 + 128 * 12, "LOD1: its triangles + both faces of the skirt (%d)" % i1.size())
		var low := 0
		for p in v1:
			if is_equal_approx(p.y, 2.0 - LevelTerrain.LOD_SKIRT):
				low += 1
		t.check(low == 129, "LOD1: the skirt hangs 1.5 m down (%d)" % low)
	else:
		t.fail("LOD1: arrays")
	t.check(tr.chunk_arrays(4, 0).is_empty() and tr.chunk_arrays(-1, 0).is_empty(), "chunk_arrays: [] outside the grid")
	var md := tr.tile_data(1, 0)
	t.check(md.size() == 129 * 129, "tile_data: 129 x 129 (square)")
	t.check(is_equal_approx(md[0], 2.0 / 2.0), "tile_data: heights / cell")
	var e := tr.edge_skirt_arrays()
	t.check(e.size() == Mesh.ARRAY_MAX and (e[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 4 * 4 * 256, "edge skirt: a quad per border cell")
	var mi := tr.chunk_node(0, 0, 1)
	t.check(mi != null and mi.name == "terrain_lod_0_0" and mi.get_meta("no_collision", false) and mi.get_meta("no_shadow", false), "chunk_node: LOD1 named, no_collision, no_shadow")
	if mi:
		t.check(is_equal_approx(mi.visibility_range_begin, 3.0 * 128.0), "chunk_node: LOD1 begins at 3 chunks")
		mi.free()
	var m0 := tr.chunk_node(0, 0, 0)
	t.check(m0 != null and m0.name == "terrain_0_0" and m0.get_meta("no_collision", false) and not m0.get_meta("no_shadow", false), "chunk_node: LOD0 named, no_collision, casts shadows")
	if m0:
		t.check(is_equal_approx(m0.visibility_range_end, 3.0 * 128.0 + 32.0), "chunk_node: LOD0 ends at 3 chunks + 32")
		m0.free()
	var es := tr.edge_skirt_node()
	t.check(es != null and es.name == "deco_world_edge" and es.get_meta("no_shadow", false), "edge_skirt_node: deco_world_edge, no_shadow")
	if es:
		es.free()


func _holes_and_winding(t: Node) -> void:
	var tr := LevelTerrain.flat_world(512.0, 257, 1.0)
	tr.heights[10 * tr.res + 10] = NAN
	var a := tr.chunk_arrays(0, 0, 0)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	t.check(idx.size() == 64 * 64 * 6 - 6 * 3, "holes: the 6 triangles round one hole sample are left out (%d)" % idx.size())
	var finite := true
	for p in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if is_nan(p.y):
			finite = false
	t.check(finite, "holes: no NAN vertex (the AABB stays finite)")
	t.check(is_nan(tr.height_at(-256.0 + 20.0, -256.0 + 20.0)) and is_nan(tr.height_at(-256.0 + 20.5, -256.0 + 19.0)), "holes: height_at NAN beside a hole")
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var down := 0
	for k in range(0, idx.size(), 3):
		var n := (verts[idx[k + 1]] - verts[idx[k]]).cross(verts[idx[k + 2]] - verts[idx[k]])
		if n.y < 0.0:
			down += 1
	t.check(down == idx.size() / 3, "winding: every ground triangle is clockwise seen from above (Godot's front)")
	# all holes: no triangles at all
	var empty := LevelTerrain.flat_world(512.0, 257, 0.0)
	empty.heights.fill(NAN)
	t.check(empty.chunk_arrays(0, 0).is_empty(), "holes: an all-hole chunk has no arrays")
	var e := tr.edge_skirt_arrays()
	var ev: PackedVector3Array = e[Mesh.ARRAY_VERTEX]
	var en: PackedVector3Array = e[Mesh.ARRAY_NORMAL]
	var ei: PackedInt32Array = e[Mesh.ARRAY_INDEX]
	var outward := 0
	for k in range(0, ei.size(), 3):
		var n := (ev[ei[k + 1]] - ev[ei[k]]).cross(ev[ei[k + 2]] - ev[ei[k]])
		if n.dot(en[ei[k]]) < 0.0 and absf(en[ei[k]].y) < 1e-4:
			outward += 1
	t.check(outward == ei.size() / 3, "edge skirt: faces out with horizontal normals")


func _raycast(t: Node) -> void:
	var tr := _world(func(x: float, z: float) -> float: return 0.05 * x + 2.0 * sin(z * 0.05))
	var hit := tr.raycast(Vector3(10.0, 200.0, 30.0), Vector3.DOWN)
	t.check(not is_nan(hit.x), "raycast: hits straight down")
	t.near(hit.y, tr.height_at(10.0, 30.0), 0.02, "raycast: at the ground's height")
	var o := Vector3(-200.0, 80.0, -50.0)
	var dir := Vector3(1.0, -0.3, 0.2).normalized()
	var h2 := tr.raycast(o, dir)
	t.check(not is_nan(h2.x) and absf(h2.y - tr.height_at(h2.x, h2.z)) < 0.05 and absf((h2 - o).normalized().dot(dir) - 1.0) < 1e-3, "raycast: an oblique ray lands on the ground along the ray")
	t.check(is_nan(tr.raycast(Vector3(0, 50, 0), Vector3.UP).x), "raycast: up misses")
	var from_out := tr.raycast(Vector3(-400.0, 40.0, 0.0), Vector3(1.0, -0.1, 0.0))
	t.check(not is_nan(from_out.x) and from_out.x > -256.0, "raycast: from outside the world box")
	t.check(is_nan(tr.raycast(Vector3(0, 50, 0), Vector3.DOWN, 10.0).x), "raycast: max_d")
	var holed := LevelTerrain.flat_world(512.0, 257, 0.0)
	var c := holed.cell_of(0.0, 0.0)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			holed.heights[(c.y + dz) * holed.res + c.x + dx] = NAN
	t.check(is_nan(holed.raycast(Vector3(0, 30, 0), Vector3.DOWN).x), "raycast: falls through a hole")
	t.check(not is_nan(holed.raycast(Vector3(20, 30, 0), Vector3.DOWN).x), "raycast: hits beside it")
	holed.heights[3] = 77.0
	t.check(holed.top() == 77.0, "top: the highest non-hole height (%s)" % holed.top())
	t.check(holed.bottom() == 0.0, "bottom: the lowest non-hole height")
	t.check(holed.cell_of(0.0, 0.0) == Vector2i(128, 128), "cell_of: the nearest sample")
	var rc := holed.rect_of(Vector2(0, 0), 10.0)
	t.check(rc == Rect2i(123, 123, 11, 11), "rect_of: the circle's box (%s)" % rc)
	t.check(holed.rect_of(Vector2(-250, -250), 20.0).position == Vector2i(0, 0), "rect_of: clamped to the grid")


func _hashes(t: Node) -> void:
	var tr := LevelTerrain.flat_world(512.0, 257, 0.0)
	var cc := tr.chunk_count()
	var tc := tr.tile_count()
	var ch := {}
	var th := {}
	for cz in cc:
		for cx in cc:
			ch[Vector2i(cx, cz)] = tr.chunk_hash(cx, cz)
	for tz in tc:
		for tx in tc:
			th[Vector2i(tx, tz)] = tr.tile_hash(tx, tz)
	for sample in [Vector2i(100, 100), Vector2i(64, 64), Vector2i(128, 30), Vector2i(0, 256)]:
		var s: Vector2i = sample
		tr.heights[s.y * tr.res + s.x] += 1.0
		var rect := Rect2i(s, Vector2i.ONE)
		var want := tr.chunks_in(rect)
		var changed: Array[Vector2i] = []
		for k in ch:
			var hv := tr.chunk_hash(k.x, k.y)
			if hv != ch[k]:
				changed.append(k)
				ch[k] = hv
		want.sort()
		changed.sort()
		t.check(changed == want and not want.is_empty(), "chunk_hash: a change at %s changes exactly chunks_in (%s vs %s)" % [s, changed, want])
		var twant := tr.tiles_in(rect)
		var tchanged: Array[Vector2i] = []
		for k in th:
			var hv := tr.tile_hash(k.x, k.y)
			if hv != th[k]:
				tchanged.append(k)
				th[k] = hv
		twant.sort()
		tchanged.sort()
		t.check(tchanged == twant and not twant.is_empty(), "tile_hash: a change at %s changes exactly tiles_in (%s vs %s)" % [s, tchanged, twant])
	# a splat change touches only its chunk
	tr.splat[(200 * tr.res + 200) * 4] = 255
	var n_changed := 0
	for k in ch:
		if tr.chunk_hash(k.x, k.y) != ch[k]:
			n_changed += 1
	t.check(n_changed == 1, "chunk_hash: a splat change at (200, 200) changes one chunk (%d)" % n_changed)
	# a local re-carve changes only the chunks of its rect
	var w := _world(func(_x: float, _z: float) -> float: return 0.0)
	var r := road(-200.0, 200.0, 5.0, [OPEN])
	w.carve([r], FLAT, BLEND)
	var wh := {}
	for cz in w.chunk_count():
		for cx in w.chunk_count():
			wh[Vector2i(cx, cz)] = w.chunk_hash(cx, cz)
	var r2 := road(-200.0, 200.0, func(x: float) -> float: return 7.0 if x >= -40.0 and x <= -22.0 else 5.0, [OPEN])
	var rect2 := w.influence_rect(r2, 79, 90, FLAT, BLEND)
	w.carve([r2], FLAT, BLEND, rect2)
	var allowed := w.chunks_in(rect2)
	var stray := 0
	var moved := 0
	for k in wh:
		if w.chunk_hash(k.x, k.y) != wh[k]:
			moved += 1
			if not k in allowed:
				stray += 1
	t.check(moved > 0 and stray == 0, "chunk_hash: a local re-carve changes only chunks_in(rect) (%d changed, %d outside)" % [moved, stray])


func _physics(t: Node) -> void:
	var tr := _world(func(x: float, z: float) -> float: return 5.0 + 0.02 * x - 0.01 * z)
	var c := tr.cell_of(-150.0, -150.0)
	tr.heights[c.y * tr.res + c.x] = NAN
	var holder := Node3D.new()
	t.add_child(holder)
	var bodies := 0
	for tz in tr.tile_count():
		for tx in tr.tile_count():
			var b := tr.tile_body(tx, tz)
			if b:
				holder.add_child(b)
				bodies += 1
	t.check(bodies == 4, "tile_body: 2 x 2 tiles on 257")
	var b0 := holder.get_child(0) as StaticBody3D
	t.check(b0.name == "col_terrain_0_0" and b0.collision_layer == 1 and b0.collision_mask == 0 and b0.get_meta("surface", "") == "offroad", "tile_body: name, layer, mask, surface")
	var shape := (b0.get_child(0) as CollisionShape3D).shape as HeightMapShape3D
	t.check(shape.map_width == 129 and shape.map_depth == 129, "tile_body: a square 129 x 129 HeightMapShape3D")
	await t.frames(3)
	var space := holder.get_world_3d().direct_space_state
	for p in [Vector2(10.0, 20.0), Vector2(-100.0, 77.0), Vector2(200.0, -180.0)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 100.0, p.y), Vector3(p.x, -100.0, p.y))
		var r := space.intersect_ray(q)
		t.check(not r.is_empty() and absf(float(r["position"].y) - tr.height_at(p.x, p.y)) < 0.05, "tile_body: a physics ray hits the ground at %s (%s vs %s)" % [p, r.get("position", "none"), tr.height_at(p.x, p.y)])
	var qh := PhysicsRayQueryParameters3D.create(Vector3(-150.0, 100.0, -150.0), Vector3(-150.0, -100.0, -150.0))
	var rh := space.intersect_ray(qh)
	t.log("physics ray over a NAN sample: %s" % ("falls through" if rh.is_empty() else "hits at %s" % rh["position"]))
	holder.free()


## Track.dress on terrain chunks and a road bucket: one shared terrain material, no body for
## no_collision meshes, no shadow for no_shadow ones, a body for the road, the edge skirt seen only.
func _dress(t: Node) -> void:
	var tr := LevelTerrain.flat_world(512.0, 257, 1.0)
	var root := Node3D.new()
	for n in [tr.chunk_node(0, 0, 0), tr.chunk_node(1, 0, 0), tr.chunk_node(0, 0, 1), tr.edge_skirt_node()]:
		root.add_child(n)
	var road := MeshInstance3D.new()
	road.name = "road_m_g1_0"
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 4)])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var pm := StandardMaterial3D.new()
	pm.resource_name = "concrete/concretefloor037b"
	am.surface_set_material(0, pm)
	road.mesh = am
	root.add_child(road)
	Track.dress(root, {"terrain_layers": {"base": "materials/nature/grassfloor002a.png"}})
	var m0 := (root.get_node("terrain_0_0") as MeshInstance3D).get_surface_override_material(0)
	var m1 := (root.get_node("terrain_1_0") as MeshInstance3D).get_surface_override_material(0)
	var ml := (root.get_node("terrain_lod_0_0") as MeshInstance3D).get_surface_override_material(0)
	t.check(m0 is ShaderMaterial and m0 == m1 and m0 == ml, "dress: one terrain ShaderMaterial shared by every terrain mesh")
	t.check((m0 as ShaderMaterial).shader == Track.TERRAIN_SHADER, "dress: the terrain shader")
	var bodies := root.find_children("*", "StaticBody3D", true, false)
	t.check(bodies.size() == 1 and bodies[0].get_parent() == road and bodies[0].get_meta("surface", "") == "road", "dress: no body for no_collision meshes, one for the road (%d)" % bodies.size())
	t.check((root.get_node("terrain_lod_0_0") as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "dress: no_shadow casts no shadow")
	t.check((root.get_node("terrain_0_0") as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "dress: LOD0 terrain casts shadows")
	var es := root.get_node("deco_world_edge") as MeshInstance3D
	t.check(es.get_surface_override_material(0) != null and es.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "dress: the edge skirt gets its world material and no shadow")
	root.free()


func _cost(t: Node) -> void:
	# a 3 km loop (radius 477 m) on MEDIUM terrain (1024 m, 513 samples)
	var tr := LevelTerrain.flat_world(1024.0, 513)
	var r := LevelRoad.new()
	var rad := 477.0
	var n := int(round(TAU * rad / 2.0))
	r.n = n
	r.step = TAU * rad / n
	r.closed = true
	var st: Array[Dictionary] = [OPEN]
	r.styles = st
	for i in n:
		var a := TAU * i / n
		var p := Vector3(cos(a) * rad, 4.0 + 3.0 * sin(a * 3.0), sin(a) * rad)
		var f := Vector3(-sin(a), 0, cos(a))
		r.pos.append(p)
		r.fwd.append(f)
		r.flat_right.append(Vector3(-f.z, 0, f.x))
		r.right.append(Vector3(-f.z, 0, f.x))
		r.width.append(12.0)
		r.style.append(0)
		r.seg.append(i / 10)
	# the best of three runs (other work on this PC skews single timings)
	var ms := INF
	for k in 3:
		ms = minf(ms, t.ms(func() -> void: tr.carve([r], FLAT, BLEND)))
	t.log("carve of a 3 km loop on 513 x 513: %.0f ms (budget 400 ms)" % ms)
	t.check(ms < 2000.0, "carve cost: a 3 km loop under 2 s here (%.0f ms)" % ms)
	var per := INF
	var per1 := INF
	for k in 3:
		var c0 := Time.get_ticks_usec()
		for c in 8:
			tr.chunk_arrays(c, 3, 0)
		per = minf(per, (Time.get_ticks_usec() - c0) / 8000.0)
		c0 = Time.get_ticks_usec()
		for c in 8:
			tr.chunk_arrays(c, 3, 1)
		per1 = minf(per1, (Time.get_ticks_usec() - c0) / 8000.0)
	t.log("chunk_arrays: LOD0 %.2f ms, LOD1 %.2f ms per chunk (budget 1.4 ms per chunk rebuild)" % [per, per1])
	t.near(tr.height_at(rad, 0.0), 4.0 - 0.35, 0.1, "carve cost case: the bed under the loop")
