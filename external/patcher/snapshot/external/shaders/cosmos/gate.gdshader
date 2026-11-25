// A jump gate's field (CosmosGate): a disc of light swirling inside the ring.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec4 tint : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform sampler3D noise_tex : filter_linear, repeat_enable;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float sw = texture(noise_tex, vec3(cos(a + r * 3.0 - TIME * 0.6), sin(a + r * 3.0 - TIME * 0.6), r * 2.0) * 0.6).r;
	float g = smoothstep(1.0, 0.7, r) * (0.25 + 0.75 * smoothstep(0.4, 0.8, sw)) * (0.4 + 0.6 * r);
	ALBEDO = tint.rgb * g * 0.9;
}
