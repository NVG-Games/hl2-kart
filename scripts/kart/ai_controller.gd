class_name AIController
extends RefCounted
## Computer racer: follows the precomputed racing line with a personal lane
## offset, brakes for corners, drifts long bends, uses items sensibly and
## rubber-bands against the player. At every fork it decides once per lap whether
## to take the branch (skill, the branch's risk, the speed its jump needs, race
## position, a dice roll) and then looks ahead along the road it chose. Track
## hazards on that road give it a lane and a speed cap (it mostly listens), and a
## gun that locks on may get a quick swerve or a brake tap. Stuck nose-in on a wall it backs
## off and swings its nose away (twice at most) before the scanner comes.

const BOOSTS := ["battery", "battery3", "hev"]
## metres before a boost-gated fork from which a bot keeps the boost it holds for that fork
const HOLD_FOR_FORK := 700.0
## stuck on a wall or a prop (_unstick): slower than STUCK_V (m/s) for STUCK_T seconds with the
## throttle down; a try backs off for at most BACK_T seconds, no faster than BACK_V, then pulls away
## for PULL_T; after UNSTICK_TRIES failed tries the scanner comes
const STUCK_V := 1.5
const STUCK_T := 0.5
const BACK_T := 1.4
const BACK_V := 4.0
const PULL_T := 0.8
const UNSTICK_TRIES := 2
## a branch's jump: from its commit point on a bot runs at least the need plus this (its kicker
## costs a couple of m/s), and it takes the branch only when it reaches the need plus this
## (_lip_speed)
const LIP_MARGIN := 2.0
## how much of the engine's push (Kart._integrate_forces) a bot turns into speed on a run-up
## (steering, the suspension's pitch and the kicker eat the rest): measured on the jumps' run-ups
const LIP_PACE := 0.55
## sideways acceleration (m/s^2) beyond which a bot can no longer swing onto a branch it planned
## before the roads part (_can_turn_in): it stays on the main road instead of overshooting
const TURN_IN_MAX := 60.0

var skill := 0.9
var lane := 0.0
var _lane_target := 0.0
var _lane_t := 0.0
var _item_wait := 0.0
var _blind_t := 0.0
var _drift_hold := 0.0
var _clock := 0.0
var _hz_obey := {}  # hazard id -> [obeys, until]: rolled once per approach
var _dodged := false  # made this lock's dodge roll
var _dodge_t := 0.0  # dodging a locked-on gun: a quick lane change
var _brake_t := 0.0  # ... and sometimes a brake tap
var _rng := RandomNumberGenerator.new()
var _plan := {}  # fork decisions: branch index + 1000 * lap -> take it
var _plan_now := {}  # the decisions for the forks of this lap: branch index -> take it
var _respawns := 0  # the kart's rescue count when the plan was last looked at
var _lip_t := 0.0  # until the next look at the jump speed of a planned branch (_plan_forks)
# stuck on a wall (_unstick): how long it has been, the try under way (0 none, 1 backing off,
# 2 pulling away) and its clock, its steering lock while backing off, tries so far, the progress at
# the first try and where this one started, the way the nose should end up, the rescue count
var _stuck_t := 0.0
var _try := 0
var _try_t := 0.0
var _lock := 0.0
var _tries := 0
var _stuck_at := 0.0
var _stuck_pos := Vector3.ZERO
var _way := Vector3.ZERO
var _unstick_respawns := 0


func _init(sk: float, seed_v: int) -> void:
	skill = sk
	_rng.seed = seed_v
	_lane_target = _rng.randf_range(-3.0, 3.0)
	_item_wait = _rng.randf_range(1.0, 3.0)


func drive(k: Kart, delta: float) -> void:
	var path := k.track.path
	var race_on: bool = k.race == null or k.race.racing or k.state == Kart.State.FINISHED
	if not race_on:
		k.in_throttle = 0.0
		k.in_steer = 0.0
		k.in_brake = 0.0
		k.in_drift = false
		k.in_item = false
		return
	var pos := k.global_position
	var sp := maxf(k.fwd_speed, 0.0)
	_lane_t -= delta
	if _lane_t <= 0.0:
		_lane_t = _rng.randf_range(2.0, 5.0)
		_lane_target = _rng.randf_range(-1.5, 1.5) * (1.25 - skill) * 2.0
	lane = lerpf(lane, _lane_target, delta * 0.8)
	_plan_forks(k, delta)
	# everything below follows the road under the kart (k.geo()) and looks ahead along the road
	# it plans to drive (_ahead); on the main loop with no fork planned that is the lap itself
	var g := k.geo()
	var i_here := g.index_at(k.route_pos())
	# beside an open edge: hold the racing line and ease off a little
	var edge := g.pit[i_here] == 1 and g.gap[i_here] == 0
	if edge:
		lane = lerpf(lane, 0.0, delta * 3.0)
	var off_lat := absf(g.lateral(pos, i_here))
	var half := g.width[i_here] * 0.5
	var look := clampf(6.0 + sp * 0.32, 6.0, 16.0)
	# tighter look-ahead through bends so the line does not cut over kerbs
	var a := _ahead(k, 25.0)
	var ga := path.geo(int(a.x))
	var bend := absf(g.fwd[i_here].signed_angle_to(ga.fwd[ga.index_at(a.y)], Vector3.UP))
	look *= clampf(1.0 - bend * 0.9, 0.5, 1.0)
	a = _ahead(k, look)
	ga = path.geo(int(a.x))
	var ti := ga.index_at(a.y)
	# track hazards on the road ahead: a lane to take (a gate's open lane, away from a strike)
	# while the point it steers for is on the main loop they stand on, never closer than a kart
	# and a half to an open edge; a speed cap further down
	_clock += delta
	var hz := _hazard_advice(k, sp)
	if int(hz.get("id", -1)) >= 0 and int(a.x) < 0 and _obeys(int(hz["id"])):
		var room := ga.width[ti] * 0.5 - (3.5 if ga.pit[ti] == 1 or edge else 2.0)
		var want := clampf(float(hz["lat"]), -maxf(room, 0.0), maxf(room, 0.0))
		lane = lerpf(lane, want - ga.lateral(ga.line_at(a.y), ti), minf(1.0, delta * 3.0))
	_dodge(k, delta)
	var target := ga.line_at(a.y) + ga.right[ti] * lane
	if int(a.x) >= 0:
		# a narrow branch: line plus lane stay clear of its edges
		var lat := ga.lateral(target, ti)
		var room := maxf(ga.width[ti] * 0.5 - 2.0, 0.0)
		target += ga.right[ti] * (clampf(lat, -room, room) - lat)
	if off_lat > half - 0.5:
		# off the tarmac: head straight back to the centre line
		look = 10.0
		a = _ahead(k, look)
		ga = path.geo(int(a.x))
		ti = ga.index_at(a.y)
		target = ga.center_at(a.y)
	# dodge karts directly ahead
	for n in k.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == k:
			continue
		var d := o.global_position - pos
		var ahead := d.dot(-k.global_basis.z)
		if ahead > 0.0 and ahead < 14.0 and absf(d.dot(k.global_basis.x)) < 2.6:
			target += ga.right[ti] * (2.0 if d.dot(k.global_basis.x) < 0.0 else -2.0)
	var to := target - pos
	var fwd := -k.global_basis.z
	var right := k.global_basis.x
	var ang := atan2(to.dot(right), to.dot(fwd))
	var steer := clampf(ang * 2.2, -1.0, 1.0)
	# corner speed: min of the racing-line speed table over the braking window
	var vt := 999.0
	var win := int((sp * 1.6 + 10.0) / path.step) + 1
	for j in win:
		var q := _ahead(k, j * path.step)
		var gq := path.geo(int(q.x))
		vt = minf(vt, gq.speed[gq.index_at(q.y)] + j * path.step * 0.35)
	var top := k.max_speed
	vt = minf(vt * (0.85 + skill * 0.25) * (0.92 if edge else 1.0), top)
	# rubber band toward the player
	var player := _player(k)
	if player and player != k:
		var gap := k.total_progress - player.total_progress
		if gap > 60.0:
			vt *= 0.9
		elif gap < -80.0:
			vt *= 1.07
			k.boost_time = maxf(k.boost_time, 0.0)
	# the jump: commit to full speed (from 40 m before its gap, or from where its branch says:
	# TrackBranch.ai_commit, where a bend comes closer to the kicker)
	var commit := _commit(k)
	if _gap_at(k, commit) or _gap_at(k, minf(15.0, commit)):
		vt = 999.0
		var c := _ahead(k, 30.0)
		var aim := path.geo(int(c.x)).center_at(c.y) - pos
		steer = clampf(atan2(aim.dot(right), aim.dot(fwd)) * 2.5, -1.0, 1.0)
	# ... and from there on a branch's jump never slower than it needs (the checks above leave the
	# run-up to a short gap partly at the racing line's corner speed)
	vt = maxf(vt, _jump_floor(k, commit))
	# a hazard's speed cap wins even over the jump (the train: stop at the line)
	if int(hz.get("vid", -1)) >= 0 and _obeys(int(hz["vid"]), 0.1):
		vt = minf(vt, float(hz["vmax"]))
	var throttle := 1.0
	var brake := 0.0
	if sp > vt + 2.0:
		throttle = 0.0
		brake = clampf((sp - vt) / 6.0, 0.0, 1.0)
	elif sp > vt:
		throttle = 0.3
	if _brake_t > 0.0:
		throttle = 0.0
		brake = 0.6
	# long bends: drift for a mini-turbo
	var drift := false
	if skill > 0.97 and sp > 20.0 and absf(ang) > 0.14 and absf(ang) < 0.4 and k.grounded and bend > 0.5:
		_drift_hold = 0.7
	if edge:
		_drift_hold = 0.0
	if _drift_hold > 0.0:
		_drift_hold -= delta
		drift = absf(steer) > 0.15 or k.drifting
		# out of it once lined up with a turbo charged, or as soon as the line wants the other way: a
		# drift keeps turning the kart its own way even against full lock (bots overshot S-bends and
		# swung past a fork's turn-in into its rail)
		if k.drifting and ((k.drift_level >= 1 and absf(ang) < 0.08) or steer * k.drift_dir < -0.3):
			drift = false
			_drift_hold = 0.0
	# stuck on a wall or a prop: back off it and swing the nose away (_unstick)
	if _unstick(k, delta, throttle > 0.0, to):
		throttle = 1.0 if _try == 2 else 0.0
		brake = 1.0 if _try == 1 and k.fwd_speed > -BACK_V else 0.0
		steer = _lock if _try == 1 else clampf(_side_angle(k, _way) * 2.2, -1.0, 1.0)
		drift = false
	# a headcrab on the face: driving half blind
	if k.blind_time > 0.0:
		_blind_t += delta
		steer = clampf(steer + sin(_blind_t * 3.7) * 0.7, -1.0, 1.0)
		throttle *= 0.8
		drift = false
	k.in_throttle = throttle
	k.in_brake = brake
	k.in_steer = steer
	k.in_drift = drift
	k.in_item = _want_item(k, delta)
	k.in_look_back = false


## Where the planned road is `d` metres ahead of the kart: Vector2(route, metres on it). On the
## part of a branch it shares with the main road a kart that does not (or no longer) plan to take
## that branch looks along the main road.
func _ahead(k: Kart, d: float) -> Vector2:
	var p := k.track.path
	if k.route >= 0 and not _plan_now.get(k.route, false) and k.route_u < p.branches[k.route].fork_nose_u - 2.0:
		return p.walk(-1, k.lap_progress, d, _plan_now)
	return p.walk(k.route, k.route_pos(), d, _plan_now)


## How far before a jump gap ahead this bot commits to it: the branch's ai_commit for a branch
## it is on or about to take, 40 m on the main loop.
func _commit(k: Kart) -> float:
	var a := _ahead(k, 40.0)
	return k.track.path.branches[int(a.x)].ai_commit if int(a.x) >= 0 else 40.0


func _gap_at(k: Kart, d: float) -> bool:
	var a := _ahead(k, d)
	var ga := k.track.path.geo(int(a.x))
	return ga.gap[ga.index_at(a.y)] == 1


## Each fork is decided once per lap, 140 m before it. On the way to its nose the decision
## is called off when the kart could no longer make the jump (hit, bumped, spun, slowed: _can_make)
## or swing onto the branch before the roads part (_can_turn_in), and a kart the scanner had to
## rescue from a branch does not try that branch again on this lap. The call-off is looked at
## every 0.1 s (at every call without a `delta`: a test stepping a bot by hand).
func _plan_forks(k: Kart, delta := 0.0) -> void:
	var p := k.track.path
	var rescued := k.respawns != _respawns
	_respawns = k.respawns
	_lip_t -= delta
	var look := _lip_t <= 0.0 or delta <= 0.0
	if look:
		_lip_t = 0.1
	for b in p.branches.size():
		var br := p.branches[b]
		var to_fork := fposmod(br.fork_s - k.lap_progress, p.length)
		var past := fposmod(k.lap_progress - br.fork_s, p.length)
		if rescued and (k.route == b or (k.lap_progress >= br.fork_s - 5.0 and k.lap_progress <= br.merge_s)):
			_plan[b + 1000 * k.lap] = false
		var key := b + 1000 * (k.lap + (1 if k.lap_progress > br.fork_s and to_fork <= 140.0 else 0))
		if to_fork <= 140.0:
			if not _plan.has(key):
				_plan[key] = _want_branch(k, br)
			elif look and _plan[key] and not _can_make(k, br, to_fork):
				_plan[key] = false
		elif look and (k.route < 0 or k.route == b) and past < br.fork_nose_u and _plan.get(key, false) \
				and not (_can_make(k, br, -past) and _can_turn_in(k, br, past)):
			_plan[key] = false
		_plan_now[b] = _plan.get(key, false)


## Take this branch? Never when the kart can not reach the speed its jump needs; otherwise a
## roll weighted by the branch's own take rate, skill against its minimum, its risk (back-
## markers gamble more) and how the kart is doing right now.
func _want_branch(k: Kart, br: TrackBranch) -> bool:
	var boost := _has_boost(k)
	if br.need_boost and not boost:
		return false
	if br.need_speed > k.max_speed * (1.32 if boost else 1.0) * 0.98:
		return false
	var p_take := br.ai_take
	p_take *= clampf((skill - br.ai_min_skill) / 0.12 + 0.5, 0.0, 1.0)
	p_take *= 1.0 - br.risk * (0.5 if k.place >= 5 else 0.8)
	if k.blind_time > 0.0 or k.state != Kart.State.NORMAL:
		p_take *= 0.3
	return _rng.randf() < p_take


## Still fast enough for the branch's jump, `to_fork` metres before its fork (negative: past
## it)? It must run onto the jump with its need plus LIP_MARGIN (_lip_speed); a held boost will.
func _can_make(k: Kart, br: TrackBranch, to_fork: float) -> bool:
	if k.state != Kart.State.NORMAL and to_fork < 40.0:
		return false
	if br.need_speed <= 0.0 or _has_boost(k):
		return true
	return _lip_speed(k, br, to_fork) >= br.need_speed + LIP_MARGIN


## The speed this bot runs onto branch br's next jump with, `to_fork` metres before its fork
## (negative: past it): up to the commit point no faster than the racing line's corner speeds (as
## drive() holds them), from there flat out; the engine as in Kart._integrate_forces at LIP_PACE,
## against the slope. Without a jump ahead: INF.
func _lip_speed(k: Kart, br: TrackBranch, to_fork: float) -> float:
	var p := k.track.path
	var u := -to_fork
	var gap := maxf(u, 0.0) + br.gap_ahead(maxf(u, 0.0))
	if gap == INF:
		return INF
	var commit := gap - br.ai_commit
	var grav := absf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))
	var pace := 0.85 + skill * 0.25
	var v := maxf(k.fwd_speed, 0.0)
	while u < gap:
		var g: TrackPath = br if u >= 0.0 else p
		var i := br.index_at(u) if u >= 0.0 else p.index_at(br.fork_s + u)
		var a := -grav * g.fwd[i].y
		if v < k.max_speed:
			a += LIP_PACE * 15.0 * k.accel_mult * (0.25 + 0.75 * clampf(1.0 - pow(v / k.max_speed, 2.2), 0.0, 1.0))
		var du := minf(2.0, gap - u)
		v = sqrt(maxf(v * v + 2.0 * a * du, 0.0))
		if u < commit:
			v = minf(v, g.speed[i] * pace)
		u += du
	return v


## Can this kart still swing onto branch br before the roads part, `past` metres past its fork?
## The arc from where it is, the way it moves, to the branch's road 5 m before its nose must not
## ask for more than TURN_IN_MAX of sideways acceleration at the speed it takes that bit of the
## branch with (it brakes for it). Looked at over the first half of the stretch both roads share
## (before the fork the main road still bends the kart its own way; later a bot giving up would
## swerve across the gore).
func _can_turn_in(k: Kart, br: TrackBranch, past: float) -> bool:
	var u := br.fork_nose_u - 5.0
	if past < 0.0 or past > br.fork_nose_u * 0.5:
		return true
	var j := br.index_at(u)
	var up := br.up[j]
	var v := k.linear_velocity - up * k.linear_velocity.dot(up)
	var sp := minf(v.length(), br.speed[j] * (0.85 + skill * 0.25))
	if sp < 8.0:
		return true
	# the nearest spot across the branch's road there, short of its edges by a kart's width
	var room := maxf(br.width[j] * 0.5 - 2.0, 0.0)
	var to := br.center_at(u) - k.global_position
	to += br.right[j] * clampf(-to.dot(br.right[j]), -room, room)
	to -= up * to.dot(up)
	return sp * sp * 2.0 * sin(minf(v.angle_to(to), PI * 0.5)) / maxf(to.length(), 1.0) <= TURN_IN_MAX


## The least speed for a branch's jump (its need plus LIP_MARGIN) on its run-up from the commit
## point, while the bot is on that branch or about to take it; 0 elsewhere.
func _jump_floor(k: Kart, commit: float) -> float:
	var b := int(_ahead(k, commit).x)
	if b < 0:
		return 0.0
	var br := k.track.path.branches[b]
	if br.need_speed <= 0.0 or _to_gap(k, br) > commit:
		return 0.0
	return br.need_speed + LIP_MARGIN


## Stuck on a wall or a prop (slower than STUCK_V for STUCK_T with the throttle down): a try backs
## off with the wheels on one lock so the nose swings off the wall towards the road ahead (for at most
## BACK_T, and no further once there is a wall right behind it or no ground: the void past a deck's
## edge, a liquid), then pulls away that way (PULL_T). The next try takes the other lock; when
## UNSTICK_TRIES have failed the kart asks for the scanner (Kart.unstick, which also holds the stall
## rescue off while a try is under way). Not in a pipe: the kart slides back to its lane there.
## True while a try drives the kart.
func _unstick(k: Kart, delta: float, driving: bool, to: Vector3) -> bool:
	if k.respawns != _unstick_respawns or k.state != Kart.State.NORMAL or k.geo().mag[k.route_index] > 0.0:
		_unstick_respawns = k.respawns
		_try = 0
		_tries = 0
		_stuck_t = 0.0
		k.unstick = Kart.Unstick.NONE
		return false
	_try_t += delta
	if _try == 1:
		var turned := absf(_side_angle(k, _way)) < 0.35 and k.global_position.distance_to(_stuck_pos) > 1.5
		if _try_t > BACK_T or turned or not _room_behind(k):
			_try = 2
			_try_t = 0.0
		return true
	if _try == 2:
		if _try_t < PULL_T and k.fwd_speed < 8.0:
			return true
		_try = 0
		k.unstick = Kart.Unstick.NONE
	if _tries > 0 and k.total_progress > _stuck_at + 10.0:
		_tries = 0
	_stuck_t = _stuck_t + delta if driving and k.speed < STUCK_V else 0.0
	if _stuck_t < STUCK_T:
		return false
	_stuck_t = 0.0
	if _tries >= UNSTICK_TRIES:
		k.unstick = Kart.Unstick.GAVE_UP
		return false
	_tries += 1
	if _tries == 1:
		_stuck_at = k.total_progress
		_way = _way_out(k, to)
		var side := _side_angle(k, _way)
		_lock = -signf(side) if absf(side) > 0.05 else 1.0
	else:
		_lock = -_lock
	_stuck_pos = k.global_position
	_try = 1
	_try_t = 0.0
	k.unstick = Kart.Unstick.TRYING
	return true


## Signed angle from the kart's nose to `dir` (positive: to its right), as drive() steers.
func _side_angle(k: Kart, dir: Vector3) -> float:
	return atan2(dir.dot(k.global_basis.x), dir.dot(-k.global_basis.z))


## Which way the nose should point to get going again: towards the point the bot steers for (`to`
## from the kart), but along the wall in front of it rather than into it, and a little away from it.
func _way_out(k: Kart, to: Vector3) -> Vector3:
	var up := k.geo().up[k.route_index]
	var way := (to - up * to.dot(up)).normalized()
	var n := _wall_ahead(k)
	if n != Vector3.ZERO:
		way -= n * minf(way.dot(n), 0.0)
		way += n * 0.5
	way -= up * way.dot(up)
	return way.normalized() if way.length() > 0.05 else n


## The kart's nose level with its road (a kart stuck nose-in may be pitched up the wall).
func _level_fwd(k: Kart) -> Vector3:
	var up := k.geo().up[k.route_index]
	var fwd := -k.global_basis.z
	fwd -= up * fwd.dot(up)
	return fwd.normalized() if fwd.length() > 0.2 else -k.global_basis.z


## The normal of what the nose is up against (a wall, a barrier, a prop), level with its road;
## ZERO when nothing is within a metre and a half of it.
func _wall_ahead(k: Kart) -> Vector3:
	var space := k.get_world_3d().direct_space_state
	var up := k.geo().up[k.route_index]
	var fwd := _level_fwd(k)
	var from := k.global_position + up * 0.6
	var reach := k.spec.box_size.z * 0.5 + 1.5
	for turn: float in [0.0, -0.5, 0.5]:
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd.rotated(up, turn) * reach,
				Game.LAYER_WORLD | Game.LAYER_PROP, [k.get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			n -= up * n.dot(up)
			if n.length() > 0.1:
				return n.normalized()
	return Vector3.ZERO


## Room to back into, level with its road: no wall right behind the kart, and ground under the spot
## it backs onto (not the void past a deck's edge, not a liquid).
func _room_behind(k: Kart) -> bool:
	var space := k.get_world_3d().direct_space_state
	var up := k.geo().up[k.route_index]
	var back := -_level_fwd(k)
	var half := k.spec.box_size.z * 0.5
	var from := k.global_position + up * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, from + back * (half + 0.7), Game.LAYER_WORLD | Game.LAYER_PROP, [k.get_rid()])
	if not space.intersect_ray(q).is_empty():
		return false
	var spot := k.global_position + back * (half + 1.5)
	q = PhysicsRayQueryParameters3D.create(spot + up * 1.5, spot - up * 3.0, Game.LAYER_WORLD, [k.get_rid()])
	var ground := space.intersect_ray(q)
	if ground.is_empty():
		return false
	var at: Vector3 = ground["position"]
	var liq := k.track.liquid_at(at, k.route_index, k.geo())
	return liq.y <= 0.0 or at.y > liq.x


func _has_boost(k: Kart) -> bool:
	return k.roulette <= 0.0 and k.item in BOOSTS


## The branch a boost is being saved for: one this kart is on or heading into whose jump
## needs more than its top speed, with that jump still ahead, or a boost-gated fork up to
## HOLD_FOR_FORK metres ahead not decided yet (the boost is what lets it take that one); -1 for none.
func _boost_jump(k: Kart) -> int:
	var p := k.track.path
	for b in p.branches.size():
		var br := p.branches[b]
		if not (br.need_boost or br.need_speed > k.max_speed * 0.97):
			continue
		if k.route == b and br.gap_ahead(k.route_u) < INF:
			return b
		var to_fork := fposmod(br.fork_s - k.lap_progress, p.length)
		if k.route < 0 and _plan_now.get(b, false):
			var past := fposmod(k.lap_progress - br.fork_s, p.length)
			if to_fork <= 140.0 or past < br.fork_nose_u:
				return b
		# kept on the main road or on another branch on the way there
		elif k.route != b and br.need_boost and to_fork <= HOLD_FOR_FORK \
				and not _plan.has(b + 1000 * (k.lap + (1 if k.lap_progress > br.fork_s else 0))):
			return b
	return -1


## Metres along the planned road from the kart to the first jump gap of a branch it is on or
## heading into.
func _to_gap(k: Kart, br: TrackBranch) -> float:
	if k.route == br.index:
		return br.gap_ahead(k.route_u)
	var p := k.track.path
	var past := fposmod(k.lap_progress - br.fork_s, p.length)
	if past < br.fork_nose_u:
		return br.gap_ahead(past)
	return fposmod(br.fork_s - k.lap_progress, p.length) + br.gap_ahead(0.0)


## What the track hazards ahead advise (HazardDirector.advice) on the road this bot plans to
## drive; {} on a track without any.
func _hazard_advice(k: Kart, sp: float) -> Dictionary:
	var hz := k.track.hazards
	if hz == null or hz.list.is_empty():
		return {}
	return hz.advice(k, k.lap_progress, sp, _plan_now)


## Does this bot take a hazard's advice on this approach? Rolled once per hazard and
## approach: better drivers mostly do, and the speed caps a little more often.
func _obeys(id: int, skill_bonus := 0.0) -> bool:
	var e: Array = _hz_obey.get(id, [])
	if e.is_empty() or _clock > float(e[1]):
		e = [_rng.randf() < clampf(0.2 + skill * 0.7 + skill_bonus, 0.0, 0.97), _clock + 8.0]
		_hz_obey[id] = e
	return e[0]


## A hazard's gun has locked on: one dodge roll per lock (a quick lane change, sometimes a
## brake tap that lets the burst fly past ahead).
func _dodge(k: Kart, delta: float) -> void:
	_dodge_t = maxf(_dodge_t - delta, 0.0)
	_brake_t = maxf(_brake_t - delta, 0.0)
	if k.hazard_lock > 0.0 and k.hazard_lock < 0.6 and not _dodged:
		_dodged = true
		if _rng.randf() < clampf((skill - 0.8) * 3.0, 0.05, 0.6):
			_lane_target = lane + (3.2 if lane <= 0.0 else -3.2)
			_lane_t = 1.2
			_dodge_t = 1.2
			if _rng.randf() < 0.4:
				_brake_t = 0.35
	elif k.hazard_lock <= 0.0:
		_dodged = false
	if _dodge_t > 0.0:
		lane = lerpf(lane, _lane_target, minf(1.0, delta * 4.0))


func _player(k: Kart) -> Kart:
	for n in k.get_tree().get_nodes_in_group("karts"):
		if (n as Kart).is_player:
			return n
	return null


func _want_item(k: Kart, delta: float) -> bool:
	if k.item == "" or k.roulette > 0.0:
		return false
	# a boost saved for a jump that needs one: fired 20-45 m before the gap once out of a bend
	# (at the latest 26 m before it), so it is not spent turning; where the branch commits later
	# (a bend near its kicker) no earlier than 5 m before that and at the latest there
	if k.item in BOOSTS:
		var hold := _boost_jump(k)
		if hold >= 0:
			var br := k.track.path.branches[hold]
			var to_gap := _to_gap(k, br)
			return to_gap >= minf(20.0, br.ai_commit - 6.0) and to_gap <= minf(45.0, br.ai_commit + 5.0) \
					and (absf(k.in_steer) < 0.3 or to_gap < minf(26.0, br.ai_commit))
	_item_wait -= delta
	if _item_wait > 0.0:
		return false
	var use := false
	match k.item:
		"battery", "battery3", "hev":
			use = absf(k.in_steer) < 0.3
		"manhack", "manhack3", "canister":
			use = k.place > 1
		"rollermine":
			use = _someone(k, 5.0, 60.0)
		"gravgun":
			use = _someone(k, 2.0, 18.0)
		"barrel", "melon", "melon3", "hopper":
			use = _someone(k, -40.0, -3.0) or _item_wait < -6.0
		"cball":
			use = _someone(k, 5.0, 70.0)
		"saw":
			use = _someone(k, 4.0, 60.0)
		"headcrab":
			# not the moment it drops: wait until there is someone close ahead to jump on
			use = k.place > 1 and ((_item_wait < -2.5 and not Items.crab_targets(k).is_empty()) or _item_wait < -15.0)
		"xenport":
			use = absf(k.in_steer) < 0.4
	if use:
		_item_wait = _rng.randf_range(0.6, 2.5)
	return use


func _someone(k: Kart, from: float, to: float) -> bool:
	for n in k.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == k:
			continue
		var d := o.total_progress - k.total_progress
		if d > from and d < to:
			return true
	return false
