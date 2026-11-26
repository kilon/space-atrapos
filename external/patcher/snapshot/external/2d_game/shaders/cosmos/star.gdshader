// A star in the 3D game (CosmosStar): its surface boiling (the 3D noise at
// two scales, drifting), hot in the middle and darker at the limb.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 c_dark : source_color = vec4(0.6, 0.2, 0.02, 1.0);
uniform vec4 c_mid : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform vec4 c_hot : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float brightness = 1.6;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 d = normalize(v_obj);
	float t = TIME * 0.02;
	float n = texture(noise_tex, d * 2.0 + vec3(t, 0.0, -t)).r * 0.6 + texture(noise_tex, d * 7.0 - vec3(0.0, t * 2.0, 0.0)).r * 0.4;
	float mu = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 col = mix(c_dark.rgb, c_mid.rgb, smoothstep(0.25, 0.6, n));
	col = mix(col, c_hot.rgb, smoothstep(0.55, 0.8, n) * 0.8 + pow(mu, 3.0) * 0.4);
	ALBEDO = col * brightness * (0.55 + 0.45 * pow(mu, 0.5));
}
