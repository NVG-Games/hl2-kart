class_name CanisterStrike
extends Node3D
## env_headcrabcanister: a Combine shell fired at the race leader. It tracks
## the leader for a moment, then slams down and leaves the canister smoking.

var owner_kart: Kart
var target: Kart
var t := 0.0
var model: Node3D
var _impact_pos := Vector3.ZERO
var _landed := false
var _marker: MeshInstance3D


static func leader_for(k: Kart) -> Kart:
	var best: Kart = null
	for n in k.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == k or o.finished:
			continue
		if best == null or o.total_progress > best.total_progress:
			best = o
	return best


func launch(k: Kart, _race, forced_target: Kart = null) -> void:
	owner_kart = k
	target = forced_target if forced_target else leader_for(k)
	if target == null:
		queue_free()
		return
	Game.play_3d("res://assets/sound/npc/env_headcrabcanister/launch.wav", k.global_position, 0.0, 1.0, 30.0)
	Game.play_3d("res://assets/sound/npc/env_headcrabcanister/incoming.wav", target.global_position, 4.0, 1.0, 60.0, target)
	model = Game.spawn_model("props_combine/headcrabcannister01a")
	add_child(model)
	model.visible = false
	_marker = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 160.0
	_marker.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.4, 0.8, 1.0, 0.6)
	_marker.material_override = m
	add_child(_marker)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	t += delta
	if t < 2.4:
		_impact_pos = target.global_position + target.linear_velocity * 0.35
		_marker.global_position = _impact_pos + Vector3.UP * 80.0
		_marker.visible = int(t * 10.0) % 2 == 0
		return
	_marker.visible = false
	if not _landed:
		model.visible = true
		var fall := clampf((t - 2.4) / 0.45, 0.0, 1.0)
		var from := _impact_pos + Vector3(30, 140, 10)
		var p := from.lerp(_impact_pos, fall)
		model.global_position = p
		var dir := (_impact_pos - from).normalized()
		model.global_basis = Basis.looking_at(dir, Vector3.UP)
		if fall >= 1.0:
			_landed = true
			Effects.explosion(get_parent(), _impact_pos, 1.6, owner_kart)
			Game.play_3d("res://assets/sound/npc/env_headcrabcanister/explosion.wav", _impact_pos, 4.0, 1.0, 40.0)
			Game.play_3d("res://assets/sound/npc/env_headcrabcanister/hiss.wav", _impact_pos, 0.0, 1.0, 14.0)
			model.global_position = _impact_pos - dir * 1.2
			Effects.smoke_column(get_parent(), _impact_pos, 6.0)
	elif t > 9.0:
		queue_free()
