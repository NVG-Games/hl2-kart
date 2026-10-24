class_name StartGantry
extends Node3D
## Start/finish arch. City 17: Combine metal carrying a Breencast monitor (a
## live render of Dr. Breen's head with his broadcasts playing). Black Mesa: a
## hazard-striped steel frame with the Sector C map and the VOX announcer.
## Xen: two giant crystals with an energy beam. The desert: an HECU frame with
## radio chatter.

var feed: BreenFeed
var speaker: AudioStreamPlayer3D
var _t := 0.0
var _next_line := 2.0
var _lines: Array[String] = []
var _words: Array[String] = []  # VOX sentence being spoken, word by word


var style := "combine"


func setup(xf: Transform3D, road_width: float, kind := "combine") -> void:
	global_transform = xf
	style = kind
	if kind != "combine":
		_themed(road_width)
		return
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


## Arches for the other worlds.
func _themed(road_width: float) -> void:
	var half := road_width * 0.5 + 1.8
	match style:
		"blackmesa":
			# under the lobby ceiling (12 m)
			_frame(half, 7.0, SourceMaterials.world_material("goldsrc/metal_wall04", Vector2(1, 3)),
				SourceMaterials.world_material("goldsrc/stripes1", Vector2(1, 3)))
			_panel("goldsrc/signc1a1_1", Vector2(6.4, 4.8), 9.3)
			_glow_light(Color(1.0, 0.72, 0.35), Vector3(0, 6.0, 2.0), 22.0, 1.8)
			_speaker()
			_next_line = 3.0
		"military":
			_frame(half, 9.5, SourceMaterials.world_material("goldsrc/out_w3", Vector2(1, 2)),
				SourceMaterials.world_material("goldsrc/out_w4", Vector2(1, 1)))
			_panel("goldsrc/c2a5g_sign1", Vector2(8.0, 4.0), 12.2)
			for side in [-1.0, 1.0]:
				var lamp := Game.spawn_model("props_c17/light_floodlight02_off")
				lamp.position = Vector3(side * half, 9.6, 0.8)
				add_child(lamp)
			_speaker()
			for i in range(1, 6):
				_lines.append("res://assets/sound/hl1src/hgrunt/c2a2_hg_chat%da.wav" % i)
			_lines.append("res://assets/sound/hl1src/hgrunt/c2a5_hg_abandon.wav")
			_lines.append("res://assets/sound/hl1src/hgrunt/c2a5_hg_lebuz.wav")
		"xen":
			for side in [-1.0, 1.0]:
				var c := Game.spawn_model("hl1/crystal")
				c.scale = Vector3.ONE * 5.5
				c.position = Vector3(side * (half + 1.0), -0.5, 0)
				c.rotation.y = 0.7 * side
				add_child(c)
				var body := StaticBody3D.new()
				body.collision_layer = Game.LAYER_WORLD
				body.set_meta("surface", "wall")
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = 1.6
				cyl.height = 10.0
				cs.shape = cyl
				cs.position = Vector3(side * (half + 1.0), 5.0, 0)
				body.add_child(cs)
				add_child(body)
			var beam := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.35
			bm.bottom_radius = 0.35
			bm.height = half * 2.0 + 2.0
			beam.mesh = bm
			beam.rotation.z = PI * 0.5
			beam.position = Vector3(0, 10.5, 0)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.55, 1.0, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 1.0, 0.5)
			mat.emission_energy_multiplier = 3.0
			beam.material_override = mat
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(beam)
			_glow_light(Color(0.5, 1.0, 0.6), Vector3(0, 10.0, 0), 26.0, 2.2)


func _frame(half: float, height: float, metal: Material, band: Material) -> void:
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, height, 1.4)
		pillar.mesh = bm
		pillar.material_override = metal
		pillar.position = Vector3(side * half, height * 0.5, 0)
		add_child(pillar)
		var stripe := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(1.3, 1.6, 1.5)
		stripe.mesh = sb
		stripe.material_override = band
		stripe.position = Vector3(side * half, 0.8, 0)
		add_child(stripe)
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.set_meta("surface", "wall")
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bm.size
		cs.shape = sh
		body.add_child(cs)
		pillar.add_child(body)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(half * 2.0 + 1.2, 1.4, 1.2)
	beam.mesh = bb
	beam.material_override = metal
	beam.position = Vector3(0, height - 0.5, 0)
	add_child(beam)


## A sign on the arch, readable from both sides.
func _panel(mat_name: String, size: Vector2, y: float) -> void:
	var mat := SourceMaterials.world_material(mat_name, Vector2.ONE)
	for face in [1.0, -1.0]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = size
		q.mesh = qm
		q.material_override = mat
		q.position = Vector3(0, y, 0.55 * face)
		q.rotation.y = 0.0 if face > 0 else PI
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(size.x + 0.5, size.y + 0.5, 1.0)
	frame.mesh = fb
	frame.material_override = SourceMaterials.world_material("goldsrc/metal_wall04", Vector2.ONE) \
		if Game.materials_db.has("goldsrc/metal_wall04") else StandardMaterial3D.new()
	frame.position = Vector3(0, y, 0)
	add_child(frame)


func _glow_light(col: Color, pos: Vector3, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	add_child(l)


func _speaker() -> void:
	speaker = AudioStreamPlayer3D.new()
	speaker.unit_size = 35.0
	speaker.max_distance = 400.0
	speaker.volume_db = 2.0
	speaker.bus = "Voice"
	speaker.position = Vector3(0, 11.0, 0)
	add_child(speaker)


func _build_feed() -> void:
	feed = BreenFeed.new()
	add_child(feed)


func _process(delta: float) -> void:
	if speaker == null:
		return
	_t += delta
	if style == "blackmesa":
		_vox(delta)
		return
	_next_line -= delta
	if _next_line <= 0.0 and not _lines.is_empty() and not speaker.playing:
		speaker.stream = Game.stream(_lines[randi() % _lines.size()])
		speaker.play()
		_next_line = randf_range(4.0, 9.0)


## The Black Mesa announcer: HL1 VOX words strung into sentences, one word at a time.
func _vox(delta: float) -> void:
	if speaker.playing:
		return
	if not _words.is_empty():
		speaker.stream = Game.stream("res://assets/sound/hl1src/vox/%s.wav" % _words.pop_front())
		speaker.play()
		return
	_next_line -= delta
	if _next_line > 0.0:
		return
	var sentences: Array = Game.voices.get("_vox", [])
	if sentences.is_empty():
		return
	for w in sentences[randi() % sentences.size()]:
		_words.append(str(w))
	_next_line = randf_range(9.0, 16.0)
