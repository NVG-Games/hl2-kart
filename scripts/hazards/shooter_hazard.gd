class_name ShooterHazard
extends Hazard
## Lock-on shooters (Combine floor turret, HL1 sentry and ceiling turret, Xen
## vortigaunt). Every peer runs its own copy against every kart it sees; only the
## karts this peer drives can be hit, so there is no network traffic. The aim lags
## the target by `stale` seconds: hold your line and you are hit; brake, boost or
## change lane during the burst and it misses.

enum S { IDLE, LOCK, FIRE, COOL }
const HISTORY := 1.0      # seconds of the target's track kept for the lagging aim
const YAW_RATE := 4.2     # rad/s (240 deg/s)
const PITCH_RATE := 2.1   # rad/s (120 deg/s)
const SPIN_RATE := 30.0   # barrel spin while firing (rad/s)

var st := S.IDLE
var st_t := 0.0
var target: Kart
var model: Node3D
var sk: Skeleton3D
var model_key := ""
var muzzle := Vector3.ZERO       # world, at rest: shots and line-of-sight rays start here
var facing := Vector3.FORWARD    # world, horizontal
var laser: MeshInstance3D
var yaw_now := 0.0
var pitch_now := 0.0
var _model_xf := Transform3D.IDENTITY   # the model under this node (flip, scale, lift)
var _muzzle_m := Vector3.ZERO    # model space
var _hist: Array = []            # [[time, pos, vel], ...] of the target, last HISTORY seconds
var _shot_i := 0
var _landed := false             # this burst has hit a kart: the rest of it does no harm
var _scan := 0.0
var _now := 0.0                  # local seconds (the aim history only)
var _ping_t := 0.0
var _near_t := 0.0
var _rig := {}
var _yaw_b := -1
var _pitch_b := -1
var _spin_b := -1
var _m2s := Transform3D.IDENTITY
var _yaw_pivot := Vector3.ZERO   # model space
var _pitch_pivot := Vector3.ZERO
var _spin := 0.0
var _spin_v := 0.0
var _flash: OmniLight3D
var _eye: MeshInstance3D         # a small light at the muzzle: amber searching, red locked on


func defaults() -> Dictionary:
	return {"mount": "floor", "model": "hl1/sentry", "fallback": "", "scale": 1.0, "range": 40.0, "cone": 60.0,
		"lock": 0.9, "burst": 0.6, "shots": 6, "cool": 5.0, "stale": 0.5, "hit_r": 1.4, "effect": "spin",
		"weapon": "ray", "rig": {}, "muzzle": [0.0, 1.2, 0.4], "laser": [1.0, 0.12, 0.1]}


## Rig bones and muzzle of a model the spec did not describe (its fallback). Subclasses
## return {"rig": {...}, "muzzle": [x, y, z]} for the models they know.
func model_rig(_key: String) -> Dictionary:
	return {}


func build() -> void:
	facing = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	model_key = pick_model([p["model"], p["fallback"]])
	# the spec's rig and muzzle are for its own model; a fallback model brings what this
	# script knows about it
	var known := model_rig(model_key)
	var spec: Dictionary = def.get("p", {})
	var own := model_key == str(p["model"])
	_rig = spec["rig"] if own and spec.has("rig") else known.get("rig", p["rig"])
	var m: Array = spec["muzzle"] if own and spec.has("muzzle") else known.get("muzzle", p["muzzle"])
	_muzzle_m = Vector3(m[0], m[1], m[2])
	var sc := float(p["scale"])
	var lift := -Game.model_aabb(model_key).position.y * sc if model_key != "" else 0.0
	# a ceiling mount is the model turned half a turn about Z: (x, y, z) -> (-x, -y, z)
	var flip := Basis(Vector3.BACK, PI) if p["mount"] == "ceiling" else Basis()
	_model_xf = Transform3D(flip.scaled(Vector3.ONE * sc), flip * Vector3(0.0, lift, 0.0))
	muzzle = global_transform * (_model_xf * _muzzle_m)
	if not visual:
		return
	if model_key != "":
		model = Game.spawn_model(model_key)
		add_child(model)
		model.transform = _model_xf
		sk = HazardRig.skeleton(model)
	if sk:
		_m2s = HazardRig.model_to_skeleton(model, sk)
		_yaw_b = HazardRig.bone(sk, str(_rig.get("yaw", "")))
		_pitch_b = HazardRig.bone(sk, str(_rig.get("pitch", "")))
		_spin_b = HazardRig.bone(sk, str(_rig.get("spin", "")))
		_yaw_pivot = _pivot(_yaw_b)
		_pitch_pivot = _pivot(_pitch_b)
	if sight_laser():
		var c: Array = p["laser"]
		laser = Effects.beam_node(Color(c[0], c[1], c[2], 0.85), 0.09, "materials/sprites/laserbeam.png", true)
		add_child(laser)
		laser.visible = false
		_eye = glow("materials/sprites/redglow1.png", 0.6 * sc, Color(1.0, 0.6, 0.1))
	_flash = light(Color(1.0, 0.8, 0.5), 7.0, 0.0)


## A bone's rest origin in model space (the muzzle height when there is no such bone).
func _pivot(bi: int) -> Vector3:
	if bi < 0:
		return Vector3(0.0, _muzzle_m.y, 0.0)
	return _m2s.affine_inverse() * sk.get_bone_global_rest(bi).origin


func lock_time() -> float:
	return tm("lock")


func tick(t: float, dt: float) -> void:
	_now += dt
	st_t += dt
	_tick_fx(dt)
	if t < 0.0:
		_sweep(t, dt)
		return
	match st:
		S.IDLE:
			_sweep(t, dt)
			_search_ping(dt)
			_scan -= dt
			if _scan <= 0.0:
				_scan = 0.15
				var k := _pick()
				if k:
					target = k
					_hist.clear()
					_enter(S.LOCK)
		S.LOCK:
			if not _still_valid(dt):
				_enter(S.COOL)
				return
			_record()
			var aim := _stale_point()
			_aim(aim, dt)
			_show_laser(aim)
			if not target.remote:
				target.hazard_lock = maxf(lock_time() - st_t, 0.01)
				target.hazard_lock_from = muzzle
			if st_t >= lock_time():
				_enter(S.FIRE)
		S.FIRE:
			if not is_instance_valid(target):
				_enter(S.COOL)
				return
			_record()
			var aim := _stale_point()
			_aim(aim, dt)
			_show_laser(aim)
			var shots: int = maxi(int(p["shots"]), 1)
			var every: float = float(p["burst"]) / shots
			while _shot_i < shots and st_t >= _shot_i * every:
				_shoot(aim)
				_shot_i += 1
			if _shot_i >= shots:
				_enter(S.COOL)
		S.COOL:
			_sweep(t, dt)
			if st_t >= tm("cool"):
				_enter(S.IDLE)


func _enter(next: S) -> void:
	if st == S.LOCK and next != S.FIRE and is_instance_valid(target) and not target.remote:
		target.hazard_lock = 0.0
	st = next
	st_t = 0.0
	match next:
		S.LOCK:
			director.note(self, "warn", target)
			on_lock()
		S.FIRE:
			_shot_i = 0
			_landed = false
			director.note(self, "fire", target)
			on_fire()
		S.COOL:
			if laser:
				laser.visible = false
			on_cool()
		S.IDLE:
			target = null


## Candidates: targetable karts (local or remote) in range, in the cone, in sight and
## coming this way (or already close). The nearest wins; ties go to the lower racer index.
func _pick() -> Kart:
	var best: Kart = null
	var bd := INF
	var cone := deg_to_rad(float(p["cone"]))
	for k in all_karts():
		if not targetable(k):
			continue
		var d := k.global_position - muzzle
		var dist := d.length()
		if dist > float(p["range"]):
			continue
		var flat := Vector3(d.x, 0.0, d.z)
		if flat.length() > 0.5 and facing.angle_to(flat.normalized()) > cone:
			continue
		if k.velocity().dot(-d) <= 0.0 and dist > 12.0:
			continue
		if not _los(k):
			continue
		if dist < bd - 0.01 or (absf(dist - bd) <= 0.01 and best and k.racer_index < best.racer_index):
			best = k
			bd = dist
	return best


func _still_valid(dt: float) -> bool:
	if not is_instance_valid(target) or not targetable(target):
		return false
	var d := target.global_position - muzzle
	if d.length() > float(p["range"]) * 1.15:
		return false
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() > 0.5 and facing.angle_to(flat.normalized()) > deg_to_rad(float(p["cone"])) * 1.2:
		return false
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.15
		return _los(target)
	return true


func _los(k: Kart) -> bool:
	var q := PhysicsRayQueryParameters3D.create(muzzle, k.global_position + k.grav_up * 0.8, Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _record() -> void:
	_hist.append([_now, target.global_position, target.velocity()])
	while _hist.size() > 2 and _now - float(_hist[0][0]) > HISTORY:
		_hist.pop_front()


## Where the target would be now had it kept doing what it did `stale` seconds ago.
func _stale_point() -> Vector3:
	var want := _now - tm("stale")
	var e: Array = _hist[0]
	for h in _hist:
		if float(h[0]) <= want:
			e = h
	return (e[1] as Vector3) + (e[2] as Vector3) * (_now - float(e[0])) + target.grav_up * 0.7


func _shoot(aim: Vector3) -> void:
	var dir := (aim - muzzle).normalized()
	var end := muzzle + dir * float(p["range"]) * 1.3
	var q := PhysicsRayQueryParameters3D.create(muzzle, end, Game.LAYER_WORLD)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		end = wall["position"]
	var victim: Kart = null
	for k in local_karts():
		var c := k.global_position + k.grav_up * 0.7
		var d := (c - Geometry3D.get_closest_point_to_segment(c, muzzle, end)).length() if p["weapon"] == "ray" \
			else c.distance_to(aim)
		# one kart per burst: a burst that hit someone does not mow down the pack behind
		if d < float(p["hit_r"]) and not _landed and hit(k, str(p["effect"]), dir * k.mass * 1.5):
			victim = k
			_landed = true
			break
		if d < 4.0 and k.is_player and _now > _near_t:
			_near_t = _now + 0.3
			director.note(self, "near", k)
			near_miss(c)
	_spin_v = SPIN_RATE
	if _flash:
		_flash.global_position = muzzle_now()
		_flash.light_energy = 3.0
	shot_fx(end, victim)


## Head and barrels: turn towards a world point at the rig's speed.
func _aim(point: Vector3, dt: float) -> void:
	var local := _model_xf.affine_inverse() * (global_transform.affine_inverse() * point)
	var want_yaw := atan2(local.x - _yaw_pivot.x, local.z - _yaw_pivot.z)
	var hor := Vector2(local.x - _pitch_pivot.x, local.z - _pitch_pivot.z).length()
	_turn_to(want_yaw, atan2(local.y - _pitch_pivot.y, hor), dt)


## Idle: the head sweeps across half the cone, following the clock.
func _sweep(t: float, dt: float) -> void:
	_turn_to(sin(t * 0.7 + float(seed_v % 100)) * deg_to_rad(float(p["cone"])) * 0.5, 0.0, dt)


func _turn_to(want_yaw: float, want_pitch: float, dt: float) -> void:
	var lim := deg_to_rad(float(p["cone"])) * 1.3
	yaw_now = move_toward(yaw_now, clampf(want_yaw, -lim, lim), YAW_RATE * dt)
	pitch_now = move_toward(pitch_now, clampf(want_pitch, -1.0, 1.0), PITCH_RATE * dt)
	pose()


## Applies yaw_now, pitch_now and the barrel spin to the rig.
func pose() -> void:
	if sk == null:
		return
	var yd := HazardRig.turn(sk, _yaw_b, _m2s.basis * Vector3.UP, yaw_now)
	var pd := HazardRig.turn(sk, _pitch_b, _m2s.basis * Vector3.RIGHT, -pitch_now, yd)
	HazardRig.turn(sk, _spin_b, _m2s.basis * Vector3.BACK, _spin, pd)


## Where the barrel's end is now (it turns with the head).
func muzzle_now() -> Vector3:
	if model == null:
		return muzzle
	return HazardRig.follow(model, sk, _pitch_b if _pitch_b >= 0 else _yaw_b, _muzzle_m)


func _show_laser(aim: Vector3) -> void:
	if laser == null:
		return
	laser.visible = true
	Effects.place_beam(laser, muzzle_now(), aim)


func _tick_fx(dt: float) -> void:
	if _flash:
		_flash.light_energy = maxf(_flash.light_energy - dt * 40.0, 0.0)
	if _eye:
		_eye.global_position = muzzle_now()
		var locked := st == S.LOCK or st == S.FIRE
		(_eye.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.1, 0.05) if locked \
			else Color(1.0, 0.6, 0.1, 0.5 + 0.3 * sin(_now * 4.0))
		# locked on: the eye flares, throbbing faster than the search light
		_eye.scale = Vector3.ONE * (1.7 + 0.5 * sin(_now * 24.0) if locked else 1.0)
	_spin_v = move_toward(_spin_v, 0.0, dt * SPIN_RATE * 0.6)
	_spin = fmod(_spin + _spin_v * dt, TAU)


func _search_ping(dt: float) -> void:
	_ping_t -= dt
	if _ping_t > 0.0:
		return
	_ping_t = 1.2
	for k in all_karts():
		if k.global_position.distance_to(muzzle) < 60.0:
			on_ping()
			return


func sleep() -> void:
	_enter(S.IDLE)
	if laser:
		laser.visible = false


func is_active(_t: float) -> bool:
	return st == S.LOCK or st == S.FIRE


# ---------------------------------------------------------------- subclass hooks
## A laser sight shows the lock (guns); a vortigaunt shows its charge instead.
func sight_laser() -> bool:
	return true


## The search ping (a kart within 60 m).
func on_ping() -> void:
	pass


## Locked on: lock sound, laser, wind-up.
func on_lock() -> void:
	pass


## The burst starts.
func on_fire() -> void:
	pass


## Lost the target or done shooting.
func on_cool() -> void:
	pass


## A shot: tracer or bolt, muzzle flash, impact at `end`; `victim` is a kart it hit here.
func shot_fx(_end: Vector3, _victim: Kart) -> void:
	pass


## A shot just missed the local player (within 4 m).
func near_miss(_at: Vector3) -> void:
	pass
