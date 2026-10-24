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

static var _mat: ShaderMaterial


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
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.5, 6.0)
	mi.mesh = pm
	mi.material_override = _mat
	mi.position = Vector3(0, 0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.3)
	l.omni_range = 5.0
	l.light_energy = 0.7
	l.position = Vector3(0, 0.6, 0)
	add_child(l)
	body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if body is Kart and not (body as Kart).remote:
		var k := body as Kart
		k.boost(1.1, 1.0)
		if k.is_player:
			Game.play_ui("res://assets/sound/weapons/physcannon/energy_bounce1.wav", -4.0)
