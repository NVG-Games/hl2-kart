class_name Effects
## One-shot effects built from HL2 sprites: env_explosion, sparks, smoke.

static var _mats := {}


static func _sprite(path: String, additive: bool, color := Color.WHITE, frames := Vector2i.ONE) -> StandardMaterial3D:
	var key := path + str(additive) + str(color) + str(frames)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = SourceMaterials.tex(path) if path.ends_with(".png") else SourceMaterials.albedo(path)
	m.albedo_color = color
	m.disable_receive_shadows = true
	if frames != Vector2i.ONE:
		m.particles_anim_h_frames = frames.x
		m.particles_anim_v_frames = frames.y
		m.particles_anim_loop = false
	_mats[key] = m
	return m


static func _burst(parent: Node, pos: Vector3, tex: String, additive: bool, amount: int, life: float, size: float,
		vel: Vector2, grav: Vector3, color: Color, fade := true, spread := 180.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _sprite(tex, additive, color)
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = grav
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.angle_min = 0.0
	p.angle_max = 360.0
	if fade:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = g
		var c := Curve.new()
		c.add_point(Vector2(0, 0.5))
		c.add_point(Vector2(1, 1.6))
		p.scale_amount_curve = c
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## env_explosion: fireball, smoke, debris sparks, light, scorch decal, damage.
static func explosion(parent: Node, pos: Vector3, scale := 1.0, by: Kart = null) -> void:
	var snd := ["res://assets/sound/weapons/explode3.wav", "res://assets/sound/weapons/explode4.wav",
		"res://assets/sound/weapons/explode5.wav"]
	Game.play_3d(snd, pos, 4.0, 1.0, 30.0)
	# env_explosion's animated fireball (sprites/zerogxplode, 15 frames)
	var fb := _burst(parent, pos + Vector3.UP * 2.0, "materials/sprites/zerogxplode_sheet.png", true, 5, 0.9, 7.0 * scale,
		Vector2(0.5, 3.0 * scale), Vector3(0, 3, 0), Color(1, 1, 1), false, 70.0)
	(fb.mesh as QuadMesh).material = _sprite("materials/sprites/zerogxplode_sheet.png", true, Color(1, 1, 1), Vector2i(5, 3))
	fb.anim_speed_min = 1.0
	fb.anim_speed_max = 1.0
	fb.explosiveness = 0.6
	_burst(parent, pos + Vector3.UP, "effects/fire_cloud1", true, 14, 0.6, 3.5 * scale,
		Vector2(2, 9 * scale), Vector3(0, 4, 0), Color(1, 0.85, 0.6))
	_burst(parent, pos + Vector3.UP * 1.5, "particle/smokesprites_0001", false, 12, 3.2, 6.0 * scale,
		Vector2(1, 4), Vector3(0, 2.5, 0), Color(0.3, 0.28, 0.26, 0.85))
	sparks(parent, pos + Vector3.UP, 2.0 * scale)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.omni_range = 18.0 * scale
	l.light_energy = 8.0
	parent.add_child(l)
	l.global_position = pos + Vector3.UP * 2.0
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	var dec := Decal.new()
	dec.texture_albedo = SourceMaterials.tex("materials/decals/scorch1.png")
	dec.size = Vector3(6, 3, 6) * scale
	dec.modulate = Color(1, 1, 1, 0.9)
	parent.add_child(dec)
	dec.global_position = pos
	var dt := dec.create_tween()
	dt.tween_interval(10.0)
	dt.tween_property(dec, "modulate:a", 0.0, 3.0)
	dt.tween_callback(dec.queue_free)
	# damage: knock karts and props away (radius ~ 9 m * scale)
	var radius := 9.0 * scale
	var tree := parent.get_tree()
	for n in tree.get_nodes_in_group("karts"):
		var k := n as Kart
		var d := k.global_position - pos
		if d.length() < radius:
			var f := 1.0 - d.length() / radius
			k.tumble(by, (d.normalized() + Vector3.UP) * k.mass * 9.0 * f)
	for n in parent.find_children("*", "PhysProp", true, false):
		var p := n as PhysProp
		var d := p.global_position - pos
		if d.length() < radius and d.length() > 0.1:
			p.sleeping = false
			var f := 1.0 - d.length() / radius
			p.apply_central_impulse((d.normalized() + Vector3.UP * 0.6) * p.mass * 16.0 * f)
			if p.model_key in PhysProp.EXPLOSIVE and f > 0.3:
				p.call_deferred("explode")
	for cam in tree.get_nodes_in_group("race_camera"):
		cam.shake(clampf(1.2 - pos.distance_to(cam.global_position) / 60.0, 0.0, 1.0))


static func sparks(parent: Node, pos: Vector3, scale := 1.0, color := Color(1.0, 0.8, 0.45)) -> void:
	_burst(parent, pos, "materials/effects/yellowflare.png", true, int(24 * scale), 0.6, 0.25,
		Vector2(4, 12 * scale), Vector3(0, -15, 0), color, true, 160.0)
	_burst(parent, pos, "materials/sprites/glow01.png", true, 3, 0.18, 2.5 * scale, Vector2(0, 0.1), Vector3.ZERO,
		color)


static func smoke_column(parent: Node, pos: Vector3, seconds: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 3.0
	var q := QuadMesh.new()
	q.size = Vector2(3, 3)
	q.material = _sprite("particle/smokesprites_0003", false, Color(0.35, 0.35, 0.35, 0.7))
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0.5, 1.0, 0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(3.5)
	tw.tween_callback(p.queue_free)


## Gravity gun punt: blue-white flash and a shock ring.
static func punt_flash(parent: Node, pos: Vector3, fwd: Vector3) -> void:
	_burst(parent, pos, "materials/sprites/physbeam.png", true, 12, 0.35, 3.0, Vector2(8, 20), Vector3.ZERO,
		Color(0.7, 0.85, 1.0), true, 25.0).direction = fwd
	_burst(parent, pos, "materials/sprites/glow01.png", true, 4, 0.3, 7.0, Vector2(0, 1), Vector3.ZERO,
		Color(0.6, 0.8, 1.0))
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.8, 1.0)
	l.omni_range = 14.0
	l.light_energy = 5.0
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
