extends RefCounted
## level/case_brush (P16, CI): LevelBrush's numbers on a 257 grid (512 m, 2 m cells): RAISE / LOWER
## at the centre and by falloff, FLATTEN, SMOOTH, seeded NOISE, the -500..1500 clamp, holes kept;
## a stroke (dabs written live, then push_applied with its region copies and the ROADS FOLLOW THE
## GROUND point sets) is one undo step that restores the heights and the points exactly; paint
## dabs and the eyedropper, AUTO PAINT, the antlion's sand band, RESIZE WORLD and NO TERRAIN ops.

const NEEDS_CONTENT := false

var t: Node


func run(t_: Node) -> void:
	t = t_
	_dabs()
	_clamp_holes()
	_stroke_undo()
	_paint()
	_auto_paint()
	_band()
	_resample()


func _flat(y := 0.0) -> LevelTerrain:
	return LevelTerrain.flat_world(512.0, 257, y)


func _at(tr: LevelTerrain, h: PackedFloat32Array, x: float, z: float) -> float:
	var c := tr.cell_of(x, z)
	return h[c.y * tr.res + c.x]


func _dabs() -> void:
	var tr := _flat()
	t.check(tr.res == 257 and is_equal_approx(tr.cell, 2.0), "a 257 grid over 512 m (2 m cells)")
	var h := tr.natural.duplicate()
	var rect := LevelBrush.dab_height(tr, h, Vector2.ZERO, 20.0, 0.5, "raise", "smooth")
	var amount := 0.5 * (LevelBrush.RATE * 20.0 + LevelBrush.RATE_MIN)
	t.near(_at(tr, h, 0, 0), amount, 1e-5, "RAISE: the centre goes up strength x (0.08 x radius + 0.25) = %.3f m" % amount)
	t.check(rect == tr.rect_of(Vector2.ZERO, 20.0) and rect.size == Vector2i(21, 21), "the dab's rect is the circle's box (%s)" % str(rect))
	t.near(_at(tr, h, 10, 0), amount * LevelBrush.weight(0.5, "smooth"), 1e-5, "SMOOTH falloff at half the radius (%.3f)" % LevelBrush.weight(0.5, "smooth"))
	t.near(_at(tr, h, 6, 0), amount, 1e-5, "SMOOTH: full strength inside 0.35 of the radius")
	t.check(_at(tr, h, 20, 0) == 0.0 and _at(tr, h, 22, 0) == 0.0 and _at(tr, h, 16, 16) == 0.0, "nothing moves at or past the radius")
	var changed := 0
	for v in h:
		if v != 0.0:
			changed += 1
	t.check(changed > 250 and changed < 21 * 21, "only the circle's samples moved (%d)" % changed)
	var hl := tr.natural.duplicate()
	LevelBrush.dab_height(tr, hl, Vector2.ZERO, 20.0, 0.5, "lower", "linear")
	t.near(_at(tr, hl, 0, 0), -amount, 1e-5, "LOWER is RAISE downwards")
	t.near(_at(tr, hl, 10, 0), -amount * 0.5, 1e-5, "LINEAR falloff: half at half the radius")
	var hf := tr.natural.duplicate()
	LevelBrush.dab_height(tr, hf, Vector2.ZERO, 20.0, 0.5, "raise", "flat")
	t.near(_at(tr, hf, 16, 0), amount, 1e-5, "FLAT falloff: full strength out to 0.9 of the radius")
	t.check(is_equal_approx(LevelBrush.ring("linear"), 0.5) and LevelBrush.ring("flat") > LevelBrush.ring("smooth"), "the inner ring sits where the weight is one half")
	# FLATTEN towards a target
	var h2 := tr.natural.duplicate()
	LevelBrush.dab_height(tr, h2, Vector2(40, 40), 12.0, 1.0, "flatten", "smooth", 5.0)
	t.near(_at(tr, h2, 40, 40), 5.0, 1e-5, "FLATTEN at strength 1: the target height at the centre")
	var h3 := tr.natural.duplicate()
	LevelBrush.dab_height(tr, h3, Vector2(40, 40), 12.0, 0.5, "flatten", "smooth", 5.0)
	t.near(_at(tr, h3, 40, 40), 2.5, 1e-5, "FLATTEN at strength 0.5: half way")
	# SMOOTH: a spike spreads, a flat field stays flat
	var h4 := tr.natural.duplicate()
	var ci := tr.cell_of(0, 0)
	h4[ci.y * tr.res + ci.x] = 10.0
	LevelBrush.dab_height(tr, h4, Vector2.ZERO, 10.0, 1.0, "smooth", "flat")
	var mid := h4[ci.y * tr.res + ci.x]
	var side := h4[ci.y * tr.res + ci.x + 1]
	t.check(mid < 2.0 and side > 0.0, "SMOOTH flattens a 10 m spike (centre %.2f, beside it %.2f)" % [mid, side])
	var sum := 0.0
	for v in h4:
		sum += v
	t.near(sum, 10.0, 0.5, "SMOOTH keeps the ground's volume (%.2f)" % sum)
	var h5 := tr.natural.duplicate()
	LevelBrush.dab_height(tr, h5, Vector2.ZERO, 30.0, 1.0, "smooth", "smooth")
	t.check(h5 == tr.natural, "SMOOTH leaves flat ground flat")
	# NOISE: seeded, bounded
	var n1 := tr.natural.duplicate()
	var n2 := tr.natural.duplicate()
	var n3 := tr.natural.duplicate()
	LevelBrush.dab_height(tr, n1, Vector2.ZERO, 40.0, 1.0, "noise", "smooth", 0.0, 7)
	LevelBrush.dab_height(tr, n2, Vector2.ZERO, 40.0, 1.0, "noise", "smooth", 0.0, 7)
	LevelBrush.dab_height(tr, n3, Vector2.ZERO, 40.0, 1.0, "noise", "smooth", 0.0, 8)
	var top := 0.0
	var moved := 0
	for v in n1:
		top = maxf(top, absf(v))
		if v != 0.0:
			moved += 1
	var a40 := LevelBrush.RATE * 40.0 + LevelBrush.RATE_MIN
	t.check(n1 == n2 and n1 != n3, "NOISE: the same seed gives the same ground, another seed another")
	t.check(moved > 100 and top > 0.1 and top <= a40 * 1.01, "NOISE moves the ground by at most its amount (%.2f of %.2f m)" % [top, a40])
	var n4 := tr.natural.duplicate()
	LevelBrush.dab_noise(tr, n4, Vector2.ZERO, 40.0, 1.0, "smooth", 128.0, 7)
	t.check(n4 != n1, "NOISE SCALE changes the pattern")
	t.check(LevelBrush.dab_height(tr, h, Vector2(5000, 0), 20.0, 1.0, "raise", "smooth") == Rect2i(), "a dab off the world touches nothing")


func _clamp_holes() -> void:
	var tr := _flat(1499.0)
	var h := tr.natural.duplicate()
	for k in 20:
		LevelBrush.dab_height(tr, h, Vector2.ZERO, 50.0, 1.0, "raise", "flat")
	var top := -INF
	for v in h:
		top = maxf(top, v)
	t.check(top == 1500.0, "heights stop at 1500 m (%.2f)" % top)
	var tl := _flat(-499.0)
	var hl := tl.natural.duplicate()
	for k in 20:
		LevelBrush.dab_height(tl, hl, Vector2.ZERO, 50.0, 1.0, "lower", "flat")
		LevelBrush.dab_noise(tl, hl, Vector2.ZERO, 50.0, 1.0, "flat", 16.0, k)
	var low := INF
	for v in hl:
		low = minf(low, v)
	t.check(low >= -500.0 and low == -500.0, "heights stop at -500 m (%.2f)" % low)
	var hh := _flat().natural.duplicate()
	var c := tr.cell_of(0, 0)
	hh[c.y * tr.res + c.x] = NAN
	LevelBrush.dab_height(tr, hh, Vector2.ZERO, 20.0, 1.0, "raise", "smooth")
	LevelBrush.dab_height(tr, hh, Vector2.ZERO, 20.0, 1.0, "smooth", "smooth")
	t.check(is_nan(hh[c.y * tr.res + c.x]) and not is_nan(hh[c.y * tr.res + c.x + 1]), "a hole stays a hole under every brush")


## A stroke written live, then one push_applied step: undo gives back the heights and the
## followed point exactly, redo the stroke.
func _stroke_undo() -> void:
	var doc := LevelDoc.blank("Brush", 512.0, 257)
	var p1 := doc.new_uid()
	var p2 := doc.new_uid()
	var p3 := doc.new_uid()
	doc.data["road"] = {"closed": false, "start": {"p": p1, "t": 0.0}, "points": [
		{"uid": p1, "pos": [0.0, 0.3, 0.0], "width": 14.0, "style": "asphalt", "follow": true},
		{"uid": p2, "pos": [10.0, 4.0, 0.0], "width": 14.0, "style": "asphalt"},
		{"uid": p3, "pos": [200.0, 0.3, 0.0], "width": 14.0, "style": "asphalt", "follow": true}]}
	var hist := EditHistory.new(doc)
	var tr := LevelTerrain.from_doc(doc)
	var before := doc.heights.duplicate()
	var rect := Rect2i()
	for k in 6:
		var r := LevelBrush.dab_height(tr, doc.heights, Vector2(-10.0 + k * 5.0, 0.0), 24.0, 0.6, "raise", "smooth")
		rect = r if not rect.has_area() else rect.merge(r)
	var after := doc.heights.duplicate()
	var rise := LevelBrush.sample(after, 257, doc.origin(), doc.cell(), 0.0, 0.0)
	var pts := LevelBrush.follow_ops(doc, before, rect)
	t.check(pts.size() == 1 and str(pts[0][1]) == str(["road", "points", "#%d" % p1, "pos"]), "ROADS FOLLOW THE GROUND: only the followed point in the stroke moves (%d)" % pts.size())
	t.near(float(pts[0][2][1]), 0.3 + rise, 1e-3, "it keeps its 0.3 m over the new ground (%.3f)" % float(pts[0][2][1]))
	var inv := doc.apply(pts)
	var do_ops := [LevelDoc.op_heights(rect, LevelBrush.region(after, 257, rect))] + pts
	var undo_ops := [LevelDoc.op_heights(rect, LevelBrush.region(before, 257, rect))] + inv
	hist.push_applied("TERRAIN: RAISE", do_ops, undo_ops)
	t.check(hist.count() == 1 and hist.undo_name() == "TERRAIN: RAISE", "a stroke is one undo step")
	hist.undo()
	t.check(doc.heights == before, "undo restores the stroke's region exactly")
	t.check(str(doc.find(p1).item.pos) == str([0.0, 0.3, 0.0]), "and the followed point (%s)" % str(doc.find(p1).item.pos))
	hist.redo()
	t.check(doc.heights == after and absf(float(doc.find(p1).item.pos[1]) - (0.3 + rise)) < 1e-3, "redo puts the stroke and the point back")
	t.check(LevelBrush.region(after, 257, rect).size() == rect.size.x * rect.size.y, "region copies the rect row by row")
	var edge := LevelBrush.region(after, 257, Rect2i(-1, -1, 2, 2))
	t.check(is_nan(edge[0]) and edge[3] == after[0], "region reads NAN outside the grid")


func _paint() -> void:
	var tr := _flat()
	var s := tr.splat.duplicate()
	var c := tr.cell_of(0, 0)
	var g := (c.y * tr.res + c.x) * 4
	LevelBrush.dab_splat(tr, s, Vector2.ZERO, 10.0, 1.0, 1, "smooth")
	t.check(s[g] == 255 and s[g + 1] == 0 and s[g + 3] == 0, "DIRT at strength 1: R full at the centre")
	LevelBrush.dab_splat(tr, s, Vector2.ZERO, 10.0, 1.0, 4, "smooth")
	t.check(s[g + 3] == 255 and s[g] == 0, "SAND over it takes the dirt's place (A full, R 0)")
	t.check(LevelBrush.strongest(s, g / 4) == 4, "the eyedropper picks SAND")
	LevelBrush.dab_splat(tr, s, Vector2.ZERO, 10.0, 0.5, 2, "flat")
	t.check(s[g + 1] >= 127 and s[g + 1] <= 128 and s[g + 3] >= 127 and s[g + 3] <= 128, "ROCK at 0.5: half rock, half the sand left (%d, %d)" % [s[g + 1], s[g + 3]])
	LevelBrush.dab_splat(tr, s, Vector2.ZERO, 10.0, 1.0, 0, "flat")
	t.check(s[g] == 0 and s[g + 1] == 0 and s[g + 2] == 0 and s[g + 3] == 0, "BASE erases the four")
	t.check(LevelBrush.strongest(s, g / 4) == 0, "the eyedropper over bare ground: BASE")
	var low := tr.splat.duplicate()
	for k in 400:
		LevelBrush.dab_splat(tr, low, Vector2.ZERO, 10.0, 0.01, 3, "flat")
	t.check(low[g + 2] == 255, "a weak brush still gets to full (%d)" % low[g + 2])
	var far := (c.y * tr.res + c.x + 8) * 4
	t.check(s[far] == 0 and s[far + 3] == 0, "nothing past the radius")


func _auto_paint() -> void:
	var tr := _flat()
	# a 45 deg ramp along +x between x 100 and 140 m, a hollow at -6 m round (-100, -100)
	for z in tr.res:
		for x in tr.res:
			var wx := tr.origin.x + x * tr.cell
			var wz := tr.origin.y + z * tr.cell
			var h := clampf(wx - 100.0, 0.0, 40.0)
			if Vector2(wx, wz).distance_to(Vector2(-100, -100)) < 20.0:
				h = -6.0
			tr.natural[z * tr.res + x] = h
	tr.heights = tr.natural.duplicate()
	var s := tr.splat.duplicate()
	var r := LevelRoad.build([{"uid": 1, "pos": [0.0, 0.0, -200.0], "width": 14.0, "style": "asphalt"},
		{"uid": 2, "pos": [0.0, 0.0, 200.0], "width": 14.0, "style": "asphalt"}], {}, false, {})
	var rect := LevelBrush.auto_paint(tr, s, {"rock": true, "sand": true, "sand_below": -3.0, "dirt": 6.0, "roads": [r]})
	t.check(rect == Rect2i(0, 0, 257, 257), "AUTO PAINT covers the grid")
	var slope := (tr.cell_of(120, 0).y * tr.res + tr.cell_of(120, 0).x) * 4
	var flat := (tr.cell_of(60, 50).y * tr.res + tr.cell_of(60, 50).x) * 4
	t.check(s[slope + 1] == 255 and s[flat + 1] == 0, "ROCK on the 45 deg slope (%d), none on the flat (%d)" % [s[slope + 1], s[flat + 1]])
	var hollow := (tr.cell_of(-100, -100).y * tr.res + tr.cell_of(-100, -100).x) * 4
	t.check(s[hollow + 3] == 255 and s[flat + 3] == 0, "SAND below -3 m (%d), none above (%d)" % [s[hollow + 3], s[flat + 3]])
	var edge := r.width[0] * 0.5 + r.treatment(r.n / 2, 1)
	var near := tr.cell_of(edge + 2.0, 0)
	var away := tr.cell_of(edge + 20.0, 0)
	t.check(s[(near.y * tr.res + near.x) * 4] == 255 and s[(away.y * tr.res + away.x) * 4] == 0, "DIRT within 6 m of the road's edge, none 20 m out")
	t.check(s[slope + 2] == 0, "PAVE is left as painted")
	var s2 := tr.splat.duplicate()
	LevelBrush.auto_paint(tr, s2, {"rock": false, "sand": false})
	t.check(s2 == tr.splat, "with every rule off nothing changes")


func _band() -> void:
	var tr := _flat()
	var s := tr.splat.duplicate()
	var r := LevelRoad.build([{"uid": 1, "pos": [0.0, 0.0, -200.0], "width": 14.0, "style": "asphalt"},
		{"uid": 2, "pos": [0.0, 0.0, 200.0], "width": 14.0, "style": "asphalt"}], {}, false, {})
	var i0 := r.closest(Vector3(0, 0, -50))
	var i1 := r.closest(Vector3(0, 0, 50))
	var rect := LevelBrush.band_splat(tr, s, r, i0, i1, 1, 16.0, 4)
	t.check(rect.has_area(), "band_splat paints (%s)" % str(rect))
	var edge := r.width[i0] * 0.5 + r.treatment(i0, 1)
	var right := r.flat_right[(i0 + i1) / 2]
	var inside := Vector3(0, 0, 0) + right * (edge + 8.0)
	var outside := Vector3(0, 0, 0) + right * (edge + 16.0 + BAND_OUT)
	var other := Vector3(0, 0, 0) - right * (edge + 8.0)
	var past := Vector3(0, 0, 90) + right * (edge + 8.0)
	t.check(_ch(tr, s, inside, 3) == 255, "the band is full sand 8 m out on its side")
	t.check(_ch(tr, s, outside, 3) == 0, "nothing past the band and its rim")
	t.check(_ch(tr, s, other, 3) == 0, "nothing on the other side")
	t.check(_ch(tr, s, past, 3) == 0, "nothing past i1 along the road")
	var both := tr.splat.duplicate()
	LevelBrush.band_splat(tr, both, r, i0, i1, 0, 16.0, 4)
	t.check(_ch(tr, both, other, 3) == 255 and _ch(tr, both, inside, 3) == 255, "side 0 paints both sides")
	t.check(LevelBrush.band_splat(tr, s, null, 0, 1, 1, 16.0, 4) == Rect2i(), "no road, no band")


const BAND_OUT := 4.0


func _ch(tr: LevelTerrain, s: PackedByteArray, p: Vector3, ch: int) -> int:
	var c := tr.cell_of(p.x, p.z)
	return s[(c.y * tr.res + c.x) * 4 + ch]


func _resample() -> void:
	var doc := LevelDoc.blank("Resize", 512.0, 257)
	for z in 257:
		for x in 257:
			doc.heights[z * 257 + x] = 0.5 * x - 0.25 * z
			doc.splat[(z * 257 + x) * 4 + 3] = 200 if x < 128 else 0
	var before := doc.heights.duplicate()
	var bsp := doc.splat.duplicate()
	t.check(LevelBrush.resample(doc, 1000.0, 513).is_empty() and LevelBrush.resample(doc, 1024.0, 257).is_empty(), "RESIZE WORLD refuses a (size, res) pair the format does not allow")
	var hist := EditHistory.new(doc)
	var ops := LevelBrush.resample(doc, 1024.0, 513)
	t.check(ops.size() == 3, "RESIZE WORLD: world, heights, splat ops")
	hist.commit("RESIZE WORLD", ops)
	t.check(doc.res() == 513 and is_equal_approx(doc.world_size(), 1024.0) and doc.heights.size() == 513 * 513 and doc.splat.size() == 513 * 513 * 4, "the world is 1024 m / 513 after it")
	var org := doc.origin()
	var ok := true
	for q in [Vector2(0, 0), Vector2(-100, 37), Vector2(200, -150), Vector2(255, 255)]:
		var a := LevelBrush.sample(before, 257, Vector2(-256, -256), 2.0, q.x, q.y)
		var b := LevelBrush.sample(doc.heights, 513, org, doc.cell(), q.x, q.y)
		ok = ok and absf(a - b) < 0.02
	t.check(ok, "the ground stays where it was in world space (bilinear)")
	var out := LevelBrush.sample(doc.heights, 513, org, doc.cell(), 400.0, 0.0)
	var border := LevelBrush.sample(before, 257, Vector2(-256, -256), 2.0, 256.0, 0.0)
	t.near(out, border, 0.02, "outside the old world the border carries on")
	var c := Vector2i(roundi((-200.0 - org.x) / doc.cell()), roundi((0.0 - org.y) / doc.cell()))
	t.check(doc.splat[(c.y * 513 + c.x) * 4 + 3] == 200, "the splat is resampled too")
	hist.undo()
	t.check(doc.res() == 257 and doc.heights == before and doc.splat == bsp, "one undo step gives back the old world exactly")
	var off := LevelBrush.terrain_ops(doc, false)
	hist.commit("NO TERRAIN", off)
	t.check(not doc.has_terrain() and doc.heights.is_empty(), "NO TERRAIN drops the heightmap")
	t.check(LevelBrush.terrain_ops(doc, false).is_empty(), "NO TERRAIN twice is nothing")
	hist.undo()
	t.check(doc.has_terrain() and doc.heights == before, "undo brings the ground back")
