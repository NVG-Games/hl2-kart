extends Node
## Spectators in a real race: the race scene with its own karts, items, hazards and events,
## the crowds spawned as Track.build spawns them (from a crowd JSON while the track has none
## of its own yet) and the player's kart driven by the AI. Checks that the spectators react to
## what really happens (GO, hits, explosions, headcrabs, the lead, the final lap, the finish),
## the easter eggs about the player's racer, the G-Man's rules and the audio budget; prints the
## frame times from the load to the race (spawning must not hitch) and saves stills (every --stills
## seconds, and of a group that turns to the player's racer with an easter egg once one of them who
## shows it is in view 10-30 m from the camera: once per role a lap).
## usage: godot --path . res://tests/crowd_race.tscn -- <track> <character> <laps> <out_prefix>
##   [--crowd crowd.json] [--hazards list.json] [--vehicle id] [--gman] [--items] [--crowds 0|1|2]
##   [--quality 0|1|2] [--difficulty 0|1|2] [--stills seconds] [--seconds limit] [--seed n] [--gman-at ...]
## --gman makes the G-Man egg certain to be armed (its chance is 40 %); --gman-at x,y,z,yaw,w0,w1
## stands him elsewhere with that window (a spot from tools/crowds.py gman_spot); --items hands out a
## headcrab, a hopper mine, a headcrab canister and a gravity gun when the player's kart is by
## spectators and the item can reach someone there, so those reactions get seen in every run.
## Exits 1 when a check fails; a check whose event never came near the camera is "not seen".

const CrowdShot := preload("res://tests/crowd_shot.gd")
## per player racer: [role, clips any of which shows the egg] when it passes; the line they call
## out is CrowdRules.pass_line's for that role, racer and world (when the content has it)
const EGGS := {
	"gordon": [["metrocop", ["condemn", "point"]], ["citizen", ["wave", "cheer", "jump"]],
		["scientist", ["wave", "cheer", "jump"]], ["vort", ["bow"]], ["islave", ["bow"]], ["hecu", ["point"]]],
	"breen": [["metrocop", ["salute"]], ["citizen", ["boo", "point", "crossed"]],
		["refugee", ["boo", "point", "crossed"]], ["rebel", ["boo", "point", "crossed"]]],
	"vortigaunt": [["vort", ["bow"]], ["islave", ["bow"]]],
	"shephard": [["hecu", ["salute"]]],
	"barney": [["guard", ["wave", "cheer", "jump"]]],
}

var tid := ""
var who := ""
var laps := 2
var out := ""
var src := ""
var hz_src := ""
var vehicle := "buggy"
var force_gman := false
var gman_at := PackedFloat64Array()
var force_items := false
var crowds := 2
var quality := 2
var difficulty := 1
var still_every := 15.0
var limit := 420.0
var race: Node
var trk: Track
var crowd: CrowdDirector
var failures := 0
var _t := 0.0
var _last_us := 0
var _frames := {}  # phase -> frame times (ms)
var _long: Array[String] = []  # frames over 33 ms: how long, when
var _skip := 0  # frames left out of the times (a still being saved)
var _go_t := -1.0
var _go_shot := false
var _shots := 0
var _next_still := 5.0
var _done_t := -1.0
var _load := {}
# audio
var _was := [false, false, false]
var _pos := [0.0, 0.0, 0.0]
var _starts: Array[float] = []
var _over_racer := 0
var _under_speech := 0  # easter eggs about the player started under a long line of the racer's
var _unducked := 0  # frames a spectator voice was not ducked under the racer's
var _max_voices := 0
var _max_beds := 0
var _max_crowd_sounds := 0
var _overlap := 0.0
# the G-Man
var _gman_on := -1.0
var _gman_shows: Array = []  # [shown at, lap, in window, distance, shown for, nearest while shown, player not driving]
var _gman_near := INF
var _gman_window_passes := 0
var _was_in_window := false
# forced items
var _force: Array[String] = ["headcrab", "gravgun", "hopper", "canister"]
var _forced := {}  # item -> [race time, group id]
var _next_force := 12.0
# easter egg stills
var _seen := 0  # decisions already looked at
var _egg_shots := {}  # "role lap" -> true
var _egg_wait: Array = []  # [group, role, give up at]: easter egg reactions to catch on a still


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var pos: Array = []
	var i := 0
	while i < a.size():
		var opt: String = a[i]
		var val: String = a[i + 1] if i + 1 < a.size() else ""
		match opt:
			"--crowd":
				src = val
			"--hazards":
				hz_src = val
			"--vehicle":
				vehicle = val
			"--crowds":
				crowds = int(val)
			"--quality":
				quality = int(val)
			"--difficulty":
				difficulty = int(val)
			"--gman-at":
				gman_at = val.split_floats(",")
			"--stills":
				still_every = float(val)
			"--seconds":
				limit = float(val)
			"--seed":
				seed(int(val))
			"--gman":
				force_gman = true
				i += 1
				continue
			"--items":
				force_items = true
				i += 1
				continue
			_:
				pos.append(opt)
				i += 1
				continue
		i += 2
	tid = pos[0]
	who = pos[1]
	laps = int(pos[2])
	out = pos[3]
	Game.settings["character"] = who
	Game.settings["vehicle"] = vehicle
	Game.settings["track"] = tid
	Game.settings["laps"] = laps
	Game.settings["difficulty"] = difficulty
	Game.settings["demo"] = false
	Game.settings["hazards"] = 1
	Game.settings["crowds"] = crowds
	Game.settings["quality"] = quality
	Game.settings["vsync"] = false
	Game.apply_settings()
	_start.call_deferred()


## Load the race as the menu does, then (while the track has no spectators of its own) spawn
## the test data's at once, as Track.build would, before the first frame is drawn.
func _start() -> void:
	var t0 := Time.get_ticks_usec()
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child(race)
	get_tree().current_scene = race
	trk = race.track
	_load["race"] = (Time.get_ticks_usec() - t0) / 1000.0
	if hz_src != "":
		var l = Game.load_json(hz_src)
		trk.hazards.queue_free()
		trk.hazards = HazardDirector.new()
		trk.add_child(trk.hazards)
		trk.hazards.setup(trk, l if l is Array else [])
	if trk.crowd == null and src != "":
		var d: Dictionary = Game.load_json(src)
		if force_gman:
			for e in d.get("crowd_eggs", []):
				if e["kind"] == "gman":
					e["chance"] = 1.0
		_skips(d)
		if crowds > 0:
			CrowdShot.stands(trk, d.get("crowd_geom", []), d.get("crowd_clear", []))
		var t1 := Time.get_ticks_usec()
		trk.crowd = CrowdDirector.spawn_for(trk, d)
		_load["crowds"] = (Time.get_ticks_usec() - t1) / 1000.0
	crowd = trk.crowd
	if DisplayServer.get_name() == "headless" or crowds <= 0:
		_check("no spectators headless or with crowds OFF", crowd == null)
	if crowd:
		crowd.trace = true
		# a track's own crowd data spawned with the track: --gman arms its egg here
		var gm: Dictionary = crowd.eggs._gman
		if force_gman and not gm.is_empty():
			gm["armed"] = true
		if gman_at.size() >= 6 and not gm.is_empty():
			var a: CrowdActor = gm["actor"]
			a.global_position = Vector3(gman_at[0], gman_at[1], gman_at[2])
			a.base_yaw = gman_at[3]
			a.rotation.y = gman_at[3]
			gm["window"] = Vector2(gman_at[4], gman_at[5])
			gm["route"] = -1
		_load["spectators"] = crowd.actors.size()
		_load["pending"] = crowd._pending.size()
	race.player.controller = AIController.new(0.95, 7)
	print("track %s, player %s on %s, %d laps, crowds %d, quality %d, difficulty %d: load %s" % [tid, who, vehicle,
		laps, crowds, quality, difficulty, _load])
	_last_us = Time.get_ticks_usec()


## Where there must never be anyone: the dedicated server, crowds OFF (the data is not spawned).
func _skips(d: Dictionary) -> void:
	var was: bool = Net.dedicated
	Net.dedicated = true
	_check("nothing spawned on a dedicated server", _gone(CrowdDirector.spawn_for(trk, d)))
	Net.dedicated = was
	var keep: int = Game.settings["crowds"]
	Game.settings["crowds"] = 0
	_check("nothing spawned with crowds OFF", _gone(CrowdDirector.spawn_for(trk, d)))
	Game.settings["crowds"] = keep


## True for no director; one that should not be there is freed again.
static func _gone(c: CrowdDirector) -> bool:
	if c == null:
		return true
	c.free()
	return false


func _process(delta: float) -> void:
	if race == null:
		return
	var now_us := Time.get_ticks_usec()
	var ft := (now_us - _last_us) / 1000.0
	_last_us = now_us
	_t += delta
	var phase: String = race._phase
	if phase == "race" and _go_t < 0.0:
		_go_t = _t
	if phase == "race" and _t - _go_t < 10.0:
		phase = "go"
	if _skip > 0:
		_skip -= 1
	else:
		(_frames.get_or_add(phase, []) as Array).append(ft)
		if ft > 33.0:
			_long.append("%.0f ms at %.2f s (%s)" % [ft, _t, phase])
	if crowd == null:
		_end_check()
		return
	_watch_audio(delta)
	_watch_gman(delta)
	_egg_stills()
	if force_items and race.racing:
		_force_items()
	if _t > _next_still:
		_next_still = _t + still_every
		_still("t%03d" % int(_t))
	if _go_t > 0.0 and not _go_shot and _t - _go_t > 0.6:
		_go_shot = true
		_still("go")
	_end_check()


func _end_check() -> void:
	var me: Kart = race.player
	if _done_t < 0.0 and (me.finished or race.karts.all(func(k: Kart) -> bool: return k.finished)):
		_done_t = _t
	if (_done_t > 0.0 and _t - _done_t > 4.0) or _t > limit:
		_report()
		get_tree().quit(1 if failures > 0 else 0)


func _still(what: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s_%02d_%s.png" % [out, _shots, what])
	_shots += 1
	_skip = 2


# ---------------------------------------------------------------- audio
## The crowd's one-shot voices: never more than three, a line never starts over the player's
## racer talking (an easter egg about the player may, under a line with more than
## CrowdAudio.RACER_WAIT s to run), and 0.9 s between two lines (an easter egg about the player may cut in).
func _watch_audio(delta: float) -> void:
	var me: Kart = race.player
	var racer: AudioStreamPlayer3D = me.audio.voice
	var on := 0
	for i in crowd.audio.voices.size():
		var p := crowd.audio.voices[i]
		var at := p.get_playback_position() if p.playing else 0.0
		if p.playing and (not _was[i] or at + 0.05 < _pos[i]):
			_starts.append(_t)
			# only an easter egg about the player may start under the racer's line, and only a long one
			# (this frame may see the start a frame late: 0.1 s of slack)
			if racer.playing and racer.get_playback_position() > 0.15:
				if crowd.audio._rank[i] == CrowdAudio.Prio.EGG * 2 + 1 \
						and CrowdAudio.left(racer) > CrowdAudio.RACER_WAIT - 0.1:
					_under_speech += 1
				else:
					_over_racer += 1
		_was[i] = p.playing
		_pos[i] = at
		on += 1 if p.playing else 0
	_max_voices = maxi(_max_voices, on)
	if on > 0 and racer.playing:
		_overlap += delta
		# a quarter second into the racer's line every spectator voice is down under it
		if racer.get_playback_position() > 0.25 and crowd.audio.voices.any(func(p: AudioStreamPlayer3D) -> bool:
				return p.playing and p.volume_db > CrowdAudio.VOICE_DB + CrowdAudio.DUCK + 0.5):
			_unducked += 1
	_max_beds = maxi(_max_beds, crowd.audio.beds.filter(func(b: AudioStreamPlayer3D) -> bool: return b.playing).size())
	if Engine.get_process_frames() % 15 == 0:
		var n := 0
		for p in crowd.find_children("*", "AudioStreamPlayer3D", true, false):
			n += 1 if (p as AudioStreamPlayer3D).playing else 0
		_max_crowd_sounds = maxi(_max_crowd_sounds, n)


# ---------------------------------------------------------------- the G-Man
## Shown once at most, from the second lap, while the player's kart is in his window and the
## camera 25-70 m off; seen (40 px of 900 tall on screen); there at least 3 s unless the camera
## comes within 15 m, which it must not do before he is gone; gone within 8 s. Also how long the
## player's kart was spun, tumbled or rescued while he was there (its camera may have looked away).
func _watch_gman(delta: float) -> void:
	var gm: Dictionary = crowd.eggs._gman
	if gm.is_empty():
		return
	var me: Kart = race.player
	var a: CrowdActor = gm["actor"]
	var cam := get_viewport().get_camera_3d()
	var d := a.global_position.distance_to(cam.global_position)
	var inside: bool = crowd.in_stretch(me, gm["route"], gm["window"])
	if inside and not _was_in_window and me.lap >= 1:
		_gman_window_passes += 1
	_was_in_window = inside
	if a.visible and _gman_on < 0.0:
		_gman_on = _t
		_gman_near = d
		_gman_shows.append([_t, me.lap, inside, d, 0.0, d, 0.0])
		_still("gman")
	elif a.visible:
		_gman_near = minf(_gman_near, d)
		if me.state != Kart.State.NORMAL:
			_gman_shows[-1][6] += delta
	elif _gman_on >= 0.0:
		var s: Array = _gman_shows[-1]
		s[4] = _t - _gman_on
		s[5] = _gman_near
		_gman_on = -1.0


# ---------------------------------------------------------------- easter egg stills
## A group turns to the player's racer with one of its easter egg clips (the decision "clip <group>
## peak <racer> <role> <clip>", once per role and lap): a still once one of that role is in view
## 10-30 m from the camera (or none after 4 s).
func _egg_stills() -> void:
	var n := crowd.decisions.size()
	for i in range(_seen, n):
		var w := crowd.decisions[i].split(" ")
		if w.size() != 6 or w[0] != "clip" or w[2] != "peak" or w[3] != who:
			continue
		if not EGGS.get(who, []).any(func(e: Array) -> bool: return e[0] == w[4] and w[5] in e[1]):
			continue
		var key := "%s %d" % [w[4], race.player.lap]
		var gs := crowd.groups.filter(func(g: CrowdDirector.Group) -> bool: return str(g.id) == w[1])
		if not _egg_shots.has(key) and not gs.is_empty():
			_egg_shots[key] = true
			_egg_wait.append([gs[0], w[4], _t + 4.0])
	_seen = n
	var cam := get_viewport().get_camera_3d()
	for e: Array in _egg_wait.duplicate():
		var g: CrowdDirector.Group = e[0]
		var ahead := g.members.any(func(a: CrowdActor) -> bool:
			var d := a.global_position.distance_to(cam.global_position)
			return String(a.role) == e[1] and d > 10.0 and d < 30.0 \
				and cam.is_position_in_frustum(a.global_position + Vector3.UP * 1.2))
		if ahead or _t > float(e[2]):
			_egg_wait.erase(e)
			if ahead:
				_still("egg_g%d_%s" % [g.id, e[1]])


# ---------------------------------------------------------------- forced items
## Hand one of the forced items out when the player's kart is beside a group of spectators
## and the item can reach someone there; one at a time, 8 s apart.
func _force_items() -> void:
	if _force.is_empty() or _t < _next_force or race.race_time < 8.0:
		return
	var me: Kart = race.player
	if me.state != Kart.State.NORMAL or me.finished:
		return
	var g := _group_by(me.global_position)
	if g == null:
		return
	var behind: Kart = null
	var ahead: Kart = null
	for k: Kart in race.karts:
		if k == me or k.finished or k.state != Kart.State.NORMAL:
			continue
		var d := me.total_progress - k.total_progress
		if d > 4.0 and d < 60.0 and (behind == null or d < me.total_progress - behind.total_progress):
			behind = k
		var to := k.global_position - me.global_position
		if to.length() < 18.0 and to.normalized().dot(-me.global_basis.z) > 0.7:
			ahead = k
	for id in _force:
		var user: Kart = null
		match id:
			"headcrab":
				# from a rival just behind: it jumps on the player
				user = behind if me.can_take_crab() else null
			"gravgun":
				user = me if ahead else null
			"hopper":
				# dropped in front of the rival just behind
				user = me if behind and me.total_progress - behind.total_progress < 25.0 else null
			"canister":
				# fired by anyone at the leader: the player, leading
				user = behind if me.place == 1 else null
		if user == null:
			continue
		user.item = id
		user.item_count = 1
		user.roulette = 0.0
		Items.use(user)
		_forced[id] = [race.race_time, g.id]
		_force.erase(id)
		_next_force = _t + 8.0
		print("forced %s by %s at s=%.0f by group %d (%s)" % [id, user.character_id, me.lap_progress, g.id, g.role])
		get_tree().create_timer(0.6 if id != "canister" else 3.4).timeout.connect(_still.bind(id))
		return


## The nearest group of a few spectators within 30 m of `p`, hot (animated) now.
func _group_by(p: Vector3) -> CrowdDirector.Group:
	var best: CrowdDirector.Group = null
	for g in crowd.groups:
		if g.tier == 0 and g.members.size() >= 5 and g.center.distance_to(p) < g.radius + 30.0:
			if best == null or g.center.distance_to(p) < best.center.distance_to(p):
				best = g
	return best


# ---------------------------------------------------------------- report
func _report() -> void:
	print("frame times (ms): ", _times())
	print("frames over 33 ms: ", ", ".join(_long))
	if crowd == null:
		print("checks failed: %d" % failures)
		return
	var kinds := {}
	for l in crowd.decisions:
		var key := _key(l)
		kinds[key] = int(kinds.get(key, 0)) + 1
	var keys := kinds.keys()
	keys.sort()
	print("decisions: ", ", ".join(keys.map(func(k: String) -> String: return "%s x%d" % [k, kinds[k]])))
	if _done_t < 0.0:
		print("stopped at %.0f s before the finish: the race's checks are left out" % _t)
		_audio_checks()
		print("checks failed: %d" % failures)
		return
	var me: Kart = race.player
	var start_ids := crowd.groups.filter(func(g: CrowdDirector.Group) -> bool: return g.tags.has("start")) \
		.map(func(g: CrowdDirector.Group) -> int: return g.id)
	# the race's events, and the reactions of the groups they came near
	_check("GO: the start event", _has("event start"))
	_check("GO: the start crowds celebrate", start_ids.any(func(id: int) -> bool: return _has("clip %d start " % id)))
	_seen_check("a hit", "event hit", "clip %d hit")
	_seen_check("an explosion", "event explosion", "clip %d explosion")
	_seen_check("a headcrab", "event headcrab", "clip %d headcrab")
	_seen_check("a fall or rescue", "event fall", "clip %d fall")
	_check("the lead changes", _has("event lead"))
	# on the director's own clock: this test's frame stamps lag a frame behind, which under load is over 50 ms
	var lead_gap := INF
	for i in range(1, crowd.lead_times.size()):
		lead_gap = minf(lead_gap, crowd.lead_times[i] - crowd.lead_times[i - 1])
	_check("lead reactions at most one per 3 s", lead_gap >= 2.999)
	if laps >= 2:
		_check("someone starts the final lap", _has("event final_lap"))
	_check("the finish", _has("event finish"))
	_check("the start crowds celebrate a finish", start_ids.any(func(id: int) -> bool: return _has("clip %d finish " % id)))
	for id in _forced:
		var at: Array = _forced[id]
		var kind := "hit" if id == "gravgun" else ("explosion" if id == "hopper" else "headcrab")
		print("  forced %s at %.1f s by group %d: %s" % [id, at[0], at[1], "reacted" if _has("clip %d %s " % [at[1], kind])
			else "no reaction there"])
	# the player's racer going by the spectators who know them
	for e in EGGS.get(who, []):
		var role: String = e[0]
		var gs := crowd.groups.filter(func(g: CrowdDirector.Group) -> bool:
			return g.members.any(func(a: CrowdActor) -> bool: return String(a.role) == role))
		if gs.is_empty():
			continue
		var cat := CrowdRules.pass_line(StringName(role), CrowdRules.attitude(StringName(role), who, vehicle), crowd.world())
		if not CrowdAudio.can_say(StringName(role), cat):
			cat = ""
		var clip_ok := false
		var line_ok := cat == ""
		for g: CrowdDirector.Group in gs:
			for c in e[1]:
				clip_ok = clip_ok or _has("clip %d peak %s %s %s" % [g.id, who, role, c])
			line_ok = line_ok or _has("line %d %s %s played" % [g.id, role, cat])
		_check("%s passing: %s %s" % [who, role, "/".join(e[1])], clip_ok)
		if cat != "":
			_check("%s passing: a %s says %s" % [who, role, cat], line_ok)
	if who == "breen" and crowd.groups.any(func(g: CrowdDirector.Group) -> bool: return g.bed != ""):
		print("  riot bed after Breen: %s" % ("yes" if crowd.groups.any(func(g: CrowdDirector.Group) -> bool:
			return g.bed_until > 0.0) else "no"))
	# the G-Man
	var gm: Dictionary = crowd.eggs._gman
	if not gm.is_empty():
		print("  G-Man armed %s, window %s (route %d), passes on lap 2+: %d, shown: %s, tallest on screen %.0f px of 900" % [
			gm["armed"], gm["window"], gm["route"], _gman_window_passes, _gman_shows, float(gm["seen_px"]) * 900.0])
		_check("G-Man shown at most once", _gman_shows.size() <= 1)
		for s: Array in _gman_shows:
			_check("G-Man only from the second lap", int(s[1]) >= 1)
			_check("G-Man only with the player in his window", bool(s[2]))
			_check("G-Man shown 25-70 m off", float(s[3]) >= CrowdEggs.GMAN_SHOW.x - 1.0
				and float(s[3]) <= CrowdEggs.GMAN_SHOW.y + 3.0)
			_check("G-Man there 3 s unless the camera came within 15 m", float(s[4]) >= CrowdEggs.GMAN_STAY - 0.1
				or float(s[5]) < CrowdEggs.GMAN_NEAR + 1.0)
			_check("G-Man gone within 8 s", float(s[4]) <= CrowdEggs.GMAN_MAX + 0.2)
			_check("G-Man gone before the camera comes within 15 m", float(s[5]) >= 11.0)
		if gm["armed"] and _gman_window_passes > 0:
			_check("G-Man armed and the player through his window: shown", _gman_shows.size() == 1)
			_check("G-Man big enough to be seen (40 px of 900)", float(gm["seen_px"]) >= CrowdEggs.GMAN_SEEN)
	_audio_checks()
	print("  player %s: place %d, laps %d, finished %s, respawns %d" % [who, me.place, me.lap, me.finished, me.respawns])
	print("checks failed: %d" % failures)


## Lines heard, how close together they started (only an easter egg about the player may cut
## into the 0.9 s gap, and then the line before it stops), voices and beds at once.
func _audio_checks() -> void:
	var gaps := []
	for i in range(1, _starts.size()):
		gaps.append(_starts[i] - _starts[i - 1])
	var lines := crowd.decisions.filter(func(l: String) -> bool: return l.begins_with("line") and l.ends_with("played"))
	print("  audio: %d lines played (%.1f a minute), %d starts heard, closest two %.2f s apart (%d under 0.85 s), most voices at once %d, beds %d, crowd sounds %d; crowd voice under the racer's %.1f s, easter eggs started under a long racer line %d" % [
		lines.size(), lines.size() / maxf(_t / 60.0, 0.01), _starts.size(), gaps.min() if not gaps.is_empty() else 0.0,
		gaps.filter(func(x: float) -> bool: return x < 0.85).size(), _max_voices, _max_beds, _max_crowd_sounds, _overlap,
		_under_speech])
	_check("at most 3 spectator voices at once", _max_voices <= 3)
	_check("at most 2 murmur beds", _max_beds <= 2)
	_check("no spectator line starts while the player's racer speaks (an easter egg about it may, under a long line)",
		_over_racer == 0)
	_check("spectator voices duck under the player's racer", _unducked == 0)
	_check("no two spectator lines start together", gaps.all(func(x: float) -> bool: return x > 0.05))


## Per phase: frames, mean, 99th percentile, the longest, and frames over 33 ms and 50 ms.
func _times() -> String:
	var parts := []
	for ph in ["intro", "count", "go", "race", "done"]:
		var l: Array = _frames.get(ph, []).duplicate()
		if l.is_empty():
			continue
		var first: float = l[0]
		l.sort()
		var sum := 0.0
		for x in l:
			sum += x
		parts.append("%s n=%d first %.1f mean %.1f p99 %.1f max %.1f >33ms %d >50ms %d" % [ph, l.size(), first,
			sum / l.size(), l[int(l.size() * 0.99)], l[-1], l.filter(func(x: float) -> bool: return x > 33.0).size(),
			l.filter(func(x: float) -> bool: return x > 50.0).size()])
	return " | ".join(parts)


## A decision without its group id: "clip <state or event> <role> <clip>", "line <role>
## <category> played|skipped", "event <kind>", "remark <file> ...", "egg ...".
static func _key(l: String) -> String:
	var w := l.split(" ")
	match w[0]:
		"clip":
			return " ".join(["clip", w[2], w[w.size() - 2], w[w.size() - 1]])
		"line":
			return " ".join(w.slice(0, 1) + w.slice(2))
	return l


func _has(prefix: String) -> bool:
	return crowd.decisions.any(func(l: String) -> bool: return l.begins_with(prefix))


## An event that happened (or not) and whether a group by the camera reacted to it.
func _seen_check(what: String, event: String, clip: String) -> void:
	if not _has(event):
		print("  not seen: %s" % what)
		return
	var near := crowd.groups.any(func(g: CrowdDirector.Group) -> bool: return _has(clip % g.id + " "))
	print("  %s: %d, spectators reacted: %s" % [what, crowd.decisions.filter(func(l: String) -> bool:
		return l == event).size(), "yes" if near else "none near the camera"])


func _check(what: String, ok: bool) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1
