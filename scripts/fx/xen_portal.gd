class_name XenPortal
extends Rescuer
## The Xen rescue (Rescuer): a Xen portal, the green of the XEN TELEPORT item. A ball of green
## energy forms over the kart where it stopped (over the surface where it sank, over it as it
## falls), drawing motes in and throwing arcs down at it. Over the last AIM seconds it swells, and
## just before the kart's photo_time it comes down on the kart and swallows it in a green flash
## (green on the screen of the camera following it). On the road it opens again where the kart was
## put back and, as the kart shows again (KartVisual._shown), spits it out in a green burst and
## closes.

const CORE := Color(0.82, 1.0, 0.78)
const HALO := Color(0.3, 1.0, 0.42)
const FLASH := Color(0.62, 1.0, 0.58)  # the screen flash
const OVER := 2.8  # metres over the kart's middle the ball forms (less under a roof)
const SIZE := 0.9  # the formed ball's radius
const SWALLOW := 2.4  # its radius as it takes the kart
const OPEN := 0.75  # opened again on the road, this much of SWALLOW (it stands a metre over the kart)
const SWOOP := 0.35  # seconds before the take it comes down on the kart
const SPIT := 0.25  # seconds after the take the kart shows again: it is spat out
const SHRINK := 0.35  # seconds the ball takes to close after that
const MOTES := 12
## sounds (Rescuer.sounds: the first list of them this install has): the hum as it forms, the
## swallow, the spit (the XEN TELEPORT item's own two)
const HUM := [["weapons/gauss/chargeloop.wav"], ["weapons/physcannon/energy_sing_loop4.wav"]]
const SWALLOWED := [["weapons/gauss/fire1.wav"]]
const SPAT := [["weapons/physcannon/energy_sing_explosion2.wav"]]
static var _sphere: SphereMesh

var _up := Vector3.UP
var _radius := 0.01  # the ball's radius now
var _bright := 0.0  # how bright it is now, 0..1
var _pull := 0.3  # how fast it draws the motes in (below 0: it throws them out)
var _open := -1.0  # t it opened on the road (or began to close, let go), -1 before
var _spat := -1.0  # t it spat the kart out, -1 before
var _cut := false  # let go before the take: it only closes where it is
var _from_r := 0.0  # let go: its radius and brightness then
var _from_b := 0.0
var _arc_in := 0.3  # seconds to the next arc
var _ball: Node3D  # the core and the halo, scaled to the radius
var _halo_mat: StandardMaterial3D
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
var _motes: Array[MeshInstance3D] = []
var _mote_mat: StandardMaterial3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()  # the arcs' scatter (looks only)


func setup(k: Kart) -> void:
	super(k)
	_rng.randomize()
	# up the way its gravity pulls where it stopped (in a tube too); the sky where it sinks or falls
	if k.rescue == Kart.Rescue.SCAN:
		_up = Rescuer.stuck_up(k)
	_ball = Node3D.new()
	add_child(_ball)
	_ball.add_child(_mesh(0.45, _ball_material(CORE, 1.0, 5.0)))
	_halo_mat = _ball_material(HALO, 0.35, 2.0)
	_ball.add_child(_mesh(1.0, _halo_mat))
	_shell_mat = _ball_material(HALO, 0.12, 1.5)
	_shell = _mesh(1.35, _shell_mat)
	_ball.add_child(_shell)
	_mote_mat = Rescuer.glow_material(Color(HALO.lightened(0.4), 0.0))
	for i in MOTES:
		var m := Rescuer.glow_quad(_mote_mat)
		add_child(m)
		_motes.append(m)
	_glow_mat = Rescuer.glow_material(Color(HALO, 0.0))
	_glow = Rescuer.glow_quad(_glow_mat)
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = HALO
	_light.omni_range = 12.0
	_light.light_energy = 0.0
	add_child(_light)
	global_transform = Transform3D(Rescuer.up_basis(_up), _over(_middle(k.global_position)))
	_hum = _play(HUM, global_position, -4.0, 0.8, 14.0, true)
	_draw()


## A material like the energy ball's (EnergyBall, whose kinds Effects.prewarm draws while the race
## loads), its own so that it can fade.
static func _ball_material(col: Color, alpha: float, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	return m


## A sphere `r` times the ball's radius, in `mat`.
static func _mesh(r: float, mat: Material) -> MeshInstance3D:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 16
		_sphere.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * r
	return mi


## The kart's middle at `kp` (until the take, on the surface of the liquid while it is under it).
func _middle(kp: Vector3) -> Vector3:
	var m := kp + _up * 0.6
	if kart.rescue == Kart.Rescue.SINK and _shot < 0.0:
		m.y = maxf(m.y, kart.liquid.x + 0.6)
	return m


## OVER metres over the kart's middle `m`, short of a roof.
func _over(m: Vector3) -> Vector3:
	var want := m + _up * OVER
	var roof := _ray(m, want + _up * SIZE)
	if not roof.is_empty():
		want = m + _up * maxf(m.distance_to(roof["position"]) - SIZE - 0.2, 1.2)
	return want


## Over the kart, forming, then swelling; just before the take down on it, wide enough to
## swallow it.
func _approach(kp: Vector3, _delta: float) -> void:
	if _taking():
		return  # (this frame the owner may already have the kart on the road)
	var m := _middle(kp)
	var take := kart.photo_time()
	var come := clampf(t / 0.6, 0.0, 1.0)
	come = come * come * (3.0 - 2.0 * come)
	var build := clampf((kart.state_time - (take - AIM)) / AIM, 0.0, 1.0)
	var swoop := clampf((kart.state_time - (take - SWOOP)) / SWOOP, 0.0, 1.0)
	swoop = swoop * swoop * (3.0 - 2.0 * swoop)
	global_transform = Transform3D(Rescuer.up_basis(_up), _over(m).lerp(m, swoop))
	_radius = lerpf(SIZE * come * (1.0 + 0.4 * build), SWALLOW, swoop)
	_bright = come * (0.45 + 0.55 * build)
	_pull = 0.3 + 0.9 * build
	if is_instance_valid(_hum):
		_hum.pitch_scale = 0.8 + 0.45 * build


func _flash_color() -> Color:
	return FLASH


## The kart swallowed where it was (where the ball stood last frame): a green burst, a shock ring,
## light, arcs and the gauss shot. The ball is gone with it until it opens on the road.
func _take() -> void:
	var c := global_position
	var world := get_parent()
	Effects.sparks(world, c, 2.5, HALO)
	Effects.shock_ring(world, c, _up, 7.0, Color(HALO, 0.9), 0.5)
	Effects.flash_light(world, c, HALO, 9.0, 16.0, 0.45)
	for i in 3:
		var a := _rng.randf() * TAU
		var to := c + global_basis * Vector3(cos(a), _rng.randf_range(-0.3, 0.6), sin(a)) * _rng.randf_range(3.0, 4.5)
		Effects.lightning(world, c, to, HALO, 0.2, 6, 0.6)
	_play(SWALLOWED, c, 2.0, 0.8, 18.0)
	_stop_hum()
	visible = false


## Open again over the kart's new place on the road.
func _arrive(kp: Vector3, _far: bool) -> void:
	_up = _road_up()
	global_transform = Transform3D(Rescuer.up_basis(_up), kp + _up)
	visible = true
	_open = t
	_radius = 0.01
	_bright = 1.0
	_pull = -1.0


## Open round the kart until it shows again, then spit it out and close.
func _leave(kp: Vector3, _delta: float, since: float) -> void:
	if _open < 0.0:
		return  # taken, not out on the road yet
	if _cut:
		var c := clampf((t - _open) / SHRINK, 0.0, 1.0)
		_radius = _from_r * (1.0 - c)
		_bright = _from_b * (1.0 - c)
		return
	if _spat < 0.0:
		var a := clampf(since / SPIT, 0.0, 1.0)
		_radius = SWALLOW * OPEN * maxf(a * (2.0 - a), 0.01)
		if since >= SPIT:
			_spit(kp)
	else:
		var f := clampf((t - _spat) / SHRINK, 0.0, 1.0)
		_radius = SWALLOW * OPEN * (1.0 - f) * (1.0 - f)
		_bright = 1.0 - f


## The kart out on the road: a green burst round it, a shock ring along the road, light, arcs
## and the item's sound.
func _spit(kp: Vector3) -> void:
	_spat = t
	var c := global_position
	var world := get_parent()
	Effects.sparks(world, c, 2.0, HALO)
	Effects.shock_ring(world, kp, _up, 6.0, Color(HALO, 0.85), 0.6)
	Effects.flash_light(world, c, HALO, 7.0, 14.0, 0.6)
	for i in 3:
		var a := _rng.randf() * TAU
		Effects.lightning(world, c, c + global_basis * Vector3(cos(a), 0.2, sin(a)) * _rng.randf_range(2.5, 4.0), HALO, 0.18, 5, 0.5)
	_play(SPAT, c, 0.0, 1.2, 18.0)


func _abandon() -> void:
	_cut = true
	_open = t
	_from_r = _radius
	_from_b = _bright
	_stop_hum()


func _stop_hum() -> void:
	if is_instance_valid(_hum):
		_hum.stop()
		_hum.queue_free()
	_hum = null


func _after_tick(kp: Vector3, delta: float) -> void:
	if not visible:
		return
	if _shot < 0.0:
		_arcs(kp, delta, lerpf(0.5, 0.08, clampf((kart.state_time - (kart.photo_time() - AIM)) / AIM, 0.0, 1.0)))
	_draw()


## Now and then an arc from the ball down to the kart, every `every` seconds or so (none once it is
## down on it).
func _arcs(kp: Vector3, delta: float, every: float) -> void:
	_arc_in -= delta
	if _arc_in > 0.0:
		return
	_arc_in = every * _rng.randf_range(0.6, 1.4)
	var c := global_position
	var to := _middle(kp) + Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0))
	if to.distance_to(c) < _radius + 0.8:
		return
	Effects.lightning(get_parent(), c + (to - c).normalized() * _radius, to, HALO, 0.14, 5, 0.4)


## Lays out the ball, its motes, the glow and the light as it is now.
func _draw() -> void:
	var r := maxf(_radius, 0.01)
	_ball.scale = Vector3.ONE * r * (1.0 + 0.06 * sin(t * 23.0))
	_halo_mat.albedo_color.a = 0.35 * _bright
	_shell.scale = Vector3.ONE * 1.35 * (1.0 + 0.12 * sin(t * 9.0))
	_shell_mat.albedo_color.a = 0.14 * _bright
	_glow.scale = Vector3.ONE * maxf(r * 3.2 * _bright, 0.01)
	_glow_mat.albedo_color.a = clampf(0.6 * _bright, 0.0, 1.0)
	_light.light_energy = 5.0 * _bright * minf(1.0, r / SIZE)
	for i in MOTES:
		# each mote spirals in from a few metres out to the ball (out from it once it spits)
		var u := fposmod(t * (0.5 + 0.9 * absf(_pull)) + float(i) * 0.618, 1.0)
		if _pull < 0.0:
			u = 1.0 - u
		var d := lerpf(r + 4.0, r * 0.8, u * u)
		var a := float(i) * TAU / MOTES + u * 2.5 + t * 0.8
		var h := sin(float(i) * 2.4) * 1.5 * (1.0 - u)
		_motes[i].position = Vector3(cos(a) * d, h, sin(a) * d)
		_motes[i].scale = Vector3.ONE * maxf(0.4 * (1.0 - 0.5 * u) * sin(minf(u * 1.2, 1.0) * PI), 0.01)
	_mote_mat.albedo_color.a = clampf(_bright, 0.0, 1.0)
