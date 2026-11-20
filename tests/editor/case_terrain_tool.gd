extends RefCounted
## editor/case_terrain_tool (P16, CI, fake registries): the TERRAIN tool in the editor scene over a
## 1024 m / 513 world with a loop whose points follow the ground. A dab rebuilds only the chunks
## under it (each < 6 ms), the collision tiles wait for the stroke's end and then carry the new
## ground; a stroke is one undo step, Ctrl inverts and Shift smooths; ROADS FOLLOW THE GROUND
## moves the followed points in the same step (and not with it off); the eyedropper, the brush
## keys, ADD LAKE (a rectangle drag, its level dot, one step each, compiled into a water), SHOW
## CARVE, RESIZE WORLD and NO TERRAIN.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}

var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0
var t: Node
var ed: TrackEditor
var tool: TerrainTool


func run(t_: Node) -> void:
	t = t_
	var hints0: Array = (Game.settings.get("editor_hints", []) as Array).duplicate()
	var doc := LevelDoc.blank("Terrain tool", 1024.0, 513)
	var pts := []
	for k in 24:
		var a := TAU * k / 24
		pts.append({"uid": doc.new_uid(), "pos": [300.0 * cos(a), 0.3, 300.0 * sin(a)], "width": 14.0, "style": "asphalt",
			"follow": true})
	doc.data["road"] = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": REG, "flags": true})
	var s := EditorSession.current()
	s._take(doc)
	s.build = b
	ed = load("res://scenes/editor.tscn").instantiate()
	t.get_tree().root.add_child(ed)
	ed.view.flush()
	ed.set_tool("terrain")
	tool = ed.tool as TerrainTool
	t.check(tool != null and tool.kinds() == PackedStringArray(["lake"]), "TERRAIN is the tool, its kind is lake")
	tool.throttle = 0.0
	tool.set_brush("raise")
	tool.size = 10.0
	tool.strength = 0.5
	tool.falloff = "smooth"
	tool.follow = true
	tool.target = NAN
	await _quiet()
	await _dab_chunks()
	await _follow(pts)
	await _lake()
	await _paint()
	_world_ops()
	await _quiet()
	ed.queue_free()
	await t.frames(2)
	s.close()
	HintCard._set_seen(hints0)


## Waits until no bake is due, running or being applied.
func _quiet() -> void:
	for k in 900:
		if ed._bake_t < 0.0 and not ed.baking() and not ed.view.busy():
			return
		await t.frames(1)
	t.fail("the editor never settled")


func _hit(x: float, z: float) -> EditorHit:
	var h := EditorHit.new()
	h.hit = true
	h.what = "terrain"
	h.pos = Vector3(x, 0.0, z)
	return h


func _ids(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = (d[k] as Object).get_instance_id() if is_instance_valid(d[k]) else 0
	return out


func _changed(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	for k in after:
		if before.get(k, -1) != after[k]:
			out.append(k)
	out.sort()
	return out


func _nat(x: float, z: float) -> float:
	return tool.natural_at(Vector2(x, z))


func _dab_chunks() -> void:
	var tr := ed.terrain()
	t.check(tr != null and tr.res == 513, "the live terrain is the bake's (513)")
	var chunks0 := _ids(ed.view.chunk_nodes())
	var tiles0 := _ids(ed.view.tile_nodes())
	t.check(chunks0.size() == 2 * 64 and tiles0.size() == 16, "64 chunks x 2 LODs and 16 tiles are up (%d, %d)" % [chunks0.size(), tiles0.size()])
	# the middle of chunk (4, 4): x = z = -512 + 4.5 x 128 = 64 m
	var steps := 0
	var hist := ed.history.position()
	ed._dragging = "tool"   # what TrackEditor sets while a tool owns the drag
	t.check(tool.drag_begin(_hit(60.0, 64.0), 0), "a drag on the ground starts a stroke")
	var first := tool.last_dab.duplicate()
	var chunks1 := _ids(ed.view.chunk_nodes())
	var moved := _changed(chunks0, chunks1)
	t.check(moved == ["terrain_4_4"], "a dab rebuilds only its chunk, the near LOD (the far one at the stroke's end) (%s)" % str(moved))
	var costs := [float(first.ms)]
	for k in 4:
		tool.drag_move(_hit(60.0 + (k + 1) * 2.5, 64.0), 0)
		costs.append(float(tool.last_dab.ms))
		steps += 1
	var best: float = costs.min()
	var rect: Rect2i = first.rect
	var only_mesh: float = t.ms(func() -> void: ed.view.update_terrain(rect, false))
	var t_refresh: float = t.ms(func() -> void: ed.refresh_terrain(rect, false))
	t.log("dabs: %s ms for %d chunk(s) each (%s); TrackEditor.refresh_terrain %.2f ms of it, the chunk's two LOD meshes %.2f ms" % [
		str(costs.map(func(x: float) -> float: return snappedf(x, 0.01))), int(first.chunks), str(rect), t_refresh, only_mesh])
	t.check(only_mesh / maxf(float(first.chunks), 1.0) < 6.0 * slack, "a chunk rebuild (both LODs) < 6 ms (%.2f ms)" % only_mesh)
	t.check(best < 16.0 * slack, "a whole dab (brush, copy, local carve, chunk) fits a 60 Hz frame (best %.2f ms)" % best)
	t.check(_changed(tiles0, _ids(ed.view.tile_nodes())).is_empty(), "no collision tile changes during the stroke")
	t.check(ed.history.position() == hist, "nothing is in the history before the stroke ends")
	var mid_y := ed.terrain().natural_at(64.0, 64.0)
	t.check(mid_y > 0.5, "the live terrain shows the raised ground during the stroke (%.2f m)" % mid_y)
	tool.drag_end(_hit(70.0, 64.0), 0)
	ed._dragging = ""
	var tiles1 := _ids(ed.view.tile_nodes())
	t.check(_changed(tiles0, tiles1) == ["col_terrain_2_2"], "at the stroke's end the tile under it is rebuilt (%s)" % str(_changed(tiles0, tiles1)))
	t.check(_changed(chunks1, _ids(ed.view.chunk_nodes())).has("terrain_lod_4_4"), "and the far LOD of its chunk")
	t.check(ed.history.position() == hist + 1 and ed.history.undo_name() == "TERRAIN: RAISE", "the stroke is one undo step (%s)" % ed.history.undo_name())
	var top := _nat(64.0, 64.0)
	t.check(top > 1.0 and top <= 5.0, "the ground went up (%.2f m)" % top)
	await t.frames(2)
	var q := PhysicsRayQueryParameters3D.create(Vector3(64, 100, 64), Vector3(64, -100, 64), 1)
	var r := ed.get_world_3d().direct_space_state.intersect_ray(q)
	t.check(not r.is_empty() and absf(float(r.position.y) - top) < 0.1, "the collision carries the new ground (%s vs %.2f)" % [str(r.get("position", "none")), top])
	# undo / redo
	var heights_after := ed.doc.heights.duplicate()
	ed.history.undo()
	t.check(absf(_nat(64.0, 64.0)) < 1e-6 and absf(ed.terrain().natural_at(64.0, 64.0)) < 1e-6, "undo puts the ground back (doc and live terrain)")
	ed.history.redo()
	t.check(ed.doc.heights == heights_after, "redo puts the stroke back")
	# a click is a one-dab stroke; Ctrl inverts, Shift smooths
	var c0 := _nat(64.0, 64.0)
	var n0 := ed.history.position()
	tool.click(_hit(64.0, 64.0), EditorTool.MOD_CTRL)
	t.check(_nat(64.0, 64.0) < c0 and ed.history.undo_name() == "TERRAIN: LOWER" and ed.history.position() == n0 + 1, "Ctrl + click with RAISE lowers (one step)")
	tool.click(_hit(64.0, 64.0), EditorTool.MOD_SHIFT)
	t.check(ed.history.undo_name() == "TERRAIN: SMOOTH", "Shift + click smooths")
	# the eyedropper and FLATTEN
	tool.picking = true
	tool.click(_hit(64.0, 64.0), 0)
	t.check(tool.brush == "flatten" and is_equal_approx(tool.target, snappedf(_nat(64.0, 64.0), 0.01)), "PICK HEIGHT: the target is the ground's (%.2f)" % tool.target)
	tool.target = 3.0
	tool.strength = 1.0
	tool.click(_hit(-200.0, -200.0), 0)
	t.check(absf(_nat(-200.0, -200.0) - 3.0) < 0.01, "FLATTEN to the picked height")
	# the brush keys
	var ev := InputEventAction.new()
	ev.action = "ed_brush_bigger"
	ev.pressed = true
	tool.key(ev)
	t.check(is_equal_approx(tool.size, 12.5), "] makes the brush 1.25 x (%.1f)" % tool.size)
	ev.action = "ed_brush_smaller"
	tool.key(ev)
	t.check(is_equal_approx(tool.size, 10.0), "[ makes it 0.8 x")
	ev.action = "ed_strength_down"
	tool.key(ev)
	t.check(is_equal_approx(tool.strength, 0.95), "Shift + [ takes 0.05 off the strength")
	tool.set_size(500.0)
	t.check(tool.size == TerrainTool.SIZE_MAX, "SIZE stops at 200 m")
	tool.set_size(10.0)
	tool.set_brush("raise")
	tool.strength = 0.5
	t.check(tool.hints(EditorHit.new()).size() >= 4, "the status bar's hints for the brush (%d)" % tool.hints(EditorHit.new()).size())
	var opts := VBoxContainer.new()
	tool.options(opts)
	t.check(opts.get_child_count() > 10, "the tool options are built (%d rows)" % opts.get_child_count())
	opts.free()
	await _quiet()


func _follow(pts: Array) -> void:
	var p: Dictionary = pts[0]   # (300, 0.3, 0)
	var uid := int(p.uid)
	var y0 := float(ed.doc.find(uid).item.pos[1])
	var g0 := _nat(300.0, 0.0)
	var n0 := ed.history.position()
	tool.strength = 0.8
	tool.size = 30.0
	tool.drag_begin(_hit(300.0, 0.0), 0)
	tool.drag_end(_hit(300.0, 0.0), 0)
	var g1 := _nat(300.0, 0.0)
	var y1 := float(ed.doc.find(uid).item.pos[1])
	t.check(g1 - g0 > 0.5, "the stroke raised the ground under the point (%.2f m)" % (g1 - g0))
	t.check(absf((y1 - y0) - (g1 - g0)) < 0.01, "ROADS FOLLOW THE GROUND: the point rode up with it (%.3f vs %.3f)" % [y1 - y0, g1 - g0])
	var other := int(pts[12].uid)   # (-300, 0.3, 0): outside the stroke
	t.check(absf(float(ed.doc.find(other).item.pos[1]) - 0.3) < 1e-6, "a point outside the stroke stays")
	t.check(ed.history.position() == n0 + 1 and tool.last_stroke.points == 1, "the point moved in the same undo step as the stroke")
	ed.history.undo()
	t.check(absf(float(ed.doc.find(uid).item.pos[1]) - y0) < 1e-6 and absf(_nat(300.0, 0.0) - g0) < 1e-6, "one undo takes back the ground and the point")
	ed.history.redo()
	t.check(absf(float(ed.doc.find(uid).item.pos[1]) - y1) < 1e-6, "redo moves the point again")
	tool.follow = false
	var y2 := y1
	tool.click(_hit(300.0, 0.0), 0)
	t.check(absf(float(ed.doc.find(uid).item.pos[1]) - y2) < 1e-6 and tool.last_stroke.points == 0, "with ROADS FOLLOW THE GROUND off the point stays")
	tool.follow = true
	tool.size = 10.0
	tool.strength = 0.5
	await _quiet()


func _lake() -> void:
	var n0 := ed.history.position()
	tool.lake_mode = true
	t.check(tool.drag_begin(_hit(100.0, -150.0), 0), "ADD LAKE: a drag on the ground starts the rectangle")
	tool.drag_move(_hit(140.0, -120.0), 0)
	tool.drag_end(_hit(160.0, -110.0), 0)
	tool.lake_mode = false
	var lakes: Array = ed.doc.data.get("lakes", [])
	t.check(lakes.size() == 1 and ed.history.position() == n0 + 1 and ed.history.undo_name() == "ADD LAKE", "ADD LAKE makes a lake in one step")
	var lk: Dictionary = lakes[0] if not lakes.is_empty() else {}
	t.check(str(lk.get("center")) == str([130.0, -130.0]) and str(lk.get("size")) == str([60.0, 40.0]), "its centre and size are the rectangle's (%s, %s)" % [str(lk.get("center")), str(lk.get("size"))])
	t.check(float(lk.get("level", -99.0)) >= 0.3 - 1e-6, "its level sits over the ground (%.2f)" % float(lk.get("level", -99.0)))
	var u := int(lk.get("uid", 0))
	t.check(ed.selection.uids == PackedInt32Array([u]) and ed.kind_of(u) == "lake", "the new lake is selected")
	var mk := EditorMarkers.new()
	mk.begin("terrain")
	tool.markers(mk)
	t.check((mk._lists["terrain"] as Array).size() == 5, "its markers: the level dot and four corner squares")
	mk.free()
	# the level dot drags up and down (one step)
	var dot := EditorHit.new()
	dot.hit = true
	dot.what = "marker"
	dot.kind = "lake"
	dot.uid = u
	dot.sub = 0
	var n1 := ed.history.position()
	t.check(tool.drag_begin(dot, 0), "the level dot drags")
	var h := EditorHit.new()
	for y in [5.0, 8.0, 12.0]:
		h = EditorHit.new()
		h.ray_from = Vector3(130.0, y, -330.0)
		h.ray_dir = Vector3(0, 0, 1)
		tool.drag_move(h, 0)
	tool.drag_end(h, 0)
	t.check(is_equal_approx(float(ed.doc.find(u).item.level), 12.0) and ed.history.position() == n1 + 1 and ed.history.undo_name() == "LAKE LEVEL", "LEVEL follows the mouse, one step (%.2f)" % float(ed.doc.find(u).item.level))
	# a corner resizes it
	var cn := EditorHit.new()
	cn.hit = true
	cn.what = "marker"
	cn.kind = "lake"
	cn.uid = u
	cn.sub = 3   # +x +z corner: the -x -z corner stays
	tool.drag_begin(cn, 0)
	tool.drag_move(_hit(200.0, -100.0), 0)
	tool.drag_end(_hit(200.0, -100.0), 0)
	var lk2: Dictionary = ed.doc.find(u).item
	t.check(str(lk2.size) == str([100.0, 50.0]) and str(lk2.center) == str([150.0, -125.0]), "a corner drag resizes it, the other corner stays (%s %s)" % [str(lk2.size), str(lk2.center)])
	var box := tool.item_aabb(u)
	t.check(box.has_volume() and is_equal_approx(box.size.x, 100.0), "item_aabb is the lake's box")
	var b := LevelCompiler.compile(ed.doc, {"id": CustomTracks.EDIT_ID, "registries": REG})
	var w: Array = b.data.get("waters", [])
	t.check(w.size() == 1 and is_equal_approx(float(w[0].level), 12.0), "the compiler makes the lake a water at its level")
	var dops := tool.delete_ops(PackedInt32Array([u]))
	ed.commit("DELETE", dops)
	t.check((ed.doc.data.lakes as Array).is_empty(), "delete_ops removes it")
	ed.history.undo()
	t.check((ed.doc.data.lakes as Array).size() == 1, "and undo brings it back")
	await _quiet()


## PAINT: a stroke is one undo step on the splat, the eyedropper, Ctrl erases, AUTO PAINT and
## LAYER TEXTURES are one step each.
func _paint() -> void:
	ed.set_tool("paint")
	var pt := ed.tool as PaintTool
	t.check(pt != null, "PAINT is the tool")
	pt.throttle = 0.0
	pt.set_layer(2)
	pt.size = 8.0
	pt.strength = 1.0
	pt.falloff = "flat"
	var doc := ed.doc
	var org := doc.origin()
	var i := roundi((100.0 - org.y) / doc.cell()) * doc.res() + roundi((-95.0 - org.x) / doc.cell())
	var before := doc.splat.duplicate()
	var n0 := ed.history.position()
	ed._dragging = "tool"
	pt.drag_begin(_hit(-100.0, 100.0), 0)
	pt.drag_move(_hit(-95.0, 100.0), 0)
	pt.drag_end(_hit(-90.0, 100.0), 0)
	ed._dragging = ""
	t.check(doc.splat[i * 4 + 1] == 255 and ed.terrain().splat[i * 4 + 1] == 255, "PAINT ROCK: the splat and the live terrain")
	t.check(ed.history.position() == n0 + 1 and ed.history.undo_name() == "PAINT: ROCK", "a paint stroke is one undo step")
	var after := doc.splat.duplicate()
	ed.history.undo()
	t.check(doc.splat == before, "undo restores the splat exactly")
	ed.history.redo()
	t.check(doc.splat == after, "redo paints it again")
	pt.set_layer(4)
	pt.picking = true
	pt.click(_hit(-95.0, 100.0), 0)
	t.check(pt.layer == 2, "PICK LAYER: the strongest layer under the cursor (ROCK)")
	pt.click(_hit(-95.0, 100.0), EditorTool.MOD_CTRL)
	t.check(doc.splat[i * 4 + 1] == 0 and ed.history.undo_name() == "PAINT: BASE", "Ctrl + click erases to BASE")
	var r := ed.build.roads[0] if ed.build != null and not ed.build.roads.is_empty() else null
	pt.auto = {"rock": true, "slope": 32.0, "sand": false, "sand_below": 0.0, "dirt": 3.0}
	var n1 := ed.history.position()
	t.check(pt.auto_paint() and ed.history.position() == n1 + 1 and ed.history.undo_name() == "AUTO PAINT", "AUTO PAINT is one undo step")
	if r != null:
		var k := r.n / 4
		var q: Vector3 = r.pos[k] + r.flat_right[k] * (r.width[k] * 0.5 + r.treatment(k, 1) + 1.0)
		var j := roundi((q.z - org.y) / doc.cell()) * doc.res() + roundi((q.x - org.x) / doc.cell())
		t.check(doc.splat[j * 4] == 255, "AUTO PAINT: DIRT beside the road's edge")
	pt.set_texture("rock", "nature/rockfloor005a")
	t.check(str(doc.data.terrain.layers.rock) == "nature/rockfloor005a" and ed.history.undo_name() == "LAYER TEXTURE: ROCK", "LAYER TEXTURES: one step")
	pt.set_texture("rock", "../../x")
	t.check(str(doc.data.terrain.layers.rock) == "nature/rockfloor005a", "a bad material key is refused")
	var opts := VBoxContainer.new()
	pt.options(opts)
	t.check(opts.get_child_count() > 10, "PAINT's options are built")
	opts.free()
	ed.set_tool("terrain")
	tool = ed.tool as TerrainTool
	await _quiet()


func _world_ops() -> void:
	# SHOW CARVE: the natural ground on and off
	var c0 := _ids(ed.view.chunk_nodes())
	tool.set_show_carve(false)
	var c1 := _ids(ed.view.chunk_nodes())
	t.check(tool._natural_shown and _changed(c0, c1).size() == c0.size(), "SHOW CARVE off rebuilds every chunk from the natural ground")
	tool.set_show_carve(true)
	t.check(not tool._natural_shown and _changed(c1, _ids(ed.view.chunk_nodes())).size() == c0.size(), "and on again from the carved one")
	# RESIZE WORLD and NO TERRAIN, one step each
	var n0 := ed.history.position()
	var h0 := ed.doc.heights.duplicate()
	t.check(not tool.resize_world(1000.0, 513), "RESIZE WORLD refuses a pair the format does not allow")
	t.check(tool.resize_world(2048.0, 513) and ed.doc.res() == 513 and is_equal_approx(ed.doc.world_size(), 2048.0), "RESIZE WORLD to 2048 m")
	t.check(ed.history.position() == n0 + 1 and ed.history.undo_name() == "RESIZE WORLD", "one undo step")
	ed.history.undo()
	t.check(ed.doc.heights == h0 and is_equal_approx(ed.doc.world_size(), 1024.0), "undo gives the old world back")
	tool.set_terrain(false)
	t.check(not ed.doc.has_terrain() and ed.history.undo_name() == "NO TERRAIN", "NO TERRAIN")
	t.check(not tool.drag_begin(_hit(0.0, 0.0), 0), "no stroke without terrain")
	ed.history.undo()
	t.check(ed.doc.has_terrain() and ed.doc.heights == h0, "undo brings the ground back")
