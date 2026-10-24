// Source "Water" shader: two scrolling normal maps ($scroll1/$scroll2),
// screen refraction with depth fog ($fogcolor/$fogend) and env reflection.
shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 fog_color : source_color = vec3(0.082, 0.188, 0.204);
uniform float fog_end = 12.0;
uniform vec2 scroll1 = vec2(0.01, 0.05);
uniform vec2 scroll2 = vec2(-0.025, 0.075);
uniform float uv_scale = 0.04;
uniform float refract_amount = 0.035;
uniform float reflect_amount = 0.6;

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wpos.xz * uv_scale;
	vec3 n1 = texture(normal_tex, uv + TIME * scroll1).rgb;
	vec3 n2 = texture(normal_tex, uv * 1.37 + TIME * scroll2).rgb;
	vec3 n = normalize(n1 + n2 - 1.0);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.7;
	vec2 off = (n.xy) * refract_amount;
	float depth = texture(depth_tex, SCREEN_UV + off).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV + off, depth) * vec3(2.0, 2.0, 1.0) - vec3(1.0, 1.0, 0.0), 1.0);
	vp.xyz /= vp.w;
	float water_depth = max(-vp.z - (-VERTEX.z), 0.0);
	if (-vp.z < -VERTEX.z) {
		off = vec2(0.0);
		depth = texture(depth_tex, SCREEN_UV).r;
		vp = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * vec3(2.0, 2.0, 1.0) - vec3(1.0, 1.0, 0.0), 1.0);
		vp.xyz /= vp.w;
		water_depth = max(-vp.z - (-VERTEX.z), 0.0);
	}
	float fogf = clamp(water_depth / fog_end, 0.0, 1.0);
	vec3 refr = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	vec3 col = mix(refr * vec3(0.8, 0.9, 0.9), fog_color, fogf);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = vec3(0.0);
	EMISSION = col * (1.0 - fres * reflect_amount);
	ROUGHNESS = 0.04;
	SPECULAR = 0.5 * reflect_amount + 0.2;
	METALLIC = 0.0;
}
