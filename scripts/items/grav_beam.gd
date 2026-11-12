class_name GravBeam
extends Node3D
## A gravity gun's beam held between two karts while it carries one (Items._pull, Kart.pulled):
## from the gun on the shooter's nose to the kart it has, following both, fading as it lets go.

var from: Node3D
var to: Node3D
var life := 0.5
var color := Color(1.0, 0.62, 0.2)
var t := 0.0
var _beam: MeshInstance3D
var _core: MeshInstance3D


static func between(a: Node3D, b: Node3D, col: Color, seconds: float) -> GravBeam:
	var g := GravBeam.new()
	g.from = a
	g.to = b
	g.color = col
	g.life = seconds
	a.get_parent().add_child(g)
	return g


func _ready() -> void:
	_beam = Effects.beam_node(color, 0.9, "materials/sprites/physbeam.png")
	add_child(_beam)
	_core = Effects.beam_node(Color(1, 1, 1, 0.8), 0.25, "materials/sprites/physbeam.png")
	add_child(_core)
	_place()


func _process(delta: float) -> void:
	t += delta
	if t >= life or not is_instance_valid(from) or not is_instance_valid(to):
		if is_instance_valid(to):
			Game.play_3d("res://assets/sound/weapons/physcannon/physcannon_drop.wav", to.global_position, 2.0, 1.0, 14.0)
		queue_free()
		return
	_place()
	var fade := clampf((life - t) / 0.2, 0.0, 1.0)  # full while it carries, gone as it lets go
	_beam.set_instance_shader_parameter("col", Color(color, fade))
	_core.set_instance_shader_parameter("col", Color(1, 1, 1, 0.8 * fade))
	# it wavers as it pulls
	_beam.set_instance_shader_parameter("width", 0.9 + 0.25 * sin(t * 40.0))


func _place() -> void:
	var a := from.global_position + from.global_basis.y * 1.1 - from.global_basis.z * 1.6
	var b := to.global_position + to.global_basis.y * 0.6
	Effects.place_beam(_beam, a, b)
	Effects.place_beam(_core, a, b)
