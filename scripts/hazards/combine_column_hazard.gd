class_name CombineColumnHazard
extends Hazard
## A column of Combine soldiers marching across a bridge over the lap (stage D6, the White Forest
## forest: HL2's column of soldiers marching over the bridge). Two abreast, in step, they march to
## and fro along the deck the track gives (p["deck"]: the walkway's centre line, world points where
## their boots stand, laid by tools/hazards.py). Each time the column comes to a post over the road
## (one over each stretch of the lap the deck crosses) it halts on its leader's signal, turns to the
## road and stands watch; then it marches on to the end of the deck, about-faces and comes back the
## same way. Where it is, which way each soldier faces and
## every step are a function of the shared hazard clock and the seed: the same on every peer with
## no network traffic.
##
## With p["edge"] (metres from the deck's line to the inside of its railing) the soldiers step up to the
## railing on the road's side once they have turned to it, in one line along it, and step back into
## column before they march on: from the road below, a soldier in the middle of a deck high overhead is
## hidden by its edge.
##
## While it stands watch at a post the road under and before the bridge there (the post's zone: p["zone"],
## or each of p["posts"] where the lap passes under the deck more than once) is a danger zone. Where
## the karts will be is only known to the peer that sees them all, so the fire is one server event
## per burst: the authority (the server, or the offline game) looks at the karts coming into the
## zone and, finding some, sends one "burst" event naming the clock time the warning starts and up
## to p["strips"] strips of road, each where a kart will be when the fire lands if it holds its line
## and speed. From the event on, everything runs on the shared clock on every peer: the strips are
## painted red on the road, the soldiers raise their rifles at them, red laser sights sweep them and
## the radio calls contact; p["warn"] seconds later (at least 1.2 s on NORMAL) they fire, tracers
## land all over each strip for p["fire"] seconds and a kart this peer drives that is in a strip then
## spins. A kart that changes lane or speed in the warning is out of it; a burst always leaves a
## lane clear (p["free"]). One burst per p["cool"] seconds at most (EASY waits longer and warns
## longer). The column never stands on a road (the deck lies off every road or well over it: the
## lint of tools/hazards.py checks it) and has no collision, so it never stops a kart.
##
## Visual only, never on a dedicated server: the soldiers (their own HL2 animations from
## assets/models/combine_soldier.anims.json, or a standing pose where the content has none), their
## rifles, the marks, the lasers, tracers, the boots and gear in time with their steps, the radio.
## The soldiers far from the camera are posed at most every other frame (AnimSet.due).

enum Seg { WALK, WATCH, END }

const LASER := Color(1.0, 0.08, 0.05, 0.75)
const MARK := Color(1.0, 0.12, 0.06, 0.8)
const TRACER := Color(0.6, 0.85, 1.0)
const T_FACE := 1.0          # seconds they take to turn from the march to the road and back
const T_TURN := 1.0          # seconds of an about-face
const T_STEP := 2.0          # seconds they take to step up to the railing at a watch (p["edge"]) and back
const STEP_LEN := 3.0        # about the metres of that step (its march in step with it)
const RAIL_GAP := 0.45       # metres from the railing a soldier stands at it
const CURTAIN := 0.9         # metres a strip's red glow rises from the road at its edges
const LEAD := 0.35           # seconds from the authority's decision to the warning: a client hears of it first
const AFTER := 0.6           # seconds they hold their aim after the fire
const AIM_IN := 0.25         # seconds to raise the rifles once warned
const AIM_OUT := 0.4         # seconds to lower them again
const BLEND := 0.35          # seconds a walk blends in from a halt and out into the next one
## march phases (share of a_WalkN's cycle) at which a boot lands: the left foot at frame 7 of 30, the
## right at frame 22
const STEPS := [0.24, 0.74]
const KART_R := 1.0          # metres a kart reaches past its centre in a strip
const POSE_NEAR := 35.0      # metres from the camera within which they are posed every frame
const POSE_MID := 120.0      # ... every other frame within this, a few times a second further out
const HEADROOM := 4.5        # metres over a road below which a deck point counts as standing on it (tests)

var anims: AnimSet
var _deck := PackedVector3Array()
var _cum := PackedFloat32Array()     # metres along the deck at each point
var _len := 0.0
var _n := 12                         # soldiers
var _rows := 6
var _ua := 0.0                       # deck metres of the column's middle at its two ends
var _ub := 0.0
var _post := 0.0                     # ... where it stands watch first (the first post)
## its watch posts in deck order: {"u": deck metres of the column's middle, "z0", "z1": the zone it watches
## from there, "watch": the road point the soldiers face}
var _posts: Array = []
# the timetable: one cycle of segments, from the A end out and back
var _seg_t := PackedFloat32Array()   # start (seconds into the cycle)
var _seg_d := PackedFloat32Array()   # duration
var _seg_k := PackedInt32Array()     # Seg
var _seg_u0 := PackedFloat32Array()  # column middle at its start / end (deck metres)
var _seg_u1 := PackedFloat32Array()
var _seg_dir := PackedFloat32Array() # the way they face along the deck (+1 towards its end)
var _seg_w := PackedFloat32Array()   # metres walked in the cycle before the segment
var _seg_post := PackedInt32Array()  # the post a watch stands at (-1 for a walk or an end)
var _cycle := 1.0
var _walk_cycle := 0.0               # metres walked in a cycle
var _phase0 := 0.0
var _move := 1.8246                  # metres a march cycle carries a soldier (a_WalkN at its own size)
## serial -> {"sn", "t_w", "t_f", "end", "strips": [{"slot", "s", "lat", "s0", "s1", "lat0", "lat1"}], "warned",
## "fired", "nodes": [MeshInstance3D], "from": where the HUD lock points}
var _bursts := {}
var _order: Array[int] = []
var _serial := 0                     # the authority's next burst serial
var _sending := -1                   # the serial the authority is sending now (its own event)
var _ready_at := -INF                # the authority's next burst no sooner than this
var _hits0 := {}                     # a client's kart -> its net_hits when a burst was last aimed at it (authority)
## the authority's bursts and the karts they aimed at (tests, tuning)
var stats := {"bursts": 0, "strips": 0}
var _men: Array = []                 # [{"node", "sk", "elite", "rifle", "muzzle", "glow", "laser", "spine", "flash"}]
var _muzzle_m := Vector3(-0.003, 0.092, -0.253)   # the rifle's muzzle, its model space
var _march_loop: AudioStreamPlayer3D
var _last_step := 0
var _stepped := false                # _last_step holds the step of the tick before
var _snd := {}
static var _mark_mat: ShaderMaterial


func defaults() -> Dictionary:
	return {"deck": [], "zone": [s - 70.0, s + 10.0], "post": -1.0, "posts": [], "count": 12, "elites": 2,
		"model": "combine_soldier", "elite_model": "combine_super_soldier", "rifle": "weapons/w_irifle", "scale": 1.0,
		"pitch": 1.5, "abreast": 1.0, "speed": 1.8, "watch": 24.0, "pause": 4.0, "phase": -1.0, "edge": -1.0,
		"warn": 1.6, "fire": 0.7, "cool": 2.5, "lookout": 90.0, "strips": 2, "strip_len": 9.0, "strip_w": 4.0,
		"free": 4.0, "shots": 12, "effect": "spin", "push": 0.3, "range": 110.0}


func build() -> void:
	aims_all = true
	_n = clampi(int(p["count"]), 1, 24)
	_rows = ceili(_n / 2.0)
	_deck_setup()
	_timetable()
	_snd["step"] = sounds([["npc/footsteps/hardboot_generic1.wav", "npc/footsteps/hardboot_generic2.wav",
		"npc/footsteps/hardboot_generic3.wav", "npc/footsteps/hardboot_generic4.wav", "npc/footsteps/hardboot_generic5.wav",
		"npc/footsteps/hardboot_generic6.wav", "npc/footsteps/hardboot_generic8.wav"], ["npc/strider/strider_step1.wav"]])
	_snd["gear"] = sounds([["npc/combine_soldier/gear1.wav", "npc/combine_soldier/gear2.wav", "npc/combine_soldier/gear3.wav",
		"npc/combine_soldier/gear4.wav", "npc/combine_soldier/gear5.wav", "npc/combine_soldier/gear6.wav"]])
	_snd["on"] = sounds([["npc/combine_soldier/vo/on1.wav", "npc/combine_soldier/vo/on2.wav"]])
	_snd["off"] = sounds([["npc/combine_soldier/vo/off1.wav", "npc/combine_soldier/vo/off2.wav", "npc/combine_soldier/vo/off3.wav"]])
	_snd["halt"] = sounds([["npc/combine_soldier/vo/stayalert.wav", "npc/combine_soldier/vo/gosharp.wav",
		"npc/combine_soldier/vo/sectorisnotsecure.wav"], ["npc/combine_soldier/vo/contact.wav"]])
	_snd["turn"] = sounds([["npc/combine_soldier/vo/copy.wav", "npc/combine_soldier/vo/affirmative.wav",
		"npc/combine_soldier/vo/movein.wav"]])
	_snd["contact"] = sounds([["npc/combine_soldier/vo/contact.wav", "npc/combine_soldier/vo/engaging.wav",
		"npc/combine_soldier/vo/prepforcontact.wav", "npc/combine_soldier/vo/readyweapons.wav"]])
	_snd["fire"] = sounds([["weapons/ar2/fire1.wav"], ["weapons/irifle/irifle_fire2.wav"]])
	_snd["ric"] = sounds(TurretHazard.RICOCHETS)
	if not visual:
		return
	var key := pick_model([str(p["model"]), "combine_soldier", "combine_soldier_prisonguard"])
	if key == "":
		return
	var elite_key := pick_model([str(p["elite_model"]), "combine_super_soldier", key])
	anims = AnimSet.of("combine_soldier")
	if anims and anims.has("march"):
		_move = maxf(anims.move("march"), 0.5)
	var mz := HazardRig.attachment(str(p["rifle"]), "muzzle")
	if not mz.is_empty():
		_muzzle_m = mz[0]
	var rifle_key := pick_model([str(p["rifle"])])
	var sc := float(p["scale"])
	for j in _n:
		var elite := _is_elite(j)
		var node := Game.spawn_model(elite_key if elite else key)
		add_child(node)
		node.top_level = true
		node.scale = Vector3.ONE * sc
		var sk := AnimSet.skeleton(node)
		var man := {"node": node, "sk": sk, "elite": elite, "rifle": null, "glow": null, "laser": null, "spine": -1,
			"axis": Vector3.BACK, "flash": -1.0, "idle_t": rnd(j, 9) * 11.0}
		if sk:
			man["spine"] = HazardRig.bone(sk, "ValveBiped.Bip01_Spine2")
			if anims != null:
				man["axis"] = _pitch_axis(node, sk, int(man["spine"]))
			else:
				# no animations in this content: a relaxed standing pose instead of the reference pose
				BipedPose.standing(sk)
			var hand := HazardRig.bone(sk, "ValveBiped.Bip01_R_Hand")
			if rifle_key != "" and hand >= 0 and anims != null:
				man["rifle"] = _hold_rifle(sk, hand, rifle_key)
		var g := glow("materials/effects/combinemuzzle2.png", 0.7, Color(0.7, 0.9, 1.0))
		g.top_level = true
		g.visible = false
		man["glow"] = g
		var b := Effects.beam_node(LASER, 0.035, "materials/sprites/laserbeam.png", true)
		add_child(b)
		b.visible = false
		man["laser"] = b
		_men.append(man)
	_march_loop = loop(["ambient/levels/streetwar/marching_distant1.wav", "ambient/levels/streetwar/marching_distant2.wav"],
		self, 30.0, -6.0)
	_place(0.0)


## The body's side (the animations face the model's +X, so its side is +Z) in the frame of the bone above
## the spine bone bi as the aim pose holds it: the chest pitches about it towards the road.
func _pitch_axis(node: Node3D, sk: Skeleton3D, bi: int) -> Vector3:
	var par := sk.get_bone_parent(bi) if bi >= 0 else -1
	if par < 0:
		return Vector3.BACK
	anims.pose(sk, "aim", 0.0)
	var side := HazardRig.model_to_skeleton(node, sk).basis * Vector3(0.0, 0.0, 1.0)
	return (sk.get_bone_global_pose(par).basis.inverse() * side).normalized()


## The AR2 in the soldier's right hand: Source bone-merges a weapon by its own copy of the hand
## bone, so the rifle hangs on the hand at the inverse of its hand bone's rest.
func _hold_rifle(sk: Skeleton3D, hand: int, key: String) -> Node3D:
	var rifle := Game.spawn_model(key)
	var rsk := AnimSet.skeleton(rifle)
	var grip := Transform3D.IDENTITY
	if rsk:
		var rb := HazardRig.bone(rsk, "ValveBiped.Bip01_R_Hand")
		if rb >= 0:
			grip = HazardRig.model_to_skeleton(rifle, rsk).affine_inverse() * rsk.get_bone_global_rest(rb)
	var at := BoneAttachment3D.new()
	at.bone_name = sk.get_bone_name(hand)
	sk.add_child(at)
	at.add_child(rifle)
	rifle.transform = grip.affine_inverse()
	return rifle


## The head and the tail of the column are elites (p["elites"] of them: the first and last soldier,
## then the other file of the first and last row).
func _is_elite(j: int) -> bool:
	var e := clampi(int(p["elites"]), 0, _n)
	var order := [0, _n - 1, 1, _n - 2]
	for k in mini(e, order.size()):
		if order[k] == j:
			return true
	return false


# ---------------------------------------------------------------- the deck and the timetable (pure)
func _deck_setup() -> void:
	for q in p["deck"]:
		if q is Array and (q as Array).size() >= 3:
			_deck.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if _deck.size() < 2:
		# no deck in the data: they stand where the hazard was placed
		_deck = PackedVector3Array([position, position + Vector3(0.0, 0.0, 0.01)])
	_cum.resize(_deck.size())
	_cum[0] = 0.0
	for i in range(1, _deck.size()):
		_cum[i] = _cum[i - 1] + _deck[i].distance_to(_deck[i - 1])
	_len = _cum[_cum.size() - 1]
	var half := (_rows - 1) * float(p["pitch"]) * 0.5
	_ua = half + 1.0
	_ub = _len - half - 1.0
	if _ub < _ua:
		_ua = _len * 0.5
		_ub = _ua
	# its posts: p["posts"] ([deck metres, zone start, zone end] each, tools/hazards.py), or the one at
	# p["post"] over p["zone"] (-1: where the deck passes nearest over the lap at s)
	var list: Array = []
	for q in p["posts"]:
		if q is Array and (q as Array).size() >= 3:
			list.append([float(q[0]), float(q[1]), float(q[2])])
	if list.is_empty():
		var zone: Array = p["zone"]
		list.append([float(p["post"]) if float(p["post"]) >= 0.0 else _nearest(road_point(s, 0.0)), float(zone[0]),
			float(zone[1])])
	list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for q in list:
		var z0 := float(q[1])
		var z1 := float(q[2])
		_posts.append({"u": clampf(float(q[0]), _ua, _ub), "z0": z0, "z1": z1,
			"watch": road_point(z0 + ahead(z0, z1) * 0.5, 0.0, 0.5)})
	_post = float(_posts[0]["u"])
	# the camera wakes it from anywhere near its first post
	position = _deck_point(_post)


## Deck metres of the deck's point nearest c in plan.
func _nearest(c: Vector3) -> float:
	var best := INF
	var out := 0.0
	for k in 200:
		var u := _len * k / 199.0
		var q := _deck_point(u)
		var d := Vector2(q.x - c.x, q.z - c.z).length()
		if d < best:
			best = d
			out = u
	return out


## The column's cycle: from its A end (the deck's first point) out to each post in turn and a watch
## there, on to the B end, about-face, back through the posts (a watch at each) to A, about-face.
func _timetable() -> void:
	var v := maxf(float(p["speed"]), 0.2)
	var W := maxf(float(p["watch"]), T_FACE * 2.0 + 1.0)
	var P := maxf(float(p["pause"]), T_TURN + 0.5)
	# [kind, from, to, the way it faces, post]
	var legs := []
	var at_u := _ua
	for i in _posts.size():
		var u := float(_posts[i]["u"])
		legs.append([Seg.WALK, at_u, u, 1.0, -1])
		legs.append([Seg.WATCH, u, u, 1.0, i])
		at_u = u
	legs.append([Seg.WALK, at_u, _ub, 1.0, -1])
	legs.append([Seg.END, _ub, _ub, 1.0, -1])
	at_u = _ub
	for i in range(_posts.size() - 1, -1, -1):
		var u := float(_posts[i]["u"])
		legs.append([Seg.WALK, at_u, u, -1.0, -1])
		legs.append([Seg.WATCH, u, u, -1.0, i])
		at_u = u
	legs.append([Seg.WALK, at_u, _ua, -1.0, -1])
	legs.append([Seg.END, _ua, _ua, -1.0, -1])
	var at := 0.0
	var walked := 0.0
	for g in legs:
		var d := 0.0
		match int(g[0]):
			Seg.WALK:
				d = absf(float(g[2]) - float(g[1])) / v
			Seg.WATCH:
				d = W
			Seg.END:
				d = P
		_seg_t.append(at)
		_seg_d.append(d)
		_seg_k.append(int(g[0]))
		_seg_u0.append(float(g[1]))
		_seg_u1.append(float(g[2]))
		_seg_dir.append(float(g[3]))
		_seg_post.append(int(g[4]))
		_seg_w.append(walked)
		at += d
		if int(g[0]) == Seg.WALK:
			walked += absf(float(g[2]) - float(g[1]))
	_cycle = maxf(at, 1.0)
	_walk_cycle = walked
	_phase0 = float(p["phase"]) if float(p["phase"]) >= 0.0 else rnd(1, 1) * _cycle


## The column at clock t: [middle (deck metres), the way it faces (+1 / -1), Seg, seconds into the
## segment, its length, metres walked since clock 0 (the march's phase), segment index, clock its
## segment began, the post it watches from (-1 while it marches or turns)].
func march_at(t: float) -> Array:
	var tt := t + _phase0
	var n := floorf(tt / _cycle)
	var u := tt - n * _cycle
	var j := _seg_t.size() - 1
	for i in _seg_t.size():
		if u < _seg_t[i] + _seg_d[i]:
			j = i
			break
	var since := clampf(u - _seg_t[j], 0.0, _seg_d[j])
	var mid := _seg_u0[j]
	var walked := n * _walk_cycle + _seg_w[j]
	if _seg_k[j] == Seg.WALK and _seg_d[j] > 0.0:
		var f := since / _seg_d[j]
		mid = lerpf(_seg_u0[j], _seg_u1[j], f)
		walked += absf(_seg_u1[j] - _seg_u0[j]) * f
	return [mid, _seg_dir[j], _seg_k[j], since, _seg_d[j], walked, j, t - since, _seg_post[j]]


## [start, end] (clock) of the watch the column stands at clock t, or [] while it marches or turns.
func watch_window(t: float) -> Array:
	var m := march_at(t)
	if int(m[2]) != Seg.WATCH:
		return []
	return [float(m[7]), float(m[7]) + float(m[4])]


## [start, end] (lap metres) of the zone the column watches at clock t, [] while it marches or turns.
func zone_at(t: float) -> Array:
	var m := march_at(t)
	if int(m[8]) < 0:
		return []
	var q: Dictionary = _posts[int(m[8])]
	return [float(q["z0"]), float(q["z1"])]


## The next watch that begins at or after clock t: [start, end] (tests, the determinism check).
func next_watch(t: float) -> Array:
	for k in 3:
		var base := floorf((t + _phase0) / _cycle) + k
		for i in _seg_t.size():
			if _seg_k[i] != Seg.WATCH:
				continue
			var w0 := base * _cycle + _seg_t[i] - _phase0
			if w0 >= t:
				return [w0, w0 + _seg_d[i]]
	return [t, t]


func _deck_point(u: float) -> Vector3:
	var j := clampi(_cum.bsearch(u, true) - 1, 0, _deck.size() - 2)
	var seg := maxf(_cum[j + 1] - _cum[j], 0.001)
	return _deck[j].lerp(_deck[j + 1], clampf((u - _cum[j]) / seg, 0.0, 1.0))


## Deck metres and metres right of the deck's line of soldier j with the column's middle at mid.
func _slot(j: int, mid: float) -> Vector2:
	var r := j / 2
	var f := j % 2
	var u := mid + (r - (_rows - 1) * 0.5) * float(p["pitch"])
	return Vector2(clampf(u, 0.0, _len), (f - 0.5) * float(p["abreast"]))


static func _angle(d: Vector3) -> float:
	return atan2(d.x, d.z)


static func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


## Soldier j at clock t: [where its boots stand, the angle it faces (atan2 of the direction, x over
## z), how far its rifle is up (0..1)]. A function of the clock and the bursts heard of.
func soldier_at(j: int, t: float, at: Array = [], burst = null) -> Array:
	var m := at if not at.is_empty() else march_at(t)
	var sl := _slot(j, float(m[0]))
	var seg := clampi(_cum.bsearch(sl.x, true) - 1, 0, _deck.size() - 2)
	var dd := _deck[seg + 1] - _deck[seg]
	dd.y = 0.0
	dd = dd.normalized() if dd.length_squared() > 0.000001 else Vector3.FORWARD
	var pos := _deck[seg].lerp(_deck[seg + 1], clampf((sl.x - _cum[seg]) / maxf(_cum[seg + 1] - _cum[seg], 0.001), 0.0, 1.0)) \
		+ Vector3(-dd.z, 0.0, dd.x) * sl.y
	var dir := float(m[1])
	var march := _angle(dd * dir)
	var a := march
	var since := float(m[3])
	var dur := float(m[4])
	match int(m[2]):
		Seg.WATCH:
			var w: Vector3 = _posts[int(m[8])]["watch"] - pos
			var wa := _angle(Vector3(w.x, 0.0, w.z))
			var into := _ease(since / T_FACE) * (1.0 - _ease((since - (dur - T_FACE)) / T_FACE))
			a = lerp_angle(march, wa, into)
			pos += _step_off(j, int(m[8]), dd, sl.y) * step_share(since, dur)
		Seg.END:
			# an about-face in the middle of the halt, each soldier a moment apart
			var t0 := dur * 0.5 - T_TURN * 0.5 + (rnd(j, 7) - 0.5) * 0.3
			a = march + PI * _ease((since - t0) / T_TURN)
	var up := 0.0
	var b: Dictionary = burst if burst is Dictionary else _burst_at(t)
	if not b.is_empty():
		up = _ease((t - float(b["t_w"]) + 0.1) / AIM_IN) * (1.0 - _ease((t - float(b["end"]) - AFTER) / AIM_OUT))
		if up > 0.0:
			var aim := aim_point(b, j, t) - pos
			a = lerp_angle(a, _angle(Vector3(aim.x, 0.0, aim.z)), up)
	return [pos, a, up]


## How far (0..1) the soldiers have stepped up to the railing `since` seconds into a watch `dur` long:
## once they have turned to the road, and back before they turn to march on (0 without p["edge"]).
func step_share(since: float, dur: float) -> float:
	if float(p["edge"]) <= 0.0:
		return 0.0
	return _ease((since - T_FACE) / T_STEP) * (1.0 - _ease((since - (dur - T_FACE - T_STEP)) / T_STEP))


## The step soldier j takes from its place in the column (lat metres right of the deck's line, which
## runs along dd there) to its place at the railing on the side of post q's road: one line along the
## railing, the rear file in the front file's gaps.
func _step_off(j: int, q: int, dd: Vector3, lat: float) -> Vector3:
	var right := Vector3(-dd.z, 0.0, dd.x)
	var w: Vector3 = _posts[q]["watch"] - _deck_point(float(_posts[q]["u"]))
	var side := 1.0 if w.dot(right) >= 0.0 else -1.0
	var front := signf(lat) == side
	var to := side * (float(p["edge"]) - RAIL_GAP)
	return right * (to - lat) + dd * (float(p["pitch"]) * 0.25 * (-1.0 if front else 1.0))


## The burst whose warning, fire or hold covers clock t (the latest one), {} for none.
func _burst_at(t: float) -> Dictionary:
	for k in range(_order.size() - 1, -1, -1):
		var b: Dictionary = _bursts[_order[k]]
		if t >= float(b["t_w"]) - 0.15 and t <= float(b["end"]) + AFTER + AIM_OUT:
			return b
	return {}


## Where soldier j's rifle points in burst b at clock t: a spot on its strip that its laser sweeps.
func aim_point(b: Dictionary, j: int, t: float) -> Vector3:
	var strips: Array = b["strips"]
	var st: Dictionary = strips[j % strips.size()]
	var tau := t - float(b["t_w"])
	var along := sin(tau * 1.4 + j * 1.7) * float(p["strip_len"]) * 0.35
	var across := sin(tau * 1.9 + j * 0.9) * float(p["strip_w"]) * 0.3
	return road_point(float(st["s"]) + along, float(st["lat"]) + across, 0.05)


## Shot k on strip `which` of burst b: [clock time, impact point].
func shot(b: Dictionary, which: int, k: int) -> Array:
	var st: Dictionary = (b["strips"] as Array)[which]
	var n := maxi(int(p["shots"]), 1)
	var sn := int(b["sn"])
	var at_s := float(st["s0"]) + rnd(sn * 7 + which, 100 + k) * (float(st["s1"]) - float(st["s0"]))
	var lat := float(st["lat0"]) + rnd(sn * 7 + which, 200 + k) * (float(st["lat1"]) - float(st["lat0"]))
	return [float(b["t_f"]) + (k + 0.5) / n * tm_fire(), road_point(at_s, lat, 0.05)]


func tm_fire() -> float:
	return float(p["fire"])


func strip_count() -> int:
	return clampi(int(p["strips"]), 1, 3)


## True when a burst warned at t_w fits the watch it falls in: the column halted and facing the road
## (and up at the railing) from before the warning until it has lowered its rifles again.
func fits_watch(t_w: float) -> bool:
	var w := watch_window(t_w)
	if w.is_empty():
		return false
	var end := t_w + tm("warn") + tm_fire() + AFTER + AIM_OUT
	return t_w >= float(w[0]) + settle() and end <= float(w[1]) - settle()


## Seconds into a watch before a burst may warn, and before its end after which none may still be
## firing: turned to the road (and up at the railing with p["edge"]).
func settle() -> float:
	return T_FACE + (T_STEP if float(p["edge"]) > 0.0 else 0.0)


# ---------------------------------------------------------------- tick
func tick(t: float, dt: float) -> void:
	if t >= 0.0 and director.authority() and t >= _ready_at and fits_watch(t + LEAD):
		_hunt(t)
	for sn in _order.duplicate():
		var b: Dictionary = _bursts[sn]
		if t > float(b["end"]) + AFTER + AIM_OUT + 1.0:
			_drop(sn)
			continue
		_burst_tick(b, t)
	if visual:
		_place(t)
		_sounds(t)


## The authority looks for karts coming into the zone and, finding some, sends one burst at them.
func _hunt(t: float) -> void:
	var zone := zone_at(t + LEAD)
	if zone.is_empty():
		return
	var z0 := float(zone[0])
	var z1 := float(zone[1])
	var half := float(p["strip_len"]) * 0.5
	var t_w := t + LEAD
	var t_f := t_w + tm("warn")
	var sn := _serial
	# where this burst's strips may begin: a little further into the zone each time, so they do not
	# always land at its start
	var room := maxf(ahead(z0, z1) - 2.0 * half, 0.0)
	var from := z0 + half + rnd(sn, 3) * room * 0.6
	var cands := []
	for k in all_karts():
		var inside := k.route < 0 and director.in_span(k.lap_progress, z0 - float(p["lookout"]), z1)
		# a client's kart: the server does not see its immunity, only the hits its owner reports; one
		# since it was last aimed at is left alone until it is out of the zone
		if k.remote and _hits0.has(k):
			if not inside:
				_hits0.erase(k)
			elif k.net_hits > int(_hits0[k]):
				continue
		if not inside or not targetable(k):
			continue
		var v := k.linear_velocity.dot(path.fwd[path.wi(k.path_index)])
		if v < 4.0:
			continue
		# (from total_progress: on the server a client's kart dead-reckons it from its owner's last state,
		# its lap_progress is that state's, a latency behind: the strip landed behind the kart)
		var at := fposmod(k.total_progress + v * (t_f - t), path.length)
		if not director.in_span(at, z0 + half, z1 - half):
			continue
		var hw := half_width(at) - float(p["strip_w"]) * 0.5 - 0.3
		cands.append([ahead(z0, at), k, at, clampf(kart_lat(k), -maxf(hw, 0.0), maxf(hw, 0.0))])
	# the karts furthest into the zone first; a burst goes once the first of them is past `from` (the
	# others it takes wherever they will be in the zone)
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	if cands.is_empty() or not director.in_span(float(cands[0][2]), from, z1 - half):
		return
	var picked := []
	for c in cands:
		if picked.size() >= strip_count():
			break
		if _fits(picked, float(c[2]), float(c[3])):
			picked.append(c)
	var args: Array = [sn, t_w, picked.size()]
	for c in picked:
		var k: Kart = c[1]
		args.append_array([director.slot_of(k), float(c[2]), float(c[3])])
		if k.remote:
			_hits0[k] = k.net_hits
	_serial += 1
	stats["bursts"] = int(stats["bursts"]) + 1
	stats["strips"] = int(stats["strips"]) + picked.size()
	_ready_at = t_f + tm_fire() + tm("cool")
	_sending = sn
	send("burst", args)
	_sending = -1


## A strip at (at, lat) can join the ones picked: it does not overlap one, and where it lies beside
## one (their stretches overlap) the road keeps a lane at least p["free"] metres wide clear.
func _fits(picked: Array, at: float, lat: float) -> bool:
	var L := float(p["strip_len"])
	var w := float(p["strip_w"]) * 0.5
	var spans := [Vector2(lat - w, lat + w)]
	for c in picked:
		var d := absf(wrapf(float(c[2]) - at, -path.length * 0.5, path.length * 0.5))
		if d >= L + 2.0:
			continue
		if absf(float(c[3]) - lat) < 2.0 * w + 0.5:
			return false
		spans.append(Vector2(float(c[3]) - w, float(c[3]) + w))
	if spans.size() == 1:
		return true
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var hw := half_width(at)
	var edge := -hw
	var best := 0.0
	for sp in spans:
		best = maxf(best, sp.x - edge)
		edge = maxf(edge, sp.y)
	best = maxf(best, hw - edge)
	return best >= float(p["free"])


func on_event(kind: String, args: Array) -> void:
	if kind != "burst" or args.size() < 3:
		return
	var sn := int(args[0])
	var n := int(args[2])
	if _bursts.has(sn) or n < 1 or n > 3 or args.size() < 3 + 3 * n:
		return
	# a burst only the authority sends (_hunt). An online server takes only the one it is sending (a
	# client's "hz" event reaches it too); a client takes one from about now only
	if Net.active and Net.is_server and sn != _sending:
		return
	var t_w := float(args[1])
	if Net.active and not Net.is_server and absf(t_w - director.clock()) > 6.0:
		return
	# a forged one can not make them fire while they march, nor anywhere but the road of the zone they watch
	if not fits_watch(t_w):
		return
	var zone := zone_at(t_w)
	var L := float(p["strip_len"]) * 0.5
	var W := float(p["strip_w"]) * 0.5
	var strips := []
	for i in n:
		var at := fposmod(float(args[4 + 3 * i]), path.length)
		var lat := float(args[5 + 3 * i])
		if not director.in_span(at, float(zone[0]), float(zone[1])) or absf(lat) > half_width(at):
			return
		strips.append({"slot": int(args[3 + 3 * i]), "s": at, "lat": lat, "s0": at - L, "s1": at + L,
			"lat0": lat - W, "lat1": lat + W})
	var t_f := t_w + tm("warn")
	# (its HUD lock points at the column where it stands watch)
	var b := {"sn": sn, "t_w": t_w, "t_f": t_f, "end": t_f + tm_fire(), "strips": strips, "warned": false,
		"fired": false, "nodes": [], "from": _deck_point(float(march_at(t_w)[0])) + Vector3.UP * 2.0}
	_bursts[sn] = b
	_order.append(sn)
	_order.sort_custom(func(a: int, c: int) -> bool:
		var ta := float(_bursts[a]["t_w"])
		var tc := float(_bursts[c]["t_w"])
		return ta < tc or (ta == tc and a < c))
	while _order.size() > 3:
		_drop(_order[0])
	if director.authority():
		_ready_at = maxf(_ready_at, float(b["end"]) + tm("cool"))
	if visual:
		for st in strips:
			b["nodes"].append(_mark(st))


func _drop(sn: int) -> void:
	var b: Dictionary = _bursts.get(sn, {})
	for nd in b.get("nodes", []):
		if is_instance_valid(nd):
			(nd as Node).queue_free()
	_bursts.erase(sn)
	_order.erase(sn)


## One burst at clock t: its warning, its target's HUD lock, its shots and its hits on the karts this
## peer drives.
func _burst_tick(b: Dictionary, t: float) -> void:
	var t_w := float(b["t_w"])
	var t_f := float(b["t_f"])
	var end := float(b["end"])
	if t >= t_w and not b["warned"]:
		b["warned"] = true
		director.note(self, "warn")
		var lead := _leader_pos(t)
		play(_snd["on"], lead, 2.0, 30.0)
		play(_snd["contact"], lead, 4.0, 40.0)
	if t >= t_f and t <= end and not b["fired"]:
		b["fired"] = true
		director.note(self, "fire")
	if t >= t_w and t < t_f:
		for st in b["strips"]:
			var k := director.kart_at(int(st["slot"]))
			if k and not k.remote and k.state == Kart.State.NORMAL:
				k.hazard_lock = maxf(t_f - t, 0.01)
				k.hazard_lock_from = b["from"]
	if t >= t_f and t <= end + 0.05:
		for st in b["strips"]:
			for k in local_karts():
				if _in_strip(k, st):
					var away := k.global_position - road_point(float(st["s"]), float(st["lat"]))
					away.y = 0.0
					hit(k, str(p["effect"]), away.normalized() * k.mass * float(p["push"]) * 5.0)
	if crossed(end, t):
		play(_snd["off"], _leader_pos(t), 0.0, 30.0)
	if visual and t >= t_f - 0.1 and t <= end + 0.1:
		var strips: Array = b["strips"]
		for i in strips.size():
			for k in maxi(int(p["shots"]), 1):
				var sh := shot(b, i, k)
				if crossed(float(sh[0]), t):
					_shoot(b, i, k, sh[1])


## Kart k on the road of strip st (its lap metres, a kart's reach either side, at the road's height).
func _in_strip(k: Kart, st: Dictionary) -> bool:
	if not on_road(k, float(st["s0"]) - KART_R, float(st["s1"]) + KART_R):
		return false
	var lat := kart_lat(k)
	if lat < float(st["lat0"]) - KART_R or lat > float(st["lat1"]) + KART_R:
		return false
	var i := path.wi(k.path_index)
	return absf((k.global_position - path.center[i]).dot(path.up[i])) < 3.0


## The soldier at the head of the column now (the elite who calls it in).
func _leader_pos(t: float) -> Vector3:
	var m := march_at(t)
	var j := _n - 1 if float(m[1]) > 0.0 else 0
	return (soldier_at(j, t)[0] as Vector3) + Vector3.UP * 1.6


func _shooter(b: Dictionary, which: int, k: int) -> int:
	var ns := (b["strips"] as Array).size()
	var mine := []
	for j in _n:
		if j % ns == which:
			mine.append(j)
	return mine[k % mine.size()] if not mine.is_empty() else 0


func _shoot(b: Dictionary, which: int, k: int, at: Vector3) -> void:
	var j := _shooter(b, which, k)
	var from := _muzzle(j)
	Effects.tracer(get_parent(), from, at, TRACER)
	if j < _men.size():
		_men[j]["flash"] = director.clock()
	match k % 3:
		0:
			Effects.dust(get_parent(), at, 0.7)
			play(_snd["fire"], from, 0.0, 30.0)
		1:
			Effects.sparks(get_parent(), at, 0.35, TRACER)
	if k % 6 == 1:
		play(_snd["ric"], at, -3.0, 12.0)


## Soldier j's muzzle now (its rifle's, or in front of its chest where the content has no rifle).
func _muzzle(j: int) -> Vector3:
	if j < _men.size():
		var rifle = _men[j]["rifle"]
		if rifle is Node3D and is_instance_valid(rifle):
			return (rifle as Node3D).global_transform * _muzzle_m
		var node: Node3D = _men[j]["node"]
		var f := node.global_basis.z.normalized() if anims == null else node.global_basis.x.normalized()
		return node.global_position + Vector3.UP * 1.3 * float(p["scale"]) + f * 0.7
	var sa := soldier_at(j, director.clock())
	return (sa[0] as Vector3) + Vector3.UP * 1.3 + Vector3(sin(float(sa[1])), 0.0, cos(float(sa[1]))) * 0.7


# ---------------------------------------------------------------- visuals
## The strips' mark material, one for the session: Effects.prewarm draws it while the race loads, so
## the first burst's warning does not wait for its shader to compile.
static func mark_material() -> ShaderMaterial:
	if _mark_mat == null:
		_mark_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = MARK_SHADER
		_mark_mat.shader = sh
	return _mark_mat


## The red mark of a strip on the road: a hatched band with a bright border, following the road, and a
## red glow rising from its edges that fades out CURTAIN metres up (a band on the road alone is a thin
## line at the horizon from a kart's height).
func _mark(st: Dictionary) -> MeshInstance3D:
	var stt := SurfaceTool.new()
	stt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	var s0 := float(st["s0"])
	var s1 := float(st["s1"])
	var lat0 := float(st["lat0"])
	var lat1 := float(st["lat1"])
	stt.set_color(Color.WHITE)
	for i in segs + 1:
		var u := float(i) / segs
		var at := lerpf(s0, s1, u)
		stt.set_uv(Vector2(0.0, u))
		stt.add_vertex(road_point(at, lat0, 0.07))
		stt.set_uv(Vector2(1.0, u))
		stt.add_vertex(road_point(at, lat1, 0.07))
	for i in segs:
		var q := i * 2
		for v in [q, q + 1, q + 2, q + 1, q + 3, q + 2]:
			stt.add_index(v)
	# the glow round its edges: (lap metres, metres right) of its outline, a wall from each point to the
	# next (u 0 on the wall: the shader draws it as the border, fading with the vertex alpha)
	var ring: Array[Vector2] = []
	for i in segs + 1:
		ring.append(Vector2(lerpf(s0, s1, float(i) / segs), lat0))
	for i in segs + 1:
		ring.append(Vector2(lerpf(s1, s0, float(i) / segs), lat1))
	ring.append(ring[0])
	var base := (segs + 1) * 2
	for k in ring.size():
		var c: Vector2 = ring[k]
		stt.set_uv(Vector2(0.0, 0.5))
		stt.set_color(Color(1.0, 1.0, 1.0, 1.0))
		stt.add_vertex(road_point(c.x, c.y, 0.07))
		stt.set_color(Color(1.0, 1.0, 1.0, 0.0))
		stt.add_vertex(road_point(c.x, c.y, 0.07 + CURTAIN))
	for k in ring.size() - 1:
		var q := base + k * 2
		for v in [q, q + 1, q + 2, q + 1, q + 3, q + 2]:
			stt.add_index(v)
	var mi := MeshInstance3D.new()
	mi.mesh = stt.commit()
	mi.material_override = mark_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("col", Color(MARK, 0.0))
	mi.set_instance_shader_parameter("size", Vector2(float(st["lat1"]) - float(st["lat0"]), float(st["s1"]) - float(st["s0"])))
	add_child(mi)
	mi.top_level = true
	mi.global_transform = Transform3D.IDENTITY
	mi.visible = false
	return mi


const MARK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
instance uniform vec4 col : source_color = vec4(1.0, 0.1, 0.05, 0.8);
instance uniform vec2 size = vec2(4.0, 9.0);
void fragment() {
	vec2 m = UV * size;
	float edge = min(min(m.x, size.x - m.x), min(m.y, size.y - m.y));
	float border = 1.0 - smoothstep(0.12, 0.28, edge);
	float hatch = step(0.55, fract((m.x + m.y) * 0.55));
	ALBEDO = col.rgb;
	ALPHA = clamp(border + hatch * 0.35 + 0.1, 0.0, 1.0) * col.a * COLOR.a;
}
"""


## Every soldier where the clock puts it, posed (near ones every frame, far ones less often), its
## laser sight and its muzzle flash; the strips' marks pulsing through the warning.
func _place(t: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var m := march_at(t)
	var b := _burst_at(t)
	var sc := float(p["scale"])
	var step := step_share(float(m[3]), float(m[4])) if int(m[2]) == Seg.WATCH else 0.0
	var moving := int(m[2]) == Seg.WALK or not b.is_empty() or (step > 0.0 and step < 1.0)
	var on := not b.is_empty() and t >= float(b["t_w"]) and t <= float(b["end"])
	for j in _men.size():
		var man: Dictionary = _men[j]
		var node: Node3D = man["node"]
		# a soldier far off is moved and posed a few times a second; standing at ease, less often still
		var d := cam.global_position.distance_to(node.global_position) if cam else 0.0
		var hz := (0.0 if d < POSE_NEAR else (30.0 if d < POSE_MID else 8.0)) if moving else \
			(20.0 if d < POSE_NEAR else (10.0 if d < POSE_MID else 4.0))
		if AnimSet.due(node, t, hz):
			var sa := soldier_at(j, t, m, b)
			var yaw := float(sa[1]) - PI * 0.5 if anims else float(sa[1])
			var bob := 0.0
			if anims == null and int(m[2]) == Seg.WALK:
				# no animations in this content: a little bob in time with the march
				bob = absf(sin(float(m[5]) / _move * TAU)) * 0.05
			node.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), (sa[0] as Vector3) + Vector3.UP * bob)
			if anims and man["sk"]:
				_pose(man, j, m, sa, b, t)
		var g: MeshInstance3D = man["glow"]
		var lit := t - float(man["flash"]) < 0.05
		var laser: MeshInstance3D = man["laser"]
		g.visible = lit
		laser.visible = on
		if lit or on:
			var mz := _muzzle(j)
			if lit:
				g.global_position = mz
			if on:
				Effects.place_beam(laser, mz, aim_point(b, j, t))
	for bb in _bursts.values():
		var vis := t >= float(bb["t_w"]) and t <= float(bb["end"]) + 0.2
		var pulse := 0.55 + 0.45 * sin((t - float(bb["t_w"])) * TAU * 2.5)
		if t >= float(bb["t_f"]):
			pulse = 1.0 - clampf((t - float(bb["end"])) / 0.2, 0.0, 1.0) * 0.8
		for nd in bb["nodes"]:
			var mi := nd as MeshInstance3D
			if mi == null:
				continue
			mi.visible = vis
			if vis:
				mi.set_instance_shader_parameter("col", Color(MARK, MARK.a * pulse))


## Soldier j's body: the march in step with the others (blended in and out of the halts), standing at
## ease on watch and at the ends, its leader's halt signal, the rifle up at the strip, its kick as it
## fires, and the chest turned down at the road.
func _pose(man: Dictionary, j: int, m: Array, sa: Array, b: Dictionary, t: float) -> void:
	var sk: Skeleton3D = man["sk"]
	var since := float(m[3])
	var dur := float(m[4])
	var phase := float(m[5]) / (_move * float(p["scale"])) * anims.length("march")
	var idle_t := t + float(man["idle_t"])
	var up := float(sa[2]) if not b.is_empty() else 0.0
	match int(m[2]):
		Seg.WALK:
			var w := _ease(since / BLEND) * (1.0 - _ease((since - dur + BLEND) / BLEND))
			if w < 1.0:
				anims.pose(sk, "idle", idle_t)
			anims.pose(sk, "march", phase, w)
		_:
			# (the rifle fully up covers the stance at ease: no need to pose that first)
			if up < 1.0:
				anims.pose(sk, "idle", idle_t)
			# stepping up to the railing and back: the march in time with the step (backwards as they
			# step back)
			var k := step_share(since, dur) if int(m[2]) == Seg.WATCH else 0.0
			if k > 0.0 and k < 1.0:
				anims.pose(sk, "march", k * STEP_LEN / (_move * float(p["scale"])) * anims.length("march"),
					clampf(minf(k, 1.0 - k) * 5.0, 0.0, 1.0))
			# the head of the column signals the halt as it comes to the post
			var head := _n - 1 if float(m[1]) > 0.0 else 0
			if int(m[2]) == Seg.WATCH and j == head and since < anims.length("halt") + 0.3:
				anims.pose(sk, "halt", since, _ease(since / 0.2) * (1.0 - _ease((since - anims.length("halt")) / 0.3)), AnimSet.CLAMP)
	if up > 0.0:
		var firing := t >= float(b["t_f"]) and t <= float(b["end"])
		anims.pose(sk, "shoot" if firing else "aim", t - float(b["t_f"]) if firing else t, up)
		# the chest bent down towards its strip: a turn of the spine about the body's side, in the frame of the
		# bone above it as the aim pose holds it (worked out once, _pitch_axis)
		var bi := int(man["spine"])
		if bi >= 0:
			var pos: Vector3 = sa[0]
			var to := aim_point(b, j, t) - (pos + Vector3.UP * 1.35 * float(p["scale"]))
			var pitch := atan2(to.y, Vector2(to.x, to.z).length())
			sk.set_bone_pose_rotation(bi, Quaternion(man["axis"] as Vector3, clampf(pitch, -0.9, 0.3) * up) * sk.get_bone_pose_rotation(bi))


## The boots and the gear in time with their steps, the distant tramp while they march, the radio
## at each halt and turn.
func _sounds(t: float) -> void:
	var m := march_at(t)
	var walking := int(m[2]) == Seg.WALK
	if _march_loop:
		if walking and not _march_loop.playing:
			_march_loop.play()
		elif not walking and _march_loop.playing:
			_march_loop.stop()
	var ph := float(m[5]) / (_move * float(p["scale"]))
	var step := floori((ph - float(STEPS[0])) * 2.0)
	if walking and step != _last_step and _stepped:
		var mid := _deck_point(float(m[0])) + Vector3.UP * 0.2
		play(_snd["step"], mid, 6.0, 18.0, 0.95 + rnd(step, 3) * 0.1)
		if step % 3 == 0:
			play(_snd["gear"], (soldier_at(int(rnd(step, 4) * _n) % _n, t)[0] as Vector3) + Vector3.UP, -2.0, 12.0)
	_last_step = step
	_stepped = true
	var t0 := float(m[7])
	if crossed(t0, t) and int(m[2]) == Seg.WATCH:
		play(_snd["on"], _leader_pos(t), 0.0, 30.0)
		play(_snd["halt"], _leader_pos(t), 3.0, 36.0)
	# their boots and gear as they step up to the railing and back
	if int(m[2]) == Seg.WATCH and float(p["edge"]) > 0.0:
		for at: float in [t0 + T_FACE + 0.3, t0 + float(m[4]) - T_FACE - T_STEP + 0.3]:
			if crossed(at, t):
				play(_snd["step"], _deck_point(float(m[0])) + Vector3.UP * 0.2, 6.0, 18.0)
				play(_snd["gear"], _leader_pos(t), -2.0, 14.0)
	if crossed(t0 + float(m[4]) * 0.5, t) and int(m[2]) == Seg.END:
		play(_snd["turn"], _leader_pos(t), 2.0, 30.0)


func wake() -> void:
	_stepped = false


func sleep() -> void:
	if _march_loop:
		_march_loop.stop()
	for man in _men:
		(man["laser"] as Node3D).visible = false
		(man["glow"] as Node3D).visible = false
	for b in _bursts.values():
		for nd in b["nodes"]:
			if is_instance_valid(nd):
				(nd as Node3D).visible = false


# ---------------------------------------------------------------- answers
## Bots: out of a strip they would be in when its fire lands, to the side of it with room (and not
## into another strip).
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	for sn in _order:
		var b: Dictionary = _bursts[sn]
		if t > float(b["end"]) or t < float(b["t_w"]) - LEAD:
			continue
		# where it will be while the fire lands, if it holds its speed
		var a := at_s + speed * maxf(float(b["t_f"]) - t, 0.0)
		var z := at_s + speed * maxf(float(b["end"]) - t, 0.0)
		for st in b["strips"]:
			var s0 := float(st["s0"]) - 2.0
			if not director.in_span(a, s0, float(st["s1"]) + 2.0) and not director.in_span(s0, a, z):
				continue
			var lat := kart_lat(k)
			if lat < float(st["lat0"]) - 2.2 or lat > float(st["lat1"]) + 2.2:
				continue
			var hw := half_width(float(st["s"])) - 1.5
			var out := []
			for want in [float(st["lat0"]) - 2.2, float(st["lat1"]) + 2.2]:
				if absf(want) <= hw and not _in_any(b, float(st["s"]), want):
					out.append(want)
			if out.is_empty():
				# no room either side: the side with more of it, at the road's edge
				out.append(-hw if float(st["lat"]) > 0.0 else hw)
			out.sort_custom(func(x: float, y: float) -> bool: return absf(x - lat) < absf(y - lat))
			return {"lat": float(out[0]), "w": 0.85}
	return {}


func _in_any(b: Dictionary, at: float, lat: float) -> bool:
	for st in b["strips"]:
		if director.in_span(at, float(st["s0"]) - 2.0, float(st["s1"]) + 2.0) and lat > float(st["lat0"]) - 1.5 \
				and lat < float(st["lat1"]) + 1.5:
			return true
	return false


## A kart the scanner would put back on a strip about to be fired on.
func blocks_respawn(at_s: float) -> bool:
	var t := director.clock()
	for b in _bursts.values():
		if t > float(b["end"]) + 0.3:
			continue
		for st in b["strips"]:
			if director.in_span(at_s, float(st["s0"]) - 12.0, float(st["s1"]) + 6.0):
				return true
	return false


## Blocked by a strip: back to just before the zone that strip is in, not before the whole span (it
## holds both legs and the hairpin between them on White Forest: a strip on the west leg sent a kart
## ~200 m back, before the east zone).
func respawn_s(at_s: float) -> float:
	for q in _posts:
		if director.in_span(at_s, float(q["z0"]) - 12.0, float(q["z1"]) + 6.0):
			return fposmod(float(q["z0"]) - 15.0, path.length)
	return super(at_s)


func is_active(t: float) -> bool:
	for b in _bursts.values():
		if t >= float(b["t_w"]) and t <= float(b["end"]):
			return true
	return false


func snapshot(t: float) -> Array:
	var m := march_at(t)
	var out: Array = [snappedf(float(m[0]), 0.001), m[1], m[2], m[6]]
	for j in _n:
		var sa := soldier_at(j, t, m)
		out.append_array([(sa[0] as Vector3).snapped(Vector3.ONE * 0.01), snappedf(float(sa[1]), 0.001), snappedf(float(sa[2]), 0.001)])
	var b := _burst_at(t)
	if not b.is_empty():
		out.append_array([b["sn"], snappedf(float(b["t_w"]), 0.001)])
		for st in b["strips"]:
			out.append_array([st["slot"], snappedf(float(st["s"]), 0.01), snappedf(float(st["lat"]), 0.01)])
		for k in 3:
			var sh := shot(b, 0, k)
			out.append_array([snappedf(float(sh[0]), 0.001), (sh[1] as Vector3).snapped(Vector3.ONE * 0.01)])
	return out


## A made-up burst for the determinism test (no karts): early in the first watch from t0 on, one strip
## in the middle of the zone and one beside it.
func test_event(t0: float, sn := 900) -> Array:
	var w := next_watch(t0)
	var t_w := float(w[0]) + settle() + 0.5
	var zone := zone_at(t_w)
	var mid := float(zone[0]) + ahead(float(zone[0]), float(zone[1])) * 0.5
	var lat := half_width(mid) - float(p["strip_w"]) * 0.5 - 0.5
	return [sn, t_w, 2, 0, mid, -lat, 1, mid + float(p["strip_len"]) + 3.0, lat]


## The deck's points and the column's length (tests: the soldiers never stand on a road).
func deck() -> PackedVector3Array:
	return _deck


func soldiers() -> int:
	return _n


func cycle() -> float:
	return _cycle


## True while no burst is announced or under way (tests).
func idle() -> bool:
	var t := director.clock()
	for b in _bursts.values():
		if t <= float(b["end"]) + AFTER:
			return false
	return true
