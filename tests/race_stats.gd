extends Node
## Fast headless AI race for tuning: prints lap times, respawns, places and, on tracks with
## branches, how often each branch was taken, completed and fallen off.
## usage: godot --headless --path . res://tests/race_stats.tscn -- <seconds> <time_scale> <laps> [difficulty] [track] [hazards] [--seed N] [--why] [--branches <track.json>] [--hazards <list.json>]
## --branches adds another track JSON's branches to the running track before the start: no
## road is built for them, so it only smoke-tests the route, AI and respawn code on them.
## The sixth plain argument turns the track hazards off (0) or on (1, the default); --hazards
## races with that data["hazards"] list (e.g. resolved offline by tools/hazards.py) instead of
## the track's own. Hazard hits are counted per hazard, per kart and per lap driven.
## A run also stops (with its report) after LOAD_S + SLACK x seconds / time_scale of real time, never
## before MIN_REAL_S: a hang or a machine too slow for the time scale.

const LOAD_S := 60.0
const SLACK := 1.5
const MIN_REAL_S := 280.0

var seconds := 120.0
var real_limit := MIN_REAL_S
var t := 0.0
var race: Node
var _next := 10.0
var _extra: Array = []  # --branches: branch entries still to add
var _hz_list: Array = []  # --hazards: the hazard list still to swap in
var _hz_hits := {}  # kart -> track hazard hits
var _hz_last := {}  # kart -> race seconds of its last hazard hit
var _hz_rescues := 0  # scanner rescues within 10 s of a hazard hit (a hit should never need one)
## per kart: {"falls", "sinks", "scans", "levels", "state", "route", "u"} plus per branch
## {"take", "done", "left", "falls", "respawns"} under "b<index>"
var _stats := {}


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var pos: Array = []
	var i := 0
	while i < a.size():
		if a[i] == "--seed" and i + 1 < a.size():
			seed(int(a[i + 1]))
			i += 2
			continue
		if a[i] == "--branches" and i + 1 < a.size():
			_extra = (Game.load_json(a[i + 1]) as Dictionary).get("branches", [])
			i += 2
			continue
		if a[i] == "--hazards" and i + 1 < a.size():
			var l = Game.load_json(a[i + 1])
			_hz_list = l if l is Array else []
			i += 2
			continue
		if not a[i].begins_with("--"):
			pos.append(a[i])
		i += 1
	if pos.size() > 0:
		seconds = float(pos[0])
	if pos.size() > 1:
		Engine.time_scale = float(pos[1])
		Engine.max_physics_steps_per_frame = 64
	real_limit = maxf(MIN_REAL_S, LOAD_S + SLACK * seconds / Engine.time_scale)
	Game.settings["demo"] = true
	Game.settings["laps"] = int(pos[2]) if pos.size() > 2 else 2
	Game.settings["difficulty"] = int(pos[3]) if pos.size() > 3 else 1
	Game.settings["track"] = pos[4] if pos.size() > 4 else "city17_circuit"
	Game.settings["hazards"] = int(pos[5]) if pos.size() > 5 else 1
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)


func _process(_d: float) -> void:
	if Time.get_ticks_msec() > real_limit * 1000.0:
		print("real-time limit hit")
		_hazard_report()
		_report()
		get_tree().quit()


func _physics_process(delta: float) -> void:
	t += delta
	if race == null or race.get("karts") == null or race.karts.is_empty():
		return
	if not _extra.is_empty():
		race.track.path.add_branches(_extra)
		_extra = []
	if not _hz_list.is_empty():
		_swap_hazards()
	if race.track.hazards and not race.track.hazards.noted.is_connected(_on_hazard):
		race.track.hazards.noted.connect(_on_hazard)
	for k in race.karts:
		_watch(k)
	if t > _next:
		_next += 10.0
		var line := "t=%.0f " % t
		for k in race.karts:
			var r: int = k.route
			line += "%s:L%d/%.0f/v%.0f/r%d%s%s " % [k.character_id.left(4), k.lap, k.lap_progress, k.speed, k.respawns,
				"*" if k.state != Kart.State.NORMAL else "", "" if r < 0 else "@b%d" % r]
		print(line)
		if "--why" in OS.get_cmdline_user_args():
			for k in race.karts:
				if k.speed < 2.0 and k.state == Kart.State.NORMAL and race.racing:
					var p: Vector3 = k.global_position
					var lat: float = race.track.path.lateral(p, k.path_index)
					var hit: Array = k.get_colliding_bodies().map(func(b): return str(b.name) + "@" + str(b.get_parent().name))
					print("   stuck %s at (%.1f, %.1f, %.1f) s=%.0f lat=%.1f w=%.1f wheels=%d touching %s" % [k.character_id, p.x, p.y, p.z, k.lap_progress, lat, race.track.path.width[k.path_index], k.wheels_on_ground, hit])
	var done := true
	for k in race.karts:
		if not k.finished:
			done = false
	if t >= seconds or done:
		_hazard_report()
		_report()
		get_tree().quit()


## --hazards: a director built from that list takes over from the track's own (the race rule
## still decides whether it spawns anything).
func _swap_hazards() -> void:
	race.track.hazards.queue_free()
	var d := HazardDirector.new()
	race.track.add_child(d)
	race.track.hazards = d
	d.setup(race.track, _hz_list)
	_hz_list = []


func _on_hazard(_h: Hazard, what: String, k: Kart) -> void:
	if what == "hit" and k:
		_hz_hits[k] = int(_hz_hits.get(k, 0)) + 1
		_hz_last[k] = t


## Track hazard hits per hazard, per kart and per lap driven.
func _hazard_report() -> void:
	var hz: HazardDirector = race.track.hazards
	if hz == null or hz.list.is_empty():
		return
	var laps := 0.0
	var per := ""
	for k in race.karts:
		laps += maxf(k.total_progress, 0.0) / race.track.path.length
		per += " %s:%d" % [k.character_id.left(4), int(_hz_hits.get(k, 0))]
	var total := 0
	for h in hz.list:
		total += int(hz.hits.get(h.id, 0))
		print("HAZARD %d %-11s hits=%d" % [h.id, h.type, int(hz.hits.get(h.id, 0))])
	print("HAZARDS hits=%d per kart lap %.2f (target <= 1.0) rescued within 10 s of a hit=%d  per kart:%s" % [total,
		total / maxf(laps, 1.0), _hz_rescues, per])


## Counts rescues by kind and branch takes / completions / falls from state changes.
func _watch(k: Kart) -> void:
	var st: Dictionary = _stats.get_or_add(k, {"falls": 0, "sinks": 0, "scans": 0, "levels": 0, "state": k.state, "route": -1, "u": 0.0})
	var r := k.route
	if k.state == Kart.State.RESPAWN and st["state"] != Kart.State.RESPAWN:
		match k.rescue:
			Kart.Rescue.FALL:
				st["falls"] += 1
			Kart.Rescue.SINK:
				st["sinks"] += 1
			_:
				st["scans"] += 1
				# rescued for being on the wrong level (Kart._check_respawn)
				if k._level_time > 0.5:
					st["levels"] += 1
		var after_hit := t - float(_hz_last.get(k, -99.0)) < 10.0
		if after_hit:
			_hz_rescues += 1
		print("  rescue t=%.1f %s %s at s=%.0f%s (%.0f, %.0f, %.0f)%s" % [t, k.character_id, Kart.Rescue.keys()[k.rescue],
			k.lap_progress, "" if r < 0 else " b%d u=%.0f" % [r, k.route_u], k.global_position.x, k.global_position.y,
			k.global_position.z, "  after a hazard hit" if after_hit else ""])
		if r >= 0:
			var b := _branch(st, r)
			b["respawns"] += 1
			if k.rescue != Kart.Rescue.SCAN:
				b["falls"] += 1
	if r != st["route"]:
		if st["route"] >= 0:
			var br: TrackBranch = race.track.path.branches[st["route"]]
			var ob := _branch(st, st["route"])
			if st["u"] >= br.merge_nose_u - 5.0:
				ob["done"] += 1
			else:
				ob["left"] += 1
		if r >= 0:
			_branch(st, r)["take"] += 1
	st["state"] = k.state
	st["route"] = r
	st["u"] = k.route_u if r >= 0 else 0.0


func _branch(st: Dictionary, r: int) -> Dictionary:
	return st.get_or_add("b%d" % r, {"take": 0, "done": 0, "left": 0, "falls": 0, "respawns": 0})


func _report() -> void:
	var laps_all: Array = []
	var finished := 0
	var falls := 0
	var levels := 0
	var resp := 0
	for k in race.karts:
		var st: Dictionary = _stats.get(k, {"falls": 0, "sinks": 0, "scans": 0, "levels": 0})
		print("%-10s %-6s place=%d finished=%s time=%.1f laps=%s respawns=%d falls=%d sinks=%d scans=%d (wrong level %d)" % [k.character_id, k.spec.id, k.place, k.finished, k.finish_time, str(k.lap_times), k.respawns, st["falls"], st["sinks"], st["scans"], st["levels"]])
		laps_all.append_array(k.lap_times)
		finished += 1 if k.finished else 0
		falls += st["falls"] + st["sinks"]
		levels += st["levels"]
		resp += k.respawns
	var mean := 0.0
	for lt in laps_all:
		mean += lt
	mean /= maxf(laps_all.size(), 1)
	print("SUMMARY track=%s finished=%d/%d laps=%d mean_lap=%.2f best_lap=%.2f respawns=%d falls=%d wrong_level=%d" % [Game.settings["track"], finished, race.karts.size(), laps_all.size(), mean, laps_all.min() if not laps_all.is_empty() else 0.0, resp, falls, levels])
	var branches: Array[TrackBranch] = race.track.path.branches
	var worst := 0
	var unused: Array = []
	for bi in branches.size():
		var tot := {"take": 0, "done": 0, "left": 0, "falls": 0, "respawns": 0}
		var per := ""
		for k in race.karts:
			var b: Dictionary = (_stats.get(k, {}) as Dictionary).get("b%d" % bi, {})
			for key in tot:
				tot[key] += int(b.get(key, 0))
			if not b.is_empty():
				per += " %s:%d/%d/%d/%d" % [k.character_id.left(4), b["take"], b["done"], b["falls"], b["respawns"]]
				worst = maxi(worst, int(b["respawns"]))
		print("BRANCH %s takes=%d done=%d left=%d falls=%d respawns=%d  (kart:take/done/falls/respawns)%s" % [branches[bi].id, tot["take"], tot["done"], tot["left"], tot["falls"], tot["respawns"], per])
		if tot["take"] == 0 or tot["done"] == 0:
			unused.append(branches[bi].id)
	if not branches.is_empty():
		# test plan: everyone finishes, no kart is rescued more than 3 times on one branch, and
		# (on NORMAL) every branch is taken and completed at least once
		var all_in: bool = finished == race.karts.size()
		var ok := all_in and worst <= 3 and unused.is_empty()
		print("BRANCH CRITERIA %s: all finished %s, most rescues of one kart on one branch %d (max 3), never taken or never completed %s" % [
			"PASS" if ok else "FAIL", all_in, worst, unused])
