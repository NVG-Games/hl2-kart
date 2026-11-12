extends Node
## Spectator data check (headless, CI): every spectator of every circuit passes the spot
## rules again (off every road, branches included, and out of tubes, not over a pit, out of
## the water, clear of props, feet on the terrain unless it stands on geometry), every model
## has a stand-in at least, every crowd voice file exists, group ids and routes are valid and
## the counts stay within the budget (per preset, and the most one chase-camera view sees).
## The built track is loaded (not for test data with stands of its own, "crowd_geom") and rays
## test every spectator against what the game collides with (walls, stands, pavements, props,
## the terrain): nothing over the feet up to head height, not walled in (inside a column); and
## it reports, without failing, the spectators whose head no point of the road nearby can see
## (a wall hides them) and those of whom it sees only the head (a wall up to their chin), by group.
## Exits 1 on a failure.
## usage: godot --headless --path . res://tests/crowd_check.tscn -- [track [crowd.json]]

const TRACKS := ["city17_circuit", "ct17", "xen", "black_mesa", "surface_tension"]
const MAX_PEOPLE := 450
## most people one view sees per preset: [lod, range, max]
const VIEWS := [[0, 110.0, 90], [1, 150.0, 160], [2, 150.0, 220]]
## where the hidden-head report looks from: metres along the road from the nearest point, and
## the height of a driver's view over the road
const SIGHT_ALONG := [-40.0, -20.0, 0.0, 20.0, 40.0]
const SIGHT_UP := 2.5

var bad := 0
var _skip: Array[RID] = []  # the loaded track's invisible walls


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var ids: Array = [a[0]] if a.size() > 0 else TRACKS
	_voices()
	# the traps stay out of the loaded tracks (they would run with nobody racing)
	Game.settings["hazards"] = 0
	for tid in ids:
		if not FileAccess.file_exists("res://assets/track/%s.json" % tid):
			continue
		var d: Dictionary = Game.load_json("res://assets/track/%s.json" % tid)
		var src: Dictionary = Game.load_json(a[1]) if a.size() > 1 else d
		_check(tid, d, src)
		if src.has("crowd_geom"):
			print("%s: ray tests left out (test data with stands of its own: they are not built)" % tid)
		elif not src.get("crowds", []).is_empty():
			await _rays(tid, src)
	print("crowd check failures: %d" % bad)
	get_tree().quit(1 if bad > 0 else 0)


func _fail(what: String) -> void:
	bad += 1
	if bad <= 40:
		print("FAIL ", what)


func _voices() -> void:
	var c: Dictionary = Game.voices.get("_crowd", {})
	if c.is_empty():
		print("no crowd voices (voices.json \"_crowd\"): spectators stay silent")
	for role in c:
		for cat in c[role]:
			for p in c[role][cat]:
				if not ResourceLoader.exists(str(p)):
					_fail("voice file %s (%s / %s)" % [p, role, cat])


func _check(tid: String, d: Dictionary, src: Dictionary) -> void:
	var people: Array = src.get("crowds", [])
	if people.is_empty():
		print("%s: no spectators" % tid)
		return
	var path := Track.make_path(d)
	var roads: Array[TrackPath] = [path]
	roads.append_array(path.branches)
	var heights := _heights(tid, d)
	var props := _props(d, src.get("crowd_clear", []))
	var groups := {}
	var ids := {}
	for b in path.branches:
		ids[b.id] = true
	for g in src.get("crowd_groups", []):
		groups[int(g["id"])] = g
		if g.get("route") != null and not ids.has(str(g["route"])):
			_fail("%s group %s: no branch %s" % [tid, g["id"], g["route"]])
	var lods := [0, 0, 0]
	var before := bad
	for m in people:
		var q := Vector3(m["pos"][0], m["pos"][1], m["pos"][2])
		var where := "%s %s at %s" % [tid, m.get("model", "?"), q]
		if not groups.has(int(m.get("group", -1))):
			_fail("%s: group %s missing" % [where, m.get("group")])
		var key := str(m.get("model", ""))
		if not Game.models.has(key) and CrowdRules.fallback(StringName(str(m.get("role", ""))), 0) == "":
			_fail("%s: no model and no stand-in" % where)
		lods[clampi(int(m.get("lod", 0)), 0, 2)] += 1
		var margin := 4.4 if m.get("dodge", false) else 0.3
		for r in roads:
			var gap := _road_gap(r, q)
			if gap < margin:
				var which := "" if r == path else " (branch %s)" % (r as TrackBranch).id
				_fail("%s: %.2f m from the road%s" % [where, gap, which])
			if _in_tube(r, q):
				_fail("%s: in or by a tube" % where)
			if _over_pit(r, q):
				_fail("%s: over a pit" % where)
		if _wet(d, q):
			_fail("%s: in the water" % where)
		var hit := _in_prop(props, q)
		if hit != "":
			_fail("%s: inside %s" % [where, hit])
		if heights and str(m.get("on", "ground")) == "ground":
			var g := _height(d, heights, q)
			if absf(g - q.y) > 0.35:
				_fail("%s: feet %.2f m off the ground" % [where, q.y - g])
	if people.size() > MAX_PEOPLE:
		_fail("%s: %d spectators (max %d)" % [tid, people.size(), MAX_PEOPLE])
	var views := _views(roads, people)
	for v in VIEWS.size():
		if views[v] > VIEWS[v][2]:
			_fail("%s: %d spectators in one view at lod <= %d (max %d)" % [tid, views[v], VIEWS[v][0], VIEWS[v][2]])
	print("%s: %d spectators in %d groups, %d eggs; lod %s; most in one view %s; %s" % [tid, people.size(),
		groups.size(), src.get("crowd_eggs", []).size(), lods, views, "ok" if bad == before else "FAILED"])


## The built track (loaded as the game loads it) against every spectator of `src`: a ray from
## the feet up to head height meets nothing, the chest is not walled in; and a report of the
## heads no point of the road within 40 m sees.
func _rays(tid: String, src: Dictionary) -> void:
	var trk := Track.new()
	add_child(trk)
	trk.build(tid)
	for f in 3:
		await get_tree().physics_frame
	var space := trk.get_world_3d().direct_space_state
	_skip.clear()
	for b in trk.find_children("col_colonly*", "StaticBody3D", true, false):
		_skip.append((b as StaticBody3D).get_rid())
	var roads: Array[TrackPath] = [trk.path]
	roads.append_array(trk.path.branches)
	var heights := _heights(tid, trk.data)
	var groups := {}  # group id -> [heads hidden, people, where one stands, only the head seen]
	var before := bad
	for m in src.get("crowds", []):
		var q := Vector3(m["pos"][0], m["pos"][1], m["pos"][2])
		var where := "%s %s at %s" % [tid, m.get("model", "?"), q]
		var low := q.y + 0.25
		if heights and str(m.get("on", "ground")) == "ground":
			low = maxf(low, _height(trk.data, heights, q) + 0.1)
		# both ways: a pavement or a road is solid from above only
		var top := q + Vector3.UP * 1.6
		var hit := _ray(space, top, Vector3(q.x, low, q.z))
		if hit.is_empty():
			hit = _ray(space, Vector3(q.x, low, q.z), top)
		if not hit.is_empty():
			_fail("%s: something built %.2f m over the feet" % [where, (hit["position"] as Vector3).y - q.y])
		if _walled_in(space, q + Vector3.UP * 1.2):
			_fail("%s: inside something built" % where)
		var g: Array = groups.get_or_add(int(m.get("group", -1)), [0, 0, q, 0])
		g[1] += 1
		if not _seen_from_road(space, roads, q + Vector3.UP * 1.65):
			g[0] += 1
		elif not _seen_from_road(space, roads, q + Vector3.UP * 1.25):
			g[3] += 1
	print("%s: rays %s; from the road (report) %s; %s" % [tid, "ok" if bad == before else "FAILED",
		_hidden_report(groups, 0, "heads hidden"), _hidden_report(groups, 3, "only the head seen")])
	trk.queue_free()
	await get_tree().process_frame


## "<what> n (g<id> k/<people> at <where>, ...)" over the groups whose count at `slot` is not 0.
static func _hidden_report(groups: Dictionary, slot: int, what: String) -> String:
	var ids := groups.keys().filter(func(k: int) -> bool: return groups[k][slot] > 0)
	ids.sort_custom(func(x: int, y: int) -> bool: return groups[x][slot] > groups[y][slot])
	var n := 0
	for k in ids:
		n += int(groups[k][slot])
	return "%s %d%s" % [what, n, "" if ids.is_empty() else " (" + ", ".join(ids.map(func(k: int) -> String:
		return "g%d %d/%d at %s" % [k, groups[k][slot], groups[k][1], (groups[k][2] as Vector3).snapped(Vector3.ONE * 0.1)])) + ")"]


## What the game collides with between a and b (the invisible city walls left out: they hide nobody).
func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, Game.LAYER_WORLD, _skip))


## Inside something built: a face straight over the chest and on seven ways of eight round it
## within 6 m (a column, a block; a wall behind or a niche leaves more open).
func _walled_in(space: PhysicsDirectSpaceState3D, c: Vector3) -> bool:
	if _ray(space, c, c + Vector3.UP * 60.0).is_empty():
		return false
	var hits := 0
	for k in 8:
		var a := k * PI / 4.0
		hits += 0 if _ray(space, c, c + Vector3(cos(a), 0.0, sin(a)) * 6.0).is_empty() else 1
	return hits >= 7


## A driver on the nearest road sees the point `head` from somewhere within 40 m of it.
func _seen_from_road(space: PhysicsDirectSpaceState3D, roads: Array[TrackPath], head: Vector3) -> bool:
	var road: TrackPath = roads[0]
	var i := 0
	var bd := INF
	for r in roads:
		var k := r.closest(head)
		var d := head.distance_squared_to(r.center[k])
		if d < bd:
			bd = d
			road = r
			i = k
	for along in SIGHT_ALONG:
		if not _hides(space, road.center_at(road.u_of(i) + along) + Vector3.UP * SIGHT_UP, head):
			return true
	return false


## Something solid between a and b; a thin sheet (a chain-link fence: two faces a few
## centimetres apart) is seen through.
func _hides(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var dir := (b - a).normalized()
	var from := a
	for k in 8:
		var hit := _ray(space, from, b)
		if hit.is_empty():
			return false
		var p: Vector3 = hit["position"]
		var back := _ray(space, p + dir * 0.01, p + dir * 0.15)
		if back.is_empty():
			return true
		from = (back["position"] as Vector3) + dir * 0.01
	return true


## Plan distance from q to the nearest road edge (segments between samples), ignoring road
## more than 8 m above or below; tubes count by their whole pipe.
func _road_gap(p: TrackPath, q: Vector3) -> float:
	var best := INF
	var q2 := Vector2(q.x, q.z)
	for i in p.n:
		var a := p.center[i]
		var b := p.center[p.wi(i + 1)]
		var tube := p.mag[i] > 0.0
		if not tube and absf(a.y - q.y) > 8.0 and absf(b.y - q.y) > 8.0:
			continue
		var half := maxf(p.width[i] * 0.5, p.mag[i] + 2.5) if tube else p.width[i] * 0.5
		var c := Geometry2D.get_closest_point_to_segment(q2, Vector2(a.x, a.z), Vector2(b.x, b.z))
		best = minf(best, q2.distance_to(c) - half)
	return best


func _in_tube(p: TrackPath, q: Vector3) -> bool:
	for i in p.n:
		if (p.mag[i] > 0.0) != (p.mag[p.wi(i - 1)] > 0.0):
			if Vector2(q.x - p.center[i].x, q.z - p.center[i].z).length() < 12.0:
				return true
	return false


func _over_pit(p: TrackPath, q: Vector3) -> bool:
	var i := p.closest(q)
	if p.pit[i] == 0 or q.y >= p.center[i].y + 0.5:
		return false
	# plan distance, not the lateral offset: past the end of a branch the nearest sample is its last
	return Vector2(q.x - p.center[i].x, q.z - p.center[i].z).length() - p.width[i] * 0.5 < 5.5


func _wet(d: Dictionary, q: Vector3) -> bool:
	var sea := float(d.get("sea_level", -1000.0))
	if (d.has("water") or sea > -500.0) and q.y < sea + 0.4:
		return true
	for w in d.get("waters", []):
		var c := Vector2(w["center"][0], w["center"][1])
		var sz := Vector2(w["size"][0], w["size"][1])
		if Rect2(c - sz * 0.5, sz).has_point(Vector2(q.x, q.z)) and q.y < float(w["level"]) + 0.4:
			return true
	return false


## [position, yaw, aabb min, aabb max, key] of every prop that could hold a spectator
## (`clear`: test data whose stands would have kept these buildings out).
func _props(d: Dictionary, clear: Array) -> Array:
	var out := []
	for p in d.get("props", []):
		var key := str(p["model"])
		if p.get("tag", "") == "far" or not Game.models.has(key) or clear.has(p["pos"]):
			continue
		var sc := float(p.get("scale", 1.0))
		var box := Game.model_aabb(key)
		out.append([Vector3(p["pos"][0], p["pos"][1], p["pos"][2]), float(p.get("yaw", 0.0)), box.position * sc,
			box.end * sc, key])
	return out


## The prop whose footprint and height range hold q (standing on its top is fine).
func _in_prop(props: Array, q: Vector3) -> String:
	for p in props:
		var pos: Vector3 = p[0]
		if absf(pos.x - q.x) > 40.0 or absf(pos.z - q.z) > 40.0:
			continue
		var lo: Vector3 = p[2]
		var hi: Vector3 = p[3]
		var c := cos(float(p[1]))
		var s := sin(float(p[1]))
		var dx := q.x - pos.x
		var dz := q.z - pos.z
		var lx := dx * c - dz * s
		var lz := dx * s + dz * c
		var m := 0.4
		if lx > lo.x - m and lx < hi.x + m and lz > lo.z - m and lz < hi.z + m and q.y > pos.y + lo.y - 2.0 \
				and q.y < pos.y + hi.y + 0.5 and absf(q.y - (pos.y + hi.y)) > 0.05:
			return str(p[4])
	return ""


func _heights(tid: String, d: Dictionary) -> PackedFloat32Array:
	if not d.has("terrain"):
		return PackedFloat32Array()
	var f := FileAccess.open("res://assets/track/%s_height.bin" % tid, FileAccess.READ)
	return f.get_buffer(f.get_length()).to_float32_array() if f else PackedFloat32Array()


func _height(d: Dictionary, h: PackedFloat32Array, q: Vector3) -> float:
	var t: Dictionary = d["terrain"]
	var nx := int(t["nx"])
	var nz := int(t["nz"])
	var i := clampf((q.x - float(t["x0"])) / float(t["cell"]), 0.0, nx - 1.001)
	var j := clampf((q.z - float(t["z0"])) / float(t["cell"]), 0.0, nz - 1.001)
	var i0 := int(i)
	var j0 := int(j)
	var fx := i - i0
	var fz := j - j0
	return h[j0 * nx + i0] * (1 - fx) * (1 - fz) + h[j0 * nx + i0 + 1] * fx * (1 - fz) \
		+ h[(j0 + 1) * nx + i0] * (1 - fx) * fz + h[(j0 + 1) * nx + i0 + 1] * fx * fz


## Most spectators within range ahead of a chase camera anywhere on any road, per preset.
func _views(roads: Array[TrackPath], people: Array) -> Array:
	var pts := PackedVector3Array()
	var lod := PackedInt32Array()
	for m in people:
		pts.append(Vector3(m["pos"][0], m["pos"][1], m["pos"][2]))
		lod.append(int(m.get("lod", 0)))
	var out := []
	for v in VIEWS:
		var best := 0
		for p in roads:
			for i in range(0, p.n):
				var cam := p.center[i] - p.fwd[i] * 8.6 + Vector3.UP * 3.3
				var n := 0
				for k in pts.size():
					var dv := pts[k] - cam
					var dist := dv.length()
					if lod[k] <= v[0] and dist < v[1] and dv.dot(p.fwd[i]) > -0.25 * dist:
						n += 1
				best = maxi(best, n)
		out.append(best)
	return out
