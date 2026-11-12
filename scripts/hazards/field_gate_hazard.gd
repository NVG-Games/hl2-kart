class_name FieldGateHazard
extends Hazard
## A Combine checkpoint gate: force-field lanes between posts across the road switch on
## and off on a pattern of the shared clock (the same on every peer, no traffic). A lane
## about to close flickers first; drive into a closed one and the field throws you back.

## Lane states (lanes_at).
enum { OPEN, CLOSED, CLOSING, IDLE }
const FIELD := Color(0.35, 0.65, 1.0)
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
uniform sampler2D tex : source_color, repeat_enable;
instance uniform vec4 col : source_color = vec4(0.35, 0.65, 1.0, 1.0);
void fragment() {
	vec2 uv = vec2(UV.x * 2.0, UV.y * 0.5 + TIME * 0.6);
	float f = texture(tex, uv).r * 0.8 + texture(tex, uv * 0.5 + vec2(0.3, -TIME * 0.25)).g * 0.5;
	float edge = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.95, UV.y);
	ALBEDO = col.rgb * (0.35 + f * 1.3);
	ALPHA = col.a * edge;
}
"""

static var _mat: ShaderMaterial

var _posts: Array[Vector3] = []
var _lane_lat: PackedFloat32Array = []   # lateral of each lane's middle
var _fwd := Vector3.FORWARD
var _across := Vector3.RIGHT
var _fields: Array[MeshInstance3D] = []
var _pattern: Array = []
var _sides := {}
var _hum: AudioStreamPlayer3D
var _snd := {}


func defaults() -> Dictionary:
	return {"posts": [], "fwd": [], "pattern": [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1]], "step": 2.0, "warn": 0.7,
		"first": 0.0, "h": 3.2, "post_model": "props_combine/combine_fence01a"}


func build() -> void:
	for q in p["posts"]:
		_posts.append(Vector3(q[0], q[1], q[2]))
	if _posts.size() < 2:
		var hw := half_width(s)
		_posts.assign([road_point(s, -hw), road_point(s, hw)])
	var f: Array = p["fwd"]
	_fwd = Vector3(f[0], 0.0, f[2]).normalized() if f.size() == 3 else path.fwd[path.index_at(s)]
	_across = (_posts[-1] - _posts[0]).normalized()
	var n := _posts.size() - 1
	_pattern = p["pattern"]
	if _pattern.is_empty() or (_pattern[0] as Array).size() != n:
		# a pattern written for another number of lanes: one closed lane walking across
		_pattern = []
		for k in n:
			var row := []
			for j in n:
				row.append(1 if j == k else 0)
			_pattern.append(row)
	var i := path.index_at(s)
	for j in n:
		_lane_lat.append(path.lateral((_posts[j] + _posts[j + 1]) * 0.5, i))
	_snd["touch"] = sounds([["ambient/machines/combine_shield_touch_loop1.wav"], ["ambient/energy/spark1.wav"]])
	_snd["zap"] = sounds([["ambient/energy/zap1.wav", "ambient/energy/zap5.wav"]])
	for q in _posts:
		_post(q)
	if not visual:
		return
	if _mat == null:
		_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_mat.shader = sh
		var tex := SourceMaterials.tex("materials/models/props_combine/combine_fenceglow.png")
		_mat.set_shader_parameter("tex", tex if tex else SourceMaterials.tex("materials/effects/com_shield002a.png"))
	var h := float(p["h"])
	for j in n:
		var a := _posts[j]
		var b := _posts[j + 1]
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(a.distance_to(b) - 0.5, h)
		mi.mesh = q
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var x := (b - a).normalized()
		mi.global_transform = Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), (a + b) * 0.5 + Vector3.UP * h * 0.5)
		_fields.append(mi)
	_hum = loop(["ambient/machines/combine_shield_loop3.wav", "weapons/physcannon/hold_loop.wav"], self, 12.0, -6.0)


## A gate post: the Combine fence pylon, solid like a barrier.
func _post(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	add_child(body)
	body.global_transform = Transform3D(Basis.looking_at(-_fwd, Vector3.UP), at)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 4.9, 1.6)
	cs.shape = bs
	cs.position = Vector3(0.0, 2.45, 0.0)
	body.add_child(cs)
	var key := str(p["post_model"])
	if visual and Game.models.has(key):
		var m := Game.spawn_model(key)
		body.add_child(m)
		var box := Game.model_aabb(key)
		m.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)


## Lane states at clock t (OPEN, CLOSED, CLOSING or IDLE before the start).
func lanes_at(t: float) -> PackedInt32Array:
	var n := _posts.size() - 1
	var out := PackedInt32Array()
	out.resize(n)
	var tt := t - float(p["first"])
	if t < 0.0 or tt < 0.0:
		out.fill(IDLE)
		return out
	var step := tm("step")
	var m := int(floor(tt / step))
	var cur: Array = _pattern[m % _pattern.size()]
	var nxt: Array = _pattern[(m + 1) % _pattern.size()]
	var left := step - (tt - m * step)
	for j in n:
		if int(cur[j]) == 1:
			out[j] = CLOSED
		elif int(nxt[j]) == 1 and left < tm("warn"):
			out[j] = CLOSING
		else:
			out[j] = OPEN
	return out


func snapshot(t: float) -> Array:
	return Array(lanes_at(t))


func tick(t: float, _dt: float) -> void:
	var lanes := lanes_at(t)
	# what changed since the previous clock tick (kept by the director, asleep or not): the
	# timetable's own moments, the same on every peer whenever it woke
	var was := lanes_at(_last_t) if _last_t > -1e8 else lanes
	for j in lanes.size():
		if lanes[j] != was[j] and (lanes[j] == CLOSING or lanes[j] == CLOSED):
			director.note(self, "warn" if lanes[j] == CLOSING else "fire")
	if visual:
		for j in _fields.size():
			var a := 0.0
			match lanes[j]:
				CLOSED:
					a = 0.85
				CLOSING:
					a = 0.3 if fmod(t * 18.0, 1.0) < 0.5 else 0.05
				IDLE:
					a = 0.1 + 0.05 * sin(t * 3.0 + j)
			_fields[j].visible = a > 0.0
			_fields[j].set_instance_shader_parameter("col", Color(FIELD, a))
			if lanes[j] == CLOSING and was[j] != CLOSING:
				play(_snd["touch"], (_posts[j] + _posts[j + 1]) * 0.5 + Vector3.UP * 1.5, -6.0, 10.0)
	var c := (_posts[0] + _posts[-1]) * 0.5
	for k in local_karts():
		var side := signf((k.global_position - c).dot(_fwd))
		var before: float = _sides.get(k, side)
		_sides[k] = side
		if side == before or k.state == Kart.State.RESPAWN:
			continue
		var u := (k.global_position - _posts[0]).dot(_across) / _posts[0].distance_to(_posts[-1]) * (_posts.size() - 1)
		var j := int(floor(u))
		if j < 0 or j >= lanes.size() or lanes[j] != CLOSED or absf(k.global_position.y - c.y) > float(p["h"]):
			continue
		if hit(k, "bounce"):
			Effects.sparks(get_parent(), k.global_position + Vector3.UP, 1.2, FIELD)
			play(_snd["zap"], k.global_position, 2.0, 14.0)


func wake() -> void:
	if _hum:
		_hum.play()


func sleep() -> void:
	_sides.clear()
	if _hum:
		_hum.stop()


## Head for a lane that is open on arrival; if none will be, arrive when one opens.
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var dist := ahead(at_s, s)
	if dist > 160.0:
		return {}
	var t := director.clock()
	var arrive := t + dist / maxf(speed, 6.0)
	var a := lanes_at(arrive - 0.3)
	var b := lanes_at(arrive)
	var c := lanes_at(arrive + 0.3)
	var lat := kart_lat(k)
	var best := -1
	for j in b.size():
		if a[j] != CLOSED and b[j] != CLOSED and c[j] != CLOSED:
			if best < 0 or absf(_lane_lat[j] - lat) < absf(_lane_lat[best] - lat):
				best = j
	if best >= 0:
		return {"lat": _lane_lat[best], "w": 0.8}
	# every lane shut on arrival: slow down to arrive as the next one opens
	var later := arrive
	for _i in 20:
		later += 0.25
		if Array(lanes_at(later)).has(OPEN):
			break
	return {"vmax": dist / maxf(later - t, 0.5)}


func blocks_respawn(at_s: float) -> bool:
	return absf(fposmod(at_s - s + path.length * 0.5, path.length) - path.length * 0.5) <= 8.0


func is_active(t: float) -> bool:
	return Array(lanes_at(t)).has(CLOSED)
