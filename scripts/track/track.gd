class_name Track
extends Node3D
## Builds a circuit from assets/track/<name>.gltf + .json: Source-style
## materials, collision by surface type, sky/sun/fog, water, props, items.
## "bsp" tracks instead load a converted Half-Life / Half-Life 2 map
## (BspWorld) with invisible barriers along the race line.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const SKY_SHADER := preload("res://shaders/sky.gdshader")

var id := ""  # the circuit's id (Game.TRACKS) once built
var data := {}
var path: TrackPath
var sea_level := -13.0
## a water plane at sea_level (on a converted BSP map sea_level is only a floor)
var has_sea := false
var _lakes: Array = []  # [Rect2 on x/z, level]: lakes above the main water line
var sun: DirectionalLight3D
var env: Environment
var item_boxes: Array[ItemBox] = []
var _static_shapes := {}
var bsp: BspWorld
var is_bsp := false
## the circuit's traps and shooters (scripts/hazards); none when the race's hazards rule is OFF
var hazards: HazardDirector
## the start arch (its Breencast; the spectators' remarks go through it)
var gantry: StartGantry
## the spectators (scripts/crowd): none on BSP maps, the dedicated server, headless runs, with
## crowds OFF or without crowd data
var crowd: CrowdDirector
## why the track could not be built ("" = fine): a custom track that is not ready here, or a
## built-in this computer has not built while online (race.gd reads it right after build)
var build_failed := ""


func build(track_name: String) -> void:
	name = "Track"
	if CustomTracks.is_custom(track_name):
		# memory; compiles synchronously only headless / in tests (CustomTracks.build_for)
		var b := CustomTracks.build_for(track_name)
		if b == null:
			build_failed = "%s is not ready on this computer." % _track_ref(track_name)
			push_error(build_failed)
			return
		build_level(b)
		return
	if not FileAccess.file_exists("res://assets/track/%s.json" % track_name):
		if Net.active:
			# online every peer must race the same track: never a silent stand-in
			build_failed = "This computer has not built %s." % track_name
			push_error(build_failed)
			return
		track_name = "city17_circuit"  # offline only
	id = track_name
	data = Game.load_json("res://assets/track/%s.json" % track_name)
	path = make_path(data)
	sea_level = data.get("sea_level", -13.0)
	is_bsp = data.get("type", "") == "bsp"
	if is_bsp:
		_build_bsp_track()
		return
	_build_geometry(track_name)
	_finish_build()


## A track compiled from the editor's format (LevelBuild): the same steps as a built circuit after
## its glTF (environment, water, props, items, hazards, background, arch, screens, crowds, fx).
func build_level(b: LevelBuild) -> void:
	name = "Track"
	id = b.id
	if not b.data.get("path") is Dictionary:
		build_failed = "%s has no road to race on." % _track_ref(b.id)
		push_error(build_failed)
		return
	data = b.data
	path = make_path(data)
	sea_level = float(data.get("sea_level", -1000.0))
	is_bsp = false
	var root := b.instantiate()
	add_child(root)
	dress(root, data)
	_finish_build()


## A track for messages: "The track <name>" from Game.track's entry for it, "This track" when
## Game.track does not know the id (its fallback entry is named "Unknown track").
static func _track_ref(track_id: String) -> String:
	var e: Dictionary = Game.track(track_id)
	var nm := str(e.get("name", "")).strip_edges()
	if str(e.get("id", "")) != track_id or bool(e.get("unknown", false)) or nm == "":
		return "This track"
	return "The track %s" % nm


## Everything after the geometry of a glTF circuit or a custom track: environment, water, lakes,
## props, lights, items, pads, hazards, background, the arch, screens, crowd, low gravity, fires,
## forest life. (BSP maps keep their own order: _build_bsp_track.)
func _finish_build() -> void:
	_build_environment(str(data.get("sky", "sky_day01_01")))
	if data.has("water") or sea_level > -500.0:
		_build_water()
		has_sea = true
	for w in data.get("waters", []):
		# lakes above the main water line (a reservoir behind a dam)
		var c := Vector2(w["center"][0], w["center"][1])
		var sz := Vector2(w["size"][0], w["size"][1])
		_build_water(float(w["level"]), c, sz)
		_lakes.append([Rect2(c - sz * 0.5, sz), float(w["level"])])
	_spawn_props()
	_spawn_lights()
	_spawn_item_boxes()
	_spawn_boost_pads()
	# before the background: BackgroundLife leaves out its gunship when a hazard has one
	_spawn_hazards()
	_spawn_background()
	_spawn_gantry_and_life()


## A converted BSP map: environment before the items, no water, props or background.
func _build_bsp_track() -> void:
	_build_bsp()
	_build_environment(_bsp_sky())
	_spawn_item_boxes()
	_spawn_boost_pads()
	_spawn_hazards()
	_spawn_gantry_and_life()


func _spawn_hazards() -> void:
	hazards = HazardDirector.new()
	add_child(hazards)
	hazards.setup(self, data.get("hazards", []))


## The start arch, its screens, the spectators and the ambient effects.
func _spawn_gantry_and_life() -> void:
	gantry = StartGantry.new()
	add_child(gantry)
	gantry.setup(Transform3D(Basis.looking_at(path.fwd[0], Vector3.UP), path.center[0]), path.width[0],
		str(data.get("gantry", "combine")), float(data.get("gantry_clear", 0.0)))
	_spawn_screens(gantry.feed)
	crowd = CrowdDirector.spawn_for(self)
	# what shows a low-gravity zone (motes, glowing columns, a hum); the karts read the zones themselves
	LowGravityField.spawn_for(self)
	# fires and columns of smoke in a ruined city (data "fires"); none headless or on the dedicated server
	RuinFires.spawn_for(self)
	# the wind in the pines and distant birds in a forest (background "forest"); none headless either
	ForestLife.spawn_for(self)


## The race paths of a track JSON: the main loop with its branches (TrackBranch).
static func make_path(d: Dictionary) -> TrackPath:
	var p := TrackPath.new(d["path"])
	p.add_branches(d.get("branches", []))
	return p


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
	dress(root, data)


## Source-style materials and collision by surface type for every mesh under `root` (a circuit's
## glTF or LevelBuild.instantiate()), by the mesh's name: terrain* gets the terrain shader (one
## ShaderMaterial per call, shared by every terrain mesh) and is offroad; decal / glow / deco are
## seen, never hit; walls / colonly / ceil / side are walls (colonly hidden), verge offroad, the rest
## road. Meta `no_collision`: the material and no body (terrain chunks: their collision is the
## height tiles); meta `no_shadow`: casts no shadow.
static func dress(root: Node3D, d: Dictionary) -> void:
	var terrain_mat: ShaderMaterial = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var kind := String(mi.name).to_lower()
		var surface := "road"
		if kind.begins_with("terrain"):
			surface = "offroad"
			if terrain_mat == null:
				terrain_mat = terrain_material(d)
			mi.set_surface_override_material(0, terrain_mat)
		else:
			# light rings, lamp strips and glowing liquids shine whether or not their VMT says $selfillum
			var lit := kind.begins_with("glow")
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				if src:
					var uvs := Vector2.ONE
					# (a soft decal, soot or a crater, is blended: see SourceMaterials.decal_material)
					var dm := SourceMaterials.decal_material(src.resource_name) if kind.begins_with("decal") else null
					mi.set_surface_override_material(i, dm if dm else SourceMaterials.world_material(src.resource_name, uvs, lit))
			if kind.begins_with("walls") or kind.begins_with("colonly") or kind.begins_with("ceil"):
				surface = "wall"
			elif kind.begins_with("verge"):
				surface = "offroad"
			elif kind.begins_with("side"):
				surface = "wall"
		if mi.get_meta("no_shadow", false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# decals, glowing light panels and set dressing: seen, never hit
		if kind.begins_with("decal") or kind.begins_with("glow") or kind.begins_with("deco"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if kind.begins_with("colonly"):
			mi.visible = false
		if mi.get_meta("no_collision", false):
			continue
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


## The terrain shader with a track's layers: `d.terrain_layers` {base, dirt, rock, pave, sand} ->
## albedo paths; a layer left out takes the default HL2 nature texture.
static func terrain_material(d: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	var layers := {
		"base_tex": "nature/grassfloor002a", "dirt_tex": "nature/dirtfloor003a", "rock_tex": "nature/rockwall006a",
		"pave_tex": "concrete/concretefloor028c", "sand_tex": "nature/blendcliffsand01a",
	}
	var own = d.get("terrain_layers", {})
	if not own is Dictionary:
		own = {}
	for k in layers:
		var info: Dictionary = Game.materials_db.get(layers[k], {})
		var tex_path: String = str(own.get(k.trim_suffix("_tex"), info.get("albedo", "")))
		m.set_shader_parameter(k, SourceMaterials.tex(tex_path))
	var rock: Dictionary = Game.materials_db.get("nature/rockwall006a", {})
	if rock.has("normal"):
		m.set_shader_parameter("rock_normal", SourceMaterials.tex(rock["normal"]))
	m.set_shader_parameter("detail_tex", SourceMaterials.tex("materials/detail/noise_detail_01.png"))
	return m


# ---------------------------------------------------------------- environment
func _build_environment(sky_name: String) -> void:
	var parts := _make_environment(sky_name, data, is_bsp)
	env = parts[2]
	sun = parts[1]
	add_child(parts[0])
	add_child(sun)
	apply_quality()
	Game.settings_changed.connect(apply_quality)


## [WorldEnvironment, DirectionalLight3D, Environment] of a track's data: the sky `d.sky`, the
## sun from it, fog, tone mapping and the circuit's `env` overrides (the nodes are not in a tree).
static func make_environment(d: Dictionary) -> Array:
	return _make_environment(str(d.get("sky", "sky_day01_01")), d, false)


static func _make_environment(sky_name: String, d: Dictionary, bsp: bool) -> Array:
	var sky_info: Dictionary = Game.skies.get(sky_name, {})
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("pano", load(sky_info.get("pano", "res://assets/sky/sky_day01_01_pano.png")))
	sm.set_shader_parameter("exposure", 1.0)
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 1.35
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.08
	e.tonemap_white = 6.0
	var hz: Array = sky_info.get("horizon", [0.6, 0.62, 0.65])
	var horizon := Color(hz[0], hz[1], hz[2])
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = horizon
	e.fog_depth_begin = 180.0
	e.fog_depth_end = 1500.0
	e.fog_depth_curve = 1.2
	e.fog_sky_affect = 0.0
	e.fog_density = 0.6
	e.ssao_enabled = true
	e.ssao_radius = 1.5
	e.ssao_intensity = 1.6
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.ssr_max_steps = 48
	e.sdfgi_use_occlusion = true
	e.sdfgi_cascades = 4
	e.sdfgi_min_cell_size = 0.4
	e.sdfgi_energy = 1.1
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05
	e.adjustment_contrast = 1.05
	we.environment = e
	var s := DirectionalLight3D.new()
	s.name = "light_environment"
	var sd: Array = sky_info.get("sun_dir", [0.6, 0.5, 0.6])
	var dir := Vector3(sd[0], maxf(sd[1], 0.35), sd[2]).normalized()
	s.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	s.light_color = Color(1.0, 0.95, 0.86)
	s.light_energy = 1.75 * float(sky_info.get("sun_scale", 1.0))
	s.shadow_enabled = true
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	s.directional_shadow_max_distance = 260.0
	s.shadow_blur = 1.2
	s.light_angular_distance = 0.6
	if bsp:
		_bsp_lighting(e, s, d)
	elif d.has("env") and d["env"] is Dictionary:
		_env_overrides(e, s, d["env"])
	return [we, s, e]


## GRAPHICS preset from Options: LOW / MEDIUM / HIGH (can change mid-race from the pause menu).
func apply_quality() -> void:
	apply_quality_to(env, sun, get_viewport(), data, is_bsp)


## The GRAPHICS preset on an environment, its sun and the viewport (MSAA): realtime GI, SSR, SSAO,
## glow, shadow splits and distance. `vp` may be null.
static func apply_quality_to(e: Environment, s: DirectionalLight3D, vp: Viewport, d: Dictionary, bsp := false) -> void:
	var q: int = int(Game.settings.get("quality", 2))
	var de = d.get("env", {})
	# BSP maps carry their own baked light: no realtime GI on top
	e.sdfgi_enabled = q >= 2 and not bsp and bool(de.get("sdfgi", true) if de is Dictionary else true)
	e.ssr_enabled = q >= 2
	e.ssao_enabled = q >= 1
	e.glow_enabled = q >= 1
	s.shadow_enabled = true
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	s.directional_shadow_max_distance = 260.0 if q >= 1 else 140.0
	if vp:
		vp.msaa_3d = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 else Viewport.MSAA_DISABLED)


## The sea (`data.sea_center`, default [300, 400]; `data.sea_size`, default 6000 m square) or a
## lake (its own level, centre and size).
func _build_water(level := NAN, center := Vector2.INF, size := Vector2.INF) -> void:
	if center == Vector2.INF:
		var c = data.get("sea_center", [300, 400])
		center = Vector2(float(c[0]), float(c[1])) if c is Array and c.size() >= 2 else Vector2(300, 400)
	if size == Vector2.INF:
		var sz := float(data.get("sea_size", 6000.0))
		size = Vector2(sz, sz)
	add_child(water_plane(sea_level if is_nan(level) else level, center, size))


## A water plane ("water_sea") at `level`, centred on `center` (x, z), `size` metres.
static func water_plane(level: float, center: Vector2, size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "water_sea"
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	mi.mesh = pm
	mi.position = Vector3(center.x, level, center.y)
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var info: Dictionary = Game.materials_db.get("nature/water_coast01", {})
	m.set_shader_parameter("normal_tex", SourceMaterials.tex(info.get("normal", "materials/nature/water_coast01_normal.png")))
	m.set_shader_parameter("fog_color", Color8(21, 48, 52))
	m.set_shader_parameter("fog_end", 9.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- props
## The collision shape of a static prop model, cached in `shapes` by key (+ "@scale").
static func _static_shape(shapes: Dictionary, key: String, model: Node3D, aabb: AABB) -> Shape3D:
	if shapes.has(key):
		return shapes[key]
	var sh: Shape3D
	if key.begins_with("props_buildings/") or key.begins_with("props_trainstation/train") or key.contains("boxcar") \
			or key.contains("tanker") or key.contains("flatcar") or key.begins_with("props_combine/combine_bunker") \
			or key.contains("combinetower") or key.contains("buttress"):
		# big irregular shapes collide with their real surface, never with an invisible box
		sh = _mesh_shape(model)
	elif key.begins_with("props_foliage/tree") or key.contains("lamppost") or key.contains("utilitypole") \
			or key.contains("powertower") or key.contains("signpole") or key.contains("traffic_light") \
			or key.begins_with("hl1/tree") or key.begins_with("hl1/light"):
		var c := CylinderShape3D.new()
		c.radius = clampf(minf(aabb.size.x, aabb.size.z) * 0.08, 0.15, 0.6)
		c.height = aabb.size.y
		sh = c
	elif key.contains("grass") or key.contains("fern") or key.contains("shrub") or key.contains("bush") \
			or key.begins_with("hl1/hair") or key.begins_with("hl1/uplant") or key.begins_with("hl1/fungus_small"):
		sh = null
	elif key.begins_with("hl1/crystal") or key.begins_with("hl1/fungus"):
		# a cluster of shards, a cap on legs: their hulls slope like a ramp a kart climbs and sticks
		# on; upright faces send it back off (the small fungi have none, above)
		var b := BoxShape3D.new()
		b.size = aabb.size * Vector3(0.8, 1.0, 0.8)
		sh = b
	else:
		sh = PhysProp.shape_for(key, model)
	shapes[key] = sh
	return sh


static func _mesh_shape(model: Node3D) -> Shape3D:
	var faces := PackedVector3Array()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := model.global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else _local_xf(model, m)
		for f in m.mesh.get_faces():
			faces.append(xf * f)
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	return sh


static func _local_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _spawn_props() -> void:
	var holder := Node3D.new()
	holder.name = "props"
	add_child(holder)
	for p in data.get("props", []):
		var n := prop_node(p, sea_level, _static_shapes)
		if n == null:
			continue
		holder.add_child(n)
		if n is PhysProp:
			# named in the tree as before (PhysProp.setup names it after its model)
			n.name = (n as PhysProp).model_key.get_file()
			(n as PhysProp).sleeping = true


## One prop of a track's data `p` ({model, pos, yaw, pitch?, roll?, scale?, physics?, tag?}) as a
## node (not in a tree; place it under a holder at the origin): a sleeping PhysProp for physics
## props, else a StaticBody3D carrying the model and its cached shape (`shapes`, by key), on the
## knock layer for street furniture. null when this install lacks the model. "float" props sit
## in the water at `sea_y` (the track's sea_level); "far" and "deco" props are never hit.
static func prop_node(p: Dictionary, sea_y: float, shapes: Dictionary) -> Node3D:
	var key: String = str(p.get("model", ""))
	if not Game.models.has(key):
		return null
	var pos := Vector3(p["pos"][0], p["pos"][1], p["pos"][2])
	var yaw: float = float(p.get("yaw", 0.0))
	if p.get("physics", false):
		var prop := PhysProp.new()
		prop.setup(key)
		prop.position = pos
		prop.rotation.y = yaw
		prop.sleeping = true
		return prop
	var model := Game.spawn_model(key)
	var sc: float = float(p.get("scale", 1.0))
	if sc != 1.0:
		model.scale = Vector3.ONE * sc
	var aabb := Game.model_aabb(key)
	if sc != 1.0:
		aabb = AABB(aabb.position * sc, aabb.size * sc)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	if _knockable(key):
		# not solid to karts: their sensor turns it into a physics prop on contact
		body.set_meta("knockable", key)
		body.collision_layer = Game.LAYER_KNOCK
	body.add_child(model)
	body.position = pos
	body.rotation.y = yaw
	# a tilted prop (a derailed wagon): pitch and roll in radians, rotation order YXZ with the yaw
	var pitch := float(p.get("pitch", 0.0))
	var roll := float(p.get("roll", 0.0))
	if pitch != 0.0 or roll != 0.0:
		body.rotation = Vector3(pitch, yaw, roll)
	if p.get("tag", "") == "float":
		body.position.y = sea_y - aabb.size.y * 0.25
	# distant set dressing (floating rocks, the Nihilanth) is never reached, and decoration a
	# circuit tags "deco" (crystals where knocked karts slide by) is seen, never hit
	var sh: Shape3D = null if p.get("tag", "") in ["far", "deco"] \
		else _static_shape(shapes, key + ("@%.2f" % sc if sc != 1.0 else ""), model, aabb)
	if sh:
		var cs := CollisionShape3D.new()
		cs.shape = sh
		# mesh and hull shapes are in the model's own units: they scale with it (uniform)
		if sh is ConcavePolygonShape3D or sh is ConvexPolygonShape3D:
			cs.scale = Vector3.ONE * sc
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
	return body


## Street furniture a kart can flatten (it turns into a prop_physics on impact).
static func _knockable(key: String) -> bool:
	for k in ["lamppost", "signpole", "streetsign", "bench", "payphone", "trashcan", "trashbin", "traffic_light",
			"wood_fence", "barricade00", "utilitypole", "cardboard", "dumpster", "furniture", "floodlight"]:
		if key.contains(k):
			return true
	return false


## Crates: [x, y, z] on level road; [x, y, z, ux, uy, uz] on tilted road (tubes, banking),
## where u is the local surface up: the crate's offset, bob and spin then follow it.
func _spawn_item_boxes() -> void:
	for p in data.get("item_boxes", []):
		var b := ItemBox.new()
		b.index = item_boxes.size()
		add_child(b)
		var pos := Vector3(p[0], p[1], p[2])
		if p.size() >= 6:
			b.global_transform = Transform3D(basis_up(Vector3(p[3], p[4], p[5]).normalized()), pos)
		else:
			b.global_position = pos
		item_boxes.append(b)


## Pads: {"pos", "fwd", "up"} on the surface; inside a tube also "r" (the pipe radius) so the
## pad bends onto the curved floor, and optionally "axis" (the pipe's direction) for a lane
## that winds round it.
func _spawn_boost_pads() -> void:
	for p in data.get("boost_pads", []):
		var pad := BoostPad.new()
		pad.radius = float(p.get("r", 0.0))
		var pos := Vector3(p["pos"][0], p["pos"][1], p["pos"][2])
		var f := Vector3(p["fwd"][0], p["fwd"][1], p["fwd"][2])
		var u := Vector3(p["up"][0], p["up"][1], p["up"][2])
		var xf := Transform3D(Basis(f.cross(u).normalized(), u, -f), pos)
		if p.has("axis"):
			pad.axis = xf.basis.inverse() * Vector3(p["axis"][0], p["axis"][1], p["axis"][2])
		add_child(pad)
		pad.global_transform = xf


## A basis whose Y is the unit vector `up`, its X kept as close to world X as possible.
static func basis_up(up: Vector3) -> Basis:
	var x := Vector3.RIGHT - up * up.x
	if x.length() < 0.1:
		x = Vector3.BACK.cross(up)
	x = x.normalized()
	return Basis(x, up, x.cross(up))


## Big Breencast screens on buildings, showing the start arch's live feed.
func _spawn_screens(feed: BreenFeed) -> void:
	if feed == null:
		return
	for e in data.get("screens", []):
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
		root.rotation.y = float(e.get("yaw", 0.0))
		var w: float = float(e.get("w", 8.0))
		var h: float = float(e.get("h", 4.5))
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(w + 0.6, h + 0.6, 0.5)
		frame.mesh = fb
		frame.material_override = SourceMaterials.world_material("metal/citadel_metalwall072a", Vector2(1, 1))
		frame.position = Vector3(0, 0, -0.3)
		root.add_child(frame)
		var scr := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		scr.mesh = q
		scr.material_override = feed.screen_material()
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(scr)


## Point lights a circuit asks for (tunnels, halls): no shadows, faded out with distance.
func _spawn_lights() -> void:
	for l in data.get("lights", []):
		var o := OmniLight3D.new()
		o.position = Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
		o.light_color = Color(l["color"][0], l["color"][1], l["color"][2])
		o.omni_range = float(l.get("range", 16.0))
		o.light_energy = float(l.get("energy", 1.2))
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 90.0
		o.distance_fade_length = 40.0
		add_child(o)


## Distant set dressing: the Citadel, striders, circling gunship.
func _spawn_background() -> void:
	var bg_kind := str(data.get("background", "city17"))
	if bg_kind == "none":
		return
	var cpos: Array = data.get("citadel", [-900, -260, -2300, 9.0])
	if bg_kind != "city17":
		return
	var cit := Game.spawn_model("props_combine/combine_citadel001")
	add_child(cit)
	cit.scale = Vector3.ONE * float(cpos[3])
	cit.global_position = Vector3(cpos[0], cpos[1], cpos[2])
	for mi in cit.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bg := BackgroundLife.new()
	add_child(bg)
	bg.setup(self)


# ---------------------------------------------------------------- queries
## The liquid a kart at `p` (closest sample `i` of road `g`, the main loop by default) is over
## or in: Vector2(surface y, kind), kind 0 none, 1 water, 2 slime. Water planes (sea, canal,
## river, lakes), then the pits and pools a circuit exports per path sample (beside the road
## or under it).
func liquid_at(p: Vector3, i: int, g: TrackPath = null) -> Vector2:
	if g == null:
		g = path
	var best := Vector2(-1e9, 0.0)
	if has_sea:
		best = Vector2(sea_level, 1.0)
	for l in _lakes:
		if float(l[1]) > best.x and (l[0] as Rect2).has_point(Vector2(p.x, p.z)):
			best = Vector2(float(l[1]), 1.0)
	if i >= 0 and i < g.liquid_kind.size() and g.liquid_kind[i] > 0:
		var beside := absf(g.lateral(p, i)) > g.width[i] * 0.5
		var y: float = g.liquid_side[i] if beside else g.liquid[i]
		if y > best.x:
			best = Vector2(y, float(g.liquid_kind[i]))
	return best


func spawn_transform(slot: int) -> Transform3D:
	var g: Array = data["grid"]
	var e: Dictionary = g[slot % g.size()]
	var pos := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
	var f := Vector3(e["fwd"][0], e["fwd"][1], e["fwd"][2]).normalized()
	return Transform3D(Basis.looking_at(f, Vector3.UP), pos)


## Per-circuit light: indoor Black Mesa has no sun, Xen glows purple, the desert burns.
## `ambient_energy` is the ambient's strength with an `ambient` colour (default 1.0) and on the
## sky's own ambient without one (default 1.35, as before).
static func _env_overrides(en: Environment, sl: DirectionalLight3D, e: Dictionary) -> void:
	if e.has("ambient"):
		var a: Array = e["ambient"]
		en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		en.ambient_light_color = Color(a[0], a[1], a[2])
		en.ambient_light_energy = float(e.get("ambient_energy", 1.0))
	else:
		en.ambient_light_energy = float(e.get("ambient_energy", 1.35))
	if e.has("sun_energy"):
		sl.light_energy = float(e["sun_energy"])
		sl.visible = sl.light_energy > 0.0
	if e.has("sun_color"):
		var c: Array = e["sun_color"]
		sl.light_color = Color(c[0], c[1], c[2])
	if e.has("sun_dir"):
		var d: Array = e["sun_dir"]
		var dir := Vector3(d[0], d[1], d[2]).normalized()
		sl.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	if e.has("fog_color"):
		var f: Array = e["fog_color"]
		en.fog_light_color = Color(f[0], f[1], f[2])
	en.fog_depth_begin = float(e.get("fog_begin", en.fog_depth_begin))
	en.fog_depth_end = float(e.get("fog_end", en.fog_depth_end))
	en.fog_sky_affect = float(e.get("fog_sky", en.fog_sky_affect))
	en.tonemap_exposure = float(e.get("exposure", en.tonemap_exposure))
	en.glow_intensity = float(e.get("glow", en.glow_intensity))
	if e.has("sky_energy"):
		(en.sky.sky_material as ShaderMaterial).set_shader_parameter("exposure", float(e["sky_energy"]))


## Karts and props are lit to match the map: light_environment's colour and
## angle, the track's ambient level (indoor maps are dim, Xen is purple...).
static func _bsp_lighting(en: Environment, sl: DirectionalLight3D, d: Dictionary) -> void:
	var sd = d.get("sun")
	if sd is Dictionary and sd.has("pitch"):
		var pitch := deg_to_rad(float(sd["pitch"]))
		var yaw := deg_to_rad(float(sd.get("yaw", 0.0)))
		# Source/GoldSrc: pitch is negative looking down, yaw around Z; convert to a Godot direction
		var dir_src := Vector3(cos(yaw) * cos(pitch), sin(yaw) * cos(pitch), sin(pitch))
		var dir := Vector3(dir_src.x, dir_src.z, -dir_src.y).normalized()
		if dir.y > -0.1:
			dir = Vector3(dir.x, -0.6, dir.z).normalized()
		sl.look_at_from_position(Vector3.ZERO, dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		var c: Array = sd.get("color", [1, 1, 1])
		sl.light_color = Color(c[0], c[1], c[2])
	var kl: float = d.get("kart_light", 1.0)
	sl.light_energy = 1.5 * kl
	var amb: Array = d.get("ambient", [0.6, 0.6, 0.6])
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(amb[0], amb[1], amb[2])
	en.ambient_light_energy = 1.0
	en.fog_depth_begin = float(d.get("fog_begin", 250.0))
	en.fog_depth_end = float(d.get("fog_end", 1800.0))
	en.tonemap_exposure = float(d.get("exposure", 1.0))
