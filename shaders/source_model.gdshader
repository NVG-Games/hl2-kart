// VertexLitGeneric approximation: half-lambert diffuse, phong specular with
// normal-map-alpha / base-alpha masks and fresnel ranges, env mask, self-illum.
shader_type spatial;
render_mode depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount = 0.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform sampler2D mask_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_mask_tex = false;
uniform bool phong = false;
uniform bool phong_mask_base_alpha = false;
uniform float phong_boost = 1.0;
uniform float phong_exponent = 20.0;
uniform vec3 fresnel_ranges = vec3(0.05, 0.5, 1.0);
uniform bool half_lambert = false;
uniform float alpha_cut = 0.0;
uniform float selfillum = 0.0;
uniform sampler2D selfillum_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_selfillum_mask = false;
uniform float env_amount = 0.0;
uniform int env_mask_mode = 0; // 0 none, 1 base alpha, 2 normal alpha, 3 mask texture
uniform sampler2D env_mask_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float flash = 0.0; // hit / invincibility flash

varying float v_phong;

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	vec3 col = mix(base.rgb, base.rgb * tint.rgb * 1.6, tint_amount);
	ALBEDO = col;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float pm = 0.0;
	if (phong) {
		pm = phong_mask_base_alpha ? base.a : (has_mask_tex ? texture(mask_tex, UV).r : 1.0);
		pm *= phong_boost;
	}
	v_phong = pm;
	float em = env_amount;
	if (env_mask_mode == 1) {
		em *= base.a;
	} else if (env_mask_mode == 2) {
		em *= has_mask_tex ? texture(mask_tex, UV).r : 1.0;
	} else if (env_mask_mode == 3) {
		em *= texture(env_mask_tex, UV).r;
	}
	em = clamp(em, 0.0, 1.0);
	ROUGHNESS = mix(0.9, 0.2, em);
	SPECULAR = mix(0.12, 0.65, em);
	METALLIC = 0.0;
	vec3 emit = vec3(0.0);
	if (selfillum > 0.0) {
		float m = has_selfillum_mask ? texture(selfillum_mask, UV).r : base.a;
		emit = col * m * selfillum;
	}
	EMISSION = emit + vec3(flash);
	if (alpha_cut > 0.0) {
		ALPHA = base.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = half_lambert ? pow(ndl * 0.5 + 0.5, 2.0) : max(ndl, 0.0);
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / PI;
	if (v_phong > 0.0) {
		vec3 r = reflect(-LIGHT, NORMAL);
		float rv = max(dot(r, VIEW), 0.0);
		float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		f = f * f;
		float fres = f > 0.5 ? mix(fresnel_ranges.y, fresnel_ranges.z, (f - 0.5) * 2.0)
				: mix(fresnel_ranges.x, fresnel_ranges.y, f * 2.0);
		float spec = pow(rv, phong_exponent) * v_phong * fres * clamp(ndl * 4.0, 0.0, 1.0);
		SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR / PI;
	}
}
