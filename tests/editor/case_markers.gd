extends RefCounted
## editor/case_markers (P7, CI): screen-space markers (C2 M1). In a top view of a 1 km world a
## 14 px marker is picked within 10 px and not beyond, nearest first, a big item by its projected
## size; a dimmed kind is click-through; issue pins are pickable in every tool, rescue pins never;
## hidden uids are neither; rectangle picks take only live kinds; begin() clears one tool's list.
## Also EditorDraw (polyline_colors, flags_on_road, strip_on_road, the flush) and the free area.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}
const S := EditorMarkers.Shape


func run(t: Node) -> void:
	var root := Node3D.new()
	root.name = "CaseMarkers"
	t.get_tree().root.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1024.0
	cam.far = 2000.0
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, 600, 0))
	cam.current = true
	var layer := CanvasLayer.new()
	layer.layer = 9
	root.add_child(layer)
	var m := EditorMarkers.new()
	layer.add_child(m)
	m.camera = cam
	await t.frames(2)
	var vs := cam.get_viewport().get_visible_rect().size
	t.log("viewport %s, %.2f px per metre" % [str(vs), vs.y / cam.size])
	_top_view(t, m, cam)
	_issues(t, m, cam)
	m.queue_redraw()
	await t.frames(2)
	t.check(true, "markers draw in top view without errors")
	_perspective(t, m, cam)
	await t.frames(1)
	root.queue_free()
	await t.frames(1)
	_draw_case(t)
	_free_area(t)


func _top_view(t: Node, m: EditorMarkers, cam: Camera3D) -> void:
	var ppm := cam.get_viewport().get_visible_rect().size.y / cam.size   # px per metre
	m.begin("road")
	m.add("road_point", 11, Vector3(100, 0, -200), S.DOT, Color.WHITE)
	m.add("road_point", 13, Vector3(100.0 + 26.0 / ppm, 0, -200), S.DOT, Color.WHITE)
	m.add("handle", 11, Vector3(100.0 + 7.0 / ppm, 0, -200), S.SQUARE, Color.WHITE, 2.0, 2)
	m.begin("objects")
	m.add("prop", 12, Vector3(-150, 0, 50), S.DOT, Color.WHITE)
	m.add("prop", 14, Vector3(200, 0, 200), S.DOT, Color.WHITE, 40.0)
	m.set_live(PackedStringArray(["road_point", "handle"]))
	var p := cam.unproject_position(Vector3(100, 0, -200))
	t.check(m.pixel_size(m.entries("road")[0], cam) == EditorMarkers.SIZE, "a 2 m item in a 1 km top view is drawn at 14 px (%.1f)" % m.pixel_size(m.entries("road")[0], cam))
	var hit := m.pick(p + Vector2(-9.0, 0.0), cam)
	t.check(int(hit.get("uid", 0)) == 11 and str(hit.get("kind", "")) == "road_point", "picked 9 px off (%s)" % str(hit))
	hit = m.pick(p + Vector2(-6.0, -6.5), cam)
	t.check(int(hit.get("uid", 0)) == 11, "picked 8.8 px off diagonally")
	t.check(m.pick(p + Vector2(-12.0, 0.0), cam).is_empty(), "not picked 12 px off")
	hit = m.pick(p + Vector2(6.0, 0.0), cam)
	t.check(str(hit.get("kind", "")) == "handle" and int(hit.get("sub", 0)) == 2, "nearest first: the handle 1 px away beats its point 6 px away (%s)" % str(hit))
	var q := cam.unproject_position(Vector3(-150, 0, 50))
	t.check(m.pick(q, cam).is_empty(), "a dim kind (prop under ROAD) is click-through")
	t.check(m.pick_kinds(q, cam, PackedStringArray(["prop"])).get("uid", 0) == 12, "pick_kinds makes it count")
	var r := m.pick_rect(Rect2(p - Vector2(20, 20), Vector2(40, 40)), cam)
	t.check(r.size() == 2 and r[0].kind == "road_point", "rectangle pick: the live point and its handle, no prop (%s)" % str(r))
	m.set_live(PackedStringArray(["*"]))
	t.check(int(m.pick(q, cam).get("uid", 0)) == 12, "SELECT (*): every kind is pickable")
	var big := cam.unproject_position(Vector3(200, 0, 200))
	var bpx := m.pixel_size(m.entries("objects")[1], cam)
	t.check(bpx > 30.0 and bpx <= EditorMarkers.MAX_PX, "a 40 m item grows to its projected size (%.1f px)" % bpx)
	t.check(int(m.pick(big + Vector2(15.0, 0.0), cam).get("uid", 0)) == 14, "and is picked within half of it")
	t.check(m.pick_rect(Rect2(Vector2.ZERO, cam.get_viewport().get_visible_rect().size), cam).size() == 5, "a full-screen rectangle takes all five")
	m.set_selected(PackedInt32Array([12]))
	m.set_hover("prop", 12)
	m.set_hidden(PackedInt32Array([12]))
	t.check(m.pick(q, cam).is_empty() and m.pick_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), cam).is_empty(), "a hidden uid is not picked")
	m.set_hidden(PackedInt32Array())
	var before := m.count()
	m.begin("road")
	t.check(m.count() == before - 3 and m.entries("objects").size() == 2, "begin(road) clears only the road tool's entries")
	m.add("road_point", 11, Vector3(100, 0, -200), S.DOT, Color.WHITE)


func _issues(t: Node, m: EditorMarkers, cam: Camera3D) -> void:
	var rep := LevelReport.new()
	rep.error("too_tight", "This bend is too tight.", {"uid": 11, "pos": Vector3(-300, 0, -300)}, "smooth")
	rep.warning("steep_warn", "Steep.", {"pos": Vector3(300, 0, 300)})
	rep.info("bake_n", "info", {"pos": Vector3(0, 0, 0)})
	rep.error("no_items", "No item crates.")   # no place: no pin
	m.set_issues(rep)
	t.check(m.entries(EditorMarkers.ISSUES).size() == 2, "a pin per placed error / warning, none for info or placeless ones")
	var p := cam.unproject_position(Vector3(-300, 0, -300))
	var w := cam.unproject_position(Vector3(300, 0, 300))
	var ok := true
	for live in [PackedStringArray(["road_point"]), PackedStringArray(["prop"]), PackedStringArray(), PackedStringArray(["*"]),
			PackedStringArray(["hazard", "hazard_point"])]:
		m.set_live(live)
		var h := m.pick(p + Vector2(4, 3), cam)
		var h2 := m.pick(w, cam)
		ok = ok and str(h.get("kind", "")) == "issue" and str((h.get("issue", {}) as Dictionary).get("code", "")) == "too_tight" \
			and str(h2.get("kind", "")) == "issue" and int(h2.get("sub", -1)) == 1
	t.check(ok, "issue pins are pickable in every tool (error and warning)")
	var hit := m.pick(p, cam)
	t.check(m.issue(int(hit.get("uid", 0))).get("uid", 0) == 11, "issue(uid) gives the report item (its uid for select + frame)")
	m.set_rescues(PackedVector3Array([Vector3(-100, 0, 300)]))
	m.set_live(PackedStringArray(["*"]))
	t.check(m.entries(EditorMarkers.RESCUES).size() == 1 and m.pick(cam.unproject_position(Vector3(-100, 0, 300)), cam).is_empty(),
		"rescue pins are drawn but never picked")
	t.check(m.pick_rect(Rect2(p - Vector2(10, 10), Vector2(20, 20)), cam).is_empty(), "issue pins are not box-selected")


func _perspective(t: Node, m: EditorMarkers, cam: Camera3D) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 70.0
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.6, -1).normalized(), Vector3.UP), Vector3(0, 400, 600))
	m.set_live(PackedStringArray(["road_point"]))
	var p := cam.unproject_position(Vector3(100, 0, -200))
	t.check(not cam.is_position_behind(Vector3(100, 0, -200)) and int(m.pick(p + Vector2(0, 9), cam).get("uid", 0)) == 11,
		"a far marker in perspective is still picked 9 px off")
	m.begin("branch")
	m.add("road_point", 99, Vector3(100, 0, 900), S.DOT, Color.WHITE)
	t.check(cam.is_position_behind(Vector3(100, 0, 900)) and m.pick(cam.unproject_position(Vector3(100, 0, 900)), cam).is_empty(),
		"a marker behind the camera is never picked")


func _draw_case(t: Node) -> void:
	var doc := LevelDoc.blank("Draw", 512.0, 0)
	var pts := []
	for k in 12:
		var a := TAU * k / 12
		pts.append({"uid": doc.new_uid(), "pos": [150.0 * cos(a), 0.0, 100.0 * sin(a)], "width": 14.0, "style": "asphalt"})
	doc.data.road = {"closed": true, "start": {"p": pts[0].uid, "t": 0.0}, "points": pts}
	var b := LevelCompiler.compile(doc, {"registries": REG})
	t.check(not b.roads.is_empty() and b.roads[0].n > 100, "a road to draw on (%d samples)" % (b.roads[0].n if not b.roads.is_empty() else 0))
	if b.roads.is_empty():
		return
	var r: LevelRoad = b.roads[0]
	var d := EditorDraw.new()
	var flags := PackedByteArray()
	flags.resize(ceili(r.n / 3.0))
	for e in flags.size():
		flags[e] = 1 if e < flags.size() / 2 else 0
	var ok := Color(0, 1, 0, 0.3)
	var bad := Color(1, 0, 0, 0.3)
	d.flags_on_road(r, flags, ok, bad)
	var vc := d.vertex_count()
	t.check(vc.tris == r.n * 6, "flags_on_road: a quad per sample on a loop (%d vertices, %d samples)" % [vc.tris, r.n])
	t.check(d._tc0[0] == ok and d._tc0[d._tc0.size() - 1] == bad, "the tint is ok where the flag is 1, bad where 0")
	var per_dense := PackedByteArray()
	per_dense.resize(r.n)
	per_dense.fill(1)
	d.clear()
	d.flags_on_road(r, per_dense, ok, bad)
	t.check(d.vertex_count().tris == r.n * 6 and d._tc0[d._tc0.size() - 1] == ok, "dense flags work too")
	d.clear()
	var cols := PackedColorArray()
	for i in r.n:
		cols.append(TrackEditor.speed_color(12.0 + 28.0 * i / r.n))
	d.polyline_colors(r.pos, cols, false)
	t.check(d.vertex_count().lines == (r.n - 1) * 2 and d._lc0[0] == TrackEditor.SLOW, "polyline_colors: a segment per pair, a colour per point")
	t.check(TrackEditor.speed_color(40.0).is_equal_approx(TrackEditor.FAST) and TrackEditor.speed_color(5.0).is_equal_approx(TrackEditor.SLOW),
		"F4 colours 12 -> 40 m/s")
	d.clear()
	d.strip_on_road(r, 10.0, 30.0, -2.0, 2.0, ok)
	t.check(d.vertex_count().tris == 60, "strip_on_road 10..30 m: 10 quads (%d)" % d.vertex_count().tris)
	d.strip_on_road(r, r.length - 4.0, 4.0, -1.0, 1.0, ok)
	t.check(d.vertex_count().tris == 60 + 24, "a strip wraps round the start line")
	d.line(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	d.box(AABB(Vector3.ZERO, Vector3.ONE), Color.WHITE)
	d.circle(Vector3.ZERO, Vector3.UP, 5.0, Color.WHITE, 16)
	d.ground_circle(LevelTerrain.flat_world(512.0, 257, 3.0), Vector2.ZERO, 20.0, Color.WHITE)
	d.flush()
	t.check(d.mesh.get_surface_count() == 2, "flush: depth-tested triangles + lines on top (%d surfaces)" % d.mesh.get_surface_count())
	d.clear()
	d.flush()
	t.check(d.mesh.get_surface_count() == 0, "clear empties the mesh")
	d.free()


func _free_area(t: Node) -> void:
	var ed := TrackEditor.new()
	t.check(ed.free_rect() == Rect2(240, 44, 980, 826) and ed.free_center() == Vector2(730, 457),
		"the free area between the panels is (240, 44) 980 x 826, centre (730, 457) on 1600 x 900")
	t.check(ed.hover != null and ed.selection != null and ed.kind_of(5) == "", "a bare TrackEditor has a hover and a selection")
	ed.free()
