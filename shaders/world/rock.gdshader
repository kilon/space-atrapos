// Asteroids in the 3D game (CosmosRocks): each instance tumbling about its own
// axis (INSTANCE_CUSTOM: axis xyz, speed w) by `clock` - set from the script,
// which so knows where each rock's veins are now - its rock grained by the 3D noise.
shader_type spatial;

uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 tone : source_color = vec4(0.42, 0.38, 0.34, 1.0);
uniform float clock = 0.0;

varying vec3 v_obj;

vec3 rot(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	v_obj = VERTEX;
	vec3 k = normalize(INSTANCE_CUSTOM.xyz * 2.0 - 1.0 + vec3(0.001));
	float a = clock * (INSTANCE_CUSTOM.w - 0.5) * 0.6;
	VERTEX = rot(VERTEX, k, a);
	NORMAL = rot(NORMAL, k, a);
}

void fragment() {
	float n = texture(noise_tex, v_obj * 0.9).r * 0.6 + texture(noise_tex, v_obj * 3.3).r * 0.4;
	ALBEDO = tone.rgb * (0.6 + 0.7 * n);
	ROUGHNESS = 0.95;
}
