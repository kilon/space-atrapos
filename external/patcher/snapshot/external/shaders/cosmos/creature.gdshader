// A planet's animal (CosmosCreature): its skin - two colours in its
// species' pattern (0 plain with a paler belly, 1 stripes, 2 spots) from the
// 3D noise in its own space - a soft rim, a flash when it's hit.
shader_type spatial;

uniform vec4 c1 : source_color = vec4(0.5, 0.4, 0.3, 1.0);
uniform vec4 c2 : source_color = vec4(0.8, 0.7, 0.5, 1.0);
uniform int pattern = 0;
uniform float flash = 0.0;
uniform sampler3D noise_tex : filter_linear, repeat_enable;

varying vec3 v_obj;
varying vec3 v_n;

void vertex() {
	v_obj = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
	v_n = NORMAL;
}

void fragment() {
	float n = texture(noise_tex, v_obj * 0.35).r;
	float k;
	if (pattern == 1) {
		k = smoothstep(0.35, 0.65, sin(v_obj.z * 6.0 + n * 6.0) * 0.5 + 0.5);
	} else if (pattern == 2) {
		k = smoothstep(0.58, 0.66, texture(noise_tex, v_obj * 1.1).r);
	} else {
		k = smoothstep(0.1, -0.6, v_n.y) * 0.8;
	}
	vec3 col = mix(c1.rgb, c2.rgb, k) * (0.85 + 0.3 * n);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col + vec3(rim * 0.12);
	ROUGHNESS = 0.8;
	EMISSION = vec3(1.0, 0.25, 0.15) * flash;
}
