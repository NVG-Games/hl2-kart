class_name Track
extends Node3D
## Builds a circuit from assets/track/<name>.gltf + .json: Source-style
## materials, collision by surface type, sky/sun/fog, water, props, items.
## "bsp" tracks instead load a converted Half-Life / Half-Life 2 map
## (BspWorld) with invisible barriers along the race line.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const SKY_SHADER := preload("res://shaders/sky.gdshader")

var data := {}
var path: TrackPath
var sea_level := -13.0
var sun: DirectionalLight3D
var env: Environment
var item_boxes: Array[ItemBox] = []
var _static_shapes := {}
var bsp: BspWorld
var is_bsp := false


func build(track_name: String) -> void:
	name = "Track"
	if not FileAccess.file_exists("res://assets/track/%s.json" % track_name):
		track_name = "city17_circuit"
	data = Game.load_json("res://assets/track/%s.json" % track_name)
	path = TrackPath.new(data["path"])
	sea_level = data.get("sea_level", -13.0)
	is_bsp = data.get("type", "") == "bsp"
	if is_bsp:
		_build_bsp()
		_build_environment(_bsp_sky())
	else:
		_build_geometry(track_name)
		_build_environment(str(Game.race_setting("sky")) if Game.race_setting("sky") else data.get("sky", "sky_day01_01"))
		_build_water()
		_spawn_props()
	_spawn_item_boxes()
	_spawn_boost_pads()
	if not is_bsp:
		_spawn_background()
	var gantry := StartGantry.new()
	add_child(gantry)
	var st := path.transform_at(0.0)
	gantry.setup(Transform3D(Basis.looking_at(path.fwd[0], Vector3.UP), path.center[0]), path.width[0])


# ---------------------------------------------------------------- BSP maps
func _build_bsp() -> void:
	bsp = BspWorld.new()
	add_child(bsp)
	bsp.load_map(str(data["map"]))
	# invisible walls along both edges of the race line (the map's own walls do the rest)
	var h: float = data.get("barrier_height", 3.0)
	for side in data.get("barriers", []):
		var faces := PackedVector3Array()
		var n: int = side.size()
		for i in n:
			if side[i] == null or side[(i + 1) % n] == null:
				continue
			var a: Array = side[i]
			var b: Array = side[(i + 1) % n]
			var pa := Vector3(a[0], a[1] - 1.0, a[2])
			var pb := Vector3(b[0], b[1] - 1.0, b[2])
			if pa.distance_to(pb) > 12.0:
				continue
			var ua := pa + Vector3.UP * (h + 1.0)
			var ub := pb + Vector3.UP * (h + 1.0)
			faces.append_array([pa, pb, ub, pa, ub, ua])
		var body := StaticBody3D.new()
		body.name = "barrier_%d" % get_child_count()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", "wall")
		var pm := PhysicsMaterial.new()
		pm.friction = 0.05
		pm.bounce = 0.15
		body.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(faces)
		cs.shape = sh
		body.add_child(cs)
		add_child(body)


	# invisible ramps over stairs on the race line (HL1/HL2 clip-ramp style)
	var rf := PackedVector3Array()
	for q in data.get("ramps", []):
		var p0 := Vector3(q[0][0], q[0][1], q[0][2])
		var p1 := Vector3(q[1][0], q[1][1], q[1][2])
		var p2 := Vector3(q[2][0], q[2][1], q[2][2])
		var p3 := Vector3(q[3][0], q[3][1], q[3][2])
		rf.append_array([p0, p2, p3, p0, p3, p1])
	if not rf.is_empty():
		var rb := StaticBody3D.new()
		rb.name = "stair_ramps"
		rb.collision_layer = Game.LAYER_WORLD
		rb.collision_mask = 0
		rb.set_meta("surface", "road")
		var rcs := CollisionShape3D.new()
		var rsh := ConcavePolygonShape3D.new()
		rsh.backface_collision = true
		rsh.set_faces(rf)
		rcs.shape = rsh
		rb.add_child(rcs)
		add_child(rb)


func _bsp_sky() -> String:
	var sky := str(data.get("sky", "")).trim_suffix("_hdr")
	if Game.skies.has(sky):
		return sky
	if Game.skies.has("hl1_" + sky):
		return "hl1_" + sky
	return "sky_day01_01"


# ---------------------------------------------------------------- geometry
func _build_geometry(track_name: String) -> void:
	var scn: PackedScene = load("res://assets/track/%s.gltf" % track_name)
	var root: Node3D = scn.instantiate()
	add_child(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var kind := String(mi.name).to_lower()
		var surface := "road"
		if kind.begins_with("terrain"):
			surface = "offroad"
			_apply_terrain_material(mi)
		else:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				if src:
					var uvs := Vector2.ONE
					mi.set_surface_override_material(i, SourceMaterials.world_material(src.resource_name, uvs))
			if kind.begins_with("walls") or kind.begins_with("colonly"):
				surface = "wall"
			elif kind.begins_with("verge"):
				surface = "offroad"
			elif kind.begins_with("side"):
				surface = "wall"
		if kind.begins_with("decal"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if kind.begins_with("colonly"):
			mi.visible = false
		var body := StaticBody3D.new()
		body.name = "col_" + kind
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", surface)
		var pm := PhysicsMaterial.new()
		pm.friction = 0.05 if surface == "wall" else 0.9
		pm.bounce = 0.15 if surface == "wall" else 0.0
		body.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var shape := mi.mesh.create_trimesh_shape()
		# invisible city walls face the road: solid from inside, passable from outside
		shape.backface_collision = surface == "wall" and not kind.begins_with("colonly")
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)


func _apply_terrain_material(mi: MeshInstance3D) -> void:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	var layers := {
		"base_tex": "nature/grassfloor002a", "dirt_tex": "nature/dirtfloor003a", "rock_tex": "nature/rockwall006a",
		"pave_tex": "concrete/concretefloor028c", "sand_tex": "nature/blendcliffsand01a",
	}
	for k in layers:
		var info: Dictionary = Game.materials_db.get(layers[k], {})
		m.set_shader_parameter(k, SourceMaterials.tex(info.get("albedo", "")))
	var rock: Dictionary = Game.materials_db.get("nature/rockwall006a", {})
	if rock.has("normal"):
		m.set_shader_parameter("rock_normal", SourceMaterials.tex(rock["normal"]))
	m.set_shader_parameter("detail_tex", SourceMaterials.tex("materials/detail/noise_detail_01.png"))
	mi.set_surface_override_material(0, m)


# ---------------------------------------------------------------- environment
func _build_environment(sky_name: String) -> void:
	var sky_info: Dictionary = Game.skies.get(sky_name, {})
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("pano", load(sky_info.get("pano", "res://assets/sky/sky_day01_01_pano.png")))
	sm.set_shader_parameter("exposure", 1.0)
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	var hz: Array = sky_info.get("horizon", [0.6, 0.62, 0.65])
	var horizon := Color(hz[0], hz[1], hz[2])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = horizon
	env.fog_depth_begin = 180.0
	env.fog_depth_end = 1500.0
	env.fog_depth_curve = 1.2
	env.fog_sky_affect = 0.0
	env.fog_density = 0.6
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssr_max_steps = 48
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_energy = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "light_environment"
	var sd: Array = sky_info.get("sun_dir", [0.6, 0.5, 0.6])
	var dir := Vector3(sd[0], maxf(sd[1], 0.35), sd[2]).normalized()
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.75 * float(sky_info.get("sun_scale", 1.0))
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	if is_bsp:
		_bsp_lighting()
	apply_quality()
	Game.settings_changed.connect(apply_quality)


## GRAPHICS preset from Options: LOW / MEDIUM / HIGH (can change mid-race from the pause menu).
func apply_quality() -> void:
	var q: int = int(Game.settings.get("quality", 2))
	# BSP maps carry their own baked light: no realtime GI on top
	env.sdfgi_enabled = q >= 2 and not is_bsp
	env.ssr_enabled = q >= 2
	env.ssao_enabled = q >= 1
	env.glow_enabled = q >= 1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0 if q >= 1 else 140.0
	get_viewport().msaa_3d = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 else Viewport.MSAA_DISABLED)


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "water_sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	mi.mesh = pm
	mi.position = Vector3(300, sea_level, 400)
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var info: Dictionary = Game.materials_db.get("nature/water_coast01", {})
	m.set_shader_parameter("normal_tex", SourceMaterials.tex(info.get("normal", "materials/nature/water_coast01_normal.png")))
	m.set_shader_parameter("fog_color", Color8(21, 48, 52))
	m.set_shader_parameter("fog_end", 9.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- props
func _static_shape(key: String, model: Node3D, aabb: AABB) -> Shape3D:
	if _static_shapes.has(key):
		return _static_shapes[key]
	var sh: Shape3D
	if key.begins_with("props_buildings/"):
		var b := BoxShape3D.new()
		b.size = aabb.size
		sh = b
	elif key.begins_with("props_foliage/tree") or key.contains("lamppost") or key.contains("utilitypole") \
			or key.contains("powertower") or key.contains("signpole") or key.contains("traffic_light"):
		var c := CylinderShape3D.new()
		c.radius = clampf(minf(aabb.size.x, aabb.size.z) * 0.08, 0.15, 0.6)
		c.height = aabb.size.y
		sh = c
	elif key.contains("grass") or key.contains("fern") or key.contains("shrub") or key.contains("bush"):
		sh = null
	else:
		sh = PhysProp.shape_for(key, model)
	_static_shapes[key] = sh
	return sh


func _spawn_props() -> void:
	var holder := Node3D.new()
	holder.name = "props"
	add_child(holder)
	for p in data.get("props", []):
		var key: String = p["model"]
		if not Game.models.has(key):
			continue
		var pos := Vector3(p["pos"][0], p["pos"][1], p["pos"][2])
		var yaw: float = p.get("yaw", 0.0)
		if p.get("physics", false):
			var prop := PhysProp.new()
			holder.add_child(prop)
			prop.setup(key)
			prop.global_position = pos
			prop.rotation.y = yaw
			prop.sleeping = true
			continue
		var model := Game.spawn_model(key)
		var aabb := Game.model_aabb(key)
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", "wall")
		if _knockable(key):
			# not solid to karts: their sensor turns it into a physics prop on contact
			body.set_meta("knockable", key)
			body.collision_layer = Game.LAYER_KNOCK
		holder.add_child(body)
		body.add_child(model)
		body.global_position = pos
		body.rotation.y = yaw
		if p.get("tag", "") == "float":
			body.global_position.y = sea_level - aabb.size.y * 0.25
		var sh := _static_shape(key, model, aabb)
		if sh:
			var cs := CollisionShape3D.new()
			cs.shape = sh
			if sh is BoxShape3D:
				cs.position = aabb.get_center()
			elif sh is CylinderShape3D:
				cs.position = Vector3(0, aabb.size.y * 0.5 + aabb.position.y, 0)
			body.add_child(cs)
		var big := aabb.size.length() > 25.0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as GeometryInstance3D).visibility_range_end = 0.0 if big else 420.0
			if not big and aabb.size.length() < 2.0:
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Street furniture a kart can flatten (it turns into a prop_physics on impact).
func _knockable(key: String) -> bool:
	for k in ["lamppost", "signpole", "streetsign", "bench", "payphone", "trashcan", "trashbin", "traffic_light",
			"wood_fence", "barricade00", "utilitypole", "cardboard", "dumpster", "furniture"]:
		if key.contains(k):
			return true
	return false


func _spawn_item_boxes() -> void:
	for p in data.get("item_boxes", []):
		var b := ItemBox.new()
		b.index = item_boxes.size()
		add_child(b)
		b.global_position = Vector3(p[0], p[1], p[2])
		item_boxes.append(b)


func _spawn_boost_pads() -> void:
	for p in data.get("boost_pads", []):
		var pad := BoostPad.new()
		add_child(pad)
		var pos := Vector3(p["pos"][0], p["pos"][1], p["pos"][2])
		var f := Vector3(p["fwd"][0], p["fwd"][1], p["fwd"][2])
		var u := Vector3(p["up"][0], p["up"][1], p["up"][2])
		pad.global_transform = Transform3D(Basis(f.cross(u).normalized(), u, -f), pos)


## Distant set dressing: the Citadel, striders, circling gunship.
func _spawn_background() -> void:
	var cit := Game.spawn_model("props_combine/combine_citadel001")
	add_child(cit)
	cit.scale = Vector3.ONE * 9.0
	cit.global_position = Vector3(-900, -260, -2300)
	for mi in cit.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bg := BackgroundLife.new()
	add_child(bg)
	bg.setup(self)


# ---------------------------------------------------------------- queries
func spawn_transform(slot: int) -> Transform3D:
	var g: Array = data["grid"]
	var e: Dictionary = g[slot % g.size()]
	var pos := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
	var f := Vector3(e["fwd"][0], e["fwd"][1], e["fwd"][2]).normalized()
	return Transform3D(Basis.looking_at(f, Vector3.UP), pos)


## Karts and props are lit to match the map: light_environment's colour and
## angle, the track's ambient level (indoor maps are dim, Xen is purple...).
func _bsp_lighting() -> void:
	var sd = data.get("sun")
	if sd is Dictionary and sd.has("pitch"):
		var pitch := deg_to_rad(float(sd["pitch"]))
		var yaw := deg_to_rad(float(sd.get("yaw", 0.0)))
		# Source/GoldSrc: pitch is negative looking down, yaw around Z; convert to a Godot direction
		var dir_src := Vector3(cos(yaw) * cos(pitch), sin(yaw) * cos(pitch), sin(pitch))
		var dir := Vector3(dir_src.x, dir_src.z, -dir_src.y).normalized()
		if dir.y > -0.1:
			dir = Vector3(dir.x, -0.6, dir.z).normalized()
		sun.look_at_from_position(Vector3.ZERO, dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		var c: Array = sd.get("color", [1, 1, 1])
		sun.light_color = Color(c[0], c[1], c[2])
	var kl: float = data.get("kart_light", 1.0)
	sun.light_energy = 1.5 * kl
	var amb: Array = data.get("ambient", [0.6, 0.6, 0.6])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(amb[0], amb[1], amb[2])
	env.ambient_light_energy = 1.0
	env.fog_depth_begin = float(data.get("fog_begin", 250.0))
	env.fog_depth_end = float(data.get("fog_end", 1800.0))
	env.tonemap_exposure = float(data.get("exposure", 1.0))
