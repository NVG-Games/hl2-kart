class_name BullsquidHazard
extends Hazard
## A Xen bullsquid at an island's edge, turned to the karts coming up the road. When one comes
## into range it growls, rears up (its range animation) and spits a gob of acid in a high arc at
## the road point the kart will reach; the gob leaves a glowing green puddle there for a few
## seconds, sizzling, and a kart that drives through it spins. The server (or the offline game)
## picks the kart and the point and sends one "spit" event; the gob's flight and the puddle are
## then the same on every peer at the same clock times (the puddle is there from t_land to
## t_land + puddle on the clock, even on a peer the event reached late), and each kart's owner
## judges its own karts. A green ring marks where the gob will land while it flies.

const ACID := Color(0.55, 1.0, 0.25)
## seconds into its range animation where the gob leaves its mouth (event 1, frame 11 at 30 fps)
const SPIT_AT := 11.0 / 30.0
const RESCUED := 2.5        # seconds after a rescue a kart is not taken as a target
const POSE_NEAR := 70.0     # metres from the camera within which it is posed every frame
const LOOK_EVERY := 14.0    # seconds between its looks about while nothing comes

var model: Node3D
var sk: Skeleton3D
var anims: AnimSet
## [t_spit, landing point, lap s, lateral, target's slot, {visual nodes}, gob start]
var _spits: Array = []
var _ready_at := -1e9       # the authority spits again from this clock time on
var _head := -1
var _yaw0 := 0.0
var _yaw := 0.0
var _idle_t := 4.0
var _snd := {}
var _rescued := {}


func defaults() -> Dictionary:
	return {"zone": [s - 40.0, s], "model": "hl1/bullsquid", "scale": 1.4, "range": 48.0, "notice": 70.0,
		"warn": 0.6, "flight": 0.95, "puddle": 3.5, "puddle_r": 2.4, "cool": 4.0, "lead": 0.95, "effect": "spin",
		"push": 0.12}


func build() -> void:
	aims_all = true
	_yaw0 = rotation.y
	_yaw = _yaw0
	_snd["growl"] = sounds([["hl1src/bullchicken/bc_attackgrowl.wav", "hl1src/bullchicken/bc_attackgrowl2.wav",
		"hl1src/bullchicken/bc_attackgrowl3.wav"], ["npc/headcrab/alert1.wav"]])
	_snd["spit"] = sounds([["hl1src/bullchicken/bc_attack2.wav", "hl1src/bullchicken/bc_attack3.wav"],
		["npc/headcrab/attack1.wav"]])
	_snd["splat"] = sounds([["hl1src/bullchicken/bc_spithit1.wav", "hl1src/bullchicken/bc_spithit2.wav",
		"hl1src/bullchicken/bc_spithit3.wav"], ["hl1src/bullchicken/bc_acid1.wav"],
		["ambient/levels/canals/toxic_slime_sizzle1.wav"]])
	_snd["sizzle"] = sounds([["ambient/levels/canals/toxic_slime_sizzle2.wav",
		"ambient/levels/canals/toxic_slime_sizzle3.wav"], ["hl1src/bullchicken/bc_acid2.wav"]])
	_snd["idle"] = sounds([["hl1src/bullchicken/bc_idle1.wav", "hl1src/bullchicken/bc_idle2.wav",
		"hl1src/bullchicken/bc_idle3.wav", "hl1src/bullchicken/bc_idle4.wav", "hl1src/bullchicken/bc_idle5.wav"]])
	var key := str(p["model"])
	if not visual or not Game.models.has(key):
		return
	model = Game.spawn_model(key)
	add_child(model)
	model.scale = Vector3.ONE * float(p["scale"])
	sk = AnimSet.skeleton(model)
	anims = AnimSet.of(key)
	if sk:
		_head = sk.find_bone("ValveBiped.Bip01_Head1")
		if _head < 0:
			_head = sk.find_bone("ValveBiped_Bip01_Head1")


## Its mouth as the rules see it: over its front, the same on every peer whatever the model.
func mouth() -> Vector3:
	return global_position + Vector3.UP * 1.3 * float(p["scale"]) + global_basis.z * 1.2 * float(p["scale"])


func snapshot(t: float) -> Array:
	return [global_position.snapped(Vector3.ONE * 0.01), snappedf(_yaw0, 0.001), _look_cycle(t)]


func _look_cycle(t: float) -> int:
	return int(floor((t + rnd(3) * LOOK_EVERY) / LOOK_EVERY))


# ---------------------------------------------------------------- tick
func tick(t: float, dt: float) -> void:
	if t >= 0.0 and director.authority():
		for k in all_karts():
			if k.state == Kart.State.RESPAWN:
				_rescued[k] = t
		if t >= _ready_at:
			_try(t)
	var flight := float(p["flight"])
	for e: Array in _spits.duplicate():
		var t_spit: float = e[0]
		var t_land := t_spit + flight
		if t < t_land:
			_lock(e, t)
		if crossed(t_spit, t):
			director.note(self, "fire")
			play(_snd["spit"], global_position, 4.0, 24.0)
			if visual:
				e[6] = _head_at() if model else mouth()
		if crossed(t_land, t):
			_land(e)
		if t >= t_land and t < t_land + float(p["puddle"]):
			_burn(e)
		if visual:
			_show(e, t)
		if t > t_land + float(p["puddle"]) + 0.2:
			for n in (e[5] as Dictionary).values():
				if is_instance_valid(n):
					(n as Node).queue_free()
			_spits.erase(e)
	if visual:
		_animate(t, dt)


## The authority spits at the first kart coming up the road whose point at the landing lies in its
## zone and in its range.
func _try(t: float) -> void:
	var zone: Array = p["zone"]
	var ahead_t := tm("warn") + float(p["flight"])
	var from := mouth()
	for k in all_karts():
		if not targetable(k) or not on_road(k, float(zone[0]) - float(p["notice"]), float(zone[1])):
			continue
		if _rescued.has(k) and t - float(_rescued[k]) < RESCUED:
			continue
		if k.velocity().dot(path.fwd[k.path_index]) < 3.0:
			continue
		var pred := k.global_position + k.velocity() * ahead_t * float(p["lead"])
		var i := path.closest(pred, k.path_index)
		var at_s := path.progress(pred, i)
		if not director.in_span(at_s, float(zone[0]), float(zone[1])) or from.distance_to(pred) > float(p["range"]):
			continue
		var hw := half_width(at_s) - 1.0
		var aim := road_point(at_s, clampf(path.lateral(pred, i), -hw, hw), 0.05)
		_ready_at = t + ahead_t + tm("cool")
		send("spit", [t + tm("warn"), aim.x, aim.y, aim.z, director.slot_of(k)])
		return


func on_event(kind: String, args: Array) -> void:
	if kind != "spit" or args.size() < 5:
		return
	var aim := Vector3(float(args[1]), float(args[2]), float(args[3]))
	var i := path.closest(aim)
	_spits.append([float(args[0]), aim, path.progress(aim, i), path.lateral(aim, i), int(args[4]), {}, Vector3.ZERO])
	director.note(self, "warn")
	play(_snd["growl"], global_position, 4.0, 22.0)


## While the gob is on its way, its target sees the lock (HUD, bots) if this peer drives it.
func _lock(e: Array, t: float) -> void:
	var k := director.kart_at(int(e[4])) if int(e[4]) >= 0 else null
	if k and not k.remote and k.state == Kart.State.NORMAL:
		k.hazard_lock = maxf(float(e[0]) + float(p["flight"]) - t, 0.01)
		k.hazard_lock_from = global_position


## The gob lands: a splash and the puddle (drawn while the clock is in its time).
func _land(e: Array) -> void:
	var aim: Vector3 = e[1]
	play(_snd["splat"], aim, 4.0, 16.0)
	if visual:
		Effects.sparks(get_parent(), aim + path.up[path.closest(aim)] * 0.3, 0.8, ACID)


## Karts this peer drives that run into the puddle spin (once a pass for its group).
func _burn(e: Array) -> void:
	var aim: Vector3 = e[1]
	var r := float(p["puddle_r"]) + 0.5
	for k in local_karts():
		var d := k.global_position - aim
		if Vector2(d.x, d.z).length() < r and absf(d.y) < 1.8:
			var side := k.global_basis.x * (1.0 if path.lateral(k.global_position, k.path_index) >= float(e[3]) else -1.0)
			hit(k, str(p["effect"]), side * k.mass * 9.0 * float(p["push"]))


# ---------------------------------------------------------------- the look
## The ring where the gob will land, the gob on its way and the puddle: each made when first shown
## (none for what this peer slept through, but a puddle still lying when it wakes) and freed when
## it sleeps.
func _show(e: Array, t: float) -> void:
	var nodes: Dictionary = e[5]
	var t_spit: float = e[0]
	var flight := float(p["flight"])
	var t_land := t_spit + flight
	var aim: Vector3 = e[1]
	if t < t_land and not nodes.has("ring"):
		nodes["ring"] = Effects.ground_ring(get_parent(), aim, path.up[path.closest(aim)], float(p["puddle_r"]),
			Color(ACID, 0.0))
	if t >= t_spit and t < t_land and not nodes.has("gob"):
		if e[6] == Vector3.ZERO:
			e[6] = mouth()
		nodes["gob"] = _gob(e[6])
	if t >= t_land and t < t_land + float(p["puddle"]) and not nodes.has("puddle"):
		nodes["puddle"] = _puddle(aim, path.up[path.closest(aim)])
	var ring: MeshInstance3D = nodes.get("ring")
	if is_instance_valid(ring):
		var u := clampf((t - (t_spit - tm("warn"))) / (tm("warn") + flight), 0.0, 1.0)
		ring.set_instance_shader_parameter("col", Color(ACID, (0.3 + 0.6 * u) * (0.6 + 0.4 * sin(t * (8.0 + 12.0 * u)))))
		ring.visible = t < t_land
	var gob: Node3D = nodes.get("gob")
	if is_instance_valid(gob):
		var u := clampf((t - t_spit) / flight, 0.0, 1.0)
		var from: Vector3 = e[6]
		# a high lob: its top a third of the throw over the straight line
		var apex := 2.0 + from.distance_to(aim) * 0.3
		gob.global_position = from.lerp(aim, u) + Vector3.UP * apex * 4.0 * u * (1.0 - u)
		gob.visible = t < t_land
	var pud: Node3D = nodes.get("puddle")
	if is_instance_valid(pud):
		var age := t - t_land
		var left := float(p["puddle"]) - age
		var grow := clampf(age / 0.25, 0.0, 1.0)
		var fade := clampf(left / 0.8, 0.0, 1.0)
		pud.scale = Vector3.ONE * (0.4 + 0.6 * grow)
		pud.visible = left > 0.0
		for n in pud.get_children():
			if n is MeshInstance3D:
				(n as MeshInstance3D).set_instance_shader_parameter("fade", fade * (0.85 + 0.15 * sin(t * 9.0)))
			elif n is OmniLight3D:
				(n as OmniLight3D).light_energy = 2.2 * fade * (0.8 + 0.2 * sin(t * 7.0))
			elif n is Decal:
				(n as Decal).modulate.a = fade


## The gob in flight: a green glow trailing drops.
func _gob(from: Vector3) -> Node3D:
	var r := Node3D.new()
	get_parent().add_child(r)
	r.global_position = from
	glow("materials/sprites/glow01.png", 1.4, Color(ACID, 0.9), r)
	glow("materials/sprites/glow01.png", 0.6, Color(0.9, 1.0, 0.7), r)
	var drops := CPUParticles3D.new()
	drops.amount = 18
	drops.lifetime = 0.45
	drops.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = Effects.sprite("materials/sprites/glow01.png", true, ACID)
	drops.mesh = q
	drops.gravity = Vector3(0, -9.0, 0)
	drops.initial_velocity_max = 0.8
	r.add_child(drops)
	return r


const PUDDLE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
uniform sampler2D tex : source_color, hint_default_white;
instance uniform float fade = 1.0;
uniform vec4 col : source_color = vec4(0.55, 1.0, 0.25, 1.0);
void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float wob = 0.08 * sin(atan(c.y, c.x) * 5.0 + TIME * 1.5);
	float edge = smoothstep(1.0, 0.75, r + wob);
	vec3 slime = texture(tex, UV * 1.5 + vec2(TIME * 0.03, TIME * 0.02)).rgb;
	ALBEDO = col.rgb * (0.55 + 0.9 * slime.g);
	ALPHA = clamp(edge * fade * 0.85, 0.0, 1.0);
}
"""
static var _puddle_mat: ShaderMaterial


## The glowing pool's material, made once and kept for the session; Effects.prewarm draws it while
## a track with a bullsquid loads, so the first puddle of a race does not stall to compile it.
static func puddle_material() -> ShaderMaterial:
	if _puddle_mat == null:
		_puddle_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = PUDDLE_SHADER
		_puddle_mat.shader = sh
		_puddle_mat.set_shader_parameter("tex", SourceMaterials.tex("materials/effects/slime1.png"))
	return _puddle_mat


## The puddle: a glowing green pool lying on the road (a soft disc over a slime decal), a green
## light, bubbles and a sizzle.
func _puddle(at: Vector3, up: Vector3) -> Node3D:
	var root := Node3D.new()
	get_parent().add_child(root)
	root.global_transform = Transform3D(Track.basis_up(up), at)
	var size := float(p["puddle_r"]) * 2.2
	var dec := Decal.new()
	dec.texture_albedo = SourceMaterials.tex("materials/effects/slime1.png")
	dec.size = Vector3(size, 1.2, size)
	dec.modulate = Color(0.6, 1.0, 0.4, 1.0)
	dec.albedo_mix = 0.9
	root.add_child(dec)
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	disc.mesh = pm
	disc.material_override = puddle_material()
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3.UP * 0.06
	root.add_child(disc)
	var l := OmniLight3D.new()
	l.light_color = ACID
	l.omni_range = 7.0
	l.light_energy = 2.2
	l.shadow_enabled = false
	l.position = Vector3.UP * 0.8
	root.add_child(l)
	var bub := CPUParticles3D.new()
	bub.amount = 14
	bub.lifetime = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.material = Effects.sprite("materials/sprites/glow01.png", true, ACID)
	bub.mesh = q
	bub.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bub.emission_sphere_radius = float(p["puddle_r"]) * 0.7
	bub.direction = Vector3.UP
	bub.spread = 15.0
	bub.gravity = Vector3(0, 1.2, 0)
	bub.initial_velocity_min = 0.3
	bub.initial_velocity_max = 1.0
	bub.scale_amount_min = 0.5
	bub.scale_amount_max = 1.4
	root.add_child(bub)
	var hiss := loop(_snd["sizzle"], root, 8.0, -2.0)
	if hiss:
		hiss.play()
	return root


## Turned to the karts coming, to its aim while it spits; its idle, a look about now and then,
## and the rear-up of its range animation timed so the gob leaves its mouth as it is thrown.
func _animate(t: float, dt: float) -> void:
	var act: Array = []
	for e in _spits:
		if t >= float(e[0]) - tm("warn") and t < float(e[0]) + 1.2:
			act = e
	var want := _yaw0
	if not act.is_empty():
		var to: Vector3 = (act[1] as Vector3) - global_position
		want = atan2(to.x, to.z)
	else:
		var k := _coming()
		if k:
			var to := k.global_position - global_position
			want = atan2(to.x, to.z)
	_yaw = lerp_angle(_yaw, want, minf(1.0, dt * 4.0))
	if model:
		model.rotation.y = _yaw - rotation.y
	if act.is_empty():
		_idle_t -= dt
		if _idle_t <= 0.0:
			_idle_t = 5.0 + rnd(int(t), 9) * 8.0
			play(_snd["idle"], global_position, -4.0, 14.0)
	if model == null or anims == null or sk == null:
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < POSE_NEAR
	if not AnimSet.due(model, t, 0.0 if near else 12.0):
		return
	anims.pose(sk, "idle", t + float(id) * 1.3)
	var lc := _look_cycle(t)
	var since := t + rnd(3) * LOOK_EVERY - lc * LOOK_EVERY
	if since < anims.length("look") and rnd(lc, 4) < 0.5:
		anims.pose(sk, "look", since, clampf(since / 0.4, 0.0, 1.0) * clampf((anims.length("look") - since) / 0.4, 0.0, 1.0),
			AnimSet.CLAMP)
	if not act.is_empty():
		var a_t := t - (float(act[0]) - SPIT_AT)
		var w := clampf((a_t + 0.25) / 0.25, 0.0, 1.0) * clampf((anims.length("range") - a_t) / 0.25, 0.0, 1.0)
		anims.pose(sk, "range", maxf(a_t, 0.0), w, AnimSet.CLAMP)


## The nearest kart coming up the road towards it (what it turns to).
func _coming() -> Kart:
	var zone: Array = p["zone"]
	var best: Kart = null
	var bd := float(p["range"]) + 20.0
	for k in all_karts():
		if not on_road(k, float(zone[0]) - 40.0, float(zone[1])):
			continue
		var d := k.global_position.distance_to(global_position)
		if d < bd:
			best = k
			bd = d
	return best


func _head_at() -> Vector3:
	if sk and _head >= 0:
		return sk.global_transform * sk.get_bone_global_pose(_head).origin + Vector3.UP * 0.2
	return mouth()


## Nobody near: what it shows goes (made again from the clock when it wakes).
func sleep() -> void:
	for e in _spits:
		for n in (e[5] as Dictionary).values():
			if is_instance_valid(n):
				(n as Node).queue_free()
		(e[5] as Dictionary).clear()


## Bots: round the puddle (or where the gob will land) when their line runs into it.
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	for e in _spits:
		var t_land := float(e[0]) + float(p["flight"])
		if t > t_land + float(p["puddle"]):
			continue
		var r := float(p["puddle_r"]) + 2.0
		var to := fposmod(float(e[2]) - at_s, path.length)
		if to > path.length - r:
			to = 0.0
		# it gets there within 3 s, while the puddle lies (or as the gob lands)
		var arrive := t + to / maxf(speed, 1.0)
		if to > maxf(speed * 3.0, 25.0) or arrive < t_land - 0.3 or arrive > t_land + float(p["puddle"]):
			continue
		var lat := kart_lat(k)
		if absf(lat - float(e[3])) > r:
			continue
		var hw := half_width(float(e[2])) - 2.0
		var away := float(e[3]) - (r + 0.5) if float(e[3]) > 0.0 else float(e[3]) + r + 0.5
		return {"lat": clampf(away, -hw, hw), "w": 0.8}
	return {}


## The scanner never drops a kart into a puddle (nor where a gob is about to land).
func blocks_respawn(at_s: float) -> bool:
	var t := director.clock()
	for e in _spits:
		var t_land := float(e[0]) + float(p["flight"])
		if t < t_land + float(p["puddle"]) and absf(fposmod(at_s - float(e[2]) + path.length * 0.5, path.length)
				- path.length * 0.5) < float(p["puddle_r"]) + 4.0:
			return true
	return false


func is_active(t: float) -> bool:
	for e in _spits:
		if t > float(e[0]) - tm("warn") and t < float(e[0]) + float(p["flight"]) + float(p["puddle"]):
			return true
	return false
