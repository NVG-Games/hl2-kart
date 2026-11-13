class_name Thrusters
extends Node3D
## Garry's Mod style thrusters strapped to a home-made kart (the bathtub): props bolted on at the
## back, each with a jet out of its end. The jet follows the throttle (a pilot flame when idle),
## grows long and turns blue-white on a boost, and roars like the HL1 RPG's rocket. Its own node
## under KartVisual, set up from the vehicle's "thrusters" entry in Game.VEHICLES:
##   {"model": prop, "scale": s, "pos": [kart-local centres], "nozzle": m from the centre (along +Z)}

const ORANGE := Color(1.0, 0.62, 0.28)
const BLUE := Color(0.55, 0.78, 1.0)

var kart: Kart
var _jets: Array = []  # [flame, core, light] per thruster
var _sound: AudioStreamPlayer3D
var _heat := 0.0  # 0 pilot flame .. 1 full thrust, eased


func setup(k: Kart, def: Dictionary) -> void:
	kart = k
	name = "Thrusters"
	var key: String = def.get("model", "props_junk/propane_tank001a")
	var s := float(def.get("scale", 1.0))
	var box := Game.model_aabb(key)
	var nozzle := float(def.get("nozzle", (box.position.y + box.size.y) * s))
	for pos in def.get("pos", []):
		var p: Vector3 = pos
		var m := Game.spawn_model(key)
		m.scale = Vector3.ONE * s
		m.rotation.x = PI * 0.5  # the prop stands along +Y: laid along the kart, its top to the back
		m.position = p
		add_child(m)
		var at := p + Vector3(0, 0, nozzle + 0.05)
		var flame := _jet("materials/effects/fire_cloud1.png", 26, 0.6, ORANGE)
		flame.position = at
		add_child(flame)
		var core := _jet("materials/effects/blueflare1.png", 16, 0.35, Color(1.0, 0.9, 0.75))
		core.position = at
		add_child(core)
		var light := OmniLight3D.new()
		light.light_color = ORANGE
		light.omni_range = 5.0
		light.light_energy = 0.0
		light.position = at + Vector3(0, 0, 0.3)
		add_child(light)
		_jets.append([flame, core, light])
	if Game.stream("res://assets/sound/hl1src/weapons/rocket1.wav"):
		_sound = AudioStreamPlayer3D.new()
		_sound.stream = Game.stream("res://assets/sound/hl1src/weapons/rocket1.wav")
		_sound.unit_size = 10.0
		_sound.max_distance = 220.0
		_sound.bus = "SFX"
		_sound.volume_db = -30.0
		add_child(_sound)
		if _sound.stream is AudioStreamWAV and (_sound.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			_sound.finished.connect(_sound.play)
		_sound.play()


## A jet of sprites out of the back (+Z), a plume that moves with the kart (left in the world
## it would break into puffs a metre apart at racing speed).
func _jet(tex: String, amount: int, size: float, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.16
	p.local_coords = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = SourceMaterials.tex(tex)
	q.material = m
	p.mesh = q
	p.direction = Vector3(0, 0, 1)
	p.spread = 5.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.color = col
	return p


func _process(delta: float) -> void:
	if kart == null:
		return
	var boosting := kart.boost_time > 0.0
	var on := kart.state == Kart.State.NORMAL or kart.state == Kart.State.FINISHED
	var want := 0.15
	if on:
		want = maxf(want, clampf(kart.in_throttle, 0.0, 1.0))
		if boosting:
			want = 1.6
	elif kart.state == Kart.State.RESPAWN:
		want = 0.0
	_heat = lerpf(_heat, want, minf(1.0, delta * 8.0))
	var blue := clampf(_heat - 1.0, 0.0, 0.6) / 0.6
	for j in _jets:
		var flame: CPUParticles3D = j[0]
		var core: CPUParticles3D = j[1]
		var light: OmniLight3D = j[2]
		flame.emitting = _heat > 0.03
		core.emitting = _heat > 0.03
		# longer and faster with the throttle, a blue-white lance on a boost
		# (idle: a small pilot flame at the valve)
		flame.initial_velocity_min = 1.0 + 11.0 * _heat
		flame.initial_velocity_max = 2.0 + 15.0 * _heat
		flame.scale_amount_min = 0.15 + 0.55 * _heat
		flame.scale_amount_max = 0.3 + 0.75 * _heat
		flame.color = ORANGE.lerp(BLUE, blue) * Color(1, 1, 1, clampf(0.15 + 0.7 * _heat, 0.0, 0.9))
		core.initial_velocity_min = 1.0 + 9.0 * _heat
		core.initial_velocity_max = 2.0 + 11.0 * _heat
		core.scale_amount_min = 0.4 + 0.4 * _heat
		core.scale_amount_max = 0.6 + 0.5 * _heat
		core.color = Color(1.0, 0.9, 0.75).lerp(Color(0.85, 0.95, 1.0), blue)
		light.light_color = ORANGE.lerp(BLUE, blue)
		light.light_energy = 0.1 + 1.6 * _heat + (sin(Time.get_ticks_msec() * 0.05) * 0.15 if _heat > 0.1 else 0.0)
	if _sound:
		_sound.volume_db = lerpf(-30.0, -4.0, clampf(_heat / 1.6, 0.0, 1.0))
		_sound.pitch_scale = 0.85 + 0.35 * clampf(_heat / 1.6, 0.0, 1.0)
