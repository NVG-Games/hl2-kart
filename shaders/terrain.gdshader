// Displacement-style terrain: WorldVertexTransition blending of HL2 nature
// textures driven by vertex colour (r dirt, g rock, b pavement, a sand).
// The rock layer is triplanar so cliffs are not smeared by the planar (x, z) / 4 UVs; on
// level ground its top projection is exactly the old planar one.
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

varying vec3 world_pos;
varying vec3 world_nrm;

float blend_w(float w, float h) {
	// height-aware transition like $blendmodulatetexture: sharper, textured edges
	return smoothstep(0.35, 0.65, w + (h - 0.5) * 0.5);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
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
	// rock: top projection from the mesh UVs, side projections on the world (z, y) and (x, y)
	// planes at the same texel size, weighted by the sharpened normal
	vec3 n = normalize(world_nrm);
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	vec3 rock = texture(rock_tex, uv * rock_scale).rgb * tw.y;
	vec3 side_n = n * tw.y;
	if (tw.y < 0.999) {
		vec2 uv_x = world_pos.zy * 0.25 * rock_scale;
		vec2 uv_z = world_pos.xy * 0.25 * rock_scale;
		rock += texture(rock_tex, uv_x).rgb * tw.x + texture(rock_tex, uv_z).rgb * tw.z;
		// side normals in world space (UDN blend: map xy added to the face's own axes)
		vec2 nx = texture(rock_normal, uv_x).rg * 2.0 - 1.0;
		vec2 nz = texture(rock_normal, uv_z).rg * 2.0 - 1.0;
		side_n += vec3(n.x, n.y + nx.y, n.z + nx.x) * tw.x + vec3(n.x + nz.x, n.y + nz.y, n.z) * tw.z;
	}
	vec3 c = base;
	c = mix(c, sand, blend_w(w.a, dot(sand, vec3(0.33))));
	c = mix(c, dirt, blend_w(w.r, dot(dirt, vec3(0.33))));
	c = mix(c, pave, blend_w(w.b, dot(pave, vec3(0.33))));
	float rw = blend_w(w.g, dot(rock, vec3(0.33)));
	c = mix(c, rock, rw);
	vec3 d = texture(detail_tex, uv * 4.0).rgb;
	c = mix(c, c * d * 2.0, 0.4);
	ALBEDO = c;
	if (tw.y < 0.999 && rw > 0.0) {
		vec3 bent = normalize(mix(n, normalize(side_n), rw));
		NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	}
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(rock_normal, uv * rock_scale).rgb, rw * tw.y);
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
}
