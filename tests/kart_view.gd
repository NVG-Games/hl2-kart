extends Node3D
## Shows one kart (vehicle + seated driver) from several angles and saves PNGs.
## usage: godot --path . res://tests/kart_view.tscn -- <out_prefix> <character> [vehicle] [nobuggy]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://kart"
	var who: String = a[1] if a.size() > 1 else "alyx"
	var vid: String = a[2] if a.size() > 2 else "buggy"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.4, 0.45, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	add_child(ground)
	var k := Kart.new()
	k.char_data = Game.character(who)
	k.character_id = who
	k.racer_index = 0
	k.spec = VehicleSpec.get_spec(vid)
	k.wheels = k.spec.wheels
	var vis := KartVisual.new()
	add_child(vis)
	vis.setup(k)
	vis.set_process(false)
	if k.spec.def.get("rig", "") == "dog":
		vis._animate_dog(0.0)
	print("driver pos ", vis.driver.position, " rot ", vis.driver.rotation, " eye ", k.spec.eye)
	print("wheels ", k.spec.wheels.map(func(w): return w["pos"]), " box ", k.spec.box_size, " @ ", k.spec.box_center)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	if a.size() > 3 and a[3] == "nobuggy":
		vis.buggy.visible = false
	var f := maxf(1.0, k.spec.length / 4.4)
	var focus := Vector3(0, maxf(0.95, k.spec.eye.y - 0.5), 0.4)
	var views := [Vector3(-3.2, 1.3, 0.4) * f, Vector3(0, 1.8, -3.5) * f, Vector3(-2.5, 2.0, 2.8) * f, Vector3(0, 5, 0.41) * f]
	views[0].y = focus.y + 0.3
	for i in views.size():
		cam.look_at_from_position(views[i], focus)
		for fr in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "_%d.png" % i)
	get_tree().quit()
