class_name SawbladeProjectile
extends Node3D
## Ravenholm's sawblade, flung flat down the road: it slices through every kart in
## its way (each one spins out) and sticks in the first wall it meets.

const HOVER := 1.1

var owner_kart: Kart
var vel := Vector3.ZERO
var up := Vector3.UP
var model: Node3D
var life := 4.0
var _stuck := -1.0
var _cut := {}


func launch(k: Kart) -> void:
	owner_kart = k
	up = k.grav_up
	var fwd := -k.global_basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	global_position = k.global_position + fwd * 3.0 + up * HOVER
	vel = fwd * maxf(60.0, k.fwd_speed + 25.0)
	model = Game.spawn_model("props_junk/sawblade001a")
	add_child(model)
	model.scale = Vector3.ONE * 1.5
	Game.play_3d(["res://assets/sound/weapons/physcannon/superphys_launch1.wav",
		"res://assets/sound/weapons/physcannon/superphys_launch2.wav"], global_position, 2.0, 1.2, 16.0)


func _physics_process(delta: float) -> void:
	if _stuck >= 0.0:
		_stuck += delta
		if _stuck > 5.0:
			queue_free()
		return
	life -= delta
	if life <= 0.0 or global_position.y < -200.0:
		queue_free()
		return
	model.rotate_object_local(Vector3.UP, 30.0 * delta)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position - up * 6.0, Game.LAYER_WORLD)
	var g := space.intersect_ray(q)
	if not g.is_empty() and (g["collider"] as Node).get_meta("surface", "road") != "wall":
		up = up.lerp(g["normal"], minf(1.0, delta * 8.0)).normalized()
		global_position = global_position.lerp(g["position"] + up * HOVER, minf(1.0, delta * 10.0))
		var sp := vel.length()
		vel -= up * vel.dot(up)
		vel = vel.normalized() * sp
	else:
		vel -= Vector3.UP * 18.0 * delta
	var step := vel * delta
	var w := PhysicsRayQueryParameters3D.create(global_position, global_position + step + step.normalized() * 0.4,
		Game.LAYER_WORLD)
	var hit := space.intersect_ray(w)
	var solid: bool = not hit.is_empty() and (hit["collider"] as Node).get_meta("surface", "") != ""
	if solid and (hit["normal"] as Vector3).dot(up) < 0.6:
		# stuck in the wall, half buried
		global_position = (hit["position"] as Vector3) - step.normalized() * 0.2
		_stuck = 0.0
		Game.play_3d("res://assets/sound/weapons/crossbow/hit1.wav", global_position, 2.0, 0.8, 14.0)
		return
	global_position += step
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as Kart
		if k == owner_kart or _cut.has(k):
			continue
		if k.global_position.distance_to(global_position) < 2.2:
			_cut[k] = true
			k.spin_out(owner_kart)
			Game.play_3d("res://assets/sound/physics/flesh/flesh_squishy_impact_hard%d.wav" % (randi() % 4 + 1),
				k.global_position, 2.0, 1.0, 12.0)
