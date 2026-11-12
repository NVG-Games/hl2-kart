class_name Effects
## One-shot effects built from HL2 sprites: env_explosion, sparks, smoke.

static var _mats := {}
static var _keep: Array[Material] = []  # one material of each kind made afresh per use (see prewarm)


## Draws, while the race loads, what would otherwise be drawn for the first time mid-race and
## stall that frame while its shader and pipelines compile: every kind of particle sprite, beam
## and ring, the energy ball, the canister marker, the scorch decal, the models the items, the
## scanner and the track's hazards spawn, and the gibs with their collision hulls. All of it sits
## tiny in front of `cam` for half a second (behind the loading card and the fly-by's first
## frames). A ring's material is kept for the session: rings made afresh later find their shader
## alive (once the last material of a kind is freed, the next one compiles again).
static func prewarm(cam: Camera3D, track: Track) -> void:
	var holder := Node3D.new()
	holder.name = "Prewarm"
	cam.add_child(holder)
	holder.position = Vector3(0.0, 0.0, -2.0)
	holder.scale = Vector3.ONE * 0.01
	var at := holder.global_position
	var spray := _have(["effects/splash3", "effects/splash2"])
	for s in [["particle/smokesprites_0001", false, false], ["materials/sprites/glow01.png", true, false],
			[spray, false, true], [spray, true, true]]:
		_burst(holder, at, s[0], s[1], 1, 0.6, 0.02, Vector2.ZERO, Vector3.ZERO, Color.WHITE, true, 0.0, s[2])
	var fb := _burst(holder, at, "materials/sprites/zerogxplode_sheet.png", true, 1, 0.6, 0.02, Vector2.ZERO, Vector3.ZERO,
		Color.WHITE, false)
	(fb.mesh as QuadMesh).material = sprite("materials/sprites/zerogxplode_sheet.png", true, Color(1, 1, 1), Vector2i(5, 3))
	for solid in [false, true]:
		var b := beam_node(Color.WHITE, 0.01, "materials/sprites/laserbeam.png", solid)
		holder.add_child(b)
		place_beam(b, at, at + cam.global_basis.x * 0.02)
	_ring_node(holder, at, cam.global_basis.z, 0.01, Color.WHITE)
	var ring := MeshInstance3D.new()
	ring.mesh = PlaneMesh.new()
	_keep.append(_ring_material("effects/splashwake1", Color.WHITE))
	ring.material_override = _keep[-1]
	holder.add_child(ring)
	for m in EnergyBall.ball_meshes():
		holder.add_child(m)
	var marker := MeshInstance3D.new()
	marker.mesh = CylinderMesh.new()
	marker.material_override = CanisterStrike.marker_material()
	holder.add_child(marker)
	var dec := Decal.new()
	dec.texture_albedo = SourceMaterials.tex("materials/decals/scorch1.png")
	holder.add_child(dec)
	var models: Array = Items.SPAWNS + ["combine_scanner"]
	if track.hazards:
		models.append_array(track.hazards.spawns())
	for key in models:
		if Game.models.has(key):
			holder.add_child(Game.spawn_model(key))
	# crate and melon gibs as the physics props they become: their collision hulls are built now too
	for gibs: Array in PhysProp.GIBS.values():
		for key: String in gibs:
			if Game.models.has(key):
				var p := PhysProp.new()
				holder.add_child(p)
				p.setup(key)
				p.freeze = true
				p.collision_layer = 0
				p.collision_mask = 0
	var tw := holder.create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(holder.queue_free)


## A particle sprite material (cached). `soft` (the splash plume): a SOFT_SHADER sprite that
## fades out towards its borders and where it meets the scene.
static func sprite(path: String, additive: bool, color := Color.WHITE, frames := Vector2i.ONE, soft := false) -> Material:
	var key := path + str(additive) + str(color) + str(frames) + str(soft)
	if _mats.has(key):
		return _mats[key]
	var tex := SourceMaterials.tex(path) if path.ends_with(".png") else SourceMaterials.albedo(path)
	if soft:
		var s := ShaderMaterial.new()
		s.shader = _soft_shader(additive)
		s.set_shader_parameter("tex", tex)
		s.set_shader_parameter("albedo", color)
		_mats[key] = s
		return s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = color
	m.disable_receive_shadows = true
	if frames != Vector2i.ONE:
		m.particles_anim_h_frames = frames.x
		m.particles_anim_v_frames = frames.y
		m.particles_anim_loop = false
	_mats[key] = m
	return m


## A particle sprite (billboard, turned by the particle's angle, sized by its scale, tinted by its
## colour) whose alpha fades out near the quad's borders, its base over the lowest third (HL2's
## spray sprites stop flat at their base, a hard line once one turns or rises), and within 1.2 m
## of whatever is behind it (proximity fade: no straight cut where it meets a wall or the surface).
const SOFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
void vertex() {
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	w = w * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 c = texture(tex, UV) * albedo * COLOR;
	ALBEDO = c.rgb;
	float edge = smoothstep(0.0, 0.1, UV.x) * smoothstep(1.0, 0.9, UV.x) * smoothstep(0.0, 0.1, UV.y) * smoothstep(1.0, 0.68, UV.y);
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, textureLod(depth_tex, SCREEN_UV, 0.0).r, 1.0);
	behind.xyz /= behind.w;
	ALPHA = c.a * edge * clamp(1.0 - smoothstep(behind.z + 1.2, behind.z, VERTEX.z), 0.0, 1.0);
}
"""
static var _soft_shaders := {}


static func _soft_shader(additive: bool) -> Shader:
	if not _soft_shaders.has(additive):
		var sh := Shader.new()
		sh.code = SOFT_SHADER.replace("blend_mix", "blend_add") if additive else SOFT_SHADER
		_soft_shaders[additive] = sh
	return _soft_shaders[additive]


static func _burst(parent: Node, pos: Vector3, tex: String, additive: bool, amount: int, life: float, size: float,
		vel: Vector2, grav: Vector3, color: Color, fade := true, spread := 180.0, soft := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = sprite(tex, additive, color, Vector2i.ONE, soft)
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


## env_explosion: fireball, smoke, debris sparks, light, scorch decal, damage. With `hurt`
## false the karts are left alone (a track hazard judges its own hits); props still fly.
static func explosion(parent: Node, pos: Vector3, scale := 1.0, by: Kart = null, hurt := true) -> void:
	var snd := ["res://assets/sound/weapons/explode3.wav", "res://assets/sound/weapons/explode4.wav",
		"res://assets/sound/weapons/explode5.wav"]
	Game.play_3d(snd, pos, 4.0, 1.0, 30.0)
	# env_explosion's animated fireball (sprites/zerogxplode, 15 frames)
	var fb := _burst(parent, pos + Vector3.UP * 2.0, "materials/sprites/zerogxplode_sheet.png", true, 5, 0.9, 7.0 * scale,
		Vector2(0.5, 3.0 * scale), Vector3(0, 3, 0), Color(1, 1, 1), false, 70.0)
	(fb.mesh as QuadMesh).material = sprite("materials/sprites/zerogxplode_sheet.png", true, Color(1, 1, 1), Vector2i(5, 3))
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
	# spectators flinch, scientists cower and scream (a barrage startles a group once in 6 s)
	CrowdDirector.notify(tree, &"explosion", pos, by)
	for n in tree.get_nodes_in_group("karts") if hurt else []:
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
	q.material = sprite("particle/smokesprites_0003", false, Color(0.35, 0.35, 0.35, 0.7))
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


# ---------------------------------------------------------------- liquids
const WATER := 1
const SLIME := 2


static func _liquid_col(kind: int) -> Color:
	return Color(0.5, 1.0, 0.25) if kind == SLIME else Color(0.85, 0.92, 0.97)


## The first of these materials that has been extracted (the newer splash sprites fall back
## to the ones every install already has).
static func _have(names: Array) -> String:
	for n in names:
		if SourceMaterials.albedo(n) != null:
			return n
	return names[-1]


## The sounds of this list that exist, else the fallback list.
static func _sounds(paths: Array, fallback: Array = []) -> Array:
	var have := paths.filter(func(p: String) -> bool: return Game.stream(p) != null)
	return have if not have.is_empty() else fallback


## A ring's own material (each fades on its own).
static func _ring_material(tex: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = SourceMaterials.albedo(tex)
	m.albedo_color = color
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A flat sprite lying on a liquid's surface that spreads out and fades (foam ring, ripple).
static func _ring(parent: Node, pos: Vector3, tex: String, color: Color, from: float, to: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	mi.mesh = pm
	var m := _ring_material(tex, color)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.06
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * from
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * to, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## A kart (or anything big) going into water or slime at `speed` m/s: a plume and a crown of
## spray, droplets, a foam ring spreading on the surface and the splash. Beside a wall (a slime
## channel) the plume and crown shrink to the room there is.
static func splash(parent: Node, pos: Vector3, kind: int, speed: float) -> void:
	var s := clampf(speed / 14.0, 0.3, 1.4)
	var col := _liquid_col(kind)
	var slime := kind == SLIME
	var room := clampf(_room(parent, pos) / 5.0, 0.35, 1.0)
	# the plume: soft spray cones shooting straight up, kept upright
	var plume := _burst(parent, pos + Vector3.UP * 0.3, _have(["effects/splash3", "effects/splash2"]), slime,
		int(5 + 6 * s), 0.9, 3.4 * s * room, Vector2(3.0, 8.0 * s), Vector3(0, -14, 0), Color(col, 0.9), true, 18.0, true)
	plume.angle_min = -15.0
	plume.angle_max = 15.0
	# the crown: blobs of liquid thrown out sideways
	var blob := _have(["effects/slime1", "effects/splash2"]) if slime else _have(["particle/water/watersplash_001a", "effects/splash2"])
	_burst(parent, pos + Vector3.UP * 0.2, blob, slime, int(8 + 10 * s), 0.8, 1.6 * s * room, Vector2(2.0, 6.0 * s * room),
		Vector3(0, -15, 0), Color(col, 0.85), true, 75.0)
	# droplets
	_burst(parent, pos + Vector3.UP * 0.5, _have(["particle/water/waterdrop_001a", "effects/splash2"]), slime,
		int(20 * s) + 6, 1.0, 0.25, Vector2(4.0, 10.0 * s), Vector3(0, -15, 0), Color(col, 0.9), true, 60.0)
	_ring(parent, pos, _have(["effects/splashwake3", "effects/splashwake1"]), Color(col, 0.8), 1.5, 6.0 + 4.0 * s, 1.4)
	_ring(parent, pos, "effects/splashwake1", Color(col, 0.6), 1.0, 3.5 + 2.0 * s, 0.9)
	var snd: Array
	if slime:
		snd = _sounds(["ambient/levels/canals/toxic_slime_sizzle1.wav", "ambient/levels/canals/toxic_slime_sizzle2.wav",
			"ambient/levels/canals/toxic_slime_sizzle3.wav"], ["physics/flesh/flesh_squishy_impact_hard1.wav"])
	else:
		snd = _sounds(["vehicles/airboat/pontoon_splash1.wav", "vehicles/airboat/pontoon_splash2.wav",
			"ambient/water/water_splash1.wav", "ambient/water/water_splash2.wav", "ambient/water/water_splash3.wav"],
			["ambient/water/wave1.wav", "ambient/water/wave2.wav"])
	Game.play_3d(snd, pos, 4.0 * s - 2.0, 1.0 if s > 0.6 else 1.25, 18.0)
	var body := _sounds(["ambient/water/water_splash1.wav", "ambient/water/water_splash2.wav"])
	if slime and not body.is_empty():
		Game.play_3d(body, pos, -4.0, 0.8, 14.0)


## Metres of open air around a point on a liquid's surface (1.2 m above it, 6 m out at most in
## eight directions).
static func _room(parent: Node, pos: Vector3) -> float:
	if not parent is Node3D:
		return 6.0
	var space := (parent as Node3D).get_world_3d().direct_space_state
	var from := pos + Vector3.UP * 1.2
	var best := 6.0
	for i in 8:
		var a := TAU * i / 8.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0.0, sin(a)) * 6.0, Game.LAYER_WORLD)
		var wall := space.intersect_ray(q)
		if not wall.is_empty():
			best = minf(best, from.distance_to(wall["position"]))
	return best


## Where something sank: bubbles boil up on the surface for `seconds`, with a few ripples
## and gurgles.
static func bubbles(parent: Node, pos: Vector3, kind: int, seconds: float) -> void:
	var slime := kind == SLIME
	var col := _liquid_col(kind)
	var p := CPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.55
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	q.material = sprite(_have(["effects/slime1" if slime else "effects/bubble", "effects/splash2"]), slime, Color(col, 0.9))
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.3, 0.05, 1.3)
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 0.05
	p.emitting = true
	var gurgle := _sounds(["ambient/levels/canals/toxic_slime_gurgle2.wav", "ambient/levels/canals/toxic_slime_gurgle4.wav",
		"ambient/levels/canals/toxic_slime_gurgle6.wav"]) if slime else _sounds(["physics/surfaces/underwater_impact_bullet1.wav",
		"physics/surfaces/underwater_impact_bullet2.wav", "physics/surfaces/underwater_impact_bullet3.wav"])
	var tw := p.create_tween()
	for i in 3:
		tw.tween_interval(seconds / 3.0)
		tw.tween_callback(func():
			_ring(parent, pos, "effects/splashwake1", Color(col, 0.45), 0.8, 2.6, 0.8)
			if not gurgle.is_empty():
				Game.play_3d(gurgle, pos, -6.0, 1.0 if slime else 0.6, 10.0))
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(p.lifetime + 0.2)
	tw.tween_callback(p.queue_free)


## Liquid running off a kart the scanner has just fished out (follows the kart).
static func drips(k: Node3D, kind: int, seconds: float) -> void:
	var slime := kind == SLIME
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.7
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.24)
	q.material = sprite(_have(["particle/water/waterdrop_001a", "effects/splash2"]), slime, Color(_liquid_col(kind), 0.9))
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9, 0.3, 1.8)
	p.direction = Vector3.DOWN
	p.spread = 10.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, -15.0, 0)
	k.add_child(p)
	p.position = Vector3(0, 0.5, 0)
	p.emitting = true
	var drip := _sounds(["ambient/water/drip1.wav", "ambient/water/drip2.wav", "ambient/water/drip3.wav",
		"ambient/water/drip4.wav"])
	var tw := p.create_tween()
	for i in 4:
		tw.tween_interval(seconds / 4.0)
		tw.tween_callback(func():
			if not drip.is_empty() and is_instance_valid(k):
				Game.play_3d(drip, k.global_position, -8.0, randf_range(0.9, 1.15), 8.0, k))
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(p.lifetime + 0.1)
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


# ---------------------------------------------------------------- beams, tracers and rings
## A beam strip that keeps its face to the camera: the mesh is a line along +Z (0..1) and the
## shader widens it across the view. Source beam textures run across the beam in U.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, world_vertex_coords;
uniform sampler2D tex : source_color, hint_default_white;
instance uniform vec4 col : source_color = vec4(1.0);
instance uniform float width = 0.1;
void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 side = normalize(cross(axis, CAMERA_POSITION_WORLD - VERTEX));
	VERTEX += side * (UV.x - 0.5) * width;
}
void fragment() {
	ALBEDO = col.rgb * texture(tex, UV).rgb;
	ALPHA = col.a;
}
"""
## A flat ring on a 1 m quad (radius 0.5) with a faint fill: strike markers and shock waves.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
instance uniform vec4 col : source_color = vec4(1.0);
instance uniform float edge = 0.14;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float ring = smoothstep(1.0, 1.0 - edge * 0.35, r) * smoothstep(1.0 - edge, 1.0 - edge * 0.65, r);
	float fill = (1.0 - r) * 0.22 * step(r, 1.0);
	ALBEDO = col.rgb;
	ALPHA = clamp((ring + fill) * col.a, 0.0, 1.0);
}
"""

static var _beam_mesh: ArrayMesh
static var _beam_shader: Shader
static var _solid_shader: Shader
static var _beam_mats := {}
static var _ring_mat: ShaderMaterial
static var _ring_mesh: PlaneMesh


## `solid`: the beam is drawn over the scene (its texture as its alpha) instead of added to it,
## so a laser sight still reads against bright sand and sky.
static func _beam_material(tex: String, solid := false) -> ShaderMaterial:
	var key := tex + ("|solid" if solid else "")
	if _beam_mats.has(key):
		return _beam_mats[key]
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER
		_solid_shader = Shader.new()
		_solid_shader.code = BEAM_SHADER.replace("blend_add", "blend_mix").replace("col.rgb * texture(tex, UV).rgb", "col.rgb") \
			.replace("ALPHA = col.a;", "ALPHA = col.a * texture(tex, UV).r;")
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 1), Vector3(1, 1, 1)]:
			st.set_uv(Vector2(v.x, v.y))
			st.add_vertex(Vector3(0, 0, v.z))
		for i in [0, 2, 1, 1, 2, 3]:
			st.add_index(i)
		_beam_mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = _solid_shader if solid else _beam_shader
	m.set_shader_parameter("tex", SourceMaterials.tex(tex))
	_beam_mats[key] = m
	return m


## A beam (laser sight, tripmine beam, strider shot) to stretch with place_beam(); `solid` for
## one that must read in daylight (see _beam_material).
static func beam_node(color: Color, width: float, tex := "materials/sprites/laserbeam.png", solid := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = _beam_material(tex, solid)
	mi.mesh = _beam_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-0.5, -0.5, 0.0), Vector3(1.0, 1.0, 1.0))
	mi.extra_cull_margin = width
	mi.set_instance_shader_parameter("col", color)
	mi.set_instance_shader_parameter("width", width)
	return mi


## Stretches a beam_node() (in the tree) from a to b, world positions.
static func place_beam(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	if d.length() < 0.001:
		d = Vector3(0.0, 0.0, 0.001)
	var z := d.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, z.cross(x), d), a)


## A beam from a to b that thins out and fades over `life` seconds.
static func beam(parent: Node, a: Vector3, b: Vector3, tex: String, color: Color, width: float, life: float) -> void:
	var mi := beam_node(color, width, tex)
	parent.add_child(mi)
	place_beam(mi, a, b)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(w: float): mi.set_instance_shader_parameter("width", w), width, width * 0.2, life)
	tw.tween_method(func(c: Color): mi.set_instance_shader_parameter("col", c), color, Color(color, 0.0), life)
	tw.chain().tween_callback(mi.queue_free)


## An electric arc from a to b: a jagged line (cosmetic randomness) with a wide glow around it.
static func lightning(parent: Node, a: Vector3, b: Vector3, color: Color, life := 0.2, segs := 8, jitter := 0.8) -> void:
	var d := b - a
	var side := d.cross(Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(d).normalized()
	var prev := a
	for i in range(1, segs + 1):
		var u := float(i) / segs
		var off := (side * randf_range(-1, 1) + up * randf_range(-1, 1)) * jitter * sin(u * PI)
		var q := a + d * u + off
		beam(parent, prev, q, "materials/sprites/laserbeam.png", Color(color.lightened(0.6), 1.0), 0.14, life)
		beam(parent, prev, q, "materials/sprites/physbeam.png", Color(color, 0.7), 0.7, life * 1.3)
		prev = q
	_burst(parent, b, "materials/sprites/glow01.png", true, 2, life * 1.5, 3.0, Vector2(0, 0.1), Vector3.ZERO, color)


## A bullet streak flying from a to b.
static func tracer(parent: Node, a: Vector3, b: Vector3, color := Color(1, 0.9, 0.6)) -> void:
	var dist := a.distance_to(b)
	var streak := minf(5.0, dist * 0.5)
	var mi := beam_node(color, 0.07, "materials/sprites/laserbeam.png")
	parent.add_child(mi)
	place_beam(mi, a, a)
	var dir := (b - a).normalized()
	var tw := mi.create_tween()
	tw.tween_method(func(u: float):
		var p := a + dir * (streak + (dist - streak) * u)
		place_beam(mi, p - dir * streak, p), 0.0, 1.0, maxf(dist / 600.0, 0.06))
	tw.tween_callback(mi.queue_free)


## A muzzle flash: a short burst of the weapon's flash sprite at pos, thrown along dir.
static func muzzle(parent: Node, pos: Vector3, dir: Vector3, tex: String, size: float) -> void:
	var p := _burst(parent, pos, tex, true, 3, 0.07, size, Vector2(0.0, size * 4.0), Vector3.ZERO, Color.WHITE, true, 8.0)
	p.direction = dir


## Bullet dust: a small grey puff and chips of concrete.
static func dust(parent: Node, pos: Vector3, scale := 1.0) -> void:
	_burst(parent, pos, "particle/smokesprites_0001", false, 5, 1.1, 1.4 * scale, Vector2(0.5, 2.5 * scale),
		Vector3(0, 0.6, 0), Color(0.55, 0.5, 0.45, 0.55), true, 60.0)
	_burst(parent, pos, "materials/effects/fleck_cement1.png", false, int(8 * scale) + 2, 0.7, 0.16 * scale,
		Vector2(3.0, 7.0 * scale), Vector3(0, -15, 0), Color.WHITE, true, 50.0)


## A ring lying flat at pos (just above the ground), facing `up`, `radius` metres out.
static func _ring_node(parent: Node, pos: Vector3, up: Vector3, radius: float, color: Color) -> MeshInstance3D:
	if _ring_mat == null:
		_ring_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = RING_SHADER
		_ring_mat.shader = sh
		_ring_mesh = PlaneMesh.new()
		_ring_mesh.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("col", color)
	parent.add_child(mi)
	place_ring(mi, pos, up, radius)
	return mi


## Moves a ring (ground_ring) to pos, facing `up`, `radius` metres out.
static func place_ring(mi: Node3D, pos: Vector3, up: Vector3, radius: float) -> void:
	mi.global_transform = Transform3D(_ring_basis(up, radius), pos + up.normalized() * 0.08)


## A ring's basis: the quad turned to face `up`, scaled to `radius`.
static func _ring_basis(up: Vector3, radius: float) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x * radius * 2.0, y, x.cross(y) * radius * 2.0)


## A shock wave lying on the ground: a ring growing from 1 m to `radius` as it fades.
static func shock_ring(parent: Node, pos: Vector3, up: Vector3, radius: float, color: Color, life: float) -> void:
	var mi := _ring_node(parent, pos, up, 1.0, color)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(r: float): mi.global_basis = _ring_basis(up, r), 1.0, radius, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c: Color): mi.set_instance_shader_parameter("col", c), color, Color(color, 0.0), life)
	tw.chain().tween_callback(mi.queue_free)


## A ring marking where something will land (the caller pulses it and frees it).
static func ground_ring(parent: Node, pos: Vector3, up: Vector3, radius: float, color: Color) -> MeshInstance3D:
	return _ring_node(parent, pos, up, radius, color)


## A signal flare burning on the ground for `seconds`: a glow and red smoke rising from it.
static func flare(parent: Node, pos: Vector3, seconds: float, color := Color(1, 0.2, 0.15)) -> void:
	var p := CPUParticles3D.new()
	p.amount = 12
	p.lifetime = 1.6
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	q.material = sprite("particle/smokesprites_0001", false, Color(color, 0.75))
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.6, 1.6)
	glow.mesh = gq
	glow.material_override = sprite("materials/sprites/redglow1.png", true, color)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(glow)
	glow.position = Vector3(0.0, 0.3, 0.0)
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func():
		p.emitting = false
		glow.queue_free())
	tw.tween_interval(p.lifetime + 0.1)
	tw.tween_callback(p.queue_free)
