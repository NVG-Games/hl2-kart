class_name PhysProp
extends RigidBody3D
## prop_physics: an HL2 model with Source surface properties (mass, friction,
## elasticity, impact/break sounds) and optional breakage into gibs.

const GIBS := {
	"props_junk/wood_crate001a": ["props_junk/wood_crate001a_chunk01", "props_junk/wood_crate001a_chunk02",
		"props_junk/wood_crate001a_chunk03", "props_junk/wood_crate001a_chunk04", "props_junk/wood_crate001a_chunk05",
		"props_junk/wood_crate001a_chunk07", "props_junk/wood_crate001a_chunk09"],
	"props_junk/wood_crate002a": ["props_junk/wood_crate001a_chunk01", "props_junk/wood_crate001a_chunk02",
		"props_junk/wood_crate001a_chunk05", "props_junk/wood_crate001a_chunk06"],
	"props_junk/watermelon01": ["props_junk/watermelon01_chunk01a", "props_junk/watermelon01_chunk01b",
		"props_junk/watermelon01_chunk02a", "props_junk/watermelon01_chunk02b", "props_junk/watermelon01_chunk02c"],
	"items/item_item_crate": ["items/item_item_crate_chunk01", "items/item_item_crate_chunk02",
		"items/item_item_crate_chunk05", "items/item_item_crate_chunk06", "items/item_item_crate_chunk07",
		"items/item_item_crate_chunk08", "items/item_item_crate_chunk09"],
}
const BREAK_SPEED := {
	"props_junk/wood_crate001a": 9.0, "props_junk/wood_crate002a": 9.0, "props_junk/watermelon01": 6.0,
	"props_junk/cardboard_box001a": 11.0,
}
const EXPLOSIVE := ["props_c17/oildrum001_explosive"]

static var _shape_cache := {}

var model_key := ""
var surface := {}
var _prev_vel := Vector3.ZERO
var _sound_cd := 0.0
var _health := 1.0
var _dead := false
var lifetime := -1.0


static func shape_for(key: String, mesh_root: Node3D) -> Shape3D:
	if _shape_cache.has(key):
		return _shape_cache[key]
	var pts := PackedVector3Array()
	for n in mesh_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mesh_root.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else Transform3D.IDENTITY
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			# skinned props: vertices are already in model space (bind pose)
			var stepv := maxi(1, v.size() / 600)
			for k in range(0, v.size(), stepv):
				pts.append(xf * v[k])
	var sh := ConvexPolygonShape3D.new()
	if pts.size() >= 4:
		sh.points = pts
	else:
		sh.points = PackedVector3Array([Vector3(-0.2, 0, -0.2), Vector3(0.2, 0, -0.2), Vector3(0, 0.4, 0), Vector3(0, 0, 0.2)])
	_shape_cache[key] = sh
	return sh


func setup(key: String) -> void:
	model_key = key
	name = key.get_file()
	var model := Game.spawn_model(key)
	add_child(model)
	var info := Game.model_info(key)
	var sp: String = str(info.get("surfaceprop", "default")).to_lower()
	surface = Game.surfaceprops.get(sp, Game.surfaceprops.get("default", {}))
	mass = clampf(float(info.get("mass", 20.0)), 1.0, 800.0)
	var pm := PhysicsMaterial.new()
	pm.friction = clampf(float(surface.get("friction", 0.8)), 0.05, 1.5)
	pm.bounce = clampf(float(surface.get("elasticity", 0.25)), 0.0, 1.0) * 0.6
	physics_material_override = pm
	var col := CollisionShape3D.new()
	col.shape = shape_for(key, model)
	add_child(col)
	collision_layer = Game.LAYER_PROP
	collision_mask = Game.LAYER_WORLD | Game.LAYER_KART | Game.LAYER_PROP | Game.LAYER_ITEM
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = mass < 30.0
	angular_damp = 0.4
	linear_damp = 0.05
	can_sleep = true
	if mass < 60.0:
		_health = 1.0


func _physics_process(delta: float) -> void:
	_sound_cd -= delta
	var v := linear_velocity
	var dv := (v - _prev_vel).length()
	if dv > 2.5 and _sound_cd <= 0.0 and get_contact_count() > 0:
		var hard := dv > 6.0
		var list: Array = surface.get("impacthard" if hard else "impactsoft", surface.get("impacthard", []))
		if not list.is_empty():
			Game.play_3d(list, global_position, linear_to_db(clampf(dv / 12.0, 0.15, 1.0)), 1.0, 8.0)
			_sound_cd = 0.12
		var limit: float = BREAK_SPEED.get(model_key, 0.0)
		if limit > 0.0 and dv > limit:
			smash(v)
		elif model_key in EXPLOSIVE and dv > 14.0:
			explode()
	_prev_vel = v
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()
	if global_position.y < -200.0:
		queue_free()


## Break into gibs like prop_data "Wooden.Medium".
func smash(vel := Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	var brk: Array = surface.get("break", [])
	if brk.is_empty():
		brk = ["res://assets/sound/physics/wood/wood_crate_break%d.wav" % (randi() % 5 + 1)]
		if model_key.contains("melon"):
			brk = ["res://assets/sound/physics/flesh/flesh_bloody_break.wav"]
	Game.play_3d(brk, global_position, 0.0, 1.0, 10.0)
	var gibs: Array = GIBS.get(model_key, [])
	for g in gibs:
		if not Game.models.has(g):
			continue
		var p := PhysProp.new()
		get_parent().add_child(p)
		p.setup(g)
		p.global_transform = global_transform
		p.global_position += Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3))
		p.linear_velocity = vel * 0.6 + Vector3(randf_range(-3, 3), randf_range(1, 4), randf_range(-3, 3))
		p.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		p.lifetime = 6.0
		p.collision_mask = Game.LAYER_WORLD
		p.collision_layer = 0
	queue_free()


func explode() -> void:
	if _dead:
		return
	_dead = true
	# a dropped barrel exists on every peer: blow up all the copies
	if has_meta("nid") and not has_meta("net_done"):
		Net.send_event("trap", [get_meta("nid")])
	Effects.explosion(get_parent(), global_position, 1.0)
	queue_free()


## Called by karts / items to apply damage-like impulses.
func hit(impulse: Vector3) -> void:
	apply_central_impulse(impulse)
	if model_key in EXPLOSIVE and impulse.length() / mass > 6.0:
		call_deferred("explode")
