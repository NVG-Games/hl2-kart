class_name EnergyBall
extends Node3D
## The AR2's alt-fire as a kart racer shell: a ball of dark energy that skims along
## the road (tubes included), bounces off every wall and flattens the first kart it
## touches, its thrower too once it has had time to come back.

const HOVER := 1.0

var owner_kart: Kart
var vel := Vector3.ZERO
var up := Vector3.UP
var speed := 44.0
var life := 7.0
var bounces := 0
var _arm := 0.6
var _loop: AudioStreamPlayer3D


func launch(k: Kart) -> void:
	owner_kart = k
	up = k.grav_up
	var fwd := -k.global_basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	global_position = k.global_position + fwd * 3.2 + up * HOVER
	speed = maxf(speed, k.fwd_speed + 12.0)
	vel = fwd * speed
	add_child(_sphere(0.45, Color(0.9, 0.97, 1.0), 1.0, 5.0))
	add_child(_sphere(0.9, Color(0.45, 0.75, 1.0), 0.35, 2.0))
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.85, 1.0)
	l.omni_range = 8.0
	l.light_energy = 2.5
	add_child(l)
	_loop = AudioStreamPlayer3D.new()
	_loop.stream = Game.stream("res://assets/sound/weapons/physcannon/energy_sing_loop4.wav")
	_loop.unit_size = 9.0
	_loop.bus = "SFX"
	add_child(_loop)
	_loop.play()
	Game.play_3d("res://assets/sound/weapons/irifle/irifle_fire2.wav", global_position, 2.0, 1.0, 16.0)


static func _sphere(r: float, col: Color, alpha: float, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	sph.radial_segments = 16
	sph.rings = 8
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _physics_process(delta: float) -> void:
	life -= delta
	_arm -= delta
	if life <= 0.0 or global_position.y < -200.0:
		_pop()
		return
	var space := get_world_3d().direct_space_state
	# skim the surface underneath, turning with it (walls of a tube included)
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position - up * 6.0, Game.LAYER_WORLD)
	var g := space.intersect_ray(q)
	if not g.is_empty() and (g["collider"] as Node).get_meta("surface", "road") != "wall":
		up = up.lerp(g["normal"], minf(1.0, delta * 8.0)).normalized()
		var at: Vector3 = g["position"] + up * HOVER
		global_position = global_position.lerp(at, minf(1.0, delta * 10.0))
		vel -= up * vel.dot(up)
		vel = vel.normalized() * speed
	else:
		vel -= Vector3.UP * 18.0 * delta
	# walls: ricochet
	var step := vel * delta
	var w := PhysicsRayQueryParameters3D.create(global_position, global_position + step + step.normalized() * 0.5,
		Game.LAYER_WORLD)
	var hit := space.intersect_ray(w)
	# only the circuit's own walls and slopes count: it goes straight through set dressing
	var solid: bool = not hit.is_empty() and (hit["collider"] as Node).get_meta("surface", "") != ""
	if solid and (hit["normal"] as Vector3).dot(up) < 0.6:
		vel = vel.bounce(hit["normal"])
		global_position += (hit["normal"] as Vector3) * 0.25
		bounces += 1
		Game.play_3d(["res://assets/sound/weapons/physcannon/energy_bounce1.wav",
			"res://assets/sound/weapons/physcannon/energy_bounce2.wav"], global_position, 0.0, 1.0, 12.0)
		if bounces > 8:
			_pop()
			return
	else:
		global_position += step
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as Kart
		if k == owner_kart and _arm > 0.0:
			continue
		if k.global_position.distance_to(global_position) > 2.3:
			continue
		# a proxy's owner decides it was hit, and tells everyone
		if k.remote:
			continue
		if k.star_time <= 0.0:
			k.tumble(owner_kart, (vel.normalized() * 5.0 + up * 4.0) * k.mass)
		if has_meta("nid"):
			Net.send_event("proj", [get_meta("nid")])
		_pop()
		return


func net_hit() -> void:
	_pop()


func _pop() -> void:
	Game.play_3d("res://assets/sound/weapons/physcannon/energy_sing_explosion2.wav", global_position, 2.0, 1.0, 16.0)
	Effects.sparks(get_parent(), global_position, 2.0, Color(0.6, 0.85, 1.0))
	queue_free()
