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
## settle's re-carve: ms of jobs a frame, samples per band piece.
const CARVE_BUDGET_MS := 6.0
const BAND_PIECE := 12
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
## The road hover tint: light, so the road and its items show through.
const HOVER_ALPHA := 0.12
## Tools that place at a point tint only +-SPOT_HALF m around the cursor.
const SPOT_TOOLS := ["items", "hazards", "crowds"]
const SPOT_HALF := 10.0
## The race direction's arrows and the grid slots.
const ARROW_EVERY := 50.0
const ARROW_COLOR := Color(1, 1, 1, 0.55)
## VIEW > GRID's square, in snap steps.
const GRID_STEPS := 64
## Seconds a status message shows before the tool's step line comes back.
const STATUS_S := 4.0
## The kind of an item by its document section (7.6); road and branch points are worked out apart.
const SECTION_KINDS := {"props": "prop", "lights": "light", "fires": "fire", "screens": "screen", "items": "item_row",
	"crates": "crate", "pads": "pad", "barrels": "barrels", "zones": "zone", "hazards": "hazard", "crowds": "crowd",
	"eggs": "egg", "lakes": "lake"}
## Shortcut -> tool (7.4).
## The keys that still reach the tool while the button holds a press (TrackEditor._press_key).
const PRESS_KEYS := ["ed_brush_smaller", "ed_brush_bigger", "ed_strength_down", "ed_strength_up"]
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
## Drag previews compile on a worker while the frame goes on (the road follows a frame or two
## behind the cursor) and settle's re-carve runs a chunk at a time; false (headless, unless a test
## sets it): both right away.
var async_preview := true

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
var _scale_base := Vector2i.ZERO   # the window's content scale size before the editor's UI size
var _pv_task := -1              # the WorkerThreadPool task of a preview being compiled
var _pv_out: Array = [null, 0]  # its result and start time (usec)
var _pv_next := {}              # road_key -> point_uids asked for while one compiles (newest wins)
var _carve_jobs: Array = []     # settle's local re-carve, a render chunk at a time (_carve_step)
var _carve_chunks := {}         # Vector2i -> true: the chunks those jobs rebuild when they are done
var _overlay_dirty := true
var _markers_dirty := true
var _box := AABB()                # the track's box at the last bake (the view's fog reach)
var _status_t := -1.0             # seconds left of status_text (-1: until replaced)
var _save_pending := false        # a save between its press and the write's end
var _grid_cache := {}             # VIEW > GRID's lines: {key, lines}
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
	async_preview = not headless
	apply_ui_size()
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
	if not headless:
		resume_music()
	_ready_done = true


func _exit_tree() -> void:
	if _scale_base != Vector2i.ZERO and is_inside_tree():
		get_window().content_scale_size = _scale_base   # the menus and the race at their own size
	if not _ready_done:
		return
	_pv_cancel()     # a worker preview still compiling is waited for
	_carve_clear()
	end_press(false)
	if history != null:
		history.end_gesture()
	if session != null and session.is_open() and camera != null:
		_store_view()


func set_tool(tool_id: String) -> void:
	if not tools.has(tool_id):
		return
	if tool != null and tool != tools[tool_id]:
		end_press(false)
		tool.deactivate()
	if tool != tools[tool_id]:
		status_text = ""   # the new tool's step line shows at once
		_status_t = -1.0
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


## preview_segments + view.show_roads. In a window the compile runs on a worker: one at a time,
## the newest request waiting for it (a drag of 20 ms previews kept the frame at 20 ms).
func preview_roads(road_key: int, point_uids: PackedInt32Array) -> void:
	if doc == null:
		return
	if not async_preview:
		var t0 := Time.get_ticks_usec()
		_show_preview(LevelCompiler.preview_segments(doc, road_key, point_uids, build), t0)
		return
	if _pv_task >= 0:
		_pv_next[road_key] = point_uids
		return
	_pv_launch(road_key, point_uids)


func _pv_launch(road_key: int, point_uids: PackedInt32Array) -> void:
	var snap := doc.snapshot()
	var prev := build
	var out := [null, Time.get_ticks_usec()]
	_pv_out = out
	_pv_task = WorkerThreadPool.add_task(func() -> void:
		out[0] = LevelCompiler.preview_segments(snap, road_key, point_uids, prev), false, "TrackEditor preview")


## A finished worker preview goes on show (while the drag still runs), then the waiting request.
func _pv_poll() -> void:
	if _pv_task < 0 or not WorkerThreadPool.is_task_completed(_pv_task):
		return
	WorkerThreadPool.wait_for_task_completion(_pv_task)
	_pv_task = -1
	var b = _pv_out[0]
	if b is LevelBuild and _dragging != "" and (build == null or (b as LevelBuild).revision > build.revision):
		_show_preview(b, int(_pv_out[1]))
	if _dragging == "":
		_pv_next = {}
	elif not _pv_next.is_empty():
		var key: int = _pv_next.keys()[0]
		var uids: PackedInt32Array = _pv_next[key]
		_pv_next.erase(key)
		_pv_launch(key, uids)


## Waits for a preview still compiling and drops it (settle and the bake take over).
func _pv_cancel() -> void:
	_pv_next = {}
	if _pv_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_pv_task)
		_pv_task = -1


func _show_preview(b: LevelBuild, t0: int) -> void:
	preview = b
	_note_preview()
	if view != null:
		view.show_roads(preview, preview.stats.get("groups", PackedStringArray()))
	last_preview_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_overlay_dirty = true
	if tool != null and tool.has_method("on_preview"):
		tool.call("on_preview")


## Gesture end (3.4, 3.11): the changed groups' collision, then a local re-carve of the edited
## segments' influence box (old and new positions) and the chunks in it; the bake follows.
func settle(road_key: int, point_uids: PackedInt32Array) -> void:
	if doc == null:
		return
	_pv_cancel()
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
		# the band the edited segments (old and new) can carve, in short pieces: a long diagonal
		# segment's whole box was up to 400 x 300 cells and froze the release for 0.2-0.35 s
		var pieces: Array = []
		for k in segs:
			for r in [old, pr]:
				pieces.append_array(_band(t, r, _seg_span(r, k), flat + blend))
		var by_chunk := {}
		for rr in pieces:
			for c in t.chunks_in(rr):
				# the cells chunk c's mesh reads (its vertices and the ring its normals use)
				var box := Rect2i(c.x * LevelTerrain.CHUNK - 1, c.y * LevelTerrain.CHUNK - 1, LevelTerrain.CHUNK + 3, LevelTerrain.CHUNK + 3)
				var part := (rr as Rect2i).intersection(box)
				if part.has_area():
					by_chunk[c] = part if not by_chunk.has(c) else (by_chunk[c] as Rect2i).merge(part)
		if not by_chunk.is_empty():
			var roads: Array = []
			for r in build.roads:
				roads.append(r)
			roads.append(pr)
			var rect := Rect2i()
			for c in by_chunk:
				rect = by_chunk[c] if not rect.has_area() else rect.merge(by_chunk[c])
				_carve_jobs.append({"t": t, "c": c, "rect": by_chunk[c], "roads": roads, "pr": pr, "flat": flat,
					"blend": blend, "skip": {road_key: segs}})
			settle_times["rect"] = rect
			settle_times["jobs"] = by_chunk.size()
			# the chunk nearest the cursor first
			var at := _mouse_ground()
			if not is_nan(at.x):
				var ci := Vector2((at.x - t.origin.x) / t.cell, (at.z - t.origin.y) / t.cell)
				_carve_jobs.sort_custom(func(a, b) -> bool:
					return Vector2((a.rect as Rect2i).get_center()).distance_squared_to(ci) < Vector2((b.rect as Rect2i).get_center()).distance_squared_to(ci))
			if not async_preview:
				carve_flush()
	last_settle_ms = (Time.get_ticks_usec() - t0) / 1000.0
	bake_soon(BAKE_DELAY)


## One settle job or more a frame, CARVE_BUDGET_MS in all: a render chunk's part of the band carved
## and that chunk rebuilt (jobs of a terrain the bake has replaced since are dropped).
func _carve_step() -> void:
	if _carve_jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var n := 0
	while not _carve_jobs.is_empty() and (n == 0 or (Time.get_ticks_usec() - t0) < CARVE_BUDGET_MS * 1000.0):
		var j: Dictionary = _carve_jobs.pop_front()
		n += 1
		var t: LevelTerrain = j.t
		if t == null or t != terrain():
			continue
		var pr: LevelRoad = j.pr
		var key := pr.key
		# the partial road carves under its own key so the skip of the old segments leaves it in
		pr.key = -77777
		t.carve(j.roads, float(j.flat), float(j.blend), j.rect, [], j.skip, true)
		pr.key = key
		if view != null:
			view.update_chunk(j.c)   # its neighbours have jobs of their own


## Runs every settle job now (headless, tests that look at the ground right after a release).
func carve_flush() -> void:
	while not _carve_jobs.is_empty():
		_carve_step()


## Drops settle jobs still waiting (a bake was applied, the editor closes).
func _carve_clear() -> void:
	_carve_jobs.clear()


## The cells a stretch of samples can carve, as boxes of at most BAND_PIECE samples each.
func _band(t: LevelTerrain, r: LevelRoad, span: Vector2i, reach: float) -> Array:
	var out: Array = []
	if r == null or span.x < 0 or r.n <= 0:
		return out
	var i := span.x
	var guard := 0
	while guard <= r.n:
		var j := i
		var m := 0
		while m < BAND_PIECE and j != span.y and guard + m < r.n:
			j = r.wrap(j + 1)
			m += 1
		var rr := _influence(t, r, Vector2i(i, j), reach)
		if rr.has_area():
			out.append(rr)
		if j == span.y or m == 0:
			break
		i = j
		guard += m
	return out


## Where the mouse meets the ground (NAN vector off the view).
func _mouse_ground() -> Vector3:
	if camera == null or not camera.is_inside_tree() or _mouse.x < 0.0:
		return Vector3(NAN, NAN, NAN)
	return _ground_point(camera.project_ray_origin(_mouse), camera.project_ray_normal(_mouse))


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


## The editor's UI size (VIEW > UI SIZE, settings.editor_ui_size): the 1600 x 900 canvas grows by
## 1 / size, so panels and text take that share of the screen they took before (0.85: 15 % less).
func apply_ui_size() -> void:
	if headless or not is_inside_tree():
		return
	var w := get_window()
	if _scale_base == Vector2i.ZERO:
		_scale_base = w.content_scale_size
		if _scale_base == Vector2i.ZERO:
			_scale_base = Vector2i(1600, 900)
	var f := clampf(float(Game.settings.get("editor_ui_size", 0.85)), 0.6, 1.25)
	w.content_scale_size = Vector2i(roundi(_scale_base.x / f), roundi(_scale_base.y / f))
	if camera != null:
		frame.call_deferred(_box if _box.size != Vector3.ZERO else track_aabb())


## A click that did nothing, said where the player looks: a toast and the status line.
func refuse(text: String) -> void:
	status(text)
	toast(text)


func toast(text: String) -> void:
	last_toast = text
	if ui != null:
		ui.toast(text)


## The status bar's message; it gives way to the tool's step line after STATUS_S seconds (sticky: a
## prompt that waits for a click stays until it is replaced or the tool changes).
func status(text: String, sticky := false) -> void:
	status_text = text
	_status_t = -1.0 if text == "" or sticky else STATUS_S
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
	end_press(false)
	var layer := get_node_or_null("UI")
	(layer if layer != null else self).add_child(d)
	d.focus_default()


## "start" | "here" | "watch". Only "cannot build" refuses (1.7); with validation errors it drives.
func test_drive(from: String, screen := Vector2(NAN, NAN)) -> void:
	if session == null or doc == null:
		return
	end_press(false)
	var why := session.drive_blocker()
	if why != "":
		_refuse(why)
		return
	var opts := {"from": from if from in ["start", "here", "watch"] else "start"}
	if opts.from == "watch":
		session.bot_lap = {}   # the new watch's result replaces it
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
	var ops := LevelFixes.ops(issue, doc, build)
	if ops.is_empty():
		toast("This one cannot be fixed automatically.")
		return
	commit("FIX: " + LevelFixes.label(issue), ops)


## SAVE (Ctrl+S) / SAVE AS (as_new: a new file from the track's name). Reuses the current bake or
## awaits the worker's with SAVING... in the status bar while input stays live; renders a thumbnail
## when there is no custom one and a window exists (1.9).
func save(as_new := false) -> void:
	# one save at a time: a second Ctrl+S while the bake or the thumbnail runs is dropped
	if session == null or doc == null or session.saving or _save_pending:
		return
	_save_pending = true
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
	end_press(false)
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
	# a resized world (same resolution, another cell) waits for its bake
	if t == null or doc == null or doc.heights.size() != t.natural.size() or t.res != doc.res() or not is_equal_approx(t.cell, doc.cell()):
		return
	var r := rect.intersection(Rect2i(0, 0, t.res, t.res))
	if not r.has_area():
		return
	var sp_ok := doc.splat.size() == t.splat.size()
	var moved := false   # a PAINT stroke changes the splat only: no re-carve for it
	for z in range(r.position.y, r.end.y):
		var row := z * t.res
		for x in range(r.position.x, r.end.x):
			var hv := doc.heights[row + x]
			var was := t.natural[row + x]
			if hv != was and not (is_nan(hv) and is_nan(was)):
				t.natural[row + x] = hv
				moved = true
			if sp_ok:
				for c in 4:
					t.splat[(row + x) * 4 + c] = doc.splat[(row + x) * 4 + c]
	var tr = doc.data.get("terrain", {})
	var flat := float(tr.get("flat", 6.0)) if tr is Dictionary else 6.0
	var blend := float(tr.get("blend", 28.0)) if tr is Dictionary else 28.0
	if build != null and moved:
		t.carve(build.roads, flat, blend, r, [], {}, true)
	if view != null:
		# a live stroke rebuilds the near LOD only; its end (collision) both
		view.update_terrain(r, collision, 2 if collision else 1)


## Metres from the camera to the far side of the track (the editor view's fog starts past it).
func view_reach() -> float:
	if camera == null or not camera.is_inside_tree():
		return 0.0
	var b := _box if _box.has_volume() or _box.size != Vector3.ZERO else track_aabb()
	return camera.global_position.distance_to(b.get_center()) + b.size.length() * 0.5


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
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			_status_t = -1.0
			status_text = ""
			if ui != null:
				ui.refresh_status()
	if _bake_t >= 0.0:
		_bake_t -= delta
		if _bake_t < 0.0:
			if _dragging != "":
				_bake_t = 0.0   # after the drag
			else:
				_start_bake()
	_pv_poll()
	_carve_step()
	if _hover_dirty:
		_update_hover()
	if camera != null and view != null:
		# the WORLD tool shows the fog as the race has it (its FOG rows are being set)
		camera.sync_env(view.env, view_reach(), tool != null and tool.id == "world")
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
	if ev is InputEventMouseButton:
		var b := ev as InputEventMouseButton
		# the release of a press on the view ends it even with a field or a dialog up since
		if not b.pressed and b.button_index == MOUSE_BUTTON_LEFT and not _press.is_empty():
			_mouse = b.position
			_lmb_up(b)
			get_viewport().set_input_as_handled()
			return
		# a click on the view (not on a panel) lets go of a text field; the field commits on focus_exited
		if b.pressed and b.button_index != MOUSE_BUTTON_WHEEL_UP and b.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			var fo := get_viewport().gui_get_focus_owner()
			if fo is LineEdit or fo is TextEdit:
				get_viewport().gui_release_focus()
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
		if pressing():
			_press_key(ev)
			return
		if tool.key(ev):
			get_viewport().set_input_as_handled()
			return
		if _shortcut(ev):
			get_viewport().set_input_as_handled()


## A key while the button holds a press: Esc cancels it (1.6), the brush keys still work; the rest
## (undo, tool keys, F5, save, delete, copy / paste) would cut into the drag and waits.
func _press_key(ev: InputEvent) -> void:
	if _act(ev, "ed_cancel"):
		end_press(true)
		get_viewport().set_input_as_handled()
		return
	for a in PRESS_KEYS:
		if _act(ev, a, true):
			tool.key(ev)
			break
	if ev.is_pressed():
		get_viewport().set_input_as_handled()


## A live press: the LMB is down on the view (a click or a drag), the gizmo's own Alt drag runs,
## or a SELECT drag still holds its gesture open.
func pressing() -> bool:
	return not _press.is_empty() or (gizmo != null and gizmo.busy()) or _select_dragging()


func _select_dragging() -> bool:
	var st = tools.get("select")
	return st is SelectTool and (st as SelectTool).dragging()


## Ends the live press now (Esc, a tool switch, a dialog, a test drive, leaving): the drag ends
## where the mouse is (the tool's drag_end), or with cancel stops and is taken back (cancel_drag);
## the button's later release is ignored. Bakes held back by the drag run again.
func end_press(cancel: bool) -> void:
	var p := _press
	var how := _dragging
	var gz := gizmo != null and gizmo.busy()
	var sd := _select_dragging()
	if p.is_empty() and not gz and how == "" and not sd:
		return
	_press = {}
	_dragging = ""
	if gz:
		gizmo.end_drag(_mouse, camera, snap, cancel)
		if cancel:
			var st = tools.get("select")
			if st is SelectTool:
				(st as SelectTool).cancel_gizmo()
	elif how == "tool" and tool != null:
		if cancel:
			tool.cancel_drag()
		else:
			tool.drag_end(_drag_hit(_mouse), int(p.get("mods", 0)))
	# a SELECT drag left without its press (the gizmo's signals, a lost release)
	var st = tools.get("select")
	if st is SelectTool and (st as SelectTool).dragging():
		if cancel:
			(st as SelectTool).cancel_gizmo()
			(st as SelectTool).cancel_drag()
		else:
			(st as SelectTool).end_drags()
	if history != null and (gz or sd or how != ""):
		history.end_gesture()
	_after_drag()


## A drag ended: the bake held back while it ran goes in.
func _after_drag() -> void:
	if _pending != null:
		var b := _pending
		_pending = null
		if b.revision >= _bake_started:
			_apply_bake(b)
	_overlay_dirty = true
	_hover_dirty = true


func _lmb_down(mb: InputEventMouseButton) -> void:
	if pressing():
		end_press(false)   # a release that never came
	_dragging = ""
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
		_after_drag()
		return
	_dragging = ""
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
		if pressing():
			return true   # (the menu's UNDO too) never inside a drag
		if history != null and history.can_undo():
			var nm := history.undo_name()
			history.undo()
			status("UNDO " + nm)
		return true
	if _act(ev, "ed_redo"):
		if pressing():
			return true
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
		if ui != null:
			ui.save_as()   # asks for the name, as the FILE menu does
		return true
	if _act(ev, "ed_save"):
		if ui != null:
			ui.save_named()   # the first save of a MY TRACK asks for its name
		else:
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
		var n := 0
		for u in selection.uids:
			if not (u in hid):
				hid.append(u)
				n += 1
		if n == 0:
			return true
		_set_hidden(hid)
		selection.clear()
		toast("Hidden %d · {ed_unhide} shows them" % n)
		return true
	if _act(ev, "ed_raise", true):
		SelectTool.nudge_height(self, 1)
		return true
	if _act(ev, "ed_lower", true):
		SelectTool.nudge_height(self, -1)
		return true
	if _act(ev, "ed_grid"):
		# as the GRID button: kept in the settings for the next session
		var on := not bool(snap.get("on", true))
		if ui != null:
			ui.set_snap("on", on)
		else:
			snap["on"] = on
		status("GRID " + ("ON" if on else "OFF"))
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


## Esc, one step per press (1.6): a held press is cancelled, then the tool's step (tool.key), then
## the last drive's trail goes, then deselect, then the EDITOR MENU.
func escape() -> void:
	if pressing():
		end_press(true)
		return
	if not trail.is_empty() or not rescues.is_empty():
		clear_trail()
		return
	if not selection.uids.is_empty():
		selection.clear()
		return
	if ui != null:
		ui.open_menu()


## The menu music goes on in the editor (7.7), also after a test drive stopped it; VIEW > MUSIC
## off keeps it quiet. true when it started a song.
func resume_music() -> bool:
	if Game.now_playing != "" or (ui != null and not bool(ui.view_flags.get("music", true))):
		return false
	Game.play_music_mode("menu")
	return Game.now_playing != ""


## VIEW > LABELS: the live markers' names beside them (the OUTLINER's names).
func set_labels(on: bool) -> void:
	if markers == null:
		return
	if on:
		markers.label_of = func(u: int) -> String: return Outliner.item_name(self, u) if doc != null else ""
	else:
		markers.label_of = Callable()
	markers.forget_names()


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
	_carve_clear()   # the bake's terrain is carved whole
	if preview != null and preview.revision <= b.revision:
		preview = null
		_preview_segs = {}
	if view != null:
		view.show_build(b)
	var hz = tools.get("hazards")
	if hz is HazardsTool:
		(hz as HazardsTool).sync_models()
	_box = track_aabb()
	_note_bot_lap(b)
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


## WATCH A BOT LAP's result as the checklist's info bot_lap (1.8), a pin where the bot got stuck;
## true when it was added to b's report.
func _note_bot_lap(b: LevelBuild) -> bool:
	if b == null or b.report == null or session == null or session.bot_lap.is_empty() or b.report.has("bot_lap"):
		return false
	var bl: Dictionary = session.bot_lap
	var where := {}
	if bl.has("s"):
		where["s"] = float(bl.s)
	if bl.get("pos") is Vector3:
		where["pos"] = bl.pos
	b.report.info("bot_lap", str(bl.get("line", "")), where)
	return true


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
	# a save's own meta (modified, app, content, bake): no edit, the trail stays and the bake is current
	if session != null and session.saving_meta:
		if ui != null:
			ui.refresh_status()
		return
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
		ui.refresh_status()   # "1 selected" goes at once (Esc, the pad, a click on nothing)
	_overlay_dirty = true


func _set_hidden(uids: PackedInt32Array) -> void:
	if session != null:
		session.hidden = uids
	if view != null:
		view.set_hidden(uids)
	if markers != null:
		markers.set_hidden(uids)
	var hz = tools.get("hazards")
	if hz is HazardsTool:
		(hz as HazardsTool).sync_models()
	if ui != null:
		ui.refresh_status()
	_overlay_dirty = true


func _refresh_markers() -> void:
	_markers_dirty = false
	if markers == null:
		return
	markers.forget_names()
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
				var w := r.width[hover.sample] * 0.5
				var col := Color(HOVER_COLOR, HOVER_ALPHA)
				if tool != null and tool.id in SPOT_TOOLS:
					# a tool that places at a point: only the stretch under the cursor
					var s := r.s[hover.sample]
					draw.strip_on_road(r, maxf(s - SPOT_HALF, 0.0), minf(s + SPOT_HALF, r.length), -w, w, col)
				else:
					var span := _seg_span(r, r.seg[hover.sample])
					if span.x >= 0:
						draw.strip_on_road(r, r.s[span.x], r.s[span.y], -w, w, col)
	if tool != null:
		tool.overlay(draw)
	# VIEW > ZONES: the low-gravity and hazard zones in every tool (their own tools draw them anyway)
	if ui != null and bool(ui.view_flags.get("zones", false)):
		var it = tools.get("items")
		if it is ItemsTool and tool != it:
			(it as ItemsTool).draw_zones(draw)
		var hz = tools.get("hazards")
		if hz is HazardsTool and tool != hz:
			(hz as HazardsTool).draw_zones(draw)
	if ui != null and bool(ui.view_flags.get("grid", false)):
		_draw_grid()
	_draw_race_marks()


## VIEW > GRID: lines on the ground every snap step (every 8th brighter) in a square of GRID_STEPS
## steps around the cursor (else the ground in the middle of the view).
func _draw_grid() -> void:
	var g := float(snap.get("grid", 1.0))
	if g <= 0.0 or camera == null or not camera.is_inside_tree():
		return
	var c := hover.pos if hover != null and hover.hit else _ground_point(camera.global_position, -camera.global_basis.z)
	if is_nan(c.x):
		return
	var t := terrain()
	var half := GRID_STEPS / 2
	var ox := floorf(c.x / g) * g
	var oz := floorf(c.z / g) * g
	var y0 := c.y
	# the lines are made again only when the square moves a step, the step or the ground changes
	var key := [ox, oz, g, doc.revision, roundf(y0) if t == null else 0.0]
	if _grid_cache.get("key") != key:
		var lines := []
		for k in range(-half, half + 1):
			var col := Color(1, 1, 1, 0.3) if posmod(int(roundf((ox + k * g) / g)), 8) == 0 else Color(1, 1, 1, 0.12)
			var col2 := Color(1, 1, 1, 0.3) if posmod(int(roundf((oz + k * g) / g)), 8) == 0 else Color(1, 1, 1, 0.12)
			var a := PackedVector3Array()
			var b := PackedVector3Array()
			for j in range(-half, half + 1, 2):
				a.append(_grid_point(t, ox + k * g, oz + j * g, y0))
				b.append(_grid_point(t, ox + j * g, oz + k * g, y0))
			lines.append([a, col])
			lines.append([b, col2])
		_grid_cache = {"key": key, "lines": lines}
	for ln in _grid_cache.lines:
		draw.polyline(ln[0], ln[1], false, false)


func _grid_point(t: LevelTerrain, x: float, z: float, y0: float) -> Vector3:
	var h := t.height_at(x, z) if t != null else NAN
	return Vector3(x, (h if not is_nan(h) else y0) + 0.15, z)


## Which way a lap runs: an arrow every ARROW_EVERY m on the main road and the branches (the last
## bake's), and the grid's slots behind the start line (1.3).
func _draw_race_marks() -> void:
	if build == null:
		return
	for r in build.roads:
		if r == null or r.n < 2 or r.partial:
			continue
		var s := ARROW_EVERY * 0.5
		while s < r.length:
			var i := r.idx(s)
			draw.arrow(r.surface(i, 0.0, 0.3), r.fwd[i], 4.0, ARROW_COLOR, false)
			s += ARROW_EVERY
	var grid = build.data.get("grid", [])
	if grid is Array:
		for slot in grid:
			if not (slot is Dictionary):
				continue
			var p := LevelView._v3(slot.get("pos")) - Vector3.UP * 0.5
			var f = slot.get("fwd")
			var fw := Vector3(float(f[0]), 0.0, float(f[2])).normalized() if f is Array and (f as Array).size() >= 3 else Vector3.FORWARD
			if fw.length_squared() < 1e-6:
				fw = Vector3.FORWARD
			var rt := fw.cross(Vector3.UP).normalized()
			var q := PackedVector3Array([p + fw * 1.5 + rt * 0.9, p + fw * 1.5 - rt * 0.9, p - fw * 1.5 - rt * 0.9, p - fw * 1.5 + rt * 0.9])
			draw.polyline(q, ARROW_COLOR, true, false)


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
	# the perspective view (TOP VIEW is a flag): T comes back to it, a save's header shows it
	session.camera = camera.persp_transform()
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
	var why := str(ld.get("failed", ""))
	if why != "":
		_refuse(why)
		return
	var res := int(ld.get("rescues", 0))
	var best := float(ld.get("best_lap", 0.0))
	var lap := _lap_text(best) if best > 0.0 else ""
	var t := ""
	if str(ld.get("from", "")) == "watch":
		if bool(ld.get("finished", true)) or float(ld.get("stuck_at_s", -1.0)) < 0.0:
			t = "BOT LAP %s, %d RESCUE%s" % [lap if lap != "" else "-", res, "" if res == 1 else "S"]
			session.bot_lap = {"line": t}
		else:
			var ss := float(ld.get("stuck_at_s", 0.0))
			t = "STUCK AT s %d" % int(ss)
			var bl := {"line": "WATCH A BOT LAP: the bot got stuck %d m after the start." % int(ss), "s": ss}
			var r := road(-1)
			if r != null and r.n > 0:
				bl["pos"] = r.pos[r.idx(ss)]
			session.bot_lap = bl
		# the checklist's bot_lap line (and its pin) on the bake shown now; the next bakes add it too
		if build != null and _note_bot_lap(build):
			if markers != null:
				markers.set_issues(build.report)
			if ui != null:
				ui.set_report(build.report)
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


## A test drive refused or failed: the toast, the status line and the validation drawer (1.7).
func _refuse(why: String) -> void:
	var text := EditorKit.prompt(why)
	toast(text)
	status(text)
	if ui != null and ui.drawer != null and not ui.drawer.visible:
		ui.toggle_validation()


func _drive(opts: Dictionary) -> void:
	if view != null:
		view.keep_resources(session)
	session.start_test_drive(get_tree(), opts, func(reason: String) -> void:
		if reason != "":
			_refuse(reason))


func _save_with(b: LevelBuild, target: String, after := Callable()) -> void:
	_save_pending = true
	if b != null and not doc.thumb_custom:
		await _render_thumb(b)
	if session == null or not session.is_open():
		_save_pending = false
		return
	_store_view()
	session.save(target, {}, func(err: int) -> void:
		_save_pending = false
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
