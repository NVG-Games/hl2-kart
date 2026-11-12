class_name BackgroundLife
extends Node3D
## Ambient City 17 life: a Combine gunship circling the circuit, a dropship
## crossing now and then, seagulls over the coast and distant battle sounds.

var track: Track
var gunship: Node3D
var dropship: Node3D
var birds: Array[Node3D] = []
var _orbits: Array = []  # [x, y, z, radius] per seagull over open water (track JSON "seagulls"), when the circuit has them
var _t := 0.0
var _drop_t := 20.0
var _ambient_t := 8.0
var _center := Vector3(180, 0, 290)


func setup(trk: Track) -> void:
	track = trk
	_orbits = trk.data.get("seagulls", [])
	# circle over the middle of whatever circuit this is
	var sum := Vector3.ZERO
	for c in trk.path.center:
		sum += c
	_center = sum / maxf(1.0, trk.path.center.size())
	_center.y = 0.0
	# a circuit with a strafing gunship (an air_strafe track hazard) has that one in the sky
	var hz = trk.get("hazards")
	if hz == null or not hz.has_type("air_strafe"):
		gunship = Game.spawn_model("gunship")
		gunship.scale = Vector3.ONE * 1.4
		add_child(gunship)
		var rotor := AudioStreamPlayer3D.new()
		rotor.stream = Game.stream("res://assets/sound/npc/combine_gunship/gunship_engine_loop3.wav")
		rotor.unit_size = 40.0
		rotor.max_distance = 900.0
		rotor.bus = "SFX"
		rotor.volume_db = -4.0
		gunship.add_child(rotor)
		rotor.play()
	dropship = Game.spawn_model("combine_dropship")
	dropship.scale = Vector3.ONE * 1.2
	dropship.visible = false
	add_child(dropship)
	for i in 10:
		var b := Game.spawn_model("seagull")
		b.scale = Vector3.ONE * 1.5
		add_child(b)
		birds.append(b)
	var wind := AudioStreamPlayer.new()
	wind.stream = Game.stream("res://assets/sound/ambient/atmosphere/city_rumble_loop1.wav")
	wind.volume_db = -14.0
	wind.bus = "SFX"
	add_child(wind)
	wind.play()


func _process(delta: float) -> void:
	_t += delta
	if gunship:
		var a := _t * 0.06
		var gp := _center + Vector3(cos(a) * 420.0, 95.0 + sin(_t * 0.3) * 10.0, sin(a) * 360.0)
		var ahead := _center + Vector3(cos(a + 0.05) * 420.0, 95.0, sin(a + 0.05) * 360.0)
		gunship.global_position = gp
		gunship.look_at(ahead, Vector3.UP)
		gunship.rotate_object_local(Vector3.UP, PI)
		gunship.rotate_object_local(Vector3.FORWARD, 0.25)
	for i in birds.size():
		var b := birds[i]
		var ba := _t * (0.25 + i * 0.02) + i * 0.7
		var c := Vector3(560 + (i % 3) * 40, -2.0 + (i % 4) * 4.0, 560 + (i % 2) * 60)
		var rad := 30.0 + i * 4.0
		if i < _orbits.size():
			var o: Array = _orbits[i]
			c = Vector3(float(o[0]), float(o[1]), float(o[2]))
			rad = float(o[3])
		b.global_position = c + Vector3(cos(ba) * rad, sin(_t * 0.7 + i) * 3.0, sin(ba) * rad)
		b.rotation.y = -ba
	_drop_t -= delta
	if _drop_t <= 0.0 and not dropship.visible:
		dropship.visible = true
		dropship.set_meta("u", 0.0)
		Game.play_3d("res://assets/sound/ambient/levels/citadel/citadel_flyer1.wav", _center + Vector3(0, 140, 0), 6.0, 1.0, 120.0)
	if dropship.visible:
		var u: float = dropship.get_meta("u") + delta / 26.0
		dropship.set_meta("u", u)
		var from := _center + Vector3(-1200, 160, -500)
		var to := _center + Vector3(1200, 180, 700)
		dropship.global_position = from.lerp(to, u)
		# along its flight line: looking at `to` fails once it gets there
		dropship.look_at(dropship.global_position + (to - from), Vector3.UP)
		dropship.rotate_object_local(Vector3.UP, PI * 0.5)
		if u >= 1.0:
			dropship.visible = false
			_drop_t = randf_range(35.0, 60.0)
	_ambient_t -= delta
	if _ambient_t <= 0.0:
		_ambient_t = randf_range(10.0, 22.0)
		var snd: String = Game.pick(["res://assets/sound/ambient/levels/streetwar/city_battle1.wav",
			"res://assets/sound/ambient/levels/streetwar/city_battle2.wav",
			"res://assets/sound/ambient/levels/coast/seagulls_ambient1.wav",
			"res://assets/sound/ambient/levels/coast/coastbird4.wav",
			"res://assets/sound/ambient/machines/thumper_hit.wav"])
		var cam := get_viewport().get_camera_3d()
		if cam:
			Game.play_3d(snd, cam.global_position + Vector3(randf_range(-80, 80), 20, randf_range(-80, 80)), -8.0, 1.0, 60.0)
