class_name ManhackProjectile
extends Node3D
## npc_manhack as a homing shell: flies along the racing line, then dives
## onto the next kart ahead.

var owner_kart: Kart
var target: Kart
var race
var s := 0.0
var speed := 42.0
var life := 14.0
var lateral := 0.0
var model: Node3D
var _blades: Array = []
var _snd: AudioStreamPlayer3D


func launch(k: Kart, r, forced_target: Kart = null) -> void:
	owner_kart = k
	race = r
	s = k.total_progress + 5.0
	lateral = k.track.path.lateral(k.global_position, k.path_index)
	target = forced_target if forced_target else next_ahead(k)
	model = Game.spawn_model("manhack")
	model.scale = Vector3.ONE * 1.6
	add_child(model)
	global_position = k.global_position + Vector3.UP * 1.8 - k.global_basis.z * 4.0
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = Game.stream("res://assets/sound/npc/manhack/mh_blade_loop1.wav")
	_snd.unit_size = 10.0
	_snd.bus = "SFX"
	add_child(_snd)
	_snd.play()
	var eng := AudioStreamPlayer3D.new()
	eng.stream = Game.stream("res://assets/sound/npc/manhack/mh_engine_loop1.wav")
	eng.unit_size = 8.0
	eng.bus = "SFX"
	add_child(eng)
	eng.play()
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.3, 0.2)
	glow.omni_range = 4.0
	glow.light_energy = 1.5
	add_child(glow)


static func next_ahead(from: Kart) -> Kart:
	var best: Kart = null
	var bd := INF
	for n in from.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == from or o.finished:
			continue
		var d := o.total_progress - from.total_progress
		if d > 0.0 and d < bd:
			bd = d
			best = o
	return best


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_die(false)
		return
	var path := owner_kart.track.path
	var pos := global_position
	var goal: Vector3
	if target and is_instance_valid(target) and target.global_position.distance_to(pos) < 30.0:
		goal = target.global_position + Vector3.UP * 1.0
	else:
		s += speed * delta
		lateral = lerpf(lateral, 0.0, delta * 0.5)
		var i := path.index_at(s)
		goal = path.line_at(s) + path.right[i] * lateral * 0.3 + path.up[i] * 1.6
		if target and is_instance_valid(target) and s > target.total_progress + 10.0:
			s = target.total_progress - 5.0
	var to := goal - pos
	var step := minf(to.length(), (speed + 8.0) * delta)
	if to.length() > 0.01:
		global_position = pos + to.normalized() * step
		var look := to.normalized()
		if absf(look.dot(Vector3.UP)) < 0.98:
			model.global_basis = Basis.looking_at(look, Vector3.UP).rotated(look, sin(Time.get_ticks_msec() * 0.02) * 0.3)
	for n in owner_kart.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == owner_kart and life > 12.5:
			continue
		# online, only the peer that drives the victim decides the hit
		if o.remote:
			continue
		if o.global_position.distance_to(global_position) < 2.6:
			if o.star_time <= 0.0:
				o.spin_out(owner_kart)
				owner_kart.audio.say("hit")
			if has_meta("nid"):
				Net.send_event("proj", [get_meta("nid")])
			_die(true)
			return
	for t in get_tree().get_nodes_in_group("traps"):
		if (t as Node3D).global_position.distance_to(global_position) < 2.0:
			(t as PhysProp).explode()
			_die(true)
			return


func net_hit() -> void:
	_die(true)


func _die(hit: bool) -> void:
	if hit:
		Game.play_3d(["res://assets/sound/npc/manhack/grind1.wav", "res://assets/sound/npc/manhack/grind2.wav"],
			global_position, 2.0, 1.0, 12.0)
		Effects.sparks(get_parent(), global_position, 1.0)
	else:
		Game.play_3d("res://assets/sound/npc/manhack/gib.wav", global_position, 0.0, 1.0, 10.0)
	queue_free()
