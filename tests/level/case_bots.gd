extends RefCounted
## level/case_bots (P12, content): computer drivers lap the templates. race.tscn in demo mode
## (every kart a bot) through a test drive of 1 lap with one rival (2 karts), hazards off, at time
## scale 4, on the oval, the figure eight, the hills and the city block (its tunnel in a steep
## hill face: the mouth once walled off, L3): every kart finishes with at most 2 rescues. On the
## hills with the LOGGING TRAIL's ai take at 1.0: tests/branch_check.gd passes on the compiled
## track's JSON, and, the track saved in user://tracks_test/ and found there by
## CustomTracks.refresh(), a bot takes the branch through to its merge within 3 laps (the branch
## passes race_stats counts, from Race.branch_log and the karts' routes).

const NEEDS_CONTENT := true
const TIMEOUT := 900
const RACE := "res://scenes/race.tscn"
const SCALE := 4.0
const MAX_RESCUES := 2
const LIMIT_S := 300.0  # race seconds a lap may take
const TRAIL_FILE := "p12_bot_trail.hl2kt"


## branch_check.gd without its own run (its _ready quits) and without the "ok" lines.
class Checker extends "res://tests/branch_check.gd":
	func _ready() -> void:
		pass

	func _expect(tag: String, ok: bool, what: String) -> void:
		_checks += 1
		if not ok:
			_fail(tag, what)


func run(t: Node) -> void:
	var steps := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 64
	for id in ["oval", "figure8", "hills", "city"]:
		await _lap(t, id)
	await _branch(t)
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = steps
	Game.test_drive = {}
	CustomTracks.forget(CustomTracks.EDIT_ID)
	t.get_tree().unload_current_scene()
	await t.frames(2)


static func _drive_opts(track_id: String, laps: int) -> Dictionary:
	return {"track": track_id, "laps": laps, "bots": 1, "hazards": 0, "difficulty": 1, "from": "start", "route": -1,
		"s": 0.0, "lat": 0.0, "errors": 0}


## The race scene of a demo test drive on `track_id`, at SCALE.
func _race(t: Node, track_id: String, laps: int) -> Node:
	Game.settings["demo"] = true
	Game.test_drive = _drive_opts(track_id, laps)
	Engine.time_scale = SCALE
	t.get_tree().change_scene_to_file(RACE)
	for i in 900:
		var cs := t.get_tree().current_scene
		if cs != null and cs.scene_file_path == RACE and cs.is_node_ready():
			return cs
		await t.frames(1)
	t.fail("%s: the race scene never came" % track_id)
	return null


func _lap(t: Node, id: String) -> void:
	var doc := LevelTemplates.make(id, LevelTemplates.title(id))
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()})
	CustomTracks.put_memory(CustomTracks.EDIT_ID, b, {"name": LevelTemplates.title(id)})
	var race := await _race(t, CustomTracks.EDIT_ID, 1)
	if race == null:
		return
	t.check(race.karts.size() == 2 and not race.player.is_player, "%s: two computer karts" % id)
	var t0 := Time.get_ticks_msec()
	while race.race_time < LIMIT_S and not _all_done(race):
		await t.get_tree().physics_frame
	Engine.time_scale = 1.0
	var line := ""
	for k: Kart in race.karts:
		line += " %s: %s, %d rescues;" % [k.character_id, ("%.1f s" % k.finish_time) if k.finished else "not finished", k.respawns]
		t.check(k.finished, "%s: %s finishes its lap (%.0f of %.0f m)" % [id, k.character_id, k.lap_progress, race.track.path.length])
		t.check(k.respawns <= MAX_RESCUES, "%s: %s needs at most %d rescues (%d)" % [id, k.character_id, MAX_RESCUES, k.respawns])
	t.log("%s (lap %.0f m, %.1f s real):%s" % [id, race.track.path.length, (Time.get_ticks_msec() - t0) / 1000.0, line])


static func _all_done(race: Node) -> bool:
	for k: Kart in race.karts:
		if not k.finished:
			return false
	return true


func _branch(t: Node) -> void:
	var doc := LevelTemplates.make("hills", "P12 BOT TRAIL")
	doc.apply([LevelDoc.op_set(["branches", 0, "ai", "take"], 1.0)])
	var b := LevelCompiler.compile(doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()})
	var entries: Array = b.data.get("branches", [])
	t.check(entries.size() == 1 and float(entries[0].get("ai", {}).get("take", 0.0)) == 1.0, "hills: the trail is exported with ai take 1.0")
	# branch_check on the exported JSON
	var json_path: String = t.tmp("hills_bot_trail.json")
	var fa := FileAccess.open(json_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(b.data))
	fa.close()
	var d: Dictionary = Game.load_json(json_path)
	var bc := Checker.new()
	t.add_child(bc)
	bc._check_track("hills_bot_trail.json", d)
	t.check(bc._checks > 20 and bc._fails == 0, "hills: branch_check passes on the exported JSON (%d checks, %d failures)" % [bc._checks, bc._fails])
	bc.free()
	# the file in user://tracks_test/, found by refresh()
	var path := CustomTracks.mine_dir() + "/" + TRAIL_FILE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CustomTracks.mine_dir()))
	t.check(LevelIO.save(doc, path) == OK, "hills: saved to %s" % path)
	CustomTracks.refresh(true)
	var id := CustomTracks.id_for_guid(str(doc.data.get("guid", "")))
	t.check(CustomTracks.valid_id(id) and CustomTracks.has(id), "hills: refresh() finds it (%s)" % id)
	if CustomTracks.valid_id(id):
		await _take(t, id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	CustomTracks.forget(id)
	CustomTracks.refresh(true)


## Three laps at most: a bot that turns into the branch at its fork and drives out at its merge.
func _take(t: Node, id: String) -> void:
	var race := await _race(t, id, 3)
	if race == null:
		return
	t.check(race.track.path.branches.size() == 1, "hills: the race has the trail")
	var took := {}
	var through := false
	var laps := 0
	while not through and race.race_time < LIMIT_S * 3.0 and not _all_done(race):
		await t.get_tree().physics_frame
		for k: Kart in race.karts:
			if k.route == 0:
				took[k.character_id] = true
			laps = maxi(laps, k.lap)
			var v: Vector2i = (race.branch_log.get(k, {}) as Dictionary).get(0, Vector2i.ZERO)
			through = through or v.y > 0
	Engine.time_scale = 1.0
	t.log("hills: %s took the trail, through to the merge %s, by lap %d (%.0f s)" % [str(took.keys()), through, laps, race.race_time])
	t.check(through and laps <= 3, "hills: a bot takes the trail (ai take 1.0) within 3 laps")
