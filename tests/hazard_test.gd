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
##     it; the groups are printed). A crane's magnet must also warn before it catches, drop the
##     kart it caught on the road ahead, leave that kart alone on the rest of its pass and never
##     catch a kart being rescued or one outside its radius. An antlion zone must wake for a kart
##     that leaves the road for its sand, warn at least its warning time before it bites, miss a kart
##     that gets back onto the far side of the road after the warning ("far") and never wake for one
##     that keeps to the road by the sand's edge ("never"). An antlion guard must warn at least its
##     warning time before it shoves, shove (tumble and throw) a kart its body reaches and never one
##     hit by its group on this pass, being rescued, charged, just hit, a metre clear of its body or
##     on a road above or below it; never come out for a kart being rescued or one standing still;
##     keep off the road while it stands, roars or walks home, leave the road soon after each charge
##     and pull up on the ground. A marching column must warn at least 1.2 s before its fire lands
##     and at least its warning time before it hits, spin a kart standing in a strip it fires on and
##     never one charged, just hit, hit by its group on this pass, being rescued or a little outside
##     the strip; ignore a burst forged for while it marches or off its zone's road; advise a bot out
##     of a strip; and never stand a soldier on a road over a whole cycle of its march. Then every drop point of the scanner
##     and of the Xen portal item along the lap must land outside every hazard's band. With out_prefix (and a
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
	"bounce": [Kart.State.SPIN, 1.6], "magnet": [Kart.State.SPIN, 1.6], "shove": [Kart.State.TUMBLE, 2.4]}

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
var _far := false       # rules: the houndeye probe drives the far side of the road (out of reach)
var _mode := ""         # rules: the probe being run (an antlion zone's plan: onto its sand, or along its edge)


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
	# an antlion zone only moves after a server-sent wake: both get the same one, mid-way to 33.3 s
	for i in a.list.size():
		if a.list[i] is AntlionHazard:
			var ev: Array = (a.list[i] as AntlionHazard).test_event(31.0)
			a.list[i].on_event("wake", ev)
			b.list[i].on_event("wake", ev.duplicate())
		# an antlion guard only runs after a server-sent charge: both get the same one at 31 s
		if a.list[i] is AntlionGuardHazard:
			var gv: Array = (a.list[i] as AntlionGuardHazard).test_event(31.0)
			a.list[i].on_event("charge", gv)
			b.list[i].on_event("charge", gv.duplicate())
		# a marching column only fires after a server-sent burst: both get the same one in its first watch
		# from 31 s on
		if a.list[i] is CombineColumnHazard:
			var cv: Array = (a.list[i] as CombineColumnHazard).test_event(31.0)
			a.list[i].on_event("burst", cv)
			b.list[i].on_event("burst", cv.duplicate())
		# a see-saw only turns by the authority's tilt events: both get the same two from 31 s
		if a.list[i] is SeesawHazard:
			for ev in (a.list[i] as SeesawHazard).test_events(31.0):
				a.list[i].on_event("tilt", ev)
				b.list[i].on_event("tilt", (ev as Array).duplicate())
	print("%d hazards on %s" % [a.list.size(), track_id])
	# the same clock gives the same state, in any order
	for ct in CHECK_TIMES:
		_expect(_state(a, ct) == _state(b, ct), "same state at t=%.1f" % ct)
	_expect(_state(a, 61.0) == _state(a, 61.0) and _state(b, 300.0) == _state(b, 300.0), "repeatable")
	# an antlion guard through its whole run (warning, charge, pull-up, aside, roar, the walk home)
	for i in a.list.size():
		if a.list[i] is AntlionGuardHazard:
			var same := true
			for j in 120:
				var ct := 30.0 + j * 0.25
				same = same and var_to_str(a.list[i].snapshot(ct)) == var_to_str(b.list[i].snapshot(ct))
			_expect(same, "%d antlion_guard  same place every 0.25 s through its run" % a.list[i].id)
		# a marching column through a whole cycle of its march, its burst among it: every soldier
		if a.list[i] is CombineColumnHazard:
			var cc := a.list[i] as CombineColumnHazard
			var same := true
			var bursts := 0
			for j in int(cc.cycle() / 0.25) + 1:
				var ct := 30.0 + j * 0.25
				same = same and var_to_str(cc.snapshot(ct)) == var_to_str(b.list[i].snapshot(ct))
				bursts += int(cc.is_active(ct))
			_expect(same and bursts > 0, "%d column  every soldier in the same place every 0.25 s through a cycle (%.0f s), its burst %s"
				% [cc.id, cc.cycle(), "in it" if bursts > 0 else "NOT SEEN"])
		# a see-saw through both its swings: the same angle every 0.05 s, and it did turn
		if a.list[i] is SeesawHazard:
			var same := true
			var turned := false
			for j in 100:
				var ct := 30.5 + j * 0.05
				same = same and var_to_str(a.list[i].snapshot(ct)) == var_to_str(b.list[i].snapshot(ct))
				turned = turned or float(a.list[i].snapshot(ct)[2]) != 0.0
			_expect(same and turned, "%d seesaw  the same angle every 0.05 s through its swings%s" % [a.list[i].id,
				"" if turned else " (it NEVER TURNED)"])
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
		if not h.type in ["train", "field_gate", "strike_zone", "air_strafe", "tentacle", "crane"]:
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
	var all_hz := director.list.duplicate()
	for h in all_hz:
		# an antlion guard's probes drive the kart through its whole zone: the other hazards there
		# (which could spin it on the way in and leave it immune to the guard's group) are set aside
		if h is AntlionGuardHazard or h is CombineColumnHazard:
			director.list.assign([h])
		# a train on a line beside or over the road never touches a kart: its own rules, no hit probes
		if h is TrainHazard and not h.on_map():
			if out == "":
				await _pass_train_rules(rig, h as TrainHazard, k)
			continue
		# a see-saw bridge never hurts a kart: its own rules (it tips towards the karts' weight, its deck is
		# where they ride), no hit probes
		if h is SeesawHazard:
			if out == "":
				await _seesaw_rules(rig, h as SeesawHazard, k)
			continue
		for mode in ["hit"] if out != "" else ["hit", "star", "immune", "group"]:
			await _probe(rig, h, k, mode)
		# a kart that heeds the houndeyes' chirp and keeps to the far side is out of their reach (and
		# one back on the far side of the road once the antlions' sand bulges)
		if (h is HoundeyeHazard or h is AntlionHazard) and out == "":
			_far = true
			await _probe(rig, h, k, "far")
			_far = false
		# a kart that keeps to the road by the antlions' sand never wakes them
		if h is AntlionHazard and out == "":
			await _probe(rig, h, k, "never")
		if h is CraneHazard and out == "":
			await _crane_rules(rig, h as CraneHazard, k)
		if h is AntlionGuardHazard and out == "":
			await _guard_rules(rig, h as AntlionGuardHazard, k)
		if h is CombineColumnHazard and out == "":
			await _column_rules(rig, h as CombineColumnHazard, k)
		if h is TrainHazard and str(h.p.get("mode", "")) == "cross" and out == "":
			await _crossing_rules(rig, h as TrainHazard, k)
		director.list.assign(all_hz)
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
	_mode = mode
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
	var hit_u := -1.0
	var shot := mode != "hit" or out == ""
	while u < float(plan["dur"]) and not landed:
		var xf: Transform3D = at.call(u)
		var vel: Vector3 = ((at.call(u + 0.02) as Transform3D).origin - xf.origin) / 0.02
		await _pin(rig, k, xf, vel)
		u += get_physics_process_delta_time()
		landed = _notes.has([h.id, "hit"])
		if warned < 0.0 and _notes.has([h.id, "warn"]):
			warned = u
		if landed and hit_u < 0.0:
			hit_u = u
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
		if h is AntlionHazard:
			_expect(warned >= 0.0 and hit_u - warned >= h.tm("warn") * 0.9, "%s warned %.2f s before it bit (want >= %.2f)"
				% [what, hit_u - warned, h.tm("warn") * 0.9])
		if h is AntlionGuardHazard:
			_expect(warned >= 0.0 and hit_u - warned >= h.tm("warn") * 0.95, "%s warned %.2f s before it shoved (want >= %.2f)"
				% [what, hit_u - warned, h.tm("warn") * 0.95])
		if h is CombineColumnHazard:
			_expect(warned >= 0.0 and hit_u - warned >= h.tm("warn") * 0.95, "%s warned %.2f s before its fire hit (want >= %.2f)"
				% [what, hit_u - warned, h.tm("warn") * 0.95])
	elif mode == "never":
		var woke := _notes.has([h.id, "warn"])
		_expect(not woke and not landed and k.state == Kart.State.NORMAL, "%s %s" % [what,
			"WOKE for a kart on the road" if woke else "asleep for a kart on the road by its sand"])
	elif mode == "far":
		var blasted := _notes.has([h.id, "fire"])
		_expect(not landed and k.state == Kart.State.NORMAL and blasted, "%s %s%s" % [what,
			"HIT on the far side" if landed else "not hit on the far side", "" if blasted else " (it never blasted: nothing tested)"])
	else:
		_expect(not landed and k.state == Kart.State.NORMAL and fired, "%s %s%s" % [what,
			"hit through it" if landed else "not hit", "" if fired else " (it never struck: nothing tested)"])
	k.state = Kart.State.NORMAL
	k.hazard_grace = 0.0
	k.star_time = 0.0
	k.hazard_lock = 0.0
	k._magnet = null  # (a crane's magnet that caught it lets go: the next probe drives it itself)
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
		# (when its crossing warns: a forest crossing's runs start up to its jitter late, one on a whole
		# railway starts as the train leaves the line's first end; its guard forgets whom it held on the
		# probes before, so this run goes)
		var t_run := (h as TrainHazard)._warn_at(run)
		_forget_held(h as TrainHazard)
		# where its line crosses the road (the game's lap metres drift a few metres from the
		# generator's late in a lap: its s alone can miss a slanted line)
		return {"t0": t_run + h.tm("warn") - 1.5, "dur": 5.0, "tele": 0.6,
			"at": func(_u: float) -> Transform3D: return _pose_at(p, h.global_position)}
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
		# along the pack's side of the road, or (_far) where the bots go when they hear the chirp
		var lat := signf(float(h.p["side"])) * (h.half_width(h.s) - 1.5)
		if _far:
			lat = -signf(float(h.p["side"])) * (h.half_width(h.s) - HoundeyeHazard.FAR_LANE)
		return {"t0": now, "dur": 4.0, "tele_warn": 0.9,
			"at": func(u: float) -> Transform3D: return _road_pose(p, h.s - 12.0 + 6.0 * u, lat),
			"ready": func() -> bool: return hd.st == HoundeyeHazard.S.IDLE}
	if h is StriderHazard:
		var sd := h as StriderHazard
		var c := sd.next_halt(sd._cycle_at(now) + 1)
		# through the road point its station looks at (a walking strider halts somewhere else each
		# cycle, and walks on through a station on a road crossing)
		var at_s := sd.probe_s(c) - 6.0
		return {"t0": sd._cycle_start(c) - 0.3, "dur": h.tm("charge") + 1.5, "tele_warn": 1.2,
			"at": func(u: float) -> Transform3D: return _road_pose(p, at_s + 6.0 * u, 0.0)}
	if h is ControllerHazard:
		# down the middle of the road at 8 m/s, at the road beside its throw as the ball lands
		var ct := h as ControllerHazard
		# the other controllers hold their throws (one beside it would hit first and leave the kart
		# immune to its group); this one throws in any cycle again
		for o in h.director.list:
			if o is ControllerHazard:
				(o as ControllerHazard)._thrown = -1000000 if o == h else 1 << 30
		var c := ct._cycle_at(now + 1.0) + 1
		var t_c := ct._cycle_start(c)
		var lead_t := h.tm("warn") + float(h.p["flight"])
		var from := ct.throw_point(t_c + h.tm("warn"))
		var zone: Array = h.p["zone"]
		var land := clampf(p.progress(from, p.closest(from, p.index_at(h.s))), float(zone[0]) + 10.0, float(zone[1]) - 5.0)
		var s0 := land - 8.0 * (0.3 + lead_t)
		return {"t0": t_c - 0.3, "dur": 0.3 + lead_t + 0.8, "tele_warn": 0.8,
			"at": func(u: float) -> Transform3D: return _road_pose(p, s0 + 8.0 * u, 0.0),
			"ready": func() -> bool: return ct._aims.is_empty()}
	if h is BullsquidHazard:
		# up the road at 10 m/s from short of its zone: it spits as the kart's landing point comes in
		var bq := h as BullsquidHazard
		var zone: Array = h.p["zone"]
		var s0 := float(zone[0]) - 10.0 * (h.tm("warn") + float(h.p["flight"])) - 8.0
		return {"t0": now, "dur": 6.0, "tele_warn": 0.6,
			"at": func(u: float) -> Transform3D: return _road_pose(p, s0 + 10.0 * u, 0.0),
			"ready": func() -> bool: return bq._spits.is_empty() and h.director.clock() >= bq._ready_at}
	if h is AntlionHazard:
		# off the road onto its sand at 16 m/s, holding a line 4.5 m out; "far": back over to the far side
		# of the road once warned (by 0.9 s in with the default grace of 0.4 s on the sand, later for a
		# zone that waits longer); "never": along the road 1.2 m in from the sand's edge
		var an := h as AntlionHazard
		var zone: Array = h.p["zone"]
		var sd := float(an.sand_side())
		var s0 := float(zone[0]) + 5.0
		var hw := h.half_width(s0)
		var mode := _mode
		var back := 0.5 + float(h.p["grace"])
		var lat_at := func(u: float) -> float:
			if mode == "never":
				return sd * (hw - 1.2)
			var out_lat := sd * lerpf(hw - 1.5, hw + 4.5, clampf((u - 0.3) / 0.6, 0.0, 1.0))
			if mode == "far":
				return lerpf(out_lat, -sd * (hw - 1.5), clampf((u - back) / 0.9, 0.0, 1.0))
			return out_lat
		return {"t0": now, "dur": (float(zone[1]) - float(zone[0])) / 16.0 if mode == "never" else 5.5, "tele_warn": 0.5,
			"at": func(u: float) -> Transform3D: return _ground_pose(p, s0 + 16.0 * u, lat_at.call(u)),
			"ready": func() -> bool: return an.idle()}
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
	if h is CraneHazard:
		# onto the next cycle's spot as the magnet comes down, creeping through it while it catches
		var cr := h as CraneHazard
		var c := cr.cycle_at(now + 1.0) + 1
		var a := cr.spot(c)
		return {"t0": cr.cycle_start(c) + cr.key(CraneHazard.LOW) - 0.6, "dur": 0.6 + h.tm("active") + 0.4, "tele_warn": 0.8,
			"at": func(u: float) -> Transform3D: return _road_pose(p, a.x - 1.0 + 1.5 * u, a.y),
			"ready": func() -> bool: return cr._held.is_empty()}
	if h is AntlionGuardHazard:
		# down the middle of the road at 22 m/s from short of the guard's home: it comes out for the kart
		# and rams it where it will be (the kart holds its line and its speed)
		var ag := h as AntlionGuardHazard
		var zone: Array = h.p["zone"]
		var s0 := ag.home_s() - minf(120.0, h.ahead(float(zone[0]), ag.home_s()) + 20.0)
		return {"t0": now, "dur": 8.0, "tele_warn": 0.8,
			"at": func(u: float) -> Transform3D: return _road_pose(p, s0 + 22.0 * u, 0.0),
			"ready": func() -> bool: return ag.can_charge(ag.director.clock()) and ag.idle()}
	if h is CombineColumnHazard:
		# down the middle of the road at 20 m/s from 35 m short of its zone (inside its group's stretch, so a
		# group's immunity holds), setting off as the column has turned to the road on its next watch: it aims
		# a burst at where the kart will be, which holds its line
		var cc := h as CombineColumnHazard
		var w := cc.next_watch(now + 1.0)
		var zone := cc.zone_at(float(w[0]) + cc.settle())
		var s0 := float(zone[0]) - 35.0
		return {"t0": float(w[0]) + cc.settle(), "dur": 6.0, "tele_warn": 0.8,
			"at": func(u: float) -> Transform3D: return _road_pose(p, s0 + 20.0 * u, 0.0),
			"ready": func() -> bool: return cc.idle()}
	return {"t0": now, "dur": 0.1, "tele": 0.0, "at": func(_u: float) -> Transform3D: return _road_pose(p, h.s, 0.0)}


## An antlion guard's own rules: (1) its body shoves a kart it reaches (tumbled, thrown away from it with
## a hop) and never one hit by its group on this pass, being rescued, charged, just hit, a metre clear of
## its body or on a road 5 m above or below; (2) it never comes out for a kart being rescued, nor (3) for
## one standing still in its zone; (4) while it stands, roars or walks home (every run it made in this
## test) it is off the racing line (its body and a metre clear of it) and, unless it lives on a deck
## (a negative p["keep"]), off the road; and off the road at most 2.5 s after each charge's meeting
## point unless on a deck; (5) it pulls up on the ground.
func _guard_rules(rig: Rig, h: AntlionGuardHazard, k: Kart) -> void:
	var p := h.path
	var sc := float(h.p["scale"])
	# (1) its body, on a made-up step of a charge: its hips a metre behind the kart on the way it runs
	await _guard_idle(rig, h, k)
	var at_s := h.home_s() + 15.0
	var xf := _road_pose(p, at_s, 0.0)
	var dir := h.road_point(at_s, 0.0) - h.home()
	dir.y = 0.0
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	var clear := right * (AntlionGuardHazard.BODY_HALF * sc + AntlionGuardHazard.KART_R + 1.0)
	for c in [["reached", "", true, Vector3.ZERO], ["hit by its group", "group", false, Vector3.ZERO],
			["being rescued", "respawn", false, Vector3.ZERO], ["charged", "star", false, Vector3.ZERO],
			["just hit", "grace", false, Vector3.ZERO], ["a metre clear of its body", "", false, clear],
			["5 m above it", "", false, Vector3.UP * 5.0], ["5 m below it", "", false, Vector3.DOWN * 5.0]]:
		director._immune.clear()
		k.state = Kart.State.NORMAL
		k.hazard_grace = 0.0
		k.star_time = 0.0
		await _pin(rig, k, xf, Vector3.ZERO)
		await _pin(rig, k, xf, Vector3.ZERO)
		match str(c[1]):
			"group":
				director._immune[k] = h.group
			"respawn":
				k.state = Kart.State.RESPAWN
			"star":
				k.star_time = 5.0
			"grace":
				k.hazard_grace = 5.0
		_notes.clear()
		var fake := {"hit": false}
		var g: Vector3 = k.global_position - dir * 1.0 - (c[3] as Vector3)
		h._ram(fake, [g, dir, AntlionGuardHazard.Ph.CHARGE, 0.5, fake, 3.0])
		var hit := _notes.has([h.id, "hit"])
		var v := k.linear_velocity
		var how := ""
		if hit:
			how = ", %s grace %.1f, thrown %.1f m/s away from it, %.1f up" % [Kart.State.keys()[k.state], k.hazard_grace,
				(v - Vector3.UP * v.y).dot(dir), v.y]
		var ok: bool = hit == bool(c[2])
		if hit and bool(c[2]):
			ok = k.state == Kart.State.TUMBLE and is_equal_approx(k.hazard_grace, 2.4) and (v - Vector3.UP * v.y).dot(dir) > 5.0 \
				and v.y > 3.0
		_expect(ok, "%d antlion_guard  a kart %s: %s%s" % [h.id, c[0], "shoved" if hit else "left alone", how])
	k.state = Kart.State.NORMAL
	k.hazard_grace = 0.0
	k.star_time = 0.0
	director._immune.clear()
	# (2) a kart being rescued all the way through its zone, and (3) one standing in it: it never comes out
	await _guard_idle(rig, h, k)
	var plan := _plan_hit(rig, h)
	var at: Callable = plan["at"]
	_notes.clear()
	var u := 0.0
	while u < float(plan["dur"]):
		k.state = Kart.State.RESPAWN
		k.state_time = 0.0
		var x0: Transform3D = at.call(u)
		await _pin(rig, k, x0, ((at.call(u + 0.02) as Transform3D).origin - x0.origin) / 0.02)
		u += get_physics_process_delta_time()
	k.state = Kart.State.NORMAL
	k.state_time = 0.0
	_expect(not _notes.has([h.id, "warn"]), "%d antlion_guard  never came out for a kart being rescued through its zone" % h.id)
	_notes.clear()
	var stand := _road_pose(p, h.home_s() - 10.0, 0.0)
	u = 0.0
	while u < 5.0:
		await _pin(rig, k, stand, Vector3.ZERO)
		u += get_physics_process_delta_time()
	_expect(not _notes.has([h.id, "warn"]), "%d antlion_guard  never came out for a kart standing in its zone" % h.id)
	# (4) and (5), over every run it made in this test
	var worst_idle := -INF
	var worst_line := INF
	var deck := float(h.p["keep"]) < 0.0
	var worst_road := 0.0
	var not_ground := 0
	var runs := 0
	var space := get_viewport().find_world_3d().direct_space_state
	for sn in h._order:
		var run: Dictionary = h._runs[sn]
		runs += 1
		var on := 0.0
		var t := float(run["t0"])
		while t < float(run["t_home"]) + 1.0:
			var st := h.state_at(t)
			if int((st[4] as Dictionary).get("sn", -1)) != int(sn):
				break
			var q: Vector3 = st[0]
			var i := p.closest(q, p.index_at(h.home_s()))
			var inside := p.width[i] * 0.5 - absf(p.lateral(q, i))
			var level := absf(q.y - p.center[i].y) < 3.0
			var ph := int(st[2])
			if level and ph in [AntlionGuardHazard.Ph.IDLE, AntlionGuardHazard.Ph.HOME, AntlionGuardHazard.Ph.ROAR]:
				worst_idle = maxf(worst_idle, inside)
				var ln := p.line_at(p.progress(q, i))
				worst_line = minf(worst_line, Vector2(q.x - ln.x, q.z - ln.z).length())
			if level and inside > 0.0 and t >= float(run["t_meet"]):
				on += 0.05
			t += 0.05
		worst_road = maxf(worst_road, on)
		var e: Vector3 = run["E"]
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(e + Vector3.UP * 1.5, e - Vector3.UP * 1.5, Game.LAYER_WORLD)).is_empty():
			not_ground += 1
	_expect(runs > 0 and (deck or worst_idle < -0.5) and worst_line >= AntlionGuardHazard.BODY_HALF * sc + 1.0,
		"%d antlion_guard  off the %s while it stands, roars or walks home (%d runs, at worst %.1f m %s the edge, %.1f m from the racing line)"
		% [h.id, "racing line" if deck else "road", runs, absf(worst_idle), "inside" if worst_idle > 0.0 else "outside", worst_line])
	_expect(deck or worst_road <= 2.5, "%d antlion_guard  on the road at most %.2f s after a charge's meeting point (want <= 2.5%s)"
		% [h.id, worst_road, "; it lives on a deck, so not counted" if deck else ""])
	_expect(not_ground == 0, "%d antlion_guard  pulled up on the ground every time (%d not)" % [h.id, not_ground])
	await _guard_idle(rig, h, k)
	director._immune.clear()


## Parks the kart short of the guard's zone until the guard is back at rest and may charge again.
func _guard_idle(rig: Rig, h: AntlionGuardHazard, k: Kart) -> void:
	var park := _road_pose(h.path, h.span.x - 60.0, 0.0)
	var waited := 0.0
	while (not h.can_charge(rig.clock) or not h.idle()) and waited < 40.0:
		await _pin(rig, k, park, Vector3.ZERO)
		waited += get_physics_process_delta_time()
	k.state = Kart.State.NORMAL
	k.hazard_grace = 0.0
	k.star_time = 0.0


## A marching column's own rules, each on a burst of its own sent at a kart parked on the road (as the
## authority sends them): (1) its warning is at least 1.2 s and a kart standing in the strip spins, warned
## at least the warning time before; (2) never a kart charged, just hit, hit by the column's group on this
## pass, being rescued, or standing a little outside the strip; (3) a burst forged for while it marches,
## or for a strip off its zone's road, is ignored; (4) a bot coming at a strip is advised out of it; (5)
## the authority sends no burst for a kart standing still; (6) over a whole cycle of its march no soldier
## stands on a road (the lap or a branch: within its edge and less than HEADROOM over or under it).
func _column_rules(rig: Rig, h: CombineColumnHazard, k: Kart) -> void:
	var p := h.path
	director._immune.clear()
	var sw := float(h.p["strip_w"])
	_expect(h.tm("warn") >= 1.2, "%d column  warns %.2f s before its fire (want >= 1.2)" % [h.id, h.tm("warn")])
	var bursts0 := int(h.stats["bursts"])
	var cases := [["hit", 0.0, true], ["star", 0.0, false], ["grace", 0.0, false], ["group", 0.0, false],
		["rescued", 0.0, false], ["beside", sw * 0.5 + CombineColumnHazard.KART_R + 0.6, false]]
	for i in cases.size():
		var c: Array = cases[i]
		var w := h.next_watch(rig.clock + 0.5)
		# the middle of the zone it watches then, a lane in from the road's left edge
		var zone := h.zone_at(float(w[0]) + h.settle() + 0.1)
		var mid := float(zone[0]) + h.ahead(float(zone[0]), float(zone[1])) * 0.5
		var lat := -(h.half_width(mid) - sw * 0.5 - 0.5)
		var xf := _road_pose(p, mid, lat + float(c[1]))
		for f in 2:
			await _pin(rig, k, xf, Vector3.ZERO)
		rig.clock = maxf(rig.clock, float(w[0]) + h.settle() + 0.1)
		k.freeze = false
		k.state = Kart.State.NORMAL
		director._immune.clear()
		_notes.clear()
		_hit_got = [k.state, 0.0]
		var t_w := rig.clock + 0.3
		h.on_event("burst", [800 + i, t_w, 1, director.slot_of(k), mid, lat])
		var end := t_w + h.tm("warn") + float(h.p["fire"]) + 0.5
		var warn_at := -1.0
		var hit_at := -1.0
		while rig.clock < end:
			k.star_time = 5.0 if c[0] == "star" else 0.0
			k.hazard_grace = 5.0 if c[0] == "grace" else (k.hazard_grace if c[0] == "hit" else 0.0)
			if c[0] == "group":
				director._immune[k] = h.group
			if c[0] == "rescued":
				k.state = Kart.State.RESPAWN
			await _pin(rig, k, xf, Vector3.ZERO)
			if warn_at < 0.0 and _notes.has([h.id, "warn"]):
				warn_at = rig.clock
			if hit_at < 0.0 and _notes.has([h.id, "hit"]):
				hit_at = rig.clock
		var what := "%d column  %-7s" % [h.id, c[0]]
		if c[2]:
			_expect(hit_at >= 0.0 and warn_at >= 0.0 and hit_at - warn_at >= h.tm("warn") * 0.95 and _hit_got[0] == Kart.State.SPIN,
				"%s %s, warned %.2f s before (want >= %.2f)" % [what, "spun" if hit_at >= 0.0 and _hit_got[0] == Kart.State.SPIN
				else ("NOT HIT" if hit_at < 0.0 else "hit, not spun"), hit_at - warn_at, h.tm("warn") * 0.95])
		else:
			_expect(hit_at < 0.0 and warn_at >= 0.0, "%s %s%s" % [what, "HIT" if hit_at >= 0.0 else "not hit",
				"" if warn_at >= 0.0 else " (it never warned: nothing tested)"])
		k.state = Kart.State.NORMAL
		k.hazard_grace = 0.0
		k.star_time = 0.0
		k.hazard_lock = 0.0
		director._immune.clear()
	# (3) forged: while it marches, and a strip off its zone's road
	var walk_t := rig.clock
	while not h.watch_window(walk_t).is_empty() or h.march_at(walk_t)[2] != CombineColumnHazard.Seg.WALK:
		walk_t += 0.5
	var w2 := h.next_watch(rig.clock + 0.5)
	var zone := h.zone_at(float(w2[0]) + h.settle() + 0.1)
	var mid := float(zone[0]) + h.ahead(float(zone[0]), float(zone[1])) * 0.5
	var lat := -(h.half_width(mid) - sw * 0.5 - 0.5)
	h.on_event("burst", [850, walk_t, 1, 0, mid, lat])
	h.on_event("burst", [851, float(w2[0]) + h.settle() + 0.5, 1, 0, fposmod(float(zone[0]) - 40.0, p.length), 0.0])
	_expect(not h._bursts.has(850) and not h._bursts.has(851), "%d column  ignores a burst forged while it marches %s, off its road %s"
		% [h.id, not h._bursts.has(850), not h._bursts.has(851)])
	# (4) a bot driving at 20 m/s down the strip's lane, there as its fire lands, is advised out of it
	var from := mid - 20.0 * (h.tm("warn") + 0.3)
	var xa := _road_pose(p, from, lat)
	for f in 2:
		await _pin(rig, k, xa, Vector3.ZERO)
	rig.clock = maxf(rig.clock, float(w2[0]) + h.settle() + 0.1)
	h.on_event("burst", [852, rig.clock + 0.3, 1, -1, mid, lat])
	await _pin(rig, k, xa, Vector3.ZERO)
	var adv := h.advice(k, from, 20.0)
	var safe: bool = adv.has("lat") and absf(float(adv["lat"]) - lat) >= sw * 0.5 + 1.0
	_expect(safe, "%d column  a bot coming at a strip is advised %s (strip %.1f +- %.1f)" % [h.id,
		"to lat %.1f" % float(adv["lat"]) if adv.has("lat") else "NOTHING", lat, sw * 0.5])
	while not h.idle():
		await _pin(rig, k, xa, Vector3.ZERO)
	# (5) none of the authority's bursts went at the karts parked above
	_expect(int(h.stats["bursts"]) == bursts0, "%d column  sent no burst for a kart standing still (%d)" % [h.id, int(h.stats["bursts"]) - bursts0])
	# (6) no soldier on a road over a whole cycle, every 0.5 s
	var geos: Array[TrackPath] = [p]
	for br in p.branches:
		geos.append(br)
	var near: Array = []   # [geo, sample] of the roads that pass within 40 m of the deck in plan
	var dk := h.deck()
	for g in geos:
		for i in g.n:
			for q in dk:
				if Vector2(g.center[i].x - q.x, g.center[i].z - q.z).length() < 40.0 + float(g.width[i]):
					near.append([g, i])
					break
	var bad := []
	var t0 := rig.clock
	for j in int(h.cycle() / 0.5) + 1:
		var ct := t0 + j * 0.5
		for n in h.soldiers():
			var q: Vector3 = h.soldier_at(n, ct)[0]
			for e in near:
				var g: TrackPath = e[0]
				var i: int = e[1]
				var d: Vector3 = q - g.center[i]
				if absf(d.dot(g.fwd[i])) > g.step * 0.5 + 0.5:
					continue
				if absf(d.dot(g.right[i])) - g.width[i] * 0.5 < 0.5 and absf(d.dot(g.up[i])) < CombineColumnHazard.HEADROOM:
					bad.append("soldier %d at %s (t %.1f)" % [n, q.snapped(Vector3.ONE * 0.1), ct])
					break
	_expect(bad.is_empty(), "%d column  no soldier on a road over a cycle (%.0f s, %d soldiers, %d road samples near the deck) %s"
		% [h.id, h.cycle(), h.soldiers(), near.size(), "" if bad.is_empty() else str(bad.slice(0, 4))])
	director._immune.clear()


## A forest level crossing ("cross"): the lamps and bell warn 2 s or more before the arms start down,
## the arms are down before the engine reaches the road and the train is on the road only while they
## are down, the road is shut 6.5 s or less per train and open 25 s or more between two trains (a pack
## held at the arms gets across before the next one); a bot that would reach the arms while they come
## down, are down or are still rising is told to stop, every one of them ("must"), and one that would
## arrive clear of that is told nothing; a kart waiting at the stop line through a whole run is never hit and sees the
## arms come down and go back up.
func _crossing_rules(rig: Rig, h: TrainHazard, k: Kart) -> void:
	var what := "%d %-11s cross " % [h.id, h.type]
	_forget_held(h)
	var g := h.gate_times()
	var down := g.x + TrainHazard.GATE_MOVE
	_expect(g.x >= 2.0, "%s lamps and bell %.1f s before the arms start down (want >= 2)" % [what, g.x])
	_expect(h.tm("warn") >= down, "%s arms down %.1f s before the engine reaches the road" % [what, h.tm("warn") - down])
	_expect(g.y - down <= 6.5, "%s road shut %.1f s per train (want <= 6.5)" % [what, g.y - down])
	var gap_min := INF
	for c in 20:
		gap_min = minf(gap_min, h._warn_at(c + 1) + g.x - (h._warn_at(c) + g.y + TrainHazard.GATE_MOVE))
	_expect(gap_min >= 25.0, "%s open %.1f s or more between two trains over 20 runs (want >= 25)" % [what, gap_min])
	# the next run that starts a few seconds from now
	var run := h.run_at(maxf(rig.clock, 1.0) + 2.0)
	var c0 := int(run[0]) + 1 if not run.is_empty() else 0
	var st := h._warn_at(c0)
	# the train's cars over the road only while the arms are down
	var on := Vector2(INF, -INF)
	var u := 0.0
	while u < g.y + 3.0:
		if _train_on_road(h, h.run_at(st + u)):
			on = Vector2(minf(on.x, u), maxf(on.y, u))
		u += 0.05
	_expect(on.x >= down and on.y <= g.y, "%s the train on the road %.2f-%.2f s into a run, the arms down %.2f-%.2f s"
		% [what, on.x, on.y, down, g.y])
	# what a bot 60 m short of the line at 20 m/s is told, for arrivals across a run
	var told_ok := true
	var at_s := fposmod(h.s - 60.0, h.path.length)
	var keep := rig.clock
	var arr := -4.0
	while arr < g.y + 6.0:
		rig.clock = st + arr - 3.0
		var a := h.advice(k, at_s, 20.0)
		if arr >= g.x and arr <= g.y + TrainHazard.GATE_MOVE + 0.2 and (a.is_empty() or not bool(a.get("must", false))):
			told_ok = false
			print("   arrival %.2f s into the run: no stop" % arr)
		if (arr < g.x - 1.6 or arr > g.y + TrainHazard.GATE_MOVE + 0.4) and not a.is_empty():
			told_ok = false
			print("   arrival %.2f s into the run: told %s" % [arr, a])
		arr += 0.25
	rig.clock = keep
	_expect(told_ok, "%s a bot arriving while the arms come down, are down or rise must stop, one arriving clear of them is told nothing" % what)
	# a kart waiting at the stop line through a whole run
	director._immune.clear()
	k.state = Kart.State.NORMAL
	k.hazard_grace = 0.0
	k.star_time = 0.0
	_notes.clear()
	rig.clock = maxf(rig.clock, st - 0.5)
	var pose := _road_pose(h.path, h.stop_s(), 0.0)
	var arm := Vector2(INF, -INF)
	while rig.clock < st + g.y + TrainHazard.GATE_MOVE + 1.0:
		await _pin(rig, k, pose, Vector3.ZERO)
		for hinge in h._gates:
			arm = Vector2(minf(arm.x, hinge.rotation.z), maxf(arm.y, hinge.rotation.z))
	var hit := _notes.has([h.id, "hit"])
	_expect(not hit and k.state == Kart.State.NORMAL and _notes.has([h.id, "warn"]) and _notes.has([h.id, "fire"]),
		"%s a kart at the stop line through a run: %s%s" % [what, "HIT" if hit else "not hit",
		"" if _notes.has([h.id, "fire"]) else " (the train never came: nothing tested)"])
	_expect(h._gates.is_empty() or (arm.x < 0.02 and arm.y > TrainHazard.GATE_UP - 0.02),
		"%s its arms came down to %.2f and went up to %.2f rad" % [what, arm.x, arm.y])
	if h._guarded():
		await _crossing_guard_rules(rig, h, k, c0)
	director._immune.clear()


## A crossing's guard: the kart just held at the stop line drives over the line, comes round and is
## 150 m short of the crossing as the next run is due: that run is called off (no warning, no train);
## it drives over the line unheld and is back as the run after is due: that one goes.
func _crossing_guard_rules(rig: Rig, h: TrainHazard, k: Kart, c0: int) -> void:
	var what := "%d %-11s guard " % [h.id, h.type]
	var held_at_line: bool = h._held_now.get(k, false)
	for at in [-10.0, 12.0, 12.0]:
		await _pin(rig, k, _road_pose(h.path, h.s + at, 0.0), Vector3.ZERO)
	var held: bool = h._held_last.get(k, false)
	var c1 := c0 + 1
	_notes.clear()
	rig.clock = maxf(rig.clock, h._start(c1) - TrainHazard.DECIDE - 0.3)
	var near := _road_pose(h.path, h.s - 150.0, 0.0)
	while rig.clock < h._warn_at(c1) + h.gate_times().y:
		await _pin(rig, k, near, Vector3.ZERO)
	var skipped: bool = h._skip.has(c1) and not _notes.has([h.id, "warn"]) and h.run_at(h._warn_at(c1) + 5.0).is_empty()
	_expect(held_at_line and held and skipped, "%s held at the arms (%s), over the line (%s), 150 m short as the next train is due: that run %s"
		% [what, held_at_line, held, "called off" if skipped else "RAN"])
	for at in [-10.0, -10.0, 12.0, 12.0]:
		await _pin(rig, k, _road_pose(h.path, h.s + at, 0.0), Vector3.ZERO)
	var c2 := c1 + 1
	_notes.clear()
	rig.clock = maxf(rig.clock, h._start(c2) - TrainHazard.DECIDE - 0.3)
	while rig.clock < h._warn_at(c2) + 0.5:
		await _pin(rig, k, near, Vector3.ZERO)
	_expect(not h._held_last.get(k, false) and not h._skip.has(c2) and _notes.has([h.id, "warn"]),
		"%s over the line unheld, back as the run after is due: that one %s" % [what, "goes" if not h._skip.has(c2) else "CALLED OFF"])
	_forget_held(h)


## A crossing's guard forgets whom it held (between probes that pin the kart at the crossing).
func _forget_held(h: TrainHazard) -> void:
	h._held_now.clear()
	h._held_last.clear()
	h._before.clear()
	h._passed.clear()


## True when a car of train h on `run` covers a point of the road across the crossing (its box as
## the hit test has it, less the kart's size).
func _train_on_road(h: TrainHazard, run: Array) -> bool:
	if run.is_empty():
		return false
	var s0 := h.path.progress(h.global_position, h.path.closest(h.global_position))
	var hw := h.half_width(s0)
	for along in [-4.0, 0.0, 4.0]:
		var lat := -hw
		while lat <= hw:
			var q := h.road_point(s0 + along, lat, 1.0)
			for j in h._cars.size():
				var x := h.car_at(j, run)
				if not x[1]:
					continue
				var d := q - (x[0] as Vector3)
				if absf(d.dot(x[2])) <= h._cars[j][0] * 0.5 and absf(d.dot(x[4]) - 2.3) <= 2.6 \
						and absf(d.dot(x[3])) <= float(h.p["half_w"]):
					return true
			lat += 1.0
	return false


## A train on a line beside or over the road ("pass") never touches a kart: a kart parked on its rails
## as the train runs over that spot, and one on the road beside it, are never hit, and the train notes
## nothing (no warning, no strike); along its whole stretch it gives no advice, never moves the
## scanner's drop point and is never "active".
func _pass_train_rules(rig: Rig, h: TrainHazard, k: Kart) -> void:
	var what := "%d %-11s pass  " % [h.id, h.type]
	for probe in [[0.3, true], [0.6, false], [0.5, true]]:
		var run := h.run_at(maxf(rig.clock, 1.0) + 2.0)
		var c := int(run[0]) + 1 if not run.is_empty() else 0
		var fwd := h._forward(c)
		var d: float = h._len * float(probe[0])
		var t_at := h._start(c) + (d if fwd else h._len - d) / float(h.p["speed"])
		var spot := h.line_point(d)
		var i := h.path.closest(spot)
		var pose := Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.6) if probe[1] \
			else _road_pose(h.path, h.path.progress(spot, i), 0.0)
		director._immune.clear()
		k.state = Kart.State.NORMAL
		k.hazard_grace = 0.0
		k.star_time = 0.0
		_notes.clear()
		rig.clock = maxf(rig.clock, t_at - 1.0)
		var met := INF
		while rig.clock < t_at + h._train_len / float(h.p["speed"]) + 1.0:
			await _pin(rig, k, pose, Vector3.ZERO)
			var now := h.run_at(rig.clock)
			for j in h._cars.size():
				var x := h.car_at(j, now) if not now.is_empty() else []
				if not x.is_empty() and x[1]:
					met = minf(met, (x[0] as Vector3).distance_to(pose.origin))
		var noted := _notes.filter(func(n: Array) -> bool: return n[0] == h.id)
		_expect(noted.is_empty() and k.state == Kart.State.NORMAL and met < 12.0 + pose.origin.distance_to(spot),
			"%s a kart %s at line m %.0f: %s, the train passed %.1f m from it" % [what, "on its rails" if probe[1]
			else "on the road beside it", d, "not hit" if noted.is_empty() else "NOTED %s" % str(noted), met])
	var quiet := true
	var at_s := h.span.x - 170.0
	while at_s <= h.span.y:
		var s_ := fposmod(at_s, h.path.length)
		if not h.advice(k, s_, 25.0).is_empty() or h.blocks_respawn(s_):
			quiet = false
		at_s += 5.0
	for tt in [h._start(0) + 1.0, h._start(1) + 5.0, h._start(2) + 9.0]:
		quiet = quiet and not h.is_active(tt)
	_expect(quiet and not h.on_map(), "%s no advice, no drop point moved, never active, not on the minimap" % what)
	director._immune.clear()


## A crane's own rules, each on a cycle of its own: (1) a kart waiting on the spot is not caught
## while the magnet comes down and warns, then is caught once it is down; (2) let go, it is carried on
## and dropped on the road ahead, near the drop spot, upright and not being rescued; (3) still in the
## crane's stretch it is not caught again by the next cycle's magnet; (4) a kart being rescued and
## (5) one standing outside the magnet's radius are not caught while it catches.
func _crane_rules(rig: Rig, h: CraneHazard, k: Kart) -> void:
	var p := h.path
	director._immune.clear()
	k._magnet = null
	# (1) warn before the catch: on the spot from before the warning until the magnet is down
	var c := await _crane_wait(rig, h, k)
	var a := h.spot(c)
	var base := h.cycle_start(c)
	var warned := -1.0
	var caught := -1.0
	while rig.clock < base + h.key(CraneHazard.CARRY) and caught < 0.0:
		await _pin(rig, k, _road_pose(p, a.x, a.y), Vector3.ZERO)
		if warned < 0.0 and _notes.has([h.id, "warn"]):
			warned = rig.clock - base
		if _notes.has([h.id, "hit"]):
			caught = rig.clock - base
	_expect(warned >= 0.0 and caught >= h.key(CraneHazard.LOW) - 0.05 and warned < caught,
		"%d crane  warns at %.2f s, catches at %.2f s into its cycle (down at %.2f s)" % [h.id, warned, caught,
		h.key(CraneHazard.LOW)])
	# (2) carried and dropped: free from here, the clock running on
	var at_s := p.progress(k.global_position, p.closest(k.global_position))
	var top := 0.0
	while rig.clock < base + h.key(CraneHazard.LET_GO) + 2.0:
		await get_tree().physics_frame
		rig.clock += get_physics_process_delta_time()
		top = maxf(top, k.global_position.y - h.road_point(a.x, a.y).y)
	var i := p.closest(k.global_position)
	var landed := p.progress(k.global_position, i)
	var ds := h.drop_spot(c)
	var drop := h.road_point(ds.x, ds.y)
	var off := Vector2(k.global_position.x - drop.x, k.global_position.z - drop.z).length()
	var on := p.on_road(k.global_position, i)
	var on_s := fposmod(landed - at_s, p.length)
	var upright := k.global_basis.y.dot(Vector3.UP)
	_expect(k.state != Kart.State.RESPAWN and k._magnet == null and on < 0.5 and on_s > 3.0 and on_s < 40.0 and off < 3.0
		and upright > 0.8 and top > 2.0,
		"%d crane  dropped on the road: %s, off the road %.2f, %.1f m on (s %.0f -> %.0f), %.1f m from the drop spot, lifted %.1f m, upright %.2f"
		% [h.id, Kart.State.keys()[k.state], on, on_s, at_s, landed, off, top, upright])
	# (3) the next cycle's magnet leaves it alone: it is still in the crane's stretch, hit on this pass
	_expect(director.immune(k, h), "%d crane  the kart it dropped is immune to its group" % h.id)
	c = await _crane_wait(rig, h, k, k.global_transform)
	await _crane_hold(rig, h, k, c, h.spot(c).y, "caught again on the same pass", false)
	# (4) a kart being rescued and (5) one outside the radius
	director._immune.clear()
	c = await _crane_wait(rig, h, k)
	await _crane_hold(rig, h, k, c, h.spot(c).y, "caught while being rescued", true)
	c = await _crane_wait(rig, h, k)
	var lat := h.spot(c).y
	var room := h.half_width(h.spot(c).x) - 1.2
	var wide := float(h.p["radius"]) + 1.6
	var out_lat := lat + wide if lat + wide <= room else lat - wide
	await _crane_hold(rig, h, k, c, out_lat, "caught %.1f m to the side (radius %.1f)" % [absf(out_lat - lat),
		float(h.p["radius"])], false)
	k.state = Kart.State.NORMAL
	k.freeze = false
	k.hazard_grace = 0.0
	director._immune.clear()


## Waits (parked at `park`, else short of the crane, still awake) until its magnet holds nobody,
## then for the next cycle, the kart upright and charged with nothing: the cycle it waited for. Parked
## short of the crane the kart's immunity from an earlier hit goes; parked at `park` (in the crane's
## stretch) it keeps it.
func _crane_wait(rig: Rig, h: CraneHazard, k: Kart, park := Transform3D()) -> int:
	var clean := park == Transform3D()
	if clean:
		park = _road_pose(h.path, h.span.x - 60.0, 0.0)
	while not h._held.is_empty() or k._magnet != null:
		await _pin(rig, k, park, Vector3.ZERO)
	var c := h.cycle_at(rig.clock) + 1
	rig.clock = maxf(rig.clock, h.cycle_start(c) + h.key(CraneHazard.ON) - 0.5)
	k.state = Kart.State.NORMAL
	k.freeze = false
	k.star_time = 0.0
	k.hazard_grace = 0.0
	if clean:
		director._immune.clear()
	# a frame for the crane to step over the clock's jump (what it noted then is not this test's)
	await _pin(rig, k, park, Vector3.ZERO)
	_notes.clear()
	return c


## Pins kart k at cycle c's spot, `lat` metres across, through the magnet's whole catching window
## (as a kart being rescued with `rescued`): it must not be caught (`what` names the failure).
func _crane_hold(rig: Rig, h: CraneHazard, k: Kart, c: int, lat: float, what: String, rescued: bool) -> void:
	var a := h.spot(c)
	var base := h.cycle_start(c)
	while rig.clock < base + h.key(CraneHazard.CARRY) + 0.2:
		if rescued:
			k.state = Kart.State.RESPAWN
			k.state_time = 0.0
		await _pin(rig, k, _road_pose(h.path, a.x, lat), Vector3.ZERO)
	var fired := _notes.has([h.id, "fire"])
	var hit := _notes.has([h.id, "hit"]) or k._magnet != null
	_expect(fired and not hit, "%d crane  %s: %s%s" % [h.id, what, "yes" if hit else "no", "" if fired else " (it never came down)"])
	k._magnet = null
	k.state = Kart.State.NORMAL
	k.state_time = 0.0


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


## A kart at lap metres at_s, `lat` metres right of the centre: on the road as _road_pose, past its
## edge on the ground under it, turned to its slope and as high as its springs hold it at rest, so its
## wheels feel what it stands on (an antlion zone wakes for a kart whose wheels are on its sand).
func _ground_pose(p: TrackPath, at_s: float, lat: float) -> Transform3D:
	var xf := p.transform_at(at_s)
	if absf(lat) <= p.width[p.index_at(at_s)] * 0.5:
		return _road_pose(p, at_s, lat)
	var q := xf.origin + xf.basis.x * lat
	var hit := get_viewport().find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		q + Vector3.UP * 6.0, q - Vector3.UP * 20.0, Game.LAYER_WORLD))
	if hit.is_empty():
		return _road_pose(p, at_s, lat)
	var n: Vector3 = hit["normal"]
	var f := (-xf.basis.z - n * (-xf.basis.z).dot(n)).normalized()
	var ride := 0.4
	var karts := get_tree().get_nodes_in_group("karts")
	var k: Kart = karts[0] if not karts.is_empty() else null
	if k and not k.wheels.is_empty():
		ride = 0.0
		for w in k.wheels:
			ride += (float(w["r"]) + Kart.TRAVEL * 0.5 - (w["pos"] as Vector3).y) / k.wheels.size()
	return Transform3D(Basis(f.cross(n).normalized(), n, -f), (hit["position"] as Vector3) + n * ride)


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
			# (the slot this peer drives, to line its hits up with the bursts aimed at it)
			print("SLOT %d" % (director.slot_of(race.player) if race.get("player") else -1))
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
		elif what == "warn" and h is AntlionGuardHazard and not (h as AntlionGuardHazard)._order.is_empty():
			var gr: Dictionary = (h as AntlionGuardHazard)._runs[(h as AntlionGuardHazard)._order[-1]]
			due = " due %.3f" % float(gr["t_meet"])
		elif what == "warn" and h is CombineColumnHazard and not (h as CombineColumnHazard)._order.is_empty():
			# a marching column's burst: when its fire lands and the strips it lands on
			var cb: Dictionary = (h as CombineColumnHazard)._bursts[(h as CombineColumnHazard)._order[-1]]
			due = " due %.3f strips %s" % [float(cb["t_f"]), ",".join((cb["strips"] as Array).map(func(st: Dictionary) -> String:
				return "%d@%.2f/%.2f" % [int(st["slot"]), float(st["s"]), float(st["lat"])]))]
		elif what == "fire" and h is TripmineHazard:
			due = " due %.3f" % (h as TripmineHazard)._rearm_at
		elif what == "fire" and h is MinefieldHazard:
			due = " due %.3f" % (h as MinefieldHazard)._mines.map(func(m: Array) -> float: return float(m[6])).max()
		elif what == "fire" and h is SeesawHazard:
			# a see-saw's tilt event as it landed: seq, clock, angle, turning speed, target
			due = " tilt %s" % ",".join((h as SeesawHazard)._seg.map(func(v) -> String: return "%.6f" % float(v)))
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


# ---------------------------------------------------------------- see-saw bridge
## A see-saw bridge (SeesawHazard): empty it rests at its rest angle; a kart on its near half tips the
## entry end down, one on its far half the exit end, and once the kart has gone it comes back to rest;
## at each of its limits and at rest a ray down onto its deck (the span and the flaps) meets a body of
## its own as high as deck_at says; a kart put back by the scanner never lands on it; with the hazards
## OFF a director still builds it, level and still and out of its list.
func _seesaw_rules(rig: Rig, h: SeesawHazard, k: Kart) -> void:
	var xs := [-15.0, 15.0]
	var want := [-1, 1]
	var away := _road_pose(h.path, fposmod(float(h.p["from"]) - 60.0, h.path.length), 0.0)
	for f in 30:
		await _pin(rig, k, away, Vector3.ZERO)
	_expect(h._side == 0 and is_equal_approx(float(h._seg[4]), h._rest()), "%d seesaw  empty: at rest (side %d, target %.2f deg)"
		% [h.id, h._side, rad_to_deg(float(h._seg[4]))])
	for c in 2:
		var at := h._pivot + h._fwd * float(xs[c]) + Vector3.UP * 0.6
		var xf := Transform3D(Basis.looking_at(h._fwd, Vector3.UP), at)
		for f in 90:
			xf.origin.y = h._pivot.y + h.deck_at(float(xs[c]), h.angle_at(rig.clock).x).x + 0.6
			await _pin(rig, k, xf, Vector3.ZERO)
		_expect(h._side == int(want[c]) and is_equal_approx(float(h._seg[4]), h.target(int(want[c]))),
			"%d seesaw  a kart %.0f m %s the pivot: side %d, target %.2f deg" % [h.id, absf(float(xs[c])),
			"before" if c == 0 else "past", h._side, rad_to_deg(float(h._seg[4]))])
	for f in 240:
		await _pin(rig, k, away, Vector3.ZERO)
	_expect(h._side == 0 and h.angle_at(rig.clock).y == 0.0 and absf(h.angle_at(rig.clock).x - h._rest()) < 1e-6,
		"%d seesaw  the kart gone: back at rest (%.3f deg)" % [h.id, rad_to_deg(h.angle_at(rig.clock).x)])
	# its deck where the karts ride it, at both limits and at rest
	var space := k.get_world_3d().direct_space_state
	var bad := []
	for th in [h._lim.x, h._rest(), h._lim.y]:
		h._next_weigh = 1e18
		h._seg = [9000, rig.clock, th, 0.0, th]
		await _pin(rig, k, away, Vector3.ZERO)
		await _pin(rig, k, away, Vector3.ZERO)
		var x0 := (h._ha - h._pivot).dot(h._fwd) + 0.5
		var x1 := (h._hb - h._pivot).dot(h._fwd) - 0.5
		for j in 41:
			var x: float = lerpf(x0, x1, j / 40.0)
			for lat in [-h._w * 0.5 + 0.4, 0.0, h._w * 0.5 - 0.4]:
				var q: Vector3 = h._pivot + h._fwd * x + h._right * lat
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 4.0, q + Vector3.DOWN * 6.0, Game.LAYER_WORLD))
				var y := h._pivot.y + h.deck_at(x, th).x
				if hit.is_empty() or (hit["collider"] as Node).get_parent() != h or absf((hit["position"] as Vector3).y - y) > 0.08:
					bad.append("%.1f deg x %.1f lat %.1f: %s" % [rad_to_deg(th), x, lat, "nothing" if hit.is_empty() else
						"%.2f m off" % ((hit["position"] as Vector3).y - y)])
	_expect(bad.is_empty(), "%d seesaw  its deck under every wheel at both limits and at rest (%d rays off%s)" % [h.id, bad.size(),
		"" if bad.is_empty() else ": " + str(bad.slice(0, 4))])
	h._next_weigh = rig.clock
	h._side = 0
	var a := float(h.p["from"])
	var b := float(h.p["to"])
	_expect(h.blocks_respawn(a) and h.blocks_respawn(b) and h.blocks_respawn((a + b) * 0.5) and not h.blocks_respawn(a - 20.0),
		"%d seesaw  no rescue drop on its stretch (s %.0f-%.0f)" % [h.id, a, b])
	# the race's hazards OFF: the span is still there, level, still and out of the list
	Game.settings["hazards"] = 0
	var off := HazardDirector.new()
	h.track.add_child(off)
	off.setup(h.track, [h.def])
	Game.settings["hazards"] = 1
	var kept := off.get_children().filter(func(n: Node) -> bool: return n is SeesawHazard)
	_expect(off.list.is_empty() and kept.size() == 1 and (kept[0] as SeesawHazard).angle_at(rig.clock).x == 0.0,
		"%d seesaw  hazards OFF: the span still built, level (%d), out of the list (%d)" % [h.id, kept.size(), off.list.size()])
	off.queue_free()
	await _pin(rig, k, away, Vector3.ZERO)
