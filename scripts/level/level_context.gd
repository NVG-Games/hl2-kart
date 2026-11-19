class_name LevelContext
extends RefCounted
## One compile's state, shared by every step and hook of LevelCompiler (3.1): the document
## snapshot, its report, the resolved styles, the roads, the terrain, the mesh buckets and the
## runtime data dict being built. Seeds and random numbers come only from `seed_of` / `rng` (2.4,
## 2.6): nothing in a compile calls randf() / randi().

var doc: LevelDoc
var report: LevelReport
var styles: Dictionary
var main: LevelRoad
var roads: Array[LevelRoad] = []    # main first, then the kept branches in doc order
var branches: Array = []           # LevelBranches' per-branch state (opaque to others; each has "ok")
var terrain: LevelTerrain          # null without terrain
var meshes: LevelMeshSet
var data := {}
var props: Array = []              # compiled props (clear_spot)
var reserved: Array = []           # [PackedVector3Array polyline, radius]
var pits: Array = []               # [{center: Vector2, radius: float, floor_y: float}] (tentacles)
var setups: Array = []             # hazard setup requests (LevelHazards' own shape)
var registries := {}               # {models, materials, skies, music}
var preview := false
var flags := false                 # compute build.flags (editor bakes)

# ---------------------------------------------------------------- additions (P2)
## Point lights the tunnels ask for ({pos, color, range, energy}, as data.lights entries): the
## compiler appends them to data.lights. Filled by LevelGeometry.build_road.
var tunnel_lights: Array = []
## Metres every tunnel style's light_every is widened by so the whole compile has <= 96 tunnel
## lights (LevelGeometry.light_extra); -1 = not planned yet.
var light_extra := -1.0


## The ground height at a plan spot: NAN without terrain, at a hole or outside the world. P2.
func ground(x: float, z: float) -> float:
	if terrain == null:
		return NAN
	return terrain.height_at(x, z)


## A seed stable across renames, saves and reorders: the first 4 bytes of sha256("<guid>:<uid>")
## read big-endian, & 0x7fffffff (2.4).
func seed_of(uid: int) -> int:
	var guid := ""
	if doc != null:
		guid = str(doc.data.get("guid", ""))
	var h := ("%s:%d" % [guid, uid]).sha256_buffer()
	return ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) & 0x7fffffff


## A random number generator seeded with seed_of(uid): the same numbers on every peer.
func rng(uid: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_of(uid)
	return r


## The road with this key (-1 the main loop, else a kept branch's uid), or null. P2.
func road(key: int) -> LevelRoad:
	for r in roads:
		if r != null and r.key == key:
			return r
	if key == -1:
		return main
	return null


## A spot `setback` metres past the road edge on `side` (-1 left, 1 right) at sample i, on
## whatever floor is there: the pavement, the verge, a tunnel's floor, the deck, or the ground
## (hazards.side_point). P2.
func side_point(r: LevelRoad, i: int, side: int, setback: float) -> Vector3:
	i = r.wrap(i)
	var sgn := -1.0 if side < 0 else 1.0
	var st := r.style_at(i)
	var k := r.kind(i)
	var edge := r.pos[i] + r.right[i] * sgn * r.width[i] * 0.5
	var q := edge + r.flat_right[i] * sgn * setback
	if k == "street" and setback <= float(st.get("walk", 4.0)) + 0.3:
		q.y = edge.y + float(st.get("curb_h", 0.16))
	elif k == "open" and setback <= float(st.get("verge_w", 4.0)):
		var drop := float(st.get("verge_drop", 0.27)) + absf(r.right[i].y) * 1.5
		q.y = edge.y - drop * setback / maxf(float(st.get("verge_w", 4.0)), 0.01)
	elif k == "tunnel" and setback <= float(st.get("wall_gap", 0.6)):
		q.y = r.pos[i].y - 0.01
	elif k == "bridge" and setback <= 0.0:
		q.y = edge.y
	else:
		q.y = ground(q.x, q.z)
	return q


## The height of whatever a kart would roll on at q: the road, its pavement or verge, or the
## ground (hazards.floor_y); near_i is a sample of the stretch q belongs to. NAN where there is
## nothing (no terrain beside a bridge). P2.
func floor_y(r: LevelRoad, q: Vector3, near_i: int) -> float:
	var best := r.wrap(near_i)
	var bd := INF
	for k in range(-12, 13):
		var j := near_i + k
		if not r.closed and (j < 0 or j >= r.n):
			continue
		j = r.wrap(j)
		var d := Vector2(r.pos[j].x - q.x, r.pos[j].z - q.z).length_squared()
		if d < bd:
			bd = d
			best = j
	var i := best
	var lat := (q - r.pos[i]).dot(r.flat_right[i])
	var hw := r.width[i] * 0.5
	var g := ground(q.x, q.z)
	if absf(lat) <= hw:
		return r.pos[i].y + r.right[i].y * lat
	var beside := side_point(r, i, 1 if lat >= 0.0 else -1, absf(lat) - hw)
	var k := r.kind(i)
	if k == "street" or k == "open":
		if is_nan(g):
			return beside.y
		return maxf(beside.y, g)
	return g


## Nudges s_m along the road (1.5 m steps either way, `tries` times) until no compiled prop and
## no reserved polyline lies within `radius` of the side spot; s_m when none is clear (P2).
func clear_spot(r: LevelRoad, s_m: float, side: int, setback: float, radius := 1.8, tries := 8) -> float:
	for k in tries:
		for sgn in [1.0, -1.0]:
			var s2: float = s_m + sgn * k * 1.5
			var q := side_point(r, r.idx(s2), side, setback)
			if _clear(q, radius):
				return s2
	return s_m


## Whether the models registry has this key. P2.
func has_model(key: String) -> bool:
	var m = registries.get("models", {})
	return m is Dictionary and (m as Dictionary).has(key)


func _clear(q: Vector3, radius: float) -> bool:
	for p in props:
		var pp = p.get("pos") if p is Dictionary else null
		var v := Vector3.ZERO
		if pp is Vector3:
			v = pp
		elif pp is Array and (pp as Array).size() >= 3:
			v = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
		else:
			continue
		if Vector2(v.x - q.x, v.z - q.z).length() <= radius:
			return false
	for res in reserved:
		if not (res is Array) or (res as Array).size() < 2 or not (res[0] is PackedVector3Array):
			continue
		var line: PackedVector3Array = res[0]
		var rr := float(res[1]) + radius
		for j in line.size():
			var a := Vector2(line[j].x, line[j].z)
			var b := a if j == line.size() - 1 else Vector2(line[j + 1].x, line[j + 1].z)
			var p2 := Vector2(q.x, q.z)
			var ab := b - a
			var t := 0.0 if ab.length_squared() < 1e-9 else clampf((p2 - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if (a + ab * t).distance_to(p2) <= rr:
				return false
	return true
