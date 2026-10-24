// Additive Source sprite (glows, sparks, combine energy) with vertex colour.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(1.0);
uniform float intensity = 1.0;

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * color.rgb * COLOR.rgb * intensity * t.a * COLOR.a;
}
