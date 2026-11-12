class_name BoostPad
extends Area3D
## Dash panel styled as a Combine energy strip with HUD-yellow chevrons.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0, 0.86, 0.0, 1.0);
void fragment() {
	float v = fract(UV.y * 3.0 + TIME * 2.2);
	float x = abs(UV.x - 0.5) * 2.0;
	float chevron = smoothstep(0.08, 0.0, abs(v - 0.5 - x * 0.35));
	float edge = smoothstep(0.92, 1.0, x);
	float glow = 0.18 + chevron * 1.4 + edge * 0.8;
	ALBEDO = col.rgb * glow * 2.0;
}
"""

const SIZE := Vector2(4.5, 6.0)
const LIFT := 0.05

static var _mat: ShaderMaterial
## inside a tube: the pipe radius (set before the pad enters the tree). The pad bends across
## its X onto a cylinder whose axis runs through (0, radius, 0) along `axis` (local, default Z)
var radius := 0.0
var axis := Vector3.BACK


func _ready() -> void:
	collision_layer = Game.LAYER_TRIGGER
	collision_mask = Game.LAYER_KART
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4.5, 2.0, 6.0)
	cs.shape = b
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)
	if _mat == null:
		_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_mat.shader = sh
	var mi := MeshInstance3D.new()
	if radius > 0.0:
		mi.mesh = _bent_mesh()
	else:
		var pm := PlaneMesh.new()
		pm.size = SIZE
		mi.mesh = pm
		mi.position = Vector3(0, LIFT, 0)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.3)
	l.omni_range = 5.0
	l.light_energy = 0.7
	l.position = Vector3(0, 0.6, 0)
	add_child(l)
	body_entered.connect(_on_body)


## The pad as a grid laid on the pipe floor: every point of the flat pad moves along up by
## r - sqrt(r^2 - x^2) + LIFT, x being its distance across the pipe's axis (the pad's X when
## the axis runs along its Z). UVs as PlaneMesh.
func _bent_mesh() -> ArrayMesh:
	var a := Vector3(axis.x, 0.0, axis.z).normalized() if Vector2(axis.x, axis.z).length() > 0.01 else Vector3.BACK
	var across := Vector3.UP.cross(a)
	var c := Vector3(0, radius, 0)
	var nx := 12
	var nz := 1 if absf(a.z) > 0.999 else 8
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in nz + 1:
		for i in nx + 1:
			var uv := Vector2(float(i) / nx, float(j) / nz)
			var q := Vector3((uv.x - 0.5) * SIZE.x, 0.0, (uv.y - 0.5) * SIZE.y)
			var x := minf(absf(q.dot(across)), radius * 0.95)
			q.y = radius - sqrt(radius * radius - x * x) + LIFT
			var w := q - c
			w -= a * w.dot(a)
			verts.append(q)
			norms.append(-w.normalized())
			uvs.append(uv)
	var idx := PackedInt32Array()
	for j in nz:
		for i in nx:
			var v0 := j * (nx + 1) + i
			idx.append_array([v0, v0 + 1, v0 + nx + 1, v0 + 1, v0 + nx + 2, v0 + nx + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _on_body(body: Node) -> void:
	if body is Kart and not (body as Kart).remote:
		var k := body as Kart
		# a kart parked on the grid is never launched before GO!
		if k.race and not k.race.get("racing"):
			return
		k.boost(1.1, 1.0)
		if k.is_player:
			Game.play_ui("res://assets/sound/weapons/physcannon/energy_bounce1.wav", -4.0)
