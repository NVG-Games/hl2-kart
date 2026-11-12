extends Node3D
## Spectator stills and behaviour checks on a real circuit with the real CrowdDirector.
## usage: godot --path . res://tests/crowd_shot.tscn -- <track> <out_prefix> <shots> [crowd.json|-] [height] [back]
## <shots>: comma list of lap metres, each optionally with an event fired there first:
##   "s"                      camera like the chase camera (height up, back metres behind)
##   "s:explosion" / ":hit" / ":fall" / ":headcrab" / ":knock" / ":lead" / ":final_lap" /
##   ":finish" / ":start"      ... about nobody, or with ":<character>" about a scripted kart of
##                            that racer standing there ("1990:lead:gordon")
##   "s:pass:<character>"     a scripted kart of that racer drives past s, the camera chasing
##   "egg:<kind>"             close-up of an easter egg (gman, holo, lamarr, zombies, gnome) or a
##                            flock (pigeon, crow, seagull, boid); the G-Man is made to show
##   "check"                  instead of stills: run the behaviour checks, exit 1 on a failure
## [crowd.json] holds "crowd_groups", "crowds", "crowd_eggs" (and the stands as "crowd_geom",
## the buildings their plots replace as "crowd_clear") to use instead of the track's own.

var trk: Track
var crowd: CrowdDirector
var cam: Camera3D
var height := 3.3
var back := 8.6
var failures := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var tid: String = a[0]
	var out: String = a[1]
	var shots: PackedStringArray = a[2].split(",")
	var src: String = a[3] if a.size() > 3 else "-"
	height = float(a[4]) if a.size() > 4 else 3.3
	back = float(a[5]) if a.size() > 5 else 8.6
	trk = Track.new()
	add_child(trk)
	trk.build(tid)
	# the spectators the track spawns itself make way for the ones under test
	if trk.crowd:
		trk.crowd.free()
	var d := {}
	if src != "-":
		d = Game.load_json(src)
		stands(trk, d.get("crowd_geom", []), d.get("crowd_clear", []))
	var t0 := Time.get_ticks_msec()
	crowd = CrowdDirector.spawn_for(trk, d)
	trk.crowd = crowd
	if crowd == null:
		print("no crowds on ", tid)
		get_tree().quit(1)
		return
	crowd.trace = true
	while not crowd.ready_all():
		await get_tree().process_frame
	print("spawned %d spectators in %d groups in %d ms (preset %d)" % [crowd.actors.size(), crowd.groups.size(),
		Time.get_ticks_msec() - t0, crowd.preset])
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	if shots.has("check"):
		await _checks()
		print("checks failed: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	for n in shots.size():
		var parts := shots[n].split(":")
		var s := float(parts[0])
		var ev := parts[1] if parts.size() > 1 else ""
		if parts[0] == "egg":
			await _egg_shot(ev)
		elif ev == "pass":
			var k := _kart(parts[2] if parts.size() > 2 else "gordon")
			await _drive(k, s - 70.0, s + 2.0)
			await get_tree().create_timer(0.3).timeout
			k.queue_free()
		else:
			_place(s)
			await get_tree().create_timer(1.2).timeout
			if ev != "":
				var k: Kart = _kart(parts[2]) if parts.size() > 2 else null
				if k:
					k.global_transform = _on_road(s)
					k.place = 1
				_event(ev, s, k)
				await get_tree().create_timer(0.6).timeout
				if k:
					k.remove_from_group("karts")
					k.queue_free()
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [out, n])
		print("shot %d s=%.0f %s gpu_ms=%.2f draw_calls=%d prims=%d animated=%d lookers=%d" % [n, s, ev,
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), _count_animated(), _count_lookers()])
	for line in crowd.decisions:
		if line.begins_with("line") or line.begins_with("event") or line.begins_with("remark") or line.begins_with("egg"):
			print("  ", line)
	get_tree().quit()


## The chase camera's view at lap metres s.
func _place(s: float) -> void:
	var tr := trk.path.transform_at(s - back)
	cam.global_position = tr.origin + Vector3.UP * height
	cam.look_at(trk.path.center_at(s + 22.0) + Vector3.UP * 1.4, Vector3.UP)


## Look at the egg or flock `kind` from 7 m away, a little above it.
func _egg_shot(kind: String) -> void:
	for e in crowd.eggs.nodes() + crowd.birds.nodes():
		if e[0] != kind:
			continue
		var node: Node3D = e[1]
		if node is CrowdActor:
			node.visible = true
			(node as CrowdActor).set_active(true)
			if kind == "gman":
				(node as CrowdActor).play(&"tie", 0.0)
		var p := node.global_position
		var i := trk.path.closest(p)
		var away := (trk.path.center[i] - p) * Vector3(1, 0, 1)
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		cam.global_position = p + away * 7.0 + Vector3.UP * 2.5
		cam.look_at(p + Vector3.UP * 1.0, Vector3.UP)
		await get_tree().create_timer(1.5).timeout
		return
	print("no egg ", kind)


## Fire `ev` at lap metres s, about kart `k` when there is one.
func _event(ev: String, s: float, k: Kart) -> void:
	var p := k.global_position if k else trk.path.center_at(s)
	match ev:
		"explosion":
			Effects.sparks(trk, p + Vector3.UP, 3.0)
			CrowdDirector.notify(get_tree(), &"explosion", p, k)
		"knock":
			CrowdDirector.notify(get_tree(), &"knock", _near_cop(p), k, null, "props_trainstation/trashcan_indoor001a")
		"finish":
			CrowdDirector.notify(get_tree(), &"finish", p, k, null, 1)
		_:
			CrowdDirector.notify(get_tree(), StringName(ev), p, k)


## A scripted kart of racer `who` (no physics: the test moves it along the road and keeps its lap
## metres; its own route tracking and rescues would fight the moves).
func _kart(who: String, ride := "buggy") -> Kart:
	var k := Kart.new()
	add_child(k)
	k.setup(who, 0, trk, true, ride)
	k.finished = true
	k.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	k.freeze = true
	k.set_physics_process(false)
	k.add_to_group("karts")
	return k


## Drive `k` from lap metres s0 to s1 at `speed` with the camera chasing it.
func _drive(k: Kart, s0: float, s1: float, speed := 24.0) -> void:
	var s := s0
	while s < s1:
		k.global_transform = _on_road(s)
		k.path_index = trk.path.index_at(s)
		k.lap_progress = fposmod(s, trk.path.length)
		var c := trk.path.transform_at(s - back)
		cam.global_position = c.origin + Vector3.UP * height
		cam.look_at(k.global_position + k.global_basis.z * -5.0 + Vector3.UP * 1.4, Vector3.UP)
		await get_tree().physics_frame
		s += speed * get_physics_process_delta_time()


func _on_road(s: float) -> Transform3D:
	var t := trk.path.transform_at(s)
	return Transform3D(t.basis, t.origin + t.basis.y * 0.6)


func _near_cop(p: Vector3) -> Vector3:
	var best := p
	var bd := INF
	for a in crowd.actors:
		if a.role == &"metrocop" and a.global_position.distance_to(p) < bd:
			bd = a.global_position.distance_to(p)
			best = a.global_position
	return best + Vector3(1.5, 0.0, 0.0)


func _count_animated() -> int:
	return crowd.actors.filter(func(x: CrowdActor) -> bool: return x.player != null and x.player.active).size()


func _count_lookers() -> int:
	return crowd.actors.filter(func(x: CrowdActor) -> bool: return x.look != null and x.look.active).size()


# ---------------------------------------------------------------- behaviour checks
## Scripted racers past the groups that should react to them; the director's trace must
## show the right clips and voice categories.
func _checks() -> void:
	var cases := [
		["metrocop", "gordon", ["metrocop condemn", "metrocop point"], "metrocop freeman"],
		["metrocop", "breen", ["metrocop salute"], "metrocop salute"],
		["vort", "vortigaunt", ["vort bow"], "vort revere"],
		["citizen", "gordon", ["citizen wave", "citizen cheer", "citizen jump"], "citizen gordon"],
		["citizen", "breen", ["citizen boo", "citizen point", "citizen crossed"], ""],
		["scientist", "gordon", ["scientist wave", "scientist cheer", "scientist jump"], "scientist "],
		["scientist", "zombie", ["scientist cower"], "scientist scream"],
		["hecu", "shephard", ["hecu salute"], "hecu salute"],
		["hecu", "gordon", ["hecu point"], "hecu freeman"],
		["vort", "gordon", ["vort bow"], "vort freeman"],
		["islave", "vortigaunt", ["islave bow"], "islave chant"],
		["metrocop", "gman_high", ["metrocop idle"], ""],
	]
	for c in cases:
		var g := _group_with(c[0])
		if g == null:
			continue
		var before := crowd.decisions.size()
		var k := _kart(c[1])
		var w: Vector2 = g.watch
		await _drive(k, w.x - 70.0, w.x + fposmod(w.y - w.x, trk.path.length) * 0.5)
		await get_tree().create_timer(0.5).timeout
		var got := crowd.decisions.slice(before)
		var clip_ok := false
		for want in c[2]:
			clip_ok = clip_ok or _has(got, "clip %d peak %s" % [g.id, c[1]], want)
		# a group of another role with a few of these in it (vortigaunts in a rebel camp) says its one
		# line from whoever is nearest
		var want: String = c[3] if g.role == StringName(c[0]) else ""
		var line_ok: bool = c[3] == "" or _has(got, "line %d %s" % [g.id, want], "")
		_report("%s passes %s group %d" % [c[1], c[0], g.id], clip_ok and line_ok, got)
		k.remove_from_group("karts")
		k.queue_free()
		await get_tree().create_timer(4.5).timeout
	# an explosion next to scientists: they cower and scream
	var sg := _group_with("scientist")
	if sg:
		_place(sg.s)
		await get_tree().create_timer(0.5).timeout
		var before := crowd.decisions.size()
		CrowdDirector.notify(get_tree(), &"explosion", sg.center)
		await get_tree().create_timer(0.3).timeout
		var got := crowd.decisions.slice(before)
		var ok := _has(got, "clip", "scientist cower") and _has(got, "line %d scientist scream" % sg.id, "")
		_report("explosion by scientists", ok, got)
	# a trash can knocked over by a metrocop: "pick up that can"
	var cg := _group_with("metrocop")
	if cg:
		_place(cg.s)
		await get_tree().create_timer(0.5).timeout
		var before := crowd.decisions.size()
		var cop := _near_cop(cg.center)
		CrowdDirector.notify(get_tree(), &"knock", cop, null, null, "props_trainstation/trashcan_indoor001a")
		await get_tree().create_timer(0.2).timeout
		var got := crowd.decisions.slice(before)
		_report("trash can by a metrocop", _has(got, "line %d metrocop pickupthecan1" % cg.id, ""), got)
	# a headcrab on a kart beside people: citizens flinch, scientists cower; both shout about it
	var hg := _group_with("citizen")
	if hg == null:
		hg = _group_with("scientist")
	if hg:
		await _event_check(hg, &"headcrab", "alyx", "cower" if hg.role == &"scientist" else "flinch", "headcrab")
	# Gordon takes the lead: citizens nearby ("Finally!"), the start arch remarks on it
	var lg := _group_with("citizen")
	if lg == null:
		lg = _group_with("scientist")
	if lg:
		await _event_check(lg, &"lead", "gordon", "", "gordon_lead" if lg.role == &"citizen" else "",
			crowd.world() != "xen")
	# a win: the start crowds celebrate
	var fg: CrowdDirector.Group = null
	for g in crowd.groups:
		if g.tags.has("start") and not g.members.is_empty():
			fg = g
	if fg:
		await _event_check(fg, &"finish", "gordon", "", "")


## Fire `kind` about a scripted kart of racer `who` standing by group g; the trace must show a
## member of g playing `clip` (any clip for ""; a lead changes no clips), a `line` of that
## category from the group unless it is "", and with `remark` a remark of the start arch.
func _event_check(g: CrowdDirector.Group, kind: StringName, who: String, clip: String, line: String,
		remark := false) -> void:
	await get_tree().create_timer(4.5).timeout
	_place(g.s)
	await get_tree().create_timer(0.5).timeout
	var before := crowd.decisions.size()
	var k := _kart(who)
	k.global_transform = Transform3D(Basis(), g.center.lerp(trk.path.center[trk.path.closest(g.center)], 0.7))
	k.place = 1
	CrowdDirector.notify(get_tree(), kind, k.global_position, k, null, 1 if kind == &"finish" else null)
	await get_tree().create_timer(0.3).timeout
	var got := crowd.decisions.slice(before)
	var ok := kind == &"lead" or _has(got, "clip %d %s" % [g.id, kind], clip)
	if line != "":
		ok = ok and _said(got, g.id, line)
	if remark:
		ok = ok and _has(got, "remark", "")
	_report("%s by %s about %s, group %d" % [kind, g.role, who, g.id], ok, got)
	_drop(k)


## A trace line of group `gid` saying a line of category `cat` (played or not).
static func _said(got: Array, gid: int, cat: String) -> bool:
	for l: String in got:
		if l.begins_with("line %d " % gid) and l.contains(" %s " % cat):
			return true
	return false


func _drop(k: Kart) -> void:
	k.remove_from_group("karts")
	k.queue_free()


## The biggest group by the main road with a member of `role` (the scripted karts drive the main road).
func _group_with(role: String) -> CrowdDirector.Group:
	var best: CrowdDirector.Group = null
	for g in crowd.groups:
		if g.members.is_empty() or g.route >= 0 or (g.kind == "cluster" and not role in ["vort", "islave", "hecu"]):
			continue
		if g.members.any(func(a: CrowdActor) -> bool: return String(a.role) == role):
			if best == null or g.members.size() > best.members.size():
				best = g
	return best


## A trace line starting with `prefix` and ending with `suffix`.
static func _has(got: Array, prefix: String, suffix: String) -> bool:
	for l: String in got:
		if l.begins_with(prefix) and l.ends_with(suffix):
			return true
	return false


func _report(what: String, ok: bool, got: Array) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1
		for l in got:
			print("    ", l)


## Test-only: the stands and gallery the generator will build (crowd_geom), and the
## buildings their plots keep out (crowd_clear), on `track` (crowd_race uses it too).
static func stands(track: Track, geom: Array, clear: Array) -> void:
	for part in geom:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _v3(part["p"])
		arr[Mesh.ARRAY_NORMAL] = _v3(part["n"])
		var uv := PackedVector2Array()
		var u: Array = part["uv"]
		for i in range(0, u.size(), 2):
			uv.append(Vector2(u[i], u[i + 1]))
		arr[Mesh.ARRAY_TEX_UV] = uv
		# the generator writes glTF's counter-clockwise triangles; Godot's front faces are clockwise
		var idx := PackedInt32Array(part["i"])
		for i in range(0, idx.size(), 3):
			var t := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = t
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = SourceMaterials.world_material(str(part["mat"]), Vector2.ONE)
		track.add_child(mi)
	var props := track.get_node_or_null("props")
	if props == null:
		return
	for body in props.get_children():
		for c in clear:
			if (body as Node3D).global_position.distance_to(Vector3(c[0], c[1], c[2])) < 0.5:
				body.queue_free()


static func _v3(f: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, f.size(), 3):
		out.append(Vector3(f[i], f[i + 1], f[i + 2]))
	return out
