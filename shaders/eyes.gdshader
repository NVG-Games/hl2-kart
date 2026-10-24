// Source "Eyes": sclera from the mesh UVs, iris projected (UV2 baked by the
// converter from the eyeball origin / iris_scale like the engine does).
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D iris_tex : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec3 sclera = texture(albedo_tex, UV).rgb;
	vec4 iris = texture(iris_tex, UV2);
	float inside = step(0.0, UV2.x) * step(UV2.x, 1.0) * step(0.0, UV2.y) * step(UV2.y, 1.0);
	ALBEDO = mix(sclera, iris.rgb, inside * iris.a);
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
