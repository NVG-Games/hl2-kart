class_name Gizmo3D
extends Node3D
## Move / rotate / scale handles (1.5): built at runtime from ArrayMesh lines and triangles,
## unshaded, drawn on top at a constant ~96 px, picked in screen space within 8 px of a projected
## handle. A drag reports `moved(delta, final)`: delta is the world transform since the drag began
## (an item's new transform = delta * its transform then), snapped by the editor's snap dict
## ({on, grid, angle, angle_on, surface}; Ctrl held inverts the grid snap). Alt + drag on a handle
## (taken here, before TrackEditor's camera orbit sees it) starts the drag with duplicate = true:
## the listener copies the selection and moves the copies. P8.

signal moved(delta: Transform3D, final: bool)
## A drag began on a handle; duplicate = Alt held (1.5: the copies move).
signal drag_started(handle: int, duplicate: bool)

## Handle ids (pick / drag).
const X_AXIS := 0
const Y_AXIS := 1
const Z_AXIS := 2
const YZ_PLANE := 3
const XZ_PLANE := 4
const XY_PLANE := 5
const VIEW_PLANE := 6
const YAW_RING := 7
const PITCH_RING := 8
const ROLL_RING := 9
const SCALE_BOX := 10
const MODES := ["move", "rotate", "scale"]
const PICK_PX := 8.0
const LENGTH_PX := 96.0
const DRAG_PX := 4.0
const RING_SEGMENTS := 64
## px of mouse travel for x e in scale drags (right / up grows).
const SCALE_PX := 100.0
## deg per px when a ring is seen edge-on (the drag follows the mouse's x).
const EDGE_DEG_PER_PX := 0.5
const AXIS_COLORS := [Color(0.95, 0.27, 0.22), Color(0.4, 0.86, 0.25), Color(0.27, 0.52, 1.0)]
const HOT := Color8(255, 155, 0)    # UiKit.ORANGE
const CENTER_COLOR := Color(1, 1, 1, 0.75)

var mode := "move":              # "move" | "rotate" | "scale"
	set(v):
		if v in MODES and v != mode:
			mode = v
			_dirty = true
var local := false:
	set(v):
		local = v
		_dirty = true
## Pitch and roll rings (props only; attach's can_rotate_all).
var rotate_all := false
## The handle under the mouse (-1 none), drawn orange.
var hover := -1
## The handle being dragged (-1 none).
var dragging := -1
## The last delta `moved` sent.
var last_delta := Transform3D()

var _xf := Transform3D()         # where it is attached (origin + the LOCAL frame)
var _live := Transform3D()       # where it is drawn (follows a drag)
var _drag := {}
var _own := {}                   # an Alt + drag taken in _unhandled_input
var _dirty := true
var _mi: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	visible = false
	_ensure_mesh()


func attach(xf: Transform3D, can_rotate_all: bool) -> void:
	_xf = Transform3D(xf.basis.orthonormalized(), xf.origin)
	_live = _xf
	if can_rotate_all != rotate_all:
		rotate_all = can_rotate_all
		_dirty = true
	visible = true
	_place(null)


func detach() -> void:
	visible = false
	hover = -1
	if not _drag.is_empty():
		_drag = {}
		dragging = -1
	_own = {}


## Where it is attached (the drag start's frame).
func attached() -> Transform3D:
	return _xf


## Handle id or -1 (8 px).
func pick(screen: Vector2, cam: Camera3D) -> int:
	if not visible or cam == null or not cam.is_inside_tree():
		return -1
	var o := _live.origin
	if cam.is_position_behind(o):
		return -1
	var length := _length(cam, o)
	var ax := _axes()
	var best := -1
	var best_d := PICK_PX
	for h in handles():
		var d := _distance(h, screen, cam, o, length, ax)
		if d < best_d:
			best_d = d
			best = h
	return best


## The handles of the current mode, in pick order.
func handles() -> PackedInt32Array:
	match mode:
		"rotate":
			return PackedInt32Array([YAW_RING, PITCH_RING, ROLL_RING]) if rotate_all else PackedInt32Array([YAW_RING])
		"scale":
			return PackedInt32Array([SCALE_BOX])
	return PackedInt32Array([VIEW_PLANE, X_AXIS, Y_AXIS, Z_AXIS, YZ_PLANE, XZ_PLANE, XY_PLANE])


## phase 0 begins at `screen` (the press), 1 moves, 2 ends; `snap` is TrackEditor.snap (+ duplicate).
func drag(handle: int, screen: Vector2, cam: Camera3D, phase: int, snap: Dictionary) -> void:
	if cam == null:
		return
	if phase == 0 or _drag.is_empty():
		_begin(handle, screen, cam, snap)
		if phase == 0:
			return
	var d := _delta(screen, cam, snap)
	last_delta = d
	var b := _xf.basis
	if mode == "rotate":
		b = (d.basis.orthonormalized() * _xf.basis).orthonormalized()
	_live = Transform3D(b, d * _xf.origin)
	_place(cam)
	var final := phase >= 2
	if final:
		_drag = {}
		dragging = -1
		_dirty = true
	moved.emit(d, final)


## A handle drag runs (TrackEditor's press or the Alt drag's own).
func busy() -> bool:
	return dragging >= 0 or not _own.is_empty()


## Ends a running drag now (Esc, a dialog, a tool switch): its last move at `screen`, or with cancel
## none (the owner takes its step back). The button's later release is ignored.
func end_drag(screen: Vector2, cam: Camera3D, snap: Dictionary, cancel := false) -> void:
	_own = {}
	if dragging < 0 or _drag.is_empty():
		dragging = -1
		return
	if cancel or cam == null:
		_drag = {}
		dragging = -1
		_dirty = true
		return
	drag(int(_drag.handle), screen, cam, 2, snap)


## World metres per screen pixel at p (perspective: at p's depth).
static func world_per_px(cam: Camera3D, p: Vector3) -> float:
	var vs := cam.get_viewport().get_visible_rect().size if cam.is_inside_tree() else Vector2(1600, 900)
	var h := vs.y if cam.keep_aspect == Camera3D.KEEP_HEIGHT else vs.x
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return cam.size / maxf(h, 1.0)
	var depth := maxf((p - cam.global_position).dot(-cam.global_basis.z), cam.near)
	return 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5) / maxf(h, 1.0)


# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if dragging < 0 and _own.is_empty():
		var h := pick(get_viewport().get_mouse_position(), cam)
		if h != hover:
			hover = h
			_dirty = true
	_place(cam)


## The Alt + drag on a handle (TrackEditor sends Alt + LMB to the camera's orbit).
func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		var cam := get_viewport().get_camera_3d()
		if mb.pressed and mb.alt_pressed and _own.is_empty():
			if _blocked():
				return
			var h := pick(mb.position, cam)
			if h < 0:
				return
			_own = {"handle": h, "pos": mb.position, "started": false}
			get_viewport().set_input_as_handled()
		elif not mb.pressed and not _own.is_empty():
			if _own.started:
				drag(int(_own.handle), mb.position, cam, 2, _snap(false))
			_own = {}
			get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and not _own.is_empty():
		var mm := ev as InputEventMouseMotion
		var cam := get_viewport().get_camera_3d()
		if not _own.started:
			if mm.position.distance_to(_own.pos) <= DRAG_PX:
				get_viewport().set_input_as_handled()
				return
			_own.started = true
			drag(int(_own.handle), _own.pos, cam, 0, _snap(true))
		drag(int(_own.handle), mm.position, cam, 1, _snap(false))
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- drags

func _begin(handle: int, screen: Vector2, cam: Camera3D, snap: Dictionary) -> void:
	var o := _xf.origin
	var ax := _axes()
	var ro := cam.project_ray_origin(screen)
	var rd := cam.project_ray_normal(screen)
	_drag = {"handle": handle, "o": o, "ax": ax, "screen": screen, "edge": false, "t0": 0.0, "p0": o}
	match handle:
		X_AXIS, Y_AXIS, Z_AXIS:
			_drag.t0 = _axis_param(o, ax[handle], ro, rd)
		YZ_PLANE, XZ_PLANE, XY_PLANE:
			_drag.p0 = _plane_hit(o, ax[handle - YZ_PLANE], ro, rd, o)
		VIEW_PLANE:
			_drag.p0 = _plane_hit(o, -cam.global_basis.z, ro, rd, o)
		YAW_RING, PITCH_RING, ROLL_RING:
			var n := _ring_axis(handle, ax)
			var p := _plane_hit(o, n, ro, rd, Vector3(NAN, NAN, NAN))
			_drag.edge = absf(rd.dot(n)) < 0.08 or is_nan(p.x) or (p - o).length() < 1e-4
			_drag.p0 = p
	dragging = handle
	last_delta = Transform3D()
	_dirty = true
	drag_started.emit(handle, bool(snap.get("duplicate", false)))


func _delta(screen: Vector2, cam: Camera3D, snap: Dictionary) -> Transform3D:
	var h := int(_drag.handle)
	var o: Vector3 = _drag.o
	var ax: Basis = _drag.ax
	var ro := cam.project_ray_origin(screen)
	var rd := cam.project_ray_normal(screen)
	var g := grid_step(snap)
	match h:
		X_AXIS, Y_AXIS, Z_AXIS:
			var a: Vector3 = ax[h]
			var t := _axis_param(o, a, ro, rd)
			if is_nan(t):
				return last_delta
			var dt := t - float(_drag.t0)
			if g > 0.0:
				if local:
					dt = snappedf(dt, g)
				else:
					dt = snappedf(o[h] + dt, g) - o[h]
			return Transform3D(Basis(), a * dt)
		YZ_PLANE, XZ_PLANE, XY_PLANE, VIEW_PLANE:
			var n: Vector3 = -cam.global_basis.z if h == VIEW_PLANE else ax[h - YZ_PLANE]
			var p := _plane_hit(o, n, ro, rd, Vector3(NAN, NAN, NAN))
			var p0: Vector3 = _drag.p0
			if is_nan(p.x) or is_nan(p0.x):
				return last_delta
			var dv := p - p0
			if g > 0.0:
				dv = _snap_move(o, dv, h, ax, g)
			return Transform3D(Basis(), dv)
		YAW_RING, PITCH_RING, ROLL_RING:
			var n := _ring_axis(h, ax)
			var ang := 0.0
			if _drag.edge:
				ang = deg_to_rad((screen.x - (_drag.screen as Vector2).x) * EDGE_DEG_PER_PX)
			else:
				var p := _plane_hit(o, n, ro, rd, Vector3(NAN, NAN, NAN))
				if is_nan(p.x):
					return last_delta
				var v0: Vector3 = (_drag.p0 as Vector3) - o
				var v1 := p - o
				v0 -= n * v0.dot(n)
				v1 -= n * v1.dot(n)
				if v0.length() < 1e-5 or v1.length() < 1e-5:
					return last_delta
				ang = v0.signed_angle_to(v1, n)
			if bool(snap.get("angle_on", true)):
				var step := float(snap.get("angle", 15.0))
				if step > 0.0:
					ang = deg_to_rad(snappedf(rad_to_deg(ang), step))
			var r := Basis(n, ang)
			return Transform3D(r, o - r * o)
		SCALE_BOX:
			var s0: Vector2 = _drag.screen
			var px := (screen.x - s0.x) - (screen.y - s0.y)
			var f := clampf(exp(px / SCALE_PX), 0.01, 100.0)
			if g > 0.0:
				f = maxf(snappedf(f, 0.05), 0.05)
			var sb := Basis.from_scale(Vector3.ONE * f)
			return Transform3D(sb, o - sb * o)
	return Transform3D()


## The grid step a drag snaps to (0 = off): snap.on, inverted while Ctrl is held (or snap.invert).
static func grid_step(snap: Dictionary) -> float:
	var on := bool(snap.get("on", true))
	var size := float(snap.get("grid", 1.0)) if not (snap.get("grid") is bool) else float(snap.get("size", 1.0))
	if snap.get("grid") is bool:
		on = bool(snap.grid)
	var invert: bool = bool(snap.get("invert")) if snap.has("invert") else Input.is_key_pressed(KEY_CTRL)
	if invert:
		on = not on
	return size if on and size > 0.0 else 0.0


## A plane move's offset with the moved origin on the grid: world axes round the plane's two axes
## (the view plane: x and z), local axes round the offset along each local axis.
func _snap_move(o: Vector3, dv: Vector3, h: int, ax: Basis, g: float) -> Vector3:
	var axes: Array = []
	match h:
		YZ_PLANE:
			axes = [1, 2]
		XZ_PLANE:
			axes = [0, 2]
		XY_PLANE:
			axes = [0, 1]
		VIEW_PLANE:
			axes = [0, 2]
	if local and h != VIEW_PLANE:
		var out := Vector3.ZERO
		for i in axes:
			var a: Vector3 = ax[i]
			out += a * snappedf(dv.dot(a), g)
		return out
	var p := o + dv
	for i in axes:
		p[i] = snappedf(p[i], g)
	return p - o


func _snap(begin: bool) -> Dictionary:
	var ed := get_parent()
	var s: Dictionary = (ed.get("snap") as Dictionary).duplicate() if ed != null and ed.get("snap") is Dictionary else {}
	if begin:
		s["duplicate"] = true
	return s


func _blocked() -> bool:
	var ed := get_parent()
	return ed != null and ed.has_method("_blocked") and bool(ed.call("_blocked"))


static func _axis_param(o: Vector3, a: Vector3, ro: Vector3, rd: Vector3) -> float:
	# the point of the axis line nearest the mouse ray
	var w := o - ro
	var b := a.dot(rd)
	var den := 1.0 - b * b
	if absf(den) < 1e-6:
		return NAN
	return (b * rd.dot(w) - a.dot(w)) / den


static func _plane_hit(o: Vector3, n: Vector3, ro: Vector3, rd: Vector3, miss: Vector3) -> Vector3:
	var den := rd.dot(n)
	if absf(den) < 1e-6:
		return miss
	var t := (o - ro).dot(n) / den
	if t < 0.0:
		return miss
	return ro + rd * t


func _ring_axis(h: int, ax: Basis) -> Vector3:
	match h:
		PITCH_RING:
			return ax.x.normalized()
		ROLL_RING:
			return ax.z.normalized()
	return Vector3.UP


func _axes() -> Basis:
	return _live.basis if local else Basis()


func _length(cam: Camera3D, o: Vector3) -> float:
	return LENGTH_PX * world_per_px(cam, o)


# ---------------------------------------------------------------- picking geometry

func _distance(h: int, screen: Vector2, cam: Camera3D, o: Vector3, length: float, ax: Basis) -> float:
	match h:
		VIEW_PLANE, SCALE_BOX:
			var half := (0.07 if h == VIEW_PLANE else 0.12) * LENGTH_PX
			return maxf(screen.distance_to(cam.unproject_position(o)) - half, 0.0)
		X_AXIS, Y_AXIS, Z_AXIS:
			var a: Vector3 = ax[h]
			return _seg_dist(screen, cam, o + a * length * 0.18, o + a * length)
		YZ_PLANE, XZ_PLANE, XY_PLANE:
			var q := _quad(h, o, length, ax)
			var pts := PackedVector2Array()
			for w in q:
				if cam.is_position_behind(w):
					return INF
				pts.append(cam.unproject_position(w))
			if Geometry2D.is_point_in_polygon(screen, pts):
				return 0.0
			var best := INF
			for i in 4:
				best = minf(best, _seg2(screen, pts[i], pts[(i + 1) % 4]))
			return best
		YAW_RING, PITCH_RING, ROLL_RING:
			var pts := _ring(h, o, length, ax)
			var best := INF
			for i in pts.size():
				var a3 := pts[i]
				var b3 := pts[(i + 1) % pts.size()]
				if cam.is_position_behind(a3) or cam.is_position_behind(b3):
					continue
				best = minf(best, _seg2(screen, cam.unproject_position(a3), cam.unproject_position(b3)))
			return best
	return INF


func _quad(h: int, o: Vector3, length: float, ax: Basis) -> PackedVector3Array:
	var uv: Array = [[1, 2], [0, 2], [0, 1]][h - YZ_PLANE]
	var u: Vector3 = ax[uv[0]] * length
	var v: Vector3 = ax[uv[1]] * length
	return PackedVector3Array([o + u * 0.25 + v * 0.25, o + u * 0.45 + v * 0.25, o + u * 0.45 + v * 0.45, o + u * 0.25 + v * 0.45])


func _ring(h: int, o: Vector3, length: float, ax: Basis) -> PackedVector3Array:
	var n := _ring_axis(h, ax)
	var r := length * (0.78 if h == PITCH_RING else (0.66 if h == ROLL_RING else 0.9))
	var u := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u).normalized()
	var out := PackedVector3Array()
	for i in RING_SEGMENTS:
		var a := TAU * i / RING_SEGMENTS
		out.append(o + (u * cos(a) + v * sin(a)) * r)
	return out


static func _seg_dist(screen: Vector2, cam: Camera3D, a: Vector3, b: Vector3) -> float:
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return INF
	return _seg2(screen, cam.unproject_position(a), cam.unproject_position(b))


static func _seg2(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


# ---------------------------------------------------------------- drawing

func _place(cam: Camera3D) -> void:
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	var length := _length(cam, _live.origin) if cam != null and cam.is_inside_tree() else 1.0
	var b := (_live.basis if local else Basis()).scaled(Vector3.ONE * maxf(length, 1e-4))
	if is_inside_tree():
		global_transform = Transform3D(b, _live.origin)
	else:
		transform = Transform3D(b, _live.origin)
	if _dirty:
		_build()


func _ensure_mesh() -> void:
	if _mi != null:
		return
	_mi = MeshInstance3D.new()
	_mi.name = "Handles"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mat.disable_fog = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.render_priority = 100
	_mi.material_override = _mat
	add_child(_mi)


## The handles in unit size, in the node's frame (its basis is the axes, scaled to LENGTH_PX).
func _build() -> void:
	_dirty = false
	_ensure_mesh()
	var lines := PackedVector3Array()
	var lcol := PackedColorArray()
	var tris := PackedVector3Array()
	var tcol := PackedColorArray()
	var ax := Basis()   # the node is already in the axes' frame
	var hot := dragging if dragging >= 0 else hover
	match mode:
		"move":
			for i in 3:
				var c: Color = HOT if hot == i else AXIS_COLORS[i]
				var a: Vector3 = ax[i]
				lines.append_array([a * 0.18, a * 0.84])
				lcol.append_array([c, c])
				_cone(tris, tcol, a, c)
			for h in [YZ_PLANE, XZ_PLANE, XY_PLANE]:
				var q := _quad(h, Vector3.ZERO, 1.0, ax)
				var c: Color = HOT if hot == h else AXIS_COLORS[h - YZ_PLANE]
				var fill := Color(c, 0.35 if hot != h else 0.6)
				tris.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
				for k in 6:
					tcol.append(fill)
				for k in 4:
					lines.append_array([q[k], q[(k + 1) % 4]])
					lcol.append_array([c, c])
			_box(tris, tcol, 0.06, HOT if hot == VIEW_PLANE else CENTER_COLOR)
		"rotate":
			for h in handles():
				var c: Color = HOT if hot == h else ([AXIS_COLORS[1], AXIS_COLORS[0], AXIS_COLORS[2]][h - YAW_RING] as Color)
				var pts := _ring_local(h)
				for k in pts.size():
					lines.append_array([pts[k], pts[(k + 1) % pts.size()]])
					lcol.append_array([c, c])
		"scale":
			for i in 3:
				var a: Vector3 = ax[i]
				lines.append_array([a * 0.12, a * 0.7])
				lcol.append_array([AXIS_COLORS[i], AXIS_COLORS[i]])
			_box(tris, tcol, 0.12, HOT if hot == SCALE_BOX else CENTER_COLOR)
	var am := ArrayMesh.new()
	if not lines.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = lines
		arr[Mesh.ARRAY_COLOR] = lcol
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	if not tris.is_empty():
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = tris
		arr2[Mesh.ARRAY_COLOR] = tcol
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
	_mi.mesh = am


## A ring in the node's frame (the yaw ring is about world up even with LOCAL axes).
func _ring_local(h: int) -> PackedVector3Array:
	var b := _live.basis if local else Basis()
	var world := _ring(h, Vector3.ZERO, 1.0, b)
	if local:
		var inv := b.inverse()
		for i in world.size():
			world[i] = inv * world[i]
	return world


static func _cone(tris: PackedVector3Array, cols: PackedColorArray, a: Vector3, c: Color) -> void:
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized() * 0.05
	var v := a.cross(u).normalized() * 0.05
	var tip := a
	var base := a * 0.8
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var p0 := base + u * cos(a0) + v * sin(a0)
		var p1 := base + u * cos(a1) + v * sin(a1)
		tris.append_array([tip, p0, p1, base, p1, p0])
		for i in 6:
			cols.append(c)


static func _box(tris: PackedVector3Array, cols: PackedColorArray, h: float, c: Color) -> void:
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0] * h
		var u: Vector3 = f[1] * h
		var v: Vector3 = f[2] * h
		tris.append_array([n - u - v, n + u - v, n + u + v, n - u - v, n + u + v, n - u + v])
		for i in 6:
			cols.append(c)
