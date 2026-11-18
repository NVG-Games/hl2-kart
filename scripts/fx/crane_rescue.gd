class_name CraneRescue
extends Rescuer
## Highway 17's rescue (Rescuer): the rebels' crane. Its magnet comes down on its cable out of the
## sky over the kart where it stopped (over the surface where it sank, after it as it falls, off a
## tube's wall from the pipe's middle), switches on and clamps onto the kart with a clank AIM
## seconds before the kart's photo_time and lifts it a little. At the take the screen flashes warm
## white and the kart is on the road, hanging under the magnet, which sets it down on its wheels,
## lets go and is wound back up into the sky. The kart's body never moves for it: only its look is
## lifted and set down (KartVisual's place under the kart), so the owner and the other players'
## copies agree.

const DROP := 28.0  # metres over the kart the magnet comes down from (less under a roof)
const LIFT := 2.0  # metres it lifts the stuck kart's look over the AIM seconds before the take
const SET := 1.3  # metres over the road the kart hangs as it shows again
const SHOW := 0.25  # seconds after the take the kart is hidden (KartVisual._shown)
const DOWN := 0.3  # seconds it takes to set the kart down once it shows
const CABLE := 70.0  # metres of cable over the magnet (into the sky, or up to a roof)
const WIND := 10.0  # how fast it is wound up after it lets go (metres over the square of the seconds)
const FLASH := Color(1.0, 0.9, 0.72)
const GLOW := Color(1.0, 0.78, 0.25)
## sounds (Rescuer.sounds: the first list of them this install has): the winch as it comes down,
## the clank as it switches on and grabs, the release
const WINCH := [["vehicles/crane/crane_extend_loop1.wav"], ["plats/crane/vertical_start.wav"]]
const GRAB := [["vehicles/crane/crane_magnet_grab.wav"], ["physics/metal/metal_barrel_impact_hard1.wav"]]
const SWITCH := [["vehicles/crane/crane_magnet_switchon.wav"]]
const LET_GO := [["vehicles/crane/crane_magnet_release.wav"], ["physics/metal/metal_barrel_impact_soft1.wav"]]

var _up := Vector3.UP
var _magnet: Node3D
var _cable: MeshInstance3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _winch: AudioStreamPlayer3D
var _height := 1.6  # the kart's height: the magnet's bottom sits on its roof
var _start := Vector3.ZERO  # where the magnet's bottom comes down from
var _bottom := Vector3.ZERO  # the magnet's bottom now
var _roof := Vector3.ZERO  # where its cable goes up to (the sky, or a roof)
var _lift := 0.0  # metres the kart's look is lifted now
var _vis_rest := Vector3.ZERO  # the kart's look's own place under it
var _vis_on := false  # this rescuer has moved the kart's look (and puts it back)
var _arrived := -1.0  # t it came over the kart's new place on the road, -1 before
var _let_go := -1.0  # t it let go of the kart (or was let go of), -1 before
var _from := Vector3.ZERO  # its bottom then: it is wound up from there
var _on := 0.0  # how bright the switched-on magnet glows, 0..1


func setup(k: Kart) -> void:
	super(k)
	# up the way its gravity pulls where it stopped (off a tube's wall too); the sky where it
	# sinks or falls
	if k.rescue == Kart.Rescue.SCAN:
		_up = Rescuer.stuck_up(k)
	if k.spec:
		_height = k.spec.height
	if k.visual:
		_vis_rest = k.visual.position
	_magnet = Node3D.new()
	add_child(_magnet)
	if Game.models.has("props_wasteland/cranemagnet01a"):
		_magnet.add_child(Game.spawn_model("props_wasteland/cranemagnet01a"))
	else:
		# a stand-in for an install without the magnet: a dark drum
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.4
		cyl.height = 1.2
		mi.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.19, 0.18)
		mi.material_override = mat
		mi.position = Vector3(0.0, -CraneHazard.MAG_BOTTOM + 0.6, 0.0)
		_magnet.add_child(mi)
	_cable = CraneHazard.cable_node()
	add_child(_cable)
	_glow_mat = Rescuer.glow_material(Color(GLOW, 0.0))
	_glow = Rescuer.glow_quad(_glow_mat)
	_glow.scale = Vector3.ONE * 3.5
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 10.0
	_light.light_energy = 0.0
	add_child(_light)
	var top := _on_kart(k.global_position)
	var room := _ray(top, top + _up * (DROP + 5.0))
	var drop := DROP if room.is_empty() else maxf(top.distance_to(room["position"]) - 4.5, 1.0)
	_start = top + _up * drop
	_bottom = _start
	_roof = _cable_top(_start)
	_winch = _play(WINCH, _start, -2.0, 1.0, 18.0, true)
	_draw()


## Where the magnet's bottom sits on the kart at `kp`: on its roof, lifted with its look (until the
## take, over the surface of the liquid while the kart is under it).
func _on_kart(kp: Vector3) -> Vector3:
	var b := kp + _up * (_height + _lift)
	if kart.rescue == Kart.Rescue.SINK and _shot < 0.0:
		b.y = maxf(b.y, kart.liquid.x + 0.3)
	return b


## The top of its cable: CABLE metres up from `from`, or the roof in the way.
func _cable_top(from: Vector3) -> Vector3:
	var want := from + _up * CABLE
	var roof := _ray(from + _up * 4.5, want)
	return want if roof.is_empty() else roof["position"]


## The kart's look lifted `h` metres along `up` (world), its body where it is; 0 puts it back.
func _look(h: float, up: Vector3) -> void:
	if not is_instance_valid(kart) or kart.visual == null:
		return
	_lift = h
	if h <= 0.001:
		if _vis_on:
			kart.visual.position = _vis_rest
		_vis_on = false
		return
	_vis_on = true
	kart.visual.position = _vis_rest + kart.global_basis.orthonormalized().inverse() * (up * h)


## Down out of the sky onto the kart's roof by AIM seconds before the take; then (stuck where it
## stopped) it lifts the kart's look.
func _approach(kp: Vector3, _delta: float) -> void:
	if _taking():
		return  # (this frame the owner may already have the kart on the road)
	var take := kart.photo_time()
	var come := clampf(kart.state_time / maxf(take - AIM, 0.3), 0.0, 1.0)
	come = 1.0 - (1.0 - come) * (1.0 - come)
	if _aimed and kart.rescue == Kart.Rescue.SCAN:
		_look(LIFT * smoothstep(take - AIM, take, kart.state_time), _up)
	_bottom = _start.lerp(_on_kart(kp), come)


## It switches on and grabs the kart.
func _aim() -> void:
	_play(SWITCH, _bottom, 0.0, 1.0, 18.0)
	_play(GRAB, _bottom, 4.0, 1.0, 22.0)
	Effects.sparks(get_parent(), _bottom, 1.0, GLOW)
	_stop_winch()


func _flash_color() -> Color:
	return FLASH


## The kart is taken in the flash: the magnet goes with it (it is over the kart's new place once
## it shows there, _arrive), and the kart will show hanging SET metres over the road.
func _take() -> void:
	_magnet.visible = false
	_cable.visible = false
	_look(0.0, _up)


## Over the kart's new place on the road, the kart hanging under it.
func _arrive(kp: Vector3, _far: bool) -> void:
	_up = _road_up()
	_arrived = t
	_look(SET, _up)
	_bottom = kp + _up * (_height + SET)
	_roof = _cable_top(_bottom)
	_magnet.visible = true
	_cable.visible = true


## Once the kart shows again it is set down on its wheels and let go; the magnet is wound up into
## the sky (Rescuer frees it LINGER seconds after the take).
func _leave(kp: Vector3, _delta: float, _since: float) -> void:
	if _let_go >= 0.0:
		var up := t - _let_go
		_bottom = _from + _up * up * up * WIND
		return
	if _arrived < 0.0:
		return  # taken, not on the road yet
	var x := clampf((t - maxf(_arrived, _shot + SHOW)) / DOWN, 0.0, 1.0)
	_look(SET * (1.0 - smoothstep(0.0, 1.0, x)), _up)
	_bottom = kp + _up * (_height + _lift)
	if x >= 1.0:
		_let_go = t
		_from = _bottom
		_look(0.0, _up)
		_play(LET_GO, _bottom, 2.0, 1.0, 20.0)
		Effects.sparks(get_parent(), _bottom, 0.6, GLOW)


## Let go before the take: it puts the kart's look back and is wound up from where it is.
func _abandon() -> void:
	_look(0.0, _up)
	_let_go = t
	_from = _bottom
	_stop_winch()


func _stop_winch() -> void:
	if is_instance_valid(_winch):
		_winch.stop()
		_winch.queue_free()
	_winch = null


func _after_tick(_kp: Vector3, delta: float) -> void:
	var on := _aimed and _let_go < 0.0 and (_shot < 0.0 or _arrived >= 0.0)
	_on = move_toward(_on, 1.0 if on else 0.0, delta * 5.0)
	_draw()


## Lays out the magnet, its cable, its glow and light as they are now.
func _draw() -> void:
	var b := Rescuer.up_basis(_up)
	var origin := _bottom + _up * CraneHazard.MAG_BOTTOM
	_magnet.global_transform = Transform3D(b, origin)
	var eye := origin + b * CraneHazard.MAG_EYE
	var top := _roof if (_roof - eye).dot(_up) > 1.0 else eye + _up * 1.0
	CraneHazard.place_cable(_cable, eye, top, 0.06)
	_glow.global_position = _bottom
	_glow_mat.albedo_color.a = 0.7 * _on * (0.8 + 0.2 * sin(t * 20.0))
	_light.global_position = _bottom - _up * 0.4
	_light.light_energy = 3.0 * _on


## Freed (or the race is gone): the kart's look goes back where it belongs.
func _exit_tree() -> void:
	_look(0.0, _up)
