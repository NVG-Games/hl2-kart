class_name Scanner
extends Node3D
## npc_cscanner doing Lakitu duty: flies in, photographs the wreck (flash +
## scanner_photo1), lifts it away and drops it back on the track.

var kart: Kart
var t := 0.0
var model: Node3D
var _start := Vector3.ZERO
var _light: SpotLight3D


static func rescue(k: Kart) -> void:
	var s := Scanner.new()
	k.get_parent().add_child(s)
	s.setup(k)


func setup(k: Kart) -> void:
	kart = k
	model = Game.spawn_model("combine_scanner")
	model.scale = Vector3.ONE * 1.6
	add_child(model)
	_start = k.global_position + Vector3(6, 14, 6)
	global_position = _start
	_light = SpotLight3D.new()
	_light.spot_range = 20.0
	_light.spot_angle = 25.0
	_light.light_energy = 0.0
	_light.light_color = Color(0.85, 0.95, 1.0)
	add_child(_light)
	Game.play_3d("res://assets/sound/npc/scanner/scanner_blip1.wav", global_position, 0.0, 1.0, 14.0, self)


func _process(delta: float) -> void:
	t += delta
	if not is_instance_valid(kart):
		queue_free()
		return
	var hover := kart.global_position + Vector3(0, 3.2, 0)
	if t < 0.7:
		global_position = _start.lerp(hover, t / 0.7)
	elif t < 2.2:
		global_position = hover + Vector3(sin(t * 3.0) * 0.2, sin(t * 5.0) * 0.15 + (t - 0.7) * 1.5, 0)
		if t - delta < 0.8 and t >= 0.8:
			Game.play_3d("res://assets/sound/npc/scanner/scanner_photo1.wav", global_position, 2.0, 1.0, 16.0, self)
			_light.light_energy = 16.0
	else:
		global_position += Vector3(0, 8, 0) * delta
	_light.light_energy = lerpf(_light.light_energy, 0.0, delta * 6.0)
	if global_position.distance_to(kart.global_position) > 0.5:
		_light.look_at(kart.global_position, Vector3.FORWARD)
	model.rotation.y += delta * 0.8
	if t > 4.0:
		queue_free()
