class_name LevelTemplates
## The five templates (1.2), built in code through the editor's own API (data ops on a LevelDoc)
## from a blank 1024 m world (res 513, cell 2 m), each applying its THEME with LevelThemes.ops:
## only material / model / sky keys by name, nothing from Valve files, so they ship in git. The
## result is in LevelDoc.sanitize's canonical form (a save and a load give it back unchanged).

const IDS := ["empty", "oval", "figure8", "hills", "city"]
const TITLES := {"empty": "EMPTY FIELD", "oval": "COMBINE TEST OVAL", "figure8": "CANALS FIGURE EIGHT",
	"hills": "WHITE FOREST HILLS", "city": "CITY 17 BLOCK"}
const THEMES := {"empty": "coast", "oval": "city17", "figure8": "coast", "hills": "whiteforest", "city": "city17"}
const DESCS := {
	"empty": "A flat grass field and no road: draw your own.",
	"oval": "A 1.1 km asphalt oval with two banked bends, crate rows, boost pads and a grandstand at the start.",
	"figure8": "A 1.6 km figure eight: one leg crosses the other on a concrete bridge.",
	"hills": "2.4 km over forest hills at sunset: dirt and asphalt, a jump with a kicker and a logging-trail shortcut.",
	"city": "1.7 km of city streets round a block grid, a tunnel under one block, a turret and a mortar zone.",
}
const WORLD := 1024.0
const RES := 513
## The circle handle factor (a quarter circle of radius r: handles of K * r).
const K := 0.5523
const PINES := ["props_foliage/tree_pine04", "props_foliage/tree_pine05", "props_foliage/tree_pine06",
	"props_foliage/tree_pine_01"]

## What sanitize found in the last make() before the canonical pass (tests: it stays empty).
static var last_report: LevelReport


static func title(id: String) -> String:
	return str(TITLES.get(id, ""))


## One line about the template (EditorHome's TEMPLATES cards).
static func describe(id: String) -> String:
	return str(DESCS.get(id, ""))


static func make(id: String, track_name: String) -> LevelDoc:
	var tid := id if id in IDS else "empty"
	var doc := LevelDoc.blank(track_name, WORLD, RES)
	_theme(doc, str(THEMES[tid]))
	match tid:
		"oval":
			_oval(doc)
		"figure8":
			_figure8(doc)
		"hills":
			_hills(doc)
		"city":
			_city(doc)
	doc.apply([LevelDoc.op_set(["desc"], str(DESCS[tid]))])
	# the canonical form: what every peer gets back from the file
	last_report = LevelReport.new()
	var clean := LevelDoc.sanitize(doc.data, last_report)
	if not last_report.items.is_empty():
		push_warning("LevelTemplates.make(%s): sanitize cleaned %d thing(s)" % [tid, last_report.items.size()])
	doc.data = clean
	doc.notify(PackedStringArray(LevelDoc.SECTIONS))
	return doc


# ---------------------------------------------------------------- helpers

static func _theme(doc: LevelDoc, theme: String) -> void:
	var ops := LevelThemes.ops(doc, theme)
	if not ops.is_empty():
		doc.apply(ops)
	if str(doc.data.get("theme", "")) != theme:
		doc.apply([LevelDoc.op_set(["theme"], theme)])


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


static func _pt(doc: LevelDoc, p: Vector3, style := "asphalt", width := 14.0) -> Dictionary:
	return {"uid": doc.new_uid(), "pos": _v(p), "width": width, "style": style, "seesaw": false, "follow": false}


## A point with aligned handles along dir (in / out lengths in metres).
static func _hpt(doc: LevelDoc, p: Vector3, dir: Vector3, h_in: float, h_out: float, style := "asphalt",
		width := 14.0) -> Dictionary:
	var q := _pt(doc, p, style, width)
	var d := dir.normalized()
	# lengths on a 0.1 m grid: they survive the file's JSON exactly
	q["handle"] = {"dir": [d.x, d.y, d.z], "in": roundf(clampf(h_in, 0.0, 200.0) * 10.0) / 10.0,
		"out": roundf(clampf(h_out, 0.0, 200.0) * 10.0) / 10.0}
	return q


static func _a(p: Dictionary, t: float) -> Dictionary:
	return {"p": int(p.uid), "t": t}


static func _road(doc: LevelDoc, pts: Array, start: Dictionary) -> void:
	doc.apply([LevelDoc.op_set(["road"], {"closed": true, "start": start, "points": pts})])


static func _row(doc: LevelDoc, at: Dictionary, road := -1) -> Dictionary:
	return {"uid": doc.new_uid(), "road": road, "at": at, "count": 0, "inset": 2.5}


static func _pad(doc: LevelDoc, at: Dictionary, road := -1) -> Dictionary:
	return {"uid": doc.new_uid(), "road": road, "at": at, "turn": 0.0}


static func _crowd(doc: LevelDoc, at: Dictionary, side: int) -> Dictionary:
	return {"uid": doc.new_uid(), "road": -1, "at": at, "side": side, "length": 20.0, "rows": 2, "density": 1.0,
		"setback": 2.5, "role": "citizen", "mood": "fan", "sit": 0.0, "tags": ["start"]}


static func _prop(doc: LevelDoc, model: String, p: Vector3, yaw: float, scale := 1.0) -> Dictionary:
	return {"uid": doc.new_uid(), "model": model, "pos": _v(p), "yaw": yaw, "pitch": 0.0, "roll": 0.0,
		"scale": scale, "physics": false, "tag": ""}


static func _heights(doc: LevelDoc, h: PackedFloat32Array) -> void:
	doc.apply([LevelDoc.op_heights_all(h)])


## Distance in plan from q to the segment a-b.
static func _seg_dist(q: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-9 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
	return q.distance_to(a + ab * t)


static func _poly_dist(q: Vector2, poly: PackedVector2Array, closed: bool) -> float:
	var best := INF
	var n := poly.size()
	for i in (n if closed else n - 1):
		best = minf(best, _seg_dist(q, poly[i], poly[(i + 1) % n]))
	return best


# ---------------------------------------------------------------- COMBINE TEST OVAL

## 14 m asphalt oval, about 1.1 km: two 270 m straights, two bends of radius 90 m (AUTO banking
## tilts them), 4 crate rows, 2 boost pads at the bend exits, a grandstand crowd each side of the
## start, the combine gantry.
static func _oval(doc: LevelDoc) -> void:
	var r := 90.0
	var c45 := r * cos(PI / 4.0)
	var spots := [Vector2(-135, 90), Vector2(-45, 90), Vector2(45, 90), Vector2(135, 90),
		Vector2(135 + c45, c45), Vector2(135 + r, 0), Vector2(135 + c45, -c45), Vector2(135, -90),
		Vector2(45, -90), Vector2(-45, -90), Vector2(-135, -90),
		Vector2(-135 - c45, -c45), Vector2(-135 - r, 0), Vector2(-135 - c45, c45)]
	var pts := []
	for s in spots:
		pts.append(_pt(doc, Vector3(s.x, 0.0, s.y)))
	_road(doc, pts, _a(pts[1], 0.5))
	doc.apply([
		LevelDoc.op_set(["items"], [_row(doc, _a(pts[2], 0.5)), _row(doc, _a(pts[5], 0.0)),
			_row(doc, _a(pts[8], 0.5)), _row(doc, _a(pts[12], 0.0))]),
		LevelDoc.op_set(["pads"], [_pad(doc, _a(pts[7], 0.25)), _pad(doc, _a(pts[0], 0.2))]),
		LevelDoc.op_set(["crowds"], [_crowd(doc, _a(pts[1], 0.5), -1), _crowd(doc, _a(pts[1], 0.5), 1)]),
		LevelDoc.op_set(["race", "gantry"], "combine"),
	])


# ---------------------------------------------------------------- CANALS FIGURE EIGHT

## About 1.6 km: two loops of radius 100 m round centres 420 m apart, joined by two straight
## diagonals that cross at the origin; one diagonal crosses the other on a 9 m concrete bridge
## (its own style: pillars every 40 m, so none stands on the road under it), the ground ramps up
## to it.
static func _figure8(doc: LevelDoc) -> void:
	var dd := 210.0
	var rr := 100.0
	var deck := 9.0
	var al := asin(rr / dd)
	var half := dd * cos(al)
	var u1 := Vector2(cos(al), sin(al))     # the flat diagonal, from the left loop to the right one
	var u2 := Vector2(-cos(al), sin(al))    # the bridge diagonal, from the right loop to the left one
	var sweep := PI + 2.0 * al
	var bridge := (LevelStyles.PRESETS.bridge as Dictionary).duplicate(true)
	bridge["name"] = "CANAL BRIDGE"
	bridge["pillar_every"] = 40.0
	doc.apply([LevelDoc.op_set(["styles"], {"canal_bridge": bridge})])
	var pts := []
	for s in [-half, -90.0, 90.0, half]:
		var q: Vector2 = u1 * s
		pts.append(_pt(doc, Vector3(q.x, 0.0, q.y)))
	for k in range(1, 6):
		var ph := (PI / 2.0 + al) - sweep * k / 6.0
		pts.append(_pt(doc, Vector3(dd + rr * cos(ph), 0.0, rr * sin(ph))))
	var lifts := {-half: 0.0, -110.0: 0.0, -40.0: deck, 40.0: deck, 110.0: 0.0, half: 0.0}
	for s in [-half, -110.0, -40.0, 40.0, 110.0, half]:
		var q: Vector2 = u2 * s
		pts.append(_pt(doc, Vector3(q.x, float(lifts[s]), q.y), "canal_bridge" if s == -40.0 else "asphalt"))
	for k in range(1, 6):
		var ph := (PI / 2.0 - al) + sweep * k / 6.0
		pts.append(_pt(doc, Vector3(-dd + rr * cos(ph), 0.0, rr * sin(ph))))
	_road(doc, pts, _a(pts[2], 0.5))
	# the ground ramps up under the bridge's approaches
	var h := doc.heights.duplicate()
	var res := doc.res()
	var cell := doc.cell()
	var org := doc.origin()
	var reach := 130.0
	var lo := (u2 * -reach).min(u2 * reach) - Vector2(45, 45)
	var hi := (u2 * -reach).max(u2 * reach) + Vector2(45, 45)
	var n2 := Vector2(-u2.y, u2.x)
	for iz in range(maxi(0, int((lo.y - org.y) / cell)), mini(res, int((hi.y - org.y) / cell) + 2)):
		for ix in range(maxi(0, int((lo.x - org.x) / cell)), mini(res, int((hi.x - org.x) / cell) + 2)):
			var q := Vector2(org.x + ix * cell, org.y + iz * cell)
			var s := absf(q.dot(u2))
			var d := absf(q.dot(n2))
			var top := 0.0
			if s >= 40.0:
				top = deck * clampf((110.0 - s) / 70.0, 0.0, 1.0)
			else:
				top = deck * smoothstep(25.0, 40.0, s)
			if top <= 0.0:
				continue
			var fall := 1.0 - smoothstep(11.0, 11.0 + 3.0 * top, d)
			var v := snappedf(top * fall, 0.01)
			if v > h[iz * res + ix]:
				h[iz * res + ix] = v
	_heights(doc, h)
	doc.apply([
		LevelDoc.op_set(["items"], [_row(doc, _a(pts[6], 0.0)), _row(doc, _a(pts[17], 0.0)),
			_row(doc, _a(pts[1], 0.2))]),
		LevelDoc.op_set(["pads"], [_pad(doc, _a(pts[9], 0.3)), _pad(doc, _a(pts[0], 0.3))]),
		LevelDoc.op_set(["crowds"], [_crowd(doc, _a(pts[2], 0.5), -1)]),
	])


# ---------------------------------------------------------------- WHITE FOREST HILLS

## The hills' ground: seeded noise hills, rising to mountains at the world's edge.
static func _hill_height(noise: FastNoiseLite, x: float, z: float) -> float:
	var edge := maxf(absf(x), absf(z))
	return 18.0 * noise.get_noise_2d(x, z) + 60.0 * smoothstep(440.0, 512.0, edge)


## About 2.4 km over sculpted hills (noise, seeded), dirt and asphalt stretches, a 14 m jump with
## a kicker, a logging-trail shortcut (kind trail, ai take 0.5), pines scattered, the forest
## background and evening light.
static func _hills(doc: LevelDoc) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1717
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0038
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	var res := doc.res()
	var cell := doc.cell()
	var org := doc.origin()
	var h := PackedFloat32Array()
	h.resize(res * res)
	for iz in res:
		for ix in res:
			h[iz * res + ix] = snappedf(_hill_height(noise, org.x + ix * cell, org.y + iz * cell), 0.01)
	_heights(doc, h)
	var n := 18
	var styles := {}
	for k in n:
		styles[k] = "dirt" if (k >= 6 and k <= 10) or k >= 14 else "asphalt"
	var pts := []
	var plan := PackedVector2Array()
	for k in n:
		var th := TAU * k / n
		var r := 360.0 + 45.0 * sin(2.0 * th + 0.6) + 28.0 * cos(3.0 * th)
		var q := Vector2(r * cos(th), r * sin(th))
		plan.append(q)
		var p := _pt(doc, Vector3(q.x, _hill_height(noise, q.x, q.y), q.y), str(styles[k]))
		p["follow"] = true
		if k == 7:
			p["gap"] = {"len": 14.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
		pts.append(p)
	_road(doc, pts, _a(pts[0], 0.6))
	# the logging trail: leaves segment 12, rejoins segment 15, cutting inside the loop
	var f := (plan[12] + plan[13]) * 0.5
	var m := (plan[15] + plan[16]) * 0.5
	var tf := (plan[13] - plan[12]).normalized()
	var tm := (plan[16] - plan[15]).normalized()
	var bp := PackedVector2Array([f + tf * 40.0 - f.normalized() * 20.0, (f + m) * 0.5 - ((f + m) * 0.5).normalized() * 25.0,
		m - tm * 40.0 - m.normalized() * 20.0])
	var bpts := []
	for q in bp:
		var p := _pt(doc, Vector3(q.x, _hill_height(noise, q.x, q.y), q.y), "dirt", 9.0)
		p["follow"] = true
		bpts.append(p)
	var branch := {"uid": doc.new_uid(), "name": "LOGGING TRAIL", "kind": "trail", "fork": _a(pts[12], 0.5),
		"merge": _a(pts[15], 0.5), "side": 0, "merge_side": 0, "points": bpts,
		"ai": {"take": 0.5, "min_skill": 0.0, "commit": 40.0}, "risk": 0.0, "respawn": "before", "retry_back": 45.0,
		"offtrack": -1.0}
	var trail := PackedVector2Array([f])
	trail.append_array(bp)
	trail.append(m)
	# pines, seeded, clear of both roads
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var props := []
	var tries := 0
	while props.size() < 160 and tries < 4000:
		tries += 1
		var q := Vector2(rng.randf_range(-490.0, 490.0), rng.randf_range(-490.0, 490.0))
		if _poly_dist(q, plan, true) < 28.0 or _poly_dist(q, trail, false) < 22.0:
			continue
		var y := _hill_height(noise, q.x, q.y)
		props.append(_prop(doc, PINES[props.size() % PINES.size()], Vector3(q.x, y, q.y),
			float(rng.randi_range(0, 359)), snappedf(rng.randf_range(0.8, 1.25), 0.05)))
	doc.apply([
		LevelDoc.op_set(["branches"], [branch]),
		LevelDoc.op_set(["props"], props),
		LevelDoc.op_set(["items"], [_row(doc, _a(pts[3], 0.5)), _row(doc, _a(pts[10], 0.5)),
			_row(doc, _a(pts[16], 0.6)), _row(doc, _a(bpts[1], 0.0), int(branch.uid))]),
		LevelDoc.op_set(["pads"], [_pad(doc, _a(pts[5], 0.4))]),
		LevelDoc.op_set(["race", "background"], "forest"),
		LevelDoc.op_set(["env", "sun"], {"az": 250.0, "el": 12.0}),
		LevelDoc.op_set(["env", "sun_color"], [1.0, 0.72, 0.45]),
		LevelDoc.op_set(["env", "exposure"], 1.0),
		LevelDoc.op_set(["env", "fog_color"], [0.9, 0.7, 0.55]),
	])


# ---------------------------------------------------------------- CITY 17 BLOCK

## About 1.7 km of CITY STREET (kerbs, pavements, fences) round a 4 x 3 grid of 100 m blocks with
## a U through its middle, corners of radius 30 m (aligned handles, so the streets stay straight),
## a TUNNEL under the raised east block, row houses and towers as props, a floor turret and a
## mortar strike zone.
static func _city(doc: LevelDoc) -> void:
	var corners := [Vector2(-200, 150), Vector2(200, 150), Vector2(200, -150), Vector2(0, -150), Vector2(0, 50),
		Vector2(-100, 50), Vector2(-100, -150), Vector2(-200, -150)]
	var r := 30.0
	var n := corners.size()
	var pts := []
	var marks := {}   # corner index -> [A point, B point]
	for i in n:
		var c: Vector2 = corners[i]
		var prev: Vector2 = corners[(i + n - 1) % n]
		var nxt: Vector2 = corners[(i + 1) % n]
		var din := (c - prev).normalized()
		var dout := (nxt - c).normalized()
		var len_in := c.distance_to(prev) - 2.0 * r
		var len_out := nxt.distance_to(c) - 2.0 * r
		var a := c - din * r
		var b := c + dout * r
		var pa := _hpt(doc, Vector3(a.x, 0.0, a.y), Vector3(din.x, 0.0, din.y), len_in / 3.0, K * r, "street")
		var pb := _hpt(doc, Vector3(b.x, 0.0, b.y), Vector3(dout.x, 0.0, dout.y), K * r, len_out / 3.0, "street")
		pts.append(pa)
		pts.append(pb)
		marks[i] = [pa, pb]
		if i == 1:
			# the tunnel under the east block: the street x = 200 from z 60 to -60
			pb["handle"]["out"] = 30.0
			var t0 := _hpt(doc, Vector3(200.0, 0.0, 60.0), Vector3(0, 0, -1), 30.0, 40.0, "tunnel")
			var t1 := _hpt(doc, Vector3(200.0, 0.0, -60.0), Vector3(0, 0, -1), 40.0, 20.0, "street")
			pts.append(t0)
			pts.append(t1)
			marks["tunnel"] = [t0, t1]
	# the corner A of corner 2 follows the tunnel's exit point: its in-handle spans 60 m
	(marks[2][0] as Dictionary)["handle"]["in"] = 20.0
	var start_seg: Dictionary = marks[0][1]
	_road(doc, pts, _a(start_seg, 0.5))
	# the raised east block over the tunnel
	var h := doc.heights.duplicate()
	var res := doc.res()
	var cell := doc.cell()
	var org := doc.origin()
	for iz in res:
		var z := org.y + iz * cell
		if absf(z) > 90.0:
			continue
		for ix in res:
			var x := org.x + ix * cell
			if absf(x - 200.0) > 80.0:
				continue
			var dx := maxf(absf(x - 200.0) - 45.0, 0.0)
			var dz := maxf(absf(z) - 55.0, 0.0)
			var v := 10.0 * (1.0 - smoothstep(0.0, 25.0, Vector2(dx, dz).length()))
			h[iz * res + ix] = snappedf(v, 0.01)
	_heights(doc, h)
	# buildings: a row house on the north and south side of every block, towers in a few
	var props := []
	for bx in [-150.0, -50.0, 50.0, 150.0]:
		for bz in [-100.0, 0.0, 100.0]:
			if bx == 150.0 and bz == 0.0:
				continue
			props.append(_prop(doc, "props_buildings/row_res_2_fullscale", Vector3(bx, 0.0, bz - 30.0), 180.0))
			props.append(_prop(doc, "props_buildings/row_res_2_fullscale", Vector3(bx, 0.0, bz + 30.0), 0.0))
			if (bx == -150.0 and bz == -100.0) or (bx == 50.0 and bz == 100.0) or (bx == -50.0 and bz == 0.0):
				props.append(_prop(doc, "props_buildings/project_building01", Vector3(bx, 0.0, bz - 4.0), 90.0))
	var st2: Dictionary = marks[2][1]     # the street z = -150 heading west
	var st7: Dictionary = marks[7][1]     # the street x = -200 heading north
	var turret := {"uid": doc.new_uid(), "type": "turret", "at": _a(st2, 0.5), "side": 1, "zone": null,
		"feel": "normal", "setback": 1.6, "mount": "floor", "pts": [], "p": {}}
	var mortar := {"uid": doc.new_uid(), "type": "strike_zone", "at": null, "side": 0,
		"zone": [_a(st7, 0.3), _a(st7, 0.7)], "feel": "normal", "style": "mortar", "pts": [], "p": {}}
	doc.apply([
		LevelDoc.op_set(["props"], props),
		LevelDoc.op_set(["hazards"], [turret, mortar]),
		LevelDoc.op_set(["items"], [_row(doc, _a(start_seg, 0.8)), _row(doc, _a(st2, 0.8)),
			_row(doc, _a(marks[5][1], 0.5))]),
		LevelDoc.op_set(["pads"], [_pad(doc, _a(marks[3][1], 0.2))]),
		LevelDoc.op_set(["crowds"], [_crowd(doc, _a(start_seg, 0.5), 1)]),
		LevelDoc.op_set(["race", "background"], "city17"),
	])
