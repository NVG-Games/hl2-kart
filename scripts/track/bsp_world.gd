class_name BspWorld
extends Node3D
## A converted Half-Life / Half-Life 2 map (tools/goldsrc_world.py,
## tools/source_world.py): textured meshes lit by the map's baked lightmap
## and static collision split into road / offroad.

const SHADER := preload("res://shaders/bsp_world.gdshader")
const ADD_SHADER := preload("res://shaders/sprite_add.gdshader")

var key := ""
var info := {}
var body: StaticBody3D
var feed: BreenFeed
var _mats := {}


func load_map(map_key: String) -> void:
	key = map_key
	name = "BspWorld"
	var base := "res://assets/maps/%s/" % key
	info = Game.load_json(base + "world.json")
	var scene: PackedScene = load(base + "world.gltf")
	var w := scene.instantiate()
	add_child(w)
	var lm: Texture2D = load(base + str(info.get("lightmap", "lightmap.png")))
	var mats: Dictionary = info.get("materials", {})
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in m.mesh.get_surface_count():
			var mname := m.mesh.surface_get_material(s).resource_name if m.mesh.surface_get_material(s) else ""
			if mname.contains("@sky3d"):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.set_surface_override_material(s, _material(mname, mats.get(mname, {}), lm))
	_build_collision(base)
	_spawn_props()


func _material(mname: String, d: Dictionary, lm: Texture2D) -> Material:
	if _mats.has(mname):
		return _mats[mname]
	var tex: Texture2D = SourceMaterials.tex(str(d.get("albedo", "")))
	var m: Material
	if d.get("monitor", false):
		# Combine screens: the live Breencast
		if feed == null:
			feed = BreenFeed.new()
			add_child(feed)
		m = feed.screen_material(false)
	elif d.get("additive", false):
		var a := ShaderMaterial.new()
		a.shader = ADD_SHADER
		a.set_shader_parameter("tex", tex)
		m = a
	elif float(d.get("opacity", 1.0)) < 0.99 or d.get("water", false) or d.get("translucent", false):
		var g := StandardMaterial3D.new()
		g.albedo_texture = tex
		g.albedo_color = Color(1, 1, 1, clampf(float(d.get("opacity", 0.6)), 0.15, 0.95) if not d.get("water", false) else 0.8)
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m = g
	else:
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("albedo_tex", tex)
		sm.set_shader_parameter("lightmap_tex", lm)
		sm.set_shader_parameter("lm_scale", float(info.get("lm_scale", 2.0)))
		sm.set_shader_parameter("fullbright", bool(d.get("fullbright", false)) and false)
		if d.get("alpha", false):
			sm.set_shader_parameter("alpha_cut", 0.5)
		if d.has("albedo2"):
			sm.set_shader_parameter("has_blend", true)
			sm.set_shader_parameter("albedo2_tex", SourceMaterials.tex(str(d["albedo2"])))
		m = sm
	_mats[mname] = m
	return m


func _build_collision(base: String) -> void:
	var c: Dictionary = info.get("collision", {})
	for kind in c:
		var f := FileAccess.open(base + str(c[kind]), FileAccess.READ)
		if f == null:
			continue
		var raw := f.get_buffer(f.get_length())
		var floats := raw.to_float32_array()
		var verts := PackedVector3Array()
		verts.resize(floats.size() / 3)
		for i in verts.size():
			verts[i] = Vector3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
		var b := StaticBody3D.new()
		b.name = "col_" + kind
		b.collision_layer = Game.LAYER_WORLD
		b.collision_mask = 0
		b.set_meta("surface", kind)
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(verts)
		cs.shape = sh
		b.add_child(cs)
		add_child(b)
		if kind == "road":
			body = b


## HL2 static props (prop_static): the converted MDLs where the map put them.
func _spawn_props() -> void:
	var props: Array = info.get("props", [])
	if props.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "StaticProps"
	add_child(holder)
	for p in props:
		var inst := Game.spawn_model(str(p["model"]), "", int(p.get("skin", 0)))
		var b: Array = p["basis"]
		var o: Array = p["origin"]
		inst.transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])), Vector3(o[0], o[1], o[2]))
		holder.add_child(inst)
		if int(p.get("solid", 0)) == 0 or p.get("aabb_min") == null:
			continue
		var lo: Array = p["aabb_min"]
		var hi: Array = p["aabb_max"]
		var size := Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
		if size.length() < 0.3:
			continue
		var key := str(p["model"])
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", "wall")
		var cs := CollisionShape3D.new()
		var centre := Vector3(lo[0] + hi[0], lo[1] + hi[1], lo[2] + hi[2]) * 0.5
		if knockable(key):
			# bollards, benches, bins: karts flatten them (Kart's front sensor)
			body.collision_layer = Game.LAYER_KNOCK
			body.set_meta("knockable", key)
		if trunk(key):
			var cyl := CylinderShape3D.new()
			cyl.radius = clampf(minf(size.x, size.z) * 0.08, 0.15, 0.6)
			cyl.height = size.y
			cs.shape = cyl
			cs.position = Vector3(centre.x, lo[1] + size.y * 0.5, centre.z)
		else:
			var box := BoxShape3D.new()
			box.size = size
			cs.shape = box
			cs.position = centre
		body.add_child(cs)
		inst.add_child(body)


## Street furniture the karts knock over instead of stopping on it.
static func knockable(key: String) -> bool:
	for k in ["post0", "bollard", "bench", "payphone", "trashcan", "trashbin", "garbage", "lamppost", "cone",
			"chair", "table", "crate", "box0", "bottle", "paint", "cardboard", "newspaper", "pallet", "barrel"]:
		if key.contains(k):
			return true
	return false


## Trees and poles block only with their trunk.
static func trunk(key: String) -> bool:
	for k in ["tree", "pole", "lamp", "antenna", "pipe", "column", "post"]:
		if key.contains(k):
			return true
	return false


func aabb() -> AABB:
	var a: Array = info.get("aabb_min", [0, 0, 0])
	var b: Array = info.get("aabb_max", [1, 1, 1])
	return AABB(Vector3(a[0], a[1], a[2]), Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]))
