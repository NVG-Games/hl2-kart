class_name Scanner
extends Rescuer
## npc_cscanner doing Lakitu duty, the City 17 rescue (Rescuer): flies in to hang just beyond the
## kart as the camera sees it (sinking: over the liquid; falling: diving after it), turns to it,
## puts its light on it and photographs it at the kart's photo_time. In that flash the kart is back
## on the road (Kart._respawn_tick); for the kart the camera follows, the flash whites out the
## screen (RaceCamera.photo_flash). The scanner then hangs by the kart on the road for a moment and
## climbs away.

const FLY_IN := 0.7  # seconds from where it appears to its post by the kart
const STAND_OFF := 3.6  # metres beyond the kart (from the camera) it hangs, facing it
const HANG := 2.0  # metres over the kart

var model: Node3D
var _start := Vector3.ZERO
var _light: SpotLight3D
var _burst: OmniLight3D  # the flash itself, lighting everything round the kart
var _side := Vector3.FORWARD  # level, which way from the kart it hangs (_away, eased)
var _glint: MeshInstance3D  # its eye: blinks while it takes aim (Rescuer.AIM), flares at the shot
var _glint_mat: StandardMaterial3D
static var _glint_tex: Texture2D


func setup(k: Kart) -> void:
	super(k)
	model = Game.spawn_model("combine_scanner")
	model.scale = Vector3.ONE * 2.0
	add_child(model)
	_side = _away(k.global_position)
	_start = k.global_position + _side * 10.0 + Vector3.UP * 14.0
	global_position = _start
	_light = SpotLight3D.new()
	_light.spot_range = 20.0
	_light.spot_angle = 25.0
	_light.light_energy = 0.0
	_light.light_color = Color(0.85, 0.95, 1.0)
	add_child(_light)
	_burst = OmniLight3D.new()
	_burst.omni_range = 14.0
	_burst.light_energy = 0.0
	_burst.light_color = Color(0.9, 0.96, 1.0)
	_burst.position = Vector3(0, -1.0, 0)
	add_child(_burst)
	_glint_mat = StandardMaterial3D.new()
	_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glint_mat.billboard_keep_scale = true
	_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glint_mat.albedo_color = Color(0.8, 0.92, 1.0, 0.0)
	_glint_mat.albedo_texture = _glint_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	_glint = MeshInstance3D.new()
	_glint.mesh = quad
	_glint.material_override = _glint_mat
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.position = Vector3(0, 0.0, 0.42)  # just in front of its eye (+Z), in the model's frame
	model.add_child(_glint)
	Game.play_3d("res://assets/sound/npc/scanner/scanner_blip1.wav", global_position, 0.0, 1.0, 14.0, self)


func _tick(kp: Vector3, delta: float) -> void:
	# (round the shot the camera cuts to the road: there it turns with it at once)
	var turn := 1.0 if _shot >= 0.0 and t - _shot < 0.5 else minf(1.0, delta * 3.0)
	_side = _side.slerp(_away(kp), turn).normalized()


func _after_tick(kp: Vector3, delta: float) -> void:
	_light.light_energy = lerpf(_light.light_energy, 2.5 if _aimed and _shot < 0.0 else 0.0, minf(1.0, delta * 6.0))
	_burst.light_energy = lerpf(_burst.light_energy, 0.0, minf(1.0, delta * 7.0))
	# the eye: a glint that blinks while it takes aim, then the flash
	var glint := 0.0
	if _shot >= 0.0:
		glint = maxf(0.0, 1.0 - (t - _shot) / 0.35)
		_glint.scale = Vector3.ONE * (1.0 + 4.0 * glint)
	elif _aimed:
		glint = 0.5 + 0.5 * sin(t * 30.0)
		_glint.scale = Vector3.ONE
	else:
		glint = 0.25
		_glint.scale = Vector3.ONE
	_glint_mat.albedo_color.a = glint
	_face(kp, delta)


## A soft round glow (white in the middle, nothing at the edge), made once.
static func _glint_texture() -> Texture2D:
	if _glint_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.8))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_glint_tex = tex
	return _glint_tex


## Which way, level, the scanner stands off from the kart: away from the camera that is looking
## (so it is seen beyond the kart, facing it and that camera), else along the kart's road.
func _away(kp: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var d := kp - cam.global_position if cam else Vector3.ZERO
	d.y = 0.0
	if d.length() < 0.5:
		var g := kart.geo()
		d = g.fwd[kart.route_index]
		d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


## Where it hangs off the kart at `kp`: STAND_OFF beyond it and `up` over it, short of a wall
## or a roof in the way.
func _post(kp: Vector3, up: float) -> Vector3:
	var from := kp + Vector3.UP * 1.2
	var want := kp + _side * STAND_OFF + Vector3.UP * up
	var q := PhysicsRayQueryParameters3D.create(from, want, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = hit["position"] + (from - want).normalized() * 0.9
	return want


## The body turned to the kart (its eye, +Z, on it), the light on it.
func _face(kp: Vector3, delta: float) -> void:
	var to := kp + Vector3.UP * 0.6 - global_position
	var flat := Vector2(to.x, to.z).length()
	if flat > 0.2:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 8.0))
	model.rotation.x = lerpf(model.rotation.x, clampf(atan2(-to.y, maxf(flat, 0.1)), -0.7, 0.7), minf(1.0, delta * 8.0))
	if to.length() > 0.5:
		_light.look_at(global_position + to, Vector3.UP if absf(to.normalized().y) < 0.95 else Vector3.FORWARD)


## In beyond the kart, facing it (over a liquid it stays above the surface while the kart sinks
## below it), the light on it; then the shot (Rescuer: _aim, _take).
func _approach(kp: Vector3, _delta: float) -> void:
	if kart.rescue == Kart.Rescue.SINK:
		kp.y = maxf(kp.y, kart.liquid.x)
	var hover := _post(kp, HANG) + Vector3(0, sin(t * 5.0) * 0.15, 0) + _side.cross(Vector3.UP) * sin(t * 3.0) * 0.2
	var a := clampf(t / FLY_IN, 0.0, 1.0)
	global_position = _start.lerp(hover, a * a * (3.0 - 2.0 * a))


func _aim() -> void:
	Game.play_3d("res://assets/sound/npc/scanner/scanner_blip1.wav", global_position, 2.0, 1.15, 16.0, self)


## The photo (Rescuer flashes the screen of the camera following the kart, white).
func _take() -> void:
	Game.play_3d("res://assets/sound/npc/scanner/scanner_photo1.wav", global_position, 4.0, 1.0, 20.0, self)
	_light.light_energy = 24.0
	_burst.light_energy = 10.0


## The kart is taken to the road in the flash (on a proxy its new place arrives a little later):
## the scanner is beyond it there at once (put back only a few metres off, it glides over after a
## moment, _leave).
func _arrive(kp: Vector3, far: bool) -> void:
	if far:
		global_position = _post(kp, HANG)


## Beyond the kart where it was put back, a moment, then up and away (Rescuer frees it LINGER
## seconds after the shot).
func _leave(kp: Vector3, delta: float, since: float) -> void:
	if not _moved:
		return
	var climb := maxf(0.0, since - 0.5)
	var over := _post(kp, HANG) + Vector3.UP * climb * climb * 7.0
	global_position = global_position.lerp(over, minf(1.0, delta * 10.0))
