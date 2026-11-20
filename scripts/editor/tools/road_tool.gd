class_name RoadTool
extends EditorTool
## 1.6 ROAD: an open road grows from the end it last grew from, so a loop clicked round in order
## closes on the first point (Shift + click, a new session or after OPEN LOOP: the end nearest the
## cursor); a rubber band shows the new segment; either end glows within 12 px: CLICK CLOSE LOOP.
## On a closed loop a ground click only deselects, the "+" dots and Ctrl + click insert points; DRAW
## (D held, or no road yet)
## sketches a road (Douglas-Peucker 3 m, points about 40 m apart, one undo step); point drags in the
## plane with FOLLOW GROUND, Shift + drag the height, readouts beside the point, the centre line on
## top, a preview while dragging and `settle` at the release; handle squares (double click: AUTO);
## Ctrl / Alt + wheel width / bank; Delete, J (jump), C (close / open the loop); the point and
## segment inspectors and the tool options. The point editing is road-agnostic (key -1 the main
## road, else a branch uid): BranchTool edits its points through the same methods. P13.

const KINDS := ["road_point", "handle", "segment", "segment_mid", "start"]
## The other end glows and a click closes the loop within this many pixels of it.
const CLOSE_PX := 12.0
## DRAW: a sample every 4 m of cursor travel, Douglas-Peucker 3 m, points about 40 m apart,
## closed when released within 30 m of the start with at least 4 points.
const DRAW_STEP := 4.0
const DRAW_TOL := 3.0
const DRAW_SPACING := 40.0
const DRAW_CLOSE := 30.0
const DRAW_MIN := 4
## A point made on the ground sits this far over the natural ground (FOLLOW GROUND's default).
const GROUND_UP := 0.3
const WIDTH_MIN := 6.0
const WIDTH_MAX := 40.0
const WIDTH_STEP := 0.5
const BANK_MAX := 25.0
const HANDLE_MAX := 200.0
const GRADE_RED := 0.30
const RAIL_RADIUS := 60.0
## J's jump: a 12 m gap at the segment's middle with a 16 m kicker of 1.8 m.
const JUMP := {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0}
const TOP_SPEED := 31.0
const SPEED_MARGIN := 1.08
const T_STEP := 1.0 / 65536.0
## Shift + drag: metres per pixel when there is no camera (tests).
const HEIGHT_PER_PX := 0.1
## The segment inspector's BARRIER choices and their LevelStyles.barrier kinds.
const BARRIER_NAMES := ["STYLE'S", "NONE", "RAIL", "FENCE", "WALL", "JERSEY"]
const BARRIER_KINDS := ["style", "none", "rail", "fence", "wall", "jersey"]
const GRIPS := ["STYLE'S", "ROAD", "OFF-ROAD"]

const POINT_COLOR := Color(1.0, 1.0, 1.0)
const END_COLOR := Color(0.45, 0.85, 1.0)
const GLOW_COLOR := Color(0.45, 1.0, 0.45)
const HANDLE_COLOR := Color(1.0, 0.85, 0.3)
const MID_COLOR := Color(0.75, 0.9, 1.0)
const START_COLOR := Color(1.0, 1.0, 1.0)
const BAND_COLOR := Color(1.0, 0.61, 0.0)
const LINE_COLOR := Color(1.0, 0.85, 0.2)
const SEG_COLOR := Color(1.0, 0.61, 0.0, 0.3)
const RED := "ff5240"

## NEW POINT WIDTH / NEW SEGMENT STYLE (tool options): a road's first point and DRAW use them.
var new_width := 14.0
var new_style := "asphalt"
## The selected segment (its owner point's uid; a click on the road), 0 none.
var segment := 0
## The last drag readout: {r, grade, width, seg, limit, r_bad, grade_bad, text} ({} none).
var readout := {}
## C on a closed loop asks "Open the loop here?" first (tests set it false).
var ask_open := true
## SET START LINE: the next click on the road puts the start line there.
var picking_start := false
## The DRAW stroke's samples (while drawing).
var draw_pts := PackedVector3Array()
## Forces DRAW for the next drag (tests; D held does the same).
var force_draw := false

## The open road's growing end: the uid of the point a click or DRAW added last, 0 none (a new
## session, after OPEN LOOP): then a click grows the end nearest the cursor.
var _grow_uid := 0
var _grow_side := 1      # that point's end: 0 the first, 1 the last (an undo or delete keeps the side)
var _drag := {}          # {mode: point | handle | start | draw, key, uid, ...}
var _label: RichTextLabel
var _gizmo := false
var _bound := false
var _length_label: Label
var _opt_closed := -1    # the loop state the options were built for


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "road"
	title = "ROAD"
	purpose = "Lay the road: click to add points, drag them, close the loop"


func kinds() -> PackedStringArray:
	return PackedStringArray(KINDS)


func activate() -> void:
	if not _bound and editor != null and editor.selection != null:
		_bound = true
		editor.selection.changed.connect(_on_selection)
		editor.baked.connect(_on_baked)


func deactivate() -> void:
	_cancel_drag(false)
	picking_start = false
	if _gizmo:
		_gizmo_off()
	if _bound and editor != null and editor.selection != null and editor.selection.changed.is_connected(_on_selection):
		editor.selection.changed.disconnect(_on_selection)
	if _bound and editor != null and editor.baked.is_connected(_on_baked):
		editor.baked.disconnect(_on_baked)
	_bound = false
	_length_label = null


func _on_baked(b: LevelBuild) -> void:
	if _length_label != null and is_instance_valid(_length_label):
		var r := LevelFixes.road_of(b, -1)
		_length_label.text = _metres(r.length if r != null else 0.0)


## The loop was closed or opened (an undo too): the options' CLOSE / OPEN LOOP button follows; a
## selected segment whose point went is let go.
func on_doc_changed(sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	if editor == null or editor.doc == null or not ("road" in sections):
		return
	if segment != 0 and index_of(-1, segment) < 0:
		segment = 0
	_follow_grow()
	if _opt_closed != int(is_closed(-1)) and editor.tool == self and editor.ui != null:
		editor.ui.refresh_tool()


## After an edit the growing end follows its point (REVERSE moves it to the other side); when the
## point is gone or no longer an end (an undo, a delete, a redo), the point now on that side grows,
## so undoing a wrong click and clicking again keeps going round.
func _follow_grow() -> void:
	if _grow_uid == 0:
		return
	var pts := points(-1)
	if pts.is_empty():
		_grow_uid = 0
	elif int(pts[-1].get("uid", 0)) == _grow_uid:
		_grow_side = 1
	elif int(pts[0].get("uid", 0)) == _grow_uid:
		_grow_side = 0
	else:
		_grow_uid = int(pts[-1 if _grow_side == 1 else 0].get("uid", 0))


## Marks the point a click or DRAW just added as the growing end.
func _grew(uid: int) -> void:
	var pts := points(-1)
	if index_of(-1, uid) < 0:
		return
	_grow_uid = uid
	_grow_side = 0 if pts.size() > 1 and int(pts[0].get("uid", 0)) == uid else 1


func _on_selection() -> void:
	if segment != 0 and editor.selection.uids != PackedInt32Array([segment]):
		segment = 0
	editor.refresh_markers()


# ---------------------------------------------------------------- the document

## The live point list of a road (-1 the main road, else a branch uid).
func points(key := -1) -> Array:
	if editor == null or editor.doc == null:
		return []
	return LevelFixes.points_of(editor.doc, key)


func is_closed(key := -1) -> bool:
	if key != -1 or editor == null or editor.doc == null:
		return false
	var road = editor.doc.data.get("road")
	return road is Dictionary and bool(road.get("closed", false)) and (road.get("points", []) as Array).size() >= 3


static func pts_path(key: int) -> Array:
	return ["road", "points"] if key == -1 else ["branches", "#%d" % key, "points"]


static func ppath(key: int, uid: int) -> Array:
	return LevelFixes.point_path(key, uid)


## The road a point belongs to (-1 main, a branch uid), -2 when the uid is not a road point.
func road_of_point(uid: int) -> int:
	var f := editor.doc.find(uid) if editor.doc != null else {}
	if f.is_empty():
		return -2
	if str(f.get("section", "")) == "road":
		return -1
	if str(f.get("section", "")) == "branches" and f.has("branch"):
		return int(f.get("road", -2))
	return -2


func index_of(key: int, uid: int) -> int:
	var pts := points(key)
	for k in pts.size():
		if pts[k] is Dictionary and int(pts[k].get("uid", 0)) == uid:
			return k
	return -1


func point(key: int, uid: int) -> Dictionary:
	var k := index_of(key, uid)
	return points(key)[k] if k >= 0 else {}


## The ground's natural height at (x, z), NAN off the terrain (or with none).
func natural(x: float, z: float) -> float:
	var t := editor.terrain() if editor != null else null
	if t == null:
		return NAN
	return t.natural_at(x, z)


## AUTO / CUSTOM handles of point k: [dir, in, out] (dir a unit vector; LevelRoad._handles).
func handle_of(key: int, k: int) -> Array:
	var pts := points(key)
	var n := pts.size()
	if k < 0 or k >= n:
		return [Vector3.ZERO, 0.0, 0.0]
	var p := _v3(pts[k].get("pos"))
	var h = pts[k].get("handle")
	if h is Dictionary and h.get("dir") != null and _v3(h.dir).length_squared() > 1e-12:
		return [_v3(h.dir).normalized(), clampf(float(h.get("in", 0.0)), 0.0, HANDLE_MAX), clampf(float(h.get("out", 0.0)), 0.0, HANDLE_MAX)]
	var closed := is_closed(key)
	var prev: Vector3
	var next: Vector3
	if closed:
		prev = _v3(pts[posmod(k - 1, n)].get("pos"))
		next = _v3(pts[(k + 1) % n].get("pos"))
	else:
		prev = _v3(pts[k - 1].get("pos")) if k > 0 else (p * 2.0 - _v3(pts[1].get("pos")) if n > 1 else p)
		next = _v3(pts[k + 1].get("pos")) if k < n - 1 else (p * 2.0 - _v3(pts[k - 1].get("pos")) if n > 1 else p)
	var d := next - prev
	d = d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO
	return [d, (p - prev).length() / 3.0, (next - p).length() / 3.0]


## The curve point of segment k at Bezier parameter u (its owner k to the next point).
func curve_at(key: int, k: int, u: float) -> Vector3:
	var pts := points(key)
	var n := pts.size()
	if n == 0:
		return Vector3.ZERO
	var j := (k + 1) % n
	var p0 := _v3(pts[k].get("pos"))
	var p1 := _v3(pts[j].get("pos"))
	var h0 := handle_of(key, k)
	var h1 := handle_of(key, j)
	var c0: Vector3 = p0 + (h0[0] as Vector3) * float(h0[2])
	var c1: Vector3 = p1 - (h1[0] as Vector3) * float(h1[1])
	var v := 1.0 - u
	return p0 * v * v * v + c0 * 3.0 * v * v * u + c1 * 3.0 * v * u * u + p1 * u * u * u


func segments(key := -1) -> int:
	var n := points(key).size()
	return n if is_closed(key) else maxi(n - 1, 0)


# ---------------------------------------------------------------- markers and overlay

func markers(m: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	var pts := points(-1)
	var n := pts.size()
	var closed := is_closed(-1)
	for k in n:
		var uid := int(pts[k].get("uid", 0))
		var p := _v3(pts[k].get("pos"))
		var end := not closed and (k == 0 or k == n - 1)
		m.add("road_point", uid, p, EditorMarkers.Shape.DOT, END_COLOR if end else POINT_COLOR, 2.0)
	add_handles(m, -1, "handle")
	for k in segments(-1):
		m.add("segment_mid", int(pts[k].get("uid", 0)), curve_at(-1, k, 0.5), EditorMarkers.Shape.PLUS, MID_COLOR, 1.6, 5)
	var st = editor.doc.data.road.get("start")
	var r := editor.road(-1)
	if st is Dictionary and int(st.get("p", 0)) > 0 and r != null and r.n > 0 and not r.partial:
		# at the left edge of the line, clear of the point there
		m.add("start", int(st.p), r.surface(0, -r.width[0] * 0.5 - 1.0, 0.3), EditorMarkers.Shape.BAR, START_COLOR, 3.0)


## The handle squares of the selected points of a road (sub 1 in, 2 out).
func add_handles(m: EditorMarkers, key: int, kind: String) -> void:
	var pts := points(key)
	for k in pts.size():
		var uid := int(pts[k].get("uid", 0))
		if not editor.selection.has(uid):
			continue
		var p := _v3(pts[k].get("pos"))
		var h := handle_of(key, k)
		var d: Vector3 = h[0]
		if d == Vector3.ZERO:
			continue
		m.add(kind, uid, p - d * float(h[1]), EditorMarkers.Shape.SQUARE, HANDLE_COLOR, 1.2, 1)
		m.add(kind, uid, p + d * float(h[2]), EditorMarkers.Shape.SQUARE, HANDLE_COLOR, 1.2, 2)


func overlay(d: EditorDraw) -> void:
	if editor == null or editor.doc == null:
		return
	draw_handle_lines(d, -1)
	var r: LevelRoad = LevelFixes.road_of(editor.build, -1)
	# the selected segment's strip
	if segment != 0 and r != null:
		var k := index_of(-1, segment)
		if k >= 0 and k < r.seg_first.size() and r.seg_first[k] >= 0:
			var i0 := r.seg_first[k]
			var s0 := r.s[i0]
			var s1 := s0 + r.seg_len[k]
			var w := r.width[i0] * 0.5
			d.strip_on_road(r, s0, s1, -w, w, SEG_COLOR)
	# while dragging: the road's centre line on top (it shows through the ground)
	if not _drag.is_empty() and str(_drag.mode) in ["point", "handle"]:
		var key := int(_drag.key)
		for rr in [editor.road(key)]:
			if rr != null and rr.n > 1:
				d.polyline(rr.pos, LINE_COLOR, rr.closed, true)
		_place_label()
	if not draw_pts.is_empty():
		d.polyline(draw_pts, BAND_COLOR, false, true)
	var h := editor.hover
	if h == null or not _drag.is_empty() or draw_pts.size() > 0:
		return
	# the rubber band of an open road and the CLOSE LOOP glow
	var pts := points(-1)
	# (over the end point's marker too: the hit is not ground there)
	if not is_closed(-1) and not pts.is_empty() and h.hit and (_is_ground(h) or close_target(h) != 0):
		var close := close_target(h)
		if close != 0:
			var cp := _v3(point(-1, close).get("pos"))
			d.circle(cp, Vector3.UP, 3.0, GLOW_COLOR)
			d.circle(cp, Vector3.UP, 4.0, GLOW_COLOR)
			var other := int(pts[0].uid) if int(pts[-1].uid) == close else int(pts[-1].uid)
			d.line(_v3(point(-1, other).get("pos")), cp, GLOW_COLOR)
		else:
			var e := extend_end(h.pos, Input.is_key_pressed(KEY_SHIFT))
			d.line(_v3(pts[e].get("pos")), _ground_pos(h), BAND_COLOR)


## The lines from the selected points to their handle squares.
func draw_handle_lines(d: EditorDraw, key: int) -> void:
	var pts := points(key)
	for k in pts.size():
		if not editor.selection.has(int(pts[k].get("uid", 0))):
			continue
		var p := _v3(pts[k].get("pos"))
		var h := handle_of(key, k)
		var v: Vector3 = h[0]
		if v != Vector3.ZERO:
			d.line(p - v * float(h[1]), p + v * float(h[2]), HANDLE_COLOR)


# ---------------------------------------------------------------- hover hints

func hints(hit: EditorHit) -> Array:
	if hit == null:
		return []
	if picking_start:
		return [["CLICK THE ROAD: SET THE START LINE"], ["{ed_cancel} CANCEL"]]
	var pts := points(-1)
	var closed := is_closed(-1)
	if hit.what == "marker":
		match hit.kind:
			"road_point":
				if close_target(hit) != 0:
					return [["CLICK CLOSE LOOP"], ["DRAG MOVE"]]
				return [["CLICK SELECT"], ["DRAG MOVE"], ["{ed_mod_shift} DRAG HEIGHT"], ["DOUBLE CLICK HANDLE AUTO"],
					["{ed_mod_ctrl} WHEEL WIDTH"], ["{ed_mod_alt} WHEEL BANK"], ["{ed_delete} DELETE"]]
			"handle":
				return [["DRAG TURN THE CURVE"], ["DOUBLE CLICK AUTO"]]
			"segment_mid":
				return [["DRAG ADD A POINT HERE"], ["CLICK SELECT THE SEGMENT"]]
			"start":
				return [["DRAG MOVE THE START LINE"]]
			"issue":
				return [["CLICK SHOW THE PROBLEM"]]
		return []
	if hit.what == "road" and hit.road == -1:
		var out := [["CLICK SELECT THE SEGMENT"], ["{ed_mod_ctrl} CLICK ADD A POINT HERE"], ["{ed_jump} JUMP"]]
		if closed:
			out.append(["{ed_close_loop} OPEN THE LOOP HERE"])
		return out
	if pts.is_empty():
		return [["CLICK ADD THE FIRST POINT"], ["DRAG DRAW A ROAD"]]
	if closed:
		# (DRAW is refused on a closed loop)
		return [["CLICK DESELECT"], ["DRAG A + DOT: ADD A POINT"], ["{ed_mod_ctrl} CLICK THE ROAD: ADD A POINT"]]
	if close_target(hit) != 0:
		return [["CLICK CLOSE LOOP"], ["{ed_close_loop} CLOSE LOOP"]]
	var out2 := [["CLICK EXTEND THE ROAD"], ["{ed_draw} + DRAG DRAW"]]
	if pts.size() >= 2:
		out2.insert(1, ["{ed_mod_shift} CLICK EXTEND THE NEARER END"])
	if pts.size() >= 3:
		out2.append(["{ed_close_loop} CLOSE LOOP"])
	return out2


func status_step() -> String:
	if picking_start:
		return "Click the road where the start line goes"
	if not draw_pts.is_empty():
		return "Drawing: release to finish (near the start: a closed loop)"
	if points(-1).is_empty():
		return "Click on the ground to start the road, or drag to draw it"
	if not is_closed(-1):
		return "Click to extend the road; click its other end (or press {ed_close_loop}) to close the loop"
	return ""


# ---------------------------------------------------------------- clicks

func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null:
		return false
	if picking_start:
		if hit.what == "road" and hit.road == -1:
			set_start_at(hit.s)
			picking_start = false
		else:
			editor.status("Click the road to set the start line")
		return true
	if hit.what == "road" and hit.road == -1:
		if has_mod(mods, MOD_CTRL):
			insert_at_hit(hit)
			return true
		select_segment(segment_owner(hit))
		return true
	if hit.what == "marker":
		match hit.kind:
			"road_point":
				if close_target(hit) != 0:
					close_loop()
					return true
				segment = 0
				return false
			"segment_mid":
				select_segment(hit.uid)
				return true
			"handle", "start":
				return true
		return false
	if _is_ground(hit) or hit.what == "prop":
		if is_closed(-1):
			if hit.what == "prop":
				return false
			# a ground click on a closed loop never adds a point
			segment = 0
			editor.selection.clear()
			return true
		if close_target(hit) != 0:
			close_loop()
			return true
		extend(_ground_pos(hit), _on_terrain(hit), has_mod(mods, MOD_SHIFT))
		return true
	return false


func double_click(hit: EditorHit, _mods: int) -> bool:
	if hit.what == "marker" and hit.kind in ["road_point", "handle", "branch_point"]:
		var key := road_of_point(hit.uid)
		if key == -2:
			return false
		set_auto_handle(key, hit.uid)
		return true
	return false


## The point uid of the other end within 12 px of the cursor (the CLOSE LOOP glow), 0 none. Only
## an open main road of 3 points or more can close.
func close_target(hit: EditorHit) -> int:
	if editor == null or is_closed(-1):
		return 0
	var pts := points(-1)
	if pts.size() < 3:
		return 0
	var first := int(pts[0].get("uid", 0))
	var last := int(pts[-1].get("uid", 0))
	if hit.what == "marker" and hit.kind == "road_point" and (hit.uid == first or hit.uid == last):
		return hit.uid
	var cam := editor.camera
	if cam == null or not cam.is_inside_tree():
		return 0
	for u in [first, last]:
		var p := _v3(point(-1, u).get("pos"))
		if cam.is_position_behind(p):
			continue
		if cam.unproject_position(p).distance_to(hit.screen) <= CLOSE_PX:
			return u
	return 0


## The index of the open road's end a click grows (0 or n - 1): the end it grew last, else (or
## `nearest`: Shift held, DRAW) the end nearest to a world spot.
func extend_end(at: Vector3, nearest := false) -> int:
	var pts := points(-1)
	if pts.size() <= 1:
		return 0
	if not nearest and _grow_uid != 0:
		if int(pts[-1].get("uid", 0)) == _grow_uid:
			return pts.size() - 1
		if int(pts[0].get("uid", 0)) == _grow_uid:
			return 0
	var a := _v3(pts[0].get("pos"))
	var b := _v3(pts[-1].get("pos"))
	var da := Vector2(at.x - a.x, at.z - a.z).length()
	var db := Vector2(at.x - b.x, at.z - b.z).length()
	return 0 if da < db else pts.size() - 1


## Adds a point to the open main road at its growing end (`nearest`: the end nearest to `at`; one
## undo step) and makes it the growing end. The new point takes its neighbour's width and style; on
## terrain FOLLOW GROUND is on.
func extend(at: Vector3, on_terrain: bool, nearest := false) -> int:
	if is_closed(-1):
		return 0
	var pts := points(-1)
	if pts.size() >= LevelDoc.CAPS.points:
		editor.toast("A road has at most %d points." % LevelDoc.CAPS.points)
		return 0
	var nb: Dictionary = {}
	var at_i := -1
	if not pts.is_empty():
		var e := extend_end(at, nearest)
		nb = pts[e]
		at_i = 0 if e == 0 and pts.size() > 1 else -1
	var uid := editor.doc.new_uid()
	var p := {"uid": uid, "pos": _arr(at), "width": float(nb.get("width", new_width)),
		"style": str(nb.get("style", new_style)), "follow": on_terrain}
	var ops := [LevelDoc.op_insert(["road", "points"], at_i, p)]
	var st = editor.doc.data.road.get("start")
	if pts.is_empty() or not (st is Dictionary) or int(st.get("p", 0)) <= 0:
		ops.append(LevelDoc.op_set(["road", "start"], {"p": uid if pts.is_empty() else int(pts[0].uid), "t": 0.0}))
	editor.commit("ADD POINT", ops)
	_grew(uid)
	editor.select(PackedInt32Array([uid]))
	succeeded()
	return uid


func close_loop() -> void:
	var ops := LevelFixes.close_loop_ops(editor.doc)
	if ops.is_empty():
		editor.status("A loop needs at least 3 points.")
		return
	editor.commit("CLOSE LOOP", ops)
	editor.status("The loop is closed.")
	succeeded()


## Opens the closed loop at the segment owned by uid: the next point becomes the first.
func open_loop_at(uid: int) -> void:
	var pts := points(-1)
	var k := index_of(-1, uid)
	if not is_closed(-1) or k < 0:
		return
	var out := []
	for q in pts.size():
		out.append((pts[(k + 1 + q) % pts.size()] as Dictionary).duplicate(true))
	editor.commit("OPEN LOOP", [LevelDoc.op_set(["road", "points"], out), LevelDoc.op_set(["road", "closed"], false)])
	segment = 0
	_grow_uid = 0


## C: closes an open loop, or asks to open a closed one at owner's segment (0: the selected one).
func toggle_loop(at := 0) -> void:
	if not is_closed(-1):
		close_loop()
		return
	var owner := at if at != 0 else selected_owner()
	if owner == 0:
		editor.status("Select a segment (click the road) to open the loop there.")
		return
	if not ask_open:
		open_loop_at(owner)
		return
	var mb := MessageBox.new("OPEN LOOP", "Open the loop here?", false, false, "OPEN", "CANCEL")
	mb.answered.connect(func(ok: bool, _t: String) -> void:
		if ok:
			open_loop_at(owner))
	editor.open_dialog(mb)


## The selected segment's owner: the clicked segment, else the first selected main-road point.
func selected_owner() -> int:
	if segment != 0 and index_of(-1, segment) >= 0:
		return segment
	for u in editor.selection.uids:
		if road_of_point(u) == -1:
			return u
	return 0


## The main road's segment under the mouse (its owner point's uid), 0 when the mouse is elsewhere.
func hover_owner() -> int:
	var h := editor.hover if editor != null else null
	if h == null or not h.hit or h.what != "road" or h.road != -1:
		return 0
	return segment_owner(h)


func select_segment(uid: int) -> void:
	if uid <= 0:
		return
	editor.select(PackedInt32Array([uid]))
	segment = uid
	if editor.ui != null:
		editor.ui.refresh_inspector()
	editor.redraw()


## The compiled road a road hit's sample belongs to: the live preview or the bake's (a hit on the
## stretch a preview leaves alone carries the bake's sample index).
func hit_road(hit: EditorHit) -> LevelRoad:
	var best: LevelRoad = null
	var bd := INF
	for r in [editor.road(hit.road), LevelFixes.road_of(editor.build, hit.road)]:
		var rr := r as LevelRoad
		if rr == null or hit.sample < 0 or hit.sample >= rr.n:
			continue
		var d := rr.pos[hit.sample].distance_to(hit.pos) if hit.hit else 0.0
		if d < bd:
			bd = d
			best = rr
	return best


## The point owning the road sample under a road hit (0 none).
func segment_owner(hit: EditorHit) -> int:
	var r := hit_road(hit)
	if r == null or hit.sample < 0 or hit.sample >= r.seg.size():
		return 0
	var k := r.seg[hit.sample]
	return r.point_uids[k] if k >= 0 and k < r.point_uids.size() else 0


## Ctrl + click on the road: a new point at that spot (one undo step).
func insert_at_hit(hit: EditorHit) -> int:
	var r := hit_road(hit)
	if r == null or hit.sample < 0 or hit.sample >= r.n:
		return 0
	var owner := segment_owner(hit)
	var k := index_of(hit.road, owner)
	if k < 0:
		return 0
	var t := clampf(r.segt[hit.sample], 0.02, 0.98)
	var ops := insert_ops(hit.road, k, r.pos[hit.sample], t, r.width[hit.sample])
	if ops.is_empty():
		return 0
	var uid := int(ops[0][3].uid)
	editor.commit("ADD POINT", ops)
	editor.select(PackedInt32Array([uid]))
	succeeded()
	return uid


## The ops that insert a point at `pos` into segment k of a road, t of the way along it: the new
## point carries the segment's style, grip, barriers, tunnel height and see-saw flag; a jump stays
## on the half it lies in; everything anchored on the segment is re-anchored onto its half.
func insert_ops(key: int, k: int, pos: Vector3, t: float, width := -1.0) -> Array:
	var pts := points(key)
	var n := pts.size()
	if k < 0 or k >= n or n >= LevelDoc.CAPS.points:
		return []
	var own: Dictionary = pts[k]
	var nxt: Dictionary = pts[(k + 1) % n]
	var uid := editor.doc.new_uid()
	var w := width if width > 0.0 else lerpf(float(own.get("width", 14.0)), float(nxt.get("width", 14.0)), t)
	var p := {"uid": uid, "pos": _arr(pos), "width": clampf(snappedf(w, 0.1), WIDTH_MIN, WIDTH_MAX),
		"style": str(own.get("style", "asphalt")), "follow": bool(own.get("follow", false))}
	for f in ["grip", "tunnel_h", "barrier_l", "barrier_r"]:
		if own.get(f) != null:
			p[f] = LevelDoc._copy(own[f])
	if bool(own.get("seesaw", false)):
		p["seesaw"] = true
	var ops := [LevelDoc.op_insert(pts_path(key), k + 1, p)]
	var g = own.get("gap")
	if g is Dictionary:
		var at := float(g.get("at", 0.5))
		var ng: Dictionary = g.duplicate(true)
		if at < t:
			ng.at = clampf(at / t, 0.1, 0.9)
			ops.append(LevelDoc.op_set(ppath(key, int(own.uid)) + ["gap"], ng))
		else:
			ng.at = clampf((at - t) / maxf(1.0 - t, 1e-3), 0.1, 0.9)
			ops[0][3]["gap"] = ng
			ops.append(LevelDoc.op_erase(ppath(key, int(own.uid)) + ["gap"]))
	ops.append_array(split_anchor_ops(key, int(own.uid), uid, t))
	return ops


## Re-anchors everything on the segment of `owner` after a point `added` at t: anchors before t
## stay on the owner (t rescaled), the others move to the new point.
func split_anchor_ops(key: int, owner: int, added: int, t: float) -> Array:
	var doc := editor.doc
	var ops := []
	var split := func(a: Variant) -> Variant:
		if not (a is Dictionary) or int(a.get("p", 0)) != owner:
			return a
		var at := clampf(float(a.get("t", 0.0)), 0.0, 1.0)
		if at < t:
			return {"p": owner, "t": snappedf(at / t, T_STEP)}
		return {"p": added, "t": snappedf((at - t) / maxf(1.0 - t, 1e-6), T_STEP)}
	if key == -1:
		var st = doc.data.road.get("start")
		var ns = split.call(st)
		if ns != st:
			ops.append(LevelDoc.op_set(["road", "start"], ns))
	for sec in ["items", "pads", "barrels", "crowds", "zones", "hazards", "branches"]:
		var list = doc.data.get(sec)
		if not (list is Array):
			continue
		for it in list:
			if not (it is Dictionary):
				continue
			var on: bool
			if sec == "hazards" or sec == "branches":
				on = key == -1
			else:
				on = (int(it.get("road", -1)) if it.get("road") != null else -1) == key
			if not on:
				continue
			var path := [sec, "#%d" % int(it.get("uid", 0))]
			var keys: Array = ["fork", "merge"] if sec == "branches" else (["a", "b"] if sec == "zones" else ["at"])
			for kk in keys:
				var na = split.call(it.get(kk))
				if na != it.get(kk):
					ops.append(LevelDoc.op_set(path + [kk], na))
			if sec == "hazards":
				var z = it.get("zone")
				if z is Array and z.size() == 2:
					var z0 = split.call(z[0])
					var z1 = split.call(z[1])
					if z0 != z[0] or z1 != z[1]:
						ops.append(LevelDoc.op_set(path + ["zone"], [z0, z1]))
				var hp = it.get("pts")
				if hp is Array:
					var np := []
					var moved := false
					for q in hp:
						if q is Dictionary and q.get("at") is Dictionary:
							var qa = split.call(q.at)
							if qa != q.at:
								var q2: Dictionary = q.duplicate(true)
								q2["at"] = qa
								np.append(q2)
								moved = true
								continue
						np.append(q)
					if moved:
						ops.append(LevelDoc.op_set(path + ["pts"], np))
	return ops


## SET START LINE: the start anchor at s metres along the main road.
func set_start_at(s_m: float) -> void:
	var r := editor.road(-1)
	if r == null or r.n <= 0:
		return
	var a := r.s_to_anchor(s_m)
	if a.is_empty():
		return
	a.t = snappedf(float(a.t), T_STEP)
	editor.commit("SET START LINE", [LevelDoc.op_set(["road", "start"], a)])
	editor.status("The start line is set.")


func set_start_here(uid: int) -> void:
	if index_of(-1, uid) < 0:
		return
	editor.commit("SET START LINE", [LevelDoc.op_set(["road", "start"], {"p": uid, "t": 0.0})])


# ---------------------------------------------------------------- drags

func drag_begin(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null:
		return false
	var drawing := force_draw or points(-1).is_empty() or _draw_held()
	if drawing and hit.what != "marker":
		force_draw = false
		if is_closed(-1):
			editor.status("The loop is closed: open it ({ed_close_loop}) to draw more.")
			return false
		return begin_draw(hit)
	if hit.what != "marker":
		return false
	match hit.kind:
		"road_point":
			return begin_point_drag(-1, hit.uid, hit, mods)
		"handle":
			return begin_handle_drag(-1, hit.uid, hit.sub, hit)
		"segment_mid":
			return begin_insert_drag(-1, hit.uid, hit, mods)
		"start":
			_drag = {"mode": "start", "key": -1, "uid": hit.uid, "name": "MOVE START LINE"}
			editor.history.begin_gesture("MOVE START LINE")
			return true
	return false


func drag_move(hit: EditorHit, mods: int) -> void:
	if _drag.is_empty():
		return
	if _drag.mode == "draw":
		draw_sample(hit)
		return
	var ops := drag_ops(hit, false)
	if not ops.is_empty():
		editor.commit(str(_drag.name), ops, "road_drag")
	_preview(false)


func drag_end(hit: EditorHit, mods: int) -> void:
	if _drag.is_empty():
		return
	if _drag.mode == "draw":
		draw_sample(hit, true)
		finish_draw()
		return
	var ops := drag_ops(hit, true)
	if not ops.is_empty():
		editor.commit(str(_drag.name), ops, "road_drag")
	_preview(true)
	editor.history.end_gesture()
	_drag = {}
	readout = {}
	_hide_label()
	succeeded()


## Starts a drag of a point of road `key` (the main road or a branch): in the plane, its height
## following the ground when FOLLOW GROUND is on; Shift (at the press): the height only.
func begin_point_drag(key: int, uid: int, hit: EditorHit, mods: int, step_name := "MOVE POINT", gesture := true) -> bool:
	var pt := point(key, uid)
	if pt.is_empty():
		return false
	var p0 := _v3(pt.pos)
	if not editor.selection.has(uid):
		editor.select(PackedInt32Array([uid]))
	var g0 := natural(p0.x, p0.z)
	_drag = {"mode": "point", "key": key, "uid": uid, "p0": p0, "off": p0.y - g0 if not is_nan(g0) else NAN,
		"follow": bool(pt.get("follow", false)), "height": has_mod(mods, MOD_SHIFT), "screen": hit.screen,
		"start": SelectTool._plane_point(hit, p0.y, p0), "name": step_name}
	if gesture:
		editor.history.begin_gesture(step_name)
	return true


## Starts a handle drag (sub 1 in, 2 out): the tangent's direction and that side's length; the
## other side keeps its length (an AUTO handle becomes CUSTOM).
func begin_handle_drag(key: int, uid: int, sub: int, hit: EditorHit, gesture := true) -> bool:
	var k := index_of(key, uid)
	if k < 0 or not (sub == 1 or sub == 2):
		return false
	var h := handle_of(key, k)
	var p := _v3(points(key)[k].pos)
	var tip: Vector3 = p + (h[0] as Vector3) * float(h[2]) if sub == 2 else p - (h[0] as Vector3) * float(h[1])
	_drag = {"mode": "handle", "key": key, "uid": uid, "sub": sub, "p": p, "h": h, "tip0": tip,
		"start": SelectTool._plane_point(hit, tip.y, tip), "name": "TURN THE CURVE"}
	if gesture:
		editor.history.begin_gesture("TURN THE CURVE")
	return true


## A "+" dot dragged: a new point in the middle of the segment, then dragged (one undo step).
func begin_insert_drag(key: int, owner: int, hit: EditorHit, mods: int, gesture := true) -> bool:
	var k := index_of(key, owner)
	if k < 0:
		return false
	var mid := curve_at(key, k, 0.5)
	var ops := insert_ops(key, k, mid, 0.5)
	if ops.is_empty():
		return false
	var uid := int(ops[0][3].uid)
	if gesture:
		editor.history.begin_gesture("ADD POINT")
	editor.commit("ADD POINT", ops)
	editor.select(PackedInt32Array([uid]))
	begin_point_drag(key, uid, hit, mods & ~MOD_SHIFT, "ADD POINT", false)
	_drag["start"] = SelectTool._plane_point(hit, mid.y, mid)
	return true


## The ops of the current point / handle / start drag for the cursor's hit.
func drag_ops(hit: EditorHit, _final: bool) -> Array:
	match str(_drag.get("mode", "")):
		"point":
			return _point_ops(hit)
		"handle":
			return _handle_ops(hit)
		"start":
			var r := editor.road(-1)
			if r == null or r.n <= 0 or r.partial:
				return []
			var p := hit.pos if hit.hit else SelectTool._plane_point(hit, r.pos[0].y, r.pos[0])
			var a := r.s_to_anchor(r.s[r.closest(p)])
			if a.is_empty():
				return []
			a.t = snappedf(float(a.t), T_STEP)
			return [LevelDoc.op_set(["road", "start"], a)]
	return []


func _point_ops(hit: EditorHit) -> Array:
	var key := int(_drag.key)
	var uid := int(_drag.uid)
	var p0: Vector3 = _drag.p0
	var p := p0
	var g := SelectTool.grid_of(editor)
	if _drag.height:
		var cam := editor.camera
		var mpp := Gizmo3D.world_per_px(cam, p0) if cam != null and cam.is_inside_tree() else HEIGHT_PER_PX
		p.y = p0.y + ((_drag.screen as Vector2).y - hit.screen.y) * mpp
		if g > 0.0:
			p.y = snappedf(p.y, g)
	else:
		var q := SelectTool._plane_point(hit, p0.y, Vector3(NAN, NAN, NAN))
		if is_nan(q.x):
			return []
		var off := q - (_drag.start as Vector3)
		p.x = p0.x + off.x
		p.z = p0.z + off.z
		if g > 0.0:
			p.x = snappedf(p.x, g)
			p.z = snappedf(p.z, g)
		if bool(_drag.follow) and not is_nan(float(_drag.off)):
			var gn := natural(p.x, p.z)
			if not is_nan(gn):
				p.y = gn + float(_drag.off)
	p.y = clampf(p.y, LevelDoc.HEIGHT_MIN, LevelDoc.HEIGHT_MAX)
	var half := editor.doc.world_size() * 0.5
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	return [LevelDoc.op_set(ppath(key, uid) + ["pos"], _arr(p))]


func _handle_ops(hit: EditorHit) -> Array:
	var key := int(_drag.key)
	var uid := int(_drag.uid)
	var p: Vector3 = _drag.p
	var tip0: Vector3 = _drag.tip0
	var q := SelectTool._plane_point(hit, tip0.y, Vector3(NAN, NAN, NAN))
	if is_nan(q.x):
		return []
	var tip := tip0 + (q - (_drag.start as Vector3))
	var v := tip - p if int(_drag.sub) == 2 else p - tip
	if v.length() < 0.5:
		return []
	var h: Array = _drag.h
	var hd := {"dir": _arr(v.normalized(), 0.0001), "in": float(h[1]), "out": float(h[2])}
	if int(_drag.sub) == 2:
		hd.out = clampf(snappedf(v.length(), 0.01), 0.0, HANDLE_MAX)
	else:
		hd["in"] = clampf(snappedf(v.length(), 0.01), 0.0, HANDLE_MAX)
	return [LevelDoc.op_set(ppath(key, uid) + ["handle"], hd)]


## Preview while dragging (the road and the readout), settle at the end.
func _preview(final: bool) -> void:
	if _drag.is_empty() or editor == null or not editor.is_inside_tree():
		return
	var key := int(_drag.key)
	var uids := PackedInt32Array([int(_drag.uid)])
	if final:
		editor.settle(key, uids)
	else:
		editor.preview_roads(key, uids)
		if _drag.mode == "point":
			readout = compute_readout(key, int(_drag.uid))
			_place_label()


## A worker preview is on show (TrackEditor._show_preview): the point's readout follows it.
func on_preview() -> void:
	if _drag.is_empty() or str(_drag.get("mode", "")) != "point":
		return
	readout = compute_readout(int(_drag.key), int(_drag.uid))
	_place_label()


## The drag readout of a point from the preview road: the tightest radius and the steepest grade
## on its two segments, its width and its segment's length; R red under the too_tight limit
## (width / 2 + treatment + 2 m), GRADE red over 30 %.
func compute_readout(key: int, uid: int) -> Dictionary:
	var pt := point(key, uid)
	var r := editor.road(key)
	if pt.is_empty() or r == null or r.n < 2:
		return {}
	# the compiled road's point index (a branch road's point 0 is its fork end)
	var kr := r.point_uids.find(uid)
	if kr < 0:
		return {}
	var nseg := r.seg_len.size()
	var segs := {}
	if kr < nseg:
		segs[kr] = true
	if kr - 1 >= 0:
		segs[kr - 1] = true
	elif r.src_closed and nseg > 0:
		segs[nseg - 1] = true
	var best_r := INF
	var limit := 0.0
	var grade := 0.0
	for i in r.n:
		if not segs.has(r.seg[i]):
			continue
		var rad := r.radius_at(i)
		if rad < best_r or limit == 0.0:
			best_r = minf(best_r, rad)
			limit = r.width[i] * 0.5 + maxf(r.treatment(i, 0), r.treatment(i, 1)) + 2.0
		var j := i + 1
		if j >= r.n:
			if not r.closed:
				continue
			j = 0
		if not segs.has(r.seg[j]) or (r.gap.size() == r.n and (r.gap[i] == 1 or r.gap[j] == 1)):
			continue
		if r.lift.size() == r.n and (r.lift[i] > 0.0 or r.lift[j] > 0.0):
			continue
		var plan := Vector2(r.pos[j].x - r.pos[i].x, r.pos[j].z - r.pos[i].z).length()
		if plan > 0.05:
			grade = maxf(grade, absf(r.pos[j].y - r.pos[i].y) / plan)
	var seg_m := 0.0
	if kr < nseg:
		seg_m = r.seg_len[kr]
	elif kr - 1 >= 0 and kr - 1 < nseg:
		seg_m = r.seg_len[kr - 1]
	var out := {"r": best_r, "grade": grade, "width": float(pt.get("width", 14.0)), "seg": seg_m, "limit": limit,
		"r_bad": best_r < limit, "grade_bad": grade > GRADE_RED}
	var rt := "STRAIGHT" if best_r > 5000.0 else "R %d m" % roundi(best_r)
	var gt := "GRADE %d %%" % roundi(grade * 100.0)
	if out.r_bad:
		rt = "[color=#%s]%s[/color]" % [RED, rt]
	if out.grade_bad:
		gt = "[color=#%s]%s[/color]" % [RED, gt]
	out["text"] = "%s · %s · %d m WIDE · SEGMENT %d m" % [rt, gt, roundi(float(out.width)), roundi(seg_m)]
	return out


func _place_label() -> void:
	if readout.is_empty() or _drag.is_empty() or editor == null or editor.camera == null or not editor.camera.is_inside_tree():
		return
	var pt := point(int(_drag.key), int(_drag.uid))
	if pt.is_empty():
		return
	var p := _v3(pt.pos)
	if editor.camera.is_position_behind(p):
		return
	if _label == null:
		_label = RichTextLabel.new()
		_label.name = "RoadReadout"
		_label.bbcode_enabled = true
		_label.fit_content = true
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.scroll_active = false
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_size_override("normal_font_size", 15)
		_label.add_theme_color_override("default_color", Color.WHITE)
		_label.add_theme_constant_override("outline_size", 4)
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		var parent: Node = editor.markers.get_parent() if editor.markers != null and editor.markers.get_parent() != null else editor
		parent.add_child(_label)
	_label.text = str(readout.get("text", ""))
	_label.size = Vector2(maxf(float(_label.get_content_width()), 40.0) + 4.0, 24)
	_label.position = readout_pos(editor.camera.unproject_position(p), _label.size, editor.free_rect())
	_label.visible = true


## Where the readout goes beside the point at `at`: right of it and above, flipped to its left near
## the right panel and below it near the top, kept inside the free area.
static func readout_pos(at: Vector2, sz: Vector2, free: Rect2) -> Vector2:
	var pos := at + Vector2(18, -26)
	if free.has_area():
		if pos.x + sz.x > free.end.x:
			pos.x = at.x - 18.0 - sz.x
		if pos.y < free.position.y:
			pos.y = at.y + 12.0
		pos.x = clampf(pos.x, free.position.x, maxf(free.end.x - sz.x, free.position.x))
		pos.y = clampf(pos.y, free.position.y, maxf(free.end.y - sz.y, free.position.y))
	return pos


func _hide_label() -> void:
	if _label != null:
		_label.visible = false


func _cancel_drag(undo: bool) -> void:
	if _drag.is_empty():
		return
	var was: String = _drag.mode
	_drag = {}
	readout = {}
	draw_pts = PackedVector3Array()
	_hide_label()
	if was != "draw":
		# only the drag's own step goes back (a drag that has not moved yet made none)
		if undo:
			editor.history.cancel_gesture()
		else:
			editor.history.end_gesture()


## Esc while the button holds a ROAD drag: the drag's step taken back, a DRAW dropped.
func cancel_drag() -> void:
	_cancel_drag(true)


# ---------------------------------------------------------------- DRAW

func _draw_held() -> bool:
	return InputMap.has_action("ed_draw") and Input.is_action_pressed("ed_draw") \
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func begin_draw(hit: EditorHit) -> bool:
	draw_pts = PackedVector3Array([_ground_pos(hit)])
	_drag = {"mode": "draw", "key": -1, "uid": 0, "terrain": _on_terrain(hit)}
	return true


## Adds the cursor's ground spot to the stroke after 4 m of travel (always at the end).
func draw_sample(hit: EditorHit, last := false) -> void:
	var p := _ground_pos(hit)
	if draw_pts.is_empty():
		draw_pts.append(p)
		return
	var q := draw_pts[draw_pts.size() - 1]
	if Vector2(p.x - q.x, p.z - q.z).length() >= DRAW_STEP or (last and Vector2(p.x - q.x, p.z - q.z).length() > 0.5):
		draw_pts.append(p)
	editor.redraw()


## Ends the stroke: Douglas-Peucker 3 m, points about 40 m apart, heights on the ground (+ 0.3 m,
## FOLLOW on), a closed loop when it ends within 30 m of its start with at least 4 points; an
## open road it began near extends it. One undo step "DRAW ROAD".
func finish_draw() -> void:
	var stroke := draw_pts
	draw_pts = PackedVector3Array()
	_drag = {}
	editor.redraw()
	var made := stroke_points(stroke, points(-1).is_empty())
	var pts: PackedVector3Array = made.points
	if pts.size() < 2:
		editor.status("Draw a longer stroke to make a road.")
		return
	var ops := []
	var existing := points(-1)
	var room := LevelDoc.CAPS.points - existing.size()
	if pts.size() > room:
		pts.resize(maxi(room, 0))
	if pts.is_empty():
		return
	var uids := PackedInt32Array()
	var recs := []
	for p in pts:
		var at: Vector3 = p
		var g := natural(at.x, at.z)
		var follow := not is_nan(g)
		if follow:
			at.y = g + GROUND_UP
		var uid := editor.doc.new_uid()
		uids.append(uid)
		var w := new_width
		var st := new_style
		if not existing.is_empty():
			w = float(existing[0].get("width", new_width))
			st = str(existing[0].get("style", new_style))
		recs.append({"uid": uid, "pos": _arr(at), "width": w, "style": st, "follow": follow})
	if existing.is_empty():
		ops.append(LevelDoc.op_set(["road", "points"], recs))
		ops.append(LevelDoc.op_set(["road", "start"], {"p": int(recs[0].uid), "t": 0.0}))
		if bool(made.closed):
			ops.append(LevelDoc.op_set(["road", "closed"], true))
	else:
		# extends the open road from the end its first sample is nearer to
		var e := extend_end(stroke[0], true)
		if e == 0 and existing.size() > 1:
			recs.reverse()
			for q in recs.size():
				ops.append(LevelDoc.op_insert(["road", "points"], q, recs[q]))
		else:
			for rec in recs:
				ops.append(LevelDoc.op_insert(["road", "points"], -1, rec))
		var other := _v3(existing[-1].pos) if e == 0 else _v3(existing[0].pos)
		var tip := stroke[stroke.size() - 1]
		if existing.size() + recs.size() >= 3 and Vector2(tip.x - other.x, tip.z - other.z).length() <= DRAW_CLOSE:
			ops.append(LevelDoc.op_set(["road", "closed"], true))
	editor.commit("DRAW ROAD", ops)
	# the stroke's last point grows next
	_grew(uids[uids.size() - 1])
	editor.select(uids)
	succeeded()


## The points a stroke becomes: {points: PackedVector3Array, closed: bool}. `may_close`: a new road
## (an open road being extended closes through finish_draw instead).
static func stroke_points(stroke: PackedVector3Array, may_close: bool) -> Dictionary:
	if stroke.size() < 2:
		return {"points": PackedVector3Array(stroke), "closed": false}
	var simple := douglas_peucker(stroke, DRAW_TOL)
	var a := stroke[0]
	var z := stroke[stroke.size() - 1]
	var closed := may_close and Vector2(a.x - z.x, a.z - z.z).length() <= DRAW_CLOSE
	var line := simple.duplicate()
	if closed:
		line.append(line[0])
	var total := 0.0
	for i in line.size() - 1:
		total += _plan(line[i], line[i + 1])
	if total < 1.0:
		return {"points": PackedVector3Array([a]), "closed": false}
	var count := maxi(roundi(total / DRAW_SPACING), 1)
	if closed:
		count = maxi(count, DRAW_MIN)
	var step := total / count
	var out := PackedVector3Array()
	var last := count if not closed else count - 1
	var seg := 0
	var acc := 0.0
	for q in last + 1:
		var want := q * step
		while seg < line.size() - 2 and acc + _plan(line[seg], line[seg + 1]) < want - 1e-6:
			acc += _plan(line[seg], line[seg + 1])
			seg += 1
		var l := _plan(line[seg], line[seg + 1])
		var f := clampf((want - acc) / l, 0.0, 1.0) if l > 1e-6 else 0.0
		out.append(line[seg].lerp(line[seg + 1], f))
	if closed and out.size() < DRAW_MIN:
		closed = false
	return {"points": out, "closed": closed}


## Douglas-Peucker in plan (x, z) with tolerance tol (metres).
static func douglas_peucker(pts: PackedVector3Array, tol: float) -> PackedVector3Array:
	var n := pts.size()
	if n < 3:
		return pts.duplicate()
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack := [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var a := Vector2(pts[span.x].x, pts[span.x].z)
		var b := Vector2(pts[span.y].x, pts[span.y].z)
		var best := -1.0
		var bi := -1
		for i in range(span.x + 1, span.y):
			var p := Vector2(pts[i].x, pts[i].z)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if d > best:
				best = d
				bi = i
		if bi >= 0 and best > tol:
			keep[bi] = 1
			stack.append(Vector2i(span.x, bi))
			stack.append(Vector2i(bi, span.y))
	var out := PackedVector3Array()
	for i in n:
		if keep[i] == 1:
			out.append(pts[i])
	return out


static func _plan(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


# ---------------------------------------------------------------- wheel, keys, delete

func wheel(hit: EditorHit, mods: int, notches: int) -> bool:
	if hit == null or hit.what != "marker" or not (hit.kind in ["road_point", "branch_point"]) or notches == 0:
		return false
	if not (has_mod(mods, MOD_CTRL) or has_mod(mods, MOD_ALT)):
		return false
	var key := road_of_point(hit.uid)
	if key == -2:
		return false
	if has_mod(mods, MOD_CTRL):
		nudge_width(key, hit.uid, WIDTH_STEP * notches)
	else:
		nudge_bank(key, hit.uid, notches)
	return true


func nudge_width(key: int, uid: int, by: float) -> void:
	var pt := point(key, uid)
	if pt.is_empty():
		return
	var w := clampf(float(pt.get("width", 14.0)) + by, WIDTH_MIN, WIDTH_MAX)
	editor.commit("WIDTH", [LevelDoc.op_set(ppath(key, uid) + ["width"], w)], "width_%d" % uid)
	editor.status("WIDTH %.1f m" % w)


## Alt + wheel: the bank +-1 deg; from AUTO it starts at the bank the road has there now.
func nudge_bank(key: int, uid: int, notches: int) -> void:
	var pt := point(key, uid)
	if pt.is_empty():
		return
	var b = pt.get("bank")
	var cur := 0.0
	if b != null:
		cur = float(b)
	else:
		var r := editor.road(key)
		var kr := r.point_uids.find(uid) if r != null else -1
		if r != null and kr >= 0 and kr < r.seg_first.size() and r.seg_first[kr] >= 0 and r.bank.size() == r.n:
			cur = roundf(rad_to_deg(r.bank[r.seg_first[kr]]))
	var nb := clampf(cur + notches, -BANK_MAX, BANK_MAX)
	editor.commit("BANK", [LevelDoc.op_set(ppath(key, uid) + ["bank"], nb)], "bank_%d" % uid)
	editor.status("BANK %d°" % roundi(nb))


func key(ev: InputEvent) -> bool:
	if editor == null:
		return false
	if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_SHIFT:
		editor.redraw()   # the rubber band follows Shift (the nearer end)
		return false
	if _act(ev, "ed_cancel"):
		if not _drag.is_empty():
			_cancel_drag(true)
			return true
		if picking_start:
			picking_start = false
			editor.status("")
			return true
		if segment != 0:
			segment = 0
			editor.redraw()
		return false
	# J and C act on the segment under the mouse (their hints say HERE), else the selected one
	if _act(ev, "ed_close_loop"):
		toggle_loop(hover_owner())
		return true
	if _act(ev, "ed_jump"):
		var o := hover_owner()
		toggle_jump(o if o != 0 else selected_owner())
		return true
	if _act(ev, "ed_delete"):
		return refuse_delete(editor.selection.uids)
	if _act(ev, "ed_move") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if _gizmo:
			_gizmo_off()
		else:
			_gizmo_on()
		return true
	return false


func _act(ev: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and ev.is_action_pressed(action, false, true)


## Delete of main-road points that would leave a closed loop under 3: refused with a toast.
func refuse_delete(uids: PackedInt32Array) -> bool:
	if not is_closed(-1):
		return false
	var gone := 0
	for u in uids:
		if road_of_point(u) == -1:
			gone += 1
	if gone > 0 and points(-1).size() - gone < 3:
		editor.toast("A closed loop keeps at least 3 points.")
		return true
	return false


## J: a jump on / off on the segment owned by uid (one undo step).
func toggle_jump(uid: int) -> void:
	var key := road_of_point(uid)
	if key == -2 or uid == 0:
		editor.status("Select a segment (click the road) for the jump.")
		return
	var pt := point(key, uid)
	if pt.get("gap") is Dictionary:
		editor.commit("JUMP OFF", [LevelDoc.op_erase(ppath(key, uid) + ["gap"])])
	else:
		editor.commit("JUMP ON", [LevelDoc.op_set(ppath(key, uid) + ["gap"], JUMP.duplicate(true))])
	succeeded()


## The ops that delete these points (a closed loop keeps at least 3), one after the other on a
## copy of the document so each re-anchors against the previous.
func delete_ops(uids: PackedInt32Array) -> Array:
	if editor == null or editor.doc == null:
		return []
	return point_delete_ops(editor.doc, uids)


static func point_delete_ops(doc: LevelDoc, uids: PackedInt32Array) -> Array:
	var tmp := LevelDoc.new()
	tmp.data = doc.data.duplicate(true)
	var road = tmp.data.get("road")
	var n_main: int = (road.points as Array).size() if road is Dictionary and road.get("points") is Array else 0
	var closed: bool = road is Dictionary and bool(road.get("closed", false))
	var out := []
	for u in uids:
		var f := tmp.find(u)
		if f.is_empty():
			continue
		if str(f.section) == "road":
			if closed and n_main <= 3:
				continue
			n_main -= 1
		elif not (str(f.section) == "branches" and f.has("branch")):
			continue
		var ops := tmp.delete_point_ops(u)
		if ops.is_empty():
			continue
		tmp.apply(ops)
		out.append_array(ops)
	return out


func item_aabb(uid: int) -> AABB:
	var key := road_of_point(uid)
	if key == -2:
		return AABB()
	var p := _v3(point(key, uid).get("pos"))
	var w := float(point(key, uid).get("width", 14.0))
	return AABB(p - Vector3(w, 2.0, w) * 0.5, Vector3(w, 4.0, w))


## A marker of the road's own kinds dragged from SELECT (7.6): the start line, handles and "+"
## dots; their ops are committed by SelectTool.
func slide(uid: int, hit: EditorHit, phase: int) -> Array:
	if phase == 0:
		match hit.kind:
			"start":
				_drag = {"mode": "start", "key": -1, "uid": uid, "name": "MOVE START LINE"}
				return []
			"handle":
				begin_handle_drag(road_of_point(uid), uid, hit.sub, hit, false)
				return []
			"segment_mid":
				var key := road_of_point(uid)
				var k := index_of(key, uid)
				if k < 0:
					return []
				var mid := curve_at(key, k, 0.5)
				var ops := insert_ops(key, k, mid, 0.5)
				if ops.is_empty():
					return []
				var nu := int(ops[0][3].uid)
				var p0 := mid
				var g0 := natural(p0.x, p0.z)
				_drag = {"mode": "point", "key": key, "uid": nu, "p0": p0, "off": p0.y - g0 if not is_nan(g0) else NAN,
					"follow": bool(point(key, uid).get("follow", false)), "height": false, "screen": hit.screen,
					"start": SelectTool._plane_point(hit, mid.y, mid), "name": "ADD POINT"}
				return ops
		return []
	if _drag.is_empty():
		return []
	var out := drag_ops(hit, phase == 2)
	if _drag.mode in ["point", "handle"] and editor.is_inside_tree():
		var key := int(_drag.key)
		var uids := PackedInt32Array([int(_drag.uid)])
		if phase == 2:
			editor.settle.call_deferred(key, uids)
		else:
			editor.preview_roads.call_deferred(key, uids)
	if phase == 2:
		_drag = {}
	return out


# ---------------------------------------------------------------- the gizmo (W)

func _gizmo_on() -> void:
	var st := editor.tools.get("select") as SelectTool
	if st == null:
		return
	st.gizmo_on()
	editor.gizmo.mode = "move"
	_gizmo = true
	editor.status("GIZMO: its Y arrow lifts the point")


func _gizmo_off() -> void:
	var st := editor.tools.get("select") as SelectTool
	if st != null:
		st.gizmo_off()
	_gizmo = false


# ---------------------------------------------------------------- tool options

func options(box: VBoxContainer) -> void:
	if editor == null or editor.doc == null:
		return
	var r := LevelFixes.road_of(editor.build, -1)
	_length_label = UiKit.label(_metres(r.length if r != null else 0.0), EditorKit.FONT_SMALL, UiKit.TEXT)
	box.add_child(EditorKit.row("ROAD LENGTH", _length_label))
	_opt_closed = int(is_closed(-1))
	box.add_child(EditorKit.row("NEW POINT WIDTH", EditorKit.number(new_width, WIDTH_MIN, WIDTH_MAX, WIDTH_STEP,
		func(v: float) -> void: new_width = v, "%.1f", " m")))
	var ids := LevelStyles.ids(editor.doc.data)
	box.add_child(EditorKit.row("SEGMENT STYLE", EditorKit.choice(style_names(ids), maxi(Array(ids).find(new_style), 0),
		func(i: int) -> void: new_style = ids[i]), "NEW SEGMENT STYLE: the style of new points and of DRAW."))
	var closed := is_closed(-1)
	box.add_child(EditorKit.actions([
		["OPEN LOOP" if closed else "CLOSE LOOP", "loop_open" if closed else "loop_closed", toggle_loop,
			("Open the loop at the selected segment ({ed_close_loop})." if closed
				else "Join the last point to the first: a lap ({ed_close_loop}).")],
		["REVERSE", "reverse", reverse, "REVERSE DIRECTION: the race runs the other way round."],
		["SET START LINE", "flag", func() -> void:
			picking_start = true
			editor.status("Click the road where the start line goes", true), "Then click the road where the start line goes."],
		["DRAPE ON GROUND", "drape", drape, "DRAPE ON TERRAIN: every road point just above the ground, and it follows the ground."],
		["SMOOTH HEIGHTS", "smooth", smooth, "Evens out the road's bumps and dips."],
		["RAILS ON BENDS", "rails", rails, "RAILS ON TIGHT BENDS: a rail on the outside of every tight bend."],
		["AUTO DRESS...", "wand", func() -> void: editor.open_dialog(AutoDressDialog.new(editor)),
			"Crate rows, boost pads, rails, scenery and a crowd in one go: you pick which."],
		["STYLES...", "palette", func() -> void: editor.open_dialog(StyleEditor.new(editor)),
			"The road styles: copy one, then change its materials, centre lines and grip."]]))
	box.add_child(EditorKit.hint("CLICK ADD · {ed_draw} + DRAG DRAW · {ed_mod_ctrl} + CLICK INSERT · {ed_close_loop} LOOP · {ed_jump} JUMP · {ed_mod_ctrl} / {ed_mod_alt} + WHEEL WIDTH / BANK"))


static func style_names(ids: PackedStringArray) -> Array:
	var out := []
	for sid in ids:
		out.append(str(LevelStyles.PRESETS[sid].name) if LevelStyles.is_preset(sid) else sid.to_upper())
	return out


func reverse() -> void:
	var ops := editor.doc.reverse_ops()
	if ops.is_empty():
		editor.status("There is no road to reverse.")
		return
	editor.commit("REVERSE TRACK DIRECTION", ops)


## DRAPE ON TERRAIN: every main-road point 0.3 m over the natural ground, FOLLOW on.
func drape() -> void:
	var ops := []
	for p in points(-1):
		var at := _v3(p.get("pos"))
		var g := natural(at.x, at.z)
		if is_nan(g):
			continue
		var uid := int(p.uid)
		ops.append(LevelDoc.op_set(ppath(-1, uid) + ["pos"], [at.x, snappedf(g + GROUND_UP, 0.001), at.z]))
		if not bool(p.get("follow", false)):
			ops.append(LevelDoc.op_set(ppath(-1, uid) + ["follow"], true))
	if ops.is_empty():
		editor.status("There is no terrain under the road.")
		return
	editor.commit("DRAPE ON TERRAIN", ops)


## SMOOTH HEIGHTS: a moving average over 5 points, strength 0.5.
func smooth() -> void:
	editor.commit("SMOOTH HEIGHTS", LevelFixes.smooth_ops(editor.doc, -1, 0.5))


## RAILS ON TIGHT BENDS: a RAIL on the outside of every bend under 60 m without a barrier there
## (LevelDress.rails_ops on a current bake), one undo step.
func rails() -> void:
	editor.bake_now(func(b: LevelBuild) -> void:
		if b == null:
			return
		var ops := LevelDress.rails_ops(editor.doc, b, RAIL_RADIUS)
		if ops.is_empty():
			editor.toast("No tight bend needs a rail.")
			return
		editor.commit("RAILS ON TIGHT BENDS", ops))


# ---------------------------------------------------------------- inspectors

func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if editor == null or uids.is_empty():
		return false
	var key := road_of_point(uids[0])
	if key == -2:
		return false
	if key == -1 and segment != 0 and uids.size() == 1 and uids[0] == segment:
		segment_inspector(key, segment, box)
	else:
		point_inspector(key, uids, box)
	return true


func point_inspector(key: int, uids: PackedInt32Array, box: VBoxContainer) -> void:
	var uid := uids[0]
	var pt := point(key, uid)
	if pt.is_empty():
		return
	var k := index_of(key, uid)
	box.add_child(EditorKit.section_icon("POINT %d" % (k + 1) if uids.size() == 1 else "%d POINTS" % uids.size(), "point"))
	box.add_child(EditorKit.row("POSITION", EditorKit.vec3(_v3(pt.pos), func(v: Vector3, final: bool) -> void:
		editor.commit("MOVE POINT", [LevelDoc.op_set(ppath(key, uid) + ["pos"], _arr(v))], "insp_pos_%d" % uid)
		if final and editor.is_inside_tree():
			editor.settle(key, PackedInt32Array([uid])))))
	box.add_child(EditorKit.row("FOLLOW GROUND", EditorKit.check(bool(pt.get("follow", false)), func(on: bool) -> void:
		editor.commit("FOLLOW GROUND", _each(key, uids, "follow", on)))))
	box.add_child(EditorKit.row("WIDTH", EditorKit.number(float(pt.get("width", 14.0)), WIDTH_MIN, WIDTH_MAX, WIDTH_STEP,
		func(v: float) -> void: editor.commit("WIDTH", _each(key, uids, "width", v), "insp_width_%d" % uid), "%.1f", " m")))
	var bank = pt.get("bank")
	box.add_child(EditorKit.row("BANK", EditorKit.toggle("AUTO", bank == null, func(on: bool) -> void:
		editor.commit("BANK", _each(key, uids, "bank", null if on else 0.0)))))
	if bank != null:
		box.add_child(EditorKit.row("BANK ANGLE", EditorKit.number(float(bank), -BANK_MAX, BANK_MAX, 1.0,
			func(v: float) -> void: editor.commit("BANK", _each(key, uids, "bank", v), "insp_bank_%d" % uid), "%d", "°")))
	var h = pt.get("handle")
	box.add_child(EditorKit.row("HANDLE", EditorKit.toggle("AUTO", not (h is Dictionary), func(on: bool) -> void:
		if on:
			set_auto_handle(key, uid)
		else:
			var hh := handle_of(key, k)
			editor.commit("HANDLE", [LevelDoc.op_set(ppath(key, uid) + ["handle"],
				{"dir": _arr(hh[0], 0.0001), "in": snappedf(float(hh[1]), 0.01), "out": snappedf(float(hh[2]), 0.01)})]))))
	if h is Dictionary:
		for side in ["in", "out"]:
			var sd: String = side
			var set_len := func(v: float) -> void:
				var cur = point(key, uid).get("handle")
				if cur is Dictionary:
					var nh: Dictionary = cur.duplicate(true)
					nh[sd] = v
					editor.commit("HANDLE", [LevelDoc.op_set(ppath(key, uid) + ["handle"], nh)], "insp_h_%d" % uid)
			box.add_child(EditorKit.row("HANDLE " + sd.to_upper(), EditorKit.number(float(h.get(sd, 0.0)), 0.0, HANDLE_MAX, 0.5,
				set_len, "%.1f", " m")))
	if key == -1:
		box.add_child(EditorKit.actions([
			["START LINE HERE", "flag", func() -> void: set_start_here(uid), "SET START LINE HERE: the start line moves to this point."],
			["EDIT SEGMENT", "segment", func() -> void: select_segment(uid), "EDIT ITS SEGMENT: the road from this point to the next."]]))


## The point fields as one set per selected point of that road.
func _each(key: int, uids: PackedInt32Array, field: String, value: Variant) -> Array:
	var out := []
	for u in uids:
		if road_of_point(u) != key:
			continue
		if value == null:
			if point(key, u).get(field) != null:
				out.append(LevelDoc.op_erase(ppath(key, u) + [field]))
		else:
			out.append(LevelDoc.op_set(ppath(key, u) + [field], value))
	return out


func segment_inspector(key: int, uid: int, box: VBoxContainer) -> void:
	var pt := point(key, uid)
	if pt.is_empty():
		return
	var k := index_of(key, uid)
	box.add_child(EditorKit.section_icon("SEGMENT %d" % (k + 1), "segment"))
	var ids := LevelStyles.ids(editor.doc.data)
	var sid := str(pt.get("style", "asphalt"))
	box.add_child(EditorKit.row("STYLE", EditorKit.choice(style_names(ids), maxi(Array(ids).find(sid), 0),
		func(i: int) -> void: editor.commit("STYLE", [LevelDoc.op_set(ppath(key, uid) + ["style"], ids[i])]))))
	for side in ["barrier_l", "barrier_r"]:
		var sd: String = side
		var cur = pt.get(sd)
		var sel := 0
		var height := 1.0
		if cur is Dictionary:
			sel = maxi(BARRIER_KINDS.find(str(cur.get("kind", "wall"))), 1)
			height = float(cur.get("h", 1.0))
		box.add_child(EditorKit.row("BARRIER LEFT" if sd == "barrier_l" else "BARRIER RIGHT",
			EditorKit.choice(BARRIER_NAMES, sel, func(i: int) -> void: set_barrier(key, uid, sd, BARRIER_KINDS[i], 0.0))))
		if cur is Dictionary and str(cur.get("kind", "")) != "none":
			var set_h := func(v: float) -> void:
				var c = point(key, uid).get(sd)
				if c is Dictionary:
					set_barrier(key, uid, sd, str(c.get("kind", "wall")), v)
			box.add_child(EditorKit.row("  HEIGHT", EditorKit.number(height, 0.5, 3.0, 0.1, set_h, "%.1f", " m")))
	var gap = pt.get("gap")
	box.add_child(EditorKit.row("JUMP", EditorKit.toggle("ON" if gap is Dictionary else "OFF", gap is Dictionary,
		func(_on: bool) -> void: toggle_jump(uid))))
	if gap is Dictionary:
		for spec in [["len", "GAP LENGTH", 4.0, 40.0, 0.5, " m"], ["at", "CENTRE", 0.1, 0.9, 0.05, ""],
				["lift", "KICKER LIFT", 0.0, 4.0, 0.1, " m"], ["ramp", "KICKER LENGTH", 6.0, 40.0, 0.5, " m"]]:
			var f: String = spec[0]
			box.add_child(EditorKit.row("  " + str(spec[1]), EditorKit.number(float(gap.get(f, JUMP[f])), spec[2], spec[3], spec[4],
				func(v: float) -> void: editor.commit("JUMP", [LevelDoc.op_set(ppath(key, uid) + ["gap", f], v)], "insp_gap_%d" % uid),
				"%.2f" if f == "at" else "%.1f", spec[5])))
		var need := jump_need(key, uid)
		var ok := need <= TOP_SPEED
		var l := UiKit.label("NEEDS %d m/s: %s" % [roundi(need), "every kart makes it" if ok else "boost only"],
			EditorKit.FONT_SMALL, EditorKit.OK_COLOR if ok else EditorKit.WARN_COLOR)
		box.add_child(l)
	var styles := LevelStyles.resolve(editor.doc.data, {})
	if str((styles.get(sid, {}) as Dictionary).get("kind", "open")) == "tunnel":
		box.add_child(EditorKit.row("TUNNEL HEIGHT", EditorKit.number(float(pt.get("tunnel_h", styles[sid].get("height", 7.5))), 5.0, 20.0, 0.5,
			func(v: float) -> void: editor.commit("TUNNEL HEIGHT", [LevelDoc.op_set(ppath(key, uid) + ["tunnel_h"], v)], "insp_th_%d" % uid),
			"%.1f", " m")))
	if key == -1:
		var on := bool(pt.get("seesaw", false))
		var legal := seesaw_legal(uid)
		var b := EditorKit.toggle("SEE-SAW STRETCH", on, func(v: bool) -> void: set_seesaw(uid, v))
		b.disabled = not on and not legal
		b.tooltip_text = "A straight, level, unbanked segment of at least 73 m" if not legal else "Adds the see-saw too"
		if legal and not on:
			b.add_theme_color_override("font_color", EditorKit.OK_COLOR)
		box.add_child(b)
	var grip = pt.get("grip")
	var gi := 0 if grip == null else (1 if str(grip) == "road" else 2)
	box.add_child(EditorKit.row("SURFACE GRIP", EditorKit.choice(GRIPS, gi, func(i: int) -> void:
		var ops := [LevelDoc.op_erase(ppath(key, uid) + ["grip"])] if i == 0 else [LevelDoc.op_set(ppath(key, uid) + ["grip"], ["", "road", "offroad"][i])]
		editor.commit("GRIP", ops))))
	box.add_child(EditorKit.hint("{ed_jump} JUMP · {ed_close_loop} OPEN THE LOOP HERE"))


## BARRIER LEFT / RIGHT: "style" (null: the style's), "none", or a RAIL / FENCE / WALL / JERSEY
## dict (2.5) with HEIGHT h (col_h = max(2.5, h)).
func set_barrier(key: int, uid: int, side: String, kind: String, height: float) -> void:
	var b = LevelStyles.barrier(kind, height)
	var path := ppath(key, uid) + [side]
	if b == null:
		if point(key, uid).get(side) != null:
			editor.commit("BARRIER", [LevelDoc.op_erase(path)])
		return
	editor.commit("BARRIER", [LevelDoc.op_set(path, b)], "insp_bar_%d_%s" % [uid, side] if height > 0.0 else "")


## The see-saw stretch and its see-saw together (LevelHazards.seesaw_ops), one undo step.
func set_seesaw(uid: int, on: bool) -> void:
	var ops := LevelHazards.seesaw_ops(editor.doc, uid, on)
	if not ops.is_empty():
		editor.commit("SEE-SAW STRETCH" if on else "NO SEE-SAW", ops)


## The segment may be a see-saw stretch: straight, level, unbanked and long enough (4.2).
func seesaw_legal(uid: int) -> bool:
	var m: LevelRoad = LevelFixes.road_of(editor.build, -1)
	if m == null:
		return false
	var k := m.point_uids.find(uid)
	return k >= 0 and LevelHazards._seesaw_segment_ok(m, k)


## The speed the segment's jump needs (branches.launch_speed + 8 %), from the bake's road.
func jump_need(key: int, uid: int) -> float:
	var g = point(key, uid).get("gap")
	if not (g is Dictionary):
		return 0.0
	var drop := 0.0
	var r := editor.road(key)
	if r != null and not r.partial:
		var k := r.point_uids.find(uid)
		for gp in r.gaps:
			if gp.x < r.seg.size() and r.seg[gp.x] == k:
				drop = r.pos[r.wrap(gp.x - 1)].y - r.pos[r.wrap(gp.y)].y
	return SPEED_MARGIN * LevelBranches.launch_speed(float(g.get("len", 12.0)), float(g.get("lift", 1.8)),
		float(g.get("ramp", 16.0)), drop)


## Double click: the point's handle back to AUTO.
func set_auto_handle(key: int, uid: int) -> void:
	if point(key, uid).get("handle") == null:
		return
	editor.commit("HANDLE AUTO", [LevelDoc.op_erase(ppath(key, uid) + ["handle"])])


# ---------------------------------------------------------------- helpers

func _is_ground(hit: EditorHit) -> bool:
	return not hit.hit or hit.what in ["terrain", "water", ""]


func _on_terrain(hit: EditorHit) -> bool:
	return hit.hit and hit.what == "terrain" and not is_nan(natural(hit.pos.x, hit.pos.z))


## Where a click on the ground puts a point: 0.3 m over the natural ground on terrain, the hit on
## water, the plane y = 0 when the ray meets nothing.
func _ground_pos(hit: EditorHit) -> Vector3:
	var p := hit.pos
	if not hit.hit:
		p = SelectTool._plane_point(hit, 0.0, Vector3(hit.ray_from.x, 0.0, hit.ray_from.z))
	if hit.what == "terrain" or not hit.hit:
		var g := natural(p.x, p.z)
		if not is_nan(g):
			p.y = g + GROUND_UP
	return p


static func _metres(m: float) -> String:
	return "%.2f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % roundi(m)


static func _arr(v: Vector3, q := 0.001) -> Array:
	return [snappedf(v.x, q), snappedf(v.y, q), snappedf(v.z, q)]


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
