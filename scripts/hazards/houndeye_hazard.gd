class_name HoundeyeHazard
extends Hazard
## A pack of houndeyes on a Xen verge. When a kart comes they chirp, turn to the road and
## charge up (squashing faster and faster while a blue light grows), then release a sonic
## blast that spins out the karts within `radius` and pushes them away. Every peer runs
## its own pack against the karts it sees; each owner judges its own karts.

enum S { IDLE, NOTICE, CHARGE, COOL }
const BLAST := Color(0.6, 0.85, 1.0)
const NOTICE_T := 0.35

var st := S.IDLE
var st_t := 0.0
var _members: Array = []      # [model, yaw at rest, yaw facing the road]
var _light: OmniLight3D
var _crackle := 0.0
var _idle_t := 3.0
var _look := 0.0
var _snd := {}


func defaults() -> Dictionary:
	return {"members": [], "side": 1, "scale": 1.5, "radius": 10.0, "notice": 30.0, "charge": 1.3, "cool": 3.5,
		"push": 0.45, "lift": 0.1, "effect": "spin", "model": "hl1/houndeye"}


func build() -> void:
	_snd["alert"] = sounds([["hl1src/houndeye/he_alert1.wav", "hl1src/houndeye/he_alert2.wav"],
		["npc/headcrab/alert1.wav"]])
	_snd["attack"] = sounds([["hl1src/houndeye/he_attack1.wav"], ["weapons/gauss/chargeloop.wav"]])
	_snd["blast"] = sounds([["hl1src/houndeye/he_blast1.wav", "hl1src/houndeye/he_blast2.wav",
		"hl1src/houndeye/he_blast3.wav"], ["npc/roller/mine/rmine_explode_shock1.wav"]])
	_snd["idle"] = sounds([["hl1src/houndeye/he_idle1.wav"], ["npc/headcrab/idle3.wav"]])
	if not visual or not Game.models.has(str(p["model"])):
		return
	for m in p["members"]:
		var node := Game.spawn_model(str(p["model"]))
		add_child(node)
		node.global_position = Vector3(m[0], m[1], m[2])
		node.scale = Vector3.ONE * float(p["scale"])
		var road := float(m[3])
		node.global_rotation.y = road + (rnd(_members.size(), 7) - 0.5) * 2.4
		_members.append([node, node.global_rotation.y, road])
	_light = light(BLAST, 14.0, 0.0)
	if _light:
		_light.position = Vector3.UP * 1.2


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
				Effects.sparks(get_parent(), global_position + Vector3.UP * 0.8, 0.3, BLAST)
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
				var at: Vector3 = (_members[i][0] as Node3D).global_position
				get_tree().create_timer(0.1 * i).timeout.connect(func(): play(_snd["alert"], at, 0.0, 14.0))
		S.CHARGE:
			play(_snd["attack"], global_position, 2.0, 18.0)


func _blast() -> void:
	director.note(self, "fire")
	var up := path.up[path.index_at(s)]
	if visual:
		play(_snd["blast"], global_position, 6.0, 18.0)
		Effects.shock_ring(get_parent(), global_position, up, float(p["radius"]), Color(BLAST, 0.9), 0.35)
		Effects.sparks(get_parent(), global_position + up, 1.0, BLAST)
		if _light:
			_light.light_energy = 10.0
		var player: Kart = director.race.player if director.race else null
		if player and player.global_position.distance_to(global_position) < 15.0:
			for cam in get_tree().get_nodes_in_group("race_camera"):
				cam.shake(0.4)
	blast(global_position, float(p["radius"]), str(p["effect"]), float(p["push"]), float(p["lift"]))


func _animate(t: float, dt: float) -> void:
	var charge := clampf(st_t / tm("charge"), 0.0, 1.0) if st == S.CHARGE else 0.0
	if _light:
		var want := 6.0 * charge * (0.7 + 0.3 * sin(t * 40.0)) if st == S.CHARGE else 0.0
		_light.light_energy = move_toward(_light.light_energy, want, dt * 40.0)
	var alert := st == S.NOTICE or st == S.CHARGE
	_look += dt
	for i in _members.size():
		var node: Node3D = _members[i][0]
		# facing the road while they attack, looking about otherwise
		var yaw: float = _members[i][2] if alert else float(_members[i][1]) + sin(_look * 0.4 + i * 2.1) * 0.6
		node.global_rotation.y = lerp_angle(node.global_rotation.y, yaw, minf(1.0, dt * 6.0))
		# squash and stretch: slow breathing, faster and deeper while charging
		var rate := 2.0 + 16.0 * charge * charge
		var depth := 0.03 + 0.12 * charge
		var sq := 1.0 + sin(t * rate + i) * depth
		node.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq)) * float(p["scale"])
	if st != S.CHARGE:
		_idle_t -= dt
		if _idle_t <= 0.0:
			_idle_t = 4.0 + rnd(int(t), 3) * 6.0
			play(_snd["idle"], global_position, -6.0, 12.0)


func sleep() -> void:
	if st != S.COOL:
		st = S.IDLE
		st_t = 0.0


## While they are about to blast: keep to the far side of the road.
func advice(_k: Kart, at_s: float, _speed: float) -> Dictionary:
	if (st != S.NOTICE and st != S.CHARGE) or ahead(at_s, s) > 45.0:
		return {}
	return {"lat": -signf(float(p["side"])) * (half_width(s) - 2.5), "w": 0.7}


func is_active(_t: float) -> bool:
	return st == S.CHARGE
