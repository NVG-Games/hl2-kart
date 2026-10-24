// LightmappedGeneric approximation: lambert world surfaces with Source detail
// textures (mod2x), bump maps and env-mapped masks.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_detail = false;
uniform float detail_scale = 4.0;
uniform float detail_blend = 0.5;
uniform float env_amount = 0.0;
uniform sampler2D env_mask_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_env_mask = false;
uniform vec2 uv_scale = vec2(1.0);
uniform float alpha_cut = 0.0;
uniform float emission = 0.0;  // $selfillum / HL1 "~" light textures

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 b = texture(albedo_tex, uv) * albedo_color;
	vec3 c = b.rgb;
	if (has_detail) {
		vec3 d = texture(detail_tex, uv * detail_scale).rgb;
		c = mix(c, c * d * 2.0, detail_blend);
	}
	ALBEDO = c;
	EMISSION = c * emission;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
	float em = env_amount * (has_env_mask ? texture(env_mask_tex, uv).r : 1.0);
	em = clamp(em, 0.0, 1.0);
	ROUGHNESS = mix(0.95, 0.3, em);
	SPECULAR = mix(0.1, 0.5, em);
	if (alpha_cut > 0.0) {
		ALPHA = b.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}
