class_name AntlionHazard
extends Hazard
## A beach where antlions sleep under the sand (stage D4, Sandtraps). The boards and the road are
## safe; a kart that leaves them and keeps its wheels on the sand of the zone (Kart.offroad, synced to
## the proxies too) for longer than p["grace"] wakes a group of one to three antlions. The server (or
## the offline game) notices it and sends one "wake" event: the kart's slot, the clock time, and for
## each antlion the spot on the sand where it digs out and the spot where its pounce lands, which is
## where the kart will be by then if it keeps going (its lap metres run on along the road at its speed,
## its offset from the road kept). From the event everything runs on the shared clock, the same on
## every peer: first the warning (the sand bulges and dust rises at each spot, a rumble and the digging
## sound, a ring on the sand where each one will land, the target's HUD lock), then each antlion digs
## out (its digout, which carries it forward), runs at the landing spot and pounces; a kart it reaches
## spins. Then they stand a moment and dig back in. Each kart's owner judges its own karts; a kart
## the group hit is left alone for the rest of the pass (Hazard.hit). Spots and runs keep off every
## road by p["keep"] metres, and a pounce only takes a kart with its wheels on the sand (Kart.offroad),
## so a kart that gets back onto the boards in time is out of reach. Online the server also stops
## waking groups for a client's kart once its owner reports a hit (net_hits) until it leaves the zone.
## Several karts on the sand wake several groups, never more than p["max_alive"] antlions at once.
## A thumper (p["thumpers"]) keeps them asleep within p["thumper_r"] metres of it.

const SAND := Color(0.86, 0.76, 0.55)
## seconds of the antlion's own digout (39 frames at 30 fps) and the metres it carries one forward
const DIGOUT_LEN := 38.0 / 30.0
const DIG_MOVE := 4.45
const DIG_RATE := 1.4         # the digout played this much faster than its own pace
const POUNCE_LEN := 33.0 / 30.0  # its pounce (34 frames at 30 fps), an 8 m leap at its own pace
const POUNCE_L := 6.5         # metres of a full pounce here
const POUNCE_T := 0.75        # seconds of the leap
const POUNCE_ARC := 0.7       # metres the leap arcs over the ground at its top
const RUN := 10.0             # m/s they run at (their agitated run is 9 m/s at its own pace)
const LINGER := 0.7           # seconds they stand where they landed, then dig back in
const DIGIN_LEN := 99.0 / 60.0  # its digin (100 frames at 60 fps)
const DIGIN_RATE := 1.3
const STAGGER := 0.22         # seconds between one antlion of a group digging out and the next
const HIT_R := 2.4            # metres round an antlion's front (in plan) its pounce reaches
const HIT_FROM := 0.35        # share of the leap after which it can hit, up to HIT_AFTER past landing
const HIT_AFTER := 0.35
const FRONT := 0.7            # metres from its origin to its jaws
const POSE_NEAR := 60.0       # metres from the camera within which they are posed every frame
const DIG_T := DIGOUT_LEN / DIG_RATE
const DIGIN_T := DIGIN_LEN / DIGIN_RATE
## approach angles (radians off straight across the kart's path, towards where it comes from) tried
## for a spot, the first ones first
const ANGLES := [0.45, 0.85, 0.15, 1.1]
## a thumper's beat: its idle (86 frames at 30 fps) lifts the hammer slowly and drops it at the end
const THUMP_EVERY := 85.0 / 30.0
const THUMP_AT := 0.985       # share of its beat where the hammer lands
## plan metres a dig-out spot and the run from it keep from any spectator (track data "crowds")
const CROWD_KEEP := 4.0

var anims: AnimSet
## serial -> {"slot", "t0", "ants": [ant...], "s_lo", "s_hi", "side", "nodes": {}, "fired"}; an ant is
## {"S", "P", "dir", "pts", "cum", "dig", "run", "pounce", "t_dig", "t_run", "t_pnc", "t_land", "t_in",
## "t_gone", "skin"} (see _plan)
var _wakes := {}
var _serial := 0               # the authority's next wake serial
## the authority's wakes: how many antlions it wanted and how many found a spot (tests, tuning)
var stats := {"wakes": 0, "wanted": 0, "placed": 0, "no_room": 0}
var _sand := {}                # kart -> seconds it has been on the zone's sand (authority)
var _rearm := {}               # kart -> clock from which it may wake another group (authority)
var _hits0 := {}               # a client's kart -> its net_hits when the last group was woken for it (authority)
var _pool: Array = []          # [{"node", "sk", "skin", "busy": [serial, j] or []}]
var _near_ids := PackedInt32Array()   # main loop samples round the zone (road clearance checks)
var _thumpers: Array[Vector3] = []
var _crowd := PackedVector2Array()   # the spectators near the zone (plan x, z): no antlion comes up among them
var _thumper_nodes: Array = []
var _ambient: AudioStreamPlayer3D
var _idle_t := 3.0
var _snd := {}
static var _mound_mat: StandardMaterial3D


func defaults() -> Dictionary:
	return {"zone": [s - 50.0, s + 50.0], "side": 0, "branches": [], "grace": 0.4, "edge": 0.3, "count": [1, 3],
		"max_alive": 6, "warn": 1.0, "rearm": 2.5, "lead": 1.0, "keep": 2.0, "reach": [11.0, 16.0], "tail": 30.0,
		"effect": "spin", "push": 0.35, "lift": 0.12, "scale": 1.0, "model": "antlion", "thumpers": [],
		"thumper_r": 28.0, "thumper_model": "props_combine/combinethumper002", "thumper_every": THUMP_EVERY}


func build() -> void:
	aims_all = true
	for q in p["thumpers"]:
		if q is Array and (q as Array).size() >= 3:
			_thumpers.append(Vector3(q[0], q[1], q[2]))
	# the lap's samples a spot could lie beside: the zone's own stretch and any other stretch of the
	# lap that passes within reach of it (a hairpin, a road back along the beach)
	var zone: Array = p["zone"]
	var a := float(zone[0]) - 60.0
	var b := float(zone[1]) + float(p["tail"]) + 60.0
	var mine := PackedVector3Array()
	for i in path.n:
		if director.in_span(path.u_of(i), a, b):
			mine.append(path.center[i])
	for i in path.n:
		var c := path.center[i]
		for q in mine:
			if Vector2(q.x - c.x, q.z - c.z).length() < 90.0:
				_near_ids.append(i)
				break
	# the spectators standing within reach of the zone's sand (the same track data on every peer;
	# only the authority picks spots, so a peer that shows no crowd still agrees)
	var people = track.data.get("crowds", []) if track != null and track.data is Dictionary else []
	for m in people:
		var mp = m.get("pos", []) if m is Dictionary else []
		if not mp is Array or (mp as Array).size() < 3:
			continue
		var at := Vector2(float(mp[0]), float(mp[2]))
		for q in mine:
			if Vector2(q.x, q.z).distance_to(at) < 70.0:
				_crowd.append(at)
				break
	_snd["rumble"] = sounds([["npc/antlion/rumble1.wav"], ["ambient/levels/coast/antlion_hill_ambient1.wav"],
		["physics/surfaces/sand_impact_bullet1.wav"]])
	_snd["digup"] = sounds([["npc/antlion/digup1.wav"], ["physics/surfaces/sand_impact_bullet2.wav",
		"physics/surfaces/sand_impact_bullet3.wav"], ["physics/surfaces/sand_impact_bullet1.wav"]])
	_snd["digdown"] = sounds([["npc/antlion/digdown1.wav"], ["physics/surfaces/sand_impact_bullet4.wav"]])
	_snd["attack"] = sounds([["npc/antlion/attack_single1.wav", "npc/antlion/attack_single2.wav",
		"npc/antlion/attack_single3.wav", "npc/antlion/attack_double1.wav", "npc/antlion/attack_double2.wav",
		"npc/antlion/attack_double3.wav"], ["npc/headcrab/attack1.wav"]])
	_snd["idle"] = sounds([["npc/antlion/idle1.wav", "npc/antlion/idle2.wav", "npc/antlion/idle3.wav",
		"npc/antlion/idle4.wav", "npc/antlion/idle5.wav"]])
	_snd["land"] = sounds([["npc/antlion/land1.wav"], ["physics/surfaces/sand_impact_bullet1.wav"]])
	_snd["thump"] = sounds([["ambient/machines/thumper_hit.wav"], ["ambient/machines/thumper_dust.wav"]])
	# each thumper is solid on every peer (a box round its model, like a static prop): its model and
	# its own animation on it where there is something to see
	var tkey := pick_model([str(p["thumper_model"]), "props_combine/combinethumper002"])
	for q in _thumpers:
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", "wall")
		add_child(body)
		body.top_level = true
		var c := path.center[path.closest(q)] - q
		body.global_transform = Transform3D(Basis(Vector3.UP, atan2(c.x, c.z)), q)
		var box := AABB(Vector3(-1.2, 0.0, -0.8), Vector3(2.4, 6.7, 1.6))
		if tkey != "":
			box = Game.model_aabb(tkey)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = box.size
		cs.shape = sh
		cs.position = box.get_center()
		body.add_child(cs)
		if visual and tkey != "":
			var m := Game.spawn_model(tkey)
			body.add_child(m)
			_thumper_nodes.append([m, AnimSet.skeleton(m), AnimSet.of(tkey)])
		else:
			_thumper_nodes.append([null, null, null])
	if not visual:
		return
	var key := str(p["model"])
	if Game.models.has(key):
		anims = AnimSet.of(key)
		for i in int(p["max_alive"]):
			var skin := i % 4
			var node := Game.spawn_model(key, "", skin)
			add_child(node)
			node.top_level = true
			node.visible = false
			node.scale = Vector3.ONE * float(p["scale"])
			_pool.append({"node": node, "sk": AnimSet.skeleton(node), "skin": skin, "busy": []})
	_ambient = loop(["ambient/levels/coast/antlion_hill_ambient1.wav", "ambient/levels/coast/antlion_hill_ambient2.wav",
		"ambient/levels/coast/antlion_hill_ambient4.wav"], self, 10.0, -8.0)


# ---------------------------------------------------------------- the rules
## Main loop samples near the zone that a point could be beside, and the branches' roads: plan
## metres from q to the nearest road edge there (negative on a road). Roads more than 6 m above or
## below q (a bridge over the beach, a tunnel under it) do not count.
func road_clearance(q: Vector3) -> float:
	var best := INF
	for i in _near_ids:
		best = minf(best, _edge_gap(path, i, q))
	for br: TrackBranch in path.branches:
		var j := br.closest(q)
		for k in range(maxi(j - 2, 0), mini(j + 3, br.n)):
			best = minf(best, _edge_gap(br, k, q))
	return best


func _edge_gap(g: TrackPath, i: int, q: Vector3) -> float:
	var d := q - g.center[i]
	if absf(d.y) > 6.0 or absf(d.dot(g.fwd[i])) > g.step * 0.75:
		return INF
	return absf(d.dot(g.right[i])) - g.width[i] * 0.5


func _near_thumper(q: Vector3) -> bool:
	var r := float(p["thumper_r"])
	for c in _thumpers:
		if Vector2(q.x - c.x, q.z - c.z).length() < r:
			return true
	return false


## Whether q is within CROWD_KEEP (plan) of a spectator by the zone.
func _near_crowd(q: Vector3) -> bool:
	for c in _crowd:
		if Vector2(q.x - c.x, q.z - c.y).length() < CROWD_KEEP:
			return true
	return false


## The road a kart drives in the zone, or null when it is somewhere the zone does not cover (another
## branch, outside its lap metres).
func _road_of(k: Kart) -> TrackPath:
	if not director.in_span(k.lap_progress, float(p["zone"][0]), float(p["zone"][1])):
		return null
	if k.route < 0:
		return path
	var br: TrackBranch = path.branches[k.route]
	return br if (p["branches"] as Array).has(br.id) else null


## True while kart k has its wheels on the zone's sand: off the road it drives, on the side the zone
## has sand, not by a thumper.
func on_sand(k: Kart) -> bool:
	if not k.offroad:
		return false
	var g := _road_of(k)
	if g == null:
		return false
	var i := k.route_index
	var lat := g.lateral(k.global_position, i)
	if absf(lat) < g.width[i] * 0.5 + float(p["edge"]):
		return false
	if int(p["side"]) != 0 and signf(lat) != signf(float(p["side"])):
		return false
	return not _near_thumper(k.global_position)


func _alive(t: float) -> int:
	var n := 0
	for w in _wakes.values():
		for a in w["ants"]:
			if t < float(a["t_gone"]):
				n += 1
	return n


func _busy_with(k: Kart, t: float) -> bool:
	var slot := director.slot_of(k)
	for w in _wakes.values():
		if int(w["slot"]) == slot and t < _ends(w):
			return true
	return false


static func _ends(w: Dictionary) -> float:
	var e := -INF
	for a in w["ants"]:
		e = maxf(e, float(a["t_gone"]))
	return e


func tick(t: float, dt: float) -> void:
	if t >= 0.0 and director.authority():
		for k in all_karts():
			# a client's kart: the server does not see its immunity, only the hits its owner reports.
			# One since its last group woke (bitten, or hit on the way): no more groups until it is
			# out of the zone, as its own director would refuse their bites anyway
			if k.remote and _hits0.has(k):
				if _road_of(k) == null:
					_hits0.erase(k)
				elif k.net_hits > int(_hits0[k]):
					_sand.erase(k)
					continue
			if not targetable(k) or not on_sand(k):
				_sand.erase(k)
				continue
			_sand[k] = float(_sand.get(k, 0.0)) + dt
			if float(_sand[k]) >= float(p["grace"]) and t >= float(_rearm.get(k, -INF)) and not _busy_with(k, t):
				_wake_for(k, t)
	for sn in _wakes.keys():
		var w: Dictionary = _wakes[sn]
		var first := _first_land(w)
		if t < first:
			_lock(w, t, first)
		for j in (w["ants"] as Array).size():
			var a: Dictionary = w["ants"][j]
			if crossed(float(a["t_pnc"]), t) and not w["fired"]:
				w["fired"] = true
				director.note(self, "fire")
			if t >= float(a["t_pnc"]) + POUNCE_T * HIT_FROM and t < float(a["t_land"]) + HIT_AFTER:
				_bite(a, t)
		if visual:
			_show(sn, w, t)
		if t > _ends(w) + 0.5:
			_drop(sn)
	if visual:
		_sounds(t, dt)
		_thump(t)


## The authority wakes a group for kart k: how many (fewer when the zone already has many awake),
## where each digs out and lands, sent to every peer as one event.
func _wake_for(k: Kart, t: float) -> void:
	var room := int(p["max_alive"]) - _alive(t)
	var cmin := int(p["count"][0])
	var cmax := int(p["count"][1])
	# fewer on EASY: the director's "every" scale (how often a hazard comes at you) thins the group
	cmax = clampi(roundi(float(cmax) / director.scale("every")), cmin, cmax)
	var want := mini(cmin + int(rnd(_serial, 1) * float(cmax - cmin + 1)), cmax)
	want = mini(want, room)
	if want <= 0:
		return
	var args: Array = [_serial, director.slot_of(k), t]
	var spots: Array[Vector3] = []
	for j in want:
		var got := _spot_for(k, t, j, spots)
		if got.is_empty():
			continue
		spots.append(got[0])
		args.append_array([got[0].x, got[0].y, got[0].z, got[1].x, got[1].y, got[1].z])
	# nowhere on the sand to come from (a narrow strip, a thumper near): try again in a moment
	_sand[k] = 0.0
	stats["wanted"] = int(stats["wanted"]) + want
	stats["placed"] = int(stats["placed"]) + spots.size()
	if spots.is_empty():
		stats["no_room"] = int(stats["no_room"]) + 1
		return
	stats["wakes"] = int(stats["wakes"]) + 1
	_serial += 1
	if k.remote:
		_hits0[k] = k.net_hits
	send("wake", args)


## Antlion j of a group for kart k woken at clock t: [dig-out spot, landing spot], or [] when no spot
## fits. Its landing is where the kart will be as it lands; its spot lies `reach` metres from there,
## ahead of the kart and out on the sand away from the road, on the sand of the zone, off every road
## and clear of the props and of the group's other spots.
func _spot_for(k: Kart, t: float, j: int, taken: Array[Vector3]) -> Array:
	var reach: Array = p["reach"]
	var keep := float(p["keep"])
	var zone: Array = p["zone"]
	for tries in 6:
		var d := lerpf(float(reach[0]), float(reach[1]), rnd(_serial * 16 + j, tries))
		if tries >= 4:
			d = 8.0  # no room for a run: a short leap straight out of the hole
		# (its place in the event is the number placed before it: a groupmate with no spot is left out)
		var tm_land := _land_after(taken.size(), d)
		var pr := _predict(k, tm_land)
		if pr.is_empty():
			return []
		var land: Vector3 = pr[0]
		var fwd: Vector3 = pr[1]
		var away: Vector3 = pr[2]
		if not director.in_span(path.progress(land, path.closest(land, k.path_index)), float(zone[0]) - 10.0,
				float(zone[1]) + float(p["tail"])):
			return []
		for ang: float in [ANGLES[(j + tries) % ANGLES.size()], ANGLES[(j + tries + 1) % ANGLES.size()]]:
			for sgn: float in [1.0, -1.0]:
				# away from the road first; the road's side only where there is room
				var dir := (-away * sgn * cos(ang) - fwd * sin(ang)).normalized()
				var spot := land - dir * d
				if _fits(spot, land, keep, taken):
					var g: Array = _ground_at(spot, 4.0, 10.0)
					spot.y = float(g[0])
					return [spot, land]
	return []


## A dig-out spot and the run from it to its landing: on the zone's sand (or ground the world does
## not say is anything else), off every road by `keep`, clear of props, of the others and of thumpers.
func _fits(spot: Vector3, land: Vector3, keep: float, taken: Array[Vector3]) -> bool:
	for q in taken:
		if Vector2(q.x - spot.x, q.z - spot.z).length() < 3.0:
			return false
	for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var q := spot.lerp(land, u)
		if _near_thumper(q) or (u < 1.0 and road_clearance(q) < keep) or _near_crowd(q):
			return false
	if road_clearance(land) < keep * 0.5:
		return false
	var g: Array = _ground_at(spot, 4.0, 10.0)
	if str(g[1]) != "offroad" and str(g[1]) != "":
		return false
	if str(g[1]) == "" and is_inside_tree() and _world_has_ground():
		# a hole in the world (the sea, a cliff edge): nowhere to come out of
		return false
	if track != null and track.liquid_at(Vector3(spot.x, float(g[0]), spot.z), -1).x > float(g[0]) - 0.2:
		# the floor of the sea or a lagoon, under water
		return false
	if is_inside_tree():
		# a ball where its body comes up, clear of the sand under it: a rock, a boat, a post is in the way
		var at := Vector3(spot.x, float(g[0]) + 1.4, spot.z)
		var sh := SphereShape3D.new()
		sh.radius = 0.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, at)
		q.collision_mask = Game.LAYER_PROP | Game.LAYER_WORLD
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return false
	return true


## Whether the static world has collision at all here (the determinism test builds none).
func _world_has_ground() -> bool:
	var c := path.center[path.index_at(s)]
	return str(_ground_at(c, 3.0, 6.0)[1]) != ""


## Seconds from the wake to antlion j's landing when its spot lies d metres from it.
func _land_after(j: int, d: float) -> float:
	var sp := _split(d)
	return tm("warn") + STAGGER * j + DIG_T + sp.y / RUN + POUNCE_T


## How d metres from spot to landing are covered: Vector3(digout, run, pounce), the same on every peer.
static func _split(d: float) -> Vector3:
	var pounce := minf(POUNCE_L, d * 0.5)
	var dig := minf(DIG_MOVE, d - pounce)
	return Vector3(dig, maxf(d - pounce - dig, 0.0), pounce)


## Where kart k will be `ahead_t` seconds from now as its road leads: [the point, its heading (plan),
## the plan direction away from the road on its side]. Its metres along its road run on at its speed,
## its offset from the road drifts with its sideways speed (by half), and stays off the road.
func _predict(k: Kart, ahead_t: float) -> Array:
	var g := _road_of(k)
	if g == null:
		return []
	var i := k.route_index
	var v := k.velocity()
	var lead := ahead_t * float(p["lead"])
	var along := v.dot(g.fwd[i])
	var lat0 := g.lateral(k.global_position, i)
	var side := signf(lat0) if absf(lat0) > 0.01 else 1.0
	var u0 := k.route_pos()
	var u1 := u0 + along * lead
	if g != path:
		u1 = clampf(u1, 0.0, g.length)
	var j := g.index_at(u1)
	var hw := g.width[j] * 0.5
	var lat1 := lat0 + v.dot(g.right[i]) * lead * 0.5
	if signf(lat1) != side or absf(lat1) < hw + float(p["keep"]):
		lat1 = side * (hw + float(p["keep"]))
	var at := g.center_at(u1) + g.right[j] * lat1
	var fw := Vector3(g.fwd[j].x, 0.0, g.fwd[j].z).normalized() * (1.0 if along >= 0.0 else -1.0)
	var away := Vector3(g.right[j].x, 0.0, g.right[j].z).normalized() * side
	at.y = float(_ground_at(at, 4.0, 10.0)[0])
	return [at, fw, away]


## The static world's ground under q, looked for from `up` metres over q's height down to `down`
## under it: [height, surface ("offroad", "road", "wall"), normal], or [q's own height, "", up] over
## nothing.
func _ground_at(q: Vector3, up: float, down: float) -> Array:
	if not is_inside_tree():
		return [q.y, "", Vector3.UP]
	var rq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * up, q - Vector3.UP * down, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	if hit.is_empty():
		return [q.y, "", Vector3.UP]
	var col = hit.get("collider")
	var surf := str((col as Node).get_meta("surface", "road")) if col is Node else "road"
	var n: Vector3 = hit["normal"]
	return [(hit["position"] as Vector3).y, surf, n if n.y > 0.3 else Vector3.UP]


func on_event(kind: String, args: Array) -> void:
	if kind != "wake" or args.size() < 9:
		return
	var sn := int(args[0])
	var t0 := float(args[2])
	var ants: Array = []
	var lo := INF
	var hi := -INF
	var side := 0.0
	# a wake only the authority sends (_wake_for): at most max_alive antlions, each run no longer than
	# its reach, so a forged one cannot make every peer trace the ground for miles
	var far := float(p["reach"][1]) + 2.0
	for j in mini((args.size() - 3) / 6, int(p["max_alive"])):
		var o := 3 + j * 6
		var spot := Vector3(float(args[o]), float(args[o + 1]), float(args[o + 2]))
		var land := Vector3(float(args[o + 3]), float(args[o + 4]), float(args[o + 5]))
		if Vector2(land.x - spot.x, land.z - spot.z).length() > far:
			continue
		var a := _plan(sn, j, t0, spot, land)
		ants.append(a)
		for q: Vector3 in [spot, land]:
			var i := path.closest(q, path.index_at(s))
			var at_s := fposmod(path.progress(q, i) - float(p["zone"][0]), path.length)
			lo = minf(lo, at_s)
			hi = maxf(hi, at_s)
			side += signf(path.lateral(q, i))
	if ants.is_empty():
		return
	_wakes[sn] = {"slot": int(args[1]), "t0": t0, "ants": ants, "s_lo": float(p["zone"][0]) + lo,
		"s_hi": float(p["zone"][0]) + hi, "side": signf(side) if side != 0.0 else 1.0, "nodes": {}, "fired": false}
	director.note(self, "warn")
	var mid := Vector3.ZERO
	for a in ants:
		mid += (a["S"] as Vector3) / ants.size()
	play(_snd["rumble"], mid, 6.0, 22.0)
	if director.authority():
		var k := director.kart_at(int(args[1]))
		if k:
			_rearm[k] = _ends(_wakes[sn]) + tm("rearm")


## Antlion j of wake sn: its run from `spot` to `land` as points every metre on the ground (heights
## from the world, the same on every peer), and its timetable.
func _plan(sn: int, j: int, t0: float, spot: Vector3, land: Vector3) -> Dictionary:
	var flat := Vector3(land.x - spot.x, 0.0, land.z - spot.z)
	var d := flat.length()
	var sp := _split(d)
	var dir := flat / d if d > 0.01 else Vector3.FORWARD
	var n := maxi(int(ceil(d)), 1)
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cum := PackedFloat32Array()
	var y := spot.y
	for k in n + 1:
		var u := float(k) / n
		var q := spot.lerp(land, u)
		var g: Array = _ground_at(Vector3(q.x, y if k > 0 else spot.y, q.z), 3.0, 6.0)
		y = float(g[0]) if str(g[1]) != "" else q.y
		pts.append(Vector3(q.x, y, q.z))
		nrm.append(g[2])
		cum.append(d * u)
	var t_dig := t0 + tm("warn") + STAGGER * j
	var t_run := t_dig + DIG_T
	var t_pnc := t_run + sp.y / RUN
	var t_land := t_pnc + POUNCE_T
	var t_in := t_land + LINGER
	return {"S": spot, "P": land, "dir": dir, "pts": pts, "nrm": nrm, "cum": cum, "dig": sp.x, "run": sp.y, "pounce": sp.z,
		"t_dig": t_dig, "t_run": t_run, "t_pnc": t_pnc, "t_land": t_land, "t_in": t_in, "t_gone": t_in + DIGIN_T,
		"skin": int(rnd(sn * 16 + j, 7) * 4.0) % 4}


## Where antlion a is at clock t: [position, phase, seconds into that phase]. Phases: 0 under the
## sand, 1 digging out, 2 running, 3 pouncing, 4 standing, 5 digging in, 6 gone.
static func ant_at(a: Dictionary, t: float) -> Array:
	var d := 0.0
	var ph := 0
	var since := 0.0
	if t < float(a["t_dig"]):
		ph = 0
		since = t - float(a["t_dig"])
	elif t < float(a["t_run"]):
		ph = 1
		since = t - float(a["t_dig"])
		d = float(a["dig"]) * since / DIG_T
	elif t < float(a["t_pnc"]):
		ph = 2
		since = t - float(a["t_run"])
		d = float(a["dig"]) + RUN * since
	elif t < float(a["t_land"]):
		ph = 3
		since = t - float(a["t_pnc"])
		d = float(a["dig"]) + float(a["run"]) + float(a["pounce"]) * since / POUNCE_T
	elif t < float(a["t_in"]):
		ph = 4
		since = t - float(a["t_land"])
		d = float(a["dig"]) + float(a["run"]) + float(a["pounce"])
	elif t < float(a["t_gone"]):
		ph = 5
		since = t - float(a["t_in"])
		d = float(a["dig"]) + float(a["run"]) + float(a["pounce"])
	else:
		ph = 6
		since = t - float(a["t_gone"])
		d = float(a["dig"]) + float(a["run"]) + float(a["pounce"])
	return [_along(a, d), ph, since]


static func _along(a: Dictionary, d: float, key := "pts") -> Vector3:
	var pts: PackedVector3Array = a[key]
	var cum: PackedFloat32Array = a["cum"]
	if pts.size() < 2:
		return pts[0]
	var k := clampi(cum.bsearch(d, true) - 1, 0, pts.size() - 2)
	return pts[k].lerp(pts[k + 1], clampf((d - cum[k]) / maxf(cum[k + 1] - cum[k], 0.001), 0.0, 1.0))


## The slope of the ground under antlion a at clock t (what it leans with).
static func ground_up(a: Dictionary, t: float) -> Vector3:
	var at: Array = ant_at(a, t)
	var pts: PackedVector3Array = a["pts"]
	var d := (Vector2(pts[0].x, pts[0].z) - Vector2((at[0] as Vector3).x, (at[0] as Vector3).z)).length()
	return _along(a, d, "nrm").normalized()


## While a group of its comes for it, the target sees the lock (HUD, bots) if this peer drives it.
func _lock(w: Dictionary, t: float, first: float) -> void:
	var k := director.kart_at(int(w["slot"]))
	if k and not k.remote and k.state == Kart.State.NORMAL:
		k.hazard_lock = maxf(first - t, 0.01)
		var mid := Vector3.ZERO
		for a in w["ants"]:
			mid += (a["S"] as Vector3) / (w["ants"] as Array).size()
		k.hazard_lock_from = mid + Vector3.UP


static func _first_land(w: Dictionary) -> float:
	var f := INF
	for a in w["ants"]:
		f = minf(f, float(a["t_land"]))
	return f


## Karts this peer drives within reach of antlion a's jaws as it lands: spun, pushed along its leap.
func _bite(a: Dictionary, t: float) -> void:
	var at: Vector3 = ant_at(a, t)[0]
	var dir: Vector3 = a["dir"]
	var jaws := at + dir * FRONT * float(p["scale"])
	for k in local_karts():
		# back on the boards (or the road): out of reach
		if not k.offroad:
			continue
		var dv := k.global_position - jaws
		if Vector2(dv.x, dv.z).length() >= HIT_R or absf(dv.y) > 2.5:
			continue
		if hit(k, str(p["effect"]), (dir * float(p["push"]) + k.grav_up * float(p["lift"])) * k.mass * 9.0):
			play(_snd["attack"], jaws, 4.0, 16.0)


func _drop(sn: int) -> void:
	var w: Dictionary = _wakes[sn]
	for n in (w["nodes"] as Dictionary).values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	for e in _pool:
		if (e["busy"] as Array).size() == 2 and int(e["busy"][0]) == sn:
			e["busy"] = []
			(e["node"] as Node3D).visible = false
	_wakes.erase(sn)


func snapshot(t: float) -> Array:
	var out: Array = [p["zone"]]
	var keys := _wakes.keys()
	keys.sort()
	for sn in keys:
		var w: Dictionary = _wakes[sn]
		# a wake past its end is gone (a sleeping peer drops it on its next tick)
		if t > _ends(w) + 0.5:
			continue
		var ants: Array = []
		for a in w["ants"]:
			var at: Array = ant_at(a, t)
			ants.append([(at[0] as Vector3).snapped(Vector3.ONE * 0.01), at[1], (a["S"] as Vector3).snapped(Vector3.ONE * 0.01),
				(a["P"] as Vector3).snapped(Vector3.ONE * 0.01), snappedf(float(a["t_land"]), 0.001)])
		out.append([sn, w["slot"], snappedf(float(w["t0"]), 0.001), ants])
	return out


## Antlions above the sand right now (tests, performance): their positions.
func visible_antlions(t: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for w in _wakes.values():
		for a in w["ants"]:
			var at: Array = ant_at(a, t)
			if int(at[1]) >= 1 and int(at[1]) <= 5:
				out.append(at[0])
	return out


## The side of the road its sand is on (tests): p["side"], or for a zone with sand on both sides the
## first side (right first) with open ground near the road's height in the middle of the zone.
func sand_side() -> int:
	if int(p["side"]) != 0:
		return int(signf(float(p["side"])))
	var zone: Array = p["zone"]
	var at_s := (float(zone[0]) + float(zone[1])) * 0.5
	for sg in [1, -1]:
		var q := road_point(at_s, sg * (half_width(at_s) + 5.0))
		var g: Array = _ground_at(q, 3.0, 4.0)
		if str(g[1]) == "offroad":
			return sg
	return 1


## True while no group is up on the clock (tests).
func idle() -> bool:
	var t := director.clock()
	for w in _wakes.values():
		if t <= _ends(w) + 0.5:
			return false
	return true


## A made-up wake on this zone's sand for the determinism test (no world, no karts): groups of
## three on the zone's sand side, landing 4 m past the road's edge.
func test_event(t0: float, sn := 900) -> Array:
	var zone: Array = p["zone"]
	var side := float(p["side"]) if int(p["side"]) != 0 else 1.0
	var args: Array = [sn, 0, t0]
	for j in 3:
		var at_s := lerpf(float(zone[0]), float(zone[1]), 0.3 + 0.2 * j)
		var i := path.index_at(at_s)
		var land := road_point(at_s, side * (half_width(at_s) + 4.0))
		var away := Vector3(path.right[i].x, 0.0, path.right[i].z).normalized() * side
		var spot := land + away * 10.0 + Vector3(path.fwd[i].x, 0.0, path.fwd[i].z).normalized() * 6.0
		args.append_array([spot.x, spot.y, spot.z, land.x, land.y, land.z])
	return args


# ---------------------------------------------------------------- the look
## Each wake: a mound of sand and a plume of dust at each spot through the warning, a ring on the
## sand where each one lands (pulsing faster as it comes), a burst of sand as each digs out; the
## antlions themselves from the pool (their own animations, or a plain rise and bob without them).
func _show(sn: int, w: Dictionary, t: float) -> void:
	var nodes: Dictionary = w["nodes"]
	var cam := get_viewport().get_camera_3d()
	for j in (w["ants"] as Array).size():
		var a: Dictionary = w["ants"][j]
		var spot: Vector3 = a["S"]
		var land: Vector3 = a["P"]
		var t0 := float(w["t0"])
		var t_dig := float(a["t_dig"])
		var up := Vector3.UP
		# the warning, made when first shown (none for what this peer slept through)
		if t < t_dig + DIG_T * 0.6 and not nodes.has("plume%d" % j):
			nodes["plume%d" % j] = _plume(spot)
			nodes["mound%d" % j] = _mound(spot)
		if t < float(a["t_land"]) and not nodes.has("ring%d" % j):
			# round where its jaws come down (they reach HIT_R from there)
			var jaws: Vector3 = land + (a["dir"] as Vector3) * FRONT * float(p["scale"])
			nodes["ring%d" % j] = Effects.ground_ring(get_parent(), jaws, up, HIT_R, Color(SAND, 0.0))
		var mound: Node3D = nodes.get("mound%d" % j)
		if is_instance_valid(mound):
			var u := clampf((t - t0) / maxf(t_dig - t0, 0.01), 0.0, 1.0)
			mound.visible = t < t_dig + 0.15
			mound.scale = Vector3(0.4 + 1.4 * u, 0.15 + 0.45 * u * (0.85 + 0.15 * sin(t * 30.0)), 0.4 + 1.4 * u)
		var plume: CPUParticles3D = nodes.get("plume%d" % j)
		if is_instance_valid(plume):
			plume.emitting = t < t_dig + DIG_T * 0.6
		var ring: MeshInstance3D = nodes.get("ring%d" % j)
		if is_instance_valid(ring):
			var u := clampf((t - t0) / maxf(float(a["t_land"]) - t0, 0.01), 0.0, 1.0)
			ring.set_instance_shader_parameter("col", Color(1.0, 0.72, 0.35, (0.25 + 0.6 * u) * (0.6 + 0.4 * sin(t * (6.0 + 14.0 * u)))))
			ring.visible = t < float(a["t_land"])
		if crossed(t_dig, t):
			Effects.dust(get_parent(), spot + up * 0.3, 1.6)
			play(_snd["digup"], spot, 4.0, 18.0)
		if crossed(float(a["t_land"]), t):
			Effects.dust(get_parent(), land + up * 0.2, 1.0)
			play(_snd["land"], land, 0.0, 14.0)
		if crossed(float(a["t_pnc"]), t):
			play(_snd["attack"], ant_at(a, t)[0], 2.0, 16.0)
		if crossed(float(a["t_in"]), t):
			play(_snd["digdown"], land, 2.0, 14.0)
		_pose_ant(sn, j, a, t, cam)


## Antlion j of wake sn as it is at clock t, on a pool model while it is above the sand.
func _pose_ant(sn: int, j: int, a: Dictionary, t: float, cam: Camera3D) -> void:
	var at: Array = ant_at(a, t)
	var ph := int(at[1])
	var e := _pool_for(sn, j, int(a["skin"]), ph >= 1 and ph <= 5)
	if e.is_empty():
		return
	var node: Node3D = e["node"]
	var pos: Vector3 = at[0]
	var since := float(at[2])
	var dir: Vector3 = a["dir"]
	var sc := float(p["scale"])
	var yaw := anims.yaw_to(dir) if anims else atan2(dir.x, dir.z) - PI * 0.5
	var sk: Skeleton3D = e["sk"]
	var lift := 0.0
	if ph == 3:
		# an arc over its leap: its own pounce hops 0.6 m over the 8 m it carries, and its legs reach
		# 0.2 m under its feet as it lands; the arc keeps them out of the sand and reads as a leap
		lift = POUNCE_ARC * sin(PI * since / POUNCE_T)
	if anims == null or sk == null:
		# no animations in this content: it rises out of the sand, bobs as it runs, arcs through its leap
		match ph:
			1:
				lift = -1.7 * (1.0 - since / DIG_T)
			2:
				lift = absf(sin(since * 18.0)) * 0.12
			3:
				lift = 1.3 * sin(PI * since / POUNCE_T)
			5:
				lift = -1.9 * since / DIGIN_T
	# leaning with the slope under it, a little more upright than the ground (as the houndeyes stand)
	var lean := Vector3.UP.lerp(ground_up(a, t), 0.85).normalized()
	node.global_transform = Transform3D((Basis(Quaternion(Vector3.UP, lean)) * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * sc),
		pos + Vector3.UP * lift)
	if anims == null or sk == null:
		return
	var near := cam != null and cam.global_position.distance_to(pos) < POSE_NEAR
	if not AnimSet.due(node, t, 0.0 if near else 15.0):
		return
	match ph:
		1:
			anims.pose(sk, "digout", since * DIG_RATE, 1.0, AnimSet.CLAMP)
		2:
			anims.pose(sk, "run", since * RUN / maxf(anims.speed("run") * sc, 0.1), 1.0, AnimSet.LOOP)
		3:
			anims.pose(sk, "pounce", since / POUNCE_T * POUNCE_LEN, 1.0, AnimSet.CLAMP)
		4:
			anims.pose(sk, "attack", since, 1.0, AnimSet.CLAMP)
		5:
			anims.pose(sk, "digin", since * DIGIN_RATE, 1.0, AnimSet.CLAMP)


## The pool model showing antlion j of wake sn ({} when it is under the sand, or none is free).
func _pool_for(sn: int, j: int, skin: int, show: bool) -> Dictionary:
	var mine := {}
	for e in _pool:
		var b: Array = e["busy"]
		if b.size() == 2 and int(b[0]) == sn and int(b[1]) == j:
			mine = e
	if not show:
		if not mine.is_empty():
			mine["busy"] = []
			(mine["node"] as Node3D).visible = false
		return {}
	if mine.is_empty():
		# a free one, of its own skin if there is one
		for e in _pool:
			if (e["busy"] as Array).is_empty() and (mine.is_empty() or int(e["skin"]) == skin):
				mine = e
				if int(e["skin"]) == skin:
					break
		if mine.is_empty():
			return {}
		mine["busy"] = [sn, j]
		(mine["node"] as Node3D).visible = true
	return mine


## A plume of sand dust rising where one is about to dig out.
func _plume(at: Vector3) -> CPUParticles3D:
	var pl := CPUParticles3D.new()
	pl.amount = 16
	pl.lifetime = 1.2
	pl.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	q.material = Effects.sprite("particle/smokesprites_0001", false, Color(SAND, 0.6))
	pl.mesh = q
	pl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pl.emission_sphere_radius = 0.9
	pl.direction = Vector3.UP
	pl.spread = 25.0
	pl.gravity = Vector3(0.0, 0.4, 0.0)
	pl.initial_velocity_min = 1.2
	pl.initial_velocity_max = 3.2
	pl.scale_amount_min = 0.6
	pl.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	pl.color_ramp = g
	get_parent().add_child(pl)
	pl.global_position = at + Vector3.UP * 0.2
	return pl


## The bulge of sand over one about to dig out: a flattened dome of the beach's own sand.
func _mound(at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mound_material(track)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = at
	return mi


## The mounds' material: the track's sand layer, or the beach sand (kept for the session).
static func mound_material(trk: Track) -> StandardMaterial3D:
	if _mound_mat == null:
		_mound_mat = StandardMaterial3D.new()
		var own: Dictionary = trk.data.get("terrain_layers", {}) if trk else {}
		var tex := str(own.get("sand", ""))
		for m in ["nature/blendsandsand008b", "nature/sandfloor010a", "nature/blendcliffsand01a"]:
			if tex == "":
				tex = str((Game.materials_db.get(m, {}) as Dictionary).get("albedo", ""))
		if tex != "":
			_mound_mat.albedo_texture = SourceMaterials.tex(tex)
			_mound_mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
		_mound_mat.albedo_color = Color(1.0, 0.95, 0.88) if tex != "" else SAND
	return _mound_mat


## The hill's own sounds while it is awake: its ambience, and now and then a chirp from one up.
func _sounds(t: float, dt: float) -> void:
	if _ambient and not _ambient.playing:
		_ambient.play()
	if _wakes.is_empty():
		return
	_idle_t -= dt
	if _idle_t <= 0.0:
		_idle_t = 1.2 + rnd(int(t * 4.0), 9) * 1.6
		var up := visible_antlions(t)
		if not up.is_empty():
			play(_snd["idle"], up[int(rnd(int(t), 11) * up.size()) % up.size()], 0.0, 14.0)


## The thumpers thump on the clock: their own animation (its beat stretched to p["thumper_every"]),
## and as each blow lands a thud and a ring of dust.
func _thump(t: float) -> void:
	var every := float(p["thumper_every"])
	var blow := every * THUMP_AT
	for k in _thumper_nodes.size():
		var e: Array = _thumper_nodes[k]
		var at := _thumpers[k]
		var tset: AnimSet = e[2]
		if tset and e[1] and AnimSet.due(e[0], t, 20.0):
			tset.pose(e[1], "idle", fposmod(t, every) * tset.length("idle") / every)
		if _last_t > -1e8 and floor((t - blow) / every) != floor((_last_t - blow) / every):
			play(_snd["thump"], at, 4.0, 30.0)
			Effects.shock_ring(get_parent(), at + Vector3.UP * 0.1, Vector3.UP, 9.0, Color(SAND, 0.7), 0.6)


## Clock times of the thumpers' blows from a to b (tests): the same on every peer.
func thumps(a: float, b: float) -> Array[float]:
	var out: Array[float] = []
	if _thumpers.is_empty():
		return out
	var every := float(p["thumper_every"])
	var k := ceilf((a - every * THUMP_AT) / every)
	while k * every + every * THUMP_AT <= b:
		out.append(k * every + every * THUMP_AT)
		k += 1.0
	return out


func wake() -> void:
	if _ambient:
		_ambient.play()


## Nobody near: what it shows goes (made again from the clock when it wakes); the antlions under it.
func sleep() -> void:
	if _ambient:
		_ambient.stop()
	for w in _wakes.values():
		for n in (w["nodes"] as Dictionary).values():
			if is_instance_valid(n):
				(n as Node).queue_free()
		(w["nodes"] as Dictionary).clear()
	for e in _pool:
		e["busy"] = []
		(e["node"] as Node3D).visible = false


## Bots: to the far side of the road while a group is up beside the stretch they come to.
func advice(_k: Kart, at_s: float, _speed: float) -> Dictionary:
	var t := director.clock()
	for w in _wakes.values():
		if t > _first_land(w) + 1.5 or t < float(w["t0"]):
			continue
		if not director.in_span(at_s, float(w["s_lo"]) - 45.0, float(w["s_hi"]) + 5.0):
			continue
		return {"lat": -float(w["side"]) * (half_width(at_s) - 2.0), "w": 0.75}
	return {}


func is_active(t: float) -> bool:
	for w in _wakes.values():
		if t >= float(w["t0"]) and t < _ends(w):
			return true
	return false


func spawns() -> Array:
	return []
