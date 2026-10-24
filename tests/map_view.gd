extends Node3D
## Renders a converted BSP world: an orthographic top-down view plus
## perspective shots. Camera specs: "x,y,z,yaw,pitch" in Godot metres/degrees.
## usage: godot --path . res://tests/map_view.tscn -- <map_key> <out_prefix> [cam ...]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var key: String = a[0]
	var out: String = a[1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var w := BspWorld.new()
	add_child(w)
	w.load_map(key)
	var box := w.aabb()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.far = 20000.0
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.z) * 1.02
	var c := box.get_center()
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(c.x, box.end.y + 50.0, c.z))
	for f in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "_top.png")
	print("top view: centre %s size %.1f (x %.1f..%.1f, z %.1f..%.1f)" % [c, cam.size, box.position.x, box.end.x, box.position.z, box.end.z])
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 70.0
	var specs := a.slice(2)
	if specs.is_empty():
		for ent in w.info.get("entities", []):
			if ent.get("classname", "") in ["info_player_start", "info_player_deathmatch"]:
				var o: Array = ent["origin_m"]
				specs.append("%f,%f,%f,0,-10" % [o[0], o[1] + 1.0, o[2]])
				specs.append("%f,%f,%f,180,-10" % [o[0], o[1] + 1.0, o[2]])
				break
	for i in specs.size():
		var p: PackedStringArray = specs[i].split(",")
		if p[0] == "track":
			_draw_track(str(p[1]))
			continue
		if p[0] == "ortho":
			# "ortho,<cx>,<cz>,<size>": top-down close-up
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(p[3])
			cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(float(p[1]), box.end.y + 50.0, float(p[2])))
			for f in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out + "_%d.png" % i)
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			continue
		if p[0] == "auto":
			# fit the whole map: "auto,<yaw>,<pitch>"
			var yaw := deg_to_rad(float(p[1]))
			var pitch := deg_to_rad(float(p[2]))
			var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
			var r := box.size.length() * 0.5
			cam.global_position = c + dir * r * 1.45
			cam.look_at(c, Vector3.UP)
		else:
			cam.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			cam.rotation_degrees = Vector3(float(p[4]) if p.size() > 4 else -10.0, float(p[3]) if p.size() > 3 else 0.0, 0)
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "_%d.png" % i)
	get_tree().quit()


## Race line (red), barriers (yellow) and crates (green) over the map.
func _draw_track(id: String) -> void:
	var t: Dictionary = Game.load_json("res://assets/track/%s.json" % id)
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var c: Array = t["path"]["center"]
	for i in c.size():
		var a: Array = c[i]
		var b: Array = c[(i + 1) % c.size()]
		im.surface_set_color(Color(1, 0.1, 0.1))
		im.surface_add_vertex(Vector3(a[0], a[1] + 0.3, a[2]))
		im.surface_add_vertex(Vector3(b[0], b[1] + 0.3, b[2]))
	for side in t.get("barriers", []):
		for i in side.size():
			var a = side[i]
			var b = side[(i + 1) % side.size()]
			if a == null or b == null:
				continue
			im.surface_set_color(Color(1, 1, 0))
			im.surface_add_vertex(Vector3(a[0], a[1] + 0.3, a[2]))
			im.surface_add_vertex(Vector3(b[0], b[1] + 0.3, b[2]))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
