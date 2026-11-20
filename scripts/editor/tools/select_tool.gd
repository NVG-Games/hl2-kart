class_name SelectTool
extends EditorTool
## 1 SELECT (1.5): click / Shift / Ctrl (TrackEditor's common rule), a box drawn from empty space
## (SELECT only; Shift adds), the gizmo for everything that has a position (Alt + drag duplicates),
## a free item's marker dragged along the ground (Shift + drag: its height), an anchored item's
## marker slid along its road through its owner tool's slide() (7.6). TrackEditor calls the statics
## for the global shortcuts in every tool: copy / cut / paste / paste in place (JSON in
## EditorSession.clipboard and the OS clipboard; pasted JSON goes through LevelDoc.sanitize_items),
## duplicate, delete (each kind through its owner's delete_ops), PgUp / PgDn (merged within 1 s),
## End / Shift+End. Another tool may borrow the gizmo with gizmo_on() / gizmo_off(). P8.

## The tool that owns each kind (7.6): its slide(), delete_ops() and item_aabb() are asked.
const OWNERS := {"road_point": "road", "handle": "road", "segment": "road", "segment_mid": "road", "start": "road",
	"branch": "branch", "branch_point": "branch", "prop": "objects", "light": "objects", "fire": "objects",
	"screen": "objects", "item_row": "items", "crate": "items", "pad": "items", "barrels": "items", "zone": "items",
	"hazard": "hazards", "hazard_point": "hazards", "crowd": "crowds", "egg": "crowds", "lake": "terrain"}
## Kinds with a position of their own: the gizmo, marker drags, PgUp / PgDn and End move them.
const FREE := ["road_point", "branch_point", "prop", "light", "fire", "screen", "crate", "egg", "lake"]
## Kinds whose marker slides along a road (anchored items, the start, branch ends) or is the road
## tool's own (handles, segments): the owner's slide() moves them.
const SLIDE := ["item_row", "pad", "barrels", "zone", "hazard", "hazard_point", "crowd", "branch", "start",
	"handle", "segment", "segment_mid"]
## The document list of each kind that copy / paste / delete handle as list items.
const SECTION_OF := {"prop": "props", "light": "lights", "fire": "fires", "screen": "screens", "item_row": "items",
	"crate": "crates", "pad": "pads", "barrels": "barrels", "zone": "zones", "hazard": "hazards", "crowd": "crowds",
	"egg": "eggs", "lake": "lakes"}
## The anchor keys of a list item ("zone" is a pair).
const ANCHOR_KEYS := ["at", "a", "b"]
## Kinds that drop onto the surface below while moved with SURFACE on.
const SURFACE_KINDS := ["prop", "fire", "egg", "crate"]
const YAW_KINDS := ["prop", "screen", "egg"]
const CLIP_KIND := "hl2kart_clip"
const NUDGE_KEY := "nudge_height"
const ALIGN_MAX := 30.0
const Y_MIN := -500.0
const Y_MAX := 1500.0
## Shift + drag of a marker: metres per px = distance x this.
const HEIGHT_PER_PX := 0.004
const BOX_FILL := Color(1.0, 0.61, 0.0, 0.12)
const BOX_LINE := Color8(255, 155, 0)

var _box := {}          # {from, to, add}
var _box_ctl: Control
var _move := {}         # a marker drag of free items
var _slide := {}        # {uid, tool}
var _gz := {}           # the gizmo drag
var _bound := false


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "select"
	title = "SELECT"
	purpose = "Select, move, rotate and scale anything; drag a box to select many"


## SELECT owns no kind: TrackEditor makes every kind live ("*") while it is active.
func kinds() -> PackedStringArray:
	return PackedStringArray()


func activate() -> void:
	gizmo_on()


func deactivate() -> void:
	_cancel()
	gizmo_off()


func options(box: VBoxContainer) -> void:
	if editor == null or editor.gizmo == null:
		return
	var ids := ["move", "rotate", "scale"]
	box.add_child(EditorKit.modes(["MOVE", "ROTATE", "SCALE"], maxi(ids.find(editor.gizmo.mode), 0),
		func(i: int) -> void: editor.gizmo.mode = ids[i]))
	box.add_child(EditorKit.toggle("LOCAL AXES", editor.gizmo.local, func(on: bool) -> void: editor.gizmo.local = on))
	box.add_child(EditorKit.hint("{ed_move} {ed_rotate} {ed_scale} MODE · {ed_space} AXES · {ed_mod_alt} + DRAG A HANDLE: DUPLICATE · {ed_mod_ctrl} DRAG: INVERT GRID"))


func hints(hit: EditorHit) -> Array:
	if hit == null or not hit.hit:
		return [["CLICK DESELECT"], ["DRAG BOX SELECT"], ["{ed_mod_shift} DRAG ADD"]]
	match hit.what:
		"gizmo":
			var verb: String = {"move": "MOVE", "rotate": "ROTATE", "scale": "SCALE"}.get(editor.gizmo.mode if editor.gizmo != null else "move", "MOVE")
			return [["DRAG %s" % verb], ["{ed_mod_alt} DRAG DUPLICATE"], ["{ed_mod_ctrl} INVERT GRID"]]
		"marker", "prop":
			var k := _kind(hit)
			if k == "issue":
				return [["CLICK SHOW THE PROBLEM"]]
			if k in SLIDE:
				return [["CLICK SELECT"], ["DRAG SLIDE ALONG THE ROAD"], ["{ed_mod_ctrl} CLICK TOGGLE"], ["{ed_delete} DELETE"]]
			return [["CLICK SELECT"], ["DRAG MOVE"], ["{ed_mod_shift} DRAG HEIGHT"], ["{ed_mod_ctrl} CLICK TOGGLE"], ["{ed_delete} DELETE"]]
	return [["CLICK DESELECT"], ["DRAG BOX SELECT"], ["{ed_mod_shift} DRAG ADD"]]


## Double click: frames the item.
func double_click(hit: EditorHit, _mods: int) -> bool:
	if (hit.what == "marker" or hit.what == "prop") and hit.uid > 0 and editor.kind_of(hit.uid) != "":
		editor.frame(item_box(editor, hit.uid))
		return true
	return false


func drag_begin(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null:
		return false
	if (hit.what == "marker" or hit.what == "prop") and hit.uid > 0:
		var k := _kind(hit)
		if k == "issue" or k == "rescue":
			return false
		if k in SLIDE:
			return _slide_begin(k, hit)
		if editor.kind_of(hit.uid) in FREE:
			if not editor.selection.has(hit.uid):
				editor.select(PackedInt32Array([hit.uid]), has_mod(mods, MOD_SHIFT))
			return _move_begin(hit, mods)
		return false
	_box = {"from": hit.screen, "to": hit.screen, "add": has_mod(mods, MOD_SHIFT)}
	_show_box()
	return true


func drag_move(hit: EditorHit, _mods: int) -> void:
	if not _slide.is_empty():
		_slide_step(hit, 1)
	elif not _move.is_empty():
		_move_step(hit, false)
	elif not _box.is_empty():
		_box.to = hit.screen
		_show_box()


func drag_end(hit: EditorHit, _mods: int) -> void:
	if not _slide.is_empty():
		_slide_step(hit, 2)
		editor.history.end_gesture()
		_slide = {}
		succeeded()
	elif not _move.is_empty():
		_move_step(hit, true)
	elif not _box.is_empty():
		_box.to = hit.screen
		box_select(Rect2(_box.from, (_box.to as Vector2) - (_box.from as Vector2)).abs(), bool(_box.add))
		_box = {}
		_show_box()


func on_doc_changed(_sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	if editor == null or editor.doc == null or editor.selection == null:
		return
	if _gz.is_empty() and _move.is_empty():
		# an undo can take selected items away
		editor.selection.keep_only(func(u: int) -> bool: return editor.kind_of(u) != "")
		if _bound:
			sync_gizmo()


# ---------------------------------------------------------------- the gizmo

## Shows the gizmo on the selection's movable items and follows the selection.
func gizmo_on() -> void:
	if _bound or editor == null or editor.gizmo == null or editor.selection == null:
		return
	_bound = true
	editor.selection.changed.connect(sync_gizmo)
	editor.gizmo.moved.connect(_on_gizmo_moved)
	editor.gizmo.drag_started.connect(_on_gizmo_started)
	sync_gizmo()


func gizmo_off() -> void:
	if not _bound:
		return
	_bound = false
	if editor.selection.changed.is_connected(sync_gizmo):
		editor.selection.changed.disconnect(sync_gizmo)
	if editor.gizmo.moved.is_connected(_on_gizmo_moved):
		editor.gizmo.moved.disconnect(_on_gizmo_moved)
	if editor.gizmo.drag_started.is_connected(_on_gizmo_started):
		editor.gizmo.drag_started.disconnect(_on_gizmo_started)
	editor.gizmo.detach()


## Attaches the gizmo at the centre of the selection's movable items (anchored items have none);
## LOCAL axes are the first prop's; pitch and roll rings only when every one is a prop.
func sync_gizmo() -> void:
	if editor == null or editor.gizmo == null or not _gz.is_empty():
		return
	var free := free_uids(editor, editor.selection.uids)
	if free.is_empty():
		editor.gizmo.detach()
		return
	var all_props := true
	var b := Basis()
	var have_b := false
	for u in free:
		var st := state_of(editor, u)
		if st.kind != "prop":
			all_props = false
		elif not have_b:
			b = st.basis
			have_b = true
	editor.gizmo.attach(Transform3D(b, selection_center(editor, free)), all_props)


func _on_gizmo_started(handle: int, duplicate: bool) -> void:
	var uids := free_uids(editor, editor.selection.uids)
	if uids.is_empty():
		return
	var mode := editor.gizmo.mode
	_gz = {"handle": handle, "mode": mode, "items": [], "name": ""}   # (guards sync_gizmo)
	var copyable := PackedInt32Array()
	if duplicate:
		for u in uids:
			if SECTION_OF.has(editor.kind_of(u)):
				copyable.append(u)
	var nm := "%s %s" % [{"move": "MOVE", "rotate": "ROTATE", "scale": "SCALE"}.get(mode, "MOVE"), noun(editor, uids)]
	if not copyable.is_empty():
		nm = "DUPLICATE %s" % noun(editor, copyable)
	_gz.name = nm
	# one step: the copies (Alt) and every move of the drag
	editor.history.begin_gesture(nm)
	if not copyable.is_empty():
		var made := paste_clip(editor, clip_of(editor, copyable), "offset", Vector3.ZERO, 0.0, nm)
		if not made.is_empty():
			uids = made
	var states := []
	for u in uids:
		states.append(state_of(editor, u))
	_gz.items = states


func _on_gizmo_moved(delta: Transform3D, final: bool) -> void:
	if _gz.is_empty():
		return
	var ops := []
	var exclude := PackedInt32Array()
	for st in _gz.items:
		exclude.append(int(st.uid))
	var drop: bool = bool(editor.snap.get("surface", false)) and _gz.mode == "move" \
		and int(_gz.handle) in [Gizmo3D.X_AXIS, Gizmo3D.Z_AXIS, Gizmo3D.XZ_PLANE, Gizmo3D.VIEW_PLANE]
	for st in _gz.items:
		ops.append_array(transform_ops(editor, st, delta, _gz.mode, drop, exclude))
	if not ops.is_empty():
		editor.commit(_gz.name, ops, "gizmo")
	_preview(_gz.items, final)
	if final:
		editor.history.end_gesture()
		_gz = {}
		sync_gizmo()
		succeeded()


# ---------------------------------------------------------------- marker drags

func _move_begin(hit: EditorHit, mods: int) -> bool:
	var uids := free_uids(editor, editor.selection.uids)
	if uids.is_empty():
		return false
	var states := []
	var anchor := {}
	for u in uids:
		var st := state_of(editor, u)
		states.append(st)
		if int(st.uid) == hit.uid:
			anchor = st
	if anchor.is_empty():
		anchor = states[0]
	var plane: Vector3 = anchor.pos
	var nm := "MOVE %s" % noun(editor, uids)
	_move = {"items": states, "anchor": anchor, "plane": plane, "height": has_mod(mods, MOD_SHIFT),
		"screen": hit.screen, "start": _plane_point(hit, plane.y, plane), "name": nm}
	editor.history.begin_gesture(nm)
	return true


func _move_step(hit: EditorHit, final: bool) -> void:
	var off := Vector3.ZERO
	var plane: Vector3 = _move.plane
	if _move.height:
		var cam := editor.camera
		var mpp := Gizmo3D.world_per_px(cam, plane) if cam != null and cam.is_inside_tree() else HEIGHT_PER_PX * 30.0
		off.y = ((_move.screen as Vector2).y - hit.screen.y) * mpp
		var g := grid_of(editor)
		if g > 0.0:
			off.y = snappedf(plane.y + off.y, g) - plane.y
	else:
		var p := _plane_point(hit, plane.y, Vector3(NAN, NAN, NAN))
		if not is_nan(p.x):
			off = p - (_move.start as Vector3)
			off.y = 0.0
			var g := grid_of(editor)
			if g > 0.0:
				off.x = snappedf(plane.x + off.x, g) - plane.x
				off.z = snappedf(plane.z + off.z, g) - plane.z
	var exclude := PackedInt32Array()
	for st in _move.items:
		exclude.append(int(st.uid))
	var drop: bool = not _move.height and bool(editor.snap.get("surface", false))
	var ops := []
	for st in _move.items:
		ops.append_array(transform_ops(editor, st, Transform3D(Basis(), off), "move", drop, exclude))
	if not ops.is_empty():
		editor.commit(_move.name, ops, "drag")
	_preview(_move.items, final)
	if final:
		editor.history.end_gesture()
		_move = {}
		sync_gizmo()
		succeeded()


## Where the cursor's ray meets the horizontal plane at height y (a drag never climbs the item it
## moves).
static func _plane_point(hit: EditorHit, y: float, miss: Vector3) -> Vector3:
	var rd := hit.ray_dir
	if absf(rd.y) < 1e-4:
		return miss
	var t := (y - hit.ray_from.y) / rd.y
	if t < 0.0:
		return miss
	return hit.ray_from + rd * t


func _slide_begin(kind: String, hit: EditorHit) -> bool:
	var t := owner_tool(editor, kind)
	if t == null:
		return false
	_slide = {"uid": hit.uid, "tool": t, "kind": kind}
	editor.history.begin_gesture("MOVE %s" % kind.to_upper().replace("_", " "))
	_slide_step(hit, 0)
	return true


func _slide_step(hit: EditorHit, phase: int) -> void:
	var t: EditorTool = _slide.tool
	var ops := t.slide(int(_slide.uid), hit, phase)
	if not ops.is_empty():
		editor.commit("MOVE %s" % str(_slide.kind).to_upper().replace("_", " "), ops, "slide")


## A road point move shows the moved stretch at once; the gesture's end settles it (3.11).
func _preview(states: Array, final: bool) -> void:
	var roads := {}
	for st in states:
		if st.kind == "road_point" or st.kind == "branch_point":
			var list: PackedInt32Array = roads.get(st.road, PackedInt32Array())
			list.append(int(st.uid))
			roads[st.road] = list   # (a packed array is a value: store it back)
	if roads.is_empty() or not editor.is_inside_tree() or editor.view == null:
		return
	for key in roads:
		if final:
			editor.settle(int(key), roads[key])
		else:
			editor.preview_roads(int(key), roads[key])


# ---------------------------------------------------------------- box select

## Selects what lies in a screen rectangle: live markers (pick_rect) and every positioned item whose
## origin projects inside; hidden ones never. `add`: Shift.
func box_select(rect: Rect2, add: bool) -> void:
	var cam := editor.camera
	var out := PackedInt32Array()
	if cam != null and cam.is_inside_tree():
		if editor.markers != null:
			for e in editor.markers.pick_rect(rect, cam):
				var k := str(e.get("kind", ""))
				var u := int(e.get("uid", 0))
				if u > 0 and not (k in ["issue", "rescue", "handle", "segment", "segment_mid", "start"]) \
						and editor.kind_of(u) != "" and not (u in out):
					out.append(u)
		var hidden := editor.session.hidden if editor.session != null else PackedInt32Array()
		for pair in positioned(editor.doc):
			var u: int = pair[0]
			var p: Vector3 = pair[1]
			if u in out or u in hidden or cam.is_position_behind(p):
				continue
			if rect.has_point(cam.unproject_position(p)):
				out.append(u)
	if add:
		editor.select(out, true)
	else:
		editor.select(out)


func _show_box() -> void:
	if _box_ctl == null:
		if _box.is_empty():
			return
		_box_ctl = BoxRect.new()
		_box_ctl.name = "SelectBox"
		var parent: Node = editor.markers.get_parent() if editor.markers != null and editor.markers.get_parent() != null else editor
		parent.add_child(_box_ctl)
	if _box.is_empty():
		_box_ctl.visible = false
		return
	(_box_ctl as BoxRect).rect = Rect2(_box.from, (_box.to as Vector2) - (_box.from as Vector2)).abs()
	_box_ctl.visible = true
	_box_ctl.queue_redraw()


## A move, slide or gizmo drag of SELECT is running (its gesture is open): undo and the edit keys
## wait (TrackEditor.pressing).
func dragging() -> bool:
	return not _move.is_empty() or not _slide.is_empty() or not _gz.is_empty()


## Ends every drag of SELECT where it is (its gesture closed, nothing taken back).
func end_drags() -> void:
	_cancel()
	sync_gizmo()


## Esc mid-drag (TrackEditor.end_press): the box goes, a move or slide is taken back.
func cancel_drag() -> void:
	var live := not _move.is_empty() or not _slide.is_empty()
	var states: Array = _move.get("items", []) if not _move.is_empty() else []
	_move = {}
	_slide = {}
	if live:
		editor.history.cancel_gesture()
	if not states.is_empty():
		_preview(states, true)
	if not _box.is_empty():
		_box = {}
		_show_box()
	sync_gizmo()


## The gizmo's drag was stopped without its last move (Esc): its step taken back.
func cancel_gizmo() -> void:
	if _gz.is_empty():
		return
	var states: Array = _gz.get("items", [])
	_gz = {}
	editor.history.cancel_gesture()
	_preview(states, true)
	sync_gizmo()


func _cancel() -> void:
	if not _move.is_empty():
		editor.history.end_gesture()
		_move = {}
	if not _slide.is_empty():
		editor.history.end_gesture()
		_slide = {}
	if not _gz.is_empty():
		editor.history.end_gesture()
		_gz = {}
	if not _box.is_empty():
		_box = {}
		_show_box()


func _kind(hit: EditorHit) -> String:
	if hit.what == "marker" and hit.kind != "":
		return hit.kind
	return editor.kind_of(hit.uid)


# ---------------------------------------------------------------- items (statics)

## The owner tool of a kind: the tool whose kinds() has it, else 7.6's table.
static func owner_tool(ed: TrackEditor, kind: String) -> EditorTool:
	for t in ed.tools.values():
		if t is EditorTool and (t as EditorTool).id != "select" and kind in (t as EditorTool).kinds():
			return t
	return ed.tools.get(OWNERS.get(kind, ""), null)


## The uids among `uids` with a position of their own (FREE kinds).
static func free_uids(ed: TrackEditor, uids: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in uids:
		if ed.kind_of(u) in FREE:
			out.append(u)
	return out


## {uid, kind, path, road, pos, yaw, pitch, roll, scale, tag, basis} of a document item ({} none).
static func state_of(ed: TrackEditor, uid: int) -> Dictionary:
	var f := ed.doc.find(uid) if ed.doc != null else {}
	if f.is_empty():
		return {}
	var it: Dictionary = f.item
	var k := ed.kind_of(uid)
	var st := {"uid": uid, "kind": k, "path": (f.path as Array).duplicate(), "road": int(f.get("road", -2))}
	if k == "lake":
		var c = it.get("center", [0.0, 0.0])
		st.pos = Vector3(float(c[0]), float(it.get("level", 0.0)), float(c[1])) if c is Array and c.size() >= 2 else Vector3.ZERO
	else:
		st.pos = _v3(it.get("pos"))
	st.yaw = float(it.get("yaw", 0.0))
	st.pitch = float(it.get("pitch", 0.0))
	st.roll = float(it.get("roll", 0.0))
	st.scale = float(it.get("scale", 1.0))
	st.tag = str(it.get("tag", ""))
	st.basis = Basis.from_euler(Vector3(deg_to_rad(st.pitch), deg_to_rad(st.yaw), deg_to_rad(st.roll)))
	return st


## The ops that put an item (its state at the drag's start) where `d` takes it: the position, and
## for a rotate the yaw (props: yaw, pitch and roll), for a scale the props' scale. `drop`: onto
## the surface below (SURFACE kinds).
static func transform_ops(ed: TrackEditor, st: Dictionary, d: Transform3D, mode: String, drop := false, exclude := PackedInt32Array()) -> Array:
	if st.is_empty():
		return []
	var ops := []
	var p1: Vector3 = d * (st.pos as Vector3)
	var kind: String = st.kind
	if drop and kind in SURFACE_KINDS:
		var s := surface_below(ed, p1 + Vector3.UP * 2.0, exclude)
		if not s.is_empty():
			p1.y = (s.pos as Vector3).y + (0.5 if kind == "crate" else 0.0)
	p1.y = clampf(p1.y, Y_MIN, Y_MAX)
	ops.append_array(pos_ops(st, p1))
	var path: Array = st.path
	if mode == "rotate" and kind in YAW_KINDS:
		if kind == "prop":
			var e := (d.basis.orthonormalized() * (st.basis as Basis)).get_euler()
			ops.append(LevelDoc.op_set(path + ["yaw"], _wrap(rad_to_deg(e.y))))
			if absf(rad_to_deg(e.x)) > 1e-3 or absf(float(st.pitch)) > 1e-3:
				ops.append(LevelDoc.op_set(path + ["pitch"], clampf(rad_to_deg(e.x), -90.0, 90.0)))
			if absf(rad_to_deg(e.z)) > 1e-3 or absf(float(st.roll)) > 1e-3:
				ops.append(LevelDoc.op_set(path + ["roll"], clampf(rad_to_deg(e.z), -90.0, 90.0)))
		else:
			ops.append(LevelDoc.op_set(path + ["yaw"], _wrap(float(st.yaw) + rad_to_deg(d.basis.orthonormalized().get_euler().y))))
	elif mode == "scale" and kind == "prop":
		var f := d.basis.get_scale().x
		var lo := 0.1 if st.tag == "far" else 0.25
		var hi := 150.0 if st.tag == "far" else 4.0
		ops.append(LevelDoc.op_set(path + ["scale"], clampf(snappedf(float(st.scale) * f, 0.05), lo, hi)))
	return ops


## The ops that set an item's position (a lake: its centre and level).
static func pos_ops(st: Dictionary, p: Vector3) -> Array:
	var path: Array = st.path
	if st.kind == "lake":
		return [LevelDoc.op_set(path + ["center"], [p.x, p.z]), LevelDoc.op_set(path + ["level"], p.y)]
	return [LevelDoc.op_set(path + ["pos"], [p.x, p.y, p.z])]


## The centre of the items' positions (the selection's movable items when uids is empty), NAN when
## none has one.
static func selection_center(ed: TrackEditor, uids := PackedInt32Array()) -> Vector3:
	var list := uids if not uids.is_empty() else free_uids(ed, ed.selection.uids)
	var box := AABB()
	var first := true
	for u in list:
		var st := state_of(ed, u)
		if st.is_empty() or not (st.kind in FREE):
			continue
		if first:
			box = AABB(st.pos, Vector3.ZERO)
			first = false
		else:
			box = box.expand(st.pos)
	return Vector3(NAN, NAN, NAN) if first else box.get_center()


## The box of an item for framing (its owner's item_aabb, the view's node, else 4 m round it).
static func item_box(ed: TrackEditor, uid: int) -> AABB:
	var t := owner_tool(ed, ed.kind_of(uid))
	if t != null:
		var b := t.item_aabb(uid)
		if b.has_volume():
			return b
	if ed.view != null:
		var vb := ed.view.item_aabb(uid)
		if vb.has_volume():
			return vb
	var st := state_of(ed, uid)
	if st.is_empty():
		return AABB()
	return AABB((st.pos as Vector3) - Vector3.ONE * 2.0, Vector3.ONE * 4.0)


## [uid, position] of every item with a position of its own (points, props, lights, fires,
## screens, crates, eggs, lakes).
static func positioned(doc: LevelDoc) -> Array:
	var out := []
	if doc == null:
		return out
	var lists: Array = [doc.data.get("road", {}).get("points", [])]
	for br in doc.data.get("branches", []):
		if br is Dictionary:
			lists.append(br.get("points", []))
	for sec in ["props", "lights", "fires", "screens", "crates", "eggs"]:
		lists.append(doc.data.get(sec, []))
	for list in lists:
		if not (list is Array):
			continue
		for it in list:
			if it is Dictionary and int(it.get("uid", 0)) > 0 and it.get("pos") is Array:
				out.append([int(it.uid), _v3(it.pos)])
	for lk in doc.data.get("lakes", []):
		if lk is Dictionary and lk.get("center") is Array and (lk.center as Array).size() >= 2:
			out.append([int(lk.get("uid", 0)), Vector3(float(lk.center[0]), float(lk.get("level", 0.0)), float(lk.center[1]))])
	return out


## "POINT" / "3 POINTS" / "OBJECT" / "12 OBJECTS" for step names and toasts.
static func noun(ed: TrackEditor, uids: PackedInt32Array) -> String:
	var points := true
	for u in uids:
		if not (ed.kind_of(u) in ["road_point", "branch_point"]):
			points = false
			break
	var word := "POINT" if points else "OBJECT"
	if uids.size() == 1:
		return word
	return "%d %sS" % [uids.size(), word]


## The grid step of moves and PgUp / PgDn: the grid size with the grid on, else 1 m (0 = no snap
## for drags: grid_of(ed, false)).
static func grid_of(ed: TrackEditor, off_is_one := false) -> float:
	var on := bool(ed.snap.get("on", true))
	var g := float(ed.snap.get("grid", 1.0)) if not (ed.snap.get("grid") is bool) else float(ed.snap.get("size", 1.0))
	if on and g > 0.0:
		return g
	return 1.0 if off_is_one else 0.0


## The first surface under `from` (physics: road, props, terrain collision; then the terrain's
## heights): {pos, normal}, {} when there is none. The bodies of `exclude` uids do not count.
static func surface_below(ed: TrackEditor, from: Vector3, exclude := PackedInt32Array()) -> Dictionary:
	var best := {}
	if ed.is_inside_tree():
		var space := ed.get_world_3d().direct_space_state
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3000.0, TrackEditor.PICK_MASK)
			var rids: Array[RID] = []
			if ed.view != null:
				for u in exclude:
					var n := ed.view.node_of(u)
					if n != null:
						_bodies(n, rids)
			q.exclude = rids
			var r := space.intersect_ray(q)
			if not r.is_empty():
				best = {"pos": r.position, "normal": r.normal}
	var t := ed.terrain()
	if t != null:
		var h := t.height_at(from.x, from.z)
		if not is_nan(h) and h <= from.y and (best.is_empty() or h > (best.pos as Vector3).y + 0.01):
			best = {"pos": Vector3(from.x, h, from.z), "normal": t.normal_at(from.x, from.z)}
	return best


static func _bodies(n: Node, out: Array[RID]) -> void:
	if n is CollisionObject3D:
		out.append((n as CollisionObject3D).get_rid())
	for c in n.get_children():
		_bodies(c, out)


# ---------------------------------------------------------------- the global shortcuts

## Ctrl+C / Ctrl+X: the selected list items as JSON (positions relative to their centre; anchored
## items keep their lap-metre offsets) into EditorSession.clipboard and the OS clipboard. Road
## points and branches are not copied.
static func copy_selection(ed: TrackEditor, cut := false) -> void:
	if ed == null or ed.doc == null:
		return
	var clip := clip_of(ed, ed.selection.uids)
	var n: int = (clip.items as Array).size()
	if n == 0:
		ed.toast("Road points and branches are not copied." if int(clip.skipped) > 0 else "Nothing to copy.")
		return
	if ed.session != null:
		ed.session.clipboard = [clip]
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(JSON.stringify(clip))
	var uids := PackedInt32Array()
	for e in clip.items:
		uids.append(int(e.uid))
	if cut:
		_delete(ed, uids, "CUT %s" % noun(ed, uids))
		ed.toast("Cut %d object%s" % [n, "" if n == 1 else "s"])
	else:
		ed.toast("Copied %d object%s" % [n, "" if n == 1 else "s"])


## Ctrl+V at the cursor's hit point (anchored items re-anchor at the nearest road spot), Ctrl+Shift+V
## in place; the OS clipboard's JSON (another track's copy) first, through LevelDoc.sanitize_items.
static func paste(ed: TrackEditor, in_place := false) -> void:
	if ed == null or ed.doc == null:
		return
	var clip := read_clipboard(ed)
	if clip.is_empty() or (clip.get("items", []) as Array).is_empty():
		ed.toast("Nothing to paste.")
		return
	var made: PackedInt32Array
	if in_place:
		made = paste_clip(ed, clip, "in_place", _v3(clip.get("center")), 0.0, "PASTE")
	else:
		made = paste_clip(ed, clip, "cursor", cursor_point(ed, _v3(clip.get("center"))), 0.0, "PASTE")
	if not made.is_empty():
		ed.toast("Pasted %d object%s" % [made.size(), "" if made.size() == 1 else "s"])


## Ctrl+D: copies offset by two grid steps along the camera's right (anchored items: along the road).
static func duplicate_selection(ed: TrackEditor) -> void:
	if ed == null or ed.doc == null:
		return
	var clip := clip_of(ed, ed.selection.uids)
	if (clip.items as Array).is_empty():
		ed.toast("Road points and branches are not copied." if int(clip.skipped) > 0 else "Nothing to duplicate.")
		return
	var step := grid_of(ed, true) * 2.0
	var right := Vector3.RIGHT
	if ed.camera != null:
		right = Vector3(ed.camera.global_basis.x.x, 0.0, ed.camera.global_basis.x.z)
		right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	var uids := PackedInt32Array()
	for e in clip.items:
		uids.append(int(e.uid))
	paste_clip(ed, clip, "offset", right * step, step, "DUPLICATE %s" % noun(ed, uids))


## Delete / Backspace: each uid through its owner tool's delete_ops (road points re-anchor through
## LevelDoc.delete_point_ops), one undo step.
static func delete_selection(ed: TrackEditor) -> void:
	if ed == null or ed.doc == null or ed.selection.uids.is_empty():
		return
	var uids := ed.selection.uids.duplicate()
	_delete(ed, uids, "DELETE %s" % noun(ed, uids))
	ed.selection.clear()


static func _delete(ed: TrackEditor, uids: PackedInt32Array, step_name: String) -> void:
	var groups := {}
	for u in uids:
		var k := ed.kind_of(u)
		if k == "" or k == "start":
			continue
		var t := owner_tool(ed, k)
		var key: String = t.id if t != null else ""
		var list: PackedInt32Array = groups.get(key, PackedInt32Array())
		list.append(u)
		groups[key] = list
	if groups.is_empty():
		return
	ed.history.begin_gesture(step_name)
	for key in groups:
		var t: EditorTool = ed.tools.get(key, null)
		# the owner's own refusal (a closed loop keeps 3 points) holds here too
		if t != null and t.has_method("refuse_delete") and t.call("refuse_delete", groups[key]):
			continue
		var ops := t.delete_ops(groups[key]) if t != null else []
		if not ops.is_empty():
			ed.commit(step_name, ops)
			continue
		# the owner has no delete_ops yet: each uid against the document as it is now
		for u in groups[key]:
			ed.commit(step_name, delete_ops_of(ed.doc, u))
	ed.history.end_gesture()


## The ops that remove one uid from the document (points re-anchor what sat on their segment).
static func delete_ops_of(doc: LevelDoc, uid: int) -> Array:
	var f := doc.find(uid)
	if f.is_empty():
		return []
	match str(f.section):
		"road":
			return doc.delete_point_ops(uid)
		"branches":
			if f.has("branch"):
				return doc.delete_point_ops(uid)
			return [["remove", ["branches"], "#%d" % uid]]
	return [["remove", [str(f.section)], "#%d" % uid]]


## PgUp / PgDn by the grid step (1 m with the grid off); presses within 1 s merge into one step.
static func nudge_height(ed: TrackEditor, dir: int) -> void:
	if ed == null or ed.doc == null:
		return
	var uids := free_uids(ed, ed.selection.uids)
	if uids.is_empty():
		return
	var step := grid_of(ed, true) * float(signi(dir))
	var ops := []
	var states := []
	for u in uids:
		var st := state_of(ed, u)
		states.append(st)
		var p: Vector3 = st.pos
		p.y = clampf(p.y + step, Y_MIN, Y_MAX)
		ops.append_array(pos_ops(st, p))
	ed.commit("%s %s" % ["RAISE" if dir > 0 else "LOWER", noun(ed, uids)], ops, NUDGE_KEY)
	var tool := ed.tools.get("select", null) as SelectTool
	if tool != null:
		tool._preview(states, false)
		tool._preview(states, true)


## End: the selection drops onto what is below it (points onto the natural ground); Shift+End also
## tilts props to the surface (pitch / roll, at most 30 deg).
static func drop_to_surface(ed: TrackEditor, align: bool) -> void:
	if ed == null or ed.doc == null:
		return
	var uids := free_uids(ed, ed.selection.uids)
	if uids.is_empty():
		return
	var ops := []
	var states := []
	var t := ed.terrain()
	for u in uids:
		var st := state_of(ed, u)
		var p: Vector3 = st.pos
		if st.kind == "lake":
			continue
		states.append(st)
		if st.kind == "road_point" or st.kind == "branch_point":
			var h := t.natural_at(p.x, p.z) if t != null else NAN
			if is_nan(h):
				continue
			ops.append_array(pos_ops(st, Vector3(p.x, h, p.z)))
			continue
		var s := surface_below(ed, p + Vector3.UP * 0.05, PackedInt32Array([u]))
		if s.is_empty():
			continue
		var q: Vector3 = s.pos
		ops.append_array(pos_ops(st, Vector3(p.x, q.y + (0.5 if st.kind == "crate" else 0.0), p.z)))
		if align and st.kind == "prop":
			var n: Vector3 = (s.normal as Vector3).normalized()
			var ang := rad_to_deg(n.angle_to(Vector3.UP))
			if ang > ALIGN_MAX:
				n = Vector3.UP.slerp(n, ALIGN_MAX / ang).normalized()
			var b := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, deg_to_rad(float(st.yaw)))
			var e := b.get_euler()
			ops.append(LevelDoc.op_set((st.path as Array) + ["yaw"], _wrap(rad_to_deg(e.y))))
			ops.append(LevelDoc.op_set((st.path as Array) + ["pitch"], clampf(rad_to_deg(e.x), -90.0, 90.0)))
			ops.append(LevelDoc.op_set((st.path as Array) + ["roll"], clampf(rad_to_deg(e.z), -90.0, 90.0)))
	if ops.is_empty():
		return
	ed.commit("%s %s" % ["DROP AND ALIGN" if align else "DROP", noun(ed, uids)], ops)
	var tool := ed.tools.get("select", null) as SelectTool
	if tool != null:
		tool._preview(states, false)
		tool._preview(states, true)


# ---------------------------------------------------------------- clipboard

## {kind, v, center, items: [{section, uid, item, s?, road?, anchors?}], skipped} of the list items
## among uids: free items' positions relative to the centre, anchored items with the lap metres of
## each anchor.
static func clip_of(ed: TrackEditor, uids: PackedInt32Array) -> Dictionary:
	var entries := []
	var skipped := 0
	var spots := []
	for u in uids:
		var k := ed.kind_of(u)
		var sec: String = SECTION_OF.get(k, "")
		if sec == "":
			skipped += 1
			continue
		var it: Dictionary = (ed.doc.find(u).item as Dictionary).duplicate(true)
		var e := {"section": sec, "uid": u, "item": it}
		if k == "lake" or it.get("pos") is Array:
			spots.append(state_of(ed, u).pos)
		else:
			var key := int(it.get("road", -1))
			var r := ed.road(key)
			if r == null and key != -1:
				key = -1
				r = ed.road(-1)
			var anchors := {}
			for ak in ANCHOR_KEYS:
				if it.get(ak) is Dictionary and r != null:
					anchors[ak] = r.anchor_s(it[ak])
			if it.get("zone") is Array and r != null:
				var z: Array = it.zone
				for zi in z.size():
					if z[zi] is Dictionary:
						anchors["zone%d" % zi] = r.anchor_s(z[zi])
			if anchors.is_empty() or r == null:
				skipped += 1
				continue
			var s0: float = anchors.values()[0]
			e["road"] = key
			e["s"] = s0
			e["anchors"] = anchors
			spots.append(r.pos[r.idx(s0)])
		entries.append(e)
	var c := Vector3.ZERO
	if not spots.is_empty():
		var lo := INF
		for p in spots:
			c += p
			lo = minf(lo, (p as Vector3).y)
		c /= float(spots.size())
		c.y = lo
	for e in entries:
		var it: Dictionary = e.item
		if e.section == "lakes":
			var cc: Array = it.get("center", [0.0, 0.0])
			it["center"] = [float(cc[0]) - c.x, float(cc[1]) - c.z]
			it["level"] = float(it.get("level", 0.0)) - c.y
		elif it.get("pos") is Array:
			var p := _v3(it.pos) - c
			it["pos"] = [p.x, p.y, p.z]
	return {"kind": CLIP_KIND, "v": 1, "center": [c.x, c.y, c.z], "items": entries, "skipped": skipped}


## The OS clipboard's copy when it holds one (another track's), else EditorSession.clipboard's.
static func read_clipboard(ed: TrackEditor) -> Dictionary:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		var txt := DisplayServer.clipboard_get()
		if txt.length() > 2 and txt.length() < (8 << 20) and txt.begins_with("{"):
			var v = JSON.parse_string(txt)
			if v is Dictionary and v.get("kind") == CLIP_KIND and v.get("items") is Array:
				return v
	if ed.session != null and not ed.session.clipboard.is_empty() and ed.session.clipboard[0] is Dictionary:
		return ed.session.clipboard[0]
	return {}


## Where Ctrl+V puts the copy's centre: the hover's hit, else what is under the mouse, else `fallback`.
static func cursor_point(ed: TrackEditor, fallback: Vector3) -> Vector3:
	if ed.hover != null and ed.hover.hit:
		return ed.hover.pos
	if ed.is_inside_tree() and ed.camera != null and ed.camera.is_inside_tree():
		var h := ed.pick(ed._mouse if ed._mouse.x >= 0.0 else ed.free_center())
		if h.hit:
			return h.pos
	return fallback


## Inserts a copy (one undo step `step_name`; new uids; sanitized; capped) and selects it.
## how: "cursor" (the centre at `at`; anchored items at the nearest road spot + their offsets),
## "in_place" (as copied; anchors kept when their points are here), "offset" (moved by `at`;
## anchored items `ds` metres along their road). Returns the new uids.
static func paste_clip(ed: TrackEditor, clip: Dictionary, how: String, at: Vector3, ds: float, step_name: String, select := true) -> PackedInt32Array:
	var doc := ed.doc
	var made := PackedInt32Array()
	var center := _v3(clip.get("center"))
	var report := LevelReport.new()
	var by_sec := {}
	for e in clip.get("items", []):
		if e is Dictionary and str(e.get("section", "")) in SECTION_OF.values() and e.get("item") is Dictionary:
			if not by_sec.has(e.section):
				by_sec[e.section] = []
			by_sec[e.section].append(e)
	var ops := []
	var capped := ""
	for sec in by_sec:
		var entries: Array = by_sec[sec]
		var raw := []
		for i in entries.size():
			var it: Dictionary = (entries[i].item as Dictionary).duplicate(true)
			it["uid"] = i + 1
			raw.append(it)
		var clean := LevelDoc.sanitize_items(sec, raw, report)
		var have: Array = doc.data.get(sec, []) if doc.data.get(sec) is Array else []
		if not (doc.data.get(sec) is Array):
			ops.append(LevelDoc.op_set([sec], []))
		var room := int(LevelDoc.CAPS.get(sec, 400)) - have.size()
		for it in clean:
			var idx := int(it.get("uid", 0)) - 1
			if idx < 0 or idx >= entries.size():
				continue
			if room <= 0:
				capped = sec
				break
			var e: Dictionary = entries[idx]
			if not _place(ed, it, e, how, at, ds, center):
				continue
			var nu := doc.new_uid()
			it["uid"] = nu
			ops.append(LevelDoc.op_insert([sec], -1, it))
			made.append(nu)
			room -= 1
	if capped != "":
		ed.toast("%s limit reached (%d)" % [capped.capitalize().trim_suffix("s"), int(LevelDoc.CAPS.get(capped, 0))])
	if made.is_empty():
		return made
	var nm := step_name
	if step_name == "PASTE":
		nm = "PASTE %s" % ("OBJECT" if made.size() == 1 else "%d OBJECTS" % made.size())
	ed.commit(nm, ops)
	if select:
		ed.select(made)
	return made


## Puts a cleaned copy in its place; false when an anchored item has no road to sit on here.
static func _place(ed: TrackEditor, it: Dictionary, e: Dictionary, how: String, at: Vector3, ds: float, center: Vector3) -> bool:
	if e.section == "lakes":
		var cc: Array = it.get("center", [0.0, 0.0])
		var base := center if how == "in_place" else (at if how == "cursor" else center + at)
		it["center"] = [float(cc[0]) + base.x, float(cc[1]) + base.z]
		it["level"] = float(it.get("level", 0.0)) + base.y
		return true
	if it.get("pos") is Array and not e.has("anchors"):
		var base2 := center if how == "in_place" else (at if how == "cursor" else center + at)
		var p := _v3(it.pos) + base2
		it["pos"] = [p.x, clampf(p.y, Y_MIN, Y_MAX), p.z]
		return true
	var anchors: Dictionary = e.get("anchors", {})
	if anchors.is_empty():
		return false
	var key := int(e.get("road", -1))
	var r := ed.road(key)
	if r == null:
		key = -1
		r = ed.road(-1)
	if r == null or r.n < 2:
		return false
	if it.has("road"):
		it["road"] = key
	if how == "in_place" and _anchors_here(ed, it, key):
		return true
	var s_ref := float(e.get("s", 0.0))
	var s_new := s_ref + ds
	if how == "cursor":
		s_new = r.s[r.closest(at)]
	for ak in anchors:
		var s: float = s_new + float(anchors[ak]) - s_ref
		var a := r.s_to_anchor(s)
		if a.is_empty():
			return false
		if str(ak).begins_with("zone"):
			var zi := int(str(ak).substr(4))
			if it.get("zone") is Array and zi < (it.zone as Array).size():
				it.zone[zi] = a
		else:
			it[ak] = a
	return true


## The item's anchors all name points of road `key` in this document.
static func _anchors_here(ed: TrackEditor, it: Dictionary, key: int) -> bool:
	var list: Array = []
	for ak in ANCHOR_KEYS:
		if it.get(ak) is Dictionary:
			list.append(it[ak])
	if it.get("zone") is Array:
		for z in it.zone:
			if z is Dictionary:
				list.append(z)
	for a in list:
		var f := ed.doc.find(int(a.get("p", 0)))
		if f.is_empty() or int(f.get("road", -2)) != key or not (f.section == "road" or f.has("branch")):
			return false
	return not list.is_empty()


static func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Vector3:
		return v
	return Vector3.ZERO


static func _wrap(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0


## The selection rectangle (drawn over the 3D view while a box is dragged).
class BoxRect:
	extends Control
	var rect := Rect2()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		draw_rect(rect, SelectTool.BOX_FILL, true)
		draw_rect(rect, SelectTool.BOX_LINE, false, 1.5)
