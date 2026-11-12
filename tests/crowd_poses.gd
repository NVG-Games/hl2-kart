extends Node3D
## Crowd pose sheets: every spectator model plays every crowd clip (and the mirrored
## ones) on a neutral floor; one PNG per clip, a strip per key and row of ten models.
## A last still "look" has them frozen, heads turned by CrowdLook toward a point on
## their right; exits 1 if a frozen head keeps turning.
## usage: godot --path . res://tests/crowd_poses.tscn -- <out_prefix> [model,model,...] [clip,clip,...]

const DEFAULT := ["humans/group01/male_01", "humans/group01/female_01", "humans/group02/male_03",
	"humans/group03/female_03", "humans/group01/male_cheaple", "police", "hl1/sci_glasses", "hl1/sci_einstein",
	"hl1/guard", "hl1/marine_mask", "vortigaunt", "hl1/islave_hd", "zombie/classic", "hl1/gman", "gman_high",
	"hl1/holo", "kleiner", "odessa", "hl1/hgrunt", "hl1/islave"]

var actors: Array[CrowdActor] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://crowd_pose"
	var keys: Array = Array(a[1].split(",")) if a.size() > 1 and a[1] != "" else DEFAULT
	keys = keys.filter(func(k: String) -> bool: return Game.models.has(k))
	keys = keys.slice(0, 20)
	var only: Array = Array(a[2].split(",")) if a.size() > 2 else []
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.46, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	floor_mi.mesh = pm
	add_child(floor_mi)
	for i in keys.size():
		var pos := Vector3((i % 10 - 4.5) * 1.35, 0, 0)
		var act := CrowdActor.new()
		add_child(act)
		act.setup({"pos": [pos.x, pos.y, pos.z], "yaw": 0.0, "role": "metrocop" if keys[i] == "police" else "citizen",
			"seed": 3}, keys[i], 0.0)
		if act.skel:
			act.animate(CrowdPoses.library(keys[i], act.skel, act.model), false)
		actors.append(act)
	print("models: ", keys)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 1.4, 11.0), Vector3(0, 1.0, 0.0))
	var size := get_viewport().get_visible_rect().size
	# the band from the floor to raised hands, cut out of each shot
	var band := Rect2i(0, int(size.y * 0.3), int(size.x), int(size.y * 0.37))
	for clip in CrowdPoses.CLIPS:
		for mirror in ([false, true] if clip in CrowdPoses.MIRRORED else [false]):
			var cname: String = clip + ("_m" if mirror else "")
			if not only.is_empty() and not only.has(clip):
				continue
			var c: Array = CrowdPoses.CLIPS[clip]
			var panels: Array[Image] = []
			for k in c[0]:
				for act in actors:
					if act.player and act.player.has_animation(cname):
						act.player.active = true
						act.player.play(cname, 0.0)
						act.player.speed_scale = 0.0
						act.player.seek(float(k[1]), true)
				# ten at a time: the first row, then the second
				for row in (actors.size() + 9) / 10:
					for i in actors.size():
						actors[i].visible = i / 10 == row
					for f in 3:
						await get_tree().process_frame
					panels.append(get_viewport().get_texture().get_image().get_region(band))
			_save_sheet(panels, "%s_%s.png" % [out, cname])
	# heads follow a point on their right while the players stand frozen
	var target := Vector3(-9.0, 1.7, 6.0)
	for act in actors:
		if act.player:
			act.player.play("idle", 0.0)
			act.player.seek(0.0, true)
			act.player.active = false
		if act.skel:
			var l := CrowdLook.new()
			if l.setup(act.skel):
				act.skel.add_child(l)
				l.target = target
				l.goal = 1.0
	await get_tree().create_timer(2.5).timeout
	var looks: Array[Image] = []
	for row in (actors.size() + 9) / 10:
		for i in actors.size():
			actors[i].visible = i / 10 == row
		for f in 3:
			await get_tree().process_frame
		looks.append(get_viewport().get_texture().get_image().get_region(band))
	_save_sheet(looks, "%s_look.png" % out)
	# frozen with the look on must not keep turning: the head stays where it settled
	var drift := 0.0
	var before := []
	for act in actors:
		before.append(_head(act))
	await get_tree().create_timer(1.0).timeout
	for i in actors.size():
		if before[i] != null:
			drift = maxf(drift, ((before[i] as Transform3D).basis.get_rotation_quaternion()
				.angle_to(_head(actors[i]).basis.get_rotation_quaternion())))
	print("look drift over 1 s (rad): %.4f" % drift)
	get_tree().quit(1 if drift > 0.02 else 0)


func _head(act: CrowdActor) -> Variant:
	if act.skel == null:
		return null
	var h := BipedPose.limb(act.skel, "Head1")
	return act.skel.get_bone_global_pose(h) if h >= 0 else null


## Panels stacked top to bottom (each key: the first row of models, then the second).
func _save_sheet(panels: Array[Image], path: String) -> void:
	var w := panels[0].get_width()
	var h := panels[0].get_height()
	var sheet := Image.create(w, h * panels.size(), false, panels[0].get_format())
	for i in panels.size():
		sheet.blit_rect(panels[i], Rect2i(0, 0, w, h), Vector2i(0, i * h))
	sheet.save_png(path)
