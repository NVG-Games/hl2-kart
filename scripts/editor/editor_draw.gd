class_name EditorDraw
extends MeshInstance3D
## Immediate lines, circles, boxes and strips over the view (1.3), on top of everything or
## depth-tested: handle lines, direction arrows, jump gaps, the racing line, zones, brush circles,
## the legal-spot tint, the last drive's trail, the dragged road's centre line. Calls collect
## vertices; the mesh is rebuilt once at the end of the frame (or by flush()). P7.

## How high strips and tints float over the road surface.
const LIFT := 0.12
## The bounds the mesh claims, so it is never culled.
const BOUNDS := 100000.0

# packed arrays are appended to in place (members, never copies held in locals)
var _lv0 := PackedVector3Array()    # lines, depth-tested
var _lc0 := PackedColorArray()
var _lv1 := PackedVector3Array()    # lines on top
var _lc1 := PackedColorArray()
var _tv0 := PackedVector3Array()    # triangles, depth-tested
var _tc0 := PackedColorArray()
var _tv1 := PackedVector3Array()    # triangles on top
var _tc1 := PackedColorArray()
var _mats: Array[StandardMaterial3D] = []
var _dirty := false
var _am: ArrayMesh


func _init() -> void:
	_am = ArrayMesh.new()
	mesh = _am
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -BOUNDS, Vector3.ONE * BOUNDS * 2.0)
	for top in [false, true]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = top
		m.render_priority = 10 if top else 1
		_mats.append(m)


func _process(_delta: float) -> void:
	if _dirty:
		flush()


func clear() -> void:
	_lv0.clear()
	_lc0.clear()
	_lv1.clear()
	_lc1.clear()
	_tv0.clear()
	_tc0.clear()
	_tv1.clear()
	_tc1.clear()
	_dirty = true


func line(a: Vector3, b: Vector3, color: Color, on_top := true) -> void:
	_seg(a, b, color, color, on_top)


func polyline(points: PackedVector3Array, color: Color, closed := false, on_top := true) -> void:
	var n := points.size()
	if n < 2:
		return
	var last := n if closed else n - 1
	for i in last:
		_seg(points[i], points[(i + 1) % n], color, color, on_top)


## A line strip with a colour per point (the racing line by target speed, the drive's trail).
func polyline_colors(points: PackedVector3Array, colors: PackedColorArray, on_top := false) -> void:
	var n := mini(points.size(), colors.size())
	for i in n - 1:
		_seg(points[i], points[i + 1], colors[i], colors[i + 1], on_top)


func circle(center: Vector3, normal: Vector3, radius: float, color: Color, segments := 48) -> void:
	var nrm := normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP
	var ax := nrm.cross(Vector3.RIGHT if absf(nrm.x) < 0.9 else Vector3.FORWARD).normalized()
	var ay := nrm.cross(ax).normalized()
	var pts := PackedVector3Array()
	var segs := maxi(segments, 3)
	for i in segs:
		var a := TAU * i / segs
		pts.append(center + (ax * cos(a) + ay * sin(a)) * radius)
	polyline(pts, color, true, true)


## A circle lying on the terrain (brush rings): every point at the ground's height + 0.3 m.
func ground_circle(t: LevelTerrain, center: Vector2, radius: float, color: Color) -> void:
	var segs := clampi(int(radius * 0.8), 32, 128)
	var pts := PackedVector3Array()
	var last_y := 0.0
	for i in segs:
		var a := TAU * i / segs
		var x := center.x + cos(a) * radius
		var z := center.y + sin(a) * radius
		var y := t.height_at(x, z) if t != null else NAN
		if is_nan(y):
			y = last_y
		last_y = y
		pts.append(Vector3(x, y + 0.3, z))
	polyline(pts, color, true, true)


func box(aabb: AABB, color: Color) -> void:
	var p := aabb.position
	var s := aabb.size
	var c := [p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z)]
	var top := []
	for q in c:
		top.append(q + Vector3(0, s.y, 0))
	for i in 4:
		line(c[i], c[(i + 1) % 4], color)
		line(top[i], top[(i + 1) % 4], color)
		line(c[i], top[i], color)


## A translucent strip on the banked road from s0 to s1 metres and lat0 to lat1 across (zones, the
## hovered segment, legal spots); wraps round a closed road when s1 < s0.
func strip_on_road(r: LevelRoad, s0: float, s1: float, lat0: float, lat1: float, color: Color) -> void:
	if r == null or r.n < 2:
		return
	var i0 := r.idx(s0)
	var i1 := r.idx(s1)
	var count := i1 - i0
	if count < 0:
		count = count + r.n if r.closed else 0
	if count <= 0:
		count = 1
	var k := 0
	while k < count:
		var a := r.wrap(i0 + k)
		var b := r.wrap(i0 + k + 1)
		if b == a:
			break
		_quad_on(r, a, b, lat0, lat1, color)
		k += 1


## The legal-spot tint (BRANCH, setup hazards): the road in `ok` where flags[i] is 1, `bad` where 0.
## flags are per exported sample (every third) or per dense sample.
func flags_on_road(r: LevelRoad, flags: PackedByteArray, ok: Color, bad: Color) -> void:
	if r == null or r.n < 2 or flags.is_empty():
		return
	var per := 1 if flags.size() >= r.n else 3
	var last := r.n if r.closed else r.n - 1
	for a in last:
		var fa := mini(a / per, flags.size() - 1)
		var w := r.width[a] * 0.5
		_quad_on(r, a, r.wrap(a + 1), -w, w, ok if flags[fa] != 0 else bad)


# ---------------------------------------------------------------- additions (P7)

## A filled triangle.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, on_top := false) -> void:
	if on_top:
		_tv1.append(a)
		_tv1.append(b)
		_tv1.append(c)
		for q in 3:
			_tc1.append(color)
	else:
		_tv0.append(a)
		_tv0.append(b)
		_tv0.append(c)
		for q in 3:
			_tc0.append(color)
	_dirty = true


## An arrow along dir (direction arrows every 50 m, the ghost kart).
func arrow(at: Vector3, dir: Vector3, length: float, color: Color, on_top := true) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-12 else Vector3.FORWARD
	var side := d.cross(Vector3.UP).normalized() * length * 0.3
	if side.length_squared() < 1e-9:
		side = Vector3.RIGHT * length * 0.3
	var tip := at + d * length * 0.5
	var back := at - d * length * 0.5
	line(back, tip, color, on_top)
	line(tip, tip - d * length * 0.35 + side, color, on_top)
	line(tip, tip - d * length * 0.35 - side, color, on_top)


## Rebuilds the mesh now (it is done at the end of the frame anyway).
func flush() -> void:
	_dirty = false
	_am.clear_surfaces()
	var surf := 0
	var parts := [[_lv0, _lc0, Mesh.PRIMITIVE_LINES, 0], [_tv0, _tc0, Mesh.PRIMITIVE_TRIANGLES, 0],
		[_lv1, _lc1, Mesh.PRIMITIVE_LINES, 1], [_tv1, _tc1, Mesh.PRIMITIVE_TRIANGLES, 1]]
	for part in parts:
		if (part[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part[0]
		arrays[Mesh.ARRAY_COLOR] = part[1]
		_am.add_surface_from_arrays(part[2], arrays)
		_am.surface_set_material(surf, _mats[part[3]])
		surf += 1


## Vertices collected since the last clear (tests): {lines, tris} counts, both layers.
func vertex_count() -> Dictionary:
	return {"lines": _lv0.size() + _lv1.size(), "tris": _tv0.size() + _tv1.size()}


func _seg(a: Vector3, b: Vector3, ca: Color, cb: Color, on_top: bool) -> void:
	if on_top:
		_lv1.append(a)
		_lv1.append(b)
		_lc1.append(ca)
		_lc1.append(cb)
	else:
		_lv0.append(a)
		_lv0.append(b)
		_lc0.append(ca)
		_lc0.append(cb)
	_dirty = true


## Two depth-tested triangles between samples a and b from lat0 to lat1, LIFT over the surface.
func _quad_on(r: LevelRoad, a: int, b: int, lat0: float, lat1: float, col: Color) -> void:
	var p0 := r.surface(a, lat0, LIFT)
	var p1 := r.surface(a, lat1, LIFT)
	var q0 := r.surface(b, lat0, LIFT)
	var q1 := r.surface(b, lat1, LIFT)
	for p in [p0, p1, q1, p0, q1, q0]:
		_tv0.append(p)
		_tc0.append(col)
	_dirty = true
