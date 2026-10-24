extends Node3D
## Debug viewer: loads a model, shoots screenshots from several angles, quits.
## usage: godot --path . res://tests/shot.tscn -- <res path> <out png prefix>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://assets/models/buggy.gltf"
	var out: String = args[1] if args.size() > 1 else "user://shot"
	var scn: PackedScene = load(path)
	var inst := scn.instantiate()
	add_child(inst)
	var aabb := _aabb(inst)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment = e
	add_child(env)
	var c := aabb.get_center()
	var r := aabb.size.length() * 0.8
	var dirs := [Vector3(0, 0.3, 1), Vector3(0, 0.3, -1), Vector3(1, 0.3, 0), Vector3(-1, 0.3, 0)]
	for i in dirs.size():
		cam.look_at_from_position(c + dirs[i].normalized() * r, c)
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "_%d.png" % i)
	get_tree().quit()

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
