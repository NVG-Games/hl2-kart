class_name CombineTeleport
extends Rescuer
## The Nova Prospekt rescue (Rescuer): a Combine teleport, in the cold blue-white of the prison's
## own. Where the kart stopped (from the surface where it sinks, round it as it falls) two rings of
## blue light mark the ground under it like a teleport pad, and two hoops of energy come up round
## it, leaning on axes that turn like a gyroscope's, lights racing round them and arcs crackling
## from them onto the kart. Over the last AIM seconds before the kart's photo_time the hoops spin up
## and close in until they sweep out a ball round the kart, and a bubble of white-blue energy swells
## inside it. Then it bursts in a white-blue flash (the screen of the camera following it flashes
## cold blue) and the kart is gone. On the road the bubble stands bright round the kart's new place
## with the hoops spinning round it, and as the kart shows again (KartVisual._shown) it collapses
## onto the kart and the hoops are flung out flat and fade. The Combine's teleport platform models
## are wall machines (a bracket with arms, a timer cabinet), so the ring is drawn as light.

const COL := Color(0.42, 0.7, 1.0)  # the Combine's cold energy blue (the AR2's ball, the prison's teleport)
const CORE := Color(0.86, 0.94, 1.0)  # its white-blue core
const FLASH := Color(0.66, 0.84, 1.0)  # the screen flash: colder and bluer than the scanner's white
const HOOP := 2.8  # metres: the hoops' radius as they come up round the kart
const CLOSE := 2.0  # their radius at the take, closed in on it
const FLUNG := 5.5  # their radius as they die away on the road
const TILT := 0.5  # radians the hoops lean as they come up ...
const SPUN := 1.25  # ... and spun up at the take, when they sweep out a ball round the kart
const BUBBLE := 2.6  # the bubble's radius at the take
const PAD := 3.2  # the outer ring on the ground under it (the inner one is PAD_IN of it)
const PAD_IN := 0.62
const HEIGHT := 3.9  # metres over its foot the whole of it takes; under a lower roof it is all smaller
const HOOPS := 2
const SEGS := 16  # straight pieces round a hoop
const BEADS := 3  # lights racing round each hoop
const SHOW := 0.25  # seconds after the take the kart is hidden (KartVisual._shown)
const FADE := 0.8  # seconds it takes to die away on the road once the kart shows
const CUT := 0.5  # seconds it takes to die away where it is when it is let go before the take
## sounds (Rescuer.sounds: the first list of them this install has): the machine winding up as it
## comes, the suck-in (timed to end at the take), the blast, the thunder after it as the kart comes
## out on the road, the crackle of the arcs. HL2's own teleports; an install without them has a
## force field and electric blasts.
const WINDUP := [["ambient/levels/labs/teleport_mechanism_windup1.wav"], ["ambient/energy/force_field_loop1.wav"]]
const SUCK_IN := [["ambient/levels/labs/teleport_preblast_suckin1.wav"]]
const BLAST := [["ambient/machines/teleport1.wav", "ambient/machines/teleport3.wav", "ambient/machines/teleport4.wav"],
	["ambient/levels/labs/electric_explosion1.wav", "ambient/levels/labs/electric_explosion2.wav"]]
const THUNDER := [["ambient/levels/labs/teleport_postblast_thunder1.wav"], ["ambient/levels/labs/electric_explosion4.wav"]]
const ZAPS := [["ambient/energy/zap1.wav", "ambient/energy/zap2.wav", "ambient/energy/zap3.wav", "ambient/energy/zap5.wav"]]
const THUNDER_HOLD := 0.9  # seconds the thunder plays at full before it fades ...
const THUNDER_FADE := 1.8  # ... over these (the file rolls on for eight)

var _up := Vector3.UP
var _mid := 1.0  # metres from the foot to the kart's middle: the bubble's centre
var _scale := 1.0  # the hoops, the bubble and the pad are this much smaller under a low roof
var _come := 0.0  # how far it has come up round the kart, 0..1
var _build := 0.0  # the build-up over the last AIM seconds, 0..1
var _bright := 0.0  # how bright the hoops and their lights are, 0..1
var _charge := 0.0  # how bright the bubble is, 0..1
var _pad := 0.0  # how bright the pad is, 0..1
var _radius := HOOP  # the hoops' radius now (before _scale)
var _tilt := TILT  # how far they lean now
var _bubble := 0.0  # the bubble's radius now (before _scale)
var _spin := 0.0  # radians the hoops' axes have turned
var _run := 0.0  # radians the lights have run round the hoops
var _out := -1.0  # t it stood out on the road (or began to die away, let go), -1 before
var _popped := -1.0  # t the bubble collapsed onto the kart as the kart showed again, -1 before
var _cut := false  # let go before the take: it only dies away where it is
var _from := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # let go: its brightness, charge, pad and bubble then
var _suck_len := 0.0  # seconds of the suck-in this install has (0: none)
var _sucked := false  # the suck-in has started
var _arc_in := 0.25  # seconds to the next arc
var _cores: Array[MeshInstance3D] = []  # each hoop's SEGS pieces, the thin bright core ...
var _glows: Array[MeshInstance3D] = []  # ... and the wide blue glow round it
var _beads: Array[MeshInstance3D] = []
var _bead_mat: StandardMaterial3D
var _pads: Array[MeshInstance3D] = []
var _ball: Node3D
var _halo_mat: StandardMaterial3D
var _shell_mat: StandardMaterial3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()  # the arcs' scatter (looks only)


func setup(k: Kart) -> void:
	super(k)
	_rng.randomize()
	# up the way its gravity pulls where it stopped (off a tube's wall too); the sky where it
	# sinks or falls
	if k.rescue == Kart.Rescue.SCAN:
		_up = Rescuer.stuck_up(k)
	_stand(k.global_position, k.rescue == Kart.Rescue.SINK)
	for i in HOOPS * SEGS:
		var c := Effects.beam_node(Color(CORE, 0.0), 0.1)
		c.extra_cull_margin = HOOP
		add_child(c)
		_cores.append(c)
		var g := Effects.beam_node(Color(COL, 0.0), 0.55, "materials/sprites/physbeam.png")
		g.extra_cull_margin = HOOP
		add_child(g)
		_glows.append(g)
	_bead_mat = Rescuer.glow_material(Color(CORE, 0.0))
	for i in HOOPS * BEADS:
		var b := Rescuer.glow_quad(_bead_mat)
		add_child(b)
		_beads.append(b)
	for i in 2:
		_pads.append(Effects.ground_ring(self, global_position, _up, PAD, Color(COL, 0.0)))
	# the bubble: the Xen portal's ball pieces (the energy ball's kind of material, which the race
	# draws once while it loads) in the Combine's colours, see-through so the kart shows inside
	_ball = Node3D.new()
	add_child(_ball)
	_halo_mat = XenPortal._ball_material(COL, 0.0, 2.0)
	_ball.add_child(XenPortal._mesh(1.0, _halo_mat))
	_shell_mat = XenPortal._ball_material(CORE, 0.0, 1.5)
	_ball.add_child(XenPortal._mesh(1.08, _shell_mat))
	_glow_mat = Rescuer.glow_material(Color(COL, 0.0))
	_glow = Rescuer.glow_quad(_glow_mat)
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = COL
	_light.omni_range = 13.0
	_light.light_energy = 0.0
	add_child(_light)
	_hum = _play(WINDUP, global_position, -6.0, 1.0, 14.0, true)
	var suck := Rescuer.sounds(SUCK_IN)
	_suck_len = Game.stream(suck[0]).get_length() if not suck.is_empty() else 0.0
	_sucked = _suck_len <= 0.0
	_draw()


## Stands it at the kart at `kp`: its foot on the ground under the kart (on the surface of the liquid
## it sinks in with `liquid`, just under the kart as it falls), all of it smaller under a low roof.
func _stand(kp: Vector3, liquid: bool) -> void:
	var foot := kp - _up * 0.5
	if liquid:
		foot = Vector3(kp.x, kart.liquid.x, kp.z)
	else:
		var ground := _ray(kp + _up * 0.5, kp - _up * 2.5)
		if not ground.is_empty():
			foot = ground["position"]
	_mid = clampf((kp - foot).dot(_up) + 0.5, 0.8, 2.5)
	var roof := _ray(foot + _up * 0.5, foot + _up * HEIGHT)
	var room := HEIGHT if roof.is_empty() else foot.distance_to(roof["position"]) - 0.3
	_scale = clampf((room - _mid) / (HEIGHT - _mid), 0.4, 1.0)
	global_transform = Transform3D(Rescuer.up_basis(_up), foot)


## With the kart until the take (a sinking kart rises out of the liquid inside it); the suck-in
## starts so that it ends at the take.
func _approach(kp: Vector3, _delta: float) -> void:
	if _taking():
		return  # (this frame the owner may already have the kart on the road)
	_stand(kp, kart.rescue == Kart.Rescue.SINK)
	var take := kart.photo_time()
	if not _sucked and kart.state_time >= take - _suck_len:
		_sucked = true
		var p := _play(SUCK_IN, global_position, 2.0, 1.0, 18.0, true)
		if p:
			p.seek(clampf(kart.state_time - (take - _suck_len), 0.0, maxf(_suck_len - 0.05, 0.0)))


func _flash_color() -> Color:
	return FLASH


## The burst where the kart was (this frame its owner may already have it on the road, so the field
## is still where it stood last frame): white-blue sparks, a shock ring along the ground, light,
## arcs flung out and the blast. The field is gone with the kart until it stands on the road.
func _take() -> void:
	var foot := global_position
	var c := foot + _up * _mid
	var world := get_parent()
	Effects.sparks(world, c, 2.6, CORE)
	Effects.shock_ring(world, foot, _up, PAD * 2.4 * _scale, Color(COL, 0.9), 0.5)
	Effects.flash_light(world, c, CORE, 10.0, 18.0, 0.45)
	for i in 5:
		var a := _rng.randf() * TAU
		var to := c + global_basis * Vector3(cos(a), _rng.randf_range(-0.2, 0.9), sin(a)) * _rng.randf_range(3.5, 5.5) * _scale
		Effects.lightning(world, c, to, COL, 0.22, 6, 0.7)
	_play(BLAST, c, 4.0, 1.0, 22.0)
	_stop_hum()
	visible = false


## Out on the road: the bubble stands bright round the kart's new place, the hoops spinning round
## it, with a shock ring, light and the thunder after the blast (faded out well before its end).
func _arrive(kp: Vector3, _far: bool) -> void:
	_up = _road_up()
	_stand(kp, false)
	visible = true
	_out = t
	_bright = 1.0
	_charge = 1.0
	_pad = 1.0
	_radius = CLOSE
	_tilt = SPUN
	_bubble = BUBBLE
	var c := global_position + _up * _mid
	Effects.shock_ring(get_parent(), global_position, _up, PAD * 1.8 * _scale, Color(COL, 0.8), 0.6)
	Effects.flash_light(get_parent(), c, CORE, 7.0, 14.0, 0.6)
	var p := _play(THUNDER, c, -3.0, 1.0, 20.0)
	if p:
		var tw := p.create_tween()
		tw.tween_interval(THUNDER_HOLD)
		tw.tween_property(p, "volume_db", -40.0, THUNDER_FADE)
		tw.tween_callback(p.queue_free)
	_draw()


## As the kart shows again (and the bubble has stood on the road a moment), the bubble collapses onto
## it in a burst of sparks; then the hoops are flung out flat and all of it dies away over FADE.
func _leave(kp: Vector3, delta: float, since: float) -> void:
	if _out < 0.0 or _cut:
		return
	if _popped < 0.0:
		_spin += delta * 14.0
		_run += delta * 18.0
		if since >= SHOW and t - _out >= 0.08:
			_popped = t
			Effects.sparks(get_parent(), kp + _up * 0.8, 1.5, CORE)
			Effects.shock_ring(get_parent(), global_position, _up, PAD * 1.4 * _scale, Color(CORE, 0.7), 0.4)
			_play(ZAPS, kp, -4.0, 1.0, 14.0)
		return
	var f := clampf((t - _popped) / FADE, 0.0, 1.0)
	var e := 1.0 - (1.0 - f) * (1.0 - f)
	_bubble = BUBBLE * maxf(1.0 - f * 3.5, 0.0)
	_charge = maxf(1.0 - f * 2.5, 0.0)
	_radius = lerpf(CLOSE, FLUNG, e)
	_tilt = lerpf(SPUN, 0.0, e)
	_bright = (1.0 - f) * (1.0 - f)
	_pad = 1.0 - f
	_spin += delta * lerpf(14.0, 2.0, f)
	_run += delta * lerpf(18.0, 4.0, f)


func _abandon() -> void:
	_cut = true
	_out = t
	_from = PackedFloat32Array([_bright, _charge, _pad, _bubble])
	_stop_hum()


func _stop_hum() -> void:
	if is_instance_valid(_hum):
		_hum.stop()
		_hum.queue_free()
	_hum = null


func _after_tick(_kp: Vector3, delta: float) -> void:
	if _shot < 0.0 and not _cut:
		# coming up round the kart, then the build-up over the last AIM seconds
		_come = smoothstep(0.0, 0.45, t)
		_build = clampf((kart.state_time - (kart.photo_time() - AIM)) / AIM, 0.0, 1.0)
		var b2 := _build * _build
		_bright = _come * (0.55 + 0.45 * _build)
		_charge = _come * (0.15 + 0.85 * b2)
		_pad = _come
		_radius = lerpf(HOOP * (0.4 + 0.6 * _come), CLOSE, b2)
		_tilt = lerpf(TILT, SPUN, _build)
		_bubble = BUBBLE * (0.3 + 0.7 * _build)
		_spin += delta * (1.8 + 12.0 * b2)
		_run += delta * (4.0 + 14.0 * _build)
		_arcs(delta, lerpf(0.32, 0.06, _build))
	elif _cut:
		var f := clampf((t - _out) / CUT, 0.0, 1.0)
		_bright = _from[0] * (1.0 - f)
		_charge = _from[1] * (1.0 - f)
		_pad = _from[2] * (1.0 - f)
		_bubble = _from[3] * (1.0 - 0.5 * f)
		_spin += delta * 2.0
		_run += delta * 4.0
	elif _out < 0.0:
		return  # taken, not on the road yet: nothing to see
	_draw()


## Now and then an arc from one of the hoops' lights onto the kart, every `every` seconds or so,
## some with a crackle.
func _arcs(delta: float, every: float) -> void:
	_arc_in -= delta
	if _arc_in > 0.0 or _beads.is_empty():
		return
	_arc_in = every * _rng.randf_range(0.6, 1.4)
	var from := _beads[_rng.randi() % _beads.size()].global_position
	var to := global_position + _up * _mid * _rng.randf_range(0.5, 1.2) \
		+ global_basis * Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))
	Effects.lightning(get_parent(), from, to, COL, 0.16, 5, 0.45)
	if _rng.randf() < 0.35:
		_play(ZAPS, to, -10.0, 1.0, 10.0)


## Lays out the hoops, their lights, the pad, the bubble, the glow and the light as it is now.
func _draw() -> void:
	var foot := global_position
	var b := global_basis
	var c := foot + _up * (_mid + 0.3 * _scale)
	var r := _radius * _scale
	var a := clampf(_bright, 0.0, 1.0)
	for h in HOOPS:
		# the hoops lean opposite ways on axes turning opposite ways round the up
		var sgn := 1.0 if h == 0 else -1.0
		var phi := _spin * sgn + float(h) * PI * 0.5
		var axis := b * Vector3(cos(phi), 0.0, sin(phi))
		var side := _up.rotated(axis, _tilt * sgn).cross(axis).normalized()
		var prev := c + axis * r
		for k in SEGS:
			var u := TAU * float(k + 1) / SEGS
			var p := c + (axis * cos(u) + side * sin(u)) * r
			var i := h * SEGS + k
			Effects.place_beam(_cores[i], prev, p)
			Effects.place_beam(_glows[i], prev, p)
			_cores[i].set_instance_shader_parameter("col", Color(CORE, a * 0.9))
			_glows[i].set_instance_shader_parameter("col", Color(COL, a * 0.5 * (0.8 + 0.2 * sin(t * 31.0 + k))))
			prev = p
		for j in BEADS:
			var u := _run * sgn + float(j) * TAU / BEADS + float(h)
			var bead := _beads[h * BEADS + j]
			bead.global_position = c + (axis * cos(u) + side * sin(u)) * r
			bead.scale = Vector3.ONE * maxf(0.8 * _scale * (0.6 + 0.4 * a), 0.01)
	_bead_mat.albedo_color.a = a
	for i in _pads.size():
		var pr := PAD * _scale * (1.0 if i == 0 else PAD_IN) * (0.85 + 0.15 * _pad)
		Effects.place_ring(_pads[i], foot, _up, pr)
		_pads[i].set_instance_shader_parameter("col", Color(COL, clampf(_pad, 0.0, 1.0) * (0.55 + 0.3 * sin(t * 7.0 + i * PI))))
	var q := clampf(_charge, 0.0, 1.0)
	_ball.position = Vector3(0.0, _mid, 0.0)
	_ball.scale = Vector3.ONE * maxf(_bubble * _scale * (1.0 + 0.04 * sin(t * 27.0)), 0.01)
	_halo_mat.albedo_color.a = 0.24 * q
	_shell_mat.albedo_color.a = 0.1 * q * (0.8 + 0.2 * sin(t * 13.0))
	_glow.position = Vector3(0.0, _mid, 0.0)
	_glow.scale = Vector3.ONE * maxf((1.5 + 4.5 * q) * _scale * maxf(a, q), 0.01)
	_glow_mat.albedo_color.a = clampf(0.3 * a + 0.5 * q, 0.0, 1.0)
	_light.position = Vector3(0.0, _mid, 0.0)
	_light.light_energy = 2.5 * a + 5.0 * q * q
