// HL2 skybox: six Source faces pre-baked into an equirect panorama
// (tools/make_skies.py uses the same mapping).
shader_type sky;

uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float exposure = 1.0;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	COLOR = texture(pano, uv).rgb * exposure;
}
