class_name TurretHazard
extends ShooterHazard
## Bullet turrets: the Combine floor turret (CT17 checkpoint), the HL1 sentry gun
## (Surface Tension camp) and the HL1 ceiling turret (Black Mesa storage hall), which
## drops out of the ceiling when a kart comes near and pulls back up into it after.

## Rig bones and muzzle (model space, the barrel's end at rest) of each turret model: a spec
## may leave them out, and a fallback model always uses these.
const RIGS := {
	"combine_turrets/floor_turret": {"rig": {"yaw": "Leftright", "pitch": "Gun", "spin": "Barrel"},
		"muzzle": [0.12, 1.34, 0.4]},
	"hl1/sentry": {"rig": {"yaw": "Dummy02", "pitch": "Dummy04", "spin": "Cylinder01"}, "muzzle": [0.0, 1.33, 0.22]},
	"hl1/turret": {"rig": {"yaw": "Dummy02", "pitch": "Dummy03", "spin": "Bone18"}, "muzzle": [0.0, 0.55, 0.9]},
}
## Sounds per model: each a list of choices, then what every install already has.
const SETS := {
	"combine_turrets/floor_turret": {
		"ping": [["npc/turret_floor/ping.wav"], ["npc/scanner/scanner_blip1.wav"]],
		"lock": [["npc/turret_floor/active.wav"], ["npc/roller/code2.wav"]],
		"fire": [["npc/turret_floor/shoot1.wav", "npc/turret_floor/shoot2.wav", "npc/turret_floor/shoot3.wav"],
			["weapons/irifle/irifle_fire2.wav"]],
		"cool": [["npc/turret_floor/retract.wav"], ["npc/scanner/cbot_servoscared.wav"]],
		"deploy": [["npc/turret_floor/deploy.wav"], ["buttons/lever7.wav"]],
		"per_shot": true, "flash": "materials/effects/combinemuzzle2.png", "tracer": Color(0.65, 0.85, 1.0)},
	"hl1/turret": {
		"ping": [["hl1src/turret/tu_ping.wav"], ["npc/scanner/scanner_blip1.wav"]],
		"lock": [["hl1src/turret/tu_alert.wav"], ["ambient/alarms/scanner_alert_pass1.wav"]],
		"spin_up": [["hl1src/turret/tu_spinup.wav"], ["weapons/gauss/chargeloop.wav"]],
		"fire": [["hl1src/turret/tu_fire1.wav"], ["weapons/irifle/irifle_fire2.wav"]],
		"cool": [["hl1src/turret/tu_spindown.wav"], ["npc/scanner/cbot_servoscared.wav"]],
		"deploy": [["hl1src/turret/tu_deploy.wav"], ["buttons/lever7.wav"]],
		"retract": [["hl1src/turret/tu_retract.wav"], ["buttons/lever7.wav"]],
		"per_shot": false, "flash": "materials/effects/muzzleflash1.png", "tracer": Color(1.0, 0.85, 0.5)},
	"hl1/sentry": {
		"ping": [["hl1src/turret/tu_ping.wav"], ["npc/scanner/scanner_blip1.wav"]],
		"lock": [["hl1src/turret/tu_alert.wav"], ["ambient/alarms/scanner_alert_pass1.wav"]],
		"spin_up": [["hl1src/turret/tu_spinup.wav"], []],
		"fire": [["hl1src/weapons/hks1.wav", "hl1src/weapons/hks2.wav", "hl1src/weapons/hks3.wav"],
			["weapons/irifle/irifle_fire2.wav"]],
		"cool": [["hl1src/turret/tu_spindown.wav"], ["npc/scanner/cbot_servoscared.wav"]],
		"per_shot": true, "flash": "materials/effects/muzzleflash1.png", "tracer": Color(1.0, 0.85, 0.5)},
}
const RICOCHETS := [["weapons/fx/rics/ric1.wav", "weapons/fx/rics/ric2.wav", "weapons/fx/rics/ric3.wav",
	"weapons/fx/rics/ric4.wav", "weapons/fx/rics/ric5.wav"], ["physics/metal/metal_solid_impact_bullet1.wav",
	"physics/metal/metal_solid_impact_bullet2.wav", "physics/metal/metal_solid_impact_bullet3.wav"]]
const NEAR_MISS := [["weapons/fx/nearmiss/bulletltor03.wav", "weapons/fx/nearmiss/bulletltor05.wav",
	"weapons/fx/nearmiss/bulletltor07.wav"], ["physics/surfaces/sand_impact_bullet1.wav"]]
const DEPLOY_T := 0.6       # the ceiling turret drops out in this long
const DEPLOY_NEAR := 55.0   # ... when a kart is this close
const DEPLOY_HOLD := 3.0    # and goes back up this long after the last one left
const DEPLOY_DROP := 1.25   # how far it drops (model metres): put away, its lid is flush with the mount

var _snd := {}
var _set := {}
var _deploy := 1.0          # 0 put away, 1 out (only the ceiling turret moves)
var _away_t := 0.0
var _ric_t := 0.0


func model_rig(key: String) -> Dictionary:
	return RIGS.get(key, {})


func build() -> void:
	super()
	_set = SETS.get(model_key, SETS["hl1/sentry"])
	for k in ["ping", "lock", "spin_up", "fire", "cool", "deploy", "retract"]:
		_snd[k] = sounds(_set.get(k, []))
	_snd["ric"] = sounds(RICOCHETS)
	_snd["near"] = sounds(NEAR_MISS)
	if p["mount"] == "ceiling":
		_deploy = 0.0
	pose()


func tick(t: float, dt: float) -> void:
	_ric_t -= dt
	if p["mount"] == "ceiling":
		_tick_deploy(dt)
		if _deploy < 1.0:
			# folded away: nothing to aim with until it is out
			_now += dt
			pose()
			return
	super(t, dt)


## The ceiling turret drops out of the ceiling when a kart comes near, and back up after.
func _tick_deploy(dt: float) -> void:
	var near := false
	for k in all_karts():
		if k.global_position.distance_to(muzzle) < DEPLOY_NEAR:
			near = true
			break
	_away_t = 0.0 if near else _away_t + dt
	var want := 1.0 if near or _away_t < DEPLOY_HOLD else 0.0
	if want > _deploy and _deploy == 0.0:
		play(_snd["deploy"], muzzle, 0.0, 14.0)
	elif want < _deploy and _deploy == 1.0:
		play(_snd["retract"], muzzle, 0.0, 14.0)
	_deploy = move_toward(_deploy, want, dt / DEPLOY_T)


func pose() -> void:
	if sk == null:
		return
	if p["mount"] != "ceiling":
		super()
		return
	# put away, the whole turret (lid on top) is pulled back into its mount, as in Half-Life
	var drop := Transform3D(Basis(), _m2s.basis * Vector3(0.0, -DEPLOY_DROP * (1.0 - smoothstep(0.0, 1.0, _deploy)), 0.0))
	var yd := HazardRig.turn(sk, _yaw_b, _m2s.basis * Vector3.UP, yaw_now, drop)
	var pd := HazardRig.turn(sk, _pitch_b, _m2s.basis * Vector3.RIGHT, -pitch_now, yd)
	HazardRig.turn(sk, _spin_b, _m2s.basis * Vector3.BACK, _spin, pd)


func on_ping() -> void:
	play(_snd["ping"], muzzle, -4.0, 14.0)


func on_lock() -> void:
	play(_snd["lock"], muzzle, 0.0, 18.0)
	play(_snd["spin_up"], muzzle, -2.0, 14.0)


func on_fire() -> void:
	if not _set.get("per_shot", true):
		play(_snd["fire"], muzzle, 2.0, 30.0)


func on_cool() -> void:
	play(_snd["cool"], muzzle, -2.0, 14.0)


func shot_fx(end: Vector3, victim: Kart) -> void:
	if not visual:
		return
	var from := muzzle_now()
	var dir := (end - from).normalized()
	Effects.tracer(get_parent(), from, end, _set.get("tracer", Color(1, 0.9, 0.6)))
	Effects.muzzle(get_parent(), from, dir, str(_set["flash"]), 0.9 * float(p["scale"]))
	if _set.get("per_shot", true):
		play(_snd["fire"], from, 0.0, 30.0)
	if victim:
		Effects.sparks(get_parent(), end, 0.6)
	else:
		Effects.dust(get_parent(), end, 0.6)
		if _ric_t <= 0.0:
			_ric_t = 0.15
			play(_snd["ric"], end, -4.0, 10.0)


func near_miss(at: Vector3) -> void:
	play(_snd["near"], at, -2.0, 6.0)
