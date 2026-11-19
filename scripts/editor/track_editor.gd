class_name TrackEditor
extends Node3D
## The editor scene's root (scenes/editor.tscn, 7.7): input routing (click / drag threshold, wheel,
## keys), hover pick, tools, commits, bakes (async, revisions, diffed apply), preview + settle,
## legal-spot flags, the last drive's trail, test drive, save + thumbnail, hosting. P7.
##
## The window shows at once: on open and on the way back from a test drive it shows the session's
## bake when that matches the document, else the PREPARING TRACK... card stays up while a worker
## bake runs; it never compiles on the main thread. Every commit bumps the document's revision and
## schedules a background bake 0.5 s after the last edit; a bake older than the newest one started
## is dropped, the newest goes to LevelView.show_build (diffed, time-sliced), the issue pins, the
## UI's report and stats, then session.build.

signal hover_changed(hit: EditorHit)
signal baked(b: LevelBuild)

const TOOL_IDS := ["select", "road", "branch", "terrain", "paint", "objects", "items", "hazards", "crowds", "world"]

var session: EditorSession
var doc: LevelDoc
var history: EditHistory
var view: LevelView
var camera: EditorCamera
var selection: EditSelection
var gizmo: Gizmo3D
var draw: EditorDraw
var markers: EditorMarkers
var ui: EditorUI
var tools := {}                 # id -> EditorTool
var tool: EditorTool
var build: LevelBuild           # the last full bake
var preview: LevelBuild         # the last partial build (while dragging)
var hover: EditorHit
var trail := {}                 # last_drive's trail while shown

# ---------------------------------------------------------------- additions (P7)

## A press that moves less than this before release is a click (C2 M2).
const DRAG_PX := 4.0
## Seconds after the last edit before the background bake.
const BAKE_DELAY := 0.5
## The fixed panels round the free area (1.3).
const PANEL_LEFT := 240.0
const PANEL_RIGHT := 380.0
const BAR_TOP := 44.0
const BAR_BOTTOM := 30.0
## Physics pick mask: the world layer and LAYER_KNOCK, where knockable props live (C1 N6).
const PICK_MASK := 1 | 32
## How far a pick ray reaches.
const RAY_LEN := 20000.0
const MAIN_SCENE := "res://scenes/main.tscn"
const CARD_TRACK := "PREPARING TRACK..."
const CARD_DRIVE := "PREPARING TEST DRIVE..."
## Racing line / trail colours: 12 m/s blue to 40 m/s red (F4).
const SLOW := Color(0.2, 0.45, 1.0)
const FAST := Color(1.0, 0.2, 0.1)
const HOVER_COLOR := Color8(255, 155, 0)
## The kind of an item by its document section (7.6); road and branch points are worked out apart.
const SECTION_KINDS := {"props": "prop", "lights": "light", "fires": "fire", "screens": "screen", "items": "item_row",
	"crates": "crate", "pads": "pad", "barrels": "barrels", "zones": "zone", "hazards": "hazard", "crowds": "crowd",
	"eggs": "egg", "lakes": "lake"}
## Shortcut -> tool (7.4).
const TOOL_KEYS := {"ed_tool_select": "select", "ed_tool_road": "road", "ed_tool_branch": "branch",
	"ed_tool_terrain": "terrain", "ed_tool_paint": "paint", "ed_tool_objects": "objects", "ed_tool_items": "items",
	"ed_tool_hazards": "hazards", "ed_tool_crowds": "crowds", "ed_tool_world": "world"}

## F4: the racing line over the roads.
var show_line := false
## The last drive's rescue spots (red pins until the next edit or Esc).
var rescues := PackedVector3Array()
## Snapping (1.5), the shape of settings.editor_snap: on (GRID), grid (m), angle_on, angle (deg),
## surface (drop what you move onto what is under it). Handed to Gizmo3D.drag.
var snap := {"on": true, "grid": 1.0, "angle": 15.0, "angle_on": true, "surface": true}
## The status line's own text (refusals, SAVING...), the UI reads it.
var status_text := ""
## The card shown in the free area ("" none).
var card := ""
## The last toast (tests, headless runs).
var last_toast := ""
## ms of the last preview_roads and settle (tests, the status bar's debug line).
var last_preview_ms := 0.0
var last_settle_ms := 0.0
## Where settle's time went (collision, carve, chunks ms; rect).
var settle_times := {}
## Bake state for the status bar: "" | "BAKING..." | "BAKED 0.8 s" | "BAKE FAILED" | "SAVING...".
var bake_state := ""
## No window: no thumbnail render.
var headless := false

var _mouse := Vector2(-1, -1)
var _hover_dirty := false
var _press := {}                # the LMB press: {pos, mods, hit, drag, double}
var _dragging := ""             # "" | "tool" | "gizmo" | "none"
var _bake_t := -1.0
var _bake_started := -1         # revision of the newest bake started
var _bake_t0 := 0
var _waiters: Array = []        # [{rev, cb}] of bake_now
var _pending: LevelBuild        # a bake held back while a drag runs
var _preview_segs := {}         # segment index -> true: the stretch the live preview replaces
var _overlay_dirty := true
var _markers_dirty := true
var _ready_done := false


func _init() -> void:
	hover = EditorHit.new()
	selection = EditSelection.new()


func _ready() -> void:
	session = EditorSession.current()
	if not session.is_open():
		# nothing to edit (a stale scene change): back to the main menu
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	doc = session.doc
	history = session.history
	headless = DisplayServer.get_name() == "headless"
	EditorInput.apply()
	view = get_node_or_null("View") as LevelView
	if view == null:
		view = LevelView.new()
		view.name = "View"
		add_child(view)
	draw = get_node_or_null("Overlay") as EditorDraw
	if draw == null:
		draw = EditorDraw.new()
		draw.name = "Overlay"
		add_child(draw)
	gizmo = get_node_or_null("Gizmo") as Gizmo3D
	if gizmo == null:
		gizmo = Gizmo3D.new()
		gizmo.name = "Gizmo"
		add_child(gizmo)
	camera = get_node_or_null("Camera") as EditorCamera
	if camera == null:
		camera = EditorCamera.new()
		camera.name = "Camera"
		add_child(camera)
	markers = get_node_or_null("Marks/Markers") as EditorMarkers
	if markers == null:
		var cl := CanvasLayer.new()
		cl.name = "Marks"
		cl.layer = 9
		add_child(cl)
		markers = EditorMarkers.new()
		markers.name = "Markers"
		cl.add_child(markers)
	ui = get_node_or_null("UI/EditorUI") as EditorUI
	if ui == null:
		var cl := CanvasLayer.new()
		cl.name = "UI"
		cl.layer = 10
		add_child(cl)
		ui = EditorUI.new()
		ui.name = "EditorUI"
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(ui)
	if ui.theme == null:
		ui.theme = EditorKit.theme()
	markers.camera = camera
	camera.current = true
	camera.far = maxf(camera.far, 16000.0)
	camera.speed = float(Game.settings.get("editor_cam_speed", camera.speed))
	var sn = Game.settings.get("editor_snap")
	if sn is Dictionary:
		for k in sn:
			snap[k] = sn[k]
	selection.uids = session.selection.duplicate()
	selection.changed.connect(_on_selection_changed)
	for id in TOOL_IDS:
		tools[id] = _make_tool(id)
	doc.changed.connect(_on_doc_changed)
	history.changed.connect(_on_history_changed)
	view.setup(self)
	view.set_hidden(session.hidden)
	markers.set_hidden(session.hidden)
	ui.setup(self)
	_restore_view()
	set_tool(session.tool if session.tool in TOOL_IDS else "road")
	# the window shows at once: the session's bake if it is current, else a worker bake behind the card
	var sb := session.build
	if sb != null and not sb.partial and sb.revision == doc.revision:
		_apply_bake(sb)
	else:
		show_card(CARD_TRACK)
		_start_bake()
	_show_last_drive()
	_ready_done = true


func _exit_tree() -> void:
	if session != null and session.is_open() and camera != null and _ready_done:
		_store_view()


func set_tool(tool_id: String) -> void:
	if not tools.has(tool_id):
		return
	if tool != null and tool != tools[tool_id]:
		tool.deactivate()
	tool = tools[tool_id]
	if session != null:
		session.tool = tool_id
	tool.activate()
	if markers != null:
		markers.set_live(PackedStringArray(["*"]) if tool_id == "select" else tool.kinds())
	HintCard.maybe_show(self, tool_id)
	if ui != null:
		ui.refresh_tool()
		ui.refresh_inspector()
	_overlay_dirty = true
	_hover_dirty = true


## What is under the cursor, in the pick order of 1.5: a gizmo handle (8 px) > a live marker or an
## issue pin (10 px, nearest; `kinds` given: only those kinds) > a prop > the road > the terrain >
## the water.
func pick(screen: Vector2, kinds := PackedStringArray()) -> EditorHit:
	var h := _ray_hit(screen)
	if camera == null or not camera.is_inside_tree():
		return h
	if gizmo != null and gizmo.visible and gizmo.is_inside_tree():
		var gh := gizmo.pick(screen, camera)
		if gh >= 0:
			h.hit = true
			h.what = "gizmo"
			h.sub = gh
			h.pos = gizmo.global_position
			return h
	if markers != null:
		var m := markers.pick(screen, camera) if kinds.is_empty() else markers.pick_kinds(screen, camera, kinds)
		if not m.is_empty():
			h.hit = true
			h.what = "marker"
			h.kind = str(m.kind)
			h.uid = int(m.uid)
			h.sub = int(m.sub)
			h.pos = m.pos
			return h
	return _surface(h)


## The nearest road spot to the ray (analytic): the banked strip under it, else the road sample
## nearest to where the ray meets the ground.
func road_hit(screen: Vector2) -> EditorHit:
	var h := _ray_hit(screen)
	var best_t := INF
	for r in _all_roads():
		var rh := _road_ray(r, h.ray_from, h.ray_dir)
		if rh.is_empty():
			continue
		var t: float = (rh.pos as Vector3).distance_to(h.ray_from)
		if t < best_t:
			best_t = t
			_fill_road(h, r, int(rh.i), rh.pos)
			h.lat = float(rh.lat)
	if h.hit:
		return h
	var g := _ground_point(h.ray_from, h.ray_dir)
	if is_nan(g.x):
		return h
	var best_d := INF
	for r in _all_roads():
		if r.n <= 0:
			continue
		var i := r.closest(g)
		var d := Vector2(g.x - r.pos[i].x, g.z - r.pos[i].z).length()
		if d < best_d:
			best_d = d
			_fill_road(h, r, i, r.pos[i])
			h.lat = clampf(r.lateral(g, i), -r.width[i] * 0.5, r.width[i] * 0.5)
			h.pos = r.surface(i, h.lat)
	return h


## The 3D view's area between the panels (1.3; 980 x 826 at (240, 44) on 1600 x 900).
func free_rect() -> Rect2:
	var vs := Vector2(1600, 900)
	if is_inside_tree():
		vs = get_viewport().get_visible_rect().size
	return Rect2(PANEL_LEFT, BAR_TOP, maxf(vs.x - PANEL_LEFT - PANEL_RIGHT, 1.0), maxf(vs.y - BAR_TOP - BAR_BOTTOM, 1.0))


## (730, 457) on 1600 x 900: FROM HERE on a pad, F framing and the reticle use it (C1 N5).
func free_center() -> Vector2:
	return free_rect().get_center()


## One undo step through the history; the document's `changed` does the rest (view, markers, bake).
func commit(step_name: String, ops: Array, merge_key := "") -> void:
	if ops.is_empty():
		return
	if history != null:
		history.commit(step_name, ops, merge_key)
	elif doc != null:
		doc.apply(ops)


func select(uids: PackedInt32Array, add := false) -> void:
	if selection == null:
		return
	if add:
		selection.add(uids)
	else:
		selection.set_to(uids)


## The kind (7.6) of a document uid, "" when it is not in the document.
func kind_of(uid: int) -> String:
	if doc == null:
		return ""
	var f := doc.find(uid)
	if f.is_empty():
		return ""
	var sec := str(f.get("section", ""))
	if sec == "road":
		return "road_point"
	if sec == "branches":
		return "branch_point" if f.has("branch") else "branch"
	return str(SECTION_KINDS.get(sec, ""))


## From preview (if newer) or build.
func road(key: int) -> LevelRoad:
	if preview != null and not preview.roads.is_empty() and preview.roads[0].key == key \
			and (build == null or preview.revision > build.revision):
		return preview.roads[0]
	if build == null:
		return null
	for r in build.roads:
		if r.key == key:
			return r
	return null


## The view's live terrain.
func terrain() -> LevelTerrain:
	if view != null and view.terrain_live != null:
		return view.terrain_live
	return build.terrain if build != null else null


## build.flags[name] or empty.
func flags(name: String) -> PackedByteArray:
	if build == null or not (build.flags.get(name) is PackedByteArray):
		return PackedByteArray()
	return build.flags[name]


## preview_segments + view.show_roads
func preview_roads(road_key: int, point_uids: PackedInt32Array) -> void:
	if doc == null:
		return
	var t0 := Time.get_ticks_usec()
	var prev := build
	preview = LevelCompiler.preview_segments(doc, road_key, point_uids, prev)
	_note_preview()
	if view != null:
		view.show_roads(preview, preview.stats.get("groups", PackedStringArray()))
	last_preview_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_overlay_dirty = true


## Gesture end (3.4, 3.11): the changed groups' collision, then a local re-carve of the edited
## segments' influence box (old and new positions) and the chunks in it; the bake follows.
func settle(road_key: int, point_uids: PackedInt32Array) -> void:
	if doc == null:
		return
	var t0 := Time.get_ticks_usec()
	if preview == null or preview.roads.is_empty() or preview.roads[0].key != road_key or preview.revision != doc.revision:
		preview = LevelCompiler.preview_segments(doc, road_key, point_uids, build)
		_note_preview()
		if view != null:
			view.show_roads(preview, preview.stats.get("groups", PackedStringArray()))
	var groups: PackedStringArray = preview.stats.get("groups", PackedStringArray())
	var tk := Time.get_ticks_usec()
	if view != null:
		view.collide_groups(road_key, groups)
	settle_times = {"collision": (Time.get_ticks_usec() - tk) / 1000.0}
	var t := terrain()
	var old: LevelRoad = null
	if build != null:
		for r in build.roads:
			if r.key == road_key:
				old = r
	if t != null and build != null and old != null and not preview.roads.is_empty():
		var pr: LevelRoad = preview.roads[0]
		var segs := _edited_segments(road_key, point_uids)
		var tr = doc.data.get("terrain", {})
		var flat := float(tr.get("flat", 6.0)) if tr is Dictionary else 6.0
		var blend := float(tr.get("blend", 28.0)) if tr is Dictionary else 28.0
		var rect := Rect2i()
		for k in segs:
			for r in [old, pr]:
				var rr := _influence(t, r, _seg_span(r, k), flat + blend)
				if rr.has_area():
					rect = rr if not rect.has_area() else rect.merge(rr)
		if rect.has_area():
			var roads: Array = []
			for r in build.roads:
				roads.append(r)
			# the partial road carves under its own key so the skip of the old segments leaves it in
			var key := pr.key
			pr.key = -77777
			roads.append(pr)
			tk = Time.get_ticks_usec()
			t.carve(roads, flat, blend, rect, [], {road_key: segs})
			settle_times["carve"] = (Time.get_ticks_usec() - tk) / 1000.0
			pr.key = key
			tk = Time.get_ticks_usec()
			if view != null:
				view.update_terrain(rect, false)
			settle_times["chunks"] = (Time.get_ticks_usec() - tk) / 1000.0
			settle_times["rect"] = rect
	last_settle_ms = (Time.get_ticks_usec() - t0) / 1000.0
	bake_soon(BAKE_DELAY)


func bake_soon(delay := 0.5) -> void:
	_bake_t = maxf(delay, 0.0)


## done(b) once a bake of the current revision is in.
func bake_now(done: Callable) -> void:
	if doc == null:
		done.call_deferred(null)
		return
	if build != null and not build.partial and build.revision == doc.revision:
		done.call_deferred(build)
		return
	_waiters.append({"rev": doc.revision, "cb": done})
	if _bake_started != doc.revision:
		_bake_t = -1.0
		_start_bake()


func toast(text: String) -> void:
	last_toast = text
	if ui != null:
		ui.toast(text)


func status(text: String) -> void:
	status_text = text
	if ui != null:
		ui.refresh_status()


func frame(aabb: AABB) -> void:
	if camera != null:
		camera.frame(aabb, free_rect())


## Frames an issue's spot (the drawer's row, an issue pin) and selects its item.
func frame_issue(issue: Dictionary) -> void:
	if issue.is_empty():
		return
	var p = issue.get("pos", Vector3.ZERO)
	if p is Array and (p as Array).size() >= 3:
		p = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var u := int(issue.get("uid", 0))
	if u > 0 and kind_of(u) != "":
		select(PackedInt32Array([u]))
	if p is Vector3:
		frame(AABB(p - Vector3(20, 8, 20), Vector3(40, 16, 40)))


func open_dialog(d: Dialog) -> void:
	if d == null:
		return
	var layer := get_node_or_null("UI")
	(layer if layer != null else self).add_child(d)
	d.focus_default()


## "start" | "here" | "watch". Only "cannot build" refuses (1.7); with validation errors it drives.
func test_drive(from: String, screen := Vector2(NAN, NAN)) -> void:
	if session == null or doc == null:
		return
	var why := session.drive_blocker()
	if why != "":
		_refuse(why)
		return
	var opts := {"from": from if from in ["start", "here", "watch"] else "start"}
	if opts.from == "here":
		var sp := screen if not (is_nan(screen.x) or is_nan(screen.y)) else _mouse
		var h := road_hit(sp)
		if not h.hit:
			_refuse("Point at the road to drive from there.")
			return
		opts["route"] = _route_index(h.road)
		opts["s"] = h.s
		opts["lat"] = h.lat
	_store_view()
	if build != null and not build.partial and build.revision == doc.revision:
		_drive(opts)
		return
	show_card(CARD_DRIVE)
	bake_now(func(_b: LevelBuild) -> void:
		hide_card(CARD_DRIVE)
		_drive(opts))


## AUTO DRESS (4.4): LevelDress's ops on the current bake, one undo step.
func auto_dress(opts: Dictionary) -> void:
	if doc == null:
		return
	bake_now(func(b: LevelBuild) -> void:
		var ops := LevelDress.ops(doc, b, opts)
		if ops.is_empty():
			toast("Nothing to add.")
			return
		commit("AUTO DRESS", ops))


## A FIX button (1.8): LevelFixes's ops for the issue, one undo step named "FIX: <label>".
func apply_fix(issue: Dictionary) -> void:
	if doc == null or issue.is_empty():
		return
	var fix := str(issue.get("fix", ""))
	var ops := LevelFixes.ops(issue, doc, build)
	if ops.is_empty():
		toast("This one cannot be fixed automatically.")
		return
	commit("FIX: " + str(LevelFixes.LABELS.get(fix, fix.to_upper().replace("_", " "))), ops)


## SAVE (Ctrl+S) / SAVE AS (as_new: a new file from the track's name). Reuses the current bake or
## awaits the worker's with SAVING... in the status bar while input stays live; renders a thumbnail
## when there is no custom one and a window exists (1.9).
func save(as_new := false) -> void:
	if session == null or doc == null or session.saving:
		return
	var target := ""
	if as_new:
		target = LevelIO.free_path(CustomTracks.mine_dir(), str(doc.data.get("name", "track")))
	bake_state = "SAVING..."
	status("SAVING...")
	_store_view()
	bake_now(func(b: LevelBuild) -> void: _save_with(b, target))


## HOST ONLINE WITH THIS TRACK (C2 S7): refused while the track has errors; saves when needed, then
## CREATE SERVER with the track picked.
func host_online() -> void:
	if session == null or doc == null:
		return
	bake_now(func(b: LevelBuild) -> void:
		var errs := b.report.errors() if b != null and b.report != null else 1
		if errs > 0 or b == null or not (b.data.get("path") is Dictionary):
			_refuse("Fix the %d error%s before you host." % [maxi(errs, 1), "" if errs == 1 else "s"])
			return
		if session.path == "" or session.dirty():
			_save_with(b, "", func(err: int) -> void:
				if err == OK:
					exit_to("host"))
			return
		exit_to("host"))


## "home" | "menu" | "host" (the UI asks about unsaved changes first).
func exit_to(where: String) -> void:
	if session == null:
		return
	_store_view()
	match where:
		"home":
			session.return_to = "home"
		"host":
			session.return_to = "host"
			session.host_track = session.track_id
		_:
			session.return_to = ""
	session.close()
	if is_inside_tree():
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


# ---------------------------------------------------------------- additions (P7)

## The card in the free area (PREPARING TRACK..., PREPARING TEST DRIVE...).
func show_card(text: String) -> void:
	card = text
	if ui != null:
		ui.show_card(text)


## Hides the card (only when it is `text`, if given).
func hide_card(text := "") -> void:
	if text != "" and card != text:
		return
	card = ""
	if ui != null:
		ui.hide_card()


## Asks for the overlay (EditorDraw) to be redrawn this frame (tools that animate).
func redraw() -> void:
	_overlay_dirty = true


## Asks every tool for its markers again this frame.
func refresh_markers() -> void:
	_markers_dirty = true


## The newest bake started (its revision) and whether one is running.
func baking() -> bool:
	return build == null or _bake_started > build.revision


## Copies the document's heights and splat in rect into the live terrain, re-carves the rect and
## rebuilds its chunks (and tiles): a brush stroke's undo, a terrain op.
func refresh_terrain(rect: Rect2i, collision: bool) -> void:
	var t := terrain()
	if t == null or doc == null or doc.heights.size() != t.natural.size() or t.res != doc.res():
		return
	var r := rect.intersection(Rect2i(0, 0, t.res, t.res))
	if not r.has_area():
		return
	var sp_ok := doc.splat.size() == t.splat.size()
	for z in range(r.position.y, r.end.y):
		var row := z * t.res
		for x in range(r.position.x, r.end.x):
			t.natural[row + x] = doc.heights[row + x]
			if sp_ok:
				for c in 4:
					t.splat[(row + x) * 4 + c] = doc.splat[(row + x) * 4 + c]
	var tr = doc.data.get("terrain", {})
	var flat := float(tr.get("flat", 6.0)) if tr is Dictionary else 6.0
	var blend := float(tr.get("blend", 28.0)) if tr is Dictionary else 28.0
	if build != null:
		t.carve(build.roads, flat, blend, r)
	if view != null:
		view.update_terrain(r, collision)


## The track's box: its road and branch points, else the middle of the world.
func track_aabb() -> AABB:
	var box := AABB()
	var first := true
	if doc != null:
		var lists: Array = [doc.data.get("road", {}).get("points", [])]
		for br in doc.data.get("branches", []):
			if br is Dictionary:
				lists.append(br.get("points", []))
		for list in lists:
			for p in list:
				if not (p is Dictionary):
					continue
				var v := LevelView._v3(p.get("pos"))
				if first:
					box = AABB(v, Vector3.ZERO)
					first = false
				else:
					box = box.expand(v)
	if first:
		var half := (doc.world_size() * 0.25) if doc != null else 128.0
		return AABB(Vector3(-half, 0, -half), Vector3(half * 2.0, 10.0, half * 2.0))
	return box.grow(10.0)


## A camera that sees the whole box from a 50 deg pitch (a new track, 1.4).
func overview(box: AABB, pitch_deg := 50.0) -> Transform3D:
	var c := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 20.0)
	var fov := deg_to_rad(camera.fov if camera != null else 70.0)
	var dist := radius / tan(fov * 0.5) * 1.05
	var p := deg_to_rad(pitch_deg)
	var eye := c + Vector3(0.0, sin(p), cos(p)) * dist
	return Transform3D(Basis.looking_at((c - eye).normalized(), Vector3.UP), eye)


## 30 m behind sample 0, 12 m up, looking at the line (Home, the thumbnail).
func start_view() -> Transform3D:
	var r := road(-1)
	if r == null or r.n < 2 or r.partial:
		return overview(track_aabb())
	var c := r.pos[0]
	var f := Vector3(r.fwd[0].x, 0.0, r.fwd[0].z).normalized()
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	var eye := c - f * 30.0 + Vector3.UP * 12.0
	return Transform3D(Basis.looking_at((c + f * 10.0 - eye).normalized(), Vector3.UP), eye)


## The mouse modifiers as EditorTool.MOD_* bits.
static func mods_of(ev: InputEvent) -> int:
	var m := 0
	if ev is InputEventWithModifiers:
		var e := ev as InputEventWithModifiers
		if e.shift_pressed:
			m |= EditorTool.MOD_SHIFT
		if e.ctrl_pressed or e.meta_pressed:
			m |= EditorTool.MOD_CTRL
		if e.alt_pressed:
			m |= EditorTool.MOD_ALT
	return m


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if doc == null or not _ready_done:
		return
	session.autosave_tick(delta)
	if _bake_t >= 0.0:
		_bake_t -= delta
		if _bake_t < 0.0:
			if _dragging != "":
				_bake_t = 0.0   # after the drag
			else:
				_start_bake()
	if _hover_dirty:
		_update_hover()
	if tool != null:
		tool.process(delta)
	if _markers_dirty:
		_refresh_markers()
	if _overlay_dirty:
		_redraw_overlay()


# ---------------------------------------------------------------- input

func _unhandled_input(ev: InputEvent) -> void:
	if doc == null or not _ready_done or tool == null:
		return
	if _blocked():
		return
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if camera.fly_input(ev):
			get_viewport().set_input_as_handled()
			return
		_mouse = mm.position
		_hover_dirty = true
		if not _press.is_empty():
			_drag_motion(mm)
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		_mouse = mb.position
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				var notches := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				if tool.wheel(_hover_or_pick(), mods_of(mb), notches):
					get_viewport().set_input_as_handled()
					return
			if camera.fly_input(ev):
				get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.alt_pressed and _press.get("alt") != true:
			if mb.pressed:
				_lmb_down(mb)
			else:
				_lmb_up(mb)
			get_viewport().set_input_as_handled()
			return
		if camera.fly_input(ev):
			get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey or ev is InputEventJoypadButton:
		if tool.key(ev):
			get_viewport().set_input_as_handled()
			return
		if _shortcut(ev):
			get_viewport().set_input_as_handled()


func _lmb_down(mb: InputEventMouseButton) -> void:
	var mods := mods_of(mb)
	var hit := pick(mb.position)
	_press = {"pos": mb.position, "mods": mods, "hit": hit, "drag": false, "double": mb.double_click}
	if mb.double_click and tool.double_click(hit, mods):
		_press["used"] = true


func _drag_motion(mm: InputEventMouseMotion) -> void:
	if _press.get("used", false):
		return
	var hit: EditorHit = _press.hit
	if not _press.drag:
		if mm.position.distance_to(_press.pos) <= DRAG_PX:
			return
		_press["drag"] = true
		if hit.what == "gizmo":
			_dragging = "gizmo"
			gizmo.drag(hit.sub, _press.pos, camera, 0, snap)
		elif tool.drag_begin(hit, _press.mods):
			_dragging = "tool"
		else:
			_dragging = "none"
	if _dragging == "gizmo":
		gizmo.drag(hit.sub, mm.position, camera, 1, snap)
	elif _dragging == "tool":
		tool.drag_move(_drag_hit(mm.position), mods_of(mm))
	_overlay_dirty = true


func _lmb_up(mb: InputEventMouseButton) -> void:
	if _press.is_empty():
		return
	var p := _press
	_press = {}
	if p.drag:
		var how := _dragging
		_dragging = ""
		if how == "gizmo":
			gizmo.drag((p.hit as EditorHit).sub, mb.position, camera, 2, snap)
		elif how == "tool":
			tool.drag_end(_drag_hit(mb.position), mods_of(mb))
		if _pending != null:
			var b := _pending
			_pending = null
			if b.revision >= _bake_started:
				_apply_bake(b)
		_overlay_dirty = true
		return
	if p.get("used", false):
		return
	click(p.hit, int(p.mods))


## A click (press + release within 4 px): an issue pin frames its spot in every tool; else the
## tool's own rule, then the common one (select, Shift adds, Ctrl toggles, nothing deselects).
func click(hit: EditorHit, mods: int) -> void:
	if hit.what == "marker" and hit.kind == "issue":
		frame_issue(markers.issue(hit.uid) if markers != null else {})
		return
	if tool.click(hit, mods):
		return
	if hit.what == "marker" or hit.what == "prop":
		if hit.uid <= 0:
			return
		if mods & EditorTool.MOD_CTRL:
			selection.toggle(hit.uid)
		else:
			select(PackedInt32Array([hit.uid]), (mods & EditorTool.MOD_SHIFT) != 0)
	elif mods == 0 and not selection.uids.is_empty():
		selection.clear()


func _shortcut(ev: InputEvent) -> bool:
	for a in TOOL_KEYS:
		if _act(ev, a):
			set_tool(TOOL_KEYS[a])
			return true
	if _act(ev, "ed_undo"):
		if history != null and history.can_undo():
			var nm := history.undo_name()
			history.undo()
			status("UNDO " + nm)
		return true
	if _act(ev, "ed_redo"):
		if history != null and history.can_redo():
			var nm := history.redo_name()
			history.redo()
			status("REDO " + nm)
		return true
	if _act(ev, "ed_copy"):
		SelectTool.copy_selection(self)
		return true
	if _act(ev, "ed_cut"):
		SelectTool.copy_selection(self, true)
		return true
	if _act(ev, "ed_paste_here"):
		SelectTool.paste(self, true)
		return true
	if _act(ev, "ed_paste"):
		SelectTool.paste(self)
		return true
	if _act(ev, "ed_duplicate"):
		SelectTool.duplicate_selection(self)
		return true
	if _act(ev, "ed_delete"):
		SelectTool.delete_selection(self)
		return true
	if _act(ev, "ed_select_all"):
		select_all()
		return true
	if _act(ev, "ed_cancel"):
		escape()
		return true
	if _act(ev, "ed_save_as"):
		save(true)
		return true
	if _act(ev, "ed_save"):
		save()
		return true
	if _act(ev, "ed_help"):
		ui.open_help()
		return true
	if _act(ev, "ed_validation"):
		if ui.has_method("toggle_validation"):
			ui.call("toggle_validation")
		return true
	if _act(ev, "ed_line"):
		show_line = not show_line
		_overlay_dirty = true
		return true
	if _act(ev, "ed_test_here"):
		test_drive("here", _mouse)
		return true
	if _act(ev, "ed_test_watch"):
		test_drive("watch")
		return true
	if _act(ev, "ed_test"):
		test_drive("start")
		return true
	if _act(ev, "ed_frame_all"):
		frame(track_aabb())
		return true
	if _act(ev, "ed_focus"):
		frame(_selection_aabb())
		return true
	if _act(ev, "ed_top"):
		camera.toggle_top(hover.pos if hover != null and hover.hit else _ground_point(camera.global_position, -camera.global_basis.z))
		if session != null:
			session.top_view = camera.top
		return true
	if _act(ev, "ed_home"):
		var xf := start_view()
		camera.global_transform = xf
		camera.go_to(xf)
		return true
	if _act(ev, "ed_drop_align"):
		SelectTool.drop_to_surface(self, true)
		return true
	if _act(ev, "ed_drop"):
		SelectTool.drop_to_surface(self, false)
		return true
	if _act(ev, "ed_unhide"):
		_set_hidden(PackedInt32Array())
		return true
	if _act(ev, "ed_hide"):
		var hid := session.hidden.duplicate()
		for u in selection.uids:
			if not (u in hid):
				hid.append(u)
		_set_hidden(hid)
		selection.clear()
		return true
	if _act(ev, "ed_raise", true):
		SelectTool.nudge_height(self, 1)
		return true
	if _act(ev, "ed_lower", true):
		SelectTool.nudge_height(self, -1)
		return true
	if _act(ev, "ed_grid"):
		snap["on"] = not bool(snap.get("on", true))
		status("GRID " + ("ON" if snap.on else "OFF"))
		return true
	# gizmo modes, only while not flying (W E R fly with the right button held)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if _act(ev, "ed_select_tool"):
			set_tool("select")
			return true
		for pair in [["ed_move", "move"], ["ed_rotate", "rotate"], ["ed_scale", "scale"]]:
			if _act(ev, pair[0]):
				gizmo.mode = pair[1]
				_overlay_dirty = true
				return true
		if _act(ev, "ed_space"):
			gizmo.local = not gizmo.local
			status("LOCAL AXES" if gizmo.local else "WORLD AXES")
			return true
	return false


## Esc: the tool's step first (tool.key), then the last drive's trail, then deselect, then the
## EDITOR MENU.
func escape() -> void:
	if not trail.is_empty() or not rescues.is_empty():
		clear_trail()
	if not selection.uids.is_empty():
		selection.clear()
		return
	if ui != null:
		ui.open_menu()


## Ctrl+A: every item of the active tool's kinds (SELECT: everything).
func select_all() -> void:
	if doc == null:
		return
	var all := tool != null and tool.id == "select"
	var kinds := tool.kinds() if tool != null else PackedStringArray()
	var out := PackedInt32Array()
	for u in doc.all_uids():
		var k := kind_of(u)
		if k != "" and (all or k in kinds):
			out.append(u)
	select(out)


## Clears the last drive's trail and rescue pins.
func clear_trail() -> void:
	trail = {}
	rescues = PackedVector3Array()
	if markers != null:
		markers.set_rescues(rescues)
	_overlay_dirty = true


func _act(ev: InputEvent, action: String, echo := false) -> bool:
	return InputMap.has_action(action) and ev.is_action_pressed(action, echo, true)


func _blocked() -> bool:
	if ui != null and ui.is_typing():
		return true
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit:
		return true
	var layer := get_node_or_null("UI")
	if layer != null:
		for c in layer.get_children():
			if c is Dialog and (c as Dialog).visible:
				return true
	return false


func _hover_or_pick() -> EditorHit:
	if hover != null and hover.screen == _mouse:
		return hover
	return pick(_mouse)


## What a drag moves over: the surface under the cursor (markers and the gizmo left out).
func _drag_hit(screen: Vector2) -> EditorHit:
	return _surface(_ray_hit(screen))


func _update_hover() -> void:
	_hover_dirty = false
	if camera == null or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return
	var h: EditorHit
	if _mouse.x < 0.0 or not free_rect().has_point(_mouse):
		h = EditorHit.new()
		h.screen = _mouse
	else:
		h = pick(_mouse)
	hover = h
	if markers != null:
		if h.what == "marker":
			markers.set_hover(h.kind, h.uid, h.sub)
		else:
			markers.set_hover("", 0, 0)
	hover_changed.emit(h)
	if ui != null:
		ui.refresh_status()
	_overlay_dirty = true


# ---------------------------------------------------------------- picking

func _ray_hit(screen: Vector2) -> EditorHit:
	var h := EditorHit.new()
	h.screen = screen
	if camera != null and camera.is_inside_tree():
		h.ray_from = camera.project_ray_origin(screen)
		h.ray_dir = camera.project_ray_normal(screen)
	return h


## prop > road > terrain > water along the ray (physics first, the analytic road and terrain when
## nothing solid is there yet: a preview, a bake still being applied, a headless frame).
func _surface(h: EditorHit) -> EditorHit:
	var from := h.ray_from
	var dir := h.ray_dir
	var best := INF
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LEN, PICK_MASK)
		q.collide_with_areas = false
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			var col: Object = res.collider
			var at: Vector3 = res.position
			best = at.distance_to(from)
			h.hit = true
			h.pos = at
			h.normal = res.normal
			var u := int(col.get_meta("level_uid", 0)) if col != null else 0
			var par: Node = (col as Node).get_parent() if col is Node else null
			if u > 0:
				h.what = "prop"
				h.uid = u
				h.kind = kind_of(u)
			elif par != null and par.has_meta("level_road"):
				h.what = "road"
				var r := road(int(par.get_meta("level_road")))
				if r == null:
					r = road(-1)   # the start line and the junction gores belong to the main loop
				if r != null and r.n > 0:
					var i := r.closest(at)
					_fill_road(h, r, i, at)
					h.lat = r.lateral(at, i)
			else:
				# a terrain tile, or world geometry without a uid (the gantry): the ground's place
				h.what = "terrain"
	if view != null:
		var sl := view.pick_shapeless(from, dir)
		if not sl.is_empty() and (sl.pos as Vector3).distance_to(from) < best:
			best = (sl.pos as Vector3).distance_to(from)
			h.hit = true
			h.what = "prop"
			h.uid = int(sl.uid)
			h.kind = kind_of(h.uid)
			h.pos = sl.pos
	var live_preview := preview != null and (build == null or preview.revision > build.revision)
	if not h.hit or (h.what == "terrain" and (live_preview or (view != null and view.busy()))):
		# a live preview or roads whose bodies are not in yet: the banked strip analytically
		for r in _all_roads():
			var rh := _road_ray(r, from, dir)
			if rh.is_empty():
				continue
			var d := (rh.pos as Vector3).distance_to(from)
			if d < best - 0.05:
				best = d
				h.hit = true
				h.what = "road"
				h.uid = 0
				h.kind = ""
				_fill_road(h, r, int(rh.i), rh.pos)
				h.lat = float(rh.lat)
				h.normal = r.up[int(rh.i)]
	if not h.hit:
		var t := terrain()
		if t != null:
			var g := t.raycast(from, dir)
			if not is_nan(g.x):
				best = g.distance_to(from)
				h.hit = true
				h.what = "terrain"
				h.pos = g
				h.normal = t.normal_at(g.x, g.z)
	var sea := _water_level()
	if not is_nan(sea) and absf(dir.y) > 1e-6:
		var tw := (sea - from.y) / dir.y
		if tw > 0.0 and tw < best and (not h.hit or h.pos.y < sea):
			h.hit = true
			h.what = "water"
			h.pos = from + dir * tw
			h.normal = Vector3.UP
			h.uid = 0
			h.road = -2
			h.sample = -1
	if h.hit and h.what in ["terrain", "water", "prop"] and h.road == -2:
		_near_road(h)
	return h


## The road fields of a hit on a road sample.
func _fill_road(h: EditorHit, r: LevelRoad, i: int, at: Vector3) -> void:
	h.hit = true
	h.what = "road"
	h.pos = at
	h.road = r.key
	h.sample = i
	h.s = r.s[i] if i < r.s.size() else i * r.step


## Fills s / lat of the nearest main-road spot for a ground hit (the status line's ROAD s .. lat ..)
## without making it a road hit.
func _near_road(h: EditorHit) -> void:
	var r := road(-1)
	if r == null or r.n <= 0 or r.partial:
		return
	var i := r.closest(h.pos)
	h.s = r.s[i] if i < r.s.size() else i * r.step
	h.lat = r.lateral(h.pos, i)


## Every road to pick on: the preview's partial road first, then the bake's (the one the preview
## replaces is still there for its other segments).
func _all_roads() -> Array[LevelRoad]:
	var out: Array[LevelRoad] = []
	if preview != null and not preview.roads.is_empty() and (build == null or preview.revision > build.revision):
		out.append(preview.roads[0])
	if build != null:
		for r in build.roads:
			out.append(r)
	return out


## LevelRoad.ray_hit, leaving out the bake road's stretch a live preview has replaced.
func _road_ray(r: LevelRoad, from: Vector3, dir: Vector3) -> Dictionary:
	var rh := r.ray_hit(from, dir)
	if rh.is_empty() or _preview_segs.is_empty() or r.partial or preview == null or preview.roads.is_empty():
		return rh
	if r.key == preview.roads[0].key and int(rh.i) < r.seg.size() and _preview_segs.has(r.seg[int(rh.i)]):
		return {}
	return rh


## The segments the live preview draws (its emitted stretch).
func _note_preview() -> void:
	_preview_segs = {}
	if preview == null or preview.roads.is_empty():
		return
	var pr: LevelRoad = preview.roads[0]
	for i in range(maxi(pr.emit_from, 0), mini(pr.emit_to + 1, pr.seg.size())):
		_preview_segs[pr.seg[i]] = true


## Where a ray meets the ground: the terrain, else the plane y = 0 (NAN vector when it never does).
func _ground_point(from: Vector3, dir: Vector3) -> Vector3:
	var t := terrain()
	if t != null:
		var g := t.raycast(from, dir)
		if not is_nan(g.x):
			return g
	if absf(dir.y) < 1e-6:
		return Vector3(NAN, NAN, NAN)
	var k := -from.y / dir.y
	if k <= 0.0:
		return Vector3(NAN, NAN, NAN)
	return from + dir * k


func _water_level() -> float:
	if doc == null:
		return NAN
	var w = doc.data.get("water", {})
	if w is Dictionary and bool(w.get("sea", false)):
		return float(w.get("level", 0.0))
	return NAN


## The TrackPath route of a road key: -1 the main loop, else the kept branch's index.
func _route_index(key: int) -> int:
	if key == -1 or build == null:
		return -1
	var k := 0
	for r in build.roads:
		if r.key == -1:
			continue
		if r.key == key:
			return k
		k += 1
	return -1


## The segments a drag of these points changes (k - 2 .. k + 1, AUTO handles move both neighbours).
func _edited_segments(road_key: int, point_uids: PackedInt32Array) -> PackedInt32Array:
	var pts: Array = []
	var closed := false
	if road_key == -1:
		var rd = doc.data.get("road", {})
		pts = rd.get("points", []) if rd is Dictionary else []
		closed = rd is Dictionary and bool(rd.get("closed", false)) and pts.size() >= 3
	else:
		for br in doc.data.get("branches", []):
			if br is Dictionary and int(br.get("uid", 0)) == road_key:
				pts = br.get("points", [])
	var ns := pts.size() if closed else pts.size() - 1
	var seen := {}
	for k in pts.size():
		if not (pts[k] is Dictionary) or not (int(pts[k].get("uid", 0)) in point_uids):
			continue
		for d in range(-2, 2):
			var sk := k + d
			if closed:
				seen[posmod(sk, ns)] = true
			elif sk >= 0 and sk < ns:
				seen[sk] = true
	var out := PackedInt32Array()
	for sk in seen:
		out.append(int(sk))
	out.sort()
	return out


## The first and last sample of segment k on a road, (-1, -1) when it has none there.
func _seg_span(r: LevelRoad, k: int) -> Vector2i:
	if r == null or k < 0 or k >= r.seg_first.size() or r.seg_first[k] < 0:
		return Vector2i(-1, -1)
	var i0 := r.seg_first[k]
	var i1 := r.n - 1
	for k2 in range(k + 1, r.seg_first.size()):
		if r.seg_first[k2] > i0:
			i1 = r.seg_first[k2]
			break
	return Vector2i(i0, mini(i1, r.n - 1))


## The terrain cells a stretch of samples (span) can carve: each sample's plan box out to half the
## width + its side treatment + reach (flat + blend), one step more.
func _influence(t: LevelTerrain, r: LevelRoad, span: Vector2i, reach: float) -> Rect2i:
	if r == null or span.x < 0 or r.n <= 0:
		return Rect2i()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var i := span.x
	var guard := 0
	while guard <= r.n:
		var rad := r.width[i] * 0.5 + maxf(r.treatment(i, 0), r.treatment(i, 1)) + reach + r.step
		var p := r.pos[i]
		lo = Vector2(minf(lo.x, p.x - rad), minf(lo.y, p.z - rad))
		hi = Vector2(maxf(hi.x, p.x + rad), maxf(hi.y, p.z + rad))
		if i == span.y:
			break
		i = r.wrap(i + 1)
		guard += 1
	var x0 := floori((lo.x - t.origin.x) / t.cell)
	var z0 := floori((lo.y - t.origin.y) / t.cell)
	var x1 := ceili((hi.x - t.origin.x) / t.cell)
	var z1 := ceili((hi.y - t.origin.y) / t.cell)
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1).intersection(Rect2i(0, 0, t.res, t.res))


func _selection_aabb() -> AABB:
	if selection == null or selection.uids.is_empty():
		return track_aabb()
	var box := AABB()
	var first := true
	for u in selection.uids:
		var b := _item_aabb(u)
		if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return track_aabb() if first else box


func _item_aabb(u: int) -> AABB:
	var k := kind_of(u)
	for t in tools.values():
		if k in (t as EditorTool).kinds():
			var b := (t as EditorTool).item_aabb(u)
			if b.has_volume() or b.position != Vector3.ZERO:
				return b
	if view != null:
		var b := view.item_aabb(u)
		if b.has_volume():
			return b
	var f := doc.find(u) if doc != null else {}
	if f.get("item") is Dictionary and f.item.get("pos") != null:
		var p := LevelView._v3(f.item.pos)
		return AABB(p - Vector3.ONE * 2.0, Vector3.ONE * 4.0)
	return AABB()


# ---------------------------------------------------------------- bakes

func _start_bake() -> void:
	if doc == null:
		return
	if _bake_started == doc.revision or (build != null and build.revision == doc.revision and not build.partial):
		return
	_bake_started = doc.revision
	_bake_t0 = Time.get_ticks_msec()
	bake_state = "BAKING..."
	if ui != null:
		ui.refresh_status()
	LevelCompiler.compile_async(doc, {"id": CustomTracks.EDIT_ID, "flags": true}, _on_bake_done)


func _on_bake_done(b: LevelBuild) -> void:
	if not is_inside_tree() or doc == null:
		return
	if b == null:
		bake_state = "BAKE FAILED"
		return
	if b.revision < _bake_started:
		return   # a newer bake is on its way: drop this one
	_serve_waiters(b)
	if _dragging != "":
		_pending = b
		return
	_apply_bake(b)


func _apply_bake(b: LevelBuild) -> void:
	build = b
	if preview != null and preview.revision <= b.revision:
		preview = null
		_preview_segs = {}
	if view != null:
		view.show_build(b)
	if markers != null:
		markers.set_issues(b.report)
	if ui != null:
		ui.set_report(b.report)
		ui.set_stats(b.stats)
	if session != null and doc != null and b.revision == doc.revision:
		session.build = b
	var failed := b.report != null and b.report.has("compile")
	bake_state = "BAKE FAILED" if failed else "BAKED %.1f s" % (float(b.stats.get("compile_ms", 0.0)) / 1000.0)
	hide_card(CARD_TRACK)
	_markers_dirty = true
	_overlay_dirty = true
	_hover_dirty = true
	if ui != null:
		ui.refresh_status()
	baked.emit(b)
	_serve_waiters(b)


func _serve_waiters(b: LevelBuild) -> void:
	if _waiters.is_empty():
		return
	var left: Array = []
	var due: Array = []
	for w in _waiters:
		if b.revision >= int(w.rev):
			due.append(w.cb)
		else:
			left.append(w)
	_waiters = left
	for cb in due:
		if (cb as Callable).is_valid():
			(cb as Callable).call(b)


# ---------------------------------------------------------------- the document changed

func _on_doc_changed(sections: PackedStringArray, uids: PackedInt32Array, rect: Rect2i) -> void:
	if not trail.is_empty() or not rescues.is_empty():
		clear_trail()
	if view != null:
		view.sync_props(uids)
		if rect.has_area():
			# collision tiles wait for the gesture's end (a brush stroke, 3.11) or the bake
			refresh_terrain(rect, _dragging == "")
	for t in tools.values():
		(t as EditorTool).on_doc_changed(sections, uids)
	_markers_dirty = true
	_overlay_dirty = true
	_hover_dirty = true
	bake_soon(BAKE_DELAY)
	if ui != null:
		ui.refresh_inspector()
		ui.refresh_status()


func _on_history_changed() -> void:
	if ui != null:
		ui.refresh_status()


func _on_selection_changed() -> void:
	if session != null:
		session.selection = selection.uids.duplicate()
	if markers != null:
		markers.set_selected(selection.uids)
	if ui != null:
		ui.refresh_inspector()
	_overlay_dirty = true


func _set_hidden(uids: PackedInt32Array) -> void:
	if session != null:
		session.hidden = uids
	if view != null:
		view.set_hidden(uids)
	if markers != null:
		markers.set_hidden(uids)
	_overlay_dirty = true


func _refresh_markers() -> void:
	_markers_dirty = false
	if markers == null:
		return
	for id in TOOL_IDS:
		markers.begin(id)
		(tools[id] as EditorTool).markers(markers)
	markers.set_selected(selection.uids)


func _redraw_overlay() -> void:
	_overlay_dirty = false
	if draw == null:
		return
	draw.clear()
	if show_line and build != null:
		for r in build.roads:
			var pts := r.line if r.line.size() == r.n else r.pos
			var cols := PackedColorArray()
			cols.resize(pts.size())
			for i in pts.size():
				cols[i] = speed_color(r.speed[i] if i < r.speed.size() else 26.0)
			draw.polyline_colors(pts, cols, false)
	if not trail.is_empty():
		var pts: PackedVector3Array = trail.get("points", PackedVector3Array())
		var sp: PackedFloat32Array = trail.get("speeds", PackedFloat32Array())
		var cols := PackedColorArray()
		cols.resize(pts.size())
		for i in pts.size():
			cols[i] = speed_color(sp[i] if i < sp.size() else 26.0)
		draw.polyline_colors(pts, cols, true)
	if preview != null and not preview.roads.is_empty() and (build == null or preview.revision > build.revision):
		draw.polyline(preview.roads[0].pos, HOVER_COLOR, false, true)
	if hover != null and hover.hit:
		if hover.what == "prop" and hover.uid > 0 and view != null:
			var box := view.item_aabb(hover.uid)
			if box.has_volume():
				draw.box(box, HOVER_COLOR)
		elif hover.what == "road" and hover.sample >= 0:
			var r := road(hover.road)
			if r != null and hover.sample < r.n and hover.sample < r.seg.size():
				var span := _seg_span(r, r.seg[hover.sample])
				if span.x >= 0:
					var w := r.width[hover.sample] * 0.5
					draw.strip_on_road(r, r.s[span.x], r.s[span.y], -w, w, Color(HOVER_COLOR, 0.25))
	if tool != null:
		tool.overlay(draw)


## The F4 / trail colour of a speed: 12 m/s blue .. 40 m/s red.
static func speed_color(v: float) -> Color:
	return SLOW.lerp(FAST, clampf((v - 12.0) / 28.0, 0.0, 1.0))


# ---------------------------------------------------------------- views, drives, saves

func _make_tool(id: String) -> EditorTool:
	match id:
		"select":
			return SelectTool.new(self)
		"road":
			return RoadTool.new(self)
		"branch":
			return BranchTool.new(self)
		"terrain":
			return TerrainTool.new(self)
		"paint":
			return PaintTool.new(self)
		"objects":
			return ObjectsTool.new(self)
		"items":
			return ItemsTool.new(self)
		"hazards":
			return HazardsTool.new(self)
		"crowds":
			return CrowdsTool.new(self)
		"world":
			return WorldTool.new(self)
	return EditorTool.new(self)


## The camera where the session (a test drive and back) or the file's header left it, else the
## whole track from a 50 deg pitch with ROAD active (a new track, 1.4).
func _restore_view() -> void:
	var xf := Transform3D()
	var have := false
	if session.has_view:
		xf = session.camera
		have = true
	elif session.path != "":
		var v = LevelIO.read_meta(session.path).get("view")
		if v is Array and (v as Array).size() >= 5:
			var b := Basis.from_euler(Vector3(deg_to_rad(float(v[4])), deg_to_rad(float(v[3])), 0.0))
			xf = Transform3D(b, Vector3(float(v[0]), float(v[1]), float(v[2])))
			have = true
	if not have:
		xf = overview(track_aabb())
		session.tool = "road"
	camera.global_transform = xf
	camera.go_to(xf)
	if session.top_view and not camera.top:
		camera.toggle_top(_ground_point(xf.origin, -xf.basis.z))
	session.camera = xf
	session.has_view = true


func _store_view() -> void:
	if session == null or camera == null or not camera.is_inside_tree():
		return
	session.camera = camera.global_transform
	session.has_view = true
	session.top_view = camera.top
	if tool != null:
		session.tool = tool.id
	if selection != null:
		session.selection = selection.uids.duplicate()


## Back from a test drive: the toast, then the trail and the rescue pins (cleared from the session).
func _show_last_drive() -> void:
	var ld: Dictionary = session.last_drive
	if ld.is_empty():
		return
	session.last_drive = {}
	var res := int(ld.get("rescues", 0))
	var best := float(ld.get("best_lap", 0.0))
	var lap := _lap_text(best) if best > 0.0 else ""
	var t := ""
	if str(ld.get("from", "")) == "watch":
		if bool(ld.get("finished", true)) or float(ld.get("stuck_at_s", -1.0)) < 0.0:
			t = "BOT LAP %s, %d RESCUE%s" % [lap if lap != "" else "-", res, "" if res == 1 else "S"]
		else:
			t = "STUCK AT s %d" % int(float(ld.get("stuck_at_s", 0.0)))
	else:
		t = "Back from the test drive: %s%d rescue%s" % ["best lap %s, " % lap if lap != "" else "", res, "" if res == 1 else "s"]
	toast(t)
	var pts = ld.get("trail", PackedVector3Array())
	var sp = ld.get("speeds", PackedFloat32Array())
	if pts is PackedVector3Array and (pts as PackedVector3Array).size() >= 2:
		trail = {"points": pts, "speeds": sp if sp is PackedFloat32Array else PackedFloat32Array()}
	var rp = ld.get("rescue_pos", PackedVector3Array())
	if rp is PackedVector3Array:
		rescues = rp
		markers.set_rescues(rescues)
	_overlay_dirty = true


static func _lap_text(sec: float) -> String:
	var m := int(sec) / 60
	return "%d:%04.1f" % [m, sec - m * 60.0]


func _refuse(why: String) -> void:
	var text := EditorKit.prompt(why)
	toast(text)
	status(text)


func _drive(opts: Dictionary) -> void:
	if view != null:
		view.keep_resources(session)
	session.start_test_drive(get_tree(), opts, func(reason: String) -> void:
		if reason != "":
			_refuse(reason))


func _save_with(b: LevelBuild, target: String, after := Callable()) -> void:
	if b != null and not doc.thumb_custom:
		await _render_thumb(b)
	_store_view()
	session.save(target, {}, func(err: int) -> void:
		bake_state = "" if err == OK else "SAVE FAILED"
		if err == OK:
			toast("Saved")
			Game.play_ui("res://assets/sound/buttons/blip1.wav")
			status("")
		else:
			status("The track could not be saved (%s)." % error_string(err))
		if ui != null:
			ui.refresh_status()
		if after.is_valid():
			after.call(err))


## Every track gets a picture (1.9): 480 x 320 from the start camera in a SubViewport of the
## editor's world, overlays hidden. Headless runs skip it.
func _render_thumb(b: LevelBuild) -> void:
	if headless or not is_inside_tree() or b == null or not (b.data.get("path") is Dictionary):
		return
	var sv := SubViewport.new()
	sv.size = Vector2i(480, 320)
	sv.world_3d = get_world_3d()
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	sv.add_child(cam)
	add_child(sv)
	cam.global_transform = start_view()
	cam.current = true
	var shown := [draw.visible, gizmo.visible]
	draw.visible = false
	gizmo.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	if img != null and not img.is_empty():
		doc.thumb = img.save_png_to_buffer()
	draw.visible = shown[0]
	gizmo.visible = shown[1]
	sv.queue_free()
