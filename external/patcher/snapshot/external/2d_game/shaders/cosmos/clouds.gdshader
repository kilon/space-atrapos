// A planet's cloud layer (CosmosPlanet): a shell above its mountains, drifting
// - coverage from the 3D noise at two scales, lit by the star, seen from
// above and below.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float cover = 0.5;
uniform float scale = 2.2;
uniform float seed = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler3D noise_tex : filter_linear, repeat_enable;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 up = normalize(v_obj);
	float a = TIME * 0.004;
	vec3 q = vec3(cos(a) * up.x - sin(a) * up.z, up.y, sin(a) * up.x + cos(a) * up.z);
	vec3 p = q * scale * vec3(0.55, 1.0, 0.55) + vec3(seed * 0.013);
	float n = texture(noise_tex, p).r * 0.62 + texture(noise_tex, p * 3.1 + 0.4).r * 0.28 + texture(noise_tex, p * 9.0).r * 0.1;
	float thr = mix(0.7, 0.42, cover);
	float c = smoothstep(thr, thr + 0.16, n);
	float lit = smoothstep(-0.2, 0.4, dot(up, sun_dir));
	ALBEDO = tint.rgb * (0.06 + 0.94 * lit) * (0.85 + 0.3 * n);
	ALPHA = c * 0.92;
}
