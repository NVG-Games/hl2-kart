// BSP world surfaces (Half-Life 1 / Half-Life 2 maps): base texture times the
// map's own baked lightmap (second UV), like the engines draw them.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D albedo2_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_blend = false;
uniform float lm_scale = 2.0;
uniform float brightness = 1.0;
uniform bool fullbright = false;
uniform float alpha_cut = 0.0;

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	if (has_blend) {
		// WorldVertexTransition: displacement vertex alpha blends the two textures
		a = mix(a, texture(albedo2_tex, UV), clamp(COLOR.a, 0.0, 1.0));
	}
	vec3 lm = fullbright ? vec3(1.0) : texture(lightmap_tex, UV2).rgb * lm_scale;
	ALBEDO = a.rgb * lm * brightness;
	if (alpha_cut > 0.0) {
		ALPHA = a.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}
