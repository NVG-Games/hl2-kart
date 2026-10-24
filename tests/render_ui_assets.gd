extends Node
## Renders menu art: portraits, vehicle and item icons (transparent PNG) and in-game
## background stills at the window resolution (run with --resolution 1920x1080).
## usage: godot --path . res://tests/render_ui_assets.tscn -- [icons|backgrounds|tracks|all]

const OUT := "res://assets/ui/"
## Where on each lap (fraction) the menu background still is taken.
const BG_AT := {"ct17": 0.04, "black_mesa": 0.74, "xen": 0.3, "surface_tension": 0.8}
var race: Node
var cam: Camera3D
var shots_done := {}
var t := 0.0
var mode := "all"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	mode = a[0] if a.size() > 0 else "all"
	if mode == "tracks" or mode == "all":
		await _track_thumbs()
	if mode == "tracks":
		get_tree().quit()
		return
	if mode != "backgrounds":
		await _icons()
	if mode == "icons":
		get_tree().quit()
		return
	Game.settings["demo"] = true
	Game.settings["sky"] = "sky_day01_01"
	Game.settings["quality"] = 2
	Game.settings["track"] = "city17_circuit"
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 9000.0
	get_tree().root.add_child.call_deferred(cam)


func _studio(size: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var c := Camera3D.new()
	vp.add_child(c)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 1.2
	rim.light_color = Color(1.0, 0.85, 0.6)
	vp.add_child(rim)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.56)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	return [vp, c]


func _save(vp: SubViewport, path: String) -> void:
	for f in 4:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _icons() -> void:
	await _vehicle_icons()
	var st := _studio(Vector2i(512, 512))
	var vp: SubViewport = st[0]
	var c: Camera3D = st[1]
	for ch in Game.CHARACTERS:
		var m := Game.spawn_model(ch["model"], "portrait")
		vp.add_child(m)
		var sks := m.find_children("*", "Skeleton3D", true, false)
		var head := Vector3(0, 1.62, 0.05)
		if sks.size() > 0:
			BipedPose.standing(sks[0])
			var hb := BipedPose.limb(sks[0], "Head1")
			if hb >= 0:
				head = sks[0].get_bone_global_pose(hb).origin
			else:
				var meta: Dictionary = Game.load_json("res://assets/models/%s.json" % ch["model"])
				if meta.get("attachments", {}).has("head"):
					var o: Array = meta["attachments"]["head"]["origin"]
					head = Vector3(o[0], o[1], o[2])
		# some HL1 rigs put "Head" at the neck: keep the helmet in frame
		head.y = maxf(head.y, Game.model_aabb(ch["model"]).end.y - 0.2)
		c.fov = 24.0
		c.look_at_from_position(head + Vector3(0.28, 0.0, 1.25), head + Vector3(0, -0.12, 0))
		await _save(vp, OUT + "portraits/%s.png" % ch["id"])
		m.queue_free()
		await get_tree().process_frame
	var icons := {}
	for id in Items.INFO:
		icons[id] = Items.INFO[id]["model"]
	icons["crate"] = "items/item_item_crate"
	icons["scanner"] = "combine_scanner"
	for id in icons:
		var key: String = icons[id]
		var m := Game.spawn_model(key)
		vp.add_child(m)
		var box := Game.model_aabb(key)
		var r := box.size.length() * 0.5
		c.fov = 30.0
		var ctr := box.get_center()
		var zoom := 0.55 if id.begins_with("manhack") else 1.0
		c.look_at_from_position(ctr + Vector3(1.0, 0.55, 1.2).normalized() * r * 3.6 * zoom, ctr)
		await _save(vp, OUT + "items/%s.png" % id)
		m.queue_free()
		await get_tree().process_frame
	vp.queue_free()


## Three-quarter front view of every vehicle, no driver, tinted neutral.
func _vehicle_icons() -> void:
	var st := _studio(Vector2i(448, 280))
	var vp: SubViewport = st[0]
	var c: Camera3D = st[1]
	for veh in Game.VEHICLES:
		var k := Kart.new()
		k.char_data = {"color": Color(0.8, 0.8, 0.8)}
		k.racer_index = 80
		k.spec = VehicleSpec.get_spec(veh["id"])
		k.wheels = k.spec.wheels
		var kv := KartVisual.new()
		vp.add_child(kv)
		kv.setup(k)
		kv.driver.visible = false
		kv.set_process(false)
		for n in kv.find_children("*", "GPUParticles3D", true, false) + kv.find_children("*", "CPUParticles3D", true, false):
			(n as Node3D).visible = false
		var box := AABB()
		var first := true
		for mi in kv.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not m.is_visible_in_tree():
				continue
			var b := m.global_transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var ctr := box.get_center()
		var r := box.size.length() * 0.5
		c.fov = 26.0
		c.look_at_from_position(ctr + Vector3(1.05, 0.5, -1.25).normalized() * r * 2.6, ctr + Vector3.DOWN * r * 0.1)
		await _save(vp, OUT + "vehicles/%s.png" % veh["id"])
		kv.queue_free()
		k.free()
		await get_tree().process_frame
	vp.queue_free()


## Menu card for every track: the grid at the start line, seen from behind and above.
func _track_thumbs() -> void:
	await get_tree().process_frame
	var keep: String = Game.settings.get("track", "city17_circuit")
	Game.settings["demo"] = true
	Game.settings["sky"] = "sky_day01_01"
	for tr in Game.TRACKS:
		Game.settings["track"] = tr["id"]
		var r: Node = load("res://scenes/race.tscn").instantiate()
		get_tree().root.add_child(r)
		var c := Camera3D.new()
		c.fov = 60.0
		c.far = 9000.0
		get_tree().root.add_child(c)
		while r.get("karts") == null or r.karts.is_empty():
			await get_tree().process_frame
		for f in 30:
			await get_tree().process_frame
		r.hud.visible = false
		if r.hud.get("root"):
			r.hud.root.visible = false
		var p: TrackPath = r.track.path
		var back := p.transform_at(-30.0)
		c.global_position = back.origin + back.basis.x * 2.0 + Vector3.UP * 7.0
		c.look_at(p.center_at(14.0) + Vector3.UP * 1.5, Vector3.UP)
		c.current = true
		for f in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		# 3:2 card from the middle of the frame
		var w := img.get_width()
		var h := img.get_height()
		var cw := mini(w, int(h * 1.5))
		img = img.get_region(Rect2i((w - cw) / 2, 0, cw, h))
		img.resize(480, 320, Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "tracks"))
		img.save_png(ProjectSettings.globalize_path(OUT + "tracks/%s.png" % tr["id"]))
		print("track card ", tr["id"])
		if tr["id"] != "city17_circuit":
			# a scenic still for the main menu, further round the lap
			var at := p.transform_at(p.length * float(BG_AT.get(tr["id"], 0.3)))
			c.global_position = at.origin - at.basis.z * -14.0 + at.basis.x * 3.0 + Vector3.UP * 5.5
			c.look_at(p.center_at(p.length * float(BG_AT.get(tr["id"], 0.3)) + 40.0) + Vector3.UP * 3.0, Vector3.UP)
			for f in 6:
				await get_tree().process_frame
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "backgrounds"))
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "backgrounds/%s.png" % tr["id"]))
		r.queue_free()
		c.queue_free()
		for f in 3:
			await get_tree().process_frame
	Game.settings["track"] = keep


func _leader() -> Kart:
	var best: Kart = null
	for k in race.karts:
		if best == null or k.total_progress > best.total_progress:
			best = k
	return best


func _shot(name: String) -> void:
	shots_done[name] = true
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "backgrounds"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "backgrounds/%s.png" % name))
	print("background ", name)
	race.camera.make_current()
	if shots_done.size() >= 4:
		get_tree().quit()


func _process(delta: float) -> void:
	if race == null or race.get("karts") == null or race.karts.is_empty():
		return
	race.hud.visible = false
	if race.hud.get("root"):
		race.hud.root.visible = false
	t += delta
	var p: TrackPath = race.track.path
	var L := _leader()
	if L == null:
		return
	var s := L.lap_progress if L.lap >= 0 else 0.0
	if int(t * 2.0) != int((t - delta) * 2.0) and int(t) % 10 == 0:
		print("t=%.0f leader s=%.0f lap=%d" % [t, s, L.lap])
	if not shots_done.has("grid") and t > 2.0:
		var tr := p.transform_at(-58.0)
		cam.global_position = tr.origin + tr.basis.x * 2.5 + Vector3.UP * 2.6
		cam.look_at(p.center_at(6.0) + Vector3.UP * 7.5, Vector3.UP)
		_shot("grid")
	elif race.racing and not shots_done.has("city") and s > 130.0 and s < 400.0:
		cam.global_position = L.global_position - L.global_basis.x * 7.0 - L.global_basis.z * 16.0 + Vector3.UP * 3.2
		cam.look_at(L.global_position + L.global_basis.z * 4.0 + Vector3.UP * 1.5, Vector3.UP)
		_shot("city")
	elif race.racing and not shots_done.has("coast") and s > 760.0 and s < 1000.0:
		var i := p.index_at(s + 35.0)
		cam.global_position = p.center[i] + p.right[i] * 22.0 + Vector3.UP * 9.0
		cam.look_at(L.global_position + Vector3.UP * 1.0, Vector3.UP)
		_shot("coast")
	elif race.racing and not shots_done.has("canal") and s > 1560.0 and s < 1840.0:
		var c2 := p.index_at(s + 28.0)
		cam.global_position = p.center[c2] + p.right[c2] * 4.0 + Vector3.UP * 4.0
		cam.look_at(L.global_position + Vector3.UP * 1.0, Vector3.UP)
		_shot("canal")
	if t > 200.0:
		get_tree().quit()
