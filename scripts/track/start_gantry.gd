class_name StartGantry
extends Node3D
## Start/finish arch in Combine metal carrying a Breencast monitor: a live
## render of Dr. Breen's head with his City 17 broadcasts playing.

var feed: BreenFeed
var speaker: AudioStreamPlayer3D
var _t := 0.0
var _next_line := 2.0
var _lines: Array[String] = []


func setup(xf: Transform3D, road_width: float) -> void:
	global_transform = xf
	var metal := SourceMaterials.world_material("metal/citadel_metalwall072a", Vector2(1, 3))
	var half := road_width * 0.5 + 1.8
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 10.0, 1.4)
		pillar.mesh = bm
		pillar.material_override = metal
		pillar.position = Vector3(side * half, 5.0, 0)
		add_child(pillar)
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.set_meta("surface", "wall")
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bm.size
		cs.shape = sh
		body.add_child(cs)
		pillar.add_child(body)
		var lamp := Game.spawn_model("props_combine/combine_light001a")
		lamp.position = Vector3(side * half, 10.0, 0)
		add_child(lamp)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(half * 2.0 + 1.0, 1.4, 1.2)
	beam.mesh = bb
	beam.material_override = metal
	beam.position = Vector3(0, 9.5, 0)
	add_child(beam)
	_build_feed()
	for face in [1.0, -1.0]:
		var scr := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(8.0, 4.5)
		scr.mesh = q
		scr.material_override = feed.screen_material()
		scr.position = Vector3(0, 12.6, 0.65 * face)
		scr.rotation.y = 0.0 if face > 0 else PI
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(scr)
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(8.6, 5.1, 1.0)
		frame.mesh = fb
		frame.material_override = metal
		frame.position = Vector3(0, 12.6, 0)
		add_child(frame)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.8, 1.0)
	glow.light_energy = 1.5
	glow.omni_range = 18.0
	glow.position = Vector3(0, 12.0, 2.5)
	add_child(glow)
	speaker = AudioStreamPlayer3D.new()
	speaker.unit_size = 35.0
	speaker.max_distance = 400.0
	speaker.volume_db = 2.0
	speaker.bus = "Voice"
	speaker.position = Vector3(0, 12.0, 0)
	add_child(speaker)
	var d := DirAccess.open("res://assets/sound/vo/breencast")
	if d:
		for f in d.get_files():
			if f.ends_with(".wav"):
				_lines.append("res://assets/sound/vo/breencast/" + f)
	_lines.sort()


func _build_feed() -> void:
	feed = BreenFeed.new()
	add_child(feed)


func _process(delta: float) -> void:
	_t += delta
	_next_line -= delta
	if _next_line <= 0.0 and not _lines.is_empty() and not speaker.playing:
		speaker.stream = Game.stream(_lines[randi() % _lines.size()])
		speaker.play()
		_next_line = randf_range(4.0, 9.0)
