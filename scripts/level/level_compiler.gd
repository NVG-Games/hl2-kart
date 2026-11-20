class_name LevelCompiler
## The pipeline (3.1): a document -> the runtime dict Track reads + road / terrain geometry, the
## gameplay data (3.7), flat zones, async compiles from snapshots and preview_segments. P4.
##
## compile() is pure: no nodes, no resources, no Game writes, no unseeded randomness; the content
## registries come in opts.registries (default: registries(), taken on the calling thread), so it
## runs on a WorkerThreadPool thread. Order (one LevelContext, the terrain carved before anything
## reads the ground): styles; the main road with its flat zones (the grid + every branch's shared
## stretches); hazards pre_geometry; branches (early lint, failing ones left out); terrain + carve
## (with ctx.pits); pits + safe_drop; racing lines; geometry (roads, start line, gores, hazard
## setups) and the terrain chunks; gameplay data; branch export; hazards resolve (setup-less ones
## left out); crowds; validation; legal-spot flags (opts.flags); the build. An open main road (or a
## road still being drawn) gets its carve and meshes for the editor and nothing to race on; a road
## over 25 km gets only lap_long (no road, carve or meshes: 6.9's bound on a received track).
##
## opts: id (String), registries (Dictionary), flags (bool), chunks (bool, default true: the
## terrain's render chunks are made here, on the worker), hooks ({branches, hazards, crowds}: the
## compile hooks' classes, tests only; default LevelBranches, LevelHazards, LevelCrowds).

## The start grid's flat zone (C2 M7): AUTO bank 0 from 80 m behind the line to 10 m after it.
const GRID_BEFORE := 80.0
const GRID_AFTER := 10.0
## 3.7 numbers (track_gen.gameplay / item_rows / pad_entry).
const GRID_SLOTS := 8
const BOX_H := 1.2
const BOX_GAP := 2.4
const PAD_UP := 0.06
const PAD_HALF_W := 2.25
const BARREL_MODEL := "props_c17/oildrum001_explosive"
const BARREL_UP := 0.6
## A road whose length (LevelRoad.length_bounds) is over LAP_MAX x this gets no build at all
## (a blocking lap_long, 6.9); a lap up to it is built (and lap_long past LAP_MAX).
const LONG_SLACK := 1.25
## A PHYSICS prop (PropCatalog.PHYS_MASS / PHYS_SIZE): kg at most, the AABB's largest side under.
const PHYS_MASS := 60.0
const PHYS_SIZE := 3.0
const KILL_BELOW := 40.0
const BG_ABOVE := 40.0
const DEFAULT_SKY := "sky_day01_01"
const MAX_LIGHTS := 128
## The env keys copied as they are into data.env (sky and sun are handled apart).
const ENV_KEYS := ["sun_color", "sun_energy", "ambient", "ambient_energy", "fog_color", "fog_begin", "fog_end",
	"fog_sky", "exposure", "glow", "sky_energy", "sdfgi"]


## opts: id (String), registries (Dictionary), flags (bool: legal-spot flags for the editor)
static func compile(doc: LevelDoc, opts := {}) -> LevelBuild:
	var t0 := Time.get_ticks_usec()
	var b := LevelBuild.new()
	b.id = str(opts.get("id", ""))
	b.report = LevelReport.new()
	b.meshes = LevelMeshSet.new()
	if doc == null:
		LevelValidate.issue(b.report, "compile", {"why": "there is no track"})
		return b
	b.revision = doc.revision
	var ctx := LevelContext.new()
	ctx.doc = doc
	ctx.report = b.report
	ctx.registries = opts.registries if opts.get("registries") is Dictionary else registries()
	ctx.flags = bool(opts.get("flags", false))
	ctx.meshes = b.meshes
	ctx.data = {}
	var hooks := _hooks(opts)
	ctx.set_meta("hooks", hooks)
	var times := {}
	var tk := Time.get_ticks_usec()
	# 1 styles
	ctx.styles = LevelStyles.resolve(doc.data, _reg(ctx, "materials"))
	b.styles = ctx.styles
	# 2 the main road, with the grid's and the branches' flat zones
	var road = doc.data.get("road", {})
	if not (road is Dictionary):
		road = {}
	var pts: Array = road.get("points", []) if road.get("points") is Array else []
	var closed := bool(road.get("closed", false)) and pts.size() >= 3
	var drivable := false
	# a road far over the lap cap is refused before it is sampled: a few KB of points can make a
	# lap of hundreds of km, minutes and GBs on every client (6.9); nothing is built for it
	var lb := LevelRoad.length_bounds(pts, closed)
	if lb.x > LevelValidate.LAP_MAX * LONG_SLACK or lb.y > LevelValidate.LAP_MAX * LevelRoad.LONG_BOUND:
		LevelValidate.issue(b.report, "lap_long", {"km": maxi(roundi(lb.x / 1000.0), 21)},
			{"road": -1, "s": 0.0, "pos": _first_pos(pts), "blocks": true})
	elif pts.size() >= 2:
		var zones := []
		if closed:
			zones.append({"a": road.get("start", {}), "before": GRID_BEFORE, "after": GRID_AFTER})
			var fz = _call(hooks.branches, "flat_zones", doc, [])
			if fz is Array:
				zones.append_array(fz)
		var bake = doc.data.get("bake", {})
		var ropts := {"key": -1, "flat": zones, "materials": _reg(ctx, "materials")}
		if closed and road.get("start") is Dictionary:
			ropts["start"] = road.start
		if bake is Dictionary and int(bake.get("main_n", 0)) > 0:
			ropts["n_hint"] = int(bake.main_n)
		ctx.main = LevelRoad.build(pts, ctx.styles, closed, ropts)
		if ctx.main.n >= 2:
			ctx.roads.append(ctx.main)
		drivable = closed and ctx.main.n >= 3 and ctx.main.length > 1.0
		if closed and not drivable:
			LevelValidate.issue(b.report, "compile", {"why": "the road has no length"}, {"road": -1})
		if drivable and bake is Dictionary and int(bake.get("main_n", 0)) > 0 and not ctx.main.hinted \
				and int(bake.main_n) != ctx.main.n:
			LevelValidate.issue(b.report, "bake_n", {"n": ctx.main.n, "was": int(bake.main_n)}, {"road": -1})
	times["road"] = _lap(tk)
	# 3 hazard setups, 4 branches (failing ones left out with their errors)
	if drivable:
		tk = Time.get_ticks_usec()
		_call(hooks.hazards, "pre_geometry", ctx)
		_call(hooks.branches, "build", ctx)
		times["branches"] = _lap(tk)
	# 5 terrain and the carve
	tk = Time.get_ticks_usec()
	ctx.terrain = LevelTerrain.from_doc(doc)
	if ctx.terrain != null and not ctx.roads.is_empty():
		var tr = doc.data.get("terrain", {})
		var flat := float(tr.get("flat", 6.0)) if tr is Dictionary else 6.0
		var blend := float(tr.get("blend", 28.0)) if tr is Dictionary else 28.0
		ctx.terrain.carve(ctx.roads, flat, blend, Rect2i(), ctx.pits)
	times["carve"] = _lap(tk)
	# 6 pits (after the carve: C1 M1) and safe drops
	for r in ctx.roads:
		r.mark_pits(Callable(ctx, "ground"))
	if drivable:
		_call(hooks.branches, "safe_drop", ctx)
	# 7 racing lines
	tk = Time.get_ticks_usec()
	if drivable:
		var off := LevelLine.racing(ctx.main)
		var adj = _call(hooks.branches, "adjust_lap_line", ctx, off, off)
		if adj is PackedFloat32Array and (adj as PackedFloat32Array).size() == ctx.main.n:
			off = adj
		LevelLine.apply(ctx.main, off)
		_call(hooks.branches, "racing", ctx)
	times["line"] = _lap(tk)
	# 8 geometry
	tk = Time.get_ticks_usec()
	for r in ctx.roads:
		LevelGeometry.build_road(ctx, r)
	if drivable:
		LevelGeometry.start_line(ctx)
		_call(hooks.branches, "geometry", ctx)
		_call(hooks.hazards, "geometry", ctx)
	times["geometry"] = _lap(tk)
	tk = Time.get_ticks_usec()
	if ctx.terrain != null and bool(opts.get("chunks", true)):
		_chunks(b, ctx.terrain)
	times["chunks"] = _lap(tk)
	_missing_styles(ctx)
	# 9 gameplay data
	tk = Time.get_ticks_usec()
	if drivable:
		_gameplay(ctx)
	else:
		_scenery_only(ctx)
	times["data"] = _lap(tk)
	# 10 branch entries, 11 hazards (setup-less ones left out), 12 crowds
	tk = Time.get_ticks_usec()
	if drivable:
		var br = _call(hooks.branches, "export_entries", ctx, [])
		ctx.data["branches"] = br if br is Array else []
		_low_gravity(ctx)
		var hz = _call(hooks.hazards, "resolve", ctx, [])
		ctx.data["hazards"] = hz if hz is Array else []
		_call(hooks.crowds, "compile", ctx)
	for k in ["branches", "hazards", "crowd_groups", "crowds", "crowd_eggs", "low_gravity"]:
		if not (ctx.data.get(k) is Array):
			ctx.data[k] = []
	times["hooks"] = _lap(tk)
	# 13 validation
	tk = Time.get_ticks_usec()
	ctx.set_meta("stats", _stats(ctx, b))
	LevelValidate.run(ctx)
	times["validate"] = _lap(tk)
	# 14 legal spots for the editor's tools
	if ctx.flags and drivable:
		var f = _call(hooks.branches, "legal", ctx, {})
		if f is Dictionary:
			for k in f:
				b.flags[k] = f[k]
		for tkey in LevelHazards.SETUP_TYPES:
			var lg = _call(hooks.hazards, "legal", ctx, PackedByteArray(), tkey)
			if lg is PackedByteArray:
				b.flags["hz_" + tkey] = lg
	# 15 the build
	b.data = ctx.data
	b.terrain = ctx.terrain
	for r in ctx.roads:
		b.roads.append(r)
	b.stats = ctx.get_meta("stats")
	b.stats["compile_ms"] = _lap(t0)
	b.stats["times"] = times
	b.stats["triangles"] = b.meshes.triangles()
	b.meta = _meta(ctx, b)
	return b


## Snapshot + registries taken here; done(build) deferred on the main thread. Returns a job id.
static func compile_async(doc: LevelDoc, opts: Dictionary, done: Callable) -> int:
	var snap := doc.snapshot() if doc != null else null
	var o: Dictionary = opts.duplicate() if opts != null else {}
	if not (o.get("registries") is Dictionary):
		o["registries"] = registries()
	var holder := [-1]
	var job := func() -> void:
		var built := LevelCompiler.compile(snap, o)
		LevelCompiler._compiled.call_deferred(holder, built, done)
	holder[0] = WorkerThreadPool.add_task(job, false, "LevelCompiler.compile_async")
	return holder[0]


## The drag preview (C1 M5): re-samples only the segments touching the dragged points plus one
## neighbour each side, widened to whole segment groups so the swapped groups are complete
## (LevelRoad.build_partial), and emits those groups' meshes only: no branches, carve, line,
## data or validation. roads = the partial road, stats.groups = the changed groups' names.
static func preview_segments(doc: LevelDoc, road_key: int, point_uids: PackedInt32Array, prev: LevelBuild) -> LevelBuild:
	var t0 := Time.get_ticks_usec()
	var b := LevelBuild.new()
	b.report = LevelReport.new()
	b.partial = true
	b.meshes = LevelMeshSet.new()
	b.stats = {"groups": PackedStringArray()}
	if doc == null:
		return b
	b.revision = doc.revision
	var pts: Array = []
	var closed := false
	if road_key == -1:
		var road = doc.data.get("road", {})
		if road is Dictionary and road.get("points") is Array:
			pts = road.points
			closed = bool(road.get("closed", false)) and pts.size() >= 3
	else:
		for br in doc.data.get("branches", []):
			if br is Dictionary and int(br.get("uid", 0)) == road_key and br.get("points") is Array:
				pts = br.points
	var ns := pts.size() if closed else pts.size() - 1
	if ns < 1:
		return b
	var touched := {}
	for k in pts.size():
		if not (pts[k] is Dictionary) or not (int(pts[k].get("uid", 0)) in point_uids):
			continue
		for d in range(-2, 2):   # segments k-2 .. k+1 change with a point's AUTO handles
			var sk := k + d
			if closed:
				touched[posmod(sk, ns)] = true
			elif sk >= 0 and sk < ns:
				touched[sk] = true
	if touched.is_empty():
		return b
	var groups := {}
	for sk in touched:
		groups[int(sk) / LevelRoad.SEG_GROUP] = true
	var gl := groups.keys()
	gl.sort()
	var window := _window(gl, ns, closed)
	var styles: Dictionary = prev.styles if prev != null and not prev.styles.is_empty() else LevelStyles.resolve(doc.data, {})
	var tr := Time.get_ticks_usec()
	var r := LevelRoad.build_partial(pts, styles, closed, window.x, window.y, {"key": road_key})
	b.stats["road_ms"] = _lap(tr)
	if r.n < 2:
		return b
	var ctx := LevelContext.new()
	ctx.doc = doc
	ctx.report = b.report
	ctx.styles = styles
	ctx.preview = true
	ctx.meshes = b.meshes
	ctx.main = r
	ctx.roads.append(r)
	ctx.light_extra = float(prev.stats.get("light_extra", -1.0)) if prev != null else -1.0
	var want := PackedInt32Array()
	for g in gl:
		want.append(int(g))
	tr = Time.get_ticks_usec()
	LevelGeometry.build_road(ctx, r, want)
	b.stats["mesh_ms"] = _lap(tr)
	b.roads.append(r)
	b.styles = styles
	var names := PackedStringArray()
	for g in want:
		names.append(r.group_name(g))
	b.stats["groups"] = names
	b.stats["triangles"] = b.meshes.triangles()
	b.stats["samples"] = r.n
	b.stats["compile_ms"] = _lap(t0)
	return b


## Game's registries, on the calling thread: {models, materials, skies, music} (music: id -> true).
## The dictionaries are Game's own (read-only once loaded), not copies.
static func registries() -> Dictionary:
	# off the main thread the tree is not ours to read: no registry known (keys kept as they are);
	# callers on a worker pass opts.registries taken on the main thread
	var g := _game() if OS.get_thread_caller_id() == OS.get_main_thread_id() else null
	if g == null:
		return {"models": {}, "materials": {}, "skies": {}, "music": {}}
	var music := {}
	var ml = g.get("music_library")
	if ml is Array:
		for e in ml:
			if e is Dictionary and str(e.get("id", "")) != "":
				music[str(e.id)] = true
	return {"models": _dict(g.get("models")), "materials": _dict(g.get("materials_db")),
		"skies": _dict(g.get("skies")), "music": music}


# ---------------------------------------------------------------- 3.7 gameplay data

static func _gameplay(ctx: LevelContext) -> void:
	var d := ctx.data
	var m := ctx.main
	d["path"] = m.export_path()
	_grid(ctx)
	_crates(ctx)
	_pads(ctx)
	d["props"] = []
	ctx.props = d.props
	_barrels(ctx)
	_props(ctx)
	_lights_fx(ctx)
	_water(ctx)
	_env(ctx)
	_race(ctx)


## An open road or one being drawn: the look (props, lights, env, water) without race data.
static func _scenery_only(ctx: LevelContext) -> void:
	ctx.data["props"] = []
	ctx.props = ctx.data.props
	_props(ctx)
	_lights_fx(ctx)
	_water(ctx)
	_env(ctx)
	_race(ctx)


static func _grid(ctx: LevelContext) -> void:
	var m := ctx.main
	var grid := []
	for k in GRID_SLOTS:
		var back := 10.0 + 6.5 * k
		var i := posmod(roundi(-back / m.step), m.n)
		var col := -1.0 if k % 2 == 0 else 1.0
		var p := m.pos[i] + m.right[i] * col * minf(4.5, 0.22 * m.width[i]) + m.up[i] * 0.8
		grid.append({"pos": _r3(p), "fwd": _r4(m.fwd[i])})
	ctx.data["grid"] = grid


## Crate rows in doc order (the main road's, then each kept branch's), then single crates.
static func _crates(ctx: LevelContext) -> void:
	var d := ctx.doc.data
	var boxes := []
	var rows_meta := []
	var auto := {}
	var bake = d.get("bake", {})
	var hints = bake.get("rows", {}) if bake is Dictionary else {}
	var cos2 := cos(deg_to_rad(2.0))
	var items: Array = d.get("items", []) if d.get("items") is Array else []
	for r in ctx.roads:
		for it in items:
			if not (it is Dictionary) or int(it.get("road", -1)) != r.key or not (it.get("at") is Dictionary):
				continue
			var i := r.anchor_i(it.at)
			var guard := 0
			while (r.gap[r.wrap(i)] == 1 or r.gap[r.wrap(i + 8)] == 1 or r.gap[r.wrap(i - 8)] == 1) \
					and (r.closed or i < r.n) and guard < 200:
				i += 5
				guard += 1
			i = r.wrap(i)
			var w := r.width[i]
			var w_in := w * 0.5 - float(it.get("inset", 2.5))
			var own := maxi(1, mini(5 if w >= 16.0 else 4, floori(2.0 * w_in / BOX_GAP + 1e-6) + 1))
			var count := int(it.get("count", 0))
			var key := str(int(it.get("uid", 0)))
			if count <= 0:
				count = own
				if hints is Dictionary and hints.has(key) and absi(int(hints[key]) - own) <= 1 and int(hints[key]) >= 1:
					count = int(hints[key])
				auto[key] = count
			var crates := []
			for k in count:
				var lat := 0.0 if count == 1 else -w_in + 2.0 * w_in * k / (count - 1)
				var c := r.surface(i, lat, BOX_H)
				var u := r.up[i]
				crates.append(c)
				boxes.append(_r3(c) if u.y >= cos2 else _r3(c) + _r4(u))
			rows_meta.append({"uid": int(it.get("uid", 0)), "road": r.key, "i": i, "s": r.s[i], "crates": crates})
	for c in d.get("crates", []):
		if c is Dictionary and c.get("pos") is Array:
			boxes.append(_r3(_v3(c.pos)))
	ctx.data["item_boxes"] = boxes
	ctx.set_meta("rows", rows_meta)
	ctx.set_meta("rows_auto", auto)


## Boost pads (pad_entry port): on the racing line or the doc's lat, clipped off an open edge,
## 0.06 m over the surface, `turn` degrees about up (positive turns right).
static func _pads(ctx: LevelContext) -> void:
	var out := []
	var meta := []
	var pads: Array = ctx.doc.data.get("pads", []) if ctx.doc.data.get("pads") is Array else []
	for r in ctx.roads:
		var has_line := r.line.size() == r.n
		for pd in pads:
			if not (pd is Dictionary) or int(pd.get("road", -1)) != r.key or not (pd.get("at") is Dictionary):
				continue
			var i := r.anchor_i(pd.at)
			var lat := 0.0
			if pd.get("lat") is float or pd.get("lat") is int:
				lat = float(pd.lat)
			elif has_line:
				lat = (r.line[i] - r.pos[i]).dot(r.right[i])
			if r.pit[i] == 1:
				var lim := maxf(r.width[i] * 0.5 - PAD_HALF_W - 1.0, 0.0)
				lat = clampf(lat, -lim, lim)
			var up := r.up[i]
			var p := r.surface(i, lat, PAD_UP)
			var f := r.fwd[i]
			var turn := float(pd.get("turn", 0.0))
			if turn != 0.0:
				f = f.rotated(up, -deg_to_rad(turn))
			out.append({"pos": _r3(p), "fwd": _r4(f), "up": _r4(up)})
			meta.append({"uid": int(pd.get("uid", 0)), "road": r.key, "i": i, "s": r.s[i], "pos": p})
	ctx.data["boost_pads"] = out
	ctx.set_meta("pads", meta)


## Barrel clusters: three explosive drums across the road at the anchor, seeded jitter.
static func _barrels(ctx: LevelContext) -> void:
	var list: Array = ctx.doc.data.get("barrels", []) if ctx.doc.data.get("barrels") is Array else []
	if list.is_empty():
		return
	if not _has(ctx, "models", BARREL_MODEL):
		ctx.report.add_missing("models", list.size())
		return
	for r in ctx.roads:
		for br in list:
			if not (br is Dictionary) or int(br.get("road", -1)) != r.key or not (br.get("at") is Dictionary):
				continue
			var i := r.anchor_i(br.at)
			var rng := ctx.rng(int(br.get("uid", 0)))
			var w := r.width[i]
			for lat in [-w / 6.0, 0.0, w / 6.0]:
				var l: float = lat + rng.randf_range(-0.4, 0.4)
				var along := rng.randf_range(-0.4, 0.4)
				var p := r.surface(i, l, BARREL_UP) + r.fwd[i] * along
				ctx.data.props.append({"model": BARREL_MODEL, "pos": _r3(p),
					"yaw": snappedf(rng.randf_range(-PI, PI), 0.0001), "physics": true})


## The doc's props this install has (missing models skipped and counted); physics only for models
## of <= 60 kg and a diagonal under 3 m (others static, with a warning).
static func _props(ctx: LevelContext) -> void:
	var models := _reg(ctx, "models")
	var src := []
	var heavy := 0
	var sea := _sea(ctx)
	for p in ctx.doc.data.get("props", []):
		if not (p is Dictionary) or not (p.get("pos") is Array):
			continue
		var key := str(p.get("model", ""))
		if not models.is_empty() and not models.has(key):
			ctx.report.add_missing("models")
			continue
		var e := {"model": key, "pos": _r3(_v3(p.pos)), "yaw": snappedf(deg_to_rad(float(p.get("yaw", 0.0))), 0.0001)}
		var pitch := float(p.get("pitch", 0.0))
		var roll := float(p.get("roll", 0.0))
		if pitch != 0.0:
			e["pitch"] = snappedf(deg_to_rad(pitch), 0.0001)
		if roll != 0.0:
			e["roll"] = snappedf(deg_to_rad(roll), 0.0001)
		var sc := snappedf(float(p.get("scale", 1.0)), 0.05)
		if sc != 1.0 and sc > 0.0:
			e["scale"] = sc
		var tag := str(p.get("tag", ""))
		if tag == "float" and not sea:
			tag = ""
		if bool(p.get("physics", false)):
			if models.is_empty() or _light_enough(models.get(key, {}), sc if sc > 0.0 else 1.0):
				e["physics"] = true
			else:
				heavy += 1
		if tag != "":
			e["tag"] = tag
		ctx.data.props.append(e)
		src.append([int(p.get("uid", 0)), e])
	if heavy > 0:
		LevelValidate.issue(ctx.report, "prop_static", {"count": heavy})
	ctx.set_meta("props_src", src)


## PropCatalog.physics_ok's rule at the prop's scale: a "props" model of at most PHYS_MASS kg
## whose AABB's largest side is under PHYS_SIZE.
static func _light_enough(info: Variant, sc: float) -> bool:
	if not (info is Dictionary) or str(info.get("kind", "props")) != "props":
		return false
	var mass := float(info.get("mass", 1e9))
	var a = info.get("aabb_min")
	var z = info.get("aabb_max")
	if not (a is Array and z is Array) or (a as Array).size() < 3 or (z as Array).size() < 3:
		return false
	var e := (_v3(z) - _v3(a)).abs()
	return mass <= PHYS_MASS and maxf(e.x, maxf(e.y, e.z)) * sc < PHYS_SIZE


## Lights (tunnel lights first, then the doc's, 128 in all), fires, screens (combine arch only),
## lakes.
static func _lights_fx(ctx: LevelContext) -> void:
	var d := ctx.doc.data
	var lights := []
	for l in ctx.tunnel_lights:
		if lights.size() >= MAX_LIGHTS:
			break
		if l is Dictionary:
			lights.append({"pos": _r3(_v3(l.get("pos"))), "color": _col(l.get("color")),
				"range": snappedf(float(l.get("range", 16.0)), 0.01), "energy": snappedf(float(l.get("energy", 1.6)), 0.01)})
	var wanted := lights.size()
	for l in d.get("lights", []):
		if not (l is Dictionary) or not (l.get("pos") is Array):
			continue
		wanted += 1
		if lights.size() >= MAX_LIGHTS:
			continue
		lights.append({"pos": _r3(_v3(l.pos)), "color": _col(l.get("color")),
			"range": float(l.get("range", 16.0)), "energy": float(l.get("energy", 1.2))})
	ctx.data["lights"] = lights
	ctx.set_meta("lights_wanted", wanted)
	var fires := []
	for f in d.get("fires", []):
		if f is Dictionary and f.get("pos") is Array:
			fires.append({"pos": _r3(_v3(f.pos)), "size": float(f.get("size", 1.0)),
				"smoke": float(f.get("smoke", 1.0)), "light": bool(f.get("light", true))})
	ctx.data["fires"] = fires
	var screens := []
	var race = d.get("race", {})
	var combine := not (race is Dictionary) or str(race.get("gantry", "combine")) == "combine"
	var left := 0
	for s in d.get("screens", []):
		if not (s is Dictionary) or not (s.get("pos") is Array):
			continue
		if not combine:
			left += 1
			continue
		screens.append({"pos": _r3(_v3(s.pos)), "yaw": snappedf(deg_to_rad(float(s.get("yaw", 0.0))), 0.0001),
			"w": float(s.get("w", 8.0)), "h": float(s.get("h", 4.5))})
	if left > 0:
		LevelValidate.issue(ctx.report, "screens", {"count": left})
	ctx.data["screens"] = screens
	var waters := []
	for l in d.get("lakes", []):
		if l is Dictionary and l.get("center") is Array and l.get("size") is Array:
			waters.append({"center": [float(l.center[0]), float(l.center[1])], "size": [float(l.size[0]), float(l.size[1])],
				"level": float(l.get("level", 0.0))})
	ctx.data["waters"] = waters


static func _water(ctx: LevelContext) -> void:
	var w = ctx.doc.data.get("water", {})
	if _sea(ctx):
		var lv := float(w.get("level", 0.0))
		ctx.data["water"] = {"level": lv}
		ctx.data["sea_level"] = lv
		ctx.data["sea_center"] = [0.0, 0.0]
		ctx.data["sea_size"] = ctx.doc.world_size() * 3.0
	else:
		ctx.data["sea_level"] = -1000.0


## sky (a key this install has, else sky_day01_01 and counted), env (the set keys; sun {az, el}
## -> sun_dir), terrain_layers (material keys -> albedo paths: the material's, else the texture at
## materials/<key>.png when this install has it, else left out and counted).
static func _env(ctx: LevelContext) -> void:
	var e = ctx.doc.data.get("env", {})
	if not (e is Dictionary):
		e = {}
	var sky := str(e.get("sky", DEFAULT_SKY))
	var skies := _reg(ctx, "skies")
	if not skies.is_empty() and not skies.has(sky):
		ctx.report.add_missing("skies")
		sky = DEFAULT_SKY
	ctx.data["sky"] = sky
	var env := {}
	for k in ENV_KEYS:
		if e.has(k) and e[k] != null:
			env[k] = e[k].duplicate() if e[k] is Array else e[k]
	var sun = e.get("sun")
	if sun is Dictionary:
		var az := deg_to_rad(float(sun.get("az", 0.0)))
		var el := deg_to_rad(float(sun.get("el", 45.0)))
		env["sun_dir"] = [snappedf(cos(el) * sin(az), 0.0001), snappedf(sin(el), 0.0001), snappedf(cos(el) * cos(az), 0.0001)]
	ctx.data["env"] = env
	if ctx.terrain != null:
		var mats := _reg(ctx, "materials")
		var tl := {}
		var layers = ctx.terrain.layers
		for k in LevelThemes.LAYER_KEYS:
			var key := str(layers.get(k, "")) if layers is Dictionary else ""
			if key == "":
				continue
			if mats.is_empty():
				tl[k] = "materials/%s.png" % key
			elif mats.get(key) is Dictionary and str(mats[key].get("albedo", "")) != "":
				tl[k] = str(mats[key].albedo)
			elif ResourceLoader.exists("res://assets/materials/%s.png" % key):
				# a texture the circuits use with no VMT entry (their sand, forest grass, Xen ground)
				tl[k] = "materials/%s.png" % key
			else:
				ctx.report.add_missing("materials")
		ctx.data["terrain_layers"] = tl


## The race keys: gantry, gantry_clear, background (+ citadel, seagulls for city17), bg_center,
## rescue, offtrack, music, kill_y (always), custom.
static func _race(ctx: LevelContext) -> void:
	var d := ctx.doc.data
	var race = d.get("race", {})
	if not (race is Dictionary):
		race = {}
	var data := ctx.data
	data["gantry"] = str(race.get("gantry", "combine"))
	var m := ctx.main
	var clear := 0.0
	if m != null and m.n > 0:
		var st := m.style_at(0)
		match m.kind(0):
			"street":
				clear = float(st.get("walk", 4.0)) + 0.3
			"bridge":
				clear = 1.0
			"tunnel":
				clear = float(st.get("wall_gap", 0.6))
			_:
				clear = float(st.get("verge_w", 4.0))
	data["gantry_clear"] = snappedf(clear, 0.001)
	var bg := str(race.get("background", "none"))
	data["background"] = bg
	var size := ctx.doc.world_size()
	if bg == "city17":
		var cit = race.get("citadel")
		data["citadel"] = (cit as Array).duplicate() if cit is Array and (cit as Array).size() >= 4 \
			else [-0.9 * size, -260.0, -2.25 * size, 9.0]
		if race.get("seagulls") is Array:
			data["seagulls"] = (race.seagulls as Array).duplicate(true)
	var low := INF
	var high := -INF
	for r in ctx.roads:
		for i in r.n:
			low = minf(low, r.pos[i].y)
			high = maxf(high, r.pos[i].y)
	if ctx.terrain != null:
		low = minf(low, ctx.terrain.bottom())
		high = maxf(high, ctx.terrain.top())
	if low == INF:
		low = 0.0
		high = 0.0
	data["kill_y"] = snappedf(low - KILL_BELOW, 0.001)
	data["bg_center"] = [0.0, snappedf(high + BG_ABOVE, 0.001), 0.0]
	data["rescue"] = str(race.get("rescue", "scanner"))
	data["offtrack"] = float(race.get("offtrack", 60.0))
	var music := []
	var lib := _reg(ctx, "music")
	for id in race.get("music", []):
		if not (id is String):
			continue
		if lib.is_empty() or lib.has(id):
			music.append(id)
		else:
			ctx.report.add_missing("music")
	data["music"] = music
	data["custom"] = {"guid": str(d.get("guid", "")), "name": str(d.get("name", "")), "author": str(d.get("author", ""))}


## Low-gravity zones: {route: -1 or the branch's index in data.branches, branch: "b<uid>", s0, s1,
## scale, ease}; zones on a branch left out of the build are left out too.
static func _low_gravity(ctx: LevelContext) -> void:
	var out := []
	var index := {}
	var k := 0
	for e in ctx.data.get("branches", []):
		if e is Dictionary:
			index[str(e.get("id", ""))] = k
		k += 1
	for z in ctx.doc.data.get("zones", []):
		if not (z is Dictionary) or not (z.get("a") is Dictionary) or not (z.get("b") is Dictionary):
			continue
		var key := int(z.get("road", -1))
		var r := ctx.road(key)
		if r == null or r.n < 2:
			continue
		var e := {"route": -1, "s0": snappedf(r.anchor_s(z.a), 0.01), "s1": snappedf(r.anchor_s(z.b), 0.01),
			"scale": float(z.get("scale", 0.4)), "ease": float(z.get("ease", 15.0))}
		if key != -1:
			var bid := "b%d" % key
			if not index.has(bid):
				continue
			e["route"] = index[bid]
			e["branch"] = bid
		out.append(e)
	ctx.data["low_gravity"] = out


# ---------------------------------------------------------------- pieces

## The terrain's render chunks (LOD0 and LOD1) and the edge skirt, on the worker.
static func _chunks(b: LevelBuild, t: LevelTerrain) -> void:
	var cc := t.chunk_count()
	for cz in cc:
		for cx in cc:
			var h := t.chunk_hash(cx, cz)
			for lod in 2:
				var arr := t.chunk_arrays(cx, cz, lod)
				if arr.is_empty():
					continue
				var nm := ("terrain_lod_%d_%d" if lod >= 1 else "terrain_%d_%d") % [cx, cz]
				b.chunks.append({"name": nm, "cx": cx, "cz": cz, "lod": lod, "hash": h, "arrays": arr})
	b.skirt = t.edge_skirt_arrays()


## Counts the material slots of the styles the roads use that this install lacks.
static func _missing_styles(ctx: LevelContext) -> void:
	var seen := {}
	for r in ctx.roads:
		for st in r.styles:
			var id := str(st.get("id", ""))
			if seen.has(id):
				continue
			seen[id] = true
			var miss = st.get("missing", [])
			if miss is PackedStringArray or miss is Array:
				if miss.size() > 0:
					ctx.report.add_missing("materials", miss.size())


static func _stats(ctx: LevelContext, b: LevelBuild) -> Dictionary:
	var samples := 0
	var branch_n := {}
	for r in ctx.roads:
		samples += r.n
		if r.key != -1:
			branch_n[str(r.key)] = r.n
	var heavy := 0
	for h in ctx.data.get("hazards", []):
		if h is Dictionary and str(h.get("type", "")) in LevelDoc.HEAVY:
			heavy += 1
	return {"samples": samples, "props": (ctx.data.get("props", []) as Array).size(),
		"lights": (ctx.data.get("lights", []) as Array).size(),
		"lights_wanted": int(ctx.get_meta("lights_wanted", 0)) if ctx.has_meta("lights_wanted") else 0,
		"people": (ctx.data.get("crowds", []) as Array).size(), "heavy": heavy,
		"crates": (ctx.data.get("item_boxes", []) as Array).size(), "light_extra": ctx.light_extra,
		"bake": {"main_n": ctx.main.n if ctx.main != null else 0, "branch_n": branch_n,
			"rows": ctx.get_meta("rows_auto", {}) if ctx.has_meta("rows_auto") else {}},
		"chunks": b.chunks.size()}


static func _meta(ctx: LevelContext, b: LevelBuild) -> Dictionary:
	var d := ctx.doc.data
	var f := b.facts()
	var race = d.get("race", {})
	return {"id": b.id, "name": str(d.get("name", "")), "short": str(d.get("short", "")), "desc": str(d.get("desc", "")),
		"author": str(d.get("author", "")), "rescue": str(race.get("rescue", "scanner")) if race is Dictionary else "scanner",
		"guid": str(d.get("guid", "")), "length": f.length, "branches": f.branches, "props": f.props,
		"hazards": f.hazards, "raceable": f.raceable, "errors": f.errors, "warnings": f.warnings}


## The window of segments covering whole groups `gl` (sorted group indices): Vector2i(first, last);
## on a loop the window may wrap (first > last).
static func _window(gl: Array, ns: int, closed: bool) -> Vector2i:
	var ng := (ns + LevelRoad.SEG_GROUP - 1) / LevelRoad.SEG_GROUP
	var g0: int = gl[0]
	var g1: int = gl[gl.size() - 1]
	if closed and gl.size() > 1:
		# the largest gap between touched groups (round the loop) is left out
		var best := -1
		var at := 0
		for q in gl.size():
			var a: int = gl[q]
			var nxt: int = gl[(q + 1) % gl.size()]
			var gap := posmod(nxt - a, ng)
			if gap > best:
				best = gap
				at = q
		g0 = gl[(at + 1) % gl.size()]
		g1 = gl[at]
	var first := g0 * LevelRoad.SEG_GROUP
	var last := mini(g1 * LevelRoad.SEG_GROUP + LevelRoad.SEG_GROUP - 1, ns - 1)
	return Vector2i(first, last)


static func _compiled(holder: Array, b: LevelBuild, done: Callable) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	if done.is_valid():
		done.call(b)


# ---------------------------------------------------------------- helpers

static func _hooks(opts: Dictionary) -> Dictionary:
	var h = opts.get("hooks", {})
	if not (h is Dictionary):
		h = {}
	return {"branches": h.get("branches", LevelBranches), "hazards": h.get("hazards", LevelHazards),
		"crowds": h.get("crowds", LevelCrowds)}


## Calls a hook's static method; `fallback` when the hook (or that method of it) is missing.
static func _call(hook: Variant, method: String, ctx: Variant, fallback: Variant = null, arg2: Variant = null) -> Variant:
	if hook == null or not hook.has_method(method):
		return fallback
	if arg2 != null:
		return hook.call(method, ctx, arg2)
	return hook.call(method, ctx)


static func _reg(ctx: LevelContext, what: String) -> Dictionary:
	var v = ctx.registries.get(what, {})
	return v if v is Dictionary else {}


static func _has(ctx: LevelContext, what: String, key: String) -> bool:
	var r := _reg(ctx, what)
	return r.is_empty() or r.has(key)


static func _sea(ctx: LevelContext) -> bool:
	var w = ctx.doc.data.get("water", {})
	return w is Dictionary and bool(w.get("sea", false))


static func _lap(t0: int) -> float:
	return snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null


static func _first_pos(pts: Array) -> Vector3:
	for p in pts:
		if p is Dictionary:
			return _v3(p.get("pos"))
	return Vector3.ZERO


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _col(v: Variant) -> Array:
	if v is Array and (v as Array).size() >= 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return [1.0, 1.0, 1.0]


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _r4(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
