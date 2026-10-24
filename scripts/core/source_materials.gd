class_name SourceMaterials
## Rebuilds imported glTF materials as Source-style shader materials using the
## VMT data exported by tools/materials.py (assets/data/materials.json).

const MODEL_SHADER := preload("res://shaders/source_model.gdshader")
const WORLD_SHADER := preload("res://shaders/source_world.gdshader")
const EYES_SHADER := preload("res://shaders/eyes.gdshader")
const SPRITE_SHADER := preload("res://shaders/sprite_add.gdshader")

static var _cache := {}
static var _tex_cache := {}


static func tex(rel: String) -> Texture2D:
	if rel == "":
		return null
	if _tex_cache.has(rel):
		return _tex_cache[rel]
	var path := "res://assets/" + rel
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[rel] = t
	return t


## Base texture of a VMT by material name (e.g. "particle/smokesprites_0001").
static func albedo(material_name: String) -> Texture2D:
	var info: Dictionary = Game.materials_db.get(material_name, {})
	return tex(info.get("albedo", "materials/" + material_name + ".png"))


static func _vec3(s: String, def := Vector3.ONE) -> Vector3:
	var parts := s.replace("[", " ").replace("]", " ").replace("{", " ").replace("}", " ").strip_edges().split(" ", false)
	if parts.size() >= 3:
		var v := Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
		if s.contains("{"):
			v /= 255.0
		return v
	if parts.size() == 1:
		var f := parts[0].to_float()
		return Vector3(f, f, f)
	return def


static func _num(info: Dictionary, key: String, def: float) -> float:
	if info.has(key):
		var v = info[key]
		if v is String:
			return _vec3(v, Vector3(def, def, def)).x
		return float(v)
	return def


## Material for a model surface. `variant` lets callers tint per-kart without
## sharing the same ShaderMaterial instance.
static func model_material(name: String, variant := "") -> Material:
	var key := name + "|" + variant
	if _cache.has(key):
		return _cache[key]
	var info: Dictionary = Game.materials_db.get(name, {})
	var m := _build_model_material(info)
	_cache[key] = m
	return m


static func _build_model_material(info: Dictionary) -> Material:
	var shader: String = info.get("shader", "vertexlitgeneric")
	var albedo := tex(info.get("albedo", ""))
	if shader == "eyes" or shader == "eyerefract" or info.get("eyeball", false):
		var e := ShaderMaterial.new()
		e.shader = EYES_SHADER
		# EyeRefract has no sclera texture: the iris map covers the whole eyeball
		e.set_shader_parameter("albedo_tex", albedo if albedo else tex(info.get("iris", "")))
		e.set_shader_parameter("iris_tex", tex(info.get("iris", "")))
		return e
	if info.get("additive", false):
		var s := ShaderMaterial.new()
		s.shader = SPRITE_SHADER
		s.set_shader_parameter("tex", albedo)
		return s
	if shader == "unlitgeneric" or info.get("translucent", false):
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = albedo
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if shader == "unlitgeneric" else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if info.get("translucent", false):
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		elif info.get("alphatest", false):
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		if info.get("nocull", false):
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.roughness = 0.9
		return sm
	var m := ShaderMaterial.new()
	m.shader = MODEL_SHADER
	m.set_shader_parameter("albedo_tex", albedo)
	var c := _vec3(str(info.get("color", "[1 1 1]")))
	m.set_shader_parameter("albedo_color", Color(c.x, c.y, c.z))
	var normal := tex(info.get("normal", ""))
	if normal:
		m.set_shader_parameter("normal_tex", normal)
		m.set_shader_parameter("has_normal", true)
	var mask := tex(info.get("normal_alpha", ""))
	if mask:
		m.set_shader_parameter("mask_tex", mask)
		m.set_shader_parameter("has_mask_tex", true)
	if info.get("phong", false):
		m.set_shader_parameter("phong", true)
		m.set_shader_parameter("phong_mask_base_alpha", info.get("basemapalphaphongmask", false))
		m.set_shader_parameter("phong_boost", _num(info, "phongboost", 1.0))
		m.set_shader_parameter("phong_exponent", _num(info, "phongexponent", 20.0))
		if info.has("phongfresnelranges"):
			m.set_shader_parameter("fresnel_ranges", _vec3(info["phongfresnelranges"], Vector3(0.05, 0.5, 1.0)))
	m.set_shader_parameter("half_lambert", info.get("halflambert", false) or info.get("phong", false))
	if info.get("alphatest", false):
		m.set_shader_parameter("alpha_cut", clampf(_num(info, "alphatestreference", 0.5), 0.05, 0.95))
	if info.get("selfillum", false):
		m.set_shader_parameter("selfillum", 1.0)
		var sim := tex(info.get("selfillummask_tex", ""))
		if sim:
			m.set_shader_parameter("selfillum_mask", sim)
			m.set_shader_parameter("has_selfillum_mask", true)
	if info.has("envmap"):
		var tint := _vec3(str(info.get("envmaptint", "[1 1 1]")))
		m.set_shader_parameter("env_amount", clampf((tint.x + tint.y + tint.z) / 3.0, 0.0, 1.0))
		if info.get("basealphaenvmapmask", false):
			m.set_shader_parameter("env_mask_mode", 1)
		elif info.get("normalmapalphaenvmapmask", false):
			m.set_shader_parameter("env_mask_mode", 2)
		elif info.has("envmapmask_tex"):
			m.set_shader_parameter("env_mask_mode", 3)
			m.set_shader_parameter("env_mask_tex", tex(info["envmapmask_tex"]))
	if info.get("nocull", false) or info.get("translucent", false):
		m.render_priority = 0
	return m


static func world_material(name: String, uv_scale := Vector2.ONE) -> Material:
	var key := "W|" + name + "|" + str(uv_scale)
	if _cache.has(key):
		return _cache[key]
	var info: Dictionary = Game.materials_db.get(name, {})
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	m.set_shader_parameter("albedo_tex", tex(info.get("albedo", "")))
	m.set_shader_parameter("uv_scale", uv_scale)
	var normal := tex(info.get("normal", ""))
	if normal:
		m.set_shader_parameter("normal_tex", normal)
		m.set_shader_parameter("has_normal", true)
	var det := tex(info.get("detail_tex", ""))
	if det:
		m.set_shader_parameter("detail_tex", det)
		m.set_shader_parameter("has_detail", true)
		m.set_shader_parameter("detail_scale", _num(info, "detailscale", 4.0))
		m.set_shader_parameter("detail_blend", _num(info, "detailblendfactor", 0.5))
	if info.has("envmap"):
		var tint := _vec3(str(info.get("envmaptint", "[0.4 0.4 0.4]")), Vector3(0.4, 0.4, 0.4))
		m.set_shader_parameter("env_amount", clampf((tint.x + tint.y + tint.z) / 3.0, 0.0, 1.0) * 0.6)
		var em := tex(info.get("envmapmask_tex", ""))
		if em:
			m.set_shader_parameter("env_mask_tex", em)
			m.set_shader_parameter("has_env_mask", true)
	if info.get("alphatest", false):
		m.set_shader_parameter("alpha_cut", 0.5)
	if info.get("selfillum", false):
		m.set_shader_parameter("emission", float(info.get("glow", 2.2)))
	_cache[key] = m
	return m


## Walk a model instance and swap every imported surface material.
static func apply_to(root: Node, variant := "", skin_map := {}) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var mname := src.resource_name
			if skin_map.has(mname):
				mname = skin_map[mname]
			mi.set_surface_override_material(i, model_material(mname, variant))
