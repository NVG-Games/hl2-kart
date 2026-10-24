extends Node3D
## One kart resting on the start straight, photographed at wheel height.
## usage: godot --path . res://tests/stance_shot.tscn -- <out_prefix>

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var trk := Track.new()
	add_child(trk)
	trk.build("city17_circuit")
	var k := Kart.new()
	add_child(k)
	k.setup("breen", 0, trk, false)
	k.global_transform = trk.spawn_transform(0)
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(2.5).timeout
	print("compress ", k.wheel_compress, " contact ", k.wheel_contact, " y ", k.global_position.y)
	var p := k.global_position
	var side := k.global_basis.x
	cam.look_at_from_position(p + side * 7.0 + Vector3.UP * 0.4, p + Vector3.UP * 0.4)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "_side.png")
	cam.look_at_from_position(p - k.global_basis.z * 8.0 + Vector3.UP * 0.5, p + Vector3.UP * 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "_front.png")
	get_tree().quit()
