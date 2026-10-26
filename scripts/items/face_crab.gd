class_name FaceCrab
extends Node3D
## The HEADCRAB item's passenger: a headcrab leaps onto a racer's face. On the
## local player it clings to the camera and covers most of the view; on anyone
## else it sits on the driver's head (and a computer driver swerves, see
## AiController). It lets go after `hold` seconds, or at once if the suit charges.

var kart: Kart
var hold := 3.6
var wait := 0.0
var t := 0.0
var model: Node3D
var _landed := false
var _on_camera := false
var _leaving := -1.0


func attach(k: Kart, seconds: float, delay: float) -> void:
	kart = k
	hold = seconds
	wait = delay
	model = Game.spawn_model("headcrabclassic")
	add_child(model)
	visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(kart):
		queue_free()
		return
	t += delta
	if not _landed:
		if t >= wait:
			_land()
		return
	if _leaving >= 0.0:
		_leaving += delta
		position += Vector3(0.0, 2.5, -1.5 if _on_camera else 0.0) * delta
		scale = Vector3.ONE * maxf(0.01, 1.0 - _leaving * 2.5) * (2.2 if _on_camera else 1.0)
		if _leaving > 0.4:
			queue_free()
		return
	# hang on and wriggle
	var w := t * 9.0
	if _on_camera:
		position = Vector3(sin(w * 0.7) * 0.03, -0.06 + sin(w) * 0.02, -0.4)
		rotation.z = sin(w * 0.5) * 0.12
	else:
		model.rotation.y = sin(w * 0.6) * 0.3
	if t - wait > hold or kart.star_time > 0.0 or kart.state == Kart.State.RESPAWN:
		_leave()


func _land() -> void:
	_landed = true
	visible = true
	kart.blind_time = maxf(kart.blind_time, hold)
	Game.play_3d("res://assets/sound/npc/headcrab/attack1.wav", kart.global_position, 3.0, 1.0, 12.0, kart)
	_on_camera = kart.is_player and not kart.remote
	if _on_camera:
		var cam := get_viewport().get_camera_3d()
		if cam:
			reparent(cam, false)
			# belly to the lens, head up the screen; this node wriggles, the model keeps the pose
			model.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO)
			transform = Transform3D(Basis(), Vector3(0, -0.04, -0.42))
			scale = Vector3.ONE * 2.2
			Game.play_ui("res://assets/sound/npc/headcrab/idle3.wav", 0.0)
			return
		_on_camera = false
	position = kart.spec.eye + Vector3(0, 0.2, 0) if kart.spec.has_eye else Vector3(0, 2.0, 0)


func _leave() -> void:
	if _leaving < 0.0:
		_leaving = 0.0
		kart.blind_time = 0.0
