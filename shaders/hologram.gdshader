// The Hazard Course hologram (hl1/holo): additive blue light with a bright rim,
// scanlines running up the body and a nervous flicker.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(0.3, 0.62, 1.0, 1.0);
uniform float strength = 1.1;
uniform float scan_density = 26.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scan = 0.6 + 0.4 * sin(world.y * scan_density - TIME * 9.0);
	float band = smoothstep(0.0, 0.08, abs(fract(world.y * 0.35 - TIME * 0.4) - 0.5));
	float flicker = 1.0 - 0.35 * step(0.92, hash(floor(TIME * 16.0)));
	float lum = dot(texture(albedo_tex, UV).rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = color.rgb * (0.18 + lum * 0.55 + rim * 1.3) * scan * (0.75 + 0.25 * band) * flicker * strength;
}
