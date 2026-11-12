extends Node
## Branch data and route tracking check (headless). For every track given (a JSON path, or a
## track id under res://assets/track/) it checks the branch fields of the track data, then
## drives a ghost kart (the real Kart progress and route code, no physics) along every route
## at 1 m steps: the main loop for two laps, main -> branch -> main through each branch, into
## a branch and out again backwards, a 30 m sideways hop onto a branch's road, and a computer
## driver (pure pursuit of its look-ahead) that takes or skips each fork, and carried along a
## branch while the scanner has it. It asserts that the route switches once per junction (fork
## side: before the nose + 15 m; never while rescued), that only a pass taken at the fork is
## credited to the race (Race.on_branch: the SHORTCUT! cheer, the results), that the lap
## progress never jumps or runs backwards on a forward drive, and that laps count once per
## loop; then puts the ghost back after falls on each branch (respawn policy: a retry has to be
## winnable from a standstill) and through a Xen portal.
## usage: godot --headless --path . res://tests/branch_check.tscn -- <track.json | track id> [...]

const DT := 1.0 / 30.0  # ghost time per 1 m step (30 m/s)
const LIFT := 0.6  # kart origin above the road
## a hop lands on a branch at most this far above the main road (tools/track_gen.py NOSE_DY: a
## kart is thrown up ~1.6 m at most, Kart.TUMBLE_UP); onto one below it, from any height
const HOP_UP := 2.5

var _fails := 0
var _checks := 0


## Stands in for Race on the ghost: the branch passes it is credited with (Kart._leave_branch).
class Passes extends Node:
	var got: Array = []

	func on_branch(_k: Kart, b: int, done: bool) -> void:
		got.append([b, done])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = PackedStringArray(["ct17"])
	for a in args:
		var file := a if a.ends_with(".json") else "res://assets/track/%s.json" % a
		var d: Dictionary = Game.load_json(file)
		if d.is_empty():
			_fail(a, "could not load " + file)
			continue
		_check_track(a.get_file(), d)
	print("branch_check: %d checks, %d failures" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check_track(label: String, d: Dictionary) -> void:
	var trk := Track.new()
	trk.data = d
	trk.path = Track.make_path(d)
	var p := trk.path
	print("== %s: lap %.0f m, %d branches" % [label, p.length, p.branches.size()])
	for b in p.branches:
		_check_data(label, p, b, d["branches"][b.index])
	var k := _ghost(trk)
	_drive_main(label, k)
	for b in p.branches:
		_drive_branch(label, k, b)
		_drive_reverse(label, k, b)
		_drive_hop(label, k, b)
		_drive_rescued(label, k, b)
		_drive_bot(label, k, b, true)
		_drive_bot(label, k, b, false)
		_respawns(label, k, b)
		_teleports(label, k, b)
	k.race.free()
	k.queue_free()
	trk.free()


# ---------------------------------------------------------------- data contract (4.1)
func _check_data(label: String, p: TrackPath, b: TrackBranch, raw: Dictionary) -> void:
	var tag := "%s/%s" % [label, b.id]
	var pd: Dictionary = raw["path"]
	var n: int = pd["center"].size()
	for key in ["line", "fwd", "right", "up", "width", "speed", "gap", "pit", "mag", "theme", "s_main"]:
		_expect(tag, pd.has(key) and pd[key].size() == n, "path.%s has %d samples" % [key, n])
	_expect(tag, not bool(pd.get("closed", true)), "path.closed is false")
	_expect(tag, b.fork_s > 0.04 * p.length and b.fork_s < b.merge_s and b.merge_s < 0.96 * p.length,
		"0.04 L < fork_s %.1f < merge_s %.1f < 0.96 L" % [b.fork_s, b.merge_s])
	_expect(tag, absf(b.fork_i * p.step - b.fork_s) < p.step and absf(b.merge_i * p.step - b.merge_s) < p.step,
		"fork_i / merge_i match fork_s / merge_s (index * length / n)")
	var mono := true
	var slope := 0.0
	for i in b.n - 1:
		mono = mono and b.s_main[i + 1] >= b.s_main[i]
		slope = maxf(slope, (b.s_main[i + 1] - b.s_main[i]) / maxf(b.u_of(i + 1) - b.u_of(i), 0.01))
	_expect(tag, mono, "s_main is monotone")
	_expect(tag, absf(b.s_main[0] - b.fork_s) < 0.5 and absf(b.s_main[b.n - 1] - b.merge_s) < 0.5, "s_main runs fork_s .. merge_s")
	print("   %s: %.1f m (main %.1f m), noses at %.1f / %.1f m, s_main slope up to %.2f, need %.1f m/s%s" % [
		tag, b.length, b.merge_s - b.fork_s, b.fork_nose_u, b.merge_nose_u, slope, b.need_speed, " (boost)" if b.need_boost else ""])
	var c0 := b.center[0].distance_to(p.center_at(b.fork_s))
	var c1 := b.center[b.n - 1].distance_to(p.center_at(b.merge_s))
	_expect(tag, c0 <= p.width[b.fork_i] * 0.5 + 0.5, "branch starts on the main road (%.1f m from its centre)" % c0)
	_expect(tag, c1 <= p.width[b.merge_i] * 0.5 + 0.5, "branch ends on the main road (%.1f m from its centre)" % c1)
	_expect(tag, b.gap[0] == 0 and b.gap[b.n - 1] == 0 and b.mag[0] == 0.0 and b.mag[b.n - 1] == 0.0, "no gap or tube at either end")
	_expect(tag, b.fork_nose_u > 0.0 and b.fork_nose_u < b.merge_nose_u and b.merge_nose_u < b.length, "noses inside the branch, in order")
	_expect(tag, b.step * (b.n - 2) <= b.length + 0.01 and b.step * (b.n - 1) >= b.length - 0.01, "samples evenly spaced (step %.3f)" % b.step)
	# the switch at a nose must not move the lap position: s_main is the main road's own there
	for nu in [b.fork_nose_u, b.merge_nose_u]:
		var q := b.center_at(nu)
		var i := p.closest(q, p.index_at(b.main_s(nu)) - 4)
		var ds := absf(p.progress(q, i) - b.main_s(nu))
		_expect(tag, ds < 2.0, "s_main matches the main road at the nose u=%.0f (off by %.2f m)" % [nu, ds])


# ---------------------------------------------------------------- ghost drives
## A kart with no body, shapes or controller: only its progress / route code runs. It counts as
## on its wheels, and a Passes stands in for the race.
func _ghost(trk: Track) -> Kart:
	var k := Kart.new()
	k.track = trk
	k.grounded = true
	k.race = Passes.new()
	k.freeze = true
	k.collision_layer = 0
	k.collision_mask = 0
	k.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(k)
	k.audio = KartAudio.new()
	k.add_child(k.audio)
	k.audio.setup(k)
	return k


## Put the ghost at lap metres s on the main road with fresh lap state.
func _reset(k: Kart, s: float, pos: Vector3) -> void:
	var p := k.track.path
	k.route = -1
	k.route_u = 0.0
	k._branch_fails.clear()
	(k.race as Passes).got.clear()
	k.global_position = pos
	k.route_index = p.closest(pos)
	k.lap = 0
	k._best_lap = -99
	k._last_s = fposmod(s, p.length)
	k._crossed_half = k._last_s > p.length * 0.5
	k._update_progress(DT)


func _main_at(p: TrackPath, s: float, lat := 0.0) -> Vector3:
	var i := p.index_at(s)
	return p.center_at(s) + p.right[i] * lat + p.up[i] * LIFT


func _branch_at(b: TrackBranch, u: float) -> Vector3:
	return b.center_at(u) + b.up[b.index_at(u)] * LIFT


## Drives the ghost through `pts`: returns {"switches": [[step, from, to, route_u]], "jump",
## "back", "laps"} and checks progress continuity; `forward` also requires it never to drop.
## A jump is a 1 m step that moves the progress 1.5 m more or less than the step before (the
## rate itself may change: a shortcut maps faster, the inside of a tight bend runs faster).
## From step `free_from` until the first route switch the progress may jump (a hop).
func _run(tag: String, k: Kart, pts: PackedVector3Array, forward: bool, free_from := -1) -> Dictionary:
	var switches: Array = []
	var worst := 0.0
	var worst_at := ""
	var back := 0.0
	var laps0 := k.lap
	var prev := k.total_progress
	var prev_dp := 1.0
	var prev_route := k.route
	var prev_u := k.route_u
	for j in pts.size():
		k.global_position = pts[j]
		k._update_progress(DT)
		var free := free_from >= 0 and j >= free_from and switches.is_empty()
		if k.route != prev_route:
			switches.append([j, prev_route, k.route, prev_u if prev_route >= 0 else k.route_u])
		var dp := prev_dp if free else k.total_progress - prev
		var over := absf(absf(dp) - absf(prev_dp)) - 1.5
		if over > worst:
			worst = over
			worst_at = "route %d at %.0f m" % [k.route, k.route_pos()]
		if forward and dp < back:
			back = dp
		prev = k.total_progress
		prev_dp = dp
		prev_route = k.route
		prev_u = k.route_u
	var r := {"switches": switches, "jump": worst, "back": back, "laps": k.lap - laps0}
	_expect(tag, worst <= 0.0, "lap progress never jumps (worst %.2f m over the limit%s)" % [worst,
			", " + worst_at if worst > 0.0 else ""])
	if forward:
		_expect(tag, back > -0.05, "progress never runs backwards (worst step %.2f m)" % back)
	return r


func _drive_main(label: String, k: Kart) -> void:
	var p := k.track.path
	var pts := PackedVector3Array()
	var s := 5.0
	while s < p.length * 2.0 + 10.0:
		pts.append(p.line_at(s) + p.up[p.index_at(s)] * LIFT)
		s += 1.0
	_reset(k, 4.0, pts[0])
	var r := _run(label + "/main", k, pts, true)
	_expect(label + "/main", (r["switches"] as Array).is_empty(), "stays on the main loop along its racing line (%d switches)" % (r["switches"] as Array).size())
	_expect(label + "/main", r["laps"] == 2, "two laps counted for two loops (%d)" % r["laps"])


## Along the fork-side edge into the branch, all of it, out along the merge-side edge, then on
## round the lap to the line and a little past it.
func _drive_branch(label: String, k: Kart, b: TrackBranch) -> void:
	var tag := "%s/%s/through" % [label, b.id]
	var p := k.track.path
	var off0 := b.side * (p.width[b.fork_i] - b.width[0]) * 0.5
	var off1 := b.merge_side * (p.width[b.merge_i] - b.width[b.n - 1]) * 0.5
	var pts := PackedVector3Array()
	var s := b.fork_s - 60.0
	while s < b.fork_s:
		pts.append(_main_at(p, s, off0 * clampf((s - b.fork_s + 60.0) / 30.0, 0.0, 1.0)))
		s += 1.0
	var u := 0.0
	while u < b.length:
		pts.append(_branch_at(b, u))
		u += 1.0
	s = b.merge_s
	while s < p.length + 10.0:
		pts.append(_main_at(p, s, off1 * clampf(1.0 - (s - b.merge_s) / 30.0, 0.0, 1.0)))
		s += 1.0
	_reset(k, b.fork_s - 61.0, pts[0])
	var r := _run(tag, k, pts, true)
	var sw: Array = r["switches"]
	_expect(tag, sw.size() == 2 and sw[0][2] == b.index and sw[1][2] == -1, "switches onto the branch and back once each (%s)" % str(sw))
	if sw.size() == 2:
		_expect(tag, sw[0][3] <= b.fork_nose_u + 15.0, "onto the branch at u=%.1f, before its nose %.1f + 15 m" % [sw[0][3], b.fork_nose_u])
		_expect(tag, sw[1][3] >= b.merge_nose_u - 15.0, "off the branch at u=%.1f, past its merge nose %.1f - 15 m" % [sw[1][3], b.merge_nose_u])
	_expect(tag, r["laps"] == 1, "one lap counted crossing the line (%d)" % r["laps"])
	var got: Array = (k.race as Passes).got
	_expect(tag, got == [[b.index, true]], "credited with one pass, completed (%s)" % str(got))


## Into the branch past its nose, back out through the fork the wrong way, then on along the
## main road's centre past the fork zone: off the branch once, never back onto it.
func _drive_reverse(label: String, k: Kart, b: TrackBranch) -> void:
	var tag := "%s/%s/reverse" % [label, b.id]
	var p := k.track.path
	var off0 := b.side * (p.width[b.fork_i] - b.width[0]) * 0.5
	var pts := PackedVector3Array()
	var s := b.fork_s - 40.0
	while s < b.fork_s:
		pts.append(_main_at(p, s, off0))
		s += 1.0
	var deep := minf(b.fork_nose_u + 25.0, b.merge_nose_u - 1.0)
	var u := 0.0
	while u < deep:
		pts.append(_branch_at(b, u))
		u += 1.0
	while u > 0.0:
		pts.append(_branch_at(b, u))
		u -= 1.0
	s = b.fork_s
	while s > b.fork_s - 40.0:
		pts.append(_main_at(p, s, off0 * clampf((s - b.fork_s + 40.0) / 20.0, 0.0, 1.0)))
		s -= 1.0
	while s < b.fork_s + 100.0:
		pts.append(_main_at(p, s))
		s += 1.0
	_reset(k, b.fork_s - 41.0, pts[0])
	var r := _run(tag, k, pts, false)
	var sw: Array = r["switches"]
	_expect(tag, sw.size() == 2 and sw[0][2] == b.index and sw[1][2] == -1, "in once, out once (%s)" % str(sw))
	_expect(tag, k.route == -1, "ends on the main road")


## On the main road level with the middle of the branch, a hop sideways onto the branch's
## road (a kart thrown over, or landing on the other road): the slow check finds it there.
func _drive_hop(label: String, k: Kart, b: TrackBranch) -> void:
	var tag := "%s/%s/hop" % [label, b.id]
	var p := k.track.path
	# the branch sample furthest from the main road, at most 30 m away and no more than HOP_UP
	# above it (no hop reaches a roof)
	var best_u := -1.0
	var best_d := 0.0
	var u := b.fork_nose_u + 10.0
	while u < b.merge_nose_u - 10.0:
		var q := b.center_at(u)
		var m := p.center_at(b.main_s(u))
		var d := Vector2(q.x, q.z).distance_to(Vector2(m.x, m.z))
		if d <= 30.0 and d > best_d and q.y - m.y < HOP_UP:
			best_d = d
			best_u = u
		u += 2.0
	if best_u < 0.0 or best_d < p.width[p.index_at(b.main_s(best_u))] * 0.5 + b.width[0] * 0.5 + 3.0:
		print("   %s: skipped (no stretch of the branch within 30 m of the main road, clear of it and within a hop's reach)" % tag)
		return
	var s0 := b.main_s(best_u)
	var pts := PackedVector3Array()
	var s := s0 - 40.0
	while s < s0:
		pts.append(_main_at(p, s))
		s += 1.0
	u = best_u
	while u < b.length:
		pts.append(_branch_at(b, u))
		u += 1.0
	s = b.merge_s
	while s < b.merge_s + 40.0:
		pts.append(_main_at(p, s))
		s += 1.0
	_reset(k, s0 - 41.0, pts[0])
	var r := _run(tag, k, pts, false, 40)
	var sw: Array = r["switches"]
	_expect(tag, sw.size() == 2 and sw[0][2] == b.index and sw[1][2] == -1, "found on the branch after a %.0f m hop, back on the main road at the merge (%s)" % [best_d, str(sw)])
	if not sw.is_empty():
		_expect(tag, sw[0][0] <= 40 + 12, "found within %d steps of the hop" % (sw[0][0] - 40))
	# landing on it further on than 15 m past its fork nose is not taking it: no pass (no
	# SHORTCUT!, nothing in the results)
	var got: Array = (k.race as Passes).got
	if not sw.is_empty() and float(sw[0][3]) > b.fork_nose_u + 15.0:
		_expect(tag, got.is_empty(), "no pass credited for landing on it at u=%.0f, past its nose %.1f + 15 m (%s)" % [
			sw[0][3], b.fork_nose_u, str(got)])


## The scanner has the kart (a fall, a sink) while it is carried past the branch's road: it never
## switches onto the branch, and no pass is credited (Kart._track_route).
func _drive_rescued(label: String, k: Kart, b: TrackBranch) -> void:
	var tag := "%s/%s/rescued" % [label, b.id]
	_reset(k, b.fork_s - 1.0, _branch_at(b, 0.0))
	k.state = Kart.State.RESPAWN
	var switched := false
	var u := 0.0
	while u < b.length:
		k.global_position = _branch_at(b, u)
		k._update_progress(DT)
		switched = switched or k.route != -1
		u += 1.0
	k.state = Kart.State.NORMAL
	var got: Array = (k.race as Passes).got
	_expect(tag, not switched and got.is_empty(), "carried all along the branch while rescued: stays on the main road, no pass (%s)" % str(got))


## A computer driver reduced to pure pursuit: an AIController with this fork decided either
## way steers the ghost 1 m per step at its look-ahead point (AIController._ahead), so the
## walker and the route tracker run together through the fork, the branch and the merge.
func _drive_bot(label: String, k: Kart, b: TrackBranch, take: bool) -> void:
	var tag := "%s/%s/bot_%s" % [label, b.id, "takes" if take else "skips"]
	var p := k.track.path
	var ai := AIController.new(1.0, 7)
	for c in p.branches:
		ai._plan[c.index] = take and c == b
	var s := b.fork_s - 150.0
	_reset(k, s - 1.0, p.line_at(s) + p.up[p.index_at(s)] * LIFT)
	# fast, and holding a battery for a jump that needs one; the ghost moves only by its steps (no
	# velocity left over from the tests before, which AIController._can_turn_in would read)
	k.fwd_speed = 28.0
	k.linear_velocity = Vector3.ZERO
	k.item = "battery" if take else ""
	var pts := PackedVector3Array()
	var pos := k.global_position
	var on_branch := false
	for j in int(b.merge_s - b.fork_s + 300.0):
		k.global_position = pos
		k._update_progress(DT)
		on_branch = on_branch or k.route == b.index
		ai._plan_forks(k)
		var a := ai._ahead(k, 12.0)
		var ga := p.geo(int(a.x))
		var aim := ga.line_at(a.y) + ga.up[ga.index_at(a.y)] * LIFT
		pos += (aim - pos).normalized()
		pts.append(pos)
	k.item = ""
	_reset(k, s - 1.0, pts[0])
	var r := _run(tag, k, pts, true)
	var sw: Array = r["switches"]
	if take:
		_expect(tag, sw.size() == 2 and sw[0][2] == b.index and sw[1][2] == -1, "follows the branch and rejoins (%s)" % str(sw))
	else:
		_expect(tag, sw.is_empty() and not on_branch, "stays on the main road (%s)" % str(sw))


## Falls on the branch: put back by its respawn policy (Kart._put_back). A "before" retry has to
## be winnable: from a standstill at the retry point a NORMAL buggy (the ghost) gets up to the
## jump's need_speed by the gap (Kart.retry_winnable); the game sends a kart that could not to
## the main road instead, and this fails until the track gives the retry a longer run-up (or
## the branch says "after" or "main").
func _respawns(label: String, k: Kart, b: TrackBranch) -> void:
	var tag := "%s/%s/respawn" % [label, b.id]
	var p := k.track.path
	var gs := b.gap_start_at_or_ahead(b.fork_nose_u, b.length)
	var u_fall := gs + 3.0 if gs < INF else (b.fork_nose_u + b.merge_nose_u) * 0.5
	# first fall
	_fall_at(k, b, u_fall)
	k._put_back(1.2)
	match b.respawn:
		"main":
			_expect(tag, k.route == -1, "policy main: back on the main road")
		"after":
			_expect(tag, k.route == b.index and k.route_u > u_fall and b.gap[b.index_at(k.route_u)] == 0, "policy after: past the gap (u=%.1f)" % k.route_u)
		_:
			var want := maxf((gs if gs < INF else u_fall - 12.0) - (b.retry_back if gs < INF else 0.0), b.fork_nose_u + 5.0)
			var winnable := gs == INF or k.retry_winnable(b, want, gs)
			if gs < INF:
				_expect(tag, winnable, "policy before: the retry from u=%.1f is winnable (%.0f m of run-up reach %.1f m/s from a standstill, the jump needs %.1f + %.1f)" % [
					want, gs - want, k.run_up_speed(b, want, gs), b.need_speed, Kart.RETRY_MARGIN])
			if not winnable:
				_expect(tag, k.route == -1, "an unwinnable retry: back on the main road instead")
			else:
				_expect(tag, k.route == b.index and absf(k.route_u - want) < 0.5, "policy before: retries from u=%.1f (at %.1f)" % [want, k.route_u])
				var c := b.center_at(k.route_u)
				_expect(tag, k.global_position.distance_to(c) < 4.0, "placed on the branch road (%.1f m from its centre line)" % k.global_position.distance_to(c))
				# second fall on the same pass: give up, main road 30 m behind (past a jump's gap
				# when that is too close in front to get up to speed for: Kart.past_gap)
				_fall_at(k, b, u_fall)
				k._put_back(1.2)
				var s_want := fposmod(k.past_gap(p, fposmod(b.main_s(u_fall) - 30.0, p.length)), p.length)
				var s_got := p.progress(k.global_position, p.closest(k.global_position))
				_expect(tag, k.route == -1 and absf(s_got - s_want) < 3.0, "second fall: main road at s=%.0f (at %.0f)" % [s_want, s_got])
	# a fall before the fork nose always goes back to the main road
	_fall_at(k, b, maxf(b.fork_nose_u - 4.0, 0.0))
	k._put_back(1.2)
	_expect(tag, k.route == -1, "a fall before the nose: back on the main road")
	_expect(tag, k._branch_fails.is_empty(), "fresh respawn policy after leaving the branch")


func _fall_at(k: Kart, b: TrackBranch, u: float) -> void:
	k.route = b.index
	k.route_index = b.index_at(u)
	k.route_u = u
	k.lap_progress = b.main_s(u)
	k.total_progress = k.lap_progress
	k.global_position = b.center_at(u) - Vector3.UP * 6.0


## The Xen portal on a branch: along it, or out past its merge; never into one from the main.
func _teleports(label: String, k: Kart, b: TrackBranch) -> void:
	var tag := "%s/%s/teleport" % [label, b.id]
	var p := k.track.path
	var u0 := b.fork_nose_u + 5.0
	_fall_at(k, b, u0)
	k.global_position = b.center_at(u0) + Vector3.UP * LIFT
	k.teleport_ahead(140.0)
	if u0 + 140.0 < b.length - 14.0 and b.gap_ahead(u0 + 140.0) > 12.0 and b.gap[b.index_at(u0 + 140.0)] == 0:
		_expect(tag, k.route == b.index and absf(k.route_u - u0 - 140.0) < 0.5, "140 m on along the branch (u=%.1f)" % k.route_u)
	else:
		_expect(tag, k.route == b.index or k.route == -1, "lands on the branch or past its merge (route %d)" % k.route)
	var g := k.geo()
	_expect(tag, g.gap[k.route_index] == 0 and g.on_road(k.global_position, k.route_index) < 1.0, "lands on a road, never in a gap")
	var s := b.fork_s - 100.0
	_reset(k, s, _main_at(p, s))
	k.teleport_ahead(140.0)
	_expect(tag, k.route == -1, "from the main road: never into the branch")
	# a kart taken over by a bot (Kart.make_local_bot) finds its route from scratch
	var at := p.locate(b.center_at((b.fork_nose_u + b.merge_nose_u) * 0.5) + Vector3.UP * LIFT)
	_expect(tag, at.x == b.index, "locate() finds a kart in the middle of the branch on it")


# ---------------------------------------------------------------- reporting
func _expect(tag: String, ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("   ok   %s: %s" % [tag, what])
	else:
		_fail(tag, what)


func _fail(tag: String, what: String) -> void:
	_fails += 1
	print("   FAIL %s: %s" % [tag, what])
