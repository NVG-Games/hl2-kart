extends RefCounted
## level/case_track (P12, content): every template compiled and put in memory as c_edit
## (CustomTracks.put_memory), then raced the way race.gd builds it (Track.build) headless in under
## 5 s: rays down the lap hit the road (meta surface road), rays down far from it the terrain
## (offroad), rays sideways from a road with barriers a barrier (wall), rays along the road
## through every tunnel opening nothing but the road; the colonly walls stop a
## ray from the road side only; the rescuer and the background's centre come from the track's
## data. The empty field has no road: build_failed is set and there is no path (race.gd then
## spawns nothing). The circuits' golden facts are case_track_golden's (run it next to this one).

const NEEDS_CONTENT := true
const TIMEOUT := 300
const BUILD_MS := 5000.0
const SAMPLES := 40

var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0


func run(t: Node) -> void:
	var holder := Node3D.new()
	holder.name = "TrackCase"
	t.add_child(holder)
	for id in LevelTemplates.IDS:
		var doc := LevelTemplates.make(id, LevelTemplates.title(id))
		if id == "oval":
			# a rescuer of its own: the race's must come from the track's data
			doc.apply([LevelDoc.op_set(["race", "rescue"], "crane")])
		var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()})
		if b == null:
			t.fail("%s: the compiler gave nothing" % id)
			continue
		var m := b.meta.duplicate(true)
		m["name"] = str(doc.data.get("name", id))
		m["author"] = "P12"
		CustomTracks.put_memory(CustomTracks.EDIT_ID, b, m)
		var trk := Track.new()
		holder.add_child(trk)
		var ms: float = t.ms(func() -> void: trk.build(CustomTracks.EDIT_ID))
		t.log("%s: compiled in %.0f ms, Track.build %.0f ms" % [id, float(b.stats.get("compile_ms", 0.0)), ms])
		if id == "empty":
			t.check(trk.build_failed != "" and trk.path == null, "empty: no road, build_failed says so (%s)" % trk.build_failed)
			trk.free()
			continue
		t.check(trk.build_failed == "" and trk.path != null, "%s: built (%s)" % [id, trk.build_failed])
		if trk.path == null:
			trk.free()
			continue
		t.check(ms <= BUILD_MS * slack, "%s: Track.build in %.0f ms (<= %.0f)" % [id, ms, BUILD_MS])
		t.check(trk.id == CustomTracks.EDIT_ID and trk.data == b.data, "%s: the track races the compiled data" % id)
		# the bodies enter the physics space
		await t.get_tree().physics_frame
		await t.get_tree().physics_frame
		var fenced := false
		for r in b.roads:
			fenced = fenced or not r.barriers.is_empty()
		_rays(t, id, trk, fenced)
		_portals(t, id, trk, b)
		_colonly(t, id, trk)
		var want := "crane" if id == "oval" else str(b.data.get("rescue", ""))
		t.check(str(b.data.get("rescue", "")) == want and Rescuer.kind_of(trk) == want,
			"%s: the rescuer from the data (%s, %s)" % [id, str(b.data.get("rescue", "")), Rescuer.kind_of(trk)])
		_background(t, id, trk)
		trk.free()
		await t.frames(1)
	CustomTracks.forget(CustomTracks.EDIT_ID)
	holder.free()


## A ray's first hit on the world layer: the collider, or null.
static func _cast(trk: Track, a: Vector3, b: Vector3, back_faces := true) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.LAYER_WORLD)
	q.hit_back_faces = back_faces
	return trk.get_world_3d().direct_space_state.intersect_ray(q)


static func _surface(hit: Dictionary) -> String:
	if hit.is_empty() or hit.collider == null:
		return ""
	return str((hit.collider as Object).get_meta("surface", ""))


## Down the lap: road; sideways from it: a barrier (on a template whose roads have one: the
## figure eight's bridge, the city's fences); down far from every road: the terrain.
func _rays(t: Node, id: String, trk: Track, fenced: bool) -> void:
	var p := trk.path
	var road := 0
	var wall := 0
	var bad := ""
	for k in SAMPLES:
		var i := int(float(k) * p.center.size() / SAMPLES)
		var c: Vector3 = p.center[i]
		var up: Vector3 = p.up[i]
		var s := _surface(_cast(trk, c + up * 2.5, c - up * 3.0))
		if s == "road":
			road += 1
		elif bad == "":
			bad = "sample %d: %s" % [i, s if s != "" else "nothing"]
		var r: Vector3 = p.fwd[i].cross(up).normalized()
		for side in [-1.0, 1.0]:
			var a := c + up * 0.7
			if _surface(_cast(trk, a, a + r * side * (p.width[i] * 0.5 + 4.0))) == "wall":
				wall += 1
	t.check(road >= int(SAMPLES * 0.9), "%s: rays down the lap hit the road (%d of %d; first miss %s)" % [id, road, SAMPLES, bad])
	if fenced:
		t.check(wall > 0, "%s: rays sideways from the road hit a barrier (%d)" % [id, wall])
	else:
		t.log("%s: no barrier on its roads (%d wall hits sideways)" % [id, wall])
	# the ground: the point of a coarse grid farthest from every road's centre line
	var pts := PackedVector3Array(p.center)
	for br in p.branches:
		pts.append_array(br.center)
	var best := Vector2.ZERO
	var best_d := -1.0
	for gz in range(-8, 9):
		for gx in range(-8, 9):
			var q := Vector2(gx * 50.0, gz * 50.0)
			var d := INF
			for c in pts:
				d = minf(d, q.distance_squared_to(Vector2(c.x, c.z)))
			if d > best_d:
				best_d = d
				best = q
	var hit := _cast(trk, Vector3(best.x, 2000.0, best.y), Vector3(best.x, -1000.0, best.y))
	t.check(_surface(hit) == "offroad" and hit.collider is StaticBody3D and str(hit.collider.name).begins_with("col_terrain"),
		"%s: a ray down %.0f m from the road hits the terrain (%s %s)" % [id, sqrt(best_d), _surface(hit),
			str(hit.collider.name) if not hit.is_empty() else ""])


## L3: rays along the road at 0.5, 1.5 and 2.5 m (on its centre and 3 m to each side) through
## every tunnel opening, from 10 m outside to 10 m inside, hit nothing but the road: no terrain
## across the mouth (the city block's hill face walled it off), no lintel at kart height.
func _portals(t: Node, id: String, trk: Track, b: LevelBuild) -> void:
	var openings := 0
	var rays := 0
	var bad := ""
	for r: LevelRoad in b.roads:
		if r.n < 3:
			continue
		var back := ceili(10.0 / maxf(r.step, 0.1))
		for i in r.n:
			var j := i + 1
			if j >= r.n:
				if not r.closed:
					continue
				j = 0
			if (r.kind(i) == "tunnel") == (r.kind(j) == "tunnel"):
				continue
			openings += 1
			var i0 := r.wrap(i - back) if r.closed else maxi(i - back, 0)
			var i1 := r.wrap(j + back) if r.closed else mini(j + back, r.n - 1)
			for lat in [-3.0, 0.0, 3.0]:
				for h in [0.5, 1.5, 2.5]:
					var a := r.surface(i0, lat, h)
					var e := r.surface(i1, lat, h)
					var hit := _cast(trk, a, e)
					rays += 1
					if not hit.is_empty() and _surface(hit) != "road" and bad == "":
						bad = "road %d sample %d lat %.0f h %.1f: %s at %s" % [r.key, i, lat, h, str(hit.collider.name), str(hit.position)]
	if openings == 0:
		t.log("%s: no tunnel opening" % id)
		return
	t.check(bad == "", "%s: rays along the road through %d tunnel openings hit only the road (%d rays; %s)" % [id, openings, rays, bad])


## The colonly walls (invisible, above a barrier) stop a ray from the road side and let one from
## the other side through; the visible walls are solid both ways.
func _colonly(t: Node, id: String, trk: Track) -> void:
	var bodies: Array = []
	var shapes_ok := true
	for n in trk.find_children("col_*", "StaticBody3D", true, false):
		var nm := String(n.name)
		var cs := n.get_child(0) as CollisionShape3D if n.get_child_count() > 0 else null
		if cs == null or not (cs.shape is ConcavePolygonShape3D):
			continue
		var sh := cs.shape as ConcavePolygonShape3D
		if nm.begins_with("col_colonly"):
			bodies.append(n)
			shapes_ok = shapes_ok and not sh.backface_collision and str(n.get_meta("surface", "")) == "wall"
		elif nm.begins_with("col_walls"):
			shapes_ok = shapes_ok and sh.backface_collision
	if bodies.is_empty():
		t.log("%s: no colonly wall" % id)
		return
	t.check(shapes_ok, "%s: colonly shapes are one-sided walls, visible walls two-sided" % id)
	var roads := PackedVector3Array(trk.path.center)
	for br in trk.path.branches:
		roads.append_array(br.center)
	var tried := 0
	var good := 0
	var why := ""
	for body: StaticBody3D in bodies:
		var faces := ((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
		var xf := body.global_transform
		var n_tri := faces.size() / 3
		for j in 6:
			if tried >= 18:
				break
			var f := int(float(j) * n_tri / 6.0) * 3
			var a := xf * faces[f]
			var b := xf * faces[f + 1]
			var c := xf * faces[f + 2]
			var nrm := (b - a).cross(c - a)
			if nrm.length() < 1e-4:
				continue
			nrm = nrm.normalized()
			var mid := (a + b + c) / 3.0
			var pa := mid + nrm * 0.4
			var pb := mid - nrm * 0.4
			var ha := _cast(trk, pa, pb, false)
			var hb := _cast(trk, pb, pa, false)
			var from_a: bool = not ha.is_empty() and ha.collider == body
			var from_b: bool = not hb.is_empty() and hb.collider == body
			tried += 1
			# the side that stops the ray is the road's (nearer to a road's centre line)
			var road_side_a := _plan_dist(roads, pa) < _plan_dist(roads, pb)
			if from_a != from_b and from_a == road_side_a:
				good += 1
			elif why == "":
				why = "%s at %s: from a %s, from b %s, a road side %s" % [body.name, str(mid), from_a, from_b, road_side_a]
	t.check(tried > 0 and good == tried, "%s: colonly walls stop rays from the road side only (%d of %d; %s)" % [id, good, tried, why])


static func _plan_dist(pts: PackedVector3Array, q: Vector3) -> float:
	var d := INF
	for c in pts:
		d = minf(d, Vector2(c.x - q.x, c.z - q.z).length_squared())
	return sqrt(d)


## data.bg_center (the world centre above the highest ground) and the background's sky life
## circling it when the theme has one.
func _background(t: Node, id: String, trk: Track) -> void:
	var bc = trk.data.get("bg_center")
	t.check(bc is Array and (bc as Array).size() == 3, "%s: bg_center in the data (%s)" % [id, str(bc)])
	var bl: BackgroundLife = null
	for n in trk.find_children("*", "", true, false):
		if n is BackgroundLife:
			bl = n
			break
	if bl == null or not (bc is Array):
		t.log("%s: no sky life on this background" % id)
		return
	var want := Vector3(float(bc[0]), float(bc[1]), float(bc[2]))
	t.check(bl._custom_center and (bl._center as Vector3).distance_to(want) < 0.01, "%s: the sky life circles bg_center" % id)
