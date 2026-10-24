// Displacement-style terrain: WorldVertexTransition blending of HL2 nature
// textures driven by vertex colour (r dirt, g rock, b pavement, a sand).
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float base_scale = 1.0;
uniform float dirt_scale = 1.0;
uniform float rock_scale = 0.5;
uniform float pave_scale = 0.6;
uniform float sand_scale = 0.8;

float blend_w(float w, float h) {
	// height-aware transition like $blendmodulatetexture: sharper, textured edges
	return smoothstep(0.35, 0.65, w + (h - 0.5) * 0.5);
}

void fragment() {
	vec2 uv = UV;
	vec4 w = COLOR;
	vec3 base = texture(base_tex, uv * base_scale).rgb;
	// break up tiling with a large-scale variation from the same texture
	base *= mix(0.8, 1.15, texture(base_tex, uv * 0.031).g * 1.6);
	vec3 sand = texture(sand_tex, uv * sand_scale).rgb;
	vec3 dirt = texture(dirt_tex, uv * dirt_scale).rgb;
	vec3 pave = texture(pave_tex, uv * pave_scale).rgb;
	vec3 rock = texture(rock_tex, uv * rock_scale).rgb;
	vec3 c = base;
	c = mix(c, sand, blend_w(w.a, dot(sand, vec3(0.33))));
	c = mix(c, dirt, blend_w(w.r, dot(dirt, vec3(0.33))));
	c = mix(c, pave, blend_w(w.b, dot(pave, vec3(0.33))));
	float rw = blend_w(w.g, dot(rock, vec3(0.33)));
	c = mix(c, rock, rw);
	vec3 d = texture(detail_tex, uv * 4.0).rgb;
	c = mix(c, c * d * 2.0, 0.4);
	ALBEDO = c;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(rock_normal, uv * rock_scale).rgb, rw);
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
}
