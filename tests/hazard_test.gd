extends Node
## Track hazards QA (scripts/hazards).
##   race (default): a demo race with hazards ON. Logs what each hazard did (warnings, shots,
##     hits, near misses), how the bots answered (stopped at a train, the lateral they passed
##     at), and with an out_prefix saves stills from two cameras at its warnings and strikes
##     (needs a window: leave out --headless).
##     godot --path . res://tests/hazard_test.tscn -- <track> <hazard id|type|all> [seconds] [time_scale] [out_prefix]
##   determinism: two directors built from the same data must show the same thing at the same
##     clock, however they are stepped (1/30 s against 1/144 s).
##     godot --headless --path . res://tests/hazard_test.tscn -- determinism <track>
##   pose: stills of every hazard model's rig (turret aim, the ceiling turret folding, the
##     strider's crouch and head, the tentacle's curl, the vortigaunt's arms) for the art pass.
##     godot --path . res://tests/hazard_test.tscn -- pose <out_prefix>
##   rules: on the real track a scripted kart is put into every hazard's danger as it strikes:
##     it must be spun or tumbled with the effect's grace, and never while charged (star),
##     still immune from another hit or already hit by the hazard's group on this pass (a
##     group's immunity must last inside its stretch and end once the kart has driven out of
##     it; the groups are printed). Then every drop point of the scanner and of the Xen
##     portal item along the lap must land outside every hazard's band. With out_prefix (and a
##     window) it saves stills of every hazard's warning and of its hit from two cameras. With
##     --branches <track.json> (another track's branches, added with no road) a gate put on the
##     main road beside each branch must advise a kart that stays on the main road and never one
##     on that branch or about to turn into it.
##     godot --headless --path . res://tests/hazard_test.tscn -- rules <track> [out_prefix]
##   net: one peer of an online race on the same hazard list: a dedicated host, or a client
##     (with --autodrive). Every peer logs the shared clock beside the wall clock (to compare
##     peers) and each hazard event as it lands; a client also sets off the first tripmine or
##     mine itself once, so that event travels client -> server -> the other clients.
##     godot --headless --path . res://tests/hazard_test.tscn -- net host <port> <track> <seconds>
##     godot --headless --path . res://tests/hazard_test.tscn -- net join <port> <nick> <seconds> --autodrive
##   view: a still of the built track, its hazards and background life running, after `seconds`:
##     the camera at x,y,z looking at x,y,z, or at seagull i ("bird<i>": then `from` is an
##     offset from that bird).
##     godot --path . res://tests/hazard_test.tscn -- view <track> <from> <at> <out.png> [seconds]
## Options: --hazards <file.json> uses that list instead of the track's data["hazards"]
## (tools/hazards.py entries, e.g. resolved offline before a rebuild); --difficulty N; --laps N;
## --branches <track.json> (rules, see above; a race with out_prefix that runs to the end also
## saves its results screen, with the shortcuts column these branches give it).

const CHECK_TIMES := [-1.0, 0.0, 1.7, 33.3, 61.0, 125.5, 300.0]
## what a hit by each effect leaves: the kart's state and its hazard grace
const EFFECTS := {"tumble": [Kart.State.TUMBLE, 2.4], "spin": [Kart.State.SPIN, 1.6], "shock": [Kart.State.SPIN, 1.6],
	"bounce": [Kart.State.SPIN, 1.6]}

var args: Array = []
var race: Node
var director: HazardDirector
var pick := "all"
var seconds := 120.0
var out := ""
var t := 0.0
var failures := 0
var _log := {}          # hazard id -> {what: count}
var _stills := {}       # hazard id -> stills taken
var _cams: Array[Camera3D] = []
var _passes := {}       # [kart, hazard id] -> lap s on the previous frame
var _stops := {}        # hazard id -> bots seen waiting at it
var _dodging := {}      # kart -> its AI's dodge timer on the previous frame
var _dodges := {}       # hazard id -> bots that swerved or braked when it locked on
var _lock_shots := 0
var _lock_armed := false
var _closing := false
var _busy := 0          # hazard stills being taken (each holds the view on its own camera)
var _override: Array = []
var _branches: Array = []  # --branches: branch entries to add (rules)
var _notes: Array = []  # rules: [hazard id, what] noted during the current probe
var _hit_got: Array = []  # rules: the kart's state and grace the moment a hit was noted


func _ready() -> void:
	args = Array(OS.get_cmdline_user_args())
	var hz := args.find("--hazards")
	if hz >= 0 and hz + 1 < args.size():
		var data = Game.load_json(args[hz + 1])
		_override = data if data is Array else []
		args = args.slice(0, hz) + args.slice(hz + 2)
	var df := args.find("--difficulty")
	if df >= 0 and df + 1 < args.size():
		Game.settings["difficulty"] = int(args[df + 1])
		args = args.slice(0, df) + args.slice(df + 2)
	var lf := args.find("--laps")
	if lf >= 0 and lf + 1 < args.size():
		Game.settings["laps"] = int(args[lf + 1])
		args = args.slice(0, lf) + args.slice(lf + 2)
	var bf := args.find("--branches")
	if bf >= 0 and bf + 1 < args.size():
		_branches = (Game.load_json(args[bf + 1]) as Dictionary).get("branches", [])
		args = args.slice(0, bf) + args.slice(bf + 2)
	Game.settings["hazards"] = 1
	match args[0] if not args.is_empty() else "":
		"determinism":
			_determinism(args[1] if args.size() > 1 else "ct17")
		"pose":
			_poses.call_deferred(args[1] if args.size() > 1 else "user://hazard_pose")
		"rules":
			out = args[2] if args.size() > 2 else ""
			_rules.call_deferred(args[1] if args.size() > 1 else "ct17")
		"net":
			# the race replaces this scene: the peer lives on beside it
			get_tree().root.add_child.call_deferred(NetRun.new(args.slice(1), _override))
		"view":
			_view.call_deferred(args.slice(1))
		_:
			_start_race()


# ---------------------------------------------------------------- race
func _start_race() -> void:
	Game.settings["demo"] = true
	Game.settings["track"] = args[0] if args.size() > 0 else "ct17"
	pick = args[1] if args.size() > 1 else "all"
	seconds = float(args[2]) if args.size() > 2 else 120.0
	if args.size() > 3:
		Engine.time_scale = float(args[3])
		Engine.max_physics_steps_per_frame = 64
	out = args[4] if args.size() > 4 else ""
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)


func _picked(h: Hazard) -> bool:
	return pick == "all" or pick == h.type or (pick.is_valid_int() and int(pick) == h.id)


## Once the race has built its track: hook the director (or swap in the --hazards list), and
## add the --branches (no road: they only give the results screen its shortcuts column).
func _attach() -> void:
	if not _branches.is_empty():
		race.track.path.add_branches(_branches)
	director = race.track.hazards
	if not _override.is_empty():
		director.queue_free()
		director = HazardDirector.new()
		race.track.add_child(director)
		race.track.hazards = director
		director.setup(race.track, _override)
		# the circuit's own background gunship gives way to a strafing one (as Track.build does)
		for bg: BackgroundLife in race.track.find_children("*", "BackgroundLife", false, false):
			if bg.gunship and director.has_type("air_strafe"):
				bg.gunship.queue_free()
				bg.gunship = null
	director.noted.connect(_on_noted)
	print("hazards: %d on %s (difficulty %d)" % [director.list.size(), Game.settings["track"], int(Game.settings["difficulty"])])
	for h in director.list:
		_log[h.id] = {}
		print("  %d %-11s s %6.0f span %.0f-%.0f%s" % [h.id, h.type, h.s, h.span.x, h.span.y, "" if _picked(h) else "  (not logged)"])
		if out != "" and _picked(h):
			_place_cams(h)


func _on_noted(h: Hazard, what: String, k: Kart) -> void:
	_log[h.id][what] = int(_log[h.id].get(what, 0)) + 1
	if not _picked(h):
		return
	var who: String = k.character_id if k else "-"
	print("t=%6.2f clock=%6.2f  %d %-11s %-5s %s" % [t, director.clock(), h.id, h.type, what, who])
	if out != "" and what in ["warn", "fire", "hit"] and int(_stills.get(h.id, 0)) < 6:
		_stills[h.id] = int(_stills.get(h.id, 0)) + 1
		_still.call_deferred(h, what, 0.15 if what == "fire" and not h is ShooterHazard else 0.0)


## Two cameras per hazard: from the road the karts come along, at the hazard (or at its
## danger zone when the hazard is far off, like a gunship's loiter point), and high from the side.
func _place_cams(h: Hazard) -> void:
	var p := race.track.path as TrackPath
	var mid := fposmod(h.span.x + (h.span.y - h.span.x) * 0.6, p.length)
	var c := p.center_at(mid)
	var i := p.index_at(mid)
	var from_s := fposmod(h.span.x - 12.0, p.length)
	var eye := p.center_at(from_s) + p.up[p.index_at(from_s)] * 5.0
	var look := h.global_position + Vector3.UP * (8.0 if h is StriderHazard else 1.5)
	if h is TentacleHazard:
		look = c   # it rises from far below the road: watch the road it slams
	var views := [[c + p.right[i] * 28.0 + Vector3.UP * 16.0, c]]
	if p.theme[i] == "tunnel":
		# indoors the side camera stays under the roof
		views[0] = [c + p.right[i] * p.width[i] * 0.45 + p.up[i] * 4.0, c]
	if look.distance_to(c) > 90.0:
		views.push_front([eye, c])
	else:
		views.push_front([eye, look])
		# close up: in front of the hazard, on the side the karts come from
		var to := p.center_at(h.span.x) - h.global_position
		to.y = 0.0
		var near := 30.0 if h is StriderHazard else 9.0
		views.append([h.global_position + to.normalized() * near + Vector3.UP * (near * 0.4), look])
	for e in views:
		var cam := Camera3D.new()
		cam.fov = 65.0
		cam.far = 3000.0
		race.add_child(cam)
		cam.look_at_from_position(e[0], e[1], Vector3.UP)
		cam.set_meta("hazard", h.id)
		_cams.append(cam)


func _still(h: Hazard, what: String, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	_busy += 1
	var keep := get_viewport().get_camera_3d()
	var n := 0
	for cam in _cams:
		if int(cam.get_meta("hazard")) != h.id:
			continue
		cam.make_current()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d_%s_%s_%d_%d.png" % [out, h.id, h.type, what, _stills[h.id], n])
		n += 1
	if keep:
		keep.make_current()
	_busy -= 1


## The race camera's view (the HUD's lock warning on it), once no hazard still holds the view.
func _lock_still(n: int) -> void:
	while _busy > 0:
		await RenderingServer.frame_post_draw
	race.camera.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_lock_%d.png" % [out, n])


func _physics_process(delta: float) -> void:
	if race == null or race.get("track") == null or race.track.get("hazards") == null:
		return
	if director == null:
		_attach()
	t += delta
	_watch_bots(delta)
	# the HUD's lock warning, from the race camera: it follows the first few karts a gun locks
	# on (as the player), and the still is taken halfway through the lock
	if out != "" and _lock_shots < 3:
		for k: Kart in race.karts:
			if k.hazard_lock > 0.6 and k != race.player:
				race.player = k
				race.camera.target = k
		var lock: float = race.player.hazard_lock
		if lock > 0.0 and lock < 0.45 and _lock_armed:
			_lock_armed = false
			_lock_shots += 1
			_lock_still.call_deferred(_lock_shots)
		elif lock >= 0.45:
			_lock_armed = true
	var done := true
	for k in race.karts:
		if not k.finished:
			done = false
	if (t >= seconds or done) and not _closing:
		_closing = true
		_summary()
		if out != "" and done:
			await _results_still()
		get_tree().quit()


## The results screen once everyone is home (stills runs that race to the end).
func _results_still() -> void:
	var wait := 0.0
	while race.hud.results_panel == null and wait < 10.0:
		await get_tree().process_frame
		wait += get_process_delta_time()
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png("%s_results.png" % out)


## How the bots answer: the lateral each one passes a hazard at, bots stopped at a train and
## bots that swerved or braked when a gun locked on.
func _watch_bots(delta: float) -> void:
	var p := race.track.path as TrackPath
	var clock := director.clock()
	for h in director.list:
		if not _picked(h):
			continue
		for k: Kart in race.karts:
			var key := [k, h.id]
			var before: float = _passes.get(key, -1.0)
			var now := k.lap_progress
			_passes[key] = now
			if h is TrainHazard and h.is_active(clock) and k.speed < 2.0 and fposmod(h.s - now, p.length) < 30.0 \
					and k.state == Kart.State.NORMAL:
				_stops[h.id] = float(_stops.get(h.id, 0.0)) + delta
			if h is ShooterHazard and (h as ShooterHazard).target == k and k.controller is AIController:
				var dodge: float = (k.controller as AIController)._dodge_t
				if dodge > float(_dodging.get(k, 0.0)) + 0.5:
					_dodges[h.id] = int(_dodges.get(h.id, 0)) + 1
					print("t=%6.2f  %d %-11s %s dodges (lock %.2f s left)" % [t, h.id, h.type, k.character_id, k.hazard_lock])
			if before >= 0.0 and fposmod(h.s - before, p.length) < 20.0 and fposmod(now - h.s, p.length) < 20.0:
				var adv := director.advice(k, before, k.speed)
				print("t=%6.2f  %d %-11s passed by %-10s lat %5.1f speed %4.1f advice lat %s vmax %s" % [t, h.id, h.type,
					k.character_id, p.lateral(k.global_position, k.path_index), k.speed,
					"%.1f" % adv["lat"] if int(adv["id"]) == h.id else "-",
					"%.1f" % adv["vmax"] if int(adv["vid"]) == h.id else "-"])
	for k: Kart in race.karts:
		if k.controller is AIController:
			_dodging[k] = (k.controller as AIController)._dodge_t


func _summary() -> void:
	# laps driven, finished or not
	var laps := 0.0
	for k in race.karts:
		laps += maxf(k.total_progress, 0.0) / race.track.path.length
	var hits := 0
	print("---- %.0f s, %.1f kart laps driven" % [t, laps])
	for h in director.list:
		var l: Dictionary = _log[h.id]
		hits += int(l.get("hit", 0))
		print("  %d %-11s warn %3d fire %3d hit %3d near %3d dodges %3d bots waiting %.1f s" % [h.id, h.type,
			int(l.get("warn", 0)), int(l.get("fire", 0)), int(l.get("hit", 0)), int(l.get("near", 0)),
			int(_dodges.get(h.id, 0)), float(_stops.get(h.id, 0.0))])
	print("  hazard hits per kart lap: %.2f (target <= 1.0)" % (hits / maxf(laps, 1.0)))
	for k in race.karts:
		print("  %-10s place %d laps %s respawns %d" % [k.character_id, k.place, str(k.lap_times), k.respawns])


# ---------------------------------------------------------------- determinism
func _determinism(track_id: String) -> void:
	var data: Dictionary = Game.load_json("res://assets/track/%s.json" % track_id)
	var defs: Array = _override if not _override.is_empty() else data.get("hazards", [])
	if defs.is_empty():
		print("FAIL no hazards on %s (pass --hazards <file.json>)" % track_id)
		get_tree().quit(1)
		return
	_check_hash()
	var a := _director(data, defs)
	var b := _director(data, defs)
	print("%d hazards on %s" % [a.list.size(), track_id])
	# the same clock gives the same state, in any order
	for ct in CHECK_TIMES:
		_expect(_state(a, ct) == _state(b, ct), "same state at t=%.1f" % ct)
	_expect(_state(a, 61.0) == _state(a, 61.0) and _state(b, 300.0) == _state(b, 300.0), "repeatable")
	# stepped at 30 Hz and at 144 Hz up to the same clock: the same timer hazards
	for target in [33.3, 61.0, 125.5]:
		_run(a, target, 1.0 / 30.0)
		_run(b, target, 1.0 / 144.0)
		_expect(_state(a, target) == _state(b, target), "same state after stepping to %.1f s" % target)
		_expect(_shown(a) == _shown(b), "same on show after stepping to %.1f s" % target)
	# the race rule OFF: no hazards at all
	Game.settings["hazards"] = 0
	var off := _director(data, defs)
	_expect(off.list.is_empty(), "hazards OFF spawns nothing")
	Game.settings["hazards"] = 1
	_expect(off.safe_respawn(123.0) == 123.0 and int(off.advice(null, 0.0, 20.0)["id"]) == -1, "OFF answers like no hazards")
	print("checked, failures: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_hash() -> void:
	var sum := 0.0
	var sq := 0.0
	var n := 20000
	for i in n:
		var v := HazardDirector.hash01(1731447211, i, i % 7)
		sum += v
		sq += v * v
		if v < 0.0 or v >= 1.0:
			_expect(false, "hash01 in [0, 1)")
			return
	var mean := sum / n
	_expect(absf(mean - 0.5) < 0.01 and absf(sq / n - mean * mean - 1.0 / 12.0) < 0.005, "hash01 uniform (mean %.4f)" % mean)
	_expect(HazardDirector.hash01(42, 7, 3) == HazardDirector.hash01(42, 7, 3)
		and HazardDirector.hash01(42, 7, 3) != HazardDirector.hash01(42, 8, 3), "hash01 is a function of its inputs")


func _director(data: Dictionary, defs: Array) -> HazardDirector:
	var trk := Track.new()
	trk.data = data
	trk.path = TrackPath.new(data["path"])
	add_child(trk)
	var d := HazardDirector.new()
	trk.add_child(d)
	d.setup(trk, defs)
	d.set_physics_process(false)
	for h in d.list:
		h.awake = true
		h.wake()
	return d


## Steps every hazard the way the director does, at a fixed dt, from its last clock to t.
func _run(d: HazardDirector, to: float, dt: float) -> void:
	var start: float = d.list[0]._last_t if not d.list.is_empty() and d.list[0]._last_t > -1e8 else 0.0
	var n := int(round((to - start) / dt))
	for i in range(1, n + 1):
		var ct := start + i * dt if i < n else to
		for h in d.list:
			h.tick(ct, dt)
			h._last_t = maxf(h._last_t, ct)


func _state(d: HazardDirector, ct: float) -> String:
	var parts := []
	for h in d.list:
		parts.append([h.id, h.snapshot(ct)])
	return var_to_str(parts)


## What the timer hazards (tier A) have on show: each part's visibility and place, in tree order.
func _shown(d: HazardDirector) -> String:
	var parts := []
	for h in d.list:
		if not h.type in ["train", "field_gate", "strike_zone", "air_strafe", "tentacle"]:
			continue
		for n in h.find_children("*", "VisualInstance3D", true, false):
			var v := n as VisualInstance3D
			parts.append([h.id, v.global_position.snapped(Vector3.ONE * 0.05) if v.is_visible_in_tree() else "hidden"])
	return var_to_str(parts)


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


# ---------------------------------------------------------------- hit rules
## Stands in for the race: the hazards read the clock (and the player) from the track's parent.
class Rig:
	extends Node3D
	var clock := -100.0
	var player: Kart

	func hazard_clock() -> float:
		return clock


func _rules(track_id: String) -> void:
	# stills want the effects in real time
	Engine.time_scale = 1.0 if out != "" else 3.0
	Engine.max_physics_steps_per_frame = 32
	var rig := Rig.new()
	add_child(rig)
	var trk := Track.new()
	rig.add_child(trk)
	trk.build(track_id)
	var defs: Array = _override if not _override.is_empty() else trk.data.get("hazards", [])
	trk.hazards.queue_free()
	director = HazardDirector.new()
	trk.add_child(director)
	trk.hazards = director
	director.setup(trk, defs)
	director.noted.connect(func(h: Hazard, what: String, hit: Kart):
		_notes.append([h.id, what])
		if what == "hit" and hit:
			_hit_got = [hit.state, hit.hazard_grace])
	var k := Kart.new()
	rig.add_child(k)
	k.setup("alyx", 0, trk, true, "buggy")
	k.add_to_group("karts")
	rig.player = k
	print("%d hazards on %s" % [director.list.size(), track_id])
	for g in director.groups.size():
		var ids := director.list.filter(func(h: Hazard) -> bool: return h.group == g).map(func(h: Hazard) -> int: return h.id)
		print("  group %d: hazards %s, lap %.0f-%.0f" % [g, str(ids), director.groups[g].x, director.groups[g].y])
	await get_tree().physics_frame
	for h in director.list:
		for mode in ["hit"] if out != "" else ["hit", "star", "immune", "group"]:
			await _probe(rig, h, k, mode)
	await _group_expiry(rig, trk, k)
	_drop_points(trk, k)
	if not _branches.is_empty():
		trk.path.add_branches(_branches)
		_branch_advice(trk, k)
	print("checked, failures: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


## One hazard, one rule: "hit" (it spins or tumbles the kart and leaves it immune for the
## effect's grace), "star" (charged: never hit), "immune" (just hit by something else: never)
## or "group" (hit by a hazard of its group on this pass: never).
func _probe(rig: Rig, h: Hazard, k: Kart, mode: String) -> void:
	# parked well short of the hazard (still awake) until it is ready to strike again
	var park := _road_pose(h.path, h.span.x - 60.0, 0.0)
	var ready: Callable = _plan_hit(rig, h).get("ready", func() -> bool: return true)
	var waited := 0.0
	while not ready.call() and waited < 30.0:
		await _pin(rig, k, park, Vector3.ZERO)
		waited += get_physics_process_delta_time()
	var plan := _plan_hit(rig, h)
	var at: Callable = plan["at"]
	# settle on the first pose (a teleport across the lap lands a frame late), then start clean:
	# whatever the last probe left (a spin, a rescue it set off) is called off
	for f in 2:
		await _pin(rig, k, at.call(0.0), Vector3.ZERO)
	rig.clock = maxf(rig.clock, float(plan["t0"]))
	k.freeze = false
	k.state = Kart.State.NORMAL
	k.hazard_grace = 5.0 if mode == "immune" else 0.0
	k.star_time = 5.0 if mode == "star" else 0.0
	director._immune.clear()
	if mode == "group":
		director._immune[k] = h.group
	_notes.clear()
	_hit_got = [k.state, 0.0]
	var u := 0.0
	var landed := false
	var warned := -1.0
	var shot := mode != "hit" or out == ""
	while u < float(plan["dur"]) and not landed:
		var xf: Transform3D = at.call(u)
		var vel: Vector3 = ((at.call(u + 0.02) as Transform3D).origin - xf.origin) / 0.02
		await _pin(rig, k, xf, vel)
		u += get_physics_process_delta_time()
		landed = _notes.has([h.id, "hit"])
		if warned < 0.0 and _notes.has([h.id, "warn"]):
			warned = u
		# the telegraph: at a set moment, or a set time after the hazard warned
		var tele := float(plan.get("tele", -1.0))
		if not shot and ((tele >= 0.0 and u >= tele) or (tele < 0.0 and warned >= 0.0 and u >= warned + float(plan["tele_warn"]))):
			shot = true
			await _probe_stills(h, k, "warn")
	if landed and out != "" and mode == "hit":
		await get_tree().create_timer(0.12).timeout
		await _probe_stills(h, k, "hit")
	# a hazard that aims at a kart (the strider, the Apache) or reacts to one never even
	# starts at a charged or immune kart; the others strike on their own timetable
	var fired := _notes.has([h.id, "fire"]) or _notes.has([h.id, "warn"]) or h.aims_all or h is ShooterHazard \
		or h is HoundeyeHazard
	var effect := "tumble" if h is TrainHazard or h is TentacleHazard else ("bounce" if h is FieldGateHazard else str(h.p["effect"]))
	var want: Array = EFFECTS[effect]
	var what := "%d %-11s %-6s" % [h.id, h.type, mode]
	if mode == "hit":
		var got := _hit_got
		_expect(landed and got[0] == want[0] and is_equal_approx(float(got[1]), float(want[1])),
			"%s %s, state %s grace %.2f (want %s %.1f)%s" % [what, "hit" if landed else "NOT HIT", Kart.State.keys()[got[0]],
			got[1], Kart.State.keys()[want[0]], want[1], "" if fired else ", it never fired"])
	else:
		_expect(not landed and k.state == Kart.State.NORMAL and fired, "%s %s%s" % [what,
			"hit through it" if landed else "not hit", "" if fired else " (it never struck: nothing tested)"])
	k.state = Kart.State.NORMAL
	k.hazard_grace = 0.0
	k.star_time = 0.0
	k.hazard_lock = 0.0
	director._immune.clear()


## A group's immunity lasts while the kart is in the group's stretch (or a little before it) and
## ends once it has driven out: past the end, or GROUP_BACK metres back before the start.
func _group_expiry(rig: Rig, trk: Track, k: Kart) -> void:
	var L := trk.path.length
	for g in director.groups.size():
		var st := director.groups[g]
		for c in [[(st.x + st.y) * 0.5, true, "inside"], [st.x - HazardDirector.GROUP_BACK * 0.5, true, "just before"],
				[st.y + 8.0, false, "past the end"], [st.x - HazardDirector.GROUP_BACK - 12.0, false, "far before"]]:
			# there first (its lap metres follow a frame later), then hit by the group, then a tick
			await _pin(rig, k, _road_pose(trk.path, fposmod(float(c[0]), L), 0.0), Vector3.ZERO)
			await _pin(rig, k, _road_pose(trk.path, fposmod(float(c[0]), L), 0.0), Vector3.ZERO)
			director._immune[k] = g
			await _pin(rig, k, _road_pose(trk.path, fposmod(float(c[0]), L), 0.0), Vector3.ZERO)
			var still: bool = director._immune.get(k, -1) == g
			_expect(still == c[1], "group %d immunity %s (lap s %.0f): %s (want %s)" % [g, c[2], k.lap_progress,
				"kept" if still else "gone", "kept" if c[1] else "gone"])
	director._immune.clear()


## Holds the kart at `xf` (reporting velocity `vel`) through one physics frame, the clock
## running on. Its road position is found afresh (a teleport across the lap is no rescue).
func _pin(rig: Rig, k: Kart, xf: Transform3D, vel: Vector3) -> void:
	k.global_transform = xf
	k.linear_velocity = vel
	k.angular_velocity = Vector3.ZERO
	k.route = -1
	k.route_index = k.track.path.closest(xf.origin)
	k._watch_time = 0.0
	await get_tree().physics_frame
	rig.clock += get_physics_process_delta_time()


## Where and when the kart has to be for hazard h to strike it: {"t0": clock to start at,
## "dur": seconds, "at": Callable(seconds in) -> Transform3D, "ready": Callable() -> bool,
## true once it can strike again, and for the stills "tele" (seconds in) or "tele_warn"
## (seconds after it warned): when its warning shows best}.
func _plan_hit(rig: Rig, h: Hazard) -> Dictionary:
	var p := h.path
	var now := maxf(rig.clock, 1.0)
	if h is TrainHazard:
		var period := h.tm("period")
		var run := maxi(ceili((now + 2.0 - float(h.p["first"])) / period), 0)
		var t_run := float(h.p["first"]) + run * period
		return {"t0": t_run + h.tm("warn") - 1.5, "dur": 5.0, "tele": 0.6,
			"at": func(_u: float) -> Transform3D: return _road_pose(p, h.s, 0.0)}
	if h is FieldGateHazard:
		var g := h as FieldGateHazard
		var tt := now + 1.0
		var lane := -1
		while lane < 0 and tt < now + 60.0:
			var a := g.lanes_at(tt)
			var b := g.lanes_at(tt + 0.6)
			for j in a.size():
				if a[j] == FieldGateHazard.CLOSED and b[j] == FieldGateHazard.CLOSED:
					lane = j
					break
			if lane < 0:
				tt += 0.05
		var mid := (g._posts[maxi(lane, 0)] + g._posts[maxi(lane, 0) + 1]) * 0.5
		# up to the field while it flickers, through it at 8 m/s once it is well and truly closed
		return {"t0": tt - 0.6, "dur": 1.4, "tele": 0.25,
			"at": func(u: float) -> Transform3D: return _pose_at(p, mid - g._fwd * (7.2 - 8.0 * u))}
	if h is StrikeZoneHazard:
		var e: Array = (h as StrikeZoneHazard).strikes(now + 1.5, now + 30.0)[0]
		var spot := (h as StrikeZoneHazard).spot(e)
		return {"t0": float(e[0]) - 1.2, "dur": 1.8, "tele": 0.7, "at": func(_u: float) -> Transform3D: return _pose_at(p, spot)}
	if h is AirStrafeHazard:
		var cy: Array = (h as AirStrafeHazard).cycle_at(now + 2.0)
		var sh: Array = (h as AirStrafeHazard).shot(0 if cy.is_empty() else int(cy[0]) + 1, 5)
		return {"t0": float(sh[0]) - 1.5, "dur": 2.0, "tele": 0.4, "at": func(_u: float) -> Transform3D: return _pose_at(p, sh[1])}
	if h is TentacleHazard:
		var tn := h as TentacleHazard
		var t_hit := tn.next_time(maxf(now, float(h.p["first"])) + 2.5, "t_hit")
		return {"t0": t_hit - 2.0, "dur": 2.8, "tele": 1.35,
			"at": func(_u: float) -> Transform3D: return _road_pose(p, h.s, (tn._cover.x + tn._cover.y) * 0.5)}
	if h is MinefieldHazard:
		# straight at the first mine at 6 m/s: in its range after 0.75 s
		var m: Array = (h as MinefieldHazard)._mines[0]
		var f := p.fwd[p.index_at(float(m[1]))]
		return {"t0": now, "dur": 2.5, "tele": 0.0,
			"at": func(u: float) -> Transform3D: return _pose_at(p, (m[0] as Vector3) - f * (8.0 - 6.0 * u)),
			"ready": func() -> bool: return m[5] and (m[7] as Array).is_empty()}
	if h is TripmineHazard:
		# through the middle of the beam at 8 m/s, 0.75 s in
		var tr := h as TripmineHazard
		var mid := (tr._a + tr._b) * 0.5
		mid.y = tr._floor
		var f := p.fwd[p.index_at(h.s)]
		return {"t0": now, "dur": 1.6, "tele": 0.0, "at": func(u: float) -> Transform3D: return _pose_at(p, mid - f * (6.0 - 8.0 * u)),
			"ready": func() -> bool: return tr._armed}
	if h is ShooterHazard:
		# driving at the gun along the road, steadily: hold your line and you are hit
		var sh := h as ShooterHazard
		return {"t0": now, "dur": 5.0, "tele_warn": 0.5,
			"at": func(u: float) -> Transform3D: return _road_pose(p, h.s - 28.0 + 6.0 * u, 0.0),
			"ready": func() -> bool: return sh.st == ShooterHazard.S.IDLE}
	if h is HoundeyeHazard:
		var hd := h as HoundeyeHazard
		var lat := signf(float(h.p["side"])) * (h.half_width(h.s) - 1.5)
		return {"t0": now, "dur": 4.0, "tele_warn": 0.9,
			"at": func(u: float) -> Transform3D: return _road_pose(p, h.s - 12.0 + 6.0 * u, lat),
			"ready": func() -> bool: return hd.st == HoundeyeHazard.S.IDLE}
	if h is StriderHazard:
		var sd := h as StriderHazard
		var c := sd._cycle_at(now) + 1
		var zone: Array = h.p["zone"]
		return {"t0": sd._cycle_start(c) - 0.3, "dur": h.tm("charge") + 1.5, "tele_warn": 1.2,
			"at": func(u: float) -> Transform3D: return _road_pose(p, float(zone[0]) + 20.0 + 6.0 * u, 0.0)}
	if h is ApacheHazard:
		var ap := h as ApacheHazard
		var every := h.tm("every")
		var t_at := ceilf((now + 0.5) / every) * every
		var zone: Array = h.p["zone"]
		# coming at the helicopter from far enough out (its rockets need 25-110 m)
		var from := float(zone[1]) - 10.0
		while from > float(zone[0]) + 10.0:
			var d := h.road_point(from, 0.0) - ap.hover_at(t_at)
			if Vector2(d.x, d.z).length() > 40.0:
				break
			from -= 5.0
		return {"t0": t_at - 0.3, "dur": 0.35 + float(h.p["flight"]) + 1.0, "tele_warn": 0.6,
			"at": func(u: float) -> Transform3D: return _road_pose(p, from - 1.8 + 6.0 * u, 0.0)}
	return {"t0": now, "dur": 0.1, "tele": 0.0, "at": func(_u: float) -> Transform3D: return _road_pose(p, h.s, 0.0)}


## Two stills of a probe as it is now: from behind the kart towards the hazard, and from the
## roadside across from it.
func _probe_stills(h: Hazard, k: Kart, what: String) -> void:
	var p := h.path
	var i := p.closest(k.global_position)
	var f := p.fwd[i]
	var up := p.up[i]
	var kp := k.global_position
	var hp := h.global_position + Vector3.UP * 2.0
	var near := hp.distance_to(kp) < 70.0 and not h is TentacleHazard
	var look := (kp + hp) * 0.5 if near else kp + f * 12.0 + up * 1.5
	var across := p.lateral(hp, i)
	var side := -signf(across) if absf(across) > 1.0 else 1.0
	var views := [[kp - f * 10.0 + up * 4.5, look], [kp + p.right[i] * 16.0 * side + up * 6.0 + f * 4.0, kp]]
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 3000.0
	add_child(cam)
	# held still while the frames render (a first view can stall): the probe goes on from here
	var held := k.freeze
	k.freeze = true
	for v in views.size():
		cam.look_at_from_position(views[v][0], views[v][1], Vector3.UP)
		cam.make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%02d_%s_%s_%s.png" % [out, h.id, h.type, what, "ab"[v]])
	k.freeze = held
	cam.queue_free()


## A kart standing on the road at lap metres at_s, `lat` metres right of the centre.
func _road_pose(p: TrackPath, at_s: float, lat: float) -> Transform3D:
	var xf := p.transform_at(at_s)
	return Transform3D(xf.basis, xf.origin + xf.basis.x * lat + xf.basis.y * 0.4)


## A kart standing at the world point `pos` (on the road), facing along the lap.
func _pose_at(p: TrackPath, pos: Vector3) -> Transform3D:
	var i := p.closest(pos)
	return Transform3D(p.transform_at(p.progress(pos, i)).basis, pos + p.up[i] * 0.4)


## The scanner's drop point after a rescue anywhere on the lap, and where the Xen portal item
## throws a kart: never inside a hazard's band.
func _drop_points(trk: Track, k: Kart) -> void:
	var p := trk.path
	var bad := []
	var moved := 0
	for at_s in range(0, int(p.length), 2):
		k.route = -1
		k.lap = 0
		k.total_progress = at_s + 12.0
		k._put_back(1.2)
		var landed := p.progress(k.global_position, p.closest(k.global_position))
		if fposmod(landed - at_s, p.length) > 3.0:
			moved += 1
		if _in_band(landed) != "":
			bad.append("rescue at %d -> %.0f in %s" % [at_s, landed, _in_band(landed)])
		k.route = -1
		k.route_index = p.index_at(at_s)
		k.lap_progress = at_s
		k.global_transform = _road_pose(p, at_s, 0.0)
		k.teleport_ahead(80.0)
		var out := p.progress(k.global_position, p.closest(k.global_position))
		if _in_band(out) != "":
			bad.append("portal at %d -> %.0f in %s" % [at_s, out, _in_band(out)])
	_expect(bad.is_empty(), "drop points: %d of %d rescues moved, none in a band %s" % [moved, int(p.length / 2.0),
		"" if bad.is_empty() else str(bad.slice(0, 6))])
	k.star_time = 0.0
	k.boost_time = 0.0


## A gate on the main road halfway along each branch's lap span: it advises a kart driving the
## main road, not one that plans to take the branch round it, nor one already on the branch.
func _branch_advice(trk: Track, k: Kart) -> void:
	var p := trk.path
	for br in p.branches:
		var at := fposmod(br.fork_s + fposmod(br.merge_s - br.fork_s, p.length) * 0.5, p.length)
		var d := HazardDirector.new()
		trk.add_child(d)
		d.setup(trk, [{"id": 0, "type": "field_gate", "s": at, "span": [at - 8.0, at + 4.0]}])
		var from := fposmod(br.fork_s - 30.0, p.length)
		k.route = -1
		k.global_transform = _road_pose(p, from, 0.0)
		k.route_index = p.index_at(from)
		k.path_index = k.route_index
		k.lap_progress = from
		var main: Dictionary = d.advice(k, from, 25.0, {})
		var turning: Dictionary = d.advice(k, from, 25.0, {br.index: true})
		k.route = br.index
		k.route_u = br.length * 0.5
		k.lap_progress = br.main_s(k.route_u)
		var on_it: Dictionary = d.advice(k, k.lap_progress, 25.0, {br.index: true})
		var says := func(a: Dictionary) -> bool: return int(a["id"]) == 0 or int(a["vid"]) == 0
		_expect(says.call(main) and not says.call(turning) and not says.call(on_it),
			"branch %s: a gate at s %.0f advises the main road %s, a kart turning off %s, one on the branch %s"
			% [br.id, at, says.call(main), says.call(turning), says.call(on_it)])
		d.free()
	k.route = -1


## The hazard whose band (blocks_respawn) lap metres at_s is inside of, by more than a metre
## (a drop on the very edge of one is not in it); "" for none.
func _in_band(at_s: float) -> String:
	for h in director.list:
		if h.blocks_respawn(at_s - 1.0) and h.blocks_respawn(at_s + 1.0):
			return h.type
	return ""


# ---------------------------------------------------------------- network
## One peer of the online test. Log lines (wall clock first, so peers can be lined up):
##   CLOCK <unix> <Net.now> <hazard clock> <synced>
##   NOTE <unix> <hazard clock> <id> <type> <what> <kart slot> [due <clock it strikes at>]
class NetRun:
	extends Node
	var args: Array = []
	var defs: Array
	var limit := 150.0
	var t := 0.0
	var director: HazardDirector
	var _log_t := 0.0
	var _forced := false
	var _count := {}

	func _init(a: Array, d: Array) -> void:
		var skip := false
		for x in a:
			if skip:
				skip = false
			elif x == "--fakelag":
				skip = true
			elif not str(x).begins_with("--"):
				args.append(x)
		defs = d
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		var port := int(args[1])
		limit = float(args[3])
		Net.state_changed.connect(func(s: String): print("STATE ", s))
		if args[0] == "host":
			Net.host({"name": "hazard test", "port": port, "bots": true, "grid": 6, "laps": 1, "difficulty": 1,
				"track": str(args[2]), "hazards": 1, "lan_only": true}, true)
			print("HOST on port %d, %s" % [port, args[2]])
			return
		Game.settings["nickname"] = str(args[2])
		Net.joined.connect(func(): Net.set_profile(Game.settings["character"], Game.settings["vehicle"], true))
		Net.connect_failed.connect(func(r): print("CONNECT FAILED ", r))
		Net.join("127.0.0.1", port)

	func _physics_process(delta: float) -> void:
		t += delta
		if t > limit:
			print("SUMMARY %s %s" % [args[0], str(_count)])
			Net.leave()
			get_tree().quit()
			return
		var race = Net.race
		if race == null or not is_instance_valid(race) or race.get("track") == null:
			return
		if director == null or not is_instance_valid(director):
			race.track.hazards.queue_free()
			director = HazardDirector.new()
			race.track.add_child(director)
			race.track.hazards = director
			director.setup(race.track, defs)
			director.noted.connect(_on_noted.bind(race))
			print("HAZARDS %d" % director.list.size())
		_log_t -= delta
		if _log_t <= 0.0:
			_log_t = 1.0
			print("CLOCK %.4f %.4f %.4f %s" % [Time.get_unix_time_from_system(), Net.now(), race.hazard_clock(), Net.clock_synced()])
		if not Net.is_server and not _forced and race.hazard_clock() > 4.0:
			_forced = true
			_set_off(race)

	## This client sets off the first tripmine or hopper mine itself (as its kart would).
	func _set_off(race: Node) -> void:
		for h in director.list:
			if h is TripmineHazard:
				var tr := h as TripmineHazard
				h.send("trip", [0, race.hazard_clock(), tr._a.x, tr._a.y, tr._a.z])
				print("SENT trip %d" % h.id)
				return
			if h is MinefieldHazard:
				h.send("pop", [0, race.hazard_clock(), director.slot_of(race.player)])
				print("SENT pop %d" % h.id)
				return

	func _on_noted(h: Hazard, what: String, k: Kart, race: Node) -> void:
		var key := "%d %s %s" % [h.id, h.type, what]
		_count[key] = int(_count.get(key, 0)) + 1
		# what the event carried, the same on every peer: when the shot lands, when the mine re-arms
		var due := ""
		if what == "warn" and h is StriderHazard and not (h as StriderHazard)._aims.is_empty():
			due = " due %.3f" % float((h as StriderHazard)._aims.values()[-1][0])
		elif what == "warn" and h is ApacheHazard and not (h as ApacheHazard)._salvos.is_empty():
			due = " due %.3f" % (float((h as ApacheHazard)._salvos[-1][0]) + float(h.p["flight"]))
		elif what == "fire" and h is TripmineHazard:
			due = " due %.3f" % (h as TripmineHazard)._rearm_at
		elif what == "fire" and h is MinefieldHazard:
			due = " due %.3f" % (h as MinefieldHazard)._mines.map(func(m: Array) -> float: return float(m[6])).max()
		print("NOTE %.4f %.3f %d %s %s %d%s" % [Time.get_unix_time_from_system(), race.hazard_clock(), h.id, h.type, what,
			director.slot_of(k) if k else -1, due])


# ---------------------------------------------------------------- views
func _view(a: Array) -> void:
	var trk := Track.new()
	add_child(trk)
	trk.build(str(a[0]))
	if not _override.is_empty():
		trk.hazards.queue_free()
		trk.hazards = HazardDirector.new()
		trk.add_child(trk.hazards)
		trk.hazards.setup(trk, _override)
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	await get_tree().create_timer(float(a[4]) if a.size() > 4 else 2.0).timeout
	var from_v := str(a[1]).split_floats(",")
	var from := Vector3(from_v[0], from_v[1], from_v[2])
	var at: Vector3
	if str(a[2]).begins_with("bird"):
		for bg: BackgroundLife in trk.find_children("*", "BackgroundLife", false, false):
			at = bg.birds[int(str(a[2]).substr(4))].global_position
		from += at
	else:
		var at_v := str(a[2]).split_floats(",")
		at = Vector3(at_v[0], at_v[1], at_v[2])
	cam.look_at_from_position(from, at, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(str(a[3]))
	get_tree().quit()


# ---------------------------------------------------------------- rig poses
func _poses(prefix: String) -> void:
	var data: Dictionary = Game.load_json("res://assets/track/ct17.json")
	var trk := Track.new()
	trk.data = data
	trk.path = TrackPath.new(data["path"])
	add_child(trk)
	var d := HazardDirector.new()
	trk.add_child(d)
	d.set_physics_process(false)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var at := Vector3(0.0, 2000.0, 0.0)   # well away from the track geometry (none is loaded)
	var shots := [
		["turret", {"model": "hl1/sentry", "scale": 1.3}, [[0.0, 0.0], [0.8, 0.0], [-0.8, 0.4], [0.0, -0.5]], 4.0],
		["turret", {"model": "combine_turrets/floor_turret", "fallback": "hl1/sentry", "scale": 1.4},
			[[0.0, 0.0], [0.7, 0.3]], 4.0],
		["turret", {"mount": "ceiling", "model": "hl1/turret", "scale": 1.5}, [[0.0, 0.0], [0.6, -0.4]], 5.0],
		["vortigaunt", {"model": "hl1/islave", "scale": 1.3}, [[0.0, 0.0], [0.6, 0.0]], 4.0],
	]
	var mark := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.06
	ball.height = 0.12
	mark.mesh = ball
	add_child(mark)
	for sh in shots:
		var h: ShooterHazard = HazardDirector.script_for(sh[0]).new()
		d.add_child(h)
		h.setup({"id": 0, "type": sh[0], "s": 0.0, "pos": [at.x, at.y, at.z], "yaw": 0.0, "p": sh[1]}, trk, d)
		var dist: float = sh[3]
		# a ceiling turret hangs: look at it from below
		var below := -1.0 if sh[1].get("mount") == "ceiling" else 1.0
		cam.look_at_from_position(at + Vector3(dist * 0.8, dist * 0.45 * below, dist * 0.9), at + Vector3.UP * 0.8 * below)
		for k in (sh[2] as Array).size():
			var yp: Array = sh[2][k]
			if h is TurretHazard:
				(h as TurretHazard)._deploy = 0.0 if sh[1].get("mount") == "ceiling" and k == 0 else 1.0
			if h is VortigauntHazard:
				h.st = ShooterHazard.S.LOCK if k > 0 else ShooterHazard.S.IDLE
				h.st_t = h.lock_time()
			h.yaw_now = yp[0]
			h.pitch_now = yp[1]
			h.pose()
			mark.global_position = h.muzzle_now()
			await _snap("%s_%s_%s_%d.png" % [prefix, sh[0], str(sh[1]["model"]).get_file(), k])
		h.queue_free()
	mark.queue_free()
	await _pose_strider(d, trk, cam, at, prefix)
	await _pose_tentacle(d, trk, cam, prefix)
	print("poses saved to ", prefix)
	get_tree().quit()


func _pose_strider(d: HazardDirector, trk: Track, cam: Camera3D, at: Vector3, prefix: String) -> void:
	var h := StriderHazard.new()
	d.add_child(h)
	h.setup({"id": 1, "type": "strider", "s": 0.0, "pos": [at.x, at.y, at.z], "yaw": 0.0, "p": {}}, trk, d)
	cam.look_at_from_position(at + Vector3(16.0, 9.0, 16.0), at + Vector3.UP * 7.0)
	for k in 3:
		h._crouch = [0.0, StriderHazard.CROUCH, 0.0][k]
		for i in 60:
			h._pose(1.0, at + [Vector3(0, 0, 40), Vector3(-15, 0, 30), Vector3(20, 4, 20)][k], 1.0 / 30.0)
		var g := h.gun_at()
		var mark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		mark.mesh = sm
		add_child(mark)
		mark.global_position = g
		await _snap("%s_strider_%d.png" % [prefix, k])
		mark.queue_free()
	h.queue_free()


func _pose_tentacle(d: HazardDirector, trk: Track, cam: Camera3D, prefix: String) -> void:
	# beside the road at s = 0: the base 24 m below the deck and 4 m out from its edge, so
	# it grows to reach the default cover the way it does on a track (+Z towards the road)
	var c := trk.path.center_at(0.0)
	var r := Vector3(trk.path.right[0].x, 0.0, trk.path.right[0].z).normalized()
	var hw: float = trk.path.width[0] * 0.5
	var base := c - r * (hw + 4.0) + Vector3.DOWN * 24.0
	var h := TentacleHazard.new()
	d.add_child(h)
	h.setup({"id": 2, "type": "tentacle", "s": 0.0, "pos": [base.x, base.y, base.z], "yaw": atan2(r.x, r.z), "p": {}}, trk, d)
	var deck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30.0, 0.5, hw * 2.0)
	deck.mesh = bm
	add_child(deck)
	deck.global_transform = Transform3D(h.global_basis, c + Vector3.DOWN * 0.25)
	cam.look_at_from_position(h.to_global(Vector3(-40.0, 30.0, 10.0)), h.to_global(Vector3(0.0, 18.0, 6.0)))
	var names := ["idle", "rear", "slam"]
	var poses := [h._idle_pose(0.0), h._rear_pose(0.0), h._slam]
	for k in 3:
		h._apply(poses[k])
		await _snap("%s_tentacle_%s.png" % [prefix, names[k]])
	print("tentacle: grown x%.2f, the slam covers %.1f..%.1f m of a road %.1f m wide (asked %s)"
		% [h.model.scale.x / float(h.p["scale"]), h._cover.x, h._cover.y, hw * 2.0, str(h.p["cover"])])
	h.queue_free()


func _snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(file)
