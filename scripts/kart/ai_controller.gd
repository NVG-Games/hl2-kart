class_name AIController
extends RefCounted
## Computer racer: follows the precomputed racing line with a personal lane
## offset, brakes for corners, drifts long bends, uses items sensibly and
## rubber-bands against the player.

var skill := 0.9
var lane := 0.0
var _lane_target := 0.0
var _lane_t := 0.0
var _item_wait := 0.0
var _drift_hold := 0.0
var _reverse_t := 0.0
var _rng := RandomNumberGenerator.new()


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
	var s := k.lap_progress
	var i_here := path.index_at(s)
	var off_lat := absf(path.lateral(pos, i_here))
	var half := path.width[i_here] * 0.5
	var look := clampf(6.0 + sp * 0.32, 6.0, 16.0)
	# tighter look-ahead through bends so the line does not cut over kerbs
	var bend := absf(path.fwd[i_here].signed_angle_to(path.fwd[path.index_at(s + 25.0)], Vector3.UP))
	look *= clampf(1.0 - bend * 0.9, 0.5, 1.0)
	var ti := path.index_at(s + look)
	var target := path.line_at(s + look) + path.right[ti] * lane
	if off_lat > half - 0.5:
		# off the tarmac: head straight back to the centre line
		look = 10.0
		ti = path.index_at(s + look)
		target = path.center_at(s + look)
	# dodge karts directly ahead
	for n in k.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == k:
			continue
		var d := o.global_position - pos
		var ahead := d.dot(-k.global_basis.z)
		if ahead > 0.0 and ahead < 14.0 and absf(d.dot(k.global_basis.x)) < 2.6:
			target += path.right[ti] * (2.0 if d.dot(k.global_basis.x) < 0.0 else -2.0)
	var to := target - pos
	var fwd := -k.global_basis.z
	var right := k.global_basis.x
	var ang := atan2(to.dot(right), to.dot(fwd))
	var steer := clampf(ang * 2.2, -1.0, 1.0)
	# corner speed: min of the racing-line speed table over the braking window
	var vt := 999.0
	var win := int((sp * 1.6 + 10.0) / path.step) + 1
	var i0 := path.index_at(s)
	for j in win:
		vt = minf(vt, path.speed[path.wi(i0 + j)] + j * path.step * 0.35)
	var top := k.max_speed
	vt = minf(vt * (0.85 + skill * 0.25), top)
	# rubber band toward the player
	var player := _player(k)
	if player and player != k:
		var gap := k.total_progress - player.total_progress
		if gap > 60.0:
			vt *= 0.9
		elif gap < -80.0:
			vt *= 1.07
			k.boost_time = maxf(k.boost_time, 0.0)
	# the jump: commit to full speed
	if path.gap[path.index_at(s + 40.0)] == 1 or path.gap[path.index_at(s + 15.0)] == 1:
		vt = 999.0
		steer = clampf(atan2((path.center_at(s + 30.0) - pos).dot(right), (path.center_at(s + 30.0) - pos).dot(fwd)) * 2.5, -1.0, 1.0)
	var throttle := 1.0
	var brake := 0.0
	if sp > vt + 2.0:
		throttle = 0.0
		brake = clampf((sp - vt) / 6.0, 0.0, 1.0)
	elif sp > vt:
		throttle = 0.3
	# long bends: drift for a mini-turbo
	var drift := false
	if skill > 0.97 and sp > 20.0 and absf(ang) > 0.14 and absf(ang) < 0.4 and k.grounded and bend > 0.5:
		_drift_hold = 0.7
	if _drift_hold > 0.0:
		_drift_hold -= delta
		drift = absf(steer) > 0.15 or k.drifting
		if k.drifting and k.drift_level >= 1 and absf(ang) < 0.08:
			drift = false
			_drift_hold = 0.0
	# stuck: back off the wall
	if k.speed < 1.5 and k.state == Kart.State.NORMAL and k.race and k.race.racing:
		_reverse_t += delta
	else:
		_reverse_t = maxf(0.0, _reverse_t - delta * 2.0)
	if _reverse_t > 1.3:
		throttle = 0.0
		brake = 1.0
		steer = -steer
		if _reverse_t > 2.6:
			_reverse_t = 0.0
	k.in_throttle = throttle
	k.in_brake = brake
	k.in_steer = steer
	k.in_drift = drift
	k.in_item = _want_item(k, delta)
	k.in_look_back = false


func _player(k: Kart) -> Kart:
	for n in k.get_tree().get_nodes_in_group("karts"):
		if (n as Kart).is_player:
			return n
	return null


func _want_item(k: Kart, delta: float) -> bool:
	if k.item == "" or k.roulette > 0.0:
		return false
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
		"barrel":
			use = _someone(k, -40.0, -3.0) or _item_wait < -6.0
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
