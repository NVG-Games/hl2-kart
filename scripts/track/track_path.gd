class_name TrackPath
extends RefCounted
## Sampled centre line + racing line of a circuit (written by tools/build_track.py).

var center := PackedVector3Array()
var line := PackedVector3Array()
var fwd := PackedVector3Array()
var right := PackedVector3Array()
var up := PackedVector3Array()
var width := PackedFloat32Array()
var speed := PackedFloat32Array()
var gap := PackedByteArray()
var theme: Array = []
var step := 6.0
var length := 1000.0
var n := 0


func _init(d: Dictionary) -> void:
	step = d["step"]
	length = d["length"]
	for p in d["center"]:
		center.append(Vector3(p[0], p[1], p[2]))
	for p in d["line"]:
		line.append(Vector3(p[0], p[1], p[2]))
	for p in d["fwd"]:
		fwd.append(Vector3(p[0], p[1], p[2]))
	for p in d["right"]:
		right.append(Vector3(p[0], p[1], p[2]))
	for p in d["up"]:
		up.append(Vector3(p[0], p[1], p[2]))
	for w in d["width"]:
		width.append(w)
	for v in d["speed"]:
		speed.append(v)
	for g in d["gap"]:
		gap.append(g)
	theme = d["theme"]
	n = center.size()
	step = length / n


func wi(i: int) -> int:
	return posmod(i, n)


## Closest sample index; with a hint only a window around it is searched.
func closest(p: Vector3, hint := -1) -> int:
	var best := 0
	var bd := INF
	if hint < 0:
		for i in n:
			var d := p.distance_squared_to(center[i])
			if d < bd:
				bd = d
				best = i
		return best
	# stay on the same stretch: a part of the lap that passes close by (a hairpin,
	# an overpass) must not steal the kart, so height counts double and every
	# sample away from the hint costs a little
	for k in range(-12, 25):
		var i := wi(hint + k)
		var dv := p - center[i]
		var d := dv.x * dv.x + dv.z * dv.z + 4.0 * dv.y * dv.y + absf(k) * step * 0.5
		if d < bd:
			bd = d
			best = i
	return best


## Distance along the lap (0..length) for a point near sample i.
func progress(p: Vector3, i: int) -> float:
	var s := i * step + (p - center[i]).dot(fwd[i])
	return fposmod(s, length)


func lateral(p: Vector3, i: int) -> float:
	return (p - center[i]).dot(right[i])


func index_at(s: float) -> int:
	return wi(int(floor(fposmod(s, length) / step)))


func center_at(s: float) -> Vector3:
	s = fposmod(s, length)
	var f := s / step
	var i := int(floor(f))
	var t := f - i
	return center[wi(i)].lerp(center[wi(i + 1)], t)


func line_at(s: float) -> Vector3:
	s = fposmod(s, length)
	var f := s / step
	var i := int(floor(f))
	var t := f - i
	return line[wi(i)].lerp(line[wi(i + 1)], t)


func transform_at(s: float) -> Transform3D:
	var i := index_at(s)
	var f := fwd[i]
	var u := up[i]
	var r := f.cross(u).normalized()
	var b := Basis(r, u, -f)
	return Transform3D(b, center_at(s))
