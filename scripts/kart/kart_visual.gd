class_name KartVisual
extends Node3D
## The chosen HL2 vehicle with animated wheels / steering (bone rigs, separate
## prop wheels or the legs of Dog), the seated driver, and per-kart effects
## (drift sparks, turbo flame, dust).

const MAX_STEER := 0.55
const RIGS := {
	"buggy": [
		{"bones": ["Rig_Buggy.Wheel_FL_Turn_parent", "Rig_Buggy.Wheel_FL_Turn", "Rig_Buggy.Wheel_FL_Rotate"], "kinds": ["susp", "turn", "spin"], "wheel": 0},
		{"bones": ["Rig_Buggy.Wheel_FR_Turn_parent", "Rig_Buggy.Wheel_FR_Turn", "Rig_Buggy.Wheel_FR_Rotate"], "kinds": ["susp", "turn", "spin"], "wheel": 1},
		{"bones": ["Rig_Buggy.Axel_RL", "Rig_Buggy.Wheel_RL"], "kinds": ["susp", "spin"], "wheel": 2},
		{"bones": ["Rig_Buggy.Axel_RR", "Rig_Buggy.Wheel_RR"], "kinds": ["susp", "spin"], "wheel": 3},
	],
	"apc": [
		{"bones": ["APC.Wheel_FL_Shock", "APC.Wheel_FL_Turn", "APC.Wheel_FL_Rotate"], "kinds": ["susp", "turn", "spin"], "wheel": 0},
		{"bones": ["APC.Wheel_FR_Shock", "APC.Wheel_FR_Turn", "APC.Wheel_FR_Rotate"], "kinds": ["susp", "turn", "spin"], "wheel": 1},
		{"bones": ["APC.Wheel_RL_Shock", "APC.Wheel_RL_Rotate"], "kinds": ["susp", "spin"], "wheel": 2},
		{"bones": ["APC.Wheel_RR_Shock", "APC.Wheel_RR_Rotate"], "kinds": ["susp", "spin"], "wheel": 3},
	],
}

var kart: Kart
var spec: VehicleSpec
var buggy: Node3D  # the vehicle model root
var skel: Skeleton3D
var driver: Node3D
var driver_skel: Skeleton3D
var _materials: Array[ShaderMaterial] = []
var _wheel_chains := []  # [{bones: [idx...], kinds: [...], wheel: i}]
var _prop_wheels := []  # [{steer: Node3D, spin: Node3D, wheel: i (-1 = extra), base_y}]
var _steer_bone := -1
var _steer_axis := Vector3.FORWARD
var _spin := 0.0
var _spin_anim := 0.0
var _yaw_offset := 0.0
var _lean := 0.0
var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _flame: CPUParticles3D
var _flame_light: OmniLight3D
var _star_glow: OmniLight3D
var _head_bone := -1
# Dog
var _gait := 0.0
var _dog := {}
var _rider_pelvis := Vector3.ZERO


func setup(k: Kart) -> void:
	kart = k
	spec = k.spec if k.spec else VehicleSpec.get_spec("buggy")
	name = "Visual"
	var variant := "kart%d" % k.racer_index
	buggy = Game.spawn_model(spec.def["model"], variant)
	buggy.rotation.y = PI + spec.yaw
	buggy.scale = Vector3.ONE * spec.scale
	buggy.position = spec.to_kart(Vector3.ZERO)
	add_child(buggy)
	skel = _find_skeleton(buggy)
	var tint_name: String = spec.def.get("tint", "")
	for mi in buggy.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(i)
			if mat is ShaderMaterial:
				_materials.append(mat)
				if tint_name != "" and m.mesh.surface_get_material(i).resource_name == tint_name:
					mat.set_shader_parameter("tint", k.char_data.get("color", Color.WHITE))
					mat.set_shader_parameter("tint_amount", 0.45)
	match spec.def.get("rig", ""):
		"buggy", "apc":
			if skel:
				_setup_wheel_bones(RIGS[spec.def["rig"]])
		"props":
			_setup_prop_wheels()
		"dog":
			_setup_dog()
	_setup_driver()
	_setup_effects()


func _find_skeleton(n: Node) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] if s.size() > 0 else null


func _bone(sk: Skeleton3D, bname: String) -> int:
	var i := sk.find_bone(bname)
	if i < 0:
		i = sk.find_bone(bname.replace(".", "_"))
	return i


func _setup_wheel_bones(defs: Array) -> void:
	for d in defs:
		var ids := []
		for b in d["bones"]:
			ids.append(_bone(skel, b))
		if -1 in ids:
			continue
		_wheel_chains.append({"bones": ids, "kinds": d["kinds"], "wheel": d["wheel"]})
	_steer_bone = _bone(skel, "Rig_Buggy.Steer_Wheel")
	if _steer_bone >= 0:
		var rest := skel.get_bone_global_rest(_steer_bone)
		var want := Vector3(0, 0.45, 0.9).normalized()
		var best := 0.0
		for ax in [rest.basis.x, rest.basis.y, rest.basis.z]:
			var a: Vector3 = ax.normalized()
			if absf(a.dot(want)) > best:
				best = absf(a.dot(want))
				_steer_axis = a * signf(a.dot(want))


## Separate wheel models (army APC tyres, little car wheels under the bathtub).
func _setup_prop_wheels() -> void:
	var key: String = spec.def.get("wheel_model", "")
	if key == "":
		return
	var box := Game.model_aabb(key)
	var ext := box.size
	var ws: float = float(spec.def.get("wheel_scale", 1.0))
	var centres := []
	for i in spec.wheels.size():
		centres.append([(spec.wheels[i]["pos"] as Vector3), i])
	for c in spec.extra_wheels:
		centres.append([c, -1])
	for c in centres:
		var pos: Vector3 = c[0]
		var steer := Node3D.new()
		steer.position = pos
		add_child(steer)
		var spin := Node3D.new()
		steer.add_child(spin)
		var w := Game.spawn_model(key)
		# turn the tyre so its thinnest extent (the axle) lies along X
		if ext.z < ext.x and ext.z <= ext.y:
			w.rotation.y = PI * 0.5
		elif ext.y < ext.x and ext.y < ext.z:
			w.rotation.z = PI * 0.5
		if pos.x > 0.0:
			w.rotation.y += PI
		w.scale = Vector3.ONE * ws
		w.position = -(w.basis * (box.get_center() * ws))
		spin.add_child(w)
		_prop_wheels.append({"steer": steer, "spin": spin, "wheel": c[1], "base_y": pos.y})


# ---------------------------------------------------------------- Dog
func _setup_dog() -> void:
	if skel == null:
		return
	for n in ["Pelvis", "Spine1", "Spine3", "Neck1", "Leg1_L", "Leg2_L", "Leg1_R", "Leg2_R", "Arm1_L", "Arm2_L", "Arm1_R", "Arm2_R"]:
		var i := _bone(skel, "Dog_Model." + n)
		if i >= 0:
			var rest := skel.get_bone_global_rest(i)
			_dog[n] = {"i": i, "axis": (rest.basis.inverse() * Vector3.RIGHT).normalized(),
				"rot": skel.get_bone_rest(i).basis.get_rotation_quaternion(), "pos": skel.get_bone_rest(i).origin}


func _dog_rot(n: String, angle: float) -> void:
	if not _dog.has(n):
		return
	var d: Dictionary = _dog[n]
	skel.set_bone_pose_rotation(d["i"], (d["rot"] as Quaternion) * Quaternion(d["axis"], angle))


func _animate_dog(delta: float) -> void:
	var sp := absf(kart.fwd_speed)
	var a := clampf(sp / 14.0, 0.0, 1.0)
	var prev := _gait
	_gait += kart.fwd_speed * delta / 3.2 * TAU
	var s := sin(_gait)
	var c := cos(_gait)
	_dog_rot("Leg1_L", -s * 0.7 * a)
	_dog_rot("Leg1_R", s * 0.7 * a)
	_dog_rot("Leg2_L", maxf(0.0, c) * 1.0 * a)
	_dog_rot("Leg2_R", maxf(0.0, -c) * 1.0 * a)
	_dog_rot("Arm1_L", s * 0.55 * a)
	_dog_rot("Arm1_R", -s * 0.55 * a)
	_dog_rot("Arm2_L", -0.5 - 0.3 * a)
	_dog_rot("Arm2_R", -0.5 - 0.3 * a)
	_dog_rot("Spine1", 0.32 * a)
	if _dog.has("Pelvis"):
		var d: Dictionary = _dog["Pelvis"]
		skel.set_bone_pose_position(d["i"], (d["pos"] as Vector3) + Vector3(0, -absf(s) * 0.12 * a, 0) / maxf(spec.scale, 0.01))
	# footfalls
	if a > 0.1 and floor(prev / PI) != floor(_gait / PI) and kart.grounded and kart.audio:
		kart.audio.footstep()
	# keep the rider on the shoulders as the body bobs
	if driver and _dog.has("Spine3"):
		var sh := buggy.transform * skel.get_bone_global_pose(_dog["Spine3"]["i"]).origin
		driver.position = sh + Vector3(0, 0.05, 0.05) - driver.basis * (_rider_pelvis * driver.scale.x)


# ---------------------------------------------------------------- driver
func _setup_driver() -> void:
	var key: String = kart.char_data.get("model", "alyx")
	driver = Game.spawn_model(key, "drv%d" % kart.racer_index)
	add_child(driver)
	driver_skel = _find_skeleton(driver)
	if driver_skel == null:
		return
	driver.rotation.y = PI
	driver.scale = Vector3.ONE * 1.08
	if spec.def.get("rig", "") == "dog":
		BipedPose.straddle(driver_skel)
		var pb := BipedPose.bone(driver_skel, "ValveBiped.Bip01_Pelvis")
		if pb < 0:
			pb = BipedPose.bone(driver_skel, "ValveBiped.hips")
		_rider_pelvis = driver_skel.get_bone_global_pose(pb).origin if pb >= 0 else Vector3(0, 0.95, 0)
		if skel and _dog.has("Spine3"):
			var sh := buggy.transform * skel.get_bone_global_pose(_dog["Spine3"]["i"]).origin
			driver.position = sh + Vector3(0, 0.05, 0.05) - driver.basis * (_rider_pelvis * driver.scale.x)
		return
	BipedPose.seated(driver_skel)
	var meta: Dictionary = Game.load_json("res://assets/models/%s.json" % key)
	var eyes_rest := Vector3(0, 1.6, 0.08)
	if meta.has("attachments") and meta["attachments"].has("eyes"):
		var o: Array = meta["attachments"]["eyes"]["origin"]
		eyes_rest = Vector3(o[0], o[1], o[2])
	_head_bone = BipedPose.bone(driver_skel, "ValveBiped.Bip01_Head1")
	if _head_bone < 0:
		_head_bone = BipedPose.bone(driver_skel, "ValveBiped.head")
	var eyes_posed := eyes_rest
	if _head_bone >= 0:
		var hr := driver_skel.get_bone_global_rest(_head_bone)
		var hp := driver_skel.get_bone_global_pose(_head_bone)
		eyes_posed = hp * (hr.affine_inverse() * eyes_rest)
	driver.position = spec.eye - driver.basis * (eyes_posed * 1.08)
	# tall drivers: lift them until both feet rest on the floor (about 0.97 m below the eyes)
	var floor_y := spec.eye.y - 0.97
	var lowest := INF
	for f in ["ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot", "ValveBiped.Bip01_L_Toe0", "ValveBiped.Bip01_R_Toe0"]:
		var fi := BipedPose.bone(driver_skel, f)
		if fi >= 0:
			lowest = minf(lowest, (driver.transform * driver_skel.get_bone_global_pose(fi).origin).y)
	if lowest < floor_y:
		driver.position.y += minf(floor_y - lowest, 0.3)


# ---------------------------------------------------------------- effects
func _sprite_mat(path: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = SourceMaterials.tex(path)
	m.albedo_color = color
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m


func _setup_effects() -> void:
	for side in [-1.0, 1.0]:
		var p := CPUParticles3D.new()
		p.amount = 40
		p.lifetime = 0.35
		p.emitting = false
		p.local_coords = false
		var q := QuadMesh.new()
		q.size = Vector2(0.18, 0.18)
		q.material = _sprite_mat("materials/effects/blueflare1.png", Color(0.5, 0.7, 1.0))
		p.mesh = q
		p.direction = Vector3(0, 1, 1)
		p.spread = 35.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, -15, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var rear: Vector3 = spec.wheels[2 if side < 0 else 3]["pos"]
		p.position = Vector3(rear.x, 0.08, rear.z)
		add_child(p)
		_sparks.append(p)
		var d := CPUParticles3D.new()
		d.amount = 24
		d.lifetime = 1.1
		d.emitting = false
		d.local_coords = false
		var dq := QuadMesh.new()
		dq.size = Vector2(1.4, 1.4)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dm.vertex_color_use_as_albedo = true
		dm.albedo_texture = SourceMaterials.tex("materials/particle/particle_smokegrenade.png")
		dm.albedo_color = Color(0.55, 0.47, 0.36, 0.5)
		dq.material = dm
		d.mesh = dq
		d.direction = Vector3(0, 1, 0.5)
		d.spread = 40.0
		d.initial_velocity_min = 0.5
		d.initial_velocity_max = 2.0
		d.gravity = Vector3(0, 0.5, 0)
		d.scale_amount_min = 0.7
		d.scale_amount_max = 1.8
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.6))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		d.color_ramp = grad
		d.position = Vector3(rear.x, 0.2, rear.z + 0.2)
		add_child(d)
		_dust.append(d)
	_flame = CPUParticles3D.new()
	_flame.amount = 30
	_flame.lifetime = 0.22
	_flame.emitting = false
	var fq := QuadMesh.new()
	fq.size = Vector2(0.7, 0.7)
	fq.material = _sprite_mat("materials/effects/fire_cloud1.png", Color(1.0, 0.75, 0.45))
	_flame.mesh = fq
	_flame.direction = Vector3(0, 0.15, 1)
	_flame.spread = 8.0
	_flame.initial_velocity_min = 5.0
	_flame.initial_velocity_max = 8.0
	_flame.gravity = Vector3.ZERO
	_flame.scale_amount_min = 0.6
	_flame.scale_amount_max = 1.3
	var fg := Gradient.new()
	fg.set_color(0, Color(1, 1, 1, 1))
	fg.set_color(1, Color(1, 0.4, 0.1, 0))
	_flame.color_ramp = fg
	_flame.position = Vector3(0, clampf(spec.height * 0.35, 0.6, 1.4), spec.rear_end_z())
	add_child(_flame)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.6, 0.25)
	_flame_light.omni_range = 6.0
	_flame_light.light_energy = 0.0
	_flame_light.position = Vector3(0, 1.0, spec.rear_end_z() + 0.3)
	add_child(_flame_light)
	_star_glow = OmniLight3D.new()
	_star_glow.light_color = Color(1.0, 0.85, 0.3)
	_star_glow.omni_range = 7.0
	_star_glow.light_energy = 0.0
	_star_glow.position = Vector3(0, 1.4, 0)
	add_child(_star_glow)


func spin() -> void:
	_spin_anim = TAU * 2.0


func _process(delta: float) -> void:
	if kart == null:
		return
	# ---- body motion: drift slide angle, spin-out, lean
	var target_yaw := 0.0
	if kart.drifting:
		target_yaw = -kart.drift_dir * 0.38
	_yaw_offset = lerpf(_yaw_offset, target_yaw, minf(1.0, delta * 8.0))
	if _spin_anim > 0.0:
		var d := delta * 11.0
		_spin_anim = maxf(0.0, _spin_anim - d)
	var lean_target := -kart.in_steer * clampf(absf(kart.fwd_speed) / 25.0, 0.0, 1.0) * 0.07
	if kart.drifting:
		lean_target = kart.drift_dir * 0.08
	_lean = lerpf(_lean, lean_target, minf(1.0, delta * 6.0))
	rotation = Vector3(-0.03 if kart.boost_time > 0.0 else 0.0, _yaw_offset + _spin_anim, _lean)

	# ---- wheels
	_spin += kart.fwd_speed * delta / 0.5
	var steer := kart.in_steer if kart.state == Kart.State.NORMAL else 0.0
	if kart.drifting:
		steer = kart.drift_dir * 0.3 - steer * 0.4
	kart.steer_visual = lerpf(kart.steer_visual, steer, minf(1.0, delta * 10.0))
	if skel:
		for ch in _wheel_chains:
			var w: int = ch["wheel"]
			# wheel centre sits on the ray hit: offset from the modelled rest height
			var susp: float = clampf(float(kart.wheel_compress[w]) - Kart.TRAVEL * 0.5, -0.3, 0.25) / spec.scale
			var delta_t := Transform3D(Basis(), Vector3(0, susp, 0))
			var bones: Array = ch["bones"]
			var kinds: Array = ch["kinds"]
			for j in bones.size():
				var bi: int = bones[j]
				var rest := skel.get_bone_global_rest(bi)
				var p := rest.origin
				var rb := Basis()
				match kinds[j]:
					"turn":
						rb = Basis(Vector3.UP, -kart.steer_visual * MAX_STEER)
					"spin":
						rb = Basis(Vector3.RIGHT, _spin)
				delta_t = delta_t * Transform3D(rb, p - rb * p)
				skel.set_bone_global_pose(bi, delta_t * rest)
		if _steer_bone >= 0:
			var rest2 := skel.get_bone_global_rest(_steer_bone)
			var rb2 := Basis(_steer_axis, kart.steer_visual * 2.2)
			skel.set_bone_global_pose(_steer_bone, Transform3D(rb2, rest2.origin - rb2 * rest2.origin) * rest2)
	for pw in _prop_wheels:
		var wi: int = pw["wheel"]
		var susp2 := 0.0
		if wi >= 0:
			susp2 = clampf(float(kart.wheel_compress[wi]) - Kart.TRAVEL * 0.5, -0.3, 0.25)
		(pw["steer"] as Node3D).position.y = float(pw["base_y"]) + susp2
		if wi == 0 or wi == 1:
			(pw["steer"] as Node3D).rotation.y = -kart.steer_visual * MAX_STEER
		(pw["spin"] as Node3D).rotation.x = -_spin
	if spec.def.get("rig", "") == "dog":
		_animate_dog(delta)

	# ---- effects
	var lvl := kart.drift_level if kart.drifting else -1
	for p in _sparks:
		p.emitting = kart.drifting and kart.grounded and lvl >= 0
		if p.emitting:
			var col := Color(1, 1, 1) if lvl == 0 else (Color(0.4, 0.65, 1.0) if lvl == 1 else Color(1.0, 0.55, 0.15))
			(p.mesh as QuadMesh).material.albedo_color = col
			p.amount = 12 if lvl == 0 else 40
	for d in _dust:
		d.emitting = kart.offroad and kart.grounded and absf(kart.fwd_speed) > 6.0
	var boosting := kart.boost_time > 0.0
	_flame.emitting = boosting
	_flame_light.light_energy = lerpf(_flame_light.light_energy, 2.5 if boosting else 0.0, minf(1.0, delta * 10.0))
	var star := kart.star_time > 0.0
	_star_glow.light_energy = (1.5 + sin(Time.get_ticks_msec() * 0.03) * 0.8) if star else 0.0
	var flash := 0.0
	if star:
		flash = 0.25 + 0.25 * sin(Time.get_ticks_msec() * 0.025)
	elif kart.state == Kart.State.SPIN or kart.state == Kart.State.TUMBLE:
		flash = 0.3 if int(Time.get_ticks_msec() / 80) % 2 == 0 else 0.0
	for m in _materials:
		m.set_shader_parameter("flash", flash)
	visible = kart.state != Kart.State.RESPAWN or kart.state_time < 0.6 or kart.state_time > 2.0
