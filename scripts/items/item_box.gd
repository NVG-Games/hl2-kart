class_name ItemBox
extends Area3D
## item_item_crate: the HL2 supply crate as an item box. Smashes into its
## chunk gibs when driven through and re-materialises a few seconds later.

const RESPAWN := 1.8

var model: Node3D
var index := -1  # same on every peer: the track builds boxes in a fixed order
var _glow: OmniLight3D
var _cool := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = Game.LAYER_TRIGGER
	collision_mask = Game.LAYER_KART
	monitoring = true
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2.2, 2.6, 2.2)
	cs.shape = b
	add_child(cs)
	model = Game.spawn_model("items/item_item_crate")
	model.scale = Vector3.ONE * 1.9
	model.position = Vector3(0, -0.6, 0)
	add_child(model)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.8, 0.35)
	_glow.omni_range = 3.5
	_glow.light_energy = 0.8
	_glow.shadow_enabled = false
	add_child(_glow)
	_t = randf() * TAU
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	model.rotation.y = _t * 0.9
	model.position.y = -0.6 + sin(_t * 2.0) * 0.15
	if _cool > 0.0:
		_cool -= delta
		if _cool <= 0.0:
			_appear()


func _appear() -> void:
	model.visible = true
	_glow.visible = true
	model.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * 1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Game.play_3d("res://assets/sound/items/suitcharge1.wav", global_position, -12.0, 1.4, 6.0)


func _on_body(body: Node) -> void:
	if _cool > 0.0 or not (body is Kart):
		return
	var k := body as Kart
	# a remote kart's owner breaks the crate on their side and tells everyone
	if k.remote:
		return
	_smash(k.linear_velocity)
	if Net.active:
		Net.send_event("box", [index])
	if k.item == "" and k.roulette <= 0.0:
		var id := Items.roll(k.place, k.get_tree().get_nodes_in_group("karts").size())
		k.give_item(id, 3 if id.ends_with("3") else 1)
		if k.is_player:
			Game.play_ui("res://assets/sound/items/ammocrate_open.wav", -4.0)


## Someone else's kart broke this crate.
func net_smash() -> void:
	if _cool <= 0.0:
		_smash(Vector3.ZERO)


func _smash(vel: Vector3) -> void:
	_cool = RESPAWN
	model.visible = false
	_glow.visible = false
	# visual gibs
	var gibs: Array = PhysProp.GIBS["items/item_item_crate"]
	for g in gibs:
		var p := PhysProp.new()
		get_parent().add_child(p)
		p.setup(g)
		p.global_position = global_position + Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.6), randf_range(-0.6, 0.6))
		(p.get_child(0) as Node3D).scale = Vector3.ONE * 1.6
		p.collision_layer = 0
		p.linear_velocity = vel * 0.7 + Vector3(randf_range(-4, 4), randf_range(2, 6), randf_range(-4, 4))
		p.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		p.lifetime = 3.0
		p.collision_mask = Game.LAYER_WORLD
	Game.play_3d("res://assets/sound/physics/wood/wood_crate_break%d.wav" % (randi() % 5 + 1), global_position, 0.0, 1.0, 10.0)
