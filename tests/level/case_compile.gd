extends RefCounted
## P4: the compiler pipeline on hand-made documents, without content (spec 3.1, 3.7, 3.8, 3.11,
## 4.4): the exported path loads in TrackPath; 8 grid slots; crates in rows of the expected count
## and doc order; pads 0.06 m over the surface; sea / background / kill_y always written; no pit
## over a carved valley and pits everywhere without terrain; a figure eight with a bridge, a
## tunnel road; preview_segments of a 4 km loop <= 12 ms; the digest stable and a snapshot
## unaffected by later edits (also through compile_async); failing branches and setup-less
## hazards left out with their errors kept (stub hooks); open / empty roads; instantiate; themes.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}
## The budgets of 3.11 are this PC's; a CI runner gets three times as long.
var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0


func run(t: Node) -> void:
	_oval_case(t)
	_valley_case(t)
	_no_terrain_case(t)
	_figure8_case(t)
	_tunnel_case(t)
	await _digest_case(t)
	_preview_case(t)
	_leave_out_case(t)
	_open_case(t)
	_themes_case(t)
	_budget_case(t)
	_content_case(t)


# ---------------------------------------------------------------- stub hooks

## Branches: one branch (uid 5) fails its early lint and is left out; one (uid 77) is kept.
class FakeBranches:
	static func flat_zones(_doc: LevelDoc) -> Array:
		return []

	static func build(ctx: LevelContext) -> void:
		LevelValidate.issue(ctx.report, "branch_nose", {"name": "B1", "m": 90}, {"uid": 5, "road": 5})
		var m := ctx.main
		var pts := []
		for k in 4:
			var i := m.wrap(40 + k * 20)
			var p := m.pos[i] + m.flat_right[i] * 30.0
			pts.append({"uid": 900 + k, "pos": [p.x, p.y, p.z], "width": 10.0, "style": "asphalt"})
		var r := LevelRoad.build(pts, ctx.styles, false, {"key": 77})
		ctx.branches = [{"uid": 5, "ok": false}, {"uid": 77, "ok": true}]
		ctx.roads.append(r)

	static func safe_drop(_ctx: LevelContext) -> void:
		pass

	static func adjust_lap_line(_ctx: LevelContext, off: PackedFloat32Array) -> PackedFloat32Array:
		return off

	static func racing(_ctx: LevelContext) -> void:
		pass

	static func geometry(_ctx: LevelContext) -> void:
		pass

	static func export_entries(ctx: LevelContext) -> Array:
		var out := []
		for r in ctx.roads:
			if r.key == 77:
				out.append({"id": "b77", "name": "KEPT", "index": 0, "path": r.export_path(), "fork_s": 80.0,
					"merge_s": 200.0, "fork_i": 13, "merge_i": 33, "fork_nose_i": 16, "merge_nose_i": 30})
		return out

	static func lint(_ctx: LevelContext) -> void:
		pass

	static func legal(_ctx: LevelContext) -> Dictionary:
		return {"branch_fork": PackedByteArray([1, 0]), "branch_merge": PackedByteArray([0, 1])}


## Hazards: two in the doc, the second has no setup and is left out with its error.
class FakeHazards:
	static func pre_geometry(_ctx: LevelContext) -> void:
		pass

	static func geometry(_ctx: LevelContext) -> void:
		pass

	static func resolve(ctx: LevelContext) -> Array:
		LevelValidate.issue(ctx.report, "hazard_setup", {"what": "ceiling turret", "needs": "a tunnel"}, {"uid": 9})
		return [{"id": 0, "type": "turret", "s": 120.123456, "span": [100.0, 140.0], "seed": ctx.seed_of(8),
			"pos": [1.0, 2.0, 3.0], "p": {"x": 1}}]

	static func lint(_ctx: LevelContext) -> void:
		pass

	static func legal(_ctx: LevelContext, _type_key: String) -> PackedByteArray:
		return PackedByteArray([1])


# ---------------------------------------------------------------- helpers

## An elliptic loop a x b of `count` points at height y (+ hills), point 0 at (a, y, 0), the start
## on point 0.
static func oval(doc: LevelDoc, a := 180.0, b := 110.0, count := 20, y := 0.0, style := "asphalt", w := 14.0, hills := 0.0) -> Array:
	var pts := []
	for k in count:
		var ang := TAU * k / count
		pts.append({"uid": doc.new_uid(), "pos": [a * cos(ang), y + hills * sin(ang * 2.0), b * sin(ang)],
			"width": w, "style": style})
	doc.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	return pts


static func vec(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


func _codes(b: LevelBuild) -> PackedStringArray:
	var out := PackedStringArray()
	for it in b.report.items:
		out.append(str(it.code))
	return out


func _no_format_left(s: String) -> bool:
	return not (s.contains("%d") or s.contains("%s") or s.contains("%."))


# ---------------------------------------------------------------- the oval

func _oval_case(t: Node) -> void:
	var doc := LevelDoc.blank("Oval", 512.0, 257)
	var pts := oval(doc)
	doc.data.items = [
		{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[3].uid, "t": 0.5}, "count": 0, "inset": 2.5},
		{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[8].uid, "t": 0.5}, "count": 3, "inset": 2.5},
	]
	doc.data.crates = [{"uid": doc.new_uid(), "pos": [10.0, 1.2, 20.0]}]
	doc.data.pads = [
		{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[12].uid, "t": 0.3}, "lat": null, "turn": 0.0},
		{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[14].uid, "t": 0.5}, "lat": 3.0, "turn": 10.0},
	]
	doc.data.barrels = [{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[16].uid, "t": 0.5}}]
	doc.data.props = [
		{"uid": doc.new_uid(), "model": "props_c17/bench01a", "pos": [0.0, 0.0, 0.0], "yaw": 90.0, "pitch": 0.0,
			"roll": 0.0, "scale": 1.0, "physics": false, "tag": ""},
		{"uid": doc.new_uid(), "model": "props_junk/trashbin01a", "pos": [5.0, 0.0, 5.0], "yaw": 0.0, "pitch": 10.0,
			"roll": 0.0, "scale": 1.5, "physics": true, "tag": "deco"},
	]
	doc.data.lights = [{"uid": doc.new_uid(), "pos": [0.0, 5.0, 0.0], "color": [1, 0.5, 0.2], "range": 16.0, "energy": 1.2}]
	doc.data.fires = [{"uid": doc.new_uid(), "pos": [20.0, 0.0, 0.0], "size": 2, "smoke": 1.0, "light": true}]
	doc.data.screens = [{"uid": doc.new_uid(), "pos": [0.0, 10.0, 60.0], "yaw": 90.0, "w": 8.0, "h": 4.5}]
	doc.data.env["sun"] = {"az": 90.0, "el": 30.0}
	doc.data.race["music"] = ["hl2_song12_long"]
	var b := LevelCompiler.compile(doc, {"id": "c_test", "registries": REG})
	var d := b.data
	t.check(b.report.errors() == 0, "the oval compiles without errors (%s)" % str(_codes(b)))
	t.check(b.revision == doc.revision and b.id == "c_test" and not b.partial, "id, revision, not partial")
	var m: LevelRoad = b.roads[0]
	# the path
	var path: Dictionary = d.get("path", {})
	var tp := TrackPath.new(path)
	t.check(tp.n == (path.center as Array).size() and tp.n * 3 == m.n, "TrackPath loads the exported path (n %d)" % tp.n)
	t.near(tp.step, float(path.length) / tp.n, 1e-3, "TrackPath step == length / n")
	t.check(path.closed == true, "the path is closed")
	# grid
	var grid: Array = d.get("grid", [])
	t.check(grid.size() == 8, "8 grid slots")
	var behind := true
	var high := true
	for k in grid.size():
		var p := vec(grid[k].pos)
		var i := m.closest(p)
		var back := m.length - m.s[i] if m.s[i] > m.length * 0.5 else -m.s[i]
		behind = behind and absf(back - (10.0 + 6.5 * k)) < 3.0
		high = high and absf((p - m.pos[i]).dot(m.up[i]) - 0.8) < 0.05
	t.check(behind, "grid slots 10 + 6.5 k m behind the line")
	t.check(high, "grid slots 0.8 m over the road")
	# crates: a row of the auto count (4 on 14 m), a row of 3, then the single crate, in doc order
	var boxes: Array = d.get("item_boxes", [])
	t.check(boxes.size() == 8, "crates: 4 + 3 + 1 (%d)" % boxes.size())
	if boxes.size() == 8:
		var i3 := m.anchor_i(doc.data.items[0].at)
		var i8 := m.anchor_i(doc.data.items[1].at)
		var ok := true
		for k in 4:
			ok = ok and vec(boxes[k]).distance_to(m.pos[i3]) < 8.0
		for k in range(4, 7):
			ok = ok and vec(boxes[k]).distance_to(m.pos[i8]) < 8.0
		t.check(ok, "crate rows in doc order at their anchors")
		t.check(vec(boxes[7]).is_equal_approx(Vector3(10, 1.2, 20)), "the single crate last, as placed")
		var c0 := vec(boxes[0])
		t.near((c0 - m.pos[i3]).dot(m.up[i3]), 1.2, 0.02, "crates 1.2 m over the surface")
		t.near(vec(boxes[0]).distance_to(vec(boxes[3])), 9.0, 0.05, "the auto row spans 2 * (w / 2 - inset)")
	t.check(str(b.stats.bake.rows.get(str(doc.data.items[0].uid), -1)) == "4" and not b.stats.bake.rows.has(str(doc.data.items[1].uid)),
		"stats.bake.rows keeps the auto row's count only")
	# pads: 0.06 over the surface, on the line or the doc's lat, turned
	var pads: Array = d.get("boost_pads", [])
	t.check(pads.size() == 2, "2 boost pads")
	for k in pads.size():
		var pd: Dictionary = doc.data.pads[k]
		var i := m.anchor_i(pd.at)
		var p := vec(pads[k].pos)
		t.near((p - m.pos[i]).dot(m.up[i]), 0.06, 0.002, "pad %d 0.06 m over the surface" % k)
		if k == 1:
			t.near((p - m.pos[i]).dot(m.right[i]), 3.0, 0.01, "pad lat as the doc says")
			t.near(rad_to_deg(vec(pads[k].fwd).angle_to(m.fwd[i])), 10.0, 0.1, "pad turned 10 deg")
		else:
			t.near((p - m.pos[i]).dot(m.right[i]), (m.line[i] - m.pos[i]).dot(m.right[i]), 0.01, "pad on the racing line")
	# props: 3 barrels (physics) then the doc's 2
	var props: Array = d.get("props", [])
	t.check(props.size() == 5, "3 barrels + 2 props (%d)" % props.size())
	if props.size() == 5:
		t.check(props[0].model == LevelCompiler.BARREL_MODEL and props[0].physics == true, "barrels are physics drums")
		t.near(float(props[3].yaw), PI / 2.0, 1e-3, "prop yaw in radians")
		t.check(not props[3].has("scale") and not props[3].has("pitch") and not props[3].has("tag") and not props[3].has("physics"),
			"defaults left out of a prop entry")
		t.check(props[4].get("scale") == 1.5 and props[4].get("tag") == "deco" and props[4].get("physics") == true
			and absf(float(props[4].pitch) - deg_to_rad(10.0)) < 1e-3, "scale, tag, physics, pitch kept")
	var b2 := LevelCompiler.compile(doc, {"registries": REG})
	t.check(JSON.stringify(b2.data.props.slice(0, 3)) == JSON.stringify(props.slice(0, 3)), "barrel jitter is seeded")
	# the rest of the dict (3.8)
	t.check(float(d.get("sea_level", 0)) == -1000.0 and not d.has("water"), "no sea: sea_level -1000, no water key")
	t.check(d.get("background") == "none" and d.get("gantry") == "combine", "background none, combine arch")
	t.check(d.has("kill_y") and d.has("bg_center") and d.has("offtrack") and d.has("rescue"), "kill_y, bg_center, offtrack, rescue")
	var low := INF
	for i in m.n:
		low = minf(low, m.pos[i].y)
	low = minf(low, b.terrain.bottom())
	t.near(float(d.kill_y), low - 40.0, 0.01, "kill_y = lowest road / ground - 40")
	t.near(float(d.bg_center[1]), maxf(b.terrain.top(), 0.0) + 40.0, 0.5, "bg_center above the terrain's top")
	t.check(not d.has("type") and not d.has("map") and not d.has("terrain"), "no type / map / terrain keys")
	t.check(d.has("terrain_layers") and str(d.terrain_layers.get("base", "")) == "materials/nature/grassfloor002a.png",
		"terrain_layers as albedo paths")
	t.near(float(d.get("gantry_clear", 0)), 4.0, 1e-3, "gantry_clear = the verge width")
	t.check((d.lights as Array).size() == 1 and (d.fires as Array).size() == 1 and (d.screens as Array).size() == 1,
		"lights, fires, screens")
	t.near(float(d.screens[0].yaw), PI / 2.0, 1e-3, "screen yaw in radians")
	var sd := vec(d.env.get("sun_dir"))
	t.check(sd.is_equal_approx(Vector3(cos(deg_to_rad(30)), sin(deg_to_rad(30)), 0.0)) or sd.distance_to(Vector3(0.866, 0.5, 0.0)) < 1e-3,
		"sun {az 90, el 30} -> sun_dir")
	t.check(d.music == ["hl2_song12_long"] and d.custom.guid == doc.data.guid, "music, custom")
	for k in ["branches", "hazards", "crowd_groups", "crowds", "crowd_eggs", "low_gravity", "waters"]:
		t.check(d.get(k) is Array, "data.%s is a list" % k)
	var pit_any := false
	for i in m.n:
		pit_any = pit_any or m.pit[i] == 1
	t.check(not pit_any, "no pit on flat ground")
	# the build
	t.check(b.digest().length() == 72 and b.digest_parts().size() == 9, "digest 72 hex, 9 parts")
	var f := b.facts()
	t.check(f.raceable == true and f.errors == 0 and f.props == 5 and f.length > 800.0, "facts")
	t.check(b.meta.name == "Oval" and b.meta.guid == doc.data.guid and b.meta.raceable == true, "meta")
	t.check(int(b.stats.samples) == m.n and float(b.stats.compile_ms) > 0.0 and int(b.stats.triangles) > 0, "stats")
	t.check(b.chunks.size() == 32 and not b.skirt.is_empty(), "16 chunks x 2 LODs made on the worker (%d)" % b.chunks.size())
	# instantiate
	var root := b.instantiate()
	var roads := 0
	var tagged := true
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("road_m_"):
			roads += 1
			tagged = tagged and int(c.get_meta("level_road", 0)) == -1 and str(c.get_meta("level_group", "")).begins_with("g")
	t.check(roads > 0 and tagged, "road buckets with level_road / level_group (%d)" % roads)
	var tc := root.get_node_or_null("terrain_chunks")
	t.check(tc != null and tc.get_child_count() == 32, "terrain chunk nodes")
	var col := root.get_node_or_null("terrain_collision")
	t.check(col != null and col.get_child_count() == 4, "4 collision tiles")
	t.check(root.get_node_or_null("deco_world_edge") != null, "the edge skirt")
	var first_group := ""
	for c in root.get_children():
		if c is MeshInstance3D and c.has_meta("level_group"):
			first_group = str(c.get_meta("level_group"))
			break
	root.free()
	var part := b.instantiate(false, PackedStringArray([first_group]))
	var only := true
	for c in part.get_children():
		only = only and c is MeshInstance3D and str(c.get_meta("level_group")) == first_group and c.get_meta("no_collision", false)
	t.check(part.get_child_count() > 0 and only, "instantiate(false, [group]) makes only that group, without collision")
	part.free()


# ---------------------------------------------------------------- pits

## A road crossing a 25 m deep valley on its embankment: the carve fills the shoulders, so no pit
## on its edges (C1 M1); the same road without terrain has pits everywhere.
func _valley_case(t: Node) -> void:
	var doc := LevelDoc.blank("Valley", 512.0, 257)
	var res := doc.res()
	var cell := doc.cell()
	var org := doc.origin()
	for z in res:
		for x in res:
			var wx := org.x + x * cell
			doc.heights[z * res + x] = -25.0 if absf(wx) < 50.0 else 0.0
	oval(doc)
	var b := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	var m: LevelRoad = b.roads[0]
	var pits := 0
	for i in m.n:
		pits += m.pit[i]
	t.check(pits == 0, "no pit over the carved valley (%d)" % pits)
	t.check(not b.report.has("compile") and b.report.has("embankment"), "the embankment hint fires over the valley")
	var g := b.terrain.height_at(0.0, 110.0 + 7.0 + 6.0)
	t.check(g > -1.0, "the carve filled the valley beside the road (%.2f)" % g)


func _no_terrain_case(t: Node) -> void:
	var doc := LevelDoc.blank("Flat", 1024.0, 0)
	oval(doc, 180.0, 110.0, 20, 3.0, "asphalt", 14.0, 4.0)
	var b := LevelCompiler.compile(doc, {"registries": REG})
	var m: LevelRoad = b.roads[0]
	var pits := 0
	var low := INF
	var high := -INF
	for i in m.n:
		pits += m.pit[i]
		low = minf(low, m.pos[i].y)
		high = maxf(high, m.pos[i].y)
	t.check(pits == m.n, "no terrain: pits everywhere (%d of %d)" % [pits, m.n])
	t.check(b.terrain == null and b.chunks.is_empty() and not b.data.has("terrain_layers"), "no terrain, no chunks, no layers")
	t.near(float(b.data.kill_y), low - 40.0, 0.01, "kill_y = lowest road sample - 40")
	t.near(float(b.data.bg_center[1]), high + 40.0, 0.01, "bg_center over the highest road")
	var path: Dictionary = b.data.path
	var all_pit := true
	for v in path.pit:
		all_pit = all_pit and int(v) == 1
	t.check(all_pit, "the exported path carries pit 1")
	var root := b.instantiate()
	t.check(root.get_node_or_null("terrain_chunks") == null and root.get_child_count() > 0, "instantiate: roads only")
	root.free()
	# the sea
	doc.data.water = {"sea": true, "level": -2.0}
	var bs := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	t.check(bs.data.get("water", {}).get("level") == -2.0 and float(bs.data.sea_level) == -2.0, "sea: water + sea_level")
	t.check(bs.data.sea_center == [0.0, 0.0] and float(bs.data.sea_size) == 3072.0, "sea centre and size (world x 3)")


# ---------------------------------------------------------------- shapes

## A figure eight whose second pass over the crossing is a bridge 8 m up.
static func figure8(doc: LevelDoc, rise := 8.0, count := 24) -> Array:
	var pts := []
	for k in count:
		var ang := TAU * k / count
		var y := rise * 0.5 * (1.0 - cos(ang))
		var st := "bridge" if absf(ang - PI) < 0.9 else "asphalt"
		pts.append({"uid": doc.new_uid(), "pos": [250.0 * sin(ang), y, 120.0 * sin(2.0 * ang)], "width": 12.0, "style": st})
	doc.data.road = {"closed": true, "start": {"p": pts[3].uid, "t": 0.0}, "points": pts}
	return pts


func _figure8_case(t: Node) -> void:
	var doc := LevelDoc.blank("Eight", 1024.0, 0)
	figure8(doc)
	var b := LevelCompiler.compile(doc, {"registries": REG})
	t.check(not b.report.has("crossing") and b.report.errors() == 0, "a figure eight with an 8 m bridge: no crossing (%s)" % str(_codes(b)))
	t.check("bridge" in b.data.path.theme and "open" in b.data.path.theme, "the path has open and bridge samples")
	var deck := false
	for e in b.meshes.meshes():
		deck = deck or str(e.material) == "concrete/concretewall066a"
	t.check(deck, "bridge skirts in the meshes")
	var flat := LevelDoc.blank("Eight flat", 1024.0, 0)
	figure8(flat, 0.0)
	var bf := LevelCompiler.compile(flat, {"registries": REG})
	var it := bf.report.first("crossing")
	t.check(not it.is_empty() and absf(it.pos.x) < 20.0 and absf(it.pos.z) < 20.0, "a flat figure eight: a crossing at the middle")


func _tunnel_case(t: Node) -> void:
	var doc := LevelDoc.blank("Tunnel", 1024.0, 0)
	var pts := oval(doc, 200.0, 140.0, 20)
	for k in range(6, 11):
		pts[k]["style"] = "tunnel"
	doc.data.lights = [{"uid": doc.new_uid(), "pos": [0.0, 5.0, 0.0], "color": [1, 1, 1], "range": 10.0, "energy": 1.0},
		{"uid": doc.new_uid(), "pos": [1.0, 5.0, 0.0], "color": [1, 1, 1], "range": 10.0, "energy": 1.0}]
	var b := LevelCompiler.compile(doc, {"registries": REG})
	var lights: Array = b.data.lights
	t.check(lights.size() > 10, "tunnel lights in data.lights (%d)" % lights.size())
	t.check(lights.size() >= 2 and vec(lights[lights.size() - 1].pos) == Vector3(1, 5, 0) and vec(lights[lights.size() - 2].pos) == Vector3(0, 5, 0),
		"tunnel lights first, then the doc's")
	t.check("tunnel" in b.data.path.theme, "the path has tunnel samples")
	t.check(b.report.errors() == 0, "the tunnel road compiles clean (%s)" % str(_codes(b)))


# ---------------------------------------------------------------- determinism

func _digest_case(t: Node) -> void:
	var doc := LevelDoc.blank("Digest", 1024.0, 0)
	var pts := oval(doc)
	doc.data.items = [{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[4].uid, "t": 0.2}, "count": 0, "inset": 2.5}]
	var o := {"registries": REG}
	var b1 := LevelCompiler.compile(doc, o)
	var b2 := LevelCompiler.compile(doc, o)
	t.check(b1.digest() == b2.digest() and b1.digest() != "", "two compiles, the same digest")
	var snap := doc.snapshot()
	var moved: Array = (pts[5].pos as Array).duplicate()
	moved[0] = float(moved[0]) + 15.0
	doc.apply([LevelDoc.op_set(["road", "points", "#%d" % pts[5].uid, "pos"], moved)])
	var bs := LevelCompiler.compile(snap, o)
	t.check(bs.digest() == b1.digest(), "a snapshot taken before an edit compiles as before it")
	var be := LevelCompiler.compile(doc, o)
	t.check(be.digest() != b1.digest() and be.digest_parts().path != b1.digest_parts().path, "the edit changes the path part")
	t.check(be.digest_parts().offtrack == b1.digest_parts().offtrack, "the other parts stay")
	var joined := ""
	for k in LevelBuild.PARTS:
		joined += str(be.digest_parts()[k]).left(8)
	t.check(be.digest() == joined, "the digest is the parts' first 8 hex in order")
	# props, lights and env stay out of the digest
	doc.data.props = [{"uid": doc.new_uid(), "model": "x/y", "pos": [1.0, 0.0, 1.0], "yaw": 0.0, "pitch": 0.0, "roll": 0.0,
		"scale": 1.0, "physics": false, "tag": ""}]
	doc.data.env["exposure"] = 1.5
	t.check(LevelCompiler.compile(doc, o).digest() == be.digest(), "props and env are not in the digest")
	# compile_async: the snapshot and the revision are taken at the call
	var rev := doc.revision
	var expect := LevelCompiler.compile(doc.snapshot(), o).digest()
	var got := [null]
	var job := LevelCompiler.compile_async(doc, o, func(bb: LevelBuild) -> void: got[0] = bb)
	var moved2: Array = (pts[9].pos as Array).duplicate()
	moved2[2] = float(moved2[2]) + 12.0
	doc.apply([LevelDoc.op_set(["road", "points", "#%d" % pts[9].uid, "pos"], moved2)])
	var waited := 0
	while got[0] == null and waited < 600:
		await t.frames(1)
		waited += 1
	var ab: LevelBuild = got[0]
	t.check(job >= 0 and ab != null, "compile_async calls done on the main thread")
	if ab != null:
		t.check(ab.revision == rev and ab.digest() == expect, "compile_async builds the snapshot taken at the call (rev %d)" % ab.revision)
		t.check(doc.revision > rev, "the doc moved on meanwhile")


# ---------------------------------------------------------------- the drag preview

func _preview_case(t: Node) -> void:
	var doc := LevelDoc.blank("Preview", 2048.0, 0)
	var pts := []
	for k in 64:
		var ang := TAU * k / 64
		pts.append({"uid": doc.new_uid(), "pos": [640.0 * cos(ang), 6.0 * sin(ang * 3.0), 640.0 * sin(ang)], "width": 14.0, "style": "asphalt"})
	doc.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var prev := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	t.near(prev.roads[0].length, 4021.0, 20.0, "a 4 km loop")
	var moved: Array = (pts[33].pos as Array).duplicate()
	moved[0] = float(moved[0]) + 6.0
	doc.apply([LevelDoc.op_set(["road", "points", "#%d" % pts[33].uid, "pos"], moved)])
	var best := INF
	var pb: LevelBuild = null
	for _k in 6:
		var t0 := Time.get_ticks_usec()
		pb = LevelCompiler.preview_segments(doc, -1, PackedInt32Array([pts[33].uid]), prev)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	t.log("preview_segments of a 4 km loop: %.2f ms (road %.2f ms, meshes %.2f ms, %d samples, %d triangles, groups %s)" % [best,
		float(pb.stats.road_ms), float(pb.stats.mesh_ms), int(pb.stats.samples), int(pb.stats.triangles), str(pb.stats.groups)])
	t.check(best <= 12.0 * slack, "preview_segments of a 4 km loop <= 12 ms incl. its group meshes (%.2f ms)" % best)
	t.check(pb.partial and pb.roads.size() == 1 and pb.roads[0].partial, "a partial build of the partial road")
	var groups: PackedStringArray = pb.stats.groups
	t.check("g%d" % pts[32].uid in groups, "the dragged point's group is in stats.groups (%s)" % str(groups))
	var inside := true
	var segs := {}
	for e in pb.meshes.meshes():
		inside = inside and str(e.group) in groups
	var pr: LevelRoad = pb.roads[0]
	for i in range(pr.emit_from, pr.emit_to + 1):
		segs[pr.seg[i]] = true
	t.check(pb.meshes.meshes().size() > 0 and inside, "only those groups' meshes")
	t.check(segs.has(32) and segs.has(39), "the changed groups are emitted whole (segments 32..39)")
	# the preview agrees with the next full bake away from the window's ends
	var full := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	var fm: LevelRoad = full.roads[0].mesh_road()
	var j := pr.seg_first[35]
	var k := fm.seg_first[35]
	t.check(j >= 0 and k >= 0 and pr.pos[j].distance_to(fm.pos[k]) < 0.05, "the preview's road matches the bake at segment 35")
	var none := LevelCompiler.preview_segments(doc, 12345, PackedInt32Array([pts[33].uid]), prev)
	t.check(none.partial and none.roads.is_empty() and none.meshes.meshes().is_empty(), "an unknown road: an empty partial build")


# ---------------------------------------------------------------- leaving pieces out

func _leave_out_case(t: Node) -> void:
	var doc := LevelDoc.blank("Leave out", 1024.0, 0)
	oval(doc, 200.0, 140.0)
	var b := LevelCompiler.compile(doc, {"registries": REG, "flags": true,
		"hooks": {"branches": FakeBranches, "hazards": FakeHazards}})
	var d := b.data
	t.check(d.has("path") and b.report.blocks_drive() == "", "a failing branch and hazard do not stop the drive")
	t.check(not b.report.raceable() and not b.facts().raceable, "but the track is not raceable")
	var bn := b.report.first("branch_nose")
	t.check(not bn.is_empty() and bn.level == "error" and str(bn.text).contains("B1") and _no_format_left(str(bn.text)),
		"the left-out branch's error is kept with its text")
	var hs := b.report.first("hazard_setup")
	t.check(not hs.is_empty() and str(hs.text).contains("ceiling turret") and hs.fix == "hazard_setup" and int(hs.uid) == 9,
		"the setup-less hazard's error is kept with its fix")
	t.check((d.branches as Array).size() == 1 and d.branches[0].id == "b77" and b.roads.size() == 2, "only the kept branch is exported")
	t.check((d.hazards as Array).size() == 1 and d.hazards[0].type == "turret", "only the resolved hazard is in the data")
	t.check(b.flags.has("branch_fork") and b.flags.has("hz_tentacle") and b.flags.size() == 2 + LevelHazards.SETUP_TYPES.size(),
		"legal-spot flags from the hooks")
	var meshes_b := false
	for e in b.meshes.meshes():
		meshes_b = meshes_b or int(e.road) == 77
	t.check(meshes_b, "the kept branch has its meshes")
	var no_flags := LevelCompiler.compile(doc, {"registries": REG, "hooks": {"branches": FakeBranches, "hazards": FakeHazards}})
	t.check(no_flags.flags.is_empty(), "no flags unless asked")


# ---------------------------------------------------------------- roads that cannot race

func _open_case(t: Node) -> void:
	var doc := LevelDoc.blank("Open", 512.0, 257)
	var pts := oval(doc)
	doc.data.road.closed = false
	var b := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
	t.check(b.report.has("open_loop") and b.report.blocks_drive() != "", "an open road: open_loop blocks the drive")
	t.check(not b.data.has("path") and not b.data.has("grid") and b.data.has("sky"), "no race data, the look kept")
	t.check(b.meshes.triangles() > 0 and b.roads.size() == 1 and not b.roads[0].closed, "the open road still has its meshes")
	var e := LevelDoc.blank("Empty", 512.0, 257)
	var be := LevelCompiler.compile(e, {"registries": REG, "chunks": false})
	t.check(be.report.has("no_road") and be.report.blocks_drive() != "" and be.roads.is_empty(), "no road: no_road blocks the drive")
	t.check(be.meshes.triangles() == 0 and be.terrain != null and not be.data.has("path"), "no road: terrain only")
	t.check(be.facts().raceable == false and be.digest().length() == 72, "facts and digest of an empty track")
	var one := LevelDoc.blank("One", 512.0, 0)
	one.data.road = {"closed": false, "start": {"p": 1, "t": 0.0}, "points": [{"uid": one.new_uid(), "pos": [0, 0, 0], "width": 14.0, "style": "asphalt"}]}
	var b1 := LevelCompiler.compile(one, {"registries": REG})
	t.check(b1.report.has("open_loop") and b1.roads.is_empty(), "a single point: open_loop, nothing built")
	t.check(pts.size() == 20 and b.roads[0].n > 100, "the open road is sampled")


# ---------------------------------------------------------------- themes

func _themes_case(t: Node) -> void:
	t.check(LevelThemes.THEMES.keys() == LevelThemes.IDS and LevelThemes.IDS == LevelDoc.THEME_IDS, "seven themes, the doc's ids")
	for id in LevelThemes.IDS:
		var doc := LevelDoc.blank("Theme", 1024.0, 513)
		var ops := LevelThemes.ops(doc, id)
		t.check(ops.size() >= 3, "%s: ops" % id)
		doc.apply(ops)
		var th: Dictionary = LevelThemes.THEMES[id]
		t.check(doc.data.theme == id and doc.data.race.gantry == th.gantry and doc.data.race.background == th.background,
			"%s: theme, gantry, background" % id)
		var src := LevelThemes.circuit(id)
		if src.is_empty():
			t.check(doc.data.env.sky == th.fallback_sky, "%s: fallback sky without content" % id)
		else:
			t.check(doc.data.env.sky == src.sky, "%s: the circuit's sky" % id)
			if src.get("terrain_layers") is Dictionary:
				t.check(str(doc.data.terrain.layers.base) == LevelThemes.material_key(str(src.terrain_layers.base)),
					"%s: terrain layers as material keys" % id)
		t.check(doc.data.race.rescue in LevelDoc.RESCUES and LevelThemes.title(id) != "", "%s: rescue and title" % id)
		var rep := LevelReport.new()
		var clean := LevelDoc.sanitize(doc.data, rep)
		t.check(rep.errors() == 0 and clean.theme == id and clean.race.gantry == th.gantry and clean.env.sky == doc.data.env.sky,
			"%s: sanitize keeps the theme" % id)
		var b := LevelCompiler.compile(doc, {"registries": REG, "chunks": false})
		t.check(b.data.get("background") == th.background, "%s: compiles with its background" % id)
	t.check(LevelThemes.ops(LevelDoc.blank("x"), "nope").is_empty() and LevelThemes.title("nope") == "", "unknown theme: nothing")
	t.check(LevelThemes.material_key("materials/nature/grassfloor002a.png") == "nature/grassfloor002a"
		and LevelThemes.material_key("res://x.png") == "", "albedo path -> material key")
	var s := LevelThemes.sun_of(Vector3(0.45, 0.6, 0.55))
	var el := deg_to_rad(float(s.el))
	var az := deg_to_rad(float(s.az))
	var back := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	t.check(back.distance_to(Vector3(0.45, 0.6, 0.55).normalized()) < 1e-3, "sun_dir -> {az, el} -> sun_dir")


# ---------------------------------------------------------------- budgets (3.11)

func _budget_case(t: Node) -> void:
	var doc := LevelDoc.blank("Budget", 1024.0, 513)
	var pts := []
	for k in 40:
		var ang := TAU * k / 40
		var rr := 420.0 + 40.0 * sin(ang * 3.0)
		pts.append({"uid": doc.new_uid(), "pos": [rr * cos(ang), 10.0 * sin(ang * 2.0), rr * sin(ang)], "width": 14.0, "style": "asphalt"})
	doc.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var props := []
	for k in 1000:
		props.append({"uid": doc.new_uid(), "model": "m/%d" % (k % 20), "pos": [-300.0 + (k % 40) * 15.0, 0.0, -300.0 + (k / 40) * 25.0],
			"yaw": float(k % 360), "pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": ""})
	doc.data.props = props
	var t0 := Time.get_ticks_usec()
	var b := LevelCompiler.compile(doc, {"registries": REG})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.log("full compile, %.1f km lap, MEDIUM terrain, 1000 props: %.0f ms (%s)" % [b.roads[0].length / 1000.0, ms, str(b.stats.times)])
	t.check(b.roads[0].length > 2500.0 and ms <= 1500.0 * slack, "full compile of a 3 km lap on MEDIUM terrain <= 1.5 s (%.0f ms)" % ms)
	t0 = Time.get_ticks_usec()
	var root := b.instantiate()
	var im := (Time.get_ticks_usec() - t0) / 1000.0
	t.log("instantiate: %.0f ms (%d chunks, %d triangles)" % [im, b.chunks.size(), int(b.stats.triangles)])
	t.check(im <= 150.0 * slack, "instantiate (meshes + tiles) <= 150 ms on MEDIUM (%.0f ms)" % im)
	root.free()


# ---------------------------------------------------------------- with this install's content

## Content only: every preset style's materials exist here, the real registries keep the barrels'
## physics, and Track.dress turns the instantiated buckets into world materials and bodies.
func _content_case(t: Node) -> void:
	if not t.content():
		t.log("no content: the registry checks are skipped")
		return
	var doc := LevelDoc.blank("Content", 512.0, 257)
	var pts := oval(doc, 180.0, 110.0, 20)
	var ids := LevelStyles.PRESET_IDS
	for k in pts.size():
		pts[k]["style"] = ids[k % ids.size()]
	doc.data.barrels = [{"uid": doc.new_uid(), "road": -1, "at": {"p": pts[2].uid, "t": 0.5}}]
	var b := LevelCompiler.compile(doc)
	t.check(b.report.missing.materials == 0 and b.report.missing.skies == 0, "presets and the default sky exist here (%s)" % str(b.report.missing))
	t.check((b.data.props as Array).size() == 3 and b.data.props[0].get("physics") == true, "the drums stay physics props (35 kg)")
	var tl: Dictionary = b.data.get("terrain_layers", {})
	t.check(tl.size() == 5 and FileAccess.file_exists("res://assets/" + str(tl.base)), "terrain_layers point at albedo files (%s)" % str(tl.get("base")))
	var root := b.instantiate()
	Track.dress(root, b.data)
	var bodies := 0
	var swapped := true
	for mi in root.find_children("road_*", "MeshInstance3D", true, false):
		bodies += mi.get_child_count()
		swapped = swapped and (mi as MeshInstance3D).get_surface_override_material(0) != null
	t.check(bodies > 0 and swapped, "Track.dress gives the road buckets world materials and bodies (%d)" % bodies)
	var tm := root.find_children("terrain_*", "MeshInstance3D", true, false)
	t.check(not tm.is_empty() and (tm[0] as MeshInstance3D).get_surface_override_material(0) is ShaderMaterial,
		"the terrain chunks share the terrain shader")
	root.free()
