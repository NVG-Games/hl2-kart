extends RefCounted
## editor/case_view (P7, content): the editor scene on each template opens at once behind
## PREPARING TRACK... (no compile on the main thread), then the worker's bake brings up the road
## buckets, terrain chunks and tiles, the props, the environment and (with a road) the silent
## gantry and the crates. A committed prop appears at once; sync_props adds, moves and removes;
## undo brings it back; show_build of a bake after one prop move swaps only that prop (no bucket,
## chunk or tile). The way back from a test drive shows the session's bake without compiling and
## draws the trail and the rescue pins until the next edit.

const NEEDS_CONTENT := true
const TIMEOUT := 240
const SCENE := "res://scenes/editor.tscn"

var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0


func run(t: Node) -> void:
	var s := EditorSession.current()
	var scene: PackedScene = load(SCENE)
	for id in LevelTemplates.IDS:
		s.create(id)
		var ed := await _open(t, scene, id)
		if ed == null:
			continue
		var v := ed.view
		var road: bool = id != "empty"
		t.check(not road or v.mesh_nodes().size() > 0, "%s: road buckets (%d)" % [id, v.mesh_nodes().size()])
		t.check(v.chunk_nodes().size() > 0 and v.tile_nodes().size() > 0, "%s: terrain chunks and tiles (%d, %d)" % [id, v.chunk_nodes().size(), v.tile_nodes().size()])
		t.check(v.world_env != null and v.sun != null and v.world_env.environment == v.env, "%s: environment and sun" % id)
		var want := 0
		for p in s.doc.data.get("props", []):
			if Game.models.has(str(p.get("model", ""))):
				want += 1
		for sec in ["lights", "fires", "screens"]:
			want += (s.doc.data.get(sec, []) as Array).size()
		t.check(v.node_count() == want, "%s: a node per prop, light, fire and screen (%d of %d)" % [id, v.node_count(), want])
		if road:
			t.check(v.gantry != null and v.gantry.silent, "%s: the start arch stands, silent" % id)
			var crates := (ed.build.data.get("item_boxes", []) as Array).size() + (ed.build.data.get("boost_pads", []) as Array).size()
			t.check(v.find_child("Items", false, false).get_child_count() >= crates, "%s: crates and pads (%d)" % [id, crates])
		if id == "empty":
			ed.test_drive("start")
			t.check(ed.last_toast.begins_with("No road yet") and ed.status_text == ed.last_toast, "no road: the drive is refused with the reason (%s)" % ed.last_toast)
		if id == "oval":
			await _save_case(t, ed)
			await _props_case(t, ed)
			await _return_case(t, scene, ed)
			ed = null
		if ed != null:
			await _close(t, ed)
	s.close()


## Instances the editor on the session's track; returns it once its first bake is in and applied.
func _open(t: Node, scene: PackedScene, id: String) -> TrackEditor:
	var t0 := Time.get_ticks_usec()
	var ed: TrackEditor = scene.instantiate()
	t.get_tree().root.add_child(ed)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.check(ed.build == null and ed.card == TrackEditor.CARD_TRACK and ed._bake_started == ed.doc.revision,
		"%s: the window shows at once behind PREPARING TRACK..., the bake runs on a worker (%.0f ms)" % [id, ms])
	t.check(ms <= 300.0 * slack, "%s: the editor shows within 0.3 s (%.0f ms)" % [id, ms])
	var waited := 0
	while ed.build == null and waited < 1200:
		await t.frames(1)
		waited += 1
	if ed.build == null:
		t.fail("%s: no bake after %d frames" % [id, waited])
		ed.queue_free()
		return null
	var frames := 0
	while ed.view.busy() and frames < 2000:
		await t.frames(1)
		frames += 1
	t.log("%s: baked in %.0f ms, applied over %d frames (%s)" % [id, float(ed.build.stats.get("compile_ms", 0.0)), frames, str(ed.view.counts)])
	t.check(ed.card == "" and not ed.view.busy(), "%s: the card is gone once the bake is shown" % id)
	t.check(ed.session.build == ed.build, "%s: session.build is the bake" % id)
	return ed


func _close(t: Node, ed: TrackEditor) -> void:
	var guard := 0
	while ed.baking() and guard < 1200:
		await t.frames(1)
		guard += 1
	ed.queue_free()
	await t.frames(2)


func _model() -> String:
	for k in ["props_c17/bench01a", "props_junk/trashbin01a", "props_c17/oildrum001"]:
		if Game.models.has(k):
			return k
	for k in Game.models:
		if str(k).begins_with("props_c17/"):
			return k
	return str(Game.models.keys()[0])


func _props_case(t: Node, ed: TrackEditor) -> void:
	var doc := ed.doc
	var v := ed.view
	var key := _model()
	var uid := doc.new_uid()
	var n0 := (doc.data.props as Array).size()
	ed.commit("ADD OBJECT", [LevelDoc.op_insert(["props"], n0, {"uid": uid, "model": key, "pos": [30.0, 0.0, 40.0],
		"yaw": 90.0, "pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": ""})])
	var node := v.node_of(uid)
	t.check(node != null and node.position.is_equal_approx(Vector3(30, 0, 40)) and is_equal_approx(node.rotation.y, PI / 2),
		"a committed prop appears at once (%s)" % key)
	t.check(node != null and node.get_meta("level_uid", 0) == uid, "its node carries level_uid")
	ed.commit("MOVE OBJECT", [LevelDoc.op_set(["props", "#%d" % uid, "pos"], [35.0, 2.0, 40.0])])
	node = v.node_of(uid)
	t.check(node != null and node.position.is_equal_approx(Vector3(35, 2, 40)), "sync_props moves it")
	ed.commit("DELETE", [LevelDoc.op_remove(["props"], n0)])
	t.check(v.node_of(uid) == null, "sync_props removes it")
	ed.history.undo()
	t.check(v.node_of(uid) != null and v.node_of(uid).position.is_equal_approx(Vector3(35, 2, 40)), "undo brings it back where it was")
	var lid := doc.new_uid()
	ed.commit("ADD LIGHT", [LevelDoc.op_insert(["lights"], (doc.data.lights as Array).size(), {"uid": lid, "pos": [0.0, 5.0, 0.0],
		"color": [1.0, 0.5, 0.2], "range": 20.0, "energy": 2.0})])
	var ln := v.node_of(lid)
	t.check(ln is OmniLight3D and is_equal_approx((ln as OmniLight3D).omni_range, 20.0), "a light becomes an OmniLight3D")
	# a prop node is picked by its body (the physics ray), the editor calls it a prop
	for k in 3:
		await t.get_tree().physics_frame
	var cam := ed.camera
	var box := v.item_aabb(uid)
	var c := box.get_center()
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.5, -1).normalized(), Vector3.UP), c + Vector3(0, 10, 20))
	await t.get_tree().physics_frame
	var hit := ed.pick(cam.unproject_position(c))
	t.check(hit.what == "prop" and hit.uid == uid and hit.kind == "prop", "pick: the prop under the cursor (%s %d %s)" % [hit.what, hit.uid, hit.kind])
	# the diff: wait for the bake of these edits, then a prop move the view has not seen yet
	await _settled(t, ed)
	var ids := {}
	for nm in v.mesh_nodes():
		ids[nm] = (v.mesh_nodes()[nm] as Node).get_instance_id()
	for nm in v.chunk_nodes():
		ids[nm] = (v.chunk_nodes()[nm] as Node).get_instance_id()
	doc.set_block_signals(true)
	doc.apply([LevelDoc.op_set(["props", "#%d" % uid, "pos"], [50.0, 0.0, 10.0])])
	doc.set_block_signals(false)
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "flags": true})
	v.show_build(b)
	v.flush()
	var c2: Dictionary = v.counts
	t.log("show_build after one prop move: %s" % str(c2))
	t.check(int(c2.props) == 1 and int(c2.meshes) == 0 and int(c2.removed) == 0 and int(c2.chunks) == 0 and int(c2.tiles) == 0
		and int(c2.env) == 0 and int(c2.items) == 0 and int(c2.gantry) == 0, "show_build after one prop move swaps only that prop")
	var same := true
	for nm in v.mesh_nodes():
		same = same and ids.get(nm) == (v.mesh_nodes()[nm] as Node).get_instance_id()
	for nm in v.chunk_nodes():
		same = same and ids.get(nm) == (v.chunk_nodes()[nm] as Node).get_instance_id()
	t.check(same and v.node_of(uid).position.is_equal_approx(Vector3(50, 0, 10)), "every bucket and chunk node is the same, the prop moved")
	ed._apply_bake(b)
	v.flush()


## SAVE: the current bake is reused, the file written on a worker, the session clean.
func _save_case(t: Node, ed: TrackEditor) -> void:
	var s := ed.session
	ed.save()
	t.check(ed.bake_state == "SAVING..." and ed.status_text == "SAVING...", "SAVING... while the save runs")
	var guard := 0
	while (s.saving or ed.last_toast != "Saved") and guard < 1200:
		await t.frames(1)
		guard += 1
	t.check(ed.last_toast == "Saved" and s.path != "" and FileAccess.file_exists(s.path) and not s.dirty(), "saved to %s, clean" % s.path)
	var meta := LevelIO.read_meta(s.path)
	t.check(meta.get("view") is Array and (meta.get("view") as Array).size() == 5, "the header keeps the camera (view)")
	if s.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(s.path))


## Waits until no bake is due or running and the view has applied the last one.
func _settled(t: Node, ed: TrackEditor) -> void:
	var guard := 0
	while (ed._bake_t >= 0.0 or ed.baking() or ed.view.busy()) and guard < 2400:
		await t.frames(1)
		guard += 1


func _return_case(t: Node, scene: PackedScene, ed: TrackEditor) -> void:
	await _settled(t, ed)
	var s := ed.session
	var b := ed.build
	t.check(s.build == b and b.revision == ed.doc.revision, "the session keeps the current bake for the drive")
	var r: LevelRoad = b.roads[0]
	s.last_drive = {"laps_done": 1, "best_lap": 62.4, "lap_times": [62.4], "rescues": 1, "finished": true, "stuck_at_s": -1.0,
		"rescue_pos": PackedVector3Array([r.pos[40]]), "trail": PackedVector3Array([r.pos[0], r.pos[10], r.pos[20], r.pos[30]]),
		"speeds": PackedFloat32Array([10.0, 20.0, 30.0, 40.0])}
	var sel_tool := "items"
	ed.set_tool(sel_tool)
	ed.queue_free()
	await t.frames(2)
	var t0 := Time.get_ticks_usec()
	var ed2: TrackEditor = scene.instantiate()
	t.get_tree().root.add_child(ed2)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.check(ed2.build == b and ed2.card == "" and ed2._bake_started == -1, "back from a drive: the session's bake, no compile (%.0f ms)" % ms)
	t.check(ed2.tool.id == sel_tool, "the tool is restored")
	t.check(ed2.last_toast.contains("1:02.4") and ed2.last_toast.contains("1 rescue"), "the toast (%s)" % ed2.last_toast)
	t.check(not ed2.trail.is_empty() and ed2.markers.entries(EditorMarkers.RESCUES).size() == 1 and s.last_drive.is_empty(),
		"the trail and the rescue pin are drawn, last_drive is used up")
	ed2.view.flush()
	await t.frames(2)
	t.check(ed2.draw.vertex_count().lines >= 6, "the trail is in the overlay")
	ed2.commit("ADD", [LevelDoc.op_insert(["lights"], 0, {"uid": ed2.doc.new_uid(), "pos": [0.0, 3.0, 0.0], "color": [1.0, 1.0, 1.0],
		"range": 8.0, "energy": 1.0})])
	t.check(ed2.trail.is_empty() and ed2.markers.entries(EditorMarkers.RESCUES).is_empty(), "the next edit clears the trail and the pins")
	await _close(t, ed2)
