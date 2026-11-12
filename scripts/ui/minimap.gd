class_name Minimap
extends Control
## Top-down track outline with racer blips (HUD yellow; player bright). Branches are drawn
## first, as bright dashes on the same dark edge as the main loop, so a shortcut stands out
## from the lap, and forks, merges and crossings read. Track hazards are small triangles on it.

const DASH := 5.0  # branch dash and gap lengths (px)
const DASH_GAP := 3.0

var race
var _pts := PackedVector2Array()
var _branch_pts: Array[PackedVector2Array] = []
var _branch_dashes: Array[PackedVector2Array] = []  # start / end pairs of each branch's dashes
var _min := Vector2.ZERO
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _prepare() -> void:
	var path: TrackPath = race.track.path
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for g: TrackPath in [path] + path.branches:
		for c in g.center:
			lo = lo.min(Vector2(c.x, c.z))
			hi = hi.max(Vector2(c.x, c.z))
	_min = lo
	var span := hi - lo
	_scale = minf(size.x / span.x, size.y / span.y) * 0.92
	var off := (size - span * _scale) * 0.5
	_min -= off / _scale
	for c in path.center:
		_pts.append(_map(c))
	_pts.append(_pts[0])
	for b in path.branches:
		var line := PackedVector2Array()
		for c in b.center:
			line.append(_map(c))
		_branch_pts.append(line)
		_branch_dashes.append(_dashes(line))


## A polyline cut into DASH-long pieces DASH_GAP apart, as start / end pairs (draw_multiline).
static func _dashes(line: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var phase := 0.0  # px into the current dash and gap
	for i in line.size() - 1:
		var a := line[i]
		var seg := a.distance_to(line[i + 1])
		var u := 0.0
		while u < seg:
			var step := minf(seg - u, (DASH if phase < DASH else DASH + DASH_GAP) - phase)
			if phase < DASH:
				out.append(a.lerp(line[i + 1], u / seg))
				out.append(a.lerp(line[i + 1], (u + step) / seg))
			u += step
			phase = fmod(phase + step, DASH + DASH_GAP)
	return out


func _map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _min) * _scale


func _process(_d: float) -> void:
	queue_redraw()


## Track hazards: small orange triangles on the outline, blinking red while one is firing.
func _draw_hazards() -> void:
	var hz: HazardDirector = race.track.hazards
	if hz == null:
		return
	var t := hz.clock()
	var blink := int(Time.get_ticks_msec() / 150.0) % 2 == 0
	for h in hz.list:
		var col := Color8(255, 140, 0, 220)
		if h.is_active(t):
			col = Color(1.0, 0.15, 0.1, 1.0 if blink else 0.35)
		var q := _map(race.track.path.center_at(h.s))
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -6), q + Vector2(5, 4), q + Vector2(-5, 4)]), col)


func _draw() -> void:
	if race == null or race.track == null:
		return
	if _pts.is_empty():
		_prepare()
	for line in _branch_pts:
		draw_polyline(line, Color(0, 0, 0, 0.35), 9.0, true)
	for dashes in _branch_dashes:
		if not dashes.is_empty():
			draw_multiline(dashes, Color8(255, 220, 0, 235), 4.0, true)
	draw_polyline(_pts, Color(0, 0, 0, 0.35), 9.0, true)
	draw_polyline(_pts, Color8(255, 220, 0, 110), 4.0, true)
	_draw_hazards()
	for k in race.karts:
		if k == race.player:
			continue
		draw_circle(_map(k.global_position), 5.0, Color(k.char_data.get("color", Color.WHITE), 0.95))
	if race.player:
		var p: Vector2 = _map(race.player.global_position)
		draw_circle(p, 8.0, Color(0, 0, 0, 0.6))
		draw_circle(p, 6.0, Hl2Style.BRIGHT)
