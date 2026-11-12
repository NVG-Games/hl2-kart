class_name StriderHazard
extends Hazard
## A Combine strider beside the road fires its warp cannon at the leader once a cycle.
## The server (or the offline game) picks the target and the aim point when the charge
## starts and tells everyone (one "aim" event); the cannon goes off at t_fire on the
## shared clock on every peer, and each kart's owner judges its own karts. Its three
## legs are posed by IK, so the feet stay planted while it sways and crouches to fire.

const GLOW := Color(0.45, 0.75, 1.0)
const LEGS := ["Right", "Left", "Hind"]
const FEET := {"Left": 0, "Right": 1, "Hind": 2}   # order of p["feet"] (tools/hazards.py)
const CROUCH := 1.5

var model: Node3D
var sk: Skeleton3D
var _m2s := Transform3D.IDENTITY
var _body_b := -1
var _neck_b := -1
var _head_b := -1
var _gun_b := -1
var _gun_m := Vector3(0.03, 10.36, 2.38)   # BigGun, model space
var _legs: Array = []                     # [upper, lower, hip, knee, foot, foot target, l1, l2] (skeleton space)
var _aims := {}                           # cycle -> [t_fire, aim point, lap s, lateral]
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _head := Vector2.ZERO                 # yaw, pitch the head has turned
var _crouch := 0.0
var _idle_t := 4.0
var _snd := {}


func defaults() -> Dictionary:
	return {"zone": [s - 40.0, s + 110.0], "scale": 1.15, "cycle": 9.0, "phase": 4.0, "charge": 1.8, "radius": 6.5,
		"push": 0.3, "lift": 0.6, "lead": 0.9, "effect": "tumble", "feet": [0.0, 0.0, 0.0]}


func build() -> void:
	aims_all = true
	_snd["alert"] = sounds([["npc/strider/striderx_alert4.wav"], ["npc/strider/striderx_alert2.wav"]])
	_snd["charge"] = sounds([["npc/strider/charging.wav"]])
	_snd["fire"] = sounds([["npc/strider/fire.wav"]])
	_snd["idle"] = sounds([["npc/strider/strider_hunt1.wav", "npc/strider/strider_hunt2.wav", "npc/strider/creak1.wav",
		"npc/strider/creak2.wav"], ["npc/strider/strider_step1.wav"]])
	if not visual or not Game.models.has("combine_strider"):
		return
	model = Game.spawn_model("combine_strider")
	add_child(model)
	model.scale = Vector3.ONE * float(p["scale"])
	sk = HazardRig.skeleton(model)
	var gun := HazardRig.attachment("combine_strider", "BigGun")
	if not gun.is_empty():
		_gun_m = gun[0]
	if sk:
		_m2s = HazardRig.model_to_skeleton(model, sk)
		_body_b = HazardRig.bone(sk, "Body_Bone")
		_neck_b = HazardRig.bone(sk, "Neck_Bone")
		_head_b = HazardRig.bone(sk, "Head_Bone")
		_gun_b = HazardRig.bone(sk, gun[1]) if not gun.is_empty() else _head_b
		_setup_legs()
	_beam = Effects.beam_node(Color(GLOW, 0.0), 0.12, "materials/effects/bluelaser1.png")
	add_child(_beam)
	_ring = Effects.ground_ring(self, global_position, Vector3.UP, float(p["radius"]), Color(0.3, 0.9, 1.0, 0.0))
	_ring.visible = false
	_glow = glow("materials/effects/strider_muzzle.png", 2.0, GLOW)
	_glow.visible = false
	_light = light(GLOW, 16.0, 0.0)


## Hip, knee and foot of each leg at rest; the foot's target sits on the ground under it
## (tools/hazards.py measured how far each foot's ground is above or below the body's).
func _setup_legs() -> void:
	var feet: Array = p["feet"]
	var sc := float(p["scale"])
	for leg in LEGS:
		var up := HazardRig.bone(sk, "Leg_%s_Bone" % leg)
		var low := HazardRig.bone(sk, "Leg_%s_Bone1" % leg)
		var foot := HazardRig.bone(sk, "Foot_%s" % leg)
		if up < 0 or low < 0 or foot < 0:
			continue
		var hip := sk.get_bone_global_rest(up).origin
		var kn := sk.get_bone_global_rest(low).origin
		var ft := sk.get_bone_global_rest(foot).origin
		var target := ft + _m2s.basis * Vector3(0.0, float(feet[FEET[leg]]) / sc, 0.0)
		_legs.append([up, low, hip, kn, ft, target, hip.distance_to(kn), kn.distance_to(ft)])


func _cycle_at(t: float) -> int:
	return int(floor((t - float(p["phase"])) / tm("cycle")))


func _cycle_start(c: int) -> float:
	return float(p["phase"]) + c * tm("cycle")


func tick(t: float, dt: float) -> void:
	if t >= 0.0 and director.authority():
		var c := _cycle_at(t)
		if crossed(_cycle_start(c), t) and not _aims.has(c):
			_pick(c)
	var active: Array = []
	for c in _aims.keys():
		var e: Array = _aims[c]
		if crossed(e[0], t):
			_fire(e[1])
		if t > float(e[0]) + 1.0:
			_aims.erase(c)
		elif t < float(e[0]):
			active = e
	if visual:
		_animate(t, dt, active)


## The authority picks the leader coming onto the deck and aims where it will be.
func _pick(c: int) -> void:
	var zone: Array = p["zone"]
	var best: Kart = null
	for k in all_karts():
		if not targetable(k) or not on_road(k, float(zone[0]) - 40.0, float(zone[1]) - 25.0):
			continue
		if k.velocity().dot(path.fwd[k.path_index]) < 2.0:
			continue
		if best == null or k.total_progress > best.total_progress:
			best = k
	if best == null:
		return
	var t_fire := _cycle_start(c) + tm("charge")
	var pred := best.global_position + best.velocity() * tm("charge") * float(p["lead"])
	var i := path.closest(pred, best.path_index)
	var at_s := path.progress(pred, i)
	if not director.in_span(at_s, float(zone[0]), float(zone[1])):
		at_s = float(zone[0]) if ahead(at_s, float(zone[0])) < ahead(float(zone[1]), at_s) else float(zone[1])
	var hw := half_width(at_s) - 1.5
	var aim := road_point(at_s, clampf(path.lateral(pred, i), -hw, hw))
	send("aim", [c, t_fire, aim.x, aim.y, aim.z])


func on_event(kind: String, args: Array) -> void:
	if kind != "aim" or args.size() < 5:
		return
	var aim := Vector3(float(args[2]), float(args[3]), float(args[4]))
	var i := path.closest(aim)
	_aims[int(args[0])] = [float(args[1]), aim, path.progress(aim, i), path.lateral(aim, i)]
	director.note(self, "warn")
	play(_snd["alert"], global_position + Vector3.UP * 14.0, 6.0, 60.0)
	play(_snd["charge"], gun_at(), 4.0, 40.0)


func _fire(aim: Vector3) -> void:
	director.note(self, "fire")
	if visual:
		Effects.beam(get_parent(), gun_at(), aim, "materials/effects/blueblacklargebeam.png", Color(0.7, 0.85, 1.0), 1.2, 0.2)
		Effects.explosion(get_parent(), aim, 1.3, null, false)
		play(_snd["fire"], gun_at(), 8.0, 60.0)
	blast(aim, float(p["radius"]), str(p["effect"]), float(p["push"]), float(p["lift"]))


## The cannon's muzzle now (it moves with the head).
func gun_at() -> Vector3:
	if model == null:
		return global_transform * (_gun_m * float(p["scale"]))
	return HazardRig.follow(model, sk, _gun_b, _gun_m)


func _animate(t: float, dt: float, active: Array) -> void:
	if model == null:
		return
	var charge := 0.0
	var focus: Vector3
	if not active.is_empty():
		charge = clampf(1.0 - (float(active[0]) - t) / tm("charge"), 0.0, 1.0)
		focus = active[1]
	else:
		focus = _nearest_kart()
	_crouch = move_toward(_crouch, CROUCH * charge, dt * 2.0)
	_pose(t, focus, dt)
	var gun := gun_at()
	_beam.visible = charge > 0.0
	_ring.visible = charge > 0.0
	_glow.visible = charge > 0.0
	if charge > 0.0:
		Effects.place_beam(_beam, gun, focus)
		_beam.set_instance_shader_parameter("col", Color(GLOW, 0.3 + 0.5 * charge))
		Effects.place_ring(_ring, focus, path.up[path.index_at(float(active[2]))], float(p["radius"]))
		var pulse := 0.5 + 0.5 * sin(t * TAU * (2.0 + 6.0 * charge))
		_ring.set_instance_shader_parameter("col", Color(0.3, 0.9, 1.0, 0.35 + 0.55 * pulse))
		_glow.global_position = gun
		_glow.scale = Vector3.ONE * (0.5 + 2.5 * charge)
	if _light:
		_light.global_position = gun
		_light.light_energy = 6.0 * charge
	_idle_t -= dt
	if _idle_t <= 0.0:
		_idle_t = 5.0 + rnd(int(t)) * 6.0
		play(_snd["idle"], global_position + Vector3.UP * 12.0, 0.0, 40.0)


func _nearest_kart() -> Vector3:
	var best := road_point(s, 0.0)
	var bd := 150.0
	for k in all_karts():
		var d := k.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = k.global_position
	return best


## Body sway and crouch with the legs solved to the planted feet; the head turns the
## cannon towards `focus`.
func _pose(t: float, focus: Vector3, dt: float) -> void:
	if sk == null:
		return
	var sc := float(p["scale"])
	var sway := Vector3(sin(t * 0.37) * 0.25, -_crouch, cos(t * 0.29) * 0.15) / sc
	var d := Transform3D(Basis(), _m2s.basis * sway)
	if _body_b >= 0:
		sk.set_bone_global_pose(_body_b, d * sk.get_bone_global_rest(_body_b))
	for leg in _legs:
		var hip: Vector3 = d * (leg[2] as Vector3)
		var foot: Vector3 = leg[5]
		var rest_knee: Vector3 = leg[3]
		var mid: Vector3 = ((leg[2] as Vector3) + (leg[4] as Vector3)) * 0.5
		var pole := d * (rest_knee + (rest_knee - mid) * 2.0)
		var kn := HazardRig.knee(hip, foot, leg[6], leg[7], pole)
		HazardRig.point(sk, leg[0], rest_knee - (leg[2] as Vector3), kn - hip)
		HazardRig.point(sk, leg[1], (leg[4] as Vector3) - rest_knee, foot - kn)
	# the head: yaw at the neck, pitch at the head, from the cannon's rest direction
	var local := model.global_transform.affine_inverse() * focus
	var pivot := _m2s.affine_inverse() * sk.get_bone_global_rest(_head_b).origin if _head_b >= 0 else _gun_m
	var rest_dir := _gun_m - pivot
	var want := local - pivot
	var want_yaw := atan2(want.x, want.z) - atan2(rest_dir.x, rest_dir.z)
	var want_pitch := atan2(want.y, Vector2(want.x, want.z).length()) - atan2(rest_dir.y, Vector2(rest_dir.x, rest_dir.z).length())
	_head.x = move_toward(_head.x, clampf(wrapf(want_yaw, -PI, PI), -1.2, 1.2), dt * 1.2)
	_head.y = move_toward(_head.y, clampf(want_pitch, -0.9, 0.5), dt * 0.8)
	var nd := HazardRig.turn(sk, _neck_b, _m2s.basis * Vector3.UP, _head.x, d)
	HazardRig.turn(sk, _head_b, _m2s.basis * Vector3.RIGHT, -_head.y, nd)


func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	for e in _aims.values():
		var left := float(e[0]) - t
		if left <= 0.0 or left > 2.5:
			continue
		var r := float(p["radius"]) + 2.0
		var lat := kart_lat(k)
		if absf(fposmod(at_s + speed * left - float(e[2]) + path.length * 0.5, path.length) - path.length * 0.5) > r \
				or absf(lat - float(e[3])) > r:
			continue
		var hw := half_width(float(e[2])) - 2.5
		var away := float(e[3]) - (r + 0.5) if float(e[3]) > 0.0 else float(e[3]) + r + 0.5
		return {"lat": clampf(away, -hw, hw), "w": 0.85}
	return {}


func is_active(t: float) -> bool:
	for e in _aims.values():
		if t < float(e[0]) and t > float(e[0]) - tm("charge"):
			return true
	return false
