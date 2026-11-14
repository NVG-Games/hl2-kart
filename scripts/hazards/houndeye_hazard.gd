class_name HoundeyeHazard
extends Hazard
## A pack of houndeyes on a Xen verge. They pace up and down the verge (their walk, a function of
## the shared clock). When a kart comes they chirp and run out to meet it, up to the road's edge
## and never onto the road (p["spots"], laid by tools/hazards.py), turn to the road and charge up
## (their attack animation, a blue light growing), then release a sonic blast that spins out the
## karts within its reach and pushes them away; then they hop back and walk home. The blast is
## centred on those spots and its reach is cut so a kart on the far side of the road, where the
## bots go when they hear the chirp, is out of it. Every peer runs its own pack against the karts
## it sees; each owner judges its own karts.

enum S { IDLE, NOTICE, CHARGE, COOL }
const BLAST := Color(0.6, 0.85, 1.0)
const NOTICE_T := 0.35
const RUN := 9.0             # m/s they run out at
const TROT := 2.6            # m/s they go home at after a blast
const PAUSE := 2.5           # seconds they stand at each end of their beat
const FAR_LANE := 2.5        # metres in from the far edge where the bots go (advice)
const FAR_MARGIN := 2.0      # metres the blast stops short of a kart there
## seconds into attack where the blast goes off (event 3, frame 59 at 25 fps)
const BLAST_AT := 59.0 / 25.0
const POSE_NEAR := 60.0      # metres from the camera within which they are posed every frame
const JUMPBACK_DROP := 0.2   # metres (model) its hop back lands under where it took off
## model metres from its origin to the front of its body as it charges up (tools/hazards.py HOUNDEYE_NOSE)
const NOSE := 0.78
## where its three feet touch the ground in the model (metres): the two in front and the one behind
const FEET := [Vector3(0.32, 0.0, 0.32), Vector3(-0.32, 0.0, 0.32), Vector3(0.0, 0.0, -0.46)]

var st := S.IDLE
var st_t := 0.0
var anims: AnimSet
## per member: {node, sk, beat (PackedVector3Array), cum, len, road (yaw facing the road), at, yaw,
## home (bool: on its beat), anim_t}
var _members: Array = []
var _spots: Array[Vector3] = []  # where each one stands to blast (every peer, visuals or not)
var _centre := Vector3.ZERO      # the blast's centre: the middle of the spots
var _reach := 10.0               # the blast's radius: p["radius"] cut to spare the far side
var _light: OmniLight3D
var _crackle := 0.0
var _idle_t := 3.0
var _snd := {}


func defaults() -> Dictionary:
	return {"members": [], "walks": [], "spots": [], "side": 1, "scale": 1.5, "radius": 10.0, "notice": 30.0,
		"charge": 1.3, "cool": 3.5, "push": 0.45, "lift": 0.1, "effect": "spin", "model": "hl1/houndeye"}


func build() -> void:
	_snd["alert"] = sounds([["hl1src/houndeye/he_alert1.wav", "hl1src/houndeye/he_alert2.wav"],
		["npc/headcrab/alert1.wav"]])
	_snd["hunt"] = sounds([["hl1src/houndeye/he_hunt1.wav", "hl1src/houndeye/he_hunt2.wav",
		"hl1src/houndeye/he_hunt3.wav", "hl1src/houndeye/he_hunt4.wav"]])
	_snd["attack"] = sounds([["hl1src/houndeye/he_attack1.wav"], ["weapons/gauss/chargeloop.wav"]])
	_snd["blast"] = sounds([["hl1src/houndeye/he_blast1.wav", "hl1src/houndeye/he_blast2.wav",
		"hl1src/houndeye/he_blast3.wav"], ["npc/roller/mine/rmine_explode_shock1.wav"]])
	_snd["idle"] = sounds([["hl1src/houndeye/he_idle1.wav", "hl1src/houndeye/he_idle2.wav",
		"hl1src/houndeye/he_idle3.wav"], ["npc/headcrab/idle3.wav"]])
	var side := signf(float(p["side"]))
	var members: Array = p["members"]
	for i in members.size():
		var m: Array = members[i]
		var home := Vector3(m[0], m[1], m[2])
		var spot := home
		if i < (p["spots"] as Array).size():
			var q: Array = p["spots"][i]
			spot = Vector3(q[0], q[1], q[2])
		else:
			# older track data: just past the edge beside where it stands, its nose off the road (as
			# tools/hazards.py lays them)
			var at_s := path.progress(home, path.closest(home))
			spot = road_point(at_s - 3.0, side * (half_width(at_s) + NOSE * float(p["scale"]) + 0.25 + 0.9 * (i % 2)))
		_spots.append(spot)
		_centre += spot / members.size()
	if members.is_empty():
		_centre = global_position
	var far := road_point(s, -side * (half_width(s) - FAR_LANE), 0.5)
	_reach = minf(float(p["radius"]), _centre.distance_to(far) - FAR_MARGIN)
	if not visual or not Game.models.has(str(p["model"])):
		return
	anims = AnimSet.of(str(p["model"]))
	for i in members.size():
		var m: Array = members[i]
		var node := Game.spawn_model(str(p["model"]))
		add_child(node)
		node.top_level = true
		node.scale = Vector3.ONE * float(p["scale"])
		var beat := PackedVector3Array()
		if i < (p["walks"] as Array).size():
			for q in p["walks"][i]:
				beat.append(Vector3(q[0], q[1], q[2]))
		if beat.is_empty():
			beat.append(Vector3(m[0], m[1], m[2]))
		var cum := PackedFloat32Array([0.0])
		for j in range(1, beat.size()):
			cum.append(cum[j - 1] + beat[j].distance_to(beat[j - 1]))
		var mem := {"node": node, "sk": AnimSet.skeleton(node), "beat": beat, "cum": cum, "len": cum[-1],
			"road": float(m[3]), "home": true, "anim_t": rnd(i, 5) * 3.0}
		var at: Array = _beat_at(mem, i, 0.0)
		mem["at"] = at[0]
		mem["yaw"] = float(at[1])
		node.global_position = at[0]
		node.global_rotation.y = float(at[1])
		_members.append(mem)
	_light = light(BLAST, 14.0, 0.0)
	if _light:
		_light.top_level = true
		_light.global_position = _centre + Vector3.UP * 1.2


## Where member i paces at clock t on its beat: [point, yaw, walking]. Up the beat, a pause, back
## down, a pause, at its walk's own pace; each starts at its own point of the round.
func _beat_at(mem: Dictionary, i: int, t: float) -> Array:
	var beat: PackedVector3Array = mem["beat"]
	var length: float = mem["len"]
	if beat.size() < 2 or length < 0.1:
		return [beat[0], float(mem["road"]), false]
	var walk := _walk_speed()
	var leg := length / walk
	var round_t := 2.0 * (leg + PAUSE)
	var u := fposmod(t + rnd(i, 6) * round_t, round_t)
	var d := 0.0
	var dir := 1.0
	var moving := true
	if u < PAUSE:
		d = 0.0
		moving = false
	elif u < PAUSE + leg:
		d = (u - PAUSE) * walk
	elif u < 2.0 * PAUSE + leg:
		d = length
		moving = false
	else:
		d = length - (u - 2.0 * PAUSE - leg) * walk
		dir = -1.0
	var cum: PackedFloat32Array = mem["cum"]
	var j := clampi(cum.bsearch(d, true) - 1, 0, beat.size() - 2)
	var a := beat[j]
	var b := beat[j + 1]
	var q := a.lerp(b, clampf((d - cum[j]) / maxf(cum[j + 1] - cum[j], 0.001), 0.0, 1.0))
	if not moving:
		return [q, float(mem["road"]), false]
	var go := (b - a) * dir
	return [q, atan2(go.x, go.z), true]


## Metres a second of their walk at their size (the walk's own pace, so the feet do not slide).
func _walk_speed() -> float:
	if anims and anims.speed("walk") > 0.0:
		return anims.speed("walk") * float(p["scale"])
	return 1.2


func snapshot(t: float) -> Array:
	var out: Array = [_centre.snapped(Vector3.ONE * 0.01), snappedf(_reach, 0.01)]
	for i in _members.size():
		out.append((_beat_at(_members[i], i, t)[0] as Vector3).snapped(Vector3.ONE * 0.01))
	return out


func tick(t: float, dt: float) -> void:
	st_t += dt
	match st:
		S.IDLE:
			if t >= 0.0 and _noticed():
				_enter(S.NOTICE)
		S.NOTICE:
			if st_t >= NOTICE_T:
				_enter(S.CHARGE)
		S.CHARGE:
			_crackle -= dt
			if _crackle <= 0.0 and visual:
				_crackle = 0.2
				Effects.sparks(get_parent(), _centre + Vector3.UP * 0.8, 0.3, BLAST)
			if st_t >= tm("charge"):
				_blast()
				_enter(S.COOL)
		S.COOL:
			if st_t >= tm("cool"):
				_enter(S.IDLE)
	if visual:
		_animate(t, dt)


## A kart coming along the road towards the pack.
func _noticed() -> bool:
	var notice := float(p["notice"])
	for k in all_karts():
		if not targetable(k) or not on_road(k, s - notice, s + 5.0):
			continue
		if k.global_position.distance_to(global_position) < notice + 2.0 and k.velocity().dot(path.fwd[k.path_index]) > 2.0:
			return true
	return false


func _enter(next: S) -> void:
	st = next
	st_t = 0.0
	match next:
		S.NOTICE:
			director.note(self, "warn")
			for i in _members.size():
				var at: Vector3 = _members[i]["at"]
				get_tree().create_timer(0.1 * i).timeout.connect(func(): play(_snd["alert"], at, 0.0, 14.0))
			play(_snd["hunt"], _centre, 0.0, 14.0)
		S.CHARGE:
			play(_snd["attack"], _centre, 2.0, 18.0)


func _blast() -> void:
	director.note(self, "fire")
	var up := path.up[path.index_at(s)]
	if visual:
		play(_snd["blast"], _centre, 6.0, 18.0)
		Effects.shock_ring(get_parent(), _centre, up, _reach, Color(BLAST, 0.9), 0.35)
		Effects.sparks(get_parent(), _centre + up, 1.0, BLAST)
		if _light:
			_light.light_energy = 10.0
		var player: Kart = director.race.player if director.race else null
		if player and player.global_position.distance_to(_centre) < 15.0:
			for cam in get_tree().get_nodes_in_group("race_camera"):
				cam.shake(0.4)
	blast(_centre, _reach, str(p["effect"]), float(p["push"]), float(p["lift"]))


## Each houndeye: on its beat while the pack is idle (walking or standing about), out to its spot
## at the run as the pack notices a kart, there through the charge (its attack animation, timed so
## the blast comes at its end), a hop back after the blast, then home at a trot to its beat.
func _animate(t: float, dt: float) -> void:
	var charge := clampf(st_t / tm("charge"), 0.0, 1.0) if st == S.CHARGE else 0.0
	if _light:
		var want := 6.0 * charge * (0.7 + 0.3 * sin(t * 40.0)) if st == S.CHARGE else 0.0
		_light.light_energy = move_toward(_light.light_energy, want, dt * 40.0)
	var out := st == S.NOTICE or st == S.CHARGE
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(_centre) < POSE_NEAR
	for i in _members.size():
		var mem: Dictionary = _members[i]
		var node: Node3D = mem["node"]
		var at: Vector3 = mem["at"]
		var yaw: float = mem["yaw"]
		var anim := "idle2"
		var rate := 1.0
		var a_t := -1.0
		if out:
			mem["home"] = false
			# in plan only: the height is the ground's (_stand below), which can sit a little under a
			# spot laid on the road's plane (older track data), and a houndeye must still get there
			var spot: Vector3 = _spots[i]
			var to := Vector3(spot.x - at.x, 0.0, spot.z - at.z)
			if to.length() > 0.05:
				at = at.move_toward(Vector3(spot.x, at.y, spot.z), RUN * dt)
				yaw = lerp_angle(yaw, atan2(to.x, to.z), minf(1.0, dt * 12.0))
				anim = "run"
				rate = RUN / maxf(_anim_speed("run"), 0.1)
			else:
				yaw = lerp_angle(yaw, float(mem["road"]), minf(1.0, dt * 8.0))
				anim = "madidle" if st == S.NOTICE else "attack"
				if st == S.CHARGE:
					a_t = BLAST_AT * charge
		elif st == S.COOL and st_t < 0.95 and not mem["home"]:
			anim = "jumpback"
			a_t = st_t
		elif not mem["home"]:
			var bt: Array = _beat_at(mem, i, t)
			var home: Vector3 = bt[0]
			var to := Vector3(home.x - at.x, 0.0, home.z - at.z)
			if to.length() < 0.15:
				mem["home"] = true
			else:
				at = at.move_toward(Vector3(home.x, at.y, home.z), TROT * dt)
				yaw = lerp_angle(yaw, atan2(to.x, to.z), minf(1.0, dt * 8.0))
				anim = "walk"
				rate = TROT / maxf(_anim_speed("walk"), 0.1)
		if mem["home"]:
			var bt: Array = _beat_at(mem, i, t)
			at = bt[0]
			yaw = lerp_angle(yaw, float(bt[1]), minf(1.0, dt * 6.0))
			anim = "walk" if bt[2] else "idle2"
		# on the ground under it, leaning with its slope: the beat's points and the spots are the
		# verge as the generator laid it, and a straight line between two of them would cut into a bulge
		var lean := Vector3.UP
		if is_inside_tree():
			var g := _stand(at, yaw)
			at.y = g[0]
			lean = g[1]
		mem["at"] = at
		mem["yaw"] = yaw
		node.global_transform = Transform3D((Basis(Quaternion(Vector3.UP, lean)) * Basis(Vector3.UP, yaw))
			.scaled(Vector3.ONE * float(p["scale"])), at)
		if anim == "jumpback":
			# the hop lands lower than it took off (the sequence's own drop): held up off the ground
			node.global_position.y += JUMPBACK_DROP * float(p["scale"]) * clampf(a_t / 0.95, 0.0, 1.0)
		mem["anim_t"] = float(mem["anim_t"]) + dt * rate
		var sk: Skeleton3D = mem["sk"]
		if anims == null or sk == null:
			# no animations in this content: breathe, faster and deeper while charging
			var sq := 1.0 + sin(t * (2.0 + 16.0 * charge * charge) + i) * (0.03 + 0.12 * charge)
			node.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq)) * float(p["scale"])
			continue
		if not AnimSet.due(node, t, 0.0 if near else 12.0):
			continue
		if a_t >= 0.0:
			anims.pose(sk, anim, a_t, 1.0, AnimSet.CLAMP)
		else:
			anims.pose(sk, anim, float(mem["anim_t"]), 1.0, AnimSet.LOOP)
	if st != S.CHARGE:
		_idle_t -= dt
		if _idle_t <= 0.0:
			_idle_t = 4.0 + rnd(int(t), 3) * 6.0
			play(_snd["idle"], _centre, -6.0, 12.0)


## How a houndeye at q turned by yaw stands: [the height of its origin, its up]. The ground is
## probed under its middle and under its three feet; it leans 0.8 of the way to the plane of its
## feet (a little more upright than the ground) and stands at least as high as the ground under its
## middle, lifted further until no foot is in the ground. Where a verge folds between its feet, the
## ground under its middle alone left the feet on the higher side up to 0.24 m in the ground. A foot
## over nothing (past an island's edge) takes the slope under its middle and lifts nothing.
func _stand(q: Vector3, yaw: float) -> Array:
	var turn := Basis(Vector3.UP, yaw)
	var sc := float(p["scale"])
	var mid := _ground(q)
	var n0 := Vector3(mid.y, mid.z, mid.w)
	var space := get_world_3d().direct_space_state
	var offs: Array[Vector3] = []
	var hs: Array[float] = []
	var firm: Array[bool] = []
	for f: Vector3 in FEET:
		var o := turn * (f * sc)
		var c := q + o
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.5, c - Vector3.UP * 3.0,
			Game.LAYER_WORLD))
		offs.append(o)
		firm.append(not hit.is_empty())
		hs.append((hit["position"] as Vector3).y if not hit.is_empty() else mid.x - (n0.x * o.x + n0.z * o.z) / maxf(n0.y, 0.1))
	var n := (offs[1] + Vector3.UP * hs[1] - offs[0] - Vector3.UP * hs[0]).cross(
		offs[2] + Vector3.UP * hs[2] - offs[0] - Vector3.UP * hs[0]).normalized()
	if n.y < 0.0:
		n = -n
	if n.y < 0.5:
		# a foot down a drop or up a step: the slope under its middle
		n = n0
	var up := Vector3.UP.lerp(n, 0.8).normalized()
	var tilt := Basis(Quaternion(Vector3.UP, up))
	var y := mid.x
	for j in offs.size():
		if firm[j]:
			y = maxf(y, hs[j] - (tilt * offs[j]).y)
	return [y, up]


## The ground (the static world) under q: its height and its normal (x; y, z, w), q's own height
## and straight up where there is none.
func _ground(q: Vector3) -> Vector4:
	var rq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 1.5, q - Vector3.UP * 3.0, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	if hit.is_empty():
		return Vector4(q.y, 0.0, 1.0, 0.0)
	var n: Vector3 = hit["normal"]
	return Vector4((hit["position"] as Vector3).y, n.x, n.y, n.z)


## Metres a second an animation carries a houndeye at its size.
func _anim_speed(anim: String) -> float:
	return anims.speed(anim) * float(p["scale"]) if anims else 1.0


func sleep() -> void:
	if st != S.COOL:
		st = S.IDLE
		st_t = 0.0


## While they are about to blast: keep to the far side of the road.
func advice(_k: Kart, at_s: float, _speed: float) -> Dictionary:
	if (st != S.NOTICE and st != S.CHARGE) or ahead(at_s, s) > 45.0:
		return {}
	return {"lat": -signf(float(p["side"])) * (half_width(s) - FAR_LANE), "w": 0.7}


func is_active(_t: float) -> bool:
	return st == S.CHARGE
