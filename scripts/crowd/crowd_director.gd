class_name CrowdDirector
extends Node3D
## The spectators of a circuit (track data "crowd_groups", "crowds", "crowd_eggs"):
## spawns them, keeps only the few near the camera animated and looking at the karts,
## runs every group's reactions (the wave as karts pass, explosions, falls, the finish
## and the easter eggs) and hands their lines to CrowdAudio. Cosmetic only: no physics,
## nothing over the network. Gameplay code reports what happens through notify().

const TICK := 0.033  # a third of the groups per tick: each group at 10 Hz
const HOT := 30.0
const WARM := 90.0
const COLD := 160.0
const SYNC_SPAWN := 160  # spectators placed at once (nearest the start); the rest a few a frame,
const SPAWN_US := 3000  # ... for at most this long (microseconds): the intro fly-by must not stutter
## clip updates a second of each animated spectator near the camera (and of its head's
## look-at), and of those further off: the same at any frame rate, a few each frame in turn
const HOT_HZ := 20.0
const WARM_HZ := 10.0
## per preset (FEW or LOW graphics, FULL, FULL + HIGH graphics): animated actors,
## look-at actors, fade distance, fade distance of the one-material background model
const PRESETS := [[20, 0, 110.0, 160.0], [45, 10, 150.0, 200.0], [70, 16, 150.0, 220.0]]
const FAR_MODELS := ["humans/group01/male_cheaple"]
const TRASH := ["trashcan", "trashbin", "garbage"]
const HUMANS := [&"citizen", &"refugee", &"rebel"]
## voices.json "_crowd" roles of the eggs and of the start arch's remarks per world
const EGG_ROLES := {"gman": "gman", "holo": "holo", "lamarr": "lamarr", "zombies": "zombie", "nihilanth": "nihilanth"}
const REMARK_ROLES := {"combine": "breen", "military": "hecu"}
## a group with an easter egg for the local player's racer turns to it from anyone else passing
## (metres of score: more than any other racer in the stretch can have)
const ME_BONUS := 30.0
## a stretch watched this much longer than the group itself (a gallery over a whole loop) peaks
## for the racer nearest its members, within WIDE_REACH metres more than the road comes to them
const WIDE_SLACK := 80.0
const WIDE_REACH := 20.0
## an easter-egg line about the player's racer refused for one of these waits up to HOLD seconds
const HOLD := 4.0
const HOLD_FOR := ["racer", "gap", "busy", "far"]
## ... unless the camera, out of range, is this many metres further from them than it has been: it has gone by
const LEAVING := 3.0

var track: Track
var data := {}
var groups: Array[Group] = []
var actors: Array[CrowdActor] = []
var audio: CrowdAudio
var eggs: CrowdEggs
var birds: CrowdBirds
var gantry: StartGantry
var preset := 2
var max_animated := 70
var max_lookers := 16
## tests: every decision (clips by role, voice categories) is written to `decisions`
var trace := false
var decisions: Array[String] = []
var lead_times: Array[float] = []  # with trace: when each lead reaction passed the 3 s throttle (CrowdActor.now())
var karts: Array[Kart] = []
var _race: Node
var _phase := 0
var _acc := 0.0
var _pending: Array = []  # [member dict, Group] still to place
var _missing := {}
var _kart_t := 0.0
var _prev := {}  # kart -> [position, time]
var _vel := {}  # kart -> measured velocity (proxies have none of their own)
var _air := {}  # kart -> true while airborne over a jump gap
var _animated := {}  # actor -> true
var _moving: Array[CrowdActor] = []  # the same near the camera (hot) and every looker, to advance in turn
var _moving_far: Array[CrowdActor] = []  # ... and further off (warm)
var _rounds := [[0.0, 0], [0.0, 0]]  # per list: updates owed (carried over), where its round is
var _lookers := {}
var _me: Kart
var _cans := 0
var _glows: Array[OmniLight3D] = []
var _glow_groups: Array = []
var _was_racing := false
var _lead_until := 0.0  # neck and neck the lead flips back and forth: one reaction per 3 s
## lines waiting to be said: [group, role, category, priority, kart, until, why refused last, the camera
## has been in range of the speakers, the nearest it has been to them]
var _held: Array = []


## One group of spectators and what it is doing.
class Group:
	extends RefCounted
	var index := 0
	var id := 0
	var route := -1  # the road it stands by: -1 the main loop, else a branch index
	var s := 0.0  # metres along that road (lap metres on the main loop)
	var side := 0
	var kind := ""
	var role := &"citizen"
	var center := Vector3.ZERO
	var radius := 10.0
	var watch := Vector2.ZERO
	var wide := false  # watches far more road than it covers: the racer nearest its members decides
	var peak_d := 0.0  # wide: metres from a member within which a racer is passing them
	var roles := {}  # the members' roles (StringName -> true)
	var bed := ""
	var bed_until := 0.0  # Breen went by: the riot bed until then
	var tags := PackedStringArray()
	var members: Array[CrowdActor] = []
	var dodgers: Array[CrowdActor] = []
	var state: int = CrowdRules.State.IDLE
	var kart: Kart  # the racer the state is about
	var until := 0.0  # timed states (AFTER, SHOCK, CELEBRATE) end then
	var tier := 3  # 0 hot, 1 warm, 2 cold, 3 out of range
	var dist := INF
	var focus := Vector3.ZERO
	var next_line := 0.0
	var next_egg := 0.0
	var next_chat := 0.0
	var next_shock := 0.0  # a barrage (mortars, the reactor's arcs): one blast in 6 s startles them
	var excite := 0.0
	var serial := 0
	var pending := false
	var said_start := false


## The track's spectators, or null where there are none: crowds OFF, BSP maps, the
## dedicated server, headless runs, track data without "crowds". `src` stands in for the
## track's own crowd data (tests).
static func spawn_for(trk: Track, src: Dictionary = {}) -> CrowdDirector:
	var d: Dictionary = src if not src.is_empty() else trk.data
	if trk.is_bsp or Net.dedicated or DisplayServer.get_name() == "headless":
		return null
	if int(Game.settings.get("crowds", 2)) <= 0 or d.get("crowds", []).is_empty():
		return null
	var c := CrowdDirector.new()
	trk.add_child(c)
	c.setup(trk, d)
	return c


## Something happened that spectators may react to (explosion, hit, fall, knock,
## headcrab, start, lead, final_lap, finish): `a` the kart it is about, `b` the other one,
## `info` extra (the prop knocked over, the finishing place).
static func notify(tree: SceneTree, kind: StringName, pos: Vector3, a: Kart = null, b: Kart = null,
		info: Variant = null) -> void:
	if tree:
		tree.call_group("crowd_director", "on_event", kind, pos, a, b, info)


func setup(trk: Track, d: Dictionary) -> void:
	track = trk
	data = d
	name = "Crowds"
	add_to_group("crowd_director")
	_race = trk.get_parent()
	gantry = trk.gantry
	_apply_preset()
	Game.settings_changed.connect(_apply_preset)
	var by_id := {}
	for e in d.get("crowd_groups", []):
		var g := Group.new()
		g.index = groups.size()
		g.id = int(e.get("id", g.index))
		g.route = route_of(e)
		g.s = float(e.get("s", 0.0))
		g.side = int(e.get("side", 0))
		g.kind = str(e.get("kind", "line"))
		g.role = StringName(str(e.get("role", "citizen")))
		var c: Array = e.get("center", [0, 0, 0])
		g.center = Vector3(c[0], c[1], c[2])
		g.radius = float(e.get("radius", 10.0))
		var w: Array = e.get("watch", [g.s - 20.0, g.s + 20.0])
		g.watch = Vector2(w[0], w[1])
		g.bed = str(e.get("bed", ""))
		g.tags = PackedStringArray(e.get("tags", []))
		g.next_chat = CrowdActor.now() + randf_range(8.0, 30.0)
		groups.append(g)
		by_id[g.id] = g
	_wide_groups(d.get("crowds", []))
	var start := track.path.center[0]
	# the voices to load ahead: the spectators', the eggs' and the start arch's remarks
	var roles := {}
	if REMARK_ROLES.has(world()):
		roles[REMARK_ROLES[world()]] = true
	for e in d.get("crowd_eggs", []):
		if EGG_ROLES.has(str(e.get("kind", ""))):
			roles[EGG_ROLES[str(e["kind"])]] = true
	for m in d.get("crowds", []):
		if int(m.get("lod", 0)) > preset or not by_id.has(int(m.get("group", -1))):
			continue
		_pending.append([m, by_id[int(m["group"])]])
		roles[str(m.get("role", "citizen"))] = true
	# nearest the start first: pop_back takes them in that order
	_pending.sort_custom(func(a: Array, b: Array) -> bool: return _dist_to(a[0], start) > _dist_to(b[0], start))
	audio = CrowdAudio.new()
	add_child(audio)
	audio.setup(self, roles.keys())
	_spawn_batch(SYNC_SPAWN)
	eggs = CrowdEggs.new()
	add_child(eggs)
	eggs.setup(self, d.get("crowd_eggs", []))
	birds = CrowdBirds.new()
	add_child(birds)
	birds.setup(self, d.get("crowd_eggs", []))
	if str(track.data.get("gantry", "")) == "xen":
		_xen_glows()


static func _dist_to(m: Dictionary, p: Vector3) -> float:
	var q: Array = m["pos"]
	return Vector3(q[0], q[1], q[2]).distance_squared_to(p)


## Groups that watch far more road than they cover (a gallery round a whole loop) are `wide`:
## their peak is a racer passing within WIDE_REACH metres more than their road comes to them
## (`people`: the "crowds" entries), not the one nearest the middle of the stretch.
func _wide_groups(people: Array) -> void:
	var at := {}
	for m in people:
		(at.get_or_add(int(m.get("group", -1)), []) as Array).append(Vector3(m["pos"][0], m["pos"][1], m["pos"][2]))
	for g in groups:
		var span := fposmod(g.watch.y - g.watch.x, track.path.length) if g.route < 0 else g.watch.y - g.watch.x
		var pts: Array = at.get(g.id, [])
		g.wide = span > 2.0 * g.radius + WIDE_SLACK and not pts.is_empty()
		if not g.wide:
			continue
		var road := track.path.geo(g.route)
		var near := INF
		for k in int(span / 4.0) + 1:
			var c := road.center_at(g.watch.x + k * 4.0)
			for q: Vector3 in pts:
				near = minf(near, c.distance_squared_to(q))
		g.peak_d = sqrt(near) + WIDE_REACH


## Everyone is placed (after the first ones the rest come a few a frame).
func ready_all() -> bool:
	return _pending.is_empty()


func _apply_preset() -> void:
	var q := int(Game.settings.get("quality", 2))
	preset = 0 if int(Game.settings.get("crowds", 2)) <= 1 or q <= 0 else q
	max_animated = PRESETS[preset][0]
	max_lookers = PRESETS[preset][1]
	for a in actors:
		a.set_range(_vis(a.key))


func _vis(key: String) -> float:
	return PRESETS[preset][3] if key in FAR_MODELS else PRESETS[preset][2]


## Place up to `n` of the spectators still to come, stopping after `budget_us` microseconds
## (-1: no limit).
func _spawn_batch(n: int, budget_us := -1) -> void:
	var t0 := Time.get_ticks_usec()
	for k in mini(n, _pending.size()):
		var e: Array = _pending.pop_back()
		_spawn(e[0], e[1])
		if budget_us >= 0 and Time.get_ticks_usec() - t0 >= budget_us:
			break
	if _pending.is_empty() and not _missing.is_empty():
		push_warning("crowds: %d models missing, stand-ins used: %s" % [_missing.size(), _missing])
		_missing.clear()


func _spawn(m: Dictionary, g: Group) -> void:
	var key := str(m.get("model", ""))
	if not Game.models.has(key):
		var f := CrowdRules.fallback(StringName(str(m.get("role", ""))), int(m.get("seed", 0)))
		_missing[key] = f
		key = f
	if key == "":
		return
	var a := CrowdActor.new()
	add_child(a)
	a.setup(m, key, _vis(key))
	if a.skel:
		a.animate(CrowdPoses.library(key, a.skel, a.model))
	var p := track.path.geo(g.route)
	var s := p.progress(a.position, p.closest(a.position, p.wi(p.index_at(g.s) - 6)))
	a.lap_s = s if absf(route_delta(g.route, s - g.s)) < g.radius + 40.0 else g.s
	a.set_meta("group", g.index)
	g.members.append(a)
	g.roles[a.role] = true
	if a.dodge:
		g.dodgers.append(a)
	actors.append(a)


## Lap distance d wrapped into -length/2 .. length/2.
func wrap_s(d: float) -> float:
	var lap := track.path.length
	return fposmod(d + lap * 0.5, lap) - lap * 0.5


## A distance along route r: lap metres wrap, a branch's metres do not.
func route_delta(r: int, d: float) -> float:
	return wrap_s(d) if r < 0 else d


## The road a crowd entry ("route": a branch id) stands by: -1 the main loop, else that
## branch's index.
func route_of(e: Dictionary) -> int:
	var r = e.get("route")
	if r == null:
		return -1
	for b in track.path.branches:
		if b.id == str(r):
			return b.index
	push_warning("crowds: no branch %s, taken as the main road" % r)
	return -1


## Metres of kart `k` along route `r`: lap metres on the main loop (a kart on a branch counts
## the lap metres its place there maps to), branch metres on branch r, NAN when it is not on r.
static func along(k: Kart, r: int) -> float:
	if r < 0:
		return k.lap_progress
	return k.route_u if k.route == r else NAN


## Kart `k` is on route `r` (that road itself, not a branch beside it) within the stretch `w`.
func in_stretch(k: Kart, r: int, w: Vector2) -> bool:
	if k == null or k.route != r:
		return false
	var at := along(k, r)
	if r >= 0:
		return at >= w.x and at <= w.y
	var lap := track.path.length
	return fposmod(at - w.x, lap) <= fposmod(w.y - w.x, lap)


func _process(delta: float) -> void:
	if not _pending.is_empty():
		_spawn_batch(_pending.size(), SPAWN_US)
	_advance(_moving, HOT_HZ, _rounds[0], delta)
	_advance(_moving_far, WARM_HZ, _rounds[1], delta)
	_acc += delta
	if _acc < TICK:
		return
	_acc = fmod(_acc, TICK)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var now := CrowdActor.now()
	if _phase == 0:
		_update_karts(now)
	elif not karts.all(func(k) -> bool: return is_instance_valid(k)):
		_drop_gone()
	var cp := cam.global_position
	var cf := -cam.global_basis.z
	# the lines held back go first
	if not _held.is_empty():
		_retry_held(now, cp)
	for gi in range(_phase, groups.size(), 3):
		_tick_group(groups[gi], now, cp, cf)
	_phase = (_phase + 1) % 3
	if _phase == 0:
		_budget(cp)
		eggs.tick(now, cam)
		birds.tick(now, cp)
		var near: Array = []
		for g in groups:
			if g.tier <= 1 and g.members.size() >= 12 and g.bed != "":
				near.append(g)
		near.sort_custom(func(a: Group, b: Group) -> bool: return a.dist < b.dist)
		audio.update_beds(near, func(g: Group) -> String: return "riot" if now < g.bed_until else g.bed,
			func(g: Group) -> float: return g.excite)


## The animated spectators of `list` move `hz` times a second each, the ones owed an update
## this frame in turn (round `r`: [updates owed, where it is]); a looker's head turns in the
## same skeleton update as its clip.
func _advance(list: Array[CrowdActor], hz: float, r: Array, delta: float) -> void:
	if list.is_empty():
		r[0] = 0.0
		return
	r[0] += list.size() * hz * delta
	var n := mini(int(r[0]), list.size())
	r[0] = minf(r[0] - n, 1.0)  # a long frame drops what it cannot catch up on
	for k in n:
		var a := list[(int(r[1]) + k) % list.size()]
		a.player.advance(1.0 / hz)
		if a.look:
			a.skel.advance(1.0 / hz)
	r[1] = (int(r[1]) + n) % list.size()


# ---------------------------------------------------------------- karts
## The local player's kart (what the race camera follows; the race's player while another camera
## is on).
func me() -> Kart:
	if is_instance_valid(_me):
		return _me
	var p: Variant = _race.get("player") if _race else null
	return p if is_instance_valid(p) and p is Kart else null


func _update_karts(now: float) -> void:
	if now > _kart_t:
		_kart_t = now + 1.0
		karts.clear()
		for n in get_tree().get_nodes_in_group("karts"):
			if n is Kart:
				karts.append(n)
	_drop_gone()
	var cam := get_viewport().get_camera_3d()
	_me = (cam as RaceCamera).target if cam is RaceCamera else null
	for k in karts:
		if _me == null and k.is_player:
			_me = k
		var p := k.global_position
		var prev: Array = _prev.get(k, [p, now - 0.1])
		_vel[k] = (p - (prev[0] as Vector3)) / maxf(now - float(prev[1]), 0.02)
		_prev[k] = [p, now]
		# a jump: airborne over a gap of the road it is on (a branch's own jumps too), then down again
		var road := k.geo()
		var over := road.gap[road.wi(k.route_index)] == 1
		if not k.grounded and over:
			_air[k] = true
		elif k.grounded and _air.get(k, false):
			_air.erase(k)
			if k.state != Kart.State.RESPAWN:
				on_event(&"land", p, k)
	var live := racing()
	if live and not _was_racing:
		for g in groups:
			g.until = 0.0
	_was_racing = live


## Forget karts that left the scene (and everything kept about them).
func _drop_gone() -> void:
	karts.assign(karts.filter(func(k) -> bool: return is_instance_valid(k)))
	for d in [_prev, _vel, _air]:
		for k in d.keys():
			if not is_instance_valid(k):
				d.erase(k)
	if not is_instance_valid(_me):
		_me = null
	for g in groups:
		if not is_instance_valid(g.kart):
			g.kart = null


## The race is on (outside a race, e.g. in tests, always).
func racing() -> bool:
	var r = _race.get("racing") if _race else null
	return r == null or bool(r)


## Which world the circuit is in, by its start arch: combine (City 17), blackmesa,
## military (the desert outside Black Mesa) or xen.
func world() -> String:
	return str(track.data.get("gantry", "combine"))


## Laps of this race (3 outside a race).
func laps() -> int:
	var l = _race.get("laps") if _race else null
	return int(l) if l != null else 3


func _done() -> bool:
	return _race != null and str(_race.get("_phase")) == "done"


func velocity(k: Kart) -> Vector3:
	return _vel.get(k, Vector3.ZERO)


static func _ride(k: Kart) -> String:
	return str(k.spec.def.get("id", "")) if k and k.spec else ""


# ---------------------------------------------------------------- groups
func _tick_group(g: Group, now: float, cp: Vector3, cf: Vector3) -> void:
	var to := g.center - cp
	g.dist = maxf(to.length() - g.radius, 0.0)
	var tier := 0 if g.dist <= HOT else (1 if g.dist <= WARM else (2 if g.dist <= COLD else 3))
	if g.dist > 25.0 and to.normalized().dot(cf) < -0.3:
		tier = maxi(tier, 2)
	if g.tier == 0 and tier > 0:
		for a in g.dodgers:
			a.visible = true
	g.tier = tier
	var lively := g.state == CrowdRules.State.PEAK or g.state == CrowdRules.State.CELEBRATE
	g.excite = move_toward(g.excite, 1.0 if lively else 0.0, 0.08)
	if tier >= 2:
		return
	_focus(g)
	_update_state(g, now)
	if g.pending:
		g.pending = false
		for a in g.members:
			if a.pending():
				a.update(now)
				g.pending = g.pending or a.pending()
	if tier == 0:
		_dodges(g, cp)
		if now > g.next_chat:
			# now and then someone who has something idle to say (a scientist's cough)
			g.next_chat = now + randf_range(12.0, 25.0)
			var a := _speaker(g, "")
			if a and CrowdAudio.can_say(a.role, "idle"):
				_say(g, a, "idle", CrowdAudio.Prio.IDLE, now)


## Where the group looks: the local player within 60 m, else the leader within 60 m,
## else the nearest kart; with nobody near, up the road where they will come from.
func _focus(g: Group) -> void:
	if not racing() and g.tags.has("start"):
		g.focus = track.path.center_at(-20.0) + Vector3.UP * 0.8
		return
	var reach := 60.0 + g.radius
	var pick: Kart = null
	if _me and _me.global_position.distance_to(g.center) < reach:
		pick = _me
	else:
		var bd := INF
		for k in karts:
			var d := k.global_position.distance_to(g.center)
			if k.place == 1 and d < reach:
				pick = k
				break
			if d < bd:
				bd = d
				pick = k
	if pick and pick.global_position.distance_to(g.center) < reach + 60.0:
		g.focus = pick.global_position + Vector3.UP * 0.8
	else:
		g.focus = track.path.geo(g.route).center_at(g.watch.x - 30.0) + Vector3.UP * 1.0


## The racer nearest to passing decides: ANTICIPATE 15-60 m before the stretch the group
## watches, PEAK along it, then AFTER for 3 s. Metres count along the group's road; a 3D
## gate keeps other parts of the lap (a figure 8) from counting, and a racer on another road
## (a branch beside the main one) counts only close by. The local player's racer goes first
## with a group that has an easter egg for it; a wide group peaks for the racer passing nearest.
func _update_state(g: Group, now: float) -> void:
	var timed := g.until > 0.0 and now < g.until
	if timed and g.state != CrowdRules.State.AFTER and not _me_passing(g):
		return
	if not racing():
		var st := CrowdRules.State.ANTICIPATE if g.tags.has("start") and not _done() else CrowdRules.State.IDLE
		_set_state(g, st, null, now)
		return
	var span := fposmod(g.watch.y - g.watch.x, track.path.length) if g.route < 0 else g.watch.y - g.watch.x
	var mine := me()
	if mine and not _cares(g, mine):
		mine = null
	var best: Kart = null
	var best_score := INF
	var best_peak := false
	for k in karts:
		var at := along(k, g.route)
		var gate := g.radius + (90.0 if k.route == g.route else 30.0)
		if is_nan(at) or k.global_position.distance_squared_to(g.center) > gate * gate:
			continue
		var rel := route_delta(g.route, at - g.watch.x)
		if rel < -60.0 or rel > span + 10.0:
			continue
		var peak := rel >= -15.0
		var score := absf(rel - span * 0.5) if peak else 1000.0 - rel
		if g.wide:
			var near := _member_dist(g, k.global_position)
			peak = peak and near < g.peak_d
			score = near if peak else 1000.0 + near
		if k == g.kart:
			score -= 5.0  # hysteresis: keep the racer they are on
		if k == mine:
			score -= ME_BONUS + span * 0.5
		if score < best_score:
			best_score = score
			best = k
			best_peak = peak
	if best:
		var st := CrowdRules.State.PEAK if best_peak else CrowdRules.State.ANTICIPATE
		if timed and st == CrowdRules.State.ANTICIPATE:
			return
		g.until = 0.0
		_set_state(g, st, best, now)
	elif g.state == CrowdRules.State.PEAK:
		_set_state(g, CrowdRules.State.AFTER, g.kart, now)
		g.until = now + 3.0
	elif not timed:
		g.until = 0.0
		_set_state(g, CrowdRules.State.IDLE, null, now)


## The local player's racer, that group g has an easter egg for, is passing it while the group is
## busy with something else (a jump's cheer, someone else's crash): it takes the group over.
func _me_passing(g: Group) -> bool:
	var k := me()
	if k == null or k == g.kart or k.route != g.route or not racing() or not _cares(g, k):
		return false
	var gate := g.radius + 90.0
	if k.global_position.distance_squared_to(g.center) > gate * gate:
		return false
	var span := fposmod(g.watch.y - g.watch.x, track.path.length) if g.route < 0 else g.watch.y - g.watch.x
	var rel := route_delta(g.route, along(k, g.route) - g.watch.x)
	if rel < -15.0 or rel > span + 10.0:
		return false
	return not g.wide or _member_dist(g, k.global_position) < g.peak_d


## Someone in group g feels something about racer k (has an easter egg for it).
func _cares(g: Group, k: Kart) -> bool:
	var ride := _ride(k)
	for r in g.roles:
		if CrowdRules.attitude(r, k.character_id, ride) != &"":
			return true
	return false


## Metres from p to the nearest member of g (to its edge while nobody is placed yet).
static func _member_dist(g: Group, p: Vector3) -> float:
	if g.members.is_empty():
		return maxf(p.distance_to(g.center) - g.radius, 0.0)
	var best := INF
	for a in g.members:
		best = minf(best, a.global_position.distance_squared_to(p))
	return sqrt(best)


## Change what the group does: every member picks its clip for the new state (its mood's,
## an easter egg's toward that racer, or the event's `kind` at `at`), queued so the change
## runs along the stand with the kart.
func _set_state(g: Group, st: int, k: Kart, now: float, kind := &"", at: Variant = null) -> void:
	if st == g.state and k == g.kart and kind == &"":
		return
	g.state = st
	g.kart = k
	g.serial += 1
	var ks := along(k, g.route) if k else g.s
	if is_nan(ks):
		ks = g.s
	var who := k.character_id if k else ""
	var ride := _ride(k)
	var seen := {}
	for a in g.members:
		var att := CrowdRules.attitude(a.role, who, ride) if k else &""
		var egg := CrowdRules.egg_state(a.role, att, st) if kind == &"" else &""
		var roll := _roll(a, g.serial)
		var c := CrowdRules.event_clip(a.role, a.mood, kind, att, roll) if kind != &"" \
			else CrowdRules.pick_clip(a.mood, st, egg, roll)
		if a.role == &"zombie":
			c = &"shamble"
		a.hold(egg == &"freeze")
		var toward: Variant = at
		if k and egg in [&"condemn", &"accuse", &"salute", &"boo", &"revere"]:
			toward = k.global_position
		var delay := clampf(absf(route_delta(g.route, a.lap_s - ks)) / 30.0, 0.0, 1.2) + _roll(a, g.serial + 1) * 0.25
		a.queue(c, now + delay, toward)
		if trace and not seen.has("%s %s" % [a.role, c]):
			seen["%s %s" % [a.role, c]] = true
			decisions.append("clip %d %s %s %s %s" % [g.id, CrowdRules.STATE_NAMES[st] if kind == &"" else String(kind),
				who, a.role, c])
	g.pending = true
	if st == CrowdRules.State.PEAK and k and kind == &"":
		_pass_lines(g, k, now)


## Deterministic 0..1 per member and state change.
static func _roll(a: CrowdActor, n: int) -> float:
	return fposmod(sin(float(a.rng_seed % 100000) * 12.9898 + float(n) * 78.233) * 43758.5453, 1.0)


## A racer goes by: the members who know (or hate) them call out first.
func _pass_lines(g: Group, k: Kart, now: float) -> void:
	var ride := _ride(k)
	var mine := k == _me
	if k.character_id == "breen":
		g.bed_until = now + 6.0
	var best: CrowdActor = null
	var best_cat := ""
	var best_prio := -1
	var best_rank := -1
	for a in _near_members(g, 6):
		var att := CrowdRules.attitude(a.role, k.character_id, ride)
		var cat := CrowdRules.pass_line(a.role, att, world())
		var prio := CrowdAudio.Prio.EGG if att != &"" else CrowdAudio.Prio.PASS
		# a guest of another kind in the group (vortigaunts in a rebel camp) has its line first
		var rank := prio * 2 + (1 if CrowdRules.kind(a.role) != CrowdRules.kind(g.role) else 0)
		if CrowdAudio.can_say(a.role, cat) and rank > best_rank:
			best = a
			best_cat = cat
			best_prio = prio
			best_rank = rank
	if best == null or (best_prio == CrowdAudio.Prio.PASS and randf() > 0.35):
		return
	if best_cat == "boo_rebel" and velocity(k).length() > 25.0 and randf() < 0.3:
		best_cat = "speed"
	# an easter egg about the player's own racer does not wait for the group's last line, and waits
	# for the racer's own (or a free voice, or the camera to come near) rather than being lost
	var hold := HOLD if mine and best_prio >= CrowdAudio.Prio.EGG else 0.0
	if _say(g, best, best_cat, best_prio, now, mine, hold > 0.0, hold):
		_join_in(g, best_cat, mine)
	if best_cat == "freeman" or best_cat.begins_with("boo_rebel"):
		for a in g.members:
			if a.role == &"metrocop" and a.clip == &"condemn":
				audio.sfx(Game.crowd_line("metrocop", "baton"), a.global_position + Vector3.UP * 1.2)
				break


## After a vortigaunt's "revere" the rest of the circle chants a moment later (a tween: it goes
## with the director).
func _join_in(g: Group, cat: String, mine: bool) -> void:
	if cat != "revere":
		return
	create_tween().tween_callback(func():
		var other := _speaker(g, "vort")
		if other:
			_say(g, other, "chant", CrowdAudio.Prio.EGG, CrowdActor.now(), mine, true, HOLD if mine else 0.0)).set_delay(1.3)


## The `n` members nearest the camera.
func _near_members(g: Group, n: int) -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null or g.members.is_empty():
		return []
	if g.members.size() <= n:
		return g.members.duplicate()
	return nearest_first(g.members, cam.global_position, n)


## The first `n` of `list` (Node3Ds) by distance to `p`, nearest first: a native sort of packed
## keys (distance, then the index) rather than a script comparison per pair.
static func nearest_first(list: Array, p: Vector3, n: int) -> Array:
	var keys := PackedInt64Array()
	keys.resize(list.size())
	for i in list.size():
		keys[i] = (int(minf((list[i] as Node3D).global_position.distance_squared_to(p), 1.0e9) * 16.0) << 20) | i
	keys.sort()
	var out := []
	for k in mini(n, keys.size()):
		out.append(list[keys[k] & 0xFFFFF])
	return out


## Someone in the group with `role` ("" anyone) near the camera.
func _speaker(g: Group, role: String) -> CrowdActor:
	for a in _near_members(g, 8):
		if role == "" or String(a.role) == role:
			return a
	return null


## The member of `role` nearest the camera, wherever in the group (a held line goes to whoever of
## that role the camera comes nearest).
func _nearest_of(g: Group, role: StringName, cp: Vector3) -> CrowdActor:
	var best: CrowdActor = null
	var bd := INF
	for a in g.members:
		if a.role == role and a.global_position.distance_squared_to(cp) < bd:
			bd = a.global_position.distance_squared_to(cp)
			best = a
	return best


## A line from member `a`: the group keeps quiet for 7 s after it (4 s for the next egg).
## `force` ignores the group's wait (lines that belong to one reaction); `hold` seconds a line
## refused for HOLD_FOR waits to be said (by whoever of that role is nearest the camera then);
## while one waits, nobody says anything less than an easter egg.
func _say(g: Group, a: CrowdActor, cat: String, prio: int, now: float, mine := false, force := false,
		hold := 0.0) -> bool:
	if cat == "":
		return false
	var queue := prio < CrowdAudio.Prio.EGG and not _held.is_empty()
	var ok := not queue and (force or now >= (g.next_egg if prio >= CrowdAudio.Prio.EGG else g.next_line))
	var path := audio.say(a.global_position + Vector3.UP * 1.6, a.role, cat, prio, mine) if ok else ""
	var why := "" if path != "" else (audio.refused if ok else ("queue" if queue else "group"))
	var held := hold > 0.0 and why in HOLD_FOR
	if held and not _held.any(func(h: Array) -> bool: return h[0] == g and h[2] == cat):
		_held.append([g, a.role, cat, prio, g.kart, now + hold, why, why != "far", INF])
	if trace:
		decisions.append("line %d %s %s %s" % [g.id, a.role, cat, "played" if path != "" else
			("held " if held else "skipped ") + why])
	if path == "":
		return false
	g.next_line = now + 7.0
	g.next_egg = now + 4.0
	return true


## Lines held back (the racer talking, every voice busy, the camera not near yet) try again until
## they are said or their time is up, the racer they are about has left the race, or the camera
## has gone by the speakers (the player has moved on): out of their range after it was in it, or
## out of it and further off than it has been (it passed them before the line came up).
func _retry_held(now: float, cp: Vector3) -> void:
	for h: Array in _held.duplicate():
		var g: Group = h[0]
		var role: StringName = h[1]
		var cat: String = h[2]
		var late := now > float(h[5])
		if late or not is_instance_valid(h[4]):
			_held.erase(h)
			if trace:
				decisions.append("line %d %s %s skipped %s" % [g.id, role, cat, "late" if late else "gone"])
			continue
		var a := _nearest_of(g, role, cp)
		if a == null or audio.say(a.global_position + Vector3.UP * 1.6, role, cat, h[3], true) == "":
			# the trace says why, each time the reason changes (nobody of that role left: "speaker")
			var why := "speaker" if a == null else audio.refused
			var out := why == "far" or why == "speaker"
			var d := a.global_position.distance_to(cp) if a else INF
			if out and (h[7] or d > float(h[8]) + LEAVING):
				_held.erase(h)
				if trace:
					decisions.append("line %d %s %s skipped passed" % [g.id, role, cat])
				continue
			if trace and why != str(h[6]):
				decisions.append("line %d %s %s wait %s" % [g.id, role, cat, why])
			h[6] = why
			h[7] = not out
			h[8] = minf(float(h[8]), d)
			continue
		_held.erase(h)
		g.next_line = now + 7.0
		g.next_egg = now + 4.0
		if trace:
			decisions.append("line %d %s %s played" % [g.id, role, cat])
		_join_in(g, cat, true)


# ---------------------------------------------------------------- budget
## Animation and look-at caps: the groups nearest the camera first, inside a group the
## members nearest the camera; everyone else freezes in the pose they had.
func _budget(cp: Vector3) -> void:
	var near: Array = []
	for g in groups:
		if g.tier <= 1 and not g.members.is_empty():
			near.append(g)
	near.sort_custom(func(a: Group, b: Group) -> bool: return a.dist < b.dist)
	var on := {}
	var hot: Array = []
	var left := max_animated
	for g: Group in near:
		if left <= 0:
			break
		var ms: Array = g.members if g.members.size() <= left else nearest_first(g.members, cp, left)
		for a: CrowdActor in ms:
			on[a] = true
			if g.tier == 0 and a.skel:
				hot.append(a)
		left -= ms.size()
	for a: CrowdActor in _animated:
		if not on.has(a):
			a.set_active(false)
	for a: CrowdActor in on:
		a.set_active(true)
	_animated = on
	# look-at: the nearest hot ones follow their group's focus
	var keep: Array = nearest_first(hot, cp, max_lookers)
	# lookers still among the nearest go on; the others turn their heads back first (while
	# they still animate: their look-at moves with the clip) and hold their place under the
	# cap until they have, then drop the modifier
	var looking := {}
	for a: CrowdActor in _lookers:
		if a in keep:
			looking[a] = true
			continue
		a.look.goal = 0.0
		if a.look.weight > 0.01 and on.has(a):
			looking[a] = true
		else:
			a.look.queue_free()
			a.look = null
	for a: CrowdActor in keep:
		if not looking.has(a) and looking.size() >= max_lookers:
			break
		if a.look == null:
			var l := CrowdLook.new()
			if not l.setup(a.skel):
				l.free()
				continue
			a.skel.add_child(l)
			a.look = l
		a.look.goal = 1.0
		a.look.target = groups[a.get_meta("group")].focus
		looking[a] = true
	_lookers = looking
	# the hot ones and every looker (its head turns in its skeleton's update) at HOT_HZ, the rest at WARM_HZ
	var near_cam := {}
	for a in hot:
		near_cam[a] = true
	_moving.clear()
	_moving_far.clear()
	for a: CrowdActor in on:
		if a.player:
			(_moving if near_cam.has(a) or a.look else _moving_far).append(a)
	_moving.append_array(eggs.moving())
	_place_glows(cp)


## Pavement spectators hop out of the way of a kart heading straight at them.
func _dodges(g: Group, cp: Vector3) -> void:
	if g.dodgers.is_empty():
		return
	for a in g.dodgers:
		a.hide_near_camera(cp)
	for k in karts:
		var p := k.global_position
		if p.distance_squared_to(g.center) > (g.radius + 25.0) ** 2:
			continue
		var v := velocity(k)
		if v.length() < 3.0:
			continue
		var e := p + v * 0.6
		for a in g.dodgers:
			var q := Geometry3D.get_closest_point_to_segment(a.global_position, p, e)
			if q.distance_to(a.global_position) < 1.6 and a.dodge_from(p, v):
				_say(g, a, CrowdRules.dodge_line(a.role), CrowdAudio.Prio.EVENT, CrowdActor.now())


# ---------------------------------------------------------------- events
func on_event(kind: StringName, pos: Vector3, a: Kart = null, b: Kart = null, info: Variant = null) -> void:
	var now := CrowdActor.now()
	if kind == &"lead":
		if now < _lead_until:
			return
		_lead_until = now + 3.0
		if trace:
			lead_times.append(now)
	if trace:
		decisions.append("event %s" % kind)
	match kind:
		&"explosion":
			_react(pos, 35.0, kind, a, now, 1.2, CrowdRules.State.SHOCK)
			_warn_gordon(pos, now)
		&"hit":
			_react(pos, 40.0, kind, a, now, 2.0, CrowdRules.State.AFTER)
			_warn_gordon(pos, now)
		&"fall":
			_react(pos, 50.0, kind, a, now, 2.5, CrowdRules.State.AFTER)
		&"headcrab", &"zombie":
			_react(pos, 20.0, kind, a, now, 3.0, CrowdRules.State.SHOCK)
		&"knock":
			_knock(pos, a, str(info) if info != null else "", now)
		&"start":
			for g in groups:
				if g.tags.has("start"):
					_timed(g, CrowdRules.State.CELEBRATE, a, now, 2.0, kind)
					if g.tier > 1 or g.said_start:
						continue
					for sp: CrowdActor in _near_members(g, 6):
						var cat := CrowdRules.event_line(sp.role, kind, &"")
						if CrowdAudio.can_say(sp.role, cat):
							g.said_start = true
							_say(g, sp, cat, CrowdAudio.Prio.EVENT, now)
							break
		&"lead":
			if a and a.global_position.distance_to(track.path.center[0]) < 120.0:
				for g in groups:
					if g.tags.has("start"):
						_timed(g, CrowdRules.State.CELEBRATE, a, now, 2.0, &"start")
			if a:
				_react(a.global_position, 60.0, kind, a, now, 0.0, -1)
		&"final_lap":
			# into the last lap in last place: "We trusted you!"
			if a and karts.size() > 1 and a.place >= karts.size():
				_react(a.global_position, 60.0, &"last", a, now, 0.0, -1)
		&"finish":
			if a and (int(info if info != null else 1) <= 1 or a == _me):
				for g in groups:
					if g.tags.has("start"):
						_timed(g, CrowdRules.State.CELEBRATE, a, now, 6.0, kind)
						_layered_cheers(g, a)
		&"land":
			for g in groups:
				if g.tags.has("jump") and g.center.distance_to(pos) < g.radius + 60.0:
					# the player's racer, that they have an easter egg for: that rather than a cheer
					if a and a == me() and _cares(g, a):
						_set_state(g, CrowdRules.State.PEAK, a, now)
						g.until = now + 2.0
					else:
						_timed(g, CrowdRules.State.CELEBRATE, a, now, 3.0, &"start")
	eggs.on_event(kind, pos, a, b, info)
	birds.on_event(kind, pos)


## Groups near `pos` react to `kind` about kart `k` for `secs` (state `st`; -1 only a
## line), each member by its role and its attitude to that racer.
func _react(pos: Vector3, r: float, kind: StringName, k: Kart, now: float, secs: float, st: int) -> void:
	var who := k.character_id if k else ""
	var ride := _ride(k)
	for g in groups:
		if g.tier > 1 or g.center.distance_to(pos) > g.radius + r:
			continue
		if kind == &"explosion":
			if now < g.next_shock:
				continue
			g.next_shock = now + 6.0
		if st >= 0:
			var staff := String(g.role) in CrowdRules.STAFF and (kind == &"explosion" or kind == &"headcrab")
			_timed(g, st, k, now, 3.0 if staff else secs, kind, pos)
		var best: CrowdActor = null
		var best_cat := ""
		for a: CrowdActor in _near_members(g, 6):
			var cat := CrowdRules.event_line(a.role, kind, CrowdRules.attitude(a.role, who, ride))
			if not CrowdAudio.can_say(a.role, cat):
				continue
			# the first one with something to say; a line for Gordon wins over the rest
			if best == null or cat.begins_with("gordon"):
				best = a
				best_cat = cat
		if best:
			var egg := best_cat.begins_with("gordon") or best_cat == "headcrab" or best_cat == "chuckle"
			_say(g, best, best_cat, CrowdAudio.Prio.EGG if egg else CrowdAudio.Prio.EVENT, now, k == _me and egg)


func _timed(g: Group, st: int, k: Kart, now: float, secs: float, kind: StringName, at: Variant = null) -> void:
	_set_state(g, st, k, now, kind, at)
	g.until = now + secs


## "Look out, Freeman!": something blew up or hit near Gordon.
func _warn_gordon(pos: Vector3, now: float) -> void:
	for k in karts:
		if k.character_id != "gordon" or k.global_position.distance_to(pos) > 10.0:
			continue
		for g in groups:
			if g.tier > 1 or g.center.distance_to(pos) > g.radius + 40.0:
				continue
			for a: CrowdActor in _near_members(g, 6):
				if a.role in HUMANS:
					_say(g, a, "gordon_warn", CrowdAudio.Prio.EGG, now, k == _me, true)
					return


func _layered_cheers(g: Group, k: Kart) -> void:
	if g.tier > 1:
		return
	var who := k.character_id if k else ""
	var ms := _near_members(g, 6)
	for n in mini(3, ms.size()):
		var a: CrowdActor = ms[n]
		var cat := CrowdRules.event_line(a.role, &"finish", CrowdRules.attitude(a.role, who))
		if CrowdAudio.can_say(a.role, cat):
			create_tween().tween_callback(func():
				_say(g, a, cat, CrowdAudio.Prio.EVENT, CrowdActor.now(), false, true)).set_delay(0.3 + n * 1.4)


## "Pick up that can": a trash can knocked over near a metrocop spectator.
func _knock(pos: Vector3, k: Kart, key: String, now: float) -> void:
	if not TRASH.any(func(t: String) -> bool: return key.contains(t)):
		return
	var best: CrowdActor = null
	var bg: Group = null
	var bd := 15.0
	for g in groups:
		if g.center.distance_to(pos) > g.radius + 15.0:
			continue
		for a in g.members:
			if a.role == &"metrocop" and a.global_position.distance_to(pos) < bd:
				bd = a.global_position.distance_to(pos)
				best = a
				bg = g
	if best == null:
		return
	best.queue(&"point", now, pos)
	bg.pending = true
	if trace:
		decisions.append("clip %d knock %s metrocop point" % [bg.id, k.character_id if k else ""])
	if k and k.character_id == "police":
		_say(bg, best, "chuckle", CrowdAudio.Prio.EGG, now, k == _me, true)
		return
	var path := _can_line(_cans)
	_cans += 1
	var played := path != "" and audio.say_path(best.global_position + Vector3.UP * 1.6, path, CrowdAudio.Prio.EGG,
		k == _me)
	if trace:
		decisions.append("line %d metrocop %s %s" % [bg.id, path.get_file().get_basename() if path != "" else "knock",
			"played" if played else "skipped"])


## The n-th time: pickupthecan1, 2, 3, then put it in the trash.
func _can_line(n: int) -> String:
	var l: Array = Game.voices.get("_crowd", {}).get("metrocop", {}).get("knock", [])
	var want := "pickupthecan%d" % (n + 1) if n < 3 else "putitinthetrash%d" % ((n - 3) % 2 + 1)
	for p in l:
		if str(p).get_file().get_basename() == want:
			return str(p)
	return str(l[n % l.size()]) if not l.is_empty() else ""


# ---------------------------------------------------------------- Xen
## Dark vortigaunts on dark ground vanish: a glow over each circle, and four small green
## lights that follow the circles nearest the camera.
func _xen_glows() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = SourceMaterials.tex("materials/sprites/glow01.png")
	m.albedo_color = Color(0.35, 0.9, 0.45)
	m.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	quad.material = m
	for g in groups:
		if g.role != &"vort" and g.role != &"islave":
			continue
		var s := MeshInstance3D.new()
		s.mesh = quad
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visibility_range_end = 180.0
		add_child(s)
		s.global_position = g.center + Vector3.UP * 1.2
		_glow_groups.append(g)
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(0.5, 1.0, 0.6)
		l.omni_range = 8.0
		l.light_energy = 1.6
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_glows.append(l)


func _place_glows(cp: Vector3) -> void:
	if _glows.is_empty():
		return
	var near := _glow_groups.filter(func(g: Group) -> bool: return g.center.distance_to(cp) < 70.0)
	near.sort_custom(func(a: Group, b: Group) -> bool:
		return a.center.distance_squared_to(cp) < b.center.distance_squared_to(cp))
	for i in _glows.size():
		_glows[i].visible = i < near.size()
		if i < near.size():
			_glows[i].global_position = (near[i] as Group).center + Vector3.UP * 2.0
