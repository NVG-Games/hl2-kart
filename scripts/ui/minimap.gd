class_name Minimap
extends Control
## Top-down track outline with racer blips (HUD yellow; player bright).

var race
var _pts := PackedVector2Array()
var _min := Vector2.ZERO
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _prepare() -> void:
	var path: TrackPath = race.track.path
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in path.center:
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


func _map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _min) * _scale


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if race == null or race.track == null:
		return
	if _pts.is_empty():
		_prepare()
	draw_polyline(_pts, Color(0, 0, 0, 0.35), 9.0, true)
	draw_polyline(_pts, Color8(255, 220, 0, 110), 4.0, true)
	for k in race.karts:
		if k == race.player:
			continue
		draw_circle(_map(k.global_position), 5.0, Color(k.char_data.get("color", Color.WHITE), 0.95))
	if race.player:
		var p: Vector2 = _map(race.player.global_position)
		draw_circle(p, 8.0, Color(0, 0, 0, 0.6))
		draw_circle(p, 6.0, Hl2Style.BRIGHT)
