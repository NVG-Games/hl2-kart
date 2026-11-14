class_name RuinFires
extends Node3D
## Fires and columns of smoke in a ruined city: the track data's "fires" list (a circuit's
## decorate() fills ctx.fires, see tools/circuits/ct17.py), each {"pos": where its flames stand,
## "size": the flames' scale (1 a burning car, 0 no flames), "smoke": the column of smoke over it
## (0 none, 1 a car's, 3 a burning block's seen from across the city), "light": a flickering
## light on it}.
##
## Cheap by design: a fire is a few CPUParticles3D with no script of its own. This one node
## checks twice a second how far the camera is from each fire and stops drawing and simulating
## the ones out of range (the flames, embers and light within FLAME_RANGE, a big column of smoke
## much further), and flickers the lights of the fires that are shown. Nothing is built on a
## headless run or the dedicated server; the low quality setting halves the particles. Purely
## for looks: no kart ever touches a fire.

const FLAME := Color(1.0, 0.72, 0.42)
const EMBER := Color(1.0, 0.6, 0.25)
const SMOKE := Color(0.16, 0.15, 0.14, 0.8)
const LIGHT := Color(1.0, 0.55, 0.25)
## metres from the camera within which a fire's flames, embers and light are drawn
const FLAME_RANGE := 260.0
## ... and its smoke: a car's column, a big one (smoke 2 or more: a burning block's)
const SMOKE_RANGE := 650.0
const BIG_SMOKE_RANGE := 1500.0
const CHECK_EVERY := 0.5

var _fires: Array[Node3D] = []       # per fire: flames, embers and light
var _fire_at := PackedVector3Array()
var _smokes: Array[Node3D] = []      # per column of smoke
var _smoke_at := PackedVector3Array()
var _smoke_reach := PackedFloat32Array()
var _lights: Array[OmniLight3D] = []
var _light_energy := PackedFloat32Array()
var _light_phase := PackedFloat32Array()
var _low := false
var _t := 0.0
var _check := 0.0


## The fires of a track with any, or null (none, a BSP map, the dedicated server, a headless run).
static func spawn_for(trk: Track) -> RuinFires:
	if trk.is_bsp or Net.dedicated or DisplayServer.get_name() == "headless":
		return null
	if (trk.data.get("fires", []) as Array).is_empty():
		return null
	var f := RuinFires.new()
	f.name = "RuinFires"
	trk.add_child(f)
	f.setup(trk.data["fires"])
	return f


func setup(list: Array) -> void:
	_low = int(Game.settings.get("quality", 2)) == 0
	for e: Dictionary in list:
		var at := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
		var size := float(e.get("size", 1.0))
		var smoke := float(e.get("smoke", 1.0))
		if size > 0.0:
			var holder := Node3D.new()
			add_child(holder)
			holder.position = at
			holder.add_child(_flames(size))
			holder.add_child(_embers(size))
			if bool(e.get("light", false)):
				var l := OmniLight3D.new()
				l.light_color = LIGHT
				l.omni_range = 6.0 + size * 7.0
				l.light_energy = 2.2
				l.shadow_enabled = false
				l.distance_fade_enabled = true
				l.distance_fade_begin = 90.0
				l.distance_fade_length = 40.0
				l.position = Vector3.UP * size * 0.9
				holder.add_child(l)
				_lights.append(l)
				_light_energy.append(l.light_energy)
				_light_phase.append(randf() * TAU)
			_fires.append(holder)
			_fire_at.append(at)
		if smoke > 0.0:
			var col := _smoke(smoke)
			add_child(col)
			col.position = at + Vector3.UP * maxf(size, 0.5) * 0.9
			_smokes.append(col)
			_smoke_at.append(at)
			_smoke_reach.append(BIG_SMOKE_RANGE if smoke >= 2.0 else SMOKE_RANGE)
	_cull()


func _process(delta: float) -> void:
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_EVERY
		_cull()
	for k in _lights.size():
		var l := _lights[k]
		if not l.is_visible_in_tree():
			continue
		var ph := _light_phase[k]
		l.light_energy = _light_energy[k] * (0.78 + 0.14 * sin(_t * 9.1 + ph) + 0.08 * sin(_t * 23.7 + ph * 3.0))


## Shows (and runs) only the fires and columns of smoke within their range of the camera.
func _cull() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	for k in _fires.size():
		_show(_fires[k], at.distance_squared_to(_fire_at[k]) < FLAME_RANGE * FLAME_RANGE)
	for k in _smokes.size():
		_show(_smokes[k], at.distance_squared_to(_smoke_at[k]) < _smoke_reach[k] * _smoke_reach[k])


static func _show(n: Node3D, on: bool) -> void:
	if n.visible == on:
		return
	n.visible = on
	n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## The flames: fire sprites licking up from a ball `size` metres across, shrinking as they rise.
func _flames(size: float) -> CPUParticles3D:
	var p := _emitter(int(clampf(10.0 * size, 6.0, 24.0)), 0.9, "effects/fire_cloud1", true, FLAME, 1.8 * size)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * size
	p.spread = 15.0
	p.initial_velocity_min = 0.8 * size
	p.initial_velocity_max = 1.8 * size
	p.gravity = Vector3(0.0, 1.5 * size, 0.0)
	p.scale_amount_curve = _curve(1.0, 0.3)
	p.color_ramp = _fade(1.0)
	p.visibility_range_end = FLAME_RANGE
	return p


## Embers: sparks floating up out of the flames and drifting off.
func _embers(size: float) -> CPUParticles3D:
	var p := _emitter(int(clampf(6.0 * size, 4.0, 14.0)), 2.6, "materials/effects/yellowflare.png", true, EMBER, 0.14)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6 * size
	p.spread = 30.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5 * size
	p.gravity = Vector3(0.4, 0.5, 0.15)
	p.color_ramp = _fade(1.0)
	p.visibility_range_end = 140.0
	return p


## A column of dark smoke rising and spreading, bent by a light wind; `smoke` scales it (3: some
## 70 m tall over a burning block).
func _smoke(smoke: float) -> CPUParticles3D:
	var life := 5.0 + 2.0 * smoke
	var p := _emitter(int(clampf(8.0 + 6.0 * smoke, 8.0, 28.0)), life, "particle/smokesprites_0001", false, SMOKE,
		3.5 * (0.6 + smoke * 0.5))
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6 * smoke
	p.spread = 8.0
	p.initial_velocity_min = 2.0 + smoke
	p.initial_velocity_max = 3.0 + smoke * 1.5
	p.gravity = Vector3(0.9, 0.2, 0.35) * (0.6 + smoke * 0.3)
	p.angular_velocity_min = -12.0
	p.angular_velocity_max = 12.0
	p.scale_amount_curve = _curve(0.4, 2.4)
	p.color_ramp = _fade(0.8)
	p.visibility_range_end = BIG_SMOKE_RANGE if smoke >= 2.0 else SMOKE_RANGE
	return p


func _emitter(amount: int, life: float, tex: String, additive: bool, color: Color, quad: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(2, int(amount * 0.5) if _low else amount)
	p.lifetime = life
	p.preprocess = minf(life, 1.0)
	p.direction = Vector3.UP
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	q.material = Effects.sprite(tex, additive, color)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p


## Fades in over the first tenth of a particle's life to `peak` and out to nothing at its end.
static func _fade(peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.1, Color(1, 1, 1, peak))
	g.add_point(0.6, Color(1, 1, 1, peak * 0.6))
	return g


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(a, b)
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c
