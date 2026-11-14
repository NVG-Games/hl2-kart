class_name TeleportRescue
extends Rescuer
## The Black Mesa rescue (Rescuer), at Black Mesa and on Surface Tension: a Half-Life teleport.
## Round the kart where it stopped (from the surface where it sank, round it as it falls) a field
## gathers: a faint column of green-yellow light, motes circling it, arcs crackling down round its
## foot. Over the last AIM seconds before the kart's photo_time it builds up with the suck-in: the
## column swells, the motes spiral in and race round it, rings run up it and the arcs come fast.
## Then it flashes and the kart is gone (the screen of the camera following it flashes pale
## green-yellow); the kart materialises on the road inside a second swirl that throws the motes
## out and dies away.

const COL := Color(0.72, 1.0, 0.38)  # Half-Life's teleport green-yellow
const FLASH := Color(0.86, 1.0, 0.64)  # the screen flash, paler
const HEIGHT := 9.0  # metres the column rises over its foot (less under a roof)
const WIDE := 3.6  # the column's width at its fullest
const FADE := 1.2  # seconds the swirl on the road takes to die away
const MOTES := 14
const RINGS := 3
## the column's pieces up its height: from, to (fractions of it) and brightness, fainter upwards
const PIECES := [[0.0, 0.3, 1.0], [0.3, 0.6, 0.6], [0.6, 1.0, 0.28]]
## sounds (Rescuer.sounds: the first list of them this install has): the suck-in, loudest just
## after it starts, so it peaks at the take; the blast; the suck-out, which swells towards its
## end, so only its last SWELL seconds as the kart comes out; a crackle as the field gathers
const SUCK_IN := [["hl1src/ambience/port_suckin1.wav"], ["hl1src/weapons/electro4.wav"]]
const BLAST := [["hl1src/debris/beamstart1.wav", "hl1src/debris/beamstart2.wav", "hl1src/debris/beamstart7.wav"],
	["ambient/machines/teleport1.wav", "ambient/machines/teleport3.wav", "ambient/machines/teleport4.wav"],
	["hl1src/debris/zap4.wav"]]
const SUCK_OUT := [["hl1src/ambience/port_suckout1.wav"], ["hl1src/weapons/electro5.wav"]]
const CRACKLE := [["hl1src/debris/zap1.wav"]]
const SWELL := 1.7

var _up := Vector3.UP
var _top := HEIGHT  # metres from the foot to the column's top
var _mid := 1.0  # metres from the foot to the kart's middle: the glow and the light
var _build := 0.0  # the build-up over the last AIM seconds, 0..1 (1 out on the road)
var _bright := 0.0  # how bright the field is now, 0..1
var _width := 0.0  # the column's width now, a fraction of WIDE
var _orbit := 2.8  # metres from the column's axis the motes circle
var _spin := 0.0  # radians the motes have turned
var _rise := 0.0  # how far the motes and rings have climbed (it wraps)
var _out := -1.0  # t it began to die away (the kart out on the road, or let go), -1 before
var _from := 1.0  # how bright it was then
var _cut := false  # let go before the take: it only dies away where it is
var _sparked := false  # the burst round the kart as it shows again on the road
var _arc_in := 0.3  # seconds to the next arc
var _pieces: Array[MeshInstance3D] = []
var _core: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _motes: Array[MeshInstance3D] = []
var _mote_mat: StandardMaterial3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()  # the arcs' scatter (looks only)


func setup(k: Kart) -> void:
	super(k)
	_rng.randomize()
	# up the way its gravity pulls where it stopped (off a tube's wall too); the sky where it
	# sinks or falls
	if k.rescue == Kart.Rescue.SCAN:
		_up = Rescuer.stuck_up(k)
	_stand(k.global_position, k.rescue == Kart.Rescue.SINK)
	for p in PIECES:
		var b := Effects.beam_node(Color(COL, 0.0), 0.1)
		b.extra_cull_margin = WIDE
		add_child(b)
		_pieces.append(b)
	_core = Effects.beam_node(Color(1.0, 1.0, 0.85, 0.0), 0.1)
	_core.extra_cull_margin = WIDE
	add_child(_core)
	for i in RINGS:
		_rings.append(Effects.ground_ring(self, global_position, _up, 1.0, Color(COL, 0.0)))
	_mote_mat = Rescuer.glow_material(Color(COL.lightened(0.35), 0.0))
	for i in MOTES:
		var m := Rescuer.glow_quad(_mote_mat)
		add_child(m)
		_motes.append(m)
	_glow_mat = Rescuer.glow_material(Color(COL, 0.0))
	_glow = Rescuer.glow_quad(_glow_mat)
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = COL
	_light.omni_range = 14.0
	_light.light_energy = 0.0
	add_child(_light)
	_play(CRACKLE, global_position, -6.0, 1.0, 12.0, true)
	_draw()


## Stands the field at the kart at `kp`: its foot on the ground under the kart (on the surface of
## the liquid it sinks in with `liquid`, just under the kart as it falls), its top short of a roof.
func _stand(kp: Vector3, liquid: bool) -> void:
	var foot := kp - _up * 0.5
	if liquid:
		foot = Vector3(kp.x, kart.liquid.x, kp.z)
	else:
		var ground := _ray(kp + _up * 0.5, kp - _up * 2.5)
		if not ground.is_empty():
			foot = ground["position"]
	var roof := _ray(foot + _up, foot + _up * HEIGHT)
	_top = HEIGHT if roof.is_empty() else maxf(foot.distance_to(roof["position"]) - 0.3, 2.5)
	_mid = clampf((kp - foot).dot(_up) + 0.5, 0.8, 3.5)
	global_transform = Transform3D(Rescuer.up_basis(_up), foot)


## Level (across the column), the way `a` radians round it.
func _flat(a: float) -> Vector3:
	return global_basis * Vector3(cos(a), 0.0, sin(a))


## With the kart until the take (a sinking kart rises out of the liquid inside the column).
func _approach(kp: Vector3, _delta: float) -> void:
	if not _taking():
		_stand(kp, kart.rescue == Kart.Rescue.SINK)


func _aim() -> void:
	_play(SUCK_IN, global_position, 2.0, 1.0, 18.0, true)


func _flash_color() -> Color:
	return FLASH


## The flash where the kart was (this frame its owner may already have it on the road, so the field
## is still where it stood last frame): sparks, a shock ring, light, arcs and the blast. The field
## is gone with the kart until it comes out.
func _take() -> void:
	var foot := global_position
	var c := foot + _up * _mid
	var world := get_parent()
	Effects.sparks(world, c, 2.4, COL)
	Effects.shock_ring(world, foot, _up, WIDE * 2.0, Color(COL, 0.9), 0.55)
	Effects.flash_light(world, c, COL, 9.0, 18.0, 0.5)
	for i in 4:
		var to := c + _flat(_rng.randf() * TAU) * _rng.randf_range(3.0, 5.0) + _up * _rng.randf_range(-0.5, 2.5)
		Effects.lightning(world, c, to, COL, 0.2, 6, 0.6)
	_play(BLAST, c, 4.0, 1.0, 22.0)
	visible = false


## Out on the road inside the second swirl, bright at once, dying away over FADE.
func _arrive(kp: Vector3, _far: bool) -> void:
	_up = _road_up()
	_stand(kp, false)
	visible = true
	_out = t
	_from = 1.0
	_build = 1.0
	var c := global_position + _up * _mid
	Effects.shock_ring(get_parent(), global_position, _up, WIDE * 1.5, Color(COL, 0.8), 0.7)
	Effects.flash_light(get_parent(), c, COL, 7.0, 14.0, 0.7)
	var p := _play(SUCK_OUT, c, 2.0, 1.0, 18.0)
	if p and p.stream.get_length() > SWELL + 0.5:
		p.seek(p.stream.get_length() - SWELL)


## As the kart shows again (KartVisual._shown), a burst of sparks round it.
func _leave(kp: Vector3, _delta: float, since: float) -> void:
	if _out >= 0.0 and not _cut and not _sparked and since >= 0.25:
		_sparked = true
		Effects.sparks(get_parent(), kp + _up * 0.8, 1.4, COL)


func _abandon() -> void:
	_out = t
	_from = _bright
	_cut = true


func _after_tick(_kp: Vector3, delta: float) -> void:
	if _shot < 0.0:
		# gathering, then the build-up over the last AIM seconds
		_build = clampf((kart.state_time - (kart.photo_time() - AIM)) / AIM, 0.0, 1.0)
		var b2 := _build * _build
		var come := clampf(t / 0.5, 0.0, 1.0)
		_bright = come * (0.35 + 0.65 * _build)
		_width = come * (0.22 + 0.78 * b2)
		_orbit = lerpf(2.8, 0.9, b2)
		_spin += delta * (1.6 + 9.0 * b2)
		_rise += delta * (0.25 + 1.2 * _build)
		_arcs(delta, lerpf(0.45, 0.07, _build))
	elif _out >= 0.0:
		# out on the road (or let go): the motes thrown out, the column thinning, all of it fading
		var f := clampf((t - _out) / FADE, 0.0, 1.0)
		_bright = _from * (1.0 - f) * (1.0 - f)
		_width = _from * (1.0 - 0.85 * f)
		_orbit = lerpf(0.9, 5.5, f)
		_spin += delta * (9.0 - 7.0 * f)
		_rise -= delta * (1.2 - 0.8 * f)
		if not _cut and f < 0.3:
			_arcs(delta, 0.1)
	else:
		return  # taken, not out on the road yet: nothing to see
	_draw()


## Now and then an arc from the column down to the ground round its foot, every `every` seconds or so.
func _arcs(delta: float, every: float) -> void:
	_arc_in -= delta
	if _arc_in > 0.0:
		return
	_arc_in = every * _rng.randf_range(0.6, 1.4)
	var a := _rng.randf() * TAU
	var foot := global_position
	var from := foot + _up * _rng.randf_range(0.6, minf(_top, 5.0)) + _flat(a) * WIDE * 0.15 * _width
	var to := foot + _flat(a + _rng.randf_range(-0.6, 0.6)) * _rng.randf_range(1.6, 3.4) + _up * 0.1
	Effects.lightning(get_parent(), from, to, COL, 0.14, 5, 0.45)


## Lays out the column, the rings, the motes, the glow and the light as the field is now.
func _draw() -> void:
	var foot := global_position
	for i in PIECES.size():
		var p: Array = PIECES[i]
		var b := _pieces[i]
		var lo: float = _top * p[0] - (0.4 if i == 0 else 0.0)
		Effects.place_beam(b, foot + _up * lo, foot + _up * (_top * float(p[1])))
		b.set_instance_shader_parameter("col", Color(COL, _bright * float(p[2]) * (0.42 + 0.08 * sin(t * 37.0 + i))))
		b.set_instance_shader_parameter("width", WIDE * _width * (1.0 - 0.3 * float(p[0])))
	Effects.place_beam(_core, foot - _up * 0.3, foot + _up * _top * 0.75)
	_core.set_instance_shader_parameter("col", Color(1.0, 1.0, 0.85, _bright * 0.8))
	_core.set_instance_shader_parameter("width", 0.2 + _width)
	var span := minf(_top, 2.0 + 3.5 * _build)
	for i in RINGS:
		var u := fposmod(_rise * 0.6 + float(i) / RINGS, 1.0)
		var r := WIDE * 0.5 * (1.25 - 0.45 * u) * (0.55 + 0.45 * _width)
		Effects.place_ring(_rings[i], foot + _up * (u * span), _up, r)
		_rings[i].set_instance_shader_parameter("col", Color(COL, _bright * sin(u * PI) * 0.85))
	for i in MOTES:
		var u := fposmod(_rise + float(i) * 0.618, 1.0)  # spread up the column
		var a := _spin + float(i) * TAU * 2.0 / MOTES  # two turns of a spiral
		var r := _orbit * (1.0 - 0.35 * u)
		_motes[i].position = Vector3(cos(a) * r, u * span, sin(a) * r)
		_motes[i].scale = Vector3.ONE * maxf((0.35 + 0.45 * _bright) * sin(u * PI), 0.01)
	_mote_mat.albedo_color.a = clampf(_bright * 1.1, 0.0, 1.0)
	_glow.position = Vector3(0.0, _mid, 0.0)
	_glow.scale = Vector3.ONE * maxf((1.2 + 4.5 * _build * _build) * _bright, 0.01)
	_glow_mat.albedo_color.a = clampf(_bright * 0.75, 0.0, 1.0)
	_light.position = Vector3(0.0, _mid, 0.0)
	_light.light_energy = 5.5 * _bright * _bright
