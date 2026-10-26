class_name HopperMine
extends Node3D
## combine_mine as a trap: dropped behind the kart it settles on the road, blinks
## while it arms, then springs at the first kart that comes close and goes off
## beside it. Its thrower is safe from it for a couple of seconds.

const RANGE := 7.0

var owner_kart: Kart
var model: Node3D
var up := Vector3.UP
var _arm := 1.0
var _life := 45.0
var _jump := -1.0
var _vel := Vector3.ZERO
var _light: OmniLight3D
var _blink := 0.0


func drop(k: Kart) -> void:
	owner_kart = k
	model = Game.spawn_model("props_combine/combine_mine01")
	add_child(model)
	up = k.grav_up
	var p := k.global_position + k.global_basis.z * 3.5 + up * 1.0
	var q := PhysicsRayQueryParameters3D.create(p, p - up * 6.0, Game.LAYER_WORLD)
	var hit := k.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		p = hit["position"]
		up = hit["normal"]
	global_position = p
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	global_basis = Basis(side, up, side.cross(up)).orthonormalized()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.15)
	_light.omni_range = 4.0
	_light.position = Vector3(0, 0.6, 0)
	add_child(_light)
	Game.play_3d("res://assets/sound/weapons/slam/mine_mode.wav", p, 0.0, 1.0, 10.0)


func _process(delta: float) -> void:
	_arm -= delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _jump >= 0.0:
		_jump += delta
		_vel -= Vector3.UP * 20.0 * delta
		global_position += _vel * delta
		if _jump > 0.38:
			Effects.explosion(get_parent(), global_position, 0.65, owner_kart)
			queue_free()
		return
	_blink += delta * (3.0 if _arm > 0.0 else 6.0)
	_light.light_energy = 2.5 if fmod(_blink, 1.0) < 0.5 else 0.2
	if _arm > 0.0:
		return
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as Kart
		if k == owner_kart and _arm > -1.5:
			continue
		if k.global_position.distance_to(global_position) < RANGE:
			_jump = 0.0
			var aim := k.global_position + k.linear_velocity * 0.35 - global_position
			_vel = aim / 0.38 + up * 4.0
			Game.play_3d("res://assets/sound/weapons/grenade/tick1.wav", global_position, 2.0, 1.4, 10.0)
			return
