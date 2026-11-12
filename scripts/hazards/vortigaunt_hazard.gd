class_name VortigauntHazard
extends ShooterHazard
## A Xen alien slave on the verge: it turns to the kart it picked, raises its arms while
## green arcs crackle between its hands (the lock), then throws one lightning bolt at
## where the kart would be. Hold your line and it hits; swerve and it scorches the road.

const BOLT := Color(0.45, 1.0, 0.55)

var _snd := {}
var _hands: Array[int] = []
var _glow: OmniLight3D
var _crackle := 0.0
var _aim_at := Vector3.ZERO


func defaults() -> Dictionary:
	var d := super()
	d.merge({"model": "hl1/islave", "scale": 1.3, "shots": 1, "burst": 0.0, "weapon": "bolt", "hit_r": 1.8,
		"effect": "shock", "range": 36.0, "cone": 75.0, "lock": 1.0, "cool": 3.0, "muzzle": [0.0, 1.25, 0.5],
		"laser": [0.3, 1.0, 0.4]}, true)
	return d


func build() -> void:
	super()
	_snd["alert"] = sounds([["hl1src/aslave/slv_alert1.wav", "hl1src/aslave/slv_alert3.wav"],
		["ambient/energy/spark1.wav", "ambient/energy/spark2.wav"]])
	_snd["charge"] = sounds([["hl1src/debris/zap1.wav"], ["ambient/energy/zap1.wav"]])
	_snd["bolt"] = sounds([["hl1src/weapons/electro4.wav", "hl1src/weapons/electro5.wav"], ["weapons/gauss/fire1.wav"]])
	_snd["hit"] = sounds([["hl1src/debris/zap4.wav"], ["ambient/energy/zap5.wav"]])
	if sk:
		for side in ["L", "R"]:
			_hands.append(BipedPose.limb(sk, side + "_Hand"))
	_glow = light(BOLT, 8.0, 0.0)
	if _glow:
		_glow.position = _muzzle_m * float(p["scale"])


func sight_laser() -> bool:
	return false


## The model turns as a whole (it has no turret bones); the arms rise while it charges.
func pose() -> void:
	if model == null:
		return
	model.rotation.y = yaw_now
	if sk == null:
		return
	sk.reset_bone_poses()
	BipedPose.standing(sk)
	# up through the charge, held a moment after the bolt, then lowered
	var raise := 0.0
	match st:
		S.LOCK:
			raise = clampf(st_t / maxf(lock_time(), 0.1), 0.0, 1.0)
		S.FIRE:
			raise = 1.0
		S.COOL:
			raise = clampf(1.5 - st_t * 2.0, 0.0, 1.0)
	if raise <= 0.0:
		return
	var up := BipedPose.U * (0.2 + 0.5 * raise) + BipedPose.F * (0.9 - 0.3 * raise)
	for side in [["L", 1.0], ["R", -1.0]]:
		var sg: float = side[1]
		BipedPose.aim(sk, side[0] + "_UpperArm", side[0] + "_Forearm", up + BipedPose.L * sg * 0.35)
		BipedPose.aim(sk, side[0] + "_Forearm", side[0] + "_Hand", up + BipedPose.F * 0.4 - BipedPose.L * sg * 0.2)


func _hands_at() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for bi in _hands:
		if bi >= 0:
			out.append(sk.global_transform * sk.get_bone_global_pose(bi).origin)
	if out.is_empty():
		out.append(muzzle_now())
	return out


func tick(t: float, dt: float) -> void:
	super(t, dt)
	if not visual or not awake:
		return
	var charging := st == S.LOCK
	if _glow:
		_glow.light_energy = lerpf(_glow.light_energy, 4.0 * clampf(st_t / lock_time(), 0.0, 1.0) if charging else 0.0,
			minf(1.0, dt * 10.0))
	if charging:
		_crackle -= dt
		if _crackle <= 0.0:
			_crackle = 0.15
			var hands := _hands_at()
			for h in hands:
				Effects.sparks(get_parent(), h, 0.25, BOLT)
			if hands.size() == 2:
				Effects.lightning(get_parent(), hands[0], hands[1], BOLT, 0.12, 4, 0.15)


func on_lock() -> void:
	play(_snd["alert"], muzzle, 2.0, 16.0)
	play(_snd["charge"], muzzle, -2.0, 12.0)


func _shoot(aim: Vector3) -> void:
	_aim_at = aim
	super(aim)


func shot_fx(_end: Vector3, victim: Kart) -> void:
	if not visual:
		return
	# the bolt ends on the kart it struck, else where it was aimed (it never stops halfway)
	var at := victim.global_position + victim.grav_up * 0.7 if victim else _aim_at
	for h in _hands_at():
		Effects.lightning(get_parent(), h, at, BOLT, 0.25, 9, 0.7)
	Effects.sparks(get_parent(), at, 1.0, BOLT)
	play(_snd["bolt"], muzzle, 4.0, 24.0)
	play(_snd["hit"], at, 0.0, 14.0)
	if not victim:
		var dec := Decal.new()
		dec.texture_albedo = SourceMaterials.tex("materials/decals/scorch1.png")
		dec.size = Vector3(2.5, 2.0, 2.5)
		dec.modulate = Color(0.5, 1.0, 0.6, 0.85)
		get_parent().add_child(dec)
		dec.global_position = at - Vector3.UP * 0.6
		var tw := dec.create_tween()
		tw.tween_interval(6.0)
		tw.tween_property(dec, "modulate:a", 0.0, 2.0)
		tw.tween_callback(dec.queue_free)
