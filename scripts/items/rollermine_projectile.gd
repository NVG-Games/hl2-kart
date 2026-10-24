class_name RollermineProjectile
extends RigidBody3D
## npc_rollermine as a bouncing shell: it rolls straight, ricochets off walls
## and shocks any vehicle it touches (rmine_shockvehicle).

var owner_kart: Kart
var life := 11.0
var bounces := 0
var _loop: AudioStreamPlayer3D
var _arm := 0.35
var _dir := Vector3.FORWARD
var _speed := 0.0


func launch(k: Kart, backwards: bool) -> void:
	owner_kart = k
	mass = 50.0
	var model := Game.spawn_model("roller")
	model.scale = Vector3.ONE * 1.8
	add_child(model)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.55
	cs.shape = sph
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.85
	pm.friction = 0.2
	physics_material_override = pm
	collision_layer = Game.LAYER_ITEM
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROP | Game.LAYER_KART
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	gravity_scale = 1.0
	var fwd := -k.global_basis.z
	_dir = -fwd if backwards else fwd
	_speed = maxf(k.fwd_speed, 0.0) + 22.0 if not backwards else 14.0
	global_position = k.global_position + Vector3.UP * 1.0 + _dir * 4.0
	linear_velocity = _dir * _speed + Vector3.UP * 2.0
	body_entered.connect(_on_body)
	_loop = AudioStreamPlayer3D.new()
	_loop.stream = Game.stream("res://assets/sound/npc/roller/mine/rmine_movefast_loop1.wav")
	_loop.unit_size = 10.0
	_loop.bus = "SFX"
	add_child(_loop)
	_loop.play()
	Game.play_3d("res://assets/sound/npc/roller/mine/rmine_tossed1.wav", global_position, 0.0, 1.0, 10.0)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 0.7, 1.0)
	l.omni_range = 4.0
	l.light_energy = 1.2
	add_child(l)


func _physics_process(delta: float) -> void:
	life -= delta
	_arm -= delta
	if life <= 0.0 or global_position.y < -60.0:
		_pop()
		return
	# keep rolling at speed in the travel direction, like the mine's motor
	var v := linear_velocity
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() > 1.0:
		_dir = flat.normalized()
	var want := _dir * maxf(_speed, 18.0)
	linear_velocity = Vector3(lerpf(v.x, want.x, delta * 2.0), v.y, lerpf(v.z, want.z, delta * 2.0))


func _on_body(other: Node) -> void:
	if other is Kart:
		var k := other as Kart
		if k == owner_kart and _arm > 0.0:
			return
		# a proxy's owner decides: bounce off it until they report the hit
		if k.remote:
			return
		if k.star_time <= 0.0:
			k.spin_out(owner_kart)
		if has_meta("nid"):
			Net.send_event("proj", [get_meta("nid")])
		_shock()
		return
	if other is PhysProp:
		(other as PhysProp).hit(linear_velocity * 30.0)
	bounces += 1
	Game.play_3d("res://assets/sound/npc/roller/mine/rmine_blip1.wav", global_position, -6.0, 1.0, 8.0)
	if bounces > 7:
		_pop()


func net_hit() -> void:
	_shock()


func _shock() -> void:
	Game.play_3d("res://assets/sound/npc/roller/mine/rmine_shockvehicle1.wav", global_position, 3.0, 1.0, 14.0)
	Effects.sparks(get_parent(), global_position, 1.5, Color(0.5, 0.75, 1.0))
	queue_free()


func _pop() -> void:
	Game.play_3d("res://assets/sound/npc/roller/mine/rmine_explode_shock1.wav", global_position, 0.0, 1.0, 12.0)
	Effects.sparks(get_parent(), global_position, 1.0, Color(0.5, 0.75, 1.0))
	queue_free()
