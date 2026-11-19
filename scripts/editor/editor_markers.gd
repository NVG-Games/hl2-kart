class_name EditorMarkers
extends Control
## Screen-space markers (1.3, C2 M1, M2): drawn every frame at a constant 14 px (never smaller than
## the item's projected world size), picked in screen space within 10 px, nearest first. The active
## tool's kinds are bright and pickable, every other kind is dim (35 %) and clicks pass through it;
## issue pins ("!") are pickable in every tool, rescue pins are view only. P7.
##
## Each tool fills its own list: begin(tool_id) clears it, the add() calls after it belong to it
## (TrackEditor calls every tool's markers(m) after each doc change or bake). The node sits on the
## CanvasLayer "Marks" with mouse_filter IGNORE: TrackEditor does the picking.

enum Shape { DOT, SQUARE, DIAMOND, TRIANGLE, RING, PLUS, PIN, BAR, SUN }

const SIZE := 14.0
const PICK_PX := 10.0
const DIM := 0.35

# ---------------------------------------------------------------- additions (P7)

## The list names of the pins this node keeps itself.
const ISSUES := "#issues"
const RESCUES := "#rescues"
## The biggest a marker grows with its projected world size.
const MAX_PX := 48.0
const HOVER_COLOR := Color8(255, 155, 0)        # UiKit.ORANGE
const SELECTED_COLOR := Color8(255, 155, 0)
const ERROR_COLOR := Color(0.92, 0.2, 0.16)
const WARNING_COLOR := Color(0.98, 0.78, 0.15)
const RESCUE_COLOR := Color(0.85, 0.1, 0.1)

## The camera markers are drawn with (pick and pick_rect take theirs).
var camera: Camera3D

var _lists := {}            # list name -> Array of entries {kind, uid, pos, shape, color, size, sub}
var _order: Array = []      # list names in the order they were first used (drawn in that order)
var _cur := ""              # the list add() appends to
var _live := {}             # kind -> true
var _all_live := false      # "*" given to set_live (SELECT)
var _hover := ["", 0, 0]
var _sel := {}              # uid -> true
var _hidden := {}           # uid -> true (H): neither drawn nor picked
var _issues: Array = []     # the report items that have a pin; a pin's uid is its index + 1
var _last_xf := Transform3D()
var _last_size := -1.0
var _last_vp := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Clears that tool's entries; add() calls after it belong to it.
func begin(tool_id: String) -> void:
	_cur = tool_id
	if not _lists.has(tool_id):
		_order.append(tool_id)
	_lists[tool_id] = []
	queue_redraw()


func add(kind: String, uid: int, pos: Vector3, shape: int, color: Color, world_size := 2.0, sub := 0) -> void:
	if _cur == "":
		begin("#misc")
	(_lists[_cur] as Array).append({"kind": kind, "uid": uid, "pos": pos, "shape": shape, "color": color,
		"size": world_size, "sub": sub})
	queue_redraw()


## Bright + pickable (SELECT: every kind; "*" in the list means every kind too).
func set_live(kinds: PackedStringArray) -> void:
	_live.clear()
	_all_live = false
	for k in kinds:
		if k == "*":
			_all_live = true
		_live[k] = true
	queue_redraw()


func set_hover(kind: String, uid: int, sub := 0) -> void:
	if _hover[0] == kind and _hover[1] == uid and _hover[2] == sub:
		return
	_hover = [kind, uid, sub]
	queue_redraw()


func set_selected(uids: PackedInt32Array) -> void:
	_sel.clear()
	for u in uids:
		_sel[u] = true
	queue_redraw()


## "!" pins, pickable in every tool: every error and warning that has a place (a pos, a uid or an s).
func set_issues(report: LevelReport) -> void:
	_issues.clear()
	if not _lists.has(ISSUES):
		_order.append(ISSUES)
	var list := []
	if report != null:
		for it in report.items:
			if not (it is Dictionary) or str(it.get("level", "")) == "info":
				continue
			var p = it.get("pos", Vector3.ZERO)
			if p is Array and (p as Array).size() >= 3:
				p = Vector3(float(p[0]), float(p[1]), float(p[2]))
			if not (p is Vector3):
				continue
			var placed: bool = (p as Vector3) != Vector3.ZERO or int(it.get("uid", 0)) > 0 or float(it.get("s", -1.0)) >= 0.0
			if not placed:
				continue
			_issues.append(it)
			var err := str(it.get("level", "")) == "error"
			list.append({"kind": "issue", "uid": _issues.size(), "pos": p, "shape": Shape.PIN,
				"color": ERROR_COLOR if err else WARNING_COLOR, "size": 0.0, "sub": 0 if err else 1})
	_lists[ISSUES] = list
	queue_redraw()


## The last drive's pins (view only).
func set_rescues(points: PackedVector3Array) -> void:
	if not _lists.has(RESCUES):
		_order.append(RESCUES)
	var list := []
	for k in points.size():
		list.append({"kind": "rescue", "uid": k + 1, "pos": points[k], "shape": Shape.PIN, "color": RESCUE_COLOR,
			"size": 0.0, "sub": 0})
	_lists[RESCUES] = list
	queue_redraw()


## {kind, uid, sub, pos} of the nearest live marker within PICK_PX, or {}. Issue pins also carry
## "issue" (the report item).
func pick(screen: Vector2, cam: Camera3D) -> Dictionary:
	return _pick(screen, cam, {}, false)


## [{kind, uid}] of live markers inside (issue and rescue pins are not selectable).
func pick_rect(rect: Rect2, cam: Camera3D) -> Array:
	var out := []
	if cam == null or not cam.is_inside_tree():
		return out
	var r := rect.abs()
	var seen := {}
	for name in _order:
		if name == ISSUES or name == RESCUES:
			continue
		for e in _lists[name]:
			if not _is_live(e.kind) or _hidden.has(e.uid):
				continue
			var key := "%s:%d" % [e.kind, e.uid]
			if seen.has(key) or cam.is_position_behind(e.pos):
				continue
			if r.has_point(cam.unproject_position(e.pos)):
				seen[key] = true
				out.append({"kind": e.kind, "uid": e.uid})
	return out


# ---------------------------------------------------------------- additions (P7)

## Like pick, with only these kinds counting as live (TrackEditor.pick's kinds); issue pins too.
func pick_kinds(screen: Vector2, cam: Camera3D, kinds: PackedStringArray) -> Dictionary:
	var only := {}
	for k in kinds:
		only[k] = true
	return _pick(screen, cam, only, true)


## The report item of an issue pin (its uid), or {}.
func issue(uid: int) -> Dictionary:
	if uid < 1 or uid > _issues.size():
		return {}
	return _issues[uid - 1]


## Hidden uids are neither drawn nor picked (H / Alt+H).
func set_hidden(uids: PackedInt32Array) -> void:
	_hidden.clear()
	for u in uids:
		_hidden[u] = true
	queue_redraw()


## Every entry of one list (tests, the tools' own checks).
func entries(list_name: String) -> Array:
	return _lists.get(list_name, [])


func count() -> int:
	var n := 0
	for name in _order:
		n += (_lists[name] as Array).size()
	return n


func is_live(kind: String) -> bool:
	return _is_live(kind)


## The marker's size in pixels at this camera: SIZE, or its projected world size (at most MAX_PX).
func pixel_size(e: Dictionary, cam: Camera3D) -> float:
	var ws := float(e.get("size", 0.0))
	if ws <= 0.0 or cam == null:
		return SIZE
	var h := cam.get_viewport().get_visible_rect().size.y if cam.is_inside_tree() else 900.0
	var px := 0.0
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		px = ws * h / maxf(cam.size, 0.001)
	else:
		var depth := -(cam.global_transform.affine_inverse() * (e.pos as Vector3)).z
		if depth <= 0.01:
			return SIZE
		px = ws * h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5) * depth)
	return clampf(px, SIZE, MAX_PX)


func _process(_delta: float) -> void:
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return
	var vs := get_viewport_rect().size
	if cam.global_transform != _last_xf or cam.size != _last_size or vs != _last_vp:
		_last_xf = cam.global_transform
		_last_size = cam.size
		_last_vp = vs
		queue_redraw()


func _draw() -> void:
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return
	var view := get_viewport_rect().grow(MAX_PX)
	for name in _order:
		for e in _lists[name]:
			if _hidden.has(e.uid) or cam.is_position_behind(e.pos):
				continue
			var p := cam.unproject_position(e.pos)
			if not view.has_point(p):
				continue
			var live: bool = e.kind == "issue" or (e.kind != "rescue" and _is_live(e.kind))
			var col: Color = e.color
			var sel: bool = _sel.has(e.uid) and e.kind != "issue" and e.kind != "rescue"
			if sel and int(e.sub) == 0:
				col = SELECTED_COLOR
			if not live and e.kind != "rescue":
				col.a *= DIM
			var px := pixel_size(e, cam)
			_shape(int(e.shape), p, px, col)
			var hov: bool = _hover[0] == e.kind and _hover[1] == e.uid and _hover[2] == e.sub
			if hov or sel:
				draw_arc(p, px * 0.5 + 3.0, 0.0, TAU, 24, HOVER_COLOR if hov else Color(1, 1, 1, col.a), 2.0, true)


# ---------------------------------------------------------------- internals

func _is_live(kind: String) -> bool:
	return _all_live or _live.has(kind)


func _pick(screen: Vector2, cam: Camera3D, only: Dictionary, use_only: bool) -> Dictionary:
	if cam == null or not cam.is_inside_tree():
		return {}
	var best := {}
	var best_d := INF
	for name in _order:
		if name == RESCUES:
			continue
		for e in _lists[name]:
			var pin: bool = e.kind == "issue"
			if not pin:
				if _hidden.has(e.uid):
					continue
				if use_only:
					if not only.has(e.kind):
						continue
				elif not _is_live(e.kind):
					continue
			if cam.is_position_behind(e.pos):
				continue
			var d := cam.unproject_position(e.pos).distance_to(screen)
			var reach := maxf(PICK_PX, pixel_size(e, cam) * 0.5)
			if d > reach or d >= best_d:
				continue
			best_d = d
			best = {"kind": e.kind, "uid": e.uid, "sub": e.sub, "pos": e.pos}
			if pin:
				best["issue"] = _issues[int(e.uid) - 1]
	return best


func _shape(shape: int, p: Vector2, px: float, col: Color) -> void:
	var r := px * 0.5
	var edge := Color(0, 0, 0, col.a * 0.8)
	match shape:
		Shape.DOT:
			draw_circle(p, r, col)
			draw_arc(p, r, 0.0, TAU, 20, edge, 1.0, true)
		Shape.SQUARE:
			var rc := Rect2(p - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6)
			draw_rect(rc, col)
			draw_rect(rc, edge, false, 1.0)
		Shape.DIAMOND:
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, edge, 1.0, true)
		Shape.TRIANGLE:
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r * 0.8), p + Vector2(-r, r * 0.8)])
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, edge, 1.0, true)
		Shape.RING:
			draw_arc(p, r * 0.85, 0.0, TAU, 24, col, maxf(2.0, r * 0.3), true)
		Shape.PLUS:
			draw_circle(p, r * 0.8, Color(0, 0, 0, col.a * 0.45))
			draw_line(p - Vector2(r * 0.6, 0), p + Vector2(r * 0.6, 0), col, 2.0)
			draw_line(p - Vector2(0, r * 0.6), p + Vector2(0, r * 0.6), col, 2.0)
		Shape.PIN:
			# a "!" flag on a stem: the point is the stem's foot
			var head := p - Vector2(0, r * 1.6)
			draw_line(p, head, col, 2.0)
			draw_circle(head, r * 0.8, col)
			draw_line(head - Vector2(0, r * 0.45), head + Vector2(0, r * 0.1), Color(0, 0, 0, col.a), 2.0)
			draw_circle(head + Vector2(0, r * 0.38), 1.2, Color(0, 0, 0, col.a))
		Shape.BAR:
			var rc := Rect2(p - Vector2(r * 0.3, r), Vector2(r * 0.6, r * 2.0))
			draw_rect(rc, col)
			draw_rect(rc, edge, false, 1.0)
		Shape.SUN:
			draw_circle(p, r * 0.5, col)
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(p + d * r * 0.65, p + d * r, col, 1.5)
		_:
			draw_circle(p, r, col)
